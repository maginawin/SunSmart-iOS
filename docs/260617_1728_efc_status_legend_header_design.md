# EFC Status Legend Header 设计说明

## 背景

EFC 设备页面的 `EmerFireAlarmStatusLegendHeaderView` 需要对齐 Figma 节点 `155:8535`。当前代码中 legend 有 `Triggered`、`Resume`、`Inactive`、`Disabled` 四项，图标约 14pt，文字 10pt；Figma 设计为三项，且图标和文字尺寸更大。

## 目标

- `EmerFireAlarmStatusLegendHeaderView` 只展示 `Triggered`、`Resume`、`Inactive`。
- 按 Figma 调整 header 视觉：背景 `#FAFAFA`、圆角 10、整体高度 32pt、每项图标容器 20pt、实际图标 16pt、文字 12pt/18pt、颜色 `#404F66`。
- 不再在 EFC 设备页主动展示 `Disabled` 功能。

## 设计

### UI 组件

修改 `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusLegendHeaderView.swift`：

- 删除 `disabledItem`。
- `UIStackView` 改为三项 arranged subviews，并使用 `.equalSpacing` 按 Figma 的非等宽项分布。
- 调整 layout 常量：
  - height: `SCRYFrom(32)`
  - container corner radius: `SCRYFrom(10)`
  - indicator container: `SCRXFrom(20)`
  - indicator image inset: `SCRXFrom(2)`，实际图标视觉为 16pt
  - icon 和 label 间距: `SCRXFrom(4)`
  - label font size: `12`
  - label line height通过原有 label 约束自然呈现，不新增复杂 attributed text
  - text color: `RGB(64, 79, 102)`
- 保留 SnapKit 和现有 `LegendItemView` 私有子类结构，避免扩大改动。

### 状态展示

修改 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRendering.swift`：

- 保留 `EmerFireAlarmMonitorDisplayState.disabled` 和 `EmerFireAlarmStatusSetView.RowStatus.disabled` 兼容分支，避免历史状态或异常状态导致调用链断裂。
- 因设备当前不支持 disabled 功能，`updateStatusSetRows(for:)` 在 `.loading`、`.repair`、`.offline`、`.disabled` 这类不可操作状态下改用 `.inactive`，不再主动展示 disabled 图标。
- `EmerFireAlarmMonitorViewModel.isAllEmergencyFunctionsDisabled` 已固定返回 `false`，不额外改动业务配置模型。

## 验证

- 静态检查：确认 `EmerFireAlarmStatusLegendHeaderView` 不再包含 `Disabled` legend item。
- 构建验证：运行 iPhoneOS `xcodebuild`，不使用 shell 包装或重定向日志。
