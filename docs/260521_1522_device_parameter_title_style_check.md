# Device Parameter Settings 标题样式检查

## 背景

用户要求检查 `Site - Space - More` 的 `Device Parameter Settings` 页面中以下可配置属性标题是否与 `Rated power:` 的标题文字样式一致，并修复差异：

- `Absolute Sensitivity:`
- `Transition Time:`

## 对比基准

`Rated power:` 在 `DeviceParameterRetedPowerViewCell` 中的标题初始化为：

- 颜色：`TextBlack_Color`
- 字号：`14`
- 默认字重：未显式传入，使用项目 `UILabel` 便捷初始化的默认字重
- 初始 top 约束：`SCRYFrom(16)`

## 发现

`Absolute Sensitivity:` 使用 `DeviceParameterAbsoluteSensitivityViewCell`，标题初始化与基准存在差异：

- 颜色为 `ImportantText_Color`，不同于 `Rated power:` 的 `TextBlack_Color`
- 字号为 `14`，与 `Rated power:` 相同
- 默认字重未显式传入，与 `Rated power:` 相同
- 初始 top 约束为 `SCRYFrom(24)`，不同于 `Rated power:` 的 `SCRYFrom(16)`

`Transition Time:` 使用 `DeviceParameterSliderViewCell`，标题由控制器配置为 `transition_time`，但标题 label 的初始化与基准存在差异：

- 颜色为 `ImportantText_Color`，不同于 `Rated power:` 的 `TextBlack_Color`
- 字号为 `14`，与 `Rated power:` 相同
- 默认字重未显式传入，与 `Rated power:` 相同
- 初始 top 约束为 `SCRYFrom(24)`，不同于 `Rated power:` 的 `SCRYFrom(16)`

## 修复

- 将 `DeviceParameterAbsoluteSensitivityViewCell` 的标题颜色改为 `TextBlack_Color`，初始 top 改为 `SCRYFrom(16)`
- 将 `DeviceParameterSliderViewCell` 的标题颜色改为 `TextBlack_Color`，初始 top 改为 `SCRYFrom(16)`

## 验证项

- 静态检查旧的 `ImportantText_Color` 标题初始化不再存在
- 静态检查两个目标 cell 的标题初始化改为 `TextBlack_Color`
- 执行 SunSmart iOS 真机 Debug 构建验证
