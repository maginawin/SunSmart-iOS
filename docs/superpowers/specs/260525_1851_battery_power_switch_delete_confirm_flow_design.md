# Battery Power Switch 删除确认流程优化设计

## 背景

真实 Battery Power Switch 当前删除链路存在确认边界不清的问题：详情页或编辑页已经弹出删除确认，用户点击 `Confirm` 后，删除动作又回到 `DeviceSwitchesViewController` 的通用删除入口。该入口同时承担确认、同步分流和本地删除职责，因此在真实 BPS 删除时可能再次出现弹窗，造成用户看到二次确认。

当前代码已经修复过列表页局部删除导致的 collection view 崩溃，并且 `MeshNetworkManager.deleteSwitch(switchData:)` 已经包含真实 BPS 的静默 `ConfigNodeReset()`、本地 switch 删除、BPS repository 删除、真实 node 移除、link group 清理和地址级云同步通知。本次设计不重复实现这些底层删除动作，而是优化真实 BPS 删除的上层流程。

## 目标

1. 真实 BPS 删除只出现一次确认弹窗。
2. 用户点击 `Confirm` 后直接进入删除执行流，不再出现第二次弹窗。
3. 不需要同步时，不跳转 `Sync device(s)`，直接本地删除并显示 `Done`。
4. 需要同步时，先跳转 `Sync device(s)`；同步成功后再本地删除并显示 `Done`。
5. 同步失败、返回或 STOP 时，停留在当前同步失败/停止状态，不删除本地数据，用户可以重新操作。
6. 删除成功后关闭 BPS 页面，回到 `site - space - main - switches`，并刷新 switches 列表。
7. 未关联真实设备的虚拟 BPS 保持现状：不弹确认，直接删除并提示 `Done`。

## 非目标

- 不改变 Kinetic Switch 的删除流程。
- 不重构全部 Switch 删除架构。
- 不改变 `SyncDevicesViewController` 的同步执行机制和失败 UI。
- 不新增 reset 结果等待或超时处理。
- 不改变真实 BPS 底层本地删除内容。

## 当前问题判断

当前没有完全按预期流程执行。原因是 BPS 详情页/编辑页的 `Confirm` 会调用 `deleteSwitchAction`，而该回调在 switches 列表控制器中进入 `deleteConfirmedSwitch`。这个函数虽然名字表示已经确认，但实际仍复用列表页通用分流逻辑，并且删除职责没有和入口确认职责彻底分离。

更合理的做法是拆分两个阶段：

1. 删除入口阶段：只负责是否展示一次确认弹窗。
2. 删除执行阶段：在确认后根据是否需要同步执行同步或本地删除。

这样可以避免入口层弹窗和执行层弹窗叠加，也能让详情页、编辑页、列表页三个入口共享同一套真实 BPS 删除结果。

## 推荐方案

采用方案 A：为真实 BPS 拆出独立的“已确认删除执行流”。

入口层行为：

- 详情页右上角 `Delete`：真实 BPS 弹一次确认；`Confirm` 后进入执行流。
- 编辑页底部 `Delete`：真实 BPS 弹一次确认；`Confirm` 后进入执行流。
- switches 列表编辑态删除：真实 BPS 弹一次确认；`Confirm` 后进入执行流。
- 未关联虚拟 BPS：不弹确认，直接本地删除并提示 `Done`。

执行层行为：

- 使用 `switchData.getNeedSyncDatas(deleteSwitch: true).isEmpty()` 判断是否需要同步。
- 非空表示需要同步。
- 空表示不需要同步。

## 删除流程设计

### 不需要同步

当 `getNeedSyncDatas(deleteSwitch: true).isEmpty()` 为 true：

1. 不跳转 `Sync device(s)`。
2. 调用统一本地删除收尾。
3. 本地删除通过 `MeshNetworkManager.instance.deleteSwitch(switchData:)` 完成。
4. 真实 BPS 在该函数内静默发送 `ConfigNodeReset()`，不等待返回。
5. 删除本地 switch、BPS repository 数据、真实 mesh node、link group/sub link group。
6. 触发 switches 列表刷新和地址级云同步通知。
7. 在 BPS 页面显示 `Done`。
8. 延迟后关闭 BPS 页面，回到 switches 页面。

### 需要同步

当 `getNeedSyncDatas(deleteSwitch: true).isEmpty()` 为 false：

1. 进入 `SyncDevicesViewController(type: .enOceanSwitch(switchData, deleteSwitch: true))`。
2. 同步页发送删除相关同步命令，包括 BPS target group unsubscribe。
3. 同步成功后，回到 BPS 删除收尾，执行与“不需要同步”相同的本地删除逻辑。
4. 同步失败、返回或 STOP 时，停留在当前同步失败/停止状态。
5. 同步失败、返回或 STOP 时不调用本地删除，不显示删除成功，不关闭 BPS 页面。

## 组件边界

### `PJEightKeySwitchMonitorVC`

- 保留真实 BPS 删除确认弹窗。
- `Confirm` 后调用“已确认真实 BPS 删除执行流”，不再回到会二次确认的入口。
- 未关联虚拟 BPS 继续直接删除。

### `PJPreAddEightKeySwitchesVC`

- 保留真实 BPS 删除确认弹窗。
- `Confirm` 后调用“已确认真实 BPS 删除执行流”，不再触发第二次确认。
- 未关联虚拟 BPS 继续直接删除。

### `DeviceSwitchesViewController`

- 列表页仍负责 switches 页面数据刷新。
- 列表编辑态删除真实 BPS 时，仍由列表页弹一次确认。
- 确认后进入同一套已确认执行流。
- 删除成功后列表使用完整刷新，不使用 `collectionView.deleteItems(at:)` 局部删除。

### `MeshNetworkManager.deleteSwitch(switchData:)`

- 继续作为本地删除收尾的唯一底层入口。
- 真实 BPS reset、node 移除、group 清理、地址级云同步通知均保持在这里。
- 不在上层额外重复发送 `ConfigNodeReset()`。

## 错误处理

- Mesh 未连接且需要同步时，沿用当前同步前连接检查，不进入本地删除。
- 同步失败、返回或 STOP 时，停留在同步页当前状态，用户可重试或自行返回。
- reset node 不等待返回，发送失败或无响应不影响本地删除。
- 本地删除完成后多次刷新通知是可接受的，列表最终以全局 `MeshNetworkManager.instance.switchs` 为准。

## 验证计划

1. 真实 BPS 详情页点击 `Delete`，只出现一次确认弹窗。
2. 真实 BPS 编辑页点击 `Delete`，只出现一次确认弹窗。
3. switches 列表编辑态删除真实 BPS，只出现一次确认弹窗。
4. 不需要同步的真实 BPS：`Confirm` 后不进入 `Sync device(s)`，直接 `Done`，关闭 BPS 页面，列表刷新。
5. 需要同步的真实 BPS：`Confirm` 后进入 `Sync device(s)`；同步成功后 `Done`，关闭 BPS 页面，列表刷新。
6. 需要同步的真实 BPS：同步失败、返回或 STOP 时停留在同步页，不删除本地数据。
7. 未关联虚拟 BPS：不弹确认，直接删除并 `Done`。
8. 删除后 switches 列表不崩溃，不调用 `collectionView.deleteItems(at:)`。
9. 使用项目指定 direct `xcodebuild` 命令验证构建通过。
