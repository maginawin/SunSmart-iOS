# Fast Add 任务检查点身份一致性修复设计

## 状态

方案 A 已由用户明确确认。

## 背景

Light 设备在 Add Device 页面直接加入 Group 时，Fast Add 会把 Group subscription、Profile、Scene、Schedule、Proximity 等消息追加到设备入网流程中。

上一轮为解决 Proximity/Predictive Lighting with Photocell 的 Night/Day 最终状态互相覆盖问题，引入了任务级检查点：每个 Deferred Task 在自己的最后一条消息成功时立即验证业务状态。

当前实现存在对象身份接线错误：

- 实际发送列表调用一次 `DeviceGroupDeferredSyncTask.makeMessageHandles()`；
- 检查点列表再次调用该方法；
- 该方法从 `DeviceOperationType.messageHandles` 重新创建消息句柄；
- Tracker 使用对象身份匹配；
- 实际发送句柄与检查点句柄内容相同，但不是同一实例；
- 检查点永久保持 `pending`，最终被误判为 `.syncFailed`。

设备端命令实际成功，因此 Group 页面根据真实 Node/Group 数据重新计算后显示正常。

## 目标

确保 Fast Add 实际发送列表和任务检查点引用同一批 `MeshMessageHandle` 实例，使成功回调能够正确完成检查点。

同时必须满足：

- 不改变其他 Group Profile 的消息内容、顺序和严格成功判定；
- 不影响不选择 Group 的直接添加设备流程；
- 不影响 Classic 与 Professional 添加模式；
- 不影响 Repair、Restore、普通 Group Sync 或其他依赖重新生成消息句柄的流程；
- 不修改 NordicSigMeshSDK；
- 不改变 Sensor Fast Add 行为；
- 真实消息失败或业务状态不一致时仍显示同步失败。

## 非目标

本次不处理：

- Mesh 协议、opcode 或 payload 调整；
- Profile 参数默认值调整；
- Path、Zone 或 Neighbor 计算规则调整；
- Node 缓存模型重构；
- Group 页面同步算法调整；
- Repair/Restore 架构调整；
- Controller 共享重构；
- SDK 修改。

## 方案选择

### 方案 A：Fast Add 专用任务批次

采用。

在 Fast Add Plan 构建期间，每个 Deferred Task 只生成一次消息句柄。由一个 Fast Add 专用批次同时持有：

- 按任务顺序展开的实际发送消息句柄；
- 使用每个任务最后一条消息句柄构建的 Checkpoint Tracker。

发送列表与检查点来自同一批对象，保证身份匹配。

### 方案 B：共享 Deferred Task 返回缓存句柄

不采用。

共享 Deferred Runner 会在重试时重新生成句柄，以避免复用已经携带完成状态、响应地址或失败状态的对象。改变该行为可能影响普通同步和未来重新启用的 Deferred Runner。

### 方案 C：使用 opcode、地址或 payload 匹配

不采用。

Night/Day 任务中存在相同 opcode、相同 Element 和相同属性类型的消息。语义键可能错误完成另一个任务的检查点，无法替代明确的对象身份。

## 架构设计

### Fast Add 任务来源

Fast Add Light 分支继续复用 `DeviceGroupDeferredSyncPlanner.makePlan` 生成任务边界和严格业务验证闭包。

每个 Deferred Task 在进入 Fast Add 专用批次前只调用一次 `makeMessageHandles()`。空消息任务继续被忽略，纯 `SceneRecall` 任务继续沿用现有过滤规则。

### Fast Add 专用批次

批次输入由以下数据组成：

- 一个任务对应的一组消息句柄；
- 该任务原有的严格业务验证闭包。

批次输出：

- `messageHandles`：保持任务及任务内消息的原始顺序；
- `checkpointTracker`：每个非空任务使用同一组消息中的最后一个对象作为检查点。

批次不理解 Mesh opcode、Profile 类型或 Node 数据，只负责保持对象身份和顺序，因此可以使用纯 Swift 单元测试覆盖。

### Fast Add Plan 接入

Light 分支：

1. 生成 Immediate 消息；
2. 为 Deferred Tasks 生成一次 Fast Add 任务来源；
3. 由批次展开 Deferred 消息并创建 Tracker；
4. `appendMessageHandles` 由 Immediate 消息加批次消息组成；
5. Immediate 操作仍使用最终验证；
6. Deferred 操作仍使用任务级检查点。

Sensor 分支继续使用现有消息列表、最终验证和空 Tracker。

### 成功与失败处理

Classic 与 Professional Controller 不变：

- 成功回调先更新 Node 数据；
- 再把实际成功句柄传给 Plan；
- Plan 将句柄交给 Tracker；
- 任务尾句柄命中后立即执行对应业务验证。

失败回调、最终 `.syncFailed` 判定和 Group 同步状态更新逻辑保持不变。

## 隔离边界

允许修改：

- `SunSmart/Main/Device/Model/FastAddTaskCheckpointTracker.swift`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift` 中的 Fast Add 专用构建部分
- `Tests/Device/FastAddTaskCheckpointTrackerTests.swift`
- 现有 Fast Add 检查脚本

明确禁止修改：

- `DeviceGroupDeferredSyncTask.makeMessageHandles()` 的共享重试语义
- `DeviceGroupDeferredSyncPlanner.run`、`runTaskAttempt` 与重试逻辑
- `Node+SyncData.swift`
- `SyncDevicesCellModel.swift` 中的 `DeviceOperationType.isSuccessful`
- Classic 与 Professional Controller
- `DeviceRestoreViewController`
- 直接添加设备的无 Group 分支
- Group 页面同步入口
- NordicSigMeshSDK
- 本地化、资源、target 和依赖配置

## 测试设计

### 纯 Swift 行为测试

新增以下用例：

1. 批次展开后的任务尾句柄与 Checkpoint 引用同一对象；
2. 实际发送的任务尾句柄成功后，`pending` 转为成功；
3. 两个内容等价但对象不同的任务保持独立；
4. 非任务尾句柄不能提前完成任务；
5. 未知句柄不影响已完成或未完成任务；
6. 空任务不创建检查点；
7. 空批次保持成功；
8. Night 检查点完成后，Day 修改当前状态不会改写 Night 结果；
9. 真实业务验证失败后，后续状态变化不能把失败改成成功。

### 源码边界检查

检查脚本必须验证：

- Fast Add Light 分支通过专用批次同时取得发送句柄和 Tracker；
- 不再对同一批 Deferred Tasks 分别生成发送句柄与检查点句柄；
- Strict operation success predicate 保持不变；
- Sensor 分支仍使用空 Tracker；
- Classic 与 Professional 仍先更新 Node、再记录检查点；
- Path/Zone 空迭代和 Sensor publication strict target 逻辑保持不变。

### 构建验证

使用 generic iPhoneOS、关闭签名构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

不使用 Simulator。

### 真机验收矩阵

Group Fast Add：

- Occupancy sensing with daylight harvesting
- Vacancy sensing with daylight harvesting
- Occupancy sensing
- Vacancy sensing
- Daylight harvesting
- Manual control
- Proximity/Predictive lighting
- Proximity/Predictive lighting with photocell

其他添加与修复流程：

- Classic 模式直接添加设备，不选择 Group；
- Professional 模式直接添加设备，不选择 Group；
- Light 添加到 Group；
- Sensor 添加到 Group；
- Repair 已有设备；
- Restore 已有设备；
- Proximity Group 无 Path；
- Proximity Group 有既有成员；
- 真实消息失败时仍显示红色同步失败图标。

## 验收标准

- 目标 Photocell Group 的所有协议与业务验证成功时，Add Device 页面显示成功图标；
- 返回 Group 页面后无待同步提示；
- Night 与 Day Scene 均保留且参数正确；
- 其他七种 Profile 的消息与结果不发生变化；
- 不选择 Group 的添加流程不进入 Fast Add 专用批次；
- Repair、Restore、普通 Group Sync 的源码路径和行为不变；
- 真实消息失败、检查点未完成或严格业务验证失败时仍显示 `.syncFailed`；
- 所有纯 Swift 测试、源码边界脚本、差异检查和四品牌 iPhoneOS 构建通过。

## 回退策略

本次改动只影响 Fast Add Plan 的 Deferred 句柄组装方式。若真机验证发现异常，可回退 Fast Add 专用批次接入，不需要回退 Node、Profile、Controller 或 SDK 代码。
