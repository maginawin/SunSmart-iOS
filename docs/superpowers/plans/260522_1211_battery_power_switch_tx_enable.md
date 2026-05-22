# Battery Power Switch TX Enable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Battery Power Switch enable/disable with `Vendor SET 0x4C 0x03 <enable>`, persisting App state only after the command succeeds.

**Architecture:** Treat key configuration and TX enable as separate Battery Power Switch own configuration concerns. Key Config remains responsible for button behavior; TX Enable is a new vendor command and sync task that can be sent alone or after Key Config. Monitor-page toggles use a dedicated activation-and-send flow; Edit SAVE routes TX Enable through the existing Sync device(s) pipeline.

**Tech Stack:** Swift, UIKit, SQLite.swift, NordicSigMeshSDK Swift Package, XCTest, xcodebuild.

---

## File Structure

- Modify `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  Add `0x03` Battery Power Switch subcode, status code, response mapping, and parsed status parameter.

- Modify `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
  Add `VendorFunctionSet.batteryPowerSwitchTxEnabled(Bool)` encoding.

- Modify `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  Add `VendorFunctionGet.batteryPowerSwitchTxEnabled` encoding for response-code completeness, although the App will not call GET in this feature.

- Modify `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`
  Add encoding and status parsing coverage for `0x4C 0x03`.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
  Persist `appliedTxEnabled` in Battery Power Switch metadata with SQLite migration.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  Add TX enable sync state and remove `enabled` from key configuration hash/generation behavior.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  Mark `appliedTxEnabled = true` for newly added switches and do not add a default `enable=1` command.

- Modify `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  Add `NodeSyncData.batteryPowerSwitchTxEnable(switchData:)` and message handle generation.

- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  Insert the TX Enable task in the Battery Power Switch sync queue and include it in own configuration success/failure handling.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  Add a reusable flow for activation followed by repeated TX Enable SET until success, timeout, cancel, or retry.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
  Add pending state support to temporarily disable both Enable switches during Monitor-page TX Enable updates.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
  Add helpers for applying a successful Monitor-page TX Enable update and persisting it.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  Replace immediate local toggle persistence with pending activation-and-send flow.

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  Delay Battery Power Switch Edit SAVE persistence when Key Config or TX Enable sync is required, and roll back `enabled` on own configuration failure.

---

### Task 1: Add SDK Support for `0x4C 0x03`

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`

- [ ] **Step 1: Add failing SDK tests**

Append these assertions to `testBatteryPowerSwitchSetEncoding()`:

```swift
XCTAssertEqual(
    SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(false)).parameters,
    Data([0x4C, 0x03, 0x00])
)
XCTAssertEqual(
    SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(true)).parameters,
    Data([0x4C, 0x03, 0x01])
)
```

Append this assertion to `testBatteryPowerSwitchGetEncoding()`:

```swift
XCTAssertEqual(
    SunricherVendorGet(function: .batteryPowerSwitchTxEnabled).parameters,
    Data([0x4C, 0x03])
)
```

Append these assertions to `testBatteryPowerSwitchStatusParsing()`:

```swift
let txSetAck = SunricherVendorStatus(parameters: Data([0x4C, 0x03, 0x00]))
XCTAssertEqual(txSetAck?.status.isSuccessful, true)
XCTAssertEqual(txSetAck?.status.code, .batteryPowerSwitchTxEnabled)
XCTAssertNil(txSetAck?.status.parameters)

let txGetDisabled = SunricherVendorStatus(parameters: Data([0x4C, 0x03, 0x00, 0x00]))
XCTAssertEqual(txGetDisabled?.status.isSuccessful, true)
XCTAssertEqual(txGetDisabled?.status.code, .batteryPowerSwitchTxEnabled)
if case .batteryPowerSwitchTxEnabled(let enabled) = txGetDisabled?.status.parameters {
    XCTAssertEqual(enabled, false)
} else {
    XCTFail("Expected battery power switch TX disabled")
}

let txGetEnabled = SunricherVendorStatus(parameters: Data([0x4C, 0x03, 0x00, 0x01]))
XCTAssertEqual(txGetEnabled?.status.isSuccessful, true)
XCTAssertEqual(txGetEnabled?.status.code, .batteryPowerSwitchTxEnabled)
if case .batteryPowerSwitchTxEnabled(let enabled) = txGetEnabled?.status.parameters {
    XCTAssertEqual(enabled, true)
} else {
    XCTFail("Expected battery power switch TX enabled")
}
```

- [ ] **Step 2: Run SDK test and verify it fails**

Run from `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected: build fails because `batteryPowerSwitchTxEnabled` is not defined.

- [ ] **Step 3: Implement SDK enum and encoding**

In `SunricherVendorStatus.swift`, extend `VendorBatteryPowerSwitchCode`:

```swift
/// 按键全局 TX 开关
case txEnable = 0x03
```

In `VendorFunctionCode.init?(vendorCode:subcode:)`, inside `.batteryPowerSwitch`, add:

```swift
case VendorBatteryPowerSwitchCode.txEnable.rawValue:
    self = .batteryPowerSwitchTxEnabled
```

In `VendorFunctionCode`, add:

```swift
/// 按键全局 TX 开关
case batteryPowerSwitchTxEnabled
```

In `VendorFunctionCode.code`, add:

```swift
case .batteryPowerSwitchTxEnabled:
    return [VendorOpCode.batteryPowerSwitch.rawValue, VendorBatteryPowerSwitchCode.txEnable.rawValue]
```

In `VendorStatusParameters`, add:

```swift
case batteryPowerSwitchTxEnabled(Bool)
```

In `SunricherVendorStatus` parsing, after `.batteryPowerSwitchLEDEnabled`, add:

```swift
case .batteryPowerSwitchTxEnabled:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 4 else {
        self.parameters = nil
        break
    }
    let enabled: UInt8 = data.read(fromOffset: 3)
    self.parameters = .batteryPowerSwitchTxEnabled(enabled > 0)
```

In `SunricherVendorSet.swift`, add this case to `VendorFunctionSet`:

```swift
/// 按键全局 TX 开关
case batteryPowerSwitchTxEnabled(Bool)
```

Add this encoding branch:

```swift
case .batteryPowerSwitchTxEnabled(let enabled):
    return data + (enabled ? 0x01 : 0x00)
```

Add this command branch:

```swift
case .batteryPowerSwitchTxEnabled: return .batteryPowerSwitchTxEnabled
```

In `SunricherVendorGet.swift`, add this case to `VendorFunctionGet`:

```swift
case batteryPowerSwitchTxEnabled
```

Add this command branch:

```swift
case .batteryPowerSwitchTxEnabled: return .batteryPowerSwitchTxEnabled
```

The existing default `data` branch already returns only `[0x4C, 0x03]` for this GET case.

- [ ] **Step 4: Run SDK test and verify it passes**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Expected: `BatteryPowerSwitchVendorMessageTests` passes.

- [ ] **Step 5: Commit SDK support**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add battery switch tx enable vendor message"
```

---

### Task 2: Persist TX Enable Applied State

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Add metadata storage field**

In `PJEightKeySwitchRepository.Metadata`, add:

```swift
let appliedTxEnabled: Bool?
```

Update the initializer signature and assignment:

```swift
appliedTxEnabled: Bool? = nil
```

```swift
self.appliedTxEnabled = appliedTxEnabled
```

In `ExpressionKey`, add:

```swift
static let appliedTxEnabled = Expression<Bool?>("appliedTxEnabled")
```

In `initDatabase()`, add the column to new table creation:

```swift
builder.column(ExpressionKey.appliedTxEnabled)
```

In the migration block, add:

```swift
if !columns.contains(where: { $0.name == "appliedTxEnabled" }) {
    _ = try? SunSmartDataManager.shared.db?.run(table.addColumn(ExpressionKey.appliedTxEnabled))
}
```

In `save(_:)`, add:

```swift
ExpressionKey.appliedTxEnabled <- switchData.appliedTxEnabled
```

In `metadata(for:)`, add:

```swift
appliedTxEnabled: row[ExpressionKey.appliedTxEnabled]
```

- [ ] **Step 2: Add model field and copy behavior**

In `PJEightKeySwitchData`, add:

```swift
var appliedTxEnabled: Bool?
```

In the metadata convenience initializer, add:

```swift
appliedTxEnabled = metadata.appliedTxEnabled
```

In `copy()`, add:

```swift
copy.appliedTxEnabled = appliedTxEnabled
```

- [ ] **Step 3: Add TX enable sync helpers**

In `PJEightKeySwitchData`, add:

```swift
var needsBatteryPowerSwitchTxEnableSync: Bool {
    guard proxyNode?.isBatteryPowerSwitch == true else {
        return false
    }
    return appliedTxEnabled != enabled
}

func markBatteryPowerSwitchTxEnableSucceeded() {
    appliedTxEnabled = enabled
    lastSyncFailedReason = nil
}
```

Update `needsBatteryPowerSwitchSync` to include TX Enable:

```swift
return needsBatteryPowerSwitchConfigurationSync || needsBatteryPowerSwitchTxEnableSync || needSyncData
```

Update `markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups:)` so a full own-configuration success records TX Enable too:

```swift
appliedTxEnabled = enabled
```

- [ ] **Step 4: Mark newly added switches as default-applied without sending command**

In `BatteryPowerSwitchAddConfiguration.prepareSwitchData(for:)`, after switchData is created and before `prepareBatteryPowerSwitchDesiredConfig`, set:

```swift
switchData.enabled = true
switchData.appliedTxEnabled = true
```

Do not add any `SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(true))` to `defaultConfigurationMessageHandles`.

- [ ] **Step 5: Run focused static checks**

Run:

```bash
rg -n "appliedTxEnabled|needsBatteryPowerSwitchTxEnableSync|markBatteryPowerSwitchTxEnableSucceeded" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: matches appear in `PJEightKeySwitchRepository.swift`, `PJEightKeySwitchData.swift`, and `BatteryPowerSwitchAddConfiguration.swift`.

- [ ] **Step 6: Commit metadata changes**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "feat: persist battery switch tx enable state"
```

---

### Task 3: Separate Key Config from Enabled State

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Remove enabled from key configuration hash**

In `batteryPowerSwitchDesiredConfigHash(appKeyIndex:)`, remove this element:

```swift
"enabled=\(enabled)",
```

Keep these elements:

```swift
return [
    "panel=\(eightKeyPanelType.storageIdentifier)",
    "link=\(linkGroupAddress?.hex ?? "nil")",
    "keyConfigWire=16,retransmit=0/0,transition=FF",
    "scenes=\(sceneTargets)",
    "appKey=\(appKeyIndex)"
].joined(separator: "|")
```

- [ ] **Step 2: Generate Key Config even when disabled**

In `batteryPowerSwitchKeyConfigurations(appKeyIndex:)`, replace:

```swift
guard enabled, let linkGroupAddress else {
    return []
}
```

with:

```swift
guard let linkGroupAddress else {
    return []
}
```

- [ ] **Step 3: Update Edit SAVE key config decision**

In `PJPreAddEightKeySwitchesVC.needsBatteryPowerSwitchConfigurationSync(_:desiredHash:)`, remove `enabled` from the direct Key Config change check.

Replace:

```swift
if sourceSwitchData.enabled != switchData.enabled ||
    sourceSwitchData.linkGroupAddress != switchData.linkGroupAddress ||
    sourceSwitchData.eightKeyPanelType != switchData.eightKeyPanelType {
    return true
}
```

with:

```swift
if sourceSwitchData.linkGroupAddress != switchData.linkGroupAddress ||
    sourceSwitchData.eightKeyPanelType != switchData.eightKeyPanelType {
    return true
}
```

- [ ] **Step 4: Add Edit SAVE TX enable decision helper**

In `PJPreAddEightKeySwitchesVC`, add:

```swift
private func needsBatteryPowerSwitchTxEnableSync(_ switchData: PJEightKeySwitchData) -> Bool {
    guard isBatteryPowerSwitchLinked(switchData) else {
        return false
    }
    guard let sourceSwitchData = viewModel.sourceSwitchData else {
        return switchData.needsBatteryPowerSwitchTxEnableSync
    }
    return sourceSwitchData.enabled != switchData.enabled || switchData.needsBatteryPowerSwitchTxEnableSync
}
```

- [ ] **Step 5: Run static checks**

Run:

```bash
rg -n "\"enabled=|guard enabled, let linkGroupAddress|sourceSwitchData.enabled != switchData.enabled" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: no matches for `"enabled=` or `guard enabled, let linkGroupAddress`; the only remaining enabled comparison should be inside `needsBatteryPowerSwitchTxEnableSync`.

- [ ] **Step 6: Commit key config separation**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "refactor: separate battery switch tx enable from key config"
```

---

### Task 4: Add TX Enable to SyncDevices Queue

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Add SyncData case and message handles**

In `NodeSyncData`, add:

```swift
/// Battery Power Switch 按键全局 TX 开关
case batteryPowerSwitchTxEnable(switchData: PJEightKeySwitchData)
```

In `NodeSyncData.getMessageHandles(node:)`, add:

```swift
case .batteryPowerSwitchTxEnable(let switchData):
    if node.primaryUnicastAddress == switchData.proxyNodeAddress, let vendorModel = node.sunricherVendorModel {
        let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(switchData.enabled)), model: vendorModel)
        handle.continuous = false
        messageHandles.append(handle)
    }
```

- [ ] **Step 2: Insert TX Enable task with correct order**

In `SyncDevicesViewController.appendBatteryPowerSwitchItems(...)`, compute both own-configuration needs:

```swift
let needsKeyConfigSync = switchData.needsBatteryPowerSwitchConfigurationSync
let needsTxEnableSync = switchData.needsBatteryPowerSwitchTxEnableSync
```

Replace the single `keyConfigStep` construction with a task array:

```swift
var ownConfigurationTasks: [SyncDeviceStepTaskModel] = []
if needsKeyConfigSync {
    ownConfigurationTasks.append(SyncDeviceStepTaskModel(
        name: "Key Config",
        operationType: .configuration(node: switchNode, type: .batteryPowerSwitchKeyConfig(switchData: switchData))
    ))
}
if needsTxEnableSync {
    ownConfigurationTasks.append(SyncDeviceStepTaskModel(
        name: "TX Enable",
        operationType: .configuration(node: switchNode, type: .batteryPowerSwitchTxEnable(switchData: switchData))
    ))
}
if !ownConfigurationTasks.isEmpty {
    let ownConfigurationStep = SyncDeviceStepModel(type: "Switch Configuration", state: .none, tasks: ownConfigurationTasks)
    ownConfigurationTasks.forEach { $0.parentStepModel = ownConfigurationStep }
    ownConfigurationStep.parentDeviceModel = switchDeviceModel
    switchDeviceModel.steps = [ownConfigurationStep]
    section.devices.append(switchDeviceModel)
    configurationDependencies = [ownConfigurationStep]
}
```

This preserves `Key Config -> TX Enable` order when both tasks exist and makes `TX Enable` first when Key Config is absent.

- [ ] **Step 3: Include TX Enable in own configuration predicates**

In `SyncDevicesViewController`, update these switch cases to include `.batteryPowerSwitchTxEnable` wherever `.batteryPowerSwitchKeyConfig` is treated as own configuration:

```swift
case .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable:
    return true
```

Apply that exact pattern in:

- `isBatteryPowerSwitchConfigurationOperation(_:)`
- `isBatteryPowerSwitchOwnConfigurationOperation(_:)`
- `isBatteryPowerSwitchSyncOperation(_:)`
- `isMissingRequiredBatteryPowerSwitchConfigurationHandles(_:messageHandles:)`
- `containsBatteryPowerSwitchOwnConfiguration(_:)` equivalents in `PJEightKeySwitchMonitorVC` and `PJPreAddEightKeySwitchesVC`

- [ ] **Step 4: Generate TX Enable handles in the SyncDevices override path**

In `batteryPowerSwitchMessageHandles(for:defaultHandles:)`, add:

```swift
case .batteryPowerSwitchTxEnable(let switchData):
    guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
          let vendorModel = node.sunricherVendorModel else {
        return defaultHandles
    }
    let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(switchData.enabled)), model: vendorModel)
    handle.continuous = false
    return [handle]
```

- [ ] **Step 5: Mark applied TX Enable after successful task**

In the Sync result success branch, add a helper:

```swift
private func markBatteryPowerSwitchTxEnableSucceededIfNeeded(for model: SyncCellModel) {
    guard let operationType = operationType(for: model) else { return }
    guard case .configuration(_, let actionType) = operationType else { return }
    guard case .batteryPowerSwitchTxEnable(let switchData) = actionType else { return }
    switchData.markBatteryPowerSwitchTxEnableSucceeded()
}
```

Call it immediately after `model.state = .successful`:

```swift
self.markBatteryPowerSwitchTxEnableSucceededIfNeeded(for: model)
```

- [ ] **Step 6: Run static checks**

Run:

```bash
rg -n "batteryPowerSwitchTxEnable|TX Enable|Switch Configuration" SunSmart/Main/Space SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: matches in `SyncDevicesCellModel.swift`, `SyncDevicesViewController.swift`, `PJEightKeySwitchMonitorVC.swift`, and `PJPreAddEightKeySwitchesVC.swift`.

- [ ] **Step 7: Commit Sync queue changes**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "feat: sync battery switch tx enable"
```

---

### Task 5: Implement Monitor-Page Pending Toggle Flow

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Add TX Enable sending protocol and sender**

In `PJEightKeySwitchActivationAlertController.swift`, add after the activation detector:

```swift
protocol PJEightKeySwitchTxEnableSending: AnyObject {
    func sendTxEnable(_ enabled: Bool, to node: Node, completion: @escaping (Bool) -> Void)
}

final class MeshBatteryPowerSwitchTxEnableSender: PJEightKeySwitchTxEnableSending {

    func sendTxEnable(_ enabled: Bool, to node: Node, completion: @escaping (Bool) -> Void) {
        guard let vendorModel = node.sunricherVendorModel else {
            completion(false)
            return
        }
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(enabled)),
            model: vendorModel,
            timeout: 1.5
        ) { response in
            guard let status = response as? SunricherVendorStatus else {
                completion(false)
                return
            }
            completion(status.status.isSuccessful && status.status.code == .batteryPowerSwitchTxEnabled)
        }
    }
}
```

- [ ] **Step 2: Add activation-and-send flow**

In the same file, add a new class `PJEightKeySwitchTxEnableFlow` that reuses `PJEightKeySwitchActivationAlertController` and `PJEightKeySwitchActivationAlertView.Content`. Use the same title as activation:

```swift
final class PJEightKeySwitchTxEnableFlow {

    private enum State {
        case idle
        case waiting
        case sending
        case succeeded
        case noResponse
        case cancelled
    }

    private weak var presenter: UIViewController?
    private let switchData: PJEightKeySwitchData
    private let enabled: Bool
    private let detector: PJEightKeySwitchActivationDetecting
    private let sender: PJEightKeySwitchTxEnableSending
    private let onSucceeded: (Bool) -> Void
    private let onFinished: () -> Void
    private let titleText = "neightkeyswitches_save_after_activation".localizedString
    private var alertController: PJEightKeySwitchActivationAlertController?
    private var countdownTimer: Timer?
    private var probeTimer: Timer?
    private var sendTimer: Timer?
    private var dismissWorkItem: DispatchWorkItem?
    private var remainingSeconds = 60
    private var generation = UUID()
    private var state: State = .idle

    init(
        presenter: UIViewController,
        switchData: PJEightKeySwitchData,
        enabled: Bool,
        detector: PJEightKeySwitchActivationDetecting = MeshBatteryPowerSwitchActivationDetector(),
        sender: PJEightKeySwitchTxEnableSending = MeshBatteryPowerSwitchTxEnableSender(),
        onSucceeded: @escaping (Bool) -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.switchData = switchData
        self.enabled = enabled
        self.detector = detector
        self.sender = sender
        self.onSucceeded = onSucceeded
        self.onFinished = onFinished
    }

    deinit {
        stopTimers()
        dismissWorkItem?.cancel()
    }

    func start() {
        let controller = PJEightKeySwitchActivationAlertController()
        controller.actionHandler = { [weak self] index in
            self?.handleAction(at: index)
        }
        alertController = controller
        controller.apply(content: waitingContent())
        presenter?.present(controller, animated: true) { [weak self] in
            self?.startWaiting()
        }
    }

    func cancel() {
        state = .cancelled
        generation = UUID()
        stopTimers()
        dismissWorkItem?.cancel()
        alertController?.dismiss(animated: true) { [weak self] in
            self?.onFinished()
        }
    }

    private func startWaiting() {
        generation = UUID()
        state = .waiting
        remainingSeconds = 60
        dismissWorkItem?.cancel()
        stopTimers()
        applyWaitingContent()
        sendActivationProbe(for: generation)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendActivationProbe(for: self.generation)
        }
    }

    private func startSending() {
        state = .sending
        stopProbeTimers()
        applySendingContent()
        sendTxEnable(for: generation)
        sendTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendTxEnable(for: self.generation)
        }
    }

    private func tickCountdown() {
        switch state {
        case .waiting, .sending:
            break
        default:
            return
        }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            showNoResponse()
        } else if case .waiting = state {
            applyWaitingContent()
        } else {
            applySendingContent()
        }
    }

    private func sendActivationProbe(for flowGeneration: UUID) {
        guard case .waiting = state, let node = switchData.proxyNode else { return }
        detector.sendActivationProbe(to: node) { [weak self] detected in
            DispatchQueue.main.async {
                guard let self,
                      detected,
                      self.generation == flowGeneration,
                      case .waiting = self.state else {
                    return
                }
                self.startSending()
            }
        }
    }

    private func sendTxEnable(for flowGeneration: UUID) {
        guard case .sending = state, let node = switchData.proxyNode else { return }
        sender.sendTxEnable(enabled, to: node) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self,
                      succeeded,
                      self.generation == flowGeneration,
                      case .sending = self.state else {
                    return
                }
                self.showSucceeded()
            }
        }
    }

    private func showSucceeded() {
        state = .succeeded
        stopTimers()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "done!".localizedString,
            statusStyle: .success,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
        onSucceeded(enabled)
        let workItem = DispatchWorkItem { [weak self] in
            self?.alertController?.dismiss(animated: true) { [weak self] in
                self?.onFinished()
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func showNoResponse() {
        state = .noResponse
        stopTimers()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_activation_timeout".localizedString,
            statusStyle: .failure,
            actions: [
                .init(title: "cancel".localizedString.uppercased(), style: .normal),
                .init(title: "try_again".localizedString.uppercased(), style: .primary)
            ]
        ))
    }

    private func applyWaitingContent() {
        alertController?.apply(content: waitingContent())
    }

    private func applySendingContent() {
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: String(format: "neightkeyswitches_activation_waiting_format".localizedString, remainingSeconds),
            statusStyle: .loading,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
    }

    private func waitingContent() -> PJEightKeySwitchActivationAlertView.Content {
        .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: String(format: "neightkeyswitches_activation_waiting_format".localizedString, remainingSeconds),
            statusStyle: .loading,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        )
    }

    private func handleAction(at index: Int) {
        switch state {
        case .waiting, .sending, .succeeded:
            cancel()
        case .noResponse:
            if index == 0 {
                cancel()
            } else {
                startWaiting()
            }
        case .idle, .cancelled:
            cancel()
        }
    }

    private func stopProbeTimers() {
        probeTimer?.invalidate()
        probeTimer = nil
    }

    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        probeTimer?.invalidate()
        probeTimer = nil
        sendTimer?.invalidate()
        sendTimer = nil
    }
}
```

- [ ] **Step 3: Add pending support to status view**

In `PJEightKeySwitchMonitorStatusSetView.State`, add:

```swift
let isPending: Bool
```

Update `configure(state:)` to disable both switches while pending:

```swift
enableSwitch.isEnabled = !state.isPending
innerEnableSwitch.isEnabled = !state.isPending
```

Update all call sites to pass `isPending`.

- [ ] **Step 4: Add successful update helper to Monitor ViewModel**

In `PJEightKeySwitchMonitorViewModel`, add:

```swift
func applyTxEnableSucceeded(_ isEnabled: Bool) {
    switchData.enabled = isEnabled
    switchData.markBatteryPowerSwitchTxEnableSucceeded()
}
```

- [ ] **Step 5: Replace immediate Monitor toggle persistence**

In `PJEightKeySwitchMonitorVC`, add properties:

```swift
private var txEnableFlow: PJEightKeySwitchTxEnableFlow?
private var pendingEnabledValue: Bool?
```

Update `updateUI()`:

```swift
bottomView.configure(state: .init(
    groupNames: viewModel.settingsState.groupNames,
    isGroupLinked: viewModel.settingsState.isGroupLinked,
    isEnabled: viewModel.settingsState.isEnabled,
    isPending: pendingEnabledValue != nil
))
```

Replace the `bottomView.enableChanged` body with:

```swift
bottomView.enableChanged = { [weak self] isOn in
    self?.startTxEnableUpdate(isOn)
}
```

Add:

```swift
private func startTxEnableUpdate(_ isEnabled: Bool) {
    guard pendingEnabledValue == nil else {
        updateUI()
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

Update `deinit`:

```swift
txEnableFlow?.cancel()
```

- [ ] **Step 6: Run static checks**

Run:

```bash
rg -n "PJEightKeySwitchTxEnableFlow|pendingEnabledValue|applyTxEnableSucceeded|isPending" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: matches in activation controller, monitor status view, monitor view model, and monitor controller.

- [ ] **Step 7: Commit Monitor flow**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: update battery switch tx enable from monitor"
```

---

### Task 6: Fix Edit SAVE Persistence Boundaries

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift` if Task 5 call-site updates missed compile issues.

- [ ] **Step 1: Compute TX Enable need in submit flow**

In `submitBatteryPowerSwitch(_:)`, after `needsConfigurationSync`, add:

```swift
let needsTxEnableSync = needsBatteryPowerSwitchTxEnableSync(switchData)
```

Change the early-success guard from:

```swift
guard needsConfigurationSync || needsTargetSync else {
```

to:

```swift
guard needsConfigurationSync || needsTxEnableSync || needsTargetSync else {
```

Change activation routing from:

```swift
if needsConfigurationSync {
    presentBatteryPowerSwitchActivation(for: switchData)
} else {
    pushBatteryPowerSwitchSync(switchData)
}
```

to:

```swift
if needsConfigurationSync || needsTxEnableSync {
    presentBatteryPowerSwitchActivation(for: switchData)
} else {
    pushBatteryPowerSwitchSync(switchData)
}
```

- [ ] **Step 2: Delay persistence when own configuration is required**

Replace the unconditional persistence block before the guard:

```swift
persistSwitchData(switchData)
switchSavedAction?(switchData)
postSwitchDataChangedNotifications()
initialSnapshot = makeSnapshot()
```

with:

```swift
let needsOwnConfigurationSync = needsConfigurationSync || needsTxEnableSync
if !needsOwnConfigurationSync {
    persistSwitchData(switchData)
    switchSavedAction?(switchData)
    postSwitchDataChangedNotifications()
    initialSnapshot = makeSnapshot()
}
```

Inside the no-sync success branch, preserve the save:

```swift
if needsOwnConfigurationSync {
    persistSwitchData(switchData)
    switchSavedAction?(switchData)
    postSwitchDataChangedNotifications()
    initialSnapshot = makeSnapshot()
}
XWHUDManager.showSuccessTipHUD("done!".localizedString)
```

This branch will normally run with `needsOwnConfigurationSync == false`; keeping the conditional makes the flow explicit and prevents future regressions.

- [ ] **Step 3: Preserve old enabled value for rollback**

Add a property:

```swift
private var pendingBatteryPowerSwitchPreviousEnabled: Bool?
```

Before calling `presentBatteryPowerSwitchActivation(for:)` or `pushBatteryPowerSwitchSync(_:)`, set:

```swift
pendingBatteryPowerSwitchPreviousEnabled = viewModel.sourceSwitchData?.enabled
```

In `pushBatteryPowerSwitchSync(_:)`, update `syncSuccessCallback` to clear it after save:

```swift
self.pendingBatteryPowerSwitchPreviousEnabled = nil
```

In `backActionCallback`, before persisting on own configuration failure, add:

```swift
if self.containsBatteryPowerSwitchOwnConfiguration(failedOperationTypes),
   let previousEnabled = self.pendingBatteryPowerSwitchPreviousEnabled {
    switchData.enabled = previousEnabled
}
self.pendingBatteryPowerSwitchPreviousEnabled = nil
```

- [ ] **Step 4: Mark TX Enable success as own configuration success in callbacks**

In `containsBatteryPowerSwitchOwnConfiguration(_:)`, update the switch:

```swift
case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable:
    return true
```

If `.batteryPowerSwitchReset` is no longer used in current flows, leave it in the case to avoid changing old cleanup behavior.

- [ ] **Step 5: Run focused static checks**

Run:

```bash
rg -n "needsTxEnableSync|needsOwnConfigurationSync|pendingBatteryPowerSwitchPreviousEnabled|batteryPowerSwitchTxEnable" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: matches show the new decision, delayed persistence, rollback, and own configuration classification.

- [ ] **Step 6: Commit Edit SAVE persistence changes**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: persist battery switch enable after sync success"
```

---

### Task 7: Full Verification

**Files:**
- Verify: App and local SDK worktrees.

- [ ] **Step 1: Confirm SDK package dependency points at local SDK**

Run from App worktree:

```bash
rg -n "nordic-sig-mesh-sdk|NordicSigMeshSDK" SunSmart.xcodeproj/project.pbxproj Package.resolved
```

Expected: output confirms the project resolves `NordicSigMeshSDK`; build output later must show the local path `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`.

- [ ] **Step 2: Run SDK focused tests**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

from:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: tests pass.

- [ ] **Step 3: Run App static checks**

Run:

```bash
rg -n "\"enabled=|guard enabled, let linkGroupAddress" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected: no output.

Run:

```bash
rg -n "batteryPowerSwitchTxEnable|batteryPowerSwitchTxEnabled|appliedTxEnabled|PJEightKeySwitchTxEnableFlow" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK
```

Expected: output shows App sync/flow/model references and SDK message references.

- [ ] **Step 4: Build SunSmart**

Run exactly from App worktree without shell wrapper and without redirection:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: output contains `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual QA checklist**

Verify on a v1.0.22+ Battery Power Switch:

- Add to Space creates an enabled App switch and does not send `SET 0x4C 0x03 0x01` during default add configuration.
- Monitor page Enable -> Disable enters pending, shows `Save After Activation` / `激活后保存`, waits for device activation, then sends `SET 0x4C 0x03 0x00` every 3 seconds until success.
- Monitor page Disable success updates local state, disables middle panel simulation, and persists to cloud through the existing notification path.
- Monitor page timeout cancel restores the previous UI state and does not persist local or cloud state.
- Monitor page TRY AGAIN restarts the 60-second waiting window and keeps using a 3-second send interval.
- Edit page toggling Enable does not send a command until SAVE.
- Edit SAVE with only Enable changed shows activation and syncs TX Enable.
- Edit SAVE with Key Config and Enable changed orders `Key Config` before `TX Enable`.
- Edit SAVE with only target group changes skips activation and goes directly to Sync device(s).
- Edit SAVE TX Enable failure does not persist the new enabled state.

- [ ] **Step 6: Commit final verification fixes if any code changed after prior commits**

If full verification required App compile fixes, commit them from the App worktree:

```bash
git add SunSmart
git commit -m "fix: complete battery switch tx enable integration"
```

If full verification required SDK compile fixes, commit them from the SDK repo:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK Tests/NordicSigMeshSDKTests
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: complete battery switch tx enable sdk integration"
```

Skip this commit if `git status --short` is clean after verification.
