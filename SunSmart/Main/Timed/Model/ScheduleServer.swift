//
//  ScheduleServer.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/18.
//

import Foundation
import NordicSigMeshSDK

struct ScheduleServer {
    
    /// 日程操作成功回调
    typealias ScheduleOperateSuccessCallback = ((Schedule)->Void)
    /// 日程操作失败回调
    typealias ScheduleOperateFailedCallback = ((Schedule)->Void)
    
    
    /// 设置日程启用/启用
    /// - Parameters:
    ///   - schedule: 日程
    ///   - enabled: 是否启用
    ///   - success: 成功回调
    ///   - failed: 失败回调
    static func setEnabledState(schedule: Schedule, enabled: Bool, success: ScheduleOperateSuccessCallback?, failed: ScheduleOperateFailedCallback?) {
        
        var setNodes: [Node] = []
        
        setNodes.append(contentsOf: schedule.nodes)
        setNodes.append(contentsOf: schedule.needDeleteNodes.filter({ !setNodes.contains($0) }))
        
        schedule.groups.forEach({
            setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
        })
        schedule.needDeleteGroups.forEach({
            setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
        })
        
        schedule.scene?.info.groups.forEach({
            setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
        })
        schedule.needDeleteScenes.forEach { scene in
            scene.info.groups.forEach({
                setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
            })
        }
        
        let previousEnabled = schedule.enabled
        schedule.enabled = enabled
        setNodes = setNodes.filter { schedule.needsSync(on: $0) }
        
        let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString

        saveSchedule(schedule: schedule, setNodes: setNodes) { _ in
            
//            schedule.enabled = enabled
            schedule.save()
            success?(schedule)
            
        } failed: { _ in
            // 部分设备设置成功。设备失败则算开启/关闭，失败设备需去同步
            if setNodes.contains(where: { !schedule.needsSync(on: $0) }) {
                
                schedule.enabled = enabled
                if meshUUID != nil {
                    schedule.save()
                }
            }else {
                schedule.enabled = previousEnabled
            }
            failed?(schedule)
        }
        
    }
    
    
    /// 删除日程
    /// - Parameters:
    ///   - schedule: 日程
    ///   - success: 成功回调
    ///   - failed: 失败回调
    static func deleteSchedule(schedule: Schedule, success: ScheduleOperateSuccessCallback?, failed: ScheduleOperateFailedCallback?) {
        
//      日程删除 => (action=noAction)
//      日程关闭 => (month=空 && action != noAction)
        // 更新缓存，删除本地设备数据
        schedule.action = .noAction
        
        schedule.needDeleteNodeAddresses.append(contentsOf: schedule.nodes.map({ $0.primaryUnicastAddress }))
        schedule.nodeAddresses.removeAll()
        
        schedule.needDeleteGroupAddresses.append(contentsOf: schedule.groups.map({ $0.address.address }))
        schedule.groupAddresses.removeAll()
        
        if let scene = schedule.scene {
            schedule.needDeleteSceneNumbers.append(scene.number)
            schedule.sceneNumber = nil
        }
        schedule.save()
        
        
//        var setNodes: [Node] = []
//        
//        setNodes.append(contentsOf: schedule.nodes)
//        setNodes.append(contentsOf: schedule.needDeleteNodes.filter({ !setNodes.contains($0) }))
//        
//        schedule.groups.forEach({
//            setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
//        })
//        schedule.needDeleteGroups.forEach({
//            setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
//        })
//        
//        schedule.scene?.info.groups.forEach({
//            setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
//        })
//        schedule.needDeleteScenes.forEach { scene in
//            scene.info.groups.forEach({
//                setNodes.append(contentsOf: $0.nodes.filter({ !setNodes.contains($0) }))
//            })
//        }
//        setNodes = setNodes.filter({ $0.scheduleDatas.keys.contains(schedule.id) })
        
        saveSchedule(schedule: schedule) { _ in
//            if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
            schedule.deleteData()
            MeshNetworkManager.instance.schedules.removeAll(where: { $0.id == schedule.id })
//            }
            success?(schedule)
        } failed: { _ in
            failed?(schedule)
        }
    }
    
    /// 保存日程
    /// - Parameters:
    ///   - schedule: 日程
    ///   - setNodes: 设置设备（传入则config日程数据）
    ///   - success: 成功回调
    ///   - failed: 失败回调
    static func saveSchedule(schedule: Schedule, setNodes: [Node]? = nil, success: ScheduleOperateSuccessCallback?, failed: ScheduleOperateFailedCallback?) {
        
        // 发送的消息操作
        var messageHandles: [MeshMessageHandle] = []
        // 传入需要设置的设备
        if let setNodes = setNodes, setNodes.count > 0 {
            setNodes.forEach({
                messageHandles.append(contentsOf: DeviceOperationType.configuration(node: $0, type: .schedule(schedule: schedule)).messageHandles)
            })
            
        }else { // 未传入需要设置的设备，默认根据配置保存设备
            let data = schedule.getNeedSyncDatas()
            
            data.deleteNodes.forEach({
                messageHandles.append(contentsOf: DeviceOperationType.delete(node: $0, type: .schedule(schedule: schedule)).messageHandles)
            })
            
            data.deleteGroups.forEach({
                $0.value.forEach({ node in
                    messageHandles.append(contentsOf: DeviceOperationType.delete(node: node, type: .schedule(schedule: schedule)).messageHandles)
                })
            })
            
            data.syncNodes.forEach({
                messageHandles.append(contentsOf: DeviceOperationType.configuration(node: $0, type: .schedule(schedule: schedule)).messageHandles)
            })
            
            data.syncGroups.forEach { group, nodes in
                nodes.forEach { node in
                    messageHandles.append(
                        contentsOf: schedule.getMessageHandles(
                            node: node,
                            contextGroup: group
                        )
                    )
                }
            }
        }
        if messageHandles.isEmpty {
            success?(schedule)
            return
        }
        
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil) { messageHandle, _ in
            if let address = messageHandle.address ?? messageHandle.model?.parentElement?.unicastAddress, 
                let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.updateData(
                    message: messageHandle.message,
                    model: messageHandle.model
                )
            }
            
        } failedBack: { messageHandle in
            print("node send message failed \(messageHandle.message)")
        } finishedBack: { resultMessageHandles in
            
            if resultMessageHandles.contains(where: { !$0.isSuccessful }) { // 设置失败
                failed?(schedule)
            }else { // 成功
                success?(schedule)
            }
            
        }
        
    }
    
}
