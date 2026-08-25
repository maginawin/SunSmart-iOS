# Calibration OnLux / OffLux 语义澄清

## 最终结论

“只有 Night Cal. 才需要 `OnLux - OffLux`”在“目标 Lux 的生成或达标判断”这一层成立：

- Sensor Cal.：用户已经给出 Target Lux，目标可达性只比较 100% 稳定 `OnLux` 与 `ceil(TargetLux × 95%)`，不得减 0% `OffLux`；
- Plane Cal.：没有 Sensor 模式的 Target Lux 95% 可达性门槛，因此也不存在用 `OnLux - OffLux` 做目标达标判断；
- Night Cal.：需要排除环境底光，使用每组目标亮度 `OnLux - OffLux`，再对多组差值求稳定结果，生成 Night Target Lux。

但“整个校准实现中只有 Night 可以出现减法”并不符合当前源码。Plane 的倍率公式和三种模式共用的 `0x38` 曲线目前也使用 Lux 差值；它们不是目标 Lux 判定，需要单独确认，不能随 Sensor 95% 修复一并删除。

## 三层语义对照

| 模式 | 目标 Lux 语义 | `0x39` 倍率 | 当前 `0x38` 曲线 |
| --- | --- | --- | --- |
| Sensor | 外部输入的 Sensor 绝对 Lux；只用 100% 稳定值判断 95% | identity 100/100 | 当前共同代码发送相对 0% 的 delta |
| Plane | 没有 Sensor 目标 95% 门槛；输入的是工作面 ON/OFF 与 Sensor ON/OFF | 当前使用两组 ON/OFF 差值计算灯光倍率，并用 OFF 比值计算环境倍率 | 当前共同代码发送相对 0% 的 delta |
| Night | 最终 Target Lux 由成对的目标亮度 Lux 减 0% Lux 后求得 | identity 100/100 | 当前共同代码发送相对 0% 的 delta |

由此可见，应明确区分：

1. 目标值或达标门槛；
2. Plane 的空间映射倍率；
3. 固件 `0x38` 灯光曲线坐标。

三者都可能看到 ON/OFF 数据，但用途不同。

## Sensor Cal.：本 Log 应如何判断

本轮参数：

- Target：295 lx；
- 95% 下限：281 lx；
- 100% 稳定 OnLux：295 lx；
- 0% 稳定 OffLux：46 lx。

Sensor 正确判断只需要：

`295 >= 281`

结果应为通过。当前实现继续计算 `295 - 46 = 249` 并以 `249 < 281` 触发 `sensorDarkCapacityInsufficient`，明确违反已确认的 Sensor 产品规则。

Sensor 的 0% Lux 不应参与：

- 目标 95% 下限判断；
- “暗环境能力”硬失败；
- 以灯具独立贡献代替满亮绝对值。

## Night Cal.：唯一用差值生成 Target 的模式

Night 会在 0% 和用户选择的目标亮度之间进行多组成对采样。每组计算：

`targetBrightnessLux - offLux`

只有每组差值为正、达到最小有效变化且多组差值稳定时，才对差值求平均形成 Night Target Lux。这正是需要排除环境底光的场景，也是“只有 Night 的最终 Target 需要 OnLux - OffLux”的准确含义。

这条逻辑不应因 Sensor 修复而调整。

## Plane Cal.：为什么源码仍然存在差值

Plane 没有 Sensor 模式的目标可达性判断，但当前倍率模型把环境底光和灯具贡献分成两个分量：

- 工作面灯光增量：`ambientLightOnLux - ambientLightOffLux`；
- Sensor 灯光增量：`sensorOnLux - sensorOffLux`；
- Sensor Rate：工作面灯光增量除以 Sensor 灯光增量；
- Ambient Light Rate：工作面 OffLux 除以 Sensor OffLux。

这里使用 ON/OFF 差值，是为了只映射灯具造成的变化，并让环境底光由独立的 Ambient Light Rate 处理。它不是用差值生成 Plane Target，也不是 Sensor 的 95% 门槛。

因此，对“Plane Cal. 也不需要减 0% Lux 吗”的回答必须分语境：

- 目标达标判断：对，Plane 没有这类减法门槛；
- 当前完整倍率数学：不对，Plane 明确使用 ON/OFF 差值计算 Sensor Rate。

如果产品要求 Plane 的倍率也完全禁止减 OffLux，就不再是 Sensor 阈值修复，而是对 Plane 两分量校准模型的变更，需要重新确认 `0x39` firmware 公式和外部照度计验收数据。

## `0x38` 曲线的独立歧义

当前 Manager 对 Plane、Sensor、Night 共用同一段 `0x38` 生成代码，发送：

- `minLux = inflectionLux - offLux`；
- `maxLux = onLux - offLux`。

但仓库内协议资料只把字段称为“步骤0照度、步骤1照度”，没有写明是绝对值还是 delta；SDK 枚举注释又把它们描述为未受灯影响时和最高亮度时的 Sensor Lux，更接近绝对值表述。当前资料之间并不充分一致。

因此不能把“Sensor 目标判断不减 0%”直接外推成“立即把三种模式的 `0x38` 全改成绝对 Lux”。如果最新 firmware 定义明确规定只有 Night 的 `0x38` 使用 delta，而 Sensor/Plane 使用绝对值，则当前共同代码还有第二个独立缺陷；实施前需要以 firmware 协议定义或设备团队确认作为依据。

## 建议的修复边界

按目前已经无歧义的产品规则，Sensor 本次失败的最小修复范围应为：

1. Sensor 目标可达性函数不再接收或使用 OffLux；
2. 只判断 100% 稳定 OnLux 是否达到 Target 的 95%；
3. 删除 `sensorDarkCapacityInsufficient` 失败分支及相应测试、文案和日志；
4. 保持 Night 成对 `OnLux - OffLux` 的 Target 生成逻辑不变；
5. Plane `0x39` 倍率和共同 `0x38` 先不随该修复改动，分别等待协议语义确认。

本轮只完成语义澄清和文档修正，未修改 App 或 SDK 业务代码。
