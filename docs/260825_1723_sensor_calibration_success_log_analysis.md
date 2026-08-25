# Sensor Calibration 成功 Log 分析

## 结论

这份 Log 可以确认 **SDK 内部的 Sensor Calibration 采样、灯具状态确认、目标可达性判断、0x38/0x39 写入及传感器上报阈值恢复均已成功**。

但这份 Log 截止于 SDK 的最后一步，不能单独证明 App 成功回调之后的整条业务链均已完成，包括传感器 publication 切换、Group Profile 保存、全部灯具 Profile 配置、Group Auto 恢复，以及真实设备长期运行效果。

因此应区分：

| 检查层级 | 结论 |
| --- | --- |
| SDK Sensor Calibration 参数写入流程 | 成功 |
| App Sensor Cal. 整轮业务收尾 | 当前 Log 未完整覆盖 |
| 真实设备闭环调光效果 | 当前 Log 不能证明 |

## SDK 成功证据

### 1. 传感器上报阈值切换成功

- 开始时将 Lux publish delta 设置为 `1`，第一次 ACK 成功。
- 结束时恢复为默认值 `5`，第一次 ACK 成功。
- SDK 源码在默认阈值恢复成功后调用 `successfulCallback`，因此最后一条 `delta=5 ... success=true` 已到达 SDK 的成功出口。

### 2. 所有必需灯具均已到达指定 Lightness

- 0%、25%、约 5% 和 100% 四个阶段均出现 `light_verify_complete ... success=true`。
- 100% 阶段的 `0x008C` 在 `attempt=1` 才确认成功，表示首次校验未满足后执行了单灯修复；最终仍然成功，不属于校准失败。

### 3. Lux 采样稳定

- 环境 Lux：代表值 `295`。
- 0% Lux：代表值 `46`。
- 25% Lux：代表值 `117`。
- 最小拐点（Lightness 3276）：代表值 `65`。
- 100% Lux：样本 `[294, 294, 294, 295]`，稳定代表值 `294`。

### 4. Sensor 模式目标可达性判断正确

- Target Lux：`294`。
- 95% 下限：`ceil(294 × 0.95) = 280`。
- 100% 稳定代表值：`294`。
- 判断：`294 >= 280`，所以 `target_reachability ... success=true` 正确。

这里使用的是 100% 时的 `sensorOnLux=294`，没有减去 0% 时的 `sensorOffLux=46`。这符合修复边界：Sensor Cal. 的目标可达性不使用 `OnLux - OffLux`。

### 5. 0x38 参数与采样结果一致

- 最小拐点：Lightness `3276`，Lux Delta `65 - 46 = 19`。
- 最大拐点：Lightness `65535`，Lux Delta `294 - 46 = 248`。
- Payload：`3138 CC0C 1300 FFFF F800`。
- `CC0C`（小端）为 3276，`1300` 为 19，`FFFF` 为 65535，`F800` 为 248。
- `ack_0x38 ... success=true`。

0x38 中减去 0% Lux 是灯光曲线相对基线的 Delta 编码，不是 Sensor 模式的目标可达性门槛，不在本次修复的删除范围内。

### 6. 0x39 写入成功

- Sensor 模式使用 identity rate：`sensorRate=100`、`ambientLightRate=100`。
- Payload：`3139 6400 6400`，两个小端数值均为 100。
- `ack_0x39 ... success=true`。

Log 中的 `sensorDeltaLux=248` 仅用于诊断展示，实际 0x39 Payload 写入的是 `100/100`，没有用 `248` 计算 Sensor 模式的校准比例。

## 为什么还不能仅凭这段 Log 宣称 App 全流程成功

SDK 在最后一次 `ack_publish_delta ... delta=5 ... success=true` 后调用 App 的 `successfulCallback`。App 随后还会执行：

1. 提交选中传感器的 Model Publication；
2. 保存目标 Lux 和 `sensorCal` 模式；
3. 将 Group Profile 配置发送到相关灯具；
4. 仅在灯具配置全部成功后恢复 Group Auto。

当前 `[DaylightCalibrationDebug]` 日志没有覆盖以上 App 层步骤，因此无法排除 SDK 成功后 publication 或灯具 Profile 配置失败、被用户停止等情况。

## 建议的现场确认

若当时 App 的 Configuring 进度最终全部完成、没有出现失败/重试弹窗，并且 Group Auto 已恢复，则可把这次校准判定为 App 层也成功。为形成可审计闭环，后续建议为 App 收尾增加独立日志：publication 提交结果、Profile 本地保存、灯具配置汇总、Group Auto 恢复和最终 `app_complete`。

真实设备验收仍应检查：环境 Lux 变化后灯具是否按新参数稳定调节，以及重启传感器/灯具后参数是否持续有效。
