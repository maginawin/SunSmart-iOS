//
//  SyncDeviceViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit

protocol SyncDeviceViewCellDelegate: AnyObject {
    
    /// 选中/取消选中更新回调
    func cell(_ cell: SyncDeviceViewCell, didSelectedAction model: SyncDevicesModel)
    
    /// 图标点击回调
    func cell(_ cell: SyncDeviceViewCell, iconClickAction model: SyncDevicesModel)
    
    /// 失败重试回调
    func cell(_ cell: SyncDeviceViewCell, resyncAction model: SyncDevicesModel)
    
    /// 状态图标点击回调
    func cell(_ cell: SyncDeviceViewCell, stateImageClickAction model: SyncDevicesModel)
    
}

extension SyncDeviceViewCellDelegate {
    
    /// 状态图标点击回调
    func cell(_ cell: SyncDeviceViewCell, stateImageClickAction model: SyncDevicesModel) {}
}

class SyncDeviceViewCell: UITableViewCell {

    var selectedImageView: UIImageView!
    var iconImageBtn: UIButton!
    var nameLabel: UILabel!
    var stateImageView: UIImageView!
    var arrowImageView: UIImageView!
    var failureLabel: UILabel!
    var resyncBtn: UIButton!
    var lineView: UIView!
    weak var delegate: SyncDeviceViewCellDelegate?
    
    var model: SyncDevicesModel! {
        didSet {
            
            nameLabel.text = model.name
            
            iconImageBtn.setImage(UIImage(named: model.imageName), for: .normal)
            
            let isGroup = model.steps.count > 0

            
            stateImageView.layer.removeAnimation(forKey: "loading")
            resyncBtn.isHidden = true
            failureLabel.isHidden = true
            selectedImageView.isHidden = true
            selectedImageView.image = UIImage(named: model.isSelected ? "device_select" : "device_select_un")
            stateImageView.snp.updateConstraints { make in
                make.right.equalTo(SCRXFrom(-60))
            }
//            isFineshed
            switch model.state {
            case .none:
                stateImageView.isHidden = true
                
            case .wait:
                stateImageView.isHidden = false
                if isGroup {
                    stateImageView.image = UIImage(named: "device_add_waiting")
                    stateImageView.snp.updateConstraints { make in
                        make.right.equalTo(SCRXFrom(-16))
                    }
                }else {
                    stateImageView.image = UIImage(named: "sync_waiting_small")
                }
                
            case .successful:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "sync_success_small")
            case .failed:
                
                if model.failedCount > 1 {
                    failureLabel.isHidden = false
                    stateImageView.isHidden = true
                }else {
                    stateImageView.isHidden = false
                    failureLabel.isHidden = true
                    stateImageView.image = UIImage(named: "sync_failed_small")
                }
                if model.isFineshed {
                    selectedImageView.isHidden = false
                    resyncBtn.isHidden = false
                }else {
                    resyncBtn.isHidden = true
                }
                
            case .inSettings:
                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "sync_loading_small")
                stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: 9999, animationKey: "loading")
            }
            
            var selectedImageLeft = SCRXFrom(36)
            var iconImageLeft = SCRXFrom(68)
            
            if isGroup {
                selectedImageView.isUserInteractionEnabled = true
                resyncBtn.isHidden = true
                if model.isFineshed {
                    selectedImageLeft = SCRXFrom(16)
                    iconImageLeft = SCRXFrom(48)
                    stateImageView.isHidden = false
                }else {
                    iconImageLeft = SCRXFrom(16)
                    stateImageView.isHidden = model.state == .none || model.state == .inSettings
                }
                
                if model.parentGroupModel != nil {
                    iconImageLeft += SCRXFrom(20)
                }
                    arrowImageView.isHidden = model.state == .none || model.state == .wait
                arrowImageView.image = UIImage(named: model.isShow ? "arrow_up" : "arrow_down")
//                }
                
            }else {
                selectedImageView.isUserInteractionEnabled = false
                arrowImageView.isHidden = true
                if model.isFineshed && model.parentGroupModel != nil {
                    iconImageLeft = SCRXFrom(68)
                }else {
                    iconImageLeft = SCRXFrom(48)
                    selectedImageLeft = SCRXFrom(16)
                }
            }
            
            selectedImageView.snp.updateConstraints { make in
                make.left.equalTo(selectedImageLeft)
            }
            
            iconImageBtn.snp.updateConstraints { make in
                make.left.equalTo(iconImageLeft)
            }
            
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 图标点击
    @objc private func iconImageBtnAction() {
        delegate?.cell(self, iconClickAction: model)
    }
    
    /// 重试
    @objc private func resyncBtnAction() {
        delegate?.cell(self, resyncAction: model)
    }
    
    /// 选中/取消选中
    @objc private func selectedImageViewAction() {
        delegate?.cell(self, didSelectedAction: model)
    }
    
    /// 状态图标点击
    @objc private func stateImageViewAction() {
        delegate?.cell(self, stateImageClickAction: model)
    }
    
    private func setupUI() {
        
        selectedImageView = UIImageView(image: UIImage(named: "device_select_un"))
        selectedImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectedImageViewAction)))
        contentView.addSubview(selectedImageView)
        selectedImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(36))
            make.centerY.equalToSuperview()
        }
        
        iconImageBtn = UIButton(normalImageName: "device_light", target: self, action: #selector(iconImageBtnAction))
        contentView.addSubview(iconImageBtn)
        iconImageBtn.snp.makeConstraints { make in
//            make.left.equalTo(selectedImageView.snp.right).offset(SCRXFrom(2))
            make.left.equalTo(SCRXFrom(68))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "ID007", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageBtn.snp.right).offset(SCRXFrom(6))
            make.width.lessThanOrEqualTo(SCRXFrom(220))
            make.centerY.equalTo(iconImageBtn)
        }
        
        resyncBtn = UIButton(normalImageName: "scene_sync", target: self, action: #selector(resyncBtnAction))
        contentView.addSubview(resyncBtn)
        resyncBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        stateImageView = UIImageView(image: UIImage(named: "loading"))
        stateImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stateImageViewAction)))
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-60))
            make.centerY.equalToSuperview()
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down"))
        addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        failureLabel = UILabel(text: "failure".localizedString, textColor: Red_Color, fontSize: 14, fontWeight: .light)
        failureLabel.isHidden = true
        contentView.addSubview(failureLabel)
        failureLabel.snp.makeConstraints { make in
            make.right.centerY.equalTo(stateImageView)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }
}
