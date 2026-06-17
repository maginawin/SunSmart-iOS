# EFC Associated Group Subscription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 EFC associated group 设备订阅改为固定候选 Model 集合，并且只对设备实际拥有的 Model 订阅 EFC Group。

**Architecture:** 订阅规划仍集中在 `EmergencyFireControllerSyncPlanner`，不修改 UI、云 schema 或普通 group SDK 全局订阅集合。Planner 用固定候选 Model ID 集合收集每个节点实际拥有的 Model 实例，生成通用 group subscription task；清理只在取消关联、成员退出或删除 EFC 时发生，Scene Server 仅保留历史清理。

**Tech Stack:** Swift, UIKit sync flow, NordicSigMeshSDK, existing EFC sync planner, Bash contract script, iPhoneOS `xcodebuild`.

---

## File Structure

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
  - owning file。定义 EFC associated group 候选订阅 Model ID，按节点实际拥有的 Model 生成 add/delete handles，移除 action type 驱动的 Light LC 增删。
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
  - 增加通用 subscription task kind，用于所有 EFC Group Model 订阅任务。
- `scripts/check_efc_controller_flows.sh`
  - 增加静态 contract，防止恢复旧逻辑：不能再用 `restoreSettings.actionType == .restoreAuto` 控制 Light LC 订阅，必须存在固定候选 Model 集合和实际 Model 收集逻辑。
- `docs/260618_1031_efc_associated_group_subscription_design.md`
  - 已确认设计，不再修改，作为本计划依据。

## Task 1: Add Generic EFC Group Subscription Task Kind

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`

- [ ] **Step 1: Add the task kind**

在 `EmergencyFireControllerSyncTaskKind` 中保留现有 `lightnessSubscription` / `lightLCSubscription` 以免影响旧状态显示，同时新增通用类型：

```swift
case associationSubscription = "Group Subscription"
```

放在现有 `lightLCSubscription` 后面：

```swift
case lightnessSubscription = "Lightness Group"
case lightLCSubscription = "LC Group"
case associationSubscription = "Group Subscription"
case associationCleanup = "Group Cleanup"
```

Expected: 后续 planner 可以用一个 task kind 表示 `0x1000/0x1300/0x1303/0x1306/0x1307/0x130F` 中任意实际存在的 Model 订阅。

- [ ] **Step 2: Commit task kind**

Run:

```bash
git diff --check -- SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift
git commit -m "feat: add EFC group subscription task kind"
```

Expected: commit 只包含 `EmergencyFireControllerSyncPlan.swift`。

## Task 2: Refactor Planner Subscription Add Path

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`

- [ ] **Step 1: Define fixed candidate Model IDs**

在 `EmergencyFireControllerSyncPlanner` 内靠近 stored properties 的位置新增：

```swift
private static let associatedGroupSubscriptionModelIDs: [UInt16] = [
    .genericOnOffServerModelId,
    .lightLightnessServerModelId,
    .lightCTLServerModelId,
    .lightCTLTemperatureServerModelId,
    .lightHSLServerModelId,
    .lightLCServerModelId
]
```

Expected: 这是 EFC desired subscription 的唯一候选集合，不读取 EFC action type。

- [ ] **Step 2: Add actual-model collector**

在 planner helper 区新增：

```swift
private func associatedGroupSubscriptionModels(for node: Node) -> [Model] {
    Self.associatedGroupSubscriptionModelIDs.flatMap { modelID in
        node.getFunctionModels(modelId: modelID)
    }
}
```

Expected: 候选集合按设备 composition 过滤；设备没有的 Model 不生成任务。使用 `getFunctionModels(modelId:)` 而不是单数 getter，避免多 element 设备漏掉实际存在的 model 实例。

- [ ] **Step 3: Replace action-type based associate logic**

用下面实现替换 `makeAssociateTasks(node:group:publishGroup:)`：

```swift
func makeAssociateTasks(
    node: Node,
    group: Group,
    publishGroup: Group
) -> [EmergencyFireControllerSyncTask] {
    var tasks = makeAssociationSubscriptionTasks(node: node, group: group, publishGroup: publishGroup)
    if let cleanupTask = makeHistoricalSubscriptionCleanupTask(node: node, group: group, publishGroup: publishGroup) {
        tasks.append(cleanupTask)
    }
    return tasks
}
```

Expected: 这里不再出现 `restoreSettings.actionType == .restoreAuto`，也不再因为非 AUTO 生成 Light LC cleanup。

- [ ] **Step 4: Add subscription task builder**

新增 helper：

```swift
private func makeAssociationSubscriptionTasks(
    node: Node,
    group: Group,
    publishGroup: Group
) -> [EmergencyFireControllerSyncTask] {
    associatedGroupSubscriptionModels(for: node).compactMap { model in
        guard !model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionAdd(group: publishGroup, to: model) else {
            return nil
        }
        let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
        handle.continuous = false
        return EmergencyFireControllerSyncTask(
            title: node.name ?? group.name,
            kind: .associationSubscription,
            address: node.primaryUnicastAddress,
            messageHandles: [handle]
        )
    }
}
```

Expected: 每个实际拥有且未订阅的 Model 生成一个 task；设备没有的 Model 不会创建 task 或 sync row。

- [ ] **Step 5: Remove obsolete add helpers**

删除以下 helper：

```swift
private func makeLightnessSubscriptionTask(...)
private func makeLightLCSubscriptionTask(...)
private func makeNonAutoRestoreCleanupTask(...)
```

保留 `makeHistoricalSubscriptionCleanupTask(...)`，它只清 Scene Server 历史订阅。

Expected: Planner 的 add path 只使用 fixed candidate set + actual-model collector，文件中不再存在上述三个 helper 名称。

- [ ] **Step 6: Compile check for planner file**

Run:

```bash
git diff --check -- SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift
```

Expected: no output.

## Task 3: Refactor Cleanup Path

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`

- [ ] **Step 1: Replace boolean cleanup selector with fixed desired cleanup**

替换 `makeCleanupMessageHandles(node:publishGroup:includeLightness:includeLightLC:includeScene:)` 的调用结构。保留一个清 fixed desired models 的 helper：

```swift
private func makeAssociationCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
    associatedGroupSubscriptionModels(for: node).compactMap { model in
        guard model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionDelete(group: publishGroup, from: model) else {
            return nil
        }
        let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
        handle.continuous = false
        return handle
    }
}
```

Expected: 清理集合与新增集合一致，并且只清设备实际拥有且当前已订阅的 Model。

- [ ] **Step 2: Keep Scene Server historical cleanup separate**

新增独立 helper：

```swift
private func makeHistoricalSceneCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
    guard let model = node.sceneModel,
          model.isSubscribed(to: publishGroup),
          let elementAddress = model.parentElement?.unicastAddress,
          model.companyIdentifier == nil,
          let message = ConfigModelSubscriptionDelete(parameters: Data() + elementAddress + publishGroup.address.address + UInt16(model.modelIdentifier)) else {
        return []
    }
    let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
    handle.continuous = false
    return [handle]
}
```

Expected: Scene Server 不再是 desired subscription，只作为历史清理。

- [ ] **Step 3: Update cleanup callers**

将 `makeAssociationCleanupTasks(...)` 中的 handles 改为：

```swift
let handles = makeAssociationCleanupMessageHandles(node: node, publishGroup: publishGroup) +
    makeHistoricalSceneCleanupMessageHandles(node: node, publishGroup: publishGroup)
```

将 `makeDeleteCleanupMessageHandles(node:publishGroup:)` 改为：

```swift
makeAssociationCleanupMessageHandles(node: node, publishGroup: publishGroup) +
    makeHistoricalSceneCleanupMessageHandles(node: node, publishGroup: publishGroup)
```

将 `makeHistoricalSubscriptionCleanupTask(...)` 中的 handles 改为只调用：

```swift
let handles = makeHistoricalSceneCleanupMessageHandles(node: node, publishGroup: publishGroup)
```

Expected: 普通 SAVE 改功能类型不会清 Light LC；取消关联、成员退出、删除 EFC 会清 fixed desired models；Scene Server 只做历史清理。

- [ ] **Step 4: Remove obsolete cleanup helper**

删除旧的 `makeCleanupMessageHandles(node:publishGroup:includeLightness:includeLightLC:includeScene:)`。

Expected: 文件中不再存在 `includeLightness`、`includeLightLC`、`includeScene` 参数。

- [ ] **Step 5: Commit planner refactor**

Run:

```bash
git diff --check -- SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift
git commit -m "feat: stabilize EFC group subscriptions"
```

Expected: commit 只包含 `EmergencyFireControllerSyncPlanner.swift`。

## Task 4: Add Contract Guard

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add positive contracts**

在 EFC sync planner 相关断言附近追加：

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "associatedGroupSubscriptionModelIDs" \
  "EFC associated group subscription must use a fixed candidate model set."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "node.getFunctionModels(modelId: modelID)" \
  "EFC associated group subscription must only create tasks for models the node actually owns."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift" \
  "case associationSubscription = \"Group Subscription\"" \
  "EFC associated group subscription tasks must use the generic subscription task kind."
```

Expected: contracts verify fixed set, actual-model filtering, and generic task kind.

- [ ] **Step 2: Add negative contracts**

追加：

```bash
assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "restoreSettings.actionType == .restoreAuto" \
  "EFC group subscriptions must not depend on Restore AUTO."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "makeNonAutoRestoreCleanupTask" \
  "EFC must not clean Light LC subscriptions just because Event Ends is not Restore AUTO."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift" \
  "includeLightLC" \
  "EFC cleanup must not use action-type-specific Light LC cleanup flags."
```

Expected: future regressions that rebind subscription behavior to action type fail the script.

- [ ] **Step 3: Run contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 4: Commit contract guard**

Run:

```bash
git diff --check -- scripts/check_efc_controller_flows.sh
git add scripts/check_efc_controller_flows.sh
git commit -m "test: guard EFC subscription model policy"
```

Expected: commit only includes `scripts/check_efc_controller_flows.sh`.

## Task 5: Final Verification

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
- Verify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Verify no unrelated files are staged**

Run:

```bash
git status --short
```

Expected: no staged files. Pre-existing unrelated modified files may still appear unstaged; do not stage them.

- [ ] **Step 2: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Run EFC contract**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
EFC controller flow contracts passed.
```

- [ ] **Step 4: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Review final behavior**

Inspect `EmergencyFireControllerSyncPlanner.swift` and confirm these facts:

- `makeAssociateTasks` no longer checks `restoreSettings.actionType`.
- `associatedGroupSubscriptionModelIDs` contains exactly `0x1000/0x1300/0x1303/0x1306/0x1307/0x130F` through the named constants.
- add tasks use `node.getFunctionModels(modelId: modelID)` so only actual models create tasks.
- cleanup for group removal/deletion uses the same actual-model collection.
- Scene Server cleanup is historical only and is not part of the desired subscription add path.

Expected: all five facts are true before reporting completion.
