# Battery Power Switch Activation Sync Delay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battery Power Switch 激活与 Sync 配置阶段避开设备刚入网后的消息拥塞窗口，降低 Reset/Config 被设备过滤的概率。

**Architecture:** 保持现有激活流程与 SyncDevicesViewController 的同步队列结构不变，仅在 BPS 专属分支加入时间保护。激活探测从 2 秒改为 3 秒；Sync 页面每轮同步记录 Reset 最早发送时间，Reset 失败后重试也重新计算等待时间，Reset 成功后阻塞后台队列 500ms 再继续 Key Config / Model Publication。

**Tech Stack:** Swift, UIKit, Timer, DispatchQueue, MeshProxyMessageCommand, NordicSigMeshSDK

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 负责 Battery Power Switch 激活等待页的探测节奏。
  - 只修改 `PJEightKeySwitchActivationFlow.startWaiting()` 中的 probe timer 间隔。

- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 负责 Sync device(s) 页面的 BPS Reset/Config 下发顺序和状态。
  - 新增 BPS Reset 首发保护、重试等待、Reset 成功后 500ms 处理窗口、等待期间停止/返回保护。

- Verify only: `SunSmart.xcworkspace`
  - 使用 AGENTS.md 指定的 xcodebuild 命令验证 SunSmart iPhoneOS Debug 编译。

---

### Task 1: 激活探测间隔改为 3 秒

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: 定位激活等待 probe timer**

Run:

```bash
rg -n "probeTimer|showDetected|scheduledTimer" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- `probeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true)` 位于 `PJEightKeySwitchActivationFlow.startWaiting()`。
- `DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)` 位于 `showDetected()`，保持不改。

- [ ] **Step 2: 修改 probe timer 间隔**

Replace this block in `PJEightKeySwitchActivationFlow.startWaiting()`:

```swift
probeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
    guard let self else { return }
    self.sendProbe(for: self.generation)
}
```

With:

```swift
probeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
    guard let self else { return }
    self.sendProbe(for: self.generation)
}
```

- [ ] **Step 3: 静态确认探测成功后进入 Sync 仍保持 1 秒**

Run:

```bash
rg -n "asyncAfter\\(deadline: \\.now\\(\\) \\+ 1\\.0|scheduledTimer\\(withTimeInterval: 3" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- 输出包含 `scheduledTimer(withTimeInterval: 3`。
- 输出包含 `asyncAfter(deadline: .now() + 1.0`。

- [ ] **Step 4: 提交激活探测间隔改动**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
git commit -m "fix: slow battery switch activation probe"
```

Expected:

- Commit 只包含 `PJEightKeySwitchActivationAlertController.swift` 的 probe 间隔改动。

---

### Task 2: Sync 页面加入 BPS Reset 等待与取消保护

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: 添加 BPS Reset 时间常量与同步轮次标识**

In `SyncDevicesViewController`, near the existing BPS properties:

```swift
private var batteryPowerSwitchActivationFlow: PJEightKeySwitchActivationFlow?
private var batteryPowerSwitchOwnConfigurationFailed = false
private var batteryPowerSwitchConfigurationResetCompleted = false
```

Replace with:

```swift
private var batteryPowerSwitchActivationFlow: PJEightKeySwitchActivationFlow?
private var batteryPowerSwitchOwnConfigurationFailed = false
private var batteryPowerSwitchConfigurationResetCompleted = false
private var batteryPowerSwitchResetEarliestDate: Date?
private var syncRunIdentifier = UUID()

private static let batteryPowerSwitchResetInitialDelay: TimeInterval = 3
private static let batteryPowerSwitchPostResetProcessingDelay: TimeInterval = 0.5
```

Expected:

- `batteryPowerSwitchResetEarliestDate` 每轮 BPS 同步记录 Reset 最早允许发送时间。
- `syncRunIdentifier` 用于等待期间识别当前同步轮次是否仍有效。

- [ ] **Step 2: 添加同步轮次与 Reset 等待 helper**

Add these methods near the existing BPS helper region, before `private var batteryPowerSwitchDataForSync`:

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

private func isActiveSyncRun(_ identifier: UUID) -> Bool {
    syncRunIdentifier == identifier && syncState == .inSync
}

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

Expected:

- 首轮 BPS Reset 不早于 Sync 轮次开始后 3 秒。
- Reset 失败后用户点击重试会重新进入 `startSync()`，从而重新设置 3 秒等待。
- 非 BPS 同步不会设置等待时间。

- [ ] **Step 3: 在 startSync 开始时创建同步轮次**

In `startSync()`, after:

```swift
batteryPowerSwitchOwnConfigurationFailed = false
batteryPowerSwitchConfigurationResetCompleted = false
```

Insert:

```swift
let syncRunIdentifier = beginSyncRun()
```

Expected:

- 每次 `startSync()`，包括普通重试和 `startBatteryPowerSwitchConfigurationResyncAfterActivation()`，都会得到新的同步轮次。

- [ ] **Step 4: 后台循环开始处检查当前同步轮次**

Inside `DispatchQueue.global().async { ... }`, immediately after:

```swift
while let model = self.getNextHandleModel() {
```

Insert:

```swift
guard self.isActiveSyncRun(syncRunIdentifier) else {
    return
}
```

Expected:

- 如果等待期间用户停止或返回，后台循环不会继续发下一条命令。

- [ ] **Step 5: Reset 下发前执行首发/重试等待**

In `startSync()`, after the existing missing-handle guard:

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

Insert before `MeshProxyMessageCommand.shared.addMessage(...)`:

```swift
guard self.waitBeforeBatteryPowerSwitchResetIfNeeded(for: model, syncRunIdentifier: syncRunIdentifier) else {
    return
}
```

Expected:

- 只有 `.batteryPowerSwitchReset` 会等待。
- 等待期间不更新 UI 文案，不显示倒计时。
- 停止或返回后，等待结束不会继续下发 Reset。

- [ ] **Step 6: Reset 成功后等待 500ms 再继续配置**

In the success branch inside `MeshProxyMessageCommand.shared.addMessage` completion, replace:

```swift
if self.isBatteryPowerSwitchResetConfiguration(model) {
    self.batteryPowerSwitchConfigurationResetCompleted = true
}
```

With:

```swift
if self.isBatteryPowerSwitchResetConfiguration(model) {
    self.waitAfterBatteryPowerSwitchResetSuccessIfNeeded(for: model)
    self.batteryPowerSwitchConfigurationResetCompleted = true
}
```

Expected:

- Reset 成功后，后台同步队列等待 500ms，再允许下一轮 Key Config / Model Publication 生成有效 message handles。
- Reset 失败不等待 500ms，仍按现有失败流程进入重试状态。

- [ ] **Step 7: Stop 与 Back 使等待中的同步轮次失效**

At the start of `backAction()`, before `applyProfileSensorTargetStateInBackgroundIfNeeded()`:

```swift
invalidateCurrentSyncRun()
```

In `rightItemAction()`, inside the `if syncState == .inSync { // stop` branch, before `MeshProxyMessageCommand.shared.stopSendMessage`:

```swift
invalidateCurrentSyncRun()
```

Expected:

- 用户点返回或 Stop 时，等待中的 Reset 不再发送。
- 用户在 `.syncFailure` 点击重试时不调用 `invalidateCurrentSyncRun()`；重试通过 `startSync()` 创建新轮次。

- [ ] **Step 8: 静态确认 BPS 等待只作用于 Reset**

Run:

```bash
rg -n "batteryPowerSwitchResetInitialDelay|batteryPowerSwitchPostResetProcessingDelay|waitBeforeBatteryPowerSwitchResetIfNeeded|waitAfterBatteryPowerSwitchResetSuccessIfNeeded|invalidateCurrentSyncRun|beginSyncRun" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `beginSyncRun()` 在 `startSync()` 调用一次。
- `waitBeforeBatteryPowerSwitchResetIfNeeded` 在 `MeshProxyMessageCommand.shared.addMessage` 前调用。
- `waitAfterBatteryPowerSwitchResetSuccessIfNeeded` 在 Reset 成功分支调用。
- `invalidateCurrentSyncRun()` 在 `backAction()` 和 Stop 分支调用。

- [ ] **Step 9: 提交 Sync 等待保护改动**

Run:

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: delay battery switch reset sync"
```

Expected:

- Commit 只包含 `SyncDevicesViewController.swift` 的 BPS Reset 等待、500ms post-reset delay、停止/返回保护。

---

### Task 3: 编译与行为验证

**Files:**
- Verify: `SunSmart.xcworkspace`

- [ ] **Step 1: 确认工作区只有本计划相关代码改动**

Run:

```bash
git status --short
```

Expected:

- 没有意外的源码文件改动。
- 允许存在本次计划文档或用户先前留下的未跟踪 docs 文件。

- [ ] **Step 2: 验证关键代码位置**

Run:

```bash
rg -n "scheduledTimer\\(withTimeInterval: 3|asyncAfter\\(deadline: \\.now\\(\\) \\+ 1\\.0" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- 激活 probe timer 是 3 秒。
- 探测成功后进入 Sync 的 delay 仍是 1 秒。

Run:

```bash
rg -n "batteryPowerSwitchResetInitialDelay: TimeInterval = 3|batteryPowerSwitchPostResetProcessingDelay: TimeInterval = 0\\.5|Thread\\.sleep\\(forTimeInterval: waitTime\\)|Thread\\.sleep\\(forTimeInterval: Self\\.batteryPowerSwitchPostResetProcessingDelay\\)" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- Sync 页面 BPS Reset 首发/重试等待是 3 秒。
- Reset 成功后的处理窗口是 500ms。

- [ ] **Step 3: 编译 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

- [ ] **Step 4: 如有设备条件，手动验证 BPS 流程**

Manual verification:

1. 添加 PID 为 `0x2A01` 或 `0x2A02` 的 Battery Power Switch。
2. 激活等待页观察探测节奏，连续探测间隔约 3 秒。
3. 探测成功后进入 Sync device(s) 页面，页面仍约 1 秒后开始流程。
4. 首个 Reset 不早于 Sync 页面该轮同步开始后约 3 秒发送。
5. Reset 成功后，Key Config / Model Publication 不会立刻紧贴 Reset 发送，存在约 500ms 处理窗口。
6. 如果 Switch Configuration 失败后点击重试，重发 Reset 前再次等待约 3 秒。
7. 等待期间点 Stop 或返回，不继续发送等待中的 Reset。

Expected:

- 等待时间不显示给用户。
- 失败场景仍保留现有失败/重试 UI。
- 非 Battery Power Switch 同步流程不出现新增等待。

---

## Self-Review

- Spec coverage:
  - Probe 间隔改 3 秒：Task 1。
  - 探测成功后进入 Sync 保持 1 秒：Task 1 静态确认，不改现有 `showDetected()`。
  - Sync 页面 BPS Reset 首发不早于页面/同步轮次开始后 3 秒：Task 2。
  - Switch configuration 失败后重发 Reset 前等待 3 秒：Task 2 通过每次 `startSync()` 重置 `batteryPowerSwitchResetEarliestDate` 覆盖。
  - Reset 成功后等待 500ms：Task 2。
  - 不展示等待时间给用户：Task 2 不改 UI 文案，Task 3 手动验证。
  - 停止/返回期间不继续发送等待中的 Reset：Task 2 同步轮次失效保护。

- Red-flag scan:
  - 本计划不包含未定义步骤。

- Type consistency:
  - 新增 helper 使用现有 `SyncCellModel`、`isBatteryPowerSwitchResetConfiguration(_:)`、`batteryPowerSwitchDataForSync`、`syncState`。
  - `Thread.sleep` 只在 `DispatchQueue.global()` 的后台同步流程中执行，不阻塞主线程。
