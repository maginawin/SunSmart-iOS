# HDB Lighting Configuration 的 Mesh 数值换算

日期：2026-10-24

当前 App 有 **5 个属性需要数值换算**：2 个亮度百分比、3 个时间值。配置保存业务值，生成 Mesh 消息时才转换；页面 Set 与设备初始化／恢复同步复用同一套规则。以下说明当前 App 和本机 SDK 的实现，不代表设备实测结果。

## 1. 需要换算的属性

| 属性 | App 配置值及允许范围 | Mesh Property ID | 下发换算 | 示例 |
|---|---|---|---|---|
| `DimIntensity` | 整数百分比，0～50% | `0x002F` | 百分比 ÷ 100 × 65535，截去小数 | 20% → 13107 |
| `BrightIntensity` | 整数百分比，50～100% | `0x002E` | 百分比 ÷ 100 × 65535，截去小数 | 80% → 52428 |
| `RampUpTime` | 整数秒，1～3 秒 | `0x0037` | 秒 × 1000 | 1 秒 → 1000 |
| `RampDownTime` | 整数秒，1～3 秒 | `0x0036` | 秒 × 1000 | 2 秒 → 2000 |
| `HoldTime` | 整数秒，5～3600 秒 | `0x003C` | 秒 × 1000 | 30 秒 → 30000 |

这 5 项均通过 `LightLCPropertySet` 下发至 Light LC Setup Server（`0x1310`）。字段未设置时，不生成该字段的写命令。

### 亮度

App 实际算法为 `UInt32(Double(value) / 100 * 65535)`，非负输入截去小数，再由 SDK 按 2 字节 `Perceived Lightness` 编码。

| 配置百分比 | 下发原始值 |
|---|---|
| 0% | 0 |
| 5% | 3276 |
| 20% | 13107 |
| 50% | 32767 |
| 80% | 52428 |
| 100% | 65535 |

表中示例仍须遵守各字段的允许范围，例如 `DimIntensity` 不允许设置为 80%。

### 时间

App 实际算法为 `UInt32(value * 1000)`，将整数秒转换为毫秒，再由 SDK 按 3 字节 `Time Millisecond 24` 编码。例如 `HoldTime = 3600` 秒，下发值为 `3600000` 毫秒。

## 2. 其他属性

`LightingControl` 是选项到命令的映射：

| 配置选项 | 实际命令与参数 |
|---|---|
| `Auto` | `LightLCLightOnOffSet(true)` |
| `Force_On` | `LightLightnessSet(65535)`，请求 100% 亮度 |
| `Force_Off` | `GenericOnOffSet(false)` |

`FailsafeDelay` 和 `InstallDate` 当前仅保存配置，不发送 Mesh 消息，因此没有下发换算。`FailsafeDelay` 不会在此路径转换为设备的超时参数。

## 3. 读回显示

- `DimIntensity`、`BrightIntensity`：`Int((Double(raw) / 65535 * 100).rounded())`，换算为整数百分比，读回显示采用四舍五入。
- `RampUpTime`、`RampDownTime`、`HoldTime`：`Double(raw) / 1000`，换算为秒，可显示小数。

实现依据：[HDBLightingConfigurationPolicy.swift](../SunSmart/Common/Data/HDBLightingConfigurationPolicy.swift) 的 `writes`，以及 [HDBLightingMessages.swift](../SunSmart/Main/Space/HDB/Model/HDBLightingMessages.swift) 的 `message`、`observation`。
