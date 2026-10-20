# HDB Lighting Configuration：确认方案与实施记录

创建：2026-10-20 16:49。更新：2026-10-20 18:53。状态：已收敛 Preparation 范围，补齐准备首行、执行先后及错误显示，并修复 Vendor 短成功应答被 HDB 误判为 responseMismatch。短 ACK 修复的 4 项相关回归及 SunSmart generic iOS Debug 构建通过；前阶段 12 项 HDB 和 2 项共享同步回归已通过。最新设备重试、UI 和完整云端联调仍待人工验收；另发现 SDK 对截断 0x32 扩展回包的长度检查缺失，作为独立待办记录。

2026-10-21 更新：Lighting Zones 已改为全量覆盖，当前契约、实施范围和本轮验证统一记录在 [Lighting Zones 设计文档第 19 节](261020_1019_HDB_lighting_zones_design.md)。下文旧章节保留其历史记录身份，不作为此次改动的验证结果。

- 用户已调整为 Sensor 优先：需要保留 Sensor 的相关 Model 先 Overwrite sensorGroupId，再 Add 全部目标 Zones；其他 Model 非空目标 Overwrite 首 Zone 再 Add 其余，空目标 DeleteAll。按同 element 的共享订阅表扩展 Sensor 保留集合，避免 LC Setup 等后续覆盖再次清掉 LC 的 Sensor。执行顺序为 Sensor 起始 → 其他订阅表起始 → Zone Add，Sensor publication 和既有参数初始化不变。
- 成员同时删除 `desired/status`，仅保留 zoneId；设备级 `lightingZonesStatus` 是整轮及空目标的唯一状态，只有 pending/synced。取消单 Zone 重试，统一整设备重发；即使已 synced，人工仍可重新 Apply 修复实况偏差。
- 用户接受无法准确识别旧 Zone 残留接收者，不新增 Space 级 pending → Multicast 拦截。既有当前目标成员检查改读设备级状态，Unicast/Broadcast、prepared、权限及应急规则保持原范围；未知旧成员由人工测试后重配。上述消费者已同步更新。
- 当前代码的持久 `HDBSyncStatus` 已仅有 `pending/synced`；本文旧的 `failed/sent`、preparation JSON 等描述属于当时设计，当前事实以源码及 Lighting Zones 第 19 节为准。本轮不改 Lighting Configuration 参数协议或其 ACK/发送依据。

## 0. Preparation 范围收敛（已确认、已实施）

用户已确认 Preparation 只用于 HDB Configuration 中 Set Lighting Zones 的前置配置，状态仅持久化到 `spaceData.hdb`。本节覆盖原实现中“普通 Profile 覆盖时自动使准备失效”的方案；本轮已移除该跨功能策略。

### 已证实的问题

状态本来就保存在 `spaceData.hdb.devices[].preparation`，没有增加标准 Group/Node 的准备状态。越界的是原普通发送流程对该状态的读写和失败拦截，已作如下调整：

| 原新增位置 | 原影响 | 本轮结果 |
| --- | --- | --- |
| `LightSensorCalibrationViewController.configuring` | 校准发送前失效 HDB 准备；保存失败会跳过该设备的原校准发送 | 已撤掉本任务新增钩子 |
| `SyncExecutionEnvironment.addMessage` | 共享发送环境先读写 HDB；失败会将消息判失败并提前结束 | 已撤掉本任务新增钩子，共享环境不承载 HDB 准备策略 |
| `GroupServer` 添加成员、删除成员、同步发送 | 普通组操作发送前失效 HDB 准备；失败会跳过原发送 | 已撤掉本任务新增三处钩子 |
| `HDBLightingMessages.changesPreparation` 与 Store 的 `invalidatePreparation(before:)` 扩展 | 识别普通 Profile/Scene 消息、跨 Space 找设备并持久化准备失效 | 已随调用方一起删除，没有迁移为其他位置的全局监听 |

此前为防止普通 Profile 覆盖固定参数而加入这些钩子，是对需求范围的过度扩展。离线测试能验证它按代码设计工作，不能证明这种跨功能依赖符合需求。

### 最终边界

| 入口 | 是否可生成/执行 Preparation | 状态行为 |
| --- | --- | --- |
| HDB Set Lighting Zones（Apply） | 有期望保留/加入的 Zone，且准备记录缺失、未成功、版本或目标集合不匹配时生成 | 成功记录可复用；退出重进不自动发送 |
| HDB Set Lighting Zones 的 Retry | 作为同一配置流程的恢复入口，可补做未完成准备 | 准备失败阻止同设备后续 Zone 任务；正常换/加 Zone 不重复成功准备 |
| HDB 纯退订、删除恢复、单项退订重试 | 不生成 | 不因设备未准备阻断退订；也不先生成后过滤准备任务 |
| HDB Lighting Configuration | 不生成、不隐式补做 | 保留现有 HDB 内部只读前置检查；未完成时提示先配置 Lighting Zones。仅保存元数据和单播 Get 保持原豁免 |
| 普通 Profile、校准、加组、退组、同步和控制 | 不生成、不维护 HDB 准备状态 | 撤销本任务增加的 HDB 保存失败对普通发送的拦截 |
| 已有设备 Restore 的 HDB 记录迁移 | 不生成、不发送 | 仅在已有 HDB Store 更新中清旧准备字段，保留重新入网后重做的依据 |

任务生成在 HDB 专用 Service/Policy 中显式区分 Set/Retry 与退订路径。`operations` 的 `includePreparation` 默认为 false，仅 HDB Set、加入重试、Retry Failed 显式启用。Retry Failed 本轮若只有退订，即使另有已同步的保留 Zone 也不生成 Preparation；无订阅任务时仍允许为旧记录补准备。共享发送和会话协调机制继续复用，没有为它们增加 HDB 判断。

Restore 的 HDB 迁移入口在本功能之前已经存在，原本就更新地址并将订阅标为 pending；本次仅多清一个 HDB 字段。已按确认方案保留该字段清理，没有增加 Restore 调用点、额外持久化步骤或新的失败拦截。实际重新准备仍只能由之后的 HDB Set/Retry 发起。地址/Composition 变化检查、准备版本、失败/取消结果也继续限定在 HDB 对象和执行流程内。

准备状态是每个设备的固定参数初始化记录，同设备多个 Zone 共用；不成为标准 Group 的配置属性。沿用现有可选 JSON 字段，旧记录缺字段仍合法；不做数据库迁移，不清除已成功记录或其他 Lighting Configuration 值。

### 一次准备的适用条件

`synced` 表示上次 HDB 固定配置已成功，不保证设备之后始终保持这些参数。撤销跨功能监听后，普通 Profile/校准等若再次写相同参数，HDB 不会自动清状态；下一次 Set 若记录仍匹配，也会复用记录。不能将其描述为“配置一次后永远不需要重配”。

本次收敛不另加设备轮询、自动覆盖检测或新的强制重做入口。若之后需要处理普通功能覆盖后的恢复，应另行确定 HDB 页面内显式重做的交互，不能再通过普通功能钩子实现。此限制已随本方案一并确认。

### 本轮实施与验证

1. 上述三个标准文件已恢复至基线 `e00aa89b` 内容，无残余差异；失效分类、Store 扩展及专用失效测试/脚本已移除。
2. HDB 任务生成已收敛；既定准备参数、ACK 核对、退订顺序、失败阻断、取消/身份校验与 HDB 持久化保留。
3. 修改生产逻辑前新增回归，分别复现“通用订阅计划隐式生成准备”和“仅退订的 Retry Failed 对保留 Zone 设备发送准备”；修复后两项通过。新增行为覆盖空 Set、单项退订重试、删除恢复、Restore 仅清字段而后续 HDB Set 重做，以及 Lighting Configuration 拒绝未准备下发但允许元数据保存且不补做准备。
4. 当前全部 12 项 `check_hdb_*.py`、`check_sync_execution_session.py`、`check_sync_run_lifecycle.py` 通过，SunSmartLocal / SunSmart generic iOS Debug 构建成功，`git diff --check` 通过。
5. 本轮是已确认范围的局部收敛，使用现有工作树与同一文档记录，由主代理统一实施和复核；未新增分支、提交、SDK 改动或跨品牌工程配置。真实普通 Profile/校准/加退组与 HDB 准备流程仍待人工验收，编译与隔离测试不替代设备验证。

### Preparation 首行、先后顺序与失败可见性（18:42 更新）

用户补充现场 JSON：`preparation.status=failed`、`version=1`，primary element 26 提供 Generic OnOff、Lightness、Vendor 0x0A78:1，element 28 提供 Generic OnOff、LC、LC Setup。该记录不会满足成功复用条件；JSON 只保存上次结果，不能据此判断失败发生在发送前、超时还是响应校验。

本轮核对并复现的实现问题：

- Saved Configuration Status 仅显示 Zone membership，Preparation 只放在 footer，缺少任务行和执行中状态。
- 原计划先退订旧 Zone，再准备；旧退订失败会使后续准备被跳过。
- 原执行器在准备失败后只跳过新增任务。如果把准备移到最前，还必须阻断该设备后续退订。
- 准备的连接/密钥/模型检查、SDK 发送、响应核对失败均丢弃错误，只保存 failed，页面无法解释“没有下发”。

已调整为：

1. 状态列表第一行固定显示 Device Preparation，覆盖 Not set、Pending、Preparing、Synced、Failed；准备中显示活动指示器，本轮失败附带错误原因。Zone 行下移，单项重试索引同步调整。准备通过原 Apply / Retry Pending / Failed 入口重试，未新增全局或独立强制准备入口。
2. 有新增/保留 Zone 且需要准备时，执行顺序改为 **Preparation → 旧 Zone 退订 → 新 Zone 订阅**。准备成功且持久化完成后才推进；准备失败跳过同设备本轮所有后续 Zone 任务。纯退订仍不生成准备，已有有效 synced 记录仍复用。
3. HDB receipt 传递瞬时错误，Executor 向页面报告；区分连接不可用、Space AppKey 缺失、模型未绑定 AppKey、实际选用密钥不符和回复不匹配。错误提示没有写入标准 Group/Node，也不改变 SDK、固件或密钥绑定。
4. 增加仅 DEBUG 的 `[HDB][LightingZones]` 日志：计划中准备数量、准备开始、前置检查失败、已确认消息数及结果。日志不输出密钥或完整配置；旧轮次异步结束不会清除新轮次的任务引用。

验证：先复现计划顺序、准备失败仍执行退订、错误未传回页面三项失败，再修复至通过。真实 Service 集成夹具采用用户的 26/28 element 结构、匹配的 failed 准备记录，并暂停传输替身的每个 ACK，验证准备未全部完成前没有退订/订阅发送；另覆盖前置 AppKey 缺失时零发送并回传原因。该夹具验证 App 编排，协议消息编码和无线设备响应不由替身证明。

最新全部 12 项 HDB 脚本通过，SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建成功（exit 0）。新增中英文文案沿用既有共享 Localizable.strings，未新增资源或品牌编译分支。未运行真机；用户这台设备上一轮的确切失败点仍未知。

最短人工步骤：保留 failed 记录并对非空 Zone 选择点击 Apply，观察首行 Preparing → Synced 后才执行 Zone 任务；若显示 Failed，读取该行错误和 `[HDB][LightingZones] Preparation preflight failed` / `Preparation result` 日志。当前轮次错误为瞬时信息，旧 JSON 没有足够信息还原历史失败原因。

### 现场日志：Vendor 成功应答被误判（18:48 分析，未修改业务代码）

用户提供的新日志明确显示 `plan preparation=1 zoneTasks=1`、`Preparation start node=17 writes=6`，因此本次准备任务已经下发。设备地址为十进制 17，即 `0x0011`，与之前仅提供 JSON 的 26/28 element 样本分开分析。

| 环节 | 现场证据 | 结论 |
| --- | --- | --- |
| 第一条准备命令 | `F0 78 0A`，参数 `33 00`，`manualControlEnabled(false)` | 已向设备发送关闭 manualControl |
| 设备回复 | `F3 78 0A`，参数 `33 00 00` | code=0x33、subcode=0、ret=0，设备报告成功，没有配置值回显 |
| SDK 解码 | `isSuccessful=true`、`code=manualControlEnabled`、`status.parameters=nil` | 原始 parameters 有 3 字节；缺少的是解码后的回显参数，不是未收到回复 |
| HDB 校验 | `HDBLightingMessages.matches` 强制匹配 `.manualControlEnabled(false)` 回显，nil 落入 false | HDB 新增校验规则与实际成功 ACK 不兼容 |
| 执行结果 | `acknowledged=0/6 error=responseMismatch` | 第一条收到成功 ACK 但未通过 App 校验；后续 5 条准备消息未继续，同设备 Zone 任务被前置条件阻断 |

已只读核对当前 SDK `SunricherVendorStatus.Status.init(data:)`：前三字节分别为命令、子码和成功码，只有至少 4 字节才解析配置回显，3 字节应答正常产生成功状态和 nil 回显。当前本地私有协议 `/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/sunricher_protocol_vendor.md` §5.2 的 0x32、0x33、0x34 均定义 subcode=0 和单字节 ret，未要求配置值回显。因此不应将本次短 ACK 视为固件失败或缺包；另外两条 Vendor 准备命令也应按各自应答契约检查，但本日志没有它们的实际回包。

`Local Vendor Model ... not bound to key` 指 App 本地 provisioner 的模型分发绑定检查。AccessLayer 在该分支跳过模型 delegate 后仍向 network manager 通知已解码消息，日志也显示 HDB 已收到并校验本次回复；它不是此次 responseMismatch 的原因，不能据此推断远端设备未绑定 AppKey。其对本地模型缓存更新的影响属于独立问题，本轮不扩展修改。`cannot add handler to 0 from 0 - dropping` 没有足够上下文建立因果联系。

后续 CloudSync HTTP/business 200 及 readback confirmed 表示 Space 数据上传和回读完成，不等于设备准备或 Zone 订阅成功；HDB failed 结果可以随 Space 正常同步。

建议最小修复限定于 HDB 响应校验：0x32/0x33/0x34 必须核对对应命令、正确子码和成功状态，接受协议定义的完整 3 字节短 ACK；若存在完整回显则继续比对请求值，错误码、错误命令、截断或非法格式仍拒绝。不得仅凭 `status.parameters=nil` 或任意 Vendor `isSuccessful` 放行，也不根据短 ACK 伪造设备读回缓存。保持准备全部成功才执行 Zone 任务的既定顺序和状态存储。

此前 Service 编排测试替换了 `HDBLightingMessages` 和协议消息，仅证明串行、失败阻断与持久化行为，未覆盖真实 SDK 的短 ACK 解码。修复验证需加入本次 `33 00 00` 报文以及 0x32/0x34 短 ACK、匹配/不匹配回显、设备失败和错误命令，执行实际 HDB matcher 与 SDK 解码路径；之后仍需现场确认全部 6 条完成并继续 Zone 订阅。本轮仅记录分析，未修改 App/SDK 业务代码、未重新构建或操作设备。

### 短 ACK 修复（18:53，用户确认后实施）

- 唯一生产逻辑调整位于 `HDBLightingMessages.matches` 的 Vendor 分支，限定三个准备命令 0x32/0x33/0x34。必须满足 SDK 成功状态、对应响应命令、原始命令字节匹配、subcode=0、ret=0。
- 恰好 3 字节的成功 ACK 直接通过；额外包含回显时，将全部回显字节与请求中的配置字节比较，同时拒绝值不匹配、长度不足、多余字节，以及被 SDK 宽松转换的非法 boolean/state。
- 不伪造设备观测缓存，不改 SDK、普通 Group/Profile 或准备任务编排、持久化字段。`LightSensorCalibrationViewController`、`SyncExecutionEnvironment`、`GroupServer` 再次核对仍与 HEAD 一致。
- 已有 `failed` 记录可通过原 Apply / Retry 重试，不需删 JSON 或迁移状态。仍要全部准备 ACK 通过才保存 synced 并继续 Zone 任务。

新增 `check_hdb_lighting_messages.py` / `HDBLightingMessagesTests.swift`，先以捕获的 `33 00 00` 复现旧 matcher 失败，再验证修复通过。CLI 夹具直接执行完整生产 matcher，并从实际映射 SDK 提取相关 Set 编码、Status 公共头和 0x32/0x33/0x34 回显解析分支；不加载 UIKit/整个 SDK，也不模拟 BLE 或本地模型 delegate。SIG 消息仅作为类型替身。覆盖三个命令的短 ACK、正确回显、逐字段错误回显、错误命令/子码/结果、额外字节及非法值。

本轮四项脚本均 exit 0：`check_hdb_lighting_messages.py`、`check_hdb_integration.py`、`check_hdb_lighting_zone_execution.py`、`check_hdb_lighting_configuration_service.py`。后面三项继续验证准备失败阻断、成功后推进、Apply/Retry、退出重进、取消及配置发送边界；未将它们的协议替身当作真实设备证明。SunSmartLocal / SunSmart / Debug / iphoneos / generic iOS / CODE_SIGNING_ALLOWED=NO 构建成功（exit 0，18:53），SDK 仍为 `8c5af55` 且无改动。`git diff --check` 通过，无新增本地化、品牌分支或资源归属变更。本轮没有重跑全部 HDB 脚本或真机安装。

独立待办：SDK `SunricherVendorStatus.Status.init(data:)` 对 0x32 仅检查总长度 >=4，随后固定读取 enabled/state/UInt32 interval；4～8 字节的截断扩展回复可在 `Data.read` 越界终止。隔离测试已触发此现有问题，与此次 3 字节合法短 ACK 无关。本轮未扩展修改 SDK；截断数据用例通过“先解析合法短 ACK，再替换原始 parameters”仅验证 HDB matcher 的拒绝行为，不声称 SDK 能安全解析这些畸形报文。后续 SDK 维护应在读取前检查完整长度，用原始截断报文验证不会崩溃，并单独核对发布依赖。

最短现场验收：保留现有 failed 记录，重新 Apply 或 Retry；确认 `Preparation result ... acknowledged=6/6 error=none` 后才发送 Zone 订阅，最终 Preparation 和 Zone 均显示 Synced。现有日志只能证明第一条设备成功回复，修复后的全部六条及订阅仍待本次真机重试。

## 1. 最终确认的范围

用户确认固定 Occupancy 参数前移 Lighting Zones，Lighting Configuration 按选中命令发送对应字段。组播实际使用 Zone Mesh groupAddress；全部消息发送完成即按全部目标成功，不等待逐设备 ACK。广播能覆盖 primary 时真实广播，secondary 精确补发单播。两个元数据字段仅保存。

最后一轮控制决定覆盖早先的显式 LC Mode 切换建议：

| LightingControl | 本期实际消息 | 说明 |
| --- | --- | --- |
| Auto | LC Light OnOff=true | 复用 App Auto，一条命令 |
| Force_Off | Generic OnOff=false | 使用主 element 的 OnOff；组播复用现有 Zone 地址，见第 10 节 |
| Force_On | Light Lightness=65535 | 复用 App 亮度 100% |

这些控制不额外发送 LC Mode。单播采用 acknowledged 变体并核对回复；组播/广播采用 Unacknowledged 变体。固件负责手动控制与自动感应状态转换，App 未修改固件；Force→Auto、重复 Force、设备重启保持仍需真实设备验收。

本次只负责 App。未修改 SDK、固件、服务器或运行配置，不自动操作真机，不提交 Git。

## 2. 协议证据与项目扩展

- 原 `SLP Interface Control Document.pdf` 第 30 页 LightingControl Remarks 明确写 **“Force_On: Light full on.”**，因此请求最大 Lightness，不是 BrightIntensity=80% 或恢复上次亮度。保留的 trim/硬件限制仍可能限制实际输出。
- 原 PDF 第 30 页 LightingControl、对应说明和第 38 页 Timer Action 中的 ~~Unoccupy_Off~~ 均有删除线。已视觉核对原页并修正 Markdown；该值不是有效枚举。
- 原 PDF 第 30 页 InstallDate 仅写 Unicast/Broadcast；用户确认 App 增加 Multicast。两份 Markdown 单列项目扩展，保留原转录和原样例 JSON。
- FailsafeDelay 的原义是 lost sync 后延迟进入保护，不是 T2 或 Manual Override Timeout。本期仅保存，默认 5 分钟；没有实现 lost sync 判断、保护输出或恢复状态机。
- Get 协议仅单播。App Zone Get 返回本地保存值；广播只有 Saved Values，不发送广播 Get。

## 3. 属性和默认值

| 命令 | HDB 属性 → App/Mesh | 初始表单默认 | 输入范围 |
| --- | --- | --- | --- |
| Light Override | LightingControl；FailsafeDelay 仅本地 | Auto；5 分钟 | Auto/Force_On/Force_Off；0–250 分钟 |
| Intensity | DimIntensity → Vacant/LC Prolong；BrightIntensity → Occupancy/LC On | 20%；80% | 0–50%；50–100% |
| Soft Dimming | RampUpTime → T1；RampDownTime → T3 | 1 秒；2 秒 | 各 1–3 秒 |
| Time Delay | HoldTime → T2 | 30 秒 | 10–3600 秒 |
| Installation Date | InstallDate，仅本地保存 | 未设置 | 有效 dd-MM-yyyy |

表单默认仅用于首次编辑，不因打开页面或 Get 自动保存/下发。合法 0 不视为缺失，数值字段留空可省略，输入非法报错。每个命令独立 Set/Get；Override 另有 Save Failsafe Delay Only，离线保存元数据不重发控制。

T5、high/low-end trim、power-up behavior、relative sensitivity 均不加入任务；也不额外写 standby level、Sensor publication、Scene、daylight lux 或校准。

## 4. Lighting Zones 设备准备

每个相关 element 的固定准备为：

| 项目 | 值 | 接收模型 |
| --- | --- | --- |
| Occupancy Mode | true | 0x130F |
| manualControl | false | Vendor 0x0A78:1 |
| lightAutoAdjustEnabled | false | Vendor 0x0A78:1 |
| T4 | Infinite，沿用 App 原始值 0xFFFFFE | 0x1310 |
| Manual override timeout | enabled=true、standby、interval=UInt32.max | Vendor 0x0A78:1 |
| 初始 LC Mode | true，最后启用 | 0x130F |

前置任务使用单播 ACK 并按各命令契约核对：Vendor 0x32/0x33/0x34 允许无回显的成功 ACK，有回显时严格核对配置；SIG 配置继续核对回复值。不改变现有 Config Subscription 的 ACK 成功标准。按最新反馈，顺序为必要设备准备 → 旧 Zone 退订 → 新增订阅。准备失败阻止同设备后续所有 Zone 任务；准备成功后若退订失败，阻止同设备后续新增。其他设备可继续，纯退订流程不要求准备。

### Preparation 目标数据结构（2026-10-20 更新）

按用户确认，当前仍处于开发阶段，直接采用目标结构，不兼容旧的 preparation target 数据，不增加迁移或双写。`schemaVersion` 与准备策略 `version` 均保持开发目标版本 1；整个 `preparation` 缺省仍表示尚未准备，是合法状态。

`spaceData.hdb.devices[].preparation.targets[]` 为扁平对象，包含：

| 字段 | 约定 |
| --- | --- |
| `elementAddress` | UInt16 数字，保持原地址格式与所属 element |
| `modelId` | 与 Space Mesh model 相同的大写十六进制字符串：SIG 为 4 位，Vendor 为 Company ID + Model ID 共 8 位，例如 `"130F"`、`"0A780001"` |
| `value` | 该模型本次准备的目标配置对象。LC、LC Setup、Vendor 必填；只参与订阅的 Generic OnOff / Lightness 省略 |

不再输出 `modelIdentifier` 和独立 `companyIdentifier`。Swift 内部仍保留模型/厂商数值用于 SDK 消息寻址，准备参数不参与订阅目标身份及 ACK 身份比较。

| modelId | value 字段与当前默认值 |
| --- | --- |
| `"130F"` | `occupancyMode: true`、`mode: true` |
| `"1310"` | `prolongTimeMilliseconds: 16777214`（0xFFFFFE，沿用当前 Infinite 原始值；0xFFFFFF 是 Unknown，不可作为目标值） |
| `"0A780001"` | `manualControlEnabled: false`、`lightAutoAdjustEnabled: false`、`manualOverrideTimeout: { enabled: true, state: "standby", intervalMilliseconds: 4294967295 }` |
| `"1000"`、`"1300"` | 无 `value` |

所有时间字段保存协议原始毫秒值。`manualOverrideTimeout.state` 使用 `standby` / `on` / `prolong` 字符串并在 App 内映射为协议枚举。`value` 是初始化目标，`status` 是整次准备结果；Vendor 短 ACK 不提供读回值，后续运行控制也不会让这里成为实时状态。

任务生成时捕获一份强类型准备目标，消息编码、pending 保存与最终 synced/failed 保存均使用这份目标。固定默认参数只在准备目标创建处定义；所有 LC Mode 消息保持最后发送。准备复用同时比较版本、成功状态、完整模型实例集合及配置值；值不同会由 HDB Apply / Retry 重做，Lighting Configuration 下发会提示尚未准备。值匹配时仍复用，纯退订仍不准备。

解码和保存拒绝模型所需 value 缺失、类型不符、地址非法、24 位配置越界/Unknown、重复模型目标等无效记录。正常未准备设备、只订阅的模型及 pending/failed 结果保持允许。没有新增 UI、普通 Group/Node 流程、SDK API 或数据库列。

本轮验证结果：

- 12 项相关 HDB 脚本通过：`check_hdb_configuration.py`、`check_hdb_persistence.py`、`check_hdb_import_recovery.py`、`check_hdb_lighting_messages.py`、`check_hdb_integration.py`、`check_hdb_lighting_configuration.py`、`check_hdb_lighting_configuration_service.py`、`check_hdb_lighting_zone_execution.py`、`check_hdb_presentation.py`、`check_hdb_zone_control.py`、`check_hdb_group_lifecycle.py`、`check_hdb_space_creation.py`。
- 新增行为覆盖：JSON 扁平结构与 SIG/Vendor ID、目标值往返及非法值拒绝；默认 6 条消息不变、非默认值驱动全部字段、多个 LC Mode 仍在最后；pending/failed/synced 保存同一份值；匹配成功记录复用、值改变后重新准备、取消后迟到 ACK 不写成功、退出重进可重试；云端配置比较和选定快照导入保留准备值。
- 编码夹具执行生产 HDB 消息生成器及当前 SDK 的 Vendor 编解码、准备 SIG Set 构造与参数实现；属性值字节序列化、Mesh transport、数据库/云端外围仍使用测试边界，不代表真实 BLE 和服务器验收。
- `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / `iphoneos` / `generic/platform=iOS` / `CODE_SIGNING_ALLOWED=NO` 构建成功，exit 0。复用 DerivedData：`~/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`；编译仍有未修改控制器中的 capture 警告。
- 分支 `feat/HDB-261020`，实施基线 `6b5267a5`。SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `8c5af55`，无 SDK 修改或新增 API 依赖。五品牌共用相同逻辑；没有资源、target、依赖和品牌条件改动，本轮采用 SunSmart 代表构建。`git diff --check` 通过。

待人工验收：在采用目标结构的开发 Space 中，对未准备设备 Apply 非空 Zone，观察 Preparation 成功后执行订阅，并检查导出 targets 的 modelId/value；退出重进再次 Apply，确认匹配准备记录复用；中断准备后重试，确认完整准备成功才继续 Zone 任务。真实设备和云端上传/回读未执行。现存旧 target 格式按用户决定不做迁移，不应作为本轮兼容验收输入。

`preparation` 独立于 membership，保存版本、结果和包含目标值的模型集合：

- 旧记录无字段为未准备，Apply/Retry 补做；已有 synced membership 保留。
- 即使没有待发送订阅，也可单独补准备。移除不要求准备成功。
- 正常加/换 Zone 保留准备与 Lighting Configuration，不重复固定参数。
- Restore/重新入网清准备；Composition 不匹配会重新准备。
- 普通 Profile、校准、退出组等不维护 HDB 准备状态，原发送前失效/失败拦截已按第 0 节撤销。
- App 重启保留状态，不自动发送。外部客户端、固件升级、掉电持久化不能靠本地标记自动证明。
- Auto/Off/亮度控制自身不清准备。初始化标记不意味着运行时 LC Mode 永久为 true。

需要下发的 Lighting Configuration 要求目标准备完成；组播还要求该 Zone 订阅完成、无残留待移除成员。元数据和单播 Get 不受准备条件限制。已准备、当前无 Zone 的设备仍可单播；首次未准备设备通过非空 Zone Apply 准备，本期不增加独立 Prepare 页面。

现有 Lighting Zones 已订阅全部实例的 0x130F、0x1310、0x1000、0x1300、Vendor 0x0A78:1，本期无需新增模型类型或公共组地址。

## 5. 发送、范围与成功

| 消息 | 模型 | 广播路径 |
| --- | --- | --- |
| Auto | LC Server 0x130F | 通常在 secondary，定向单播补发 |
| Force_Off | 主 element 的 Generic OnOff 0x1000 | 可安全广播时发 allNodes，否则精确单播到 primary；不补发 secondary |
| Force_On | Lightness 0x1300 | primary 可真实广播，secondary 输出补发 |
| Dim/Bright、T1/T3、T2 | LC Setup 0x1310 | 通常在 secondary，各属性定向补发 |
| FailsafeDelay、InstallDate | 无 Mesh 消息 | 本地批量保存 |

按实际 Composition 路由，不按 PID 猜测。每条子消息最多一次 allNodes；没有可覆盖 primary 就不发无用广播。AppKey 必须绑定当前 Space 子网；若 allNodes 可被目标之外的模型接收，则该次退回精确单播，避免跨范围控制。

官方依据：[Mesh Protocol 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html) §3.7.3.2、§4.3.2.19：allNodes 固定组的 primary 分发及订阅限制；[Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html) §6.5.1.1：LC/Setup 与 Lightness 的 element 关系。特殊固件若额外跨 element 分发，需协议或实测证明后再采用。

群发与广播补发均串行等待 SDK 发送完成，全部完成才标成功；不把 Void enqueue 当作成功。这样也避开现有普通队列对同目标/opcode 不区分参数的去重，Intensity、SoftDimming 的两条 0x63 消息均发送。

单播 Set 等待目标 element 的 ACK 并核对值。发送错误、取消、部分发送不能判整体成功；已发送的硬件操作不宣称回滚。共享 SyncSessionCoordinator 管理执行权，取消等待所属 Task 退出后才允许新操作。

## 6. 持久化与读取

继续使用同一个 Space `hdb` blob，schemaVersion=1 新增可选字段兼容旧记录。

- devices：设备 preparation、Lighting Configuration。
- lightingZones：Zone 保存的 Lighting Configuration。
- 根对象：广播保存的 Lighting Configuration。
- 配置结果按实际字段记录 revision/status/source/basis，未执行字段保持原结果。仅保存 FailsafeDelay 不会把失败的 LightingControl 标成成功；元数据始终以 local 保存结果表达。
- 单播更新设备；组播更新 Zone 和本次成员；广播更新本次目标灯和当前 Zone 对应字段，包括空 Zone 的保存意图。
- 新加入设备不自动继承 Zone 历史参数；不同 Zone 共用设备时，硬件按后写覆盖前写，其他 Zone 保存值不随单播或组播改写。
- Store 从最新持久状态保存意图后再发送，完成后保存结果并沿用云同步；成员编辑保留新字段，删除按 UUID 清记录，Restore 清准备。
- 本地 HDB 请求/执行结果与 SDK 设备缓存分开，不伪造读回值。

单播 Get 逐 element 读取新回复，显示 saved 与 observed，标记 mixed/incomplete；不会用默认值冒充读回。Override 读取 LC Mode/LC OnOff/Lightness，保留最后请求，不能仅凭当前亮度逆推最后控制命令。Zone Get 读取保存值，InstallDate 和 FailsafeDelay 读本地元数据。

## 7. 实施文件与执行记录

- [x] Task 1：`HDBConfiguration`、`HDBLightingZonePolicy`、Store 的准备状态、旧数据、恢复与字段保留。
- [x] Task 2：`HDBLightingZoneService/Executor` 前置任务、ACK 校验、失败阻断；`HDBLightingMessages` 提供 HDB 消息编码与响应校验，跨功能失效适配已移除。
- [x] Task 3：`HDBLightingConfigurationPolicy/Service` 精确字段、路由、串行发送、单播读回、身份校验和持久化。
- [x] Task 4：新增 `HDBLightingConfigurationViewController`，首页入口、准备提示、English/简体中文和五品牌源文件归属。

原实现曾在 `SyncExecutionEnvironment`、`LightSensorCalibrationViewController.configuring`、`GroupServer` 的添加/删除/同步发送前复用准备失效边界。该跨功能策略及辅助代码已按第 0 节完整撤销。

使用 Superpowers writing-plans / executing-plans / TDD / requesting-code-review / verification-before-completion。根据用户要求，只维护本文档；不额外创建提交或分支。

实施裁决及审查修复：

1. 最终控制映射遵从用户确认，不显式切换 LC Mode；若固件不承担转换，需固件联调结论，不能以离线测试证明。
2. 结果细化到实际字段，避免元数据成功覆盖控制失败或部分属性覆盖其他结果。已复现旧行为并加入回归。
3. 取消期间保持 busy，旧 Task 完成后才接受新请求；已复现 cancel→新元数据保存被旧轮次覆盖的风险并加入真实 Service 回归。
4. 异步业务闭包明确 MainActor，确保返回后的 Store/UI 操作仍在主线程；Service 回归复现并验证修复。
5. 原集成测试加入异步准备等待，不删原订阅/恢复/读次数断言；SDK 编码仍由编译和协议核对覆盖，测试替身不等于无线运行。

原只读审查提出的字段结果覆盖、取消重入问题已处理。审查中按旧方案提出的“Profile 直接发送漏失效”不再作为新范围的修复目标，其相关钩子已撤销；审查结论不等同需求确认或真实设备验收。

## 8. 验证与交接

工作树：`feat/HDB-261020`，基线 HEAD `e00aa89b`，修改未提交。SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，本次未修改；本地 workspace 继续通过 `.local-sdk/` 覆盖，正式远端依赖未改。

本轮调整后验证：当前 12 个 `check_hdb_*.py` 脚本全部通过，覆盖配置模型、准备/订阅执行、真实 Store/Service 集成、配置路由、配置 Service 串行发送与取消重入、导入恢复、持久化、普通组生命周期、Zone 控制、显示、Space 创建、控制状态观察。跨功能准备失效脚本已随该策略移除，新增边界用例并入现有配置/集成/Service 测试。另运行 `check_sync_execution_session.py`、`check_sync_run_lifecycle.py` 均通过；Session 测试有 `default will never be executed` 编译警告。新增测试验证行为，未把源码字符串匹配当作设备证明。

本轮已完成 SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建，结果 `BUILD SUCCEEDED`（exit 0）；构建输出含未依赖 AppIntents 的元数据提取跳过提示。本地 SDK 路径再次核对正确，revision `8c5af55`、工作树无改动。DerivedData 复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`。本轮无 Simulator、安装或真机运行。本轮仅收敛共享逻辑，无品牌条件、资源或工程配置变更；前阶段四个新增源文件已核对五品牌归属，其他品牌构建仍为该新功能合入前检查项。

最短人工验收：

1. Saved Configuration Status 首行显示 Preparation；首次或 failed 记录 Apply 时先 Preparing，全部准备 ACK 成功并保存后才退订/订阅。准备失败显示原因、阻断该设备后续任务；成功后换/加 Zone 不重发固定参数，Restore 后重新准备。
2. 分别设置 Intensity、Soft Dimming、Time Delay，单播 Get 核对各 element；无关字段不重发。
3. Auto → Force_On → Force_Off → Auto，确认固件自动/手动状态转换与 100% 请求效果。
4. 两灯组播与混合 element 广播，核对目的地址、全部发送后的成功和 secondary 补发。
5. 离线仅保存两个元数据；取消发送后重进。普通 Profile/校准/退组不再因本次 HDB 准备维护而被拦截，也不再保证操作后 HDB 自动显示需准备。
6. 云上传、回读及导入导出保留新增字段；退出重进保持 pending/failed 供手动重试。

仍待外部验证：目标固件对 Infinite 编码、Vendor 与 LC 状态关系、设备掉电保持、实际 Occupancy、最终 UI 布局和云端 round trip。Trigger Zones 与 Failsafe 运行机制不在本次实施范围。

## 9. Force Off 提示模型未绑定：只读分析（2026-10-20 19:24）

本节为本次最新分析，不将前述阶段的构建、设备日志或测试结果视为本轮现场验证。当前 App 分支 `feat/HDB-261020`，HEAD `9c23a0e0`；开始时已有 `HDBConfigurationViewController.swift` 菜单调整，未触碰。SDK 映射仍为 `one-dev`，revision `8c5af55`，工作树干净。本轮只更新本文档，无 App/SDK 生产代码修改、构建或真机操作。

### 已证实的直接原因

`Lighting Configuration → Light Override → Set` 调用 `HDBLightingConfigurationService.set`。三种选项使用不同模型：

| 选项 | 消息 | 目标 SIG Model |
| --- | --- | --- |
| Auto | `LightLCLightOnOffSet(true)` / Unacknowledged | `0x130F` |
| Force On | `LightLightnessSet(65535)` / Unacknowledged | `0x1300` |
| Force Off | `GenericOnOffSet(false)` / Unacknowledged | `0x1000` |

Service 遍历目标设备的所有 element，通过 `HDBLightingZonePolicy.requiredTargets` 保留五类模型的全部实例。发送前，逐个对当前命令实际使用的模型调用 `HDBLightingMessages.model`；只要某个 `0x1000` 的 `boundApplicationKeys` 不包含当前 Space AppKey index，就抛出 `modelNotBound`，由 `HDBUIError` 显示用户报告的文案。

因此该文案说明 **App 当前本地模型信息中，至少一个被选中的 OnOff 实例缺少 Space AppKey 绑定**。它不是设备收到 Force Off 后返回的错误，也不表示所有模型都未绑定。此预检发生在配置持久化和发送之前，静态缺绑定的场景会整次拒绝；组播/广播只要一个目标设备的一个实例缺绑定，也会拦截全部目标。

SDK 的 `boundApplicationKeys` 从 Node 已知 ApplicationKey 与当前 Model 的 `bind` 交集取得。它不是一次设备实时查询；要区分设备确实未绑定与本地缓存缺失，必须核对该模型的现场绑定列表。Auto、Force On 成功只证明各自模型的这条路径可用，不能证明所有 `0x1000` 都已绑定。

### 上游不一致与为什么 Preparation/Zone 成功能共存

已证实 HDB 与当前 SDK 采用不同的实例范围：

- SDK `Node.onoffModel` 使用 `getFunctionModel(0x1000)`，按 element 顺序返回首个实例。
- SDK `supportModels` 只纳入这个 `onoffModel`，`getConfigMessageHandles` 对 `supportModels` 生成 AppKey Bind。快速配网及 App 后续配置/同步会调用该方法。
- 普通单设备 Off 的 `LightGroupControlCommandSender.setNodeOnOff` 也使用 `node.onoffModel`。
- HDB 的准备记录、Zone 订阅和 Lighting Configuration 则以全部相关模型实例为范围。
- SDK 的成功 Bind 回执只更新回执指向的 Model；不会因为另一个 element 或 LC Model 已绑定，就自动将所有 OnOff 记为已绑定。

当设备 primary element 上的 OnOff 已绑定，而另一个 element（例如 LC 所在 element）还有未绑定的 OnOff 时，现有配网/普通 Off 可以工作，HDB Force Off 却会在检查第二个实例时失败。前文记录过 26/28 双 element、各有一个 OnOff 的现场结构；这是支持该原因的历史结构证据，不能当成本轮设备的地址或绑定实测。

Preparation 只为 Vendor、LC、LC Setup 生成固定参数消息；OnOff 和 Lightness 的准备 `value` 为 nil，不生成消息。`prepare` 只校验这些实际消息目标的绑定，因此不会发现第二个 OnOff 缺绑定。Zone 操作发送 Subscription Add/Delete，没有补发 App Bind；订阅成功也没有覆盖这个遗漏。准备状态匹配检查只包含版本、状态、目标及固定值，不包含当前绑定情况，所以重复 Apply/Retry 不能保证修复缺绑定。

### 最小复现与证据边界

使用临时 Swift 夹具，载入未改动的生产 `HDBConfiguration`、`HDBLightingConfigurationPolicy`，提取原样的 `requiredTargets`、`HDBLightingMessages.model` 和 SDK `getFunctionModel` 执行。Node/Model/Key 由内存边界提供，构造 primary 26 的 OnOff/Lightness/Vendor 已绑定，secondary 28 的 LC/LC Setup 已绑定、OnOff 未绑定：

1. Auto 与 Force On 预检成功。
2. Force Off 稳定抛出 `modelNotBound`。
3. SDK 普通 Off 仍选中已绑定的首个 OnOff。
4. 全部具有准备值的模型绑定检查成功，没有检查 secondary OnOff。
5. 仅为夹具中的 secondary OnOff 补充绑定后，Force Off 预检成功。

夹具退出码 0，运行后已自动清理。它证明该实现路径可精确复现症状，不证明现场一定是 element 28，也不证明设备实际绑定表或无线控制效果。

现有 `check_hdb_lighting_configuration_service.py` 使用的 `HDBMeshTestBoundaries` 将 `HDBLightingMessages.model` 替换为只查找模型、没有绑定校验的实现；`HDBLightingTransportBoundaries` 又让所有模型都返回已绑定 Key。因此此前 Service 回归通过没有覆盖本问题，不需要重跑这些用例来确认它是否存在。

### 建议修复边界（未实施）

本小节为当时“全部实例参与 Force Off”前提下的建议，已由第 10 节用户明确的主 element 规则替代，不再执行补绑定方案。

保持既定“整台设备、全部相关实例”的范围，优先在 HDB Set Lighting Zones / Retry 的前置流程补齐当前 Space AppKey 的缺失模型绑定，复用现有 SDK ConfigModelAppBind、回执更新和保存机制。绑定保障应独立于“固定参数 Preparation 已 synced 可复用”的判定，否则已有设备仍会跳过修复；只补缺失项，不强制重发已完成固定参数，不改普通 Profile/普通组或全局 SDK 的模型选择策略。

Binding 失败或取消时不能把该轮 HDB 订阅/可控状态当作完成；成功绑定须保存到现有 Mesh 数据，退出重进后可复用。Lighting Configuration 保留发送前校验，不在点 Force Off 时偷偷进行额外配网。补充 DEBUG 诊断需包含 node/element/model、期望及已有 Key index，不输出密钥内容。

不建议只删掉绑定校验、静默过滤未绑定实例，或将全部实例收缩成首个 OnOff 来消除提示：这会掩盖现有“全部实例”契约与配网结果不一致的问题。若要改成“与普通 Off 完全相同的首实例控制”，需要另行确认需求，并同步审视 Zone 订阅、准备目标、组播/广播路由和历史记录，不能只改当前报错行。

针对修复应覆盖双 OnOff 部分绑定、全部已绑定时无重复绑定、已有 synced 准备的补绑定、失败/重试/取消、保存后重新进入，以及单播/组播/广播预检。该逻辑是共享 App 路径，无品牌条件差异；正式实现后按实际变更选择相关回归和 SunSmart generic iOS 构建。实际 Force Off、Force → Auto、组播和 secondary element 行为仍由设备验收证明。本问题目前不要求服务器或固件修改。

现场定点确认的最短证据：在 `HDBLightingMessages.model` 的 `modelNotBound` 分支读取 node address、target element address、model ID、Space Key index 和 `model.bind`，不读取或输出 Key 字节；如需核对设备实际状态，再通过该 element/model 的 Config SIG Model App Get/List 确认。现有提示未携带这些标识，因此本轮无法锁定现场具体实例。

## 10. Force Off 仅使用主 element（2026-10-20 19:28，已实施）

用户明确调整：Force Off 直接使用主 element 的 Generic OnOff。Lighting Zone 已对全部 `0x1000` 实例订阅目标组，包含主 element；Zone 页现有 Off 也发送 Generic OnOff 到该组地址，因此无需修改添加 Zone、准备参数、模型绑定或 SDK。

本轮在 `HDBLightingConfigurationPolicy` 增加命令目标选择，供 Service 绑定预检和路由共用。Force Off 只选择 `elementAddress == node.primaryUnicastAddress` 的 SIG `0x1000`；主 element 缺模型报 Unsupported，缺 Space AppKey 绑定仍拒绝，不回退 secondary。Auto、Force On 和其他配置保持原实例范围。

- 单播：只向主 element 发送一条 acknowledged Off。
- 组播：仅以各设备主 element 的 OnOff 作为模型及绑定前置条件，继续向现有 Zone 地址发送一条 unacknowledged Off。既有 secondary 订阅保留；若它本身已绑定并订阅同一组，也可能收到组播。本次不承诺设备端仅 primary 接收组地址消息。
- 广播：安全范围检查仍保留；允许时发一次 allNodes，不再补发 secondary OnOff；不允许 allNodes 时精确发送到各目标设备主 element。
- Preparation 匹配、保存字段、取消/重试和 ACK 成功判据保持原机制，已有全实例准备与订阅记录继续复用，无迁移或重新配网要求。

验证：先通过新增双 OnOff 夹具复现旧路由多发 secondary、旧 Service 被未绑定 secondary 拦截，再完成修改。配置 Service 夹具现在提取并执行生产 `HDBLightingMessages.model`，替换之前跳过绑定检查的替身，覆盖 secondary 未绑定仍可单播/组播/广播、primary 未绑定时零发送且不改变持久数据。策略夹具覆盖主 element 缺模型不回退、广播安全回退，以及 Force On 仍补发 secondary。

本轮 4 项回归通过：`check_hdb_lighting_configuration.py`、`check_hdb_lighting_configuration_service.py`、`check_hdb_configuration.py`、`check_hdb_integration.py`。SunSmartLocal / SunSmart / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO` 编译退出码 0，DerivedData 继续复用本工作树目录。共享逻辑无品牌条件、资源或工程配置差异，本轮未重复五品牌构建。

本次修改期间 HEAD 从 `6b2119a3` 前进至 `e94db57a`；本任务未执行 Git 提交或修改首页菜单。SDK realpath 仍为 `one-dev`、revision `8c5af55`，无 SDK 改动。未运行真机或云端联调。人工最短验收：同一已配置 Lighting Zone 的设备依次 Auto → Force Off → Force On → Auto，并分别确认单播、Zone 组播和广播的实际关灯及恢复自动行为。

## 11. Lighting Configuration 广播模式下的实际发送方式（2026-10-20 19:43）

页面选择 Broadcast 不代表所有属性都发送到 `0xFFFF`。当前实现按目标模型所在 element 路由：允许广播时，主 element 上的目标模型使用 allNodes 广播，非主 element 上的目标模型逐一单播。若某条命令的目标模型全部位于非主 element，该命令只发送单播，不额外发送广播。

以前文记录的设备结构为例，主 element 提供 Generic OnOff / Lightness，非主 element 提供 LC / LC Setup；在通过广播范围检查的前提下，实际发送如下：

| 页面属性 / 选项 | 目标模型 | Broadcast 模式下的实际发送 |
| --- | --- | --- |
| LightingControl → Auto | LC `0x130F` | 逐设备单播到 LC 所在的非主 element |
| DimIntensity | LC Setup `0x1310`，属性 `0x002F` | 逐设备单播到 LC Setup 所在的非主 element |
| BrightIntensity | LC Setup `0x1310`，属性 `0x002E` | 同上 |
| RampUpTime | LC Setup `0x1310`，属性 `0x0037` | 同上 |
| RampDownTime | LC Setup `0x1310`，属性 `0x0036` | 同上 |
| HoldTime | LC Setup `0x1310`，属性 `0x003C` | 同上 |
| LightingControl → Force On | Lightness `0x1300` | 主 element 使用 `0xFFFF`；若非主 element 也有 Lightness 实例，另补单播 |
| LightingControl → Force Off | 主 element 的 Generic OnOff `0x1000` | 发送一次 `0xFFFF`，不补发非主 element 的 OnOff |
| FailsafeDelay、InstallDate | 无 Mesh 写入 | 仅保存数据，不发送 Mesh 消息 |

上述 Auto 和五个配置属性的单播行为取决于设备 Composition，并非按属性固定限制。如果 LC / LC Setup 位于主 element，对应命令也可以使用广播；混合设备结构则可能同时包含一次广播和多个非主 element 单播。

### 广播范围检查与回退

`HDBLightingConfigurationService.set` 检查网络内非 provisioner 节点：若当前目标集合之外的节点，其主 element 存在本次命令对应的 SIG 模型，并绑定本次使用的 AppKey，则不允许发送 allNodes。此时本次所有实际 Mesh 写入均退回目标 element 地址逐一单播，Force Off 也改为向各目标设备主 element 单播。该检查依据 App 本地模型及绑定信息，不是设备实时查询。

### Broadcast 与 Unicast 的命令及 ACK 差异（2026-10-20 19:46 更新）

预期及当前实现一致：**显式选择 Unicast 时，实际 Mesh Set 必须使用 acknowledged 命令，并等待、校验设备响应；选择 Broadcast 时，即使路由到单播地址，也继续使用 Unacknowledged 命令。** 目的地址和是否等待 ACK 是两个独立维度，不能仅凭目的地址将 Broadcast 的逐设备发送等同于页面 Unicast 模式。

| 页面模式 / 路由情况 | 实际目的地址 | Set 消息类型 | 完成依据 |
| --- | --- | --- | --- |
| Unicast | 所选设备的目标 element 单播地址 | Acknowledged | 等待各条请求的响应并校验匹配，依据为 `acknowledged` |
| Broadcast，主 element 广播 | `0xFFFF` | Unacknowledged | 全部发送调用成功完成，依据为 `sent`，不等待设备 ACK |
| Broadcast，非主 element 补发或全部位于非主 element | 各目标 element 单播地址 | Unacknowledged | 同上 |
| Broadcast，范围检查不允许 allNodes 而回退 | 各目标 element 单播地址 | Unacknowledged | 同上 |

以 LightingControl → Auto 为例：Unicast 使用 `LightLCLightOnOffSet(true)`，收到 `LightLCLightOnOffStatus` 后检查 `targetState ?? isOn` 是否与请求一致；Broadcast 使用 `LightLCLightOnOffSetUnacknowledged(true)`，不执行该 ACK 校验。Force Off、Force On 和 LC Property Set 也按页面 scope 选择对应的 acknowledged / unacknowledged 版本。FailsafeDelay、InstallDate 仅保存数据，不适用 Mesh ACK 要求。

因此 Broadcast 记录为 `synced` 时，含义仍受 `basis=sent` 限定，不能据此证明每台设备已应用配置。Unicast 的响应确认也不等于实际照明效果或后续自动运行已完成验收。

Broadcast 模式的读取入口显示 Saved Values，仅返回本地保存值，不向设备发送 Get。

### 本次 Broadcast Auto 日志证据

用户提供的 SDK 发送日志中，4 条 Auto 消息均为 `LightLCLightOnOffSetUnacknowledged(isOn: true)`，opcode 为 `0x829B`；Network PDU 的 seq 3105～3108 分别对应 `dst=0x001F / 0x0022 / 0x0025 / 0x0028`。该日志片段内没有 Auto 发往 `0xFFFF` 的记录，证实本次可见的 Auto 控制全部为单播地址、Unacknowledged 命令。

后续发往 `0x001D / 0x0020 / 0x0023 / 0x0026` 的 `LightCTLGet` 是独立状态查询，其 `LightCTLStatus` 不是上述 Auto Set 的 ACK；HTTP 同步成功和云端 readback confirmed 同样不构成设备控制 ACK。Auto 目标地址分别比 CTL 查询地址大 2，与 LC 位于后续 element 的结构相符，但仅凭这些地址不能确认 Composition，也不能区分此次全单播是由非主 element 路由还是广播范围检查回退造成。

依据：`SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift` 的 `writes` / `targets` / `route`、`SunSmart/Main/Space/HDB/Model/HDBLightingConfigurationService.swift` 的 `set` / `get`、`SunSmart/Main/Space/HDB/Model/HDBLightingMessages.swift` 的消息选择、响应校验及页面入口。本节基于当前工作树代码和用户提供的 SDK 日志核对；未重新采集 Composition 或独立无线抓包。本轮仅补充文档，未修改业务代码、运行构建或自动执行真机验证；显式 Unicast 的 ACK 行为已核对代码，本次日志未提供该模式的现场执行证据。
