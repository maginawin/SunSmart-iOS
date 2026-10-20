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

    private var session: SyncExecutionSession?
    private var completion: ((Set<UUID>) -> Void)?
    private var nodes: [Node] = []
    private var incomplete = Set<UUID>()
    var isRunning: Bool { session != nil }
    var didChange: (() -> Void)?

    func run(space: SpaceData, nodes: [Node], standardIncomplete: Set<UUID>, completion: @escaping (Set<UUID>) -> Void) {
        precondition(Thread.isMainThread)
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
        self.session = session
        session.environment.configurationIsCurrent = SpaceSyncTaskScope.capture()
        let plan = SyncTaskPlanBuilder(type: .devices(eligible), initialState: .inSync,
            profileSensorProtectionContext: nil, groupProfileSyncContext: nil,
            supplementaryProximityLightingSyncDatas: [], imageExists: { _ in false }).build()
        session.sections = plan.sections
        session.onSettled = { [weak self] state in
            guard let self else { return }
            self.trace(state == .syncSuccess ? "settled-success" : "settled-incomplete")
            if state != .syncSuccess { self.incomplete.formUnion(eligible.map(\.uuid).filter { id in
                eligible.first { $0.uuid == id }.map { $0.getNeedSync() } ?? true
            }) }
            self.finish()
        }
        session.onPlanInvalidated = { [weak self] in
            self?.trace("plan-invalidated"); self?.incomplete.formUnion(eligible.map(\.uuid)); self?.finish()
        }
        session.onStopped = { [weak self] in
            self?.trace("stopped"); self?.incomplete.formUnion(eligible.map(\.uuid)); self?.finish()
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
        didChange?()
        completion(result)
    }
}
