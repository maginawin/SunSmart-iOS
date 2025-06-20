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
                    node.updateData(message: sendMessageHandle.message)
                } failedBack: { messageHandles in
                    print("node send message failed \(messageHandles.message)")
                } finishedBack: { messageHandles in
                    DispatchQueue.main.async {
                        // 未设置完成
                        if messageHandles.contains(where: { !$0.isSuccessful }) {
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
        
        // 解绑本地节点订阅组信息
        for element in MeshNetworkManager.instance.localNode?.elements ?? [] {
            let subscribeModels = element.models.filter({ $0.isSubscribed(to: group) })
            subscribeModels.forEach({
                $0.unsubscribe(from: group)
            })
        }
        
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
                    node.updateData(message: sendMessageHandle.message)
                } failedBack: { messageHandle in
                    print("node send message failed \(messageHandle.message)")
                } finishedBack: { messageHandles in
                    DispatchQueue.main.async {
                        // 未删除完成
                        if messageHandles.contains(where: { !$0.isSuccessful }) {
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
                do {
                    try MeshNetworkManager.instance.meshNetwork?.remove(group: group)
                    group.deleteExtension()
                    successful?(group)
                } catch  {
                    failed?(group)
                }
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
//                    switch responseMessage {
//                    case is SceneRegisterStatus: // 更新场景成功
//                        if let sceneMessage = sendMessageHandle.message as? SceneStore, let sceneData = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == sceneMessage.scene }) {
//                            node.sceneDatas.updateValue(sceneData, forKey: sceneMessage.scene)
//                        }
//                    case is SchedulerActionStatus: // 更新日程成功
//                        let message = (responseMessage as! SchedulerActionStatus)
//                        node.scheduleDatas.updateValue(message.entry, forKey: Int(message.index))
//                        break
//                    default:
//                        break
//                    }
                } failedBack: { messageHandle in
                    print("node send message failed \(messageHandle.message)")
                    
                } finishedBack: { messageHandles in
                    // 本地化缓存
//                    node.save()
                    DispatchQueue.main.async {
                        // 未设置完成
                        if messageHandles.contains(where: { !$0.isSuccessful }) {
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
        
//        if node.lightLCSetupModel != nil { // 同步灯光控制配置
        let syncProfile = node.getNodeSyncProfiles(group: self)
        syncProfile.forEach({
            messages.append(contentsOf: $0.getMessageHandles(node: node))
        })
        // 临近照明
        if let model = node.sunricherVendorModel, let syncPath = node.getNodeSyncProximityLighting(group: self) {
            switch syncPath {
            case .proximityLightingEnabled(let enabled):
                messages.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingEnabled(enabled)), model: model))
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                messages.append(MeshMessageHandle(message: SunricherVendorSet(function: .proximityLightingNeighborSet(enabled: true, relay: relayNumber, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, relayAppKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index, neighborAddresses: neighborAddresses)), model: model))
            default:
                break
            }
        }
//        }
        // 添加需要同步的场景、日程消息处理list
        messages.append(contentsOf: getNodeSyncDataMessageHandles(node: node))
        
        // 添加动能开关订阅
        self.info.switchs.forEach { switchData in
            if switchData.linkGroup != nil {
                let subscriptionMessageHandles = node.getEnOceanSubscriptionMessageHandles(switchKeys: switchData.switchKeys)
                messages.append(contentsOf: subscriptionMessageHandles)
            }
        }
        
        return messages
    }
    
    /// 根据节点获取从组移出需要的消息处理list
    /// - Parameter node: 节点
    /// - Returns: 消息处理list
    func getNodeExitMessageHandles(node: Node) -> [MeshMessageHandle] {
        
        var messages: [MeshMessageHandle] = []
        // 设备中组关联的场景
       
        let removeSceneDatas = self.info.sceneExecuteDatas.filter { data in
            return node.sceneExecuteDatas.contains(where: { $0.sceneNumber == data.sceneNumber })
        }
//        self.info.bindSceneDatas.filter { groupSceneData in
//            return node.bindSceneDatas.contains(where: { $0.sceneId == groupSceneData.sceneId })
//        }
        // 设备删除组关联的场景
        removeSceneDatas.forEach { data in
            // 设备是否支持场景model
            if let sceneSetupModel = node.sceneSetupModel {
                // 删除场景
                messages.append(MeshMessageHandle(message: SceneDelete(data.sceneNumber), model: sceneSetupModel))
            }
        }
        
        // 设备中组关联的日程
       let removeSchedules = self.info.bindSchedules.filter { schedule in
           return node.schedulerActions.filter({ $0.value.isValid }).contains(where: { Int($0.key) == schedule.id })
        }
        // 设备删除日程
        removeSchedules.forEach { schedule in
            if let schedulerSetupModel = node.schedulerSetupModel {
                // 删除日程，协议不支持删除，将对应id的日程设置为无效数据
                messages.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: SchedulerRegistryEntry()), model: schedulerSetupModel))
            }
        }
        
        // 删除节点内model上报到组数据
        for element in node.elements {
            let publishModels = element.models.filter({ $0.publish?.publicationAddress == address })
            publishModels.forEach({
                messages.append(MeshMessageHandle(message: ConfigModelPublicationSet(disablePublicationFor: $0)!, address: node.primaryUnicastAddress))
            })
        }
        
        // 解除动能开关绑定
        self.info.allSwitchs.forEach { switchData in
            if switchData.linkGroup != nil {
                let unbindSwitchMessages = node.getEnOceanUnSubscriptionMessageHandles(switchKeys: switchData.switchKeys)
                messages.append(contentsOf: unbindSwitchMessages)
            }
        }
        // 解除动能开关代理
        if node.enOceanMacAddress?.count ?? 0 > 0, let switchData = self.info.allSwitchs.first(where: { $0.proxyNodeAddress == node.primaryUnicastAddress && $0.enOceanMacAddress == node.enOceanMacAddress }) {
            if switchData.linkGroup != nil {
                let disableSwitchMessages = node.getEnOceanSwitchDisableMessageHandles(switchKeys: switchData.switchKeys)
                messages.append(contentsOf: disableSwitchMessages)
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
        self.info.sceneExecuteDatas.forEach { data in
            // 设备是否支持场景model及亮度model
            if let sceneSetupModel = node.sceneSetupModel, let lightnessModel = node.lightnessModel {
                // 设备是否支持色温model
                let lightness = data.lightness
                if let ctlModel = node.ctlModel, node.temperatureModel != nil {
                    var message: MeshMessage!
//                    if ctlModel.publish?.publicationAddress.address == .allNodes { // 修改后等待主动上报
//                        message = LightCTLSetUnacknowledged(lightness: lightness, temperature: UInt16(data.cct), deltaUV: 0, transitionTime: .immediate, delay: 0)
//                    }else { // 不会上报设置ACK
                        message = LightCTLSet(lightness: lightness, temperature: data.cct, deltaUV: 0, transitionTime: .immediate, delay: 0)
//                    }
                    messages.append(MeshMessageHandle(message: message, model: ctlModel))
                }else { // 不支持则设置亮度
                    var message: MeshMessage!
//                    if lightnessModel.publish?.publicationAddress.address == .allNodes { // 修改后等待主动上报
//                        message = LightLightnessSetUnacknowledged(lightness: lightness, transitionTime: .immediate, delay: 0)
//                    }else { // 不会上报设置ACK
                        message = LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0)
//                    }
                    messages.append(MeshMessageHandle(message: message, model: lightnessModel))
                }
                // 保存场景
                messages.append(MeshMessageHandle(message: SceneStore(data.sceneNumber), model: sceneSetupModel))
                
//                if let vendorModel = node.sunricherVendorModel {
//                    // 保存场景前禁用灯光控制
////                    if node.lightLCProperty.lightControlEnabled {
//                        messages.insert(MeshMessageHandle(message: SunricherVendorSet(function: .lightControlEnabled(enabled: false)), model: vendorModel), at: 0)
////                    }
//                    // 保存完场景开启灯光控制
////                    if !node.lightLCProperty.lightControlEnabled {
////                        messages.append(MeshMessageHandle(message: SunricherVendorSet(code: .lightControlEnabled, parameters: .lightControlEnabled(enabled: true)), model: vendorModel))
////                    }
//                }
                
            }
        }
        // 设备需要新增/更新的日程
        let setSchedules = self.info.bindSchedules.filter { schedule in
            !node.schedulerActions.filter({ $0.value.isValid }).contains(where: { schedule.id == $0.key })
        }
        
        setSchedules.forEach { schedule in
            // 设置时区
            if let timeModel = node.timeModel {
                messages.append(MeshMessageHandle(message: Node.setLocalTimeMessage(), model: timeModel))
            }
            // 设置日程
            if let schedulerSetupModel = node.schedulerSetupModel {
                
//                let months: [Month] = Schedule.allMonths // schedule.enabled ? Schedule.allMonths : []
                // SchedulerRegistryEntry(year: .any(), month: .any(of: months), day: .any(), hour: .specific(hour: schedule.hour), minute: .specific(minute: schedule.minute), second: .specific(second: 0), dayOfWeek: .any(of: schedule.weekDays), action: schedule.enabled ? schedule.action : .noAction, transitionTime: .init(steps: UInt8(schedule.fadeTime), stepResolution: .seconds), sceneNumber: schedule.scene?.number ?? 0)
                messages.append(MeshMessageHandle(message: SchedulerActionSet(index: UInt8(schedule.id), entry: schedule.schedulerEntry), model: schedulerSetupModel))
            }
        }
        return messages
        
    }
    
}
