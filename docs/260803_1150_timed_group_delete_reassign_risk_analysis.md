# Timed 日程在删除 Group 后重新分组的风险分析

## 1. 分析范围

分析以下操作在当前 `fix` worktree 与本地 `NordicSigMeshSDK` 实现下的实际行为：

1. 创建 Group 1、Group 2 和 16 个间隔 1 分钟的日程，每个日程同时关联两个 Group；
2. 将设备加入 Group 1，并修改日程 1 的时间；
3. 删除 Group 1，再将设备加入 Group 2，观察设备执行情况。

本报告只做源码与聚焦契约测试分析，没有修改业务代码，也没有进行真机、真实 Mesh 射频环境或设备固件验收。

## 2. 结论

### 2.1 最终成功态

如果“修改日程 1”“删除 Group 1”“加入 Group 2 并同步”三个操作都明确成功，则设备最终应只保留 Group 2 当前关联的 16 个日程，不应存在 Group 1 和 Group 2 各自占用一套日程的情况，也不应保留日程 1 的旧时间。

原因是：

- App 的 16 个日程是 Space 级全局对象，id 固定为 0～15；两个 Group 关联的是同一批日程，不是 32 个独立日程。
- SIG Scheduler Entry 本身不保存 App Group 地址。Group 只用于 App 判断某个设备是否应拥有该 Entry。
- 删除 Group 1 时，当前实现会先把退出设备上每个相关 index 在全部 Scheduler Setup Model 中写成无效 Entry，再删除 Group subscription，最后才删除本地 Group。
- 设备加入 Group 2 时，会按相同的 0～15 index 重建 Entry；写入前先清理非 Owner Scheduler Model，再写唯一 Owner Model。
- 修改日程 1 修改的是全局日程对象。Group 2 后续拿到的是修改后的时间，不存在一份“Group 1 旧时间”和一份“Group 2 新时间”。

因此，成功完成后的稳态不应出现“同一个日程因两个 Group 而执行两次”。

### 2.2 仍可能观察到异常的条件

这套流程不是设备侧原子事务。16 个日程会被逐条、逐 Model 发送，因此以下现象是可能的：

1. **删除或加入过程中仍有日程执行**
   - 删除 Group 1 时，尚未轮到清理的 index 仍是有效 Entry。
   - 加入 Group 2 时，已经写入成功的 index 会先于后续 index 生效。
   - 16 条日程间隔只有 1 分钟，如果同步跨过执行分钟，过程态中的旧 Entry 或已写入的新 Entry 可能被触发。
   - 这属于同步过程的非原子窗口，不能仅凭同步期间的一次动作断定最终存在两套日程。

2. **失败后设备只保留部分日程或新旧 Entry 混合**
   - Scheduler Action Set、Time Set 或 Group subscription 任一消息超时/失败，都可能发生前面若干条已成功、后面若干条尚未执行的部分状态。
   - 正常 UI 应显示同步失败或待重试；此时不能继续按“删除完成”或“加入完成”验收。
   - 删除 Group 的正常成功回调要求该设备本轮所有消息成功；失败时本地 Group 不应被当作已成功删除。

3. **多 Scheduler Model 的短暂双 Owner 风险**
   - 当前正常写入会先清理全部非 Owner Model，再写 Owner Model；正常成功后每个 index 只应有一个有效 Owner Entry。
   - 如果设备原本已有残留 Entry，且清理非 Owner Model 失败、Owner 写入成功，则过程态可能同时存在两个有效 Entry。当前同步任务会因消息失败而标记失败，但设备在重试完成前可能处于双 Owner 状态。
   - 在本测试的干净成功路径中，Group 1 删除会先清理全部 Scheduler Model，所以不应产生该状态。

4. **设备时钟同步失败或批量发送导致时间偏移**
   - 每个启用日程写入前都会先发送 Time Set，再发送 Scheduler Entry。
   - Group Members 的 Sync Devices 路径按日程任务串行构造并发送 Time Set，而且 Time Set 是该日程任务的第一条消息。前面日程任务的排队不会让当前 Time Set 预先老化；设备收到 Time Set 后时钟会继续运行，后续 cleanup/Owner Set 的耗时本身不会继续增加时钟偏差。真正需要关注的是 Time Set 从构造到设备接收之前的连接、共享队列或发送延迟。
   - Fast Add 路径会先批量构造 deferred message handles，多个 Time Set 的时间值可能早于各自真实发送时刻。消息队列较长时，最终设备时钟可能落后于手机当前时间。
   - Time Set 失败而 Scheduler Entry 成功时，该任务整体应显示失败；在重试前，日程内容可能正确但设备时钟仍不正确。

### 2.3 对“删除 Group 1 时删除所有相关日程”的准确解释

这里需要区分两层数据：

- **设备层**：退出 Group 1 的设备应删除 0～15 号 Scheduler Entry；这是本场景的核心预期。
- **App 层**：因为同一批日程仍关联 Group 2，所以不能把 16 个全局日程对象全部删除。App 只移除每个日程中的 Group 1 地址，保留 Group 2 地址和日程定义。

因此正确结果是：删除 Group 1 成功后、设备尚未加入 Group 2 前，App 中仍应看到 16 个属于 Group 2 的日程，但该设备上暂时不应有这些有效 Entry；加入 Group 2 同步成功后，再把同一批 Entry 写回设备。

## 3. 当前源码状态链

### 3.1 16 条日程不是两组各 16 条

- `MeshNetwork+SunSmart.swift:731-738` 只分配 0～15 共 16 个全局日程 id。
- `Scheduler.swift:123-132` 保存的是日程目标 Group 地址列表；两个 Group 只是同一日程的两个目标。
- `SchedulerRegistryEntry` 不包含 App Group 地址，因此设备侧无法按 Group 保存两份同 index Entry。

同一个 Scheduler Model 内，对相同 index 的再次写入是覆盖，不是追加。

### 3.2 修改日程 1

- `ScheduleAddViewController.swift:363-425` 先更新同一个 `Schedule` 对象的时间并保存，再根据设备缓存差异进入同步页面。
- `MeshNetwork+SunSmart.swift:1564-1611` 按 Owner Model、Entry 内容和非 Owner 残留判断是否需要同步。
- `Node+MessageHandles.swift:448-472` 写入时先发 Time Set，再清理非 Owner Model，最后写 Owner Entry。

若修改同步成功，设备和 App 都是新时间；若失败，App 已保存新时间，但设备可能仍是旧时间，UI 必须保留失败/待同步状态。

### 3.3 删除 Group 1

- `GroupServer.swift:91-140` 对 Group 中设备逐个执行退出消息，并以所有消息是否成功决定该设备删除是否成功。
- `GroupServer.swift:152-167` 只有所有设备都成功后才删除本地 Group；任一设备失败则走删除失败流程。
- `GroupServer.swift:291-358` 先将节点标记为退出上下文，生成清理数据，并把退出消息设为遇错中止。
- `MeshNetwork+SunSmart.swift:1537-1562` 在 `exitFailure` 上下文中不再把 Group 1 或 Group 2 当作当前设备的有效目标。
- `MeshNetwork+SunSmart.swift:1613-1626` 只要任一 Scheduler Model 中仍有该 index 的有效 Entry，就判定需要删除。
- `Node+MessageHandles.swift:435-446` 删除时把相同 index 的无效 Entry 写到设备全部 Scheduler Setup Model，而不是只删当前 Owner。
- `MeshNetwork+SunSmart.swift:1166-1185` 设备清理与本地 Group 删除成功后，才从日程地址列表移除 Group 1，Group 2 地址仍保留。

这条顺序保证“先清设备 Entry，再删 Group subscription/本地 Group”。

### 3.4 加入 Group 2

- `GroupMembersViewController.swift:306-323` 把新增设备交给 Sync Devices 流程。
- `SyncDevicesViewController.swift:1350-1380` 先建立 Add to Group 步骤。
- `SyncDevicesViewController.swift:1484-1507` 把 16 个日程拆为独立任务。
- `SyncDevicesViewController.swift:1718-1724` 让后续配置依赖 Add to Group 成功。
- `SyncDevicesViewController.swift:2352-2707` 逐任务串行生成消息、发送、更新设备缓存并判断成功。
- `Node+MessageHandles.swift:448-472` 根据 Group 2 Profile 和日程 Action 选择唯一 Owner，清理其他 Scheduler Model 后写入。

如果 Group 1 和 Group 2 的 Profile 类型不同，Auto/On 日程可能发生 Light LC Scheduler 与 ordinary Scheduler 之间的 Owner 切换；当前清理全部非 Owner Model 的逻辑就是为避免同 index 双 Owner。

## 4. 风险矩阵

| 阶段 | 成功后的预期 | 失败/过程中可能看到的现象 | 是否能证明最终异常 |
| --- | --- | --- | --- |
| 设备加入 Group 1 | 0～15 每个 index 只有一个有效 Owner Entry | 只写入部分 index；Time Set 或某个 Model 清理失败 | 不能，需看任务最终状态和权威读取 |
| 修改日程 1 | 日程 1 使用新时间，其他 15 条不变 | App 已保存新时间，设备仍为旧时间或 Owner 残留 | 能证明本次修改未收敛，但不能证明 Group 造成双日程 |
| 删除 Group 1 | 全部 Scheduler Model 的 0～15 均无有效 Entry；本地 Group 1 删除 | 前面 index 已删、后面仍有效；到点可能继续执行；Group 删除显示失败 | 不能按删除成功验收 |
| 加入 Group 2 | 0～15 按 Group 2 Owner 规则重建，每个 index 仅一份有效 Entry | 已写入的先执行、未写入的缺失；Time Set 失败造成执行偏移 | 不能按加入成功验收 |
| Group 2 同步成功后 | 仅执行 Group 2 当前日程；日程 1 为新时间 | 若仍出现旧时间或同 index 双 Owner，则属于真实异常 | 可以，需 Register/Action 与 Time Status 证据 |

## 5. 建议的真机验证方法

### 5.1 先验证稳态，不要让执行时间落在同步窗口内

第一轮建议把 16 条日程安排在开始操作至少 10 分钟以后，避免把“删除/加入过程中尚未完成”误判成最终残留。

记录四个明确时间点：

1. 日程 1 修改同步成功；
2. Group 1 删除成功提示；
3. Group 2 Add to Group 成功；
4. Group 2 的 16 个 Schedule 任务全部成功。

只有第 4 个时间点之后的设备行为才用于判定最终态。

### 5.2 每个关键阶段读取设备真实状态

不要只依据 HUD 成功、列表刷新或本地缓存。建议在以下阶段读取全部 Scheduler Model 的 Register 和 0～15 Action：

1. 加入 Group 1 并完成 16 条同步后；
2. 修改日程 1 后；
3. 删除 Group 1 成功后、加入 Group 2 前；
4. 加入 Group 2 并完成同步后；
5. 退出并重进 Space、强制结束 App 再启动后。

验收条件：

- 阶段 3：所有 Scheduler Model 的 0～15 均无有效 Entry；
- 阶段 4：每个 index 在全部 Scheduler Model 中恰好一个有效 Entry；
- 有效 Entry 位于 Group 2 Profile/Action 对应的 Owner Model；
- 日程 1 的 hour/minute 是修改后的值；
- 其余 15 条与 App 当前定义一致；
- Time Status 与手机当前时间的偏差处于产品允许范围内。

重点日志包括：

- `[schedule-local]`；
- `[node-scheduler-model]`；
- `[schedule-sync] reason=`；
- `ScheduleSend set/delete`；
- Scheduler Register、Scheduler Action Get/Status；
- Time Set/Time Status。

### 5.3 单独验证非原子窗口

第二轮再保留“每条间隔 1 分钟”，故意让删除或加入跨过日程触发分钟。预期可能看到同步过程中的部分执行，但在最终同步成功后不得再出现：

- Group 1 旧时间的日程 1；
- 同一 index 在两个 Scheduler Model 中都有效；
- 已成功删除后、尚未加入 Group 2 时仍执行任何 0～15 日程；
- Group 2 同步成功后缺少某个 index。

### 5.4 失败注入

在删除到约第 8 个 index 时让设备短暂离线，验证：

- Group 1 删除必须显示失败；
- 本地不能把 Group 1 当作已完整删除；
- 设备允许处于部分删除状态，但 Retry 后必须收敛为全部无效；
- 只有 Retry 成功后才执行加入 Group 2。

在加入 Group 2 时分别制造 Time Set、非 Owner cleanup 和 Owner Set 失败，验证失败任务可见且重试后每个 index 只有一个 Owner Entry。

## 6. 静态验证结果与边界

已执行：

- `scripts/check_timed_scheduler_single_owner.sh`：通过；
- `scripts/check_timed_scheduler_persistence.sh`：通过。

这两项证明当前源码的单 Owner、全 Model 清理、缓存持久化与权威读取契约没有发生静态回归，但不能替代真机验证。尤其不能仅凭 Scheduler Action Status、HUD 成功或构建通过认定整个“删组—清 Entry—重分组—校时”链路已经闭环。

## 7. 最终判断

当前实现下，这个测试用例**不会在完整成功后天然生成 Group 1 和 Group 2 两套独立日程**。真正需要重点观察的是：

1. 16 条逐条处理造成的过程态执行；
2. 删除/加入部分失败后未完成 Retry；
3. 多 Scheduler Model 的清理失败；
4. Time Set 失败或 Fast Add 批量预生成时间值造成的设备时钟偏移。

因此，预期应表述为：

> Group 1 删除成功后，设备的全部 Scheduler Model 中不再存在 0～15 的有效 Entry；Group 2 同步成功后，再按 Group 2 的 Owner 规则恢复同一批 0～15 Entry，并且每个 index 只能有一个有效 Owner Entry。

只有同时满足这两个阶段的权威读取结果，才能确认设备最终仅执行 Group 2 日程。
