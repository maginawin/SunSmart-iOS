import Foundation

enum WiFiGatewayConnectionPollingObservation: Equatable {
    case connecting
    case connected
    case passwordError
    case failed
    case notConfigured
    case requestFormatError
    case reserved
    case noValidResult
}

enum WiFiGatewayConnectionPollingAction: Equatable {
    case none
    case sendQuery
    case schedule(after: TimeInterval)
    case connected
    case failed
    case notConfigured
    case timedOut
}

struct WiFiGatewayConnectionPollingReducer {
    private enum Phase: Equatable {
        case idle
        case active(deadline: TimeInterval)
        case finished
    }

    private var phase: Phase = .idle

    mutating func start(now: TimeInterval) -> WiFiGatewayConnectionPollingAction {
        guard phase == .idle else { return .none }
        phase = .active(deadline: now + WiFiGatewayV19Timing.connectionPollWindow)
        return .sendQuery
    }

    mutating func receive(
        _ observation: WiFiGatewayConnectionPollingObservation,
        now: TimeInterval
    ) -> WiFiGatewayConnectionPollingAction {
        guard case .active(let deadline) = phase else { return .none }
        switch observation {
        case .connected:
            phase = .finished
            return .connected
        case .passwordError, .failed, .reserved:
            phase = .finished
            return .failed
        case .notConfigured:
            phase = .finished
            return .notConfigured
        case .connecting, .requestFormatError, .noValidResult:
            guard now < deadline else {
                phase = .finished
                return .timedOut
            }
            return .schedule(
                after: min(WiFiGatewayV19Timing.connectionPollInterval, deadline - now)
            )
        }
    }

    mutating func timerFired(now: TimeInterval) -> WiFiGatewayConnectionPollingAction {
        guard case .active(let deadline) = phase else { return .none }
        guard now < deadline else {
            phase = .finished
            return .timedOut
        }
        return .sendQuery
    }
}
