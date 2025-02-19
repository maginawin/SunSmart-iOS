//
//  DaliMasterViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/17.
//

import UIKit
import NordicSigMeshSDK

class DaliMasterViewController: DeviceBaseViewController {

    private var singleControlView: DaliMasterSingleControlView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
    }
    
    private func setupUI() {
        
        var lightType: DaliMasterSingleControlView.LightType!
        if node.temperatureModel != nil {
            lightType = .cct(range: node.lightCTLTemperatureRange ?? node.defalutLightCTLTemperatureRange)
        }else if node.lightnessModel != nil {
            lightType = .lightness
        }else {
            lightType = .onOff
        }
        
        singleControlView = DaliMasterSingleControlView(frame: .zero, lightType: lightType)
        singleControlView.delegate = self
        view.addSubview(singleControlView)
        singleControlView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
    }
    
    
    /// 更新UI数据
    override func updateData() {
        super.updateData()
//        self.replySwitch.isOn = node.replyEnabled
        
        if node.isKeybindComplete {

            let lightness100 = node.isOn ? Node.getLightness100(lightness: node.lightness) : 0
            
            if node.isOn {
                singleControlView.lightImageBtn.isSelected = true
                singleControlView.onoffBtn.isSelected = true
                
                let progress = CGFloat(Float(lightness100) / 100.0) * 0.5
                var alpha = 0.5 + progress
                if self.node.temperatureModel != nil {
                    singleControlView.lightBgView.image = UIImage(named: "device_light_bg")?.withTintColor(Node.getCctMixColor(temperature100: self.node.temperature100))
                    
                    var garyBgAlpha: CGFloat = 0
                    if node.temperature100 >= 45 && node.temperature100 <= 55 {
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
            
            singleControlView.brightnessLabel.text = "\(lightness100)%"
            singleControlView.cctLabel.text = "\(node.temperature)K"
            
            singleControlView.lightnessSlider.slider.limitRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
            
            singleControlView.lightnessSlider.value = Node.getLightness100(lightness: node.lightness)
            singleControlView.cctSlider.value = Int(node.temperature)
            
        }
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
        MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: cct, ack: ack)
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

