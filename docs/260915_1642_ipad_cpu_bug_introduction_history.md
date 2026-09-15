# iPad 高 CPU 问题的 Git 引入历史

## 1. 结论

针对 [CPU trace 复核报告](260915_1632_ipad_cpu_trace_analysis.md)，**最关键的近期性能退化结构在 2026-09-02 的 `a3680fe54` 引入，2026-09-07 的 `6c496837` 形成当前 trace 中最重的成员扫描路径。**

它们叠加了早已存在的后台任务重复提交和缓存计算不合并问题。不能把本次约 485% CPU 全部归因于 9 月 15 日的某一个提交。

| 问题 | 引入日期（UTC+8） | 提交 | 定位结论 |
| --- | --- | --- | --- |
| 每台设备重建全空间邻近照明拓扑 | **2026-09-02** | **`a3680fe54`** | 主因的关键结构变化；从当前设备所属组检查扩展为全空间计划，普通组内设备也可能走到全空间计算 |
| 每个相关组扫描全部节点、Element、Model、subscriptions | **2026-09-07 17:10** | **`6c496837`** | 新增 `ProximityLightingTopologyContext.members`，形成 trace 中占 72.84% 的调用链；此前已有通过 `group.nodes` 扫描成员的成本 |
| 分组 Cell 每次赋值都提交后台同步检查，无任务合并/结果身份校验 | 2025-03-06 | `1e2465c1` | 原有同步检查改为 global queue；2025-04-03 改成调用 `group.needSync` |
| 设备页每次 updateUI 提交后台同步检查，无任务合并 | 2025-04-03 | `588da2b6` | 直接新增当前 `devices.contains { needSync }` 后台入口 |
| 缓存为空时并发重复计算；进入空间另起全设备缓存刷新 | 2025-12-25 | `bd56258d` | 引入缓存和全设备预计算，但没有共享正在执行的计算任务；是旧问题的未解决部分，不代表缓存整体使性能变差 |
| 日程判断逐设备反查组成员 | 2025-05-10；2026-06-03 扩大复用 | `46b984ba`；`4b7bed6d` | 旧删除日程检查先加入全组成员反查，后提取为 `Schedule.targets` 并用于同步、删除及批量收集 |
| SDK 的 subscriptions 每次构造完整订阅组数组 | 至迟 2023-08-31 | SDK `1ed243eb` | SDK 首次提交已存在；不能称为 2026 年新引入的 SDK bug |
| 主线程完整导入/导出；清理阶段重复导出 | 2026-09-07；2026-09-15 | `d4e4e436`；`54804a09` | 独立的停顿问题，见第 5 节；本次 trace 中没有命中这些函数 |

这里的“引入”指可从代码历史确认的机制变化，**不是已经实测该提交第一次达到 485% CPU**。未进行旧版本真机性能二分。

## 2. 核心拓扑热点：9 月 2 日引入，9 月 7 日改变扫描实现

### 2.1 `a3680fe54`：单设备检查变成全空间计划

- 完整提交：`a3680fe54ad89f5398be84affddd04bfff8d9791`。
- 标题：`doing group trigger zone & space trigger zone`。
- AuthorDate：2026-09-02 14:41:57；CommitDate：2026-09-02 20:20:29，均为 UTC+8。
- 当前位置：[Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)、[GroupProximityLightingData.swift](../SunSmart/Main/Group/Model/GroupProximityLightingData.swift)。

已比较该提交与父提交：

1. 旧 `getNodeSyncProximityLighting` 先检查当前组是否为邻近照明 Profile、是否退出组失败；不符合时直接返回禁用差异或 nil。
2. 符合时只围绕当前组的路径、区域和成员计算当前节点邻居。旧版也读取 `group.nodes`，所以不能说此前完全没有成员扫描。
3. 新版先检查厂商 Model，随后在没有传入 `topologyPlan` 时调用 `makePlan(for: self, contextGroup: group)`。
4. 新增的 `makePlan(for:)` 根据组加载 Space，再调用 `makePlan(space:)`；空间计划枚举所有符合邻近照明条件的组，为每个组构造成员快照，再执行拓扑策略。
5. 当前同步状态入口 `getNeedSyncGroup` 仍不传入共享计划，因此逐节点检查会逐次重建计划。`topologyPlan` 参数虽已存在，但没有在三类 trace 入口之间建立批次复用。

**关键变化有两层：计算范围从当前组扩大为整个空间；判断当前组 Profile 的早期返回被计划计算替代。** 在存在邻近照明组的大空间内，即使被检查节点属于普通组，也可能先计算其他组的拓扑。

邻近照明同步检查本身更早由 `b2c43247`（2025-05-23 09:44:22，`邻近照明路径设置`）加入 `getNeedSyncGroup`。但当时没有空间级 Planner，不能把 2025 年的功能入口当作本次全空间重建的引入点。

### 2.2 `6c496837`：当前最重的 subscriptions 扫描路径

- 完整提交：`6c496837cf7bc4fb5cb914dd3e29135adc736b39`。
- 时间：2026-09-07 17:10:15。
- 标题：`fix: editor import will cause path, trigger zone missed`。

该提交新增 `ProximityLightingTopologyContext`：

- `makeGroupSnapshot` 从读取 `group.nodes` 改为调用 `members(of:nodes:)`。
- `members` 针对一个组过滤全部候选节点，并逐级检查 elements、models、`subscriptions.contains`。
- `makePlan(space:)` 增加明确的网络上下文、节点集和完整性检查。
- `makePlan(for:)` 从根据 `group?.subNetworkId` 查 Space 改为根据 `node.subNetworkId` 查 Space；没有组的节点也能构建空间计划，移除了旧的 group-only fallback。

这与 trace 的实际链路直接对应：单节点计划 → 空间计划 → 组快照 → members → subscriptions。报告中 members 包含权重为 26.732 秒、占 72.84%。

**9 月 7 日是当前具体扫描实现的引入点；9 月 2 日才是逐节点重建全空间计划的起点。** 由于旧 `group.nodes` 本身也很重，没有前后性能实测，不能宣称 9 月 7 日一定比 9 月 2 日慢多少倍。

## 3. 三个并行入口和缓存问题：2025 年已存在

### 补充：拓扑状态检查是否向设备发命令

第 2 节的拓扑检查本身不发送设备读取或设置命令，使用本地数据计算并比较：

- 期望状态：从内存中的 Mesh 对象、必要时本地数据库加载的 Space/Group/路径/Trigger Zone 配置计算目标拓扑。`MeshNetwork.load` 在此是加载本地网络数据，不是连接设备读取。
- 已知设备状态：读取 Node 的 `proximityLightingEnabled`、`proximityLightingRelayCount`、`proximityLightingNeighborAddresses`。SDK 中这三个 getter 直接读取关联对象缓存，不执行设备请求；它们不保证是此刻设备实时状态。
- 比较结果：`ProximityLightingTopologyPolicy.mutation` 只返回差异类型，`getNodeSyncProximityLighting` 将其包装为 `NodeSyncData`；页面状态判断只据此判断是否需要同步。
- 后续进入实际同步执行流程时，才由同步任务将差异转换为邻近照明启用、转发次数、邻居地址等设备命令；对应命令构建在 `SyncDevicesCellModel.swift` 的邻近照明分支。

因此，这条高 CPU 热点来自反复执行本地扫描、拓扑计算和比较，不能据此推断 App 同时在大量发送蓝牙命令。其他并行业务是否正在通信，需要单独查看发送日志。

### 3.1 分组 Cell：`1e2465c1`，2025-03-06 11:43:27

当前位置：[GroupsViewCell.swift](../SunSmart/Main/Group/View/GroupsViewCell.swift)，第 33～40 行。

提交把原先直接执行的组内设备同步检查移入 `DispatchQueue.global().async`，结果再派回主队列。没有合并重复任务，也没有在结果回写前核对 Cell 是否仍代表原来的 Group。

`588da2b6`（2025-04-03）随后把闭包里的组内设备遍历换成 `self.group.needSync`，保留同一并发结构。因此不能依据当前 `self.group.needSync` 那一行的 blame，把并发问题误判为 4 月 3 日才出现。

trace 实际采到 7 个线程执行该类入口；Cell 复用后结果错位是代码风险，trace 没有证明已发生 UI 错位。

### 3.2 设备页：`588da2b6`，2025-04-03 18:01:37

当前位置：[DeviceLightsViewController.swift](../SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift)，第 347～352 行。

该提交在 `updateUI` 非编辑分支新增 global queue，遍历 devices 判断 needSync，完成后更新同步按钮。父版本没有这段入口；当前仍没有正在检查标记、取消或按数据版本合并。

trace 中有 6 个线程运行这种检查，说明多个后台检查在同一窗口内重叠。是否针对同一节点或同一版本，仍不能从采样确定。

### 3.3 全设备预计算与非合并缓存：`bd56258d`，2025-12-25 17:00:56

提交标题是 `修复设备数量多时判断设备同步状态卡顿问题，增加同步状态缓存`，同时做了三件事：

1. `needSync`、`needSyncGroupData` 改为读缓存，缺失时同步计算并写回。
2. 增加 `reloadSyncStateCache`，直接执行组同步判断及必要的设备同步判断。
3. 进入空间加载完网络、调用 `reloadData` 后，再启动 global queue 遍历全部 realNodes 刷新缓存。

问题在于：页面已能启动检查，预计算也能启动检查；缓存只保存完成结果，没有记录“该版本已有任务正在计算”。关联对象 getter/setter 不会自动把整个“读空 → 计算 → 写回”合为一次操作。

这可定位为**引入缓存时留下的并发缺口，以及新增的第三个计算入口**。缓存对已完成结果仍有优化价值；缺少运行版本对比时，不应断言该优化提交整体造成性能倒退。

后续 `6d7fa6a1`（2026-01-13 17:09:09）将缓存命中的返回值改为同时考虑 `needSyncGroupData`，仍没有增加任务合并。

当前文件：[MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)，第 2408～2445、2613 行附近；[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)，第 756～762 行。

## 4. 日程扫描和 SDK：更早的成本被放大

### 4.1 日程：首次反查与当前公共函数不是同一提交

**`46b984ba`，2025-05-10 17:56:49**：在 `getNodeNeedDeleteSchedules` 中，把仅判断 `schedule.nodeAddresses` 扩展为同时遍历日程组、场景组，并逐组执行 `nodes.contains(self)`。对每个设备、每个日程重新计算组成员的模式在此已经出现。

**`4b7bed6d`，2026-06-03 15:20:33**，标题 `fix: add/remove group members and sync schedulers`：

- 新增当前 `Schedule.targets(node:contextGroup:)`。
- 把上述目标判断集中到 `targets`，同时供 `needsSync`、`needsDelete` 调用。
- 将 `getNodeSyncSchedules`、`getNodeNeedDeleteSchedules` 和批量日程目标收集改为使用这些函数。
- 旧同步路径可直接依据传入 group 的身份判断，新版先反查实际组成员，再使用 contextGroup fallback，扩大了成员扫描的使用范围。

因此，**2025-05-10 是已确认的旧删除路径引入点；2026-06-03 是 trace 中 `Schedule.targets` 这条公共路径的引入及复用扩大点**。不能只把函数创建日期当作整个扫描问题的最早日期。

### 4.2 SDK 热点并非最近更新新增

已核对：项目 `Package.resolved` 指向 release 分支的 `a6246b1b0409824a3227a9c7cad8140219feb182`；本地 SDK `one-dev` 的 HEAD 正是此 revision，且工作区干净。三个热点文件与该 revision 比较无差异。

| SDK 行为 | 可确认历史 | 证据 |
| --- | --- | --- |
| `Model.subscriptions` 拼接全部组和特殊组，再 filter/contains | SDK 首次提交 `1ed243eb`，2023-08-31 10:02:52 | getter 主体 blame 全部落在根提交；仓库不是 shallow clone |
| `Group.nodes` 扫描 realNodes，并查询每个 `Node.group` | `97c97c1a`，2023-09-18 16:58:32 | 当前第 40 行和相应变更历史 |
| `Node.group` 遍历 Element/Model，再读取 subscriptions | `97c97c1a`，2023-09-18 16:58:32 | 循环与 getter 在该提交新增；之后主要修改过滤规则和返回方式 |

这些 accessor 具有真实的计算成本，但不是因此就能判定 SDK 实现功能错误。最近应用层在嵌套循环内反复调用它们，才把既有成本放大成主要热点。2023-08-31 只是当前 SDK 仓库能追到的最早记录，不能认定为上游原始实现日期。

上述版本核对补齐了前一份报告的源码依赖边界；**仍未验证 iPad 安装包 UUID 对应的实际 App/SDK 构建 revision**。

## 5. 9 月 15 日及主线程问题分别贡献了什么

### 5.1 `54804a09`：追加检查和独立的重复导出

2026-09-15 11:17:34，`fix: sync error tasks`：

- 在 `getNeedSync()` 的无组节点分支新增邻近照明等残留配置检查，扩大可能进入重计算的场景。
- 单节点邻近照明判断新增 `SiteTriggerZoneTopologyReader.mergedLocalTarget`；显式传入 plan 时跳过这一步。这是后续批量优化必须保留的语义边界，不应直接认定为已发生的功能 bug。
- 新增 `SpaceSyncCleanupCoordinator`：先导出 original，处理完后再导出 readback；第二次导出在 `didChange` 条件块之外。
- `active` 只合并仍在执行的同空间任务，完成后移除；没有复用已完成且配置未变的检查结果。
- 进入空间改为调用该 Coordinator；云上传及恢复路径也新增调用。顺序发生的入口可再次进行完整检查和导出。

最后三项是上一轮日志中重复全量导出的明确结构来源。但 trace 中 Site Reader 仅占 0.21%，清理 Coordinator 和 export 没有命中，不能将它们作为这次 485% 的首要归因。

### 5.2 `d4e4e436`：2026-09-07 15:01:04 强制主线程执行边界

标题 `fix: space trigger zone sync issues`。对比父提交可确认：

- `SpaceData.export` 的完整 payload 构建从 continuation 闭包改为 `MainActor.run`。
- `SpaceData.update` 新增 `@MainActor`。

这是明确把这些工作固定到主线程的提交。父版本是否也因调用上下文而在主线程运行，不能只根据缺少注解就断言不会；14.819 秒导入和数秒导出是当前数据规模下的日志结果，不能反推历史版本耗时。

### 5.3 最近几个修复没有消除当前主热点

- `cf5e5c13`（2026-09-15 11:37）修改启动恢复和 Site Reader 的加载路径，没有为逐节点空间计划或三类后台入口增加共享计算。
- `744c9e25`（2026-09-15 15:42）处理 Site Zone 清理批次等路径，没有消除本文定位的逐节点拓扑重建。
- `61f87888`（2026-09-15 16:22）主要处理配置导入、Profile 和清理策略，没有改动当前 Planner、日程 targets、Cell 后台检查或缓存计算实现。

所以看到提交标题 `fix: cpu 100% bug` 后仍有 485% 现象，不足以说明该修复引入了新热点；代码证据显示它修的是其他路径。

## 6. 历史范围、验证方法与建议基线

### 历史范围

- 分析基准 App HEAD：`61f878880802472cb43a63ef6eb02b875e162a6f`。
- 开始分析时业务源码干净，仅两份既有 CPU 报告未跟踪。结束时工作区出现其他进行中的同步状态优化改动，包括 `NodeSyncReadContext.swift`、`NodeSyncStatusRefresh.swift` 及相关业务文件；这些改动不是本次分析写入，本文按上述 HEAD 和最初读取的源码追溯，不评价这些新改动的修复效果。源码行号以该分析基准为准。
- 表中日期默认是原始提交 AuthorDate，均为 UTC+8；9 月 2 日同时列出了不同的 CommitDate。
- 已用祖先关系检查确认表中 App 提交全部包含在当前 HEAD 历史中，未把仅存在于其他分支的候选提交算入结论。
- `bd56258d` 和 `6d7fa6a1` 首次进入当前 HEAD 第一父链的提交是 `58bc39c3`（2026-03-25 14:28:25，Merge branch 'power'）。
- `4b7bed6d` 首次进入当前 HEAD 第一父链的是 `b540e06b`（2026-06-03 15:51:02，Merge branch 'sync-profiles' into dev）。
- 这些是当前提交图上的汇入位置，不是 App 发布日期，也不是 site-tz-plus 分支创建日期。

### 已完成与未完成

已完成相关源码、blame、内容增删历史、提交与父提交 diff、SDK 锁定版本、Git 祖先关系的只读核查。未修改业务代码、SDK 或设备状态；只新增本文档。没有构建、运行旧版本或进行真机 CPU 二分，因此不能报告“从某次提交开始稳定出现 485%”或给出各提交的性能倍率。

若需要实测定位性能拐点，最有价值的对照顺序为：

1. `a3680fe54` 的父提交与该提交：验证当前组计算扩展到全空间的影响。
2. `6c496837` 的父提交与该提交：验证成员扫描实现及无组节点处理范围变化的影响。
3. `54804a09` 的父提交与该提交：分别测后台同步检查和主线程清理导出，避免两类现象混合。

对照需固定设备、数据规模、配置、操作与构建方式；旧版本涉及数据迁移/恢复语义，宜使用独立测试数据。此次没有执行回退，也不建议直接整体回退这些包含正确性修复的提交。

**修复重点仍是：为同一有效配置批次共享拓扑和成员索引，并合并后台同步状态检查。** 这同时针对 9 月新增的重计算和旧并发入口，覆盖本次 trace 已证实的主要负载。
