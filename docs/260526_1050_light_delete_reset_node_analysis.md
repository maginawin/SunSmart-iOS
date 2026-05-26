# Light 删除 Reset Node 分析

## 问题

分析灯类型设备删除时，是否也发送和 Battery Power Switch 删除相同的 reset node 命令。

## 结论

灯类型设备删除时也发送 `ConfigNodeReset()` 到设备 `primaryUnicastAddress`。底层 reset node 命令与 Battery Power Switch 删除使用的是同一个 Bluetooth Mesh foundation message：`ConfigNodeReset`。

但两者发送方式不同：

- 灯删除走 `MeshAPI.resetNode` 或 `MeshAPI.resetNodes`，SDK 内部发送 `ConfigNodeReset()` 后会等待 `ConfigNodeResetStatus` 或超时，并根据成功/失败决定删除本地缓存或提示强制删除。
- Battery Power Switch 删除走 `MeshAPI.sendMessage(message: ConfigNodeReset(), address: node.primaryUnicastAddress)`，只是静默入队发送，不等待返回；随后继续删除本地 switch、repository 记录和真实 node。

## 灯删除证据

- 单灯详情删除入口 `SunSmart/Main/Device/Controller/DeviceLightViewController.swift:470`：
  - 调用 `MeshAPI.resetNode(address: self.node.primaryUnicastAddress)`。
  - reset success 后执行 `node.deleteExtension()` 并通知地址变化。
  - reset fail 后弹出 force delete。
- 灯列表批量删除入口 `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift:706`：
  - 构造 `(address: primaryUnicastAddress, timeout: ...)`。
  - 调用 `MeshAPI.resetNodes(addressDataList: ...)`。
  - 只对 `successAddressList` 中的 node 执行 `deleteExtension()`；失败项提示 force delete。
- 通用设备删除 helper `SunSmart/Main/Device/Model/DeviceProtocol.swift:117`：
  - 调用 `MeshAPI.resetNodes(addressList: nodes.map { $0.primaryUnicastAddress })`。
  - success 后删除扩展数据；失败后提示 force delete。

## SDK 证据

- `NordicSigMeshSDK/MeshLib/MeshAPI.swift:135`：
  - `resetNode(address:)` 转发到 `MeshAddDeviceManager.manager.resetNodes(addressList: [address], ...)`。
- `NordicSigMeshSDK/MeshLib/MeshAPI.swift:145` 和 `155`：
  - `resetNodes(...)` 转发到 `MeshAddDeviceManager.manager.resetNodes(...)`。
- `NordicSigMeshSDK/MeshLib/Manager/MeshAddDeviceManager.swift:406`：
  - 实际发送 `MeshAPI.sendMessage(message: ConfigNodeReset(), address: address, timeout: addressData.timeout)`。
  - 收到 `ConfigNodeResetStatus` 记为成功，否则记为失败。

## 对比 BPS

`SunSmart/Common/Data/MeshNetwork+SunSmart.swift:896` 中 BPS 删除直接调用：

`MeshAPI.sendMessage(message: ConfigNodeReset(), address: node.primaryUnicastAddress)`

该调用命中无回调的 `sendMessage(message: MeshMessage, address:)`，只是将消息加入通用消息队列，不等待 reset status。

## 结论边界

如果只问“是不是同一个 reset node 命令”，答案是：是，都是 `ConfigNodeReset()`。

如果问“删除流程语义是否一样”，答案是：不一样。灯删除通常等待 ACK 并在失败时保留本地节点或提示强制删除；BPS 删除不等待 ACK，发送后立即继续本地删除。
