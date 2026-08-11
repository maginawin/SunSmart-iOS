import Foundation

@main
struct SyncGatewaysScanSessionTests {

    static func main() {
        testActiveElapsedExcludesPausedTime()
        testPauseResumeAreIdempotent()
        testSessionIdentityAndFinishAreTerminal()
        print("SyncGatewaysScanSessionTests passed")
    }

    private static func testActiveElapsedExcludesPausedTime() {
        var core = SyncGatewaysScanSessionCore(sessionID: UUID())
        core.resume(at: 10)
        require(core.consumeElapsed(at: 14) == 4, "Running scan must consume monotonic elapsed time")
        core.pause(at: 15)
        require(core.consumeElapsed(at: 30) == 0, "Paused wall time must not count toward RSSI expiry")
        core.resume(at: 40)
        require(core.consumeElapsed(at: 43) == 3, "Resumed scan must continue with a fresh monotonic baseline")
    }

    private static func testPauseResumeAreIdempotent() {
        var core = SyncGatewaysScanSessionCore(sessionID: UUID())
        core.resume(at: 1)
        core.resume(at: 100)
        require(core.consumeElapsed(at: 3) == 2, "Repeated resume must not replace an active baseline")
        core.pause(at: 4)
        core.pause(at: 200)
        core.resume(at: 10)
        require(core.consumeElapsed(at: 12) == 2, "Repeated pause must remain idempotent")
    }

    private static func testSessionIdentityAndFinishAreTerminal() {
        let sessionID = UUID()
        var core = SyncGatewaysScanSessionCore(sessionID: sessionID)
        core.resume(at: 1)
        require(core.accepts(callbackSessionID: sessionID), "Current scan session callback must be accepted")
        require(!core.accepts(callbackSessionID: UUID()), "Stale scan session callback must be rejected")

        core.finish()
        core.resume(at: 10)
        require(core.consumeElapsed(at: 20) == 0, "Finished session must never resume")
        require(!core.accepts(callbackSessionID: sessionID), "Finished session must reject even matching callbacks")
        require(core.phase == .finished, "Finish must be terminal")
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
