# Site Time Zone 夏令时问题分析与解决方案

## 2026-11-05 实施：Site 入口刷新、Space 校时与下一次 DST 下发（App 完成，待设备验收）

本节对应用户新增需求：进入 Site 更新 DST 信息；进入 Space 使用 Site current offset 校时，并向设备发送下一次切换。**用户已确认按本版本实施；App 改动与自动化验证已完成，设备/真实 API 验收尚未执行。** 下文历史记录中的“不增加未来 TimeZoneSet”是上一轮范围，本轮已扩展到 App 侧未来计划下发。

### 实施清单（本轮执行记录）

执行：使用 writing-plans / executing-plans / TDD，在现有 linked worktree 单人实施，无子代理、不提交。本文顶部最新需求为 Spec。Tech Stack：Swift/Foundation/UIKit、既有 Store 和 Nordic SDK。目标：保持纯 IANA 保存，缺失/无效时区手机回退，Space 会话自动校时与未来计划广播。

- [x] Task 1：`SiteTimeSetMessageFactory` 增加可选快照、语义目标和下一次切换参数；`SiteTimeZoneValue` 提供身份有效性与原值保留入口。扩展 `SiteTimeSetMessageFactoryTests`，先复现 missing/invalid 回退失败，再覆盖有效快照、暂时离线、跨切换、无未来计划和半小时偏移。沿真实 Site 属性解析/导入检查原值保留与回执保护。
- [x] Task 2：在现有工厂发送边界生成 TimeZoneSet，复用 SDK TAI 转换；广播发送当前/未来两条，单设备 TimeSet 成功后追加补充计划，不改变原任务的 TimeStatus 成功含义。新增离线传输测试，编译真实 SDK TimeZoneSet/Status/TAI 序列化，验证未来参数、零计划、取消和过期拒发。
- [x] Task 3：新增 `SpaceClockSyncCoordinator.swift`，Foundation 可注入协调器负责观察回调、异步 prepare 合并、连接代际与发送目标去重；UIKit 适配负责 Site/Space/权限/网络上下文。Space 生命周期接入，移除 Devices 首连独占的自动广播。新增真实 Store + 异步事件行为测试，验证失败恢复、初始已连接、晚响应、退出、去重、目标变化；新增文件统一加入六品牌。
- [x] Task 4：核对 Gateway Fast Add、Information 与其他校时使用方的前置 guard，统一从共享准备入口取得 Site/手机解析结果。运行 `check_site_dst.sh`、工厂/传输/调用方、Site Props 与受影响网关/Timed 回归，检查项目与六品牌归属，再串行 generic iOS 构建受影响品牌；自行复核并交付人工验收步骤。

Pre-flight：Task 2/3/4 共用 Task 1 的 `prepareClock(siteID:)` 与 `resolve` 返回值，手机分支不应被可选 snapshot guard 拒绝；取消与晚回复必须在发送边界二次验证。持久化仅保留原始非法字符串以供降级，不能把本次手机解析写回 Site。

Ruling：实施开始 SDK HEAD 未变，但已有另一任务的 Scheduler 未提交修改（含 MessageManager/ProxyCommand 等）；本任务不写 SDK，不覆盖或清理它们，测试与构建记录当前 SDK 来源。已有钩子若不足，先证明具体缺口再决定隔离方案。

Ruling：单设备现有流程以 TimeStatus 判当前校时成功；未来计划作为其有效回复后的补充发送，不新增强制 ACK 依赖，避免不支持 future transition 的旧固件使现有日程/初始化整体失败。补充发送仍须校验来源/目标/会话有效性；未来计划实际生效由独立回读与运行验收证明。

### 最新需求确认：保存契约、App 关闭、旧版兼容及广播能力

1. **保存契约保持当前分支不变。** 用户已明确选择“保留当前分支的纯 IANA，不再调整格式”。当前 `SiteTimeZoneValue.storageValue` 返回 `ianaId`，`SiteData.timezone` setter 会规范化旧后缀，SiteProps 更新与 Site 导出均使用 storageValue。此行为已在提交 `030a6d41` 引入，本次不恢复旧的 `IANA (UTC±HH:mm)`、不新增结构化字段、不改服务器接口。下一次切换的四字段仍属于现有 App 快照缓存，不能把动态 offset/DST 展示字符串写回 timezone。
2. **功能目标是 App 未运行时也能完成预置的下一次 DST。** App 在可连接时先设置当前时间，再下发未来切换；设备收到并正确实现该状态后，转换点不需要 App 在线。这是产品目标，需要设备运行证据才能宣称达成。App 不运行不等于设备断电；掉电保持当前时钟/未来计划、离线设备漏收以及再下一次计划续期分别验收。当前 Space 的广播不覆盖未连接的其他 Spaces 或所有 Site 网关；这些网络仍需各自下发机会或网关已具备的独立同步能力。
3. **解析失败按“没有可用 Site 时区”进行校时回退。** 新版本沿用用户要求，使用手机当前 offset；仅是运行时的校时来源回退，不清空服务器字段、不自动上传 null、不把未解析成功当成属性同步成功。已发布旧 App 无法通过本次修改获得新行为。只读核对历史 `5511abc6`：旧解析器要求 `IANA (UTC±HH:mm)`，其 TimeSet 工厂确实对 nil/空白/解析失败执行 phoneFallback；但该历史提交不是已确认的所有上架包基线，而且属性解析可能在到达工厂前就失败，故不保证所有旧版完整链路均能回退。保持当前纯 IANA 是已确认决定；旧版兼容仍应针对实际版本验收。即使成功回退，也只是降级：手机与 Site 异地时可能校错时区，不能宣称旧版支持 Site DST。
4. **广播发送不要求先按型号筛选，能力验收仍要区分。** 按用户倾向继续推荐 A，不新增型号白名单作为发送前提。支持模型且能解密/接收的目标才可能处理命令；广播不会让不支持 TimeZoneSet 的固件自动具备能力，也不证明每台已经收取、到点执行或掉电保留。App 可先完成统一广播；型号/固件兼容性由用户或对应团队用受控设备验收，不要求本任务修改固件。

标准依据：Time Setup Server 收到 TimeZoneSet 后设置未来 offset 与切换 TAI，Time 状态到达该时刻时执行切换；这支持“预先配置、App 离线时执行”的设计，但不证明具体产品实现和掉电行为。[Bluetooth Mesh Model 1.1，5.1.1.7.1、5.3.2.2.2](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。

当前 App 的 `SitePropsAPIClient.timezoneValue` 对部分非法字符串会返回失败，使整个属性响应失败。实施手机回退时须检查这一前置入口与导入/持久化，确保“没有可用时区”的运行时分类能到达校时工厂，同时保留原始配置、字段提供状态和 pending/回执保护；不能只改工厂或一律吞掉整份响应错误。正常纯 IANA 保存格式不变，字段级解析失败处理属于本次回退所需的关联修复。

**用户追加的已定规则：Site 没有时区，或者 Site 时区无效时，仍使用手机时区校时。** 该规则覆盖本文旧方案中针对上述情况的“拒绝校时/不回退手机”要求；用户本次补充不等于批准实施完整方案。

校时来源按以下规则区分：

| 状态 | 已实施行为 |
| --- | --- |
| Site 时区有效且有可用服务器快照 | 使用 Site 的 current_offset；有下一次切换时下发 Site 计划 |
| Site 存在，但 timezone 缺失、空白、格式非法或已确认不是有效时区 | 使用手机在实际发送时刻的当前时区偏移校时，不依赖 Site DST 请求成功 |
| Site 时区有效，但网络超时、请求失败、响应损坏或缓存已过期 | 与“配置无效”区分；暂沿用原缓存/重试规则，无可用快照时待重试，不因临时网络故障切换到可能异地的手机时区 |
| Site/Space 已删除、身份不匹配、权限撤销或会话失效 | 仍取消发送；手机回退不能绕过归属和权限校验 |

实现注意：当前 `SiteTimeZoneValue.validIdentifier` 仅检查字符串语法，不能据此认定 IANA 实际存在。识别不存在的时区应结合项目已有时区目录与明确的服务器有效性结果；手机系统不认识的 IANA 可能是系统数据库较旧，不能仅凭此否定服务器已确认的有效时区。网络失败/通用错误不能视作“服务器确认时区无效”，缺少明确错误契约时补诊断而不猜测。

手机回退属于本次明确要求；未来计划的处理建议为：不复用旧 Site 的 next_switch/switches_to，不擅自扩展成查询或推算手机下一次 DST；当前校时后用相同手机 offset 和零切换时间覆盖旧未来计划，防止设备随后执行旧 Site 计划。手机时区/偏移改变或 Site 配置恢复有效时，重建发送目标。手机偏移也须可被 Mesh 编码，不可静默取整。

### 1. 实施前结论与证据（保留问题基线）

| 用户问题 | 当前源码结论 | 证据 |
| --- | --- | --- |
| 进入 Space 会同步日期时间吗 | 正常路径会：Devices 子页首次收到 Mesh 已连接通知后延迟 3 秒；Visitor 跳过。不是“只要进入就必定完成” | `DevicesViewController.addObservation()`、`syncTimeNodes()`；`SpaceViewController` 创建 Devices 子页并连接 Space 子网 |
| 使用 Site current offset 吗 | 是。`prepare(siteID:)` 后以服务器/有效缓存 `current_offset` 创建固定偏移 TimeZone，再生成 TimeSet；不使用手机时区、旧 Site 字符串后缀或 switches_to 作为当前 offset | `SiteTimeSetMessageFactory.resolve`、`broadcast`；SDK `ExplicitTimeSetInput.make` |
| 不进 Edit 就不能更新 DST 吗 | 不是。Site 页已有 `viewDidAppear → observeSiteTimeZone/refresh`；Space 校时发送前也会 prepare；其他校时入口共用服务 | `SiteViewController.swift:244`、`:926`；`DevicesViewController.swift:449`；`SiteTimeZoneService` |
| 每日接口是否需要前移到 Site | 当前已经具备该行为，应保留并回归，不新增另一套 Site 请求/缓存 | `SiteTimeZoneStore.refresh` 根据快照自然日/切换点判断，合并同 IANA 请求；同日成功缓存不重复网络请求 |
| 是否发送下一次 DST | 没有。App 中没有 TimeZoneSet 构造/发送调用；nextSwitch 目前用于展示和缓存失效。SDK 已有 TimeZoneSet/TimeZoneStatus | App 全量 Swift 调用检索；SDK `TimeZoneSet.swift` / `TimeZoneStatus.swift` |

当前校时广播目的地址为 `.allNodes`（0xFFFF），在当前 Space 网络/密钥上下文发送；不能解释成已经同步整个 Site 的全部 Spaces，也不能解释成所有设备都回执成功。`lastSyncDateTimestamp` 在入队后即写入，不能作为逐设备确认记录。`SpaceData.needSyncDate` 虽有 24 小时判断，当前没有调用方，不能据此宣称已有每日自动校时。

关键缺口：

- `firstConnectionNetwork` 在请求、校时完成前即置 false；失败后，同一 Devices 页面普通重连不再调用自动校时。KVO 仅 `.new`，进入时已经连接的情况也没有在此入口主动评价现态。
- Site 页 `viewDidDisappear` 移除 DST 观察者。Space 本身没有持续订阅当前 IANA；若没有其他观察者，长时间停留 Space 时，服务每秒检查/前台恢复不会自动刷新这个时区。即便其他消费者刷新了缓存，也没有 Space 校时订阅把新目标发给设备。
- 广播排队只证明尝试发送；旧页面、不同 Space 子网、账号/权限变化及请求跨切换点，都要在发送时核对，不能只看 Site ID 和 Mesh 对象。

有效 Site 时区的服务规则保持：按 IANA 的当地自然日成功请求一次；跨 next_switch 可额外刷新；失败允许后续明确事件重试，不按每秒 tick 无限重试。跨日失败而旧快照未过 next_switch 可继续使用；跨切换点失败或无有效缓存时停止依赖该 offset 的发送，不由 App 自行猜测新 DST。Site 时区缺失/无效则走上述手机回退分支。当前源码仍直接返回 nil，尚未实现该补充要求。

### 2. 方案与取舍

**推荐 A：沿用广播校时，追加未来切换广播，补齐 Space 生命周期。** 每次有效同步由当前 1 条 TimeSet 增为 2 条逻辑消息（不含 SDK/网络层重传）；不新增逐设备持久化确认表。符合当前自动校时行为，保持进入 Space 的交互成本较低。它表达“向当前 Space 全节点发送”，不承诺每台收到；离线节点依靠后续重入/重新连接/初始化补发。

备选 B：枚举当前 Space 所有具备 Time Setup Server 的目标 Element，逐一发送 TimeSet + TimeZoneSet 并校验回执。N 个目标约为 2N 条请求及对应响应（不含重试），能区分部分失败，需维护目标集合、成功/待重试状态和会话恢复，设备多时耗时增加。若产品要求“全部设备逐台确认成功”，应选 B，不能用 A 的广播时间戳替代。

用户已表达统一广播的方向，以下开发范围继续按 A 展开；用户随后已明确授权实施。B 仅保留为逐台确认要求出现时的备选，不重复要求用户在当前阶段建立型号白名单或选择两套并存机制。

### 3. 推荐方案的行为与改动范围

1. **保留 Site 入口刷新。** 复用 `SiteTimeZoneService/Store`，不移动或删除 Edit/Create、直接校时的 prepare。Site 提前准备缓存，Space 发送前仍需检查，避免页面间等待跨过切换点。成功缓存的自然日规则不变，不把每次进 Site 变成强制 HTTP 请求。
2. **由 Space 生命周期拥有时钟同步会话。** 在 Space 页面建立轻量协调器，持有当前 IANA 观察和会话 token；Devices 页的 firstConnectionNetwork 仍可服务其他首次连接业务，但不再作为时钟同步唯一门禁。Space 入场主动评价连接现态，连接就绪仍保留原 3 秒避让；首次失败后可在 Mesh 重连、网络恢复、前台恢复、再次进入以及有效快照到达时重新评价。跨日/切换点直接复用 Store 通知，不新增一套每秒定时器。
3. **事件合并而非反复广播。** 同一会话中用 IANA/currentOffset/nextSwitch/switchesTo 构成语义目标；仅 requestedAt 变化不代表设备目标变化。相同目标成功发起的一轮不被每次通知重复排队；新连接会话、新增/重新初始化设备、目标变化或之前未能入队才允许补发。当前失败目标保留待尝试，失败重试仅由上述外部事件驱动，不在失败回调内递归 refresh。这里的“发起”仅表示广播尝试，不登记设备成功。App 重启/重新进入重新评价，已有 DST JSON 缓存继续复用；不增加数据库 schema。
4. **共享工厂生成当前时间与未来计划。** 扩展 `SiteTimeSetMessageFactory` 的消息组能力，显式区分 Site 快照与手机回退来源；手机回退不得伪造 SiteTimeZoneSnapshot。Site 分支以同一合法快照准备两条消息；手机分支按发送时刻取手机 offset 并覆盖旧计划。发送前逐条校验绝对时间、来源、语义目标和会话上下文；排队跨 nextSwitch、手机时区变化、Site 配置改变时废弃旧组，重新解析后重建。当前 offset 相同但下一次切换变化，也必须更新计划。各调用方不得继续用 `prepare(siteID:) != nil` 或必须存在 IANA 的前置 guard 阻断合法手机回退，须共同接入来源解析结果；现有 source/phoneFallback 类型可复用，不影响 Site 时区持久化值。
5. **覆盖同类设备入口。** Space 广播是主入口；普通设备初始化/重新配置、网关 Fast Add/现场校时要能够从共享工厂取得未来计划，避免在本轮广播后新增设备漏配。逐项核对 `Node+MessageHandles`、`MeshNetwork+SunSmart`、`SyncDevicesCellModel`、`GatewayFastAddTimeInitialization` 及现有网关/Information 校时调用方；Group/Timed 的 TimeSet 调用一并审计，保留原有校时失败阻止依赖日程的语义。不在每个日程条目后机械追加重复计划，不把未来计划超时冒认成已有 TimeSet 的回执。
6. **权限、退出和网关边界。** 自动写设备仍仅 Owner/Editor；校验账号/区域、Site ID、Space ID、当前子网及 AppKey、页面会话和最新权限。退出/切换/降权使待发送失效；合法晚响应可进入所属 IANA 缓存，但不得唤起旧 Space 发送。Site 查询本身不触发全 Site 网关云端校时，`/sitespace/gateway/datetime/update` 的 body、触发范围和状态语义保持原契约。

新增协调器仅管理“当前 Space 的观察、触发合并、待尝试和取消”，原因是现有 Devices 首连布尔值不能表示这些状态；不新建全局任务框架或持久化调度系统。多消息接入保留现有队列与 SDK 发送有效性钩子；实施时若现有发送失败回调不足，只补必需的 App/SDK 边界，不通过写成功时间戳掩盖失败。

### 4. SIG Mesh 参数与兼容边界

SIG 的 Time Zone Set 用于设置未来 offset 与生效 TAI 时间，标准消息有 Time Zone Status 响应；TimeSet 设置当前时间，不等于设置下一次切换。[Bluetooth Mesh Model 1.1，5.1.1.6–7、5.2.1.5–6、5.3.2.2](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。

| 顺序/条件 | 消息与参数 | 目标、确认和失败 |
| --- | --- | --- |
| 有效当前快照 | TimeSet；date 为实际发送时刻，tzOffset=`current_offset`；TAI/Delta 复用 SDK `ExplicitTimeSetInput` | A 保留 0xFFFF 广播和当前 Space 密钥；有响应不代表全员确认 |
| 有合法未来 next_switch/switches_to，无论 is_dst true/false | TimeZoneSet（0x823C）；new offset=`switches_to`；taiSeconds 为 next_switch 绝对时间转 Mesh TAI 秒 | A 追加 0xFFFF 广播；不可把有 ACK 定义的消息称为另一个 UNACK opcode。无全员 ACK 汇总；局部丢包/离线在后续事件补发 |
| 成对 null，没有下一次切换 | 在当前 TimeSet 后发送 TimeZoneSet(new offset=current_offset, taiSeconds=0) | 覆盖旧未来计划，避免从 DST 地区改到无下一次切换地区后仍执行旧计划；固件必须验证该行为 |
| Site 时区缺失或已确认无效 | TimeSet 使用发送时刻手机当前 offset；建议追加 TimeZoneSet(new offset=同一手机 offset, taiSeconds=0) 覆盖旧计划 | 不要求 Site DST 快照；不下发旧 Site 的未来计划；仍校验 Space/权限/会话 |
| 有效 Site 时区的快照缺失/过期、切换时间已到或响应字段不能编码 | 不发送依赖该快照的时钟消息组；保留待尝试 | 不把临时请求/数据异常判成 Site 时区无效，不改写 API 快照推算下一季 |

转换复用 SDK：`Mesh TAI = floor(nextSwitch.timeIntervalSince1970 - 946684800 + MeshTimeConversion.taiUTCOffset(at: nextSwitch))`。先校验有限值、2000 年之后、40 bit 范围及精度，再调用带 precondition 的 API；不可把 Unix 秒直接写入，也不可再次叠加当前/目标时区 offset。时区字段按 15 分钟编码，验证 current/switches 均可编码，支持半小时 DST，不写死增减 60 分钟。DST 本身不要求另发闰秒用的 TAI-UTC Delta Set。

目标能力：Time Setup Server（SIG Model ID 0x1201，与 Time Server 0x1200 区分）。A 沿用全节点广播，能够实际处理的 Element/品牌/固件范围需验证；没有该模型的设备不能通过 App 增加命令获得能力。单播入口发到实际承载该模型的 Element 单播地址，含 Primary 或其他承载 Element；若采用 B，枚举全部匹配 Element，不能只用返回第一个匹配项的 `node.timeSetupModel`。不更改设备订阅、绑定或凭据来扩大本次广播范围。

下一次计划只有一条，不是永久 DST 日历。App 关闭后设备能否到点执行、断电是否保留、完成后能否获取再下一次，属于固件/网关能力。即使 App 实现本方案，长期再不访问该 Space 且无网关续期，也不能保证无限期自动 DST。

外部验收由固件/网关团队负责：确认 0x823C/0x823D、时间基准、空计划覆盖、模型位置、到点执行与掉电行为；核对网关是否会把旧 offset 重新覆盖到节点。服务器团队维持现有四字段契约与下一次切换准确性，不需要本任务修改服务器。App 可独立开发；宣称无人值守跨 DST 前，上述设备与网关验收是发布依赖。

### 5. 开发步骤与验证

已按用户确认的 A 执行以下步骤并维护本文，不另起重复计划：

1. 增加行为用例复现首连失败后重连不补发、长驻 Space 跨切换不触发的问题；用可注入时钟、真实 Store/Codable 和可控连接事件覆盖生命周期，不只断言源码字符串。
2. 增加共享时钟消息组与真实 TimeZoneSet 编解码测试，覆盖标准时/DST 两种当前状态、30 分钟差值、带 offset 的 ISO 时间、null 清除、错误字段、排队跨切换点/目标变更及迟到回执。新增缺字段/空白/非法及不存在时区的手机回退、服务器确认有效但手机不识别的 IANA、有效时区网络失败不误回退、手机时区变化、Site 配置恢复、旧计划清除及同类调用方前置 guard；更新现有“缺失时区必须返回 nil”的旧断言，不以放宽断言替代真实发送行为验证。
3. 接入 Space 协调器并替换旧自动校时触发；覆盖进入时已连接、延迟内退出、断网失败后恢复、同日去重、跨日目标不变不重复发、nextSwitch 改变、账号/权限/子网切换。
4. 接入上述初始化/重试同类入口，验证新设备、失败/取消、Fast Add 真正发送边界；保留 Group/Timed 原有依赖规则。验证非法时区经过实际 Site 属性解析/保存/重载后仍可执行手机校时回退，且不会清空原始云端字段或错误清除 pending；核对已确认的纯 IANA Site 保存与云端请求格式未被改变。
5. 运行 DST、TimeSet 工厂/调用方、传输边界及实际触及的 Group/Timed/网关测试；核对本地 SDK 映射后构建 SunSmart Debug generic iOS。新增共享文件核对六品牌归属，若新增 target 成员或公共 SDK API带来跨品牌集成风险，合入前补全部受影响品牌。无 Simulator/自动真机，不 commit/push。

人工最短验收：手机设为与 Site 不同的时区，不打开 Edit，进入 Site → Space → 连接灯具；读取当前 TimeStatus 和 TimeZoneStatus，与 current_offset/switches_to/next_switch 对照。分别覆盖当前标准时但有下一次 DST、当前 DST、无下一次切换；用受控测试时钟/固件跨切换点，完全关闭 App，核对设备实际 offset 及日程动作。再单独做断电重启，确认时钟和未来计划保持/恢复情况，不能用前一个不断电用例替代。验证首次断网后恢复、设备离线后重进、新增设备、改 Site 时区后的旧计划清除；有网关时核对未被反向覆盖。记录型号、固件版本、广播接收/状态回读和实际切换结果，作为能力发布依据，不作为 App 发送白名单前置条件。

追加手机回退验收：Site timezone 缺失/空白/无效时，断网仍能按手机当前 offset 校时；变更手机时区后重入更新；Site 恢复有效时区后重新使用 Site current_offset。检查旧未来计划已覆盖，且有效 Site 单纯断网没有误切到手机时区。Site 不存在、权限撤销仍不能下发。

### 6. 本轮实施结果与交接（2026-11-05 14:15 +08）

**已完成 App 开发，尚未验证真实 API、BLE、UIKit 生命周期与设备到点切换。** 本轮没有修改固件/服务器，没有 commit/push。

实现结果：

- 保留当前纯 IANA 保存/上传契约。无效原始字段经 Site Props、实际 SQLite 保存/重载、导入和导出得以保留；运行时手机 offset 不写回 Site。时区识别结合手机系统、项目目录、已有服务器快照；系统不认识但服务器已确认的 IANA 仍走 Site 分支。缺失/空白/非法或三者均不认识的身份走手机回退，有效 Site 的网络错误不触发手机回退。
- Site 入口已有按需请求与每日缓存继续复用。Space 自己持有观察与连接会话：已连接入场、3 秒等待、重连、网络恢复、前台恢复、快照更新及新增节点均重新评价；退出/后台撤销旧会话。相同当前/未来目标去重，仅 requestedAt 改变不重复广播；失败不会递归请求。没有新增持久化任务表或计时器。
- 每轮自动同步顺序为 TimeSet → TimeZoneSet，目的地址均为当前 Space 的 0xFFFF。当前 offset 与下一次切换取同一有效来源；成对 null 或手机回退时以当前 offset、TAI=0 覆盖旧未来计划。未把广播入队写成逐设备成功时间戳。
- Gateway/Information/Fast Add/普通初始化及 Group/Timed 共用准备或发送边界。单设备有效 TimeStatus 后追加同 Element 的 Time Setup Server 补充计划，不把未来 ACK 作为已有任务成功的新增条件。普通 SDK 回执 validator 在来源匹配之前运行，因此补充发送延后到 SDK 已记录匹配成功之后；重复回调只入队一次。调用方完成不会误取消刚排队的补充计划，节点移除、Site 变更、网络/AppKey 变化仍拒发。
- 新增 `SpaceClockSyncCoordinator.swift` 纳入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六 target。无 UI 文案/资源变更。

代码与依赖：

- 工作树 `feat-daylight-saving-261024`，分支 `feat/daylight-saving-261024`，HEAD 保持 `2354ac91db5f02820249b860dcbf08964477fe6a`；本轮 App/测试/本文改动未提交。
- `SunSmartLocal.xcworkspace` 映射 `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `4b4c0f56fa3e686dfb856923f8e90b0eae95b0e8`。实施开始 SDK 已有其他任务的 Scheduler 未提交差异；本任务未写 SDK。离线传输夹具仅补这些新增类型的边界 stub，不改其实现。构建依赖该本地 SDK 状态，不表示远端 release 已具备/发布全部钩子。

验证记录：

| 范围 | 命令/结果 | 实际覆盖边界 |
| --- | --- | --- |
| DST Store/日期/缓存 | `bash scripts/check_site_dst.sh` 通过 | Foundation、JSON/Codable、自然日和切换点；非真实 API |
| 来源与手机回退 | `zsh scripts/check_site_timeset_message_factory.sh` 通过 | 无效/缺失、有效 Site 无缓存暂停、服务器确认但系统不认识的 IANA、手机变更、跨切换失效 |
| 自动校时会话 | `bash scripts/check_space_clock_sync.sh` 通过 | 可注入生命周期 + 真实 Store/磁盘缓存/异步回调；重连、长驻跨 DST、迟到、去重、下一次计划变化、强制新设备补发、权限拒发；UIKit/KVO 本身未运行 |
| 消息/实际发送边界 | `python3 scripts/check_site_clock_transmission.py` 和 `python3 scripts/check_site_dst_transmission.py` 通过 | 真实 App 工厂、SDK handle/TimeSet/TimeZoneSet/TAI/序列化、普通/Fast Add 发送边界；Model/网络/无线传输为 stub，回执记账为可控边界 |
| 属性与持久化 | `bash scripts/check_site_props.sh`；`python3 scripts/check_site_hdb_persistence.py /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` 通过 | 真实解析、导入/receipt 代码摘取和真实 SQLite 重启；新增无效 timezone 原值保留/无伪编辑；网络/UI/Mesh 分配为边界 |
| 同类校时入口 | `zsh scripts/check_site_timeset_call_sites.sh`、`bash scripts/check_gateway_information_time.sh`、`bash scripts/check_light_information_time.sh`、`zsh scripts/check_timed_schedule_time_sync.sh` 通过 | 工厂调用约束、网关/灯具 Information/Fast Add 与 Timed 既有回归；静态契约不代替真机 |
| 网关整套回归 | `bash scripts/check_site_sync_gateways.sh` **非全绿** | 首项 `SiteGatewayHeaderLayoutPolicyTests.swift:193` 的 “Keep equal shares with a 112 pt minimum” 失败；测试与生产文件均和 HEAD 相同，提取 HEAD 两文件独立编译可复现。未修改该无关布局；去掉首项后单独运行原脚本其余部分全部通过 |
| 工程 | `plutil -lint SunSmart.xcodeproj/project.pbxproj`、`git diff --check` 通过 | 新源文件六品牌归属与格式 |
| generic iOS 编译 | 六 scheme 串行 Debug/iphoneos 构建退出码均 0；LogStoreManifest 六条记录均 0 error | SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart；没有 Simulator/真机安装。存在原有资源重名、弃用 API 等警告；部分输出出现 “failed with exit code 0” 诊断，但最终退出码和构建记录均成功 |

构建命令模板：`xcodebuild -workspace SunSmartLocal.xcworkspace -scheme '<scheme>' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-clock-sync -quiet CODE_SIGNING_ALLOWED=NO build`。最终生产代码改动后已完成六品牌构建；后续只新增离线回归与更新本文，没有继续改变生产代码。

人工验收按第 5 节执行：重点是异地手机下进入 Site → Space 的当前 offset/未来计划回读，手机回退，App 完全关闭后的转换点，以及单独的掉电重启。TimeStatus 正常、HTTP 成功或广播发送不能代替“所有设备持久化并执行未来计划”的证据；长期无人进入且网关不续期仍只保证已预置的下一次计划。已有布局回归失败独立保留，不以本轮扩大修改范围。

---

## 2026-11-04 更新：服务器 next-transition 接入方案（已确认，App/SDK 实施完成）

用户已确认按本文范围实施，并补充服务器负责 DST 处理，`is_dst` 直接表示当前是否夏令时。App 按响应四字段执行展示与当前 offset 解析，不自行推算/翻转 DST；旧云端校时 API 保持原有契约，真实网关回读列为运行验收。

本节记录 2026-11-04 已实施方案，替代后文 2026-08-20 历史分析中的「系统 IANA 规则作为主要 offset 来源」「旧字符串 offset 回退」「继续上传带 offset 的字符串」等建议。后续变更以本文顶部 2026-11-05 追加方案及用户补充为准，尤其是 Site 时区缺失/无效时恢复手机时区回退。历史分析保留用于说明演进，不作为本轮实施依据。

初始分析阶段仅做只读核对；用户随后已确认实施。当前实施结果与验证进度见下方执行记录，未操作真机、服务器或固件。

### A. 结论、已确认规则与剩余契约

需求方向合理：Site 持久化稳定的 IANA 身份，服务器响应提供当前 offset 与 DST 展示信息。必须同时调整页面、Site 数据往返、设备校时和网关状态判断；只改页面会继续用旧 offset 下发，并把季节变化误当 Site 属性变更。

用户在本轮已确认：

1. 每个 IANA 时区按该时区的自然日成功请求一次，缓存持久化，所有 Site 共用；直接校时即使没有打开 Time Zone 页面也执行同一按需刷新。
2. 到达已缓存的 `next_switch` 后，允许额外成功请求一次；不采用 App 自行翻转 DST 状态作为正常更新机制。App 在后台错过切换点，恢复前台或再次使用该时区时补查。
3. 请求失败不计成功次数，允许下次展示/使用重试。有旧缓存且未跨已知切换点时可继续使用；无缓存或已跨切换点而刷新失败时，暂停依赖该 offset 的校时。页面仍可展示回退值，但不能据此认定校时成功。
4. 新写出的 `site.timezone` 仅包含 IANA。兼容读旧的 `IANA (UTC±HH:mm)`，剥离末尾后缀，旧后缀不再参与 offset 解析或下发。

服务端契约和发布验收边界：

- JSON 正式字段按示例使用 `switches_to`，解释中的 `switch_to` 应视为笔误并统一；不自行猜测双字段优先级。
- 用户已确认服务器负责 DST：App 严格按 `is_dst` 和 `current_offset` / `switches_to` 排列展示，不自行推导切换后的状态，不假定变化量为一小时。字段语义由服务器保证。
- `next_switch = null` 可按本次契约显示一个 offset，但缓存不能据此永久认定该地区今后永远无 DST；仍每日刷新。
- `/sitespace/gateway/datetime/update` 的服务器/网关内部过程，以及其对纯 IANA 的支持，仍需外部证据。用户说明它可能由网关向服务器同步时区，App 端可证事实见 D 节。
- 老版本 App 只认识带 offset 的格式。新 App 可兼容旧数据，不代表旧 App 能读取新服务器数据；旧客户端兼容或最低版本发布策略由对应产品/服务器团队确认。

这些不是要求我们修改服务器或固件。App 接入可独立推进，云端真实校时验收需确认外部契约。

### B. 当前源码事实与完整影响范围

分析基线：`feat/daylight-saving-261024`，HEAD `5511abc662335d55d9065910b7cae034168de20b`。开始时只有用户既有未跟踪文件 `SunSmart/all_timeszones.json`，本轮保留；运行时资源仍是 `all_utc_timezones.json`。

| 功能链 | 当前入口/共享文件（均相对仓库根目录） | 必要改动 |
| --- | --- | --- |
| Create / Edit Site、城市选择联动、手机默认时区 | `SunSmart/Main/Site/Controller/SiteCreateViewController.swift` 中的共用表单、`SiteEditViewController.swift`、`SiteCreationDraft.swift`、`SiteTimeZoneCatalog.swift` | 草稿只保存身份；选中时区变动订阅相应缓存；接口回调只更新派生显示，不覆盖用户后来选择的城市/时区；Local time 使用同一有效 offset |
| Time Zone 列表、搜索、选择 | `SiteTimeZoneSelectionViewController.swift`、`SiteTimeZoneSelectionCell.swift` | 可见项按需请求、缓存共用；搜索匹配已知当前/标准/DST offset；不为一次搜索请求整个目录；滚动复用防串行内容 |
| 编辑确认、Site 入口、Review sync、Sync Gateways 卡片、菜单待同步标识 | `SiteViewController.swift`、`SiteTimeZoneReviewSyncView.swift`、`SyncGatewaysTimeZoneCardView.swift`、相关状态/Target/Context | 展示文本与同步数值分离；用最新有效 offset 重算差异，保留权限和历史失败重试；缓存到达不能被「本次入口已处理」门禁吞掉 |
| 网关详情 Time Zone / Date & Time / 同步提示 | `GatewayViewController.swift`、`GatewayDetailClockCoordinator.swift`、`GatewayTimeSyncCoordinator.swift` | 移除独立旧字符串 offset 解析；目标显示和校时共用服务；读取设备的实际 offset 与目标保持区分 |
| 灯具/网关 Information 页 | `DeviceInformationViewController.swift`、`GatewayTimeInformationCoordinator.swift`、`InformationClockRecovery.swift` | 实际设备读数继续显示设备报告的单一 offset；只有目标判断/恢复校时接新服务，不把服务器期望值伪装成设备实测值 |
| 普通设备初始化、单设备、Group、Timed、批量同步、采集日程 | `SiteTimeSetMessageFactory.swift`、`Node+MessageHandles.swift`、`MeshNetwork+SunSmart.swift`、`ScheduleServer.swift`、`GroupServer.swift`、`SyncDevicesCellModel.swift` | 准备同步时按需获取快照；共享工厂使用有效当前 offset；无有效值时依赖校时的任务失败/待重试，不能简单跳过 TimeSet 后把整项标成功 |
| 网关快速添加、全节点广播及 DEBUG 单节点校时 | `GatewayFastAddTimeInitialization.swift`、`DevicesViewController.swift` | 同一目标解析；保持原目的地址、ACK/UNACK、重试及时间有效性检查，不顺手扩大广播范围 |
| Site 创建/克隆、SQLite、导入导出/分享/转移、属性冲突与回执 | `SiteData.swift`、`Database.swift`、`MeshNetwork+SunSmart.swift`、`ImportData.swift`、`ExportData.swift`、`SitePropsAPIClient.swift`、`SitePropsEditPolicy.swift`、`SitePropsEditCoordinator.swift`、`CloudSynchronizationManager.swift` | 新旧字符串兼容；sync/add/get/retrieve/update 共用入口仅写 IANA；身份相等与 offset 相等分开；旧回执不得覆盖新草稿/pending |
| 网关 Last online 等历史时间展示 | `SiteTimeZoneValue.formattedGatewayLastOnline`、`SiteViewController.swift` | 按历史 timestamp 对应的 IANA 规则格式化；当前日期缓存不能证明历史 offset，建议只在历史格式化使用 Foundation，不为历史记录调用「当前日期」接口 |
| 品牌与资源 | `SunSmart.xcodeproj/project.pbxproj`、中英本地化 | 实际六 target：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart；核对新增源文件/资源及文案归属 |

补充核对：磁盘上的旧 `EmerFireAlarmSyncCellModel.swift` 有手机时区调用，但未编入工程；实际编译的是 `EmerFireAlarmSyncAliases.swift`，复用 `SyncCellModel`。SDK 的独立 `MeshScheduleServer` 没有当前 App 调用，不因关键字命中扩大改造。HDB 导入日期文本、日志时间和日历控件的手机时区用途不属于 Site 时区，不统一替换。

最小行为核对（直接执行现有 `SiteTimeZoneValue` 源码）：

- `America/Chicago (UTC-06:00)` 可解析，`America/Chicago` 返回 nil。
- 同一 IANA 的 `UTC-06:00` 与 `UTC-05:00` 被当前合成 Equatable 判为不同值。
- 给定 `2026-11-01T01:00:00-06:00` 解析成 `2026-11-01T07:00:00Z`；本机 Foundation 在该瞬间前一秒为 -300 分钟/DST，切换点为 -360 分钟/非 DST。此项验证日期语义，不证明新接口或设备行为。

### C. 推荐设计与缓存规则

#### C1. 方案选择

建议采用一个 App 共享的专用时区服务。国家/城市服务已有固定分区、异步解析、原子文件缓存、请求去重和观察者模式，可复用这些做法；其「每进程刷新」策略不能直接满足本次自然日/切换点有效性，故新增小型专用 Store，避免修改城市/国家的业务语义。不建通用缓存框架，不增加数据库表或新依赖。

分散在页面中的缓存无法满足跨页面/跨 Site 去重；以 iOS 规则替代服务器作为当前 offset 主来源又不符合本次契约，因此均不作为主方案。用户已确认整套设计，执行结果见下方记录。

拆开三种值：

- **时区身份**：规范化后的 IANA；用于 Site 持久化、属性差异及请求 key，不携带当前 offset。
- **响应快照**：完整四字段、请求 UTC date、收到时间、所属自然日、schema 版本及缓存 revision；保存原始响应语义。
- **运行时解析结果**：IANA、当前 offset 分钟、展示文本、来源/新鲜度、有效截止时间；用于一次判断、发送和回执核对，不写回 Site 属性。

#### C2. 请求与响应

- 新增网络 case，拟用现有 POST/JSON 方式请求 `/sitespace/schedule/dst/next-transition`；沿用当前分区 baseURL/请求头，发起时固定分区。四服务器已部署是用户提供信息，本轮未做线上验证；缓存跨分区共用以同一 IANA 返回一致规则为前提。
- `timezone` 为纯 IANA；`date` 在实际发起请求时获取 `Date()`，序列化为 UTC 的 `yyyy-MM-dd'T'HH:mm:ss+00:00`，不对 timestamp 再加减手机 offset。手机绝对时间错误仍会传错查询日期，本期不另建可信时钟服务。
- 复用已有有界请求入口（建议 10 秒），不加无限自动重试。HTTP/业务成功和合法 data 同时成立才登记成功。
- `is_dst` 必须为 Bool；current/switches offset 按有符号分钟解析，不限定整数小时，不假设 DST 差值恒为 60 分钟。`next_switch` 必须携带 offset 并解析为绝对时间，不能去掉尾部 offset 后作为本地时间解析。
- next_switch/switches_to 必须符合成对 null 或成对有效的契约；缺字段、类型错误、时间早于请求日期、非法 offset 均不污染成功缓存。请求时刻在切换前、响应时已跨切换点的旧快照可保留为历史缓存，但不能视为当前可校时值。
- `next_switch` 中携带的 offset 与 `switches_to` 的关系以服务器协议确认；不在 App 猜测转换前后墙上时间的表达方式。

#### C3. 频率、持久化与生命周期

1. 以规范化 IANA 为 key，内存加 Application Support 下版本化 JSON 原子写入。共享同一 in-flight 请求；成功标记独立于页面和内存淘汰，重启恢复当天记录。
2. 成功覆盖的是请求 date 所属的目标时区自然日，不是响应到达时的手机日期；使用 Gregorian 日期键，不使用「过去 24 小时」。在快照有效区间内以服务器 current_offset 计算当地日期，避免系统时区数据库与服务器规则不一致；到达 next_switch 先判失效并刷新。系统无法识别的 IANA 仍保留身份，不默认为手机时区。
3. 同一天且尚未越过快照 next_switch，直接使用缓存。跨日刷新；跨 next_switch 额外刷新，两种原因合并为一个请求。每个已知 transition 只接受一次覆盖它之后的成功响应，避免旧 next_switch 反复触发。
4. 前台可见页面在跨日/切换点时更新；后台不承诺定点执行，前台恢复、再次展示、开始校时均重新检查。手机改时间/改时区要重新评价有效性，不清空全部缓存；日期回拨不把未来采样快照当当前有效值。
5. 列表仅请求可见项，建议限制并发为 3；选中时区/实际校时优先。滚动离开撤销不再需要的排队任务，已发共享任务由服务管理。重载、计时器 tick、缓存通知不成为失败后的无限重试源；每次重新展示/明确操作才重试。
6. 缓存文件损坏按无缓存处理。写盘失败保留本进程成功值并在 DEBUG 记录；重启后磁盘无成功记录可能重取，这是持久化失败边界，不能保证物理存储失败时仍严格跨进程一次。
7. 缓存更新只通知当前仍使用该 IANA 的消费者；离页、取消、换城市、换 Site、换账号/分区后的旧回调不得更新旧 UI 或触发旧校时。公共缓存可接收合法结果，业务操作仍需自己的 session/identity 检查。

#### C4. 展示和失败行为

| 有效响应 | 时区配置区域右侧显示 | 校时/网关目标 |
| --- | --- | --- |
| next_switch 为 null | current_offset | current_offset |
| next_switch 非空，is_dst=false | current_offset / switches_to | current_offset |
| next_switch 非空，is_dst=true | switches_to / current_offset (DST) | current_offset |
| 无缓存、正在首次请求或首次请求失败 | JSON 静态 offset；目录无匹配显示 Unknown | 不使用 JSON 校时；先请求，失败保留待重试 |
| 缓存跨日、刷新失败，未跨已知 next_switch | 保留旧缓存展示 | 按已确认规则可暂用旧 current_offset，后续明确使用再重试 |
| 已跨 next_switch、刷新失败 | 保留回退信息并显示“需要刷新”的本地化状态；不继续宣称旧 DST 状态是当前状态 | 暂停相关校时，不用旧 current_offset 或 JSON 冒充有效结果 |

补充：无缓存时不影响保存合法 IANA；保存 Site 与校时是两个阶段，前者成功、后者待重试要分别报告。无有效 offset 不能把依赖校时的日程任务判成功，也不能清除旧 pending。与时间无关的控制继续沿用现有流程。

列表、表单行现有固定 44 高度且右侧抗压缩。双 offset 加 `(DST)` 会明显加宽，需核对窄屏、长 IANA、iPad 和字号；建议只针对时区行允许必要换行/自适应高度，不影响共用 Site Type 等行。标准/DST 配对文本与单个「实际同步 offset」分为不同格式化入口，Accessibility 使用展示文字，不复用 storageValue。

#### C5. 历史数据和事务

- 旧格式只去掉严格匹配的末尾 ` (UTC±HH:mm)`，不按第一个空格/括号粗截；纯 IANA 直接接收，未知身份不被自动清空或改成手机时区。
- 采用惰性规范化：读取进入身份模型，正常保存/导出/属性提交时写纯 IANA；不批量修改 Site updateTimestamp，不产生迁移专用上传。原有 timezone pending 继续保留并用纯 IANA 重试。
- `SitePropsValues`、草稿 changedFields、远端回执匹配按身份比较；缓存刷新、DST 到点、同 IANA 旧后缀变化都不成为 Site 属性编辑。
- Site JSON 的 timezone 与设备 JSON 的 timezoneOffset 是两种字段。后者继续代表设备实测数值，保留既有编码、保存和上传方式。
- get/retrieve 的缺失/null、合法旧值、局部 patch、SQLite 重载、克隆、分享/转移、初始上传回执、失败回滚和旧实例保存都需沿真实数据边界覆盖。

### D. `/sitespace/gateway/datetime/update` 当前使用方式

此节以当前 HEAD 源码为准。旧 `docs/260815_1647_site_gateway_cloud_timezone_sync_design.md` 描述了更广的入口和 180 秒超时，不能直接作为当前实现事实。

| 阶段 | 当前 App 行为及证据 |
| --- | --- |
| 唯一业务构造入口 | `SiteEditViewController.finishTimeZoneCommit` 构造 Cloud API/Sync/Session；全源码调用检索未发现普通 Site 入口直接调用该 API |
| 前置 Site 同步 | `SiteTimeZoneEditSyncCoordinator.run` 先 `submitter.submit(snapshot)`；失败不启动网关请求，保留失败/重试路径 |
| 选择目标 | `SiteGatewayLocalTimeZoneContextBuilder` 从本地 Site 网关、正确主 Mesh 上下文和可配置权限生成目标；本地 offset 与目标不同才进入请求；已匹配网关不重复请求 |
| 发起 | `SiteGatewayCloudTimeZoneAPIClient.submit` → POST `/sitespace/gateway/datetime/update`，JSON 只有 `siteId`、`gateways: [MAC]`，没有 timezone、UTC offset、date 或 DST 参数 |
| 请求受理 | data.requestId 必须合法且为正整数；受理并不代表网关已完成 |
| 轮询 | POST `/sitespace/request/status`，JSON 为 requestId；`SiteGatewayCloudTimeZoneSyncCoordinator` 每 3 秒轮询，当前源码总时限 60 秒，从整批开始计时，含提交等待 |
| 终态 | Requested 继续等待；Succeed/Succeeded 转 Synced；Failed/Expired 转 Failed；未知/缺失保留等待，超时仅剩余项失败；取消与迟到回调受 token 限制 |
| 成功映射 | `SiteGatewayCloudTimeZoneSessionCoordinator.confirmations` 将成功 MAC 映射为发起时的 `input.targetTimeZone.offsetMinutes`；状态响应本身没有实际 offset，这是 App 基于任务语义的推定 |
| 返回 Site | Edit 回调保存 confirmed offsets/reviewContext 并重算提示，后续远端 gateways[].timezoneOffset 用于核对 |
| 另一条现场路径 | 普通进入 Site 处理属性与差异提示；Review sync → SyncGatewaysViewController → GatewayTimeSyncCoordinator 走 BLE TimeSet/TimeStatus，之后经 CloudBridge 上传本地结果。这条路径不等于上述云端命令接口 |

因此可证结论是「App 请求服务器为指定网关启动校时任务，并轮询结果」。服务器通知网关主动拉取还是直接推送，是外部实现，当前仓库没有足够源码/协议证据。用户的理解与 App 契约相容，但尚不能证实“网关自己获取”以及“已经支持纯 IANA”。本轮不实际触发生产网关校时来猜测其实现。

本次建议保留现有触发范围和请求 body，不擅自给旧接口增加参数，不把每日 DST 查询变成每日全网关强制校时。App 使用有效 current_offset 选择差异目标；服务器使用同一 Site IANA/规则在任务执行时得出当前 offset。

需服务器/网关团队确认：

1. 命令具体触发什么、网关从哪里获得时区；该源是否已接受纯 IANA，是否仍解析旧字符串后缀。
2. Succeed 表示网关完成校时还是只表示消息送达；网关实际 offset 是否回写到 Site 响应的 gateways[].timezoneOffset。
3. 排队跨切换点时按请求时刻还是执行时刻计算；建议按执行时刻。

最短联调：测试 Site 设置纯 America/Chicago → 调用旧校时接口 → 轮询终态 → 回读网关 offset/TimeStatus，与同一时刻 next-transition.current_offset 比较；至少覆盖非 DST、DST、切换前后。App 的状态/构建通过不能代替这项验收。由对应团队或用户操作受控测试设备。

### E. 同步生命周期与 SDK 边界

- 先在操作入口异步取得有效解析结果，再执行权限/目标差异判断。页面加载可以先展示缓存，纯工厂不偷偷发网络请求；多个任务共享一次刷新。
- 同一事务记录 IANA、offset、缓存 revision、next_switch 和请求时间。发出 TimeSet 前、收到 ACK/轮询成功时再次核对；目标变更后旧成功只能证明旧目标，不能清除新目标待同步。
- 当前 SDK 显式 TimeSet handle 虽在发送时刷新时间，却固定创建时传入的 TimeZone。长队列/连接等待跨 next_switch 是实际需要测试的边界，不能仅修任务生成处。
- SDK 现有 `MeshMessageHandle.messageProvider` 可延迟生成消息，但返回值非可空，`prepareMessageForSend` 没有失效拒发结果。优先利用 App 现有任务取消/重建机制使失效任务待重试；如果无法覆盖已交给 SDK 的排队窗口，需要最小的可选发送前有效性检查/拒发机制，并覆盖普通队列和 Fast Add。该条件性 SDK 范围须纳入实施验证，不允许在失效时仍生成旧 TimeSet，也不新增后台网络到 SDK。
- 分批失败仅重试相关待同步目标；缓存 revision 变化但 offset 未变，不重复校时已成功网关。跨切换点实际 offset 变化时，旧 confirmed offset 和 reviewContext 重新评价。
- 云端 Succeed 当前没有实际 offset，跨切换点/更换 IANA 后禁止直接登记新目标已确认；刷新/回读并与当前目标核对，不能把旧任务成功沿用到新目标。
- 本期不增加未来 TimeZoneSet 调度，不保证 App 关闭时灯具自行 DST 切换。缓存定时刷新也不等于设备定时执行。若需要无人操作自动切换，属于单独的设备/网关能力与外部契约确认。

本地 workspace 映射为 `SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `dbcf6f1a7014320331f3cccdc0a46edc1a0baa88`。已有其他任务的 MeshProxyMessageCommand、SchedulerActionStatus 修改及 SchedulerReadback 测试/脚本均保留。本轮由当前任务写入必要 SDK 发送钩子；新增公开 API 必须随 SDK release 发布，本地映射编译不代表正式 release 已可用。

### F. 建议开发顺序与验收

以下阶段规划已进入实施，进度见执行记录。

1. **身份与数据兼容**：拆开 identity/snapshot/resolution，贯通 Site 读写、比较、pending/回执，先覆盖新旧 JSON 与真实 SQLite 往返；不写批量迁移任务。
2. **接口和专用缓存**：实现严格解析、日界/切换点规则、持久化和去重；覆盖迟到响应、请求跨日、失败重试、写盘失败、重启及时间回拨。
3. **全部目标展示**：接入共用表单/列表、Local time、确认弹窗、网关目标和 Review sync，处理长文本、生命周期和异步复用。Information 实测读数保持真实性；历史时间按历史日期格式化。
4. **校时及差异状态**：接入共享工厂与独立 Gateway resolver、直接校时刷新和待重试状态；验证队列/连接等待跨切换点，按 E 节处理必要 SDK 边界；云端接口维持既有触发方式，补失效确认保护。
5. **回归和构建**：先最小针对性行为测试，再跑关联已有脚本；新增文件/本地化/SDK 接口涉及六品牌归属，稳定后覆盖六品牌 generic iOS Debug，关闭签名，不用 Simulator，不自动真机。

必要验证矩阵：

- 无 DST、DST 两种状态及切换瞬间；+05:45/+09:30 等非整小时；半小时 DST/南半球；null、缺字段、非法数据、系统不认识但服务器识别的 IANA。
- 同时多页面/多 Site 一次请求、列表滚动复用、请求中切换城市、退出重进、跨日、跨 next_switch、后台恢复、请求先于切换但晚于切换返回、成功缓存重启恢复。
- 无缓存/过切换点失败确实不发 TimeSet、不把依赖校时的任务判成功；未跨切换点旧缓存保留；恢复网络后只重试未完成目标。
- 旧格式纯 IANA 往返；同 IANA 季节变化不触发 Site 属性 pending；原 pending、缺字段/null、旧实例、旧回执、保存失败及进程重启恢复。
- Owner/Editor/Visitor 权限、正确 Site/主 Mesh 归属、设备实测 offset 不被缓存覆盖；云端 Succeed 到达时目标已变化；BLE ACK 与实际发送目标一致，取消/迟到应答不污染新会话。
- 排队与 Fast Add 真正进入发送路径的跨切换点测试。只断言源码或提前构造消息，不能替代发送边界行为验证。

优先脚本：`check_site_creation.sh`、`check_site_props.sh`、`check_site_sync_gateways.sh`、`check_site_timeset_message_factory.sh`、`check_site_timeset_call_sites.sh`、`check_timed_schedule_time_sync.sh`、`check_gateway_information_time.sh`、`check_light_information_time.sh`，及真实 SQLite/转移的 `check_site_hdb_persistence.py`、`check_site_transfer.py`。按脚本各自 shebang/参数执行；旧源码契约测试仅作入口遗漏检查，不当作运行验证。若触及公共上传回执，再补 `check_space_recovery_receipts.py`。

人工最短路径：创建 Chicago Site → 等接口成功确认双 offset/Local time → 保存并回读纯 IANA → 选择 Singapore 验证单 offset → 同时打开另一 Site 验证共用缓存 → 断网验证旧缓存/无缓存区别 → 用可控测试时钟跨 DST 与次日 → 在线/现场两条校时路径核对网关/灯具实际 offset。手机系统授权和真实 API、UIKit、设备/服务器联动单独验收。

### G. 初始分析阶段的证据（实施结果见执行记录）

- 已核对当前工作树、生产调用链、共享数据与六品牌工程引用；已核对给定日期解析及现有新格式不兼容行为。
- Swift 最小探针首次因默认 ModuleCache 不可写失败，改用任务专用临时 module cache 后成功；未修改业务代码规避环境问题。
- 未请求新 DST 线上 API，未调用会校时的旧网关 API；未运行整套回归、App 构建或真机；以往 review/构建结果不能视为本需求验证。
- 本轮只更新本文档；等待整体范围确认后使用 Superpowers writing-plans 细化可执行任务，沿用本轮已确认决定，不重复讨论。

外部资料：IANA 明确时区可一年变化多次，且不总在两种 offset 间切换，因此对「标准/DST 两列」必须依赖明确接口语义：[IANA theory](https://www.iana.org/time-zones/theory)。DST 调整量可以为正、负或不同幅度，不应写死加一小时：[RFC 9636](https://www.rfc-editor.org/rfc/rfc9636.html#section-2)。UTC 请求格式沿用 Foundation ISO 8601/POSIX 固定格式能力：[Apple DateFormatter](https://developer.apple.com/documentation/foundation/dateformatter?changes=_4)。

---

## Implementation Plan / 执行记录（2026-11-04）

执行方式：主代理在现有隔离工作树 inline 实施，使用 writing-plans → executing-plans / TDD。用户已授权，沿用同一文档记录；不创建重复文档、不使用子代理、不 commit。以下为本文 A～G 的具体任务。

Goal：纯 IANA Site 身份、服务器 DST 缓存、全 App 展示/校时/状态判断一致，失效 offset 不下发。
Architecture：`SiteTimeZoneValue` 只以 IANA 标识相等；`SiteTimeZoneSnapshot` 表示服务器响应及采样时刻；专用 Store 管请求、自然日/切换点失效、持久化和共享。运行时服务连接网络与 UI 生命周期，TimeSet 只消费有效快照。
Tech Stack：Swift、Foundation、UIKit、现有 Moya/NetworkRequest、SQLite.swift、NordicSigMeshSDK。
Spec：本文 A～G 及用户最新服务器 DST 说明。

Global constraints：仅 App/必要 SDK；六品牌；保留既有未提交改动；服务器 `is_dst` 是权威；IANA 自然日一次且切换后额外刷新；失败不消耗次数；无有效 offset 暂停校时；不增未来设备 DST 调度；不自动真机、不 commit/push。

Review focus：晚到响应跨日/切换不误作有效；缓存更新不覆盖草稿/pending；共享请求取消不影响其他消费者；排队消息及回执跨切换不冒认新成功；Information 实测值与服务器目标保持区分。分别由任务 1～4 行为测试覆盖。

### Task 1：身份、快照和持久化兼容

文件：`SiteTimeZoneValue.swift`、`SiteData.swift`、现有 props/import/export 共用边界；`Tests/Site/SiteTimeZoneValueTests.swift`、props/SQLite 测试。
接口：`SiteTimeZoneValue(storageValue:)` 兼容新旧；`storageValue` 为 IANA；`offsetMinutes: Int?` 仅来自有效服务器快照；展示 fallback 独立；`SiteTimeZoneSnapshot` 严格解析四字段、保存 requestDate、判断 `isUsable(at:)` 与 `needsRefresh(at:)`。

- [x] 先复现纯 IANA 解析失败、旧后缀影响身份、服务器快照展示/失效边界；确认 RED。
- [x] 实现身份和快照；旧后缀不用于 offset，历史时间按 IANA/历史 date；保留缺字段/null和原 pending 语义。
- [x] 运行时区值与 props/真实 SQLite/转移回归，检查正常、旧值、旧回执与失败回滚。

### Task 2：网络与进程共享缓存

文件：新增 `SiteTimeZoneStore.swift`、`SiteTimeZoneService.swift`；`NetowrkReqeustApi.swift`；新增 `Tests/Site/SiteTimeZoneStoreTests.swift`、`scripts/check_site_dst.sh`。
接口：Store 注入 clock/read/write/fetch，提供 `snapshot(for:at:)`、`refresh(identifier:completion:)`、观察与取消；服务绑定 value 的快照查询并协调前台刷新；API case `siteDST(timezone:date:region:)`。

- [x] 测试同区共享请求、自然日与切换点、失败重试、持久缓存重启、跨界迟到响应与写失败，观察 RED。
- [x] 实现线程安全内存快照、后台文件写入、并发限制/排队与观察；严格 UTC request date；旧缓存仅在允许边界用于校时。
- [x] `bash scripts/check_site_dst.sh` 全部 PASS；保留真实序列化/文件读写测试。

### Task 3：页面和同步策略接入

文件：Create/Edit/Selection/Site/SyncGateways/Gateway 控制器与相关 View、SiteEntry/Target/Context/Session 策略；中英 strings、工程归属。
接口：页面订阅 IANA 的快照刷新；Site 属性仅按 identity 比较，目标/确认使用显式 offset 快照；共享服务提供异步 `prepare`。

- [x] 覆盖无快照不作待同步成功、缓存改变重算、旧 cloud result 不确认新 offset、草稿不被覆盖的行为用例，观察 RED。
- [x] 接入全部时区配置展示、列表可见项请求与搜索；时区行自适应长文字；生命周期和取消门禁；Information 保持实测显示。
- [x] 跑 creation/props/sync_gateways 回归；核对六品牌源文件与本地化归属。

### Task 4：实际校时准备、发送与回执

文件：`SiteTimeSetMessageFactory.swift`、GatewayDetail/GatewayTimeSync/InformationClockRecovery、所有工厂调用入口；必要时 SDK `MeshMessageHandle`/两处真实发送入口。
接口：校时入口先准备有效 snapshot；发送前和 ACK 后检查 IANA/offset/有效期；无有效数据让依赖校时的任务保留失败重试，其他控制不受影响。

- [x] 复现无快照、过 next_switch、连接/排队跨切换和旧 ACK 的行为，观察 RED。
- [x] 接入初始化/Timed/Group/批量/FastAdd/广播/Information；验证现有 SDK 能否阻止失效发送，必要时最小增加可选拒发校验，保留既有 SDK 差异。
- [x] 跑 TimeSet、Timed、Gateway/Light Information 与发送边界行为测试；核对目的地址、ACK 和重试未被无关改变。

### Task 5：集成、审查与构建

- [x] 执行关联回归和真实 SQLite；检查工程、本地化、依赖映射与 diff（两项既有回归失败单列）。
- [x] 对最终差异做单独只读自审（按用户规则不使用子代理）；必要修复按行为测试验证。
- [x] 核对 workspace/scheme/SDK 后串行六品牌 generic iOS Debug，稳定 DerivedData，不 clean，不重定向构建日志。
- [x] 更新本文已验证/人工验收/SDK发布依赖并交付，保持未提交。

Ledger：
- 基线 HEAD 5511abc6；仅本文及原有 all_timeszones.json 未提交；已是 linked worktree。SDK 为 one-dev，保留既有 Scheduler/MeshProxy 差异。
- Pre-flight：Task 1 的 nullable offset 由 Task 2 提供；Task 3 与 Task 4 必须显式处理不可用，不能默认 0 或手机时区。新身份相等不能代替同步事务的 offset 相等。
- Ruling：用户已授权实施并禁止子代理/自动提交，覆盖技能默认的重复审批、子代理审查和 commit 步骤；ledger 直接保留在本任务文档。

### 最终验证记录（2026-11-04）

- Tasks 1～4 已实现：身份/严格响应解析/专用共享缓存、所有实际生产入口的显示与校时、临发送与 ACK 失效检查、纯 IANA SQLite 往返。
- RED→GREEN：纯 IANA/身份等价、服务器快照、共享缓存、SDK 前置钩子缺失、跨 DST 后 Sync Gateways 已成功项重新待同步、云端旧 Succeed 不能确认已变目标。
- `check_site_dst.sh`：值/快照/缓存三组通过，覆盖真实 JSON/Codable/磁盘读写、重启、并发合并与上限、自然日、切换点额外成功、迟到响应、失败重试、损坏缓存和写盘失败。写盘失败仍保留本进程成功快照；重启只能重新请求。
- `check_site_dst_transmission.py`：提取真实 SDK handle、普通队列 sendMessageEvent 和 Fast Add sendAppendMessages，注入下层 Mesh stub；验证异步准备、重复完成、取消、排队后过期和实际发往下层的 offset。未覆盖蓝牙/Access 层重传和真实设备。
- `check_site_props.sh`、`check_site_timeset_message_factory.sh`、`check_site_timeset_call_sites.sh`、`check_timed_schedule_time_sync.sh`、`check_light_information_time.sh`（含 gateway 子套件）通过。
- 真实 SQLite 脚本已改为执行生产 timezone accessor，验证旧格式写入后纯 IANA 保存/重载；`check_site_hdb_persistence.py` 和 `check_site_transfer.py` 通过。导入中的 Mesh/Space 和网络仍是替身边界。
- `check_site_creation.sh` 首个 metadata 城市字段断言失败；用 HEAD 原始 SiteTimeZoneValue 单独复现同一行（SiteCreationMetadataTests:113），属于既有问题，本轮未修改业务实现；其余 creation 子套件全部通过。
- `check_site_sync_gateways.sh` 首个 HeaderLayoutPolicy 的 112pt 断言失败，该策略/测试都与 HEAD 相同，属于既有问题。本轮相关其余 25 组检查通过。旧源码归属断言从四/五品牌更新到实际六品牌；不修改产品布局以迁就旧断言。
- SDK 条件项实际使用：MeshMessageHandle 可选异步准备、临发送有效性/所属批次检查、响应验证与拒绝回调；普通和 Fast Add 两发送入口；MeshAPI.sendMessage(handle:) 保留原队列。未使用钩子的消息沿用原行为。
- Fire Alarm 活跃入口仍为共享 SyncCellModel；未编入工程的历史重复文件不改。未增加服务器/固件改动，不自动触发未来设备 DST 切换。
- 作者独立自审发现并修正：直接 Gateway MeshAPI 也排队、旧 cloud Succeed 需同时撤销旧已同步行、缺时区不能跳过 TimeSet 后继续依赖任务、直接请求超时后队列不得晚发。无子代理审查（遵循用户规则）。
- 工程、两份本地化 plist、App/SDK diff 检查通过；新 Store/Service 在六 target 均恰好引用一次，正式依赖声明仍是远端 release，本地 workspace 映射检查通过。
- 最终差异六品牌构建全部 exit 0：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。统一命令参数：`xcodebuild -workspace SunSmartLocal.xcworkspace -scheme <brand> -configuration Debug -sdk iphoneos -destination generic/platform=iOS -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-cli CODE_SIGNING_ALLOWED=NO -quiet build`。串行、不 clean、不 Simulator；现有未使用变量、弱引用捕获和 asset symbol 警告未在本轮扩大修复。
- 最后自审补充：Review 状态的 IANA 相等不能吞掉 offset 显示更新；新增独立显示快照比较和行为回归。Review 横幅与结果行改为完整换行/按内容测高，已打开的结果同时重算网关摘要，避免切换点之后仍展示旧成功。
- 未执行：真实新 DST API、旧云端网关校时接口、UIKit 运行、蓝牙/网关/灯具回读。不将编译或离线测试当作这些验收；尚未 commit/push。

### SDK 交付和人工验收

本轮 SDK 修改限定在 `MeshMessageManager.swift`、`MeshProxyMessageCommand.swift`、`MeshFastAddDeviceManager.swift`、`MeshAPI.swift`；原有 SchedulerActionStatus 和 SchedulerReadback 差异保留。SDK 基线 `dbcf6f1a7014320331f3cccdc0a46edc1a0baa88` 加当前未提交差异；App 正式依赖未换绑个人路径。

发布顺序：先由 SDK 维护者审查并发布可选发送钩子/API 到正式 release，再锁定包含该版本的 App 依赖。App 新使用 `prepareForTransmission`、`transmissionIsValid`、`responseIsValid`、`transmissionRejected`、`hasPreparedTransmission`、`prepareMessageForSend() -> Bool` 和 `MeshAPI.sendMessage(handle:)`。这些当前只在本地 SDK 工作树验证，未宣称远端已发布。

最短人工验收：

1. 旧格式 Chicago Site 打开 Time Zone，核对 `UTC-06:00 / UTC-05:00 (DST)` 或服务器当前对应状态；Singapore 单 offset。保存、服务器回读、重新进 App 均仅存 IANA；同 IANA 季节变化不产生 Site 属性 pending。
2. 两个 Site 同一时区同日复用一次成功请求；重启仍复用。次日、受控 DST 切换点/后台恢复按规则刷新；无缓存/过切换点断网可展示静态回退，但直接和队列校时不能下发；恢复网络重试。
3. Create/Edit/列表、Site Review/结果、Sync Gateways、网关详情在小屏和长字符串下可完整显示；接口回调/滚动复用不能覆盖后来选择；同 IANA 新 offset 更新所有可见目标并重算待同步。
4. 灯具初始化/Timed/Group/批量、Gateway Fast Add/详情/Sync Gateways、Information 恢复分别核对设备 TimeStatus。Information 实际读数与目标展示区分；长队列、取消和切换点附近的旧 ACK 不得清除新待同步。
5. 旧 `/sitespace/gateway/datetime/update` 请求仍只有原 siteId/gateways；Succeed 后真实回读 offset，与同一时刻服务器 current_offset 对照。网关服务端自动 DST 由对应团队验收，不在 App 模拟。

两项既有失败继续开放：创建 metadata 城市部分回执断言，以及 HeaderLayoutPolicy 的 112pt 断言。没有为本轮改变城市合并或 Header 最小宽度策略。


## 历史分析（2026-08-20，以下不作为本轮实施方案）

## 结论

当前问题的根因不是 `all_utc_timezones.json` 少了一个夏令时布尔值，而是 App 将 JSON 中的静态 `utcOffset` 保存为 Site 的长期业务真值。

正确的数据语义应调整为：

- Site 的长期真值是 IANA 时区标识，例如 `America/Chicago`；
- `UTC-05:00` 或 `UTC-06:00` 是这个时区在某一个具体日期的派生结果；
- UI、Local time、Gateway 待同步判断和 Mesh `TimeSet` 都必须针对同一个目标日期，从 IANA 规则动态计算当前 offset；
- JSON 可继续承担列表分组、搜索和城市元数据职责，但其中的静态 `utcOffset` 不能继续作为运行时真值。

只把 Chicago 在 JSON 中从 `-06:00` 改成 `-05:00` 不能解决问题，因为 2026-11-01 夏令时结束后又会错误。

## 当前源码证据

### 1. JSON 保存的是标准时偏移

`SunSmart/all_utc_timezones.json` 中 `America/Chicago` 为：

- `utcOffset = -06:00`
- `abbr = CST`

这描述的是标准时间，不包含日期规则。

### 2. Catalog 将静态偏移直接构造成 Site 值

`SiteTimeZoneCatalogEntry.value` 直接使用 `ianaId + utcOffset` 创建 `SiteTimeZoneValue`。手机默认时区精确命中 Catalog 时也直接返回该静态值。

因此在 2026 年夏季，即使手机时区是 `America/Chicago`，新建 Site 仍会保存 `America/Chicago (UTC-06:00)`。

### 3. Site 值把 offset 作为固定字段

`SiteTimeZoneValue` 当前包含 `ianaId` 与固定 `offsetMinutes`，并据此完成：

- `displayOffset`；
- `storageValue`；
- Mesh offset 可编码判断；
- `formattedLocalDate`。

`formattedLocalDate` 明确使用 `TimeZone(secondsFromGMT:)`，不会调用 IANA 的夏令时规则。

### 4. TimeSet 同样使用固定 offset

`SiteTimeSetMessageFactory.resolve` 从保存值读取固定 `offsetMinutes`，再创建 `TimeZone(secondsFromGMT:)`。因此 Chicago 夏季向 Gateway 或灯具下发的仍是 `UTC-06:00`。

### 5. 同步状态全部按固定 offset 比较

Site Entry、Review Sync、Sync Gateways、Gateway 云端确认等链路均把 `targetTimeZone.offsetMinutes` 与 Gateway 当前/远端 offset 比较。

因此若只修 Edit Site 显示，系统仍会出现以下不一致：

- 页面显示 `UTC-05:00`，但 TimeSet 下发 `UTC-06:00`；
- Gateway 实际为 `UTC-05:00`，却被判断为待同步；
- Site 云端字符串因季节偏移变化被误判为用户修改了时区。

## Foundation 验证

使用系统 `TimeZone(identifier: "America/Chicago")` 验证：

| 日期 | 系统计算 offset | DST |
| --- | ---: | --- |
| 2026-01-15 | UTC-06:00 | 否 |
| 2026-08-20 | UTC-05:00 | 是 |
| 2026-11-01 06:59:59 UTC | UTC-05:00 | 是 |
| 2026-11-01 07:00:00 UTC | UTC-06:00 | 否 |

Foundation 已提供所需时区规则，不应在 App JSON 中自行维护美国、欧洲等地区的 DST 日期表。

## 推荐数据模型

### 长期身份

以 `ianaId` 作为 Site timezone 的稳定身份和相等判断依据。

例如以下两个值表示同一个 Site 时区，而不是两次用户配置：

- `America/Chicago (UTC-06:00)`
- `America/Chicago (UTC-05:00)`

括号中的 offset 只能视为快照或兼容字段。

### 日期派生值

所有需要 offset 的地方必须显式提供目标日期，再通过 IANA `TimeZone` 计算：

- 当前 UI：以当前 `Date` 计算；
- `TimeSet`：以消息实际生成时的 `Date` 计算；
- Gateway 是否待同步：以本次检查时的同一日期快照计算；
- 未来 DST 切换：以转换发生日期计算新旧 offset。

同一事务必须共享同一个日期快照，避免刚好跨越 DST 切换点时 UI、判断和下发使用不同结果。

### 无效 IANA 的兼容回退

服务器可能已有无法被当前系统识别的 IANA 标识。建议：

- IANA 有效：动态派生 offset；
- IANA 无效但旧字符串 offset 合法：保留固定 offset 兼容行为，并记录诊断；
- IANA 与旧 offset 不一致：IANA 规则优先，旧 offset 仅作为历史快照；
- `Etc/GMT±N` 仍按其 IANA 固定规则处理，不额外套用 DST。

## 云端与本地兼容策略

### 推荐的最终协议

服务器最好将 Site timezone 作为结构化字段保存：

- 稳定字段：`ianaId`；
- 可选诊断快照：`offsetMinutes` 和快照时间；
- 不由服务器把某次 offset 当作时区身份。

如果暂时不能改服务器，第一阶段可继续读写现有 `ianaId (UTC±HH:mm)` 字符串，但业务相等判断只比较规范化后的 `ianaId`，括号 offset 在上传时写入当前日期的派生值。需要注意：这会导致旧版本 App 仍把动态 offset 当固定值，因此 App/服务器/旧版本兼容策略必须在上线前确认。

### 旧数据迁移

不建议启动时批量把所有 Site 标记为用户待同步。建议采用惰性规范化：

1. 读取旧字符串并保留 `ianaId` 与 legacy offset；
2. 运行时动态计算 effective offset；
3. 只有用户实际修改时区，或已有合法 Site props 同步事务时，才回写规范化值；
4. 同一 `ianaId` 的季节 offset 改变，不生成 Site timezone pending，不提升 Site 属性更新时间戳。

## UI 调整边界

### Time Zone 列表

- 列表中的 offset 使用当前日期动态计算；
- 搜索 offset 也应匹配当前动态 offset；
- JSON 静态 offset 可作为额外搜索别名保留，避免用户按标准时偏移搜索不到。

### Edit Site

- 标题继续显示 IANA 名称；
- 右侧 offset 和 Local time 都使用 IANA 时区动态格式化；
- App 进入前台、页面重新可见以及系统时区数据库更新后重新计算；
- 不需要每 0.5 秒重新解析 IANA，只需复用 `TimeZone`，时间文本按现有定时器刷新。

## Gateway 与 Mesh 的关键限制

Bluetooth Mesh 设备当前持有的是数值 offset，不会因为保存了 `America/Chicago` 而自行获得完整 IANA 规则。因此修正 App 计算只解决“本次下发正确”，不能自动保证设备在下一次 DST 切换后自行更新。

当前 SDK 已提供 `TimeZoneSet`，可携带“下一 offset + 生效 TAI 时间”，但当前 App 业务路径主要使用 `TimeSet`，没有建立 DST 未来转换调度。可分两个阶段：

### 第一阶段：当前时间正确

- 所有 `TimeSet` 在消息生成时动态计算 effective offset；
- Site/Gateway 待同步判断使用当前 effective offset；
- App 在进入 Site、连接 Gateway、Proxy Ready、执行 Timed/设备同步时发现季节偏移变化，则提示或执行现有同步流程。

这能保证用户再次使用 App 或重新连接时纠正设备，但不能保证无人打开 App 时按转换点自动切换。

### 第二阶段：转换点自动生效

如果固件完整支持 Time Zone Server 状态与计划切换，可在设备同步时：

1. 下发当前 `TimeSet`；
2. 根据 IANA 规则求下一次 DST transition；
3. 计算 transition 后的新 offset；
4. 下发 `TimeZoneSet`，让设备在指定 TAI 时间切换；
5. 读取 `TimeZoneStatus`，验证 current、next 和切换时间；
6. 每次转换后继续安排下一次转换。

这一阶段必须先用实际 Gateway、灯具和固件确认 `0x823C/0x823D` 的支持、持久化、重启行为和 TAI 语义，不能仅凭 SDK 有消息类型就认定设备可用。

对于持续联网的 Wi-Fi/4G Gateway，也可以由云端按 Site IANA 时区在转换点推送；这比依赖 App 在前台更可靠，但需要服务器和 Gateway 运行时共同支持。

## 建议实施顺序

1. 先修改 `SiteTimeZoneValue` 语义：身份与 effective offset 分离，所有派生 API 接受日期。
2. 修改 Catalog、列表、Edit Site 与 Local time，验证 Chicago 夏季/冬季显示。
3. 修改 Site props 比较与合并：同 IANA、不同季节 offset 不再视为用户配置冲突。
4. 修改全部 TimeSet 工厂和 Gateway pending/confirmation 判断，统一使用同一日期快照的 effective offset。
5. 增加旧格式与无效 IANA 的兼容测试。
6. 完成四个品牌 target 的 iPhoneOS 构建。
7. 再单独评估并实机验证 `TimeZoneSet` 的未来 DST 自动切换能力。

## 必测场景

- Chicago：2026-01-15 为 `UTC-06:00`，2026-08-20 为 `UTC-05:00`；
- Chicago：2026-11-01 转换点前后相差一小时；
- New York、London、Sydney：覆盖不同地区和南半球规则；
- Singapore、Kathmandu、Etc/UTC：无 DST 和 15/45 分钟 offset；
- 同 IANA、旧云端 offset 与当前 effective offset 不同：不产生 Site 属性冲突；
- Gateway 当前 offset 与有效 offset 相同：不显示待同步；
- TimeSet ACK/TimeStatus 返回值与当前 effective offset 一致才成功；
- 无效 IANA + 合法 legacy offset：继续可展示和下发，但有诊断；
- DST 切换时 App 在前台、后台、未运行，以及 Gateway/灯具重启后的行为。

## 仍需产品/协议确认

1. 云端是否允许把 `timezone` 改为只保存 IANA，或增加结构化字段？
2. 是否必须保证 App 未运行时，Gateway/灯具也能在 DST 转换点自动更新？
3. 现有已上线旧版本 App 如何解释服务器返回的动态 offset？
4. 哪些设备型号真实支持并持久化 `TimeZoneSet` 的 future transition？

在这四项确认前，建议先批准第一阶段的“当前 effective offset 正确”改造，不直接假设设备具备自动 DST 调度能力。
