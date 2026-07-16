# Simulate Fault Figma 呈现效果实施总结

## 实施结果

Simulate Fault 已从系统 `.automatic` sheet 改为独立 View Controller 的 `.overFullScreen` 自定义呈现，以匹配 Figma 节点 `295:12911` 的位置与背景。

本次改动仅调整 Simulate Fault 的呈现层和相关测试契约，没有修改菜单权限、按钮内容、按钮事件边界、Mesh 协议或其他设备页面。

## 主要改动

### 全屏背景与贴底卡片

- `SimulateFaultViewController` 使用 `.overFullScreen`。
- 根视图保持透明。
- 新增覆盖整个 Controller 的 dimming control，使用黑色 30% 透明背景。
- 白色 content view 与 Controller 左右和底部对齐，仅顶部两个角使用 20pt 圆角。
- dimming control 位于 content view 下方，覆盖 Navigation Bar 和 Status Bar 所在的 presentation 范围。

### 关闭交互

- 点击 dimming control 直接 dismiss。
- content view 与 dimming control 是兄弟视图，content view 位于上层；内容区域的点击和滑动不会触发背景关闭。
- 没有在根视图、content view、collection view 上安装关闭用 tap 或 pan gesture。
- 按已确认取舍，不再提供系统 `.automatic` sheet 的原生下滑关闭。
- Space 丢失 effective edit capability 时仍主动 dismiss。

### Figma 布局对齐

- 375pt 宽、34pt 底部安全区时，内容卡片高度由模型推导为 386pt；对应 812pt 高参考画布时顶部为 y = 426。
- Header 高度 40pt，Header 到第一个 section 间距 8pt，section 间距 11pt。
- Header 标题改为 14pt Regular 和 Figma 重要文字色。
- Header 图标使用 30pt 容器和 16pt 实际图标尺寸。
- 卡片宽度跟随当前 View Controller 宽度。
- collection view 继续按内部宽度自动换行；768pt 宽参考下 Light Status 为一排，卡片高度缩短为 351pt。
- 内容高度超过可用高度时，卡片高度限制为屏幕高度并启用内部滚动。
- 容器宽度、高度或底部安全区变化时重新计算卡片高度和滚动状态。

## 测试调整

- 新增 `SimulateFaultPresentationMetrics` 纯逻辑模型，统一管理内容水平边距、Header/section 间距、底部留白和卡片高度推导。
- `SimulateFaultModelTests` 新增 375pt 手机与 768pt 宽屏的卡片高度断言。
- `check_simulate_fault.sh` 更新为 `.overFullScreen`、30% 遮罩、20pt 顶部圆角和仅背景控件关闭的静态契约。
- 继续禁止 Mesh 命令、回传事件、选中状态和内容关闭手势。

## 验证结果

- `SimulateFaultModelTests`：通过。
- `scripts/check_simulate_fault.sh`：通过。
- `scripts/check_device_menu_icons.sh`：通过，保留 `menu_set_proxy` 期望。
- `git diff --check`：通过。
- SunSmart，Debug，iPhoneOS generic device：构建成功。
- Archipelago，Debug，iPhoneOS generic device：构建成功。
- SLG Sync Plus，Debug，iPhoneOS generic device：构建成功。
- SylSmart，Debug，iPhoneOS generic device：构建成功。

构建日志仍包含工程既有的 deprecated API、重复 asset symbol 和 App Intents metadata warning；本次修改涉及的 Swift 文件无新增编译错误。

## 尚需人工验收

- 在 375 × 812 或相同安全区设备上核对卡片顶部位置与 Figma。
- 在 393pt 宽设备上核对卡片与当前设备页面同宽。
- 确认遮罩覆盖 Navigation Bar 和 Status Bar。
- 确认点击遮罩关闭，滑动或点击内容区域不关闭。
- 在 iPad 上确认 Light Status 单排和卡片高度缩短。

本轮遵循项目规则，未使用 Simulator 进行验证。
