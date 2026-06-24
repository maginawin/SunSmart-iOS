# EFC Group Cleanup 修复方案

## 背景

删除 EFC 设备关联的 Group 后，如果在 Sync device(s) 页面立刻 Stop，再从 Main - Lights 底部同步入口补完 L1/L2 的 Group cleanup，EFC Edit 页面仍可能展示 Devices not synced。继续点击后，同步页会显示 Group 1 下的 EFC1 Group cleanup，并且很快成功。

这不是 EFC1 真实加入了 Group 1。它是 EFC pending cleanup 残留后，被 EFC Edit 入口重新规划成 local-only cleanup task，再被 Sync UI fallback 映射成 EFC bindNode 的显示问题。

## 根因判断

1. EFC 删除关联组后，旧组地址会进入 `pendingUnassociateGroupAddresses`，等待灯节点取消订阅 EFC 内部 publish group。
2. Lights 页同步入口走 `.devices`，每个灯节点会生成自己的 `emergencyFireControllerAssociations` 任务。
3. 多个灯或多个 group 同步时，任务里携带的 `DeviceEmerFireData` 可能是不同时间点的副本。若每个任务成功后直接保存自己的副本，后保存的副本可能覆盖前一个任务刚清掉的 pending group。
4. EFC Edit 入口再次打开同步页时，残留 pending group 会进入 `makeCleanupItems()`。
5. 如果该 group 已经没有实际可下发的灯端 cleanup message，planner 会生成 `messageHandles = []` 的 local-only cleanup task，用于清本地 pending 标记。
6. 当前 Sync UI 在找不到 `task.address` 对应 node 时 fallback 到 `data.bindNode`，所以 local-only group task 被显示成 EFC1。

## 推荐方案

采用 EFC-only 最小修复，不改 SDK 的 `Group.nodes` 语义，不重构 AC power switch、battery power switch、scene、schedule 的同步框架。

### 1. 清 pending 必须基于 store 最新对象

修改 `DeviceEmerFireData+Sync.swift` 中 EFC pending 清理和 sync state 刷新逻辑：

- `clearPending(for:meshUUID:subnetworkId:)` 不直接保存当前 task 携带的 `DeviceEmerFireData` 副本。
- 清理前先按 `id + meshUUID + meshNetworkId` 从 `DeviceEmerFireStore` 读取最新对象。
- 在最新对象上移除对应 `pendingUnassociateGroupAddresses`。
- 保存最新对象后，把当前实例同步到最新状态，避免后续通知继续带旧数据。
- `markDeleteCleanupSucceeded(...)` / `markDeleteCleanupInterrupted(...)` 同样基于最新对象保存。
- `refreshEmergencyFireControllerSyncState(...)` 保持对当前对象计算，避免 EFC 自身配置刚完成时丢失内存里的 `controllerSelfSyncPending` 结果；调用它的 cleanup 持久化路径负责先切到最新对象。

预期效果：Lights 页一次补完 Group 1 / Group 2 cleanup 后，不会因为后一个任务保存旧副本而把前一个 group 的 pending 恢复回来。

### 2. EFC association 目标节点只允许灯设备

修改 `EmergencyFireControllerSyncPlanner.swift`：

- 增加 EFC association target helper，例如只返回 `node.deviceType == .light` 的节点。
- `makeAssociatedGroupItems()` 使用该 helper。
- `makeCleanupItems()` 使用该 helper。
- `makeDeleteCleanupItems()` / `makeDeleteCleanupItem(...)` 使用该 helper。
- `makeGroupMutationItems(...)` 对 `addNodes` / `exitNodes` 也做同样保护。

预期效果：即使某个非灯节点因为历史订阅或异常模型状态被 `group.nodes` 命中，EFC group subscription / cleanup 也不会把它当成灯端目标。

### 3. local-only cleanup 按 group 显示，不 fallback 成 EFC

修改 `SyncDevicesViewController.swift` 的 EFC item 转 UI model 逻辑：

- 为 `messageHandles.isEmpty && kind == .associationCleanup && clearsUnassociatePending == true` 的 task 识别 local-only group cleanup。
- 这类 task 的 UI 名称使用 group/item 名称或 `Group cleanup`，地址使用 group address。
- 不再通过 `nodeForEmergencyFireControllerTask(...) ?? data.bindNode` 把它显示成 EFC bindNode。
- 执行层仍可复用现有 empty-task completion 逻辑：标记成功并清本地 pending，不发送 Mesh message。

预期效果：如果未来仍出现本地残留 pending，页面最多显示一个 group-level cleanup，不会再显示 “Group 1 中的 EFC1”。

### 4. 不扩大 sibling flow

本轮不改以下流程的业务行为：

- AC power switch
- battery power switch
- scene
- schedule

原因：

- Power switch 目前按订阅/退订 message handle 是否存在过滤目标节点，不存在 EFC local-only cleanup fallback。
- Scene/Schedule 目前按 scene/scheduler 能力模型过滤节点，不存在这次的 EFC bindNode fallback 显示问题。
- 若未来发现它们也有非灯节点误入目标列表，应单独按对应业务定义处理，不把 EFC 的 `isSynced/pendingUnassociateGroupAddresses` 模型套过去。

## 计划改动文件

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
  - store 最新对象清 pending
  - delete cleanup 基于 store 最新对象落库
  - EFC aggregate sync state 由最新对象 mutation 后重新计算

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
  - 收口 EFC association target node
  - add / cleanup / delete cleanup 统一过滤灯节点

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 修 local-only group cleanup 显示
  - 去掉 group-address task fallback 到 EFC bindNode 的 UI 表现

- `scripts/check_efc_controller_flows.sh`
  - 增加 contract，防止 EFC association planner 重新直接遍历未过滤的 `group.nodes`
  - 增加 contract，防止 local-only cleanup 再显示成 EFC bindNode

## 验收场景

### 自动验证

1. `bash scripts/check_efc_controller_flows.sh`
2. `git diff --check`
3. `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

### 手动验证

1. EFC1 已关联 Group 1 和 Group 2，Group 1 中有 L1，Group 2 中有 L2。
2. 在 EFC Edit 中取消 Group 1 / Group 2，SAVE 后进入 Sync device(s)，立刻 Stop。
3. 确认 L1 / L2 Group cleanup 失败。
4. 返回 Main - Lights，点击底部同步按钮，完成 L1 / L2 剩余 cleanup。
5. 回到 EFC1 Edit：
   - 如果没有 controller self-config pending，不应继续展示 Devices not synced。
   - 如果仍有本地 pending cleanup，Sync 页面不得显示 EFC1 作为 Group 1/Group 2 的成员。
6. 添加 Group 后 Stop，再从 Lights 页补同步，确认不会引入 EFC 自身的 association task。
7. AC power switch、battery power switch、scene、schedule 做 smoke check，确认本轮没有改变其 group add/delete 行为。

## 需要确认

请确认本轮按上述 EFC-only 方案执行：

- 修 EFC pending stale overwrite。
- 修 EFC association target node 过滤。
- 修 local-only group cleanup UI 显示。
- 不修改 AC power switch、battery power switch、scene、schedule 的业务逻辑，只保留分析结论和 smoke 验证。
