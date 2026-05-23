# CCT Parameter Settings Figma UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Device Parameter Settings 中 `Change Control Page` 和 `Absolute CCT Range` 启用后的 UI 调整为 Figma 设计稿效果，并修正特殊设备条件为 `companyIdentifier == 0x0A78 && productIdentifier == 0x2013`。

**Architecture:** 保留现有数据流、开关启用逻辑、云同步和设备参数下发逻辑，只替换两个 CCT 参数 cell 的启用后 UI。新增 `DeviceParameterCctRangeSlider` 作为 CCT 专用双滑块组件，但放在现有 `DeviceParameterSettingsViewCell.swift` 中，避免修改 Xcode project 配置；特殊设备默认值继续在 SDK `Node` 属性层统一提供。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK Swift Package、CocoaPods workspace、xcodebuild。

---

## Scope Check

本计划只覆盖 Device Parameter Settings 的 CCT 参数 UI 优化和特殊设备 company ID 修正。它不重做 CCT 支持判断、云同步 JSON 字段、Absolute CCT Range 下发协议、组控并集逻辑、Scene/Profile clamp 逻辑。

## File Structure

| 文件 | 责任 |
| --- | --- |
| `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` | 把特殊设备 company ID 从 `0x0178` 修正为 `0x0A78` |
| `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` | 把隐藏 PWM frequency 的特殊设备条件从 `0x0178` 修正为 `0x0A78` |
| `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift` | 重做 `DeviceParameterChangeControlPageViewCell`；新增 `DeviceParameterCctRangeSlider`；重做 `DeviceParameterAbsoluteCctRangeViewCell` |
| `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift` | 给 Absolute CCT Range cell 传入默认 range，并处理 Reset 回调 |
| `SunSmart/en.lproj/Localizable.strings` | 更新两个 CCT 参数英文说明文案 |
| `SunSmart/zh-Hans.lproj/Localizable.strings` | 更新两个 CCT 参数中文说明文案 |

不新建 Swift 文件，避免触碰 `SunSmart.xcodeproj/project.pbxproj`。当前工作区已有未提交的 `project.pbxproj` 变更，执行计划时不得覆盖或整理该文件。

---

### Task 1: 修正特殊设备 company ID

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 查找旧特殊设备判断**

Run:

```bash
rg -n "0x0178|0x0A78|0x2013|isSingleWhiteDefaultCctProduct" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: 看到 SDK `isSingleWhiteDefaultCctProduct` 和 App `supportPwmFrequency` 中仍有 `0x0178 && 0x2013`。

- [ ] **Step 2: 修正 SDK 特殊设备判断**

在 `Node+Propertys.swift` 中把 `isSingleWhiteDefaultCctProduct` 改为：

```swift
var isSingleWhiteDefaultCctProduct: Bool {
    companyIdentifier == 0x0A78 && productIdentifier == 0x2013
}
```

- [ ] **Step 3: 修正 App PWM frequency 排除条件**

在 `MeshNetwork+SunSmart.swift` 的 `supportPwmFrequency` 中把特殊设备判断改为：

```swift
if companyIdentifier == 0x0A78 && pid == 0x2013 {
    return false
}
```

- [ ] **Step 4: 静态验证旧 company ID 不再命中特殊判断**

Run:

```bash
rg -n "0x0178|0x0A78|0x2013|isSingleWhiteDefaultCctProduct" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: `0x0A78` 与 `0x2013` 出现在两个特殊判断中；`0x0178` 不再出现于这两个文件。

- [ ] **Step 5: Commit 特殊设备 ID 修正**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: update cct default product company id"
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: update cct pwm product company id"
```

---

### Task 2: 新增 CCT 专用范围滑块组件

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`

- [ ] **Step 1: 在文件中新增 `DeviceParameterCctRangeSliderDelegate`**

在 `DeviceParameterAbsoluteCctRangeViewCellDelegate` 前或后新增：

```swift
protocol DeviceParameterCctRangeSliderDelegate: AnyObject {
    func cctRangeSlider(_ slider: DeviceParameterCctRangeSlider, rangeChanged range: ClosedRange<UInt16>)
}
```

- [ ] **Step 2: 新增 `DeviceParameterCctRangeSlider` 类骨架**

在 `DeviceParameterSettingsViewCell.swift` 中新增类，放在 `DeviceParameterAbsoluteCctRangeViewCell` 前面：

```swift
final class DeviceParameterCctRangeSlider: UIControl {

    private let trackLayer = CALayer()
    private let highlightLayer = CALayer()
    private let lowerThumbView = UIImageView(image: UIImage(named: "slider_point"))
    private let upperThumbView = UIImageView(image: UIImage(named: "slider_point"))

    weak var delegate: DeviceParameterCctRangeSliderDelegate?

    private(set) var selectedThumb: Thumb = .upper
    private var lowerBound: UInt16 = NodeAbsoluteCctRange.defaultRange.lowerBound
    private var upperBound: UInt16 = NodeAbsoluteCctRange.defaultRange.upperBound

    enum Thumb {
        case lower
        case upper
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSlider()
    }

    func configure(range: ClosedRange<UInt16>) {
        lowerBound = normalizedLower(range.lowerBound)
        upperBound = normalizedUpper(range.upperBound)
        layoutSlider()
    }

    func stepSelectedThumb(by step: Int) {
        switch selectedThumb {
        case .lower:
            let value = Int(lowerBound) + step
            lowerBound = normalizedLower(UInt16(max(0, value)))
        case .upper:
            let value = Int(upperBound) + step
            upperBound = normalizedUpper(UInt16(max(0, value)))
        }
        layoutSlider()
        delegate?.cctRangeSlider(self, rangeChanged: lowerBound...upperBound)
    }

    private func setupUI() {
        layer.addSublayer(trackLayer)
        layer.addSublayer(highlightLayer)

        trackLayer.backgroundColor = RGB(229, 229, 229).cgColor
        highlightLayer.backgroundColor = Slider_Color.cgColor

        addSubview(lowerThumbView)
        addSubview(upperThumbView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }
}
```

- [ ] **Step 3: 增加 CCT 数值归一化方法**

在 `DeviceParameterCctRangeSlider` 内加入：

```swift
private func normalizedLower(_ value: UInt16) -> UInt16 {
    let rounded = roundedToStep(value)
    return min(max(rounded, NodeAbsoluteCctRange.minLowerBound), NodeAbsoluteCctRange.maxLowerBound)
}

private func normalizedUpper(_ value: UInt16) -> UInt16 {
    let rounded = roundedToStep(value)
    return min(max(rounded, NodeAbsoluteCctRange.minUpperBound), NodeAbsoluteCctRange.maxUpperBound)
}

private func roundedToStep(_ value: UInt16) -> UInt16 {
    let step = NodeAbsoluteCctRange.step
    let halfStep = step / 2
    return ((value + halfStep) / step) * step
}
```

Expected: `2700K` 和 `5000K` 是合法值；`(2700K, 5000K)` 不可能被归一化为最终值。

- [ ] **Step 4: 增加值与位置映射**

在 `DeviceParameterCctRangeSlider` 内加入：

```swift
private var thumbSize: CGFloat {
    SCRYFrom(30)
}

private var usableWidth: CGFloat {
    max(1, bounds.width - thumbSize)
}

private func xPosition(for value: UInt16, thumb: Thumb) -> CGFloat {
    switch thumb {
    case .lower:
        let progress = CGFloat(value - NodeAbsoluteCctRange.minLowerBound) / CGFloat(NodeAbsoluteCctRange.maxLowerBound - NodeAbsoluteCctRange.minLowerBound)
        return thumbSize / 2 + usableWidth * progress * 0.45
    case .upper:
        let progress = CGFloat(value - NodeAbsoluteCctRange.minUpperBound) / CGFloat(NodeAbsoluteCctRange.maxUpperBound - NodeAbsoluteCctRange.minUpperBound)
        return thumbSize / 2 + usableWidth * (0.55 + progress * 0.45)
    }
}

private func lowerValue(for x: CGFloat) -> UInt16 {
    let progress = min(max((x - thumbSize / 2) / (usableWidth * 0.45), 0), 1)
    let value = CGFloat(NodeAbsoluteCctRange.minLowerBound) + progress * CGFloat(NodeAbsoluteCctRange.maxLowerBound - NodeAbsoluteCctRange.minLowerBound)
    return normalizedLower(UInt16(value))
}

private func upperValue(for x: CGFloat) -> UInt16 {
    let progress = min(max((x - thumbSize / 2 - usableWidth * 0.55) / (usableWidth * 0.45), 0), 1)
    let value = CGFloat(NodeAbsoluteCctRange.minUpperBound) + progress * CGFloat(NodeAbsoluteCctRange.maxUpperBound - NodeAbsoluteCctRange.minUpperBound)
    return normalizedUpper(UInt16(value))
}
```

Expected: 左段映射 `1000...2700K`，右段映射 `5000...10000K`，中间 `45%...55%` 是视觉间隔区。Figma 比例不作为实现依据。

- [ ] **Step 5: 增加布局方法**

在 `DeviceParameterCctRangeSlider` 内加入：

```swift
private func layoutSlider() {
    guard bounds.width > 0 else {
        return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let trackHeight = SCRYFrom(2)
    let trackY = bounds.midY - trackHeight / 2
    trackLayer.frame = CGRect(x: thumbSize / 2, y: trackY, width: usableWidth, height: trackHeight)
    trackLayer.cornerRadius = trackHeight / 2

    let lowerX = xPosition(for: lowerBound, thumb: .lower)
    let upperX = xPosition(for: upperBound, thumb: .upper)
    highlightLayer.frame = CGRect(x: lowerX, y: trackY, width: upperX - lowerX, height: trackHeight)
    highlightLayer.cornerRadius = trackHeight / 2

    CATransaction.commit()

    lowerThumbView.frame = CGRect(x: lowerX - thumbSize / 2, y: bounds.midY - thumbSize / 2, width: thumbSize, height: thumbSize)
    upperThumbView.frame = CGRect(x: upperX - thumbSize / 2, y: bounds.midY - thumbSize / 2, width: thumbSize, height: thumbSize)
}
```

- [ ] **Step 6: 增加拖动和点击处理**

在 `DeviceParameterCctRangeSlider` 内加入：

```swift
@objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let location = gesture.location(in: self)

    if gesture.state == .began {
        selectedThumb = nearestThumb(to: location)
    }

    switch selectedThumb {
    case .lower:
        lowerBound = lowerValue(for: location.x)
    case .upper:
        upperBound = upperValue(for: location.x)
    }

    layoutSlider()
    delegate?.cctRangeSlider(self, rangeChanged: lowerBound...upperBound)
}

@objc private func handleTap(_ gesture: UITapGestureRecognizer) {
    let location = gesture.location(in: self)
    selectedThumb = nearestThumb(to: location)
    switch selectedThumb {
    case .lower:
        lowerBound = lowerValue(for: location.x)
    case .upper:
        upperBound = upperValue(for: location.x)
    }
    layoutSlider()
    delegate?.cctRangeSlider(self, rangeChanged: lowerBound...upperBound)
}

private func nearestThumb(to point: CGPoint) -> Thumb {
    let lowerDistance = abs(point.x - lowerThumbView.center.x)
    let upperDistance = abs(point.x - upperThumbView.center.x)
    return lowerDistance < upperDistance ? .lower : .upper
}
```

- [ ] **Step 7: 静态验证 slider 类型存在**

Run:

```bash
rg -n "DeviceParameterCctRangeSlider|DeviceParameterCctRangeSliderDelegate|normalizedLower|normalizedUpper|xPosition\\(for" SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift
```

Expected: 能看到新增 slider、delegate、归一化和映射方法。

- [ ] **Step 8: Commit CCT slider 组件**

```bash
git add SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift
git commit -m "feat: add cct range slider"
```

---

### Task 3: 重做 Change Control Page 启用后 UI

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`

- [ ] **Step 1: 替换 cell 私有控件属性**

在 `DeviceParameterChangeControlPageViewCell` 中移除 `segmentControl` 属性，改为：

```swift
private var optionsContainerView: UIView!
private var singleWhiteButton: UIControl!
private var singleWhiteIconView: UIImageView!
private var singleWhiteLabel: UILabel!
private var tunableWhiteButton: UIControl!
private var tunableWhiteIconView: UIImageView!
private var tunableWhiteLabel: UILabel!
private var selectedValue: NodeChangeControlPage = .tunableWhite
private var defaultValue: NodeChangeControlPage = .tunableWhite
```

- [ ] **Step 2: 更新 `configure`**

把 `configure(value:enabled:defaultValue:)` 改为：

```swift
func configure(value: NodeChangeControlPage, enabled: Bool, defaultValue: NodeChangeControlPage) {
    self.selectedValue = value
    self.defaultValue = defaultValue
    configureOptionTitles()
    updateOptionUI()
    updateParameterEnable(enable: enabled)
}
```

- [ ] **Step 3: 增加选项标题和选中态方法**

在 `DeviceParameterChangeControlPageViewCell` 中加入：

```swift
private func configureOptionTitles() {
    let defaultText = "default".localizedString
    let singleWhiteText = "single_white".localizedString
    let tunableWhiteText = "tunable_white".localizedString
    singleWhiteLabel.text = defaultValue == .singleWhite ? "\(singleWhiteText) (\(defaultText))" : singleWhiteText
    tunableWhiteLabel.text = defaultValue == .tunableWhite ? "\(tunableWhiteText) (\(defaultText))" : tunableWhiteText
}

private func updateOptionUI() {
    singleWhiteIconView.image = UIImage(named: selectedValue == .singleWhite ? "select" : "select_un")
    tunableWhiteIconView.image = UIImage(named: selectedValue == .tunableWhite ? "select" : "select_un")
}
```

- [ ] **Step 4: 替换 value changed action**

删除 `segmentValueChanged(_:)`，新增：

```swift
@objc private func optionTapped(_ sender: UIControl) {
    selectedValue = sender === singleWhiteButton ? .singleWhite : .tunableWhite
    updateOptionUI()
    delegate?.cell(self, didSelect: selectedValue)
}
```

- [ ] **Step 5: 更新启用隐藏逻辑**

把 `updateParameterEnable(enable:)` 中的 `segmentControl` 引用替换为 `optionsContainerView`：

```swift
enableSwitch.isOn = enable
optionsContainerView.isHidden = !enable
noteLabel.isHidden = !enable
```

启用时 note 约束改为：

```swift
noteLabel.snp.remakeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(optionsContainerView.snp.bottom).offset(SCRYFrom(14)).priority(.high)
    make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
}
```

禁用时 note 约束改为：

```swift
noteLabel.snp.remakeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(optionsContainerView.snp.bottom).offset(SCRYFrom(14)).priority(.high)
}
```

- [ ] **Step 6: 替换 `setupUI()` 中 segmented control 为 radio 选项条**

在标题和开关之后创建 `optionsContainerView`：

```swift
optionsContainerView = UIView()
optionsContainerView.backgroundColor = RGB(249, 250, 252)
optionsContainerView.layer.cornerRadius = SCRYFrom(7)
containerView.addSubview(optionsContainerView)
optionsContainerView.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20)).priority(.high)
    make.height.equalTo(SCRYFrom(40))
}
```

创建两个选项：

```swift
singleWhiteButton = UIControl()
singleWhiteButton.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
optionsContainerView.addSubview(singleWhiteButton)
singleWhiteButton.snp.makeConstraints { make in
    make.left.top.bottom.equalToSuperview()
    make.width.equalTo(optionsContainerView.snp.width).multipliedBy(0.5)
}

singleWhiteIconView = UIImageView(image: UIImage(named: "select_un"))
singleWhiteButton.addSubview(singleWhiteIconView)
singleWhiteIconView.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(8))
    make.centerY.equalToSuperview()
    make.width.height.equalTo(SCRYFrom(30))
}

singleWhiteLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
singleWhiteLabel.adjustsFontSizeToFitWidth = true
singleWhiteLabel.minimumScaleFactor = 0.75
singleWhiteButton.addSubview(singleWhiteLabel)
singleWhiteLabel.snp.makeConstraints { make in
    make.left.equalTo(singleWhiteIconView.snp.right).offset(SCRXFrom(2))
    make.right.lessThanOrEqualTo(SCRXFrom(-4))
    make.centerY.equalToSuperview()
}

tunableWhiteButton = UIControl()
tunableWhiteButton.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
optionsContainerView.addSubview(tunableWhiteButton)
tunableWhiteButton.snp.makeConstraints { make in
    make.right.top.bottom.equalToSuperview()
    make.width.equalTo(optionsContainerView.snp.width).multipliedBy(0.5)
}

tunableWhiteIconView = UIImageView(image: UIImage(named: "select_un"))
tunableWhiteButton.addSubview(tunableWhiteIconView)
tunableWhiteIconView.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(8))
    make.centerY.equalToSuperview()
    make.width.height.equalTo(SCRYFrom(30))
}

tunableWhiteLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
tunableWhiteLabel.adjustsFontSizeToFitWidth = true
tunableWhiteLabel.minimumScaleFactor = 0.75
tunableWhiteButton.addSubview(tunableWhiteLabel)
tunableWhiteLabel.snp.makeConstraints { make in
    make.left.equalTo(tunableWhiteIconView.snp.right).offset(SCRXFrom(2))
    make.right.lessThanOrEqualTo(SCRXFrom(-4))
    make.centerY.equalToSuperview()
}
```


- [ ] **Step 7: 调整 note 样式为 Figma 风格**

把 Change Control Page 的 note 改为左对齐、12 号：

```swift
noteLabel = UILabel(text: "change_control_page_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .regular, fit: false)
noteLabel.textAlignment = .left
noteLabel.numberOfLines = 0
```

- [ ] **Step 8: 静态验证 Change Control Page 不再使用 `UISegmentedControl`**

Run:

```bash
rg -n "DeviceParameterChangeControlPageViewCell|UISegmentedControl|optionsContainerView|singleWhiteButton|tunableWhiteButton|optionTapped" SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift
```

Expected: `DeviceParameterChangeControlPageViewCell` 中不再创建 `UISegmentedControl`，能看到 radio 选项控件。

- [ ] **Step 9: Commit Change Control Page UI**

```bash
git add SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift
git commit -m "feat: update change control page parameter ui"
```

---

### Task 4: 重做 Absolute CCT Range 启用后 UI 和 Reset

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`

- [ ] **Step 1: 扩展 Absolute CCT Range delegate**

把 `DeviceParameterAbsoluteCctRangeViewCellDelegate` 改为：

```swift
protocol DeviceParameterAbsoluteCctRangeViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterAbsoluteCctRangeViewCell, parameterEnableStateChanged enable: Bool)
    func cell(_ cell: DeviceParameterAbsoluteCctRangeViewCell, rangeChanged range: ClosedRange<UInt16>)
    func absoluteCctRangeViewCellResetAction(_ cell: DeviceParameterAbsoluteCctRangeViewCell)
}
```

- [ ] **Step 2: 替换 Absolute CCT Range cell 属性**

在 `DeviceParameterAbsoluteCctRangeViewCell` 中保留 `containerView`、`titleLabel`、`enableSwitch`、`noteLabel`、`lowerBound`、`upperBound`，并替换中间控件为：

```swift
private var resetBtn: UIButton!
private var sliderContentView: UIView!
private var lowerValueLabel: UILabel!
private var upperValueLabel: UILabel!
private var minusBtn: UIButton!
private var addBtn: UIButton!
private var cctRangeSlider: DeviceParameterCctRangeSlider!
```

- [ ] **Step 3: 更新 `configure` 支持默认范围**

把 `configure(range:enabled:)` 改为：

```swift
func configure(range: ClosedRange<UInt16>, enabled: Bool) {
    lowerBound = range.lowerBound
    upperBound = range.upperBound
    normalizeRange()
    updateValueLabels()
    cctRangeSlider.configure(range: lowerBound...upperBound)
    updateParameterEnable(enable: enabled)
}
```

- [ ] **Step 4: 更新启用隐藏逻辑**

在 `updateParameterEnable(enable:)` 中使用：

```swift
enableSwitch.isOn = enable
resetBtn.isHidden = !enable
sliderContentView.isHidden = !enable
noteLabel.isHidden = !enable
```

启用时 note 约束：

```swift
noteLabel.snp.remakeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(sliderContentView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
    make.bottom.equalTo(SCRYFrom(-20)).priority(.high)
}
```

禁用时 note 约束：

```swift
noteLabel.snp.remakeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(sliderContentView.snp.bottom).offset(SCRYFrom(16)).priority(.high)
}
```

- [ ] **Step 5: 替换加减和 reset action**

删除原有 lower/upper 两组加减 action，保留两个按钮 action：

```swift
@objc private func resetBtnAction() {
    delegate?.absoluteCctRangeViewCellResetAction(self)
}

@objc private func minusBtnClick() {
    cctRangeSlider.stepSelectedThumb(by: -Int(NodeAbsoluteCctRange.step))
}

@objc private func addBtnClick() {
    cctRangeSlider.stepSelectedThumb(by: Int(NodeAbsoluteCctRange.step))
}
```

- [ ] **Step 6: 重建 `setupUI()` 中间区域**

在开关之后增加 Reset：

```swift
resetBtn = UIButton(title: "reset".localizedString, titleSize: 12, titleWeight: .regular, titleColor: Bar_Color, target: self, action: #selector(resetBtnAction))
resetBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: SCRXFrom(8))
resetBtn.layer.cornerRadius = SCRYFrom(12)
resetBtn.layer.borderWidth = 0.5
resetBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.5).cgColor
resetBtn.isHidden = true
containerView.addSubview(resetBtn)
resetBtn.snp.makeConstraints { make in
    make.right.equalTo(enableSwitch.snp.left).offset(SCRXFrom(-24))
    make.centerY.equalTo(enableSwitch)
    make.height.equalTo(SCRYFrom(24))
    make.width.greaterThanOrEqualTo(SCRXFrom(48))
}
```

新增 slider 内容区域：

```swift
sliderContentView = UIView()
containerView.addSubview(sliderContentView)
sliderContentView.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20)).priority(.high)
    make.height.equalTo(SCRYFrom(76))
}

lowerValueLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
sliderContentView.addSubview(lowerValueLabel)
lowerValueLabel.snp.makeConstraints { make in
    make.left.top.equalToSuperview()
}

upperValueLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
upperValueLabel.textAlignment = .right
sliderContentView.addSubview(upperValueLabel)
upperValueLabel.snp.makeConstraints { make in
    make.right.top.equalToSuperview()
}

minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
sliderContentView.addSubview(minusBtn)
minusBtn.snp.makeConstraints { make in
    make.left.equalToSuperview()
    make.bottom.equalToSuperview()
    make.width.height.equalTo(SCRYFrom(30))
}

addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
sliderContentView.addSubview(addBtn)
addBtn.snp.makeConstraints { make in
    make.right.equalToSuperview()
    make.centerY.equalTo(minusBtn)
    make.width.height.equalTo(SCRYFrom(30))
}

cctRangeSlider = DeviceParameterCctRangeSlider()
cctRangeSlider.delegate = self
sliderContentView.addSubview(cctRangeSlider)
cctRangeSlider.snp.makeConstraints { make in
    make.left.equalTo(minusBtn.snp.right).offset(SCRXFrom(15))
    make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-15))
    make.centerY.equalTo(minusBtn)
    make.height.equalTo(SCRYFrom(40))
}
```

- [ ] **Step 7: 调整 note 样式为 Figma 风格**

把 Absolute CCT Range 的 note 改为左对齐、12 号：

```swift
noteLabel = UILabel(text: "absolute_cct_range_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .regular, fit: false)
noteLabel.textAlignment = .left
noteLabel.numberOfLines = 0
```

- [ ] **Step 8: 让 cell 接收 slider 回调**

在文件中增加：

```swift
extension DeviceParameterAbsoluteCctRangeViewCell: DeviceParameterCctRangeSliderDelegate {
    func cctRangeSlider(_ slider: DeviceParameterCctRangeSlider, rangeChanged range: ClosedRange<UInt16>) {
        lowerBound = range.lowerBound
        upperBound = range.upperBound
        updateValueLabels()
        delegate?.cell(self, rangeChanged: range)
    }
}
```

- [ ] **Step 9: 在 controller 中给 Reset 写回默认值**

在 `DeviceParameterSettingsController` 的 Absolute CCT delegate extension 中增加：

```swift
func absoluteCctRangeViewCellResetAction(_ cell: DeviceParameterAbsoluteCctRangeViewCell) {
    guard let indexPath = tableView.indexPath(for: cell) else {
        return
    }
    let data = defaultCctRangeDataForSelection
    absoluteCctRangeData = data
    parameterDatas[indexPath.row].data = data
    cell.configure(range: data.range, enabled: true)
    updateSetupBtnState()
}
```

- [ ] **Step 10: 静态验证 Absolute CCT Range UI**

Run:

```bash
rg -n "absoluteCctRangeViewCellResetAction|DeviceParameterCctRangeSlider|sliderContentView|resetBtn|scene_data_value_minus|scene_data_value_add" SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift
```

Expected: 能看到 Reset delegate、CCT slider、加减按钮和 controller reset 写回逻辑。

- [ ] **Step 11: Commit Absolute CCT Range UI**

```bash
git add SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift
git commit -m "feat: update absolute cct range parameter ui"
```

---

### Task 5: 更新 CCT 参数说明文案

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 查找现有 CCT 文案**

Run:

```bash
rg -n "change_control_page_message|absolute_cct_range_message" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 两个语言文件都已有这两个 key。

- [ ] **Step 2: 更新英文文案**

在 `SunSmart/en.lproj/Localizable.strings` 中把两个 key 改为：

```text
"change_control_page_message" = "Note: This device can be controlled as either a single-white or tunable-white light. Select the page that matches the connected luminaire. When Single White is selected, the app treats the device as brightness-only and hides CCT controls; group control capabilities are updated accordingly.";
"absolute_cct_range_message" = "Note: The device supports a wide color temperature range for different luminaires. If the connected luminaire cannot report or match its actual CCT range automatically, set the range manually. The app will limit CCT control to this range.";
```

- [ ] **Step 3: 更新中文文案**

在 `SunSmart/zh-Hans.lproj/Localizable.strings` 中把两个 key 改为：

```text
"change_control_page_message" = "注意：此设备可按单白光或可调白光灯具控制。请选择与实际连接灯具匹配的控制页面。选择单白光后，App 会将设备按仅亮度控制处理并隐藏色温控制；对应组控能力也会同步变化。";
"absolute_cct_range_message" = "注意：设备支持较宽的色温范围，以适配不同灯具。若连接的灯具无法反馈或自动匹配实际色温范围，需要手动设置。App 会将色温控制限制在该范围内。";
```

- [ ] **Step 4: 验证文案 key 仍唯一**

Run:

```bash
rg -n "change_control_page_message|absolute_cct_range_message" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 每个 key 在每个语言文件中各出现一次。

- [ ] **Step 5: Commit 本地化文案**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: update cct parameter descriptions"
```

---

### Task 6: 构建和回归验证

**Files:**
- Verify only

- [ ] **Step 1: 验证无 Figma 远程资源引用**

Run:

```bash
rg -n "figma.com/api/mcp|ffZ6mSpXLtHi3e7YdEmvMl|31:11665" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '*.swift' -g '*.strings'
```

Expected: 无结果。

- [ ] **Step 2: 验证特殊设备旧 company ID 不再残留**

Run:

```bash
rg -n "0x0178|0x0A78|0x2013" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '*.swift'
```

Expected: `0x0A78` 与 `0x2013` 出现在特殊设备判断中；`0x0178` 不应再出现在 CCT 特殊设备判断里。如果 `0x0178` 在无关业务中出现，确认它不与 `0x2013` 组成 CCT 默认值或 PWM 排除条件。

- [ ] **Step 3: 验证 slider 禁止区间相关实现存在**

Run:

```bash
rg -n "minLowerBound|maxLowerBound|minUpperBound|maxUpperBound|normalizedLower|normalizedUpper|lowerValue\\(for|upperValue\\(for|stepSelectedThumb" SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: 能看到 CCT 边界常量、归一化方法、位置映射和步进方法。

- [ ] **Step 4: 构建 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。该命令必须直接运行，不使用 `/bin/zsh -lc`，不重定向输出。

- [ ] **Step 5: SDK SwiftPM 测试说明**

如果本次仅修正 SDK `Node+Propertys.swift`，尝试运行：

```bash
swift test
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: 当前仓库已知 SwiftPM 环境会因为 `no such module 'UIKit'` 失败。若失败信息仍是 `MeshDeviceProvisioningManager.swift:8:8: error: no such module 'UIKit'`，记录为既有 SwiftPM 平台问题；不要把它当成本次 CCT UI 变更失败。

- [ ] **Step 6: 最终状态检查**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected:

- App 侧只剩用户已有的未提交项或本次明确不提交的文件。
- SDK 侧应为 clean，除非 Task 1 commit 因用户要求暂停。

---

## Spec Coverage Self-Review

| Spec 要求 | 覆盖任务 |
|---|---|
| Figma 中两个 CCT 参数组的 UI 效果 | Task 3、Task 4 |
| 特殊设备条件改为 `0x0A78 / 0x2013` | Task 1 |
| Change Control Page 文案和默认项按设备类型变化 | Task 3、Task 5 |
| Absolute CCT Range Reset 恢复设备类型默认值 | Task 4 |
| min 范围 `1000...2700K`，max 范围 `5000...10000K` | Task 2、Task 4 |
| `2700K` 和 `5000K` 可选，`(2700K, 5000K)` 不可选 | Task 2、Task 6 |
| 新建 `DeviceParameterCctRangeSlider` | Task 2 |
| 尽量复用现有控件和图片资源 | Task 2、Task 3、Task 4 |
| 不需要用户上传 images 资源 | Task 3、Task 4 |
| 保持现有保存、同步、下发逻辑 | Task 4、Task 6 |

Plan 自检结论：无占位符；无未覆盖 spec 项；新 delegate、方法名和 controller 回调一致。
