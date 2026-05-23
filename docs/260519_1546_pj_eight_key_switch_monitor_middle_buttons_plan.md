# PJEightKeySwitchMonitorVC 中间按钮 UI 分析与修复计划

## 背景

本次分析对象是 `PJEightKeySwitchMonitorVC` 页面中间的 8 键 Switch 控件，实际实现位于：

- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorPanelView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorKeyView.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJEightKeySwitchMonitorViewModel.swift`

用户已确认采用方案 B：外层面板在 iPad 居中收敛宽度，按钮内部按不同 key 类型使用独立约束表达视觉规则。

## 当前实现结论

`PJEightKeySwitchMonitorVC` 中的 `panelView` 使用左右各 `SCRXFrom(60)` 的约束和固定高度 `SCRYFrom(502)`。

`PJEightKeySwitchMonitorPanelView` 内部按钮为固定尺寸：

- 每个 key 宽度为 `SCRXFrom(104)`。
- 每个 key 高度为 `SCRYFrom(94)`。
- 左右两列总宽约为 `sideInset * 2 + cellWidth * 2 + columnSpacing * 2`。

在 iPhone 375pt 宽度下，外层 panel 宽度约为 255pt，基本贴合内部两列按钮宽度。

在 iPad 834pt 宽度下，外层 panel 宽度约为 714pt，但内部按钮仍约 256pt 且固定从左侧排布，会出现卡片过宽、按钮内容明显靠左的异常。

`PJEightKeySwitchMonitorKeyView` 当前所有 key 共用一个垂直居中的 `contentStack`，无法同时满足以下差异化规则：

- long press 文案贴近顶部。
- dimming 箭头必须在按钮内上下左右居中。
- ON 与 dimming 使用相同的顶部文案布局。
- 1、2、3、4 的 detail 文本需要固定到底部 8。

## 修复目标

1. iPad 上中间 Switch 控件不再横向铺满导致内容靠左，应保持与按钮内容匹配的宽度并居中。
2. `Long press Dimming`、`Long press AUTO` 文案颜色为 `#94A3B8`。
3. long press dimming 一行按钮中的上下箭头在按钮中上下左右居中。
4. dimming 文案顶部间隔为 4，左右间隔为 8。
5. ON 按钮文字布局与 long press dimming 相同。
6. 1、2、3、4 按钮中若有文字，文字颜色为 `#1E2329`，底部间隔为 8，左右间隔为 8。

## 修复方案

### 1. 收敛外层 panel 宽度

在 `PJEightKeySwitchMonitorPanelView` 暴露 `preferredWidth`，宽度由内部两列 key 的固定设计尺寸计算：

- `sideInset * 2`
- `cellWidth * 2`
- `columnSpacing * 2`

在 `PJEightKeySwitchMonitorVC` 中将 panel 改为水平居中，并使用 `preferredWidth` 作为宽度，同时保留左右最小安全间距。这样 iPhone 继续接近原效果，iPad 不会生成异常宽卡片。

### 2. 调整 key 内部布局结构

在 `PJEightKeySwitchMonitorKeyView` 中保留现有手势和交互逻辑，只替换内容布局：

- `topLabel` 独立约束到顶部，`top = 4`，`left/right = 8`。
- `mainLabel` 用于 ON/OFF 或数字主文字。
- `detailLabel` 独立约束到底部，`bottom = 8`，`left/right = 8`。
- `arrowImageView` 独立约束到 `containerView.center`，确保 dimming 上下箭头不受顶部文案影响。

### 3. 按 style 切换显示规则

- `.scene` 和 `.brightness`：
  - `mainLabel` 居中显示数字。
  - `detailLabel` 若存在，颜色使用 `RGB(30, 35, 41)`，底部 8，左右 8。
- `.dimming`：
  - `topLabel` 显示 long press dimming，颜色使用 `RGB(148, 163, 184)`。
  - `arrowImageView` 显示上下箭头并居中。
  - `mainLabel`、`detailLabel` 隐藏。
- `.toggle(.on)`：
  - `topLabel` 显示 long press AUTO，颜色使用 `RGB(148, 163, 184)`。
  - `mainLabel` 显示 ON，使用与 dimming 相同的顶部文案约束。
  - `detailLabel`、`arrowImageView` 隐藏。
- `.toggle(.off)`：
  - 保持无顶部文案，主文字居中。

## 验证计划

1. 静态 RED 检查当前实现不满足目标。
   - 查找 `RGB(148, 163, 184)` 应失败。
   - 查找 `preferredWidth` 应失败。
   - 查找 `detailLabel.snp.makeConstraints` 中底部 8 应失败。
2. 修改实现后执行 GREEN 检查。
   - 确认 long press 颜色使用 `RGB(148, 163, 184)`。
   - 确认 panel 宽度使用 `PJEightKeySwitchMonitorPanelView.preferredWidth` 并居中。
   - 确认 `arrowImageView.center.equalToSuperview()`。
   - 确认 `topLabel` 顶部 4、左右 8。
   - 确认 `detailLabel` 底部 8、左右 8。
3. 执行 `git diff --check`。
4. 执行 SunSmart 构建命令：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 注意事项

- 本次不修改 `user-temp/`。
- 本次不回退当前工作区已有未提交改动。
- `PJEightKeySwitchMonitorVC.swift` 已存在未提交修改，改动时只在面板布局约束附近追加本次需要的调整。
- 不改变 scene tap、dimming long press、AUTO long press、disabled tap 的行为。
