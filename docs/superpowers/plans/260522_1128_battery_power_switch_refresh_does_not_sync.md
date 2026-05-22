# Battery Power Switch Refresh Battery Sync Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Battery Power Switch Monitor 页的 refresh battery 按钮只刷新电量，不再在配置未完整时进入 SAVE/Sync 流程。

**Architecture:** 本次只调整 Monitor 页 refresh 入口的业务分支。`PJEightKeySwitchBatteryRefreshFlow` 继续负责 `Refresh Device` 电量刷新；`PJEightKeySwitchActivationFlow` 和 `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 继续只服务明确的配置同步入口。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK `GenericBatteryGet` / `SunricherVendorGet`、Xcode `xcodebuild`。

---

## 文件结构

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 修改 `refreshMonitor()`，删除 refresh battery 到 Battery Power Switch sync 的隐式跳转。
  - 保留 `pushBatteryPowerSwitchSync()`、`presentBatteryPowerSwitchActivation()`、`pushBatteryPowerSwitchSyncController()`，不改 SAVE/Sync 行为。
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
  - 只验证 refresh flow 仍使用 `GenericBatteryGet`，不修改。
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 只验证 activation flow 仍使用 Battery Power Switch capability probe，且不被 refresh battery 入口调用。

---

### Task 1: 拆开 Monitor Refresh Battery 与 Sync 入口

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:212-242`

- [ ] **Step 1: 记录当前异常分支**

Run:

```bash
nl -ba SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift | sed -n '212,242p'
```

Expected: 看到 `refreshMonitor()` 中存在以下分支：

```swift
guard !viewModel.needsBatteryPowerSwitchSync else {
    pushBatteryPowerSwitchSync()
    return
}
```

- [ ] **Step 2: 修改 `refreshMonitor()`，删除 sync 跳转分支**

将 `refreshMonitor()` 从当前实现：

```swift
private func refreshMonitor() {
    guard !isRefreshing else { return }
    guard !viewModel.needsBatteryPowerSwitchSync else {
        pushBatteryPowerSwitchSync()
        return
    }
    guard let node = viewModel.informationNode else {
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        return
    }
    isRefreshing = true
    headerView.setRefreshing(true)

    let flow = PJEightKeySwitchBatteryRefreshFlow(
        presenter: self,
        node: node,
        onBatteryLevel: { [weak self] level in
            guard let self else { return false }
            guard self.viewModel.saveBatteryLevel(level) else {
                return false
            }
            self.updateUI()
            return true
        },
        onFinished: { [weak self] in
            self?.finishBatteryRefresh()
        }
    )
    batteryRefreshFlow = flow
    flow.start()
}
```

改为：

```swift
private func refreshMonitor() {
    guard !isRefreshing else { return }
    guard let node = viewModel.informationNode else {
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        return
    }
    isRefreshing = true
    headerView.setRefreshing(true)

    let flow = PJEightKeySwitchBatteryRefreshFlow(
        presenter: self,
        node: node,
        onBatteryLevel: { [weak self] level in
            guard let self else { return false }
            guard self.viewModel.saveBatteryLevel(level) else {
                return false
            }
            self.updateUI()
            return true
        },
        onFinished: { [weak self] in
            self?.finishBatteryRefresh()
        }
    )
    batteryRefreshFlow = flow
    flow.start()
}
```

Do not modify:

```swift
private func pushBatteryPowerSwitchSync()
private func presentBatteryPowerSwitchActivation()
private func pushBatteryPowerSwitchSyncController()
```

- [ ] **Step 3: 验证 `refreshMonitor()` 不再触发 sync**

Run:

```bash
nl -ba SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift | sed -n '212,242p'
```

Expected: `refreshMonitor()` 中不再出现 `needsBatteryPowerSwitchSync` 或 `pushBatteryPowerSwitchSync()`。

- [ ] **Step 4: 验证 sync 方法仍保留**

Run:

```bash
rg -n "private func pushBatteryPowerSwitchSync\\(|private func presentBatteryPowerSwitchActivation\\(|private func pushBatteryPowerSwitchSyncController\\(" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: 仍有 3 个匹配：

```text
private func pushBatteryPowerSwitchSync()
private func presentBatteryPowerSwitchActivation()
private func pushBatteryPowerSwitchSyncController()
```

- [ ] **Step 5: 提交 Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "fix: keep battery refresh out of sync flow"
```

Expected: commit 成功，且只提交 `PJEightKeySwitchMonitorVC.swift`。

---

### Task 2: 验证 Refresh 与 SAVE 两条路径仍独立

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: 静态验证 refresh 入口不引用 sync 判断**

Run:

```bash
sed -n '212,242p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: 输出中不包含：

```text
needsBatteryPowerSwitchSync
pushBatteryPowerSwitchSync()
```

- [ ] **Step 2: 静态验证 refresh flow 仍读取电量**

Run:

```bash
rg -n "GenericBatteryGet|batteryRefreshProbeInterval|showUpdated\\(level:" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift
```

Expected: 至少包含：

```text
GenericBatteryGet()
batteryRefreshProbeInterval
showUpdated(level: level)
```

- [ ] **Step 3: 静态验证 SAVE activation flow 未被删除**

Run:

```bash
rg -n "SunricherVendorGet\\(function: \\.batteryPowerSwitchCapability\\)|PJEightKeySwitchActivationFlow|onDetectedCompleted|completeDetected" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected: 至少包含：

```text
SunricherVendorGet(function: .batteryPowerSwitchCapability)
final class PJEightKeySwitchActivationFlow
onDetectedCompleted
completeDetected
```

- [ ] **Step 4: 检查改动范围**

Run:

```bash
git status --short
```

Expected: 没有未提交的业务文件改动。若前面按 Task 1 提交完成，输出应为空。

- [ ] **Step 5: 运行 iPhoneOS Debug build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 输出包含：

```text
** BUILD SUCCEEDED **
```

如果 build 失败，先确认失败是否来自本计划修改的 `PJEightKeySwitchMonitorVC.swift`。如果失败来自无关文件或环境，记录首个失败原因，不修改无关模块。

- [ ] **Step 6: 记录手动 QA 场景**

在最终汇总中明确以下人工验证点：

```text
1. 配置未完整的 Battery Power Switch，在 Monitor 页点击 refresh battery，只展示 Refresh Device / 刷新设备。
2. Refresh Device 弹窗中按设备按键并收到电量后，只更新电量，不进入 SAVE/Sync 页面。
3. Refresh Device 弹窗超时或取消后，不进入 SAVE/Sync 页面。
4. Switch Edit 页面点击 SAVE，如果需要 own configuration，仍展示 Save After Activation / 激活后保存。
5. Edit SAVE 的激活弹窗检测到设备后，仍进入 Battery Power Switch 同步页面。
```

