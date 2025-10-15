//
//  FirmwareUpdateStateView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/27.
//

import UIKit

protocol FirmwareUpdateStateViewDelegate: AnyObject {
    
    /// 点击取消更新回调
    func firmwareUpdateCancelAction(_ view: FirmwareUpdateStateView)
    
    /// 点击重试回调
    func firmwareUpdateRetryAction(_ view: FirmwareUpdateStateView)
    
    /// 点击ok回调
    func firmwareUpdateOKAction(_ view: FirmwareUpdateStateView)
}

class FirmwareUpdateStateView: UIView {

    /// 状态
    enum State {
        /// 连接中
        case connect
        /// 开始升级
        case start
        /// 升级中 progress：进度1~100%  estimatedTime：预估时间
        case inProgress(progress: Int, estimatedTime: String)
        /// 升级成功（单设备）
        case completed
        /// 升级失败（单设备）
        case failure(message: String?)
        /// 升级结果（多设备） successfuly：成功数量  failed：失败数量
        case result(successfuly: Int, failed: Int)
    }
    
//    enum UpdateState {
//        case start(title: String, message: String, deviceName: String, currentVersion: String, targetVersion: String)
//        case inProgress()
//    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var versionLabel: UILabel!
    private var progressView: CustomProgressView!
    private var progressLabel: UILabel!
    private var stateLabel: UILabel!
    private var operateBtn: UIButton!
    private var rertyBtn: UIButton!
    private var completedBtn: UIButton!
    private var failedBtn: UIButton!
    
    private var state: State = .connect
    weak var delegate: FirmwareUpdateStateViewDelegate?
    
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
    
    func start(title: String, message: String = "firmware_update_message".localizedString, deviceName: String, currentVersion: String, targetVersion: String) {
        
        titleLabel.text = title
        messageLabel.text = message
        progressLabel.text = "0%"
        progressView.progress = 0
        
        let versionAttStr = NSMutableAttributedString(string: "\(deviceName) : \(currentVersion)->\(targetVersion)")
        let deviceNameRange = (versionAttStr.string as NSString).range(of: deviceName)
        versionAttStr.addAttribute(.font, value: UIFont.systemFont(ofSize: SCRYFrom(14)), range: deviceNameRange)
        versionLabel.attributedText = versionAttStr
    }
    
    func update(state: State) {
        
        self.operateBtn.setTitle("cancel".localizedString, for: .normal)
        self.operateBtn.setTitleColor(TextBlack_Color, for: .normal)
        self.operateBtn.backgroundColor = .white
        self.operateBtn.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(132))
            make.width.equalTo(SCRXFrom(140))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        self.rertyBtn.isHidden = true
        self.completedBtn.isHidden = true
        self.failedBtn.isHidden = true
        self.stateLabel.textColor = SubText_Color
        self.stateLabel.isHidden = false
        self.versionLabel.isHidden = false
        self.progressView.isHidden = false
        self.progressLabel.isHidden = false
        
        self.state = state
        
        switch state {
        case .connect:
            self.stateLabel.text = "connect_to_device".localizedString
            
        case .start:
            self.stateLabel.text = "start_upgrade".localizedString
            
        case .inProgress(let progress, let estimatedTime):
            self.progressView.progress = progress
            self.progressLabel.text = "\(progress)%"
            self.stateLabel.text = String(format: "update_estimated_time".localizedString, estimatedTime)
        case .completed:
            self.stateLabel.text = "upgrade_completed".localizedString
            self.stateLabel.textColor = RGB(0, 209, 124)
            self.operateBtn.setTitle("ok".localizedString, for: .normal)
            self.operateBtn.setTitleColor(.white, for: .normal)
            self.operateBtn.backgroundColor = Bar_Color
        case .failure(let message):
            self.messageLabel.text = message ?? "single_upgrade_failure_message".localizedString
            self.stateLabel.text = "upgrade_failure".localizedString
            self.stateLabel.textColor = Red_Color
            self.rertyBtn.isHidden = false
            self.operateBtn.setTitle("cancel".localizedString, for: .normal)
            self.operateBtn.snp.remakeConstraints { make in
                make.right.equalTo(self.contentView.snp.centerX).offset(SCRXFrom(-7))
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(132))
                make.width.equalTo(SCRXFrom(124))
                make.height.equalTo(SCRYFrom(32))
                make.bottom.equalTo(SCRYFrom(-24))
            }
        case .result(let successfuly, let failed):
            if failed > 0 {
                self.messageLabel.text = "multi_upgrade_result_message".localizedString
                self.rertyBtn.isHidden = false
                self.operateBtn.setTitle("cancel".localizedString, for: .normal)
                self.operateBtn.snp.remakeConstraints { make in
                    make.right.equalTo(self.contentView.snp.centerX).offset(SCRXFrom(-7))
                    make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(76))
                    make.width.equalTo(SCRXFrom(124))
                    make.height.equalTo(SCRYFrom(32))
                    make.bottom.equalTo(SCRYFrom(-24))
                }
            }else {
                self.messageLabel.text = "multi_upgrade_completed_message".localizedString
                self.operateBtn.setTitle("ok".localizedString, for: .normal)
                self.rertyBtn.isHidden = true
                self.operateBtn.snp.remakeConstraints { make in
                    make.centerX.equalToSuperview()
                    make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(76))
                    make.width.equalTo(SCRXFrom(124))
                    make.height.equalTo(SCRYFrom(32))
                    make.bottom.equalTo(SCRYFrom(-24))
                }
            }
            self.titleLabel.text = "\("upgrade_result".localizedString): \(successfuly)/\(successfuly + failed)"
            self.stateLabel.isHidden = true
            self.completedBtn.isHidden = false
            self.failedBtn.isHidden = false
            self.versionLabel.isHidden = true
            self.progressView.isHidden = true
            self.progressLabel.isHidden = true
        
            let completedAttStr = NSMutableAttributedString(string: "\("completed:".localizedString) \(successfuly)")
            completedAttStr.addAttribute(.foregroundColor, value: TextBlack_Color, range: (completedAttStr.string as NSString).range(of: "\(successfuly)"))
            self.completedBtn.setAttributedTitle(completedAttStr, for: .normal)
            
            let failedAttStr = NSMutableAttributedString(string: "\("failed:".localizedString) \(failed)")
            failedAttStr.addAttribute(.foregroundColor, value: TextBlack_Color, range: (failedAttStr.string as NSString).range(of: "\(failed)"))
            self.failedBtn.setAttributedTitle(failedAttStr, for: .normal)
        }
        
    }
    
    // MARK: - Action
    /// 操作事件 cancel、ok
    @objc private func operateBtnAction() {
        hide()
        switch state {
        case .connect, .start, .inProgress:
            delegate?.firmwareUpdateCancelAction(self)
        default:
            delegate?.firmwareUpdateOKAction(self)
        }
        
    }
    
    /// 重试
    @objc private func rertyBtnAction() {
        hide()
        delegate?.firmwareUpdateRetryAction(self)
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
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.top.equalTo(SCRYFrom(24))
        }
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(26))
            make.right.equalTo(SCRXFrom(-26))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        versionLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        versionLabel.textAlignment = .center
        contentView.addSubview(versionLabel)
        versionLabel.snp.makeConstraints { make in
            make.left.right.equalTo(messageLabel)
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(24))
        }
        
        progressView = CustomProgressView()
        progressView.trackColor = RGB(217, 217, 217)
        progressView.cornerRadius = SCRYFrom(1)
        progressView.progressColor = Bar_Color
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(26))
            make.right.equalTo(SCRXFrom(-64))
            make.top.equalTo(versionLabel.snp.bottom).offset(SCRYFrom(22))
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
        
        completedBtn = UIButton(title: "completed: ".localizedString + "5", titleSize: 14, titleWeight: .light, titleColor: SubText_Color, normalImageName: "calibration_completed_num")
        completedBtn.setImagePosition(position: .left, spacing: SCRXFrom(6))
        completedBtn.isUserInteractionEnabled = false
        completedBtn.isHidden = true
        contentView.addSubview(completedBtn)
        completedBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(22))
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(23))
        }
        
        failedBtn = UIButton(title: "failed: 2".localizedString, titleSize: 14, titleWeight: .light, titleColor: SubText_Color, normalImageName: "calibration_failed_num")
        failedBtn.setImagePosition(position: .left, spacing: SCRXFrom(6))
        failedBtn.isUserInteractionEnabled = false
        failedBtn.isHidden = true
        contentView.addSubview(failedBtn)
        failedBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-28))
            make.top.centerY.equalTo(completedBtn)
        }
        
        operateBtn = UIButton(title: "cancel".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(operateBtnAction))
        operateBtn.backgroundColor = .white
        operateBtn.layer.cornerRadius = SCRYFrom(5)
        contentView.addSubview(operateBtn)
        operateBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(132))
            make.width.equalTo(SCRXFrom(140))
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
