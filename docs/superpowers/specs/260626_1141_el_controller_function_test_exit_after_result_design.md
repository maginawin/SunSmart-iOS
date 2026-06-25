# EL Controller Function Test 结果后退出设计

## 背景

EL Controller Function Test 已改为在 Start 成功后每 2 秒轮询 `GET 0x03 Function Test Result`。现有 App 行为是：拿到可解析结果后停止轮询，并把 Function Test UI 停在结果状态。

本次补充要求：拿到任意终态结果后，App 需要随即发送 Exit Function Test 命令，让设备退出 Function Test；但 UI 继续保持当前测试结果，不恢复默认。只有用户离开并重新进入设备页面时，才按现有页面会话逻辑恢复默认并重新读取 Device Status。

## 目标

- Function Test 轮询拿到终态结果后，停止轮询。
- Function Test UI 保持当前结果状态：
  - Test Passed
  - Lamp Fault
  - Battery Fault
  - Circuit Fault
  - Result Invalid - Device in DT or battery depleted
- 随即发送 `SET 0x08 Exit Function Test`。
- Exit 使用 fire-and-forget，不等待 ACK，不根据 Exit 返回更新 UI。
- 设备主动上报 `RET 0x03` 时也走同一结果后 Exit 流程。
- 页面离开或 push 新页面后仍按现有逻辑停止轮询并恢复默认 UI。

## 非目标

- 不修改 SDK 协议编码或解析。
- 不新增 Exit 按钮。
- 不在页面离开时额外发送 Exit。
- 不在 Exit 后重新读取 Device Status。
- 不因为 Exit 失败、超时或无 ACK 把 UI 改成 Failed。

## 现有代码事实

- `ELControllerFunctionTestHelper` 已集中处理 Function Test 状态机。
- `handleFunctionTestResultStatus(_:)` 是轮询结果和主动上报结果的共同收口。
- `applyFunctionTestResult(_:)` 当前只更新 UI，不发送 Exit。
- `stopPageSession()` 当前会停止轮询并恢复 Function Test / RX/TX 默认 UI，符合“重新进退设备页面才复位”的要求。
- SDK 已提供 `SunricherVendorSet(function: .elControllerExitFunctionTest)`。

## 推荐方案

继续使用 App helper 作为唯一修改点。

在 `ELControllerFunctionTestHelper` 中新增一个 fire-and-forget 的 Exit 方法：

- 检查 `isActive`。
- 检查 `node.sunricherVendorModel`。
- 调用 `MeshAPI.sendMessage(message: SunricherVendorSet(function: .elControllerExitFunctionTest), model: vendorModel)`。
- 不传 callback，不等待 ACK，不更新 UI。

在 `handleFunctionTestResultStatus(_:)` 成功解析结果后：

1. 停止 Function Test Result 轮询。
2. 调用 `applyFunctionTestResult(_:)`，让 UI 显示当前结果。
3. 调用 Exit 方法。

这样轮询返回和设备主动 `RET 0x03` 都会覆盖到。

## 结果处理流程

### 轮询未拿到有效结果

以下情况保持现状：

- `GET 0x03` 超时。
- 无响应。
- `ret != 0`。
- payload 长度不足或解析不到 `ELControllerFunctionTestResult`。

处理方式：

- UI 保持 `Awaiting device response...`。
- 继续每 2 秒轮询。
- 不发送 Exit。

### 轮询或上报拿到终态结果

`ret == 0` 且成功解析 `ELControllerFunctionTestResult` 后：

- `result.isValid == false`
  - UI 显示 `Result Invalid - Device in DT or battery depleted`。
  - 停止轮询。
  - 发送 Exit。
- `result.isValid == true && result.hasFault == false`
  - UI 显示 `Test Passed`。
  - 停止轮询。
  - 发送 Exit。
- `result.isValid == true && result.hasFault == true`
  - UI 显示对应故障项。
  - 停止轮询。
  - 发送 Exit。

多个 fault bit 同时为 1 时，UI 继续展示多个故障项；只发送一次 Exit。

## UI 复位规则

- Exit 发送后：不复位 UI，保持当前结果。
- 用户点击 Start 再次开始：先进入 Awaiting，按新一轮流程执行。
- `viewWillDisappear`：停止轮询并恢复默认 UI。
- 再次 `viewWillAppear`：先默认 UI，再读取 Device Status。

## 文案调整

建议同步更新 invalid 结果文案：

- English：`Result Invalid - Device in DT or battery depleted`
- 简体中文：`结果无效 - 设备处于 DT 或电池电量耗尽`

其他结果文案保持现有：

- `Test Passed`
- `Lamp Fault`
- `Battery Fault`
- `Circuit Fault`

## 测试与验证

代码验证：

- `GET 0x03` 返回 pass 后，UI 显示 Passed，发送 Exit，轮询停止。
- `GET 0x03` 返回任意 fault 后，UI 显示 fault，发送 Exit，轮询停止。
- `GET 0x03` 返回 invalid 后，UI 显示新 invalid 文案，发送 Exit，轮询停止。
- `GET 0x03` 单次失败时继续 Awaiting 和轮询，不发送 Exit。
- 主动 `RET 0x03` 成功结果也发送 Exit。
- Exit 不传 callback，不改变当前 UI。
- 页面离开后 UI 恢复默认。

构建验证：

使用项目推荐 iPhoneOS 构建命令：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 已确认决策

- 使用方案 A：结果处理收口处发送 Exit。
- Exit 后保持当前结果 UI，不恢复默认。
- 只有用户重新进退设备页面时恢复默认 UI。
- Exit 不等待 ACK，不处理返回状态。
