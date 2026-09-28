import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message):
            return message
        }
    }
}

@main
struct DeviceScheduleAddressCleanupTests {
    static func main() throws {
        try testRemovesDeletedAddressFromActiveAndPendingTargets()
        try testPreservesOtherTargetsAndRemovesDuplicates()
        try testReportsNoChangeWhenAddressIsNotReferenced()
        let legacy = Data("""
        {"scope":{"siteId":"s","spaceId":"p","meshUUID":"m","networkId":"n"},"entries":[{"id":"11111111-1111-1111-1111-111111111111","nodeUUID":"node","primaryAddress":1,"elementAddresses":[1],"stage":"prepared"}]}
        """.utf8)
        let decoded = try JSONDecoder().decode(SpaceDeletionJournal.self, from: legacy)
        try expect(decoded.entries[0].leaveReceipt == nil, "Old prepared intents must not become success.")
        var entry = decoded.entries[0]
        entry.leaveReceipt = .init(evidence: "acknowledged", notBefore: 103, createdTimestamp: 55)
        try expect(!entry.permitsLeaveRecovery(now: 102, createdTimestamp: 55, address: 1), "Recovery must respect settling time.")
        try expect(entry.permitsLeaveRecovery(now: 103, createdTimestamp: 55, address: 1), "Complete receipt permits local recovery.")
        try expect(!entry.permitsLeaveRecovery(now: 104, createdTimestamp: 56, address: 1), "Reused provisioning instance is protected.")
        try expect(!entry.permitsLeaveRecovery(now: 104, createdTimestamp: 55, address: 2), "Same UUID at a new address is not the recorded instance.")
        print("DeviceScheduleAddressCleanupTests passed")
    }

    private static func testRemovesDeletedAddressFromActiveAndPendingTargets() throws {
        let result = DeviceScheduleAddressCleanup.removing(
            address: UInt16(0x1200),
            activeAddresses: [0x1200, 0x1201],
            pendingDeleteAddresses: [0x1202, 0x1200]
        )

        try expect(result.didChange, "Removing an active or pending target must report a change.")
        try expect(result.activeAddresses == [0x1201], "The deleted address must be removed from active targets.")
        try expect(result.pendingDeleteAddresses == [0x1202], "The deleted address must be removed from pending targets.")
    }

    private static func testPreservesOtherTargetsAndRemovesDuplicates() throws {
        let result = DeviceScheduleAddressCleanup.removing(
            address: UInt16(0x1200),
            activeAddresses: [0x1200, 0x1201, 0x1200],
            pendingDeleteAddresses: [0x1200, 0x1202, 0x1200]
        )

        try expect(result.activeAddresses == [0x1201], "All duplicate active references must be removed.")
        try expect(result.pendingDeleteAddresses == [0x1202], "All duplicate pending references must be removed.")
    }

    private static func testReportsNoChangeWhenAddressIsNotReferenced() throws {
        let result = DeviceScheduleAddressCleanup.removing(
            address: UInt16(0x1200),
            activeAddresses: [0x1201],
            pendingDeleteAddresses: [0x1202]
        )

        try expect(!result.didChange, "Capturing a deletion context must not mutate unrelated schedules.")
        try expect(result.activeAddresses == [0x1201], "Unrelated active targets must be preserved.")
        try expect(result.pendingDeleteAddresses == [0x1202], "Unrelated pending targets must be preserved.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure.assertion(message)
        }
    }
}
