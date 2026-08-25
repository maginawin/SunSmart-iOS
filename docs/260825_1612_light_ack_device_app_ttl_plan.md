# Light ACK Rx / App Tx TTL 分析与开发方案

## 需求目标

在 Lab 同时开启以下配置：

- `Display light ACK details`
- `Override Light/Group control TTL`

并把 `Light/Group Control TTL` 设置为 `25` 后，Lights 列表或 Light Detail 发送 acknowledged 灯控命令。收到设备 ACK 后，在现有 `Result ...` 行下方增加：

`ACK Rx TTL 25 (App Tx TTL 25)`

其中：

- `ACK Rx TTL`：App 实际收到 ACK 时，该 Network PDU 中的剩余 TTL。
- `App Tx TTL`：本次 App 灯控命令实际采用的发送 TTL；必须在发送时固化，不能在 ACK 返回后重新读取 Lab 设置。

本需求用于同时排查两个争议：

1. App 是否真的按 Lab 的 `Light/Group Control TTL` 下发命令。
2. 设备回复 ACK 时使用的 TTL 是否符合预期。

## 核心结论

### 1. 设备 ACK 有 TTL，但不在 ACK 的 Access payload 内

以 `GenericOnOffSet` / `GenericOnOffStatus` 为例：

- `GenericOnOffStatus` 的 opcode 和 parameters 中没有 TTL 字段。
- 承载该 Status 的 Bluetooth Mesh Network PDU 固定有 `CTL + TTL` 字段，其中 TTL 为 7 bit。
- 因此，不能从 `GenericOnOffStatus`、`LightLightnessStatus` 或 `LightCTLTemperatureStatus` 对象本身读取 TTL；必须保留 SDK 解码 Network PDU 时得到的接收元数据。

Bluetooth Mesh Protocol 1.1 的 Network PDU 定义：

- https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html

### 2. 当前 SDK 已经解出 TTL，但向上层传递时丢失

当前本地 SDK：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

接收链路如下：

1. `NetworkPdu` 从解密后的 Network header 读取 `ttl = deobfuscatedData[0] & 0x7F`。
2. `AccessMessage(fromUnsegmentedPdu:)` 从 `NetworkPdu` 构造 Lower Transport Access Message，但当前没有保存 `networkPdu.ttl`。
3. `UpperTransportPdu`、`AccessPdu` 继续只传 source、destination、sequence、IV Index、opcode 和 parameters。
4. `NetworkManager.notifyAbout(newMessage:from:to:)` 与 `MeshNetworkManager.waitFor(...)` 最终只回调 `MeshMessage`。
5. `MeshAPI.sendMessage(... result:)` 只向 App 返回 `StaticMeshResponse?`。

所以现有 `LightAckProgressTracker.finish(...)` 能拿到 ACK 类型，却拿不到承载该 ACK 的 Network PDU TTL。

### 3. `ACK Rx TTL` 是 App 收到 ACK 时的剩余 TTL

TTL 每经过一个 Relay，重发的 Network PDU TTL 会减 1。因此：

- 设备与 Proxy 路径没有 Mesh Relay 时，收到的 TTL 通常等于设备发送 ACK 时的初始 TTL。
- ACK 经过一个或多个 Relay 时，App 收到的 TTL 会小于设备初始 TTL。
- 所以 `ACK Rx TTL 25` 可以证明 App 收到的 ACK Network PDU TTL 为 25；只有在确认未经过 Relay 时，才能进一步等同于设备 ACK 的初始 TTL / Default TTL。
- 如果收到 `ACK Rx TTL 24`，不能立即判定设备错误；可能是设备以 25 发出并经过了一次 Relay。

该语义需要在测试记录中明确，避免把“接收 TTL”和“设备配置的 Default TTL”混为一谈。

### 4. 当前 App 发送链路确实会使用 Lab TTL 25

当前源码链路为：

1. `LabSettings.lightGroupControlTTLOverride` 在 override 开启时返回 `25`。
2. `LightGroupControlCommandSender.defaultTTL` 返回同一值。
3. ACK 详情路径把该值传给 `LightAckProgressTracker.send(... defaultTTL:)`。
4. Tracker 继续传给 `MeshAPI.sendMessage(... defaultTTL:)`。
5. `MeshMessageHandle.defaultTTL` 保存该值。
6. `MeshMessageManager` 调用 `MeshNetworkManager.send(... withTtl: messageHandle.defaultTTL)`。
7. Lower Transport 使用 `initialTtl ?? provisionerNode.defaultTTL ?? networkParameters.defaultTtl` 计算 Network PDU TTL。
8. 因为本次 `initialTtl` 明确为 `25`，最终构造 outgoing Network PDU 时使用 `25`，不会落到 node default 或 SDK default。

因此，从当前代码看，已接入 `LightGroupControlCommandSender` 的 Light / Group 控制命令会按 25 下发。

但 UI 的 `App Tx TTL` 不能在 ACK 返回后再次读取 `LabSettings`，否则用户在等待 ACK 期间修改设置会让展示值与本次命令不一致。应在 `send(...)` 入口捕获本次的 `defaultTTL`。

## 推荐实现范围

### 纳入

只扩展现有 `LightAckProgressTracker` 已覆盖的 acknowledged 灯控诊断：

- Lights 列表单灯 on/off。
- Light Detail on/off。
- Light Detail brightness / lightness。
- Light Detail CCT。
- Light Detail vendor identify。

本轮不扩大 `Display light ACK details` 的业务覆盖面。Group 页面当前没有接入 `LightAckProgressTracker`，因此不因本需求新增 Group ACK 弹窗或改变 Group 控制交互。

### 不纳入

- 不修改设备 Default TTL。
- 不发送 `ConfigDefaultTtlSet`。
- 不修改 SDK 全局 `networkParameters.defaultTtl`。
- 不把 Lab TTL 扩展到 Energy、Schedule、Firmware、Gateway、EFC、Sensor、Sync 等其他业务。
- 不改变 ACK timeout、retry、replay protection 或现有 ACK 成功判定。
- 不用原始 BLE 字节扫描或同 source 最近一包的 TTL 猜测 ACK TTL。

## 推荐技术方案

### 一、SDK 增加“消息 + 接收元数据”的兼容性 API

新增一个公开、只读的接收结果类型，语义示例：

- `message: MeshMessage`
- `receivedTTL: UInt8`
- `source: Address`
- `destination: MeshAddress`
- 可选保留 `sequence`、`ivIndex`，便于后续诊断，但本需求 UI 只消费 TTL。

现有仅返回 `MeshMessage` / `StaticMeshResponse` 的 API 保持不变；新增 metadata-aware overload，避免影响 SDK 其他调用方。

接收元数据沿真实解码链路传递：

1. `NetworkPdu.ttl`
2. `AccessMessage`
3. `UpperTransportPdu`
4. `AccessPdu`
5. `AccessLayer.handle(...)`
6. `NetworkManager.notifyAbout(...)`
7. metadata-aware `waitFor(...)`
8. metadata-aware `MeshAPI.sendMessage(...)`
9. `LightAckProgressTracker`

不能只在 Network Layer 发一个全局 TTL Notification，再由 App 按时间或 source 猜测关联关系。一个设备可能同时发送状态 publication 或其他 ACK，这种做法会把无关包的 TTL 错配给当前控制命令。

### 二、分段消息语义必须明确

每个分段都是独立 Network PDU，可能因路径不同而具有不同的接收 TTL。因此 SDK 不应把任意一个 segment 的 TTL 无条件声称为整条 Access Message 的唯一 TTL。

本需求涉及的 `GenericOnOffStatus`、`LightLightnessStatus`、`LightCTLTemperatureStatus` 和当前 identify status 都是短 ACK，预期为 unsegmented Access Message，可提供单一精确 `receivedTTL`。

SDK 公共设计建议二选一：

1. `receivedTTL: UInt8?`：unsegmented 时有值；segmented 且无法定义唯一值时为 `nil`。这是本需求的推荐最小方案。
2. 后续若确有分段诊断需求，再扩展为 `receivedTTLRange` 或 per-segment TTL，不在本轮过度设计。

### 三、App Tx TTL 在发送时固化

`LightAckProgressTracker.send(...)` 已接收 `defaultTTL`。本次只需要：

- 创建 command id 时同步保存本次 `defaultTTL`。
- ACK 返回时使用保存值，不重新读取 `LabSettings`。
- 当前需求场景 override 已开启，因此 `defaultTTL == 25`，它就是 Lower Transport 构造 outgoing Network PDU 时采用的显式 initial TTL。
- 旧 command 的异步回调继续通过 `activeCommandId` 拒绝，避免新旧命令 TTL 串线。

如未来要求在 override 关闭时也展示 App 的“最终有效 TTL”，应由 SDK 额外返回 Lower Transport 已解析的 effective outgoing TTL；不建议 App 自己复制 SDK 的 fallback 规则。本轮不扩展该范围。

### 四、Result 下方展示 TTL 行

现有成功结果顺序：

1. `Result ... OK / Failed`
2. `Response ...`

调整为：

1. `Result ... OK / Failed`
2. `ACK Rx TTL 25 (App Tx TTL 25)`
3. `Response ...`

展示规则：

- 收到并成功解码、匹配本次命令的 ACK，且 `receivedTTL` 与本次 `appTxTTL` 均存在：展示组合行。
- ACK timeout：不展示 `ACK Rx TTL`，避免伪造设备侧数据。
- 普通 send error / cancelled：不展示 `ACK Rx TTL`。
- vendor status 返回业务失败：仍然收到了 ACK，应展示 TTL 行。
- replay protection 拒收：当前 packet 在 Lower Transport 已有 TTL，但没有进入正常 ACK callback。建议同步给 `MeshReplayProtectionDiscardEvent` 增加 `receivedTTL`，匹配当前命令后也展示 TTL 行；这样“设备已回复但被安全层拒收”的诊断仍完整。
- SDK 对分段消息返回 `receivedTTL == nil` 时不展示该行。

建议新增国际化 key：

- English：`ACK Rx TTL %d (App Tx TTL %d)`
- 简体中文：`ACK 接收 TTL %d（App 发送 TTL %d）`

UI 不需要新增控件。`LightAckProgressAlertView.messageLabel` 已支持多行，content view 使用最小高度与下方约束，可由新增文本自然撑高；实现后仍需做小屏视觉检查。

## 预计修改点

### NordicSigMeshSDK

主要涉及：

- `nRFMeshProvision/Layers/Network Layer/NetworkPdu.swift`
  - 已有 TTL 解码，无需改变协议算法。
- `nRFMeshProvision/Layers/Lower Transport Layer/AccessMessage.swift`
  - 保留 unsegmented Network PDU 接收 TTL。
- `nRFMeshProvision/Layers/Lower Transport Layer/SegmentedAccessMessage.swift`
  - 明确 segmented metadata 的可选语义。
- `nRFMeshProvision/Layers/Upper Transport Layer/UpperTransportPdu.swift`
- `nRFMeshProvision/Layers/Access Layer/AccessPdu.swift`
- `nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`
- `nRFMeshProvision/Layers/NetworkManager.swift`
- `nRFMeshProvision/MeshNetworkManager.swift`
- `nRFMeshProvision/MeshNetworkManager+Callbacks.swift`
  - 新增兼容的 metadata-aware wait / callback 链路。
- `MeshLib/MeshAPI.swift`
  - 新增只供需要接收元数据的 acknowledged send overload。
- `MeshLib/Diagnostics/MeshReplayProtectionDiscardEvent.swift`
  - 补充 `receivedTTL`，用于 replay rejected 诊断。

SDK 当前已有与本需求无关的用户改动：

- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateServer.swift`
- `Tests/NordicSigMeshSDKTests/SensorCalibrateMathTests.swift`

实施时必须保留，不覆盖、不格式化这些文件。

### SunSmart App

- `SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift`
  - 使用 metadata-aware ACK API。
  - 固化本次 App Tx TTL。
  - 在 Result 下插入 TTL 行。
  - replay rejected 时消费事件中的 TTL。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增 TTL 行本地化。
- 新增或扩展聚焦的 contract / regression script。

项目当前已把四个品牌 target 的 `NordicSigMeshSDK` 引用统一切换到本地路径，因此修改 SDK 后四个 target 都可能受影响，需要同步构建验证。

## 测试与验收方案

### 1. SDK 自动测试

新增聚焦测试：

- 构造 TTL 为 25 的 unsegmented received Network PDU，解码到 ACK result 后仍得到 `receivedTTL == 25`。
- TTL 为 0、1、25、127 时均不被截断或错误 fallback。
- metadata-aware callback 只匹配 source + destination + response opcode 对应的 ACK。
- 旧 callback API 行为与类型不变。
- segmented Access Message 不返回伪造的唯一 TTL。
- replay discard event 携带被拒收 Network PDU 的 TTL。

### 2. App 聚焦回归

检查：

- `LightAckProgressTracker` 捕获发送时的 App Tx TTL，而不是完成时读取 Lab。
- TTL 行位于 Result 后、Response 前。
- success 与 vendor failed ACK 都展示 TTL。
- timeout / cancelled 不展示伪造的 ACK Rx TTL。
- replay rejected 有 packet TTL 时展示 TTL。
- 第二条命令覆盖第一条命令后，旧 callback 不污染当前弹窗。
- English 与简体中文 key 均存在。

### 3. 构建验证

按工程规则直接运行 iPhoneOS 构建，不使用 shell 包装、不重定向日志、不使用 Simulator：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

同时运行：

- SDK 聚焦 `swift test`。
- `scripts/check_lab_light_group_ttl.sh`。
- `scripts/check_light_ack_replay_diagnostics.sh`。
- 新增的 ACK TTL contract script。
- App 与 SDK 各自的 `git diff --check`。

### 4. 真机 / Mesh 验收矩阵

| 场景 | App Tx TTL | 设备配置 TTL | 预期展示 | 说明 |
| --- | ---: | ---: | --- | --- |
| 直连、双方 25 | 25 | 25 | `ACK Rx TTL 25 (App Tx TTL 25)` | 最直接验收场景 |
| App 改 20，设备保持 25 | 20 | 25 | `ACK Rx TTL 25 (App Tx TTL 20)` | 验证两侧数据独立 |
| App 保持 25，设备改 20 | 25 | 20 | `ACK Rx TTL 20 (App Tx TTL 25)` | 验证设备 ACK TTL |
| 设备 25，ACK 经过一次 Relay | 25 | 25 | 可能为 `ACK Rx TTL 24 (App Tx TTL 25)` | 不能误判为固件未使用 25 |
| ACK timeout | 25 | 任意 | 无 ACK Rx TTL 行 | 无法证明设备已回复 |
| ACK 被 replay protection 拒收 | 25 | 25 | replay result + TTL 行 | TTL 来自被拒收的 Network PDU |

真机验收需要同时保存 SDK network log，核对同一 ACK 的 source、destination、sequence、opcode 与 TTL，证明 UI 行和原始解码数据一致。

## 风险与边界

1. `ACK Rx TTL` 明确表示 App 收到 ACK 时的 Network PDU TTL，避免误解为设备配置的 Default TTL；测试报告仍必须注明 Relay 会递减。
2. 不能把最近一次同 source Network PDU 的 TTL 当作 ACK TTL，必须与当前 ACK 回调绑定。
3. App Tx TTL 25 是本次显式 override 的发送 TTL；override 关闭时的最终 fallback TTL 不在本轮展示范围。
4. SDK 公共回调修改必须采用新增 overload / result wrapper，不能破坏现有大量 `MeshMessage`、`MeshResponse` 调用方。
5. 自动测试与四品牌编译只能证明代码链路和集成正确；最终仍需真机 BLE Proxy / Mesh Relay / 固件 ACK 验收。

## 建议实施顺序

1. 先在 SDK 增加接收 TTL metadata 的无损传递与聚焦测试。
2. 增加 metadata-aware `waitFor` / `MeshAPI` acknowledged send API，保持旧 API 兼容。
3. 给 replay discard event 补接收 TTL。
4. App Tracker 固化 App Tx TTL，并在 Result 下展示组合行。
5. 补 English / 简体中文与 contract checks。
6. 跑 SDK tests、App scripts、App/SDK diff check。
7. 串行构建四个品牌 target。
8. 按真机矩阵做直连与 Relay 验收，并与 SDK network log 对照。

## 已确认的实施语义

- UI 使用最终确认文案 `ACK Rx TTL 25 (App Tx TTL 25)`。
- `ACK Rx TTL` 明确定义为“ACK 到达 App 时的 Network PDU 剩余 TTL”，不是无条件等同于设备 Default TTL。
- 正常 ACK 与 replay rejected packet 都展示 TTL；纯 timeout / cancelled 不展示。
- 本轮只扩展现有 Light ACK details 覆盖的入口，不新增 Group ACK 弹窗。
- override 关闭时，不在本轮推算或展示 App fallback TTL。
