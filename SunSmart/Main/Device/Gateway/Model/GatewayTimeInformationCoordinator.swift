import Foundation

struct GatewayTimeInformationSnapshot: Equatable {
    let seconds: UInt64
    let taiDelta: Int16
    let offsetMinutes: Int
    let dateTimeText: String
    let timeZoneText: String
}

enum GatewayTimeInformationFormatter {
    static func makeSnapshot(
        seconds: UInt64,
        subSecond: UInt8,
        taiDelta: Int16,
        offsetMinutes: Int
    ) -> GatewayTimeInformationSnapshot? {
        guard let date = MeshTimeConversion.date(
                seconds: seconds, subSecond: subSecond, taiDelta: taiDelta
              ),
              date.timeIntervalSince1970 >= MeshTimeConversion.unixEpochOffset,
              date.timeIntervalSince1970 < 253_402_300_800,
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
        return GatewayTimeInformationSnapshot(
            seconds: seconds,
            taiDelta: taiDelta,
            offsetMinutes: offsetMinutes,
            dateTimeText: formatter.string(from: date),
            timeZoneText: timeZoneText
        )
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
    private let context: GatewayInformationContext
    private var recovery: InformationClockRecovery?
    private var isPageAttached = true

    init(context: GatewayInformationContext) {
        self.context = context
    }

    deinit { recovery?.detach() }

    @discardableResult
    func read() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isPageAttached, recovery == nil else { return false }
        let node = context.node
        let manager = MeshLibManager.manager
        guard let readyContext = manager.currentProxyReadyContext,
              readyContext.nodeAddress == node.primaryUnicastAddress,
              manager.currentProxy?.nodeAddress == node.primaryUnicastAddress else {
            onReadState?(.disconnected)
            return false
        }
        guard let transport = InformationClockMeshTransport(
            node: node,
            requiresDirectProxy: true,
            canConfigure: { [context] in context.site.canConfigureGateway(context.gatewayModel) }
        ) else {
            onReadState?(.failed)
            return false
        }
        let operation = InformationClockRecovery(transport: transport)
        recovery = operation
        operation.onFinish = { [weak self] sample in
            guard let self, self.isPageAttached else { return }
            self.recovery = nil
            guard let sample,
                  let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
                    seconds: sample.seconds, subSecond: sample.subSecond,
                    taiDelta: sample.taiDelta, offsetMinutes: sample.offsetMinutes
                  ) else {
                self.onReadState?(.failed)
                return
            }
            self.onReadState?(.succeeded(snapshot))
            self.markGatewayDirtyAndSync()
        }
        onReadState?(.reading)
        return operation.start()
    }

    func finishPage() {
        dispatchPrecondition(condition: .onQueue(.main))
        isPageAttached = false
        recovery?.detach()
        recovery = nil
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
            logCloudFailure()
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
                    self.logCloudFailure()
                case .wait, .inProgress, .successful:
                    break
                }
            }
        }
    }

    private func logCloudFailure() {
        #if DEBUG
        print("[InformationClock] Gateway time cloud synchronization failed")
        #endif
    }
}
#endif
