# iPad CPU 同步检查修复与验证

## 结论

已按 trace 的优先级修复同步状态重复计算、拓扑/订阅成员扫描，并减少无变化清理的重复导出。修改保留在当前工作区，未提交 Git。

原 trace 中 14 个后台线程在同一窗口重复执行同步检查，主要开销为每节点重建全空间拓扑以及 Model.subscriptions 构造数组。本次消除了三个已确认入口的独立 global queue 作业，并共享批次内实际计算结果。

## 实现

### P0：共享刷新及配置版本保护

- 新增 `NodeSyncStatusRefresh`，合并分组 Cell、设备页、空间缓存预热请求。同一个 owner 的新请求替换旧请求；Cell 复用、设备页离开时取消旧回调。
- 同一批次每节点只检查一次，预热仍处理完整节点集合。同步读取分片运行于主队列，以适应现有 live Mesh 对象的访问方式，每片使用 6 ms 软预算。
- 新增 `NodeSyncReadContext`，复用节点分组、组成员、基础空间拓扑及 Site Zone 目标。待加入成员继续使用 additionalGroupMembers，保留 exitFailure、Space Zone 和 Site Zone 合并规则。
- 网络对象、子网、账号、区域、两个数据库 revision、配置可用状态和设备缓存失效代数变化时，丢弃旧批次并重算；发布前再次验证，失效计算不写回本片节点缓存。
- 版本不可读取时保守显示待同步，不持续空转。跨空间旧请求不提交回调。
- 缓存仅服务当前批次，结束后释放，未建立跨批次永久缓存。

### P1：降低成员查询成本

- 已知普通组直接调用 SDK `isSubscribed(to:)`；虚拟组、特殊地址或不在网络中的组保留 subscriptions 查询，避免改变主 Element 默认 All Nodes 等语义。
- 日程的组/场景组成员判断、sensor publication 成员数量复用批次索引；Node.group 在该批次内每节点只读取一次。
- SDK 未修改，仍使用 workspace 解析出的 release revision `a6246b1`。两个新增源文件已加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，均只加入一次。

### P2：无变化清理复用导出

- `SpaceSyncCleanupCoordinator` 保存本次持久化读取快照。
- 无修复写入、数据库 revision 未变化、时间戳一致时，清理回读复用第一次导出的结果和网络。
- 有变化、基线验证/删除恢复期间写入、版本未知时仍完整导出回读；权限/恢复上下文、拓扑、扩展数据、时间戳及待删除保护继续检查。
- 此项将无变化清理中的完整导出从 2 次减为 1 次。导入、独立备份和云上传仍有各自的工作；没有将整个导入/导出流程移到后台，也不能据此宣称原日志所有秒级停顿已消失。

## 验证结果

### 真机隔离测试

2026-09-15 17:07，在允许使用的 **MtestiPhone15** 上安装并运行隔离自检 App，进程退出码 0：

> PASS: 500 nodes, 14 readers, 1 plan, 500 subscription reads, 0.020 s; overrides, Site targets, schedules, cancellation and invalidation; Cell reuse and marker PASS

- 500 节点、7 个组请求、6 个设备页请求、1 个完整预热共用 1 次基础拓扑；断言每节点仅检查一次。
- 普通组、待加入成员、退出失败、Space Zone、Site Zone、日程目标与原逐节点计算对照通过。
- owner 替换/取消、批次中失效重算、账号/区域/数据库/配置可用状态变化、未知 revision 和跨网络请求通过。
- 实际 `GroupsViewCell` 与 SnapKit 在真机运行；旧结果不会覆盖复用后的组，同步图标设置正确且布局尺寸大于零。原有布局约束未改。
- 用例使用生产刷新器、生产拓扑/任务生成代码，SDK、数据库与部分节点同步读取由替身隔离；20 ms 是合成场景批次墙钟时间，不是原 iPad 数据的全功能耗时，也不是 CPU 降幅。
- 首轮 XCTest 因真机 IDE 连接中断未启动用例，随后使用 App 自检入口验证。自检中的同步 RunLoop 等待已改为 async 等待，避免测试本身阻塞主队列。

### 构建与回归

- 五个品牌 scheme 的 Debug、iphoneos、generic/platform=iOS、无签名构建均成功；最终 SunSmart 构建再次通过。
- `check_node_sync_status_refresh.py`：通过。
- `check_space_sync_readback_reuse.py`：生产 cleanup perform 通过；无变化导出 1 次，变化/未知版本 2 次；失败回读、旧上下文和待删除状态不可完成清理。
- `check_space_sync_cleanup.py`、`check_site_zone_cleanup_loading.py`：通过。
- `check_path_topology_persistence.sh`（含邻近照明、导入隔离、删除恢复、回执保护）、`check_site_trigger_zones.sh`、`check_timed_scheduler_single_owner.sh`：通过。
- `git diff --check`、project.pbxproj plist 校验及五 target 源文件成员校验：通过。
- 构建仍有已有的品牌资源/重复源文件和 AppIntents 提示；本次未处理无关配置。

## 复测范围与限制

6 ms 是让出队列的软预算，不能抢占单次节点计算或首次全空间计划；尚未测得原 iPad LLH 数据上的最长片段。完整业务中的 Profile、日程、恢复检查可能比隔离数据更重。

未操作 iPad LLH，未进行 BLE 连接/云端写入实测，未宣称 485% 已降至某一数值或 UI 体验已人工验收。建议人工使用同一构建配置及原 500 节点空间复测：

1. 进入空间并等待网络加载，连接 Dongle，连续切换 Devices / Groups / Scenes。
2. 用相同采样方式录制 20～30 秒 Time Profiler；对比平均/峰值 CPU、累计 CPU 时间、后台线程数、主线程最长忙碌段。
3. 确认同步按钮和组同步图标正确，快速滚动/复用无旧标记覆盖；修改 Profile、成员、日程和 Site Zone 后可重新显示待同步。
4. 检查 BLE 服务发现/连接超时是否仍出现；若仍存在，依据新 trace 和回调队列进一步区分蓝牙链路与计算阻塞。
5. 单独观察 `[SiteImportTiming]` 的导入/导出耗时；本次后台 CPU 修复不替代该阶段的性能复核。

## 文件

- 核心：`SunSmart/Common/Data/NodeSyncReadContext.swift`、`NodeSyncStatusRefresh.swift`。
- 测试：`Tests/Group/NodeSyncStatusRefreshTests.swift`、`SpaceSyncReadbackReuseTests.swift`。
- 真机工程生成器：`scripts/prepare_node_sync_status_ui_tests.py`，生成至 `/tmp/NodeSyncStatusTests`。
- 原始分析：[trace 报告](260915_1632_ipad_cpu_trace_analysis.md)。
