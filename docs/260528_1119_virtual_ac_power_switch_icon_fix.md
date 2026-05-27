# Virtual AC Power Switch Icon Fix

## 问题

测试发现添加虚拟 AC Power Switch 后，设备图标预期为 `device_ACPowerSwitch`，实际显示为 `device_BatteryPowerSwitch`。

## 根因

Power Switch 的显示逻辑没有统一从 `PJEightKeyPowerSwitchKind` 解析设备图标：

- 未绑定的虚拟 Power Switch 列表图标仍走通用状态图标逻辑，无法表达 AC/Battery 类型。
- Battery/AC Power Switch 同步页的 switch 本体行 fallback 固定写成 `device_BatteryPowerSwitch`，AC 场景会被误判为 Battery 图标。

## 修复

- 在 `PJEightKeyPowerSwitchKind` 增加统一图标映射：
  - `.battery` -> `device_BatteryPowerSwitch`
  - `.ac` -> `device_ACPowerSwitch`
- 未绑定的虚拟 Power Switch 列表图标改为使用 `powerSwitchKind.deviceIconAssetName`。
- `SyncDevicesViewController` 的 Power Switch 本体行改为优先使用 `switchData.powerSwitchKind.deviceIconAssetName`，避免 AC 落到 Battery fallback。

## 验证

- 静态检查确认 `PJEightKeySwitchData` 已包含 `device_ACPowerSwitch` 映射。
- 静态检查确认 `SyncDevicesViewController` 不再存在固定 fallback 到 `device_BatteryPowerSwitch` 的逻辑。
- 已运行：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

结果：构建成功。
