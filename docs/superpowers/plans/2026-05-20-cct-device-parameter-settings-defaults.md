# CCT Device Parameter Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `companyIdentifier == 0x0178 && productIdentifier == 0x2013` 的 CCT 设备增加特殊默认值，并在 Device Parameter Settings 中移除该设备的 PWM frequency。

**Architecture:** 默认值放在本地 `NordicSigMeshSDK` 的 `Node` 属性层，业务入口继续使用 `effectiveChangeControlPage`、`effectiveSupportCct`、`effectiveCctRange`。App 侧只负责基于同一默认规则展示 `Default` 文案，并在 `supportPwmFrequency` 层排除特殊 PID，让读取、设置、列表、筛选入口自然一致。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、CocoaPods workspace、xcodebuild。

---

## Scope Check

本计划只覆盖一个 Device Parameter Settings 默认值优化，不拆分子项目。它依赖上一轮 CCT 参数持久化和控制逻辑已存在，不重新实现云同步、下发、组控或 Scene/Profile clamp。

## File Structure

| 文件 | 责任 |
| --- | --- |
| `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` | 增加特殊 PID 判断，并让 CCT 默认值按设备类型返回 |
| `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` | 在 `supportPwmFrequency` 中排除 `0x0178/0x2013` |
| `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift` | Device Parameter Settings 打开开关、冲突回退、cell 配置时使用设备类型默认值 |
| `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift` | Change Control Page segmented control 显示 `Default` 后缀 |

---

### Task 1: SDK 默认值规则

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`

- [ ] **Step 1: 定位现有 CCT 默认值**

Run:

```bash
rg -n "NodeAbsoluteCctRange|effectiveChangeControlPage|effectiveCctRange|effectiveSupportCct" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: 找到 `NodeAbsoluteCctRange.defaultRange`、`effectiveChangeControlPage`、`effectiveCctRange`、`effectiveSupportCct`。

- [ ] **Step 2: 修改 `NodeAbsoluteCctRange` 默认范围声明**

在 `public struct NodeAbsoluteCctRange` 中保留现有约束常量，并把默认范围拆成标准默认和特殊 PID 默认：

```swift
public struct NodeAbsoluteCctRange {
    public static let standardDefaultRange: ClosedRange<UInt16> = LightCTL_TemperatureRange.min...LightCTL_TemperatureRange.max
    public static let singleWhiteDefaultRange: ClosedRange<UInt16> = 2700...5000
    public static let defaultRange: ClosedRange<UInt16> = standardDefaultRange
    public static let minLowerBound: UInt16 = 1000
    public static let maxLowerBound: UInt16 = 2700
    public static let minUpperBound: UInt16 = 5000
    public static let maxUpperBound: UInt16 = 10000
    public static let step: UInt16 = 100
}
```

- [ ] **Step 3: 增加 `Node` 默认值封装**

在 `public extension Node` 中、`rawSupportCct` 附近增加：

```swift
var isSingleWhiteDefaultCctProduct: Bool {
    companyIdentifier == 0x0178 && productIdentifier == 0x2013
}

var defaultChangeControlPage: NodeChangeControlPage {
    isSingleWhiteDefaultCctProduct ? .singleWhite : .tunableWhite
}

var defaultAbsoluteCctRange: ClosedRange<UInt16> {
    isSingleWhiteDefaultCctProduct ? NodeAbsoluteCctRange.singleWhiteDefaultRange : NodeAbsoluteCctRange.standardDefaultRange
}
```

- [ ] **Step 4: 更新 `effective*` 读取逻辑**

把现有实现改成配置值优先，未配置时走设备类型默认值：

```swift
var effectiveChangeControlPage: NodeChangeControlPage {
    changeControlPage ?? defaultChangeControlPage
}

var effectiveSupportCct: Bool {
    rawSupportCct && effectiveChangeControlPage != .singleWhite
}

var effectiveCctRange: ClosedRange<UInt16> {
    absoluteCctRange ?? defaultAbsoluteCctRange
}
```

- [ ] **Step 5: 静态检查默认值调用点**

Run:

```bash
rg -n "NodeAbsoluteCctRange\\.defaultRange|\\.effectiveChangeControlPage|\\.effectiveCctRange|\\.effectiveSupportCct" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK SunSmart -g '*.swift'
```

Expected: App 侧控制、组控、场景和参数页仍主要通过 `effective*` 读取；`NodeAbsoluteCctRange.defaultRange` 只保留在通用 UI 初始化或标准默认回退处。

- [ ] **Step 6: Commit SDK 默认规则**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add cct product defaults"
```

---

### Task 2: App 参数可见性与默认值回退

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`

- [ ] **Step 1: 排除特殊 PID 的 PWM frequency 支持**

在 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` 的 `supportPwmFrequency` 中，`guard` 之后、`switch pid` 之前加入：

```swift
if companyIdentifier == 0x0178 && pid == 0x2013 {
    return false
}
```

Expected: 参数设置页、读取参数、参数列表和筛选入口都会通过现有 `supportPwmFrequency` 返回 false 隐藏 PWM。

- [ ] **Step 2: 在 Settings Controller 增加选择集合默认值**

在 `DeviceParameterSettingsController` 的属性区域增加两个计算属性：

```swift
private var defaultChangeControlPageForSelection: NodeChangeControlPage {
    devices.first?.defaultChangeControlPage ?? .tunableWhite
}

private var defaultCctRangeDataForSelection: DeviceParameterCctRangeData {
    DeviceParameterCctRangeData(range: devices.first?.defaultAbsoluteCctRange ?? NodeAbsoluteCctRange.defaultRange)
}
```

- [ ] **Step 3: 初始化 CCT 参数时使用设备类型默认值**

在 `viewDidLoad` 中 `if node.rawSupportCct` 分支内，把追加参数前的 CCT 默认数据更新为：

```swift
if node.rawSupportCct {
    changeControlPage = defaultChangeControlPageForSelection
    absoluteCctRangeData = defaultCctRangeDataForSelection
    parameterDatas.append(.init(type: .changeControlPage, data: changeControlPage, enable: false))
    parameterDatas.append(.init(type: .absoluteCctRange, data: absoluteCctRangeData, enable: false))
}
```

- [ ] **Step 4: Cell 回退值使用设备类型默认值**

在 `cellForRowAt` 的两个 CCT case 中调整 fallback：

```swift
case .changeControlPage:
    let cell = tableView.dequeueReusableCell(withIdentifier: "changeControlPageCell", for: indexPath) as! DeviceParameterChangeControlPageViewCell
    let value = parameterData.data as? NodeChangeControlPage ?? defaultChangeControlPageForSelection
    cell.configure(value: value, enabled: parameterData.enable, defaultValue: defaultChangeControlPageForSelection)
    cell.delegate = self
    return cell
case .absoluteCctRange:
    let cell = tableView.dequeueReusableCell(withIdentifier: "absoluteCctRangeCell", for: indexPath) as! DeviceParameterAbsoluteCctRangeViewCell
    let range = (parameterData.data as? DeviceParameterCctRangeData)?.range ?? defaultCctRangeDataForSelection.range
    cell.configure(range: range, enabled: parameterData.enable)
    cell.delegate = self
    return cell
```

- [ ] **Step 5: 开关打开时冲突回退使用设备类型默认值**

在 `DeviceParameterChangeControlPageViewCellDelegate` 中更新 enable 分支：

```swift
if enable {
    let value = uniformValue(devices.map({ $0.effectiveChangeControlPage }), defaultValue: defaultChangeControlPageForSelection)
    changeControlPage = value
    data.data = value
    cell.configure(value: value, enabled: true, defaultValue: defaultChangeControlPageForSelection)
}
```

在 `DeviceParameterAbsoluteCctRangeViewCellDelegate` 中更新 enable 分支：

```swift
if enable {
    let value = uniformValue(devices.map({ DeviceParameterCctRangeData(range: $0.effectiveCctRange) }), defaultValue: defaultCctRangeDataForSelection)
    absoluteCctRangeData = value
    data.data = value
    cell.configure(range: value.range, enabled: true)
}
```

- [ ] **Step 6: 编译前静态检查**

Run:

```bash
rg -n "defaultChangeControlPageForSelection|defaultCctRangeDataForSelection|configure\\(value: .*defaultValue|companyIdentifier == 0x0178 && pid == 0x2013" SunSmart -g '*.swift'
```

Expected: 能看到 Settings Controller 的默认回退、Change Control Page cell 配置调用和 PWM 特殊排除。

- [ ] **Step 7: Commit App 默认回退和 PWM 可见性**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift
git commit -m "feat: apply cct product defaults"
```

---

### Task 3: Change Control Page 默认文案

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`

- [ ] **Step 1: 扩展 Change Control Page cell 的 configure 签名**

在 `DeviceParameterChangeControlPageViewCell` 中，把现有 `configure(value:enabled:)` 改为：

```swift
func configure(value: NodeChangeControlPage, enabled: Bool, defaultValue: NodeChangeControlPage) {
    configureSegmentTitles(defaultValue: defaultValue)
    segmentControl.selectedSegmentIndex = value == .singleWhite ? 0 : 1
    updateParameterEnable(enable: enabled)
}
```

- [ ] **Step 2: 增加 segmented control 文案 helper**

在 `DeviceParameterChangeControlPageViewCell` 中增加：

```swift
private func configureSegmentTitles(defaultValue: NodeChangeControlPage) {
    let defaultText = "default".localizedString
    let singleWhiteText = "single_white".localizedString
    let tunableWhiteText = "tunable_white".localizedString
    let singleWhiteTitle = defaultValue == .singleWhite ? "\(singleWhiteText) (\(defaultText))" : singleWhiteText
    let tunableWhiteTitle = defaultValue == .tunableWhite ? "\(tunableWhiteText) (\(defaultText))" : tunableWhiteText
    segmentControl.setTitle(singleWhiteTitle, forSegmentAt: 0)
    segmentControl.setTitle(tunableWhiteTitle, forSegmentAt: 1)
}
```

- [ ] **Step 3: 保持初始化文案为标准默认**

在 `setupUI()` 中创建 `segmentControl` 后保留标准默认标题即可：

```swift
segmentControl = UISegmentedControl(items: ["single_white".localizedString, "tunable_white".localizedString])
```

Expected: cell 被 `configure` 后才根据当前 PID 显示 `Default` 后缀；复用 cell 时也会重新设置标题。

- [ ] **Step 4: 检查所有调用点都传入默认值**

Run:

```bash
rg -n "configure\\(value: .*enabled:" SunSmart/Main/Device/Parameter -g '*.swift'
```

Expected: `DeviceParameterChangeControlPageViewCell` 的调用点都包含 `defaultValue:` 参数。

- [ ] **Step 5: Commit 文案展示**

```bash
git add SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift
git commit -m "feat: show cct default option labels"
```

---

### Task 4: 验证与收尾

**Files:**
- Read: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Read: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
- Read: `SunSmart/Main/Device/Parameter/View/DeviceParameterSettingsViewCell.swift`
- Read: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`

- [ ] **Step 1: 检查无 enabled 持久化回归**

Run:

```bash
rg -n "changeControlPageEnabled|absoluteCctRangeEnabled|enabled.*Cct|Cct.*Enabled" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '*.swift'
```

Expected: 无匹配。

- [ ] **Step 2: 检查特殊 PID 默认规则只在封装层和 PWM 支持层出现**

Run:

```bash
rg -n "0x0178|0x2013|isSingleWhiteDefaultCctProduct|singleWhiteDefaultRange|standardDefaultRange" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '*.swift'
```

Expected: 特殊 PID 判断出现在 SDK `Node` 默认值封装和 App `supportPwmFrequency` 排除处；Settings Controller 只读取默认值封装。

- [ ] **Step 3: 检查 App 编译**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 检查 SDK 测试现状**

Run:

```bash
swift test
```

Workdir: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected: 如果仍因既有 `UIKit` 依赖报 `no such module 'UIKit'`，在最终说明中明确记录该 SDK 测试环境限制；如果通过，记录通过结果。

- [ ] **Step 5: 最终 git 状态检查**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: App 工作区只剩用户已有的未提交文件或本任务已提交内容；SDK 工作区干净或只包含本任务已提交内容。

