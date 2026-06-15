# Up/Down Ratio Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task in this repository. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `0x0A78 / 0x2491` 单设备控制页新增 Up/Down Ratio 滑条控件，并把 up ratio 永久保存到本地 `Node.PreConfiguration`。

**Architecture:** 新增独立 `DeviceUpDownRatioControlView`，复用 `BuoySliderView` / `CustomDeviceSlider` 的滑动和浮窗能力。页面层只对 `0x0A78 / 0x2491` 展示控件，接收 `valueChanging` / `valueChanged` 事件，当前只更新本地 `node.upRatio` 并持久化，不发送 Mesh/vendor 命令。

**Tech Stack:** UIKit, SnapKit, SQLite.swift, NordicSigMeshSDK `Node` extension, Xcode project target source membership.

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - 给 `Node.PreConfiguration` 增加 `upRatio` 字段。
  - 给 `Node` 增加 `upRatio` get/set，本地默认值为 `50`，取值 clamp 到 `0...100`。
- Modify: `SunSmart/Common/Data/Database.swift`
  - 给 `node_preConfiguration` 表增加 `upRatio` 列。
  - 读取和保存 `Node.PreConfiguration.upRatio`。
- Modify: `SunSmart/Common/Data/Node+Capability.swift`
  - 增加 `supportsUpDownRatioControl`，只匹配 `0x0A78 / 0x2491`。
- Modify: `SunSmart/Main/Group/View/BuoySliderView.swift`
  - 增加可选 `valueTextProvider`，默认保持现有 `value + unit` 展示。
- Create: `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`
  - 独立 ratio 控件，包含 title/value label、slider、quick buttons 和事件。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 对目标 PID 插入 ratio 控件。
  - 按目标设备和非目标设备分别设置布局约束。
  - 页面接线事件，当前只保存本地 `upRatio`。
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - 将新 Swift 文件加入 Device/View 分组。
  - 将新 Swift 文件加入与 `DeviceLightControlPanelView.swift` 相同的 4 个 target source phase。

---

### Task 1: 增加本地 upRatio 存储

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Common/Data/Database.swift`

- [ ] **Step 1: 在 `Node.PreConfiguration` 加字段和 `Node.upRatio` 访问器**

In `SunSmart/Common/Data/Node+SyncData.swift`, update `Node.PreConfiguration` and add the `Node.upRatio` property near `preConfiguration`:

```swift
extension Node {
    
    static var preConfigurationKey: UInt8 = 0
    private static let defaultUpRatio = 50
    
    /// 设备预配置数据
    class PreConfiguration: Codable {
        /// 白天profile lux阈值
        var dayProfileStartsAboveLux: UInt16?
        /// 晚上profile lux阈值
        var nightProfileStartsBelowLux: UInt16?
        /// 白天profile灯光数据（暂未使用）
        var dayProfileLightData: Profile.LightControlData?
        /// 晚上profile灯光数据（暂未使用）
        var nightProfileLightData: Profile.LightControlData?
        /// 是否重置光感校准数据
        var resetDaylightCalibration: Bool?
        /// 是否显示lux（光感设备在设备页面）
        var displayLux: Bool = false
        /// Up/Down Ratio 中 up 的比例，本地永久存储，不参与云同步。
        var upRatio: Int?
    }
    
    /// 设备预配置数据
    var preConfiguration: PreConfiguration {
        get {
            var preConfiguration = objc_getAssociatedObject(self, &Node.preConfigurationKey) as? PreConfiguration
            if preConfiguration == nil {
                if let uuid = self.network?.uuid.uuidString {
                    
                    preConfiguration = Node.PreConfiguration.load(meshUUID: uuid, nodeAddress: self.primaryUnicastAddress) ?? PreConfiguration()
                }else {
                    preConfiguration = PreConfiguration()
                }
                self.preConfiguration = preConfiguration!
            }
            return preConfiguration!
        }set  {
            objc_setAssociatedObject(self, &Node.preConfigurationKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var upRatio: Int {
        get {
            let value = preConfiguration.upRatio ?? Self.defaultUpRatio
            return max(0, min(100, value))
        }
        set {
            preConfiguration.upRatio = max(0, min(100, newValue))
        }
    }
    
    var downRatio: Int {
        100 - upRatio
    }
```

- [ ] **Step 2: 在本地数据库表增加 `upRatio` 列**

In `SunSmart/Common/Data/Database.swift`, update `Node.PreConfiguration.ExpressionKey`:

```swift
struct ExpressionKey {
    static let id = Expression<Int64>("id")
    static let meshUUID = Expression<String>("meshUUID")
    static let nodeAddress = Expression<Int>("nodeAddress")
    static let dayProfileStartsAboveLux = Expression<Int?>("dayProfileStartsAboveLux")
    static let dayProfileLightData = Expression<Data?>("dayProfileLightData")
    static let nightProfileStartsBelowLux = Expression<Int?>("nightProfileStartsBelowLux")
    static let nightProfileLightData = Expression<Data?>("nightProfileLightData")
    static let resetDaylightCalibration = Expression<Bool?>("resetDaylightCalibration")
    static let occupancyEnable = Expression<Bool>("occupancyEnable")
    static let displayLux = Expression<Bool>("displayLux")
    static let upRatio = Expression<Int?>("upRatio")
}
```

In the `create` builder, add the column after `displayLux`:

```swift
builder.column(ExpressionKey.displayLux)
builder.column(ExpressionKey.upRatio)
builder.unique(ExpressionKey.meshUUID, ExpressionKey.nodeAddress)
```

In the schema migration block, add:

```swift
// 是否存在”upRatio“属性
if !columns.contains(where: { $0.name == "upRatio" }) {
    _ = try? SunSmartDataManager.shared.db?.run(Node.PreConfiguration.nodePreConfigurationTable.addColumn(ExpressionKey.upRatio, defaultValue: 50))
}
```

- [ ] **Step 3: 读取和保存 `upRatio`**

In `Node.PreConfiguration.load(meshUUID:nodeAddress:)`, after `displayLux`:

```swift
preConfiguration.displayLux = row[ExpressionKey.displayLux]
preConfiguration.upRatio = row[ExpressionKey.upRatio]
return preConfiguration
```

In `Node.PreConfiguration.save(meshUUID:nodeAddress:)`, add `upRatio` to the insert list:

```swift
ExpressionKey.resetDaylightCalibration <- self.resetDaylightCalibration,
ExpressionKey.displayLux <- self.displayLux,
ExpressionKey.upRatio <- self.upRatio.map { max(0, min(100, $0)) }
```

- [ ] **Step 4: 静态检查本地存储未进入云同步**

Run:

```bash
rg -n "upRatio|downRatio" SunSmart/Common/Data
```

Expected:

- `Node+SyncData.swift` contains `upRatio` and `downRatio`.
- `Database.swift` contains the `node_preConfiguration` column, load, and save changes.
- `ExportData.swift` and `ImportData.swift` do not contain `upRatio` or `downRatio`.

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Database.swift
git commit -m "feat: store up down ratio locally"
```

---

### Task 2: 增加目标设备能力判断

**Files:**
- Modify: `SunSmart/Common/Data/Node+Capability.swift`

- [ ] **Step 1: 增加 `supportsUpDownRatioControl`**

Append this to the existing `extension Node` in `SunSmart/Common/Data/Node+Capability.swift`:

```swift
    var supportsUpDownRatioControl: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x2491
    }
```

The resulting file should still have one `extension Node` block.

- [ ] **Step 2: 检查 PID gate**

Run:

```bash
rg -n "supportsUpDownRatioControl|0x2491|0x1502|1502" SunSmart/Common/Data/Node+Capability.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift docs/superpowers/specs/260613_1013_up_down_ratio_control_design.md
```

Expected:

- `supportsUpDownRatioControl` uses `0x2491`.
- No `0x1502` or bare `1502` appears in these files.

- [ ] **Step 3: Commit**

```bash
git add SunSmart/Common/Data/Node+Capability.swift
git commit -m "feat: gate up down ratio control by pid"
```

---

### Task 3: 扩展 `BuoySliderView` 的 value 文案格式化

**Files:**
- Modify: `SunSmart/Main/Group/View/BuoySliderView.swift`

- [ ] **Step 1: 添加 formatter 属性和 helper**

In `SunSmart/Main/Group/View/BuoySliderView.swift`, add this property near the callbacks:

```swift
    var valueTextProvider: ((Int) -> String)?
```

Add this helper inside `BuoySliderView`:

```swift
    private func valueText(_ value: Int) -> String {
        valueTextProvider?(value) ?? "\(value)\(unit)"
    }
```

- [ ] **Step 2: 替换固定 value 文案**

Replace the `value` setter body with:

```swift
    var value: Int {
        get {
            return Int(slider.value)
        }set {
            slider.value = Float(newValue)
            valueLabel.text = valueText(Int(slider.value))
        }
    }
```

Replace `sliderTouchDownAction()` with:

```swift
    @objc private func sliderTouchDownAction() {
        UIView.animate(withDuration: 0.3) {
            self.buoyImageView.alpha = 1
        }
        valueLabel.text = valueText(Int(slider.value))
    }
```

In `slider(_:valueChanged:ended:)`, replace:

```swift
valueLabel.text = "\(Int(value))\(unit)"
```

with:

```swift
valueLabel.text = valueText(Int(value))
```

- [ ] **Step 3: 检查默认行为不变**

Run:

```bash
rg -n "valueTextProvider|valueText\\(" SunSmart/Main/Group/View/BuoySliderView.swift
```

Expected:

- One `valueTextProvider` property.
- One `valueText(_:)` helper.
- The `value` setter, touch-down handler, and value-changed delegate call all use `valueText(...)`.

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Main/Group/View/BuoySliderView.swift
git commit -m "feat: allow custom slider value text"
```

---

### Task 4: 新增 `DeviceUpDownRatioControlView`

**Files:**
- Create: `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: 创建 ratio 控件文件**

Create `SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift` with this content:

```swift
//
//  DeviceUpDownRatioControlView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/13.
//

import UIKit

final class DeviceUpDownRatioControlView: UIView {

    var valueChanging: ((Int) -> Void)?
    var valueChanged: ((Int) -> Void)?

    var upValue: Int {
        get {
            currentUpValue
        }
        set {
            setUpValue(newValue, notifyChanging: false, notifyChanged: false)
        }
    }

    var downValue: Int {
        100 - upValue
    }

    private let titleLabel = UILabel(text: "Up/Down Ratio", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
    private let valueLabel = UILabel(text: "50/50", textColor: RGB(46, 49, 93), fontSize: 14, fontWeight: .light)
    private let sliderView = BuoySliderView(frame: .zero, functionType: .level())
    private let quickButtonsView = UpDownRatioQuickButtonsView()

    private var currentUpValue = 50
    private var suppressCallbacks = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        bindActions()
        setUpValue(50, notifyChanging: false, notifyChanged: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }

        valueLabel.textAlignment = .right
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
        }

        sliderView.slider.minimumValue = 0
        sliderView.slider.maximumValue = 100
        sliderView.slider.step = 1
        sliderView.slider.limitRange = 0...100
        sliderView.slider.minimumTrackTintColor = Slider_Color
        sliderView.slider.maximumTrackTintColor = RGB(229, 229, 229)
        sliderView.valueTextProvider = { value in
            "\(value)/\(100 - value)"
        }
        addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFit(4))
            make.height.equalTo(SCRYFrom(40))
        }

        addSubview(quickButtonsView)
        quickButtonsView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(sliderView.snp.bottom).offset(SCRYFit(8))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalToSuperview()
        }
    }

    private func bindActions() {
        sliderView.valueChangedCallback = { [weak self] value in
            self?.setUpValue(value, notifyChanging: true, notifyChanged: false)
        }

        sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
            guard ended else { return }
            self?.setUpValue(value, notifyChanging: false, notifyChanged: true)
        }

        quickButtonsView.valueSelected = { [weak self] value in
            self?.setUpValue(value, notifyChanging: true, notifyChanged: true)
        }
    }

    private func setUpValue(_ value: Int, notifyChanging: Bool, notifyChanged: Bool) {
        let clampedValue = max(0, min(100, value))
        currentUpValue = clampedValue

        UIView.performWithoutAnimation {
            sliderView.value = clampedValue
            valueLabel.text = ratioText(upValue: clampedValue)
            quickButtonsView.configure(selectedValue: clampedValue)
            layoutIfNeeded()
        }

        guard !suppressCallbacks else { return }
        if notifyChanging {
            valueChanging?(clampedValue)
        }
        if notifyChanged {
            valueChanged?(clampedValue)
        }
    }

    private func ratioText(upValue: Int) -> String {
        "\(upValue)/\(100 - upValue)"
    }
}

private final class UpDownRatioQuickButtonsView: UIView {

    var valueSelected: ((Int) -> Void)?

    private let stackView = UIStackView()
    private let values = [100, 75, 50, 25, 0]
    private var buttons: [UIButton] = []
    private var selectedValue: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        configure(selectedValue: 50)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(selectedValue: Int) {
        self.selectedValue = values.contains(selectedValue) ? selectedValue : nil

        UIView.performWithoutAnimation {
            buttons.enumerated().forEach { index, button in
                let value = values[index]
                let isSelected = value == self.selectedValue
                button.backgroundColor = isSelected ? RGB(102, 103, 171) : .white
                button.layer.borderColor = isSelected ? RGB(102, 103, 171).cgColor : RGB(236, 236, 236).cgColor
                button.setTitleColor(isSelected ? .white : RGB(102, 103, 171), for: .normal)
                button.layoutIfNeeded()
            }
        }
    }

    private func setupUI() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = SCRXFrom(10)
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        values.enumerated().forEach { index, value in
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = FONTS(SCRYFrom(12))
            button.layer.cornerRadius = SCRYFrom(16)
            button.layer.borderWidth = 1
            button.setTitle("\(value)/\(100 - value)", for: .normal)
            button.addTarget(self, action: #selector(buttonClick(sender:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            button.snp.makeConstraints { make in
                make.width.equalTo(SCRXFrom(56))
                make.height.equalTo(SCRYFrom(32))
            }
            buttons.append(button)
        }
    }

    @objc private func buttonClick(sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        valueSelected?(values[sender.tag])
    }
}
```

- [ ] **Step 2: 检查控件是否包含所有接口**

Run:

```bash
rg -n "var upValue|var downValue|valueChanging|valueChanged|100, 75, 50, 25, 0|Up/Down Ratio" SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift
```

Expected:

- The file exposes `upValue`, `downValue`, `valueChanging`, and `valueChanged`.
- The quick values are exactly `[100, 75, 50, 25, 0]`.
- The title is exactly `Up/Down Ratio`.

- [ ] **Step 3: 添加 Xcode project 引用**

In `SunSmart.xcodeproj/project.pbxproj`, add one `PBXFileReference`, four `PBXBuildFile` entries, the file in the `Device/View` group, and one source membership per existing target that already includes `DeviceLightControlPanelView.swift`.

Use IDs that do not already exist. This plan reserves:

```text
C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */
C8D1C0112F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */
C8D1C0122F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */
C8D1C0132F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */
C8D1C0142F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */
```

Add near the other `PBXBuildFile` entries:

```pbxproj
		C8D1C0112F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */; };
		C8D1C0122F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */; };
		C8D1C0132F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */; };
		C8D1C0142F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */; };
```

Add near the other `PBXFileReference` entries:

```pbxproj
		C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeviceUpDownRatioControlView.swift; sourceTree = "<group>"; };
```

Add in the `C898EA6D2AC2D59C0023B480 /* View */` group immediately after `DeviceLightControlPanelView.swift`:

```pbxproj
				C8D1C0102F10000000000001 /* DeviceUpDownRatioControlView.swift */,
```

Add the four source memberships immediately after each existing `DeviceLightControlPanelView.swift in Sources` line:

```pbxproj
				C8D1C0112F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */,
```

```pbxproj
				C8D1C0122F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */,
```

```pbxproj
				C8D1C0132F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */,
```

```pbxproj
				C8D1C0142F10000000000001 /* DeviceUpDownRatioControlView.swift in Sources */,
```

- [ ] **Step 4: 检查 target membership**

Run:

```bash
rg -n "DeviceUpDownRatioControlView.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected:

- 1 `PBXFileReference`.
- 4 `PBXBuildFile` entries.
- 1 group child.
- 4 source phase memberships.
- Total lines containing `DeviceUpDownRatioControlView.swift`: 10.

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add up down ratio control view"
```

---

### Task 5: 接入 `DeviceLightViewController`

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: 增加属性**

Near `private var controlPanelView: DeviceLightControlPanelView!`, add:

```swift
    private var upDownRatioView: DeviceUpDownRatioControlView!
```

- [ ] **Step 2: 在 `setupUI()` 创建并约束 ratio view**

After creating `controlPanelView`, add:

```swift
        upDownRatioView = DeviceUpDownRatioControlView()
        upDownRatioView.isHidden = true
        contentView.addSubview(upDownRatioView)
```

Replace the existing `onoffBtn.snp.makeConstraints` and `controlPanelView.snp.makeConstraints` blocks with:

```swift
        onoffBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if isIPad {
                make.width.height.equalTo(56)
            }
            if node.supportsUpDownRatioControl {
                make.top.equalTo(upDownRatioView.snp.bottom).offset(SCRYFit(40))
            } else {
                make.top.equalTo(lightImageBtn.snp.bottom).offset(SCRYFit(isIPad ? 250 : 190))
            }
        }

        upDownRatioView.snp.makeConstraints { make in
            make.top.equalTo(brightnessView.snp.bottom).offset(SCRYFit(20))
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.equalTo(SCRXFrom(30))
                make.right.equalTo(SCRXFrom(-29))
            }
        }

        controlPanelView.snp.makeConstraints { make in
            make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(node.supportsUpDownRatioControl ? 16 : (isIPad ? 80 : 30)))
            make.bottom.equalToSuperview().offset(SCRYFit(-8))
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            }else {
                make.left.equalTo(SCRXFrom(30))
                make.right.equalTo(SCRXFrom(-29))
            }
        }
```

- [ ] **Step 3: 在 `updateData(refreshControlPanel:)` 同步 ratio 值**

After `cctLabel.text = "\(node.temperature)K"`:

```swift
            upDownRatioView.upValue = node.upRatio
```

- [ ] **Step 4: 在 `setupEmergencySignUI()` 和 `updateEmergencySignData()` 隐藏 ratio view**

In both methods, next to `controlPanelView.isHidden = true`, add:

```swift
        upDownRatioView.isHidden = true
```

- [ ] **Step 5: 在 `bindSliderAction()` 接线 ratio events**

At the end of `bindSliderAction()`, add:

```swift
        upDownRatioView.valueChanging = { [weak self] value in
            self?.node.upRatio = value
        }
        upDownRatioView.valueChanged = { [weak self] value in
            guard let self = self else { return }
            self.node.upRatio = value
            if let meshUUID = self.node.network?.uuid.uuidString {
                self.node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: self.node.primaryUnicastAddress)
            }
        }
```

- [ ] **Step 6: 在 `updateUI()` 控制显示**

Before `controlPanelView.isHidden = !node.supportDimming && !node.singleDeviceDisplaySupportCct`, add:

```swift
        upDownRatioView.isHidden = !node.supportsUpDownRatioControl
```

- [ ] **Step 7: 检查没有发送设备命令**

Run:

```bash
rg -n "upDownRatioView|upRatio|supportsUpDownRatioControl|MeshAPI|SunricherVendor" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected:

- `upDownRatioView` is configured and connected.
- `upRatio` is saved through `preConfiguration.save(...)`.
- No `MeshAPI` or `SunricherVendor` call appears inside the new ratio event closures.

- [ ] **Step 8: Commit**

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: show up down ratio on target light"
```

---

### Task 6: 验证构建和范围

**Files:**
- Verify only.

- [ ] **Step 1: 检查旧 PID 没有残留**

Run:

```bash
rg -n "0x1502|1502" SunSmart/Main/Device SunSmart/Common/Data docs/superpowers/specs/260613_1013_up_down_ratio_control_design.md docs/superpowers/plans/260613_1022_up_down_ratio_control_implementation_plan.md
```

Expected:

- No output for the new ratio feature paths.
- Existing unrelated `devices_config.json` entries are not part of this command.

- [ ] **Step 2: 检查云同步边界**

Run:

```bash
rg -n "upRatio|downRatio" SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift SunSmart/Common/Data/SpaceData.swift SunSmart/Common/Network
```

Expected: no output.

- [ ] **Step 3: 检查新文件 target membership**

Run:

```bash
rg -n "DeviceUpDownRatioControlView.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected: 10 matching lines.

- [ ] **Step 4: 检查 whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- If build fails due to missing CocoaPods generated xcconfig or xcfilelist files, run `pod install` from the worktree root, then rerun the same iPhoneOS build command.

- [ ] **Step 6: Final commit if verification required fixes**

If verification required code changes after Task 5, commit those fixes:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/Node+Capability.swift SunSmart/Main/Group/View/BuoySliderView.swift SunSmart/Main/Device/View/DeviceUpDownRatioControlView.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: verify up down ratio control"
```

If Task 6 required no changes, do not create an empty commit.

---

## Self-Review

- Spec coverage: covered target PID `0x2491`, independent ratio view, title/value behavior, slider range, quick buttons, selected state, local permanent storage, no server sync, page event reservation, layout constraints, and iPhoneOS build verification.
- Placeholder scan: no `TBD`, `TODO`, or open-ended implementation steps.
- Type consistency: `upRatio`, `downRatio`, `supportsUpDownRatioControl`, `valueTextProvider`, `DeviceUpDownRatioControlView`, `valueChanging`, and `valueChanged` are named consistently across tasks.
