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
    /// 秒，UInt32.max 表示无限长。显示与编辑均以此整数值为准。
    var second: UInt32 = 600 {
        didSet {
            updateUI()
        }
    }
    /// 是否可编辑
    var editable: Bool = true
     
    weak var delegate: ProfileManualOverrideTimeoutViewDelegate?
    /// 超时时间数据
    private var timeoutDatas: [(name: String, second: UInt32)] = []
    private var hasSliderChanges = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setData()
        setupUI()
        updateUI()
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
        
        guard second != .max,
              let next = timeoutDatas.first(where: { $0.second > second }) else { return }
        selectTimeout(next.second)
    }
    
    @objc private func minusBtnClick() {
        
        guard editable else {
            delegate?.timeoutViewDisableEditAction(view: self)
            return
        }
        
        guard second != .max,
              let previous = timeoutDatas.last(where: { $0.second < second }) else { return }
        selectTimeout(previous.second)
    }
    
    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        
        guard editable else {
            updateUI()
            delegate?.timeoutViewDisableEditAction(view: self)
            return
        }
        selectTimeout(sender.isOn ? 600 : .max)
    }
    
    @objc private func enableSwitchBtnAction() {
        if self.editable {
            self.enableSwitch.isOn = !self.enableSwitch.isOn
            enableSwitchValueChanged(sender: self.enableSwitch)
        }else {
            delegate?.timeoutViewDisableEditAction(view: self)
        }
    }
    
    /// 非预设值只借用最近的有限档位定位滑块，不改写原始秒数。
    private var displayIndex: Int {
        if second == .max { return timeoutDatas.count - 1 }
        return timeoutDatas.indices.dropLast().min {
            abs(Int64(timeoutDatas[$0].second) - Int64(second))
                < abs(Int64(timeoutDatas[$1].second) - Int64(second))
        } ?? 0
    }

    private func selectTimeout(_ value: UInt32) {
        let changed = second != value
        second = value
        if changed {
            delegate?.view(self, timeoutValueChanged: value)
        }
    }

    private func updateUI() {
        let enabled = second != .max
        enableSwitch.isOn = enabled
        // 手势尚未结束时允许从 Infinite 拖回有限值；取消也走结束回调。
        slider.isEnabled = enabled || slider.isSliding
        addBtn.isEnabled = enabled
        minusBtn.isEnabled = enabled
        if !slider.isSliding {
            slider.value = Float(displayIndex)
        }
        updateValue()
    }
    
    private func updateValue() {
        
        valueLabel.text = timeoutDatas.first(where: { $0.second == second })?.name
            ?? "\(second) \("sec".localizedString)"
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
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.75
        contentView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.left.greaterThanOrEqualTo(timeoutLabel.snp.right).offset(SCRXFrom(8))
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
        slider.step = 1
        slider.value = 10
        slider.sendsFinalValueOnTouchCancel = true
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
        guard editable else {
            updateUI()
            delegate?.timeoutViewDisableEditAction(view: self)
            return
        }
        // 只有 touch-down 后被取消/松手时，不将历史非预设值改成滑块定位值。
        if ended && !hasSliderChanges {
            updateUI()
            return
        }
        hasSliderChanges = !ended
        guard slider.isEnabled, value.isFinite else { return }
        let index = Int(min(Float(timeoutDatas.count - 1), max(0, value.rounded())))
        selectTimeout(timeoutDatas[index].second)
    }
    
    
    /// 是否可以滑动
    /// - Parameters:
    ///   - slider: 滑条
    ///   - value: 数值
    /// - Returns: 是否可以滑动
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool {
        hasSliderChanges = false
        if !editable {
            delegate?.timeoutViewDisableEditAction(view: self)
        }
        return editable
    }
    
}
