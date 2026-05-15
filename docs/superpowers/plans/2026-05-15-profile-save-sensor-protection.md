# SAVE Profile PIR Target State Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During Group page SAVE Profile sync, disable all group PIR sensors with per-node no-wait unicast before Profile configuration, then apply the newly saved Profile's PIR target state after Profile configuration.

**Architecture:** Replace the existing outer-loop group multicast protection with SAVE Profile specific sync tasks. Add an app-local unacknowledged Sunricher vendor set wrapper for pre-Profile PIR disable, create synthetic pre/post PIR sync tasks around normal Profile configuration, skip duplicate normal PIR tasks, and use a fallback path for stop/back/failure after the pre-disable phase starts.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, `MeshNetworkManager` callback sends, existing `SyncDevicesViewController` / `SyncDevicesCellModel` task models.

---

## File Structure

- Modify `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - Add an internal `SunricherVendorSetUnacknowledged` wrapper using the same vendor opcode and payload as `SunricherVendorSet`.
  - Replace old snapshot/restore context with target-state context.
  - Add action types for Profile protection disable and Profile target-state enable.
  - Add helpers that build synthetic sync device models for pre-disable and post-enable phases.
- Modify `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - Keep existing context creation before `saveActionCallback?(selectProfile)` and pass it to the sync controller.
- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Insert synthetic PIR protection models into the configuration section.
  - Skip normal `pirEnabled(true/false)` tasks while SAVE Profile protection is active.
  - Execute pre-disable tasks with direct no-wait unicast and `100 ms` spacing.
  - Execute remaining target-state enable tasks on failure/stop/back when needed.

The project currently has no focused unit test target for this flow, so verification is build checks plus source checks that prove group multicast and old-state restoration are gone.

---

### Task 1: Add App-Local Unacknowledged Sunricher Vendor Set

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Add the no-wait vendor message type**

In `SyncDevicesCellModel.swift`, after `class SyncCellModel` and before `final class ProfileSensorProtectionContext`, add:

```swift
struct SunricherVendorSetUnacknowledged: StaticUnacknowledgedVendorMessage {

    static let opCode: UInt32 = SunricherVendorSet.opCode

    let function: VendorFunctionSet

    var parameters: Data? {
        return SunricherVendorSet(function: function).parameters
    }

    init(function: VendorFunctionSet) {
        self.function = function
    }

    init?(parameters: Data) {
        return nil
    }
}
```

This keeps the device-facing vendor opcode and payload identical to the acknowledged set while making the send path no-wait. It stays in the app target and does not require modifying the sibling `nordic-sig-mesh-sdk` repository.

- [ ] **Step 2: Build-check the message type**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pir-target-task1.log 2>&1
```

Expected: build succeeds. If it fails, `/tmp/sun-smart-profile-pir-target-task1.log` must not contain unresolved symbols for `StaticUnacknowledgedVendorMessage`, `SunricherVendorSet.opCode`, or `VendorFunctionSet`.

- [ ] **Step 3: Commit**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "Add unacknowledged Sunricher vendor set"
```

---

### Task 2: Replace Context With PIR Target-State Planning

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Replace `ProfileSensorProtectionContext`**

In `SyncDevicesCellModel.swift`, replace the current `ProfileSensorProtectionContext`, `Group.profileSensorProtectionPIREnabledSnapshot()`, and `Node.supportsProfileSensorProtection` block. Keep the `SunricherVendorSetUnacknowledged` struct from Task 1, then use this context:

```swift
final class ProfileSensorProtectionContext {

    static let operationInterval: TimeInterval = 0.1
    static let disableSendCount = 2
    static let disableInterval: TimeInterval = 0.1

    private weak var group: Group?
    let savedProfileType: Profile.ProfileType
    private var preDisableStarted = false
    private var fallbackTargetStateStarted = false
    private var targetStateTaskAddresses: Set<Address> = []

    init(group: Group, savedProfile: Profile) {
        self.group = group
        self.savedProfileType = savedProfile.type
    }

    var usesPIRTargetState: Bool {
        return savedProfileType.occupancyType
    }

    var sensorNodes: [Node] {
        return group?.sensorNodes.filter { $0.supportsProfileSensorProtection } ?? []
    }

    var groupAddress: Address {
        return group?.address.address ?? 0
    }

    func markPreDisableStarted() {
        preDisableStarted = true
    }

    func markTargetStateTaskStarted(for node: Node) {
        targetStateTaskAddresses.insert(node.primaryUnicastAddress)
    }

    func remainingTargetStateMessageHandles() -> [MeshMessageHandle] {
        guard preDisableStarted,
              usesPIRTargetState,
              !fallbackTargetStateStarted else {
            return []
        }
        fallbackTargetStateStarted = true
        return targetEnableNodes(excluding: targetStateTaskAddresses).compactMap { node in
            guard let vendorModel = node.sunricherVendorModel else { return nil }
            return MeshMessageHandle(message: SunricherVendorSet(function: .pirEnabled(enabled: true)), model: vendorModel)
        }
    }

    func markDisableStartedIfNeeded() -> Bool {
        guard !preDisableStarted else { return false }
        preDisableStarted = true
        return true
    }

    func markRestoreStartedIfNeeded() -> Bool {
        guard preDisableStarted,
              !fallbackTargetStateStarted else {
            return false
        }
        fallbackTargetStateStarted = true
        return true
    }

    func temporaryDisableMessage() -> MeshMessage {
        return SunricherVendorSet(function: .pirEnabled(enabled: false))
    }

    func restoreMessageHandles() -> [MeshMessageHandle] {
        guard usesPIRTargetState else { return [] }
        return targetEnableNodes(excluding: []).compactMap { node in
            guard let vendorModel = node.sunricherVendorModel else { return nil }
            return MeshMessageHandle(message: SunricherVendorSet(function: .pirEnabled(enabled: true)), model: vendorModel)
        }
    }

    func preDisableDeviceModel() -> SyncDevicesModel? {
        let tasks = sensorNodes.map { node in
            SyncDeviceStepTaskModel(
                name: "pir_disable".localizedString,
                operationType: .configuration(node: node, type: .profileSensorProtectionDisable)
            )
        }
        guard !tasks.isEmpty else { return nil }

        let step = SyncDeviceStepModel(type: "pir_disable".localizedString, state: .none, tasks: tasks)
        tasks.forEach { $0.parentStepModel = step }

        let model = SyncDevicesModel(name: "pir_disable".localizedString, address: 0)
        model.steps = [step]
        step.parentDeviceModel = model
        return model
    }

    func postTargetStateDeviceModel() -> SyncDevicesModel? {
        guard usesPIRTargetState else { return nil }

        let tasks = targetEnableNodes(excluding: []).map { node in
            SyncDeviceStepTaskModel(
                name: "pir_enabled".localizedString,
                operationType: .configuration(node: node, type: .profileSensorTargetEnable)
            )
        }
        guard !tasks.isEmpty else { return nil }

        let step = SyncDeviceStepModel(type: "pir_enabled".localizedString, state: .none, tasks: tasks)
        tasks.forEach { $0.parentStepModel = step }

        let model = SyncDevicesModel(name: "pir_enabled".localizedString, address: 0)
        model.steps = [step]
        step.parentDeviceModel = model
        return model
    }

    private func targetEnableNodes(excluding excludedAddresses: Set<Address>) -> [Node] {
        return sensorNodes.filter { !excludedAddresses.contains($0.primaryUnicastAddress) }
    }
}

private extension Node {

    var supportsProfileSensorProtection: Bool {
        return presenceDetectedSensorModel != nil && capabilities.contains(.pirEnabled)
    }
}
```

- [ ] **Step 2: Add protection action types**

In `enum ActionType`, directly after `case pirEnabled(_ enabled: Bool)`, add:

```swift
/// SAVE Profile PIR 前置禁用，使用 no-wait 单播
case profileSensorProtectionDisable
/// SAVE Profile PIR 后置目标状态启用，使用 ACK 单播
case profileSensorTargetEnable
```

- [ ] **Step 3: Update success checks**

In `DeviceOperationType.isSuccessful`, update both `.delete` and `.configuration` switch branches that handle `ActionType` so they include:

```swift
case .profileSensorProtectionDisable:
    return node.pirEnabled == false
case .profileSensorTargetEnable:
    return node.pirEnabled == true
```

The `.delete` branch may not use these cases in practice, but adding them keeps the enum exhaustive and safe.

- [ ] **Step 4: Update message handle generation**

In `DeviceOperationType.messageHandles`, update both `.delete` and `.configuration` switch branches so they include:

```swift
case .profileSensorProtectionDisable:
    break
case .profileSensorTargetEnable:
    messageHandles.append(contentsOf: NodeSyncData.pirEnabled(true).getMessageHandles(node: node))
```

The disable case intentionally returns no handles because it is executed by the no-wait helper in `SyncDevicesViewController`.

The `markDisableStartedIfNeeded`, `markRestoreStartedIfNeeded`, `temporaryDisableMessage`, `restoreMessageHandles`, `groupAddress`, `disableSendCount`, and `disableInterval` members are temporary compile bridges for the old `SyncDevicesViewController` helpers. Task 4 must delete those old helpers and then remove these bridge members before final verification.

- [ ] **Step 5: Build-check the model layer**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pir-target-task2.log 2>&1
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "Add profile PIR target-state planning"
```

---

### Task 3: Insert Pre/Post PIR Tasks And Skip Duplicate Normal PIR Tasks

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Insert synthetic protection devices into group SAVE Profile sync**

In `setupDataSource()`, inside `case .group(let group, let inNodes, let outNodes):`, after all group node models are appended and before `appendEmergencyFireControllerGroupMutationItems(...)`, add:

```swift
if inNodes == nil, outNodes == nil, let context = profileSensorProtectionContext {
    if let preDisableDevice = context.preDisableDeviceModel() {
        configurationSection.devices.insert(preDisableDevice, at: 0)
    }
    if let postTargetStateDevice = context.postTargetStateDeviceModel() {
        configurationSection.devices.append(postTargetStateDevice)
    }
}
```

This scopes the synthetic tasks to SAVE Profile's `SyncDevicesViewController(type: .group(group, inNodes: nil, outNodes: nil))` path and avoids member mutation flows.

- [ ] **Step 2: Skip normal PIR tasks while protection is active**

In `getSyncDeviceModel(group:node:effectiveMemberCount:)`, locate:

```swift
case .pirEnabled(let enabled):
    let name = enabled ? "pir_enabled".localizedString : "pir_disable".localizedString
    let task = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .pirEnabled(enabled)))
```

Replace the whole `case .pirEnabled(let enabled):` block with:

```swift
case .pirEnabled(let enabled):
    if profileSensorProtectionContext != nil {
        break
    }

    let name = enabled ? "pir_enabled".localizedString : "pir_disable".localizedString
    let task = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .pirEnabled(enabled)))

    let step = SyncDeviceStepModel(type: name, state: .none, tasks: [task])
    task.parentStepModel = step
    if node.groupState == .exitFailure || removeGroupStep != nil {
        deleteSteps.append(step)
    } else {
        configturationSteps.append(step)
    }
```

The `break` exits the `switch` case and prevents duplicate normal `pirEnabled(false)` and `pirEnabled(true)` tasks when SAVE Profile protection owns PIR ordering.

- [ ] **Step 3: Build-check task generation**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pir-target-task3.log 2>&1
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "Insert profile PIR protection tasks"
```

---

### Task 4: Execute No-Wait Disable And Fallback Target State

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Remove old group multicast helpers**

Delete these methods from `SyncDevicesViewController`:

```swift
private func disableProfileSensorsBeforeSyncIfNeeded()
private func restoreProfileSensorsIfNeeded()
private func restoreProfileSensorsInBackgroundIfNeeded()
```

Also remove the call to `self.disableProfileSensorsBeforeSyncIfNeeded()` near the start of `startSync()`.

- [ ] **Step 2: Add target-state fallback helpers**

Before `private func startSync()`, add:

```swift
private func applyRemainingProfileSensorTargetStateIfNeeded() {
    guard let context = profileSensorProtectionContext else {
        return
    }

    let messageHandles = context.remainingTargetStateMessageHandles()
    guard !messageHandles.isEmpty else {
        return
    }

    let semaphore = DispatchSemaphore(value: 0)
    MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 7, progressBack: nil, successfulBack: nil, failedBack: nil) { resultMessageHandles in
        resultMessageHandles.forEach { handle in
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                node.clearSyncStateCache()
            }
        }
        semaphore.signal()
    }
    semaphore.wait()
}

private func applyRemainingProfileSensorTargetStateInBackgroundIfNeeded() {
    DispatchQueue.global().async {
        self.applyRemainingProfileSensorTargetStateIfNeeded()
    }
}
```

- [ ] **Step 3: Add special task executor**

Before `private func startSync()`, add:

```swift
private func completeProfileSensorProtectionTaskIfNeeded(for model: SyncCellModel) -> Bool {
    guard let taskModel = model as? SyncDeviceStepTaskModel else {
        return false
    }

    switch taskModel.operationType {
    case .configuration(let node, let type):
        switch type {
        case .profileSensorProtectionDisable:
            profileSensorProtectionContext?.markPreDisableStarted()
            let isSuccessful = sendProfileSensorProtectionDisable(node: node)
            Thread.sleep(forTimeInterval: ProfileSensorProtectionContext.operationInterval)
            taskModel.state = isSuccessful ? .successful : .failed
            if !isSuccessful {
                taskModel.failedCount += 1
            }
            updateCell(model: taskModel)
            return true

        case .profileSensorTargetEnable:
            profileSensorProtectionContext?.markTargetStateTaskStarted(for: node)
            return false

        default:
            return false
        }
    default:
        return false
    }
}

private func sendProfileSensorProtectionDisable(node: Node) -> Bool {
    guard let vendorModel = node.sunricherVendorModel else {
        return false
    }

    let message = SunricherVendorSetUnacknowledged(function: .pirEnabled(enabled: false))
    do {
        try MeshNetworkManager.instance.send(message, to: vendorModel, completion: nil)
        node.pirEnabled = false
        node.savePropertys()
        node.clearSyncStateCache()
        return true
    } catch {
        print("profile PIR disable no-wait send failed: \(error)")
        return false
    }
}
```

- [ ] **Step 4: Call the special task executor in the sync loop**

In `startSync()`, after the UI reload and before `completeEmptyEmergencyFireControllerTaskIfNeeded(...)`, add:

```swift
if self.completeProfileSensorProtectionTaskIfNeeded(for: model) {
    DispatchQueue.main.async {
        if let progressModel = self.showProressStepModel,
           let progressView = SyncDevicesProgressView.current() {
            progressView.stepModel = progressModel
        }
        let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
        self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
    }
    continue
}
```

- [ ] **Step 5: Replace stop/back/failure hooks**

In `backAction()`, replace:

```swift
restoreProfileSensorsInBackgroundIfNeeded()
```

with:

```swift
applyRemainingProfileSensorTargetStateInBackgroundIfNeeded()
```

In the stop branch of `rightItemAction()`, replace:

```swift
MeshProxyMessageCommand.shared.stopSendMessage { [weak self] _ in
    self?.restoreProfileSensorsInBackgroundIfNeeded()
}
```

with:

```swift
MeshProxyMessageCommand.shared.stopSendMessage { [weak self] _ in
    self?.applyRemainingProfileSensorTargetStateInBackgroundIfNeeded()
}
```

In the Bluetooth-off early failure branch of `startSync()`, replace:

```swift
self.restoreProfileSensorsIfNeeded()
```

with:

```swift
self.applyRemainingProfileSensorTargetStateIfNeeded()
```

Near the normal sync completion, replace:

```swift
self.restoreProfileSensorsIfNeeded()
```

with:

```swift
self.applyRemainingProfileSensorTargetStateIfNeeded()
```

- [ ] **Step 6: Build-check sync execution**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pir-target-task4.log 2>&1
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "Execute profile PIR target-state protection"
```

---

### Task 5: Final Verification

**Files:**
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

- [ ] **Step 1: Confirm old group multicast behavior is removed**

Run:

```bash
rg -n "disableProfileSensorsBeforeSyncIfNeeded|restoreProfileSensorsIfNeeded|temporaryDisableMessage|groupAddress|disableSendCount|recordedPIREnabledByAddress" SunSmart/Main/Space SunSmart/Main/Profile
```

Expected: no matches.

- [ ] **Step 2: Confirm new PIR protection behavior is scoped**

Run:

```bash
rg -n "profileSensorProtectionContext|profileSensorProtectionDisable|profileSensorTargetEnable|SunricherVendorSetUnacknowledged|remainingTargetStateMessageHandles" SunSmart/Main SunSmart/Common
```

Expected:

```text
SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift: creates and passes profileSensorProtectionContext
SunSmart/Main/Space/Controller/SyncDevicesViewController.swift: inserts tasks and executes no-wait/fallback target state
SunSmart/Main/Space/Model/SyncDevicesCellModel.swift: defines SunricherVendorSetUnacknowledged, context, and action types
```

- [ ] **Step 3: Confirm Sensor Server publication code is untouched**

Run:

```bash
git diff HEAD~4..HEAD -- SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift
```

Expected: no changes related to `sensorEnabled`, `sensorDisable`, `sensorServerPublicationRetransmit`, or Sensor Server publication message generation.

- [ ] **Step 4: Run final build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pir-target-final.log 2>&1
```

Expected: build succeeds.

- [ ] **Step 5: Commit verification notes if any plan-only corrections were needed**

If implementation required plan corrections, commit those doc updates:

```bash
git add docs/superpowers/plans/2026-05-15-profile-save-sensor-protection.md
git commit -m "Update profile PIR target-state implementation plan"
```

If no plan corrections were needed, do not create a commit for this step.
