import Foundation

@main
struct SiteTimeZoneSyncResultLayoutPolicyTests {

    static func main() {
        testCompactTerminalContentKeepsPreferredHeightWithoutScrolling()
        testOverflowingTerminalContentCapsCardAndKeepsFooterVisible()
        testOverflowingPushingContentUsesEntireCardAsViewport()
        testSmallTerminalViewportStillReservesCompleteFooter()
        print("SiteTimeZoneSyncResultLayoutPolicyTests passed")
    }

    private static func testCompactTerminalContentKeepsPreferredHeightWithoutScrolling() {
        let layout = SiteTimeZoneSyncResultLayoutPolicy.makeLayout(
            contentHeight: 180,
            availableHeight: 500,
            requestedFooterHeight: 61
        )

        require(layout.resultCardHeight == 241, "Compact card must keep its preferred height")
        require(layout.contentViewportHeight == 180, "Compact content must keep its full viewport")
        require(layout.footerHeight == 61, "Terminal footer must remain 61pt")
        require(!layout.contentScrolls, "Compact content must not scroll needlessly")
    }

    private static func testOverflowingTerminalContentCapsCardAndKeepsFooterVisible() {
        let layout = SiteTimeZoneSyncResultLayoutPolicy.makeLayout(
            contentHeight: 600,
            availableHeight: 320,
            requestedFooterHeight: 61
        )

        require(layout.resultCardHeight == 320, "Overflowing card must cap to safe-area availability")
        require(layout.contentViewportHeight == 259, "Terminal viewport must exclude the fixed footer")
        require(layout.footerHeight == 61, "Overflow must not shrink or scroll away the footer")
        require(layout.contentScrolls, "Overflowing terminal content must scroll")
        require(
            layout.contentViewportHeight + layout.footerHeight == layout.resultCardHeight,
            "Visible content and footer must fit inside the capped result card"
        )
    }

    private static func testOverflowingPushingContentUsesEntireCardAsViewport() {
        let layout = SiteTimeZoneSyncResultLayoutPolicy.makeLayout(
            contentHeight: 600,
            availableHeight: 320,
            requestedFooterHeight: 0
        )

        require(layout.resultCardHeight == 320, "Pushing card must remain safe-area capped")
        require(layout.contentViewportHeight == 320, "Collapsed footer must release its full height")
        require(layout.footerHeight == 0, "Pushing footer must remain collapsed")
        require(layout.contentScrolls, "Overflowing pushing content must scroll")
    }

    private static func testSmallTerminalViewportStillReservesCompleteFooter() {
        let layout = SiteTimeZoneSyncResultLayoutPolicy.makeLayout(
            contentHeight: 120,
            availableHeight: 80,
            requestedFooterHeight: 61
        )

        require(layout.resultCardHeight == 80, "Small cards must still respect the available height")
        require(layout.contentViewportHeight == 19, "Only the content viewport may shrink")
        require(layout.footerHeight == 61, "The unique DONE footer must remain completely visible")
        require(layout.contentScrolls, "Content must scroll when the footer consumes most available height")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
