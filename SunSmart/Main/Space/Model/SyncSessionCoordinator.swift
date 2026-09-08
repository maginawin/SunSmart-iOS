import Foundation

/// Sync Devices 会话共享发送通道；前一会话停止和补偿完成后才交给后一会话。
final class SyncSessionTransportLane {
    static let shared = SyncSessionTransportLane()
    private var owner: UUID?
    private var waiting: [(UUID, () -> Void)] = []

    func acquire(_ identifier: UUID, ready: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard owner != identifier, !waiting.contains(where: { $0.0 == identifier }) else { return }
        if owner == nil {
            owner = identifier
            ready()
        } else {
            waiting.append((identifier, ready))
        }
    }

    func cancel(_ identifier: UUID) {
        precondition(Thread.isMainThread)
        waiting.removeAll { $0.0 == identifier }
    }

    func release(_ identifier: UUID) {
        precondition(Thread.isMainThread)
        guard owner == identifier else { return }
        owner = nil
        if !waiting.isEmpty {
            let next = waiting.removeFirst()
            owner = next.0
            next.1()
        }
    }
}

/// 主线程拥有轮次、通道及补偿边界；所有异步完成必须返回主线程。
final class SyncSessionCoordinator {
    private enum Phase { case idle, waiting, running, settling }
    private let owner = UUID()
    private let lane: SyncSessionTransportLane
    let lifecycle = SyncRunLifecycle()
    private var phase = Phase.idle
    private var pendingStart: ((UUID) -> Void)?
    private var completion: (() -> Void)?
    private(set) var closed = false

    init(lane: SyncSessionTransportLane = .shared) { self.lane = lane }
    var identifier: UUID { lifecycle.identifier }
    var isSettling: Bool { phase == .settling }
    var isRunning: Bool { phase == .running }

    func start(_ action: @escaping (UUID) -> Void) {
        precondition(Thread.isMainThread)
        guard !closed, phase != .running else { return }
        pendingStart = action
        drain()
    }

    private func drain() {
        guard !closed, phase == .idle, pendingStart != nil else { return }
        phase = .waiting
        lane.acquire(owner) { [self] in
            guard !closed, let action = pendingStart else {
                phase = .idle
                lane.release(owner)
                return
            }
            pendingStart = nil
            phase = .running
            action(lifecycle.begin())
        }
    }

    func stop(settle: (@escaping () -> Void) -> Void) {
        precondition(Thread.isMainThread)
        pendingStart = nil
        completion = nil
        lifecycle.invalidate()
        if phase == .waiting {
            lane.cancel(owner)
            phase = .idle
        } else if phase == .running {
            phase = .settling
            let gate = SyncAttemptCompletionGate()
            settle { [self] in
                precondition(Thread.isMainThread)
                guard gate.claim() else { return }
                releaseAndDrain()
            }
        }
        // 已在补偿时不再次停止 SDK，否则会替换补偿自己的完成回调。
    }

    func finish(_ identifier: UUID, settle: (@escaping () -> Void) -> Void, finished: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard phase == .running, lifecycle.claimCompletion(identifier) else { return }
        phase = .settling
        completion = finished
        let gate = SyncAttemptCompletionGate()
        settle { [self] in
            precondition(Thread.isMainThread)
            guard gate.claim() else { return }
            let callback = completion
            completion = nil
            if !closed { callback?() }
            releaseAndDrain()
        }
    }

    private func releaseAndDrain() {
        phase = .idle
        lane.release(owner)
        drain()
    }

    func close(idleCleanup: ((@escaping () -> Void) -> Void)? = nil, settle: (@escaping () -> Void) -> Void) {
        precondition(Thread.isMainThread)
        guard !closed else { return }
        let needsIdleCleanup = phase == .idle || phase == .waiting
        closed = true
        stop(settle: settle)
        if needsIdleCleanup, let idleCleanup {
            phase = .waiting
            lane.acquire(owner) { [self] in
                phase = .settling
                let gate = SyncAttemptCompletionGate()
                idleCleanup { [self] in
                    precondition(Thread.isMainThread)
                    guard gate.claim() else { return }
                    releaseAndDrain()
                }
            }
        }
    }
}
