import Foundation

/// One visible Space owns one connection generation. All callbacks run on the main thread.
final class SpaceClockSyncSession {
    typealias Prepare = (Bool, @escaping (SiteTimeSetTimeZoneResolution?) -> Void) -> Void
    private let prepare: Prepare
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let isAllowed: () -> Bool
    private let send: (SiteTimeSetTimeZoneResolution, @escaping () -> Bool, @escaping () -> Void) -> Void
    private var active = false
    private var connected = false
    private var ready = false
    private var generation = UUID()
    private var requestID: UUID?
    private var pendingRefresh = false
    private var pendingRetry = false
    private var lastTarget: SiteClockTarget?
    private var deliveryID: UUID?

    init(prepare: @escaping Prepare,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         isAllowed: @escaping () -> Bool,
         send: @escaping (SiteTimeSetTimeZoneResolution, @escaping () -> Bool, @escaping () -> Void) -> Void) {
        self.prepare = prepare; self.schedule = schedule; self.isAllowed = isAllowed; self.send = send
    }
    func activate(connected: Bool) {
        guard !active else { refresh(retry: true); return }
        active = true
        connectionChanged(connected)
    }
    func stop() {
        active = false; connected = false; invalidate()
    }
    private func invalidate() {
        generation = UUID(); requestID = nil; ready = false
        pendingRefresh = false; pendingRetry = false; lastTarget = nil; deliveryID = nil
    }
    func connectionChanged(_ value: Bool) {
        guard active, connected != value else { return }
        connected = value; invalidate()
        guard value else { return }
        let token = generation
        schedule(3) { [weak self] in
            guard let self, self.active, self.connected, self.generation == token else { return }
            self.ready = true
            self.refresh(retry: true)
        }
    }
    func refresh(retry: Bool, force: Bool = false) {
        guard active, connected, ready, isAllowed() else { return }
        if force { lastTarget = nil; deliveryID = nil }
        guard requestID == nil else {
            pendingRefresh = true; pendingRetry = pendingRetry || retry; return
        }
        let token = UUID(), owner = generation
        requestID = token
        prepare(retry) { [weak self] resolution in
            guard let self, self.active, self.connected, self.generation == owner,
                  self.requestID == token else { return }
            self.requestID = nil
            let again = self.pendingRefresh, retryAgain = self.pendingRetry
            self.pendingRefresh = false; self.pendingRetry = false
            guard self.isAllowed() else { return }
            if let resolution, resolution.target != self.lastTarget {
                let delivery = UUID()
                self.lastTarget = resolution.target; self.deliveryID = delivery
                self.send(resolution, { [weak self] in
                    guard let self else { return false }
                    return self.active && self.connected && self.generation == owner
                        && self.deliveryID == delivery && self.isAllowed()
                }, { [weak self] in
                    guard let self, self.generation == owner, self.deliveryID == delivery else { return }
                    self.lastTarget = nil; self.deliveryID = nil
                })
            }
            // Passive failure notifications cannot become an immediate network retry loop.
            if again && (resolution != nil || retryAgain) { self.refresh(retry: retryAgain) }
        }
    }
}

#if canImport(UIKit) && canImport(NordicSigMeshSDK)
import UIKit
import NordicSigMeshSDK

final class SpaceClockSyncCoordinator {
    private let space: SpaceData
    private let isVisible: () -> Bool
    private let userID = UserData.currentUserId
    private let region = UserData.currentServerRegion
    private var observer: UUID?
    private var observedID: String?
    private var tokens: [NSObjectProtocol] = []
    private var connection: NSKeyValueObservation?
    private var internet: NSKeyValueObservation?
    private var running = false
    private var nodes: Set<UUID> = []
    private lazy var session = SpaceClockSyncSession(prepare: { [weak self] retry, completion in
        guard let self, let site = SiteData.load(siteId: self.space.siteId) else { completion(nil); return }
        self.observe(site.timezone)
        Task { @MainActor in
            completion(await SiteTimeZoneService.shared.prepareClock(siteID: self.space.siteId, retry: retry))
        }
    }, schedule: { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }, isAllowed: { [weak self] in self?.canSend == true }, send: { [weak self] resolution, valid, rejected in
        guard let self else { return }
        let manager = MeshNetworkManager.instance
        let network = manager.meshNetwork
        let keyIndex = manager.currentApplicationKey.index
        let keyData = manager.currentApplicationKey.key
        let rawTimezone = SiteData.load(siteId: self.space.siteId)?.timezone
        SiteTimeSetMessageFactory.broadcast(resolution: resolution, isCurrent: { [weak self] in
            guard let self, valid(), self.canSend,
                  let site = SiteData.load(siteId: self.space.siteId), site.timezone == rawTimezone else { return false }
            return manager.meshNetwork === network && manager.currentApplicationKey.index == keyIndex
                && manager.currentApplicationKey.key == keyData
        }, rejected: rejected)
        // Broadcast attempt only. No per-device success or durable confirmation is recorded.
    })

    init(space: SpaceData, isVisible: @escaping () -> Bool) {
        self.space = space; self.isVisible = isVisible
    }
    private var canSend: Bool {
        let manager = MeshNetworkManager.instance
        return running && isVisible() && UIApplication.shared.applicationState == .active
            && UserData.currentUserId == userID && UserData.currentServerRegion == region
            && (space.permission == .owner || space.permission == .editor) && !space.disableEditorPermission
            && space.state == .normal && MeshLibManager.manager.isMeshNetworkConnected
            && manager.meshNetwork?.uuid.uuidString == space.meshUUID
            && manager.currentNetworkKey.networkId.hex == space.meshNetworkId
    }
    func start() {
        guard !running else { session.refresh(retry: true); return }
        running = true
        observe(SiteData.load(siteId: space.siteId)?.timezone)
        nodes = Set(MeshNetworkManager.instance.realNodes.map(\.uuid))
        connection = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.session.connectionChanged(MeshLibManager.manager.isMeshNetworkConnected)
            }
        }
        internet = NetworkRequest.shared.observe(\.networkable, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                if NetworkRequest.shared.networkable { self?.session.refresh(retry: true) }
            }
        }
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification,
                     .NSSystemTimeZoneDidChange, .init(spacePermissionChangedNotificaitonName)] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.session.activate(connected: MeshLibManager.manager.isMeshNetworkConnected)
                self.session.connectionChanged(MeshLibManager.manager.isMeshNetworkConnected)
                self.session.refresh(retry: true)
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.session.stop()
        })
        tokens.append(NotificationCenter.default.addObserver(forName: .init(devicesUpdateNotificationName), object: nil, queue: .main) { [weak self] _ in
            guard let self, self.canSend else { return }
            let current = Set(MeshNetworkManager.instance.realNodes.map(\.uuid))
            let added = !current.subtracting(self.nodes).isEmpty
            self.nodes = current
            if added { self.session.refresh(retry: true, force: true) }
        })
        session.activate(connected: MeshLibManager.manager.isMeshNetworkConnected)
    }
    private func observe(_ storageValue: String?) {
        let value = storageValue.flatMap(SiteTimeZoneValue.init(storageValue:))
        let id = value?.isRecognizedTimeZone == true ? value?.ianaId : nil
        guard id != observedID else { return }
        SiteTimeZoneService.shared.removeObserver(observer)
        observedID = id; observer = nil
        if let id {
            // The session owns refresh; subscribing itself must not force a retry on failure.
            observer = SiteTimeZoneService.shared.store.observe(identifier: id) { [weak self] in
                self?.session.refresh(retry: false)
            }
        }
    }
    func stop() {
        running = false; session.stop()
        SiteTimeZoneService.shared.removeObserver(observer)
        observer = nil; observedID = nil
        connection = nil; internet = nil
        tokens.forEach(NotificationCenter.default.removeObserver); tokens.removeAll()
    }
    deinit { stop() }
}
#endif
