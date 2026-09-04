import Foundation
import NordicSigMeshSDK

let proximityLightingImportSyncNotificationName = "proximityLightingImportSyncNotification"

struct ProximityLightingImportSyncRequest {
    let spaceId: String
    let syncDatas: [(node: Node, syncData: NodeSyncData)]
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

    var hardErrors: [ProximityLightingTopologyReconciler.HardError] {
        return normalized.hardErrors
    }

    var isValid: Bool {
        return normalized.isValid
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
        return begin(
            space: space,
            groups: MeshNetworkManager.instance.groups.filter {
                $0.subNetworkId == space.meshNetworkId && !$0.isVirtual
            },
            nodes: MeshNetworkManager.instance.realNodes
        )
    }

    static func begin(
        space: SpaceData,
        groups: [Group],
        nodes: [Node]
    ) -> ProximityLightingLifecycleTransaction {
        let sourceSnapshot = makeSnapshot(space: space, groups: groups)
        let oldResult = Reconciler.normalize(sourceSnapshot)
        return .init(
            space: space,
            groups: groups,
            nodes: nodes,
            sourceSnapshot: sourceSnapshot,
            oldResult: oldResult,
            draft: sourceSnapshot
        )
    }

    static func commit(
        _ preparation: ProximityLightingLifecyclePreparation,
        allowExistingHardErrors: Bool = false,
        hasAdditionalLogicalChange: Bool = false,
        applyAdditionalChanges: () -> Void = {}
    ) -> ProximityLightingLifecycleResult? {
        guard preparation.isValid
                || (allowExistingHardErrors && preparation.doesNotIntroduceHardErrors) else {
            return nil
        }

        let transaction = preparation.transaction
        let normalized = preparation.normalized
        let topologyChanged = transaction.sourceSnapshot != normalized.snapshot
        let didChange = topologyChanged || hasAdditionalLogicalChange

        if didChange {
            transaction.space.markLocalChangePendingCloudSync()
            applyAdditionalChanges()
            apply(
                normalized.snapshot,
                sourceSnapshot: transaction.sourceSnapshot,
                to: transaction.space,
                groups: transaction.groups
            )
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

    static func makeSnapshot(space: SpaceData) -> Reconciler.Snapshot {
        return makeSnapshot(
            space: space,
            groups: MeshNetworkManager.instance.groups.filter {
                $0.subNetworkId == space.meshNetworkId && !$0.isVirtual
            }
        )
    }

    private static func makeSnapshot(
        space: SpaceData,
        groups: [Group]
    ) -> Reconciler.Snapshot {
        let groupStates = groups
            .sorted { $0.address.address < $1.address.address }
            .map { group -> Reconciler.GroupState in
                let path = group.info.proximityLightingPath
                return .init(
                    address: group.address.address,
                    eligible: ProximityLightingTopologyPlanner.isEligible(group),
                    relayNumber: group.info.profile.proximityLightingNumber,
                    memberAddresses: Set(
                        group.nodes
                            .filter { $0.groupState != .exitFailure }
                            .map { ProximityLightingTopologyPlanner.normalizedAddress(for: $0) }
                    ),
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
    ) {
        let groupsByAddress = Dictionary(
            uniqueKeysWithValues: groups
                .map { ($0.address.address, $0) }
        )
        let sourceGroupsByAddress = Dictionary(
            uniqueKeysWithValues: sourceSnapshot.groups.map { ($0.address, $0) }
        )

        snapshot.groups.forEach { groupState in
            guard let group = groupsByAddress[groupState.address],
                  sourceGroupsByAddress[groupState.address] != groupState else {
                return
            }
            if groupState.hasTopology {
                group.info.proximityLightingPath = makePath(from: groupState)
            } else {
                group.info.proximityLightingPath = nil
            }
            group.info.save()
        }

        let newZones = makeSpaceZones(from: snapshot.spaceZones)
        if !spaceZonesEqual(space.triggerZones, newZones) {
            space.triggerZones = newZones
        }
        space.save()
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
