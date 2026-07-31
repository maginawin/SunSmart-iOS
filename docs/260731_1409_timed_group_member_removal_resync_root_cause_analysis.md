# Group Members 移除后 Timed 出现待同步：根因分析

## 1. 结论

这是一个与 2026-07-31 刚修复问题不同的新触发路径，但两者都发生在 2026-07-27 引入的 Timed 单 Owner Scheduler 规则之后。

本次问题的直接根因是：

1. L2、L6 加入自动 Profile Group 后，所有 `Turn On` 定时的 Owner 从 ordinary Scheduler 迁移到 Light LC Scheduler。
2. L2、L6 移出 Group 时，Owner 规则会立即把设备目标的 `Turn On` 定时重新判定为 ordinary Scheduler。
3. 成员移除数据规划能够识别出这批 Scheduler Owner 迁移任务，但 `SyncDevicesViewController` 对 `outNodes` 只保留 `removeDevice`，丢弃了同一节点返回的 `configturationDevice`。
4. 因而 Group 目标定时 id 0、5 被正确删除，但设备目标定时 id 1、3 没有从 Light LC Scheduler 迁回 ordinary Scheduler。
5. 再进入 Timed 时，严格单 Owner 判定发现 ordinary Owner 缺少 id 1、3，于是正确显示 `owner-entry-missing`。

因此，Timed 页面不是误报，也不是刚修复的缓存持久化问题再次复发。设备真实的 per-Model Scheduler 状态在成员移除后确实不符合当前 Owner 规则。

准确归因是：

> 2026-07-27 的 membership-dependent Scheduler Owner 规则使“退出自动 Profile Group 时需要迁移设备目标 Turn On 定时”成为新业务要求；成员移除 UI 流程中从 2025 年起就存在的 outNodes 只执行删除步骤、丢弃配置步骤的非对称行为，没有覆盖这个新要求。

## 2. 与 2026-07-31 最近修复的区别

最近提交 `eafc6e7e` 修复的是：

- Space 重载后 per-Model Scheduler 缓存无法从数据库恢复；
- Model 状态变成 unknown；
- Timed 因 `owner-model-unknown` 或 `cleanup-model-unknown` 重复提示同步；
- 通过 SDK codec 修复、损坏数据保护和权威读取恢复状态。

本次日志呈现的是另一种状态：

- 移除前，所有 Model 都是 `state=known`；
- 移除后，L2、L6 的两个 Scheduler Model 仍然都是 `state=known`；
- 没有 `SchedulerModelCacheRepair`、缓存解码错误、`owner-model-unknown` 或 `cleanup-model-unknown`；
- 明确原因是 id 1、3 的 `owner-entry-missing`；
- Light LC Model 中还能看到 id 1、3 的有效残留。

`eafc6e7e` 没有修改：

- membership 到 Scheduler Owner 的解析；
- Group Members 的 outNodes 数据源装配；
- `.syncSchedules` 在删除/配置 Section 之间的分类。

它只是让当前真实差异能够以明确的 `reason` 输出。不能通过再次读取缓存来修复本次问题，因为设备中的 entry 确实还位于旧 Owner Model。

## 3. 日志时间线

### 3.1 添加 L2、L6 到 Group

日志：

`add l2 l6 to group members.txt`

L2（0019）和 L6（0028）都执行了以下四条 `Turn On` 定时：

| Node | 设置的 Schedule id |
| --- | --- |
| L2 / 0019 | 0、1、3、5 |
| L6 / 0028 | 0、1、3、5 |

其中：

- id 0、5 是 Group 目标定时；
- id 1、3 是 Device 目标定时；
- id 2、4 是 `Turn Off`，仍由 ordinary Scheduler 持有，不需要迁移。

这说明添加成员流程不只同步 Group 目标定时，还会把设备自身的 `Turn On` 定时从 ordinary Scheduler 迁移到自动 Profile 使用的 Light LC Scheduler。

### 3.2 添加后检查 Timed

日志：

`check timed page.txt`

结果：

- 6 条定时在所有目标节点上均为 `reason=synchronized`；
- L2：
  - ordinary Scheduler 0019：id 2、4；
  - Light LC Scheduler 001B：id 0、1、3、5；
- L6：
  - ordinary Scheduler 0028：id 2、4；
  - Light LC Scheduler 002A：id 0、1、3、5。

这是当前 Owner 规则下正确且完整的基线。

### 3.3 移出 Group

日志：

`remove members.txt`

实际发送的 Scheduler 操作只有：

| Node | 操作 |
| --- | --- |
| L2 / 0019 | delete id 0、5，且清理两个 Scheduler Model |
| L6 / 0028 | delete id 0、5，且清理两个 Scheduler Model |

日志中没有：

- set id 1；
- set id 3；
- 将 id 1、3 从 Light LC Scheduler 迁移到 ordinary Scheduler。

id 0、5 的所有 `SchedulerActionStatus(noAction)` 都成功；Group Subscription 删除也成功。没有 Mesh 超时或设备失败可以解释后续待同步。

### 3.4 移除后再次检查 Timed

日志：

`check timed again.txt`

Group 目标已经正确更新：

- id 0、5 的目标节点只剩 L1、L3、L4、L5；
- L2、L6 不再参与 id 0、5 的同步判断；
- 这两条 Group 定时没有造成错误提示。

真正待同步的是：

| Schedule | Target | Action | 异常节点 | 原因 |
| --- | --- | --- | --- | --- |
| id 1 | devices | Turn On | L2、L6 | `owner-entry-missing` |
| id 3 | devices | Turn On | L2、L6 | `owner-entry-missing` |

同时，逐 Model 缓存显示：

- L2 ordinary 0019 只有 id 2、4；
- L2 Light LC 001B 仍有 id 1、3；
- L6 ordinary 0028 只有 id 2、4；
- L6 Light LC 002A 仍有 id 1、3。

这不是 entry 丢失，而是 Owner 已改变、entry 仍停留在旧 Owner。

### 3.5 手动修复两条 Scheduler

日志：

- `fix one scheduler.txt`
- `fix two scheduler.txt`

修复 id 1 和 id 3 时，对 L2、L6 都执行了相同迁移：

1. `TimeSet`；
2. 向旧 Light LC Scheduler 写入 `noAction`：
   - L2：001B；
   - L6：002A；
3. 向 ordinary Scheduler 写入目标 entry：
   - L2：0019；
   - L6：0028。

全部 `TimeStatus` 和 `SchedulerActionStatus` 成功。

这个手动修复过程恰好补上成员移除流程遗漏的迁移动作，因此构成了对根因假设的直接验证。

## 4. 源码数据流

### 4.1 Owner 会随 membership 改变

`SunSmart/Main/Timed/Model/Scheduler.swift:11-49`

规则是：

- `Turn On` + 自动 Profile Group：Light LC Scheduler；
- `Turn On` + 无 Group：ordinary Scheduler；
- `Turn Off` 等普通动作：始终 ordinary Scheduler；
- `groupState == .exitFailure` 时，退出中的 Group 不再算有效 membership。

因此在 `GroupMembersViewController` 将 L2、L6 标记为 `.exitFailure` 后，id 1、3 的预期 Owner 会从 Light LC 切换为 ordinary。

### 4.2 严格同步判定正确识别差异

`SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1533-1610`

`Schedule.needsSync` 会：

1. 按当前 membership 解析 Owner；
2. 检查 Owner Model 是否存在目标 entry；
3. 检查非 Owner Model 是否仍有同 id 残留。

移除后的 L2、L6 在 ordinary Scheduler 中缺少 id 1、3，所以返回 `owner-entry-missing`。即使先检查 cleanup，Light LC 中的 id 1、3 也会形成 `cleanup-entry-residual`。

### 4.3 Node 同步规划能够生成迁移需求

`SunSmart/Common/Data/Node+SyncData.swift:482-490`

Group 同步会同时收集：

- `syncSchedules`；
- `deleteSchedules`。

在当前数据下：

- id 1、3 仍直接包含 L2、L6 的 Node Address，并且 ordinary Owner 缺少 entry，所以属于 `syncSchedules`；
- id 0、5 是 Group 目标，L2、L6 退出后不再是 target，且设备上仍有 entry，所以属于 `deleteSchedules`。

### 4.4 迁移任务在 UI 数据源装配时被丢弃

`SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1328-1500`

`getSyncDeviceModel` 的分类：

- `.syncSchedules` 被放入 `configturationSteps`；
- `.deleteSchedules` 被放入 `deleteSteps`。

但 outNodes 的数据源装配位于：

`SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:155-160`

它只把 `result.removeDevice` 加入 Remove Section，没有处理 `result.configturationDevice`。

对比 inNodes：

`SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:162-176`

inNodes 同时接收：

- `removeDevice`；
- `configturationDevice`。

所以：

- 添加 L2、L6 时，id 1、3 的 ordinary → Light LC 迁移能够执行；
- 移除 L2、L6 时，id 1、3 的 Light LC → ordinary 迁移被丢弃；
- id 0、5 属于删除步骤，因此仍能执行。

这解释了六份日志中的全部差异。

## 5. 为什么只有 id 1、3 出问题

本次 6 条定时形成了完整对照：

| id | Target | Action | 移除后的行为 |
| --- | --- | --- | --- |
| 0 | Group | Turn On | 正确从 L2、L6 的两个 Model 删除 |
| 1 | Device | Turn On | 应迁移回 ordinary，但迁移任务被丢弃 |
| 2 | Device | Turn Off | Owner 始终 ordinary，无变化 |
| 3 | Device | Turn On | 应迁移回 ordinary，但迁移任务被丢弃 |
| 4 | Device | Turn Off | Owner 始终 ordinary，无变化 |
| 5 | Group | Turn On | 正确从 L2、L6 的两个 Model 删除 |

因此问题与以下因素无关：

- Scheduler index 容量；
- Group 目标残留；
- `TimeSet` 或时区；
- Mesh 消息失败；
- 缓存 codec 或 Space 重载；
- 所有定时普遍失效。

它只影响“退出自动 Profile Group 后仍直接以 Device 为目标的 Turn On 定时”。

## 6. 变更历史与测试覆盖缺口

### 6.1 新规则

提交 `2891ec03`（2026-07-27）引入：

- membership-dependent Owner；
- ordinary / Light LC 单 Owner；
- 写 Owner 前清理非 Owner；
- per-Model 严格同步判定。

这是本次迁移需求产生的时间点。

### 6.2 旧非对称行为

Git blame 显示：

- outNodes 只接收 `removeDevice` 的结构来自 2025-03-06；
- `.syncSchedules` 固定进入 `configturationSteps` 来自 2025-04-08。

过去退出 Group 主要意味着删除 Group 数据，配置型任务被丢弃不一定可见。Owner 规则开始依赖 membership 后，退出 Group 首次需要保留某些直接设备目标 Scheduler，并把它们配置到另一个 Owner，旧假设不再成立。

### 6.3 现有测试为什么没有发现

当前：

`scripts/check_timed_scheduler_single_owner.sh`

仍然通过：

- `TimedSchedulerOwnerPolicyTests passed`
- `TimedSchedulerSingleOwnerContractTests passed`

现有合同覆盖了：

- 各 membership 的 Owner 选择；
- 设置前清理非 Owner；
- Group 同步传入 contextGroup；
- per-Model 严格判定。

但没有覆盖：

> Group Members 的 outNodes 在同一次退出流程中，既有 Group 目标删除任务，又有直接 Device 目标 Scheduler Owner 迁移任务。

因此这是生命周期编排层的覆盖缺口，不是 Owner Policy 单元规则错误。

## 7. 修复方向

预期行为不应通过隐藏 Timed 同步图标来实现。图标反映的是设备真实 Owner 不一致；忽略它会留下 Light LC 残留，并可能使退出 Group 后的 Device Turn On 定时无法按当前普通控制语义执行。

正确方向是：

1. 在 Group Members 移除流程中保留退出节点所需的 Scheduler Owner 迁移任务；
2. 确保迁移与 Group 定时删除、Profile 清理、Subscription 删除按明确顺序执行；
3. 成功后更新两个 Scheduler Model 的本地缓存；
4. 完成成员移除时，Timed 不应再有真实差异。

实施前需要重点确认顺序：

- Group 目标 id 0、5 要从所有 Scheduler Model 删除；
- Device 目标 id 1、3 要先清理 Light LC，再写 ordinary；
- 退出 Group 的 Subscription/Profile 操作不能导致迁移任务被跳过；
- 任一迁移失败时仍应保留真实待同步状态，不能把失败伪装成成功。

不建议：

- 将 `owner-entry-missing` 按已同步处理；
- 只删除 Light LC 中的 id 1、3 而不写 ordinary；
- 回退到扁平 `schedulerActions` 判定；
- 每次进入 Timed 通过权威读取掩盖成员移除流程遗漏。

## 8. 建议回归矩阵

### 必测主路径

1. 自动 Profile Group；
2. 节点先有 Device Target 的 Turn On、Turn Off；
3. 加入 Group：
   - Turn On 迁到 Light LC；
   - Turn Off 保持 ordinary；
   - Timed 全部 synchronized；
4. 移出 Group：
   - Group Target 定时从退出节点删除；
   - Device Target Turn On 迁回 ordinary；
   - Turn Off 不发生无关重写；
   - Timed 不显示待同步；
5. 再次加入同一 Group：
   - Device Target Turn On 再迁到 Light LC；
   - 不产生双 Owner 残留。

### 对照场景

- Manual Control Group：Turn On 前后都应使用 ordinary，不应产生迁移；
- 只有一个 ordinary Scheduler 的旧设备；
- 双 Scheduler 设备；
- outNodes 中一台成功、一台失败；
- 离线退出后重新同步；
- App 杀进程/Space 重载后状态保持；
- Group Target、Device Target、Scene Target 混合；
- id 0 和 id 15 边界。

## 9. 当前工作区与验证边界

- 本轮只完成日志和源码分析；
- 未修改 App 或 SDK 业务代码；
- 未执行 commit、push 或 merge；
- 当前工作区在生成本文档前无未提交差异；
- 聚焦单 Owner 自动化合同测试通过；
- 现有日志已足够确认根因，不需要通过 Simulator 或 generic iPhoneOS build 来证明分析结论；
- 真机修复验收必须在实施后重新执行添加成员、移除成员和 Timed 检查全流程。
