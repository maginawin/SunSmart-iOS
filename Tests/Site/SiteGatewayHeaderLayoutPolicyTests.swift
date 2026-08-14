import Foundation

@main
struct SiteGatewayHeaderLayoutPolicyTests {

    static func main() {
        require(height(status: false, review: false) == 48)
        require(height(status: true, review: false) == 96)
        require(height(status: true, review: true) == 160)
        require(height(status: false, review: true) == 112)
        print("SiteGatewayHeaderLayoutPolicyTests passed")
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
