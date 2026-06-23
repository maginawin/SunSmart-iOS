# ZLL Controller Sensor 图标命名更新方案

## 背景

CIP `0x0A78`、PID `0x2132` 设备配置已更新为：

- `categoryName`: `ZLLC Controller`
- `elementCount`: `2`
- `iconCategory`: `ZLLControllerSensor`
- `deviceCategory`: `Lighting`
- `modelName`: `SR-BL2421-SSVT—AUXRJ45`

同时新增并统一了离线图片资源命名：

- 在线 / 添加设备图标：`device_ZLLControllerSensor`
- ZLL Controller Sensor 离线图标：`device_offline_ZLLControllerSensor`
- AC Power Switch 离线图标：`device_offline_ACPowerSwitch`

## 当前代码事实

`MeshDeviceConfigInfo.iconName` 的默认规则是：

- `device_\(iconCategory)`

因此 `iconCategory = ZLLControllerSensor` 会自然解析到 `device_ZLLControllerSensor`。

`MeshDeviceConfigInfo.offlineIconName` 的默认规则是：

- `device_offline_\(iconCategory)`

因此 `ZLLControllerSensor` 在新资源命名下不需要新增特例，会自然解析到 `device_offline_ZLLControllerSensor`。

当前仍存在一个历史特例：`ACPowerSwitch` 离线图标被返回为旧资源名 `device_ACPowerSwitch_offline`。资源重命名后，这个特例会导致 AC Power Switch 离线图标不再命中新资源。

此外，`PJEightKeySwitchData.swift` 中也存在同样的旧资源名硬编码。

## 推荐方案

采用统一命名规则方案：

1. 保留 `SunSmart/devices_config.json` 中 `0x0A78 / 0x2132` 的 `iconCategory = ZLLControllerSensor` 和 `deviceCategory = Lighting`。
2. 不为 `ZLLControllerSensor` 新增离线图标特例，让它直接走 `device_offline_\(iconCategory)` 默认规则。
3. 移除 `MeshDeviceConfigInfo.offlineIconName` 中 `ACPowerSwitch` 的旧特例，使 AC Power Switch 也走默认规则并解析到 `device_offline_ACPowerSwitch`。
4. 同步修改 `PJEightKeySwitchData.swift` 中 AC Power Switch 离线图标硬编码为 `device_offline_ACPowerSwitch`。

## 不在本次范围内

- 不新增 `Node.DeviceType`。`deviceCategory = Lighting` 已归类为 `.light`。
- 不修改添加设备、设备列表、重置设备等入口逻辑。现有入口已经通过 `info.iconName` 或 `node.iconName` 使用配置驱动图标。
- 不新增国际化文案。本次没有新增用户可见文本。
- 不调整 SDK 或协议逻辑。本次只涉及 App 资源命名与图标解析。

## 验证方案

实施后执行：

1. 使用 `jq empty` 校验 `SunSmart/devices_config.json` 及相关 asset `Contents.json`。
2. 静态确认以下资源存在：
   - `SunSmart/Assets.xcassets/Device/device_ZLLControllerSensor.imageset`
   - `SunSmart/Assets.xcassets/Device/device_offline_ZLLControllerSensor.imageset`
   - `SunSmart/Assets.xcassets/Device/device_offline_ACPowerSwitch.imageset`
3. 使用 `rg` 确认旧资源名 `device_ACPowerSwitch_offline` 和 `ZLLControllerSensor_offline` 不再被代码引用。
4. 执行 `git diff --check`。
5. 执行 iPhoneOS 构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
