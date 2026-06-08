# Battery Power Switch Activation Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将所有 Battery Power Switch 等待激活探测统一改为 Vendor GET `0x4C 0x03`。

**Architecture:** 现有 SAVE、Re-Sync、Identify、TX Enable 等等待激活流程都通过 `PJEightKeySwitchActivationDetecting` 调用默认 `MeshBatteryPowerSwitchActivationDetector`。本次只替换该 detector 的探测命令和成功判断，所有 flow 自动继承新行为。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Sunricher vendor mesh messages, Xcode build.

---

### Task 1: 替换等待激活探测命令

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: 修改 detector 发送的 GET 命令**

在 `MeshBatteryPowerSwitchActivationDetector.sendActivationProbe(to:completion:)` 中，将等待激活探测命令改为：

```swift
message: SunricherVendorGet(function: .batteryPowerSwitchTxEnabled),
```

- [ ] **Step 2: 修改成功响应判断**

同一个方法内，将成功条件改为：

```swift
completion(status.status.isSuccessful && status.status.code == .batteryPowerSwitchTxEnabled)
```

- [ ] **Step 3: 静态检查旧探测命令不再出现在 detector 中**

Run:

```sh
sed -n '58,78p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- `MeshBatteryPowerSwitchActivationDetector` 使用 `.batteryPowerSwitchTxEnabled`。
- `MeshBatteryPowerSwitchActivationDetector` 不再使用 `.batteryPowerSwitchCapability`。

### Task 2: 验证影响范围

**Files:**
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Inspect: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
- Inspect: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 确认等待激活 flow 仍共用默认 detector**

Run:

```sh
rg -n "PJEightKeySwitchActivationFlow|PJEightKeySwitchIdentifyFlow|PJEightKeySwitchTxEnableFlow|MeshBatteryPowerSwitchActivationDetector|batteryPowerSwitchCapability|batteryPowerSwitchTxEnabled" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller SunSmart/Main/Group/Switch/Controller SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `MeshBatteryPowerSwitchActivationDetector` 只在默认参数中被引用。
- `PJEightKeySwitchActivationFlow`、`PJEightKeySwitchIdentifyFlow`、`PJEightKeySwitchTxEnableFlow` 未改变注入方式。
- `batteryPowerSwitchCapability` 不再出现在 activation detector 的实现中。

- [ ] **Step 2: 确认 SDK 已有 `0x4C 0x03` GET 定义**

Run:

```sh
rg -n "batteryPowerSwitchTxEnabled|Data\\(\\[0x4C, 0x03\\]\\)" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift
```

Expected:

- `VendorFunctionGet.batteryPowerSwitchTxEnabled` 存在。
- SDK 测试覆盖 `SunricherVendorGet(function: .batteryPowerSwitchTxEnabled).parameters == Data([0x4C, 0x03])`。

### Task 3: 构建验证

**Files:**
- Build target: `SunSmart.xcworkspace`

- [ ] **Step 1: 运行 iOS 真机泛型构建**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds。
- 如果构建失败，优先确认失败是否与本次 detector 修改相关； unrelated 既有问题单独记录。

### Task 4: 提交实现

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
- Create: `docs/superpowers/plans/260608_1520_battery_power_switch_activation_probe.md`

- [ ] **Step 1: 查看最终 diff**

Run:

```sh
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift docs/superpowers/plans/260608_1520_battery_power_switch_activation_probe.md
```

Expected:

- 代码 diff 只替换 activation detector 的 GET function 和 response code。
- plan 文档为新增文件。

- [ ] **Step 2: 提交本次实现相关文件**

Run:

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift docs/superpowers/plans/260608_1520_battery_power_switch_activation_probe.md
git commit -m "fix: use tx enable get for power switch activation probe"
```

Expected:

- 提交只包含本次 detector 修改和实现计划。
- 不提交既有的 `SyncDevicesViewController.swift` 修改和未跟踪分析文档。

## Self-Review

- Spec 覆盖：Task 1 实现统一探测命令，Task 2 验证所有等待激活 flow 共用 detector，Task 3 验证构建。
- 无 TBD、TODO 或待填充步骤。
- 类型一致：使用 SDK 现有 `SunricherVendorGet(function: .batteryPowerSwitchTxEnabled)` 和 `.batteryPowerSwitchTxEnabled` response code。
- 范围聚焦：不修改同步队列、UI、本地化、资源、target 配置或 SDK。
