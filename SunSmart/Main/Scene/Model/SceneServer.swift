import Foundation
import NordicSigMeshSDK

struct SceneServer {
    typealias GroupOperateSuccessCallback = ((Scene) -> Void)
    typealias GroupOperateFailedCallback = ((Scene) -> Void)

    private static var deletionSessions: [SceneScopeKey: SyncExecutionSession] = [:]
    private struct SceneScopeKey: Hashable { let mesh: String; let network: String; let number: UInt16 }

    static func deleteScene(scene: Scene, success: GroupOperateSuccessCallback?, failed: GroupOperateFailedCallback?) {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork,
              scene.network === network || (scene.network == nil && scene.info.configuration?.isDeleting == true) else {
            failed?(scene); return
        }
        let scope = SceneScope(meshUUID: network.uuid.uuidString, networkID: manager.currentNetworkKey.networkId.hex)
        let key = SceneScopeKey(mesh: scope.meshUUID, network: scope.networkID, number: scene.number)
        guard deletionSessions[key] == nil, !MeshProxyMessageCommand.shared.isBusy else { failed?(scene); return }
        let references = referenceNames(scene: scene)
        guard references.isEmpty else {
            SRAlertView(message: String(format: "scene_delete_referenced".localizedString,
                                        references.joined(separator: "\n")),
                        actions: [SRAlertAction(title: "ok".localizedString, actionHandler: nil)]).show()
            failed?(scene); return
        }
        let store = SceneConfigurationStore()
        do {
            try SceneConfigurationStore.validateAccess(scope)
            if try SceneConfigurationStore.deletionAlreadyCompleted(scene: scene, scope: scope) {
                success?(scene); return
            }
            // Reload the authoritative row after SDK removal / App commit failure.
            if scene.network == nil {
                guard let info = SceneInfo.load(meshUUID: scope.meshUUID, sceneId: scene.number),
                      info.configuration?.isDeleting == true,
                      info.configuration?.revision == scene.info.configuration?.revision else { throw SceneConfigurationStore.Failure.unavailable }
                scene.info = info
            } else { try store.prepareDeletion(scene: scene) }
            if scene.info.configuration?.pendingOperations.isEmpty == true {
                try store.finishDeletion(info: scene.info, scope: scope)
                notifyDeletion(); success?(scene); return
            }
            guard scene.network === network, !scene.info.projectionPending,
                  MeshLibManager.manager.isMeshNetworkConnected else { failed?(scene); return }
            let environment = SyncExecutionEnvironment()
            environment.configurationIsCurrent = SceneCommandBuilder.captureConfigurations()
            let run = SyncExecutionSession(type: .scene(scene), reSync: false, environment: environment)
            let writes = SyncDevicesSectionModel(title: ""), removals = SyncDevicesSectionModel(title: "")
            SyncSceneScheduleTaskBuilder().appendScene(to: writes, removal: removals, scene: scene)
            run.sections = [removals, writes]
            deletionSessions[key] = run
            let finish = {
                guard deletionSessions[key] === run else { return }
                deletionSessions[key] = nil
                run.onStopped = nil; run.onSettled = nil; run.onPlanInvalidated = nil
                guard manager.meshNetwork === network, manager.currentNetworkKey.networkId.hex == scope.networkID,
                      referenceNames(scene: scene).isEmpty else { failed?(scene); return }
                do {
                    try SceneConfigurationStore.validateAccess(scope)
                    try store.finishDeletion(info: scene.info, scope: scope)
                    notifyDeletion(); success?(scene)
                } catch { failed?(scene) }
            }
            // Do not begin another deletion generation while the old transport
            // is stopping; reuse the established compensation/stop gate.
            run.onSettled = { _ in run.onStopped = finish; run.close() }
            run.onPlanInvalidated = {
                run.onStopped = {
                    deletionSessions[key] = nil
                    run.onStopped = nil; run.onSettled = nil; run.onPlanInvalidated = nil
                    failed?(scene)
                }
                run.close()
            }
            run.start()
        } catch { failed?(scene) }
    }

    private static func notifyDeletion() {
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
    }

    static func referenceNames(scene: Scene) -> [String] {
        SceneConfigurationStore.deletionReferenceNames(number: scene.number)
    }
}

/// Human review is restricted to an interrupted, explicitly prepared Restore.
/// No receipt means ordinary provisioning can never offer identity inheritance.
enum SceneRestoreConfirmation {
    static func presentIfNeeded(nodes: [Node]? = nil, sceneNumber: SceneNumber? = nil, completion: @escaping (Bool) -> Void) {
        let store = SceneConfigurationStore()
        do {
            // Both Restore and Sync re-entry must finish durable verified work
            // before treating an empty prepared-candidate list as ready.
            _ = try store.resumeVerifiedRestores()
            guard let candidate = try store.pendingRestoreConfirmations(nodes: nodes, sceneNumber: sceneNumber).first else {
                #if DEBUG
                print("[SceneSync] stage=restoreReady scene=\(sceneNumber ?? 0)")
                #endif
                completion(true); return
            }
            let message = String(format: "scene_restore_confirm_message".localizedString, candidate.node.name ?? candidate.node.primaryUnicastAddress.hex)
            SRAlertView(message: message, actions: [
                SRAlertAction(title: "cancel".localizedString, actionHandler: { _ in
                    #if DEBUG
                    print("[SceneSync] stage=restoreCancelled scene=\(sceneNumber ?? 0)")
                    #endif
                    completion(false)
                }),
                SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: { _ in
                    do {
                        guard !MeshProxyMessageCommand.shared.isBusy else { throw SceneConfigurationStore.Failure.unavailable }
                        try store.verifyRestore(receiptID: candidate.receipt.id, newNode: candidate.node, expectedIdentity: candidate.identity)
                        presentIfNeeded(nodes: nodes, sceneNumber: sceneNumber, completion: completion)
                    } catch {
                        #if DEBUG
                        print("[SceneSync] stage=restoreVerificationFailed errorType=\(Swift.type(of: error)) storeFailure=\(String(describing: error as? SceneConfigurationStore.Failure))")
                        #endif
                        XWHUDManager.showErrorTipHUD("scene_restore_pending".localizedString)
                        completion(false)
                    }
                })
            ]).show()
        } catch {
            #if DEBUG
            print("[SceneSync] stage=restorePreparationFailed errorType=\(Swift.type(of: error)) storeFailure=\(String(describing: error as? SceneConfigurationStore.Failure))")
            #endif
            XWHUDManager.showErrorTipHUD("scene_restore_pending".localizedString)
            completion(false)
        }
    }
}
