//
//  EmerFireAlarmSyncDeviceStepViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit

protocol EmerFireAlarmSyncDeviceStepViewCellDelegate: AnyObject {
    /// 重新同步事件回调
    func cell(_ cell: EmerFireAlarmSyncDeviceStepViewCell, resyncAction model: EmerFireAlarmSyncStepModel)
}

class EmerFireAlarmSyncDeviceStepViewCell: UITableViewCell {

    /// 进度
    var progressLabel: UILabel!
    /// 状态
    var stateImageView: UIImageView!
    /// 操作名称
    var stepNameLabel: UILabel!
    /// 失败文本
    var failureLabel: UILabel!
    /// 重试
    var resyncBtn: UIButton!
    /// 进度线
    var topLineView: UIView!
    var bottomLineView: UIView!
    
    weak var delegate: EmerFireAlarmSyncDeviceStepViewCellDelegate?
    
    var stepModel: EmerFireAlarmSyncStepModel! {
        didSet {
            
            stepNameLabel.text = stepModel.type
            if stepModel.showProgress {
                progressLabel.text = "\(stepModel.current)/\(stepModel.count)"
            }else {
                progressLabel.text = nil
            }
            resyncBtn.isHidden = true
            stateImageView.isHidden = false
            
//            var loadingStart: Double = 0
//            if let loadingAnimation = stateImageView.layer.animation(forKey: "loading") as? CABasicAnimation, let fromValue =  loadingAnimation.fromValue as? Double {
//                loadingStart = fromValue / 2.0 / .pi
//            }
            
//            if stepModel.state != .inSettings {
                stateImageView.layer.removeAnimation(forKey: "loading")
//            }
            failureLabel.isHidden = true
            
            switch stepModel.state {
            case .wait:
                stateImageView.image = UIImage(named: "sync_waiting_small")
                progressLabel.isHidden = true
            case .successful:
                stateImageView.image = UIImage(named: "sync_success_small")
                progressLabel.isHidden = true
            case .failed:
//                stateImageView.image = UIImage(named: "sync_failed_small")
//                stateImageView.isHidden = false
                stateImageView.image = UIImage(named: "sync_failed_small")
                progressLabel.isHidden = false
                
                if stepModel.tasks.contains(where: { $0.failedCount > 1 }) {
                    failureLabel.isHidden = false
                }else {
                    failureLabel.isHidden = true
                }
                resyncBtn.isHidden = !stepModel.isFineshed
            case .inSettings:
                stateImageView.image = UIImage(named: "sync_loading_small")
                if let animation = stepModel.loadingAnimation {
                    stateImageView.layer.add(animation, forKey: "loading")
                }else {
                    stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: 9999, animationKey: "loading")
                    if let animation = stateImageView.layer.animation(forKey: "loading") {
                        stepModel.loadingAnimation = animation
                    }
                }
                progressLabel.isHidden = false
            default:
                break
            }
            
            if stepModel.parentDeviceModel?.parentGroupModel != nil {
                progressLabel.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(40))
                }
                stateImageView.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(79))
                }
            }
            
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func resyncBtnAction() {
        delegate?.cell(self, resyncAction: stepModel)
    }
    
    private func setupUI() {
        
        progressLabel = UILabel(text: "16/16", textColor: RGB(100, 116, 139), fontSize: 13, fontWeight: .light)
        contentView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.centerY.equalToSuperview()
        }
        
        stateImageView = UIImageView(image: UIImage(named: "sync_success"))
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(59))
//            make.width.height.equalTo(SCRYFrom(24))
        }
        
        stepNameLabel = UILabel(text: "Scene", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
        contentView.addSubview(stepNameLabel)
        stepNameLabel.snp.makeConstraints { make in
            make.left.equalTo(stateImageView.snp.right).offset(SCRXFrom(19))
            make.width.lessThanOrEqualTo(SCRXFrom(200))
            make.centerY.equalTo(stateImageView)
        }
        
        topLineView = UIView()
        topLineView.backgroundColor = RGB(220, 220, 220)
        contentView.addSubview(topLineView)
        topLineView.snp.makeConstraints { make in
            make.centerX.equalTo(stateImageView)
            make.top.equalToSuperview()
            make.bottom.equalTo(stateImageView.snp.top)
            make.width.equalTo(1)
        }
        
        bottomLineView = UIView()
        bottomLineView.backgroundColor = RGB(220, 220, 220)
        contentView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.centerX.width.equalTo(topLineView)
            make.top.equalTo(stateImageView.snp.bottom)
            make.bottom.equalToSuperview()
            make.width.equalTo(1)
        }
        
        resyncBtn = UIButton(normalImageName: "scene_sync", target: self, action: #selector(resyncBtnAction))
        contentView.addSubview(resyncBtn)
        resyncBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(stepNameLabel)
        }
        
        failureLabel = UILabel(text: "failure".localizedString, textColor: Red_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(failureLabel)
        failureLabel.snp.makeConstraints { make in
            make.right.equalTo(resyncBtn.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalTo(resyncBtn)
        }
        
    }
}
