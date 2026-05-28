# Real Power Switch Icon Fix

## 背景

测试发现真实 AC Power Switch 绑定后仍会显示 8-key 组合状态图，而不是设备类型图标。期望：

- AC Power Switch 显示 `device_ACPowerSwitch`
- Battery Power Switch 显示 `device_BatteryPowerSwitch`
- 虚拟与真实 Power Switch 保持一致，不再根据绑定/同步状态切换为组合图标

## 根因

`PJEightKeySwitchData.displayIconAssetName` 之前在设备已绑定时使用 `displayStatus.iconAssetName`，导致真实 Power Switch 进入绑定态后显示 `eight_key_switch_*` 系列组合状态图。

## 修复

`displayIconAssetName` 统一返回 `powerSwitchKind.deviceIconAssetName`：

- `.ac` 返回 `device_ACPowerSwitch`
- `.battery` 返回 `device_BatteryPowerSwitch`

设备 cell 的默认图和资源缺失 fallback 也移除了 `eight_key_switch_*` 组合图，避免真实或虚拟 Power Switch 在复用/绑定态下短暂或异常显示组合图。

同步设备页此前已改为使用同一套 `powerSwitchKind.deviceIconAssetName`，因此虚拟列表、真实列表与同步页展示保持一致。

## 验证

- 静态检查 `displayIconAssetName` 不再引用 `displayStatus.iconAssetName`
- 运行 iOS 真机 generic build 验证编译
