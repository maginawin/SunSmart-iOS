# SyncGatewayCell 无信号文案对齐设计

## 目标

修复 `SyncGatewayCell` 的信号文案布局：

- 有有效 RSSI 时，展示 `signalView`，`signalLabel` 左边保持位于 `signalView` 右边并保留现有间距。
- 没有有效 RSSI 或处于 No signal 状态时，隐藏 `signalView`，`signalLabel` 展示现有本地化文案 `site_sync_gateways_no_signal`，左边与 `nameLabel` 左边对齐。
- 不改变文案的垂直位置、右侧限制、字体、颜色、Cell 高度、操作按钮或同步状态逻辑。

## 根因

当前 `signalLabel` 的左约束始终连接到 `signalView` 右边。设置 `signalView.isHidden = true` 只影响绘制，不会停用该视图的 Auto Layout 约束或清除其宽度，因此无信号文案仍保留隐藏信号条的宽度和间距。

## 方案

采用已确认的方案 A：在 `update(item:action:)` 根据当前信号展示状态重建 `signalLabel` 约束。

- 有信号：左约束连接 `signalView.snp.right`，间距保持现有值。
- 无信号：左约束连接 `nameLabel`。
- 两种状态都保留 `signalLabel` 现有的垂直居中和右侧上限约束。

此方案只修改 `SyncGatewayCell` 的局部布局状态，不引入新的视图层级，也不改动信号状态的数据来源。

## 状态流

`SyncGatewayItemState` 的 `rssi` 与 `isNoSignal` 继续决定是否展示信号条。更新信号文案后，同一分支同步选择对应的左约束，避免复用 Cell 或连续刷新时遗留上一次布局状态。

## 测试与验证

1. 先扩充 `SyncGatewaysUIContractTests`，要求 Cell 同时具备有信号和无信号两条左对齐路径，并验证测试在生产代码修改前按预期失败。
2. 实施最小约束修改后，重新运行 Sync Gateways 检查脚本。
3. 运行 `git diff --check`。
4. 因该文件属于四个 App target，分别执行 SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 generic iPhoneOS Debug 构建；构建验证不等同于真机视觉验收。

## 非目标

- 不修改 RSSI 或 No signal 的判定逻辑。
- 不新增或修改本地化 Key。
- 不调整其他 Cell、页面样式或约束。
- 不进行无关重构或格式化。
