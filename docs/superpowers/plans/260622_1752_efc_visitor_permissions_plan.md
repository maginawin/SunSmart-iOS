# EFC Visitor Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Project preference for this repository:** use Inline Execution with `superpowers:executing-plans` unless the user explicitly asks for subagents.

**Goal:** Restrict Visitor behavior on real and virtual EFC device pages exactly as specified, while keeping Identify and unrelated EFC controls unchanged.

**Architecture:** Add one EFC Monitor-specific Visitor predicate, use it only in menu routing and the three Mock button actions, and lock the behavior with the existing EFC contract script. Do not change `SpaceData.deviceOperates`, `canConfigureDevice`, or global Visitor control semantics.

**Tech Stack:** Swift, UIKit, existing `XWHUDManager`, existing `.localizedString`, Bash contract script, Xcode iPhoneOS build.

---

## File Structure

- Modify: `scripts/check_efc_controller_flows.sh`
  - Responsibility: static contract guard for EFC flows and Visitor permission behavior.
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift`
  - Responsibility: expose the EFC Monitor-specific Visitor predicate.
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
  - Responsibility: build real and virtual EFC right-menu options.
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - Responsibility: guard the three Mock button actions before any device/group/business validation.

No localization file changes are expected because `Insufficient permissions` already exists in English and Simplified Chinese.

## Task 1: Add Visitor Permission Contracts

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh:249`

- [ ] **Step 1: Add failing contract assertions**

Insert these assertions after the existing `guardLinkedDeviceForAction()` assertion block and before the `assert_count` block that currently expects 4 linked-device guards:

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift" \
  "var isEffectiveVisitor: Bool" \
  "EFC monitor must expose a page-local Visitor predicate."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift" \
  "space?.permission == .visitor" \
  "EFC monitor Visitor predicate must come from Space permission."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "showRealEmergencyFireControllerVisitorMenu()" \
  "Real EFC Visitor menu must use a dedicated Information-only branch."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "makeInformationMenuItem()" \
  "EFC Information menu item must be shared by normal and Visitor real-device menus."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "guard !viewModel.isEffectiveVisitor else { return }" \
  "Virtual EFC Visitor menu must expose no options."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guardVisitorCanUseMockAction()" \
  "EFC Mock actions must share a Visitor permission guard."

assert_count "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "guard guardVisitorCanUseMockAction()" \
  "3" \
  "Fire Alarm, Power Loss, and Restore Mock actions must all check Visitor permission first."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift" \
  "\"Insufficient permissions\".localizedString" \
  "Visitor Mock action denial must show the requested localized Toast."

assert_contains "SunSmart/en.lproj/Localizable.strings" \
  "\"Insufficient permissions\" = \"Insufficient permissions\";" \
  "English localization must include Insufficient permissions."

assert_contains "SunSmart/zh-Hans.lproj/Localizable.strings" \
  "\"Insufficient permissions\" = \"权限不足\";" \
  "Simplified Chinese localization must include Insufficient permissions."
```

- [ ] **Step 2: Run contract script and verify failure**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL with the first new assertion, likely:

```text
FAIL: EFC monitor must expose a page-local Visitor predicate.
```

- [ ] **Step 3: Commit contract**

Run:

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: add EFC visitor permission contract"
```

Expected: commit includes only `scripts/check_efc_controller_flows.sh`.

## Task 2: Add Visitor Predicate and Menu Routing

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift:27`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift:20`

- [ ] **Step 1: Add EFC Monitor Visitor predicate**

In `EmerFireAlarmMonitorViewModel`, add this property immediately after `canOperateEmergencyActions`:

```swift
    var isEffectiveVisitor: Bool {
        space?.permission == .visitor
    }
```

The surrounding section should become:

```swift
    var canConfigureDevice: Bool {
        space?.deviceOperates.contains(.edit) ?? false
    }

    var canOperateEmergencyActions: Bool {
        canConfigureDevice
    }

    var isEffectiveVisitor: Bool {
        space?.permission == .visitor
    }

    var isAllEmergencyFunctionsDisabled: Bool {
        false
    }
```

- [ ] **Step 2: Refactor Information menu item into a shared helper**

In `EmerFireAlarmMonitorRouting.swift`, add these helpers inside `extension EmerFireAlarmMonitorVC`, after `showUnlinkedVirtualEmergencyFireControllerMenu()` and before `informationGroupText()`:

```swift
    private func makeInformationMenuItem() -> MenuPopView.MenuItem {
        .init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
            guard let self else { return }
            guard let node = self.currentDevice?.bindNode else {
                XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                return
            }
            let controller = DeviceInformationViewController(
                node: node,
                emptyGroupText: "efc_not_yet_linked_group".localizedString,
                showsSceneSection: false,
                groupTextOverride: self.informationGroupText()
            )
            self.navigationController?.pushViewController(controller, animated: true)
        })
    }

    private func showEmergencyFireControllerMenu(items: [MenuPopView.MenuItem]) {
        guard !items.isEmpty else { return }
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
    }

    private func showRealEmergencyFireControllerVisitorMenu() {
        showEmergencyFireControllerMenu(items: [makeInformationMenuItem()])
    }
```

- [ ] **Step 3: Update real EFC menu to use Visitor branch**

Replace `moreClick()` with:

```swift
    @objc func moreClick() {
        if isUnlinkedVirtualEmergencyFireController {
            showUnlinkedVirtualEmergencyFireControllerMenu()
            return
        }

        if viewModel.isEffectiveVisitor {
            showRealEmergencyFireControllerVisitorMenu()
            return
        }

        let config = currentConfig ?? currentDevice.map(viewModel.makeConfig(from:))
        var items: [MenuPopView.MenuItem] = []
        if canConfigureDevice {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
                self?.openEditSettings(config: config)
            }))
        }
        if space?.deviceOperates.contains(.delete) ?? false {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                self?.deleteDevice()
            }))
        }

        items.append(makeInformationMenuItem())

        if !isAllEmergencyFunctionsDisabled, canConfigureDevice {
            items.append(.init(icon: UIImage(named: "menu_refresh"), title: "refresh".localizedString, tapItemBack: { [weak self] _ in
                self?.refresh()
            }))
        }

        showEmergencyFireControllerMenu(items: items)
    }
```

- [ ] **Step 4: Update virtual EFC menu to expose no Visitor options**

Replace the beginning and ending of `showUnlinkedVirtualEmergencyFireControllerMenu()` so the full method is:

```swift
    private func showUnlinkedVirtualEmergencyFireControllerMenu() {
        guard !viewModel.isEffectiveVisitor else { return }

        let config = currentConfig ?? currentDevice.map(viewModel.makeConfig(from:))
        var items: [MenuPopView.MenuItem] = []
        if canConfigureDevice {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
                self?.openEditSettings(config: config)
            }))
        }
        if space?.deviceOperates.contains(.delete) ?? false {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                guard let self, let currentDevice = self.currentDevice else { return }
                self.confirmDeleteEmergencyFireControllerDeviceOrVirtual(
                    currentDevice,
                    space: space,
                    presentsSyncModally: false
                ) { [weak self] in
                    self?.finishDeleteDevice()
                }
            }))
        }

        showEmergencyFireControllerMenu(items: items)
    }
```

- [ ] **Step 5: Run contract script and verify remaining Mock guard failure**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL on the Mock guard assertion:

```text
FAIL: EFC Mock actions must share a Visitor permission guard.
```

- [ ] **Step 6: Commit menu routing**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift
git commit -m "fix: restrict EFC visitor menus"
```

Expected: commit includes only the ViewModel and Routing files.

## Task 3: Guard the Three Mock Buttons

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift:403`

- [ ] **Step 1: Add shared Mock action Visitor guard**

Add this helper immediately before `mockFireAlarmAction()`:

```swift
    private func guardVisitorCanUseMockAction() -> Bool {
        guard !viewModel.isEffectiveVisitor else {
            XWHUDManager.showTipHUD("Insufficient permissions".localizedString, isLineFeed: true)
            return false
        }
        return true
    }
```

- [ ] **Step 2: Put the guard first in Fire Alarm Mock action**

Change `mockFireAlarmAction()` to start with:

```swift
    @discardableResult
    func mockFireAlarmAction() -> Bool {
        guard guardVisitorCanUseMockAction() else {
            return false
        }
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

- [ ] **Step 3: Put the guard first in Power Loss Mock action**

Change `mockPowerLossAction()` to start with:

```swift
    @discardableResult
    func mockPowerLossAction() -> Bool {
        guard guardVisitorCanUseMockAction() else {
            return false
        }
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

- [ ] **Step 4: Put the guard first in Restore Mock action**

Change `mockRestoreAction()` to start with:

```swift
    @discardableResult
    func mockRestoreAction() -> Bool {
        guard guardVisitorCanUseMockAction() else {
            return false
        }
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

- [ ] **Step 5: Run EFC contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 6: Run EFC i18n hardcoded-string script**

Run:

```bash
bash scripts/check_efc_i18n.sh
```

Expected:

```text
PASS: no targeted EFC hardcoded strings found.
```

- [ ] **Step 7: Commit Mock guard**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
git commit -m "fix: block EFC mock actions for visitors"
```

Expected: commit includes only `EmerFireAlarmMonitorVC.swift`.

## Task 4: Final Verification

**Files:**
- Verify: `scripts/check_efc_controller_flows.sh`
- Verify: `scripts/check_efc_i18n.sh`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`

- [ ] **Step 1: Check worktree scope**

Run:

```bash
git status --short
```

Expected: clean worktree after Task 3 commits.

- [ ] **Step 2: Run EFC contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 3: Run EFC i18n script**

Run:

```bash
bash scripts/check_efc_i18n.sh
```

Expected:

```text
PASS: no targeted EFC hardcoded strings found.
```

- [ ] **Step 4: Run whitespace diff check**

Run:

```bash
git diff --check HEAD
```

Expected: no output.

- [ ] **Step 5: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 6: Review final diff against spec**

Run:

```bash
git show --stat --oneline HEAD~2..HEAD
```

Expected: the final two implementation commits only include:

```text
scripts/check_efc_controller_flows.sh
SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorViewModel.swift
SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift
SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
```

If Task 1 produced a separate test commit, include `HEAD~3..HEAD` instead and verify the same file list.

## Self-Review

- Spec coverage: covered real EFC Visitor menu Information-only behavior, virtual EFC Visitor no-menu behavior, Visitor denial for the three Mock buttons, Identify unchanged, no global permission change, no localization additions, and contract/build verification.
- Placeholder scan: no placeholder terms or vague implementation steps remain.
- Type consistency: `isEffectiveVisitor`, `guardVisitorCanUseMockAction()`, `makeInformationMenuItem()`, `showEmergencyFireControllerMenu(items:)`, and `showRealEmergencyFireControllerVisitorMenu()` are defined before use and referenced consistently.
