# Battery Power Switch 电量读取日志分析

## 结论

当前代码在 battery power switch 添加成功后会自动发起一次 `GenericBatteryGet`，触发点在添加流程的 `addSuccess` 回调内。

用户提供的日志不能证明“添加成功后没有自动 get battery”。相反，日志尾部连续出现两次 `GenericBatteryGet`，更符合以下情况：

1. 添加成功后自动读取电量一次。
2. 随后用户在详情页手动刷新电量，又读取一次。

## 证据

- `DeviceAddClassicModeController.finalizeBatteryPowerSwitchAddConfiguration(for:)` 和 `DeviceAddProfessionalModeController.finalizeBatteryPowerSwitchAddConfiguration(for:)` 都会调用 `BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(for:node:)`。
- `readInitialBatteryLevelIfPossible` 内部使用 `MeshBatteryPowerSwitchBatteryReader().readBatteryLevel(from:)`。
- 手动刷新电量也使用同一个 `MeshBatteryPowerSwitchBatteryReader`。
- 该 reader 发送的消息都是 `GenericBatteryGet()`，因此自动读取和手动读取在当前日志中没有可区分标签。

## 日志解读

日志中 `batteryPowerSwitchKeyConfig` 配置全部成功，之后出现两次：

- `send message: GenericBatteryGet() address: 151`
- `GenericBatteryStatus(batteryLevel: 0, timeToDischarge: 16777215, timeToCharge: 16777215, flags: 65)`

这说明设备确实响应了两次电量读取请求。`batteryLevel: 0` 在 SDK 中属于已知电量值；只有 `0xFF` 才表示未知电量。`timeToDischarge` 和 `timeToCharge` 为 `0xFFFFFF` 只表示放电/充电时间未知，不影响电量值本身的保存判断。

## 仍然不确定的点

当前日志没有标识 `GenericBatteryGet` 的调用来源，因此无法仅凭日志百分百区分第一条来自自动读取还是来自手动刷新。

如果需要把这个问题验证到不可歧义，建议在自动读取和手动刷新两个入口各增加一条带来源的调试日志，例如：

- `BatteryPowerSwitch initial battery read`
- `BatteryPowerSwitch manual battery refresh`

这样下次日志可以直接判断来源。
