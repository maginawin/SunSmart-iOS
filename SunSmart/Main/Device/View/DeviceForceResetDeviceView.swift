//
//  DeviceForceResetDeviceView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/15.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceForceResetDeviceViewDelegate: AnyObject {
    
    /// 点击identity事件
    func deviceViewDidIdentifyActioin(view: DeviceForceResetDeviceView)
    
    /// 点击reset事件
    func deviceViewDidResetActioin(view: DeviceForceResetDeviceView)
    
}

class DeviceForceResetDeviceView: UIView {

    var deviceImageView: UIImageView!
    var nameLabel: UILabel!
    var macAddressLabel: UILabel!
    var identifyBtn: UIButton!
    var resetBtn: UIButton!
    var signalStrengthView: DeviceSignalStrengthView!
    var signalLabel: UILabel!
    
    weak var delegate: DeviceForceResetDeviceViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(device: ProvisioningDevice, state: DeviceForceResetDeviceController.DeviceState) {
        
        deviceImageView.image = UIImage(named: device.icon ?? "")
        
        nameLabel.text = device.deviceName ?? "device".localizedString
        
        if let macAddress = device.macAddress, !macAddress.isEmpty {
            macAddressLabel.text = macAddress.getMacAddressSegmentString()
        }else {
            macAddressLabel.text = device.peripheral.identifier.uuidString
        }
        
        signalStrengthView.setSignalStrength(rssi: device.rssi.intValue)
        signalLabel.text = "\(device.rssi.intValue)dB"
        
        identifyBtn.imageView?.layer.removeAnimation(forKey: "loading")
        resetBtn.imageView?.layer.removeAnimation(forKey: "loading")
        
        switch state {
        case .none:
            identifyBtn.isEnabled = true
            identifyBtn.setTitle("identify".localizedString, for: .normal)
            identifyBtn.setImage(nil, for: .normal)
            resetBtn.isHidden = true
            resetBtn.setImage(nil, for: .normal)
        case .identifying:
            identifyBtn.setTitle(nil, for: .normal)
            identifyBtn.setImage(UIImage(named: "device_reset_loading"), for: .normal)
            identifyBtn.imageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
            identifyBtn.isEnabled = false
            resetBtn.isHidden = false
            resetBtn.isEnabled = false
            resetBtn.setImage(nil, for: .normal)
        case .idenfityFinish:
            identifyBtn.isEnabled = true
            identifyBtn.setTitle("identify".localizedString, for: .normal)
            identifyBtn.setImage(nil, for: .normal)
            resetBtn.isHidden = false
            resetBtn.isEnabled = true
            resetBtn.setImage(nil, for: .normal)
            resetBtn.setTitle("reset".localizedString, for: .normal)
        case .reseting:
            identifyBtn.isEnabled = false
            resetBtn.isHidden = false
            resetBtn.isEnabled = false
            resetBtn.setTitle(nil, for: .normal)
            resetBtn.setImage(UIImage(named: "device_reset_loading"), for: .normal)
            resetBtn.imageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
        }

        identifyBtn.layer.borderColor = identifyBtn.isEnabled ? Bar_Color.cgColor : Bar_Color.withAlphaComponent(0.5).cgColor
        
        resetBtn.layer.borderColor = resetBtn.isEnabled ? Red_Color.cgColor : Bar_Color.withAlphaComponent(0.5).cgColor
        
    }
    
    /// 识别
    @objc private func identifyBtnClick() {
        delegate?.deviceViewDidIdentifyActioin(view: self)
    }
    
    /// 重置
    @objc private func resetBtnClick() {
        delegate?.deviceViewDidResetActioin(view: self)
    }
    
    
    private func setupUI() {
        
        deviceImageView = UIImageView()
        addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        nameLabel = UILabel(text: "Device", textColor: RGB(13, 14, 28), fontSize: 15, fontWeight: .light, fit: false)
        addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.width.lessThanOrEqualTo(SCRXFrom(isIPad ? 200 : 119))
        }
        
        macAddressLabel = UILabel(text: "", textColor: RGB(142, 142, 147), fontSize: 12, fontWeight: .light, fit: false)
        addSubview(macAddressLabel)
        macAddressLabel.snp.makeConstraints { make in
            make.left.right.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(3))
        }
        
        resetBtn = UIButton(title: "reset".localizedString, titleSize: 14 , titleWeight: .light, titleColor: Red_Color, target: self, action: #selector(resetBtnClick))
        resetBtn.setTitleColor(Red_Color.withAlphaComponent(0.5), for: .disabled)
        resetBtn.layer.cornerRadius = SCRYFrom(15)
        resetBtn.layer.borderWidth = 0.6
        resetBtn.layer.borderColor = Red_Color.cgColor
        resetBtn.isHidden = true
        addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(64))
            make.height.equalTo(SCRYFrom(30))
//            make.width.height.equalTo(SCRYFrom(30))
        }
        
        identifyBtn = UIButton(title: "identify".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(identifyBtnClick))
        identifyBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        identifyBtn.layer.cornerRadius = SCRYFrom(15)
        identifyBtn.layer.borderColor = Bar_Color.cgColor
        identifyBtn.layer.borderWidth = 0.6
        addSubview(identifyBtn)
        identifyBtn.snp.makeConstraints { make in
            make.right.equalTo(resetBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(resetBtn)
            make.width.height.equalTo(resetBtn)
        }
        
//        identifyLoadingView = UIImageView(image: UIImage(named: "loading"))
//        identifyLoadingView.isHidden = true
//        contentView.addSubview(identifyLoadingView)
//        identifyLoadingView.snp.makeConstraints { make in
//            make.center.equalTo(identifyBtn)
//            make.width.height.equalTo(SCRYFrom(40))
//        }
        
        signalStrengthView = DeviceSignalStrengthView()
        addSubview(signalStrengthView)
        signalStrengthView.snp.makeConstraints { make in
            make.left.equalTo(macAddressLabel)
            make.top.equalTo(macAddressLabel.snp.bottom).offset(SCRYFrom(8))
            make.width.equalTo(SCRXFrom(56))
            make.height.equalTo(2)
        }
        
        signalLabel = UILabel(text: "", textColor: AssistText_Color, fontSize: 12, fontWeight: .light, fit: false)
        addSubview(signalLabel)
        signalLabel.snp.makeConstraints { make in
            make.left.equalTo(signalStrengthView.snp.right).offset(SCRXFrom(9))
            make.centerY.equalTo(signalStrengthView)
        }
        
    }
    
}
