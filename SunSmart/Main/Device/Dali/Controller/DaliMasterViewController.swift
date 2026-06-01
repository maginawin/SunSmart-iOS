//
//  DaliMasterViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/17.
//

import UIKit
import NordicSigMeshSDK

class DaliMasterViewController: DeviceBaseViewController {

    /// 单设备view
    private var singleControlView: DaliMasterSingleControlView!
    /// 多设备view
    private var multipleControlsView: DaliMasterMultipleControlsView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
    }
    
    override func moreClick() {
        
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
        
        items.append(.init(icon: UIImage(named: "menu_dali_setting"), title: "dali_setting".localizedString, tapItemBack: {[weak self] _ in
            self?.daliSettings()
        }))
        
        
        //        isIphoneX ? 18 : 15
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        //        SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
        
    }

    
    
    private func setupUI() {
        
        var lightType: DaliMasterSingleControlView.LightType!
        if node.singleDeviceDisplaySupportCct {
            lightType = .cct(range: node.effectiveCctRange)
        }else if node.lightnessModel != nil {
            lightType = .lightness
        }else {
            lightType = .onOff
        }
        
        singleControlView = DaliMasterSingleControlView(frame: .zero, lightType: lightType)
        singleControlView.delegate = self
        view.addSubview(singleControlView)
        singleControlView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        multipleControlsView = DaliMasterMultipleControlsView()
        multipleControlsView.isHidden = true
        multipleControlsView.delegate = self
        view.addSubview(multipleControlsView)
        multipleControlsView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
    }
    
    
    /// 更新UI数据
    override func updateData() {
        super.updateData()
//        self.replySwitch.isOn = node.replyEnabled
        
        if node.isKeybindComplete {

            let lightness100 = node.isOn ? Node.getLightness100(lightness: node.lightness) : 0
            
            if node.isOn {
                singleControlView.isHidden = true
                multipleControlsView.isHidden = false
                singleControlView.lightImageBtn.isSelected = true
                singleControlView.onoffBtn.isSelected = true
                
                let progress = CGFloat(Float(lightness100) / 100.0) * 0.5
                var alpha = 0.5 + progress
                if self.node.singleDeviceDisplaySupportCct {
                    let temperature100 = self.node.getEffectiveTemperature100(temperature: self.node.temperature)
                    singleControlView.lightBgView.image = UIImage(named: "device_light_bg")?.withTintColor(Node.getCctMixColor(temperature100: temperature100))
                    
                    var garyBgAlpha: CGFloat = 0
                    if temperature100 >= 45 && temperature100 <= 55 {
                        garyBgAlpha = 0.5
                        alpha = 1
                    }
                    if garyBgAlpha != singleControlView.lightGrayBgView.alpha {
                        UIView.animate(withDuration: 0.25) {
                            self.singleControlView.lightGrayBgView.alpha = garyBgAlpha
                        }
                    }
                    
                }else {
                    singleControlView.lightBgView.image = UIImage(named: "device_light_bg")
                }
                singleControlView.lightBgView.alpha = alpha
                
            }else {
                singleControlView.lightImageBtn.isSelected = false
                singleControlView.onoffBtn.isSelected = false
                singleControlView.lightBgView.image = UIImage(named: "device_light_off_bg")
                singleControlView.lightBgView.alpha = 1
            }
            
            singleControlView.brightnessView.itemValueLabel.text = "\(lightness100)%"
            singleControlView.cctView.itemValueLabel.text = "\(node.temperature)K"
            
            singleControlView.lightnessSlider.slider.limitRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
            
            singleControlView.lightnessSlider.value = Node.getLightness100(lightness: node.lightness)
            singleControlView.cctSlider.value = Int(node.temperature)
            
        }
    }
    
    private func daliSettings() {
        let vc = DaliSettingViewController(node: node)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 设备开关控制
    private func meshOnoff(isOn: Bool) {
        
        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: isOn)
    }
    
    /// 设备亮度控制
    private func meshLightnessSet(lightness: UInt16, ack: Bool = false) {
        MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: ack)
    }

    /// 设备亮度控制
    private func meshCctSet(cct: UInt16, ack: Bool = false) {
        MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: node.clampEffectiveCct(cct), ack: ack)
    }
    
}

extension DaliMasterViewController: DaliMasterSingleControlViewDelegate {
    
    /// 开关事件
    func view(_ view: DaliMasterSingleControlView, onoffAction isOn: Bool) {
        node.isOn = isOn
        if node.isOn {
            node.lightness = node.trunOffLightness ?? node.lightnessRange.upperBound
        }else {
            node.trunOffLightness = node.lightness
            node.lightness = 0
        }
        updateData()
        meshOnoff(isOn: isOn)
    }
    
    /// 亮度修改事件 value: 亮度百分比 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterSingleControlView, lightnessValueChanged value: Int, throttle: Bool, ended: Bool) {
        
        let lightness = Node.getLightness(lightness100: value)
        if value == 0 {
            self.node.trunOffLightness = self.node.lightness
        }
        
        self.node.lightness = lightness
        self.node.isOn = lightness > 0
        self.updateData()
        
        if throttle {
            meshLightnessSet(lightness: lightness, ack: ended)
        }
    }
    
    /// 色温修改事件 cct: 色温 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterSingleControlView, cctValueChanged cct: Int, throttle: Bool, ended: Bool) {
        
        self.node.temperature = UInt16(cct)
        self.updateData()
        if throttle {
            meshCctSet(cct: UInt16(cct), ack: ended)
        }
        
    }
    
}


extension DaliMasterViewController: DaliMasterMultipleControlsViewDelegate {
    
    //************ Dali主机 *************/
    /// dali主机onoff事件 isOn: 开/关
    func view(_ view: DaliMasterMultipleControlsView, masterOnOffAction isOn: Bool) {
        
    }
    
    /// dali主机亮度修改事件 value: 亮度百分比 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterMultipleControlsView, masterLightnessValueChanged value: Int, throttle: Bool, ended: Bool) {
        
    }
    
    /// dali主机色温修改事件 cct: 色温 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterMultipleControlsView, masterCctValueChanged cct: Int, throttle: Bool, ended: Bool) {
        
    }
    
    /// dali主机扫描dali设备
    func daliMasterDidScanDevices(view: DaliMasterMultipleControlsView) {
        
    }
    
    //************ Dali设备 *************/
    /// dali设备开关事件 isOn: 开/关
    func view(_ view: DaliMasterMultipleControlsView, daliOnOffAction isOn: Bool) {
        
    }
    
    /// dali设备详情
    func view(_ view: DaliMasterMultipleControlsView, daliDeviceDetails device: Node) {
        
    }
    
}
