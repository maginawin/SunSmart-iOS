# llh debug.trace：进入 Space 后切换 Scene、Timed、Main 卡顿分析

补充：[Timed 日志含义与 Space 会话缓存方案](260915_2047_space_runtime_cache_design.md)。原始日程定义已有内存缓存，后续优化重点为跨页面派生结果复用、按变化更新及未知设备状态补读管理。

## 结论

**主要原因是切页时在主线程同步计算列表的同步标记，以及进入空间后仍持续执行的主线程同步状态刷新。Scene、Timed 的卡片检查没有接入此前的批量只读上下文，因此仍会重复扫描整个空间的组成员、订阅和保护状态。**

本次 trace 有明确的卡顿事件和对应调用栈：

| 页面或任务 | 实测证据 | 直接原因 |
| --- | --- | --- |
| Timed | 一次 **10.302 秒**的 Severe Hang；其中卡片配置占 **9.932 CPU 秒** | 卡片为了显示同步提示，调用完整日程同步/删除计划；逐节点判断目标时重新展开全组成员 |
| Scene | 首轮两条相邻记录合计约 **4.583 秒**；之后还有 **2.285、2.372 秒** | 每张卡片同步调用 `scene.needSyncGroups`，反复扫描成员并检查保护文件 |
| Main | 设备列表初次显示/重建对应 **0.485、0.374 秒**的卡顿记录 | 主线程加载设备、刷新列表、配置 Cell；同时承受整个空间共享刷新任务的负载 |
| 共享状态刷新 | `NodeSyncStatusRefresh.step()` 累计约 **18.35 CPU 秒**位于主线程 | 拓扑订阅采集、Profile/传感器查询、应急消防关联检查仍有大量主线程工作 |
| 诊断回溯 | `libRPAC` 的回溯生成累计 **51.832 CPU 秒**，约占全部采样 **42%** | 后台符号查找增加整机负载；需单独排除诊断干扰后衡量正式性能 |

这里的 CPU 秒是采样权重，累计值不等于单次操作耗时。Timed 的 10.302 秒、Scene 的各段时间来自 Hangs 表；它们是真实录制到的停顿区间。

**修复应先覆盖 Timed、Scene 的卡片同步检查，再降低共享刷新器的总计算量。** 只优化 `reloadData`、页面动画或关闭 Debug 打印，无法消除已测出的主要工作量。

## 1. 数据与定位可靠性

输入：`/Users/maginawin/Downloads/tmp/llh debug.trace`。

| 项目 | 记录 |
| --- | --- |
| 设备 | iPad LLH，iPad (A16)，iPadOS 26.6.2 |
| 进程 | SunSmart，PID 1342，Attached |
| 时间 | 2026-09-15 20:16:57.785～20:18:42.509，UTC+8 |
| 时长 | 104.723321 秒 |
| 采样 | Time Profiler，1 ms；123,451 条，全部为 Running |
| 全进程累计权重 | 123.451 CPU 秒 |
| 主线程累计权重 | 58.298 CPU 秒 |
| Hangs | 24 条，总计 39.455 秒；其中 Severe Hang 9、Hang 11、Microhang 4 |
| 首末样本 | 相对 5.981248～104.723244 秒 |
| 温度 | 全程 Nominal |
| 缺失调用栈 | 30 条，约 0.024% |
| App 二进制 UUID | `DD38AB58-4A8E-3B28-8BD8-393CDC9C669C`，`SunSmart.debug.dylib` |

找到与 trace UUID 完全一致的本机产物：

`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmartLocal-egeyacjjbvbtjlcsspefcffccarf/Build/Products/Debug-iphoneos/SunSmart.app/SunSmart.debug.dylib`

其 DerivedData 指向当前工作树的 `SunSmartLocal.xcworkspace`。使用匹配二进制及 `atos` 核对了 Scene/Timed Cell、刷新器、拓扑采集函数的源码位置。当前 HEAD 为 `c81fb38c`，提交时间 20:19:13，晚于录制结束；不能直接把 commit 时间当作录制二进制的版本证明。但 trace 已包含 `NodeSyncTopologyCapture` 等新路径，不能将它当成此前优化前的旧记录。

解析完整处理 XML 的 id/ref；同一函数在单条栈内只计一次。下文“包含权重”包含子调用，父子项不能直接相加。采样不能推算函数调用次数或精确的单个刷新分片耗时。

## 2. Timed：十秒卡顿几乎全部发生在日程卡片的同步检查

### 现场证据

相对 **83.746766～94.048712 秒**，Hangs 记录 **10.301946 秒**，主线程运行样本达 **10.292 秒**。

在 `SchedulesViewCell.schedule.didset` 的 9.932 秒样本中：

| 包含的子调用 | 权重 |
| --- | ---: |
| `Group.nodes` | 9.908 秒 |
| `Schedule.targets(node:contextGroup:)` | 9.905 秒 |
| `Schedule.needsDelete(from:contextGroup:)` | 9.349 秒 |
| `Model.subscriptions` | 8.953 秒 |

主要调用链：

`TimedViewController.cellForItemAt` → `SchedulesViewCell.schedule.didset` → `Schedule.getNeedSyncDatas` → 全设备的残留日程删除检查 → `needsDelete` → `targets` → `Group.nodes` → `Node.group` → `Model.subscriptions`。

### 对应源码与放大机制

- [TimedViewController.swift](../SunSmart/Main/Timed/Controller/TimedViewController.swift)：第 70、182 行附近，每次 `viewWillAppear` 都调用 `updateUI`，随后 `reloadData`。
- [SchedulesViewCell.swift](../SunSmart/Main/Timed/View/SchedulesViewCell.swift)：第 74 行，为决定一个提示图标是否隐藏，直接调用 `schedule.getNeedSyncDatas().isEmpty()`。
- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：第 1648 行开始构建完整同步/删除数据；第 1708 行附近遍历 `realNodes` 查找残留日程。每台节点进入 `needsDelete` 后又调用 `targets`。
- 同文件第 1554 行：`targets` 在没有 `NodeSyncReadContext.current` 时回退到 `group.nodes.contains(node)`。这个 Cell 调用路径没有安装上下文。

SDK 的 `Group.nodes` 每次都从全空间 `realNodes` 筛选成员；`Node.group` 又遍历 Element/Model；`Model.subscriptions` 根据整个网络的组列表重新构造订阅结果。因而“对 N 台节点逐一检查日程”内嵌了多次全节点扫描，具有接近平方级的放大因素，实际程度取决于组数、Model 数和提前返回条件。

目前 Cell 只需要一个提示状态，却付出了生成完整执行计划的成本。这条列表路径既没有批量成员索引，也没有利用共享刷新器的临时上下文。

### Debug 日程打印的占比

`debugPrintScheduleDiagnostics()` 在相对 93.692～94.027 秒累计 **0.335 秒**；缓存修复入口约 **0.008 秒**。诊断打印确实拖长 Timed 的显示过程，但无法解释前面的约 9.93 秒。只关打印后仍会保留主要卡顿。

## 3. Scene：组成员扫描之外，还重复访问保护文件

### 现场证据

Scene 卡片配置的累计主线程权重为 **6.794 秒**，其中 `Scene.needSyncGroups` 为 **6.783 秒**。

| 相对时间 | Hangs 时长 | 说明 |
| --- | ---: | --- |
| 74.436229～79.018871 秒 | 合计约 4.583 秒 | 两条记录分别为 2.321、2.261 秒，中间仅约 1 微秒，体验上接近连续停顿 |
| 81.338712～83.623778 秒 | 2.285 秒 | Scene Cell 同步检查主导 |
| 97.918344～100.290147 秒 | 2.372 秒 | Scene Cell 同步检查主导 |

在 Scene Cell 的 6.794 秒样本中：

| 包含的子调用 | 权重 |
| --- | ---: |
| `SpaceConfigurationSafety.configurationAvailable` | 3.880 秒 |
| `SpaceConfigurationSafety.isBlocked` | 3.705 秒 |
| `Model.subscriptions` | 2.617 秒 |
| `Group.nodes` | 2.452 秒 |
| `Data.init(contentsOf:options:)` | 0.471 秒 |
| `deletionCleanupPending` | 0.468 秒 |

保护检查还包括路径生成、`fileExists`、恢复状态 JSON 解码等。**3.705 秒是整个保护检查链的权重，不能全部算成磁盘读取时间。** Time Profiler 没有采集等待线程，也无法由这些运行样本推算完整 I/O 等待时间。

### 对应源码

- [ScenesViewController.swift](../SunSmart/Main/Scene/Controller/ScenesViewController.swift)：第 70、223、251 行附近，每次切入都刷新并重新配置 Cell，`refreshData` 的条件判断被注释掉。
- [ScenesViewCell.swift](../SunSmart/Main/Scene/View/ScenesViewCell.swift)：第 27 行，直接读取 `scene.needSyncGroups.count`。
- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：第 1337 行，遍历场景关联组，再通过 `group.nodes.contains` 对节点调用 `getSyncData(.scenes)`。
- [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)：第 440 行，进入 `getSyncData` 即执行配置可用性检查。
- [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)：第 834 行只在存在 `NodeSyncReadContext.current` 时使用快照；否则进入第 80 行的实时保护文件检查。

因此，此前把保护文件读取移出批量节点检查，并没有自动覆盖 Scene 卡片。`NodeSyncReadContext.current` 只在刷新器的同步执行片段内有效，不是任意页面都能直接复用的全局结果缓存。

## 4. Main 与共享主线程：切换其他页也会受到影响

### Main 自身的直接证据

Main 对应 `DevicesViewController`，其中灯设备列表为 `DeviceLightsViewController`。

- 相对 34.431～34.916 秒有 **0.485 秒**的卡顿，包含 `loadDevices`、`updateUI`、Cell 创建和配置。
- 相对 43.427～43.800 秒有 **0.374 秒**的卡顿，包含再次加载和配置设备列表；其前面紧接清理回读长任务。
- 整段录制中，`DeviceLightsViewController` 相关调用栈累计约 **1.727 CPU 秒**，其中 `cellForItemAt` 约 **1.414 秒**。

这部分证据能确认 Main 的列表停顿。trace 没有页面点击 signpost，无法把每一次用户点击 Main 都与卡顿逐一对齐。若点击发生在 Scene/Timed 的同步长任务期间，主线程必须先完成已有任务才能处理后续切页，这能解释“切回 Main 也不响应”；该点击时序属于根据共享主线程机制作出的推断。

### 批量刷新器仍有大量主线程负载

[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 第 756 行附近在网络就绪后提交全设备预热；[DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift) 第 327～358 行在 UI 更新时取消/重新提交页面请求。

刷新器 `step()` 本体累计约 **18.35 CPU 秒**位于主线程。相关内部热点包括：

| 路径 | 累计权重 | 代码原因 |
| --- | ---: | --- |
| `NodeSyncTopologyCapture.advance` | 6.681 秒 | 主线程逐 Model 读取订阅，采集空间快照 |
| 采集中的 `captureModelUnit` | 6.594 秒 | 内部仍调用成本较高的 `model.subscriptions` |
| `Node.getNeedSyncGroup` | 约 10.00 秒 | 节点级业务判定仍由主线程执行 |
| Profile 同步检查 | 4.849 秒 | 包含反复寻找组绑定的光照传感器 |
| `GroupInfo.ambientLightSensorNode` | 4.667 秒 | getter 扫描 `realNodes`，再匹配 Element 地址 |
| 应急消防关联同步计划 | 2.947 秒 | 包含关联控制器查询和计算 |
| `controllersAffecting(group:in:)` | 2.453 秒 | `DeviceEmerFireStore.devices(in:)` 仍会进入 repository/SQLite 读取 |

代码位置：

- [NodeSyncStatusRefresh.swift](../SunSmart/Common/Data/NodeSyncStatusRefresh.swift)：第 78、140、182 行附近；4 ms 预算在处理单元之后检查，不能中断内部同步函数。
- [NodeSyncTopologySnapshot.swift](../SunSmart/Common/Data/NodeSyncTopologySnapshot.swift)：第 130～147 行，逐 Model 采集 `subscriptions`。
- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：第 1457 行，光照传感器 getter 扫描所有真实节点。
- [EmergencyFireControllerSyncPlanner.swift](../SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift)：第 49 行，按组查询影响它的控制器。
- [DeviceEmerFireData.swift](../SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift)：第 42 行，`devices(in:)` 调用 repository。

采集栈在录制后段反复出现，最后 100.307～104.723 秒仍有 **3.633 秒**采集权重，录制停止时任务尚未结束。当前代码在请求完成或失效后清空 `context/results`，后续请求可能重新采集；但没有批次 ID 和失效原因事件，**不能仅凭这些样本断言发生了多少次重建，或认定某个失效分支出现死循环。**

累计 18.35 秒说明总工作量仍重；它不代表一次 18 秒长任务。本次没有分片起止 signpost，不能用采样直接声称每片是否满足 4 ms 预算。

### 同一录制中的 Group 页补充热点

Group Cell 也有 0.630～0.705 秒的多次卡顿。`GroupsViewCell.group.didset` 的 2.539 秒中，**2.521 秒**发生在 `group.isOn` → `group.nodes`。虽然同步图标已改走批量请求，设置 Cell 背景色仍在现场扫描组成员。

此项有独立的 Group 调用栈证据，不应混写成 Main 自己执行了这些函数。

## 5. 进入 Space 的前置停顿与诊断开销

### 导入、导出和清理仍有前置长任务

相对 15.759～23.573 秒和 30.255～32.767 秒的多段卡顿包含 `SpaceData.update`、`MeshNetwork.load`、节点加载、密钥派生。相对 36.989～43.427 秒的卡顿包含清理导出、扩展清理、回读加载。

这些能够解释进入 Space 前后的停顿，但 Scene/Timed 在 74～100 秒的卡顿有独立列表调用栈。应分别处理进入流程与切页流程。

### `libRPAC` 回溯成本很高

已从 frame 对应 binary 确认 `__generateCulledBacktrace_block_invoke_2` 属于 `libRPAC.dylib`；其后台权重为 **51.832 秒**。其中主要工作是 `dladdr` / `findClosestSymbol`。同一库还出现在 `interposed_sqlite3_step` 栈中；录制也加载了 `libMainThreadChecker`、`libBacktraceRecording`。

因此这份 Debug 录制受到明显的运行时诊断影响。不能据此估计正式 Release 的绝对卡顿秒数，也不能把这 51.832 秒直接加到任意一次页面延迟上。导出的 Hang Risk 日志没有具体条目，无法仅凭库名确定是哪条诊断消息或哪个 Scheme 开关触发了全部回溯。

离线导出时只对 Mac 上的 `xctrace` 使用了 `NSZombieEnabled=YES` 和 `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`，以绕过导出工具异常；这些变量不作用于已经录制完毕的 iPad App。

## 6. 建议修复顺序

### P0：让 Scene、Timed 卡片只消费已计算的页面状态

1. 给 Scene/Timed 增加专属的同步状态结果，按空间、配置版本及设备同步缓存版本统一失效。Cell 配置只读结果，避免构建完整执行计划。
2. Timed 一次建立日程目标节点集合、组成员索引及残留日程状态；列表检查避免每个节点重新展开 `group.nodes`。继续保留 owner/cleanup Model、unknown 状态、残留日程、退出失败、场景间接目标语义。
3. Scene 的展示检查复用批次保护快照及成员索引，避免逐节点读取/解码保护文件。实际执行同步/删除时继续使用完整授权校验。
4. 页面按数据变化刷新；重入同一未变化页面复用状态。结果返回前检查页面、空间、版本和 Cell 绑定，避免展示过期结果。

不能直接把 `Node.needSync` 的总状态当作“该 Scene/该 Schedule 是否需要同步”，否则会把其他配置差异显示到错误卡片上。未知、不可用和已同步也应保留区别。不要通过跳过保护校验或漏掉残留日程检查换取速度。

### P1：降低共享批次的总工作量

5. 在快照中建立 Element 地址到 Node 的索引，替代 `ambientLightSensorNode` 对全节点的反复查询。
6. 在一致版本边界内一次读取应急消防控制器，复用组到控制器关系；将可分离的数据库读取和纯值计算放到后台，主线程仅采集必要的活对象数据及发布结果。
7. 检查拓扑采集的重复启动来源；记录批次 ID、失效原因、采集次数、节点检查次数和每片时长，再决定版本内结果保留策略。
8. Group 背景开关状态使用已有状态或成员快照计算，避免每次 Cell 配置执行 `nodes.isEmpty` 和 `nodes.contains` 两轮成员展开。

SDK 本地开发路径存在，本次仅只读核对 `Sources/NordicSigMeshSDK` 中 `Group+Nodes.swift`、`Node+Propertys.swift`、`Model.swift`。如需优化 SDK accessor，应遵循特殊地址、虚拟组、主 Element 默认订阅等语义，并检查所有依赖 target。

### 测量与验证

- 在同一 iPad、同一空间数据上录制无运行时诊断干扰的 Release 对照；保留 Debug 记录作为问题定位依据。
- 记录页面选择、页面出现、状态批次与分片的起止事件；分别比较首次显示、重复切换、数据变化后的刷新。
- 重点检查 Timed 十秒长任务、Scene 的保护文件读取、Group 的重复成员扫描是否消失；同时检查同步图标、日程残留清理和保护状态语义。
- 最终体验由人工在 iPad LLH 确认。本次未操作设备、未运行 Computer Use，未进行 UI 验收。

## 7. 本次交付与证据位置

已完成完整 Time Profiler/Hangs/Thermal 导出、引用解析、主线程与功能入口聚合、逐段卡顿关联、匹配二进制 UUID 和源码核对。本次只新增分析文档，未修改业务代码、SDK、Scheme 或测试文件。

临时分析文件：

- `/tmp/llh-debug-toc.xml`
- `/tmp/llh-debug-samples.xml`
- `/tmp/llh-debug-events.xml`
- `/tmp/analyze_llh_debug_trace.py`
- `/tmp/llh-debug-summary.json`
- `/tmp/llh-debug-rows.json`
- `/tmp/llh-debug-hangs.json`

本次结论以用户提供的原始 trace 为准；历史报告中的测试和性能数字不作为本次修复或验收结果。
