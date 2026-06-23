# EFC LINK Sync Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复虚拟 EFC LINK 真实 EFC 后的同步闭环：空组不制造待同步状态，真实组在 LINK 阶段完成组订阅下发，成功后不再显示需要同步。

**Architecture:** 在 Classic / Professional Add Device 的 EFC append 阶段新增 linked associated group subscription 追踪，并把 EFC LINK 的 synced 判定从单一 controller 默认配置扩展为 controller 配置与 linked group subscription 两部分。`LinkedEmerFireEditVC` 的正常 LINK 回调只刷新页面状态，不再跳转同步页。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 `MeshMessageHandle` append callback、现有 shell contract 脚本、iPhoneOS `xcodebuild`。

---

## File Structure

- 当前工作区已有未提交改动。执行本计划时，开始前必须运行 `git status --short`；如果某个任务要修改的文件在任务开始前已经是 dirty 状态，不要在该任务内提交该文件，除非先人工确认 diff 只包含本任务变更。后续实现可以先完成代码与验证，最终由用户决定如何处理这些已有改动。
- Modify: `scripts/check_efc_controller_flows.sh`
  - 增加 contract，先表达 EFC LINK 必须有 linked associated group subscription helper、Classic/Professional 都调用该 helper、LINK 成功回调不再调用 `openSyncAfterLinkedDeviceIfNeeded()`。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 新增 EFC LINK group subscription handle 追踪。
  - 新增 `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(...)`。
  - 调整 `finishEmergencyFireDefaultConfiguration(for:)` 为 LINK 闭环 synced 判定。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 与 Classic 保持同构实现，避免两条 Add Device 模式行为漂移。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
  - 正常 LINK 成功后只刷新状态和通知，不再自动打开 Sync 页面；保留 `openSyncAfterLinkedDeviceIfNeeded()` 符号作为兜底入口，避免与既有 contract 冲突。

## Task 1: Contract First

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add failing contract assertions**

Insert the following assertions near the existing EFC LINK assertions, after the check for `openSyncAfterLinkedDeviceIfNeeded()`:

```bash
assert_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)" \
  "Classic EFC LINK must append associated group subscription messages during Add Device."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)" \
  "Professional EFC LINK must append associated group subscription messages during Add Device."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift" \
  "finishLinkedEmergencyFireControllerConfiguration(for: node)" \
  "Classic EFC LINK must finish controller and associated group sync state together."

assert_contains "SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift" \
  "finishLinkedEmergencyFireControllerConfiguration(for: node)" \
  "Professional EFC LINK must finish controller and associated group sync state together."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift" \
  "self?.openSyncAfterLinkedDeviceIfNeeded()" \
  "EFC LINK success must not immediately open the EFC sync page."
```

- [ ] **Step 2: Run contract to verify it fails**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL on at least the new `appendLinkedEmergencyFireControllerGroupSubscriptionMessages(...)` assertion before implementation.

- [ ] **Step 3: Commit contract when safe**

Run:

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: add EFC link sync contract"
```

Expected: commit includes only `scripts/check_efc_controller_flows.sh`. If this file had pre-existing uncommitted changes before Task 1, skip this commit and leave the task changes unstaged until final review.

## Task 2: Classic Add Device EFC LINK Sync

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: Add linked group tracking storage**

Near the existing EFC tracking properties:

```swift
private var emergencyFireDefaultConfigurationMessageHandles: [Address: [MeshMessageHandle]] = [:]
private var failedEmergencyFireDefaultConfigurationNodeAddresses: Set<Address> = []
private var emergencyFireGroupMutationMessageHandles: [Address: [MeshMessageHandle]] = [:]
private var failedEmergencyFireGroupMutationNodeAddresses: Set<Address> = []
```

add:

```swift
private var linkedEmergencyFireGroupSubscriptionMessageHandles: [Address: [MeshMessageHandle]] = [:]
private var failedLinkedEmergencyFireGroupSubscriptionNodeAddresses: Set<Address> = []
```

- [ ] **Step 2: Clear linked tracking when scan state resets**

Find the same reset block that clears `emergencyFireDefaultConfigurationMessageHandles` and `emergencyFireGroupMutationMessageHandles`; add:

```swift
linkedEmergencyFireGroupSubscriptionMessageHandles.removeAll()
failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.removeAll()
```

- [ ] **Step 3: Add helper to append linked group subscription messages**

Add this helper near `appendEmergencyFireControllerDefaultConfigurationMessages(...)`:

```swift
private func appendLinkedEmergencyFireControllerGroupSubscriptionMessages(
    controller: DeviceEmerFireData,
    appendMessages: inout [MeshMessageHandle]
) {
    guard bindToEmerFire != nil,
          let nodeAddress = controller.bindNodeAddress,
          let publishGroupAddress = try? controller.ensurePublishGroup(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
          let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)) else {
        return
    }

    let planner = EmergencyFireControllerSyncPlanner(
        data: controller,
        meshUUID: space.meshUUID,
        subnetworkId: space.meshNetworkId
    )
    let handles = controller.configuration.activeLightLCGroupAddresses.sorted().flatMap { groupAddress -> [MeshMessageHandle] in
        guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress)) else {
            return []
        }
        return group.nodes.flatMap { node in
            planner.makeAssociateTasks(node: node, group: group, publishGroup: publishGroup)
                .flatMap { $0.messageHandles }
        }
    }

    guard !handles.isEmpty else {
        return
    }
    appendMessages.append(contentsOf: handles)
    linkedEmergencyFireGroupSubscriptionMessageHandles[nodeAddress, default: []].append(contentsOf: handles)
    failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.remove(nodeAddress)
}
```

- [ ] **Step 4: Add lookup helper for linked group subscription failures**

Add this helper near `emergencyFireDefaultConfigurationNodeAddress(containing:)`:

```swift
private func linkedEmergencyFireGroupSubscriptionNodeAddress(containing messageHandle: MeshMessageHandle) -> Address? {
    linkedEmergencyFireGroupSubscriptionMessageHandles.first { _, handles in
        handles.contains { $0 === messageHandle }
    }?.key
}
```

- [ ] **Step 5: Replace finish helper**

Replace the body of `finishEmergencyFireDefaultConfiguration(for:)` with a new helper named `finishLinkedEmergencyFireControllerConfiguration(for:)`:

```swift
private func finishLinkedEmergencyFireControllerConfiguration(for node: Node) {
    let hadDefaultConfiguration = emergencyFireDefaultConfigurationMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
    let hadLinkedGroupSubscription = linkedEmergencyFireGroupSubscriptionMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
    guard hadDefaultConfiguration || hadLinkedGroupSubscription,
          let controller = DeviceEmerFireStore.shared.devices(in: space).first(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) else {
        return
    }

    let defaultConfigurationFailed = failedEmergencyFireDefaultConfigurationNodeAddresses.contains(node.primaryUnicastAddress)
    let linkedGroupSubscriptionFailed = failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.contains(node.primaryUnicastAddress)
    failedEmergencyFireDefaultConfigurationNodeAddresses.remove(node.primaryUnicastAddress)
    failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.remove(node.primaryUnicastAddress)

    controller.isSynced = hadDefaultConfiguration && !defaultConfigurationFailed && !linkedGroupSubscriptionFailed
    DeviceEmerFireStore.shared.save(controller)
}
```

Then replace all Classic calls to:

```swift
self.finishEmergencyFireDefaultConfiguration(for: node)
```

with:

```swift
self.finishLinkedEmergencyFireControllerConfiguration(for: node)
```

- [ ] **Step 6: Append linked group subscriptions in EFC branch**

In the `.emergencyController` append branch, after:

```swift
appendEmergencyFireControllerDefaultConfigurationMessages(controller: controller, appendMessages: &appendMessages)
```

add:

```swift
appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)
```

- [ ] **Step 7: Track linked group subscription failures**

In `appendMessageFailedBack`, after the existing default configuration failure tracking:

```swift
if let nodeAddress = self.emergencyFireDefaultConfigurationNodeAddress(containing: messageHandle) {
    self.failedEmergencyFireDefaultConfigurationNodeAddresses.insert(nodeAddress)
}
```

add:

```swift
if let nodeAddress = self.linkedEmergencyFireGroupSubscriptionNodeAddress(containing: messageHandle) {
    self.failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.insert(nodeAddress)
}
```

- [ ] **Step 8: Run contract and expect Professional assertions still fail**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: Classic assertions pass; Professional assertions still fail until Task 3.

- [ ] **Step 9: Commit Classic implementation when safe**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
git commit -m "fix: sync EFC link groups in classic add"
```

Expected: commit includes only `DeviceAddClassicModeController.swift`. If this file had pre-existing uncommitted changes before Task 2, skip this commit and leave the task changes unstaged until final review.

## Task 3: Professional Add Device EFC LINK Sync

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Apply the same tracking storage**

Near the existing EFC tracking properties, add:

```swift
private var linkedEmergencyFireGroupSubscriptionMessageHandles: [Address: [MeshMessageHandle]] = [:]
private var failedLinkedEmergencyFireGroupSubscriptionNodeAddresses: Set<Address> = []
```

- [ ] **Step 2: Clear linked tracking when scan state resets**

In the reset block that clears EFC tracking dictionaries, add:

```swift
linkedEmergencyFireGroupSubscriptionMessageHandles.removeAll()
failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.removeAll()
```

- [ ] **Step 3: Add linked group subscription append helper**

Add the same helper used in Classic near `appendEmergencyFireControllerDefaultConfigurationMessages(...)`:

```swift
private func appendLinkedEmergencyFireControllerGroupSubscriptionMessages(
    controller: DeviceEmerFireData,
    appendMessages: inout [MeshMessageHandle]
) {
    guard bindToEmerFire != nil,
          let nodeAddress = controller.bindNodeAddress,
          let publishGroupAddress = try? controller.ensurePublishGroup(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
          let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)) else {
        return
    }

    let planner = EmergencyFireControllerSyncPlanner(
        data: controller,
        meshUUID: space.meshUUID,
        subnetworkId: space.meshNetworkId
    )
    let handles = controller.configuration.activeLightLCGroupAddresses.sorted().flatMap { groupAddress -> [MeshMessageHandle] in
        guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress)) else {
            return []
        }
        return group.nodes.flatMap { node in
            planner.makeAssociateTasks(node: node, group: group, publishGroup: publishGroup)
                .flatMap { $0.messageHandles }
        }
    }

    guard !handles.isEmpty else {
        return
    }
    appendMessages.append(contentsOf: handles)
    linkedEmergencyFireGroupSubscriptionMessageHandles[nodeAddress, default: []].append(contentsOf: handles)
    failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.remove(nodeAddress)
}
```

- [ ] **Step 4: Add lookup helper**

Add:

```swift
private func linkedEmergencyFireGroupSubscriptionNodeAddress(containing messageHandle: MeshMessageHandle) -> Address? {
    linkedEmergencyFireGroupSubscriptionMessageHandles.first { _, handles in
        handles.contains { $0 === messageHandle }
    }?.key
}
```

- [ ] **Step 5: Replace finish helper**

Replace `finishEmergencyFireDefaultConfiguration(for:)` with:

```swift
private func finishLinkedEmergencyFireControllerConfiguration(for node: Node) {
    let hadDefaultConfiguration = emergencyFireDefaultConfigurationMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
    let hadLinkedGroupSubscription = linkedEmergencyFireGroupSubscriptionMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
    guard hadDefaultConfiguration || hadLinkedGroupSubscription,
          let controller = DeviceEmerFireStore.shared.devices(in: space).first(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) else {
        return
    }

    let defaultConfigurationFailed = failedEmergencyFireDefaultConfigurationNodeAddresses.contains(node.primaryUnicastAddress)
    let linkedGroupSubscriptionFailed = failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.contains(node.primaryUnicastAddress)
    failedEmergencyFireDefaultConfigurationNodeAddresses.remove(node.primaryUnicastAddress)
    failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.remove(node.primaryUnicastAddress)

    controller.isSynced = hadDefaultConfiguration && !defaultConfigurationFailed && !linkedGroupSubscriptionFailed
    DeviceEmerFireStore.shared.save(controller)
}
```

Then replace all Professional calls to:

```swift
self.finishEmergencyFireDefaultConfiguration(for: node)
```

with:

```swift
self.finishLinkedEmergencyFireControllerConfiguration(for: node)
```

- [ ] **Step 6: Append linked group subscriptions**

In the Professional `.emergencyController` append branch, after:

```swift
appendEmergencyFireControllerDefaultConfigurationMessages(controller: controller, appendMessages: &appendMessages)
```

add:

```swift
appendLinkedEmergencyFireControllerGroupSubscriptionMessages(controller: controller, appendMessages: &appendMessages)
```

- [ ] **Step 7: Track failures**

In `appendMessageFailedBack`, after default configuration failure tracking, add:

```swift
if let nodeAddress = self.linkedEmergencyFireGroupSubscriptionNodeAddress(containing: messageHandle) {
    self.failedLinkedEmergencyFireGroupSubscriptionNodeAddresses.insert(nodeAddress)
}
```

- [ ] **Step 8: Run contract and expect only LINK callback assertion to fail**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: Classic and Professional linked group assertions pass; `LinkedEmerFireEditVC` no-sync-page assertion still fails until Task 4.

- [ ] **Step 9: Commit Professional implementation when safe**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: sync EFC link groups in professional add"
```

Expected: commit includes only `DeviceAddProfessionalModeController.swift`. If this file had pre-existing uncommitted changes before Task 3, skip this commit and leave the task changes unstaged until final review.

## Task 4: Remove Normal LINK-to-Sync Jump

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`

- [ ] **Step 1: Replace LINK success dismiss callback**

Replace:

```swift
self.dismiss(animated: true) { [weak self] in
    self?.openSyncAfterLinkedDeviceIfNeeded()
}
```

with:

```swift
self.dismiss(animated: true)
```

- [ ] **Step 2: Keep fallback helper**

Keep `openSyncAfterLinkedDeviceIfNeeded()` in the file. Existing contract still checks the symbol, and the behavior change is only that normal LINK success no longer calls it.

- [ ] **Step 3: Run contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: `EFC controller flow contracts passed.`

- [ ] **Step 4: Commit LINK callback change when safe**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift
git commit -m "fix: keep EFC link on edit page"
```

Expected: commit includes only `LinkedEmerFireEditVC.swift`. If this file had pre-existing uncommitted changes before Task 4, skip this commit and leave the task changes unstaged until final review.

## Task 5: Verification

**Files:**
- Verify only, no planned edits.

- [ ] **Step 1: Run contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 2: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git status --short
git diff -- scripts/check_efc_controller_flows.sh SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift
```

Expected:

- Only the four planned files have new unstaged changes from implementation if commits were skipped.
- If task commits were made, `git status --short` may still show unrelated pre-existing local changes; do not revert or stage them.

- [ ] **Step 5: Final commit if implementation commits were skipped and target files are cleanly attributable**

If Tasks 1-4 were not committed individually, commit only the planned files:

```bash
git add scripts/check_efc_controller_flows.sh SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift
git commit -m "fix: complete EFC link sync"
```

Expected: commit contains only planned implementation files. If any planned file had pre-existing uncommitted changes, do not commit it without reviewing the complete file diff with the user.
