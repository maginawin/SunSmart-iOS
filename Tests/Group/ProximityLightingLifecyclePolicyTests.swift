import Foundation

@main
struct ProximityLightingLifecyclePolicyTests {

    typealias Reconciler = ProximityLightingTopologyReconciler
    typealias GroupState = Reconciler.GroupState
    typealias SpaceMember = ProximityLightingTopologyPolicy.SpaceZoneMember

    static func main() {
        testProfileDemotionRemovesGroupAndSpaceTopology()
        testMemberRemovalCleansEveryReference()
        testGroupDeletionKeepsOnlyValidCrossGroupMembers()
        testNodeDeletionCleansAllElementAddresses()
        testAddressMigrationReplacesEveryReference()
        testNormalizationKeepsIntentionalSequenceReuse()
        testNormalizationDeduplicatesZoneMembers()
        testHardLimitsAreRejected()
        testChangedAndCandidateAddressesCoverOldAndNewTopology()
        print("PASS: Proximity Lighting lifecycle policy tests.")
    }

    private static func testProfileDemotionRemovesGroupAndSpaceTopology() {
        var snapshot = makeSnapshot()
        snapshot.updateGroup(address: 0xC000, eligible: false, relayNumber: 2)

        let result = Reconciler.normalize(snapshot)
        let group = result.snapshot.group(address: 0xC000)

        require(group?.hasTopology == false, "Demoted Group retained topology")
        require(group?.paths.isEmpty == true, "Demoted Group retained Sequence data")
        require(group?.zones.isEmpty == true, "Demoted Group retained Trigger Zone data")
        require(
            result.snapshot.spaceZones[0].members == [.init(groupAddress: 0xC001, deviceAddress: 3)],
            "Space Trigger Zone retained members from a demoted Group"
        )
        require(result.plan.target(for: 1).enabled == false, "Demoted Group member was not disabled")
        require(result.plan.target(for: 3).neighborAddresses == [4], "Cross-Group peer did not return to its Group topology")
    }

    private static func testMemberRemovalCleansEveryReference() {
        var snapshot = makeSnapshot()
        snapshot.updateGroupMembers(address: 0xC000, members: [2])

        let result = Reconciler.normalize(snapshot)
        let group = requiredGroup(result.snapshot, address: 0xC000)

        require(group.paths == [[nil, 2, nil, 2]], "Every removed Sequence occurrence was not cleared")
        require(group.zones == [[2]], "Every removed Group Zone occurrence was not cleared")
        require(
            result.snapshot.spaceZones[0].members == [.init(groupAddress: 0xC001, deviceAddress: 3)],
            "Space Zone retained a removed Group member"
        )
        require(result.plan.target(for: 1).enabled == false, "Removed member was not disabled")
    }

    private static func testGroupDeletionKeepsOnlyValidCrossGroupMembers() {
        var snapshot = makeSnapshot()
        snapshot.removeGroup(address: 0xC000)

        let result = Reconciler.normalize(snapshot)

        require(result.snapshot.group(address: 0xC000) == nil, "Deleted Group remained in topology")
        require(
            result.snapshot.spaceZones[0].members == [.init(groupAddress: 0xC001, deviceAddress: 3)],
            "Deleted Group remained in Space Trigger Zone"
        )
        require(result.plan.target(for: 1).enabled == false, "Deleted Group member was not disabled")
    }

    private static func testNodeDeletionCleansAllElementAddresses() {
        var snapshot = makeSnapshot()
        snapshot.removeNodeAddresses([1, 2])

        let result = Reconciler.normalize(snapshot)
        let group = requiredGroup(result.snapshot, address: 0xC000)

        require(group.paths == [[nil, nil, nil, nil]], "Node element addresses remained in Sequence")
        require(group.zones == [[]], "Node element addresses remained in Group Zone")
        require(
            result.snapshot.spaceZones[0].members == [.init(groupAddress: 0xC001, deviceAddress: 3)],
            "Node element addresses remained in Space Zone"
        )
    }

    private static func testAddressMigrationReplacesEveryReference() {
        var snapshot = makeSnapshot()
        snapshot.replaceNodeAddress(from: 1, to: 5, owningGroupAddress: 0xC000)

        let result = Reconciler.normalize(snapshot)
        let group = requiredGroup(result.snapshot, address: 0xC000)

        require(group.memberAddresses == [2, 5], "Migrated address did not replace Group membership")
        require(group.paths == [[5, 2, 5, 2]], "Migrated address did not replace every Sequence occurrence")
        require(group.zones == [[5, 2]], "Migrated address did not replace and normalize every Group Zone occurrence")
        require(result.snapshot.spaceZones[0].members.contains(.init(groupAddress: 0xC000, deviceAddress: 5)), "Migrated address did not replace Space Zone reference")
        require(!result.snapshot.spaceZones[0].members.contains(.init(groupAddress: 0xC000, deviceAddress: 1)), "Old address remained in Space Zone")
    }

    private static func testNormalizationKeepsIntentionalSequenceReuse() {
        let group = GroupState(
            address: 0xC000,
            eligible: true,
            relayNumber: 2,
            memberAddresses: [1, 2],
            hasTopology: true,
            paths: [[1, 2, 1], [1, 2]],
            zones: [[1, 2], [1, 2]]
        )
        let result = Reconciler.normalize(.init(groups: [group], spaceZones: []))

        require(result.snapshot.groups[0].paths == group.paths, "Intentional Sequence reuse was removed")
        require(result.snapshot.groups[0].zones == group.zones, "Cross-Zone reuse was removed")
    }

    private static func testNormalizationDeduplicatesZoneMembers() {
        let group = GroupState(
            address: 0xC000,
            eligible: true,
            relayNumber: 2,
            memberAddresses: [1, 2],
            hasTopology: true,
            paths: [],
            zones: [[1, 1, 2, 1]]
        )
        let spaceZone = ProximityLightingTopologyPolicy.SpaceZoneSnapshot(
            members: [
                .init(groupAddress: 0xC000, deviceAddress: 1),
                .init(groupAddress: 0xC000, deviceAddress: 1),
                .init(groupAddress: 0xC000, deviceAddress: 2)
            ]
        )
        let result = Reconciler.normalize(.init(groups: [group], spaceZones: [spaceZone]))

        require(result.snapshot.groups[0].zones == [[1, 2]], "Group Zone duplicates were not removed stably")
        require(result.snapshot.spaceZones[0].members.count == 2, "Space Zone duplicates were not removed stably")
    }

    private static func testHardLimitsAreRejected() {
        let group = GroupState(
            address: 0xC000,
            eligible: true,
            relayNumber: 21,
            memberAddresses: [1],
            hasTopology: true,
            paths: Array(repeating: [1], count: 33),
            zones: Array(repeating: [1], count: 33)
        )
        let result = Reconciler.normalize(
            .init(
                groups: [group],
                spaceZones: Array(repeating: .init(members: []), count: 33)
            )
        )

        require(result.hardErrors.contains(.invalidRelayNumber(groupAddress: 0xC000, value: 21)), "Invalid relay number was accepted")
        require(result.hardErrors.contains(.tooManyPaths(groupAddress: 0xC000, count: 33)), "Path count overflow was accepted")
        require(result.hardErrors.contains(.tooManyGroupZones(groupAddress: 0xC000, count: 33)), "Group Zone count overflow was accepted")
        require(result.hardErrors.contains(.tooManySpaceZones(count: 33)), "Space Zone count overflow was accepted")
    }

    private static func testChangedAndCandidateAddressesCoverOldAndNewTopology() {
        let oldSnapshot = makeSnapshot()
        let oldResult = Reconciler.normalize(oldSnapshot)
        var newSnapshot = oldSnapshot
        newSnapshot.updateGroup(address: 0xC000, eligible: false, relayNumber: 2)
        let newResult = Reconciler.normalize(newSnapshot)

        let changed = Reconciler.changedDeviceAddresses(from: oldResult.plan, to: newResult.plan)
        let candidates = Reconciler.candidateDeviceAddresses(old: oldResult, new: newResult)

        require(changed == [1, 2, 3], "Old/new target diff missed a cross-Group device")
        require(candidates == [1, 2, 3, 4], "Candidate set did not cover the complete old/new topology")
    }

    private static func makeSnapshot() -> Reconciler.Snapshot {
        let first = GroupState(
            address: 0xC000,
            eligible: true,
            relayNumber: 2,
            memberAddresses: [1, 2],
            hasTopology: true,
            paths: [[1, 2, 1, 2]],
            zones: [[1, 2, 1]]
        )
        let second = GroupState(
            address: 0xC001,
            eligible: true,
            relayNumber: 3,
            memberAddresses: [3, 4],
            hasTopology: true,
            paths: [[3, 4]],
            zones: []
        )
        let spaceZone = ProximityLightingTopologyPolicy.SpaceZoneSnapshot(
            members: [
                .init(groupAddress: 0xC000, deviceAddress: 1),
                .init(groupAddress: 0xC000, deviceAddress: 1),
                .init(groupAddress: 0xC001, deviceAddress: 3)
            ]
        )
        return .init(groups: [first, second], spaceZones: [spaceZone])
    }

    private static func requiredGroup(_ snapshot: Reconciler.Snapshot, address: UInt16) -> GroupState {
        guard let group = snapshot.group(address: address) else {
            fatalError("Missing Group \(address)")
        }
        return group
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
