# Power Switch Delete Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一 Battery/AC Power Switch 在所有相关删除入口的确认提示，并保持 Kinetic Switch 现状。

**Architecture:** 在 `PJEightKeyPowerSwitchKind` 中新增删除确认文案计算属性，所有 Battery/AC 删除弹窗通过该属性取 message。各入口只调整弹窗触发位置和确认后的原有动作，不修改删除、sync、cache、权限或页面关闭链路。

**Tech Stack:** Swift, UIKit, `SRAlertView`, existing `.localizedString` localization, iPhoneOS `xcodebuild`.

---

### Task 1: 增加 Battery/AC 删除确认文案源

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Run current localization check**

Run:

```sh
rg -n "power_switch_(battery|ac)_delete_message|switchs_delete_message" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Device SunSmart/Main/Group/Switch
```

Expected before implementation: no `power_switch_battery_delete_message` or `power_switch_ac_delete_message` entries exist, and Battery/AC deletion code still references `switchs_delete_message` or `alert_delete_message`.

- [ ] **Step 2: Add computed property to `PJEightKeyPowerSwitchKind`**

In `PJEightKeySwitchData.swift`, add this property after `deviceIconAssetName`:

```swift
    var deleteConfirmationMessage: String {
        switch self {
        case .battery:
            return "power_switch_battery_delete_message".localizedString
        case .ac:
            return "power_switch_ac_delete_message".localizedString
        }
    }
```

- [ ] **Step 3: Add English localization keys**

In `SunSmart/en.lproj/Localizable.strings`, place the new keys next to existing switch delete keys:

```text
"power_switch_battery_delete_message" = "Are you sure to delete the battery power switch?";
"power_switch_ac_delete_message" = "Are you sure to delete the AC power switch?";
```

- [ ] **Step 4: Add Simplified Chinese localization keys**

In `SunSmart/zh-Hans.lproj/Localizable.strings`, place the new keys next to existing switch delete keys:

```text
"power_switch_battery_delete_message" = "确定删除该电池供电开关？";
"power_switch_ac_delete_message" = "确定删除该 AC 供电开关？";
```

- [ ] **Step 5: Verify localization keys resolve in source**

Run:

```sh
rg -n "power_switch_(battery|ac)_delete_message|deleteConfirmationMessage" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: property exists once, and each new key exists once in English and once in Simplified Chinese.

### Task 2: Update Main - Switches delete confirmation

**Files:**
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

- [ ] **Step 1: Confirm current failure path**

Run:

```sh
sed -n '400,422p' SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected before implementation: `isUnlinkedVirtualBatteryPowerSwitch` deletes cache directly, and the shared alert uses `"switchs_delete_message".localizedString`.

- [ ] **Step 2: Replace `requestDeleteSwitch(_:)` with Battery/AC-aware confirmation**

Replace the existing `requestDeleteSwitch(_:)` body with:

```swift
    private func requestDeleteSwitch(_ switchData: DeviceSwitchData) {
        guard canDeleteSwitches else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }

        if let eightKeySwitch = eightKeySwitchData(for: switchData) {
            SRAlertView(
                title: "notification".localizedString,
                message: eightKeySwitch.powerSwitchKind.deleteConfirmationMessage,
                actions: [
                    .cancelAction,
                    SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                        guard let self else { return }
                        if self.isUnlinkedVirtualBatteryPowerSwitch(switchData) {
                            self.deleteCache(switchData: switchData)
                            XWHUDManager.showSuccessTipHUD("done!".localizedString)
                        } else {
                            self.deleteConfirmedSwitch(switchData)
                        }
                    })
                ]
            ).show()
            return
        }

        SRAlertView(title: "notification".localizedString, message: "switchs_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
            self?.deleteConfirmedSwitch(switchData)
        })]).show()
    }
```

- [ ] **Step 3: Verify direct delete path is gone**

Run:

```sh
sed -n '400,430p' SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected: unlinked virtual Battery/AC delete occurs only inside the `CONFIRM` handler.

### Task 3: Update Battery/AC detail and edit delete confirmations

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Confirm current detail and edit failures**

Run:

```sh
rg -n "message: \"switchs_delete_message\"|deleteUnlinkedVirtualSwitch\\(\\)|switchData\\.proxyNode\\?\\.isBatteryPowerSwitch" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected before implementation: monitor page directly deletes unlinked virtual switches, and both files still use `switchs_delete_message` for at least one Battery/AC path.

- [ ] **Step 2: Update `PJEightKeySwitchMonitorVC.deleteCurrentSwitch()`**

Replace `deleteCurrentSwitch()` with:

```swift
    private func deleteCurrentSwitch() {
        guard viewModel.space.deviceOperates.contains(.delete) else {
            showNoPermissionTip()
            return
        }

        SRAlertView(
            title: "notification".localizedString,
            message: viewModel.switchData.powerSwitchKind.deleteConfirmationMessage,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    guard let self else { return }
                    if self.viewModel.isUnlinkedVirtualBatteryPowerSwitch {
                        self.deleteUnlinkedVirtualSwitch()
                    } else {
                        self.deleteSwitchAction?(self.viewModel.switchData, self)
                    }
                })
            ]
        ).show()
    }
```

- [ ] **Step 3: Update `PJPreAddEightKeySwitchesVC.deleteAction()`**

Replace the existing Battery-only proxy-node guard and alert with:

```swift
    private func deleteAction() {
        guard ensureDeletable() else { return }
        guard let switchData = viewModel.sourceSwitchData else { return }
        SRAlertView(
            title: "notification".localizedString,
            message: switchData.powerSwitchKind.deleteConfirmationMessage,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    guard let self else { return }
                    self.deleteSwitchAction?(switchData, self)
                })
            ]
        ).show()
    }
```

- [ ] **Step 4: Verify detail/edit no longer reuse Kinetic message**

Run:

```sh
rg -n "switchs_delete_message|deleteConfirmationMessage|deleteUnlinkedVirtualSwitch\\(\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: `deleteConfirmationMessage` appears in both files; `switchs_delete_message` does not appear in these two files; unlinked virtual deletion remains present only as the confirmed action.

### Task 4: Update Group Power Switch delete confirmation

**Files:**
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: Confirm current group failure**

Run:

```sh
sed -n '372,396p' SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected before implementation: virtual switches call `detachVirtualSwitch(_:)` directly, and real switches use `alert_delete_message`.

- [ ] **Step 2: Replace `deleteSwitch(id:)` with shared Battery/AC confirmation**

Replace the existing `deleteSwitch(id:)` with:

```swift
    private func deleteSwitch(id: String) {
        guard editable else {
            showNoPermissionTip()
            return
        }
        guard let switchData = switchData(id: id) else { return }

        SRAlertView(
            title: "notification".localizedString,
            message: switchData.powerSwitchKind.deleteConfirmationMessage,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self, weak switchData] _ in
                    guard let self, let switchData else { return }
                    if self.viewModel.isRealSwitch(switchData) {
                        self.detachRealSwitch(switchData)
                    } else {
                        self.detachVirtualSwitch(switchData)
                    }
                })
            ]
        ).show()
    }
```

- [ ] **Step 3: Verify virtual group detach is confirm-gated**

Run:

```sh
sed -n '372,404p' SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected: both real and virtual delete actions are inside the alert `CONFIRM` handler.

### Task 5: Final verification and commit

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Verify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Static usage verification**

Run:

```sh
rg -n "switchs_delete_message|alert_delete_message|deleteConfirmationMessage|power_switch_(battery|ac)_delete_message" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- Battery/AC power switch entrypoints use `deleteConfirmationMessage`.
- Kinetic-compatible `switchs_delete_message` remains in `DeviceSwitchesViewController` only for non-8-key switch fallback.
- `alert_delete_message` no longer drives Group Power Switch delete confirmation.
- New localization keys exist in both localization files.

- [ ] **Step 2: Check patch hygiene**

Run:

```sh
git diff --check
```

Expected: no output.

- [ ] **Step 3: Build iPhoneOS**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Inspect changed files**

Run:

```sh
git diff --stat
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: diff is limited to delete confirmation message selection and localization keys.

- [ ] **Step 5: Commit implementation**

Run:

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings docs/superpowers/plans/260611_1652_power_switch_delete_confirmation_implementation.md
git commit -m "fix: update power switch delete confirmations"
```

Expected: one focused commit containing the implementation and this plan.
