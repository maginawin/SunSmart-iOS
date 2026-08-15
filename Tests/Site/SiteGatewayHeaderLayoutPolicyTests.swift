import Foundation

@main
struct SiteGatewayHeaderLayoutPolicyTests {

    static func main() {
        require(height(status: false, review: false) == 48)
        require(height(status: true, review: false) == 96)
        require(height(status: true, review: true) == 160)
        require(height(status: false, review: true) == 112)
        testEmptyStateFrameIgnoresVerticalBoundsOffset()
        print("SiteGatewayHeaderLayoutPolicyTests passed")
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
