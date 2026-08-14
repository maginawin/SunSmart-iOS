import Foundation

@main
struct WiFiGatewayAutomaticLoadGateTests {

    static func main() {
        testOnlyCurrentReadySessionCanDrain()
        testReloadOverridesResume()
        testInvalidationClosesBarrier()
        print("WiFiGatewayAutomaticLoadGateTests passed")
    }

    private static func testOnlyCurrentReadySessionCanDrain() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let readySessionID = UUID()

        gate.request(forceReload: false)
        require(gate.takeIfReady(currentSessionID: readySessionID) == nil, "Intent must wait for Proxy Ready")
        gate.markReady(sessionID: readySessionID)
        require(gate.takeIfReady(currentSessionID: UUID()) == nil, "A stale Proxy session must not drain")
        require(gate.takeIfReady(currentSessionID: readySessionID) == .resume, "Current Ready session must drain")
    }

    private static func testReloadOverridesResume() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let sessionID = UUID()

        gate.markReady(sessionID: sessionID)
        gate.request(forceReload: false)
        gate.request(forceReload: true)

        require(gate.takeIfReady(currentSessionID: sessionID) == .reload, "Reload must supersede resume")
        require(gate.takeIfReady(currentSessionID: sessionID) == nil, "A drained intent must run once")
    }

    private static func testInvalidationClosesBarrier() {
        var gate = WiFiGatewayAutomaticLoadGate()
        let sessionID = UUID()

        gate.markReady(sessionID: sessionID)
        gate.invalidate()
        gate.request(forceReload: true)

        require(gate.takeIfReady(currentSessionID: sessionID) == nil, "Disconnect must invalidate Ready state")
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
