# WiFi Gateway DFU SDK 设计

## 1. 目标

在本地 `NordicSigMeshSDK` 中实现 WiFi Gateway 的以下私有协议能力：

- `43 10`：下发互联网接入模组 OTA metadata，并解析 metadata 接收结果。
- `43 11`：查询互联网接入模组 OTA 状态，并解析查询应答或网关主动进度上报。

本轮只提供 SDK 消息编码、严格参数校验、强类型应答解析和 response matching，不实现 App 页面、升级业务流程、自动轮询、状态缓存或 OTA session 管理。

## 2. 现有代码基础

本地 SDK 已有统一的 Sunricher Vendor 消息框架：

- `SunricherVendorSet` 对应 Vendor Opcode `0xF00A78`。
- `SunricherVendorGet` 对应 Vendor Opcode `0xF10A78`。
- `SunricherVendorStatus` 对应 Vendor Opcode `0xF30A78`。
- `VendorOpCode.gateway` 已表示业务 opcode `0x43`。
- `VendorGatewayCode`、`ResponseCode` 和现有 response matching 已按主码、子码区分请求和应答。
- 现有 WiFi Gateway 协议已经采用强类型参数和结果模型，并在 SDK 边界执行输入校验。

因此本功能直接扩展现有 Gateway routing，不新增 vendor 基础消息层，也不创建另一套 DFU transport。

## 3. 已确认的设计决策

### 3.1 SDK 构造阶段严格拒绝非法 metadata

`43 10` 不接受未经校验的原始字符串集合。SDK 提供 throwing metadata value object，在生成 Mesh payload 前完成全部参数校验。

严格校验包括完整业务 payload 从 `43` 起不超过 256 字节。即使 Mesh 传输层仍可能因为自身能力拒绝消息，SDK 也不能主动生成协议已明确禁止的超长业务 payload。

### 3.2 保持 SDK 与 App 职责分离

SDK 只表达协议事实：

- `43 10 00` 表示 metadata 已被网关接收，不表示 OTA 成功。
- `43 11` 中 `ret=0x00` 表示状态消息格式正常，不表示 OTA 成功。
- 只有 `stage=0x08 SUCCESS` 才是协议层的 OTA 最终成功状态。

SDK 不在收到 `43 10 00` 后自动轮询，不以 percent 推断成功，不维护本轮 firmware ID，也不将旧状态与新 OTA session 自动关联。上述行为留给下一次 App 功能规划。

### 3.3 查询应答和主动上报使用同一解析模型

`43 11` 查询应答和网关主动进度上报具有相同 payload，因此统一解析为同一个强类型状态结果。主动上报不要求存在对应的 `SunricherVendorGet` 请求对象。

### 3.4 不强制 stage 与 code 的业务组合

SDK 严格检查长度、ASCII、percent 和字段边界，但不因为 stage/code 组合不符合文档建议而丢弃整个消息。例如收到 `SUCCESS + VERSION_MISMATCH` 时，SDK保留两个原始 typed 值，交给上层判定为协议或网关异常。

## 4. `43 10` Start WiFi DFU

### 4.1 Metadata 模型

新增公开类型 `WiFiGatewayDFUMetadata`，包含：

- `url: String`
- `sha256: String`
- `size: UInt32`
- `firmwareID: String`

公开 initializer 使用 `throws`。模型内部保存通过校验的 ASCII bytes，消息编码直接使用这些 bytes，避免校验结果和最终编码不一致。

新增 `WiFiGatewayDFUMetadataField`，用于标识 URL 或 firmware ID 字段。

新增 `WiFiGatewayDFUMetadataValidationError`，至少区分：

- URL scheme 非法。
- URL 或 firmware ID 包含非法字节。
- SHA256 长度不是 64 字节。
- SHA256 包含非十六进制 ASCII 字节。
- size 为 0。
- firmware ID 长度不在 `1...32`。
- 完整业务 payload 超过 256 字节。

### 4.2 输入校验

URL 必须：

- 以区分大小写的 `http://` 开头。
- 使用 ASCII 字节。
- 每个字节位于 `0x20...0x7E`。
- 不包含双引号 `0x22`、CR `0x0D` 或 LF `0x0A`。

协议没有禁止反斜杠，因此 SDK 不增加该限制。URL 不单独设置固定最大长度，而是由完整 payload 的 256 字节上限约束。

SHA256 必须：

- 恰好为 64 个 ASCII 字节。
- 每个字节属于 `0...9`、`a...f` 或 `A...F`。
- 编码时保留调用方提供的大小写，不做规范化。

size 必须大于 0。

firmware ID 必须：

- 长度为 `1...32` 个 ASCII 字节。
- 每个字节位于 `0x20...0x7E`。
- 不包含双引号 `0x22`、CR `0x0D` 或 LF `0x0A`。
- 不由 SDK 自动删除前导 `v/V`，保持调用方目标标识原值。

完整业务 payload 长度严格按 `73 + urlBytes.count + firmwareIDBytes.count` 计算，并要求不超过 256 字节。

### 4.3 SET 编码

扩展项：

- `VendorGatewayCode.wifiDFUStart = 0x10`
- `ResponseCode.wifiGatewayDFUStart`
- `VendorFunctionSet.wifiGatewayDFUStart(WiFiGatewayDFUMetadata)`

编码字段依次为：

1. `0x43`
2. `0x10`
3. URL 长度，U16 Little Endian
4. URL ASCII bytes
5. SHA256 的 64 字节十六进制 ASCII
6. size，U32 Little Endian
7. firmware ID 长度，U8
8. firmware ID ASCII bytes

### 4.4 SET 应答

新增 `WiFiGatewayDFUStartResult`：

- `.accepted`
- `.invalidParameters`
- `.busy`
- `.internalError`
- `.internetUnavailable`
- `.reserved(rawValue: UInt8)`

`FunctionParameters` 新增 `.wifiGatewayDFUStart(WiFiGatewayDFUStartResult)`。

所有 `43 10` 应答必须精确为三个字节。任何 trailing bytes 都使 typed parameters 解析失败，并令 `status.isSuccessful` 为 false。

只有 `.accepted` 对应 `status.isSuccessful == true`；其它定义值和保留值保留 `errorCode`。

## 5. `43 11` Get WiFi DFU Status

### 5.1 GET 编码

扩展项：

- `VendorGatewayCode.wifiDFUStatusGet = 0x11`
- `ResponseCode.wifiGatewayDFUStatusGet`
- `VendorFunctionGet.wifiGatewayDFUStatus`

SDK 生成的 payload 固定为精确的 `43 11`，不提供附加参数入口，因此不会生成 trailing bytes。

### 5.2 Stage 模型

新增 `WiFiGatewayDFUStage`：

- `.idle`
- `.downloading`
- `.verifying`
- `.verifyOK`
- `.verifyFail`
- `.rebooting`
- `.recovering`
- `.versionCheck`
- `.success`
- `.timeout`
- `.failed`
- `.reserved(rawValue: UInt8)`

定义值依次映射 `0x00...0x0A`。未知值不得映射为成功或解析失败。

### 5.3 Code 模型

新增 `WiFiGatewayDFUCode`，映射：

- `0x00` `.none`
- `0x01` `.noNetwork`
- `0x02` `.http`
- `0x03` `.sizeMismatch`
- `0x04` `.verify`
- `0x05` `.versionRejected`
- `0x06` `.noPartition`
- `0x07` `.noMemory`
- `0x08` `.otaBegin`
- `0x09` `.otaWrite`
- `0x0A` `.otaEnd`
- `0x0B` `.setBoot`
- `0x0C` `.internalError`
- `0x0D` `.triggerError`
- `0x0E` `.triggerTimeout`
- `0x0F` `.triggerBusyTimeout`
- `0x10` `.otaTimeout`
- `0x11` `.protocolError`
- `0x12` `.versionProtocol`
- `0x13` `.versionMissing`
- `0x14` `.versionQueryError`
- `0x15` `.versionQueryTimeout`
- `0x16` `.versionMismatch`
- `0x17` `.recoveryTimeout`
- `0x18...0xFF` `.reserved(rawValue: UInt8)`

### 5.4 状态和结果模型

新增 `WiFiGatewayDFUStatus`：

- `stage: WiFiGatewayDFUStage`
- `percent: UInt8`
- `code: WiFiGatewayDFUCode`
- `firmwareID: String?`
- `moduleVersion: String?`

长度为 0 的 firmware ID 或 module version 映射为 `nil`，不创建空字符串。

新增 `WiFiGatewayDFUStatusResult`：

- `.success(WiFiGatewayDFUStatus)`
- `.invalidParameters`
- `.reserved(rawValue: UInt8)`

`FunctionParameters` 新增 `.wifiGatewayDFUStatus(WiFiGatewayDFUStatusResult)`。

这里的 `.success` 仅表示 `ret=0x00` 且 payload 合法，不等价于 `WiFiGatewayDFUStage.success`。

### 5.5 正常状态解析

正常状态要求：

- `ret == 0x00`。
- percent 位于 `0...100`。
- firmware ID 长度位于 `0...32`。
- module version 长度位于 `0...32`。
- 两个字符串的实际字节数与各自 length 字段完全一致。
- 两个字符串只包含可打印 ASCII `0x20...0x7E`。
- 解析完 module version 后不得存在 trailing bytes。

响应字段没有声明禁止双引号，因此接收解析只执行可打印 ASCII 校验，不额外拒绝双引号。该规则也与现有 `43 14` version 响应解析保持一致。

SDK 保留未知 stage 和 code。SDK 不修改 percent，不根据 stage/code 自动生成错误，也不以 `percent=100` 推断 OTA 成功。

### 5.6 错误状态解析

`ret != 0x00` 时必须使用精确的三字节短应答：

- `0x01` 映射为 `.invalidParameters`。
- 其它值映射为 `.reserved(rawValue:)`。

短应答携带 trailing bytes 时视为 malformed response。

## 6. Response Matching 与主动上报

新增的两个 `ResponseCode` 都使用 `[0x43, subcode]` 参与现有 vendor response matching：

- `wifiGatewayDFUStart` 只匹配 `43 10`。
- `wifiGatewayDFUStatusGet` 只匹配 `43 11`。

它们不能与 `43 14` 或其它 Gateway 子命令互相匹配。

网关主动发送的 `43 11` 仍由 `SunricherVendorStatus` 独立解析。SDK 本轮不新增 manager、缓存或通知封装；现有消息接收方可以从 `FunctionParameters.wifiGatewayDFUStatus` 获取强类型状态。

## 7. 文件影响范围

SDK 修改：

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`
- `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

`VendorServerDelegate` 只补充新增 SET case 的 compile-safe no-op，不缓存 URL、SHA256、firmware ID 或 OTA 状态。

App 仓库除本设计文档外不修改业务代码、UI、本地化、资源或 target 配置。

## 8. 测试范围

### 8.1 Metadata 和 SET 编码

- 验证完整 `43 10` payload 字段顺序。
- 验证 U16 URL 长度和 U32 size 使用 Little Endian。
- 验证完整 payload 恰好 256 字节可创建，257 字节被拒绝。
- 验证 `http://` 与 `https://`。
- 验证 URL 和 firmware ID 的非 ASCII、不可打印字符、双引号、CR 和 LF。
- 验证 SHA256 长度、大小写十六进制和非法字符。
- 验证 size 为 0。
- 验证 firmware ID 长度 1、32、0、33。

### 8.2 `43 10` 应答

- 覆盖 `0x00...0x04`。
- 覆盖保留 ret。
- 覆盖所有短应答的 trailing bytes。

### 8.3 `43 11` 编码和解析

- 验证 GET 精确编码为 `43 11`。
- 表驱动覆盖全部定义 stage。
- 表驱动覆盖全部定义 code 和保留 code。
- 覆盖 firmware ID、module version 的 0 字节和 32 字节边界。
- 覆盖 percent 0、100、101。
- 覆盖字段不足、长度不匹配、非法 ASCII 和 trailing bytes。
- 覆盖 `43 11 01`、保留 ret 和错误短应答 trailing bytes。
- 验证语义不一致的 stage/code 仍被保留，而不是静默丢弃。

### 8.4 Response matching

- 验证 `43 10` SET 只匹配 `43 10`。
- 验证 `43 11` GET 只匹配 `43 11`。
- 验证 `43 10`、`43 11`、`43 14` 不会互相串包。
- 验证 `43 11` payload 可以脱离 GET request 独立构造并解析为主动上报状态。

## 9. 验证标准

实现阶段按 TDD 先写失败测试，再加入最小实现。

验证顺序：

1. 运行 `WiFiGatewayVendorMessageTests` 定向测试。
2. 如果 SwiftPM 测试继续被 SDK 既有的 macOS/UIKit 限制阻塞，记录原始错误，不将其描述为测试通过。
3. 使用 iPhoneOS 构建 `NordicSigMeshSDK` scheme。
4. 使用 iPhoneOS 分别构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 App scheme。
5. 不使用 Simulator，不用 shell 包装或日志重定向。

## 10. 明确不在本轮实现的内容

- App 触发升级。
- 云端固件 metadata 获取或下载。
- 自动轮询 `43 11`。
- 接收主动进度后的 UI 更新。
- OTA session、超时、重试或恢复策略。
- 以本轮 firmware ID 过滤旧状态。
- `IDLE` 的 App 展示规则。
- stage/code 到用户文案的映射。
- OTA 完成后自动查询 `43 14`。
- UPGRADE 按钮状态和实际升级操作。

这些内容在下一次 App 功能规划中结合页面状态机、云端 New version 和当前 `43 14` 能力单独设计。
