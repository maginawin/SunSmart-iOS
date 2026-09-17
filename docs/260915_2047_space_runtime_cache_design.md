# Space 页面运行时缓存：Timed 日志补充分析与优化建议

## 结论

**建议采用 Space 会话级缓存：同一次进入 Space 期间，数据未变化就复用 Group、Scene、Timed 的成员索引和页面状态；真正退出 Space 后释放这些派生缓存。** 同时通过变更事件更新受影响的数据，避免在空间内编辑、同步或接收设备消息后继续显示旧状态。

现有工程已经缓存了日程定义、节点日程记录以及部分节点同步结果。当前缺口主要是：

1. 页面每次出现都刷新整个列表，Cell 又重新计算同步状态。
2. 成员关系、场景/日程目标和同步标记缺少可跨页面重入复用的结果。
3. Timed 每次出现都打印全空间的 Scheduler Model 诊断。
4. 未知设备状态的补读由 Timed 控制器触发，缺少 Space 级的任务归属与重试管理。

因此，单纯多保存一份 `[Schedule]`，或者增加一个“Timed 已加载”的布尔值，对前一份 trace 的十秒卡顿帮助有限。需要缓存的是重复计算的结果及其依赖关系，并管理好设备补读任务。

本次是对 [trace 分析](260915_2040_llh_debug_space_tab_hang_analysis.md) 的补充，只分析和提出方案，未实施代码修改。源码核对时 App HEAD 为 `387a4f04`；SDK 只读检查本地 `one-dev` 工作树。

## 1. 每次打印日志能说明什么

### 1.1 Timed 的三类工作分别由不同入口执行

| 工作 | 当前入口 | 是否每次页面出现都发生 |
| --- | --- | --- |
| 读取本地日程定义、更新列表 | `viewWillAppear` → `updateUI` | 是，读取已有内存数组后执行 `reloadData` |
| 计算并打印诊断信息 | `viewDidAppear` → `debugPrintScheduleDiagnostics` | Debug 构建中是，补读批次结束还会再次打印 |
| 从设备补读 Scheduler 状态 | `viewDidAppear` → `repairUnknownSchedulerModelCachesIfNeeded` | 每次检查入口条件；仅连接可用、命令队列空闲、有未知 Model 且本控制器没有进行中的修复时才提交 |

依据：[TimedViewController.swift](../SunSmart/Main/Timed/Controller/TimedViewController.swift)，第 70、79、182、232、313 行附近。

`[PJUIDebug] enter controller=TimedViewController` 和 `Timed Debug Begin` 表明生命周期/诊断入口运行了，不能据此判断发生了数据库重新加载。长诊断函数还会：

- 对每条日程两次求值 `schedule.existNodes`；这是计算属性，会展开设备、组、场景及待删除目标。
- 对目标节点再次调用 `schedulerSyncDifference`。
- 遍历所有节点的旧日程记录。
- 遍历全空间所有支持 Scheduler 的节点和 Model，打印其状态。

所以日志中只有一条日程、16 个关联节点，仍会输出数百台设备的信息。日志长度不等于向这些设备发送了同样数量的请求。

### 1.2 原始日程定义已有运行时缓存

[MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 第 553 行的 `MeshNetworkManager.schedules` 使用关联对象保存 `[Schedule]`。第 595～606 行的 `loadExtensionData` 在加载空间扩展数据时调用 `Schedule.load` 填充它。

Timed 的 `updateUI` 直接读取这份数组，没有调用 `Schedule.load` 或云端 API。清理、导入、恢复等流程可能另行重新加载数据，应保留其必要刷新语义；日常切页无需重走这些流程。

SDK 中，`MeshNetworkManager.scenes` 读取内存中的网络场景数组，`groups` 筛选内存中的网络组数组。它们也不是每次切页都从设备下载。

### 1.3 页面对象缓存不能替代数据计算缓存

Group、Scene、Timed 的 `viewWillAppear` 都无条件刷新。三个页面已有 `refreshData` 字段，但出现时按需刷新的条件被注释掉；Group 的部分通知还会直接刷新隐藏页面。

即使 WMPageController 复用了控制器，再次出现仍会调用这些刷新入口。恢复按需刷新时，应显式处理首次显示，因为这些字段初始为 `false`，不能直接取消注释就认为首次数据一定能显示。

依据：[GroupsViewController.swift](../SunSmart/Main/Group/Controller/GroupsViewController.swift) 第 80、109、395 行；[ScenesViewController.swift](../SunSmart/Main/Scene/Controller/ScenesViewController.swift) 第 70、223 行。

## 2. 日志中的 unknown：已有部分缓存，但 Model 级证据不完整

### 2.1 两套记录表达不同的信息

| 日志 | 对应数据 | 含义 |
| --- | --- | --- |
| `[schedule-node] … valid=true` | `node.schedulerActions[id]` | 节点级兼容记录中有一条有效日程 |
| `[node-scheduler-model] … state=unknown` | 对应 Model 在 `allSchedulerModelEntrys` 中没有条目 | 尚不能确认这个具体 Model 的日程状态 |
| `state=known entries=[]` | 对应 Model 有一个空字典 | 该 Model 的缓存状态已知，记录为空；不应按缓存缺失重复补读 |
| `owner-model-unknown` | 同步策略选择的 owner Model 没有已知记录 | 无法确认日程是否在正确的普通/Light LC Scheduler Model 上 |

同一个节点可能有两个 Scheduler Model。节点级兼容记录没有提供足够的 Model 归属证据，所以有 `valid=true` 与 `owner-model-unknown` 可以同时成立。

本次日志的 16 个关联节点中，15 个报告 `owner-model-unknown`；L35 报告 `not-applicable`。后者在代码中可能来自缺少所选 owner Model，或目标判定不适用，仅凭该行不能确定具体原因。

依据：[TimedSchedulerOwnerPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift)、[Scheduler.swift](../SunSmart/Main/Timed/Model/Scheduler.swift) 第 12 行，以及 [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 第 1588 行。

### 2.2 设备缓存也有持久化，并非退出页面就自动丢失

本地 SDK 已有以下路径：

- `Node+Propertys.swift`：`schedulerActions` 和 `allSchedulerModelEntrys` 都保存到节点的关联对象。
- `MeshDatabase.swift` 第 958～1019 行：分别恢复兼容记录和按 Element 定位的 Model 记录。
- 同文件第 1262～1293 行：分别序列化兼容记录与 Model 记录，包括已知空 Model。
- `Node+Messages.swift` 第 149～188 行：收到 Scheduler 状态后更新 Model 缓存并调用 `savePropertys`。

App 的部分云数据导入路径只根据节点级 `schedules` 填充兼容记录，[ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 第 2219～2239 行即可看到这种情况。它可以形成“旧记录存在、Model 状态未知”的数据形态。其他可能性包括尚未完成首次补读、补读失败、持久化/解码异常或重新导入；本段日志不足以判定是哪一种。

### 2.3 日志末尾确实在查询设备，但不能证明每次都重建全量批次

`SchedulerGet` 与返回的 `SchedulerStatus(schedules: 0)` 证明有真实蓝牙读操作。十进制地址 9063、9064 分别是十六进制 `2367`、`2368`；它们在前面的 Model 诊断中均为 `unknown`，查询与补读未知状态相符。

其中节点 `14@2365` 的 `2365` Model 已知为空，而 `2367` Model 未知。这说明“节点是否有一份缓存”太粗，必须考虑每个 Model 的状态。

当前补读机制有两项限制：

1. App 以节点为单位挑选任务：任意一个 Model 未知，就将整个节点交给 SDK。SDK 的 `getSchedule(index:nil,nodes:)` 会读取该节点所有 Scheduler Model，半已知节点可能再次查询已知 Model。
2. SDK 的完整读取按节点判定成功；任一相关请求失败，结束处理会清除该节点本批 Scheduler Model 缓存，并恢复读取前的兼容记录。这能解释部分失败后再次看到 `owner-model-unknown` 的可能性。

第二项是现有完整性处理，不能为了速度直接移除。若改为保留按 Model 成功的结果，必须证明该 Model 的状态位图和所有声明存在的日程条目都读完了，保留“不完整”状态，并回归 owner/cleanup 判定。

本段没有 `[SchedulerModelCacheRepair] start/finished` 的批次信息、失败列表及保存结果，无法判断末尾请求是刚创建的批次还是先前队列的继续，也无法确认成功数据是否在下一次进入前被清空。

`Local … not bound to key` 来自 SDK Access Layer 向本地 Model 分发消息的检查。日志已经有 App 接收消息记录，SDK 另有节点状态更新路径，因此这组警告本身不能证明接收或缓存保存失败。实际缓存转换和批次结果仍需单独核对。

`System gesture gate timed out` 与此前 trace 的主线程长任务表现一致；它不能单独证明由打印或蓝牙查询造成。此前十秒卡顿中，日程卡片同步计算约 9.93 秒，诊断打印约 0.34 秒，这些仍是该份 trace 的测量结论。

## 3. 推荐方案：Space 会话缓存＋按依赖更新

### 3.1 缓存生命周期

- 进入 Space、有效网络数据就绪后，创建一个 Space 会话对象，统一持有页面派生状态和读取任务。
- Group、Scene、Timed、Main 引用同一个会话，不在各自页面里再复制一套全空间数据。
- 切换 Tab、进入组详情、弹出编辑页面时保留会话。
- 真正退出 Space 导航流程、切换空间/账户或替换网络对象时，结束旧会话，取消其工作并拒绝迟到结果。
- 退出时释放成员索引、页面显示状态、任务票据、诊断去重状态等临时数据；保留既有持久化配置和已经确认的设备记录。
- 重新进入 Space 时，从当前有效数据创建新会话。是否重新向设备读取，按未知、失效和业务新鲜度策略决定，无需把重新创建 UI 缓存等同于重新读全空间设备。

会话身份至少区分账户/区域、Site/Space、Mesh/子网以及本次进入的唯一标识。派生结果不能跨不同网络对象直接沿用旧的 Node/Model 引用。

[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 已有区分真正离开 Space 流程的 `viewDidDisappear` 条件，可结合其生命周期管理。不能仅在 `viewWillDisappear` 清缓存，因为弹出或进入详情也可能触发；也不能只等 `deinit`，异步任务可能延长对象存活。

### 3.2 需要复用的内容与更新条件

| 层次 | 缓存内容 | 何时更新 |
| --- | --- | --- |
| 原始配置 | 现有网络组/场景、内存日程数组 | 导入、云同步、用户编辑或恢复完成 |
| 成员索引 | 组到节点、节点到组、Element 地址到节点、场景/日程目标集合 | 增删设备、组订阅变化、恢复/退出失败、场景组变化；Profile 改变时更新受影响的 owner 判定 |
| 页面派生状态 | 每个 Scene/Schedule 的同步状态、Group 的成员摘要、可见行数据 | 所依赖配置、设备读回或保护状态变化 |
| 设备观测 | 每个 Scheduler Model 的未知、读取中、完整已知、失效/失败状态 | 完整读回、成功配置、失败、设备重置、组成变化或新鲜度复核 |
| 实时显示 | 在线/离线、开关、亮度、执行动画等 | 收到相关状态或用户操作，局部更新 |

“Space 内加载一次”应理解为：**同一有效版本只准备一次；配置和设备数据有变化时更新受影响部分。** Group 的开关/在线状态不能冻结到退出 Space，否则灯已经改变，页面仍会显示旧状态。

具体例子：

- 反复切换页面、数据未变化：复用索引和同步结果，不调用完整同步计划，不自动打印全量诊断。
- 修改一条日程：更新这一条日程及相关节点的结果。
- 增删组成员：更新该组及依赖它的 Scene、Timed 状态。
- 普通亮度/开关上报：更新相关设备与组显示，避免触发全空间 Scheduler 状态重建。
- Scheduler 完整读回：更新对应 Model 和依赖它的日程状态；合并连续消息造成的 UI 更新。
- 权限或保护状态改变：立即撤销不再有效的操作权限/结果；实际执行时继续进行完整校验。

当前 `ConfigurationSnapshotRevision` 会因任意相关数据库连接的写入变化而失效，适合保守的一致性检查。若把它直接作为所有页面缓存的唯一失效条件，频繁设备写入仍可能导致缓存持续重建。长期方案应补齐按字段/依赖的版本与事件；覆盖不完整时保留保守失效兜底，不直接削弱现有导出、保护和执行路径的校验。

### 3.3 首次进入也应降低计算量

缓存主要改善重复进入。若第一次仍在主线程执行约十秒的完整计算，再把结果缓存起来，首次体验仍然很差。

建议在 Space 数据就绪后建立轻量会话，优先显示当前页面；共享成员索引在不阻塞 UI 的前提下准备，Scene/Timed 状态按需计算，空闲时可低优先级预热。所有页面在相同版本请求同一数据时共享进行中的任务。

UI 配置 Cell 只读取结果。重计算前捕获一致的值快照，将纯计算放到后台；SDK 活对象仍按已有线程归属访问。完成后检查会话和版本，再局部更新可见行。缓存状态需区分“尚未计算”“不可用”“已同步”“需要同步”，不能把默认 `false` 当作已同步。

不要直接把所有现有 getter 包进全局后台队列，也不要把初始化时的全部工作同时提前到 Space 主线程入口。

## 4. 蓝牙补读应由 Space 统一管理

建议将 Timed 自动补读纳入会话级协调器：

1. 同一会话、同一设备/Model、同一有效版本的请求合并；再次进入 Timed 复用正在进行的任务。
2. 完整已知数据（包括已知空）在有效期内复用；未知或失效数据按需读取。
3. 失败仍保留为失败/未知，并记录重试时机；通过重连、明确刷新或有节制的退避重试触发，避免每次 Tab 出现都立即重试同一批离线节点。
4. 首先处理当前日程的目标、owner 和 cleanup Model；其他可能存在残留日程的节点分批扫描。尚未覆盖的残留检查保持未完成，不能因未扫描就宣称全部同步。
5. 执行写入/删除前，复用现有 `ScheduleServer.readUnknownSchedulerState` 的完整性要求，由执行流程确保必要数据已知；展示缓存不能代替执行证据。
6. 离开 Space 后，取消属于该会话的待执行任务并阻止迟到结果写入新页面；不能清空共享 BLE 队列影响其他操作。若 SDK 不支持按任务取消，需要先明确其取消和回调边界。

第一阶段可继续沿用 SDK 的节点级完整读取，只在 App 层管理去重、优先级与重试。进一步优化到“仅读未知 Model”需要扩展 SDK 的读取粒度和完整性状态，并回归半成功、非空位图缺条目、普通/Light LC 双 Model、离线失败等情况。

重新进入 Space 可以启动新的复核周期；UI 应先使用有效的本地配置呈现，设备复核按需继续。若产品明确要求“每次进入都强制全量设备读回”，其通信耗时仍然存在，运行时缓存无法消除这部分首次工作。

## 5. 建议落地顺序与验证标准

### 第一阶段：直接处理重复切页

1. 将全量 Timed 诊断改为按需导出，或同一会话/诊断版本只打印一次；默认只输出简短统计，全部保留在 `#if DEBUG` 内。
2. Group、Scene、Timed 加入首次加载与数据变化判断；隐藏页面积累需要更新的项，重新出现时一次应用。
3. 将 Scene/Timed 同步状态从 Cell 的同步计算路径移出，使用共享成员索引和会话结果缓存；Group 背景开关状态也避免再次展开整个组成员。
4. 将补读任务从 Timed 控制器归属迁移到 Space 会话，避免切页决定任务是否新建。

### 第二阶段：处理首次显示和动态更新

5. 完善模型状态与拓扑依赖索引，减少全空间扫描，并合并连续读回引起的计算。
6. 按实际字段变化更新缓存版本，保留保护状态及网络替换的整体失效机制。
7. 测量每个会话的缓存命中、重算原因、读取请求数量、主线程片段和页面显示耗时，再评估 SDK 的 Model 级读取优化。

### 验证标准

- 在无数据变化时连续切换 Group/Scene/Timed：不增加完整同步计划计算次数，不额外新建设备读取批次，不重复输出全量诊断。
- 修改日程、场景关联、组成员或 Profile 后：相关页面立即更新，未受影响页面继续复用。
- 接收开关/在线状态：Group/Main 显示及时更新，不导致全空间同步结果重算。
- 已知空 Model 不反复补读；失败、半成功、旧兼容记录存在但 owner 未知等状态不得被标记为完整已同步。
- 退出 Space、进入其他空间、返回原空间，以及编辑页关闭、应用回前台时，缓存生命周期符合预期，旧请求不污染新会话。
- 同一数据量下对比首次显示和重复显示的 trace；关闭自动日志不能作为十秒计算问题已经解决的证据。

本次完成了源码与日志含义的核对，未运行构建、真机或 UI 验收，未声称已获得优化后的性能数字。
