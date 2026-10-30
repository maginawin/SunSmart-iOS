import Foundation
import NordicSigMeshSDK

/// Owns draft confirmation; transport, stopping and formal retries stay in SyncExecutionSession.
final class SceneSaveCoordinator {
    enum SendPurpose { case preview, beforeSave }
    enum TargetResult { case successful, failed, offline }
    struct Report { let revision: UUID; let results: [TimedSchedulerNodeIdentity: TargetResult] }
    var onReport: ((Report) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onFormalCompletion: ((Bool) -> Void)?
    private(set) var committedNumber: SceneNumber?
    private let store: SceneConfigurationStore
    private let makeEnvironment: () -> SyncExecutionEnvironment
    private var session: SyncExecutionSession?
    private var generation = UUID()
    private var draft: SceneDraft?
    private var confirmation: SceneTargetSnapshot?
    private var formalStarted = false

    init(store: SceneConfigurationStore = SceneConfigurationStore(),
         makeEnvironment: @escaping () -> SyncExecutionEnvironment = { SyncExecutionEnvironment() }) {
        self.store = store; self.makeEnvironment = makeEnvironment
    }

    /// Persist DONE's intent; the visible Sync page owns all formal transmission.
    /// Retain the revision after a durable write so projection retries cannot
    /// allocate another scene or replace its pending operation generations.
    func saveForSync(draft: SceneDraft) throws -> SceneCommitResult {
        precondition(Thread.isMainThread)
        if committedNumber != nil, self.draft?.revision != draft.revision {
            throw SceneConfigurationStore.Failure.staleDraft
        }
        let result = try store.commit(draft: draft, expectedRevision: draft.revision)
        self.draft = draft
        switch result {
        case .ready(let scene): committedNumber = scene.number
        case .projectionPending(let number): committedNumber = number
        }
        return result
    }

    func send(draft: SceneDraft, purpose: SendPurpose) throws {
        precondition(Thread.isMainThread)
        guard committedNumber == nil else { throw SceneConfigurationStore.Failure.staleDraft }
        try SceneConfigurationStore.validateAccess(draft.scope)
        try store.validateSource(draft)
        let snapshot = try SceneTargetResolver.resolve(draft: draft)
        guard snapshot.unresolved.filter({ $0.action == .write }).isEmpty,
              !snapshot.targets.contains(where: { EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: $0.node) }) else {
            throw SceneConfigurationStore.Failure.invalidTargets
        }
        self.draft = draft; confirmation = nil; generation = UUID()
        let token = generation
        let begin = { [weak self] in
            guard let self, self.generation == token else { return }
            self.begin(draft, snapshot: snapshot, purpose: purpose, token: token)
        }
        if let session { session.onStopped = begin; session.close() }
        else { begin() }
    }

    private func begin(_ draft: SceneDraft, snapshot: SceneTargetSnapshot, purpose: SendPurpose, token: UUID) {
        let environment = makeEnvironment()
        environment.configurationIsCurrent = { [weak self] in
            guard let self, self.generation == token else { return false }
            do {
                try SceneConfigurationStore.validateAccess(draft.scope)
                try self.store.validateSource(draft)
                let current = try SceneTargetResolver.resolve(draft: draft)
                return current.comparison == snapshot.comparison
                    && !current.targets.contains { EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: $0.node) }
            } catch { return false }
        }
        let run = SyncExecutionSession(type: .devices(snapshot.targets.map(\.node)), reSync: false, environment: environment)
        session = run; run.publishesCloudChange = false
        let section = SyncDevicesSectionModel(title: "")
        var models: [TimedSchedulerNodeIdentity: SyncDevicesModel] = [:]
        var results: [TimedSchedulerNodeIdentity: TargetResult] = [:]
        for target in snapshot.targets {
            guard target.node.state else { results[target.identity] = .offline; continue }
            let model = SyncDevicesModel(name: target.node.name ?? "", address: target.node.primaryUnicastAddress)
            models[target.identity] = model; section.devices.append(model)
            run.parameterOnlyOperations[ObjectIdentifier(model)] = {
                guard target.node.sceneConfigurationIdentity == target.identity else { return [] }
                if draft.kind == .groups {
                    return SceneCommandBuilder.parameterHandles(node: target.node, target: SceneExecuteData(sceneNumber: 0,
                        isOn: target.parameters.isOn, lightness: target.parameters.lightness, cct: target.parameters.cct))
                }
                return SceneCommandBuilder.parameterHandles(node: target.node, parameters: target.parameters)
            }
        }
        run.sections = [section]
        run.onPlanInvalidated = { [weak self] in
            guard let self, self.generation == token else { return }
            self.confirmation = nil; self.onFailure?(SceneConfigurationStore.Failure.staleDraft)
        }
        run.onSettled = { [weak self] _ in
            guard let self, self.generation == token, environment.configurationIsCurrent() else { return }
            for (identity, model) in models { results[identity] = model.state == .successful ? .successful : .failed }
            self.confirmation = purpose == .beforeSave ? snapshot : nil
            self.onReport?(.init(revision: draft.revision, results: results))
        }
        run.start()
    }

    @discardableResult
    func confirm(revision: UUID) throws -> SceneCommitResult {
        precondition(Thread.isMainThread)
        guard let draft, revision == draft.revision else { throw SceneConfigurationStore.Failure.staleDraft }
        if committedNumber == nil {
            guard let confirmation, confirmation.revision == revision,
                  try SceneTargetResolver.resolve(draft: draft).comparison == confirmation.comparison else {
                throw SceneConfigurationStore.Failure.staleDraft
            }
        }
        let result = try store.commit(draft: draft, expectedRevision: revision)
        switch result {
        case .projectionPending(let number): committedNumber = number
        case .ready(let scene):
            committedNumber = scene.number
            if !formalStarted { formalStarted = true; startFormal(scene) }
        }
        return result
    }

    private func startFormal(_ scene: Scene) {
        let environment = makeEnvironment()
        environment.configurationIsCurrent = SceneCommandBuilder.captureConfigurations()
        let run = SyncExecutionSession(type: .scene(scene), reSync: false, environment: environment)
        let writes = SyncDevicesSectionModel(title: ""), removals = SyncDevicesSectionModel(title: "")
        SyncSceneScheduleTaskBuilder().appendScene(to: writes, removal: removals, scene: scene)
        run.sections = [removals, writes]
        let token = generation
        var delivered = false
        let complete: (Bool) -> Void = { [weak self] success in
            guard let self, self.generation == token, !delivered else { return }
            delivered = true
            self.onFormalCompletion?(success)
        }
        run.onSettled = { state in complete(state == .syncSuccess && !scene.needSync) }
        // Invalidation is delivered only after Session's stop/compensation gate.
        // The committed number and intent remain authoritative for ordinary Sync.
        run.onPlanInvalidated = { complete(false) }
        session = run; run.start()
    }

    func cancel() {
        precondition(Thread.isMainThread)
        generation = UUID(); if committedNumber == nil { draft = nil }; confirmation = nil
        session?.close(); session = nil; formalStarted = false
    }
}
