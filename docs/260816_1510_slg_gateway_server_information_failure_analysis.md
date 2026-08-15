# SLG Sync Plus 网关 Server Information / Verify Configuration 失败分析

## 结论

本次失败不是 BLE、Proxy、Mesh Network PDU 或分段重传失败。App 发出的 12 个 Segmented Access Message 全部被地址 `0x000A` 的网关确认，网关随后主动返回了 Vendor Status：

- Response Code：`gatewayMQTTConnectInfoSet`
- 原始参数：`43 02 01`
- `ret`：`0x01`
- SDK 解析：`isSuccessful = false`、`errorCode = 1`

项目内协议文档对 `0x43/0x02` 的定义是“设置 MQTT 服务器参数”，其 `ret=1` 明确定义为“内存不足”。因此直接失败点是：网关固件收到了完整 MQTT 配置，但在处理或保存该配置时拒绝了请求。

SLG Sync Plus 独有、且与该返回高度相关的最可能触发原因，是 App 把品牌级 `customId=0x03` 直接编码到了协议的“MQTT 连接实例号”字段。当前协议只暴露 MQTT 上下文 0 和上下文 1；SDK 自身对该字段也只记录了值 0、1 的品牌语义。由此推断，SLG 的值 3 很可能超出网关固件支持的 MQTT 实例范围，固件尝试访问或分配不存在的实例时返回 `ret=1`。

该触发原因属于高可信推断，但仅凭当前一份 Log 还不能把它提升为固件侧已证实结论。`ret=1` 的直接含义已证实；“实例号 3 不受支持”应通过对照下发确认。

## Log 解码

请求 Access PDU：

- Vendor opcode：`0xF0780A`
- 功能：`0x43/0x02`，设置网关 MQTT Server Information
- 连接实例号：`0x03`
- Server 地址长度：`0x28`，即 40 字节
- Username 长度：`0x1E`，即 30 字节
- Password 长度：`0x20`，即 32 字节
- Client ID 长度：`0x17`，即 23 字节
- Keepalive：`0x003C`，即 60 秒
- Clean Session：`0x01`
- Auth Mode：`0x00`
- SSL Version：`0x04`

各长度字段与 Log 中的实际 UTF-8 字节数量一致，没有看到 App 侧长度前缀错位、尾字段缺失或大小端错误。请求参数共 137 字节，加上 3 字节 Vendor opcode 与 4 字节 TransMIC 后正好形成 12 个 12 字节 Lower Transport 分段。

网关返回 `ackedSegments = 0x00000FFF`，表示 12 个分段全部收到。紧接着的 `0xF3780A / 43 02 01` 是业务失败应答，不是超时或无响应。

## SLG target 的差异来源

`MacroDefinition.swift` 针对不同 target 定义了不同的全局 `customId`：

- SunSmart：`0x00`
- SylSmart：`0x01`
- Archipelago：`0x02`
- SLG Sync Plus：`0x03`

`GatewayServerAuthorizationService` 解析服务器返回的 MQTT host、port、username、password、client ID 后，不使用服务器响应中的 MQTT 实例号，而是把上述 target 全局 `customId` 写入 `MQTTConnectInformation`。

SDK 序列化 `gatewayMQTTConnectInfoSet` 时，又把 `connectInfo.customId` 作为 `0x43/0x02` payload 的第一个字段发送。因此 SLG Log 中出现了 `43 02 03 28 ...`。

这里存在语义混用风险：

- App 将该值视为品牌或 customer ID；
- 协议文档将同一字节定义为“连接实例号”；
- MQTT 状态查询只返回上下文 0、上下文 1；
- SDK 注释也只列出 `0` 和 `1`。

这解释了为什么问题集中出现在 SLG target，而 Mesh 传输与普通 Config 消息仍然正常。

## Verify Configuration 为什么连带失败

Verify Configuration 不是独立向网关发送一条“验证 MQTT 配置”的 Mesh 命令。当前实现中：

1. Server Information 发送 `gatewayMQTTConnectInfoSet`。
2. SDK 只有在 Vendor Status 成功时，才把目标 MQTT 配置写入 `node.gatewayInfo.mqttConnectInfo`。
3. 本次 Status 为失败，所以消息 handle 被标记失败，本地节点状态也不会更新为目标配置。
4. Verify Configuration 通过本地状态比较目标 `gateway.mqttServerInfo` 与当前 `node.gatewayInfo.mqttConnectInfo`，或检查 `getNodeSyncGatewayData(gateway:)` 是否为空。
5. Server Information 未收敛时，验证条件必然不成立；在 Gateway Recovery 任务图中，Verify Configuration 还依赖所有前置步骤，前置失败后会被跳过并最终显示失败。

因此 Verify Configuration 是 Server Information 失败后的结果，不是第二个独立根因。

## 第二段 ConfigDefaultTtlGet Log 的含义

第二次点击后发出的 `ConfigDefaultTtlGet` 使用网关 Device Key，并成功返回 `ConfigDefaultTtlStatus(ttl: 7)`。这证明当时：

- 网关地址 `0x000A` 可达；
- Device Key 解密正常；
- 标准 Config Client/Server 通道正常；
- 默认 TTL 读取成功。

但它不能证明 MQTT Server Information 成功，也不是当前源码中 Verify Configuration 使用的验证命令。Log 顺序是第二次点击后先打印“完成”，之后才出现 `ConfigDefaultTtlGet`；SDK 的 `MeshNodeHeartbeatManager` 会对没有灯模型的节点使用该消息作为在线心跳。因此这条消息更符合独立后台心跳，而不是 Verify Configuration 发出的验证请求。

第二次点击本身没有新的 Server Information 或验证消息，符合当前实现：Verify Configuration 的 `messageHandles` 为空，只执行本地状态/差异判定；由于 Server Information 已失败且前置依赖未成功，该步骤不会重新读取 MQTT 配置并会继续失败或被标记为 Skipped。

Log 中的 TCP `RST` 出现在第一轮同步完成以后，也没有与 `0x43/0x02` Vendor Status 建立调用关系，不应作为本次 Mesh Server Information 失败原因。

## 建议的最小确认实验

1. 在同一台网关、同一固件、相同 MQTT 字段下，只把连接实例号从 `3` 改为固件已支持的 `0` 或 `1`，观察 `43 02 ret`。
2. 如果改为 `0/1` 后返回 `ret=0`，即可确认根因是品牌 custom ID 与协议连接实例号混用。
3. 如果仍返回 `ret=1`，再按单变量方式缩短 Server、Username、Password、Client ID，定位固件实际的单字段或总长度内存上限；当前完整 Access PDU 较长，但编码本身是自洽的。
4. 同时记录网关 PID、主固件版本和通信模组版本，确认 SLG 交付固件是否声明支持额外 MQTT 实例。

在固件协议负责人确认前，不建议直接把 SLG 的全局品牌 `customId` 改成 0 或 1，因为该全局值还可能被其他服务身份、固件查询或品牌路由使用。更合理的修复边界是把“品牌 customer ID”和“网关 MQTT connection instance”拆成两个独立概念，再按固件契约选择实例号。

## 证据范围

本结论基于用户提供的真机 Log、当前 worktree App 源码、本地 NordicSigMeshSDK 源码以及项目内 Vendor 协议文档的静态交叉分析。本轮没有修改业务代码，没有执行构建，也没有进行真机对照下发；因此尚未验证实例号 0/1 的实际设备结果。
