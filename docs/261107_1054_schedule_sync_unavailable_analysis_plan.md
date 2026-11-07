# Schedule 1 添加后无法同步：原因与修复方案

日期：2026-11-07，UTC+08:00。工作树 `feat-device-scene-261028`，分支 `feat/device-scene-261028`，HEAD `9b65c8ea`。分析开始时工作区干净。

> 实施更新：用户已确认实施，修复及自动化验证已完成，详见第 8 节。第 1～7 节保留分析阶段的证据与原方案；真实设备／线上闭环仍待人工验收。

## 1. 结论与未完成项

**直接原因是 App 同步前清理流程遗漏了 Timed v3 的共享格式到本地格式转换。** v3 JSON 的 `schedules[].nodeSlots[].identity` 只保存 `unicastAddress`；本地 `Schedule` 模型仍要求完整 `nodeUUID + unicastAddress + deviceKeyFingerprint`。`SpaceSyncCleanupCoordinator.extensionChanges` 将共享 JSON 直接交给本地模型解码，遇到 `Schedule 1` 的非空绑定时抛错。上层吞掉具体错误，记录 `cleanupPreparation / -2004`，UI 显示 “Space data is unavailable. Reopen this Space to retry.”。

本地 Schedule 已创建并保留 `pendingApply`，因此显示 “Devices not synced”。新建和点击该提示重试都经过同一清理入口，重试不会避开缺陷。

**关联问题是新建／编辑后的本地业务意图没有在进入设备同步前持久标记为待上传。** 当前样本的本地 Schedule 与服务器不同，但本地修改时间仍等于上次上传确认时间；提前失败没有设备结果可发布，服务器继续保留空日程。本问题应与解析修复一起覆盖，避免失败、取消、重启后的本地／云端状态继续分离。

已用两份原始样本运行当前生产解析与清理策略，复现具体缺字段错误；复用现有转换入口后，同一绑定恢复结果与原始本地存储完全一致。本轮只分析与留档，未修改 App／SDK 业务代码、数据库、原始样本或服务器，未构建、未操作真机、未发起线上请求。手机实际安装包 revision、完整 SQLite／UI／Mesh／云端闭环仍待实施后验证。

## 2. 输入与数据证据

- App：`/Users/maginawin/Downloads/Space_Space 1_20261107_104824_545+0800.json`
- Server：`/Users/maginawin/Desktop/cannot sync schedule server data.txt`
- Space：`3486A356-ED8F-406C-8C83-EB8422387978`，`Space 1`。

App 文件是 `_debugInspection.purpose=localConfigurationInspection` 的诊断导出；`uploadable=false` 是导出用途标记，不等于云端上传失败的根因，也不能原样作为上传请求。

| 项目 | App | Server |
| --- | --- | --- |
| Space UUID、NetKey、AppKey | 与服务器一致，未记录密钥值 | 与 App 一致 |
| 设备 | L1 / `0010`，L2 / `0013` | 相同节点身份和 Device Key |
| Group／Scene／spaceData | 与服务器一致 | 与 App 一致 |
| `spaceData.timedSchemaVersion` | 3 | 3 |
| Space 级 `schedules` | 一条 `Schedule 1` | `[]` |
| `updateTimestamp` | 1794019535 | 1794019535 |
| 本地 `lastUploadCloudTimestamp` | 1794019535，与本地修改时间相同 | 不适用 |
| Node 级旧 `schedules` | v3 导出不含该字段 | 两台均为 `[]` |
| `custProps.schedulerModelStates` | 不共享 | 无该字段 |

Schedule 1 的业务 ID 为 `0`，目标类型为 devices，目标 `0010`，启用，周四 08:00，action=0。绑定为 slot=0、`pendingApply`，三个 actionAddress 均为 `0010`。共享身份仅含地址；`rawLocal.app.schedules[].nodeSlots.json` 中完整身份、slot、state、actionAddress 均存在。没有证据表明本地 Schedule 丢失或被服务器保存后再删除。

关键诊断位于 `_debugInspection.spaces[0].status`：

- `lastSyncDiagnostic = {stage: cleanupPreparation, error: -2004, localTimestamp: 1794019535, recordedAt: 1794019695}`。
- `recoveryPhase=active`、`recoveryAuthority=writable`、`membershipPhase=joined`、`membershipNetworkMatches=true`。
- `pendingImport=false`、`pendingUpload=false`、`pendingDeletionCleanup=false`、`requiresRemoteImport=false`。
- `comparisonPayloadAvailable=true`、`issues=[]`（这两项在对应 Space 诊断对象上）。
- configuration／nodeIdentities／timed 基线存在；schedulerModels 基线不存在。v3 已不共享 Model 观察，不能仅凭后者或没有 last-complete-export 文件判定本次数据不可用。
- 两台设备本地 Scheduler Model 缓存均为已记录的空 entry 数据；仅凭导出无法证明故障期间设备实际接收过哪些命令。

服务器附带的旧 Node schedules 字段已被当前分支的 v3 输入兼容逻辑忽略。生产策略对本次服务器样本校验通过，因此它不是本次失败点。这与 [先前的 v3 旧字段恢复分析](261107_1019_space_restore_v3_legacy_node_schedules_analysis.md) 是不同阶段的问题。

## 3. 触发链与代码依据

1. [ScheduleAddViewController.swift](../SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift) 的 `saveBtnAction` 调用 `TimedSchedulerBindings.prepare/commit`，先保存 Schedule 和 nodeSlots，再设置 Space schema／计数并进入 `.schedule(schedule)` 同步页。
2. [ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 的 Space export 调用 `TimedSchedulerPayloadPolicy.exportPayload`。v3 输出按既定契约缩减绑定身份，删除 Node 级 Scheduler 观察；本地原始存储不因此缩减。
3. [SyncDevicesViewController.swift](../SunSmart/Main/Space/Controller/SyncDevicesViewController.swift) 在 `buildPreparedTaskPlan` 之前调用 `SpaceSyncCleanupCoordinator.prepareForDeviceSync()`。Schedule 修复按钮同样进入此控制器。
4. [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 的 `perform` 导出 `.cleanupInspection`，执行拓扑规范化，然后调用 `extensionChanges`。当前第 319–325 行仅调用 `repairingStaleBindings`，取出 `schedules` 直接 `JSONDecoder.decode([Schedule].self)`。
5. [Scheduler.swift](../SunSmart/Main/Timed/Model/Scheduler.swift) 的 decoder 使用 `[TimedSchedulerNodeSlot]`；其 identity 要求完整本地身份。共享 v3 `identity={unicastAddress: "0010"}` 导致 `keyNotFound(nodeUUID)`。`repairingStaleBindings` 不负责转换为本地 identity。
6. `extensionChanges` 把 decode 失败映射为 `persistenceFailed`；`perform` 的 `try?` guard 返回 false，defer 写入 `cleanupPreparation / configurationUnavailable`。`NetworkRequest.swift` 将其映射为 `-2004` 和 `configuration_sync_unavailable` 文案，尚未构建本次 Schedule 写入任务。

正确入口已经存在：[TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `decodingSchedules` 先校验整份 Space，再从同一份已验证 nodes 恢复完整身份。`ImportData.swift` 和 `ExportData.swift` 的迁移读取已使用它，清理流程遗漏了接入。无需修改 `Schedule` 解码器，使其接受缺少身份的本地记录。

清理针对整个 Space 的全部 schedules，所以影响不局限于 Schedule 页面：同一 Space 的其他设备同步，以及使用 `prepare/prepareBatch` 的 Space／Site 上传，也可能被这条非空绑定阻断。没有绑定或日程为空时，直接解码没有 identity 可检查，因此之前正常不代表这条路径兼容 v3。

## 4. 本地已保存，但没有待上传标记

[TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift) 的 `commit` 保存 schedules 和 schema，但没有推进 Space 的 `lastUpdate`。新建有目标时直接进入同步；无目标分支才立即发布 `.common`。

[SyncExecutionSession.swift](../SunSmart/Main/Space/Model/SyncExecutionSession.swift) 仅在 `cloudResultChanged` 或已经存在待上传变化时发布云同步通知。本次 preparation 失败发生在 session 开始之前，失败返回和页面返回均不补业务变更标记。

[SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 的 `needUploadCloud` 依赖 `lastUpdate > lastUploadCloudTimestamp`。本次两个值相等，且 `pendingUpload=false`，与本地已有 Schedule、服务器为空的样本一致。这是代码与快照共同支持的状态缺口；尚未对真实页面的强退时序进行运行复现。

## 5. 建议实施范围

### A. 修复共享格式到本地模型的转换

- 在 `extensionChanges` 中复用 `TimedSchedulerPayloadPolicy.decodingSchedules(timedPayload)`，再解码为 `[Schedule]`；首次准备和持久化回读共用此入口。
- 保留既有完整快照校验、ID 唯一性、节点归属、slot／路由合法性、持久化事务与失败阻断。校验失败不能当作空 schedules。
- 不给本地 identity 补空 UUID／空指纹，不绕过 cleanup，不在发送时仅凭短地址临时认领绑定。
- 在真实失败分支补最少量 DEBUG 诊断，区分 Timed 校验／解码与持久化错误，只记录阶段和错误路径，不记录 key、指纹或完整 payload。

### B. 保存意图与待上传状态保持一致

- 新建／编辑实际提交业务变化时，在同一配置事务内使用现有 Space 修改时间／待上传机制持久记录变更，再进入设备同步。事务失败回滚 Schedule、绑定和版本，不假报保存成功。
- 不把所有 `Schedule.save` 或每次 `prepare` 一律视为业务修改，避免观察读取、无变化准备、成功结果重放重复推进版本；完成后使用现有云同步队列与回执机制。
- 审核新增、编辑、启停、删除等直接相关入口，统一“已提交意图”的发布边界，保留 pendingApply／pendingRemoval 的失败与取消恢复能力。已经匹配且确认成功的设备不重新下发。
- 对本次历史记录，修复后重试应保留 ID=0、slot=0 和原绑定；通过已确认 Timed 基线比较识别“本地不同但时间戳未推进”的情况，补现有待上传标记。不能以“存在 pendingApply”单独认定云端缺失，更不能拿服务器 `schedules=[]` 直接覆盖本地记录。
- 权限、账号／Space 切换、正在确认的旧上传、云端更新冲突继续沿用现有保护；基线不足时保留本地数据并进入既有核对流程，不无条件覆盖云端。

### C. 数据结构与责任边界

**本方案不新增、删除或修改数据库表／字段、export JSON Key／类型／层级／默认值／字段语义。** 数据库完整 identity、共享 v3 短 identity、三种 binding state 均保持现行契约；只修复现有转换入口的使用及现有修改时间的写入时机，无结构迁移／回填需求。B 的历史补标记是已有版本字段的状态修复，不改变其定义。

无需 SDK 新 API、固件修改、服务器部署或外部接口变更。业务代码由五个品牌共享，预计影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；实施时确认实际 target 归属，纯共享逻辑以代表 SunSmart scheme 验证。若实施中发现必须改变结构，先另行展示前后契约并取得确认。

## 6. 已执行的验证与边界

临时只读诊断程序 `/tmp/schedule_cleanup_probe.py`：从当前源文件提取生产 Schedule Codable／Profile Codable／weekdays 方法，直接编译生产 `TimedSchedulerPayloadPolicy`、`SpaceSyncCleanupPolicy` 及依赖策略。输入文件只读，完整身份仅在内存比较，不打印密钥或指纹。

| 检查 | 结果 |
| --- | --- |
| App 实际样本拓扑 cleanup normalize | 通过，0 项修复 |
| App 实际样本 Timed canonical | 通过 |
| 当前路径直接解码本地 Schedule | 失败：`Index 0.nodeSlots.Index 0.identity` 缺 `nodeUUID` |
| 同一数据先经现有 decodingSchedules 再解码 | 通过，1 条 Schedule |
| 恢复后的全部绑定与 rawLocal 数据比较 | 完全一致，包括完整身份、slot=0、pendingApply、actionAddress |
| App 样本在内存改为空 schedules 后直接解码 | 通过，验证空列表会掩盖该问题 |
| 服务器实际样本 normalize／canonical／两种解码入口 | 全部通过，0 条 Schedule |
| `python3 scripts/check_space_sync_cleanup.py` | 既有回归通过 |

已有 cleanup 测试主要验证纯快照策略；`SpaceSyncReadbackReuseTests` 将 `extensionChanges` 替换成 fixture，不能覆盖真实 Schedule codec 边界。曾直接向 cleanup 脚本传 App 包装文件；该脚本仅支持根对象或 `data`，不支持 `spaces[0]`，因此该次断言失败属于输入包装不适配。随后诊断程序明确解包后得到上表结果，不能把最初失败当成真实 Profile 损坏。

临时程序隔离了 SDK 基本类型与运行对象，未执行 UIKit、真实数据库事务、BLE 发送和服务器写入。它证明解析根因与现有 adapter 对样本的适用性，不代表完整修复已经通过。

## 7. 实施后的最小验证与人工验收

1. 补脱敏行为回归，覆盖 `exportPayload → cleanup normalize → 实际 extensionChanges 的 Timed 读取 → Schedule decoder → 保存／重载／再清理`，不得以空 schedules 或 mock decoder 替代本次边界。确认重复清理无变化。
2. 覆盖 v3 非空绑定的 pendingApply／synced／pendingRemoval、合法空目标、旧 v1/v2；缺节点、重复 slot／ID、非法路由及完整身份不符仍被拒绝或按既有合法清理策略处理。
3. 覆盖新建／编辑保存后 preparation 失败、取消、无成功 ACK、退出重进、重启；验证本地意图、绑定与待上传版本同时保留。还需覆盖无变化重试、ACK 部分成功、历史漏标记恢复、上传失败重试及旧请求迟到，不重复同步已成功且未变化的目标。
4. 运行受影响 cleanup、Timed 持久化／设备绑定／云回执回归和 `git diff --check`。生产 Swift 修改稳定后，核对本地 workspace／SDK 映射，构建一次 SunSmart Debug generic iOS（不使用 Simulator）。
5. 人工最短验收：更新 App 后保留原 `Schedule 1`，点击 Devices not synced → 修复；应进入 L1 的任务而非 Space unavailable。完成后重新进入页面，查看状态；再读取云端 Space，确认业务 ID=0、slot=0 的 Schedule 和绑定状态一致。随后模拟一次同步失败／取消并重启，确认记录和重试入口仍在，云端最终收敛。设备按时执行另行验证，不能用上传成功代替。

分析阶段仅新增本文档；后续已按授权完成实施，结果如下。


## 8. 实施结果（2026-11-07）

### 8.1 最终改动

- `SpaceSyncCleanupCoordinator.cleanupSchedules` 复用 v3 解码适配器，将经过完整快照验证的短身份恢复为本地完整身份后再解码 Schedule。首次清理与回读共用该入口，非法数据仍失败；DEBUG 日志仅标记验证／解码阶段和错误类型。
- `TimedSchedulerBindings.withLocalChange` 比较实际持久化 Schedule 内容，只对真实变更推进原有 Space 上传版本；排序比较消除日程及绑定遍历顺序影响。使用现有 `configurationTransaction`，业务行、绑定和版本写入任一失败时整体回滚。
- 新建、编辑、启停和删除相关用户入口接入事务边界。普通观察／拓扑准备仍走默认 commit，不因调用 prepare 本身推进上传版本。启停全部失败沿用原回退语义；回退也保存新版本，回退持久化失败则保留已提交值，避免内存与数据库分离。
- 新建／编辑提交后，在进入设备同步之前通过现有通知与队列提交已保存意图。`commitLocalChangeForCloudSync` 先读取已持久版本，防止旧页面对象误认为没有待上传变化；通知不再重复推进同一次业务变更版本。
- 清理回读通过后，对“本地修改时间等于确认时间”的原生 v3 Space 比较已确认 Timed 基线；确有差异才补现有待上传标记。云端已确认的 pendingApply 不触发补标记，重复清理不重复推进版本，权限／导入／旧上传保护仍生效。非空日程缺基线则进入已有配置核对流程。
- 未改变 App／SDK 数据库或 export JSON 结构；没有 SDK、服务器、固件、依赖声明、项目资源或国际化改动。未 commit／push。

### 8.2 验证结果

下列 8 项回归均通过：

| 脚本 | 本轮相关证据 |
| --- | --- |
| `check_timed_slot_persistence.py` | 生产 v3 导出→纯 cleanup→真实 cleanupSchedules／Schedule codec→真实 SQLite→重载→再导出；三种状态、旧格式、空目标、非法归属；版本写入失败整体回滚、重试、重新打开连接、无变化不推进；既有部分成功和启停回退 |
| `check_space_recovery_receipts.py` | 历史漏标记恢复、已确认 pendingApply、保存失败、权限限制、缺基线核对、重复清理；既有上传失败／迟到回执／云本地冲突恢复 |
| `check_space_sync_readback_reuse.py` | 生产 perform 的回读、失败重试、扩展写入失败与不收敛保护 |
| `check_space_sync_cleanup.py` | 完整快照清理、合法空配置、缺设备／Group、Profile 和幂等性 |
| `check_timed_device_slots.py` | 业务 ID 与物理 slot 分离、v3 短身份和 v1/v2 兼容、重配网及占槽保护 |
| `check_timed_delete_result.py` | 清理预约失败／迟到回复不错误删除记录，确认后完成删除 |
| `check_timed_task_replacement.py` | 生产任务准入、替换／迟到回调、解绑、部分成功和启停回退 |
| `check_timed_empty_target_cloud_sync.py` | 实际控制器成功分支与云同步通知；空目标 17 条、新建／编辑提交意图先于设备同步、旧页面采用已存版本、干净无变化不入队 |

SQLite 回归暴露了直接 savepoint 失败后未结束事务的边界；本次新增保存入口改用项目既有配置事务机制后，失败→重试→重新打开连接验证通过。未修改共享 SDK。部分既有测试替身缺少当前生产 API，已补齐其边界声明；未用这些替身代替新增 codec／SQLite 验证。

Swift CLI 编译 SQLite 时默认 clang cache 目录被沙箱拒绝，改用 `CLANG_MODULE_CACHE_PATH=/tmp/sunsmart-scene-clang-cache` 后完成测试，没有删除共享缓存。

再次只读运行用户两份原始样本：App 经修复后的**生产 cleanupSchedules** 解析出 1 条 Schedule，完整绑定与 rawLocal 一致；服务器样本解析出 0 条。旧直接解码路径仍可复现缺 `nodeUUID`，作为失败对照。原文件未修改，未复制到仓库，密钥／指纹未输出。

### 8.3 构建与共享范围

- SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2809c54`；检查时工作区干净，本轮未写入。
- 使用现有 `SunSmartLocal.xcworkspace`，其 workspace 引用 App 工程、Pods 及 `.local-sdk/nordic-sig-mesh-sdk`；正式工程远端依赖未变。
- 一次 SunSmart Debug／iphoneos／generic iOS 构建完成，`CODE_SIGNING_ALLOWED=NO`，退出码 0。原生构建记录为 **0 errors、119 warnings**，App 可执行产物存在。终端出现过编译器“exit code 0 but produced no further output”诊断文本，最终构建记录无错误；不将警告等同运行失败或声称已清除它们。
- 独立 DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-schedule-sync`。未 clean，未操作真机或 Simulator。
- 实际工程核对发现这些生产文件也属于 HSmart，共享范围为 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。改动为无品牌分支的共享逻辑，没有新增资源／SDK API／target 配置风险，本轮以 SunSmart 为代表构建。

### 8.4 验证边界与交付

Schedule 编解码、保存／加载、事务机制使用生产实现并运行于真实 SQLite。测试中的 Space 字段适配器只持久化版本／确认时间／schema；完整 App Space 表、Mesh 对象、UI 调度、设备发送和云传输分别是受控边界，不能视为真机或服务器验收。真实 cleanup 的 Timed 读取函数已直接执行；完整协调器的其他 Mesh 适配由既有回读 fixture 验证。

最终 `git diff --check` 通过。交付保留未提交改动，更新本任务文档；没有操作其他工作树。人工验收沿用第 7 节步骤：保留原 Schedule 1，修复并确认设备任务可执行，重进检查状态，再比对服务器 Schedule 及失败／取消重启后的恢复。服务器接受请求与设备按时执行须分别验收。
