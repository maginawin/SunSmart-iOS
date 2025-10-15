//
//  EnergyHarvestStateView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/6.
//

import UIKit

protocol EnergyHarvestStateViewDelegate: AnyObject {
    
    /// 点击取消回调
    func energyHarvestCancelAction(_ view: EnergyHarvestStateView)
    
    /// 点击重试回调
    func energyHarvestRetryAction(_ view: EnergyHarvestStateView)
    
    /// 点击完成回调
    func energyHarvestDoneAction(_ view: EnergyHarvestStateView)
}

class EnergyHarvestStateView: UIView {

    /// 状态
    enum State {
        /// 连接中
        case connect
        /// 获取中 progress：进度1~100%  estimatedTime：预估时间
        case inProgress(progress: Int, estimatedTime: String)
        /// 获取成功
        case completed
        /// 获取失败
        case failure(message: String?)
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var progressView: CustomProgressView!
    private var progressLabel: UILabel!
    private var stateLabel: UILabel!
    private var failedBtn: UIButton!
    private var operateBtn: UIButton!
    private var rertyBtn: UIButton!
    
    private var state: State = .connect
    weak var delegate: EnergyHarvestStateViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        } completion: { _ in
            
        }
    }
    
    func hide() {
        
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    func update(state: State) {
        
        self.operateBtn.setTitle("cancel".localizedString, for: .normal)
//        self.operateBtn.setTitleColor(TextBlack_Color, for: .normal)
//        self.operateBtn.backgroundColor = .white
        self.operateBtn.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(92))
            make.width.equalTo(SCRXFrom(124))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        self.rertyBtn.isHidden = true
        self.failedBtn.isHidden = true
        self.stateLabel.textColor = SubText_Color
        self.stateLabel.isHidden = false
        self.progressView.isHidden = false
        self.progressLabel.isHidden = false
        
        self.state = state
        
        switch state {
        case .connect:
            self.stateLabel.text = "connect_to_device".localizedString
            self.progressView.progress = 0
            self.progressLabel.text = "0%"
        case .inProgress(let progress, let estimatedTime):
            self.progressView.progress = progress
            self.progressLabel.text = "\(progress)%"
            self.stateLabel.text = String(format: "update_estimated_time".localizedString, estimatedTime)
        case .completed:
            self.stateLabel.text = "harvest_completed".localizedString
            self.stateLabel.textColor = RGB(0, 209, 124)
            self.operateBtn.setTitle("done".localizedString, for: .normal)
//            self.operateBtn.setTitleColor(.white, for: .normal)
//            self.operateBtn.backgroundColor = Bar_Color
        case .failure:
//            self.messageLabel.text = message ?? "single_upgrade_failure_message".localizedString
//            self.stateLabel.text = "upgrade_failure".localizedString
//            self.stateLabel.textColor = Red_Color
            self.stateLabel.isHidden = true
            self.failedBtn.isHidden = false
            self.rertyBtn.isHidden = false
            self.operateBtn.setTitle("cancel".localizedString, for: .normal)
            self.operateBtn.snp.remakeConstraints { make in
                make.right.equalTo(self.contentView.snp.centerX).offset(SCRXFrom(-7))
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(92))
                make.width.equalTo(SCRXFrom(124))
                make.height.equalTo(SCRYFrom(32))
                make.bottom.equalTo(SCRYFrom(-24))
            }
        }
        
    }
    
    // MARK: - Action
    /// 操作事件 cancel、ok
    @objc private func operateBtnAction() {
        switch state {
        case .connect, .inProgress:
//            delegate?.firmwareUpdateCancelAction(self)
            SRAlertView(title: "notification".localizedString, message: "energy_harvest_cancel_prompt".localizedString, actions: [SRAlertAction(title: "NO".localizedString, style: .cancel), SRAlertAction(title: "YES".localizedString, style: .default, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                self.delegate?.energyHarvestCancelAction(self)
                self.hide()
                
            })]).show()
            
        default:
            hide()
            delegate?.energyHarvestDoneAction(self)
        }
        
    }
    
    /// 重试
    @objc private func rertyBtnAction() {
        hide()
        delegate?.energyHarvestRetryAction(self)
    }
    
    /// 点击失败提示
    @objc private func failedBtnAction() {
        if case .failure(let message) = state {
            SRAlertView(message: message, actions: [SRAlertAction(title: "GOT IT".localizedString)]).show()
        }
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = RGB(239, 239, 239)
        contentView.layer.cornerRadius = SCRYFrom(20)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(isIPad ? SCRXFrom(150) : SCRXFrom(37))
            make.right.equalTo(isIPad ? SCRXFrom(-150) : SCRXFrom(-36))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: "harvest".localizedString, textColor: TextBlack_Color, fontSize: 15)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.top.equalTo(SCRYFrom(24))
        }
        
        messageLabel = UILabel(text: "energy_harvest_message".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(26))
            make.right.equalTo(SCRXFrom(-26))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        progressView = CustomProgressView()
        progressView.trackColor = RGB(217, 217, 217)
        progressView.cornerRadius = SCRYFrom(1)
        progressView.progressColor = Bar_Color
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(26))
            make.right.equalTo(SCRXFrom(-64))
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(26))
            make.height.equalTo(SCRYFrom(2))
        }
        
        progressLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.left.equalTo(progressView.snp.right).offset(SCRXFrom(11))
            make.centerY.equalTo(progressView)
        }
        
        stateLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(progressView.snp.bottom).offset(SCRYFrom(12))
        }
        
        failedBtn = UIButton(title: "harvest_failed".localizedString, titleSize: 14, titleWeight: .light, titleColor: Red_Color, normalImageName: "device_fault", target: self, action: #selector(failedBtnAction))
        failedBtn.setImagePosition(position: .right, spacing: SCRXFrom(8))
        failedBtn.isHidden = true
        contentView.addSubview(failedBtn)
        failedBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(progressView.snp.bottom).offset(SCRYFrom(9))
        }
        
        operateBtn = UIButton(title: "cancel".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(operateBtnAction))
        operateBtn.backgroundColor = .white
        operateBtn.layer.cornerRadius = SCRYFrom(5)
        contentView.addSubview(operateBtn)
        operateBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(92))
            make.width.equalTo(SCRXFrom(124))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        
        rertyBtn = UIButton(title: "RETRY".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(rertyBtnAction))
        rertyBtn.backgroundColor = .white
        rertyBtn.layer.cornerRadius = SCRYFrom(5)
        rertyBtn.isHidden = true
        contentView.addSubview(rertyBtn)
        rertyBtn.snp.makeConstraints { make in
            make.left.equalTo(contentView.snp.centerX).offset(SCRXFrom(7))
            make.centerY.height.equalTo(operateBtn)
            make.width.equalTo(SCRXFrom(124))
        }
        
    }
    
}
