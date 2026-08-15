import Foundation

struct WiFiGatewayProxySessionTracker {
    private(set) var currentSessionID: UUID?

    @discardableResult
    mutating func begin(sessionID: UUID) -> Bool {
        guard currentSessionID != sessionID else { return false }
        currentSessionID = sessionID
        return true
    }

    mutating func invalidate() {
        currentSessionID = nil
    }
}

struct WiFiGatewayAutomaticLoadGate {
    enum Intent: Equatable {
        case resume
        case reload
    }

    private var readySessionID: UUID?
    private var pendingIntent: Intent?

    mutating func request(forceReload: Bool) {
        let requestedIntent: Intent = forceReload ? .reload : .resume
        if pendingIntent != .reload {
            pendingIntent = requestedIntent
        }
    }

    mutating func markReady(sessionID: UUID) {
        readySessionID = sessionID
    }

    mutating func takeIfReady(currentSessionID: UUID?) -> Intent? {
        guard let currentSessionID,
              currentSessionID == readySessionID,
              let intent = pendingIntent else {
            return nil
        }
        pendingIntent = nil
        return intent
    }

    mutating func invalidate() {
        readySessionID = nil
        pendingIntent = nil
    }
}
