import Foundation
import NordicSigMeshSDK

/// Repairs local instances, not physical devices. All callers run on the main
/// queue so imports, provisioning completions and upload preparation cannot interleave.
enum SiteDeviceOwnershipReconciler {
    private static var runningSites = Set<String>()

    static func instance(_ node: Node, space: SpaceData) -> SiteDeviceOwnershipPolicy.Instance? {
        guard !node.isProvisioner, !node.isLocalProvisioner,
              node.network?.uuid.uuidString == space.meshUUID, node.subNetworkId == space.meshNetworkId,
              let mac = SiteDeviceOwnershipPolicy.normalizedMAC(node.macAddress) else { return nil }
        return .init(siteId: space.siteId, spaceId: space.id, networkId: space.meshNetworkId,
                     uuid: node.uuid.uuidString, address: node.primaryUnicastAddress,
                     created: node.createdTimestamp, mac: mac)
    }

    static func provisioned(_ node: Node, space: SpaceData) {
        let account = UserData.currentUserId, region = UserData.currentServerRegion
        DispatchQueue.main.async {
            guard account == UserData.currentUserId, region == UserData.currentServerRegion,
                  let identity = instance(node, space: space) else { return }
            // An explicit local provisioning event is later even if the phone
            // clock moved back. Persist an ordered generation for restart/import.
            let otherGenerations = SpaceData.load(siteId: space.siteId).flatMap { candidate in
                (MeshNetwork.load(meshUUID: candidate.meshUUID, subnetworkId: candidate.meshNetworkId)?.nodes ?? []).compactMap { other -> Int64? in
                    guard let otherIdentity = instance(other, space: candidate), otherIdentity.mac == identity.mac,
                          otherIdentity.spaceId != identity.spaceId else { return nil }
                    return otherIdentity.created
                }
            }
            if let latest = otherGenerations.max(), node.createdTimestamp <= latest {
                guard latest < Int64.max else { return }
                node.restoreCreatedTimestamp(latest + 1)
                guard node.save() else { return }
            }
            guard let preferred = instance(node, space: space) else { return }
            let changed = reconcile(siteId: space.siteId, preferred: preferred)
            for old in SpaceData.load(siteId: space.siteId) where changed.contains(old.id) {
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: old), level: .normal)
            }
        }
    }

    @discardableResult
    static func reconcile(siteId: String, preferred: SiteDeviceOwnershipPolicy.Instance? = nil) -> Set<String> {
        guard Thread.isMainThread, !runningSites.contains(siteId) else { return [] }
        runningSites.insert(siteId)
        defer { runningSites.remove(siteId) }
        let spaces = SpaceData.load(siteId: siteId).filter { $0.state == .normal }
        guard needsReconciliation(spaces: spaces) else { return [] }
        let started = Date()
        // Nodes and Groups hold weak network links. Keep every loaded Space
        // alive through identity validation and deletion, not only its loop body.
        var networks: [MeshNetwork] = []
        defer {
            withExtendedLifetime(networks) {}
            #if DEBUG
            print("[SiteDeviceOwnership] site=\(siteId) phase=reconcile spaces=\(spaces.count) elapsed=\(Date().timeIntervalSince(started))")
            #endif
        }
        var records: [(space: SpaceData, node: Node, identity: SiteDeviceOwnershipPolicy.Instance)] = []
        var allNodes: [Node] = []
        var changed = Set<String>()
        for space in spaces {
            guard !SpaceConfigurationSafety.hasPendingImport(space) else { continue }
            let hadCleanup = SpaceConfigurationSafety.hasPendingDeletionCleanup(space)
            if hadCleanup { DevicePermanentDeletionContext.resume(space: space) }
            if hadCleanup && !SpaceConfigurationSafety.hasPendingDeletionCleanup(space) { changed.insert(space.id) }
            guard let network = ProximityLightingTopologyContext.network(for: space) else { continue }
            networks.append(network)
            for node in network.nodes {
                allNodes.append(node)
                if let identity = instance(node, space: space) { records.append((space, node, identity)) }
            }
        }
        var decisions = SiteDeviceOwnershipPolicy.removals(records.map(\.identity), preferred: preferred)
        // A same-second local provisioning decision survives a failed write/restart.
        // Revalidate its exact winner and never let it outrank a newer instance.
        for old in records where !decisions.contains(where: { $0.old == old.identity }) {
            guard let journal = try? SpaceConfigurationSafety.deletionJournal(old.space),
                  let proof = journal.entries.first(where: {
                      $0.stage != .cleaned && $0.nodeUUID == old.identity.uuid && $0.primaryAddress == old.identity.address && $0.replacement != nil
                  })?.replacement,
                  records.contains(where: { $0.identity == proof }),
                  records.filter({ $0.identity.mac == proof.mac }).allSatisfy({ $0.identity.created <= proof.created }) else { continue }
            decisions.append((old.identity, proof))
        }
        for decision in decisions {
            guard let old = records.first(where: { $0.identity == decision.old }),
                  let winner = records.first(where: { $0.identity == decision.winner }),
                  SpaceConfigurationSafety.canAutomaticallyUpload(old.space),
                  SpaceConfigurationSafety.canAutomaticallyUpload(winner.space),
                  let persistedWinner = MeshNetwork.load(meshUUID: winner.space.meshUUID, subnetworkId: winner.space.meshNetworkId),
                  persistedWinner.nodes.contains(where: { instance($0, space: winner.space) == decision.winner }) else { continue }
            // SDK rows are keyed by Site/address. Refuse ambiguous overlapping
            // ranges rather than deleting any part of the retained instance.
            let removedAddresses = ProximityLightingLifecycleCoordinator.topologyAddresses(for: old.node)
            guard allNodes.allSatisfy({ $0 === old.node ||
                removedAddresses.isDisjoint(with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: $0)) }) else {
                #if DEBUG
                print("[SiteDeviceOwnership] site=\(siteId) oldSpace=\(old.space.id) result=blocked reason=overlappingAddresses")
                #endif
                continue
            }
            CloudSynchronizationManager.shared.cancelSynchronizationHandle(space: old.space)
            if DevicePermanentDeletionContext.removeSuperseded(node: old.node, space: old.space, replacement: decision.winner) {
                changed.insert(old.space.id)
                #if DEBUG
                print("[SiteDeviceOwnership] site=\(siteId) oldSpace=\(old.space.id) winnerSpace=\(winner.space.id) oldAddress=\(decision.old.address.hex) winnerAddress=\(decision.winner.address.hex) result=cleaned")
                #endif
            } else {
                SpaceConfigurationSafety.block(old.space, reason: "deletionCleanupPending")
                #if DEBUG
                print("[SiteDeviceOwnership] site=\(siteId) oldSpace=\(old.space.id) result=cleanupPending")
                #endif
            }
        }
        return changed
    }

    /// Do not decode Elements/Models just to discover that nothing needs repair.
    /// Read failures conservatively retain the existing reconciliation path.
    private static func needsReconciliation(spaces: [SpaceData]) -> Bool {
        let spaces = spaces.filter { !SpaceConfigurationSafety.hasPendingImport($0) }
        if spaces.contains(where: { SpaceConfigurationSafety.hasPendingDeletionCleanup($0) }) { return true }
        guard spaces.count > 1 else { return false }
        let started = Date()
        do {
            var identities: [(spaceId: String, mac: String?)] = []
            for meshUUID in Set(spaces.map(\.meshUUID)) {
                let rows = try SiteDeviceOwnershipStore.loadMACs(meshUUID: meshUUID)
                let scopedSpaces = Dictionary(grouping: spaces.filter { $0.meshUUID == meshUUID }, by: \.meshNetworkId)
                for row in rows {
                    for space in scopedSpaces[row.networkId] ?? [] {
                        identities.append((space.id, row.mac))
                    }
                }
            }
            // Include uncommitted live instances without loading another Mesh.
            if let network = MeshNetworkManager.instance.meshNetwork {
                for space in spaces where space.meshUUID == network.uuid.uuidString {
                    identities.append(contentsOf: network.nodes.compactMap { node in
                        guard let identity = instance(node, space: space) else { return nil }
                        return (identity.spaceId, identity.mac)
                    })
                }
            }
            let needed = SiteDeviceOwnershipPolicy.hasCrossSpaceDuplicate(identities)
            #if DEBUG
            print("[SiteDeviceOwnership] phase=preflight spaces=\(spaces.count) identities=\(identities.count) needsRepair=\(needed) elapsed=\(Date().timeIntervalSince(started))")
            #endif
            return needed
        } catch {
            #if DEBUG
            print("[SiteDeviceOwnership] phase=preflight result=unavailable")
            #endif
            return true
        }
    }
}
