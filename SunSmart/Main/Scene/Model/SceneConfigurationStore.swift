import Foundation
import NordicSigMeshSDK

enum SceneCommitResult {
    case ready(Scene)
    case projectionPending(number: SceneNumber)
}

/// App rows own intent. SDK Scenes are a recoverable projection, never the allocation authority.
final class SceneConfigurationStore {
    enum Failure: Error { case staleDraft, unavailable, noNumber, persistence, invalidTargets }

    private struct CompletedDeletionKey: Hashable {
        let meshUUID: String
        let networkID: String
        let number: SceneNumber
    }
    // Session-local proof for an old detail page after Sync finalized its tombstone.
    // Absence alone is never evidence of completion; a reused number also rejects it.
    private static var completedDeletions: [CompletedDeletionKey: UUID] = [:]

    static func deletionAlreadyCompleted(scene: Scene, scope: SceneScope) throws -> Bool {
        guard scene.subNetworkId == scope.networkID, let configuration = scene.info.configuration,
              configuration.isDeleting,
              completedDeletions[.init(meshUUID: scope.meshUUID, networkID: scope.networkID, number: scene.number)] == configuration.revision,
              !MeshNetworkManager.instance.scenes.contains(where: { $0.number == scene.number }),
              !Scene.loadAddresses(meshUUID: scope.meshUUID).contains(scene.number) else { return false }
        return try !SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID).contains { $0.sceneId == scene.number }
    }

    static func exportRecords(scope: SceneScope, scenes: [Scene]) throws -> [SceneConfigurationPayload.Record] {
        let infos = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        var records: [UInt16: SceneConfigurationPayload.Record] = [:]
        for scene in scenes where !scene.number.isSpecialScene {
            guard scene.number > 0, records[scene.number] == nil else { throw Failure.persistence }
            records[scene.number] = .init(number: scene.number, name: scene.name, imageId: scene.info.imageId, configuration: nil)
        }
        for info in infos {
            guard !info.configurationLoadFailed else { throw Failure.persistence }
            if let config = info.configuration {
                records[info.sceneId] = .init(number: info.sceneId, name: config.name, imageId: info.imageId, configuration: config)
            } else if let legacy = records[info.sceneId] {
                records[info.sceneId] = .init(number: info.sceneId, name: legacy.name, imageId: info.imageId, configuration: nil)
            } else { throw Failure.persistence } // A nameless legacy orphan is not an empty configuration.
        }
        let result = records.values.sorted { $0.number < $1.number }
        _ = try SceneConfigurationPayload.encode(records: result)
        return result
    }

    /// Called within the existing complete-Space import savepoint and recovery barrier.
    /// Does not allocate, create a draft, regenerate tasks, or require editor access:
    /// read-only users may receive intent, but validateAccess still forbids executing it.
    static func importRecords(_ records: [SceneConfigurationPayload.Record], scope: SceneScope) throws {
        _ = try SceneConfigurationPayload.encode(records: records)
        let local = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        let all = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        let otherNumbers = Set(all.map(\.sceneId)).subtracting(local.map(\.sceneId))
        guard otherNumbers.isDisjoint(with: records.map(\.number)),
              SceneInfo.delete(meshUUID: scope.meshUUID, networkId: scope.networkID) else { throw Failure.persistence }
        for record in records {
            let info = SceneInfo(sceneId: record.number, imageId: record.imageId)
            info.configuration = record.configuration
            try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        }
    }

    /// Reuse the caller's durable cloud-removal journal and App savepoint.
    /// No address-only fallback: missing identity proof leaves intent untouched.
    static func removeConfirmedIdentities(_ identities: [TimedSchedulerNodeIdentity], scope: SceneScope) throws {
        guard !identities.isEmpty else { return }
        let removed = try Set(identities.map(SceneConfiguration.identity))
        for info in try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) {
            guard !info.configurationLoadFailed else { throw Failure.persistence }
            guard let configuration = info.configuration else { continue }
            let updated = try configuration.removingConfirmedIdentities(removed)
            guard updated != configuration else { continue }
            info.configuration = updated
            try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        }
    }

    /// Freeze the exact cleanup identities before any radio operation. A retry
    /// keeps the original revision/generations, including unresolvable targets.
    func prepareDeletion(scene: Scene) throws {
        let snapshot = try SceneTargetResolver.resolve(scene: scene)
        try Self.validateAccess(snapshot.scope)
        if scene.info.configuration?.isDeleting == true { return }
        guard !MeshProxyMessageCommand.shared.isBusy else { throw Failure.unavailable }
        let manager = MeshNetworkManager.instance
        var identities = Set(snapshot.targets.map(\.identity) + snapshot.cleanupTargets.map(\.identity)
            + snapshot.unresolved.map(\.identity))
        identities.formUnion(scene.info.configuration?.deviceMembers.map(\.identity) ?? [])
        identities.formUnion(scene.info.configuration?.pendingOperations.map(\.identity) ?? [])
        if snapshot.comparison.kind == .groups {
            // Legacy Group scenes may have residual registered targets after an
            // interrupted group exit. Device-mode display categories are never targets.
            guard let network = manager.meshNetwork,
                  scene.addresses.allSatisfy({ network.node(withAddress: $0) != nil }) else { throw Failure.invalidTargets }
            let registeredNodes = scene.addresses.compactMap { network.node(withAddress: $0) }
            for node in manager.realNodes where registeredNodes.contains(where: { $0 === node })
                || node.sceneExecuteDatas.contains(where: { $0.sceneNumber == scene.number })
                || node.elements.contains(where: { $0.observedSceneRegister?.contains(scene.number) == true }) {
                guard let identity = node.timedSchedulerIdentity else { throw Failure.invalidTargets }
                identities.insert(try SceneConfiguration.identity(identity))
            }
        }
        let previous = scene.info.configuration
        let groups = scene.info.groups
        let states = groups.map { $0.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }?.state }
        var configuration = previous ?? SceneConfiguration(kind: snapshot.comparison.kind, name: scene.name)
        configuration.revision = UUID()
        configuration.isDeleting = true
        configuration.pendingOperations = identities.map { identity in
            previous?.pendingOperations.first { $0.identity == identity && $0.action == .remove }
                ?? .init(identity: identity, action: .remove)
        }
        configuration = try configuration.normalized()
        let saved = SunSmartDataManager.shared.configurationTransaction {
            scene.info.configuration = configuration
            try scene.info.saveConfiguration(meshUUID: snapshot.scope.meshUUID, subnetworkId: snapshot.scope.networkID)
            for group in groups {
                group.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }?.state = .waitDelete
                guard group.info.save() else { throw Failure.persistence }
            }
        }
        guard saved else {
            scene.info.configuration = previous
            for (group, state) in zip(groups, states) {
                if let state { group.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }?.state = state }
            }
            throw Failure.persistence
        }
        manager.realNodes.forEach { $0.clearSyncStateCache() }
    }

    static func deletionReferenceNames(number: SceneNumber) -> [String] {
        let manager = MeshNetworkManager.instance
        var names = manager.schedules.filter {
            $0.sceneNumber == number || $0.needDeleteSceneNumbers.contains(number)
        }.map(\.name)
        let switches = manager.switchs + manager.groups.flatMap { $0.info.switchs }
        names.append(contentsOf: switches.filter {
            [$0.sceneANumber, $0.sceneBNumber, $0.sceneCNumber, $0.sceneDNumber].contains(number)
        }.map(\.name))
        // SDK-observed Scheduler entries may still recall a formerly selected
        // Scene even after the business target has been edited.
        names.append(contentsOf: manager.realNodes.filter { node in
            node.allSchedulerModelEntrys.values.contains { entries in
                entries.values.contains { $0.isValid && $0.sceneNumber == number }
            }
        }.map(SceneCapacity.label))
        return Array(Set(names)).sorted()
    }

    /// SDK deletion is first. If the App transaction then fails, its durable
    /// tombstone still reserves the number and load/retry can finish without
    /// recreating a callable SDK Scene.
    func finishDeletion(info: SceneInfo, scope: SceneScope) throws {
        guard !info.configurationLoadFailed, let configuration = info.configuration,
              configuration.isDeleting, configuration.pendingOperations.isEmpty,
              Self.deletionReferenceNames(number: info.sceneId).isEmpty,
              let network = MeshNetworkManager.instance.meshNetwork,
              network.uuid.uuidString == scope.meshUUID,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == scope.networkID else { throw Failure.invalidTargets }
        guard let persisted = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
            .first(where: { $0.sceneId == info.sceneId }),
              persisted.configuration == configuration else { throw Failure.staleDraft }
        try network.remove(scene: info.sceneId)
        let groups = MeshNetworkManager.instance.groups.filter {
            $0.info.sceneExecuteDatas.contains { $0.sceneNumber == info.sceneId }
        }
        let previous = groups.map { $0.info.sceneExecuteDatas }
        let saved = SunSmartDataManager.shared.configurationTransaction {
            for group in groups {
                group.info.sceneExecuteDatas.removeAll { $0.sceneNumber == info.sceneId }
                guard group.info.save() else { throw Failure.persistence }
            }
            guard info.delete(meshUUID: scope.meshUUID) else { throw Failure.persistence }
        }
        guard saved else {
            for (group, data) in zip(groups, previous) { group.info.sceneExecuteDatas = data }
            throw Failure.persistence
        }
        Self.completedDeletions[.init(meshUUID: scope.meshUUID, networkID: scope.networkID, number: info.sceneId)] = configuration.revision
        groups.forEach { $0.updateGroupSyncState() }
    }

    /// Persist before SDK provisioning can replace the old Node. Only the
    /// explicit Restore controller calls this; ordinary add is intentionally absent.
    func prepareRestore(oldNode: Node) throws -> UUID? {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, oldNode.network === network,
              oldNode.subNetworkId == manager.currentNetworkKey.networkId.hex,
              manager.realNodes.contains(where: { $0 === oldNode }),
              let raw = oldNode.timedSchedulerIdentity else { throw Failure.invalidTargets }
        let scope = SceneScope(meshUUID: network.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        try Self.validateAccess(scope)
        let identity = try SceneConfiguration.identity(raw)
        let infos = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        guard !infos.contains(where: \.configurationLoadFailed) else { throw Failure.persistence }
        guard infos.contains(where: { info in
            info.configuration?.deviceMembers.contains { $0.identity == identity } == true
                || info.configuration?.pendingOperations.contains { $0.identity == identity } == true
        }) else { return nil }
        guard let space = SpaceData.load(subNetworkId: scope.networkID) else { throw Failure.unavailable }
        let state = try SpaceConfigurationSafety.recoveryState(space)
        var receipts = try restoreReceipts(state.sceneRestoreReceipts)
        if let existing = receipts.first(where: {
            $0.scope == scope && $0.recoveryGeneration == state.generation && $0.oldIdentity == identity && $0.stage == .prepared
        }) { return existing.id }
        let receipt = SceneRestoreReceipt(id: UUID(), scope: scope, recoveryGeneration: state.generation, oldIdentity: identity)
        receipts.append(receipt)
        try SpaceConfigurationSafety.saveSceneRestoreReceipts(JSONEncoder().encode(receipts), context: state, space: space)
        return receipt.id
    }

    /// The callback is the evidence that this explicit Restore produced this
    /// new identity. UUID/time/address observed at a later load is insufficient.
    func verifyRestore(receiptID: UUID, newNode: Node, expectedIdentity: TimedSchedulerNodeIdentity? = nil) throws {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, newNode.network === network,
              newNode.subNetworkId == manager.currentNetworkKey.networkId.hex,
              manager.realNodes.contains(where: { $0 === newNode }),
              let raw = newNode.timedSchedulerIdentity else { throw Failure.invalidTargets }
        let scope = SceneScope(meshUUID: network.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        try Self.validateAccess(scope)
        let identity = try SceneConfiguration.identity(raw)
        guard expectedIdentity == nil || expectedIdentity == identity else { throw Failure.invalidTargets }
        guard let space = SpaceData.load(subNetworkId: scope.networkID),
              let persisted = MeshNetwork.load(meshUUID: scope.meshUUID, subnetworkId: scope.networkID),
              persisted.nodes.contains(where: { $0.sceneConfigurationIdentity == identity }) else { throw Failure.persistence }
        let state = try SpaceConfigurationSafety.recoveryState(space)
        var receipts = try restoreReceipts(state.sceneRestoreReceipts)
        guard let index = receipts.firstIndex(where: { $0.id == receiptID }),
              receipts[index].scope == scope, receipts[index].recoveryGeneration == state.generation,
              receipts[index].stage == .prepared,
              receipts[index].oldIdentity.nodeUUID == identity.nodeUUID else { throw Failure.invalidTargets }
        let infos = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        guard !infos.contains(where: \.configurationLoadFailed), infos.contains(where: { info in
            info.configuration?.deviceMembers.contains { $0.identity == receipts[index].oldIdentity } == true
                || info.configuration?.pendingOperations.contains { $0.identity == receipts[index].oldIdentity } == true
        }) else { throw Failure.invalidTargets }
        receipts[index].newIdentity = identity; receipts[index].stage = .verified
        try SpaceConfigurationSafety.saveSceneRestoreReceipts(JSONEncoder().encode(receipts), context: state, space: space)
        try resumeVerifiedRestores()
    }

    /// Replays only durable callback evidence. An interrupted prepared receipt
    /// stays visible for manual review; it cannot acquire a key by UUID matching.
    @discardableResult
    func resumeVerifiedRestores() throws -> Bool {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork else { throw Failure.unavailable }
        let scope = SceneScope(meshUUID: network.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        guard let space = SpaceData.load(subNetworkId: scope.networkID) else { throw Failure.unavailable }
        let state = try SpaceConfigurationSafety.recoveryState(space)
        var receipts = try restoreReceipts(state.sceneRestoreReceipts)
        guard receipts.contains(where: { $0.scope == scope && $0.recoveryGeneration == state.generation && $0.stage == .verified }) else {
            return receipts.contains { $0.scope == scope && $0.recoveryGeneration == state.generation && $0.stage == .prepared }
        }
        guard (try? Self.validateAccess(scope)) != nil else { return true }
        for index in receipts.indices where receipts[index].scope == scope
            && receipts[index].recoveryGeneration == state.generation && receipts[index].stage == .verified {
            guard let new = receipts[index].newIdentity,
                  manager.realNodes.contains(where: { $0.sceneConfigurationIdentity == new }) else { continue }
            let old = receipts[index].oldIdentity
            let infos = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
            let saved = SunSmartDataManager.shared.configurationTransaction {
                for info in infos {
                    guard !info.configurationLoadFailed else { throw Failure.persistence }
                    guard let configuration = info.configuration else { continue }
                    let updated = try configuration.restoringIdentity(from: old, to: new)
                    guard updated != configuration else { continue }
                    info.configuration = updated
                    try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
                }
            }
            guard saved else { throw Failure.persistence }
            // Idempotent if the process exits after the App commit: no remaining
            // old identity means a replay cannot generate another revision/write.
            for scene in manager.scenes {
                if let info = SceneInfo.load(meshUUID: scope.meshUUID, sceneId: scene.number) { scene.info = info }
            }
            manager.realNodes.forEach { $0.clearSyncStateCache() }
            // App data is already committed. Keep live SceneInfo aligned even
            // if the independent receipt write fails and verified must replay.
            receipts[index].stage = .applied
            try SpaceConfigurationSafety.saveSceneRestoreReceipts(JSONEncoder().encode(receipts), context: state, space: space)
        }
        return receipts.contains { $0.scope == scope && $0.recoveryGeneration == state.generation && $0.stage != .applied }
    }

    struct RestoreConfirmation {
        let receipt: SceneRestoreReceipt
        let node: Node
        let identity: TimedSchedulerNodeIdentity
    }

    func pendingRestoreConfirmations(nodes: [Node]? = nil, sceneNumber: SceneNumber? = nil) throws -> [RestoreConfirmation] {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork else { return [] }
        let scope = SceneScope(meshUUID: network.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        try Self.validateAccess(scope)
        guard let space = SpaceData.load(subNetworkId: scope.networkID) else { throw Failure.unavailable }
        let state = try SpaceConfigurationSafety.recoveryState(space)
        let infos = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
            .filter { sceneNumber == nil || $0.sceneId == sceneNumber }
        guard !infos.contains(where: \.configurationLoadFailed) else { throw Failure.persistence }
        let receipts = try restoreReceipts(state.sceneRestoreReceipts)
        // A verified receipt can remain unresolved (for example the new Node
        // identity changed again). It is not equivalent to no pending work.
        guard !receipts.contains(where: {
            $0.scope == scope && $0.recoveryGeneration == state.generation && $0.stage == .verified
        }) else { throw Failure.invalidTargets }
        return receipts.compactMap { receipt in
            guard receipt.scope == scope, receipt.recoveryGeneration == state.generation, receipt.stage == .prepared,
                  let node = manager.realNodes.first(where: { $0.uuid.uuidString.uppercased() == receipt.oldIdentity.nodeUUID }),
                  nodes?.contains(where: { $0 === node }) ?? true,
                  let identity = node.sceneConfigurationIdentity, identity != receipt.oldIdentity,
                  infos.contains(where: { info in
                      info.configuration?.deviceMembers.contains { $0.identity == receipt.oldIdentity } == true
                        || info.configuration?.pendingOperations.contains { $0.identity == receipt.oldIdentity } == true
                  }) else { return nil }
            return .init(receipt: receipt, node: node, identity: identity)
        }
    }

    private func restoreReceipts(_ data: Data?) throws -> [SceneRestoreReceipt] {
        guard let data else { return [] }
        return try JSONDecoder().decode([SceneRestoreReceipt].self, from: data)
    }

    static func validateAccess(_ scope: SceneScope) throws {
        // Keep every existing authority check; identify only the first rejection.
        func unavailable(_ reason: String) -> Failure {
            #if DEBUG
            print("[SceneSync] stage=accessRejected reason=\(reason)")
            #endif
            return .unavailable
        }
        guard Thread.isMainThread else { throw unavailable("notMainThread") }
        let manager = MeshNetworkManager.instance
        guard scope.meshUUID == manager.meshNetwork?.uuid.uuidString,
              scope.networkID == manager.currentNetworkKey.networkId.hex else { throw unavailable("scopeChanged") }
        guard SpaceConfigurationSafety.currentConfigurationAvailable else { throw unavailable("configurationUnavailable") }
        guard let space = SpaceData.load(subNetworkId: scope.networkID), space.meshUUID == scope.meshUUID else { throw unavailable("storedSpaceMissingOrChanged") }
        guard space.canEditing, space.sceneOperates.contains(.edit) else { throw unavailable("storedSpaceNotEditable") }
        guard let active = SpaceViewController.currentSpace(), active.meshUUID == scope.meshUUID,
              active.meshNetworkId == scope.networkID else { throw unavailable("activeSpaceMissingOrChanged") }
        guard active.canEditing, active.sceneOperates.contains(.edit) else { throw unavailable("activeSpaceNotEditable") }
        guard let recovery = try? SpaceConfigurationSafety.recoveryState(space) else { throw unavailable("recoveryUnreadable") }
        guard recovery.phase == .active, recovery.authority == .writable else { throw unavailable("recoveryNotWritable") }
    }

    /// CREATE reserves a durable, empty scene before opening its member editor.
    /// Keep this explicit so ordinary draft saves still require a selection.
    func createEmpty(draft: SceneDraft) throws -> SceneCommitResult {
        guard draft.number == nil, draft.groupParameters.isEmpty, draft.deviceMembers.isEmpty else {
            throw Failure.invalidTargets
        }
        return try commit(draft: draft, expectedRevision: draft.revision, allowsEmptyCreation: true)
    }

    func commit(draft: SceneDraft, expectedRevision: UUID) throws -> SceneCommitResult {
        try commit(draft: draft, expectedRevision: expectedRevision, allowsEmptyCreation: false)
    }

    private func commit(draft: SceneDraft, expectedRevision: UUID, allowsEmptyCreation: Bool) throws -> SceneCommitResult {
        precondition(Thread.isMainThread)
        guard draft.revision == expectedRevision else { throw Failure.staleDraft }
        try Self.validateAccess(draft.scope)
        let manager = MeshNetworkManager.instance
        // Idempotence across a projection failure, coordinator recreation and App restart.
        if let committed = try SceneInfo.loadAll(meshUUID: draft.scope.meshUUID, subnetworkId: draft.scope.networkID)
            .first(where: { $0.configuration?.revision == draft.revision }) {
            return project(committed, scope: draft.scope)
        }
        if let unchanged = try sceneIfUnchanged(draft: draft) { return .ready(unchanged) }
        let snapshot = try SceneTargetResolver.resolve(draft: draft)
        guard (allowsEmptyCreation || draft.number != nil || snapshot.hasConfiguredMembers), snapshot.unresolved.filter({ $0.action == .write }).isEmpty,
              !snapshot.targets.contains(where: { EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: $0.node) }) else {
            throw Failure.invalidTargets
        }
        let plan = try TimedSchedulerBindings.prepareTopology(sceneSnapshot: snapshot)
        let previousGroups = manager.groups.map { ($0, $0.info.sceneExecuteDatas) }
        var info: SceneInfo?
        var transactionError: Error?
        let saved = SunSmartDataManager.shared.configurationTransaction {
            do {
                try Self.validateAccess(draft.scope)
                try validateSource(draft)
                let number = try draft.number ?? nextAvailableNumber()
                let oldScene = manager.scenes.first { $0.number == number }
                let oldSnapshot = try oldScene.map { try SceneTargetResolver.resolve(scene: $0) }
                let targets = Set(snapshot.targets.map(\.identity))
                let currentOperations = Dictionary(uniqueKeysWithValues: (oldScene?.info.configuration?.pendingOperations ?? []).map { ($0.identity, $0) })
                let previousTargets = Dictionary(uniqueKeysWithValues: (oldSnapshot?.targets ?? []).map { ($0.identity, $0) })
                let writes = snapshot.targets.compactMap { target -> ScenePendingOperation? in
                    let previous = previousTargets[target.identity]
                    let previousAuxiliary = previous?.displayGroupAddress.flatMap { oldSnapshot?.comparison.groupAuxiliaryData[$0] }
                    let nextAuxiliary = target.displayGroupAddress.flatMap { snapshot.comparison.groupAuxiliaryData[$0] }
                    let sameTarget = oldSnapshot?.comparison.kind == snapshot.comparison.kind
                        && previous?.parameters == target.parameters && previousAuxiliary == nextAuxiliary
                    let pending = currentOperations[target.identity]
                    if sameTarget, pending?.action == .write { return pending }
                    let desired = SceneExecuteData(sceneNumber: number, isOn: target.parameters.isOn,
                        lightness: target.parameters.lightness, cct: target.parameters.cct)
                    if sameTarget, pending == nil,
                       target.node.sceneExecuteDatas.first(where: { $0.sceneNumber == number })?
                        .isSynced(with: desired, for: target.node) == true { return nil }
                    return .init(identity: target.identity, action: .write)
                }
                // Use the current committed state: an ACK may have completed a
                // removal since this editor captured its source snapshot.
                let cleanupSnapshot = oldSnapshot ?? snapshot
                var cleanup = Set(cleanupSnapshot.cleanupTargets.map(\.identity)
                    + cleanupSnapshot.unresolved.filter { $0.action == .remove }.map(\.identity))
                cleanup.formUnion(oldSnapshot?.targets.map(\.identity) ?? [])
                cleanup.formUnion(oldSnapshot?.unresolved.map(\.identity) ?? [])
                cleanup.formUnion(oldScene?.info.configuration?.deviceMembers.map(\.identity) ?? [])
                cleanup.formUnion(currentOperations.keys)
                cleanup.subtract(targets)
                var configuration = SceneConfiguration(kind: draft.kind, name: draft.name, revision: draft.revision,
                    deviceMembers: draft.deviceMembers,
                    pendingOperations: writes + cleanup.map { identity in
                        if let pending = currentOperations[identity], pending.action == .remove { return pending }
                        return .init(identity: identity, action: .remove)
                    })
                configuration = try configuration.normalized()
                let value = SceneInfo(sceneId: number, imageId: draft.imageId)
                value.configuration = configuration
                try TimedSchedulerBindings.commit(plan) {
                    for group in manager.groups {
                        let old = group.info.sceneExecuteDatas.first { $0.sceneNumber == number }
                        guard old != nil || draft.groupParameters[group.address.address] != nil else { continue }
                        group.info.sceneExecuteDatas.removeAll { $0.sceneNumber == number }
                        if let parameters = draft.groupParameters[group.address.address] {
                            // Keep HSL/LC and the old group unit/trim interpretation.
                            let data = SceneExecuteData(sceneNumber: number, isOn: parameters.isOn,
                                lightness: parameters.lightness, cct: parameters.cct, lightControlData: old?.lightControlData)
                            data.hue = old?.hue ?? 0; data.saturation = old?.saturation ?? 0
                            group.info.sceneExecuteDatas.append(data)
                        }
                        guard group.info.save(meshUUID: draft.scope.meshUUID, subnetworkId: draft.scope.networkID) else {
                            throw Failure.persistence
                        }
                    }
                    try value.saveConfiguration(meshUUID: draft.scope.meshUUID, subnetworkId: draft.scope.networkID)
                }
                info = value
            } catch { transactionError = error; throw error }
        }
        guard saved, let info else {
            previousGroups.forEach { $0.0.info.sceneExecuteDatas = $0.1 }
            throw transactionError ?? Failure.persistence
        }
        return project(info, scope: draft.scope)
    }

    /// Compare content, not the editor's fresh revision. ACK progress and topology
    /// may still require synchronization, but must not recreate every write intent.
    func sceneIfUnchanged(draft: SceneDraft) throws -> Scene? {
        try Self.validateAccess(draft.scope)
        try validateSource(draft)
        guard let number = draft.number,
              let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) else { return nil }
        guard !scene.info.projectionPending else { throw Failure.persistence }
        let current = try SceneTargetResolver.resolve(scene: scene)
        let edited = try SceneTargetResolver.resolve(draft: draft)
        guard scene.info.imageId == draft.imageId, current.comparison == edited.comparison else { return nil }
        return scene
    }

    func validateSource(_ draft: SceneDraft) throws {
        guard let number = draft.number else { return }
        guard let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }),
              scene.info.configuration?.isDeleting != true,
              let current = try? SceneDraft(scene: scene),
              current.sourceConfiguration?.revision == draft.sourceConfiguration?.revision,
              current.sourceGroupParameters == draft.sourceGroupParameters,
              current.sourceGroupAuxiliaryData == draft.sourceGroupAuxiliaryData,
              current.sourceGroupAddresses == draft.sourceGroupAddresses,
              current.sourceImageId == draft.sourceImageId,
              current.sourceName == draft.sourceName else { throw Failure.staleDraft }
        // ACK progress may change while editing; all configuration content must still match.
        var old = draft.sourceConfiguration, now = current.sourceConfiguration
        old?.pendingOperations = []; now?.pendingOperations = []
        guard old == now else { throw Failure.staleDraft }
    }

    /// Edit name/icon without re-creating device writes, cleanup or Scheduler slots.
    /// In-flight ACK progress belongs to the current committed configuration.
    func commitMetadata(draft: SceneDraft, expectedRevision: UUID) throws -> SceneCommitResult {
        precondition(Thread.isMainThread)
        guard draft.revision == expectedRevision, let number = draft.number,
              let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }),
              !scene.info.projectionPending, scene.info.configuration?.isDeleting != true else { throw Failure.staleDraft }
        try Self.validateAccess(draft.scope)
        try validateSource(draft)
        let snapshot = try SceneTargetResolver.resolve(scene: scene)
        var original = snapshot.comparison
        let edited = try SceneTargetResolver.resolve(draft: draft).comparison
        original.name = edited.name
        guard original == edited else { throw Failure.invalidTargets }
        // Metadata does not replace synchronization ownership, including when a
        // legacy group is first promoted to durable App metadata.
        var configuration = scene.info.configuration ?? SceneConfiguration(kind: .groups, name: scene.name,
            revision: snapshot.revision ?? draft.revision)
        configuration.name = draft.name
        let info = SceneInfo(sceneId: number, imageId: draft.imageId)
        info.configuration = configuration
        try info.saveConfiguration(meshUUID: draft.scope.meshUUID, subnetworkId: draft.scope.networkID)
        return project(info, scope: draft.scope)
    }

    func nextAvailableNumber() throws -> SceneNumber {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, let provisioner = network.localProvisioner else { throw Failure.unavailable }
        let app = try SceneInfo.loadAll(meshUUID: network.uuid.uuidString)
        let used = Set(Scene.loadAddresses(meshUUID: network.uuid.uuidString)).union(app.map(\.sceneId))
            .union(network.scenes.map(\.number))
        guard let number = SceneRegisterPolicy.nextOrdinaryNumber(used: used,
            ranges: provisioner.allocatedSceneRange.map { $0.firstScene...$0.lastScene }) else { throw Failure.noNumber }
        return number
    }

    /// Settings re-entry repairs durable projection before creating an editable revision.
    /// Recovery uses committed App rows and never re-commits or regenerates operations.
    func editingDraft(for scene: Scene) throws -> SceneDraft {
        guard scene.info.configuration?.isDeleting != true else { throw Failure.staleDraft }
        let scope = try SceneTargetResolver.resolve(scene: scene).scope
        try Self.validateAccess(scope)
        if scene.info.projectionPending {
            try restoreSceneProjections()
            guard !scene.info.projectionPending else { throw Failure.persistence }
        }
        return try SceneDraft(scene: scene)
    }

    func restoreSceneProjections() throws {
        let manager = MeshNetworkManager.instance
        guard let mesh = manager.meshNetwork else { throw Failure.unavailable }
        let scope = SceneScope(meshUUID: mesh.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        var failed = false
        for info in try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) {
            guard !info.configurationLoadFailed else { throw Failure.persistence }
            guard let configuration = info.configuration else { continue }
            if configuration.isDeleting, configuration.pendingOperations.isEmpty {
                // Keep the Space usable so its Schedule/Switch cleanup can run.
                // Only a known reference defers release; persistence/identity
                // errors from finalization still fail the recovery attempt.
                if !Self.deletionReferenceNames(number: info.sceneId).isEmpty { continue }
                do { try finishDeletion(info: info, scope: scope) }
                catch { failed = true }
                continue
            }
            if configuration.isDeleting, !mesh.scenes.contains(where: { $0.number == info.sceneId }) {
                // An absent SDK row is not physical cleanup evidence. Preserve
                // unknown/pending targets and the number instead of resurrecting it.
                continue
            }
            if case .projectionPending = project(info, scope: scope) { failed = true }
        }
        if failed { throw Failure.persistence }
    }

    /// Explicit Sync Devices retry may recover an SDK orphan for cleanup only.
    /// Attach its tombstone before exposing the projection; never allocate a new
    /// number, regenerate operations, or make it selectable for Recall/Store.
    func prepareDeletionRetries() throws {
        let manager = MeshNetworkManager.instance
        guard let mesh = manager.meshNetwork else { throw Failure.unavailable }
        let scope = SceneScope(meshUUID: mesh.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        try Self.validateAccess(scope)
        for info in try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) {
            guard !info.configurationLoadFailed else { throw Failure.persistence }
            guard let configuration = info.configuration, configuration.isDeleting else { continue }
            if configuration.pendingOperations.isEmpty {
                if !Self.deletionReferenceNames(number: info.sceneId).isEmpty { continue }
                try finishDeletion(info: info, scope: scope)
                continue
            }
            if let existing = mesh.scenes.first(where: { $0.number == info.sceneId }), !existing.info.projectionPending { continue }
            if case .projectionPending = project(info, scope: scope, deletionRetry: true) { throw Failure.persistence }
        }
    }

    private func project(_ info: SceneInfo, scope: SceneScope, deletionRetry: Bool = false) -> SceneCommitResult {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, network.uuid.uuidString == scope.meshUUID,
              manager.currentNetworkKey.networkId.hex == scope.networkID,
              let configuration = info.configuration else { return .projectionPending(number: info.sceneId) }
        let existing = network.scenes.first { $0.number == info.sceneId }
        // A tombstone reserves its number but must not resurrect an executable Scene.
        if configuration.isDeleting, existing == nil, !deletionRetry { return .projectionPending(number: info.sceneId) }
        if let existing, existing.subNetworkId != scope.networkID { return .projectionPending(number: info.sceneId) }
        let scene = existing ?? Scene(info.sceneId, name: configuration.name)
        let oldName = scene.name
        scene.name = configuration.name; scene.subNetworkId = scope.networkID
        // Attach intent before SDK add/save: even an orphan cleanup projection
        // must never be observable as a normal executable Scene.
        info.projectionPending = true
        scene.info = info
        if existing == nil { network.add(scene: scene) }
        guard scene.save() else {
            scene.name = oldName
            return .projectionPending(number: info.sceneId)
        }
        info.projectionPending = false
        return .ready(scene)
    }
}
