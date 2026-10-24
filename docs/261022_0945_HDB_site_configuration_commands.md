# HDB 网关配置任务

当前字段、必填规则和完整示例见 [HDB 数据契约](261022_1116_HDB_device_model_arrays_plan.md)。Zone Set 使用设备记录中的三个 Model 清单；下文筛选范围用于核对清单，不要求网关重新推导 SDK 的关联模型。

Element 按设备 Composition 选择；“所有 Elements”包含 Primary Element，同类 Model 的全部实例均需处理。Vendor Model：Company ID=`0x0A78`，Model ID=`0x0001`。

Config 命令发送到设备 Primary Address，参数指定目标 Element Address 和 Model ID；灯光控制命令按下文指定地址发送。配置任务等待成功 ACK 后继续，失败停止当前设备任务。

## 1. 添加设备：Preparation

按以下顺序执行。

### 1.1 Sensor Group 保留与本机 publication

- 设备任一 Element 存在 Sensor Server `0x1100`：为设备分配唯一 `sensorGroupId`，已有则复用。地址范围 `0xC001...0xFEFC`，不得与其他 Sensor Group、Lighting Zone 重复。保留 `sensorGroupModels`，按 Composition 生成，供其他功能使用；本任务不下发 Sensor Group 订阅。
- 读取 `sensorPublication` 的单条配置：`modelId=1100`；`elementAddress` 是本机 LC Server `0x130F` 所在 Element 的目的地址，**不是发布方 Sensor 的 Element 地址**。无组地址或无 LC 时该字段为 null，跳过 publication；多个 LC 无法唯一确定时报错。
- 目的地址非空时，定位 Presence Detected（Property ID=`0x004D`）所在 Element 的 Sensor Server `0x1100`。要求全部 Sensor Server 类型已知且非 0，并且仅有一个 Presence Sensor；类型未齐或无 Presence 时跳过 publication，多个 Presence 时报错。
- 核对发布方 Sensor 和接收方 LC 都绑定当前 Space AppKey，然后向节点 Primary Address 发送 `ConfigModelPublicationSet`，等待匹配的成功 ACK：
  - 参数 ElementAddress=Presence Sensor 所在 Element；ModelIdentifier=`0x1100`。
  - PublishAddress=`sensorPublication.elementAddress`；AppKey=当前 Space AppKey，Credentials Flag=`0`，TTL=`0xFF`，Period=`0`，Retransmit Count=`2`、Interval=`100 ms`。
  - 例如 Primary/Presence=`0008`、LC=`000A`：配置命令发往 `0008`，参数 ElementAddress=`0008`、PublishAddress=`000A`；运行时 Sensor Status 从 `0008` 发布到 `000A`。

publication 的 null 是合法跳过，不代表后续依赖 LC 的固定参数、灯光参数和 Auto 已具备执行条件；执行完整灯控初始化前仍须核对其所需模型。

### 1.2 固定参数

- 所有 Elements 下的 Vendor Model，依次发送 `SunricherVendorSet`：
  - `manualControlEnabled=false`，功能码 `0x33`。
  - `lightAutoAdjustEnabled=false`，功能码 `0x34`。
  - `manualOverrideTimeout`，功能码 `0x32`：`enabled=true`、`state=standby(0)`、`interval=0xFFFFFFFF ms`。
- 所有 Elements 下的 Light LC Setup Server `0x1310`：
  - `LightLCPropertySet`：Prolong Time（`0x003B`）=`0xFFFFFE`。
- 所有 Elements 下的 Light LC Server `0x130F`：
  - `LightLCOccupancyModeSet(true)`。

### 1.3 灯光参数

向第一个包含 SIG Light LC Server `0x130F` 的 Element 中的 Light LC Setup Server `0x1310` 发送 `LightLCPropertySet`，值取设备 Lighting Configuration；新设备默认如下：

| 参数 | Property ID | 默认写入值 |
| --- | --- | --- |
| Dim Intensity | `0x002F` | `13107`（20%） |
| Bright Intensity | `0x002E` | `52428`（80%） |
| Ramp Up Time | `0x0037` | `1000 ms` |
| Ramp Down Time | `0x0036` | `2000 ms` |
| Hold Time | `0x003C` | `30000 ms` |

亮度换算：`UInt16(百分比 × 65535 / 100)`；时间换算：秒 × 1000。

### 1.4 启用 LC 与 Auto

- 向所有 Elements 下的 `0x130F` 发送 `LightLCModeSet(true)`。
- 全部完成后，仅向第一个包含 `0x130F` 的 Element 发送 `LightLCLightOnOffSet(true)`，省略 Transition Time 和 Delay。

## 2. 设置 Lighting Zones

执行顺序：**Delete All → Broadcast → Add Zones**。全部 Delete All 成功后才能开始 Add；重试从 Delete All 重新执行。

开始 Delete All 前，核对设备身份、权限、AppKey/Model 绑定、任务占用，以及 `zoneModels`、`broadcastModels`、`sensorGroupModels` 与 Composition 的一致性。目标 Zone 必须存在且不超过 8 个；`broadcastId` 必须为 65277；`sensorGroupId` 非空时必须是有效、无冲突的 Sensor Group 地址；该地址及模型清单非空不要求本任务订阅。任一项失败，不发送 Delete All。

Zone Models 即 `zoneModels`，设备须具备以下五类；在所列范围内收录全部实例：

| Model | Element 范围 |
| --- | --- |
| Generic OnOff Server `0x1000` | 仅 Primary |
| Light Lightness Server `0x1300` | 所有 Elements，包括 Primary |
| Light LC Server `0x130F` | 所有 Elements，包括 Primary |
| Light LC Setup Server `0x1310` | 所有 Elements，包括 Primary |
| Vendor `0x0A78 / 0x0001` | 仅 Primary |

### 2.1 Delete All

- 遍历 `zoneModels`，对每项指定的 Element/Model 发送 `ConfigModelSubscriptionDeleteAll`。全部成功后继续。

### 2.2 Broadcast：订阅 `0xFEFD`

`broadcastModels=[]`：跳过本节。否则遍历 `broadcastModels`，向每项指定的 Element/Model 发送 `ConfigModelSubscriptionAdd(broadcastId)`，即 Add(65277)，全部成功后继续。清单由 App 按以下范围生成：

- 遍历所有包含 `0x130F` 的非 Primary Elements。
  - 向其中的 `0x130F` 发送 `ConfigModelSubscriptionAdd(0xFEFD)`。
  - 同一 Element 内如果有 `0x1000`、`0x1310`，也分别发送该订阅命令。
- 对于非 Primary Element 内的 `0x1306`，如果本轮 Delete All 会清除它的订阅：
  - 同一 Element 内有与它共享订阅表的 `0x1000`、`0x1300`、`0x130F`、`0x1310` 时，向其中实际共享的每个 Model 发送 `ConfigModelSubscriptionAdd(0xFEFD)`。
  - 没有上述共享 Model 时，直接向 `0x1306` 发送该订阅命令。

> 0x1306 是 Light CTL Temperature Server

#### 订阅关联

指 Model 之间存在 **Model Extension（模型扩展）关系**。同一 Element 内，相关 Models 共享订阅表，**Add 和 Delete All 都会影响共享该表的 Models**。仅仅处于同一 Element，或订阅了相同组地址，不算关联。这属于 SIG Mesh 标准规则，参见 [Mesh Model 1.1 §1.4.1.1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。本文逐 Model 列出 Add 是当前 App 的显式发送方式，不表示共享表上的 Add 不会联动。

- **LC 示例**：同一 Element 内，`0x1310` 扩展 `0x130F`，`0x130F` 扩展 `0x1000`，因此三者共享订阅表。
- **色温受影响示例**：同一 Element 内存在 `0x1306`、`0x1002`、`0x1300`。其中 `0x1306` 和 `0x1300` 都扩展 Generic Level Server `0x1002`，所以 Delete All `0x1300` 会影响 `0x1306`，需要恢复 `0xFEFD`。
- **色温不受影响示例**：该 Element 只有 `0x1306` 和 `0x1002`，没有连接到 Zone Models 的扩展关系，本轮 Delete All 不影响它。
- **跨 Element**：当前 SDK 将 `0x130F` 关联到前面最近一个包含 `0x1300` 的 Element 中的该 Model，但标准订阅表仍按 Element 分开；不能由扩展关系推导跨 Element 的订阅表也共享。

**HDB 实现区别**：App 在 Delete All 成功后，额外清除整条扩展链的本地订阅缓存，包括其他 Elements；源码注释将此归因于 HDB 固件行为。这不是上述标准共享规则，本次未以设备读回验证。App 已将本轮恢复目标写入 `broadcastModels`，网关直接执行该清单；判断固件是否确实跨 Element 清除，须以设备读回为准。

`sensorGroupId` 与 `sensorGroupModels` 仍需保存和传递，但本次 Zone Set 不订阅该组。不得因为清单非空而补回 Sensor Group。添加设备时的地址分配和本机 Presence publication 按 §1.1 执行。

### 2.3 Add Zones

- 按所选 `zoneId` 查询 `hdb.lightingZones[].groupId`，将 4 位十六进制字符串解析为实际组地址。
- 对每个解析后的组地址，遍历 `zoneModels`，向每项指定的 Element/Model 发送 `ConfigModelSubscriptionAdd(groupAddress)`。
- 每台设备最多选择 8 个 Zone；选择为空时，仅执行前面的 Delete All 和保留地址恢复。

全部实际需要的阶段收到成功 ACK 并完成保存后，才将 `lightingZonesStatus` 记为 synced。失败、超时、取消或保存失败保持 pending；重试从 Delete All 开始，旧任务迟到的 ACK 不得确认新任务。

## 3. Auto / Force On / Force Off

### Lighting Zone：发送到 Zone 的 groupId 对应组地址

| 操作 | 命令 | 接收 Model |
| --- | --- | --- |
| Auto | `LightLCLightOnOffSetUnacknowledged(true)` | `0x130F` |
| On | `GenericOnOffSetUnacknowledged(true)` | `0x1000` |
| Off | `GenericOnOffSetUnacknowledged(false)` | `0x1000` |

### Lighting Configuration：选中设备，逐 Element 单播并等待 ACK

| 操作 | 命令 | 目标 |
| --- | --- | --- |
| Auto | `LightLCLightOnOffSet(true)` | 第一个包含 `0x130F` 的 Element |
| Force On | `LightLightnessSet(65535)` | 第一个包含 `0x1300` 的 Element |
| Force Off | `GenericOnOffSet(false)` | Primary Element 下的 `0x1000` |

以上控制命令均省略 Transition Time 和 Delay。


## 4. Lighting Configuration 字段描述

`spaceData.hdb.schemaVersion=2`。设备 `lightingConfiguration` 的五个 Property 字段提供单个 `elementAddress/modelId/property`，均为 4 位十六进制字符串。`lightingControl` 直接保存 `Auto`、`Force_On`、`Force_Off` 的目标地址字符串；用 `lightingControl[lightingControl.value]` 取当前选项地址，按上表生成固定命令与值，不再读取 mapValues。status/value 保持实际业务状态。

设备 nodeAddress、sensorGroupId、broadcastId 也为 4 位十六进制字符串；三个 Model 清单的 elementAddress 为 4 位、SIG modelId 为 4 位、Vendor modelId 为 8 位。字符串无 0x 前缀、输出大写；解析后再按 Mesh 字段编码。devices[].mac 无分隔符，devices[].lightingZones 是 zoneId 数字数组。顶层 hdb.lightingZones 保留名称及 4 位十六进制字符串 groupId；先按 zoneId 查目录并解析 groupId 得到实际组地址，不读取旧 groupAddress。

“第一个”按 Composition Element index 从小到大选择，包括 Primary。五个 Property 必须发到第一个 LC 所在 Element 的 LC Setup，缺少该 Setup 时失败，不回退到其他 Element。地址显式 null 表示无目标，不得下发或记为发送成功；应存在目标却填 null 属于非法数据。

参数 Set 均逐条等待 ACK：Intensity 为 Dim→Bright，Soft Dimming 为 Ramp Up→Ramp Down；值按 §1.3 换算。failsafeDelay、installDate 仅保存配置，不发送命令。固定 Preparation 的 Vendor/Mode/Occupancy/Prolong 与 Zone/Sensor/Broadcast 订阅仍保持原有全部目标范围。

描述由 App 按已保存的设备模型清单生成；保存和回读必须保留全部新字段，不兼容缺字段的旧 HDB 数据，也不自动迁移。外部执行方按本节及字段描述执行，不能沿用先前 Lighting Configuration 的全实例下发规则。
