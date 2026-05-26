# Battery Power Switch 删除 Reset Node 分析

## 问题

分析删除真实 Battery Power Switch 时，是否会先向该 Battery Power Switch 的 node address 发送 reset node 命令。

## 结论

会发送。当前源码在最终删除缓存入口 `MeshNetworkManager.deleteSwitch(switchData:)` 中，会先从 `switchData.proxyNode` 取出真实 Battery Power Switch node，并在删除本地 switch、删除 repository 记录、从 mesh network force remove node 之前，调用 `MeshAPI.sendMessage(message: ConfigNodeReset(), address: node.primaryUnicastAddress)`。

因此 reset node 的目标地址就是 Battery Power Switch 真实 node 的 `primaryUnicastAddress`。

## 证据

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:848` 的 `deleteSwitch(switchData:)`：
  - 先判断 `switchData.proxyNode?.isBatteryPowerSwitch == true`，得到 `realBatteryPowerSwitchNode`。
  - 随即调用 `silentlyResetBatteryPowerSwitchIfNeeded(realBatteryPowerSwitchNode)`。
  - 后续才执行 repository 删除、`switchData.delete(...)`、`self.switchs.removeAll(...)`、`forceRemove(node:)`。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:892` 的 `silentlyResetBatteryPowerSwitchIfNeeded(_:)`：
  - guard node 非空。
  - 发送 `ConfigNodeReset()` 到 `node.primaryUnicastAddress`。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1641` 到 `1650` 定义真实 BPS 识别条件：
  - company identifier 为 `0x0A78`。
  - product identifier 为 `0x2A01` 或 `0x2A02`。

## 删除流程边界

需要注意“先发送 reset node”只是在最终本地删除入口 `deleteSwitch(switchData:)` 内成立。

从用户点击删除确认开始，部分入口会先进入 `SyncDevicesViewController(type: .enOceanSwitch(..., deleteSwitch: true))`，执行 target group unsubscription 等删除同步任务；同步成功后才调用 `MeshNetworkManager.deleteSwitch(switchData:)`。所以完整用户流程中，reset node 不是所有网络消息的第一条；它是在真正删除本地 BPS 记录和 force remove node 之前发送。

## 调用入口

- `DeviceSwitchesViewController` 删除确认后最终调用 `deleteCache(switchData:)`，再进入 `MeshNetworkManager.deleteSwitch(switchData:)`。
- `DeviceSwitchViewController` 删除同步成功后直接调用 `MeshNetworkManager.deleteSwitch(switchData:)`。
- `PJPreAddEightKeySwitchesVC` 和 `PJEightKeySwitchMonitorVC` 的真实 BPS 删除确认通过 `deleteSwitchAction` 回到列表/上层删除链路，最终也进入 `MeshNetworkManager.deleteSwitch(switchData:)`。

## 风险说明

当前 reset 使用的是静默发送方式，不等待 `ConfigNodeResetStatus`。如果设备离线、proxy 断开或消息发送失败，本地删除仍会继续执行。
