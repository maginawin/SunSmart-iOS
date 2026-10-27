import Foundation

/// Timing and ownership for the BLE firmware page's single discovery window.
struct BleFirmwareScanSession {
    enum Mode {
        case automatic
        case batteryActivation
    }

    struct Discovery {
        let isFirstDiscovery: Bool
        let foundAllTargets: Bool
    }

    private(set) var sessionID: UUID?
    private(set) var mode: Mode?
    private(set) var deadline: TimeInterval = 0
    private var targetAddresses: Set<UInt16> = []
    private var discoveredAddresses: Set<UInt16> = []

    var isActive: Bool { sessionID != nil }

    mutating func begin(mode: Mode, targetAddresses: Set<UInt16>, at now: TimeInterval) -> UUID {
        let id = UUID()
        sessionID = id
        self.mode = mode
        self.targetAddresses = targetAddresses
        discoveredAddresses.removeAll()
        deadline = now + (mode == .batteryActivation ? 30 : 10)
        return id
    }

    func accepts(sessionID: UUID, at now: TimeInterval) -> Bool {
        self.sessionID == sessionID && now < deadline
    }

    mutating func receive(address: UInt16, sessionID: UUID, at now: TimeInterval) -> Discovery? {
        guard accepts(sessionID: sessionID, at: now), targetAddresses.contains(address) else {
            return nil
        }
        let isFirstDiscovery = discoveredAddresses.insert(address).inserted
        if mode == .automatic && isFirstDiscovery {
            deadline = now + 10
        }
        return Discovery(
            isFirstDiscovery: isFirstDiscovery,
            foundAllTargets: discoveredAddresses == targetAddresses
        )
    }

    func remainingSeconds(at now: TimeInterval) -> Int? {
        guard isActive, mode == .batteryActivation else { return nil }
        return max(0, Int(ceil(deadline - now)))
    }

    /// Reject before mutating selection, so waiting never clears an earlier selection.
    @discardableResult
    func performSelectionChange(_ change: () -> Void) -> Bool {
        guard !isActive else { return false }
        change()
        return true
    }

    @discardableResult
    mutating func end(sessionID: UUID) -> Bool {
        guard self.sessionID == sessionID else { return false }
        self.sessionID = nil
        mode = nil
        targetAddresses.removeAll()
        discoveredAddresses.removeAll()
        return true
    }
}
