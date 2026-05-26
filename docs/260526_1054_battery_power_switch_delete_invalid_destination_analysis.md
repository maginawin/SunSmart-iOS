# Battery Power Switch 删除 invalidDestination 日志分析

## 问题

删除 Battery Power Switch 时打印：

- `Error: Unknown destination Node`
- `Failed to send message: invalidDestination`

需要判断这是否表示 reset node 发送失败。

## 结论

是。该日志表示 SDK 在发送 reset node 消息时，已经无法在当前 mesh network 中通过目标地址找到 destination Node，因此抛出 `AccessError.invalidDestination`。这不是单纯没有收到 ACK，而是发送前的目标节点校验失败，消息没有正常发出。

## 证据

- `NordicSigMeshSDK/MeshLib/Manager/MeshMessageManager.swift:177` 捕获发送异常后打印 `Failed to send message: \(error)`。
- `NordicSigMeshSDK/nRFMeshProvision/MeshNetworkManager.swift:600` 和 `MeshNetworkManager+Callbacks.swift:385` 都有相同校验：
  - 通过 `meshNetwork.node(withAddress: destination)` 查找目标 node。
  - 查不到时打印 `Error: Unknown destination Node`。
  - 随后抛出 `AccessError.invalidDestination`。

## 当前 BPS 删除路径

`SunSmart/Common/Data/MeshNetwork+SunSmart.swift:848` 的 `deleteSwitch(switchData:)`：

1. `silentlyResetBatteryPowerSwitchIfNeeded(realBatteryPowerSwitchNode)`。
2. `MeshAPI.sendMessage(message: ConfigNodeReset(), address: node.primaryUnicastAddress)`。
3. 继续删除 repository 和 switch 本地数据。
4. `removeRealBatteryPowerSwitchNodeIfNeeded(realBatteryPowerSwitchNode)`。
5. `self.meshNetwork?.forceRemove(node: node)`。

`MeshAPI.sendMessage(message:address:)` 本身并不立即同步发送，它只是将 `MeshMessageHandle` 加入 `MeshMessageManager` 队列。

因此当前代码存在时序问题：reset 消息入队后，BPS node 很快被本地 `forceRemove`；当 `MeshMessageManager` 定时器稍后真正发送该消息时，SDK 再通过 address 查 destination node，就可能已经查不到，于是打印 `Unknown destination Node` 并发送失败。

## 判断

如果该日志正好发生在 BPS 删除 reset 之后，则基本可以判断这次 `ConfigNodeReset()` 没有正常发出。

它不表示设备拒绝 reset，也不表示设备收到了 reset 但没有回包；它表示 App/SDK 本地发送前就认为目标 node 不存在。

## 后续方向

如果要保持“不等 ACK”，仍需要保证实际发送发生在本地移除 node 之前。当前只调用无回调 `MeshAPI.sendMessage(...)` 不足以保证这一点，因为它只是入队。

可选方向：

- 在 SDK 增加真正的 fire-and-forget reset API：同步调用 `MeshNetworkManager.instance.send(ConfigNodeReset(), to: address)`，发送调用返回后再移除本地 node，但不等待 `ConfigNodeResetStatus`。
- 或在 App 层延迟本地 `forceRemove(node:)`，给消息队列一次发送窗口；但这是时间假设，不如前者明确。
- 或改用现有 `MeshAPI.resetNode(...)`，但这会等待 ACK 或 timeout，删除流程语义会变成灯设备删除那种行为。
