//
//  DeviceGroupDeferredSyncPlanner.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

struct DeviceGroupDeferredSyncTask {
    let operationType: DeviceOperationType
    let messageHandles: [MeshMessageHandle]
    let filteredSceneRecallCount: Int

    func makeMessageHandles() -> [MeshMessageHandle] {
        operationType.messageHandles.filter { !($0.message is SceneRecall) }
    }
}

struct DeviceGroupDeferredSyncPlan {
    let immediateMessageHandles: [MeshMessageHandle]
    let deferredTasks: [DeviceGroupDeferredSyncTask]

    var hasDeferredTasks: Bool {
        !deferredTasks.isEmpty
    }
}

struct DeviceGroupDeferredSyncPlanResult {
    let node: Node
    let group: Group
    let succeeded: Bool
}

enum DeviceGroupDeferredSyncPlanner {

    static func makePlan(
        node: Node,
        group: Group,
        profileSyncContext: GroupProfileSyncContext? = nil
    ) -> DeviceGroupDeferredSyncPlan {
        let syncDatas = node.getSyncData(type: .group(group), profileSyncContext: profileSyncContext)
        var immediateHandles: [MeshMessageHandle] = []
        var deferredTasks: [DeviceGroupDeferredSyncTask] = []

        syncDatas.forEach { syncData in
            switch syncData {
            case .deviceInitialize, .subscribeGroup:
                immediateHandles.append(contentsOf: syncData.getMessageHandles(node: node))
            case .profile,
                 .syncScenes,
                 .deleteScenes,
                 .syncSchedules,
                 .deleteSchedules,
                 .syncCollectionSchedules,
                 .deleteCollectionSchedules,
                 .syncSwitchProxy,
                 .deleteSwitchProxy,
                 .syncSwitchs,
                 .deleteSwitchs,
                 .proximityLightingEnabled,
                 .proximityLightingRelayNumber,
                 .proximityLightingNeighbor:
                deferredTasks.append(contentsOf: makeDeferredTasks(syncData: syncData, node: node))
            default:
                immediateHandles.append(contentsOf: syncData.getMessageHandles(node: node))
            }
        }

        return DeviceGroupDeferredSyncPlan(
            immediateMessageHandles: immediateHandles,
            deferredTasks: deferredTasks
        )
    }

    static func run(
        plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
        maxRetryCount: Int = 2,
        completion: @escaping ([DeviceGroupDeferredSyncPlanResult]) -> Void
    ) {
        runPlans(plans, index: 0, maxRetryCount: maxRetryCount, results: [], completion: completion)
    }
}

private extension DeviceGroupDeferredSyncPlanner {

    static func makeDeferredTasks(syncData: NodeSyncData, node: Node) -> [DeviceGroupDeferredSyncTask] {
        var tasks: [DeviceGroupDeferredSyncTask] = []

        func appendTask(_ operationType: DeviceOperationType) {
            let messageHandles = operationType.messageHandles
            let filteredMessageHandles = messageHandles.filter { !($0.message is SceneRecall) }
            let filteredSceneRecallCount = messageHandles.count - filteredMessageHandles.count
            guard !filteredMessageHandles.isEmpty else {
                return
            }
            tasks.append(
                DeviceGroupDeferredSyncTask(
                    operationType: operationType,
                    messageHandles: filteredMessageHandles,
                    filteredSceneRecallCount: filteredSceneRecallCount
                )
            )
        }

        switch syncData {
        case .profile(let types):
            types.forEach { type in
                appendTask(.configuration(node: node, type: .profile(type: type)))
            }
        case .syncScenes(let datas):
            datas.forEach { scene, data in
                appendTask(.configuration(node: node, type: .scene(sceneId: scene.number, executeData: data)))
            }
        case .deleteScenes(let scenes):
            scenes.forEach { scene in
                appendTask(.delete(node: node, type: .scene(sceneId: scene.number, executeData: nil)))
            }
        case .syncSchedules(let schedules):
            schedules.forEach { schedule in
                appendTask(.configuration(node: node, type: .schedule(schedule: schedule)))
            }
        case .deleteSchedules(let schedules):
            schedules.forEach { schedule in
                appendTask(.delete(node: node, type: .schedule(schedule: schedule)))
            }
        case .syncCollectionSchedules(let schedules):
            schedules.forEach { index, entry in
                appendTask(.configuration(node: node, type: .collectionSchedule(index: index, entry: entry)))
            }
        case .deleteCollectionSchedules(let scheduleIds):
            scheduleIds.forEach { index in
                appendTask(.delete(node: node, type: .collectionSchedule(index: index, entry: SchedulerRegistryEntry())))
            }
        case .syncSwitchProxy(let switchData):
            appendTask(.configuration(node: node, type: .enOceanProxy(switchData: switchData)))
        case .deleteSwitchProxy(let switchData):
            appendTask(.delete(node: node, type: .enOceanProxy(switchData: switchData)))
        case .syncSwitchs(let switchDatas):
            switchDatas.forEach { switchData in
                appendTask(.configuration(node: node, type: .enOceanSwitch(switchData: switchData)))
            }
        case .deleteSwitchs(let switchDatas):
            switchDatas.forEach { switchData in
                appendTask(.delete(node: node, type: .enOceanSwitch(switchData: switchData)))
            }
        case .proximityLightingEnabled(let enabled):
            appendTask(.configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
        case .proximityLightingRelayNumber(let relayNumber):
            appendTask(.configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
        case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
            appendTask(
                .configuration(
                    node: node,
                    type: .proximityLightingNeighbor(
                        relayNumber: relayNumber,
                        neighborAddresses: neighborAddresses
                    )
                )
            )
        default:
            break
        }

        return tasks
    }

    static func runPlans(
        _ plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
        index: Int,
        maxRetryCount: Int,
        results: [DeviceGroupDeferredSyncPlanResult],
        completion: @escaping ([DeviceGroupDeferredSyncPlanResult]) -> Void
    ) {
        guard index < plans.count else {
            completion(results)
            return
        }

        let item = plans[index]
        runTasks(
            item.plan.deferredTasks,
            index: 0,
            node: item.node,
            group: item.group,
            maxRetryCount: maxRetryCount,
            hadFailure: false
        ) { planSucceeded in
            var nextResults = results
            nextResults.append(
                DeviceGroupDeferredSyncPlanResult(
                    node: item.node,
                    group: item.group,
                    succeeded: planSucceeded
                )
            )
            runPlans(
                plans,
                index: index + 1,
                maxRetryCount: maxRetryCount,
                results: nextResults,
                completion: completion
            )
        }
    }

    static func runTasks(
        _ tasks: [DeviceGroupDeferredSyncTask],
        index: Int,
        node: Node,
        group: Group,
        maxRetryCount: Int,
        hadFailure: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < tasks.count else {
            if hadFailure {
                node.clearSyncStateCache()
                group.updateGroupSyncState()
            }
            completion(!hadFailure)
            return
        }

        let task = tasks[index]
        let messageHandles = task.makeMessageHandles()
        guard !messageHandles.isEmpty else {
            runTasks(
                tasks,
                index: index + 1,
                node: node,
                group: group,
                maxRetryCount: maxRetryCount,
                hadFailure: hadFailure,
                completion: completion
            )
            return
        }

        runTaskAttempt(
            task,
            attempt: 0,
            maxRetryCount: maxRetryCount,
            node: node,
            group: group
        ) { taskSucceeded in
            runTasks(
                tasks,
                index: index + 1,
                node: node,
                group: group,
                maxRetryCount: maxRetryCount,
                hadFailure: hadFailure || !taskSucceeded,
                completion: completion
            )
        }
    }

    static func runTaskAttempt(
        _ task: DeviceGroupDeferredSyncTask,
        attempt: Int,
        maxRetryCount: Int,
        node: Node,
        group: Group,
        completion: @escaping (Bool) -> Void
    ) {
        let messageHandles = task.makeMessageHandles()
        guard !messageHandles.isEmpty else {
            completion(true)
            return
        }

        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 15, progressBack: nil, successfulBack: { handle, statusMessage in
            if statusMessage is LightLightnessStatus
                || statusMessage is LightCTLTemperatureStatus
                || statusMessage is LightCTLStatus
                || statusMessage is LightHSLStatus,
               messageHandles.contains(where: { $0.message is SceneStore }) {
                let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
                targetNode.updateNodeStatus(message: statusMessage, source: address)
            }
        }, failedBack: nil) { resultMessageHandles in
            resultMessageHandles.forEach { handle in
                let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
                targetNode.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                targetNode.clearSyncStateCache()
            }

            let resultSuccessful = !resultMessageHandles.contains { !$0.isSuccessful }
            let operationSuccessful = task.operationType.isSuccessful
            let taskSucceeded = resultSuccessful && operationSuccessful
            logTaskAttempt(
                task,
                node: node,
                attempt: attempt,
                maxRetryCount: maxRetryCount,
                resultSuccessful: resultSuccessful,
                operationSuccessful: operationSuccessful
            )

            if taskSucceeded {
                completion(true)
                return
            }

            if attempt < maxRetryCount {
                runTaskAttempt(
                    task,
                    attempt: attempt + 1,
                    maxRetryCount: maxRetryCount,
                    node: node,
                    group: group,
                    completion: completion
                )
                return
            }

            node.clearSyncStateCache()
            group.updateGroupSyncState()
            completion(false)
        }
    }

    static func logTaskAttempt(
        _ task: DeviceGroupDeferredSyncTask,
        node: Node,
        attempt: Int,
        maxRetryCount: Int,
        resultSuccessful: Bool,
        operationSuccessful: Bool
    ) {
        #if DEBUG
        print("[GroupDeferredSync] node=\(node.primaryUnicastAddress) attempt=\(attempt + 1)/\(maxRetryCount + 1) resultSuccessful=\(resultSuccessful) operationSuccessful=\(operationSuccessful) operation=\(task.operationType)")

        if case .configuration(_, let type) = task.operationType,
           case .profile(let profileType) = type,
           case .sensorEnabled(let sensorModels, let publishAddress, _, let retransmit) = profileType {
            sensorModels.forEach { model in
                let currentAddress = model.publish?.publicationAddress.address
                let currentRetransmit = model.publish?.retransmit
                print("[GroupDeferredSync] sensorPublication node=\(node.primaryUnicastAddress) expected=\(publishAddress) current=\(currentAddress.map { String($0) } ?? "<nil>") expectedRetransmit=\(retransmit) currentRetransmit=\(currentRetransmit.map { "\($0)" } ?? "<nil>")")
            }
        }
        #endif
    }
}
