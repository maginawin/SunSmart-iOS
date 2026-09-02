import Foundation

@main
struct ProximityLightingTopologyPolicyTests {

    typealias Policy = ProximityLightingTopologyPolicy

    static func main() {
        testEmptySpaceZonesDoNotChangeGroupTopology()
        testGroupAndSpaceTopologyAreMerged()
        testRemovingSpaceZoneRestoresGroupTopology()
        testCrossGroupZoneMergesBothGroupTopologies()
        testGroupProfileRelayChangePreservesMergedTopology()
        testMismatchedSpaceZoneMembershipIsIgnored()
        testDuplicateEdgesAreRemoved()
        testUnknownDeviceIsDisabled()
        testAffectedAddressesIgnoreEmptyZones()
        testHealthyTargetDoesNotCreateMutation()
        testEligibleEmptyTopologyIsNeverDisabled()
        testDisabledEligibleDeviceIsRecovered()
        testIneligibleEnabledDeviceIsDisabled()
        testInvalidEnabledTargetNeverDisables()
        testRelayOnlyChangeDoesNotRewriteNeighbors()
        testBelowMaximumNeighborCountIsAccepted()
        testMaximumNeighborCountIsAccepted()
        testMoreThanMaximumNeighborCountIsRejectedAfterMerge()
        testUInt8MaximumNeighborCountIsRejected()
        testDuplicateEdgesDoNotCreateCapacityViolation()
        print("PASS: Proximity Lighting topology policy tests.")
    }

    private static func testEmptySpaceZonesDoNotChangeGroupTopology() {
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: [1, 2, 3],
            paths: [[1, 2, 3]]
        )
        let baseline = Policy.makePlan(groups: [group], spaceZones: [])
        let withEmptyZones = Policy.makePlan(
            groups: [group],
            spaceZones: Array(repeating: .init(members: []), count: 32)
        )

        require(baseline.targets == withEmptyZones.targets, "Empty Space zones changed Group topology")
        require(withEmptyZones.target(for: 1).enabled, "Eligible device was disabled by empty Space zones")
        require(withEmptyZones.target(for: 1).neighborAddresses == [2], "Path start neighbor mismatch")
        require(withEmptyZones.target(for: 2).neighborAddresses == [1, 3], "Path middle neighbors mismatch")
        require(withEmptyZones.target(for: 3).neighborAddresses == [2], "Path end neighbor mismatch")
    }

    private static func testGroupAndSpaceTopologyAreMerged() {
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: [1, 2, 3],
            paths: [[1, 2, 3]]
        )
        let spaceZone = makeSpaceZone([(0xC000, 1), (0xC000, 3)])
        let plan = Policy.makePlan(groups: [group], spaceZones: [spaceZone])

        require(plan.target(for: 1).neighborAddresses == [2, 3], "Space edge did not merge into Group path")
        require(plan.target(for: 2).neighborAddresses == [1, 3], "Unrelated Group path node changed")
        require(plan.target(for: 3).neighborAddresses == [1, 2], "Space edge did not merge into Group path end")
    }

    private static func testRemovingSpaceZoneRestoresGroupTopology() {
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: [1, 2, 3],
            paths: [[1, 2, 3]]
        )
        let plan = Policy.makePlan(groups: [group], spaceZones: [])

        require(plan.target(for: 1) == .init(enabled: true, relayNumber: 1, neighborAddresses: [2]), "Removing Space zone did not restore Group target")
        require(plan.target(for: 3).enabled, "Removing Space zone disabled a Group member")
    }

    private static func testCrossGroupZoneMergesBothGroupTopologies() {
        let firstGroup = makeGroup(
            address: 0xC000,
            relay: 1,
            members: [1, 2],
            paths: [[1, 2]]
        )
        let secondGroup = makeGroup(
            address: 0xC001,
            relay: 3,
            members: [3, 4],
            zones: [[3, 4]]
        )
        let spaceZone = makeSpaceZone([(0xC000, 1), (0xC001, 3)])
        let plan = Policy.makePlan(groups: [firstGroup, secondGroup], spaceZones: [spaceZone])

        require(plan.target(for: 1).neighborAddresses == [2, 3], "First Group contribution was overwritten")
        require(plan.target(for: 3).neighborAddresses == [1, 4], "Second Group contribution was overwritten")
        require(plan.target(for: 1).relayNumber == 1, "First device did not keep its Group Profile relay")
        require(plan.target(for: 3).relayNumber == 3, "Second device did not keep its Group Profile relay")
    }

    private static func testGroupProfileRelayChangePreservesMergedTopology() {
        let firstGroup = makeGroup(
            address: 0xC000,
            relay: 2,
            members: [1, 2],
            paths: [[1, 2]]
        )
        let secondGroup = makeGroup(
            address: 0xC001,
            relay: 3,
            members: [3, 4],
            zones: [[3, 4]]
        )
        let spaceZone = makeSpaceZone([(0xC000, 1), (0xC001, 3)])
        let plan = Policy.makePlan(groups: [firstGroup, secondGroup], spaceZones: [spaceZone])

        require(plan.target(for: 1) == .init(enabled: true, relayNumber: 2, neighborAddresses: [2, 3]), "Updated Group relay changed the merged topology")
        require(plan.target(for: 3) == .init(enabled: true, relayNumber: 3, neighborAddresses: [1, 4]), "Another Group relay was changed")
    }

    private static func testMismatchedSpaceZoneMembershipIsIgnored() {
        let firstGroup = makeGroup(address: 0xC000, relay: 1, members: [1])
        let secondGroup = makeGroup(address: 0xC001, relay: 3, members: [2])
        let spaceZone = makeSpaceZone([(0xC001, 1), (0xC001, 2)])
        let plan = Policy.makePlan(groups: [firstGroup, secondGroup], spaceZones: [spaceZone])

        require(plan.target(for: 1).neighborAddresses.isEmpty, "A stale Space Group reference created an invalid edge")
        require(plan.target(for: 1).relayNumber == 1, "A stale Space Group reference changed the owner Group relay")
        require(plan.target(for: 2).neighborAddresses.isEmpty, "A stale Space member was retained in a Zone edge")
        require(plan.target(for: 2).relayNumber == 3, "The valid device did not keep its Group Profile relay")
    }

    private static func testDuplicateEdgesAreRemoved() {
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: [1, 2],
            paths: [[1, 2]],
            zones: [[1, 2]]
        )
        let spaceZone = makeSpaceZone([(0xC000, 1), (0xC000, 2)])
        let plan = Policy.makePlan(groups: [group], spaceZones: [spaceZone])

        require(plan.target(for: 1).neighborAddresses == [2], "Duplicate neighbor edges were retained")
        require(plan.target(for: 2).neighborAddresses == [1], "Duplicate reverse edges were retained")
    }

    private static func testUnknownDeviceIsDisabled() {
        let plan = Policy.makePlan(groups: [], spaceZones: [])
        require(plan.target(for: 9) == .init(enabled: false, relayNumber: nil, neighborAddresses: []), "Unknown device did not receive disabled target")
    }

    private static func testAffectedAddressesIgnoreEmptyZones() {
        let emptyZones = Array(repeating: Policy.SpaceZoneSnapshot(members: []), count: 32)
        require(
            Policy.affectedDeviceAddresses(oldSpaceZones: [], newSpaceZones: emptyZones).isEmpty,
            "Empty Space zones affected devices"
        )

        let oldZone = makeSpaceZone([(0xC000, 1), (0xC000, 2)])
        let newZone = makeSpaceZone([(0xC000, 2), (0xC001, 3)])
        require(
            Policy.affectedDeviceAddresses(oldSpaceZones: [oldZone], newSpaceZones: [newZone]) == [1, 2, 3],
            "Old and new Space memberships were not unioned"
        )
    }

    private static func testHealthyTargetDoesNotCreateMutation() {
        let current = Policy.CurrentState(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [2, 3]
        )
        let target = Policy.Target(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [3, 2]
        )
        require(
            Policy.mutation(from: current, to: target) == nil,
            "Healthy topology created a redundant mutation"
        )
    }

    private static func testEligibleEmptyTopologyIsNeverDisabled() {
        let target = Policy.Target(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: []
        )
        let current = Policy.CurrentState(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [2]
        )
        require(
            Policy.mutation(from: current, to: target)
                == .neighbors(relayNumber: 1, neighborAddresses: []),
            "Eligible device with no neighbors was disabled instead of clearing neighbors"
        )
    }

    private static func testDisabledEligibleDeviceIsRecovered() {
        let current = Policy.CurrentState(
            enabled: false,
            relayNumber: 1,
            neighborAddresses: [2]
        )
        let target = Policy.Target(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [2]
        )
        require(
            Policy.mutation(from: current, to: target) == .enabled(true),
            "Disabled eligible device was not re-enabled"
        )
    }

    private static func testIneligibleEnabledDeviceIsDisabled() {
        let current = Policy.CurrentState(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [2]
        )
        let target = Policy.Target(
            enabled: false,
            relayNumber: nil,
            neighborAddresses: []
        )
        require(
            Policy.mutation(from: current, to: target) == .enabled(false),
            "Ineligible enabled device was not disabled"
        )
    }

    private static func testInvalidEnabledTargetNeverDisables() {
        let current = Policy.CurrentState(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [2]
        )
        let target = Policy.Target(
            enabled: true,
            relayNumber: nil,
            neighborAddresses: [2]
        )
        require(
            Policy.mutation(from: current, to: target) == nil,
            "Invalid enabled target produced a destructive mutation"
        )
    }

    private static func testRelayOnlyChangeDoesNotRewriteNeighbors() {
        let current = Policy.CurrentState(
            enabled: true,
            relayNumber: 1,
            neighborAddresses: [2]
        )
        let target = Policy.Target(
            enabled: true,
            relayNumber: 2,
            neighborAddresses: [2]
        )
        require(
            Policy.mutation(from: current, to: target) == .relayNumber(2),
            "Relay-only change rewrote the neighbor table"
        )
    }

    private static func testBelowMaximumNeighborCountIsAccepted() {
        let members = Set((1...184).map(UInt16.init))
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: members,
            zones: [Array(members)]
        )
        let plan = Policy.makePlan(groups: [group], spaceZones: [])

        require(
            plan.target(for: 1).neighborAddresses.count == 183,
            "Neighbor count below the maximum was not compiled"
        )
        require(
            !plan.hasCapacityViolation,
            "Neighbor count below the maximum was rejected"
        )
    }

    private static func testMaximumNeighborCountIsAccepted() {
        let members = Set((1...185).map(UInt16.init))
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: members,
            zones: [Array(members)]
        )
        let plan = Policy.makePlan(groups: [group], spaceZones: [])

        require(
            plan.target(for: 1).neighborAddresses.count == Policy.maximumNeighborCount,
            "Maximum neighbor count was not compiled"
        )
        require(
            !plan.hasCapacityViolation,
            "Maximum neighbor count was rejected"
        )
    }

    private static func testMoreThanMaximumNeighborCountIsRejectedAfterMerge() {
        let firstMembers = Set((1...93).map(UInt16.init))
        let secondMembers = Set((94...186).map(UInt16.init))
        let allMembers = firstMembers.union(secondMembers)
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: allMembers,
            zones: [Array(firstMembers), Array(secondMembers)]
        )
        let spaceZone = makeSpaceZone(
            allMembers.map { (UInt16(0xC000), $0) }
        )
        let plan = Policy.makePlan(groups: [group], spaceZones: [spaceZone])

        require(plan.hasCapacityViolation, "Merged topology over the limit was accepted")
        require(
            plan.capacityViolations.first(where: { $0.deviceAddress == 1 })
                == .init(
                    deviceAddress: 1,
                    neighborCount: 185,
                    maximumNeighborCount: Policy.maximumNeighborCount
                ),
            "Capacity violation did not identify the final merged neighbor count"
        )
        require(
            Policy.mutation(
                from: .init(enabled: false, relayNumber: nil, neighborAddresses: []),
                to: plan.target(for: 1)
            ) == nil,
            "An oversized merged target entered the synchronization mutation path"
        )
        let oversizedTarget = plan.target(for: 1)
        require(
            Policy.mutation(
                from: .init(
                    enabled: false,
                    relayNumber: oversizedTarget.relayNumber,
                    neighborAddresses: oversizedTarget.neighborAddresses
                ),
                to: oversizedTarget
            ) == nil,
            "An oversized target generated an enable mutation"
        )
        require(
            Policy.mutation(
                from: .init(
                    enabled: true,
                    relayNumber: 2,
                    neighborAddresses: oversizedTarget.neighborAddresses
                ),
                to: oversizedTarget
            ) == nil,
            "An oversized target generated a relay-number mutation"
        )
    }

    private static func testUInt8MaximumNeighborCountIsRejected() {
        let members = Set((1...256).map(UInt16.init))
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: members,
            zones: [Array(members)]
        )
        let plan = Policy.makePlan(groups: [group], spaceZones: [])

        require(
            plan.capacityViolations.first(where: { $0.deviceAddress == 1 })
                == .init(
                    deviceAddress: 1,
                    neighborCount: 255,
                    maximumNeighborCount: Policy.maximumNeighborCount
                ),
            "The U8 field maximum bypassed the transport capacity limit"
        )
        require(
            Policy.mutation(
                from: .init(enabled: true, relayNumber: 2, neighborAddresses: []),
                to: plan.target(for: 1)
            ) == nil,
            "A U8-maximum target entered the synchronization mutation path"
        )
    }

    private static func testDuplicateEdgesDoNotCreateCapacityViolation() {
        let members = Set((1...185).map(UInt16.init))
        let group = makeGroup(
            address: 0xC000,
            relay: 1,
            members: members,
            paths: [Array(members).map(Optional.some)],
            zones: [Array(members)]
        )
        let spaceZone = makeSpaceZone(
            members.map { (UInt16(0xC000), $0) }
        )
        let plan = Policy.makePlan(groups: [group], spaceZones: [spaceZone])

        require(
            plan.target(for: 1).neighborAddresses.count == Policy.maximumNeighborCount,
            "Duplicate relationships changed the deduplicated neighbor count"
        )
        require(
            !plan.hasCapacityViolation,
            "Duplicate relationships created a false capacity violation"
        )
    }

    private static func makeGroup(
        address: UInt16,
        relay: UInt8,
        members: Set<UInt16>,
        paths: [[UInt16?]] = [],
        zones: [[UInt16]] = []
    ) -> Policy.GroupSnapshot {
        return .init(
            address: address,
            relayNumber: relay,
            memberAddresses: members,
            paths: paths,
            zones: zones
        )
    }

    private static func makeSpaceZone(_ members: [(UInt16, UInt16)]) -> Policy.SpaceZoneSnapshot {
        return .init(
            members: members.map {
                .init(groupAddress: $0.0, deviceAddress: $0.1)
            }
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError(message)
        }
    }
}
