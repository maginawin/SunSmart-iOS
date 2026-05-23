# CCT Device Parameter Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Device Parameter Settings 中为真实支持 CCT 的 PID 设备增加 Change Control Page 和 Absolute CCT Range，并让 App 侧控制、展示、场景与云同步全部使用有效 CCT 能力。

**Architecture:** 先在本地 NordicSigMeshSDK 的 `Node` 属性层新增两个持久化字段和有效能力封装，再在 App 的导入导出、设备参数同步和控制入口统一接入。Change Control Page 是本地参数，保存即成功；Absolute CCT Range 通过 `LightCTLTemperatureRangeSet` 下发成功后写本地，并由 `effectiveCctRange` 影响所有 CCT UI 和下发前 clamp。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SQLite.swift、本地 JSON 导入导出、Xcode workspace 构建。

---

## 文件结构

**SDK 属性与数据库**

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`

**App 数据同步与 JSON**

- Modify: `SunSmart/Common/Data/ExportData.swift`
- Modify: `SunSmart/Common/Data/ImportData.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

**Device Parameter Settings**

- Modify: `SunSmart/Main/Device/Parameter/Model/DeviceParameterData.swift`
- Create: `SunSmart/Main/Device/Parameter/Model/DeviceParameterCctRangeData.swift`
- Create: `SunSmart/Main/Device/Parameter/View/DeviceParameterChangeControlPageViewCell.swift`
- Create: `SunSmart/Main/Device/Parameter/View/DeviceParameterAbsoluteCctRangeViewCell.swift`
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift`
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterFilterView.swift`
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

**CCT 控制入口**

- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightBasicController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
- Modify: `SunSmart/Main/Device/View/DeviceLightControlView.swift`
- Modify: `SunSmart/Main/Device/View/DeviceLightHeaderView.swift`
- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`
- Modify: `SunSmart/Main/Group/View/BuoySliderView.swift`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Modify: `SunSmart/Main/Group/Model/GroupServer.swift`
- Modify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
- Modify: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`
- Modify: `SunSmart/Main/Scene/Controller/ScenesViewController.swift`
- Modify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`
- Modify: `SunSmart/Main/Scene/View/SceneAddDataListViewCell.swift`
- Modify: `SunSmart/Main/Scene/View/SceneGroupsViewCell.swift`
- Modify: `SunSmart/Main/Profile/View/ProfilePowerUpBehaviorView.swift`
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

---

### Task 0: 依赖和工作区预检查

**Files:**
- Verify: `SunSmart.xcodeproj/project.pbxproj`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

- [ ] **Step 1: 确认 App 使用本地 NordicSigMeshSDK**

Run:

```bash
rg -n "relativePath = \"/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk\"|XCRemoteSwiftPackageReference \"nordic-sig-mesh-sdk\"" SunSmart.xcodeproj/project.pbxproj
```

Expected: `project.pbxproj` 中 `nordic-sig-mesh-sdk` package reference 指向本地 `relativePath`，这样 SDK 修改会参与 App 构建。

- [ ] **Step 2: 记录当前两个仓库状态**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: 只记录状态，不清理用户未跟踪或未提交文件。

---

### Task 1: SDK CCT 配置属性与有效能力

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`

- [ ] **Step 1: 新增 CCT 配置类型和默认范围**

在 `Node+Propertys.swift` 的 `LightCTL_TemperatureRange` 附近新增：

```swift
public enum NodeChangeControlPage: String, Codable {
    case singleWhite
    case tunableWhite
}

public struct NodeAbsoluteCctRange {
    public static let defaultRange: ClosedRange<UInt16> = LightCTL_TemperatureRange.min...LightCTL_TemperatureRange.max
    public static let minLowerBound: UInt16 = 1000
    public static let maxLowerBound: UInt16 = 2700
    public static let minUpperBound: UInt16 = 5000
    public static let maxUpperBound: UInt16 = 10000
    public static let step: UInt16 = 100
}
```

- [ ] **Step 2: 新增 Node 持久化属性和有效能力 helper**

在 `AssociatedKeys` 增加 `changeControlPage`、`absoluteCctRange` 两个 key，并在 `public extension Node` 中增加：

```swift
var rawSupportCct: Bool {
    temperatureModel != nil
}

var changeControlPage: NodeChangeControlPage? {
    get { objc_getAssociatedObject(self, &AssociatedKeys.changeControlPage) as? NodeChangeControlPage }
    set { objc_setAssociatedObject(self, &AssociatedKeys.changeControlPage, newValue, .OBJC_ASSOCIATION_RETAIN) }
}

var absoluteCctRange: ClosedRange<UInt16>? {
    get { objc_getAssociatedObject(self, &AssociatedKeys.absoluteCctRange) as? ClosedRange<UInt16> }
    set { objc_setAssociatedObject(self, &AssociatedKeys.absoluteCctRange, newValue, .OBJC_ASSOCIATION_RETAIN) }
}

var effectiveChangeControlPage: NodeChangeControlPage {
    changeControlPage ?? .tunableWhite
}

var effectiveSupportCct: Bool {
    rawSupportCct && effectiveChangeControlPage != .singleWhite
}

var effectiveCctRange: ClosedRange<UInt16> {
    absoluteCctRange ?? NodeAbsoluteCctRange.defaultRange
}

func clampEffectiveCct(_ value: UInt16) -> UInt16 {
    min(effectiveCctRange.upperBound, max(effectiveCctRange.lowerBound, value))
}

func getEffectiveTemperature(temperature100: Int) -> UInt16 {
    Node.getTemperature(temperature100: temperature100, range: effectiveCctRange)
}

func getEffectiveTemperature100(temperature: UInt16) -> Int {
    Node.getTemperature100(temperature: temperature, range: effectiveCctRange)
}
```

同时把 `temperature` getter/setter、`temperature100`、`getTemperature(temperature100:)`、`getTemperature100(temperature:)` 改为使用 `effectiveCctRange`，保证旧入口即使未逐一改完也不会越界。

- [ ] **Step 3: 新增 SQLite 字段声明**

在 `MeshDatabase.swift` 的 `PropertyExpressionKey` 增加：

```swift
static let changeControlPage = Expression<String?>("changeControlPage")
static let absoluteCctRangeMin = Expression<Int?>("absoluteCctRangeMin")
static let absoluteCctRangeMax = Expression<Int?>("absoluteCctRangeMax")
```

在 `nodePropertysTable.create` block 中增加三列。

- [ ] **Step 4: 新增数据库迁移**

在现有 `phaseEnergyConsumptions`、`motionSensitivityRange` 这类 column 检查附近增加：

```swift
if !columns.contains(where: { $0.name == "changeControlPage" }) {
    _ = try? database?.run(Node.nodePropertysTable.addColumn(PropertyExpressionKey.changeControlPage))
}
if !columns.contains(where: { $0.name == "absoluteCctRangeMin" }) {
    _ = try? database?.run(Node.nodePropertysTable.addColumn(PropertyExpressionKey.absoluteCctRangeMin))
}
if !columns.contains(where: { $0.name == "absoluteCctRangeMax" }) {
    _ = try? database?.run(Node.nodePropertysTable.addColumn(PropertyExpressionKey.absoluteCctRangeMax))
}
```

- [ ] **Step 5: 读写数据库字段**

在 node property load 逻辑中增加：

```swift
if let rawValue = row[PropertyExpressionKey.changeControlPage] {
    self.changeControlPage = NodeChangeControlPage(rawValue: rawValue)
}
if let min = row[PropertyExpressionKey.absoluteCctRangeMin],
   let max = row[PropertyExpressionKey.absoluteCctRangeMax],
   min < max {
    self.absoluteCctRange = UInt16(min)...UInt16(max)
}
```

在 `savePropertys()` 的 insert/update 字段中增加：

```swift
PropertyExpressionKey.changeControlPage <- self.changeControlPage?.rawValue,
PropertyExpressionKey.absoluteCctRangeMin <- self.absoluteCctRange.map { Int($0.lowerBound) },
PropertyExpressionKey.absoluteCctRangeMax <- self.absoluteCctRange.map { Int($0.upperBound) },
```

- [ ] **Step 6: 运行 SDK 测试**

Run:

```bash
swift test
```

Workdir: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected: SwiftPM 测试通过，或现有无关测试失败被记录到本任务结果中。

- [ ] **Step 7: Commit**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add cct parameter persistence"
```

---

### Task 2: App JSON 导入导出与删除清理

**Files:**
- Modify: `SunSmart/Common/Data/ExportData.swift`
- Modify: `SunSmart/Common/Data/ImportData.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: 导出 node JSON 新字段**

在两个 node 导出路径中，紧跟 `lightCTLTemperatureRangeMin/Max` 或 `ratedPowerPhases` 写入处增加：

```swift
if let changeControlPage = node.changeControlPage {
    nodeDict.updateValue(changeControlPage.rawValue, forKey: "changeControlPage")
}
if let range = node.absoluteCctRange {
    nodeDict.updateValue(range.lowerBound, forKey: "absoluteCctRangeMin")
    nodeDict.updateValue(range.upperBound, forKey: "absoluteCctRangeMax")
}
```

确认 `Node.export` 路径里的 `self` 版本也写同样字段。

- [ ] **Step 2: 导入 node JSON 新字段**

在 `ImportData.swift` 两处读取 node 扩展属性的位置，紧跟 `lightCTLTemperatureRangeMin/Max` 后增加：

```swift
if let rawValue = nodeJson["changeControlPage"].string {
    node.changeControlPage = NodeChangeControlPage(rawValue: rawValue)
}
if let min = nodeJson["absoluteCctRangeMin"].uInt16,
   let max = nodeJson["absoluteCctRangeMax"].uInt16,
   min < max {
    node.absoluteCctRange = min...max
}
```

如果字段不存在，不写属性，让 `effectiveChangeControlPage` 和 `effectiveCctRange` 走默认值。

- [ ] **Step 3: 删除设备时清理配置**

在 `MeshNetwork+SunSmart.swift` 的 `Node.deleteExtension()` 中，删除网关缓存后增加：

```swift
changeControlPage = nil
absoluteCctRange = nil
savePropertys()
```

这个清理只影响业务扩展数据；底层 Mesh Composition Data 不变。

- [ ] **Step 4: Restore 复制新配置**

在 `DeviceRestoreViewController.swift` 中 `newNode.lightCTLTemperatureRange = oldNode.lightCTLTemperatureRange` 附近增加：

```swift
newNode.changeControlPage = oldNode.changeControlPage
newNode.absoluteCctRange = oldNode.absoluteCctRange
```

设备恢复是旧设备配置转移流程，不等同删除后重新添加；这里复制配置可以保持用户已确认的设备参数。

- [ ] **Step 5: Build 验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 构建通过。

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "feat: sync cct parameters in node json"
```

---

### Task 3: DeviceParameterType 与同步结果

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

- [ ] **Step 1: 新增 Absolute CCT Range 参数类型**

在 `DeviceParameterType` 增加：

```swift
case absoluteCctRange(range: ClosedRange<UInt16>)
```

`rawValue` 使用 `6`。`getMessageHandles(node:)` 增加：

```swift
case .absoluteCctRange(let range):
    if let ctlModel = node.ctlModel, node.rawSupportCct {
        messageHandles.append(MeshMessageHandle(message: LightCTLTemperatureRangeSet(range), model: ctlModel))
    }
```

Change Control Page 不进入 `DeviceParameterType`，因为它不下发设备，也不需要失败重试。

- [ ] **Step 2: SyncDevicesViewController 展示任务**

在 `.devicesParameter` 和 `.deviceParameterTypes` 两个 switch 中加入：

```swift
case .absoluteCctRange(let range):
    let taskModel = SyncDeviceStepTaskModel(name: "absolute_cct_range".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .absoluteCctRange(range: range))))
    let step = SyncDeviceStepModel(type: "absolute_cct_range".localizedString, state: .none, tasks: [taskModel])
    taskModel.parentStepModel = step
    steps.append(step)
```

在 `.deviceParameterTypes` 聚合任务处使用同名 `taskModel`，添加到 `tasks`。

- [ ] **Step 3: 成功后写本地**

在 `MeshNetwork+SunSmart.swift` 的 `Node.updateData(message:isSuccess:)` 增加：

```swift
case is LightCTLTemperatureRangeSet:
    guard isSuccess else { return }
    let message = message as! LightCTLTemperatureRangeSet
    absoluteCctRange = message.range
    lightCTLTemperatureRange = message.range
    temperature = clampEffectiveCct(temperature)
    savePropertys()
```

这样 `SyncDevicesViewController` 根据发送请求成功回调即可落本地，和 ratedPower 的 “发送成功后本地数据可验证” 模型保持一致。

- [ ] **Step 4: 成功判定扩展**

在 `SyncDevicesCellModel.swift` 和 `EmerFireAlarmSyncCellModel.swift` 的 `DeviceParameterType.isSuccessful(node:)` 加入：

```swift
case .absoluteCctRange(let range):
    return node.absoluteCctRange == range
```

- [ ] **Step 5: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 枚举 switch 覆盖完整，无编译错误。

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
git commit -m "feat: add absolute cct range sync parameter"
```

---

### Task 4: Device Parameter Settings UI 与保存逻辑

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/Model/DeviceParameterData.swift`
- Create: `SunSmart/Main/Device/Parameter/Model/DeviceParameterCctRangeData.swift`
- Create: `SunSmart/Main/Device/Parameter/View/DeviceParameterChangeControlPageViewCell.swift`
- Create: `SunSmart/Main/Device/Parameter/View/DeviceParameterAbsoluteCctRangeViewCell.swift`
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 增加参数类型和标题文案**

在 `DeviceParameterData.ParameterType` 增加：

```swift
case changeControlPage
case absoluteCctRange
```

`rawValue` 使用 `6`、`7`。`data` 返回：

```swift
case .changeControlPage:
    return ("change_control_page".localizedString, "change_control_page_message".localizedString, nil, "")
case .absoluteCctRange:
    return ("absolute_cct_range".localizedString, "absolute_cct_range_message".localizedString, nil, "K")
```

- [ ] **Step 2: 新增范围编辑模型**

创建 `DeviceParameterCctRangeData.swift`：

```swift
import Foundation
import NordicSigMeshSDK

struct DeviceParameterCctRangeData: Equatable {
    var lowerBound: UInt16
    var upperBound: UInt16

    static let `default` = DeviceParameterCctRangeData(range: NodeAbsoluteCctRange.defaultRange)

    init(range: ClosedRange<UInt16>) {
        lowerBound = range.lowerBound
        upperBound = range.upperBound
    }

    var range: ClosedRange<UInt16> {
        lowerBound...upperBound
    }
}
```

- [ ] **Step 3: 创建 Change Control Page cell**

创建 `DeviceParameterChangeControlPageViewCell.swift`，结构沿用现有参数卡片样式：白色 container、标题、`UISwitch`、两个横向按钮或 `UISegmentedControl`。公开接口：

```swift
protocol DeviceParameterChangeControlPageViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterChangeControlPageViewCell, parameterEnableStateChanged enable: Bool)
    func cell(_ cell: DeviceParameterChangeControlPageViewCell, didSelect value: NodeChangeControlPage)
}

final class DeviceParameterChangeControlPageViewCell: UITableViewCell {
    weak var delegate: DeviceParameterChangeControlPageViewCellDelegate?
    func configure(value: NodeChangeControlPage, enabled: Bool)
}
```

分段选项显示 `Single White`、`Tunable White`，默认选 `Tunable White`。

- [ ] **Step 4: 创建 Absolute CCT Range cell**

创建 `DeviceParameterAbsoluteCctRangeViewCell.swift`，结构沿用灵敏度范围卡片：标题、`UISwitch`、两个值按钮、说明文案。公开接口：

```swift
protocol DeviceParameterAbsoluteCctRangeViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterAbsoluteCctRangeViewCell, parameterEnableStateChanged enable: Bool)
    func cell(_ cell: DeviceParameterAbsoluteCctRangeViewCell, rangeChanged range: ClosedRange<UInt16>)
}

final class DeviceParameterAbsoluteCctRangeViewCell: UITableViewCell {
    weak var delegate: DeviceParameterAbsoluteCctRangeViewCellDelegate?
    func configure(range: ClosedRange<UInt16>, enabled: Bool)
}
```

下限可选 `1000...2700`，上限可选 `5000...10000`，步进 `100`。如果用户选到非法组合，立即把下限限制为小于上限，且显示当前合法值。

- [ ] **Step 5: SettingsController 初始化默认值和参数展示**

在 `DeviceParameterSettingsController` 增加：

```swift
private var changeControlPage: NodeChangeControlPage = .tunableWhite
private var absoluteCctRangeData: DeviceParameterCctRangeData = .default
```

`viewDidLoad` 中如果 `devices.first?.rawSupportCct == true`，在普通参数列表末尾追加：

```swift
parameterDatas.append(.init(type: .changeControlPage, data: changeControlPage, enable: false))
parameterDatas.append(.init(type: .absoluteCctRange, data: absoluteCctRangeData, enable: false))
```

- [ ] **Step 6: 打开开关时按单设备/一致/冲突预填**

在 `DeviceParameterSettingsController` 增加 helper：

```swift
private func uniformValue<T: Equatable>(_ values: [T], defaultValue: T) -> T {
    guard let first = values.first, values.allSatisfy({ $0 == first }) else {
        return defaultValue
    }
    return first
}
```

打开 Change Control Page 开关时：

```swift
let values = devices.map { $0.effectiveChangeControlPage }
changeControlPage = uniformValue(values, defaultValue: .tunableWhite)
data.data = changeControlPage
```

打开 Absolute CCT Range 开关时：

```swift
let values = devices.map { DeviceParameterCctRangeData(range: $0.effectiveCctRange) }
absoluteCctRangeData = uniformValue(values, defaultValue: .default)
data.data = absoluteCctRangeData
```

关闭开关只改变 `data.enable`，不清空设备已有配置。

- [ ] **Step 7: 保存时拆分本地参数和下发参数**

在 `setupAction()` 构造参数时：

```swift
var localSuccessResults: [ParameterSettingsResultItem] = []
var setParameters: [DeviceParameterType] = []
```

Change Control Page 开关打开时对所有设备执行：

```swift
devices.forEach {
    $0.changeControlPage = changeControlPage
    $0.temperature = $0.clampEffectiveCct($0.temperature)
    _ = $0.savePropertys()
}
NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
localSuccessResults.append(.init(parameterType: .changeControlPage, parameter: nil, successNodes: devices, failedNodes: []))
```

Absolute CCT Range 开关打开时追加：

```swift
setParameters.append(.absoluteCctRange(range: absoluteCctRangeData.range))
```

`ParameterSettingsResultItem.parameter` 改为 `DeviceParameterType?`，因为 Change Control Page 没有 mesh 参数。

- [ ] **Step 8: 仅本地参数时直接完成**

如果 `setParameters.isEmpty && !localSuccessResults.isEmpty`，显示成功、回调 `settingsCompletionCallback?(localSuccessResults)`，然后 pop 回设备列表。

如果同时有下发参数，保留现有 `SyncDevicesViewController`，其回调结果和 `localSuccessResults` 合并后传给上层。

- [ ] **Step 9: 本地化文案**

在英文和简体中文 Localizable 中加入：

```text
"change_control_page" = "Change Control Page";
"change_control_page_message" = "Choose how this CCT-capable device is shown and controlled in the app.";
"single_white" = "Single White";
"tunable_white" = "Tunable White";
"absolute_cct_range" = "Absolute CCT Range";
"absolute_cct_range_message" = "Set the absolute color temperature range supported by this device.";
"minimum_cct" = "Minimum CCT";
"maximum_cct" = "Maximum CCT";
```

简体中文对应为：

```text
"change_control_page" = "控制页面类型";
"change_control_page_message" = "选择此 CCT 设备在 App 中按单白光或可调白光展示和控制。";
"single_white" = "单白光";
"tunable_white" = "可调白光";
"absolute_cct_range" = "绝对色温范围";
"absolute_cct_range_message" = "设置此设备支持的绝对色温范围。";
"minimum_cct" = "最低色温";
"maximum_cct" = "最高色温";
```

- [ ] **Step 10: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 构建通过。

- [ ] **Step 11: Commit**

```bash
git add SunSmart/Main/Device/Parameter/Model/DeviceParameterData.swift SunSmart/Main/Device/Parameter/Model/DeviceParameterCctRangeData.swift SunSmart/Main/Device/Parameter/View/DeviceParameterChangeControlPageViewCell.swift SunSmart/Main/Device/Parameter/View/DeviceParameterAbsoluteCctRangeViewCell.swift SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add cct parameter settings ui"
```

---

### Task 5: 设备参数列表展示、筛选和失败重试

**Files:**
- Modify: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift`
- Modify: `SunSmart/Main/Device/Parameter/View/DeviceParameterFilterView.swift`

- [ ] **Step 1: 增加临时展示属性**

在 `DeviceParameterDevicesViewController.swift` 底部 `extension Node` 增加：

```swift
static var tempChangeControlPageKey: UInt8 = 0
static var tempAbsoluteCctRangeKey: UInt8 = 0

var tempChangeControlPage: NodeChangeControlPage {
    get { objc_getAssociatedObject(self, &Node.tempChangeControlPageKey) as? NodeChangeControlPage ?? effectiveChangeControlPage }
    set { objc_setAssociatedObject(self, &Node.tempChangeControlPageKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
}

var tempAbsoluteCctRange: ClosedRange<UInt16> {
    get { objc_getAssociatedObject(self, &Node.tempAbsoluteCctRangeKey) as? ClosedRange<UInt16> ?? effectiveCctRange }
    set { objc_setAssociatedObject(self, &Node.tempAbsoluteCctRangeKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
}
```

- [ ] **Step 2: 初始化和保存回调更新临时值**

`viewDidLoad` 遍历设备时，如果 `node.rawSupportCct`：

```swift
node.tempChangeControlPage = node.effectiveChangeControlPage
node.tempAbsoluteCctRange = node.effectiveCctRange
```

`settingsCompletionCallback` 成功分支增加：

```swift
case .changeControlPage:
    node.tempChangeControlPage = node.effectiveChangeControlPage
case .absoluteCctRange:
    node.tempAbsoluteCctRange = node.effectiveCctRange
```

失败分支只会记录 Absolute CCT Range；Change Control Page 不会进入失败。

- [ ] **Step 3: 列表 cell 显示两项**

`DeviceParameterDeviceCell` 增加两个 row view，并在 `ParameterDisplayItem` 列表追加：

```swift
let changeControlPageText = "\("change_control_page".localizedString): \(device.tempChangeControlPage == .singleWhite ? "single_white".localizedString : "tunable_white".localizedString)"
let absoluteCctRangeText = "\("absolute_cct_range".localizedString): \(device.tempAbsoluteCctRange.lowerBound)K~\(device.tempAbsoluteCctRange.upperBound)K"
```

两项 `isSupported` 使用 `device.rawSupportCct`。

- [ ] **Step 4: 筛选支持新参数**

在 `DeviceParameterFilterView.ParameterType` 增加 `changeControlPage`、`absoluteCctRange`，图标名使用本地已有参数图标或复用 `"absolute_sensitivity"` 图标。

在 `DeviceParameterDevicesViewController.setupFilterData()` 收集 CCT 选项：

```swift
changeControlPages.append(node.tempChangeControlPage)
absoluteCctRanges.append(node.tempAbsoluteCctRange)
```

在 `promptViewFilterAction` 中新增两个 filter data，筛选逻辑分别比较 `tempChangeControlPage` 和 `tempAbsoluteCctRange`。

- [ ] **Step 5: 重试回调兼容可选 parameter**

由于 `ParameterSettingsResultItem.parameter` 改为可选，`settingsCompletionCallback` 的失败分支改为：

```swift
guard let type = item.parameter else { return }
```

成功分支继续按 `parameterType` 更新临时显示。

- [ ] **Step 6: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 构建通过，设备参数列表可显示新字段。

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift SunSmart/Main/Device/Parameter/View/DeviceParameterFilterView.swift
git commit -m "feat: show cct parameters in device parameter list"
```

---

### Task 6: 设备页、组控和批量控制使用有效 CCT

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightBasicController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
- Modify: `SunSmart/Main/Device/View/DeviceLightControlView.swift`
- Modify: `SunSmart/Main/Device/View/DeviceLightHeaderView.swift`
- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`
- Modify: `SunSmart/Main/Group/View/BuoySliderView.swift`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Modify: `SunSmart/Main/Group/Model/GroupServer.swift`

- [ ] **Step 1: Group 有效 CCT helper**

在 `MeshNetwork+SunSmart.swift` 的 `extension Group` 中新增：

```swift
var effectiveSupportCct: Bool {
    nodes.contains(where: { $0.effectiveSupportCct })
}

var effectiveCctRange: ClosedRange<UInt16> {
    let ranges = nodes.filter { $0.effectiveSupportCct }.map { $0.effectiveCctRange }
    guard let first = ranges.first else {
        return NodeAbsoluteCctRange.defaultRange
    }
    return ranges.reduce(first) { result, range in
        min(result.lowerBound, range.lowerBound)...max(result.upperBound, range.upperBound)
    }
}

func clampEffectiveCct(_ value: UInt16) -> UInt16 {
    min(effectiveCctRange.upperBound, max(effectiveCctRange.lowerBound, value))
}
```

把 `Group.cct` 的统计过滤条件从 `temperatureModel != nil` 改为 `effectiveSupportCct`，把 `supportCct` getter 改为返回 `effectiveSupportCct`。

- [ ] **Step 2: 单设备控制页替换能力判断**

在 `DeviceLightViewController.swift`：

- `node.temperatureModel != nil` 改为 `node.effectiveSupportCct`。
- 初始化 `cctSlider` 的 range 改为 `node.effectiveCctRange`。
- `valueChangedCallback` 和 `valueThrottleChangedCallback` 下发前使用 `node.clampEffectiveCct(UInt16(value))`。
- 背景色和 Header 百分比使用 `node.getEffectiveTemperature100(temperature: node.temperature)`。

- [ ] **Step 3: 基础控制页替换百分比换算**

在 `DeviceLightBasicController.swift`：

- row count 使用 `node.effectiveSupportCct ? 2 : 1`。
- CCT cell 展示使用 `node.getEffectiveTemperature100(temperature:)`。
- `.cct` 操作使用 `node.getEffectiveTemperature(temperature100:)`。
- Scene 显示中的 `Node.getTemperature100(..., range: node.lightCTLTemperatureRange ?? node.defalutLightCTLTemperatureRange)` 改为 `node.getEffectiveTemperature100(temperature:)`。

- [ ] **Step 4: 批量灯控视图支持范围**

在 `BuoySliderView.swift` 增加：

```swift
func updateCctRange(_ range: ClosedRange<UInt16>) {
    slider.minimumValue = Float(range.lowerBound)
    slider.maximumValue = Float(range.upperBound)
    value = min(Int(range.upperBound), max(Int(range.lowerBound), value))
}
```

在 `DeviceLightControlView` 增加：

```swift
func updateCctRange(_ range: ClosedRange<UInt16>) {
    cctSliderView.updateCctRange(range)
}
```

在 `DeviceLightsViewController.swift`：

- `devices.contains(where: { $0.temperatureModel != nil })` 改为 `devices.contains(where: { $0.effectiveSupportCct })`。
- 计算有效 CCT 设备范围并集后传给 `lightControlView.updateCctRange(range)`。
- 批量下发时只给 `effectiveSupportCct` 的设备发送 CCT，并按每台设备 `clampEffectiveCct`。

- [ ] **Step 5: 组控页使用组有效能力**

在 `GroupViewController.swift`：

- `group.nodes.contains(where: { $0.temperatureModel != nil })` 改为 `group.effectiveSupportCct`。
- 初始化 `cctSlider` 使用 `group.effectiveCctRange`。
- 滑动下发前 `group.cct = Int(group.clampEffectiveCct(UInt16(value)))`。

在 `GroupServer.swift`：

- `if let ctlModel = node.ctlModel, node.temperatureModel != nil` 改为 `if let ctlModel = node.ctlModel, node.effectiveSupportCct`。
- `LightCTLSet` 的 temperature 使用 `node.clampEffectiveCct(data.cct)`。
- Single White 设备走 lightness 或 on/off 分支。

- [ ] **Step 6: 列表和 Header 展示**

在 `DeviceLightHeaderView.swift`、`DevicesViewCell.swift`、`DeviceInformationViewController.swift` 中：

- `temperatureModel != nil` 改为 `effectiveSupportCct`。
- `temperature100` 改为 `getEffectiveTemperature100(temperature:)`。
- Scene 信息里的 CCT 百分比按 `effectiveCctRange` 计算。

- [ ] **Step 7: 查漏 grep**

Run:

```bash
rg -n "temperatureModel != nil|lightCTLTemperatureRange \\?\\?|temperature100" SunSmart/Main/Device SunSmart/Main/Group SunSmart/Common/Data -g '*.swift'
```

Expected: 剩余命中都是“读取设备真实能力”的场景，例如添加设备读取 `LightCTLTemperatureRangeGet`；控制/展示入口不再直接用这些旧判断。

- [ ] **Step 8: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 构建通过。

- [ ] **Step 9: Commit**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Device/View/DeviceLightControlView.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Group/View/BuoySliderView.swift SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Model/GroupServer.swift
git commit -m "feat: apply effective cct controls"
```

---

### Task 7: Scene、Profile 和 Power Up CCT clamp

**Files:**
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Modify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
- Modify: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`
- Modify: `SunSmart/Main/Scene/Controller/ScenesViewController.swift`
- Modify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`
- Modify: `SunSmart/Main/Scene/View/SceneAddDataListViewCell.swift`
- Modify: `SunSmart/Main/Scene/View/SceneGroupsViewCell.swift`
- Modify: `SunSmart/Main/Profile/View/ProfilePowerUpBehaviorView.swift`
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

- [ ] **Step 1: Scene 同步消息 clamp**

在 `Node+MessageHandles.swift` 的 `Scene.getSyncMessageHandles(node:data:)` 中：

```swift
let cct = node.clampEffectiveCct(UInt16(data.cct))
if let ctlModel = node.ctlModel, node.effectiveSupportCct {
    messageHandles.append(MeshMessageHandle(message: LightCTLSet(lightness: lightness, temperature: cct, deltaUV: 0, transitionTime: .immediate, delay: 0), model: ctlModel))
}
```

Single White 设备不发送 CTL，只保存亮度或开关。

- [ ] **Step 2: SceneStore 缓存使用有效能力**

在 `MeshNetwork+SunSmart.swift` 的 `Node.updateData(message:isSuccess:)` 中处理 `SceneStore` 的分支：

- `if self.temperatureModel == nil` 改为 `if !self.effectiveSupportCct`。
- 保存的 `cct` 使用 `clampEffectiveCct(cct)`。

- [ ] **Step 3: Scene picker 支持传入 CCT range**

在 `SceneExecuteDataPickerView.show` 增加参数：

```swift
cctRange: ClosedRange<UInt16> = NodeAbsoluteCctRange.defaultRange
```

实例保存 `private var cctRange = NodeAbsoluteCctRange.defaultRange`，初始化 `DeviceSliderFunctionView` 时：

```swift
cctSliderView = DeviceSliderFunctionView(frame: .zero, title: "", value: min(Int(cctRange.upperBound), max(Int(cctRange.lowerBound), cct)), functionType: .cct(min: Int(cctRange.lowerBound), max: Int(cctRange.upperBound)))
```

- [ ] **Step 4: Scene 设置页传入组有效范围**

在 `SceneSettingsViewController.swift`、`SceneAddViewController.swift` 调用 `SceneExecuteDataPickerView.show` 时，按当前 group 传入 `group.effectiveCctRange`。保存 `SceneExecuteData` 前用 `group.clampEffectiveCct(UInt16(cct))`。

执行场景 preview 时，`MeshAPI.setGroupCTLState` 的 temperature 用 `group.clampEffectiveCct(UInt16(data.cct))`。

- [ ] **Step 5: Scene 列表展示颜色使用有效范围**

`SceneAddDataListViewCell` 和 `SceneGroupsViewCell` 当前使用 `SceneExecuteData.cctRange`。改为 cell 接收 `cctRange` 或 `Group`，使用 `Node.getTemperature100(temperature: UInt16(sceneData.cct), range: group.effectiveCctRange)`。

旧数据不改写，只展示时 clamp 计算颜色。

- [ ] **Step 6: Power Up 视图支持范围**

在 `ProfilePowerUpBehaviorView` 增加：

```swift
var cctRange: ClosedRange<UInt16> = NodeAbsoluteCctRange.defaultRange {
    didSet {
        cctSliderView.slider.minimumValue = Float(cctRange.lowerBound)
        cctSliderView.slider.maximumValue = Float(cctRange.upperBound)
        cctSliderView.slider.value = min(Float(cctRange.upperBound), max(Float(cctRange.lowerBound), cctSliderView.slider.value))
    }
}
```

默认 `4500` 改为 clamp 到当前范围。

- [ ] **Step 7: Profile 保存下发前 clamp**

在 `ProfileSettingsViewController.swift` 设置 `selectProfile.powerUpCct` 前，按当前 profile 目标 group 的 `effectiveCctRange` clamp。`ProfileType.powerOnState` 产生的消息在 `Node+MessageHandles.swift` 里也按 `node.clampEffectiveCct(defaultCct)` 处理。

- [ ] **Step 8: 查漏 grep**

Run:

```bash
rg -n "SceneExecuteData\\.cctRange|LightCTL_TemperatureRange\\.min|LightCTL_TemperatureRange\\.max|setGroupCTLState\\(|LightCTLSet\\(" SunSmart/Main/Scene SunSmart/Main/Profile SunSmart/Common/Data -g '*.swift'
```

Expected: Scene/Profile 入口不再使用固定 `2700...6500` 做用户输入或下发范围；保留默认常量的地方只用于无上下文默认值。

- [ ] **Step 9: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 构建通过。

- [ ] **Step 10: Commit**

```bash
git add SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift SunSmart/Main/Scene/Controller/SceneAddViewController.swift SunSmart/Main/Scene/Controller/ScenesViewController.swift SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift SunSmart/Main/Scene/View/SceneAddDataListViewCell.swift SunSmart/Main/Scene/View/SceneGroupsViewCell.swift SunSmart/Main/Profile/View/ProfilePowerUpBehaviorView.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
git commit -m "feat: clamp scene and profile cct"
```

---

### Task 8: 最终验证

**Files:**
- Verify only

- [ ] **Step 1: 全局旧判断查漏**

Run:

```bash
rg -n "temperatureModel != nil|node\\.temperature100|lightCTLTemperatureRange \\?\\?|SceneExecuteData\\.cctRange|LightCTL_TemperatureRange\\.(min|max)" SunSmart -g '*.swift'
```

Expected: 剩余命中属于真实能力读取、设备添加读取范围、SDK 默认常量定义、或明确无上下文默认值；把每个剩余命中写入最终验证记录。

- [ ] **Step 2: 检查 enabled/disabled 没有被持久化**

Run:

```bash
rg -n "changeControlPageEnabled|absoluteCctRangeEnabled|enabled.*Cct|Cct.*Enabled" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '*.swift'
```

Expected: 没有新增持久化 enabled 字段。

- [ ] **Step 3: 检查 JSON 字段名**

Run:

```bash
rg -n "changeControlPage|absoluteCctRangeMin|absoluteCctRangeMax" SunSmart/Common/Data /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK -g '*.swift'
```

Expected: App 导入导出、SDK 本地属性保存读取均有命中。

- [ ] **Step 4: SDK 测试**

Run:

```bash
swift test
```

Workdir: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

Expected: SwiftPM 测试通过，或记录现有无关失败。

- [ ] **Step 5: App 构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 构建通过。

- [ ] **Step 6: 手动验证清单**

在真机或可连 Mesh 环境中验证：

- 真实 CCT PID 设备进入 Device Parameter Settings 时展示两个新参数。
- 非 CCT PID 设备不展示两个新参数。
- 两个参数开关默认关闭；关闭保存不修改已有值。
- 单设备打开开关展示该设备值；多设备值一致展示共同值；多设备冲突展示默认值。
- Change Control Page 设为 Single White 后，单设备页、组控、批量控制、设备列表不再展示该设备 CCT 能力。
- Absolute CCT Range 下发成功后，设备页滑条范围、组控范围并集、Scene/Profile 输入范围都受限制。
- Absolute CCT Range 下发失败时，该设备本地值不变，失败设备进入现有失败重试入口。
- 云同步失败时，本地值保留，`needUploadCloud` 仍可由现有入口重试。
- 删除设备后重新添加同设备，两个配置回到默认值。

- [ ] **Step 7: 最终提交状态**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: 只有用户明确保留的未跟踪文件；实现相关改动都已提交。
