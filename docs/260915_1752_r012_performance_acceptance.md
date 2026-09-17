# R0、R1、R2 实施与验收

## 结论

本轮完成 R0 清理回读修复、R1 可选测量点与可复现隔离基准、R2 保护状态批次快照。未实施 R3～R5，未提交 Git commit。

**R2 在真实文件和 MtestiPhone15 上通过验证：刷新节点循环及 isCurrent 的保护文件读盘为 0；每轮读取量与依赖文件数有关，不再随节点检查次数增加。**

**整 App 在 iPad LLH 上的性能验收尚未完成。** 当前真机隔离压力测试的主线程片段 P95 为 9.716 ms，高于规划的 8 ms；不能宣称所有卡顿或 CPU 485% 的整体现象已经解决。

依据：[实施计划](260915_1728_ipad_performance_optimization_plan.md)、[Release trace 分析](260915_1723_release_ipad_cpu_trace_analysis.md)。

## 1. R0：恢复持久化 Space 回读

- 删除只凭 Mesh revision、秒级 lastUpdate 复用首次导出的清理快路。
- 清理结束前，重新加载 Space 并执行第二次导出、normalize、扩展数据与版本检查。
- 保留原恢复、删除、权限、事务及回执保护。
- 新回归使用两个不同 Space 对象：调用者和持久化对象具有相同时间戳，但 Zone 内容或可读性不同。此时不得错误完成引用清理。

正确性代价：无变化清理也恢复两次导出。R4 完成包含 Space/Mesh/扩展数据的完整持久化快照契约后，才能重新引入复用。

## 2. R1：测量与基线

### 已接入

新增 `AppPerformance`，仅显式设置 Swift 编译条件 `SUNSMART_PERFORMANCE` 时启用；正常生产构建默认关闭。未改动共享 Scheme 的诊断设置。

| 测量点 | 范围 |
| --- | --- |
| SyncBatch | 一次刷新批次的墙钟区间 |
| SyncMainStep / SyncMainPrepare | 主队列完整片段，包括循环外检查、异步读取完成后的准备与发布 |
| ProtectionRead | 后台保护文件读取和解码 |
| ProtectionFileRead / ProtectionFileProbe | 文件读取尝试和 pending 路径探测次数 |
| SyncGroupMembers / SyncTopologyRead | 成员读取、拓扑读取/计算 |
| SyncNodeCheck / SyncPublish | 节点判断和结果发布 |
| SyncNodeComputed / SyncResultHit | 实际计算次数与批次命中 |
| SyncNodeRequest / SyncGroupRequest / SyncWarmUpRequest | 请求来源类别及请求节点数 |
| SyncCancelled / SyncInvalidated / SyncUnavailable | 取消、失效和不可用结果 |
| SyncProtectionGeneration | 匿名进程内代数，不记录账号或空间内容 |
| ResponseDecode / ImportOperation / SpaceExportMain / SpaceCleanup | 响应、导入、导出及清理区间 |

区间为墙钟时间，不直接等于 CPU 时间。Signpost 使用独立 ID；未输出账号、密钥、认证数据或业务 JSON。节点的业务来源、持久化 SQL、Site 拓扑详细阶段仍可通过 Time Profiler 栈区分，后续迁移对应 R3/R4 时再细分。

默认关闭版本的优化 SIL 已检查：begin/end/event 无时钟读取、无 signpost 发送。开启版本的开销计入本次测量；未将开启版本视为零开销。

### 可复现基准

`scripts/check_space_protection_snapshot.py` 从固定旧版本 `28b918b2` 提取生产保护读取器，重定向到测试目录及 UserDefaults suite。哈希、JSON 解码、文件探测、删除日志逻辑保留。

新旧读取器使用同一份实际编码文件：active recovery state、16 KiB authorizationBaseline、空 deletion journal。每轮 2,000 次检查，共 15 轮；OS 文件缓存已暖，每轮新建逻辑快照。**这不是 5 次进程冷启动 + 10 次暖启动，也不是完整 Node 同步链的前后对比。**

刷新压力夹具为 500 节点、50 组、每节点 20 Model，运行 15 个全新批次。生产调度器、批次上下文、拓扑和保护文件读取参与执行；SDK/数据库及其他节点业务输入仍有隔离边界。

另链接与主工程相同 revision 的真实 NordicSigMeshSDK，验证 10,000 个真实 Model 的字符串订阅、普通组、虚拟组、特殊地址。此项是 SDK 数据表示回归，不代表完整 SDK 拓扑或 BLE 验收。

## 3. R2：保护状态快照与失效

### 读取边界

- 主队列只捕获 account、region、meshUUID、networkID 等值；串行 worker 读取保护文件。
- 快照包含 recovery phase、authority、持久化 identity、recovery generation、blocked reason、pending import/reference/deletion 标志、读取错误及进程代数。
- recovery 与 deletion identity 不一致、JSON 损坏、无读取权限、非法目录名均返回不可用；确认不存在的文件按原语义视为无标记。
- 每轮最多读取 recovery state 和 deletion journal 各一次，探测两个 pending 标记各一次；一次读取内部复用路径哈希。
- NodeSyncReadContext 的节点保护查询复用快照。isCurrent 改为内存保护版本比较，保留账户、区域、网络、设备代数、数据库版本及组损坏状态检查。
- **isCurrent 仍有数据库 revision 查询。** 本轮“0 次主线程 I/O”仅指保护文件，不包括全部 SQLite/getter 工作；后续属于 R3。
- 不跨已完成批次长期缓存。前台恢复使代数失效；每次新批次重新读盘。
- 显式 group 与 nil group 分别缓存，避免恢复组、待加入组语义被错误合并。

### 写入覆盖

所有实际保护路径和 blocked key 的生产读写点均经过仓库搜索；未发现 Safety 文件外直接写这些保护路径的入口。原始状态/journal 编码器仍由正式 Safety writer 调用。

| Writer/路径 | 处理 |
| --- | --- |
| saveState | 写入开始/结束更新代数，覆盖 authority、phase、generation、提交状态迁移；失败同样失效 |
| block、clearActiveMarkers | blocked 设置/解除及 active 标记清理纳入代数 |
| updateDeletionJournal、confirmLocalChanges | journal 更新、回执清理及关联 blocked 解除纳入代数 |
| begin/finishImport | pending 导入创建、归档、删除及解除阻止纳入代数 |
| begin/finishSyncReferenceCleanup | pending 引用清理创建/完成纳入代数 |
| archiveDeletedSpace、retryArchiveMoves | identity 目录变更及移动纳入代数 |
| finishSubmission | 提交确认、baseline 与阻止解除纳入代数 |
| authorizeLocalRecovery、applyReferenceRepair | 恢复写入阶段及直接标记修改纳入代数；HTTP 审查之前的只读阶段不提前标为 writer |
| 账号/区域/网络切换 | 捕获值与当前上下文比较，拒绝旧空间结果 |

读前、读后校验同一代数；writer 活跃期间返回不可用。批次发布前再次校验。内存节点缓存提交以短锁与 writer 开始排序，锁内不做文件 I/O、不调用 UI 回调。回调前再检查上下文，不使用过期的“已同步”结论。

数据库版本不可用时直接结束为保守结果，避免无限重建快照。命令发送、写入、导入/删除完成等正式授权继续走原 Safety 路径；只读快照不作为执行授权。

## 4. 验收结果

### 真机环境

- MtestiPhone15：iPhone 15，iOS 26.6.2（23G90），有线连接。
- 隔离测试 App：`com.sunricher.node-sync-status-test`。
- Release、Swift `-O`、whole-module；测试宏 `DEBUG SUNSMART_PERFORMANCE`。DEBUG 用于测试结果输出，未运行生产 App 的 DEBUG 日志链。
- 最终 Mach-O UUID：`3D9D6BBA-AD41-3172-8A10-F40C16C81A03`。
- SDK：`a6246b1b0409824a3227a9c7cad8140219feb182`，与 workspace 固定版本一致；未修改 SDK。
- 通过 devicectl 直接启动，自测退出码 0。未登录账号、写云端或发送 BLE 命令。

### 真机指标（无 Instruments 采样的直接启动）

| 指标 | 结果 |
| --- | --- |
| 旧读取器：每轮 2,000 次，15 轮 CPU 中位数 | 0.5790 s |
| 批次快照：相同检查，CPU 中位数 | 0.0003 s |
| 对应墙钟中位数 | 0.5790 → 0.0003 s |
| 5,000 次保护查询 | 2 次文件读取 + 2 次路径探测；主线程读取 0 |
| 15 次刷新批次保护文件读取 | 30 次；主线程 0 |
| 500 节点、14 个重叠读者 | 1 次基础拓扑，500 次订阅读取，约 0.021 s |
| 压力夹具完整主线程片段 | P95 9.716 ms，最大 9.899 ms |
| Cell 复用、过期回调、同步图标 | 隔离真机自测通过 |
| 真实 SDK Model 字符串订阅 | 10,000 个 Model，通过 |

保护读取子系统 CPU 在此夹具下降约 99.9% 以上。**不得把这个比例当作整 App CPU 降幅，也不得将 0.021 s 的简化 Node 夹具当作真实 500 节点空间的完成时间。**

### 正确性回归

- R0：同时间戳的陈旧 Space、Zone 差异/不可读、未知 revision、恢复保护；二次导出行为通过。
- R2 真实文件：缺失目录、损坏状态/journal、pending import/reference/deletion、blocked、权限失败、身份不匹配、非法目录通过。
- 并发：读取中原子替换、后台 writer、写入中读取、失败写入、旧快照提交拒绝通过。
- 实际生产 writer：saveState 失败、authority、journal、block 的代数失效通过。
- 刷新：14 个重叠 owner、替换/取消、设备代数变化、真实 pending 文件中途创建、账号/区域/网络切换、前台恢复、无数据库版本通过。
- 保护文件损坏时，即使选择为空，也必须返回保守结果；最终真机版本包含此项回归。
- `check_space_recovery_receipts.py`、`check_proximity_scoped_import.py`、`check_space_sync_cleanup.py`、`check_sync_task_builders.py` 通过。

R0 coordinator 测试通过隔离持久化接口提供独立 Space 对象；未把这一项表述为完整 App SQLite + UI 集成测试。

### 构建

五个品牌的 Sources membership 均已同步新增文件：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。品牌构建使用 iphoneos、generic/platform=iOS；不使用 Simulator。

五个品牌最终 Debug 构建全部通过。SunSmart 默认 Release、启用测量的 Release 构建均通过；默认 Release Mach-O UUID 为 `B2C14932-470C-3055-8DA4-4CBB02CF9AA6`。`git diff --check` 通过。现有资源名冲突、重复资源/编译项、依赖 Sendable 和 UIKit deprecated 警告保持原状。

### 额外 trace 与复现入口

- [隔离自测 Time Profiler trace](/Users/maginawin/Downloads/temp/r012-acceptance/r012-mtest-release.trace) 已录制保存。它对应加入“损坏文件 + 空选择”最后一项回归前的测试二进制 UUID `6E1C5EB9-0430-39E5-AF46-C1DFE3A793BA`，不得混同最终测试版本。
- `xctrace export --toc` 对该文件退出码 139（崩溃）；未通过 Computer Use 打开，也未据未解析的 trace 宣称 CPU 栈、libRPAC、Hangs 或内存验收通过。
- 上表来自最终二进制的直接启动计数器/计时及 CPU rusage，非这份 trace 的采样推算。
- 复现脚本：[保护文件基准](../scripts/check_space_protection_snapshot.py)、[刷新调度回归](../scripts/check_node_sync_status_refresh.py)、[真机测试工程生成器](../scripts/prepare_node_sync_status_ui_tests.py)、[清理回读回归](../scripts/check_space_sync_readback_reuse.py)。
- 真机测试工程位于 `/tmp/NodeSyncStatusTests/RecoveryLayout.xcodeproj`，使用 Release、iphoneos、MtestiPhone15；通过参数 `--self-test` 执行后自动退出。测试脚本与生产源的抽取方式已保存，可以重新生成。

## 5. 尚未完成的整体验收

1. iPad LLH 的完整生产空间、无诊断 Release 前后同流程录制尚未取得，R1 的原设备可比基线仍待人工补齐。
2. 当前压力片段 P95 超过 8 ms，且节点业务/数据库部分有替身；R3 的首次拓扑、成员/Site 计划迁移和 SQL 版本边界仍需实施。
3. 导入、导出、清理、列表及 BLE 超时本轮没有做业务性能迁移；R0 反而恢复必要回读开销。不能据此宣称这些问题已解决。
4. 未取得整 App 每操作 CPU 秒、峰值内存、hangs、热状态与蓝牙回调延迟的完整前后指标。

按项目 [AGENTS.md](../AGENTS.md)：“允许使用真机 MtestiPhone15 自查 UI，其他个人设备默认由人工操作”。本轮只自动操作 MtestiPhone15，iPad LLH 复测和最终体验验收由人工完成。

### iPad 人工复测步骤

1. 同一数据快照、同一 iPad/OS，固定进入 Site → 兴东 → Devices/Groups 切页 → 等待刷新与蓝牙连接的操作时间线；不要在两次录制间更改空间数据。
2. 使用 Profile 的 Release 构建，由 Instruments 启动，分别保留启用诊断和无诊断的录制；性能收益以无诊断结果比较。Profile/Time Profiler 和 Hangs 的录制流程参考 [Apple：Identifying a hang](https://developer.apple.com/tutorials/instruments/identifying-a-hang)。
3. 要查看本轮事件，在专用测量构建添加 `SUNSMART_PERFORMANCE`，记录 Time Profiler、Points of Interest、Hangs、Thermal State；另保留默认关闭测量的 Release 作总 CPU 对照。[Apple：Recording Performance Data](https://developer.apple.com/documentation/os/recording-performance-data?language=objc)
4. 至少 5 次进程重启后的首轮刷新、10 次同进程重复刷新；记录各轮 CPU 秒、墙钟、主线程片段、hangs、内存峰值，并区分 OS 缓存是否已暖。
5. R2 必须满足：SyncMainStep/SyncMainPrepare 的节点检查与 isCurrent 不再出现保护文件 Data(contentsOf:)；一次有效批次的 ProtectionFileRead 至多 2、ProtectionFileProbe 至多 2；保护变更后不得发布旧的已同步结果。
6. 同时检查导出/清理与首次拓扑峰值；超过预算的栈作为 R3/R4/R5 输入，不通过关闭保护或放宽回读来消除。
