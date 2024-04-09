//
//  DeviceLightHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/17.
//

import UIKit
import NordicSigMeshSDK

class DeviceLightHeaderView: UIView {

    var lightGrayBgView: UIImageView!
    var lightBgView: UIImageView!
    var lightImageView: UIImageView!
    var rssiBtn: UIButton!
    var brightnessBtn: UIButton!
    var cctBtn: UIButton!
    var controlBtn: UIButton!
    /// 开关控制回调
    var onoffControlCallback: ((Bool)->Void)?
    
    var node: Node! {
        didSet {
            
            var garyBgAlpha: CGFloat = 0
            
//            lightGrayBgView.isHidden = true
            controlBtn.isSelected = node.isOn
            var bgImage = UIImage(named: "device_light_bg")
            
            var lightness100 = node.lightness100
            if node.isOn, node.lightness == 0, let trunOffLightness = node.trunOffLightness { // 开灯并且亮度0，设备亮度未上报；先显示设备关灯前的亮度值
                lightness100 = Node.getLightness100(lightness: trunOffLightness, range: node.lightnessRange)
            }
            
            if node.isOn {
                let alpha = CGFloat(lightness100) / 100.0
                lightBgView.alpha = max(alpha, 0.1)
                brightnessBtn.setTitle("| \(lightness100)%", for: .normal)
                if node.temperatureModel != nil {
                    bgImage = bgImage?.withTintColor(Node.getCctMixColor(temperature100: node.temperature100))
                    if node.temperature100 >= 45 && node.temperature100 <= 58 {
                        garyBgAlpha = 1
                    }
                }
            }else {
                bgImage = bgImage?.withTintColor(RGB(216, 216, 216))
                lightBgView.alpha = 1
                brightnessBtn.setTitle("| \("off_state".localizedString)", for: .normal)
            }
            
            lightBgView.image = bgImage
            rssiBtn.setTitle(node.rssi != nil ? "| \(node.rssi!)dB" : "--", for: .normal)
            if node.temperatureModel != nil {
                cctBtn.isHidden = false
                cctBtn.setTitle("| \(node.temperature100)%", for: .normal)
            }else {
                cctBtn.isHidden = true
            }
            
            if garyBgAlpha != lightGrayBgView.alpha {
                UIView.animate(withDuration: 0.25) {
                    self.lightGrayBgView.alpha = garyBgAlpha
                }
            }
            
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RGB(246, 246, 246)
        self.clipsToBounds = true
        setupUI()
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: - Action
    
    @objc private func controlBtnClick(sender: UIButton) {
//        sender.isSelected = !sender.isSelected
        
//        if sender.isSelected {
//            lightBgView.image = UIImage(named: "device_light_bg")
//        }else {
//            lightBgView.image = UIImage(named: "device_light_bg")?.withTintColor(RGB(216, 216, 216))
//        }
//        lightBgView.alpha = 0.3
        onoffControlCallback?(!sender.isSelected)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        lightGrayBgView = UIImageView(image: UIImage(named: "device_light_gray_bg"))
        lightGrayBgView.alpha = 0
        addSubview(lightGrayBgView)
        lightGrayBgView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.width.equalTo(lightGrayBgView.snp.height).multipliedBy(750 / 244.0)
        }
        
        lightBgView = UIImageView(image: UIImage(named: "device_light_bg"))
        addSubview(lightBgView)
        lightBgView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(-22))
//            make.width.equalTo(lightBgView.snp.height)
            make.width.height.equalTo(SCRYFrom(200))
        }
        
        lightImageView = UIImageView(image: UIImage(named: "device_light_big"))
        addSubview(lightImageView)
        lightImageView.snp.makeConstraints { make in
            make.center.equalTo(lightBgView)
        }
        
        rssiBtn = UIButton(title: "| -70dB", titleSize: 14, titleColor: TextBlack_Color, normalImageName: "device_rssi")
        rssiBtn.isUserInteractionEnabled = false
        rssiBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(rssiBtn)
        rssiBtn.snp.makeConstraints { make in
            make.left.equalTo(lightBgView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(8))
        }
        
        brightnessBtn = UIButton(title: "| 37%", titleSize: 14, titleColor: TextBlack_Color, normalImageName: "device_brightness")
        brightnessBtn.isUserInteractionEnabled = false
        brightnessBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(brightnessBtn)
        brightnessBtn.snp.makeConstraints { make in
            make.left.equalTo(rssiBtn)
            make.centerY.equalToSuperview()
        }
        
        cctBtn = UIButton(title: "| 85%", titleSize: 14, titleColor: TextBlack_Color, normalImageName: "device_cct")
        cctBtn.isUserInteractionEnabled = false
        cctBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(cctBtn)
        cctBtn.snp.makeConstraints { make in
            make.left.equalTo(rssiBtn)
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        controlBtn = UIButton(normalImageName: "device_control_off", selectedImageName: "device_control_on", target: self, action: #selector(controlBtnClick))
        addSubview(controlBtn)
        controlBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-29))
        }
    }
    
}
