# WiFi Gateway DFU SDK 实施总结

## 1. 实施范围

本轮仅在本地 `NordicSigMeshSDK` 中实现 WiFi Gateway 以下协议：

- `43 10` Start WiFi DFU：严格校验并编码 OTA metadata，解析 metadata 接收结果。
- `43 11` Get WiFi DFU Status：编码精确 GET payload，解析查询应答及网关主动进度上报。

未修改 App 业务代码、页面、文案、资源或 target 配置；未实现自动轮询、OTA session、状态缓存、firmware ID 归属判断或升级 UI。

## 2. SDK 提交

- `ebca413 feat: add wifi gateway dfu start protocol`
- `7283f5d feat: add wifi gateway dfu status protocol`

SDK 分支：`dev`。

## 3. Public API

### 3.1 Start DFU

- `WiFiGatewayDFUMetadata`
- `WiFiGatewayDFUMetadataField`
- `WiFiGatewayDFUMetadataValidationError`
- `WiFiGatewayDFUStartResult`
- `VendorFunctionSet.wifiGatewayDFUStart`
- `FunctionParameters.wifiGatewayDFUStart`

metadata initializer 在 SDK 构造阶段严格检查：

- URL 必须以区分大小写的 `http://` 开头。
- URL 和 firmware ID 必须为允许的可打印 ASCII，并拒绝双引号、CR 和 LF。
- SHA256 必须为 64 字节十六进制 ASCII，接受大小写。
- size 必须大于 0。
- firmware ID 长度必须为 `1...32`。
- 完整业务 payload 必须满足 `73 + url_len + firmware_id_len <= 256`。

`43 10` ACK 必须精确为三个字节；定义 ret `0x00...0x04` 和保留值均保留为强类型结果。只有 `0x00 accepted` 的 `status.isSuccessful` 为 true。

### 3.2 Get DFU Status

- `VendorFunctionGet.wifiGatewayDFUStatus`
- `WiFiGatewayDFUStage`
- `WiFiGatewayDFUCode`
- `WiFiGatewayDFUStatus`
- `WiFiGatewayDFUStatusResult`
- `FunctionParameters.wifiGatewayDFUStatus`

`43 11` parser 严格检查：

- GET payload 固定为 `43 11`。
- `ret=0x00` 正常消息必须完整携带 stage、percent、code、两个长度字段和对应字符串。
- percent 必须位于 `0...100`。
- firmware ID 和 module version 长度必须位于 `0...32`，且实际长度精确匹配。
- 接收字符串只接受可打印 ASCII。
- 不允许 trailing bytes。
- 未知 stage、code 和 ret 保留 raw value，不映射为成功。
- 不强制修改或丢弃语义不一致的 stage/code 组合。

查询应答和网关主动上报使用同一个 `SunricherVendorStatus` parser。`ret=0x00` 只代表状态 payload 合法，只有 `stage=0x08 SUCCESS` 表示协议定义的 OTA 最终成功。

## 4. SDK 修改文件

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`
- `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

`VendorServerDelegate` 对 Start DFU 仅增加 compile-safe no-op，不缓存 URL、SHA256、firmware ID 或 OTA 状态。

## 5. 测试与验证

### 5.1 XCTest 状态

执行：

`swift test --filter WiFiGatewayVendorMessageTests`

结果：阻塞，未运行到 XCTest 用例。既有 SDK 在 macOS SwiftPM 构建时于以下位置失败：

`Sources/NordicSigMeshSDK/MeshLib/Manager/MeshDeviceProvisioningManager.swift:8:8: error: no such module 'UIKit'`

因此本轮不宣称 `WiFiGatewayVendorMessageTests` 已执行通过。新增测试文件另以 Swift frontend parse 检查语法，exit code 为 0；该检查不替代 XCTest 执行。

测试源码覆盖：

- `43 10` Little Endian wire encoding。
- metadata 全部输入限制及 256/257 字节边界。
- `43 10` 全部 ret、保留 ret 和 trailing bytes。
- `43 11` GET 编码、全部定义 stage/code、保留值。
- 空版本、32 字节版本、percent、非法 ASCII、长度不匹配和 trailing bytes。
- 语义冲突 stage/code 的原值保留。
- `43 10`、`43 11`、`43 14` response matching 防串包及 source address 隔离。

### 5.2 iPhoneOS 构建

以下构建均使用 Debug、`generic/platform=iOS` 和 `CODE_SIGNING_ALLOWED=NO`，实际结果均为 `BUILD SUCCEEDED`：

- NordicSigMeshSDK
- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

App 四个 target 的 package resolution 均确认使用本地 SDK：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

## 6. 内联代码审查结论

按已批准设计逐项检查了消息方向、subcode、长度、ret、stage、code、主动上报和 response matching：

- `43 10` 与 `43 11` 均复用既有 Gateway vendor routing，没有新增重复 transport。
- `43 10`、`43 11`、`43 14` 使用独立 `ResponseCode`，不会按不同子码互相匹配。
- SDK 未把 metadata accepted、percent 100 或状态查询成功误判为 OTA 成功。
- SDK 未增加 App 状态、自动轮询或缓存，保持本轮 SDK-only 范围。

未发现需要阻止交付的 Critical 或 Important 问题。

## 7. 后续范围

下一次 App 功能规划需要单独设计：

- 从云端固件信息构造 `WiFiGatewayDFUMetadata`。
- 用户触发 Start DFU。
- 只在 `43 10 00` 后进入本轮 `43 11` 状态处理。
- 以本轮 firmware ID 过滤旧状态或诊断状态。
- 主动上报与轮询的协调、超时和页面生命周期。
- stage/code 到 UI 文案、进度和终态的映射。
- OTA 成功后使用 `43 14` 刷新当前 WiFi firmware version。
