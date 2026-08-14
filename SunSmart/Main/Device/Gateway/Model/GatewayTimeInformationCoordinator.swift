import Foundation

struct GatewayTimeInformationSnapshot: Equatable {
    let seconds: UInt64
    let offsetMinutes: Int
    let dateTimeText: String
    let timeZoneText: String
}

enum GatewayTimeInformationDecision: Equatable {
    case success(GatewayTimeInformationSnapshot)
    case failure(showError: Bool)
    case restoreOnly
    case ignored
}

enum GatewayTimeInformationFormatter {
    static let meshEpochOffset: TimeInterval = 946_684_800

    static func makeSnapshot(
        seconds: UInt64,
        offsetMinutes: Int
    ) -> GatewayTimeInformationSnapshot? {
        guard seconds > 0,
              let timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let sign = offsetMinutes < 0 ? "-" : "+"
        let absoluteMinutes = abs(offsetMinutes)
        let timeZoneText = String(
            format: "UTC%@%02d:%02d",
            sign,
            absoluteMinutes / 60,
            absoluteMinutes % 60
        )
        let date = Date(
            timeIntervalSince1970: TimeInterval(seconds) + meshEpochOffset
        )

        return GatewayTimeInformationSnapshot(
            seconds: seconds,
            offsetMinutes: offsetMinutes,
            dateTimeText: formatter.string(from: date),
            timeZoneText: timeZoneText
        )
    }
}

struct GatewayTimeInformationAttemptCore {
    private var activeAttemptID: UUID?
    private var isAttached = true

    mutating func begin() -> UUID? {
        guard activeAttemptID == nil, isAttached else { return nil }
        let attemptID = UUID()
        activeAttemptID = attemptID
        return attemptID
    }

    mutating func receive(
        attemptID: UUID,
        seconds: UInt64,
        offsetMinutes: Int
    ) -> GatewayTimeInformationDecision {
        guard activeAttemptID == attemptID else { return .ignored }
        activeAttemptID = nil
        guard isAttached else { return .restoreOnly }
        guard let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: seconds,
            offsetMinutes: offsetMinutes
        ) else {
            return .failure(showError: true)
        }
        return .success(snapshot)
    }

    mutating func fail(attemptID: UUID) -> GatewayTimeInformationDecision {
        guard activeAttemptID == attemptID else { return .ignored }
        activeAttemptID = nil
        return isAttached ? .failure(showError: true) : .restoreOnly
    }

    mutating func detach() {
        isAttached = false
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct GatewayInformationContext {
    let site: SiteData
    let gateway: Gateway

    var node: Node { gateway.node }
    var gatewayModel: GatewayModel { gateway.model }
}

enum GatewayTimeInformationReadState: Equatable {
    case disconnected
    case reading
    case succeeded(GatewayTimeInformationSnapshot)
    case failed
}

final class GatewayTimeInformationCoordinator {
    var onReadState: ((GatewayTimeInformationReadState) -> Void)?
    var onCloudFailure: (() -> Void)?

    private struct RuntimeAttempt {
        let id: UUID
        let previousTimestamp: UInt64
        let previousTimeZone: TimeZone?
    }

    private let context: GatewayInformationContext
    private var core = GatewayTimeInformationAttemptCore()
    private var runtimeAttempt: RuntimeAttempt?
    private var isPageAttached = true

    init(context: GatewayInformationContext) {
        self.context = context
    }

    @discardableResult
    func read() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isPageAttached else { return false }

        let node = context.node
        let manager = MeshLibManager.manager
        guard let readyContext = manager.currentProxyReadyContext,
              readyContext.nodeAddress == node.primaryUnicastAddress,
              manager.currentProxy?.nodeAddress == node.primaryUnicastAddress else {
            onReadState?(.disconnected)
            return false
        }
        guard let model = node.timeModel else {
            onReadState?(.failed)
            return false
        }
        guard let attemptID = core.begin() else { return false }

        runtimeAttempt = RuntimeAttempt(
            id: attemptID,
            previousTimestamp: node.timestamp,
            previousTimeZone: node.timezone
        )
        onReadState?(.reading)
        MeshAPI.sendMessage(message: TimeGet(), model: model, timeout: 10) { [self] response in
            DispatchQueue.main.async {
                settle(attemptID: attemptID, response: response)
            }
        }
        return true
    }

    func finishPage() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isPageAttached else { return }
        isPageAttached = false
        core.detach()
    }

    private func settle(attemptID: UUID, response: StaticMeshResponse?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let runtimeAttempt, runtimeAttempt.id == attemptID else { return }

        guard let status = response as? TimeStatus else {
            let decision = core.fail(attemptID: attemptID)
            if response != nil {
                restoreNode(using: runtimeAttempt)
            }
            finishRead(attemptID: attemptID, decision: decision)
            return
        }

        let offsetMinutes = status.time.tzOffset.secondsFromGMT() / 60
        let decision = core.receive(
            attemptID: attemptID,
            seconds: status.time.seconds,
            offsetMinutes: offsetMinutes
        )
        switch decision {
        case .success(let snapshot):
            let node = context.node
            node.timestamp = status.time.seconds
            node.timezone = status.time.tzOffset
            guard node.savePropertys() else {
                restoreNode(using: runtimeAttempt)
                finishRead(attemptID: attemptID, decision: .failure(showError: true))
                return
            }
            self.runtimeAttempt = nil
            onReadState?(.succeeded(snapshot))
            markGatewayDirtyAndSync()
        case .failure, .restoreOnly:
            restoreNode(using: runtimeAttempt)
            finishRead(attemptID: attemptID, decision: decision)
        case .ignored:
            break
        }
    }

    private func finishRead(
        attemptID: UUID,
        decision: GatewayTimeInformationDecision
    ) {
        guard runtimeAttempt?.id == attemptID else { return }
        runtimeAttempt = nil
        guard isPageAttached else { return }
        if case .failure(let showError) = decision, showError {
            onReadState?(.failed)
        }
    }

    private func restoreNode(using attempt: RuntimeAttempt) {
        let node = context.node
        node.timestamp = attempt.previousTimestamp
        node.timezone = attempt.previousTimeZone
        _ = node.savePropertys()
    }

    private func markGatewayDirtyAndSync() {
        let node = context.node
        let gatewayModel = context.gatewayModel
        gatewayModel.lastUpdate = GatewayCloudSyncGenerationPolicy.next(
            now: Int64(Date().timeIntervalSince1970),
            current: gatewayModel.lastUpdate,
            uploaded: gatewayModel.lastUploadCloudTimestamp
        )
        gatewayModel.syncCloudError = nil
        guard gatewayModel.save() else {
            onCloudFailure?()
            return
        }

        CloudSynchronizationManager.shared.addSynchronizationHandle(
            operation: .syncGateway(gateway: gatewayModel, node: node),
            level: .promptly
        ) { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.isPageAttached else { return }
                switch state {
                case .failure, .cancel:
                    self.onCloudFailure?()
                case .wait, .inProgress, .successful:
                    break
                }
            }
        }
    }
}
#endif
