//
//  ProfileManualOverrideTimeoutView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

protocol ProfileManualOverrideTimeoutViewDelegate: AnyObject {
    
    /// 帮助
    func timeoutViewHelpAction(view: ProfileManualOverrideTimeoutView)
    
    /// 手动控制超时时长修改
    /// - Parameters:
    ///   - view: view
    ///   - second: 秒 max：无限长（禁用） >0：启用
    func view(_ view: ProfileManualOverrideTimeoutView, timeoutValueChanged second: UInt32)
    
    /// 禁止交互下编辑事件
    func timeoutViewDisableEditAction(view: ProfileManualOverrideTimeoutView)
}

class ProfileManualOverrideTimeoutView: UIView {

    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    private var enableSwitch: UISwitch!
    private var enableSwitchBtn: UIButton!
    private var contentView: UIView!
    /// 增加
    private var addBtn: UIButton!
    /// 减少
    private var minusBtn: UIButton!
    /// timeout
    private var timeoutLabel: UILabel!
    /// 当前值
    var valueLabel: UILabel!
    /// 滑条
    var slider: CustomDeviceSlider!
    /// 秒，未启用传-1
    var second: UInt32 = 600 {
        didSet {
            if let value = timeoutDatas.firstIndex(where: { $0.second == second }) {
                slider.value = Float(value)
//                valueLabel.text = timeoutDatas[Int(slider.value)].name
            }else {
                slider.value = 10
            }
//            updateValue()
            updateUI()
        }
    }
    /// 是否可编辑
    var editable: Bool = true
     
    weak var delegate: ProfileManualOverrideTimeoutViewDelegate?
    /// 超时时间数据
    private var timeoutDatas: [(name: String, second: UInt32)] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setData()
        setupUI()
    }
    
    private func setData() {
        for index in 0...60 {
            if index == 0 {
                timeoutDatas.append((name: "5 s", second: 5))
            }else {
                timeoutDatas.append((name: "\(index) min", second: UInt32(index * 60)))
            }
        }
        timeoutDatas.append((name: "infinite".localizedString, second: .max))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func helpBtnAction() {
        delegate?.timeoutViewHelpAction(view: self)
    }

    @objc private func addBtnClick() {
        
        guard editable else {
            delegate?.timeoutViewDisableEditAction(view: self)
            return
        }
        
        slider.value = min(slider.value + 1, slider.maximumValue)
        let second = timeoutDatas[Int(slider.value)].second
        delegate?.view(self, timeoutValueChanged: second)
        if slider.value == slider.maximumValue {
            updateUI()
        }else {
            updateValue()
        }
        
    }
    
    @objc private func minusBtnClick() {
        
        guard editable else {
            delegate?.timeoutViewDisableEditAction(view: self)
            return
        }
        
        slider.value = max(slider.value - 1, slider.minimumValue)
        updateValue()
        let second = timeoutDatas[Int(slider.value)].second
        delegate?.view(self, timeoutValueChanged: second)
    }
    
    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        
        if sender.isOn {
            slider.value = 10
        }else {
            slider.value = slider.maximumValue
        }
        let second = timeoutDatas[Int(slider.value)].second
        delegate?.view(self, timeoutValueChanged: second)
        
        updateUI()
    }
    
    @objc private func enableSwitchBtnAction() {
        if self.editable {
            self.enableSwitch.isOn = !self.enableSwitch.isOn
            enableSwitchValueChanged(sender: self.enableSwitch)
        }else {
            delegate?.timeoutViewDisableEditAction(view: self)
        }
    }
    
    private func updateUI() {
        
        enableSwitch.isOn = slider.value != slider.maximumValue
        
        if enableSwitch.isOn {
            slider.isEnabled = true
            addBtn.isEnabled = true
            minusBtn.isEnabled = true
        }else {
            slider.isEnabled = false
            addBtn.isEnabled = false
            minusBtn.isEnabled = false
        }
        updateValue()
//        contentView.snp.updateConstraints { make in
//            make.height.equalTo(enableSwitch.isOn ? SCRYFrom(89) : 0)
//        }
//        self.contentView.isHidden = !self.enableSwitch.isOn
//        UIView.animate(withDuration: 0.3) {
//            self.contentView.isHidden = !self.enableSwitch.isOn
//            self.layoutIfNeeded()
//        }
    }
    
    private func updateValue() {
        
        valueLabel.text = timeoutDatas[Int(slider.value)].name
    }

    private func setupUI() {
        
        titleLabel = UILabel(text: "manual_override_timeout".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(titleLabel)
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.isOn = true
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        enableSwitch.tintColor = RGB(207, 207, 207)
        addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        enableSwitchBtn = UIButton(target: self, action: #selector(enableSwitchBtnAction))
        enableSwitchBtn.isHidden = !editable
        addSubview(enableSwitchBtn)
        enableSwitchBtn.snp.makeConstraints { make in
            make.edges.equalTo(enableSwitch)
        }
        
        contentView = UIView()
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(89))
        }
        
        timeoutLabel = UILabel(text: "timeout".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(timeoutLabel)
        timeoutLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(4))
        }
        
        valueLabel = UILabel(text: "10 min", textColor: TextBlack_Color, fontWeight: .light)
        contentView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(timeoutLabel)
        }

        addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
//        addBtn.setImage(<#T##image: UIImage?##UIImage?#>, for: .highlighted)
        contentView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-21))
        }
        
        minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
        contentView.addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalTo(addBtn)
        }
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.minimumTrackTintColor = Slider_Color
        slider.maximumTrackTintColor = RGB(229, 229, 229)
        slider.layer.cornerRadius = 2
        slider.minimumValue = 0
        slider.maximumValue = Float(timeoutDatas.count - 1)
        slider.value = 10
        slider.throttle = true
        slider.delegate = self
        contentView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(61))
            make.right.equalTo(SCRXFrom(-62))
            make.centerY.equalTo(addBtn)
            make.height.equalTo(SCRYFrom(40))
        }
    }
}

extension ProfileManualOverrideTimeoutView: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        guard slider.isEnabled else {
            return
        }
        if slider.value == slider.maximumValue && ended {
            updateUI()
        }else {
            updateValue()
        }
        let second = timeoutDatas[Int(slider.value)].second
        delegate?.view(self, timeoutValueChanged: UInt32(second))
    }
    
    
    /// 是否可以滑动
    /// - Parameters:
    ///   - slider: 滑条
    ///   - value: 数值
    /// - Returns: 是否可以滑动
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool {
        if !editable {
            delegate?.timeoutViewDisableEditAction(view: self)
        }
        return editable
    }
    
}
