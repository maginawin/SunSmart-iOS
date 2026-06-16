# Group Manual Input NO ACK Broadcast Plan

## 目标

回退上一轮 group brightness 最终值改 ACK 的修复，并按新预期实现 group 手动输入 brightness 与 color temperature 时下发两次 NO ACK 组播，中间间隔 100ms。

## 当前代码事实

- `GroupViewController.sendGroupBrightnessValue(_:ended:)` 当前会调用 `MeshAPI.setGroupLightnessState(..., ack: ended)`。
- `showGroupBrightnessInputAlert()` 确认后会调用 `controlPanelView.setBrightnessValue`、`applyGroupBrightnessValue`、`sendGroupBrightnessValue(..., ended: true)`。
- `showGroupCCTInputAlert()` 确认后会先 normalize CCT，再调用 `applyGroupCCTValue`，随后单次调用 `MeshAPI.setGroupColorTemperatureState(...)`，默认 NO ACK。
- `MeshAPI.setGroupLightnessState` 和 `MeshAPI.setGroupColorTemperatureState` 的默认 `ack` 都是 `false`，会发送 unacknowledged group message。

## 设计原则

- 只调整 group 页面手动输入确认路径，不改变 slider 拖动路径、CCT quick button、单设备页面或 Scene/Profile 逻辑。
- 手动输入确认后仍先更新本地 UI 与本地 group/node 状态。
- 不等待响应、不提示失败、不回滚。
- 两次 NO ACK 发送使用同一个 normalized/clamped 最终值。
- 第二次发送用 `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)`，避免引入额外状态机或回调。

## 实施步骤

1. 在 `GroupViewController` 中回退 `sendGroupBrightnessValue(_:ended:)`：
   - 将 `ack: ended` 改回默认 NO ACK 或显式 `ack: false`。
   - 保持 slider 路径仍调用该方法，避免 slider 行为意外变成 ACK。

2. 新增或内联一个很窄的发送 helper：
   - brightness：对 group address 发送 `MeshAPI.setGroupLightnessState(..., ack: false)` 两次。
   - CCT：对 group address 发送 `MeshAPI.setGroupColorTemperatureState(..., ack: false)` 两次。
   - 第二次发送延迟 100ms。

3. 修改 `showGroupBrightnessInputAlert()`：
   - 确认输入后仍更新 `controlPanelView` 和本地状态。
   - 不再通过会被 slider 共用的 `sendGroupBrightnessValue(..., ended: true)` 下发。
   - 改为手动输入专用的两次 NO ACK group brightness 发送。
   - 保持 `reloadVisibleGroupDeviceItems()` 和 `refreshAutoState()`。

4. 修改 `showGroupCCTInputAlert()`：
   - 保留当前 normalize + apply + UI 更新。
   - 将单次 `setGroupColorTemperatureState` 改为两次 NO ACK group CCT 发送，间隔 100ms。
   - 保持当前 limit message 与 `refreshAutoState()` 行为。

5. 更新上一份分析文档 `docs/260616_1552_group_brightness_input_ack_fix.md`：
   - 标记 ACK 方案已被新方案替代。
   - 说明最终采用手动输入两次 NO ACK 组播，避免大组 ACK 响应风暴。

## 验证计划

- 源码断言：
  - `sendGroupBrightnessValue` 不再包含 `ack: ended`。
  - `showGroupBrightnessInputAlert()` 手动输入路径包含两次 brightness NO ACK 发送。
  - `showGroupCCTInputAlert()` 手动输入路径包含两次 CCT NO ACK 发送。
  - 两个手动输入路径都包含 100ms 延迟发送。
- `git diff --check`。
- 推荐 iPhoneOS 构建命令：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

当前已知构建风险：上一轮验证时 iPhoneOS build 失败在 FireAlarm/SDK 符号不匹配，和 group 手动输入逻辑无关。实施后仍需要重新跑并记录实际结果。

## 实施结果

- 已回退 `sendGroupBrightnessValue(_:ended:)` 的 ACK 发送，slider 路径保持 NO ACK。
- 已新增 group 手动输入 brightness 专用两次 NO ACK 发送，第二次延迟 100ms。
- 已新增 group 手动输入 color temperature 专用两次 NO ACK 发送，第二次延迟 100ms。
- 手动输入确认后仍更新本地 UI 与 group/node 状态，不等待响应、不提示失败、不回滚。

## 验证结果

- 源码断言通过：
  - `sendGroupBrightnessValue` 不再包含 `ack: ended`。
  - 手动输入 brightness 路径调用 `sendGroupManualBrightnessValue(clampedValue)`。
  - 手动输入 color temperature 路径调用 `sendGroupManualCCTValue(temperature)`。
  - brightness 与 color temperature helper 均包含两次 `ack: false` 发送。
  - 两个 helper 均使用 `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)`。
- `git diff --check` 通过。
- iPhoneOS `xcodebuild` 构建未通过；失败点不在本次修改文件，而是现有 FireAlarm/SDK 符号不匹配：
  - `EmergencyControllerMode` not found。
  - `VendorFunctionSet` has no member `emergencyMode`。
  - `EmergencyControllerResendParameters` not found。
