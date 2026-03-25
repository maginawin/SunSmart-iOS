//
//  ProfileNightDayIlluminanceThresholdView.swift
//  SunSmart
//
//  Created by yuankehong on 2026/1/4.
//

import UIKit

protocol ProfileNightDayIlluminanceThresholdViewDelegate: AnyObject {
    
    /// 帮助
    func nightDayIlluminanceThresholdViewHelpAction(_ view: ProfileNightDayIlluminanceThresholdView)
    
    /// 编辑晚上输入条件lux回调
    func view(_ view: ProfileNightDayIlluminanceThresholdView, nightStartsBelowLuxEditChanged lux: Int?)
    
    /// 编辑白天输入条件lux回调
    func view(_ view: ProfileNightDayIlluminanceThresholdView, dayStartsAboveLuxEditChanged lux: Int?)
    
    /// 设备详情
    func nightDayIlluminanceThresholdViewDeviceDetailAction(_ view: ProfileNightDayIlluminanceThresholdView)
    
}

class ProfileNightDayIlluminanceThresholdView: UIView {
    
    /// 设备详情照度设置状态
    enum DeviceDetailStartLuxState {
        /// 无
        case none
        /// 所有设备与组一致
        case allSameGroup
        /// 部分设备与组不一致
        case someDifferentGroup
        /// 组内没有设备
        case noDevices
    }

    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    
    private var nightStartsBelowLabel: UILabel!
    private var nightLuxField: UITextField!
    private var nightLuxLabel: UILabel!
    private var nightLuxTipLabel: UILabel!
    
    private var dayStartsAboveLabel: UILabel!
    private var dayLuxField: UITextField!
    private var dayLuxLabel: UILabel!
    private var dayLuxTipLabel: UILabel!
    
    private var deviceDetailView: UIView!
    private var deviceDetailTitleLabel: UILabel!
    private var deviceDetailTipLabel: UILabel!
    private var deviceDetailArrowImageView: UIImageView!
    
    private var deviceDetailNoteView: UIView!
    private var deviceDetailNoteLabel: UILabel!
    
    var editable: Bool = true
    
    weak var delegate: ProfileNightDayIlluminanceThresholdViewDelegate?
    
    /// 晚上的条件lux
    var nightStartsBelowLux: Int? {
        get {
            guard let inputText = nightLuxField.text, let lux = Int(inputText) else { return nil }
            return lux
        }set {
            nightLuxField.text = newValue != nil ? "\(newValue!)" : nil
        }
    }
    
    /// 白天的条件lux
    var dayStartsAboveLux: Int? {
        get {
            guard let inputText = dayLuxField.text, let lux = Int(inputText) else { return nil }
            return lux
        }set {
            dayLuxField.text = newValue != nil ? "\(newValue!)" : nil
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 更新晚上条件lux 提示
    func updateNightStartsBelowLuxTip(tipMessage: String? = nil) {
        nightLuxTipLabel.text = tipMessage
        if tipMessage != nil {
            nightLuxField.layer.borderColor = Red_Color.cgColor
        }else {
            nightLuxField.layer.borderColor = Border_Color.cgColor
        }
    }
    
    /// 更新白天条件lux 提示
    func updateDayStartsAboveLuxTip(tipMessage: String? = nil) {
        dayLuxTipLabel.text = tipMessage
        if tipMessage != nil {
            dayLuxField.layer.borderColor = Red_Color.cgColor
        }else {
            dayLuxField.layer.borderColor = Border_Color.cgColor
        }
    }
    
    /// 更新设备详情描述文本
    func updateDeviceDetailMessage(state: DeviceDetailStartLuxState) {
        
        switch state {
        case .none:
            deviceDetailTipLabel.text = nil
        case .allSameGroup:
            deviceDetailTipLabel.text = "profile_all_start_lux_same_group".localizedString
            deviceDetailTipLabel.textColor = Green_Color
        case .someDifferentGroup:
            deviceDetailTipLabel.text = "profile_some_start_lux_different_group".localizedString
            deviceDetailTipLabel.textColor = Orange_Color
        case .noDevices:
            deviceDetailTipLabel.text = "profile_group_no_devices".localizedString
            deviceDetailTipLabel.textColor = AssistText_Color
        }
        
        if state == .someDifferentGroup {
            deviceDetailNoteView.isHidden = false
            deviceDetailView.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.top.equalTo(dayLuxField.snp.bottom).offset(SCRYFrom(16))
                make.height.equalTo(SCRYFrom(30))
            }
            deviceDetailNoteView.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(deviceDetailView.snp.bottom).offset(SCRYFrom(8))
                make.bottom.equalTo(SCRYFrom(-24))
            }
        }else {
            deviceDetailNoteView.isHidden = true
            deviceDetailView.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.top.equalTo(dayLuxField.snp.bottom).offset(SCRYFrom(16))
                make.height.equalTo(SCRYFrom(30))
                make.bottom.equalTo(SCRYFrom(-24))
            }
            deviceDetailNoteView.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(deviceDetailView.snp.bottom).offset(SCRYFrom(8))
            }
        }
        
    }
    
    
    // MARK: - Action
    
    @objc private func helpBtnAction() {
        
        delegate?.nightDayIlluminanceThresholdViewHelpAction(self)
    }
    
    /// 晚上条件lux输入回调
    @objc private func nightLuxFieldEditChanged(sender: UITextField) {
        guard editable else {
            return
        }
        sender.layer.borderColor = Border_Color.cgColor
        nightLuxTipLabel.text = nil
        delegate?.view(self, nightStartsBelowLuxEditChanged: nightStartsBelowLux)
    }
    
    @objc private func dayLuxFieldEditChanged(sender: UITextField) {
        guard editable else {
            return
        }
        sender.layer.borderColor = Border_Color.cgColor
        dayLuxTipLabel.text = nil
        delegate?.view(self, dayStartsAboveLuxEditChanged: dayStartsAboveLux)
    }
    
    @objc private func deviceDetailViewAction() {
        delegate?.nightDayIlluminanceThresholdViewDeviceDetailAction(self)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "nightday_illuminance_threshold".localizedString, textColor: TextBlack_Color, fontSize: 16)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(10))
        }
        
        nightStartsBelowLabel = UILabel(text: "night_starts_below_lux".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(nightStartsBelowLabel)
        nightStartsBelowLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20))
        }
        
        nightLuxLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        addSubview(nightLuxLabel)
        nightLuxLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(nightStartsBelowLabel)
        }
        
        nightLuxField = UITextField()
        nightLuxField.textColor = ImportantText_Color
        nightLuxField.textAlignment = .center
        nightLuxField.font = UIFont.systemFont(ofSize: FontFit(12))
        nightLuxField.keyboardType = .numberPad
        nightLuxField.layer.cornerRadius = SCRYFrom(5)
        nightLuxField.layer.borderWidth = 0.6
        nightLuxField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        nightLuxField.returnKeyType = .done
        nightLuxField.delegate = self
        nightLuxField.addTarget(self, action: #selector(nightLuxFieldEditChanged), for: .editingChanged)
        addSubview(nightLuxField)
        nightLuxField.snp.makeConstraints { make in
            make.right.equalTo(nightLuxLabel.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(nightLuxLabel)
            make.width.equalTo(isIPad ? SCRXFrom(100) : SCRXFrom(72))
            make.height.equalTo(SCRYFrom(28))
        }
        
        nightLuxTipLabel = UILabel(text: "", textColor: Error_Red_Color, fontSize: 12, fontWeight: .light)
        addSubview(nightLuxTipLabel)
        nightLuxTipLabel.snp.makeConstraints { make in
            make.top.equalTo(nightLuxField.snp.bottom).priority(.high)
            make.right.equalTo(SCRXFrom(-16))
        }
        
        dayStartsAboveLabel = UILabel(text: "day_starts_above_lux".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(dayStartsAboveLabel)
        dayStartsAboveLabel.snp.makeConstraints { make in
            make.left.equalTo(nightStartsBelowLabel)
            make.top.equalTo(nightLuxField.snp.bottom).offset(SCRYFrom(22))
        }
        
        dayLuxLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        addSubview(dayLuxLabel)
        dayLuxLabel.snp.makeConstraints { make in
            make.right.equalTo(nightLuxLabel)
            make.centerY.equalTo(dayStartsAboveLabel)
        }
        
        dayLuxField = UITextField()
        dayLuxField.textColor = ImportantText_Color
        dayLuxField.textAlignment = .center
        dayLuxField.font = UIFont.systemFont(ofSize: FontFit(12))
        dayLuxField.keyboardType = .numberPad
        dayLuxField.layer.cornerRadius = SCRYFrom(5)
        dayLuxField.layer.borderWidth = 0.6
        dayLuxField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        dayLuxField.returnKeyType = .done
        dayLuxField.delegate = self
        dayLuxField.addTarget(self, action: #selector(dayLuxFieldEditChanged), for: .editingChanged)
        addSubview(dayLuxField)
        dayLuxField.snp.makeConstraints { make in
            make.right.width.height.equalTo(nightLuxField)
            make.centerY.equalTo(dayLuxLabel)
            make.width.equalTo(isIPad ? SCRXFrom(100) : SCRXFrom(72))
        }
        
        dayLuxTipLabel = UILabel(text: "", textColor: Error_Red_Color, fontSize: 12, fontWeight: .light)
        addSubview(dayLuxTipLabel)
        dayLuxTipLabel.snp.makeConstraints { make in
            make.top.equalTo(dayLuxField.snp.bottom).priority(.high)
            make.right.equalTo(nightLuxTipLabel)
        }
        
        deviceDetailView = UIView()
        deviceDetailView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deviceDetailViewAction)))
        addSubview(deviceDetailView)
        deviceDetailView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(dayLuxField.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(30))
        }
        
        deviceDetailTitleLabel = UILabel(text: "device_detail".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        deviceDetailTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        deviceDetailTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        deviceDetailView.addSubview(deviceDetailTitleLabel)
        deviceDetailTitleLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
        }
        
        deviceDetailArrowImageView = UIImageView(image: UIImage(named: "arrow_right_black"))
        deviceDetailArrowImageView.sizeToFit()
        deviceDetailView.addSubview(deviceDetailArrowImageView)
        deviceDetailArrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-10))
            make.centerY.equalToSuperview()
            make.size.equalTo(deviceDetailArrowImageView.frame.size)
        }
        
        deviceDetailTipLabel = UILabel(text: "", textColor: Green_Color, fontSize: 12, fit: false)
        deviceDetailTipLabel.textAlignment = .right
        deviceDetailTipLabel.adjustsFontSizeToFitWidth = true
        deviceDetailView.addSubview(deviceDetailTipLabel)
        deviceDetailTipLabel.snp.makeConstraints { make in
            make.right.equalTo(deviceDetailArrowImageView.snp.left).priority(.high)
            make.left.equalTo(deviceDetailTitleLabel.snp.right).offset(SCRXFrom(20)).priority(.low)
            make.centerY.equalToSuperview()
        }
        
        deviceDetailNoteView = UIView()
        deviceDetailNoteView.backgroundColor = RGB(254, 252, 200)
        deviceDetailNoteView.layer.cornerRadius = 10
        addSubview(deviceDetailNoteView)
        deviceDetailNoteView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(deviceDetailView.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalTo(SCRYFrom(-24))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.alignment = .center
        
        deviceDetailNoteLabel = UILabel(text: "", textColor: Title_Color, fontSize: 12, fontWeight: .light, fit: false)
        deviceDetailNoteLabel.numberOfLines = 0
        deviceDetailNoteLabel.attributedText = NSMutableAttributedString(string: "profile_start_lux_note".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        deviceDetailNoteView.addSubview(deviceDetailNoteLabel)
        deviceDetailNoteLabel.snp.makeConstraints { make in
            make.edges.equalTo(UIEdgeInsets(top: SCRYFrom(8), left: SCRYFrom(8), bottom: SCRYFrom(8), right: SCRYFrom(8)))
        }
            
    }
    
}

extension ProfileNightDayIlluminanceThresholdView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endEditing(true)
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.isEmpty || string.isPureNumandCharacters() else {
            return false
        }
        return true
    }
    
}
