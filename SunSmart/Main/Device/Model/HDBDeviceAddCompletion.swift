import Foundation
import NordicSigMeshSDK

/// Runs only after FastAdd has reset its delegate/transmitter and standard receipts are applied.
final class HDBDeviceAddCompletion {
    /// HDB captures a scanned MAC before provisioning. Nil leaves ordinary Sites on their existing callback/fallback path.
    static func provisioningMAC(_ raw: String?, siteId: String) throws -> String? {
        guard let site = SiteData.load(siteId: siteId) else { throw HDBConfigurationError.unavailable }
        guard try site.loadIsHdbSite() else { return nil }
        return try HDBDeviceConfiguration.normalizedMAC(raw).replacingOccurrences(of: ":", with: "")
    }

    private var runIdentifier = UUID()
    private var session: SyncExecutionSession?
    // Stop/compensation may outlive the controller. Release only after the terminal callback.
    private var retainedUntilFinish: HDBDeviceAddCompletion?
    private var completion: ((Set<UUID>) -> Void)?
    private var nodes: [Node] = []
    private var incomplete = Set<UUID>()
    var isRunning: Bool { session != nil }
    var didChange: (() -> Void)?

    static func currentBatchNodes(addresses: Set<UInt16>, nodes: [Node]) -> [Node] {
        nodes.filter { addresses.contains($0.primaryUnicastAddress) }
    }

    func run(space: SpaceData, nodes: [Node], standardIncomplete: Set<UUID>, completion: @escaping (Set<UUID>) -> Void) {
        precondition(Thread.isMainThread)
        let runIdentifier = UUID()
        self.runIdentifier = runIdentifier
        retainedUntilFinish = self
        self.completion = completion; self.nodes = nodes; incomplete = standardIncomplete
        var contexts: [HDBDeviceSyncContext] = []
        for node in nodes {
            do {
                guard let context = try HDBDeviceSyncContext.resolve(space: space, node: node) else { continue }
                guard !standardIncomplete.contains(node.uuid), node.isKeybindComplete, !node.getStandardNeedSync() else {
                    incomplete.insert(node.uuid); continue
                }
                guard context.isCurrent() else { throw HDBConfigurationError.unavailable }
                contexts.append(context)
            } catch {
                incomplete.insert(node.uuid)
                trace("validate-failed", node: node, error: error)
            }
        }
        guard !contexts.isEmpty else { finish(); return }
        do {
            // Intent saves enqueue uploads. Their cleanup must see the newly added
            // nodes in the summary before any preparation task captures a revision.
            try HDBConfigurationStore.update(space: space, refreshCounts: true) { _ in }
            trace("summary-saved")
        } catch {
            trace("summary-failed", error: error)
            incomplete.formUnion(contexts.map { $0.node.uuid })
            finish(); return
        }
        var eligible: [Node] = []
        for context in contexts {
            do {
                try HDBDeviceSyncService.prepareIntent(context: context, subscriptionsWereReset: true)
                eligible.append(context.node)
            } catch {
                incomplete.insert(context.node.uuid)
                trace("intent-failed", node: context.node, error: error)
            }
        }
        guard !eligible.isEmpty else { finish(); return }
        let session = SyncExecutionSession(type: .devices(eligible), reSync: false)
        session.publishesCloudChange = false
        self.session = session
        session.environment.configurationIsCurrent = SpaceSyncTaskScope.capture()
        let plan = SyncTaskPlanBuilder(type: .devices(eligible), initialState: .inSync,
            profileSensorProtectionContext: nil, groupProfileSyncContext: nil,
            supplementaryProximityLightingSyncDatas: [], imageExists: { _ in false }).build()
        session.sections = plan.sections
        session.onSettled = { [weak self] state in
            guard let self, self.runIdentifier == runIdentifier else { return }
            self.trace(state == .syncSuccess ? "settled-success" : "settled-incomplete")
            if state != .syncSuccess { self.incomplete.formUnion(eligible.map(\.uuid).filter { id in
                eligible.first { $0.uuid == id }.map { $0.getNeedSync() } ?? true
            }) }
            self.finish()
        }
        session.onPlanInvalidated = { [weak self] in
            guard let self, self.runIdentifier == runIdentifier else { return }
            self.trace("plan-invalidated"); self.incomplete.formUnion(eligible.map(\.uuid)); self.finish()
        }
        session.onStopped = { [weak self] in
            guard let self, self.runIdentifier == runIdentifier else { return }
            self.trace("stopped"); self.incomplete.formUnion(eligible.map(\.uuid)); self.finish()
        }
        trace("start")
        session.start()
        didChange?()
    }

    func cancel() { session?.close() }

    private func trace(_ stage: String, node: Node? = nil, error: Error? = nil) {
        #if DEBUG
        let reason = (error as? HDBConfigurationError).map { String(describing: $0) } ?? "none"
        let address = node.map { String(format: "%04X", $0.primaryUnicastAddress) } ?? "batch"
        print("[HDB][Add] stage=\(stage) node=\(address) count=\(nodes.count) incomplete=\(incomplete.count) reason=\(reason)")
        #endif
    }

    private func finish() {
        guard let completion else { return }
        for node in nodes {
            node.clearSyncStateCache()
            if HDBDeviceSyncService.needsSync(node: node) { incomplete.insert(node.uuid) }
        }
        self.completion = nil
        let result = incomplete
        trace("finished")
        session?.onSettled = nil; session?.onStopped = nil; session?.onPlanInvalidated = nil
        session = nil
        retainedUntilFinish = nil
        didChange?()
        completion(result)
    }
}

/// Owns provisioning-to-HDB completion, independently of the page's weak callbacks.
/// Only HDB callers enroll; ordinary device addition keeps its existing scheduling.
final class HDBDeviceAddBatch {
    private var scope: DeviceAddCloudScope?
    private var token: UUID?
    private var starts: [(Bool) -> Void] = []
    private var ready = false
    private var preparing = false
    private var closing = false
    private weak var pageSpace: SpaceData?
    private var initialAddresses = Set<UInt16>()
    private var provisioned: [UUID: Node] = [:]
    var identifier: UUID? { token }
    var isActive: Bool { token != nil }
    var isWaiting: Bool { isActive && !ready }

    func acceptsCallbacks(from identifier: UUID?) -> Bool {
        guard let identifier else { return true }
        return token == identifier && !closing && scope?.currentSpace != nil
    }

    func enqueue(space: SpaceData, start: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        guard !closing else { start(false); return }
        if ready && !preparing { start(scope?.currentSpace != nil); return }
        starts.append(start)
        guard token == nil else { return }
        let scope = DeviceAddCloudScope(space: space)
        self.scope = scope
        pageSpace = space
        initialAddresses = Set(MeshAPI.getTheUsedDeviceAddresses(meshUUID: space.meshUUID))
        token = CloudSynchronizationManager.shared.beginDeviceAdd(scope: scope) { [self] allowed in
            let callbacks = starts; starts.removeAll()
            ready = allowed
            refreshPageSpace()
            if !allowed { finish() }
            callbacks.forEach { $0(allowed) }
        }
        trace("begin")
    }

    func beginPreparation() { if isActive { preparing = true } }

    func cancelQueuedStarts() {
        let callbacks = starts; starts.removeAll()
        callbacks.forEach { $0(false) }
    }

    private func refreshPageSpace() {
        guard let latest = scope?.currentSpace, let pageSpace else { return }
        pageSpace.hdb = latest.hdb; pageSpace.hdbPersistenceBaseline = latest.hdbPersistenceBaseline
        pageSpace.hdbLoadFailed = latest.hdbLoadFailed
        pageSpace.lastUpdate = latest.lastUpdate
        pageSpace.lastUploadCloudTimestamp = latest.lastUploadCloudTimestamp
        pageSpace.refreshSummaryCountsFromSpaceMesh()
    }

    func recordProvisioned(_ node: Node, batch: UUID?) {
        guard token == batch, isActive, !closing, scope?.currentSpace != nil else { return }
        provisioned[node.uuid] = node
        // Persist before standard configuration/HDB execution can fail or the App exits.
        persistLocalChanges()
    }

    func nodes(addresses: Set<UInt16>, currentNodes: [Node]) -> [Node] {
        HDBDeviceAddCompletion.currentBatchNodes(addresses: addresses, nodes: currentNodes).filter {
            !isActive || provisioned[$0.uuid]?.primaryUnicastAddress == $0.primaryUnicastAddress
        }
    }

    private func persistLocalChanges() {
        guard let space = scope?.currentSpace else { return }
        space.refreshSummaryCountsFromSpaceMesh()
        space.markLocalChangePendingCloudSync()
        SiteData.load(siteId: space.siteId)?.markSiteUploadNeededForSpaceAddressChange()
        refreshPageSpace()
    }

    func finish() {
        guard let token else { return }
        if !closing && !starts.isEmpty {
            // Devices selected during HDB/CCT cleanup wait for the transport lane,
            // but remain in the same cloud batch until their own tasks settle.
            preparing = false
            let callbacks = starts; starts.removeAll()
            let allowed = scope?.currentSpace != nil
            callbacks.forEach { $0(allowed) }
            if allowed { return }
        }
        trace("finish")
        let changedAddresses = scope.map { Set(MeshAPI.getTheUsedDeviceAddresses(meshUUID: $0.meshUUID)) != initialAddresses } ?? false
        if (!provisioned.isEmpty || changedAddresses), let space = scope?.currentSpace {
            // Reload after all ACK saves; never overwrite HDB data with the page's old Space.
            space.commitLocalChangeForCloudSync(changeType: .network(type: .address))
            refreshPageSpace()
        }
        self.token = nil; ready = false; closing = false; preparing = false; pageSpace = nil
        scope = nil; provisioned.removeAll(); initialAddresses.removeAll()
        CloudSynchronizationManager.shared.endDeviceAdd(token: token)
    }

    func finishIfCurrent(_ identifier: UUID?) {
        guard let identifier, token == identifier else { return }
        finish()
    }

    private func trace(_ stage: String) {
        #if DEBUG
        print("[HDB][AddBatch] stage=\(stage) nodes=\(provisioned.count) queued=\(starts.count)")
        #endif
    }

    func cancelWaiting() {
        guard isWaiting else { return }
        let callbacks = starts; starts.removeAll()
        finish()
        callbacks.forEach { $0(false) }
    }

    func close(completion: HDBDeviceAddCompletion) {
        guard isActive else { completion.cancel(); return }
        if isWaiting { cancelWaiting(); return }
        closing = true
        cancelQueuedStarts()
        if completion.isRunning {
            // Its retained terminal callback releases the batch after stop/compensation.
            completion.cancel()
        } else {
            let identifier = token
            MeshAPI.stopFastAddDevice { [self] _, _ in finishIfCurrent(identifier) }
        }
    }
}
