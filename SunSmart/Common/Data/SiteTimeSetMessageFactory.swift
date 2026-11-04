import Foundation

enum SiteTimeSetPhoneFallbackReason: Equatable {
    case missingSite, missingTimeZone, invalidTimeZone, unencodableSiteOffset
}
enum SiteTimeSetTimeZoneSource: Equatable {
    case site
    case phoneFallback(SiteTimeSetPhoneFallbackReason)
}
struct SiteTimeSetTimeZoneResolution {
    let timeZone: TimeZone
    let offsetMinutes: Int
    let source: SiteTimeSetTimeZoneSource
    let snapshot: SiteTimeZoneSnapshot
}
enum SiteTimeSetMessageFactory {
    static func resolve(storageValue: String?, phoneTimeZone: TimeZone = .current,
                        at date: Date = Date()) -> SiteTimeSetTimeZoneResolution? {
        guard let storageValue, let identity = SiteTimeZoneValue(storageValue: storageValue),
              let snapshot = identity.snapshot(at: date), snapshot.isUsable(at: date),
              SiteTimeZoneValue.isMeshEncodable(snapshot.offsetMinutes),
              let zone = TimeZone(secondsFromGMT: snapshot.offsetMinutes * 60) else { return nil }
        return .init(timeZone: zone, offsetMinutes: snapshot.offsetMinutes, source: .site, snapshot: snapshot)
    }
}

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

struct SiteTimeSetMessagePlan {
    let handle: MeshMessageHandle
    let offset: () -> Int?
    var targetOffsetMinutes: Int? { offset() }
    let source: SiteTimeSetTimeZoneSource = .site
}

/// A prepared offset is pinned to the transmission and its response. It can never fall back to a catalog value.
private final class SiteTimeSetPreparedContext {
    let identity: SiteTimeZoneValue
    let siteID: String?
    private let region = UserData.currentServerRegion
    private let lock = NSLock()
    private var resolution: SiteTimeSetTimeZoneResolution?
    init(identity: SiteTimeZoneValue, siteID: String?, resolution: SiteTimeSetTimeZoneResolution?) {
        self.identity = identity; self.siteID = siteID; self.resolution = resolution
    }
    var current: SiteTimeSetTimeZoneResolution? {
        lock.lock(); defer { lock.unlock() }; return resolution
    }
    func prepare(_ completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            let region = UserData.currentServerRegion
            let userID = UserData.currentUserId
            let snapshot = await SiteTimeZoneService.shared.prepare(identity)
            let siteStillMatches = siteID.map { SiteData.load(siteId: $0)?.timezone.flatMap(SiteTimeZoneValue.init(storageValue:)) == identity } ?? true
            let resolved = snapshot == nil ? nil : SiteTimeSetMessageFactory.resolve(storageValue: identity.storageValue)
            guard region == UserData.currentServerRegion, userID == UserData.currentUserId, siteStillMatches else { completion(false); return }
            set(resolved)
            completion(resolved != nil)
        }
    }
    private func set(_ value: SiteTimeSetTimeZoneResolution?) { lock.lock(); resolution = value; lock.unlock() }
    func canSend() -> Bool {
        guard let current else { return false }
        guard current.snapshot.isUsable(at: Date()), identity.offsetMinutes == current.offsetMinutes else { return false }
        let checkIdentity = { [self] in
            guard region == UserData.currentServerRegion else { return false }
            return siteID.map { SiteData.load(siteId: $0)?.timezone.flatMap(SiteTimeZoneValue.init(storageValue:)) == identity } ?? true
        }
        return Thread.isMainThread ? checkIdentity() : DispatchQueue.main.sync(execute: checkIdentity)
    }
    func accepts(_ message: MeshMessage) -> Bool {
        guard canSend(), let current, let status = message as? TimeStatus else { return false }
        return status.time.seconds > 0 && status.time.tzOffset.secondsFromGMT() / 60 == current.offsetMinutes
    }
}

extension SiteTimeSetMessageFactory {
    static func resolve(siteID: String, phoneTimeZone: TimeZone = .current, at date: Date = Date()) -> SiteTimeSetTimeZoneResolution? {
        resolve(storageValue: SiteData.load(siteId: siteID)?.timezone, phoneTimeZone: phoneTimeZone, at: date)
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
        // A missing Site must fail the prerequisite, never silently skip TimeSet and continue its dependent schedule.
        let rejected = MeshMessageHandle(message: Node.setLocalTimeMessage(date: date, timeZone: TimeZone(secondsFromGMT: 0)!), model: model)
        rejected.prepareForTransmission = { $0(false) }
        rejected.transmissionIsValid = { false }
        rejected.continuous = false
        return rejected
    }
    static func makePlan(node: Node, model: Model, phoneTimeZone: TimeZone = .current, at date: Date = Date()) -> SiteTimeSetMessagePlan? {
        guard let siteID = node.network?.uuid.uuidString,
              let identity = SiteData.load(siteId: siteID)?.timezone.flatMap(SiteTimeZoneValue.init(storageValue:)) else { return nil }
        return makePlan(model: model, context: .init(identity: identity, siteID: siteID,
            resolution: resolve(storageValue: identity.storageValue, at: date)))
    }
    static func makePlan(model: Model, resolution: SiteTimeSetTimeZoneResolution) -> SiteTimeSetMessagePlan {
        makePlan(model: model, context: .init(identity: SiteTimeZoneValue(storageValue: resolution.snapshot.identifier)!, siteID: model.parentElement?.parentNode?.network?.uuid.uuidString, resolution: resolution))
    }
    static func makePlan(model: Model, storageValue: String) -> SiteTimeSetMessagePlan? {
        guard let identity = SiteTimeZoneValue(storageValue: storageValue) else { return nil }
        return makePlan(model: model, context: .init(identity: identity, siteID: model.parentElement?.parentNode?.network?.uuid.uuidString,
            resolution: resolve(storageValue: storageValue)))
    }
    /// Keep the existing queued transport and timeout, while checking the prepared target at wire time.
    static func sendPrepared(resolution: SiteTimeSetTimeZoneResolution, model: Model,
                             isCurrent: @escaping () -> Bool,
                             completion: @escaping (TimeStatus?) -> Void) {
        let handle = makePlan(model: model, resolution: resolution).handle
        let valid = handle.transmissionIsValid
        var completed = false
        handle.transmissionIsValid = {
            let check = { !completed && isCurrent() }
            let current = Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
            return current && (valid?() ?? false)
        }
        let finish: (TimeStatus?) -> Void = { status in
            DispatchQueue.main.async {
                guard !completed else { return }
                completed = true
                completion(status)
            }
        }
        handle.transmissionRejected = { finish(nil) }
        guard let destination = model.parentElement?.unicastAddress,
              handle.transmissionIsValid?() == true else { finish(nil); return }
        do {
            try MeshNetworkManager.instance.waitFor(messageWithOpCode: TimeStatus.opCode, from: destination, timeout: 10) { result in
                let status = (try? result.get()) as? TimeStatus
                finish(status.flatMap { handle.hasPreparedTransmission && handle.transmissionIsValid?() == true && handle.responseIsValid?($0) == true ? $0 : nil })
            }
            MeshAPI.sendMessage(handle: handle)
        } catch { finish(nil) }
    }

    static func broadcast(resolution: SiteTimeSetTimeZoneResolution, isCurrent: @escaping () -> Bool,
                          rejected: @escaping () -> Void) {
        let identity = SiteTimeZoneValue(storageValue: resolution.snapshot.identifier)!
        let handle = MeshMessageHandle(messageProvider: {
            Node.setLocalTimeMessage(date: Date(), timeZone: resolution.timeZone)
        }, address: .allNodes)
        handle.transmissionIsValid = {
            let current = Thread.isMainThread ? isCurrent() : DispatchQueue.main.sync(execute: isCurrent)
            return current && resolution.snapshot.isUsable(at: Date()) && identity.offsetMinutes == resolution.offsetMinutes
        }
        handle.transmissionRejected = { DispatchQueue.main.async(execute: rejected) }
        MeshAPI.sendMessage(handle: handle)
    }

    private static func makePlan(model: Model, context: SiteTimeSetPreparedContext) -> SiteTimeSetMessagePlan {
        let handle = MeshMessageHandle(messageProvider: {
            // SDK validation runs before wire serialization. UTC is only an inert initial message for opcode/model metadata.
            Node.setLocalTimeMessage(date: Date(), timeZone: context.current?.timeZone ?? TimeZone(secondsFromGMT: 0)!)
        }, model: model)
        handle.prepareForTransmission = context.prepare
        handle.transmissionIsValid = context.canSend
        handle.responseIsValid = context.accepts
        handle.continuous = false
        return SiteTimeSetMessagePlan(handle: handle, offset: { context.canSend() ? context.current?.offsetMinutes : nil })
    }
}
#endif
