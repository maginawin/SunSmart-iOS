# Group Add PIR Publication Sync Follow-up Analysis

## 背景

第一轮方案 A 已完成两个修复点：

- Add Device 自动入组路径生成 deferred profile sync 时传入 `.memberAdded` 上下文。
- `addFinish` 收尾时基于 `successList` 补齐可能漏收集的 group deferred plans。

但复测仍存在残留问题：

- 从 Group Members 页 Add device。
- 扫描 2 个带 PIR 功能设备并点击 `Add Selected`。
- 添加完成后仍有 1 个设备在组内展示为需要同步。
- 点击 Main - Lights 左下角同步按钮后，只补发一条 `ConfigModelPublicationSet`：
  - `elementAddress: 72`
  - `modelIdentifier: 4352`，即 SIG Sensor Server `0x1100`
  - `publish: 0xC009`
  - `status: Success`
- 补发成功后设备恢复正常。

这说明方案 A 已经不足以解释全部问题。剩余问题不再像是“没有生成 Sensor publication 任务”，而更像是“Add Device 自动 deferred sync 阶段认为任务已完成，但目标 Sensor Server publication 没有被可靠写入本地 mesh model 或没有真正满足成功条件”。

## 当前证据

### 1. 残留项仍然是 Sensor Server publication

用户补发日志稳定指向：

- `ConfigModelPublicationSet`
- `modelIdentifier: 4352`
- publish address 指向当前 group。

组内待同步图标的判断路径是：

- `GroupMembersViewController`
- `node.needSyncGroupData`
- `Node.getNeedSyncGroup()`
- `getNodeSyncProfiles(group:sensorPublicationSyncMode: .legacyCompatible)`
- `ProfileType.sensorEnabled(...)`

因此残留状态的直接原因是：

- 带 PIR 设备的 `presenceDetectedSensorModel.publish` 不是目标 group address，或 retransmit 没有满足当前判定。

### 2. Add Device deferred runner 与手动同步 runner 的成功判定不一致

手动同步页 `SyncDevicesViewController` 在每个 task 完成后会同时检查：

- `resultMessageHandles` 是否都成功。
- `operationType.isSuccessful` 是否为 true。

对 `.sensorEnabled(...)` 来说，`operationType.isSuccessful` 最终会调用：

- `ProfileType.isSuccessful(node:)`
- `Model.isSensorServerPublicationConfigured(publishAddress:retransmit:)`

也就是复核本地 model 的 publication 是否真的已经被更新到目标 group。

当前 `DeviceGroupDeferredSyncPlanner.runTasks` 只根据 `handle.isSuccessful` 判断 task 是否失败，没有复用 `operationType.isSuccessful`。如果 SDK 收到 ACK/Status，但本地 model publish 没有落成目标值，Add Device deferred runner 仍会继续下一步并最终完成。

### 3. `MeshProxyMessageCommand` 是共享单例队列，Add Device 收尾阶段更容易出现交错

SDK 中 `MeshProxyMessageCommand.shared.addMessage(...)` 的行为：

- 如果当前已有 `sendMessageHandles` 且不在 reset，会把新 handles append 到同一队列。
- 非 nil 的 `successfulBack`、`failedBack`、`finishedBack` 会覆盖共享 callback。
- `ConfigModelPublicationStatus` response matching 只校验 element/model/company，不校验返回的 publish address。

这表示在 Add Device 收尾阶段，如果 provision 后续配置、设备初始化补发、页面刷新触发的其它配置消息与 deferred sync 交错，runner 的“完成回调”不一定等价于“当前 deferred operation 的目标状态已满足”。

手动同步按钮通常是一个明确的同步会话，且每个 task 都在 UI sync run 内用 `operationType.isSuccessful` 复核，因此同一条 publication 补发后可以恢复。

### 4. 批量 2 个和 3 个都只残留 1 个，符合“执行可靠性/完成判定”问题

如果是单纯缺 `.memberAdded` 上下文，理论上所有新增成员都可能缺完整 profile。

如果是单纯 `addSuccess` / `addFinish` 收集边界问题，方案 A 的 `successList` 补齐应明显消除。

现在仍稳定只残留一个 Sensor publication，更符合：

- 某个 task 的 response/本地状态更新未完成但被视为成功。
- 或共享队列插入/回调覆盖导致某个 publication task 的结果归属不可靠。

## 根因判断

优先级最高的剩余根因是：

> Add Device 的 group deferred sync runner 只看 message handle 层面的成功，没有像手动同步页一样复核 `operationType.isSuccessful`，导致 Sensor Server publication 在批量添加场景下可能被错误标记为完成。

次级风险是：

> `DeviceGroupDeferredSyncPlanner` 将 profile 拆成多个独立 task 并逐个调用共享 `MeshProxyMessageCommand`。在 Add Device 收尾阶段，这比手动同步页更容易受到共享队列插入、callback 覆盖和 response matching 宽松的影响。

## 方案 B

在保留方案 A 的基础上，修复 deferred runner 的完成判定，并按业务预期加入自动重试。

重试规则：

- 每个 deferred task 最多尝试 3 次：首次发送 + 2 次自动重试。
- 触发重试的条件包括：
  - 任一 `MeshMessageHandle.isSuccessful == false`。
  - 消息返回成功，但 `task.operationType.isSuccessful == false`。
- 重试发生在 Add Device 收尾阶段内部，不弹出新 UI，不需要用户点击 Main - Lights 的同步按钮。
- 重试 2 次后仍失败，才保留现有待同步状态，由 Members / Main - Lights 的同步入口兜底。
- 重试只覆盖 group deferred sync tasks，不重试 provisioning、key bind、基础入组 immediate handles，也不改变 Add Device 的整体成功/失败定义。

### 1. 在 deferred task 完成后复用 `operationType.isSuccessful`

修改 `DeviceGroupDeferredSyncPlanner.runTasks`：

- 保留 `resultMessageHandles` 的 success/fail 判断。
- 在执行 `targetNode.updateData(message:isSuccess:)` 和 `clearSyncStateCache()` 后，再检查：
  - `task.operationType.isSuccessful`
- 只有当 message handles 全成功且 `operationType.isSuccessful == true` 时，task 才算成功。
- 如果 `operationType.isSuccessful == false`，视为本次尝试失败，进入自动重试。
- 如果 2 次重试后仍失败，才调用 `group.updateGroupSyncState()` 保留需要同步状态。

这样即使 `ConfigModelPublicationStatus` 收到了，但本地 `presenceDetectedSensorModel.publish` 没有更新到 group，Add Device 不会把该设备误判为同步完成。

### 2. 增加 task 级自动重试

建议把重试放在 `DeviceGroupDeferredSyncPlanner` 内部，而不是 Add Device controller 内部：

- planner 最接近 task/message/operation 成功判定。
- Classic 和 Professional 可以共享同一套重试语义。
- controller 只关心最终 plan 成功或失败。

建议接口：

- `DeviceGroupDeferredSyncPlanner.run(plans:maxRetryCount:completion:)`
- `maxRetryCount` 默认值为 `2`
- `runTasks` 内部维护 `attempt`，失败且 `attempt < maxRetryCount` 时重发同一个 task。

每次重试前需要重新取 `task.operationType.messageHandles` 或重新构建 task 的 handles。原因是上一次 `MeshMessageHandle` 已经带有 `respondAddresss` / `notRespondAddresss` 等运行态，不能直接复用同一个 handle 实例重发。

### 3. 调整设备成功标记时机

当前 `finishGroupDeferredSyncPlans` 在 `DeviceGroupDeferredSyncPlanner.run` 完成后，会无条件调用 `markPendingGroupDeferredSyncDevicesSucceeded()`。

建议让 `DeviceGroupDeferredSyncPlanner.run` 返回每个 plan 的执行结果：

- plan 全部 deferred tasks 成功：对应 `ProvisioningDevice.addState = .success`。
- plan 经 2 次自动重试后仍有失败或 operation 复核失败：不强制标 success，保留现有待同步状态，让 Members / Main - Lights 显示 sync 按钮。

如果 UI 体验上必须把 provision 成功和 profile sync 失败拆开，可以保持 provision success，但需要确保 group sync state 不被误清，并且不要隐藏待同步提示。

### 4. 降低共享队列插入风险

短期最小改动：

- 继续串行执行 plans/tasks。
- 每个 task 调用 `addMessage` 时传入与手动同步一致或更保守的 `ackMessageTimeout`，建议 15 秒。
- 在 finished callback 内基于 `operationType.isSuccessful` 做最终判断。
- task 失败时最多自动重试 2 次。

中期更稳方案：

- 将同一 node 的 deferred tasks 尽量合并到一次 `addMessage` 调用，减少共享单例队列启动/重置次数。
- 或抽出一个无 UI 的 sync runner，复用 `SyncDevicesViewController` 的 task 执行语义和成功判定，避免 Add Device 维护第二套同步实现。

本次建议先做短期最小改动，因为风险低、改动范围集中，能直接覆盖当前 Sensor publication 残留。

## 推荐实施计划

### Task 1: 加强 `DeviceGroupDeferredSyncPlanner` 成功判定与自动重试

修改文件：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

步骤：

- 调整 `run` / `runPlans` / `runTasks` 的 completion，使其能返回每个 plan 是否成功。
- 为 `run` 增加 `maxRetryCount: Int = 2`。
- 在每个 task finished callback 中：
  - 先按现有逻辑更新 `targetNode.updateData(...)`。
  - 再计算 `let operationSuccessful = task.operationType.isSuccessful`。
  - `taskFailed = resultMessageHandles.contains { !$0.isSuccessful } || !operationSuccessful`。
- task failed 且 `attempt < maxRetryCount` 时，重新生成当前 task 的 message handles 并重试。
- task failed 且重试耗尽时，清理 sync cache 并调用 `group.updateGroupSyncState()`。

### Task 2: 避免无条件标记 deferred sync 设备成功

修改文件：

- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

步骤：

- `finishGroupDeferredSyncPlans` 接收 planner 返回的 plan 结果。
- 只对 deferred sync 成功的设备调用 success 状态刷新。
- 对 deferred sync 失败的设备保留或恢复为可感知状态，但不阻断整体 Add Device 完成回调。
- 确保 `deviceAddCallback` 和 refresh notification 仍在 deferred sync 尝试后触发。

### Task 3: 加诊断日志便于真机确认

建议在 Debug 日志中打印：

- deferred plan node address。
- 每个 task 的 `operationType`。
- `resultSuccessful`。
- `operationSuccessful`。
- 对 `.sensorEnabled` 打印期望 publish address 与当前 `model.publish?.publicationAddress.address`。

日志只用于定位，不应改变 Release 行为。

### Task 4: 验证

静态验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

真机验证：

- 新建非 Manual Control profile group。
- 从 Members 页 Add device。
- 扫描并同时添加 2 个带 PIR 设备。
- 返回 Members 后确认两个设备都不显示需要同步。
- 重复同时添加 3 个带 PIR 设备。
- Main - Lights 左下角不应出现需要补发的 sync 按钮，或点击同步时不再出现针对新增设备的 Sensor Server publication 补发。

## 风险

- 如果 underlying SDK 未能稳定更新 model.publish，operation 复核会暴露失败而不是隐藏失败，页面仍可能显示需要同步；这是正确行为，但用户可能仍看到待同步提示。
- 如果业务希望 Add Device 成功态不受 profile sync 影响，需要把 provision success 和 deferred sync failed 的 UI 状态分离，不能简单把设备标为 failed。
- 如果后续仍复现，需要进一步把 deferred sync 改为复用 `SyncDevicesViewController` 的无 UI runner，或修 SDK `MeshProxyMessageCommand` 的队列隔离与 publication response matching。
