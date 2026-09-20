import Foundation

enum InformationTTLFailure: Equatable {
    case permission, disconnected, unavailable, readFailed, unconfirmed, mismatch
    case localSave, cloudSync
}

enum InformationTTLPhase: Equatable {
    case idle, reading, writing, verifying, synchronizing
}

enum InformationTTLResult: Equatable {
    case read, updated, unchanged
    case failed(InformationTTLFailure)
}

enum InformationTTLValue {
    // Zero is valid on the wire and in existing devices, but is not offered as
    // an editable value in Information: it can prevent multi-hop responses.
    static func isValid(_ value: UInt8) -> Bool { value == 0 || (2...127).contains(value) }
    static func isEditable(_ value: UInt8) -> Bool { (2...127).contains(value) }

    static func parse(_ text: String) -> UInt8? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = UInt8(text), isEditable(value) else { return nil }
        return value
    }
}

enum InformationTTLCloudConfirmation {
    /// A completed older upload, or cancellation caused by task replacement,
    /// cannot acknowledge this edit. A confirmed newer snapshot can.
    static func result(target: Int64, uploaded: Int64, failed: Bool, expired: Bool) -> Bool? {
        if uploaded >= target { return true }
        if failed || expired { return false }
        return nil
    }
}

protocol InformationTTLService: AnyObject {
    var isCurrent: Bool { get }
    var readBlocker: InformationTTLFailure? { get }
    var writeBlocker: InformationTTLFailure? { get }
    var canSynchronize: Bool { get }
    var cachedTTL: UInt8? { get }
    var needsCloudSync: Bool { get }
    func getTTL(completion: @escaping (UInt8?) -> Void)
    func setTTL(_ value: UInt8, completion: @escaping (UInt8?) -> Void)
    func persist(_ value: UInt8, markCloudDirty: Bool) -> Bool
    func synchronize(completion: @escaping (Bool) -> Void)
}

/// Main-queue operation state. Device confirmation survives detaching the page;
/// only this operation's callbacks can advance its state.
final class InformationTTLCoordinator {
    private let service: InformationTTLService
    private var request: UUID?
    private var attached = true
    private var needsPersistence = false
    private var retryResult: InformationTTLResult = .updated
    private(set) var value: UInt8?
    private(set) var needsRetry = false
    private(set) var retryFailure: InformationTTLFailure = .cloudSync
    private(set) var phase: InformationTTLPhase = .idle
    var onChange: (() -> Void)?
    var onResult: ((InformationTTLResult) -> Void)?

    init(service: InformationTTLService) { self.service = service }

    @discardableResult
    func read() -> Bool {
        guard attached, phase == .idle else { return false }
        if let blocker = service.readBlocker { finish(.failed(blocker)); return false }
        let previous = service.cachedTTL
        value = nil
        let id = begin(.reading)
        service.getTTL { [self] response in
            guard claim(id), attached else { return }
            guard service.isCurrent else { finish(.failed(.unavailable)); return }
            guard let response, InformationTTLValue.isValid(response) else {
                finish(.failed(.readFailed)); return
            }
            accept(response, dirty: previous != response, result: .read)
        }
        return true
    }

    @discardableResult
    func update(_ target: UInt8) -> Bool {
        guard attached, phase == .idle, InformationTTLValue.isEditable(target), value != nil else { return false }
        if let blocker = service.writeBlocker { finish(.failed(blocker)); return false }
        guard target != value else { finish(.unchanged); return false }
        let id = begin(.writing)
        service.setTTL(target) { [self] response in
            guard claim(id) else { return }
            guard service.isCurrent else { value = nil; finish(.failed(.unconfirmed)); return }
            if response == target {
                accept(target, dirty: true, result: .updated)
            } else {
                verify(target)
            }
        }
        return true
    }

    private func verify(_ target: UInt8) {
        guard service.readBlocker == nil else { value = nil; finish(.failed(.unconfirmed)); return }
        let id = begin(.verifying)
        service.getTTL { [self] response in
            guard claim(id) else { return }
            guard service.isCurrent, let response, InformationTTLValue.isValid(response) else {
                value = nil; finish(.failed(.unconfirmed)); return
            }
            accept(response, dirty: true, result: response == target ? .updated : .failed(.mismatch))
        }
    }

    private func accept(_ confirmed: UInt8, dirty: Bool, result: InformationTTLResult) {
        value = confirmed
        retryResult = result
        needsPersistence = !service.persist(confirmed, markCloudDirty: dirty)
        if needsPersistence {
            needsRetry = true
            retryFailure = .localSave
            finish(.failed(.localSave))
        } else if dirty || service.needsCloudSync {
            sync(result: result)
        } else {
            needsRetry = false
            finish(result)
        }
    }

    @discardableResult
    func retry() -> Bool {
        guard attached, phase == .idle, needsRetry, let value else { return false }
        guard service.isCurrent, service.canSynchronize else { finish(.failed(.permission)); return false }
        if needsPersistence {
            guard service.persist(value, markCloudDirty: true) else { finish(.failed(.localSave)); return false }
            needsPersistence = false
        }
        sync(result: retryResult)
        return true
    }

    private func sync(result: InformationTTLResult) {
        needsRetry = true
        retryFailure = .cloudSync
        let id = begin(.synchronizing)
        service.synchronize { [self] successful in
            guard claim(id) else { return }
            needsRetry = !successful
            finish(successful ? result : .failed(.cloudSync))
        }
    }

    func detach() {
        attached = false
        onChange = nil
        onResult = nil
        // Reads have no user-confirmed mutation to finish. Issued writes and
        // persistence/upload continue, retained by their bounded callbacks.
        if phase == .reading { request = nil; phase = .idle }
    }

    private func begin(_ phase: InformationTTLPhase) -> UUID {
        let id = UUID()
        request = id
        self.phase = phase
        onChange?()
        return id
    }

    private func claim(_ id: UUID) -> Bool {
        guard request == id else { return false }
        request = nil
        return true
    }

    private func finish(_ result: InformationTTLResult) {
        phase = .idle
        onChange?()
        onResult?(result)
    }
}
