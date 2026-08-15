import Foundation

@main
struct GatewayDetailProxyConnectionStateTests {

    private static let targetAddress: UInt16 = 0x0005
    private static let otherAddress: UInt16 = 0x0006

    static func main() {
        testInitialStateIsDisconnected()
        testStartConnectingRetainsAttemptID()
        testGattSuccessDoesNotBecomeReady()
        testGattFailureEndsMatchingAttempt()
        testMatchingProxyReadyBecomesReady()
        testOtherProxyReadyDoesNotEndConnectingAttempt()
        testReadyTimeoutOnlyEndsMatchingAttempt()
        testStaleAttemptEventsCannotOverwriteReadySession()
        testMeshDisconnectEndsReadySession()
        testNewReadySessionReplacesPreviousSession()
        testMatchingReadySnapshotRestoresReadyState()
        testLateMatchingReadyRestoresStateAfterTimeout()
        print("GatewayDetailProxyConnectionStateTests passed")
    }

    private static func testInitialStateIsDisconnected() {
        let machine = makeMachine()

        require(machine.state == .disconnected, "A new target must begin disconnected")
        require(!machine.state.isReady, "Disconnected must not be ready")
        require(machine.state.activeAttemptID == nil, "Disconnected must not expose an attempt")
        require(machine.state.readySessionID == nil, "Disconnected must not expose a session")
    }

    private static func testStartConnectingRetainsAttemptID() {
        var machine = makeMachine()
        let attemptID = UUID()

        let changed = machine.reduce(.startConnecting(attemptID: attemptID))

        require(changed, "Starting a new attempt must change state")
        require(machine.state == .connecting(attemptID: attemptID), "Connecting must retain the active attempt")
        require(machine.state.activeAttemptID == attemptID, "Connecting must expose the active attempt")
    }

    private static func testGattSuccessDoesNotBecomeReady() {
        var machine = makeMachine()
        let attemptID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))

        let changed = machine.reduce(.connectCompleted(attemptID: attemptID, succeeded: true))

        require(!changed, "GATT success alone must not change Proxy state")
        require(machine.state == .connecting(attemptID: attemptID), "GATT success must continue waiting for Proxy Ready")
    }

    private static func testGattFailureEndsMatchingAttempt() {
        var machine = makeMachine()
        let attemptID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))

        let changed = machine.reduce(.connectCompleted(attemptID: attemptID, succeeded: false))

        require(changed, "The active GATT failure must change state")
        require(machine.state == .disconnected, "The active GATT failure must disconnect")
    }

    private static func testMatchingProxyReadyBecomesReady() {
        var machine = makeMachine()
        let attemptID = UUID()
        let sessionID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))

        let changed = machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: sessionID))

        require(changed, "Target Proxy Ready must change state")
        require(machine.state == .ready(sessionID: sessionID), "Target Proxy Ready must retain its session")
        require(machine.state.isReady, "Ready session must report ready")
        require(machine.state.readySessionID == sessionID, "Ready must expose its session")
    }

    private static func testOtherProxyReadyDoesNotEndConnectingAttempt() {
        var machine = makeMachine()
        let attemptID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))

        let changed = machine.reduce(.proxyReady(nodeAddress: otherAddress, sessionID: UUID()))

        require(!changed, "Another Proxy must not change the target attempt")
        require(machine.state == .connecting(attemptID: attemptID), "Another Proxy must not end target connecting")
    }

    private static func testReadyTimeoutOnlyEndsMatchingAttempt() {
        var machine = makeMachine()
        let activeAttemptID = UUID()
        machine.reduce(.startConnecting(attemptID: activeAttemptID))

        let staleChanged = machine.reduce(.readyTimedOut(attemptID: UUID()))

        require(!staleChanged, "A stale timeout must be ignored")
        require(machine.state == .connecting(attemptID: activeAttemptID), "A stale timeout must preserve the active attempt")

        let activeChanged = machine.reduce(.readyTimedOut(attemptID: activeAttemptID))

        require(activeChanged, "The active timeout must change state")
        require(machine.state == .disconnected, "The active timeout must disconnect")
    }

    private static func testStaleAttemptEventsCannotOverwriteReadySession() {
        var machine = makeMachine()
        let attemptID = UUID()
        let sessionID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))
        machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: sessionID))

        let failureChanged = machine.reduce(.connectCompleted(attemptID: attemptID, succeeded: false))
        let timeoutChanged = machine.reduce(.readyTimedOut(attemptID: attemptID))

        require(!failureChanged, "A stale failure must not replace Ready")
        require(!timeoutChanged, "A stale timeout must not replace Ready")
        require(machine.state == .ready(sessionID: sessionID), "Ready must survive stale attempt events")
    }

    private static func testMeshDisconnectEndsReadySession() {
        var machine = makeMachine()
        machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: UUID()))

        let changed = machine.reduce(.meshDisconnected)

        require(changed, "Mesh disconnect must change Ready state")
        require(machine.state == .disconnected, "Mesh disconnect must end Ready")
    }

    private static func testNewReadySessionReplacesPreviousSession() {
        var machine = makeMachine()
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: firstSessionID))

        let changed = machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: secondSessionID))

        require(changed, "A new target session must change state")
        require(machine.state == .ready(sessionID: secondSessionID), "The latest target session must replace the old session")
    }

    private static func testMatchingReadySnapshotRestoresReadyState() {
        var machine = makeMachine()
        let sessionID = UUID()

        machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: sessionID))

        require(machine.state == .ready(sessionID: sessionID), "A current matching Ready snapshot must restore Ready")
    }

    private static func testLateMatchingReadyRestoresStateAfterTimeout() {
        var machine = makeMachine()
        let attemptID = UUID()
        let sessionID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))
        machine.reduce(.readyTimedOut(attemptID: attemptID))

        let changed = machine.reduce(.proxyReady(nodeAddress: targetAddress, sessionID: sessionID))

        require(changed, "A valid late target Ready must restore state")
        require(machine.state == .ready(sessionID: sessionID), "A late target Ready must become Ready")
    }

    private static func makeMachine() -> GatewayDetailProxyConnectionStateMachine {
        GatewayDetailProxyConnectionStateMachine(targetAddress: targetAddress)
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
