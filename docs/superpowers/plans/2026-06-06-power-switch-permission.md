# Power Switch Permission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict visitor and temporarily downgraded owner/editor users on battery/ac power switch device pages and group power switch lists.

**Architecture:** Reuse the existing `SpaceData.deviceOperates` and `SpaceData.groupOperates` permissions, which already include `disableEditorPermission`. Add local read-only guards in the two affected controllers so blocked actions show `No permission!` and do not mutate data or send Mesh messages.

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, existing `XWHUDManager` toast patterns, existing xcodebuild validation.

---

## File Structure

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`: add effective edit/read-only properties and make battery refresh depend on effective edit permission.
- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`: route menu, enable/disable, refresh, identify, edit and delete actions through effective permission.
- Modify `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`: keep disabled-looking controls tappable enough to report permission denial via controller callbacks.
- Modify `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`: centralize `No permission!` toast and block group-list editing actions when `editable == false`.
- Verification only: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`.

## Task 1: Device Detail Effective Visitor Permission

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Add effective permission properties to the monitor view model**

In `PJEightKeySwitchMonitorViewModel`, add these computed properties near `needsBatteryPowerSwitchSync`:

```swift
    var canEditPowerSwitch: Bool {
        space.deviceOperates.contains(.edit)
    }

    var isEffectiveVisitor: Bool {
        !canEditPowerSwitch
    }
```

Then replace `canRefreshBattery` with:

```swift
    var canRefreshBattery: Bool {
        switchData.powerSwitchKind == .battery &&
            switchData.proxyNode?.isBatteryPowerSwitch == true &&
            canEditPowerSwitch
    }
```

- [ ] **Step 2: Add a shared no-permission toast helper in the monitor controller**

In `PJEightKeySwitchMonitorVC`, add this helper near `moreAction()`:

```swift
    private func showNoPermissionTip() {
        XWHUDManager.showTipHUD("No permission!", isLineFeed: true)
    }
```

- [ ] **Step 3: Restrict the right menu for effective visitor users**

Replace `moreAction()` in `PJEightKeySwitchMonitorVC` with:

```swift
    @objc private func moreAction() {
        var items: [MenuPopView.MenuItem] = []

        if viewModel.isEffectiveVisitor {
            guard viewModel.isRealBatteryPowerSwitch else {
                return
            }
            items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
                self?.pushInformation()
            }))
        } else {
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
                items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: { [weak self] _ in
                    self?.identifyAction()
                }))
            }
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

- [ ] **Step 4: Block bottom enable/disable for effective visitor users**

At the top of `startTxEnableUpdate(_:)` in `PJEightKeySwitchMonitorVC`, insert:

```swift
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            updateUI()
            return
        }
```

The full method should begin:

```swift
    private func startTxEnableUpdate(_ isEnabled: Bool) {
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            updateUI()
            return
        }
        guard pendingEnabledValue == nil else {
            updateUI()
            return
        }
```

- [ ] **Step 5: Block refresh and identify defensively**

At the top of `refreshMonitor()` after the `isRefreshing` guard, insert:

```swift
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            updateUI()
            return
        }
```

At the top of `identifyAction()`, insert:

```swift
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            return
        }
```

- [ ] **Step 6: Block edit and delete defensively**

At the top of `pushEditor()`, insert:

```swift
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            return
        }
```

At the top of `deleteCurrentSwitch()`, insert:

```swift
        guard viewModel.space.deviceOperates.contains(.delete) else {
            showNoPermissionTip()
            return
        }
```

- [ ] **Step 7: Build-check the device detail changes**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds, or any failure is unrelated to the modified files and is recorded before continuing.

- [ ] **Step 8: Commit Task 1**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "fix: restrict power switch monitor permissions"
```

## Task 2: Group Power Switch List Read-Only Toasts

**Files:**
- Modify: `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: Make disabled header enable taps report back to the controller**

In `GroupPowerSwitchHeaderView.configure(state:)`, replace:

```swift
        enableButton.isEnabled = state.isEditable && !state.isEnablePending
```

with:

```swift
        enableButton.isEnabled = !state.isEnablePending
```

This keeps pending TX updates blocked but allows read-only taps to call `enableAction`, where the controller shows `No permission!`.

- [ ] **Step 2: Make disabled panel buttons report back to the controller**

In `GroupPowerSwitchPanelCell.configure(definition:isEditable:isSaveEnabled:)`, replace the button enabled assignments with:

```swift
        deleteButton.isEnabled = true
        deleteButton.alpha = isEditable ? 1 : 0.35
        saveButton.isEnabled = isEditable ? isSaveEnabled : true
        saveButton.alpha = isEditable ? 1 : 0.35
        saveButton.setImage(UIImage(named: isSaveEnabled ? "switch_save" : "switch_save_un"), for: .normal)
```

This preserves the disabled visual state for read-only users but lets taps reach the controller permission guard.

- [ ] **Step 3: Add a shared no-permission helper to the group controller**

In `GroupPowerSwitchesViewController`, add this helper near `addSwitchButtonAction()`:

```swift
    private func showNoPermissionTip() {
        XWHUDManager.showTipHUD("No permission!", isLineFeed: true)
    }
```

- [ ] **Step 4: Use the fixed toast text for all group-list permission guards**

Replace each `XWHUDManager.showTipHUD("no_permission".localizedString + "！")` inside `GroupPowerSwitchesViewController` permission guards with:

```swift
            showNoPermissionTip()
```

The affected methods are:

```swift
    @objc private func addSwitchButtonAction()
    private func startEnableUpdate(id: String, enabled: Bool)
    private func selectPanel(id: String)
    private func selectScenes(id: String)
    private func moreSettings(id: String)
    private func deleteSwitch(id: String)
    private func saveSwitch(id: String)
```

- [ ] **Step 5: Block Group row editing in read-only mode**

Replace `showGroups(id:)` in `GroupPowerSwitchesViewController` with:

```swift
    private func showGroups(id: String) {
        guard editable else {
            showNoPermissionTip()
            return
        }
        guard let switchData = switchData(id: id) else { return }
        let vc = SwitchSelectGroupsViewController(groups: switchData.bindGroups, selectGroups: switchData.bindGroups)
        vc.editable = false
        navigationController?.pushViewController(vc, animated: true)
    }
```

- [ ] **Step 6: Ensure Scene row is also read-only guarded**

Confirm `selectScenes(id:)` still starts with:

```swift
        guard editable else {
            showNoPermissionTip()
            return
        }
```

This keeps scene editing aligned with Panel, Group, and More Settings.

- [ ] **Step 7: Build-check the group list changes**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds, or any failure is unrelated to the modified files and is recorded before continuing.

- [ ] **Step 8: Commit Task 2**

```bash
git add SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
git commit -m "fix: restrict group power switch permissions"
```

## Task 3: Final Verification

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Verify: `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`
- Verify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: Search for old group-list permission text**

Run:

```bash
rg -n "\"no_permission\"\\.localizedString \\+ \"！\"|No permission!" SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: `No permission!` appears in the new helpers, and the old localized-plus-fullwidth-exclamation permission guard no longer appears in the two modified controllers.

- [ ] **Step 2: Final iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git diff --stat HEAD
git status --short
```

Expected: only intended files remain changed for this task. Pre-existing unrelated modified files may still appear and must not be reverted.

- [ ] **Step 4: Commit final plan document if not already committed**

If `docs/superpowers/plans/2026-06-06-power-switch-permission.md` is still uncommitted, run:

```bash
git add docs/superpowers/plans/2026-06-06-power-switch-permission.md
git commit -m "docs: add power switch permission plan"
```
