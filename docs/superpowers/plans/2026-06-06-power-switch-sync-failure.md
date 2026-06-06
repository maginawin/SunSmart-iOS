# Power Switch Sync Failure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battery/AC Power Switch 在 STOP 或 SAVE 任一同步任务失败后持久化为未同步，并在 switches 列表显示未同步 icon。

**Architecture:** 抽出 `DeviceOperationType` 的 power switch 同步判定，让同步页和三个外层入口复用同一语义。同步结果仍由现有 `SyncDevicesViewController` 产出，外层入口负责持久化 `PJEightKeySwitchData`；列表通过 `syncState` 和状态 icon 展示未同步。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 SQLite repository、现有 `xcodebuild` iOS device build。

---

## 文件结构

- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 在 `DeviceOperationType` 上新增可复用判定：power switch 全同步任务、own configuration 任务。
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 复用 `DeviceOperationType` 判定，确保 STOP / failure / resync 的 power switch 范围一致。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - SAVE 返回失败时，任一 power switch 同步任务失败即标记 switch 未同步。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 详情页 SAVE 返回失败时使用同一判定。
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
  - group power switches SAVE 返回失败时使用同一判定。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - `syncState != .synced` 驱动 Battery/AC Power Switch 列表未同步状态。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchesViewCell.swift`
  - 未同步和 repair 状态使用 `PJEightKeySwitchStatus.iconAssetName`。

## 测试约束

当前仓库没有发现明确的 Swift test target 文件路径；本计划不新增测试 target，避免引入 project 配置改动。验证以代码级检查、状态流转检查和项目规则指定的 `xcodebuild` 为准。

### Task 1: 抽出 Power Switch Operation 判定

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: 记录当前私有判定覆盖范围**

Run:

```sh
rg -n "isBatteryPowerSwitchOwnConfigurationOperation|isBatteryPowerSwitchSyncOperation|batteryPowerSwitchTargetSubscription" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:
- `SyncDevicesViewController.swift` 中存在 own configuration 和全 sync 两个私有 helper。
- `DeviceOperationType` 中存在 `.batteryPowerSwitchKeyConfig`、`.batteryPowerSwitchTxEnable`、`.batteryPowerSwitchLEDIndicator`、`.batteryPowerSwitchTargetSubscription` action type。

- [ ] **Step 2: 在 `DeviceOperationType` 内新增 computed properties**

在 `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift` 的 `enum DeviceOperationType` 内，靠近 `isSuccessful` 之前加入：

```swift
    var isPowerSwitchOwnConfigurationOperation: Bool {
        switch self {
        case .configuration(_, let type):
            switch type {
            case .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchTxEnable,
                 .batteryPowerSwitchLEDIndicator:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    var isPowerSwitchSyncOperation: Bool {
        switch self {
        case .configuration(_, let type), .delete(_, let type):
            switch type {
            case .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchTxEnable,
                 .batteryPowerSwitchLEDIndicator,
                 .batteryPowerSwitchTargetSubscription:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
```

- [ ] **Step 3: Verify Swift reference compiles syntactically by grep**

Run:

```sh
rg -n "var isPowerSwitchOwnConfigurationOperation|var isPowerSwitchSyncOperation" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:
- 两个 property 都在 `SyncDevicesCellModel.swift` 中出现一次。

### Task 2: 同步页复用统一判定

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 替换私有 helper 的内部逻辑**

保留 `SyncDevicesViewController` 中现有方法名，降低调用点改动；将内部逻辑改为复用 Task 1 的 property：

```swift
    private func isBatteryPowerSwitchConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        return operationType.isPowerSwitchOwnConfigurationOperation
    }
    
    private func isBatteryPowerSwitchOwnConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        return operationType.isPowerSwitchOwnConfigurationOperation
    }

    private func isBatteryPowerSwitchSyncOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        return operationType.isPowerSwitchSyncOperation
    }
```

- [ ] **Step 2: 确认 STOP 会处理 `.inSettings`**

检查 `rightItemAction()` 的 stop 分支，未完成状态判断必须包含 `.inSettings`：

```swift
                    if $0.state == .none || $0.state == .wait || $0.state == .inSettings {
                        $0.state = .failed
                        ($0 as? SyncDevicesModel)?.failedCount += 1
                        ($0 as? SyncDeviceStepTaskModel)?.failedCount += 1
                    }
```

如果当前代码缺少 `.inSettings`，补上；如果已经存在，保持不变。

- [ ] **Step 3: 确认旧 completion 受 run id 保护**

检查 `MeshProxyMessageCommand.shared.addMessage` 的 `successfulBack`、`failedBack`、`finishedBack`，写 model 状态前必须有：

```swift
                    guard self.isActiveSyncRun(syncRunIdentifier) else {
                        return
                    }
```

finishedBack 中需要 signal semaphore 后返回：

```swift
                    guard self.isActiveSyncRun(syncRunIdentifier) else {
                        semaphore.signal()
                        return
                    }
```

如果当前代码已具备这些 guard，保持不变。

- [ ] **Step 4: Verify 同步页 helper 使用统一 property**

Run:

```sh
rg -n "isPowerSwitchOwnConfigurationOperation|isPowerSwitchSyncOperation" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:
- `SyncDevicesViewController` 的私有 helper 内出现 Task 1 的 property。
- 原有调用点继续调用私有 helper，无需大范围改名。

### Task 3: 三个入口失败回调改为全 Power Switch 同步判定

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: 更新 `PJPreAddEightKeySwitchesVC` helper**

将 `containsBatteryPowerSwitchOwnConfiguration(_:)` 改为：

```swift
    private func containsBatteryPowerSwitchOwnConfiguration(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchOwnConfigurationOperation }
    }

    private func containsPowerSwitchSyncOperation(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchSyncOperation }
    }
```

- [ ] **Step 2: 更新 `PJPreAddEightKeySwitchesVC` failure callback**

在 `pushBatteryPowerSwitchSync(_:)` 的 `backActionCallback` 中，将失败优先判断改为：

```swift
            if self.containsPowerSwitchSyncOperation(failedOperationTypes) {
                switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
                if let snapshot = self.pendingBatteryPowerSwitchOwnStateSnapshot {
                    switchData.enabled = snapshot.enabled
                    switchData.moreSettingsState = snapshot.moreSettings
                }
            } else if self.containsBatteryPowerSwitchOwnConfiguration(successOperationTypes) {
                switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
            }
```

说明：成功分支仍只允许 own configuration 成功时更新 applied own configuration，避免仅 target group 成功就改写 own applied 状态。

- [ ] **Step 3: 更新 `PJEightKeySwitchMonitorVC` helper**

将 `containsBatteryPowerSwitchOwnConfiguration(_:)` 改为：

```swift
    private func containsBatteryPowerSwitchOwnConfiguration(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchOwnConfigurationOperation }
    }

    private func containsPowerSwitchSyncOperation(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchSyncOperation }
    }
```

- [ ] **Step 4: 更新 `PJEightKeySwitchMonitorVC` failure callback**

在 `pushBatteryPowerSwitchSyncController()` 的 `backActionCallback` 中，将失败优先判断改为：

```swift
            if self.containsPowerSwitchSyncOperation(failedOperationTypes) {
                self.viewModel.switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
            } else if self.containsBatteryPowerSwitchOwnConfiguration(successOperationTypes) {
                self.viewModel.switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
            }
```

- [ ] **Step 5: 更新 `GroupPowerSwitchesViewController` helper**

将 `containsBatteryPowerSwitchOwnConfiguration(_:)` 改为：

```swift
    private func containsBatteryPowerSwitchOwnConfiguration(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchOwnConfigurationOperation }
    }

    private func containsPowerSwitchSyncOperation(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchSyncOperation }
    }
```

- [ ] **Step 6: 更新 `GroupPowerSwitchesViewController` failure callback**

在 `pushPowerSwitchSync(_:mode:)` 的 `.save` 回调路径中，将失败优先判断改为：

```swift
            if self.containsPowerSwitchSyncOperation(failedOperationTypes) {
                switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
            } else if self.containsBatteryPowerSwitchOwnConfiguration(successOperationTypes) {
                switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
            }
```

保留 `mode == .deleteGroup` 的现有回退逻辑，不改变该分支。

- [ ] **Step 7: Verify 三个入口都引用全 sync 判定**

Run:

```sh
rg -n "containsPowerSwitchSyncOperation|isPowerSwitchSyncOperation" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected:
- 三个 VC 都有 `containsPowerSwitchSyncOperation`。
- 三个 failure callback 都优先检查 failed operation types。

### Task 4: 列表状态由 `syncState` 驱动未同步

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: 更新 `displayStatus`**

将 `displayStatus` 中的 `needsSync` 计算调整为 power switch 专属分支：

```swift
    var displayStatus: PJEightKeySwitchStatus {
        if let node = proxyNode, !node.isKeybindComplete {
            return .repairRequiredMode
        }
        let isBound = proxyNode?.isPowerSwitch == true || !(enOceanMacAddress?.isEmpty ?? true)
        let needsSync: Bool
        if proxyNode?.isPowerSwitch == true {
            needsSync = syncState != .synced || needsBatteryPowerSwitchSync
        } else {
            needsSync = needSyncData
        }
        if isBound && needsSync {
            return .syncIssueBoundSwitch
        }
        if isBound {
            return enabled ? .boundEnabled : .boundDisabled
        }
        return enabled ? .unboundEnabled : .unboundDisabled
    }
```

- [ ] **Step 2: Verify 不再对 power switch 使用旧 kinetic sync 规则**

Run:

```sh
sed -n '266,282p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:
- `proxyNode?.isPowerSwitch == true` 分支中包含 `syncState != .synced || needsBatteryPowerSwitchSync`。
- 非 power switch 分支仍使用 `needSyncData`。

### Task 5: Switches 列表显示未同步状态 icon

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchesViewCell.swift`

- [ ] **Step 1: 更新 `configure` icon 选择**

将 `configure(with:eightKeySwitch:editing:)` 调整为先取得 status，并仅在特殊状态使用状态 icon：

```swift
    func configure(with switchData: DeviceSwitchData, eightKeySwitch: PJEightKeySwitchData, editing: Bool) {
        self.switchData = switchData
        nameLabel.text = switchData.name
        let status = eightKeySwitch.displayStatus
        switch status {
        case .syncIssueBoundSwitch, .repairRequiredMode:
            iconImageView.image = UIImage(named: status.iconAssetName)
        default:
            iconImageView.image = UIImage(named: eightKeySwitch.displayIconAssetName)
        }
        deleteBtn.isHidden = !editing
        applyStatus(status)
    }
```

说明：普通状态保留 `displayIconAssetName`，避免影响 AC offline 图标；未同步和 repair 状态使用已有状态资源。

- [ ] **Step 2: Verify 状态 icon 资源存在**

Run:

```sh
test -d SunSmart/Assets.xcassets/EightKeySwitches1.5/eight_key_switch_sync_issue.imageset
test -d SunSmart/Assets.xcassets/EightKeySwitches1.5/eight_key_switch_repair_required.imageset
```

Expected:
- 两条命令都返回 exit code 0。

### Task 6: 静态检查与编译验证

**Files:**
- Verify only

- [ ] **Step 1: 检查无遗漏旧 own-only 判断**

Run:

```sh
rg -n "containsBatteryPowerSwitchOwnConfiguration\\(failedOperationTypes\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected:
- 无输出。失败回调不再只用 own configuration 判断失败。

- [ ] **Step 2: 检查全 sync 判定覆盖 target subscription**

Run:

```sh
rg -n "case \\.batteryPowerSwitchKeyConfig,|batteryPowerSwitchTargetSubscription" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:
- `isPowerSwitchOwnConfigurationOperation` 覆盖 key config、TX、LED。
- `isPowerSwitchSyncOperation` 覆盖 key config、TX、LED、target subscription。

- [ ] **Step 3: 检查工作区只包含预期代码改动**

Run:

```sh
git status --short
```

Expected:
- 本计划列出的 7 个源码文件有修改。
- 允许存在用户已有未提交文件；不要暂存或回退与本任务无关的改动。

- [ ] **Step 4: 编译验证**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:
- Build succeeds。
- 如果失败，先确认是否为本次改动导致；如果是类型/访问控制错误，按最小范围修复后重复本命令。

- [ ] **Step 5: 提交实现**

只暂存本任务涉及源码和计划文档：

```sh
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git add SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchesViewCell.swift
git add docs/superpowers/plans/2026-06-06-power-switch-sync-failure.md
git commit -m "fix: mark power switch sync failures"
```

Expected:
- Commit succeeds。
- 不包含 unrelated dirty files。

## 手动验收清单

- Battery Power Switch 在 `Switch Configuration` 期间点击 `STOP`，返回 switches 列表显示未同步 icon。
- AC Power Switch 在 `Switch Configuration` 期间点击 `STOP`，返回 switches 列表显示未同步 icon。
- 任一 `Group Subscription` 失败，返回 switches 列表显示未同步 icon。
- 任一 `Group Unsubscription` 失败，返回 switches 列表显示未同步 icon。
- SAVE 全部任务成功，switch 状态为 synced，列表不显示未同步 icon。
- 普通 Kinetic Switch 未同步逻辑仍由 `needSyncData` 驱动。
