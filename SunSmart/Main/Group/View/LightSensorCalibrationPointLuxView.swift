//
//  LightSensorCalibrationPointLuxView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/12.
//

import UIKit

protocol LightSensorCalibrationPointLuxViewDelegate: AnyObject {
    /// 输入测量值回调
    /// - Parameters:
    ///   - view: view
    ///   - lux: 测量值 为空则未输入
    func view(_ view: LightSensorCalibrationPointLuxView, measuredLightValueEditing lux: Int?)
    
    /// 点击onoff事件
    func sensorCalibrationPointLuxViewOnOffAction(_ view: LightSensorCalibrationPointLuxView)
}

class LightSensorCalibrationPointLuxView: UIView {
    
    var titleLabel: UILabel!
    var measuredLuxField: UITextField!
    private var luxLabel: UILabel!
    var noteLabel: UILabel!
    var onoffBtn: UIButton!
    
    weak var delegate: LightSensorCalibrationPointLuxViewDelegate?
    
    /// 测量值
    var measuredLightValue: Int? {
        get {
            return Int(measuredLuxField.text ?? "")
        }set {
            if let value = newValue {
                measuredLuxField.text = "\(value)"
            }else {
                measuredLuxField.text = nil
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
    
    @objc private func onoffBtnAction() {
        delegate?.sensorCalibrationPointLuxViewOnOffAction(self)
    }
    
    @objc private func measuredLuxFieldEditChanged(sender: UITextField) {
        
        guard let text = sender.text, let value = Int(text) else {
            delegate?.view(self, measuredLightValueEditing: nil)
            return
        }
        delegate?.view(self, measuredLightValueEditing: value)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "Sensor ratio", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(10))
        }
        
        measuredLuxField = UITextField()
        measuredLuxField.attributedPlaceholder = NSAttributedString(string: "measured_light_level".localizedString, attributes: [.foregroundColor: SubText_Color])
        measuredLuxField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        measuredLuxField.textColor = TextBlack_Color
        measuredLuxField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
        measuredLuxField.leftViewMode = .always
        measuredLuxField.layer.cornerRadius = 5
        measuredLuxField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        measuredLuxField.keyboardType = .numberPad
        measuredLuxField.layer.borderWidth = 0.6
        measuredLuxField.returnKeyType = .done
        measuredLuxField.delegate = self
        measuredLuxField.addTarget(self, action: #selector(measuredLuxFieldEditChanged), for: .editingChanged)
        addSubview(measuredLuxField)
        measuredLuxField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(self.snp.centerX).offset(SCRXFrom(10))
            make.height.equalTo(SCRYFrom(32))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        luxLabel = UILabel(text: "LX", textColor: SubText_Color, fontSize: 15, fontWeight: .light)
        addSubview(luxLabel)
        luxLabel.snp.makeConstraints { make in
            make.left.equalTo(measuredLuxField.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(measuredLuxField)
        }
        
        onoffBtn = UIButton(title: "", titleSize: 15, titleWeight: .light, titleColor: Bar_Color)
        onoffBtn.layer.cornerRadius = SCRYFrom(5)
        onoffBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.3).cgColor
        onoffBtn.layer.borderWidth = 0.6
        onoffBtn.addTarget(self, action: #selector(onoffBtnAction), for: .touchUpInside)
        addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(measuredLuxField)
            make.width.equalTo(SCRXFrom(72))
            make.height.equalTo(SCRYFrom(32))
        }
        
        noteLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fit: false)
        noteLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        noteLabel.numberOfLines = 0
        addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(measuredLuxField)
            make.right.equalTo(onoffBtn)
            make.top.equalTo(measuredLuxField.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-25))
        }
        
    }
    
    
}

extension LightSensorCalibrationPointLuxView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return textField.resignFirstResponder()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if !string.isPureNumandCharacters() && string != "" {
            return false
        }
        return true
    }
    
}
