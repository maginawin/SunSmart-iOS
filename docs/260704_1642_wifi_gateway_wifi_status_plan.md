# WiFi Gateway Wi-Fi Status View 更新分析与方案

## 结论

- 当前 WiFi Gateway 协议能知道设备是否连接 Wi-Fi 成功：`wifiGatewayConnectionStatus` 返回 `0x01` 时解析为 `.connected`。
- 当前 WiFi Gateway 协议能读取 Wi-Fi RSSI：`wifiGatewayRSSIStatus` 返回 `status = 0x00` 且 `rssi` 有效时解析为 `.valid(dbm:)`。
- 当前协议不能可靠判断设备是否能访问互联网。已有 typed 状态只覆盖 Wi-Fi connection status 与 Wi-Fi RSSI status，没有 Internet reachable / WAN reachable / DNS reachable 等结果字段。
- 因此顶部右侧状态建议只表达 Wi-Fi 连接与信号强弱，不展示或推断 Internet 状态。

## 已核实事实

### 协议事实

- `SunricherVendorGet(function: .wifiGatewayConnectionStatus)` 对应 Wi-Fi connection status。
- `WiFiGatewayConnectionStatus` 结果：
  - `0x00` -> `.notStartedOrConnecting`
  - `0x01` -> `.connected`
  - `0x02` -> `.passwordError`
  - `0x03` -> `.failed`
  - 其它 -> `.reserved(rawValue:)`
- `SunricherVendorGet(function: .wifiGatewayRSSIStatus)` 对应 Wi-Fi RSSI status。
- `WiFiGatewayRSSIStatus` 结果：
  - `status = 0x00` 且 RSSI 有效 -> `.valid(dbm:)`
  - `status = 0x01` -> `.unavailable`
  - `status = 0x02` -> `.readFailed`
  - 其它 -> `.reserved(rawValue:)`

### 当前页面事实

- `WiFiGatewayViewController` 已经继承 `GatewayViewController` 并配置左侧 SIG Mesh status。
- `GatewayInformationHeaderView` 已有可复用的 `GatewayHeaderStatusItemView`，目前用于左侧 SIG Mesh status。
- 右侧仍是原 4G signal UI：`signalImageView` + `networkTypeLabel("4G")` + `signalLabel`。
- WiFi Gateway 已禁用父类 4G signal refresh：`supportsGatewaySignalRefresh == false`。
- 现有 Wi-Fi connection status 获取/轮询主要用于 `Network Connectivity` section，还没有驱动顶部右侧 Wi-Fi status view。

### Figma 事实

- Figma 节点 `211:5832` 中右侧 `wifi status view` 与左侧 `sig mesh stauts view` 同为 `130 x 56`。
- 右侧结构为：
  - 图标：`30 x 30`
  - 标题：`Wi-Fi`，12pt，次级文字色 `#64748B`
  - 状态：例如 `No Signal`，12pt，主文字色 `#272536`
- 该结构适合复用当前 `GatewayHeaderStatusItemView`。

### 资源事实

- 当前已存在资源：
  - `wifi_excellent`
  - `wifi_good`
  - `wifi_poor`
  - `wifi_bad`
  - `wifi_no_signal`
  - `wifi_not_connected`
  - `wifi_no_internet`

## 推荐方案

推荐方案：继续复用并轻微泛化 `GatewayHeaderStatusItemView`，让 `GatewayInformationHeaderView` 同时持有左侧 SIG Mesh status view 和右侧 Wi-Fi status view。

优点：

- 与当前左侧 SIG Mesh 的实现方向一致。
- 4G Gateway 保持默认右侧 4G signal view，不受影响。
- WiFi Gateway 只配置右侧为 Wi-Fi status view，后续若要调整右侧样式，也只改同一个可复用 status item。
- 不把 RSSI 轮询逻辑放进 view，view 只负责展示，状态机仍留在 `WiFiGatewayViewController`。

## UI 状态映射

当 Wi-Fi connection status 为 `.connected` 时：

- 先立即获取一次 Wi-Fi RSSI status。
- 然后每隔 2 秒获取一次 Wi-Fi RSSI status。
- 按 RSSI 更新右侧 Wi-Fi status view：
  - `> -60 dBm`：图片 `wifi_excellent`，状态 `Excellent`，标题 `Wi-Fi`
  - `<= -60 && > -69 dBm`：图片 `wifi_good`，状态 `Good`，标题 `Wi-Fi`
  - `<= -69 && > -80 dBm`：图片 `wifi_poor`，状态 `Poor`，标题 `Wi-Fi`
  - `<= -80 dBm`：图片 `wifi_bad`，状态 `Bad`，标题 `Wi-Fi`
  - RSSI 无效、`.unavailable`、`.readFailed`、`.reserved` 或解析失败：图片 `wifi_no_signal`，状态 `No Signal`，标题 `Wi-Fi`

当 Wi-Fi connection status 不是 `.connected` 时：

- 停止 Wi-Fi RSSI 轮询。
- 右侧 Wi-Fi status view 展示：
  - 图片：`wifi_not_connected`
  - 状态：`Not Connected`
  - 标题：`Wi-Fi`

资源缺口处理：

- 用户已补齐 `wifi_not_connected` imageset，实施使用该资源，不复用 `wifi_no_internet`。

## 状态流

1. 页面 header 创建时，WiFi Gateway 将左侧配置为 SIG Mesh status，右侧配置为 Wi-Fi status。
2. Gateway 离线时：
   - 停止 Wi-Fi connection polling。
   - 停止 Wi-Fi RSSI polling。
   - 顶部右侧显示 `Not Connected`。
3. Gateway 在线并读取 Wi-Fi connection status：
   - `.connected`：更新 Network Connectivity section，并启动顶部 RSSI refresh。
   - 其它状态：更新 Network Connectivity section，并停止顶部 RSSI refresh。
4. 用户点击 Connect 并轮询 connection status：
   - 由其它状态变成 `.connected`：停止 connection polling，保存密码，先获取一次 RSSI，再启动 2 秒 RSSI timer。
   - 由 `.connected` 变成其它状态或 disconnect/clear：停止 RSSI timer，显示 `Not Connected`。
5. 页面离开或 controller deinit：
   - 停止 RSSI timer，避免后台继续发 SIG Mesh GET。

## 本地化

新增用户可见文案 key，需同步 English 与 zh-CN：

- `wifi_status_title` = `Wi-Fi`
- `wifi_status_excellent` = `Excellent`
- `wifi_status_good` = `Good`
- `wifi_status_poor` = `Poor`
- `wifi_status_bad` = `Bad`
- `wifi_status_no_signal` = `No Signal`
- `wifi_status_not_connected` = `Not Connected`，zh-CN 为 `未连接`

说明：这些 UI 原型文案按英文显示，但仍应走本地化 key，符合项目国际化规则。

## 实施步骤

1. 更新静态检查脚本，先覆盖以下预期：
   - WiFi Gateway 右侧不再配置 4G status view。
   - WiFi Gateway 使用 `GatewayHeaderStatusItemView` 或同等可复用 status item 显示 `Wi-Fi`。
   - 存在 `wifiGatewayRSSIStatus` 获取逻辑。
   - 存在 2 秒 RSSI timer。
   - connection status 非 `.connected` 时停止 RSSI timer。
   - RSSI 阈值和图片/文案映射完整。
   - 新本地化 key 在 English 与 zh-CN 中都存在。
2. 泛化 `GatewayInformationHeaderView`：
   - 保留左侧 `gatewayStateView`。
   - 为右侧新增 `wifiStatusView` 或将现有 `signalContentView` 替换为 `GatewayHeaderStatusItemView`。
   - 增加公开方法更新右侧 Wi-Fi status，例如 `setWiFiStatus(...)`。
   - 默认 4G Gateway 仍走旧 signal UI。
3. 在 `WiFiGatewayViewController` 中管理 Wi-Fi RSSI 状态：
   - 增加 `wifiRSSITimer`。
   - 增加 `startWiFiRSSIStatusRefresh()` / `stopWiFiRSSIStatusRefresh()`。
   - 增加 `refreshWiFiRSSIStatus()`，发送 `.wifiGatewayRSSIStatus`。
   - 增加 RSSI 到 UI 状态的映射 helper。
4. 将 RSSI refresh 挂到现有 connection status 状态转移：
   - `applyConnectionStatus(.connected)`：先 refresh 一次 RSSI，再启动 timer。
   - `applyConnectionStatus` 的其它 case：停止 timer 并显示 `Not Connected`。
   - `pollNetworkConnectionStatus()` 成功连接时同样启动 RSSI refresh。
   - `hideNetworkConnectivityForOfflineGateway()`、`clearNetworkByDisconnect()`、`clearLocalNetworkFields()`、`viewWillDisappear` 离开页面、`deinit` 停止 timer。
5. 验证：
   - 跑新增/更新的静态检查脚本。
   - 跑既有 WiFi Gateway 相关检查脚本。
   - 跑 `git diff --check`。
   - 跑 iPhoneOS build：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- Internet reachability：当前协议不支持，不建议用 RSSI 或 connection status 推断。
- 定时器频率：2 秒获取一次 RSSI 符合需求，但需要在页面离开、Gateway 离线、连接状态变化时严格停止，避免 SIG Mesh 请求堆积。
- 并发请求：当前页面已有 connection status polling；RSSI polling 应只在 `.connected` 后启动，避免连接过程中并发查询过多。
- 资源命名：使用用户新增的 `wifi_not_connected`。

## 待确认

已确认：

1. 使用新增的 `wifi_not_connected` imageset。
2. `Not Connected` 的 zh-CN 翻译为 `未连接`。
