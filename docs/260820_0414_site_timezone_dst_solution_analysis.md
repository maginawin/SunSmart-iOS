# Site Time Zone 夏令时问题分析与解决方案

## 2026-11-04 更新：服务器 next-transition 接入方案（已确认，App/SDK 实施完成）

用户已确认按本文范围实施，并补充服务器负责 DST 处理，`is_dst` 直接表示当前是否夏令时。App 按响应四字段执行展示与当前 offset 解析，不自行推算/翻转 DST；旧云端校时 API 保持原有契约，真实网关回读列为运行验收。

本节是当前方案，替代后文 2026-08-20 历史分析中的「系统 IANA 规则作为主要 offset 来源」「旧字符串 offset 回退」「继续上传带 offset 的字符串」等建议。历史分析保留用于说明演进，不作为本轮实施依据。

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
