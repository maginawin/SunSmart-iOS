# Battery/AC Power Switch Panel Action Spacing Analysis

## 问题

在 group 页面进入 `Battery Power Switch` 或 `AC Power Switch`，展开 switch cell 后，`delete` / `save` 按钮距离上方 panel type image 底部的间隔明显大于 `Kinetic switch`。

## 根因

`Kinetic switch` 的展开布局由 `GroupSwitchPanelViewCell` 承载，panel 图片容器和 `delete` / `save` 按钮在同一个 table row 内：

- panel 容器 top：`SCRYFrom(8)`
- panel 容器 height：`SCRYFrom(288)`
- 按钮 top：`panel.bottom + SCRYFrom(16)`
- row height：`SCRYFrom(84) + SCRXFrom(288)`

当前 `Battery/AC Power Switch` 在上次结构对齐时拆成了两个 row：

- `GroupPowerSwitchPanelPreviewCell`
- `GroupPowerSwitchActionCell`

同时 `panelPreview` row 仍使用了 Kinetic 整个 panel/action row 的高度：`SCRYFrom(84) + SCRXFrom(288)`。这会在 panel 容器底部之后保留一大段 row 内空白，再进入下一行 action cell；action cell 内部又有 `SCRYFrom(16)` 的顶部间距，所以实际视觉间隔被放大。

## 修复方案

采用推荐方案：将 Battery/AC 的 panel preview 与 `delete` / `save` 合并为一个 Kinetic-style panel/action cell。

具体调整：

- 在 `GroupPowerSwitchCell.swift` 中用 `GroupPowerSwitchPanelCell` 替代分离的 `GroupPowerSwitchPanelPreviewCell` 和 `GroupPowerSwitchActionCell`。
- `GroupPowerSwitchPanelCell` 内部沿用 Kinetic 布局基准：
  - panel 容器 top `SCRYFrom(8)`
  - panel 容器 height `SCRYFrom(288)`
  - `delete` / `save` top 为 panel bottom + `SCRYFrom(16)`
  - 按钮水平位置与 Kinetic 一致
- 在 `GroupPowerSwitchesViewController` 中：
  - 将展开 rows 从 `.panelPreview + .actions` 改为单个 `.panelPreview`
  - `.panelPreview` cell 同时配置 panel definition、edit 权限和 save 状态
  - `.panelPreview` row height 保持 `SCRYFrom(84) + SCRXFrom(288)`

## 验证

- 静态检查 `GroupPowerSwitchesViewController` 中不再存在 `.actions` row。
- 确认 `delete` / `save` 与 panel 容器在同一个 cell 内。
- 运行 iPhoneOS 构建：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

