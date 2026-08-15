import Foundation

@main
struct SiteGatewayCloudTimeZoneTargetTests {

    static func main() {
        testOwnerTargetsPreserveRemoteOrderAndDeduplicateNormalizedIDs()
        testEditorTargetsUseAuthorizedGatewaysAndAddMissingBoundGateway()
        testVisitorHasNoTargets()
        testRequestMACAndDisplayNameUseWireAndLocalFallbacks()
        testOffsetPrecedenceAndUnknownRemoteOffsets()
        testConfirmedRemoteAcknowledgmentRequiresCompleteMatchingEvidence()
        print("SiteGatewayCloudTimeZoneTargetTests passed")
    }

    private static func testOwnerTargetsPreserveRemoteOrderAndDeduplicateNormalizedIDs() {
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            remote: remote(
                role: .owner,
                gateways: [
                    gateway(" EF725643A2B9 ", requestMAC: " EF725643A2B9 ", offsetMinutes: 480),
                    gateway("aa:bb", requestMAC: "AA:BB", offsetMinutes: 0),
                    gateway("ef725643a2b9", requestMAC: "ef725643a2b9", offsetMinutes: 0),
                    gateway(nil, requestMAC: nil, offsetMinutes: 0)
                ]
            ),
            localByGatewayID: [:]
        )

        require(targets.map(\.id) == ["ef725643a2b9", "aa:bb"], "Owner must preserve first valid remote Gateway order and deduplicate normalized IDs")
        require(targets.map(\.remoteOrder) == [0, 1], "Remote order must refer to the first matching remote Gateway")
        require(targets.map(\.requiresSync) == [true, true], "Conflicting duplicate offsets and mismatched Gateways must require sync")
    }

    private static func testEditorTargetsUseAuthorizedGatewaysAndAddMissingBoundGateway() {
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            remote: remote(
                role: .visitor,
                spaces: [
                    space(.editor, gatewayId: " EF725643A2B9 ", requestGatewayId: " EF725643A2B9 "),
                    space(.visitor, gatewayId: "visitor", requestGatewayId: "visitor"),
                    space(.editor, gatewayId: "missing", requestGatewayId: "Missing-Wire"),
                    space(.editor, gatewayId: "ef725643a2b9", requestGatewayId: "ignored-duplicate")
                ],
                gateways: [
                    gateway("visitor", requestMAC: "visitor", offsetMinutes: 0),
                    gateway("EF725643A2B9", requestMAC: "EF725643A2B9", offsetMinutes: 0)
                ]
            ),
            localByGatewayID: [:]
        )

        require(targets.map(\.id) == ["ef725643a2b9", "missing"], "Editor must only receive authorized Gateway targets, including a missing server Gateway")
        require(targets.map(\.requestMAC) == ["EF725643A2B9", "Missing-Wire"], "Editor must use remote MAC first and Space wire ID for a missing remote Gateway")
        require(targets.map(\.remoteOrder) == [1, 2], "Missing Editor Gateways must follow remote entries using a deterministic synthetic order")
        require(targets.allSatisfy(\.requiresSync), "Mismatched and missing offsets must require sync")
    }

    private static func testVisitorHasNoTargets() {
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            remote: remote(
                role: .visitor,
                spaces: [space(.visitor, gatewayId: "visitor", requestGatewayId: "visitor")],
                gateways: [gateway("visitor", requestMAC: "visitor", offsetMinutes: 0)]
            ),
            localByGatewayID: [:]
        )

        require(targets.isEmpty, "Visitor must not receive cloud Gateway sync targets")
    }

    private static func testRequestMACAndDisplayNameUseWireAndLocalFallbacks() {
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            remote: remote(
                role: .owner,
                gateways: [
                    gateway(" EF725643A2B9 ", requestMAC: " EF725643A2B9 ", offsetMinutes: 0),
                    gateway("aa:bb", requestMAC: "   ", offsetMinutes: 0)
                ]
            ),
            localByGatewayID: [
                " EF725643A2B9 ": SiteGatewayCloudTimeZoneLocalSnapshot(
                    displayName: "  Kitchen Gateway  ",
                    dirtyOffsetMinutes: nil
                ),
                "AA:BB": SiteGatewayCloudTimeZoneLocalSnapshot(
                    displayName: "   ",
                    dirtyOffsetMinutes: nil
                )
            ]
        )

        require(targets.first?.id == "ef725643a2b9", "IDs must compare after trimming and lowercasing")
        require(targets.first?.requestMAC == "EF725643A2B9", "Request must preserve the trimmed wire MAC")
        require(targets.first?.displayName == "Kitchen Gateway", "Display names must use the trimmed local name")
        require(targets.last?.requestMAC == "aa:bb", "Empty remote request MAC must fall back to the normalized ID")
        require(targets.last?.displayName == "aa:bb", "Empty local names must fall back to the request MAC")
    }

    private static func testOffsetPrecedenceAndUnknownRemoteOffsets() {
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: 480,
            remote: remote(
                role: .owner,
                gateways: [
                    gateway("matched", requestMAC: "matched", offsetMinutes: 480),
                    gateway("missing", requestMAC: "missing", offsetMinutes: nil),
                    gateway("conflict", requestMAC: "conflict", offsetMinutes: 480),
                    gateway("CONFLICT", requestMAC: "CONFLICT", offsetMinutes: 0),
                    gateway("confirmed", requestMAC: "confirmed", offsetMinutes: 0),
                    gateway("local", requestMAC: "local", offsetMinutes: 0)
                ]
            ),
            localByGatewayID: [
                "confirmed": SiteGatewayCloudTimeZoneLocalSnapshot(displayName: "", dirtyOffsetMinutes: 0),
                "local": SiteGatewayCloudTimeZoneLocalSnapshot(displayName: "", dirtyOffsetMinutes: 480)
            ],
            confirmedOffsetMinutesByGatewayID: [" CONFIRMED ": 480]
        )

        require(targets.map(\.effectiveOffsetMinutes) == [480, nil, nil, 480, 480], "Effective offset priority must be confirmed, local dirty, then a non-conflicting remote value")
        require(targets.map(\.requiresSync) == [false, true, true, false, false], "Only matching effective offsets may skip sync")
    }

    private static func testConfirmedRemoteAcknowledgmentRequiresCompleteMatchingEvidence() {
        let acknowledgedIDs = SiteGatewayCloudTimeZoneConfirmationPolicy.acknowledgedGatewayIDs(
            confirmedOffsetMinutesByGatewayID: [
                " ALL-MATCH ": 480,
                "match-and-nil": 480,
                "conflict": 480,
                "missing": 480
            ],
            remote: [
                gateway("all-match", requestMAC: "all-match", offsetMinutes: 480),
                gateway("ALL-MATCH", requestMAC: "ALL-MATCH", offsetMinutes: 480),
                gateway("match-and-nil", requestMAC: "match-and-nil", offsetMinutes: 480),
                gateway("MATCH-AND-NIL", requestMAC: "MATCH-AND-NIL", offsetMinutes: nil),
                gateway("conflict", requestMAC: "conflict", offsetMinutes: 480),
                gateway("CONFLICT", requestMAC: "CONFLICT", offsetMinutes: 0)
            ]
        )

        require(
            acknowledgedIDs == ["all-match"],
            "Confirmation may clear only when at least one remote entry exists and every entry has the confirmed offset"
        )
    }

    private static func remote(
        role: SiteEntryRole,
        spaces: [SiteEntrySpaceAccessSnapshot] = [],
        gateways: [SiteEntryGatewayTimeZoneSnapshot] = []
    ) -> SiteEntryTimeZoneRemoteSnapshot {
        SiteEntryTimeZoneRemoteSnapshot(
            role: role,
            values: SitePropsValues(siteName: "Site", imageId: 1, timezone: nil),
            timestamp: 1,
            spaces: spaces,
            gateways: gateways
        )
    }

    private static func space(
        _ role: SiteEntryRole,
        gatewayId: String?,
        requestGatewayId: String?
    ) -> SiteEntrySpaceAccessSnapshot {
        SiteEntrySpaceAccessSnapshot(
            role: role,
            gatewayId: gatewayId,
            requestGatewayId: requestGatewayId
        )
    }

    private static func gateway(
        _ id: String?,
        requestMAC: String?,
        offsetMinutes: Int?
    ) -> SiteEntryGatewayTimeZoneSnapshot {
        SiteEntryGatewayTimeZoneSnapshot(
            id: id,
            requestMAC: requestMAC,
            offsetMinutes: offsetMinutes
        )
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}
