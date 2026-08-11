import Foundation

@main
struct SyncGatewaysContextTests {

    static func main() {
        testOwnerSelectionUsesDirtyLocalOverrideAndRemoteOrder()
        testEditorSelectionUsesOnlyVisibleGatewayIDs()
        testVisitorSelectionIsEmpty()
        testSelectionDeduplicatesNormalizedIDs()
        print("SyncGatewaysContextTests passed")
    }

    private static func testOwnerSelectionUsesDirtyLocalOverrideAndRemoteOrder() {
        let targets = SyncGatewaysContextSelectionPolicy.select(
            scope: .owner,
            targetOffsetMinutes: 480,
            remote: [
                .init(id: " aa:bb ", offsetMinutes: 0, order: 0),
                .init(id: "cc:dd", offsetMinutes: 480, order: 1),
                .init(id: "ee:ff", offsetMinutes: nil, order: 2),
                .init(id: "gg:hh", offsetMinutes: 0, order: 3)
            ],
            local: [
                "aa:bb": .init(
                    displayName: "Gateway A",
                    offsetMinutes: 480,
                    isCloudDirty: true,
                    hasGatewayModel: true,
                    hasNode: true
                ),
                "gg:hh": .init(
                    displayName: "Gateway G",
                    offsetMinutes: 480,
                    isCloudDirty: false,
                    hasGatewayModel: true,
                    hasNode: true
                )
            ]
        )

        require(targets.map(\.id) == ["ee:ff", "gg:hh"], "Dirty local target must override stale cloud, while clean local must not")
        require(targets.map(\.remoteOrder) == [2, 3], "Targets must preserve remote Site gateway order")
        require(targets[0].displayName == nil, "Missing local binding must keep an optional display name")
        require(!targets[0].isSyncable, "Missing local Gateway/Node binding must remain visible but unavailable")
        require(targets[1].displayName == "Gateway G", "Local display name must be retained")
        require(targets[1].isSyncable, "Complete local binding must be syncable")
    }

    private static func testEditorSelectionUsesOnlyVisibleGatewayIDs() {
        let scope = SiteGatewayAccessScope.resolve(remote: remoteSnapshot(
            role: .visitor,
            spaces: [
                .init(role: .editor, gatewayId: " AA:BB "),
                .init(role: .editor, gatewayId: "aa:bb"),
                .init(role: .visitor, gatewayId: "cc:dd")
            ]
        ))

        let targets = SyncGatewaysContextSelectionPolicy.select(
            scope: scope,
            targetOffsetMinutes: 480,
            remote: [
                .init(id: "cc:dd", offsetMinutes: 0, order: 0),
                .init(id: "aa:bb", offsetMinutes: 0, order: 1)
            ],
            local: [:]
        )

        require(scope == .editor(["aa:bb"]), "Editor scope must normalize and deduplicate bound Gateway IDs")
        require(targets.map(\.id) == ["aa:bb"], "Editor must not gain access to Visitor-only Gateways")
        require(targets[0].remoteOrder == 1, "Filtering must not rewrite remote order")
    }

    private static func testVisitorSelectionIsEmpty() {
        let scope = SiteGatewayAccessScope.resolve(remote: remoteSnapshot(
            role: .visitor,
            spaces: [.init(role: .visitor, gatewayId: "aa:bb")]
        ))
        let targets = SyncGatewaysContextSelectionPolicy.select(
            scope: scope,
            targetOffsetMinutes: 480,
            remote: [.init(id: "aa:bb", offsetMinutes: 0, order: 0)],
            local: [:]
        )

        require(scope == .visitor, "Site without an Editor Space must resolve to Visitor scope")
        require(targets.isEmpty, "Visitor must not receive onsite Gateway targets")
    }

    private static func testSelectionDeduplicatesNormalizedIDs() {
        let targets = SyncGatewaysContextSelectionPolicy.select(
            scope: .owner,
            targetOffsetMinutes: 480,
            remote: [
                .init(id: "AA:BB", offsetMinutes: 0, order: 0),
                .init(id: " aa:bb ", offsetMinutes: nil, order: 1),
                .init(id: nil, offsetMinutes: 0, order: 2),
                .init(id: "  ", offsetMinutes: 0, order: 3)
            ],
            local: [:]
        )

        require(targets.map(\.id) == ["aa:bb"], "Only identified Gateways can become BLE targets and duplicate MACs count once")
        require(targets[0].remoteOrder == 0, "The first remote duplicate defines stable order")
        require(targets[0].initialOffsetMinutes == 0, "The first remote duplicate defines initial offset")
    }

    private static func remoteSnapshot(
        role: SiteEntryRole,
        spaces: [SiteEntrySpaceAccessSnapshot]
    ) -> SiteEntryTimeZoneRemoteSnapshot {
        SiteEntryTimeZoneRemoteSnapshot(
            role: role,
            values: SitePropsValues(siteName: "Site", imageId: 0, timezone: nil),
            timestamp: 1,
            spaces: spaces,
            gateways: []
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
