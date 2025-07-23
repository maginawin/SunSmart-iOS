//
//  DeviceLightViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/16.
//

import UIKit
import NordicSigMeshSDK

class DeviceLightViewController: UIViewController {

    private var lightGrayBgView: UIImageView!
    private var lightBgView: UIImageView!
    private var lightImageBtn: UIButton!
    private var brightnessView: UIView!
    private var brightnessImageView: UIImageView!
    private var brightnessLineView: UIView!
    private var brightnessLabel: UILabel!
    private var cctView: UIView!
    private var cctImageView: UIImageView!
    private var cctLineView: UIView!
    private var cctLabel: UILabel!
    
    private var onoffBtn: UIButton!
    private var lightnessSlider: BuoySliderView!
    private var cctSlider: BuoySliderView!
    
    private var replyLabel: UILabel!
    private var replySwitch: UISwitch!
    private var pwmPeriodLabel: UILabel!
    
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
//        menuView?.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
//        let tap = UITapGestureRecognizer(target: self, action: #selector(test))
//        tap.numberOfTapsRequired = 2
//        view.addGestureRecognizer(tap)
        
        
//        node.lightCTLTemperatureRange = 2700...6500
        // 初始化UI
        setupUI()
        // 根据设备类型显示UI
        updateUI()
        // 绑定事件
        bindSliderAction()
        // 获取设备数据
        getNodeState()
        
#if DEBUG
        replySwitch.isHidden = false
        replyLabel.isHidden = false
        // 获取节点转发功能是否启用
        MeshAPI.getReplyState(address: node.primaryUnicastAddress, result: nil)
        
        // 读取pwm周期
//        if let model = node.sunricherVendorModel {
//            MeshAPI.sendMessage(message: SunricherVendorGet(function: .pwmPeriod), model: model)
//        }
#else
        replySwitch.isHidden = true
        replyLabel.isHidden = true
#endif
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.messageDelegate = self
        
        // 更新数据
        updateData()
        updateSliderValue()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        MeshLibManager.manager.messageDelegate = self.lastMessageDelegate
        
        NotificationCenter.default.post(name: .init(deviceStateUpdateNotificationName), object: self.node)
    }
    
    /// 获取设备数据
    @objc private func getNodeState() {
        
        MeshAPI.getNodeState(address: node.primaryUnicastAddress)
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5, nodeScan: {[weak self] data in
            guard let self = self else { return }
            if data.node.primaryUnicastAddress == self.node.primaryUnicastAddress {
                self.node.rssi = data.rssi.intValue
                MeshLibManager.manager.stopRefreshNodesRSSI()
            }
        }, finished: nil)
    }
    
    /// 更新UI数据
    private func updateData() {
        
        self.replySwitch.isOn = node.features?.relay == .enabled
        
        if node.isKeybindComplete {
            
            view.hideEmptyDataView()
            
            guard node.state else { // 离线
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
                return
            }
            view.hideEmptyDataView()

            let lightness100 = node.isOn ? Node.getLightness100(lightness: node.lightness) : 0
            
            if node.isOn {
                lightImageBtn.isSelected = true
                onoffBtn.isSelected = true
                
                let progress = CGFloat(Float(lightness100) / 100.0) * 0.5
                var alpha = 0.5 + progress
                if self.node.temperatureModel != nil {
                    lightBgView.image = UIImage(named: "device_light_bg")?.withTintColor(Node.getCctMixColor(temperature100: self.node.temperature100))
                    
                    var garyBgAlpha: CGFloat = 0
                    if node.temperature100 >= 45 && node.temperature100 <= 55 {
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
            }
            
            brightnessLabel.text = "\(lightness100)%"
            cctLabel.text = "\(node.temperature)K"
            
            lightnessSlider.slider.limitRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
            
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
    
    private func updateSliderValue() {
        lightnessSlider.value = Node.getLightness100(lightness: node.lightness)
        cctSlider.value = Int(node.temperature)
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
           
        #if DEBUG
//        items.append(.init(icon: UIImage(named: "menu_edit"), title: "pwm_period".localizedString, hideAnimation: false, tapItemBack: {[weak self] _ in
//            self?.setPwmPeriod()
//        }))
//        #endif
        items.append(.init(icon: UIImage(named: "menu_edit"), title: "LED inverse", tapItemBack: {[weak self] _ in
            self?.test()
        }))
        #endif
//        if let group = self.node.group {
//            let profileType = group.info.profile.type
//            if profileType == .occupancy_daylight || profileType == .occupancy || profileType == .vacancy_daylight || profileType == .vacancy || profileType == .proximityLighting {
//                items.append(.init(icon: UIImage(named: "settings"), title: "settings".localizedString, tapItemBack: {[weak self] _ in
//                    
//                }))
//            }
//        }
        
        items.append(.init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] _ in
            self?.refresh()
        }))
        
        
//        isIphoneX ? 18 : 15
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
//        SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
        
//        MenuPopView.show(items: items, anchorPoint: CGPoint(x: view.width - SCRXFrom(17) - 15, y: y), menuWidth: MenuPopView.defalutMenuWidth + SCRXFrom(10))
    }
    
    private func test() {
        if let model = node.sunricherVendorModel {
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .ledInversion(inversion: !node.ledInversion)), model: model)
        }
    }
    
    /// 设置pwm频率
    private func setPwmFrequency() {
        let pwmPeriod = node.pwmFrequency
        SRAlertView(title: "set_pwm_period".localizedString, inputText: pwmPeriod != nil ? "\(pwmPeriod!)" : nil, inputFieldStyle: .init(placeholder: "0-65535", keyboardType: .numberPad), actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .default)], textValueChangedBack: nil) {[weak self] text in
            guard let self = self else { return }
            guard let value = UInt16(text) else {
                XWHUDManager.showTipHUD("invalid".localizedString + "!", isLineFeed: true)
                return
            }
            if let model = self.node.sunricherVendorModel {
                XWHUDManager.showCustomHUD(withMessage: nil, view: self.view)
                MeshAPI.sendMessage(message: SunricherVendorSet(function: .pwmFrequency(value)), model: model) {[weak self] response in
                    guard let self = self else { return }
                    XWHUDManager.hideInView(with: self.view)
                    guard let statusMessage = response as? SunricherVendorStatus, statusMessage.status.isSuccessful else {
                        XWHUDManager.showErrorTipHUD("failed!".localizedString)
                        return
                    }
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    self.updateData()
                }
            }
        }.show()
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
  
            MeshAPI.resetNode(address: self.node.primaryUnicastAddress) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                self?.space.luminairesCount = MeshNetworkManager.instance.lightNodes.count
                self?.space.save()
                self?.node.deleteExtension()
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
                    self.node.deleteExtension()
                    MeshNetworkManager.instance.meshNetwork?.remove(node: self.node)
//                    _ = self.space.meshManager?.save()
                    self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                    self.space.luminairesCount = MeshNetworkManager.instance.lightNodes.count
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
        navigationController?.pushViewController(DeviceInformationViewController(node: self.node), animated: true)
    }
    
    /// 设置
    private func settings() {
        
        
        
    }
    
    /// 刷新
    private func refresh() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 2)
        getNodeState()
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5) {[weak self] nodeDatas in
            guard let self = self else { return }
            if !nodeDatas.contains(where: { $0.node.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.node.rssi = nil
            }
        }
    }
    
    // MARK: - Action
    
    @objc private func onoffAction(sender: UIButton) {
        node.isOn = !node.isOn
        if node.isOn {
            node.lightness = node.trunOffLightness ?? node.lightnessRange.upperBound
        }else {
            node.trunOffLightness = node.lightness
            node.lightness = 0
        }
        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn)
        updateData()
        updateSliderValue()
    }
    
    private func bindSliderAction() {
        
        lightnessSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            
            let lightness = Node.getLightness(lightness100: value)
            
            if value == 0 {
                self.node.trunOffLightness = self.node.lightness
            }
            
            self.node.lightness = lightness
            self.node.isOn = lightness > 0
            self.updateData()
        }
        lightnessSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
            let lightness = Node.getLightness(lightness100: value, range: self.node.lightnessRange)
            MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: ended)
           
        }
        
        cctSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            self.node.temperature = UInt16(value)
            self.updateData()
        }
        cctSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: UInt16(value), ack: ended)
        }
    }
    
    @objc private func replySwitchValueChanged(sender: UISwitch) {
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
        
        if node.temperatureModel != nil {
            cctSlider.isHidden = false
            cctView.isHidden = false
        }else {
            cctSlider.isHidden = true
            cctView.isHidden = true
        }
        
        if node.lightnessModel != nil {
            lightnessSlider.isHidden = false
            brightnessView.isHidden = false
            if node.temperatureModel != nil {
                brightnessView.snp.remakeConstraints { make in
                    make.right.equalTo(view.snp.centerX).offset(SCRXFrom(-42))
                    make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(28))
                    make.height.equalTo(SCRYFrom(20))
                }
            }
        }else {
            lightnessSlider.isHidden = true
            brightnessView.isHidden = false
        }
        
    }
    
    private func setupUI() {
        
        lightGrayBgView = UIImageView(image: UIImage(named: "device_light_gray_bg"))
        lightGrayBgView.alpha = 0
        view.addSubview(lightGrayBgView)
        lightGrayBgView.snp.makeConstraints { make in
            
            make.centerX.equalToSuperview()
//            make.width.equalTo(lightBgView.snp.height)
            if isIPad {
                make.top.equalTo(SCRYFit(198))
                make.width.height.equalTo(SCRYFit(238))
            }else {
                make.top.equalTo(SCRYFit(108))
                make.width.height.equalTo(SCRYFit(200))
            }
            
        }
        
        lightBgView = UIImageView(image: UIImage(named: "device_light_bg"))
        view.addSubview(lightBgView)
        lightBgView.snp.makeConstraints { make in
//            make.top.equalTo(SCRYFit(108))
            make.centerX.equalToSuperview()
            make.top.width.height.equalTo(lightGrayBgView)
//            make.width.equalTo(lightBgView.snp.height)
//            make.width.height.equalTo(SCRYFit(200))
        }
        
        lightImageBtn = UIButton(normalImageName: "device_light_control_off", selectedImageName: "device_light_control_on", target: self, action: #selector(onoffAction))
        view.addSubview(lightImageBtn)
        lightImageBtn.snp.makeConstraints { make in
            make.center.equalTo(lightBgView)
            if isIPad {
                make.width.height.equalTo(67)
            }
        }
        
        brightnessView = UIView()
        view.addSubview(brightnessView)
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
        view.addSubview(cctView)
        cctView.snp.makeConstraints { make in
            make.left.equalTo(view.snp.centerX).offset(SCRXFrom(22))
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
        cctLabel = UILabel(text: "4500K", textColor: TextBlack_Color, fontSize: 14)
        cctView.addSubview(cctLabel)
        cctLabel.sizeToFit()
        cctLabel.snp.makeConstraints { make in
            make.left.equalTo(cctLineView.snp.right).offset(SCRXFrom(6))
            make.centerY.right.equalToSuperview()
            make.width.greaterThanOrEqualTo(cctLabel.width)
        }
        
        let cctRange = self.node.lightCTLTemperatureRange ?? self.node.defalutLightCTLTemperatureRange
        cctSlider = BuoySliderView(frame: .zero, functionType: .cct(min: Int(cctRange.lowerBound), max: Int(cctRange.upperBound)))
        cctSlider.slider.interval = 0.3
        cctSlider.slider.step = 10
//        Node.getTemperature100(temperature: UInt16(group.cct))
//        cctSlider.isHidden = !group.supportCct
        cctSlider.isHidden = true
        view.addSubview(cctSlider)
        cctSlider.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
                make.bottom.equalTo(SCRYFit(-102) - kSafeAreaBottomHeight)
            }else {
                make.left.equalTo(SCRXFrom(30))
                make.right.equalTo(SCRXFrom(-29))
                make.bottom.equalTo(SCRYFit(-52) - kSafeAreaBottomHeight)
            }
            make.height.equalTo(76)
        }
        
        lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
        lightnessSlider.slider.interval = 0.3
//        lightnessSlider.isHidden = !group.supportLightness
        view.addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(cctSlider)
            make.bottom.equalTo(cctSlider.snp.top).offset(SCRYFit(2))
        }
        
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
        view.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if isIPad {
                make.width.height.equalTo(56)
                make.bottom.equalTo(lightnessSlider.snp.top).offset(SCRYFit(-28))
            }else {
                make.bottom.equalTo(lightnessSlider.snp.top).offset(SCRYFit(-8))
            }
        }
        
        replySwitch = UISwitch()
        replySwitch.onTintColor = Bar_Color
        replySwitch.tintColor = RGB(207, 207, 207)
        replySwitch.addTarget(self, action: #selector(replySwitchValueChanged), for: .valueChanged)
        view.addSubview(replySwitch)
        replySwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(lightBgView.snp.top)
        }
        
        replyLabel = UILabel(text: "Reply", textColor: TextBlack_Color, fontSize: 13)
        replyLabel.isHidden = true
        view.addSubview(replyLabel)
        replyLabel.snp.makeConstraints { make in
            make.centerY.equalTo(replySwitch)
            make.right.equalTo(replySwitch.snp.left).offset(SCRXFrom(-6))
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
            updateSliderValue()
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
                updateSliderValue()
            }
        }
    }
    
}
