import Foundation

@main
struct GatewayFastAddTimeInitializationTests {

    static func main() {
        testAcceptsKnownMatchingGatewayTime()
        testRejectsUnknownGatewayTime()
        testRejectsMismatchedGatewayOffset()
        testAcceptsNegativeQuarterHourOffset()
        print("GatewayFastAddTimeInitializationTests passed")
    }

    private static func testAcceptsKnownMatchingGatewayTime() {
        require(
            GatewayFastAddTimeInitializationPolicy.accepts(
                seconds: 100,
                offsetMinutes: 480,
                targetOffsetMinutes: 480
            ),
            "Non-zero matching TimeStatus must succeed"
        )
    }

    private static func testRejectsUnknownGatewayTime() {
        require(
            !GatewayFastAddTimeInitializationPolicy.accepts(
                seconds: 0,
                offsetMinutes: 480,
                targetOffsetMinutes: 480
            ),
            "Unknown time must fail"
        )
    }

    private static func testRejectsMismatchedGatewayOffset() {
        require(
            !GatewayFastAddTimeInitializationPolicy.accepts(
                seconds: 100,
                offsetMinutes: 0,
                targetOffsetMinutes: 480
            ),
            "Wrong offset must fail"
        )
    }

    private static func testAcceptsNegativeQuarterHourOffset() {
        require(
            GatewayFastAddTimeInitializationPolicy.accepts(
                seconds: 100,
                offsetMinutes: -225,
                targetOffsetMinutes: -225
            ),
            "Matching negative 15-minute offsets must succeed"
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
