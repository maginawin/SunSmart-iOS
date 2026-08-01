# Proximity/Photocell Group 直接添加后仍需同步根因分析

## 1. 结论

本次“直接把设备添加到 `Proximity/Predictive lighting with photocell` Group 后立即提示设备需要同步”不是设备普遍配置失败，也不是 Cloud Sync 失败。

根因已经定位到 **Fast Add 的 Timed Scheduler 消息重建丢失 `contextGroup`**：

1. Planner 首次创建 Schedule deferred task 时，已经携带目标 Group，能够把自动照明 Group 的 `Auto/On` Schedule 正确路由到 Light LC Scheduler；
2. task 内也保存了这批正确的 `messageHandles`；
3. 但 `DeviceGroupDeferredSyncTask.makeMessageHandles()` 没有使用已保存的 handles，而是通过 `operationType.messageHandles` 再生成一批；
4. 第二次生成没有 `contextGroup`，且新节点此时尚未稳定成为 Group member，于是 Owner 被误判为 ordinary Scheduler；
5. Fast Add 实际把有效 Schedule 写到 ordinary Scheduler，并清空 Light LC Scheduler；
6. 添加结束后，节点已稳定属于自动 Profile Group，严格的 per-Model Need Sync 判断会以 Light LC Scheduler 为 Owner，因此发现真实差异并显示“需要同步”；
7. 用户点击 Sync 后，App 反向清空 ordinary Scheduler，并把相同 Schedule 写到 Light LC Scheduler，随后同步完成。

因此，这是一个真实的 Scheduler Owner 写错位置，不是单纯 UI 误报。

## 2. 日志证据

### 2.1 基础配置、Profile、Scene、Proximity 均有成功响应

添加日志中可以看到：

- AppKey 和 Model Bind 均返回 `Success`；
- Group subscription 返回 `ConfigModelSubscriptionStatus(status: Success)`；
- Profile、Night/Day Scene、`motionSensitivity(62258)`、`proximityLightingNeighborSet` 等均收到成功响应；
- Group Profile 为 type `8`，即 Proximity/Predictive lighting with photocell；
- Site Cloud Sync 返回 HTTP 200 和业务 code 200。

所以不能把此次问题归因于一般 Mesh 超时、Profile 写入失败或云端上传失败。

### 2.2 同一批 Schedule 在 Fast Add 规划阶段被生成两次

添加日志 `564-575` 中，完全相同的 Schedule 生成日志连续出现两遍：

- set index `0`；
- set index `5`；
- delete index `1...4`。

这与当前源码完全对应：

- `makeDeferredTasks` 先用 `schedule.getMessageHandles(node:contextGroup:)` 生成并保存一次；
- `makeTaskCheckpointBatch` 又调用 `task.makeMessageHandles()`；
- `task.makeMessageHandles()` 再从 `operationType.messageHandles` 生成一次。

### 2.3 Fast Add 实际写入了错误 Scheduler Owner

新设备 Primary Unicast 为 `0x002B`，其双 Scheduler 分布为：

- ordinary Scheduler Setup Model：Element `0x002B`；
- Light LC Scheduler Setup Model：Element `0x002D`。

对自动 Profile Group 的 `Auto/On` Schedule，正确 Owner 应是 Light LC Scheduler `0x002D`。

但添加日志显示：

| index | Fast Add 清理目标 | Fast Add 有效 entry 目标 |
|---|---:|---:|
| 0 | `0x002D` | `0x002B` |
| 5 | `0x002D` | `0x002B` |

具体证据：

- `1180-1194`：在 `0x002D` 写入 `noAction`；
- `1195-1209`：在 `0x002B` 写入 index 0 的 `turnOn`；
- `1226-1240`：在 `0x002D` 写入 `noAction`；
- `1241-1255`：在 `0x002B` 写入 index 5 的 `turnOn`。

这些消息都成功返回，但“协议响应成功”不等于“业务 Owner 正确”。

### 2.4 点击 Sync 后，App 把 Owner 反向迁移到正确 Model

Sync 日志只对 Schedule 差异做了实质修复，前后的 `pirEnabled(false/true)` 是普通 Group Profile SAVE 的传感器保护流程，不是此次根因。

Sync 日志显示：

| index | Sync 清理目标 | Sync 有效 entry 目标 |
|---|---:|---:|
| 0 | `0x002B` | `0x002D` |
| 5 | `0x002B` | `0x002D` |

具体证据：

- `110-126`：在 `0x002B` 清理 index 0；
- `128-144`：在 `0x002D` 写入 index 0 的 `turnOn`；
- `166-182`：在 `0x002B` 清理 index 5；
- `184-200`：在 `0x002D` 写入 index 5 的 `turnOn`；
- `285`：同步完成。

前后两份日志形成完整闭环：第一次写反，第二次纠正。

## 3. 源码根因链

### 3.1 Owner 规则本身正确

`Scheduler.swift` 的规则为：

- `turnOn` + automatic Group -> Light LC Scheduler；
- Manual Control Group 或其他 Action -> ordinary Scheduler；
- `contextGroup` 用于新节点尚未稳定进入 Group 时提供有效 membership。

此规则不是本次错误点。

### 3.2 Planner 已生成正确的 context-aware handles

`DeviceGroupDeferredSyncPlanner.makeDeferredTasks` 的 `.syncSchedules` 分支调用：

`schedule.getMessageHandles(node: node, contextGroup: group)`

并通过 `appendTask(... messageHandles:)` 保存到 `DeviceGroupDeferredSyncTask.messageHandles`。

这一步的设计是正确的。

### 3.3 task 重建时丢弃了保存的 handles 和 Group context

`DeviceGroupDeferredSyncTask` 同时存在：

- `messageHandles` 属性；
- `makeMessageHandles()` 方法。

但方法当前返回的是：

`operationType.messageHandles.filter { ... }`

而不是保存的 `messageHandles`。

`DeviceOperationType.messageHandles` 的 `.schedule` 分支又调用：

`schedule.getMessageHandles(node: node)`

这里没有传 `contextGroup`。

因此，Planner 虽然构造了正确句柄，实际 Fast Add batch 却使用了后来无上下文重建的错误句柄。

### 3.4 严格 Need Sync 正确揭示了设备真实差异

当前 `Schedule.schedulerSyncDifference` 会：

1. 根据当前 Group membership 计算 Owner；
2. 检查 Owner Model 是否存在匹配 entry；
3. 检查全部非 Owner Model 是否仍有 residual entry。

Fast Add 后节点已属于 automatic Group，因此 Owner 为 `0x002D` 对应的 Light LC Scheduler。设备实际状态却是：

- Light LC Scheduler：被清空；
- ordinary Scheduler：存在有效 entry。

Need Sync 返回差异是正确行为。如果强行清除 `needSyncGroupData` 或隐藏图标，只会掩盖真实配置错误。

## 4. 为什么感觉“以前修复过，现在又出现”

你的感觉是对的：2026-07-24 确实修复过同一页面、同一 Profile 下的 Fast Add 红色同步图标，但本次不是完全相同的根因。

### 4.1 2026-07-24 修复的根因

提交 `ea1fa257` 修复的是 Fast Add checkpoint 对象身份问题：

- 实际发送列表和 checkpoint 分别生成了内容相同但对象不同的 handles；
- Tracker 使用 `===`，导致 checkpoint 永久 pending；
- 最终显示 `.syncFailed`，但当时 Group 页面按真实设备状态重新计算后可以是正常状态。

该修复通过 batch 让发送列表与 checkpoint 复用同一批对象，解决了当时的身份匹配问题。

### 4.2 2026-07-27 新增的交互条件

提交 `2891ec03` 引入双 Scheduler 单 Owner 规则，并为新 Group member 的 Schedule 生成增加了 `contextGroup`。

但是旧的 `makeMessageHandles()` 重试机制仍然从 `operationType` 无上下文重建 handles，导致新增的 `contextGroup` 只在 task 创建时生效，实际发送时被丢弃。

这就是本次回归的直接引入点：

- 7 月 24 日的对象身份修复本身仍然有效；
- 7 月 27 日加入新的 Scheduler Owner 上下文后，与旧的 handles 重建机制发生了组合冲突；
- 7 月 31 日更严格的 per-Model Scheduler 缓存/Need Sync 判断把真实错误准确显示出来。

所以更准确的结论是：**旧问题的 UI 症状再次出现，但这是后续双 Scheduler 功能引入的跨模块回归，不是 7 月 24 日同一根因原封不动地没修好。**

### 4.3 历史分析中已经出现过风险信号

`docs/260724_1528_proximity_photocell_fast_add_red_icon_followup_analysis.md` 曾指出：task 已保存原始 handles，但 `makeMessageHandles()` 会重新从 operation 生成，并建议复用保存的 handles。

最终确认的 7 月 24 日设计为了保留“每次重试生成全新 handle”的语义，明确没有修改共享 `makeMessageHandles()`。这在当时只处理对象身份时可以成立，但后来加入需要 `contextGroup` 的 Scheduler 路由后，单纯重建 operation handles 已不再保持语义等价。

## 5. 影响范围

本问题不只可能影响 Profile type 8，但该 Profile 最容易稳定复现，因为它存在 index 0 和 5 的自动 `turnOn` Schedule。

高风险条件：

- Classic 或 Professional Fast Add 直接选择 Group；
- 新节点尚未稳定成为 Group member；
- automatic Profile Group；
- 节点有 ordinary + Light LC 两个 Scheduler Setup Models；
- Group 关联了 `turnOn` Schedule；若历史导入数据允许 Scene target 与 `turnOn` 的异常组合，也存在同类风险。

低风险或不受影响：

- Manual Control Group：`turnOn` 的 Owner 本来就是 ordinary；
- 单 Scheduler 设备：Owner 会回退到唯一 Model；
- 没有 Schedule 的 Group；
- 不是通过 Fast Add deferred task 的普通同步页，因为进入同步页时节点 membership 已稳定。

## 6. 最小修复方向

不建议直接让所有重试复用同一个已执行过的 `MeshMessageHandle`，因为 handle 内含响应和运行状态；原有“重试时生成新 handle”要求有合理性。

建议把 deferred task 从“无上下文地重新读取 operation handles”改成“使用 task 自己保存的 context-aware handle factory”：

1. task 创建时保存生成闭包或等价的语义上下文；
2. 普通任务继续通过 operation 创建新 handles；
3. Schedule task 的工厂每次都调用 `schedule.getMessageHandles(node:contextGroup:)`；
4. Fast Add batch 只调用工厂一次，并让实际发送列表与 checkpoint 复用同一批对象；
5. Deferred retry 每次重新调用同一个 context-aware 工厂，继续获得全新对象；
6. 不改变 opcode、payload、Schedule Owner 规则或 Need Sync 严格判定。

## 7. 必须新增的回归测试

现有测试分别覆盖 checkpoint 身份和 Scheduler Owner 策略，但没有覆盖两者的组合边界。至少需要增加：

1. 新节点 `node.group == nil`，传入 automatic `contextGroup` 时，Fast Add 实际 batch 的 `turnOn` 有效 entry 目标必须为 Light LC Scheduler，cleanup 必须为 ordinary Scheduler；
2. 同一任务重试生成的新 handles 仍保持相同 context-aware Owner，但对象身份必须是新实例；
3. Fast Add 实际发送 batch 尾 handle 与 checkpoint 必须为同一实例；
4. Manual Control Group 仍写 ordinary Scheduler；
5. 单 Scheduler 设备仍写唯一 Model；
6. Classic 与 Professional 两条直接加组入口共享同一结果；
7. 点击 Sync 前后不能出现 Scheduler Owner 翻转；
8. Profile、Scene、Proximity、无 Schedule Group 和真实失败路径不回归。

## 8. 当前验证状态

- 两份真机日志已完成逐消息对照，能够证明 Fast Add 写反和 Sync 纠正；
- 当前源码和 Git 历史已完成反向追踪；
- 已按 TDD 补充 Fast Add Scheduler context 传播契约：当前缺陷代码先以 `DeviceOperationType must expose context-aware message generation` 准确失败，实施后通过；
- 已补充 Group-aware、per-Model Schedule 成功判定契约：旧判定先以 `Schedule configuration must verify the owner and cleanup Models` 准确失败，实施后通过；
- `bash scripts/check_fast_add_task_checkpoint_tracker.sh` 通过；
- `zsh scripts/check_timed_scheduler_single_owner.sh` 通过；
- `bash scripts/check_fast_add_dual_scene_verification.sh` 已修复多行匹配并通过；把 Group context 生成断言阈值临时改为错误值时脚本准确失败，恢复后再次通过；
- `git diff --check` 通过；
- `SunSmart`、`Archipelago`、`SylSmart` 三个 scheme 的 Debug generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建均显示 `BUILD SUCCEEDED`；
- 业务改动只涉及 App 内 `DeviceOperationType` 消息生成边界和 `DeviceGroupDeferredSyncPlanner`，未修改 SDK、数据库、云端、UI、本地化、资源、依赖或 target 配置；
- 修复后 Classic、Professional 真机 Fast Add、再次进入 Sync、Scene Recall、无 Schedule Group 和真实失败路径仍待硬件验收，不能仅凭静态测试和 build 宣称完整真机修复完成。

## 9. Scene 关联路径的补充判断

“场景相关联”需要区分三条不同链路：

1. 普通 Scene 与 Group 关联后，新设备加入 Group 时执行 Scene Store；
2. Timed 选择 Scene 作为执行目标；
3. Profile 内置 Day/Night Scene 及其光照触发配置。

### 9.1 普通 Scene Store 不存在本次同根因

Scene deferred task 在规划阶段已经保存具体的 `sceneId` 和 `SceneExecuteData`。实际重新生成消息时，只根据节点能力生成 OnOff、Lightness 或 CTL 设置，再发送 Scene Store；该过程不依赖 `contextGroup`，因此重新生成 handle 不会改变消息语义或目标 Model。

Scene 成功判定也是使用节点已缓存的场景数据与具体 `SceneExecuteData` 比较，不依赖 Group membership。因此，本次 Schedule task 丢失 `contextGroup` 的 Owner 翻转问题不会原样发生在普通 Scene Store。

### 9.2 Timed 选择 Scene 时不会触发当前 Owner 翻转

当前 UI 在 target 为 Scene 时会隐藏 On/Off，只允许并固定生成 `sceneRecall`。Scheduler Owner 策略只有 `turnOn` 且属于 automatic Group 时选择 Light LC Scheduler；`sceneRecall` 一律选择 ordinary Scheduler。

所以即使 Scene 通过 Group 间接包含新设备，Fast Add 重建 Schedule handles 时丢失 `contextGroup`，`sceneRecall` 的 Owner 仍保持 ordinary，不会出现本次日志中 ordinary `0x002B` 与 Light LC `0x002D` 之间的反向写入。

理论例外是历史导入、数据库异常或未来功能允许 Scene target 搭配 `turnOn`。这类非当前 UI 可创建的数据仍会落入相同风险，因为 `turnOn` 的 Owner 继续依赖 Group 上下文。

### 9.3 当前两份日志也不支持 Scene 同步失败判断

Fast Add 日志中 Day/Night 内置场景 `0xFF01`、`0xFF02` 的 Scene Store 和光照触发场景配置均成功发送。随后人工 Sync 的实质纠正集中在 Schedule index 0 和 5：先清理 ordinary Scheduler，再向 Light LC Scheduler 写入有效 `turnOn` entry；没有出现对应 Scene Store 的补写。

因此，就当前代码和这次真机日志而言：普通 Scene、Timed Scene Recall 以及 Profile Day/Night Scene 都没有表现出与本次相同的同步问题；当前应修的是 Fast Add `turnOn` Schedule 的 context-aware handle 重建边界。
