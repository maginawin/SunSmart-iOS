# 同版本 Site / Space 云端覆盖修复

日期：2026-11-04，UTC+08:00。分支 `feat/device-scene-261028`，基准 HEAD `3fe26b7f`，修复尚未提交。

## 当前结论与已确认规则

用户已确认：**Site 或 Space 版本时间戳相同，完整采用云端配置覆盖本地，不保护本地业务修改，不进入冲突选择。** Web 可以在不增加时间戳的情况下修改数据。补充规则：旧云端快照缺少可默认的业务属性时，先补 App 默认值，再覆盖本地。此规则取代初次分析中“先比较再人工复核”的建议。

现场死循环的直接原因是 prepared 回执进入同版本设备删除协调后提前返回 `unacceptedSubmission`，又没有安排可完成的恢复出口。该路径由 **`153bc667e71dc8820162aac59b23f169df8f7826`（2026-10-28）**引入。它不等于最初上传异常或 Web 修改的发生时间。

已完成 App 修复并通过现场样本离线复现和 SunSmart generic iOS Debug 编译。真实云端往返、真机 UI 和 Mesh 验收未运行。无需服务端或 SDK 改动；共享逻辑影响全部品牌，本次未改资源、target 配置或品牌条件分支。

## 现场证据

输入文件：

- `/Users/maginawin/Downloads/Space_空间 2_20261104_105908_622+0800.json`
- `/Users/maginawin/Desktop/xyy space data.txt`

只记录状态、摘要和必要的设备地址，不复制密码或 Mesh Key。

| 项目 | App 导出 | 服务端 GET / 含义 |
| --- | --- | --- |
| Space 身份 | 与 GET 相同 | 没有比较错 Space |
| 最新时间戳 | `1793760893`，10:54:53 | 同为 `1793760893`，不代表内容相同 |
| 最近确认时间 | `1793759689`，10:34:49 | 后续修改尚未确认 |
| 回执 | `pendingUpload=true`，`submissionPhase=prepared` | 不能当作已收到并持久化成功响应 |
| 失败诊断 | 10:59:04：`membershipReconciliation / unacceptedSubmission` | `lastSyncDiagnostic.stage=sameVersionRemoval.unacceptedSubmission`，错误 `-2002` |
| 恢复状态 | `active / writable / joined`，初始化完成 | 不是访客、退出中或未初始化 |
| 阻断标记 | 没有 `blockedReason` | 不满足现有冲突复核入口条件 |
| 实际节点数 | 10 | 9，但 GET 的 `deviceCount` 仍为 10 |
| 只在本地 | L10 `113A`、L9 `115B` | 云端缺少这两个实例 |
| 只在云端 | 无 L11 | L11 `1152`；UUID、地址与本地 `localDeletion / cleaned` 记录一致 |
| L11 本地删除清理 | 10:35:15 完成，无待清理项 | `cleaned` 不是云端删除已确认的证据 |
| C002 Profile | `calibrationMode=none` | `calibrationMode=planeCal`；另有 `daylightSensorAddress=113A` |
| NetKey / AppKey | 与 GET 相同 | 8 个共有节点的 Device Key 与主地址也相同 |
| Scene / Schedule / Switch | 与 GET 对应数组相同 | 当前没有这些数组被改写的证据 |

`spaceData.sceneConfigurations=[]` 与云端缺字段，在当前生产逻辑比较中已经等价；`sceneDisplayOrder` 被排除于同步比较。本次不是简单重现 11 月 3 日修复的空 Scene 扩展兼容问题。

共有节点还存在字段表示与参数差异，例如本地部分灯具导出色温范围 2700～6500 K，而 GET 缺少相应范围字段，GET 又补了一些 0/false。不能把所有缺失、0、false 都视为等价，也不能在没有协议/导入语义证据时认定全部是服务端丢字段。

### 原始提交证据的限制

导出包含回执摘要，不包含完整不可变提交和基线。当前生产函数计算导出逻辑配置摘要为 `c310e7bff8cabdc6`，导出记录的 `submissionSHA256` 为 `bb9ccb720f7d0117`；因此当前导出不能直接代表原 POST 内容。基线仅记录 7 个节点及摘要，具体集合也未提供。

这不影响现场失败点的定位，但限制了进一步归因：不能确定最初 POST 是否发出、服务器是否部分处理、accepted 落盘是否失败，也不能把当前两份快照的全部差异逐项归因于那一次上传。`prepared` 表示没有持久化 accepted 证据，不等于“请求肯定没发出”。

## 修改前为什么重试一直失败

1. 普通 Space 同步、Site 内嵌 Space 同步等入口，先调用 `SpaceConfigurationSafety.resumeUpload`，恢复旧回执后才会准备新 POST。
2. GET 成功后，`resumeUpload` 在一般回读比较之前调用 `reconcileSameVersionNodeRemoval`。
3. 该函数在远端版本不低于提交版本、远端实际节点数量少于回执记录的实例数时，检查回执必须为 `accepted`。现场诊断证明命中了这个条件。
4. `prepared` 返回 `unacceptedSubmission`；此时还没有验证两边是否真的只是删除关系。
5. 此错误只记录失败。只有 `completeBaselineUnavailable`、`notOnlyNodeRemoval` 才在这个分支设置冲突复核标记。
6. 上层立即结束同步，原来的完整回读确认、基线一致时替换 prepared、回读冲突时进入人工复核等路径均到不了；新 POST 也不会发送。
7. Space 导航栏没有看到复核阻断状态，只提供再次 SYNC。回执已落盘，退出重进和重启也不会解除这个循环。

关键代码：

- `SunSmart/Common/Data/SpaceConfigurationSafety.swift`：`resumeUpload`、`reconcileSameVersionNodeRemoval`、`requiresConfigurationReview`、`cloudBaselineReview`。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift`：上传前恢复回执，失败即结束；网络成功后才 `markSubmissionAccepted`。
- `SunSmart/Main/Space/Controller/SpaceViewController.swift`：`updateSyncState`、`showConfigurationRecovery`。
- `SpaceConfigurationSafety.uploadBeforeUnbind` 与 `ShareAuthorityViewController` 的解绑前 Site 同步复用该流程，也受影响。

上述保护属于修改前的策略。用户已明确 Web 可在同一时间戳修改配置，版本相等时应直接采用云端；本轮不再要求用户逐项复核这些业务差异。

## 引入时间与前后区别

以下是代码提交时间，不是 App 发布或用户安装时间。

| 提交 | 时间（UTC+08:00） | 变化 |
| --- | --- | --- |
| `abfbe5a7` | 作者 09-07 17:46；提交 09-08 11:02 | 建立 prepared → accepted → verified 机制；未知结果留回执，通过回读完成确认或冲突处理 |
| `206d2095` | 作者 09-09 20:48；提交 09-10 11:40 | 明确 `parse_error` 拒绝时清理对应 prepared；超时等未知结果仍保留 |
| **`153bc667`** | **作者 10-28 12:23:24；提交 10-28 13:52:34** | **引入同版本删除协调及 prepared 提前失败，截断原恢复出口** |
| `1e1c7b9a` | 10-28 15:02 | 远端版本适用范围由相等扩至不小于；现场版本相等，在此前已会触发 |
| `7405226d` | 11-03 17:59:27 | 修复空 Scene 比较，并完善 accepted 同版本冲突的显式云端选择；未覆盖 prepared 的提前返回 |

`153bc667` 的父提交为 `7b0aa0a07cdb3b9a10aea1e6dcc7edb9bb9e2836`。父版本的成员协调对 prepared 跳过自动删除，但允许继续一般回读：匹配可确认，符合已确认基线可重新提交，不匹配最终设置 `uploadReadbackConflict`。不能说父版本能自动合并本次混合差异，但它没有新增这条永久提前返回路径。

现有 `unknownPost` 用例把“未自动删节点、回执保留”视为正确，未验证后续恢复或 UI 复核可达。另一些 prepared 回归使用无有效 Device Key/Elements 的简化节点，没有进入严格的实例集合比较分支。因此这些测试此前通过，仍可能漏掉本次组合。

## 已实施行为

1. Space 的直接详情导入、Site 内嵌 Space 导入以及同步回读，共用 `prefersNewerCloud` 的版本选择。相同版本进入完整云端导入，绕过 prepared/accepted、删除日志、本地优先标记、旧基线及业务冲突对本地内容的保留。旧回执被替代，不伪造 accepted。
2. 复用已有云端导入的 generation、检查点和 pending import。旧删除、Scene 恢复及上传回执不能在重启后自动重放；晚到旧回调失效。同一已持久化快照重试复用原 generation。判断相等以实际本地版本为准；仅与尚未落地的暂存版本相等时继续原选定导入。
3. 同版本完整保留云端日程字段，不因缺少设备实例而清理日程绑定并生成新上传。现有 `cloudImport` 回执增加可选 `replacesEqualVersion`，让中断重试保持同一策略；无新表或独立恢复机制。较新云端的原有引用规范化行为保持不变。
4. 导入 App 数据事务中删除该 Space 的旧 Group 成员保存回执；事务失败时一并回滚。防止重启后把旧 Group 成员写回已覆盖的配置。
5. Site 名称、图片、时区和标准属性接受同版本云端值，成功保存后清掉对应待同步状态。完整 Site 导入也替换扩展数据中的本地草稿；同版本 Web 扩展变化不再产生 ambiguous/review 状态。写入失败仍可重试。
6. 部分 props 响应只覆盖实际提供的字段；缺字段不能当作删除，显式 null 仍表示清空。Zone 编辑自身的预上传 GET 若只是未变化的基线，继续使用其独立本地顺序令牌，以免刚保存的编辑在发送前被自己的 GET 消掉。

保留正常导入所需的身份/账户/权限、可解析格式、数据库事务和退出/取消检查；这些检查不用于在同版本业务冲突时保留本地配置。本地版本确实较新时仍走原策略。

主要实现文件：`ImportData.swift`、`SpaceConfigurationSafety.swift`、`DeviceScheduleAddressCleanup.swift`、`GroupMemberPersistence.swift`、`SitePropsEditPolicy.swift`、`SiteExtensionState.swift`、`SiteExtensionStore.swift`。

## 补充需求：旧项目缺属性

上一轮只覆盖部分兼容字段，未完整覆盖本次补充需求：Profile 缺少必填亮度/时间参数仍被预检拦截，完整 Site 缺少标准属性、时区或扩展时可能保留本地旧值。本轮已实施以下补全。

| 数据 | 缺失时的行为 |
| --- | --- |
| 完整 Site 名称、图片、时区 | 空名称、图片 0、时区 nil；不继承本地值 |
| 完整 Site 坐标、国家/城市/地址/描述等标准属性 | 使用 `SiteStandardProperties()` 的 nil 默认值 |
| 完整 Site 扩展或扩展内 siteType / triggerZones | 默认扩展、siteType=nil、空 Zone；清掉被覆盖的本地草稿 |
| Space 的 groups / scenes / schedules | 空数组；已有记录仍按云端内容导入 |
| Group 名称、父地址；Scene 名称、图片 | 空名称、父地址 0000；空名称、图片 0 |
| Profile 亮度、时间、校准、灵敏度、接力次数等参数 | 采用现有 `Profile.fromCloud` / 模型导入默认值；通用 Scene 与 Photocell 日/夜条件同步补全 |
| 日程的名称、启用、目标类型、动作、时间等 | 空名称、禁用、Group 目标、noAction、0 时间、空目标；节点槽沿用既有未分配默认规则 |
| Space 缺失 deviceBlinkMode | 恢复 none，修复原先沿用本地值的问题；其他展示字段沿用已有默认机制 |

Profile 主要默认值为 highEndTrim=100、lowEndTrim=0、occupancyLevel=100、vacantLevel=50、standbyLevel=0、taskLevel=100、manualOverrideTimeout=600 秒、powerUpState=0、powerOnCct=4500 K、adjustSpeed=50、relativeSensitivity=95、calibrationMode=none、targetNightBrightness=50、邻近照明接力数=2。根层缺失 T1～T5 沿用原云端导入的 0；独立 Scene 缺失时间沿用模型的 2/1200/2/600/2 秒。这些规则不读取本地旧 Profile。

统一默认值用于预检、实际解码、暂存快照重试和回读比较。成员比较摘要版本从 5 升至 6，复用已有旧摘要重建逻辑；默认配置恢复记录也按同样方式比较，避免合法缺字段与补全后的导出互相冲突。没有新增数据库表或独立恢复流程。

本轮处理的是字段缺失。显式 0、false、空数组和合法 null 保持原含义；显式错误类型或损坏数据不伪装成缺失。Space/设备 UUID、网络/Device Key、Group 地址、Profile 的 id/type、Scene 编号、日程 id 及设备组成仍需有效，不能凭默认值创造实体身份。单独的部分 `siteProps` 响应继续只应用所提供的字段，避免把局部响应当作完整快照。

新增行为回归已先复现失败，再验证修复：

- 同版本旧 Profile 缺参数、旧功能数组缺失、暂存旧快照后重试；清除 prepared/旧恢复状态，不产生反向上传。
- 8 种稀疏 Profile 经真实生产解码 → SQLite 保存/重启 → 生产导出，与云端默认化比较一致；显式零值保留、错误值拒绝。
- 缺业务属性的日程经生产 Codable → SQLite 重启/导出后，回读比较一致。
- 完整旧 Site 缺基础、标准和扩展字段后，SQLite 重启仍为默认值；失败回滚、重试及部分 props 读取均通过。

补充验证：`check_profile_persistence.py`、`check_timed_slot_persistence.py`、`check_timed_device_slots.py`、Scene roundtrip 三组，以及下列 Site/Space 相关套件通过。最新 generic iOS Debug 构建于 **2026-11-04 11:57** 完成，`BUILD SUCCEEDED`。测试与构建均使用当前 App 改动，未改 SDK；真实云端和真机验收仍未执行。

## Review 修复：Site 列表摘要与完整详情分开导入

P1 已复现并修复。上一轮无条件调用 `completeCloudSnapshot`，而 `SitesViewController.loadSitesRequest → SiteData.import → update` 传入的可能只是列表摘要，因此缺少时区、标准属性、扩展字段也会被当作清空。

调用方现在必须显式传入 `SiteImportSource`，没有默认来源：Sites 列表使用 `listSummary`；Site 详情、分享管理的 Site 详情及接收 Site 使用 `completeDetail`。来源沿 `SiteData.import` 传递到实际更新方法，不根据 JSON 中是否存在某个字段猜测快照是否完整。

- 列表只应用已提供的属性，缺失时区、图片、创建时间、来源、标准属性及整个扩展时保留原值。未提供的待同步属性及其确认时间也保留，不能把列表刷新当作这些修改已经上传成功。
- 完整详情仍遵循已确认规则：同版本云端覆盖本地，缺少可默认业务属性时补 App 默认值；完整详情的扩展替换保持有效。
- 列表显式提供 null 或 0 时仍按其含义应用；数据库保存失败时恢复本次属性、版本和待同步状态，可再次导入。

新增 SQLite 回归在修复前确认失败；修复后覆盖同版本/较新列表摘要、时区/城市/地址/HDB/Trigger Zones/扩展草稿保留、待同步字段保留、显式 null/0、保存失败回滚、重试和重启重载。已有完整详情缺字段补默认值、同版本覆盖及失败重试回归继续通过。

本轮 6 个相关脚本通过：`check_site_hdb_persistence.py`、`check_site_props.sh`、`check_site_transfer.py`、`check_site_trigger_zones.sh`、`check_site_space_mesh_context_ownership.sh`、`check_gateway_orphan_cleanup.py`；`git diff --check` 通过。前述 SQLite 测试运行生产导入/保存/扩展代码，网络及 Mesh 准备仍为夹具边界；列表 UI 到入口的真实请求未运行。

2026-11-04 **12:18**，`SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO` 构建通过。SDK 仍为 `one-dev` 的 `dbcf6f1` 加原有未提交改动，本轮未改 SDK。没有 commit、push、真机安装或线上请求。

最短人工验收：对已有时区、城市/地址、HDB 和 Trigger Zones 的 Site 刷新 Sites 列表，重启后确认这些配置及未提交草稿仍在；再进入完整 Site 详情，确认旧云端缺字段仍按默认值覆盖。

## 验证与边界

- 现场两份文件只在内存读取，不复制 Mesh Key 或账户数据到仓库。回执与 SQLite 使用临时测试目录。
- 现场样本：10 → 9 节点；保留云端 L11/1152，去掉本地独有 L9/115B、L10/113A；C002 为 `planeCal`；日程字段采用云端；prepared 清除，不再保持 blocked/pending，也不产生清理后的反向上传。
- 同版本用例覆盖正常、prepared、accepted、冲突、本地优先、删除日志、合法空配置、写入失败重试、持久化选定快照与旧回调失效。真实业务导入决定由 Timed 入口回归另行覆盖。
- Site 属性与扩展覆盖生产序列化、真实 SQLite、失败回滚、重启读取；Group 成员旧回执覆盖事务回滚及重启后不重放。
- SDK Node 解码/导入预检已对现场云端 9 个节点通过。Space 大型回执夹具仍以网络、SDK 和 App 数据行提交为边界，不能替代完整 App 对真实云端的运行验收。
- 构建：`SunSmartLocal.xcworkspace` / `SunSmart` / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO`，首轮 2026-11-04 11:40 完成，补充修复于 11:57 再次通过。本地 SDK 映射到 `nordic-sig-mesh-sdk-worktrees/one-dev`（`dbcf6f1`，已有其他任务未提交改动）；本轮未修改 SDK。
- 未运行真机、线上 POST/GET 或 Mesh 下发。用户的 `AGENTS.md` 改动保留，未 commit/push。

已通过的独立回归：

- `bash scripts/check_site_props.sh`
- `bash scripts/check_site_trigger_zones.sh`
- `bash scripts/check_site_hdb_type.sh`
- `python3 scripts/check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk`
- `python3 scripts/check_group_member_persistence.py`
- `python3 scripts/check_space_membership_lifecycle.py`
- `python3 scripts/check_proximity_scoped_import.py`
- `python3 scripts/check_timed_empty_target_cloud_sync.py`
- `python3 scripts/check_cloud_node_import.py --snapshot <现场云端文件>`
- `python3 scripts/check_space_recovery_receipts.py --cloud-authority --equal-cloud-sample <现场导出> <现场云端文件>`
- `git diff --check`

完整回执套件已通过：`python3 scripts/check_space_recovery_receipts.py --equal-cloud-sample <现场导出> <现场云端文件>`，包含现场样本、旧版本回读、普通上传、失败重试、重启与生命周期回归。该夹具把网络重试退避从 500 ms 缩短为 1 ms，保留异步取消点；验证的是重试状态和结果，不是实际等待时长。

## 最短人工验收

1. 安装本次构建，进入“空间 2”并同步。预期采用当前云端快照，不出现本例的未确认循环，也不要求选择本地/云端。
2. 核对 9 个设备、L11/1152、C002 校准配置及日程；退出重进并重启，再次同步，旧 L9/L10 或旧 Group 成员配置不自动回来。
3. Web 同时间戳修改 Site 名称/属性/扩展及 Space 配置，App 刷新后采用云端值；再在 App 做一次新修改，确认更高版本的普通上传仍正常。
4. 用缺少上述业务属性的旧项目刷新 App，确认缺项为默认值、已提供的 0/false 保留；退出重进/重启再同步，不恢复旧本地值，不出现未确认循环。
5. 导入中断/存储失败后重试应完成同一云端替换；真实 Mesh 执行另按对应功能验收。

服务端 GET 的 `deviceCount=10` 与实际 nodes=9 仍不一致，本次按 nodes 导入，不依赖该计数决定覆盖。是否需要修正 Web 的版本生成、计数或事务一致性，由后端/Web 团队另行核对；不是本轮 App 修复的发布前置条件。本轮没有修改任何后端代码、配置或部署。
