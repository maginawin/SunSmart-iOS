# Scheduler Model unknown 自动补读逻辑的引入时间

## 结论

Timed 页面因 Scheduler Model 状态未知而触发蓝牙补读的逻辑，在提交 `eafc6e7eb43a0da6ab1862d38aaeda3314e3eae8` 中引入。

- 提交说明：`fix: timed sync issues`。
- 作者：`maginawin`。
- 作者时间与提交时间均为 **2026-07-31 11:39:12，UTC+8**。
- Git 可确认代码进入提交的时间，无法精确证明实际开始编写的时间。

## 直接代码证据

通过当前工作树的 `git blame` 与该提交的 `git show` 交叉核对：

- [TimedViewController.swift](../SunSmart/Main/Timed/Controller/TimedViewController.swift) 第 88 行：在 `viewDidAppear` 调用 `repairUnknownSchedulerModelCachesIfNeeded()`。
- 同文件第 232～305 行：筛选未知节点、等待 Mesh 命令空闲、调用 `MeshAPI.getSchedule(index: nil, ...)`、完成后刷新页面。
- [TimedSchedulerOwnerPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift) 第 48～55 行：只要有 Scheduler Model 且至少一个 Model 状态未知，就需要补读。

以上入口、修复函数及判断策略均来自 `eafc6e7e`。

## 为什么有旧记录还会补读

旧节点级缓存 `node.schedulerActions` 与逐 Model 缓存 `node.allSchedulerModelEntrys` 表达的信息不同。节点级记录不能证明日程属于哪个 Model，也不能证明其他 Model 没有残留。

当前补读条件只检查每个 Scheduler Setup Model 在 `allSchedulerModelEntrys` 中是否存在状态，不检查旧节点级记录是否存在。因此，旧记录存在与 Model unknown 可以同时成立。即使没有旧记录，只要满足同样的 unknown 条件，也会进入补读筛选。

实际启动还要求 Timed 页面可见、Mesh 已连接、当前页面没有正在执行的修复；排除 Dongle。全局命令忙时延迟 0.5 秒重试。全部 Model 已知后不再因该条件补读；失败后仍未知的节点后续进入页面可以重试。

## 相关时间线

| 时间（UTC+8） | 提交 | 变化 |
| --- | --- | --- |
| 2026-07-27，作者时间 16:07:12、提交时间 20:28:15 | `2891ec03` | 同步判断由节点级缓存改为逐 Model 判断，并检查其他 Model 的残留。 |
| 2026-07-31 11:39:12 | `eafc6e7e` | 增加 Timed 页面 unknown 自动补读。 |
| 2026-09-04 16:24:30 | `e437a828` | 在 `ScheduleServer` 增加通用的未知节点筛选与读取入口，复用同一判断策略。 |

7 月 31 日的[实施总结](260731_1111_timed_scheduler_resync_solution_a_implementation_summary.md)记载，当时修复针对退出/重进 Space 后 Scheduler Model 缓存恢复失败、日程反复显示待同步的问题；包括持久化兼容与未知缓存补读。

## 本次范围

仅核对当前源码、Git 历史及已有文档，并新增本记录。未修改业务代码，未运行构建或设备验证。
