//
//  ProfileLevelSettingsView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/1.
//

import UIKit


class ProfileLevelSettingsView: UIView {
    
    typealias LevelSettingsCallback = ((LevelResult)->Void)
    typealias LevelItemValueChangedCallback = ((ProfileLevelSettingsItem, Int)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    /// Auto.min.value
    private var autoMinValueLabel: UILabel?
    private var autoMinValueSwitch: UISwitch?
    private var promptLabel: UILabel?
    
    private var items: [ProfileLevelSettingsItem] = []
    
    let levelType: ProfileLevelSettingsView.LevelType
    let valueChangedCallback: LevelItemValueChangedCallback?
    let settingsCallback: LevelSettingsCallback?

    
    init(levelType: ProfileLevelSettingsView.LevelType, valueChangedCallback: LevelItemValueChangedCallback?, settingsCallback: LevelSettingsCallback?) {
        self.levelType = levelType
        self.valueChangedCallback = valueChangedCallback
        self.settingsCallback = settingsCallback
        super.init(frame: UIScreen.main.bounds)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    /// 当前显示的view
    static func current() -> ProfileLevelSettingsView? {
        let view = UIApplication.shared.keyWindow().subviews.first(where: { $0.isKind(of: ProfileLevelSettingsView.classForCoder()) }) as? ProfileLevelSettingsView
        return view
    }
    
    func show() {
        if self.superview == nil {
            UIApplication.shared.keyWindow().addSubview(self)
//            layoutIfNeeded()
        }
        self.shadeView.alpha = 0
        self.contentView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
        }
    }
    
    /// Item进入刷新状态
    func startItemLoadding(type: ProfileLevelSettingsView.LevelType.ItemType) {
        if let item = items.first(where: { $0.itemType.rawValue == type.rawValue }) {
            item.showLoadingAnimation()
        }
    }
    
    /// Item停止刷新状态
    func stopItemLoadding(type: ProfileLevelSettingsView.LevelType.ItemType) {
        if let item = items.first(where: { $0.itemType.rawValue == type.rawValue }) {
            item.hideLoadingAnimation()
        }
    }
    
    /// 更新Item数据
    func updateItemData(type: ProfileLevelSettingsView.LevelType.ItemType) {
        if let item = items.first(where: { $0.itemType.rawValue == type.rawValue }) {
            item.value = type.data.value
        }
    }
    
    // MARK: - Action
    /// 遮罩点击
    @objc private func shadeViewAction() {
        
        var result: LevelResult!
        switch levelType {
        case .highLowEndTrim:
            result = .highLowEndTrim(high: items.first!.value, low: items.last!.value)
        case .occupancyAndVacantLevel:
            result = .occupancyAndVacantLux(occupanyLux: items.first!.value, vacantLux: items.last!.value)
        case .occupancyAndVacantLux:
            result = .occupancyAndVacantLux(occupanyLux: items.first!.value, vacantLux: items.last!.value)
        case .autoMinValue:
            result = .autoMinValue(level: items.first!.value, enabled: autoMinValueSwitch!.isOn)
        case .taskLevel:
            result = .taskLevel(level: items.first!.value)
        case .taskLux:
            result = .taskLux(lux: items.first!.value)
        }
        settingsCallback?(result)
        dismiss()
    }
    
    private func dismiss() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }

    }
    
    /// 最小值开关修改
    @objc private func autoMinValueSwitchValueChanged(sender: UISwitch) {
        
        contentView.snp.updateConstraints { make in
            make.height.equalTo(sender.isOn ? SCRYFrom(220) : SCRYFrom(64))
        }
        UIView.animate(withDuration: 0.25) {
            self.layoutIfNeeded()
            
            if sender.isOn {
                self.promptLabel?.isHidden = self.items.first?.itemType.data.min == 0
                self.items.first?.isHidden = false
            }else {
                self.promptLabel?.isHidden = true
                self.items.first?.isHidden = true
            }
            
        }completion: { _ in
           
        }
       
        
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.alpha = 0
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 15
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(SCRYFrom(-34))
            make.height.equalTo(SCRYFrom(220))
        }
//        let  levelType.items
        if case .autoMinValue = levelType {
            
//            contentView.snp.updateConstraints { make in
//                make.height.equalTo(SCRYFrom(64))
//            }
            
            autoMinValueLabel = UILabel(text: "profile_auto_min_value".localizedString, textColor: TextBlack_Color, fontSize: 15)
            contentView.addSubview(autoMinValueLabel!)
            autoMinValueLabel!.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.top.equalTo(SCRYFrom(23))
            }
            
            autoMinValueSwitch = UISwitch()
            autoMinValueSwitch?.onTintColor = Bar_Color
            autoMinValueSwitch?.tintColor = RGB(207, 207, 207)
            autoMinValueSwitch?.addTarget(self, action: #selector(autoMinValueSwitchValueChanged), for: .valueChanged)
            contentView.addSubview(autoMinValueSwitch!)
            autoMinValueSwitch!.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-20))
                make.centerY.equalTo(autoMinValueLabel!)
            }
            
            promptLabel = UILabel(text: "profile_auto_min_value_prompt".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
            promptLabel?.numberOfLines = 2
            contentView.addSubview(promptLabel!)
            promptLabel!.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                make.bottom.equalTo(SCRYFrom(-22))
            }
           
            if let item = levelType.items.first {
                promptLabel?.isHidden = item.data.min == 0
                let itemView = ProfileLevelSettingsItem(itemType: item)
                itemView.valueChangedCallback = {[weak self] (value, ended) in
                    if ended {
                        self?.valueChangedCallback?(itemView, value)
                    }
                }
                contentView.addSubview(itemView)
                itemView.snp.makeConstraints { make in
                    make.left.equalTo(SCRXFrom(20))
                    make.right.equalTo(SCRXFrom(-20))
                    make.centerY.equalToSuperview()
                    make.height.equalTo(SCRYFrom(70))
                }
                items.append(itemView)
            }
            
            switch levelType {
            case .autoMinValue(_, _, let enabled):
                autoMinValueSwitch!.isOn = enabled
                
                contentView.snp.updateConstraints { make in
                    make.height.equalTo(enabled ? SCRYFrom(220) : SCRYFrom(64))
                }
                if enabled {
                    self.promptLabel?.isHidden = self.items.first?.itemType.data.min == 0
                    self.items.first?.isHidden = false
                }else {
                    self.promptLabel?.isHidden = true
                    self.items.first?.isHidden = true
                }
                
//                autoMinValueSwitchValueChanged(sender: autoMinValueSwitch!)
            default:
                break
            }
           
        }else {
            
            var lastAddItem: ProfileLevelSettingsItem?
            for item in levelType.items {
                
                let itemView = ProfileLevelSettingsItem(itemType: item)
                itemView.valueChangedCallback = {[weak self] (value, ended) in
                    if ended {
                        self?.valueChangedCallback?(itemView, value)
                    }
                }
                contentView.addSubview(itemView)
                itemView.snp.makeConstraints { make in
                    make.left.equalTo(SCRXFrom(20))
                    make.right.equalTo(SCRXFrom(-20))
                    make.height.equalTo(SCRYFrom(70))
                    if let lastItem = lastAddItem {
                        make.top.equalTo(lastItem.snp.bottom).offset(SCRYFrom(28))
                    }else {
                        make.top.equalTo(SCRYFrom(24))
                    }
                }
                lastAddItem = itemView
                items.append(itemView)
            }
            if levelType.items.count == 1 {
                contentView.snp.updateConstraints({ make in
                    make.height.equalTo(SCRYFrom(122))
                })
            }
            
        }
        
    }
    
}

class ProfileLevelSettingsItem: UIView {
    
    private var titleLabel: UILabel!
    
    private var valueLabel: UILabel!
    /// 滑条
    private var slider: CustomDeviceSlider!
    /// 增加
    private var addBtn: UIButton!
    /// 减少
    private var minusBtn: UIButton!
    /// 加载图标
    private var loadingImageView: UIImageView!
    /// 类型
    var itemType: ProfileLevelSettingsView.LevelType.ItemType
    /// 数值修改回调 value：数值  是否停止修改
    var valueChangedCallback: ((_ value: Int, _ ended: Bool)->Void)?
    /// 是否加载中
    private var loading: Bool = false
    
    var value: Int {
        get {
            // 光感传感器是否已校准，校准后显示实际环境照度值
            if itemType.data.calibrated {
                let data = itemType.data
                return data.value
            }else {
                return Int(slider.value)
            }
        }set {
            // 光感传感器是否已校准，校准后显示实际环境照度值
            if itemType.data.calibrated {
                switch itemType {
                case .occupancyLux:
                    itemType = .occupancyLux(value: newValue, calibrated: true)
                case .vacantLux:
                    itemType = .vacantLux(value: newValue, calibrated: true)
                case .taskLux:
                    itemType = .taskLux(value: newValue, calibrated: true)
                default:
                    break
                }
            }else {
                slider.value = Float(newValue)
            }
            updateValue()
        }
    }
    
    init(frame: CGRect = .zero, itemType: ProfileLevelSettingsView.LevelType.ItemType) {
        self.itemType = itemType
        super.init(frame: frame)
        
        setupUI()
        
        let data = itemType.data
        titleLabel.text = data.title
        slider.minimumValue = Float(data.range.lowerBound)
        slider.maximumValue = Float(data.range.upperBound)
        slider.limitRange = data.min...data.max
        if data.calibrated {
            slider.value = 0
        }else {
            slider.value = Float(data.value)
        }
        updateValue()
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 显示loading动画
    func showLoadingAnimation() {
        
        loading = true
        slider.isUserInteractionEnabled = false
        
        loadingImageView.isHidden = false
        loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
        valueLabel.isHidden = true
    }
    
    /// 隐藏loading动画
    func hideLoadingAnimation() {
        
        loading = false
        slider.isUserInteractionEnabled = true
        loadingImageView.isHidden = true
        loadingImageView.layer.removeAnimation(forKey: "loading")
        valueLabel.isHidden = false
    }
    
    @objc private func addBtnClick() {
        if loading { // 加载中禁止数值修改
            return
        }
        slider.value = min(slider.value + 1, slider.maximumValue)
        updateValue()
        valueChangedCallback?(Int(slider.value), true)
    }
    
    @objc private func minusBtnClick() {
        if loading { // 加载中禁止数值修改
            return
        }
        slider.value = max(slider.value - 1, slider.minimumValue)
        updateValue()
        valueChangedCallback?(Int(slider.value), true)
    }
    
    private func updateValue() {
        let data = itemType.data
        if data.calibrated {
            valueLabel.text = "\(value)\(data.unit)"
        }else {
            valueLabel.text = "\(Int(slider.value))\(data.unit)"
        }
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }
        
        valueLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-47))
            make.centerY.equalTo(titleLabel)
        }

        loadingImageView = UIImageView(image: UIImage(named: "loading"))
        loadingImageView.isHidden = true
        addSubview(loadingImageView)
        loadingImageView.snp.makeConstraints { make in
            make.center.equalTo(valueLabel)
        }
        
        addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
        addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-6))
            make.right.equalToSuperview()
        }
        
        minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
        addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalTo(addBtn)
        }
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.minimumTrackTintColor = Slider_Color
        slider.maximumTrackTintColor = RGB(229, 229, 229)
        slider.layer.cornerRadius = 2
        slider.minimumValue = 0
        slider.maximumValue = 100
//        slider.throttle = false
        slider.value = 50
        slider.delegate = self
        addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(41))
            make.right.equalTo(SCRXFrom(-42))
            make.centerY.equalTo(addBtn)
            make.height.equalTo(SCRYFrom(40))
        }
        
    }
    
}

extension ProfileLevelSettingsItem: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        updateValue()
        valueChangedCallback?(Int(value), ended)
    }
    
}

extension ProfileLevelSettingsView {
    
    enum LevelType {
        enum ItemType {

            var rawValue: Int {
                switch self {
                case .howEndTrim:
                    return 1
                case .lowEndTrim:
                    return 2
                case .occupancyLevel:
                    return 3
                case .occupancyLux:
                    return 4
                case .vacantLevel:
                    return 5
                case .vacantLux:
                    return 6
                case .autoMinValue:
                    return 7
                case .taskLevel:
                    return 8
                case .taskLux:
                    return 9
                }
            }
            
            /// title：标题  value：当前值  range：默认可选范围  min：最小值  max：最大值  unit：单位 calibrated：是否已校准（获取实际环境lux）
            var data: (title: String, value: Int, range: ClosedRange<Int>, min: Int, max: Int, unit: String, calibrated: Bool) {
                
                let levelRange: ClosedRange<Int> = 0...100
//                let luxRange: ClosedRange<Int> = 0...1500
                
                switch self {
                case .howEndTrim(let value):
                    return ("profile_high_end_trim".localizedString, value, 50...100, levelRange.lowerBound, levelRange.upperBound, "%", false)
                case .lowEndTrim(let value):
                    return ("profile_low_end_trim".localizedString, value, 0...30, 0, 30, "%", false)
                case .occupancyLevel(let value, let inputRange):
                    return ("profile_occupancy_level".localizedString, value, levelRange, inputRange.lowerBound, inputRange.upperBound, "%", false)
                case .occupancyLux(let value, let inputRange, let calibrated):
                    return ("profile_occupancy_level".localizedString, value, calibrated ? levelRange : inputRange, inputRange.lowerBound, inputRange.upperBound, "lx", calibrated)
                case .vacantLevel(let value, let inputRange):
                    return ("profile_vacant_level".localizedString, value, levelRange, inputRange.lowerBound, inputRange.upperBound, "%", false)
                case .vacantLux(let value, let inputRange, let calibrated):
                    return ("profile_vacant_level".localizedString, value, calibrated ? levelRange : inputRange, inputRange.lowerBound, inputRange.upperBound, "lx", calibrated)
                case .autoMinValue(let value, let inputRange):
                    return ("light_level".localizedString, value, 0...30, inputRange.lowerBound, inputRange.upperBound, "%", false)
                case .taskLevel(let value, let inputRange):
                    return ("profile_task_level".localizedString, value, levelRange, inputRange.lowerBound, inputRange.upperBound, "%", false)
                case .taskLux(let value, let inputRange, let calibrated):
                    return ("profile_task_level".localizedString, value, calibrated ? levelRange : inputRange, inputRange.lowerBound, inputRange.upperBound, "lx", calibrated)
                }
                
            }
            
            case howEndTrim(value: Int)
            case lowEndTrim(value: Int)
            case occupancyLevel(value: Int, inputRange: ClosedRange<Int> = 0...100)
            case occupancyLux(value: Int, inputRange: ClosedRange<Int> = 0...1500, calibrated: Bool = false)
            case vacantLevel(value: Int, inputRange: ClosedRange<Int> = 0...100)
            case vacantLux(value: Int, inputRange: ClosedRange<Int> = 0...1500, calibrated: Bool = false)
            case autoMinValue(value: Int, inputRange: ClosedRange<Int> = 0...30)
            case taskLevel(value: Int, inputRange: ClosedRange<Int> = 0...100)
            case taskLux(value: Int, inputRange: ClosedRange<Int> = 0...1500, calibrated: Bool = false)
        }
        
        var items: [ItemType] {
            switch self {
            case .highLowEndTrim(let high, let low):
                return [.howEndTrim(value: high), .lowEndTrim(value: low)]
            case .occupancyAndVacantLevel(let occupanyLevel, let vacantLevel, let inputRange):
                return [.occupancyLevel(value: occupanyLevel, inputRange: inputRange), .vacantLevel(value: vacantLevel, inputRange: inputRange)]
            case .occupancyAndVacantLux(let occupanyLux, let vacantLux, let inputRange, let calibrated):
                return [.occupancyLux(value: occupanyLux, inputRange: inputRange, calibrated: calibrated), .vacantLux(value: vacantLux, inputRange: inputRange, calibrated: calibrated)]
            case .autoMinValue(let level, let inputRange, _):
                return [.autoMinValue(value: level, inputRange: inputRange)]
            case .taskLevel(let level, let inputRange):
                return [.taskLevel(value: level, inputRange: inputRange)]
            case .taskLux(let lux, let inputRange, let calibrated):
                return [.taskLux(value: lux, inputRange: inputRange, calibrated: calibrated)]
            }
        }
        
        
        /// 亮度输出范围
        case highLowEndTrim(high: Int = 100, low: Int = 0)
        /// 第一阶段（占用）+ 第二阶段（闲置）亮度值
        case occupancyAndVacantLevel(occupanyLevel: Int, vacantLevel: Int, inputRange: ClosedRange<Int> = 0...100)
        /// 第一阶段（占用）+ 第二阶段（闲置）照度值 calibrated：是否已校准
        case occupancyAndVacantLux(occupanyLux: Int = 500, vacantLux: Int = 100, inputRange: ClosedRange<Int> = 0...1500, calibrated: Bool = false)
        /// 光照补偿亮度最低值
        case autoMinValue(level: Int = 0, inputRange: ClosedRange<Int> = 0...30, enabled: Bool = false)
        /// ON后亮度值
        case taskLevel(level: Int = 100, inputRange: ClosedRange<Int> = 0...100)
        /// 光照维持环境照度值  calibrated：是否已校准
        case taskLux(lux: Int = 500, inputRange: ClosedRange<Int> = 0...1500, calibrated: Bool = false)
    }
    
    /// level结果
    enum LevelResult {
        /// 亮度输出范围
        case highLowEndTrim(high: Int, low: Int)
        /// 第一阶段（占用）+ 第二阶段（闲置）亮度值
        case occupancyAndVacantLevel(occupanyLevel: Int, vacantLevel: Int)
        /// 第一阶段（占用）+ 第二阶段（闲置）照度值
        case occupancyAndVacantLux(occupanyLux: Int, vacantLux: Int)
        /// 光照补偿亮度最低值
        case autoMinValue(level: Int, enabled: Bool)
        /// ON后亮度值
        case taskLevel(level: Int)
        /// 光照维持环境照度值
        case taskLux(lux: Int)
    }
    
}
