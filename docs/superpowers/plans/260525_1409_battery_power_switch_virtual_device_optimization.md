# Battery Power Switch 虚拟设备详情页优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化未关联真实设备的 Battery Power Switch 详情页，让它显示 `Unlinked`、模拟操作静默、Enable 本地成功、菜单只保留 Edit / Delete，并支持直接本地删除。

**Architecture:** 在 `PJEightKeySwitchMonitorViewModel` 集中定义未关联虚拟 BPS 状态，并让 `PJEightKeySwitchMonitorVC` 通过该状态分流 Header、面板交互、Enable、菜单和删除。真实 Battery Power Switch 继续走现有同步、激活和设备控制路径。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、SQLite metadata repository、现有 `MeshNetworkManager` 本地缓存。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  - 增加未关联虚拟 BPS 状态。
  - 增加 Header status style：`unlinked`。
  - 让 Header 在虚拟未关联模式下返回 `Unlinked`。
  - 将持久化方法改为返回保存结果，并同步更新 `MeshNetworkManager.instance.switchs` 中同 id 的基础 switch。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 菜单根据虚拟未关联状态隐藏 Information / Identify。
  - 面板短按、长按、disabled tap 在虚拟未关联状态下静默 no-op。
  - Enable 在虚拟未关联状态下直接更新本地数据并刷新 UI。
  - Delete 在虚拟未关联状态下直接本地删除、通知刷新、提示 `done!`、关闭页面。
- No target/resource changes:
  - 不新增本地化 key，使用已有 `neightkeyswitches_unlinked`。
  - 不修改品牌 target、依赖或资源。

---

### Task 1: ViewModel 虚拟态与 Header 状态

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`

- [ ] **Step 1: Capture current relevant behavior**

Run:

```bash
rg -n "StatusStyle|isRealBatteryPowerSwitch|canRefreshBattery|headerState|batteryStatusStyle|statusText|statusColor|func persist" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
```

Expected: output shows `StatusStyle` only has `normal`, `lowBattery`, `unknown`; `batteryStatusStyle()` returns `.unknown` when battery update time is nil; `persist()` returns `Void`.

- [ ] **Step 2: Add virtual-unlinked status and Header behavior**

Edit `PJEightKeySwitchMonitorViewModel.swift`:

```swift
struct HeaderState {
    enum StatusStyle {
        case normal
        case lowBattery
        case unknown
        case unlinked
    }

    let batteryText: String
    let batteryIconSystemName: String
    let statusPrefixText: String
    let statusText: String
    let statusColor: UIColor
    let updatedText: String
    let style: StatusStyle
    let showsRefreshButton: Bool
}
```

Add this property near `isRealBatteryPowerSwitch`:

```swift
var isUnlinkedVirtualBatteryPowerSwitch: Bool {
    !isRealBatteryPowerSwitch
}
```

Update `batteryStatusStyle(now:)`:

```swift
func batteryStatusStyle(now: Date = Date()) -> HeaderState.StatusStyle {
    if isUnlinkedVirtualBatteryPowerSwitch {
        return .unlinked
    }
    guard let batteryLastUpdateTime = switchData.batteryLastUpdateTime else {
        return .unknown
    }
    let elapsed = max(0, now.timeIntervalSince1970 - TimeInterval(batteryLastUpdateTime))
    if elapsed > batteryStaleInterval {
        return .unknown
    }
    guard let level = reportedBatteryLevel() else {
        return .unknown
    }
    return level <= 10 ? .lowBattery : .normal
}
```

Update `statusText(for:)`:

```swift
func statusText(for style: HeaderState.StatusStyle) -> String {
    switch style {
    case .normal:
        return "neightkeyswitches_status_normal".localizedString
    case .lowBattery:
        return "neightkeyswitches_status_low_battery".localizedString
    case .unknown:
        return "neightkeyswitches_status_unknown".localizedString
    case .unlinked:
        return "neightkeyswitches_unlinked".localizedString
    }
}
```

Update `statusColor(for:)`:

```swift
func statusColor(for style: HeaderState.StatusStyle) -> UIColor {
    switch style {
    case .normal:
        return RGB(69, 197, 122)
    case .unknown, .unlinked:
        return RGB(148, 163, 184)
    case .lowBattery:
        return RGB(240, 162, 55)
    }
}
```

- [ ] **Step 3: Make persistence reusable for local virtual updates**

Replace `persist()` with this implementation:

```swift
@discardableResult
func persist() -> Bool {
    let baseSaved = switchData.save()
    let metadataSaved = PJEightKeySwitchRepository.shared.save(switchData)
    if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
        MeshNetworkManager.instance.switchs[index].update(switchData: switchData)
    }
    return baseSaved && metadataSaved
}
```

This preserves existing call sites that ignore the return value and gives the virtual Enable path a single local-save API.

- [ ] **Step 4: Verify ViewModel static state**

Run:

```bash
rg -n "case unlinked|isUnlinkedVirtualBatteryPowerSwitch|neightkeyswitches_unlinked|case \\.unknown, \\.unlinked|@discardableResult\\nfunc persist\\(\\) -> Bool" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
```

Expected: output includes the new `unlinked` style, the new virtual state property, the `neightkeyswitches_unlinked` return, shared gray color branch, and `persist() -> Bool`.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
git commit -m "feat: mark unlinked virtual battery switches"
```

Expected: commit succeeds.

---

### Task 2: Monitor VC 虚拟态交互分流

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Capture current VC behavior**

Run:

```bash
rg -n "moreAction|Identify|disabledTapAction|startTxEnableUpdate|handlePanelKeyTap|presentDimmingPopup|presentForcedAutoPopup|deleteCurrentSwitch|SyncDevicesViewController|showTipHUD\\(\"failed" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: output shows Identify is always appended, disabled tap shows a tip, Enable without node shows `failed`, and delete always opens a confirmation alert.

- [ ] **Step 2: Limit virtual-unlinked menu to Edit and Delete**

Replace `moreAction()` with:

```swift
@objc private func moreAction() {
    var items: [MenuPopView.MenuItem] = []
    if viewModel.space.deviceOperates.contains(.edit) {
        items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
            self?.pushEditor()
        }))
    }
    if viewModel.space.deviceOperates.contains(.delete) {
        items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
            self?.deleteCurrentSwitch()
        }))
    }
    if !viewModel.isUnlinkedVirtualBatteryPowerSwitch {
        if viewModel.isRealBatteryPowerSwitch {
            items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
                self?.pushInformation()
            }))
        }
        items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: { _ in
            // Identify
        }))
    }

    guard !items.isEmpty else {
        return
    }

    let touchCenterX = view.width - navigationRightItemMargin - 15
    let touchCenterY = view.safeAreaInsets.top - 10
    let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
    MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
}
```

- [ ] **Step 3: Make virtual-unlinked panel interactions silent**

Update `bindActions()` disabled tap closure:

```swift
panelView.disabledTapAction = { [weak self] in
    guard self?.viewModel.isUnlinkedVirtualBatteryPowerSwitch != true else {
        return
    }
    XWHUDManager.showTipHUD("neightkeyswitches_disabled_tip".localizedString, isLineFeed: true)
}
```

Update `handlePanelKeyTap(index:)`:

```swift
private func handlePanelKeyTap(index: Int) {
    guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
        return
    }
    guard shouldAcceptKeyTap(index: index) else {
        return
    }
    virtualGroupControlSender.sendKeyTap(index: index, switchData: viewModel.switchData)
}
```

Update `presentDimmingPopup()`:

```swift
private func presentDimmingPopup() {
    guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
        return
    }
    let vc = PJEightKeySwitchDimmingPopupController()
    vc.brightnessEndedAction = { [weak self] value in
        guard let self else { return }
        self.virtualGroupControlSender.sendBrightness(value, switchData: self.viewModel.switchData)
    }
    present(vc, animated: true)
}
```

Update `presentForcedAutoPopup()`:

```swift
private func presentForcedAutoPopup() {
    guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
        return
    }
    let vc = PJEightKeySwitchForcedAutoPopupController()
    vc.autoAction = { [weak self] in
        guard let self else { return }
        self.virtualGroupControlSender.sendAuto(switchData: self.viewModel.switchData)
    }
    present(vc, animated: true)
}
```

- [ ] **Step 4: Make virtual-unlinked Enable save locally**

Add this helper near `startTxEnableUpdate(_:)`:

```swift
private func updateUnlinkedVirtualEnable(_ isEnabled: Bool) {
    viewModel.updateEnabled(isEnabled)
    _ = viewModel.persist()
    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
    updateUI()
}
```

Update the beginning of `startTxEnableUpdate(_:)`:

```swift
private func startTxEnableUpdate(_ isEnabled: Bool) {
    guard pendingEnabledValue == nil else {
        updateUI()
        return
    }
    guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
        updateUnlinkedVirtualEnable(isEnabled)
        return
    }
    guard viewModel.informationNode != nil else {
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        updateUI()
        return
    }

    pendingEnabledValue = isEnabled
    updateUI()

    let flow = PJEightKeySwitchTxEnableFlow(
        presenter: self,
        switchData: viewModel.switchData,
        enabled: isEnabled,
        onSucceeded: { [weak self] enabled in
            guard let self else { return }
            self.viewModel.applyTxEnableSucceeded(enabled)
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
        },
        onFinished: { [weak self] in
            guard let self else { return }
            self.pendingEnabledValue = nil
            self.txEnableFlow = nil
            self.updateUI()
        }
    )
    txEnableFlow = flow
    flow.start()
}
```

- [ ] **Step 5: Make virtual-unlinked Delete local and immediate**

Add this helper near `deleteCurrentSwitch()`:

```swift
private func deleteUnlinkedVirtualSwitch() {
    MeshNetworkManager.instance.deleteSwitch(switchData: viewModel.switchData)
    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
    XWHUDManager.showSuccessTipHUD("done!".localizedString)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        self?.dismissLikeSystem()
    }
}
```

Update the beginning of `deleteCurrentSwitch()`:

```swift
private func deleteCurrentSwitch() {
    guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
        deleteUnlinkedVirtualSwitch()
        return
    }

    SRAlertView(
        title: "notification".localizedString,
        message: "switchs_delete_message".localizedString,
        actions: [
            .cancelAction,
            SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                guard let self else { return }
                self.dismiss(animated: true) {
                    self.deleteSwitchAction?(self.viewModel.switchData)
                }
            })
        ]
    ).show()
}
```

- [ ] **Step 6: Verify VC static routing**

Run:

```bash
rg -n "isUnlinkedVirtualBatteryPowerSwitch|updateUnlinkedVirtualEnable|deleteUnlinkedVirtualSwitch|Identify|showTipHUD\\(\"failed|PJEightKeySwitchTxEnableFlow|SyncDevicesViewController" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:
- `isUnlinkedVirtualBatteryPowerSwitch` appears in menu, panel tap, long press popup guards, Enable guard, and delete guard.
- `Identify` appears only inside the non-virtual menu branch.
- `PJEightKeySwitchTxEnableFlow` remains only in the non-virtual Enable path.
- `SyncDevicesViewController` remains only in existing sync methods, not in `deleteUnlinkedVirtualSwitch()`.

- [ ] **Step 7: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: handle unlinked battery switch locally"
```

Expected: commit succeeds.

---

### Task 3: Verification

**Files:**
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Inspect: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Verify no new localization or target changes**

Run:

```bash
git diff --name-only HEAD~2..HEAD
```

Expected: only these code files changed in implementation commits:

```text
SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

- [ ] **Step 2: Verify virtual Header and no refresh**

Run:

```bash
rg -n "case unlinked|neightkeyswitches_unlinked|showsRefreshButton: canRefreshBattery|canRefreshBattery" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift
```

Expected: `case unlinked` exists, `statusText(for:)` returns `neightkeyswitches_unlinked`, and refresh visibility still comes from `canRefreshBattery`, which requires a real battery power switch node.

- [ ] **Step 3: Verify virtual interactions do not send commands**

Run:

```bash
rg -n "handlePanelKeyTap|presentDimmingPopup|presentForcedAutoPopup|sendKeyTap|sendBrightness|sendAuto|MeshAPI.sendMessage" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: panel handlers guard `!viewModel.isUnlinkedVirtualBatteryPowerSwitch` before any sender call; `MeshAPI.sendMessage` remains only inside `PJEightKeySwitchVirtualGroupControlSender`.

- [ ] **Step 4: Verify virtual Enable and Delete do not sync**

Run:

```bash
rg -n "updateUnlinkedVirtualEnable|deleteUnlinkedVirtualSwitch|PJEightKeySwitchTxEnableFlow|SyncDevicesViewController|SRAlertView" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: `updateUnlinkedVirtualEnable` persists and posts notifications without creating `PJEightKeySwitchTxEnableFlow`; `deleteUnlinkedVirtualSwitch` deletes locally without `SRAlertView` or `SyncDevicesViewController`; real-device sync code remains unchanged.

- [ ] **Step 5: Build SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds. Existing warnings may remain, but there must be no new compile errors.

- [ ] **Step 6: Check worktree**

Run:

```bash
git status --short
```

Expected: clean worktree.

