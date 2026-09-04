# Energy Data - True power meter 采集与 L12 分析

## 分析范围

- 页面路径：`Site -> Space -> More -> Energy Data -> Static Data`
- 操作：选择 `True power meter`，点击 `HARVEST NEW ENERGY DATA`，任务未全部完成后选择 `Use incomplete data`
- 重点设备：L12，CID `0x0A78`，PID `0x2304`，主地址 `0x0D04`
- 证据：当前 App 源码、主 workspace 固定的 NordicSigMeshSDK `release@86f5ec9e40148b9cd93e0512702337fcec41dd40`、用户提供的 App 日志和后续加测的设备串口日志

## 结论

当前功能需要分成“采集链路”和“True power meter 分类展示”两部分判断：

| 层级 | L12 当前结果 | 判断 |
| --- | --- | --- |
| Mesh 请求与响应 | App 向 L12 的能耗 Sensor Element `0x0D06` 发送 `Sensor Get`，并收到 `0.283 kWh` 与 `0.313 kWh` | 正常 |
| 节点缓存与不完整快照 | L12 已设置 Rated Power，读取成功后会以主地址 `0x0D04` 保存 `precise=283 Wh`、`max/total=313 Wh` | 正常 |
| `True power meter` 分类 | 采集时没有按该分类改变设备集合或协议 | 未实现分类采集 |
| Space / Group / Device 展示 | 该分类下源码直接把汇总值改为 0、把设备列表清空 | 不正常，当前属于占位行为 |

因此，Space all lights 显示 `0.000 kWh` 不是 L12 没有上报，也不是 `Use incomplete data` 丢掉了 L12；直接原因是 `True power meter` 展示分支把已经采集到的值强制覆盖为 0。

## L12 日志核对

### 1. `0x0D04` 与 `0x0D06` 不是地址错位

L12 的主地址是十进制 `3332`，即 `0x0D04`。App 实际发送：

- `SensorGet(property: nil)` 到十进制 `3334`，即 `0x0D06`；
- `SensorStatus` 也从 `0x0D06` 返回；
- 读取完成后的 Identify 发到十进制 `3332`，即主地址 `0x0D04`。

App 通过 `node.energyModel` 找到承载能耗 Property 的 Sensor Server Model，并以该 Model 所属 Element 作为目标地址。当前 L12 的能耗 Model 位于主地址之后的第 2 个 Element，因此能耗通信使用 `0x0D06`。读取成功后的闪烁识别使用节点主地址 `0x0D04`，两者用途不同，链路一致。

### 2. L12 的 Sensor 响应有效

App 收到：

- `Precise Total Device Energy Use = 0.283 kWh`；
- `Active Energy Loadside = 0.313 kWh`。

主 workspace 当前固定的 SDK 会把：

- `Precise Total Device Energy Use` 写入 `node.preciseTotalDeviceEnergyUse`；
- `Active Energy Loadside` 兼容写入 `node.totalDeviceEnergyUse`。

随后 App 在创建静态快照时，将两者分别保存为 L12 的实际累计能耗和当前 App 所称的满功率累计能耗。以日志值计算，L12 单独就应为 Space 精确总能耗贡献 `0.283 kWh`，因此正常分类汇总不可能是 0。

### 3. 后加测设备串口日志只作旁证

设备后续加测打印了 `real_sensor_get: real:284072` 和 `total_sensor_get: total:314001`，说明设备端两个累计计数器均非零，并且与 App 较早读取到的 `0.283/0.313 kWh` 在趋势上相符。

由于用户已说明串口日志是后续加测，并非 App 日志对应的同一次读取，不能据此要求两个时间点的原始值完全相同。它能证明的是 L12 固件能返回非零能耗，而不是证明同一报文的逐字节一致性。

## 当前 Harvest new energy data 的收集逻辑

### 1. 下拉分类不参与采集

`statisticsFilterType` 只在 `updateUI()` 和各展示 View 中使用。点击 Harvest 后，无论当前选择 `All Statistics`、`True power meter` 还是 `Manual data entry`，都进入同一个 `readMeshDevicesEnergy()`。

采集设备集合为当前 Mesh 中：

- `deviceType == .light`；
- 不是 Emergency Sign Controller。

这里没有读取 `supportRealPowerMetering`，也没有按 PID `0x2304` 对设备进行 True power meter 分类。

### 2. Rated Power 是采集前置条件，不是本次实时读取内容

进入 Harvest data 后，每个灯具建立一个 `totalDeviceEnergyUse` 读取任务。若节点本地的 `phaseEnergyConsumptions` 为空，任务会立即标记为缺少 Rated Power，不发送本次能耗请求。

L12 的 PID `0x2304` 在当前 App 中确实被判定为支持真实功率计量。执行 Activate 后，设备参数链路会设置并读取 Rated Power，使 `phaseEnergyConsumptions` 非空。Harvest 本身不会再次 Activate，也不会重新读取 Rated Power；它只使用已经缓存的 Rated Power 判断该设备是否具备采集前置条件。

### 3. 实际 Mesh 请求

符合前置条件且存在 `node.energyModel` 时，App 创建不指定 Property 的 `Sensor Get`：

- Model：SIG Sensor Server，Model ID `0x1100`；
- 请求 Opcode：`0x8231`；
- 请求参数：空；
- 响应 Opcode：`0x52`；
- 含义：返回目标 Element 上的全部 Sensor 值。

因此 L12 一次响应同时带回 `Precise Total Device Energy Use` 和 `Active Energy Loadside`，符合当前实现。

### 4. 串行读取与成功判断

Harvest data 页面逐设备串行执行任务，每个请求默认等待应答；消息 Handle 成功后设备任务标记为成功。如果设备闪烁模式不是 None，成功设备还会追加一次 Identify，这正是 L12 日志中 `SensorStatus` 之后出现 `0x0D04` Identify 的原因。

若某些设备缺少 Rated Power、缺少能耗 Model、超时或响应失败，整个页面进入 failure 状态，并显示 `Use incomplete data`。

### 5. `Use incomplete data` 的保存语义

选择 `Use incomplete data` 后：

- 成功设备：从 Node 缓存复制本次 `totalDeviceEnergyUse` 与 `preciseTotalDeviceEnergyUse`；
- 失败设备：本次快照的两个能耗字段留空；
- 未设置 Rated Power 的设备：状态改为 `notSetPower`；
- 所有设备记录以节点主地址保存，因此 L12 快照地址是 `0x0D04`；
- 快照写入 App 本地 SQLite 的 `energyStaticDatas` 表；
- Space 精确总能耗是所有快照记录 `preciseTotalEnergyUse` 的求和，空值按 0 处理。

L12 在所贴日志中已收到有效 `SensorStatus`，且 Rated Power 已激活，因此它不属于失败设备，应以成功记录进入不完整快照。

## `0.000 kWh` 的直接代码原因

当前 `True power meter` 分支没有对快照设备进行真实分类或求和，而是执行以下占位处理：

- Space：把 `totalEnergy`、`maxTotalEnergyUse`、`totalRatedPower`、节能值和节能比例全部设为 0；
- Latest / Previous / Interval：全部设为 0；
- Group：把每个 Pie 数据值与比例设为 0，并把 Group 总值设为 0；
- Device：直接把 `showDevices` 清空。

Git 历史显示，这一行为从 2025-06-07 的能耗分类改动开始就是显式加入的零值/空列表逻辑，并非本次 L12 采集后才产生的计算异常。当前页面虽然提供 `True power meter` 选项，但对应分类统计仍未接入实际数据。

另一个分类问题是：Space 和 Group 的 `Manual data entry` 没有单独过滤，显示结果与 All 相同；Device 层只排除 `notSetPower`，没有排除 `supportRealPowerMetering == true` 的设备，因此已激活 Rated Power 的 L12 也会被包含在该分类中。现有三个分类不是互斥、完整的业务分类。

## 云同步日志的关系

末尾的 `/sitespace/sync/spaceprops` 成功，只能证明 Space props 上传成功。Harvest 完成时控制器会发送 Space device change 通知，因此触发该上传；静态 Energy 快照本身由 `EnergyStatisticsStaticData.save(spaceId:)` 写入本地 SQLite。

所以 HTTP 200 与本问题的 `True power meter` 汇总是否正确没有直接证明关系。

## 建议的后续修复边界（本次未实施）

如继续修复，应先确认产品对三个分类的明确口径，然后在一处统一分类并让 Space、Group、Device 共用同一过滤结果：

- `All Statistics`：全部具备能耗记录的合格灯具；
- `True power meter`：由真实功率计量能力判定的设备，例如当前 PID `0x2304`；
- `Manual data entry`：使用手动 Rated Power 曲线、且不属于真实功率计量设备的灯具。

不能只删除 Space View 中的置零代码，否则 Group、Device、历史值和分类互斥性仍会不一致。历史快照只保存了 `productId`、未保存公司 ID 或数据来源类型，修复时还需要决定历史数据如何稳定分类。

## 代码证据

- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift:38-58`：能耗分类定义。
- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift:150-180`：Harvest 设备范围。
- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift:241-307`：节点缓存转换、`Use incomplete data` 保存。
- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift:325-363`：Group 和 Device 的 True power meter 零值/空列表逻辑。
- `SunSmart/Main/Energy/View/EnergyStaticDataSpaceView.swift:298-385`：Space、Latest、Previous、Interval 的强制置零逻辑。
- `SunSmart/Main/Energy/View/EnergyStaticDataGroupView.swift:35-79`：Group 总值强制置零逻辑。
- `SunSmart/Main/Space/Controller/ReadDevicesDataViewController.swift:183-214`：Harvest 任务与 Rated Power 前置判断。
- `SunSmart/Main/Space/Controller/ReadDevicesDataViewController.swift:390-420`：`Use incomplete data` 入口。
- `SunSmart/Main/Space/Controller/ReadDevicesDataViewController.swift:472-705`：串行读取、结果判定与完成回调。
- `SunSmart/Common/Data/Node+SyncData.swift:323-350`：由 Energy Model 创建 `SensorGet()`。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2518-2541`：PID `0x2304` 的真实功率计量能力。
- `SunSmart/Main/Energy/Model/EnergyStatisticsStaticData.swift:24-75`：Space 聚合计算。
- `SunSmart/Common/Data/Database.swift:2883-2957`：Energy 静态快照本地持久化。
- NordicSigMeshSDK `release@86f5ec9e` 的 `Node+SupportModels.swift:503-506`：定位能耗 Sensor Model。
- NordicSigMeshSDK `release@86f5ec9e` 的 `Node+Messages.swift:212-283`：Sensor 能耗值写入 Node 缓存。
- NordicSigMeshSDK `release@86f5ec9e` 的 `SensorGet.swift:33-55` 和 `SensorStatus.swift:36-63`：请求与响应定义。

## 验证边界

本结论已由当前源码、固定 SDK 版本和用户日志交叉验证。未修改业务代码，因此未执行构建。当前证据足以判定 L12 通信与解析成功，也足以定位 `0.000 kWh` 的 UI/分类代码原因；尚未验证修复后的真机完整 UI，因为本次没有实施修复。
