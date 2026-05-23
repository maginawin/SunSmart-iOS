# Battery Power Switch Force Full Configuration After Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battery Power Switch 每次 reset 成功后，必须强制下发完整 Key Config 和全部 Profile Client Model Publication，不能因本地 publication 缓存跳过。

**Architecture:** 将“本轮 reset 已成功”作为 SyncDevicesViewController 的发送上下文，而不是写进全局 `DeviceOperationType.messageHandles`。BPS own configuration 的 message handles 和成功判定在同步控制器里集中处理，group-only sync 仍沿用已有 target subscription 路径。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、MeshMessageHandle、xcodebuild。

---

## 文件结构

- 修改 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 负责本轮 reset 上下文标记、BPS own configuration 强制 handles、reset 后成功判定覆盖。
- 修改 `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 保留普通 publication 状态校验，但避免 reset 后仍把空 handles 当成功的全局默认。
- 不新增测试文件
  - 当前 workspace 没有现成 XCTest target 或 test plan，本次用静态检查和 `xcodebuild` 验证。

## Task 1: 建立 BPS Reset 后强制配置上下文

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 增加本轮 reset 完成标记**

在 controller 属性区加入：

```swift
private var batteryPowerSwitchConfigurationResetCompleted = false
```

- [ ] **Step 2: 每轮 startSync 开始时重置标记**

在 `startSync()` 开头已有：

```swift
batteryPowerSwitchOwnConfigurationFailed = false
```

改为：

```swift
batteryPowerSwitchOwnConfigurationFailed = false
batteryPowerSwitchConfigurationResetCompleted = false
```

- [ ] **Step 3: reset 成功后设置标记**

在 `MeshProxyMessageCommand.shared.addMessage` finished callback 内，`model.state = .successful` 后加入：

```swift
if self.isBatteryPowerSwitchResetConfiguration(model) {
    self.batteryPowerSwitchConfigurationResetCompleted = true
}
```

- [ ] **Step 4: 新增 reset 判断 helper**

在 BPS helper 区增加：

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

- [ ] **Step 5: 静态检查**

Run: `rg -n "batteryPowerSwitchConfigurationResetCompleted|isBatteryPowerSwitchResetConfiguration" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

Expected: 属性、`startSync` 重置、成功分支置位、helper 均能搜到。

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: track battery switch reset configuration"
```

## Task 2: Reset 后强制生成完整 Key Config 和 Model Publication

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 在发送前改用 BPS 专用 handle helper**

在 `startSync()` 中得到 `messageHandles` 后、特殊任务处理前加入：

```swift
messageHandles = batteryPowerSwitchMessageHandles(for: model, defaultHandles: messageHandles)
```

放置位置要求：在 `completeProfileSensorProtectionTaskIfNeeded`、`completeEmptyEmergencyFireControllerTaskIfNeeded`、`completeEmergencyFireControllerAutoRestoreTaskIfNeeded` 之前，以便后续空 handles 判断使用最终 handles。

- [ ] **Step 2: 新增 BPS own configuration handles helper**

在 BPS helper 区增加：

```swift
private func batteryPowerSwitchMessageHandles(for model: SyncCellModel, defaultHandles: [MeshMessageHandle]) -> [MeshMessageHandle] {
    guard let operationType = operationType(for: model) else {
        return defaultHandles
    }
    switch operationType {
    case .configuration(let node, let actionType):
        switch actionType {
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
        case .batteryPowerSwitchModelPublication(let switchData):
            guard batteryPowerSwitchConfigurationResetCompleted,
                  node.primaryUnicastAddress == switchData.proxyNodeAddress,
                  let switchGroup = switchData.linkGroup else {
                return defaultHandles
            }
            let handles = node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: true)
            handles.forEach { $0.continuous = false }
            return handles
        default:
            return defaultHandles
        }
    default:
        return defaultHandles
    }
}
```

- [ ] **Step 3: 保留 reset 自身发送策略**

确认 `DeviceOperationType.messageHandles` 中 `.batteryPowerSwitchReset` 仍生成 vendor reset handle，且 `continuous = false`。

- [ ] **Step 4: 静态检查 publication 强制模式**

Run: `rg -n "includeExisting: true|batteryPowerSwitchMessageHandles|batteryPowerSwitchKeyConfig" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

Expected: `batteryPowerSwitchMessageHandles` 中 Model Publication 使用 `includeExisting: true`，Key Config 强制按 `batteryPowerSwitchKeyConfigurations` 生成。

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: force battery switch configuration after reset"
```

## Task 3: Reset 后禁止空 Publication 默认成功

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Inspect: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: 增加 reset 后空 handles 失败判断**

在 `startSync()` 中 BPS fail-fast 判断之后、`MeshProxyMessageCommand.shared.addMessage` 之前加入：

```swift
if self.isMissingRequiredBatteryPowerSwitchConfigurationHandles(model, messageHandles: messageHandles) {
    model.state = .failed
    (model as? SyncDevicesModel)?.failedCount += 1
    (model as? SyncDeviceStepTaskModel)?.failedCount += 1
    self.batteryPowerSwitchOwnConfigurationFailed = true
    self.markPendingBatteryPowerSwitchOwnConfigurationTasksFailed()
    self.updateCell(model: model)
    continue
}
```

- [ ] **Step 2: 新增 required handles helper**

在 BPS helper 区增加：

```swift
private func isMissingRequiredBatteryPowerSwitchConfigurationHandles(_ model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
    guard batteryPowerSwitchConfigurationResetCompleted,
          messageHandles.isEmpty,
          let operationType = operationType(for: model) else {
        return false
    }
    switch operationType {
    case .configuration(_, let actionType):
        switch actionType {
        case .batteryPowerSwitchKeyConfig, .batteryPowerSwitchModelPublication:
            return true
        default:
            return false
        }
    default:
        return false
    }
}
```

- [ ] **Step 3: 增加发送结果优先成功判断 helper**

在 BPS helper 区增加：

```swift
private func isBatteryPowerSwitchOperationSuccessful(model: SyncCellModel, resultSuccessful: Bool, operationSuccessful: Bool, messageHandles: [MeshMessageHandle]) -> Bool {
    guard batteryPowerSwitchConfigurationResetCompleted,
          isBatteryPowerSwitchOwnConfiguration(model) else {
        return resultSuccessful && operationSuccessful
    }
    return !messageHandles.isEmpty && resultSuccessful
}
```

- [ ] **Step 4: 替换成功分支判断**

将：

```swift
if resultSuccessful && operationSuccessful || self.isEmergencyFireControllerDeleteCleanup(model) {
```

替换为：

```swift
if self.isBatteryPowerSwitchOperationSuccessful(
    model: model,
    resultSuccessful: resultSuccessful,
    operationSuccessful: operationSuccessful,
    messageHandles: messageHandles
) || self.isEmergencyFireControllerDeleteCleanup(model) {
```

- [ ] **Step 5: 保留普通 publication 校验**

不删除 `SyncDevicesCellModel.swift` 中 `isBatteryPowerSwitchPublicationSuccessful`。该校验继续服务于未 reset 的普通状态检查；reset 后路径由 `SyncDevicesViewController` 的发送结果覆盖。

- [ ] **Step 6: 静态检查空 handles 失败路径**

Run: `rg -n "isMissingRequiredBatteryPowerSwitchConfigurationHandles|isBatteryPowerSwitchOperationSuccessful|messageHandles\\.isEmpty" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

Expected: 能看到 helper 和发送前失败分支。

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: validate battery switch reset configuration sends"
```

## Task 4: 验证 group-only 与 reset 后完整配置不互相回归

**Files:**
- Inspect: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: 静态检查 group-only 不触发 own configuration**

Run: `rg -n "if switchData\\.needsBatteryPowerSwitchConfigurationSync|case \\.batteryPowerSwitchTargetSubscription:|return false" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

Expected: `appendBatteryPowerSwitchItems` 仅在 `needsBatteryPowerSwitchConfigurationSync` 为 true 时创建 reset/key/publication；target subscription 不被 `isBatteryPowerSwitchConfigurationOperation` 归为 activation-gated configuration。

- [ ] **Step 2: 静态检查 BPS 自身配置 hash 不包含 group-only 字段**

Run: `rg -n "groups=|unbind=|bindGroupAddresses|unbindGroupAddresses|scenes=|publication=profileClients" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

Expected: `batteryPowerSwitchDesiredConfigHash` 不包含 `groups=` 和 `unbind=`，仍包含 panel/enabled/link/scenes/appKey 等自身配置字段。

- [ ] **Step 3: 静态检查 SAVE 分支按 configuration 与 target sync 分流**

Run: `rg -n "needsConfigurationSync|needsTargetSync|presentBatteryPowerSwitchActivation|pushBatteryPowerSwitchSync" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

Expected: 只有 `needsConfigurationSync` 为 true 时展示 activation；仅 `needsTargetSync` 时直接 push sync controller。

- [ ] **Step 4: 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。既有 warnings 可以记录但不在本任务处理。

- [ ] **Step 5: 工作区检查**

Run: `git status --short`

Expected: 只包含本任务预期改动，或工作区干净。

- [ ] **Step 6: 记录验证结果**

在最终回复中记录 `rg` 静态检查结果、`xcodebuild` 构建结果，以及是否仍存在既有 warnings。

## 自审

- Spec coverage：Task 1-3 覆盖 reset 后强制完整 Key Config / Model Publication、不默认成功、保留 re-sync activation；Task 4 覆盖 group-only 不回归和构建验证。
- Placeholder scan：无未完成标记。
- Type consistency：计划中的 helper 均放在 `SyncDevicesViewController`，依赖现有 `SyncCellModel`、`DeviceOperationType`、`MeshMessageHandle`、`PJEightKeySwitchData`、`Node` 类型。
