# Sensor Calibration 日志分析

## 结论

本轮 Sensor Cal. 的命令编码、目标地址、字段顺序和 ACK 均正常，未发现 ON/OFF 颠倒、UInt16 编码错误或下发到错误节点。

但业务数据存在明显风险：目标为 148 lx，而校准过程中同一传感器在灯光 100% 时只测得 132 lx。在环境底值仍为 71 lx 的前提下，灯光最大贡献为 61 lx，目标需要贡献 77 lx，当前灯具比目标少 16 lx。因此，在相同环境条件下，148 lx 不是本轮校准曲线可达到的目标。

## 日志解码

### 基本参数

| 参数 | 值 | 判定 |
| --- | ---: | --- |
| 模式 | Sensor | 正确 |
| Node / 目标地址 | `0x008F` / `0x008F` | 一致 |
| Dim level | 100% | SDK 仍会执行自身的 0% 至 100% 曲线采样 |
| Sensor OFF | 71 lx | 有效 |
| Sensor ON | 132 lx | 大于 OFF，有效 |
| 灯光最大增量 | 61 lx | `132 - 71`，计算正确 |
| Target | 148 lx | 高于当前 100% 实测值 16 lx |

### `0x38` payload

`3138FF3F0500FFFF3D00` 按当前 iOS 小端 UInt16 编码可还原为：

- `31 38`：Daylight Sensor / Calibration Inflection Point。
- `FF 3F`：`0x3FFF = 16383`，约为 25% lightness。
- `05 00`：最小拐点 Lux 增量 5。
- `FF FF`：`65535`，100% lightness。
- `3D 00`：最大 Lux 增量 61。

所有字段与结构化日志完全一致。25% 拐点表示 SDK 的 5% 步进搜索在约 25% 时确认灯光影响达到阈值；仅凭本组摘要日志无法看到 5%、10%、15%、20% 的原始采样，但 payload 本身没有异常。

### `0x39` payload

`313964006400` 可还原为：

- `31 39`：Daylight Sensor / Calibration Rate。
- `64 00`：Sensor Rate 100。
- `64 00`：Ambient Light Rate 100。

Sensor Cal. 按当前设计使用传感器自身 Lux 坐标，因此 100%/100% identity 倍率正确。`0x38`、`0x39` 都收到成功 ACK。

## 关键业务风险

App 当前只校验目标值位于 0 至 2500 lx，不会把 `targetLux` 传入 SDK，也不会在校准完成前将它与 `sensorOnLux` 比较。SDK 只负责生成传感器曲线和写入 identity 倍率；成功后 App 才把 148 保存到 Profile 的 `taskLevel` 或 `occupancyLevel`。

因此，本轮校准即使发现 `targetLux=148 > sensorOnLux=132`，仍会显示 SDK 校准成功。若运行环境仍接近 OFF 71 lx，灯具 100% 只能达到约 132 lx，闭环会长期顶在最大输出而无法达到 148 lx。外部日光后续升高时可能达到 148 lx，但这不能证明灯具在当前校准场景下具备达标能力。

如果 148 来自 `Use sensor reading`，它与随后 SDK 100% 稳定采样的 132 相差 16 lx，还需检查读取时刻、灯具是否已稳定到 100%、环境光变化及传感器上报波动；日志本身无法区分 148 是手动输入还是 `Use sensor reading` 得到的。

## ACK 边界

两个 ACK 仅证明传感器接受了 `0x38` 和 `0x39`。它们不证明：

- Profile 目标值已成功同步到全部灯具；
- Sensor Publication 与 Group Subscription 已全部成功；
- 固件读取回来的曲线与倍率等于写入值；
- 实际闭环能达到 148 lx。

需要结合后续 Configuring 结果、设备读回或抓包，以及 0%/100%/闭环稳定后的实测 Lux 才能完成真机判定。
