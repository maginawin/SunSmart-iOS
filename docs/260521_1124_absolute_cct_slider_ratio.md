# Absolute CCT Range Slider 比例问题分析

## 背景

用户反馈 `Device Parameter Settings` 的 `2.Parameter selection` 页面中，`Absolute CCT Range` slider 的中间 `2700K...5000K` 区域看起来过窄，怀疑不是按整体 slider 数值比例展示。

## 结论

判断正确。旧实现把 slider 横向区域写死为：

- lower thumb 可拖区域：左侧 `45%`
- 中间不可设置区域：`10%`
- upper thumb 可拖区域：右侧 `45%`

但实际数值域是 `1000K...10000K`：

- 左侧 `1000K...2700K`：`1700 / 9000 = 18.89%`
- 中间 `2700K...5000K`：`2300 / 9000 = 25.56%`
- 右侧 `5000K...10000K`：`5000 / 9000 = 55.56%`

因此旧实现的中间段只有 `10%`，明显小于按数值比例应显示的 `25.56%`。

## 修复方案

在 `DeviceParameterCctRangeSlider` 中统一使用完整数值域 `NodeAbsoluteCctRange.minLowerBound...NodeAbsoluteCctRange.maxUpperBound` 做坐标映射：

- `xPosition(for:)` 按完整 `1000K...10000K` 计算位置。
- lower thumb 仍限制在 `1000K...2700K`。
- upper thumb 仍限制在 `5000K...10000K`。
- 触摸/拖动的反向取值使用同一套完整数值域映射，避免显示位置和实际取值不一致。

## 验证

已用一段独立比例校验确认新映射下 `2700K...5000K` 宽度比例为 `0.2555555555555556`，符合 `2300 / 9000`。
