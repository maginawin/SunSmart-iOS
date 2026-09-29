# Lights 批量删除后 Deleting 不消失、CPU 与内存上涨分析

日期：2026-09-29。第 1～8 节保留现场分析；用户确认后按第 7 节边界实施 App 修复，实施与验证记录见第 9 节。未安装或操作真机。

## 1. 结论

已定位主要原因：批量删除在主线程逐台执行完整的 Space 永久删除收尾，每台都重新加载整个网络、重新生成及验证拓扑、遍历节点检查配置保护状态。其计算量随删除数量和 Space 规模叠加，造成数分钟持续主线程占用。`Deleting...` 的关闭位于这些工作之后，采样停止时尚未执行到。

证据支持“非常慢的批量清理”，不支持把此次问题直接归结为无限循环或循环引用泄漏。内存增长可能包含长时间未排空的临时对象、操作生命周期内保留的对象/拓扑结果以及运行时诊断开销；具体占比和是否另有泄漏，需要 Allocations / Memory Graph。当前 trace 未记录这些数据，也没有证明最终发生内存崩溃。

多选设备、选择整个组、选择删除 Space 全部设备进入相同的 `LightsBatchDeletionOperation.cleanup`，都有相同的性能风险；并非 PA 组专有。这里的“整个组”是 Lights 页按组选择成员，不是删除 Group 定义；“Space 全部设备”也不是删除 Space 对象。

## 2. 输入与代码基线

- 日志：`/Users/maginawin/Desktop/tmp/delete PA crash/delete PA group logs.txt`。
- trace：`/Users/maginawin/Desktop/tmp/delete PA crash/delete PA group.trace`。
- App：`fix/delete-devices-260928`，HEAD `f9094834cc8b8e695a1e8c7dbdcfd596e9beb6c9`，开始调查时工作树干净。
- 实际本地入口：`SunSmartLocal.xcworkspace`；`.local-sdk/nordic-sig-mesh-sdk` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK：HEAD `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，调查时无未提交改动。
- trace：2026-09-29 16:03:34.223 至 16:10:53.463（+08:00），439.240 秒，Time Profiler，附加至 SunSmart；结束原因是用户停止采样。
- 调用栈包含 `SunSmart.debug.dylib` 和当前批量删除方法。trace 未提供可直接核对的 Git revision，源码与记录的对应依据是调用链及日志标记，不声称已校验运行二进制的提交号。

`xctrace export` 在沙箱内返回 `Missing features`，获准在沙箱外执行后成功，无需变更 trace 或工程。导出 XML、解析脚本及统计在 `/tmp/pa-delete-*`、`/tmp/analyze_pa_trace*.py`，原始输入未修改。

## 3. 现场证据

### 3.1 发包结束不等于本地清理结束

日志统计：

| 项目 | 结果 | 含义 |
| --- | --- | --- |
| `[DeviceLeave] submitted` | 128 次、128 个不同目标 | 全部为单播地址；没有组地址或 FFFF 提交 |
| 首次至最后一次提交 | 41.833 秒 | uptime 35293.487690 至 35335.320364 |
| 退网成功状态接收 | 127 个不同源地址 | `0x349F` 未见 ACK；接收日志不等于 executor 必然接受该 ACK，也不证明物理擦除已完成 |
| 本地 `cleanup=complete` | 35 台 | 截至日志末尾仅能证实这 35 台完成 App 清理 |
| 上述记录的 `proximityTasks` | 都是 0 | 不等于没有遍历节点或计算拓扑 |
| `LightCTLGet` 发送日志 | 153 条 | 删除发包阶段仍有状态读取；不是后续数分钟主线程热点的主要来源 |

所以，页面按 PA 组选中并不等于空口按 Group 组播。本次规划结果是逐台单播；具体为何回退需当时的 Vendor 订阅、同步状态快照，现有日志不够区分。规划器会在订阅/绑定/范围不满足条件时选择单播。

最后一个删除目标为 `0x3337`；约 3.5 秒后日志出现 Proxy 连接关闭，再进入本地清理。日志没有本轮起始 Proxy Ready 地址，不仅凭排序断言该目标就是 Proxy。trace 已越过 executor 的等待阶段，不能把后续约 400 秒归因于还在等 Proxy 或最后一个 ACK。

### 3.2 CPU 采样定位

统计来自导出的 `time-profile` 表，每条采样按 weight 累加。以下是包含子调用的 CPU 采样时间，不是精确函数调用次数，也不是互斥耗时，不能相加求总耗时。

| 栈路径/函数 | CPU 采样时间 |
| --- | ---: |
| 主线程全部采样 | 401.643 秒 |
| `LightsBatchDeletionOperation.cleanup` / `DevicePermanentDeletionContext.forceRemove` | 390.287 秒 |
| `DevicePermanentDeletionContext.complete` | 389.141 秒 |
| `MeshNetwork.load` | 164.680 秒 |
| `Node.getNodeSyncProximityLighting` | 148.701 秒 |
| `SpaceConfigurationSafety.configurationAvailable` | 148.696 秒 |
| `NetworkKey.regenerateKeyDerivatives` | 138.882 秒 |
| 后台 `libRPAC` 的 `__generateCulledBacktrace_block_invoke_2` | 341.453 秒 |

清理栈首次出现在 trace 相对时间 34.882 秒，最后一次仍出现在 439.224 秒。整个区间约 404 秒，其中该清理链占约 390 CPU 秒，主线程接近持续占满一个核心。

所有线程合计约 744.741 CPU 秒，对 439.240 秒记录时长，平均约 169.6% CPU；稳定清理期间每 30 秒采样约 52 CPU 秒，约 173%。这与用户观察到的约 185% 属于同一量级，不应解释为同一个线程占用了 185%。

另有约 341 秒 CPU 来自 `libRPAC` 回溯处理。该符号是实测；将其归为调试期运行时诊断放大因素是结合符号与 Apple 诊断机制的判断，本轮未做开关对照实验，不能直接量化关闭后的收益。[Apple 文档](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early)明确说明 Thread Performance Checker 的开销可能出现在采样栈中，建议 Profile 或从 Instruments 启动应用以避免附加到已开启检测的 Run 进程。

`potential-hangs` 和相关 runtime fault 表没有事件行；主线程工作位置及持续时长来自 CPU 调用栈，不是从空的 Hangs 表推定。

## 4. 根因链路

### 4.1 async 方法仍在主线程串行收尾

[DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift) 的 `startBatchDeletion` 先显示 HUD，再等待 operation 返回，随后才隐藏 HUD、恢复交互及刷新列表。

[LightsBatchDeletionOperation.swift](../SunSmart/Common/Data/LightsBatchDeletionOperation.swift) 标记为 `@MainActor`。发包等待结束后同步调用 `cleanup(ids:force:)`，循环内逐台 `context.forceRemove()`，期间没有异步切片或主线程让出。外层的 `Task` / `async` 不会使这一段自动变为后台执行。

因此 HUD 是被未完成的清理链阻挡，而非已发现某条正常完成分支漏调用 `hide()`。仅提前隐藏 HUD 或增加超时不能解决阻塞、内存增长和未完成的数据一致性工作。

### 4.2 每台设备重复整个 Space 的收尾

[DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift) 的路径为：`forceRemove` → SDK 从网络/数据库移除该 Node → `commit` → `complete`。

一次正常 `complete` 至少执行两次完整 `MeshNetwork.load`：第一次验证持久化节点及地址，第二次读取保存后的网络进行一致性复核。中间还会：

1. 遍历删除日志及剩余节点，计算确认删除的地址集合。
2. 获取全 Space 拓扑快照并规范化；事务内清理关联引用和保存。
3. 重新读取 GroupInfo、构建拓扑并核对 Scene/Schedule 中已删除地址。
4. 清除节点同步缓存、发送清理通知，遍历网络节点生成邻近照明同步任务。

这些保护有业务意义，问题是批量入口仍以“移除一台 → 完整收尾一次”调用，导致重复全网工作。删除 D 台、Space 有 N 台及 G 个组时，至少产生 D 次随 N/G 增长的读取和遍历；全删时剩余规模递减，但累计仍有近似二次增长的部分，不能按“每台固定小成本”估计。

已有 `complete` 能把多条已经从持久化网络消失的 journal entry 合并收尾，`removeCloudInstances` 也有先移除一批再收尾的流程可参考。但当前 Lights 入口逐台先移除再立即 commit，没利用这项能力。复用时必须重新检查返回结果、失败与幂等语义，不能简单连续调用旧 commit 并把后续 nil 当成失败。

### 4.3 网络重载意外触发大量临时密钥派生

SDK `MeshDatabase.swift` 的 `Node.load` 为每一行构造 Node 时传入新建的 `NetworkKey()`，随后从数据库恢复实际的 NetKey 索引。这个临时 key 构造会生成随机 key 并计算派生值。

trace 在清理后半段明确出现：`complete` → `MeshNetwork.load` → `Node.load` → `NetworkKey()` → `regenerateKeyDerivatives` → CMAC/AES。138.882 秒相关 CPU 并不代表又向设备发送了大量加密包，主要是读取本地节点时重复初始化产生的计算。

这是 SDK 现有加载成本，被 App 每台两次全网络重载放大。App 减少重载是首要措施；若进一步修改 SDK，应提供不生成占位密钥的数据库恢复入口，保持真正 NetworkKey 的校验、派生和缺失 Device Key 安全语义，不用共享假 key 绕过校验。

### 4.4 同步任务读取又逐节点反复解码大状态文件

[Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift) 的 `getNodeSyncProximityLighting` 首先调用 `configurationAvailable`。没有当前 `NodeSyncReadContext` 时，[SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 会读取并完整解码恢复状态及删除日志。

恢复状态含 `nodeIdentitiesBaseline` 等全网信息；trace 也出现 `SpaceCloudNodeRemovalPolicy.Instance.init(from:)` 的大量解码。每个节点重复读取相同保护状态，外层每删除一台又遍历一次，放大 JSON 解码、文件系统调用和对象分配。

清理阶段有两条相关路径：生命周期 coordinator 生成结果时对候选节点生成任务，`complete` 末尾再次对网络节点生成任务。即使最后返回 `proximityTasks=0`，前置校验成本也已发生。

现有 `NodeSyncReadContext` / `SpaceProtectionReadSnapshot` 提供了有版本的读取机制，但状态读取快照不能未经审查直接成为删除权限凭据。修复需要区分事务授权检查与同一稳定版本内的重复纯读取，并保留版本变化时的失效规则。

### 4.5 次要放大与关联一致性

- 每台完成后发送通知，Space 页面可能逐次 `reloadData`、更新同步状态；后半段采样的 `WMPageController.reloadData` 约 7.7 CPU 秒。建议汇总通知，不把它当成主要原因。
- 删除阶段仍穿插普通状态读取，是无线和日志额外负担，但不是数分钟收尾的主热点。若处理，只暂停本页面拥有的刷新，避免全局取消别的任务。
- 批量操作创建的其余 prepared entry 会让通用配置保护返回 blocked，因此中间轮次仍花时间读取却得到零同步任务。若还有失败节点，必须核对用户取消/强删后是否按最终状态重新生成幸存节点的同步任务，不能直接把中途收集的空数组视作完整结果。这是修复批量收尾时必须覆盖的一致性边界；没有现场快照，不能断言本次具体漏了哪些邻居配置。

## 5. 内存泄漏判断

| 判断 | 证据与限制 |
| --- | --- |
| 持续大量分配 | 调用栈证实不断重建网络、节点、JSON 状态和加密临时数据；未记录分配字节数 |
| 临时对象长期未释放 | 高优先级假设：主线程同步清理长时间不返回，且此循环没有局部 autorelease pool；须用 Allocations 确认具体对象和释放时点 |
| 操作主动持有对象 | 源码确认 `allNodes`、contexts、Task/self 保留本轮对象，`outcome.lifecycle` 每台追加包含 plan/syncDatas 的结果；随批次增长且操作未结束就不会整体释放，不等于循环引用泄漏 |
| SDK 模型的简单父子引用环 | 核对的 Node→network、Element→Node、Model→Element、Group/Scene→network 均为 weak；这些链路没有直接支持泄漏假说，不能据此排除其他环 |
| libRPAC 的内存开销 | CPU 回溯工作明显；其内存占比及是否存在积压未测得 |
| 无限循环/最终 OOM | trace 未显示停在不前进的单一循环；本地逐台完成日志与多种收尾阶段支持持续工作。记录由用户停止，无 Allocations、Memory Graph 或 jetsam/crash 证据，不能认定无限增长直到崩溃 |

Swift 调用 Foundation/Objective-C API 仍可能创建 autoreleased 对象；长循环中的临时对象会在更晚的 pool drain 才释放。这种内存增长机制及局部 pool 的使用见 [Apple WWDC24：Analyze heap memory](https://developer.apple.com/videos/play/wwdc2024/10173/)。它解释了为什么“内存一直涨”未必是 retain cycle，但尚不是本次对象级确认。

## 6. 受影响入口

| 入口 | 影响判断 |
| --- | --- |
| Lights 勾选 PA/其他整个组，成员数大于 1 | 当前实测路径；相同清理实现，与组名、是否 PA profile 无直接绑定 |
| Lights 手动选择多个设备 | 相同 `run → cleanup → forceRemove → complete`，相同风险；少量设备可能不明显，大 Space 中少量删除也有全网开销 |
| Lights 全选，仅删除选中灯 | 相同风险；未删除的其他节点越多，每轮全网读取成本越高 |
| Lights 选择删除 Space 全部设备 | 相同风险；广播仅减少无线阶段，不减少逐台本地清理。有 Gateway 时另有服务器/网关收尾及开关配置清理，不能因此推断整体安全或更快 |
| 无 Proxy 选择 Force Delete / 失败后 Force Remaining | 跳过或补做无线阶段，但仍走同一逐台 forceRemove；可能更快进入 CPU 高占用 |
| 只选择一台灯 / DeviceProtocol 的旧 Reset 路径 | 复用 complete，单台也有全网固定成本；无本次 D 次逐台放大，HUD 隐藏位置不同，不能推定会出现完全相同的界面现象 |
| 重进、重启后的 `resume(space:)` | 保留的删除日志支持不重发无线命令的本地恢复；仍调用 complete，现状可能再次很慢，重启不是已确认解决办法 |
| 删除 Group 定义 / 删除 Space 对象 | 不属于本次这三个 Lights 入口；不能由本报告推定其故障表现 |

上述共享 App/SDK 逻辑适用于使用这些入口的品牌；本轮现场证据仅 SunSmart，无其他品牌运行验收。

## 7. 已确认的修复边界

优先改共享批量收尾，不改变已确认的无线协议、退网发送顺序和 ACK/提交证据语义。

1. **批量移除、批量收尾。** 先可靠记录目标及回执，按明确成功/强删集合完成本地 Node 移除，再汇总确认地址，一次清理引用、计算拓扑、保存、读回核验及发通知。复用现有 journal、事务和 cloud removal 的批量思路，保留部分失败可恢复，不把尚未成功的设备加入删除集合。
2. **复用稳定读取。** 同一个收尾阶段共享网络/日志/保护快照，最终持久化读回仍保留；避免逐台、逐节点反复解码全网状态。保护版本变更、外部 pending import、账号/网络变化必须继续使操作失效。
3. **控制主线程和内存峰值。** 先减少重复工作，再基于不可变输入将允许的重计算/读取串行移出主线程，或在安全提交边界分片；共享 MeshNetwork 和数据库事务不能直接丢进任意后台 Task。合理限定临时对象 autorelease pool，及时释放中间快照，最终仅保留必要的汇总结果。
4. **按最终状态生成同步任务。** 本轮未完成 entry 不可错误阻止其自身已授权清理，也不可为性能整体放宽配置保护。部分失败的取消/强删、所有设备删除、仍有幸存设备三个状态分别验收。
5. **SDK 加载优化单独评估。** `Node.load` 的占位 NetworkKey 派生有直接热点证据，可作为配套优化；App 批量化后再用同规模样本判断剩余收益。若引用新增 SDK API，需要一并记录本地 revision 和正式 release 发布待办。
6. **UI 完整收尾。** 真实完成或明确失败/中断后统一恢复 HUD 和交互；不以强行关弹窗掩盖还在执行的工作。

## 8. 验证与未完成项

分析阶段完成：日志计数、Time Profiler 栈及时间区间统计、入口/持久化/恢复/同步消费者源码追踪、本地 workspace/SDK 映射核对。当时仅新增本文档，未运行构建或声称修复通过。后续实施见下一节。

已有 `check_lights_batch_deletion.sh` 覆盖规划器、executor、Gatt receipt 和准备/上下文检查；其 Swift 编译输入没有整个 `LightsBatchDeletionOperation.cleanup → complete → 真实 SDK/存储` 集成链。上下文脚本只提取 guard/prepare 段。现有小规模恢复夹具也不能替代这次现场规模的 CPU、内存结论。本轮未重复运行这些测试。

实施后最小验证：

- 行为回归：多个设备、整组、全部设备；正常/部分失败/强删；中途退出或重启恢复；地址复用及缺失/旧日志；幸存节点、Scene/Schedule、Space/Group 拓扑保持一致。
- 工作量回归：将“整网读取/保护文件解码/拓扑构建/通知次数”纳入批量收尾验证，确保不再随每台删除重复全网流程，测试真实调用的关键边界而非源码字符串。
- 编译：若改 Swift，完成相应回归和一次 SunSmart generic iOS Debug 构建；若有 SDK 公共 API/依赖风险，再覆盖受影响品牌。
- 现场性能由用户验收：同一 Space、同一批设备，记录无线阶段与本地收尾各自时间；先用关闭 Thread Performance Checker 的 Profile 作为 CPU 对照，再单独采集 Allocations。关注 `MeshNetwork/Node`、恢复状态、拓扑结果、Foundation 临时对象及回溯组件的 Created & Still Living。
- 内存结论：观察清理期间峰值及结束/退出页面后存活对象是否下降；若仍存在阶梯增长，再用 Memory Graph 的保留路径确认泄漏。不要只要求进程 footprint 立即回到原值，也不要用 Leaks 没报错替代存活对象分析。
- 若出现实际终止，补充对应 crash/jetsam 记录，区分内存终止、watchdog 和其他崩溃。现有输入无需重录即可确认本报告的 CPU/收尾根因；进一步内存分类才需要新增证据。

## 9. 实施与验证记录

2026-09-29，用户确认按上述边界修复。修改位于原工作树，App HEAD 未变，未提交。SDK 仍为前述 `one-dev/2598bd1`，无 SDK、依赖、工程配置、资源或国际化变更。

### 9.1 最终实现

- `DevicePermanentDeletionContext.forceRemoveBatch` 在保留原 journal intent 的前提下先移除目标实例，再一次标记 removed、一次完整收尾/读回核验。每最多 8 台或累计约 8ms 的移除工作后返回主队列，并重新核验操作上下文；这是切片检查阈值，不是单次 I/O 耗时上限。临时对象用局部 autorelease pool 限定生命周期，共享 MeshNetwork 和事务仍由主线程串行访问。
- 本地移除前检查数据库删除返回值；拒绝被替换的实例和已经绑定到其他网络的 Node。相同批次重复完成不再删除或重载。中途上下文改变后停止剩余移除，已经移除的持久化记录留待恢复。
- Lights 的多选、整组选中、全 Space、Force Delete 均接入批量入口。本轮无线失败且无 Leave receipt 的 prepared intent 在生成最终拓扑任务前取消；有回执的记录仍保留用于恢复。
- Scene、Schedule、Group 光传感器、开关代理和 DFU 引用按地址集合统一清理；保留 Group/Scene/Schedule 定义、未选设备及其他 Space。只发一次完成通知。
- 生命周期 coordinator 在确认删除时跳过中间同步任务生成；journal/读回完成后，用一个有版本与账号/网络约束的保护快照生成幸存节点任务。普通调用方继续沿用原有读取路径，不放宽删除授权或导入保护。
- 操作完成后释放初始节点列表及已完成 context，仅保留当前拓扑结果。失败后强删改为异步，完成后恢复 HUD/交互，并使用最终拓扑；不把强删前的旧任务叠加到新任务中。
- `resume(space:)` 先汇总当前可恢复记录，再一次收尾，避免重启后重复逐台完整清理。

### 9.2 自动化证据与范围

128 台删除 + 1 台幸存 PA 成员的执行夹具，编译并调用真实 App 删除 context、拓扑 coordinator、节点任务方法以及保护快照读取逻辑，SDK/存储边界使用 doubles：

| 验证项 | 结果 |
| --- | --- |
| 完成/失败统计 | 128 台完成，未选设备保留 |
| 清理核心的 `MeshNetwork.load` 次数 | 2：一次持久化预检，一次读回；不会每台重复 |
| 最终任务的保护状态读取 | 1 次，按快照版本核验 |
| 逻辑提交、完成通知 | 各 1 次 |
| 幸存 PA 设备 | 有最终邻居清理任务，设备观测缓存未伪造为已同步 |
| 再次完成相同批次 | 不重删、不重载 |
| 部分失败后强删 | 返回最终空拓扑，不保留已删除设备的旧同步任务 |
| 存储失败/事务失败 | 保留失败设备或可恢复 journal，不报告全部成功 |
| 分片间失效与重启恢复 | 停止未执行项，恢复已删除项，保留尚未移除节点 |
| 实例替换、跨网络、快照失效 | 拒绝使用失效实例或其他网络的保护凭据 |

已执行的回归：`check_lights_batch_deletion.sh`、`check_device_permanent_deletion_cleanup.sh`、`check_gateway_deletion.sh`、`check_space_protection_snapshot.py`、`check_proximity_scoped_import.py`、`check_path_topology_persistence.sh`。除新增批量回归，还覆盖共享清理、Site 归属、旧 Zone 数据、删除/导入保护、云端回执和网关路径；最终结果均通过。

最终生产代码的 `SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO` 构建于 16:40 完成，结果 `BUILD SUCCEEDED`。DerivedData 使用既有 `SunSmart-fix-delete-devices-260928` 独立目录。改动是各品牌共用且无品牌条件分支的 App 逻辑，没有新增 target 配置、资源或 SDK 公共 API 编译风险，本轮使用代表 scheme SunSmart；未执行其他品牌构建、Release 或 Simulator。常规 AppIntents 元数据跳过警告不影响构建结果。

夹具中的 2 次加载统计只覆盖真实 cleanup 核心，不能据此认定整 App 的页面通知消费者也恰好只有 2 次数据库调用；也不能换算为真机耗时、内存峰值或泄漏已消除。

### 9.3 SDK 与人工验收边界

本轮优先消除了 App 每台重复的全网加载与任务计算。SDK 的占位 NetworkKey 派生成本仍存在于单次加载中，未新增 SDK API，未引入新的 SDK 发布前置条件；此前批量退网功能自身的 SDK release 发布待办保持原状。是否进一步优化该构造器，依据修复后同规模 trace 的剩余占比决定。

读回核验与拓扑提交仍有一次同步工作，尚未实测其最长主线程停顿。因此本轮交付是逻辑修复、工作量回归与构建结果，不能宣称已测得真机 CPU/内存回落或无泄漏。

最短人工步骤：在同一现场分别测 PA 整组、多选、全 Space；确认目标设备结果与失败提示正确，收尾后 HUD 消失、交互恢复、CPU 回落，内存不再持续增长；再测部分失败选择取消/强删，确认未删设备与其邻近照明同步状态正确。DEBUG 可搜索 `[LightsBatchDeletion] cleanup requested=… completed=… failed=… interrupted=… seconds=…` 和 `[DevicePermanentDeletion] … nodes=… cleanup=complete proximityTasks=…`。若仍有明显增长，补采 Allocations/Memory Graph 分辨临时分配、长期持有与实际泄漏。
