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
        testGatewayWidthsAndOverflow()
        testGatewaySelectionVisibility()
        testGatewayScrollRestoration()
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

    private static func testGatewayWidthsAndOverflow() {
        let empty = SiteGatewayListLayout(availableWidth: 303, gatewayCount: 0)
        require(empty.itemWidth == 0 && empty.contentWidth == 0)
        require(empty.clampedOffset(100) == 0)
        let cases: [(width: CGFloat, count: Int, expected: CGFloat, scrolls: Bool)] = [
            (303, 1, 151.5, false), (303, 2, 112, true),
            (303, 3, 112, true), (303, 4, 112, true),
            (303, 10, 112, true), (303, 50, 112, true),
            (480, 1, 240, false), (480, 2, 160, false),
            (480, 3, 120, false), (480, 4, 120, true)
        ]
        for test in cases {
            let layout = SiteGatewayListLayout(availableWidth: test.width, gatewayCount: test.count)
            require(layout.itemWidth == test.expected, "Keep equal shares with a 112 pt minimum")
            require((layout.contentWidth > layout.viewportWidth) == test.scrolls)
            require(layout.itemWidth + layout.viewportWidth == test.width)
        }
        for count in 1...3 {
            let threshold = CGFloat(count + 1) * 112
            let below = SiteGatewayListLayout(availableWidth: threshold - 1, gatewayCount: count)
            let equal = SiteGatewayListLayout(availableWidth: threshold, gatewayCount: count)
            let above = SiteGatewayListLayout(availableWidth: threshold + CGFloat(count + 1), gatewayCount: count)
            require(below.itemWidth == 112 && below.contentWidth > below.viewportWidth)
            require(equal.itemWidth == 112 && equal.contentWidth == equal.viewportWidth)
            require(above.itemWidth == 113 && above.contentWidth == above.viewportWidth)
        }
    }

    private static func testGatewaySelectionVisibility() {
        let layout = SiteGatewayListLayout(availableWidth: 303, gatewayCount: 10)
        require(layout.offsetToReveal(gatewayIndex: 9, currentOffset: 0) == 929, "Menu must reach the last gateway")
        require(layout.offsetToReveal(gatewayIndex: 0, currentOffset: 929) == 0)
        require(layout.offsetToReveal(gatewayIndex: 1, currentOffset: 100) == 100, "Already visible items must not move")
        require(layout.offsetToReveal(gatewayIndex: 1, currentOffset: 0) == 33, "Only scroll the clipped portion")
        require(layout.clampedOffset(-20) == 0)
        require(layout.clampedOffset(2000) == 929)
        for index in 0..<10 {
            let offset = layout.offsetToReveal(gatewayIndex: index, currentOffset: 400)
            let start = CGFloat(index) * layout.itemWidth
            require(start >= offset && start + layout.itemWidth <= offset + layout.viewportWidth)
        }
        let narrow = SiteGatewayListLayout(availableWidth: 200, gatewayCount: 3)
        require(narrow.offsetToReveal(gatewayIndex: 1, currentOffset: 0) == 112, "Extremely narrow viewports align the item's leading edge")
    }

    private static func testGatewayScrollRestoration() {
        let ids = ["a", "b", "c", "d", "e"]
        let layout = SiteGatewayListLayout(availableWidth: 303, gatewayCount: ids.count)
        let position = SiteGatewayListScrollPosition(gatewayIDs: ids, offset: 130, layout: layout)
        require(position.gatewayID == "b")
        require(position.restoredOffset(gatewayIDs: ids, layout: layout) == 130, "Status refresh must retain browsing position")

        let inserted = ["new"] + ids
        let insertedLayout = SiteGatewayListLayout(availableWidth: 303, gatewayCount: inserted.count)
        require(position.restoredOffset(gatewayIDs: inserted, layout: insertedLayout) == 242, "Inserting before the anchor must retain the visible gateway")
        let removedBefore = ["b", "c", "d", "e"]
        let smallerLayout = SiteGatewayListLayout(availableWidth: 303, gatewayCount: removedBefore.count)
        require(position.restoredOffset(gatewayIDs: removedBefore, layout: smallerLayout) == 18)
        require(position.restoredOffset(gatewayIDs: ["a", "c", "d", "e"], layout: smallerLayout) == 130, "Deleted anchors use the clamped previous offset")
        let one = SiteGatewayListLayout(availableWidth: 303, gatewayCount: 1)
        require(position.restoredOffset(gatewayIDs: ["e"], layout: one) == 0)
        let empty = SiteGatewayListLayout(availableWidth: 303, gatewayCount: 0)
        require(position.restoredOffset(gatewayIDs: [], layout: empty) == 0)

        let wide = SiteGatewayListLayout(availableWidth: 640, gatewayCount: ids.count)
        let widePosition = SiteGatewayListScrollPosition(gatewayIDs: ids, offset: 150, layout: wide)
        require(widePosition.restoredOffset(gatewayIDs: ids, layout: layout) == 111, "Shrinking widths must not skip the anchor")
        let all = SiteGatewayListScrollState()
        let favourites = SiteGatewayListScrollState()
        all.position = position
        all.selectItem("e")
        favourites.selectItem("")
        require(favourites.position == nil && all.selectedItemID == "e", "Pages own independent scroll and selection state")
        require(all.needsSelectionReveal)
        all.needsSelectionReveal = false
        all.selectItem("e")
        require(!all.needsSelectionReveal, "A status refresh must not pull browsing back to the selected item")
        all.selectItem("e", reveal: true)
        require(all.needsSelectionReveal, "Reselecting the same gateway from the menu must reveal it")
        all.needsSelectionReveal = false
        all.selectItem("")
        require(all.selectedItemID == "" && all.position?.gatewayID == "b", "Overview retains the browsing anchor")
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
