//
//  DeviceRatedPowerCalibrationSetSeparatelyViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/6.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceRatedPowerCalibrationSetSeparatelyViewCellDelegate: AnyObject {
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, testShowStateChange show: Bool)
    
    func calibrationCellDimSaveAction(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell)
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, calibrationAction inputValue: UInt32)
    
    func calibrationCellTestGetAction(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell)
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, lightnessValueChanged lightness: Int)
    
    func calibrationCellReSyncAction(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell)
    
    func cell(_ cell: DeviceRatedPowerCalibrationSetSeparatelyViewCell, identifyDevice device: Node)
}

class DeviceRatedPowerCalibrationSetSeparatelyViewCell: UITableViewCell {

    private var containerView: UIView!
    private var calibrationView: UIView!
    private var deviceImageView: UIImageView!
    private var nameLabel: UILabel!
    private var dimSaveBtn: UIButton!
    private var unfoldBtn: UIButton!
    private var arrowImageView: UIImageView!
    private var inputValueLabel: UILabel!
    private var inputValueField: UITextField!
    private var calibrationValueLabel: UILabel!
    private var calibrationValueField: UITextField!
    private var calibrationBtn: UIButton!
    private var syncFailBtn: UIButton!
    
    private var testView: UIView!
    private var testLabel: UILabel!
    private var getRatedPowerBtn: UIButton!
    private var testValueBtn: UIButton!
    private var lightnessLabel: UILabel!
    private var lightnessMinusBtn: UIButton!
    private var lightnessAddBtn: UIButton!
    private var lightnessSlider: CustomDeviceSlider!
    
    private let maxIntegerDigits = 7
    
    weak var delegate: DeviceRatedPowerCalibrationSetSeparatelyViewCellDelegate?
    
    var device: Node! {
        didSet {
            
            deviceImageView.image = UIImage(named: device.iconName)
            nameLabel.text = device.name
            
            
            if let inputPower = device.inputPower {
                inputValueField.text = String(format: "%.2f", Double(inputPower) / 100.0)
            }else {
                inputValueField.text = nil
            }
            if let calibrationRatedPower = device.calibrationRatedPower {
                inputValueField.placeholder = String(format: "%.2f", Double(calibrationRatedPower) / 100.0)
            }else {
                inputValueField.placeholder = "e.g., 250.25"
            }
            
            if let ratedPower = device.calibrationCollectRatedPower {
                calibrationValueField.placeholder = String(format: "%.2f", Double(ratedPower) / 100.0)
            }else  {
                calibrationValueField.placeholder = "--"
            }
            
            switch device.powerCalibrateState {
            case .none:
                containerView.isUserInteractionEnabled = true
                testView.isUserInteractionEnabled = true
                getRatedPowerBtn.imageView?.layer.removeAnimation(forKey: "loading")
                getRatedPowerBtn.setImage(nil, for: .normal)
                getRatedPowerBtn.setTitle("get".localizedString, for: .normal)
                
                dimSaveBtn.imageView?.layer.removeAnimation(forKey: "loading")
                dimSaveBtn.setImage(nil, for: .normal)
                dimSaveBtn.setTitle("Dim&Save".localizedString.localizedString, for: .normal)
                
            case .dimSave:
                containerView.isUserInteractionEnabled = false
                dimSaveBtn.setImage(UIImage(named: "sync_loading_small"), for: .normal)
                dimSaveBtn.imageView?.layer.addRotationAnimation(duration: 1, repeatCount: 999, animationKey: "loading")
                dimSaveBtn.setTitle(nil, for: .normal)
            case .powerGet:
                
                testView.isUserInteractionEnabled = false
                getRatedPowerBtn.setImage(UIImage(named: "loading_small_white"), for: .normal)
                getRatedPowerBtn.imageView?.layer.addRotationAnimation(duration: 1, repeatCount: 999, animationKey: "loading")
                getRatedPowerBtn.setTitle(nil, for: .normal)
            }
            
            syncFailBtn.isHidden = device.powerCalibrateError == nil
            
            lightnessSlider.value = Float(device.powerTestLightness)
            lightnessLabel.text = "\(device.powerTestLightness)%"
            
            if device.calibrationRatedPower != nil {
                getRatedPowerBtn.isEnabled = true
                getRatedPowerBtn.backgroundColor = Bar_Color
            }else {
                getRatedPowerBtn.isEnabled = false
                getRatedPowerBtn.backgroundColor = Bar_Color.withAlphaComponent(0.5)
            }
            if let testCurrentPower = device.testCurrentPower {
                testValueBtn.setTitle(String(format: "%.2f", Double(testCurrentPower) / 100.0), for: .normal)
            }else {
                testValueBtn.setTitle("--", for: .normal)
            }
            
            if device.unfold {
                arrowImageView.image = UIImage(named: "arrow_up_black")
            }else {
                arrowImageView.image = UIImage(named: "arrow_down_black")
            }
            
            updateTestViewUI()
            updateCalibrateBtnState()
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateTestViewUI() {
        
        testView.isHidden = !device.unfold
        testView.snp.updateConstraints { make in
            make.height.equalTo(device.unfold ? SCRYFrom(122) : 0)
        }
        
    }
    
    private func updateCalibrateBtnState() {
        guard let text = inputValueField.text, let value = Double(text), Int(value * 100) < UInt32.max else {
            calibrationBtn.isEnabled = false
            calibrationBtn.backgroundColor = Bar_Color.withAlphaComponent(0.5)
            return
        }
        calibrationBtn.isEnabled = true
        calibrationBtn.backgroundColor = Bar_Color
        print(UInt32(value * 100))
        device.inputPower = UInt32(value * 100)
    }
    
    // MARK: - Action
    
    @objc private func dimSaveBtnAction() {
        delegate?.calibrationCellDimSaveAction(self)
    }
    
    @objc private func syncFailBtnAction() {
        delegate?.calibrationCellReSyncAction(self)
    }
    
    @objc private func calibrationBtnAction() {
        guard let text = inputValueField.text, let value = Double(text) else { return }
        delegate?.cell(self, calibrationAction: UInt32(value * 100))
    }
    
    @objc private func getRatedPowerBtnAction() {
        delegate?.calibrationCellTestGetAction(self)
    }
    
    @objc private func lightnessAddBtnAction() {
        lightnessSlider.value += 1
        lightnessLabel.text = "\(Int(lightnessSlider.value))%"
        
        delegate?.cell(self, lightnessValueChanged: Int(lightnessSlider.value))
    }
    
    @objc private func lightnessMinusBtnAction() {
        lightnessSlider.value -= 1
        lightnessLabel.text = "\(Int(lightnessSlider.value))%"
        delegate?.cell(self, lightnessValueChanged: Int(lightnessSlider.value))
    }
    
    @objc private func unfoldBtnAction() {
        delegate?.cell(self, testShowStateChange: !device.unfold)
    }
    
    @objc private func inputValueFieldEditChanged() {
        updateCalibrateBtnState()
    }
    
    @objc private func deviceImageViewTapAction() {
        delegate?.cell(self, identifyDevice: device)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview().priority(.high)
            make.bottom.equalTo(SCRYFrom(-12)).priority(.high)
        }
        
        calibrationView = UIView()
        containerView.addSubview(calibrationView)
        calibrationView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview().priority(.high)
            make.height.equalTo(SCRYFrom(108))
        }
        
        deviceImageView = UIImageView()
        deviceImageView.isUserInteractionEnabled = true
        deviceImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deviceImageViewTapAction)))
        calibrationView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.top.equalTo(SCRYFrom(12))
            make.width.height.equalTo(30)
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_down_black"))
        calibrationView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.centerY.equalTo(deviceImageView)
            make.right.equalTo(SCRXFrom(-8))
            make.width.height.equalTo(30)
        }
        
        dimSaveBtn = UIButton(title: "Dim&Save".localizedString, titleSize: 12, titleWeight: .light, titleColor: ImportantText_Color, target: self, action: #selector(dimSaveBtnAction))
        dimSaveBtn.backgroundColor = Background_Color
        dimSaveBtn.layer.cornerRadius = SCRYFrom(14)
        dimSaveBtn.layer.borderWidth = 0.5
        dimSaveBtn.layer.borderColor = Border_Color.cgColor
        calibrationView.addSubview(dimSaveBtn)
        dimSaveBtn.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(arrowImageView)
            make.width.equalTo(SCRXFrom(68))
            make.height.equalTo(SCRYFrom(30))
        }
        
        
        nameLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 15, fontWeight: .light)
        calibrationView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(deviceImageView)
            make.right.equalTo(dimSaveBtn.snp.left).offset(SCRXFrom(-30))
        }
        
        inputValueField = UITextField()
        inputValueField.textAlignment = .center
        inputValueField.textColor = ImportantText_Color
        inputValueField.font = UIFont.systemFont(ofSize: FontFit(12))
//        inputValueField.placeholder = "e.g., 250.25"
        inputValueField.layer.cornerRadius = SCRYFrom(5)
        inputValueField.layer.borderWidth = 0.5
        inputValueField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        inputValueField.returnKeyType = .done
        inputValueField.keyboardType = .decimalPad
        inputValueField.delegate = self
        inputValueField.addTarget(self, action: #selector(inputValueFieldEditChanged), for: .editingChanged)
        calibrationView.addSubview(inputValueField)
        inputValueField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(deviceImageView.snp.bottom).offset(SCRYFrom(24))
            make.width.equalTo(SCRXFrom(72))
            make.height.equalTo(SCRYFrom(28))
        }
        
        inputValueLabel = UILabel(text: "input_value".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        calibrationView.addSubview(inputValueLabel)
        inputValueLabel.snp.makeConstraints { make in
            make.centerX.equalTo(inputValueField)
            make.bottom.equalTo(inputValueField.snp.top).offset(SCRYFrom(-4))
        }
        
        let inputValueUnitLabel = UILabel(text: "W", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        calibrationView.addSubview(inputValueUnitLabel)
        inputValueUnitLabel.snp.makeConstraints { make in
            make.centerY.equalTo(inputValueField)
            make.left.equalTo(inputValueField.snp.right).offset(SCRXFrom(4))
        }
        
        let inputLineView = UIView()
        inputLineView.backgroundColor = Message_Color
        calibrationView.addSubview(inputLineView)
        inputLineView.snp.makeConstraints { make in
            make.left.equalTo(inputValueUnitLabel.snp.right).offset(SCRXFrom(10))
            make.centerY.equalTo(inputValueUnitLabel)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(12))
        }
        
        calibrationValueField = UITextField()
        calibrationValueField.textAlignment = .center
        calibrationValueField.textColor = ImportantText_Color
        calibrationValueField.font = UIFont.systemFont(ofSize: FontFit(12))
        calibrationValueField.placeholder = "--"
        calibrationValueField.layer.cornerRadius = SCRYFrom(5)
        calibrationValueField.layer.borderWidth = 0.5
        calibrationValueField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        calibrationValueField.backgroundColor = RGB(248, 248, 248)
//        calibrationValueField.returnKeyType = .done
//        calibrationValueField.delegate = self
        calibrationValueField.isEnabled = false
        calibrationView.addSubview(calibrationValueField)
        calibrationValueField.snp.makeConstraints { make in
            make.left.equalTo(inputLineView.snp.right).offset(SCRXFrom(10))
            make.centerY.width.height.equalTo(inputValueField)
        }
        
        calibrationValueLabel = UILabel(text: "calibration_value".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        calibrationView.addSubview(calibrationValueLabel)
        calibrationValueLabel.snp.makeConstraints { make in
            make.centerX.equalTo(calibrationValueField)
            make.bottom.equalTo(calibrationValueField.snp.top).offset(SCRYFrom(-4))
        }
        
        let calibrationValueUnitLabel = UILabel(text: "W", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        calibrationView.addSubview(calibrationValueUnitLabel)
        calibrationValueUnitLabel.snp.makeConstraints { make in
            make.centerY.equalTo(calibrationValueField)
            make.left.equalTo(calibrationValueField.snp.right).offset(SCRXFrom(4))
        }
        
        syncFailBtn = UIButton(normalImageName: "sync_failed", target: self, action: #selector(syncFailBtnAction))
        calibrationView.addSubview(syncFailBtn)
        syncFailBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(inputValueField)
        }
        
        calibrationBtn = UIButton(title: "calibrate".localizedString, titleSize: 12, titleWeight: .light, titleColor: .white, target: self, action: #selector(calibrationBtnAction))
        calibrationBtn.backgroundColor = Bar_Color.withAlphaComponent(0.5)
        calibrationBtn.layer.cornerRadius = SCRYFrom(15)
        calibrationView.addSubview(calibrationBtn)
        calibrationBtn.snp.makeConstraints { make in
            make.right.equalTo(syncFailBtn.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(syncFailBtn)
            make.width.equalTo(SCRXFrom(68))
            make.height.equalTo(SCRYFrom(30))
        }
        
        unfoldBtn = UIButton(target: self, action: #selector(unfoldBtnAction))
        calibrationView.addSubview(unfoldBtn)
        unfoldBtn.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.left.equalTo(dimSaveBtn.snp.right)
            make.bottom.equalTo(syncFailBtn.snp.top).offset(SCRYFrom(-12))
        }
        
        testView = UIView()
        testView.layer.cornerRadius = SCRYFrom(10)
        testView.backgroundColor = RGB(236, 242, 255)
        testView.isHidden = true
        containerView.addSubview(testView)
        testView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(calibrationView.snp.bottom).priority(.high)
            make.height.equalTo(0)
            make.bottom.equalToSuperview().priority(.high)
//            make.height.equalTo(SCRYFrom(122))
        }
        
        testLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        let attStr = NSMutableAttributedString(string: "\("test".localizedString): " + "calibration_test_note".localizedString)
        attStr.addAttributes([.foregroundColor: ImportantText_Color], range: (attStr.string as NSString).range(of: "\("test".localizedString):"))
        testLabel.attributedText = attStr
        testView.addSubview(testLabel)
        testLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(6))
            make.right.equalTo(SCRXFrom(-16))
        }
        
        getRatedPowerBtn = UIButton(title: "get".localizedString, titleSize: 12, titleColor: .white, target: self, action: #selector(getRatedPowerBtnAction))
        getRatedPowerBtn.layer.cornerRadius = SCRYFrom(5)
        getRatedPowerBtn.backgroundColor = Bar_Color
        testView.addSubview(getRatedPowerBtn)
        getRatedPowerBtn.snp.makeConstraints { make in
            make.right.equalTo(testView.snp.centerX).offset(SCRXFrom(-38))
            make.top.equalTo(testLabel.snp.bottom).offset(SCRYFrom(12))
            make.width.equalTo(SCRXFrom(72))
            make.height.equalTo(SCRYFrom(28))
        }
        
        testValueBtn = UIButton(title: "--", titleSize: 12, titleColor: ImportantText_Color)
        testValueBtn.layer.cornerRadius = SCRYFrom(5)
        testValueBtn.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        testValueBtn.layer.borderWidth = 0.5
        testValueBtn.backgroundColor = .white
        testValueBtn.isUserInteractionEnabled = false
        testView.addSubview(testValueBtn)
        testValueBtn.snp.makeConstraints { make in
            make.left.equalTo(testView.snp.centerX).offset(SCRXFrom(22))
            make.centerY.width.height.equalTo(getRatedPowerBtn)
        }
        
        let testValueUnitLabel = UILabel(text: "W", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        testView.addSubview(testValueUnitLabel)
        testValueUnitLabel.snp.makeConstraints { make in
            make.centerY.equalTo(testValueBtn)
            make.left.equalTo(testValueBtn.snp.right).offset(SCRXFrom(4))
        }
        
        
        lightnessLabel = UILabel(text: "50%", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        testView.addSubview(lightnessLabel)
        lightnessLabel.snp.makeConstraints { make in
            make.centerY.equalTo(testValueUnitLabel)
            make.right.equalTo(SCRXFrom(-15))
        }

        lightnessAddBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(lightnessAddBtnAction))
        testView.addSubview(lightnessAddBtn)
        lightnessAddBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-15))
            make.bottom.equalTo(SCRYFrom(-18))
        }
        
        lightnessMinusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(lightnessMinusBtnAction))
        testView.addSubview(lightnessMinusBtn)
        lightnessMinusBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(15))
            make.bottom.equalTo(lightnessAddBtn)
        }
        
        lightnessSlider = CustomDeviceSlider()
        lightnessSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        lightnessSlider.minimumTrackTintColor = Slider_Color
        lightnessSlider.maximumTrackTintColor = RGB(229, 229, 229)
        lightnessSlider.layer.cornerRadius = 2
        lightnessSlider.minimumValue = 0
        lightnessSlider.maximumValue = 100
        lightnessSlider.value = 50
        lightnessSlider.throttle = true
        lightnessSlider.delegate = self
        testView.addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            make.left.equalTo(lightnessMinusBtn.snp.right).offset(SCRXFrom(17))
            make.right.equalTo(lightnessAddBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(lightnessMinusBtn)
            make.height.equalTo(SCRYFrom(40))
        }
        
        
    }
    
    
}

extension DeviceRatedPowerCalibrationSetSeparatelyViewCell: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//        if !string.isPureNumandCharacters() && string != "" {
//            return false
//        }
//        return true
        
        guard let currentText = textField.text else { return true }
        
        // 允许删除操作
        if string.isEmpty { return true }
        
        // 如果已经包含小数点且尝试输入另一个小数点，拒绝
        if string == ".", currentText.contains(".") {
            return false
        }
        
        // 如果当前没有小数点且尝试输入小数点，检查整数部分长度
        if string == ".", !currentText.contains(".") {
            let integerPart = currentText
            return integerPart.count <= maxIntegerDigits
        }
        
        // 构建新文本
        let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
        
        // 验证新文本是否符合数字格式
        guard newText.isValidDecimal(maxIntegerDigits: maxIntegerDigits, maxFractionDigits: 2) else {
            return false
        }
        
        return true
        
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        
        if let text = textField.text, let power = Double(text) {
            textField.text = String(format: "%.2f", power)
        }
        
        return true
    }
    
}

extension DeviceRatedPowerCalibrationSetSeparatelyViewCell: CustomDeviceSliderDelegate {
    
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        lightnessLabel.text = "\(Int(value))%"
    }
    
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        delegate?.cell(self, lightnessValueChanged: Int(value))
    }
    
}
