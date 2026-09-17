import Foundation
import CryptoKit

/// Read-only task preview from a complete server target and either a prior target
/// or Node observations. Transport commands and durable receipts are outside this policy.
enum SiteTriggerZoneSyncPlanningPolicy {
    typealias DeviceID = SiteTriggerZoneMember.Identity
    typealias Topology = SiteTriggerZoneTopologyPolicy

    enum Kind: Hashable { case remove, configuration }
    enum ConfigurationChange: Equatable { case add, update }

    enum PreviousTargetError: Error, Equatable {
        case duplicateChange(UUID)
        case staleTarget(UUID)
        case invalidPreviousMembers(UUID)
    }

    /// Restore the earliest retained membership for every changed Zone while
    /// keeping all other confirmed Zones. The resolver normalizes legacy
    /// trigger-element fields against the same verified Node inventory.
    static func reconstructPreviousZones(
        confirmedZones: [SiteTriggerZone],
        changes: [SiteTriggerZoneDeviceSyncChange],
        resolve: (SiteTriggerZone) -> [SiteTriggerZoneMember]?
    ) -> Result<[SiteTriggerZone], PreviousTargetError> {
        var previousZones = confirmedZones
        var seen = Set<UUID>()
        for change in changes {
            guard seen.insert(change.zoneID).inserted else {
                return .failure(.duplicateChange(change.zoneID))
            }
            guard case .array = change.previousMembers,
                  case .array = change.targetMembers else {
                return .failure(.invalidPreviousMembers(change.zoneID))
            }
            let current = confirmedZones.first { $0.zoneId == change.zoneID }
            guard (current?.fields["members"] ?? .array([])) == change.targetMembers else {
                return .failure(.staleTarget(change.zoneID))
            }
            let previousBase: SiteTriggerZone
            if let current {
                previousBase = current
            } else {
                guard let deleted = SiteTriggerZone(value: .object([
                    "zoneId": .string(change.zoneID.uuidString),
                    "members": change.previousMembers
                ])) else { return .failure(.invalidPreviousMembers(change.zoneID)) }
                previousBase = deleted
            }
            var previous = previousBase
            previous.fields["members"] = change.previousMembers
            guard let members = resolve(previous) else {
                return .failure(.invalidPreviousMembers(change.zoneID))
            }
            previous.replaceMembers(members)
            if let index = previousZones.firstIndex(where: { $0.zoneId == change.zoneID }) {
                previousZones[index] = previous
            } else {
                previousZones.append(previous)
            }
        }
        return .success(previousZones)
    }

    struct Task: Equatable {
        let deviceID: DeviceID
        let kind: Kind
        /// Obsolete edges only. Other Group Path/Zone edges remain in target.
        let removedNeighbors: [UInt16]
        let target: Topology.Target?
        let configurationChange: ConfigurationChange?
        let sources: Set<Topology.Source>
        /// Provenance of edges actually added or removed by this task.
        let relationshipSources: Set<Topology.Source>

        init(deviceID: DeviceID, kind: Kind, removedNeighbors: [UInt16],
             target: Topology.Target?, configurationChange: ConfigurationChange? = nil,
             sources: Set<Topology.Source> = [],
             relationshipSources: Set<Topology.Source> = []) {
            self.deviceID = deviceID
            self.kind = kind
            self.removedNeighbors = removedNeighbors
            self.target = target
            self.configurationChange = configurationChange
            self.sources = sources
            self.relationshipSources = relationshipSources
        }
    }

    struct SpaceTasks {
        let spaceID: String
        let remove: [Task]
        let configuration: [Task]
        /// Read-only Space AppKey candidate for sending vendor commands. This
        /// is separate from each target's forwarding Key and is not a session
        /// or Model Bind verification.
        let transportKeyCandidate: Topology.KeyReference?

        init(spaceID: String, remove: [Task], configuration: [Task],
             transportKeyCandidate: Topology.KeyReference? = nil) {
            self.spaceID = spaceID
            self.remove = remove
            self.configuration = configuration
            self.transportKeyCandidate = transportKeyCandidate
        }
    }

    enum Issue: Hashable {
        case incompleteTopology
        case topology(Topology.Issue)
        case invalidMembers(UUID)
        case invalidPreviousMembers(UUID)
        case missingSpaceOrder(String)
        case duplicateSpaceOrder(String)
        case duplicateObservation(DeviceID)
        case missingObservation(DeviceID)
        case unverifiedObservation(DeviceID)
        case addressMismatch(DeviceID)
        case missingObservedState(DeviceID)
        case missingObservedNeighbors(DeviceID)
        case orphanObservation(DeviceID)
        case requiresDeviceReconciliation(DeviceID)
    }

    enum Blocker: String, CaseIterable, Hashable {
        case cloud, schema, permission, mesh, keys, ttl, preparation, capacity
        case addresses, members, topology, observations, reconciliation, previousTarget
    }

    static func blockers(for issues: Set<Issue>) -> [Blocker] {
        let kinds = Set(issues.map { issue -> Blocker in
            switch issue {
            case .incompleteTopology, .missingSpaceOrder, .duplicateSpaceOrder:
                return .topology
            case .invalidMembers, .invalidPreviousMembers:
                return .members
            case .duplicateObservation, .missingObservation, .unverifiedObservation,
                 .addressMismatch, .missingObservedState, .missingObservedNeighbors,
                 .orphanObservation:
                return .observations
            case .requiresDeviceReconciliation:
                return .reconciliation
            case .topology(let reason):
                switch reason {
                case .duplicateSpace, .inconsistentMesh: return .mesh
                case .incompleteSpace: return .topology
                case .duplicateDevice, .duplicateAddress, .unresolvedLocalAddress:
                    return .addresses
                case .invalidMember, .duplicateMember: return .members
                case .unknownPrimaryEvidence, .unknownDevicePreparation: return .preparation
                case .missingSpaceKey, .missingPrimaryKey: return .keys
                case .unknownTargetTTL: return .ttl
                case .insufficientPermission: return .permission
                case .capacity: return .capacity
                }
            }
        })
        return Blocker.allCases.filter(kinds.contains)
    }

    /// A cache-only snapshot can suggest tasks, but cannot confirm completion or
    /// authorize commands. Forwarding AppKey and TTL require separate evidence.
    struct Observation {
        enum Evidence { case cache, verified }
        let deviceID: DeviceID
        let address: UInt16
        let enabled: Bool?
        let relayNumber: UInt8?
        let neighborAddresses: [UInt16]?
        let forwardKey: Topology.ForwardKey?
        let forwardKeyReference: Topology.KeyReference?
        let ttl: UInt8?
        let evidence: Evidence

        init(deviceID: DeviceID, address: UInt16, enabled: Bool?, relayNumber: UInt8?,
             neighborAddresses: [UInt16]?, forwardKey: Topology.ForwardKey?, ttl: UInt8?,
             evidence: Evidence, forwardKeyReference: Topology.KeyReference? = nil) {
            self.deviceID = deviceID
            self.address = address
            self.enabled = enabled
            self.relayNumber = relayNumber
            self.neighborAddresses = neighborAddresses
            self.forwardKey = forwardKey
            self.forwardKeyReference = forwardKeyReference
            self.ttl = ttl
            self.evidence = evidence
        }
    }

    struct Plan {
        let spaces: [SpaceTasks]
        let issues: Set<Issue>
        /// Stable digest of the entire executable Site target, not a receipt.
        let targetFingerprint: String?

        init(spaces: [SpaceTasks], issues: Set<Issue>, targetFingerprint: String? = nil) {
            self.spaces = spaces
            self.issues = issues
            self.targetFingerprint = targetFingerprint
        }

        var isComplete: Bool { issues.isEmpty }
        var taskCount: Int { spaces.reduce(0) { $0 + $1.remove.count + $1.configuration.count } }
        var blockers: [Blocker] { SiteTriggerZoneSyncPlanningPolicy.blockers(for: issues) }
    }

    /// Attach a potential transport Key without changing device-target
    /// equality or its fingerprint. The active Mesh session and the device's
    /// Vendor Model Bind still require 3A evidence before any send.
    static func withTransportCandidates(_ plan: Plan,
                                        spaces: [Topology.SpaceSnapshot]) -> Plan {
        var issues = plan.issues
        let tasks = plan.spaces.map { space -> SpaceTasks in
            let matches = spaces.filter { $0.id == space.spaceID }
            let key = matches.count == 1 ? matches[0].spaceKey : nil
            if key?.materialIdentity?.isEmpty != false {
                issues.insert(.topology(.missingSpaceKey(space.spaceID)))
            }
            return .init(spaceID: space.spaceID, remove: space.remove,
                         configuration: space.configuration,
                         transportKeyCandidate: key)
        }
        return .init(spaces: tasks, issues: issues,
                     targetFingerprint: plan.targetFingerprint)
    }

    struct AttributedTask {
        let spaceID: String
        let task: Task
    }

    struct Attribution {
        let directByZone: [UUID: [AttributedTask]]
        let sharedByZone: [UUID: [AttributedTask]]
        /// Includes cleanup for deleted Zones, even when a live Zone shares a Node.
        let siteLevel: [AttributedTask]
    }

    /// Direct means this task changes an edge from the Zone. Shared means the
    /// Zone participates on the same device or Space, without claiming that
    /// its own membership change caused the write.
    static func attributeTasks(_ plan: Plan, liveZoneIDs: Set<UUID>) -> Attribution {
        var directByZone: [UUID: [AttributedTask]] = [:]
        var sharedByZone: [UUID: [AttributedTask]] = [:]
        var siteLevel: [AttributedTask] = []
        for space in plan.spaces {
            for task in space.remove + space.configuration {
                let entry = AttributedTask(spaceID: space.spaceID, task: task)
                let relationshipZones = Set(task.relationshipSources.compactMap { source -> UUID? in
                    guard case .siteZone(let id) = source else { return nil }
                    return id
                })
                let participantZones = Set(task.sources.compactMap { source -> UUID? in
                    switch source {
                    case .siteZone(let id), .spacePrimaryDueToZone(let id): return id
                    default: return nil
                    }
                })
                let direct = relationshipZones.intersection(liveZoneIDs)
                let shared = participantZones.intersection(liveZoneIDs).subtracting(direct)
                for id in direct { directByZone[id, default: []].append(entry) }
                for id in shared { sharedByZone[id, default: []].append(entry) }
                if !relationshipZones.subtracting(liveZoneIDs).isEmpty
                    || direct.isEmpty && shared.isEmpty {
                    siteLevel.append(entry)
                }
            }
        }
        return .init(directByZone: directByZone, sharedByZone: sharedByZone,
                     siteLevel: siteLevel)
    }

    static func hasDeletedZoneCleanup(confirmedZones: [SiteTriggerZone],
                                      changes: [SiteTriggerZoneDeviceSyncChange]) -> Bool {
        let liveIDs = Set(confirmedZones.map(\.zoneId))
        return changes.contains { !liveIDs.contains($0.zoneID) && $0.hasKnownDeviceDelta }
    }

    /// A narrow proof that retained Zone edits add/remove only relationship
    /// sources. Every affected member must already belong to one unchanged
    /// covering Zone, so both directed edges and Space Primary selection stay
    /// the same. This does not prove the physical target is installed.
    static func allRetainedChangesAreSourceOnly(
        confirmedZones: [SiteTriggerZone], changes: [SiteTriggerZoneDeviceSyncChange]
    ) -> Bool {
        guard !changes.isEmpty else { return false }
        let changedIDs = Set(changes.map(\.zoneID))
        guard changedIDs.count == changes.count,
              Set(confirmedZones.map(\.zoneId)).count == confirmedZones.count else { return false }
        let stableZones = confirmedZones.filter { !changedIDs.contains($0.zoneId) }
        let covers = stableZones.compactMap { zone -> Set<RelationMember>? in
            guard let members = zone.members else { return nil }
            let values = members.compactMap(RelationMember.init)
            return values.count == members.count ? Set(values) : nil
        }
        for change in changes {
            let currentMembers = confirmedZones.first(where: { $0.zoneId == change.zoneID })?
                .fields["members"] ?? .array([])
            guard currentMembers == change.targetMembers,
                  let previous = relationMembers(change.previousMembers),
                  let target = relationMembers(change.targetMembers) else { return false }
            let affected = previous.union(target)
            guard covers.contains(where: { affected.isSubset(of: $0) }) else { return false }
        }
        return true
    }

    private struct RelationMember: Hashable {
        let identity: DeviceID
        let groupAddress: UInt16
        let primaryAddress: UInt16
        let deviceAddress: UInt16

        init?(_ member: SiteTriggerZoneMember) {
            guard let groupAddress = member.groupAddress,
                  let primaryAddress = member.primaryAddress,
                  let deviceAddress = member.deviceAddress else { return nil }
            identity = member.identity
            self.groupAddress = groupAddress
            self.primaryAddress = primaryAddress
            self.deviceAddress = deviceAddress
        }
    }

    private static func relationMembers(_ value: SiteJSONValue) -> Set<RelationMember>? {
        guard case .array(let values) = value else { return nil }
        let members = values.compactMap(SiteTriggerZoneMember.init(value:))
        guard members.count == values.count,
              Set(members.map(\.identity)).count == members.count else { return nil }
        let relations = members.compactMap(RelationMember.init)
        return relations.count == members.count ? Set(relations) : nil
    }

    /// Source attribution and observed Key/Bind preparation are deliberately
    /// excluded: neither changes the desired device configuration. A missing
    /// forwarding Key or TTL cannot be given an executable target identity.
    static func targetFingerprint(siteID: String, topology: Topology.Plan) -> String? {
        guard !siteID.isEmpty, topology.canPreviewTasks else { return nil }
        let targets: [FingerprintTarget] = topology.targets.compactMap { id, target in
            guard !target.enabled || target.forwardKeyReference?.materialIdentity?.isEmpty == false
                && target.ttl != nil else {
                return nil
            }
            return FingerprintTarget(
                spaceID: UUID(uuidString: id.spaceID)?.uuidString ?? id.spaceID,
                nodeUUID: id.nodeUUID.uuidString,
                address: target.address, enabled: target.enabled,
                relayNumber: target.relayNumber,
                neighbors: target.neighborAddresses.sorted(),
                forwardKey: target.forwardKey == .primary ? "primary" : "space",
                networkKeyIndex: target.forwardKeyReference?.networkIndex,
                applicationKeyIndex: target.forwardKeyReference?.applicationIndex,
                keyMaterialIdentity: target.forwardKeyReference?.materialIdentity,
                ttl: target.ttl
            )
        }.sorted {
            ($0.spaceID, $0.nodeUUID) < ($1.spaceID, $1.nodeUUID)
        }
        guard targets.count == topology.targets.count,
              Set(targets.map { "\($0.spaceID)/\($0.nodeUUID)" }).count == targets.count else {
            return nil
        }
        return digest(FingerprintInput(
            version: 1, siteID: UUID(uuidString: siteID)?.uuidString ?? siteID,
            targets: targets))
    }

    /// A cloud-content identity remains available while hardware-only TTL or
    /// Key evidence prevents an executable device target fingerprint.
    static func cloudFingerprint(siteID: String, data: SiteExtensionData) -> String? {
        guard !siteID.isEmpty else { return nil }
        return digest(CloudFingerprintInput(
            version: 1, siteID: UUID(uuidString: siteID)?.uuidString ?? siteID,
            extensionData: data))
    }

    private static func digest<Value: Encodable>(_ value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct FingerprintInput: Encodable {
        let version: Int
        let siteID: String
        let targets: [FingerprintTarget]
    }

    private struct CloudFingerprintInput: Encodable {
        let version: Int
        let siteID: String
        let extensionData: SiteExtensionData
    }

    private struct FingerprintTarget: Encodable {
        let spaceID: String
        let nodeUUID: String
        let address: UInt16
        let enabled: Bool
        let relayNumber: UInt8?
        let neighbors: [UInt16]
        let forwardKey: String
        let networkKeyIndex: UInt16?
        let applicationKeyIndex: UInt16?
        let keyMaterialIdentity: String?
        let ttl: UInt8?
    }

    /// Reconcile a complete server target with observed Node state. Unknown or
    /// cache-only fields remain explicit issues while tentative tasks are shown.
    static func makeRecoveryPlan(target: Topology.Plan,
                                 observations: [Observation],
                                 siteSpaceOrder: [String]) -> Plan {
        guard target.canPreviewTasks else {
            return .init(spaces: [], issues: Set(target.issues.map(Issue.topology)))
        }
        var issues = Set(target.issues.map(Issue.topology))
        var byID: [DeviceID: Observation] = [:]
        for observation in observations {
            if byID.updateValue(observation, forKey: observation.deviceID) != nil {
                issues.insert(.duplicateObservation(observation.deviceID))
            }
        }
        var order: [String] = []
        for spaceID in siteSpaceOrder {
            if order.contains(spaceID) { issues.insert(.duplicateSpaceOrder(spaceID)) }
            else { order.append(spaceID) }
        }
        var removeBySpace: [String: [Task]] = [:]
        var configurationBySpace: [String: [Task]] = [:]
        for (id, desired) in target.targets {
            guard order.contains(id.spaceID) else {
                issues.insert(.missingSpaceOrder(id.spaceID))
                continue
            }
            guard let observed = byID.removeValue(forKey: id) else {
                issues.insert(.missingObservation(id))
                continue
            }
            guard observed.address == desired.address else {
                issues.insert(.addressMismatch(id))
                continue
            }
            if observed.evidence == .cache { issues.insert(.unverifiedObservation(id)) }
            if observed.enabled == nil || desired.enabled && (
                observed.relayNumber == nil || observed.forwardKey == nil
                    || observed.forwardKeyReference == nil || observed.ttl == nil
            ) {
                issues.insert(.missingObservedState(id))
            }
            guard let oldNeighbors = observed.neighborAddresses else {
                issues.insert(.missingObservedNeighbors(id))
                continue
            }
            let removedNeighbors = Array(Set(oldNeighbors).subtracting(desired.neighborAddresses)).sorted()
            let sources = target.sourcesByDevice[id] ?? []
            if !removedNeighbors.isEmpty || observed.enabled == true && !desired.enabled {
                removeBySpace[id.spaceID, default: []].append(
                    .init(deviceID: id, kind: .remove,
                          removedNeighbors: removedNeighbors, target: desired,
                          sources: sources.union([.unattributedPreviousState]),
                          relationshipSources: removedNeighbors.isEmpty ? [] : [.unattributedPreviousState])
                )
            }
            if desired.enabled && (
                observed.enabled != true || observed.relayNumber != desired.relayNumber
                    || Set(oldNeighbors) != Set(desired.neighborAddresses)
                    || observed.forwardKey != desired.forwardKey
                    || observed.forwardKeyReference != desired.forwardKeyReference
                    || observed.ttl != desired.ttl
                    || desired.primaryPreparation == .installOrBind
            ) {
                let addedNeighbors = Set(desired.neighborAddresses).subtracting(oldNeighbors)
                let addedSources = addedNeighbors.reduce(into: Set<Topology.Source>()) { result, address in
                    result.formUnion(target.neighborSourcesByDevice[id]?[address] ?? [])
                }
                configurationBySpace[id.spaceID, default: []].append(
                    .init(deviceID: id, kind: .configuration,
                          removedNeighbors: [], target: desired,
                          configurationChange: observed.enabled != true
                              || !addedNeighbors.isEmpty && removedNeighbors.isEmpty ? .add : .update,
                          sources: sources,
                          relationshipSources: addedSources.union(
                            removedNeighbors.isEmpty ? [] : [.unattributedPreviousState]))
                )
            }
        }
        for id in byID.keys { issues.insert(.orphanObservation(id)) }
        let spaces = order.compactMap { spaceID -> SpaceTasks? in
            let removes = (removeBySpace[spaceID] ?? []).sorted {
                $0.deviceID.nodeUUID.uuidString < $1.deviceID.nodeUUID.uuidString
            }
            let configurations = (configurationBySpace[spaceID] ?? []).sorted {
                $0.deviceID.nodeUUID.uuidString < $1.deviceID.nodeUUID.uuidString
            }
            guard !removes.isEmpty || !configurations.isEmpty else { return nil }
            return .init(spaceID: spaceID, remove: removes, configuration: configurations)
        }
        return .init(spaces: spaces, issues: issues)
    }

    /// The old/new cloud diff remains a read-only candidate even if every Node
    /// has a trusted observation: actual device state must first be reconciled
    /// into a separate recovery plan. A cached Set echo adds another blocker.
    static func requiringDeviceObservations(_ plan: Plan,
                                            observations: [Observation]) -> Plan {
        var issues = plan.issues
        let byID = Dictionary(grouping: observations, by: \.deviceID)
        for task in plan.spaces.flatMap({ $0.remove + $0.configuration }) {
            let id = task.deviceID
            issues.insert(.requiresDeviceReconciliation(id))
            guard let matches = byID[id], !matches.isEmpty else {
                issues.insert(.missingObservation(id))
                continue
            }
            guard matches.count == 1, let observed = matches.first else {
                issues.insert(.duplicateObservation(id))
                continue
            }
            if let targetAddress = task.target?.address,
               observed.address != targetAddress {
                issues.insert(.addressMismatch(id))
            }
            if observed.evidence != .verified {
                issues.insert(.unverifiedObservation(id))
            }
            if observed.enabled == nil || task.target?.enabled == true && (
                observed.relayNumber == nil || observed.forwardKey == nil
                    || observed.forwardKeyReference == nil || observed.ttl == nil
            ) {
                issues.insert(.missingObservedState(id))
            }
            if observed.neighborAddresses == nil {
                issues.insert(.missingObservedNeighbors(id))
            }
        }
        return .init(spaces: plan.spaces, issues: issues,
                     targetFingerprint: plan.targetFingerprint)
    }

    static func makePlan(
        previous: Topology.Plan,
        target: Topology.Plan,
        selectedZoneID: UUID,
        previousZones: [SiteTriggerZone],
        confirmedZones: [SiteTriggerZone],
        siteSpaceOrder: [String]
    ) -> Plan {
        let topologyIssues = previous.issues.union(target.issues)
        var issues = Set(topologyIssues.map(Issue.topology))
        guard previous.canPreviewTasks, target.canPreviewTasks else {
            return .init(spaces: [], issues: issues)
        }
        var order: [String] = []
        func append(_ spaceID: String) {
            if !order.contains(spaceID) { order.append(spaceID) }
        }
        let selected = confirmedZones.first { $0.zoneId == selectedZoneID }
        for zone in ([selected].compactMap { $0 } + confirmedZones.filter { $0.zoneId != selectedZoneID }) {
            guard let members = zone.members else {
                issues.insert(.invalidMembers(zone.zoneId))
                continue
            }
            members.forEach { append($0.identity.spaceID) }
        }
        for zone in previousZones.filter({ $0.zoneId == selectedZoneID }) {
            guard let members = zone.members else {
                issues.insert(.invalidPreviousMembers(zone.zoneId))
                continue
            }
            members.forEach { append($0.identity.spaceID) }
        }
        var seenSiteSpaces = Set<String>()
        for spaceID in siteSpaceOrder {
            if !seenSiteSpaces.insert(spaceID).inserted { issues.insert(.duplicateSpaceOrder(spaceID)) }
            append(spaceID)
        }

        var removeBySpace: [String: [Task]] = [:]
        var configurationBySpace: [String: [Task]] = [:]
        let allDevices = Set(previous.targets.keys).union(target.targets.keys)
        for id in allDevices {
            guard seenSiteSpaces.contains(id.spaceID) else {
                issues.insert(.missingSpaceOrder(id.spaceID))
                continue
            }
            let old = previous.targets[id]
            let new = target.targets[id]
            let oldNeighbors = Set(old?.neighborAddresses ?? [])
            let newNeighbors = Set(new?.neighborAddresses ?? [])
            let removedNeighbors = Array(oldNeighbors.subtracting(newNeighbors)).sorted()
            let addedNeighbors = newNeighbors.subtracting(oldNeighbors)
            let sources = (previous.sourcesByDevice[id] ?? []).union(target.sourcesByDevice[id] ?? [])
            let removedSources = removedNeighbors.reduce(into: Set<Topology.Source>()) { result, address in
                result.formUnion(previous.neighborSourcesByDevice[id]?[address] ?? [])
            }
            let addedSources = addedNeighbors.reduce(into: Set<Topology.Source>()) { result, address in
                result.formUnion(target.neighborSourcesByDevice[id]?[address] ?? [])
            }
            if old?.enabled == true && (!removedNeighbors.isEmpty || new?.enabled != true) {
                removeBySpace[id.spaceID, default: []].append(
                    .init(deviceID: id, kind: .remove,
                          removedNeighbors: removedNeighbors, target: new, sources: sources,
                          relationshipSources: removedSources)
                )
            }
            if let new, new.enabled,
               old != new || new.primaryPreparation == .installOrBind {
                configurationBySpace[id.spaceID, default: []].append(
                    .init(deviceID: id, kind: .configuration,
                          removedNeighbors: [], target: new,
                          configurationChange: old?.enabled != true
                              || !addedNeighbors.isEmpty && removedNeighbors.isEmpty ? .add : .update,
                          sources: sources,
                          relationshipSources: removedSources.union(addedSources))
                )
            }
        }
        let spaces = order.compactMap { spaceID -> SpaceTasks? in
            let removes = (removeBySpace[spaceID] ?? []).sorted { $0.deviceID.nodeUUID.uuidString < $1.deviceID.nodeUUID.uuidString }
            let configurations = (configurationBySpace[spaceID] ?? []).sorted {
                $0.deviceID.nodeUUID.uuidString < $1.deviceID.nodeUUID.uuidString
            }
            guard !removes.isEmpty || !configurations.isEmpty else { return nil }
            return .init(spaceID: spaceID, remove: removes, configuration: configurations)
        }
        return .init(spaces: spaces, issues: issues)
    }
}
