# Battery Power Switch LED Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide Battery Power Switch Periodic Reporting and route LED Indicator changes through SAVE-after-activation, persisting only after `Vendor SET 0x4C 0x02 <enable>` succeeds.

**Architecture:** Keep `More Settings` as an edit-only surface and add an independent applied LED state beside the existing TX Enable applied state. Battery Power Switch own configuration becomes an ordered SyncDevices step: Key Config, TX Enable, LED Indicator, then target group operations. SDK status parsing accepts the 3-byte LED SET ACK while preserving 4-byte GET parsing.

**Tech Stack:** Swift, UIKit, SnapKit, SQLite.swift, NordicSigMeshSDK Swift Package, XCTest, xcodebuild.

---

## File Structure

- Modify `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  Accept `RET 0x4C 0x02 0x00` as a successful LED SET ACK without parsed parameters.

- Modify `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`
  Add LED SET encoding, LED GET encoding, 3-byte SET ACK parsing, and 4-byte GET parsing coverage.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
  Add `appliedLEDIndicatorEnabled` metadata persistence and SQLite migration.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  Add LED sync state, success marker, and include LED in Battery Power Switch sync decisions.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  Mark newly added Battery Power Switch devices as LED-applied enabled without sending a default LED command.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMoreSettingsController.swift`
  Hide Periodic Reporting while keeping LED Indicator visible.

- Modify `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  Add `batteryPowerSwitchLEDIndicator(switchData:)` action and message handle generation.

- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  Insert LED Indicator after TX Enable in Battery Power Switch own configuration.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  Include LED in SAVE activation decisions, own configuration classification, and rollback snapshots.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  Include LED own configuration in sync result classification used by Monitor-page resync.

---

### Task 1: Fix SDK LED SET ACK Parsing

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: Add failing SDK tests**

In `testBatteryPowerSwitchSetEncoding()`, append:

```swift
XCTAssertEqual(
    SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(false)).parameters,
    Data([0x4C, 0x02, 0x00])
)
XCTAssertEqual(
    SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(true)).parameters,
    Data([0x4C, 0x02, 0x01])
)
```

In `testBatteryPowerSwitchGetEncoding()`, append:

```swift
XCTAssertEqual(
    SunricherVendorGet(function: .batteryPowerSwitchLEDEnabled).parameters,
    Data([0x4C, 0x02])
)
```

In `testBatteryPowerSwitchStatusParsing()`, append:

```swift
let ledSetAck = SunricherVendorStatus(parameters: Data([0x4C, 0x02, 0x00]))
XCTAssertEqual(ledSetAck?.status.isSuccessful, true)
XCTAssertEqual(ledSetAck?.status.code, .batteryPowerSwitchLEDEnabled)
XCTAssertNil(ledSetAck?.status.parameters)

let ledGetDisabled = SunricherVendorStatus(parameters: Data([0x4C, 0x02, 0x00, 0x00]))
XCTAssertEqual(ledGetDisabled?.status.isSuccessful, true)
XCTAssertEqual(ledGetDisabled?.status.code, .batteryPowerSwitchLEDEnabled)
if case .batteryPowerSwitchLEDEnabled(let enabled) = ledGetDisabled?.status.parameters {
    XCTAssertEqual(enabled, false)
} else {
    XCTFail("Expected battery power switch LED disabled")
}

let ledGetEnabled = SunricherVendorStatus(parameters: Data([0x4C, 0x02, 0x00, 0x01]))
XCTAssertEqual(ledGetEnabled?.status.isSuccessful, true)
XCTAssertEqual(ledGetEnabled?.status.code, .batteryPowerSwitchLEDEnabled)
if case .batteryPowerSwitchLEDEnabled(let enabled) = ledGetEnabled?.status.parameters {
    XCTAssertEqual(enabled, true)
} else {
    XCTFail("Expected battery power switch LED enabled")
}
```

- [ ] **Step 2: Run SDK test to expose current behavior**

Run from `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected in a SwiftPM-capable environment: the new `ledSetAck` assertion fails because 3-byte LED ACK is currently treated as invalid. In the current local repo, SwiftPM may fail earlier with `no such module 'UIKit'`; record that exact output and continue because the iPhoneOS app build is the authoritative SDK compile check here.

- [ ] **Step 3: Accept 3-byte SET ACK for LED status**

In `SunricherVendorStatus.swift`, replace the `.batteryPowerSwitchLEDEnabled` parse block with this final branch:

```swift
case .batteryPowerSwitchLEDEnabled:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 4 else {
        self.parameters = nil
        break
    }
    let enabled: UInt8 = data.read(fromOffset: 3)
    self.parameters = .batteryPowerSwitchLEDEnabled(enabled > 0)
```

This branch intentionally matches TX Enable behavior: `data.count == 3` is a successful SET ACK with no parsed parameters, and `data.count >= 4` is a GET response with the enabled value.

- [ ] **Step 4: Re-run SDK test command**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected in a SwiftPM-capable environment: `BatteryPowerSwitchVendorMessageTests` passes. If the local command fails with `no such module 'UIKit'`, keep that as a known environment limitation and verify through the final iPhoneOS build.

- [ ] **Step 5: Commit SDK ACK fix**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: accept battery switch led set ack"
```

---

### Task 2: Add App LED Applied State

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Add repository metadata and SQLite column**

In `PJEightKeySwitchRepository.Metadata`, add:

```swift
let appliedLEDIndicatorEnabled: Bool?
```

Add this initializer parameter with the other optional applied fields:

```swift
appliedLEDIndicatorEnabled: Bool? = nil
```

Assign it:

```swift
self.appliedLEDIndicatorEnabled = appliedLEDIndicatorEnabled
```

In `ExpressionKey`, add:

```swift
static let appliedLEDIndicatorEnabled = Expression<Bool?>("appliedLEDIndicatorEnabled")
```

In `table.create`, add:

```swift
builder.column(ExpressionKey.appliedLEDIndicatorEnabled)
```

In migration after `appliedTxEnabled`, add:

```swift
if !columns.contains(where: { $0.name == "appliedLEDIndicatorEnabled" }) {
    _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.appliedLEDIndicatorEnabled))
}
```

In `save(_:)`, add:

```swift
ExpressionKey.appliedLEDIndicatorEnabled <- switchData.appliedLEDIndicatorEnabled
```

In `metadata(for:)`, pass:

```swift
appliedLEDIndicatorEnabled: row[ExpressionKey.appliedLEDIndicatorEnabled]
```

- [ ] **Step 2: Add `PJEightKeySwitchData` state and helpers**

In `PJEightKeySwitchData`, add:

```swift
var appliedLEDIndicatorEnabled: Bool?
```

In `convenience init(baseSwitchData:metadata:)`, assign:

```swift
appliedLEDIndicatorEnabled = metadata.appliedLEDIndicatorEnabled
```

In `copy()`, assign:

```swift
copy.appliedLEDIndicatorEnabled = appliedLEDIndicatorEnabled
```

Update `needsBatteryPowerSwitchSync`:

```swift
return needsBatteryPowerSwitchConfigurationSync
    || needsBatteryPowerSwitchTxEnableSync
    || needsBatteryPowerSwitchLEDIndicatorSync
    || needSyncData
```

Add:

```swift
var needsBatteryPowerSwitchLEDIndicatorSync: Bool {
    guard proxyNode?.isBatteryPowerSwitch == true else {
        return false
    }
    return appliedLEDIndicatorEnabled != moreSettingsState.ledIndicatorEnabled
}
```

Update `markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups:)`:

```swift
appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled
```

Add:

```swift
func markBatteryPowerSwitchLEDIndicatorSucceeded() {
    appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled
    lastSyncFailedReason = nil
}
```

- [ ] **Step 3: Mark new devices as LED-applied enabled**

In `BatteryPowerSwitchAddConfiguration.prepareSwitchData(for:)`, after `switchData.appliedTxEnabled = true`, add:

```swift
switchData.moreSettingsState.ledIndicatorEnabled = true
switchData.appliedLEDIndicatorEnabled = true
```

Do not add any LED message handle in `defaultConfigurationMessageHandles(...)`.

- [ ] **Step 4: Static check for new state**

Run:

```bash
rg -n "appliedLEDIndicatorEnabled|needsBatteryPowerSwitchLEDIndicatorSync|markBatteryPowerSwitchLEDIndicatorSucceeded" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: matches in repository, data model, and add configuration only at this point.

- [ ] **Step 5: Commit app state changes**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "feat: track battery switch led applied state"
```

---

### Task 3: Hide Periodic Reporting in More Settings

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMoreSettingsController.swift`

- [ ] **Step 1: Remove Periodic Reporting from the visible layout**

In `setupUI()`, keep the periodic views declared in the file, but stop adding `periodicCardView` to `contentView`. Make `ledCardView` the first visible card:

```swift
contentView.addSubview(ledCardView)
ledCardView.snp.makeConstraints { make in
    make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.bottom.equalTo(SCRYFrom(-24))
}
```

Remove these visible setup calls from execution:

```swift
contentView.addSubview(periodicCardView)
periodicCardView.addSubview(periodicTitleLabel)
periodicCardView.addSubview(periodicDescriptionLabel)
periodicCardView.addSubview(periodicSliderView)
```

The `periodicCardView`, labels, slider, `PeriodicReportingOption`, and `state.periodicReporting` definitions remain in the codebase.

- [ ] **Step 2: Stop binding hidden slider actions**

In `bindActions()`, remove the slider binding body so hidden Periodic Reporting cannot change state:

```swift
private func bindActions() {}
```

Keep `viewModel.state.periodicReporting` unchanged when the controller opens and returns.

- [ ] **Step 3: Static checks for hidden-but-retained Periodic Reporting**

Run:

```bash
rg -n "contentView.addSubview\\(periodicCardView\\)|periodicSliderView.valueChanged" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMoreSettingsController.swift
```

Expected: no matches.

Run:

```bash
rg -n "PeriodicReportingOption|periodicReporting|periodicSliderView" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: definitions and storage references remain.

- [ ] **Step 4: Commit UI hiding**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMoreSettingsController.swift
git commit -m "feat: hide battery switch periodic reporting"
```

---

### Task 4: Add LED Indicator to SyncDevices

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Add a SyncDevices action type**

In `ActionType`, after `batteryPowerSwitchTxEnable`, add:

```swift
/// Battery Power Switch LED 指示总开关
case batteryPowerSwitchLEDIndicator(switchData: PJEightKeySwitchData)
```

In `DeviceOperationType.isSuccessful`, include LED with the own configuration cases:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
    return true
```

Apply this to both `.delete` and `.configuration` branches where the same cases appear.

- [ ] **Step 2: Generate the LED message handle**

In `DeviceOperationType.messageHandles`, include LED in the delete no-op list:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator, .batteryPowerSwitchTargetSubscription:
    break
```

In the `.configuration` switch, after `.batteryPowerSwitchTxEnable`, add:

```swift
case .batteryPowerSwitchLEDIndicator(let switchData):
    if node.primaryUnicastAddress == switchData.proxyNodeAddress, let vendorModel = node.sunricherVendorModel {
        let handle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(switchData.moreSettingsState.ledIndicatorEnabled)),
            model: vendorModel
        )
        handle.continuous = false
        messageHandles.append(handle)
    }
```

- [ ] **Step 3: Insert LED after TX Enable in the own configuration step**

In `SyncDevicesViewController.appendBatteryPowerSwitchItems(...)`, add:

```swift
let needsLEDIndicatorSync = switchData.needsBatteryPowerSwitchLEDIndicatorSync
```

After the TX Enable task append, add:

```swift
if needsLEDIndicatorSync {
    ownConfigurationTasks.append(SyncDeviceStepTaskModel(
        name: "LED Indicator",
        operationType: .configuration(node: switchNode, type: .batteryPowerSwitchLEDIndicator(switchData: switchData))
    ))
}
```

Keep this order in the source:

```text
Key Config
TX Enable
LED Indicator
```

- [ ] **Step 4: Include LED in Monitor-page own configuration classification**

In `PJEightKeySwitchMonitorVC.containsBatteryPowerSwitchOwnConfiguration(_:)`, update the switch:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
    return true
```

- [ ] **Step 5: Static check for ordering and message generation**

Run:

```bash
rg -n "batteryPowerSwitchLEDIndicator|LED Indicator|batteryPowerSwitchLEDEnabled" SunSmart/Main/Space SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected: matches in `ActionType`, message handle generation, own configuration task creation, and Monitor classification.

- [ ] **Step 6: Commit sync queue changes**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: sync battery switch led indicator"
```

---

### Task 5: Route Edit SAVE Persistence Through LED Success

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Replace single enabled rollback with an own-state snapshot**

Add this private struct near `Snapshot`:

```swift
private struct BatteryPowerSwitchOwnStateSnapshot {
    let enabled: Bool
    let moreSettings: PJEightKeySwitchMoreSettingsViewModel.State
}
```

Replace:

```swift
private var pendingBatteryPowerSwitchPreviousEnabled: Bool?
```

with:

```swift
private var pendingBatteryPowerSwitchOwnStateSnapshot: BatteryPowerSwitchOwnStateSnapshot?
```

- [ ] **Step 2: Include LED in SAVE own configuration decision**

In `submitBatteryPowerSwitch(_:)`, after `needsTxEnableSync`, add:

```swift
let needsLEDIndicatorSync = needsBatteryPowerSwitchLEDIndicatorSync(switchData)
```

Replace:

```swift
let needsOwnConfigurationSync = needsConfigurationSync || needsTxEnableSync
```

with:

```swift
let needsOwnConfigurationSync = needsConfigurationSync || needsTxEnableSync || needsLEDIndicatorSync
```

Replace pending snapshot assignment:

```swift
pendingBatteryPowerSwitchPreviousEnabled = viewModel.sourceSwitchData?.enabled
```

with:

```swift
if let sourceSwitchData = viewModel.sourceSwitchData {
    pendingBatteryPowerSwitchOwnStateSnapshot = BatteryPowerSwitchOwnStateSnapshot(
        enabled: sourceSwitchData.enabled,
        moreSettings: sourceSwitchData.moreSettingsState
    )
}
```

- [ ] **Step 3: Add LED sync comparison helper**

After `needsBatteryPowerSwitchTxEnableSync(_:)`, add:

```swift
private func needsBatteryPowerSwitchLEDIndicatorSync(_ switchData: PJEightKeySwitchData) -> Bool {
    guard isBatteryPowerSwitchLinked(switchData) else {
        return false
    }
    guard let sourceSwitchData = viewModel.sourceSwitchData else {
        return switchData.needsBatteryPowerSwitchLEDIndicatorSync
    }
    return sourceSwitchData.moreSettingsState.ledIndicatorEnabled != switchData.moreSettingsState.ledIndicatorEnabled
        || switchData.needsBatteryPowerSwitchLEDIndicatorSync
}
```

- [ ] **Step 4: Restore LED state on own configuration failure**

In `pushBatteryPowerSwitchSync(_:)` success callback, replace:

```swift
self.pendingBatteryPowerSwitchPreviousEnabled = nil
```

with:

```swift
self.pendingBatteryPowerSwitchOwnStateSnapshot = nil
```

In `backActionCallback`, replace the old enabled rollback block:

```swift
if let previousEnabled = self.pendingBatteryPowerSwitchPreviousEnabled {
    switchData.enabled = previousEnabled
}
```

with:

```swift
if let snapshot = self.pendingBatteryPowerSwitchOwnStateSnapshot {
    switchData.enabled = snapshot.enabled
    switchData.moreSettingsState = snapshot.moreSettings
}
```

Replace the final clear:

```swift
self.pendingBatteryPowerSwitchPreviousEnabled = nil
```

with:

```swift
self.pendingBatteryPowerSwitchOwnStateSnapshot = nil
```

- [ ] **Step 5: Include LED in own configuration classification**

In `containsBatteryPowerSwitchOwnConfiguration(_:)`, update:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
    return true
```

- [ ] **Step 6: Static check SAVE flow**

Run:

```bash
rg -n "pendingBatteryPowerSwitchPreviousEnabled|pendingBatteryPowerSwitchOwnStateSnapshot|needsBatteryPowerSwitchLEDIndicatorSync|batteryPowerSwitchLEDIndicator" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: no `pendingBatteryPowerSwitchPreviousEnabled` match; matches for the new snapshot, LED helper, and LED own configuration classification.

- [ ] **Step 7: Commit SAVE flow changes**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: persist battery switch led after sync success"
```

---

### Task 6: Final Verification

**Files:**
- Verify app and SDK working trees.

- [ ] **Step 1: Run whitespace check**

Run from `/Users/maginawin/Developer/iOS/YKH/sun-smart/.worktrees/k8-switch-260519`:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 2: Verify Periodic Reporting is hidden but retained**

Run:

```bash
rg -n "contentView.addSubview\\(periodicCardView\\)|periodicSliderView.valueChanged" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMoreSettingsController.swift
```

Expected: no matches.

Run:

```bash
rg -n "PeriodicReportingOption|periodicReporting|ExpressionKey.periodicReporting" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: matches remain in the ViewModel, repository, and edit snapshot code.

- [ ] **Step 3: Verify LED command is not sent during add defaults**

Run:

```bash
rg -n "batteryPowerSwitchLEDEnabled" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected: no matches.

- [ ] **Step 4: Verify Battery Power Switch own configuration coverage**

Run:

```bash
rg -n "batteryPowerSwitchLEDIndicator|appliedLEDIndicatorEnabled|needsBatteryPowerSwitchLEDIndicatorSync" SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Space
```

Expected: matches cover data model, repository, add configuration, SyncDevices action/message, SyncDevices ordering, and Edit/Monitor own configuration classification.

- [ ] **Step 5: Build the iOS app**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run SDK targeted test command**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected in a SwiftPM-capable environment: tests pass. In this local SDK repository, a known `no such module 'UIKit'` SwiftPM failure may occur before tests run; report that exact limitation and rely on the successful iPhoneOS app build for SDK compilation.

- [ ] **Step 7: Verify working trees**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: no uncommitted changes in either repo after all planned commits.
