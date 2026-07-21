import Foundation

@main
struct WiFiGatewayTimeSyncCoordinatorTests {
    static func main() {
        testFirstAttemptStartsAndDuplicateJoins()
        testFinishedSessionReturnsStoredResult()
        testNewSessionStartsAgain()
        testAutomaticLoadWaitsForTimeSync()
        testAutomaticLoadUsesCurrentReadySession()
        testAutomaticReloadOverridesResume()
        testAutomaticLoadInvalidationClosesBarrier()
        print("WiFiGatewayTimeSyncCoordinatorTests passed")
    }

    private static func testFirstAttemptStartsAndDuplicateJoins() {
        var gate = WiFiGatewayTimeSyncSessionGate()
        let sessionID = UUID()

        precondition(gate.begin(sessionID: sessionID) == .start)
        precondition(gate.begin(sessionID: sessionID) == .join)
    }

    private static func testFinishedSessionReturnsStoredResult() {
        var gate = WiFiGatewayTimeSyncSessionGate()
        let sessionID = UUID()

        precondition(gate.begin(sessionID: sessionID) == .start)
        gate.finish(sessionID: sessionID, result: .success)

        precondition(gate.begin(sessionID: sessionID) == .finished(.success))
    }

    private static func testNewSessionStartsAgain() {
        var gate = WiFiGatewayTimeSyncSessionGate()
        let firstSessionID = UUID()
        let secondSessionID = UUID()

        precondition(gate.begin(sessionID: firstSessionID) == .start)
        gate.finish(sessionID: firstSessionID, result: .failed)

        precondition(gate.begin(sessionID: secondSessionID) == .start)
    }

    private static func testAutomaticLoadWaitsForTimeSync() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let sessionID = UUID()

        gate.request(forceReload: true)
        precondition(gate.takeIfReady(currentSessionID: sessionID) == nil)

        gate.markReady(sessionID: sessionID)
        precondition(gate.takeIfReady(currentSessionID: sessionID) == .reload)
    }

    private static func testAutomaticLoadUsesCurrentReadySession() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let readySessionID = UUID()

        gate.markReady(sessionID: readySessionID)
        gate.request(forceReload: false)

        precondition(gate.takeIfReady(currentSessionID: UUID()) == nil)
        precondition(gate.takeIfReady(currentSessionID: readySessionID) == .resume)
    }

    private static func testAutomaticReloadOverridesResume() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let sessionID = UUID()

        gate.markReady(sessionID: sessionID)
        gate.request(forceReload: false)
        gate.request(forceReload: true)

        precondition(gate.takeIfReady(currentSessionID: sessionID) == .reload)
        precondition(gate.takeIfReady(currentSessionID: sessionID) == nil)
    }

    private static func testAutomaticLoadInvalidationClosesBarrier() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let sessionID = UUID()

        gate.markReady(sessionID: sessionID)
        gate.invalidate()
        gate.request(forceReload: true)

        precondition(gate.takeIfReady(currentSessionID: sessionID) == nil)
    }
}
