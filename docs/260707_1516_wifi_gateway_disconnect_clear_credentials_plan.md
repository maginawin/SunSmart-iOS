# WiFi Gateway Disconnect Clear Credentials Plan

## 背景

WiFi Gateway 设备边界为 CID `0x0A78`、PID `0x2721`。SDK 已按 `docs/260707_1427_wifi_gateway_clear_credentials_sdk_plan.md` 增加 `43 13` clear wifi ssid & password 协议：

- App -> SIG Mesh 网关：`SunricherVendorSet(function: .wifiGatewayCredentialsClear)`，payload 精确为 `43 13`
- SIG Mesh 网关 -> App：`SunricherVendorStatus`，payload 为 `43 13 <ret>`
- SDK typed result：`WiFiGatewayCredentialsClearResult`
- 清除后连接状态复核：`WiFiGatewayConnectionStatus.notConfigured` 对应 `43 0E 04`

本次规划 App 侧 WiFi Gateway 页面如何把现有虚拟 Disconnect 改为真实清除网关凭据。

## 当前代码事实

页面落点：

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`

当前行为：

- `Network Connectivity` 的按钮由 `GatewayNetworkConnectivityCell.ConnectState` 控制：`.available` 显示 `Connect to Wi-Fi`，`.connected` 显示 `Disconnect`，`.connecting` 显示 loading。
- `WiFiGatewayViewController.networkConnectButtonAction()` 在 `.connected` 时调用 `clearNetworkByDisconnect()`。
- `clearNetworkByDisconnect()` 目前只停止本地轮询/RSSI、清空本地 `networkSSID` / `networkPassword` / UI 状态，没有发送 Mesh 命令，所以它确实是虚拟 disconnect。
- 页面已存在 `networkOperationID`，可以防止旧请求回调覆盖新状态。
- 页面已存在 `sendWiFiGatewayGet` 和 `sendWiFiGatewayCredentialsSet`，缺少 clear set 的发送 helper。
- 页面已有 `connectionPollTimeout = 60` 供连接流程使用，但 clear 协议是单次最终结果，不需要再轮询 `43 0E` 才能判断成功。

SDK 覆盖情况：

- `SunricherVendorSet(function: .wifiGatewayCredentialsClear)` 可编码 `43 13`。
- `SunricherVendorStatus` 可解析 `43 13 00/01/02/其他` 到 typed clear result。
- `43 13` response matching 已与 `43 0D`、`43 0E`、`43 12` 隔离。
- `43 0E 04` 已能解析为 `.notConfigured`，可用于后续 Refresh 或手动复核。

## 需求完整性分析

用户提出的主流程合理：

- 点击 Disconnect 后发送 clear credentials 命令。
- UI 进入等待状态并转圈。
- 收到 `43 13 00` 后提示成功，并清空 SSID/password。
- 收到 `43 13 01` 后提示错误。
- 收到 `43 13 02` 或其它保留值后提示失败。
- 超时按清除失败处理。

需要补齐的边界：

1. clear 失败、参数错误或超时时也清空当前 SSID/password。原因是用户已确认优先允许继续配置新的 Wi-Fi，而不是保留旧展示。
2. 点击 Disconnect 后应暂停当前连接轮询和 RSSI 轮询，避免旧 `43 0E` / `43 0F` 回调在 clear 等待期间刷新出旧状态。
3. clear 等待期间应禁用 Select WiFi、Refresh、SSID clear、Password edit、Show/Hide 和主按钮，避免并发操作。
4. 页面离开后如果 clear 回调回来，不应弹出即时 HUD；建议复用现有 `pendingNetworkResultHUD` 机制，页面回来后再展示结果。
5. 网关离线、没有 vendor model、response nil、response 类型不匹配都按清除失败处理，并恢复到清除前的 connected UI。
6. 参数错误 `43 13 01` 对 App 来说理论上不应发生，因为 SDK public API 不会构造 trailing bytes；但仍应按协议展示错误提示。
7. 成功后需要同步清空本地 password cache 中当前 SSID 对应的缓存值，否则用户重新选择同名 SSID 时可能回填旧密码。

## 方案比较

### 方案 A：复用 `.connecting` 表示 disconnect 等待

优点：改动最小，现有 cell 已有 loading 动画和禁用逻辑。

缺点：controller 中很多逻辑把 `.connecting` 当成“正在连接 Wi-Fi”，例如连接状态轮询回调、编辑权限、超时语义和 HUD 命名都会混在一起。后续维护容易误把 disconnect 当 connect 处理。

### 方案 B：新增独立 `.disconnecting` 状态

优点：状态语义清晰；Connect 和 Disconnect 的等待态都能转圈，但 controller 可明确区分正在连接和正在清除凭据；失败恢复、成功清空、按钮禁用都更直接。

缺点：需要改 `GatewayNetworkConnectivityCell.ConnectState` 和 `WiFiGatewayViewController` 的多个 switch。

### 方案 C：保持按钮文字并用全局 HUD loading

优点：cell 改动少。

缺点：不符合“点击 disconnect 后开始转圈等待网关回复”的 UI 要求；全局 loading 与当前 cell 内已有交互模型不一致。

推荐采用方案 B。

## 推荐设计

### 状态模型

在 `GatewayNetworkConnectivityCell.ConnectState` 新增：

- `.disconnecting`

cell 行为：

- `.connecting` 和 `.disconnecting` 都显示 loading icon 旋转。
- 两者都隐藏按钮 title，并禁用主按钮。
- `.disconnecting` 期间禁用 Select WiFi、Refresh、SSID clear、Password edit、Show/Hide。
- `.connected` 仍显示 `disconnect`。
- `.available` 仍显示 `connect_to_wifi`。

controller 行为：

- 新增 `isNetworkOperationInProgress` 或局部判断，把 `.connecting` 与 `.disconnecting` 都视为操作中。
- 现有 guard `networkConnectState != .connecting` 需要扩展为“不是操作中”，避免 disconnect 等待期间其它入口可操作。
- `startWiFiRSSIStatusRefresh()` 仍只允许 `.connected`。
- clear 开始时保存当前 SSID，用于清除本地 password cache；无论 clear 结果如何，流程结束后都清空 SSID/password 展示。

### Clear 命令发送

在 `WiFiGatewayViewController` 新增发送 helper：

- 使用 `node.sunricherVendorModel`
- 发送 `SunricherVendorSet(function: .wifiGatewayCredentialsClear)`
- 默认 timeout 建议 `10s`，与现有 `sendWiFiGatewayCredentialsSet` 保持一致
- completion 返回 `WiFiGatewayCredentialsClearResult?`
- response nil、类型不匹配、参数不匹配都返回 nil，由 UI 按失败处理

### Disconnect 主流程

将 `clearNetworkByDisconnect()` 从本地清空改为真实 clear 流程：

1. guard 当前状态为 `.connected` 且节点在线，否则忽略或提示失败。
2. 停止连接轮询和 RSSI 轮询。
3. 记录当前 SSID/password 快照。
4. 设置 `networkConnectState = .disconnecting`。
5. reload `.networkConnectivity`，按钮显示转圈。
6. `beginNetworkOperation()`，发送 `43 13`。
7. 回调必须校验 `operationID` 和 `node.state`。
8. result 为 `.cleared`：
   - 清空本地 `networkSSID`、`networkPassword`、`networkCredentialSource`、`isNetworkPasswordVisible`
   - 清空当前 SSID 对应的 `UserDefaults` password cache
   - 设置 `networkConnectState = .disabled`
   - 更新 header 为 `Not Connected`
   - reload cell
   - 提示成功
9. result 为 `.invalidParameters`：
   - 清空本地 `networkSSID`、`networkPassword`、`networkCredentialSource`、`isNetworkPasswordVisible`
   - 清空当前 SSID 对应的 `UserDefaults` password cache
   - 设置 `networkConnectState = .disabled`
   - 更新 header 为 `Not Connected`
   - reload cell
   - 提示失败
10. result 为 `.failed`、`.reserved`、nil 或超时：
   - 清空本地 `networkSSID`、`networkPassword`、`networkCredentialSource`、`isNetworkPasswordVisible`
   - 清空当前 SSID 对应的 `UserDefaults` password cache
   - 设置 `networkConnectState = .disabled`
   - 更新 header 为 `Not Connected`
   - reload cell
   - 提示失败

说明：`MeshAPI.sendMessage(... timeout:)` 已承担超时回调，App 不需要额外创建 timer；只要 nil response 统一按失败处理即可。

### 成功后的 Network Connectivity 完整性

clear 成功后页面本地状态应与协议复核结果一致：

- 本地 UI：SSID/password 为空，按钮 disabled，Wi-Fi header 为 Not Connected。
- 下次 Refresh：因为 `networkCredentialSource = .localClear`，走 `refreshGatewayCredentials()`。
- 若网关正常返回 `43 12 01`，页面按 not configured 走 phone SSID 回填路径。
- 若后续手动查询 `43 0E` 返回 `43 0E 04`，SDK 已能解析 `.notConfigured`，页面现有 `applyConnectionStatus` 会按未连接处理。

### 提示策略

优先复用现有文案：

- 成功：`successfully`
- 失败：`failed`

参数错误复用现有失败提示：

- English：`failed`
- 简体中文：`失败`

原因：用户已确认参数错误不新增独立本地化文案，统一按失败提示处理。

### 不纳入本次范围

- 不新增单独的 Wi-Fi 网关 internet/cloud/MQTT reachability 判断。当前协议仍只能表达 Wi-Fi/AP 连接状态，不能证明可访问互联网。
- 不改 4G Gateway 或其它 Gateway 页面。
- 不改 SDK 协议实现。
- 不新增明文 password 日志。

## 实施计划

1. 修改 `GatewayNetworkConnectivityCell.swift`
   - 为 `ConnectState` 增加 `.disconnecting`
   - 将 loading 判断从仅 `.connecting` 扩展为 `.connecting || .disconnecting`
   - 确保 `.disconnecting` 时禁用所有网络连接相关交互

2. 修改 `WiFiGatewayViewController.swift`
   - 增加操作中判断 helper
   - 增加 clear credentials 发送 helper
   - 增加清除成功/失败处理方法
   - 将 `clearNetworkByDisconnect()` 改为发送 `43 13`
   - 成功后清空当前 SSID 的本地 password cache
   - 失败/参数错误/超时恢复 clear 前展示

3. 本地化
   - 不新增本地化 key
   - 参数错误、clear 失败、超时统一复用现有 `failed`

4. 补充轻量回归检查
   - 扩展或新增脚本，检查 WiFi Gateway disconnect 使用 `.wifiGatewayCredentialsClear`
   - 检查没有新增 password 明文日志
   - 检查 `.disconnecting` 禁用交互和 loading 判断存在

5. 验证
   - `git diff --check`
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
   - 如改动触及共享 cell，建议串行验证其它品牌 target：`Archipelago`、`SLG Sync Plus`、`SylSmart`

## 已确认

采用推荐方案 B，并按以下行为实现：

1. clear 失败、参数错误、超时时，仍清空 SSID/password，以允许用户继续配置新的 Wi-Fi。
2. 参数错误复用现有 `failed` 提示，不新增本地化文案。
