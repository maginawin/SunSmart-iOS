# HDB 添加设备 preparation 与同步恢复：分析及实施方案

> **For agentic workers:** 用户已确认方案，采用当前会话内实施，使用 `superpowers:executing-plans`。不提交 Git。实施进度和验证记录维护在本文，避免增加重复计划文件。

## 实施进度（2026-10-21）

- 已核对仍为原 HEAD，只有本文未跟踪；已有相关隔离基线可复用。现有工作树已隔离，不另建工作树。
- Task 1 完成：生产 Optional 缓存及 HDB 待同步读取回归均经历 RED → GREEN。
- Task 2 完成：首次 intent 前刷新并保存数量，同时回填用于云同步的 Space 对象；交错回归、失败恢复和 DEBUG 原因已补齐。
- Task 3 完成：英中文 Apply 引导、相关回归、SunSmart Debug generic iOS 构建及最终独立只读审查均完成。
- 任务接口检查：缓存接口、HDB completion 接口及同步页面保持不变；三个任务没有接口命名冲突。按项目要求将执行记录放本文，不额外生成技能账本或自动提交。

**Goal:** HDB 设备完成标准入网后自动完成 preparation；真实失败保留可恢复状态，Main → Lights 的同步入口能够列出并修复这些设备，之后允许设置 Lighting Zones。

**Architecture:** 继续复用 `HDBDeviceAddCompletion`、`HDBDeviceSyncService` 和普通 `SyncExecutionSession`。修复共享读取缓存，并在自动 preparation 前完成设备数量持久化；保留身份、权限、配置版本及严格 ACK 校验。只在确认的失败边界补诊断和回归，不新增第二套同步器。

**Tech Stack:** Swift/UIKit、现有隔离 Swift 回归脚本、NordicSigMeshSDK 本地 workspace。

**Spec:** 本文“目标行为与范围”及用户本轮要求。

日期：2026-10-21。工作树：`feat-HDB-261020`，分支：`feat/HDB-261020`，HEAD：`e6bfecf4e7454b7df0f180df3cd884355291ad42`。分析开始时工作树干净。

## 结论与置信边界

1. **已证实 preparation 没有完成，不能把本次现象解释成设备未入网。** 日志里的 `0x000E` 标准添加成功，之后 HDB Sensor Group 订阅也收到 Success；导出四台灯的初始化签名均为 `pending:`，且 Sensor publication 不完整。日志未出现后续 HDB 初始化命令。
2. **已复现 Lights 不显示同步入口的确定根因。** `NodeSyncReadContext.memoized` 对 Optional 返回类型错误处理冷缓存，导致 Site 查询不执行、HDB 被当成不存在，刷新将设备缓存为无需同步。
3. **已发现并隔离复现自动 preparation 的版本竞态；现场具体触发点仍待诊断确认。** 自动准备先产生云同步，添加页面在准备结束后才保存设备数量。云端上传前的本地 cleanup 可以修正数量并推进 `Space.lastUpdate`。生产 HDB task 在收到相同成功 ACK 时，只因该版本变化就拒绝结果，后继步骤不再执行。现场确实有 cleanup 日志，但没有任务阶段/版本诊断，不能把“数量修正”写成唯一已证实的现场原因。
4. **Apply 拦截符合当前数据。** 添加 Lighting Zone 前要求 preparation receipt 与 Sensor Group 链路完整，四台灯都不满足。应修复准备与恢复入口，不能直接移除拦截或伪造成功签名。

以上为确认前的分析结论。确认后已修改 App 与回归夹具；SDK、原始日志和导出 JSON 均未修改。实施验证见文末。

## 输入与现场证据

- 日志：`/Users/maginawin/Desktop/doing/wwd/add hdb light log.txt`，902 行。
- 导出：`/Users/maginawin/Desktop/doing/wwd/Space_Space 2_20261021_140803_587+0800.json`，采集时间 2026-10-21 14:08:03 +08:00。
- 导出可生成比较配置，`issues=[]`，无 pending import/upload/deletion cleanup；包含 63 个 Lighting Zone 和 4 台 PID `0x2502` 灯。未发现之前 HDB 解码恢复问题的同类阻断。
- 只记录状态和地址，不复制密钥、凭据或初始化签名全文。

| 日志行 | 观察 | 含义 |
| --- | --- | --- |
| 13、675 | 配网成功、添加成功 | 标准 FastAdd 阶段成功，不等于 HDB 后置准备完成 |
| 651、660 | LC Mode 设为 false 并收到对应 Status | 标准配置阶段的关闭 LC，不能当作 HDB 完成证据 |
| 679–714 | 三次 baselineRequest | HDB 初始保存期间云同步流程已启动 |
| 715 | LC `0x0010/0x130F` 订阅 `0xC081` | 已执行一个 HDB 前置链路任务 |
| 763 | 相同元素、模型、组地址的 Subscription Status = Success | 设备没有拒绝这条订阅 |
| 764–776 | 导出及 `SpaceSyncCleanup repairs=[] extensionChanges=0` | 存在本地 cleanup 交错；不能直接解释成 preparation 的成功 |
| 763 之后 | 无后续 publication、HDB vendor/base/参数初始化发送记录 | 后续任务没有在该日志中继续执行 |

| 设备 | 主地址 | Sensor Group | LC 订阅 | Presence 发布 | Ambient 发布 | 初始化签名 |
| --- | --- | --- | --- | --- | --- | --- |
| L2 | 0x0005 | 0xC07F | 已记录 | 缺失 | 缺失 | pending |
| L3 | 0x0008 | 0xC080 | 已记录 | 已记录 | 缺失 | pending |
| L4 | 0x000B | 0xC082 | 已记录 | 已记录 | 缺失 | pending |
| L1 | 0x000E | 0xC081 | 已记录 | 缺失 | 缺失 | pending |

以上是 App 导出的观察状态，不是重新读取四台真实设备后的验收。导出的配置字段 `lightingControl/brightIntensity/dimIntensity/rampUpTime/rampDownTime/holdTime` 全部 pending。`failsafeDelay=synced` 是模型对本地配置字段的现有处理，不能据此推断 preparation 已下发。

## 因果链与相关使用方

### Lights 的缓存缺陷

`DeviceLightsViewController.updateUI` → `NodeSyncStatusRefresh.request(nodes:)` → `context.perform` → `node.getNeedSync()` → `HDBDeviceSyncService.needsSync` → `HDBDeviceSyncContext.resolve`。

- `NodeSyncReadContext.swift` 的 `memoized<Value>` 直接将字典下标结果 `as? Value`。当 Value 是 `SiteData?` 时，缺失字典项也能形成可解包的“Optional(nil)”，从而提前返回 nil，不执行数据库读取闭包。
- `HDBDeviceSyncContext` 因 Site 为 nil 返回 nil；`needsSync` 将 nil context 解释为不属于 HDB，返回 false。
- 刷新将 false 写入 `node.cacheNeedSync`，Lights 隐藏底部 Sync 按钮；点击入口又使用 `node.needSync` 缓存筛选，因此不能只强制显示按钮。
- 现有 `getNeedSync` 已经 OR HDB 判断，问题不在于少接了 HDB；当前 HEAD 也没有另一个遗漏 HDB 的后台设备 evaluator。
- 全部 memoized 使用方已核对：只有 HDB Site 查询返回顶层 Optional。HDB spaces/type/config/cleanup、Emergency Fire planner、Schedule/Scene reads 返回非 Optional，修复时保持其缓存语义。

纯 Swift 当前工具链复现：同一 `.some(site)` 查询调用两次，原实现的 `read` 次数为 0、结果均 nil。先确认字典存在 Any 值再转型后，`.some` 和合法 `.none` 各自只读取一次，正常缓存。

### 添加完成与 preparation

Classic、Professional、Restore 均使用 `HDBDeviceAddCompletion.run`。已有行为是在 FastAdd 释放传输所有权、标准配置结果应用之后，建立 HDB intent，创建普通 `.devices` 同步计划，再决定添加成功或 `.syncFailed`。

计划顺序：缺少的 Sensor Group 订阅 → 缺少的 Presence/Ambient 发布 → HDB 初始化 → 待恢复 Zone/参数任务。各步骤依赖前一步成功。初始化本身包含基础设置、照明参数、LC Mode 和 Auto；只有严格 ACK 与持久化均完成才写正式 receipt。

版本竞态的具体链路：

1. `HDBDeviceSyncService.prepareIntent` 的新设备登记、Sensor Group 分配、恢复初始化状态分别使用 Store 保存；`HDBConfigurationStore.update` 默认不刷新数量，却立即安排云同步。
2. Classic/Professional 直到 `hdbCompletion.run` 的完成闭包才更新并保存 `deviceCount/luminairesCount`。
3. 云任务在 `resumeUpload` 后进入 `SpaceSyncCleanupCoordinator.prepare`。如果数量和 Mesh 中已新增的节点不一致，cleanup 通过 `ProximityLightingLifecycleCoordinator.commit` 修正数量并推进 `lastUpdate`。
4. `HDBDeviceSyncTask.makeHandles` 捕获 Space revision，`receive` 和 `persist` 均要求版本相同。因此可能在有效回包到达后仍判旧任务失败，后继依赖不再执行。

**现场限制：** cleanup 的 `didChange` 除数量修正外，还可能由 `finishSensorGroupCleanup` 导致。虽然样本无删除清理证据、现象符合数量竞态，日志没有捕获 old/new revision 和拒绝原因，尚不能唯一锁定这次手机执行的具体分支。不能据此修改服务器或放宽整个版本保护。

隔离回放直接编译生产 Store/Context/Service/Task，模拟订阅缓存先应用再交付 ACK。三组均为同一 Success ACK、HDB 内容不变：

| 时序 | persist 结果 |
| --- | --- |
| 版本不变 | true |
| receive 前只令 lastUpdate +1 | false |
| receive 后、persist 前只令 lastUpdate +1 | false |

回放脚本：`/tmp/hdb-subscription-revision-replay/check_replay.py --device-tasks`。临时文件可能被系统清理；正式实施应将行为夹具纳入现有测试。SDK/数据库/云端在此为替身，该结果不等于复现了真实云回调交错。

已核对 SDK：ConfigClient 原地应用订阅并保存；Node.save 不修改 Space 版本，不发送该类通知或替换 Node；ACK 成功回调先于队列完成，App 将完成回调异步交付主线程。没有证据需要修改这些 SDK 行为。

### Apply 与恢复入口

`HDBLightingZoneService.setLightingZones` 对非空 Zone 选择调用 `isPrepared`；初始化 receipt 或 Sensor 链路缺失便返回 `notPrepared`。空选择的合法清除路径不应被新增保护阻断。Lighting Configuration 的下发也共享 readiness 检查，组播另要求 Zone subscription 已完成。

Lighting Zones 设备页 Commands 中已经有 `Sync Device(s)`，直接进入 `.devices([node])`，可绕过 Lights 错误缓存筛选作为现有恢复入口。是否真正修复仍以任务成功和最终 receipt 为准，当前不能保证旧版本手机重试必然成功。

## 目标行为与范围

- 新增：标准入网成功后自动完成 HDB preparation；成功才结束为成功。已入网但准备失败保留设备和 pending，不提示用户重新配网。
- 修复：Main → Lights 显示现有 Sync 入口；同步页列出待修复设备及剩余的订阅、发布、Preparation 或 Zone 任务。沿用现有页面的逐设备任务展示，本次不改变所有灯卡片的图标语义。
- 恢复：四台存量 pending 设备无需删除或重新添加，通过普通同步补齐；已经 ACK 的发布/参数尽量复用现有进度，失败/取消/退出重进保持可恢复。
- Apply：准备完成后允许添加 Zone；仍未准备时提示用户使用真实存在的同步入口，不伪造 preparation 或订阅成功。
- 只修改 App。预计不需要 SDK 新 API、固件、服务器、导出 schema 或历史数据迁移。

## Global Constraints

- 仅 App 端开发；方案已确认，不自动提交、推送或操作真机。
- 复用现有同步器、传输所有权、严格 ACK 和持久化机制。
- 保留账号/Space/节点身份、权限、版本失效保护；真实目标变更和迟到回包必须继续拒绝。
- 用户可见文案同步 English 与简体中文；诊断仅 DEBUG，不打印密钥、签名全文或凭据。
- 共享逻辑影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；不改 target/依赖配置。

## Review Focus

- 冷缓存中合法 nil 与缺失条目必须区分，非 HDB Site 不能被误判需要 HDB 同步。
- 首次 HDB 云同步必须看到完整设备数量，不能由本次添加生成的 cleanup 使自己的任务失效。
- 存储失败不能假成功；批量添加中部分失败不能吞掉其他设备的成功状态。
- 真实配置改变、账号/Space 切换、取消和迟到 ACK 仍需失效保护。
- 存量 partial preparation 重新进入同步与成功后再次进入 Apply 的状态必须连续。

## 已确认实施任务

### Task 1：修复共享缓存和 Lights 恢复可见性

文件：`SunSmart/Common/Data/NodeSyncReadContext.swift`；扩展 `Tests/Group/NodeSyncStatusRefreshTests.swift`、HDB context/service 夹具与相应现有脚本。Lights 控制器、Node 缓存和同步候选筛选作为集成验证对象，只有必要时才修改。

接口：保留 `memoized<Value>(_:read:) -> Value`、`needsSync(node:) -> Bool`、`NodeSyncStatusRefresh.request` 现有接口。

- [x] 补失败测试：`coldOptionalSomeReadsOnce`、`cachedOptionalNilReadsOnce`、非 Optional 缓存；旧实现应在第一个用例失败。
- [x] 修复为先判断字典确有 Any 值，再转换 Value；保持合法 nil 可以被缓存。
- [x] 连接生产缓存与 HDB resolve/needsSync 回归：4 台 pending 在 context 内外一致为 true；准备完成后为 false；普通 Site 为 false；缓存清除后能重新计算。
- [x] 验证刷新结果、Node 缓存、Sync 点击候选一致；运行 `check_node_sync_status_refresh.py` 和 `check_hdb_integration.py --device-sync`。现有刷新测试的无 HDB stub 必须补足，不能只跑原测试宣称覆盖。

### Task 2：保证自动 preparation 的前置持久化与任务完整执行

主要文件：`SunSmart/Main/Device/Model/HDBDeviceAddCompletion.swift`、必要的 `HDBConfigurationStore.swift` / `HDBDeviceSyncService.swift`；扩展 `HDBDeviceAddCompletionTests.swift`、`HDBDeviceSyncTaskTests.swift` 及边界夹具。Classic/Professional/Restore 三个调用方统一核对，优先在共有入口实施。

接口：保留 `run(space:nodes:standardIncomplete:completion:)`；复用 Store 的 `update(space:refreshCounts:_:)` 和 `SpaceData.refreshSummaryCountsFromSpaceMesh()`，不引入新的同步服务。

- [x] 先补“旧数量 + 标准入网完成 + HDB 首次保存立即触发 cleanup”的交错夹具，连接实际 completion/任务推进；验证当前行为能在成功 ACK 下中断，而不是只写源码断言。
- [x] 在首个 HDB intent/云同步之前，对当前匹配 Space 的设备数量进行持久化。只对确需 HDB 的批次执行；失败则保留待同步并结束该批次的 HDB 成功判定。保存从最新持久化 Space 开始，避免旧页面对象覆盖配置。
- [x] 验证首个云同步快照数量正确，数量 cleanup 不再推进当前任务版本；订阅 → 两类 Sensor 发布 → 初始化连续完成并保存正式 receipt。
- [x] 加有限 DEBUG 原因：任务阶段、节点地址、版本 old/new、上下文失效/ACK不匹配/保存失败；不记录敏感值。现场若仍失败，日志应精确区分停止点，不能再次用统一“失败”推断原因。
- [x] 覆盖真实外部变更仍拒绝、部分 ACK 重试、数量保存/receipt 保存失败、取消/迟到回包、混合成功批次、恢复设备与存量 pending。保留当前版本保护；不为本次竞态新增无限重试或整体放宽校验。
- [x] 运行 `check_hdb_device_preparation.py`、`check_sync_execution_session.py`；真实交错若无法在夹具覆盖，明确列为设备日志验收项，不能称已完整修复现场。

### Task 3：明确 Apply 引导并验证完整用户路径

文件：现有 `SunSmart/en.lproj/Localizable.strings` 与 `SunSmart/zh-Hans.lproj/Localizable.strings` 的 `hdb_prepare_required`；验证 HDB Zone 和 Lighting Configuration 共同使用方。

- [x] 将提示明确指向 `Sync Device(s)` 及 Main → Lights 的 Sync 入口；保留 readiness 检查。建议英文：`Complete device setup with Sync Device(s) in Lighting Zones, or use Sync in Main > Lights, then retry.`
- [x] 验证准备未完成仍拦截非空 Zone、完成后允许 Apply、空选择清除仍合法；参数下发与 Zone 组播仍遵守各自前置条件。
- [x] 运行 `check_hdb_integration.py`、`check_hdb_lighting_configuration_service.py`；检查两种语言 strings 格式、现有 key 和五品牌资源引用。
- [x] 一轮修改完成后使用 `SunSmartLocal.xcworkspace` / `SunSmart`，Debug、generic iOS、禁用签名构建一次；沿用工作树固定 DerivedData。当前本地 SDK realpath 为 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，核对时无未提交差异。

## 确认前分析验证（历史记录）

- 已通过：Optional 冷缓存运行探针及候选表达式 some/none 缓存探针。
- 已通过：生产 HDB subscription revision 交错隔离回放（三组结果见上表）。
- 已通过：`check_hdb_integration.py --device-sync`、`--device-tasks`、`--add-completion`。原套件未连接生产 NodeSyncReadContext 与 HDB，也没有实际云 cleanup 时序；原测试绿色不否定现场缺陷。
- 未执行：App 编译、手机 UI/BLE、真实 SQLite/云回调交错、四台灯实际修复及 Lighting Zone 下发。没有修改固件或服务器的依据。

## 最短人工验收（实施后由用户操作）

1. HDB Space 新增一台灯：标准入网后继续完成 preparation，最终显示成功；DEBUG 日志能看见订阅、发布、初始化及 receipt 成功。
2. 用现有四台 pending 灯进入 Main → Lights：Sync 可见，进入后列出未完成任务；完成后退出重进，待同步消失，再 Apply Lighting Zone 成功。
3. 中途断开或取消一次：设备仍保留，待同步不会消失；恢复连接后重试完成。无需重置设备。

用户已确认按以上 App 端范围实施；自动 preparation 的现场具体中断分支仍保留证据限制，通过新增交错夹具与 DEBUG 日志闭合，而非预先断言所有失败都来自数量竞态。


## 实施验证记录（2026-10-21）

- 范围裁定：继续使用现有工作树，按用户要求只更新本文且不自动提交；不另建技能账本或重复计划。最终审查范围是本任务相对 `e6bfecf` 的未提交差异，不审查整个 HDB 功能分支历史。
- 必要关联修复：`refreshCounts: true` 原来只把 groupCount 回填给当前 Space，而云队列使用当前 Space；现同步回填六项 summary，避免数据库已刷新而上传对象仍旧。复用原 summary helper，不新增计数规则。
- Task 1 RED：原缓存分别失败于 Optional 冷读不执行、4 台 pending 在 HDB 读取上下文中消失。GREEN：`check_node_sync_status_refresh.py` 与 `check_hdb_integration.py --device-sync` 通过。Lights 刷新、Node 缓存、点击候选已静态确认共用此读取结果，无需改页面。
- Task 2 RED：`--add-execution` 在生产 completion → Store → HDB planner/task 链路中失败于成功订阅 ACK 的 persist。GREEN：修复前置数量及上传对象后，订阅、两个发布、初始化全部完成，生成正式 receipt，之后 Zone Apply/ACK 成功。首个及后续云快照均包含最新设备和灯具数量；同时核对其他 summary 字段回填。
- 边界回归：真实外部 revision 变化分别在 receive 前和 persist 前发生时仍拒绝 ACK；summary 保存失败无 intent/session/上传并保留待同步；现有测试覆盖部分 ACK、receipt 保存失败、标准配置失败的混合批次、取消/迟到回调、恢复设备和存量 pending。
- 已通过：`check_sync_execution_session.py`；`check_hdb_integration.py`（含未准备时 Apply 拒绝、完成后允许、合法空选择/移除）；`check_hdb_lighting_configuration_service.py`；两种 strings 的 plutil 检查。五品牌共享同一 strings variant，未改资源归属或 target 配置。
- 测试边界：新增夹具使用生产缓存方法、summary 方法、add completion、Store、HDB planner/task 和 Zone service；数据库/SDK/云 cleanup 是边界替身，普通总 planner/session 由替身连接，真实 Session 生命周期另由既有 suite 覆盖。不能将其称为完整 App、SQLite、云端或 BLE 验收。扩展测试曾有一处 throwing precondition 编译错误，修正后通过，不涉及生产逻辑回退。
- 本地 SDK 核对：`SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55f5887e588e71f053ab44e2f6aa53a86a0`，无 SDK 未提交差异。
- DEBUG 诊断：`[HDB][Add]` 报告 summary/intent/session 阶段；`[HDB][DeviceTask]` 报告 subscription/publication/initialization、expected/current revision、ACK 数及拒绝/保存失败原因。不打印完整签名、密钥或凭据。
- 准备总套件最终一轮（`check_hdb_device_preparation.py`，含四个子模式）已通过；代表 SunSmart Debug generic iOS 构建及独立只读审查已完成。真实设备/云端交错及 Main → Lights 体验由用户按上方三步验收。

- 构建通过：`xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020 CODE_SIGNING_ALLOWED=NO -quiet build`，退出码 0。日志中曾输出一条“command failed with exit code 0”的异常诊断；进一步只读核对本次 `A27C2D12-7F04-437A-A53F-E4C5B7F32FDF.xcactivitylog` 明确结束为 `Build succeeded`，无 `Build failed`，修改文件的 object 与 App 产物时间均为本次构建。未 clean 或重跑；已有 weak/implicit-strong-capture 警告未扩展修改。
- 最终审查：独立 `gpt-6-astra` 只读检查本轮差异、Classic/Professional/Restore 调用方、共享 Store 的 Zone 创建使用方及测试边界；未发现可确认新增缺陷，无 Critical/Important/Minor，无放弃判断项。审查没有替代运行验收。
- 最终状态：只保留本任务 App、测试、脚本和本文的未提交修改；无 SDK、固件、后端、依赖或 target 修改，无 commit/push/merge、无真机安装或运行。按项目授权边界保留当前分支与工作树，不追加技能的合并/推送确认菜单。
