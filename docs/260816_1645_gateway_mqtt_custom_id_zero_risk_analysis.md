# Gateway MQTT `customId` 全部改为 0 的风险分析

## 结论

如果真机已经证明相同 Gateway 固件只接受 MQTT 连接实例 `0`，让四个品牌的 Gateway MQTT 配置统一使用实例 `0` 是合理方向，代码影响面也比较集中。

但不建议只把 `MacroDefinition.swift` 中四个 target 的全局 `customId` 全部改为 `0` 后直接发布。主要风险不在编译，而在存量数据和设备侧实例迁移：已有本地记录仍可能保存 `1/2/3`，Gateway 固件也可能保留旧实例，而当前普通同步差异判断不会因为 `customId` 改变而自动重发 MQTT 配置。

建议把它作为一次明确的“MQTT 连接实例归一化到 0”迁移，而不是简单修改品牌常量。

## 已确认的代码影响范围

当前 App 全局 `customId` 的实际业务调用点是：

- Gateway Register 响应构造 `MQTTConnectInformation`；
- cloud import 重建 `MQTTConnectInformation`；
- Gateway 页面遗留授权构造路径。

这些调用最终都服务于 Gateway MQTT `0x43/0x02`。Firmware API 和 Firmware 数据库中同名的 `customId/customerId` 使用独立参数或局部变量，不会因为修改 `MacroDefinition.swift` 的全局值而一起改变。

因此，从当前 App 静态源码看，将这个全局值统一为 `0` 不会直接改变：

- Gateway Register HTTP 请求参数；
- 服务器返回的 MQTT host、username、password、client ID；
- target 的 app key/app secret；
- Firmware 查询、下载和缓存 customer ID；
- BLE、Mesh Proxy、Wi-Fi credentials、APN 或 OTA 协议。

## 主要风险

### 1. 只改常量不会迁移已有本地记录

`MQTTConnectInformation` 会整体 JSON 编码到 Gateway 本地数据库。已经授权过的 SylSmart、Archipelago、SLG Gateway 记录可能仍保存 `1/2/3`。

共享授权服务默认在本地 MQTT 信息有效时直接复用，不会重新按新常量构造。因此升级 App 后：

- 新增或重新导入的 Gateway 使用 `0`；
- 已有 Gateway 仍可能使用旧值；
- 同一品牌、同一 App 版本中可能同时存在新旧两种实例值。

### 2. 普通同步差异判断忽略 `customId`

`getNodeSyncGatewayData` 只比较 server address、client ID、username 和 password，没有比较 `customId`。

即使把本地记录迁移成 `0`，如果其他 MQTT 字段相同，普通“是否需要同步”判断仍可能认为没有变化，不会自动生成 `0x43/0x02` 下发任务。

恢复任务的完整 MQTT equality/verification 会比较 `customId`，但不能依赖所有用户都主动进入恢复流程。迁移必须显式强制一次 Server Information 下发，或把 `customId` 纳入同步差异判断。

### 3. Gateway 设备侧可能保留旧实例

项目协议提供按“连接实例号”设置 MQTT 参数和 SSL PEM，但没有看到删除/清空某个 MQTT 实例的命令。

从 `1/2/3` 改向 `0` 时，设备侧可能出现：

- 实例 `0` 写入新配置；
- 原实例 `1/2/3` 仍保留旧配置；
- 固件如果允许多个实例运行，可能产生重复 MQTT 连接、重复上报、同一 client ID 互踢或旧实例继续连接；
- 如果实例和证书绑定，原实例证书与新实例不匹配。

当前 App 下发 MQTT 信息使用 `authMode=none`，没有看到 App 侧 PEM 写入调用，因此证书风险对当前主路径较低；但仍需确认品牌固件是否预置证书或其他系统是否配置过旧实例。

### 4. SDK 历史上的品牌语义可能仍存在于固件

SDK 最初把该字节命名为 `platformType`，并注明 `0=SunSmart`、`1=新加坡`。虽然当前 Vendor 协议将它定义为“连接实例号”，但没有 Gateway 固件源码证明固件完全不按品牌分支。

如果固件仍用该字节选择 topic 格式、根证书、预置域名、数据结构或品牌处理逻辑，全部改为 `0` 可能让 SylSmart、Archipelago、SLG 被当作 SunSmart 处理。

由于 MQTT server address、credentials 和 client ID 都由服务器完整下发，这种风险未必实际存在；但必须通过固件负责人或跨品牌真机验证排除。

### 5. 回滚不是只改回常量

一旦实例 `0` 已写入 Gateway，代码回滚到 `1/2/3` 不会自动清理实例 `0`。如果要回滚，需要同时考虑本地记录、设备旧实例、Broker 会话和强制重下发，否则可能继续存在混合配置。

## 风险等级

| 风险项 | 等级 | 原因 |
| --- | --- | --- |
| App 代码调用面 | 低 | 全局值实际集中在 Gateway MQTT 构造 |
| 新 Gateway 使用实例 0 | 低到中 | 用户已有真机现象支持 0，但尚未形成四品牌完整证据 |
| 存量 Gateway 自动迁移 | 高 | 当前不会因常量变化自动重构、重发 |
| 设备侧旧实例残留 | 中到高 | 协议未看到删除实例能力，固件行为未知 |
| 品牌/平台语义丢失 | 中 | SDK 历史注释存在该语义，缺少固件源码确认 |
| 回滚复杂度 | 中 | App、本地数据库、Gateway 实例和 Broker 会话需要一起考虑 |

## 推荐实施边界

如果决定统一为 `0`，推荐方案是：

1. 不再把品牌 `customId` 直接当作协议实例号；新增含义明确的 Gateway MQTT connection instance，当前固定为 `0`。
2. 保留品牌 customer ID 概念，避免将来 Firmware、服务器或其他品牌路由需要时又复用实例字段。
3. 加入存量 `MQTTConnectInformation.customId != 0` 的本地迁移，更新后保存 Gateway 记录。
4. 将 MQTT instance 以及其他协议字段纳入同步差异判断，或为迁移 Gateway 显式安排一次强制 `0x43/0x02` 下发。
5. 以 Vendor Status `ret=0` 为下发成功证据，并在 App 状态模型中确认目标信息已经收敛。
6. 与固件确认旧实例是否自动停用/覆盖；若不会，补充清理或设备重置策略。
7. 分品牌、小批量发布并保留迁移版本标记，避免每次启动都重复强制下发。

## 最小真机验收矩阵

四个 target 至少分别验证：

- 新增 Gateway：发送 `43 02 00 ...` 并收到 `43 02 00`；
- 已授权旧 Gateway：从旧实例迁移到 `0`，确认实际发生一次下发；
- Gateway 重启和 App 重启后配置仍有效；
- Gateway MQTT/Internet 在线状态恢复；
- 状态/事件上报和服务器远程消息正常；
- 同一 client ID 不发生周期性踢线或重复连接；
- cloud import、Repair、Recovery、手动 Authorize 都保持实例 `0`；
- App 回滚或迁移失败时有明确恢复路径。

## 证据范围

本分析基于当前 App、NordicSigMeshSDK 和 Vendor 协议的静态源码以及用户反馈“只有实例 0 能正常工作”。本轮没有修改业务代码、没有构建，也没有独立完成四品牌 Gateway、Broker 或服务器端验证。
