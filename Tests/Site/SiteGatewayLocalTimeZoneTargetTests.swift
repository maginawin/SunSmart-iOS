import Foundation

@main
struct SiteGatewayLocalTimeZoneTargetTests {
    static func main() {
        testFiltersPermissionAndComparesOffsets()
        testUnknownOffsetRemainsPending()
        testNormalizesDeduplicatesAndPreservesWireMAC()
        testOrphanRowsDoNotBecomeTargets()
        print("SiteGatewayLocalTimeZoneTargetTests passed")
    }

    private static func testFiltersPermissionAndComparesOffsets() {
        let targets = SiteGatewayLocalTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            candidates: [
                candidate("owner-match", offset: 480, canConfigure: true),
                candidate("editor-pending", offset: 0, canConfigure: true),
                candidate("visitor-hidden", offset: 0, canConfigure: false)
            ]
        )

        require(
            targets.map(\.id) == ["owner-match", "editor-pending"],
            "Only Gateways allowed by the shared configure permission may become targets"
        )
        require(
            targets.map(\.requiresSync) == [false, true],
            "Only a different local UTC offset may require sync"
        )
    }

    private static func testUnknownOffsetRemainsPending() {
        let targets = SiteGatewayLocalTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            candidates: [candidate("unknown", offset: nil, canConfigure: true)]
        )

        require(targets.first?.effectiveOffsetMinutes == nil, "Unknown local offset must remain unknown")
        require(targets.first?.requiresSync == true, "Unknown local offset must not be treated as synced")
    }

    private static func testNormalizesDeduplicatesAndPreservesWireMAC() {
        let targets = SiteGatewayLocalTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            candidates: [
                SiteGatewayLocalTimeZoneCandidate(
                    requestMAC: " EF725643A2B9 ",
                    displayName: " Kitchen Gateway ",
                    currentOffsetMinutes: 0,
                    canConfigure: true,
                    hasNode: true
                ),
                candidate("ef725643a2b9", offset: 480, canConfigure: true),
                candidate("   ", offset: 0, canConfigure: true)
            ]
        )

        require(targets.count == 1, "Normalized duplicate or empty MACs must not expand the request")
        require(targets.first?.id == "ef725643a2b9", "Local comparison ID must be normalized")
        require(targets.first?.requestMAC == "EF725643A2B9", "API request must preserve the trimmed local wire MAC")
        require(targets.first?.displayName == "Kitchen Gateway", "UI must use the trimmed local Gateway name")
    }

    private static func candidate(
        _ mac: String,
        offset: Int?,
        canConfigure: Bool,
        hasNode: Bool = true
    ) -> SiteGatewayLocalTimeZoneCandidate {
        SiteGatewayLocalTimeZoneCandidate(
            requestMAC: mac,
            displayName: mac,
            currentOffsetMinutes: offset,
            canConfigure: canConfigure,
            hasNode: hasNode
        )
    }

    private static func testOrphanRowsDoNotBecomeTargets() {
        let orphans = ["CC9E27179B40", "E2F54FDEECEB", "F1ADFFA8B2C7"].map {
            candidate($0, offset: nil, canConfigure: true, hasNode: false)
        }
        require(SiteGatewayLocalTimeZoneTargetBuilder.build(targetOffsetMinutes: -180, candidates: orphans).isEmpty,
                "The three orphan rows must produce no task despite Owner permission and unknown offsets")
        let mixed = SiteGatewayLocalTimeZoneTargetBuilder.build(targetOffsetMinutes: -180,
            candidates: orphans + [candidate("valid-unknown", offset: nil, canConfigure: true)])
        require(mixed.count == 1 && mixed.first?.id == "valid-unknown" && mixed.first?.requiresSync == true,
                "A real Node with unknown timezone must remain syncable next to orphan records")
    }
}

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else { fatalError(message) }
}
