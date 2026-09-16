import Foundation

@main
struct SiteGatewayHeaderLayoutPolicyTests {

    static func main() {
        testEmptySiteGatewaySelection()
        testOverviewCompatibility()
        testSelectionChangesUpdateHeaderAndEmptyState()
        require(height(status: false, review: false) == 48)
        require(height(status: true, review: false) == 96)
        require(height(status: true, review: true) == 160)
        require(height(status: false, review: true) == 112)
        testEmptyStateFrameIgnoresVerticalBoundsOffset()
        print("SiteGatewayHeaderLayoutPolicyTests passed")
    }

    private static func testEmptySiteGatewaySelection() {
        require(showsStatus(selected: "gateway-a"), "A selected gateway must remain accessible in an empty Site")
        require(showsStatus(selected: "gateway-b"), "Each visible gateway must be accessible")
        require(!showsStatus(selected: nil), "An empty Site Overview must keep statistics hidden")
        require(!showsStatus(selected: "removed"), "A stale gateway selection must not expose an entry")
        require(
            !showsStatus(selected: "gateway-a", visible: []),
            "A gateway removed from the permitted list must not expose an entry"
        )
        require(
            showsStatus(selected: "gateway-a", hasSiteSpaces: true),
            "A selected gateway must remain visible without matching Space status, including empty Favourites"
        )
    }

    private static func testOverviewCompatibility() {
        require(
            showsStatus(selected: nil, hasSiteSpaces: true),
            "A Site with Spaces and visible gateways must keep Overview statistics"
        )
        require(
            !showsStatus(selected: nil, visible: [], hasSiteSpaces: true),
            "An Owner without gateway data must keep Overview statistics hidden"
        )
        require(
            showsStatus(selected: nil, visible: [], hasSiteSpaces: true, hasServerStatus: true),
            "Server-owned Space status must remain visible without a local gateway"
        )
        require(
            showsStatus(selected: nil, visible: [], hasSiteSpaces: true, isOwner: false),
            "Non-Owner Overview visibility must retain the existing rule"
        )
        require(
            !showsStatus(selected: nil, visible: [], hasServerStatus: true, isOwner: false),
            "An empty Site Overview must stay hidden regardless of role or status flags"
        )
    }

    private static func testSelectionChangesUpdateHeaderAndEmptyState() {
        var bounds = CGRect()
        bounds.origin.x = -16
        bounds.origin.y = -72
        bounds.size.width = 390
        bounds.size.height = 700
        // Each page has its own selection. Deleting a selected gateway falls back to Overview.
        let scenarios: [(all: String?, favourites: String?, visible: [String], allHeight: CGFloat, favouritesHeight: CGFloat)] = [
            (nil, nil, ["gateway-a", "gateway-b"], 48, 48),
            ("gateway-a", nil, ["gateway-a", "gateway-b"], 96, 48),
            (nil, "gateway-b", ["gateway-a", "gateway-b"], 48, 96),
            ("gateway-a", "gateway-b", ["gateway-a", "gateway-b"], 96, 96),
            ("gateway-a", "gateway-b", ["gateway-b"], 48, 96),
            ("gateway-a", "gateway-b", [], 48, 48)
        ]
        for scenario in scenarios {
            for review in [false, true] {
                for (selection, expectedBaseHeight) in [
                    (scenario.all, scenario.allHeight),
                    (scenario.favourites, scenario.favouritesHeight)
                ] {
                    let headerHeight = height(
                        status: showsStatus(selected: selection, visible: scenario.visible),
                        review: review
                    )
                    require(headerHeight == expectedBaseHeight + (review ? 64 : 0))
                    let frame = SiteGatewayHeaderLayoutPolicy.emptyStateFrame(
                        collectionBounds: bounds,
                        headerHeight: headerHeight
                    )
                    require(frame.origin.y == headerHeight, "Empty content must start below the complete header")
                }
            }
        }
    }

    private static func showsStatus(
        selected: String?,
        visible: [String] = ["gateway-a", "gateway-b"],
        hasSiteSpaces: Bool = false,
        hasServerStatus: Bool = false,
        isOwner: Bool = true
    ) -> Bool {
        SiteGatewayHeaderLayoutPolicy.showsGatewayStatus(
            selectedGatewayID: selected,
            visibleGatewayIDs: visible,
            hasSiteSpaces: hasSiteSpaces,
            hasServerGatewayStatus: hasServerStatus,
            isSiteOwner: isOwner
        )
    }

    private static func testEmptyStateFrameIgnoresVerticalBoundsOffset() {
        var bounds = CGRect()
        bounds.origin.x = -16
        bounds.origin.y = -72
        bounds.size.width = 390
        bounds.size.height = 700

        let frame = SiteGatewayHeaderLayoutPolicy.emptyStateFrame(
            collectionBounds: bounds,
            headerHeight: 96
        )

        require(frame.origin.x == -16)
        require(frame.origin.y == 96)
        require(frame.size.width == bounds.size.width)
        require(frame.size.height == bounds.size.height)
    }

    private static func height(
        status: Bool,
        review: Bool
    ) -> CGFloat {
        SiteGatewayHeaderLayoutPolicy.height(
            gatewayListHeight: 48,
            gatewayStatusHeight: 48,
            reviewSyncHeight: 64,
            showsGatewayStatus: status,
            showsReviewSync: review
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Unexpected Site Gateway Header height",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
