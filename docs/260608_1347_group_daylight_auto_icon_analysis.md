# Group daylight profile Sensor 行 A 图标展示逻辑分析

## 结论

Group 页面底部 Sensor 行中，位于光照度图标左侧的 A 图标来自 `GroupSensorView.controlStateImageView`，资源名是 `group_auto`。

它不是仅由 profile 类型决定展示。实际展示需要同时满足：

1. 当前 group 的 profile 是 `Daylight harvesting (Closed loop)`，即 `ProfileType.daylight`。
2. group 已绑定一个 daylight/ambient light sensor：`group.info.ambientLightSensorNode != nil`。
3. 绑定的 daylight sensor 有 `lightLCModel`，页面能发送 `LightLCLightOnOffGet` 查询其 Light LC OnOff 状态。
4. 收到 `LightLCLightOnOffStatus` 后，`isOn == true`，写入 `sensorNode.lightControlOn = true`。
5. `updataSensorAutoStateUI()` 根据 `group.info.ambientLightSensorNode?.lightControlOn == true` 显示 A 图标。

因此，在以下三个 profile 中：

- `Occupancy sensing with daylight harvesting` (`.occupancy_daylight`)
- `Vacancy sensing with daylight harvesting` (`.vacancy_daylight`)
- `Daylight harvesting (Closed loop)` (`.daylight`)

只有 `.daylight` profile 会通过 `updataSensorAutoStateUI()` 显示这个 Sensor 行 A 图标；`.occupancy_daylight` 和 `.vacancy_daylight` 会被强制隐藏。

## 代码路径

- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `updateUI()`：按 profile 决定 Sensor 行支持类型：
    - `.occupancy_daylight` / `.vacancy_daylight`：`supportSensorType = .all`
    - `.daylight`：`supportSensorType = .ambientLight`
  - `refreshAutoState()`：如果存在 `group.info.ambientLightSensorNode` 和 `sensor.lightLCModel`，发送 `LightLCLightOnOffGet()`。
  - `didReceiveMessage`：收到 `LightLCLightOnOffStatus` 后把 `sensorNode.lightControlOn` 更新为 `lightOnOffStatus.isOn`，再调用 `updataSensorAutoStateUI()`。
  - `updataSensorAutoStateUI()`：仅当 `group.info.profile.type == .daylight` 时，根据绑定光照传感器的 `lightControlOn` 控制 A 图标显隐；其他 profile 一律隐藏。

- `SunSmart/Main/Group/View/GroupSensorView.swift`
  - `controlStateImageView = UIImageView(image: UIImage(named: "group_auto")?.withTintColor(.black))`
  - 约束位置：`right == lightImageView.left - 16`，所以视觉上在光照度图标左侧。
  - `supportSensorType` 每次变化时先执行 `controlStateImageView.isHidden = true`。
  - `sensors` 设置时，如果存在已上报、已校准、在线的光照传感器，会按该 sensor 的 `lightControlOn` 做一次局部刷新；但 `GroupViewController.updateUI()` 随后设置 `supportSensorType` 会先隐藏该图标，后续最终显隐以 `updataSensorAutoStateUI()` 为准。

## 与 lux 展示的关系

光照度数值本身要求找到一个 `ambientLightSensorModel?.publish != nil && sensorCalibrated && steadyDaylightLux != nil && state == true` 的光照传感器，才会显示类似 `123lx`。

A 图标的最终显示不直接依赖 lux 文本是否显示。它依赖的是绑定 daylight sensor 的 `LightLCLightOnOffStatus.isOn`。也就是说，A 表示当前 daylight Light LC 控制处于 On/Auto 状态，而不是单纯表示“当前 profile 是 daylight harvesting”或“当前有 lux 值”。

## 补充说明

页面底部主控制区还有一个独立的 `autoBtn`，资源是 `auto` / `auto_big`，点击后发送 `LightLCLightOnOffSetUnacknowledged(true)`。它和 Sensor 行内部的 `group_auto` A 状态图标不是同一个 UI。
