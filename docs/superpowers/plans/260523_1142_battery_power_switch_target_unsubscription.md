# Battery Power Switch Target Unsubscription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery Power Switch target group 退订任务不下发消息导致 `Remove Switch` 持续失败的问题，并统一相关 BPS target subscription 展示语义。

**Architecture:** 保留现有 `deleteSwitchs` / `syncSwitchs` 数据流，只在 `DeviceOperationType.messageHandles` 中补齐 BPS target subscription 的 delete 分支，并在 `SyncDevicesViewController` 中让纯 BPS target group 任务显示为 Group Subscription / Group Unsubscription。`unbindGroupAddresses` 仍由现有 virtual group delete 成功后的状态检查清理，不引入新的状态存储。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Xcode workspace、xcodebuild。

---

## Scope Check

Spec 聚焦一个子系统：Battery Power Switch target group subscription / unsubscription。它覆盖多个入口，但共享同一套 `DeviceOperationType` 和 SyncDevices 任务展开路径，不需要拆成多个 plan。

当前工程未发现可用 XCTest target，本计划不新增测试 target，避免扩大 target 配置和多品牌 target 影响面。验证使用精确静态检查、直接 iOS 构建和真实设备手工复现。

## File Structure

- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 负责 `DeviceOperationType.messageHandles` 的实际消息生成。
  - 本次只补齐 `.delete + .batteryPowerSwitchTargetSubscription` 分支。

- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 负责 Sync device(s) 页面任务模型生成。
  - 本次只调整纯 BPS `.syncSwitchs` / `.deleteSwitchs` 步骤标题，避免 BPS target unsubscription 继续显示为传统 `Remove Switch`。

- Verify only: `SunSmart/Common/Data/Node+SyncData.swift`
  - 确认 BPS 已走 `getBatteryPowerSwitchTargetSubscriptionMessageHandles`，不回落到传统 EnOcean `switchKeys`。

- Verify only: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 确认 BPS target subscription / unsubscription 的差异 handles 和 `unbindGroupAddresses` 清理逻辑保持可用。

---

### Task 1: Baseline Static Checks

**Files:**
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: Confirm all BPS target subscription call sites**

Run:

```bash
rg -n "batteryPowerSwitchTargetSubscription" SunSmart --glob '!user-temp/**'
```

Expected:

- `SyncDevicesCellModel.swift` has success checks and message handle generation.
- `SyncDevicesViewController.swift` creates BPS target subscription tasks.
- No other file creates `batteryPowerSwitchTargetSubscription`.

- [ ] **Step 2: Confirm BPS delete branch currently has no message generation**

Run:

```bash
sed -n '400,455p' SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected before Task 2:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator, .batteryPowerSwitchTargetSubscription:
    break
```

This confirms `.delete + .batteryPowerSwitchTargetSubscription` is skipped.

- [ ] **Step 3: Confirm BPS paths already avoid traditional EnOcean switchKeys**

Run:

```bash
sed -n '1398,1450p' SunSmart/Common/Data/Node+SyncData.swift
sed -n '1495,1540p' SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- `getNodeSyncSwitchs` uses `getBatteryPowerSwitchTargetSubscriptionMessageHandles(... unsubscribe: false)` for BPS.
- `getNodeNeedDeleteSwitchs` uses `getBatteryPowerSwitchTargetSubscriptionMessageHandles(... unsubscribe: true)` for BPS.
- `DeviceSwitchData.getNeedSyncDatas` uses BPS target handles for both sync and delete directions.

---

### Task 2: Generate Messages For BPS Target Unsubscription In Delete Operations

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Split BPS target subscription out of the delete no-op branch**

In `DeviceOperationType.messageHandles`, inside the `.delete` branch, replace:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator, .batteryPowerSwitchTargetSubscription:
    break
```

with:

```swift
case .batteryPowerSwitchTargetSubscription(let switchData, _, let unsubscribe):
    messageHandles.append(contentsOf: node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: unsubscribe))
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
    break
```

Rationale:

- Group member removal creates `.delete(... batteryPowerSwitchTargetSubscription(... unsubscribe: true))`.
- The action already carries direction, so the delete branch should honor it instead of assuming all BPS operations are own configuration no-ops.
- BPS own configuration remains unavailable in delete operations.

- [ ] **Step 2: Run static check for the new delete branch**

Run:

```bash
sed -n '400,455p' SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:

```swift
case .batteryPowerSwitchTargetSubscription(let switchData, _, let unsubscribe):
    messageHandles.append(contentsOf: node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: unsubscribe))
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
    break
```

- [ ] **Step 3: Confirm configuration branch still generates BPS target messages**

Run:

```bash
sed -n '560,572p' SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:

```swift
case .batteryPowerSwitchTargetSubscription(let switchData, _, let unsubscribe):
    messageHandles.append(contentsOf: node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: unsubscribe))
```

- [ ] **Step 4: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: send battery switch target unsubscription"
```

Expected: commit succeeds with only `SyncDevicesCellModel.swift` staged.

---

### Task 3: Make Pure BPS Target Tasks Use BPS-Specific Step Titles

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Update `.syncSwitchs` step title for pure BPS target subscription**

In `getSyncDeviceModel(group:node:effectiveMemberCount:)`, inside `case .syncSwitchs(let switchDatas)`, replace:

```swift
let step = SyncDeviceStepModel(type: "switch".localizedString, state: .none, tasks: syncSwitchTasks)
```

with:

```swift
let stepTitle = switchDatas.allSatisfy { $0.batteryPowerSwitchData != nil }
    ? "Group Subscription"
    : "switch".localizedString
let step = SyncDeviceStepModel(type: stepTitle, state: .none, tasks: syncSwitchTasks)
```

Rationale:

- BPS target subscription is not a traditional switch binding operation.
- Existing BPS dedicated sync page already uses `Group Subscription`, so this keeps UI wording consistent without adding localization keys.
- Mixed traditional/BPS tasks keep the old `switch` title to avoid mislabeling traditional switch work.

- [ ] **Step 2: Update `.deleteSwitchs` step title for pure BPS target unsubscription**

In the same method, inside `case .deleteSwitchs(let switchDatas)`, replace:

```swift
let step = SyncDeviceStepModel(type: "remove_switch".localizedString, state: .none, tasks: deleteSwitchTasks)
```

with:

```swift
let stepTitle = switchDatas.allSatisfy { $0.batteryPowerSwitchData != nil }
    ? "Group Unsubscription"
    : "remove_switch".localizedString
let step = SyncDeviceStepModel(type: stepTitle, state: .none, tasks: deleteSwitchTasks)
```

Rationale:

- The user-facing symptom is `0/2 Remove Switch`, but the BPS operation is target device virtual group unsubscription.
- This change keeps traditional switch removal text unchanged.

- [ ] **Step 3: Run static check for step titles**

Run:

```bash
sed -n '1284,1318p' SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `.syncSwitchs` uses `Group Subscription` only when all switch data are Battery Power Switch.
- `.deleteSwitchs` uses `Group Unsubscription` only when all switch data are Battery Power Switch.
- Existing `batteryPowerSwitchTargetSubscription` task creation remains unchanged.

- [ ] **Step 4: Confirm no localization resources were modified**

Run:

```bash
git diff --name-only
```

Expected:

- Only `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift` is listed for Task 3.
- No `.strings`, assets, target config, Podfile, or project file changes.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: label battery switch target group tasks"
```

Expected: commit succeeds with only `SyncDevicesViewController.swift` staged.

---

### Task 4: Verify Removed Group State Handling Stays Correct

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Confirm BPS success marker can preserve removed groups**

Run:

```bash
sed -n '160,174p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:

```swift
func markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: Bool = true) {
    syncState = .synced
    appliedConfigHash = desiredConfigHash
    appliedTxEnabled = enabled
    appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled
    lastSyncFailedReason = nil
    lastSyncedAt = Int64(Date().timeIntervalSince1970)
    if clearRemovedGroups {
        unbindGroupAddresses.removeAll()
    }
}
```

- [ ] **Step 2: Confirm per-group cleanup still depends on successful virtual group delete**

Run:

```bash
sed -n '2400,2420p' SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- On successful `ConfigModelSubscriptionDelete` for a virtual group, code finds the matching switch data.
- It removes one `unbindGroupAddresses` entry only when the node group no longer contains nodes that still need BPS target unsubscription.

- [ ] **Step 3: Confirm BPS failure callbacks preserve removed groups when only own configuration succeeded**

Run:

```bash
sed -n '535,544p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
sed -n '377,386p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

```swift
switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
```

and:

```swift
self.viewModel.switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
```

Rationale:

- Task 2 makes target unsubscription tasks actually run.
- On full sync success, clearing removed groups remains acceptable.
- On partial failure, existing callbacks already preserve removed groups, and per-group cleanup handles successful target unsubscriptions.

- [ ] **Step 4: Do not change state handling unless one of the checks fails**

If Steps 1-3 match expected output, do not edit these files. This keeps the fix focused and avoids changing Battery Power Switch own configuration state semantics.

---

### Task 5: Full Static Verification And Build

**Files:**
- Verify: whole workspace

- [ ] **Step 1: Confirm only intended source files changed after implementation**

Run:

```bash
git status --short
```

Expected after Task 2 and Task 3 commits:

- No unstaged source changes.
- The implementation commits should already contain the modified source files.

- [ ] **Step 2: Confirm all BPS target subscription operation sites are accounted for**

Run:

```bash
rg -n "batteryPowerSwitchTargetSubscription" SunSmart/Main/Space --glob '!user-temp/**'
```

Expected:

- `SyncDevicesCellModel.swift` has:
  - success check in `.delete`
  - success check in `.configuration`
  - message generation in `.delete`
  - message generation in `.configuration`
  - action enum case
- `SyncDevicesViewController.swift` has:
  - BPS target task generation for sync
  - BPS target task generation for delete
  - BPS sync operation classification

- [ ] **Step 3: Confirm no accidental localization, resource, target, or dependency changes**

Run:

```bash
git diff HEAD --name-only
git diff HEAD~2..HEAD --name-only
```

Expected:

- `git diff HEAD --name-only` is empty.
- `git diff HEAD~2..HEAD --name-only` lists only:
  - `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 4: Build SunSmart directly with xcodebuild**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- If build fails because of unrelated existing issues, capture the first relevant compiler error and do not mask it with extra changes.

- [ ] **Step 5: Manual regression checklist**

Use real devices or the existing manual QA setup:

1. Add light to Group A.
2. Add Battery Power Switch and include Group A as target control group.
3. Confirm BPS can control the light.
4. Remove the light from Group A members.
5. Open Sync device(s).
6. Confirm the BPS target cleanup task is shown as `Group Unsubscription` when the step contains only BPS tasks.
7. Run sync and confirm the task completes.
8. Confirm the light no longer subscribes to the BPS virtual group.
9. Repeat with a traditional EnOcean/Kinetic switch if available and confirm its removal still shows the old switch removal wording and still syncs normally.

---

## Completion Criteria

- `.delete + .batteryPowerSwitchTargetSubscription` generates target subscription difference handles.
- Pure BPS target subscription/unsubscription steps no longer present as traditional `Switch` / `Remove Switch`.
- `unbindGroupAddresses` cleanup remains tied to successful target unsubscription or full successful BPS sync.
- No localization, resource, target config, Pod dependency, or unrelated module changes.
- Direct `xcodebuild` for `SunSmart` succeeds, or any build blocker is clearly reported with exact compiler output.
