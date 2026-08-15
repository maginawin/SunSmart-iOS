# Gateway MQTT `customId` 语义、业务影响与历史分析

## 结论

Gateway MQTT 配置中的 `customId` 不是 MQTT Broker 的 `clientId`，也不是 Gateway Register HTTP 接口返回的字段。

当前 App 在收到服务器下发的 MQTT host、port、username、password、`mqttClientId` 后，按编译 target 注入一个 `UInt8` 品牌值：

| Target | `customId` |
| --- | ---: |
| SunSmart（默认分支） | `0x00` |
| SylSmart | `0x01` |
| Archipelago | `0x02` |
| SLG Sync Plus | `0x03` |

这个值在 App/SDK 中被命名为 customer ID，SDK 历史上还曾命名为 `platformType`；但当前项目 Vendor 协议把 `0x43/0x02` payload 的同一字节定义为“连接实例号”。因此最准确的描述是：

> `customId` 是 App 根据品牌 target 生成、最终占用 Gateway MQTT“连接实例号”协议字段的一个品牌字节。

这里存在明确的命名/语义冲突。源码只能证明 App 如何构造和发送该字节，不能单独证明 Gateway 固件是否支持 `0x02`、`0x03`，或固件内部是否还赋予它品牌路由语义。

## 数据链路

1. App 调用 Gateway Register HTTP 接口。
2. 服务器响应提供 `mqttUsername`、`mqttPassword`、`mqttClientId`、host 和 port，不提供 `customId`。
3. `GatewayServerAuthorizationService` 使用当前 target 的全局 `customId` 构造 `MQTTConnectInformation`。
4. App 把完整 MQTT 信息编码后保存到本地 Gateway 数据库。
5. Gateway 授权、恢复、修复或同步流程通过 SDK 发送 Vendor `0x43/0x02`。
6. SDK 把 `customId` 放在 `0x43/0x02` payload 的首字段；协议文档称该字段为“连接实例号”。
7. Gateway 成功接受配置后，才可能使用对应 MQTT 上下文连接 Broker。

## 直接影响的功能

### 1. Gateway Server Information 配置

`customId` 是写入 Gateway MQTT 配置消息的实际 wire 字段。值不受固件支持时，可能导致 `0x43/0x02` 被拒绝；值被接受但语义错误时，可能写入错误的 MQTT 连接实例。

### 2. Gateway 授权、恢复、修复与重新同步

2026-07-10 后，共享 `GatewayServerAuthorizationService` 被 Gateway 页面授权、Fast Add、Cloud Sync、Repair/Recovery 等路径复用。这些路径获得 MQTT credentials 后都使用相同 target `customId`，随后在需要时同步 Server Information 到 Gateway。

### 3. 本地持久化和模型比较

`customId` 随 `MQTTConnectInformation` 一起 JSON 编码到本地数据库，并参与 SDK MQTT 信息相等判断和 `GatewayModel` 整体相等判断。

但是当前 `getNodeSyncGatewayData` 判定是否需要重发 MQTT 配置时，只比较 server address、client ID、username 和 password，没有比较 `customId`、keepalive、clean session、auth mode 或 SSL version。因此：

- 改变全局 `customId` 不会自动让已有 Gateway 产生 Server Information 重同步任务；
- 只有重新授权、目标/设备 MQTT 信息其他比较字段不同，或走明确恢复路径时，新的值才会再次下发；
- 本地数据库已有 MQTT 记录会保留创建时编码进去的值，除非记录被重新构造或覆盖。

### 4. Cloud 导入/导出

Gateway cloud export 的 `mqttConnectInfo` 没有导出 `customId`。Cloud import 时 App 根据当前 target 重新注入全局 `customId`。因此它不是一个由服务器保存并回传的稳定 Gateway 属性，而是 App 侧按品牌重新派生的值。

## 间接业务影响

如果 `customId` 导致 Gateway MQTT 配置失败或配置了错误实例，所有依赖 Gateway MQTT 上下行的业务都可能间接受影响，例如 Gateway 云端在线状态、设备/事件上报、服务器到 Gateway 的远程消息或控制。

这些属于协议链路上的合理影响范围，不代表仅凭 App 源码已经逐项证明每个业务都由该字段路由。实际影响需结合 Gateway 固件实现、Broker topic/认证规则和服务器日志确认。

以下功能没有发现由这个 Gateway MQTT `customId` 直接控制：

- 手机到 Gateway 的 BLE/GATT 或 Mesh Proxy 建链；
- 本地 Mesh 控制与标准 Config 消息；
- Wi-Fi SSID/password 配置；
- SIM APN 配置；
- WiFi Gateway OTA；
- Firmware API/数据库中同名的 `customId`/`customerId`。Firmware 业务使用的是另一组模型和请求参数，不是本字段。

## 历史时间线

| 日期 | 仓库/提交 | 变化 | 语义是否变化 |
| --- | --- | --- | --- |
| 2025-05-22 11:36 | NordicSigMeshSDK `451f9c177f` | 首次加入 Gateway MQTT Set API，首字段名为 `platformType`，注释为 `0=SunSmart`、`1=新加坡`；初始序列化尚未完成 | 首次出现平台/品牌语义 |
| 2025-05-22 15:15 | NordicSigMeshSDK `837cd5d8ac` | 完成 Gateway MQTT 自定义配置编码，`platformType` 成为 payload 首字节 | 首次真正进入 wire payload |
| 2025-07-28 09:38 | App `3c48ad96bd` | 在 `MacroDefinition.swift` 增加 target 全局 `customId`：默认 `0`、SylSmart `1`、Archipelago `2` | App 首次定义当前品牌映射 |
| 2025-08-01 16:27 | NordicSigMeshSDK `bf6df4524a` | 增加 `GatewayInformation.MQTTConnectInformation`，把原 `platformType` 包装/改名为 `customId`，序列化位置不变 | 名称变化，wire 位置不变 |
| 2025-08-08 16:22 | App `14e3102298` | App 1.0.8 加入 Space Gateway 配置、Gateway Register、MQTT 本地保存、cloud import 和 `0x43/0x02` 下发，正式使用全局 `customId` | Gateway MQTT `customId` 正式进入 App 业务 |
| 2025-08-15 11:22 | App `f99ae43ee1` | MQTT server address 增加 `tcp://` 前缀 | `customId` 未变化 |
| 2025-11-24 16:22 | App `1395f8b8c0` | 新增 SLG Sync Plus target，并增加 `customId=0x03` | 最近一次品牌值集合变化 |
| 2025-12-04 10:51 | App `5145f76b47` | Gateway 数据迁移到 Site 级流程，扩展 cloud import/注册路径，继续按 target 注入相同值 | 路径变化，值和 wire 语义未变 |
| 2026-02-08 22:14 | App `1d12f182df` | Gateway import 解析收敛到共享入口，Gateway 页面模型切换，仍注入相同值 | 结构重构，值和 wire 语义未变 |
| 2026-04-11 09:32 | App `55db3429af` | 项目加入 Vendor 协议文档，明确 `0x43/0x02` 首字段为“连接实例号” | 暴露出与 App/SDK 命名的语义差异 |
| 2026-07-10 12:10 | App `1eee31cd63` | 新增共享 Server Authorization/Recovery 服务，多入口统一复用 MQTT 构造和同步；继续使用全局 `customId` | 影响入口扩大，值和 wire 语义未变 |

截至当前 App HEAD `7cb9edd58e`（2026-08-16 15:54，`feat: timezone improve`），当前分支没有发现 2025-11-24 之后再次修改四个 target 的 `customId` 值。

## 风险判断

当前实现把“品牌 customer/platform ID”和协议“MQTT 连接实例号”视为同一个字节。对 `0`、`1`，SDK 历史注释与既有品牌映射能够对应；对 Archipelago `2`、SLG `3`，当前 App/SDK 没有看到固件能力协商或合法范围校验。

因此：

- `2`、`3` 是否为合法 Gateway MQTT 实例，需要固件协议负责人或真机对照下发确认；
- 不应仅为了修复某个 target，直接修改全局 `customId`，因为它会改变新授权/新导入记录的品牌值，同时已有记录又不会自动重同步；
- 更稳妥的长期设计是拆分 `brandCustomerId` 与 `mqttConnectionInstanceId`，并让后者来自明确固件契约或能力表。

## 证据范围

本分析基于当前 `time-zone-test` App 源码、当前本地 NordicSigMeshSDK 相关源文件、App/SDK Git 历史和项目 Vendor 协议文档的静态核对。

本轮没有修改业务代码、没有执行构建、没有进行 Gateway 真机下发、没有查询服务器或 Broker 日志。协议字段的 wire 位置和 App 历史已由源码/Git 证实；Gateway 固件对实例 `2`、`3` 的支持及全部 MQTT 下游业务影响仍需真机/固件/服务器证据确认。
