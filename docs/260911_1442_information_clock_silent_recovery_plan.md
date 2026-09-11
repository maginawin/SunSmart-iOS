# Gateway / Light Information 时间读取与静默补偿方案

日期：2026-09-11。本文记录实施前分析；用户随后已确认实施，并要求不执行真机验收。实施结果见 [实施记录](260911_1504_information_clock_silent_recovery_result.md)。

## 结论

方案方向合理，但需要补充读写 Model 区分、写入权限、失败分类、单次补偿上限、回读验证以及异步生命周期保护。建议仅在 Information 时间读取无法完成时，执行一次有条件的静默补偿；正常读取成功不自动校时，即使设备时区与目标时区不同。

## 当前行为与源码证据

| 项目 | Gateway Information | Light Information |
| --- | --- | --- |
| 入口 | GatewayViewController 的 Information 菜单传入 gatewayContext | DeviceLightViewController.information() 传入 lightTimeContext |
| 实际页面 | 共用 DeviceInformationViewController | 共用 DeviceInformationViewController |
| 自动触发 | viewDidLoad 调用 requestGatewayTime | viewDidLoad 调用 requestLightTime |
| 读取消息 | TimeGet，超时 10 秒 | TimeGet，超时 10 秒 |
| 连接要求 | 当前直接连接的 Proxy Ready 必须是该 Gateway | 正常 Mesh 连接即可，可经其他 Proxy 路由 |
| Model 准备 | 要求有 timeModel；当前未主动检查或补绑定 | 确认设备有当前 AppKey、修复本地 Time Client 绑定；有编辑权限才补绑远端 Time Server |
| 失败反馈 | failed_to_retrieve_data 错误 HUD | failed_to_retrieve_data 错误 HUD；未连接还有 device_offline_message HUD |
| 读取成功后 | 保存 Node，更新 Gateway 同步代次并加入云同步；云失败另有 HUD | 保存 Node，不发起 Gateway 云同步 |

这两个入口都会尝试读取，但并非所有设备都一定发送消息。Light 没有 Time Server 时两行显示 Not supported，并且不发送；Gateway 未直连 Proxy Ready 时显示未连接。共用 Information 的其他入口没有传入相应 context，不自动获得本次行为。

Date-time 与 timezone 来自同一次 TimeGet 的 TimeStatus，不是分别发送两个 Get。点击任意一行都会重新触发相同读取。现有提示是 XWHUDManager.showErrorTipHUD，并非需要点确认的 UIAlertController。

关键源码位置（相对仓库根目录）：

- `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`：83–177 行负责进入页面、状态反馈及云失败 HUD；284–338 行负责时间行；516–518 行负责点击重读。
- `SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift`：133 行起为连接校验和读取，177 行起为响应验证、保存与云同步。
- `SunSmart/Main/Device/Lights/Model/LightTimeInformationCoordinator.swift`：65 行起为准备与读取，135 行起为绑定、响应处理。
- `SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift`：现有手动同步已包含两个 Model 的绑定、TimeSet 和最终 TimeGet，可复用其验证思路；不能直接把包含其他页面生命周期和副作用的整个协调器套给 Light。
- `SunSmart/Common/Data/SiteTimeSetMessageFactory.swift`：已提供 Site 优先、手机时区回退及 Mesh 编码校验。
- `SunSmart/Main/Device/Gateway/Model/GatewayModel.swift`：SiteData.canConfigureGateway 为现有 Gateway 配置权限入口。

SDK 核对：本地 one-dev 存在，HEAD 与当前 Package.resolved 均为 `a6246b1b0409824a3227a9c7cad8140219feb182`，本地 SDK 工作区干净。TimeStatus 的五字节全零响应表示时间未知，后续时区等字段缺省；不能把此时 SDK 默认时区当作设备实测时区。SDK 的 MeshAPI.sendMessage 回调把底层异常折叠为 nil，不能只凭 nil 断言是“未绑定”或特定错误。SDK Node+Messages 还会在接收 TimeStatus 时更新并保存 Node 时间，补偿设计必须考虑该副作用。

## 建议确认的完整行为

### 1. 时间来源

目标时区使用设备所属 Site 的有效、可编码时区；Site 不存在、时区为空、格式错误或不可编码时，使用发送时手机当前时区。手机时区仍不可编码时静默结束。

复用现有 SiteTimeSetMessageFactory，不新建一套时区解析。当前 Site 保存的是 `IANA (UTC±HH:mm)`，工厂采用其中固定 UTC 偏移，不按 IANA 自动计算夏令时。本次沿用此语义；自动 DST 属于独立需求。

当前时刻来自发送时 Date()，目标时区作为独立偏移传给 TimeSet。绑定完成后再生成发送时间，不能使用进入页面时已经过期的 Date，也不能先手动加减时区后再让 SDK 转换，避免双重偏移。发送时锁定目标偏移，最终回读与该偏移比较。

### 2. 首次读取与恢复分支

| 条件 | 建议行为 |
| --- | --- |
| 首读有效且本地保存成功 | 展示设备实测值，结束；不发 TimeSet |
| 本地已知读取 Model 未绑定，且具备恢复条件 | 不等待一次注定无法正常发送的读取；直接进入补绑、TimeSet、回读链路 |
| 首读无响应，连接/会话仍有效且具备恢复条件 | 最多尝试一次 TimeSet 补偿；不把无响应直接归因为未绑定 |
| 首读返回时间未知（seconds == 0）且具备恢复条件 | 最多尝试一次 TimeSet 补偿 |
| 缺少时间 Model、设备 AppKey、本地 Time Client 不可用、无配置权限、已断连、页面退出、Site/设备会话变化 | 静默结束，不发送恢复命令 |
| 错误响应类型、其他无效数据、本地保存失败 | 静默结束，不通过写设备来修复本地或不明问题 |
| 绑定失败、TimeSet 失败、最终回读失败或校验失败 | 静默结束，不再进入补偿 |

具备恢复条件指：页面操作仍有效、设备仍属于原 Site/网络、连接条件满足、设备存在 Time Server 与 Time Setup Server、设备已持有当前 AppKey、本地 Time Client 可接收响应且用户具备设备配置权限。只缺 Time Setup Server 的设备可以正常读取，但失败后无法自动写入。

### 3. 绑定与发送

读取依赖 Time Server（0x1200），TimeSet 依赖 Time Setup Server（0x1201），本地接收依赖 Time Client（0x1202）。补偿时逐个检查远端两个 Model 与当前 AppKey 的绑定状态，只绑定缺失项；绑定成功须校验状态、AppKey index、Element 地址及 Model 身份。

全部就绪后只对当前设备 Time Setup Server 所在 Element 单播 TimeSet；收到有效非零 TimeStatus、偏移匹配后，再向 Time Server 所在 Element 发送一次 TimeGet。不能假设两个 Model 位于主 Element，也不能通过广播修复 Information 中的单个设备。

读写均已绑定时跳过绑定，但仍检查写入权限：Light 沿用所属 Space 的设备编辑权限，Gateway 沿用 SiteData.canConfigureGateway。只读用户可以读取已配置好的设备；即使 Model 已绑定，也不能自动写时间。

### 4. 成功边界与数据一致性

TimeSet 响应只代表进入回读阶段，最终 TimeGet 验证通过才发布补偿成功状态。验证包含：来源与当前请求匹配、有效非零时间、偏移等于目标、时间误差在现有 Gateway 同步容差 30 秒内。

页面只展示经过验证的设备数据，不用准备发送的手机时间冒充读取结果。失败时首次显示 `--`；已有本页有效快照则保留，断连状态沿用已有表现。Light 无能力时继续显示现有 Not supported 文案。

需要保护 SDK 自动写入 Node 的副作用：操作保留已确认快照，对无效、中间或过期响应做受当前操作所有权约束的恢复；不能用旧操作备份覆盖同设备更新的有效结果。失败后不上传未经最终确认的值，回滚本地缓存也不代表设备实际时间被回滚。

Gateway 最终验证成功后保留既有本地保存、Gateway dirty 标记及云同步；云同步失败保留现有待同步/错误状态并静默处理，不触发第二次设备校时。Light 仅本地保存。两者均不修改 Site 时区。

### 5. 静默范围与生命周期

建议本次 Information 时间链路的读取错误、离线、绑定失败、写入失败、回读失败、本地保存失败和 Gateway 时间云同步失败全部不显示错误 HUD/弹窗；内部保留阶段、设备、时区来源与失败原因日志，不记录密钥。

首次进入自动执行一轮。一次主动读取最多包含一次恢复和一次最终回读；连续点击两行合并到在途操作，结束后用户点击可启动新一轮。最终回读禁止递归恢复，不增加定时重试。

每阶段与异步回调检查 operationID、Site/网络、设备、AppKey 和连接会话；Gateway 要求同一个直连 Proxy Ready 会话。退出页面、切 Site、断连或会话失效后停止发送后续命令，迟到回调不更新页面或云状态。已发送命令可能已在设备生效，不能宣称可撤回。

TimeGet 与 TimeSet 都返回 TimeStatus，SDK 以响应 opcode 和来源注册回调。应串行执行，并核查 Gateway 父页面及其他同设备时间任务的冲突；已有任务在途时延后或跳过自动恢复，不能互相取消等待回调。SDK 全局 Node 状态副作用仍需结合真实消息时序验收。

本次范围是 Gateway/Light Information 的时间链路。Gateway 主页面既有 Sync clock、SYNC NOW 自动提示、Site 同步、入网初始化以及其他 Information 数据读取不因此改变。

## 开发拆分

1. 增加 Information 专用的共享时间恢复状态机/策略，显式区分读取、补绑定、写入、最终回读、成功、静默结束；把是否允许补偿作为状态约束。
2. 接入 GatewayTimeInformationCoordinator 与 LightTimeInformationCoordinator；两者保留各自连接、权限和持久化边界，共享恢复判定、绑定校验及回读验证。补充 Gateway 配置权限和原始 Site/会话快照；复用现有时间工厂。
3. 调整 DeviceInformationViewController 时间链路失败处理，移除相关 HUD，保留现有行、点击交互及国际化文案。本轮预计不需新增文案或修改 SDK。
4. 更新现有测试中的“Information 永不 TimeSet”“读取失败必须提示”等旧契约，新增状态机与可控传输测试验证真实调用顺序、次数、目的 Model 和失败收敛；避免仅靠字符串包含判断新行为正确。
5. 检查五个品牌 target 的共享源码归属；如新增文件，同步加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。逐个直接 xcodebuild 验证 generic iPhoneOS Debug、CODE_SIGNING_ALLOWED=NO，不使用 Simulator。

## 验证与验收

自动化覆盖：首读成功零写入；两个 Model 的四种绑定组合；未知时间；无响应；只读用户；缺 AppKey/Model；绑定失败；写入失败；回读失败/偏移错误/时间超差；Site 与手机时区不同；缺失及无效 Site 时区；UTC+05:45；绑定耗时后时间新鲜度；重复点击；页面退出、切 Site、重连、迟到回调；云失败；旧响应不覆盖新快照；无循环恢复。

真机验收：Wi-Fi/4G Gateway 直连与普通 Light Mesh 路由分别抓取绑定、TimeSet、最终 TimeGet；确认失败全程无时间错误提示、两行刷新和点击正常，并验证离开页面和断连场景。按项目 UI 要求检查 iPhone/iPad 完整约束与实际布局，不能以编译或源码检查代替。Gateway 云同步需额外验证服务器回读，不把 Mesh ACK 当作云成功。

本轮已完成的基线检查：

- `bash scripts/check_light_information_time.sh /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` 通过，包含 Gateway 时间、原有手动同步、Fast Add 及相关资源契约。
- `zsh scripts/check_site_timeset_message_factory.sh` 通过。
- 工作区初始干净，SDK 工作区干净；本轮仅新增本文档。

本轮未做 iOS 构建、设备校时或真机/服务器验证；上述基线仅说明现有行为与现有测试一致，不说明新方案已实现。

## 待确认

建议按以上边界实施，尤其确认：失败最多恢复一次；缺绑定可直接进入恢复；时间未知纳入恢复；已绑定仍受配置权限约束；Site 无效与缺失均回退手机时区；Information 时间云同步失败也静默。用户确认后再修改业务代码。
