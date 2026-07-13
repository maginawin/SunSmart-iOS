# WiFi Gateway RSSI 网络状态集成设计

## 1. 目标

为 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 适配 V1.7 `43 0F` RSSI 查询响应，在 RSSI 有效时使用新增的 `network_status` 更新详情页顶部 Wi-Fi 状态，同时兼容没有 `network_status` 的旧固件成功响应。

本次改动必须保持现有 Wi-Fi 配置、连接状态、RSSI 分级和非成功 RSSI 状态的行为，不使用 `43 0E`、RSSI、MQTT 状态或其他字段推断 Internet 状态。

## 2. 当前实现与问题

当前工程已经具备以下链路：

- App 使用 `SunricherVendorGet(function: .wifiGatewayRSSIStatus)` 发送精确的 `43 0F` 查询。
- 本地 `NordicSigMeshSDK` 将旧格式 `43 0F <rssi_status> <rssi>` 解析为 `WiFiGatewayRSSIStatus`。
- `WiFiGatewayViewController` 仅在 Gateway 已配置、已连接 Wi-Fi 且页面可见时循环查询 RSSI。
- RSSI 有效时，顶部根据 RSSI 阈值展示 `Excellent`、`Good`、`Poor` 或 `Bad`；RSSI 不可用、查询失败、保留状态或解析失败时展示 `No Signal`。
- 当前轮询采用每 2 秒触发一次的重复 timer，查询 timeout 也为 2 秒。

V1.7 响应增加第五个字节 `network_status`。当前 SDK 严格要求 RSSI 响应长度为 4 字节，因此新的 5 字节响应会被判定为解析失败，App 最终错误展示 `No Signal`。当前 2 秒固定轮询也不符合“收到一轮响应后等待 5 秒再发送下一轮”的新时序要求。

## 3. 已确认的产品规则

### 3.1 RSSI 展示

当页面需要展示 RSSI 时，保持原有分级展示，不显示原始 `-65 dBm` 数值：

| RSSI 范围 | 图标与文字 |
|---|---|
| `RSSI > -60 dBm` | `Excellent` |
| `-69 dBm < RSSI <= -60 dBm` | `Good` |
| `-80 dBm < RSSI <= -69 dBm` | `Poor` |
| `RSSI <= -80 dBm` | `Bad` |

### 3.2 Internet 状态展示

只有 `rssi_status == 0x00` 时，App 才允许使用 `network_status`：

| `network_status` | 页面顶部文字 |
|---|---|
| `0x00 NORMAL` | 保持原有 RSSI 分级文字 |
| `0x01 UNAVAILABLE` | `No Internet` |
| `0x02 UNKNOWN` | `Unknown` |
| 其他保留值 | `Unknown` |

`UNAVAILABLE`、`UNKNOWN` 和保留值响应中的 RSSI 仍然有效，因此顶部继续使用该 RSSI 对应的现有信号分级图标。不得使用 `wifi_no_signal` 图标，以免把 Internet 状态误表示为 Wi-Fi 无信号。

### 3.3 旧固件兼容

旧固件可能返回 4 字节成功响应：

```text
43 0F 00 <rssi>
```

该响应在协议模型中表示 Internet 状态未报告，语义上按 Unknown 对待，但页面保持兼容行为，继续展示 RSSI 对应的 `Excellent`、`Good`、`Poor` 或 `Bad`，不展示 `Unknown`。

这样可以避免升级 App 后让尚未升级固件的 Gateway 从正常 RSSI 分级退化为 `No Signal` 或 `Unknown`。

### 3.4 非成功 RSSI 状态

当 `rssi_status != 0x00` 时保持现状：

- `0x01`：展示 `No Signal`。
- `0x02`：展示 `No Signal`。
- 其他保留值：展示 `No Signal`。
- 不解析、不保存、不展示 `network_status`。

## 4. SDK 协议设计

### 4.1 Typed result

在本地 `NordicSigMeshSDK` 中扩展 WiFi Gateway RSSI typed result，使有效 RSSI 同时携带独立的 Internet 状态。Internet 状态应能明确表达：

- `normal`
- `unavailable`
- `unknown`
- `reserved(rawValue:)`
- `notReported`：旧固件没有返回第五字节

`notReported` 必须与协议明确返回的 `UNKNOWN` 分开，保证 App 可以执行旧固件兼容展示，而不会把两者都映射成 `Unknown` 文案。

### 4.2 Payload 长度规则

SDK 按以下规则解析 `43 0F` response：

| `rssi_status` | 允许长度 | 解析规则 |
|---|---:|---|
| `0x00` | 4 字节 | 解析 RSSI，Internet 状态为 `notReported` |
| `0x00` | 5 字节 | 解析 RSSI 和 `network_status` |
| 非 `0x00` | 4 字节 | 保持现有 RSSI failure typed result |
| 非 `0x00` | 5 字节 | 保持现有 RSSI failure typed result，忽略第五字节 |
| 任意值 | 少于 4 或多于 5 字节 | 解析失败 |

对于 `rssi_status == 0x00`，RSSI 继续按 signed int8 二进制补码解析，有效范围为 `-127...0 dBm`。超出范围或格式非法时解析失败。

对于 `rssi_status != 0x00`，继续沿用当前行为，不把第四字节暴露为 `0 dBm`，也不因为第五字节存在而改变 failure category。

### 4.3 GET 编码与响应匹配

GET payload 保持精确的两个字节 `43 0F`，不修改 `SunricherVendorGet` 编码。

继续使用现有 `ResponseCode.wifiGatewayRSSIStatusGet` 和 `MeshMessageHandle.matchesResponse` 匹配响应，不新增 vendor opcode、response code 或消息基类。

## 5. App 页面设计

### 5.1 状态映射

`WiFiGatewayViewController` 收到有效 RSSI typed result 后执行以下映射：

| Internet typed 状态 | 状态文字 | 图标 |
|---|---|---|
| `normal` | RSSI 分级文字 | RSSI 分级图标 |
| `unavailable` | `No Internet` | RSSI 分级图标 |
| `unknown` | `Unknown` | RSSI 分级图标 |
| `reserved` | `Unknown` | RSSI 分级图标 |
| `notReported` | RSSI 分级文字 | RSSI 分级图标 |

RSSI unavailable、read failed、保留 `rssi_status` 和整个 response 解析失败继续走现有 `No Signal` 状态。

### 5.2 Header 边界

本次只改变 `WiFiGatewayViewController` 传给现有 header API 的 icon 和 status 文本，不修改 `GatewayInformationHeaderView` 的布局、尺寸或公开接口，不增加图片资源。

以下既有状态保持不变：

- 未配置 SSID/password：`Not Configured`
- 已配置但未连接 Wi-Fi：`Not Connected`
- Gateway 离线：保持当前页面隐藏 Network Connectivity 和停止 RSSI 查询的行为
- `rssi_status != 0x00`：`No Signal`

### 5.3 国际化

新增 WiFi 专用本地化 key，不复用语义不完整的全局 Internet 错误长文案或其他 Gateway signal key：

| 语义 | English | 简体中文 |
|---|---|---|
| Internet 不可用 | `No Internet` | `无互联网连接` |
| Internet 状态未知 | `Unknown` | `未知` |

所有新文案必须同时加入 English 和 `zh-Hans` 本地化文件。四个品牌 target 使用共享本地化资源，不修改独立 target 配置。

## 6. 轮询时序设计

### 6.1 响应驱动的单次调度

将当前 2 秒重复 timer 改为响应驱动的单次 timer：

1. Wi-Fi 状态进入 connected 且允许 RSSI 查询时，立即发送一轮 `43 0F`。
2. 本轮收到有效响应、失败响应、非法响应或 2 秒 timeout 后，完成本轮 UI 处理。
3. 从本轮 completion 时刻开始等待 5 秒。
4. 单次 timer 到期后发起下一轮查询。
5. 下一轮 completion 后再次创建新的单次 timer。

不得使用从请求发出时刻开始计算的固定 5 秒重复 timer，因为协议要求的是收到一轮响应后等待 5 秒。

### 6.2 请求冲突

页面继续复用现有单 active WiFi request gate。如果 RSSI timer 到期时存在其他 WiFi Gateway 请求，本轮不得并发发送；应在 5 秒后再次尝试，避免一次冲突导致 RSSI 轮询永久停止。

### 6.3 停止条件

以下场景继续立即取消待执行 timer，且不得再发新的 `43 0F`：

- 页面离开或关闭
- Gateway 离线
- key bind 未完成
- Wi-Fi connection status 不再是 connected
- 开始 Connect、Disconnect 或 Repair 流程

### 6.4 可见状态更新时间

采用 2 秒查询硬截止和 completion 后 5 秒等待后，一轮最坏请求周期为 7 秒。结合模组状态收敛和约 1 秒 Mesh/UI 余量：

- Wi-Fi/IP 丢失：不超过 13 秒可见
- WAN 丢失：不超过 18 秒可见
- WAN 恢复：不超过 13 秒可见

该调度与 V1.7 时序目标一致。

## 7. 修改范围

### 7.1 本地 SDK

- 修改 `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 增加 Internet typed 状态。
  - 扩展 `WiFiGatewayRSSIStatus` 的有效结果。
  - 支持 V1.7 5 字节响应和旧 4 字节成功响应。
- 修改 `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
  - 覆盖新旧 payload、保留值和非法长度。

### 7.2 App

- 修改 `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - 增加 Internet 状态到 header 的映射。
  - 保持现有 RSSI 阈值。
  - 将固定重复 timer 改为 completion 后单次调度。
- 修改 `SunSmart/en.lproj/Localizable.strings`。
- 修改 `SunSmart/zh-Hans.lproj/Localizable.strings`。
- 修改 `scripts/check_wifi_gateway_wifi_status_header.sh`。

### 7.3 明确不修改

- `GatewayInformationHeaderView` 布局和接口
- Wi-Fi 图片资源
- `43 0E` Wi-Fi connection status
- `43 0D` credentials set、`43 12` credentials get、`43 13` clear credentials
- Network Connectivity 的编辑、Refresh、Connect 和 Disconnect 行为
- 4G Gateway 页面
- CocoaPods、Swift Package 引用路径和 target 配置
- MQTT、cloud 或 server authorization 状态链路

## 8. 测试与验证

### 8.1 SDK parsing tests

必须覆盖：

- 新版 `NORMAL`、`UNAVAILABLE`、`UNKNOWN`
- 新版保留 `network_status`
- 旧版 4 字节成功响应
- `rssi_status` 为 `0x01`、`0x02` 和保留值时的 4/5 字节响应
- `-127 dBm`、`0 dBm` 和常见负 RSSI
- 非法正数、`-128 dBm`、缺字节和 trailing bytes
- GET 编码仍精确为 `43 0F`
- response matching 仍只匹配当前 Gateway、当前 subcode

### 8.2 App contract tests

扩展现有 focused shell contract，检查：

- `NORMAL` 和 `notReported` 使用原有 RSSI 分级
- `UNAVAILABLE` 映射为 `No Internet`
- `UNKNOWN` 和保留值映射为 `Unknown`
- 非成功 `rssi_status` 继续映射为 `No Signal`
- RSSI 阈值未改变
- completion 后 5 秒单次调度，不再存在 2 秒重复 RSSI timer
- English 和简体中文文案完整

### 8.3 构建验证

按项目规则执行 generic iPhoneOS、Debug、关闭签名的构建验证：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`
- 本地 SDK 的 `NordicSigMeshDemo`

同时运行相关 focused shell contracts 和 `git diff --check`。若 macOS `swift test` 仍被 SDK 的既有 UIKit 依赖阻断，以 SDK tests 的静态覆盖、App 四 target build 和 SDK Demo iPhoneOS build 作为本仓库的有效验收证据。

## 9. 验收标准

满足以下条件时视为完成：

1. V1.7 `43 0F 00 <rssi> <network_status>` 能被 SDK 正确解析。
2. `NORMAL` 保持原有 RSSI 分级展示，不显示原始 dBm。
3. `UNAVAILABLE` 展示 `No Internet`。
4. `UNKNOWN` 和保留 `network_status` 展示 `Unknown`。
5. 旧 4 字节成功响应继续展示原有 RSSI 分级。
6. `rssi_status != 0x00` 的页面行为保持为 `No Signal`。
7. `network_status` 不会在非成功 RSSI 状态中被解析或用于 UI。
8. 下一轮查询只会在上一轮 completion 后等待 5 秒再发出。
9. 页面退出、Gateway 离线或 Wi-Fi 断开后不会继续轮询。
10. 新文案具备 English 和简体中文翻译。
11. focused contracts、`git diff --check`、四个 App target 和 SDK Demo 构建通过。

