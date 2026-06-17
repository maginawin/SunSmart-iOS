# Daylight Calibration Point LUX 算法与 SIG Mesh 协议说明

## 结论

`ambientLightOffLux` 和 `ambientLightOnLux` 是用户用照度计读到的参考照度值，不是直接下发给设备的两个原始 lux payload。

当前校准流程把它们作为“真实环境参考值”保存到 SDK，然后通过 SIG Mesh 控灯、SIG Sensor 读取传感器实测 lux，再计算两类厂商校准参数：

- 灯光对传感器读数产生影响的亮度拐点：`daylightCalibrateIlluminanceInflectionPoint`
- 传感器读数与真实水平面环境光之间的倍率：`daylightCalibrateRate`

其中 `ambientLightOffLux` / `ambientLightOnLux` 只在最终倍率计算阶段使用。拐点命令中的 `minLux` / `maxLux` 来自传感器实测值差值，不来自输入框原值。

## 输入来源

页面入口是 `LightSensorCalibrationViewController.calibrationBtnAction()`。

页面读取：

- `OFF - Calibration Point LUX` -> `offLux`
- `ON - Calibration Point LUX` -> `onLux`

页面只做四类校验：

1. 当前没有正在 loading 的 sensor。
2. 已选中 sensor。
3. `onLux` / `offLux` 都存在，且在 `UInt16` 范围内。
4. `onLux > offLux`。

校验通过后调用 SDK：

```text
MeshSensorCalibrateManager.calibrate(
  node: sensor,
  ambientLightOffLux: UInt16(offLux),
  ambientLightOnLux: UInt16(onLux)
)
```

SDK 保存到内部状态：

- `ambientLightOffLux`：关灯时，用户用外部照度计测得的真实环境 lux。
- `ambientLightOnLux`：开灯时，用户用外部照度计测得的真实环境 lux。

源码位置：

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`

## SIG Mesh 协议层次

这条校准链路同时使用标准 SIG Mesh 消息和 Sunricher 厂商消息。

### 标准 SIG Mesh 消息

标准 SIG Mesh 消息负责“控制灯”和“读取传感器”，不承载用户输入的 ON/OFF lux。

| 目的 | SIG Mesh Message | Opcode | 当前用途 |
| --- | --- | --- | --- |
| 控制组亮度 | `LightLightnessSetUnacknowledged` | `0x824D` | 将 group 灯光设为 0%、25%、50%、75%、95%、100% 等采样点 |
| 读取环境光传感器 | `SensorGet` | `0x8231` | 请求 `Present Ambient Light Level` |
| 传感器回应 | `SensorStatus` | `0x52` | 返回传感器实测 lux |
| 临时设置传感器 publish | `ConfigModelPublicationSet` | 标准 Config Model 消息 | 校准期间让 sensor publish 到本机节点，便于稳定性检查 |

`SensorGet` 请求的属性是：

- Device Property：`Present Ambient Light Level`
- Property ID：`0x004E`

也就是说，SDK 采样的 `lightOffLux` / `lightOnLux` / 拐点 lux 都来自 SIG Sensor Server 对 `0x004E` 的 `SensorStatus` 上报或响应。

### Sunricher 厂商消息

真正写入校准结果的是厂商 Access Message：

| 消息 | Opcode |
| --- | --- |
| `SunricherVendorSet` | `0xF0780A` |
| `SunricherVendorStatus` | `0xF3780A` |

厂商 payload 的前两字节是 Sunricher 自定义功能码：

- 主码：`VendorOpCode.daylightSensor = 0x31`
- 子码：
  - `0x36`：`daylightCalibrate`
  - `0x37`：`daylightPublishDelta`
  - `0x38`：`daylightCalibrateIlluminanceInflectionPoint`
  - `0x39`：`daylightCalibrateRate`

当前 SDK 的 `UInt16` payload 通过 `Data + UInt16` 写入。在 iOS 当前运行环境下这是 little-endian 字节序；代码里只有显式调用 `.bigEndian` 的地方才会用大端。

ACK 规则：

- ACK opcode：`0xF3780A`
- ACK payload 起始：`0x31 + 子码 + status`
- `status == 0` 表示成功。
- `status != 0` 表示失败，SDK 记录为 `errorCode`。

## 完整算法流程

### 1. 连接与初始化

SDK 先检查传感器节点是否有：

- `ambientLightSensorModel`
- `sunricherVendorModel`

如果当前 mesh proxy 不是这个 sensor，本流程会扫描并连接该 sensor 的 Mesh Proxy GATT；发送路径会优先对校准设备走这个 GATT bearer，否则走当前 mesh proxy。

### 2. 清空旧校准值

发送：

```text
SunricherVendorSet / 0xF0780A
payload: 31 36 FF FF
```

含义：

- `0x31`：daylight sensor 主码
- `0x36`：daylight calibrate 子码
- `0xFFFF`：清空或重置设备缓存的旧校准值

SDK 要求收到 `SunricherVendorStatus` 且 `status == 0`，否则失败。

### 3. 重置倍率为 100/100

发送：

```text
SunricherVendorSet / 0xF0780A
payload: 31 39 64 00 64 00
```

含义：

- `0x39`：daylightCalibrateRate
- `sensorRate = 100`
- `ambientLightRate = 100`

这里还没有使用用户输入，只是把设备倍率恢复为 1.00 倍，避免旧倍率影响后续 sensor lux 采样。

### 4. 降低传感器上报阈值

发送：

```text
SunricherVendorSet / 0xF0780A
payload: 31 37 01 00
```

含义：

- `0x37`：daylightPublishDelta
- `delta = 1 lux`

这样校准期间 sensor 对 lux 变化更敏感，便于 App 观察环境光是否稳定。

### 5. 临时把 Sensor Publish 指向本机

SDK 发送 `ConfigModelPublicationSet`，把 ambient light sensor model 的 publish address 临时设为本机 local node unicast address。

这一步不是校准数学本身，但它让 App 能在接下来的 3 秒窗口里接收 `SensorStatus` publish，用于稳定性判断。

### 6. 环境光稳定性检查

SDK 注册 `SensorStatus` 回调，筛选属性：

```text
DeviceProperty.presentAmbientLightLevel = 0x004E
```

持续收集约 3 秒，得到 `publishLuxs`。

当前判断规则：

- 如果 `publishLuxs.count == 0`，当前代码也进入下一步。
- 如果有数据，要求 `max(publishLuxs) - min(publishLuxs) <= 10`。
- 否则失败为 `ambientInstability(minLux:maxLux:)`。

这个稳定性检查用的是传感器自己的 `SensorStatus`，不是用户输入的 lux。

### 7. 获取关灯传感器基准点 `offPoint`

SDK 先控制灯光为 0：

```text
LightLightnessSetUnacknowledged / 0x824D
lightness = 0x0000
```

等待约 3 秒后读取 sensor lux：

```text
SensorGet / 0x8231
property = 0x004E Present Ambient Light Level
```

得到：

```text
offPoint.lightness = 0
offPoint.lux = sensor 在关灯状态下实测的 lux
```

这个 `offPoint.lux` 会保存为后续的 `lightOffLux`，但此时还不是最终变量赋值点。

### 8. 搜索灯光影响传感器的最小拐点

SDK 以 `offPoint.lux` 作为基准：

```text
baseLux = offPoint.lux
threshold = 2 lux
```

先做粗扫：

```text
25%, 50%, 75%, 95%
```

每个点都执行：

1. 用 `LightLightnessSetUnacknowledged` 设置 group lightness。
2. 等待约 3 秒。
3. 用 `SensorGet(0x004E)` 读取当前 lux。
4. 判断 `currentLux >= baseLux + 2`。

如果某个粗扫点首次满足条件，则在“上一个未满足点”和“当前满足点”之间做 5% 步进精扫。

精扫规则：

- 起点：上一个未满足百分比 + 5%
- 终点：当前满足百分比
- 步进：5%
- 第一个满足 `lux >= baseLux + 2` 的点作为拐点

如果粗扫和精扫都没有找到满足点：

```text
resultPoint = offPoint
```

即认为灯光最小影响点就是 0%。

### 9. 获取全开传感器点 `onPoint`

SDK 控制灯光为最大亮度：

```text
LightLightnessSetUnacknowledged / 0x824D
lightness = 0xFFFF
```

等待约 3 秒后读取 sensor lux：

```text
SensorGet / 0x8231
property = 0x004E Present Ambient Light Level
```

得到：

```text
onPoint.lightness = 0xFFFF
onPoint.lux = sensor 在全开状态下实测的 lux
```

随后要求：

```text
onPoint.lux >= offPoint.lux
```

如果全开读数小于关灯读数，认为拐点数据异常，校准失败。

### 10. 计算并下发灯光拐点

先计算传感器实测差值：

```text
minLuxDelta = resultPoint.lux - offPoint.lux
maxLuxDelta = onPoint.lux - offPoint.lux
```

这两个值必须是非负值。

然后发送：

```text
SunricherVendorSet / 0xF0780A
payload:
31 38
minLightness
minLuxDelta
maxLightness
maxLuxDelta
```

字段含义：

| 字段 | 来源 | 含义 |
| --- | --- | --- |
| `minLightness` | `resultPoint.lightness` | 传感器开始明显受灯光影响的最小亮度 |
| `minLux` | `resultPoint.lux - offPoint.lux` | 最小拐点相对关灯基准的 sensor lux 增量 |
| `maxLightness` | `0xFFFF` | 全开亮度 |
| `maxLux` | `onPoint.lux - offPoint.lux` | 全开相对关灯基准的 sensor lux 增量 |

注意：这里的 `minLux` / `maxLux` 都是 sensor 实测增量，不是 `ambientLightOffLux` / `ambientLightOnLux`。

成功后 SDK 记录：

```text
lightOffLux = offPoint.lux
lightOnLux = onPoint.lux
lightMinInflectionPoint = (resultPoint.lightness, minLuxDelta)
lightMaxInflectionPoint = (0xFFFF, maxLuxDelta)
```

### 11. 计算最终校准倍率

这一步才使用用户输入的两个参考 lux。

先计算用户照度计参考差值：

```text
ambientLuxDelta = ambientLightOnLux - ambientLightOffLux
```

再计算传感器实测差值：

```text
sensorLuxDelta = lightOnLux - lightOffLux
```

两个差值都必须大于 0。否则失败为 `inflectionPointError`。

然后计算两个 rate：

```text
ambientLightRateValue = ambientLightOffLux / lightOffLux * 100
sensorRateValue = ambientLuxDelta / sensorLuxDelta * 100
```

当前 SDK 实际使用 `clampedRate`：

```text
rate = Double(max(numerator, 1)) / Double(max(denominator, 1)) * 100
rateInt = Int(rate)
rateUInt16 = clamp(rateInt, 0...5000)
```

因此：

- 分母为 0 时按 1 处理，避免除 0。
- 分子为 0 时按 1 参与计算，但 `Int(rate)` 仍可能截断为 0。
- 小数部分会被截断，不做四舍五入。
- 最大值限制为 5000，即最大 50.00 倍。

两个 rate 的业务含义：

| rate | 公式 | 含义 |
| --- | --- | --- |
| `ambientLightRateValue` | `ambientLightOffLux / lightOffLux * 100` | 关灯基准下，传感器读数到照度计真实水平面环境光的比例 |
| `sensorRateValue` | `(ambientLightOnLux - ambientLightOffLux) / (lightOnLux - lightOffLux) * 100` | 灯光打开造成的真实 lux 增量，与 sensor 实测 lux 增量之间的比例 |

### 12. 下发最终倍率

发送：

```text
SunricherVendorSet / 0xF0780A
payload:
31 39
sensorRateValue
ambientLightRateValue
```

字段顺序要注意：payload 中先是 `sensorRate`，再是 `ambientLightRate`。

这也是整个流程中唯一直接使用 `ambientLightOffLux` / `ambientLightOnLux` 计算出的下发命令。

### 13. 保存本地校准数据

如果设备 ACK 成功，SDK 保存：

```text
sensorCalibrationData = {
  sensorRatio: sensorRateValue,
  ambientlightRatio: ambientLightRateValue,
  minLightInflectionPointData: (minLightness, minLuxDelta),
  maxLightInflectionPointData: (0xFFFF, maxLuxDelta)
}
```

这份本地数据后续会参与 group sync / need sync 判断，用于把校准结果同步给其他相关设备。

### 14. 恢复 sensor 上报阈值

最后 SDK 把 publish delta 恢复为默认值：

```text
SunricherVendorSet / 0xF0780A
payload: 31 37 05 00
```

当前代码对这一步保留兼容逻辑：发送后直接回调成功，不强制要求 ACK 成功。

## 举例说明

假设用户输入：

```text
ambientLightOffLux = 200
ambientLightOnLux = 600
```

SDK 采样得到：

```text
lightOffLux = 50
lightOnLux = 250
```

则：

```text
ambientLuxDelta = 600 - 200 = 400
sensorLuxDelta = 250 - 50 = 200
ambientLightRateValue = 200 / 50 * 100 = 400
sensorRateValue = 400 / 200 * 100 = 200
```

最终倍率命令下发：

```text
31 39 C8 00 90 01
```

解释：

- `31`：daylight sensor
- `39`：calibrate rate
- `C8 00`：`sensorRate = 200`
- `90 01`：`ambientLightRate = 400`

输入框中的 `200` 和 `600` 不会以 `C8 00`、`58 02` 的形式作为一对 ON/OFF lux 原样下发。它们只参与计算后变成 rate。

## 关键失败条件

当前流程中和算法相关的失败点主要有：

- sensor 不支持 `ambientLightSensorModel` 或 `sunricherVendorModel`。
- 连接 sensor / proxy 超时。
- reset、rate reset、publish delta、publish set 没有成功 ACK。
- 3 秒稳定性窗口内 sensor lux 波动超过 10 lux。
- 任一采样点无法读取 `SensorStatus(0x004E)`。
- 全开 sensor lux 小于关灯 sensor lux。
- `ambientLightOnLux <= ambientLightOffLux`。
- `lightOnLux <= lightOffLux`。
- 拐点命令或最终 rate 命令没有收到成功 ACK。

## 一句话算法

App 把用户输入的 OFF/ON lux 当成照度计参考值；SDK 通过 SIG Mesh 反复控制灯光亮度并读取 sensor 的 `Present Ambient Light Level`，先算出“灯光亮度 -> sensor lux 增量”的拐点，再把“用户照度计看到的真实 lux 增量”和“sensor 实测 lux 增量”换算成两个百分比倍率，最后用 Sunricher `0x31/0x38` 与 `0x31/0x39` vendor command 写入设备。

## 源码依据

- `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - `calibrationBtnAction()`：读取 ON/OFF lux、校验 `onLux > offLux`、调用 SDK。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
  - `calibrate(...)`：保存 `ambientLightOffLux` / `ambientLightOnLux`。
  - `initialize()`：reset、rate reset、publish delta、临时 publish。
  - `stabilityVerify()`：环境光稳定性检查。
  - `setLightingAndSensorInflectionPoint()`：采样关灯、拐点、全开，并下发拐点。
  - `findTurningPointEfficiently(...)` / `fineSearchInSegment(...)`：25/50/75/95 粗扫与 5% 精扫。
  - `setCalibrateRate()`：计算并下发 `sensorRateValue` / `ambientLightRateValue`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
  - `SunricherVendorSet.opCode = 0xF0780A`
  - vendor payload 拼接规则。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - `SunricherVendorStatus.opCode = 0xF3780A`
  - `VendorOpCode.daylightSensor = 0x31`
  - `VendorDaylightSensorCode` 子码 `0x36` 到 `0x39`
  - ACK status byte 为 0 时成功。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift`
  - `setGroupLightnessState(...)`：发送 `LightLightnessSetUnacknowledged`。
  - `getAmbientSensorValue(...)`：发送 `SensorGet(.presentAmbientLightLevel)`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Lighting/LightLightnessSetUnacknowledged.swift`
  - SIG opcode `0x824D`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Sensors/SensorGet.swift`
  - SIG opcode `0x8231`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Sensors/SensorStatus.swift`
  - SIG opcode `0x52`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/DeviceProperty.swift`
  - `Present Ambient Light Level = 0x004E`。
