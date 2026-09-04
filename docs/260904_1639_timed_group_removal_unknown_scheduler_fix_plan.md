# Group 移除流程 unknown Scheduler 清理修复计划

## 状态

- 日期：2026-09-04
- 状态：已确认并实施，结果见 `docs/260904_1647_timed_group_removal_unknown_scheduler_fix_summary.md`
- 范围：修复 Cloud 导入等场景下 Scheduler 分 Model 缓存未知时，设备退出 Group 或整组删除会漏掉设备端定时清理的问题

## 问题确认

当前删除策略有意把任一 Scheduler Model 状态未知视为“暂不能判定删除”，因此 `TimedSchedulerDeletePolicy.shouldDelete` 会返回 `false`。这个保护本身正确，可避免只依赖旧的扁平缓存误删。

Schedule 编辑和显式删除入口会在修改目标前调用 `ScheduleServer.readUnknownSchedulerState`，完整读取设备所有 Scheduler Model 的 Register 和 Action；Group 移除入口没有执行同样的前置读取：

1. Group Members 保存时，先把退出设备置为 `.exitFailure`。
2. `SyncDevicesViewController` 随后调用 `Node.getSyncData`。
3. 对原 Group Target 日程，退出状态使其不再命中目标；删除差量转而依赖各 Scheduler Model 的实际 Entry。
4. Cloud 导入节点的 `allSchedulerModelEntrys` 仍为未知时，删除策略返回 `false`，因而不会产生 `.deleteSchedules`。
5. 其他退组任务仍可继续，最终出现 App 已退组但设备端旧定时仍执行。

同一风险还存在于 `GroupServer.deleteGroup`：它会直接为组内节点构造退出消息。因此修复不能只覆盖 Group Members 页面。

## 修复原则

- 保留 unknown 状态不直接生成删除任务的安全策略，不把旧的 `schedulerActions` 兼容投影当作权威数据。
- 把全量 Scheduler 读取作为“开始 Group 移除”的前置条件，而不是普通删除差量或发送任务。
- 只有读取成功且所有 Scheduler Model 都由 unknown 收敛为 known 后，才允许修改成员状态、提交拓扑变更、构建退出任务或删除 Group。
- 读取失败、设备离线或 Mesh 命令繁忙时终止本次操作；缓存继续保持 unknown，以便用户重试。
- 读取成功后保持现有差量语义：Group Target 日程生成删除，仍指向设备的 Device Target 日程按现有 Owner 规则迁移，已知为空则不产生无效写入。
- 不改变现有“日程迁移发送失败不阻断成员退组”的任务策略；本次新增的只是生成可靠差量前必须完成的权威读取。

## 实施步骤

### 1. 复用并收紧 Scheduler 权威读取入口

在 `ScheduleServer` 复用现有 `nodesRequiringAuthoritativeSchedulerRead` 与 `readUnknownSchedulerState`：

- 输入 Group 移除涉及的节点集合，内部只读取至少一个 Scheduler Model 未知的节点。
- 无 Scheduler Model 或所有 Model 已知时立即成功，不增加 Mesh 通信。
- 全量读取使用 `index: nil`，成功条件保持为无失败地址且读取后所有待查 Model 均已知。
- 明确 completion 的线程切换由 UI 调用方回到主线程，避免后台回调直接修改页面或业务状态。

优先复用现有方法，不新增另一套 unknown 判定和读取逻辑。

### 2. Group Members 保存增加前置读取

调整 `GroupMembersViewController` 的保存编排：

- 用户完成必要确认后，对 `exitNodes` 执行 Scheduler 权威读取；仅新增成员时不触发读取。
- 读取放在 `performSave` 之前，因此也早于动能开关 pending-removal 持久化、Proximity Lighting lifecycle commit、`.exitFailure` 标记和同步页创建。
- 读取期间复用已有 `syncing_data` HUD，阻止重复提交。
- 成功后只调用一次原有 `performSave` continuation，不重新弹出确认框。
- 失败时复用 `sync_failed` 提示并留在成员编辑页；成员关系、拓扑、预配置和开关代理待删除状态均不落盘。

### 3. 整组删除增加同一前置读取

调整 `GroupServer.deleteGroup`：

- 在创建 Proximity Lighting 删除事务、调用 `groupDeleteNodes` 和构造退出消息之前，对 `group.nodes` 执行同一权威读取。
- 将读取成功后的原删除实现拆成私有 continuation，避免用递归重新进入公开入口、重复检查或重复回调。
- 读取失败时只调用现有 `failed` 回调，不发送退组、场景、日程或拓扑消息，也不删除本地 Group 数据。
- `groupDeleteNodes` 当前只有 `deleteGroup` 生产调用方，保持其同步消息构造职责，不在同步的 `getNodeExitMessageHandles` 中伪造异步读取。

这会同时覆盖 Groups 列表和 Group 详情页发起的整组删除。

### 4. 补充回归契约

扩展 Timed Scheduler 测试：

- Policy 测试增加 Cloud 导入典型状态：所有 Scheduler Model 都未知时必须要求权威读取。
- 保留并继续验证：unknown 且旧兼容 Entry 有效时不能直接判定删除。
- Timed 集成契约读取 `GroupMembersViewController`，断言退出节点先完成权威读取，成功后才进入 `performSave`，失败分支不能触发成员/拓扑提交。
- 断言 `GroupServer.deleteGroup` 在 lifecycle transaction、`groupDeleteNodes` 和 `getNodeExitMessageHandles` 之前完成权威读取，失败时直接结束。
- 调整 `scripts/check_timed_scheduler_single_owner.sh` 的参数，纳入 Group Members 源码；该脚本必须使用 zsh 执行。
- 保持现有 Group lifecycle 契约，锁定连接检查和 lifecycle commit 仍早于 `.exitFailure` 等既有顺序要求。

建议先写会在当前实现上失败的契约，再实施业务修复，以证明测试确实捕获此次遗漏。

## 验证计划

### 自动化验证

1. `zsh scripts/check_timed_scheduler_single_owner.sh`
2. `bash scripts/check_path_topology_persistence.sh`
3. `git diff --check`
4. 对五个共享 App scheme 分别执行 generic iPhoneOS、Debug、关闭签名构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。

当前基线中前两组契约均通过，说明现有测试尚未覆盖该回归；新增契约应先在未修复代码上失败。

### 真机验收矩阵

至少使用一个包含 ordinary Scheduler 和 Light LC Scheduler 的真实灯具验证：

| 场景 | 预置状态 | 期望结果 |
| --- | --- | --- |
| Group Members 退出 | Cloud 导入，所有 Model 缓存 unknown，Group Target 日程有效 | 先完整读取，再生成对应 `.deleteSchedules`；退出后原定时不再执行 |
| Group Members 退出 | 一个 Model 已知、一个未知 | 必须读取未知 Model 后再生成差量，不得直接退组 |
| Group Members 退出 | 所有 Model 已知为空 | 不生成日程删除写入，其他退组任务正常执行 |
| Group Members 退出 | Device Target 日程仍指向该设备 | 按退出后的 ordinary Owner 规则同步/迁移，不能被当作 Group Target 删除 |
| 整组删除 | Cloud 导入且缓存 unknown | 先读取所有受影响节点，再删除设备侧日程和 Group |
| 权威读取失败 | ACK 超时、断连或 Mesh busy | 不置 `.exitFailure`，不提交拓扑或本地成员变更，提示失败并可重试 |
| 权威读取部分失败 | 多节点中至少一个读取失败 | 整次 Group 变更不开始；成功节点缓存可保留，失败节点下次继续读 |
| 读取后发送失败 | 权威读取成功，后续日程迁移/删除消息失败 | 沿用现有同步页失败与退组策略，不把读取失败和发送失败混为一类 |

真机需读取每个 Scheduler Model 的 0～15 号 Entry，并结合设备实际触发观察确认；编译、契约测试和 Mesh ACK 不能替代定时不再执行的最终验收。

## 预计改动文件

- `SunSmart/Main/Timed/Model/ScheduleServer.swift`
- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift`
- `SunSmart/Main/Group/Model/GroupServer.swift`
- `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`
- `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`
- `scripts/check_timed_scheduler_single_owner.sh`

预计不修改 NordicSigMeshSDK、项目 target 配置、资源或本地化文件。

## 风险与边界

- 退出包含 Scheduler 能力但本地缓存未知的设备时，会新增一次全量读取，可能增加操作等待时间；这是避免残留定时所需的确定性成本。
- 不应在读取前提交任何可见业务状态，否则读取失败会留下“本地已退组、设备未清理”的新型部分提交。
- 多节点读取必须整体作为开始 Group 变更的门槛，不能让已读取成功的节点先行退出。
- 本方案只修复 Group 成员退出和整组删除的 Scheduler unknown 前置条件，不扩展到无关的 Cloud/Proximity Lighting 重构。
