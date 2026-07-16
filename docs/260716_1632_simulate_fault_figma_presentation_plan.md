# Simulate Fault Figma 呈现效果分析与开发计划

## 结论

可以按 Figma 还原 Simulate Fault 的位置与背景，但不能继续依赖纯系统 `.automatic` 呈现。

Figma 节点 `295:12911` 描述的是“全屏透明呈现容器 + 自定义贴底内容卡片”，而 `.automatic` 是“系统 sheet”。系统 sheet 会自行决定顶部位置、圆角、宽度、dimming 颜色与透明度，不提供跨系统版本的像素级控制入口。因此若以 Figma 为验收基准，需要保留独立 `SimulateFaultViewController`，仅将其呈现方式改为 `.overFullScreen`，并由该 View Controller 自己管理遮罩和内容卡片。

## Figma 结构化数据

参考画布：375 × 812。

- 遮罩：覆盖整个 375 × 812 画布，包括 Status Bar 和 Navigation Bar；颜色为黑色，透明度 30%。
- 内容卡片：左右与画布齐平，底部贴住画布底部，顶部位于 y = 426，高度 386。
- 内容卡片：白色，仅左上角和右上角使用 20pt 圆角。
- Header：y = 434，高 40；图标实际视觉尺寸 16pt，位于 30pt 图标容器中；标题为 14pt Regular。
- Motion Sensor：x = 16，y = 482，宽 343。
- Photocell Sensor：x = 16，y = 575，宽 343。
- Light Status：x = 16，y = 668，宽 343。
- Section 水平边距 16，圆角 14；section 间距 11。
- 375pt 宽度下 Light Status 为两排；更宽设备仍按现有 collection view 自适应列数，一排能容纳时显示一排。

Figma 的 y = 426 不应作为所有设备上的固定绝对值。实现应由内容高度、section 自适应高度和底部安全区共同推导卡片高度；在 375 × 812 参考设备上得到与 Figma 相同的位置，在其他尺寸上保持贴底并完整展示内容。

## 当前实现差异

当前 `SimulateFaultViewController` 使用 `.automatic`：

- 系统控制 sheet 的顶部位置和高度，无法保证参考设备上从 y = 426 开始。
- 系统控制 dimming view，无法保证黑色 30%，也无法将其作为业务约束稳定覆盖到相同层级。
- 系统控制圆角和卡片宽度，iPad 上可能变成居中表单或系统 sheet 宽度。
- 当前根视图直接为白色，没有独立的全屏遮罩层和贴底内容卡片。
- 当前 Header 标题为 16pt Medium，与 Figma 的 14pt Regular 不一致。
- 当前 stack 对 Header 和第一个 section 也使用 11pt 间距；Figma 对应间距为 8pt，后续 section 间距才是 11pt。
- 当前内容绑定到系统 sheet safe area，底部留白由系统决定，与 Figma 的内容位置不一致。

## 推荐方案 A

### 呈现结构

保留 `SimulateFaultViewController`，改为 `.overFullScreen`：

1. Controller 根视图透明并覆盖当前 presentation context 的完整范围。
2. 添加全屏 dimming control，黑色 30%，约束到根视图四边，因此覆盖 Navigation Bar 和 Status Bar。
3. 添加白色 content view，左右和底部贴住根视图，仅顶部两个角为 20pt。
4. Header 和三个 section 放在 content view 中；content view 高度由内部纵向约束和底部安全区推导，不写固定弹窗高度。
5. 正常竖屏高度足够时完整展示所有内容；如可用高度不足，则仅内容区允许滚动，避免截断。

### 点击与手势

- 点击 dimming control 直接 dismiss。
- dimming control 与 content view 是兄弟视图，且 content view 位于其上方；内容区不会命中 dimming control，因此点击、滑动 collection view 都不会误关闭。
- 不在根视图或 content view 上安装关闭手势。
- `.overFullScreen` 不再自动获得系统 sheet 的下滑关闭。第一版不增加全卡片 pan gesture，避免重现“内容区域滑动导致关闭”的问题。
- 如果必须保留下滑关闭，建议作为后续独立增强，只在 Header 区域识别向下拖动，并设置距离和速度阈值；不应在 collection view 或整个内容区识别。

### 自适应规则

- 卡片宽度跟随当前 `SimulateFaultViewController.view` 宽度，即当前设备详情呈现上下文的宽度。
- 卡片底部贴底，底部内边距结合 safe area 推导。
- Section 继续复用 `SimulateFaultSectionView` 和现有 collection view 高度计算。
- 375pt 宽度下保持 Figma 两排 Light Status；足够宽时自动变为一排，卡片整体高度随之缩短。
- 旋转或容器宽度变化后重新计算 collection view 高度与卡片高度。

## 不推荐方案

### 继续 `.automatic`

只能接受系统近似效果，不能把位置、卡片宽度和 30% 黑色背景作为稳定验收项。

### `.automatic` 加 detent

在部分新系统可近似控制高度和圆角，但不同 iOS 版本需要分支；系统 dimming 仍不可按 Figma 精确控制，iPad 宽度也仍由系统决定，不能满足本次重点。

### 自定义 `UIPresentationController`

也能实现，但当前页面只有一个弹窗，额外引入 transitioning delegate、presentation controller 和 animator 会扩大改动面。`.overFullScreen` VC 内部布局已足够覆盖需求。

## 实施计划

### Task 1：先更新视觉与交互契约

修改 `scripts/check_simulate_fault.sh`：

- 将 `.automatic` 契约改为 `.overFullScreen`。
- 增加全屏 30% 黑色遮罩、白色贴底 content view、20pt 顶部圆角契约。
- 增加“关闭事件只绑定 dimming control”的契约。
- 禁止在根视图、content view 或 collection view 安装关闭用 pan/tap 手势。
- 保留仅 light 设备入口、effective edit capability、固定文案、图标、无 Mesh 命令、无选中状态等既有契约。

先运行契约并确认当前 `.automatic` 实现失败，形成 RED。

### Task 2：改造 View Controller 呈现层

修改 `SunSmart/Main/Device/View/SimulateFaultViewController.swift`：

- 根视图改为透明。
- 新增 dimming control 与 content view。
- 使用 `.overFullScreen`，并采用与当前项目弹窗一致的轻量 modal transition。
- 将现有 Header、Scroll View、stack 和 section 移入 content view。
- 按 Figma 修正 Header 字体、图标容器、顶部间距和 Header 到第一个 section 的间距。
- 用内部内容高度与 safe area 推导 content view 高度；可用高度不足时保留滚动兜底。
- dimming control 点击直接 dismiss；权限丢失 dismiss 行为保持不变。
- 按钮 action 仍只在本 VC 内接收，不发命令、不关闭、不保留选中状态。

`DeviceLightViewController` 的菜单入口和 `present(controller, animated: true)` 不需要改变。

### Task 3：验证

自动验证：

- 运行 `Tests/Device/SimulateFaultModelTests.swift`，覆盖 375pt 与宽屏下 collection 行数和高度。
- 运行 `scripts/check_simulate_fault.sh`。
- 运行 `scripts/check_device_menu_icons.sh`，继续接受既有 `menu_set_proxy` 期望。
- 运行 `git diff --check`。
- 使用 iPhoneOS Debug 分别构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart，不使用 Simulator。

人工验收：

- 在 375 × 812 参考尺寸上，卡片顶部、背景透明度、顶部圆角和内部位置与 Figma 对齐。
- 在 393pt 宽设备上，卡片与设备页面同宽并贴底。
- 遮罩覆盖 Navigation Bar 和 Status Bar。
- 点击遮罩关闭；点击或滑动内容区域不关闭。
- 点击任一 item 不关闭、不保留选中态、不发送 Mesh 命令。
- iPad 宽度允许时 Light Status 为一排，卡片高度随内容缩短。
- 权限在展示期间丢失时弹窗关闭。

## 需要确认的取舍

采用方案 A 后，可以准确控制 Figma 的位置和背景，但不再拥有系统 `.automatic` sheet 的原生下滑关闭。建议本次优先恢复 Figma 视觉和可靠的外部点击关闭，不在整个内容区增加自定义下滑手势。

