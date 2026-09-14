import Foundation

/// A read-only Site projection. Mesh addresses are resolved only after stable node identities
/// and the complete set of Space snapshots have been checked.
enum SiteTriggerZoneTopologyPolicy {
    typealias DeviceID = SiteTriggerZoneMember.Identity

    enum KeyEvidence: Equatable {
        case present
        case absent
        case unknown
    }

    enum ForwardKey: Equatable {
        case space
        case primary
    }

    struct KeyReference: Equatable, Hashable {
        let networkIndex: UInt16
        let applicationIndex: UInt16
        /// Digest of the resolved Key pair; never print the component Key values.
        let materialIdentity: String?

        init(networkIndex: UInt16, applicationIndex: UInt16,
             materialIdentity: String? = nil) {
            self.networkIndex = networkIndex
            self.applicationIndex = applicationIndex
            self.materialIdentity = materialIdentity
        }
    }

    enum Source: Hashable {
        case local(ProximityLightingTopologyPolicy.Source)
        case siteZone(UUID)
        case spacePrimaryDueToZone(UUID)
        case retainedPrimarySpace
        case unattributedPreviousState
    }

    enum PrimaryPreparation: Equatable {
        case notNeeded
        case ready
        case installOrBind
        case unknown
    }

    struct NodeSnapshot {
        let id: DeviceID
        let primaryAddress: UInt16
        let address: UInt16
        let groupAddress: UInt16?
        let primaryNetKey: KeyEvidence
        let primaryAppKey: KeyEvidence
        let primaryModelBind: KeyEvidence
    }

    struct SpaceSnapshot {
        let id: String
        let meshUUID: UUID
        let nodes: [NodeSnapshot]
        /// Read-only plans may still be shown; device writes require permission.
        var canConfigure = true
        let spaceKey: KeyReference?
        let primaryKey: KeyReference?
        /// Nil until the 3A physical test establishes the forwarding TTL.
        let targetTTL: UInt8?
        /// Existing Group Path, Group Trigger Zone, and Space Trigger Zone target.
        let localPlan: ProximityLightingTopologyPolicy.Plan
    }

    struct Target: Equatable {
        let address: UInt16
        let enabled: Bool
        let relayNumber: UInt8?
        let neighborAddresses: [UInt16]
        let forwardKey: ForwardKey
        let forwardKeyReference: KeyReference?
        let ttl: UInt8?
        let primaryPreparation: PrimaryPreparation
    }

    enum Issue: Hashable {
        case duplicateSpace(String)
        case inconsistentMesh(String)
        case incompleteSpace(String)
        case duplicateDevice(DeviceID)
        case duplicateAddress(UInt16)
        case unresolvedLocalAddress(String, UInt16)
        case invalidMember(UUID, DeviceID)
        case duplicateMember(UUID, DeviceID)
        case unknownPrimaryEvidence(String)
        case missingSpaceKey(String)
        case missingPrimaryKey(String)
        case unknownTargetTTL(String)
        case insufficientPermission(String)
        case unknownDevicePreparation(DeviceID)
        case capacity(DeviceID, Int)
    }

    struct Plan {
        let targets: [DeviceID: Target]
        /// Attribution is separate from Target equality: a second Zone can
        /// share an existing edge without creating a redundant device write.
        let sourcesByDevice: [DeviceID: Set<Source>]
        /// Exact provenance of each directed neighbor relationship.
        let neighborSourcesByDevice: [DeviceID: [UInt16: Set<Source>]]
        let primarySpaceIDs: Set<String>
        let issues: Set<Issue>

        var isComplete: Bool { issues.isEmpty }
        /// Key/TTL and device preparation gaps block execution but do not
        /// invalidate a tentative, read-only neighbor diff.
        var canPreviewTasks: Bool {
            issues.allSatisfy {
                switch $0 {
                case .missingSpaceKey, .missingPrimaryKey, .unknownTargetTTL,
                     .unknownDevicePreparation, .insufficientPermission:
                    return true
                default:
                    return false
                }
            }
        }
    }

    static func confirmedZones(from state: SiteTriggerZoneState) -> [SiteTriggerZone]? {
        guard state.pending == nil, !state.conflict, !state.hasAmbiguousRemote,
              state.rejectedRemote == nil,
              let serverData = state.serverData, serverData == state.data,
              serverData.supportsMemberEditing else { return nil }
        return serverData.zones
    }

    static func makePlan(
        spaces: [SpaceSnapshot],
        zones: [SiteTriggerZone]
    ) -> Plan {
        var issues = Set<Issue>()
        var nodesByID: [DeviceID: NodeSnapshot] = [:]
        var nodesByAddress: [UInt16: DeviceID] = [:]
        var localTargets: [DeviceID: ProximityLightingTopologyPolicy.Target] = [:]
        var sourcesByDevice: [DeviceID: Set<Source>] = [:]
        var neighborSourcesByDevice: [DeviceID: [UInt16: Set<Source>]] = [:]
        var neighborIDs: [DeviceID: Set<DeviceID>] = [:]
        var snapshotsBySpace: [String: SpaceSnapshot] = [:]
        var seenSpaces = Set<String>()
        let siteMesh = spaces.first?.meshUUID

        for space in spaces {
            if !seenSpaces.insert(space.id).inserted { issues.insert(.duplicateSpace(space.id)) }
            snapshotsBySpace[space.id] = space
            if space.meshUUID != siteMesh { issues.insert(.inconsistentMesh(space.id)) }
            if !space.canConfigure { issues.insert(.insufficientPermission(space.id)) }
            if space.spaceKey?.materialIdentity?.isEmpty != false {
                issues.insert(.missingSpaceKey(space.id))
            }
            if space.primaryKey?.materialIdentity?.isEmpty != false {
                issues.insert(.missingPrimaryKey(space.id))
            }
            if space.targetTTL == nil && space.localPlan.targets.values.contains(where: \.enabled) {
                issues.insert(.unknownTargetTTL(space.id))
            }
            if !space.localPlan.isComplete || space.localPlan.hasCapacityViolation {
                issues.insert(.incompleteSpace(space.id))
            }
            for node in space.nodes {
                if node.id.spaceID != space.id || nodesByID.updateValue(node, forKey: node.id) != nil {
                    issues.insert(.duplicateDevice(node.id))
                }
                if nodesByAddress.updateValue(node.id, forKey: node.address) != nil {
                    issues.insert(.duplicateAddress(node.address))
                }
            }
        }

        for space in spaces {
            let nodesByLocalAddress = Dictionary(grouping: space.nodes, by: \.address)
            for (address, target) in space.localPlan.targets {
                guard let node = nodesByLocalAddress[address]?.only else {
                    issues.insert(.unresolvedLocalAddress(space.id, address))
                    continue
                }
                localTargets[node.id] = target
                sourcesByDevice[node.id, default: []].formUnion(
                    (space.localPlan.sourcesByAddress[address] ?? []).map(Source.local)
                )
                for neighborAddress in target.neighborAddresses {
                    guard let neighbor = nodesByLocalAddress[neighborAddress]?.only else {
                        issues.insert(.unresolvedLocalAddress(space.id, neighborAddress))
                        continue
                    }
                    if neighbor.id != node.id {
                        neighborIDs[node.id, default: []].insert(neighbor.id)
                        neighborSourcesByDevice[node.id, default: [:]][neighbor.address, default: []]
                            .formUnion((space.localPlan.neighborSourcesByAddress[address]?[neighborAddress] ?? [])
                                .map(Source.local))
                    }
                }
            }
        }

        var siteSpaceIDs = Set<String>()
        var zoneIDsBySpace: [String: Set<UUID>] = [:]
        for zone in zones {
            guard let members = zone.members else {
                issues.insert(.incompleteSpace("site-zone-\(zone.zoneId.uuidString)"))
                continue
            }
            var seenMembers = Set<DeviceID>()
            var validIDs: [DeviceID] = []
            var valid = true
            for member in members {
                let id = member.identity
                if !seenMembers.insert(id).inserted {
                    issues.insert(.duplicateMember(zone.zoneId, id))
                    valid = false
                    continue
                }
                guard let node = nodesByID[id], let localTarget = localTargets[id],
                      localTarget.enabled, node.groupAddress == member.groupAddress,
                      node.primaryAddress == member.primaryAddress,
                      node.address == member.deviceAddress else {
                    issues.insert(.invalidMember(zone.zoneId, id))
                    valid = false
                    continue
                }
                validIDs.append(id)
            }
            guard valid else { continue }
            siteSpaceIDs.formUnion(validIDs.map(\.spaceID))
            for id in validIDs {
                zoneIDsBySpace[id.spaceID, default: []].insert(zone.zoneId)
                sourcesByDevice[id, default: []].insert(.siteZone(zone.zoneId))
                neighborIDs[id, default: []].formUnion(validIDs.filter { $0 != id })
                for neighborID in validIDs where neighborID != id {
                    if let address = nodesByID[neighborID]?.address {
                        neighborSourcesByDevice[id, default: [:]][address, default: []]
                            .insert(.siteZone(zone.zoneId))
                    }
                }
            }
        }

        var primarySpaces = siteSpaceIDs
        for space in spaces {
            if space.nodes.contains(where: { $0.primaryAppKey == .present }) {
                primarySpaces.insert(space.id)
            } else if !siteSpaceIDs.contains(space.id),
                      space.nodes.contains(where: { $0.primaryAppKey == .unknown }) {
                issues.insert(.unknownPrimaryEvidence(space.id))
            }
        }

        var targets: [DeviceID: Target] = [:]
        for (id, localTarget) in localTargets {
            guard let node = nodesByID[id], let space = snapshotsBySpace[id.spaceID] else { continue }
            let neighbors = Array(neighborIDs[id] ?? []).compactMap { nodesByID[$0]?.address }.sorted()
            if neighbors.count > ProximityLightingTopologyPolicy.maximumNeighborCount {
                issues.insert(.capacity(id, neighbors.count))
            }
            let usesPrimary = primarySpaces.contains(id.spaceID)
            if usesPrimary {
                let zoneIDs = zoneIDsBySpace[id.spaceID] ?? []
                if zoneIDs.isEmpty {
                    sourcesByDevice[id, default: []].insert(.retainedPrimarySpace)
                } else {
                    sourcesByDevice[id, default: []].formUnion(
                        zoneIDs.map(Source.spacePrimaryDueToZone)
                    )
                }
            }
            let preparation: PrimaryPreparation
            if !usesPrimary {
                preparation = .notNeeded
            } else if node.primaryNetKey == .unknown || node.primaryAppKey == .unknown
                        || node.primaryModelBind == .unknown {
                preparation = .unknown
                issues.insert(.unknownDevicePreparation(id))
            } else if node.primaryNetKey == .present && node.primaryAppKey == .present
                        && node.primaryModelBind == .present {
                preparation = .ready
            } else {
                preparation = .installOrBind
            }
            targets[id] = Target(
                address: node.address,
                enabled: localTarget.enabled,
                relayNumber: localTarget.relayNumber,
                neighborAddresses: neighbors,
                forwardKey: usesPrimary ? .primary : .space,
                forwardKeyReference: usesPrimary ? space.primaryKey : space.spaceKey,
                ttl: space.targetTTL,
                primaryPreparation: preparation
            )
        }
        return Plan(targets: targets, sourcesByDevice: sourcesByDevice,
                    neighborSourcesByDevice: neighborSourcesByDevice,
                    primarySpaceIDs: primarySpaces, issues: issues)
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
