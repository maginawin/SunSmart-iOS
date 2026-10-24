# HDB 网关配置任务

当前字段、必填规则和完整示例见 [HDB 数据契约](../../docs/261022_1116_HDB_device_model_arrays_plan.md)。Zone Set 使用设备记录中的三个 Model 清单；下文筛选范围用于核对清单，不要求网关重新推导 SDK 的关联模型。

Element 按设备 Composition 选择；“所有 Elements”包含 Primary Element，同类 Model 的全部实例均需处理。Vendor Model：Company ID=`0x0A78`，Model ID=`0x0001`。

Config 命令发送到设备 Primary Address，参数指定目标 Element Address 和 Model ID；灯光控制命令按下文指定地址发送。配置任务等待成功 ACK 后继续，失败停止当前设备任务。

## 1. 添加设备：Preparation

按以下顺序执行。

### 1.1 Sensor publication

- 设备任一 Element 存在 Sensor Server `0x1100`：分配或复用设备唯一 `sensorGroupId`，范围 `0xC001...0xFEFC`，不得与其他 Sensor Group、Lighting Zone 重复。保留 `sensorGroupModels` 元数据，本步骤不添加 Sensor Group 订阅。
- 全部 Sensor Server 类型已知且非 0，并且仅有一个 Presence Detected（Property ID=`0x004D`）时，生成一条 `sensorPublication`：`modelId="1100"`，`elementAddress` 为该 Presence Sensor 所在 Element，`publishAddress` 为本机唯一 LC Server `0x130F` 所在 Element。
- 类型未齐或没有 Presence 时，数组为 `[]`；多个 Presence 时报错。有发布方但无组或无 LC 时，保留发布方信息，`publishAddress=null`；有组且多个 LC 时不默认选第一个，报不支持。
- 数组为空或 `publishAddress=null`：跳过 publication 配置；null 不表示下发禁用命令。
- 非空目标：向设备 Primary Address 发送 `ConfigModelPublicationSet`，参数如下，等待成功 ACK 后继续：
  - Element Address=`sensorPublication[].elementAddress`。
  - Model ID=`sensorPublication[].modelId`（当前为 `0x1100`）。
  - Publish Address=`sensorPublication[].publishAddress`（本机 LC 单播地址）。
  - AppKey=当前 Space AppKey，Credentials Flag=`0`，TTL=`0xFF`，Period=`0`，Retransmit Count=`2`、Interval=`100 ms`。
- 下发前校验发布方与本机 LC 均绑定该 AppKey。当前字段只接受新结构；不兼容旧字段语义。

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

开始 Delete All 前，核对设备身份、权限、AppKey/Model 绑定、任务占用，以及 `zoneModels`、`broadcastModels`、`sensorGroupModels` 与 Composition 的一致性。目标 Zone 必须存在且不超过 8 个；`broadcastId` 必须为 65277；`sensorGroupId` 非空时必须是有效、无冲突的 Sensor Group 地址。任一项失败，不发送 Delete All。

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

### 2.3 保留 Sensor Group 元数据

保留 `sensorGroupId` 与 `sensorGroupModels`，无论是否非空，本步骤均不向 Sensor Group 添加订阅。添加设备时的地址分配与本机 Presence publication 按 §1.1 执行。

### 2.4 Add Zones

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

## 5. 固件网关如何执行 Lighting Configuration

2026-10-22 只读核对 `sunsmart-fireware`（HEAD `585c45a`）及 Nordic 官方 NCS v3.2.4 源码。本工程使用 nRF Connect SDK / Zephyr；以下接口不适用于直接照搬旧 nRF5 SDK for Mesh 示例。此 checkout 未附实际 SDK、构建 `.config` 或运行记录，接口以官方 v3.2.4 核对，部署版本仍由固件团队确认。当前选中产品是灯具 `PRODUCT_9033A_MW_V_54L15`，网关路径另受 `PRODUCT_9036T_GW` / `PRODUCT_HAS_SUNSMART_GATEWAY` 控制。

本节按“网关收到配置后，通过 Mesh 写入灯具”说明。灯具端已实现相应 Server 的收包、参数更新和状态回复；这些配置不要求另造 Vendor 协议。

### 5.1 将字段映射为消息

SDK 支持以下操作，但没有接受任意 `elementAddress/modelId/property/value` 并自动理解业务单位的万能接口。适配层按下表选择消息：

| 输入 | 有 ACK 的 Nordic API | Set / Status Opcode | 参数 |
| --- | --- | --- | --- |
| modelId="1310"，五个 Property | `bt_mesh_light_ctrl_cli_prop_set(cli, ctx, property, val, rsp)` | 0x62 / 0x64 | Property ID + 按属性格式编码的值 |
| Auto：固定 Model 0x130F | `bt_mesh_light_ctrl_cli_light_onoff_set(cli, ctx, set, rsp)` | 0x829A / 0x829C | `set.on_off=true` |
| Force_On：固定 Model 0x1300 | `bt_mesh_lightness_cli_light_set(cli, ctx, set, rsp)` | 0x824C / 0x824E（Actual） | `set.lvl=65535` |
| Force_Off：固定 Model 0x1000 | `bt_mesh_onoff_cli_set(cli, ctx, set, rsp)` | 0x8202 / 0x8204 | `set.on_off=false` |

接口来源：[LC Client](https://github.com/nrfconnect/sdk-nrf/blob/v3.2.4/include/bluetooth/mesh/light_ctrl_cli.h)、[Lightness Client](https://github.com/nrfconnect/sdk-nrf/blob/v3.2.4/include/bluetooth/mesh/lightness_cli.h)、[OnOff Client](https://github.com/nrfconnect/sdk-nrf/blob/v3.2.4/include/bluetooth/mesh/gen_onoff_cli.h)。LC Setup Server 的 Property 也由 LC Client API 发送，不需要一个独立的“LC Setup Client”。

执行前与发送时：

1. `lightingControl` 用外层 `value` 选择同对象的 `Auto` / `Force_On` / `Force_Off` 地址字符串，以十六进制解析为 UInt16。Model 和命令值按上表固定生成；不得把字符串 Auto 或地址文本直接作为 Mesh 参数发送。
2. `ctx.addr=elementAddress`，该地址是远端灯具的 Element 单播地址，不是 Element index，也不能一律替换为 Primary Address。地址为 null 时拒绝发送。无需再扫描并向其他实例发送。
3. `ctx.app_idx` 使用此 Space 的 AppKey index，`ctx.net_idx` 使用其所属 NetKey index，设置适用 TTL。发送端需持有这些密钥，且本地发送 Model 与远端目标 Model 已绑定对应 AppKey。JSON 配置之外，这些来自现有 Mesh 网络上下文，不需要逐字段重复保存。
4. `cli` 是网关本地已初始化、加入 Composition 并绑定 AppKey 的 Client 实例；不能用远端 `modelId` 强转一个 Client 指针。`modelId` 在本适配中用于选消息，通常不作为这四种消息的 payload 字段；Property Set 的 payload 才包含 Property ID。
5. 三种控制 Set 的 `transition=NULL`，省略 Transition Time/Delay，与 App 一致。Lightness Client 必须采用 Actual 表示；启用 `CONFIG_BT_MESH_LIGHTNESS_LINEAR` 会改变该 API 所用 Opcode。
6. 使用有 ACK 接口，不能替换为 `_set_unack`。`rsp=NULL` 表示非阻塞，不代表不请求 ACK；此时返回 0 只表示发送调用成功，必须在对应 status handler 中完成任务。非空 rsp 会等待响应，应放在允许阻塞且不阻塞接收回调的执行上下文。

### 5.2 Property 值的单位

先调用 `bt_mesh_lc_prop_format_get(property)` 获取格式，再通过 `bt_mesh_sensor_value_from_micro(format, micro, &val)` 构造 `bt_mesh_sensor_value`，检查返回值，最后传给 `bt_mesh_light_ctrl_cli_prop_set`。`micro` 使用该属性物理单位的百万分之一，必须使用 64 位运算。

| JSON 字段 | Property / SDK 枚举 | JSON 单位 → SDK micro 参数 → 空中编码 |
| --- | --- | --- |
| brightIntensity | 46 / `BT_MESH_LIGHT_CTRL_PROP_LIGHTNESS_ON` | 百分比 p → 截断(p / 100 × 65535) × 1000000 → 2 字节 Lightness Actual |
| dimIntensity | 47 / `BT_MESH_LIGHT_CTRL_PROP_LIGHTNESS_PROLONG` | 同上；对应 Prolong 亮度 |
| rampDownTime | 54 / `BT_MESH_LIGHT_CTRL_PROP_TIME_FADE_PROLONG` | 秒 s → s × 1000000 → 3 字节毫秒 |
| rampUpTime | 55 / `BT_MESH_LIGHT_CTRL_PROP_TIME_FADE_ON` | 同上 |
| holdTime | 60 / `BT_MESH_LIGHT_CTRL_PROP_TIME_ON` | 同上 |

例如 Bright=80：先得到 52428，再向 `from_micro` 传入 52428000000；Ramp Down=2 秒：向 `from_micro` 传入 2000000，SDK 编码为 2000 毫秒。若已经从 JSON 换算成毫秒，则向 `from_micro` 传入毫秒 × 1000，不可再乘 1000000。格式和单位见 [LC Property 定义](https://github.com/nrfconnect/sdk-nrf/blob/v3.2.4/include/bluetooth/mesh/light_ctrl.h)、[sensor 转换接口](https://github.com/nrfconnect/sdk-nrf/blob/v3.2.4/include/bluetooth/mesh/sensor.h)。

若复用现有底层打包器，以下为未加密 Access 消息字节（不含地址、密钥和传输层封装）：

| 示例 | Opcode + Parameters（十六进制） |
| --- | --- |
| Bright 80%，Property 46 | `62 2E 00 CC CC` |
| Dim 5%，Property 47 | `62 2F 00 CC 0C` |
| Ramp Down 2 秒，Property 54 | `62 36 00 D0 07 00` |
| Ramp Up 1 秒，Property 55 | `62 37 00 E8 03 00` |
| Hold 10 秒，Property 60 | `62 3C 00 10 27 00` |
| Auto | `82 9A 01 TID` |
| Force On | `82 4C FF FF TID` |
| Force Off | `82 02 00 TID` |

Property ID 与数值均按小端写入；不要将两字节 Opcode 当小端整数拼接，使用 `bt_mesh_model_msg_init`。SDK Client 管理 TID；底层手工打包时，新事务分配 TID，同一事务重传保留 TID。重复调用 Client Set 可能递增 TID，不能默认等同原包重传。Property Set 不含 TID。

### 5.3 当前工程已有入口与最小接入范围

网关现有链路是 MQTT `AT+...` → `_commands[]` parser → executor 队列 → packager → `mod_sunricher_srv_send` → `bt_mesh_model_send`。源码见 [gateway_sunsmart.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/gateway_sunsmart.c)、[mod_sunricher_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/mod_sunricher_srv.c)。该底层通道借用本地 Vendor Model 发送标准 Opcode，靠 Access 回调接收 ACK；这里的 Model 指针是本地发送 Model，不是远端 0x1310。

| HDB 操作 | 已有网关命令 / 打包函数 | 接口输入单位 |
| --- | --- | --- |
| 两个亮度 Property | `CTRL_PROP_LIGHTNESS_SET` / `packager_ctrl_prop_lightness_set` | 已换算的 0…65535，非百分比 |
| 三个时间 Property | `CTRL_PROP_TIME_SET` / `packager_ctrl_prop_time_set` | 毫秒，非 JSON 秒 |
| Auto | `CTRL_LIGHT_ONOFF_SET` / `packager_ctrl_light_onoff_set` | onoff=1，time=65535 表示省略过渡字段 |
| Force Off | `ONOFF_SET` / `packager_onoff_set` | onoff=0，time=65535 表示省略过渡字段 |
| Force On | 当前 `_commands[]` 没有对应 Lightness Set 打包入口 | 补 0x824C 打包入口，或接入 Lightness Client |

现有 AT 协议的参数顺序为 `sequence,app_idx,address,property,value`；两个控制命令为 `sequence,app_idx,address,onoff,time,delay`。例如 app_idx=0、目标 Element=1234 时，Bright=80 可表示为 `AT+CTRL_PROP_LIGHTNESS_SET=1,0,1234,46,52428`，Ramp Down=2 秒为 `AT+CTRL_PROP_TIME_SET=2,0,1234,54,2000`；实际字符串以 CRLF 结束。这里是调用格式说明，未向设备发送。AppKey index 必须替换为实际值。

建议固件团队复用现有队列与发送通道，增加 HDB 字段映射、校验和 Force On 打包，不必为了此需求替换整个网关发送架构。若选用 SDK Client 路线，当前网关已有 EnOcean LC/OnOff Client，但其异步 handlers 为 NULL，不能直接复用后把发送返回值当作完成；需协调使用权、回调和队列。当前网关 Composition 没有 Lightness Client，应补对应实例、Kconfig 与 AppKey 绑定，或保留底层通道；不要求修改 JSON 来携带本地 Client Model 清单。

在已核对的网关 MQTT 路径中，没有直接消费本次 `lightingConfiguration` 新格式 的入口。因此“SDK 支持”与“当前工程已经能接收这份 JSON”需要区分：前者已从 SDK 与收包实现确认，后者仍需适配。

### 5.4 ACK 与现有相关缺口

按同一设备逐项发送并等待对应 Status。Property 回复需匹配来源 Element、AppKey、Opcode=0x64、Property ID 和编码后的值；控制回复校验目标状态（存在 target 时用 target，否则用 present）。失败或超时保留待重试，不能把 `bt_mesh_model_send` 返回 0 或任意同 Opcode 回包记为配置成功。SDK Property Client 会匹配来源和 Property ID，业务仍需核对回读值与任务身份；使用异步接口时需自行维护完整任务关联。

当前网关复用前必须处理的相关问题：

- `msg_cb` 已核对 Opcode、AppKey、来源地址，但 Property Set 使用 `ack_common`，未检查 Property ID/值。两个连续 Property 都使用 0x64，前一条迟到回复可能错误完成后一条任务。应增加逐属性回复校验；同属性同值的迟到回复没有协议事务 ID 可区分，任务取消/重建还需执行层管理。
- `ack_ctrl_prop_lightness_get`、`ack_ctrl_prop_time_get` 在 `sensor_ch_decode` 后将 v 初始化为 0，又调用 `bt_mesh_sensor_value_from_micro`，方向用反了，随后报告的 v 仍为 0。应由固件团队改用 `bt_mesh_sensor_value_to_micro` 并检查 numeric status，之后亮度除 1000000、时间除 1000。HDB 如需回读验收，不能直接依赖当前两个 Get 报告。
- `timeout_commandor` 忽略底层发送返回值，Property 打包函数也忽略 `from_micro` 的返回值。适配 HDB 时应检查地址、属性范围、类型、转换与发送错误；格式不支持或数值非法时终止当前字段，而不是发送钳制值或仅等待超时。
- 不建议用当前 `BACKDOOR` 临时替代 Force On：`parser_backdoor` 把 ACK Opcode 读入 uint8_t，无法完整保存 Lightness Status 0x824E。

灯具端 [sr_light_ctrl_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/sr_light_ctrl_srv.c) 的 `_bt_mesh_sr_light_ctrl_setup_srv_op` 已注册 0x62；`handle_prop_set` → `prop_set` 按 Property 解码，更新 light/fade/on 参数，发送 0x64 后调用配置存储。`light_onoff_set` 会清除手动覆盖状态，符合本任务 Auto 命令用途；亮度与 OnOff 则由 [sr_lightness_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/sr_lightness_srv.c) 处理。Status ACK 不等于掉电存储完成，重启保持与实际灯光行为需要设备验收。

本轮只补充 App 仓库内的接口说明，未修改固件、SDK、后端或运行配置，未构建/烧录固件。固件团队负责 HDB 适配及上述相关修正；发布前按本节示例抓取目标地址、Opcode、数值和 Status，并验证超时重试、迟到回复、断电恢复及实际灯光行为。

### 5.5 Property Set 后自动保存，不需要 Store Scene

以 `brightIntensity`（Property 0x002E）为例，当前工程已实现自动持久化；App/网关发送 Property Set 后，不需要再发送 Scene Store 或其他“提交配置”命令。[prj.conf](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/prj.conf) 明确设置 `CONFIG_BT_MESH_STORE_TIMEOUT=2`（秒），并启用 `CONFIG_BT_SETTINGS=y`、`CONFIG_SETTINGS=y`。

实际调用顺序如下，核心源码均在 [sr_light_ctrl_srv.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/sr_light_ctrl_srv.c)：

1. `handle_prop_set` → `prop_set` → `update_lightness_setpoint`：更新 `srv->cfg.light[SR_LIGHT_CTRL_STATE_ON]`。若当前处于 ON 状态，同时更新当前/过渡中的亮度目标；其他状态先更新 ON 状态配置。
2. `prop_tx` 发送 Property Status，随后执行 `bt_mesh_scene_invalidate` 和 `store(srv, FLAG_STORE_CFG)`。无 ACK 的 Property Set 同样会安排保存。
3. `store` 设置配置脏标志，调用 `bt_mesh_model_data_store_schedule(srv->model)`，将工作交给 Mesh 延迟保存队列。
4. 到期后 SDK 调用 LC Server 的 `.pending_store = light_ctrl_srv_pending_store`，进入 `store_cfg_data`。它复制此时最新的完整 `srv->cfg`（及启用时的 regulator 配置），调用 `bt_mesh_model_data_store(srv->setup_srv, false, NULL, &data, sizeof(data))`，写入 LC Setup Server 的持久记录。
5. `bt_mesh_model_data_store` → `settings_save_one` → 所选 Settings 后端写入非易失存储。工程通用 52840 配置使用 NVS；54L15 [板级配置](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/boards/nrf54l15dk_nrf54l15_cpuapp.conf) 关闭 NVS、启用 ZMS，两者都支持此自动保存路径。
6. 重启时 [main_9033a.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/src/main_9033a.c) 调用 `settings_load()`；LC Setup Server 的 `lc_setup_srv_settings_set` 读出配置，执行 `srv->cfg = data.cfg`，不依赖 Scene Recall。

模型数据写入可核对 [工程保留的 NCS 3.2.4 access.c](/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware/patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/access.c)。

**2 秒是共享保存队列的调度延迟，并非每次 Set 都重新计时，也不是保证第 2000 毫秒完成写入。** NCS 3.2.4 的 `bt_mesh_settings_store_schedule` 保留较早的既定 deadline，必要时提前。首次 Set 后 0.8 秒再次修改，通常仍在首次安排的约 2 秒处保存最新值，而非延至 2.8 秒；其他待保存操作可能使它提前，工作队列和存储操作可能增加执行时间。见 [NCS 3.2.4 调度实现](https://github.com/nrfconnect/sdk-zephyr/blob/ncs-v3.2.4/subsys/bluetooth/mesh/settings.c) 和 [Zephyr 模型数据存储说明](https://docs.zephyrproject.org/latest/services/connectivity/bluetooth/api/mesh/access.html#model-data-storage)。

Scene 的关系：

- `bt_mesh_scene_invalidate` 清除当前 Scene 标记和待执行 Scene 工作，表示参数已偏离原 Scene；不删除已保存的 Scene，也不阻止 LC 参数自动保存。
- Scene Store 另存带 Scene 编号的参数快照，供以后 Recall。无需为了保存 Bright/Dim/时间参数而增加 Scene Store。
- 当前固件的 Scene Recall 会把 `scene->cfg` 覆盖回 `srv->cfg`，随后再次安排保存。因此召回旧 Scene 可能覆盖新 Bright 值，不能把这种覆盖误判为 Property Set 没有保存。

持久化边界：Property Status 在完成存储前就发送，刚收到 ACK 就断电仍可能丢失本次修改。另一个明确的异常路径是：`store_cfg_data` 先清除 `FLAG_STORE_CFG`，再忽略 `bt_mesh_model_data_store` 返回值；写失败时底层记录错误，但本函数不恢复脏标志或主动重试。后续新的配置保存可能重新写入最新值，不能保证这次失败自动恢复。这里记录原因与责任边界，未修改固件。

最短人工验收：仅 Set Bright 到不同的值，确认 Property Status；不 Store Scene，保持供电并留出超过 2 秒的调度余量（例如等待 5 秒），断电重启后用 App Property Get 核对。期间不要 Scene Recall，也不要依赖旧网关存在解码问题的 Get 文本。现有 `Store Timeout` 日志只说明进入保存回调；可进一步核对底层 `Stored ... value` / `Failed to store ... value` 来定位写入结果。最终时间以实际 SDK、最终 `.config` 与设备运行结果为准，本轮未执行断电实测。
