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

/// Main-thread ownership shared only by Gateway detail pages. A delayed page
/// release must never close the next page's connection.
final class GatewayDetailConnectionOwnership {
    static let shared = GatewayDetailConnectionOwnership()
    private var ownerID: UUID?
    private weak var session: GatewayDetailConnectionSession?
    private var closedAt: [String: TimeInterval] = [:]

    func claim(_ session: GatewayDetailConnectionSession) {
        guard ownerID != session.id else { return }
        self.session?.finish()
        ownerID = session.id
        self.session = session
    }

    func owns(_ id: UUID) -> Bool { ownerID == id }

    func release(_ id: UUID) {
        guard owns(id) else { return }
        ownerID = nil
        session = nil
    }

    func recordClose(target: String, at now: TimeInterval) {
        closedAt = closedAt.filter { now - $0.value < 1 }
        closedAt[target] = now
    }

    func cooldown(target: String, at now: TimeInterval) -> TimeInterval {
        guard let lastClose = closedAt[target] else { return 0 }
        return max(0, 1 - (now - lastClose))
    }
}

/// App-side connection lifecycle. The injected transport and clock are also used
/// by the behavior tests; no SDK internals or log parsing are required.
final class GatewayDetailConnectionSession {
    typealias Cancel = () -> Void
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Cancel
    private static let maximumAttempts = 3
    private static let retryAdmissionWindow: TimeInterval = 50

    struct Environment {
        var contextIsCurrent: () -> Bool
        var canConnect: () -> Bool
        var readySession: () -> UUID?
        var connect: (@escaping (Bool) -> Void) -> Void
        var disconnect: () -> Void
    }

    let id = UUID()
    var onStateChange: (() -> Void)?
    var onReady: ((UUID) -> Void)?
    var onExhausted: (() -> Void)?
    var onDiagnostic: ((String) -> Void)?
    private(set) var isFinished = false
    private(set) var attemptCount = 0
    private var machine: GatewayDetailProxyConnectionStateMachine
    private let target: String
    private let ownership: GatewayDetailConnectionOwnership
    private let environment: Environment
    private let callbackTimeout: TimeInterval
    private let readyTimeout: TimeInterval
    private let now: () -> TimeInterval
    private let schedule: Schedule
    private var visible = false
    private var automaticConnectionEnabled = true
    private var sentAttempt = false
    private var ownsConnection = false
    private var cleaning = false
    private var exhausted = false
    private var startedAt: TimeInterval?
    private var closedReadySessions = Set<UUID>()
    private var cancelConnect: Cancel?
    private var cancelDeadline: Cancel?
    private var cancelBudget: Cancel?

    var state: GatewayDetailProxyConnectionState { machine.state }

    init(target: String, address: UInt16,
         ownership: GatewayDetailConnectionOwnership = .shared,
         environment: Environment,
         callbackTimeout: TimeInterval,
         readyTimeout: TimeInterval,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         schedule: @escaping Schedule = GatewayDetailConnectionSession.scheduleTimer) {
        self.target = target
        self.machine = GatewayDetailProxyConnectionStateMachine(targetAddress: address)
        self.ownership = ownership
        self.environment = environment
        self.callbackTimeout = callbackTimeout
        self.readyTimeout = readyTimeout
        self.now = now
        self.schedule = schedule
    }

    static func scheduleTimer(after delay: TimeInterval, action: @escaping () -> Void) -> Cancel {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    static func retainDuringDisconnect(_ bearer: AnyObject, schedule: Schedule = scheduleTimer) {
        _ = schedule(2) { withExtendedLifetime(bearer) {} }
    }

    func resume() {
        guard !isFinished else { return }
        ownership.claim(self)
        visible = true
        guard validateContext() else { return }
        if let readyID = environment.readySession(), !closedReadySessions.contains(readyID) {
            acceptReady(readyID)
        } else {
            if state.isReady {
                machine.reduce(.meshDisconnected)
                ownsConnection = false
                onStateChange?()
            }
            ensureConnection()
        }
    }

    /// A child page or an interactive dismissal may only hide this page. Keep
    /// an established connection, but never start a queued attempt while hidden.
    func pause() {
        visible = false
        if state.activeAttemptID != nil, !sentAttempt {
            cancelRecovery()
            resetState()
        }
    }

    func setAutomaticConnectionEnabled(_ enabled: Bool) {
        automaticConnectionEnabled = enabled
        if !enabled {
            cancelRecovery()
            if state.activeAttemptID != nil {
                resetState()
                disconnectOwnedConnection()
            }
        } else {
            ensureConnection()
        }
    }

    func availabilityChanged() {
        guard !isFinished, ownership.owns(id), validateContext() else { return }
        if !environment.canConnect() {
            cancelRecovery()
            resetState()
            disconnectOwnedConnection()
            exhausted = false
        } else {
            ensureConnection()
        }
    }

    func receiveReady(sessionID: UUID) {
        guard !isFinished, !cleaning, ownership.owns(id), validateContext(),
              environment.readySession() == sessionID,
              !closedReadySessions.contains(sessionID),
              state.isReady || sentAttempt else { return }
        acceptReady(sessionID)
    }

    func connectionLost() {
        guard !isFinished, !cleaning, ownership.owns(id), validateContext(),
              state.isReady, environment.readySession() == nil else { return }
        if let readyID = state.readySessionID { closedReadySessions.insert(readyID) }
        machine.reduce(.meshDisconnected)
        ownsConnection = false
        onStateChange?()
        ensureConnection()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        visible = false
        diagnostic("finish")
        cancelRecovery()
        // Invalidate the attempt before calling SDK APIs, which may synchronously
        // deliver a global disconnect event.
        resetState()
        disconnectOwnedConnection()
        ownership.release(id)
    }

    private func ensureConnection() {
        guard !isFinished, visible, automaticConnectionEnabled, !exhausted,
              ownership.owns(id), validateContext(), environment.canConnect(),
              state == .disconnected else { return }
        attemptCount = 0
        startedAt = now()
        cancelBudget = schedule(Self.retryAdmissionWindow) { [weak self] in self?.budgetExpired() }
        startAttempt(minimumDelay: 0)
    }

    private func startAttempt(minimumDelay: TimeInterval) {
        guard let startedAt, now() - startedAt < Self.retryAdmissionWindow, attemptCount < Self.maximumAttempts else {
            endRecovery(reason: "budget_exhausted")
            return
        }
        let attemptID = UUID()
        machine.reduce(.startConnecting(attemptID: attemptID))
        let delay = max(minimumDelay, ownership.cooldown(target: target, at: now()))
        diagnostic("scheduled attempt=\(attemptID) delay=\(delay)")
        onStateChange?()
        // Even the zero-delay path is cancellable before it reaches the SDK.
        cancelConnect = schedule(delay) { [weak self] in self?.send(attemptID: attemptID) }
    }

    private func send(attemptID: UUID) {
        guard accepts(attemptID), validateContext() else { return }
        cancelConnect = nil
        guard visible, automaticConnectionEnabled, environment.canConnect() else {
            cancelRecovery()
            resetState()
            return
        }
        guard let startedAt, now() - startedAt < Self.retryAdmissionWindow else {
            endRecovery(reason: "budget_exhausted")
            return
        }
        attemptCount += 1
        sentAttempt = true
        ownsConnection = true
        diagnostic("connect attempt=\(attemptID)")
        cancelDeadline = schedule(callbackTimeout) { [weak self] in
            self?.failed(attemptID: attemptID, reason: "callback_timeout")
        }
        environment.connect { [weak self] succeeded in
            self?.completed(attemptID: attemptID, succeeded: succeeded)
        }
    }

    private func completed(attemptID: UUID, succeeded: Bool) {
        guard accepts(attemptID), sentAttempt, validateContext() else {
            diagnostic("ignored_callback attempt=\(attemptID)")
            return
        }
        diagnostic("completed attempt=\(attemptID) succeeded=\(succeeded)")
        guard succeeded else {
            failed(attemptID: attemptID, reason: "connect_failed")
            return
        }
        cancelDeadline?()
        cancelDeadline = schedule(readyTimeout) { [weak self] in
            self?.failed(attemptID: attemptID, reason: "ready_timeout")
        }
    }

    private func failed(attemptID: UUID, reason: String) {
        guard accepts(attemptID), validateContext() else { return }
        diagnostic("failed attempt=\(attemptID) reason=\(reason)")
        cancelDeadline?()
        cancelDeadline = nil
        machine.reduce(.connectCompleted(attemptID: attemptID, succeeded: false))
        sentAttempt = false
        disconnectOwnedConnection()
        guard visible, automaticConnectionEnabled, environment.canConnect() else {
            cancelRecovery()
            onStateChange?()
            return
        }
        startAttempt(minimumDelay: 1)
    }

    private func acceptReady(_ sessionID: UUID) {
        cancelRecovery()
        exhausted = false
        ownsConnection = true
        let changed = machine.reduce(.proxyReady(nodeAddress: machine.targetAddress, sessionID: sessionID))
        diagnostic("ready session=\(sessionID)")
        if changed { onStateChange?() }
        if visible { onReady?(sessionID) }
    }

    private func budgetExpired() {
        guard !isFinished, ownership.owns(id), validateContext(), !state.isReady else { return }
        cancelBudget = nil
        // The window limits new retries. An issued attempt retains its own
        // GATT and Ready deadlines, including after this window has elapsed.
        if sentAttempt {
            diagnostic("retry_window_elapsed active_attempt_continues")
            return
        }
        endRecovery(reason: "budget_exhausted")
    }

    private func endRecovery(reason: String) {
        exhausted = true
        diagnostic(reason)
        cancelRecovery()
        resetState()
        disconnectOwnedConnection()
        if visible, automaticConnectionEnabled, environment.canConnect() { onExhausted?() }
    }

    private func accepts(_ attemptID: UUID) -> Bool {
        !isFinished && !cleaning && ownership.owns(id) && state.activeAttemptID == attemptID
    }

    @discardableResult
    private func validateContext() -> Bool {
        guard environment.contextIsCurrent() else {
            finish()
            return false
        }
        return true
    }

    private func disconnectOwnedConnection() {
        guard ownsConnection else { return }
        ownsConnection = false
        guard ownership.owns(id), environment.contextIsCurrent() else { return }
        if let readyID = environment.readySession() { closedReadySessions.insert(readyID) }
        ownership.recordClose(target: target, at: now())
        cleaning = true
        diagnostic("close_requested")
        environment.disconnect()
        cleaning = false
    }

    private func cancelRecovery() {
        cancelConnect?()
        cancelDeadline?()
        cancelBudget?()
        cancelConnect = nil
        cancelDeadline = nil
        cancelBudget = nil
        startedAt = nil
        sentAttempt = false
    }

    private func resetState() {
        machine = GatewayDetailProxyConnectionStateMachine(targetAddress: machine.targetAddress)
        onStateChange?()
    }

    private func diagnostic(_ event: String) {
        onDiagnostic?("page=\(id) count=\(attemptCount) uptime=\(now()) \(event)")
    }
}
