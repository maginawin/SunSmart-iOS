//
//  ScheduleServer.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/18.
//

import Foundation
import NordicSigMeshSDK

struct ScheduleServer {

    private struct ScheduleDeviceBatch {
        let node: Node
        let contextGroup: Group?
        let delete: Bool
    }
    
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
        var deviceBatches: [ScheduleDeviceBatch] = []
        // 传入需要设置的设备
        if let setNodes = setNodes, setNodes.count > 0 {
            setNodes.forEach { node in
                deviceBatches.append(
                    ScheduleDeviceBatch(node: node, contextGroup: nil, delete: false)
                )
            }
        }else { // 未传入需要设置的设备，默认根据配置保存设备
            let data = schedule.getNeedSyncDatas()

            data.deleteNodes.forEach { node in
                deviceBatches.append(
                    ScheduleDeviceBatch(node: node, contextGroup: nil, delete: true)
                )
            }

            data.deleteGroups.forEach { _, nodes in
                nodes.forEach { node in
                    deviceBatches.append(
                        ScheduleDeviceBatch(node: node, contextGroup: nil, delete: true)
                    )
                }
            }

            data.syncNodes.forEach { node in
                deviceBatches.append(
                    ScheduleDeviceBatch(node: node, contextGroup: nil, delete: false)
                )
            }

            data.syncGroups.forEach { group, nodes in
                nodes.forEach { node in
                    deviceBatches.append(
                        ScheduleDeviceBatch(
                            node: node,
                            contextGroup: group,
                            delete: false
                        )
                    )
                }
            }
        }

        guard !deviceBatches.isEmpty else {
            success?(schedule)
            return
        }

        runScheduleDeviceBatches(
            deviceBatches,
            schedule: schedule,
            index: 0,
            hadFailure: false
        ) { hadFailure in
            if hadFailure {
                failed?(schedule)
            } else {
                success?(schedule)
            }
        }
    }

    private static func runScheduleDeviceBatches(
        _ batches: [ScheduleDeviceBatch],
        schedule: Schedule,
        index: Int,
        hadFailure: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < batches.count else {
            completion(hadFailure)
            return
        }

        let batch = batches[index]
        guard let messageHandles = makeScheduleMessageHandles(
            schedule: schedule,
            batch: batch
        ) else {
            runScheduleDeviceBatches(
                batches,
                schedule: schedule,
                index: index + 1,
                hadFailure: true,
                completion: completion
            )
            return
        }
        guard !messageHandles.isEmpty else {
            runScheduleDeviceBatches(
                batches,
                schedule: schedule,
                index: index + 1,
                hadFailure: hadFailure,
                completion: completion
            )
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
            runScheduleDeviceBatches(
                batches,
                schedule: schedule,
                index: index + 1,
                hadFailure: hadFailure || resultMessageHandles.contains(where: { !$0.isSuccessful }),
                completion: completion
            )
        }
    }

    private static func makeScheduleMessageHandles(
        schedule: Schedule,
        batch: ScheduleDeviceBatch
    ) -> [MeshMessageHandle]? {
        if batch.delete {
            return schedule.getMessageHandles(node: batch.node, delete: true)
        }

        var messageHandles: [MeshMessageHandle] = []
        let timeSyncPlan = TimedScheduleTimeSyncPolicy.makePlan(
            hasTimeModel: batch.node.timeModel != nil,
            scheduleEnabledStates: [schedule.enabled]
        )
        if timeSyncPlan.requiresTimeSync {
            guard let timeModel = batch.node.timeModel,
                  let timeHandle = SiteTimeSetMessageFactory.makeHandle(
                      node: batch.node,
                      model: timeModel
                  ) else {
                return nil
            }
            timeHandle.continuous = false
            messageHandles.append(timeHandle)
        }
        messageHandles.append(
            contentsOf: schedule.getMessageHandles(
                node: batch.node,
                contextGroup: batch.contextGroup
            )
        )
        return messageHandles
    }
}
