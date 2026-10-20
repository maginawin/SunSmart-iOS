import Foundation

/// One shared transport owner, with durable results for the complete device target.
final class HDBLightingZoneExecutor {
    private let coordinator: SyncSessionCoordinator
    private let send: (HDBZoneOperation, @escaping (HDBZoneReceipt) -> Void) -> Void
    private let stop: (@escaping () -> Void) -> Void
    private let isCurrent: () -> Bool
    private let persist: (HDBZoneReceipt) throws -> Void
    private var operations: [HDBZoneOperation] = []
    private var blockedNodes = Set<UUID>()
    private var completion: (() -> Void)?
    private(set) var isRunning = false
    private(set) var error: Error?

    init(lane: SyncSessionTransportLane = .shared,
         send: @escaping (HDBZoneOperation, @escaping (HDBZoneReceipt) -> Void) -> Void,
         stop: @escaping (@escaping () -> Void) -> Void,
         isCurrent: @escaping () -> Bool, persist: @escaping (HDBZoneReceipt) throws -> Void) {
        coordinator = SyncSessionCoordinator(lane: lane)
        self.send = send; self.stop = stop; self.isCurrent = isCurrent; self.persist = persist
    }

    func start(_ operations: [HDBZoneOperation], completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard !isRunning else { return }
        self.operations = operations; self.completion = completion
        blockedNodes = []; error = nil; isRunning = true
        coordinator.start { [weak self] identifier in self?.next(identifier) }
    }

    private func next(_ identifier: UUID) {
        guard coordinator.lifecycle.isActive(identifier) else { return }
        guard isCurrent() else { error = HDBConfigurationError.unavailable; cancel(); return }
        while let first = operations.first,
              blockedNodes.contains(first.nodeUuid) {
            operations.removeFirst()
        }
        guard !operations.isEmpty else { finish(identifier); return }
        let operation = operations.removeFirst()
        guard !operation.subscriptions.isEmpty else { error = HDBConfigurationError.unsupportedModels; finish(identifier); return }
        let gate = SyncAttemptCompletionGate()
        send(operation) { [weak self] receipt in
            guard let self = self, self.coordinator.lifecycle.isActive(identifier), gate.claim() else { return }
            guard self.isCurrent(), receipt.operation == operation else {
                self.error = HDBConfigurationError.unavailable; self.cancel(); return
            }
            do { try self.persist(receipt) }
            catch { self.error = error; self.finish(identifier); return }
            if !receipt.successful {
                if self.error == nil { self.error = receipt.error ?? HDBConfigurationError.responseMismatch }
                self.blockedNodes.insert(operation.nodeUuid)
            }
            self.next(identifier)
        }
    }

    private func finish(_ identifier: UUID) {
        coordinator.finish(identifier, settle: { $0() }) { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            let callback = self.completion; self.completion = nil
            callback?()
        }
    }

    func cancel() {
        precondition(Thread.isMainThread)
        operations = []
        coordinator.stop { [self] done in
            stop { [self] in
                completeCancellation()
                done()
            }
        }
        if !coordinator.isSettling { completeCancellation() }
    }

    private func completeCancellation() {
        isRunning = false
        let callback = completion; completion = nil
        callback?()
    }
}
