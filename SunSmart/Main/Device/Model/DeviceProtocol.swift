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
    func deleteNodes(nodes: [Node], space: SpaceData?, forceDeleteMessage: String?, forceDeleteNote: String?, result: DevicesResultCallback?)

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
    
    /// Deletion completion is local persistence, independent of cloud and peer sync.
    func deleteNodes(nodes: [Node], space: SpaceData? = nil, forceDeleteMessage: String? = nil,
                     forceDeleteNote: String? = nil, result: DevicesResultCallback?) {
        guard !nodes.isEmpty else { result?([], []); return }
        Task { @MainActor in
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            guard let target = space ?? nodes.first.flatMap({ node in
                node.network.flatMap { network in
                    SpaceData.load(siteId: network.uuid.uuidString).first { $0.meshNetworkId == node.subNetworkId }
                }
            }), await SpaceConfigurationSafety.prepareForDeviceDeletion(target) else {
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
                result?([], nodes)
                return
            }
            let contexts = nodes.map { DevicePermanentDeletionContext(node: $0, space: target) }
            guard contexts.allSatisfy({ $0.isPrepared }) else {
                contexts.forEach { $0.cancel() }
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
                result?([], nodes)
                return
            }
            let finish = {
                let success = zip(nodes, contexts).filter { $0.1.wasRemoved }.map { $0.0 }
                let failed = zip(nodes, contexts).filter { !$0.1.wasRemoved }.map { $0.0 }
                // Removal, cleanup and cloud confirmation have separate outcomes.
                // Remaining peers retain their dirty configuration for later sync.
                if !success.isEmpty && failed.isEmpty { DevicePermanentDeletionContext.showCompletion(space: target) }
                result?(success, failed)
            }
            let resetFinished: () -> Void = {
                XWHUDManager.hide()
                contexts.forEach { _ = $0.commit() }
                let remaining = contexts.filter { !$0.wasRemoved }
                guard !remaining.isEmpty else { finish(); return }
                let alertView = SRAlertView(title: "notification".localizedString, actions: [
                    SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { _ in
                        remaining.forEach { $0.cancel() }
                        finish()
                    }),
                    SRAlertAction(title: "force_delete".localizedString, style: .destructive, actionHandler: { _ in
                        remaining.forEach { _ = $0.forceRemove() }
                        if remaining.contains(where: { !$0.wasRemoved }) {
                            XWHUDManager.showErrorTipHUD("configuration_deletion_cleanup_pending".localizedString)
                        }
                        finish()
                    })
                ])
                let message = NSMutableAttributedString(string: forceDeleteMessage ?? "devices_force_delete_message".localizedString,
                    attributes: [.foregroundColor: TextBlack_Color])
                message.append(NSAttributedString(string: forceDeleteNote ?? "devices_force_delete_note".localizedString,
                    attributes: [.foregroundColor: Message_Color]))
                alertView.messageLabel.attributedText = message
                alertView.show()
            }
            var resetNodes = zip(nodes, contexts).filter { $0.1.canReset }.map { $0.0 }
            // Preserve the proxy-last behavior and short timeout for offline lights.
            resetNodes.sort { !$0.isProxy && $1.isProxy }
            guard !resetNodes.isEmpty else { resetFinished(); return }
            MeshAPI.resetNodes(addressDataList: resetNodes.map { ($0.primaryUnicastAddress, $0.state || $0.isProxy ? 10 : 2) },
                resetSuccess: nil, resetFail: nil) { _, _ in resetFinished() }
        }
    }
}
