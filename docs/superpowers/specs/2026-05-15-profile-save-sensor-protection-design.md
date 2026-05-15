# SAVE Profile PIR 目标状态保护设计

## 背景

Group 页面在当前组包含支持传感器的设备，并且当前 Profile 使用传感器行为时，可以显示传感器面板。面板会列出传感器，每个 presence sensor 行都可以启用或禁用 PIR 功能。这个行级开关当前会向选中的传感器发送 `SunricherVendorSet(function: .pirEnabled(enabled: ...))`。

SAVE Profile 已经通过 `ProfileSettingsViewController.saveAction()` 保存组 Profile 设置，并在设备需要同步时进入 `SyncDevicesViewController(type: .group(group, inNodes: nil, outNodes: nil))`。同步流程会发送多种 Profile 配置命令，包括 Light LC 设置、场景、lux 触发条件、Sensor Server publication、PIR 功能变化以及其他 Profile 相关命令。

问题是：SAVE Profile 同步期间，如果 PIR 传感器感应到人，它可能会控制设备；这些设备同时又在接收配置命令。这会形成竞争，导致目标设备有概率不响应部分配置命令。

之前的设计是在同步循环外用组播禁用 PIR，并在结束后恢复旧的启用状态。这个方案不够可靠，因为组播可能不是每个设备都能收到；而且当保存后的 Profile 改变了 PIR 是否应该启用时，恢复旧状态本身也是错误的。

## 目标

在 Group 页面 SAVE Profile 同步期间，下发 Profile 配置命令之前，先禁用组内所有 PIR 传感器功能；Profile 配置结束之后，再应用新保存 Profile 所要求的 PIR 目标状态。

前置禁用和后置启用都必须使用 ACK 命令，并进入现有 SAVE 同步队列。发送间隔、超时、成功/失败校验、节点状态更新都复用现有同步任务逻辑。

## 非目标

- 不修改 Group 传感器面板行级启用/禁用行为。
- 不修改 Sensor Server publication 启用/禁用语义。
- 不修改现有 Sensor Server publication retransmit 规则。
- 不优化或移除 Sensor Server publication 的 `ProfileType.sensorEnabled` 或 `ProfileType.sensorDisable` 任务。
- 不把这个保护流程自动应用到组成员变更、完整设备恢复、场景同步、日程同步、传感器校准或其他同步入口。
- 不为 SAVE Profile PIR 保护单独实现一套发送间隔、超时或 ACK 等待逻辑。

## 架构

新增一个 SAVE Profile 专用的 PIR 保护上下文，例如 `ProfileSensorProtectionContext`，并从 `ProfileSettingsViewController` 传入 `SyncDevicesViewController`。

上下文应包含：

- 目标 `Group`。
- 用户点击 SAVE 前的旧 Profile 类型。
- 用户点击 SAVE 后的新 Profile 类型。
- 当前组内支持 PIR 的传感器节点，用节点地址标识。
- 用户点击 SAVE 前，支持 PIR 的传感器节点中 `pirEnabled == true` 的节点地址集合。
- PIR 禁用策略：对支持 PIR 的传感器生成 ACK `pirEnabled(false)` 同步任务。
- 最终 PIR 启用策略：根据旧 Profile、新 Profile 和 SAVE 前 PIR 启用快照，对需要启用的传感器生成 ACK `pirEnabled(true)` 同步任务。
- 内部状态，用于避免重复执行最终目标状态发送。

`SyncDevicesViewController` 不应再把这个保护逻辑作为同步循环外的组播 guard。它应将 PIR 保护集成到 SAVE Profile 同步任务顺序中：

1. Profile 配置任务运行前，向所有支持 PIR 的组内传感器发送逐节点 PIR 禁用任务。
2. 执行现有 Profile 配置任务。
3. Profile 配置任务结束后，发送新 Profile 目标状态所需的逐节点 PIR 启用任务。

这样可以让行为仍然只作用于 SAVE Profile，同时把时序明确放进现有的逐设备任务协调流程。

保护上下文只应在当前 Group 存在 PIR-capable sensor 时启用。PIR-capable sensor 定义为：

- `presenceDetectedSensorModel != nil`
- `capabilities.contains(.pirEnabled)`

如果组内没有符合条件的节点，则不创建或不传入 `ProfileSensorProtectionContext`。这样无传感器设备、只有环境光传感器的设备、没有 `.pirEnabled` 能力的设备都不会进入保护流程，也不会因为保护上下文存在而跳过普通同步任务。

## 数据流

1. 用户从 Group 页面打开 Profile 设置。
2. 用户点击 SAVE。
3. 在调用 `saveActionCallback?(selectProfile)` 之前，为当前组内支持 PIR 的传感器节点构建 SAVE Profile PIR 保护上下文：
   - `presenceDetectedSensorModel != nil`
   - `capabilities.contains(.pirEnabled)`
   - 保存旧 `group.info.profile.type`
   - 保存新 `selectProfile.type`
   - 保存当前 `pirEnabled == true` 的传感器节点地址集合
   如果没有这样的节点，则不构建保护上下文。
4. 现有 save callback 持久化选中的 Profile 到 `group.info.profile`，并更新组同步状态。
5. 如果 `group.nodes.contains(where: { $0.needSync })`，创建 `SyncDevicesViewController(type: .group(group, inNodes: nil, outNodes: nil))` 并附加传感器保护上下文。
6. 生成同步 model 时，在 Profile 配置任务之前，为支持 PIR 的组内传感器插入 PIR 禁用任务。
7. 从普通 Profile 同步列表中移除或跳过重复的 `pirEnabled(false)` 任务，因为所有支持 PIR 的组内传感器已经在 Profile 配置之前禁用。
8. 将重复的 `pirEnabled(true)` 任务移动或合并到 Profile 配置之后的最终 PIR 目标状态阶段。
9. 现有 Profile、场景、日程、开关、Sensor Server publication 以及其他组同步任务按当前逻辑执行。
10. Profile 配置任务完成后，应用新保存 Profile 要求的最终 PIR 目标状态。

如果没有同步页面，因为没有节点需要同步，则不需要临时禁用。

## PIR 目标状态规则

最终 PIR 目标状态应用，指的是只对新保存 Profile 应用后应该启用的传感器发送 `pirEnabled(true)`。判断目标状态时必须使用 SAVE 前采集的快照，因为前置禁用会把本地和设备侧的 PIR 状态都改成 disabled。

Profile 配置后，只有同时满足以下条件的传感器才应该启用：

- 传感器仍然是组成员。
- 传感器仍然支持 PIR：`presenceDetectedSensorModel != nil` 且 `capabilities.contains(.pirEnabled)`。
- 新保存的 Profile 类型使用 PIR 传感器行为。
- 目标状态规则判定该传感器应该启用。

使用 PIR 的 Profile 类型包括：

- `occupancy_daylight`
- `vacancy_daylight`
- `occupancy`
- `vacancy`
- `proximityLighting`
- `proximityLightingWithPhotocell`

目标状态规则如下：

- 旧 Profile 使用 PIR，新 Profile 也使用 PIR：Profile 配置结束后，只启用 SAVE 前 `pirEnabled == true` 的传感器。这样普通参数修改、或两个支持 PIR 的 Profile 之间切换时，SAVE 前后传感器启用/禁用状态保持一致。
- 旧 Profile 不使用 PIR，新 Profile 使用 PIR：Profile 配置结束后，启用组内所有 PIR-capable 传感器。这样从非传感器 Profile 切换到传感器 Profile 时，新 Profile 默认获得完整 PIR 行为。
- 新 Profile 不使用 PIR：Profile 配置结束后不启用任何传感器。这样从使用 PIR 的 Profile 切换到不使用 PIR 的 Profile，或两个不使用 PIR 的 Profile 之间切换时，PIR 保持禁用。

这意味着最终阶段不是简单“恢复旧的启用状态”，也不是只要新 Profile 使用 PIR 就启用全部；它是“基于旧/新 Profile 关系和 SAVE 前快照，应用新 Profile 的 PIR 目标状态”。

## 任务顺序与去重

SAVE Profile 同步时，PIR 功能任务应作为一个专用保护序列处理：

1. Profile 前置阶段：
   - 为每个支持 PIR 的组内传感器生成 `pirEnabled(false)`。
   - 每个禁用命令都使用 ACK `SunricherVendorSet(function: .pirEnabled(enabled: false))`。
   - 发送进入现有同步队列，间隔、超时、重试或失败处理与其他 SAVE 同步命令保持一致。
   - 禁用任务必须根据 ACK 结果和 `node.pirEnabled == false` 校验成功失败。
2. Profile 配置阶段：
   - 执行普通 Profile 配置任务。
   - 这个阶段不发送普通 `pirEnabled(false)` 任务。
   - 这个阶段不发送普通 `pirEnabled(true)` 任务。
3. Profile 后置阶段：
   - 如果目标状态规则判定存在需要启用的 PIR-capable 组内传感器，则为每个目标传感器发送一次 `pirEnabled(true)`。
   - 每个启用命令都使用 ACK `SunricherVendorSet(function: .pirEnabled(enabled: true))`。
   - 启用任务必须根据 ACK 结果和 `node.pirEnabled == true` 校验成功失败。
   - 如果新保存 Profile 不使用 PIR，或者旧/新 Profile 都使用 PIR 但 SAVE 前没有任何传感器启用，则不发送启用任务。
   - 如果普通 Profile 同步生成了相同节点的 `pirEnabled(true)` 任务，只保留这个 Profile 后置任务。

Profile 前置禁用不应再使用特殊的 no-wait 路径，也不应手动 `sleep` 控制间隔。它应像其他 SAVE 同步任务一样由现有 ACK 队列完成。

## 失败与停止处理

只要 Profile 前置禁用已经开始，发生以下情况时，都必须尝试执行 Profile 后置 PIR 目标状态阶段：

- 普通同步成功完成。
- 普通同步完成但存在失败任务。
- 用户在同步运行中点击 stop。
- 用户在临时禁用已经执行后离开同步页面。

最终目标状态尝试必须是幂等的。上下文标记应防止多个生命周期路径同时触发重复的最终启用发送。

如果前置禁用或后置启用在正常同步队列中失败，应按普通同步任务标记失败，并参与同步成功/失败判断。用户 stop、返回页面或蓝牙关闭等兜底路径中触发的最终目标状态发送也应使用 ACK message handles；这类兜底发送应尽量更新本地节点状态，但不需要重新打开同步 UI。

## 消息行为

Profile 前置 PIR 禁用：

- Message：`SunricherVendorSet(function: .pirEnabled(enabled: false))`。
- Target：每个支持 PIR 的组内传感器节点，使用单播。
- Transport：使用现有 ACK 同步队列，与其他 SAVE 命令保持相同发送节奏和超时逻辑。
- 状态更新：根据 ACK 结果和现有 `node.updateData(message:isSuccess:)` 更新本地 PIR 状态。

Profile 后置 PIR 目标状态启用：

- Message：`SunricherVendorSet(function: .pirEnabled(enabled: true))`
- Target：满足旧/新 Profile 关系和 SAVE 前快照目标状态规则的传感器。
- Transport：使用现有 ACK 同步队列，与前置禁用保持同一类发送和校验逻辑。
- Deduplication：每个节点最多发送一次启用。

## 测试

验证应覆盖：

- SAVE Profile 同步在普通 Profile 配置前发送逐节点 ACK PIR 禁用。
- PIR 禁用阶段使用现有 SAVE 同步队列，不再手动 `sleep` 或直接发送 unack/no-wait message。
- 前置禁用失败时，对应同步任务标记失败。
- 后置启用失败时，对应同步任务标记失败。
- 普通 Profile 配置不会发送重复的 `pirEnabled(false)`。
- 普通 Profile 配置不会在 Profile 配置结束前发送 `pirEnabled(true)`。
- 没有 PIR-capable sensor 的 group 不创建或不使用保护上下文，也不会跳过普通 `pirEnabled` 同步任务。
- 没有传感器功能、只有环境光传感器、没有 `.pirEnabled` 能力的设备不会收到前置禁用或后置启用命令。
- 从使用 PIR 的 Profile 切换到不使用 PIR 的 Profile 后，PIR 保持禁用。
- 从不使用 PIR 的 Profile 切换到使用 PIR 的 Profile 后，Profile 配置结束后启用组内支持 PIR 的传感器。
- 从使用 PIR 的 Profile 修改参数并保存，SAVE 前全部启用时，Profile 配置结束后启用全部传感器。
- 从使用 PIR 的 Profile 修改参数并保存，SAVE 前部分启用时，Profile 配置结束后只启用 SAVE 前启用的传感器。
- 从使用 PIR 的 Profile 修改参数并保存，SAVE 前全部禁用时，Profile 配置结束后不启用传感器。
- 从使用 PIR 的 Profile 切换到另一个使用 PIR 的 Profile 后，Profile 配置结束后只启用切换前已启用的传感器。
- 从不使用 PIR 的 Profile 切换到另一个不使用 PIR 的 Profile 后，Profile 配置结束后不启用传感器。
- 现有 Sensor Server publication 启用/禁用任务保持不变。
- 如果新保存 Profile 使用 PIR，同步失败后仍然尝试最终 PIR 目标状态阶段。
- 如果新保存 Profile 使用 PIR，在禁用后 stop 或离开同步页面仍然尝试最终 PIR 目标状态阶段。
- 组成员变更和传感器面板行级开关不会运行这个保护流程。

## 验收标准

- Group 页面 SAVE Profile 同步期间，PIR 传感器活动不能在 Profile 配置命令发送期间触发普通组控制。
- 同步结束后，PIR 启用状态符合旧/新 Profile 关系和 SAVE 前快照计算出的目标状态。
- PIR 禁用使用单播 ACK 发送，而不是组播或 unack/no-wait 特殊路径。
- PIR 启用在 Profile 配置结束后使用单播 ACK 发送。
- 前置禁用和后置启用都需要校验成功失败。
- 无 PIR-capable sensor 的设备不会进入保护命令流程。
- 功能范围仅限 Group 页面 SAVE Profile。
- 现有 Sensor Server publication retransmit 行为保持不变。
