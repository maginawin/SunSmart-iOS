//
//  ProfileLightSensorTemplateController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/22.
//

import UIKit
import NordicSigMeshSDK

class ProfileLightSensorTemplateController: UIViewController {

    private var bottomView: DeviceBottomBtnView!
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var nameTitleLabel: UILabel!
    private var nameField: UITextField!
    
    private var nightDayTitleLabel: UILabel!
    private var nightDayView: UIView!
    private var nightLabel: UILabel!
    private var nightLuxField: UITextField!
    private var nightLuxUnitLabel: UILabel!
    private var nightLuxTipLabel: UILabel!
    private var dayLabel: UILabel!
    private var dayLuxField: UITextField!
    private var dayLuxUnitLabel: UILabel!
    private var dayLuxTipLabel: UILabel!
    
    private var appliedDeviceTitleLabel: UILabel!
    private var appliedDeviceView: UIView!
    private var appliedDevicesLabel: UILabel!
    private var appliedDeviceArrowImageView: UIImageView!
    
    let canAppliedDevices: [Node]
    
    var template: ProfileLightSensorTemplate?
    
    private var appliedDevices: [Node] = []
    
    init(canAppliedDevices: [Node]) {
        self.canAppliedDevices = canAppliedDevices
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        setupUI()
        
        if let template = self.template {
            title = "template_detail".localizedString
            nameField.text = template.name
            nightLuxField.text = "\(template.nightStartsBelowLux)"
            dayLuxField.text = "\(template.dayStartsAboveLux)"
            appliedDevices = template.devices
            
            bottomView.showEditUI()
        }else {
            title = "create_light_sensor_template".localizedString
            bottomView.showCreateUI()
        }
        
        if canAppliedDevices.count > 0 {
            if appliedDevices.count > 0 {
                appliedDevicesLabel.text = appliedDevices.map({ $0.name ?? "" }).joined(separator: ",")
            }else {
                appliedDevicesLabel.text = "no_device_selected".localizedString
            }
        }else {
            appliedDevicesLabel.text = "no_members".localizedString
        }
        
        updateBottomViewUI()
        
    }
    
    @objc private func updateBottomViewUI() {
        
        if let name = nameField.text, !name.isAllInputTextEmpty() {
            bottomView.saveBtn.isEnabled = true
            bottomView.createBtn.isEnabled = true
        }else {
            bottomView.saveBtn.isEnabled = false
            bottomView.createBtn.isEnabled = false
        }
    }
    
    @objc private func saveAction() {
        
        guard let name = nameField.text, let nightLuxStr = nightLuxField.text, let nightLux = Int(nightLuxStr), let dayLuxStr = dayLuxField.text, let dayLux = Int(dayLuxStr) else {
            return
        }
        
        // lux必须小于65535
        let luxRange: ClosedRange<Int> = Int(UInt16.min)...Int(UInt16.max)
        
        guard luxRange.contains(nightLux) else {
            nightLuxTipLabel.text = "\("limit_range".localizedString) 0~5000lux"
            nightLuxField.layer.borderColor = Red_Color.cgColor
            return
        }
        guard luxRange.contains(dayLux) else {
            dayLuxTipLabel.text = "\("limit_range".localizedString) 0~5000lux"
            dayLuxField.layer.borderColor = Red_Color.cgColor
            return
        }
        
        // 晚上必须小于白天lux
        guard nightLux < dayLux else {
            
            nightLuxTipLabel.text = "profile_night_startsbelow_less_day".localizedString
            nightLuxField.layer.borderColor = Red_Color.cgColor
            dayLuxTipLabel.text = "profile_night_startsbelow_greater_day".localizedString
            dayLuxField.layer.borderColor = Red_Color.cgColor
            return
        }
        // 白天lux-晚上lux必须大于等于5
        guard dayLux - nightLux >= 5 else {
            
            nightLuxTipLabel.text = "profile_night_startsbelow_less_day_threshold".localizedString
            nightLuxField.layer.borderColor = Red_Color.cgColor
            dayLuxTipLabel.text = "profile_night_startsbelow_greater_day_threshold".localizedString
            dayLuxField.layer.borderColor = Red_Color.cgColor
            return
        }
        
        
        
    }
    
    @objc private func deleteAction() {
        
        
    }
    
    @objc private func nightLuxFieldEditChanged(sender: UITextField) {
        
        sender.layer.borderColor = TextField_Border_Color.cgColor
        nightLuxTipLabel.text = nil
    }
    
    @objc private func dayLuxFieldEditChanged(sender: UITextField) {
        sender.layer.borderColor = TextField_Border_Color.cgColor
        dayLuxTipLabel.text = nil
    }
    
    private func setupUI() {
        
        bottomView = DeviceBottomBtnView()
        bottomView.createBtn.setTitle("save".localizedString, for: .normal)
        bottomView.createBtn.setTitleColor(Title_Color, for: .normal)
        bottomView.createBtn.setTitleColor(Title_Color.withAlphaComponent(0.5), for: .disabled)
        bottomView.createBtn.addTarget(self, action: #selector(saveAction), for: .touchUpInside)
        bottomView.deleteBtn.addTarget(self, action: #selector(deleteAction), for: .touchUpInside)
        bottomView.saveBtn.setTitleColor(Title_Color, for: .normal)
        bottomView.saveBtn.setTitleColor(Title_Color.withAlphaComponent(0.5), for: .disabled)
        bottomView.saveBtn.addTarget(self, action: #selector(saveAction), for: .touchUpInside)
//        bottomView.showCreateUI()
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaTopHeight + SCRYFrom(56))
        }
        
        scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.enableKeyboardDismissal()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        nameTitleLabel = UILabel(text: "name".localizedString, textColor: Chart_Text_Color, fontSize: 15)
        contentView.addSubview(nameTitleLabel)
        nameTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(9))
            make.left.equalTo(SCRXFrom(20))
        }
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = UIFont.systemFont(ofSize: FontFit(15), weight: .light)
        nameField.layer.cornerRadius = SCRYFrom(5)
        nameField.layer.borderColor = TextField_Border_Color.cgColor
        nameField.layer.borderWidth = 0.6
        nameField.backgroundColor = .white
        nameField.clearButtonMode = .whileEditing
        nameField.rightViewMode = .whileEditing
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 0))
        nameField.leftViewMode = .always
        nameField.addTarget(self, action: #selector(updateBottomViewUI), for: .editingChanged)
        nameField.returnKeyType = .done
        nameField.delegate = self
        contentView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(nameTitleLabel)
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(nameTitleLabel.snp.bottom).offset(SCRYFrom(9))
            make.height.equalTo(SCRYFrom(40))
        }
        
        nightDayTitleLabel = UILabel(text: "nightday_illuminance_threshold".localizedString, textColor: Chart_Text_Color, fontSize: 15)
        contentView.addSubview(nightDayTitleLabel)
        nightDayTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(nameField)
        }
        
        nightDayView = UIView()
        nightDayView.layer.cornerRadius = SCRYFrom(10)
        nightDayView.backgroundColor = .white
        contentView.addSubview(nightDayView)
        nightDayView.snp.makeConstraints { make in
            make.left.right.equalTo(nameField)
            make.top.equalTo(nightDayTitleLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(100))
        }
        
        nightLabel = UILabel(text: "night_starts_below".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        nightDayView.addSubview(nightLabel)
        nightLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.top.equalTo(SCRYFrom(20))
        }
        
        nightLuxUnitLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        nightDayView.addSubview(nightLuxUnitLabel)
        nightLuxUnitLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(nightLabel)
        }
        
        nightLuxField = UITextField()
        nightLuxField.textColor = TextBlack_Color
        nightLuxField.font = UIFont.systemFont(ofSize: FontFit(12))
        nightLuxField.layer.cornerRadius = SCRYFrom(5)
        nightLuxField.backgroundColor = .white
        nightLuxField.layer.borderColor = TextField_Border_Color.cgColor
        nightLuxField.layer.borderWidth = 0.6
        nightLuxField.keyboardType = .numberPad
        nightLuxField.addTarget(self, action: #selector(nightLuxFieldEditChanged), for: .editingChanged)
        nightLuxField.returnKeyType = .done
        nightLuxField.textAlignment = .center
        nightLuxField.delegate = self
        contentView.addSubview(nightLuxField)
        nightLuxField.snp.makeConstraints { make in
            make.right.equalTo(nightLuxUnitLabel.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(nightLabel)
            make.width.equalTo(SCRXFrom(72))
            make.height.equalTo(SCRYFrom(28))
        }
        
        nightLuxTipLabel = UILabel(text: nil, textColor: Error_Red_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(nightLuxTipLabel)
        nightLuxTipLabel.snp.makeConstraints { make in
            make.right.equalTo(nightLuxUnitLabel)
            make.top.equalTo(nightLuxField.snp.bottom)
        }
        
        dayLabel = UILabel(text: "day_starts_above".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        nightDayView.addSubview(dayLabel)
        dayLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.top.equalTo(nightLuxField.snp.bottom).offset(SCRYFrom(22))
        }
        
        dayLuxUnitLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        nightDayView.addSubview(dayLuxUnitLabel)
        dayLuxUnitLabel.snp.makeConstraints { make in
            make.right.equalTo(nightLuxUnitLabel)
            make.centerY.equalTo(dayLabel)
        }
        
        dayLuxField = UITextField()
        dayLuxField.textColor = TextBlack_Color
        dayLuxField.font = UIFont.systemFont(ofSize: FontFit(12))
        dayLuxField.layer.cornerRadius = SCRYFrom(5)
        dayLuxField.backgroundColor = .white
        dayLuxField.layer.borderColor = TextField_Border_Color.cgColor
        dayLuxField.layer.borderWidth = 0.6
        dayLuxField.keyboardType = .numberPad
        dayLuxField.addTarget(self, action: #selector(dayLuxFieldEditChanged), for: .editingChanged)
        dayLuxField.returnKeyType = .done
        dayLuxField.textAlignment = .center
        dayLuxField.delegate = self
        contentView.addSubview(dayLuxField)
        dayLuxField.snp.makeConstraints { make in
            make.right.equalTo(dayLuxUnitLabel.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(dayLabel)
            make.width.height.equalTo(nightLuxField)
        }
        
        dayLuxTipLabel = UILabel(text: nil, textColor: Error_Red_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(dayLuxTipLabel)
        dayLuxTipLabel.snp.makeConstraints { make in
            make.right.equalTo(dayLuxUnitLabel)
            make.top.equalTo(dayLuxField.snp.bottom)
        }
        
        appliedDeviceTitleLabel = UILabel(text: "applied_to_device".localizedString, textColor: Chart_Text_Color, fontSize: 15)
        contentView.addSubview(appliedDeviceTitleLabel)
        appliedDeviceTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(nightDayTitleLabel)
            make.top.equalTo(nightDayView.snp.bottom).offset(SCRYFrom(16))
        }
        
        appliedDeviceView = UIView()
        appliedDeviceView.backgroundColor = .white
        appliedDeviceView.layer.cornerRadius = SCRYFrom(5)
        appliedDeviceView.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        appliedDeviceView.layer.borderWidth = 0.6
        contentView.addSubview(appliedDeviceView)
        appliedDeviceView.snp.makeConstraints { make in
            make.left.right.equalTo(nightDayView)
            make.top.equalTo(appliedDeviceTitleLabel.snp.bottom).offset(SCRYFrom(9))
            make.height.equalTo(SCRYFrom(40))
            make.bottom.equalToSuperview()
        }
        
        appliedDevicesLabel = UILabel(text: "", textColor: Chart_Text_Color, fontSize: 14, fontWeight: .light)
        appliedDeviceView.addSubview(appliedDevicesLabel)
        appliedDevicesLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-45))
        }
        
        appliedDeviceArrowImageView = UIImageView(image: UIImage(named: "arrow_light_right"))
        appliedDeviceView.addSubview(appliedDeviceArrowImageView)
        appliedDeviceArrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-2))
            make.centerY.equalToSuperview()
        }
            
    }
    
    
    

}

extension ProfileLightSensorTemplateController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard string.isEmpty || string.isPureNumandCharacters() else {
            return false
        }
        
        return true
    }
}
