# Brightness Off Value Label Design

## 背景

上一次修复后，亮度 slider 的总轨道恢复为 0...100，`limitRange` 继续使用 low-end trim / high-end trim，因此 slider 两端能显示灰色禁用区域。

新的问题是：当设备或组处于 Off 状态时，调用方会传入亮度值 0，但 `DeviceLightControlPanelView` 内部会按 `brightnessRange` clamp，导致右上角 brightness value label 显示 low-end trim，而不是 0%。

## 目标

- 灯 Off 时，on/off 按钮上方亮度状态显示 0%，slider 右上角 brightness value label 也显示 0%。
- 组 Off 时，slider 右上角 brightness value label 也显示 0%。
- 灯或组 On 时，继续按现有逻辑显示实际亮度百分比。
- slider 本身仍不能滑入 low-end trim 以下或 high-end trim 以上的灰色禁用区。

## 非目标

- 不修改 Profile 的 low-end trim / high-end trim 数据模型。
- 不修改 group profile sync、`LightLightnessRangeSet` 或任何 mesh 命令。
- 不修改 CCT slider 或 CCT value label。

## 方案

采用方案 A：在 `DeviceLightControlPanelView` 内区分“展示亮度值”和“slider 可交互值”。

- `brightnessValue == 0` 作为 Off 状态展示特例保留。
- slider 的实际 `value` 继续交给 `CustomDeviceSlider.limitRange` clamp，因此 Off 时 thumb 会停在 low-end trim 位置。
- detailed mode 右上角 brightness value label 使用展示亮度值；Off 时显示 `0%`。
- 用户拖动 slider 时，回调 value 仍来自 slider 的可交互值，因此 On 后行为保持当前逻辑。

## 数据流

- `DeviceLightViewController.updateControlPanel()` 继续传入 `Node.getLightness100(lightness: node.lightness)`；Off 时为 0。
- `GroupViewController.updateControlPanel()` 继续在 `group.isOn == false` 时传入 0。
- `GroupViewController.onoffBtnClick()` 继续调用 `controlPanelView.setBrightnessValue(0)`。
- `DeviceLightControlPanelView` 内部保存的 `configuration.brightnessValue` 允许为 0，但 slider value 仍由 `limitRange` clamp。

## 测试与验证

- 用 source check 先确认当前实现会把 `brightnessValue` clamp 到 `brightnessRange.lowerBound`。
- 修改后确认存在 shared helper，允许 0 并 clamp 非 0 值。
- 运行 `git diff --check`。
- 运行 iPhoneOS workspace build：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
