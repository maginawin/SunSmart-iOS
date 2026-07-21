# Battery/AC Power Switch “Enable State” 文案调整分析与方案

## 决策状态

2026-07-21 已确认采用方案 A：新增页面专用国际化 Key。

## 目标

只把 Battery Power Switch 与 AC Power Switch Monitor 页面底部弹窗中，`Settings` 同一行的 `Enable` 更新为 `Enable State`。

以下内容保持现状：

- 弹窗展开后图例中的 `Enable`。
- Edit Switch 页面设置列表中的 `Enable`。
- App 其他页面的 `Enable`。
- 页面布局、图标、状态计算、点击行为和数据流。

## 代码事实

- 底部弹窗由 `PJEightKeySwitchMonitorStatusSetView` 管理。
- 目标文案来自该 View 的 `enableTitleLabel`，当前读取通用国际化 Key `enable`。
- 同一文件的展开图例 `enableLegendLabel` 也读取 `enable`，但不属于本次修改范围。
- Edit Switch 页的 `enableRowView` 同样读取 `enable`，也不属于本次修改范围。
- Battery 与 AC 都通过 `PJEightKeySwitchMonitorVC` 使用同一个底部弹窗，因此不需要分别实现。
- 当前只有 English 与简体中文两份 `Localizable.strings`；同一国际化资源被 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 引用。

## 方案比较

### 方案 A：新增页面专用国际化 Key（推荐）

新增 `neightkeyswitches_enable_state`：

- English：`Enable State`
- 简体中文：`启用状态`

仅让目标 `enableTitleLabel` 改用该 Key。

优点：范围最精确，满足国际化要求，不影响同文件图例、Edit 页和其他模块。缺点：增加一个国际化 Key。

### 方案 B：修改通用 `enable` 的英文翻译

优点：改动行数少。缺点：会同时修改多个页面，并且会误改本次明确排除的展开图例和 Edit 页，不符合范围要求。

### 方案 C：在目标 Label 中直接写 `Enable State`

优点：只触达目标 Label。缺点：硬编码用户可见文案，违反项目国际化要求，简体中文也无法正确显示。

## 推荐设计

采用方案 A。改动严格限制在以下三个文件：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

不修改 `enableLegendLabel`、`PJEightKeySwitchEditorView`、控制器、ViewModel、布局约束和状态逻辑。

## 开发计划

1. 在 English 和简体中文本地化文件的 NEightKeySwitches 区域新增专用 Key。
2. 仅把 `enableTitleLabel` 的文本来源切换到新 Key。
3. 静态核对通用 `enable` Key、展开图例与 Edit 页引用均未变化。
4. 校验两份 `Localizable.strings` 语法。
5. 检查四个品牌 target 仍共同引用该国际化资源，并使用 iPhoneOS 构建验证相关 scheme；不使用 Simulator。
6. 运行 `git diff --check`，确认最终差异只包含上述三处目标文件。

## 验收标准

- Battery Power Switch Monitor 页底部弹窗折叠栏显示 `Settings ... Enable State`。
- AC Power Switch Monitor 页底部弹窗折叠栏显示 `Settings ... Enable State`。
- 展开图例仍显示 `Enable` / `Disable`。
- Edit Switch 页仍显示 `Enable`。
- 其他 `Enable` 文案不变。
- English 显示 `Enable State`，简体中文显示 `启用状态`。
- 无布局、交互、数据或协议行为变化。
