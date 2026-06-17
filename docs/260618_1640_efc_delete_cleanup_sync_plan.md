# EFC Delete Cleanup Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement explicit SAVE vs Delete sync semantics for real EFC deletion, so Delete only clears group subscriptions and any interruption immediately leaves the EFC recoverable through normal sync.

**Architecture:** Reuse `SyncDevicesViewController` and `DeviceProtocol.deleteNodes(nodes:)`, but add an explicit EFC sync context to prevent Delete retry from becoming SAVE-style subscription repair. Split `EmergencyFireControllerSyncPlanner` so normal SAVE generates full EFC configuration tasks while Delete generates only group subscription delete tasks. Persist Delete progress inside the sync page, not only after returning to the previous screen.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `SyncDevicesViewController`, existing `EmergencyFireControllerSyncPlanner`, shell contract script.

---

## File Structure

- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Add EFC sync context to `SyncType.emergencyFire`.
  - Generate normal tasks for SAVE context and delete-only cleanup tasks for Delete context.
  - Persist group cleanup progress and failure state during Delete sync.
  - Keep Retry behavior context-aware.

- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
  - Keep `makeItems()` for SAVE/repair/full configuration sync.
  - Change Delete cleanup generation so it never emits controller disable or subscription add tasks.
  - Return failure-capable tasks for groups that still need cleanup but currently have no sendable handles.

- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
  - Add helpers to remove a group from both EFC functions after Delete cleanup succeeds.
  - Add helper to mark Delete cleanup as interrupted/failed and save `isSynced = false`.

- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
  - Use the Delete sync context from the shared EFC delete helper.
  - If associate groups are already empty, skip Sync and go directly to Reset deletion.
  - After Delete sync success, save empty associate groups before Reset.

- Modify `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
  - Keep using the shared EFC delete helper.
  - Do not add a second delete implementation.

- Modify `scripts/check_efc_controller_flows.sh`
  - Add contract checks for explicit Delete context.
  - Guard against Delete context emitting controller body tasks or `ConfigModelSubscriptionAdd`.
  - Guard that Delete cleanup still reaches `deleteNodes(nodes:)`.

## Task 1: Add Explicit EFC Sync Context

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`

- [ ] **Step 1: Add the sync context enum near `SyncType`**

Add this enum inside `extension SyncDevicesViewController`, immediately before `enum SyncType`:

```swift
enum EmergencyFireSyncContext {
    case saveConfiguration(persistsSyncResult: Bool, changedFromConfiguration: EmergencyFireControllerConfiguration?)
    case deleteCleanup

    var persistsSyncResult: Bool {
        switch self {
        case .saveConfiguration(let persistsSyncResult, _):
            return persistsSyncResult
        case .deleteCleanup:
            return false
        }
    }

    var changedFromConfiguration: EmergencyFireControllerConfiguration? {
        switch self {
        case .saveConfiguration(_, let changedFromConfiguration):
            return changedFromConfiguration
        case .deleteCleanup:
            return nil
        }
    }

    var isDeleteCleanup: Bool {
        if case .deleteCleanup = self {
            return true
        }
        return false
    }
}
```

- [ ] **Step 2: Replace the EFC `SyncType` case**

Replace:

```swift
case emergencyFire(data: DeviceEmerFireData, items: [EmergencyFireControllerSyncItem]?, persistsSyncResult: Bool, changedFromConfiguration: EmergencyFireControllerConfiguration?)
```

with:

```swift
case emergencyFire(data: DeviceEmerFireData, items: [EmergencyFireControllerSyncItem]?, context: EmergencyFireSyncContext)
```

- [ ] **Step 3: Update EFC sync setup switch**

In `setupDataSource()`, replace the current EFC case with:

```swift
case .emergencyFire(let data, let suppliedItems, let context):
    let targetSection = context.persistsSyncResult ? configurationSection : removeSection
    targetSection.prefersDevicesBeforeGroups = true
    appendEmergencyFireControllerItems(
        to: targetSection,
        data: data,
        items: suppliedItems ?? makeEmergencyFireControllerItems(data: data, context: context)
    )
```

- [ ] **Step 4: Replace the task factory signature and body**

Replace `makeEmergencyFireControllerItems(data:changedFromConfiguration:)` with:

```swift
private func makeEmergencyFireControllerItems(
    data: DeviceEmerFireData,
    context: EmergencyFireSyncContext
) -> [EmergencyFireControllerSyncItem] {
    let planner = EmergencyFireControllerSyncPlanner(
        data: data,
        meshUUID: data.meshUUID,
        subnetworkId: data.meshNetworkId,
        changedFromConfiguration: context.changedFromConfiguration
    )
    if context.isDeleteCleanup {
        return planner.makeDeleteCleanupItems()
    }
    do {
        return try planner.makeItems()
    } catch {
        syncState = .syncFailure
        DispatchQueue.main.async {
            XWHUDManager.showErrorTipHUD(error.localizedDescription)
        }
        return []
    }
}
```

- [ ] **Step 5: Update all SAVE/repair call sites**

Update each existing SAVE/repair EFC sync creation to pass `.saveConfiguration(...)`:

```swift
SyncDevicesViewController(
    type: .emergencyFire(
        data: savedDevice,
        items: nil,
        context: .saveConfiguration(
            persistsSyncResult: true,
            changedFromConfiguration: viewModel.lastSavedConfigurationChange?.old
        )
    )
)
```

Use `changedFromConfiguration: nil` for repair, manual sync, bind-after-sync, and any existing `persistsSyncResult: true` EFC sync entry.

- [ ] **Step 6: Update the Delete call site**

In the shared EFC delete helper, use:

```swift
let controller = SyncDevicesViewController(
    type: .emergencyFire(
        data: device,
        items: cleanupItems,
        context: .deleteCleanup
    )
)
```

- [ ] **Step 7: Update pattern matches that read `persistsSyncResult`**

Replace all EFC pattern matches like:

```swift
guard case .emergencyFire(_, _, let persistsSyncResult, _) = type
```

with:

```swift
guard case .emergencyFire(_, _, let context) = type
let persistsSyncResult = context.persistsSyncResult
```

For delete-only checks, use:

```swift
guard case .emergencyFire(_, _, let context) = type,
      context.isDeleteCleanup,
      let taskContext = emergencyFireControllerTask(for: model) else {
    return false
}
```

- [ ] **Step 8: Compile-check references**

Run:

```bash
rg -n "emergencyFire\\(data:.*persistsSyncResult|case \\.emergencyFire\\([^\\n]*persistsSyncResult|changedFromConfiguration:" SunSmart/Main
```

Expected: only `.saveConfiguration(... changedFromConfiguration: ...)` usages remain; no old four-parameter `SyncType.emergencyFire` construction remains.

- [ ] **Step 9: Commit Task 1**

```bash
git add SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift
git commit -m "feat: add EFC sync context"
```

## Task 2: Make Delete Cleanup Planner Delete-Only

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`

- [ ] **Step 1: Reuse existing group metadata**

Use the existing `EmergencyFireControllerSyncTask.pendingGroupAddress` to identify which associated group a Delete cleanup task belongs to. Do not add a new task property for this work.

- [ ] **Step 2: Replace `makeDeleteCleanupItems()` behavior**

Change `makeDeleteCleanupItems()` so it never calls `makeDisableControllerItems()`. The method should:

```swift
func makeDeleteCleanupItems() -> [EmergencyFireControllerSyncItem] {
    guard let publishGroup = data.publishGroup else {
        return []
    }

    let addresses = Set(
        data.configuration.powerLossSettings.associateGroupAddresses +
        data.configuration.powerLossSettings.pendingUnassociateGroupAddresses +
        data.configuration.fireAlarmSettings.associateGroupAddresses +
        data.configuration.fireAlarmSettings.pendingUnassociateGroupAddresses
    )

    return addresses.sorted().map { address in
        makeDeleteCleanupItem(groupAddress: address, publishGroup: publishGroup)
    }
}
```

- [ ] **Step 3: Add group-level Delete cleanup item factory**

Add:

```swift
private func makeDeleteCleanupItem(groupAddress: Address, publishGroup: Group) -> EmergencyFireControllerSyncItem {
    guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress)) else {
        let task = EmergencyFireControllerSyncTask(
            title: "Group Cleanup",
            kind: .deleteCleanup,
            address: groupAddress,
            messageHandles: [],
            isUnsupported: true,
            pendingGroupAddress: groupAddress
        )
        return EmergencyFireControllerSyncItem(name: String(format: "%04X", groupAddress), iconName: "device_light", address: groupAddress, tasks: [task], controller: data)
    }

    let tasks = group.nodes.map { node -> EmergencyFireControllerSyncTask in
        guard node.state, node.isKeybindComplete else {
            return EmergencyFireControllerSyncTask(
                title: node.name ?? group.name,
                kind: .deleteCleanup,
                address: node.primaryUnicastAddress,
                messageHandles: [],
                isUnsupported: true,
                pendingGroupAddress: groupAddress
            )
        }
        let handles = makeDeleteCleanupMessageHandles(node: node, publishGroup: publishGroup)
        return EmergencyFireControllerSyncTask(
            title: node.name ?? group.name,
            kind: .deleteCleanup,
            address: node.primaryUnicastAddress,
            messageHandles: handles,
            isUnsupported: handles.isEmpty,
            pendingGroupAddress: groupAddress
        )
    }

    return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks, controller: data)
}
```

This makes offline, unbound, missing-model, or already-unreachable group members visible as failed tasks instead of silently skipping the group.

- [ ] **Step 4: Keep existing normal cleanup behavior unchanged**

Do not change `makeCleanupItems()` or `makeAssociationCleanupTasks(...)` for normal SAVE/repair context. Those methods still handle pending unassociate cleanup outside Delete.

- [ ] **Step 5: Verify planner text**

Run:

```bash
rg -n "makeDeleteCleanupItems|makeDisableControllerItems|SunricherVendorSet\\(function: \\.emergencyEnabled|ConfigModelSubscriptionAdd|ConfigModelSubscriptionDelete" SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift
```

Expected:
- `makeDeleteCleanupItems()` no longer references `makeDisableControllerItems()`.
- `SunricherVendorSet(function: .emergencyEnabled(false))` remains only inside `makeDisableControllerItems()`.
- Delete cleanup generation uses `ConfigModelSubscriptionDelete` through `makeDeleteCleanupMessageHandles(...)`.

- [ ] **Step 6: Commit Task 2**

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift
git commit -m "feat: make EFC delete cleanup subscription-only"
```

## Task 3: Persist Delete Cleanup Progress and Failure Immediately

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Add progress persistence helpers**

In `DeviceEmerFireData+Sync.swift`, add:

```swift
func markDeleteCleanupSucceeded(groupAddress: Address, meshUUID: String, subnetworkId: String) {
    configuration.powerLossSettings.associateGroupAddresses.removeAll { $0 == groupAddress }
    configuration.fireAlarmSettings.associateGroupAddresses.removeAll { $0 == groupAddress }
    configuration.powerLossSettings.pendingUnassociateGroupAddresses.removeAll { $0 == groupAddress }
    configuration.fireAlarmSettings.pendingUnassociateGroupAddresses.removeAll { $0 == groupAddress }
    isSynced = true
    save(meshUUID: meshUUID, networkId: subnetworkId)
}

func markDeleteCleanupInterrupted(meshUUID: String, subnetworkId: String) {
    isSynced = false
    save(meshUUID: meshUUID, networkId: subnetworkId)
}
```

The successful helper sets `isSynced = true` because the remaining configuration after a fully cleared group is internally consistent. If later groups fail, the failure helper sets `isSynced = false`.

- [ ] **Step 2: Add context helper in SyncDevicesViewController**

Add:

```swift
private var emergencyFireSyncContext: EmergencyFireSyncContext? {
    guard case .emergencyFire(_, _, let context) = type else {
        return nil
    }
    return context
}
```

- [ ] **Step 3: Track group success after each model finishes**

Add:

```swift
private func persistEmergencyFireDeleteCleanupProgressIfNeeded(for model: SyncCellModel) {
    guard emergencyFireSyncContext?.isDeleteCleanup == true,
          let taskContext = emergencyFireControllerTask(for: model),
          let groupAddress = taskContext.task.pendingGroupAddress else {
        return
    }
    guard let groupModel = (model as? SyncDevicesModel)?.parentGroupModel
        ?? (model as? SyncDeviceStepTaskModel)?.parentStepModel?.parentDeviceModel?.parentGroupModel else {
        return
    }
    let allGroupModels = groupModel.deviceModels
    let allFinished = allGroupModels.allSatisfy { deviceModel in
        if let operationType = deviceModel.operationType,
           case .configuration(_, let type) = operationType,
           case .emergencyFireController = type {
            return deviceModel.state == .successful
        }
        return deviceModel.steps.flatMap { $0.tasks }.allSatisfy { $0.state == .successful }
    }
    guard allFinished else {
        return
    }
    taskContext.data.markDeleteCleanupSucceeded(
        groupAddress: groupAddress,
        meshUUID: taskContext.data.meshUUID,
        subnetworkId: taskContext.data.meshNetworkId
    )
}
```

- [ ] **Step 4: Call progress persistence on task success**

After `model.state = .successful` and `clearEmergencyFireControllerPendingIfNeeded(for: model)`, call:

```swift
self.persistEmergencyFireDeleteCleanupProgressIfNeeded(for: model)
```

Also call the same helper after `completeEmptyEmergencyFireControllerTaskIfNeeded(...)` marks a delete cleanup task successful, but only if the task is not unsupported.

- [ ] **Step 5: Persist failure on Stop**

In `rightItemAction()` when `syncState == .inSync`, after setting unfinished models to failed and before `finishEmergencyFireControllerSyncIfNeeded(success: false)`, call:

```swift
persistEmergencyFireDeleteCleanupFailureIfNeeded()
```

Add:

```swift
private func persistEmergencyFireDeleteCleanupFailureIfNeeded() {
    guard emergencyFireSyncContext?.isDeleteCleanup == true,
          case .emergencyFire(let data, _, _) = type else {
        return
    }
    data.markDeleteCleanupInterrupted(meshUUID: data.meshUUID, subnetworkId: data.meshNetworkId)
}
```

- [ ] **Step 6: Persist failure after sync finishes with failed tasks**

In the end of `startSync()`, immediately before or after `finishEmergencyFireControllerSyncIfNeeded(success:)`, add:

```swift
if self.syncState == .syncFailure {
    self.persistEmergencyFireDeleteCleanupFailureIfNeeded()
}
```

This covers failures without requiring the user to tap Back.

- [ ] **Step 7: Keep SAVE result persistence unchanged**

Ensure `finishEmergencyFireControllerSyncIfNeeded(success:)` still saves `data.isSynced = success` only for `context.persistsSyncResult == true`. Delete failure is handled by the explicit helper above.

- [ ] **Step 8: Commit Task 3**

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: persist EFC delete cleanup progress"
```

## Task 4: Route Delete Entry Through Delete Context and Reset Correctly

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`

- [ ] **Step 1: Add an associate group check**

In the shared delete helper, before creating `SyncDevicesViewController`, compute:

```swift
let hasAssociateGroups = !device.configuration.activeLightLCGroupAddresses.isEmpty ||
    device.configuration.hasPendingCleanup
```

- [ ] **Step 2: Skip Sync when there are no groups to clean**

If `hasAssociateGroups == false`, call:

```swift
deleteEmergencyFireControllerNodeAndCache(device, space: space, completion: completion)
return
```

Do this before any mesh connectivity guard for cleanup, because no cleanup messages are needed.

- [ ] **Step 3: Use Delete context and supplied cleanup items**

Build cleanup items with `planner.makeDeleteCleanupItems()`. If the returned items are empty, go directly to Reset:

```swift
let cleanupItems = planner.makeDeleteCleanupItems()
guard !cleanupItems.isEmpty else {
    deleteEmergencyFireControllerNodeAndCache(device, space: space, completion: completion)
    return
}
let controller = SyncDevicesViewController(
    type: .emergencyFire(
        data: device,
        items: cleanupItems,
        context: .deleteCleanup
    )
)
```

- [ ] **Step 4: Keep mesh connectivity guard only for sendable cleanup**

Use:

```swift
let needsMeshSync = cleanupItems.flatMap { $0.tasks }.contains { !$0.messageHandles.isEmpty }
if needsMeshSync {
    guard MeshLibManager.manager.isMeshNetworkConnected else {
        XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
        device.markDeleteCleanupInterrupted(meshUUID: device.meshUUID, subnetworkId: device.meshNetworkId)
        return
    }
}
```

If cleanup items exist but all are unsupported/no handles, present the sync page so the user sees failures instead of silently resetting.

- [ ] **Step 5: After Delete sync success, clear remaining groups and Reset**

In `syncSuccessCallback`, before `deleteEmergencyFireControllerNodeAndCache(...)`, ensure all associate and pending cleanup groups are empty and save:

```swift
device.configuration.powerLossSettings.associateGroupAddresses.removeAll()
device.configuration.fireAlarmSettings.associateGroupAddresses.removeAll()
device.configuration.powerLossSettings.pendingUnassociateGroupAddresses.removeAll()
device.configuration.fireAlarmSettings.pendingUnassociateGroupAddresses.removeAll()
device.isSynced = true
DeviceEmerFireStore.shared.save(device)
```

This makes Reset CANCEL leave a retained EFC with empty associate groups and no false sync issue.

- [ ] **Step 6: Keep Others page delegated to the shared helper**

Confirm `DeviceOthersViewController.confirmDeleteEmergencyFireController(_:)` only calls:

```swift
confirmDeleteEmergencyFireControllerDevice(
    device,
    space: space,
    presentsSyncModally: true,
    preferredContentSize: isIPad ? iPadPreferredContentSize : nil
) { [weak self] in
    self?.finishDeleteOthersItem()
}
```

- [ ] **Step 7: Commit Task 4**

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
git commit -m "feat: route EFC delete cleanup context"
```

## Task 5: Add Contract Guards

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add SyncType context assertions**

Add assertions:

```bash
assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "enum EmergencyFireSyncContext" \
  "EFC sync must distinguish SAVE and Delete contexts."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "case deleteCleanup" \
  "EFC Delete sync must have an explicit delete cleanup context."

assert_contains "SunSmart/Main/Space/Controller/SyncDevicesViewController.swift" \
  "context.isDeleteCleanup" \
  "EFC Delete sync retry must remain delete-only."
```

- [ ] **Step 2: Add planner delete-only assertions**

Add assertions:

```bash
assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "var items = makeDisableControllerItems()" \
  "EFC Delete cleanup must not send controller disable tasks."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "items.append(contentsOf: makeDisableControllerItems())" \
  "EFC Delete cleanup must not include controller body tasks."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "ConfigModelSubscriptionDelete" \
  "EFC Delete cleanup must clear group subscriptions."
```

- [ ] **Step 3: Add progress persistence assertions**

Add assertions:

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift" \
  "markDeleteCleanupInterrupted" \
  "EFC Delete cleanup failures must be persisted immediately."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift" \
  "markDeleteCleanupSucceeded" \
  "EFC Delete cleanup successful groups must be removed from associate groups."
```

- [ ] **Step 4: Run contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: all assertions pass.

- [ ] **Step 5: Commit Task 5**

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: guard EFC delete cleanup sync"
```

## Task 6: Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Check old API removal**

Run:

```bash
rg -n "emergencyFire\\(data:.*persistsSyncResult|case \\.emergencyFire\\([^\\n]*persistsSyncResult" SunSmart/Main
```

Expected: no output.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Run contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: all assertions pass.

- [ ] **Step 4: Build iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Final status review**

Run:

```bash
git status --short
```

Expected: only unrelated pre-existing files remain modified or untracked.

## Self-Review

- Spec coverage: The plan covers SAVE full sync, Delete subscription-only cleanup, Delete Stop/partial failure immediate persistence, Delete retry staying delete-only, empty associate groups direct Reset, Reset CANCEL/FORCE DELETE outcomes, and contract/build verification.
- Placeholder scan: This plan intentionally avoids unresolved placeholder markers and gives exact target files, command lines, and expected outputs.
- Type consistency: The plan consistently uses `EmergencyFireSyncContext`, `.saveConfiguration`, `.deleteCleanup`, `markDeleteCleanupSucceeded`, and `markDeleteCleanupInterrupted`.
