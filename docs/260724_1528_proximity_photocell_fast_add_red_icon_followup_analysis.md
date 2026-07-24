# Proximity/Predictive Lighting with Photocell Fast Add 红色图标复盘

## 结论

本次日志中的 Mesh 配置实际成功，右侧红色图标仍然出现的直接原因不是设备超时、订阅失败或 Profile 参数回包不一致，而是上一轮新增的 Fast Add 任务检查点与实际发送消息使用了不同的 `MeshMessageHandle` 实例。

检查点跟踪器用对象身份 `===` 匹配“任务最后一条消息”。实际发送列表和检查点列表分别调用了 `makeMessageHandles()`，而该方法每次都会通过 `operationType.messageHandles` 重新创建一批句柄。发送成功回调拿到的是第一批句柄，检查点保存的是第二批句柄，因此匹配永远失败，所有任务检查点保持 `pending`；`pending` 又被视为失败，最终设备状态被设置为 `.syncFailed`，Add Device 页面显示 `sync_failed` 红色图标。

该问题与日志表现完全一致：

- Mesh 命令与响应均成功；
- 设备已经加入 Group，Profile、Night/Day Scene 和 Proximity 参数也已写入；
- Add Device 页面仍显示瞬时同步失败；
- 回到 Group 页面后，页面按真实 Node/Group 数据重新计算，不依赖 Fast Add 的临时检查点，因此不显示待同步提示。

## 日志证据

### 1. Key Bind 与 Model Bind 成功

日志中的 `ConfigAppKeyStatus` 和所有 `ConfigModelAppStatus` 均为 `Success`。没有出现配置状态失败或 AppKey/Device Key 解密失败。

### 2. Group 订阅成功

以下两类订阅均收到 `0x801F ConfigModelSubscriptionStatus(status: Success)`：

- 内部地址 `0xFEFD` 的相关模型订阅；
- 目标 Group `0xC000` 的多个模型订阅。

因此本次不是“首条订阅超时导致串行流程中止”的历史问题。

### 3. Night Profile 成功

Night 条件与 Scene 写入均返回成功：

- Lux 条件：index `0`，范围 `0...30`；
- 执行 Scene：`0xFF01`；
- LC Mode、Occupancy Mode、Manual Override、Manual Control、Light Auto Adjust 均返回成功；
- Lightness On/Prolong/Standby、T1～T5 均回显请求值；
- `SceneRegisterStatus` 包含 `0xFF01`。

### 4. Day Profile 成功

Day 条件与 Scene 写入均返回成功：

- Lux 条件：index `1`，范围 `70...65535`；
- 执行 Scene：`0xFF02`；
- Day 的 Lightness 与时间参数均回显请求值；
- `SceneRegisterStatus` 最终包含 `[0xFF01, 0xFF02]`。

这也说明 Night 和 Day 两组 Scene 都真实写入，并非上一轮要解决的“最终状态覆盖 Night 校验”问题。

### 5. Motion Sensitivity 精确一致

请求：

- Vendor 参数：`40 32 F3`
- little-endian 数值：`0xF332 = 62258`

响应：

- `motionSensitivity(value: 62258, maxValue: 63241, minValue: 49151)`

请求值与设备最终值完全一致，不存在此前设备回包 `61410` 或其他量化值导致严格比较失败的问题。

### 6. Proximity Neighbor 配置成功

请求：

- enabled：`true`
- relay：`2`
- ttl：`0`
- AppKey Index：`1`
- neighborAddresses：空数组

响应：

- `SunricherVendorStatus`
- `isSuccessful: true`
- response code：`proximityLightingNeighborSet`

当前 Group 只有一个设备，空邻居数组与日志上下文一致。

### 7. 添加与云上传成功

日志明确出现“添加成功”，随后 Cloud Sync 返回：

- HTTP status：`200`
- business code：`200`
- message：`success`

云上传成功不能单独证明 Mesh Profile 成功，但在本次日志中 Mesh 各任务本身也都有成功响应。

## 源码根因链

### 1. Deferred Task 已保存原始消息句柄，但未被复用

`DeviceGroupDeferredSyncTask` 持有：

- `messageHandles`
- `filteredSceneRecallCount`

但 `makeMessageHandles()` 没有返回保存的 `messageHandles`，而是重新读取 `operationType.messageHandles`。

`DeviceOperationType.messageHandles` 是计算属性，内部每次都新建 `MeshMessageHandle`，例如 Proximity Neighbor 分支会执行新的 `MeshMessageHandle(...)` 构造。

### 2. 发送列表与检查点列表分别生成

Fast Add Plan 构建时：

1. `appendMessageHandles` 调用一次 `task.makeMessageHandles()`，得到实际发送实例 A；
2. `makeTaskCheckpoints` 再调用一次 `task.makeMessageHandles()`，得到检查点实例 B。

A 与 B 的协议内容相同，但对象身份不同。

### 3. Tracker 使用对象身份匹配

`FastAddTaskCheckpointTracker.recordSuccess` 使用：

`checkpoint.lastMessageHandle === messageHandle`

发送成功回调传入实例 A，Tracker 中保存实例 B，所以查找不到条目并直接返回。

### 4. Pending 被判定为失败

Tracker 的 `hasFailure` 将以下状态都视为失败：

- `pending`
- `failed`

由于所有任务检查点都无法命中，它们一直是 `pending`，所以 `plan.hasVerificationFailure` 必定为 `true`。

### 5. UI 显示红色同步失败图标

Classic 和 Professional 添加流程在 `addSuccess` 中调用 `resolveFastAddGroupSyncFailed`。当 `plan.hasVerificationFailure == true` 时：

- `groupSyncFailed = true`
- `addDevice.addState = .syncFailed`
- `DeviceAddViewCell` 使用资源 `sync_failed`

这就是设备右侧红色图标的完整触发链。

## 为什么 Group 页面没有待同步提示

Fast Add 红色图标使用的是添加流程内存中的临时 Plan 与检查点状态；Group 页面则根据 Node、Model subscription、Profile、Scene 等持久化/缓存数据重新计算同步状态。

本次设备实际响应均成功，本地 Node 数据也被 SDK 的响应处理器更新。因此离开 Add Device 页面后，错误的 `pending` 检查点不再参与 Group 页面判定，Group 页面显示正常。

## 与日志中其他信息的关系

以下日志不是本次红色图标的原因：

- `Local ... model ... not bound to key`：描述本地 Provisioner 的对应 Model，不代表远端设备绑定失败；请求已经加密发送且收到有效响应。
- `UnknownMessage(opCode: 0xE0780A)`：来自设备广播地址 `0xFFFF` 的 Vendor 消息，与当前逐条 ACK 配置链无直接关系。
- `XPC connection invalid`：发生在“添加成功”之后，没有中断 Mesh 配置链。
- HTTP gzip 声明与探针结果不一致：服务端仍返回业务成功，与 Add Device 的 `.syncFailed` 判定无关。
- 上传 JSON 中的 `configComplete: false`：值得在其他 Key Bind 问题中单独核查，但即使不考虑该字段，任务检查点对象身份不一致也已经足以稳定触发本次 `.syncFailed`。

## 影响范围

该缺陷不只影响 `Proximity/Predictive Lighting with Photocell`。

凡是 Light 类型设备在 Fast Add 中产生任意 Deferred Task，都会创建无法命中的任务检查点，并在最终阶段被判为同步失败。该 Profile 因为包含 Night/Day、LC Property、Scene Store、Sensitivity 和 Proximity Neighbor 等大量 Deferred Task，所以可以稳定复现。

Sensor 分支使用空检查点列表，不受此对象身份问题直接影响。

## 测试遗漏

现有测试只验证了 Tracker 在“传入同一个对象实例”时的状态转换，没有覆盖 Planner 的实际接线：

- 实际发送列表的最后一个句柄；
- 检查点保存的最后一个句柄；
- 两者是否为同一对象。

现有脚本也只检查相关类型和调用是否存在，无法发现两次生成句柄造成的身份不一致。

## 建议的最小修复边界

后续修复应限制在 Fast Add Deferred Task 句柄复用与对应回归测试：

1. `DeviceGroupDeferredSyncTask.makeMessageHandles()` 必须复用任务创建时保存的 `messageHandles`，不能再次从 `operationType` 生成；
2. 增加 Planner 级回归测试，断言实际发送列表中的任务尾句柄与 Checkpoint 引用的是同一实例；
3. 保留现有任务边界校验策略，不回退到所有 Profile 只做最终状态校验；
4. Classic 与 Professional 继续共享同一 Plan 行为；
5. 真机复测本场景，确认 Add Device 页面显示成功图标，且 Group 页面仍无待同步提示。

本报告仅完成原因分析，未修改业务代码。
