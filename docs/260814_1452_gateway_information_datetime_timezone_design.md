# Gateway Information Date Time 与 Time Zone 最终设计

## 1. 更正后的结论

此前分析错误地把 Site 根级 `timezone` 与 `site.gateways[].timezoneOffset` 混为一谈。经用户更正，本需求的数据边界如下：

- Site 根级 timezone 是全局时区真值和全部 Gateway 同步的目标，任何单个 Gateway 的 `TimeStatus` 都不能修改它。
- Gateway Information 页面读取到的 `TimeStatus` 只更新当前 Gateway 的实际时间状态：本地 Node `timestamp/timezone`，以及 Cloud `site.gateways[]` 中对应 Gateway 的 `timestamp/timezoneOffset` 快照。
- Gateway 实际 Offset 与 Site 根级 Offset 不一致，只表示该 Gateway 需要通过 Sync Gateways 修正，不能让 Gateway 反向改变 Site 根级 timezone。
- 停止 WiFi Gateway 页面在连接成功/Proxy Ready 后自动发送 `TimeSet`。
- 添加 Gateway 时，以手机当前绝对时间和 Site 根级 Offset 发送一次初始化 `TimeSet`。
- 后续 Site → Gateway 的时区修正由现有 Sync Gateways 页面负责。

本需求不涉及 Site props timezone 更新，不调用 `/sitespace/update/siteprops`，不创建 Site timezone pending，也不修改 `SiteData.timezone`、`SiteData.lastUpdate` 或 `SiteData.lastUploadCloudTimestamp`。

## 2. 三个不同的数据对象

### 2.1 Site 根级 timezone

当前 App 使用 `SiteData.timezone` 保存 Site 根级 timezone，格式为 `IANA ID (UTC±HH:mm)`；解析后对应 `SiteTimeZoneValue.ianaId` 和 `offsetMinutes`。

它是：

- Site 的全局时区；
- 添加 Gateway 时首次初始化 TimeSet 的 Offset 来源；
- Sync Gateways 页面向各 Gateway 写入 TimeSet 的目标 Offset；
- 判断 Gateway 是否需要同步的比较基准。

它不是 Information 页面读取后的写入目标。

### 2.2 本地 Gateway 实际状态

App 本地没有 `SiteData.gateways` 数组属性。当前 Gateway 的时间状态保存在 Mesh Node：

- `node.timestamp`：最近一次有效 `TimeStatus` 返回的 Gateway 时间快照；
- `node.timezone`：最近一次有效 `TimeStatus` 返回的 Gateway 固定 Offset；
- `node.savePropertys()`：把两项持久化到本地 Mesh 数据库。

`GatewayModel` 负责 Gateway 业务身份和 Cloud dirty generation，但不直接保存独立 timezoneOffset 字段。

### 2.3 Cloud `site.gateways[]` 快照

服务器 Site payload 中的 `gateways[]` 包含每个 Gateway 的 `timestamp/timezoneOffset`。App 更新该快照的现有正确入口是：

- 更新本地 Node 的 timestamp/timezone；
- 推进对应 `GatewayModel.lastUpdate` generation；
- enqueue `.syncGateway(gateway:node:)`；
- Gateway Register 导出当前 Node，并更新服务器对应 Gateway 项。

这不是 Site props update，也不是 `.syncSite`。

现有 Gateway Register 导出会把 Node 的 `timestamp` 与 `timezoneOffset` 一起带上，不能通过当前 `.syncGateway` 只选择其中一个字段。用户已确认允许同一 Gateway 子项的 `timestamp` 与 `timezoneOffset` 一起更新；约束只是不允许修改 Site 根级 timezone。

## 3. 当前源码事实

### 3.1 Information 页面入口

- 4G Gateway 与 WiFi Gateway 的 More 菜单共同打开 `DeviceInformationViewController`。
- Gateway 入口隐藏 Group 和 Scene Section。
- 当前页面只持有 `Node`，还没有 `GatewayModel` 或专用 Cloud sync context。
- Device 信息顺序为 Name、MAC、PID、Address、Version Identifier、Model、Device Type、Firmware、Signal strength。
- Date time 与 Time zone 应只在 Gateway Information 入口追加到 Signal strength 之后；普通设备 Information 不受影响。

### 3.2 蓝牙连接判定

`node.state == true` 不能单独证明当前手机通过蓝牙直连的是本 Gateway。可靠判定应同时满足：

- `currentProxyReadyContext` 存在；
- Ready Context 的 `nodeAddress` 等于当前 Gateway Primary Unicast Address；
- `currentProxy?.nodeAddress` 等于当前 Gateway 地址。

Information 页面只复用 Gateway 主页面已经建立的连接，不主动连接或重连 Gateway。

### 3.3 WiFi Gateway 当前自动 TimeSet

WiFi Gateway 当前在 Proxy Ready 后调用 `WiFiGatewayTimeSyncCoordinator`，使用 `Date()` 和 `TimeZone.current` 自动发送 `TimeSet`。

该行为会在 Information 读取前改变 Gateway 实际值，也使用了手机 Offset 而不是 Site Offset。用户已确认停止此行为。Gateway 主页面以后只负责连接和配置，不隐式发送 `TimeSet`。

### 3.4 添加 Gateway 当前尚未发送 TimeSet

- `SiteDeviceAddViewController` 使用 Fast Add。
- Gateway 的 `appendMessagesBack` 当前只追加 Project ID、关联 Spaces、Subnet AppKey Index、APN、MQTT 和 Attention 等消息。
- `getNodeSyncGatewayData(gateway:)` 不包含 `TimeSet`。
- Fast Add SDK 内部也没有为 Gateway 自动发送 `TimeSet`。

因此，添加 Gateway 时按 Site Offset 初始化一次 TimeSet 是本需求需要新增的行为。

### 3.5 Sync Gateways 已承担后续修正

现有 Sync Gateways 已符合“Site 根级 timezone 为权威”的方向：

- 使用 Site `offsetMinutes` 作为目标；
- 只选择 Gateway Cloud/Local Offset 与 Site 目标不一致的 Gateway；
- 连接用户现场选择的 Gateway；
- 使用手机当前绝对时间 `Date()` 与 Site fixed Offset 发送 `TimeSet`；
- 只在有效 `TimeStatus` 的 seconds 非零且 Offset 等于 Site 目标时判定成功；
- 保存 Node timestamp/timezone；
- 通过 `.syncGateway` 更新 Cloud Gateway 快照。

Sync Gateways 是用户现场操作页面，不是后台自动同步。未靠近、未点击或同步失败的 Gateway 会继续保持待同步状态。

## 4. 协议与格式

### 4.1 Information 读取

- 请求：SIG Mesh `TimeGet`，Opcode `0x8237`，Parameters 为空。
- 目标：`node.timeModel`，即 Gateway Time Server Model 所在的实际 Element；不能硬编码为 Primary Element 地址。
- 响应：`TimeStatus`，Opcode `0x5D`。
- 响应由发往该 Model 的事务回调接收；如底层暴露 source，校验对象应是该 Model 所在 Element，而不是无条件使用 Gateway Primary Unicast Address。
- `TimeStatus.time.seconds == 0` 表示未知时间，不能更新 UI、Node 或 Cloud Gateway 快照。
- Date time 与 Time zone 必须来自同一条 typed `TimeStatus`，原子更新。

### 4.2 添加与 Sync Gateways 写入

- 请求：`TimeSet`，Opcode `0x5C`。
- 目标：`node.timeSetupModel` 所在的实际 Element；不能硬编码为 Primary Element 地址。
- 时间：手机当前绝对时间 `Date()`。
- Time Zone：由 Site 根级 `SiteTimeZoneValue.offsetMinutes` 构造 fixed `TimeZone`。
- 不能先手动给 Date 加 Offset再交给 TimeSet 编码，否则可能重复应用偏移。
- 成功条件：收到 typed `TimeStatus`、seconds 非零且返回 Offset 等于 Site 目标。

### 4.3 展示格式

- Date time：先按项目公式 `UnixSeconds = seconds + 946684800` 得到绝对时间，再使用 Gateway response Offset 格式化为 `yyyy-MM-dd HH:mm:ss`。
- Time zone：使用 Gateway response Offset 格式化为 `UTC±HH:mm`，例如 `UTC+08:00`。
- Date formatter 固定 Gregorian Calendar 和 `en_US_POSIX` Locale。
- 页面不展示 Site 根级 Offset、Cloud Gateway 旧值或调试对比字段。

## 5. Information 页面数据流

### 5.1 页面进入

1. 仅 Gateway Information Context 追加 Date time 与 Time zone。
2. 检查当前 direct Proxy Ready 是否匹配本 Gateway。
3. 未连接：不发送消息，Date time 显示 `Gateway not connected` / `网关未连接`，Time zone 显示 `--`。用户已确认该展示口径。
4. 已连接：发送一次 `TimeGet`。
5. 页面停留期间若 Gateway 随后才变为 Proxy Ready，不自动读取；用户点击任一新增行后重新判断并读取。用户已确认该生命周期口径。

### 5.2 点击任一行

1. 重新检查当前 direct Proxy Ready。
2. 未连接：不发消息，保持 Date time 未连接提示和 Time zone `--`，不主动重连；两行保持可点击。用户已确认该交互口径。
3. 已连接且请求进行中：忽略重复点击。
4. 已连接且无请求：发送新的 `TimeGet`。

### 5.3 有效 TimeStatus

1. 在发送前保存 Node 原有 timestamp/timezone。SDK 当前会在业务回调前自动把任何 `TimeStatus` 写入 Node，因此业务层必须保留可恢复快照。
2. 验证 attempt ID、发往 `node.timeModel` 的事务回调、typed `TimeStatus` 和非零 seconds，不把响应 Element 硬编码为 Primary Element。
3. 用同一响应生成 Date time/Time zone Snapshot。
4. 将 response seconds/tzOffset 明确写入当前 Node，并调用 `savePropertys()`；保存失败则恢复发送前旧值并再次持久化恢复结果。
5. 本地保存成功后原子刷新两行。
6. 推进对应 GatewayModel Cloud generation。
7. enqueue `.syncGateway`，把 Node 的最新 timestamp/timezoneOffset 更新到 Cloud `site.gateways[]` 对应项。
8. 不读取、不修改、不提交 Site 根级 timezone。

无论 Gateway Offset 是否等于 Site 根级 Offset，都应记录本次真实 Gateway 状态；两者是否一致只影响后续 Gateway sync status，不影响 Site 根级数据。

### 5.4 失败与退出

- TimeGet 超时、响应类型错误或 seconds 为零：恢复发送前 Node timestamp/timezone，防止 SDK 的自动 `TimeStatus` 持久化留下无效值；不推进 Gateway Cloud generation，不 enqueue `.syncGateway`。首次失败时两行显示 `--`，已有成功值时保留上一次有效值，显示一次读取失败 Toast，并允许用户点击重试。用户已确认该失败口径。
- 本地 Node 保存失败：恢复 Node 旧值，不刷新两行、不推进 Gateway Cloud generation、不 enqueue `.syncGateway`，并按读取失败处理。
- Cloud Gateway sync 失败：页面和本地 Node 保留本次 Gateway 返回的真实值，GatewayModel 保持 dirty；显示一次 Cloud 更新失败 Toast，不回滚，也不要求重新读取 Gateway，由现有 Gateway Cloud sync 机制后续重试。用户已确认该失败口径。
- 使用 attempt ID/generation 丢弃旧响应和旧 Cloud callback，避免连续点击或页面退出后的旧结果覆盖新状态。

## 6. 添加 Gateway 数据流

4G Gateway 与 WiFi Gateway 共用 `device.deviceType == .gateway` 的 Fast Add 分支。在 Fast Add 已完成 Composition/Key Bind、可以取得 `timeSetupModel` 后，两类 Gateway 都追加一次初始化 TimeSet：

1. 从当前 Site 根级 `SiteTimeZoneValue.offsetMinutes` 获取目标 Offset。
2. 用手机当前绝对时间和 fixed Site TimeZone 构造 `TimeSet`。
3. 发送到新 Gateway 的 `timeSetupModel`。
4. 验证返回的 typed `TimeStatus`。
5. 保存 Node timestamp/timezoneOffset。
6. 添加完成后现有 `.syncGateway` 会导出最新 Node 状态到 Cloud Gateway 快照。

TimeSet 作为 Gateway 附加消息队列的最后一项。Fast Add 的追加消息成功回调根据 SDK 已更新的 Node timestamp/timezone 验证 seconds 非零且 Offset 等于 Site 目标；失败回调、无效状态或缺少模型时保持 Node timezone 为 nil、timestamp 为 0，使 Gateway Register 省略 `timezoneOffset/timestamp`。

Site timezone 未配置、Gateway 不支持 Time Setup Model、TimeSet 超时或返回错误时，不回滚已经成功的 Provision/Key Bind，也不把 Gateway 添加判为失败。Gateway 保持添加成功，并进入后续 Sync Gateways 待同步状态。用户已确认该失败语义。

## 7. 方案比较

### 方案 A：TimeGet 后立即同步 Gateway Cloud 快照（推荐）

- 有效 TimeStatus 后保存 Node。
- 推进 GatewayModel generation。
- 立即 enqueue `.syncGateway`。
- Site 根级 timezone 完全不变。

优点：App 本地 Gateway 状态、Cloud `site.gateways[]` 与真实 Gateway 快速收敛；后续 Site 入口和 Sync Gateways 能使用最新证据。

用户已确认采用方案 A。

### 方案 B：只保存本地 Node，等待其他 Gateway 云同步机会

优点：Information 页面副作用较少。

缺点：Cloud `site.gateways[].timezoneOffset` 可能长期过期，后续 Site sync status 仍使用旧值，不满足“更新 site.gateways 属性”的要求。

### 方案 C：只修改当前页面或 SiteViewController 内存中的远端快照

优点：UI 立即看起来更新。

缺点：不落本地数据库、不更新服务器，重新进入页面即丢失，也绕过 Gateway Register。不可采用。

## 8. 架构设计

### 8.1 Gateway Information Context

Gateway 菜单创建 Information 页面时，显式传入当前 `GatewayModel`/Gateway identity 和 Cloud sync 能力。普通设备入口不传，因此不显示新行。

不通过全局 current Site/Space 反查 Gateway，避免跨 Site 或页面生命周期错配。

### 8.2 Gateway Time Information Coordinator

聚焦职责：

- direct Proxy Ready 判定；
- TimeGet attempt 和重复请求控制；
- typed TimeStatus 验证；
- Date time/Time zone Snapshot；
- Node 本地持久化；
- GatewayModel dirty generation 与 `.syncGateway`；
- 旧响应/旧 callback 隔离。

Coordinator 不修改 SiteData，不调用 Site props API，不发送 TimeSet，也不主动连接/断开 Gateway。

### 8.3 稳定行身份

当前 Device Information 使用数组下标 `1` 判断 MAC Copy。新增可点击行后，建议把 Device 信息行改为带稳定 identity 的轻量模型，再按 identity 分发 MAC Copy、Date time refresh 和 Time zone refresh。

这是本需求所需的局部调整，不扩展到无关页面。

## 9. 预计修改范围

### 业务代码

- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
  - Information 入口传入明确 Gateway Context。
- `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
  - 仅 Gateway Context 追加两行、使用稳定 row identity、绑定读取状态。
- 建议新增 `SunSmart/Main/Device/Gateway/Model/GatewayTimeInformationCoordinator.swift`
  - TimeGet、Snapshot、Node 保存和 Gateway Cloud sync。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift`
  - 移除 Gateway 页面 Proxy Ready 自动 TimeSet 调用与不再需要的 session gate；保留 WiFi 网络自动加载所需屏障时序。
- `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift`
  - 添加 Gateway 时追加一次 Site Offset TimeSet。
- 复用 `GatewayCloudSyncGenerationPolicy`、`CloudSynchronizationManager.syncGateway` 的既有模式，避免复制 generation 规则。

明确不修改：

- `SiteData.timezone`；
- `SiteTimeZoneValue`；
- `SitePropsEditCoordinator`；
- `SitePropsAPIClient`；
- Site props pending/timestamp；
- Site timezone 编辑、入口仲裁和云同步策略。

### 本地化

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

Time zone、读取失败和 Cloud 更新失败可复用现有 Key；Date time 与 Gateway not connected 没有合适 Key，需要同步增加 English 与简体中文。

## 10. 测试与验收

### 聚焦测试

- 普通设备 Information 不显示新行。
- 4G/WiFi Gateway 两行位于 Signal strength 后。
- direct Proxy 地址不匹配时不发送 TimeGet。
- TimeGet 和添加阶段 TimeSet 分别发往实际 `timeModel`、`timeSetupModel`，不硬编码 Primary Element。
- 页面进入且当前 Gateway 已连接时自动读取一次；点击任一行刷新；in-flight 去重。
- 只接受目标 Gateway 的 typed TimeStatus；seconds 为零失败。
- Date time 和 Time zone 格式正确且原子更新。
- 有效响应保存 Node 并 enqueue 一次 `.syncGateway`。
- 无效响应/本地保存失败不 enqueue Cloud。
- Information 流程没有任何 SiteData timezone 或 Site props update 写入。
- WiFi Gateway Proxy Ready 不再发送 TimeSet，但既有 WiFi 自动加载仍能打开屏障。
- 添加 Gateway 使用 Site Offset，而不是 `TimeZone.current`。
- Sync Gateways 继续使用 Site Offset 并同步 Gateway Cloud snapshot。

### 构建与真机

- 运行 Gateway、Information、Fast Add、Sync Gateways、Cloud generation 聚焦测试/contracts。
- 对 English、简体中文 Localizable.strings 运行 `plutil -lint`。
- 运行 `git diff --check`。
- 直接构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 generic iPhoneOS Debug，关闭签名，不使用 Simulator。
- 真机分别验证 4G/WiFi Gateway：添加初始化、已连接读取、未连接提示、TimeGet 超时、连续点击、断开、Cloud Gateway sync 成功/失败和 Sync Gateways 后续修正。

## 11. 验收边界

- 静态测试和 generic iPhoneOS build 不能证明真实 Gateway 支持 TimeGet 或返回正确 TimeStatus。
- `.syncGateway` 请求成功必须用真实服务器重新读取 `site.gateways[].timestamp/timezoneOffset` 验证，不能用本地 Node 保存成功代替。
- 添加 TimeSet 与 Sync Gateways 必须用真机确认目标 Element、ACK、Offset 和断开时序。
- 本文档是经逐项确认后的最终设计，本轮未修改业务代码。

## 12. 已确认设计决策

以下业务边界已确认：

- 允许同一 Gateway 子项的 `timestamp` 与 `timezoneOffset` 随 `.syncGateway` 一起更新；
- Site 根级 timezone 及相关属性保持不变；
- 添加 Gateway 初始化 `TimeSet` 失败不回滚 Provision/Key Bind，Gateway 添加结果保持成功，并留给 Sync Gateways 后续修正。
- Gateway 未连接时，Date time 显示 `Gateway not connected` / `网关未连接`，Time zone 显示 `--`；两行可点击，点击只重新判断连接，不主动重连。
- 蓝牙已连接但 `TimeGet` 超时或返回无效 `TimeStatus` 时，保留上一次有效值；从未成功读取则两行显示 `--`；显示一次读取失败 Toast；不更新 Node、不 enqueue `.syncGateway`，允许点击重试。
- `TimeGet` 和本地 Node 保存成功、但 `.syncGateway` 更新 Cloud Gateway 快照失败时，页面和本地 Node 保留新值，GatewayModel 保持 dirty；显示一次 Cloud 更新失败 Toast，不回滚、不重新读取 Gateway，交由现有机制后续重试。
- 页面进入时 Gateway 尚未连接、随后才变为 Proxy Ready 时，不自动发送 `TimeGet`；维持未连接展示，用户点击任一新增行后再重新判断和读取，Information 页面不额外订阅 Proxy Ready。
- 总体实现采用方案 A：读取有效 `TimeStatus` 后更新页面与本地 Node，并立即通过既有 `.syncGateway` 更新 Cloud Gateway 快照。

### 已确认：架构与职责边界

- `GatewayViewController` 以明确 Gateway Context 打开 Information，Context 包含当前 `SiteData`、`GatewayModel` 和 `Node`；普通设备入口仍只传 Node，因此不会显示新行。
- `DeviceInformationViewController` 只负责稳定行模型、页面状态和点击分发，不直接拼接 Mesh/Cloud 细节。
- 新增 `GatewayTimeInformationCoordinator`，负责连接资格检查、单次 `TimeGet` attempt、typed `TimeStatus` 验证、格式化、本地 Node 保存和触发既有 Gateway Cloud sync。
- Coordinator 只使用注入的当前 Gateway Context，不从全局 Site/Space 反查；不监听 Proxy Ready，不主动连接/断开，不发送 `TimeSet`。
- 既有 `GatewayCloudSyncGenerationPolicy` 与 `.syncGateway` 仍是 Cloud 并发及 dirty 状态的唯一规则来源，不复制另一套 generation 机制。
- Site 根级 timezone 相关模型、API、pending 与 timestamp 均不进入该调用链。

用户已确认该架构与职责边界。

### 已确认：完整数据流

1. **Information 读取**：Gateway Information 在 Signal strength 后追加两行。进入页面只检查一次匹配当前 Gateway 地址的 direct Proxy Ready；已连接就发送 `TimeGet`，未连接就展示已确认的占位。点击任一行时重新检查并读取；in-flight 点击去重，后续才连接成功不会触发自动读取。
2. **有效响应落地**：只接受当前 attempt、目标 Gateway 的 typed `TimeStatus` 且 seconds 非零。Date time 与 Time zone 从同一响应生成；Node `timestamp/timezone` 保存成功后再原子刷新两行、推进当前 GatewayModel generation，并 enqueue `.syncGateway`。整个链路不比较、更不修改 Site 根级 timezone。
3. **Gateway 添加初始化**：Fast Add 完成 Provision、Composition 与 Key Bind 后，用手机当前绝对 `Date()` 和 Site 根级 fixed Offset 构造一次 `TimeSet`，不手动给 Date 加减 Offset。`TimeSet` 放在现有 Gateway 附加消息队列最后，避免初始化失败阻断 Gateway 配置或 Attention；失败只记录为待 Sync Gateways，Gateway 仍添加成功。
4. **停止 WiFi 页面隐式写时钟**：移除 WiFi Gateway `gatewayProxyDidBecomeReady` 对 `WiFiGatewayTimeSyncCoordinator` 的调用。Proxy Ready 后直接打开既有 automatic-load gate 并继续 WiFi 网络信息加载，不能因为取消 TimeSet 而阻塞原有加载流程。
5. **后续修正唯一入口**：Gateway 主页面和 Information 页面均不发送 `TimeSet`；添加成功后只有用户进入现有 Sync Gateways 流程时，才再次以 Site 根级 Offset 修正 Gateway 并同步其 Cloud 快照。

用户已确认该完整数据流。

### 已确认：状态、错误反馈与并发保护

- **读取中**：不新增全屏 HUD 或额外 loading 文案。已有有效值时继续显示旧值；首次读取时显示 `--`。读取期间重复点击直接忽略，避免并发 `TimeGet`。
- **未连接**：Date time 显示 `Gateway not connected` / `网关未连接`，Time zone 显示 `--`；不 Toast、不主动连接。
- **读取或持久化失败**：TimeGet 超时、错误类型、seconds 为零，或 `savePropertys()` 返回 false 时，保留上一份有效 UI；首次失败维持 `--`，显示一次读取失败 Toast。持久化失败还需恢复 Node 的旧 timestamp/timezone。
- **Cloud 失败**：保留新 UI 和已持久化 Node，GatewayModel 维持 dirty，显示一次 Cloud 更新失败 Toast，后续由既有同步机制重试。
- **生命周期隔离**：每次读取使用 attempt ID；退出页面或启动新 attempt 后，旧 Mesh 回调不能刷新 UI、保存 Node 或触发 Cloud。Cloud 已入队后不因页面退出取消，但页面已不可见时不再弹 Toast。
- **连接中断**：发送后断开按读取失败处理，不主动重连或断开任何 Gateway。

用户已确认该状态与错误处理设计。

### 已确认：显示格式与国际化文案

- 行标题：`Date time` / `日期时间`；`Time zone` / `时区`。Time zone 复用现有 `site_time_zone_row_title`，Date time 新增 Key。
- 未连接值：`Gateway not connected` / `网关未连接`，新增 Key；Time zone 显示非本地化占位 `--`。
- 读取失败 Toast：复用 `failed_to_retrieve_data`，即 `Failed to retrieve data.` / `获取数据失败。`。
- Cloud 失败 Toast：复用 `site_entry_sync_failed_to_update_server`，即 `Failed to update server` / `服务器更新失败`。
- Date time：按项目规则先将 Gateway seconds 加 `946684800` 转为 Unix seconds，再用同一条 `TimeStatus` 的 Gateway fixed Offset 格式化为 `yyyy-MM-dd HH:mm:ss`；固定 Gregorian Calendar 与 `en_US_POSIX` Locale。
- Time zone：同一 Gateway Offset 格式化为 `UTC±HH:mm`，例如 `UTC+08:00`、`UTC-05:30`，零 Offset 显示 `UTC+00:00`。
- 页面不展示 Site 根级 Offset、Cloud Gateway 旧 Offset、IANA 时区名称或任何调试对比字段。

用户已确认该显示格式与国际化文案。

### 已确认：测试与验收设计

- **纯逻辑测试**：覆盖 Gateway seconds 到日期的 `946684800` 转换、正/负/零及 15 分钟 Offset 格式、seconds 为零、连接判定、读取状态转换、in-flight 去重、旧 attempt 丢弃，以及持久化失败回滚。
- **页面契约**：普通设备不显示新行；4G/WiFi Gateway 两行位于 Signal strength 后；稳定 row identity 不破坏 MAC Copy；进入和点击触发规则、退出页面行为及国际化 Key 正确。
- **数据边界契约**：有效响应只更新当前 Node 与 Gateway generation，并 enqueue 一次 `.syncGateway`；无效响应或本地保存失败不入队；任何 Information 路径均不得写 `SiteData.timezone`、Site props pending/API/timestamp。
- **流程回归**：Fast Add 的 Site Offset `TimeSet` 位于 Gateway 附加消息末尾且失败仍回调添加成功；WiFi Proxy Ready 不发送 `TimeSet` 但 automatic-load gate 正常打开；现有 Sync Gateways 仍按 Site Offset 写 Gateway 并上传 Gateway 快照。
- **静态与构建验证**：运行相关 tests/contracts、两种语言 `plutil -lint`、`git diff --check`；直接用 `xcodebuild` 对 SunSmart、Archipelago、SLG Sync Plus、SylSmart 做关闭签名的 generic iPhoneOS Debug 构建，不使用 Simulator。
- **真机与服务器验收**：分别使用 4G/WiFi Gateway 验证添加初始化、已连接读取、未连接、超时、连续点击、读取中断、Offset 不一致、Cloud 成功/失败与 Sync Gateways 后续修正；服务器必须重新读取 `site.gateways[].timestamp/timezoneOffset` 证明更新成功。
- **证据边界**：静态测试和 generic build 只证明代码与 target 集成，不代表 BLE/Mesh、真实 Gateway、网络或 Cloud 端到端通过。

用户已确认该测试与验收设计。

## 13. 补充决策：Fast Add TimeSet 失败值

### 13.1 当前源码行为

- 新 Gateway 的 `node.timezone` 默认是 `nil`，`node.timestamp` 默认是 `0`。
- TimeSet 成功并收到有效 `TimeStatus` 后，Node 保存真实 timezone/timestamp，Gateway Register 导出时会同时包含编码后的 `timezoneOffset` 与 `timestamp`。
- TimeSet 失败、缺少 Time Setup Model 或返回无效响应时，Node 保持 timezone `nil`、timestamp `0`。
- 当前 `Node.export()` 只在 timezone 非空时才同时写出 `timezoneOffset` 与 `timestamp`，所以失败后客户端上传的 Gateway Node payload 会省略这两个字段，而不是自然写成 `0`。
- 服务器收到缺失字段后是保存 null、省略、保留旧值还是补默认 `0`，仅凭客户端源码无法确认，必须通过真实 Gateway Register 与 `/get/siteprops` 回读验证。

### 13.2 原始值 0 的现有语义

当前 App 按 `(timezoneOffset - 64) × 15` 分钟解码，原始 `timezoneOffset = 0` 会得到 `UTC-16:00`，不是“未知”或“未初始化”。直接上传 `0` 而不调整解析/导入规则，会在本地和 Cloud 之间制造一个看似有效但错误的时区值。

### 13.3 已确认方案

用户确认采用字段缺失方案：失败时保持 Node timezone 为 nil、timestamp 为 0，Gateway payload 省略 `timezoneOffset/timestamp`。现有 Site/Gateway 状态策略已经把缺失 Offset 视为待 Sync Gateways，无需引入伪造时区。

不采用 `0/0` 业务哨兵，也不修改现有 Offset 编解码规则。
