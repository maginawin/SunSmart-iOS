import Foundation

enum GatewayDetailTimeZoneSource: Equatable {
    case site
    case phoneFallback
}

struct GatewayDetailTargetTimeZone: Equatable {
    let identifier: String
    let offsetMinutes: Int
    let source: GatewayDetailTimeZoneSource

    var displayOffset: String {
        let sign = offsetMinutes < 0 ? "-" : "+"
        let magnitude = abs(offsetMinutes)
        return String(format: "UTC%@%02d:%02d", sign, magnitude / 60, magnitude % 60)
    }

    var isMeshEncodable: Bool {
        let encodedOffset = offsetMinutes / 15 + 64
        return offsetMinutes.isMultiple(of: 15)
            && (0...Int(UInt8.max)).contains(encodedOffset)
    }

    var fixedTimeZone: TimeZone? {
        TimeZone(secondsFromGMT: offsetMinutes * 60)
    }
}

enum GatewayDetailTimeZoneResolver {
    static func resolve(
        storageValue: String?,
        phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> GatewayDetailTargetTimeZone {
        if let storageValue,
           let value = SiteTimeZoneValue(storageValue: storageValue) {
            return GatewayDetailTargetTimeZone(
                identifier: value.ianaId,
                offsetMinutes: value.offsetMinutes,
                source: .site
            )
        }

        return GatewayDetailTargetTimeZone(
            identifier: phoneTimeZone.identifier,
            offsetMinutes: phoneTimeZone.secondsFromGMT(for: date) / 60,
            source: .phoneFallback
        )
    }
}

struct GatewayDetailClockSample: Equatable {
    let seconds: UInt64
    let subSecond: UInt8
    let offsetMinutes: Int
}

struct GatewayDetailClockState: Equatable {
    private(set) var sample: GatewayDetailClockSample?
    private(set) var offBySeconds: Int?
    private(set) var requiresSync = false
    private(set) var isSyncing = false

    mutating func accept(
        sample: GatewayDetailClockSample,
        offBySeconds: Int,
        targetOffsetMinutes: Int,
        targetIsMeshEncodable: Bool = true
    ) {
        self.sample = sample
        self.offBySeconds = offBySeconds
        requiresSync = !targetIsMeshEncodable
            || sample.offsetMinutes != targetOffsetMinutes
    }

    mutating func completeSync(
        sample: GatewayDetailClockSample,
        offBySeconds: Int,
        targetOffsetMinutes: Int,
        targetIsMeshEncodable: Bool = true
    ) {
        accept(
            sample: sample,
            offBySeconds: offBySeconds,
            targetOffsetMinutes: targetOffsetMinutes,
            targetIsMeshEncodable: targetIsMeshEncodable
        )
        isSyncing = false
    }

    mutating func failRead() {
        requiresSync = true
    }

    mutating func beginSync() {
        isSyncing = true
    }

    mutating func failSync() {
        isSyncing = false
        requiresSync = true
    }
}

final class GatewayDetailClockFormatter {
    private let formatter: DateFormatter

    init() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-M-d hh:mm:ss a"
        self.formatter = formatter
    }

    func format(date: Date, offsetMinutes: Int) -> String {
        formatter.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60)
        return formatter.string(from: date)
    }
}

enum GatewayDetailClockCore {
    static let meshEpochOffset: TimeInterval = 946_684_800
    static let syncToleranceSeconds = 30
    static let minimumSyncPresentationDuration: TimeInterval = 1

    static func remainingSyncPresentationDuration(
        startedAtUptime: TimeInterval,
        completedAtUptime: TimeInterval
    ) -> TimeInterval {
        let elapsed = max(0, completedAtUptime - startedAtUptime)
        return max(0, minimumSyncPresentationDuration - elapsed)
    }

    static func offBySeconds(
        localDate: Date,
        targetOffsetMinutes: Int,
        sample: GatewayDetailClockSample
    ) -> Int {
        let localWallTime = localDate.timeIntervalSince1970
            + TimeInterval(targetOffsetMinutes * 60)
        let gatewayWallTime = TimeInterval(sample.seconds)
            + meshEpochOffset
            + TimeInterval(sample.subSecond) / 256
            + TimeInterval(sample.offsetMinutes * 60)
        return Int((gatewayWallTime - localWallTime).rounded())
    }

    static func formatOffBy(seconds: Int) -> String {
        guard seconds != 0 else { return "0s" }
        let sign = seconds > 0 ? "+" : "-"
        let magnitude = abs(seconds)
        if magnitude < 60 {
            return "\(sign)\(magnitude)s"
        }
        return "\(sign)\(magnitude / 60)m \(magnitude % 60)s"
    }

    static func isWithinTolerance(seconds: Int) -> Bool {
        abs(seconds) <= syncToleranceSeconds
    }

    static func isVerifiedSync(
        targetOffsetMinutes: Int,
        sampleOffsetMinutes: Int,
        offBySeconds: Int
    ) -> Bool {
        targetOffsetMinutes == sampleOffsetMinutes
            && isWithinTolerance(seconds: offBySeconds)
    }

    static func isDisplayable(sample: GatewayDetailClockSample) -> Bool {
        guard sample.seconds > 0,
              TimeZone(secondsFromGMT: sample.offsetMinutes * 60) != nil else {
            return false
        }
        let date = Date(
            timeIntervalSince1970: TimeInterval(sample.seconds) + meshEpochOffset
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.year, from: date)
        return (2000...9999).contains(year)
    }

    static func format(date: Date, offsetMinutes: Int) -> String {
        GatewayDetailClockFormatter().format(
            date: date,
            offsetMinutes: offsetMinutes
        )
    }

    static func gatewayDisplayDate(localDate: Date, offBySeconds: Int) -> Date {
        localDate.addingTimeInterval(TimeInterval(offBySeconds))
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

enum GatewayDetailClockCoordinatorError: Error {
    case disconnected
    case targetOffsetUnencodable
    case missingTimeModels
    case missingApplicationKey
    case modelBindingFailed
    case timeSetFailed
    case timeGetFailed
    case readbackVerificationFailed
    case localPersistenceFailed
}

final class GatewayDetailClockCoordinator {
    typealias ReadCompletion = (Result<(GatewayDetailClockSample, Int), GatewayDetailClockCoordinatorError>) -> Void
    typealias SyncCompletion = (Result<(GatewayDetailClockSample, Int), GatewayDetailClockCoordinatorError>) -> Void

    private struct NodeTimeBackup {
        let timestamp: UInt64
        let timeZone: TimeZone?
    }

    private let context: GatewayInformationContext
    private var activeOperationID: UUID?
    private var activeBackup: NodeTimeBackup?
    private var isAttached = true

    init(context: GatewayInformationContext) {
        self.context = context
    }

    @discardableResult
    func read(
        target: GatewayDetailTargetTimeZone,
        completion: @escaping ReadCompletion
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isAttached, activeOperationID == nil else { return false }
        guard isCurrentProxyReady() else {
            completion(.failure(.disconnected))
            return false
        }
        guard let model = context.node.timeModel else {
            completion(.failure(.missingTimeModels))
            return false
        }

        let operationID = UUID()
        activeOperationID = operationID
        let backup = makeBackup()
        activeBackup = backup
        sendTimeGet(model: model) { [self] result in
            DispatchQueue.main.async {
                guard self.finishOperation(operationID) else { return }
                switch result {
                case .success(let sample):
                    let offBy = GatewayDetailClockCore.offBySeconds(
                        localDate: Date(),
                        targetOffsetMinutes: target.offsetMinutes,
                        sample: sample
                    )
                    guard self.persist(sample: sample) else {
                        self.restore(backup)
                        completion(.failure(.localPersistenceFailed))
                        return
                    }
                    self.markGatewayDirtyAndSync()
                    completion(.success((sample, offBy)))
                case .failure(let error):
                    self.restore(backup)
                    completion(.failure(error))
                }
            }
        }
        return true
    }

    @discardableResult
    func synchronize(
        target: GatewayDetailTargetTimeZone,
        completion: @escaping SyncCompletion
    ) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isAttached, activeOperationID == nil else { return false }
        guard target.isMeshEncodable, let fixedTimeZone = target.fixedTimeZone else {
            completion(.failure(.targetOffsetUnencodable))
            return false
        }
        guard isCurrentProxyReady() else {
            completion(.failure(.disconnected))
            return false
        }
        let node = context.node
        guard let timeModel = node.timeModel,
              let timeSetupModel = node.timeSetupModel else {
            completion(.failure(.missingTimeModels))
            return false
        }
        guard MeshNetworkManager.instance.meshNetwork != nil else {
            completion(.failure(.missingApplicationKey))
            return false
        }

        let currentApplicationKey = MeshNetworkManager.instance.currentApplicationKey
        guard let applicationKey = node.applicationKeys.first(where: {
            $0.index == currentApplicationKey.index
        }) else {
            completion(.failure(.missingApplicationKey))
            return false
        }
        let operationID = UUID()
        activeOperationID = operationID
        let backup = makeBackup()
        activeBackup = backup
        bindIfNeeded(
            models: [timeModel, timeSetupModel],
            applicationKey: applicationKey,
            operationID: operationID
        ) { [self] bindingSucceeded in
            guard self.activeOperationID == operationID else { return }
            guard bindingSucceeded, self.isCurrentProxyReady() else {
                self.failSync(
                    operationID: operationID,
                    backup: backup,
                    error: bindingSucceeded ? .disconnected : .modelBindingFailed,
                    completion: completion
                )
                return
            }

            let message = Node.setLocalTimeMessage(date: Date(), timeZone: fixedTimeZone)
            MeshAPI.sendMessage(message: message, model: timeSetupModel, timeout: 10) { [self] response in
                DispatchQueue.main.async {
                    guard self.activeOperationID == operationID else { return }
                    guard let status = response as? TimeStatus,
                          status.time.seconds > 0,
                          status.time.tzOffset.secondsFromGMT() / 60 == target.offsetMinutes,
                          self.isCurrentProxyReady() else {
                        self.failSync(
                            operationID: operationID,
                            backup: backup,
                            error: .timeSetFailed,
                            completion: completion
                        )
                        return
                    }
                    self.sendFinalReadback(
                        operationID: operationID,
                        target: target,
                        model: timeModel,
                        backup: backup,
                        completion: completion
                    )
                }
            }
        }
        return true
    }

    func finishPage() {
        dispatchPrecondition(condition: .onQueue(.main))
        isAttached = false
    }

    private func sendFinalReadback(
        operationID: UUID,
        target: GatewayDetailTargetTimeZone,
        model: Model,
        backup: NodeTimeBackup,
        completion: @escaping SyncCompletion
    ) {
        sendTimeGet(model: model) { [self] result in
            DispatchQueue.main.async {
                guard self.activeOperationID == operationID else { return }
                switch result {
                case .success(let sample):
                    let offBy = GatewayDetailClockCore.offBySeconds(
                        localDate: Date(),
                        targetOffsetMinutes: target.offsetMinutes,
                        sample: sample
                    )
                    guard GatewayDetailClockCore.isVerifiedSync(
                        targetOffsetMinutes: target.offsetMinutes,
                        sampleOffsetMinutes: sample.offsetMinutes,
                        offBySeconds: offBy
                    ) else {
                        self.failSync(
                            operationID: operationID,
                            backup: backup,
                            error: .readbackVerificationFailed,
                            completion: completion
                        )
                        return
                    }
                    guard self.finishOperation(operationID) else { return }
                    guard self.persist(sample: sample) else {
                        self.restore(backup)
                        completion(.failure(.localPersistenceFailed))
                        return
                    }
                    self.markGatewayDirtyAndSync()
                    completion(.success((sample, offBy)))
                case .failure:
                    self.failSync(
                        operationID: operationID,
                        backup: backup,
                        error: .timeGetFailed,
                        completion: completion
                    )
                }
            }
        }
    }

    private func bindIfNeeded(
        models: [Model],
        applicationKey: ApplicationKey,
        operationID: UUID,
        completion: @escaping (Bool) -> Void
    ) {
        guard activeOperationID == operationID else { return }
        guard let model = models.first else {
            completion(true)
            return
        }
        let remaining = Array(models.dropFirst())
        guard !model.isBoundTo(applicationKey) else {
            bindIfNeeded(
                models: remaining,
                applicationKey: applicationKey,
                operationID: operationID,
                completion: completion
            )
            return
        }
        guard let message = ConfigModelAppBind(applicationKey: applicationKey, to: model) else {
            completion(false)
            return
        }

        do {
            try MeshNetworkManager.instance.send(message, to: context.node) { [self] result in
                DispatchQueue.main.async {
                    guard self.activeOperationID == operationID else { return }
                    guard case .success(let response) = result,
                          let status = response as? ConfigModelAppStatus,
                          status.status == .success,
                          status.applicationKeyIndex == applicationKey.index,
                          status.elementAddress == model.parentElement?.unicastAddress,
                          status.modelIdentifier == model.modelIdentifier,
                          status.companyIdentifier == model.companyIdentifier else {
                        completion(false)
                        return
                    }
                    self.bindIfNeeded(
                        models: remaining,
                        applicationKey: applicationKey,
                        operationID: operationID,
                        completion: completion
                    )
                }
            }
        } catch {
            completion(false)
        }
    }

    private func sendTimeGet(
        model: Model,
        completion: @escaping (Result<GatewayDetailClockSample, GatewayDetailClockCoordinatorError>) -> Void
    ) {
        MeshAPI.sendMessage(message: TimeGet(), model: model, timeout: 10) { response in
            guard let status = response as? TimeStatus,
                  status.time.seconds > 0 else {
                completion(.failure(.timeGetFailed))
                return
            }
            let sample = GatewayDetailClockSample(
                seconds: status.time.seconds,
                subSecond: status.time.subSecond,
                offsetMinutes: status.time.tzOffset.secondsFromGMT() / 60
            )
            guard GatewayDetailClockCore.isDisplayable(sample: sample) else {
                completion(.failure(.timeGetFailed))
                return
            }
            completion(.success(sample))
        }
    }

    private func failSync(
        operationID: UUID,
        backup: NodeTimeBackup,
        error: GatewayDetailClockCoordinatorError,
        completion: @escaping SyncCompletion
    ) {
        guard finishOperation(operationID) else { return }
        restore(backup)
        completion(.failure(error))
    }

    private func finishOperation(_ operationID: UUID) -> Bool {
        guard activeOperationID == operationID else { return false }
        activeOperationID = nil
        let backup = activeBackup
        activeBackup = nil
        guard isAttached else {
            if let backup {
                restore(backup)
            }
            return false
        }
        return true
    }

    private func isCurrentProxyReady() -> Bool {
        let address = context.node.primaryUnicastAddress
        return MeshLibManager.manager.currentProxyReadyContext?.nodeAddress == address
            && MeshLibManager.manager.currentProxy?.nodeAddress == address
    }

    private func makeBackup() -> NodeTimeBackup {
        NodeTimeBackup(
            timestamp: context.node.timestamp,
            timeZone: context.node.timezone
        )
    }

    private func restore(_ backup: NodeTimeBackup) {
        context.node.timestamp = backup.timestamp
        context.node.timezone = backup.timeZone
        _ = context.node.savePropertys()
    }

    private func persist(sample: GatewayDetailClockSample) -> Bool {
        let node = context.node
        node.timestamp = sample.seconds
        node.timezone = TimeZone(secondsFromGMT: sample.offsetMinutes * 60)
        return node.savePropertys()
    }

    private func markGatewayDirtyAndSync() {
        let gatewayModel = context.gatewayModel
        gatewayModel.lastUpdate = GatewayCloudSyncGenerationPolicy.next(
            now: Int64(Date().timeIntervalSince1970),
            current: gatewayModel.lastUpdate,
            uploaded: gatewayModel.lastUploadCloudTimestamp
        )
        gatewayModel.syncCloudError = nil
        guard gatewayModel.save() else { return }
        CloudSynchronizationManager.shared.addSynchronizationHandle(
            operation: .syncGateway(gateway: gatewayModel, node: context.node),
            level: .promptly
        )
    }
}
#endif
