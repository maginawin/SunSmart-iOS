# EMSign Cell 图标位置优化设计

## 背景

EMSign 设备已在 Lights、Group、Group Members 三处设备控件中隐藏 brightness/cct 进度条，并保持在线 ON 视觉状态。由于当前在线态仍复用普通灯的图标 top 约束，EMSign 在线图标会比离线态更靠上；在没有进度条的布局下，应与离线态图标位置一致。

## 目标

- Lights 分类下 EMSign 设备在线时，图标位置与离线态一致。
- Group 详情页 EMSign 设备在线时，图标位置与该 cell 离线态一致。
- Group Members/组成员管理页 EMSign 设备在线时，图标位置与离线态一致。
- 不改变普通灯的在线/离线布局。
- 不改变 EMSign 的点击 no-op、ON 视觉状态、隐藏 brightness/cct 进度条等既有逻辑。

## 确认方案

采用方案一：在 cell 层针对 EMSign 调整图标 top 约束。

- `DevicesViewCell` 在线 EMSign 使用离线/repair 态图标位置：`SCRYFrom(24)`。
- `GroupDeviceViewCell` 在线 EMSign 使用 Group cell 离线/repair 态图标位置：`SCRYFrom(17)`。

该方案直接复用现有离线态布局常量，改动集中在 cell 渲染层。Lights 与 Group Members 共用 `DevicesViewCell`，Group 详情页使用 `GroupDeviceViewCell`，因此可以覆盖三处展示。

## 非目标

- 不新增 EMSign 专用 cell。
- 不调整图标尺寸、名称 label 位置或 cell 高宽。
- 不改变离线态 icon、repair icon、proxy flag 等其他状态展示。
- 不调整 Mesh 命令、点击、长按或 Identify 页面逻辑。

## 验证点

- `DevicesViewCell` 中在线 EMSign 的 icon top 为 `SCRYFrom(24)`，普通在线灯仍为 `SCRYFrom(12)`。
- `GroupDeviceViewCell` 中在线 EMSign 的 icon top 为 `SCRYFrom(17)`，普通在线灯仍为 `SCRYFrom(10)`。
- Lights、Group、Group Members 三处 EMSign 在线 cell 不显示 brightness/cct 进度条，图标不再偏上。
- iOS Debug iphoneos 构建通过。
