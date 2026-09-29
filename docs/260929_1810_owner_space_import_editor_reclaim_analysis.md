# Owner 进入 Space 失败与 Editor 清除结果分析

日期：2026-09-29，Asia/Singapore。状态：分析方案已获用户确认，App 修复及自动化验证已完成；SDK、服务器数据和真机未操作。下文保留分析证据，文末记录实施结果与待验收项。

## 结论

1. 服务端仍确认当前用户是 Owner。本次恢复页提示不是 Owner 被撤权，而是 App 无法接受配置导入。提供的响应中有一个可确定复现的阻断点：`nodes[359]`、设备 `L438`、地址 `3E27` 的 `vid` 为 `""`，当前 SDK 的 Node 解码器要求非空的 4 位十六进制值，或字段缺失/null。App 将 Node 解码失败合并为 `configurationStagingFailed`，最终显示误导性的本机保存失败文案。
2. “清除所有 Editor 后仍能访问”是另一条问题链。当前响应仍含另一用户的 Editor 记录；批量清除代码确实存在跨 Space 错误更新本地成员，以及部分失败误报成功的缺陷。缺少当时清除接口的请求/回包和 Editor 端日志，不能断言现场发生了哪一种清除失败，也不能证明清除操作生成了空 `vid`。
3. 建议先修 App 的云端节点兼容及错误分类，再修 Editor 清除结果的 Space 维度处理和权威回读。保留配置完整性保护，不对 Owner 无条件跳过校验，不删除 L438，不把未知 VID 填成真实版本 `0000`。

## 输入与代码基线

- Xcode 日志：[xcode logs.txt](</Users/maginawin/Desktop/tmp/cannot enter llh/xcode logs.txt>)。
- 服务端响应：[get space props.txt](</Users/maginawin/Desktop/tmp/cannot enter llh/get space props.txt>)，2,995,812 字节，与日志的解压后响应大小一致。
- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-delete-devices-260928`，分支 `fix/delete-devices-260928`，HEAD `ee3b1c0a0d083d2b0eb26a91ebccb160c05e5c1c`。
- 初始仅有其他任务的未跟踪文档 `docs/260929_1758_space_lights_all_cooldown_plan.md`，未改动。
- 本地入口 `SunSmartLocal.xcworkspace` 存在；`.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，查询时工作树干净。
- 用户日志未记录 App/SDK revision，以下源码定位基于当前工作树；没有把当前 revision 当作现场二进制版本的证明。
- 样本包含密钥和身份信息，仓库只保存必要诊断结论，不复制原始响应或完整密钥。

## Owner 阻断的证据链

### 服务端权限成功，失败发生在客户端导入

目标 Space 为“兴东2”，ID `8B1E801A-C2CE-4205-8479-6311D49D0418`。

| 证据 | 结果 | 含义 |
| --- | --- | --- |
| HTTP 与业务结果 | HTTP 200，响应 `code=200`、`message=success` | 此次 GET 已成功 |
| 当前角色 | `data.role=owner`，`owner.userId` 与请求用户一致 | 没有将当前用户降级成 Editor/Visitor |
| Editor | 响应存在另一用户的 `editor` 对象 | 至少此 GET 快照仍报告有 Editor |
| 更新时间 | 云端 `1790673183`，本地 `1790670352` | 云端较新，当前导入决策会尝试覆盖配置 |
| 节点数量 | 云端与本地计数均为 368 | 计数相等不能证明所有节点可解码或是同一成员集合 |
| Group 数量 | 云端 22，其中 18 个普通组、4 个 `isVirtual=true` 的开关隐藏组 | 本地显示 18 与此一致，不是本轮组丢失证据 |
| 临近照明预检 | `schema=1 groups=18 spaceZones=1 repairs=0 maxNeighbors=2` | 此轮拓扑预检没有报告修复；不代表每个 Node 都经过完整解码 |
| 最后阶段 | `applyDecision` → `end` → `SpaceRecoveryViewController` | 进入更新分支后拒绝导入；没有 `applied` 或事务读回成功日志 |

进入链路为：

`SiteViewController.selectSpaceAction` → `loadSpaceReqeust` → GET `/sitespace/get/spaceprops` → `restoreConfiguration` → `SpaceData.update` → 导入结果 `.rejected` → `showSpaceRecovery`。

`loadSpaceReqeust` 对 `.rejected` 的处理不按 Owner 免除。Owner 身份授予业务权限，但不会使损坏/无法解码的配置变得可安全应用。因此不能通过放行 Owner 来修复数据兼容问题。

### 确认的异常节点与失败条件

异常定位（数组下标从 0 开始）：

| 属性 | 样本值 |
| --- | --- |
| JSON 路径 | `data.nodes[359].vid`，第 360 个节点 |
| name / unicastAddress | `L438` / `3E27` |
| uuid | `FFD1D5CC-D6A5-4FD6-802E-2A33295AD029` |
| vid | 空字符串 `""` |
| cid / pid | `0A78` / `2503` |
| crpl | `null` |
| groupState / groupAddress | `0` / 空字符串 |
| appKeys / elements | AppKey 列表为空；3 个 Element 的 models 均为空 |
| createdTimestamp | `1790672212`，2026-09-29 16:56:52 +08 |

这些字段符合尚未取得完整 Composition/配置资料的节点形态，但仅凭快照不能认定实际配网步骤、操作人或固件失败原因。`configComplete=false` 的项目业务含义也不能单独用来推导现场操作状态。

SDK `Node.init(from:)` 的 `versionIdentifier` 解码使用 `decodeIfPresent(String.self)`；空字符串是“存在的字符串”，随后 `UInt16(hex:)` 因不是 4 位十六进制而返回 nil，抛出：

`Version Identifier must be 4-character hexadecimal string.`

`crpl=null` 使用 `decodeIfPresent`，不会触发同一种错误。样本 368 个节点中，`cid`、`pid` 都有值，367 个 `vid` 有值，仅此节点的 `vid` 为空。

### 为什么前面预检通过，最后仍失败

`ProximityLightingImportPreflight.parse` 主要核对临近照明拓扑。对 `groupState=.none` 且没有普通组订阅的节点，代码会在 Node 解码之前 `continue`。L438 正好属于这种节点，因而可以出现“拓扑预检正常”。

随后 `SpaceData.update` 在配置暂存前要求 `nodeDicts.allSatisfy`：每个节点都必须成功解码并恢复 Scheduler 快照。L438 在这里失败。该 guard 同时包括 Group 数量完整性、Node 解码、Scheduler 恢复、清理凭证保存和 `beginImport`，任一失败都返回同一个 `configurationStagingFailed`。

`SpaceRecoveryViewController.message` 又将 `configurationStagingFailed` 与 `configurationPersistenceFailed` 都映射为 `space_recovery_storage_failed`。因此“无法保存到本机”不是本轮磁盘或 SQLite 故障的证据，而是错误分类过粗。

对于这一解码失败，guard 会短路，尚未进入当前配置替换事务，也不会由本轮调用执行 `beginImport`。此前的成员状态准备、Key 补齐及元数据保存仍可能发生，故不能把文案扩展解释成“整个 App 的所有本地状态完全没有变化”。

日志没有输出具体 rejectionReason/DecodingError，且未提供手机数据库和旧 pending-import。因此已确认的是：此响应在当前实现中有确定的直接阻断点，且与阶段日志相符；尚未实测该手机是否同时存在其他保存或旧恢复凭证问题。

### 空 VID 从哪里来，Editor 为何可能正常

当前 SDK 的 `Node.encode` 对未知 `versionIdentifier` 使用 `encodeIfPresent`；App 的两条 Node 导出路径从该编码结果构造云端对象，没有主动把 VID 填成空字符串。现有证据只能确定“GET 返回空 VID 与解码契约冲突”，不能确定是服务器缺省值转换、历史客户端上传，还是历史数据本身。需用 L438 的原始上传和服务器落库/序列化记录进一步区分。

Editor 即使仍能进入，也不推翻该问题：已在 Space 内的会话不必再次走这次导入；本地版本较新且无需更新的设备，也可能在解码所有 Node 前跳过配置替换。旧版本 App 的行为还可能不同。这些是代码允许的解释，现场具体原因需要 Editor 端进入日志确认。

## 清除 Editor 的独立问题链

### 已证实的客户端行为

- 单空间：`SharingSettingViewController.clearSpaceEditorRequest` 调用 `/sitespace/space/permis/reclaim`，传 `roleName=editor, force=false`。
- 批量：`ShareAuthorityViewController.clearSpacesEditorRequest` 调用 `/sitespace/site/permis/bulk/reclaim`，传目标 Space ID 列表和 `roleName=editor, force=false`。
- `4006` 被 App 解释为 `editorBeingUsedSpace`。当前产品流程允许正在使用中的 Editor 清除失败，Editor 流程没有 Visitor 那样的强制清除选项。不能把“清除所有”理解为无条件强制回收。
- 正常在线权限失效时，Space 页已有心跳错误处理：收到 `4009/noSpacePermission` 会停止心跳/相关监听，标记成员状态并退出。此样本没有 Editor 侧请求，不能证明服务器是否对它返回过撤权。

### 缺陷 A：成功结果丢失 Space 维度

服务端结果结构按代码契约是 `detail[spaceId][userId] = code`。实现先把所有成功的 userId 汇总为 `successEditorIds`，再遍历全部目标 Space，只要其 Editor 用户 ID 在列表内便清空。

| 模拟服务端结果 | 正确本地结果 | 当前代码结果 |
| --- | --- | --- |
| A/E = 200；B/E = 4006 | A 清除 E；B 保留 E | A、B 都清除 E |

同一个 Editor 管理多个 Space 时，一处成功会污染另一处失败的本地展示。它没有真正撤掉 B 的服务器权限；再次读取服务器元数据时，B 的 Editor 又可能出现。

### 缺陷 B：仅识别“正在使用”作为失败

批量回调的成功提示只取决于 `usedEditorIds` 是否为空。内层结果若为其他非 200 错误，或部分 Space 结果缺失，当前逻辑仍可能显示整体成功。`detail` 中空字典也被直接当作对应缓存 Editor 已清除，尚无本轮服务器契约证据证明空字典总表示这个含义。

隔离执行当前结果处理代码，输入 A/E=4009、B/E=4009 时，两处缓存仍有 E，但最终提示分支为 success。

### 能判断与不能判断的范围

提供的 GET 仍有 Editor 记录，与“权限尚未撤销或后来又加入”的状态相容。现有材料不能区分：当时正在使用返回 4006、其他错误误报、目标 Space 未被选中/漏回、服务器未实际撤权、旧分享重新加入，或服务端读回缓存滞后。

本轮没有直接证据将“清除 Editor”与 `vid=""` 建立因果关系。客户端清除请求只提交成员参数，不发送 Node 配置，也不直接修改 VID。

需要服务端/现场补齐的最短证据：当时批量 reclaim 的 Space 列表、顶层 code 和各 Space 的 detail；紧随其后的 Owner 成员回读；Editor 重新 GET/心跳返回码与时间。如回读声称已清除但 Editor 在线请求仍成功，再追服务器鉴权、会话/缓存和重新加入记录。

## 建议实施方案

### 1. 修复云端 Node 解码兼容，覆盖完整导入链

推荐在 App 的云端 Node 解码边界加入小范围兼容处理：把明确的 `vid=""` 视为“未知版本”，在传给 SDK 的临时解码对象中移除该字段，使其保持 nil。原始响应和已有恢复快照保留原值用于诊断。缺失/null 原本就应继续合法。

同步覆盖 `ImportData.swift` 的四个实际 Node 解码点：临近照明预检、Space 暂存前完整校验、Space 事务内导入，以及 `Node.import`（Site 网关导入使用）。共享入口保证 Site 整体导入、单 Space 进入、恢复重试、批量加入及 Space 页刷新一致。

复用选择：

- 直接复用现有 `Node.import` 不合适：它是带业务属性恢复/持久化后续流程的异步导入，不能让纯预检执行这些副作用。
- 扩展 `SpaceSyncCleanupPolicy.normalize` 不合适：该策略处理拓扑引用并生成修复凭证，未知 VID 不应变成拓扑变更或触发不必要上传；而且它不覆盖独立 Node/网关入口。
- 因此选择 `ImportData.swift` 内一个小型共享解码准备函数，复用已有 UUID 别名适配及 JSONDecoder。暂不改 SDK 通用 CDB 解码规则，不新增公共框架或依赖。

兼容边界：

- 允许缺失、null、精确空字符串及正常 4 位十六进制 VID；恢复未知值为 nil，不伪造版本。
- 非空非法 VID（如 `ZZZZ`）、类型错误继续拒绝，不把任意损坏输入都转换为 nil。
- 本次不把 `cid/pid/crpl` 等字段批量放宽为空。当前样本只有空 VID；其他字段扩大兼容需要对应契约/样本。
- 保留 L438 的 UUID、地址、Device Key、已知 PID、Element 占位及其他配置。不可用跳过此 Node、节点数降为 367或删除设备来绕过失败。
- 既有 pending-import 的重试也必须经过同一解码兼容点，不能要求用户清库、重建 Space 或删除恢复凭证。

服务器配套建议：确认未知 VID 的 API 表示为字段省略或 null，排查空字符串默认值和历史数据。App 兼容用于接纳存量响应；服务端永久修正可独立进行，当前无需新增 SDK API/发布依赖。原始上传缺失，暂不指定后台批量数据改写。

### 2. 将解码、暂存、落库错误分开，修正文案

拆开目前大型 guard 的错误原因：Node/Group 解码失败、Scheduler 恢复失败、备份/凭证保存失败、数据库事务或读回失败。DEBUG 中输出 Space、节点地址/索引、字段路径和错误类别；不打印密钥或整份节点 JSON，也不逐节点输出正常日志。

Node 解码失败应提示配置数据无法读取/需要恢复，只有实际保存失败才使用存储错误文案。Owner 当前没有 Leave 按钮（`showSpaceRecovery` 传入 `leave=nil`），文案却建议 leave；调整为与实际可执行操作一致的提示。沿用已有国际化机制，补 English 与简体中文。

失败仍保留旧配置与上传保护；修复后通过完整导入、持久化读回、finishImport 和 membership initialized 后再恢复编辑/上传。不新增绕过完整性校验的 Owner 特权。

### 3. 修复 Editor 回收结果并明确未完成状态

批量结果按 `(spaceId, editorId)` 逐项应用，不跨 Space 汇总用户 ID 后回写。仅对该 Space 的明确成功证据清理对应旧 Editor；明确失败或结果未知保留其成员信息，并显示失败/待确认。任何非 200、漏回、非法结构都不能显示整体成功；空字典语义应结合服务器契约或成员回读确认。

利用已有成员查询能力（`.spaceMembers`，现用于成员列表）回读目标 Space，单空间与批量清除都应使本地展示与权威成员结果收敛。回读失败标记“待确认”，不能假称清除全部成功，也不据此擅自重发回收。成员回读只更新明确返回的权限字段，不能把不含设备配置的成员响应送入全量 Space 配置导入。

异步回调检查当前账户/区域、Site/Space 及操作开始时的 Editor 身份；操作期间出现新 Editor、页面退出或重试晚回包时，不得清掉新成员。重进后通过成员回读纠正旧版本留下的错误缓存，不通过本地 nil 推断服务器已撤权。

保持 `force=false` 的现行语义。若产品希望“清除所有”连正在使用的人也强制下线，需另行明确服务端支持、在线会话/离线控制的边界，不在本修复中静默改为强制请求。

Visitor 批量清除也发现相同的跨 Space 用户 ID 聚合写法，且当前每个 Space 仅删除匹配到的第一个 Visitor。这是相关但独立的缺陷：本次 Editor 修复避免复制该实现；Visitor 的行为修复单独列项，不自动扩大本轮实施范围。

## 验证与验收边界

### 分析阶段已执行

1. 解析原始文件核对响应大小、角色、当前用户匹配、计数、异常节点字段；未向服务器发起请求。
2. 临时 Swift 探针直接提取当前 SDK 的可选 `cid/pid/vid/crpl` 解码块及 `UInt16(hex:)` 实现，扫描样本：368 个节点中 367 通过，L438 的 `vid` 失败。相同节点用 VID 缺失/null 可通过此字段探针，`0003` 可通过，空字符串和 `ZZZZ` 被拒绝。
3. 临时 Swift 探针直接提取批量 Editor 结果处理代码，用模拟 Space/保存边界复现跨 Space 误清缓存及非 4006 错误误报成功。

以上是分析阶段的定向字段和结果处理复现，不是完整 Node 解码/完整 App 导入、SQLite 保存、真实服务器撤权或设备运行验收。临时探针位于临时目录并已由上下文清理；未新增测试工程。分析阶段未进行 App 构建、真机操作或全量回归；确认后的实施验证见下文。

### 实施后必要验证

| 范围 | 最小验证及预期 |
| --- | --- |
| Node 兼容 | 原 SDK 解码契约与 App 兼容入口联动；覆盖缺失/null/空/有效/非法非空/错误类型，保留未知为 nil |
| 完整 Space 导入 | 脱敏样本包含 368 节点、18 普通组、4 隐藏组、5 场景、5 日程、2 开关、1 Space Zone；L438 不丢失，正常提交及读回 |
| 其他入口 | Site 导入、单 Space 进入/重试、Space 页刷新、Node/网关入口对相同 VID 表示结果一致 |
| 失败与恢复 | 其他节点真正损坏、暂存写失败、事务失败时保留旧配置及保护；pending-import 重试、退出重进和重启恢复一致；不能因兼容处理创建新的永久阻断 |
| Editor 回收 | 同 Editor 跨两个 Space 的全成功/部分 4006/其他错误/漏回/空字典/回读失败，缓存与提示逐 Space 正确 |
| 异步权限 | 重试晚回包、回读时 Editor 已更换、账户切换；旧结果不清除新 Editor |
| 真实验收 | Owner 更新后在线进入“兴东2”；Owner 清除 Editor 后，Owner 回读成员及 Editor 再次进入/心跳均符合服务器结果 |

优先扩展已有 `check_proximity_scoped_import.py`、`check_space_membership_lifecycle.py`、`check_space_recovery_receipts.py` 的相应覆盖。它们存在 SDK/存储替身边界，不能只依赖过于宽松的 Mock Node 来验证 VID；应新增直接覆盖生产解码字段/适配的回归。实际涉及事务行为时才追加 `check_configuration_database_safety.sh` 的定向验证。

共享逻辑影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。实施完成后使用已确认映射的 `SunSmartLocal.xcworkspace`，先做一次代表性 SunSmart Debug generic iOS 编译。若新增源文件/本地化资源归属或 target 配置存在跨品牌风险，合入前按项目规则补所有受影响品牌；不自动操作真机。

## 确认后实施结果

### 已完成的 App 改动

- `ImportData.swift`：新增小范围 `CloudNodeImport` 解码适配，将精确空 VID 从临时解码对象移除，保留未知为 nil；原始响应、待恢复快照和其他身份字段不变。四个 Node 解码点全部使用同一入口。非空非法值、错误类型及其他字段仍按 SDK 原契约拒绝。
- Space 暂存前完整校验分别返回 Node 解码、Group 解码、Scheduler 恢复、参考数据暂存、导入暂存失败；配置事务成功后的 finishImport 失败另归类为恢复收尾失败。新增 DEBUG 日志只输出字段路径、错误类型和定位信息，不打印载荷值或完整密钥。
- `SpaceRecoveryViewController.swift` 与共享中英文本：数据无法读取不再误报本机存储失败；恢复收尾失败不声称旧配置仍是当前配置；通用恢复文案不再要求 Owner 执行不存在的 Leave 操作。按钮和权限保护保持原有机制。
- `BatchSpaceData.swift`：放置专项 `SpaceEditorReclaim`，由单空间和批量清除共同调用；按 Space/Editor 解析结果，先回读成员，再更新本地 Editor。成员接口缺字段或不能确认时，最多补一次完整 Owner Space GET，只读其中成员元数据，不触发 Mesh 导入。
- 不完整成员响应缺少 `editor` 不视为清除；完整、身份匹配且角色为 Owner 的 Space GET 则沿用现有导入规则，将未返回 Editor 视为无 Editor。显式 null/空对象可表示无 Editor；损坏的非空 Editor 对象不清空缓存。
- 只有成员回读确认无 Editor，且没有明确回收错误，才报告清除成功；缺失/空 detail 可由权威回读解决，回读失败则保留缓存并提示待确认。明确 4006 或其他非 200 不显示全成功。权威回读若已有新 Editor，会保留新 Editor 并提示未确认全部清除。
- 异步操作同时核对账户/区域及 membership epoch、Space、角色、退出状态、操作开始时内存及数据库中的 Editor ID、同 Space 的操作 generation。旧回包不覆盖新 Editor；保存使用刚加载的最新 Space 行，避免把其他配置改回旧值。本地保存失败不提前更改页面对象。页面离开后不弹过期结果提示。
- 两个清除入口均防止重复点击；保留 `force=false`，不改服务器 API、SDK 或权限强制回收语义。Visitor 的独立问题未纳入实施。

### 已执行的验证

| 检查 | 结果与边界 |
| --- | --- |
| `python3 scripts/check_cloud_node_import.py --snapshot <用户原始响应文件>` | 通过。直接使用实际 SDK 可选标识字段解码代码及 App 的共享适配、暂存前 guard。原始空 VID 先复现失败，适配后 368 个节点通过这一字段/暂存边界检查；同时覆盖非法值、Group/Scheduler 错误分类、暂存失败及重试。其他 Node 字段、Scheduler 实体和存储是明确替身，不代表完整 App 事务验收。 |
| `python3 scripts/check_space_editor_reclaim.py` | 通过。生产清除协调方法在隔离 HTTP/数据库边界下验证同 Editor 跨 Space 部分成功、非 4006 错误、漏回/空/非法 detail、读回失败与补读、成员替换、账户/区域/epoch/角色变化、退出、保存失败、重试晚回包、取消及单空间入口。 |
| `python3 scripts/check_proximity_scoped_import.py` | 通过。原有导入/拓扑/删除/恢复与 Site 归属执行回归，测试 runner 接入共享 Node 解码适配。 |
| `python3 scripts/check_space_membership_lifecycle.py` | 通过。成员身份、恢复准备、上传阻断、失败/晚回包/退出重试等原有隔离回归。 |
| `python3 scripts/check_space_recovery_receipts.py` | 通过。恢复凭证、版本/权限、失败/重试、清理凭证和导入准备回归；有既有测试替身中不可达 default 的编译警告。 |
| 五品牌项目引用核对 | 通过。SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均引用本次修改的共享 Swift 文件及同一 English/简体中文资源。没有新增生产文件、资源文件或 target 配置，不产生新的 target 归属差异。 |
| 本地化格式及差异检查 | 中英文本 `plutil -lint`、`git diff --check` 通过。 |
| SunSmart Debug generic iOS 编译 | `SunSmartLocal.xcworkspace`、`SunSmart` scheme、`-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`，结果 `BUILD SUCCEEDED`。DerivedData 为工作树稳定目录 `SunSmart-fix-delete-devices-260928`。这是编译结果，不是手机运行结果。 |

SDK 仍为上文记录的 one-dev revision，工作树无改动；未引入新 SDK API，无本次 SDK 发布待办。正式工程、依赖锁文件和其他任务的文档未修改；Git 未提交。

### 尚待真实运行验收

1. Owner 使用此分支构建，在线进入“兴东2”（若在恢复页则点击 Retry）。预期不再因 L438 空 VID 进入存储错误页；设备总数 368、18 个普通组及既有场景/日程/开关/Trigger Zone 保留。退出重进，再启动 App 后重复确认。
2. 对同一 Editor 管理的两个 Space 批量清除：一个可清除，一个处于正在使用状态。预期仅确认清除的空间不再显示 Editor；失败空间仍保留 Editor，提示部分无法清除。单空间清除也需要回读确认后才提示成功。
3. 清除期间断网，或请求结果不能确认：预期保留成员信息并提示待确认；恢复网络后重新查看成员，不能仅凭之前的成功提示判断已撤权。操作期间换号/成员变化或旧回包晚到时，不清除新成员。
4. 服务器已确认清除后，用原 Editor 账号重新在线进入或等待心跳，应收到对应权限结果。当前客户端请求不是强制踢人，4006 应按未清除处理；离线 BLE 能否继续控制及分享重新加入属于服务器/产品契约范围，本轮未改动。

若仍失败，保留 `[SpaceImportDecode]`、`[SpaceImport]`、`[SpaceEditorReclaim]` 的 DEBUG 记录及相关接口业务结果即可定位阶段，不需要输出完整密钥。原清除操作的真实回包和 Editor 日志仍缺失，不能把本轮客户端回归视为历史现场撤权原因已经唯一确定。
