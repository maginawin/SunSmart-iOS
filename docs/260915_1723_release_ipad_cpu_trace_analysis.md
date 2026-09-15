# Release iPad LLH trace：旧热点改善，主线程和诊断开销仍明显

## 结论

**部分解决，尚未完成性能修复。** 这段录制未再出现旧 trace 中约 485% CPU 的 14 个后台同步检查作业；旧 subscriptions/组成员重复扫描已明显缩小。但是，新刷新器仍消耗大量主线程时间，导入、导出、清理和列表构建仍有卡顿。另有很大一部分 CPU 来自运行时诊断回溯，不能把这份录制直接当作无调试干扰的线上 Release 性能。

本次只分析，未修改业务代码或用户的 Scheme 设置。

## 1. 数据范围与比较限制

输入：`/Users/maginawin/Downloads/tmp/release iPad LLH cpu.trace`。

| 项目 | 本次记录 |
| --- | --- |
| 设备 | iPad LLH，iPad (A16)，iPadOS 26.6.2 |
| 进程 | SunSmart，PID 1240，Attached |
| 录制时间 | 2026-09-15 17:14:14.128～17:15:31.718（UTC+8） |
| 时长 | 77.590490 秒 |
| 工具 | Time Profiler，1 ms，未采集 waiting threads |
| 样本 | 56,842 条，均标记 Running，累计 56.842 CPU 秒 |
| 主线程 | 21.852 CPU 秒，占全部样本 38.44% |
| Hangs | 9 次，总计 4.113 秒，最大 756.07 ms |
| 温度 | 全程 Nominal |
| App 符号 | SunSmart，UUID A863DB76-0B61-31FC-9C23-1D9E1B1EF4B1 |

完整解析 XML id/ref；一条栈中相同函数只计一次。“包含权重”含子调用，不能跨层相加。采样不能给出函数调用次数，也不能精确还原每个刷新片段的起止。

- 旧 trace 是 Debug、7.927 秒的持续同步扫描；新 trace 是用户提供的 Release、77.590 秒，覆盖请求、导入、进入空间和页面刷新。两者构建方式和操作窗口不同，不能把平均值相除当作代码优化收益。
- 本次首末样本为相对 7.7309～74.2829 秒。录制开始 7.73 秒没有 time-profile 样本，生命周期为 Unknown；不能据此判断那段没有业务活动。全窗口平均值会被无样本/低负载区间稀释。
- 34 条样本没有可解析栈，约 0.06%；部分系统符号是地址，Release 也存在内联和合并符号，不宜仅以某个名称消失判定其计算绝对为零。
- 新刷新器和 read context 符号确实在栈内，证明本次执行了新路径。当前 HEAD 是 `28b918b2`，但本机所检索 Release 产物 UUID 为 7BEAF9B4…，与 trace 不同，未确认该录制二进制对应的精确 Git revision。

## 2. CPU：旧的 485% 未再出现，但仍有持续高负载段

以下为采样权重 / 墙钟区间估算；100% 约为一个 CPU 核心的执行量，不是设备总算力百分比。

| 指标 | 旧 Debug trace | 本次 Release trace |
| --- | ---: | ---: |
| 完整 1 秒区间峰值 | 489.6% | **224.7%**（17～18 秒） |
| 代表性高负载区间 | 1～7 秒均值 482.75% | 30～39 秒均值 **151.0%**；60～68 秒 **155.45%** |
| 完整录制平均 | 462.95% | **73.26%**，含较长低负载/无样本区间 |
| Model.subscriptions 包含权重 | 33.904 秒 / 92.39% | **0.141 秒 / 0.25%** |
| Group.nodes 包含权重 | 9.147 秒 / 24.93% | **0.099 秒 / 0.17%** |
| Schedule.targets 包含权重 | 5.970 秒 / 16.27% | **0.062 秒 / 0.11%** |

新记录在 70～77 秒仅有 5 ms CPU 权重，说明负载会结束，未见始终运行到停止录制的旧型扫描。不能据此保证其他操作或更大数据量下不会再次出现高 CPU。

### 修复有效的证据

- 旧的 GroupsViewCell、DeviceLightsViewController 与 reloadSyncStateCache 的 14 个后台重叠同步检查链未再出现；当前 NodeSyncStatusRefresh.step 的 16.252 秒样本全部位于主线程。
- subscriptions、Group.nodes、Schedule.targets 的绝对采样权重在更长记录中仍大幅缩小，支持减少全量订阅数组/成员扫描确实起效。
- 不能只说“CPU 从 485% 降到 73%”：后者的平均分母包含等待和低负载区间，且诊断配置不同。

## 3. 新刷新器仍然很重：主线程累计 16.252 秒

刷新器占全部 CPU 权重 28.59%，占主线程权重 **74.37%**。

按相邻采样间隔超过 1 秒分组，可看到三段刷新活跃窗口（不是函数调用数，也不保证每段只有一个批次）：

| 相对时间 | 窗口跨度 | 刷新器 CPU 权重 | 其中配置保护检查 | 其中 isCurrent |
| --- | ---: | ---: | ---: | ---: |
| 28.092～38.632 秒 | 10.540 秒 | 5.778 秒 | 3.816 秒 | 1.091 秒 |
| 47.434～55.503 秒 | 8.069 秒 | 5.296 秒 | 3.517 秒 | 1.019 秒 |
| 59.775～67.711 秒 | 7.936 秒 | 5.178 秒 | 3.368 秒 | 0.998 秒 |

配置保护与 isCurrent 列重叠，不可相加。刷新器内配置保护路径共 10.701 秒，约占刷新计算 **65.84%**。期间主线程常保持约 65%～68% 单核负载。

### A. SpaceConfigurationSafety 的重复文件查询成为主要业务热点

主要链路：

`NodeSyncStatusRefresh.step → computeNeedSyncGroup / getNeedSync → configurationAvailable → isBlocked → 路径、文件存在检查、读取恢复文件、JSONDecoder`。

源码 `SunSmart/Common/Data/SpaceConfigurationSafety.swift`：

- 第 11 行附近的 key 每次计算 SHA256，并逐字节 String(format:) 转十六进制。
- 第 78 行 isBlocked 每次重新创建 recoveryRoot/文件路径，查 state 文件、读取并解码；继续检查 pending-import、pending-reference-cleanup 和 device-deletions。
- 第 809 行 configurationAvailable 可在单节点的多个子检查中反复进入该流程。

本次 isBlocked 全局包含权重 10.559 秒，几乎全部在主线程。相关路径的全局权重包括 URL.appendingPathComponent 3.559 秒、fileExists 2.074 秒、Data(contentsOf:) 约 1.320 秒；这些是嵌套统计，不能相加作为额外成本。

### B. 新增的版本校验自身也做重 I/O

`NodeSyncReadContext.isCurrent` 占 **3.108 秒**。它每次比较 `currentConfigurationAvailable`，后者仍进入 isBlocked 读文件。

`NodeSyncStatusRefresh.step` 在第 79 行之后才开始 6 ms 预算计时，前面的 isCurrent 不在预算内；第 128 行发布前再次调用 isCurrent，也在循环预算之外。**因此 6 ms 是循环软预算，不能推导每片总耗时小于 6 ms。**

没有逐片 signpost，不能从该 trace 精确证明单次 step 最长耗时；目前可确认的是累计负担很大，而不是每次 step 都卡住 8 秒。

### C. 普通组直接查询仍有字符串转换成本

`ProximityLightingTopologyContext.members` 仍有 1.730 秒包含权重，`Model.isSubscribed(to:)` 为 1.667 秒。栈中可见 String(format:)；实际 SDK 实现是 `subscribe.contains(address.hex)`。虽然比构造 subscriptions 数组轻，但地址字符串仍在循环中生成。后续可将地址转换和订阅索引放到批次准备阶段，并保留虚拟/特殊地址语义。

### 对上一轮验证的修正

MtestiPhone15 的约 20 ms 是隔离替身数据中的调度、拓扑和 Cell 用例，未覆盖真实恢复文件 I/O 和所有 Profile 读取。**它验证了去重和语义保护，不能代表真实数据下的刷新耗时；本次 trace 已证明这一限制会影响实际体验。**

## 4. 很大的诊断开销：libRPAC 回溯记录约 29.96 CPU 秒

后台栈：

`libRPAC.dylib!__generateCulledBacktrace_block_invoke_2 → dyld 地址符号 → dispatch 工作线程`。

- 后台包含该回溯函数的样本为 **29.960 秒，占全部 CPU 52.71%**。若加上主线程的 7 ms，则是 29.967 秒。
- 已确认函数所属 binary 为 `/usr/lib/libRPAC.dylib`；还采到 libMainThreadChecker.dylib。
- 例如 60～68 秒，整体 CPU 155.45%，其中约 **92.05 个百分点**属于回溯记录，刷新器约 **62.80 个百分点**。诊断和业务都在消耗资源。

这支持“运行时检查/回溯记录显著干扰本次测量”的判断。结合当前 Scheme 将 Run 的 Debug 改为 Release、仍选 LLDB，强烈怀疑是 Xcode Run 注入的 Thread Performance Checker 相关开销；该具体开关没有记录在表内，需在录制设置中确认。不能把上述差值直接当作关闭检查器后的实测 CPU。

Apple 明确说明 Thread Performance Checker 默认随 Run 启用，某些 App 会让其额外成本出现在 profile 栈中；推荐用 Profile、让 Instruments 启动 App，或关闭该检查器后重新测量。[Apple：Diagnosing performance issues early](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early?language=objc)

因此 **Release 编译不等于已排除诊断干扰**。复测时保留本次作为诊断线索，并增加一份无上述检查器的可比录制；关闭检查器本身不修复主线程文件访问。

## 5. 九次主线程卡顿：导入、导出、清理和列表工作仍未解决

| 相对起点 | 检测持续时间 | 区间主要业务栈 |
| --- | ---: | --- |
| 16.254 秒 | 494.88 ms | SiteViewController.performSiteLoad → JSON(response) → SwiftyJSON.unwrap；主线程 469 ms 权重 |
| 18.083 秒 | 483.64 ms | SpaceData.update → MeshNetwork.load → Node.load；含 JSON 包装、NetworkKey 衍生密钥计算 |
| 18.998 秒 | 508.16 ms | SpaceData.export；成员快照和 JSONEncoder |
| 27.024 秒 | 460.85 ms | loadSpaceReqeust → SpaceData.update → MeshNetwork.load / Node.load |
| 27.751 秒 | 323.48 ms | UICollectionView 布局、DeviceLightsViewController.cellForItemAt、DevicesViewCell 创建/赋值 |
| 28.515 秒 | 531.73 ms | SpaceSyncCleanupCoordinator.perform → SpaceData.export，成员快照和编码 |
| 29.046 秒 | **756.07 ms** | 清理 extensionChanges、MissingGroupSubscriptionCleanup.subscriptions 和拓扑快照 |
| 29.802 秒 | 295.16 ms | 清理后的列表重建/Cell 布局，少量刷新器交错 |
| 47.230 秒 | 258.91 ms | GroupsViewCell.group.didSet → Group.isOn → Group.nodes，后段有刷新计算 |

总共 6 次 Microhang、3 次 Hang，持续时间合计 **4.113 秒**。这是 Hangs 工具检测的区间时长，不等于各函数 CPU 时间。最后几段存在多个工作交错，不能全部归因给一个函数。

### 主线程二次 JSON 包装

NetworkRequest.request 虽在 responseQueue 解码，但把结果派回主线程后，SiteViewController 第 504 行再次 `JSON(response)["data"]`，会递归遍历大响应。这次有对应 495 ms 卡顿。网络后台解码并不保证页面收到结果后没有重解析/包装。

### 导出减少次数不等于单次已足够快

清理中减少第二次无变化导出已落实，但这里仍见约 532 ms 的导出卡顿，之后 extensionChanges 又占约 756 ms 卡顿中的主要部分。不能仅靠“2 次变 1 次”判断导出问题完成。

单次全局包含采样 SpaceData.export 为 1.018 秒，MeshNetwork.load 为 1.606 秒（其中主线程 0.666 秒），SpaceData.update 为 2.308 秒（其中主线程 2.010 秒）；异步函数/内联栈可能让这些归属重叠，不相加为总阶段时间。

### Cell 同步刷新之外仍有成员扫描

47.230 秒的卡顿中 Group.isOn/Group.nodes 各命中约 99 ms。新批次只覆盖异步状态检查，Cell didSet 中同步读取 Group.isOn 不在该上下文内，仍扫描成员。

旧 trace 未覆盖这些导入/列表阶段且只有约 8 秒，没有 Hangs 不能作为“旧版本不卡、新版本变卡”的证据。但本次足以确认这些问题仍然存在。

## 6. 其他性能结论的边界

- **温度**：本次为 Nominal，未见热状态升级；没有长期耗电和温度数据。
- **蓝牙**：GattBearer 只有约 1 ms 相关采样，没有完整 CoreBluetooth 时序/超时日志；不能确认上一轮发现的发现服务、连接超时是否已解决。
- **内存、泄漏、GPU、帧率**：没有 Allocations、Leaks、GPU 或完整动画帧指标，不能据 CPU trace 宣称这些指标正常。
- **GCD 低级提示**：54 条事件，其中 50 条 Source Missing QoS、4 条 Mutation After Activation；没有 hang-risks 表记录。当前首要证据指向上述业务/I/O 和回溯开销，不将这些低级事件直接判定为主要原因。

## 7. 下一轮处理顺序

1. **建立无诊断干扰的基线**：Product → Profile 或让 Instruments 启动 Release App；核对 Thread Performance Checker 设置。用相同空间和操作录制，比较平均/峰值 CPU 与主线程负担。不是仅把 Run 改成 Release。
2. **优先减掉同步刷新里的重复保护文件读取**：以 account/site/space/network 为范围准备不可变恢复状态快照；权限、导入/恢复/删除日志或配置变更时显式失效。计算过程读内存，保留发布前一致性验证；不能直接移除安全检查或长期缓存布尔值。
3. **让版本判断足够轻，并把全部 step 工作计入预算**：文件读取不应隐藏在 isCurrent getter；对准备、计算和发布分别加 signpost。若完整准备仍很重，使用明确独占/不可变快照在后台准备，再主线程发布。
4. **减少主线程响应包装、Mesh 载入、导出及清理计算**：复用已解码结构；按线程安全边界准备持久化快照、序列化和纯校验，主线程只应用必要变化。保持删除恢复、权限和数据版本保护。
5. **优化成员与列表**：批次级订阅地址字符串/集合；Group.isOn 复用成员/状态结果；减少 Device Cell 初始化、重复页面 reload 和布局工作。

验收应同时看：原多核扫描不再重叠、刷新总 CPU 时间下降、主线程片段及 >250 ms 卡顿减少、同步结果与保护逻辑保持正确。单看 CPU 百分比下降不足以验收。

## 8. 本次产物

- 本报告：`docs/260915_1723_release_ipad_cpu_trace_analysis.md`。
- 临时导出：`/tmp/release_ipad_llh_toc.xml`、`release_ipad_llh_samples.xml`、`release_ipad_llh_events.xml`、`release_ipad_llh_diagnostics.xml`。
- 完整解析结果：`/tmp/release_ipad_llh_rows.json`、`release_ipad_llh_summary.json`；旧版本对照见 [旧 trace 分析](260915_1632_ipad_cpu_trace_analysis.md)。
