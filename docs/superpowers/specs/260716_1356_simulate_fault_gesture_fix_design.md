# Simulate Fault 手势误关闭修复设计

## 问题与根因

`SimulateFaultOverlayView` 当前将关闭手势直接安装在 `dimmingView` 上，关闭逻辑没有再次判断触摸是否起始于弹窗内容区域。内容区内部存在 `UIScrollView` 与 Collection View 手势；在手势竞争以及弹出动画的 presentation frame 与 model frame 短暂不一致时，遮罩 tap 可能完成识别并调用 `dismiss()`。

另一条关闭路径是 Navigation Controller 的交互式侧滑返回：弹窗覆盖到 Navigation Bar 后，导航容器的 `interactivePopGestureRecognizer` 仍可能开始，进而触发页面 `viewWillDisappear` 中的弹窗清理；即使返回转场随后取消，弹窗也已被移除。

日志中的 `PJUIDebug tap view=...UIScrollView -> UIView` 是弹窗被移除后，窗口级调试手势重新执行 `hitTest` 得到的底层设备页视图，不表示底层 UIScrollView 主动关闭了弹窗。同期 Mesh `SensorGet` 与 `SensorStatus` 不参与弹窗生命周期。

## 修复方案

采用方案 A：

- 将 outside tap 安装到整个 `SimulateFaultOverlayView`。
- 由 `UIGestureRecognizerDelegate` 在触摸开始时决定是否允许识别。
- 触点位于 content 的 model frame 或动画期间的 presentation frame 时，拒绝 outside tap。
- 触点对应视图属于 content 子树时，同样拒绝 outside tap。
- outside tap 不取消内容区控件事件；内容区的 UIScrollView pan 和 Collection View item 点击保持原行为。
- 仅当触点起始于弹窗内容区域外、且最终满足 tap 手势条件时关闭弹窗。
- 弹窗显示期间临时禁用交互式侧滑返回，所有弹窗退出路径完成后恢复手势原状态。

触点判定抽成纯逻辑 `SimulateFaultDismissalPolicy`，覆盖内容 model frame、presentation frame 和真正外部区域三类测试。

## Navigation Bar 覆盖范围

弹窗从 `DeviceLightViewController.view` 改为挂载到 `navigationController.view`；无 Navigation Controller 时回退到当前页面 `view`。因此遮罩覆盖当前设备页、Navigation Bar 以及状态栏以下的 Navigation Controller 可用区域，底部弹窗仍与当前页面同宽。

## 范围边界

- 不增加下滑关闭行为。
- 不改变按钮事件、选中状态或命令发送边界。
- 不修改 Mesh 通信。
- 不调整其他弹窗或其他设备页面。

## 验证

- 纯逻辑测试：model frame 内不关闭、presentation frame 内不关闭、两者之外才允许关闭。
- 静态契约：overlay 使用 delegate 过滤；light 页面挂载到 Navigation Controller；无 Mesh 命令。
- 静态契约：弹窗显示期间禁用交互式侧滑返回，关闭后恢复先前状态。
- 现有 Simulate Fault、菜单图标、本地化契约全部通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个 target 使用 iPhoneOS Debug 构建。
