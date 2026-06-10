# Group Add PIR Publication Retry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Add Device 自动入组后的 group deferred sync 在 Sensor Server publication 同步失败时自动重试 2 次，重试耗尽后才保留需要同步状态。

**Architecture:** 在 `DeviceGroupDeferredSyncPlanner` 内部加入 task 级重试和 operation 状态复核，Classic / Professional Add Device controller 只消费最终 plan 结果。保留方案 A 的 `.memberAdded` 上下文和 `successList` 补齐逻辑，不改 provisioning、key bind、immediate group add 行为。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Add Device controllers、现有 `MeshProxyMessageCommand`。

---

## Scope

实现设计文档：

- `docs/superpowers/specs/260610_1650_group_add_pir_publication_sync_followup.md`

修改文件：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

不修改：

- NordicSigMeshSDK
- 本地化和资源
- Xcode target 配置
- Manual Control profile 规则
- provisioning / key bind / immediate group add 流程

## Expected Behavior

- 每个 group deferred sync task 最多尝试 3 次：首次 + 2 次自动重试。
- 以下任一条件视为本次 task 尝试失败：
  - `resultMessageHandles` 中存在 `isSuccessful == false`。
  - `task.operationType.isSuccessful == false`。
- task 成功后继续下一个 task。
- task 重试耗尽后，当前 plan 失败，继续处理下一个 device 的 plan。
- plan 成功的 device 才在 deferred sync 完成后标记为 `.success`。
- plan 失败的 device 不再被无条件标记为 `.success`；保持待同步状态，后续由 Members / Main - Lights 同步入口兜底。

## Task 1: 增强 deferred sync task 的可重试能力

**Files:**

- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

- [ ] **Step 1: 给 task 增加 fresh handles 方法**

在 `DeviceGroupDeferredSyncTask` 中保留现有属性，并新增方法：

```swift
func makeMessageHandles() -> [MeshMessageHandle] {
    operationType.messageHandles.filter { !($0.message is SceneRecall) }
}
```

原因：`MeshMessageHandle` 会在发送过程中写入 `respondAddresss`、`notRespondAddresss`、`handle` 等运行态。重试时必须重新从 `operationType` 生成 fresh handles，不能复用上一次失败的 handle 实例。

- [ ] **Step 2: 调整 `makeDeferredTasks` 使用 fresh handles 方法**

在 `appendTask(_:)` 中保留现有 filtered 逻辑，但确保后续执行时不依赖 task 初始化时保存的 `messageHandles` 做重试。

建议保持 `messageHandles` 属性不删除，减少调用方改动；runner 中统一调用 `task.makeMessageHandles()` 获取本次尝试的 handles。

- [ ] **Step 3: 静态检查 task 结构**

Run:

```sh
rg -n "struct DeviceGroupDeferredSyncTask|makeMessageHandles|operationType.messageHandles|SceneRecall" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected:

- `DeviceGroupDeferredSyncTask` 内存在 `makeMessageHandles()`。
- runner 中后续发送使用 fresh handles。

## Task 2: 让 planner 返回每个 plan 的最终结果

**Files:**

- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

- [ ] **Step 1: 新增 plan 运行结果类型**

在 `DeviceGroupDeferredSyncPlan` 后新增：

```swift
struct DeviceGroupDeferredSyncPlanResult {
    let node: Node
    let group: Group
    let succeeded: Bool
}
```

- [ ] **Step 2: 修改 `run` 签名**

把：

```swift
static func run(
    plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
    completion: @escaping () -> Void
)
```

改为：

```swift
static func run(
    plans: [(node: Node, group: Group, plan: DeviceGroupDeferredSyncPlan)],
    maxRetryCount: Int = 2,
    completion: @escaping ([DeviceGroupDeferredSyncPlanResult]) -> Void
)
```

- [ ] **Step 3: 修改 `runPlans` 累积结果**

让 `runPlans` 接收 `results: [DeviceGroupDeferredSyncPlanResult]`，每个 plan 完成后 append：

```swift
DeviceGroupDeferredSyncPlanResult(
    node: item.node,
    group: item.group,
    succeeded: planSucceeded
)
```

当 `index >= plans.count` 时调用 `completion(results)`。

- [ ] **Step 4: 静态检查签名**

Run:

```sh
rg -n "DeviceGroupDeferredSyncPlanResult|static func run\\(|runPlans\\(" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected:

- `run` completion 返回 `[DeviceGroupDeferredSyncPlanResult]`。
- `runPlans` 累积 result。

## Task 3: 增加 task 级 2 次自动重试

**Files:**

- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

- [ ] **Step 1: 修改 `runTasks` 返回 plan 是否成功**

把 `runTasks` completion 语义调整为：

```swift
completion(!hadFailure)
```

也就是 `true` 表示当前 plan 全部 tasks 成功，`false` 表示至少一个 task 经重试后仍失败。

- [ ] **Step 2: 新增 `runTaskAttempt` helper**

新增私有方法：

```swift
static func runTaskAttempt(
    _ task: DeviceGroupDeferredSyncTask,
    attempt: Int,
    maxRetryCount: Int,
    node: Node,
    group: Group,
    completion: @escaping (Bool) -> Void
)
```

执行逻辑：

- `let messageHandles = task.makeMessageHandles()`
- 空 handles 直接 `completion(true)`。
- 调用 `MeshProxyMessageCommand.shared.addMessage(...)`，`ackMessageTimeout` 使用 `15`。
- finished callback 中先按现有逻辑对每个 handle 调 `targetNode.updateData(message:isSuccess:)` 和 `clearSyncStateCache()`。
- 计算：

```swift
let resultSuccessful = !resultMessageHandles.contains { !$0.isSuccessful }
let operationSuccessful = task.operationType.isSuccessful
let taskSucceeded = resultSuccessful && operationSuccessful
```

- 如果 `taskSucceeded == false && attempt < maxRetryCount`，递归调用 `runTaskAttempt(... attempt: attempt + 1 ...)`。
- 如果重试耗尽，调用 `group.updateGroupSyncState()` 后 `completion(false)`。
- 如果成功，`completion(true)`。

- [ ] **Step 3: 让 `runTasks` 调用 `runTaskAttempt`**

把现有 `MeshProxyMessageCommand.shared.addMessage(...)` 发送块收敛到 `runTaskAttempt`。

`runTasks` 中对每个 task 的处理变成：

```swift
runTaskAttempt(task, attempt: 0, maxRetryCount: maxRetryCount, node: node, group: group) { taskSucceeded in
    runTasks(
        tasks,
        index: index + 1,
        node: node,
        group: group,
        maxRetryCount: maxRetryCount,
        hadFailure: hadFailure || !taskSucceeded,
        completion: completion
    )
}
```

- [ ] **Step 4: 加 Debug 诊断日志**

在 `runTaskAttempt` finished callback 中打印：

```swift
print("[GroupDeferredSync] node=\(node.primaryUnicastAddress) attempt=\(attempt + 1)/\(maxRetryCount + 1) resultSuccessful=\(resultSuccessful) operationSuccessful=\(operationSuccessful) operation=\(task.operationType)")
```

如 task 是 `.configuration(_, .profile(.sensorEnabled(...)))`，额外打印期望 group address 与当前 sensor model publish address。

- [ ] **Step 5: 静态检查重试逻辑**

Run:

```sh
rg -n "runTaskAttempt|maxRetryCount|operationSuccessful|resultSuccessful|ackMessageTimeout: 15|GroupDeferredSync" SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
```

Expected:

- `maxRetryCount` 默认是 `2`。
- `operationType.isSuccessful` 参与最终判定。
- `ackMessageTimeout` 是 `15`。
- Debug 日志存在。

## Task 4: Classic Add Device 按 plan 结果标记设备状态

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: 修改 pending success 标记方法签名**

把：

```swift
private func markPendingGroupDeferredSyncDevicesSucceeded()
```

改为：

```swift
private func markPendingGroupDeferredSyncDevicesFinished(
    results: [DeviceGroupDeferredSyncPlanResult]
)
```

- [ ] **Step 2: 按成功地址集合更新 addState**

在方法内建立成功地址集合：

```swift
let succeededAddresses = Set(results.filter { $0.succeeded }.map { $0.node.primaryUnicastAddress })
```

然后遍历 `pendingGroupDeferredSyncSuccessDevices`：

- 如果 address 在 `succeededAddresses` 中，设置 `device.addState = .success`。
- 如果不在，设置 `device.addState = .syncFailed`。
- 两种情况都调用 `reloadDeviceState(device)`。

最后清空 `pendingGroupDeferredSyncSuccessDevices` 并调用 `updateUIState()`。

- [ ] **Step 3: 修改 `finishGroupDeferredSyncPlans` completion**

把：

```swift
DeviceGroupDeferredSyncPlanner.run(plans: plans) { [weak self] in
    DispatchQueue.main.async {
        self?.markPendingGroupDeferredSyncDevicesSucceeded()
        completion()
    }
}
```

改为消费 results：

```swift
DeviceGroupDeferredSyncPlanner.run(plans: plans, maxRetryCount: 2) { [weak self] results in
    DispatchQueue.main.async {
        self?.markPendingGroupDeferredSyncDevicesFinished(results: results)
        completion()
    }
}
```

- [ ] **Step 4: 静态检查 Classic 调用点**

Run:

```sh
rg -n "markPendingGroupDeferredSyncDevices|DeviceGroupDeferredSyncPlanner.run\\(plans: plans|maxRetryCount: 2|syncFailed" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected:

- Classic 使用 `markPendingGroupDeferredSyncDevicesFinished(results:)`。
- Classic 调用 planner 时显式传 `maxRetryCount: 2`。
- deferred sync 失败设备会进入 `.syncFailed`。

## Task 5: Professional Add Device 按 plan 结果标记设备状态

**Files:**

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 对齐 Classic 的 pending success 标记方法**

把 Professional 中的：

```swift
private func markPendingGroupDeferredSyncDevicesSucceeded()
```

改为：

```swift
private func markPendingGroupDeferredSyncDevicesFinished(
    results: [DeviceGroupDeferredSyncPlanResult]
)
```

方法内部逻辑与 Classic 保持一致：

- 成功地址设置 `.success`。
- 失败地址设置 `.syncFailed`。
- reload device state。
- 清空 pending devices。
- `updateUIState()`。

- [ ] **Step 2: 修改 `finishGroupDeferredSyncPlans` completion**

使用：

```swift
DeviceGroupDeferredSyncPlanner.run(plans: plans, maxRetryCount: 2) { [weak self] results in
    DispatchQueue.main.async {
        self?.markPendingGroupDeferredSyncDevicesFinished(results: results)
        completion()
    }
}
```

- [ ] **Step 3: 静态检查 Professional 调用点**

Run:

```sh
rg -n "markPendingGroupDeferredSyncDevices|DeviceGroupDeferredSyncPlanner.run\\(plans: plans|maxRetryCount: 2|syncFailed" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Professional 与 Classic 行为一致。

## Task 6: 失败状态与最终回调边界复核

**Files:**

- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 确认 Add Device 最终回调仍在 deferred sync 尝试后触发**

Run:

```sh
rg -n "finishGroupDeferredSyncPlans\\(successDevices: successList\\)|deviceAddCallback|spaceDataChangedNotificaitonName|devicesAddNotificationName" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- `deviceAddCallback` 仍在 `finishGroupDeferredSyncPlans` completion 内。
- space count、refresh notification 仍在 deferred sync 尝试后执行。

- [ ] **Step 2: 确认没有把 provision 失败和 deferred sync 失败混为一类**

Run:

```sh
rg -n "addState = \\.failed|addState = \\.syncFailed|addFail|finishGroupDeferredSyncPlans" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- provisioning `addFail` 仍使用 `.failed`。
- group deferred sync 重试耗尽才使用 `.syncFailed`。

## Task 7: 验证

**Files:**

- Verify all modified files.

- [ ] **Step 1: Diff 检查**

Run:

```sh
git diff --check
```

Expected:

- No output.

- [ ] **Step 2: iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- `** BUILD SUCCEEDED **`

- [ ] **Step 3: 真机复测 2 设备批量添加**

Manual test:

- 创建新 group，profile 选择非 Manual Control 且会启用 PIR。
- 自动跳转 Members。
- 点击 Add device。
- Scan 到 2 个带 PIR 功能设备。
- 点击 `Add Selected`。

Expected:

- Add Device 收尾阶段如首次 publication 失败，会自动重试，最多看到 3 次同一 deferred task 尝试日志。
- 返回 Members 后，不应有设备显示需要同步。
- Main - Lights 左下角不应出现针对新增设备的 sync 按钮。

- [ ] **Step 4: 真机复测 3 设备批量添加**

Manual test:

- 使用同一流程同时添加 3 个带 PIR 功能设备。

Expected:

- 所有成功添加的设备都完成 Sensor Server publication。
- 若某设备 2 次自动重试后仍失败，只有该设备显示需要同步，点击 Main - Lights 同步按钮仍可补齐。

## Self-Review

- Spec coverage: 覆盖了 task 级 2 次自动重试、operation 成功复核、Classic/Professional 状态标记、失败兜底同步入口。
- Placeholder scan: 本计划没有占位标记或未定义任务。
- Type consistency: 新增类型统一为 `DeviceGroupDeferredSyncPlanResult`；controller 使用同一个结果类型消费 planner 输出。
