# Absolute CCT Range Reset 按钮样式检查

## 背景

用户要求在 `Site - Space - More` 的 `Device Parameter Settings` 页面中：

- 确定启用 `Transition Time:` 后展示的 `Reset` 按钮样式 A
- 将启用 `Absolute CCT Range:` 后展示的 `Reset` 按钮样式改成样式 A

## 样式 A

`Transition Time:` 使用 `DeviceParameterSliderViewCell`，启用后展示的 `Reset` 按钮样式为：

- 标题：`reset`
- 字号：`14`
- 字重：`.light`
- 标题颜色：`Bar_Color`
- 内容内边距：左右 `SCRXFrom(11.5)`
- 圆角：`SCRYFrom(14)`
- 边框宽度：`0.5`
- 边框颜色：`RGB(220, 220, 220)`
- 高度：`SCRYFrom(28)`
- 右侧约束：距离开关左侧 `SCRXFrom(-24)`
- 垂直对齐：与开关居中对齐

## 发现

`Absolute CCT Range:` 使用 `DeviceParameterAbsoluteCctRangeViewCell`，原 Reset 按钮与样式 A 不一致：

- 字号为 `12`，样式 A 为 `14`
- 字重为 `.regular`，样式 A 为 `.light`
- 未设置左右内容内边距
- 圆角为 `SCRYFrom(12)`，样式 A 为 `SCRYFrom(14)`
- 边框颜色为 `Bar_Color.withAlphaComponent(0.5)`，样式 A 为 `RGB(220, 220, 220)`
- 高度为 `SCRYFrom(24)`，样式 A 为 `SCRYFrom(28)`
- 额外设置了最小宽度约束，样式 A 依赖内容内边距
- 垂直对齐到标题，样式 A 对齐到开关

## 修复

已将 `DeviceParameterAbsoluteCctRangeViewCell` 的 Reset 按钮初始化和约束对齐到 `DeviceParameterSliderViewCell` 的样式 A。

## 验证项

- 静态检查旧的 Absolute CCT Range Reset 按钮样式不再存在
- 静态检查 Absolute CCT Range Reset 按钮使用样式 A 参数
- 执行 SunSmart iOS 真机 Debug 构建验证
