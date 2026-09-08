//
//  SyncDeviceStepViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit

protocol SyncDeviceStepViewCellDelegate: AnyObject {
    /// 重新同步事件回调
    func cell(_ cell: SyncDeviceStepViewCell, resyncAction model: SyncDeviceStepModel)
}

class SyncDeviceStepViewCell: UITableViewCell {

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
    
    weak var delegate: SyncDeviceStepViewCellDelegate?
    
    private var displayedState: SyncDevicesState?
    private var displayedFinished: Bool?
    private var displayedFailure: Bool?

    var stepModel: SyncDeviceStepModel! {
        didSet {
            displayedState = nil
            stepNameLabel.text = stepModel.type
            let isGrouped = stepModel.parentDeviceModel?.parentGroupModel != nil
            progressLabel.snp.updateConstraints { make in
                make.left.equalTo(SCRXFrom(isGrouped ? 40 : 20))
            }
            stateImageView.snp.updateConstraints { make in
                make.left.equalTo(SCRXFrom(isGrouped ? 79 : 59))
            }
            updateProgress()
        }
    }

    /// 进度变化直接更新文字，保留现有 Cell 和正在运行的动画。
    func updateProgress() {
        guard let stepModel else { return }
        let progressText = stepModel.showProgress ? "\(stepModel.current)/\(stepModel.count)" : nil
        if progressLabel.text != progressText {
            progressLabel.text = progressText
        }

        var state = stepModel.state
        // 前一个任务完成、下一个任务尚未开始时，聚合状态会短暂返回 wait。
        // 已开始的步骤保持进度可见，不改变任务模型的状态或调度语义。
        if state == .wait, !stepModel.isFineshed,
           stepModel.tasks.contains(where: { $0.state == .successful || $0.state == .failed }) {
            state = .inSettings
        }
        let hasRepeatedFailure = stepModel.tasks.contains { $0.failedCount > 1 }
        guard displayedState != state || displayedFinished != stepModel.isFineshed ||
                displayedFailure != hasRepeatedFailure else { return }
        displayedState = state
        displayedFinished = stepModel.isFineshed
        displayedFailure = hasRepeatedFailure

        resyncBtn.isHidden = true
        failureLabel.isHidden = true
        stateImageView.isHidden = false
        if state != .inSettings {
            stateImageView.layer.removeAnimation(forKey: "loading")
        }
        switch state {
        case .none, .wait:
            stateImageView.image = UIImage(named: "sync_waiting_small")
            progressLabel.isHidden = true
        case .successful:
            stateImageView.image = UIImage(named: "sync_success_small")
            progressLabel.isHidden = true
        case .failed:
            stateImageView.image = UIImage(named: "sync_failed_small")
            progressLabel.isHidden = false
            failureLabel.isHidden = !hasRepeatedFailure
            resyncBtn.isHidden = !stepModel.isFineshed
        case .inSettings:
            stateImageView.image = UIImage(named: "sync_loading_small")
            progressLabel.isHidden = false
            if stateImageView.layer.animation(forKey: "loading") == nil {
                stateImageView.layer.addRotationAnimation(duration: 1.5, repeatCount: 9999, animationKey: "loading")
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
        progressLabel.font = .monospacedDigitSystemFont(ofSize: progressLabel.font.pointSize, weight: .light)
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
