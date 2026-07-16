# Simulate Fault 菜单与标题图标修复设计

## 背景与根因

Light 设备页右上角菜单固定使用 `SCRXFrom(114)` 的宽度。`MenuPopView` 内部还会扣除左右边距，并为 30pt 菜单图标和图文间距预留空间，导致英文 `Simulate Fault` 的单行显示空间不足，最终被裁切。

Simulate Fault 弹窗标题区域已有 30×30 的图标容器，但 `black_debug` 图片视图本身固定为 16×16，因此实际视觉尺寸不是需求指定的 30×30。

## 修复方案

采用局部固定宽度方案：

- 仅将 `DeviceLightViewController` 的右上角菜单宽度从 `SCRXFrom(114)` 调整为 `SCRXFrom(140)`。
- 不修改共享 `MenuPopView`，避免影响其他设备或页面的菜单布局。
- 保持标题图标容器为 30×30，并将 `headerImageView` 的实际宽高约束调整为 30×30。
- 不修改菜单字体、行数、图标资源、弹窗内容高度计算、权限逻辑或按钮事件处理。

## 回归验证

- 在 `scripts/check_simulate_fault.sh` 中增加 Light 菜单宽度与 `black_debug` 实际尺寸契约。
- 先运行契约确认旧实现因两项布局不满足而失败，再实施最小代码修改并确认通过。
- 运行 `SimulateFaultModelTests`、设备菜单图标检查和 `git diff --check`。
- 使用 iPhoneOS generic destination 构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 范围

本次只修复 Light 设备页的 `Simulate Fault` 菜单文字裁切和弹窗标题图标尺寸，不调整其他菜单、其他设备页面或 Simulate Fault 的交互逻辑。
