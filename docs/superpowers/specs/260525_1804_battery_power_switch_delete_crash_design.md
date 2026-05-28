# Battery Power Switch 删除崩溃修复设计

## 背景

删除真实 Battery Power Switch 时，App 在发送 `ConfigNodeReset()` 后崩溃：

- 崩溃位置：`DeviceSwitchesViewController.deleteCache`
- 断言：`attempt to delete item 0 from section 0 which only contains 0 items before the update`
- 当前触发链路：删除真实 BPS 后，`MeshNetworkManager.deleteSwitch` 会删除全局 `switchs` 数据并发送 `switchsRefreshNotificationName`，列表页收到通知后执行 `updateUI()` 和 `collectionView.reloadData()`；随后 `deleteCache` 继续对同一个全局数据源执行 `collectionView.deleteItems(at:)`，导致 UIKit 认为更新前 section 已经没有 item，却还要删除 item 0。

这说明崩溃根因不是 `ConfigNodeReset` 命令，而是全局数据源、刷新通知、局部删除动画三者的更新时序不一致。

## 目标

1. 删除真实 Battery Power Switch 不再触发 collection view 数据源断言。
2. 删除真实 Battery Power Switch 必须在用户点击删除确认后才执行。
3. 未关联真实设备的虚拟 Battery Power Switch 不需要弹窗确认，直接删除并提示 Done。
4. 保留上一轮设计：真实 BPS 删除时继续静默发送 reset、本地删除真实 Node、明确触发网络地址级云同步。

## 非目标

- 不重构 Switch 列表的数据源结构。
- 不改变 Kinetic Switch 的现有同步页行为。
- 不新增第二层“同步完成确认”。
- 不改变未关联虚拟 BPS 的 Done 提示方式。

## 推荐方案

采用方案 A：删除成功后列表统一走完整刷新，不再对全局 `MeshNetworkManager.instance.switchs` 执行局部 `deleteItems` 动画。

理由：

- 当前 collection view 的数据源直接读取全局 `switchs` 数组，不是控制器私有快照。
- 删除过程中可能由 `deleteSwitch`、详情页、列表页、其他监听者同时触发通知刷新。
- 使用 `reloadData` 或 `updateUI` 可以让 UI 以删除后的全局状态为准，避免局部动画和通知刷新争抢同一个数据源状态。
- 改动范围小，符合本次 bug 修复目标。

## 交互设计

### 真实 Battery Power Switch

用户点击 Delete 后，必须先展示现有删除确认弹窗。只有用户点击 `confirm` 后，才进入同步删除流程或本地删除流程。

同步成功后执行本地删除：

1. 静默发送 `ConfigNodeReset()`，不等待返回。
2. 删除本地 switch 数据和 BPS repository 数据。
3. 删除对应真实 Node 的扩展信息和 mesh node。
4. 删除关联 link group / sub link group。
5. 明确发送地址级云同步通知。
6. 列表页完整刷新，不执行 `deleteItems`。

### 未关联虚拟 Battery Power Switch

未关联真实设备的虚拟 BPS 保持轻量行为：

1. 点击 Delete 后不弹确认。
2. 直接删除本地虚拟 switch 数据。
3. 提示 Done。
4. 列表页完整刷新。

## 数据流

列表页删除入口：

1. cell 删除按钮触发删除操作。
2. 真实设备先展示确认弹窗；虚拟未关联设备直接删除。
3. 真实设备确认后，如果存在需要同步的数据，展示现有 `SyncDevicesViewController`；同步成功回调中执行本地删除。
4. 本地删除完成后，列表页调用 `updateUI()` 或 `reloadData()`，以全局 `switchs` 当前数量重绘。

详情页/编辑页删除入口：

1. 真实设备由详情页或编辑页的删除确认弹窗保护。
2. 用户确认后通过 `deleteSwitchAction` 回到列表页统一执行真实删除流程。
3. 虚拟未关联 BPS 在详情页直接删除，不走确认弹窗。

## 错误处理

- reset 命令发送失败或没有响应，不阻塞删除流程。
- 同步页失败时沿用现有失败处理，不删除本地真实设备。
- 删除后如果当前列表为空，退出编辑状态并显示空态。
- 列表刷新以全局数据源为准，不依赖旧 index。

## 验证计划

1. 删除只有 1 个真实 BPS 的 Space，确认不再崩溃，列表变为空态。
2. 删除多个 switch 中的真实 BPS，确认列表刷新正确，无错删、无断言。
3. 点击 Delete 后取消，确认真实 BPS 不被删除。
4. 点击 Delete 后 confirm，确认才进入同步/删除流程。
5. 删除未关联虚拟 BPS，确认无弹窗、直接 Done、列表刷新。
6. 构建验证：`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
