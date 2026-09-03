//
//  ProximityLightingTopologyPolicy.swift
//  SunSmart
//
import Foundation

struct ProximityLightingTopologyPolicy {

    typealias DeviceAddress = UInt16
    typealias GroupAddress = UInt16

    static let maximumNeighborCount = 184

    struct GroupSnapshot {
        let address: GroupAddress
        let relayNumber: UInt8
        let memberAddresses: Set<DeviceAddress>
        let paths: [[DeviceAddress?]]
        let zones: [[DeviceAddress]]
    }

    struct SpaceZoneMember: Hashable {
        let groupAddress: GroupAddress
        let deviceAddress: DeviceAddress
    }

    struct SpaceZoneSnapshot: Equatable {
        let members: [SpaceZoneMember]
    }

    struct Target: Equatable {
        let enabled: Bool
        let relayNumber: UInt8?
        let neighborAddresses: [DeviceAddress]
    }

    struct CurrentState: Equatable {
        let enabled: Bool
        let relayNumber: UInt8?
        let neighborAddresses: [DeviceAddress]
    }

    struct CapacityViolation: Equatable {
        let deviceAddress: DeviceAddress
        let neighborCount: Int
        let maximumNeighborCount: Int
    }

    enum Mutation: Equatable {
        case enabled(Bool)
        case relayNumber(UInt8)
        case neighbors(relayNumber: UInt8, neighborAddresses: [DeviceAddress])
    }

    struct Plan {
        let targets: [DeviceAddress: Target]
        let capacityViolations: [CapacityViolation]

        var hasCapacityViolation: Bool {
            return !capacityViolations.isEmpty
        }

        func target(for deviceAddress: DeviceAddress) -> Target {
            return targets[deviceAddress] ?? Target(
                enabled: false,
                relayNumber: nil,
                neighborAddresses: []
            )
        }
    }

    static func makePlan(
        groups: [GroupSnapshot],
        spaceZones: [SpaceZoneSnapshot]
    ) -> Plan {
        let sortedGroups = groups.sorted { $0.address < $1.address }
        let groupsByAddress = sortedGroups.reduce(into: [GroupAddress: GroupSnapshot]()) {
            $0[$1.address] = $1
        }
        var relayNumbersByDeviceAddress: [DeviceAddress: UInt8] = [:]
        var neighborAddresses: [DeviceAddress: Set<DeviceAddress>] = [:]

        sortedGroups.forEach { group in
            group.memberAddresses.forEach { address in
                relayNumbersByDeviceAddress[address] = group.relayNumber
                _ = neighborAddresses[address, default: []]
            }

            group.paths.forEach { path in
                path.enumerated().forEach { index, optionalAddress in
                    guard let address = optionalAddress,
                          group.memberAddresses.contains(address) else {
                        return
                    }
                    if index > 0,
                       let previousAddress = path[index - 1],
                       group.memberAddresses.contains(previousAddress),
                       previousAddress != address {
                        neighborAddresses[address, default: []].insert(previousAddress)
                    }
                    if index + 1 < path.count,
                       let nextAddress = path[index + 1],
                       group.memberAddresses.contains(nextAddress),
                       nextAddress != address {
                        neighborAddresses[address, default: []].insert(nextAddress)
                    }
                }
            }

            group.zones.forEach { zone in
                let validAddresses = Set(
                    zone.filter { group.memberAddresses.contains($0) }
                )
                validAddresses.forEach { address in
                    neighborAddresses[address, default: []].formUnion(
                        validAddresses.filter { $0 != address }
                    )
                }
            }
        }

        spaceZones.forEach { zone in
            let validMembers = zone.members.filter { member in
                guard let group = groupsByAddress[member.groupAddress] else {
                    return false
                }
                return group.memberAddresses.contains(member.deviceAddress)
            }
            let validAddresses = Set(validMembers.map(\.deviceAddress))
            validAddresses.forEach { address in
                neighborAddresses[address, default: []].formUnion(
                    validAddresses.filter { $0 != address }
                )
            }
        }

        var targets: [DeviceAddress: Target] = [:]
        relayNumbersByDeviceAddress.keys.sorted().forEach { address in
            targets[address] = Target(
                enabled: true,
                relayNumber: relayNumbersByDeviceAddress[address],
                neighborAddresses: Array(neighborAddresses[address] ?? []).sorted()
            )
        }

        let capacityViolations = targets.keys.sorted().compactMap { address -> CapacityViolation? in
            guard let target = targets[address],
                  target.neighborAddresses.count > maximumNeighborCount else {
                return nil
            }
            return CapacityViolation(
                deviceAddress: address,
                neighborCount: target.neighborAddresses.count,
                maximumNeighborCount: maximumNeighborCount
            )
        }

        return Plan(
            targets: targets,
            capacityViolations: capacityViolations
        )
    }

    static func mutation(
        from current: CurrentState,
        to target: Target
    ) -> Mutation? {
        guard target.neighborAddresses.count <= maximumNeighborCount else {
            return nil
        }
        guard target.enabled else {
            return current.enabled ? .enabled(false) : nil
        }
        guard let relayNumber = target.relayNumber else {
            return nil
        }

        let neighborsEqual = current.neighborAddresses.sorted()
            == target.neighborAddresses.sorted()
        if neighborsEqual, current.relayNumber == relayNumber {
            return current.enabled ? nil : .enabled(true)
        }
        if current.enabled,
           neighborsEqual,
           current.relayNumber != relayNumber {
            return .relayNumber(relayNumber)
        }
        return .neighbors(
            relayNumber: relayNumber,
            neighborAddresses: target.neighborAddresses
        )
    }

    static func affectedDeviceAddresses(
        oldSpaceZones: [SpaceZoneSnapshot],
        newSpaceZones: [SpaceZoneSnapshot]
    ) -> Set<DeviceAddress> {
        return Set(
            (oldSpaceZones + newSpaceZones)
                .flatMap(\.members)
                .map(\.deviceAddress)
        )
    }
}
