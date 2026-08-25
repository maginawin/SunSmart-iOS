# Path Search by Name 按钮位置优化记录

## 调整结果

- `Add to Path` 与 `Add to Zone` 共用的 `GroupPathSequenceDeviceAddView` 中，`Search by Name` 按钮已从 Manually Add 分类栏右侧移至标题栏。
- 按钮位于 `arrow_down_black` 对应的展开/收起按钮左侧，水平间距固定为 16pt。
- 两个按钮使用垂直中心约束对齐。
- `Search by Name` 按钮继续保持 30 x 30，不缩放。
- 原展开/收起按钮的位置及约束没有修改。
- 原显示条件保持不变：仅在添加视图已展开且选中 Manually Add 时显示。
- 过滤参数、选择状态和 Path / Zone 共用逻辑没有修改。

## 验证

- `DeviceNameFilterExpansionContractTests`：完成 RED→GREEN，覆盖相对 `collapseBtn` 的垂直居中和左侧 16pt 间距。
- `GroupPathSequenceDeviceAddViewContractTests`：通过。
- `git diff --check`：通过。
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 Debug generic iPhoneOS 构建：全部通过。

## 待真机确认

当前验证不替代真机视觉验收。仍需确认 Add to Path / Add to Zone 展开状态下按钮实际间距、点击区域、不同标题长度，以及 iPhone/iPad 上的视觉对齐。
