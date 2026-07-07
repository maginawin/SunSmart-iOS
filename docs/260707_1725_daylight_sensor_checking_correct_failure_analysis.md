# 日光传感器安装检查失败提示触发条件分析

## 结论

当前 App 提示“日光传感器存在问题，请检查安装是否正确后重试。”的直接条件是：用户在 Group 的日光传感器校准页面点击校准后，`MeshSensorCalibrateManager` 返回 `.lightNoEffect` 或 `.inflectionPointError`。

这条提示不是连接失败、固件版本不支持、用户 ON/OFF lux 输入大小错误、或环境光不稳定的提示。它表示校准流程已经进入“检查灯光是否能被日光传感器正确感知 / 计算校准拐点和倍率”阶段，并判定数据关系不成立。

## 入口

- 文案 key：`checking_correct_failure`
- 中文文案：`日光传感器存在问题，请检查安装是否正确后重试。`
- 入口页面：`LightSensorCalibrationViewController`
- 页面来源：Group 页面进入 `LightSensorCalibrationViewController(group:)`

用户点击校准时，页面先校验：

- 已选择传感器；
- ON/OFF lux 都有值；
- ON/OFF lux 在 `UInt16` 范围内；
- `onLux > offLux`；
- 传感器支持当前校准能力。

通过这些校验后，才调用 SDK 的 `MeshSensorCalibrateManager.manager.calibrate(...)`。

## UI 层错误映射

`LightSensorCalibrationViewController` 对 SDK 失败类型的映射如下：

- `.connectTimeout` / `.disconnect`：显示连接失败；
- `.deviceNotsupport` / `.noResponse`：显示连接失败；
- `.ambientInstability`：显示“亮度发生意外变化，请在稳定光环境下重试。”；
- `.lightNoEffect`：显示“日光传感器存在问题，请检查安装是否正确后重试。”；
- `.inflectionPointError`：显示“日光传感器存在问题，请检查安装是否正确后重试。”。

因此，这个问题提示只对应 `.lightNoEffect` 和 `.inflectionPointError` 两类底层错误。

## `.lightNoEffect` 的实际条件

当前 SDK 主路径中，`.lightNoEffect` 主要发生在读取灯光亮度点对应的传感器 lux 失败时：

- 读取 0% 亮度下的 `offPoint` 失败；
- 读取 100% 亮度下的 `onPoint` 失败。

这些读取是 SDK 先控制灯光亮度，等待约 3 秒，再通过 ambient sensor value 获取传感器当前 lux。失败通常意味着 App 没能拿到该传感器对当前灯光状态的有效 lux 数据。

从用户现象上看，常见可能性包括：

- 传感器未正确安装或未对准被控灯具区域；
- 传感器与当前 group 的灯具空间关系不成立，灯光变化没有反映到传感器读数；
- 传感器当前没有有效上报或读取失败；
- 校准过程中 mesh 通信或 SensorGet / SensorStatus 链路没有返回有效 lux。

## `.inflectionPointError` 的实际条件

`.inflectionPointError` 表示 App 已经拿到部分数据，但数据无法形成有效校准关系。当前主路径包括：

- 100% 亮度的传感器 lux 小于 0% 亮度的传感器 lux；
- 计算 `resultPoint.lux - offPoint.lux` 或 `onPoint.lux - offPoint.lux` 时数据关系异常；
- 下发 daylight calibration inflection point vendor 命令失败或设备返回非成功；
- 最终计算倍率时，用户输入的 `ambientLightOnLux - ambientLightOffLux` 不大于 0，或传感器实测的 `lightOnLux - lightOffLux` 不大于 0。

UI 层已经提前拦截 `onLux <= offLux`，所以实际更常见的是传感器实测差值不成立：灯开到 100% 后，传感器读到的 lux 没有比关灯时更高。

## 校准流程中的相关阶段

校准开始后 SDK 大致按以下顺序执行：

1. 清旧 daylight calibration；
2. 将 sensor/ambient rate 复位为 100/100；
3. 将 daylight publish delta 临时设置为 1；
4. 将 ambient light sensor publish 临时配置到本地节点；
5. 采样环境光稳定性，3 秒内 lux 波动大于 10 会走 `.ambientInstability`，不会显示本问题提示；
6. 控制灯光到 0%、25%、50%、75%、95%、100% 以及必要的 5% 细分点，读取传感器 lux；
7. 根据 0% 与 100% 的传感器 lux 差值计算拐点和倍率；
8. 下发 daylight calibration inflection point 和 calibrate rate；
9. 成功后保存 `sensorCalibrationData`，失败后清空本地 `sensorCalibrationData` 并尝试禁用该 sensor publication。

## 判断边界

这句提示更接近“日光传感器没有正确感知当前 group 灯光变化 / 校准数据关系不成立”，不等价于：

- App 蓝牙连接失败；
- 设备完全不支持校准；
- 用户输入格式错误；
- 环境光不稳定。

如果现场复现该提示，优先记录校准期间 0%、100% 亮度下的 sensor lux，以及用户输入的 OFF/ON lux。关键判断是：

- 用户输入是否满足 `ON > OFF`；
- sensor 实测是否满足 `lightOnLux > lightOffLux`；
- sensor lux 是否能在灯光变化后稳定返回；
- vendor inflection point 命令是否 ACK 成功。
