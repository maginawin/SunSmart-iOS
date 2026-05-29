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
}

struct DeviceGroupDeferredSyncPlan {
    let immediateMessageHandles: [MeshMessageHandle]
    let deferredTasks: [DeviceGroupDeferredSyncTask]

    var hasDeferredTasks: Bool {
        !deferredTasks.isEmpty
    }
}

enum DeviceGroupDeferredSyncPlanner {

    static func makePlan(node: Node, group: Group) -> DeviceGroupDeferredSyncPlan {
        let syncDatas = node.getSyncData(type: .group(group))
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
        completion: @escaping () -> Void
    ) {
        runPlans(plans, index: 0, completion: completion)
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
        completion: @escaping () -> Void
    ) {
        guard index < plans.count else {
            completion()
            return
        }

        let item = plans[index]
        runTasks(item.plan.deferredTasks, index: 0, node: item.node, group: item.group, hadFailure: false) { _ in
            runPlans(plans, index: index + 1, completion: completion)
        }
    }

    static func runTasks(
        _ tasks: [DeviceGroupDeferredSyncTask],
        index: Int,
        node: Node,
        group: Group,
        hadFailure: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < tasks.count else {
            if hadFailure {
                node.clearSyncStateCache()
                group.updateGroupSyncState()
            }
            completion(hadFailure)
            return
        }

        let task = tasks[index]
        let messageHandles = task.messageHandles
        guard !messageHandles.isEmpty else {
            runTasks(tasks, index: index + 1, node: node, group: group, hadFailure: hadFailure, completion: completion)
            return
        }

        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil, successfulBack: { handle, statusMessage in
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
            var taskFailed = false
            resultMessageHandles.forEach { handle in
                let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
                targetNode.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                targetNode.clearSyncStateCache()
                if !handle.isSuccessful {
                    taskFailed = true
                }
            }
            if taskFailed {
                group.updateGroupSyncState()
            }
            runTasks(
                tasks,
                index: index + 1,
                node: node,
                group: group,
                hadFailure: hadFailure || taskFailed,
                completion: completion
            )
        }
    }
}
