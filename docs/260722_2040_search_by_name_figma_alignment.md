# Search by Name Figma 对齐与验证记录

## 调整依据

- Figma 文件：One SunSmart。
- 节点：`381:1079`，`Search Panel`。
- 结构化设计显示：外层为白色浮层，内部是一块统一的搜索背景；搜索图标、输入内容、系统 Clear 按钮与 `Cancel` 在视觉上均位于统一背景内。

## 本次调整

- 新增独立的固定搜索背景，由其负责背景色、描边和圆角。
- 输入框改为透明、无边框，只负责输入、占位文字、系统 Clear 按钮与键盘 Search。
- 将输入框和 `Cancel` 同时放入固定搜索背景，修复 `Cancel` 位于描边区域外的问题。
- `Cancel` 右边距固定为 `12pt`，输入框右边与 `Cancel` 左边的间距固定为 `12pt`；输入框左边约束保持不变。
- 修复初始空文本时横向宽度分配不稳定：`Cancel` 使用 required 水平 Content Hugging 与 Compression Resistance，始终保持标题 intrinsic width；输入框使用 defaultLow，固定吸收剩余宽度，不再依赖输入内容长度触发布局纠正。
- 按 Figma 对齐外层浮层与内层搜索背景的尺寸、圆角、内边距、描边及阴影方向。
- 保留原有 Search 提交、Cancel 丢弃草稿和遮罩空白区域关闭逻辑，不修改设备过滤行为。

## 自动化验证

- 新增 `DeviceNameFilterSearchViewContractTests`，并完成 RED/GREEN 验证：
  - 调整前因缺少独立搜索背景而按预期失败。
  - 调整后验证输入框无框透明、统一背景持有输入框和 `Cancel`、Figma 样式参数归属正确。
- `DeviceNameFilterSessionTests`：通过。
- `git diff --check`：通过。
- generic iPhoneOS Debug 构建：
  - SunSmart：`BUILD SUCCEEDED`。
  - Archipelago：`BUILD SUCCEEDED`。
  - SLG Sync Plus：`BUILD SUCCEEDED`。
  - SylSmart：`BUILD SUCCEEDED`。

## 尚待手工验收

- 真机上确认系统 Clear 按钮、长名称输入和 `Cancel` 之间没有覆盖。
- 真机上确认键盘弹出后，浮层位置、阴影和遮罩效果与 Figma 一致。
- 分别确认 iPhone 与 iPad 的搜索浮层宽度及安全区表现。
