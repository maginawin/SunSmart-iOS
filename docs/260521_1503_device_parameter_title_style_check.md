# Device Parameter Title Style Check

## 范围

检查 `Site - Space - More - Device Parameter Settings` 中以下标题是否与 `Rated power` 一致：

- `Change Control Page:`
- `Absolute CCT Range:`

## 对比结果

`Rated power` 标题定义在 `DeviceParameterRetedPowerViewCell`：

- textColor: `TextBlack_Color`
- fontSize: `14`
- fontWeight: 默认
- left: `SCRXFrom(16)`
- 初始 top: `SCRYFrom(16)`
- 启用后 top: `SCRYFrom(24)`
- 禁用后 top: `SCRYFrom(24)`，bottom: `SCRYFrom(-23)`

`Change Control Page` 和 `Absolute CCT Range` 的标题样式属性中，颜色、字号、字重、left、启用布局和禁用布局都与 `Rated power` 一致。

发现的不一致：

- 两个新增标题在 `setupUI()` 初始约束中使用 `SCRYFrom(24)`。
- `Rated power` 在 `setupUI()` 初始约束中使用 `SCRYFrom(16)`。

虽然运行时 `configure/updateParameterEnable` 会重新设置启用或禁用布局，但初始约束仍属于代码层面的不一致。

## 修复

已将以下两个标题的初始 top 约束改为 `SCRYFrom(16)`，与 `Rated power` 保持一致：

- `DeviceParameterChangeControlPageViewCell.titleLabel`
- `DeviceParameterAbsoluteCctRangeViewCell.titleLabel`
