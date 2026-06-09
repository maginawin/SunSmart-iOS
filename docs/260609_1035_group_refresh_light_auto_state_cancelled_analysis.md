# Group Refresh Light Auto State Cancelled 分析

## 结论

Group 页面 refresh 时出现：

`❌ 消息发送失败 message: SunricherVendorGet(function: NordicSigMeshSDK.VendorFunctionGet.lightAutoState), error: cancelled`

不是用户点击取消，也不是 Group 页面主动取消了这条消息。它是 SDK 对 acknowledged vendor get 等待响应超时后的清理结果。

## 日志链路

1. Group 页面触发 refresh 菜单。
2. `GroupViewController.refreshAutoState()` 在 daylight profile 下，对 `group.info.ambientLightSensorNode.sunricherVendorModel` 发送：
   `SunricherVendorGet(function: .lightAutoState)`。
3. 这条 vendor get 的 opcode 是 `0xF1780A`，参数是 `0x32`。
4. SDK 发送到 address `0005` 后没有收到匹配的 `SunricherVendorStatus`。
5. SDK 对 acknowledged message 做重发：
   `Resending Access PDU (opcode: 0xF1780A, parameters: 0x32)`。
6. 超时后 SDK 打印：
   `Response to Access PDU (opcode: 0xF1780A, parameters: 0x32) not received (timeout)`。
7. 随后 SDK 调用 `AccessLayer.cancel(...)` 清理该可靠消息上下文，并向上层回调 `AccessError.cancelled`。
8. `MeshMessageManager.handleSendResult` 打印：
   `❌ 消息发送失败 ... error: cancelled`。

## 代码证据

- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `refreshAutoState()` 只在 `group.info.profile.type == .daylight` 时执行。
  - 发送目标是 `group.info.ambientLightSensorNode` 的 `sunricherVendorModel`。
  - 发送消息是 `SunricherVendorGet(function: .lightAutoState)`。

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - `SunricherVendorGet.opCode == 0xF1780A`。
  - `.lightAutoState` 复用 `.manualOverrideTimeout` 的 command，因此参数是 `0x32`。

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`
  - acknowledged message 超时后先打印 timeout。
  - timeout block 内调用 `cancel(MessageHandle(...))`。
  - `cancel` 会打印 `Cancelling messages with op code...`，并回调 `AccessError.cancelled`。

## 为什么 LightCTLGet 正常但 lightAutoState 失败

日志中 address `0005` 能回复 `LightCTLStatus`，说明节点可达，且普通 SIG Light CTL model 通信正常。

失败的是 vendor get：

- `SunricherVendorGet(.lightAutoState)`
- opcode `0xF1780A`
- vendor 参数 `0x32`
- 期望收到 `SunricherVendorStatus`

因此不能从 `LightCTLGet` 成功推断 `lightAutoState` 必然成功。当前日志更像是 address `0005` 对这条 vendor get 没有回复，或者回复不符合 SDK 匹配条件。

## 后续排查方向

- 确认 address `0005` 是否真的是当前 group 的 ambient light sensor node。
- 确认该节点固件是否支持 `lightAutoState` / vendor `0x32` 的 4-byte status 回复。
- 确认该节点的 Sunricher Vendor Model 是否已绑定当前 AppKey。
- 如果 node `0005` 不是传感器，或不支持该 vendor get，应调整 `refreshAutoState()` 的发送目标筛选，避免对不支持的节点发送。
- 如果设备实际有回复但 App 仍 timeout，应检查 `SunricherVendorStatus` 对 `0x32` status 的解析和 `AccessLayer.isResponse(_:to:)` 的匹配条件。
