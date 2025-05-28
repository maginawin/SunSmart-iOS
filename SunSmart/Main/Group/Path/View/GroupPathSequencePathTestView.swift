//
//  GroupPathSequencePathTestView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/26.
//

import UIKit
import NordicSigMeshSDK

class GroupPathSequencePathTestView: UIView {
    /// 状态
    enum State {
        /// 无（未开始）
        case none
        /// 测试中
        case testing
        /// 暂停
        case pause
    }

    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var closeBtn: UIButton!
    private var messageLabel: UILabel!
    private var startBtn: UIButton!
    private var stopBtn: UIButton!
    private var stateView: UIView!
    private var stateLabel: UILabel!
    private var progressLabel: UILabel!
    
    private let group: Group
    private var addresses: [Address]
    private var state: State = .none
    private var controlTimer: Timer?
    
    private var progress: Int = 0

    init(group: Group, addresses: [Address]) {
        self.group = group
        self.addresses = addresses
        
        super.init(frame: UIScreen.main.bounds)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
        }
        
        updateUI()
        shadeView.alpha = 0
        contentView.alpha = 0
        UIView.animate(withDuration: 0.25) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
        }
        
    }
    
    private func dismiss() {
        
        stopControlTimer()
        
        UIView.animate(withDuration: 0.25) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    private func updateUI() {
        
        switch state {
        case .none:
            messageLabel.text = "path_test_start_message".localizedString
            startBtn.isSelected = false
            startBtn.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(16))
            }
            stopBtn.isHidden = true
            stateLabel.text = "click_start_test".localizedString
            stateLabel.textColor = TextBlack_Color
        case .testing:
            
            messageLabel.text = "path_testing_message".localizedString
            startBtn.isSelected = true
            startBtn.snp.remakeConstraints { make in
                make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-20))
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(16))
            }
            stopBtn.isHidden = false
            stateLabel.text = "testing…".localizedString
            stateLabel.textColor = Green_Color
            
        case .pause:
            
            messageLabel.text = "path_testing_message".localizedString
            startBtn.isSelected = false
            startBtn.snp.remakeConstraints { make in
                make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-20))
                make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(16))
            }
            stopBtn.isHidden = false
            stateLabel.text = "pause_test".localizedString
            stateLabel.textColor = Red_Color
            
        }
        
        updateProgressText()
    }
    
    /// 更新进度文本
    private func updateProgressText() {
        
        let attStr = NSMutableAttributedString(string: "\(progress)/\(addresses.count)")
        attStr.addAttribute(.foregroundColor, value: TextBlack_Color, range: (attStr.string as NSString).range(of: "\(progress)/"))
        progressLabel.attributedText = attStr
    }
    
    // MARK: - Mesh
    private func startControlTimer(fireDelay: TimeInterval? = nil) {
        
        controlTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: {[weak self] timer in
            guard let self = self else { return }
            guard timer.isValid, self.progress < self.addresses.count else {
                self.stopControlTimer()
                self.state = .none
                self.updateUI()
                return
            }
            MeshAPI.setNodeLightnessState(address: self.addresses[self.progress], lightness: .max)
            self.progress += 1
            self.updateProgressText()
            if self.progress == self.addresses.count {
                self.stopControlTimer()
                self.progress = 0
                self.state = .none
                self.updateUI()
            }
        })
        if let delay = fireDelay {
            controlTimer?.fireDate = Date(timeIntervalSinceNow: delay)
        }
        RunLoop.current.add(controlTimer!, forMode: .common)
    }
    
    private func stopControlTimer() {
        controlTimer?.invalidate()
        controlTimer = nil
    }
    
    // MARK: - Action
    
    @objc private func closeBtnAction() {
        dismiss()
    }
    
    @objc private func startBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            if state == .none {
                // 把组内灯熄灭
                MeshAPI.setGroupOnOffState(address: group.address.address, isOn: false)
                startControlTimer(fireDelay: 2)
            }else {
                startControlTimer()
            }
            state = .testing
            
        }else {
            state = .pause
            stopControlTimer()
        }
        updateUI()
    }
    
    @objc private func stopBtnAction() {
        progress = 0
        state = .none
        stopControlTimer()
        updateUI()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(15)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(8)))
            make.height.equalTo(SCRYFrom(188))
        }
        
        titleLabel = UILabel(text: "test".localizedString, textColor: TextBlack_Color, fontSize: 16, fit: false)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(closeBtnAction))
        contentView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(8))
        }
        
        messageLabel = UILabel(text: "path_test_start_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(22))
            make.right.equalTo(SCRXFrom(-22))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
        }
        
        startBtn = UIButton(normalImageName: "quick_add_start", selectedImageName: "quick_add_pause", target: self, action: #selector(startBtnAction))
        contentView.addSubview(startBtn)
        startBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        stopBtn = UIButton(normalImageName: "quick_add_stop", target: self, action: #selector(stopBtnAction))
        stopBtn.isHidden = true
        contentView.addSubview(stopBtn)
        stopBtn.snp.makeConstraints { make in
            make.left.equalTo(self.snp.centerX).offset(SCRXFrom(20))
            make.centerY.equalTo(startBtn)
        }
        
        stateView = UIView()
        contentView.addSubview(stateView)
        stateView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-24))
        }
        
        stateLabel = UILabel(text: "click_start_test".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light, fit: false)
        stateView.addSubview(stateLabel)
        stateLabel.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
        }
        
        progressLabel = UILabel(text: "0/0", textColor: AssistText_Color, fontSize: 14, fontWeight: .light, fit: false)
        stateView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.left.equalTo(stateLabel.snp.right).offset(SCRXFrom(16))
            make.right.equalToSuperview()
        }
    }
    
}
