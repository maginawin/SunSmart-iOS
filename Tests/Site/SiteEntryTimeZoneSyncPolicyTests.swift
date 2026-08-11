import Foundation

@main
struct SiteEntryTimeZoneSyncPolicyTests {

    static func main() {
        testResponseParser()
        testOwnerDecisionMatrix()
        testEditorGatewayScope()
        testVisitorCloudAuthority()
        testLocalDecisionSnapshot()
        testReviewStateUsesServerTruth()
        testReviewStateRespectsAccessScope()
        testDirtyLocalOverridePreventsRepeatedBLEReview()
        testReviewStateRejectsInvalidServerTimezone()
        print("SiteEntryTimeZoneSyncPolicyTests passed")
    }

    private static let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!
    private static let utc = SiteTimeZoneValue(
        ianaId: "Etc/UTC",
        rawUTCOffset: "+00:00"
    )!
    private static let invalid = SiteTimeZoneValue(
        ianaId: "Invalid/Zone",
        rawUTCOffset: "+08:00"
    )!

    private static func testResponseParser() {
        let snapshot = SiteEntryTimeZoneSyncResponseParser.parse(siteData: [
            "role": "visitor",
            "siteName": "Remote Site",
            "imageId": NSNumber(value: 7),
            "timezone": "Asia/Singapore (UTC+08:00)",
            "updateTimestamp": "101",
            "spaces": [
                ["role": "editor", "gatewayId": " AA:BB "],
                ["role": "visitor", "gatewayId": "CC:DD"],
                ["role": "unknown", "gatewayId": "  "]
            ],
            "gateways": [
                ["macAddress": "AA:BB", "timezoneOffset": 96],
                ["macAddress": "CC:DD", "timezoneOffset": NSNumber(value: 64)],
                ["macAddress": "EE:FF", "timezoneOffset": "60"],
                ["macAddress": "11:22", "timezoneOffset": true],
                ["macAddress": "33:44", "timezoneOffset": -1],
                ["macAddress": "55:66", "timezoneOffset": 256],
                ["macAddress": "77:88", "timezoneOffset": 96.5],
                ["macAddress": "99:AA", "timezoneOffset": "invalid"]
            ]
        ])

        require(snapshot?.role == .visitor, "Expected response Site role")
        require(snapshot?.values.siteName == "Remote Site", "Expected complete remote Site props")
        require(snapshot?.values.imageId == 7, "Expected remote image ID")
        require(snapshot?.values.timezone == singapore, "Expected normalized remote timezone")
        require(snapshot?.timestamp == 101, "Expected numeric-string timestamp")
        require(snapshot?.spaces.map(\.gatewayId) == ["aa:bb", "cc:dd", nil], "Gateway IDs must be normalized")
        require(snapshot?.spaces.map(\.role) == [.editor, .visitor, .visitor], "Unknown Space role must not gain Editor access")
        require(snapshot?.gateways.map(\.id) == ["aa:bb", "cc:dd", "ee:ff", "11:22", "33:44", "55:66", "77:88", "99:aa"], "Gateway identities must be normalized")
        require(snapshot?.gateways.map(\.offsetMinutes) == [480, 0, -60, nil, nil, nil, nil, nil], "Gateway offsets must decode only valid UInt8 integers")

        let invalidTimezone = SiteEntryTimeZoneSyncResponseParser.parse(siteData: remoteSiteData(
            role: "owner",
            timezone: "Invalid/Zone (UTC+08:00)",
            timestamp: 102
        ))
        require(invalidTimezone?.values.timezone == nil, "Unknown IANA identifiers must be rejected")

        var missingTimestamp = remoteSiteData(role: "owner", timezone: "Etc/UTC (UTC+00:00)", timestamp: 103)
        missingTimestamp.removeValue(forKey: "updateTimestamp")
        require(SiteEntryTimeZoneSyncResponseParser.parse(siteData: missingTimestamp) == nil, "Missing timestamp must fail parsing")

        var missingSiteName = remoteSiteData(role: "owner", timezone: "Etc/UTC (UTC+00:00)", timestamp: 104)
        missingSiteName.removeValue(forKey: "siteName")
        require(SiteEntryTimeZoneSyncResponseParser.parse(siteData: missingSiteName) == nil, "Visitor authority requires complete Site props")
    }

    private static func testOwnerDecisionMatrix() {
        require(
            decide(
                role: .owner,
                local: singapore,
                localTime: 100,
                remote: singapore,
                remoteTime: 101,
                gateways: [gateway("a", 480)]
            ) == .noAction,
            "Equal Site timezone and matching Gateway must enter normally"
        )

        requireGatewayOnly(
            decide(
                role: .owner,
                local: singapore,
                localTime: 100,
                remote: singapore,
                remoteTime: 101,
                gateways: [gateway("a", 480), gateway("b", 0)]
            ),
            timezone: singapore,
            pending: 1,
            message: "Equal Site timezone with one mismatch must show Gateway status"
        )

        let remoteWins = decide(
            role: .owner,
            local: singapore,
            localTime: 100,
            remote: utc,
            remoteTime: 101,
            gateways: [gateway("a", 0), gateway("b", 480)]
        )
        requireRemote(remoteWins, timezone: utc, pending: 1, "Cloud target must drive Gateway comparison")

        let localWins = decide(
            role: .owner,
            local: singapore,
            localTime: 101,
            remote: utc,
            remoteTime: 100,
            gateways: [gateway("a", 0), gateway("b", 480)]
        )
        requireLocal(localWins, timezone: singapore, pending: 1, "App target must drive Gateway comparison")

        requireLocal(
            decide(role: .owner, local: singapore, localTime: 100, remote: utc, remoteTime: 100),
            timezone: singapore,
            pending: 0,
            "Equal timestamp conflict must upload App timezone"
        )
        requireRemote(
            decide(role: .owner, local: nil, localTime: 100, remote: utc, remoteTime: 1),
            timezone: utc,
            pending: 0,
            "Only valid cloud timezone must win"
        )
        requireLocal(
            decide(role: .owner, local: singapore, localTime: 1, remote: nil, remoteTime: 100),
            timezone: singapore,
            pending: 0,
            "Only valid App timezone must upload"
        )
        require(
            decide(role: .owner, local: nil, localTime: 100, remote: nil, remoteTime: 101) == .noAction,
            "Two invalid timezones must keep current behavior"
        )
        requireRemote(
            decide(role: .owner, local: invalid, localTime: 100, remote: utc, remoteTime: 1),
            timezone: utc,
            pending: 0,
            "Unknown local IANA identifier must be invalid"
        )

        requireGatewayOnly(
            decide(
                role: .owner,
                local: singapore,
                localTime: 100,
                remote: singapore,
                remoteTime: 101,
                gateways: [
                    gateway("duplicate", 480),
                    gateway("DUPLICATE", nil),
                    gateway(nil, nil)
                ]
            ),
            timezone: singapore,
            pending: 2,
            message: "Duplicate IDs count once and malformed anonymous Gateway remains pending"
        )
    }

    private static func testEditorGatewayScope() {
        let spaces = [
            space(.editor, gatewayId: "editor-gateway"),
            space(.visitor, gatewayId: "visitor-gateway")
        ]
        requireGatewayOnly(
            decide(
                role: .visitor,
                local: singapore,
                localTime: 100,
                remote: singapore,
                remoteTime: 101,
                spaces: spaces,
                gateways: [gateway("editor-gateway", 0), gateway("visitor-gateway", 0)]
            ),
            timezone: singapore,
            pending: 1,
            message: "Editor must ignore Visitor-only Gateway"
        )

        require(
            decide(
                role: .visitor,
                local: singapore,
                localTime: 100,
                remote: singapore,
                remoteTime: 101,
                spaces: [space(.editor, gatewayId: nil)],
                gateways: [gateway("visitor-gateway", 0)]
            ) == .noAction,
            "Editor Spaces without Gateway bindings must not inspect unrelated Gateways"
        )

        requireGatewayOnly(
            decide(
                role: .visitor,
                local: singapore,
                localTime: 100,
                remote: singapore,
                remoteTime: 101,
                spaces: [
                    space(.editor, gatewayId: "missing"),
                    space(.editor, gatewayId: "MISSING")
                ],
                gateways: []
            ),
            timezone: singapore,
            pending: 1,
            message: "Missing bound Gateway must be pending and duplicate bindings count once"
        )

        let editorLocalWins = decide(
            role: .visitor,
            local: singapore,
            localTime: 200,
            remote: utc,
            remoteTime: 100,
            spaces: [space(.editor, gatewayId: "a")],
            gateways: [gateway("a", 480)]
        )
        guard case let .useLocal(editorSnapshot, editorGateway) = editorLocalWins else {
            fatalError("An Editor Space grants the approved Site timezone upload flow")
        }
        require(editorSnapshot.values.timezone == singapore, "Editor must upload the App timezone target")
        require(editorGateway == .inSync, "The bound Editor Gateway already matches the App target")
    }

    private static func testVisitorCloudAuthority() {
        let local = localSnapshot(
            timezone: singapore,
            lastUpdate: 200,
            pending: SitePropsPendingState(fields: [.siteName, .timezone], timestamp: 200)
        )
        let remote = remoteSnapshot(
            role: .visitor,
            timezone: utc,
            timestamp: 100,
            values: SitePropsValues(siteName: "Cloud Site", imageId: 9, timezone: utc),
            spaces: [space(.visitor, gatewayId: "visitor-gateway")],
            gateways: [gateway("visitor-gateway", 480)]
        )
        let decision = SiteEntryTimeZoneSyncPolicy.decide(local: local, remote: remote, now: 500)

        guard case let .useVisitorRemote(state) = decision else {
            fatalError("Visitor must use cloud even when App timestamp is newer")
        }
        require(state.values == remote.values, "Visitor must adopt complete cloud Site props")
        require(state.lastUpdate == 100, "Visitor must adopt cloud updateTimestamp")
        require(state.lastUploadCloudTimestamp == 100, "Visitor cloud version must be the upload baseline")
        require(state.pending.fields.isEmpty && state.pending.timestamp == nil, "Visitor must clear all Site props pending")

        let alreadyAuthoritative = SiteEntryTimeZoneSyncPolicy.decide(
            local: localSnapshot(
                values: remote.values,
                lastUpdate: 100,
                lastUploadCloudTimestamp: 100,
                pending: SitePropsPendingState(fields: [], timestamp: nil)
            ),
            remote: remote,
            now: 500
        )
        require(alreadyAuthoritative == .noAction, "Visitor must avoid redundant persistence when cloud state already matches")

        let invalidRemote = remoteSnapshot(
            role: .visitor,
            timezone: invalid,
            timestamp: 300,
            values: SitePropsValues(siteName: "Cloud Site", imageId: 9, timezone: invalid),
            spaces: [space(.visitor, gatewayId: nil)],
            gateways: []
        )
        require(
            SiteEntryTimeZoneSyncPolicy.decide(local: local, remote: invalidRemote, now: 500) == .noAction,
            "Visitor must not persist an invalid cloud timezone"
        )
    }

    private static func testLocalDecisionSnapshot() {
        let decision = SiteEntryTimeZoneSyncPolicy.decide(
            local: localSnapshot(
                timezone: singapore,
                lastUpdate: 100,
                pending: SitePropsPendingState(fields: [.imageId], timestamp: 90)
            ),
            remote: remoteSnapshot(role: .owner, timezone: utc, timestamp: 100),
            now: 50
        )

        guard case let .useLocal(snapshot, gateway) = decision else {
            fatalError("Expected a local decision")
        }
        require(snapshot.siteId == "site-id", "Expected current Site identifier")
        require(snapshot.fields == [.timezone], "Entry sync must upload only timezone")
        require(snapshot.timestamp == 101, "Timestamp must be newer than local and cloud")
        require(snapshot.values.siteName == "Local Site", "Local name must remain unchanged")
        require(snapshot.values.imageId == 7, "Local image must remain unchanged")
        require(snapshot.values.timezone == singapore, "Expected App timezone")
        require(gateway == .noGateways, "Expected no Gateway summary")
    }

    private static func testReviewStateUsesServerTruth() {
        let tokyo = SiteTimeZoneValue(
            ianaId: "Asia/Tokyo",
            rawUTCOffset: "+09:00"
        )!
        let remote = remoteSnapshot(
            role: .owner,
            timezone: tokyo,
            timestamp: 100,
            gateways: [gateway("AA:BB", 480)]
        )

        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: remote) ==
                .review(serverTimezone: tokyo, gatewayCount: 1),
            "Remote server timezone must drive the refresh review state"
        )
        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(
                remote: remote,
                serverTimezone: singapore
            ) == .hidden,
            "A successful local upload must recompute against the new server timezone"
        )
    }

    private static func testReviewStateRespectsAccessScope() {
        let editorSpaces = [
            space(.editor, gatewayId: "editor-gateway"),
            space(.visitor, gatewayId: "visitor-gateway")
        ]
        let gateways = [
            gateway("editor-gateway", 0),
            gateway("visitor-gateway", 0)
        ]
        let editorRemote = remoteSnapshot(
            role: .visitor,
            timezone: singapore,
            timestamp: 100,
            spaces: editorSpaces,
            gateways: gateways
        )
        let visitorRemote = remoteSnapshot(
            role: .visitor,
            timezone: singapore,
            timestamp: 100,
            spaces: [space(.visitor, gatewayId: "visitor-gateway")],
            gateways: gateways
        )

        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: editorRemote) ==
                .review(serverTimezone: singapore, gatewayCount: 1),
            "Editor must count only Editor Space gateways"
        )
        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: visitorRemote) == .hidden,
            "Visitor must not expose a gateway sync action"
        )

        let ownerRemote = remoteSnapshot(
            role: .owner,
            timezone: singapore,
            timestamp: 100,
            gateways: [
                gateway("AA:BB", 480),
                gateway("aa:bb", 0),
                gateway(nil, nil)
            ]
        )
        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: ownerRemote) ==
                .review(serverTimezone: singapore, gatewayCount: 2),
            "Owner must deduplicate identified gateways and count anonymous invalid gateways"
        )

        let missingEditorGateway = remoteSnapshot(
            role: .visitor,
            timezone: singapore,
            timestamp: 100,
            spaces: [space(.editor, gatewayId: "missing")],
            gateways: []
        )
        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: missingEditorGateway) ==
                .review(serverTimezone: singapore, gatewayCount: 1),
            "Missing Editor-bound gateway data must remain pending"
        )

        let allInSync = remoteSnapshot(
            role: .owner,
            timezone: singapore,
            timestamp: 100,
            gateways: [gateway("AA:BB", 480)]
        )
        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: allInSync) == .hidden,
            "A valid all-in-sync snapshot must hide the page component"
        )
    }

    private static func testReviewStateRejectsInvalidServerTimezone() {
        let invalidRemote = remoteSnapshot(
            role: .owner,
            timezone: nil,
            timestamp: 100,
            gateways: [gateway("AA:BB", nil)]
        )
        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(remote: invalidRemote) == nil,
            "Invalid cloud timezone must not replace the last trusted page state"
        )
    }

    private static func testDirtyLocalOverridePreventsRepeatedBLEReview() {
        let remote = remoteSnapshot(
            role: .owner,
            timezone: singapore,
            timestamp: 100,
            gateways: [gateway("AA:BB", 0), gateway("CC:DD", 0)]
        )
        let dirtyOverride = ["aa:bb": 480]

        require(
            SiteEntryTimeZoneSyncPolicy.reviewState(
                remote: remote,
                localDirtyOffsetMinutesByGatewayID: dirtyOverride
            ) == .review(serverTimezone: singapore, gatewayCount: 1),
            "Review count must exclude a locally confirmed dirty Gateway"
        )

        let decision = SiteEntryTimeZoneSyncPolicy.decide(
            local: localSnapshot(timezone: singapore, lastUpdate: 100),
            remote: remote,
            now: 500,
            localDirtyOffsetMinutesByGatewayID: dirtyOverride
        )
        requireGatewayOnly(
            decision,
            timezone: singapore,
            pending: 1,
            message: "Entry decision and Review component must share the dirty local override"
        )
    }

    private static func decide(
        role: SiteEntryRole,
        local: SiteTimeZoneValue?,
        localTime: Int64,
        remote: SiteTimeZoneValue?,
        remoteTime: Int64,
        spaces: [SiteEntrySpaceAccessSnapshot] = [],
        gateways: [SiteEntryGatewayTimeZoneSnapshot] = []
    ) -> SiteEntryTimeZoneDecision {
        SiteEntryTimeZoneSyncPolicy.decide(
            local: localSnapshot(timezone: local, lastUpdate: localTime),
            remote: remoteSnapshot(
                role: role,
                timezone: remote,
                timestamp: remoteTime,
                spaces: spaces,
                gateways: gateways
            ),
            now: 500
        )
    }

    private static func localSnapshot(
        timezone: SiteTimeZoneValue?,
        lastUpdate: Int64,
        pending: SitePropsPendingState = SitePropsPendingState(fields: [], timestamp: nil)
    ) -> SiteEntryTimeZoneLocalSnapshot {
        localSnapshot(
            values: SitePropsValues(siteName: "Local Site", imageId: 7, timezone: timezone),
            lastUpdate: lastUpdate,
            lastUploadCloudTimestamp: 80,
            pending: pending
        )
    }

    private static func localSnapshot(
        values: SitePropsValues,
        lastUpdate: Int64,
        lastUploadCloudTimestamp: Int64?,
        pending: SitePropsPendingState
    ) -> SiteEntryTimeZoneLocalSnapshot {
        SiteEntryTimeZoneLocalSnapshot(
            siteId: "site-id",
            values: values,
            lastUpdate: lastUpdate,
            lastUploadCloudTimestamp: lastUploadCloudTimestamp,
            pending: pending
        )
    }

    private static func remoteSnapshot(
        role: SiteEntryRole,
        timezone: SiteTimeZoneValue?,
        timestamp: Int64,
        values: SitePropsValues? = nil,
        spaces: [SiteEntrySpaceAccessSnapshot] = [],
        gateways: [SiteEntryGatewayTimeZoneSnapshot] = []
    ) -> SiteEntryTimeZoneRemoteSnapshot {
        SiteEntryTimeZoneRemoteSnapshot(
            role: role,
            values: values ?? SitePropsValues(siteName: "Remote Site", imageId: 8, timezone: timezone),
            timestamp: timestamp,
            spaces: spaces,
            gateways: gateways
        )
    }

    private static func space(
        _ role: SiteEntryRole,
        gatewayId: String?
    ) -> SiteEntrySpaceAccessSnapshot {
        SiteEntrySpaceAccessSnapshot(role: role, gatewayId: gatewayId?.lowercased())
    }

    private static func gateway(
        _ id: String?,
        _ offsetMinutes: Int?
    ) -> SiteEntryGatewayTimeZoneSnapshot {
        SiteEntryGatewayTimeZoneSnapshot(id: id?.lowercased(), offsetMinutes: offsetMinutes)
    }

    private static func remoteSiteData(
        role: String,
        timezone: String,
        timestamp: Int64
    ) -> [String: Any] {
        [
            "role": role,
            "siteName": "Remote Site",
            "imageId": 7,
            "timezone": timezone,
            "updateTimestamp": timestamp,
            "spaces": [],
            "gateways": []
        ]
    }

    private static func requireGatewayOnly(
        _ decision: SiteEntryTimeZoneDecision,
        timezone: SiteTimeZoneValue,
        pending: Int,
        message: String
    ) {
        guard case let .showGatewayStatus(actualTimezone, gateway) = decision else {
            fatalError(message)
        }
        require(actualTimezone == timezone, message)
        require(gateway == .pending(pending), message)
    }

    private static func requireRemote(
        _ decision: SiteEntryTimeZoneDecision,
        timezone: SiteTimeZoneValue,
        pending: Int,
        _ message: String
    ) {
        guard case let .useRemote(actualTimezone, _, gateway) = decision else {
            fatalError(message)
        }
        require(actualTimezone == timezone, message)
        require(gateway == expectedGatewaySummary(pending: pending), message)
    }

    private static func requireLocal(
        _ decision: SiteEntryTimeZoneDecision,
        timezone: SiteTimeZoneValue,
        pending: Int,
        _ message: String
    ) {
        guard case let .useLocal(snapshot, gateway) = decision else {
            fatalError(message)
        }
        require(snapshot.values.timezone == timezone, message)
        require(gateway == expectedGatewaySummary(pending: pending), message)
    }

    private static func expectedGatewaySummary(pending: Int) -> SiteEntryGatewaySummary {
        pending > 0 ? .pending(pending) : .noGateways
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
