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

struct DeviceGroupFastAddSyncPlan {
    let nodeAddress: Address
    let group: Group
    let appendMessageHandles: [MeshMessageHandle]
    let verificationOperations: [DeviceOperationType]

    func contains(_ messageHandle: MeshMessageHandle) -> Bool {
        appendMessageHandles.contains { $0 === messageHandle }
    }

    var hasVerificationFailure: Bool {
        verificationOperations.contains { !$0.isSuccessful }
    }
}

enum DeviceGroupFastAddSyncPlanner {

    static func makePlan(
        node: Node,
        group: Group,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil
    ) -> DeviceGroupFastAddSyncPlan? {
        switch node.deviceType {
        case .light:
            let syncDatas = node.getSyncData(
                type: .group(group, effectiveMemberCount: effectiveMemberCount),
                profileSyncContext: profileSyncContext
            )
            let plan = DeviceGroupDeferredSyncPlanner.makePlan(
                node: node,
                group: group,
                effectiveMemberCount: effectiveMemberCount,
                profileSyncContext: profileSyncContext
            )
            let appendMessageHandles = plan.immediateMessageHandles
                + plan.deferredTasks.flatMap { $0.makeMessageHandles() }
            guard !appendMessageHandles.isEmpty else {
                return nil
            }
            return DeviceGroupFastAddSyncPlan(
                nodeAddress: node.primaryUnicastAddress,
                group: group,
                appendMessageHandles: appendMessageHandles,
                verificationOperations: makeVerificationOperations(syncDatas: syncDatas, node: node)
            )
        case .sensor:
            let syncDatas = node.getSyncData(type: .group(group, effectiveMemberCount: effectiveMemberCount))
            let appendMessageHandles = syncDatas.flatMap { $0.getMessageHandles(node: node) }
            guard !appendMessageHandles.isEmpty else {
                return nil
            }
            return DeviceGroupFastAddSyncPlan(
                nodeAddress: node.primaryUnicastAddress,
                group: group,
                appendMessageHandles: appendMessageHandles,
                verificationOperations: makeVerificationOperations(syncDatas: syncDatas, node: node)
            )
        default:
            return nil
        }
    }
}

enum DeviceGroupDeferredSyncPlanner {

    static func makePlan(
        node: Node,
        group: Group,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil
    ) -> DeviceGroupDeferredSyncPlan {
        let syncDatas = node.getSyncData(
            type: .group(group, effectiveMemberCount: effectiveMemberCount),
            profileSyncContext: profileSyncContext
        )
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

private extension DeviceGroupFastAddSyncPlanner {

    static func makeVerificationOperations(
        syncDatas: [NodeSyncData],
        node: Node
    ) -> [DeviceOperationType] {
        var operationTypes: [DeviceOperationType] = []

        syncDatas.forEach { syncData in
            switch syncData {
            case .deviceInitialize:
                operationTypes.append(.configuration(node: node, type: .deviceInitialize))
            case .subscribeGroup(let group):
                operationTypes.append(.configuration(node: node, type: .group(group: group)))
            case .unsubscribeGroup(let group):
                operationTypes.append(.delete(node: node, type: .group(group: group)))
            case .profile(let types):
                types.forEach {
                    operationTypes.append(.configuration(node: node, type: .profile(type: $0)))
                }
            case .syncScenes(let datas):
                datas.forEach { scene, data in
                    operationTypes.append(.configuration(node: node, type: .scene(sceneId: scene.number, executeData: data)))
                }
            case .deleteScenes(let scenes):
                scenes.forEach { scene in
                    operationTypes.append(.delete(node: node, type: .scene(sceneId: scene.number, executeData: nil)))
                }
            case .syncSchedules(let schedules):
                schedules.forEach { schedule in
                    operationTypes.append(.configuration(node: node, type: .schedule(schedule: schedule)))
                }
            case .deleteSchedules(let schedules):
                schedules.forEach { schedule in
                    operationTypes.append(.delete(node: node, type: .schedule(schedule: schedule)))
                }
            case .syncSwitchProxy(let switchData):
                operationTypes.append(.configuration(node: node, type: .enOceanProxy(switchData: switchData)))
            case .deleteSwitchProxy(let switchData):
                operationTypes.append(.delete(node: node, type: .enOceanProxy(switchData: switchData)))
            case .syncSwitchs(let switchDatas):
                switchDatas.forEach { switchData in
                    operationTypes.append(.configuration(node: node, type: .enOceanSwitch(switchData: switchData)))
                }
            case .deleteSwitchs(let switchDatas):
                switchDatas.forEach { switchData in
                    operationTypes.append(.delete(node: node, type: .enOceanSwitch(switchData: switchData)))
                }
            case .deviceParameterTypes(let types):
                types.forEach { type in
                    operationTypes.append(.configuration(node: node, type: .deviceParameters(parameterType: type)))
                }
            case .syncCollectionSchedules(let schedules):
                schedules.forEach { index, entry in
                    operationTypes.append(.configuration(node: node, type: .collectionSchedule(index: index, entry: entry)))
                }
            case .deleteCollectionSchedules(let scheduleIds):
                scheduleIds.forEach { index in
                    operationTypes.append(.delete(node: node, type: .collectionSchedule(index: index, entry: SchedulerRegistryEntry())))
                }
            case .proximityLightingEnabled(let enabled):
                operationTypes.append(.configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
            case .proximityLightingRelayNumber(let relayNumber):
                operationTypes.append(.configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                operationTypes.append(
                    .configuration(
                        node: node,
                        type: .proximityLightingNeighbor(
                            relayNumber: relayNumber,
                            neighborAddresses: neighborAddresses
                        )
                    )
                )
            case .syncGatewaySIMAPN(let apn):
                operationTypes.append(.configuration(node: node, type: .gatewaySIMAPN(apn: apn)))
            case .syncGatewayMQTTInformation(let mqttInformation):
                operationTypes.append(.configuration(node: node, type: .gatewayMQTTInformation(mqttInformation: mqttInformation)))
            case .syncGatewayProjectId(let projectId):
                operationTypes.append(.configuration(node: node, type: .gatewayAssociationProjectId(projectId: projectId)))
            case .syncGatewaySubnetAppkeyIndexs(let appkeyIndexs):
                operationTypes.append(.configuration(node: node, type: .gatewaySubnetAppkeyIndexs(appkeyIndexs: appkeyIndexs)))
            case .gatewayAssociatedSpaces(let datas, let activate):
                datas.forEach { data in
                    operationTypes.append(
                        .configuration(
                            node: node,
                            type: .gatewayAssociatedSpace(
                                networkKey: data.networkKey,
                                applicationKey: data.applicationKey,
                                activate: activate
                            )
                        )
                    )
                }
            case .gatewayUnbindAssociatedSpaces(let datas, let activate):
                datas.forEach { data in
                    operationTypes.append(
                        .configuration(
                            node: node,
                            type: .gatewayUnbindAssociatedSpace(
                                networkKey: data.networkKey,
                                applicationKey: data.applicationKey,
                                activate: activate
                            )
                        )
                    )
                }
            case .pirEnabled(let enabled):
                operationTypes.append(.configuration(node: node, type: .pirEnabled(enabled)))
            case .emergencyFireControllerAssociations:
                break
            case .addNetworkKey,
                 .removeNetworkKey,
                 .addApplicationkey,
                 .removeApplicationkey:
                break
            }
        }

        return operationTypes
    }
}

enum UpDownLightDefaultCctStepsReader {

    static func readAfterProvisioning(
        devices: [ProvisioningDevice],
        completion: @escaping () -> Void
    ) {
        let nodes = devices.compactMap {
            MeshNetworkManager.instance.meshNetwork?.node(withAddress: $0.address)
        }
        readAfterProvisioning(nodes: nodes, completion: completion)
    }

    static func readAfterProvisioning(
        nodes: [Node],
        completion: @escaping () -> Void
    ) {
        let supportedNodes = nodes.filter { $0.supportsUpDownLightDefaultCctSteps }
        guard !supportedNodes.isEmpty else {
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        read(nodes: supportedNodes, index: 0, completion: completion)
    }
}

private extension UpDownLightDefaultCctStepsReader {

    static func read(
        nodes: [Node],
        index: Int,
        completion: @escaping () -> Void
    ) {
        guard index < nodes.count else {
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        let node = nodes[index]
        guard let vendorModel = node.sunricherVendorModel else {
            save(steps: 5, for: node)
            read(nodes: nodes, index: index + 1, completion: completion)
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .upDownLightDefaultCctSteps),
            model: vendorModel,
            timeout: 7
        ) { response in
            let steps = normalizedSteps(from: response)
            DispatchQueue.main.async {
                save(steps: steps, for: node)
                read(nodes: nodes, index: index + 1, completion: completion)
            }
        }
    }

    static func normalizedSteps(from response: StaticMeshResponse?) -> UInt8 {
        guard let status = response as? SunricherVendorStatus,
              status.status.isSuccessful,
              case .upDownLightDefaultCctSteps(let steps) = status.status.parameters,
              steps == 6 else {
            return 5
        }
        return 6
    }

    static func save(steps: UInt8, for node: Node) {
        node.upDownLightDefaultCctSteps = steps
        _ = node.savePropertys()
    }
}
