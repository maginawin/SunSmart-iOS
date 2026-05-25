# Battery Power Switch 添加后自动 Battery Get 修复设计

## 背景

Battery Power Switch 添加成功后需要自动读取一次电量。当前代码已经在 Classic Add 与 Professional Add 的 Battery Power Switch finalize 路径中调用 `readInitialBatteryLevelIfPossible(...)`，但实际效果不稳定，表现为添加完成后页面仍显示未获取电量。

根因不是没有调用读取逻辑，而是读取发起时机处在 Add Manager 生命周期内部。单个设备 `addSuccess` 中发起 `GenericBatteryGet` 后，整体添加流程很快进入 `addFinish`，随后 App 层会立即断开 Battery Power Switch proxy，Add Manager reset 又会调用 `MeshMessageManager.cancelAll()`，清空待发送消息并取消等待回调。因此 `GenericBatteryGet` 可能没发出，或已发出但 `GenericBatteryStatus` 回来前 completion 被取消。

本设计只修复 Battery Power Switch 类型设备，不改变普通灯、网关、Emergency、Kinetic Switch、普通 Switch，也不改变手动 Refresh Battery 弹窗。

## 目标

1. Battery Power Switch 添加成功后稳定自动发送一次 `GenericBatteryGet`。
2. 收到有效 `GenericBatteryStatus` 时保存 `batteryLevel` 和 `batteryLastUpdateTime`，并刷新 Switch 列表/详情数据。
3. 自动读取失败、超时、未知电量或非法电量时静默忽略，不影响添加成功结果。
4. Battery Power Switch 添加后仍主动断开 BLE，但断开时机延后到自动读取完成或超时之后。
5. 变更范围严格限制在 Battery Power Switch，当前支持 PID 为 `0x2A01` 和 `0x2A02`。

## 非目标

- 不把自动 Battery Get 变成普通设备添加流程的一部分。
- 不改变 Add Manager 的全局 `cancelAll()` 行为。
- 不修改普通手动 Refresh Battery 弹窗的轮询频率、文案、超时或保存规则。
- 不新增 UI 提示或用户可见状态。
- 不改变 BLE Direct OTA 成功后的 Battery Power Switch 断开逻辑。
- 不处理 Battery Power Switch 以外设备的电量读取。

## 方案选择

采用“Add 完成后后置读取”的 App 层方案。

Classic Add 与 Professional Add 不再在单个设备 `addSuccess` 的 finalize 阶段立即发送 Battery Get，而是在 finalize 阶段只收集待读取信息。整体 `addFinish` 完成现有回调和通知后，再安排一个后置读取任务。这个任务发生在 Add Manager 即将 reset 的窗口之外，能够避开 `MeshMessageManager.cancelAll()` 对待发送消息和等待回调的清理。

未采用的方案：

- 将 Battery Get 放入 Add Manager append message 队列：可靠性强，但会改变添加耗时，并让电量读取参与添加流程体验，不符合当前 best-effort 目标。
- 修改 SDK 或 Add Manager 的 `cancelAll()`：影响全局 Mesh 消息生命周期，风险高且超出本次 BPS-only 修复范围。

## 架构

设计保持现有职责边界：

- `BatteryPowerSwitchAddConfiguration` 继续负责 BPS Switch 数据创建、LINK 数据准备、配置状态标记和持久化。
- Classic / Professional Add Controller 负责记录添加完成后需要读取电量的 BPS 项，并在 `addFinish` 时把 pending 项复制给后置任务。
- `MeshBatteryPowerSwitchBatteryReader` 继续作为唯一电量读取实现，发送 `GenericBatteryGet` 并解析 `GenericBatteryStatus`。
- `PJEightKeySwitchRepository.saveBattery(...)` 继续负责保存数据库和同步内存缓存。

新增概念是 Add Controller 内部的 pending battery read 列表。列表只保存 Battery Power Switch 的 Switch 数据和 node address，用于 `addFinish` 后重新获取 Node 并读取电量。后置任务不依赖 Add Controller 长期存活；`addFinish` 中复制 pending 项到局部常量，延迟闭包只持有这些读取项，并通过静态 helper 完成读取、保存和断开。

## 数据流

Battery Power Switch 添加成功后的流程调整为：

1. 单个设备进入 `addSuccess`。
2. 如果 node 是支持的 Battery Power Switch，调用 finalize 完成 Switch 数据创建/更新和 sync 状态保存。
3. finalize 返回本次关联到的 `PJEightKeySwitchData`，Add Controller 将其与 node address 记录到 pending battery read 列表。
4. 整体添加进入 `addFinish`。
5. `addFinish` 保留现有 device callback、space count 更新和通知。
6. 如果没有 pending BPS 读取项，按当前行为立即断开 BPS proxy。
7. 如果存在 pending BPS 读取项，将列表复制给后置任务，延后执行自动 Battery Get。
8. 每个读取项重新通过 node address 获取当前 mesh node；仍是 Battery Power Switch 时，调用 reader 读取电量。
9. 读取成功时保存电量和更新时间，并发送 Switch 刷新通知。
10. 读取完成、读取失败或超时后，断开对应 BPS proxy。

读取任务是 best-effort。它不改变 add success/fail 列表，不改变 `syncState`，不影响 `appliedConfigHash`，也不阻塞用户看到添加完成结果。

## 断连策略

Battery Power Switch 仍遵守添加后主动断开 BLE 的要求，但断连从“addFinish 立即断开”调整为：

- 没有 pending battery read：立即断开，行为不变。
- 有 pending battery read：读取 completion 执行后断开。
- reader 超时返回 nil 后断开。
- node 不存在、node 已不是 Battery Power Switch、没有 battery model：立即断开或跳过读取后断开。

当前 reader timeout 为 2.5 秒，因此单个 Battery Power Switch 的断开最多延后约 2.5 秒。多设备添加场景只对 Battery Power Switch 生效。

## 错误处理

- 读取返回 nil：不保存、不提示，继续断开。
- 返回 `batteryLevel == 0xFF` 或大于 100：由 reader 过滤，不保存。
- 数据库保存失败：不提示，仍结束读取并断开。
- addFinish 后 node 已不存在：跳过读取并尝试对已记录的 BPS node 执行断开。
- 多个 Battery Power Switch 同时添加：逐个读取或按现有 Mesh 消息队列串行化，不影响非 BPS 设备。

## 测试与验证

静态验证：

1. Classic Add 和 Professional Add 中不再从 `addSuccess` 阶段直接发送自动 Battery Get。
2. 自动 Battery Get 只从 addFinish 后置任务触发。
3. 触发条件只包含 `node.isBatteryPowerSwitch` 且受 `BatteryPowerSwitchAddConfiguration.isSupportedAddNode(...)` 限制。
4. 普通手动 Refresh Battery 仍使用 `MeshBatteryPowerSwitchBatteryReader`，流程不变。
5. `disconnectBatteryPowerSwitchNodes(...)` 不再在有 pending battery read 时抢先断开。

行为验证：

1. 添加 `0x2A01` 或 `0x2A02` Battery Power Switch，日志中应在 addFinish 后看到一次 `GenericBatteryGet`。
2. 设备返回有效 `GenericBatteryStatus` 时，详情页显示电量和更新时间。
3. 设备不响应或返回未知电量时，添加仍成功，电量保持未获取状态。
4. 添加普通灯、网关、Emergency、普通 Switch 时，不出现新增 Battery Get 或断连延迟。
5. Battery Power Switch 添加后，自动读取完成或超时后 BLE 被断开。
6. iOS build 通过。

## 风险与缓解

- 风险：后置读取与 Add Manager reset 的相对时序仍可能过近。
  缓解：读取任务通过 `DispatchQueue.main.asyncAfter` 做短延迟，确保 Add Manager reset 和 `cancelAll()` 已执行完。

- 风险：读取期间用户已经离开添加页，controller 生命周期结束。
  缓解：后置任务只捕获 pending 读取项，不依赖 controller；读取结果通过 repository 和通知同步到全局数据。

- 风险：延后断开让 BPS 多保持连接约 2.5 秒。
  缓解：只对 BPS 生效，且只有添加后一次；读取完成或超时即断开。

## 实施边界

本次计划只修改：

- `BatteryPowerSwitchAddConfiguration.swift`
- `DeviceAddClassicModeController.swift`
- `DeviceAddProfessionalModeController.swift`

不修改 SDK Add Manager，不修改 `MeshMessageManager.cancelAll()`，不修改资源、本地化、target 配置或依赖。
