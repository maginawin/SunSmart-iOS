# P1 空间拓扑主线程阻塞修复与验证

日期：2026-09-15。实施基线：`1a5154b3`，包含 `1a55fe7` 及后续保护快照竞态修复。

## 结论与范围

状态刷新路径已经改为 **主线程分片提取值、后台准备拓扑、主线程读取结果**。首个节点不再同步触发全空间拓扑、Site 计划或待加入组的覆盖计划计算。

本次完成代码修复、定向回归、五个品牌 iPhoneOS 构建及 MtestiPhone15 上的隔离压力测试。生产 App 使用实际账户/空间数据时的整体性能与人工交互验收仍须单独完成，不能将本文的隔离测试数字直接视为生产 App 的完整耗时。

此前 `1a55fe7` 未消除该调用链，分析与约 222 ms 的 macOS 首节点复测见 [提交分析](260915_1802_commit_1a55fe7_p1_analysis.md)。本文不将不同设备或不同夹具的时间换算成性能提升比例。

## 实现

| 位置 | 改动 |
| --- | --- |
| `NodeSyncTopologySnapshot.swift` | 逐组路径/区域成员、逐 Element/Model 提取；4 ms 软预算；保留 SDK 的订阅顺序和组排除规则；形成值输入及组成员索引。 |
| `NodeSyncTopologyStorage.swift` | 捕获账户对应的数据库路径；后台打开独立只读 SQLite 连接；读取持久化 Space Zone、Site 状态和其他空间的 Mesh 输入，调用既有纯策略。 |
| `NodeSyncReadContext.swift` | 移除 getter 中懒构建全空间计划的行为；等待准备完成后提供内存查询；缺少覆盖输入返回不可用。 |
| `NodeSyncStatusRefresh.swift` | 准备完成后才进入节点判断；每个请求记录游标，可见请求优先；最后一个 owner 取消时取消准备；回调核对请求对象身份。 |
| `Database.swift` | `GroupInfo.load` / `Profile.loadAll` 接受显式数据库连接；拓扑读取可跳过不参与计算的光照模板，其他调用保留默认行为。 |
| `project.pbxproj` | 两个新文件加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的 Sources。 |

基础计划每个有效批次构建一次。恢复组按组地址与节点归一化地址准备覆盖计划，只缓存所需节点的目标和相关容量异常。不同显式 Group 的 Bool 判断仍按对象身份分别缓存。

后台不持有活动 Node、Group、Element、Model。其他空间使用专属 SDK 解码对象；不调用旧的 `SpaceData.load` / `MeshNetwork.load`，避免读取期间触发持久化修复、保护状态写入或钥匙串迁移。SDK 本身未修改。

保留 Site 当前及历史成员参与判断、确认版本/schema 校验、主网/空间 Key 证据、旧 `triggerElementAddress` 转换和依赖空间保护。读取失败保持不可用，包括空节点请求，不会产生“已同步”结果。

### 一致性及调度边界

- 沿用账户、区域、网络实例、`NodeSyncStatusGeneration`、保护代数和两库 `ConfigurationSnapshotRevision` 校验；失效批次从头重新提取。
- 后台准备使用串行队列和取消标记；完成回调以弱 context 和取消标记拒绝旧结果。各空间之间检查取消，单次纯策略计算不会被强行中断。
- 活跃保护 writer 沿用基线的保守不可用语义，不忙等；写入结束后的新请求重新读取。未新增持续自动重试策略。
- 采用原调度器的局部状态扩展，没有另建全局状态机；已覆盖新准备阶段的替换、取消、失效和恢复组分支。
- SDK 常规 GATT 接收使用 `CBCentralManager(... queue: nil)`，配置状态处理沿接收链执行；App 的组拓扑提交、恢复组保存和清理路径继续通过保存/清缓存使读取失效。此项是相关路径代码核对，不能等同于整个 SDK/App 的线程安全证明。

## 验证

### 定向回归

以下均通过：

- `check_node_sync_status_refresh.py`：首节点压力、单批去重、1/14 owner、普通/退出/显式组、Space Zone、Site 目标、日程、恢复组、空输入不可用、保护准备竞态、拓扑准备取消/替换和提取期间失效。
- `check_profile_persistence.py`：真实 Profile/GroupInfo SQLite 校验；新增只读连接在全局数据库切换后仍读取原库的用例。
- `check_space_protection_snapshot.py`。
- `check_sync_task_builders.py`。
- `check_proximity_scoped_import.py`。
- `check_space_sync_cleanup.py`。
- `check_space_sync_readback_reuse.py`。
- `check_space_recovery_receipts.py`。
- `check_site_trigger_zones.sh`。
- `git diff --check`。

真机新增 `NodeSyncTopologyStorageTests` 直接装配生产读取器、DTO、纯策略、SQLite 和 SDK 解码，覆盖两空间目标合并、非主 Element 的 Vendor 地址、旧地址格式及越界、历史成员、未确认 Site、主 Key 不一致、损坏 Space/远端 Mesh、依赖空间保护及读取零写入。GroupInfo 在此夹具中隔离，其正式持久化实现由上述 Profile 回归另行验证。

### 品牌构建

直接 `xcodebuild`、Debug、`iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`：

| Scheme | 结果 |
| --- | --- |
| SunSmart | 通过 |
| Archipelago | 通过 |
| SLG Sync Plus | 通过 |
| SylSmart | 通过 |
| Lumineux | 通过 |

部分品牌仍有已有的资源名称、Info.plist 资源阶段和重复 Compile Sources 警告；本次没有修改相关资源。未使用 Simulator。

### 真机性能

设备为 MtestiPhone15，iPhone 15，iOS 26.6.2（23G90）。SDK 锁定 revision 为 `a6246b1b0409824a3227a9c7cad8140219feb182`。测试工程由 `prepare_node_sync_status_ui_tests.py` 生成；Release `-O`，启用 `DEBUG SUNSMART_PERFORMANCE` 供测量与断言，正式 App 未启用性能宏。

固定 500 节点、50 组、每节点 20 Model。真实 SDK `Model.isSubscribed(to:)` 的字符串查询接入每个 Model 的订阅提取，随后执行生产投影、纯拓扑、读取上下文、调度和节点邻近照明差异判断。Node/Group 容器、非拓扑业务和刷新器的数据库版本源仍为隔离边界。

每次重启运行完整测试套件，其中包含仅首节点的专项测试，以及 15 批交替使用 1 和 14 个 owner 的压力刷新；不将它表述为正式 App 冷启动性能。阈值是完整 `SyncMainStep` / `SyncMainPrepare` 的 P95 ≤ 8 ms、最大 ≤ 16.7 ms，超限直接失败；首节点阶段还要求主线程基础计划次数为 0、主队列探针等待 ≤ 16.7 ms。每个有效压力批次断言只有一个基础计划、每节点判断一次。

五次使用同一构建，App UUID 为 `AA329332-379B-39A7-AFA7-56D157A720FE`（arm64），全部退出码为 0。累计 75 个压力批次：

| 重启轮次 | 首节点最大/ms | 探针等待/ms | 压力 P95/ms | 压力最大/ms | 单批耗时中位数/s | 15 批 CPU/s | 进程峰值/MiB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 4.089 | 3.908 | 4.046 | 6.078 | 0.455 | 6.788 | 204.4 |
| 2 | 4.048 | 3.922 | 4.048 | 5.956 | 0.468 | 6.977 | 199.2 |
| 3 | 4.061 | 3.914 | 4.050 | 6.088 | 0.492 | 7.275 | 198.9 |
| 4 | 4.062 | 3.880 | 4.048 | 6.163 | 0.482 | 7.128 | 199.0 |
| 5 | 4.063 | 3.864 | 4.050 | 6.081 | 0.496 | 7.344 | 198.9 |

所有轮次均通过 SDK、存储、并发请求和 Cell 复用检查。每轮保护文件读取为 30 次，主线程读取为 0；该计数专指保护文件，不表示主线程没有数据库访问。

macOS 隔离回归的一次记录：P95 4.005 ms，最大 4.009 ms，首节点最大 4.004 ms，探针等待 3.956 ms；15 批 CPU 合计 0.129 s，单批中位数 0.009 s，进程峰值 13.3 MiB。macOS 没有接入 iOS SDK 查询，不与真机时间直接比较。

CPU 是 15 批刷新期间的进程 CPU 增量之和；峰值内存为整个测试进程的 `ru_maxrss`，包含数据构造、SQLite/SDK 测试及 UI，不代表新增拓扑对象单独占用。

同工程还运行正式 `GroupsViewCell` 的复用、同步标记及图标布局检查。此结果属于自动化行为检查，未代替人工体验验收。

## 验证边界与剩余验收

1. 上述压力数据验证了 P1 的拓扑调用链，但刷新夹具的 `ConfigurationSnapshotRevision` 和非拓扑节点判断使用替身；两库真实读取另在存储测试中执行。不能据此宣称生产主线程的数据库检查、所有 getter 或锁竞争均满足 16.7 ms。
2. 生产 `ConfigurationSnapshotRevision.current()` 保留在主线程，用以维持既有两库一致性语义；SDK 写连接的 `busyTimeout` 为 1.5 s。数据库锁竞争及完整生产刷新仍是计划中的未完成性能门槛，本次未通过删减版本检查换取测试数字。
3. 需要在正式 App 的测试空间复测首次进入 Groups/Devices、连续滚动复用、同步标记、导入/清理结束刷新及连续切换空间，并记录带真实性能宏的完整片段；原 iPad 场景由人工操作。
4. 本次没有发送蓝牙 Mesh 配置命令、执行云端同步或修改 SDK，也没有将 P2 清理回读问题纳入改动。构建和自动化检查通过不表示这些业务已完成真机验收。

工作区改动保留供审查，未创建 Git commit。
