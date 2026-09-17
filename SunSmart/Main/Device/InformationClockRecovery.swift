import Foundation

struct InformationClockSample: Equatable {
    let seconds: UInt64
    let offsetMinutes: Int
    let taiDelta: Int16
    var subSecond: UInt8 = 0

    var utcDate: Date? {
        MeshTimeConversion.date(seconds: seconds, subSecond: subSecond, taiDelta: taiDelta)
    }

    var isValid: Bool {
        guard let utcDate else { return false }
        return utcDate.timeIntervalSince1970 >= MeshTimeConversion.unixEpochOffset
            && utcDate.timeIntervalSince1970 < 253_402_300_800
            && offsetMinutes.isMultiple(of: 15)
            && TimeZone(secondsFromGMT: offsetMinutes * 60) != nil
    }

    func matches(offset: Int, date: Date) -> Bool {
        guard isValid, let utcDate else { return false }
        return offsetMinutes == offset && abs(utcDate.timeIntervalSince(date)) <= 30
    }
}

enum InformationClockResponse {
    case sample(InformationClockSample)
    case noResponse
    case invalid
}

enum InformationClockModel: CaseIterable {
    case server, setup
}

protocol InformationClockTransport: AnyObject {
    var isCurrent: Bool { get }
    var canRecover: Bool { get }
    func isBound(_ model: InformationClockModel) -> Bool
    func bind(_ model: InformationClockModel, completion: @escaping (Bool) -> Void)
    func targetOffset(at date: Date) -> Int?
    func setTime(date: Date, offset: Int, completion: @escaping (InformationClockResponse) -> Void)
    func getTime(completion: @escaping (InformationClockResponse) -> Void)
    func persist(_ sample: InformationClockSample) -> Bool
    func finish()
}

/// One user request owns the complete read / recover / readback transaction.
/// A final readback can never re-enter recovery.
final class InformationClockRecovery {
    private enum Stage { case idle, reading, binding, setting, readback, finished }
    private var stage = Stage.idle
    private var callbackID = UUID()
    private var attached = true
    private let transport: InformationClockTransport
    private let now: () -> Date
    var onFinish: ((InformationClockSample?) -> Void)?

    init(transport: InformationClockTransport, now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.now = now
    }

    @discardableResult
    func start() -> Bool {
        guard stage == .idle, attached else { return false }
        guard transport.isCurrent else { finish(nil); return false }
        if transport.isBound(.server) {
            read(target: nil)
        } else {
            recover()
        }
        return true
    }

    func detach() {
        attached = false
        // Keep the transport lease until the pending response settles. The SDK
        // may still apply that response to Node before delivering our callback.
    }

    private func read(target: Int?) {
        guard isCurrent else { finish(nil); return }
        stage = target == nil ? .reading : .readback
        let id = nextCallback()
        transport.getTime { [self] response in
            guard accept(id) else { return }
            switch response {
            case .sample(let sample) where sample.isValid:
                guard target.map({ sample.matches(offset: $0, date: now()) }) ?? true,
                      transport.persist(sample) else { finish(nil); return }
                finish(sample)
            case .noResponse:
                if target == nil { recover() } else { finish(nil) }
            case .sample(let sample) where sample.seconds == 0:
                if target == nil { recover() } else { finish(nil) }
            case .sample, .invalid:
                finish(nil)
            }
        }
    }

    private func recover() {
        guard isCurrent, transport.canRecover else { finish(nil); return }
        #if DEBUG
        print("[InformationClock] attempting one clock recovery")
        #endif
        stage = .binding
        bindRemaining(InformationClockModel.allCases[...])
    }

    private func bindRemaining(_ models: ArraySlice<InformationClockModel>) {
        guard isCurrent, transport.canRecover else { finish(nil); return }
        guard let model = models.first else { setTime(); return }
        if transport.isBound(model) {
            bindRemaining(models.dropFirst())
            return
        }
        let id = nextCallback()
        transport.bind(model) { [self] success in
            guard accept(id) else { return }
            guard success else { finish(nil); return }
            bindRemaining(models.dropFirst())
        }
    }

    private func setTime() {
        guard isCurrent, transport.canRecover else { finish(nil); return }
        let date = now()
        guard let offset = transport.targetOffset(at: date),
              offset.isMultiple(of: 15),
              TimeZone(secondsFromGMT: offset * 60) != nil,
              date.timeIntervalSince1970 >= 946_684_800 else { finish(nil); return }
        stage = .setting
        let id = nextCallback()
        transport.setTime(date: date, offset: offset) { [self] response in
            guard accept(id) else { return }
            guard case .sample(let sample) = response,
                  sample.isValid, sample.offsetMinutes == offset else { finish(nil); return }
            read(target: offset)
        }
    }

    private var isCurrent: Bool { attached && transport.isCurrent }

    private func nextCallback() -> UUID {
        callbackID = UUID()
        return callbackID
    }

    private func accept(_ id: UUID) -> Bool {
        guard stage != .finished, callbackID == id else { return false }
        guard isCurrent else { finish(nil); return false }
        return true
    }

    private func finish(_ sample: InformationClockSample?) {
        guard stage != .finished else { return }
        #if DEBUG
        if sample == nil { print("[InformationClock] silently stopped at \(stage)") }
        #endif
        stage = .finished
        transport.finish()
        if attached { onFinish?(sample) }
        onFinish = nil
    }
}

enum InformationClockCachePolicy {
    static func mayAcceptResponse(
        currentSeconds: UInt64, currentOffset: Int?,
        confirmedSeconds: UInt64, confirmedOffset: Int?,
        responseSeconds: UInt64, responseOffset: Int
    ) -> Bool {
        (currentSeconds == responseSeconds && currentOffset == responseOffset)
            || (currentSeconds == confirmedSeconds && currentOffset == confirmedOffset)
    }
}

/// Shared with the Gateway detail clock so identical TimeStatus callbacks cannot
/// cancel each other. Access is confined to the main queue.
final class InformationClockLease {
    private static var owners: [String: UUID] = [:]
    private let key: String
    private let id = UUID()

    private init(key: String) { self.key = key }

    static func acquire(key: String) -> InformationClockLease? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard owners[key] == nil else { return nil }
        let lease = InformationClockLease(key: key)
        owners[key] = lease.id
        return lease
    }

    var isOwner: Bool { Self.owners[key] == id }

    func release() {
        if isOwner { Self.owners[key] = nil }
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

extension InformationClockLease {
    static func acquire(node: Node) -> InformationClockLease? {
        guard let network = node.network else { return nil }
        return acquire(key: "\(network.uuid.uuidString)/\(node.primaryUnicastAddress)")
    }
}

final class InformationClockMeshTransport: InformationClockTransport {
    private let node: Node
    private let network: MeshNetwork
    private let applicationKey: ApplicationKey
    private let keyData: Data
    private let proxy: ProxyReadyContext
    private let lease: InformationClockLease
    private let canConfigure: () -> Bool
    private let requiresDirectProxy: Bool
    private var confirmedTimestamp: UInt64
    private var confirmedTimeZone: TimeZone?
    private var pendingRequest: UUID?

    init?(node: Node, requiresDirectProxy: Bool, canConfigure: @escaping () -> Bool) {
        let manager = MeshNetworkManager.instance
        guard let network = node.network, manager.meshNetwork === network,
              let proxy = MeshLibManager.manager.currentProxyReadyContext,
              MeshLibManager.manager.isMeshNetworkConnected,
              !requiresDirectProxy || proxy.nodeAddress == node.primaryUnicastAddress,
              node.timeModel != nil else { return nil }
        let key = manager.currentApplicationKey
        guard node.applicationKeys.contains(where: { $0.index == key.index }),
              manager.ensureLocalTimeClientModelBinding(),
              let lease = InformationClockLease.acquire(node: node) else { return nil }
        self.node = node
        self.network = network
        self.applicationKey = key
        self.keyData = key.key
        self.proxy = proxy
        self.lease = lease
        self.canConfigure = canConfigure
        self.requiresDirectProxy = requiresDirectProxy
        confirmedTimestamp = node.timestamp
        confirmedTimeZone = node.timezone
    }

    private var ownsNetwork: Bool {
        lease.isOwner && node.network === network
            && MeshNetworkManager.instance.meshNetwork === network
            && network.nodes.contains(where: { $0 === node })
    }

    var isCurrent: Bool {
        guard ownsNetwork else { return false }
        let manager = MeshLibManager.manager
        let key = MeshNetworkManager.instance.currentApplicationKey
        return manager.isMeshNetworkConnected && manager.currentProxyReadyContext == proxy
            && (!requiresDirectProxy || manager.currentProxy?.nodeAddress == node.primaryUnicastAddress)
            && key.index == applicationKey.index && key.key == keyData
            && node.applicationKeys.contains(where: { $0.index == key.index })
    }

    var canRecover: Bool {
        isCurrent && canConfigure() && node.timeModel != nil && node.timeSetupModel != nil
    }

    private func model(_ kind: InformationClockModel) -> Model? {
        kind == .server ? node.timeModel : node.timeSetupModel
    }

    func isBound(_ kind: InformationClockModel) -> Bool {
        model(kind)?.isBoundTo(applicationKey) == true
    }

    func bind(_ kind: InformationClockModel, completion: @escaping (Bool) -> Void) {
        guard canRecover, let model = model(kind),
              let message = ConfigModelAppBind(applicationKey: applicationKey, to: model) else {
            completion(false)
            return
        }
        let request = beginRequest(timeout: 45) { completion(false) }
        do {
            try MeshNetworkManager.instance.send(message, to: node) { [self] result in
                DispatchQueue.main.async {
                    guard self.claimRequest(request) else { return }
                    guard self.isCurrent,
                          case .success(let response) = result,
                          let status = response as? ConfigModelAppStatus,
                          status.status == .success,
                          status.applicationKeyIndex == self.applicationKey.index,
                          status.elementAddress == model.parentElement?.unicastAddress,
                          status.modelIdentifier == model.modelIdentifier,
                          status.companyIdentifier == model.companyIdentifier else {
                        completion(false)
                        return
                    }
                    completion(true)
                }
            }
        } catch {
            if claimRequest(request) { completion(false) }
        }
    }

    func targetOffset(at date: Date) -> Int? {
        let resolution = SiteTimeSetMessageFactory.resolve(node: node, at: date)
        #if DEBUG
        if let resolution {
            print("[InformationClock] timezone source=\(resolution.source) offset=\(resolution.offsetMinutes)")
        }
        #endif
        return resolution?.offsetMinutes
    }

    func setTime(date: Date, offset: Int, completion: @escaping (InformationClockResponse) -> Void) {
        guard canRecover, let model = node.timeSetupModel,
              let timeZone = TimeZone(secondsFromGMT: offset * 60) else {
            completion(.invalid)
            return
        }
        send(Node.setLocalTimeMessage(date: date, timeZone: timeZone), model: model, completion: completion)
    }

    func getTime(completion: @escaping (InformationClockResponse) -> Void) {
        guard isCurrent, let model = node.timeModel else { completion(.invalid); return }
        send(TimeGet(), model: model, completion: completion)
    }

    private func send(
        _ message: StaticAcknowledgedMeshMessage,
        model: Model,
        completion: @escaping (InformationClockResponse) -> Void
    ) {
        guard isCurrent, let destination = model.parentElement?.unicastAddress else {
            completion(.invalid)
            return
        }
        // A different SDK caller may cancel the shared response listener. Keep
        // our own terminal deadline so a cancelled listener cannot hold the
        // device lease forever. This is not a retry timer.
        let request = beginRequest(timeout: 15) { completion(.invalid) }
        let callback: (Result<MeshMessage, Error>) -> Void = { [self] result in
            DispatchQueue.main.async {
                guard self.claimRequest(request) else { return }
                let response: MeshMessage
                switch result {
                case .success(let message): response = message
                case .failure(let error):
                    if let accessError = error as? AccessError, case .timeout = accessError {
                        completion(.noResponse)
                    } else {
                        completion(.invalid)
                    }
                    return
                }
                guard let status = response as? TimeStatus else {
                    completion(.invalid)
                    return
                }
                let offset = status.time.tzOffset.secondsFromGMT() / 60
                guard !self.ownsNetwork || InformationClockCachePolicy.mayAcceptResponse(
                    currentSeconds: self.node.timestamp,
                    currentOffset: self.node.timezone.map { $0.secondsFromGMT() / 60 },
                    confirmedSeconds: self.confirmedTimestamp,
                    confirmedOffset: self.confirmedTimeZone.map { $0.secondsFromGMT() / 60 },
                    responseSeconds: status.time.seconds,
                    responseOffset: offset
                ) else {
                    completion(.invalid)
                    return
                }
                // The SDK applies TimeStatus before this callback. Only undo
                // this exact sample while still owning this Node; never restore
                // an old backup over a different, newer update.
                if self.ownsNetwork,
                   self.node.timestamp == status.time.seconds,
                   self.node.timezone == status.time.tzOffset {
                    self.node.timestamp = self.confirmedTimestamp
                    self.node.timezone = self.confirmedTimeZone
                    guard self.node.savePropertys() else {
                        completion(.invalid)
                        return
                    }
                }
                completion(.sample(InformationClockSample(
                    seconds: status.time.seconds,
                    offsetMinutes: offset,
                    taiDelta: status.time.taiDelta,
                    subSecond: status.time.subSecond
                )))
            }
        }
        do {
            let manager = MeshNetworkManager.instance
            try manager.waitFor(
                messageWithOpCode: message.responseOpCode,
                from: destination, timeout: 10, completion: callback
            )
            // Send immediately to the actual Element using the captured key.
            // Do not queue a stale Date or let Model key ordering select a key.
            try manager.send(message, to: MeshAddress(destination), using: applicationKey) { [self] result in
                guard case .failure = result else { return }
                DispatchQueue.main.async {
                    if self.claimRequest(request) { completion(.invalid) }
                }
            }
        } catch {
            if claimRequest(request) { completion(.invalid) }
        }
    }

    private func beginRequest(timeout: TimeInterval, onTimeout: @escaping () -> Void) -> UUID {
        let id = UUID()
        pendingRequest = id
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.claimRequest(id) else { return }
            onTimeout()
        }
        return id
    }

    private func claimRequest(_ id: UUID) -> Bool {
        guard pendingRequest == id else { return false }
        pendingRequest = nil
        return true
    }

    func persist(_ sample: InformationClockSample) -> Bool {
        guard isCurrent, sample.isValid else { return false }
        node.timestamp = sample.seconds
        node.timezone = TimeZone(secondsFromGMT: sample.offsetMinutes * 60)
        guard node.savePropertys() else {
            node.timestamp = confirmedTimestamp
            node.timezone = confirmedTimeZone
            _ = node.savePropertys()
            return false
        }
        confirmedTimestamp = node.timestamp
        confirmedTimeZone = node.timezone
        return true
    }

    func finish() {
        pendingRequest = nil
        lease.release()
    }
}
#endif
