//
//  DeviceParameterSliderViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/3.
//

import UIKit

protocol DeviceParameterSliderViewCellDelegate: AnyObject {
    
    /// 修改滑条数值
    func cell(_ cell: DeviceParameterSliderViewCell, sliderValueChange value: Int)
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterSliderViewCell, parameterEnableStateChanged enable: Bool)
    
    /// 恢复
    func sensitivityViewCellResetAction(_ cell: DeviceParameterSliderViewCell)
    
}

class DeviceParameterSliderViewCell: UITableViewCell {

    private var containerView: UIView!
    var titleLabel: UILabel!
    var enableSwitch: UISwitch!
    private var sliderView: UIView!
    /// 增加
    private var addBtn: UIButton!
    /// 减少
    private var minusBtn: UIButton!
    /// 数值
    var valueLabel: UILabel!
    /// 滑条
    var slider: CustomDeviceSlider!
    /// 提示信息
    var noteLabel: UILabel!
    
    private var resetBtn: UIButton!
    
    weak var delegate: DeviceParameterSliderViewCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
//        selectionStyle = .none
//        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .clear
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func enableSwitchValueChanged() {
        updateParameterEnable(enable: enableSwitch.isOn)
        
        delegate?.cell(self, parameterEnableStateChanged: enableSwitch.isOn)
    }
    
    @objc private func addBtnClick() {
        
        slider.value = min(slider.value + 1, slider.maximumValue)
        delegate?.cell(self, sliderValueChange: Int(slider.value))
    }
    
    @objc private func minusBtnClick() {
        slider.value = max(slider.value - 1, slider.minimumValue)
        delegate?.cell(self, sliderValueChange: Int(slider.value))
    }
    
    @objc private func resetBtnAction() {
        delegate?.sensitivityViewCellResetAction(self)
    }
    
    func updateParameterEnable(enable: Bool) {
        enableSwitch.isOn = enable
        
        resetBtn.isHidden = !enable
        if enable {
            
            noteLabel.isHidden = false
            sliderView.isHidden = false
            
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
            }
            
            noteLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(sliderView)
                make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
            }
        }else {
            
            noteLabel.isHidden = true
            sliderView.isHidden = true
            
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24))
                make.bottom.equalTo(SCRYFrom(-23))
            }
            
            noteLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(sliderView)
                make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            }
        }
    }
    
    private func setupUI() {
        
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
        titleLabel = UILabel(text: "absolute_sensitivity".localizedString + ":", textColor: ImportantText_Color, fontSize: 14)
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24)).priority(.high)
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        containerView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        resetBtn = UIButton(title: "reset".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(resetBtnAction))
        resetBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(11.5), bottom: 0, right: SCRXFrom(11.5))
        resetBtn.layer.cornerRadius = SCRYFrom(14)
        resetBtn.layer.borderWidth = 0.5
        resetBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        resetBtn.isHidden = true
        containerView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(enableSwitch.snp.left).offset(SCRXFrom(-24))
            make.centerY.equalTo(enableSwitch)
            make.height.equalTo(SCRYFrom(28))
        }
        
        sliderView = UIView()
        containerView.addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(30))
            make.height.equalTo(SCRYFrom(69))
        }
        
        addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
        sliderView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-6))
        }
        
        minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
        sliderView.addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalTo(addBtn)
        }
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.minimumTrackTintColor = Slider_Color
        slider.maximumTrackTintColor = RGB(229, 229, 229)
        slider.layer.cornerRadius = 2
        slider.delegate = self
        sliderView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(45))
            make.right.equalTo(SCRXFrom(-45))
            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        valueLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        sliderView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
//            make.width.greaterThanOrEqualTo(SCRXFrom(30))
        }
        
        noteLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        containerView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(sliderView)
            make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
        }
        
    }
    
}

extension DeviceParameterSliderViewCell: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        delegate?.cell(self, sliderValueChange: Int(value))
    }
}
