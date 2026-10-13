# 3F-Office 持续云同步失败：历史基线与版本门禁不一致

日期：2026-10-12，时间均为 UTC+08:00。分支：`fix/261012-0x2321`，HEAD：`452cd49c09fe534770a263f56ccac3b7933006ad`。开始分析时工作树干净。

状态：用户已授权“按推荐方案修复”，App 端实现已落地，验证与现场待办见文末。未修改 SDK、服务器或输入样本，未提交 Git，未运行真机或发起线上请求。

## 结论与证据边界

修复前，本例失败发生在**新上传之前的云端基线核对**。服务器返回版本 `1791519248`，早于本机最后确认版本 `1791596221`；当前 App 的 Profile/成员核对把这种返回判为旧版本并停止同步。没有待确认上传回执，所以本例不是上一轮空空间的 `accepted + initialized=false` 问题。

关键兼容缺口是：**云端逻辑配置摘要仍与持久化历史基线摘要一致，但版本门禁先拒绝，无法进入“云端基线未变化、本地编辑继续上传”的路径。** 共享方法返回失败后，上层保留本机数据并显示 `-2002 / configurationUploadUnconfirmed`；重新点击 SYNC 仍执行同一 GET 和同一判断。

两份文件足以确认当前版本关系、成员差异与失败阶段；不能证明最初为什么出现版本倒挂。历史客户端的确认口径、服务端时间字段未推进、旧数据覆盖或读取旧副本均需历史请求/存储证据区分，不能直接认定为服务器回滚或上传丢包。

用户已回复“不确定”是否主动删除过差异中的六台设备，因此本文只称“本地缺失、服务器存在”，不认定为用户删除，也不认定哪一份设备清单必然正确。

## 样本对比

输入：

- [App 诊断导出](</Users/maginawin/Desktop/doing/wils sync issues/phase 3/Space_3F-Office_20261012_194534_885+0800.json>)。
- [服务器 get space props](</Users/maginawin/Desktop/doing/wils sync issues/phase 3/server data.json>)。

Space UUID：`103F386B-E05D-497B-BB0D-9131B1E9CB6A`。App 快照时间：10 月 12 日 19:45:34。导出标记 `_debugInspection.uploadable=false`，属于诊断文件，不应直接作为上传请求体。

| 项目 | App 本地 | 服务器 |
| --- | --- | --- |
| 当前配置时间 | `1791598958`，10 月 10 日 10:22:38 | `1791519248`，10 月 9 日 12:14:08 |
| 本机最后确认时间 | `1791596221`，10 月 10 日 09:37:01 | 当前返回比它早 21 小时 22 分 53 秒 |
| 设备数 / deviceCount | 266 / 266 | 272 / 272 |
| Group | 18，其中虚拟组 2 | 完全相同 |
| 场景 / 日程 / Space Trigger Zone | 均为空 | 均为空 |
| 网络密钥对象 | 与服务器逐字段相同 | 与本地相同 |
| 权限 | 数据库 Owner；无密码验证要求 | owner，owner.userId 与导出账号相同 |
| Timed schema | 显式 1 | 未提供，生产解析器按合法旧格式处理 |

诊断状态：

- `configurationInitialized=true`、`membershipPhase=joined`、`membershipNetworkMatches=true`。
- `recoveryPhase=active`、`recoveryAuthority=writable`、`requiresRemoteImport=false`、`unbindRequested=false`。
- `pendingUpload=false`、`legacyUploadMarker=false`、`pendingImport=false`、`pendingDeletionCleanup=false`；无 `blockedReason`。
- 数据库 `syncCloudError=-2002`。
- 19:45:27：`lastSyncDiagnostic.stage=cloudMembership`。
- 19:45:32：`lastReadbackDiagnostic.stage=baselineReconciliation`，`reason=profilesOrMembership`，`error=-2002`。

`pendingDeletionCleanup=false` 只表示没有未完成清理，不证明从未删除，也不能证明不存在已清理、待上传的删除记录。导出不包含完整删除日志和恢复基线。

生产比较器计算结果：

| 比较对象 | SHA-256 前 8 字节 |
| --- | --- |
| 导出中的持久基线摘要 | `2b553a16f2839613` |
| 服务器逻辑配置 | `2b553a16f2839613` |
| 当前本地逻辑配置 | `2c657685ff72a73f` |

摘要匹配是强定位证据，不能代替实施时对手机内完整持久基线的比较，也不表示所有 JSON 字段都一致。当前逻辑摘要覆盖 Group/Profile、成员及相关拓扑，不包含所有节点观测缓存和开关字段。

### 六台差异设备与开关关联

本地 266 台全部能在服务器找到相同 UUID、单播地址和 Device Key；没有本地独有设备。服务器额外六台均为 PID `2503`、PA 组 `CC80`、`groupState=1`：

| 名称 | 地址 |
| --- | --- |
| L266 | 138D |
| L267 | 1390 |
| L268-Nearby | 1393 |
| L269 | 1396 |
| L270 | 1399 |
| L272 | 139F |

仅在内存比较副本排除这六个实例后，本地与服务器的生产逻辑配置完全等价，Scheduler Model 快照也等价。两边 Group/Profile 对象原样一致；Profile、日程目标与引用清理预检均有效且没有待规范化的修复项。空 Trigger Zone、旧 Timed schema 和设备状态缓存差异不是此次版本门禁失败的依据。

另有一项直接关联差异：服务器“开关 1”的代理为 `1393`，本机已无该节点，开关也未导出代理和 EnOcean 身份字段。既有导出按本地属性存在性输出这些字段，既有引用清理会剔除失效代理。此现象与节点缺失有关联，但不能证明六台缺失的操作来源。恢复前须核对代理关系，不能只把 deviceCount 改到一致；本文不记录任何密钥材料。

## 失败链路与为什么一直重试无效

1. [SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 根据 `lastUpdate > lastUploadCloudTimestamp` 判定仍需上传，本例为 `1791598958 > 1791596221`。
2. [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 在构造新上传 API 前逐个调用 `SpaceConfigurationSafety.resumeUpload`。它也服务于 Site 携带 Spaces 的同步；解绑前上传复用同一确认方法。
3. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 中，无 submission 但存在本地修改及节点/Model 基线时，先 GET 当前 Space，再执行 `reconcileCloudProfiles` 与 `reconcileCloudMembership`。返回 false 即结束本轮，新 POST 尚未发起。
4. Profile 核对具备完整前置基线时，先要求 `remoteTimestamp >= lastUploadCloudTimestamp`，失败记录 `profileCloudVersionBehind`。若旧记录缺少 Timed 等前置基线，该方法会提前交还后续流程；成员核对仍要求 `remoteTimestamp >= timestamp`，本例 timestamp 就是最后确认版本。此处失败仅返回 false，没有专属原因。
5. 成员核对的时间要求位于成员差集和配置内容比较之前。因此本例尚未走到“服务器成员有没有变”或“与历史基线是否相同”的判断，六台差异不是该次失败的直接判据。
6. 普通刷新 [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 同样调用这两个核对方法；失败时返回 preserved，不覆盖本地，也不会推进确认版本。同步入口记录 `baselineReconciliation / profilesOrMembership`；导入入口可能记录 `cloudMembership`。这些行为与本例导出一致。
7. 上层持久化 `-2002`，通过 [NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift) 映射到用户看到的提示。当前没有 blockedReason，[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 展示普通失败和 SYNC，而非已有的配置恢复选择；重试不改变两个版本或基线，所以继续失败。

本例导出没有持久基线字段存在性详情，故不能唯一确定 Profile 方法是否因旧字段缺失而跳过；两条路径都被同一个版本关系阻断。`cloudMembership` 诊断与旧基线分支相容，但不是缺少 Timed 基线的直接证明。

### 上游版本关系的限制

`lastUploadCloudTimestamp` 是本机“已确认的本地版本”记录，不是此次 GET 现场测出的服务端版本。当前代码既会在完整导入时采用远端版本，也会在提交确认后保存 submission.timestamp；仅凭该数字不能反推出某一次 HTTP 请求、服务端保存内容或手机时钟错误。

没有当时的 POST、响应、紧随其后的 GET、服务端持久记录与历史 App 构建信息，不能唯一解释 10 月 10 日确认时间是怎样产生的。当前失败机制已足够清楚，无需等待这些资料才能规划 App 的兼容恢复。

## 离线因果复现

第一组探针直接编译执行生产 `SpaceConfigurationIntegrityPolicy`、`SpaceCloudNodeRemovalPolicy`、`SchedulerModelSnapshot`、`SpaceSyncCleanupPolicy`，读取原始两份文件，得到上述摘要、实例身份、差集及规范化结果。

第二组复用 `scripts/check_space_recovery_receipts.py` 的生产方法提取设施，仅在临时 harness 注入探针，执行真实 `resumeUpload`、基线核对、membership 与恢复状态持久化。设备和 Group 使用样本；业务历史基线按与导出摘要匹配的服务器配置构造，节点/Model 基线也由夹具构造，分别测试有/无 Timed 基线。**这些完整历史字段不是从手机导出读出的。** HTTP、App 数据库、SDK 密钥加载沿用测试替身，原文件的网络密钥对象一致性已另行核对。

| 对照 | 生产方法结果 |
| --- | --- |
| 原时间关系，缺 Timed 基线的旧记录形态 | 一次 GET 后 `-2002`，`baselineReconciliation / profilesOrMembership` |
| 原时间关系，完整基线 | 同样失败，另有 `profileCloudVersionBehind` |
| 只把内存响应时间改为 `1791596221`，旧记录形态 | 前置核对成功，仍需后续上传 |
| 同上，完整基线 | 前置核对成功，仍需后续上传 |

四个对照均保留本地 266 台、无 pending 回执、确认时间不变。Timed 生产 canonical 对两份原始输入均有效且完全相同。改变时间只用于因果对照，不是建议手动改服务器时间或用户数据库。

以上是实施前定位探针：当时未执行整个回归套件。实施后的验证结果另见文末；真实 POST、服务器持久化、完整 Mesh 导入、真机开关功能和 UI 仍需现场验收。

## 已获授权的修复方案

### 1. 为“无待确认提交、基线内容未变、版本偏旧”增加受约束的恢复路径

优先复用 `SpaceConfigurationSafety` 的持久基线、身份校验和现有比较方法，在 Profile 与成员核对共用的边界统一分类。不要分别删除两个时间判断，也不要以“本地时间比较新”为由允许覆盖。

允许继续准备本地上传的条件：

- 当前账号/区域/Space/网络身份一致，有当前写权限，membership 已初始化；没有待导入、退出、权限恢复要求或未完成清理。
- 没有 prepared/accepted/verified submission；本分支只解决上传前基线兼容，不替代已有提交确认。
- GET 载荷完整有效，网络密钥相同；完整逻辑基线与云端规范化结果等价，节点实例（含 Device Key 身份与元素地址）、Scheduler Model 与 Timed 比较均满足相应契约。生产决策不得只比较调试短摘要、设备数量或版本号。
- 对此次基线等价放行，不把旧 GET 当作新的云端删设备证据，不回滚本地配置、不更改 lastUploadCloudTimestamp、不立即宣告同步成功。
- 继续执行已有清理、完整导出、创建回执、POST 和新提交读回。只有新提交真正满足确认规则并完成持久化后才清除错误；提交期间的新本地编辑仍待上传。

若云端真的偏离基线、出现新实例/密钥变化、缺必要证据或权限改变，继续保护本地。短暂旧读可重试；持续不可判定或真实冲突应提供可执行的恢复选择，不能无限复用含混错误，也不能把一次旧响应自动认定为用户应覆盖的冲突。

### 2. 同时处理历史基线缺字段与恢复入口

旧状态可能已有通用迁移标记却没有 Timed 基线。现有 `backfillTimedUpgradeBaseline` 又要求云端时间恰好等于最后确认时间；只调整版本门禁而不检查迁移链，可能留下下一处阻塞。

- 优先从可信、版本和作用域匹配的保存快照/既有 Model 基线恢复缺失证据；节点身份可复用已有 legacyInstances，继续要求完整覆盖，不能由当前 GET 自证历史身份。
- 对本例两端日程和节点日程均为空的合法旧格式，若其他必要基线已验证，可采用严格的“本地与云端均为合法空 Timed 配置”兼容规则；这是补齐当前双方没有差异的字段，不得把任意未知/非空旧字段默认清空。已有非空、非法或相冲突基线不覆盖。
- 新建基线与修复持久化都要覆盖失败后重载重试，不提前移动确认时间，不让补基线产生误成功。
- 普通 GET 导入、Space/Site 同步、后台恢复及解绑前上传采用一致结果；旧快照只用于确认基线，不能因此进入完整导入并把六台设备重新带回本机。已有显式“使用本机数据”恢复也需复用同一版本处理，否则重设基线后仍可能再次卡在该门禁。
- 对没有足够基线、无法证明缺失字段或成员变更来源的记录，复用已有检查点和配置恢复选择。需要人选择本机或云端时展示六台差异及开关代理影响，选定后再次校验远端、账号、权限和本地版本，不默默选择 266 或 272。

本次尚不能承诺该手机一定满足自动恢复的全部条件，因为诊断未包含完整恢复状态和删除日志。应让修复版先读取手机已有证据；证据不足时有明确恢复路径，而不是放宽身份和数据校验。

### 3. 补足直接对应本问题的诊断

在既有 DEBUG 诊断中增加 `remoteTimestamp`、`lastConfirmedTimestamp`、基线字段存在性，以及配置/身份/Model/Timed 是否等价的布尔结果；把 `profilesOrMembership` 分为具体失败原因，如版本偏旧、缺基线、实例变化、Model 不同、存储失败。输出阶段与原因，不输出完整指纹、密钥或整个业务载荷。

共享生产修改预计集中在 `SpaceConfigurationSafety.swift`；按实际接线需要调整 `ImportData.swift`，复用现有页面恢复流程和比较工具。不新增通用同步框架，不改 SDK、固件、正式依赖或后端配置。五品牌共享此逻辑；没有品牌分支/资源差异时以 SunSmart 代表构建。若需要新增用户可见文案，补齐 English 与简体中文。

### 4. 验证与现场恢复边界

优先扩展现有回执/导入测试，使用脱敏夹具验证本次行为，不把含密钥的用户样本加入仓库：

1. 复现本例时间关系、完整及旧版缺 Timed 基线；基线等价时能从预检继续到 POST，再完成有效读回，重启后状态稳定。
2. 旧时间但内容/身份/Model/非空 Timed 有变化、缺 nodes、权限撤回、无可靠基线时不得自动覆盖；已有 pending 回执仍遵循原确认规则。
3. 本地正常增删成员、合法空空间/空配置、节点顺序变化保持兼容；云端真实移除仍须满足其独立版本与身份规则。
4. 存储失败、取消、账号/区域/membership 变化、异步期间本地新编辑及重新加载均保留可重试状态，不能清掉较新的变更。
5. 覆盖 Space、Site 携带 Spaces、普通导入、解绑上传和显式本机恢复接线；现有删除、Profile、Timed 与清理回归不能退化。完成后构建一次 SunSmart generic iOS Debug。

现场由用户确认六台与开关代理的正确状态，再在原 Space 同步、退出重进并重启。若选择保留本机 266 台，预期新的服务器 GET 也有同样的有效成员和开关引用，确认时间与新提交一致、无 pending 且不再弹错；若应恢复六台，则走审核后的云端恢复，不以本次兼容逻辑代替数据选择。设备实际通信及开关功能另行验收。

服务端配合仅为核查契约与证据：对应团队比较同一次 POST body、响应、持久记录与 GET，确认 `updateTimestamp` 和业务配置来自同一版本，写后读取不会长期返回旧副本。若新 POST 后始终读回旧成员/旧版本，App 应继续报告未确认，不能仅凭 HTTP 200 消除提示。服务端原因未证实前，不将后端修改列为已确认必需项；本次不执行任何服务端改动。

当前不建议清空本机、重置 lastUploadCloudTimestamp、删除保护记录或直接 Reload 来试运气。先保留两份证据和既有恢复检查点，再按上述分支恢复。


## App 实施结果

实现沿用现有回执、检查点、配置恢复和导入机制，没有调整服务器时间契约或 SDK：

- `SpaceConfigurationSafety.reconcileOlderCloudBaseline` 同时接入上传前核对和普通 GET 导入。完整基线、网络密钥、Device Key/元素身份、Scheduler Model、Timed、权限和生命周期均验证后，旧 GET 只允许本地继续准备新上传。已有待确认提交仍走严格读回路径。
- 自动放行额外要求：历史成员在本机缺失时，必须存在该实例的已完成删除记录，且完成版本落在最后确认版本之后、本地版本之内。没有依据不把六台设备当作已授权删除。可信已确认快照可补身份/Model，合法双端空 Timed 可补旧记录；legacyInstances 缺元素身份时不会强行放行。
- 对同一配置和本地版本重复出现的可审核冲突，保存语义摘要并转为 `cloudBaselineNeedsReview`；第一次仍可重试。暂态设备观测值变化不会无限重置重复判断。存储错误、账号切换、取消、非法载荷和网络密钥冲突继续保留保护，不据此授权替换。
- 页面复用配置恢复入口，展示本地/云端数量、独有实例名称与地址、开关代理从云端到本机的差异。英文与简体中文文案均已补齐；设备列表最多展示 12 项并标注剩余数量，本例六台全部显示。预览不可用时不提供未核对的本机替换。
- “使用本机数据”再次核对预览对应的本地/远端版本与配置、网络身份、权限和 membership 世代，保留检查点，以新本地版本记录用户授权，再走现有 POST/回读。授权只对应该本地版本，后续编辑不会自动继承未知删除的授权。
- “重新加载云端”把核对后的选择原子保存为 `reviewed-cloud-import.json`，复用待导入恢复。中断后继续同一已审核载荷；导入成功前保留删除记录。成功后清理被放弃的本地记录，导入自身产生的引用清理仍须上传。无效拓扑保留诊断并停止重放，损坏的待导入文件拒绝恢复，不从下一次 GET 猜测用户选择。
- DEBUG 导出增加三方时间、基线字段存在性、具体失败原因与各项等价结果，不输出密钥或完整载荷。诊断成功只代表基线核对完成，不提前推进确认时间或清空提交回执。

新增恢复状态字段为可选 Codable 字段，旧回执可继续读取；用户选择云端后的专用文件使用现有账号/区域/Space/网络作用域目录及原子写入。五品牌共用上述代码和 Localizable.strings，无新增品牌条件或工程依赖；代表 scheme 为 SunSmart。

### 原始样本实施后探针

再次通过临时 harness 读取原始两份文件，执行生产恢复与上传回执方法。样本设备、Group、Timed、开关内容保留；测试只在既有 SDK 密钥加载替身边界替换 NetKey/AppKey，并为独立用例隔离 Space 作用域。原始两边网络密钥对象另行验证完全相同。完整历史基线和删除记录仍为**构造的测试前提**，并非从手机恢复出来。

| 条件 | 结果 |
| --- | --- |
| 完整等价基线 + 六条准确删除记录 | 预检通过，仍保留 266 台与旧确认版本；模拟新 POST/匹配 GET 后确认到 `1791598958` |
| 同上，旧记录缺 Timed 基线且无完整快照 | 合法双端空 Timed 补齐后完成同一上传/回读流程 |
| 等价基线，但没有删除记录 | 自动上传被拒绝；重复核对进入恢复预览，包含 L266～L272 六台差异及 Switch1 代理 `1393` |

因此修复版不承诺该手机无需选择就同步成功：实际自动恢复与否取决于手机内保留的完整基线和删除记录。最终以新 POST 的完整回读确认判定同步成功。

### 验证记录

2026-10-12 完成以下验证：

| 检查 | 结果与边界 |
| --- | --- |
| `python3 scripts/check_space_recovery_receipts.py` | 通过。执行生产上传/回读、旧回执、Profile、成员、导入前置核对及新恢复方法；新增用例覆盖自动恢复、显式本机替换、云端选择中断续导、存储失败、无效拓扑、损坏回执、账号/权限/membership/本地版本变化。真实 Mesh 导入和 HTTP 为隔离边界 |
| `python3 scripts/check_space_protection_snapshot.py` | 通过。新恢复文件能阻断编辑并使缓存失效；5000 次检查只做一次工作线程读取（2 次文件读取、3 次存在性探测），主线程文件读取为 0 |
| `python3 scripts/check_space_membership_lifecycle.py` | 通过。账号、权限、离开/重新加入及配置初始化保护回归；之后未改 membership 实现，新增异步路径的世代变化另在回执套件覆盖 |
| `python3 scripts/check_site_zone_cleanup_batch.py <本地 SDK 目录>` | 通过。Site 批量清理、SQLite、取消及生产协调器接线回归；其后未改协调器/批清理实现 |
| `python3 scripts/check_timed_slot_persistence.py` | 通过。Timed SQLite 迁移、槽位持久化、清理、回滚与晚回执保护；其后未改 Timed 实现 |
| 原始 266/272 台样本临时探针 | 三个上述情形通过；未复制含密钥样本进仓库 |
| `plutil -lint` 两份 Localizable.strings；`git diff --check` | 通过 |
| SunSmart generic iOS Debug unsigned | 最终代码 `BUILD SUCCEEDED`；无 Simulator、安装或真机运行 |

构建入口：`SunSmartLocal.xcworkspace`，scheme `SunSmart`，`-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。稳定 DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-261012-0x2321`。本地 SDK 映射指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，本任务未改 SDK；正式依赖未变。回执测试有测试替身穷举 switch 的既有不可达 default warning；构建有未依赖 AppIntents 的元数据提取提示，均无错误。

本轮没有后端改动或发布依赖。以上自动化与编译结果不代替真实云端及手机验收。

### 最短人工验收

1. 使用修复版打开原 3F-Office，点击 SYNC。证据完整时应自动完成；证据不足时，重复同一核对后进入恢复提示，先核对六台设备和开关代理。
2. 确认应保留本机 266 台才选择“使用本机数据”；确认应恢复云端 272 台才选择“重新加载云端”。不确定时取消，不清空本机或删除回执。
3. 完成后退出重进并重启 App，检查设备数量、PA 组、Switch1 代理/功能及同步状态。同步成功必须有新的服务器配置读回；若仍失败，导出 DEBUG JSON，查看 `lastBaselineDiagnostic` 与 `lastReadbackDiagnostic`，区分基线不明和新提交未确认。

尚未验收：真实 HTTP 写后读、真实 SDK/Mesh 完整导入、真机 UI/开关行为、其余品牌运行。服务端若继续返回旧数据，保留未确认提示属于保护行为，需对应团队检查写后读版本一致性。

### 2026-10-12 Review 恢复阻塞修复

修复三处恢复路径顺序问题，未改 SDK、后端、依赖或品牌配置：

1. `requiresRemoteImport` 尚未清除时，旧云端基线检查返回不适用，继续走原有权威导入。降为 visitor 后导入中断、重启再恢复 owner/editor 的路径可继续；只有完整导入收尾成功才重新开放上传，Timed 降级限制保持有效。
2. 当前本地版本的 `localReplacementVersion` 显式授权同时覆盖相同 UUID 下的实例身份变化和已审核移除。自动路径仍拒绝 Device Key/地址变化，本地版本再次变化后旧授权不再适用，成功上传读回后清除授权。
3. 审核云端导入在落盘前，先对规范化结果执行 Group、Schedule、Node 解码和调度模型恢复检查。无效 Group（含虚拟 Group）、Node 或调度模型不会产生待导入意图，原本地版本及删除回执保留，可重新审核修正后的云端或选择本机恢复。

本轮验证结果：`check_space_recovery_receipts.py`、`check_cloud_node_import.py`、`check_space_protection_snapshot.py` 及 `git diff --check` 均通过；`SunSmartLocal.xcworkspace` / SunSmart / generic iOS Debug unsigned 构建 `BUILD SUCCEEDED`，复用上文 DerivedData 和同一 SDK revision。受限环境中首次 Xcode workspace 查询失败，使用常规构建权限后完成编译，未改工程映射。

回归执行实际恢复状态机、审核落盘、导入准备、上传回执和收尾逻辑，并复用 SDK 的 Group 解码器与 Node 可选标识字段解码代码。HTTP、Mesh/SQLite 导入提交、其余 Node 字段和调度恢复对象仍是隔离边界，不能据此认定真实设备/云端验收通过。

补充人工验收：分别验证「visitor 中断导入后恢复 editor/owner」、「审核选择同 UUID 新实例的本机数据后同步」、「无效云端 Group 被拒绝后重新获取修正数据」。前两项完成后退出重进，检查配置和同步状态；第三项应能再次选择云端或本机恢复，不持续重放无效载荷。
