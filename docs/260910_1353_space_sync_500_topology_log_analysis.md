# Space 同步失败：拓扑修复、HTTP 500 与回读差异分析

> 后续结论更新：用户已确认请求缺少 Space netKey/appKey；容器与数据库核对进一步定位到同索引不同 Key 的导入跳过和导出静默缺字段。gzip 不再作为本案主因。详见 [密钥缺失分析与修复计划](260910_1413_space_export_missing_mesh_keys_analysis_plan.md)。下文保留初步排查时的证据边界。

分析日期：2026-09-10。依据：用户提供日志、当前 site-trigger-zone 工作区源码及相关 Git 变更。本轮仅分析和新增本文；未修改业务代码，未请求生产服务，未执行构建或真机测试。未保存原日志中的密码或 Mesh Key。

## 结论

最终同步失败的直接原因已经确定：`/srv2/sitespace/sync/spaceprops` 两次返回 HTTP 500，响应业务码为字符串 `9999`、消息为 `unknown error`。上传前本地导出均已达到 `repairs=0`，所以最后失败不再是本地拓扑导出被拦截。

此前确实另有数据问题：Group `C007`（49159，Group 2）的 Zone 和两个 Space Trigger Zone 引用了地址 `009F`（159），但该地址不属于预检解析出的该 Group 有效成员集合。App 因清理引用会删除配置而保留本地快照，要求审核修复。后续日志表明本地修复已应用，而服务器回读仍保留这些引用。

尚不能确定 HTTP 500 内部具体异常。源码显示 2026-09-08 提交 `3262505654a2d317a356b15ae11890adb8ef90d2` 新增真实请求体 gzip，且本次两个上传都经过压缩；应优先核查服务端请求解压兼容性。这是有代码依据的排查假设，不是已证明的根因。

## 现场链路

| 阶段 | 日志证据 | 判断 |
| --- | --- | --- |
| 查询 Site / Space | spaceInfo HTTP 200、businessCode=200，完成解码 | 云配置能够读取 |
| 首次导入 | invalidRemoteTopology；warnings=[]；hardErrors=[:]；repairs 三项 | 无硬错误不代表可无损导入，删除无效引用仍触发保护 |
| 进入 Space | entryTopologyNeedsReview | 本地拓扑也需要审核；不是新发生的 HTTP 错误 |
| 首次导出 | rejected unapplied topology repairs | 修复未应用，普通导出被拒绝，尚未上传 |
| 审核过程 | 导出 repairs=3，随后 repairs=0 | 与审核导出、应用本地引用修复、重新导出的代码路径一致；仅凭 tap 日志不能还原按钮文案 |
| 第一次上传 task=10 | gzip 3468 字节，HTTP 500 / 9999 | 已发送至服务端，得到错误响应 |
| 恢复回读 task=12～14 | phase=prepared；连续三次 mismatch，远端版本均为 1788515247 | 服务端未确认接受提交；读到的配置仍不匹配本地修复版本 |
| 第二次上传 task=15 | gzip 3393 字节，HTTP 500 / 9999 | 重试仍失败，日志结束前没有成功确认 |

目标 Space 为 `E335D681-CB9B-48C1-8A6F-223706D4E70D`，Site 为 `7FF83E38-E50E-4C2E-BBCB-68F5CDC2E50E`。其他两个 Space 的 `serverUpdateTimestampNotNewer` 是版本相同的跳过，不是本次故障。

## 拓扑问题的确切含义

三条 repair 为：

- `groupZone[49159:159]`：一个 Group Zone 移除无效的 159 引用。
- `spaceZone[49159:159]` 两次：两个 Space Zone 分别移除同一 Group / Device 引用，不是同一 Zone 重复成员诊断。

`ProximityLightingTopologyReconciler` 对 Group Zone 检查 `group.memberAddresses`；对 Space Zone 检查 Group 资格与成员关系。`ImportData.swift` 根据节点订阅、groupState、groupAddress 和规范化设备地址构建该集合。因此可以确认引用与有效成员集合不一致，但不能仅凭截断日志判定设备已被物理删除：可能涉及成员退出、迁移或其他历史状态，需要原始节点和变更记录。

`hasValidationIssues` 包含 `hasDestructiveRepairs`，不只检查 warnings / hardErrors。移除上述引用属于会删除配置的修复；当前存在可用本地快照时，导入策略选择保留而非静默覆盖。

`remoteNodes=2 localNodes=3` 不能直接解释为丢了一台真实设备。此处 localNodes 打印 MeshNetwork 全部 nodes 数量，而导出会过滤 provisioner、localProvisioner 和 isConfigComplete 节点，统计口径不同；差一项可能来自 provisioner，日志不能确认具体身份。

## 回读为何不匹配

提交 ID 为 `889FE42A-E5E9-4678-8055-036D359653FD`；提交及本地时间戳为 `1789019527`，回读仍为 `1788515247`。三个回读得到相同配置摘要：submittedSHA256=`3fe290a99d9c273e`，remoteSHA256=`6af7e844cadfee54`。

已打印差异：

- Group `C007` 第一个 Zone：提交 addresses 数量为 0，远端仍为 1，成员为 159。
- Trigger Zone 0：提交 2 个成员，远端 3 个成员；删除前置成员后，数组下标移动，产生多个字段 diff。
- Trigger Zone 1：提交 2 个成员，远端 3 个成员。

9 条字段 diff 不代表 9 个独立损坏点，和三处引用清理一致。双方均为 2 个节点，extra / missing RemoteNodes 均为 0；此轮主要可见差异在 Group Zone / Space Zone 引用，而非节点增减。

远端 `deviceCount=7` 与 nodes=2 不一致，是需要后端检查的摘要异常；它不参与当前逻辑配置比较，不能解释这次 canonical mismatch。当前 App 导出使用 nodeDicts.count 写 deviceCount。updateTimestamp 也不是 configurationData 比较字段，本次失败不是只因时间戳落后。

第一次上传失败后提交保持 `prepared` 符合实现：提交先持久化，再发 HTTP；成功响应后才标记 accepted。9999 不属于 rejectSubmission 会清除提交的明确权限/资源错误，因而保留用于恢复核验。三次回读后仍发生第二次上传，结合当前代码，与 prepared 提交的远端仍匹配授权基线、允许重新提交的分支一致；不能套用“永远卡在回读、根本没有上传”的旧问题结论。

回读只能证明读路径仍返回旧配置，不能排除后端部分写入或缓存未刷新；HTTP 500 也不能证明事务完全没有副作用。

## HTTP 500 的优先排查方向

### 1. 请求体 gzip 兼容性

`NetworkRequest.swift` 的 `HTTPBodyEncoding.prepare` 对 siteprops / spaceprops 上传、原始 Body >= 1024 字节执行 `gzipped(level: .bestSpeed)`，设置 Content-Encoding 为 gzip。当前分支没有服务端能力协商。

Git 变更确认该逻辑在 2026-09-08 的 `32625056` 新增，之前 requestClosure 不执行这一压缩。日志的 declaredContentEncodingGzip=true、actualBodyGzip=true 与当前实现吻合：不是之前“声明 gzip，实际普通 JSON”的表现。

如果服务器或代理仍直接把压缩字节当作 JSON 解析，就可能在进入业务处理之前失败。需要后端确认是否对该路由实际执行了解压，再解析 JSON。查询响应 Content-Encoding=gzip 只证明下载方向压缩，不能证明上传方向解压。

### 2. 解压后的业务解析、配置保存或数据库异常

如果后端已正确解压并解析，继续检查该次请求的字段验证、Group / Trigger Zone 更新、身份匹配、数据库约束、事务及缓存失效。请求包装来自 NetowrkReqeustApi：siteId、spaceId、spaces 数组、userId；Space Trigger Zones 当前上传位于 spaceData 中，响应兼容根级旧格式，需核对后端转换路径。

上传 Body 被日志省略，不能据此完成每个字段的后端契约验证；不能仅因 repairs=0 就断言全部上传字段都符合服务端要求。两次压缩字节数不同也不证明丢字段，可能来自快照内容、序列化或压缩结果变化。

### 建议取证顺序

1. 按上述 Site / Space 和提交时间关联后端两次 `/sync/spaceprops` 异常栈，确定失败在解压、JSON、业务或数据库哪一步。客户端 task=10/15 仅是本机任务编号。
2. 记录请求解压前后长度、JSON 解析结果和异常字段路径；摘要脱敏，不记录密码或 Mesh Key。
3. 若异常指向解压，在隔离测试环境或请求解析测试中，对同一份脱敏业务输入比较普通 JSON 与真实 gzip；不要直接对生产 Space 反复重放写请求。
4. 若解压正常，核对实际存储、回读投影与缓存，特别是 C007 / 009F 的三处引用、spaceData.triggerZones 和 deviceCount。
5. 修复后验收应同时满足上传成功与回读配置相等，随后再确认重新进入不会重复触发同一拓扑保护。不要仅清除 pending / blocked 标记或放宽比较制造成功状态。

## 其他日志

- UIScene lifecycle、空 App Group identifier、nw_connection、XPC 提示没有建立到本次上传 500 的因果链；应用随后完成多次 HTTP 请求及业务流程。
- 没有蓝牙配置发送失败或 Mesh ACK 超时证据，不能把本次云同步失败归因为设备离线。
- `businessCode=<missing>` 是日志字段提取问题：logger 用 `.int`，而错误响应的 code 是字符串。实际请求处理用 `.intValue`，CloudSync 已正确记录 9999，不是服务器没有业务码。
- 心跳响应 `{}` 被当前代码接受，但不证明配置写入成功。

## 源码索引

| 位置 | 作用 |
| --- | --- |
| SunSmart/Common/Data/ImportData.swift:168、223、1730 | destructive repairs 判定、远端成员集合、导入保护 |
| SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift:189、239、309、340 | repair 含义、删除性质、Group / Space Zone 引用检查 |
| SunSmart/Common/Data/ExportData.swift:384、437、479、942 | 节点过滤、未应用修复保护、Space 扩展序列化、deviceCount |
| SunSmart/Common/Network/NetworkRequest.swift:49、140、520 | 请求编码接入、业务响应处理、真实 gzip |
| SunSmart/Common/Network/NetowrkReqeustApi.swift:419 | Space 上传请求包装 |
| SunSmart/Common/Network/NetworkLoggerPlugin.swift:58 | businessCode 诊断提取 |
| SunSmart/Common/Cloud/CloudSynchronizationManager.swift:1016 | 提交持久化、HTTP 发送与 accepted 状态 |
| SunSmart/Common/Data/SpaceConfigurationSafety.swift:419、464、513 | 失败提交保留、恢复回读、基线匹配后的重提交出口 |
| SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift:140 | Group / memberships / Trigger Zone 逻辑比较 |

工作区原有 project.pbxproj 修改及两个未跟踪分析文档保持不变。本轮未进行运行验证；具体服务端根因仍需异常栈或隔离环境对照证据。
