# Gateway 详情页 Time Zone 功能需求分析与开发方案

## 1. 结论

需求的功能目标合理：在用户已经直连当前 Gateway 的蓝牙 Proxy 后，展示 Site 目标时区、Gateway 当前本地时间、目标时区下的手机本地时间和两者偏差，并允许用户现场修复 Gateway 时间。

当前描述可以进入开发规划，但还不是完全闭合的实现规格。建议按本文方案补齐后再实施，主要缺口是：

1. Gateway 回读成功但其时区与当前 Time Zone 行不一致时，也应显示 `Sync required`。否则最需要同步的时区不一致场景反而没有标题提示，且无法合理进入 Figma 的时区不一致弹窗。
2. “没有 Time Model”需要区分两类情况：
   - Composition 中根本不存在 Time Server / Time Setup Server：App 无法配置出固件未声明的 Model，只能同步失败。
   - Model 存在但没有绑定当前 AppKey：可以在用户点击同步后先发送 Model App Bind，再发送 TimeSet。
3. Figma 的无 Gateway 时间节点将 `Sync clock` 画成禁用态，但文字需求明确要求仍可点击。应以文字需求为准。
4. 当前 Site 有合法但 Mesh 无法编码的 Offset（不是 15 分钟倍数）时，不能悄悄改用手机时区同步，否则下发值与 Time Zone 行展示值不同。应保留 Site 展示并让同步失败。
5. TimeSet 回应成功并不足以证明最终状态。应继续 TimeGet 回读，并校验已知时间、目标 Offset 和时钟偏差后才显示成功 Toast。
6. 初次 TimeGet、用户同步、页面离开、蓝牙断开、重新连接和迟到回包之间需要统一会话隔离，否则旧回包可能覆盖新状态。
7. `Off by` 的“时区已经计算”需要明确为墙钟时间差，而不是两个绝对时间点之差；否则 Gateway 使用错误时区时，偏差可能仍接近 0，和功能目标冲突。
8. 成功、失败、未知和已有有效值后的重试失败需要明确保留策略，避免把仍然可信的上一次 TimeGet 结果无条件清空。

## 2. Figma 核对结果

已通过 Figma 结构化设计读取以下节点：

- `486:13076`：Gateway 详情完整页面。
- `486:13099`：`ListItem/TimeZone/AmericaAnchorage` 完整 Time Zone 区域。
- `486:13103`：只读时区行。
- `486:13107`：有 Gateway 时间时的 `Off by` 行。
- `486:13376`：无 Gateway 时间时的 `Off by --` 行。
- `487:13384`：正负 30 秒内的绿色状态。
- `399:12772`：`Gateway time zone needs sync` 弹窗。
- `399:13230`、`399:13136`：同步成功、失败 Toast。

设计意图如下：

- Time Zone 区域位于 Name 下方。
- Time Zone 标题、只读时区行、12 pt 间隔、无标题的三行时钟卡片组成一个连续区域。
- 时区行和 Gateway / Local / Off by 行高度均为 44 pt，卡片宽度沿用当前 Gateway 页面 343 pt 内容宽度。
- `Off by` 左侧状态点为 8 pt：普通偏差为 `#FFB900`，正负 30 秒内为 `#00D17C`，未知为 `#94A3B8`。
- `Sync clock` 为浅紫背景、紫色文字的胶囊按钮；同步中只替换为 `Syncing...` 并禁止重复触发。
- 弹窗约 302 pt 宽、20 pt 圆角，现有 `SRAlertView` 的结构与尺寸接近，可复用。
- Toast 与 `ToastStatusView.Appearance.siteUpdate` 的 343 × 44 pt、图标、半透明深色背景一致，可直接复用。

明确的设计覆盖项：Figma 节点 `486:13376` 中未知状态的按钮为 40% 透明禁用外观；本需求要求它仍然可点击，因此实现不采用该禁用态。

## 3. 当前源码基础

### 3.1 Gateway 页面覆盖范围

- 4G Gateway 使用 `GatewayViewController`。
- WiFi Gateway 使用 `WiFiGatewayViewController`，继承 `GatewayViewController`。
- 两个入口都由 `SiteViewController` 创建。

因此应在共享 `GatewayViewController` 实现 Time Zone 和时钟区块，WiFi 页面只调整 Section 插入顺序及 Proxy Ready hook，不能分别复制两套逻辑。

本期“所有 Gateway 设备页面”建议定义为上述 4G / WiFi Gateway 详情页。右上角菜单进入的通用 `DeviceInformationViewController` 已有只读 Date time / Time zone 行，不属于 Figma 中 Name 下方的新区域；它只复用底层 TimeGet 能力，不改变现有页面结构。

### 3.2 连接状态

`GatewayViewController` 已使用目标地址匹配的 `GatewayDetailProxyConnectionStateMachine` 区分 connecting、Proxy Ready 和 disconnected。新区域必须只以当前 Gateway 的 direct Proxy Ready 为展示条件，不能使用 Gateway Cloud/MQTT Internet 状态代替。

### 3.3 Site 时区与时间格式

- `SiteTimeZoneValue` 已能解析 `IANA (UTC±HH:mm)`、提供 IANA 名称和 Offset，并校验 Mesh 15 分钟编码条件。
- `SiteTimeZoneCatalog` 已能生成手机默认时区信息。
- `SiteTimeSetMessageFactory` 已提供 Site 优先、缺失/无效时手机回退和显式固定 Offset 的 TimeSet 构造能力。
- `SiteTimeZoneValue.formattedLocalDate` 当前是 `yyyy-M-d h:mm:ss a`；本需求要求小时补零，因此 Gateway 详情页应使用独立格式 `yyyy-M-d hh:mm:ss a`，不要全局修改 Edit Site 的既有格式。

### 3.4 TimeGet / TimeSet

- 已有 `GatewayTimeInformationCoordinator`：要求当前 Gateway direct Proxy Ready，向 `node.timeModel` 发送 TimeGet，校验 TimeStatus，持久化 Node，并触发对应 Gateway 的 Cloud sync。
- SDK 中 `node.timeModel` 对应 Time Server `0x1200`，`node.timeSetupModel` 对应 Time Setup Server `0x1201`。
- TimeSet 为 `0x5C`，TimeStatus 为 `0x5D`。
- SDK 普通配网的默认绑定列表没有 Time Server / Time Setup Server，因此旧 Gateway 确实可能存在 Model 已声明但未绑定当前 AppKey 的情况。
- SDK 已支持 `ConfigModelAppBind`，成功的 `ConfigModelAppStatus` 会更新本地 Model bind；预计不需要修改 SDK。
- SDK 收到任何 TimeStatus 时会先写 Node，因此协调器必须保存操作前快照，并在无效、失败或迟到回包时恢复，避免把未知时间或未完成操作误持久化。

## 4. 推荐产品语义

### 4.1 Time Zone 行的唯一解析结果

页面进入一次可见 Proxy Ready 会话时解析一个统一的“目标时区”：

1. Site 有合法 `SiteTimeZoneValue`：展示 Site 的 IANA 名称与保存的固定 UTC Offset，并以该固定 Offset 计算 Local 和 TimeSet。
2. Site 时区缺失、空或格式无效：展示手机当前 `TimeZone.current.identifier` 与当前日期下的实际 UTC Offset，不展示 `Not configured`，且不写回 Site、不上传服务器。
3. Site 值合法但 Offset 不是 15 分钟倍数：仍展示 Site 值；同步不可用时走失败 Toast，禁止改用手机时区偷偷下发另一值。
4. 手机回退 Offset 也不可由 Mesh 编码：仍可展示 Local，但同步失败。

当系统时区或系统时间发生显著变化时，重新解析手机回退值；若目标 Offset 改变，则清空本次 Gateway 样本并重新 TimeGet。

### 4.2 Section 展示与顺序

- connecting / disconnected：Time Zone 和时钟两个 Section 都不展示，停止 0.5 秒 Timer。
- 当前 Gateway Proxy Ready：立即展示两个 Section、启动 Timer，并且每个新 Proxy Ready session 自动发起一次 TimeGet。
- 4G 顺序：Name → Time Zone → Clock → Associated Spaces → APN → Server Information。
- WiFi 顺序：Name → Time Zone → Clock → Network Connectivity → Associated Spaces → Server Information。
- 断开后立即隐藏；同一页面重新连接成功后重新展示并重新 TimeGet。

### 4.3 TimeGet 状态

| 状态 | Gateway | Local | Off by | 标题提示 |
| --- | --- | --- | --- | --- |
| 初次读取中 | `--` | 实时值 | `Off by --` | 暂不显示 |
| 读取成功、Offset 与目标一致 | 实时推算值 | 实时值 | 实际偏差 | 不显示 |
| 读取成功、Offset 与目标不一致 | 实时推算值 | 实时值 | 包含时区差的偏差 | `Sync required` |
| 超时、错误回包、TimeStatus 未知、解析失败 | `--` | 实时值 | `Off by --` | `Sync required` |
| Composition 缺少 Time Server 或 TimeGet Model 未绑定 | `--` | 实时值 | `Off by --` | `Sync required` |
| 目标 Site Offset 无法 Mesh 编码 | 根据 TimeGet 结果 | 实时值 | 根据 TimeGet 结果 | `Sync required` |

初次 TimeGet 不自动修改 Model 配置；读失败后由用户点击同步显式触发配置和 TimeSet。

### 4.4 `Off by` 计算

按需求采用“已经应用各自时区后的墙钟时间差”：

- Local 墙钟 = 手机当前绝对时间 + Time Zone 行的目标 Offset。
- Gateway 墙钟 = TimeStatus 的 TAI 时间换算结果 + Gateway 回报 Offset。
- `Off by` = Gateway 墙钟 − Local 墙钟。

这样 Gateway 使用 UTC+00:00、Site 使用 UTC+08:00 时，时区差会体现在 `Off by` 中；不再额外重复叠加时区。

TimeStatus 的 sub-second 应纳入计算，最终显示秒数按最接近整数取整：

- 正数显示 `+`，负数显示 `-`，0 显示 `0s`。
- 绝对值小于 60 秒：只显示秒，例如 `-36s`。
- 绝对值大于等于 60 秒：分钟不转小时，显示 `+2m 36s`、`+120m 0s`。
- 正负 30 秒内（含边界）为绿色；其他已知值为黄色；未知为灰色。

取得一次有效样本后保存 Offset 差。0.5 秒 Timer 每次只读取一次 `Date()`：先更新 Local，再用 `Gateway = Local + Off by` 推算 Gateway 行；不重复访问蓝牙。只有新的 TimeGet 或 TimeSet 后回读成功时才重新计算 Offset 差。

### 4.5 `Sync required` 弹窗文案

已知 Gateway Offset 且与目标不一致时沿用 Figma 语义：

`The Site now uses UTC+08:00, while this gateway still uses UTC+00:00. Until you sync, schedules and automations may run at the wrong local time.`

TimeGet 失败或 Gateway 时间/时区未知时，用户建议的文案方向正确，建议做轻微语法调整：

`The Site now uses UTC+08:00, while this gateway’s time zone is unknown. Until you sync, schedules and automations may run at the wrong local time.`

`LATER` 只关闭弹窗；`SYNC NOW` 先关闭弹窗，再进入与 `Sync clock` 完全相同的同步入口。

### 4.6 同步状态链

统一流程如下：

1. 校验页面仍属于当前 Gateway、当前 direct Proxy Ready session，且没有另一个时钟同步操作。
2. 将按钮改成 `Syncing...` 并禁止重复点击；Local / Gateway Timer 继续运行。
3. 解析当前目标时区；若不能精确编码为 Mesh Offset，失败。
4. 确认 Composition 同时存在 Time Server 和 Time Setup Server。缺少任一 Model 时失败，不能尝试创建 Model。
5. 确认 Node 已知当前 ApplicationKey。
6. 对 Time Server、Time Setup Server 中尚未绑定当前 ApplicationKey 的 Model，顺序发送 `ConfigModelAppBind`；逐个校验 `ConfigModelAppStatus` 的 success、Element、Model ID 和 AppKey index。
7. 在实际发送边界重新获取 `Date()`，用目标固定 Offset 生成 TimeSet，发送到实际 Time Setup Server Element。
8. 校验 TimeSet 返回的 TimeStatus：时间非 0、Offset 等于目标 Offset。
9. 再向 Time Server 发送 TimeGet，不直接把第 8 步当成最终 UI 成功。
10. 校验 TimeGet 回读，重新计算 Gateway、Local 和 Off by，持久化 Node，并沿用现有 Gateway Cloud sync 队列更新该 Gateway 快照。
11. 只有最终回读有效、Offset 等于目标且 Off by 在正负 30 秒内，才显示 `Gateway clock synced.`。
12. 任一步失败则显示 `Sync failed. Please retry.`，按钮恢复为 `Sync clock`，保留 `Sync required`。

Toast 只代表本地 BLE / Mesh 同步及本地持久化成功，不代表 Gateway Register 已到达服务器；Cloud 上传失败继续走既有独立提示，不回滚已确认的设备时间。

若同步前已有有效 TimeGet 样本，同步失败后保留该样本继续显示，因为它仍是已知事实；若同步前为未知，则 Gateway 保持 `--`。这比无条件清空真实数据更可靠。

## 5. 状态与生命周期设计

建议在共享协调器中显式维护以下互斥状态：

- hidden / disconnected
- reading
- known
- unknown
- binding
- setting
- verifying
- detached

关键规则：

- 同一时刻只允许一个 TimeGet 或同步操作；同步中按钮不可重复点击。
- 初次 TimeGet 尚未结束时，`Sync clock` 可暂时禁止触发，读取完成或失败后立即可用；这不改变“Gateway 无值时仍可点击”的产品要求。
- 每次 Proxy Ready session 使用独立 token；断开或切换目标后，旧回包只做必要的数据恢复，不更新当前 UI。
- 页面真正退出时停止 UI 回调；已发出的 TimeSet 若仍收到有效结果，只按既有持久化边界处理，不在离开的页面显示 Toast。
- 进入后台、系统显著时间变化和系统时区变化分别处理，Timer 不在不可见页面运行。
- WiFi 的 Network Connectivity 自动读取与 Clock 流程共享同一 Proxy，但各自保留独立业务状态；依赖底层消息队列串行发送，不互相覆盖 UI 状态。

## 6. 开发方案

### 阶段 1：纯值模型和状态机

- 扩展 Gateway 时间格式化模型，增加目标时区解析、12 小时两位小时格式、墙钟差计算、Offset 文案和颜色状态。
- 扩展 `GatewayTimeInformationCoordinator` 或增加其内部 Detail facade，使只读 Information 页面 API 保持兼容，同时支持详情页的读取、Model Bind、TimeSet、TimeGet 回读和会话隔离。
- 保留操作前 Node 时间快照，处理 SDK 自动保存 TimeStatus 的副作用。

### 阶段 2：共享 Gateway UI

- 在 `GatewayViewController.SectionType` 增加 Time Zone 和 Clock 两种 Section。
- 增加只读 Time Zone row 及 Off by / Sync clock 专用 Cell；Gateway、Local 行可复用现有 Cell 样式，但由统一展示模型驱动。
- 在共享基类接入 Proxy Ready 展示、断开隐藏、自动 TimeGet、0.5 秒 Timer、弹窗、同步入口与 Toast。
- 调整 `WiFiGatewayViewController.sections`，保证 Time Zone / Clock 始终紧跟 Name，Network Connectivity 排在其后。
- WiFi 的 Proxy Ready override 必须继续调用共享时钟逻辑，不能覆盖基类行为。

### 阶段 3：文案和资源

- 复用 `site_time_zone_title`、`gateway`、`Later` 和现有 Site Update Toast 图标。
- 为 Local、Sync required、Sync clock、Syncing、Off by、两种弹窗说明、SYNC NOW、成功/失败 Toast 增加 English 与 zh-CN 文案。
- 成功文案采用 Figma 的正确拼写 `Gateway clock synced.`，不采用需求正文中的 `syned`。
- 若现有资源中的状态点和按钮足以用 UIView 绘制，则不新增图片资源；本期不修改其他品牌资源。

### 阶段 4：测试与验证

新增或扩展纯值测试：

- Date 格式、正负/零/跨日、15/30/45 分钟 Offset、sub-second。
- `Off by` 正负号、0、59/60 秒、30/31 秒边界、大分钟值。
- Site、手机 fallback、无效 Site、不可编码 Offset。
- TimeGet 成功、未知 5-byte TimeStatus、超时、错误类型、缺少 Model、未绑定 Model。
- Bind Time Server / Time Setup Server 的顺序、Status 身份校验、任一步失败。
- TimeSet 回包有效但 TimeGet 回读失败、Offset 不匹配、偏差超过阈值。
- 重复点击、断开、重连、离页、迟到回包和 session token。

新增 UI / contract 测试：

- 4G 与 WiFi 都通过共享基类展示。
- Section 顺序及仅 Proxy Ready 可见。
- Time Zone 行无箭头、无点击行为。
- 未知状态 Sync clock 仍可点击；同步中显示 `Syncing...`。
- `Sync required` 的失败、Offset mismatch、成功清除规则。
- Toast 使用 `.siteUpdate` 与 `.bottom`。
- 双语 Key、所有新增 Swift 文件的四 target Sources membership。
- 保留 `check_wifi_gateway_proxy_ready_no_time_set.sh` 的核心约束：Proxy Ready 只能自动 TimeGet，不能自动 TimeSet。

本地验证顺序：

1. 运行新增 focused tests 与现有 Gateway Information、Site TimeSet、WiFi Proxy Ready contracts。
2. 校验双语 strings、project.pbxproj 和 `git diff --check`。
3. 串行执行 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 generic iPhoneOS Debug unsigned build，不使用 Simulator。
4. 真机分别验收 4G / WiFi：已绑定、未绑定、Composition 缺 Model、TimeGet unknown、超时、Offset mismatch、断线重连、前后台、快速重复点击和系统时区变化。

构建与 contracts 不能替代真机 BLE / Mesh、Gateway 固件时钟、Cloud 回读和四品牌视觉验收。

## 7. 预计改动范围

主要修改：

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `Tests/Device/` 下 Gateway 时间纯值与 contract tests
- `scripts/check_gateway_information_time.sh` 或新增聚焦检查脚本

可能新增：

- Gateway Time Zone / Clock 专用 Cell 文件；新增时同步加入四个 app target。

预计不修改：

- Site 时区持久化和服务器 API。
- Gateway Cloud/MQTT Internet 状态定义。
- Gateway 固件。
- NordicSigMeshSDK；现有公开 Model Bind、TimeGet、TimeSet 能力已足够，开发时若发现回调身份无法可靠区分，再单独评估最小 SDK API 扩展。

## 8. 待确认决策

建议确认以下四点后按本文方案实施：

1. `Sync required` 除读取/解析失败外，也在 Gateway Offset 与当前 Time Zone Offset 不一致、目标 Offset 无法 Mesh 编码时展示。
2. `Off by` 按应用双方 Offset 后的墙钟时间计算 `Gateway datetime − Local datetime`，因此会包含 Site / Gateway 时区不一致造成的差值。
3. 同步成功必须通过最终 TimeGet 回读，并要求 Offset 一致且 Off by 在正负 30 秒内；否则按失败处理。
4. 同步失败时，已有有效 Gateway 样本继续保留；只有原本未知时才继续显示 `--`。
