import Foundation

@main
struct GatewayTimeSyncCoordinatorTests {

    static func main() {
        testOnlyOneAttemptAndOldResultsAreIgnored()
        testDetachBeforeAndAfterSendHaveDifferentOwnership()
        testTypedTimeStatusValidation()
        testTimeoutSettlesOnlyMatchingAttempt()
        testBackgroundCancelsOnlyBeforeSend()
        print("GatewayTimeSyncCoordinatorTests passed")
    }

    private static func testOnlyOneAttemptAndOldResultsAreIgnored() {
        var core = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let first = core.begin(gatewayID: "a")
        require(first != nil, "First Gateway must acquire the only attempt slot")
        require(core.begin(gatewayID: "b") == nil, "A second Gateway must not start concurrently")
        require(core.markSent(attemptID: first!), "The active connecting attempt must transition to sent")

        let result = core.receive(
            attemptID: first!,
            status: .init(seconds: 100, offsetMinutes: 480),
            targetOffsetMinutes: 480
        )
        require(result == .success(renderUI: true), "Matching known Time Status must finish the visible attempt")

        let retry = core.begin(gatewayID: "a")!
        require(
            core.receive(
                attemptID: first!,
                status: .init(seconds: 101, offsetMinutes: 480),
                targetOffsetMinutes: 480
            ) == .ignored,
            "A stale Time Status must not settle a newer Retry"
        )
        require(core.markSent(attemptID: retry), "Retry must remain active after stale callback")
    }

    private static func testDetachBeforeAndAfterSendHaveDifferentOwnership() {
        var beforeSend = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let connecting = beforeSend.begin(gatewayID: "a")!
        require(beforeSend.detachPage() == .cancelledBeforeSend, "Page exit before Time Set must cancel the attempt")
        require(!beforeSend.markSent(attemptID: connecting), "Cancelled connecting attempt must never send")

        var afterSend = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let sent = afterSend.begin(gatewayID: "a")!
        require(afterSend.markSent(attemptID: sent), "Expected sent attempt")
        require(afterSend.detachPage() == .ignored, "Sent attempt must detach without becoming a UI failure")
        require(afterSend.phase == .detachedAfterSend, "Sent attempt ownership must survive the page")
        require(
            afterSend.receive(
                attemptID: sent,
                status: .init(seconds: 100, offsetMinutes: 480),
                targetOffsetMinutes: 480
            ) == .success(renderUI: false),
            "Detached sent success must persist without rendering the closed page"
        )
    }

    private static func testTypedTimeStatusValidation() {
        var unknownTime = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let unknownAttempt = unknownTime.begin(gatewayID: "a")!
        require(unknownTime.markSent(attemptID: unknownAttempt), "Expected sent attempt")
        require(
            unknownTime.receive(
                attemptID: unknownAttempt,
                status: .init(seconds: 0, offsetMinutes: 480),
                targetOffsetMinutes: 480
            ) == .failure(renderUI: true),
            "Unknown zero Time Status must fail Device sync"
        )

        var wrongOffset = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let wrongAttempt = wrongOffset.begin(gatewayID: "a")!
        require(wrongOffset.markSent(attemptID: wrongAttempt), "Expected sent attempt")
        require(
            wrongOffset.receive(
                attemptID: wrongAttempt,
                status: .init(seconds: 100, offsetMinutes: 0),
                targetOffsetMinutes: 480
            ) == .failure(renderUI: true),
            "Mismatched Time Status offset must fail Device sync"
        )
    }

    private static func testTimeoutSettlesOnlyMatchingAttempt() {
        var core = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let attempt = core.begin(gatewayID: "a")!
        require(core.markSent(attemptID: attempt), "Expected sent attempt")
        require(core.timeout(attemptID: UUID()) == .ignored, "Stale timeout must be ignored")
        require(core.timeout(attemptID: attempt) == .failure(renderUI: true), "Matching timeout must fail the attempt")
        require(core.timeout(attemptID: attempt) == .ignored, "Terminal attempt must ignore duplicate timeout")
    }

    private static func testBackgroundCancelsOnlyBeforeSend() {
        var connecting = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let connectingAttempt = connecting.begin(gatewayID: "a")!
        require(
            connecting.cancelBeforeSendForBackground() == .failure(renderUI: true),
            "Background must fail a connection that has not sent Time Set"
        )
        require(
            !connecting.markSent(attemptID: connectingAttempt),
            "A background-cancelled connection must never send"
        )

        var sent = GatewayTimeSyncAttemptCore(pageSessionID: UUID())
        let sentAttempt = sent.begin(gatewayID: "b")!
        require(sent.markSent(attemptID: sentAttempt), "Expected sent attempt")
        require(
            sent.cancelBeforeSendForBackground() == .ignored,
            "A sent Time Set must retain ownership while the app is backgrounded"
        )
        require(sent.phase == .sent, "Background must not detach a sent attempt")
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
