import Foundation

@main
struct SiteGatewayAssociationConsistencyPolicyTests {

    static func main() {
        testCompleteEmptySnapshotClearsOrphan()
        testCompleteSnapshotPreservesMatchingGateway()
        testGatewayIdMatchingIgnoresCaseAndOuterWhitespace()
        testRestrictedSnapshotPreservesOrphan()
        testMissingGatewayArrayPreservesOrphan()
        testMalformedGatewayEntryMakesSnapshotNonAuthoritative()
        testSpaceWithoutGatewayIsPreserved()
        print("SiteGatewayAssociationConsistencyPolicyTests passed")
    }

    private static func testCompleteEmptySnapshotClearsOrphan() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: []
        )

        precondition(
            snapshot.decision(for: "EF725643A2B9") ==
                .clearOrphan(gatewayId: "EF725643A2B9")
        )
    }

    private static func testCompleteSnapshotPreservesMatchingGateway() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: ["EF725643A2B9"]
        )

        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testGatewayIdMatchingIgnoresCaseAndOuterWhitespace() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: [" ef725643a2b9 "]
        )

        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testRestrictedSnapshotPreservesOrphan() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: false,
            rawGatewayIds: []
        )

        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testMissingGatewayArrayPreservesOrphan() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: nil
        )

        precondition(
            snapshot.decision(for: "EF725643A2B9") == .preserve
        )
    }

    private static func testMalformedGatewayEntryMakesSnapshotNonAuthoritative() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: ["EF725643A2B9", nil]
        )

        precondition(
            snapshot.decision(for: "ORPHAN") == .preserve
        )
    }

    private static func testSpaceWithoutGatewayIsPreserved() {
        let snapshot = SiteGatewayAssociationSnapshot.make(
            isComplete: true,
            rawGatewayIds: []
        )

        precondition(snapshot.decision(for: nil) == .preserve)
        precondition(snapshot.decision(for: "  ") == .preserve)
    }
}
