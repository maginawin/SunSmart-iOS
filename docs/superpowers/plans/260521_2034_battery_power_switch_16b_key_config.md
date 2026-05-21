# Battery Power Switch 16B Key Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 battery power switch 按键配置升级为 v1.0.22 16B wire，并移除按每个 profile client model 配置 publication retransmit 的耗时流程。

**Architecture:** 以本地 `NordicSigMeshSDK` 作为协议边界，SDK 负责 typed 16B 编解码，App 继续通过 `SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(...))` 发送配置。App 同步流程只保留 BPS Key Config 和 target group subscription，不再生成 BPS Model Publication step。

**Tech Stack:** Swift、NordicSigMeshSDK Swift Package、UIKit App、Xcode workspace、SwiftPM XCTest。

---

## 文件结构

- 修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`：用测试锁定 16B SET 编码和 16B GET status 解析。
- 修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`：扩展 action type 到 `0x10`，让 `BatteryPowerSwitchKeyConfiguration` 固定 16B 编解码。
- 修改 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`：添加流程只返回 Key Config handles。
- 修改 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`：更新 desired config hash，表达 16B key config 默认值。
- 修改 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`：SAVE 同步只生成 Key Config step，删除 BPS Model Publication 执行和成功判断。
- 修改 `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`：删除 BPS Model Publication operation case 和 message handle 生成。
- 修改 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`：own configuration 判断不再包含 BPS Model Publication。
- 修改 `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`：own configuration 判断不再包含 BPS Model Publication。
- 修改 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`：删除 BPS profile client model publication helper，保留 target capability/subscription 相关逻辑。

## Task 1: SDK 测试锁定 16B 协议

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`

- [ ] **Step 1: 更新 SET 编码测试为 16B wire**

将 `testBatteryPowerSwitchSetEncoding()` 中 3 个 `XCTAssertEqual` 的 expected data 更新为 16B 配置体，末尾固定追加 `0x01, 0x03, 0xFF`。示例替换如下：

```swift
XCTAssertEqual(
    SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(sceneConfig)).parameters,
    Data([0x4C, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x34, 0x12, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x01, 0x03, 0xFF])
)
```

`moveStop` expected data 改为：

```swift
Data([0x4C, 0x00, 0x04, 0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x01, 0x03, 0xFF])
```

`lightness` expected data 改为：

```swift
Data([0x4C, 0x00, 0x01, 0x00, 0x08, 0x00, 0xFF, 0xBF, 0x00, 0x00, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x01, 0x03, 0xFF])
```

- [ ] **Step 2: 更新 status 解析测试为 16B 配置体**

将 `keyStatus` 的 data 改为 `0x4C 0x00 0x00` 后跟 16B 配置体，并增加新字段断言：

```swift
let keyStatus = SunricherVendorStatus(parameters: Data([0x4C, 0x00, 0x00, 0x02, 0x00, 0x05, 0x00, 0x00, 0x00, 0x34, 0x12, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x01, 0x03, 0xFF]))
XCTAssertEqual(keyStatus?.status.isSuccessful, true)
if case .batteryPowerSwitchKeyConfig(let config) = keyStatus?.status.parameters {
    XCTAssertEqual(config.button, 2)
    XCTAssertEqual(config.trigger, .click)
    XCTAssertEqual(config.type, .sceneRecall)
    XCTAssertEqual(config.sceneId, 0x1234)
    XCTAssertEqual(config.address, 0xC123)
    XCTAssertEqual(config.retransmitCount, 1)
    XCTAssertEqual(config.retransmitInterval, 3)
    XCTAssertEqual(config.transition, 0xFF)
} else {
    XCTFail("Expected battery power switch key config")
}
```

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected: FAIL。失败原因应包含 16B expected data 与当前 13B actual data 不相等，或 `BatteryPowerSwitchKeyConfiguration` 没有 `retransmitCount` / `retransmitInterval` / `transition` 属性。

- [ ] **Step 4: 提交测试变更**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "test: cover battery switch 16b key config"
```

## Task 2: SDK 实现 16B-only 编解码

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`

- [ ] **Step 1: 扩展 action type 枚举**

把 `BatteryPowerSwitchActionType` 替换为完整 `0x00...0x10`：

```swift
public enum BatteryPowerSwitchActionType: UInt8, Codable {
    case disabled = 0
    case onOffToggle = 1
    case onOffSet = 2
    case levelDelta = 3
    case levelMove = 4
    case sceneRecall = 5
    case lightCtrlOnOff = 6
    case factoryReset = 7
    case lightnessSet = 8
    case ctlSet = 9
    case ctlTemperatureSet = 10
    case hslSet = 11
    case hslHueSet = 12
    case hslSaturationSet = 13
    case powerLevelSet = 14
    case powerOnOffSet = 15
    case defaultTransitionTimeSet = 16
}
```

- [ ] **Step 2: 扩展 `BatteryPowerSwitchKeyConfiguration` 字段和 initializer**

在 `ttl` 后新增字段，并给 initializer 增加默认参数：

```swift
public let retransmitCount: UInt8
public let retransmitInterval: UInt8
public let transition: UInt8
```

initializer 签名改为：

```swift
public init(
    button: UInt8,
    trigger: BatteryPowerSwitchTrigger,
    type: BatteryPowerSwitchActionType,
    value: UInt8 = 0,
    level: Int16 = 0,
    sceneId: SceneNumber = 0,
    address: Address = 0,
    appKeyIndex: UInt16 = 0xFFFF,
    ttl: UInt8 = 0xFF,
    retransmitCount: UInt8 = 1,
    retransmitInterval: UInt8 = 3,
    transition: UInt8 = 0xFF
) {
    self.button = button
    self.trigger = trigger
    self.type = type
    self.value = value
    self.level = level
    self.sceneId = sceneId
    self.address = address
    self.appKeyIndex = appKeyIndex
    self.ttl = ttl
    self.retransmitCount = retransmitCount
    self.retransmitInterval = retransmitInterval
    self.transition = transition
}
```

- [ ] **Step 3: 固定 16B 解析**

将 `init?(data:)` 的长度检查从 `13` 改为 `16`，并读取新字段：

```swift
init?(data: Data) {
    guard data.count >= 16,
          let trigger = BatteryPowerSwitchTrigger(rawValue: data.read(fromOffset: 1)),
          let type = BatteryPowerSwitchActionType(rawValue: data.read(fromOffset: 2)) else {
        return nil
    }
    self.button = data.read(fromOffset: 0)
    self.trigger = trigger
    self.type = type
    self.value = data.read(fromOffset: 3)
    self.level = data.read(fromOffset: 4)
    self.sceneId = data.read(fromOffset: 6)
    self.address = data.read(fromOffset: 8)
    self.appKeyIndex = data.read(fromOffset: 10)
    self.ttl = data.read(fromOffset: 12)
    self.retransmitCount = data.read(fromOffset: 13)
    self.retransmitInterval = data.read(fromOffset: 14)
    self.transition = data.read(fromOffset: 15)
}
```

- [ ] **Step 4: 固定 16B 编码**

将 `data` 改为：

```swift
var data: Data {
    Data([button, trigger.rawValue, type.rawValue, value]) +
    level +
    sceneId +
    address +
    appKeyIndex +
    Data([ttl, retransmitCount, retransmitInterval, transition])
}
```

- [ ] **Step 5: 运行 SDK 测试**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected: PASS。

- [ ] **Step 6: 提交 SDK 实现**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: encode battery switch key config as 16b"
```

## Task 3: App 添加流程只保留 Key Config

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: 移除添加流程中的 switchGroup publication 依赖**

在 `BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(...)` 中删除 `let switchGroup = switchData.linkGroup` guard 条件，guard 改为：

```swift
guard isSupportedAddNode(node),
      node.primaryUnicastAddress == switchData.proxyNodeAddress,
      let vendorModel = node.sunricherVendorModel else {
    return []
}
```

- [ ] **Step 2: 删除添加流程 publication handles**

删除以下代码块：

```swift
let publicationHandles = node.getBatteryPowerSwitchPublicationMessageHandles(
    switchGroup: switchGroup,
    includeExisting: true
)
publicationHandles.forEach { $0.continuous = false }

return keyConfigHandles + publicationHandles
```

替换为：

```swift
return keyConfigHandles
```

- [ ] **Step 3: 更新 desired config hash**

在 `PJEightKeySwitchData.batteryPowerSwitchDesiredConfigHash(appKeyIndex:)` 中，将：

```swift
"publication=profileClients@link,retransmit=1/200",
```

替换为：

```swift
"keyConfigWire=16,retransmit=1/200,transition=FF",
```

- [ ] **Step 4: 静态检查添加流程不再引用 BPS publication**

Run:

```bash
rg -n "getBatteryPowerSwitchPublicationMessageHandles|batteryPowerSwitchModelPublication" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected: no output。

- [ ] **Step 5: 提交 App 添加流程变更**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "feat: send battery switch retransmit in key config"
```

## Task 4: App SAVE 同步删除 BPS Model Publication

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 删除 SAVE UI 的 Model Publication step**

在 `SyncDevicesViewController.appendBatteryPowerSwitchItems(...)` 中，将 `if switchData.needsBatteryPowerSwitchConfigurationSync` 内部改为只创建 `Key Config`：

```swift
let keyConfigTask = SyncDeviceStepTaskModel(name: "Key Config", operationType: .configuration(node: switchNode, type: .batteryPowerSwitchKeyConfig(switchData: switchData)))
let keyConfigStep = SyncDeviceStepModel(type: "Key Config", state: .none, tasks: [keyConfigTask])
keyConfigTask.parentStepModel = keyConfigStep
keyConfigStep.parentDeviceModel = switchDeviceModel

switchDeviceModel.steps = [keyConfigStep]
section.devices.append(switchDeviceModel)
configurationDependencies = [keyConfigStep]
```

删除同一区块中创建 `publicationTask`、`publicationStep`、`publicationStep.relevanceStepModels = [keyConfigStep]` 的代码。

- [ ] **Step 2: 删除 SyncDevicesViewController 的 execution case**

在 `messageHandles(for:model:)` 或同等 switch 中删除：

```swift
case .batteryPowerSwitchModelPublication(let switchData):
    guard batteryPowerSwitchKeyConfigurationCompleted,
          node.primaryUnicastAddress == switchData.proxyNodeAddress,
          let switchGroup = switchData.linkGroup else {
        return defaultHandles
    }
    let handles = node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: true)
    handles.forEach { $0.continuous = false }
    return handles
```

在 `isMissingRequiredBatteryPowerSwitchConfigurationHandles(...)` 中删除 `.batteryPowerSwitchModelPublication` 分支。

- [ ] **Step 3: 删除 SyncDevicesCellModel 的 operation case**

在 `SyncDataType` 或当前定义 battery switch sync type 的 enum 中删除：

```swift
case batteryPowerSwitchModelPublication(switchData: PJEightKeySwitchData)
```

删除文件内所有 `.batteryPowerSwitchModelPublication` 分支，包括：

```swift
case .batteryPowerSwitchModelPublication(let switchData):
    return isBatteryPowerSwitchPublicationSuccessful(node: node, switchData: switchData)
```

以及 message handle 生成分支：

```swift
case .batteryPowerSwitchModelPublication(let switchData):
    if node.primaryUnicastAddress == switchData.proxyNodeAddress, let switchGroup = switchData.linkGroup {
        let handles = node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: false)
        handles.forEach { $0.continuous = false }
        messageHandles.append(contentsOf: handles)
    }
```

- [ ] **Step 4: 更新 Edit 和 Monitor own configuration 判断**

在 `PJPreAddEightKeySwitchesVC.containsBatteryPowerSwitchOwnConfiguration(...)` 和 `PJEightKeySwitchMonitorVC.containsBatteryPowerSwitchOwnConfiguration(...)` 中，将：

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchModelPublication:
    return true
```

替换为：

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig:
    return true
```

- [ ] **Step 5: 删除 BPS publication helper**

在 `MeshNetwork+SunSmart.swift` 中删除：

```swift
private var batteryPowerSwitchPublicationRetransmit: Publish.Retransmit {
    Publish.Retransmit(publishRetransmitCount: 1, intervalSteps: 3)
}

func getBatteryPowerSwitchPublicationMessageHandles(switchGroup: Group, includeExisting: Bool = false) -> [MeshMessageHandle] {
    ...
}
```

保留 `batteryPowerSwitchTargetCapabilityModels`、subscription、unsubscription 相关方法。

- [ ] **Step 6: 静态检查没有残留 BPS Model Publication 路径**

Run:

```bash
rg -n "batteryPowerSwitchModelPublication|getBatteryPowerSwitchPublicationMessageHandles|batteryPowerSwitchPublicationRetransmit|publication=profileClients" SunSmart
```

Expected: no output。

- [ ] **Step 7: 提交 SAVE 同步变更**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "refactor: remove battery switch model publication sync"
```

## Task 5: 最终验证

**Files:**
- Verify: SDK tests
- Verify: SunSmart iOS build
- Verify: `docs/superpowers/specs/260521_2031_battery_power_switch_16b_key_config_design.md`

- [ ] **Step 1: 跑 SDK Battery Power Switch 测试**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected: PASS。

- [ ] **Step 2: 跑 SDK 全量测试**

Run:

```bash
swift test
```

Expected: PASS。

- [ ] **Step 3: 跑 App 静态残留检查**

Run:

```bash
rg -n "batteryPowerSwitchModelPublication|getBatteryPowerSwitchPublicationMessageHandles|batteryPowerSwitchPublicationRetransmit|publication=profileClients" SunSmart
```

Expected: no output。

- [ ] **Step 4: 跑 App 16B hash 检查**

Run:

```bash
rg -n "keyConfigWire=16,retransmit=1/200,transition=FF" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected: one match in `batteryPowerSwitchDesiredConfigHash(appKeyIndex:)`。

- [ ] **Step 5: 跑 SunSmart iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 检查 git 状态**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: 只显示本任务相关改动，或工作区干净；不得回退用户已有改动。

## Self-Review

- Spec coverage: Task 1/2 覆盖 SDK 16B 编解码和 action type 扩展；Task 3/4 覆盖 App 删除每 Model publication retransmit、添加和 SAVE 流程只保留 Key Config、hash 变更；Task 5 覆盖 SDK 测试、残留检查和 App build。
- Placeholder scan: 计划中没有占位项或未定义的测试命令。
- Type consistency: 新字段统一命名为 `retransmitCount`、`retransmitInterval`、`transition`；App hash 使用 `keyConfigWire=16,retransmit=1/200,transition=FF`；BPS Model Publication 相关符号在 Task 4 删除。
