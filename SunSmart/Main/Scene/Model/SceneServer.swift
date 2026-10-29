import Foundation
import NordicSigMeshSDK

struct SceneServer {
    typealias GroupOperateSuccessCallback = ((Scene) -> Void)
    typealias GroupOperateFailedCallback = ((Scene) -> Void)

    static func deleteScene(scene: Scene, success: GroupOperateSuccessCallback?, failed: GroupOperateFailedCallback?) {
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork, scene.network === network,
              let db = SunSmartDataManager.shared.db else { failed?(scene); return }
        let networkID = manager.currentNetworkKey.networkId.hex
        let references = referenceNames(scene: scene)
        guard references.isEmpty else {
            SRAlertView(message: String(format: "scene_delete_referenced".localizedString,
                                        references.joined(separator: "\n")),
                        actions: [SRAlertAction(title: "ok".localizedString, actionHandler: nil)]).show()
            failed?(scene)
            return
        }
        let groups = scene.info.groups
        var nodes = scene.nodes
        for node in groups.flatMap(\.nodes) + manager.realNodes.filter({
            $0.sceneExecuteDatas.contains { $0.sceneNumber == scene.number } ||
                $0.elements.contains { $0.observedSceneRegister?.contains(scene.number) == true }
        }) where !nodes.contains(node) { nodes.append(node) }
        // Never discard an unresolved address just to free the Scene number.
        guard scene.addresses.allSatisfy({ network.node(withAddress: $0) != nil }) else { failed?(scene); return }
        let models = nodes.flatMap { node in
            node.elements.compactMap { $0.model(withSigModelId: .sceneSetupServerModelId) }
        }
        let unknown = models.filter { $0.parentElement?.observedSceneRegister == nil }
        guard unknown.isEmpty else {
            guard !MeshProxyMessageCommand.shared.isBusy, MeshLibManager.manager.isMeshNetworkConnected else {
                failed?(scene); return
            }
            let reads = unknown.map { MeshMessageHandle(message: SceneRegisterGet(), model: $0) }
            MeshProxyMessageCommand.shared.addMessage(messageHandles: reads, finishedBack: { results in
                DispatchQueue.main.async {
                    guard manager.meshNetwork === network, manager.currentNetworkKey.networkId.hex == networkID,
                          network.scenes.contains(where: { $0 === scene }),
                          nodes.allSatisfy({ network.node(withAddress: $0.primaryUnicastAddress) === $0 }),
                          results.count == reads.count, results.allSatisfy(\.isSuccessful),
                          unknown.allSatisfy({ $0.parentElement?.observedSceneRegister != nil }) else {
                        failed?(scene); return
                    }
                    deleteScene(scene: scene, success: success, failed: failed)
                }
            })
            return
        }
        // Mark all relations before transport. Successful groups are retained
        // until the whole deletion succeeds, so retries keep the original intent.
        let snapshots = groups.map { $0.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }?.state }
        do {
            try db.savepoint {
                for group in groups {
                    group.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }?.state = .waitDelete
                    guard group.info.save() else { throw TimedSchedulerBindings.Failure.persistence }
                }
            }
        } catch {
            for (group, state) in zip(groups, snapshots) {
                if let state { group.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }?.state = state }
            }
            failed?(scene); return
        }
        let handles = models.filter { $0.parentElement?.observedSceneRegister?.contains(scene.number) == true }
            .map { MeshMessageHandle(message: SceneDelete(scene.number), model: $0) }
        let finish: ([MeshMessageHandle]) -> Void = { results in
            DispatchQueue.main.async {
                guard manager.meshNetwork === network, manager.currentNetworkKey.networkId.hex == networkID,
                      network.scenes.contains(where: { $0 === scene }),
                      nodes.allSatisfy({ network.node(withAddress: $0.primaryUnicastAddress) === $0 }),
                      results.count == handles.count, results.allSatisfy(\.isSuccessful),
                      models.allSatisfy({ $0.parentElement?.observedSceneRegister?.contains(scene.number) == false }),
                      referenceNames(scene: scene).isEmpty else { failed?(scene); return }
                let previous = groups.map { $0.info.sceneExecuteDatas }
                do {
                    try db.savepoint {
                        for group in groups {
                            group.info.sceneExecuteDatas.removeAll { $0.sceneNumber == scene.number }
                            guard group.info.save() else { throw TimedSchedulerBindings.Failure.persistence }
                        }
                        // Capture identity before SDK remove disconnects Scene.network.
                        guard scene.info.delete(meshUUID: network.uuid.uuidString) else {
                            throw TimedSchedulerBindings.Failure.persistence
                        }
                    }
                    // The authoritative read also reconciles stale Scene.addresses.
                    try network.remove(scene: scene.number)
                    nodes.forEach { $0.delete(sceneId: scene.number) }
                    groups.forEach { $0.updateGroupSyncState() }
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
                    success?(scene)
                } catch {
                    for (group, data) in zip(groups, previous) {
                        group.info.sceneExecuteDatas = data
                        _ = group.info.save()
                    }
                    _ = scene.info.save(meshUUID: network.uuid.uuidString, subnetworkId: networkID)
                    failed?(scene)
                }
            }
        }
        if handles.isEmpty { finish([]) }
        else {
            guard !MeshProxyMessageCommand.shared.isBusy else { failed?(scene); return }
            MeshProxyMessageCommand.shared.addMessage(messageHandles: handles, finishedBack: finish)
        }
    }

    static func referenceNames(scene: Scene) -> [String] {
        let manager = MeshNetworkManager.instance
        var names = manager.schedules.filter {
            $0.sceneNumber == scene.number || $0.needDeleteSceneNumbers.contains(scene.number)
        }.map(\.name)
        let switches = manager.switchs + manager.groups.flatMap { $0.info.switchs }
        names.append(contentsOf: switches.filter {
            [$0.sceneANumber, $0.sceneBNumber, $0.sceneCNumber, $0.sceneDNumber].contains(scene.number)
        }.map(\.name))
        // SDK-observed Scheduler entries may still recall a formerly selected
        // Scene even after the business target has been edited.
        names.append(contentsOf: manager.realNodes.filter { node in
            node.allSchedulerModelEntrys.values.contains { entries in
                entries.values.contains { $0.isValid && $0.sceneNumber == scene.number }
            }
        }.map(SceneCapacity.label))
        return Array(Set(names)).sorted()
    }
}
