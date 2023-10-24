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
    var nameLabel: UILabel!
    var macAddressLabel: UILabel!
    var identifyBtn: UIButton!
    var addBtn: UIButton!
    var stateImageView: UIImageView!
    var addStateLabel: UILabel!
    var identifyLoadingView: UIImageView!
    var identifyStateLabel: UILabel!
    
    weak var delegate: DeviceAddViewCellDelegate?
    
    var device: ProvisioningDevice! {
        didSet {
            
            deviceImageView.image = UIImage(named: "device_add_light")
            identifyBtn.isHidden = true
            addBtn.isHidden = true
            stateImageView.isHidden = true
            stateImageView.snp.updateConstraints { make in
                make.width.height.equalTo(SCRYFrom(30))
            }
            addStateLabel.isHidden = true
            identifyLoadingView.isHidden = true
            identifyStateLabel.isHidden = true
            
            stateImageView.layer.removeAnimation(forKey: "loading")
            deviceImageView.layer.removeAnimation(forKey: "identify")
            identifyLoadingView.layer.removeAnimation(forKey: "loading")
            
            switch device.selectedState {
            case .unselected:
                selectImageView.image = UIImage(named: "select_un")
            case .selected:
                selectImageView.image = UIImage(named: "select")
            case .disabled:
                selectImageView.image = UIImage(named: "select_disable")
            }
         
            switch device.addState {
            case .none, .scaning:
                identifyBtn.isHidden = false
                addBtn.isHidden = false
                if device.addState == .scaning {
                    identifyBtn.isEnabled = false
                    addBtn.isEnabled = false
                }else {
                    identifyBtn.isEnabled = true
                    addBtn.isEnabled = true
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
                    identifyStateLabel.text = "identifing".localizedString
                    deviceImageView.layer.addOpacityAnimation(fromOpacity: 1, toOpacity: 0, duration: 0.5, repeatCount: 10, animationKey: "identify")
                }else if device.addState == .identifyFail {
                    identifyStateLabel.text = "device_add_failed".localizedString
                    identifyStateLabel.textColor = Red_Color
                }
                let textSize = identifyStateLabel.sizeThatFits(CGSize(width: 120, height: 30))
                identifyStateLabel.snp.updateConstraints { make in
                    make.width.equalTo(textSize.width + SCRXFrom(12))
                }
                identifyLoadingView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
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
                stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "loading")
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
            }
        
            nameLabel.text = device.deviceName ?? "device".localizedString
            
            if let macAddress = device.macAddress, !macAddress.isEmpty {
                var result = ""
                var offset = 0
                for _ in 0..<Int(macAddress.count / 2) {
                    if offset + 2 > macAddress.count { break }
                    let string = macAddress.subString(rang: NSRange(location: offset, length: 2))
                    offset += 2
                    result.append(String(format: "%@%@", result.isEmpty ? "" : ":", string))
                }
                macAddressLabel.text = result
            }else {
                macAddressLabel.text = device.peripheral.identifier.uuidString
            }
            
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
            make.left.equalTo(SCRXFrom(42))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        nameLabel = UILabel(text: "Device", textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-135))
        }
        
        macAddressLabel = UILabel(text: "DF:EF:32:DG:HJ:67", textColor: RGB(156, 163, 175), fontSize: 14)
        contentView.addSubview(macAddressLabel)
        macAddressLabel.snp.makeConstraints { make in
            make.left.right.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(4))
        }
        
        addBtn = UIButton(normalImageName: nil, target: self, action: #selector(addBtnClick))
        addBtn.setBackgroundImage(UIImage(named: "device_add"), for: .normal)
        contentView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        identifyBtn = UIButton(title: "identify".localizedString, titleSize: 14, titleColor: TextBlack_Color, target: self, action: #selector(identifyBtnClick))
        identifyBtn.setTitleColor(TextBlack_Color.withAlphaComponent(0.5), for: .disabled)
        identifyBtn.layer.cornerRadius = SCRYFrom(3)
        identifyBtn.layer.borderColor = RGB(156, 163, 175).cgColor
        identifyBtn.layer.borderWidth = 0.5
        identifyBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: SCRXFrom(8))
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
        
        identifyStateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12)
        identifyStateLabel.layer.cornerRadius = 3
        identifyStateLabel.layer.borderWidth = 0.5
        identifyStateLabel.layer.borderColor = Message_Color.cgColor
        identifyStateLabel.textAlignment = .center
        identifyStateLabel.backgroundColor = .white
        identifyStateLabel.isHidden = true
        contentView.addSubview(identifyStateLabel)
        identifyStateLabel.snp.makeConstraints { make in
            make.center.equalTo(identifyLoadingView)
            make.height.equalTo(22)
            make.width.equalTo(50)
        }
        
        stateImageView = UIImageView()
        stateImageView.isUserInteractionEnabled = true
        stateImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stateImageViewClick)))
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        addStateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12)
        addStateLabel.layer.cornerRadius = 3
        addStateLabel.layer.borderWidth = 0.5
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
    }

}
