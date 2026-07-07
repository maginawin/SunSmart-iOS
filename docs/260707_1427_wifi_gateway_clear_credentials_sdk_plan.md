# WiFi Gateway Clear Credentials SDK Plan

## 背景

WiFi Gateway 设备身份边界为 CID `0x0A78`、PID `0x2721`。本次只规划在本地 `NordicSigMeshSDK` 中实现 `43 13` clear wifi ssid & password 协议，不实现 App 页面入口、按钮、缓存清理 UI 或产品业务流程。

协议方向：

- App -> SIG Mesh 网关：Vendor Set，payload 固定 `43 13`
- SIG Mesh 网关 -> App：Vendor Status，payload `43 13 <ret>`

## 当前代码事实

本地 SDK 路径：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

现有 WiFi Gateway 协议已接入同一套 vendor message 体系：

- `SunricherVendorSet.swift`：已有 `wifiGatewayCredentialsSet`，编码为 `43 0D ...`
- `SunricherVendorGet.swift`：已有 `wifiGatewayConnectionStatus`、`wifiGatewayRSSIStatus`、`wifiGatewayCredentials`，分别编码为 `43 0E`、`43 0F`、`43 12`
- `SunricherVendorStatus.swift`：已有 `VendorGatewayCode`、`ResponseCode`、WiFi typed result 解析，以及 `isWiFiGatewayResponse`
- `VendorServerDelegate.swift`：对 `wifiGatewayCredentialsSet` 走 no-op，避免 SDK 缓存或处理明文 Wi-Fi credentials
- `WiFiGatewayVendorMessageTests.swift`：已有 WiFi Gateway vendor message 编码、解析、response matching 测试

SDK 现有 opcode 常量使用当前工程约定：

- Set：`SunricherVendorSet.opCode = 0xF0780A`
- Get：`SunricherVendorGet.opCode = 0xF1780A`
- Status：`SunricherVendorStatus.opCode = 0xF3780A`

这与文档中的 `0xF00A78` / `0xF30A78` 是同一厂商 opcode 在当前 SDK 表示方式下的既有写法。本次不新增 vendor base layer，也不修改现有 opcode 常量。

## 方案

推荐方案：沿用现有 `SunricherVendorSet` / `SunricherVendorStatus` 架构，新增一个无参数 SET function 和一个独立 typed clear result。

### 1. 新增 request 编码

在 `VendorGatewayCode` 中新增 gateway subcode：

- `wifiCredentialsClear = 0x13`

在 `ResponseCode` 中新增：

- `wifiGatewayCredentialsClear`

在 `VendorFunctionSet` 中新增：

- `wifiGatewayCredentialsClear`

编码规则：

- `SunricherVendorSet(function: .wifiGatewayCredentialsClear).parameters` 必须精确等于 `43 13`
- SDK 不提供携带 trailing bytes 的 public API
- 缺少 subcode 或 subcode 非 `0x13` 不在 SDK 的 clear command API 表达范围内

### 2. 新增 response 解析

在 `SunricherVendorStatus` 的 WiFi Gateway response parser 中新增 `43 13 <ret>` 解析。

建议新增独立结果类型：

- `WiFiGatewayCredentialsClearResult.cleared`：`ret == 0x00`
- `WiFiGatewayCredentialsClearResult.invalidParameters`：`ret == 0x01`
- `WiFiGatewayCredentialsClearResult.failed`：`ret == 0x02`
- `WiFiGatewayCredentialsClearResult.reserved(rawValue:)`：其它值

在 `FunctionParameters` 中新增：

- `wifiGatewayCredentialsClear(WiFiGatewayCredentialsClearResult)`

解析边界：

- 只接受长度精确为 3 的 response payload：`43 13 <ret>`
- `43 13 00` 解析为最终清除成功
- `43 13 01` 解析为参数错误
- `43 13 02` 解析为清除失败、存储删除失败、ESP32 返回失败或当前状态不可抢占
- `43 13 xx` 的其它值解析为 reserved，并由 App 按失败处理
- `43 13 00 00` 这类 trailing bytes response 应解析失败，不能误判成功

### 3. 补充 `43 0E 04` 状态解析

协议要求清除成功后 `43 0E` 查询结果应返回 `43 0E 04`。当前 SDK 的 `WiFiGatewayConnectionStatus` 只显式支持 `0x00`、`0x01`、`0x02`、`0x03`，`0x04` 目前会落到 reserved。

建议同步新增：

- `WiFiGatewayConnectionStatus.notConfigured`：`status == 0x04`

保留当前 `SunricherVendorStatus.Status.isSuccessful` 的既有行为：由于 `status != 0`，通用 `isSuccessful` 仍为 `false`，业务侧应读取 typed result 判断具体连接状态。这与现有 `connected`、`passwordError`、`failed` 的行为一致。

### 4. Delegate 与敏感信息边界

`VendorServerDelegate` 需要补新增 `FunctionParameters.wifiGatewayCredentialsClear` 分支，建议继续 no-op。

原因：

- clear response 不携带 SSID/password
- SDK 不应在 delegate path 中缓存、打印或生成明文 password 日志
- App 清除成功后同步清空本地展示缓存属于后续 App 侧实现，不纳入本次 SDK-only 变更

### 5. 测试计划

在 `WiFiGatewayVendorMessageTests.swift` 中补充 focused tests：

- clear request 编码必须等于 `43 13`
- clear response `43 13 00` 解析为 `.cleared`
- clear response `43 13 01` 解析为 `.invalidParameters`
- clear response `43 13 02` 解析为 `.failed`
- clear response 其它 ret 解析为 `.reserved(rawValue:)`
- `43 13 00 00` 不得解析为成功参数
- `43 0E 04` 解析为 `.notConfigured`
- `MeshMessageHandle.matchesResponse` 中 clear request 只匹配 `43 13 <ret>`，不匹配 `43 0D`、`43 0E`、`43 12` 或 legacy `43 05`

## 验证计划

优先验证命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

同时建议验证 SDK demo：

`xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

说明：

- 当前仓库历史上 `swift test` 可能先被 macOS SwiftPM 的 `no such module 'UIKit'` 卡住，不能作为本地 SDK 逻辑是否正确的唯一验收依据。
- 如果实现阶段仍需要跑 focused tests，可先尝试 `swift test --filter WiFiGatewayVendorMessageTests`，失败时以错误日志判断是否仍是既有 UIKit 阻塞。

## 需要确认

请确认是否采用以上方案，特别是这两个点：

1. 是否同意新增独立 clear result：`WiFiGatewayCredentialsClearResult`，不复用 `WiFiGatewayCredentialsSetResult`。
2. 是否同意同步把 `43 0E 04` 补成 `WiFiGatewayConnectionStatus.notConfigured`，以匹配清除成功后的复核语义。

确认后再进入 SDK 实现；未确认前不修改 SDK 代码。
