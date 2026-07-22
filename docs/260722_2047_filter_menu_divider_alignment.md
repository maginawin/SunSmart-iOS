# Filter device 菜单分隔线对齐记录

## 问题

过滤选项菜单的分隔线父 View 高度为 `16pt`，但实际分隔线只有一条物理像素。额外的垂直空间位于两个 `44pt` 选项行之间，使 `Search by Name` 与 `Reset` 的文字在整个菜单中看起来没有垂直居中。

## 调整

- 分隔线高度使用当前确认的 `1.0pt`。
- 分隔线父 View 高度改为与分隔线完全相同。
- 分隔线在父 View 中从 `y = 0` 开始，不再保留额外上下留白。
- 菜单总高度和 `Reset` 行起点同步使用新的分隔线高度。
- 两个选项行高度仍保持 `44pt`，按钮文字继续由按钮自身垂直居中。
- 菜单按钮改用 `UIButton.Configuration.plain()`，由 configuration 管理标题、白色前景色和 `16pt` directional contentInsets，不再使用 iOS 15 已弃用的 `contentEdgeInsets`。

## 验证

- 新增 `DeviceNameFilterMenuViewContractTests` 并完成 RED/GREEN 验证。
- `DeviceNameFilterSearchViewContractTests`：通过。
- `DeviceNameFilterSessionTests`：通过。
- `git diff --check`：通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart generic iPhoneOS Debug 构建均为 `BUILD SUCCEEDED`。
- 四个 target 的 `xcodebuild -quiet` 输出均未再出现本菜单的 `contentEdgeInsets` deprecated 警告。

## 待手工验收

- 真机确认两个菜单选项文字的视觉垂直居中效果。
- 确认 `1.0pt` 分隔线显示清晰且没有额外间隙。
