# Battery Power Switch Configuration Re-Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battery Power Switch configuration 失败后，Re-Sync 先等待设备激活，再从 `Reset` 开始全量重发 configuration，同时修正 Model Publication 成功判定并减少不必要等待。

**Architecture:** 改动集中在通用同步页面的 BPS 分支。`SyncDevicesViewController` 负责识别 BPS configuration Re-Sync、复用 activation flow、全量重置 configuration 状态；`SyncDevicesCellModel` 负责 publication 真实校验、跳过已正确 publication，并让 BPS 自身单播消息 fail-fast。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `SyncDevicesViewController`, existing `PJEightKeySwitchActivationFlow`, existing Mesh `MeshMessageHandle.continuous`.

---

## File Structure

- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Add BPS activation flow property.
  - Add BPS operation classification helpers.
  - Add BPS full configuration reset helpers.
  - Gate BPS configuration Re-Sync through activation flow.
  - Mark later BPS own-unicast tasks failed when fail-fast has already triggered.

- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - Change `.batteryPowerSwitchModelPublication` success from unconditional `true` to real publication state check.
  - Change publication message generation from `includeExisting: true` to `includeExisting: false`.
  - Set BPS own-unicast message handles `continuous = false` for reset, key config, and model publication.

- Verification only: no XCTest target exists in this worktree. Use focused `rg` checks and `xcodebuild` compile verification.

---

### Task 1: Add BPS Configuration Classification Helpers

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Add activation flow and fail-fast state properties**

Near existing properties in `SyncDevicesViewController`, after `profileSensorProtectionContext`, add:

```swift
    private var batteryPowerSwitchActivationFlow: PJEightKeySwitchActivationFlow?
    private var batteryPowerSwitchOwnConfigurationFailed = false
```

- [ ] **Step 2: Add operation classification helpers**

Add these helpers inside `extension SyncDevicesViewController` before `prepareDeviceForResync(_:)`:

```swift
    private var batteryPowerSwitchDataForSync: PJEightKeySwitchData? {
        guard case .batteryPowerSwitch(let switchData) = type else {
            return nil
        }
        return switchData
    }

    private func isBatteryPowerSwitchConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchReset,
                 .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchModelPublication:
                return true
            case .batteryPowerSwitchTargetSubscription(_, _, let unsubscribe):
                return !unsubscribe
            default:
                return false
            }
        default:
            return false
        }
    }

    private func isBatteryPowerSwitchOwnConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchReset,
                 .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchModelPublication:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func operationType(for model: SyncCellModel) -> DeviceOperationType? {
        if let deviceModel = model as? SyncDevicesModel {
            return deviceModel.operationType
        }
        if let taskModel = model as? SyncDeviceStepTaskModel {
            return taskModel.operationType
        }
        return nil
    }
```

- [ ] **Step 3: Add model classification helpers**

Continue adding:

```swift
    private func containsBatteryPowerSwitchConfiguration(_ device: SyncDevicesModel) -> Bool {
        if let operationType = device.operationType {
            return isBatteryPowerSwitchConfigurationOperation(operationType)
        }
        return device.steps.contains { step in
            containsBatteryPowerSwitchConfiguration(step)
        }
    }

    private func containsBatteryPowerSwitchConfiguration(_ step: SyncDeviceStepModel) -> Bool {
        step.tasks.contains { task in
            isBatteryPowerSwitchConfigurationOperation(task.operationType)
        }
    }

    private func isBatteryPowerSwitchOwnConfiguration(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model) else {
            return false
        }
        return isBatteryPowerSwitchOwnConfigurationOperation(operationType)
    }
```

- [ ] **Step 4: Verify helper names are unique**

Run:

```bash
rg -n "batteryPowerSwitchActivationFlow|batteryPowerSwitchOwnConfigurationFailed|isBatteryPowerSwitchConfigurationOperation|containsBatteryPowerSwitchConfiguration|isBatteryPowerSwitchOwnConfiguration" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: output shows only the newly added property/helper declarations.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "refactor: classify battery switch sync tasks"
```

---

### Task 2: Gate BPS Configuration Re-Sync Through Activation

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Add full reset helpers**

Add these helpers near the classification helpers:

```swift
    private func resetBatteryPowerSwitchConfigurationForResync() {
        batteryPowerSwitchOwnConfigurationFailed = false
        sections.forEach { section in
            section.devices.forEach { resetBatteryPowerSwitchConfigurationIfNeeded($0) }
            section.groups.forEach { group in
                group.deviceModels.forEach { resetBatteryPowerSwitchConfigurationIfNeeded($0) }
            }
        }
        tableView.reloadData()
    }

    private func resetBatteryPowerSwitchConfigurationIfNeeded(_ device: SyncDevicesModel) {
        guard containsBatteryPowerSwitchConfiguration(device) else {
            return
        }
        device.isFineshed = false
        device.isSelected = false
        device.failedCount = 0
        if let operationType = device.operationType,
           isBatteryPowerSwitchConfigurationOperation(operationType) {
            device.state = .none
            return
        }
        device.steps.forEach { step in
            guard containsBatteryPowerSwitchConfiguration(step) else {
                return
            }
            step.isFineshed = false
            step.tasks.forEach { task in
                guard isBatteryPowerSwitchConfigurationOperation(task.operationType) else {
                    return
                }
                task.isFineshed = false
                task.failedCount = 0
                task.state = .none
            }
        }
    }
```

- [ ] **Step 2: Add activation runner**

Add:

```swift
    private func startBatteryPowerSwitchConfigurationResyncAfterActivation() {
        guard let switchData = batteryPowerSwitchDataForSync else {
            return
        }
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: switchData
        ) { [weak self] in
            guard let self else { return }
            self.batteryPowerSwitchActivationFlow = nil
            self.resetBatteryPowerSwitchConfigurationForResync()
            self.syncState = .inSync
            self.updateSyncStateUI()
            self.startSync()
        }
        batteryPowerSwitchActivationFlow = flow
        flow.start()
    }
```

- [ ] **Step 3: Add selected-failure helper**

Add:

```swift
    private func selectedFailedDevicesForResync() -> [SyncDevicesModel] {
        var selectedDevices: [SyncDevicesModel] = []
        sections.forEach { section in
            let models = section.allModels.filter {
                (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed
            } as! [SyncDevicesModel]
            selectedDevices.append(contentsOf: models)
        }
        return selectedDevices
    }
```

- [ ] **Step 4: Update top RE-Sync path**

In `rightItemAction()`, inside `else if syncState == .syncFailure`, replace the local selected-model collection block with:

```swift
            let selectModels = selectedFailedDevicesForResync()
            if selectModels.count > 0 {
                if selectModels.contains(where: { containsBatteryPowerSwitchConfiguration($0) }) {
                    startBatteryPowerSwitchConfigurationResyncAfterActivation()
                } else {
                    selectModels.forEach { device in
                        prepareDeviceForResync(device)
                    }
                    syncState = .inSync
                    startSync()
                }
            }
```

Keep the existing final `updateSyncStateUI()` call after the branch.

- [ ] **Step 5: Update single-device Re-Sync**

Replace `cell(_:resyncAction model: SyncDevicesModel)` with:

```swift
    func cell(_ cell: SyncDeviceViewCell, resyncAction model: SyncDevicesModel) {
        if containsBatteryPowerSwitchConfiguration(model) {
            startBatteryPowerSwitchConfigurationResyncAfterActivation()
            return
        }
        prepareDeviceForResync(model)
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
```

- [ ] **Step 6: Update single-step Re-Sync**

Replace `cell(_:resyncAction model: SyncDeviceStepModel)` with:

```swift
    func cell(_ cell: SyncDeviceStepViewCell, resyncAction model: SyncDeviceStepModel) {
        if containsBatteryPowerSwitchConfiguration(model) {
            startBatteryPowerSwitchConfigurationResyncAfterActivation()
            return
        }
        prepareStepForResync(model)
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
```

- [ ] **Step 7: Verify remove/unsubscription is excluded**

Run:

```bash
rg -n "batteryPowerSwitchTargetSubscription\\(_, _, let unsubscribe\\)|return !unsubscribe|startBatteryPowerSwitchConfigurationResyncAfterActivation|selectedFailedDevicesForResync" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: output includes `return !unsubscribe`, proving `unsubscribe == true` stays outside full configuration Re-Sync.

- [ ] **Step 8: Build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: activate before battery switch resync"
```

---

### Task 3: Make BPS Model Publication Real and Faster

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Add publication success helper**

Add this helper near `DeviceOperationType` or below the enum extension area:

```swift
private func isBatteryPowerSwitchPublicationSuccessful(node: Node, switchData: PJEightKeySwitchData) -> Bool {
    guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
          let switchGroup = switchData.linkGroup else {
        return false
    }
    return node.getBatteryPowerSwitchPublicationMessageHandles(
        switchGroup: switchGroup,
        includeExisting: false
    ).isEmpty
}
```

- [ ] **Step 2: Replace unconditional publication success in `DeviceOperationType.isSuccessful`**

In both `.delete` and `.configuration` switch branches, change the BPS cases from:

```swift
            case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchModelPublication:
                return true
```

to:

```swift
            case .batteryPowerSwitchModelPublication(let switchData):
                return isBatteryPowerSwitchPublicationSuccessful(node: node, switchData: switchData)
            case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig:
                return true
```

Do this for both occurrences in the file.

- [ ] **Step 3: Optimize publication message generation**

In `DeviceOperationType.messageHandles`, change:

```swift
messageHandles.append(contentsOf: node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: true))
```

to:

```swift
messageHandles.append(contentsOf: node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: false))
```

- [ ] **Step 4: Set BPS own-unicast handles to fail-fast**

In `DeviceOperationType.messageHandles`, update the BPS own-unicast cases so generated handles set `continuous = false`:

```swift
            case .batteryPowerSwitchReset(let switchData):
                if node.primaryUnicastAddress == switchData.proxyNodeAddress, let vendorModel = node.sunricherVendorModel {
                    let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchResetDefaults), model: vendorModel)
                    handle.continuous = false
                    messageHandles.append(handle)
                }
            case .batteryPowerSwitchKeyConfig(let switchData):
                if node.primaryUnicastAddress == switchData.proxyNodeAddress, let vendorModel = node.sunricherVendorModel {
                    let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
                    messageHandles.append(contentsOf: switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
                        let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)), model: vendorModel)
                        handle.continuous = false
                        return handle
                    })
                }
            case .batteryPowerSwitchModelPublication(let switchData):
                if node.primaryUnicastAddress == switchData.proxyNodeAddress, let switchGroup = switchData.linkGroup {
                    let handles = node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: false)
                    handles.forEach { $0.continuous = false }
                    messageHandles.append(contentsOf: handles)
                }
```

- [ ] **Step 5: Verify no unconditional publication success remains**

Run:

```bash
rg -n "batteryPowerSwitchModelPublication|includeExisting: true|continuous = false|isBatteryPowerSwitchPublicationSuccessful" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:
- `.batteryPowerSwitchModelPublication` success points call `isBatteryPowerSwitchPublicationSuccessful`.
- BPS publication message generation uses `includeExisting: false`.
- BPS own-unicast handles show `continuous = false`.
- No BPS publication line still uses `includeExisting: true`.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: validate battery switch publication sync"
```

---

### Task 4: Mark Later BPS Own Configuration Tasks Failed After Fail-Fast

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Add fail-fast marking helper**

Add near BPS helpers:

```swift
    private func markPendingBatteryPowerSwitchOwnConfigurationTasksFailed() {
        sections.forEach { section in
            section.devices.forEach { markPendingBatteryPowerSwitchOwnConfigurationTasksFailed(in: $0) }
            section.groups.forEach { group in
                group.deviceModels.forEach { markPendingBatteryPowerSwitchOwnConfigurationTasksFailed(in: $0) }
            }
        }
    }

    private func markPendingBatteryPowerSwitchOwnConfigurationTasksFailed(in device: SyncDevicesModel) {
        guard containsBatteryPowerSwitchConfiguration(device) else {
            return
        }
        if let operationType = device.operationType,
           isBatteryPowerSwitchOwnConfigurationOperation(operationType),
           device.state == .none || device.state == .wait {
            device.state = .failed
            device.failedCount += 1
            return
        }
        device.steps.forEach { step in
            step.tasks.forEach { task in
                guard isBatteryPowerSwitchOwnConfigurationOperation(task.operationType),
                      task.state == .none || task.state == .wait else {
                    return
                }
                task.state = .failed
                task.failedCount += 1
            }
        }
    }
```

- [ ] **Step 2: Clear fail-fast flag at the beginning of each sync run**

At the start of `startSync()`, before iterating sections, add:

```swift
        batteryPowerSwitchOwnConfigurationFailed = false
```

- [ ] **Step 3: Skip BPS own-unicast tasks if fail-fast already triggered**

In `startSync()`, after `messageHandles` is computed and before sending through `MeshProxyMessageCommand.shared.addMessage`, add:

```swift
                if batteryPowerSwitchOwnConfigurationFailed,
                   isBatteryPowerSwitchOwnConfiguration(model) {
                    model.state = .failed
                    (model as? SyncDevicesModel)?.failedCount += 1
                    (model as? SyncDeviceStepTaskModel)?.failedCount += 1
                    updateCell(model: model)
                    DispatchQueue.main.async {
                        if let model = self.showProressStepModel,
                           let progressView = SyncDevicesProgressView.current() {
                            progressView.stepModel = model
                        }
                    }
                    continue
                }
```

- [ ] **Step 4: Trigger fail-fast when a BPS own task fails**

In the `finishedBack` closure where `model.state = .failed` is assigned, add immediately after incrementing failed counts:

```swift
                        if self.isBatteryPowerSwitchOwnConfiguration(model) {
                            self.batteryPowerSwitchOwnConfigurationFailed = true
                            self.markPendingBatteryPowerSwitchOwnConfigurationTasksFailed()
                        }
```

The surrounding failure branch should become:

```swift
                    }else {
                        model.state = .failed
                        (model as? SyncDevicesModel)?.failedCount += 1
                        (model as? SyncDeviceStepTaskModel)?.failedCount += 1
                        if self.isBatteryPowerSwitchOwnConfiguration(model) {
                            self.batteryPowerSwitchOwnConfigurationFailed = true
                            self.markPendingBatteryPowerSwitchOwnConfigurationTasksFailed()
                        }
                    }
```

- [ ] **Step 5: Verify fail-fast code is scoped to BPS own configuration**

Run:

```bash
rg -n "batteryPowerSwitchOwnConfigurationFailed|markPendingBatteryPowerSwitchOwnConfigurationTasksFailed|isBatteryPowerSwitchOwnConfiguration" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: all matches are in helper declarations, startSync skip logic, and failure handling.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: fail fast battery switch configuration"
```

---

### Task 5: Final Verification

**Files:**
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Verify activation gate exists on BPS Re-Sync**

Run:

```bash
rg -n "startBatteryPowerSwitchConfigurationResyncAfterActivation|PJEightKeySwitchActivationFlow|resetBatteryPowerSwitchConfigurationForResync|containsBatteryPowerSwitchConfiguration" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: output shows the activation flow helper, reset helper, and all three Re-Sync call sites.

- [ ] **Step 2: Verify publication no longer uses unconditional success or full resend**

Run:

```bash
rg -n "batteryPowerSwitchModelPublication|isBatteryPowerSwitchPublicationSuccessful|includeExisting: false|includeExisting: true" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
```

Expected:
- `batteryPowerSwitchModelPublication` success uses `isBatteryPowerSwitchPublicationSuccessful`.
- publication message generation uses `includeExisting: false`.
- no BPS publication generation uses `includeExisting: true`.

- [ ] **Step 3: Verify BPS own messages are fail-fast**

Run:

```bash
rg -n "continuous = false|batteryPowerSwitchOwnConfigurationFailed|markPendingBatteryPowerSwitchOwnConfigurationTasksFailed" SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:
- BPS reset/key config/publication handles set `continuous = false`.
- controller tracks and marks later BPS own configuration failures.

- [ ] **Step 4: Final build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Confirm git status**

Run:

```bash
git status --short
```

Expected: no modified tracked files. The pre-existing untracked `docs/260520_1516_battery_power_switch_publication_analysis.md` may still appear and must not be added unless the user explicitly asks.
