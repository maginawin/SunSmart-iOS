//
//  MeshFirmwareTypeUpdateViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/10/31.
//

import UIKit
import NordicSigMeshSDK

class MeshFirmwareTypeUpdateViewCell: UICollectionViewCell {
    
    /// 设备类型
    private var deviceTypeView: UIView!
    private var deviceTypeLabel: UILabel!
    private var productIdLabel: UILabel!
    private var deviceTypeLineView: UIView!
    
    /// 本地版本
    private var targetVersionView: UIView!
    private var targetVersionTitleLabel: UILabel!
    private var targetVersionInfoView: UIView!
    private var targetVersionLabel: UILabel!
    private var newVersionView: UIView!
    private var versionInfoImageView: UIImageView!
//    private var targetVersionLineView: UIView!
    
    /// 版本状态
    private var versionStateView: UIView!
    private var versionStateTitleLabel: UILabel!
    private var versionStateLabel: UILabel!
    private var updatableTipsView: UIView!
    private var versionStateImageView: UIImageView!
    private var versionStateLineView: UIView!
    
    /// 设备数量
    private var deviceNumberView: UIView!
    private var totalLabel: UILabel!
    private var totalNumberLabel: UILabel!
    private var upgradedLabel: UILabel!
    private var upgradedNumberLabel: UILabel!
    
    /// 当前版本点击回调
    var currentVersionCallback: (()->Void)?
    
    var firmwareTypeData: FirmwareUpdateTypeData! {
        didSet {
            
            deviceTypeLabel.text = firmwareTypeData.categoryName
            productIdLabel.text = String(format: "0x%04X", firmwareTypeData.productId)
            if let targetVersion = firmwareTypeData.targetVersion, let serverVersion = firmwareTypeData.serverData?.version {
                newVersionView.isHidden = !(serverVersion.compare(targetVersion, options: .numeric) == .orderedDescending)
            }else {
                newVersionView.isHidden = true
            }
            targetVersionLabel.text = firmwareTypeData.targetVersion ?? "None"
            
            updatableTipsView.isHidden = true
            versionStateImageView.layer.removeAnimation(forKey: "updating")
            
            versionStateLabel.snp.remakeConstraints({ make in
                make.left.equalTo(targetVersionLabel)
                make.centerY.equalTo(versionStateTitleLabel)
            })
            
            if let updateState = firmwareTypeData.distributorData?.distributionState {
                
                switch updateState {
                case .none:
                    
                    versionStateImageView.isHidden = true
                    versionStateLabel.isHidden = false
                    switch firmwareTypeData.versionState {
                    case .none:
                        versionStateLabel.text = "--"
                        versionStateLabel.textColor = SubText_Color
                    case .updatable:
                        updatableTipsView.isHidden = false
                        versionStateLabel.text = "updatable".localizedString
                    case .latest:
                        versionStateLabel.text = "latest".localizedString
                    }
                    versionStateLabel.snp.remakeConstraints { make in
                        make.left.equalTo(updatableTipsView.snp.right).offset(SCRXFrom(6))
                        make.centerY.equalTo(versionStateTitleLabel)
                    }
                    
                case .await:
                    versionStateLabel.isHidden = true
                    versionStateImageView.isHidden = false
                    versionStateImageView.image = UIImage(named: "sync_waiting_small")
                    
                case .updating(let updatePhase):
                    versionStateLabel.isHidden = false
                    versionStateLabel.textColor = SubText_Color
                    var currentProgress: UInt8 = 0
                    switch updatePhase {
                    case .verifying:
                        currentProgress = 0
                    case .blob(let progress, _):
                        currentProgress = progress
                    case .apply:
                        currentProgress = 100
                    }
                    versionStateLabel.text = "\(currentProgress)%"
                    versionStateImageView.isHidden = false
                    versionStateImageView.image = UIImage(named: "sync_loading_small")
                    versionStateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "updating")
                    
                case .complete:
                    versionStateLabel.isHidden = false
                    versionStateLabel.text = "install_firmware_complete".localizedString
                    versionStateLabel.textColor = RGB(0, 209, 124)
                    versionStateImageView.isHidden = true
                case .failure:
                    versionStateLabel.isHidden = false
                    versionStateLabel.text = "install_firmware_failure".localizedString
                    versionStateLabel.textColor = Red_Color
                    versionStateImageView.isHidden = true
                case .waitingInstall:
                    versionStateLabel.isHidden = false
                    versionStateLabel.text = "waiting_install".localizedString
                    versionStateLabel.textColor = RGB(148, 163, 184)
                    versionStateImageView.isHidden = true
                }
               
                
            }else {
                versionStateImageView.isHidden = true
                versionStateLabel.isHidden = false
                switch firmwareTypeData.versionState {
                case .none:
                    versionStateLabel.text = "--"
                    versionStateLabel.textColor = SubText_Color
                case .updatable:
                    updatableTipsView.isHidden = false
                    versionStateLabel.text = "updatable".localizedString
                case .latest:
                    versionStateLabel.text = "latest".localizedString
                }
                
//                versionStateLabel.snp.remakeConstraints({ make in
//                    make.left.equalTo(targetVersionLabel)
//                    make.centerY.equalTo(versionStateTitleLabel)
//                })
            }
            
            
            
            totalNumberLabel.text = "\(firmwareTypeData.nodes.count)"
            if firmwareTypeData.targetVersion != nil {
                // 已升级的设备
                let upgradedCount = firmwareTypeData.upgradedNodes.count
//                firmwareTypeData.nodes.filter({ $0.firmwareVersion != nil && targetVersion.compare($0.firmwareVersion!, options: .numeric) == .orderedSame }).count
                upgradedNumberLabel.text = "\(upgradedCount)"
            }else {
                upgradedNumberLabel.text = "--"
            }
            
            
            
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowOpacity = 1
        layer.shadowRadius = SCRYFrom(10)
        layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Action
    /// 当前版本
    @objc private func targetVersionAction() {
        currentVersionCallback?()
    }
    
    
    // MARK: - UI
    
    private func setupUI() {
        
        deviceTypeView = UIView()
        contentView.addSubview(deviceTypeView)
        deviceTypeView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        deviceTypeLabel = UILabel(text: "BLE to 0-10V converter ", textColor: TextBlack_Color, fontSize: 14)
        deviceTypeView.addSubview(deviceTypeLabel)
        deviceTypeLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(22))
        }
        
        productIdLabel = UILabel(text: "0xBD01", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        deviceTypeView.addSubview(productIdLabel)
        productIdLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(deviceTypeLabel)
        }
        
        deviceTypeLineView = UIView()
        deviceTypeLineView.backgroundColor = RGB(236, 236, 236)
        deviceTypeView.addSubview(deviceTypeLineView)
        deviceTypeLineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        targetVersionView = UIView()
//        targetVersionView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(targetVersionAction)))
        contentView.addSubview(targetVersionView)
        targetVersionView.snp.makeConstraints { make in
            make.left.right.equalTo(deviceTypeView)
            make.top.equalTo(deviceTypeView.snp.bottom)
            make.height.equalTo(SCRYFrom(52))
        }
        
        targetVersionTitleLabel = UILabel(text: "current_target_version".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        targetVersionView.addSubview(targetVersionTitleLabel)
        targetVersionTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.centerY.equalToSuperview()
        }
        
        targetVersionInfoView = UIView()
        targetVersionInfoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(targetVersionAction)))
        targetVersionView.addSubview(targetVersionInfoView)
        targetVersionInfoView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
        }
        
        versionInfoImageView = UIImageView(image: UIImage(named: "firmware_version_more"))
        targetVersionInfoView.addSubview(versionInfoImageView)
        versionInfoImageView.snp.makeConstraints { make in
            make.top.bottom.right.equalToSuperview()
//            make.right.equalTo(SCRXFrom(-20))
//            make.centerY.equalToSuperview()
        }
        
        targetVersionLabel = UILabel(text: "1.2.0", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        targetVersionInfoView.addSubview(targetVersionLabel)
        targetVersionLabel.snp.makeConstraints { make in
            make.right.equalTo(versionInfoImageView.snp.left).offset(SCRXFrom(-9))
            make.left.equalToSuperview()
            make.centerY.equalTo(versionInfoImageView)
        }
        
        newVersionView = UIView()
        newVersionView.backgroundColor = RGB(255, 72, 49)
        newVersionView.layer.cornerRadius = 2
        targetVersionView.addSubview(newVersionView)
        newVersionView.snp.makeConstraints { make in
            make.right.equalTo(targetVersionLabel.snp.left).offset(SCRXFrom(-6))
            make.centerY.equalTo(targetVersionLabel)
            make.width.height.equalTo(4)
        }
        
        versionStateView = UIView()
        contentView.addSubview(versionStateView)
        versionStateView.snp.makeConstraints { make in
            make.left.right.equalTo(targetVersionView)
            make.top.equalTo(targetVersionView.snp.bottom)
            make.height.equalTo(SCRYFrom(40))
        }
        
        versionStateTitleLabel = UILabel(text: "device_version_state".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        versionStateView.addSubview(versionStateTitleLabel)
        versionStateTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(6))
        }
        
        updatableTipsView = UIView()
        updatableTipsView.backgroundColor = RGB(255, 72, 49)
        updatableTipsView.layer.cornerRadius = 2
        versionStateView.addSubview(updatableTipsView)
        updatableTipsView.snp.makeConstraints { make in
            make.centerX.width.height.equalTo(newVersionView)
            make.centerY.equalTo(versionStateTitleLabel)
        }
        
        versionStateLabel = UILabel(text: "--", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        versionStateView.addSubview(versionStateLabel)
        versionStateLabel.snp.makeConstraints { make in
            make.left.equalTo(updatableTipsView.snp.right).offset(SCRXFrom(6))
            make.centerY.equalTo(versionStateTitleLabel)
        }
        
        versionStateImageView = UIImageView()
        versionStateView.addSubview(versionStateImageView)
        versionStateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-23))
            make.centerY.equalTo(versionStateTitleLabel)
        }
        
        versionStateLineView = UIView()
        versionStateLineView.backgroundColor = deviceTypeLineView.backgroundColor
        versionStateView.addSubview(versionStateLineView)
        versionStateLineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        deviceNumberView = UIView()
        contentView.addSubview(deviceNumberView)
        deviceNumberView.snp.makeConstraints { make in
            make.left.right.equalTo(targetVersionView)
            make.top.equalTo(versionStateView.snp.bottom)
            make.height.equalTo(SCRYFrom(40))
        }
        
        totalLabel = UILabel(text: "total".localizedString + ":", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        deviceNumberView.addSubview(totalLabel)
        totalLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(17))
        }
        
        totalNumberLabel = UILabel(text: "10", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        totalNumberLabel.textAlignment = .right
        deviceNumberView.addSubview(totalNumberLabel)
        totalNumberLabel.snp.makeConstraints { make in
            make.left.equalTo(totalLabel.snp.right)
            make.centerY.equalTo(totalLabel)
            make.width.equalTo(SCRXFrom(34))
        }
        
        upgradedNumberLabel = UILabel(text: "10", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        upgradedNumberLabel.textAlignment = .right
        deviceNumberView.addSubview(upgradedNumberLabel)
        upgradedNumberLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-26))
            make.centerY.equalTo(totalLabel)
            make.width.equalTo(SCRXFrom(34))
        }
        
        upgradedLabel = UILabel(text: "upgraded".localizedString + ":", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        deviceNumberView.addSubview(upgradedLabel)
        upgradedLabel.snp.makeConstraints { make in
            make.right.equalTo(upgradedNumberLabel.snp.left)
            make.centerY.equalTo(upgradedNumberLabel)
        }
    }
}
