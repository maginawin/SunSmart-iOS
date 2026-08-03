# Timed 多日程同步的 Time Set 数量与排队风险分析

## 1. 结论

当前实现不是“每个设备同步一次时间”，而是“每个需要写入且已启用的日程生成一次 Time Set”。

对同一个设备：

- 有 `N` 个需要同步、已启用的日程，并且设备支持 Time Model：生成 `N` 条 Time Set 消息；
- 已禁用日程：仍会写 Scheduler Entry，但不生成 Time Set；
- 删除日程：只写无效 Scheduler Entry，不生成 Time Set；
- 设备不支持 Time Model：不生成 Time Set。

因此，16 条日程全部启用且全部需要同步时，会产生 16 条 Time Set，而不是 1 条。

需要区分两条执行路径：

1. 普通 Sync Devices/Deferred Sync：每个日程任务真正开始执行时才构造自己的 Time Set，前面日程排队通常不会让后面的 Time Set 过期。
2. Fast Add：会在计划阶段提前构造所有日程任务的消息，16 条 Time Set 的时间值会在发送前就固定下来；后面的 Time Set 可能在长队列中等待，因此存在把较早时间写给设备的真实风险。

## 2. 数量计算

### 2.1 UI 任务与 Mesh 消息不是同一个概念

`SyncDevicesViewController.swift:1484-1507` 会把每个待同步日程创建成一个 `SyncDeviceStepTaskModel`。Time Set 没有作为独立 UI Task 展示，而是包含在每个 Schedule Task 的 Mesh message handles 中。

`Node+MessageHandles.swift:448-472` 的单个启用日程写入顺序为：

1. Time Set；
2. 清理全部非 Owner Scheduler Model；
3. 向唯一 Owner Scheduler Model 写 Scheduler Action Set。

假设设备 Composition 中有 `K` 个 Scheduler Setup Model：

- 单个启用日程：1 条 Time Set + `K - 1` 条 cleanup + 1 条 Owner Set，共 `K + 1` 条消息；
- `N` 个启用日程：`N` 条 Time Set，共 `N × (K + 1)` 条日程相关消息。

常见情况：

| 待同步的启用日程 | Scheduler Setup Model 数 | Time Set 数 | 日程相关消息总数 |
| --- | ---: | ---: | ---: |
| 16 | 1 | 16 | 32 |
| 16 | 2 | 16 | 48 |

以上还不包含 Add to Group、Profile、Scene、Switch 等其他配置消息。

## 3. Time Set 的时间值何时固定

`Node.setLocalTimeMessage()` 在被调用时立即读取 `Date()`，计算 TAI 时间并创建 Time Set。

SDK 的 `TimeSet` 保存的是创建时得到的固定 `TaiTime`。真正发送时只对这个固定值进行 marshal，不会再次读取当前时间。

因此，设备收到时间的偏差主要取决于：

> Time Set 构造时刻到设备实际收到该消息之间的等待时间。

Time Set 已经被设备接收以后，设备时钟会继续运行。后续等待 Scheduler cleanup、Owner Set 或 ACK 的时间，不会自动继续扩大该次校时偏差。

## 4. 普通 Sync Devices 路径

### 4.1 当前执行顺序

- `SyncDevicesViewController.swift:2352-2415` 每次只选择一个待执行任务，然后读取该任务的 `messageHandles`；此时才创建 Time Set。
- `SyncDevicesViewController.swift:2543-2707` 立即把本任务消息交给 `MeshProxyMessageCommand`，并等待该任务完成后才处理下一个日程任务。
- Time Set 是当前 Schedule Task 的第一条 message handle。

因此，日程 1～15 的执行耗时不会让日程 16 的 Time Set 从任务列表创建阶段一直等待；日程 16 开始执行时会重新读取当时的 `Date()`。

### 4.2 是否仍可能错误

仍存在以下偏差来源，但不是单纯由“有 16 个日程任务”直接造成：

1. Time Set 构造后，Mesh 连接尚未真正建立；`MeshProxyMessageCommand` 最长会等待连接超时。
2. `MeshProxyMessageCommand` 是共享单例；如果已有其他消息队列，新的 handles 可能追加到现有队列。
3. Time Set 的传输和设备处理本身有正常网络延迟。
4. Time Set 失败但 Scheduler Set 成功时，日程内容可能正确、设备时间仍旧；当前任务整体会因存在失败 handle 而显示失败。

正常已连接、没有外部队列竞争的 Sync Devices 流程中，构造后 Time Set 就作为本任务第一条消息发送，排队导致明显错误时间的概率较低。

## 5. Deferred Sync 路径

`DeviceGroupDeferredSyncPlanner.swift:330-420` 同样按任务串行执行，并在每次 `runTaskAttempt` 开始时才调用 `task.makeMessageHandles`。

因此它与普通 Sync Devices 类似：

- 16 个启用日程仍会产生 16 条 Time Set；
- 每条 Time Set 在对应日程任务开始或重试时重新生成；
- 前面日程任务耗时不会直接老化后面尚未构造的 Time Set。

## 6. Fast Add 路径的真实排队风险

Fast Add 与上述路径不同：

- `DeviceGroupDeferredSyncPlanner.swift:203-239` 先把所有日程拆成 deferred tasks；
- `DeviceGroupDeferredSyncPlanner.swift:458-475` 在创建 checkpoint batch 时遍历全部 tasks，并立即调用 `task.makeMessageHandles`；
- `DeviceGroupDeferredSyncPlanner.swift:77-116` 把已经生成的所有 handles 合并成一个 `appendMessageHandles` 数组；
- Classic/Professional Fast Add 再把整个数组追加到入网扩展消息队列。

结果是：

1. 16 条 Time Set 通常在计划生成阶段几乎同时取值；
2. 这些 Time Set 对象保存固定时间，不会在出队发送时刷新；
3. 后面的 Time Set 需要等待前面的 Group、Profile、Scene、Time Set、cleanup 和 Owner Set 消息；
4. 后面的 Time Set 可能再次把设备时钟设置回接近计划生成时刻的旧值。

所以在 Fast Add + 16 条启用日程 + 双 Scheduler Model 的情况下，至少有 48 条日程相关消息排队，最后一条 Time Set 可能明显晚于其时间值的生成时刻。这个路径确实可能造成设备时间落后，不能只归类为理论风险。

## 7. 其他批量构造路径

`ScheduleServer.saveSchedule` 在保存单个日程时，会预先为所有目标设备构造 message handles。它对同一设备只有一条日程，所以不会产生“同设备 16 条 Time Set”，但目标设备很多时，后面设备的 Time Set 也可能在批量队列中等待。

`NodeSyncData.syncSchedules` 也支持一次性展开多个日程 handles。调用方如果直接把整个数组放入一个串行队列，同样具有提前固化时间值的问题。

## 8. 建议的正确策略

从语义上，日程批量同步只需要对同一个设备校时一次，不需要每个日程都重复 Time Set。

建议策略：

1. 每个设备、每轮 Schedule 同步最多生成一个独立 Time Set Task；
2. Time Set 必须在该任务真正出队发送时构造，而不是在计划生成时构造；
3. Time Set 成功后再执行该设备的全部 Scheduler cleanup/Owner Set；
4. Time Set 失败时保留明确失败状态，不把 Scheduler Entry ACK 成功当成整轮同步成功；
5. 全部日程完成后可发送 Time Get，通过 Time Status 与手机发送/接收时间窗口核对设备时间偏差。

如果暂时保留“每日程一次 Time Set”，至少也应把 Time Set 改为发送时动态构造，尤其不能在 Fast Add checkpoint batch 创建阶段固定 16 个时间值。

## 9. 验证建议

建议为 Time Set 增加只记录时间信息的诊断日志，不记录任何认证数据：

- handle 创建时间；
- 实际发送时间；
- Time Set payload 中的 TAI seconds/subsecond 和 timezone offset；
- Time Status 接收时间及设备返回值；
- 该 handle 前面等待的队列长度；
- 对应 Node、Schedule id 和同步路径（Sync Devices、Deferred Sync、Fast Add）。

验收重点：

- 普通 Sync Devices 的每条 Time Set 构造到实际发送延迟；
- Fast Add 第 1 条与最后 1 条 Time Set 的构造/发送时间差；
- 16 条同步完成后立即 Time Get，确认设备时间与手机时间偏差；
- 模拟 Mesh 未连接、共享队列繁忙和 ACK 接近超时的情况；
- 验证失败时 UI/任务状态不会把“日程已写入但时间未同步”误报为完整成功。

## 10. 分析边界

本报告基于当前 `fix` worktree 和本地 `NordicSigMeshSDK` 源码静态分析，没有修改业务代码，也没有通过真机日志测量实际排队时间。因此可以确认消息数量和时间值固化时机，但实际偏差秒数仍需真机日志验证。
