# GroupPathSequenceDeviceAddView 空态显示问题修复总结

## 问题结论

测试反馈的问题真实存在。

在未选择 Path 或 Zone 时，`GroupPathSequenceDeviceAddView` 应展示引导内容。循环切换 `Quick add`、`Trigger add`、`Manually add` 的过程中，控制器会刷新 Trigger Add 或 Manually Add 的设备列表。原有 `reloadData` 仅根据设备数量控制 `No devices`，因此会覆盖引导状态设置，把已经隐藏的 `No devices` 再次显示。

该问题与 Sequence/Trigger Zone 控制器本身是否选中 Path/Zone 无关，根因位于 Trigger Add 与 Manually Add 子视图对空态可见性的判断不完整。

## 修复方案

在以下两个子视图中统一空态可见性计算：

- `GroupPathSequenceTriggerAddView`
- `GroupPathSequenceManuallyAddView`

`No devices` 现在仅在以下条件同时满足时展示：

- 引导内容已经隐藏，即已选中 Path 或 Zone；
- 当前设备列表为空。

`reloadData` 与 `setGuideVisible` 均调用同一可见性更新方法，避免设备刷新和引导状态相互覆盖。

本次未修改 Sequence、Trigger Zone 或 Space Trigger Zone 控制器，也未改变 Space Trigger Zone 的隐藏状态。选中 Path/Zone 后设备列表为空时，仍保留原有 `No devices` 展示行为。

## 测试与验证

### TDD 合同测试

先新增合同断言，验证 Trigger Add 与 Manually Add 的设备刷新必须保留引导状态控制。修复前测试按预期失败：

`Trigger Add reload must preserve guide-controlled empty-state visibility`

完成最小修复后，合同测试通过。

### 静态检查

- `git diff --check` 通过；
- Trigger Add 与 Manually Add 中未发现 `SCRXFrom` 或 `SCRYFrom`；
- 改动仅涉及两个子视图的空态显示规则及对应合同测试。

### iPhoneOS 构建

以下 Debug、generic iPhoneOS、关闭代码签名的构建均成功：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建日志仍包含项目既有警告，例如 AppIntents metadata 跳过、部分资源符号重复及历史 API 弃用警告；未发现与本次修改相关的编译错误。

## 建议手工回归

1. Sequence 未选 Path：展开底部视图，多次循环切换 Quick Add、Trigger Add、Manually Add，Trigger Add 与 Manually Add 均不应出现 `No devices`。
2. Sequence 选中 Path：当对应设备列表为空时，Trigger Add 与 Manually Add 应继续显示 `No devices`。
3. Trigger Zone 未选 Zone：多次循环切换三个模式，Trigger Add 不应出现 `No devices`。
4. Trigger Zone 选中 Zone：当 Trigger Add 设备列表为空时，应继续显示 `No devices`。
5. 确认 Space Trigger Zone 的入口仍保持隐藏。

