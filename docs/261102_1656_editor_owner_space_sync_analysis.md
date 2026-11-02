# Owner 删除设备并创建定时后，Editor 保留旧空间数据

分析日期：2026-11-02。分支：`feat/device-scene-261028`，HEAD：`1531a7f9`。开始分析时工作树干净。用户确认“按上述规则实施”后，已在当前工作树完成 App 修改；尚未提交。

## 结论

Owner 的删除和定时数据已经保存到云端，Editor 收到的云端配置也包含这些更新。问题在 App 的导入保护：`reconcileSameVersionNodeRemoval` 将“云端版本更新、设备减少且同时修改其他配置”的正常更新，按“只能删除设备”的条件检查，失败后阻止整份配置导入。

本例 Editor 没有待上传业务改动、上传回执或删除清理任务，仍被标记为 `cloudConfigurationConflict`，保留 3 台设备、L1 的 Group 1 归属以及空定时列表。自动重试进入相同条件，不能自行收敛。

预期应为 Editor 接受完整的新云端配置，显示 L2、L3，Group 1 不再包含 L1，Timed 显示 Schedule 1；必须同步配置和计数，不能只修正列表数字。

## 样本证据

输入：桌面的 `editor export.json`、`editor spaceprops.txt`、`owner export.json`、`owner spaceprops.txt`。所有文件均可完整解析为 JSON。这里不复制网络密钥、设备密钥或用户授权信息。

空间均为 Space 3，UUID 为 `E39A972E-B383-43B0-AAAC-5E30F5D1AEFE`。

| 字段 | Editor 本地导出 | Owner 本地导出 | 两端 spaceprops |
| --- | --- | --- | --- |
| nodes | L1、L2、L3 | L2、L3 | L2、L3 |
| deviceCount | 3 | 2 | 2 |
| schedules 数量 | 0 | 1 | 1 |
| timedSchemaVersion | 1 | 2 | 2 |
| updateTimestamp | 1793608720 | 1793608976 | 1793608976 |
| 本地 lastUploadCloudTimestamp | 1793608720 | 1793608976 | 不适用 |

两个 `spaceprops.data` 对象逐字段比较，仅 `role` 不同（editor / owner）；其余全部相同。云端更新时刻为 2026-11-02 16:42:56（UTC+8），Editor 本地仍停在 16:38:40，落后 256 秒。

Editor `_debugInspection.spaces[0].status` 记录：

- `blockedReason = cloudConfigurationConflict`。
- `lastSyncDiagnostic.stage = sameVersionRemoval.notOnlyNodeRemoval`，错误码 `-2005`。
- `lastReadbackDiagnostic.stage = baselineReconciliation`，`reason = notOnlyNodeRemoval`，本地/确认时间为 1793608720，远端时间为 1793608976。
- `pendingUpload = false`、`pendingImport = false`、`pendingDeletionCleanup = false`、`prefersLocalMembership = false`、`deletionSummary = []`。
- `recoveryPhase = active`、`recoveryAuthority = writable`、`membershipPhase = joined`、`requiresRemoteImport = false`。
- `baselineNodeCount = 3`，配置、节点身份、Scheduler 模型和 Timed 基线均存在；`hasCompleteExportSnapshot = false`。

最后一项仅表示磁盘上没有 `last-complete-export.json`，不能解释成所有基线均缺失。此次记录的拒绝原因也不是 `completeBaselineUnavailable`。

Owner 对应的确认时间已经为 1793608976，`lastReadbackDiagnostic.stage = confirmed`，无待上传或待删除记录。结合两端服务端响应，可以确认本次差异发生在 Editor 应用云端数据的阶段，不需要依赖“Owner 可能未上传”的假设。

### Group 与定时的实际内容

- Group 1 地址为 `C003`；Editor 的 L1 地址为 `0011`，仍保存 `groupAddress = C003`、`groupState = 1`，多个 Model 的订阅中仍有 C003。因此设备列表和 Group 内同时出现 L1，是同一份旧节点配置仍然存在的结果。
- Owner 和云端没有 L1；L2、L3 没有归属 Group 1。本次删除后 Group 1 是空组，Group 和 Scene 自身仍存在。
- Schedule 1 实际是 `selectTarget = 2`（Scene），目标 `sceneAddress = 001C`，即 Scene 1；该场景由 Group 1 的 `scenesDatas.sceneNumber = 28` 关联。并非直接以 `groupAddresses` 关联 Group 1。
- Schedule 1 为 enabled，08:00，`dayOfWeek = 4`，`action = 2`。它的 `nodeSlots`、`deviceAddresses`、`groupAddresses` 都为空，与当前场景下没有剩余目标设备相符。定时记录本身存在；空执行目标不等于应隐藏这条定时。

## 代码根因与完整行为链

1. [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 的 `restoreConfiguration` 在身份及成员关系检查后，调用 `candidate.update`。
2. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 `SpaceData.update` 先验证 Scene 和 Timed 格式、应用权限元数据，再调用 `reconcileSameVersionNodeRemoval`。本例是 Timed v1 → v2，属于升级，不是降级拦截。
3. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 中，该函数条件是 `remoteTimestamp >= timestamp`，并未局限同版本；它也没有在本地干净且云端更新时让出给完整导入。只要远端节点数小于基线节点数，就继续执行“纯删除”检查。
4. [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 的 `SpaceCloudNodeRemovalPolicy.Snapshot.removals` 要求空间配置指纹相等，保留节点的配置指纹也相等。空间指纹包含 `schedules` 和 `spaceData`，所以新增 Schedule 1、Timed v1 → v2 已足以使判断失败。旧回执降级比较分支同样要求投影后的 Timed 基线相等，不能接受本次新增定时。
5. 失败设置 `cloudConfigurationConflict`，返回 `.failed("notOnlyNodeRemoval")`。`SpaceData.update` 随即返回 `.preserved("sameVersionNodeRemovalNeedsReview")`，尚未走到后面的新版本完整导入。
6. 正常完整导入原本会更新节点、Group/Scene、Schedule，并重算 `deviceCount` 和 `scheheduleCount`。由于提前返回，这些变化都没有落地。[SpacesViewCell.swift](../SunSmart/Main/Space/View/SpacesViewCell.swift) 继续读取旧的本地计数，出现 Luminaires 3、Schedules 0；空间内页面同样读取旧配置。

这是“纯删除特例接管正常新版本导入”的路由问题。应先明确新版本的取舍策略，再让同版本等其他分支保留原有校验；不能只删除一个比较条件，而让其他保护、上传回执和恢复任务继续阻止或回写已选定的配置。

### 重试及现有恢复入口

`recoverCloudMembershipIfNeeded → resumeUpload → reconcileSameVersionNodeRemoval` 再次取得同一份云端配置后仍会返回 `notOnlyNodeRemoval`，与样本的 `baselineReconciliation` 诊断吻合。

[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的“重新加载云端数据”只有在 `needsOlderCloudBaselineReview` 为真时才准备 `reviewed-cloud-import.json`。该条件目前只识别 `cloudBaselineNeedsReview`，不识别本例的 `cloudConfigurationConflict`。因此本例会以未建立 reviewed 标记的普通导入再次经过同一拦截。此为代码链路结论，未做真机按钮验证；不能将这个按钮作为已验证的临时恢复方案。

同一保护用于 Owner/Editor 等可写角色，Visitor 在该函数入口直接跳过；影响不限于 Editor 页面，也不限于新增定时。设备数减少并伴随其他业务配置变化时，都应检查是否触发同类错误。具体其他组合没有在本次样本中实测。

## 已确认并实施的规则：更高版本直接采用服务器配置

2026-11-02 用户确认按以下规则实施，替代此前“仅本地干净时接受新版本”的建议。

### 业务规则

采用服务器新版本优先，并明确：这里的版本是 Space 的 `updateTimestamp`，不是 Timed 的 `timedSchemaVersion`，也不是设备固件版本。

| 条件 | 行为 |
| --- | --- |
| 服务器 updateTimestamp > 本地当前 lastUpdate | 自动采用服务器整份空间配置；本地未上传修改、旧上传回执、旧删除/恢复意图和历史“优先本机”选择不否决这次更新 |
| 服务器 updateTimestamp = 本地当前 lastUpdate | 保持现有同版本回读、纯删除和差异核对规则，不扩大为无条件覆盖 |
| 服务器 updateTimestamp < 本地当前 lastUpdate | 保持现有旧版本协调逻辑，不因“高于上次确认版本”就丢掉更新的本地修改 |

以持久化的最新 `lastUpdate` 为准，并核对当前对象、待提交版本和已暂存导入版本，避免用过期对象或较老回执降低比较门槛。异步准备后重新核对版本和操作上下文；准备期间产生更新版本时重新决策。

例如，上次确认 100、本地修改到 120、服务器 110，不满足本次覆盖条件；服务器为 130 时整份使用服务器，120 的未上传改动不再参与合并。用户此前选择“使用本机数据”的旧意图，也会被之后更高的服务器版本替代。

**已确认的实际取舍：** 本机离线修改、未上传删除可能被更高服务器版本覆盖。若服务器仍含本机已经删除的设备，该设备可能重新出现在本机配置中。App 配置覆盖无法撤销已经发送的设备 Reset 或其他物理操作。

### 仍须满足的导入条件

“不保护旧业务配置”不取消导入成立所需的检查：

- 同一账号上下文、Site/Space 和网络身份；权限、密码状态及退出/删除 Space 流程仍按实际授权处理，旧响应不能重新激活已退出空间。
- 必需字段、节点身份、Scene、Profile、Timed、HDB、Proximity 等内容能解析且通过结构/引用校验；合法空数组可导入，缺失必需数组不能当作空配置删除本地数据。
- 支持的旧格式使用现有兼容语义导入。对新版本明确携带的合法 Timed v1 数据，不再仅因本地曾到 v2 就保留旧定时；未知 schema 或无法可靠还原的内容继续报错。审查 `timedSchemaDowngrade`、旧 Zone 缺字段等分支，区分兼容解析要求与保留本地业务数据的偏好，不能仍用后者否决已选新版本。
- 事务、备份、失败恢复和异步上下文校验继续生效；导入失败不标记为同步成功，不清空唯一可恢复的数据。

### 实施范围

1. **统一新版本决策。** 在 `SpaceConfigurationSafety` / `SpaceData.update` 的共享边界识别有效的新版本，优先于纯删除、Profile 合并、本地 membership 偏好、旧删除恢复和旧格式迁移保护。仅在这条路径跳过“保留旧配置”的分支；其他版本路径不批量放宽。
2. **复用完整导入。** 扩展现有配置 checkpoint、持久化导入意图、`pending-import` 和事务导入机制，记录此次自动选择的云端快照及被替代的本地版本；不另外实现一套 Nodes/Groups/Scenes/Schedules 写库流程，也不伪装成用户手动确认。完整预检和持久化选择完成后才使旧操作失效。
3. **替代旧任务而非合并旧意图。** 为此次替换更新恢复代次，暂停/失效该 Space 的旧上传和异步修改，归档被替代的上传回执、设备删除/引用清理、Scene 恢复及本机优先记录。导入期间旧记录不能重放；失败/重启依据持久化选择继续导入，完成后再清除已过期状态和本次冲突标记。不能先全清记录再尝试落库，也不能把“服务器新版本已导入”记成“旧 POST 已确认成功”。
4. **接通所有共享入口。** 覆盖正常分享/空间 GET 导入、页面刷新、`resumeUpload` 中有/无 submission 的回读、进入 Space 的自动恢复和“重新加载云端数据”。已有 `cloudConfigurationConflict` 也按同一版本规则恢复，无需用户退出重加空间。
5. **处理同步队列交接。** `CloudSynchronizationManager` 当前捕获旧 lifecycle，代次变化后会取消整项任务。应识别新配置已接管的结果，禁止继续发送旧 payload；重新读取当前状态，需要兼容规范化回写时排队新版本。Site 批量任务中的其他 Space 仍需继续或重新入队，不能因为其中一项接受云端而丢失其他任务。
6. **刷新完整展示。** 采用已有导入后的计数重算、缓存失效和页面刷新，确保设备、Group 成员、Scene、Timed 与 Space 统计来自同一份配置。保留纯本机展示偏好，不把它们当作待合并的云端业务配置。

生产改动位于 `SpaceConfigurationSafety.swift`、`ImportData.swift`、`SpaceMembershipCoordinator.swift`、`CloudSynchronizationManager.swift`，以及 `DeviceScheduleAddressCleanup.swift` 内的 `SpaceRecoveryState`。新增可选 `cloudImport` 状态，兼容已有持久化记录；设备删除与 Scene 恢复继续使用现有 generation 校验，不另建同步框架。

**在途操作边界：** 已经发出的 POST 或设备命令不能靠忽略回调撤销。当前手机同一 Space 的上传/导入须串行交接，已发请求结束或结果不明时以重新 GET 校验作为后续决策依据，避免旧完成回调污染新状态。不能声称 App 单端取消可保证服务器从未接收旧请求；未知结果继续保留证据并复查，但不再仅为保留旧业务意图而拒绝一个有效的新版本。

### 验证目标与人工验收

优先扩展现有隔离框架的行为用例，不创建新 Xcode 工程：

- 本次真实样本：新版本删除 L1 并新增 Schedule 1，Editor 从 3/0 收敛到 2/1；覆盖完整 snapshot、旧回执和已有 blocked 状态。
- 版本边界：100/120/110 不进入新版本覆盖；100/120/130 覆盖全部旧改动；同版本纯删除、同版本差异和旧云端回读保持原有行为。
- 本地非干净状态：待上传编辑/删除、prepared/accepted/结果未知的旧 submission、本机优先选择、旧 Scene/引用清理记录均不能在接管后回写旧配置。
- 整份配置：删除伴随新增/改名/Scene/Profile/Timed 修改；合法空设备/空 Group/空场景目标的定时仍正确导入；合法 Timed v1 与 v2 兼容，未知格式/坏数据不误导入。
- 失败与并发：预检失败、写入/提交失败、导入中断后重启、旧回调晚到、等待期间本地新修改、退出空间/账号切换，以及 Site 批量中仅一个 Space 被服务器接管。
- 自动重试和手动重新加载均执行相同规则；成功导入后只在产生真实的新规范化改动时回写，不能复活旧节点或旧定时。

按实现差异运行 `check_space_recovery_receipts.py`、相关 import/membership/deletion 回归，并补充上传队列交接的行为测试。共享 Swift 逻辑修改完成后，核对本地 workspace/SDK 映射，使用 SunSmart Debug generic iOS 构建一次；无资源、target 或 SDK API 差异时不重复五品牌构建。

此为五个品牌共用的 App 同步行为。本次未修改 SDK、固件或后端。人工验收由用户完成：重放原始步骤，Editor 显示 L2/L3、Group 1 无 L1、Timed 有 Schedule 1，Space 显示 2/1；退出重进、重启和再次同步后保持一致，Owner/云端不被旧数据覆盖。

### 当前版本机制的限制

`markSpaceUploadNeeded` 使用手机当前秒级时间，并确保大于本机及上次确认版本。这是现有更新时间策略，不是服务器分配的全局递增 revision；手机时钟偏差、跨手机同值或并发写入不能仅靠本次规则彻底解决。本次沿用该版本契约，不扩展为后端版本服务改造，也不据此承诺所有并发场景均能判断真实操作先后。

## 修复前的复现证据

完成四份 JSON 的结构和内容比较；使用现有 `check_space_recovery_receipts.py` 的隔离测试框架，在临时文件中加入本次样本探针，执行当前生产导入前置逻辑、删除比较和恢复判断：

- 真实样本节点身份比较确认仅减少 L1；空间指纹比较拒绝；将远端 schedules/spaceData 替换回旧值的对照可恢复空间指纹相等。
- 模拟 Editor 无待提交改动，分别使用完整 removalSnapshot 和无该 snapshot 的回退路径，均复现 `.preserved("sameVersionNodeRemovalNeedsReview")`，保留 3 台设备和空 schedules。
- 两种情况下自动恢复均仍失败，并保留配置核对状态。

临时探针：`/tmp/sunsmart_editor_sync_probe.py`。使用现有本地 SDK 映射 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` 的测试解码边界；SDK 未修改。首次编译因默认模块缓存目录写权限失败，指定已有可写 Xcode 模块缓存后完成验证。

隔离探针保留真实业务 payload 和生产判断，网络 GET、数据库/SDK 对象为既有测试替身，网络 Key 解码使用替身边界；不能代表完整 App 落库或真机同步验收。此阶段未构建 App。后续实施和验证见下节；全程未运行真机、请求线上服务或修改源数据。四个文件未提供两台手机的 App build 标识，代码定位基于当前工作树；现场诊断与当前代码分支一致。


## 实施结果与验证记录

### 数据接管与恢复

- 新版本判断同时读取当前对象、持久化 Space、上次确认、待提交和暂存导入的时间，避免旧对象或旧确认版本降低门槛；异步预检后的既有版本/上下文核对继续生效。
- 完整预检通过后，先保存 checkpoint 和原始云端快照，再原子切换恢复 generation 与目录。旧上传、删除、Scene 恢复和引用清理记录归档隔离；迟到的旧回执不能确认新状态。保留原始快照，使导入前的兼容规范化即使中断也能重做并保留必要的回写意图。
- 正常 GET、上传前回读、已提交回读和进入 Space 的恢复共用完整导入。失败保留 pending import；重进/重启继续选定快照。完成时清除旧冲突和 syncCloudError，补清异常退出窗口残留的“保留本地修改”标记。
- 同一手机有实际 HTTP 写请求时，导入等待该请求结束并重新 GET。同步队列成功接管新 generation 后继续当前批次；因其他并发接管而失效的任务从磁盘重新排队其余仍需上传的 Space，不发送已捕获的旧 payload。
- 合法 Timed v1 新版本允许替换本地 v2；相同/较旧版本沿用原策略。未知 schema、错误网络身份、无效结构与拓扑仍拒绝。

### 自动验证

现有隔离框架新增 `Tests/Group/NewerCloudImportTests.swift`，执行生产导入前置逻辑、新版本选择、checkpoint/状态切换、回执与 `finishImport`；SQLite/SDK 提交和网络为既有替身边界。上传队列用例执行生产 `CloudSynchronizationManager` 编排，HTTP 为测试替身。

| 验证 | 结果与范围 |
| --- | --- |
| `check_space_recovery_receipts.py` | 最终整轮通过，包含异常退出旧标记清理。覆盖干净/脏本地状态、prepared/accepted 回执、旧删除与本机优先、pending 导入、预检/写入失败、版本边界、Timed v1、重启、两条回读和 HTTP 等待；同版本/较旧版本既有回归保留 |
| 真实 Editor 样本（通过环境变量提供，未入库） | 最终隔离回归通过：节点 L2/L3、Schedule 1、schema 2，历史冲突清除，不再有旧配置待上传 |
| `check_device_add_cloud_batch.py` | 通过：新服务器版本接管后不再 POST 旧配置，同批次其他 Space 的待上传任务继续；原有批量、账号隔离和回执用例通过 |
| `check_space_membership_lifecycle.py` | 通过：成员关系、退出/重加及旧响应隔离的既有回归 |
| `check_hdb_import_recovery.py` | 通过：HDB 导入、恢复及坏数据拒绝；更新测试替身以匹配共享导入入口 |
| `check_cloud_node_import.py --snapshot <editor spaceprops>` | 通过：真实两节点快照的解码/暂存边界 |
| `check_space_sync_cleanup.py --snapshot <editor spaceprops>` | 通过：两节点快照，其余配置保留，Proximity 无额外修改 |
| `check_device_permanent_deletion_cleanup.sh` | 通过：删除清理及持久化状态兼容回归 |
| SunSmart Debug / generic iOS | 最终代码构建通过（2026-11-02 17:32，iPhoneOS 27.1 SDK） |

本地入口为 `SunSmartLocal.xcworkspace`，SDK 实际映射到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `dbcf6f1`，SDK 无本任务改动。构建使用 `iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，固定 DerivedData 为 `SunSmart-feat-device-scene-261028-cli`。纯共享逻辑没有新增资源或品牌条件路径，使用 SunSmart 代表构建，未重复其他四品牌。

本次未执行真机、真实 HTTP 服务或完整 App 数据库运行验收。原始场景仍需人工验收：Owner 删除 L1 并创建定时后，Editor 显示 Luminaires 2 / Schedules 1；进入后仅 L2/L3，Group 1 无 L1，Timed 有 Schedule 1；退出重进、重启和再次同步后保持一致，并确认 Owner 未被旧配置覆盖。另用两台手机验证离线本地修改遇到更高服务器版本时整份采用服务器，与已确认取舍一致。

## 2026-11-02 审查问题修复

三项问题均已用新增行为回归复现并修复，修改继续落在当前工作树；此前未提交改动保留。

| 问题 | 修复与边界 |
| --- | --- |
| 新版本缺少 Proximity schema，旧本地 Zone 引用已删除的节点/Group，导入反复失败 | 新版本整份替换及其 pending import 重试，在预检阶段采用初始化的 Zone 兼容语义：缺字段或旧格式空数组解析为空 Zone。预检与事务落库使用同一结果；明确提供的有效 Zone 仍保留，同版本/较旧版本的兼容保护不变 |
| POST 回读采用更高版本并修复引用后，规范化改动漏排队 | 接管 lifecycle 后记录云端导入；原 handle 完成并移除后，共用已有队列交接机制，从持久化状态筛选仍需上传的 Space，按普通队列延迟自动补传。已确认的批次成员不重复上传，旧 POST 不确认新版本；后续上传失败沿用既有持久回执和恢复机制 |
| 每次导入归档全库备份，存储无界累积 | 有效导入完成后，按账号、区域、Mesh/Space 身份只保留最近两代归档的数据库快照。每代沿用现有当前目录的快照上限；更早归档清理两库备份、侧文件和 checkpoint 标记，保留回执、恢复状态和诊断 payload。当前目录、未完成/失败导入和待移动目录不清理；清理失败不否决成功导入，后续归档重试/启动恢复再次尝试 |

本轮自动验证：

- `check_proximity_scoped_import.py`：通过。执行实际预检调用、Zone 赋值及拓扑协调器，覆盖缺字段/旧格式空数组、远端删除节点/Group、有效显式 Zone、普通旧格式空槽保留；SQLite/SDK 对象仍是测试边界。
- `check_device_add_cloud_batch.py`：通过。实际 Manager/Handle 自动完成 POST → 新版本回读 → 规范化版本第二次 POST；覆盖单 Space 与 Site 批次，无手动同步或前台事件触发。
- `check_space_recovery_receipts.py`：通过。实际 Timed 规范化产生新上传意图，pending 新版本重试采用整份替换语义；归档文件夹连续五代导入、最终落库失败、移动失败、清理失败及重试、最近两代内容保留、其他身份和当前目录隔离均覆盖。
- `check_space_membership_lifecycle.py`、`check_hdb_import_recovery.py`：通过，成员关系/旧响应隔离及共享 HDB 导入边界回归。
- `check_configuration_database_safety.sh`：通过，真实临时 SQLite WAL 备份、事务失败回滚、重复重试及隔离；归档保留测试使用可辨认的文件内容，不宣称为完整 App 数据库恢复验收。
- SunSmart Debug / generic iOS：2026-11-02 17:58 构建通过。沿用 `SunSmartLocal.xcworkspace`、`SunSmart-feat-device-scene-261028-cli` DerivedData 和上述本地 SDK `dbcf6f1`，SDK 无改动；未重复其他品牌构建。

本轮未运行真机或真实云端服务。除原始场景外，人工验收最短补充：本机已有非空 Trigger Zone 时，接收删除其节点/Group 的较新旧格式配置，确认能进入空间且重启后不再阻断；上传后回读若发生引用规范化，确认无需再次手动同步便能在云端看到修复版本。
