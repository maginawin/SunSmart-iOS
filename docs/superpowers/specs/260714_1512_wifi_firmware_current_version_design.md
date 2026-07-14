# WiFi Firmware Current Version 设计

## 1. 目标

为 WiFi Gateway（CID `0x0A78`、PID `0x2721`）增加实时 WiFi firmware version 查询能力，并接入现有 `WiFi Firmware Update` 页面：

- SDK 实现 Vendor GET `43 14` 及严格应答解析。
- App 进入页面后并行获取云端 New version 与网关 Current version。
- 页面将 `Current target version` 改为 `Current version`，初始显示 `Loading...`。
- 只有 New version 严格高于 Current version 时启用 `UPGRADE`。

本次不实现真实 WiFi DFU。`UPGRADE` 点击后继续显示现有 `under_development` 提示。

## 2. 当前实现与约束

- `WiFiGatewayViewController.moreClick()` 已提供 `WiFi DFU` 菜单入口。
- `WiFiFirmwareUpdateViewController` 已复用 `FirmwareVersionViewController` 的布局、云端查询、历史列表和 dev profile 查询。
- 当前 WiFi 页面把云端版本展示为 `Current target version`，并无条件认为有效云端固件可升级。
- 当前 WiFi controller 没有目标 `Node`，无法发送面向当前网关的 Vendor GET。
- App 已通过本地 Swift Package 引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- SDK 已有 `43 0D`、`43 0E`、`43 0F`、`43 12`、`43 13` 的 Gateway vendor routing、response matching 和 typed result 模式。

实现必须保持改动聚焦，不改变 4G Gateway、BLE/Mesh Firmware Update 或其它品牌 target 的既有行为。

## 3. 方案选择

采用方案 A：在共享 `FirmwareVersionViewController` 增加窄扩展点，由 `WiFiFirmwareUpdateViewController` 管理设备实时版本状态。

未采用：

- 不复制完整固件页面到 WiFi controller，避免重复约 500 行 UI 与云端请求逻辑。
- 不把所有固件页面迁移到新的通用双数据源模型，避免本次需求扩大为 BLE/Mesh 固件页面重构。

## 4. SDK 设计

### 4.1 请求编码

沿现有 `SunricherVendorGet` pipeline 增加 WiFi firmware version 查询：

- Vendor Opcode：`0xF10A78`，SDK access-layer 表示继续遵循现有 byte-order 约定。
- Payload 永远为精确的 `43 14` 两字节。
- API 不接收额外参数，因此调用方无法生成带 trailing bytes 的请求。

### 4.2 Response routing

增加独立的 Gateway subcode 和 `ResponseCode`：

- `VendorGatewayCode` 增加 `0x14`。
- `VendorFunctionGet` 增加 WiFi firmware version 查询。
- `ResponseCode` 将 Gateway `0x43/0x14` 映射为独立 response code。
- response code 的编码返回 `43 14`，使 `MeshMessageHandle.matchesResponse` 只匹配本次查询结果，不接受其它 Gateway subcode。

### 4.3 Typed result

SDK 暴露以下等价语义的结果类型：

| ret | Typed result | `isSuccessful` |
| --- | --- | --- |
| `0x00` | success(version) | true |
| `0x01` | invalidParameters | false |
| `0x02` | busy | false |
| `0x03` | queryFailed | false |
| `0x04` | deadlineExceeded | false |
| 其它 | reserved(rawValue) | false |

非成功结果保留原始 `errorCode`。App 本轮统一显示失败，但 SDK 不压扁 ret 语义。

### 4.4 严格解析

成功应答必须满足：

- payload 精确为 `43 14 00 version_len version`；
- `version_len` 为 `1...32`；
- `version_len` 与剩余字节数完全一致；
- version 仅包含可展示 ASCII 字节 `0x20...0x7E`；
- 不允许任何 trailing bytes。

失败应答必须满足：

- payload 精确为 `43 14 ret` 三字节；
- `ret!=0x00`；
- 不允许任何 trailing bytes。

长度错误、非 ASCII、控制字符、缺少 version length、version length 非法或声明长度不匹配时，`SunricherVendorStatus` 仍可识别 response code，但 parameters 为 nil，整体按解析失败处理。

### 4.5 Delegate 行为

`VendorServerDelegate` 对该只读结果保持 no-op：

- 不写入 `Node.firmwareVersion`；
- 不写数据库或云端；
- 不缓存 WiFi firmware version；
- 不改变其它 Gateway 信息。

## 5. App 设计

### 5.1 页面入口

- `WiFiFirmwareUpdateViewController` 改为由当前 `Node` 初始化。
- `WiFiGatewayViewController` 的 `WiFi DFU` 菜单把 `self.node` 传入新页面。
- 页面只查询传入 node 的 `sunricherVendorModel`。
- node 没有 Vendor Model、未 key bind 或已离线时，不发送 `43 14`，Current version 进入 failed 状态。

WiFi DFU 仍可作为只读页面进入，不新增 Owner/Editor 权限门槛。真实升级尚未实现，因此本轮不增加升级权限判断。

### 5.2 双数据源

页面有两个互相独立的数据源：

- New version：现有云端 latest firmware 请求，身份保持 `manufacturerId=0A78`、`deviceType=2721`、`customerId=wifi`；dev 查询继续使用现有 profile 规则。
- Current version：当前网关实时返回的 `43 14` success version。

首次进入页面时并行发起两项查询。任一请求完成后只更新自身状态，再统一重算 UI；不得用一项结果代替另一项。

### 5.3 Current version 状态

WiFi 页面维护三个状态：

| 状态 | 页面展示 | `UPGRADE` |
| --- | --- | --- |
| loading | `Loading...` | 禁用 |
| loaded(version) | 网关返回的 version | 按联合比较决定 |
| failed | `Failed` | 禁用 |

进入页面和每次 Refresh 开始时都先进入 loading，清除上一次 Current version，防止旧版本参与新一轮比较。

以下情况进入 failed：

- ret 为 `0x01...0x04` 或保留值；
- SDK 解析失败；
- App 等待超时；
- node 离线、未 key bind 或没有 Vendor Model；
- 回调不是匹配的 WiFi firmware version result。

### 5.4 UI 扩展点

共享 `FirmwareVersionViewController` 增加当前需求所需的窄扩展能力：

- Current version 标题；默认仍为 `Current target version`。
- Current version 展示文本；默认仍来自本地 firmware cache。
- 是否需要在云端请求结束前创建 UI；默认保持历史页面行为，WiFi 页面开启立即创建。
- 页面首次加载和 Refresh 时触发附加数据加载。
- 子类在附加数据返回后请求共享页面刷新 UI。
- 附加数据失败是否要求展示 Refresh。

共享默认值必须保持 BLE/Mesh 固件页面现有行为。WiFi 子类覆盖标题、Current version 状态和联合升级判断，不复制整套页面。

### 5.5 Refresh

现有 Refresh 在 WiFi 页面执行联合重试：

1. 清除旧云端 `serverData` 与旧错误状态。
2. Current version 重置为 loading。
3. 禁用 `UPGRADE`。
4. 并行发起云端请求和 `43 14` 查询。

云端或设备任一数据源失败时，页面必须提供 Refresh。Refresh 不复用上一轮任一成功值参与比较。

### 5.6 App timeout

网关协议的 5 秒是网关从收到合法 GET 到发出最终 RET 的内部截止。App 使用现有 10 秒 Mesh response timeout，为网关处理和 Mesh 传输留出余量：

- 网关在内部 5 秒到期时应返回 typed `deadlineExceeded`；
- App 不把自身 timeout 也设为 5 秒，避免与 `ret=0x04` 同时到期而丢失诊断信息；
- 10 秒仍无匹配 response 时，App 按 failed 展示。

### 5.7 页面生命周期

- 页面销毁后忽略延迟回调。
- 查询结果不持久化。
- 返回 WiFi Gateway 页面时，现有 RSSI/Network Connectivity 生命周期按原逻辑恢复。
- 不引入自动轮询 Current version。

## 6. 版本比较

New version 与 Current version 使用同一规范化规则：

1. 如果首字符为小写 `v` 或大写 `V`，只移除这一个字符。
2. 移除后为空则不可比较。
3. 使用项目现有 `String.compare(options: .numeric)` 比较。
4. 只有 New version 相对 Current version 为 `.orderedDescending` 时启用 `UPGRADE`。

以下情况均禁用：

- New version 等于 Current version；
- New version 低于 Current version；
- 任一数据源 loading、failed 或缺失；
- 任一版本规范化后为空；
- 云端响应字段或 PID 校验失败。

不补齐版本段，不定义 prerelease 权重，不对异常字符串做猜测性升级判断。

## 7. UI 与国际化

- WiFi 页面当前版本标题使用英文 `Current version`。
- 简体中文对应 `当前版本`。
- 初始值复用现有 `Loading...` key。
- 失败值复用现有 `failed` key；英文实际展示为 `Failed`。
- 其它固件页面继续使用 `Current target version`，不改变既有 key 或文案。
- `New version`、页面标题和 `UPGRADE` 文案保持现状。

如不存在 `current_version` key，则新增并同步 English 与简体中文；不得硬编码用户可见文案。

## 8. 错误状态矩阵

| 云端 New version | 设备 Current version | 页面结果 |
| --- | --- | --- |
| loading | 任意 | `UPGRADE` 禁用 |
| valid | loading | Current 显示 `Loading...`，`UPGRADE` 禁用 |
| valid | failed | Current 显示 `Failed`，提供 Refresh，`UPGRADE` 禁用 |
| failed/not found | valid | 沿用云端错误或无固件状态，提供适用的 Refresh，`UPGRADE` 禁用 |
| valid | valid，New > Current | 显示新版本信息，`UPGRADE` 启用 |
| valid | valid，New <= Current | 显示已是最新版本，`UPGRADE` 禁用 |

## 9. 影响范围

### SDK

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `Sources/NordicSigMeshSDK/MeshLib/MessageDelegate/VendorServerDelegate.swift`
- `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

### App

- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `scripts/check_wifi_gateway_firmware_update.sh`

不修改 Swift Package 引用方式；工程当前已使用本地 SDK 路径。

## 10. 测试设计

### 10.1 SDK focused tests

- GET 编码精确为 `43 14`。
- success 支持长度 1、长度 32 和常规点分数字版本。
- `0x01...0x04` 及未知 ret 正确映射 typed result。
- success 缺少 length、length 为 0、length 大于 32、声明长度不符、非 ASCII、控制字符和 trailing bytes 均拒绝。
- 非 success 带 trailing bytes 拒绝。
- `MeshMessageHandle` 只匹配同 source 的 `43 14`，拒绝 `43 0E`、`43 0F` 等其它 response。

### 10.2 App focused contracts

- 菜单传递当前 node。
- WiFi 页面标题为 `Current version`，其它固件页面标题不变。
- 初始值、Refresh loading、success 和 failed 展示正确。
- Refresh 同时触发云端和设备查询。
- New > Current 启用；New = Current、New < Current、缺失、失败和不可比较均禁用。
- `v/V` 规范化规则生效。
- `UPGRADE` 仍调用现有 `under_development` 行为。

### 10.3 回归与构建

- 运行 WiFi Gateway focused scripts。
- 运行 `git diff --check`。
- SDK `swift test` 若仍被现有 macOS `UIKit` 限制阻断，不把它误判为协议实现失败。
- 直接执行 Debug iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。
- 构建本地 SDK `NordicSigMeshDemo` 的 iPhoneOS target。

## 11. 验收标准

- 进入页面立即显示 `Current version: Loading...`。
- App 发送精确 `43 14`。
- 合法成功响应展示实时 WiFi firmware version。
- 所有协议失败、解析失败、无 model、离线和 App timeout 都显示 `Failed`，且不保留旧值。
- Refresh 同时刷新 Current version 与 New version。
- 只有 New version 严格高于 Current version 时 `UPGRADE` 可用。
- `UPGRADE` 点击仍显示 `under_development`。
- 其它 Gateway、BLE/Mesh 固件页面和四个品牌 target 无行为或构建回归。
