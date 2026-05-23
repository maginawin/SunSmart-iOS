# Battery Power Switch Key Config Delay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 Battery Power Switch 添加与 Sync 配置流程中的 Reset 命令，并把 3 秒首发保护和 500ms 处理窗口移动到 Key Config 前后。

**Architecture:** 保留现有 Battery Power Switch 添加、激活、Sync 页面结构，不做跨模块重构。Add 阶段直接下发 Key Config 与 Publication；Sync 阶段只生成 Key Config 和 Model Publication 两个 own configuration step，target group 继续依赖 own configuration。原 Reset enum 和底层 message handle 支持保留，但当前 Add/Sync 流程不再生成 Reset 命令。

**Tech Stack:** Swift, UIKit, Timer, DispatchQueue, MeshProxyMessageCommand, NordicSigMeshSDK, xcodebuild

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 移除添加设备时默认 switch configuration 中的 `batteryPowerSwitchResetDefaults`。
  - 保持 PID 限定、默认 switch data、Key Config、Publication 和成功/失败落盘逻辑不变。

- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Sync 页面不再创建 BPS Reset step。
  - 将上次实现的 Reset 等待状态、helper、成功标记改成 Key Config 语义。
  - Key Config 下发前等待到 `startSync()` 后至少 3 秒；Key Config 成功后等待 500ms。

- Verify only: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 保留 `.batteryPowerSwitchReset` case 和底层 message handle 支持。
  - 只做引用检查，不在本任务中删除 enum 或 message handle 分支。

- Verify only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 确认 probe 间隔仍为 3 秒，探测成功后进入 Sync 仍为 1 秒。

---

### Task 1: 移除添加阶段的 Battery Power Switch Reset

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: 定位 Add 阶段 Reset 和默认配置命令**

Run:

```bash
rg -n "batteryPowerSwitchResetDefaults|defaultConfigurationMessageHandles|keyConfigHandles|publicationHandles|return \\[" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- 输出包含 `batteryPowerSwitchResetDefaults`。
- 输出包含 `return [resetHandle] + keyConfigHandles + publicationHandles`。

- [ ] **Step 2: 删除 Add 阶段 Reset handle**

In `BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(...)`, replace:

```swift
let resetHandle = MeshMessageHandle(
    message: SunricherVendorSet(function: .batteryPowerSwitchResetDefaults),
    model: vendorModel
)
resetHandle.continuous = false

let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
```

With:

```swift
let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
```

- [ ] **Step 3: 修改 Add 阶段返回命令顺序**

In the same method, replace:

```swift
return [resetHandle] + keyConfigHandles + publicationHandles
```

With:

```swift
return keyConfigHandles + publicationHandles
```

Expected:

- Add 阶段默认配置从 Key Config 开始。
- Publication 仍紧跟 Key Config。
- `prepareSwitchData`、`markSucceeded`、`markFailed` 不变。

- [ ] **Step 4: 静态确认 Add 阶段不再发送 Reset**

Run:

```bash
rg -n "batteryPowerSwitchResetDefaults|resetHandle|return \\[resetHandle\\]" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- 没有输出。

- [ ] **Step 5: 提交 Add 阶段改动**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "fix: remove battery switch reset during add"
```

Expected:

- Commit 只包含 `BatteryPowerSwitchAddConfiguration.swift`。

---

### Task 2: Sync 阶段移除 Reset step 并改为 Key Config 等待

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 定位 Sync 阶段 BPS Reset 创建和等待状态**

Run:

```bash
rg -n "batteryPowerSwitchConfigurationResetCompleted|batteryPowerSwitchResetEarliestDate|batteryPowerSwitchResetInitialDelay|batteryPowerSwitchPostResetProcessingDelay|batteryPowerSwitchReset\\(|isBatteryPowerSwitchResetConfiguration|waitBeforeBatteryPowerSwitchResetIfNeeded|waitAfterBatteryPowerSwitchResetSuccessIfNeeded|Reset" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- 输出包含 BPS 属性区的 Reset 状态。
- 输出包含 `appendBatteryPowerSwitchItems` 中的 `Reset` step。
- 输出包含 `startSync()` 中 Reset 前等待、Reset 成功标记、Reset 成功后 500ms 等待。

- [ ] **Step 2: 重命名 BPS 配置状态为 Key Config 语义**

Near the top of `SyncDevicesViewController`, replace:

```swift
private var batteryPowerSwitchOwnConfigurationFailed = false
private var batteryPowerSwitchConfigurationResetCompleted = false
private var batteryPowerSwitchResetEarliestDate: Date?
private var syncRunIdentifier = UUID()

private static let batteryPowerSwitchResetInitialDelay: TimeInterval = 3
private static let batteryPowerSwitchPostResetProcessingDelay: TimeInterval = 0.5
```

With:

```swift
private var batteryPowerSwitchOwnConfigurationFailed = false
private var batteryPowerSwitchKeyConfigurationCompleted = false
private var batteryPowerSwitchKeyConfigEarliestDate: Date?
private var syncRunIdentifier = UUID()

private static let batteryPowerSwitchKeyConfigInitialDelay: TimeInterval = 3
private static let batteryPowerSwitchPostKeyConfigProcessingDelay: TimeInterval = 0.5
```

- [ ] **Step 3: `startSync()` 初始化改为 Key Config 状态**

In `startSync()`, replace:

```swift
batteryPowerSwitchConfigurationResetCompleted = false
let syncRunIdentifier = beginSyncRun()
```

With:

```swift
batteryPowerSwitchKeyConfigurationCompleted = false
let syncRunIdentifier = beginSyncRun()
```

- [ ] **Step 4: 移除 BPS Reset step，保留 Key Config 和 Model Publication**

In `appendBatteryPowerSwitchItems(...)`, replace the whole `if switchData.needsBatteryPowerSwitchConfigurationSync { ... }` block with:

```swift
if switchData.needsBatteryPowerSwitchConfigurationSync {
    let keyConfigTask = SyncDeviceStepTaskModel(name: "Key Config", operationType: .configuration(node: switchNode, type: .batteryPowerSwitchKeyConfig(switchData: switchData)))
    let keyConfigStep = SyncDeviceStepModel(type: "Key Config", state: .none, tasks: [keyConfigTask])
    keyConfigTask.parentStepModel = keyConfigStep
    keyConfigStep.parentDeviceModel = switchDeviceModel

    let publicationTask = SyncDeviceStepTaskModel(name: "Model Publication", operationType: .configuration(node: switchNode, type: .batteryPowerSwitchModelPublication(switchData: switchData)))
    let publicationStep = SyncDeviceStepModel(type: "Model Publication", state: .none, tasks: [publicationTask])
    publicationTask.parentStepModel = publicationStep
    publicationStep.parentDeviceModel = switchDeviceModel
    publicationStep.relevanceStepModels = [keyConfigStep]

    switchDeviceModel.steps = [keyConfigStep, publicationStep]
    section.devices.append(switchDeviceModel)
    configurationDependencies = [keyConfigStep, publicationStep]
}
```

Expected:

- Sync UI 不再显示 `Reset` step。
- `Model Publication` 只依赖 `Key Config`。
- target group add/remove 仍依赖 `configurationDependencies`，也就是 Key Config 和 Model Publication。

- [ ] **Step 5: 将同步轮次 helper 改为 Key Config 最早发送时间**

Replace:

```swift
private func beginSyncRun() -> UUID {
    let identifier = UUID()
    syncRunIdentifier = identifier
    if batteryPowerSwitchDataForSync != nil {
        batteryPowerSwitchResetEarliestDate = Date().addingTimeInterval(Self.batteryPowerSwitchResetInitialDelay)
    } else {
        batteryPowerSwitchResetEarliestDate = nil
    }
    return identifier
}

private func invalidateCurrentSyncRun() {
    syncRunIdentifier = UUID()
    batteryPowerSwitchResetEarliestDate = nil
}
```

With:

```swift
private func beginSyncRun() -> UUID {
    let identifier = UUID()
    syncRunIdentifier = identifier
    if batteryPowerSwitchDataForSync != nil {
        batteryPowerSwitchKeyConfigEarliestDate = Date().addingTimeInterval(Self.batteryPowerSwitchKeyConfigInitialDelay)
    } else {
        batteryPowerSwitchKeyConfigEarliestDate = nil
    }
    return identifier
}

private func invalidateCurrentSyncRun() {
    syncRunIdentifier = UUID()
    batteryPowerSwitchKeyConfigEarliestDate = nil
}
```

- [ ] **Step 6: 将等待 helper 从 Reset 改为 Key Config**

Replace:

```swift
@discardableResult
private func waitBeforeBatteryPowerSwitchResetIfNeeded(for model: SyncCellModel, syncRunIdentifier identifier: UUID) -> Bool {
    guard isBatteryPowerSwitchResetConfiguration(model),
          let earliestDate = batteryPowerSwitchResetEarliestDate else {
        return isActiveSyncRun(identifier)
    }
    let waitTime = earliestDate.timeIntervalSinceNow
    if waitTime > 0 {
        Thread.sleep(forTimeInterval: waitTime)
    }
    batteryPowerSwitchResetEarliestDate = nil
    return isActiveSyncRun(identifier)
}

private func waitAfterBatteryPowerSwitchResetSuccessIfNeeded(for model: SyncCellModel) {
    guard isBatteryPowerSwitchResetConfiguration(model) else {
        return
    }
    Thread.sleep(forTimeInterval: Self.batteryPowerSwitchPostResetProcessingDelay)
}
```

With:

```swift
@discardableResult
private func waitBeforeBatteryPowerSwitchKeyConfigIfNeeded(for model: SyncCellModel, syncRunIdentifier identifier: UUID) -> Bool {
    guard isBatteryPowerSwitchKeyConfigConfiguration(model),
          let earliestDate = batteryPowerSwitchKeyConfigEarliestDate else {
        return isActiveSyncRun(identifier)
    }
    let waitTime = earliestDate.timeIntervalSinceNow
    if waitTime > 0 {
        Thread.sleep(forTimeInterval: waitTime)
    }
    batteryPowerSwitchKeyConfigEarliestDate = nil
    return isActiveSyncRun(identifier)
}

private func waitAfterBatteryPowerSwitchKeyConfigSuccessIfNeeded(for model: SyncCellModel) {
    guard isBatteryPowerSwitchKeyConfigConfiguration(model) else {
        return
    }
    Thread.sleep(forTimeInterval: Self.batteryPowerSwitchPostKeyConfigProcessingDelay)
}
```

- [ ] **Step 7: 将 Reset 判断 helper 改为 Key Config 判断**

Replace:

```swift
private func isBatteryPowerSwitchResetConfiguration(_ model: SyncCellModel) -> Bool {
    guard let operationType = operationType(for: model) else {
        return false
    }
    switch operationType {
    case .configuration(_, let actionType):
        if case .batteryPowerSwitchReset = actionType {
            return true
        }
        return false
    default:
        return false
    }
}
```

With:

```swift
private func isBatteryPowerSwitchKeyConfigConfiguration(_ model: SyncCellModel) -> Bool {
    guard let operationType = operationType(for: model) else {
        return false
    }
    switch operationType {
    case .configuration(_, let actionType):
        if case .batteryPowerSwitchKeyConfig = actionType {
            return true
        }
        return false
    default:
        return false
    }
}
```

- [ ] **Step 8: `startSync()` 发送前等待 Key Config**

In `startSync()`, replace:

```swift
guard self.waitBeforeBatteryPowerSwitchResetIfNeeded(for: model, syncRunIdentifier: syncRunIdentifier) else {
    return
}

let isBatteryPowerSwitchResetModel = self.isBatteryPowerSwitchResetConfiguration(model)
MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: self.ackTimeout(for: model), progressBack: nil, successfulBack: { handle, statusMessage in
```

With:

```swift
guard self.waitBeforeBatteryPowerSwitchKeyConfigIfNeeded(for: model, syncRunIdentifier: syncRunIdentifier) else {
    return
}

let isBatteryPowerSwitchKeyConfigModel = self.isBatteryPowerSwitchKeyConfigConfiguration(model)
MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: self.ackTimeout(for: model), progressBack: nil, successfulBack: { handle, statusMessage in
```

- [ ] **Step 9: Key Config 成功后标记完成**

In the `MeshProxyMessageCommand.shared.addMessage` completion success branch, replace:

```swift
if isBatteryPowerSwitchResetModel {
    self.batteryPowerSwitchConfigurationResetCompleted = true
}
```

With:

```swift
if isBatteryPowerSwitchKeyConfigModel {
    self.batteryPowerSwitchKeyConfigurationCompleted = true
}
```

- [ ] **Step 10: Key Config 成功后等待 500ms**

After `semaphore.wait()`, replace:

```swift
if isBatteryPowerSwitchResetModel, model.state == .successful {
    self.waitAfterBatteryPowerSwitchResetSuccessIfNeeded(for: model)
}
```

With:

```swift
if isBatteryPowerSwitchKeyConfigModel, model.state == .successful {
    self.waitAfterBatteryPowerSwitchKeyConfigSuccessIfNeeded(for: model)
}
```

- [ ] **Step 11: Key Config handles 不再依赖 Reset 完成**

In `batteryPowerSwitchMessageHandles(for:defaultHandles:)`, replace the `.batteryPowerSwitchKeyConfig` branch:

```swift
case .batteryPowerSwitchKeyConfig(let switchData):
    guard batteryPowerSwitchConfigurationResetCompleted,
          node.primaryUnicastAddress == switchData.proxyNodeAddress,
          let vendorModel = node.sunricherVendorModel else {
        return defaultHandles
    }
    let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
    return switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
        let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)), model: vendorModel)
        handle.continuous = false
        return handle
    }
```

With:

```swift
case .batteryPowerSwitchKeyConfig(let switchData):
    guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
          let vendorModel = node.sunricherVendorModel else {
        return defaultHandles
    }
    let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
    return switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
        let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)), model: vendorModel)
        handle.continuous = false
        return handle
    }
```

- [ ] **Step 12: Publication 依赖 Key Config 完成**

In `batteryPowerSwitchMessageHandles(for:defaultHandles:)`, replace:

```swift
guard batteryPowerSwitchConfigurationResetCompleted,
      node.primaryUnicastAddress == switchData.proxyNodeAddress,
      let switchGroup = switchData.linkGroup else {
    return defaultHandles
}
```

With:

```swift
guard batteryPowerSwitchKeyConfigurationCompleted,
      node.primaryUnicastAddress == switchData.proxyNodeAddress,
      let switchGroup = switchData.linkGroup else {
    return defaultHandles
}
```

- [ ] **Step 13: 缺失 handles 和成功判断改为 Key Config 语义**

In `isMissingRequiredBatteryPowerSwitchConfigurationHandles(...)`, replace:

```swift
guard batteryPowerSwitchConfigurationResetCompleted,
      messageHandles.isEmpty,
      let operationType = operationType(for: model) else {
    return false
}
```

With:

```swift
guard messageHandles.isEmpty,
      let operationType = operationType(for: model) else {
    return false
}
```

Then inside the same method, replace:

```swift
case .batteryPowerSwitchKeyConfig, .batteryPowerSwitchModelPublication:
    return true
```

With:

```swift
case .batteryPowerSwitchKeyConfig:
    return true
case .batteryPowerSwitchModelPublication:
    return batteryPowerSwitchKeyConfigurationCompleted
```

In `isBatteryPowerSwitchOperationSuccessful(...)`, replace:

```swift
guard batteryPowerSwitchConfigurationResetCompleted,
      isBatteryPowerSwitchOwnConfiguration(model) else {
    return resultSuccessful && operationSuccessful
}
return !messageHandles.isEmpty && resultSuccessful
```

With:

```swift
guard isBatteryPowerSwitchOwnConfiguration(model) else {
    return resultSuccessful && operationSuccessful
}
return !messageHandles.isEmpty && resultSuccessful
```

Expected:

- Key Config 自身用实际 message handles 成功结果判断。
- Model Publication 在 Key Config 成功后才使用 includeExisting publication handles。
- 非 BPS 操作仍走原判断。

- [ ] **Step 14: 清理 BPS own configuration 中的 Reset 分类**

In `isBatteryPowerSwitchConfigurationOperation(_:)`, `isBatteryPowerSwitchOwnConfigurationOperation(_:)`, and `isBatteryPowerSwitchSyncOperation(_:)`, remove `.batteryPowerSwitchReset` from the BPS own/sync matching cases used by Sync 页面。

Expected final cases:

```swift
case .batteryPowerSwitchKeyConfig,
     .batteryPowerSwitchModelPublication:
    return true
```

For sync operation including target groups:

```swift
case .batteryPowerSwitchKeyConfig,
     .batteryPowerSwitchModelPublication,
     .batteryPowerSwitchTargetSubscription:
    return true
```

Note:

- Do not remove `.batteryPowerSwitchReset` from `SyncDevicesCellModel.swift` in this task。
- Do not delete `DeviceOperationType.batteryPowerSwitchReset`。

- [ ] **Step 15: 静态确认 Sync 页面不再创建或等待 Reset**

Run:

```bash
rg -n "batteryPowerSwitchConfigurationResetCompleted|batteryPowerSwitchResetEarliestDate|batteryPowerSwitchResetInitialDelay|batteryPowerSwitchPostResetProcessingDelay|waitBeforeBatteryPowerSwitchResetIfNeeded|waitAfterBatteryPowerSwitchResetSuccessIfNeeded|isBatteryPowerSwitchResetConfiguration|SyncDeviceStepTaskModel\\(name: \"Reset\"|SyncDeviceStepModel\\(type: \"Reset\"" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- 没有输出。

- [ ] **Step 16: 静态确认 Key Config 延时与成功后等待存在**

Run:

```bash
rg -n "batteryPowerSwitchKeyConfigurationCompleted|batteryPowerSwitchKeyConfigEarliestDate|batteryPowerSwitchKeyConfigInitialDelay|batteryPowerSwitchPostKeyConfigProcessingDelay|waitBeforeBatteryPowerSwitchKeyConfigIfNeeded|waitAfterBatteryPowerSwitchKeyConfigSuccessIfNeeded|isBatteryPowerSwitchKeyConfigConfiguration|Thread.sleep" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- 输出包含 Key Config earliest date。
- 输出包含 3 秒常量。
- 输出包含 0.5 秒常量。
- 输出包含 Key Config 前等待和 Key Config 成功后等待 helper。

- [ ] **Step 17: 提交 Sync 阶段改动**

Run:

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: delay battery switch key config sync"
```

Expected:

- Commit 只包含 `SyncDevicesViewController.swift`。

---

### Task 3: 全量检查和构建验证

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: 确认 Add 阶段不再包含 Reset**

Run:

```bash
rg -n "batteryPowerSwitchResetDefaults|resetHandle" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- 没有输出。

- [ ] **Step 2: 确认 Sync 页面不再创建 Reset step**

Run:

```bash
rg -n "SyncDeviceStepTaskModel\\(name: \"Reset\"|SyncDeviceStepModel\\(type: \"Reset\"|batteryPowerSwitchReset\\(switchData" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- 没有输出。

- [ ] **Step 3: 确认底层 Reset 支持仍保留**

Run:

```bash
rg -n "case batteryPowerSwitchReset|batteryPowerSwitchResetDefaults" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:

- 输出包含 `case batteryPowerSwitchReset`。
- 输出包含 `batteryPowerSwitchResetDefaults`。

- [ ] **Step 4: 确认激活节奏未被改坏**

Run:

```bash
rg -n "scheduledTimer\\(withTimeInterval: 3|asyncAfter\\(deadline: \\.now\\(\\) \\+ 1\\.0" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- 输出包含 `scheduledTimer(withTimeInterval: 3`。
- 输出包含 `asyncAfter(deadline: .now() + 1.0`。

- [ ] **Step 5: 检查 git diff 是否聚焦**

Run:

```bash
git diff --stat HEAD~2..HEAD
```

Expected:

- Diff 只涉及：
  - `BatteryPowerSwitchAddConfiguration.swift`
  - `SyncDevicesViewController.swift`
- 如果实现计划文档也在当前分支，文档 commit 应独立于代码 commit。

- [ ] **Step 6: 运行 iOS 构建验证**

Run this direct command from repo root:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Exit code 0。
- 输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 7: 提交验证后收尾**

Run:

```bash
git status --short
```

Expected:

- 没有未提交的代码改动。
- 允许存在与本任务无关、此前已经存在的未跟踪 docs 文件，但不要删除或提交它们，除非用户明确要求。
