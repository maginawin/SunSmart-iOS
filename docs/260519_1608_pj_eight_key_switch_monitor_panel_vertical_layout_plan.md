# PJEightKeySwitchMonitorVC 中间 Panel 垂直布局优化计划

## 背景

本次补充优化 `PJEightKeySwitchMonitorVC` 中间 Panel 的垂直布局。前一轮已将 Panel 水平收敛并居中，但垂直方向仍沿用固定顶部位置。

相关文件：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift`

## 当前问题

当前 `panelView` 的垂直约束为：

- `top = headerView.bottom + 18`
- `height = 502`
- 无 bottom 保护约束
- 无滚动容器

因此在 iPhone 高度不足时，Panel 不会自动缩小或滚动，而是继续从顶部向下绘制固定高度，可能被底部设置栏遮挡。

直接压缩 Panel 高度不可取，因为 Panel 内部有文字和图标，压缩高度容易导致文字与图标重叠。

## 用户确认方案

### iPhone

- Panel 保持固定设计高度，不做高度压缩。
- Panel 放入 `UIScrollView`。
- 滚动区域位于 `headerView` 与 `bottomView` 之间。
- 当可用高度不足时，允许用户纵向滚动查看完整 Panel。
- 水平方向继续保持居中。

### iPad

- 屏幕高度足够，不需要滚动。
- Panel 保持固定设计高度。
- Panel 在 `headerView.bottom` 与 `bottomView.top` 之间的可用区域内水平、垂直居中。

## 实现计划

1. 在 `PJEightKeySwitchMonitorVC` 中新增 `panelScrollView`。
2. `setupUI()` 中按设备类型分支：
   - iPhone：`panelScrollView` 加入主 view，`panelView` 加入 scroll view。
   - iPad：`panelView` 继续直接加入主 view。
3. iPhone 约束：
   - `panelScrollView.top = headerView.bottom`
   - `panelScrollView.bottom = bottomView.top`
   - `panelScrollView.left/right = superview`
   - `panelView.top = contentLayoutGuide.top + 18`
   - `panelView.bottom = contentLayoutGuide.bottom - 12`
   - `panelView.centerX = frameLayoutGuide.centerX`
   - `panelView.width = PJEightKeySwitchMonitorPanelView.preferredWidth`
   - `panelView.height = 502`
4. iPad 约束：
   - 新增布局参考区，顶部为 `headerView.bottom`，底部为 `bottomView.top`。
   - `panelView.centerY = 参考区.centerY`
   - `panelView.centerX = superview.centerX`
   - 保留左右安全边距与固定宽高。
5. 验证：
   - 静态检查存在 `UIScrollView`、`contentLayoutGuide`、`frameLayoutGuide`。
   - 静态检查存在 iPad `centerY` 约束。
   - `git diff --check`。
   - 执行 SunSmart iOS 构建。

## 注意事项

- 不改变 Panel 内部按钮布局、颜色或交互。
- 不压缩 Panel 高度。
- 不处理 `user-temp/`。
- 不回退当前工作区已有未提交改动。
