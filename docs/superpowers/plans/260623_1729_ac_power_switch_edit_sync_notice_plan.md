# AC Power Switch Edit Sync Notice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AC power switch 在 Main - Switches 显示需要同步时，长按进入 Edit 页面也显示 `devices_not_synced` 提示，并点击进入同步页。

**Architecture:** 在 `PJEightKeySwitchData` 中收口一个 Battery/AC 共用的同步提示判断，让列表状态和 Edit 页按钮使用同一语义。Edit 页继续读取当前持久化/实时 switch 数据进入现有 `SyncDevicesViewController`，不引入 AC 专用同步页，也不混入未保存表单。

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 新增 `needsPowerSwitchSyncNotice` 计算属性，封装“真实 LINK 的 Battery/AC power switch 是否应显示同步提示”。
  - 调整 `displayStatus` 的 power switch need-sync 判断，复用该属性。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 将 Edit 页右上角按钮的显示和点击 guard 改为 `needsPowerSwitchSyncNotice`。
  - 保留 `currentEightKeySwitchData` 数据来源，确保点击同步使用持久化/实时数据。
- No new localization files:
  - `devices_not_synced` 已存在于 English 和简体中文。
- No test file changes:
  - 当前逻辑位于 UIKit 页面和 Mesh runtime 数据模型，仓库没有现成的轻量单元测试 harness 覆盖该类；使用代码检查和 iPhoneOS 构建验证。

---

### Task 1: 收口 Power Switch 同步提示判断

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [x] **Step 1: Add shared computed property**

在 `needsBatteryPowerSwitchSync` 后新增：

```swift
var needsPowerSwitchSyncNotice: Bool {
    guard proxyNode?.isPowerSwitch == true else {
        return false
    }
    return syncState != .synced || needsBatteryPowerSwitchSync
}
```

- [x] **Step 2: Reuse the shared property in displayStatus**

将 `displayStatus` 中 power switch 分支：

```swift
if proxyNode?.isPowerSwitch == true {
    needsSync = syncState != .synced || needsBatteryPowerSwitchSync
} else {
    needsSync = needSyncData
}
```

替换为：

```swift
if proxyNode?.isPowerSwitch == true {
    needsSync = needsPowerSwitchSyncNotice
} else {
    needsSync = needSyncData
}
```

- [x] **Step 3: Verify the property keeps AC activation unchanged**

确认同文件中仍保持：

```swift
var requiresActivationBeforeOwnConfiguration: Bool {
    powerSwitchKind == .battery
}
```

Expected: AC `.ac` 返回 false，不走 Battery activation。

---

### Task 2: Edit 页同步提示改用共享判断

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [x] **Step 1: Update click guard**

将 `syncFailedButtonAction()` 中：

```swift
guard let switchData = currentEightKeySwitchData,
      switchData.needsBatteryPowerSwitchSync else {
    updateSyncFailedButtonVisibility()
    return
}
```

替换为：

```swift
guard let switchData = currentEightKeySwitchData,
      switchData.needsPowerSwitchSyncNotice else {
    updateSyncFailedButtonVisibility()
    return
}
```

- [x] **Step 2: Update visibility condition**

将 `updateSyncFailedButtonVisibility()` 中：

```swift
editorView.syncFailedButton.isHidden = !switchData.needsBatteryPowerSwitchSync
```

替换为：

```swift
editorView.syncFailedButton.isHidden = !switchData.needsPowerSwitchSyncNotice
```

- [x] **Step 3: Preserve persisted/current data source**

确认 `syncFailedButtonAction()` 仍调用：

```swift
pushBatteryPowerSwitchSync(switchData)
```

其中 `switchData` 来自：

```swift
private var currentEightKeySwitchData: PJEightKeySwitchData?
```

Expected: 不调用 `viewModel.buildSwitchData()`，因此不会把未保存表单混入同步任务。

---

### Task 3: Verification

**Files:**
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [x] **Step 1: Search for old Edit-page guard usage**

Run:

```bash
rg -n "needsBatteryPowerSwitchSync|needsPowerSwitchSyncNotice|requiresActivationBeforeOwnConfiguration|syncFailedButtonAction|updateSyncFailedButtonVisibility" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected:
- `PJEightKeySwitchData` defines `needsPowerSwitchSyncNotice`.
- `displayStatus` uses `needsPowerSwitchSyncNotice`.
- `PJPreAddEightKeySwitchesVC` button guard and visibility use `needsPowerSwitchSyncNotice`.
- `requiresActivationBeforeOwnConfiguration` still returns `powerSwitchKind == .battery`.

- [x] **Step 2: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [x] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

---

## Self-Review

- Spec coverage: Main - Switches 与 Edit 页同步提示语义对齐由 Task 1 和 Task 2 覆盖；AC 不走 activation 由 Task 1 和 Task 3 覆盖；未保存表单不混入同步由 Task 2 覆盖。
- Placeholder scan: 无占位项。
- Type consistency: `needsPowerSwitchSyncNotice` 是 `PJEightKeySwitchData` 的计算属性，Task 1 定义后 Task 2 使用；`currentEightKeySwitchData` 和 `pushBatteryPowerSwitchSync(_:)` 均为现有方法。
