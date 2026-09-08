import Foundation
import NordicSigMeshSDK

let deviceDeletionCleanupCompletedNotification = Notification.Name("deviceDeletionCleanupCompleted")

final class DevicePermanentDeletionContext {
    private let node: Node
    private let network: MeshNetwork?
    private let space: SpaceData?
    private let entry: SpaceDeletionJournal.Entry
    private let recoveryContext: SpaceRecoveryState?
    private static var activeEntries = Set<UUID>()
    private(set) var isPrepared = false
    private var didCommit = false

    init(node: Node, space currentSpace: SpaceData? = nil) {
        self.node = node
        network = node.network
        space = currentSpace ?? node.network.flatMap { network in
            SpaceData.load(siteId: network.uuid.uuidString).first { $0.meshNetworkId == node.subNetworkId }
        }
        entry = .init(id: UUID(), nodeUUID: node.uuid.uuidString,
                      primaryAddress: node.primaryUnicastAddress,
                      elementAddresses: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node),
                      macAddress: node.macAddress, productId: node.productIdentifier)
        recoveryContext = space.flatMap { try? SpaceConfigurationSafety.recoveryState($0) }
        prepare()
    }

    private func prepare() {
        guard let space, let network,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              space.meshUUID == network.uuid.uuidString, space.meshNetworkId == node.subNetworkId,
              MeshNetworkManager.instance.meshNetwork === network,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              !SpaceConfigurationSafety.hasPendingImport(space),
              SpaceConfigurationSafety.checkpoint(space,
                refresh: (try? SpaceConfigurationSafety.deletionJournal(space).needsCleanup) == false) else { return }
        isPrepared = SpaceConfigurationSafety.updateDeletionJournal(space) {
            if !$0.entries.contains(where: { $0.id == entry.id }) { $0.entries.append(entry) }
        }
        if isPrepared { Self.activeEntries.insert(entry.id) }
    }

    func cancel() {
        // Reset may already have removed the Node even if a timeout is also
        // reported. Do not discard the only durable evidence of that deletion.
        guard let space, let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              network?.nodes.contains(where: { $0.uuid == node.uuid }) == true else { return }
        if SpaceConfigurationSafety.updateDeletionJournal(space, {
            $0.entries.removeAll { $0.id == entry.id && $0.stage == .prepared }
        }) { isPrepared = false; Self.activeEntries.remove(entry.id) }
    }

    deinit {
        Self.activeEntries.remove(entry.id)
        // An interrupted Reset with an absent Node must remain replayable.
        if let space, let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
           network?.nodes.contains(where: { $0.uuid == node.uuid }) == true {
            _ = SpaceConfigurationSafety.updateDeletionJournal(space) {
                $0.entries.removeAll { $0.id == entry.id && $0.stage == .prepared }
            }
        }
    }

    @discardableResult
    func prepareForForceRemoval() -> Bool {
        if !isPrepared { prepare() }
        return isPrepared
    }

    @discardableResult
    func forceRemove() -> ProximityLightingLifecycleResult? {
        if !isPrepared { prepare() }
        guard isPrepared, let network, let space, let recoveryContext,
              SpaceConfigurationSafety.isCurrent(recoveryContext, space: space) else { return nil }
        network.remove(node: node)
        return commit()
    }

    @discardableResult
    func commit() -> ProximityLightingLifecycleResult? {
        guard isPrepared, !didCommit, let space,
              let recoveryContext, SpaceConfigurationSafety.isCurrent(recoveryContext, space: space),
              network?.nodes.contains(where: { $0.uuid == node.uuid }) == false else { return nil }
        if (try? SpaceConfigurationSafety.deletionJournal(space).entries.first { $0.id == entry.id }?.stage) == .cleaned {
            didCommit = true
            return nil
        }
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) {
                journal.entries[index].stage = .removed
            }
        }) else { return nil }
        let result = Self.complete(entry: entry, space: space)
        didCommit = result != nil
        return result
    }

    /// A prepared intent is confirmed only by absence from its own persisted network.
    static func resume(space: SpaceData) {
        guard !SpaceConfigurationSafety.hasPendingImport(space),
              let journal = try? SpaceConfigurationSafety.deletionJournal(space),
              journal.entries.contains(where: { $0.stage != .cleaned && !activeEntries.contains($0.id) }),
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { return }
        for entry in journal.entries where entry.stage != .cleaned && !activeEntries.contains(entry.id) {
            if persisted.nodes.contains(where: { $0.uuid.uuidString == entry.nodeUUID }) {
                if entry.stage == .prepared {
                    if entry.replacement != nil { continue } // Reconciler retries only after checking the new owner.
                    _ = SpaceConfigurationSafety.updateDeletionJournal(space) {
                        $0.entries.removeAll { $0.id == entry.id }
                    }
                }
                continue
            }
            _ = complete(entry: entry, space: space)
        }
    }

    private static func complete(entry: SpaceDeletionJournal.Entry, space: SpaceData) -> ProximityLightingLifecycleResult? {
        guard !SpaceConfigurationSafety.hasPendingImport(space),
              space.lastUpdate < Int64.max, (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              let network = ProximityLightingTopologyContext.network(for: space),
              !persisted.nodes.contains(where: {
                  $0.uuid.uuidString == entry.nodeUUID || !entry.elementAddresses.isDisjoint(
                    with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: $0))
              }),
              !network.nodes.contains(where: { $0.uuid.uuidString == entry.nodeUUID }) else { return nil }
        guard let journal = try? SpaceConfigurationSafety.deletionJournal(space) else { return nil }
        let removed = journal.entries.filter { candidate in
            candidate.stage != .cleaned && !persisted.nodes.contains { node in
                node.uuid.uuidString == candidate.nodeUUID || !candidate.elementAddresses.isDisjoint(
                    with: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node))
            }
        }
        let addresses = Set(removed.flatMap { $0.elementAddresses })
        guard removed.contains(where: { $0.id == entry.id }) else { return nil }
        var transaction = ProximityLightingLifecycleCoordinator.begin(space: space)
        transaction.removeConfirmedAddresses(addresses)
        let result = ProximityLightingLifecycleCoordinator.commit(
            transaction.prepare(), hasAdditionalLogicalChange: true,
            confirmedDeletionAddresses: addresses,
            applyAdditionalChanges: {
                for removedEntry in removed {
                    try cleanExtensions(entry: removedEntry, space: space, network: network)
                }
                let nodes = ProximityLightingTopologyContext.realNodes(in: network)
                space.deviceCount = nodes.count
                space.luminairesCount = nodes.filter { $0.deviceType == .light }.count
            })
        guard let result,
              let savedSpace = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              let savedNetwork = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
            SpaceConfigurationSafety.block(space, reason: "deletionCleanupPending")
            return nil
        }
        ProximityLightingTopologyContext.loadGroupInfo(network: savedNetwork, space: savedSpace)
        let readback = ProximityLightingLifecycleCoordinator.begin(space: savedSpace,
            groups: savedNetwork.groups.filter { !$0.isVirtual },
            nodes: ProximityLightingTopologyContext.realNodes(in: savedNetwork), network: savedNetwork).prepare()
        guard readback.isValid, readback.normalized.repairs.isEmpty,
              savedNetwork.scenes.allSatisfy({ addresses.isDisjoint(with: $0.addresses) }),
              Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId).allSatisfy({
                  addresses.isDisjoint(with: $0.nodeAddresses) && addresses.isDisjoint(with: $0.needDeleteNodeAddresses)
              }),
              SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                  for index in journal.entries.indices where removed.contains(where: { $0.id == journal.entries[index].id }) {
                      journal.entries[index].stage = .cleaned
                      journal.entries[index].completedTimestamp = space.lastUpdate
                  }
              }) else {
            SpaceConfigurationSafety.block(space, reason: "deletionCleanupPending")
            return nil
        }
        network.nodes.forEach { $0.clearSyncStateCache() }
        let manager = MeshNetworkManager.instance
        if manager.meshNetwork === network, manager.currentNetworkKey.networkId.hex == space.meshNetworkId {
            manager.schedules = Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
            manager.switchs = DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId)
        }
        NotificationCenter.default.post(name: deviceDeletionCleanupCompletedNotification, object: space)
        let datas = network.nodes.compactMap { node -> (node: Node, syncData: NodeSyncData)? in
            guard let data = node.getNodeSyncProximityLighting(topologyPlan: result.plan) else { return nil }
            return (node, data)
        }
        #if DEBUG
        print("[DevicePermanentDeletion] space=\(space.id) node=\(entry.primaryAddress.hex) cleanup=complete proximityTasks=\(datas.count)")
        #endif
        return .init(didChange: result.didChange, plan: result.plan,
                     affectedDeviceAddresses: result.affectedDeviceAddresses,
                     syncDatas: datas, repairs: result.repairs)
    }

    /// Remove a superseded provisioning instance from its own persisted Space.
    /// No Mesh Reset is sent, and the currently connected subnet is never switched.
    @discardableResult
    static func removeSuperseded(node: Node, space: SpaceData,
                                 replacement: SiteDeviceOwnershipPolicy.Instance) -> Bool {
        guard let network = node.network, network.uuid.uuidString == space.meshUUID,
              node.subNetworkId == space.meshNetworkId, replacement.siteId == space.siteId,
              replacement.spaceId != space.id, replacement.address != node.primaryUnicastAddress,
              SiteDeviceOwnershipPolicy.normalizedMAC(node.macAddress) == replacement.mac,
              !SpaceConfigurationSafety.hasPendingImport(space),
              SpaceConfigurationSafety.checkpoint(space, refresh: true) else { return false }
        let existing = try? SpaceConfigurationSafety.deletionJournal(space).entries.first {
            $0.nodeUUID == node.uuid.uuidString && $0.primaryAddress == node.primaryUnicastAddress && $0.replacement != nil && $0.stage != .cleaned
        }
        var intent = existing ?? SpaceDeletionJournal.Entry(id: UUID(), nodeUUID: node.uuid.uuidString,
            primaryAddress: node.primaryUnicastAddress,
            elementAddresses: ProximityLightingLifecycleCoordinator.topologyAddresses(for: node),
            macAddress: node.macAddress, productId: node.productIdentifier)
        intent.replacement = replacement
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            journal.entries.removeAll { $0.id == intent.id }
            journal.entries.append(intent)
        }) else { return false }
        // SDK removal clears Scene element addresses. Persist/read back the Node
        // deletion before committing app-side schedule and topology cleanup.
        guard node.delete() else { return false }
        network.remove(node: node)
        guard let persisted = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              !persisted.nodes.contains(where: { $0.uuid.uuidString == intent.nodeUUID && $0.primaryUnicastAddress == intent.primaryAddress }) else { return false }
        guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
            if let index = journal.entries.firstIndex(where: { $0.id == intent.id }) { journal.entries[index].stage = .removed }
        }) else { return false }
        return complete(entry: intent, space: space) != nil
    }

    private static func cleanExtensions(entry: SpaceDeletionJournal.Entry, space: SpaceData, network: MeshNetwork) throws {
        for scene in network.scenes where !entry.elementAddresses.isDisjoint(with: scene.addresses) {
            for address in entry.elementAddresses {
                while scene.addresses.contains(address) { scene.remove(address: address) }
            }
            guard scene.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
        }
        for schedule in Schedule.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let addresses = entry.elementAddresses.union([entry.primaryAddress])
            let active = schedule.nodeAddresses.filter { !addresses.contains($0) }
            let pending = schedule.needDeleteNodeAddresses.filter { !addresses.contains($0) }
            if active != schedule.nodeAddresses || pending != schedule.needDeleteNodeAddresses {
                schedule.nodeAddresses = active
                schedule.needDeleteNodeAddresses = pending
                guard schedule.save(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) else {
                    throw SpaceConfigurationSafety.SafetyError.persistenceFailed
                }
            }
        }
        for group in network.groups where group.info.ambientLightSensorNodeAddress == entry.primaryAddress {
            group.info.ambientLightSensorNodeAddress = nil
            guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        for item in DeviceSwitchData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) {
            let decision = KineticSwitchBindingPolicy.referenceCleanupDecision(node: entry.primaryAddress,
                current: item.proxyNodeAddress, pendingRemoval: item.deleteProxyNodeAddress)
            guard decision.clearsCurrent || decision.clearsPendingRemoval else { continue }
            if decision.clearsCurrent { item.proxyNodeAddress = nil }
            if decision.clearsCredentials { item.enOceanMacAddress = nil; item.enOceanSecurityKey = nil }
            if decision.clearsPendingRemoval { item.deleteProxyNodeAddress = nil }
            guard item.save(meshUUID: space.meshUUID, networkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }
        // Gateway identity is Site-wide: moving a node must not delete its new owner's association.
        if entry.replacement == nil, let mac = entry.macAddress { GatewayModel.delete(siteId: space.siteId, macAddress: mac) }
        if let productId = entry.productId,
           let distribution = MeshDistributionData.load(meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId, productId: productId),
           distribution.distributionAddress == entry.primaryAddress {
            distribution.delete(meshUUID: space.meshUUID, networkId: space.meshNetworkId, productId: productId)
        }
    }

    static func showCompletion(space: SpaceData) {
        if SpaceConfigurationSafety.hasPendingDeletionCleanup(space) {
            XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
        } else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
        }
    }

    static func showCompletion(contexts: [DevicePermanentDeletionContext]) {
        if contexts.contains(where: { $0.space.map(SpaceConfigurationSafety.hasPendingDeletionCleanup) ?? true }) {
            XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
        } else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
        }
    }
}
