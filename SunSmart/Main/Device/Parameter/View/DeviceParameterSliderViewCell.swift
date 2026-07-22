//
//  DeviceParameterSliderViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/3.
//

import UIKit
import NordicSigMeshSDK

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
        
        titleLabel = UILabel(text: "absolute_sensitivity".localizedString + ":", textColor: TextBlack_Color, fontSize: 14)
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16)).priority(.high)
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

protocol DeviceParameterPhotosensorExceptionViewCellDelegate: AnyObject {
    func photosensorCell(_ cell: DeviceParameterPhotosensorExceptionViewCell, selectionChanged selected: Bool)
    func photosensorCell(_ cell: DeviceParameterPhotosensorExceptionViewCell, featureEnabledChanged enabled: Bool)
    func photosensorCell(_ cell: DeviceParameterPhotosensorExceptionViewCell, maxPercentChanged value: UInt8)
    func photosensorCellResetAction(_ cell: DeviceParameterPhotosensorExceptionViewCell)
}

final class DeviceParameterPhotosensorExceptionViewCell: UITableViewCell {
    weak var delegate: DeviceParameterPhotosensorExceptionViewCellDelegate?

    private let containerView = UIView()
    private let titleLabel = UILabel(text: "photosensor_exception".localizedString + ":", textColor: TextBlack_Color, fontSize: 14)
    private let selectionSwitch = UISwitch()
    private let detailsView = UIView()
    private let featurePanelView = UIView()
    private let featureTitleLabel = UILabel(text: "feature_switch".localizedString, textColor: AssistText_Color, fontSize: 12)
    private let featureStateLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
    private let featureSwitch = UISwitch()
    private let resetButton = UIButton()
    private let sliderView = UIView()
    private let slider = CustomDeviceSlider()
    private let minusButton = UIButton()
    private let addButton = UIButton()
    private let valueLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
    private let noteLabel = UILabel(text: "photosensor_exception_note".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
    private let defaultLabel = UILabel(text: "photosensor_exception_default".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)

    private var maxPercent: UInt8 = PhotosensorExceptionState.defaultMaxPercent

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(selected: Bool, state: PhotosensorExceptionState) {
        selectionSwitch.isOn = selected
        featureSwitch.isOn = state.isEnabled
        maxPercent = state.maxPercent ?? maxPercent
        slider.value = Float(maxPercent)
        updateValueLabel()
        updateVisibility()
    }

    @objc private func selectionChanged() {
        updateVisibility()
        delegate?.photosensorCell(self, selectionChanged: selectionSwitch.isOn)
    }

    @objc private func featureChanged() {
        if featureSwitch.isOn, maxPercent == 0 {
            maxPercent = PhotosensorExceptionState.defaultMaxPercent
        }
        updateVisibility()
        delegate?.photosensorCell(self, featureEnabledChanged: featureSwitch.isOn)
    }

    @objc private func resetAction() {
        maxPercent = PhotosensorExceptionState.defaultMaxPercent
        slider.value = Float(maxPercent)
        updateValueLabel()
        delegate?.photosensorCellResetAction(self)
    }

    @objc private func minusAction() {
        updateMaxPercent(max(Int(maxPercent) - 1, 1))
    }

    @objc private func addAction() {
        updateMaxPercent(min(Int(maxPercent) + 1, 100))
    }

    private func updateMaxPercent(_ value: Int) {
        maxPercent = UInt8(min(max(value, 1), 100))
        slider.value = Float(maxPercent)
        updateValueLabel()
        delegate?.photosensorCell(self, maxPercentChanged: maxPercent)
    }

    private func updateValueLabel() {
        valueLabel.text = "\(maxPercent)%"
    }

    private func updateVisibility() {
        let selected = selectionSwitch.isOn
        let enabled = featureSwitch.isOn
        detailsView.isHidden = !selected
        sliderView.isHidden = !enabled
        resetButton.isHidden = !enabled
        featureStateLabel.text = (enabled ? "photosensor_exception_enabled" : "photosensor_exception_disabled").localizedString

        titleLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24))
            if !selected {
                make.bottom.equalTo(SCRYFrom(-23))
            }
        }
        detailsView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(18))
            if selected {
                make.bottom.equalToSuperview()
            }
        }
        featurePanelView.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(enabled ? 144 : 64))
        }
        noteLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(featurePanelView.snp.bottom).offset(SCRYFrom(12))
        }
    }

    private func setupUI() {
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }

        containerView.addSubview(titleLabel)
        selectionSwitch.onTintColor = Bar_Color
        selectionSwitch.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        containerView.addSubview(selectionSwitch)
        selectionSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }

        containerView.addSubview(detailsView)
        featurePanelView.backgroundColor = RGB(249, 250, 252)
        featurePanelView.layer.cornerRadius = SCRYFrom(7)
        detailsView.addSubview(featurePanelView)

        featurePanelView.addSubview(featureTitleLabel)
        featureTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(12))
        }
        featurePanelView.addSubview(featureStateLabel)
        featureStateLabel.snp.makeConstraints { make in
            make.left.equalTo(featureTitleLabel)
            make.top.equalTo(featureTitleLabel.snp.bottom).offset(SCRYFrom(4))
        }

        featureSwitch.onTintColor = Bar_Color
        featureSwitch.addTarget(self, action: #selector(featureChanged), for: .valueChanged)
        featurePanelView.addSubview(featureSwitch)
        featureSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-14))
            make.top.equalTo(SCRYFrom(16))
        }

        resetButton.setTitle("reset".localizedString, for: .normal)
        resetButton.setTitleColor(Bar_Color, for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        resetButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(11.5), bottom: 0, right: SCRXFrom(11.5))
        resetButton.layer.cornerRadius = SCRYFrom(14)
        resetButton.layer.borderWidth = 0.5
        resetButton.layer.borderColor = RGB(220, 220, 220).cgColor
        resetButton.addTarget(self, action: #selector(resetAction), for: .touchUpInside)
        featurePanelView.addSubview(resetButton)
        resetButton.snp.makeConstraints { make in
            make.right.equalTo(featureSwitch.snp.left).offset(SCRXFrom(-24))
            make.centerY.equalTo(featureSwitch)
            make.height.equalTo(SCRYFrom(28))
        }

        featurePanelView.addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-14))
            make.top.equalTo(SCRYFrom(70))
            make.height.equalTo(SCRYFrom(69))
        }

        minusButton.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        minusButton.addTarget(self, action: #selector(minusAction), for: .touchUpInside)
        sliderView.addSubview(minusButton)
        minusButton.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-6))
        }

        addButton.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        addButton.addTarget(self, action: #selector(addAction), for: .touchUpInside)
        sliderView.addSubview(addButton)
        addButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-6))
        }

        slider.minimumValue = 1
        slider.maximumValue = 100
        slider.value = Float(maxPercent)
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

        sliderView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
        }

        noteLabel.textAlignment = .left
        noteLabel.numberOfLines = 0
        detailsView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(featurePanelView.snp.bottom).offset(SCRYFrom(12))
        }

        defaultLabel.textAlignment = .left
        defaultLabel.numberOfLines = 0
        detailsView.addSubview(defaultLabel)
        defaultLabel.snp.makeConstraints { make in
            make.left.right.equalTo(noteLabel)
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-20))
        }

        updateValueLabel()
    }
}

extension DeviceParameterPhotosensorExceptionViewCell: CustomDeviceSliderDelegate {
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        updateMaxPercent(Int(value.rounded()))
    }
}
