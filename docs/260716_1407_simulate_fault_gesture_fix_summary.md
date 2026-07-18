# Simulate Fault 手势误关闭修复总结

## 结论

Simulate Fault 弹窗的误关闭存在两条 UI 路径：

1. 遮罩关闭手势缺少对内容区触摸的显式过滤，且未同时考虑弹出动画期间的 model frame 和 presentation frame。
2. Navigation Controller 的交互式侧滑返回仍可在弹窗显示时开始，触发 `viewWillDisappear` 提前移除弹窗。

用户日志中的 Mesh `SensorGet` / `SensorStatus` 与弹窗关闭无关。`PJUIDebug` 记录的底层 `UIScrollView` 是弹窗移除后，窗口级调试手势再次 hit-test 所得。

## 修复内容

- outside tap 改由整个 overlay 承载，通过 `UIGestureRecognizerDelegate` 在触摸开始时过滤。
- 触点位于 content 子视图、model frame 或 presentation frame 时不允许关闭。
- outside tap 不取消、不延迟内容区控件事件，保留 Collection View 点击和 Scroll View 滑动。
- overlay 挂载到 `navigationController.view`，背景遮罩覆盖设备页及整个 Navigation Bar；无 Navigation Controller 时回退到当前页面。
- 弹窗显示期间临时禁用交互式侧滑返回，弹窗退出后恢复其原状态。
- 未改变 Simulate Fault 的事件边界：仍只传事件，不发送 Mesh 命令。

## 验证证据

- TDD RED：定向契约首次失败于缺少 overlay dismissal cleanup。
- 纯逻辑测试：model frame 内、presentation frame 内不关闭，两者之外才允许关闭。
- 定向契约：Simulate Fault、设备菜单图标、设备国际化检查全部通过。
- `plutil -lint` 通过，`git diff --check` 通过。
- iPhoneOS Debug 构建通过：SunSmart、Archipelago、SLG Sync Plus、SylSmart 均为 `BUILD SUCCEEDED`。

## 人工验收建议

- 在弹窗内容区上下滑动，弹窗保持展示。
- 点击各个 fault item，事件正常回传且弹窗不关闭。
- 在内容区以外轻点，弹窗关闭。
- 在 Navigation Bar 区域轻点，遮罩可见且弹窗关闭。
- 弹窗显示时从屏幕左边缘滑动，页面与弹窗均不被误关闭；弹窗正常关闭后，侧滑返回恢复。
