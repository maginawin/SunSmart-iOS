import Foundation

@main
struct SyncGatewaysContextTests {

    static func main() {
        testRuntimeDescriptorsPreserveSharedCandidateValuesAndAvailability()
        testExplicitFailedIDsFilterRuntimeDescriptorsExactly()
        print("SyncGatewaysContextTests passed")
    }

    private static func testRuntimeDescriptorsPreserveSharedCandidateValuesAndAvailability() {
        let descriptors = SyncGatewayRuntimeDescriptorPolicy.make(
            candidates: [
                .init(
                    id: "missing",
                    displayName: "Missing Remote Gateway",
                    remoteOrder: 2,
                    effectiveOffsetMinutes: nil,
                    requiresSync: true
                ),
                .init(
                    id: "conflict",
                    displayName: "Conflict",
                    remoteOrder: 0,
                    effectiveOffsetMinutes: nil,
                    requiresSync: true
                )
            ],
            localAvailabilityByGatewayID: [
                " CONFLICT ": .init(hasGatewayModel: true, hasNode: true)
            ]
        )

        require(
            descriptors.map(\.id) == ["missing", "conflict"],
            "Runtime descriptors must preserve the shared entry candidate order"
        )
        require(
            descriptors.map(\.initialOffsetMinutes) == [nil, nil],
            "Unknown or conflicting offsets from the shared entry builder must stay pending"
        )
        require(
            descriptors.map(\.isSyncable) == [false, true],
            "Only local GatewayModel plus Node availability may enable BLE sync"
        )
    }

    private static func testExplicitFailedIDsFilterRuntimeDescriptorsExactly() {
        let descriptors = SyncGatewayRuntimeDescriptorPolicy.make(
            candidates: [
                .init(
                    id: "succeeded",
                    displayName: "Succeeded",
                    remoteOrder: 0,
                    effectiveOffsetMinutes: 480,
                    requiresSync: false
                ),
                .init(
                    id: "failed",
                    displayName: "Failed",
                    remoteOrder: 1,
                    effectiveOffsetMinutes: 480,
                    requiresSync: false
                ),
                .init(
                    id: "other",
                    displayName: "Other",
                    remoteOrder: 2,
                    effectiveOffsetMinutes: 0,
                    requiresSync: true
                )
            ],
            localAvailabilityByGatewayID: [
                "failed": .init(hasGatewayModel: true, hasNode: true),
                "other": .init(hasGatewayModel: true, hasNode: true)
            ],
            requiredGatewayIDs: [" FAILED "]
        )

        require(
            descriptors.map(\.id) == ["failed"],
            "An explicit Review context must show exactly its failed IDs, even when stale local evidence says one already matches"
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
