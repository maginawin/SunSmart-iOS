# Battery Power Switch 添加后自动 Battery Get 不生效根因分析

## 现象

Battery Power Switch 添加成功后，代码尝试自动读取一次电量，但实际进入设备页面后电量没有稳定保存或展示。

## 证据链

当前自动读取入口在 `BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(for:node:)`。

Classic Add 与 Professional Add 都在 `finalizeBatteryPowerSwitchAddConfiguration(for:)` 中调用该 helper：

- fallback 创建 Switch 数据后调用一次。
- 正常 `markFailed` / `markSucceeded` 后调用一次。

helper 内部通过 `MeshBatteryPowerSwitchBatteryReader.readBatteryLevel(from:)` 发送 `GenericBatteryGet`，并在收到有效 `GenericBatteryStatus` 后调用 `PJEightKeySwitchRepository.saveBattery(...)`。

问题不在于添加流程完全没有调用自动读取，而在于自动读取被放在了添加管理器尚未完全结束的阶段：

1. `MeshFastAddDeviceOperation.deviceAddSuccessHandle()` 回调 App 层 `addSuccess`。
2. App 层 `addSuccess` 调用 `finalizeBatteryPowerSwitchAddConfiguration(for:)`。
3. `finalize...` 里调用 `readInitialBatteryLevelIfPossible(...)`。
4. `readInitial...` 通过 `MeshAPI.sendMessage(...)` 注册等待 `GenericBatteryStatus`，并把 `GenericBatteryGet` 放入 `MeshMessageManager` 队列。
5. operation 成功后，`MeshFastAddDeviceManager.startAddOperation()` 发现添加队列结束，调用 App 层 `addFinish`。
6. App 层 `addFinish` 会对 Battery Power Switch 调 `disconnectBatteryPowerSwitchNodes(...)`，即 `MeshLibManager.manager.disconnectProxy(node:)`。
7. `addFinish` 返回后，`MeshFastAddDeviceManager.reset()` 调用 `MeshMessageManager.manager.cancelAll()`。

`cancelAll()` 会清空待发送消息，并取消 MeshNetworkManager 的所有等待回调和 notify callback。因此自动读取有两个失败窗口：

- `GenericBatteryGet` 还没真正发出时，被 `cancelAll()` 清掉。
- `GenericBatteryGet` 已经发出但 `GenericBatteryStatus` 尚未回来时，等待回调被取消，completion 不执行，电量不会保存。

同时，`addFinish` 中立即断开 Battery Power Switch proxy，会进一步缩短设备回包窗口。对于 Low Power Battery Power Switch，这会让自动读取更不稳定。

## 旧假设复核

之前怀疑 `MeshAPI.sendMessage(message:model:timeout:)` 会取消同 source/opcode 的等待回调，导致自动读取和手动刷新互相覆盖。当前工作区已有改动把 reader 改成 `address` 版本，这确实可以避免同类读取互相取消，但它不能解决添加管理器结束时的 `cancelAll()` 和立即断连问题。

因此，`model` 版本取消等待回调是一个次级风险；本次“添加成功后自动读取不生效”的主因是自动读取时机处在 Add Manager 生命周期内部。

## 结论

根因是：自动 Battery Get 当前在单个设备 `addSuccess` 里发起，但全局添加流程随后会执行 `addFinish` 断连和 `MeshFastAddDeviceManager.reset()` 的 `MeshMessageManager.cancelAll()`，导致自动读取消息或等待回调被清理。

修复方向应把自动电量读取移出 Add Manager 即将 reset 的窗口，或显式纳入 Add Manager append message 流程中等待完成。前者改动更小；后者语义更强但会改变添加完成耗时。
