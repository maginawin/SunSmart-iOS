# HDB 网关配置任务

Element 按设备 Composition 选择；“所有 Elements”包含 Primary Element，同类 Model 的全部实例均需处理。Vendor Model：Company ID=`0x0A78`，Model ID=`0x0001`。

Config 命令发送到设备 Primary Address，参数指定目标 Element Address 和 Model ID；灯光控制命令按下文指定地址发送。配置任务等待成功 ACK 后继续，失败停止当前设备任务。

## 1. 添加设备：Preparation

按以下顺序执行。

### 1.1 Sensor Group

- 设备任一 Element 存在 Sensor Server `0x1100`：为设备分配唯一 `sensorGroupId`，已有则复用。地址范围 `0xC001...0xFEFC`，不得与其他 Sensor Group、Lighting Zone 重复。
  - 订阅 `sensorGroupId`：发送 `ConfigModelSubscriptionAdd`。
    - 所有 Elements 下的 Light LC Server `0x130F`。
    - 所有 Elements 下的 Sensor Server `0x1100`。
  - 发布到 `sensorGroupId`：发送 `ConfigModelPublicationSet`。
    - 目标：Presence Detected（Property ID=`0x004D`）所在 Element 的 Sensor Server `0x1100`。
    - 条件：全部 Sensor Server 类型已知且非 0，并且仅有一个 Presence Sensor；类型未齐或无 Presence 时跳过 publication，类型已齐但存在多个 Presence 时报错。
    - 参数：Address=`sensorGroupId`，AppKey=当前 Space AppKey，Credentials Flag=`0`，TTL=`0xFF`，Period=`0`，Retransmit Count=`2`、Interval=`100 ms`。
- 没有 Sensor Server：跳过本节。

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

向所有 Elements 下的 Light LC Setup Server `0x1310` 发送 `LightLCPropertySet`，值取设备 Lighting Configuration；新设备默认如下：

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
- 全部完成后，向所有 Elements 下的 `0x130F` 发送 `LightLCLightOnOffSet(true)`，省略 Transition Time 和 Delay。

## 2. 设置 Lighting Zones

执行顺序：**Delete All → Broadcast → Sensor Group → Add Zones**。全部 Delete All 成功后才能开始 Add；重试从 Delete All 重新执行。

Zone Models 为所有 Elements 下的以下全部实例（设备须具备这五类）：

- Generic OnOff Server `0x1000`。
  - 只需要 Primary element 中的 Generic OnOff Server 

- Light Lightness Server `0x1300`。
  - 所有 Elements

- Light LC Server `0x130F`。
  - 所有 Elements

- Light LC Setup Server `0x1310`。
  - 所有 Elements

- Vendor Model `0x0A78 / 0x0001`。
  - 只需要 Primary element 中的 Vendor Model 


### 2.1 Delete All

- 对全部 Zone Models 发送 `ConfigModelSubscriptionDeleteAll`。

### 2.2 Broadcast：订阅 `0xFEFD`

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

**HDB 实现区别**：App 在 Delete All 成功后，额外清除整条扩展链的本地订阅缓存，包括其他 Elements；源码注释将此归因于 HDB 固件行为。这不是上述标准共享规则，本次未以设备读回验证。网关复现当前 App 任务时，按整条链计算恢复目标；判断固件是否确实跨 Element 清除，须以设备读回为准。

### 2.3 订阅 `sensorGroupId`

- 设备有 Sensor Server：必须已有 `sensorGroupId`。
  - 遍历所有包含 `0x130F` 的 Elements，包括 Primary Element。
  - 向其中的 `0x130F` 发送 `ConfigModelSubscriptionAdd(sensorGroupId)`。
  - 同一 Element 内如果有 `0x1000`、`0x1310`，也分别发送该订阅命令。
- 没有 Sensor Server：跳过本节。

### 2.4 Add Zones

- 按所选 `zoneId` 查询实际 `groupAddress`。
- 对每个 `groupAddress`，向全部 Zone Models 发送 `ConfigModelSubscriptionAdd(groupAddress)`。
- 每台设备最多选择 8 个 Zone；选择为空时，仅执行前面的 Delete All 和保留地址恢复。

## 3. Auto / Force On / Force Off

### Lighting Zone：发送到 Zone 的 groupAddress

| 操作 | 命令 | 接收 Model |
| --- | --- | --- |
| Auto | `LightLCLightOnOffSetUnacknowledged(true)` | `0x130F` |
| On | `GenericOnOffSetUnacknowledged(true)` | `0x1000` |
| Off | `GenericOnOffSetUnacknowledged(false)` | `0x1000` |

### Lighting Configuration：选中设备，逐 Element 单播并等待 ACK

| 操作 | 命令 | 目标 |
| --- | --- | --- |
| Auto | `LightLCLightOnOffSet(true)` | 所有 Elements 下的 `0x130F` |
| Force On | `LightLightnessSet(65535)` | 所有 Elements 下的 `0x1300` |
| Force Off | `GenericOnOffSet(false)` | Primary Element 下的 `0x1000` |

以上控制命令均省略 Transition Time 和 Delay。
