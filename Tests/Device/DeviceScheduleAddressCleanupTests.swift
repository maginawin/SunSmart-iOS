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
