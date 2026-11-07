# 添加设备后云同步导致设备消失：原因、引入提交与修复方案

日期：2026-11-07，UTC+08:00。分析工作树 `feat/timed-simple-261106`，HEAD `f53d4dcace3807e43d3f7581177e0dad52dd228d`。开始分析时工作树干净。本轮只分析和编写本文档，没有修改 App／SDK 业务代码、服务器或输入文件，没有提交。

## 1. 结论及重要未完成项

**这次是服务器上传异常与 App 等版本覆盖策略组合造成的数据丢失。** 日志里的上传不是成功：`POST /sitespace/sync/spaceprops` 返回 HTTP 500、业务码字符串 `9999`。随后重新进入 Space，`/sitespace/get/spaceprops` 返回 HTTP 200，但包含 `deviceCount=2`、`nodes=[]`。App 将这份与本地同版本的响应选作完整权威配置，覆盖后本地设备数由 2 变成 0。

- **已证实的 App 问题：** 即使本机上传结果未知、存在 `prepared` 回执，也仅凭相同时间戳走完整云端替换；异常云端结果因此可以覆盖尚未确认的新设备，并退出待同步状态。直接触发这条等版本路径的提交是 **`eb9caaf3b0059d1cadc4c7ee3bdcc9c25988acf0`，2026-11-04 13:48:57 +08:00，`fix: sync issues of Xie YY`**。
- **已证实的服务端现象：** 上传返回 500；详情返回的计数与节点集合不一致；版本已经与本地新版本相同。**部分写入后失败是优先排查假设，并非已经证明的数据库事实。** 同样可能涉及读取聚合／缓存、节点解析兼容或其他写端。没有服务端请求体、异常栈、事务记录，无法定位服务器内部失败行和引入部署。
- **既有规则需要修订边界：** [11 月 4 日任务文档](261104_1110_space_prepared_sync_deadlock_analysis.md)明确记录用户确认过“同版本完整采用云端，覆盖本地业务修改和 prepared 回执”。当前实现和测试遵循该决定。因此本次应增加失败／未知上传的保护例外，不能把它描述成一次无意写错比较符，也不宜整体回滚旧修复。
- 推荐 **App 增加异常覆盖保护，同时服务器修复失败与快照一致性**。本轮方案尚未实施；服务器 500 的根因、当前已安装构建的准确 revision、真实 Mesh 状态及数据恢复仍未验证。

## 2. 输入与现场事实

### 输入

- App 导出：`/Users/maginawin/Downloads/Space_Space 1_20261107_093734_912+0800.json`
- Xcode 日志：`/Users/maginawin/Desktop/xcode logs.txt`
- 服务器响应：`/Users/maginawin/Desktop/server data.txt`

Site：`3E7A3B62-7742-44B2-9839-8005CEA233B4`。Space：`3486A356-ED8F-406C-8C83-EB8422387978`，名称 Space 1。全文不复制密码、NetKey、AppKey 或 Device Key。

### 添加后的本地快照

| 项目 | 证据与含义 |
| --- | --- |
| 捕获时间 | 2026-11-07 09:37:34 +08:00 |
| L1 | PID `2502`，地址 `0010`，3 个 Elements，创建时间 09:37:19 |
| L2 | PID `2502`，地址 `0013`，3 个 Elements，创建时间 09:37:20 |
| 设备数据 | `spaces[0].nodes` 为 2；`rawLocal.mesh.nodes`、`nodePropertys` 均为 2；原始 App Space 记录 `deviceNumber=2` |
| 本地版本 | `1794015449`，09:37:29 |
| 最近确认上传版本 | `1794015332`，09:35:32；早于本次添加 |
| 上传回执 | `pendingUpload=true`、`submissionPhase=prepared`、`submittedTimestamp=1794015449` |
| 本地错误 | 原始 App Space 行 `syncCloudError=9999` |
| 身份／权限 | owner，`active / writable / joined`，初始化完成，网络匹配，无待删除清理、无 pending import |
| 已确认节点基线 | `baselineNodeCount=0`；当前删除比较快照记录 2 个节点 |
| 内容摘要 | 使用当前生产 `configurationData` 计算得到 `96aa18aaf2c5957d`，与导出中的 `submissionSHA256` 相同 |

因此“需要同步”有真实依据：新增后的版本大于最近上传确认版本，且上传未确认。不能将此问题归为单纯图标误显示。`baselineNodeCount=0` 也说明本次两台设备不是当前确认基线中的旧节点。

摘要一致证明导出与回执的**逻辑配置比较内容**一致；不证明整个 HTTP 原始请求逐字节一致，也不替代完整回执中的所有身份字段。两台节点均在原始本地存储与正常业务导出中，未发现 App 导出先丢失节点的证据。

### 日志中的连续触发链

| 日志行 | 事实 |
| --- | --- |
| 13–27 | `syncSpace → spaceUpload`，POST `/sitespace/sync/spaceprops`；压缩体 2546 bytes，声明与实际 gzip 一致；正文被日志省略 |
| 28–44 | HTTP 500，响应 `code="9999"`、`message="unknown error"`；CloudSync 记录 Failure |
| 68–79 | 用户点击弹窗按钮，退出 Space 回到 Site，再点击 Space；断开前 NodePresence count=2 |
| 80–101 | 请求 Space 详情，HTTP 200／业务码 200，响应同一 Space、`updateTimestamp=1794015449`、`deviceCount=2`、`nodes=[]` |
| 110–123 | 导入前本地 device=2；local/submitted/remote 三个版本均为 `1794015449`；`SpaceCloudSelection ... conflict=false nodes=0` |
| 124–136 | 进入 importInProgress；导入后本地 device=0，note=`serverSummaryDiffersButLocalNeedsUpload` |
| 140–153 | 约 09:38:15 重新加载网络及扩展数据 |
| 180–181 | 后续恢复检查显示 `noPendingReceipt` |
| 208–215 | 进入设备页面后再次离开，NodePresence count=0 |

日志中的 Request 没有绝对时间或与导出绑定的 attempt ID，因此不强行将导出中的 9999 与这一条 POST 认定为同一次尝试；但日志内部的“500 → 退出重进 → 空节点 GET → 本地 2→0”顺序完整。

独立 server 文件与日志 GET 在本次相关字段上相同；完整对象只有一个密码字段值不同，不能称为逐字段完全相同。App／server 的 NetKey 与 AppKey 对象相等，Group、Scene、Schedule、Space 扩展和共同的普通属性一致，核心业务差异为 `nodes: 2 → 0`。

日志没有证明“Mesh 同步成功后设备被复位”。目前可以确认的是 App 配置被云端空列表替换；没有看到 Node Reset 命令。

## 3. App 为什么会接受这份响应

涉及共享入口，不局限于设备列表页面：

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `loadSpaceReqeust` 获取详情并调用 `restoreConfiguration(... authoritativeGET: true)`。
2. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `rejectSubmission` 对 500／9999 保留 `prepared`。仅明确的 `400 + parse_error` 或特定权限结果按各自规则退回；保留未知结果本身是合理的。
3. 同文件 `prefersNewerCloud` 第 262–286 行在远端版本等于当前本地版本时返回 true。此处没有要求不存在待上传回执，也没有证明远端 Nodes 包含本次新增实例。
4. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 在第 1953 行将其视为 `authoritativeCloudImport`。后续针对 pending 本地修改、节点集合、旧基线等保护以 `!authoritativeCloudImport`／`!reviewedCloudImport` 为前提，因而被绕过。
5. `beginNewerCloudImport` 刷新检查点、切换恢复 generation、暂存空节点快照并归档旧回执。旧回调失效是合理的生命周期保护，但不能修正错误的快照选择。
6. Import 第 2251 行允许 `lastUpdate >= self.lastUpdate`；第 2447 行附近移除现有非本地 Provisioner 节点，再按云端 `nodeDicts` 建回。本次列表为空，所以两台设备均没有建回。
7. 导入保存远端版本为本地及确认版本，完成 pending import；回执不再待确认，后续显示为无需继续上传。

同一选择逻辑也被 `resumeUpload → importNewerCloudIfNeeded` 使用，Site 内嵌 Space 导入同样会进入共享更新路径。仅给 Site 页面或设备列表加条件会漏掉同步回读等入口。

App 当前只把 `deviceCount` 与实际数组的差异作为诊断，实际导入按节点数组进行。**不能单独把 `deviceCount` 当作节点恢复依据，不能据计数凭空创建两个 Node。** 历史 Web 数据也曾有计数滞后，直接全局拒绝所有计数不等的旧数据会改变兼容行为。

## 4. 引入时间与测试为何没拦住

| 提交／阶段 | 行为及结论 |
| --- | --- |
| `32c768371`，2026-11-02 18:01:15 +08:00 | 建立较新云端完整替换路径；选择条件是远端版本严格大于本地、回执和待导入的最大版本 |
| `eb9caaf3` 的父提交 `3fe26b7f` | 此次等版本数据不会被该选择器选为较新云端 |
| **`eb9caaf3`，2026-11-04 13:48:57 +08:00** | 新增“与本地同版本也完整采用云端”，同时将最终导入条件改为 `>=`，覆盖 prepared／accepted 与本地修改；这是本次链路的直接引入点 |
| 后续 11 月 4 日冲突／旧版本修复 | 保留上述等版本条件；现场 `conflict=false`，本次不需要冲突分支即可触发 |
| `bc125d6b`，2026-11-05 | 普通上传的本地确认／减少 GET 等改动没有消除重进 Space 的等版本导入，本次日志证明该入口仍发生 |
| `e560574b`，2026-11-06 16:24:39 +08:00 | 新 Timed v3 导出格式。它是服务器 500 的兼容性排查项，尚不能据此断言它引入 500 |
| 当前 `f53d4dca`，2026-11-07 09:40:21 +08:00 | Scene 返回后的同步状态修改；与 09:37–09:38 样本时间相比更晚，且未修改上述共享覆盖链，不是本次直接原因 |

以上是仓库提交时间，不是发布或安装时间；未读取手机安装包 revision。当前源码与日志包含的选择和导入行为对应。

[NewerCloudImportTests.swift](../Tests/Group/NewerCloudImportTests.swift) 的 `testEqualCloudImports` 本来就要求等版本覆盖，包括 prepared／accepted、空云端、本地优先和删除记录等场景，并检查清除回执。这验证了原先确认的策略，却没有把“本机新设备提交 500／未知结果，远端同版本缺失这些实例”作为不能静默丢数据的独立验收条件。

先前空 Space、恢复回执的绿色结果也不替代此场景：它们的任务和数据边界不同。本轮已重新核对当前实现，不将历史测试结论当作当前现场验收。

## 5. 本轮离线验证及边界

复用 `scripts/check_space_recovery_receipts.py` 的编译设施，在 `/tmp/sunsmart_261107_device_loss_probe.py` 注入只用于诊断的入口；没有修改仓库测试和生产源码。实际输入为用户两份 JSON。

| 检查 | 结果 |
| --- | --- |
| 生产配置摘要对照 | 当前导出的摘要与记录的 submissionSHA256 相同 |
| 模拟实际 500 错误处理 | 执行生产 `prepareSubmission`、`rejectSubmission(9999, HTTP 500)` 后，2 个 Node 与 prepared 回执均保留 |
| 历史选择器 A/B | 从 Git 原文提取父提交及 `eb9caaf3` 的选择函数，以同一状态运行：父版本 false、引入提交 true、当前 true |
| 重新进入 Space 路径 | 执行生产导入准备、版本选择、恢复状态落盘／归档／完成逻辑：2→0，pendingUpload=false，needUpload=false，generation 更换 |
| 上传回读路径 | 执行生产 `resumeUpload`，得到相同的 2→0 结果 |

该诊断退出码为 0；这里“通过”表示成功复现现有缺陷，**不是修复通过**。历史 A/B 运行的是确切选择函数，不是对整个历史 App 的完整构建或 Git 全仓库 bisect。

边界：网络返回、App 数据库对象加载、Mesh 对象替换和 checkpoint 为现有夹具边界；Net/App Key 使用夹具的匹配身份，节点内容保留样本；原手机回执未完整导出，prepared 由样本重建，节点基线按已知空集合设置。验证执行真实状态文件写入，但没有执行真实手机 SQLite／SDK 全量提交；实际设备列表 2→0 由现场日志独立证明。未运行完整 App 构建、真机、服务端写入或 HTTP 重放。

SDK 映射只读核对：`.local-sdk/nordic-sig-mesh-sdk` 指向约定的 `one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，工作树干净；未修改 SDK。

## 6. 服务端应定位什么

### 已知、推断与缺失证据

| 分类 | 内容 |
| --- | --- |
| 已知 | POST gzip 形态正常，HTTP 500／9999；随后同 Space GET 200，版本为 1794015449，计数 2、实际 Nodes 0 |
| 已知 | App 的完整导出从同一 `nodeDicts` 同时写入 `deviceCount` 与 `nodes`；节点编码数量不完整会使导出失败。`spaceUpload` 包装保留 Nodes；`withoutBindingGeneration` 仅处理日程绑定字段 |
| 优先假设 | Space 标量（含版本、计数）先写成功，节点处理随后抛异常，事务未完整回滚；或写入成功但详情聚合／缓存漏了节点 |
| 兼容性假设 | 现场是 `timedSchemaVersion=3`，Nodes 不再输出 `schedules`／`custProps.schedulerModelStates`；服务端如果仍按旧格式必需读取，可能异常。原 v3 契约已将服务器存取兼容列为发布依赖，尚无本次联调完成证据 |
| 不能证明 | 本次压缩请求解压后的精确 Nodes 内容、数据库提交顺序、具体异常字段、是否有其他端并发写入，以及服务器哪个部署首次出错 |

相关既有契约：[Timed v3 数据格式与外部责任](261105_1429_space_timed_json_demo/261105_1429_space_timed_json_contract.md)。v3 假设必须由后端异常栈或兼容对照复现验证；不能因“最近改过格式”就直接回滚 App 数据结构。

### 给服务器团队的执行清单

1. 按 Site、Space 和版本 `1794015449` 定位 2026-11-07 09:37–09:39 +08:00 的 `/srv2/sitespace/sync/spaceprops` 与 `/srv2/sitespace/get/spaceprops`；以服务端访问时间及 request ID 精确关联，补齐异常堆栈。不要在共享日志输出密钥和密码。
2. 检查 POST 解压后 `spaces[0].nodes` 是否含地址 `0010`、`0013` 的两个实例，`deviceCount=2` 与 schema=3；如不含，继续定位请求端序列化边界，不能直接认定服务端吞节点。
3. 核对写前／写后 Space 行、节点关联、版本、事务回滚、缓存及读副本状态，排除 500 后已更新主表却未保存 Nodes，或 GET 聚合落后。检查同时间其他客户端写入。
4. 在受控环境使用脱敏的同形状完整请求复现。分别覆盖正常成功、节点写入中途失败、未知字段、v3 缺少旧节点日程字段、旧格式合法空数组，以及两个入口 `spaceprops`／含 Space 的 `siteprops`。
5. 修复已定位的解析／持久化／聚合错误。完整 Space 写入需作为一致快照提交，失败不得暴露部分版本；校验不支持的输入应在任何业务写入之前返回明确错误。读取应提供同一已提交快照的 Nodes、计数和版本，缓存失效与事务提交一致。
6. 验收成功上传后立即、重试、跨客户端读取均保留两台节点及相同网络身份；故障注入返回失败后，旧完整快照仍保持一致。合法删除全部设备应得到 count=0、nodes=[]，不能被修成永远保留旧设备。

责任方为服务器团队；本任务不修改后端代码、部署或运行配置。服务器修复与线上往返验收完成前，不能宣称云同步根因已全部解决。

## 7. 修复方案与待确认的规则例外

### 方案比较

| 方案 | 优点 | 风险／取舍 |
| --- | --- | --- |
| 只修服务器，保留无条件同版本覆盖 | 完全保留 11 月 4 日业务决定 | App 对下一次失败、未知结果或不完整读取仍可静默丢本地新增；不推荐单独采用 |
| **App 增加未知上传保护，服务器修复一致性（推荐）** | 截断本次数据丢失，同时保留本地干净时的正常 Web 同版本覆盖 | 必须确认原规则新增例外；未知结果下不能仅凭相同 timestamp 自动判定是 Web 删除还是本次 POST 未完整写入 |
| 所有等版本都不导入 | 规则简单 | 使 Web 不增 timestamp 的合法编辑不再生效，可能恢复此前死循环；不推荐 |

**建议确认的例外：同一 Space 存在本机尚未确认的提交，或可证明仍有未确认的本地新增时，远端同版本缺少这些实例／内容不符合提交，不能自动选为空权威快照并退休本地回执。** 本地干净、无未知上传时仍按既有规则处理合法 Web 同版本修改；合法空空间／明确云端删除仍需要可达。

现有字段不能可靠区分“Web 真正删除了尚未确认的本机新增”和“服务器失败造成缺失”。出现这类歧义时应保留本地和错误，提供可执行的重试／已有显式恢复选择；不能宣称通过计数或 timestamp 就已辨别用户意图，也不能自动反向上传覆盖另一端合法编辑。

### A. App 修复范围

- [ ] **先补行为回归。** 在现有 `SpaceRecoveryReceiptTests`／`NewerCloudImportTests` 以及上传流程夹具中，加入“确认空基线→新增两节点→真实生产提交序列→500／超时→同版本空详情→退出重进／重启”的组合。先复现当前 2→0，再将验收改为保留 2 节点、保留未确认状态和错误。使用现有真实持久化边界测试补充 SQLite／SDK 导入验证，不只在内存中赋值。
- [ ] **在共享云端选择之前处理异常候选。** 主要修改 `SpaceConfigurationSafety.swift` 与 `ImportData.swift`，复用现有 submission、node identities、已确认基线、检查点和恢复入口。对未知提交、待上传本地新增与不完整／不匹配回读先核对身份和内容；未解决时不得 `beginNewerCloudImport`，不得删除本地 Node 或清空 pending。必须同时覆盖直接 Space、Site 内嵌 Space、`resumeUpload`、显式同步与进入前恢复。权限撤销／退出／网络身份异常仍执行已有安全规则，不能因保留设备开放写入。
- [ ] **给重试一个完成出口。** 保留 500／超时的未知结果语义；一致回读可确认，明确支持的重试走现有上传与回执流程，失败继续保留。对持续歧义复用现有恢复选择，而不是永久停留在 prepared 前置失败；不未经选择覆盖合法云端修改。`resumeLocalUpload` 会清除 prepared 以允许重发，因此不能把保护仅绑定在 `submission != nil`：后续 dirty／新增相对确认基线的证据也须保留。无需为了绕过判断强制增加时间戳。
- [ ] **校验异常完整响应。** 对完整详情的明确数量矛盾记录结构化原因并阻止本次破坏性替换；数量只作为一致性信号，不能作为唯一成员权威或用来补造节点。针对历史计数滞后的兼容数据须保留正常入口测试，并将采用何种严格校验限制在此次批准的异常条件内。
- [ ] **错误展示与诊断保持真实。** 沿用 Space 云错误和恢复机制，失败不显示为同步完成。补充受 DEBUG 保护的 attempt、版本、回执阶段、节点数量、选择原因；不打印原始请求体或密钥。若新增用户文案，复用或同时补齐英文／简中 Key。

**最小状态成本：** 首轮复用已有回执、已确认实例基线和恢复文件，不新增持久状态或独立恢复系统。本轮方案不要求新增／修改数据库表、字段或 export JSON Key／类型／层级／默认值／语义，故没有新结构迁移。若实施发现必须持久化新的失败来源或引入服务器 revision，应先另列前后结构与例子，重新确认后才修改；不把它隐含在本方案内。

共享逻辑影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；当前没有已证实的 SDK／固件修改需求。

### B. 自动化与人工验收

确认方案并实施后：

1. 运行相关既有回归：`python3 scripts/check_space_recovery_receipts.py`、`SUNSMART_UPLOAD_FLOW=1 python3 scripts/check_space_recovery_receipts.py`、`python3 scripts/check_cloud_node_import.py`，按实际涉及的 Site 入口补最小关联回归。
2. 覆盖 500、超时但服务器实际成功、真正拒绝、重试失败再成功、旧响应迟到、账号／角色变化、退出重进及重启；回执、节点和确认版本均须验证。
3. 保留干净状态的同版本 Web 修改、合法空 Space、明确全部删除、较新云端完整导入、旧云端不能覆盖新本地、设备同地址不同身份保护，防止退回旧的同步死循环。
4. 一轮 Swift 修改完成后核对本地 SDK 映射，按项目规则构建 `SunSmartLocal.xcworkspace / SunSmart`，Debug、iphoneos、generic iOS、`CODE_SIGNING_ALLOWED=NO`。纯共享逻辑无品牌差异时先用代表 scheme，不使用 Simulator。
5. 用户真实设备最短验收：新增 L1/L2→模拟／触发上传失败→返回 Site→重进 Space→重启 App，预期两设备仍在且明确显示待同步／失败；服务器修复后重试→GET、退出重进均保留两节点，云同步状态才清除。另做正常 Web 同版本修改及合法清空的对照。

## 8. 当前已丢失数据的恢复安排

这份 09:37:34 导出仍包含两台节点的完整业务数据和原始本地记录，因此已有可评估的恢复来源。App 的 `beginNewerCloudImport` 还会在替换前制作 App／Mesh 两份数据库检查点并归档旧 generation；当前源码保留最近两代退休数据库备份，但手机上的实际文件是否仍在尚未检查。

建议先保留现有导出和 App 容器，不卸载 App、不急于复位并重新配网。恢复前核对同账号／区域／Space／网络身份、节点 UUID／地址及 Device Key 身份，优先评估该 Space 的完整一致恢复；不直接用共享数据库旧副本覆盖其他 Space 的后续修改。该文件是 DEBUG 检查导出，不能直接宣称可从普通分享导入入口无损导入；不得把含 `_debugInspection` 的整份文件直接 POST 给服务器。

恢复应在 App 保护及服务器问题受控后进行，否则恢复后的节点可能被同一空快照再次覆盖。本轮没有执行数据恢复，也没有操作真机。


## 9. 本轮实施：仅增加 App 等版本设备保护例外

授权：用户仅要求实施“本机存在未知上传结果或尚未确认的新增设备，远端同版本缺失这些实例时，不自动删除本地节点、清空回执或标记同步完成”。第 7 节其他修复暂不实施。基线 HEAD 仍为 `f53d4dca`；开始时仅本文档未跟踪。

### 范围与实现决定

- 已修改 `SpaceConfigurationSafety.swift`、`ImportData.swift` 两个共享生产文件。复用原回执、确认节点基线和只读导出，增加 `equalCloudNodeProtectionIssue` 检查；不新增数据库／export JSON／恢复文件字段，不修改 SDK、服务器、重试队列或恢复 UI，不执行数据恢复。
- 直接导入在完整云端选择之前返回 preserved；Site 内嵌 Space 经 `SpaceData.import → restoreConfiguration → update` 复用该入口。上传回读经 `importNewerCloudIfNeeded` 使用同一检查并返回未确认失败，不能走旧回执退休和确认完成。
- 未知提交使用 prepared／已有明确未知结果标记及提交实例；待上传但没有回执时比较当前实例与已确认节点基线，因此普通重试准备清除 prepared 后仍可保护新设备。实际已删除的本地节点不受旧回执强行保留。
- 对 accepted／verified 回执按现有成功语义使用其实例作为确认依据。旧记录没有节点基线时，只在从未确认过上传或实际创建时间晚于确认时间的情况下认定新增，不把缺字段直接解释为空基线。
- 比较 UUID、单播地址、Device Key 指纹和 Elements 集合，不依赖总数量；相同数量但替换实例也不能绕过保护。当前节点读取失败时不允许本次候选覆盖。
- 异步只读导出返回后复核账号／恢复 generation、完整回执状态、本地版本、确认版本及持久 Space 行。取消、期间新修改或确认完成使旧候选失效；访客／权限撤销仍沿原安全流程，密码事件仍生效。
- 原有较新／较旧云端策略、本地干净时的 Web 同版本修改及合法空配置保持原规则；只读检查不增加 HTTP 请求，不改变上传命令或重试次数。

### 执行记录与验证

- [x] 新增行为回归先失败：500 后收到同版本空详情时，旧生产入口返回 prepared，未阻止导入。
- [x] 加入共享保护后，定向场景通过，包括无回执、清除回执后、重开恢复、部分缺失、实例替换、旧记录及异步状态变化。
- [x] 生产上传流程用例覆盖 Space／Site POST 500 后再接收空详情，原始持久回执和两台设备均保留；既有成功／失败／部分批量保存行为通过。
- [x] Cloud Node 解码／导入门禁回归及本次服务器样本通过。
- [x] 完整回执回归与本次现场样本最终通过（exit 0）。本次现场样本的两台设备、原 prepared 回执和 dirty 状态保留，没有生成替换导入。
- [x] SunSmart generic iOS Debug 编译通过（`BUILD SUCCEEDED`，exit 0）。

最终验证命令：

```sh
python3 scripts/check_space_recovery_receipts.py --equal-cloud-sample '/Users/maginawin/Downloads/Space_Space 1_20261107_093734_912+0800.json' '/Users/maginawin/Desktop/server data.txt'
SUNSMART_UPLOAD_FLOW=1 python3 scripts/check_space_recovery_receipts.py
python3 scripts/check_cloud_node_import.py --snapshot '/Users/maginawin/Desktop/server data.txt'
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-timed-simple-261106-device-loss CODE_SIGNING_ALLOWED=NO build
git diff --check
```

构建解析到本地 SDK `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，SDK 工作区干净且本轮未修改。本轮仅共享 Swift 逻辑，没有品牌条件、资源归属、公开 SDK API 或依赖变化，因此使用 SunSmart 代表 scheme；未逐一构建其他品牌。回归脚本仍有既有精简网络枚举导致的 `default will never be executed` 警告，不影响通过。

旧测试的调整仅涉及两类：原先明确要求 prepared 缺失节点也被等版本覆盖的断言，改为保留；旧只测回执的夹具补齐实际存在的本地 Space 行，让新增异步复核读取真实模拟状态，而不是错误返回行不存在。没有删除成功确认、正常云端编辑或权限保护断言。

验证边界：回执与恢复状态使用实际文件序列化／重读；上传流程执行生产 Task、准备与回执处理，HTTP、App SQLite 和 SDK Mesh 对象是已有夹具边界。共享导入测试执行真实导入准备逻辑并断言在落库前退出；完整 Site UI→SQLite／SDK 持久化→真机重启仍需人工验收，不将离线赋值视为整 App 落库验证。

本轮最短人工验收：新增两设备→触发上传失败→退出并重进 Space→重启 App，预期设备仍在，仍提示待同步／失败；后续服务器返回完整同版本节点时可继续正常确认。既有已丢失设备不会由本修复自动恢复，服务器 500 也仍待后续处理。
