//
//  DeviceForceResetViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/15.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceForceResetViewCellDelegate: AnyObject {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceForceResetViewCell, identify device: ProvisioningDevice)
    
    /// 设备添加重置事件回调
    func cell(_ cell: DeviceForceResetViewCell, deviceReset device: ProvisioningDevice)
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceForceResetViewCell, deviceStateImageClick device: ProvisioningDevice)

}

class DeviceForceResetViewCell: UITableViewCell {

    var selectImageView: UIImageView!
    var deviceImageView: UIImageView!
    var identifyAnimationView: UIImageView!
    var nameLabel: UILabel!
    var macAddressLabel: UILabel!
//    var versionLabel: UILabel!
    var identifyBtn: UIButton!
    var resetBtn: UIButton!
    var stateImageView: UIImageView!
    var stateLabel: UILabel!
    var identifyLoadingView: UIImageView!
    var identifyStateLabel: UILabel!
    var signalStrengthView: DeviceSignalStrengthView!
    var signalLabel: UILabel!
    var lineView: UIView!
    
    weak var delegate: DeviceForceResetViewCellDelegate?
    
    var device: ProvisioningDevice! {
        didSet {
            
            deviceImageView.image = UIImage(named: device.icon ?? "")
            identifyAnimationView.isHidden = true
            identifyBtn.isHidden = true
            resetBtn.isHidden = true
            stateImageView.isHidden = true
            stateLabel.isHidden = true
            stateImageView.snp.updateConstraints { make in
                make.width.height.equalTo(30)
            }
            identifyLoadingView.isHidden = true
            identifyStateLabel.isHidden = true
            
            if !(device.resetState == .identifying || device.resetState == .identifyWait) {
                identifyLoadingView.layer.removeAnimation(forKey: "loading")
            }
            if device.resetState != .identifying {
                deviceImageView.layer.removeAnimation(forKey: "identify")
            }
            if device.resetState != .reseting {
                stateImageView.layer.removeAnimation(forKey: "loading")
            }
            
            switch device.selectedState {
            case .unselected:
                selectImageView.image = UIImage(named: "device_select_un")
            case .selected:
                selectImageView.image = UIImage(named: "device_select")
            case .disabled:
                selectImageView.image = UIImage(named: "device_select_disable")
            }
            
         
            switch device.resetState {
            case .none, .scanning, .disable:
                identifyBtn.isHidden = false
                resetBtn.isHidden = false
                if device.resetState == .scanning || device.resetState == .disable {
                    identifyBtn.isEnabled = false
                    resetBtn.isEnabled = false
                    identifyBtn.layer.borderColor = RGB(156, 163, 175, 0.5).cgColor
                }else {
                    identifyBtn.isEnabled = true
                    resetBtn.isEnabled = device.deviceType != .unknown
                    identifyBtn.layer.borderColor = Bar_Color.cgColor
                }
                
            case .identifyWait, .identifying, .identifyFail:
                resetBtn.isHidden = false
                identifyLoadingView.isHidden = false
                identifyStateLabel.isHidden = false
                identifyStateLabel.textColor = TextBlack_Color
                if device.resetState == .identifyWait {
                    identifyStateLabel.text = "device_add_waiting".localizedString
                }else if device.resetState == .identifying {
                    identifyStateLabel.text = "identifying".localizedString
                    identifyAnimationView.isHidden = false
//                    deviceImageView.layer.addOpacityAnimation(fromOpacity: 1, toOpacity: 0, duration: 0.5, repeatCount: 10, animationKey: "identify")
                    if identifyAnimationView.layer.animation(forKey: "identify") == nil {
                        identifyAnimationView.layer.addScaleAnimation(fromScale: 0, toScale: 1, duration: 1, repeatCount: .max, timingName: .easeInEaseOut, animationKey: "identify")
                    }
                }else if device.resetState == .identifyFail {
                    identifyStateLabel.text = "device_identify_failed".localizedString
                    identifyStateLabel.textColor = Red_Color
                }
                let textSize = identifyStateLabel.sizeThatFits(CGSize(width: 120, height: 30))
                identifyStateLabel.snp.updateConstraints { make in
                    make.width.equalTo(textSize.width + SCRXFrom(12))
                }
                if identifyLoadingView.layer.animation(forKey: "loading") == nil {
                    identifyLoadingView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
                }
            case .wait:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_waiting")
            case .reseting:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "loading")
                if stateImageView.layer.animation(forKey: "loading") == nil {
                    stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
                }
            case .success:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_success")
            case .failed:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_fault")
                identifyBtn.isHidden = false
                stateLabel.text = "retry".localizedString
                stateLabel.isHidden = false
            }
        
            nameLabel.text = device.deviceName ?? "device".localizedString
            
            if let macAddress = device.macAddress, !macAddress.isEmpty {
                macAddressLabel.text = macAddress.getMacAddressSegmentString()
            }else {
                macAddressLabel.text = device.peripheral.identifier.uuidString
            }

            if device.icon?.contains("Lighting") ?? true {
                identifyAnimationView.snp.updateConstraints { make in
                    make.centerX.equalToSuperview()
                    make.centerY.equalToSuperview().offset(SCRYFrom(-4))
                }
            }else {
                
                identifyAnimationView.snp.updateConstraints { make in
                    make.centerX.centerY.equalToSuperview()
                }
            }
            
            signalStrengthView.setSignalStrength(rssi: device.rssi.intValue)
            signalLabel.text = "\(device.rssi.intValue)dB"
//            versionLabel.text = device.version
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func identifyBtnClick() {
        delegate?.cell(self, identify: device)
    }
    
    @objc private func resetBtnClick() {
        delegate?.cell(self, deviceReset: device)
    }
    
    @objc private func stateImageViewClick() {
        delegate?.cell(self, deviceStateImageClick: device)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        selectImageView = UIImageView()
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }
        
        deviceImageView = UIImageView()
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(40))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        identifyAnimationView = UIImageView(image: UIImage(named: "device_light_identify"))
        deviceImageView.addSubview(identifyAnimationView)
        identifyAnimationView.snp.makeConstraints { make in
            make.centerX.centerY.equalToSuperview()
//            make.top.equalTo(SCRYFrom(3))
            make.width.height.equalTo(SCRYFrom(10))
        }
        
        nameLabel = UILabel(text: "Device", textColor: RGB(13, 14, 28), fontSize: 15, fontWeight: .light, fit: false)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-135))
        }
        
        macAddressLabel = UILabel(text: "DF:EF:32:DG:HJ:67", textColor: RGB(142, 142, 147), fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(macAddressLabel)
        macAddressLabel.snp.makeConstraints { make in
            make.left.right.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(3))
        }
        
        resetBtn = UIButton(normalImageName: nil, target: self, action: #selector(resetBtnClick))
        resetBtn.setImage(UIImage(named: "reset"), for: .normal)
        resetBtn.setImage(UIImage(named: "reset_disable"), for: .disabled)
        contentView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
//            make.width.height.equalTo(SCRYFrom(30))
        }
        
        identifyBtn = UIButton(title: "identify".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(identifyBtnClick))
        identifyBtn.setTitleColor(RGB(39, 37, 54, 0.5), for: .disabled)
        identifyBtn.layer.cornerRadius = 15
        identifyBtn.layer.borderColor = Bar_Color.cgColor
        identifyBtn.layer.borderWidth = 0.6
        identifyBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(14), bottom: 0, right: SCRXFrom(14))
        contentView.addSubview(identifyBtn)
        identifyBtn.snp.makeConstraints { make in
            make.right.equalTo(resetBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(resetBtn)
            make.height.equalTo(resetBtn)
        }
        
        identifyLoadingView = UIImageView(image: UIImage(named: "loading"))
        identifyLoadingView.isHidden = true
        contentView.addSubview(identifyLoadingView)
        identifyLoadingView.snp.makeConstraints { make in
            make.center.equalTo(identifyBtn)
            make.width.height.equalTo(SCRYFrom(40))
        }
        
        identifyStateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        identifyStateLabel.layer.cornerRadius = 3
        identifyStateLabel.layer.borderWidth = 0.6
        identifyStateLabel.layer.borderColor = Message_Color.cgColor
        identifyStateLabel.textAlignment = .center
        identifyStateLabel.backgroundColor = .white
        identifyStateLabel.isHidden = true
        contentView.addSubview(identifyStateLabel)
        identifyStateLabel.snp.makeConstraints { make in
            make.center.equalTo(identifyLoadingView)
            make.height.equalTo(16)
            make.width.equalTo(50)
        }
        
        stateImageView = UIImageView()
        stateImageView.isUserInteractionEnabled = true
        stateImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stateImageViewClick)))
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(30)
        }
        
        stateLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        stateLabel.isUserInteractionEnabled = true
        stateLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stateImageViewClick)))
        contentView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.top.equalTo(stateImageView.snp.bottom).offset(SCRYFrom(-2))
            make.centerX.equalTo(stateImageView)
        }
        
        signalStrengthView = DeviceSignalStrengthView()
        contentView.addSubview(signalStrengthView)
        signalStrengthView.snp.makeConstraints { make in
            make.left.equalTo(macAddressLabel)
            make.top.equalTo(macAddressLabel.snp.bottom).offset(SCRYFrom(8))
            make.width.equalTo(SCRXFrom(56))
            make.height.equalTo(2)
        }
        
        signalLabel = UILabel(text: "", textColor: AssistText_Color, fontSize: 12, fontWeight: .light, fit: false)
        contentView.addSubview(signalLabel)
        signalLabel.snp.makeConstraints { make in
            make.left.equalTo(signalStrengthView.snp.right).offset(SCRXFrom(9))
            make.centerY.equalTo(signalStrengthView)
        }
        
//        versionLabel = UILabel(text: "", textColor: AssistText_Color, fontSize: 12, fontWeight: .light, fit: false)
//        contentView.addSubview(versionLabel)
//        versionLabel.snp.makeConstraints { make in
//            make.left.equalTo(signalLabel.snp.right).offset(SCRXFrom(10))
//            make.centerY.equalTo(signalLabel)
//        }
        
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }

}
