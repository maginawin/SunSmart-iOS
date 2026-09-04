//
//  DeviceProtocol.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/17.
//

import Foundation
import NordicSigMeshSDK

protocol DeviceProtocol {
    
    /// 设备结果回调
    typealias DevicesResultCallback = (_ successNodes: [Node], _ failedNodes: [Node])->Void
    
    /// 修复设备
    func repairDevices(nodes: [Node], result: DevicesResultCallback?)
    
    /// 修复设备失败
    func showRepairFailed(continue nodes: [Node], result: DevicesResultCallback?)
    
    /// 删除设备
    func deleteNodes(nodes: [Node], forceDeleteMessage: String?, forceDeleteNote: String?, result: DevicesResultCallback?)

    /// 永久删除后同步仍存在设备的邻近照明目标。
    func syncPermanentDeletionPeers(
        _ results: [ProximityLightingLifecycleResult],
        completion: @escaping () -> Void
    )
    
}

extension DeviceProtocol {
    
    /// 修复设备
    func repairDevices(nodes: [Node], result: DevicesResultCallback?) {
        
        // 是否连接网络
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_repair_offline".localizedString, isLineFeed: true)
            return
        }
        // 多设备配置
        if nodes.count > 1 {
            let alertView =  SRAlertView(title: "repairing".localizedString, titleFont: FONTS(SCRYFrom(15)), message: "0/\(nodes.count)", messageColor: TextBlack_Color, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "loading_big"), loadingState: true, btnText: "STOP".localizedString, btnTextColor: .white, btnTextFont: Font_Medium_Size(SCRYFrom(15))) {
                SRAlertView.hide()
                MeshAPI.stopKeyBind(keyBindFinish: nil)
                result?(nodes.filter({ $0.isKeybindComplete }), nodes.filter({ !$0.isKeybindComplete }))
            }
            alertView.show()
            
            MeshAPI.startKeyBind(nodes: nodes, startKeyBind: { node in
                let index = (nodes.firstIndex(of: node) ?? 0) + 1
                alertView.messageLabel.text = "\(index)/\(nodes.count)"
            }, keyBindSuccess: nil, keyBindFail: nil) { successList, failList in
                SRAlertView.hide()
                if failList.isEmpty { // 全部修复成功
                    if MeshLibManager.manager.bluetoothState == .poweredOn {
                        XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                    }
                    result?(nodes, [])
                }else { // 全部/部分修复失败
                    //                    result?([], nodes)
                    self.showRepairFailed(continue: nodes, result: result)
                }
            }
            
        }else { // 单设备配置
            XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)
            
            MeshAPI.startKeyBind(node: nodes.first!, startKeyBind: nil) { node in
                XWHUDManager.hide()
                if MeshLibManager.manager.bluetoothState == .poweredOn {
                    XWHUDManager.showSuccessTipHUD("complete!".localizedString)
                }
                result?([node], [])
                // 通知space数据修改
                //                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                //                MeshAPI.getNodeCTLState(address: node.primaryUnicastAddress)
            } keyBindFail: { _ in
                XWHUDManager.hide()
                //                self?.updateUI()
                //                complete?([], nodes)
                self.showRepairFailed(continue: nodes, result: result)
                // 通知space数据修改
                //                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
        }
    }
    
    /// 修复设备失败
    func showRepairFailed(continue nodes: [Node], result: DevicesResultCallback?) {
        
        let actions: [SRAlertAction] = [
            SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { _ in
                result?(nodes.filter({ $0.isKeybindComplete }), nodes.filter({ !$0.isKeybindComplete }))
            }),
            SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: { _ in
                self.repairDevices(nodes: nodes, result: result)
            })
        ]
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: actions)
        alertView.stateImageView.snp.remakeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.centerX.equalToSuperview()
        }
        alertView.messageLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(27))
            make.right.equalTo(SCRXFrom(-27))
            make.top.equalTo(alertView.stateImageView.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.hLineView.snp.remakeConstraints { make in
            make.left.right.equalTo(0)
            make.height.equalTo(0.5)
            make.top.equalTo(alertView.messageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        alertView.show()
        
    }
    
    /// 删除设备
    func deleteNodes(nodes: [Node], forceDeleteMessage: String? = nil, forceDeleteNote: String? = nil, result: DevicesResultCallback?) {
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        let deletionContexts = Dictionary(uniqueKeysWithValues: nodes.map {
            ($0.primaryUnicastAddress, DevicePermanentDeletionContext(node: $0))
        })
        
        MeshAPI.resetNodes(addressList: nodes.map({ $0.primaryUnicastAddress }), resetSuccess: nil, resetFail: nil, resetFinish: { successAddressList, failAddressList in
            XWHUDManager.hide()
            let successNodes = nodes.filter({ successAddressList.contains($0.primaryUnicastAddress) })
            var lifecycleResults = successNodes.compactMap {
                deletionContexts[$0.primaryUnicastAddress]?.commit()
            }
            if failAddressList.isEmpty { // 删除成功
                if MeshNetworkManager.instance.realNodes.isEmpty, MeshLibManager.manager.isMeshNetworkConnected {
                    MeshLibManager.manager.close()
                }
                self.syncPermanentDeletionPeers(lifecycleResults) {
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    result?(nodes, [])
                }
                
            }else { // 删除失败（提示是否强制删除这部分设备）
                
                
                let failedNodes = nodes.filter({ failAddressList.contains($0.primaryUnicastAddress) })
                
                let alertView = SRAlertView(title: "notification".localizedString, actions: [SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { _ in
                    self.syncPermanentDeletionPeers(lifecycleResults) {
                        result?(successNodes, failedNodes)
                    }
                    
                }), SRAlertAction(title: "force_delete".localizedString, actionHandler: { _ in
                    failedNodes.forEach { node in
                        MeshNetworkManager.instance.meshNetwork?.remove(node: node)
                        if let lifecycleResult = deletionContexts[node.primaryUnicastAddress]?.commit() {
                            lifecycleResults.append(lifecycleResult)
                        }
                    }
                    self.syncPermanentDeletionPeers(lifecycleResults) {
                        XWHUDManager.showSuccessTipHUD("done!".localizedString)
                        result?(nodes, [])
                    }
                })])
                let messageAttStr = NSMutableAttributedString(string: forceDeleteMessage ?? "devices_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
                messageAttStr.append(NSAttributedString(string: forceDeleteNote ?? "devices_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
                alertView.messageLabel.attributedText = messageAttStr
                alertView.show()
            }
            
            
        })
        
    }
    
}

extension DeviceProtocol where Self: UIViewController {

    func syncPermanentDeletionPeers(
        _ results: [ProximityLightingLifecycleResult],
        completion: @escaping () -> Void
    ) {
        let datas = ProximityLightingLifecycleCoordinator.mergedSyncDatas(from: results)
        guard MeshLibManager.manager.isMeshNetworkConnected, !datas.isEmpty else {
            completion()
            return
        }
        let vc = SyncDevicesViewController(type: .spaceTriggerZones(datas: datas))
        var didFinish = false
        let finish = { [weak vc] in
            guard !didFinish else { return }
            didFinish = true
            if let vc, vc.navigationController?.topViewController === vc {
                vc.navigationController?.popViewController(animated: false)
            }
            completion()
        }
        vc.syncSuccessCallback = { _ in finish() }
        vc.backActionCallback = { _ in finish() }
        navigationController?.pushViewController(vc, animated: true)
    }
}
