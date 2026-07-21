import Foundation

@main
struct WiFiGatewayConnectionPollingReducerTests {
    static func main() {
        testImmediateThenFiveSecondPolling()
        testSixtyFiveSecondBoundary()
        testFormatErrorAndTimeoutPreserveFlow()
        testTerminalResultsStopPolling()
        print("WiFiGatewayConnectionPollingReducerTests passed")
    }

    static func testImmediateThenFiveSecondPolling() {
        var reducer = WiFiGatewayConnectionPollingReducer()
        precondition(reducer.start(now: 100) == .sendQuery)
        precondition(reducer.receive(.connecting, now: 102) == .schedule(after: 5))
        precondition(reducer.timerFired(now: 107) == .sendQuery)
    }

    static func testSixtyFiveSecondBoundary() {
        var reducer = WiFiGatewayConnectionPollingReducer()
        _ = reducer.start(now: 0)
        precondition(reducer.receive(.connecting, now: 64) == .schedule(after: 1))
        precondition(reducer.timerFired(now: 65) == .timedOut)
        precondition(reducer.timerFired(now: 66) == .none)
    }

    static func testFormatErrorAndTimeoutPreserveFlow() {
        var reducer = WiFiGatewayConnectionPollingReducer()
        _ = reducer.start(now: 0)
        precondition(reducer.receive(.requestFormatError, now: 1) == .schedule(after: 5))
        precondition(reducer.timerFired(now: 6) == .sendQuery)
        precondition(reducer.receive(.noValidResult, now: 9) == .schedule(after: 5))
    }

    static func testTerminalResultsStopPolling() {
        let values: [(WiFiGatewayConnectionPollingObservation, WiFiGatewayConnectionPollingAction)] = [
            (.connected, .connected),
            (.passwordError, .failed),
            (.failed, .failed),
            (.notConfigured, .notConfigured),
            (.reserved, .failed)
        ]
        for (observation, expected) in values {
            var reducer = WiFiGatewayConnectionPollingReducer()
            _ = reducer.start(now: 0)
            precondition(reducer.receive(observation, now: 1) == expected)
            precondition(reducer.timerFired(now: 2) == .none)
        }
    }
}
