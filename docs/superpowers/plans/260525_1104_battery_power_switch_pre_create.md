# Battery Power Switch Pre-Create Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable local pre-creation of an unbound Battery Power Switch from the Space add-device flow.

**Architecture:** Reuse the existing `PJPreAddEightKeySwitchesVC` editor and `PJEightKeySwitchData` persistence path. Add an explicit create kind so Battery Power Switch pre-create can save as unbound local BPS metadata with `syncState = .synced`, while leaving real-device binding, virtual group creation, and sync for a later flow.

**Tech Stack:** Swift, UIKit, SnapKit, SQLite-backed project repositories, NordicSigMeshSDK types, existing SunSmart notification and HUD helpers.

---

## Scope Check

The spec is one subsystem: local Battery Power Switch pre-create from the existing Space add-device flow. It does not include real BPS scanning, binding, virtual group allocation, or protocol sync changes.

## File Structure

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`
  - Owns editor state and creates `PJEightKeySwitchData`.
  - Add `CreationKind` and Battery Power Switch pre-create defaults.
- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - Owns validation, save flow, close flow, and existing link/edit actions.
  - Add create-kind initializer and make persistence report success/failure.
- Modify `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - Owns the Space add-device menu callbacks.
  - Replace the Battery Power Switch `under_development` branch with the editor presentation.
- No new localization keys, assets, target config, dependencies, or Auth data.

## Task 1: Add Battery Power Switch Create Kind To ViewModel

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`

- [ ] **Step 1: Inspect current ViewModel defaults**

Run:

```bash
sed -n '1,130p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
```

Expected:

- `deviceName` uses `MeshNetworkManager.instance.getNextSwitchName()`.
- `isEnabled` defaults to `true`.
- `selectedPanelType` defaults to `.scene8Key`.
- `moreSettings` defaults to `.default`.
- `buildSwitchData()` creates `PJEightKeySwitchData`.

- [ ] **Step 2: Add `CreationKind` and store it**

In `PJPreAddEightKeySwitchesViewModel`, add the enum and property immediately after the struct opening:

```swift
struct PJPreAddEightKeySwitchesViewModel {

    enum CreationKind {
        case kineticSwitch
        case batteryPowerSwitch
    }

    let space: SpaceData
    let sourceSwitchData: PJEightKeySwitchData?
    let creationKind: CreationKind
```

Then change the create initializer from:

```swift
init(space: SpaceData) {
    self.space = space
    self.sourceSwitchData = nil
    self.deviceName = MeshNetworkManager.instance.getNextSwitchName()
}
```

to:

```swift
init(space: SpaceData, creationKind: CreationKind = .kineticSwitch) {
    self.space = space
    self.sourceSwitchData = nil
    self.creationKind = creationKind
    self.deviceName = MeshNetworkManager.instance.getNextSwitchName()
}
```

In the edit initializer, set the stored create kind explicitly:

```swift
init(space: SpaceData, switchData: PJEightKeySwitchData) {
    self.space = space
    self.sourceSwitchData = switchData
    self.creationKind = .batteryPowerSwitch
    self.deviceName = switchData.name
    self.isEnabled = switchData.enabled
    self.selectedPanelType = switchData.eightKeyPanelType
    self.selectedGroups = switchData.bindGroups
    self.moreSettings = switchData.moreSettingsState
    self.sceneDatas = [
        .init(type: .sceneA, scene: switchData.sceneA),
        .init(type: .sceneB, scene: switchData.sceneB),
        .init(type: .sceneC, scene: switchData.sceneC),
        .init(type: .sceneD, scene: switchData.sceneD)
    ]
}
```

- [ ] **Step 3: Add a ViewModel flag for BPS pre-create**

Add this computed property near `showsSceneRow`:

```swift
var isBatteryPowerSwitchPreCreate: Bool {
    sourceSwitchData == nil && creationKind == .batteryPowerSwitch
}
```

- [ ] **Step 4: Set local unbound BPS sync metadata in `buildSwitchData()`**

At the end of `buildSwitchData()`, after:

```swift
switchData.eightKeyPanelType = selectedPanelType
switchData.moreSettingsState = moreSettings
```

add:

```swift
if isBatteryPowerSwitchPreCreate {
    switchData.syncState = .synced
    switchData.desiredConfigVersion = 0
    switchData.desiredConfigHash = ""
    switchData.appliedConfigHash = ""
    switchData.lastSyncFailedReason = nil
    switchData.lastSyncedAt = nil
    switchData.appliedTxEnabled = nil
    switchData.appliedLEDIndicatorEnabled = nil
}
```

The complete tail of `buildSwitchData()` should be:

```swift
switchData.maxKeyCount = 8
switchData.panelType = selectedPanelType == .scene8Key ? .scenes_4key : .default_4key
switchData.eightKeyPanelType = selectedPanelType
switchData.moreSettingsState = moreSettings
if isBatteryPowerSwitchPreCreate {
    switchData.syncState = .synced
    switchData.desiredConfigVersion = 0
    switchData.desiredConfigHash = ""
    switchData.appliedConfigHash = ""
    switchData.lastSyncFailedReason = nil
    switchData.lastSyncedAt = nil
    switchData.appliedTxEnabled = nil
    switchData.appliedLEDIndicatorEnabled = nil
}
return switchData
```

- [ ] **Step 5: Verify ViewModel references**

Run:

```bash
rg -n "CreationKind|isBatteryPowerSwitchPreCreate|syncState = \\.synced|appliedTxEnabled = nil|appliedLEDIndicatorEnabled = nil" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
```

Expected:

- `CreationKind` enum exists.
- `creationKind` property exists.
- `isBatteryPowerSwitchPreCreate` exists.
- `syncState = .synced`, `appliedTxEnabled = nil`, and `appliedLEDIndicatorEnabled = nil` appear in `buildSwitchData()`.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
git commit -m "feat: add battery power switch pre-create model mode"
```

Expected: one commit containing only the ViewModel change.

## Task 2: Make The Editor Persist Local BPS Creates Safely

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Add create-kind initializer support**

Change the create initializer from:

```swift
init(space: SpaceData) {
    self.viewModel = PJPreAddEightKeySwitchesViewModel(space: space)
    super.init(nibName: nil, bundle: nil)
}
```

to:

```swift
init(space: SpaceData, creationKind: PJPreAddEightKeySwitchesViewModel.CreationKind = .kineticSwitch) {
    self.viewModel = PJPreAddEightKeySwitchesViewModel(space: space, creationKind: creationKind)
    super.init(nibName: nil, bundle: nil)
}
```

Keep the edit initializer unchanged.

- [ ] **Step 2: Add a local save failure HUD helper**

Add this method near `postSwitchDataChangedNotifications()`:

```swift
private func showSaveFailedTip() {
    XWHUDManager.showErrorTipHUD("failed".localizedString)
}
```

- [ ] **Step 3: Make `persistSwitchData(_:)` return success**

Replace the current method:

```swift
private func persistSwitchData(_ switchData: PJEightKeySwitchData) {
    if let sourceSwitchData = viewModel.sourceSwitchData,
       let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == sourceSwitchData.id }) {
        MeshNetworkManager.instance.switchs[index] = switchData
    } else {
        MeshNetworkManager.instance.switchs.append(switchData)
    }
    switchData.save()
    PJEightKeySwitchRepository.shared.save(switchData)
}
```

with:

```swift
@discardableResult
private func persistSwitchData(_ switchData: PJEightKeySwitchData) -> Bool {
    guard switchData.save(),
          PJEightKeySwitchRepository.shared.save(switchData) else {
        return false
    }

    if let sourceSwitchData = viewModel.sourceSwitchData,
       let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == sourceSwitchData.id }) {
        MeshNetworkManager.instance.switchs[index] = switchData
    } else if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
        MeshNetworkManager.instance.switchs[index] = switchData
    } else {
        MeshNetworkManager.instance.switchs.append(switchData)
    }
    return true
}
```

This keeps memory updates behind successful database writes and prevents duplicate in-memory entries for the same id.

- [ ] **Step 4: Guard the create/edit submit save path**

In `submitAction()`, replace:

```swift
persistSwitchData(switchData)
switchSavedAction?(switchData)
```

with:

```swift
guard persistSwitchData(switchData) else {
    showSaveFailedTip()
    return
}
switchSavedAction?(switchData)
```

Expected behavior:

- Local BPS pre-create does not call `submitBatteryPowerSwitch(_:)` because `proxyNodeAddress == nil`.
- It persists locally, posts notifications, shows success, and closes.
- If either local save fails, it shows the existing localized `failed` HUD and stays open.

- [ ] **Step 5: Guard Battery Power Switch sync callback saves**

In `pushBatteryPowerSwitchSync(_:)`, update both callback save points.

In `syncSuccessCallback`, replace:

```swift
self.persistSwitchData(switchData)
self.switchSavedAction?(switchData)
```

with:

```swift
guard self.persistSwitchData(switchData) else {
    self.showSaveFailedTip()
    return
}
self.switchSavedAction?(switchData)
```

In `backActionCallback`, replace:

```swift
self.persistSwitchData(switchData)
self.switchSavedAction?(switchData)
```

with:

```swift
guard self.persistSwitchData(switchData) else {
    self.showSaveFailedTip()
    return
}
self.switchSavedAction?(switchData)
```

This keeps the changed persistence contract consistent for existing BPS edit/sync code paths.

- [ ] **Step 6: Verify the controller save contract**

Run:

```bash
rg -n "init\\(space: SpaceData, creationKind|showSaveFailedTip|@discardableResult|persistSwitchData\\(switchData\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- The create initializer accepts `creationKind`.
- `showSaveFailedTip()` exists.
- `persistSwitchData(_:)` is annotated with `@discardableResult` and returns `Bool`.
- Every active call to `persistSwitchData(switchData)` is either guarded or intentionally uses the return value.

- [ ] **Step 7: Compile-check the changed Swift files**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- No error about `PJPreAddEightKeySwitchesViewModel.CreationKind`.
- No error about ignoring or mismatching `persistSwitchData` return type.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "feat: persist battery power switch pre-create locally"
```

Expected: one commit containing only the controller persistence and initializer changes.

## Task 3: Wire The Space Add-Device Entry

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`

- [ ] **Step 1: Replace the Battery Power Switch under-development branch**

In `addAction(point:)`, replace the current `onBatterySwitch` block:

```swift
onBatterySwitch: { [weak self] in
    guard let self = self else { return }
//                        let vc = PJPreAddEightKeySwitchesVC(space: self.space)
//                        if isIPad {
//                            vc.preferredContentSize = iPadPreferredContentSize
//                        }
//                        self.present(NavigationViewController(rootViewController: vc), animated: true)
    XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
}
```

with:

```swift
onBatterySwitch: { [weak self] in
    guard let self = self else { return }
    let vc = PJPreAddEightKeySwitchesVC(space: self.space, creationKind: .batteryPowerSwitch)
    if isIPad {
        vc.preferredContentSize = iPadPreferredContentSize
    }
    self.present(NavigationViewController(rootViewController: vc), animated: true)
}
```

- [ ] **Step 2: Verify the entry has no stale commented code**

Run:

```bash
sed -n '339,356p' SunSmart/Main/Device/Controller/DevicesViewController.swift
```

Expected:

- `onKineticSwitch` still calls `self?.switchAdd()`.
- `onBatterySwitch` creates `PJPreAddEightKeySwitchesVC(space: self.space, creationKind: .batteryPowerSwitch)`.
- The old commented `PJPreAddEightKeySwitchesVC(space:)` block is gone.
- The old `under_development` HUD is gone from this branch.

- [ ] **Step 3: Verify the Battery Power Switch entry compiles**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- No error about `.batteryPowerSwitch` type inference in `DevicesViewController`.

- [ ] **Step 4: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Device/Controller/DevicesViewController.swift
git commit -m "feat: open battery power switch pre-create flow"
```

Expected: one commit containing only the entry wiring.

## Task 4: Final Verification

**Files:**
- Verify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Static-check no pre-create virtual group allocation**

Run:

```bash
rg -n "ensureBatteryPowerSwitchLinkGroup" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
```

Expected:

- The only match is inside `submitBatteryPowerSwitch(_:)`.
- There is no match in `buildSwitchData()`.
- There is no match in the unlinked local submit path.

- [ ] **Step 2: Static-check no pre-create sync navigation**

Run:

```bash
rg -n "SyncDevicesViewController|submitBatteryPowerSwitch|isBatteryPowerSwitchLinked" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- `SyncDevicesViewController` remains only in existing BPS sync methods.
- `submitAction()` still gates the sync path behind `isBatteryPowerSwitchLinked(switchData)`.
- Unbound pre-created BPS has `proxyNodeAddress == nil`, so it follows the local persistence path.

- [ ] **Step 3: Static-check BPS defaults**

Run:

```bash
rg -n "isEnabled = true|selectedPanelType.*scene8Key|moreSettings.*\\.default|getNextSwitchName|syncState = \\.synced|proxyNodeAddress: nil|linkGroupAddress: nil" SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift
```

Expected:

- Default name uses `getNextSwitchName()`.
- Default enabled state is true.
- Default selected panel type is `.scene8Key`.
- Default more settings use `.default`, where LED Indicator is enabled.
- `buildSwitchData()` creates unbound data with nil proxy and group addresses.
- BPS pre-create sets `syncState = .synced`.

- [ ] **Step 4: Static-check list recognition is still supported**

Run:

```bash
rg -n "makeEightKeySwitch\\(from:|PJEightKeySwitchesViewCell|eightKeySwitchData\\(for:" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift
```

Expected:

- `DeviceSwitchesViewController.eightKeySwitchData(for:)` still calls `PJEightKeySwitchRepository.shared.makeEightKeySwitch(from:)`.
- The collection view still uses `PJEightKeySwitchesViewCell` when metadata exists.

- [ ] **Step 5: Run final iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

- [ ] **Step 6: Manual QA on simulator or device**

Use a normal app run after the build succeeds.

Expected manual behavior:

- Space add-device menu opens normally.
- Selecting `Switches` opens `PJSwitchesTypesVC`.
- Selecting `Battery Power Switch` opens the Switch editor.
- Defaults are Name from next switch name, Enable On, Panel `Scene Panel (8 key)`, Group `N/A`, Scene `N/A`, LED Indicator Enabled in More Settings.
- Panel, Group, Scene, and More Settings remain selectable.
- Tapping `CREATE` adds one switch to the Switches list.
- New list item renders as the 8-key / Battery Power Switch cell.
- Entering edit for the new item shows LINK.
- Deleting the unbound item removes it locally without opening sync.

- [ ] **Step 7: Confirm git state**

Run:

```bash
git status --short
```

Expected:

- No uncommitted changes after the task commits, or only intentionally uncommitted runtime artifacts that are not added.

## Self-Review

Spec coverage:

- Entry flow is covered by Task 3.
- Defaults are covered by Task 1 and final static checks.
- Local-only creation without real node, virtual group, or sync is covered by Task 1, Task 2, and Task 4.
- Existing preview reuse is preserved by not changing `PJEightKeySwitchPanelView` or `PJEightKeySwitchEditorView`.
- Save failure handling is covered by Task 2.
- List recognition and delete/edit follow existing paths and are checked in Task 4.

Placeholder scan:

- The plan contains no unresolved placeholders.
- Each code edit step includes concrete code.
- Each validation step includes a command and expected result.

Type consistency:

- `CreationKind` is defined on `PJPreAddEightKeySwitchesViewModel` before `PJPreAddEightKeySwitchesVC` references it.
- `.batteryPowerSwitch` is passed from `DevicesViewController` through the new editor initializer.
- `persistSwitchData(_:)` returns `Bool`, and active call sites guard the return value.
