//
//  DeviceParameterAbsoluteSensitivityViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/17.
//

import UIKit

protocol DeviceParameterAbsoluteSensitivityViewCellDelegate: AnyObject {
    
    /// 修改灵敏度范围
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, changeSensitivityRange range: ClosedRange<UInt8>)
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterAbsoluteSensitivityViewCell, parameterEnableStateChanged enable: Bool)
    
}

class DeviceParameterAbsoluteSensitivityViewCell: UITableViewCell {

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
    
    weak var delegate: DeviceParameterAbsoluteSensitivityViewCellDelegate?

    /// 选择的范围
    var selectRange: ClosedRange<UInt8> = 0...80 {
        didSet {
            slider.lowerValue = Double(selectRange.lowerBound)
            slider.upperValue = Double(selectRange.upperBound)
            updateSliderUI()
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        
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
        slider.upperValue = min(slider.upperValue + 1, slider.maximumValue)
        updateSliderUI()
    }
    
    @objc private func minusBtnClick() {
        slider.upperValue = max(slider.upperValue - 1, slider.minimumValue)
        updateSliderUI()
    }
    
    @objc private func sliderValueChanged() {
        updateSliderUI()
        delegate?.cell(self, changeSensitivityRange: UInt8(slider.lowerValue)...UInt8(slider.upperValue))
    }
    
    func updateParameterEnable(enable: Bool) {
        enableSwitch.isOn = enable
        if enable {
            
            noteLabel.isHidden = false
            sliderView.isHidden = false
            
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24))
            }
            
            noteLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(sliderView)
                make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16))
                make.bottom.equalTo(SCRYFrom(-20))
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
                make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16))
            }
        }
    }
    
    private func updateSliderUI() {
        let range = UInt8(slider.lowerValue)...UInt8(slider.upperValue)
        
        minLabel.text = "\(range.lowerBound)%"
        maxLabel.text = "\(range.upperBound)%"
        guard slider.frame != .zero else {
            return
        }
        let minProgress = (Double(range.lowerBound) - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)
        let maxProgress = (Double(range.upperBound) - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)
        
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
        
        titleLabel = UILabel(text: "absolute_sensitivity".localizedString + ":", textColor: ImportantText_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24))
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        sliderView = UIView()
        contentView.addSubview(sliderView)
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
        slider.lowerValue = Double(selectRange.lowerBound)
        slider.upperValue = Double(selectRange.upperBound)
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
        
        maxLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        sliderView.addSubview(maxLabel)
        maxLabel.snp.makeConstraints { make in
            make.centerX.equalTo(slider.snp.left).offset(20)
            make.top.equalToSuperview()
//            make.width.greaterThanOrEqualTo(SCRXFrom(30))
        }
        
        noteLabel = UILabel(text: "absolute_sensitivity_messsage".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.textAlignment = .center
        noteLabel.numberOfLines = 0
        contentView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.right.equalTo(sliderView)
            make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-20))
        }
        
    }
}
