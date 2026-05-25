# Battery Power Switch 添加后电量未展示问题修复

## 问题

添加 battery power switch 时，日志中可以看到设备返回了 `GenericBatteryStatus`，但进入 battery power switch 页面后仍显示未获取过电量。

## 根因

当前电量读取共用 `MeshBatteryPowerSwitchBatteryReader`，内部使用 `MeshAPI.sendMessage(message:model:timeout:)` 发送 `GenericBatteryGet`。

这个 `model` 版本的发送方法会在每次发送前取消同一 source/opcode 的等待回调。添加成功后的自动读取、页面手动刷新以及刷新轮询如果发生重叠，就可能出现：

1. `GenericBatteryGet` 已发出。
2. 设备返回 `GenericBatteryStatus`，日志能看到 report。
3. 原等待回调已经被后一次读取取消。
4. `readInitialBatteryLevelIfPossible` 的 completion 没有执行，因此没有调用 `saveBattery` 写入数据库。

另外，`saveBattery` 之前只更新传入的 `PJEightKeySwitchData` 实例。如果当前内存列表已经被重新加载成基础 `DeviceSwitchData`，页面可能继续拿到旧缓存。

## 修复

- `MeshBatteryPowerSwitchBatteryReader` 改用 `MeshAPI.sendMessage(message:address:timeout:)`，避免发送新读取请求时主动取消已有等待回调。
- `PJEightKeySwitchRepository.saveBattery` 保存成功后，同步更新 `MeshNetworkManager.instance.switchs` 中对应 switch 的 `batteryLevel` 和 `batteryLastUpdateTime`。
- 如果内存列表中是基础 `DeviceSwitchData`，保存后用 repository metadata 重新构造 `PJEightKeySwitchData` 并替换缓存，保证页面读取到最新电量。

## 预期结果

添加过程中只要成功收到有效 `GenericBatteryStatus`，电量会写入 `pjEightKeySwitchs` 表，并同步到内存缓存。进入 battery power switch 页面时应展示添加时获取到的电池电量和更新时间。
