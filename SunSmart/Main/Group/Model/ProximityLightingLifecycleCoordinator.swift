import Foundation
import NordicSigMeshSDK

let proximityLightingImportSyncNotificationName = "proximityLightingImportSyncNotification"

struct ProximityLightingImportSyncRequest {
    let spaceId: String
    let meshUUID: String
    let networkId: String
}

struct ProximityLightingLifecycleResult {
    let didChange: Bool
    let plan: ProximityLightingTopologyPlanner.Plan
    let affectedDeviceAddresses: Set<Address>
    let syncDatas: [(node: Node, syncData: NodeSyncData)]
    let repairs: [ProximityLightingTopologyReconciler.Repair]
}

struct ProximityLightingLifecyclePreparation {
    let transaction: ProximityLightingLifecycleTransaction
    let normalized: ProximityLightingTopologyReconciler.Result

    var sourceSnapshot: ProximityLightingTopologyReconciler.Snapshot { transaction.sourceSnapshot }

    var hardErrors: [ProximityLightingTopologyReconciler.HardError] {
        return normalized.hardErrors
    }

    var isValid: Bool {
        return transaction.contextAvailable && normalized.isValid
    }

    var doesNotIntroduceHardErrors: Bool {
        return normalized.hardErrors.allSatisfy {
            transaction.oldResult.hardErrors.contains($0)
        }
    }
}

struct ProximityLightingLifecycleTransaction {
    fileprivate let space: SpaceData
    fileprivate let groups: [Group]
    fileprivate let nodes: [Node]
    fileprivate let network: MeshNetwork?
    fileprivate let contextAvailable: Bool
    fileprivate let sourceSnapshot: ProximityLightingTopologyReconciler.Snapshot
    fileprivate let oldResult: ProximityLightingTopologyReconciler.Result
    fileprivate var draft: ProximityLightingTopologyReconciler.Snapshot

    mutating func updateProfile(group: Group, profile: Profile) {
        draft.updateGroup(
            address: group.address.address,
            eligible: ProximityLightingLifecycleCoordinator.isEligible(profile.type),
            relayNumber: profile.proximityLightingNumber
        )
    }

    mutating func updateMembers(group: Group, members: [Node]) {
        draft.updateGroupMembers(
            address: group.address.address,
            members: Set(members.map {
                ProximityLightingTopologyPlanner.normalizedAddress(for: $0)
            })
        )
    }

    mutating func replaceGroupTopology(
        group: Group,
        path: GroupProximityLightingPathData?
    ) {
        draft.replaceGroupTopology(
            address: group.address.address,
            hasTopology: path != nil,
            paths: path?.paths.map { $0.items.map(\.address) } ?? [],
            zones: path?.zones.map(\.addresses) ?? []
        )
    }

    mutating func replaceSpaceZones(_ zones: [SpaceTriggerZone]) {
        draft.spaceZones = ProximityLightingTopologyPlanner.makeSpaceZoneSnapshots(zones)
    }

    mutating func removeGroup(_ group: Group) {
        draft.removeGroup(address: group.address.address)
    }

    mutating func removeNode(_ node: Node) {
        draft.removeNodeAddresses(
            ProximityLightingLifecycleCoordinator.topologyAddresses(for: node)
        )
    }

    mutating func removeConfirmedAddresses(_ addresses: Set<Address>) {
        draft.removeNodeAddresses(addresses)
    }

    mutating func replaceNodeAddress(
        from oldNode: Node,
        to newNode: Node,
        group: Group
    ) {
        draft.replaceNodeAddress(
            from: ProximityLightingTopologyPlanner.normalizedAddress(for: oldNode),
            to: ProximityLightingTopologyPlanner.normalizedAddress(for: newNode),
            owningGroupAddress: group.address.address
        )
    }

    func prepare() -> ProximityLightingLifecyclePreparation {
        return .init(
            transaction: self,
            normalized: ProximityLightingTopologyReconciler.normalize(draft)
        )
    }
}

enum ProximityLightingLifecycleCoordinator {

    typealias Reconciler = ProximityLightingTopologyReconciler

    static func begin(space: SpaceData) -> ProximityLightingLifecycleTransaction {
        let network = ProximityLightingTopologyContext.network(for: space)
        return begin(
            space: space,
            groups: network?.groups.filter { !$0.isVirtual && $0.subNetworkId == space.meshNetworkId } ?? [],
            nodes: network.map { ProximityLightingTopologyContext.realNodes(in: $0) } ?? [],
            network: network
        )
    }

    static func begin(
        space: SpaceData,
        groups: [Group],
        nodes: [Node],
        network: MeshNetwork? = nil
    ) -> ProximityLightingLifecycleTransaction {
        let network = network ?? groups.first?.network ?? nodes.first?.network
        let sourceSnapshot = makeSnapshot(space: space, groups: groups, nodes: nodes)
        let oldResult = Reconciler.normalize(sourceSnapshot)
        return .init(
            space: space,
            groups: groups,
            nodes: nodes,
            network: network,
            contextAvailable: ProximityLightingTopologyContext.isAvailable(
                space: space, network: network, groups: groups, nodes: nodes),
            sourceSnapshot: sourceSnapshot,
            oldResult: oldResult,
            draft: sourceSnapshot
        )
    }

    static func commit(
        _ preparation: ProximityLightingLifecyclePreparation,
        allowExistingHardErrors: Bool = false,
        hasAdditionalLogicalChange: Bool = false,
        isImportApplication: Bool = false,
        confirmedDeletionAddresses: Set<Address>? = nil,
        reviewedReferenceSnapshot: Reconciler.Snapshot? = nil,
        automaticCleanupSnapshot: Reconciler.Snapshot? = nil,
        applyAdditionalChanges: () throws -> Void = {}
    ) -> ProximityLightingLifecycleResult? {
        guard preparation.transaction.contextAvailable else { return nil }
        guard preparation.isValid
                || (allowExistingHardErrors && preparation.doesNotIntroduceHardErrors) else {
            return nil
        }

        let transaction = preparation.transaction
        let normalized = preparation.normalized
        let topologyChanged = transaction.sourceSnapshot != normalized.snapshot
        let didChange = topologyChanged || hasAdditionalLogicalChange
        var isScopedRecovery = false
        if let addresses = confirmedDeletionAddresses {
            var expected = transaction.sourceSnapshot
            expected.removeNodeAddresses(addresses)
            guard !isImportApplication, !addresses.isEmpty,
                  expected == transaction.draft, expected == normalized.snapshot,
                  normalized.isValid else { return nil }
            isScopedRecovery = true
        }
        if let reviewed = reviewedReferenceSnapshot {
            guard !isImportApplication, confirmedDeletionAddresses == nil,
                  reviewed == transaction.sourceSnapshot,
                  normalized.canReviewReferenceRepair else { return nil }
            isScopedRecovery = true
        }
        if let source = automaticCleanupSnapshot {
            guard !isImportApplication, confirmedDeletionAddresses == nil, reviewedReferenceSnapshot == nil,
                  source == transaction.sourceSnapshot, transaction.draft == source,
                  normalized.isValid else { return nil }
            isScopedRecovery = true
        }
        // A server snapshot is authoritative input, never an implicit local edit.
        guard !isImportApplication || !normalized.hasDestructiveRepairs else { return nil }

        guard isImportApplication || ((isScopedRecovery
            ? !SpaceConfigurationSafety.hasPendingImport(transaction.space)
            : !SpaceConfigurationSafety.isBlocked(transaction.space))
            && !transaction.space.triggerZonesLoadFailed
            && transaction.groups.allSatisfy { !$0.info.profileLoadFailed && !$0.info.topologyLoadFailed }
            && SpaceConfigurationSafety.checkpoint(transaction.space)) else { return nil }
        if didChange {
            let space = transaction.space
            let originalZones = space.triggerZones
            let originalTimestamp = space.lastUpdate
            let originals = transaction.groups.map { group in
                (group: group, name: group.name,
                 info: GroupInfo.load(meshUUID: space.meshUUID, address: group.address.address,
                                      subnetworkId: space.meshNetworkId))
            }
            let saved = SunSmartDataManager.shared.configurationTransaction {
                if !isImportApplication {
                    transaction.space.markLocalChangePendingCloudSync()
                }
                try applyAdditionalChanges()
                try apply(
                    normalized.snapshot,
                    sourceSnapshot: transaction.sourceSnapshot,
                    to: transaction.space,
                    groups: transaction.groups
                )
            }
            guard saved else {
                space.triggerZones = originalZones
                space.lastUpdate = originalTimestamp
                for original in originals {
                    if let info = original.info { original.group.info = info }
                    if original.group.name != original.name {
                        original.group.name = original.name
                        original.group.save()
                    }
                    original.group.updateGroupSyncState()
                }
                return nil
            }
        }

        return makeResult(
            transaction: transaction,
            normalized: normalized,
            didChange: didChange,
            clearSyncStateCache: didChange
        )
    }

    static func preview(
        _ preparation: ProximityLightingLifecyclePreparation,
        allowExistingHardErrors: Bool = false
    ) -> ProximityLightingLifecycleResult? {
        guard preparation.transaction.contextAvailable else { return nil }
        guard preparation.isValid
                || (allowExistingHardErrors && preparation.doesNotIntroduceHardErrors) else {
            return nil
        }

        let transaction = preparation.transaction
        let normalized = preparation.normalized
        return makeResult(
            transaction: transaction,
            normalized: normalized,
            didChange: transaction.sourceSnapshot != normalized.snapshot,
            clearSyncStateCache: false
        )
    }

    private static func makeSnapshot(
        space: SpaceData,
        groups: [Group],
        nodes: [Node]
    ) -> Reconciler.Snapshot {
        let groupStates = groups
            .sorted { $0.address.address < $1.address.address }
            .map { group -> Reconciler.GroupState in
                let path = group.info.proximityLightingPath
                return .init(
                    address: group.address.address,
                    eligible: ProximityLightingTopologyPlanner.isEligible(group),
                    relayNumber: group.info.profile.proximityLightingNumber,
                    memberAddresses: ProximityLightingTopologyContext.members(of: group, nodes: nodes),
                    hasTopology: path != nil,
                    paths: path?.paths.map { $0.items.map(\.address) } ?? [],
                    zones: path?.zones.map(\.addresses) ?? []
                )
            }
        return .init(
            groups: groupStates,
            spaceZones: ProximityLightingTopologyPlanner.makeSpaceZoneSnapshots(
                space.triggerZones
            )
        )
    }

    static func topologyAddresses(for node: Node) -> Set<Address> {
        var addresses = Set<Address>()
        addresses.insert(ProximityLightingTopologyPlanner.normalizedAddress(for: node))
        node.elements.forEach { addresses.insert($0.unicastAddress) }
        addresses.insert(node.primaryUnicastAddress)
        return addresses
    }

    static func isEligible(_ profileType: Profile.ProfileType) -> Bool {
        return profileType == .proximityLighting
            || profileType == .proximityLightingWithPhotocell
    }

    static func mergedSyncDatas(
        from results: [ProximityLightingLifecycleResult]
    ) -> [(node: Node, syncData: NodeSyncData)] {
        var byAddress: [Address: (node: Node, syncData: NodeSyncData)] = [:]
        results.forEach { result in
            result.syncDatas.forEach {
                byAddress[$0.node.primaryUnicastAddress] = $0
            }
        }
        return byAddress.values.sorted {
            $0.node.primaryUnicastAddress < $1.node.primaryUnicastAddress
        }
    }

    private static func makeResult(
        transaction: ProximityLightingLifecycleTransaction,
        normalized: Reconciler.Result,
        didChange: Bool,
        clearSyncStateCache: Bool
    ) -> ProximityLightingLifecycleResult {
        let candidateAddresses = Reconciler.candidateDeviceAddresses(
            old: transaction.oldResult,
            new: normalized
        )
        let affectedAddresses = Reconciler.changedDeviceAddresses(
            from: transaction.oldResult.plan,
            to: normalized.plan
        )
        let candidateNodes = makeCandidateNodes(
            addresses: candidateAddresses,
            nodes: transaction.nodes
        )
        let overCapacityAddresses = Set(
            normalized.plan.capacityViolations.map(\.deviceAddress)
        )
        if clearSyncStateCache {
            candidateNodes.forEach { $0.clearSyncStateCache() }
        }
        let syncDatas = makeSyncDatas(
            plan: normalized.plan,
            nodes: candidateNodes.filter {
                !overCapacityAddresses.contains(
                    ProximityLightingTopologyPlanner.normalizedAddress(for: $0)
                )
            }
        )
        return .init(
            didChange: didChange,
            plan: normalized.plan,
            affectedDeviceAddresses: affectedAddresses,
            syncDatas: syncDatas,
            repairs: normalized.repairs
        )
    }

    private static func makeCandidateNodes(
        addresses candidateAddresses: Set<Address>,
        nodes: [Node]
    ) -> [Node] {
        var nodesByPrimaryAddress: [Address: Node] = [:]
        nodes.forEach { node in
            let normalizedAddress = ProximityLightingTopologyPlanner.normalizedAddress(for: node)
            let matchesCandidate = candidateAddresses.contains(normalizedAddress)
                || candidateAddresses.contains(where: { node.contains(elementWithAddress: $0) })
            guard matchesCandidate else {
                return
            }
            nodesByPrimaryAddress[node.primaryUnicastAddress] = node
        }
        return nodesByPrimaryAddress.values.sorted {
            $0.primaryUnicastAddress < $1.primaryUnicastAddress
        }
    }

    private static func makeSyncDatas(
        plan: ProximityLightingTopologyPlanner.Plan,
        nodes: [Node]
    ) -> [(node: Node, syncData: NodeSyncData)] {
        return nodes.compactMap { node in
                guard let syncData = node.getNodeSyncProximityLighting(
                    topologyPlan: plan
                ) else {
                    return nil
                }
                return (node: node, syncData: syncData)
            }
    }

    private static func apply(
        _ snapshot: Reconciler.Snapshot,
        sourceSnapshot: Reconciler.Snapshot,
        to space: SpaceData,
        groups: [Group]
    ) throws {
        let groupsByAddress = Dictionary(
            uniqueKeysWithValues: groups
                .map { ($0.address.address, $0) }
        )
        let sourceGroupsByAddress = Dictionary(
            uniqueKeysWithValues: sourceSnapshot.groups.map { ($0.address, $0) }
        )

        for groupState in snapshot.groups {
            guard let group = groupsByAddress[groupState.address],
                  sourceGroupsByAddress[groupState.address] != groupState else {
                continue
            }
            if groupState.hasTopology {
                group.info.proximityLightingPath = makePath(from: groupState)
            } else {
                group.info.proximityLightingPath = nil
            }
            guard group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                throw SpaceConfigurationSafety.SafetyError.persistenceFailed
            }
        }

        let newZones = makeSpaceZones(from: snapshot.spaceZones)
        if !spaceZonesEqual(space.triggerZones, newZones) {
            space.triggerZones = newZones
        }
        guard space.save() else { throw SpaceConfigurationSafety.SafetyError.persistenceFailed }
    }

    private static func makePath(
        from groupState: Reconciler.GroupState
    ) -> GroupProximityLightingPathData {
        return .init(
            paths: groupState.paths.map { addresses in
                .init(
                    items: addresses.map {
                        .init(address: $0)
                    }
                )
            },
            zones: groupState.zones.map {
                .init(addresses: $0)
            }
        )
    }

    private static func makeSpaceZones(
        from snapshots: [ProximityLightingTopologyPolicy.SpaceZoneSnapshot]
    ) -> [SpaceTriggerZone] {
        return snapshots.map { snapshot in
            .init(
                items: snapshot.members.map {
                    .init(
                        groupAddress: $0.groupAddress,
                        deviceAddress: $0.deviceAddress
                    )
                }
            )
        }
    }

    private static func spaceZonesEqual(
        _ lhs: [SpaceTriggerZone],
        _ rhs: [SpaceTriggerZone]
    ) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { $0 == $1 }
    }
}
