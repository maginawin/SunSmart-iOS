//
//  DeviceParameterAbsoluteSensitivityViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/17.
//

import UIKit

protocol DeviceParameterAbsoluteSensitivityViewCellDelegate: AnyObject {
    
    /// 修改灵敏度范围
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, changeSensitivityRange range: ClosedRange<Double>)
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, parameterEnableStateChanged enable: Bool)
    
    /// 恢复
    func sensitivityViewCellResetAction(_ cell: DeviceParameterAbsoluteSensitivityViewCell)
    
}

class DeviceParameterAbsoluteSensitivityViewCell: UITableViewCell {
    
    private var containerView: UIView!
    private var titleLabel: UILabel!
    private var enableSwitch: UISwitch!
    private var sliderView: UIView!
    /// 增加
    private var addBtn: UIButton!
    /// 减少
    private var minusBtn: UIButton!
    /// 最小值
    var minLabel: UILabel!
    /// 最大值
    var maxLabel: UILabel!
    /// 滑条
    var slider: RangeSlider!
    /// 提示信息
    private var noteLabel: UILabel!
    
    private var resetBtn: UIButton!
    
    weak var delegate: DeviceParameterAbsoluteSensitivityViewCellDelegate?

    /// 选择的范围
    var selectRange: ClosedRange<Double> = 0...80 {
        didSet {
            slider.lowerValue = selectRange.lowerBound
            slider.upperValue = selectRange.upperBound
            updateSliderUI()
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
//        layer.cornerRadius = SCRYFrom(10)
//        backgroundColor = .white
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateSliderUI()
    }
    
    @objc private func enableSwitchValueChanged() {
        updateParameterEnable(enable: enableSwitch.isOn)
        
        delegate?.cell(self, parameterEnableStateChanged: enableSwitch.isOn)
    }
    
    @objc private func addBtnClick() {
        
        if slider.lowerThumbLayer.highlighted {
            slider.lowerValue = min(slider.lowerValue + 0.1, slider.maximumValue)
        }else {
            slider.upperValue = min(slider.upperValue + 0.1, slider.maximumValue)
        }
        updateSliderUI()
        delegate?.cell(self, changeSensitivityRange: Double(slider.lowerValue)...Double(slider.upperValue))
    }
    
    @objc private func minusBtnClick() {
        if slider.lowerThumbLayer.highlighted {
            slider.lowerValue = max(slider.lowerValue - 0.1, slider.minimumValue)
        }else {
            slider.upperValue = max(slider.upperValue - 0.1, slider.minimumValue)
        }
        updateSliderUI()
        delegate?.cell(self, changeSensitivityRange: Double(slider.lowerValue)...Double(slider.upperValue))
    }
    
    @objc private func sliderValueChanged() {
        updateSliderUI()
        delegate?.cell(self, changeSensitivityRange: Double(slider.lowerValue)...Double(slider.upperValue))
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
                make.top.equalTo(SCRYFrom(24)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-23)).priority(.high)
            }
            
            noteLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(sliderView)
                make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            }
        }
    }
    
    private func updateSliderUI() {
        
        minLabel.text = "\(slider.lowerValue.toSimplifyStr(maxDigits: 1))%"
        maxLabel.text = "\(slider.upperValue.toSimplifyStr(maxDigits: 1))%"
        guard slider.frame != .zero else {
            return
        }
        let minProgress = (slider.lowerValue - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)
        let maxProgress = (slider.upperValue - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)
        
        minLabel.snp.updateConstraints { make in
            let x = 24 + (slider.width - 44) * CGFloat(minProgress)
            make.centerX.equalTo(slider.snp.left).offset(x)
        }
        maxLabel.snp.updateConstraints { make in
            let x = 24 + (slider.width - 44) * CGFloat(maxProgress)
            make.centerX.equalTo(slider.snp.left).offset(x)
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
        
        slider = RangeSlider()
        slider.trackHighlightTintColor = Slider_Color
        slider.trackHighlightDisableTintColor = Slider_Color.withAlphaComponent(0.5)
        slider.trackTintColor = RGB(229, 229, 229)
        slider.thumbDisableTintColor = Background_Color
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.minimumRange = 10
        slider.lowerValue = Double(selectRange.lowerBound)
        slider.upperValue = Double(selectRange.upperBound)
        slider.upperThumbLayer.highlighted = true
        slider.keepThumbHighlighted = true
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        sliderView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        minLabel = UILabel(text: "\(selectRange.lowerBound)%", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        sliderView.addSubview(minLabel)
        minLabel.snp.makeConstraints { make in
            make.centerX.equalTo(slider.snp.left).offset(0)
            make.top.equalToSuperview()
//            make.width.greaterThanOrEqualTo(SCRXFrom(30))
        }
        
        maxLabel = UILabel(text: "\(selectRange.upperBound)%", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        sliderView.addSubview(maxLabel)
        maxLabel.snp.makeConstraints { make in
            make.centerX.equalTo(slider.snp.left).offset(20)
            make.top.equalToSuperview()
//            make.width.greaterThanOrEqualTo(SCRXFrom(30))
        }
        
        noteLabel = UILabel(text: "absolute_sensitivity_messsage".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        containerView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(sliderView)
            make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            make.bottom.equalTo(SCRYFrom(-20))
        }
        
    }
}
