import Foundation

struct ProximityLightingTopologyReconciler {

    typealias Policy = ProximityLightingTopologyPolicy
    typealias DeviceAddress = Policy.DeviceAddress
    typealias GroupAddress = Policy.GroupAddress

    static let maximumPathCount = 32
    static let maximumPathItemCount = 200
    static let maximumGroupZoneCount = 32
    static let maximumSpaceZoneCount = 32

    struct GroupState: Equatable {
        let address: GroupAddress
        var eligible: Bool
        var relayNumber: UInt8
        var memberAddresses: Set<DeviceAddress>
        var hasTopology: Bool
        var paths: [[DeviceAddress?]]
        var zones: [[DeviceAddress]]
    }

    struct Snapshot: Equatable {
        var groups: [GroupState]
        var spaceZones: [Policy.SpaceZoneSnapshot]

        func group(address: GroupAddress) -> GroupState? {
            return groups.first { $0.address == address }
        }

        mutating func updateGroup(
            address: GroupAddress,
            eligible: Bool,
            relayNumber: UInt8
        ) {
            guard let index = groups.firstIndex(where: { $0.address == address }) else {
                return
            }
            groups[index].eligible = eligible
            groups[index].relayNumber = relayNumber
        }

        mutating func updateGroupMembers(
            address: GroupAddress,
            members: Set<DeviceAddress>
        ) {
            guard let index = groups.firstIndex(where: { $0.address == address }) else {
                return
            }
            groups[index].memberAddresses = members
        }

        mutating func replaceGroupTopology(
            address: GroupAddress,
            hasTopology: Bool,
            paths: [[DeviceAddress?]],
            zones: [[DeviceAddress]]
        ) {
            guard let index = groups.firstIndex(where: { $0.address == address }) else {
                return
            }
            groups[index].hasTopology = hasTopology
            groups[index].paths = paths
            groups[index].zones = zones
        }

        mutating func removeGroup(address: GroupAddress) {
            groups.removeAll { $0.address == address }
        }

        mutating func removeNodeAddresses(_ addresses: Set<DeviceAddress>) {
            guard !addresses.isEmpty else {
                return
            }
            for index in groups.indices {
                groups[index].memberAddresses.subtract(addresses)
                groups[index].paths = groups[index].paths.map { path in
                    path.map { address in
                        guard let address, !addresses.contains(address) else {
                            return nil
                        }
                        return address
                    }
                }
                groups[index].zones = groups[index].zones.map { zone in
                    zone.filter { !addresses.contains($0) }
                }
            }
            spaceZones = spaceZones.map { zone in
                .init(members: zone.members.filter { !addresses.contains($0.deviceAddress) })
            }
        }

        mutating func replaceNodeAddress(
            from oldAddress: DeviceAddress,
            to newAddress: DeviceAddress,
            owningGroupAddress: GroupAddress
        ) {
            guard oldAddress != newAddress,
                  let index = groups.firstIndex(where: { $0.address == owningGroupAddress }) else {
                return
            }
            if groups[index].memberAddresses.remove(oldAddress) != nil {
                groups[index].memberAddresses.insert(newAddress)
            }
            groups[index].paths = groups[index].paths.map { path in
                path.map { $0 == oldAddress ? newAddress : $0 }
            }
            groups[index].zones = groups[index].zones.map { zone in
                zone.map { $0 == oldAddress ? newAddress : $0 }
            }
            spaceZones = spaceZones.map { zone in
                .init(
                    members: zone.members.map { member in
                        guard member.groupAddress == owningGroupAddress,
                              member.deviceAddress == oldAddress else {
                            return member
                        }
                        return .init(
                            groupAddress: owningGroupAddress,
                            deviceAddress: newAddress
                        )
                    }
                )
            }
        }
    }

    enum Repair: Equatable {
        case removedIneligibleGroupTopology(groupAddress: GroupAddress)
        case clearedInvalidSequenceAddress(groupAddress: GroupAddress, deviceAddress: DeviceAddress)
        case removedInvalidGroupZoneAddress(groupAddress: GroupAddress, deviceAddress: DeviceAddress)
        case removedDuplicateGroupZoneAddress(groupAddress: GroupAddress, deviceAddress: DeviceAddress)
        case removedInvalidSpaceZoneMember(groupAddress: GroupAddress, deviceAddress: DeviceAddress)
        case removedDuplicateSpaceZoneMember(groupAddress: GroupAddress, deviceAddress: DeviceAddress)
    }

    enum HardError: Equatable {
        case duplicateGroupAddress(groupAddress: GroupAddress)
        case invalidRelayNumber(groupAddress: GroupAddress, value: UInt8)
        case tooManyPaths(groupAddress: GroupAddress, count: Int)
        case tooManyPathItems(groupAddress: GroupAddress, pathIndex: Int, count: Int)
        case tooManyGroupZones(groupAddress: GroupAddress, count: Int)
        case tooManySpaceZones(count: Int)
        case multipleGroupMembership(deviceAddress: DeviceAddress, groupAddresses: [GroupAddress])
        case tooManyNeighbors(deviceAddress: DeviceAddress, count: Int)

        var diagnosticName: String {
            switch self {
            case .duplicateGroupAddress:
                return "duplicateGroupAddress"
            case .invalidRelayNumber:
                return "invalidRelayNumber"
            case .tooManyPaths:
                return "tooManyPaths"
            case .tooManyPathItems:
                return "tooManyPathItems"
            case .tooManyGroupZones:
                return "tooManyGroupZones"
            case .tooManySpaceZones:
                return "tooManySpaceZones"
            case .multipleGroupMembership:
                return "multipleGroupMembership"
            case .tooManyNeighbors:
                return "tooManyNeighbors"
            }
        }
    }

    struct Result {
        let snapshot: Snapshot
        let plan: Policy.Plan
        let candidateAddresses: Set<DeviceAddress>
        let repairs: [Repair]
        let hardErrors: [HardError]

        var didRepair: Bool {
            return !repairs.isEmpty
        }

        var isValid: Bool {
            return hardErrors.isEmpty
        }
    }

    static func normalize(_ source: Snapshot) -> Result {
        var hardErrors = structuralErrors(in: source)
        var repairs: [Repair] = []
        let candidates = rawCandidateAddresses(in: source)
        var normalizedGroups: [GroupState] = []

        source.groups.sorted(by: { $0.address < $1.address }).forEach { sourceGroup in
            var group = sourceGroup
            guard group.eligible else {
                if group.hasTopology || !group.paths.isEmpty || !group.zones.isEmpty {
                    repairs.append(.removedIneligibleGroupTopology(groupAddress: group.address))
                }
                group.hasTopology = false
                group.paths = []
                group.zones = []
                normalizedGroups.append(group)
                return
            }

            group.paths = group.paths.map { path in
                path.map { optionalAddress in
                    guard let address = optionalAddress else {
                        return nil
                    }
                    guard group.memberAddresses.contains(address) else {
                        repairs.append(
                            .clearedInvalidSequenceAddress(
                                groupAddress: group.address,
                                deviceAddress: address
                            )
                        )
                        return nil
                    }
                    return address
                }
            }

            group.zones = group.zones.map { zone in
                var seen = Set<DeviceAddress>()
                return zone.compactMap { address in
                    guard group.memberAddresses.contains(address) else {
                        repairs.append(
                            .removedInvalidGroupZoneAddress(
                                groupAddress: group.address,
                                deviceAddress: address
                            )
                        )
                        return nil
                    }
                    guard seen.insert(address).inserted else {
                        repairs.append(
                            .removedDuplicateGroupZoneAddress(
                                groupAddress: group.address,
                                deviceAddress: address
                            )
                        )
                        return nil
                    }
                    return address
                }
            }
            normalizedGroups.append(group)
        }

        let eligibleGroupsByAddress = normalizedGroups.reduce(
            into: [GroupAddress: GroupState]()
        ) { result, group in
            if group.eligible {
                result[group.address] = group
            }
        }
        let normalizedSpaceZones = source.spaceZones.map { zone in
            var seen = Set<Policy.SpaceZoneMember>()
            let members = zone.members.compactMap { member -> Policy.SpaceZoneMember? in
                guard let group = eligibleGroupsByAddress[member.groupAddress],
                      group.memberAddresses.contains(member.deviceAddress) else {
                    repairs.append(
                        .removedInvalidSpaceZoneMember(
                            groupAddress: member.groupAddress,
                            deviceAddress: member.deviceAddress
                        )
                    )
                    return nil
                }
                guard seen.insert(member).inserted else {
                    repairs.append(
                        .removedDuplicateSpaceZoneMember(
                            groupAddress: member.groupAddress,
                            deviceAddress: member.deviceAddress
                        )
                    )
                    return nil
                }
                return member
            }
            return Policy.SpaceZoneSnapshot(members: members)
        }

        let normalized = Snapshot(
            groups: normalizedGroups,
            spaceZones: normalizedSpaceZones
        )
        let plan = Policy.makePlan(
            groups: normalizedGroups.compactMap { group in
                guard group.eligible else {
                    return nil
                }
                return .init(
                    address: group.address,
                    relayNumber: group.relayNumber,
                    memberAddresses: group.memberAddresses,
                    paths: group.hasTopology ? group.paths : [],
                    zones: group.hasTopology ? group.zones : []
                )
            },
            spaceZones: normalizedSpaceZones
        )
        hardErrors.append(
            contentsOf: plan.capacityViolations.map {
                .tooManyNeighbors(
                    deviceAddress: $0.deviceAddress,
                    count: $0.neighborCount
                )
            }
        )

        return Result(
            snapshot: normalized,
            plan: plan,
            candidateAddresses: candidates.union(plan.targets.keys),
            repairs: repairs,
            hardErrors: hardErrors
        )
    }

    static func changedDeviceAddresses(
        from oldPlan: Policy.Plan,
        to newPlan: Policy.Plan
    ) -> Set<DeviceAddress> {
        let addresses = Set(oldPlan.targets.keys).union(newPlan.targets.keys)
        return Set(addresses.filter {
            oldPlan.target(for: $0) != newPlan.target(for: $0)
        })
    }

    static func candidateDeviceAddresses(old: Result, new: Result) -> Set<DeviceAddress> {
        return old.candidateAddresses.union(new.candidateAddresses)
    }

    private static func rawCandidateAddresses(in snapshot: Snapshot) -> Set<DeviceAddress> {
        var result = Set<DeviceAddress>()
        snapshot.groups.forEach { group in
            if group.eligible || group.hasTopology || !group.paths.isEmpty || !group.zones.isEmpty {
                result.formUnion(group.memberAddresses)
            }
            group.paths.forEach { path in
                result.formUnion(path.compactMap { $0 })
            }
            group.zones.forEach { result.formUnion($0) }
        }
        snapshot.spaceZones.forEach { zone in
            result.formUnion(zone.members.map(\.deviceAddress))
        }
        return result
    }

    private static func structuralErrors(in snapshot: Snapshot) -> [HardError] {
        var errors: [HardError] = []
        let duplicateGroupAddresses = Dictionary(grouping: snapshot.groups, by: \.address)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        errors.append(
            contentsOf: duplicateGroupAddresses.map {
                .duplicateGroupAddress(groupAddress: $0)
            }
        )

        snapshot.groups.sorted(by: { $0.address < $1.address }).forEach { group in
            if group.eligible,
               !(group.relayNumber <= 20 || group.relayNumber == .max) {
                errors.append(
                    .invalidRelayNumber(
                        groupAddress: group.address,
                        value: group.relayNumber
                    )
                )
            }
            if group.paths.count > maximumPathCount {
                errors.append(
                    .tooManyPaths(
                        groupAddress: group.address,
                        count: group.paths.count
                    )
                )
            }
            group.paths.enumerated().forEach { index, path in
                if path.count > maximumPathItemCount {
                    errors.append(
                        .tooManyPathItems(
                            groupAddress: group.address,
                            pathIndex: index,
                            count: path.count
                        )
                    )
                }
            }
            if group.zones.count > maximumGroupZoneCount {
                errors.append(
                    .tooManyGroupZones(
                        groupAddress: group.address,
                        count: group.zones.count
                    )
                )
            }
        }
        if snapshot.spaceZones.count > maximumSpaceZoneCount {
            errors.append(.tooManySpaceZones(count: snapshot.spaceZones.count))
        }

        var groupAddressesByDevice: [DeviceAddress: Set<GroupAddress>] = [:]
        snapshot.groups.filter(\.eligible).forEach { group in
            group.memberAddresses.forEach {
                groupAddressesByDevice[$0, default: []].insert(group.address)
            }
        }
        groupAddressesByDevice.keys.sorted().forEach { deviceAddress in
            let groupAddresses = Array(groupAddressesByDevice[deviceAddress] ?? []).sorted()
            if groupAddresses.count > 1 {
                errors.append(
                    .multipleGroupMembership(
                        deviceAddress: deviceAddress,
                        groupAddresses: groupAddresses
                    )
                )
            }
        }
        return errors
    }
}
