# 空间 1 持续云同步失败：现场对账与收敛方案

日期：2026-09-23。工作树 `fix`，初次分析时 HEAD `60ddbd0c`、工作树干净。最初分析只读取三份用户现场文件和当前代码；随后按文末确认方案实施 App 修复。未发送服务器写请求、未操作真机。原始文件含 Mesh 密钥；本文不记录密钥值。

## 结论与证据等级

1. **直接失败已确认。** 两次手动 Space 同步都发出 `POST /sitespace/sync/spaceprops`，服务端均返回 HTTP 500、业务码字符串 `9999`、`unknown error`。没有成功响应，也没有新版回读。请求正文被日志省略，所以无法从这段日志确定服务端抛错的具体字段或代码位置。
2. **App 放行不完整配置已确认。** 15:59 的调试导出可生成 Space 比较快照，但该快照没有 `netKey`、`appKey`、`appKeyIndex`；原始记录标记 `networkConfigurationUnavailable=true`。当前 `SpaceData.export` 找不到匹配的 NetworkKey/ApplicationKey 时直接跳过这些字段，`prepareSubmission` 只检查版本、UUID、`nodes` 和配置投影，因此这种全量 Space 仍可发往服务器。导出时间晚于两次请求；日志没有原始请求 JSON，不能证明两次请求的具体字段逐字相同，但同一 Space、同一提交时间戳及相同本地状态使此问题高度相关。
3. **服务器现有快照也不一致。** `/get/spaceprops` 返回 `nodes=[]`，却返回 `deviceCount=3`；Group `C000` 的 Path/Zone 还引用地址 65、77、86、89。本地导出为 `nodes=[]`、`deviceCount=0`，没有该 Group Path。服务端数据为何形成这种状态，需要服务端写入、缓存和历史请求记录，不能仅由当前 GET 判断。
4. **持续提示的原因已确认。** 本地 `lastUpdateTimestamp=1789889269`，`lastUploadCloudTimestamp=1787128216`，本地记录了 `syncCloudError=9999`。`SpaceData.needUploadCloud` 和 `showSyncCloudError` 因而持续提示。HTTP 500 被视为可能已写入的未知结果，提交回执保留；下次重试先读旧云端三次，均不匹配，再发送同样条件的上传，第二次仍 500。

**对 500 的判断边界：**缺 Key 是最具体的 App 请求缺陷和首要服务端排查方向，但未取得解压后的实际请求体和服务端异常栈，不能宣称它已经被证明是此次 HTTP 500 的唯一触发字段。先前在中国大陆服务完成过真实 gzip 上传及新版回读；本日志也显示请求头与压缩字节一致，不能仅因 `Content-Encoding:gzip` 就归因于压缩。若服务端入口日志显示解压错误，再单独修传输契约。

## 三份文件对账

| 项目 | 进入/同步日志 | 服务器 GET | App 调试导出 |
| --- | --- | --- | --- |
| Space | 同一 Site/Space，`syncSpace` | `空间 1` | `空间 1` |
| 版本 | prepared 提交 `1789889269`；远端回读 `1787128216` | `1787128216` | `1789889269` |
| Node / 数量 | 提交与远端 Node 都为 0，远端 `deviceCount=3` | `nodes=[]`、`deviceCount=3` | `nodes=[]`、`deviceCount=0` |
| Key | 上传 body 不在日志中 | 有 `netKey`、`appKey` | 两者及 `appKeyIndex` 均缺失；rawLocal 提示网络配置不可用 |
| Group Path | 回读差异显示本地缺失、云端存在 | `C000` 有 Path/Zone | `C000` 无 Path/Zone |
| 新字段 | 回读差异显示本地有两个 Profile 默认值和空 `triggerZones` | 两个 Profile 字段缺失，`spaceData={}` | 两组 Profile 均有 `calibrationMode=none`、`targetNightBrightness=50`；`spaceData.triggerZones=[]` |
| 上传 | 两次 `gzip` POST，均 HTTP 500/`9999` | 只说明旧版仍可读 | `_debugInspection.uploadable=false` 是调试导出的固定标记，不表示业务上传被拒绝 |

日志中最初的 `cleanupPreparation/-2004 reason=none` 是另一个准备失败信号；后续手动请求确实通过准备并发出 HTTP，不应把该行当作本次两次 500 的直接失败点。`preserved pending local deletion/recovery` 表示本地待处理状态受保护，不能据此推断又发生了一次删除。

回读的六条差异只能解释提交与云端尚未收敛，不能解释服务端为什么抛 500。正式提交比较只投影 Group 配置、Node 成员和 Zone，不比较 NetworkKey/AppKey，因此当前日志的差异诊断也没有报告缺 Key。

## 当前调用链的具体缺口

- `SpaceViewController.syncSpace` 入队 `.syncSpace`；`CloudSynchronizationManager` 先进行清理、恢复回执，再调用 `space.export(purpose:.cloudSync)`、持久化 prepared 提交并发送 `spaceUpload`。
- `SpaceData.export` 从当前子网寻找 NetworkKey，再找绑定的 ApplicationKey；两个 JSON 字段都是条件写入，缺失不会让导出失败。`DebugCloudJSONRecords` 用另一次 NetworkKey 读取给出 `networkConfigurationUnavailable`，与最终 JSON 缺 Key 相互印证。
- `SpaceConfigurationSafety.prepareSubmission` 对待上传快照没有 Key 完整性门槛；`SpaceConfigurationIntegrityPolicy.configurationData` 也有意只比较逻辑配置，而非网络身份。安全恢复分支 `upgradeRecoveryConfiguration` 已要求两种 Key，却没有覆盖普通上传。
- 服务端返回 500 后，`rejectSubmission` 保留未知结果的 prepared 回执。此保护可避免把已成功但响应丢失的写入误判为失败；然而当前三次回读加再次发送，对稳定拒绝且缺少可定位错误的情形增加等待和重复请求。

## Key 为何不可用、何时引入、是否已修复（后续追查）

**现场能确认的边界。**服务器的 NetKey 通过 Bluetooth Mesh K3 派生出的 Network ID 与 App 原始 `spaces.subNetworkKey` 一致，服务器的 AppKey 也绑定同一 NetKey 索引。因此这不是“服务器 Key 与本地记录的子网 ID 原本就不匹配”。App 调试导出的比较快照同时缺 `netKey`、`appKey`、`appKeyIndex`，另一条读取路径标记 `networkConfigurationUnavailable=true`。SDK 的 `MeshNetwork.load(meshUUID:subnetworkId:)` 在过滤节点/组之前，从同一 Site 级 `meshNetwork` 行解码完整 `networkKeys`/`applicationKeys`；`subnetworkId` 本身不会过滤 Key。能确定的是 **2026-09-23 15:59 左右 App 从本地 MeshNetwork 读不到与该 Space ID 匹配的 NetKey**，从而也无法导出绑定的 AppKey。当前 JSON 未包含 `meshNetwork` 原始 Key 列，仍不能区分“数据库里已没有该项”“列无法完整解码”与“另一个 Key 占用该索引”，更不能确定第一次丢失发生在哪次操作。

**Site Owner 转给服务器/Web 再转回同一 App，是一个与现场高度吻合的具体丢 Key 路径。**前提是这部 App 在转出后刷新过 Site 列表，收到 `OwnerTransfer` 事件并把原 Site 保留为 `.waitDeleted`，且用户没有先清掉本地缓存。接收转回的 Site 时，`SharePermissionSelectionController.receiveSiteRequest` 调用 `SiteData.import`；对于已有的 `.waitDeleted` Site，`SiteData.import` 设置 `initialize=true`。接着 `SiteData.update` **即使已经加载到本地 MeshNetwork**，仍因 `initialize` 调用 SDK `MeshNetworkManager.createMeshNetwork`，只带入服务器返回的 Site 主 NetKey/AppKey。SDK 对相同 `meshUUID` 的 `MeshNetwork.save(allData:true)` 用 `insert or replace` 覆写 Site 级 MeshNetwork 行里的**整个** NetKey/AppKey 数组；它不会因此删除原子网 Group/Scene 表，所以能够形成“Space 行和 8 个 Group/4 个 Scene 仍在、子网 Key 不见了”的现场组合。这是 App 本地重建覆写路径，不要求服务器先丢 Key；服务器 GET 仍有该 Space Key 与之相符。

随后 Site 导入各 Space 时，已有的 `SpaceData` 行使 `SpaceData.import` 的 `initialize` 仍为 `false`，不会随 Site 重新初始化。当前日志里该 Space 又命中待提交状态保护，`SpaceData.update` 在补子网 Key 之前返回；即使没有待提交状态，2026-09-16 后远端版本较旧且本地仍需上传时，也可能跳过导入。因而 Site 主网络被重建后，服务器返回的 Space Key 不一定能写回本地。这条链路由当前源码逐段成立，但**本次三份文件没有转出/转回请求和 `.waitDeleted` 进入记录**，不能断言这部手机已经实际走过。若转回前这部 App 没有把 Site 标为 `.waitDeleted`，此特定重建路径就不会由转移直接触发。核实需要同一手机的 Site 列表 `OwnerTransfer` 事件、接收 Site 响应及其 `spaces` 字段、转回前后 MeshNetwork 的脱敏 Key 索引/Network ID 摘要。

SDK 中有两类能够造成或固化这种状态的机制，但这三份材料没有命中它们的操作证据：`removeSubnetwork` 会先从内存数组移除 AppKey/NetKey，再删除子网 Node/Group/Scene，最后保存；App 的 `SpaceData.delete` 是其调用者。现场原始 Mesh 表仍有该子网的 8 条 Group、4 条 Scene，因此不能把它解释成一次**完整成功**的子网删除；若曾执行删除，需要查部分失败或后续重建。SDK 子网删除未检查 Node/Group/Scene 各表删除结果，使部分失败值得核对。`MeshNetwork.save()` 会把**整组** Key 数组以 `insert or replace` 写回 Site 级行；`load()` 对任一 Key 数组解码失败时保持空数组，且加载过程中还可能因补记已使用地址调用 `save()`。这意味着解码异常或持有过期/不完整网络对象的写入有抹掉 Key 的风险；它们是待验证的候选路径，不能写成现场已证实根因。应先备份并只读检查手机 Mesh 数据库该 Site 的 `netKeys`/`appKeys` 原始列是否存在、是否可解码、索引与 Network ID，连同当时的删除/恢复记录和历史 App 日志定位第一笔变化；不在普通 DEBUG 日志打印密钥值。

**代码引入时间可以分层确定，数据丢失时间不能。**

| 缺口 | Git 证据 | 与这次现场的关系 |
| --- | --- | --- |
| Space 导出找不到 Key 时静默省略字段 | `14f727f4e`，2024-06-21；按 Network ID 选择 NetKey 的代码为 `e841e42c1`，2024-12-16 | 已确认存在于当前代码，直接产出缺 Key JSON；并非 2026-09 新引入 |
| 已转让的 Site 转回时强制重建同 UUID MeshNetwork | `e841e42c1`，2024-12-16，增加 `.waitDeleted -> initialize=true` 与 `meshNetwork == nil || initialize` | 这是目前找到的最直接 Key 覆写候选；若现场确有同机转出/转回并先标记 `.waitDeleted`，可解释保留 Group/Scene 却缺子网 Key |
| 导入仅当 NetKey **索引不存在**时同时补 NetKey/AppKey | `23b4bbba9`，2024-09-20 | 对“NetKey 在但 AppKey 丢失”或“同索引不同 NetKey”无法恢复；保存结果也未检查 |
| 待上传/恢复时进入 Space 先保护本地、跳过云端导入 | `abfbe5a71`，2026-09-07 | 本次日志明确命中该分支；这一分支保护待上传本地变更，但也不会单独补 Key |
| prepared 提交只检查 UUID、版本、`nodes` 和逻辑配置，不检查 Key | `abfbe5a71`，2026-09-07 | 本次上传能够发出，说明现有门槛未拦下该类不完整快照；实际 POST body 未留存，不能逐字证明它与稍后导出相同 |
| 原先位于云端版本判断之前的缺子网 Key 补齐分支被移除 | `0970b93b`，2026-09-16 | 对**没有本地待处理状态**且远端版本较旧的缺 Key Space，恢复机会减少；但本次先命中 9 月 7 日的保护分支，不能将 9 月 16 日提交认作本次丢 Key 的直接原因 |

2026-09-21 的 `0b9d748d` 修的是升级同步/回读兼容，没有增加上传 Key 完整性校验；当前 HEAD `60ddbd0c` 的导出、提交预检、导入分支仍是上述行为。本地 SDK HEAD `ebbe1c9` 的 `load/save/removeSubnetwork` 也仍有上述语义。因此**这次表现出来的“本地 Key 不可用 + 不完整整包继续上传 + 待提交状态下不恢复”尚未修复**。至于最初使 Key 不可用的那一笔写入，现有文件不能定责或给出引入提交；仅凭服务器 2026-08-19 版本有 Key，只能证明服务器保有旧值，不能反推手机在该时刻之后何时丢失。

下一次修复需分两步：先让所有整包上传在统一入口拒绝缺失/索引绑定错误的 Key 并给出明确本地错误；再根据原始数据库和恢复记录决定当前 Space 能否安全补齐 Key。若云端 Key 与本地子网身份一致但本地有同索引不同值或待提交的其他真实配置差异，保持人工核对，不能用 GET 覆盖本地待上传数据。对 SDK 的解码失败与整列覆写路径增加失败保护和最小故障注入，追踪第一笔让 Key 数组从完整变为不完整的写入。

## 修复方案，按最小完整链实施

### 1. 先查清当前 Space 的本地 Key 和服务端异常

- 服务端按两次 `/sync/spaceprops` 的时间、Site/Space 标识查请求 ID、解压后的 envelope 字段清单、异常类型及栈、事务是否开始/回滚。只在受控诊断中检查 Key **是否存在及索引/绑定关系**，不输出 Key 值；明确区分请求解析、业务校验、持久化与响应阶段。将 `9999` 改为带请求 ID、字段路径和稳定错误码的 4xx/5xx，不向客户端回显敏感值。
- App/SDK 侧定向检查该 Space 的 `subNetworkKey` 是否能在 Site MeshNetwork 中找到对应 NetworkKey，以及绑定 AppKey；确认是本地 Key 真丢失、子网 ID 错配，还是两种读取 API 的行为不同。只读核对并保留原始数据库/恢复状态。服务器旧快照已有 `deviceCount`/Path 不一致，不能直接覆盖手机本地数据。

### 2. 堵住 App 的不完整整包上传

- 在一个共享的 Space 快照校验入口要求同一 Site/Space 身份、`nodes`/Group 等必需结构、NetworkKey 和绑定的 AppKey 都完整，且 NetKey 索引、AppKey `boundNetKey`、本地子网 ID 关系一致。`syncSpace`、`syncSite` 嵌套 Space、首次上传和解绑前上传共用这一入口；导出失败时给出可定位的本地错误，保留 dirty 状态与提交回执，不发送请求。
- 不能把远端 Key 直接补进本地或把空字段解释为删除 Key。只有身份关系、来源与版本可核对且用户确认采用哪份配置时才做受控恢复；缺失或不一致时保留人工核对。Profile 旧格式默认值可做有限规范化，Key 身份和真实 Path/Node 差异不可放宽。
- 精简诊断：记录 `stage`、失败字段路径、Space/version、请求 ID、压缩状态与正文摘要，禁止完整 Key/凭据/请求体日志。错误展示区分“本地配置不完整”“服务器拒绝”“结果待确认”，避免一律显示通用未知错误。

### 3. 让服务端和 App 对全量快照有同一合同

- 服务端统一 `/sync/spaceprops`、`/sync/siteprops` 内嵌 Space 与 `/get/spaceprops` 的字段校验、写入和回读映射。缺必需 Key 或 Key 关系不一致应在写入前以明确 4xx 拒绝；不能抛 `9999`，也不能部分更新。
- `nodes=[]` 与字段缺失分开处理；`deviceCount`、Node 成员及 Path/Zone 引用必须来自同一提交版本。对当前云端 `nodes=0/deviceCount=3` 的历史状态先查来源，再决定如何修复，不凭数量字段或单次 GET 自动清理。
- 对 5xx/超时保留未知结果回读，但按提交 ID/版本作有界确认；若回读仍是已确认旧版且请求被明确拒绝，允许重新生成一次提交。稳定失败应停止盲目重复同一无效整包并暴露可操作原因。

### 4. 必要验收

- 使用脱敏旧格式、缺 NetKey、缺 AppKey、Key 绑定错误、有效空 Node、旧云端残留数量/Path、HTTP 500 未知结果、明确 4xx 拒绝、超时后服务器已提交等夹具，验证不会丢本地配置，也不会错误清除“需要同步”。测试真实生产导出/提交路径，不只检查比较函数或源码文本。
- 用受控测试 Space 分别经两个上传接口提交有效整包，再 GET 验证版本、Key 关系、Node/`deviceCount`、Group Path/Zone 和新字段。自动测试/编译通过不等于当前手机、服务端和 Mesh 验收；当前 Space 的恢复要先完成上面的 Key 与服务器异常核对。

## 对近期反复失败的判断

接口数量确实少，但每次传的是 Space 全量配置，来源跨 App SQLite、SDK Mesh 数据、恢复回执、服务端数据库/缓存，任何一层把“缺字段”“空值”“已确认版本”混为一谈都会形成持续失败。近期案例分别出现过 gzip 接收不兼容、旧格式比较误判、旧 SQLite 表清理不收敛、服务器空 Node 回读不一致；它们不应被当作一个原因反复打补丁。当前最该收敛的是**单一上传快照合同、单一预检入口、明确错误码和一次端到端写入回读验收**，删减重复的失败分支与无结论重试，而非继续给 UI 叠加恢复路径。

## 2026-09-23 待确认实施方案：仅修复 Space Key 丢失

### 范围与决策

本次只处理 Site 转回引起的子网 Key 覆写、Space NetKey/AppKey 缺失后的安全补齐，以及防止不完整 Key 进入现有整包同步。不改 Node、Group、Path/Zone 的业务合并规则，不新增通用同步框架。NetKey 与绑定的 AppKey 是一组；只恢复一边缺失的字段，不改变两边已有但不相同的 Key。服务器当前样本有完整 Key、本地缺 Key；不能把“服务器缺 Key”当作当前 Space 的恢复方向。

| 两侧状态 | 建议动作 |
| --- | --- |
| 都完整且相同 | 维持现有同步，不因 Key 建任务 |
| 本地缺部分或全部，服务器完整 | 仅在认证响应的 Site/Space、账号/角色/成员状态、NetKey 派生 Network ID、索引及 AppKey 绑定均与持久化 Space 身份一致，且本地没有同索引不同值时，补缺字段到本地 MeshNetwork，检查保存和重新读取；保留本地配置、时间戳、待上传与删除回执，再让原同步任务继续 |
| 服务器缺部分或全部，本地完整 | 只接受 Owner 的完整权威 GET，排除权限裁剪、摘要响应和暂时不可读；本地 Key 派生 ID 与持久化 Space 身份一致，服务器已有的另一种 Key 不冲突，且非 Key 配置经现有版本/兼容比较确认可安全整包上传时，生成现有 `.syncSpace` 任务，成功后 GET 核对 Key 和配置。服务器无独立网络身份字段时，以已持久化的 Space ID 和可用的既往确认快照校验；证据不足则人工核对 |
| 任一侧有同索引不同值、Key Refresh 冲突、身份不可证，或两侧都缺 | 保留原数据及回执，阻止自动覆盖和上传，提示配置核对 |

Key 解析应检查 128 bit 长度、NetKey/AppKey 有效索引、`boundNetKey`、NetKey K3 Network ID 与 `meshNetworkId`；对本地已有其他 Space 的同索引 Key 不得覆写。补 Key 是身份恢复，不借此导入旧服务器整份 Space、降低版本或清除本地待上传改动。

### 最小代码落点

1. **先堵生成缺 Key 的入口。**`SiteData.import/update` 对 `.waitDeleted` Site 转回时，若相同 `meshUUID` 的本地 MeshNetwork 已存在，保留所有子网 Key，仅在 Site 主 Key 身份一致时更新主网络与 Provisioner/地址；本地网络不存在才新建。主 Key 冲突、保存/回读失败则停止接收并保留原始本地数据，不显示成功。Site 的“需重新分配手机地址”与“需重建全部 MeshNetwork”不再共用一个 `initialize` 判断。
2. **在 Space 导入的版本/本地变更保护判断之前做 Key 专项核对。**复用已认证、完整的 Space 响应，处理“本地缺、云端完整”；只写 Mesh Key，不让普通 GET 越过 `preservesLocalChanges` 导入旧配置。保存前按 `meshUUID` 重新读取当前 Key 数组并串行补缺，防止多个 Space 导入使用旧网络对象相互覆写；保存后重新读取确认。对“云端缺、本地完整”返回受保护的修复决定，而非当作完整云端配置导入；由原同步队列发 `.syncSpace`。Site 详情内嵌 Space 与单 Space GET 走同一 Key 判断，但 Site 列表摘要不能触发修复。
3. **一个共享 Key 合同供出口和最后提交门使用。**`SpaceData.export(.cloudSync)` 找不到有效 Key 时返回可定位的本地错误；`SpaceConfigurationSafety.prepareSubmission` 在 `.spaceUpload`、Site 上传内嵌 Space 和首次上传的共同入口再用同一合同阻止漏网 payload。调试导出仍可保留缺 Key 证据，不作为可上传快照。
4. **把 Key 纳入上传确认。**当前 prepared 回执与 `resumeUpload/readUploadedConfiguration` 只比较逻辑配置。新回执保存脱敏的 Key 身份摘要/索引，不保存额外明文 Key；HTTP 成功或未知结果回读都需确认服务器返回同一对 Key，才清除待同步。旧回执没有摘要时，先用现有云端回读和本地已验证 Key 保守确认；不能证明时保留待核对，不盲目丢弃回执或重复发送旧缺 Key 整包。服务器若仍以 500 拒绝完整修复快照，需要服务端明确拒绝原因并修复写入合同，App 不把 HTTP 成功当作端到端修复。

### 验证与边界

- 生产路径回归：同一手机把含至少两个 Space 的 Site 转出、列表标记 `.waitDeleted`、转回同 UUID；确认主 Key、两个子网 NetKey/AppKey、Group/Scene 都保留。补上“未保留旧 Site 的全新接收”与“主 Key 冲突”对照。
- 缺失矩阵：本地缺 NetKey、仅缺 AppKey、服务器缺 NetKey/仅缺 AppKey、双方 Key 不同、同索引占用、旧格式省略字段、Editor/Visitor 裁剪响应、待上传回执、空 Node 与保存失败。只对可证明的缺失补齐；冲突不自动修。
- 现有 `Tests/Group/SpaceMembershipLifecycleTests.swift`、`Tests/Group/SpaceRecoveryReceiptTests.swift` 与相关 `scripts/check_space_*` 增加真实行为夹具，覆盖导入、提交和回读；之后运行相关脚本与 SunSmart Debug generic iOS 构建。本方案未改代码，当前没有测试或构建结果。
- 最终用受控测试 Site 做转出/转回及 `/sync/spaceprops`、`/sync/siteprops` 与 GET 回读，核对完整 Key、版本和其他配置。用户手机的原始 Mesh Key 列与转移历史仍需只读核实，不能仅凭现有三份文件宣称已还原这次操作。

## 2026-09-23 实施记录

已按上节授权范围修改 App，未修改 SDK 或服务器：

- Site 转回时，先核对原本地网络的主 Key 与服务器主 Key，再保留所有已有子网 Key；重新分配手机地址不再触发重建 MeshNetwork。Site 保存前合并子 Space 刚补入的 Key，遇到同索引冲突或保存失败即停止；接收入口收到失败不再显示成功，Site 列表也不会把“服务器有但导入失败”的 Site 当作服务器已删除。全新接收仍可创建网络。
- Space GET 在普通版本比较及本地待上传保护之前，按持久化 Space 的 Network ID 核验服务器 NetKey/AppKey，串行补入本地缺失项并保存、回读。已有同索引不同 Key 拒绝自动修复；仅补 Key，不导入服务器旧业务配置或改写待上传时间戳。
- 服务器仅缺一种 Key 时，只在 Owner 的完整 Space GET、另一种 Key 与本地一致、非 Key 配置投影相符且本地身份可验证的情况下，排入既有 `.syncSpace`。若旧提交回执已在队列中，且回读证明业务配置已到达、只缺一种 Key，则仅解除该回执，保留待同步版本，再由现有任务上传完整快照。两种 Key 都缺、裁剪响应、身份不明或配置冲突仍需人工核对。
- 云同步导出与最终提交回执使用同一 Key 完整性规则。回执记录脱敏 Key 指纹；正常 HTTP 成功和未知结果都经 GET 回读核对 Key 与配置后才清除。旧回执没有指纹时，以本地现存完整 Key 和云端回读保守核对。调试导出保留缺 Key 证据。

自动验证：`check_space_key_integrity.py` 覆盖两个 Space 共存、仅缺 AppKey、服务器单侧缺失、同索引冲突、保存失败和无效身份；`check_space_membership_lifecycle.py` 与 `check_space_recovery_receipts.py` 覆盖导入身份、旧回执、成功/未知结果回读及拒绝清除不完整 Key 回执。SunSmart Debug generic iOS 构建通过。隔离测试使用 Mesh 与网络替身，不等于真机/受控服务器验收。

未完成的现场验收：原用户 Site 的转出/转回历史与原始 Key 列仍缺只读证据；需受控 Site 实测双 Space 转回及 `/sync/spaceprops`、`/sync/siteprops` 的服务器写入和 GET 回读。如果完整 Key 请求仍返回 HTTP 500，需服务器异常栈定位，App 侧不能据此断言服务端已修复。
