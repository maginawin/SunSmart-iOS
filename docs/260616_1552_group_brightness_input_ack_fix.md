# Group Brightness Input Ack Fix

> 状态：已被 `docs/260616_1606_group_manual_input_noack_plan.md` 的方案替代。最终不采用 group ACK，改为 group 手动输入 brightness / color temperature 时下发两次 NO ACK 组播，间隔 100ms。

## 问题

测试路径为 More -> Content Display，开启 CCT quick buttons，并把 control style 设为 Detailed。设备加入 group 后，在 group 页面通过 brightness 数值按钮多次手输亮度值，偶现设备亮度没有变化。

## 根因

Detailed 模式下点击 brightness 数值按钮会进入 `GroupViewController.showGroupBrightnessInputAlert()`，确认后调用 `sendGroupBrightnessValue(_:ended:)`。该方法接收 `ended` 参数，但发送 group brightness 时没有把它传给 `MeshAPI.setGroupLightnessState` 的 `ack` 参数。

因此手输确认虽然是一次最终值操作，但实际仍发送 `LightLightnessSetUnacknowledged`。连续多次手输时，如果某次 unack group 消息丢失，App 本地状态已经更新，设备端亮度却不会变化。

对比依据：

- 单设备亮度手输确认使用 `ack: true`。
- NordicSigMeshDemo 的 group brightness slider 在最终值 `ended == true` 时传 `ack: ended`。
- 当前 group brightness slider 与手输确认共用 `sendGroupBrightnessValue(_:ended:)`，修复该方法可以同时覆盖最终值发送。

## 修复

将 `sendGroupBrightnessValue(_:ended:)` 中的 group brightness 发送改为传入 `ack: ended`。

这样拖动过程仍为 unack，避免每个中间值等待响应；slider 结束和手输确认这类最终值发送会使用 acknowledged message，提高连续操作下的可靠性。

## 替代原因

group address 使用 acknowledged opcode 时，组内大量设备可能同时回 Status，容易造成大组场景的 mesh 空口拥塞。新预期要求不提示、不回滚，并通过两次 NO ACK 组播提升手动输入确认的下发可靠性。

## 验证

- RED：修改前源码断言找不到 `ack: ended`，按预期失败。
- GREEN：修改后源码断言确认 group brightness 发送已传 `ack: ended`。
- `git diff --check` 通过。
- iPhoneOS `xcodebuild` 构建未通过；失败点不在本次修改文件，而是现有 FireAlarm/SDK 符号不匹配：
  - `EmergencyControllerMode` not found。
  - `VendorFunctionSet` has no member `emergencyMode`。
  - `EmergencyControllerResendParameters` not found。
