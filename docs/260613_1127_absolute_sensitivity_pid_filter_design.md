# Absolute Sensitivity PID 过滤设计

## 背景

在 Site - Space - More - Device Parameter Settings 中，Absolute Sensitivity 目前通过 `Node.supportMotionSensitivity` 判断是否支持。该判断只检查设备是否存在 Sunricher vendor model 和 presence detected sensor model，没有排除指定的 `0x0A78` PID。

因此，当指定 PID 的设备运行时带有 presence detected sensor model 时，Absolute Sensitivity 仍可能出现在：

- `1.Select the device to be set up` 设备列表行
- Filter 弹窗的 Absolute Sensitivity 过滤项
- Next 后的 `2.Parameter selection` 功能模块

## 已确认规则

当设备的 CIP 是 `0x0A78`，且 PID 属于以下列表时，设备不支持 Absolute Sensitivity：

- `0x2121`
- `0x2122`
- `0x2131`
- `0x2132`
- `0x2133`
- `0x2491`
- `0x2492`
- `0x2493`
- `0x2494`

该规则只作用于 `0x0A78` 厂商设备。其它厂商即使 PID 数值相同，也不受影响。

## 当前代码分析

当前 `Node.supportMotionSensitivity` 位于 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`。它的现有逻辑是：

- 没有 Sunricher vendor model 时返回不支持
- 有 presence detected sensor model 时返回支持

Device Parameter Settings 的相关入口都复用或间接复用该能力判断：

- `DeviceParameterDeviceCell` 使用 `device.supportMotionSensitivity` 决定设备列表行是否显示 Absolute Sensitivity
- `DeviceParameterDevicesViewController.nodeSupportsFilter(_:type:)` 使用 `node.supportMotionSensitivity` 决定 Filter 是否包含 Absolute Sensitivity
- `DeviceParameterSettingsController` 使用首个选中设备的 `supportMotionSensitivity` 决定 Next 后是否添加 `.motionSensitivityRange` 参数模块

本地 `devices_config.json` 当前能找到 `0x2121`、`0x2131`、`0x2132`、`0x2491`，但这些 PID 没有被现有能力判断排除。`0x2122`、`0x2133`、`0x2492`、`0x2493`、`0x2494` 当前未在本地配置文件中出现，但设备配置可能来自云端或后续更新，仍需要在运行时能力判断中覆盖。

## 方案选择

采用方案 A：在 `Node.supportMotionSensitivity` 中统一收口 PID 黑名单判断。

不采用只在 Device Parameter Settings 页面局部过滤的方案，因为它会让其它同步、读取或恢复路径继续认为设备支持该能力，后续容易出现入口不一致。

不采用修改 `devices_config.json` 的方案，因为当前问题不是配置范围字段导致的，并且部分 PID 不在本地 JSON 中，云端配置也可能覆盖本地数据。

## 设计

在 `Node.supportMotionSensitivity` 中增加一个 `0x0A78` + PID 黑名单判断：

- 如果 `companyIdentifier == 0x0A78`
- 且 `productIdentifier` 属于已确认黑名单
- 则返回不支持 Absolute Sensitivity

其余设备保持现有逻辑：仍要求 Sunricher vendor model 存在，并要求 presence detected sensor model 存在。

建议将黑名单封装为 `Node` 扩展内部的私有静态集合或私有辅助判断，避免在多个 UI 控制器重复散落 PID 判断。

## 预期效果

修复后，黑名单设备在 Device Parameter Settings 中会统一表现为不支持 Absolute Sensitivity：

- 设备列表页不显示 Absolute Sensitivity 行
- Filter 弹窗不显示 Absolute Sensitivity 选项
- Next 后的 Parameter selection 不显示 Absolute Sensitivity 模块

其它厂商、其它 PID、以及原本支持 Absolute Sensitivity 的设备不改变。

## 验证

静态验证：

- 确认 `supportMotionSensitivity` 已包含 `0x0A78` + PID 黑名单排除
- 确认 Device Parameter Settings 三处入口仍走该共享能力判断

构建验证：

- 运行 iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险与边界

- 该改动会影响所有调用 `supportMotionSensitivity` 的路径，不仅限于 Device Parameter Settings。这是预期行为，因为这些 PID 的设备本身被定义为不支持 Absolute Sensitivity。
- 不修改本地化、资源、target 配置或依赖。
- 不改变 Relative Sensitivity、Profile Sensitivity、Calibration 等其它功能判断。
