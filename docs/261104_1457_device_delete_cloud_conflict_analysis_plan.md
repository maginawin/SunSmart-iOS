# 删除设备后 Space 同步阻断：现场分析与修复方案

> 2026-11-04 补充：文末新增“Space 1 强制删除 L2”样本。该样本已发出上传，失败为 HTTP 500 / 9999，与本文原 Space 2 样本的旧回执冲突不同。以下原方案不能直接视作 L2 本次失败的修复方案。

## 结论与边界

当前 App 的“服务器优先”有条件：云端版本等于或高于当前本地版本才自动完整导入。本样本本地版本高于云端 9 秒，因此仍走旧上传回执恢复；回读不匹配后进入 `uploadReadbackConflict`，阻止后续上传和设备添加。存在两个需要补齐的流程：本地较新且旧回执冲突时的云端优先出口，以及该错误的“重新加载云端”覆盖入口。

分析后用户已确认实施。App 修复、相关离线回归及 SunSmart generic iOS Debug 编译已完成，未提交；真实服务器/设备验收未运行。源码基准：`feat/daylight-saving-261024` / `110b7ce8ee1f90480dd50c34f6d836a4a916a784`，开始分析时工作树干净。现有 SDK 链接指向 `nordic-sig-mesh-sdk-worktrees/one-dev`，未写入 SDK。

输入：

- `/Users/maginawin/Downloads/Space_空间 2_20261104_140849_839+0800.json`
- `/Users/maginawin/Desktop/xyy server data.txt`

下文不保存密码、网络密钥或 Device Key。分析阶段未构建；实施验证记录见文末。未运行真机或发起真实服务器请求。

## 现场证据

Space UUID 一致；NetKey/AppKey 相等，8 个共有节点的 Device Key 和主地址相等。Group、Scene、Schedule、Switch、EFC 和整个 `spaceData` 数组/对象在两份样本中相等。当前差异不是上午的 Profile 校准冲突或空 Scene 字段兼容问题。

| 项目 | App | 服务器 / 含义 |
| --- | --- | --- |
| 当前版本 | 1793771786，13:56:26 | 1793771777，13:56:17 |
| 最近确认版本 | 1793771641，13:54:01 | App 后续变更尚未确认 |
| 设备数量 | 9 | 10 |
| 共有设备 | L1～L8，共 8 个 | 身份相同 |
| 本地独有 | L9，115E | 服务器没有此实例 |
| 云端独有 | 无 | L11，1152；L10，1161 |
| 删除日志 | L11 于 13:56:16 cleaned；L10 于 13:56:25 cleaned | cleaned 仅证明本地引用清理完成 |
| 上传回执 | prepared，提交版本 1793771777 | 不是当前 9 节点版本 |
| 最新错误 | 14:08:45，remoteValidation / remoteConfigurationMismatch，-2002 | blockedReason=uploadReadbackConflict |
| 权限和恢复 | writable / active / joined，初始化完成 | 不是访客或未初始化 |
| 待办 | pendingUpload=true；pendingImport=false；pendingDeletionCleanup=false | 阻断来自上传冲突，不是删除清理未完成 |

导出中还有一条 13:44:13 的 `sameVersionRemoval.unacceptedSubmission`，其本地版本为 1793760893。这是更早的诊断，不能当成本次最新失败原因。

虽然用户本次操作是删除一个设备，日志仍保留了两条最近删除记录。不能由此推断本次单次点击删除了两个设备；可以确认本地已有连续变更与旧回执叠加。

## 生产比较函数核对

使用已有 `check_space_recovery_receipts.py` 的编译边界，在临时目录注入只读探针，调用当前生产 `configurationData` / `configurationFingerprint`，未修改测试或生产源码。

| 候选配置 | 生产逻辑配置摘要 | 与导出状态的关系 |
| --- | --- | --- |
| 当前本地 9 节点 | 69e3495e68800f5b | 当前待上传内容 |
| 当前服务器 10 节点 | c86578563db07a7e | 与旧提交摘要不同 |
| 当前本地补回 L10 | 7b190dff5a3c1872 | 等于 submissionSHA256 |
| 当前本地补回 L10、L11 | 466167e64586a263 | 等于 baselineSHA256；baselineNodeCount=11 |
| 当前本地仅补回 L11 | 37caf0e453ec08f8 | 不匹配旧提交 |

这支持以下本地逻辑配置链：已确认 11 节点 → 删除 L11 后提交 10 节点 → 再删除 L10 后剩 9 节点。但服务器的 10 节点是另一组：仍有 L10、L11，没有 L9。因此“服务器节点数量也是 10”不能证明提交已正确回读。

摘要只覆盖生产逻辑配置投影，并且导出仅保留截短摘要；它不是原始 POST 全字段的完整证明。原不可变提交、基线文件以及 POST 请求/响应未提供，无法确认为什么服务器保留 L11、遗漏 L9，也无法判断 POST 未发出、超时、部分处理、后续覆盖或 accepted 落盘失败中的哪一种发生。`prepared` 不等于请求肯定未发送。

探针还确认：现场版本条件下 `prefersNewerCloud=false`；设为现场阻断原因后 `requiresConfigurationReview=true`，而 `needsCloudSnapshotReview=false`。临时探针没有执行完整 App 数据库导入或网络状态机，不能声称现场端到端重现通过。

## 完整触发链

1. `DevicePermanentDeletionCleanup.swift` 完成本地引用清理并持久化 `cleaned`，保留待上传变更。正常情况下短暂需要同步是预期行为。
2. `CloudSynchronizationManager.swift` 在生成新上传请求之前，先运行 `SpaceConfigurationSafety.resumeUpload`。旧回执失败则直接结束任务，当前 9 节点版本不会得到新 POST 机会。
3. `SpaceConfigurationSafety.prefersNewerCloud` 对比内存/落盘本地版本、最近确认版本、submission 和 pending import 的最大版本。云端 1777 < 本地 1786，所以上午已经加入的同版本完整覆盖分支不适用。
4. 旧 prepared 回执的 GET 回读进入一般配置比较。生产逻辑配置包含节点成员集合；远端保留 L11、缺失 L9，与提交逻辑配置不同。最新诊断明确为 `remoteConfigurationMismatch`。
5. prepared 回执只有在云端仍符合最近确认基线时，才可以按未发送提交替换。服务器逻辑配置也不同于 11 节点基线，因此这条恢复路线不能解决本例。重试结束设置 `uploadReadbackConflict`。
6. `SpaceData.deviceOperates` 对 blocked Space 只保留控制能力；`canEditing` 同样返回 false。Lights、Sensors、Switches、Others、Group 等共享这些判断，因此添加设备被禁用。不能靠解锁某个按钮修复。
7. 重新同步仍先恢复同一旧回执，形成重复失败；退出重进也不能仅凭页面刷新清除落盘状态。

`readbackRemovals` 只投影有 cloudRemoval 或 replacement 证据的已完成实例。本例是 localDeletion，不会拿本地 cleaned 日志伪造“云端已删除”。而且云端还缺 L9，仅放宽本地删除比较也无法解释全部差异。

## 云端重新加载也有遗漏

`SpaceViewController.showConfigurationRecovery` 仅在 `needsCloudSnapshotReview` 为 true 时生成完整覆盖 review；该函数当前只识别 `cloudBaselineNeedsReview` 和 `cloudConfigurationConflict`，不识别 `uploadReadbackConflict`。

因此本例选择“重新加载云端”时没有调用 `prepareReviewedCloudImport`，只把 GET 交给 `restoreConfiguration(authoritativeGET: true)`。`authoritativeGET` 不等于无条件覆盖许可。云端较旧，`ImportData.update` 仍进入普通协调与 `preservesLocalChanges` 保护；待上传回执和删除日志可能返回 preserved，无法完成选择的云端覆盖。这是源码确认的入口缺口，未运行 UIKit 点击验收。

## 建议决策

已确认：**正常本地修改允许上传；确定无法按基线/提交确认的业务冲突，完整采用当前有效云端快照，即使云端时间较旧。** 显式“重新加载云端”也进入完整覆盖流程。这里是对现有同版本规则的扩展。

本例按该策略恢复后的准确结果是云端 10 节点：L10、L11 会重新出现在 App，L9 被移除。这只是配置替换，不代表已 Reset 的实物重新入网；若需再次删除 L10/L11，应在恢复完成后重新执行正常删除上传。若实际目标是最终保留本地 9 节点，则属于采用本地修改的另一种策略，不能同时宣称完全以这份云端快照为准。

两个替代方案：

- 只修复手动云端恢复：改动较小，用户仍需点击一次恢复；不能满足后台冲突自动云端优先。
- 任意 GET 内容不一致立即覆盖：不推荐。正常删除后、POST 之前服务器本来就是旧状态，上传前 GET 会立刻撤销刚做的删除；离线新增也会丢失。只有把整个 App 修改体系改为服务器事务先提交才可能全面采用该规则，这超出本次最小修复。

## 实施计划

1. **补齐行为复现。** 扩展 `Tests/Group/SpaceRecoveryReceiptTests.swift`、`NewerCloudImportTests.swift` 和已有回执脚本。构造完整合法身份的 11 → 10 → 9、prepared 旧提交与服务器另一组 10 节点；覆盖相同时间不同成员、本地较新、无新 POST、失败后添加权限和恢复出口。样本做脱敏，不能把本机密钥提交到仓库。
2. **收敛冲突裁决。** 在 `SpaceConfigurationSafety` 中保留“回读精确匹配 → 确认旧提交，再上传后续本地修改”和“云端未变基线 → 安全准备新上传”；对确认的业务冲突转入已选云端完整导入，覆盖 prepared/accepted 及无回执基线冲突。网络失败、身份不符、撤权、无效载荷或存储失败不能伪装成业务冲突成功。不要仅把 `prefersNewerCloud` 改成恒 true。
3. **复用持久化导入机制。** 扩展现有 cloudImport / pending import / checkpoint，而不是新增独立状态机。较旧快照被选定后，要能绕过本地时间、旧回执及本地删除保护；记录选择原因和版本，在重启后恢复同一策略。先落盘选择和备份，再切换 generation，导入成功后统一清旧 submission、阻断和已放弃删除/成员保存回执；失败可重试且不会半清空。完整业务覆盖沿用旧字段默认化，不能意外以本地配置补齐云端缺字段。
4. **补齐所有入口。** `ImportData.update` 的直接 Space 与 Site 内嵌导入、`resumeUpload`、显式重新加载共用裁决与导入结果。过渡/存量错误 `uploadReadbackConflict` 接入完整云端恢复。`CloudSynchronizationManager` 必须接纳导入后新生命周期并完成当前同步；旧回调不能恢复旧提交。涉及解绑前上传的共享入口一并回归。
5. **共享权限与诊断。** 不绕开 `deviceOperates` / `canEditing`；完成持久化导入后刷新所有添加入口。DEBUG 记录本地/提交/云端版本、成员数量、差异类别、选择原因、导入阶段，区分历史诊断和最新失败。不输出完整 payload 或密钥。

维护成本集中在现有回执/导入的裁决原因及恢复语义，无新增数据库表或独立恢复系统。影响所有使用共享代码的品牌；预计无需 SDK、资源归属或服务器实现改动。

## 验证与外部证据

最小回归应覆盖：正常单次删除和连续删除；上传响应未知；旧提交精确确认后继续新上传；服务器成员混合变化；云端较旧/相等/较新；合法空 Space/旧缺字段；撤权、地址复用和密钥不匹配；选择后落盘失败、导入中断/重启、晚到回调；恢复后的再次新增/删除与再次同步。回归要经过生产序列化与恢复文件读写，另覆盖真实 SQLite/SDK 导入边界，不能只给 fixture 赋值就算完整恢复通过。

优先运行 `check_space_recovery_receipts.py`、`check_space_membership_lifecycle.py`、`check_space_sync_cleanup.py`，以及实际修改触及的导入/持久化回归。Swift 修改完成后用当前正确映射的 `SunSmartLocal.xcworkspace` 构建一次 SunSmart Debug generic iOS；不使用 Simulator，不自动运行真机。

最短人工验收：恢复该 Space → 核对采用云端后的 10 节点集合和添加入口 → 退出/重启确认不回放旧删除 → 新增测试设备并同步 → 删除一个测试设备并同步 → 再 GET 核对新集合和重进状态。固件 Reset 与云端记录删除分别检查。

服务器配合仅需只读联调证据：对应版本的 POST 请求、响应和随后的 GET，核对节点集合与 UUID/地址关系、更新时间是否由同一写入产生。服务器团队负责解释节点保存/删除语义及是否有其他写入方。本轮不能将当前差异判定为服务器 bug，也不提出未经证明的服务端修改；若后续证明服务端丢写，单独记录接口契约和发布依赖。App 冲突恢复可以独立实施，但正常删除/新增的真实云端往返仍是验收条件。

## 已实施结果（2026-11-04 15:57，UTC+08:00）

- `SpaceConfigurationSafety` 的共享云端选择增加已诊断业务冲突的出口：`uploadReadbackConflict`、`cloudConfigurationConflict` 可以选择版本较旧的完整云端配置。普通较旧 GET 不触发此规则；已选默认修复的云端来源未变化时仍允许修复上传。
- prepared 回执不再在纯删除协调函数里提前返回 `unacceptedSubmission`，而是继续一般回读：准确匹配可确认；未变化基线可安排新上传；业务冲突可选择完整云端。
- accepted 回执遇到混合新增/删除时，区分普通成员集合变化与身份异常。相同 UUID、重叠 Element 地址对应的实例身份变化继续保护；自动冲突选择需要现有实例证据。没有完整证明的历史回执、无效载荷、撤权、存储失败和网络失败不会被伪造成成功覆盖。
- 云端选择复用已有 checkpoint、generation、独立恢复目录及 pending import。现有 `CloudImport` 增加可选 `replacesConflictingVersion`，用于重启后保留完整云端字段语义；没有新表或独立恢复系统。成功导入后旧回执与删除日志不能重放，旧上传回调失效。
- `ImportData.update` 对本次协调新发现的业务冲突重新进入一次完整导入预检；直接 Space 与 Site 内嵌 Space 共用该方法。上传前回读和提交后回读也调用同一选择机制。`uploadReadbackConflict` 纳入显式云端审核恢复入口。
- 沿用 CloudSynchronizationManager 已有的 `adoptedCloudImport` 生命周期接纳，不另外创建任务队列。导入后的共享保护状态解除，恢复编辑/添加；没有为单个按钮添加绕过逻辑。
- 增加 DEBUG 云端选择日志，只输出本地/提交/云端版本、冲突标识及节点数；补齐提交回读诊断中的云端时间戳。

实际生产改动限于 `SpaceConfigurationSafety.swift`、`ImportData.swift`、`DeviceScheduleAddressCleanup.swift`。资源、品牌条件、依赖声明及 SDK API 均未修改。共享五品牌逻辑一致，本次采用 SunSmart 代表构建。

### 时间戳与数据保留

`SpaceViewController.swift` 中的 `markSpaceUploadNeeded` 使用 `max(now, lastUpdate + 1, lastUploadCloudTimestamp + 1)`，正常本地修改会递增版本并进入待上传状态。它保证高于本机已有版本和最近确认版本，不能保证高于尚未读取的其他客户端最新版本，也不能证明这次内容已被服务器持久化。

因此正常上传路径保留新修改；已确认业务冲突后，采用云端会有意放弃未确认的本地差异。本样本的目标结果仍是云端 10 节点，不能承诺“时间戳较新，所以任何情况下都不丢本地修改”。

### 行为回归与代码复核

新增用例先在修改前复现 prepared 失败；后续分别复现 accepted 分支、直接导入分支与 Device Key 异常，修正后通过。新增覆盖：连续本地删除、prepared/accepted、已存冲突、直接导入中新发现冲突、持久化选定快照后恢复、合法空云端、取消、checkpoint/state 写失败、错误网络/Device Key、坏 Timed、旧回执精确匹配、旧基线未变、旧回调失效、清理删除记录，以及恢复后新增节点和新一轮同步。

旧回归中“任何不同都必须让 resumeUpload 失败”的预期按已确认策略调整：原提交的直接确认仍要求准确匹配；合法冲突可以通过独立云端导入完成，并断言旧回执已经失效、云端配置被采用。Scene、Timed target 和节点成员等路径保留严格比较测试；损坏数据、密钥/地址身份变化和未知证据仍有拒绝用例。没有把冲突导入算成原 POST 已确认。

按本工作树不使用子代理的规则，完成共享选择、异步导入保护、恢复落盘和回调接纳的本地差异复核，未执行独立代理审查。

### 验证记录

| 验证 | 结果 / 边界 |
| --- | --- |
| `check_space_recovery_receipts.py` 全套 | 最终修改通过；生产状态机、Codable/恢复文件持久化、导入准备及受控网络边界 |
| `check_space_membership_lifecycle.py` | 通过；成员生命周期、权限、取消、上传屏障等 |
| `check_space_sync_cleanup.py` | 通过；引用清理、合法空值及异常快照 |
| `check_space_protection_snapshot.py` | 通过；真实保护文件读取与失效 |
| `check_cloud_node_import.py` | 通过；节点 codec、异常字段分类与重试 |
| `check_group_member_persistence.py` | 通过；真实独立 App/Mesh SQLite、事务回滚及云端替换时旧成员回执清理 |
| SunSmart Debug generic iOS | 通过；`SunSmartLocal.xcworkspace`、iphoneos、generic/platform=iOS、`CODE_SIGNING_ALLOWED=NO` |
| `git diff --check` | 通过 |

回执夹具保留 SDK/数据库实际提交与网络的模拟边界；SQLite 成员保存回归只覆盖相关持久化机制，不等于执行完整 App 导入。没有运行完整现场云端往返、真机 UIKit、BLE Reset 或 Mesh 验收。

构建 DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-cli`。构建出现既有 weak/strong capture 和不可达 default 等警告，没有编译错误。SQLite 回归首次受默认 Clang ModuleCache 写权限限制，指定已有可写的 `CLANG_MODULE_CACHE_PATH` 后通过；没有清缓存。

实施过程中两份原始现场文件已不在用户给定路径。额外的完整样本恢复探针因文件不存在而未执行成功，不能计为通过；保留分析阶段已完成的生产摘要核对与本次等价合法夹具验证。原始 POST 的未知结果仍无法从本轮证据进一步归因。

SDK 来源为 `one-dev` / `dbcf6f1a7014320331f3cccdc0a46edc1a0baa88`，其中 MeshProxyMessageCommand、SchedulerActionStatus 及 Scheduler readback 测试/脚本的既有修改均未触碰。本任务没有 commit、push、同步其他工作树、操作真机或修改外部服务。

## 2026-11-04 补充：Space 1 强制删除 L2

### 结论与证据边界

本次本地删除完成，云端上传确实发出；直接失败原因是 `/sitespace/sync/siteprops` 返回 HTTP 500、`{"code":"9999","message":"unknown error"}`。当前材料只能定位到该接口失败，无法确定内部异常是删除事务、请求字段兼容、解压解析还是其他服务问题，也不能排除实际 Site 请求中的 App 字段问题。不能把本次解释为旧回执冲突阻止 POST，或把 Reset 超时当成云端 500 的原因。

输入为 `before force delete app export json.json`、`force delete L2 logs.txt`、`after force delete L2 app export json.json`。源码仍为 `110b7ce8ee1f90480dd50c34f6d836a4a916a784`。本轮只读取文件、比较 JSON、核对源码并补充本文；未修改业务代码、SDK 或服务器，未发送网络请求、构建或运行真机。

### 事件链

1. 日志第 5～23 行：向 L2 主地址 `0x0026` 发送 `ConfigNodeReset`，重试后未收到应答并取消。因此实物是否已 Reset 未确认。
2. 第 24～26 行：用户确认强制删除，本地输出 `cleanup=complete proximityTasks=0`。删除记录完成时间为 15:16:30（UTC+8）。
3. 第 29～53 行：上传前读取 `/sitespace/get/spaceprops`，HTTP/业务码均为 200；读取的是删除前的 2 节点版本，版本号 `1793776521`。随后记录 `noPendingReceipt`，本轮上传前没有旧 submission 阻断。
4. 第 66～80 行：执行 `syncSite`，仅同步 Space 1，POST `/sitespace/sync/siteprops`，实际 gzip 请求体 6157 字节，声明与实际编码一致。日志省略正文。
5. 第 83～98 行：返回 HTTP 500、9999，App 将错误写入 Space。没有成功响应后的云端回读记录，不能断言服务器完全未写入或已经完成删除。

### 删除前后对照

| 项目 | 删除前 | 删除后 |
| --- | --- | --- |
| 节点集合 | L1 `0023`、L2 `0026` | 仅 L1；L1 导出对象完全相等 |
| deviceCount / 本地 deviceNumber / luminaireNumber | 2 | 1 |
| 当前版本 | `1793776521`，15:15:21 | `1793776591`，15:16:31 |
| 最近确认版本 | `1793776521` | 不变 |
| Scene 4 新配置成员 | L1、L2 | 仅 L1 |
| 本地 Mesh Scene 4 addresses | `0023,0026` | `0023` |
| pendingDeletionCleanup | false | false |
| pendingUpload | false | true |
| submission | 无 | prepared，提交版本 `1793776591` |
| syncCloudError | null | 9999 |
| recoveryPhase / authority | active / writable | 不变 |

两份文件均包含 9 个 Group、20 个 Scene、4 个 Schedule、2 个 Switch。顶层 `groups/scenes/schedules/switches/emergencyFireControllers` 完全相等；`spaceData` 只有 Scene 4 的 deviceMembers 删除了 L2，其他字段保持一致。网络密钥相等，未写入本文。结构化检查未发现删除后的业务导出中残留 L2 UUID 或其 `0026～0028` 元素地址；本地 Scene 配置和 Mesh Scene 地址也同步清理。导出诊断 `issues=[]`，但这不能替代服务器接口校验。

### 为什么仍有 prepared 和历史冲突记录

- `CloudSynchronizationManager.swift:1441` 附近先保存 submission，再发请求；仅成功响应才调用 `markSubmissionAccepted`。`SpaceConfigurationSafety.swift:1245` 的 `rejectSubmission` 只对明确的解析拒绝或指定权限/资源错误清理记录。通用 500 / 9999 保留 prepared，以便后续确认写入结果。因此 prepared 是本次请求失败后的恢复状态，不是“没有发请求”的证据。
- `CloudSynchronizationManager.swift:1537` 附近将失败保存为 `syncCloudError=9999`，本地版本尚未得到确认，故仍需同步。
- 两份导出均保留 `lastSyncDiagnostic=-2005 / baselineConfigurationMismatch`，其时间为 15:12:39；本次删除发生在 15:16:30。该诊断删除前后完全相同，不能作为本次最新失败原因。删除前 pendingUpload=false、syncCloudError=null；本次最新 readback 为 noPendingReceipt。
- `DeviceLightsViewController.swift:940` 的强制删除沿 `forceRemove` 完成本地清理，再调用 `commitLocalChangeForCloudSync`。强制删除允许无 Reset 应答时移除本地记录，但云端保存仍需要上传接口成功。

### 尚缺哪些证据

这两份是 Space 调试检查快照，标记 `purpose=localConfigurationInspection / uploadable=false`。`DebugCloudJSONExporter.swift:181` 使用 Space 包装生成它们；现场真正发送的却是 Site 上传，`NetowrkReqeustApi.swift:421` 包装为 `site + user`。因此导出能证明本地前后变化，不能当成 task 91 的精确完整请求体，也不能把调试标记误认为发给服务器的字段。

最短后续核查由服务器团队只读提供：

1. 查 2026-11-04 15:16:31（UTC+8）附近，Site `4BA40AB1-8D22-49D2-84F8-884A37E01EB5`、Space `C601D629-0E70-49F5-BDBC-420FCBD19005` 对应 `/srv2/sitespace/sync/siteprops` 的异常栈及失败步骤。
2. 在受控环境核对该次请求解压后的完整 Site 数据，确认请求解析、节点删除、Scene 成员更新分别到哪一步；日志或交接仅保留脱敏摘要，不能复制完整密钥。
3. 核对失败后实际云端版本、节点集合和 Scene 4 成员，判断事务回滚或部分写入。日志中的 spaceInfo 是上传前读取，不能回答上传后的状态。

预期接口契约是接受本次合法本地配置变更并返回明确结果；本例目标变化为设备 2→1、L2 移除、Scene 4 移除 L2。具体责任及修复方向必须以异常栈和实际请求为准；当前不提出服务器代码变更或发布依赖，也不以 App 冲突恢复方案代替接口异常定位。
