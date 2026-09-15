# iPad LLH CPU trace 复核：后台同步状态检查导致约 485% CPU

## 结论：修正上一轮的优先级

**这段 trace 的持续高 CPU 来自后台同步状态检查的重复全空间计算。主线程导入/导出没有出现在本次采样中，不能作为这段 485% 的直接原因。**

采样中有 14 个后台工作线程：7 个执行分组 Cell 同步状态检查、6 个执行设备页同步状态检查、1 个执行进入空间后的全设备缓存刷新。它们几乎全部落到 `Node.getNeedSyncGroup`，再反复遍历节点、Model、分组订阅，计算邻近照明拓扑及日程成员关系。

- 采样窗口中间完整 6 秒，平均约 **482.75% CPU**；单个完整秒区间最高约 **489.6%**，与用户观察到的 485% 一致。
- `Model.subscriptions` 出现在 **92.39%** 的采样栈中，是底层共同热点。
- 为单台设备构建空间拓扑的 `makePlan(for:contextGroup:)` 出现在 **73.26%** 的采样栈中。
- 主线程只有 **3 个采样、合计 3 ms 权重**；Hangs 表无记录。

上一轮报告中的主线程导出长任务仍是日志证实的独立性能问题；但若目标是先消除本次持续 485%，应先修同步状态检查的计算重复和任务重叠，而不是先迁移导出线程。

## 1. 数据范围和统计方式

输入：`/Users/maginawin/Downloads/tmp/iPad LLH CPU.trace`。

| 项目 | trace 记录 |
| --- | --- |
| 设备 | iPad LLH，iPad (A16)，iPadOS 26.6.2 |
| 进程 | SunSmart，PID 1210 |
| 录制方式 | Attached，Time Profiler，Deferred |
| 起止时间 | 2026-09-15 16:24:42.768 ～ 16:24:50.696（UTC+8） |
| 录制时长 | 7.927023 秒 |
| 采样间隔 | 1 ms |
| 样本数 | 36,698 |
| 样本状态 | 全部 Running；未记录 waiting threads |
| 累计采样权重 | 36.698 秒，跨线程累计 |
| 首末采样相对时间 | 0.287935833 ～ 7.926935250 秒 |
| 温度状态 | 全程 Nominal |
| Hangs | potential-hangs 表没有事件；阈值 >250 ms |
| App 符号 | SunSmart.debug.dylib，UUID F623650D-A97A-37D0-9FE8-46E598094CD4 |

按完整录制时长计算的平均 CPU 约 462.95%，但最初约 0.288 秒没有样本，因此以中间完整秒区间更适合核对用户看到的持续值：

| 相对时间区间 | 累计权重 | 估算进程 CPU |
| --- | ---: | ---: |
| 1～2 秒 | 4.794 秒 | 479.4% |
| 2～3 秒 | 4.846 秒 | 484.6% |
| 3～4 秒 | 4.783 秒 | 478.3% |
| 4～5 秒 | 4.877 秒 | 487.7% |
| 5～6 秒 | 4.769 秒 | 476.9% |
| 6～7 秒 | 4.896 秒 | 489.6% |

以上为 Time Profiler 权重/墙钟区间的估算，不是硬件指令计数或 Xcode 面板的逐点原始数值。14 个线程不代表同时占用 14 个核心；实际运行量约为 4.8 个核心。

解析时完整解析 XML 的 id/ref，包括 thread、weight、tagged-backtrace、backtrace 和 frame；同一函数在一条栈内只计一次。以下“包含耗时”统计包含子调用，各层之间重叠，不能直接相加。采样数也不能用来推算函数调用次数。

## 2. 三类并行入口共同放大工作量

以下入口彼此不重叠，合计覆盖全部后台样本：

| 后台入口 | 采到的线程数 | 累计权重 | 占全部采样 |
| --- | ---: | ---: | ---: |
| GroupsViewCell.group.didSet 中的 global queue 闭包 | 7 | 18.394 秒 | 50.12% |
| DeviceLightsViewController.updateUI 中的 global queue 闭包 | 6 | 15.692 秒 | 42.76% |
| SpaceViewController.setNetworkConnected 中的 reloadSyncStateCache 批量刷新 | 1 | 2.609 秒 | 7.11% |
| Main Thread | 1 | 0.003 秒 | 0.008% |

两类页面检查从最早采样一直延续到录制结束。设备页检查同时在 6 个线程上留下样本，证明不止一份同类后台工作在该窗口内重叠运行；不能从采样确认它们是否针对同一 Node 或相同数据版本。

### 对应源码

- `SunSmart/Main/Group/View/GroupsViewCell.swift:33`：每次设置 group 都 `DispatchQueue.global().async` 检查 `self.group.needSync`，没有在此入口合并/取消工作。闭包读取 self.group，Cell 复用还需考虑结果是否仍对应当前组。
- `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift:347`：updateUI 提交 `devices.contains { $0.needSync }`，入口没有正在执行任务的合并机制。重复 UI 更新可以提交多份检查。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:756` 附近：后台遍历 realNodes 刷新同步缓存，与上面两类检查共享同一批业务对象。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2408` 附近：needSync/needSyncGroupData 在缓存为空时直接计算；没有“该版本正在计算”的状态。单次关联对象读写并不能合并“读空 → 长计算 → 写回”的并发过程。

这些机制解释了为什么“已经有缓存”仍会出现大量重复计算。trace 支持任务重叠和共同热点，但没有对象身份信息，不能把同一个 Node 的缓存竞争写成已经测出的事实。

## 3. 核心算法热点

| 调用栈包含的函数 | 权重 | 占比 |
| --- | ---: | ---: |
| Node.getNeedSyncGroup | 36.688 秒 | 99.97% |
| Model.subscriptions getter | 33.904 秒 | 92.39% |
| Node.getNodeSyncProximityLighting | 27.048 秒 | 73.70% |
| ProximityLightingTopologyPlanner.makePlan(for:contextGroup:) | 26.885 秒 | 73.26% |
| ProximityLightingTopologyContext.members(of:nodes:) | 26.732 秒 | 72.84% |
| Group.nodes getter | 9.147 秒 | 24.93% |
| Schedule.targets(node:contextGroup:) | 5.970 秒 | 16.27% |

### A. 为单台设备重复构建整个空间拓扑

已在实际栈中确认的调用链：

页面/缓存刷新 → getNeedSyncGroup → getNodeSyncProximityLighting → makePlan(for:node) → makePlan(space) → makeGroupSnapshot → members(of:nodes:) → Model.subscriptions。

`Node+SyncData.swift:1669` 附近：没有传入预先计算的 topologyPlan 时，调用单节点 makePlan。`GroupProximityLightingData.swift:328` 附近的实现进一步加载 Space 并调用空间级 makePlan。

`GroupProximityLightingData.swift:243`：计算一个组的成员时遍历 nodes，再遍历 elements/models，然后读取 subscriptions 检查组地址。**为了回答一台设备“是否需要同步”，会重新扫描整个空间的相关成员关系；下一台设备又重复扫描。**

沿用日志的 500 台场景，批量检查因这种嵌套扫描具备近似平方级放大因素；实际次数受提前返回、符合条件的组数、Model 数量、缓存状态影响，不能用 500×500 直接声称实测执行次数。

### B. Model.subscriptions 不是轻量属性读取

本地 SDK `nRFMeshProvision/Mesh Model/Model.swift:87` 的 getter 每次执行：

1. 构造可订阅的特殊组列表。
2. 读取网络全部 groups 并拼接特殊组。
3. 针对每个组查 subscribe 字符串数组。
4. 返回筛选结果，并按主 Element 规则补 All Nodes。

因此内层 subscriptions 查询会产生反复的数组拼接、filter、contains、引用计数和临时对象管理。trace 的 Self Weight 中，swift_retain 为 4.714 秒、swift_release 为 4.161 秒，合计 **8.875 秒/24.18%**。这与大量临时数组和对象访问相符，不应据此把问题归因成 Swift runtime 自身错误。

33.904 秒 subscriptions 栈按上层来源分区：拓扑成员链 25.476 秒，日程目标链 5.453 秒，其他 2.975 秒。它不仅服务于邻近照明，所以只缓存拓扑计划仍会留下日程、Profile 等成员查询开销。

### C. 日程检查也在重复扫描全部组成员

`MeshNetwork+SunSmart.swift:1554` 的 Schedule.targets 通过 `groups.contains { $0.nodes.contains(node) }` 和场景组判断目标。

本地 SDK `MeshLib/Group/Group+Nodes.swift:34` 的 Group.nodes 每次扫描管理器 realNodes，并访问 Node.group；`MeshLib/Node/Node+Propertys.swift:403` 的 Node.group 又遍历 models/subscriptions。trace 中 Schedule.targets 占 16.27%，为第二个明确需要减少重复成员扫描的热点。

SDK 实现与 trace 中 Model.subscriptions、Node.group、Group.nodes 的实际符号链相符；本次未比对安装包 SDK revision 与本地 SDK checkout，故修改前仍需核对依赖来源。

## 4. 对上一轮结论的修正与排除范围

- 本次 SpaceData.export、SpaceData.update、SpaceSyncCleanupCoordinator、MeshNetwork.load 的采样命中均为 **0**。不能说它们制造了当前窗口的 485%，也不能据此否定它们在其他时间段的长耗时。
- 用户日志中的 Site 导入时间为 16:19:05～16:19:30，网络扩展加载完成约 16:19:50；trace 从 16:24:42 开始，约晚 4 分 52 秒。两者不能按同一时间段叠加。没有录制前的采样，也不能证明这 14 个工作线程已经连续执行了 5 分钟。
- SpaceConfigurationSafety 仅占 0.250 秒/0.68%；其中 deletionCleanupPending 为 0.029 秒/0.08%。此前看到的保护文件读取不是本次主要负载。
- SiteTriggerZoneTopologyReader 仅占 0.076 秒/0.21%，不是本次主因。
- 主线程运行样本极少且没有 Hangs 事件，这段 trace 不支持“主线程导出导致蓝牙超时”的现场因果链。旧日志中的回调延迟推断仍需对应时段采样验证。
- 全程 Nominal，未记录升温等级；不能把本次高 CPU 归为过热导致，也不能凭 8 秒记录判断更长时间的温度变化。
- 包含 Debug dylib，数字反映当前被采样构建；Release 优化可能改变常数开销，但不会自动消除逐节点重建全空间计划和重复提交任务的结构性问题。
- 录制在任务完成前停止；无法区分“极慢的有限重复扫描”与其他更长期行为。当前证据不需要假设死循环，已足以解释高 CPU。

## 5. 建议修复顺序

### P0：共享一次批量计算，合并后台入口

1. 按 account/site/space/network 和有效配置版本，建立一次一致的同步状态快照；设备页、分组 Cell、批量缓存刷新读取同一份结果。
2. 同一有效版本已有后台计算时共享该任务；配置变化时使旧结果失效，过时页面结果不再提交 UI。状态判定还依赖设备已同步缓存、权限和恢复状态，不能只以云时间戳作为缓存键。
3. 同一批次只计算一次空间拓扑和节点目标映射；保留 additionalGroupMembers、恢复组、exitFailure、Space Zone 与 Site Zone 的语义。现有传入 topologyPlan 的分支会跳过 mergedLocalTarget，不能简单传 plan 导致 Site Zone 目标丢失。

### P1：移除嵌套循环中的全量订阅数组与成员扫描

4. 对明确组的订阅判断优先评估 SDK 已有 isSubscribed(to:) API，避免只是判断一个组就构造全部 subscriptions；按普通组、虚拟组、特殊地址和主 Element 默认订阅规则验证等价性。
5. 为本次快照建立组到节点、节点到组、日程目标等索引，复用成员集合；Schedule.targets 不再为每台节点重复构建 group.nodes。
6. 只有需要时才在 SDK 层优化共有 accessor；本地 SDK 路径存在，但本次只做分析，未修改它。

### P2：独立处理上一轮发现的主线程导入/导出

7. 继续按上一轮报告合并清理/回读/上传的重复导出，并按线程安全边界移出纯计算。此项解决进入页面时的停顿，不作为本次后台 485% 的首要修复。

不能仅将 global queue 改成串行队列来宣称解决：它可能降低瞬时 CPU，却保留大量重复工作和长时间任务积压。应首先降低总计算量，再控制并发。

## 6. 验证与交付

本次已完成：完整 time-profile 导出、36,698 行引用解析、按线程/入口/函数/时间区间聚合、Hangs 和 Thermal 表核查、与当前源码对应。未修改业务代码、SDK 或设备状态，也未声称问题已修复。

建议修复后人工在 iPad LLH 复现相同操作并录制：

- 分组页、设备页反复切换时，同一空间/版本只有一份批量状态计算。
- 同步按钮、分组同步图标、设备配置/日程/邻近照明差异判断与之前一致。
- makePlan 次数按批次增长，订阅成员查询按快照复用；在 DEBUG 下记录实际调用次数，不能用采样数代替。
- 对比相同完整时间窗口的累计 CPU 权重、CPU 曲线与任务完成时间，检查降低 CPU 的同时没有拖长同步状态更新时间。
- 回归导入保护、永久删除/恢复、权限变化、跨空间切换、Site Zone 合并，以及 Cell 复用后的 UI 结果。

导出中间文件和解析脚本位于 `/tmp/ipad_llh_toc.xml`、`/tmp/ipad_llh_samples.xml`、`/tmp/ipad_llh_hangs_thermal.xml`、`/tmp/analyze_ipad_trace.py`、`/tmp/ipad_llh_summary.json`；它们是临时分析文件。原始 trace 为证据来源。

工具说明：普通 xctrace 导出曾在其自身的 objc_release/自动释放池路径崩溃；限制其 cooperative pool 并开启 NSZombieEnabled 后成功导出。这些环境变量只作用于离线导出工具，没有作用于已结束录制的 iPad App，未改变本报告的原始采样权重。

上一轮日志分析：[iPad CPU 485% 日志分析](260915_1623_ipad_cpu_485_analysis.md)。
