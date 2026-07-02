# WiFi Gateway Vendor Protocol SDK 设计

## 背景

WiFi Gateway 的设备身份为 `CID 0x0A78, PID 0x2721`。本次只规划 SDK 层协议能力，不在 App 中接入页面、按钮、菜单动作或业务流程。

协议使用 Sunricher vendor model：

- Set vendor opcode：`0xF00A78`
- Get vendor opcode：`0xF10A78`
- Response / Report vendor opcode：`0xF30A78`
- Vendor main opcode：`0x43`

当前 SDK 已有 `SunricherVendorSet`、`SunricherVendorGet`、`SunricherVendorStatus` 体系，并且已有 Gateway 主码 `0x43` 下的 `0x01...0x0C` 子协议。实现时继续复用这套体系。协议资料中的 `0xF00A78 / 0xF10A78 / 0xF30A78` 与 SDK 当前常量写法 `0xF0780A / 0xF1780A / 0xF3780A` 是 vendor opcode 表达方式差异，不新增第二套 opcode。

## 目标

- 在 SDK 中支持 WiFi Gateway 的四个私有协议：
  - `43 0D`：设置 Wi-Fi SSID/password。
  - `43 0E`：查询 Wi-Fi 连接状态。
  - `43 0F`：查询 Wi-Fi RSSI。
  - `43 12`：读取 Wi-Fi SSID/password。
- App 将来能区分业务结果类别，而不是只能依赖通用成功/失败布尔值。
- SDK 对请求参数做协议级校验，避免静默截断或生成明显非法 payload。
- SDK 严格解析响应 payload 长度、保留值和敏感字段边界。
- 不新增包含明文 Wi-Fi 密码的日志、缓存或数据库写入。

## 非目标

- 不实现 App 层 UI、菜单入口、配置流程、轮询流程或权限控制。
- 不修改 WiFi Gateway 当前页面行为。
- 不修改 4G Gateway 既有 `0x43 0x01...0x0C` 协议。
- 不新增 Auth 信息。
- 不新增本地化文案。

## 方案选择

采用方案 A：扩展现有 `SunricherVendorSet / SunricherVendorGet / SunricherVendorStatus`。

原因：

- 现有 SDK 已经统一处理 Sunricher set/get/status vendor opcode。
- `MeshMessageHandle.matchesVendorStatus` 已按 `ResponseCode` 匹配回包，新增 WiFi 子码后可避免 `43 0E`、`43 0F`、`43 12` 互相误匹配。
- 改动集中在 SDK 协议枚举、payload 编码、status typed parsing 和单元测试。
- 不需要新增一套 vendor message 分发机制。

未采用的方案：

- 新增 WiFi Gateway 专用 message 类型：隔离更强，但会重复现有 vendor status 分发和匹配逻辑，风险更高。
- 只新增 `MeshAPI` 高层 helper：底层仍需 typed 协议解析，且当前阶段不接 App 功能，API 面不应过早扩大。

## SDK 架构设计

### 协议枚举

在 `VendorGatewayCode` 中新增：

- `wifiCredentialsSet = 0x0D`
- `wifiConnectionStatusGet = 0x0E`
- `wifiRSSIStatusGet = 0x0F`
- `wifiCredentialsGet = 0x12`

在 `ResponseCode` 中新增对应 case，并补齐：

- `ResponseCode.init(opcode:subcode:)`
- `ResponseCode.code`
- `VendorFunctionSet.command / responseCommand`
- `VendorFunctionGet.command / responseCommand`

这些新增 case 只映射到 `VendorOpCode.gateway = 0x43`，不影响其它主码。

### 请求编码

`VendorFunctionSet` 新增设置凭据能力，生成：

```text
43 0D <ssid_len> <ssid> <password_len> <password?>
```

编码规则：

- SSID 使用 UTF-8 字节，长度必须为 `1...31`。
- Password 使用 UTF-8 字节，长度必须为 `0` 或 `8...63`。
- SSID 和 password 字节必须在 `0x20...0x7E`，且排除 `0x22` 和 `0x5C`。
- `password == nil` 或空字符串都表示开放 Wi-Fi，编码为 `password_len = 0`，不携带 password 字段。
- 非法输入不静默截断。SDK 应提供明确的 validation failure 机制，避免发出设备必然返回参数错误的 payload。

`VendorFunctionGet` 新增三个无参数查询：

- `.wifiGatewayConnectionStatus` -> `43 0E`
- `.wifiGatewayRSSIStatus` -> `43 0F`
- `.wifiGatewayCredentials` -> `43 12`

SDK 公共 API 只生成精确两字节查询 payload，不提供额外 trailing bytes 的正常构造入口。

## 响应解析设计

响应继续由 `SunricherVendorStatus(parameters:)` 解析，并通过 `status.parameters` 暴露 typed result。

### 设置 Wi-Fi 凭据

Payload：

```text
43 0D <ret>
```

新增结果类型 `WiFiGatewayCredentialsSetResult`：

- `0x00` -> `.accepted`
- `0x01` -> `.invalidParameters`
- `0x02` -> `.internalError`
- 其它 -> `.reserved(rawValue:)`

解析为：

```text
.wifiGatewayCredentialsSet(WiFiGatewayCredentialsSetResult)
```

`ret = 0x00` 只表示配置已接收并开始 Wi-Fi 启动或重连，不表示已连接，也不表示已持久化。

### 查询 Wi-Fi 连接状态

Payload：

```text
43 0E <result>
```

新增结果类型 `WiFiGatewayConnectionStatus`：

- `0x00` -> `.notStartedOrConnecting`
- `0x01` -> `.connected`
- `0x02` -> `.passwordError`
- `0x03` -> `.failed`
- 其它 -> `.reserved(rawValue:)`

解析为：

```text
.wifiGatewayConnectionStatus(WiFiGatewayConnectionStatus)
```

关键约定：`43 0E 01` 是“Wi-Fi 连接成功”，不是通用 ACK 失败。App 将来必须使用 typed enum 判断业务状态，不应把 `SunricherVendorStatus.Status.isSuccessful` 当作连接成功判断。

### 查询 Wi-Fi RSSI

Payload：

```text
43 0F <status> <rssi>
```

新增结果类型 `WiFiGatewayRSSIStatus`：

- `status = 0x00` 且 `rssi` 有效 -> `.valid(dbm:)`
- `status = 0x01` -> `.unavailable`
- `status = 0x02` -> `.readFailed`
- 其它 -> `.reserved(rawValue:)`

解析规则：

- 成功 payload 长度必须精确为 4。
- `status = 0x00` 时，`rssi` 按 signed int8 二进制补码解析，有效范围为 `-127...0 dBm`。
- 例如 `0xBF` 解析为 `-65 dBm`。
- `status != 0x00` 时，`rssi` 固定字节不暴露为 `0 dBm`，App 不应显示信号值。
- `status = 0x00` 但 `rssi` 超出范围或格式非法时，不解析业务参数，并将该 response 标记为解析失败。

### 读取 Wi-Fi 凭据

Payload：

```text
43 12 <status> ...
```

新增结果类型 `WiFiGatewayCredentialsReadResult`：

- `0x00` -> `.success(WiFiGatewayCredentials)`
- `0x01` -> `.notConfigured`
- `0x02` -> `.internalError`
- 其它 -> `.reserved(rawValue:)`

成功格式：

```text
43 12 00 <ssid_len> <ssid> <password_len> <password?>
```

解析规则：

- `status = 0x00` 时必须携带 SSID/password 结构，payload 长度必须与声明长度精确匹配。
- `ssid_len` 必须为 `1...31`。
- `password_len` 必须为 `0` 或 `8...63`。
- `password_len = 0` 表示开放 Wi-Fi，不携带 password 字段。
- SSID/password 是明文原始字符串，不加密、不脱敏、不持久化。
- `status = 0x01` 和 `status = 0x02` 的 payload 必须精确为 3 字节。

## 通用成功状态约定

现有 `SunricherVendorStatus.Status` 会把第三字节非 `0x00` 视为 `isSuccessful = false`。本次不把 `isSuccessful` 扩展为所有 WiFi 业务状态的真值，避免破坏旧协议调用方。

WiFi Gateway 新协议的业务判断以 `status.parameters` 中的 typed enum 为准：

- 设置凭据：`.accepted` 表示设备接收了配置。
- 连接状态：`.connected` 表示 Wi-Fi 已连接。
- RSSI：`.valid(dbm:)` 表示 RSSI 可显示。
- 读取凭据：`.success(credentials)` 表示读取成功。

对于 `43 0E 01` 这类第三字节非零但业务成功的响应，SDK 必须解析出 typed enum。App 不应仅根据 `isSuccessful` 过滤掉该响应。

## 错误处理

- 请求侧非法 SSID/password：不生成 payload，返回明确 validation failure。
- 回包短于协议最小长度：已能识别 `opcode/subcode` 时保留 `ResponseCode`，但不解析业务参数，并标记解析失败；短到无法识别 `opcode/subcode` 时才返回 nil。
- 回包存在额外 trailing bytes：不解析业务参数，并标记解析失败。
- 已知失败码：解析为 typed enum，App 可区分原因。
- 保留值：解析为 `.reserved(rawValue:)`，App 将来可按失败或暂不可用处理。
- 明文 password：SDK 不打印、不缓存、不写数据库；测试只能使用固定假数据。

## 测试设计

新增 `WiFiGatewayVendorMessageTests`。

编码测试：

- 设置普通 Wi-Fi：`43 0D <ssid_len> <ssid> <password_len> <password>`。
- 设置开放 Wi-Fi：`password_len = 0` 且不携带 password。
- SSID 长度 `0`、`32` 失败。
- Password 长度 `1...7`、`64` 失败。
- 非法字符：非可打印 ASCII、`0x22`、`0x5C` 失败。
- 查询连接状态：`43 0E`。
- 查询 RSSI：`43 0F`。
- 查询凭据：`43 12`。

解析测试：

- `43 0D 00 / 01 / 02 / FF` 分别解析为 accepted、invalid parameters、internal error、reserved。
- `43 0E 00 / 01 / 02 / 03 / FF` 分别解析为 connecting、connected、password error、failed、reserved。
- `43 0F 00 BF` 解析为 `-65 dBm`。
- `43 0F 01 00` 解析为 unavailable，且不暴露 `0 dBm`。
- `43 0F 02 00` 解析为 read failed。
- `43 12 00 ...` 解析出明文 SSID/password。
- `43 12 00 ... password_len = 0` 解析为开放 Wi-Fi。
- `43 12 01` 解析为 not configured。
- `43 12 02` 解析为 internal error。
- 各子码短包、声明长度不匹配、trailing bytes 均不解析业务参数。

匹配测试：

- `SunricherVendorGet(function: .wifiGatewayConnectionStatus)` 只能匹配 `43 0E` status。
- `43 0E` 请求不能被 `43 0F` 或 `43 12` 回包误匹配。
- 新增 `0x0D/0x0E/0x0F/0x12` 不影响旧 `0x43 0x05/0x0B/0x0C` 匹配。

## 验收

- SDK 新增测试通过。
- 优先运行 `swift test`；如果既有 UIKit 或环境问题阻塞，则运行新增测试过滤命令并记录阻塞原因。
- App 侧至少确认依赖本地 SDK 的 iPhoneOS build 可通过；按仓库规则优先使用：

```text
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

- 如修改影响 shared SDK API，后续实现阶段再评估是否补充 `Archipelago`、`SLG Sync Plus`、`SylSmart` 构建验证。
- 不出现新增明文 Wi-Fi password 日志。

## 实施范围

预计实现文件：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

不预计修改 App 源码。
