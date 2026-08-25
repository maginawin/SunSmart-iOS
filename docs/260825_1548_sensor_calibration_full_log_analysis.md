# Calibration 页面 Sensor Cal. 完整 Log 分析

## 分析范围

- App 工作区：`new-calibration`，HEAD `d6a9971d`。
- App 校准入口：`LightSensorCalibrationViewController`。
- 实际运行 SDK：工程当前引用本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- SDK HEAD：`71061e16da09ab7f94b0d5b3ac57ce0aad566864`；`MeshSensorCalibrateManager.swift` 存在本轮开始前已有的未提交诊断日志改动，本次仅只读分析。
- 证据：用户提供的完整 Console Log、当前 App/SDK 源码和现有协议编码实现。
- 本文不复写 Log 中的 Mesh Key、用户 ID、Site/Space ID 等敏感值。

## 总结论

本轮校准在“App 当前状态机和 Mesh 命令链路”层面基本成功：目标传感器、Model/Element 地址、`0x38`/`0x39` 字段顺序和小端编码正确；关键 Vendor 命令、Sensor Publication 切换、三台灯具的目标 Lux/Scene 配置均收到成功响应；最后也出现了只有配置全成功才会触发的 Group Auto 恢复命令，云同步返回成功。

但本轮不能判定为“物理校准质量符合要求”，也不能证明 100 lx 闭环已达标。最重要的问题是 Sensor 模式每个亮度点只固定等待约 3 秒后取一个值，没有做稳定窗口判断。Log 中 100% 的确认采样为 86 lx，但同一 100% 阶段后续仍上升到 89 lx、94 lx，已经直接证明最大点采样过早，`0x38` 的最大增量 61 lx 被低估。目标 100 lx 又没有传入 SDK 做可达性校验；当前日志窗口内最高只看到 94 lx，恢复 Auto 后只看到约 59～72 lx，尚未看到收敛到 100 lx。

因此应分两层判定：

| 判定层次 | 结论 | 依据 |
| --- | --- | --- |
| 页面输入与模式 | 通过 | `mode=sensor`、目标 100 lx、Dim level 50% 均进入正确分支 |
| 地址与协议编码 | 通过 | Vendor 目标 `0x008F`，Ambient Sensor Element `0x0090`，Group `0xC000`；payload 可正确解码 |
| 设备 ACK | 通过 | `0x36`、初始化/最终 `0x39`、`0x37`、`0x38`、Publication、灯具 LC/Scene 配置均有成功响应 |
| 曲线计算内部一致性 | 基本通过 | `41-25=16`，`86-25=61`，与 `0x38` payload 完全一致 |
| 采样稳定性 | 不通过/证据不足 | 100% 读数在确认采样后继续从 86 上升到 89、94 |
| 目标 100 lx 可达性 | 未证明，存在高风险 | SDK 不校验目标；当前 100% 采样和后续最高值均低于 100 |
| 配置后闭环 | 未完成验收 | Auto 已恢复，但日志只看到 Lux 降至 59～72，未看到最终稳定值 |
| 断电持久化与固件实际应用 | 未验证 | ACK 不是 `0x38`/`0x39` 读回，也没有断电重启测试 |

## 地址与设备角色

| 地址 | 角色 | 判定 |
| --- | --- | --- |
| `0x0001` | App 本地 Primary Element | 校准期间 Sensor Publication 临时指向这里，正确 |
| `0x008F` | 选中节点 L2 的 Primary Element / Vendor Model | `0x36`～`0x39` 校准命令目标，正确 |
| `0x0090` | L2 的 Ambient Light Sensor Server Element | `SensorGet` 和 Sensor Publication 来源，正确 |
| `0xC000` | Group 1 | 亮度扫描、最终 Sensor Publication、Auto 开关目标，正确 |
| `0x008E`、`0x0091`、`0x0094` | 三个灯具的 Light LC / Scene Element | 最终写入 100 lx 并保存 Scene，均收到成功状态 |

`ConfigModelPublicationSet` 显示 `address: 143`、`elementAddress: 144` 并不矛盾：Config 消息发给节点 Primary Address `0x008F`，被配置的 Sensor Server 位于 Element `0x0090`。

## 完整流程还原

### 1. 页面入口和 Auto 状态

页面确认输入为：

- Sensor Cal.；
- 目标照度 100 lx；
- Dim level 50%；
- 选中节点 L2，Primary Address `0x008F`。

`dimLevelPercent=50` 不是 SDK 的单点校准亮度。它是 Sensor 页面手动调光/校准完成后的恢复亮度。SDK 校准期间仍会覆盖 Group 亮度并扫描 0%、25%、50%、30%、100%。完成后 Log 中确实发送 `lightness=32767`，即约 50%。

页面进入未完成的 Sensor 草稿时已经暂停 Group Auto，所以本段 Log 开头没有再次出现 Auto OFF 不代表漏发；源码会防止重复发送。

### 2. 直连目标 Sensor

当前 Mesh Proxy 不是 L2，因此 SDK 扫描并连接 SR Dongle/L2 的 GATT Proxy：

- Central powered on；
- 连接、发现 Service/Characteristic；
- Data Out notification enabled；
- GATT Bearer ready。

后续校准 Vendor 命令直接发给 `0x008F`，响应也来自 `0x008F`。这条链路正常。

### 3. 校准初始化

| 步骤 | Payload/消息 | Log 结果 | 判定 |
| --- | --- | --- | --- |
| 清空旧校准 | `31 36 FF FF` | `31 36 00` | 成功 |
| 初始倍率归一 | `31 39 64 00 64 00` | `31 39 00` | 成功；100/100 为 identity |
| 临时上报阈值 | `31 37 01 00` | `31 37 00` | 成功；校准期间 1 lx 上报 |
| 临时 Publication | Sensor Element `0x0090` → `0x0001` | Config Status Success | 成功 |

初始化和最终都发送一次 `0x39 100/100` 是预期行为：第一次清除旧倍率对采样的影响，第二次保存 Sensor Cal. 的 identity 倍率，不是异常重复。

### 4. 环境稳定性检查

SDK 在临时 Publication 成功后监听约 3 秒。当前规则为：

- 收到样本时，`max-min <= 10 lx` 才通过；
- 一个样本都没收到也直接通过。

Log 中 100 lx 的 Sensor Status 出现在 Publication Status 完成前，之后直到开始关灯扫描没有清晰的新稳定窗口样本。因此本轮很可能是以“0 个样本”通过了稳定性检查。这个判断是基于消息顺序和源码的推断，Log 缺少 stability 样本数，不能百分之百确认。

即使本轮环境实际上稳定，“0 个样本也算稳定”仍属于判定缺口。

### 5. 亮度扫描与 Lux 采样

| 设定亮度 | 周边 Publish 变化 | 最终 `SensorGet` | 算法用途 | 判定 |
| ---: | --- | ---: | --- | --- |
| 0% | 93 → 81 → 65 → 50 → 36 → 26 | 25 lx | OFF 基准 | 得到 `offPoint=25` |
| 25% | 19 → 14 → 11 → 15 → 19 → 23 | 25 lx | 粗扫 | 差值 0，不满足 2 lx 阈值 |
| 50% | 26 → 29 → 32 → 37 → 43 → 47 | 50 lx | 粗扫 | 差值 25，进入 25%～50% 精扫 |
| 30% | 52 → 54 → 50 → 46 → 43，随后还有 40 | 41 lx | 精扫 | 首个满足点，`41-25=16` |
| 100% | 39 → 44 → 55 → 65 → 75 → 83 | 86 lx | 最大点 | SDK采用 86；之后仍出现 89、94 |

粗扫/精扫选择 30% 作为最小拐点符合当前算法：25% 不满足，30% 的单次读取相对 OFF 增加 16 lx，超过 2 lx 阈值。

但序列也暴露出明显动态滞后：

- 30% 是从 50% 向下调整，读取时仍处于下降过程，41 后还有 40；
- 100% 是从 30% 向上调整，读取 86 后还继续到 89、94；
- Sensor 模式没有像 Night 模式那样等待连续稳定窗口，只是固定等待约 3 秒并读取一次。

这意味着本轮的曲线参数与“取样瞬间”一致，但不等于与“稳定状态”一致。

### 6. `0x38` 解码

实际 payload：

`31 38 CC 4C 10 00 FF FF 3D 00`

按当前 Apple 小端 UInt16 编码解码：

| 字段 | 数值 | 计算来源 |
| --- | ---: | --- |
| Main/Sub code | `0x31 / 0x38` | Daylight Sensor / Inflection Point |
| `minLightness` | `0x4CCC = 19660`，约 30% | 精扫结果 |
| `minLux` | `0x0010 = 16` | `41 - 25` |
| `maxLightness` | `0xFFFF = 65535`，100% | 固定最大点 |
| `maxLux` | `0x003D = 61` | `86 - 25` |

字段顺序、大小端、差值计算和目标地址全部正确，设备返回 `31 38 00` 成功 ACK。

主要问题不是编码，而是 `maxLux=61` 建立在未稳定的 86 lx 上。若以后续已观察到的 94 lx 作为最低候选稳定值，最大增量至少应为 `94-25=69 lx`，当前值至少低估 8 lx，约 12%。94 之后是否还会继续上升，Log 也没有证明。

### 7. 最终 `0x39` 与本地校准数据

实际 payload：

`31 39 64 00 64 00`

即：

- `sensorRate=100`；
- `ambientLightRate=100`。

这符合 Sensor Cal. 的设计：直接使用传感器自身 Lux 坐标，不做外部工作面照度倍率映射。设备返回成功 ACK，App/SDK 随后把 30%/16 lx、100%/61 lx 和 100/100 倍率保存为本地 `sensorCalibrationData`。

### 8. 恢复上报阈值和 Publication

- `daylightPublishDelta(5)` 返回成功 ACK；
- SDK 关闭直连 GATT，`Cancelling connection` / `XPC connection invalid` 与主动关闭连接的时点一致，不是本次校准失败；
- App 把 `0x0090` 的 Sensor Publication 从本机 `0x0001` 改回 Group `0xC000`；
- 最终 Publication 为 period disabled、retransmit 2 次/100 ms，Config Status Success；
- 后续 `0x0090 → 0xC000` 的 Sensor Status 已出现，证明运行时路由恢复。

同一 Lux 连续出现三次，是 Publication 本体加两次 retransmit 的预期现象，不是 App 重复处理错误。

### 9. Profile、三台灯具和 Auto 恢复

当前 Group 类型是 `occupancy_daylight`（云数据中的 Profile type 1），所以目标 100 被保存到 `occupancyLevel`，并按 Lux 发送为 `Light Control Ambient LuxLevel On = 100 lx`。

Log 对三个 Light LC/Scene Element 分别完成：

1. Recall General Scene `0xFF00`；
2. 写入 Ambient LuxLevel On 100 lx；
3. Store Scene `0xFF00`。

`0x008E`、`0x0091`、`0x0094` 三组响应均成功。随后出现 Group `LightLCLightOnOffSetUnacknowledged(isOn: true)`。按页面源码，这条 Auto ON 只会在 `configuring(lightNodes:)` 全部成功后执行，因此可反推 App 认为本轮灯具配置全部成功。

这里仍有两个证据边界：

- Auto ON 是 Group Unacknowledged 消息，没有逐灯 ACK；
- 云端两次 `spaceprops` 返回成功，只证明期望状态已上传，不是设备状态 readback。

## 主要问题与风险

### P1：Sensor 模式采样未等待稳定，已在本 Log 中实际暴露

源码对 Sensor/Plane 亮度点只执行“发 Group Unack 亮度 → 等约 3 秒 → 单次 SensorGet”。本 Log 的 100% 读取 86 后仍继续到 89、94，说明固定等待不足。

直接后果：

- `0x38.maxLux` 偏小；
- 固件对灯具贡献曲线的估计可能错误；
- 自动调光增益、响应速度、稳态误差或饱和行为可能异常；
- 每次校准结果会受灯具过渡时间、传感器滤波和 Mesh 时延影响，重复性差。

### P1：目标 100 lx 没有参与可达性校验

页面只校验目标在 0～2500，调用 `calibrateSensor` 时并不传入目标。SDK 只生成灯具—传感器曲线，成功后 App 才把 100 lx 保存并配置到灯具。

本轮证据为：

- SDK 采用的 100% 值仅 86 lx；
- 同阶段后续最高只观察到 94 lx；
- 目标为 100 lx。

因此当前环境下目标可能位于灯具能力上限附近或以上，至少没有安全余量。不能据此绝对断言永远不可达，因为 94 lx 后没有继续等待到稳定；但也绝不能把 ACK 成功当作 100 lx 可达。

### P1：亮度扫描使用 Group Unack，未证明每台灯都到达采样亮度

0%、25%、50%、30%、100% 都是发往 `0xC000` 的 `LightLightnessSetUnacknowledged`。Console 中看到本机对组播包的 loopback/解密，不是三台灯的 Lightness Status。

只要有一台灯丢包、渐变尚未结束或输出限制不同，Sensor Lux 曲线就不再代表完整 Group。最终逐灯 Profile ACK 也不能反向证明之前的扫描亮度都执行成功。

### P2：环境稳定性允许零样本通过

当前 `publishLuxs.count == 0` 也视为稳定。本轮很可能走到了这个分支。无数据只能说明“没有观测”，不能说明环境稳定。

### P2：恢复 publish delta 的成功未被 SDK 严格门控

源码在发送 `daylightPublishDelta(5)` 后，无论回调内容是否为成功状态都会触发校准成功。本轮设备确实返回了 `31 37 00`，所以没有造成此次故障；但丢包/失败时仍可能被页面标为成功。

### P2：没有 `0x38`/`0x39` 设备读回与断电持久化证据

现有 Vendor GET 没有 `0x38`、`0x39` 读取接口。本 Log 只能证明 Set ACK，不能证明：

- 固件最终保存值与 App payload 一致；
- 曲线/倍率已写入 NVM；
- 断电重启后仍生效；
- 固件实际按 App 假定的公式使用这些字段。

### P2：闭环恢复后的日志尚未达到稳定终点

Publication 恢复到 Group 后，先出现约 82/77 lx；恢复 Auto 后继续出现 72、64、63、59 lx。逐灯 Light CTL 读取约为 50.0%、52.9%、53.4%。

这与“刚恢复到 Dim level 50%，随后才重新开启 Auto”的时序相符，但 Log 在控制器收敛前结束。当前证据既不能证明闭环失败，也不能证明闭环最终达到 100 lx。

### P3：终态可观测性不足

统一诊断日志目前覆盖到 `ack_0x39`，缺少：

- publish delta 恢复结果；
- Sensor Publication 提交/回滚结果；
- Profile 持久化结果；
- 每个 configuring 节点最终结果；
- Group Auto 恢复事件；
- 最终稳定 Lux/Lightness；
- 整轮 `app_complete` 或 `app_failed_after_sdk`。

本轮只能结合普通 Mesh Log 和源码反推后半段成功，排障成本较高。

## Log 中不是校准故障的现象

- `Discarding packet (seqAuth ..., expected > ...)`：同一消息经不同 relay/TTL 重复到达，被重放保护丢弃，属于正常 Mesh 去重。
- `Local ... model ... not bound to key`：虽然日志嘈杂，但对应 ACK 已被正确解析并驱动回调，本轮不是失败证据。
- `Secure Network beacon ... secondary network`：业务 Access PDU 仍能用 Space 1 AppKey 正常解密，不是此次校准阻塞点。
- `Cancelling connection` / `XPC connection invalid`：发生在 SDK 完成 Sensor 参数阶段并主动关闭专用 GATT 后，后续普通 Mesh 配置仍成功。
- 同一 Sensor Lux 连续三次：最终 Publication 配置了两次 retransmit，属于预期。
- Presence Detected 日志：来自 `0x0092` 的 PIR 状态，与 `0x0090` Ambient Lux 校准数据不是同一属性。

## 与校准无关但必须注意的旁路问题

### 日志泄露敏感 Mesh/用户数据

HTTP request body 日志包含完整 Mesh Application Key、用户/Site/Space 标识及完整 Space 配置。这类日志一旦上传工单、群聊或外部平台，就具备安全和隐私风险。

建议：

- 默认对 Key、UUID、用户标识和设备标识脱敏；
- 不在 Release 或可远程采集的普通日志中打印完整 Space JSON；
- 如果本份 Log 已离开可信环境，应评估相关 Mesh Key 是否需要轮换。

### Gzip 声明和观察到的 Body 不一致

日志显示 `Content-Encoding: gzip`，但探针报告 `actualBodyGzip=false`。服务器仍返回 200，说明这次没有阻断云同步；也可能是日志探针观察到压缩前 body，而网络层稍后才处理。应在 HTTP/抓包层单独确认，不能仅凭当前日志认定线上 wire 一定错误。

## 建议的真机复验标准

在不修改业务逻辑的前提下，本轮至少需要以下复验才能判定“校准符合要求”：

1. 保持自然光和人员遮挡稳定，分别在 0%、30%、50%、100% 等待 Lux 连续多次进入窄范围后再记录；重点确认 100% 最终稳定值。
2. 在每个采样亮度读取三台灯的实际 Lightness，确认 Group 中所有灯都达到目标，而不是只看到 App 的 Group Unack send。
3. 确认稳定 100% Lux 高于目标 100 lx，并保留合理余量；若稳定值仍低于或贴近 100，应降低目标或排查灯具输出/安装关系。
4. 完成配置并恢复 Auto 后持续观察到稳定，记录 Sensor Lux 和每台灯 Lightness；验收条件应是 Lux 收敛到 100 lx 的允许误差范围，而不是只看 `0x38`/`0x39` ACK。
5. 断电重启 Sensor 和灯具，再验证 Publication、100/100 倍率语义、自动调光和目标 Lux 是否保持。
6. 若产品目标是工作面/桌面 100 lx，而非传感器安装点 100 lx，Sensor Cal. 的 identity 100/100 本身不建立空间映射，必须同时用外部照度计验证或改用 Plane Cal.。

## 最终回答

本轮可以判定为“协议发送成功、App 配置流程成功”，不能判定为“校准质量和 100 lx 闭环符合要求”。

最可能影响现场效果的首要问题是 Sensor 模式固定 3 秒单次采样导致曲线最大点偏低；其次是目标 Lux 不参与可达性检查；再次是 Group 亮度扫描无逐灯确认。若现场表现为 Auto 恢复后达不到 100 lx、响应慢、亮度顶住或多次校准结果不一致，这三项应优先排查。

## 源码依据

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`：Sensor 页面输入、Auto 暂停/恢复、目标保存、Publication 提交、Configuring。
- `SunSmart/Main/Group/View/LightSensorCalibrationModeView.swift`：Sensor 目标范围 `0...2500` 和 Dim level UI。
- `SunSmart/Common/Data/Node+SyncData.swift`：`occupancy_daylight` 目标 Lux 和灯具待同步 Profile 计算。
- `SunSmart/Common/Data/Node+MessageHandles.swift`：Light LC Lux、Scene、Publication 的消息构造。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`：初始化、稳定性检查、拐点搜索、固定等待采样、`0x38`/`0x39`、回滚和 publish delta 恢复。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift`：Group Lightness 默认 Unack、Ambient Sensor Get。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`：Vendor payload 字段顺序。
