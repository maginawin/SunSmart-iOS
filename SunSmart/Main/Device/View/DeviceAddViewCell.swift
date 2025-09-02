//
//  DeviceAddViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/10.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceAddViewCellDelegate: AnyObject {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice)
    
    /// 设备添加点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice)
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice)

}

class DeviceAddViewCell: UITableViewCell {

    var selectImageView: UIImageView!
    var deviceImageView: UIImageView!
    var identifyAnimationView: UIImageView!
    var nameLabel: UILabel!
    var macAddressLabel: UILabel!
    var identifyBtn: UIButton!
    var addBtn: UIButton!
    var stateImageView: UIImageView!
    var addStateLabel: UILabel!
    var identifyLoadingView: UIImageView!
    var identifyStateLabel: UILabel!
    var signalStrengthView: DeviceSignalStrengthView!
    var signalLabel: UILabel!
    var lineView: UIView!
    var activityImageView: UIImageView!
    
    var activityTimer: Timer?
    
    weak var delegate: DeviceAddViewCellDelegate?
    
    var device: ProvisioningDevice! {
        didSet {
            
            deviceImageView.image = UIImage(named: device.icon ?? "")
            identifyAnimationView.isHidden = true
            identifyBtn.isHidden = true
            addBtn.isHidden = true
            stateImageView.isHidden = true
            stateImageView.snp.updateConstraints { make in
                make.width.height.equalTo(30)
            }
            addStateLabel.isHidden = true
            identifyLoadingView.isHidden = true
            identifyStateLabel.isHidden = true
            
            if !(device.addState == .identifying || device.addState == .identifyConnecting || device.addState == .identifyWait) {
                identifyLoadingView.layer.removeAnimation(forKey: "loading")
            }
            if device.addState != .identifying {
                deviceImageView.layer.removeAnimation(forKey: "identify")
            }
            if !(device.addState == .addConnecting || device.addState == .adding) {
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
            
         
            switch device.addState {
            case .none, .scaning:
                identifyBtn.isHidden = false
                addBtn.isHidden = false
                if device.addState == .scaning {
                    identifyBtn.isEnabled = false
                    addBtn.isEnabled = false
                    identifyBtn.layer.borderColor = RGB(156, 163, 175, 0.5).cgColor
                }else {
                    identifyBtn.isEnabled = true
                    addBtn.isEnabled = device.deviceType != .unknown
                    identifyBtn.layer.borderColor = Bar_Color.cgColor
                }
                
            case .identifyConnecting, .identifyWait, .identifying, .identifyFail:
                addBtn.isHidden = false
                identifyLoadingView.isHidden = false
                identifyStateLabel.isHidden = false
                identifyStateLabel.textColor = TextBlack_Color
                if device.addState == .identifyWait {
                    identifyStateLabel.text = "device_add_waiting".localizedString
                }else if device.addState == .identifyConnecting {
                    identifyStateLabel.text = "device_add_connecting".localizedString
                    addBtn.isHidden = true
                }else if device.addState == .identifying {
                    identifyStateLabel.text = "identifying".localizedString
                    identifyAnimationView.isHidden = false
//                    deviceImageView.layer.addOpacityAnimation(fromOpacity: 1, toOpacity: 0, duration: 0.5, repeatCount: 10, animationKey: "identify")
                    if identifyAnimationView.layer.animation(forKey: "identify") == nil {
                        identifyAnimationView.layer.addScaleAnimation(fromScale: 0, toScale: 1, duration: 1, repeatCount: .max, timingName: .easeInEaseOut, animationKey: "identify")
                    }
                }else if device.addState == .identifyFail {
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
            case .addConnecting, .adding:
                addStateLabel.isHidden = false
                if device.addState == .addConnecting {
                    addStateLabel.text = "device_add_connecting".localizedString
                }else {
                    addStateLabel.text = "device_add_adding".localizedString
                }
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "loading")
                if stateImageView.layer.animation(forKey: "loading") == nil {
                    stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
                }
                stateImageView.snp.updateConstraints { make in
                    make.width.height.equalTo(SCRYFrom(40))
                }
                let textSize = addStateLabel.sizeThatFits(CGSize(width: 120, height: 30))
                addStateLabel.snp.updateConstraints { make in
                    make.width.equalTo(textSize.width + SCRXFrom(10))
                }
            case .success:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_success")
            case .failed:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "device_add_fail")
                identifyBtn.isHidden = false
            case .syncFailed:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "sync_failed")
                identifyBtn.isHidden = false
            }
        
            nameLabel.text = device.deviceName ?? "device".localizedString
            
            if let macAddress = device.macAddress, !macAddress.isEmpty {
                macAddressLabel.text = macAddress.getMacAddressSegmentString()
            }else {
                macAddressLabel.text = device.peripheral.identifier.uuidString
            }

            
            let activityDuration = device.activityDate != nil ? device.activityDate!.distance(to: Date()) : 0
            
            if device.triggerActionTypes.count > 0 && activityDuration < 3 && device.addState != .identifying {
                if device.triggerActionTypes.contains(.lightSensing) {
                    activityImageView.image = UIImage(named: "device_lightsensor_activity")
                }else if device.triggerActionTypes.contains(.motionSensing) {
                    activityImageView.image = UIImage(named: "device_motion_activity")
                }
                activityImageView.isHidden = false
                startActivityTimer(interval: 3 - activityDuration)
//                if device.macAddress == "D8A6F671810F" {
//                    
//                    print("activity: \(Date().timeIntervalSince1970 - device.activityDate!.timeIntervalSince1970)")
//                }
            }else {
                activityImageView.isHidden = true
                stopActivityTimer()
            }
            if device.icon?.contains("Lighting") ?? true {
                identifyAnimationView.snp.updateConstraints { make in
                    make.centerX.equalToSuperview()
                    make.centerY.equalToSuperview().offset(SCRYFrom(-4))
                }
                
                activityImageView.snp.updateConstraints { make in
        //            make.centerX.equalToSuperview().offset(-0.3)
        //            make.top.equalTo(SCRYFrom(3))
                    make.centerX.equalToSuperview().offset(-0.2)
                    make.centerY.equalToSuperview().offset(SCRYFrom(-4))
                }
            }else {
                
                identifyAnimationView.snp.updateConstraints { make in
                    make.centerX.centerY.equalToSuperview()
                }
                
                activityImageView.snp.updateConstraints { make in
        //            make.centerX.equalToSuperview().offset(-0.3)
        //            make.top.equalTo(SCRYFrom(3))
                    make.centerX.equalToSuperview().offset(-0.2)
                    make.centerY.equalToSuperview().offset(-0.2)
                }
            }
            
            signalStrengthView.setSignalStrength(rssi: device.rssi.intValue)
            signalLabel.text = "\(device.rssi.intValue)dB"
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func startActivityTimer(interval: TimeInterval) {
        stopActivityTimer()
        
        activityTimer = LCWeakTimer.scheduledTimer(timeInterval: interval, aTarget: self, selector: #selector(deviceActivityFinish), userInfo: nil, repeats: false)
        RunLoop.current.add(activityTimer!, forMode: .common)
    }
    
    private func stopActivityTimer() {
        activityTimer?.invalidate()
        activityTimer = nil
    }
    
    @objc private func deviceActivityFinish() {
        device.triggerActionTypes.removeAll()
        
        activityImageView.isHidden = true
    }
    
    // MARK: - Action
    
    /// 添加设备
    @objc private func addBtnClick() {
        delegate?.cell(self, deviceAdd: device)
    }
    
    /// 识别设备
    @objc private func identifyBtnClick() {
        delegate?.cell(self, identify: device)
    }
    
    /// 设备状态图标点击
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
//        identifyAnimationView.backgroundColor = RGB(0, 234, 164)
//        identifyAnimationView.isUserInteractionEnabled = false
//        identifyAnimationView.layer.cornerRadius = SCRYFrom(6)
        deviceImageView.addSubview(identifyAnimationView)
        identifyAnimationView.snp.makeConstraints { make in
            make.centerX.centerY.equalToSuperview()
//            make.top.equalTo(SCRYFrom(3))
            make.width.height.equalTo(SCRYFrom(10))
        }
        
        activityImageView = UIImageView(image: UIImage(named: "device_motion_activity"))
        activityImageView.isHidden = true
        deviceImageView.addSubview(activityImageView)
        activityImageView.snp.makeConstraints { make in
//            make.centerX.equalToSuperview().offset(-0.3)
//            make.top.equalTo(SCRYFrom(3))
            make.centerX.equalToSuperview().offset(-0.2)
            make.centerY.equalToSuperview().offset(-0.2)
            make.width.height.equalTo(SCRYFrom(15))
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
        
        addBtn = UIButton(normalImageName: nil, target: self, action: #selector(addBtnClick))
        addBtn.setImage(UIImage(named: "device_add"), for: .normal)
        addBtn.setImage(UIImage(named: "device_add_disable"), for: .disabled)
        contentView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
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
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(addBtn)
            make.height.equalTo(addBtn)
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
        
        addStateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        addStateLabel.layer.cornerRadius = 3
        addStateLabel.layer.borderWidth = 0.6
        addStateLabel.layer.borderColor = Message_Color.cgColor
        addStateLabel.textAlignment = .center
        addStateLabel.backgroundColor = .white
        addStateLabel.isHidden = true
        contentView.addSubview(addStateLabel)
        addStateLabel.snp.makeConstraints { make in
            make.center.equalTo(stateImageView)
            make.height.equalTo(22)
            make.width.equalTo(50)
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
