# 空空间持续云同步失败：初始化标记与上传确认互相阻断

日期：2026-10-12。分析分支：`fix/261012-0x2321`。初次分析 HEAD：`2b66f57f`；复测分析 HEAD：`33b8729e`（`fix: wil sync empty space failure`）。

状态：上轮修复已提交，但用户真实测试仍失败。用户随后授权按复查建议修复；第二轮代码修复、相关回归及 SunSmart generic iOS Debug 编译已完成，原问题空间仍待真机复测。前半部分保留历史证据及实施记录，最新交付见文末“第二轮实施与验证”。

## 本次复测摘要（第二轮修复前）

- 新样本仍为 `accepted + initialized=false + lastUploadCloudTimestamp=null`，业务配置与旧样本完全一致，服务器数据也完全未变。数据库错误由 `4009` 变成 `-2004`，说明错误归类变化，上传确认和初始化尚未完成。
- 已复现一个上轮遗漏的兼容性缺陷：未初始化空间的恢复门禁要求回执包含 `keyFingerprint` 和 `nodeIdentities`，但生产 `migratePendingUpload` 不生成这两个字段。此状态会在请求服务器之前返回 `-2004`，反复重开不能改变它。
- 新 JSON 没有导出上述回执字段、membership 网络身份或恢复权限标记，也没有读回失败的具体判断结果。因此可以确认兼容性缺陷存在，不能据此唯一认定现场就是缺少这两个字段；其他前置条件失败或最终本地复核失败尚不能排除。
- 上轮“历史状态恢复”夹具重新生成了完整回执，只覆盖那一种回执形态，未覆盖实际迁移出来的旧回执。这是验证覆盖不足；离线通过不能说明用户现场状态已经恢复。
- 进入空间后的拓扑清理仍可能在 pending 回执存在时直接失败并记录 `cleanupPreparation / -2004`。退出页面的“保存到服务器失败”是统一失败文案，不是服务器拒绝写入的证据。

## 初次分析结论（修复前版本）

样本中的 Space 已留下 `accepted` 上传回执，但 App 同时将其记为 `joined / initialized=false`。当前代码在上传读回确认时要求空间已经初始化，因此即使 GET 成功、角色为 owner、云端配置与提交配置一致，也会在本地生成 `4009 / noSpacePermission`，无法完成确认。

待确认回执一直保留，又使同步引用清理不满足 `submission == nil` 的条件，出现 `cleanupPreparation / -2004`。后台恢复也会因初始化门禁不满足而不调度该 Space。普通云端刷新会保留待上传本地数据，无法通过完整导入把初始化标记改为 true，形成持续阻断。

这是已用当前生产方法复现的 App 状态衔接缺陷。两份 JSON 足以解释当前为什么持续失败，但没有请求时序日志，不能确定现场第一次失败由哪个刷新入口、网络事件或回调交错触发。没有证据要求修改服务端、SDK 或固件。

## 输入与直接证据

- App：`/Users/maginawin/Desktop/doing/Wil sync failed app export data.json`。
- Server：`/Users/maginawin/Desktop/doing/unsync server data.json`。
- Space：`空间 1`，UUID `4368F189-308D-4E75-838A-ECEED463CE1D`。
- App 快照时间：2026-10-12 17:07:43（UTC+08:00）；最近诊断时间：17:07:15。
- 服务端文件是后续提供的快照，不是失败时的完整网络日志。响应体 `code=200 / message=success`，未提供 HTTP 头。

| 证据位置 | 值 | 含义 |
| --- | --- | --- |
| App `_debugInspection.spaces[0].status.membershipPhase` | `joined` | 没有处于退出/解绑流程 |
| 同上 `configurationInitialized` | `false` | 本地配置授权被初始化门禁阻断 |
| 同上 `submissionPhase / pendingUpload` | `accepted / true` | 上传回执尚未完成读回确认 |
| 同上 `submittedTimestamp / localTimestamp` | 均为 `1791795842` | 提交与当前本地版本同为 17:04:02 |
| 原始 Space 行 `lastUploadCloudTimestamp` | `null` | 从未记录完成的云端确认 |
| 同上 `syncCloudError`，以及原始 Site 行 | 均为 `4009` | 数据库保存了“无 Space 权限”错误 |
| `lastSyncDiagnostic` | `cleanupPreparation / -2004` | 后续准备阶段因状态不满足而失败 |
| `pendingImport / pendingDeletionCleanup` | 均为 `false` | 不是尚未完成的导入或删除清理 |
| `recoveryPhase / state` | `active / 1` | 恢复记录与 Space 均处于正常生命周期 |
| Server `role / owner` | `owner`；owner 用户 ID 与导出用户一致 | 样本不支持“当前用户确实无权限”结论 |

`recordSyncFailure` 只更新当前对象及 DEBUG 诊断，不立即保存可能过期的 Space 对象；云同步操作结束时才持久化最终错误。因此数据库里的 `4009` 与后来记录的 `-2004` 可以并存，不是样本自相矛盾。

## 数据差异是否会导致确认失败

两侧 Space UUID、更新时间、NetKey/AppKey 对象、名称、显示设置等共同字段相同；`nodes / groups / scenes / schedules / switches / emergencyFireControllers` 均为空。密钥仅作内存比较，本报告不记录密钥。

主要表示差异：

- App 有 `appKeyIndex=1`；Server 的 AppKey 自身仍有同一 index 和绑定关系。当前密钥解析允许顶层 `appKeyIndex` 缺省。
- App `spaceData.timedSchemaVersion=1`；Server 未返回该字段。[TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `schema` 将缺省值解释为 1，实际规范化结果相同。
- Server 多出权限、网关、保护开关等响应字段，不是提交配置丢失证据。
- App `_debugInspection.uploadable=false` 是调试导出器固定添加的标识，不表示本次发现了配置损坏；同样，`issues=[]` 只说明比较视图可生成，不证明云同步状态正常。

用实际 JSON 执行生产策略得到：

| 比较/校验 | 结果 |
| --- | --- |
| `configurationData / configurationsMatch` | 两侧合法且等价 |
| 当前配置摘要与 `submissionSHA256` | 匹配：`621d1cd30fbc782e` |
| `TimedSchedulerPayloadPolicy.canonical` | 相等 |
| `scheduleTargetsData` | 相等 |
| `SchedulerModelSnapshot.spaceData` | 相等 |
| `SpaceSyncCleanupPolicy.normalize` | 两侧均 0 个节点、0 项修复 |

因此，本例空配置是合法数据；没有发现会导致当前确认失败的业务配置差异。摘要匹配是调试快照中的截断摘要证据，导出文件没有包含完整原始上传回执，不能将其写成完整请求的逐字节复核。

## 当前代码如何形成持续失败

1. **首次确认前，云端恢复准备可能创建未初始化 membership。**
   [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 的 `preparedRecord` 仅在 `lastUploadCloudTimestamp != nil` 时设置 `initialized=true`；否则新记录默认 false。`restoreConfiguration` 在调用实际导入前就保存该记录。对于本地新建 owner，没有 membership 时 `allowsConfiguration` 原本允许继续；一旦写入该 false 记录，判断变为不允许。

2. **待确认上传使普通导入保留本地数据。**
   [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 `SpaceData.update` 调用 `preservesLocalChanges`。回执存在时返回 `.preserved("localDeletionOrRecoveryPendingUpload")`，而 `restoreConfiguration` 只有收到 `.applied` 才将 membership 初始化。GET 成功或 preserved 均不会完成这个步骤。

3. **读回确认错误地依赖同一个初始化门禁。**
   [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `resumeUpload` 收到成功 GET 后应用远端 metadata，随后要求 `canAutomaticallyUpload`。后者先要求 `SpaceMembershipCoordinator.allowsConfiguration`，因 false 初始化标记失败。`resumeUpload` 随即返回 `authorityError`，在本例没有密码验证需求时统一映射成 `4009`。失败发生在配置匹配和 `finishSubmission` 之前，所以回执一直是 accepted，确认时间一直为空。

4. **同步准备和后台恢复继续被阻断。**
   `canCleanSyncReferences` 要求 `state.submission == nil`，现有回执使其失败。[SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 的兜底诊断记录 `cleanupPreparation / configurationUnavailable(-2004)`。后台 [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 又用 `canAutomaticallyUpload` 筛选候选，排除该空间。显式同步的主流程虽然先调用 `resumeUpload`，仍然返回 4009；问题不能简单概括成“所有同步入口都把清理放在读回之前”。

5. **UI 持续显示失败。**
   [SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 的 `showSyncCloudError` 在需要上传或存在 pending 回执时保留错误显示；空间列表显示该错误，Site 列表也显示下属空间错误。仅清除提示字段不会完成回执或初始化，后续仍会出现。

本例数据符合“本地新建空空间首次确认尚未完成时，普通 GET/导入准备写入未初始化记录”的触发路径。现有 Site 导入、Site 内 Space GET、Space GET 和 Reload 都复用 `restoreConfiguration`，所以不是只改一个页面按钮即可覆盖。现场具体先后顺序仍需当时日志确认。

## 离线复现与验证边界

复用 `scripts/check_space_recovery_receipts.py` 的编译与隔离设施，在临时内存扩展测试入口，没有修改仓库脚本或测试文件，也未修改输入 JSON。执行实际的比较策略、membership 存储/准备、导入前置分支、上传回执及读回方法；数据库、HTTP、SDK 密钥计算沿用现有夹具边界。实际密钥对象相等性另用原始 JSON 在内存中核对。

复现步骤和观测：

1. 构造 owner、未确认版本的 Space，保存同内容 accepted 回执。
2. 调用生产 `preparedRecord`，产生 `joined / initialized=false`。
3. 将服务器配置交给生产 `update` 前置链路，得到 `preserved("localDeletionOrRecoveryPendingUpload")`。
4. GET 固定返回成功 owner 数据，生产 `resumeUpload` 返回 4009；`pendingUpload=true`，`lastUploadCloudTimestamp=nil`。
5. 生产 `canCleanSyncReferences=false`，`configurationSyncError=-2004`，与现场诊断吻合。
6. 仅在隔离夹具中把 membership 改为已初始化作为因果对照，再读同一份服务器配置：确认成功，pending 回执清除，确认时间写入，清理条件恢复。

第 6 步只是诊断对照，不是可直接应用于用户数据库的修复方案。未经身份、回执及配置验证，不应统一设置 initialized=true。

本轮没有执行完整 App 构建、真机操作、线上请求或服务端写入；不将隔离复现等同于现场操作时序已经重放。

## 已确认的修复边界

- 在共享 membership/上传确认链路解决状态衔接：本地合法新建配置与未完成导入的占位数据需要可验证地区分，避免普通刷新把有效 owner 配置降为不可确认。
- 对已有 `accepted + initialized=false` 状态提供恢复：满足同账号/区域/Space/网络身份、有效回执、当前远端权限及严格配置读回匹配后，才能完成确认并持久化初始化状态；不能绕过身份校验、直接丢弃 pending 回执或只清空错误。
- 读回确认与允许发起新写入的前置条件需要分别审视；不得让“确认已有提交”依赖只能在确认/导入后才能满足的条件。成功持久化后，后台恢复与显式重试都应能继续。
- 修正错误归类：本地初始化不完整或保存失败不应一律被报告成服务端权限错误。实际 visitor、退出中、权限撤回或密码验证仍须拦截。
- 针对本次关联风险验证：新建空空间上传与 GET 交错、accepted 未完成时重复 Reload、退出重进/重启恢复、保存失败后的重试；并保证真正未完成的分享导入/旧占位记录、身份不符、权限不足及非空数据不匹配仍被保护。
- 五品牌共享上述逻辑；当前没有发现本次必要的 SDK API、协议、服务端字段或固件变更。若实施，采用现有回归夹具并构建代表 scheme；真实 App 首次上传、刷新、重进后的状态收敛另行验收。

## 分析阶段工作区

仅新增本分析文档。原有两份未跟踪的 0x2321 分析文档保持不变；业务代码、依赖、SDK、输入样本均未修改，无提交。

## 实施内容

1. `prepareSubmission` 在完整配置、调度数据、网络身份及本地写权限验证后，通过 `SpaceMembershipCoordinator.confirmConfiguration` 保存已初始化记录。新空间在首次 POST 前已经有经过校验的完整本地配置，普通 GET 的准备步骤不会再把它变成未初始化占位记录。该步骤不写成功上传时间，也不跳过服务器读回。
2. 新增 `canResumePendingUpload`，仅允许符合生命周期、权限及恢复状态的已有提交进入确认。对于未初始化记录，额外要求 owner、同一网络、完整回执及与本地一致的密钥指纹。`canAutomaticallyUpload` 继续保留原有初始化门禁，不因 pending 回执而开放新写入。
3. 恢复历史异常时，GET 必须确认 owner 及当前用户，并通过原有配置、密钥、日程目标、Timed 和 Scheduler Model 比较；完成前再只读导出当前本地配置，与回执核对，防止空占位数据、部分导入或本地数据缺失被当作有效配置。成功后才保存确认时间、初始化状态并清除回执。
4. membership 与回执分属不同持久化文件，不能假设一次原子写入。确认过程保留 verified 回执直到 membership 写入及最终回执保存完成；保存失败可在重新加载后重试，不将失败解释为服务端权限不足。账号、区域和 membership epoch 变化会使旧响应失效。
5. 后台恢复和 Space 页面进入都允许调度合法 pending 确认；后台跳过这些记录的前置引用清理，由现有同步操作先读回确认，再按是否还有本地改动决定后续上传。真正未完成的分享导入、无回执占位记录、退出中、权限不足、密码验证和身份错误仍被阻断。
6. 本地初始化或持久化失败使用配置不可用/上传未确认错误；实际 visitor、权限撤回仍保留权限错误。

保守恢复边界：历史未初始化记录若缺少完整回执，或本地业务配置已经与回执不同，不自动设为 initialized，也不丢弃回执。新版本正常创建的空间已在首次提交前初始化，后续合法新编辑继续走现有版本确认流程，已由原有回归覆盖。

涉及四个共享生产文件：`SpaceMembershipCoordinator.swift`、`SpaceConfigurationSafety.swift`、`CloudSynchronizationManager.swift`、`SpaceViewController.swift`。复用现有恢复存储和同步队列，未新增数据库字段、依赖、用户文案或协议字段。

## 实施验证

- `check_space_recovery_receipts.py` 已通过，最终权限错误分类调整后复跑通过：新增新空间重复 GET、历史空/非空回执恢复、重新加载、无回执占位、网络/密钥/owner 不符、本地数据缺失、权限撤回、退出/重新加入、账号/区域切换、取消、离线及三种保存失败重试覆盖。运行生产回执、membership、metadata 和导入前置方法；数据库/HTTP/SDK 保持既有隔离边界。已有 Profile、成员移除、日程、首次上传与版本等回归一同运行。
- `check_space_membership_lifecycle.py` 已通过：生产 membership 身份、退出/重新加入、持久化和旧响应保护。
- `check_site_zone_cleanup_batch.py` 已通过：生产后台调度新增验证 pending 未初始化空间被调度且跳过清理，无权限回执及无回执占位空间不进入队列；原有批量、SQLite、取消及账号隔离回归通过。
- 将用户原始 App/Server JSON 再次送入临时隔离夹具，恢复其 `accepted + initialized=false` 状态：最终初始化成功，pending 清除，确认时间为 `1791795842`，清理条件恢复。实际密钥对象先在内存核对相等；SDK 密钥计算仍为夹具边界，其他业务数据使用原样本，未改写输入文件。
- App 构建入口为 `SunSmartLocal.xcworkspace / SunSmart`，Debug、generic iOS、禁用签名。首次沙箱调用在 workspace 识别时失败；同一入口授权执行后构建成功。最终错误分类调整后的增量构建也通过（退出码 0）。
- SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，工作树干净。本次未修改 SDK 或引用新 API，无 SDK 发布依赖。
- DerivedData 固定为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-261012-0x2321`。生产修改属于五品牌共享逻辑，没有资源、target 配置或不同编译条件变更，选择 SunSmart 验证，没有机械重复五品牌构建。
- `git diff --check` 通过；文档内部文件链接均已核对。

仍待人工运行验收：安装修复构建后，保持原账号进入问题 Space，触发一次同步或将 App 切回前台；应消除同步失败提示，重新进入/重启后不复发。再新建一个空 Space，首次同步期间进入/刷新并返回，确认它最终完成同步。未自动安装或运行真机，离线测试与编译不代替真实服务器往返和 UI 验收。

## 上轮实施结束时工作区

生产代码和现有测试/运行脚本的差异均未提交；同一分析文档已更新。此前两份 0x2321 分析文档保持不变。SDK、正式依赖配置、服务器、固件及原始 JSON 均未修改。

## 2026-10-12 实测失败后的复查（33b8729e）

### 新样本与状态对照

本轮输入：

- App：`/Users/maginawin/Desktop/doing/wils sync issues/Space_空间 1_20261012_174622_438+0800.json`。
- Server：`/Users/maginawin/Desktop/doing/wils sync issues/unsync server data.json`。

新 App 是单 Space 调试导出，顶层业务数据为 `spaces[0]`；旧 App 是 Site 导出，业务数据为 `site.spaces[0]`。对这两个对象作完整 JSON 对象比较，结果相同；新旧服务器响应对象也完全相同（文件排版不同）。所以这次不是“修复后又生成了不同配置”的证据。

| 项目 | 旧样本 | 新样本 |
| --- | --- | --- |
| Space UUID | `4368F189-308D-4E75-838A-ECEED463CE1D` | 相同 |
| 本地/提交版本 | `1791795842`，17:04:02（UTC+08:00） | 相同 |
| 待确认配置摘要 | `621d1cd30fbc782e` | 相同 |
| membership / 初始化 | `joined / false` | 相同 |
| 回执 / pending | `accepted / true` | 相同 |
| 最后成功上传时间 | `null` | 相同 |
| 数据库同步错误 | `4009` | `-2004` |
| 最近诊断 | `cleanupPreparation / -2004` | 相同类型，记录于 17:45:44 |
| App 抓取时间 | 17:07:43 | 17:46:22 |

新样本没有 pending import、pending deletion cleanup 或显式 blockedReason。服务器响应体仍为成功，当前角色 owner、owner 用户 ID 与 App 当前用户相同。NetKey/AppKey 对象在原始本地网络配置、业务导出和服务器数据中相符；没有输出密钥材料。空设备/组/日程等业务数据、可兼容的 Timed schema 缺省问题沿用上轮比较结论，因为相应对象没有变化。

这些是快照证据，不等于本次按钮点击期间已收到成功 GET，也不能还原中间是否发生过请求。

### 已证实的恢复兼容性缺陷

当前 [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 存在以下闭环：

1. `resumeUpload` 先调用 `migratePendingUpload`。历史 `uploadReadbackUnconfirmed` 标记没有结构化回执时，迁移从 `last-complete-export.json` 生成 accepted 回执；保存配置、时间戳、日程目标、Timed 和 Scheduler Model 数据，但不保存 `keyFingerprint`、`nodeIdentities`。
2. `canResumePendingUpload` 对初始化为 false 的 owner 要求这两个字段均非 nil，另有网络身份及配置字段等条件。空空间的合法节点身份应为 `[]`；缺失的 `nil` 不能满足该门禁。
3. `resumeUpload` 在 GET 之前检查该门禁，失败时调用 `authorityError`。对于普通 owner，本地初始化不可用被映射为 `configurationUnavailable / -2004`。
4. 回执仍保留为 accepted，初始化仍为 false。页面自动同步与后台候选也使用这一门禁；显式重试虽进入 `resumeUpload`，仍立即失败。普通导入继续保护 pending 数据，无法仅靠重开完成初始化。

复用现有 `check_space_recovery_receipts.py` 的编译设施，在临时测试入口运行当前生产方法，未修改仓库测试或输入文件。提供匹配的 owner 服务器响应，并分别控制回执字段，得到：

| 隔离状态 | `resumeUpload` 结果 | 实际调用请求替身次数 | 最终初始化 / pending |
| --- | --- | --- | --- |
| 完整回执，未初始化 | 成功 | 1 | true / false |
| 仅缺 `keyFingerprint`，未初始化 | `-2004` | 0 | false / true |
| 仅缺 `nodeIdentities`，未初始化 | `-2004` | 0 | false / true |
| 两字段都缺，未初始化 | `-2004` | 0 | false / true |
| 两字段都缺，但原本已初始化 | 成功 | 1 | true / false |
| 实际调用生产旧回执迁移，未初始化 | `-2004` | 0 | false / true |

这个对照证明问题是“旧回执形态与未初始化恢复门禁的组合”，并不是所有旧回执都不可恢复。测试执行真实回执迁移、恢复判断与 membership 持久化；HTTP、App 数据库、SDK 密钥计算及导出仍为现有测试替身。SDK `MeshNetwork.load(allData:false)` 的实际实现会读取 NetKey/AppKey；没有发现仅因 `allData:false` 就不加载密钥的问题。

### 清理诊断与两种弹窗的含义

[CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 的显式同步主流程已经先调用 `resumeUpload`，再生成上传请求和执行清理。不能把当前问题归结成“同步按钮始终先清理后确认”。

不过，[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 在 Mesh 网络数据加载完成后调用 `reconcileLegacyProximityLightingTopology`，这里仍直接调用 `SpaceSyncCleanupCoordinator.prepare`，没有先处理 pending 回执。`canCleanSyncReferences` 要求 `submission == nil`，所以 pending 状态不能继续清理；[SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 会记录 `cleanupPreparation / -2004`。该入口会干扰最后诊断和错误展示，属于同一恢复链需要处理的入口，但不单独证明显式同步的真实失败判断。

- `Space data is unavailable. Reopen this Space to retry.` 对应 App 本地错误 `configurationUnavailable(-2004)`。它既可能来自读回前的门禁，也可能来自读回匹配后的本地配置复核，或其他准备阶段；当前文案没有提供具体判断结果。
- `Failed to save the data to the server...` 来自退出同步失败时的 `showSyncSpaceFailedAlert`，统一使用 `space_sync_failed_message`。这个回调不根据底层错误改变提示，因此不表示一定发起过 POST，也不说明用户分享设置有问题。
- 最后诊断与数据库最终错误的记录时点不同；`cleanupPreparation` 可能由进入页面时的清理覆盖。不能把它当作点击同步操作的完整追踪。

### 现场尚缺的决定性证据

`debugSnapshotStatus` 只导出回执阶段、版本及配置摘要，没有导出：

- 回执中 `keyFingerprint / nodeIdentities / scheduleTargets / timedConfiguration / schedulerModelStates` 是否存在。
- membership 网络 ID 是否与当前 Space 一致，以及恢复状态的 `authority / requiresRemoteImport / unbindRequested`。
- 本次恢复是否通过前置条件、是否发起 GET、是否通过远端比较，及本地只读导出复核具体失败项。

因此“现场缺少旧回执字段”仍是假设，尽管当前生产代码已经存在可复现的对应缺陷。当前 JSON 也不足以排除回执指纹不符、membership 网络身份不符或最后本地复核失败。`submissionSHA256` 只涵盖规范化业务配置，不证明这些其他字段齐全或匹配。

上轮 `testFirstUploadMembershipRecovery` 的 historical 辅助方法先用当前 `prepareSubmission` 生成完整新回执，再把 initialized 改成 false；使用实际业务 JSON 的临时复现也采用了重新生成回执的方式。它们验证了“完整回执”的恢复，没有还原现场未导出的原始回执。这一边界应明确修正，不能继续用上轮绿色结果推定现场已修复。

### 建议的下一轮 App 修复与验收边界

1. 先补最小可定位诊断：在恢复前置条件和最终本地复核处记录具体失败阶段与布尔校验结果；DEBUG 导出增加上述非敏感字段的存在性、身份匹配结果和恢复状态。按同步尝试关联诊断，避免进入页面的清理覆盖确认失败原因；不输出密钥或完整指纹。
2. 修正旧回执迁移的契约。已有回执缺字段和仅有旧标记两种入口都要覆盖。仅从可验证的持久快照补全：核对账号/区域/Space/网络身份、版本和原回执配置，并与当前本地配置及远端权限、密钥、配置一致性相结合后恢复；不能为通过门禁随意填空数组或直接设置 initialized=true。快照不足或身份不符应保留保护并说明原因。现场具体缺失哪项应以新增证据为准。
3. 统一相关入口的顺序：pending 时先确认或迁移，完成后再清理。空间进入的拓扑清理遇到 pending 应延期，并在确认成功后完成必要清理，不能只跳过后永久不再执行。后台、页面自动同步、显式同步应使用同一恢复条件。
4. 在现有夹具补“生产迁移生成的回执 + initialized=false”、各可选字段缺失、网络/权限不符、快照缺失、保存失败重试及进入空间与同步交错；保留当前完整回执、新建空/非空空间的正常路径。
5. 修改后按项目规则做相关回归及代表 scheme 编译，再由用户以原问题空间执行同步、退出重进、重启复测；成功标准为回执清除、initialized=true、确认时间落盘且不再弹错。服务端、SDK、固件无已证实的必要改动。

本轮未实施上述建议，未进行 App 构建、真机操作或线上写入。开始复查时工作树干净，上轮修复已位于 `33b8729e`；本轮仅更新本分析文档。

## 第二轮实施与验证

用户指令：按建议修复。基线仍为 `fix/261012-0x2321 / 33b8729e`；开始实施时仅本文档存在上轮分析差异。本次修改四个共享生产文件、两份现有测试及其运行脚本，未修改 SDK、依赖、服务器、固件或用户输入文件；未提交。

收尾检查另发现 `docs/261012_1641_2321_slg_scan_device_type_analysis.md` 和 `docs/261012_1650_2321_device_parameter_visibility_analysis.md` 被删除；本任务没有执行这两项删除，也没有恢复或处理这些外部工作区变化。

### 已完成修改

1. **恢复候选与确认条件分开。** `canResumePendingUpload` 允许身份、角色、生命周期等基础条件成立的旧标记和缺字段回执进入恢复尝试；它不授予新写入权限，也不表示可以直接确认。新写入仍要求 `canAutomaticallyUpload`。
2. **补全可验证的旧回执。** `migratePendingUpload` 同时处理旧 `uploadReadbackUnconfirmed` 标记和未初始化空间的结构化缺字段回执。补全来源只能是当前账号/区域/Space/网络恢复目录的 `last-complete-export.json`。已有回执必须与快照版本、配置及全部非空字段一致，快照密钥必须与当前本地网络一致，日程、Timed、Scheduler Model 及节点身份必须可解析。空节点集合由实际快照解析得到，不把缺失值强制写成空值。
3. **补全后重新读回。** 保留既有回执 ID、版本和配置；新重建的字段从 accepted 阶段重新 GET 验证，即便旧回执曾是 verified 也不能跳过。迁移不开放云端删节点权限。确认时继续要求远端 owner 为当前用户、密钥与配置一致，并增加本地及远端节点实例身份比较（包括 Device Key 身份和元素地址），避免只比较业务配置而漏掉设备身份差异。节点顺序不同不造成误拒绝。
4. **清理在确认后执行。** Space 页面和共享清理入口遇到 pending 回执先延期，不改写为新的清理失败，也不创建单空间入口的 Site 清理请求。云同步操作在读回完成后走既有 `getNetworkApi` 清理/导出边界，然后才决定是否可直接结束；清理生成新本地改动时继续正常上传。Site 的快速完成判断读取最新持久状态，避免漏掉清理期间产生的 Site 改动。
5. **保存可定位的诊断。** DEBUG 状态导出增加恢复权限、远端导入/解绑标记、membership 网络匹配、旧标记、快照存在性、五项回执字段存在性及本地密钥匹配结果。`lastReadbackDiagnostic` 独立记录 attemptId、阶段、具体原因和错误码，不被 `lastSyncDiagnostic` 中的清理诊断覆盖；旧的悬挂尝试不能覆盖较新尝试的记录。不输出密钥材料或完整指纹。

保存失败、离线、取消、账号/区域或 membership 变化继续保留可重试状态。快照缺失、身份不一致或字段冲突仍保持阻断；本次没有用“统一初始化”或“删除待确认回执”消除提示。

### 自动验证

| 验证 | 结果与边界 |
| --- | --- |
| `check_space_recovery_receipts.py` | 通过。直接写入历史回执形态和旧标记，覆盖空/非空空间、五类字段分别缺失、全部缺失、旧 verified 强制重读、快照缺失/版本/配置/密钥错误、已有回执字段冲突、网络/权限/远端导入拦截、远端 owner/Device Key 不符、本地节点缺失/Device Key 不符，以及保存失败和离线后的重新加载重试。验证新增 DEBUG 字段及诊断不被清理覆盖。已有完整回执、Profile、导入、删除和权限等回归一同通过。 |
| `check_site_zone_cleanup_batch.py` | 通过。运行实际同步准备与快速完成分支、批量清理协调和 SQLite Zone 持久化。新增验证进入空间时延期清理、读回先于清理、无改动不发多余 POST、有清理改动继续上传、读回/清理失败、取消及清理期间新 pending 的保护。该套中的读回与 Mesh/Space 修复为替身；真实读回逻辑由上一套覆盖。 |
| `check_space_membership_lifecycle.py` | 通过。membership 身份、持久化、旧响应、退出/重新加入及账号隔离。 |
| `check_space_sync_cleanup.py --snapshot <新 server data>` | 通过。使用现场服务器快照，0 个设备、0 项 proximity 修复；既有清理、兼容和幂等性回归通过。只读输入文件。 |
| App 构建 | `SunSmartLocal.xcworkspace / SunSmart`，Debug、`-sdk iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`，退出码 0。输出包含未修改位置的 capture 警告，无编译错误。 |
| 工作区检查 | `git diff --check` 和本文档内部链接检查通过。 |

构建前重新确认 SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision 为 `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，SDK 工作树干净。DerivedData 复用本工作树固定目录。没有新增 SDK API、资源或品牌编译条件，选 SunSmart 代表共享逻辑完成一次编译。

### 仍需现场验收

安装本轮构建，保持原账号进入原问题 Space，点击同步，然后退出重进并重启 App。期望 `configurationInitialized=true`、`pendingUpload=false`、成功确认时间落盘且不再弹错；另验证新建空空间首次同步。

现场原始回执字段和持久快照未包含在之前两份 JSON 中，不能承诺该设备一定符合自动迁移条件。若仍失败，重新导出该 Space 的 DEBUG 数据，优先读取 `status.lastReadbackDiagnostic.stage/reason`、`submissionFields`、`hasCompleteExportSnapshot` 和身份匹配布尔结果；这些字段可区分缺快照、身份不符、远端差异和本地复核失败，不再仅依赖笼统的 `cleanupPreparation`。本轮未安装或操作真机，未执行线上请求；隔离测试和编译不替代现场验收。
