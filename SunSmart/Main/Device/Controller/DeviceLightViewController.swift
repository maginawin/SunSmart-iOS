//
//  DeviceLightViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/16.
//

import UIKit
import NordicSigMeshSDK

class DeviceLightViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var lightGrayBgView: UIImageView!
    private var lightBgView: UIImageView!
    private var lightImageBtn: UIButton!
    private var upDownLightView: UpDownLightView!
    private var brightnessView: UIView!
    private var brightnessImageView: UIImageView!
    private var brightnessLineView: UIView!
    private var brightnessLabel: UILabel!
    private var cctView: UIView!
    private var cctImageView: UIImageView!
    private var cctLineView: UIView!
    private var cctLabel: UILabel!
    
    private var onoffBtn: UIButton!
    private var controlPanelView: DeviceLightControlPanelView!
    private var upDownRatioView: DeviceUpDownRatioControlView!
    private var confirmedUpRatioValue = 50
    private var hasEditedUpRatioValue = false
    private var upRatioEditGeneration: UInt = 0
    private var upRatioCommandScheduler = UpDownRatioCommandScheduler()
    
    private var relayLabel: UILabel!
    private var relaySwitch: UISwitch!
    private var pwmPeriodLabel: UILabel!
    
    private var luxLabel: UILabel?
    private var emergencySignIdentifyButton: UIButton?
    private var elFunctionTestView: ELControllerFunctionTestView?
    private var elRxTxCableView: ELControllerFunctionTestView?
    private var elControllerFunctionTestHelper: ELControllerFunctionTestHelper?
    
    private weak var lastMessageDelegate: MeshLibManagerMessageDelegate?
    
    let space: SpaceData
    let node: Node

    private var supportsELControllerLocalFunctionViews: Bool {
        node.companyIdentifier == 0x0A78 && node.productIdentifier == 0x24C1
    }

    init(space: SpaceData, node: Node) {
        self.space = space
        self.node = node
        self.confirmedUpRatioValue = node.upRatio
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
            
            navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        }
//        menuView?.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
//        let tap = UITapGestureRecognizer(target: self, action: #selector(test))
//        tap.numberOfTapsRequired = 2
//        view.addGestureRecognizer(tap)
        
        
//        node.lightCTLTemperatureRange = 2700...6500
        // 初始化UI
        setupUI()
        if node.isEmergencySignController {
            setupEmergencySignUI()
        } else {
            // 根据设备类型显示UI
            updateUI()
            // 绑定事件
            bindSliderAction()
            getInitialUpRatioValue()
        }
        // 获取设备数据
        getNodeState()
        
//#if DEBUG
        updateRelayControlState()
        // 获取节点转发功能是否启用
        MeshAPI.getReplyState(address: node.primaryUnicastAddress, result: nil)
//        #if DEBUG
        if !node.isEmergencySignController, node.ambientLightSensorModel != nil {
            luxLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
            luxLabel?.isHidden = !node.preConfiguration.displayLux
            contentView.addSubview(luxLabel!)
            luxLabel!.snp.makeConstraints { make in
                make.left.equalTo(cctView.snp.right).offset(SCRXFrom(30))
                make.centerY.equalTo(brightnessLabel)
            }
        }
//        #endif
        // 读取pwm周期
//        if let model = node.sunricherVendorModel {
//            MeshAPI.sendMessage(message: SunricherVendorGet(function: .pwmPeriod), model: model)
//        }
//#else
//        replySwitch.isHidden = true
//        replyLabel.isHidden = true
//#endif
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.messageDelegate = self
        // 更新数据
        updateData()

        if supportsELControllerLocalFunctionViews {
            elControllerFunctionTestHelper?.startPageSession()
        }

        if !node.isEmergencySignController, node.ambientLightSensorModel != nil {
            getNodeAmbientSensorLux()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        elControllerFunctionTestHelper?.stopPageSession()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        MeshLibManager.manager.messageDelegate = self.lastMessageDelegate
        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
    }
    
    /// 获取设备数据
    @objc private func getNodeState() {
        
        MeshAPI.getNodeState(address: node.primaryUnicastAddress)
        if node.ambientLightSensorModel != nil {
            getNodeAmbientSensorLux()
        }
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 10, nodeScan: {[weak self] data in
            guard let self = self else { return }
            if data.node.primaryUnicastAddress == self.node.primaryUnicastAddress {
                self.node.rssi = data.rssi.intValue
                MeshLibManager.manager.stopRefreshNodesRSSI()
            }
        }, finished: nil)
    }
    
    /// 获取设备lux
    private func getNodeAmbientSensorLux() {
        guard node.ambientLightSensorModel != nil else {
            return
        }
        if self.luxLabel != nil {
            MeshAPI.getAmbientSensorValue(node: node) {[weak self] value in
                self?.luxLabel?.text = "\(value ?? self?.node.daylightLux ?? 0)lx"
            }
        }
        
    }
    
    /// 更新UI数据
    private func updateData(refreshControlPanel: Bool = true) {
        updateRelayControlState()

        if node.isEmergencySignController {
            updateEmergencySignData()
            return
        }
        
        if node.isKeybindComplete {
            
            view.hideEmptyDataView()
            
            guard node.state else { // 离线
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
                return
            }
            view.hideEmptyDataView()

            let lightness100 = node.isOn ? Node.getLightness100(lightness: node.lightness) : 0
            let isLightOn = node.isOn && node.lightness > 0
            let topLightOn = node.supportsUpDownRatioControl ? node.isOn : isLightOn
            let lightnessText = isLightOn && lightness100 == 0 ? "<1%" : "\(lightness100)%"
            
            updateTopLightView(lightness100: lightness100, isLightOn: topLightOn)
            
            brightnessLabel.text = lightnessText
            cctLabel.text = "\(node.temperature)K"
            upDownRatioView.upValue = node.upRatio
            if refreshControlPanel {
                updateControlPanel()
            }
            
//            pwmPeriodLabel.text = node.pwmPeriod != nil ? "pwm: \(node.pwmPeriod!)" : nil
            
        }else {
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                    // 修复
                    self?.repairBtnClick()
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

    private func updateRelayControlState() {
        relaySwitch.isOn = node.features?.relay == .enabled
        updateRelayControlVisibility()
    }

    private func updateRelayControlVisibility() {
        let shouldHideRelayControl = !node.supportsLightDetailRelayControl
        relaySwitch.isHidden = shouldHideRelayControl
        relayLabel.isHidden = shouldHideRelayControl
    }
    
    private func updateControlPanel() {
        let cctRange = node.effectiveCctRange
        let brightnessRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
        let brightnessValue = node.isOn ? Node.getLightness100(lightness: node.lightness) : 0
        controlPanelView.configure(.init(
            controlType: space.controlType,
            showCCTQuickButtons: space.showCCTQuickButtons,
            showsBrightness: node.supportDimming,
            showsCCT: node.singleDeviceDisplaySupportCct,
            brightnessValue: brightnessValue,
            brightnessRange: brightnessRange,
            cctValue: Int(node.clampEffectiveCct(node.temperature)),
            cctRange: Int(cctRange.lowerBound)...Int(cctRange.upperBound)
        ))
    }

    private func updateTopLightView(lightness100: Int, isLightOn: Bool) {
        if node.supportsUpDownRatioControl {
            lightGrayBgView.isHidden = true
            lightBgView.isHidden = true
            lightImageBtn.isHidden = true
            upDownLightView.isHidden = false
            onoffBtn.isSelected = isLightOn

            let temperature100 = node.singleDeviceDisplaySupportCct ? node.getEffectiveTemperature100(temperature: node.temperature) : 50
            upDownLightView.configure(.init(
                isOn: isLightOn,
                brightnessPercent: lightness100,
                temperaturePercent: temperature100,
                supportsCCT: node.singleDeviceDisplaySupportCct,
                upRatio: node.upRatio,
                downRatio: node.downRatio
            ))
            return
        }

        lightGrayBgView.isHidden = false
        lightBgView.isHidden = false
        lightImageBtn.isHidden = false
        upDownLightView.isHidden = true

        if isLightOn {
            lightImageBtn.isSelected = true
            onoffBtn.isSelected = true

            let progress = CGFloat(Float(lightness100) / 100.0) * 0.5
            var alpha = 0.5 + progress
            if self.node.singleDeviceDisplaySupportCct {
                let temperature100 = self.node.getEffectiveTemperature100(temperature: self.node.temperature)
                lightBgView.image = UIImage(named: "device_light_bg")?.withTintColor(Node.getCctMixColor(temperature100: temperature100))

                var garyBgAlpha: CGFloat = 0
                if temperature100 >= 45 && temperature100 <= 55 {
                    garyBgAlpha = 0.5
                    alpha = 1
                }
                if garyBgAlpha != lightGrayBgView.alpha {
                    UIView.animate(withDuration: 0.25) {
                        self.lightGrayBgView.alpha = garyBgAlpha
                    }
                }

            }else {
                lightBgView.image = UIImage(named: "device_light_bg")
            }
            lightBgView.alpha = alpha

        }else {
            lightImageBtn.isSelected = false
            onoffBtn.isSelected = false
            lightBgView.image = UIImage(named: "device_light_off_bg")
            lightBgView.alpha = 1
            if lightGrayBgView.alpha != 0 {
                UIView.animate(withDuration: 0.25) {
                    self.lightGrayBgView.alpha = 0
                }
            }
        }
    }
    
    @objc private func backAction() {
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1  {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func moreClick() {
        
//        var y = kNavigationHeight
//        if self.presentingViewController != nil {
//            y = StatusBarManager.statusBarFrame.height + (navigationController?.navigationBar.height ?? kNavigationHeight)
//        }
        let menuWidth = SCRXFrom(140)
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
        
        items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, hideAnimation: false, performsActionAfterDismiss: true, tapItemBack: {[weak self] _ in
            self?.information()
        }))
        // #if DEBUG
//        if routeTest {
//            items.append(.init(icon: UIImage(named: "menu_information"), title: "Route", hideAnimation: false, tapItemBack: {[weak self] _ in
//                self?.readRoute()
//            }))
//        }
        items.append(.init(icon: UIImage(named: "menu_set_proxy"), title: "set_proxy".localizedString, tapItemBack: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: nil, view: self.view)
            MeshLibManager.manager.connectProxy(node: self.node) {[weak self] result in
                guard let self = self else { return }
                XWHUDManager.hideInView(with: self.view)
                if result {
                    XWHUDManager.showSuccessTipHUD("successful".localizedString + " !")
                }else {
                    XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                }
                
            }
        }))
        items.append(.init(icon: UIImage(named: "menu_identify"), title: "identify".localizedString, tapItemBack: {[weak self] _ in
            guard let self = self else { return }
            self.sendIdentifyCommand()
//            let appkey = MeshNetworkManager.instance.meshNetwork?.applicationKeys.first
//            try? MeshNetworkManager.instance.send(AttentionSet(attentionTimer: 5), to: MeshAddress(self.node.primaryUnicastAddress), using:  MeshNetworkManager.instance.currentApplicationKey)
            
//            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.5) {
//                try? MeshNetworkManager.instance.send(AttentionSet(attentionTimer: 5), to: MeshAddress(87), using: appkey!)
//            }
//            87
        }))
        items.append(.init(icon: UIImage(named: "menu_firmware_update"), title: "reboot".localizedString, tapItemBack: {[weak self] _ in
            guard let self = self, let vendorModel = self.node.sunricherVendorModel else { return }
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .deviceRestart), model: vendorModel)
        }))
        // #endif
//        #if DEBUG
//        items.append(.init(icon: UIImage(named: "menu_edit"), title: "pwm_period".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
//            self?.setPwmPeriod()
//        }))
//        #endif
//        items.append(.init(icon: UIImage(named: "menu_edit"), title: "LED inverse", tapItemBack: {[weak self] _ in
//            self?.test()
//        }))
//        #endif
        if self.node.ambientLightSensorModel != nil {
            items.append(.init(icon: UIImage(named: "display_lux"), title: "display_lux".localizedString, tapItemBack: {[weak self] _ in
                self?.displayLux()
            }))
        }
     
        items.append(.init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] _ in
            self?.refresh()
        }))

        if space.deviceOperates.contains(.edit) {
            items.append(.init(
                icon: UIImage(named: "menu_debug"),
                title: "simulate_fault".localizedString,
                hideAnimation: false,
                performsActionAfterDismiss: true,
                tapItemBack: { [weak self] _ in
                    self?.showSimulateFault()
                }
            ))
        }
        
        
//        isIphoneX ? 18 : 15
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
//        SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: menuWidth) // SCRXFrom(114)
        
//        MenuPopView.show(items: items, anchorPoint: CGPoint(x: view.width - SCRXFrom(17) - 15, y: y), menuWidth: MenuPopView.defalutMenuWidth + SCRXFrom(10))
    }

    private func showSimulateFault() {
        guard space.deviceOperates.contains(.edit) else { return }
        guard presentedViewController == nil else { return }

        let controller = SimulateFaultViewController(space: space, node: node)
        present(controller, animated: true)
    }
    
    private func test() {
        if let model = node.sunricherVendorModel {
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .ledInversion(inversion: !node.ledInversion)), model: model)
        }
    }
    
    /// 读取路由表
    private func readRoute() {
        let otherNodes = MeshNetworkManager.instance.realNodes.filter({ $0.primaryUnicastAddress != self.node.primaryUnicastAddress })
        otherNodes.forEach({
            $0.routes.removeAll()
        })
        let vc = ReadDevicesDataViewController(type: .routeTableList(proxyAddress: self.node.primaryUnicastAddress, nodes: otherNodes))
        vc.readSuccessCallback = {[weak self] _ in
            self?.navigationController?.popViewController(animated: true)
            self?.exportRouteTableFile(nodes: otherNodes)
        }
        vc.backActionCallback = {[weak self] _ in
            self?.navigationController?.popViewController(animated: true)
            self?.exportRouteTableFile(nodes: otherNodes)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func exportRouteTableFile(nodes: [Node]) {
        guard nodes.contains(where: { $0.routes.count > 0 }) else {
            XWHUDManager.showErrorTipHUD("未找到路由信息")
            return
        }
        let routeTables = nodes.compactMap({ node in
            if node.routes.count > 0 {
                return ["name": node.name ?? "", "primaryUnicastAddress": node.primaryUnicastAddress, "routes": node.routes.map({ ["address": $0.address, "totalRssi": $0.totalRssi, "rssi": $0.rssi] })]
            }
            return nil
        })
        guard let data = try? JSONSerialization.data(withJSONObject: routeTables) else {
            XWHUDManager.showErrorTipHUD("导出数据失败")
            return
        }
        
        XWHUDManager.showHUD()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // 文件名称 网络名称_网络更新时间
            let date = Date()
            let formatter = DateFormatter.init()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            var timeStr = formatter.string(from: date)
            timeStr = timeStr.replacingOccurrences(of: " ", with: "T")
            timeStr = timeStr.replacingOccurrences(of: ":", with: "")
            
            let name = "\((node.name ?? ""))_routes_\(timeStr)"
            
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
            try? data.write(to: fileURL)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                // 适配 iPad
                if let popoverController = controller.popoverPresentationController {
                    // 设置 sourceView（可以是按钮或视图）
                    popoverController.sourceView = self.view
                    
                    // 设置 sourceRect（浮层的锚点位置）
                    popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                    
                    // 或者设置 barButtonItem（如果是导航栏按钮）
                    // popoverController.barButtonItem = self.shareButton
                }
                controller.completionWithItemsHandler = { type, success, items, error in
                    if success {
                        XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    }
                }
                self.present(controller, animated: true)
                
                XWHUDManager.hide()
            }
        }
    }
    
    
    private func syncDevice() {
        let vc = SyncDevicesViewController(type: .devices([node]))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 编辑设备
    private func editNode() {
        
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
             
//             self.lightBasicVc?.reloadNodeName(text)
//             reloadNodeName
             
         }.show()
    }
    
    /// 删除设备
    private func deleteNode() {
        
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            let deletionContext = DevicePermanentDeletionContext(node: self.node)
  
            MeshAPI.resetNode(address: self.node.primaryUnicastAddress) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                self?.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count
                self?.space.save()
                deletionContext.commit()
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                    // 通知space数据修改
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                    self?.backAction()
                }
            } resetFail: { _, error in
                XWHUDManager.hide()
                
                let alertView = SRAlertView(title: "notification".localizedString, actions: [.cancelAction, SRAlertAction(title: "force_delete".localizedString, style: .destructive, actionHandler: {[weak self] _ in
                    guard let self = self else { return }
                    deletionContext.commit()
                    MeshNetworkManager.instance.meshNetwork?.remove(node: self.node)
//                    _ = self.space.meshManager?.save()
                    self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                    self.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count
                    self.space.save()
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                        // 通知space数据修改
//                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                        self?.backAction()
                    }
                })])
                let messageAttStr = NSMutableAttributedString(string: "device_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
                messageAttStr.append(NSAttributedString(string: "device_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
                alertView.messageLabel.attributedText = messageAttStr
                alertView.show()
            }
            
        })]).show()
        
    }
    
    /// 修复设备
    @objc private func repairBtnClick() {
        
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_repair_offline".localizedString, isLineFeed: true)
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: "repairing".localizedString, isWindow: true)
        MeshAPI.startKeyBind(node: node, startKeyBind: nil) {[weak self] node in
            XWHUDManager.hide()
            if MeshLibManager.manager.bluetoothState == .poweredOn {
                XWHUDManager.showSuccessTipHUD("complete!".localizedString)
            }
            self?.updateUI()
            self?.updateData()
            self?.getNodeState()
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        } keyBindFail: {[weak self] _ in
            XWHUDManager.hide()
            self?.repairFailed()
            // 通知space数据修改
//            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: nil)
        }
        
    }
    
    /// 修复失败
    private func repairFailed() {
        
        let alertView = SRAlertView(message: "repair_failed_message".localizedString, messageFont: FONTS(SCRYFrom(15)), stateImage: UIImage(named: "alert_failed"), actions: [.cancelAction, SRAlertAction(title: "repair".localizedString, style: .default, actionHandler: {[weak self] _ in
            self?.repairBtnClick()
        })])
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
    
    /// 信息
    private func information() {
        
//        MeshAPI.setLightnessRange(address: node.primaryUnicastAddress, range: 255...65535)
        let showsSceneSection = !node.isEmergencySignController
        let lightTimeContext = LightTimeInformationContext(
            canConfigureTimeServer: space.deviceOperates.contains(.edit)
        )
        pushDeviceInformationController(
            DeviceInformationViewController(
                node: self.node,
                showsSceneSection: showsSceneSection,
                lightTimeContext: lightTimeContext
            )
        )
    }
    
    /// 设置
    private func settings() {
        
        
        
    }
    
    /// 显示/隐藏lux
    private func displayLux() {
        
        let displayLux = !node.preConfiguration.displayLux
        SRAlertView(title: "display_lux".localizedString, message: "display_lux_message".localizedString, tapBackgroundHide: true, actions: [.cancelAction,SRAlertAction(title: displayLux ? "show".localizedString : "hide".localizedString, actionHandler: {[weak self] _ in
            guard let self = self, let meshUUID = self.node.network?.uuid.uuidString else { return }
            
            self.luxLabel?.isHidden = !displayLux
            if displayLux {
                self.getNodeAmbientSensorLux()
            }
            self.node.preConfiguration.displayLux = displayLux
            self.node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: self.node.primaryUnicastAddress)
        })]).show()
        
    }
    
    /// 刷新
    private func refresh() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 2)
        getNodeState()
        refreshUpDownRatioValue(allowOverwriteEditedValue: true)
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5) {[weak self] nodeDatas in
            guard let self = self else { return }
            if !nodeDatas.contains(where: { $0.node.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.node.rssi = nil
            }
        }
    }
    
    // MARK: - Action
    
    @objc private func onoffAction(sender: UIControl) {
        guard !node.isEmergencySignController else {
            return
        }
        node.isOn = !node.isOn
        if node.isOn {
            let restoredLightness = node.trunOffLightness ?? node.lightnessRange.upperBound
            node.lightness = restoredLightness > 0 ? restoredLightness : node.lightnessRange.upperBound
        }else {
            if node.lightness > 0 {
                node.trunOffLightness = node.lightness
            }
            node.lightness = 0
        }
        sendLightDetailOnOffCommand()
        updateData(refreshControlPanel: false)
        updateControlPanel()
    }

    private func setupEmergencySignUI() {
        lightImageBtn.setImage(UIImage(named: "device_center_EMSign"), for: .normal)
        lightImageBtn.setImage(UIImage(named: "device_center_EMSign"), for: .selected)
        lightImageBtn.removeTarget(self, action: #selector(onoffAction), for: .touchUpInside)
        lightImageBtn.isUserInteractionEnabled = false
        lightImageBtn.isSelected = true
        lightImageBtn.snp.remakeConstraints { make in
            make.center.equalTo(lightBgView)
            make.width.height.equalTo(SCRYFit(48))
        }

        lightBgView.image = UIImage(named: "device_light_bg")
        lightBgView.alpha = 1
        lightGrayBgView.alpha = 0

        brightnessView.isHidden = true
        cctView.isHidden = true
        controlPanelView.isHidden = true
        upDownRatioView.isHidden = true
        onoffBtn.isHidden = true
        updateRelayControlState()

        let identifyButton = UIButton(normalImageName: "EMSign_identify", target: self, action: #selector(emergencySignIdentifyAction))
        identifyButton.imageView?.contentMode = .scaleAspectFit
        identifyButton.addTarget(self, action: #selector(emergencySignIdentifyTouchDown(_:)), for: .touchDown)
        identifyButton.addTarget(self, action: #selector(emergencySignIdentifyTouchDown(_:)), for: .touchDragEnter)
        identifyButton.addTarget(self, action: #selector(emergencySignIdentifyTouchUp(_:)), for: .touchUpInside)
        identifyButton.addTarget(self, action: #selector(emergencySignIdentifyTouchUp(_:)), for: .touchUpOutside)
        identifyButton.addTarget(self, action: #selector(emergencySignIdentifyTouchUp(_:)), for: .touchCancel)
        identifyButton.addTarget(self, action: #selector(emergencySignIdentifyTouchUp(_:)), for: .touchDragExit)
        contentView.addSubview(identifyButton)
        identifyButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(30))
            make.width.height.equalTo(isIPad ? 56 : 40)
            if !supportsELControllerLocalFunctionViews {
                make.bottom.lessThanOrEqualToSuperview().offset(SCRYFit(-8))
            }
        }
        emergencySignIdentifyButton = identifyButton

        if supportsELControllerLocalFunctionViews {
            let functionTestView = ELControllerFunctionTestView(kind: .functionTest)
            contentView.addSubview(functionTestView)
            functionTestView.snp.makeConstraints { make in
                make.top.equalTo(identifyButton.snp.bottom).offset(SCRYFit(30))
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            elFunctionTestView = functionTestView

            let rxTxCableView = ELControllerFunctionTestView(kind: .rxTxCable)
            contentView.addSubview(rxTxCableView)
            rxTxCableView.snp.makeConstraints { make in
                make.top.equalTo(functionTestView.snp.bottom).offset(SCRYFit(16))
                make.left.right.equalTo(functionTestView)
                make.bottom.lessThanOrEqualToSuperview().offset(SCRYFit(-8))
            }
            elRxTxCableView = rxTxCableView

            let helper = ELControllerFunctionTestHelper(node: node)
            helper.updateFunctionTestState = { [weak functionTestView] state in
                functionTestView?.applyFunctionTestState(state)
            }
            helper.updateRxTxState = { [weak rxTxCableView] state in
                rxTxCableView?.applyRxTxState(state)
            }
            helper.showOfflineMessage = {
                XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
            }
            elControllerFunctionTestHelper = helper

            functionTestView.onAction = { [weak self] in
                self?.elControllerFunctionTestHelper?.startFunctionTest()
            }
            rxTxCableView.onAction = { [weak self] in
                self?.elControllerFunctionTestHelper?.checkRxTxCable()
            }

            setELControllerFunctionViewsHidden(!node.isKeybindComplete || !node.state)
        }
    }

    private func setELControllerFunctionViewsHidden(_ hidden: Bool) {
        elFunctionTestView?.isHidden = hidden
        elRxTxCableView?.isHidden = hidden
    }

    private func handleELControllerVendorStatus(_ status: SunricherVendorStatus, sentFrom source: Address) {
        guard supportsELControllerLocalFunctionViews else { return }
        elControllerFunctionTestHelper?.handleStatus(status, sentFrom: source)
    }

    private func updateEmergencySignData() {
        brightnessView.isHidden = true
        cctView.isHidden = true
        controlPanelView.isHidden = true
        upDownRatioView.isHidden = true
        onoffBtn.isHidden = true
        updateRelayControlState()

        if node.isKeybindComplete {
            view.hideEmptyDataView()

            guard node.state else {
                elControllerFunctionTestHelper?.stopPageSession()
                emergencySignIdentifyButton?.isHidden = true
                setELControllerFunctionViewsHidden(true)
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
                return
            }

            view.hideEmptyDataView()
            emergencySignIdentifyButton?.isHidden = false
            setELControllerFunctionViewsHidden(false)
            emergencySignIdentifyButton?.isEnabled = true
            emergencySignIdentifyButton?.alpha = 1
            lightImageBtn.isSelected = true
            lightBgView.image = UIImage(named: "device_light_bg")
            lightBgView.alpha = 1
            lightGrayBgView.alpha = 0
        } else {
            elControllerFunctionTestHelper?.stopPageSession()
            emergencySignIdentifyButton?.isHidden = true
            setELControllerFunctionViewsHidden(true)
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) { [weak self] in
                    self?.repairBtnClick()
                }
                if let emptyView = view.emptyView {
                    if space.deviceOperates.contains(.edit) {
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                        }
                    } else {
                        emptyView.button.isHidden = true
                    }
                }
            }
        }
    }

    private func sendIdentifyCommand() {
        if node.isSupportVendorIdentify {
            guard let vendorModel = node.sunricherVendorModel else { return }
            sendTrackedVendorIdentifyCommand(model: vendorModel)
            return
        }

        LightGroupControlCommandSender.identify(address: node.primaryUnicastAddress)
    }

    private var lightAckDeviceName: String {
        LightAckProgressTracker.deviceName(node)
    }

    private func sendLightDetailOnOffCommand() {
        guard LabSettings.displayLightAckDetails else {
            LightGroupControlCommandSender.setNodeOnOff(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
            return
        }
        guard let model = node.onoffModel else {
            return
        }

        let commandDescription = node.isOn ? "on".localizedString : "off".localizedString
        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: commandDescription,
            opcode: GenericOnOffSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: GenericOnOffSet(node.isOn),
            model: model,
            context: context,
            defaultTTL: LabSettings.outgoingMeshTTLOverride
        )
    }

    private func sendLightDetailBrightnessCommand(percent: Int, lightness: UInt16) {
        guard LabSettings.displayLightAckDetails else {
            LightGroupControlCommandSender.setNodeLightness(address: node.primaryUnicastAddress, lightness: lightness, ack: true)
            return
        }
        guard let model = node.lightnessModel else {
            return
        }

        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: "\("brightness".localizedString) \(percent)%",
            opcode: LightLightnessSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: LightLightnessSet(lightness: lightness),
            model: model,
            context: context,
            defaultTTL: LabSettings.outgoingMeshTTLOverride
        )
    }

    private func sendLightDetailCCTCommand(temperature: UInt16) {
        guard LabSettings.displayLightAckDetails else {
            LightGroupControlCommandSender.setNodeColorTemperature(address: node.primaryUnicastAddress, temperature: temperature, ack: true)
            return
        }
        guard let model = node.temperatureModel else {
            return
        }

        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: "\(temperature)K",
            opcode: LightCTLTemperatureSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: LightCTLTemperatureSet(temperature: temperature, deltaUV: 0),
            model: model,
            context: context,
            defaultTTL: LabSettings.outgoingMeshTTLOverride
        )
    }

    private func sendTrackedVendorIdentifyCommand(model: Model) {
        let message = SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500)))

        guard LabSettings.displayLightAckDetails else {
            LightGroupControlCommandSender.sendVendorIdentify(message, model: model)
            return
        }

        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: "identify".localizedString,
            opcode: SunricherVendorSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: message,
            model: model,
            context: context,
            defaultTTL: LabSettings.outgoingMeshTTLOverride
        )
    }

    @objc private func emergencySignIdentifyAction() {
        guard node.isKeybindComplete, node.state else {
            XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
            return
        }
        sendIdentifyCommand()
    }

    @objc private func emergencySignIdentifyTouchDown(_ sender: UIButton) {
        setEmergencySignIdentifyButton(sender, pressed: true)
    }

    @objc private func emergencySignIdentifyTouchUp(_ sender: UIButton) {
        setEmergencySignIdentifyButton(sender, pressed: false)
    }

    private func setEmergencySignIdentifyButton(_ button: UIButton, pressed: Bool) {
        if pressed {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                button.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                button.alpha = 0.72
            }
            return
        }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.45,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            button.transform = .identity
            button.alpha = button.isEnabled ? 1 : 0.45
        }
    }
    
    private func bindSliderAction() {
        
        controlPanelView.brightnessValueChanged = {[weak self] value in
            guard let self = self else { return }
            self.applyBrightnessValue(value)
        }
        controlPanelView.brightnessThrottleValueChanged = {[weak self] value, ended in
            guard let self = self else { return }
            let lightness = Node.getLightness(lightness100: value)
            if ended {
                self.sendLightDetailBrightnessCommand(percent: value, lightness: lightness)
            } else {
                LightGroupControlCommandSender.setNodeLightness(address: self.node.primaryUnicastAddress, lightness: lightness)
            }
           
        }
        
        controlPanelView.cctValueChanged = {[weak self] value in
            guard let self = self else { return }
            self.applyCCTValue(value)
        }
        controlPanelView.cctThrottleValueChanged = {[weak self] value, ended in
            guard let self = self else { return }
            let temperature = self.node.clampEffectiveCct(UInt16(value))
            if ended {
                self.sendLightDetailCCTCommand(temperature: temperature)
            } else {
                LightGroupControlCommandSender.setNodeColorTemperature(address: self.node.primaryUnicastAddress, temperature: temperature)
            }
        }
        controlPanelView.cctQuickButtonValueSelected = { [weak self] value in
            self?.applyCCTQuickButtonValue(value)
        }
        controlPanelView.editBrightnessRequested = { [weak self] in
            self?.showBrightnessInputAlert()
        }
        controlPanelView.editCCTRequested = { [weak self] in
            self?.showCCTInputAlert()
        }
        upDownRatioView.valueChanging = { [weak self] value in
            guard let self else { return }
            self.hasEditedUpRatioValue = true
            self.upRatioEditGeneration &+= 1
            self.applyLocalUpRatioValue(value)
        }
        upDownRatioView.valueSampled = { [weak self] value in
            guard let self else { return }
            self.hasEditedUpRatioValue = true
            self.enqueueUpRatioCommand(value: value, kind: .sampling)
        }
        upDownRatioView.valueChanged = { [weak self] value in
            guard let self else { return }
            self.hasEditedUpRatioValue = true
            self.enqueueUpRatioCommand(value: value, kind: .final)
        }
    }

    private func getInitialUpRatioValue() {
        refreshUpDownRatioValue(allowOverwriteEditedValue: false)
    }

    private func refreshUpDownRatioValue(allowOverwriteEditedValue: Bool) {
        guard node.supportsUpDownRatioControl, let vendorModel = node.sunricherVendorModel else {
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .upDownLightUpRatio),
            model: vendorModel,
            timeout: 7
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self,
                      allowOverwriteEditedValue || !self.hasEditedUpRatioValue else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.isSuccessful,
                      case .upDownLightUpRatio(let value) = status.status.parameters else {
                    return
                }

                let upRatio = Int(value)
                self.confirmedUpRatioValue = upRatio
                self.saveLocalUpRatioValue(upRatio)
                self.upDownRatioView.upValue = upRatio
                self.updateData(refreshControlPanel: false)
            }
        }
    }

    private func applyLocalUpRatioValue(_ value: Int) {
        let clampedValue = max(0, min(100, value))
        node.upRatio = clampedValue
        updateData(refreshControlPanel: false)
    }

    private func saveLocalUpRatioValue(_ value: Int) {
        node.upRatio = max(0, min(100, value))
        if let meshUUID = node.network?.uuid.uuidString {
            node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
        }
    }

    private func rollbackUpRatioValue() {
        node.upRatio = confirmedUpRatioValue
        upDownRatioView.upValue = confirmedUpRatioValue
        updateData(refreshControlPanel: false)
    }

    private func enqueueUpRatioCommand(value: Int, kind: UpDownRatioCommandScheduler.Kind) {
        let command: UpDownRatioCommandScheduler.Command?
        switch kind {
        case .sampling:
            command = upRatioCommandScheduler.enqueueSampling(
                value: value,
                editGeneration: upRatioEditGeneration
            )
        case .final:
            command = upRatioCommandScheduler.enqueueFinal(
                value: value,
                editGeneration: upRatioEditGeneration
            )
        }
        if let command {
            sendUpRatioCommand(command)
        }
    }

    private func sendUpRatioCommand(_ command: UpDownRatioCommandScheduler.Command) {
        guard let vendorModel = node.sunricherVendorModel else {
            finishUpRatioCommand(command, succeeded: false)
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .upDownLightUpRatio(UInt8(command.value))),
            model: vendorModel,
            timeout: 7
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                let succeeded = (response as? SunricherVendorStatus).map {
                    $0.status.isSuccessful && $0.status.code == .upDownLightUpRatio
                } ?? false
                self.finishUpRatioCommand(command, succeeded: succeeded)
            }
        }
    }

    private func finishUpRatioCommand(
        _ command: UpDownRatioCommandScheduler.Command,
        succeeded: Bool
    ) {
        let isCurrentEdit = command.editGeneration == upRatioEditGeneration
        if succeeded {
            confirmedUpRatioValue = command.value
            if command.kind == .final {
                saveConfirmedUpRatioValue(command.value, preservingVisibleValue: !isCurrentEdit)
                if isCurrentEdit {
                    updateData(refreshControlPanel: false)
                }
            }
        } else if command.kind == .final, isCurrentEdit {
            rollbackUpRatioValue()
            ToastStatusView.show(in: view, message: "configuration_failed".localizedString, type: .failure)
        }

        if let nextCommand = upRatioCommandScheduler.completeCurrentCommand() {
            sendUpRatioCommand(nextCommand)
        }
    }

    private func saveConfirmedUpRatioValue(_ value: Int, preservingVisibleValue: Bool) {
        let visibleValue = node.upRatio
        saveLocalUpRatioValue(value)
        if preservingVisibleValue {
            node.upRatio = visibleValue
        }
    }

    private func applyBrightnessValue(_ value: Int) {
        let lightness = Node.getLightness(lightness100: value)

        if value == 0 && node.lightness > 0 {
            node.trunOffLightness = node.lightness
        }

        node.lightness = lightness
        node.isOn = lightness > 0
        updateData(refreshControlPanel: false)
    }

    private func applyCCTValue(_ value: Int) {
        node.temperature = node.clampEffectiveCct(UInt16(value))
        updateData(refreshControlPanel: false)
    }

    private func applyCCTQuickButtonValue(_ value: Int) {
        let range = controlPanelView.currentCCTRange
        let clampedValue = max(range.lowerBound, min(range.upperBound, value))
        if clampedValue != value {
            XWHUDManager.showTipHUD("cct_limit_reached_message".localizedString, isLineFeed: true)
        }
        controlPanelView.setCCTValue(clampedValue)
        applyCCTValue(clampedValue)
        sendLightDetailCCTCommand(temperature: UInt16(clampedValue))
    }

    private func showBrightnessInputAlert() {
        let range = controlPanelView.currentBrightnessRange
        showIntegerInputAlert(
            title: "brightness".localizedString,
            range: range
        ) { [weak self] value in
            guard let self = self else { return }
            self.controlPanelView.setBrightnessValue(value)
            self.applyBrightnessValue(value)
            self.sendLightDetailBrightnessCommand(percent: value, lightness: Node.getLightness(lightness100: value))
        }
    }

    private func showCCTInputAlert() {
        let range = controlPanelView.currentCCTRange
        showIntegerInputAlert(
            title: "color_temp".localizedString,
            range: range
        ) { [weak self] value in
            guard let self = self else { return }
            let normalizedValue = DeviceLightControlPanelView.normalizedCCTInputValue(value, range: range)
            let temperature = self.node.clampEffectiveCct(UInt16(normalizedValue))
            self.controlPanelView.setCCTValue(Int(temperature))
            self.applyCCTValue(Int(temperature))
            self.sendLightDetailCCTCommand(temperature: temperature)
        }
    }

    private func showIntegerInputAlert(title: String, range: ClosedRange<Int>, confirm: @escaping (Int) -> Void) {
        SRAlertView(
            title: title,
            inputText: nil,
            inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 5, textAlignment: .center, showClear: true),
            actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)],
            textValueChangedBack: nil
        ) { text in
            guard let value = Int(text) else {
                XWHUDManager.showTipHUD("illegal_input".localizedString, isLineFeed: true)
                return
            }
            let clamped = max(range.lowerBound, min(range.upperBound, value))
            confirm(clamped)
        }.show()
    }
    
    @objc private func relaySwitchValueChanged(sender: UISwitch) {
        sender.isEnabled = false
//        if sender.isOn {
//            MeshAPI.sendMessage(message: ConfigRelaySet(count: 1, steps: 1), address: node.primaryUnicastAddress)
//            MeshAPI.sendMessage(message: ConfigRelaySet(count: 1, steps: 1), model: <#T##Model#>, result: <#T##((StaticMeshResponse?) -> ())##((StaticMeshResponse?) -> ())##(StaticMeshResponse?) -> ()#>)
//        }
        
        
        MeshAPI.setReplyState(address: node.primaryUnicastAddress, enabled: sender.isOn) { successful in
            sender.isEnabled = true
            if !successful {
                sender.isOn = !sender.isOn
            }
        }
    }
    
    private func updateUI() {
        
        if node.singleDeviceDisplaySupportCct {
            cctView.isHidden = false
        }else {
            cctView.isHidden = true
        }
        
        if node.supportDimming {
            brightnessView.isHidden = false
            if node.singleDeviceDisplaySupportCct {
                brightnessView.snp.remakeConstraints { make in
                    make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-42))
                    make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(28))
                    make.height.equalTo(SCRYFrom(20))
                }
            }
        }else {
            brightnessView.isHidden = true
        }
        upDownRatioView.isHidden = !node.supportsUpDownRatioControl
        let usesUpDownLightView = node.supportsUpDownRatioControl
        upDownLightView.isHidden = !usesUpDownLightView
        lightGrayBgView.isHidden = usesUpDownLightView
        lightBgView.isHidden = usesUpDownLightView
        lightImageBtn.isHidden = usesUpDownLightView
        controlPanelView.isHidden = !node.supportDimming && !node.singleDeviceDisplaySupportCct
        
    }
    
    private func setupUI() {
        
        view.addSubview(scrollView)
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        relaySwitch = UISwitch()
        relaySwitch.onTintColor = Bar_Color
        relaySwitch.tintColor = RGB(207, 207, 207)
        relaySwitch.addTarget(self, action: #selector(relaySwitchValueChanged), for: .valueChanged)
        contentView.addSubview(relaySwitch)
        relaySwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFit(16))
        }

        relayLabel = UILabel(text: "relay".localizedString, textColor: TextBlack_Color, fontSize: 13)
        contentView.addSubview(relayLabel)
        relayLabel.snp.makeConstraints { make in
            make.centerY.equalTo(relaySwitch)
            make.right.equalTo(relaySwitch.snp.left).offset(SCRXFrom(-6))
        }

        lightGrayBgView = UIImageView(image: UIImage(named: "device_light_gray_bg"))
        lightGrayBgView.alpha = 0
        contentView.addSubview(lightGrayBgView)
        lightGrayBgView.snp.makeConstraints { make in

            make.centerX.equalToSuperview()
//            make.width.equalTo(lightBgView.snp.height)
            if isIPad {
                make.width.height.equalTo(SCRYFit(238))
            }else {
                make.width.height.equalTo(SCRYFit(200))
            }
            make.top.equalTo(relaySwitch.snp.bottom)

        }
        
        lightBgView = UIImageView(image: UIImage(named: "device_light_bg"))
        contentView.addSubview(lightBgView)
        lightBgView.snp.makeConstraints { make in
//            make.top.equalTo(SCRYFit(108))
            make.centerX.equalToSuperview()
            make.top.width.height.equalTo(lightGrayBgView)
//            make.width.equalTo(lightBgView.snp.height)
//            make.width.height.equalTo(SCRYFit(200))
        }
        
        lightImageBtn = UIButton(normalImageName: "device_light_control_off", selectedImageName: "device_light_control_on", target: self, action: #selector(onoffAction))
        contentView.addSubview(lightImageBtn)
        lightImageBtn.snp.makeConstraints { make in
            make.center.equalTo(lightBgView)
            if isIPad {
                make.width.height.equalTo(67)
            }
        }

        upDownLightView = UpDownLightView()
        upDownLightView.isHidden = true
        upDownLightView.addTarget(self, action: #selector(onoffAction), for: .touchUpInside)
        contentView.addSubview(upDownLightView)
        upDownLightView.snp.makeConstraints { make in
            make.centerX.equalTo(lightBgView)
            make.top.equalTo(lightGrayBgView)
            make.width.equalTo(UpDownLightView.preferredSize.width)
            make.height.equalTo(UpDownLightView.preferredSize.height)
        }
        
        brightnessView = UIView()
        contentView.addSubview(brightnessView)
        brightnessView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(isIPad ? 68 : 28))
            make.height.equalTo(SCRYFrom(20))
        }
        
        brightnessImageView = UIImageView(image: UIImage(named: "device_brightness"))
        brightnessView.addSubview(brightnessImageView)
        brightnessImageView.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(20))
        }
        
        brightnessLineView = UIView()
        brightnessLineView.backgroundColor = RGB(148, 163, 184)
        brightnessView.addSubview(brightnessLineView)
        brightnessLineView.snp.makeConstraints { make in
            make.left.equalTo(brightnessImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(12))
        }
        brightnessLabel = UILabel(text: "100%", textColor: TextBlack_Color, fontSize: 14)
        brightnessView.addSubview(brightnessLabel)
        brightnessLabel.sizeToFit()
        brightnessLabel.snp.makeConstraints { make in
            make.left.equalTo(brightnessLineView.snp.right).offset(SCRXFrom(6))
            make.centerY.right.equalToSuperview()
            make.width.equalTo(brightnessLabel.width)
        }
        
        cctView = UIView()
        contentView.addSubview(cctView)
        cctView.snp.makeConstraints { make in
            make.left.equalTo(contentView.snp.centerX).offset(SCRXFrom(22))
            make.centerY.height.equalTo(brightnessView)
        }
        
        cctImageView = UIImageView(image: UIImage(named: "device_cct"))
        cctView.addSubview(cctImageView)
        cctImageView.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(20))
        }
        
        cctLineView = UIView()
        cctLineView.backgroundColor = RGB(148, 163, 184)
        cctView.addSubview(cctLineView)
        cctLineView.snp.makeConstraints { make in
            make.left.equalTo(cctImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(12))
        }
        cctLabel = UILabel(text: "4000K", textColor: TextBlack_Color, fontSize: 14)
        cctView.addSubview(cctLabel)
        cctLabel.sizeToFit()
        cctLabel.snp.makeConstraints { make in
            make.left.equalTo(cctLineView.snp.right).offset(SCRXFrom(6))
            make.centerY.right.equalToSuperview()
            make.width.greaterThanOrEqualTo(cctLabel.width)
        }
        
        controlPanelView = DeviceLightControlPanelView()
        contentView.addSubview(controlPanelView)

        upDownRatioView = DeviceUpDownRatioControlView()
        upDownRatioView.isHidden = true
        contentView.addSubview(upDownRatioView)
        
        var offImageName = "device_control_off"
        var onImageName = "device_control_on"
        var disableImageName = "group_control_disable"
        if isIPad {
            offImageName = "device_control_off_big"
            onImageName = "device_control_on_big"
            disableImageName = "group_control_disable_big"
        }
        
        onoffBtn = UIButton(normalImageName: offImageName, selectedImageName: onImageName, target: self, action: #selector(onoffAction))
        onoffBtn.setImage(UIImage(named: disableImageName), for: .disabled)
        contentView.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if isIPad {
                make.width.height.equalTo(56)
            }
            if node.supportsUpDownRatioControl {
                make.top.equalTo(upDownRatioView.snp.bottom).offset(SCRYFit(isIPad ? 40 : 20))
            } else {
                if isIPad {
                    make.top.equalTo(lightImageBtn.snp.bottom).offset(SCRYFit(250))
                } else {
                    make.top.equalTo(brightnessView.snp.bottom).offset(SCRYFit(40))
                }
            }
        }

        upDownRatioView.snp.makeConstraints { make in
            make.top.equalTo(brightnessView.snp.bottom).offset(SCRYFit(20))
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.equalTo(SCRXFrom(30))
                make.right.equalTo(SCRXFrom(-29))
            }
        }

        controlPanelView.snp.makeConstraints { make in
            make.top.equalTo(onoffBtn.snp.bottom).offset(isIPad ? (node.supportsUpDownRatioControl ? 16 : 80) : node.supportsUpDownRatioControl ? 4 : 16)
            make.bottom.equalToSuperview().offset(SCRYFit(-8))
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.equalTo(SCRXFrom(30))
                make.right.equalTo(SCRXFrom(-29))
            }
        }
        
//        pwmPeriodLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)
//        view.addSubview(pwmPeriodLabel)
//        pwmPeriodLabel.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(20))
//            make.centerY.equalTo(replySwitch)
//        }
    }

}

extension DeviceLightViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
            updateData()
        }
    }
    
    /// 设备数据修改时间戳更新
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdateTimeChange node: Node, lastUpdate: Int64) {
//        if node.lastUpdateSyncTime != lastUpdate {
            node.clearSyncStateCache()
//        }
    }
    
    /// 收到消息回调
    /// - Parameters:
    ///   - manager: mesh网络管理
    ///   - message: 消息体
    ///   - source: 来源设备地址
    ///   - destination: 接收设备地址
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        if let status = message as? SunricherVendorStatus {
            handleELControllerVendorStatus(status, sentFrom: source)
        }

        if let node = manager.meshNetwork?.node(withAddress: source), !node.isProvisioner {
            node.updateData(message: message)
            if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
                updateData()
            }
        }
    }
    
}
