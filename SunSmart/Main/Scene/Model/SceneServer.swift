//
//  SceneServer.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import Foundation
import NordicSigMeshSDK

struct SceneServer {
    
    /// 组操作成功回调
    typealias GroupOperateSuccessCallback = ((Scene)->Void)
    /// 组操作失败回调
    typealias GroupOperateFailedCallback = ((Scene)->Void)
    
    /// 删除场景
    /// - Parameters:
    ///   - scene: 场景
    ///   - success: 成功回调
    ///   - failed: 失败回调
    static func deleteScene(scene: Scene, success: GroupOperateSuccessCallback?, failed: GroupOperateFailedCallback?) {
        // 需要发送消息删除的组
        let deleteGroups = scene.info.groups.filter({ $0.nodes.count > 0 })
        
        if deleteGroups.isEmpty { // 不需要发送消息，直接删除缓存
            do {
               try deleteSceneData(scene: scene)
                success?(scene)
            } catch {
                failed?(scene)
            }
            return
        }
        
        let messageHandles = deleteGroups.map({ MeshMessageHandle(message: SceneDelete(scene.number), address: $0.address.address) })
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil) { messageHandle, _ in
         

        } failedBack: { messageHandle in

            
        } finishedBack: { resultMessageHandles in
            // 清除缓存数据
            // 删除成功的组list
            var successGroups: [Group] = []
            // 删除失败的组list
            var failedGroups: [Group] = []
            
            resultMessageHandles.forEach { messageHandle in
                guard messageHandle.message is SceneDelete else { return }
                for successAddress in messageHandle.respondAddresss {
                    if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: successAddress) {
                        node.delete(sceneId: scene.number)
                    }
                }
                
                if let groupAddress = messageHandle.address, let group = deleteGroups.first(where: { $0.address.address == groupAddress }) {
                    if messageHandle.isSuccessful { // 全部删除完成
                        group.delete(sceneId: scene.number)
                        scene.info.groups.removeAll(where: { $0.address.address == groupAddress })
                        successGroups.append(group)
                    }else { // 部分设备删除成功，设置组内场景数据为待删除状态
                        group.updateSceneState(sceneId: scene.number, state: .waitDelete)
                        failedGroups.append(group)
                    }
                }
            }
            if successGroups.count >= scene.info.groups.count { // 场景数据删除成功，下一步删除场景
                do {
                   try deleteSceneData(scene: scene)
                    success?(scene)
                } catch {
                    failed?(scene)
                }
            }else { // 场景数据删除未删除完成
                failed?(scene)
            }
        }

    }
    
    /// 删除场景
    static private func deleteSceneData(scene: Scene) throws {
        
        try MeshNetworkManager.instance.meshNetwork?.remove(scene: scene.number)
        _ = MeshNetworkManager.instance.save()
        // 删除场景扩展数据
        scene.delete()
    }
    
    
    
    
}
