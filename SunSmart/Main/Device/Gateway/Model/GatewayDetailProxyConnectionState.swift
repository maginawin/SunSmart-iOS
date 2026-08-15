import Foundation

enum GatewayDetailProxyConnectionState: Equatable {
    case disconnected
    case connecting(attemptID: UUID)
    case ready(sessionID: UUID)

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    var activeAttemptID: UUID? {
        guard case .connecting(let attemptID) = self else { return nil }
        return attemptID
    }

    var readySessionID: UUID? {
        guard case .ready(let sessionID) = self else { return nil }
        return sessionID
    }
}

enum GatewayDetailProxyConnectionEvent: Equatable {
    case startConnecting(attemptID: UUID)
    case connectCompleted(attemptID: UUID, succeeded: Bool)
    case proxyReady(nodeAddress: UInt16, sessionID: UUID)
    case readyTimedOut(attemptID: UUID)
    case meshDisconnected
}

struct GatewayDetailProxyConnectionStateMachine {
    let targetAddress: UInt16
    private(set) var state: GatewayDetailProxyConnectionState = .disconnected

    @discardableResult
    mutating func reduce(_ event: GatewayDetailProxyConnectionEvent) -> Bool {
        let nextState: GatewayDetailProxyConnectionState

        switch event {
        case .startConnecting(let attemptID):
            guard case .disconnected = state else { return false }
            nextState = .connecting(attemptID: attemptID)

        case .connectCompleted(let attemptID, let succeeded):
            guard state.activeAttemptID == attemptID else { return false }
            guard !succeeded else { return false }
            nextState = .disconnected

        case .proxyReady(let nodeAddress, let sessionID):
            if nodeAddress == targetAddress {
                nextState = .ready(sessionID: sessionID)
            } else if state.isReady {
                nextState = .disconnected
            } else {
                return false
            }

        case .readyTimedOut(let attemptID):
            guard state.activeAttemptID == attemptID else { return false }
            nextState = .disconnected

        case .meshDisconnected:
            guard state.isReady else { return false }
            nextState = .disconnected
        }

        guard nextState != state else { return false }
        state = nextState
        return true
    }
}
