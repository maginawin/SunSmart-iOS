//
//  DeviceBaseViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/17.
//

import UIKit
import NordicSigMeshSDK

class DeviceBaseViewController: UIViewController, DeviceProtocol {
   
    private var lastMessageDelegate: MeshLibManagerMessageDelegate?
    
    let space: SpaceData
    let node: Node

    init(space: SpaceData, node: Node) {
        self.space = space
        self.node = node
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = node.name
        view.backgroundColor = Background_Color
        
        self.lastMessageDelegate = MeshLibManager.manager.messageDelegate

        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            
            navigationController?.setNavigationBarBackgroundColor(color: .clear)
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.messageDelegate = self
        
        // 更新数据
        updateData()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        MeshLibManager.manager.messageDelegate = self.lastMessageDelegate
        
        NotificationCenter.default.post(name: .init(deviceStateUpdateNotificationName), object: self.node)
    }
    
    @objc private func backAction() {
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1  {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    /// 获取设备数据
    private func getNodeState() {
        
        MeshAPI.getNodeState(address: node.primaryUnicastAddress)
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5) {[weak self] nodes in
            guard let self = self else { return }
            if !nodes.contains(where: { $0.node.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.node.rssi = nil
            }
        }
        
    }
    
    /// 更新UI数据
    func updateData() {
        
        if node.isKeybindComplete {
            
            view.hideEmptyDataView()
            
            guard node.state else { // 离线
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
                return
            }
            view.hideEmptyDataView()
        } else {
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                    // 修复
                    self?.repair()
                }
                if let emptyView = view.emptyView {
                    if space.deviceOperates.contains(.edit) { // 是否有编辑设备权限
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                        }
                    }else {
                        emptyView.button.isHidden = true
                    }
                }
            }
        }
    }
    
    /// 修复
    private func repair() {
        
        repairDevices(nodes: [self.node], result: {[weak self] _, _ in
            guard let self = self else { return }
            if self.node.isKeybindComplete {
                self.updateData()
                self.getNodeState()
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
        })
    }
    
    @objc func moreClick() {
        
        var items: [MenuPopView.MenuItem] = []
        if space.deviceOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "edit"), title: "edit".localizedString, tapItemBack: {[weak self] _ in
                self?.editNode()
            }))
        }
        if space.deviceOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] _ in
                self?.deleteNode()
            }))
        }
        
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
            self?.information()
        }))
           
        items.append(.init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] _ in
            self?.refresh()
        }))
        
//        isIphoneX ? 18 : 15
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
//        SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
        
    }
    
    /// 编辑设备
    func editNode() {
        
        SRAlertView(title: "edit_name".localizedString, messageColor: Red_Color, messageFont: UIFont.systemFont(ofSize: 13, weight: .light), inputText: node.name, inputFieldStyle: .init(placeholder: ""), actions: [.cancelAction, .init(title: "done".localizedString, style: .default)]) {[weak self] text, validRange in
//            guard let self = self else { return }
             if !validRange && !text.isEmpty { // 长度超限
                 return "text_length_exceeded".localizedString
             }else if (MeshNetworkManager.instance.isNodeTautonym(nodeName: text) ) && text != self?.node.name { // 重名
                 return "name_already_exists".localizedString
             }
             return nil
         } inputDoneBack: {[weak self] text in
             guard let self = self else { return }
             self.title = text
             self.node.name = text
//             _ = self.space.meshManager?.save()
             self.node.save()
             // 通知space数据修改
             NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
             
         }.show()
    }
    
    /// 删除设备
    func deleteNode() {
        
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            
            self.deleteNodes(nodes: [node]) {[weak self] successNodes, failedNodes in
                guard let self = self else { return }
                if successNodes.contains(where: { $0.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                    self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                    self.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count
                    self.space.save()
                    DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                        // 通知space数据修改
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                        self.backAction()
                    }
                }
            }
        })]).show()
    }
    
    /// 信息
    func information() {
        
//        MeshAPI.setLightnessRange(address: node.primaryUnicastAddress, range: 255...65535)
        navigationController?.pushViewController(DeviceInformationViewController(node: self.node), animated: true)
    }
    
    /// 刷新
    func refresh() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 2)
        getNodeState()
    }
    
    
    
}


extension DeviceBaseViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
            updateData()
        }
    }
    
    /// 收到消息回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - message: 消息体
    ///   - source: 来源设备地址
    ///   - destination: 接收设备地址
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        if let node = manager.meshNetwork?.node(withAddress: source), !node.isProvisioner {
            node.updateData(message: message)
            if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
                updateData()
            }
        }
    }
    
}
