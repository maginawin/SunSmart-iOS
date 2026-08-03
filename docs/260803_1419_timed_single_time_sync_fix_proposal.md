# Timed 单设备单次校时修复方案（待确认）

## 1. 目标与范围

本方案针对常规 Timed 日程在多条同步、Fast Add、设备恢复和多设备批量保存时重复生成 `Time Set`，并可能因消息提前构造、排队后再次写入旧时间而造成设备时钟偏移的问题。

目标状态：

1. 同一个设备在同一轮日程写入中最多执行一次校时；
2. 校时消息在真正发送边界刷新时间，而不是在计划、UI Task 或 checkpoint 建立时固定时间；
3. 校时成功后才允许继续写入该设备的启用日程；
4. 校时失败必须形成可见失败，不能仅凭 Scheduler Action ACK 把整轮同步判为成功；
5. 删除日程、仅同步禁用日程或设备没有 Time Model 时，不额外生成校时任务；
6. 保持现有 Scheduler 单 Owner、非 Owner cleanup、Group 退出清理和 Fast Add checkpoint 身份语义不变。

原“删除 Group 1，再把设备加入 Group 2”的设备日程清理链路在完整成功态下已经符合预期，本次不重写 Group 删除事务。该场景作为核心回归用例：删除成功后全部 Scheduler Model 中无有效 Entry；加入 Group 2 成功后每个 index 仅有一个 Group 2 对应 Owner Entry。

## 2. 方案比较

### 方案 A：单次校时任务 + 发送边界动态刷新（推荐）

- App 层把校时从单个 `Schedule` 的消息构造中移出，按“设备 + 本轮同步”只规划一次独立任务；
- SDK 的 `MeshMessageHandle` 保持对象身份不变，但允许指定消息在每次真实发送/重试前刷新；
- 普通代理队列与 Fast Add 附加消息队列都在各自发送边界执行刷新；
- 校时任务作为全部启用日程写入的前置条件。

优点：同时解决重复消息、Fast Add 旧时间、连接等待和 busy 重试后的旧时间；不会破坏依赖同一 handle 实例的 Fast Add checkpoint。

代价：需要对本地 `NordicSigMeshSDK` 增加一个小而通用的动态消息能力，并验证四个品牌 target。

### 方案 B：App 内每设备只保留一条预构造 Time Set，并放到队列最前

- 不改 SDK；
- 每个设备只创建一条 Time Set，并尽量排在 Schedule 消息之前。

优点：改动较小，能消除 16 条 Time Set 在队列中反复把时钟拨回的问题。

缺点：Time Set 在回调或计划阶段仍已固定；Mesh 未连接、共享队列繁忙或 Fast Add 延迟时，构造到实际发送的等待仍会直接变成时钟误差。只能降低风险，不能满足“真正执行时取当前时间”。

### 方案 C：保留每日程一条 Time Set，但在发送时动态刷新

- 给现有每条 Time Set 增加发送时刷新；
- 不改变日程任务数量和依赖结构。

优点：可以消除固定旧时间问题，业务编排改动较小。

缺点：16 个日程仍有 16 次 ACK 校时，双 Scheduler Model 时仍至少有 48 条日程相关消息；同步耗时、失败面和设备压力都没有解决，不符合“每设备每轮一次”的语义。

## 3. 推荐方案的核心设计

### 3.1 两层职责分离

App 负责决定“是否需要校时、每个设备本轮需要几次、与哪些任务存在依赖”；SDK 只负责保证动态消息在真实发送或重试前取最新值。

不让 `Schedule.getMessageHandles` 隐式插入 Time Set。该方法只负责：

1. 清理所有非 Owner Scheduler Model 的相同 index；
2. 向唯一 Owner Scheduler Model 写入 Scheduler Action Set；
3. 删除时向全部 Scheduler Model 写入无效 Entry。

新增统一的 Timed 校时策略，满足下列条件时返回一条动态 Time Set handle：

- 本轮至少有一个需要写入的启用日程；
- 设备存在 Time Model；
- 本轮尚未为该设备规划校时。

以下情况返回零条：

- 纯删除日程；
- 只写禁用日程；
- 设备没有 Time Model；
- 本轮已存在该设备校时任务。

### 3.2 SDK 动态消息句柄

在本地 `NordicSigMeshSDK` 为 `MeshMessageHandle` 增加可选的“发送前刷新消息”能力：

- 固定消息保持当前行为；
- 动态 Time Set handle 在真实发送前，用当时的 `Date` 和 `TimeZone.current` 重建 Time Set；
- busy 或显式重试再次发送时再次刷新；
- handle 本身不替换，因此 `===` 身份、Fast Add checkpoint、成功/失败回调和目标 Model 均保持不变。

必须接入两个真实发送边界：

1. `MeshMessageManager` 从内部队列取出 handle、准备序列化之前；
2. `MeshFastAddDeviceOperation` 发送当前 append handle 之前。

不把动态时间放在 `parameters` 的普通读取中生成，避免日志、去重或响应匹配等非发送访问意外改变 payload。

### 3.3 普通 Sync Devices

在同一设备的 Schedule step 中增加一个独立的 `Sync Time` task，并让所有启用日程配置 task 依赖它：

1. `Sync Time` 成功：继续串行执行日程 cleanup 和 Owner Set；
2. `Sync Time` 失败：依赖的启用日程保持未执行并把整个 Schedule step 标记失败；
3. 删除任务与禁用日程不依赖校时，可以继续执行；
4. 重试任一依赖校时的日程时，本轮同时重置并重新执行一次 `Sync Time`，其 payload 在发送时刷新；
5. UI 增加 English 和简体中文本地化，任务详情能区分“时间同步失败”与“日程写入失败”。

Group 退出迁移保持现有非阻断边界：Time Set 或日程迁移失败可以让日程同步显示失败，但不能因此阻止 Group subscription 清理和本地退出完成；纯删除日程仍不需要 Time Set。

### 3.4 Deferred Sync 与 Device Restore

`DeviceGroupDeferredSyncPlanner` 在首个启用日程任务前插入一次校时任务，后续 Schedule task 不再各自携带 Time Set。每次 task attempt 都重新生成 handle，SDK 又在发送边界刷新 payload。

`DeviceRestoreViewController` 当前会在建立 deferred task 时保存已构造 handles，方案中改为保存语义任务，在每次执行/重试时生成 handles：

- 每设备的启用日程恢复前只插入一个校时任务；
- Time Set 失败后不执行后续启用日程；
- 重试使用新的发送时刻；
- Scene Recall 过滤、响应追踪和现有恢复失败展示保持不变。

### 3.5 Fast Add

Fast Add 计划中为每个设备插入一条动态 Time Set handle，并放在该设备首个启用 Schedule task 前：

1. Group subscription、Profile 和前置 Scene 按现有顺序执行；
2. Time Set 发送成功后才进入日程 cleanup/Owner Set；
3. Time Set 设置为该设备日程段的中止点，失败时后续 Schedule 不发送，并把设备标为 `syncFailed`；
4. 动态刷新只替换 handle 内部消息，不创建第二套 handle；
5. `FastAddTaskCheckpointBatch` 仍只组装一次并复用完全相同的 handle 实例，避免恢复历史上的 checkpoint 身份不匹配问题。

Classic 和 Professional 两条入口使用同一 planner，不分别实现校时规则。

### 3.6 ScheduleServer 与批量入口

`ScheduleServer.saveSchedule` 可能一次保存到多个设备。不能把所有设备放在一个“Time Set 失败即中止全队列”的批次中，建议改为按设备顺序执行独立小批次：

- 每个设备：可选的一条动态 Time Set + 该设备的 Schedule cleanup/Owner Set；
- 当前设备校时失败时跳过它的 Schedule 写入、记录该设备失败，然后继续下一个设备；
- 最终聚合全部设备结果决定保存成功或失败。

同时收口以下批量构造入口，避免绕开统一策略：

- `NodeSyncData.syncSchedules`；
- `Group.getNodeAddMessageHandles`；
- 节点恢复消息构造；
- 所有直接调用 `Schedule.getMessageHandles` 的生产路径。

SDK 自带的 `MeshScheduleServer` 保持“一设备一次”的业务规则，但其 Time Set 也使用发送边界刷新能力，避免多设备批量时后部设备拿到旧时间。

### 3.7 失败真值与日志

成功条件：动态 Time Set 收到匹配设备的 Time Status，且后续所有目标 Scheduler Model 操作满足现有单 Owner 权威状态检查。

不把以下单点当作整轮成功：

- Time Status 成功但 Scheduler cleanup/Owner Set 失败；
- Scheduler Action Status 成功但 Time Set 失败；
- Fast Add append 消息发送完成但 checkpoint 尚未全部验证；
- 本地缓存看似一致但权威读取仍有非 Owner 残留。

DEBUG 日志只记录 Node、同步入口、队列等待时长、Time Set 刷新/发送时间、Time Status 接收时间和失败阶段，不记录 AppKey、NetKey 或其他认证数据。

## 4. 计划修改范围

### 4.1 本地 NordicSigMeshSDK

- `MeshMessageManager.swift`：支持动态消息保持 handle 身份，并在代理发送边界刷新；
- `MeshFastAddDeviceManager.swift`：在 append 消息真实发送/重试前刷新；
- `MeshScheduleServer.swift`：使用动态 Time Set；
- SDK 聚焦测试：固定 handle 不受影响、动态 handle 每次发送刷新、重试刷新且对象身份不变。

工程目前已经引用本地 SDK 路径；实施时会保留这一现状，不修改依赖来源或新增认证信息。

### 4.2 SunSmart App

- `Node+MessageHandles.swift`：移除单 Schedule 内隐式 Time Set，提供统一的日程消息与单次校时组装策略；
- `SyncDevicesCellModel.swift`、`SyncDevicesViewController.swift`：增加独立校时 task、依赖和重试语义；
- `DeviceGroupDeferredSyncPlanner.swift`：Deferred/Fast Add 每设备插入一次校时并保留 checkpoint identity；
- `DeviceRestoreViewController.swift`：deferred restore 改为执行时生成 handles；
- `ScheduleServer.swift`：按设备执行独立日程批次并聚合结果；
- `GroupServer.swift`、`MeshNetwork+SunSmart.swift`：接入统一批次策略；
- `Localizable.strings`：同步 English、简体中文可见文案；
- Timed 与 Fast Add 聚焦契约测试和检查脚本。

当前 worktree 中 `SyncDevicesViewController.swift`、`DeviceRestoreViewController.swift` 和工程配置已有其他未提交改动。实施时只在现有内容上做最小增量，不覆盖、回退或格式化这些无关修改。

## 5. 测试与验收矩阵

### 5.1 自动化契约

1. 同设备 16 个启用日程：恰好 1 个 Time Set task；
2. 同设备 16 个禁用日程：0 个 Time Set task；
3. 启用/禁用混合：1 个 Time Set task；
4. 纯删除：0 个 Time Set task；
5. 无 Time Model：0 个 Time Set task，日程写入保持当前兼容行为；
6. 多设备：每个符合条件的设备各 1 个，不按 Group 或 Scheduler Model 合并；
7. Time Set 位于首个启用 Schedule 写入前，失败会阻断本设备后续启用日程；
8. 重试会刷新 Time Set 时间，且 Fast Add tracker 仍能用同一 handle 身份命中 checkpoint；
9. 单/双 Scheduler Model 的 cleanup → Owner Set 顺序与 `needsSync`/`needsDelete` 权威检查不变；
10. Group 退出时删除日程不依赖校时，日程迁移失败不阻断 Group 退出；
11. ScheduleServer 某一设备校时失败只跳过该设备，不吞掉其他设备的批次结果；
12. 固定消息句柄的去重、响应匹配、ACK、busy retry 行为无回归。

### 5.2 静态与构建验证

- 新增/更新 SDK 单元测试；
- 运行 Timed 单 Owner、持久化、Fast Add checkpoint 等现有聚焦脚本；
- `git diff --check`；
- 按项目要求直接使用 `xcodebuild`，依次验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 generic iPhoneOS Debug build，不使用 Simulator。

### 5.3 真机 Mesh 验收

至少覆盖：

- 普通 Sync Devices：1 条、16 条启用、启用/禁用混合；
- 单 Scheduler Model 与 ordinary + Light LC 双 Scheduler Model；
- Fast Add Classic、Fast Add Professional、Device Restore、单日程编辑、多设备保存；
- Group 1 删除后加入 Group 2 的原始场景；
- Mesh 未连接后重连、队列繁忙、Time Set ACK 失败、cleanup 失败、Owner Set 失败；
- 同步完成后读取 Time Status、Scheduler Register 和 0～15 Action。

最终验收要求：

- 每设备每轮只实际发送一次 Time Set；
- 日志中的 Time Set payload 对应真实发送时刻，而不是计划建立时刻；
- Group 1 删除成功后全部 Scheduler Model 均无有效 0～15 Entry；
- Group 2 同步成功后每个 index 仅一个有效 Owner Entry，日程 1 使用修改后的时间；
- 设备时间与手机时间偏差满足产品既定容差。当前源码没有定义具体秒数，真机验收前需由产品/固件共同确认容差，不在代码中自行假定。

## 6. 明确不做

- 不把 16 条 Scheduler 写入改成设备侧原子事务；SIG Scheduler 本身仍是逐条配置，同步过程中仍可能存在部分生效窗口；
- 不改变 Group 删除时 App 全局 Schedule 对象的保留规则；删除 Group 1 只移除其关联地址，仍被 Group 2 使用的 Schedule 必须保留；
- 不修改 Scheduler Owner 选择规则；
- 不把 Time Get 强制加入每次生产同步。第一阶段用 Time Status ACK 和真机验收确认；若后续需要持续时钟漂移监控，再单独设计周期性 Time Get；
- 不顺手重构其他 Mesh 队列或设备恢复模块。

## 7. 待确认决策

建议确认并采用方案 A，按以下失败策略实施：

> 同一设备每轮日程写入最多校时一次；Time Set 在真实发送/重试边界刷新；Time Set 失败则阻断该设备本轮后续启用日程，但不阻断纯删除日程，也不阻断 Group 退出清理。

确认后再编写逐步骤实施计划，并按 Superpowers 的 Inline Execution 在当前会话执行；未经确认不修改业务代码或 SDK。
