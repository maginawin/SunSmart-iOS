# HDB 设备订阅与发布诊断方案与实施记录

创建：2026-10-21；更新：2026-10-22。状态：已确认并实施，相关回归与五品牌本地 SDK 构建通过，真实设备与最终 UI 待用户验收。

## 1. 结论与范围

建议在 `HDB Site → Space → More → HDB Configuration → Devices → 设备` 页面最底部增加 Diagnostics 区域，读取该设备参与 Set Lighting Zone 和 Preparation 的全部相关 element/model 实例的 Subscription 与 Publication，逐项比较读取前的 App 保存值并展示差异。

本期重点回答：Set Lighting Zone 后，Presence Sensor 的发布是否仍指向本设备 Sensor Group，LC 接收模型及其共享订阅模型是否仍保留该地址，子 element 所需 `0xFEFD` 和所选 Zone 地址是否完整。

- 保持设备诊断为观察操作：不自动 Set、Sync、修复、分配 Group、改变 HDB 状态或上传云端。
- 当前 SDK 的订阅状态解析存在已复现缺陷，Get 还会更新并保存本地模型。可信诊断需要先完成小范围 SDK 配套，不能只在页面追加 Get 按钮。
- 本轮没有现场 Set 前后回读或运行日志，尚不能确认 occupancy 失效的根因。现有 ACK / synced 不能证明设备当前订阅表与 App 一致。
- 本期不读取全部 Mesh models，不新增 LC Mode、Occupancy Mode、Vendor 参数、Sensor 实时事件或 AppKey 绑定的主动 Get。这些属于订阅/发布一致后可能需要的下一步调查。

## 2. 已核实的行为链

| 环节 | 当前事实 | 诊断含义 |
| --- | --- | --- |
| 页面入口 | `SpaceMoreViewController` 按 HDB 类型、功能可见性与 Group edit 权限进入；Devices 点击进入 `HDBLightingZoneDeviceViewController` | 在实际设备详情底部追加，不加到 Zone 详情或 Lighting Configuration 参数页 |
| 现有 Get | `HDBLightingZoneService.getLightingZones` 读取本地 HDB 元数据，页面只展示 JSON | 保留其含义，新入口明确标为读取设备 |
| Set Lighting Zone | 先保存完整 Zone 意图为 pending，再执行 overwrite/deleteAll/add，全部阶段成功后变为 synced | pending 也允许诊断，失败/中断时尤其需要读取 |
| Zone 目标 | 五类 model 的所有实际实例；按 element/model/company 区分 | 不能只读主 element 或每类 model 的首个实例 |
| 订阅保护 | `zoneSensorTargets` 与 `zoneBroadcastTargets` 根据同 element 的 relatedModels 计算保护集合 | 不把 Sensor Group 加到所有 model，也不假设所有 element 共用一张表 |
| Preparation | 有任一 SIG Sensor Server 就为各 Sensor Server 及 LC 生成 Sensor Group 订阅；Publication 仅选择属性映射完整且唯一的 Presence `0x004D` 实例 | 所有 `0x1100` 都要读订阅/发布，Presence 标记和属性未识别原因也要显示 |
| 就绪判断 | 初始化身份及 App 本地 subscriptions/publish 参与 isPrepared/pendingLinks；并非实时设备观测 | 不用“Preparation 完成”代替本次读取，不要求 isPrepared 成功才允许诊断 |
| SDK Get | Config 消息用 DeviceKey，发往节点主单播地址，payload 指定目标 element/model | 不把 Config Get 发到 Sensor/LC 子 element；也不增加 AppKey 已绑定的读取门槛 |

源码入口：

- [设备页](../SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDeviceViewController.swift)、[HDB 入口页](../SunSmart/Main/Space/HDB/Controller/HDBConfigurationViewController.swift)。
- [Zone 服务](../SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift)、[Zone 策略](../SunSmart/Common/Data/HDBLightingZonePolicy.swift)。
- [设备上下文与目标选择](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift)、[Preparation 策略](../SunSmart/Common/Data/HDBDevicePreparationPolicy.swift)、[准备/同步任务](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift)。

## 3. 读取哪些实例

| Model | ID | 纳入原因 | 本期读取 |
| --- | --- | --- | --- |
| Generic OnOff Server | `0x1000` | Set Lighting Zone | Subscription + Publication |
| Light Lightness Server | `0x1300` | Set Lighting Zone | Subscription + Publication |
| Light LC Server | `0x130F` | Zone、Sensor 接收、Preparation | Subscription + Publication |
| Light LC Setup Server | `0x1310` | Zone、Preparation | Subscription + Publication |
| Sunricher Vendor Model | Company `0x0A78` / Model `0x0001` | Zone、Preparation | Vendor Subscription + Publication |
| Sensor Server | SIG `0x1100` | Preparation 的订阅与发布 | 每个实际实例的 Subscription + Publication |

集合按 `(elementAddress, companyIdentifier, modelIdentifier)` 去重。目标来自当前节点的 composition；表中 ID 是筛选规则，不是硬编码设备 element 布局。显示 element index 与十六进制单播地址、model 名称/ID、来源 `Lighting Zone` / `Preparation` / 两者。

复用生产目标选择与共享表关系。若完整 `requiredTargets` 校验失败，仍列出实际存在的相关 model 并允许在有效身份与权限下读取，另报缺失的必需类型，不能因设备不满足完整 HDB 能力而让诊断页面空白。可将现有筛选条件抽为小的纯函数，生产 Set 保留原完整校验，诊断只使用筛选部分。

Sensor 行显示 App 已识别的属性，例如 `Presence 0x004D`、`Ambient 0x004E`、`Energy 0x0072`、`Unknown`。映射不完整时，本期不补发 Descriptor Get、不猜测发布 element；仍可读取所有实际 Sensor Server 的 Publication，并标明 HDB 当前没有生成发布目标。不能把“不生成发布任务”显示成“occupancy 配置正常”。多个 Presence 的歧义也单独显示，不阻断其他项回读。

同 element 的共享订阅关系只用于解释和计算 HDB 要求；本期不因此扩展成全节点模型扫描。对范围内每个实例独立读取，保留设备实际回复，不能用一个实例的结果填充其他实例。

## 4. 比较基线与判定

### 4.1 读取前冻结两个来源

1. **App Saved**：从当前 Space 的已保存 Mesh/Node 取目标 model 的原始订阅地址与完整 publication，复制为不可变值。核对它与当前连接节点的 UUID、主地址、子网、DeviceKey 身份及 composition 对应；不把可变 Model 引用作为基线。
2. **HDB Expected**：从已保存 HDB 配置、设备 Sensor Group、当前目标选择和 Preparation policy 计算本功能所需值。使用保存的 Zone 意图，不使用页面尚未 Apply 的勾选草稿。

已有 SDK `Model.subscriptions` 会给主 element 自动追加 All Nodes `0xFFFF`，并只返回本地已知 Group，直接使用它会产生假差异或漏项。优先使用已保存 Model 的 Codable `subscribe` 原始列表提取基线，按 SDK `MeshAddress` 解析；无需为此导出整个带密钥 Mesh。若原始值无法解析，显示基线错误，不回退成空列表。`0xFFFF` 不作为人工配置订阅参与比较。保留 `0xFEFD`。

若存在 Label UUID，比较可由设备回读的 16 位地址，额外保留本地 Label 信息，并提示设备回复不能验证 Label UUID 是否相同。本 HDB 分配的 Sensor Group 是普通 group 地址，App 的 `isVirtual=true` 标记不代表 SIG 虚拟地址。

### 4.2 Subscription

- 实际值直接取成功且身份匹配的 Subscription List `addresses`，不能读 SDK 更新后的 `model.subscriptions` 当作无线结果。
- 规范化为地址集合并排序；顺序不同、重复地址不产生集合差异，原始响应可在报告保留。
- `Missing on Device = App Saved − Device Actual`；`Extra on Device = Device Actual − App Saved`。空订阅表是合法成功值，超时/错误/未读不是空表。
- 每个 Zone 管理的目标期望值为：保存的所有 Zone groupAddress，加上该目标属于 sensorTargets 时的 sensorGroupId，加上属于 broadcastTargets 时的 `0xFEFD`。Zone ID 必须查目录映射，不能直接按 ID 推导地址。
- Sensor Server 的 Preparation 使用 Add：HDB 检查应要求包含本设备 sensorGroupId，不将其他非 HDB 订阅一概认定为错误；其完整列表仍与 App Saved 比较。
- 空 Zones 仍检查必须保留的 Sensor Group / FEFD。missing sensorGroupId 或缺少配置记录显示“无法形成完整 HDB 预期”，不偷偷分配或补建记录。

两个结论分别显示：`Matches App` / `Different from App`，以及 `HDB Requirements Met` / `Missing HDB Configuration` / `HDB Expectation Unavailable`。这样 App 与设备都漏了 Sensor Group 时，仍能直接指出问题。

### 4.3 Publication

比较 destination、AppKey index、Friendship credentials flag、TTL、Period、Retransmit count/interval；必须显示具体不同字段。`nil` 与设备 `0x0000` 规范化为 Disabled；地址禁用时不以无效附带字段制造“发布启用”差异，报告可保留原始字段。

Presence 的 HDB 期望来自现有 Preparation 配置：sensorGroupId、当前 HDB AppKey index、credentials=false、TTL=`0xFF`、Period disabled、`HDBDeviceSyncService.sensorPublicationRetransmit`。当前代码该重传值为 count=2 / interval=100 ms，不能照抄旧文档中的“retransmit disabled”。展示时 TTL `0xFF` 标为 `Default TTL`，不与某个数值 TTL 擅自等同。

其余 model，以及未被当前 policy 选为发布目标的 Sensor，仍比较 App Saved 与 Device Actual，但 HDB 期望显示 `Not managed by HDB`；没有 Preparation 发布任务不等于设备发布必须禁用，也不能据此宣称错误发布已被清除。

### 4.4 总结果

- 逐项状态：`Not Read`、`Reading`、`Matches App`、`Different from App`、`Not Supported`、`Read Failed`、`Cancelled`、`Snapshot Changed`。
- 非成功协议状态保留错误码；只有明确“不支持”才显示 Not Supported，Invalid Model 等其他错误不能掩盖为正常空值。
- 摘要给出比较成功、不同、未完成和不支持的数量。只要本轮选定范围有未完成项，就不能显示全量一致。只读了 Subscription 时，摘要明确限定为 Subscription。
- 即使所有读取项与 App 一致，仍单独显示 HDB 要求检查结果，并注明这是配置快照，不能证明感应事件已产生或灯控执行正常。

## 5. 页面交互

在设备详情页追加始终位于最后的 `Diagnostics` section；现有本地 JSON 展开后，该区域仍在 JSON 后面。

- 操作：`Read Subscriptions`、`Read Publications`、`Read All`；执行时显示进度与 `Cancel`。
- 结果按 element 排序，每个 model 展示两项读取状态；展开后展示 `App Saved`、`Device Actual` 和具体差异，以及 HDB 要求说明。
- 失败项可手动 Retry；重试先验证同一基线仍有效，配置变化则重新捕获并开始新一轮，不能把不同配置时刻的数据拼成“全部一致”。
- 完成后提供 `Copy Diagnostic Report`，包含时间、App/SDK 版本、设备 UUID/地址、Sensor 属性、Zone/Sensor 地址、逐项值及错误；不含 DeviceKey、AppKey、NetKey 内容、账号凭据或整份 Mesh 导出。AppKey 只显示 index。
- 结果是本次进入页面的临时观察，不写入 HDB JSON/数据库，不新增报告历史系统。退出重进显示 Not Read；现场需要留证时使用 Copy。
- 诊断过程中禁用 Apply、Sync 及重复 Get，避免交错写入；原本未 Apply 的 Zone 勾选保留。回读刷新只更新诊断区域，不调用会重载 saved selection 的整页 reload。
- 入口沿用当前 HDB 访问权限与安全上下文，不扩大角色权限。未准备完成、Zone pending、某类 model 缺失不应成为诊断自身的禁止条件；账号/子网/节点身份失效、安全阻断、无 DeviceKey、离线等仍须明确处理。
- 所有新增文案同步 English 与简体中文，复用现有状态/取消/复制 Key；页面文字不暴露 SDK 实现细节。

## 6. SDK 配套：本次必要边界

### 6.1 订阅状态码解码

本机 `one-dev` revision `8c5af55` 的 `ConfigSIGModelSubscriptionList.init(parameters:)` 和 `ConfigVendorModelSubscriptionList.init(parameters:)` 都使用 `ConfigMessageStatus(rawValue: 0)`，没有读取收到的 `parameters[0]`。

本轮直接编译这两个生产解码文件，仅为协议类型和 Data 基础操作提供临时依赖边界，得到：

| 输入状态字节 | SIG 解码结果 | Vendor 解码结果 |
| --- | --- | --- |
| `0x00` Success | `0x00` | `0x00` |
| `0x02` Invalid Model | `0x00` | `0x00` |
| `0x08` Not a Subscribe Model | `0x00` | `0x00` |

这是已复现的解码缺陷，但不是 occupancy 根因证据。修复应从实际状态字节解码，保留失败结果，并验证最小长度、地址列表偶数字节长度和非法状态。否则失败的空列表可以被诊断误判为“设备实际为空”。仅在 App 检查 `status.isSuccess` 无法绕过，重新编码后的 `parameters` 也已经丢失真实状态。

### 6.2 单请求观察模式

`ConfigurationClientHandler` 收到成功 Publication Get 后修改 model.publish；收到 Subscription List 后会覆盖该模型及同 element relatedModels 的订阅，可能创建本地 New Group，并在末尾 `node.save()`。这意味着“App 不主动 save”并不足以保证诊断不改本地数据。

建议只为三类 Get（SIG Subscription、Vendor Subscription、Publication）增加请求级、不参与无线编码的本地更新选项，默认保持现有行为；诊断显式关闭本地更新。Handler 对这些观察请求跳过模型/Group 变更与 Node 保存，但正常解码、交付响应。不要使用全局临时开关，也不要在回读后恢复整个 Node 快照，避免覆盖其他任务的合法更新。原 Set、标准配置和其他调用方维持现状。

对未关联到活动请求的响应、取消后的迟到回复，同样应验证不会由观察请求触发本地配置写回。只影响配置缓存与持久化副作用；不改变正常 Mesh 接收、重放保护等运行状态。

### 6.3 传输和响应关联

优先复用现有 `SyncSessionCoordinator` 的共享通道和 `MeshNetworkManager.send(AcknowledgedConfigMessage, to: node)`，每次只发送一个读取请求。SIG/Vendor 分别用现有 Get 类型，Publication 使用同一 ConfigModelPublicationGet。无需新增固件协议。

SDK 异步 Config 回调当前主要按源地址与 opcode 关联，所以 App 仍必须核对响应类型、elementAddress、modelIdentifier、companyIdentifier 和状态。错误模型/element 的迟到回复不能填入当前行，即使 SDK 已把它作为响应交付，也只能形成未完成/响应不匹配结果，再由用户重试。本期不顺带改造整个 SDK 响应路由。

开始、每次发送前和响应落地前核对会话、账号/区域、Site/Space/子网、节点实例/地址/DeviceKey、composition、HDB revision 与比较基线。取消/离页按已有 Task 取消与通道释放机制等待清理完成，旧回调不得更新新轮结果；不停止其他任务的传输。

本期 SDK 修改只能在已确认存在的 `one-dev` 中实施，执行前重新核对是否被其他任务占用。正式 project 保留远端 release 配置，本地使用 SunSmartLocal；交付需记录 SDK 新 revision/未提交差异及正式 release 发布待办。涉及新增 SDK 请求选项时，App 正式依赖必须具备该 API，不能以本地构建替代发布。

## 7. 实施边界与复用

| 改动位置 | 计划内容 |
| --- | --- |
| `HDBLightingZoneDeviceViewController` | 底部诊断区域、进度/取消、草稿保留与读取期间互斥 |
| HDB diagnostic policy / snapshot | 纯值快照、目标筛选、Subscription 集合差异、Publication 字段差异、HDB 要求说明 |
| HDB diagnostic service | 复用上下文与共享传输机制、串行读取、失败继续、身份和会话校验、结果报告 |
| 现有 HDB policy/context | 仅在复用需要时提取目标筛选或期望发布值；检查 Zone、Preparation、Sync、添加完成等现有使用方，保持写入行为不变 |
| SDK | 两个订阅 List 解码修复、三类 Get 的观察模式与对应 Handler 行为 |
| 工程与本地化 | 新 App 文件纳入五品牌 Sources；补齐中英文，核对资源归属 |

不修改 HDB schema、数据迁移、同步状态定义、Zone 写入顺序或 Preparation 选择规则；不自动清理未知发布/订阅。当前诊断不要求服务器/网关接口配套，也不修改固件、服务器或运行配置。

## 8. 验证与现场使用

实施后需要的最小有效验证：

1. **SDK**：实际二进制 payload 的成功/非成功状态、空列表、SIG/Vendor 多地址、截断/非法长度；观察 Get 前后模型、relatedModels、Group 集合及持久 Node 不变；默认 Get 与 Set 仍保留原更新行为；取消/无关联回复不写入。
2. **比较策略**：同值不同顺序、合法空集合、缺失/多余地址、主 element 隐式 `0xFFFF`、FEFD、未知 Group、Label 比较边界；Publication Disabled、地址/Key index/credentials/TTL/period/retransmit 各字段差异。
3. **HDB 目标与要求**：多 element 同 ID、Vendor/SIG 区分、无 Sensor、多个 Sensor、完整唯一 Presence/未知属性/歧义；空和非空 Zones、Sensor Add 允许额外合法订阅、共享列表所需地址；App/设备同样缺 Sensor Group 也能提示 HDB 缺项。
4. **异步服务**：逐项超时/不支持/失败继续；错 element/model/company/source、重复或迟到回复；读取中取消、离页、重入、账号/权限/网络/设备变化、HDB 配置变化；不会修改 HDB 状态或触发云同步，不与 Apply/Sync 并发。
5. **现有回归**：按实际改动运行 `check_hdb_device_preparation.py`、`check_hdb_integration.py`、`check_hdb_lighting_zone_execution.py`、`check_hdb_presentation.py` 及共享 Session 相关回归；新增行为夹具覆盖诊断策略与服务，不只做源码字符串断言。
6. **构建**：实现稳定后用映射正确的 SunSmartLocal 做 SunSmart / Debug / generic iOS 构建。本方案涉及共享 SDK API、新文件与品牌 Sources，合入前覆盖 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，串行复用本工作树 DerivedData。不使用 Simulator，不默认增加 Release。

最短人工取证：

1. 对同一台现场设备，Set 前执行 Read All 并复制报告，同时确认当时 Auto 下感应能否触发。
2. Apply 目标 Zones 后，不先执行 Sync 或重新 Preparation，直接再次 Read All 并复制报告，保留原始故障状态。
3. 优先检查 Presence Publication → sensorGroupId → LC/共享模型 Subscription 这条链，再看 Zone 地址与 FEFD 差异；必要时空 Zones 再测一次。
4. 若订阅/发布全部符合预期而仍不触发，后续再调查 LC Mode / Occupancy Mode、当前 Override、Sensor Status 事件与固件处理。该结果只能排查本期配置范围，不能直接认定固件故障。

## 9. 分析阶段基线

- App 工作树：`feat-HDB-261020`；分支 `feat/HDB-261020`；HEAD `b7cd24d8`。
- SDK：`.local-sdk/nordic-sig-mesh-sdk` realpath 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55`，检查时工作树干净。`SunSmartLocal.xcworkspace` 存在。
- 开始时已有修改 `docs/261021_1610_HDB_self_sensor_two_stage_analysis.md` 与未跟踪 `docs/261021_1510_HDB_device_add_cloud_requests_analysis.md`；本任务均未改动。
- 本轮完成源码链路调查和两类 Subscription List 解码缺陷的临时隔离复现；仅新增本文。没有修改 App/SDK 业务代码，没有 App 构建、无线通信、真机或云端联调。
- 用户随后确认实施；实现与验证记录见下节。occupancy 根因仍需同设备 Set 前后回读证据。


## 10. 已实施与验证记录

实施完成时间：2026-10-21 23:59（Asia/Singapore）。App HEAD 仍为 `b7cd24d8`，SDK HEAD 仍为 `8c5af55`；均未提交或推送。

### 已实施

- 在设备详情末尾增加 Diagnostics，支持 Read Subscriptions、Read Publications、Read All、Cancel、Retry Incomplete Reads、逐 model 展开及 Copy Diagnostic Report；本地 Get JSON 展开后，诊断仍位于其后。
- 读取时冻结已保存 Node 的原始 model subscribe/publication 与 HDB 预期，串行查询全部相关实例；范围内任一必需 model 缺失仍可读取剩余实例并提示缺项。
- 订阅比较去重/排序且排除隐式 All Nodes，保留未知本地 Group 地址、Label 信息、Sensor Group 与 FEFD；发布比较独立于 UI 文案，覆盖地址、Key index、credentials、TTL、Period、Retransmit，Disabled 规范化。
- App 一致性与 HDB 要求分别显示。Presence/环境光/能耗属性、未知映射和多个 Presence 的歧义均可解释，不猜测发布目标或自动补发现。
- 回读期间禁止 Apply/Sync/重复 Get；结果回调只刷新展示，不重载 saved selection，因此保留未 Apply 的勾选。取消等待自身 SDK Task 结束后释放共享通道；离页清除观察结果。
- 配置 revision、节点/网络/账号/权限、DeviceKey、composition 或本地比较基线变化会使结果失效。重试仅复用同一基线；失效后重新读取全份所选范围。报告使用捕获时的设备地址，不跟随之后的地址变化。
- SDK 两类 Subscription List 使用真实状态字节并拒绝非法列表长度/状态；三类 Get 通过 `updatesLocalState=false` 只观察，跳过模型、relatedModels、Group 创建和 Node 保存。默认值 true，其他调用方原有更新行为保留。
- 新增两个 App 文件、一个诊断回归脚本及配套夹具；源码与中英文资源已纳入五品牌。未修改 HDB schema、Preparation/Zone 写入语义、云端或固件。

实现入口：

- [值快照、比较与展示](../SunSmart/Main/Space/HDB/Model/HDBDeviceDiagnostics.swift)。
- [读取服务与报告](../SunSmart/Main/Space/HDB/Model/HDBDeviceDiagnosticsService.swift)。
- [设备页](../SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDeviceViewController.swift)。
- [App 诊断行为测试](../Tests/HDB/HDBDiagnosticsTests.swift)、[运行脚本](../scripts/check_hdb_diagnostics.py)。

### 已通过的自动化验证

| 检查 | 结果与证据范围 |
| --- | --- |
| SDK `scripts/check_configuration_readback.py` | 真实 SIG/Vendor/Get/Publication codecs 与接收处理相关生产分支；覆盖非成功状态、空/多地址、非法长度/状态、观察模式不改模型/相关模型/Group/保存计数、默认 Get/Set 仍更新、未关联回复不更新。无线与存储对象为边界夹具，并非完整 SDK 真机测试 |
| App `scripts/check_hdb_diagnostics.py` | 生产 policy/context/service/session；覆盖全部实例、缺 model、无 Sensor、多 Sensor、未知/多个 Presence、空 Zones、原始未知 Group/Label、双向订阅差异、发布全部字段、App/设备同样缺 HDB 项、错误响应、部分失败/重试、取消/迟到响应、排队取消、revision/身份/权限变化、无 AppKey 可读/无 DeviceKey 拒绝、报告保留旧地址且不含密钥。SDK/数据库/无线为边界，无 UI 运行 |
| `check_hdb_device_preparation.py` | 策略与 device-sync、device-tasks、add-completion、add-execution、subelement 五种集成模式通过 |
| `check_hdb_integration.py` | 共享订阅、空目标、严格 ACK、持久失败和迟到回复等现有行为通过 |
| `check_hdb_lighting_zone_execution.py` / `check_hdb_presentation.py` | Zone 重试/取消/通道及既有展示策略通过 |
| `check_sync_execution_session.py` / `check_sync_run_lifecycle.py` | 会话调度、停止/补偿/重试、跨页通道所有权与失效回执通过 |
| 工程/本地化/依赖 | 两个新增源文件各有五个 target Sources 项；五品牌 Localizable 资源均含英文与简体中文；新增 Key 无缺失/重复；strings/project plutil、App/SDK diff 检查及 `check_nordic_sdk_dependency.sh` 通过 |

App 诊断脚本复用本机 SDK 新增的 codec/接收分支测试源生成器；执行回归需同时保留本次 SDK 的测试文件，不应只复制 App 修改后把缺少 SDK 配套误认为产品逻辑失败。

### 构建

实际入口 `SunSmartLocal.xcworkspace`，SDK realpath 仍为 `one-dev`。串行复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`，使用 Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO。

| Scheme | 最终结果 |
| --- | --- |
| SunSmart | exit 0，构建记录 0 errors |
| Archipelago | exit 0，构建记录 0 errors |
| SLG Sync Plus | exit 0，构建记录 0 errors |
| SylSmart | exit 0，构建记录 0 errors |
| Lumineux | exit 0，构建记录 0 errors |

部分品牌有现有 asset 命名、weak capture、弃用 API 或 Info.plist 资源提示。Xcode CLI 输出中还出现过“command failed with exit code 0”的诊断文本，已对照最终退出码与 LogStoreManifest：上述五次最终构建均为 0 errors；未因此清缓存或修改无关代码。

未运行 Simulator、安装/启动真机或进行云端联调。隔离测试与编译不证明 UI 布局、无线往返或 occupancy 已恢复。

### SDK 发布依赖与交接

- App 调用新 API `ConfigModelReadbackMessage` / Get 的 `updatesLocalState`。当前仅本地 SDK `8c5af55 + 未提交差异` 提供这些能力，正式远端 release 尚未由本任务发布。
- SDK 生产修改共七个文件：ConfigMessage、ConfigurationClientHandler、三类 Get、两类 Subscription List；另有两个 standalone 测试文件和两个测试脚本。正式发布需同时包含解码修复与观察模式，不能只发布 App。
- 合入/正式远端依赖构建前，由既定发布流程提交并发布该 SDK，再核对 App 解析到包含新 API 的 revision。正式工程远端地址/release 配置保持原样，本任务没有 commit/push/tag/deploy。
- 报告携带 App 版本、可取得的 SDK bundle 版本及 readback API 标识；静态集成无法取得独立 SDK bundle 版本时明确记为 not separately versioned，不伪造 SDK revision。精确源码版本由本节构建记录关联。
- 两份原有未提交文档保持原样。下一步由用户按第 8 节对同一设备收集 Set 前后报告，先保留现场状态，再判断是否需要 Sync 或继续读取 LC/Occupancy 参数。
