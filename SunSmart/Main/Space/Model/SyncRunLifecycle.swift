import Foundation

/// 保护轮次身份和等待的生命周期；不持有 UI、Node 或任务模型。
final class SyncRunLifecycle {
    private let lock = NSLock()
    private var currentIdentifier = UUID()
    private var active = false
    private var waiters: [ObjectIdentifier: SyncRunWaiter] = [:]

    var identifier: UUID {
        lock.lock()
        defer { lock.unlock() }
        return currentIdentifier
    }

    func begin() -> UUID {
        replace(active: true)
    }

    @discardableResult
    func invalidate() -> UUID {
        replace(active: false)
    }

    private func replace(active: Bool) -> UUID {
        lock.lock()
        let pending = Array(waiters.values)
        waiters.removeAll()
        currentIdentifier = UUID()
        self.active = active
        let identifier = currentIdentifier
        lock.unlock()
        pending.forEach { $0.signal() }
        return identifier
    }

    func isCurrent(_ identifier: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return identifier == currentIdentifier
    }

    func isActive(_ identifier: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active && identifier == currentIdentifier
    }

    /// 主线程收尾前领取一次完成权。迟到回调和重复收尾都不能再次发布结果。
    func claimCompletion(_ identifier: UUID) -> Bool {
        lock.lock()
        guard active, identifier == currentIdentifier else { lock.unlock(); return false }
        active = false
        let pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.signal() }
        return true
    }

    func makeWaiter(for identifier: UUID) -> SyncRunWaiter? {
        lock.lock()
        defer { lock.unlock() }
        guard active, identifier == currentIdentifier else { return nil }
        let waiter = SyncRunWaiter()
        waiters[ObjectIdentifier(waiter)] = waiter
        return waiter
    }

    func finishWaiting(_ waiter: SyncRunWaiter) {
        lock.lock()
        waiters.removeValue(forKey: ObjectIdentifier(waiter))
        lock.unlock()
        waiter.signal()
    }
}

/// STOP 可以独立唤醒等待者，不依赖 SDK 是否保留原 finished 回调。
final class SyncRunWaiter {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var signalled = false

    func signal() {
        lock.lock()
        guard !signalled else { lock.unlock(); return }
        signalled = true
        lock.unlock()
        semaphore.signal()
    }

    @discardableResult
    func wait(timeout: DispatchTime = .distantFuture) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }
}

/// SDK 的每次发送尝试仅允许一次完成回写；重试会创建新的领取器。
final class SyncAttemptCompletionGate {
    private let lock = NSLock()
    private var completed = false

    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
