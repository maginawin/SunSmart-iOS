# Brightness Trim Slider Analysis

## 结论

- 当前代码仍然有亮度范围限制能力，`CustomDeviceSlider.limitRange` 会 clamp 值，并在 `minimumValue...maximumValue` 外存在不可用区间时绘制灰色段。
- 当前设备控制页和组控页没有显示 0%-low-end trim、high-end trim-100% 的灰色禁用区域，原因是新 `DeviceLightControlPanelView` 把 slider 的 `minimumValue` / `maximumValue` 直接设置成了 trim range，导致总轨道范围和限制范围相同。
- 设备控制页的行为变化由 `357fe61d feat: add control type & quick buttons for device` 引入，最早包含在 tag `1.0.19.1`。
- 组控页的行为变化由 `9aeaa1e5 fix: respect change control page in group CCT display` 引入，最早包含在 tag `1.0.19.1`。

## 代码证据

- `SunSmart/Common/View/CustomDeviceSlider.swift`：
  - `value` getter/setter 会按 `limitRange` clamp。
  - `updateLimitUI()` 只有在 `maximumValue > limitRange.upperBound` 或 `minimumValue < limitRange.lowerBound` 时才绘制右/左灰色禁用段。
- `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift`：
  - `configureBrightnessSlider()` 当前设置：
    - `minimumValue = brightnessRange.lowerBound`
    - `maximumValue = brightnessRange.upperBound`
    - `limitRange = brightnessRange`
  - 因此即使传入 20...80，slider 总轨道也是 20...80，不再有 0...20 或 80...100 可画成灰色。
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`：
  - 当前设备页传入的是 `node.lightnessRange` 转换后的百分比范围。
  - 旧代码在 `357fe61d^` 中是 `BuoySliderView(.level())`，默认 0...100，总轨道不变，只设置 `lightnessSlider.slider.limitRange = node.lightnessRange`。
- `SunSmart/Main/Group/Controller/GroupViewController.swift`：
  - 当前组控页传入的是 `group.info.profile.lightControlData.lowEndTrim...highEndTrim`。
  - 旧代码在 `9aeaa1e5^` 中是 `BuoySliderView(.level())`，默认 0...100，总轨道不变，只设置 `lightnessSlider.slider.limitRange = data.lowEndTrim...data.highEndTrim`。

## Proximity/Predictive Lighting With Photocell

- 当前模型存在通用 `profile.lightControlData`，也存在 `dayData.sceneData.lightControlData` 和 `nightData.sceneData.lightControlData`。
- 但 High-end / Low-end trim 的编辑回调会把通用、day、night 三份 `LightControlData` 的 trim 一起改成同一个值。
- 导出 profile 顶层只写 `highEndTrim` / `lowEndTrim`；day/night 字段只写条件信息和 scene number。scene 内部的 light control 数据复用顶层 trim 初始化。
- 同步下发 `LightLightnessRangeSet` 时使用的是 `groupProfile.lightControlData.lowEndTrim...highEndTrim`，不是 day/night 当前条件各自的 trim。
- 因此旧 App 没有真正按 Proximity/Predictive lighting with photocell 的 day/night 两套 low-end trim / high-end trim 独立处理。

## 建议方案

### 方案 A：只恢复视觉与交互范围

- `DeviceLightControlPanelView` 保持现有传入 API。
- 亮度 slider 总范围固定为 0...100，`limitRange` 使用传入的 trim range。
- 输入弹窗和发送逻辑继续按当前 `currentBrightnessRange` clamp。
- 优点：改动最小，能恢复灰色禁用段和不可滑入禁用区的旧体验。
- 缺点：不解决 photocell day/night 双 trim 的模型语义。

### 方案 B：恢复灰段，并为 photocell 明确采用统一 effective trim

- 在方案 A 基础上，定义当前控制页和设备 lightness range 统一使用 profile 顶层 trim。
- Proximity/Predictive lighting with photocell 即使有 day/night scene，也不让实时控制页随 day/night 自动切换范围。
- 优点：与当前 sync 下发 `LightLightnessRangeSet` 的单一设备亮度范围一致，不会出现 day/night 切换后设备 range 与 UI 不一致。
- 缺点：不能表达产品上真正希望的 day/night 双 trim。

### 方案 C：完整支持 photocell day/night 双 trim

- 需要扩展数据保存、导入导出、Profile 编辑、sync 规划和控制页 effective range。
- 需要明确当前 active condition 是 day 还是 night，再决定组控页展示哪套 trim。
- 由于设备 `LightLightnessRangeSet` 是单一 lightness range，若 day/night 要不同范围，需要在条件切换时同步设备 range，或者改成只把 day/night trim 用于场景阶段值 clamp，不作为设备 lightness range。
- 优点：能完整表达两套 trim。
- 缺点：协议和状态切换成本高，容易引入 day/night 切换时 UI、设备 range、scene recall 不一致的问题。

## 推荐

先采用方案 B：恢复 0...100 总轨道与灰色禁用段，并明确 Proximity/Predictive lighting with photocell 的控制页使用 profile 顶层 effective trim。这样与当前设备 `LightLightnessRangeSet` 的单一 range 保持一致，风险最低。

如果后续产品要求 day/night 真正不同的 low/high trim，应先确认协议层是否允许在 day/night 条件切换时动态改设备 lightness range；否则不要把 day/night trim 解释成设备级可调范围。
