# Fast Add Scheduler Group 上下文重建修复设计

## 1. 文档状态

- 状态：用户已确认
- 日期：2026-08-01
- 范围：iOS App 内 Fast Add 与 Group Deferred Sync
- 前置分析：`docs/260801_1128_proximity_photocell_direct_add_scheduler_owner_regression_analysis.md`

## 2. 问题摘要

设备通过 Classic 或 Professional Fast Add 直接加入 automatic Profile Group 时，新节点的 `node.group` 可能尚未稳定。Planner 初次为 `turnOn` Schedule 生成消息时传入了目标 Group，因此能够选择 Light LC Scheduler；但实际组装 Fast Add batch 或执行 deferred retry 时，task 会从不带 Group 上下文的 `operationType.messageHandles` 重新生成消息，Owner 被错误地改判为 ordinary Scheduler。

设备虽然对错误 Model 上的 Mesh 消息返回成功，但进入 Group 后，严格的 per-Model Need Sync 会识别出 Owner entry 缺失和非 Owner residual entry，因此提示设备仍需同步。

## 3. 目标

1. Fast Add 首次发送和每次 deferred retry 都使用同一目标 Group 解析 Schedule Owner。
2. 同一个 Fast Add batch 内，实际发送 handles 与 checkpoint 必须复用完全相同的对象实例。
3. 不同 retry 必须重新创建 handles，不能复用已经执行并携带响应状态的对象。
4. ACK 成功后使用 Group-aware、per-Model Schedule 状态确认业务同步成功，不能只检查合并后的 `schedulerActions`。
5. 修正失效的 `check_fast_add_dual_scene_verification.sh`，让测试能够覆盖本次跨边界回归。
6. Classic 与 Professional 继续共享同一个 Planner 行为。

## 4. 明确不在范围内

- 不修改 NordicSigMeshSDK。
- 不修改 Scheduler Owner 业务规则。
- 不修改 opcode、payload、消息顺序、超时或最大 retry 次数。
- 不修改数据库结构或历史数据迁移。
- 不修改云端接口、上传数据或同步状态协议。
- 不修改 UI、文案、本地化、资源、依赖或 target 配置。
- 不通过隐藏 Need Sync、清理 dirty state 或放宽 per-Model 比较掩盖设备真实差异。

## 5. 方案比较与决策

### 5.1 采用：显式的 context-aware 消息生成 API

为 `DeviceOperationType` 提供能够接收可选 `contextGroup` 的消息生成入口。现有 `messageHandles` 属性继续作为无上下文兼容入口；Fast Add 和 deferred retry 显式调用 context-aware 入口。

优点：

- Group 依赖在类型和调用点上可见；
- 普通 Sync 调用保持兼容；
- retry 每次自然生成新 handles；
- 后续其他 Group-sensitive 操作可以复用同一边界；
- 无需在 task 中保存隐藏闭包。

### 5.2 不采用：task 保存消息生成闭包

闭包能够把 Group 捕获到 task 中，改动范围较集中，但依赖关系不可从类型签名直接识别，也更难进行源码契约检查。Node、Group 和 Schedule 的隐式捕获会增加后续维护成本。

### 5.3 不采用：直接复用 task 已保存的 handles

该方案改动最小，却会让 deferred retry 复用已经执行过的 `MeshMessageHandle`。handle 中存在响应和运行状态，复用会破坏 retry 的独立性，因此不满足修复目标。

## 6. 架构设计

### 6.1 DeviceOperationType 消息生成边界

`DeviceOperationType` 增加显式的 context-aware 消息生成方法：

- 默认 `contextGroup` 为空，保持所有现有调用行为；
- Schedule configuration 分支把 `contextGroup` 继续传递给 `Schedule.getMessageHandles`；
- 非 Schedule 分支保持现有生成逻辑；
- 原 `messageHandles` 计算属性委托给无上下文方法，避免一次性修改所有普通同步调用点。

### 6.2 DeviceGroupDeferredSyncTask 语义

Task 只持有可重新生成消息的业务操作，不再把预先创建的一批 handles 当作 retry 数据源。

Task 提供两个 Group-aware 行为：

1. 根据 `operationType` 和 `contextGroup` 创建当前 attempt 的新 handles，并保留现有 Scene Recall 过滤；
2. 根据 `operationType` 和 `contextGroup` 验证当前业务操作是否真正同步。

Schedule configuration 使用 `schedule.needsSync(on:contextGroup:)` 的反向结果；Schedule delete 使用 model-aware 删除差异判断；其他任务继续使用现有 `operationType.isSuccessful`。

### 6.3 Fast Add batch

Fast Add 创建 task checkpoint batch 时传入目标 Group。每个 task 在该步骤只生成一次 handles：

- 生成结果加入实际发送列表；
- 同一数组的最后一个 handle 作为 checkpoint；
- checkpoint 在回调更新 Node 和具体 Model 缓存后，执行 Group-aware 业务状态验证。

这保证同一 batch 内发送对象与 checkpoint 对象身份一致。

### 6.4 Deferred retry

`runTaskAttempt` 每个 attempt 都使用传入的目标 Group 调用 task 的消息生成方法。递归 retry 会再次调用生成方法，因此得到全新 handle 对象，但 Schedule Owner、cleanup Model 和 payload 语义保持一致。

`runTasks` 不应预生成并丢弃一批 handles；空消息任务由 attempt 层按现有成功语义处理，避免一次无意义的重复生成。

## 7. 数据流

### 7.1 Fast Add 首次发送

Group sync data → semantic deferred task → 使用目标 Group 生成 handles → 同一批 handles 同时进入发送列表和 checkpoint tracker → Mesh 回调按 handle 的具体 Model 更新缓存 → Group-aware checkpoint 验证 → 生成 Fast Add 最终状态。

### 7.2 Deferred retry

Semantic deferred task → attempt 读取同一目标 Group → 创建全新 handles → 发送并更新具体 Model 缓存 → Group-aware operation 验证 → 成功结束或进入下一 attempt。

### 7.3 automatic Group 的正确 Schedule 路由

新节点尚无稳定 Group → contextGroup 提供 automatic membership → `turnOn` Owner 为 Light LC Scheduler → ordinary Scheduler 收到 cleanup entry → Light LC Scheduler 收到有效 entry。

## 8. 失败处理

1. Mesh ACK 失败：保持现有 retry 流程和最大重试次数。
2. ACK 全部成功但正确 Owner 缺失：业务验证失败并 retry。
3. 正确 Owner 匹配但非 Owner 存在 residual entry：业务验证失败并 retry。
4. 最后一次 retry 仍失败：保留真实失败状态，清理同步状态缓存并重新计算 Group Need Sync。
5. 空 handles：沿用当前无消息即无需执行的成功语义。
6. Scene Recall：继续从 deferred 配置发送中排除，不改变现有行为。
7. 不以 HTTP 200、单条 Mesh ACK 或 iOS build 成功替代最终业务验收。

## 9. 文件边界

### 9.1 业务代码

- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 增加 `DeviceOperationType` 的 context-aware 消息生成入口；
  - Schedule configuration 传递 Group 上下文；
  - 保留 `messageHandles` 的兼容行为。

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - task 改为按 Group 上下文生成每次 attempt 的新 handles；
  - Fast Add batch 传入目标 Group，保持发送对象与 checkpoint 身份一致；
  - retry 传入同一 Group；
  - Schedule 使用 model-aware、Group-aware 成功判定；
  - 删除无意义的预生成和被丢弃的 handles。

### 9.2 测试与脚本

- `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`
  - 增加 Fast Add batch、deferred retry 和 Schedule verification 的 Group 上下文接线契约；
  - 禁止 task 通过无上下文属性重建 Schedule handles；
  - 保留 Owner、cleanup 和历史入口契约。

- `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
  - 复用并补强同一 batch 的尾 handle 身份测试；
  - 验证等价但不同实例不能错误完成 checkpoint。

- `scripts/check_fast_add_dual_scene_verification.sh`
  - 修复 Classic/Professional 多行调用导致的脆弱匹配；
  - 串联 checkpoint tracker 与 Timed Scheduler context 契约；
  - 增加 Fast Add batch 和 retry 必须传 Group 的检查；
  - 保留 Profile、Scene、Proximity、空 Path 和真实失败检查。

- `scripts/check_timed_scheduler_single_owner.sh`
  - 原有执行入口保持不变；若新增测试输入文件，再只补充明确的文件参数。

## 10. 回归测试矩阵

| 场景 | 期望 Owner | 期望 cleanup | 期望结果 |
|---|---|---|---|
| 新节点 + automatic Group + turnOn | Light LC | ordinary | 首次添加后无需再次 Sync |
| 新节点 + Manual Control Group + turnOn | ordinary | Light LC | Owner 不翻转 |
| Scene Recall | ordinary | Light LC | 不受 Group membership 影响 |
| 单 Scheduler Model 设备 | 唯一 Model | 无可清理 Model | 正常回退 |
| automatic Group retry | Light LC | ordinary | 每次新 handle、相同语义 |
| 正确 Owner + 非 Owner residual | Light LC | ordinary residual 必须清除 | 仍判 Need Sync |
| 无 Schedule Group | 不适用 | 不适用 | 不新增 Schedule 消息 |
| 普通 Scene Store | Scene Setup Model | 不适用 | 场景同步不回归 |
| Proximity 空邻居/空 Path | 不适用 | 不适用 | 保持当前成功语义 |
| 真实 ACK 或状态校验失败 | 按目标计算 | 按目标计算 | retry 后仍失败则保留失败状态 |

Classic 与 Professional 两个入口都必须执行上述 automatic Group 主路径；Profile type 8 作为主验收样本，其他 automatic Profile 作为影响范围抽样。

## 11. 验证层级

### 11.1 静态与可执行契约

1. Fast Add checkpoint tracker 测试通过；
2. Timed Scheduler Owner policy 测试通过；
3. Timed Scheduler single-owner contract 测试通过；
4. 修正后的 Fast Add dual-scene/task-scoped verification 脚本通过；
5. `git diff --check` 通过。

### 11.2 iPhoneOS 构建

直接使用 `xcodebuild` 和 generic iPhoneOS destination，验证共享源码覆盖的 `SunSmart`、`Archipelago`、`SylSmart` scheme。不得使用 Simulator 或 shell 包装重定向日志。

### 11.3 真机 Mesh 验收

1. Classic 直接添加设备到 Proximity/Predictive Lighting with Photocell Group；
2. Professional 重复同一路径；
3. 添加日志中 index 0、5 首次即清理 ordinary Scheduler，并向 Light LC Scheduler 写有效 entry；
4. 添加完成后设备不显示 Need Sync；
5. 再进入 Sync 页面不产生 ordinary → Light LC 的反向迁移；
6. 验证 Scene Recall、普通 Scene Store 和无 Schedule Group 不回归；
7. 验证真实失败仍能显示失败并保留同步入口。

## 12. 完成标准

- 首次 Fast Add 不再把 automatic Group 的 `turnOn` Schedule 写入 ordinary Scheduler；
- Fast Add 与普通 Group Sync 对同一节点计算出相同的 Scheduler Owner 真值；
- 同一 batch 的发送/checkpoint 对象身份与不同 retry 的对象独立性同时成立；
- ACK 成功但 Model Owner 错误不能被判为业务成功；
- 所有静态测试和目标 scheme generic iPhoneOS build 通过；
- 真机日志闭环证明首次写入正确，且无需点击 Sync 二次迁移；
- 未修改 SDK、数据库、云端、UI、本地化、资源、依赖或 target 配置。
