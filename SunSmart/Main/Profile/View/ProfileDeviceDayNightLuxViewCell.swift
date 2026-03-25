//
//  ProfileDeviceDayNightLuxViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/23.
//

import UIKit
import NordicSigMeshSDK

protocol ProfileDeviceDayNightLuxViewCellDelegate: AnyObject {
    
    /// 识别设备
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, identify device: Node)
    
    /// 晚上lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, nightLuxEditChanged nightLux: Int?)
    
    /// 晚上lux停止编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, nightLuxEditEnd nightLux: Int?)
    
    /// 白天lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditChanged dayLux: Int?)
    
    /// 白天lux停止编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditEnd dayLux: Int?)
    
    /// 获取当前lux
    func deviceDayNightLuxViewCellGetLuxAction(_ cell: ProfileDeviceDayNightLuxViewCell)
    
    /// 恢复lux修改
    func deviceDayNightLuxViewCellResetAction(_ cell: ProfileDeviceDayNightLuxViewCell)
    
    /// 确认修改回调
    func deviceDayNightLuxViewCellModifyAction(_ cell: ProfileDeviceDayNightLuxViewCell)
    
    /// 设备重新同步事件
    func deviceDayNightLuxViewCellResyncAction(_ cell: ProfileDeviceDayNightLuxViewCell)
    
}

extension ProfileDeviceDayNightLuxViewCellDelegate {
    
    /// 晚上lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, nightLuxEditChanged nightLux: Int?) {
        
    }
    
    /// 晚上lux停止编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, nightLuxEditEnd nightLux: Int?) {
        
    }
    
    /// 白天lux编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditChanged dayLux: Int?) {
        
    }
    
    /// 白天lux停止编辑
    func cell(_ cell: ProfileDeviceDayNightLuxViewCell, dayLuxEditEnd dayLux: Int?) {
        
    }
    
    /// 获取当前lux
    func deviceDayNightLuxViewCellGetLuxAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        
    }
    
    /// 恢复lux修改
    func deviceDayNightLuxViewCellResetAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        
    }
    
    /// 确认修改回调
    func deviceDayNightLuxViewCellModifyAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        
    }
    
    /// 设备重新同步事件
    func deviceDayNightLuxViewCellResyncAction(_ cell: ProfileDeviceDayNightLuxViewCell) {
        
    }
    
}

class ProfileDeviceDayNightLuxViewCell: UICollectionViewCell {
    
    var selectedImageView: UIImageView!
    var deviceImageView: UIImageView!
    var nameLabel: UILabel!
    var getLuxBtn: UIButton!
    var luxLabel: UILabel!
    var nonsupportNoteLabel: UILabel!
    private var luxUnitLabel: UILabel!
    
    private var nightStartsBelowLabel: UILabel!
    var nightLuxField: UITextField!
    private var nightLuxUnitLabel: UILabel!
    var dayStartsAboveLabel: UILabel!
    var dayLuxField: UITextField!
    private var dayLuxUnitLabel: UILabel!
    private var luxLineView: UIView!
    
    var modifyBtn: UIButton!
    var resetBtn: UIButton!
    var syncFailBtn: UIButton!
    
    private var updateLuxTimer: Timer?
    
    weak var delegate: ProfileDeviceDayNightLuxViewCellDelegate?
    
    var device: Node! {
        didSet {
            
            nameLabel.text = device.name
            deviceImageView.image = UIImage(named: device.iconName)
            if let lux = device.steadyDaylightLux {
                luxLabel.text = "\(lux)"
            }else {
                luxLabel.text = "--"
            }
            if let nightLux = device.tempNightLux {
                nightLuxField.text = "\(nightLux)"
            }else {
                nightLuxField.text = ""
            }
            if let dayLux = device.tempDayLux {
                dayLuxField.text = "\(dayLux)"
            }else {
                dayLuxField.text = ""
            }
            
        }
    }
    
    /// 设备图标左边距
    var deviceImageLeftMargin: CGFloat = SCRXFrom(12) {
        didSet {
            deviceImageView.snp.updateConstraints { make in
                make.left.equalTo(deviceImageLeftMargin)
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Action
    
    @objc private func getLuxBtnAction() {
        delegate?.deviceDayNightLuxViewCellGetLuxAction(self)
    }
    
    @objc private func resetBtnAction() {
        delegate?.deviceDayNightLuxViewCellResetAction(self)
    }
    
    @objc private func modifyBtnAction() {
        delegate?.deviceDayNightLuxViewCellModifyAction(self)
    }
    
    @objc private func nightLuxFieldEditChanged(sender: UITextField) {
        guard let text = sender.text, let lux = Int(text) else {
            delegate?.cell(self, nightLuxEditChanged: nil)
            return
        }
        delegate?.cell(self, nightLuxEditChanged: lux)
    }
    
    
    @objc private func nightLuxFieldEditEnd(sender: UITextField) {
        guard let text = sender.text, let lux = Int(text) else {
            delegate?.cell(self, nightLuxEditEnd: nil)
            return
        }
        delegate?.cell(self, nightLuxEditEnd: lux)
    }
    
    @objc private func dayLuxFieldEditChanged(sender: UITextField) {
        guard let text = sender.text, let lux = Int(text) else {
            delegate?.cell(self, dayLuxEditChanged: nil)
            return
        }
        delegate?.cell(self, dayLuxEditChanged: lux)
    }
    
    @objc private func dayLuxFieldEditEnd(sender: UITextField) {
        guard let text = sender.text, let lux = Int(text) else {
            delegate?.cell(self, dayLuxEditEnd: nil)
            return
        }
        delegate?.cell(self, dayLuxEditEnd: lux)
    }

    
    @objc private func deviceImageViewAction() {

        delegate?.cell(self, identify: device)
    }
    
    @objc private func syncFailBtnAction() {
        
        delegate?.deviceDayNightLuxViewCellResyncAction(self)
    }
    
    // MARK: - Publich Methods
    
    /// 刷新节点lux
    func reloadNodeLux() {
        if let lux = device.steadyDaylightLux {
            luxLabel.text = "\(lux)"
            luxLabel.backgroundColor = RGB(179, 237, 103)
            luxLabel.layer.borderWidth = 0
        }
    }
    
    /// 开始get lux loading
    func startGetLuxLoading() {
        getLuxBtn.setTitle(nil, for: .normal)
        getLuxBtn.setImage(UIImage(named: "loading_16"), for: .normal)
        getLuxBtn.imageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
    }
    
    /// 停止get lux loading
    func stopGetLuxLoading() {
        getLuxBtn.setTitle("get".localizedString, for: .normal)
        getLuxBtn.setImage(nil, for: .normal)
        getLuxBtn.imageView?.layer.removeAnimation(forKey: "loading")
    }
    
    /// 显示支持光照传感器UI
    func showLightSensorLuxUI() {
        
        luxLabel.isHidden = false
        luxUnitLabel.isHidden = false
        getLuxBtn.isHidden = false
        nightStartsBelowLabel.isHidden = false
        nightLuxField.isHidden = false
        nightLuxUnitLabel.isHidden = false
        luxLineView.isHidden = false
        dayStartsAboveLabel.isHidden = false
        dayLuxField.isHidden = false
        dayLuxUnitLabel.isHidden = false
        nonsupportNoteLabel.isHidden = true
    }
    
    /// 显示不支持光照传感器UI
    func showLightSensorNonsupportUI() {
        luxLabel.isHidden = true
        luxUnitLabel.isHidden = true
        getLuxBtn.isHidden = true
        nightStartsBelowLabel.isHidden = true
        nightLuxField.isHidden = true
        nightLuxUnitLabel.isHidden = true
        luxLineView.isHidden = true
        dayStartsAboveLabel.isHidden = true
        dayLuxField.isHidden = true
        dayLuxUnitLabel.isHidden = true
        modifyBtn.isHidden = true
        resetBtn.isHidden = true
        syncFailBtn.isHidden = true
        nonsupportNoteLabel.isHidden = false
    }
    
    // MARK: - Lux Timer
    
    /// 开始lux更新倒计时，3s内没有新的数据则变为灰色背景
    private func startUpdateLuxTimer() {
        
        stopUpdateLuxTimer()
        
        updateLuxTimer = LCWeakTimer.scheduledTimer(timeInterval: 1, aTarget: self, selector: #selector(updateLuxState), userInfo: nil, repeats: false)
        RunLoop.current.add(updateLuxTimer!, forMode: .common)
    }
    
    private func stopUpdateLuxTimer() {
        updateLuxTimer?.invalidate()
        updateLuxTimer = nil
    }
    
    @objc private func updateLuxState() {
        stopUpdateLuxTimer()
        luxLabel.backgroundColor = .clear
        luxLabel.layer.borderWidth = 1
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
//        stopUpdateLuxTimer()
        updateLuxState()
    }
    
    
    
    // MARK: - UI
    
    private func setupUI() {
        
        selectedImageView = UIImageView(image: UIImage(named: "schedule_target_select_un"))
        selectedImageView.isHidden = true
        contentView.addSubview(selectedImageView)
        selectedImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.top.equalTo(SCRYFrom(8))
        }
        
        deviceImageView = UIImageView()
        deviceImageView.isUserInteractionEnabled = true
        deviceImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deviceImageViewAction)))
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(deviceImageLeftMargin)
            make.top.equalTo(selectedImageView)
            make.width.height.equalTo(30)
        }
        
        getLuxBtn = UIButton(title: "get".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(getLuxBtnAction))
        getLuxBtn.layer.cornerRadius = SCRYFrom(12)
        getLuxBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.3).cgColor
        getLuxBtn.layer.borderWidth = 0.6
        contentView.addSubview(getLuxBtn)
        getLuxBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(deviceImageView)
            make.width.equalTo(SCRXFrom(44))
            make.height.equalTo(SCRYFrom(24))
        }
        
        luxUnitLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(luxUnitLabel)
        luxUnitLabel.snp.makeConstraints { make in
            make.right.equalTo(getLuxBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(getLuxBtn)
        }
        
        luxLabel = UILabel(text: "--", textColor: ImportantText_Color, fontSize: 12, fontWeight: .light)
        luxLabel.layer.cornerRadius = SCRYFrom(10)
        luxLabel.layer.masksToBounds = true
        luxLabel.layer.borderColor = RGB(220, 220, 220).cgColor
        luxLabel.textAlignment = .center
        luxLabel.layer.borderWidth = 1
        luxLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(luxLabel)
        luxLabel.snp.makeConstraints { make in
            make.right.equalTo(luxUnitLabel.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(luxUnitLabel)
            make.width.equalTo(SCRXFrom(52))
            make.height.equalTo(SCRYFrom(20))
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(deviceImageView)
            make.right.equalTo(luxLabel.snp.left).offset(SCRXFrom(-30)).priority(.low)
        }
        
        nightLuxField = UITextField()
        nightLuxField.textColor = TextBlack_Color
        nightLuxField.font = UIFont.systemFont(ofSize: FontFit(12))
        nightLuxField.keyboardType = .numberPad
        nightLuxField.textAlignment = .center
        nightLuxField.layer.cornerRadius = SCRYFrom(5)
        nightLuxField.layer.borderWidth = 0.6
        nightLuxField.layer.borderColor = TextField_Border_Color.cgColor
        nightLuxField.returnKeyType = .done
        nightLuxField.addTarget(self, action: #selector(nightLuxFieldEditChanged), for: .editingChanged)
        nightLuxField.addTarget(self, action: #selector(nightLuxFieldEditEnd), for: .editingDidEnd)
        nightLuxField.delegate = self
        contentView.addSubview(nightLuxField)
        nightLuxField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.bottom.equalTo(SCRYFrom(-13))
            make.width.equalTo(SCRXFrom(60))
            make.height.equalTo(SCRYFrom(28))
        }
        
        nightStartsBelowLabel = UILabel(text: "night_starts_below".localizedString, textColor: SubText_Color, fontSize: 10, fontWeight: .light)
        contentView.addSubview(nightStartsBelowLabel)
        nightStartsBelowLabel.snp.makeConstraints { make in
            make.left.equalTo(nightLuxField)
            make.bottom.equalTo(nightLuxField.snp.top).offset(SCRYFrom(-4))
        }
        
        nightLuxUnitLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(nightLuxUnitLabel)
        nightLuxUnitLabel.snp.makeConstraints { make in
            make.left.equalTo(nightLuxField.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(nightLuxField)
        }
        
        luxLineView = UIView()
        luxLineView.backgroundColor = Message_Color
        contentView.addSubview(luxLineView)
        luxLineView.snp.makeConstraints { make in
            make.centerY.equalTo(nightLuxField)
            make.left.equalTo(nightLuxUnitLabel.snp.right).offset(SCRXFrom(11))
            make.width.equalTo(0.5)
            make.height.equalTo(SCRYFrom(12))
        }
        
        dayLuxField = UITextField()
        dayLuxField.textColor = TextBlack_Color
        dayLuxField.font = UIFont.systemFont(ofSize: FontFit(12))
        dayLuxField.keyboardType = .numberPad
        dayLuxField.layer.cornerRadius = SCRYFrom(5)
        dayLuxField.layer.borderWidth = 0.6
        dayLuxField.layer.borderColor = TextField_Border_Color.cgColor
        dayLuxField.textAlignment = .center
        dayLuxField.returnKeyType = .done
        dayLuxField.addTarget(self, action: #selector(dayLuxFieldEditChanged), for: .editingChanged)
        dayLuxField.addTarget(self, action: #selector(dayLuxFieldEditEnd), for: .editingDidEnd)
        dayLuxField.delegate = self
        contentView.addSubview(dayLuxField)
        dayLuxField.snp.makeConstraints { make in
            make.left.equalTo(luxLineView.snp.right).offset(SCRXFrom(10))
            make.centerY.width.height.equalTo(nightLuxField)
        }
        
        dayStartsAboveLabel = UILabel(text: "day_starts_above".localizedString, textColor: SubText_Color, fontSize: 10, fontWeight: .light)
        contentView.addSubview(dayStartsAboveLabel)
        dayStartsAboveLabel.snp.makeConstraints { make in
            make.left.equalTo(dayLuxField)
            make.bottom.equalTo(dayLuxField.snp.top).offset(SCRYFrom(-4))
        }
        
        dayLuxUnitLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(dayLuxUnitLabel)
        dayLuxUnitLabel.snp.makeConstraints { make in
            make.left.equalTo(dayLuxField.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(dayLuxField)
        }
        
        syncFailBtn = UIButton(normalImageName: "sync_failed_small", target: self, action: #selector(syncFailBtnAction))
        syncFailBtn.isHidden = true
        contentView.addSubview(syncFailBtn)
        syncFailBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalTo(nightLuxField)
        }
        
        modifyBtn = UIButton(title: "modify".localizedString, titleSize: 12, titleColor: TextBlack_Color, target: self, action: #selector(modifyBtnAction))
        modifyBtn.layer.cornerRadius = SCRYFrom(5)
        modifyBtn.layer.borderColor = TextField_Border_Color.cgColor
        modifyBtn.layer.borderWidth = 0.6
        modifyBtn.isHidden = true
        contentView.addSubview(modifyBtn)
        modifyBtn.snp.makeConstraints { make in
            make.left.equalTo(dayLuxUnitLabel.snp.right).offset(SCRXFrom(11))
            make.height.centerY.equalTo(dayLuxField)
            make.width.equalTo(SCRXFrom(48))
        }
        
        resetBtn = UIButton(normalImageName: "reset", target: self, action: #selector(resetBtnAction))
        resetBtn.isHidden = true
        contentView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        
        let noteArrStr = NSAttributedString(string: "light_sensor_nonsupport_note".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        
        nonsupportNoteLabel = UILabel(text: nil, textColor: Message_Color, fontSize: 13, fontWeight: .light, fit: false)
        nonsupportNoteLabel.numberOfLines = 0
        nonsupportNoteLabel.attributedText = noteArrStr
        nonsupportNoteLabel.isHidden = true
        contentView.addSubview(nonsupportNoteLabel)
        nonsupportNoteLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(12))
        }
    }
    
}

extension ProfileDeviceDayNightLuxViewCell: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//        if string != "" && string.isPureNumandCharacters()
        guard string.isEmpty || string.isPureNumandCharacters() else {
            return false
        }
//        let inputText = (textField.text ?? "") + string
//        guard let lux = Int(inputText) else {
//            return false
//        }
        return true
    }
    
}
