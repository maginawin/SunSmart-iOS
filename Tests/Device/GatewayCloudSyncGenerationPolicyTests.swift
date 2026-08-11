import Foundation

@main
struct GatewayCloudSyncGenerationPolicyTests {

    static func main() {
        testNextGenerationIsStrictlyMonotonic()
        testConfirmationNeverRegresses()
        testOldRequestCannotCleanNewDirtyGeneration()
        print("GatewayCloudSyncGenerationPolicyTests passed")
    }

    private static func testNextGenerationIsStrictlyMonotonic() {
        require(
            GatewayCloudSyncGenerationPolicy.next(now: 100, current: 100, uploaded: 100) == 101,
            "A new local mutation must be newer than both current and uploaded generations"
        )
        require(
            GatewayCloudSyncGenerationPolicy.next(now: 50, current: 100, uploaded: 120) == 121,
            "Clock rollback must not break monotonic generation ordering"
        )
    }

    private static func testConfirmationNeverRegresses() {
        require(
            GatewayCloudSyncGenerationPolicy.confirmed(previous: 100, submitted: 90) == 100,
            "An old joined request must not reduce the confirmed generation"
        )
        require(
            GatewayCloudSyncGenerationPolicy.confirmed(previous: 80, submitted: 90) == 90,
            "A newer submitted request must advance confirmation"
        )
    }

    private static func testOldRequestCannotCleanNewDirtyGeneration() {
        require(
            GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 101, confirmed: 100),
            "Completion for generation 100 must leave generation 101 dirty"
        )
        require(
            !GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 100, confirmed: 100),
            "Matching generations must be clean"
        )
        require(
            GatewayCloudSyncGenerationPolicy.needsAnotherUpload(current: 1, confirmed: nil),
            "Missing confirmation must remain dirty"
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
