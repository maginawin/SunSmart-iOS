# Device Parameter Settings PID 差异分析

## 结论

`0x2304`、`0x2305` 在 `devices_config.json` 中与 `0x2302` 同为 `Driver Lighting`、同一 `modelName`，但参数页不按 `modelName` 判定，而是按 `Node` 的能力开关组装 UI。

修复前能力开关中：

- `0x2302`、`0x2303`、`0x2801`、`0x2802` 被判定为支持真实功率计量。
- `0x2304`、`0x2305` 未被判定为支持真实功率计量。
- `0x2302`、`0x2303`、`0x2801`、`0x2802` 被排除在 PWM Frequency 外。
- `0x2304`、`0x2305` 未被排除，因此会展示 PWM Frequency。

因此修复前 `0x2304`、`0x2305` 会走“手动 Rated Power 参数配置”路径，而 `0x2302` 会走“Energy Reporting / Activate / Inhibit”路径。这就是功率参数配置不一致的直接原因。

## 入口链路

用户路径：

`Site -> Space -> More -> Device Parameter Settings`

代码链路：

- `SpaceMoreViewController` 点击 `.deviceParameters` 后进入 `DeviceCategorysViewController`。
- `DeviceCategorysViewController` 按 `node.productIdentifier` 分组。
- 单个 PID 分组进入 `DeviceParameterDevicesViewController`。
- 选择设备后进入 `DeviceParameterSettingsController(devices:)`。

## 关键判定点

### 参数页 UI 组装

`DeviceParameterSettingsController.viewDidLoad` 中使用首个设备的能力开关决定页面内容：

- `node.supportRealPowerMetering == true`：展示 `energyReporting` section。
- `node.supportRealPowerMetering == false`：展示 `.ratedPower` 手动参数 cell。
- `node.supportPwmFrequency == true`：展示 `.pwmFrequency` 参数 cell。

对应代码：

- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift:109`
- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift:111`
- `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift:117`

### PID 能力开关

`supportRealPowerMetering` 目前只包含：

`0x2302, 0x2303, 0x2801, 0x2802`

`supportPwmFrequency` 排除列表目前只包含：

`0x0031, 0x0041, 0x0302, 0x0303, 0x1031, 0x1041, 0x1302, 0x1303, 0x2302, 0x2303, 0x2801, 0x2802`

对应代码：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2207`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2216`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2239`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2245`

### Energy Reporting 内部差异

`0x2801` 与 `0x2302` 都支持真实功率计量，但 `0x2801` 还支持真实功率校准：

- `supportRealPowerCalibration` 只包含 `0x2801, 0x2802`。
- 因此 `0x2801` 的 Energy Reporting 中会多一个 `Calibrate` 按钮。
- `0x2302` 不展示 `Calibrate`，只展示 `Inhibit All` / `Activate All`。

对应代码：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2252`
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2258`
- `SunSmart/Main/Device/Parameter/View/DeviceParameterEnergyReportViewCell.swift:48`

## 四个 PID 修复前行为对比

| PID | `supportRealPowerMetering` | `supportRealPowerCalibration` | `supportPwmFrequency` | 页面/流程表现 |
| --- | --- | --- | --- | --- |
| `0x2302` | true | false | false | Energy Reporting；无 PWM；无 Calibrate |
| `0x2801` | true | true | false | Energy Reporting；无 PWM；有 Calibrate |
| `0x2304` | false | false | true | 手动 Rated Power 参数；有 PWM |
| `0x2305` | false | false | true | 手动 Rated Power 参数；有 PWM |

## 根因假设

`0x2304`、`0x2305` 是后来加入 `devices_config.json` 的同型号 PID，但没有同步加入 `MeshNetwork+SunSmart.swift` 中与 `0x2302` 对应的能力判定列表，导致 Device Parameter Settings 走错 UI/流程。

这不是 `devices_config.json` 展示信息的问题，而是运行时能力判定遗漏。

## 已实施修复点

已确认产品预期是 `0x2304`、`0x2305` 与 `0x2302` 完全一致：

- 已在 `supportRealPowerMetering` 中加入 `0x2304, 0x2305`。
- 已在 `supportPwmFrequency` 排除列表中加入 `0x2304, 0x2305`。
- 不要加入 `supportRealPowerCalibration`，除非产品确认这两个 PID 也应支持校准。按“与 `0x2302` 相同”的预期，它们不应显示 `Calibrate`。

修复后：

| PID | 页面/流程 |
| --- | --- |
| `0x2304` | 与 `0x2302` 一致：Energy Reporting；无 PWM；无 Calibrate |
| `0x2305` | 与 `0x2302` 一致：Energy Reporting；无 PWM；无 Calibrate |

## 需要同步关注

- 读取参数时 `DeviceParameterDevicesViewController.readAction` 总会读取 `.ratedPower`，并按 `supportPwmFrequency` 决定是否读取 PWM；修复后 `0x2304/0x2305` 将不再读取 PWM。
- 设置功率时真实功率计量路径会使用 `ReadDevicesDataViewController(type: .readRatedPower)` 里的 `.autoSetRatedPower`，该逻辑发送 `SunricherVendorSet(function: .ratedPower(pid: pid))`，会使用当前设备自身 PID。
- 如果固件侧 `0x2304/0x2305` 的自动功率设置命令也应与 `0x2302` 相同，需要确认 `SunricherVendorSet(function: .ratedPower(pid:))` 内部是否已支持这两个 PID。
