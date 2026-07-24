# Fast Add 检查点对象身份修复实施总结

## 结论

方案 A 已完成代码实现、自动测试、源码边界检查和四品牌 generic iPhoneOS 构建。

本次修复解决的是 Fast Add 内部的对象身份接线问题：

- 每个 deferred task 只生成一次实际发送的 `MeshMessageHandle`；
- 同一批对象同时用于发送列表与任务尾部 checkpoint；
- 成功回调中的实际句柄可以通过 `===` 命中对应 checkpoint；
- checkpoint 不再因为引用了另一批内容相同但对象不同的句柄而永久保持 pending。

该结论只覆盖代码与自动化验证。目标设备真机添加及其他业务回归仍需在真实 Mesh 环境完成。

## 实现范围

修改文件：

- `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
- `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- `scripts/check_fast_add_dual_scene_verification.sh`

文档：

- `docs/260724_1536_fast_add_checkpoint_identity_fix_design.md`
- `docs/260724_1540_fast_add_checkpoint_identity_fix_implementation_plan.md`
- `docs/260724_1548_fast_add_checkpoint_identity_fix_implementation_summary.md`

## 保持不变的边界

本次没有修改：

- `DeviceGroupDeferredSyncTask.makeMessageHandles()` 的共享重试语义；
- `DeviceGroupDeferredSyncPlanner.run`、`runTasks`、`runTaskAttempt`；
- Classic 与 Professional Controller；
- 无 Group 直接添加设备流程；
- Sensor Fast Add 消息组装与空 checkpoint tracker；
- Repair、Restore 和 Group 页面同步入口；
- `Node+SyncData.swift`；
- `SyncDevicesCellModel.swift` 的严格成功判定；
- Path、Zone、Neighbor、Profile 参数和消息顺序；
- NordicSigMeshSDK；
- 本地化、资源、target 和依赖配置。

## TDD 证据

### RED

先增加 batch 身份测试，在生产代码尚未提供 batch API 时运行：

`bash scripts/check_fast_add_task_checkpoint_tracker.sh`

结果按预期失败，Swift 编译器报告找不到：

- `FastAddTaskCheckpointBatch`
- `FastAddTaskCheckpointSource`

Planner 边界测试也先在旧接线上运行：

`bash scripts/check_fast_add_dual_scene_verification.sh`

结果按预期失败：

`FAIL: Light Fast Add must prepare deferred handles and checkpoints in one batch`

### GREEN

完成最小实现后，两组检查均通过：

- `PASS: Fast Add task checkpoint tracker`
- `PASS: Fast Add dual-scene task-scoped verification`

测试覆盖：

- batch 保持任务及任务内消息顺序；
- 发送列表尾句柄与 checkpoint 使用同一对象；
- 实际尾句柄成功后 checkpoint 完成；
- 内容等价但对象不同的句柄保持独立；
- 非尾句柄不能提前完成任务；
- 未知句柄不改变 pending 或 completed 状态；
- 空任务被忽略；
- 空 batch 成功；
- Night checkpoint 结果不被 Day 最终状态覆盖；
- 已失败 checkpoint 不会被后续状态反转；
- pending 与真实验证失败仍判定为失败。

## 构建结果

以下命令均使用 generic iPhoneOS、关闭签名，结果均为 `BUILD SUCCEEDED`：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建解析到的 `NordicSigMeshSDK` 仍为本地路径引用，本次未修改 SDK。

## 提交

- `6ed21914 test: cover fast add checkpoint handle identity`
- `64efbd18 fix: reuse fast add handles for task checkpoints`

## 待真机验收

### 目标场景

将 Light 设备从 Add Device 页面直接加入未配置 Path 的 `Proximity/Predictive lighting with photocell` Group：

1. 所有 Mesh 配置响应成功；
2. `motionSensitivity` 返回值与请求值严格一致；
3. 空 `neighborAddresses` 的 `proximityLightingNeighborSet` 成功；
4. Night Scene `FF01` 和 Day Scene `FF02` 都写入成功；
5. Add Device 页面设备右侧不再显示红色同步失败图标；
6. 返回 Group 页面后设备正常展示且无待同步提示。

### Profile 回归

- Occupancy sensing with daylight harvesting
- Vacancy sensing with daylight harvesting
- Occupancy sensing
- Vacancy sensing
- Daylight harvesting
- Manual control
- Proximity/Predictive lighting
- Proximity/Predictive lighting with photocell

### 其他流程回归

- Classic 直接添加且不选择 Group；
- Professional 直接添加且不选择 Group；
- Light 添加到普通 Group；
- Sensor 添加到 Group；
- Repair 已有设备；
- Restore 已有设备；
- Proximity Group 有既有成员；
- 真实消息失败时仍显示红色同步失败图标。

## 当前状态

代码实现与本地自动化验证完成。

是否彻底消除目标真机场景的红色图标，需要以上真机验收结果才能最终确认。
