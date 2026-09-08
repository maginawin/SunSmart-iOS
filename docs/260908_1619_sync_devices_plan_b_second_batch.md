# Sync Devices 方案 B 第二批：全部场景构建、轮次保护与执行策略

日期：2026-09-08。工作区：`refactory-sync-devices`。承接 [方案 B 计划](260908_1544_sync_devices_plan_b.md) 与 [首批结果](260908_1555_sync_devices_plan_b_first_batch.md)。

## 1. 当前交付范围

本批完成阶段 1C，并完成阶段 2 的第一部分：成功判定、消防重试参数、普通重试重置和返回结果汇总。阶段 3 的完整同步会话尚未抽离，阶段 4 的实际页面验收尚未执行。

控制器由最初 4,034 行、首批后 3,327 行，降至 2,176 行。行数仅说明职责迁移规模，不作为正确性证据。

### 全部场景构建

- `SyncTaskPlanBuilder` 覆盖现有 14 类 `SyncType`，组合普通设备、网关、Profile、Scene／Schedule、开关、消防、参数、Dongle 和邻近照明构建器。
- 保留既有 Node／业务 planner 的需求计算。Group 成员数量、Profile 上下文、PIR 保护与跨 Group 补充范围仍由原输入决定。
- 构建结果包含 sections、初始状态、邻近任务引用和诊断；后台构建期间不再不断写页面 sections。主线程 `installTaskPlan` 一次安装，退出页面后丢弃迟到结果，避免再次自动开始和弹出旧诊断。
- 默认删除分区在前；电池开关配置分区在前。保留父引用、依赖边、Proxy 顺序及初始失败状态。
- 消防 planner 错误从后台 HUD 操作改为结果诊断，安装结果时显示；原本静默失败的入口仍不额外提示。
- 19 个构建方法／分支经去除空白与注释后核对逻辑一致；其余两个方法的差异是消防错误返回方式及电池图标存在性查询注入。此核对不代替可执行行为测试。
- Builder 仍使用可变兼容模型。电池目标订阅及消防构建保留既有消息非空探测；没有将所有消息提前生成或缓存，也不声称所有构建器都是纯函数。

### 独立缺陷修复

1. **Dongle 删除日程漏建**：旧分支收集删除集合后只遍历配置集合。相同测试输入在旧实现触发 `Dongle delete-only input must produce both removal tasks`。新构建器同时遍历两类输入；删除仍以无效 `SchedulerRegistryEntry` 写入原索引，保留现有消息工厂语义。仅删除、增删混合、空输入及无绑定节点已通过。
2. **STOP／旧轮次收尾**：旧最终收尾可在轮次失效后写状态并调用成功回调；可控测试首先失败于 `STOP must reject old finalization before any state write or callback`。现在主线程收尾先领取当前轮次的一次完成权，再修改状态、持久化和发出事件。
3. **停止时等待无法依赖旧 SDK 回调**：锁定 SDK 的 `stopSendMessage(wait:finishedBack:)` 会替换原完成回调。`SyncRunLifecycle` 独立登记和释放等待者，STOP／新轮次不依赖被替换的回调才能结束等待。迟到回调仅释放自己的等待者。
4. **重复完成回写**：每次发送尝试持有独立 `SyncAttemptCompletionGate`，重复完成不得重复进入 `Node.updateData` 与最终任务状态写入；合法重试使用新领取器。

### 执行策略

- `SyncOperationResultPolicy`：普通操作同时要求 ACK 和业务状态成功；Repair 初始化还要求非空消息；Devices not synced 恢复初始化、电池本体和消防删除清理保留专用结果判定。消防删除仍为 5 秒超时、最多 3 次尝试、间隔 0.2 秒；普通超时仍为 15 秒。
- `SyncRetryPolicy`：迁移设备／步骤／任务重置和 `resyncRelevanceCheck`，保留成功的无关任务，重做必要 TimeSet 与 Profile 前置任务，清理重用 Handle 的响应地址。
- `SyncResultCollector`：迁移 `SyncResultData` 与返回汇总。仍只汇总 section.devices 和 Group 成员，按 Node 合并，遗漏网络节点不返回；不擅自扩展到 Proxy。

## 2. 验证证据与边界

新增测试编译并执行生产构建器／策略，模型、`NodeSyncData` 和相关依赖规则来自生产源码。SDK、数据库及 UI 控件使用替身，不能证明真实 Mesh 执行结果。

| 检查 | 结果 |
| --- | --- |
| `python3 scripts/check_sync_task_builders.py` | 通过：普通／网关／Dongle、独立 Profile 步骤依赖、邻近输入与身份、七类参数；成功判定 40 种组合；重试与结果汇总 |
| `python3 scripts/check_sync_run_lifecycle.py` | 通过：实际收尾函数与实际安装函数；STOP、旧轮次排队完成、每轮一次完成、取消等待、后续合法重试、重复尝试领取、退出后构建完成、手动重试入口 |
| `python3 scripts/check_sync_devices_progress.py` | 通过：连续任务、位数变化、首任务失败、重复失败与重试 |
| `python3 scripts/check_sync_devices_row_display.py` | 通过：设备／Group／Proxy 显示、复用、旧开始事件及重复 UI 写入 |
| `bash scripts/check_efc_controller_flows.sh` | 通过：消防流程契约与缓存测试 |
| `bash scripts/check_wifi_gateway_repair_recovery.sh` | 通过 |
| `bash scripts/check_wifi_gateway_server_information_recovery.sh` | 通过 |
| `zsh scripts/check_timed_scheduler_single_owner.sh` | 通过：owner 与 TimeSet 依赖、重试契约 |
| `zsh scripts/check_site_timeset_call_sites.sh` | 通过 |
| `bash scripts/check_path_topology_persistence.sh` | 通过：包含拓扑、生命周期、Trigger Zone、导入持久化和读回等现有测试组 |
| `bash scripts/check_nordic_sdk_dependency.sh` | 通过：共享远程依赖 |
| 新文件工程登记 | 14 个累计新增生产文件分别登记到五个 App target，无重复新增 |
| `git diff --check` | 通过 |

源码契约按实际职责迁移到明确文件，并保留页面到总装器、总装器到专用构建器的调用检查。没有改成在整个项目任意找到文本即算通过。Scene／Schedule、开关与消防尚未建立完整的真实类型执行夹具；当前证据是迁移核对、现有契约及 App 编译，不称为 14 类端到端执行覆盖。

五品牌构建使用直接 `xcodebuild`、Debug、iphoneos、generic iOS、关闭签名；SDK 仍为远程 release 锁定 `86f5ec9e40148b9cd93e0512702337fcec41dd40`。未修改 SDK、依赖锁、用户文案或资源。

| Scheme | 本批最终构建 |
| --- | --- |
| SunSmart | 通过 |
| Archipelago | 通过 |
| SylSmart | 通过 |
| SLG Sync Plus | 通过 |
| Lumineux | 通过 |

已有工程警告包括部分品牌 Info.plist 位于 Copy Bundle Resources、SylSmart 重复 FSCalendar 编译项以及 AppIntents 元数据提示；不纳入本次修复。

## 3. 后续工作与真机边界

**后续代码工作可以继续，不以用户先做真机测试为前提。** 本批没有将方案 B 整体标记为完成。

1. 阶段 2 后半：迁出电池专用重置、Daylight 恢复、PIR 补偿、消防持久化及共用 Identify 方法，避免仅把发送循环换一个文件。
2. 阶段 3：建立 `SyncExecutionSession` 与传输／授权／延迟接口。应用层任务模型访问需统一到主线程；现在仍存在后台 worker 与 SDK 回调修改模型，本批轮次门禁不等于所有状态已线程安全。
3. 停止补偿与新轮次必须明确串行边界：现有 PIR 补偿使用独立信号量，Profile 快照恢复仍由延迟发送完成，当前执行任务仍与页面展开字段有关。STOP 后立即重试、补偿回调被替换及页面切换中的全局发送所有权，仍需可控传输测试及后续实现。
4. 完成会话迁移后，再做真实 UIKit 布局与页面全路径，以及实际 BLE／Mesh／网关验收：STOP 后重试、入退组、网关授权后动态消息、Dongle 删除读回、电池激活、消防部分删除与重试、PIR／Lux／Profile 补偿。未运行 Simulator，也未将无签名 generic iOS 构建称为真机验证。

未提交、推送或合并 Git 改动；保留用户原有分析文档和首批未提交内容。
