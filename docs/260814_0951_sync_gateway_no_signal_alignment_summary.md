# SyncGatewayCell 无信号文案对齐实施总结

## 结果

`SyncGatewayCell` 现在会根据实际信号展示状态切换 `signalLabel` 的左约束：

- 展示 `signalView` 时，`signalLabel` 继续位于信号条右边并保留原间距。
- 隐藏 `signalView` 时，`signalLabel` 展示现有本地化 `No signal` 文案，左边与 `nameLabel` 左边对齐。
- 两种状态共用原有垂直位置和右侧限制，连续刷新或状态切换时会重建为当前状态对应的约束。

## 兼容现有改动

- 保留用户现有的 `gateway_sync_tz_fail` 图标引用和资源变更。
- 按用户确认，将 `SyncGatewaysUIContractTests` 的旧图标断言同步为 `gateway_sync_tz_fail`。
- 保留用户对按钮边框宽度和其他 Gateway 图标资源的调整，仅移除了一个行末空格以通过补丁检查。

## 自动验证

- TDD RED：新增布局契约后，focused test 因缺少信号状态约束切换而按预期失败。
- TDD GREEN：实施最小修复后，focused test 通过。
- `scripts/check_site_sync_gateways.sh`：通过。
- `git diff --check` 与 `git diff --cached --check`：通过。
- generic iPhoneOS Debug 构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart 均通过。

构建输出仍包含工程既有的重复资源名、弃用 API 和并发隔离等警告，本次没有扩修这些无关问题。

## 验收边界

自动测试和 generic iPhoneOS 编译证明源码契约与四 target 编译有效，但不替代真机视觉验收。建议在真机确认有效 RSSI、No signal，以及两种状态往返切换时的最终位置。
