# iPad LLH CPU 485% 日志与代码分析

> 后续已完成 [trace 复核](260915_1632_ipad_cpu_trace_analysis.md)：16:24:42 开始的 7.93 秒采样确认，当前约 485% CPU 的主因是后台同步状态检查反复计算全空间拓扑和订阅成员。本文中的主线程导入/导出长耗时属于更早日志中的独立性能问题；优先级以 trace 复核报告为准。

## 结论与证据边界

日志直接定位到严重的主线程长任务：500 台设备空间的导入，以及进入空间、配置清理、云同步过程中的重复全量导出。它们是当前应优先处理的性能问题，并可能延迟蓝牙回调。另一个值得重点采样的多核负载来源是后台同步状态检查中重复构建整个空间的邻近照明拓扑。

**现有证据不能证明上述某个函数独占了 485% CPU，也不能确认 485% 是瞬时峰值还是持续占用。** 日志没有 CPU 时间、线程栈、峰值时间区间或设备采样记录。若该值来自 Xcode/Instruments 的 App 进程 CPU 指标，485% 表示各线程累计约 4.85 个逻辑核心的运行量；单个主线程无法独自解释它。参见 [Apple：Identifying a hang](https://developer.apple.com/tutorials/instruments/identifying-a-hang)。

本次只分析用户日志和当前工作区源码，没有修改业务代码、构建或操控 iPad LLH。工作区已有未提交改动，不能保证当前源码与日志对应的安装包完全一致。本地 SDK 源码仅用来佐证调用机制，未核对安装包实际解析的 SDK revision。

## 1. 日志中的主要耗时

| 阶段 | 耗时 | 解释 |
| --- | ---: | --- |
| Site 列表导入 | 0.715 秒 | 5 个 Site 的初始导入，不是后续长耗时主体 |
| siteprops HTTP 解码 | 0.817 秒，后台 | 解压后 7,392,376 bytes；数据量较大，但解码远短于后续导入 |
| Site 详情导入 | 24.890 秒 | 主要等待 Space 更新完成 |
| 兴东，500 台，完整 Space 更新 | 18.142 秒 | 包含异步预检等待及主线程工作，不能全部算为 CPU 时间 |
| 兴东 localNetworkLoaded | 2.011 秒，主线程 | 同步加载本地 Mesh 网络 |
| 兴东 applyDecision → beforeTransactionReadback | 9.078 秒，主线程 | 大批节点/组/场景等处理、持久化、拓扑校验及提交 |
| 兴东 beforeTransactionReadback → end | 5.741 秒，主线程 | 回读网络、验证持久化拓扑、完成导入和生成后续同步数据等 |
| 兴东2 remotePreflight decoded | 0.959 秒，后台 | 实际后台预检阶段 |
| 兴东2 remotePreflightPrepared | 17.855 秒 | 包含串行预检排队及恢复主线程的等待，不能解释为后台解码了 17.855 秒 |
| 兴东2 upgradeBaselineExported | 4.502 秒 | 其中导出 trace 内 2.741 秒，其他开销还在 trace 之外 |
| 兴东2 Space 更新 | 23.517 秒，最终 skipped | 时间戳相同仍先完成预检、基线导出及本地加载，之后才判断跳过 |

兴东从 applyDecision 到 end 约 **14.819 秒**。当前 `SpaceData.update` 是 `@MainActor`；对应段落在同步 continuation 闭包中，没有异步让出点。这足以造成明显的界面停顿，期间也可能包含数据库等待或 I/O，并不等于 14.819 秒纯计算。

`SiteImportTrace` 使用 systemUptime 的差值，记录墙钟耗时；`main=true` 表示打点所在主线程。跨越 await 的阶段包含挂起等待；同步 `MainActor.run` 内的耗时则对应持续占据主线程的工作区间。不能将嵌套 Site/Space 总时间相加。

## 2. 同一空间出现 7 次重导出

在点击进入兴东及后续连接、同步过程中，日志记录了以下 7 次 export：

| trace 前缀 | 网络来源 | trace 内总耗时 |
| --- | --- | ---: |
| F9675642 | reused | 3.189 秒 |
| 492134E1 | reloaded | 5.175 秒 |
| ACB9DCCB | reused | 3.564 秒 |
| 1DD316F2 | reloaded | 5.130 秒 |
| E3F26D02 | reused | 3.387 秒 |
| 4C95F3AB | reloaded | 5.661 秒 |
| 5287A89C | reloaded | 5.387 秒 |

这些同步主线程导出区间合计 **31.493 秒**，分散在日志对应的操作过程中，并非一次连续 31 秒阻塞。尚未计入 trace 开始前的导出授权/网络加载和结束后的上传准备。

代码对应：

- `SunSmart/Common/Data/ExportData.swift:408`：先执行 `snapshotExportAuthorization`，内部会加载网络；trace 此时尚未开始。
- `ExportData.swift:413`：完整 payload 构建放在 `MainActor.run` 中。
- `ExportData.swift:423`：revision 无法复用时再次 `MeshNetwork.load`。
- `ExportData.swift:589` 附近：遍历节点，执行 JSONEncoder → JSONSerialization → 字典扩展；同时还有组信息加载、拓扑准备、场景和日程处理。

`networkReused` 只复用了网络对象，没有复用最终 payload；因此依然耗时约 3.2～3.6 秒。不能将 `[ProximityLightingExport]` 附近的全部耗时单独归给邻近照明，该日志属于完整导出流程中的一个打点。

### 为什么重复导出

- `SpaceViewController.reconcileLegacyProximityLightingTopology` 在进入空间后启动清理。
- `SpaceSyncCleanupCoordinator.perform` 先导出 original（约第 137 行），随后导出 readback（约第 181 行）。readback 不以 didChange 为前置条件，未发生变更也会执行。
- `SyncOperation.getNetworkApi` 的 syncSite/syncSpace 路径再次调用清理，然后执行上传 payload 的完整导出。
- 前台/网络恢复也可能触发待同步空间的清理流程。
- cleanup 的 active 字典能合并同一空间正在执行的工作，但没有复用已完成且 revision 未变化的结果；导出本身也未在这些入口之间共享最终 payload。

所以一次顺序完成的清理和一次后续云上传路径就可能贡献多次完整导出。**目前 export 日志没有 purpose、caller 或父 trace，不能把上述 7 个 trace 逐个断言为某个入口，也不能认定存在无限循环。**

## 3. 多核 CPU 的重点嫌疑：同步状态检查反复算全空间拓扑

当前代码存在以下链路：

1. `SpaceViewController.swift:756` 附近通过 global queue 遍历所有 realNodes，调用 `reloadSyncStateCache`。
2. `DeviceLightsViewController.swift:347` 在后台检查设备 needSync；`GroupsViewCell.swift:33` 每次设置 group 都提交后台 needSync 检查。
3. `MeshNetwork+SunSmart.swift:2613` 的缓存刷新调用 getNeedSyncGroup/getNeedSync。
4. `Node+SyncData.swift:1669` 的 getNodeSyncProximityLighting 在调用方未传入 plan 时，为单台节点调用 `makePlan(for:contextGroup:)`。
5. `GroupProximityLightingData.swift:328` 附近将该调用扩展为 `makePlan(space:)`，读取 Space 并构建完整空间拓扑；不是仅查询这台设备。
6. `SiteTriggerZoneTopologyReader.mergedLocalTarget` 又读取 Site 和区域状态；若空间参与 Site Zone，还会进一步构建 Site 级计划。日志未展示 Site Zone 数据，不能假定本次命中了这个更重的分支。

节点检查有提前返回和缓存，并非每台、每次必然走到全量拓扑计算；但批量刷新、页面后台检查及缓存失效存在重复计算机会。多个 global queue 任务可以同时执行，因此这条链比单个主线程导出更能解释多核负载。**这是有源码支持的候选原因，没有采样权重，不能写成已确认的 485% 根因。**

日志中的 remotePreflight 使用单独的串行 preparationQueue；不能因同时有多个 Space 更新任务，就断言 5 个空间在并行解码。

## 4. 蓝牙超时与其他日志

服务发现超时阈值是 3 秒，而同期单次主线程导出达到 3.564 秒，另外多次达到 5 秒以上。日志表现为导出期间出现 `Service discovery timed out`，之后才继续 `Discovering characteristics`，与回调延迟相符。

本地 SDK 的 `BaseGattProxyBearer` 使用 `CBCentralManager(... queue: nil ...)`，服务发现/连接超时由 BackgroundTimer 触发；重试再提交到主队列。主线程长任务会影响蓝牙委托回调处理，后台超时可能先发生。**这支持“主线程阻塞加重超时”的判断，但不能排除 Dongle、射频环境或系统连接问题，也不能把所有 10 秒连接超时都归给导出。**

- UIScene、全屏和方向警告：属于兼容性提示，没有显示持续循环执行，当前证据不足以归因为 CPU 主因。
- 空 App Group identifier：配置问题需要独立处理，当前只出现一次，没有证据解释持续高 CPU。
- nw_connection/XPC 警告：缺乏堆栈和频率数据，不能单凭字符串定位性能根因。
- 心跳每 30 秒一次，响应 2 bytes、解码约几十微秒，本日志不支持心跳为主要负载。
- `[SpaceConfigurationSafety] blocked ... importInProgress` 是导入保护状态，不代表 CPU 被锁死或发生死锁。
- `[SpaceSyncCleanup] repairs=[] extensionChanges=0` 不必然代表完全没有变化：didChange 还包含计数变化和 normalized payload 变化。
- 组数从 17 到 1 的 ProximityLightingExport 日志只统计 eligible 邻近照明组，不能据此判断普通分组被删除。

## 5. 优化顺序与验证办法

### 优先减少重复工作

1. 以空间配置 revision、权限/恢复上下文和数据作用域标识同一次快照，复用清理结果与导出 payload，避免进入空间、云上传和恢复流程各做一轮全量工作。
2. 无变化时的回读应设计成有 revision/一致性保障的快速验证；保留事务回读、删除恢复、云提交确认等安全约束，不直接删除检查。
3. 批量同步状态检查一次建立空间拓扑计划，再按节点查目标；有 Site Zone 时保留合并目标语义。不能直接复用现有 topologyPlan 参数而漏掉该参数路径当前跳过的 Site 目标合并。
4. 合并同一 revision 的后台状态刷新；避免每个 cell 重复提交全空间工作。

### 再缩短主线程执行段

5. 在受控线程获取一致、可跨线程使用的不可变快照，后台执行纯 JSON/拓扑计算；数据库事务和共享 Mesh 对象按照线程安全边界提交。不能只给共享可变对象套 Task.detached。
6. 在时间戳未变化、没有恢复/迁移/摘要修复需求时尽早跳过重准备；不能仅凭时间戳相同就跳过安全恢复逻辑。

### 需要补齐的实测

由人工在 iPad LLH 复现，使用 Time Profiler + Hangs 录制从 Site 列表、进入兴东，到设备页/分组页停留及 Dongle 连接的完整区间。标记 CPU 485% 出现时刻，按线程查看：

- 主线程：SpaceData.export、SpaceData.update、MeshNetwork.load、JSON 编解码、SQLite、拓扑 prepare/commit/readback。
- 后台线程：reloadSyncStateCache、getNeedSyncGroup、makePlan(for:)、SiteTriggerZoneTopologyReader、HTTP 编解码。
- 若 CPU 峰值在上述任务完成后仍持续，应继续检查该峰值区间的实际线程栈，不能沿用进入页面时的耗时结论。

建议新增仅 DEBUG 下的导出 purpose/caller/父 trace、各阶段耗时、计划构建次数、合并刷新次数；补齐授权阶段和上传准备阶段的打点。量化每次进入空间的导出次数、主线程最长任务和峰值 CPU 持续时间，再比较优化前后。若采样显示线程主要等待，应进一步查线程状态与锁/I/O，而非把墙钟时间都算成 CPU 消耗。

目前已完成日志与静态代码核查；未完成 CPU 峰值采样、蓝牙因果验证和真机优化验证，不宣称性能问题已修复。
