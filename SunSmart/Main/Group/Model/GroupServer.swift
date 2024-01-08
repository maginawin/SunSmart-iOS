//
//  GroupServer.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/14.
//

import Foundation
import NordicSigMeshSDK

struct GroupServer {
    
    /// 操作进度 当前进度/总数量
    typealias GroupOperateProgressCallback = ((Int, Int)->Void)
    /// 组操作成功回调
    typealias GroupOperateSuccessCallback = ((Group)->Void)
    /// 组操作失败回调
    typealias GroupOperateFailedCallback = ((Group)->Void)
    /// 组添加设备、删除设备、同步数据成功回调
    typealias GroupOperateNodeSuccessCallback = ((Node)->Void)
    /// 组添加设备、删除设备、同步数据失败回调
    typealias GroupOperateNodeFailedCallback = ((Node)->Void)
    /// 组操作设备完成回调 成功设备list，失败设备list
    typealias GroupOperateNodeFinshedCallback = (([Node],[Node])->Void)
    
    
    /// 组添加设备list
    /// - Parameters:
    ///   - group: 组
    ///   - nodes: 设备list
    ///   - progress: 进度回调
    ///   - successful: 单个设备成功回调
    ///   - failed: 单个设备失败回调
    ///   - finshed: 完成回调（成功设备list，失败设备list）
    static func groupAddNodes(group: Group, nodes: [Node], progress: GroupOperateProgressCallback?, successful: GroupOperateNodeSuccessCallback?, failed: GroupOperateNodeFailedCallback?, finshed: GroupOperateNodeFinshedCallback?) {
        
        guard nodes.count > 0 else {
            finshed?([], [])
            return
        }
        
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            var successNodes: [Node] = []
            var failedNodes: [Node] = []
            
            nodes.enumerated().forEach({ (index, node) in
                DispatchQueue.main.async {
                    progress?(index + 1, nodes.count)
                }
                let messageHandles = group.getNodeAddMessageHandles(node: node)
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil) { sendMessageHandle, responseMessage in
                    switch responseMessage {
                    case is SceneRegisterStatus: // 设置场景成功
                        if let sceneMessage = sendMessageHandle.message as? SceneStore,
                            let sceneData = group.info.bindSceneDatas[sceneMessage.scene] {
                            node.sceneDatas.updateValue(sceneData, forKey: sceneMessage.scene)
                        }
                    case is SchedulerActionStatus: // 设置日程成功
                        let message = (responseMessage as! SchedulerActionStatus)
//                        if let scheduler = group.info.bindSchedules.first(where: { $0.id == schedulerId }) {
//                            node.schedules.append(scheduler)
                        node.scheduleDatas.updateValue(message.entry, forKey: Int(message.index))
//                        }
                    default:
                        break
                    }
                } failedBack: { messageHandles in
                    print("node send message failed \(messageHandles.message)")
                } finishedBack: { messageHandles in
                    // 本地化缓存
                    node.save()
                    DispatchQueue.main.async {
                        // 未设置完成
                        if messageHandles.contains(where: { !$0.isFinished }) {
                            failedNodes.append(node)
                            failed?(node)
                        }else { // 已完成
                            successNodes.append(node)
                            successful?(node)
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            })
            
            DispatchQueue.main.async {
                finshed?(successNodes, failedNodes)
            }
        }
        
    }
    
    
    /// 组删除设备list
    /// - Parameters:
    ///   - group: 组
    ///   - nodes: 设备list
    ///   - progress: 进度
    ///   - successful: 成功回调
    ///   - failed: 失败回调
    ///   - finshed: 完成回调（成功设备list，失败设备list）
    static func groupDeleteNodes(group: Group, nodes: [Node], progress: GroupOperateProgressCallback?, successful: GroupOperateNodeSuccessCallback?, failed: GroupOperateNodeFailedCallback?, finshed: GroupOperateNodeFinshedCallback?) {
        
        guard nodes.count > 0 else {
            finshed?([], [])
            return
        }
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            var successNodes: [Node] = []
            var failedNodes: [Node] = []
            
            nodes.enumerated().forEach({ (index, node) in
                DispatchQueue.main.async {
                    progress?(index + 1, nodes.count)
                }
                let messageHandles = group.getNodeExitMessageHandles(node: node)
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil) { sendMessageHandle, responseMessage in
                    switch responseMessage {
                    case is SceneRegisterStatus: // 删除场景成功
                        if let sceneMessage = sendMessageHandle.message as? SceneDelete {
                            node.sceneDatas.removeValue(forKey: sceneMessage.scene)
                        }
                    case is SchedulerActionStatus: // 删除日程成功
                        let schedulerId = (responseMessage as! SchedulerActionStatus).index
                        node.scheduleDatas.removeValue(forKey: Int(schedulerId))

                    default:
                        break
                    }
                } failedBack: { messageHandles in
                    print("node send message failed \(messageHandles.message)")
                } finishedBack: { messageHandles in
                    // 本地化缓存
                    node.save()
                    DispatchQueue.main.async {
                        // 未删除完成
                        if messageHandles.contains(where: { !$0.isFinished }) {
                            failedNodes.append(node)
                            failed?(node)
                        }else { // 已完成
                            successNodes.append(node)
                            successful?(node)
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            })
            
            DispatchQueue.main.async {
                finshed?(successNodes, failedNodes)
            }
        }
        
    }
    
    /// 删除组
    /// - Parameters:
    ///   - group: 组
    ///   - progress: 删除进度
    ///   - successful: 成功回调
    ///   - failed: 失败回调
    static func deleteGroup(group: Group, progress: GroupOperateProgressCallback?, successful: GroupOperateSuccessCallback?, failed: GroupOperateFailedCallback?) {
        
        self.groupDeleteNodes(group: group, nodes: group.nodes, progress: progress, successful: nil, failed: nil) { (_, deleteFailedNodes) in
            if deleteFailedNodes.isEmpty { // 删除成功
                // 删除组缓存数据
//                if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                    try? MeshNetworkManager.instance.meshNetwork?.remove(group: group)
                    _ = MeshNetworkManager.instance.save()
                    group.delete()
//                }
                successful?(group)
            }else {
                failed?(group)
            }
        }
    }
    
    
    /// 组设备同步数据
    /// - Parameters:
    ///   - group: 组
    ///   - nodes: 设备list
    ///   - progress: 进度
    ///   - successful: 成功回调
    ///   - failed: 失败回调
    ///   - finshed: 完成回调
    static func syncData(group: Group, nodes: [Node], progress: GroupOperateProgressCallback?, successful: GroupOperateNodeSuccessCallback?, failed: GroupOperateNodeFailedCallback?, finshed: GroupOperateNodeFinshedCallback?) {
        
        guard nodes.count > 0 else {
            finshed?([], [])
            return
        }
        
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            var successNodes: [Node] = []
            var failedNodes: [Node] = []
            
            nodes.enumerated().forEach({ (index, node) in
                DispatchQueue.main.async {
                    progress?(index + 1, nodes.count)
                }
                let messageHandles = group.getNodeSyncDataMessageHandles(node: node)
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil) { sendMessageHandle, responseMessage in
                    switch responseMessage {
                    case is SceneRegisterStatus: // 更新场景成功
                        if let sceneMessage = sendMessageHandle.message as? SceneStore, let sceneData = group.info.bindSceneDatas[sceneMessage.scene] {
                            node.sceneDatas.updateValue(sceneData, forKey: sceneMessage.scene)
                        }
                    case is SchedulerActionStatus: // 更新日程成功
                        let message = (responseMessage as! SchedulerActionStatus)
                        node.scheduleDatas.updateValue(message.entry, forKey: Int(message.index))
                        break
                    default:
                        break
                    }
                } failedBack: { messageHandle in
                    print("node send message failed \(messageHandle.message)")
                    
                } finishedBack: { messageHandles in
                    // 本地化缓存
                    node.save()
                    DispatchQueue.main.async {
                        // 未设置完成
                        if messageHandles.contains(where: { !$0.isFinished }) {
                            failedNodes.append(node)
                            failed?(node)
                        }else { // 已完成
                            successNodes.append(node)
                            successful?(node)
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            })
            
            DispatchQueue.main.async {
                finshed?(successNodes, failedNodes)
            }
        }
        
    }
    
    
    
    
}

extension Group {
    
    /// 根据节点获取添加到组需要的消息处理list
    /// - Parameter node: 节点
    /// - Returns: 消息处理list
    func getNodeAddMessageHandles(node: Node) -> [MeshMessageHandle] {
        
        var messages: [MeshMessageHandle] = []
        
        node.getSubscribeToGroupMessages(self).forEach({
            messages.append(MeshMessageHandle(message: $0, address: node.primaryUnicastAddress))
        })
        // 添加需要同步的场景、日程消息处理list
        messages.append(contentsOf: getNodeSyncDataMessageHandles(node: node))
        return messages
    }
    
    /// 根据节点获取从组移出需要的消息处理list
    /// - Parameter node: 节点
    /// - Returns: 消息处理list
    func getNodeExitMessageHandles(node: Node) -> [MeshMessageHandle] {
        
        var messages: [MeshMessageHandle] = []
        // 设备中组关联的场景
       
        let removeSceneDatas = self.info.bindSceneDatas.filter { (sceneId, _) in
            return node.sceneDatas.keys.contains(where: { $0 == sceneId })
        }
//        self.info.bindSceneDatas.filter { groupSceneData in
//            return node.bindSceneDatas.contains(where: { $0.sceneId == groupSceneData.sceneId })
//        }
        // 设备删除组关联的场景
        removeSceneDatas.forEach { (sceneId: SceneNumber, data: SceneExecuteData) in
            // 设备是否支持场景model
            if let sceneSetupModel = node.sceneSetupModel {
                // 删除场景
                messages.append(MeshMessageHandle(message: SceneDelete(sceneId), model: sceneSetupModel))
            }
        }
        
        // 设备中组关联的日程
       let removeSchedules = self.info.bindSchedules.filter { schedule in
            return node.scheduleDatas.contains(where: { Int($0.key) == schedule.id })
        }
        // 设备删除日程
        removeSchedules.forEach { schedule in
            if let schedulerSetupModel = node.schedulerSetupModel {
                // 删除日程，协议不支持删除，将对应id的日程设置为无效数据
                messages.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry()), model: schedulerSetupModel))
            }
        }
        // 设备退出组
        node.getUnsubscribeGroupMessages(self).forEach({
            messages.append(MeshMessageHandle(message: $0, address: node.primaryUnicastAddress))
        })
        messages.forEach({ $0.continuous = false })
        
        return messages
    }
    
    /// 获取设备同步组数据消息处理list
    func getNodeSyncDataMessageHandles(node: Node) -> [MeshMessageHandle] {
        
        var messages: [MeshMessageHandle] = []
        
        // 设备绑定组添加的场景
        self.info.bindSceneDatas.forEach { (sceneId: SceneNumber, data: SceneExecuteData) in
            // 设备是否支持场景model及亮度model
            if let sceneSetupModel = node.sceneSetupModel, let lightnessModel = node.lightnessModel {
                // 设备是否支持色温model
                let lightness = Node.getLightness(lightness100: data.lightness)
                if let ctlModel = node.ctlModel {
                    messages.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: UInt16(data.cct), deltaUV: 0), model: ctlModel))
                }else { // 不支持则设置亮度
                    messages.append(MeshMessageHandle(message: LightLightnessSet(lightness: lightness), model: lightnessModel))
                }
                // 保存场景
                messages.append(MeshMessageHandle(message: SceneStore(sceneId), model: sceneSetupModel))
            }
        }
        // 设备需要新增/更新的日程
        let setSchedules = self.info.bindSchedules.filter { schedule in
            !node.scheduleDatas.contains(where: { schedule.id == $0.key })
        }
        
        setSchedules.forEach { schedule in
            // 设置时区
            if node.timezome == nil, let timeModel = node.timeModel {
                messages.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
            }
            // 设置日程
            if let schedulerSetupModel = node.schedulerSetupModel {
                messages.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry(year: .any(), month: .any(of: [.January,.February,.March,.April,.May,.June,.July,.August,.September,.October,.November,.December]), day: .any(), hour: .specific(hour: schedule.hour), minute: .specific(minute: schedule.minute), second: .specific(second: 0), dayOfWeek: .any(of: schedule.weekDays), action: schedule.action, transitionTime: .init(steps: UInt8(schedule.fadeTime), stepResolution: .seconds), sceneNumber: schedule.actionSceneId)), model: schedulerSetupModel))
            }
        }
        return messages
        
    }
    
}
