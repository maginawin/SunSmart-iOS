import Foundation

struct WiFiFirmwareDFUTransactionGate: Codable, Equatable {
    private(set) var cancelDeadline: TimeInterval?

    mutating func beginCancel(at now: TimeInterval, timeout: TimeInterval) -> Bool {
        guard !blocksStart(at: now) else { return false }
        cancelDeadline = now + timeout
        return true
    }

    mutating func finishCancel() {
        cancelDeadline = nil
    }

    @discardableResult
    mutating func expireIfNeeded(at now: TimeInterval) -> Bool {
        guard let cancelDeadline, now >= cancelDeadline else { return false }
        self.cancelDeadline = nil
        return true
    }

    func blocksStart(at now: TimeInterval) -> Bool {
        guard let cancelDeadline else { return false }
        return now < cancelDeadline
    }
}
