# WiFi Gateway Not Configured 状态分析与方案

## 结论

- 需求方向成立：当前页面已经能通过 `wifiGatewayCredentials` 区分网关是否已保存 SSID/password，但 header 仍把未配置状态展示成 `Not Connected`，因此用户看不出“未配置”和“已配置但未连接”的差异。
- `No Signal` 不应表示未配置，也不应表示未连接。按当前代码，它只应出现在 Wi-Fi 已连接后，RSSI 状态不可用、读取失败、解析失败或无有效 43 0F 响应的场景。
- 推荐只改 WiFi Gateway `CID 0x0A78 / PID 0x2721` 的顶部 Wi-Fi 状态映射，不改 4G Gateway，不改 Network Connectivity 表单结构，不新增 Auth 信息。

## 已核实事实

### 入口与设备边界

- Site 页面进入 Gateway 详情时，使用 `gateway.node.isWiFiGateway` 分流到 `WiFiGatewayViewController`。
- `isWiFiGateway` 的判定边界是 `companyIdentifier == 0x0A78` 且 `productIdentifier == 0x2721`。
- `WiFiGatewayViewController` 继承 `GatewayViewController`，但已通过 `supportsGatewaySignalRefresh == false` 退出 legacy 4G signal refresh。

### 当前配置状态链路

- 页面连接 proxy 成功后会调用 `loadNetworkConnectivityFromGateway()`。
- 该方法先发送 `wifiGatewayCredentials` GET。
- 结果为 `.success(credentials)` 时，当前代码把 `networkCredentialSource` 设为 `.gateway`，再读取 `wifiGatewayConnectionStatus`。
- 结果为 `.notConfigured` 时，当前代码把 `networkCredentialSource` 设为 `.phone`，显示 Network Connectivity，并读取手机当前 SSID 作为输入态。
- 问题在于 `.notConfigured` 分支没有更新 header 为 `Not Configured`，header 仍保持初始化或清理状态里的 `Not Connected`。

### 当前 Wi-Fi header 状态链路

- header 创建时默认显示 `wifi_status_not_connected`。
- 连接状态为 `.connected` 时，页面启动 43 0F RSSI 轮询。
- 连接状态不是 `.connected` 时，页面停止 RSSI 轮询并显示 `Not Connected`。
- RSSI 有效时显示 `Excellent / Good / Poor / Bad`。
- RSSI 不可用、读取失败、reserved、解析失败或无 typed status 时显示 `No Signal`。

## 需求完整性判断

当前需求需要补充 4 个边界，建议作为验收口径：

1. “未配置 ssid & password”的真值来源应定义为 43 12 `wifiGatewayCredentials` 返回 `.notConfigured`，而不是本地输入框为空、手机 SSID 为空或 password 为空。
2. 已配置但未连接的真值来源应定义为 43 12 返回 `.success(credentials)` 后，43 0E `wifiGatewayConnectionStatus` 返回非 `.connected`，包括 `.notStartedOrConnecting`、`.passwordError`、`.failed`、`.notConfigured`、`.reserved`。
3. `No Signal` 只在已连接 Wi-Fi 后查询 RSSI 失败或不可用时展示；未配置和未连接都不展示 `No Signal`。
4. Clear/Disconnect 成功后，网关凭据已被清除，应把 header 更新为 `Not Configured`，而不是继续显示 `Not Connected`。

## 方案对比

### 方案 A：在现有 header 状态枚举中增加 Not Configured（推荐）

- 在 `WiFiHeaderStatus` 增加 `notConfigured`，复用现有 `not_configured` 本地化 key，图标建议先复用 `wifi_not_connected`。
- 在 43 12 `.notConfigured`、clear 成功后的本地清理、以及 43 0E `.notConfigured` 且无 gateway credentials 的路径中更新 header。
- 已配置但非 connected 继续走 `Not Connected`。
- 已 connected 后继续走 RSSI 信号强度或 `No Signal`。

优点：改动最小，符合当前状态机，用户能直接区分配置状态；不需要新增资源和文案。

### 方案 B：增加独立 Not Configured 图标

- 文案同方案 A，但新增 `wifi_not_configured` 图片资源。

优点：视觉区分更强。
缺点：需要设计/资源配合，当前需求没有指定新图标，会扩大范围。

### 方案 C：只在 Network Connectivity 表单展示未配置

- Header 保持现状，仅在表单或输入区域提示未配置。

优点：改动更小。
缺点：不满足“顶部 header wifi 状态下面文字改成 `Not Configured`”。

## 推荐开发方案

采用方案 A。

### 状态映射

- 43 12 `.notConfigured`：
  - header：`Not Configured`
  - Network Connectivity：继续显示，回退手机 SSID 输入态
  - RSSI timer：停止
- 43 12 `.success(credentials)` + 43 0E `.connected`：
  - header：按 43 0F RSSI 显示 `Excellent / Good / Poor / Bad`
  - 如果 RSSI 失败或不可用：`No Signal`
- 43 12 `.success(credentials)` + 43 0E 非 `.connected`：
  - header：`Not Connected`
  - RSSI timer：停止
- Disconnect/Clear 成功：
  - header：`Not Configured`
  - 本地 SSID/password 清空
  - Network Connectivity 保持未配置输入态
- Gateway 离线或 proxy 连接失败：
  - header：继续按现有逻辑显示 `Not Connected`
  - 不把离线误判为 `Not Configured`

### 实施步骤

1. 更新静态检查脚本，覆盖以下契约：
   - `WiFiHeaderStatus` 包含 `notConfigured`。
   - 43 12 `.notConfigured` 分支更新 header 为 `Not Configured`。
   - 已配置但 43 0E 非 connected 仍为 `Not Connected`。
   - 只有 RSSI 查询失败/不可用时展示 `No Signal`。
   - `not_configured` 本地化 key 已在 English 与 zh-CN 存在。
2. 修改 `WiFiGatewayViewController`：
   - 增加 header 状态 `notConfigured`。
   - 在 credentials read `.notConfigured` 分支调用该状态。
   - 在 refresh credentials `.notConfigured` 分支调用该状态。
   - 在 clear 成功后的状态收敛中调用该状态。
   - 保留 offline、连接失败、password error 等路径的 `Not Connected`。
3. 如有必要，拆分一个小 helper：
   - 用于表达 “gateway credentials 已配置 / 未配置 / 未知”。
   - 只在现有 controller 内部使用，不新增跨模块抽象。
4. 验证：
   - 跑 WiFi Gateway 相关静态检查脚本。
   - 跑 `git diff --check`。
   - 跑 iPhoneOS build：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
   - 如改动本地化，确认 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` target 没有资源引用问题。

## 待确认

1. `Not Configured` 的图标是否先复用 `wifi_not_connected`。这是推荐范围。
2. Disconnect/Clear 成功后是否也立即显示 `Not Configured`。我建议是，因为此时 43 0D clear 已让网关进入未配置状态。
