# Space 运行时缓存分阶段实施结果

## 结论

已落地本轮 App 层优化：Space 内复用有效的成员索引和同步判断，Scene/Timed 的同步计算从 Cell 配置过程移到分片刷新器，Timed 未知状态补读统一归 Space 管理。修改位于当前工作区，尚未提交 Git。

这次优化处理重复计算和任务重复发起。不能据隔离夹具的耗时，宣称原始 iPad LLH 的 10.302 秒 Timed 卡顿已完成体验验收；仍需同数据真机 trace 对比。

## 分阶段变更

### 1. Space 会话与派生缓存

- `NodeSyncStatusRefresh` 在 Space 存活期间保留已完成的上下文、节点状态和 Scene/Timed 查询结果。
- 首次加载扩展数据后开始会话；真正退出 Space 导航流程时释放；`deinit` 作为清理兜底。切 Tab、打开详情不清除会话。
- 网络对象、子网、账户、区域、数据库版本、节点状态代次和保护状态发生变化时重新准备。失败或无法读取版本时不复用结果。
- 页面对象已从当前数据源移除、Cell 被复用、请求被替换、跨网络或退出后，旧结果不能更新新内容。
- 保留 SDK 原有持久化数据；退出时清理的是 App 的派生缓存和待执行任务。重新进入 Space 重建 App 会话，已知设备记录仍按原有策略使用，不强制清空全网读回证据。

涉及：`Common/Data/NodeSyncStatusRefresh.swift`、`NodeSyncReadContext.swift`、`Main/Space/Controller/SpaceViewController.swift`。

### 2. Group、Scene、Timed 页面

- 首次进入或版本/数据变化时更新列表；无变化的再次进入复用页面。隐藏页面只标记需要刷新；使用页面出现状态判断，避免 WMPageController 保留在窗口中的离屏页面持续重载。
- Scene/Timed 使用 `SpacePageSyncRead` 分片检查；每轮主线程预算约 4 ms，发现需要同步即可提前结束。预算在节点检查之间生效，单节点工作仍需继续通过真实 trace 观察。
- 查询保持原有目标、退出失败、待删除 Group/Scene、残留日程检查语义；实际执行写入/删除的完整计划没有替换为展示缓存。
- 待计算/不可用状态沿用现有警示图标；Cell 复用通过请求 ID 和取消机制隔离。
- Group 开关背景读取实时状态，并使用共享成员索引，避免再次完整展开 `group.nodes`。没有把灯的实时开关状态冻结到 Space 退出。
- Timed 生命周期不再调用全网调试打印；诊断方法保留供调试器显式调用。新增摘要输出仍处于 `#if DEBUG` 内。

### 3. Timed 蓝牙补读

- 新增 `SpaceSchedulerReadCoordinator`，Space 持有协调器，Timed 出现只表达读取需求。
- 合并正在执行的需求；每批最多 2 个节点，批次间让出主队列，并等待共享 Mesh 命令空闲。
- 已知空 Model 记录按有效缓存处理；只选存在未知 Model 的非 Dongle 节点。
- 已有日程记录、直接关联日程的节点优先，其余未知节点继续分批。使用既有记录作为优先级提示，避免为排序在页面入口再次展开所有组。
- 每批完成后设置 30 秒重试冷却；失败保持未知，后续进入页面产生新需求且过了冷却才重试。已知成功记录由 SDK 保留并在下次候选筛选时排除。
- 退出或切换上下文后取消后续批次、拒绝迟到的页面更新。已经交给 SDK 的一批仍按 SDK 现有规则结束；不清空共享 BLE 队列。
- SDK 的节点级完整读回、失败回退、执行前未知状态预读保持原样，没有修改 SDK。

### 4. 共享热点

- 复用 Element 地址到 Node 的索引，减少光照传感器查找。
- 同一上下文内只获取一次应急控制器集合。
- 日程 owner 判断复用上下文成员关系，保留显式 Group、恢复 Group 的优先级。
- Main 的节点状态刷新也共享上述上下文；本轮未重写 Main 的设备过滤、排序和列表构建流程。
- 新增文件已登记到 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个 target 的 Sources，各一次。

## 验证

| 检查 | 结果 |
|---|---|
| SunSmart Debug / iphoneos / generic iOS / 禁用签名 | 构建通过 |
| 五个品牌 target 的新增文件引用 | 每个文件各一次；本轮完整构建为 SunSmart，其他品牌未分别构建 |
| `check_node_sync_status_refresh.py` | 通过：命中、设备/数据库失效、退出及析构清理、跨网络、取消、保护读取竞态 |
| 新旧日程查询对比 | 320 组场景通过；执行生产完整计划和生产分片枚举，设备比较结果使用隔离边界 |
| Scene 成员结果对比 | 13 组通过 |
| 补读队列 | 忙碌等待、去重、2/2/1 分批、冷却、断连、退出和跨上下文迟到回调通过 |
| `check_timed_scheduler_single_owner.sh` | owner 策略与 App/SDK 接入契约通过；迁移后的契约定位已更新 |
| `check_timed_scheduler_persistence.sh` | 持久化与读取完整性通过 |
| `check_sync_task_builders.py` | 同步计划、成功/重试矩阵、恢复范围通过 |
| `check_group_page_ui_refresh_coalescing.sh` | 通过 |
| `git diff --check` | 通过 |

### MtestiPhone15 实际运行

使用 `prepare_node_sync_status_ui_tests.py` 生成隔离工程，以 Release、iphoneos、既有 `DEBUG SUNSMART_PERFORMANCE` 条件编译，手动通过 `devicectl` 安装并使用 `--self-test` 启动。夹具不连接用户账户、云端或蓝牙设备。

新版本输出包含 `Space cache hit/invalidation/exit/cross-network`、`320 schedule plans`，以及 `Group/Scene/Timed Cell reuse, layout and marker PASS`，退出码为 0。验证实际生产 Cell 的复用、异步状态更新、图标布局和日程启用/禁用布局。

最终版本运行的 500 节点、50 组、每节点 20 个 Model、15 批次夹具：主线程分片 P95 **4.047 ms**，最大 **6.260 ms**，单批墙钟时间中位数 **0.467 s**。这些是隔离调度夹具指标，不是页面切换端到端时间，也不包含真实 BLE 通信。最后一次显式安装、自检于 21:05 完成，退出码为 0，包含析构清理回归。

XCTest 启动器首次遇到签名团队不匹配，改用设备已有签名团队后遇到 IDE 连接中断（退出码 74）。随后显式安装最新测试 App，直接自检通过；没有将 XCTest 失败记作通过，也没有删除设备上已有应用。相关失败记录位于 `/tmp/SpaceRuntimeCache_20260915*.xcresult`。

## 后续原数据复测

1. 同一 Space 依次进入 Main、Group、Scene、Timed，再循环切换至少 10 次。比较首次和重复进入的耗时、`SyncPageResultHit`、`SyncNodeComputed`、`SyncMainStep` 及 `SchedulerRepairBatch`。
2. 验证修改日程、场景组、Profile、增删成员、同步失败和恢复后，新状态及时显示；开关/在线变化仍及时更新。
3. Timed 读回未结束时切页，再返回，确认复用同一读取队列；断连失败后短时间切页不反复读同一节点。
4. 退出并重进、切到其他 Space、从详情返回、应用回前台，检查缓存生命周期与保护状态。
5. 在 iPad LLH 原有大空间分别录制 Debug 和接近发布配置的 trace，区分 App 同步计算、BLE 等待及原 trace 中 libRPAC 符号化的 CPU 开销。

按字段精细失效、连续读回的进一步合并、Main 过滤排序优化、SDK Model 粒度补读，保留为下一轮有真实指标后的优化。当前仍采用保守整体版本失效，不能保证任何实时消息到来时都命中缓存。最终体验由人工确认。

## 关联

- [原 trace 分析](260915_2040_llh_debug_space_tab_hang_analysis.md)
- [运行时缓存设计](260915_2047_space_runtime_cache_design.md)
- [实施计划](260915_2051_space_cache_implementation_plan.md)
