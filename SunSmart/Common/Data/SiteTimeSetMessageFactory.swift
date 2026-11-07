import Foundation

enum SiteTimeSetPhoneFallbackReason: Equatable {
    case missingSite, missingTimeZone, invalidTimeZone, unencodableSiteOffset
}
enum SiteTimeSetTimeZoneSource: Equatable {
    case site
    case phoneFallback(SiteTimeSetPhoneFallbackReason)
}
struct SiteClockTarget: Equatable {
    let source: SiteTimeSetTimeZoneSource
    let identifier: String?
    let offsetMinutes: Int
    let nextOffsetMinutes: Int
    let nextSwitch: Date?
}

struct SiteTimeSetTimeZoneResolution {
    let timeZone: TimeZone
    let offsetMinutes: Int
    let source: SiteTimeSetTimeZoneSource
    let snapshot: SiteTimeZoneSnapshot?
    let storageValue: String?
    let nextOffsetMinutes: Int
    let nextSwitch: Date?

    var target: SiteClockTarget {
        .init(source: source, identifier: snapshot?.identifier, offsetMinutes: offsetMinutes,
              nextOffsetMinutes: nextOffsetMinutes, nextSwitch: nextSwitch)
    }
    func isCurrent(at date: Date = Date(), phoneTimeZone: TimeZone = .current) -> Bool {
        SiteTimeSetMessageFactory.resolve(storageValue: storageValue, phoneTimeZone: phoneTimeZone, at: date)?.target == target
    }
}
enum SiteTimeSetMessageFactory {
    static func resolve(storageValue: String?, phoneTimeZone: TimeZone = .current,
                        at date: Date = Date()) -> SiteTimeSetTimeZoneResolution? {
        let raw = storageValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return phoneFallback(storageValue: storageValue, reason: .missingTimeZone, zone: phoneTimeZone, at: date)
        }
        guard let identity = SiteTimeZoneValue(storageValue: raw), identity.isRecognizedTimeZone else {
            return phoneFallback(storageValue: storageValue, reason: .invalidTimeZone, zone: phoneTimeZone, at: date)
        }
        // A valid Site with a temporarily unavailable response is not an invalid timezone.
        guard let snapshot = identity.snapshot(at: date), snapshot.isUsable(at: date),
              SiteTimeZoneValue.isMeshEncodable(snapshot.offsetMinutes),
              let zone = TimeZone(secondsFromGMT: snapshot.offsetMinutes * 60) else { return nil }
        let nextOffset = snapshot.switchesTo.flatMap(SiteTimeZoneValue.parseOffset) ?? snapshot.offsetMinutes
        guard SiteTimeZoneValue.isMeshEncodable(nextOffset) else { return nil }
        return .init(timeZone: zone, offsetMinutes: snapshot.offsetMinutes, source: .site,
                     snapshot: snapshot, storageValue: storageValue,
                     nextOffsetMinutes: nextOffset, nextSwitch: snapshot.nextSwitchDate)
    }

    private static func phoneFallback(storageValue: String?, reason: SiteTimeSetPhoneFallbackReason,
                                      zone: TimeZone, at date: Date) -> SiteTimeSetTimeZoneResolution? {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds.isMultiple(of: 900), SiteTimeZoneValue.isMeshEncodable(seconds / 60),
              let fixed = TimeZone(secondsFromGMT: seconds) else { return nil }
        return .init(timeZone: fixed, offsetMinutes: seconds / 60, source: .phoneFallback(reason),
                     snapshot: nil, storageValue: storageValue, nextOffsetMinutes: seconds / 60, nextSwitch: nil)
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct SiteTimeSetMessagePlan {
    let handle: MeshMessageHandle
    let offset: () -> Int?
    var targetOffsetMinutes: Int? { offset() }
}

/// Pins the source and transport identity through async preparation and the actual wire send.
private final class SiteTimeSetPreparedContext {
    let storageValue: String?
    let siteID: String?
    private weak var node: Node?
    private let requiresProxyConnection: Bool
    private let region = UserData.currentServerRegion
    private let userID = UserData.currentUserId
    private let network = MeshNetworkManager.instance.meshNetwork
    private let networkID = MeshNetworkManager.instance.currentNetworkKey.networkId
    private let keyIndex = MeshNetworkManager.instance.currentApplicationKey.index
    private let keyData = MeshNetworkManager.instance.currentApplicationKey.key
    private let lock = NSLock()
    private var resolution: SiteTimeSetTimeZoneResolution?
    private var transitionQueued = false

    init(storageValue: String?, siteID: String?, node: Node?, resolution: SiteTimeSetTimeZoneResolution?,
         requiresProxyConnection: Bool = true) {
        self.storageValue = storageValue; self.siteID = siteID; self.node = node; self.resolution = resolution
        self.requiresProxyConnection = requiresProxyConnection
    }
    var current: SiteTimeSetTimeZoneResolution? {
        lock.lock(); defer { lock.unlock() }; return resolution
    }
    func prepare(_ completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let resolved = await SiteTimeZoneService.shared.prepareClock(storageValue: storageValue)
            guard identityIsCurrent() else { completion(false); return }
            setResolution(resolved)
            completion(resolved != nil)
        }
    }
    private func setResolution(_ value: SiteTimeSetTimeZoneResolution?) {
        lock.lock(); resolution = value; lock.unlock()
    }
    private func identityIsCurrent() -> Bool {
        let manager = MeshNetworkManager.instance
        // Fast Add owns an independent bearer; its SDK operation validates that transport.
        guard (!requiresProxyConnection || MeshLibManager.manager.isMeshNetworkConnected),
              region == UserData.currentServerRegion, userID == UserData.currentUserId,
              manager.meshNetwork === network, manager.currentNetworkKey.networkId == networkID,
              manager.currentApplicationKey.index == keyIndex, manager.currentApplicationKey.key == keyData else { return false }
        guard let node, node.network === network,
              network?.nodes.contains(where: { $0 === node }) == true else { return false }
        guard let siteID else { return true } // Pre-save Gateway Fast Add owns its draft value.
        guard let site = SiteData.load(siteId: siteID) else { return false }
        return site.timezone == storageValue
    }
    func canSend() -> Bool {
        guard let current, current.isCurrent() else { return false }
        return Thread.isMainThread ? identityIsCurrent() : DispatchQueue.main.sync(execute: identityIsCurrent)
    }
    func accepts(_ message: MeshMessage) -> Bool {
        guard canSend(), let current, let status = message as? TimeStatus else { return false }
        return status.time.seconds > 0 && status.time.tzOffset.secondsFromGMT() / 60 == current.offsetMinutes
    }
    func enqueueTransition(model: Model, isCurrent: @escaping () -> Bool = { true }) {
        guard canSend(), let current else { return }
        lock.lock()
        guard !transitionQueued else { lock.unlock(); return }
        transitionQueued = true
        lock.unlock()
        SiteTimeSetMessageFactory.sendTransition(resolution: current, model: model,
            isCurrent: { self.canSend() && isCurrent() })
    }
}

extension SiteTimeSetMessageFactory {
    static func resolve(siteID: String, phoneTimeZone: TimeZone = .current, at date: Date = Date()) -> SiteTimeSetTimeZoneResolution? {
        guard let site = SiteData.load(siteId: siteID) else { return nil }
        return resolve(storageValue: site.timezone, phoneTimeZone: phoneTimeZone, at: date)
    }
    static func resolve(node: Node, phoneTimeZone: TimeZone = .current, at date: Date = Date()) -> SiteTimeSetTimeZoneResolution? {
        guard let id = node.network?.uuid.uuidString else { return nil }
        return resolve(siteID: id, phoneTimeZone: phoneTimeZone, at: date)
    }
    static func makeMessage(siteID: String, date: Date = Date(), phoneTimeZone: TimeZone = .current) -> TimeSet? {
        guard let resolution = resolve(siteID: siteID, phoneTimeZone: phoneTimeZone, at: date) else { return nil }
        return Node.setLocalTimeMessage(date: date, timeZone: resolution.timeZone)
    }
    static func makeHandle(node: Node, model: Model, phoneTimeZone: TimeZone = .current, at date: Date = Date()) -> MeshMessageHandle? {
        if let plan = makePlan(node: node, model: model, phoneTimeZone: phoneTimeZone, at: date) { return plan.handle }
        // Missing Site/ownership must still fail dependent schedule tasks.
        let rejected = MeshMessageHandle(message: Node.setLocalTimeMessage(date: date, timeZone: TimeZone(secondsFromGMT: 0)!), model: model)
        rejected.prepareForTransmission = { $0(false) }
        rejected.transmissionIsValid = { false }
        rejected.continuous = false
        return rejected
    }
    static func makePlan(node: Node, model: Model, phoneTimeZone: TimeZone = .current, at date: Date = Date()) -> SiteTimeSetMessagePlan? {
        guard let siteID = node.network?.uuid.uuidString, let site = SiteData.load(siteId: siteID) else { return nil }
        return makePlan(model: model, context: .init(storageValue: site.timezone, siteID: siteID, node: node,
            resolution: resolve(storageValue: site.timezone, phoneTimeZone: phoneTimeZone, at: date)))
    }
    static func makePlan(model: Model, resolution: SiteTimeSetTimeZoneResolution) -> SiteTimeSetMessagePlan {
        makePlan(model: model, context: .init(storageValue: resolution.storageValue,
            siteID: model.parentElement?.parentNode?.network?.uuid.uuidString,
            node: model.parentElement?.parentNode, resolution: resolution))
    }
    static func makePlan(model: Model, storageValue: String?, usesFastAddBearer: Bool = false) -> SiteTimeSetMessagePlan? {
        makePlan(model: model, context: .init(storageValue: storageValue,
            siteID: model.parentElement?.parentNode?.network?.uuid.uuidString,
            node: model.parentElement?.parentNode, resolution: resolve(storageValue: storageValue),
            requiresProxyConnection: !usesFastAddBearer))
    }

    /// A future transition is supplementary: its missing ACK cannot change TimeSet success.
    static func sendPrepared(resolution: SiteTimeSetTimeZoneResolution, model: Model,
                             isCurrent: @escaping () -> Bool,
                             completion: @escaping (TimeStatus?) -> Void) {
        let context = SiteTimeSetPreparedContext(storageValue: resolution.storageValue,
            siteID: model.parentElement?.parentNode?.network?.uuid.uuidString,
            node: model.parentElement?.parentNode, resolution: resolution)
        let handle = makePlan(model: model, context: context).handle
        // This flow owns the supplementary send and connection release below.
        handle.responseIsValid = context.accepts
        let valid = handle.transmissionIsValid
        var completed = false
        handle.transmissionIsValid = {
            let check = { !completed && isCurrent() }
            return (Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)) && (valid?() ?? false)
        }
        let finish: (TimeStatus?) -> Void = { status in
            DispatchQueue.main.async {
                guard !completed else { return }
                completed = true
                if status != nil, isCurrent(), context.canSend() {
                    sendTransition(resolution: resolution, model: model,
                                   isCurrent: { context.canSend() && isCurrent() },
                                   completion: { completion(status) })
                } else {
                    completion(status)
                }
            }
        }
        handle.transmissionRejected = { finish(nil) }
        guard let destination = model.parentElement?.unicastAddress,
              handle.transmissionIsValid?() == true else { finish(nil); return }
        do {
            try MeshNetworkManager.instance.waitFor(messageWithOpCode: TimeStatus.opCode, from: destination, timeout: 10) { result in
                let status = (try? result.get()) as? TimeStatus
                finish(status.flatMap { handle.hasPreparedTransmission && handle.transmissionIsValid?() == true && context.accepts($0) ? $0 : nil })
            }
            MeshAPI.sendMessage(handle: handle)
        } catch { finish(nil) }
    }

    static func transitionMessage(resolution: SiteTimeSetTimeZoneResolution, at date: Date = Date()) -> TimeZoneSet? {
        guard date.timeIntervalSince1970 >= MeshTimeConversion.unixEpochOffset,
              resolution.isCurrent(at: date), let zone = TimeZone(secondsFromGMT: resolution.nextOffsetMinutes * 60) else { return nil }
        var seconds: UInt64 = 0
        if let change = resolution.nextSwitch {
            let utc = change.timeIntervalSince1970
            guard change > date, utc.isFinite, utc.rounded(.down) == utc, utc >= MeshTimeConversion.unixEpochOffset,
                  utc < MeshTimeConversion.unixEpochOffset + Double(MeshTimeConversion.maximumSeconds) - 32_512 else { return nil }
            seconds = ExplicitTimeSetInput.make(date: change, timeZone: zone).seconds
        }
        return TimeZoneSet(tzOffset: zone, taiSeconds: seconds)
    }

    static func sendTransition(resolution: SiteTimeSetTimeZoneResolution, model: Model,
                               isCurrent: @escaping () -> Bool, completion: (() -> Void)? = nil) {
        guard let message = transitionMessage(resolution: resolution) else { completion?(); return }
        // Send to the actual Time Setup element, never blindly to a Time Server element.
        guard let element = model.parentElement,
              let setup = element.model(withSigModelId: .timeSetupServerModelId) else { completion?(); return }
        let context = SiteTimeSetPreparedContext(storageValue: resolution.storageValue,
            siteID: element.parentNode?.network?.uuid.uuidString, node: element.parentNode, resolution: resolution)
        let handle = MeshMessageHandle(message: message, model: setup)
        handle.transmissionIsValid = {
            let active = Thread.isMainThread ? isCurrent() : DispatchQueue.main.sync(execute: isCurrent)
            return active && context.canSend()
        }
        // Ordinary sync and temporary Gateway connections use the same bounded
        // GATT submission. An optional transition must not own the destination's
        // ACK slot while Scheduler / Switch tasks advance after TimeStatus.
        Task { @MainActor in
            guard handle.prepareMessageForSend() else { completion?(); return }
            _ = try? await MeshNetworkManager.instance.submitTimeZoneSet(message, to: setup,
                isCurrent: { handle.transmissionIsValid?() == true })
            completion?()
        }
    }

    static func broadcast(resolution: SiteTimeSetTimeZoneResolution, isCurrent: @escaping () -> Bool,
                          rejected: @escaping () -> Void) {
        guard let transition = transitionMessage(resolution: resolution) else { rejected(); return }
        let time = MeshMessageHandle(messageProvider: {
            Node.setLocalTimeMessage(date: Date(), timeZone: resolution.timeZone)
        }, address: .allNodes)
        let future = MeshMessageHandle(message: transition, address: .allNodes)
        for handle in [time, future] {
            handle.transmissionIsValid = {
                let current = Thread.isMainThread ? isCurrent() : DispatchQueue.main.sync(execute: isCurrent)
                return current && resolution.isCurrent()
            }
            handle.transmissionRejected = { DispatchQueue.main.async(execute: rejected) }
            MeshAPI.sendMessage(handle: handle)
        }
    }

    private static func makePlan(model: Model, context: SiteTimeSetPreparedContext) -> SiteTimeSetMessagePlan {
        let handle = MeshMessageHandle(messageProvider: {
            Node.setLocalTimeMessage(date: Date(), timeZone: context.current?.timeZone ?? TimeZone(secondsFromGMT: 0)!)
        }, model: model)
        handle.prepareForTransmission = context.prepare
        handle.transmissionIsValid = context.canSend
        handle.responseIsValid = { [weak handle] message in
            guard context.accepts(message) else { return false }
            // The SDK checks opcode/source AFTER this validator. Only enqueue after
            // it has recorded a successful matching response, never during validation.
            if let handle {
                DispatchQueue.main.async {
                    guard handle.hasPreparedTransmission, handle.isSuccessful else { return }
                    // Preserve the caller's operation guard through GATT backpressure,
                    // including STOP/replacement after the TimeStatus was accepted.
                    context.enqueueTransition(model: model,
                        isCurrent: { handle.transmissionIsValid?() ?? true })
                }
            }
            return true
        }
        handle.continuous = false
        return SiteTimeSetMessagePlan(handle: handle, offset: { context.canSend() ? context.current?.offsetMinutes : nil })
    }
}
#endif
