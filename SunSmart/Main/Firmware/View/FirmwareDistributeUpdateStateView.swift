//
//  FirmwareDistributeUpdateStateView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/6.
//

import UIKit

protocol FirmwareDistributeUpdateStateViewDelegate: AnyObject {
    
    /// 点击取消更新回调
    func firmwareUpdateCancelAction(_ view: FirmwareDistributeUpdateStateView)
    
    /// 点击重试回调
    func firmwareUpdateRetryAction(_ view: FirmwareDistributeUpdateStateView)
    
    /// 点击ok回调
    func firmwareUpdateOKAction(_ view: FirmwareDistributeUpdateStateView)
    
    /// 点击详情回调
    func firmwareUpdateDetailsAction(_ view: FirmwareDistributeUpdateStateView)
}

extension FirmwareDistributeUpdateStateViewDelegate {
    /// 点击取消更新回调
    func firmwareUpdateCancelAction(_ view: FirmwareDistributeUpdateStateView) {}
    
    /// 点击重试回调
    func firmwareUpdateRetryAction(_ view: FirmwareDistributeUpdateStateView) {}
    
    /// 点击ok回调
    func firmwareUpdateOKAction(_ view: FirmwareDistributeUpdateStateView) {}
    
    /// 点击详情回调
    func firmwareUpdateDetailsAction(_ view: FirmwareDistributeUpdateStateView) {}
}

class FirmwareDistributeUpdateStateView: UIView {

    /// 状态
    enum State {
        /// 连接中
        case connect
        /// 开始升级
        case start
        /// 上传中 progress：进度1~100%  estimatedTime：预估时间
        case inProgress(progress: Int, estimatedTime: String?)
        /// 上传成功
        case completed
        /// 上传失败
        case failure(message: String?)
    }
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var messageLabel: UILabel!
    private var progressView: CustomProgressView!
    private var progressLabel: UILabel!
    private var stateImageView: UIImageView!
    private var stateLabel: UILabel!
    private var operateBtn: UIButton!
    private var rertyBtn: UIButton!
    private var detailsBtn: UIButton!
    
    private var state: State = .connect
    /// 是否上传固件
    private var isUpload: Bool = true
    /// 是否分发所有者
    private var isOwner: Bool = false
    weak var delegate: FirmwareDistributeUpdateStateViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
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
    
    func start(title: String, message: String, deviceName: String? = nil, distributeVersion: String?, isUpload: Bool = true, isOwner: Bool = false) {
        self.isUpload = isUpload
        self.isOwner = isOwner
        titleLabel.text = title
        messageLabel.text = message
        progressLabel.text = "0%"
        progressView.progress = 0
        
        if let name = deviceName, let version = distributeVersion, isUpload {
            stateLabel.text = "\(version)--> \(name)"
        }
    }
    
    /// 更新状态
    func update(state: State) {
        
        self.operateBtn.setTitle("cancel".localizedString, for: .normal)
        self.operateBtn.setTitleColor(TextBlack_Color, for: .normal)
        self.operateBtn.backgroundColor = .white
        self.operateBtn.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(stateLabel.snp.bottom).offset(SCRYFrom(23))
            make.width.equalTo(SCRXFrom(140))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        self.rertyBtn.isHidden = true
        self.stateLabel.textColor = TextBlack_Color
        self.messageLabel.isHidden = false
        self.stateLabel.isHidden = false
        self.progressView.isHidden = false
        self.progressLabel.isHidden = false
        self.stateImageView.isHidden = false
        self.detailsBtn.isHidden = true
        self.stateLabel.snp.remakeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(progressView.snp.bottom).offset(SCRYFrom(12))
        }
        
        self.state = state
        
        switch state {
        case .connect:
            fallthrough
        case .start:
            if !isUpload {
                self.operateBtn.setTitle("GOT_IT".localizedString, for: .normal)
            }
            if isOwner {
                self.operateBtn.snp.remakeConstraints { make in
                    make.left.equalTo(self.contentView.snp.centerX).offset(SCRXFrom(7))
                    make.top.equalTo(stateLabel.snp.bottom).offset(SCRYFrom(23))
                    make.width.equalTo(SCRXFrom(124))
                    make.height.equalTo(SCRYFrom(32))
                    make.bottom.equalTo(SCRYFrom(-24))
                }
                self.detailsBtn.isHidden = false
            }
        case .inProgress(let progress, let estimatedTime):
            self.progressView.progress = progress
            self.progressLabel.text = "\(progress)%"
            if !isUpload {
                self.stateLabel.text = String(format: "update_estimated_time".localizedString, estimatedTime ?? "")
                self.stateLabel.textColor = SubText_Color
                self.operateBtn.setTitle("GOT_IT".localizedString, for: .normal)
            }
            if isOwner {
                self.operateBtn.snp.remakeConstraints { make in
                    make.left.equalTo(self.contentView.snp.centerX).offset(SCRXFrom(7))
                    make.top.equalTo(stateLabel.snp.bottom).offset(SCRYFrom(23))
                    make.width.equalTo(SCRXFrom(124))
                    make.height.equalTo(SCRYFrom(32))
                    make.bottom.equalTo(SCRYFrom(-24))
                }
                self.detailsBtn.isHidden = false
            }
        case .completed:
            self.messageLabel.isHidden = true
            self.progressView.isHidden = true
            self.progressLabel.isHidden = true
            self.stateImageView.image = UIImage(named: "success_big")
            self.stateImageView.isHidden = false
            self.stateLabel.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalTo(self.stateImageView.snp.bottom).offset(SCRYFrom(8))
            }
            self.operateBtn.setTitle("ok".localizedString, for: .normal)
        case .failure(let message):
            self.messageLabel.isHidden = true
            self.stateImageView.image = UIImage(named: "disconnect_big")
            self.stateImageView.isHidden = false
            self.progressView.isHidden = true
            self.progressLabel.isHidden = true
            self.stateLabel.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalTo(self.stateImageView.snp.bottom).offset(SCRYFrom(8))
            }
            self.rertyBtn.isHidden = false
            self.operateBtn.snp.remakeConstraints { make in
                make.right.equalTo(self.contentView.snp.centerX).offset(SCRXFrom(-7))
                make.top.equalTo(stateLabel.snp.bottom).offset(SCRYFrom(23))
                make.width.equalTo(SCRXFrom(124))
                make.height.equalTo(SCRYFrom(32))
                make.bottom.equalTo(SCRYFrom(-24))
            }
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
    
    /// 详情
    @objc private func detailsBtnAction() {
        hide()
        delegate?.firmwareUpdateDetailsAction(self)
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
            make.left.equalTo(SCRXFrom(37))
            make.right.equalTo(SCRXFrom(-36))
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
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: FontFit(14), fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(21))
            make.right.equalTo(SCRXFrom(-21))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(10))
        }
        
        progressView = CustomProgressView()
        progressView.trackColor = RGB(217, 217, 217)
        progressView.cornerRadius = SCRYFrom(1)
        progressView.progressColor = Bar_Color
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-82))
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(23))
            make.height.equalTo(SCRYFrom(2))
        }
        
        progressLabel = UILabel(text: "", textColor: Bar_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.left.equalTo(progressView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(progressView)
        }
        
        stateImageView = UIImageView()
        contentView.addSubview(stateImageView)
        stateImageView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(26))
            make.centerX.equalToSuperview()
        }
        
        stateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: FontFit(14), fontWeight: .light, fit: false)
        contentView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(progressView.snp.bottom).offset(SCRYFrom(12))
        }
        
        operateBtn = UIButton(title: "cancel".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(operateBtnAction))
        operateBtn.backgroundColor = .white
        operateBtn.layer.cornerRadius = SCRYFrom(5)
        contentView.addSubview(operateBtn)
        operateBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(stateLabel.snp.bottom).offset(SCRYFrom(23))
            make.width.equalTo(SCRXFrom(140))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        
        rertyBtn = UIButton(title: "re-upload".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(rertyBtnAction))
        rertyBtn.backgroundColor = .white
        rertyBtn.layer.cornerRadius = SCRYFrom(5)
        rertyBtn.isHidden = true
        contentView.addSubview(rertyBtn)
        rertyBtn.snp.makeConstraints { make in
            make.left.equalTo(contentView.snp.centerX).offset(SCRXFrom(7))
            make.centerY.height.equalTo(operateBtn)
            make.width.equalTo(SCRXFrom(124))
        }
        
        detailsBtn = UIButton(title: "DETAILS".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(detailsBtnAction))
        detailsBtn.backgroundColor = .white
        detailsBtn.layer.cornerRadius = SCRYFrom(5)
        detailsBtn.isHidden = true
        contentView.addSubview(detailsBtn)
        detailsBtn.snp.makeConstraints { make in
            make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-7))
            make.centerY.height.equalTo(operateBtn)
            make.width.equalTo(SCRXFrom(124))
        }
        
    }
    
    
}
