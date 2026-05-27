# Kinetic Switch 与 Battery Power Switch 设备图片分析

## 结论

Kinetic switch 与 Battery Power Switch 在“选择开关类型”入口使用各自独立图片；进入 8-key switch 数据模型后的列表、状态、面板预览和按键提示多数共享同一套图片。

Battery Power Switch 作为真实 Mesh 设备节点时，另外通过 `devices_config.json` 的 `iconCategory = BatteryPowerSwitch` 解析出独立设备图 `device_BatteryPowerSwitch`。

## 单独使用的图片

### Kinetic switch 单独使用

- `Kinetics_device`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/Kinetics_device.imageset`
  - 文件：`Kinetics_device@2x.png`、`Kinetics_device@3x.png`
  - 用途：`PJSwitchesTypesViewModel` 中开关类型选择页的 Kinetic switch 入口图片。

### Battery Power Switch 单独使用

- `BatteryPowersw_device`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/BatteryPowersw_device.imageset`
  - 文件：`BatteryPowersw_device@2x.png`、`BatteryPowersw_device@3x.png`
  - 用途：`PJSwitchesTypesViewModel` 中开关类型选择页的 Battery Power Switch 入口图片。

- `device_BatteryPowerSwitch`
  - 资源路径：`SunSmart/Assets.xcassets/Device/device_BatteryPowerSwitch.imageset`
  - 文件：`device_battery_power_switch.png`、`device_battery_power_switch@2x.png`、`device_battery_power_switch@3x.png`
  - 来源：`devices_config.json` 中 PID `0x2A01` / `0x2A02` 的 `iconCategory` 为 `BatteryPowerSwitch`，`MeshDeviceConfigInfo.iconName` 会拼成 `device_BatteryPowerSwitch`。
  - 用途：真实 Battery Power Switch 节点的设备图标；`SyncDevicesViewController.appendBatteryPowerSwitchItems` 同步页也优先使用 `switchNode.iconName`，失败时 fallback 到 `device_BatteryPowerSwitch`。

- `battery_ek`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/battery_ek.imageset`
  - 文件：`battery_ek@2x.png`、`battery_ek@3x.png`
  - 用途：Battery Power Switch 详情头部电量图标。代码里只有 battery layout 使用它；AC header 不显示该图标，Kinetic switch 也没有电量来源。

## 共享使用的图片

这些图片由 `PJEightKeySwitchData` / `PJEightKeySwitchStatus` / `PJEightKeySwitchPanelDefinition` 驱动，不按 Kinetic 或 Battery Power Switch 分支区分。

- `eight_key_switch_bound_enabled`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/eight_key_switch_bound_enabled.imageset`
  - 文件：`eight_key_switch_bound_enabled@2x.png`、`eight_key_switch_bound_enabled@3x.png`
  - 用途：8-key switch 列表默认、已绑定、未绑定、禁用等状态图标；Kinetic 与 Battery Power Switch 都会走 `displayStatus.iconAssetName`。

- `eight_key_switch_sync_issue`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/eight_key_switch_sync_issue.imageset`
  - 文件：`eight_key_switch_sync_issue@2x.png`、`eight_key_switch_sync_issue@3x.png`
  - 用途：绑定开关存在同步问题时的列表状态图标；Kinetic 使用 `needSyncData`，Battery/AC Power Switch 使用 `needsBatteryPowerSwitchSync`。

- `eight_key_switch_repair_required`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/eight_key_switch_repair_required.imageset`
  - 文件：`eight_key_switch_repair_required@2x.png`、`eight_key_switch_repair_required@3x.png`
  - 用途：绑定节点 key bind 不完整时的列表状态图标，Kinetic 与 Battery Power Switch 共用。

- `Scene Panel (8 key)`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/Scene Panel (8 key).imageset`
  - 用途：8-key scene panel 预览图，按 `PJEightKeySwitchData.eightKeyPanelType` 决定，与开关来源无关。

- `Brightness Panel (8 key)`
  - 资源路径：`SunSmart/Assets.xcassets/EightKeySwitches1.5/Brightness Panel (8 key).imageset`
  - 用途：8-key brightness panel 预览图，按 `PJEightKeySwitchData.eightKeyPanelType` 决定，与开关来源无关。

- `switch_press` / `switch_press_long`
  - 资源路径：`SunSmart/Assets.xcassets/Group/switch_press.imageset`、`SunSmart/Assets.xcassets/Group/switch_press_long.imageset`
  - 用途：8-key panel 上短按/长按动作提示图标，Kinetic 与 Battery Power Switch 共用。

## 兼容旧开关页面的共享图片

旧的 `DeviceSwitchesViewCell` 仍使用：

- `device_switch`
- `sync_failed_big`

这套逻辑属于旧 `DeviceSwitchData` 列表显示，不区分 Kinetic switch 与 Battery Power Switch 的 1.5 入口图片；当前 8-key switch 列表使用的是 `PJEightKeySwitchesViewCell` 与 `PJEightKeySwitchStatus` 的 `eight_key_switch_*` 图片。

## 关键代码位置

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJSwitchesTypesViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchesViewCell.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchStatus.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchPanelDefinition.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`
- `SunSmart/Common/Mesh/Device/MeshDeviceConfigInfo.swift`
- `SunSmart/devices_config.json`
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
