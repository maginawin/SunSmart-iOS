# AC Power Switch Offline Icon Fix

## 背景

AC Power Switch 是常电设备，应像 light 等真实 Mesh 节点一样，在离线时显示单独离线图标。Battery Power Switch 不需要离线图标。

## 实现

- 保持 `devices_config.json` 中 AC Power Switch 的 `iconCategory` 为 `ACPowerSwitch`。
- 在线真实 Mesh 节点图标继续由默认规则解析为 `device_ACPowerSwitch`。
- 在 `MeshDeviceConfigInfo.offlineIconName` 中为 `ACPowerSwitch` 增加特例，返回 `device_ACPowerSwitch_offline`。
- Battery Power Switch 保持默认规则，不新增离线图标特例。

## 验证

- 静态确认 AC Power Switch PID `0x2A11` / `0x2A12` 仍使用 `iconCategory: "ACPowerSwitch"`。
- 静态确认项目存在 `device_ACPowerSwitch.imageset` 和 `device_ACPowerSwitch_offline.imageset`，不存在 `device_offline_BatteryPowerSwitch.imageset`。
- 已运行：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

结果：构建成功。
