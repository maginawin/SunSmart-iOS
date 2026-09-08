import Foundation

/// SDK 在后台安装首批队列；收到其开始事件前，不能把 isBusy == false 当作停止完成。
final class SyncCommandStopGate {
    private var batch: UUID?
    private var ready = false
    private var stopAction: (() -> Void)?
    private var stopCompletion: (() -> Void)?

    func submitted() -> UUID {
        precondition(Thread.isMainThread)
        let identifier = UUID()
        batch = identifier
        ready = false
        return identifier
    }

    func started(_ identifier: UUID) {
        precondition(Thread.isMainThread)
        guard batch == identifier else { return }
        ready = true
        let action = stopAction
        stopAction = nil
        action?()
    }

    func finished(_ identifier: UUID) {
        precondition(Thread.isMainThread)
        guard batch == identifier else { return }
        batch = nil
        ready = false
        stopAction = nil
        let completion = stopCompletion
        stopCompletion = nil
        completion?()
    }

    func stop(using action: @escaping (@escaping () -> Void) -> Void, completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard let identifier = batch else { completion(); return }
        guard stopCompletion == nil else { return }
        stopCompletion = completion
        let request = { [self] in action { self.finished(identifier) } }
        if ready { request() } else { stopAction = request }
    }
}
