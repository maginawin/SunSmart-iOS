import Foundation
import NordicSigMeshSDK

final class NodeSyncPreparationCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Only values cross the preparation queue. SDK objects stay in the capture's
/// owning queue; a copied [Node] is not a detached topology snapshot.
struct NodeSyncTopologySnapshot {
    struct Device {
        let id: UUID
        let primaryAddress: Address
        let address: Address
        let elementCount: Int
        let groupAddress: Address?
        let subscriptions: Set<Address>
        let exited: Bool
        let evidence: NodeSyncTopologyStorage.NodeEvidence
    }
    struct GroupValue {
        let address: Address
        let eligible: Bool
        let relay: UInt8
        let paths: [[Address?]]
        let zones: [[Address]]
    }
    let meshUUID: String
    let networkID: String
    let groups: [GroupValue]
    let devices: [Device]
    let isAvailable: Bool
    let keys: NodeSyncTopologyStorage.KeyEvidence

    func groupSnapshots() -> [ProximityLightingTopologyPolicy.GroupSnapshot] {
        var members: [Address: Set<Address>] = [:]
        for device in devices where !device.exited {
            for group in device.subscriptions { members[group, default: []].insert(device.address) }
        }
        return groups.filter(\.eligible).map {
            .init(address: $0.address, relayNumber: $0.relay,
                  memberAddresses: members[$0.address] ?? [], paths: $0.paths, zones: $0.zones)
        }
    }
}

/// Incremental live-object access. The cursor advances below Node granularity,
/// including path members, so a large node/group cannot consume an entire slice.
final class NodeSyncTopologyCapture {
    private let network: MeshNetwork
    private let networkID: String
    private let sourceNodes: [Node]
    private let sourceGroups: [Group]
    private var groupIndex = 0, pathIndex = 0, itemIndex = 0, zoneIndex = 0
    private var paths: [[Address?]] = [], zones: [[Address]] = []
    private var groups: [NodeSyncTopologySnapshot.GroupValue] = []
    private var nodeIndex = 0, elementIndex = 0, modelIndex = 0
    private var subscriptions = Set<Address>()
    private var membership: Group?
    private var devices: [NodeSyncTopologySnapshot.Device] = []
    private var available = true
    private(set) var memberships: [ObjectIdentifier: Group] = [:]
    private(set) var groupNodes: [Address: [Node]] = [:]
    private(set) var elementNodes: [Address: Node] = [:]
    private(set) var nodes: [Node] = []
    private(set) var damagedGroups = Set<ObjectIdentifier>()

    init(network: MeshNetwork, networkID: String) {
        self.network = network
        self.networkID = networkID
        sourceNodes = network.nodes
        sourceGroups = network.groups
    }

    func advance(until deadline: TimeInterval) -> Bool {
        precondition(Thread.isMainThread)
        let interval = AppPerformance.begin("SyncTopologyCapture")
        defer { interval.end() }
        repeat {
            if groupIndex < sourceGroups.count {
                captureGroupUnit()
            } else if nodeIndex < sourceNodes.count {
                captureModelUnit()
            } else { return true }
        } while ProcessInfo.processInfo.systemUptime < deadline
        return groupIndex == sourceGroups.count && nodeIndex == sourceNodes.count
    }

    func snapshot() -> NodeSyncTopologySnapshot {
        precondition(Thread.isMainThread)
        return .init(meshUUID: network.uuid.uuidString, networkID: networkID,
                     groups: groups, devices: devices, isAvailable: available,
                     keys: NodeSyncTopologyStorage.keyEvidence(network: network, networkID: networkID))
    }

    private func captureGroupUnit() {
        let group = sourceGroups[groupIndex]
        guard !group.isVirtual else { groupIndex += 1; return }
        guard group.network === network, group.subNetworkId == networkID else {
            available = false; groupIndex += 1; return
        }
        let info = group.info
        if info.profileLoadFailed || info.topologyLoadFailed {
            available = false; damagedGroups.insert(ObjectIdentifier(group))
        }
        let path = info.proximityLightingPath
        if pathIndex < (path?.paths.count ?? 0), let path {
            if paths.count == pathIndex { paths.append([]) }
            if itemIndex < path.paths[pathIndex].items.count {
                paths[pathIndex].append(path.paths[pathIndex].items[itemIndex].address)
                itemIndex += 1
            } else { pathIndex += 1; itemIndex = 0 }
            return
        }
        if zoneIndex < (path?.zones.count ?? 0), let path {
            if zones.count == zoneIndex { zones.append([]) }
            if itemIndex < path.zones[zoneIndex].addresses.count {
                zones[zoneIndex].append(path.zones[zoneIndex].addresses[itemIndex]); itemIndex += 1
            } else { zoneIndex += 1; itemIndex = 0 }
            return
        }
        groups.append(.init(address: group.address.address,
                            eligible: ProximityLightingTopologyPlanner.isEligible(group),
                            relay: info.profile.proximityLightingNumber, paths: paths, zones: zones))
        paths = []; zones = []; pathIndex = 0; itemIndex = 0; zoneIndex = 0; groupIndex += 1
    }

    private func captureModelUnit() {
        let node = sourceNodes[nodeIndex]
        guard !node.isLocalProvisioner && !node.isProvisioner && !node.isConfigComplete else {
            nodeIndex += 1; return
        }
        guard node.network === network, node.subNetworkId == networkID else {
            available = false; nodeIndex += 1; return
        }
        if elementIndex < node.elements.count {
            let element = node.elements[elementIndex]
            elementNodes[element.unicastAddress] = node
            if modelIndex < element.models.count {
                let model = element.models[modelIndex]
                let interval = AppPerformance.begin("SyncSubscriptionCapture")
                let subscribed = model.subscriptions
                interval.end()
                for group in subscribed {
                    subscriptions.insert(group.address.address)
                    if membership == nil && Self.isMembershipGroup(group) { membership = group }
                }
                modelIndex += 1
            } else { elementIndex += 1; modelIndex = 0 }
            return
        }
        let address = ProximityLightingTopologyPlanner.normalizedAddress(for: node)
        devices.append(.init(id: node.uuid, primaryAddress: node.primaryUnicastAddress,
                             address: address, elementCount: node.elements.count,
                             groupAddress: membership?.address.address, subscriptions: subscriptions,
                             exited: node.groupState == .exitFailure,
                             evidence: NodeSyncTopologyStorage.nodeEvidence(node)))
        nodes.append(node)
        if let membership {
            memberships[ObjectIdentifier(node)] = membership
            groupNodes[membership.address.address, default: []].append(node)
        }
        subscriptions = []; membership = nil; elementIndex = 0; modelIndex = 0; nodeIndex += 1
    }

    static func isMembershipGroup(_ group: Group) -> Bool {
        let address = group.address.address
        return address.isGroup && !address.isSpecialGroup && !group.isVirtual
            && address != .meshOTAGroupAddress && address != .localClientGroupAddress
            && address != .subElementBroadcastGroupAddress
    }
}

struct NodeSyncPreparedTopology {
    let groups: [ProximityLightingTopologyPolicy.GroupSnapshot]
    let spaceZones: [ProximityLightingTopologyPolicy.SpaceZoneSnapshot]
    let plan: ProximityLightingTopologyPolicy.Plan
    let site: SiteTriggerZoneTopologyReader.LocalTargetSnapshot
    let isAvailable: Bool

    static var unavailable: Self {
        .init(groups: [], spaceZones: [], plan: .unavailable, site: .unavailable, isAvailable: false)
    }

    func override(groupAddress: Address, nodeAddress: Address) -> ProximityLightingTopologyPolicy.Plan {
        let interval = AppPerformance.begin("SyncTopologyOverride")
        defer { interval.end() }
        let values = groups.map { group -> ProximityLightingTopologyPolicy.GroupSnapshot in
            guard group.address == groupAddress else { return group }
            return .init(address: group.address, relayNumber: group.relayNumber,
                         memberAddresses: group.memberAddresses.union([nodeAddress]), paths: group.paths, zones: group.zones)
        }
        let result = ProximityLightingTopologyPolicy.makePlan(groups: values, spaceZones: spaceZones)
        // The status reader consumes only this node's target. Do not retain one
        // full-space plan for every pending node in a large recovery batch.
        return .init(targets: [nodeAddress: result.target(for: nodeAddress)],
                     capacityViolations: result.capacityViolations.filter { $0.deviceAddress == nodeAddress },
                     isComplete: result.isComplete)
    }
}
