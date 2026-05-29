# Light Add Group Deferred Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 light 设备在 Site - Space 添加流程中自动加入 group 后，Profile、Scene、Schedule、Switch target 和其它 group 关联功能按 deferred sync 补发；补发失败时设备仍添加成功，但 group 进入需要同步状态。

**Architecture:** 新增一个无 UI 状态的 `DeviceGroupDeferredSyncPlanner`，负责把 `node.getSyncData(type: .group(group))` 拆成 append 阶段的 immediate handles 和添加成功后的 deferred tasks。Classic 和 Professional 添加页复用该 helper：append 阶段只发送入组/初始化等基础命令，add finish 前串行执行 deferred group sync，并在失败时更新 node/group 待同步状态。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 `MeshProxyMessageCommand` / `DeviceOperationType` / `NodeSyncData`。

**Implementation Note:** 新增 Swift 文件需要加入 `SunSmart.xcodeproj/project.pbxproj` 的 Sources；已同步加入 `SunSmart`、`Archipelago`、`SylSmart`、`SLG Sync Plus` 四个共享业务 target。实现时 append 阶段只对 light + group 使用 deferred planner；非 light 入组保留原有完整 group sync 行为。

---

## File Structure

- Create: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - 定义 `DeviceGroupDeferredSyncTask`。
  - 定义 `DeviceGroupDeferredSyncPlan`。
  - 定义 `DeviceGroupDeferredSyncPlanner.makePlan(node:group:)`。
  - 提供 `immediateMessageHandles` 和 deferred task 规划。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 增加 pending deferred plans 存储。
  - light + group append 阶段改用 planner 的 immediate handles。
  - add success 收集 deferred plan。
  - add finish 通知回调前执行 deferred plans。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 与 Classic 保持同样行为。
- Verify only: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - 本计划默认不修改 restore。只有实现中发现必须复用私有逻辑时，才抽 helper；抽出后 restore 行为必须保持一致。

## Task 1: Add DeviceGroupDeferredSyncPlanner

**Files:**
- Create: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Reference: `SunSmart/Common/Data/Node+SyncData.swift`
- Reference: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Create planner file with task and plan types**

Add the new file:

```swift
//
//  DeviceGroupDeferredSyncPlanner.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

struct DeviceGroupDeferredSyncTask {
    let operationType: DeviceOperationType
    let messageHandles: [MeshMessageHandle]
    let filteredSceneRecallCount: Int
}

struct DeviceGroupDeferredSyncPlan {
    let immediateMessageHandles: [MeshMessageHandle]
    let deferredTasks: [DeviceGroupDeferredSyncTask]

    var hasDeferredTasks: Bool {
        !deferredTasks.isEmpty
    }
}

enum DeviceGroupDeferredSyncPlanner {
}
```

- [ ] **Step 2: Add makePlan entry point**

Append this implementation in the same file:

```swift
extension DeviceGroupDeferredSyncPlanner {

    static func makePlan(node: Node, group: Group) -> DeviceGroupDeferredSyncPlan {
        let syncDatas = node.getSyncData(type: .group(group))
        var immediateHandles: [MeshMessageHandle] = []
        var deferredTasks: [DeviceGroupDeferredSyncTask] = []

        syncDatas.forEach { syncData in
            switch syncData {
            case .deviceInitialize, .subscribeGroup:
                immediateHandles.append(contentsOf: syncData.getMessageHandles(node: node))
            case .profile,
                    .syncScenes,
                    .deleteScenes,
                    .syncSchedules,
                    .deleteSchedules,
                    .syncCollectionSchedules,
                    .deleteCollectionSchedules,
                    .syncSwitchProxy,
                    .deleteSwitchProxy,
                    .syncSwitchs,
                    .deleteSwitchs,
                    .proximityLightingEnabled,
                    .proximityLightingRelayNumber,
                    .proximityLightingNeighbor:
                deferredTasks.append(contentsOf: makeDeferredTasks(syncData: syncData, node: node))
            default:
                immediateHandles.append(contentsOf: syncData.getMessageHandles(node: node))
            }
        }

        return DeviceGroupDeferredSyncPlan(
            immediateMessageHandles: immediateHandles,
            deferredTasks: deferredTasks
        )
    }
}
```

- [ ] **Step 3: Add deferred task conversion**

Append this private implementation:

```swift
private extension DeviceGroupDeferredSyncPlanner {

    static func makeDeferredTasks(syncData: NodeSyncData, node: Node) -> [DeviceGroupDeferredSyncTask] {
        var tasks: [DeviceGroupDeferredSyncTask] = []

        func appendTask(_ operationType: DeviceOperationType) {
            let messageHandles = operationType.messageHandles
            let filteredMessageHandles = messageHandles.filter { !($0.message is SceneRecall) }
            let filteredSceneRecallCount = messageHandles.count - filteredMessageHandles.count
            guard !filteredMessageHandles.isEmpty else {
                return
            }
            tasks.append(
                DeviceGroupDeferredSyncTask(
                    operationType: operationType,
                    messageHandles: filteredMessageHandles,
                    filteredSceneRecallCount: filteredSceneRecallCount
                )
            )
        }

        switch syncData {
        case .profile(let types):
            types.forEach { type in
                appendTask(.configuration(node: node, type: .profile(type: type)))
            }
        case .syncScenes(let datas):
            datas.forEach { scene, data in
                appendTask(.configuration(node: node, type: .scene(sceneId: scene.number, executeData: data)))
            }
        case .deleteScenes(let scenes):
            scenes.forEach { scene in
                appendTask(.delete(node: node, type: .scene(sceneId: scene.number, executeData: nil)))
            }
        case .syncSchedules(let schedules):
            schedules.forEach { schedule in
                appendTask(.configuration(node: node, type: .schedule(schedule: schedule)))
            }
        case .deleteSchedules(let schedules):
            schedules.forEach { schedule in
                appendTask(.delete(node: node, type: .schedule(schedule: schedule)))
            }
        case .syncCollectionSchedules(let schedules):
            schedules.forEach { index, entry in
                appendTask(.configuration(node: node, type: .collectionSchedule(index: index, entry: entry)))
            }
        case .deleteCollectionSchedules(let scheduleIds):
            scheduleIds.forEach { index in
                appendTask(.delete(node: node, type: .collectionSchedule(index: index, entry: SchedulerRegistryEntry())))
            }
        case .syncSwitchProxy(let switchData):
            appendTask(.configuration(node: node, type: .enOceanProxy(switchData: switchData)))
        case .deleteSwitchProxy(let switchData):
            appendTask(.delete(node: node, type: .enOceanProxy(switchData: switchData)))
        case .syncSwitchs(let switchDatas):
            switchDatas.forEach { switchData in
                appendTask(.configuration(node: node, type: .enOceanSwitch(switchData: switchData)))
            }
        case .deleteSwitchs(let switchDatas):
            switchDatas.forEach { switchData in
                appendTask(.delete(node: node, type: .enOceanSwitch(switchData: switchData)))
            }
        case .proximityLightingEnabled(let enabled):
            appendTask(.configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
        case .proximityLightingRelayNumber(let relayNumber):
            appendTask(.configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
        case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
            appendTask(
                .configuration(
                    node: node,
                    type: .proximityLightingNeighbor(
                        relayNumber: relayNumber,
                        neighborAddresses: neighborAddresses
                    )
                )
            )
        default:
            break
        }

        return tasks
    }
}
```

- [ ] **Step 4: Run focused static check**

Run:

```bash
rg -n "DeviceGroupDeferredSyncPlanner|DeviceGroupDeferredSyncTask|SceneRecall|makePlan" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected:

- `DeviceGroupDeferredSyncPlanner` exists.
- `makePlan` exists.
- deferred task conversion filters `SceneRecall`.

## Task 2: Add Classic Add Flow Deferred Execution

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:52`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:1096`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:1206`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:1255`

- [ ] **Step 1: Add pending deferred plan storage**

Near existing properties:

```swift
private var addSuccessNodes: [Node] = []
private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
```

change to:

```swift
private var addSuccessNodes: [Node] = []
private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
private var pendingGroupDeferredSyncPlans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)] = []
```

- [ ] **Step 2: Replace direct group sync append messages**

In the `shouldApplyLightingDefaults, let group = self.addToGroup` branch, replace:

```swift
let syncDatas = node.getSyncData(type: .group(group))
syncDatas.forEach({
    appendMessages.append(contentsOf: $0.getMessageHandles(node: node))
})
```

with:

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
appendMessages.append(contentsOf: plan.immediateMessageHandles)
```

- [ ] **Step 3: Collect deferred plan on add success**

Inside `addSuccess`, after the existing `if let group = self.addToGroup { ... }` block and before BPS battery handling, insert:

```swift
if node.deviceType == .light, let group = self.addToGroup {
    let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
    if plan.hasDeferredTasks {
        self.pendingGroupDeferredSyncPlans.append((node: node, group: group, plan: plan))
    }
}
```

- [ ] **Step 4: Add deferred execution helpers**

Add these private methods before `checkDeviceAddressesAreSufficient(devices:)`:

```swift
private func finishGroupDeferredSyncPlans(completion: @escaping () -> Void) {
    let plans = pendingGroupDeferredSyncPlans
    pendingGroupDeferredSyncPlans.removeAll()
    runGroupDeferredSyncPlans(plans, index: 0, completion: completion)
}

private func runGroupDeferredSyncPlans(
    _ plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
    index: Int,
    completion: @escaping () -> Void
) {
    guard index < plans.count else {
        completion()
        return
    }

    let item = plans[index]
    runGroupDeferredSyncTasks(item.plan.deferredTasks, index: 0, node: item.node, group: item.group, hadFailure: false) { [weak self] _ in
        self?.runGroupDeferredSyncPlans(plans, index: index + 1, completion: completion)
    }
}

private func runGroupDeferredSyncTasks(
    _ tasks: [DeviceGroupDeferredSyncTask],
    index: Int,
    node: Node,
    group: Group,
    hadFailure: Bool,
    completion: @escaping (Bool) -> Void
) {
    guard index < tasks.count else {
        if hadFailure {
            node.clearSyncStateCache()
            group.updateGroupSyncState()
        }
        completion(hadFailure)
        return
    }

    let task = tasks[index]
    let messageHandles = task.messageHandles
    guard !messageHandles.isEmpty else {
        runGroupDeferredSyncTasks(tasks, index: index + 1, node: node, group: group, hadFailure: hadFailure, completion: completion)
        return
    }

    MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil, successfulBack: { handle, statusMessage in
        if statusMessage is LightLightnessStatus
            || statusMessage is LightCTLTemperatureStatus
            || statusMessage is LightCTLStatus
            || statusMessage is LightHSLStatus,
           messageHandles.contains(where: { $0.message is SceneStore }) {
            let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
            let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
            targetNode.updateNodeStatus(message: statusMessage, source: address)
        }
    }, failedBack: nil) { [weak self] resultMessageHandles in
        guard let self = self else { return }
        var taskFailed = false
        resultMessageHandles.forEach { handle in
            let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
            let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
            targetNode.updateData(message: handle.message, isSuccess: handle.isSuccessful)
            targetNode.clearSyncStateCache()
            if !handle.isSuccessful {
                taskFailed = true
            }
        }
        if taskFailed {
            group.updateGroupSyncState()
        }
        self.runGroupDeferredSyncTasks(
            tasks,
            index: index + 1,
            node: node,
            group: group,
            hadFailure: hadFailure || taskFailed,
            completion: completion
        )
    }
}
```

- [ ] **Step 5: Run deferred sync before final notifications**

In `addFinish`, wrap the existing body with `finishGroupDeferredSyncPlans`.

Replace:

```swift
self.deviceStateCallback?(false)
self.deviceAddCallback?(self.addSuccessNodes)

self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
```

with:

```swift
self.finishGroupDeferredSyncPlans { [weak self] in
    guard let self = self else { return }
    self.deviceStateCallback?(false)
    self.deviceAddCallback?(self.addSuccessNodes)

    self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
```

Then add the closing brace after:

```swift
self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
```

so the end of the block becomes:

```swift
            self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
        }
```

- [ ] **Step 6: Run focused static checks**

Run:

```bash
rg -n "pendingGroupDeferredSyncPlans|finishGroupDeferredSyncPlans|runGroupDeferredSyncTasks|DeviceGroupDeferredSyncPlanner.makePlan|node.getSyncData\\(type: \\.group" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected:

- New pending storage and helper methods exist.
- Classic add flow uses `DeviceGroupDeferredSyncPlanner.makePlan`.
- The old direct `node.getSyncData(type: .group(group))` append loop is absent from Classic.

## Task 3: Add Professional Add Flow Deferred Execution

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:120`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:1014`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:1074`
- Reference: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:1137`

- [ ] **Step 1: Add pending deferred plan storage**

Near existing properties:

```swift
private var addSuccessNodes: [Node] = []
private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
```

change to:

```swift
private var addSuccessNodes: [Node] = []
private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
private var pendingGroupDeferredSyncPlans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)] = []
```

- [ ] **Step 2: Replace direct group sync append messages**

In the `shouldApplyLightingDefaults, case .group(let group) = self.addTarget` branch, replace:

```swift
let syncDatas = node.getSyncData(type: .group(group))
syncDatas.forEach({
    appendMessages.append(contentsOf: $0.getMessageHandles(node: node))
})
```

with:

```swift
let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
appendMessages.append(contentsOf: plan.immediateMessageHandles)
```

- [ ] **Step 3: Collect deferred plan on add success**

Inside `addSuccess`, after the existing `if case .group(let group) = self.addTarget { ... }` block and before BPS battery handling, insert:

```swift
if node.deviceType == .light, case .group(let group) = self.addTarget {
    let plan = DeviceGroupDeferredSyncPlanner.makePlan(node: node, group: group)
    if plan.hasDeferredTasks {
        self.pendingGroupDeferredSyncPlans.append((node: node, group: group, plan: plan))
    }
}
```

- [ ] **Step 4: Add deferred execution helpers**

Add the same three private helper methods from Task 2 Step 4 before `checkDeviceAddressesAreSufficient(devices:)`.

Use the exact method bodies from Task 2 Step 4:

```swift
private func finishGroupDeferredSyncPlans(completion: @escaping () -> Void) {
    let plans = pendingGroupDeferredSyncPlans
    pendingGroupDeferredSyncPlans.removeAll()
    runGroupDeferredSyncPlans(plans, index: 0, completion: completion)
}

private func runGroupDeferredSyncPlans(
    _ plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
    index: Int,
    completion: @escaping () -> Void
) {
    guard index < plans.count else {
        completion()
        return
    }

    let item = plans[index]
    runGroupDeferredSyncTasks(item.plan.deferredTasks, index: 0, node: item.node, group: item.group, hadFailure: false) { [weak self] _ in
        self?.runGroupDeferredSyncPlans(plans, index: index + 1, completion: completion)
    }
}

private func runGroupDeferredSyncTasks(
    _ tasks: [DeviceGroupDeferredSyncTask],
    index: Int,
    node: Node,
    group: Group,
    hadFailure: Bool,
    completion: @escaping (Bool) -> Void
) {
    guard index < tasks.count else {
        if hadFailure {
            node.clearSyncStateCache()
            group.updateGroupSyncState()
        }
        completion(hadFailure)
        return
    }

    let task = tasks[index]
    let messageHandles = task.messageHandles
    guard !messageHandles.isEmpty else {
        runGroupDeferredSyncTasks(tasks, index: index + 1, node: node, group: group, hadFailure: hadFailure, completion: completion)
        return
    }

    MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil, successfulBack: { handle, statusMessage in
        if statusMessage is LightLightnessStatus
            || statusMessage is LightCTLTemperatureStatus
            || statusMessage is LightCTLStatus
            || statusMessage is LightHSLStatus,
           messageHandles.contains(where: { $0.message is SceneStore }) {
            let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
            let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
            targetNode.updateNodeStatus(message: statusMessage, source: address)
        }
    }, failedBack: nil) { [weak self] resultMessageHandles in
        guard let self = self else { return }
        var taskFailed = false
        resultMessageHandles.forEach { handle in
            let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
            let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
            targetNode.updateData(message: handle.message, isSuccess: handle.isSuccessful)
            targetNode.clearSyncStateCache()
            if !handle.isSuccessful {
                taskFailed = true
            }
        }
        if taskFailed {
            group.updateGroupSyncState()
        }
        self.runGroupDeferredSyncTasks(
            tasks,
            index: index + 1,
            node: node,
            group: group,
            hadFailure: hadFailure || taskFailed,
            completion: completion
        )
    }
}
```

- [ ] **Step 5: Run deferred sync before final notifications**

In `addFinish`, wrap the existing body with `finishGroupDeferredSyncPlans`.

Replace:

```swift
self.deviceAddCallback?(self.addSuccessNodes)
self.deviceStateCallback?(false)

self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
```

with:

```swift
self.finishGroupDeferredSyncPlans { [weak self] in
    guard let self = self else { return }
    self.deviceAddCallback?(self.addSuccessNodes)
    self.deviceStateCallback?(false)

    self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
```

Then add the closing brace after:

```swift
self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
```

so the end of the block becomes:

```swift
            self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
        }
```

- [ ] **Step 6: Run focused static checks**

Run:

```bash
rg -n "pendingGroupDeferredSyncPlans|finishGroupDeferredSyncPlans|runGroupDeferredSyncTasks|DeviceGroupDeferredSyncPlanner.makePlan|node.getSyncData\\(type: \\.group" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- New pending storage and helper methods exist.
- Professional add flow uses `DeviceGroupDeferredSyncPlanner.makePlan`.
- The old direct `node.getSyncData(type: .group(group))` append loop is absent from Professional.

## Task 4: Remove Duplication If It Becomes Noisy

**Files:**
- Optional Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Optional Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Optional Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Check duplicated helper size**

Run:

```bash
rg -n "private func finishGroupDeferredSyncPlans|private func runGroupDeferredSyncPlans|private func runGroupDeferredSyncTasks" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Each controller contains the same three helpers after Tasks 2 and 3.

- [ ] **Step 2: If duplication blocks readability, move runner to planner file**

If the duplicated helpers make both controllers hard to read, replace them with this helper in `DeviceGroupDeferredSyncPlanner.swift`:

```swift
extension DeviceGroupDeferredSyncPlanner {

    static func run(
        plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
        completion: @escaping () -> Void
    ) {
        runPlans(plans, index: 0, completion: completion)
    }
}

private extension DeviceGroupDeferredSyncPlanner {

    static func runPlans(
        _ plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
        index: Int,
        completion: @escaping () -> Void
    ) {
        guard index < plans.count else {
            completion()
            return
        }

        let item = plans[index]
        runTasks(item.plan.deferredTasks, index: 0, node: item.node, group: item.group, hadFailure: false) { _ in
            runPlans(plans, index: index + 1, completion: completion)
        }
    }

    static func runTasks(
        _ tasks: [DeviceGroupDeferredSyncTask],
        index: Int,
        node: Node,
        group: Group,
        hadFailure: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < tasks.count else {
            if hadFailure {
                node.clearSyncStateCache()
                group.updateGroupSyncState()
            }
            completion(hadFailure)
            return
        }

        let task = tasks[index]
        let messageHandles = task.messageHandles
        guard !messageHandles.isEmpty else {
            runTasks(tasks, index: index + 1, node: node, group: group, hadFailure: hadFailure, completion: completion)
            return
        }

        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil, successfulBack: { handle, statusMessage in
            if statusMessage is LightLightnessStatus
                || statusMessage is LightCTLTemperatureStatus
                || statusMessage is LightCTLStatus
                || statusMessage is LightHSLStatus,
               messageHandles.contains(where: { $0.message is SceneStore }) {
                let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
                targetNode.updateNodeStatus(message: statusMessage, source: address)
            }
        }, failedBack: nil) { resultMessageHandles in
            var taskFailed = false
            resultMessageHandles.forEach { handle in
                let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
                let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
                targetNode.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                targetNode.clearSyncStateCache()
                if !handle.isSuccessful {
                    taskFailed = true
                }
            }
            if taskFailed {
                group.updateGroupSyncState()
            }
            runTasks(
                tasks,
                index: index + 1,
                node: node,
                group: group,
                hadFailure: hadFailure || taskFailed,
                completion: completion
            )
        }
    }
}
```

- [ ] **Step 3: If runner moved, simplify controller finish helpers**

In each controller, replace the three helper methods with:

```swift
private func finishGroupDeferredSyncPlans(completion: @escaping () -> Void) {
    let plans = pendingGroupDeferredSyncPlans
    pendingGroupDeferredSyncPlans.removeAll()
    DeviceGroupDeferredSyncPlanner.run(plans: plans, completion: completion)
}
```

- [ ] **Step 4: Re-run static check**

Run:

```bash
rg -n "DeviceGroupDeferredSyncPlanner.run|private func runGroupDeferredSyncTasks|static func run\\(" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- If runner was moved, controllers call `DeviceGroupDeferredSyncPlanner.run`.
- If runner was not moved, controllers still contain their local helpers and no static `run` exists.

## Task 5: Verify Behavior And Build

**Files:**
- Verify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Verify append stage no longer directly sends group feature sync**

Run:

```bash
rg -n "node.getSyncData\\(type: \\.group\\(|syncDatas\\.forEach\\(|DeviceGroupDeferredSyncPlanner.makePlan" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Both add controllers contain `DeviceGroupDeferredSyncPlanner.makePlan`.
- No light + group branch contains the old `syncDatas.forEach { appendMessages.append(contentsOf: $0.getMessageHandles(node: node)) }` pattern.

- [ ] **Step 2: Verify deferred failure marks group for sync**

Run:

```bash
rg -n "group.updateGroupSyncState\\(\\)|updateData\\(message: handle.message, isSuccess: handle.isSuccessful\\)|clearSyncStateCache\\(\\)" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Deferred runner updates node data with actual handle success.
- Deferred runner clears sync state cache.
- Deferred runner calls `group.updateGroupSyncState()` when a task fails.

- [ ] **Step 3: Verify only light + group stores deferred plans**

Run:

```bash
rg -n "node.deviceType == \\.light|pendingGroupDeferredSyncPlans.append|case \\.group\\(let group\\)|let group = self.addToGroup" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Deferred plan append is guarded by `node.deviceType == .light`.
- Classic uses `self.addToGroup`.
- Professional uses `case .group(let group) = self.addTarget`.

- [ ] **Step 4: Run diff whitespace check**

Run:

```bash
git diff --check -- SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- No trailing whitespace or whitespace error output.

- [ ] **Step 5: Build SunSmart for iPhoneOS**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- Do not use shell wrapping or log redirection.

- [ ] **Step 6: Manual verification checklist**

Use a real test path or simulator-connected Mesh environment that can add devices:

1. Add a light into a group with a non-default Profile.
2. Confirm the light joins the group.
3. Confirm the group Profile is applied to the light.
4. Confirm group Scenes include and control the light.
5. Confirm group Schedules are written to the light.
6. Confirm BPS / EnOcean switch / sensor target subscriptions for that group can control the light.
7. Force one deferred command to fail, then confirm the device remains added and the group becomes needs-sync.
8. Enter existing sync flow and confirm failed items can be regenerated and synced.
9. Add a light without choosing a group and confirm behavior is unchanged.
10. Add a non-light device and confirm behavior is unchanged.

## Task 6: Documentation And Commit

**Files:**
- Modify: `docs/superpowers/plans/260529_1035_light_add_group_deferred_sync.md` only if implementation notes are needed.
- Commit implementation files from previous tasks.

- [ ] **Step 1: Check final changed files**

Run:

```bash
git status --short
```

Expected changed files:

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- `SunSmart.xcodeproj/project.pbxproj`
- This plan file only if task checkboxes or implementation notes were updated.

- [ ] **Step 2: Review focused diff**

Run:

```bash
git diff -- SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Changes are limited to light group deferred sync.
- No Auth information added.
- No unrelated formatting churn.
- Project file change only adds the new Swift helper to the four shared business targets.
- No SDK, resource, localization, or dependency changes.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: defer light group sync after add"
```

Expected:

- Commit succeeds.
