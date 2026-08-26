# Lab 全局 Mesh 命令 TTL 现状分析与开发方案

## 结论

当前 `Override Light/Group Control TTL` 并非只影响 on/off，但也没有覆盖所有命令。

- 已覆盖：部分 Light / Group 页面发出的 on/off、brightness / lightness、CCT、All Lights 以及单灯 Identify 命令。
- 未覆盖：All Lights CCT / AUTO、Group AUTO / TEST、Up/Down Ratio、设备重启、LED Inversion，以及其他页面中的 Mesh 查询、配置、同步、添加、OTA 等命令。
- `Display light ACK details` 与 TTL 覆盖是两个独立设置。它只决定部分单灯 ACK 命令是否显示诊断详情，不决定 TTL 覆盖是否生效。

因此，若新需求是“开关打开后，App 发出的所有 Mesh 命令统一使用配置值作为 Network PDU TTL”，现有 `Light/Group Control TTL` 描述和页面级发送器设计都不再准确，需要一起调整。

## 当前实现证据

### 设置与 TTL 注入方式

- `LabSettings.lightGroupControlTTLOverride` 在开关关闭时返回 `nil`，打开时返回用户配置的 `0...127`。
- `LightGroupControlCommandSender` 只在它封装的命令上向 `MeshAPI.sendMessage` 传入 `defaultTTL`。
- SDK 最终 TTL fallback 顺序仍是：调用方 `initialTtl`、本地 Provisioner Node 的 `defaultTTL`、`networkParameters.defaultTtl`。

这意味着当前方案是“指定调用点覆盖”，不是全局覆盖。

### 当前覆盖矩阵

| 入口 / 命令 | 当前是否使用 Lab TTL | 说明 |
| --- | --- | --- |
| Lights 列表单灯 on/off | 是 | ACK 详情打开、关闭两条路径均传入 Lab TTL |
| Light 详情 on/off | 是 | ACK 命令 |
| Light 详情 brightness | 是 | 拖动中 unack、结束时 ACK 均覆盖 |
| Light 详情 CCT | 是 | 拖动中 unack、结束时 ACK 均覆盖 |
| Light 详情 Identify | 是 | Health Attention 和 Vendor Identify 均覆盖 |
| All Lights on/off | 是 | 广播控制 |
| All Lights brightness | 是 | 广播控制 |
| All Lights CCT | 否 | 仍直接调用 `MeshAPI.sendMessage` |
| All Lights AUTO | 否 | 仍直接调用 `MeshAPI.sendMessage` |
| Group 列表 / 详情 on/off | 是 | 通过专用发送器 |
| Group brightness / CCT | 是 | 通过专用发送器 |
| Group member 单灯 on/off | 是 | 通过专用发送器 |
| Group AUTO / TEST / Group Test | 否 | 仍直接调用 `MeshAPI.sendMessage` |
| Light Up/Down Ratio Get / Set | 否 | 仍直接调用 `MeshAPI.sendMessage` |
| Light 重启、LED Inversion 等 | 否 | 仍直接调用 `MeshAPI.sendMessage` |
| 其他业务模块的 Mesh 命令 | 否 | 不经过 `LightGroupControlCommandSender` |

### ACK 详情开关的真实作用域

`Display light ACK details` 当前只用于以下单灯 ACK 诊断：

- Lights 列表单灯 on/off；
- Light 详情 on/off；
- Light 详情 brightness；
- Light 详情 CCT；
- Light 详情 Vendor Identify。

它不负责 Group 命令，也不是 TTL override 的总开关。即使关闭 ACK 详情，只要打开 TTL override，当前已纳入专用发送器的命令仍会使用 Lab TTL。

## 新需求的建议定义

建议把“所有命令”定义为：

> App 作为本地 Provisioner 主动下发的所有 Mesh Access 与 Configuration 消息，其 Network PDU TTL 都优先使用 Lab 配置值。

打开覆盖后，TTL 优先级调整为：

1. Lab 全局 Outgoing Mesh TTL；
2. 调用方显式 `initialTtl`；
3. 本地 Provisioner Node `defaultTTL`；
4. SDK `networkParameters.defaultTtl`。

关闭覆盖后，完全恢复现有 2 到 4 的顺序，不改变历史行为。

### 纳入范围

- SIG 与 Vendor Access Message；
- Get、Set 及其他由 App 主动构造的 Access 命令；
- acknowledged 与 unacknowledged 命令；
- Configuration Message；
- 单播、组播、虚拟地址和广播目标；
- 分段与非分段 Access Message；
- 通过 `MeshAPI`、`MeshMessageManager` 或 SDK manager 最终进入统一 Access 发送链路的命令；
- 原本调用点显式传入 `TTL = 0` 的 Access 命令。开启全局覆盖后也应以 Lab 值为准，才能满足“所有命令”。

### 不纳入范围

- Provisioning PDU；
- Proxy Configuration PDU；
- SDK 自动生成的 Lower Transport Segment Acknowledgment；
- Mesh 节点中继其他设备消息时的 TTL 递减；
- 设备发给 App 的上行消息；
- Heartbeat 等 Mesh Control Message；
- 消息 payload 内部具有独立协议语义的 TTL 字段，例如 Model Publication TTL、Firmware Update / Distribution TTL、邻近照明参数中的 TTL。

这些数据不属于 App 下发 Access / Configuration 命令的 Network PDU TTL。尤其要避免把“外层 Network PDU TTL”与“payload 内嵌 TTL 参数”混为一谈。

如果产品要求连 Heartbeat Control Message 或 payload 内部 TTL 参数也统一改写，需要另立需求；不建议借此 Lab 开关隐式改变协议业务参数。

## UI 与命名调整

`Light/Group Control TTL` 已不符合全局作用域，建议改为以下英文文案：

- 开关：`Override Outgoing Mesh TTL`
- 数值项：`Outgoing Mesh TTL`
- 输入说明：`Overrides the Network PDU TTL for all outgoing Mesh access and configuration messages. Embedded TTL fields are unchanged.`

对应简体中文：

- 开关：`覆盖下行 Mesh TTL`
- 数值项：`下行 Mesh TTL`
- 输入说明：`覆盖 App 下发的所有 Mesh Access 与 Configuration 消息的 Network PDU TTL；消息载荷内的 TTL 字段不变。`

说明：Lab 页面默认展示英文 UI；简体中文仍需同步维护，以满足项目国际化要求。

### 配置兼容

- 保留现有 UserDefaults 存储 Key：`lab_override_light_group_control_ttl` 与 `lab_light_group_control_ttl`，避免升级后丢失用户已保存的开关和值。
- Swift 属性名、枚举 Row 名和国际化 Key 可改为 `outgoingMeshTTL` 语义。
- 若新增国际化 Key，旧 Key 可暂时保留但不再引用；不需要迁移 UserDefaults 数据。
- 默认值继续为 `5`，允许范围继续为 `0...127`。

## 推荐技术方案

### 1. 在 SDK 统一发送层提供全局覆盖入口

工程当前已经使用本地 `NordicSigMeshSDK`，四个品牌 target 共用该依赖。建议在 SDK 的 `MeshNetworkManager` 暴露一个可选的 outgoing Access message TTL override，由 App 在启动和 Lab 设置变化时同步。

不要通过修改 `networkParameters.defaultTtl` 或 Provisioner Node `defaultTTL` 实现：

- 二者都会被调用方显式 `initialTtl` 抢占，无法满足“所有命令”；
- 修改 Node `defaultTTL` 还可能污染 Mesh 数据与持久化语义；
- `networkParameters.defaultTtl` 是 fallback，不是 Lab 强制覆盖层。

### 2. 在 Lower Transport 的 Access Message 出口应用覆盖

SDK 的 Access Message 最终分为两个统一出口：

- 非分段 Upper Transport PDU；
- 分段 Upper Transport PDU。

在这两个出口计算 effective TTL：全局 override 非空时使用 override，否则沿用当前 `initialTtl ?? provisionerNode.defaultTTL ?? networkParameters.defaultTtl`。

该位置的优点：

- 同时覆盖 App 与 SDK manager 发出的 Application / Configuration 消息；
- 不依赖页面是否使用 `MeshAPI` 或专用 helper；
- ACK、unack、SIG、Vendor、单播、组播、广播使用同一规则；
- 分段消息的所有 segment 及重传保持同一个 TTL；
- 不会误改 Lower Transport ACK、Proxy Configuration 与 Heartbeat 的协议 TTL。

SDK override 必须只保存在运行时，不写入 Mesh JSON / SQLite，也不发送 `ConfigDefaultTtlSet`。

### 3. App 统一同步 Lab 配置

在 App 的 Mesh 初始化完成后执行一次配置同步，并在以下事件即时同步：

- `Override Outgoing Mesh TTL` 开关变化；
- `Outgoing Mesh TTL` 数值保存；
- App 冷启动后恢复 UserDefaults；
- Mesh network 被重新加载或 SDK 内部 NetworkManager 被重建。

建议让 SDK 的公开 override 存在于稳定的 `MeshNetworkManager` 实例，并确保内部 `NetworkManager` 重建后仍能读取同一值，避免切换 Site / Space 后静默失效。

### 4. 收敛现有 Light / Group 专用 TTL 逻辑

全局覆盖生效后，`LightGroupControlCommandSender` 不应再承担 TTL 注入职责，否则会形成两套优先级来源。

建议：

- 保留其灯控命令构造能力，作为现有页面的轻量 helper；
- 移除 helper 内部对 `LabSettings.lightGroupControlTTLOverride` 的读取和逐条 `defaultTTL` 注入；
- ACK 详情若仍需显示 App Tx TTL，可直接读取新的 `LabSettings.outgoingMeshTTLOverride` 作为诊断上下文，但真正发送 TTL 由 SDK 全局层决定；
- 更新或替换 `scripts/check_lab_light_group_ttl.sh`，不再断言 override 只能出现在 Light / Group 文件中，改为验证 App 设置与 SDK 全局出口的契约。

这样既避免大范围回退页面调用，也能保证 TTL 只有一个权威执行点。

## 特殊风险

### 显式 TTL = 0 的流程会改变

SDK 中 Fast Add、`MeshNodeHeartbeatManager` 的 Vendor 状态查询、部分 Firmware / BLOB 流程存在显式 `TTL = 0`。其中：

- `MeshNodeHeartbeatManager` 当前发送的是 `SunricherReportStart` Access Message，不是 Mesh Heartbeat Control Message，因此会被 Lab 值覆盖；
- Fast Add 与 Firmware / BLOB 中属于 Access Message 的下行包，在 override 打开后同样会被 Lab 值覆盖；
- 真正的 Mesh Heartbeat Control Message 属于本方案排除项，不应被改写。

这符合“所有 Access / Configuration 命令”的字面要求，但可能改变原本要求单跳或特定拓扑的诊断行为。因此 Lab 输入说明需要明确其全局影响，实际设备验证必须覆盖这些流程。

### TTL 过低会导致功能性失败

- `TTL = 0` 只能到达当前直连 Proxy 可转发到的目标，不能经过 Relay；
- Group / Broadcast、设备添加后的配置、同步和 OTA 对拓扑更敏感；
- 此类失败是 Lab 强制 TTL 的预期网络结果，不应被误判为 App 业务回归。

### TTL 过高会扩大消息传播

Lab 最大允许 `127` 符合 Mesh Network TTL 范围，但可能增加网络负载。建议保留范围，不额外限制实验能力，同时在说明中强调这是全局诊断开关。

## 实施步骤

1. 在 SDK 定义公开、运行时的 Outgoing Access / Configuration TTL override，并补充 `0...127` 校验。
2. 在非分段和分段 Access Message 的 Lower Transport 出口应用统一优先级；保持 Control / Proxy / Provisioning 路径不变。
3. 为 SDK 增加 override 开启、关闭、显式 TTL、fallback、分段消息和排除路径测试。
4. 在 App 中将 Lab 配置语义从 Light / Group 改为 Outgoing Mesh，保留 UserDefaults 旧存储 Key。
5. 在 App Mesh 初始化、开关变化和数值保存时同步 SDK override，并覆盖 NetworkManager 重建场景。
6. 移除 `LightGroupControlCommandSender` 的逐命令 TTL 注入；保留灯控消息构造职责。
7. 保持 `Display light ACK details` 的既有作用域；只更新其诊断 TTL 来源，不扩展成全局 ACK UI。
8. 同步 English、简体中文文案，并检查四品牌 target 的资源与源码成员关系。
9. 更新 TTL contract 脚本和相关文档，明确本方案取代原“仅 Light / Group”作用域。
10. 完成 SDK、App 构建和真实 Mesh 拓扑验证。

## 验证方案

### 自动化与静态契约

- SDK override 关闭时，原显式 TTL 与 fallback 顺序不变；
- SDK override 打开时，调用方传 `nil`、`0`、其他显式值均以 Lab override 为准；
- 非分段和分段 Access Message 都使用 override；
- Segment ACK、Heartbeat、Proxy Configuration 不使用 override；
- override 只接受 `0...127`；
- UserDefaults 旧 Key 可恢复旧版本保存值；
- App 冷启动、切换 Site / Space、重建内部 NetworkManager 后 override 仍有效；
- `git diff --check` 通过。

### 四品牌构建

按项目要求直接、串行运行 generic iPhoneOS build：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建只能证明编译与 target 集成，不代表真实 Mesh TTL 已验收。

### 真机 / Mesh 验收矩阵

1. override 关闭：抽查 Light、Group、配置、同步、添加、OTA，行为与当前版本一致。
2. override 打开且 TTL = 0：在直连 Proxy 下验证 Network PDU TTL 为 0，并确认需要 Relay 的目标按预期不可达。
3. override 打开且 TTL = 2 或 5：跨一跳 / 多跳验证单播、Group、Broadcast。
4. 覆盖 ACK 与 unack、SIG 与 Vendor、Get 与 Set、Application 与 Configuration。
5. 覆盖短消息与触发分段的长消息，确认每个 segment 和重传 TTL 一致。
6. 专门验证 Fast Add、设备配置、同步、Firmware / BLOB / OTA，确认全局 TTL 对原显式 TTL 流程的影响符合需求。
7. 验证 Heartbeat、Proxy Configuration、Provisioning 和 Segment ACK 未被改写。
8. 打开 `Display light ACK details`，确认显示的 App Tx TTL 与抓包 / SDK 发送日志一致；关闭时发送 TTL 不受影响。
9. 在 Lab 页面检查 English 与简体中文布局、数值输入、开关即时生效和重启恢复；四品牌都需实际布局检查。

## 完成边界

- SDK 单元测试、contract 脚本和四品牌构建通过，只能证明代码与集成契约。
- 只有在真实 Proxy / Relay Mesh 中通过代表性抓包或可信 SDK Network PDU 日志确认 TTL，才能宣称全局 TTL 行为验收完成。
- Fast Add、同步、OTA 等高风险流程仍需分别完成真实设备验收，不能由普通灯控成功代替。
