# EFC Virtual Device Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Others 页面短按未绑定虚拟 EFC 进入虚拟 EFC 设备页，并在该页固定展示 Unlinked、阻止未绑定设备执行命令、只提供 Edit/Delete 菜单。

**Architecture:** 采用方案 A，在现有 `EmerFireAlarmMonitorVC` 内按 `currentDevice?.bindNode == nil` 分流虚拟设备行为。Others 页只修正短按路由；设备页内分别收口 action guard、右上角菜单和本地删除流程，真实 EFC cleanup + Reset 删除流程保持不变。

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, shell contract script, iPhoneOS xcodebuild。

---

## File Structure

- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
  - 负责 Others 页面短按/长按路由。
  - 本计划只改 EFC 短按分支，让 `.unboundDevice` 进入设备页，保留 `.syncIssueDevice` 进入 Edit。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - 负责 EFC 设备页底部按钮 action。
  - 新增未绑定设备 guard，并让 Identify / Mock fire alarm / Mock power loss / Mock restore 都优先使用。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
  - 负责 EFC 设备页右上角菜单与删除流程。
  - 新增未绑定虚拟设备菜单分支和本地删除流程，真实 EFC 删除继续走共享 cleanup + Reset helper。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 新增 EFC 虚拟设备删除确认文案。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增 EFC 虚拟设备删除确认文案中文翻译。
- Modify: `scripts/check_efc_controller_flows.sh`
  - 增加 contract，锁定短按路由、未绑定 action guard、虚拟菜单和虚拟删除边界。

## Task 1: Add Failing Contract For Virtual EFC Page

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add route and action guard assertions**

In `scripts/check_efc_controller_flows.sh`, after the existing Others long-press assertions and before the shared delete flow assertions, add:

```bash
assert_not_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "device.displayStatus == .unboundDevice || device.displayStatus == .syncIssueDevice" \
  "Others page short tap must not send unlinked virtual EFC directly to Edit."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "if device.displayStatus == .syncIssueDevice" \
  "Others page short tap should still route sync-issue EFC to Edit."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guardLinkedDeviceForAction()" \
  "EFC device page actions must share an unlinked-device guard."

assert_count "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guard guardLinkedDeviceForAction()" \
  "4" \
  "Identify and three Mock actions must all guard unlinked virtual EFC before executing."
```

- [ ] **Step 2: Add virtual menu and delete assertions**

In the same script, near the `EmerFireAlarmMonitorRouting.swift` assertions, add:

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "isUnlinkedVirtualEmergencyFireController" \
  "EFC device page menu must explicitly identify unlinked virtual EFC."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "showUnlinkedVirtualEmergencyFireControllerMenu" \
  "Unlinked virtual EFC menu must be separated from real EFC menu items."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "deleteUnlinkedVirtualEmergencyFireController" \
  "Unlinked virtual EFC Delete must use a local-only deletion flow."

assert_contains "SunSmart/en.lproj/Localizable.strings" \
  "Are you sure to delete the EFC device?" \
  "English localization must include virtual EFC delete confirmation."

assert_contains "SunSmart/zh-Hans.lproj/Localizable.strings" \
  "Are you sure to delete the EFC device?" \
  "Chinese localization must include virtual EFC delete confirmation key."
```

- [ ] **Step 3: Run contract and verify it fails**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL on the first new assertion that has not been implemented yet, such as:

```text
FAIL: Others page short tap must not send unlinked virtual EFC directly to Edit.
```

- [ ] **Step 4: Commit contract**

Run:

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: cover virtual EFC device page"
```

Expected: commit only the script change for the failing contract.

## Task 2: Route Virtual EFC Short Tap To Device Page

**Files:**
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Update the EFC short tap branch**

In `DeviceOthersViewController.collectionView(_:didSelectItemAt:)`, replace the EFC branch with:

```swift
case .emergencyFireController(let device):
    if device.displayStatus == .syncIssueDevice {
        openEmergencyFireEdit(for: device)
        return
    }
    let config = makeLinkedEmerFireConfig(from: device)
    let vc = EmerFireAlarmMonitorVC(space: space, device: device, config: config)
    if isIPad {
        vc.preferredContentSize = iPadPreferredContentSize
    }
    present(NavigationViewController(rootViewController: vc), animated: true)
```

This preserves direct Edit for `.syncIssueDevice` and sends `.unboundDevice` to the device page.

- [ ] **Step 2: Run contract and verify routing assertion passes**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: route assertions pass; script still fails on later unimplemented virtual action/menu assertions.

- [ ] **Step 3: Commit short tap route**

Run:

```bash
git add SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
git commit -m "fix: open virtual EFC device page on tap"
```

Expected: commit only the Others route change.

## Task 3: Guard Virtual EFC Action Buttons

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add shared unlinked-device guard**

In `EmerFireAlarmMonitorVC`, near `canConfigureDevice`, add:

```swift
func guardLinkedDeviceForAction() -> Bool {
    guard currentDevice?.bindNode != nil else {
        XWHUDManager.showTipHUD("Not executed. Please link a device first.".localizedString, isLineFeed: true)
        return false
    }
    return true
}
```

- [ ] **Step 2: Use guard in Identify**

Change `identifyAction()` to start with:

```swift
@discardableResult
func identifyAction() -> Bool {
    guard guardLinkedDeviceForAction() else {
        return false
    }
    guard let healthModel = currentDevice?.bindNode?.healthModel else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    MeshAPI.sendMessage(message: AttentionSet(attentionTimer: 6), model: healthModel, timeout: 5) { response in
        if response == nil {
            DispatchQueue.main.async {
                XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
            }
        }
    }
    return true
}
```

- [ ] **Step 3: Use guard in Mock fire alarm**

Change `mockFireAlarmAction()` to start with:

```swift
@discardableResult
func mockFireAlarmAction() -> Bool {
    guard guardLinkedDeviceForAction() else {
        return false
    }
    guard guardMockActionHasAssociatedGroup() else {
        return false
    }
    guard let configuration = currentEmergencyConfiguration() else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    return sendBrightness(configuration.fireAlarmSettings.triggerBrightness, logName: "mock fire alarm")
}
```

- [ ] **Step 4: Use guard in Mock power loss**

Change `mockPowerLossAction()` to start with:

```swift
@discardableResult
func mockPowerLossAction() -> Bool {
    guard guardLinkedDeviceForAction() else {
        return false
    }
    guard guardMockActionHasAssociatedGroup() else {
        return false
    }
    guard let configuration = currentEmergencyConfiguration() else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    return sendBrightness(configuration.powerLossSettings.triggerBrightness, logName: "mock power loss")
}
```

- [ ] **Step 5: Use guard in Mock restore**

Change `mockRestoreAction()` to start with:

```swift
@discardableResult
func mockRestoreAction() -> Bool {
    guard guardLinkedDeviceForAction() else {
        return false
    }
    guard guardMockActionHasAssociatedGroup() else {
        return false
    }
    guard let configuration = currentEmergencyConfiguration() else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    switch configuration.restoreSettings.actionType {
    case .restoreAuto:
        return lightLCOnAction(logName: "mock restore auto")
    case .setBrightness:
        return sendBrightness(configuration.restoreSettings.brightness, logName: "mock restore brightness")
    case .none:
        print("[EFC] mock restore none")
        return true
    }
}
```

- [ ] **Step 6: Run contract and verify action assertions pass**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: action guard assertions pass; script still fails on unimplemented menu/localization assertions.

- [ ] **Step 7: Commit action guard**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
git commit -m "fix: guard virtual EFC actions"
```

Expected: commit only the monitor action guard change.

## Task 4: Add Virtual EFC Menu And Local Delete Flow

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add virtual EFC helper property**

In `extension EmerFireAlarmMonitorVC`, before `moreClick()`, add:

```swift
var isUnlinkedVirtualEmergencyFireController: Bool {
    currentDevice?.bindNode == nil
}
```

- [ ] **Step 2: Split menu at the top of `moreClick()`**

Change the beginning of `moreClick()` to:

```swift
@objc func moreClick() {
    if isUnlinkedVirtualEmergencyFireController {
        showUnlinkedVirtualEmergencyFireControllerMenu()
        return
    }

    let config = currentConfig ?? currentDevice.map(viewModel.makeConfig(from:))
    var items: [MenuPopView.MenuItem] = []
```

Keep the existing real EFC menu body after this block.

- [ ] **Step 3: Add virtual-only menu**

In the same extension, add:

```swift
private func showUnlinkedVirtualEmergencyFireControllerMenu() {
    let config = currentConfig ?? currentDevice.map(viewModel.makeConfig(from:))
    var items: [MenuPopView.MenuItem] = []
    if canConfigureDevice {
        items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
            self?.openEditSettings(config: config)
        }))
    }
    if space?.deviceOperates.contains(.delete) ?? false {
        items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
            self?.confirmDeleteUnlinkedVirtualEmergencyFireController()
        }))
    }

    let touchCenterX = view.width - navigationRightItemMargin - 15
    let touchCenterY = view.safeAreaInsets.top - 10
    let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
    MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
}
```

- [ ] **Step 4: Add virtual delete confirmation**

In the same extension, add:

```swift
private func confirmDeleteUnlinkedVirtualEmergencyFireController() {
    guard space?.deviceOperates.contains(.delete) ?? false else {
        XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
        return
    }
    SRAlertView(title: "notification".localizedString, message: "Are you sure to delete the EFC device?".localizedString, actions: [
        .cancelAction,
        SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
            self?.deleteUnlinkedVirtualEmergencyFireController()
        })
    ]).show()
}
```

- [ ] **Step 5: Add local-only virtual delete**

In the same extension, add:

```swift
private func deleteUnlinkedVirtualEmergencyFireController() {
    guard let currentDevice else { return }
    DeviceEmerFireStore.shared.deleteCachedDevice(currentDevice)
    if let space {
        space.deviceCount = MeshNetworkManager.instance.realNodes.count
        space.luminairesCount = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }.count
        space.save()
    }
    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
    NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
    XWHUDManager.showSuccessTipHUD("done!".localizedString)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        self?.closeOrBack()
    }
}
```

- [ ] **Step 6: Run contract and verify menu assertions pass except localization**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: menu and delete helper assertions pass; script still fails on missing localization key.

- [ ] **Step 7: Commit virtual menu flow**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift
git commit -m "fix: add virtual EFC device menu"
```

Expected: commit only the routing/menu/delete flow change.

## Task 5: Add Delete Confirmation Localization

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add English string**

In `SunSmart/en.lproj/Localizable.strings`, add near existing EFC action toast strings:

```text
"Are you sure to delete the EFC device?" = "Are you sure to delete the EFC device?";
```

- [ ] **Step 2: Add Chinese string**

In `SunSmart/zh-Hans.lproj/Localizable.strings`, add near existing EFC action toast strings:

```text
"Are you sure to delete the EFC device?" = "确定要删除该 EFC 设备吗？";
```

- [ ] **Step 3: Run contract and verify all assertions pass**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 4: Commit localization**

Run:

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: localize virtual EFC delete"
```

Expected: commit only localization changes.

## Task 6: Final Verification

**Files:**
- Verify all modified files from Tasks 1-5.

- [ ] **Step 1: Inspect final changed files**

Run:

```bash
git status --short
```

Expected: only pre-existing unrelated worktree changes remain, or the tree is clean if those were already committed by the current task sequence.

- [ ] **Step 2: Run contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 4: Build iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke checklist**

Use the app manually if a device dataset is available:

```text
1. Open Site - Space - Main - Others.
2. Long press a virtual EFC item.
3. Verify Edit opens.
4. Return to Others.
5. Short tap the same virtual EFC item.
6. Verify EFC device page opens.
7. Verify top status is Unlinked and uses the same text color as Normal State.
8. Tap Identify, Mock fire alarm, Mock power loss, and Mock restore.
9. Verify each tap shows Not executed. Please link a device first.
10. Open the right menu.
11. Verify only Edit and Delete are shown.
12. Tap Delete.
13. Verify the alert message is Are you sure to delete the EFC device?.
14. Confirm deletion.
15. Verify the page closes and the Others list no longer shows that virtual EFC.
16. Verify a real EFC still uses the cleanup + Reset delete flow.
```

Expected: all checklist items pass.

## Self-Review

- Spec coverage:
  - Short tap virtual EFC enters device page: Task 2.
  - Long press virtual EFC enters Edit: preserved and contract guarded in Task 1.
  - Top `Unlinked` status with Normal State style: existing `renderUnlinkedState()` remains the source; verified in Task 6 manual checklist.
  - Four buttons show link-device toast regardless of groups: Task 3.
  - Right menu only Edit/Delete: Task 4.
  - Delete confirmation message and Battery power switch style: Tasks 4-5.
  - Virtual delete is local-only and does not Reset: Task 4.
  - Real EFC delete remains cleanup + Reset: Task 4 preserves existing real menu branch and Task 6 verifies.
- Placeholder scan:
  - No placeholder terms are intentionally left in implementation steps.
- Type consistency:
  - `guardLinkedDeviceForAction()`, `isUnlinkedVirtualEmergencyFireController`, `showUnlinkedVirtualEmergencyFireControllerMenu()`, `confirmDeleteUnlinkedVirtualEmergencyFireController()`, and `deleteUnlinkedVirtualEmergencyFireController()` are introduced before use.
