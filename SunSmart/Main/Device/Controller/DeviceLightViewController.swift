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

        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
            
            navigationController?.setNavigationBarBackgroundColor(color: .clear)
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        }
//        menuView?.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        
        node.lightCTLTemperatureRange = 2700...6500
        
        // 初始化UI
        setupUI()
        // 根据设备类型显示UI
        updateUI()
        // 绑定事件
        bindSliderAction()
        // 获取设备数据
        getNodeState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.register(self)
        
        // 更新数据
        updateData()
        updateSliderValue()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        NotificationCenter.default.post(name: .init(deviceStateUpdateNotificationName), object: self.node)
    }
    
    /// 获取设备数据
    @objc private func getNodeState() {
        
        MeshAPI.getNodeState(address: node.primaryUnicastAddress)
    
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 2) {[weak self] nodes in
            guard let self = self else { return }
            if !nodes.contains(where: { $0.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.node.rssi = nil
            }
        }
        
    }
    
    /// 更新UI数据
    private func updateData() {
        
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
                if self.node.ctlModel != nil {
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
            
        }else {
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                    // 修复
                    self?.repairBtnClick()
                }
                if let emptyView = view.emptyView {
                    emptyView.button.snp.updateConstraints { make in
                        make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
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
        
        var y = kNavigationHeight
        if self.presentingViewController != nil {
            y = StatusBarManager.statusBarFrame.height + (navigationController?.navigationBar.height ?? kNavigationHeight)
        }
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "edit"), title: "edit".localizedString, tapItemBack: {[weak self] _ in
                self?.editNode()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] _ in
                self?.deleteNode()
            }),
            .init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: {[weak self] _ in
                self?.information()
            }),
            .init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: {[weak self] _ in
                self?.refresh()
            })
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(17) - 15, y: y), menuWidth: MenuPopView.defalutMenuWidth + SCRXFrom(10))
    }
    
    /// 编辑设备
    private func editNode() {
        
        SRAlertView(title: "edit_name".localizedString, inputText: node.name, placeholder: "", actions: [.cancelAction, .init(title: "done".localizedString, style: .default)]) {[weak self] text, validRange in
//            guard let self = self else { return }
             if !validRange && !text.isEmpty { // 长度超限
                 return "text_length_exceeded".localizedString
             }else if (self?.space.isNodeTautonym(nodeName: text) ?? false) && text != self?.node.name { // 重名
                 return "name_already_exists".localizedString
             }
             return nil
         } inputDoneBack: {[weak self] text in
             guard let self = self else { return }
             self.title = text
             self.node.name = text
             _ = self.space.meshManager?.save()
             self.space.save()
//             self.lightBasicVc?.reloadNodeName(text)
//             reloadNodeName
             
         }.show()
    }
    
    /// 删除设备
    private func deleteNode() {
        
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
  
            MeshAPI.resetNode(address: self.node.primaryUnicastAddress) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.space.save()
                self?.node.delete()
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                    self?.backAction()
                }
            } resetFail: { _, error in
                XWHUDManager.hide()
                
                let alertView = SRAlertView(title: "notification".localizedString, actions: [.cancelAction, SRAlertAction(title: "force_delete".localizedString, actionHandler: {[weak self] _ in
                    guard let self = self else { return }
                    self.node.delete()
                    self.space.meshManager?.meshNetwork?.remove(node: self.node)
                    _ = self.space.meshManager?.save()
                    self.space.save()
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
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
            
        } keyBindFail: {[weak self] _ in
            XWHUDManager.hide()
            self?.repairFailed()
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
    
    /// 刷新
    private func refresh() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 3)
        getNodeState()
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
    
    private func updateUI() {
        
        if node.ctlModel != nil {
            cctSlider.isHidden = false
            cctView.isHidden = false
        }else {
            cctSlider.isHidden = true
            cctView.isHidden = true
        }
        
        if node.lightnessModel != nil {
            lightnessSlider.isHidden = false
            brightnessView.isHidden = false
            if node.ctlModel != nil {
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
            make.top.equalTo(SCRYFit(108))
            make.centerX.equalToSuperview()
//            make.width.equalTo(lightBgView.snp.height)
            make.width.height.equalTo(SCRYFit(200))
        }
        
        lightBgView = UIImageView(image: UIImage(named: "device_light_bg"))
        view.addSubview(lightBgView)
        lightBgView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFit(108))
            make.centerX.equalToSuperview()
//            make.width.equalTo(lightBgView.snp.height)
            make.width.height.equalTo(SCRYFit(200))
        }
        
        lightImageBtn = UIButton(normalImageName: "device_light_control_off", selectedImageName: "device_light_control_on", target: self, action: #selector(onoffAction))
        view.addSubview(lightImageBtn)
        lightImageBtn.snp.makeConstraints { make in
            make.center.equalTo(lightBgView)
        }
        
        brightnessView = UIView()
        view.addSubview(brightnessView)
        brightnessView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(28))
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
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            make.bottom.equalTo(SCRYFit(-52) - kSafeAreaBottomHeight)
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
        
        onoffBtn = UIButton(normalImageName: "device_control_off", selectedImageName: "device_control_on", target: self, action: #selector(onoffAction))
        onoffBtn.setImage(UIImage(named: "group_control_disable"), for: .disabled)
        view.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.bottom.equalTo(lightnessSlider.snp.top).offset(SCRYFit(-8))
            make.centerX.equalToSuperview()
        }
        
    }

}

extension DeviceLightViewController: MeshLibManagerDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
            updateData()
            updateSliderValue()
        }
    }
    
}
