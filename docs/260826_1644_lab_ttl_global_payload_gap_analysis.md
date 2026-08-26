# Lab TTL 全局覆盖与设备配置 Payload 缺口分析

## 用户确认的预期

Lab 中启用 TTL Override 后：

- App 发出的 Mesh Access / Configuration Message 的 Network PDU TTL 使用 Lab TTL；
- 任何命令 payload 中用于配置设备后续发包行为的 TTL 字段，也使用 Lab TTL；
- Lab 关闭时保持各功能原有默认值和协议语义。

## 结论

当前实现只完整覆盖了第一类。第二类没有统一覆盖，因此 Kinetic Switch、Battery/AC Power Switch、EFC Controller 等设备在完成配置后，仍可能使用 `5`、`0xFF` 或 `0`，而不是 Lab TTL。

SDK 对现状已有明确说明：`outgoingAccessMessageTtlOverride` 只影响 Network PDU TTL，不修改嵌入消息 payload 的 TTL。来源：

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/MeshNetworkManager.swift:38-42`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/OutgoingAccessMessageTtlPolicy.swift:10-17`

## 已覆盖部分：App 自己发包的 TTL

`LabSettings.applyOutgoingMeshTTLOverride()` 把 Lab 值写入 `MeshNetworkManager.outgoingAccessMessageTtlOverride`。Lower Transport 在分段与非分段 Access Message 出口都优先选择该值：

`Lab override -> per-message TTL -> Provisioner Default TTL -> Network Default TTL`

所以 Lab 开启后，App 发出的 Kinetic、Power Switch、EFC Vendor/Config 命令本身在 Mesh 网络上传输时，Network PDU 初始 TTL 已使用 Lab 值。

这不代表命令内部告诉设备“以后用什么 TTL”的字段也被修改。

## 未覆盖部分

### 1. Kinetic Switch Proxy Publication TTL

Kinetic Switch 对 Proxy Client Model 配置 Publication 时仍使用：

- `MeshNetworkManager.instance.networkParameters.defaultTtl`
- 当前 SDK 初始化值为 `5`。

来源：

- `MeshEnOceanProxyServer.swift:403-409`
- `MeshLibManager.swift:1376-1381`

因此 Lab TTL 为 `25` 时：

- App 发送 `ConfigModelPublicationVirtualAddressSet` 这条配置包的 Network PDU TTL 是 `25`；
- 但该配置包 payload 内写给 Proxy 的 Publication TTL 仍是 `5`；
- Proxy 后续响应 Kinetic 按键、主动发布控制消息时仍按 Publication TTL `5`。

### 2. Battery / AC Power Switch 按键配置 TTL

Battery 与 AC Power Switch 共用 `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(...)` 和 `BatteryPowerSwitchKeyConfiguration`。

App 构造所有 Key Configuration 时均未显式传入 TTL，因此使用 SDK 默认值：

- `ttl = 0xFF`

该 TTL 被直接编码到 16-byte 按键配置 payload 的 offset 12。

来源：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift:262-279,326-410`
- `NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift:789-852`

另外，当前 `batteryPowerSwitchDesiredConfigHash(...)` 没有包含 TTL。即使把生成值改为 Lab TTL，如果不同 TTL 没有进入 hash，切换或修改 Lab TTL 后也不会可靠地把 Power Switch 标记为需要重新同步。

### 3. EFC Controller Scene Publication TTL

EFC Scene Client Publication 仍使用 `networkParameters.defaultTtl`，当前为 `5`：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift:202-216`

并且当前是否需要重配只比较 Publication Address，不比较 Publication TTL：

- `DeviceEmerFireData+Sync.swift:33-47,196-198`

因此仅修改 Lab TTL 不会让已配置的 EFC Publication 自动进入同步。

### 4. EFC Action Config TTL

EFC 三类状态 Action Config 使用固定值：

- `emergencyActionTTL = 0xFF`

来源：

- `DeviceEmerFireData+Sync.swift:13-18,287-305`

此外，`LinkedEmerFireConfig.actionConfig(...)` 在 action 无效时直接构造 `.invalid`，没有把调用方传入的 TTL 继续写入，因此该分支也会回到 SDK 默认 `0xFF`：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift:284-305`

### 5. Proximity / EFC Association Neighbor TTL

邻近照明 Neighbor Set payload 的 TTL 存在不一致：

- 部分链路使用 `networkParameters.defaultTtl`；
- `Node+MessageHandles`、`SyncDevicesCellModel`、`EmerFireAlarmSyncCellModel` 使用固定 `0`。

SDK 注释说明 `0` 是现有业务默认：邻居不超出广播覆盖范围时使用 `0`，需要跨 Mesh Relay 时才考虑大于 `0`。

根据本次确认的预期，Lab 开启时这些 payload TTL 也应使用 Lab 值；Lab 关闭时应保留各链路当前的 `0` 或默认 TTL 行为，避免改变生产语义。

## 不应混淆的 TTL

### `0xFF` 的语义边界

- 标准 Model Publication：已由 SDK 实现确认，`publish.ttl == 0xFF` 时使用该 Model 所属 Node 的 `defaultTTL`；如果本地节点缓存没有该值，SDK 再回退到 `networkParameters.defaultTtl`。
- Battery / AC Power Switch `0x4C/0x00` Key Configuration：本地产品对接协议明确规定，TTL `0...127` 为显式 TTL，`0xFF` 表示“用默认 TTL”。因此设备真正发送按键控制消息时，`0xFF` 不是 TTL 255，而是让设备解析并使用自身默认 TTL。
- EFC `0x4D/0x07` Action Config：当前本地 SDK/设计资料确认字段支持 `0...127` 和 `0xFF`，并要求默认配置写 `0xFF`，但现有资料没有像 Power Switch 协议一样逐字写明固件 fallback 到哪个 Default TTL。其意图高度一致，但若需要作为固件验收结论，仍应由 EFC 固件协议或实发日志确认。

因此，若 Lab TTL 为 `25` 且目标是让设备后续主动消息明确使用 `25`，payload 应写显式值 `25`，不能继续写 `0xFF`。Lab 的 Lower Transport Override 无法覆盖远端 Node 自己生成的消息。

以下数据不属于“生成命令时应写 Lab TTL”的配置点：

- 接收到的 Network PDU TTL 诊断值；
- `Node.defaultTTL` 本地缓存；
- Status 消息解析出的设备 TTL；
- Lower Transport ACK 内部状态；
- 仅用于函数参数透传、最终仍由全局 Lower Transport Override 覆盖的 per-message TTL。

也不应仅为了满足 Lab Override 就自动向所有远端节点新增 `ConfigDefaultTtlSet (0x800D)`。这是改变远端 Node Default TTL 的独立配置行为，不等同于让现有 TTL-bearing payload 使用 Lab 值。

## 如果按“任何 TTL 都使用 Lab”完整实现

需要采用统一的有效 TTL 解析规则，而不是逐处直接读取 `LabSettings`：

`Lab TTL（开启时） ?? 该功能原有 TTL`

最小实现范围至少包括：

1. SDK 提供统一、线程安全的“payload effective TTL”读取能力，复用现有 `MeshNetworkManager.outgoingAccessMessageTtlOverride`。
2. Kinetic Proxy Publication 使用有效 TTL。
3. Battery/AC Key Configuration 显式写入有效 TTL，并把 TTL 纳入 desired/applied config hash。
4. EFC Publication 与 Action Config 使用有效 TTL；Publication 同步判断同时比较 address 和 TTL；invalid action 分支也传入 TTL。
5. Proximity / EFC Association 的 Neighbor Set 在 Lab 开启时使用 Lab TTL，关闭时保留当前 fallback。
6. 继续审计 SDK 内其他 TTL-bearing payload，包括普通 Model Publication、Heartbeat Publication、Sensor Calibration、Mesh OTA/DFU 的 update/upload/distribution TTL。
7. 增加契约测试，分别验证 Lab 关闭时保持原值、Lab 开启时所有目标 payload 写入 Lab TTL。

## 尚需确认的同步语义

“新生成的命令使用 Lab TTL”与“Lab TTL 改变后自动重配所有已配置设备”是两个不同范围。

当前 Kinetic、Power Switch、EFC 都不会仅因为 Lab TTL 改变而自动完整重配。若预期还包括已配置设备，需要额外设计统一的 TTL 配置版本/失效机制，并决定在哪个 UI 或同步入口提示和执行重新同步，不能只替换构造命令时的 TTL 值。

## 验证边界

本分析基于当前 `fix` worktree 与其实际本地 `NordicSigMeshSDK` 静态源码。未修改业务代码、未构建、未执行真实 Switch/EFC Mesh 同步。
