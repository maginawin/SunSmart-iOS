# Group Daylight Calibration AUTO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Per project preference, use Inline Execution by default unless the user explicitly requests subagents.

**Goal:** 所有 daylight profile 在 Calibration 成功并完成 group profile 配置后，立即触发一次 group AUTO，使设备无需用户手动点击 AUTO 即可进入自动控制运行态。

**Architecture:** 在 `LightSensorCalibrationViewController` 的校准成功后配置链路中增加一个明确的 auto restore 步骤。先完成当前传感器 publication 与 group 内灯具 profile 配置；当配置未失败或无需配置时，再对 group 地址发送与 group 页面 AUTO 按钮一致的 `LightLCLightOnOffSetUnacknowledged(true)`。该行为仅限定在 `.occupancy_daylight`、`.vacancy_daylight`、`.daylight` 且校准/启用当前光感成功的路径。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Bluetooth Mesh Light LC、Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - 负责 Calibration 页成功后的传感器启用、profile 配置、AUTO restore 触发。
  - 新增 daylight profile 判断与校准后 AUTO 触发 helper。
  - 调整 `configuring(lightNodes:)` 支持配置完成回调，保证 AUTO 在配置完成后发送。
- Read only: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 作为 AUTO 按钮行为参考，保持命令一致。
- Read only: `SunSmart/Common/Data/Node+SyncData.swift`
  - 确认配置同步仍由既有 `getNodeSyncProfiles()` 生成，不重写 profile 同步逻辑。
- Read only: `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 确认 profile 配置项和 Light LC 运行态触发的职责边界。
- Docs: `docs/260608_1130_group_daylight_calibration_auto_analysis.md`
  - 问题分析依据。

## Behavior Contract

- Calibration 成功且传感器启用成功后：
  - 如果 group profile 是 `.occupancy_daylight`、`.vacancy_daylight`、`.daylight`，最终发送一次 `LightLCLightOnOffSetUnacknowledged(true)` 到 `group.address.address`。
  - 如果 `configuring(lightNodes:)` 有需要配置的灯，AUTO 在配置全部完成后发送。
  - 如果没有需要配置的灯，AUTO 仍应发送。
  - 如果配置中有 failed nodes，当前失败结果不发送 AUTO，避免在部分 profile 未配置成功时给用户造成“已恢复自动”的假象。
  - 如果用户在失败弹窗中 Retry，且 retry 后配置成功，应发送 AUTO，因为此时校准后的配置链路已经完成。
  - 如果传感器 enable publication 失败，不发送 AUTO。
- 非 daylight profile 不改变行为。
- 手动选择已校准光感设备并启用时，也应在启用并完成必要 profile 配置后触发 AUTO，因为用户预期同样是切换当前 group 使用的 daylight sensor 后自动生效。
- 用户主动取消配置、离开页面、校准失败时，不发送 AUTO。

## Task 1: Add Completion Result To Calibration Profile Configuring

**Files:**
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

- [x] **Step 1: Change `configuring(lightNodes:)` signature**

将现有：

```swift
private func configuring(lightNodes: [Node]) {
```

改为：

```swift
private func configuring(lightNodes: [Node], completion: ((Bool) -> Void)? = nil) {
```

约定 `Bool == true` 表示没有失败节点或无需配置；`false` 表示配置失败或被中断。

- [x] **Step 2: Handle empty sync list as success**

在 `setLightNodes.isEmpty` 分支中，隐藏弹窗后调用：

```swift
completion?(true)
```

注意保持当前 UI 行为不变。

- [x] **Step 3: Return success or failure after loop**

在最终 `DispatchQueue.main.async` 中：

- `failedNodes.count > 0` 时，保持展示 `showCheckingCorrectFailure(...)`，然后 `completion?(false)`。
- `failedNodes.count == 0` 时，保持 `SRAlertView.hide()`，然后 `completion?(true)`。

- [x] **Step 4: Preserve existing callers**

已有 `configuring(lightNodes:)` 调用不需要全部改签名，因为 completion 默认 nil；重点确认以下调用仍编译：

- 校准成功后的 `sensorEnabled(...)`
- 选择已校准传感器后的 `sensorEnabled(...)`
- disable 传感器后的 `sensorDisable(...)`
- retry 失败节点的 `showCheckingCorrectFailure(...)`

## Task 2: Add Daylight AUTO Restore Helper

**Files:**
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

- [x] **Step 1: Add daylight profile guard helper**

在 controller 内新增 private helper：

```swift
private var shouldRestoreAutoAfterDaylightCalibration: Bool {
    let type = group.info.profile.type
    return type == .occupancy_daylight || type == .vacancy_daylight || type == .daylight
}
```

- [x] **Step 2: Add AUTO restore command helper**

在 controller 内新增 private helper：

```swift
private func restoreGroupAutoAfterDaylightCalibration() {
    guard shouldRestoreAutoAfterDaylightCalibration else { return }
    MeshAPI.sendMessage(
        message: LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0),
        address: group.address.address
    )
}
```

保持命令与 `GroupViewController.autoBtnAction(sender:)` 一致。

- [x] **Step 3: Keep helper local**

不要新增跨文件 service，不改 `GroupViewController`，不把 AUTO 触发混入 `Node+SyncData`。这是运行态触发，不是 profile 配置项。

## Task 3: Trigger AUTO After Calibration Success Path

**Files:**
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

- [x] **Step 1: Update `sensorEnabled(sensor:resetCalibrated:result:)` to expose configuration completion**

将内部两处触发配置的地方改为带 completion 的调用。

当前 sensor 已经配置 publication 时：

```swift
if ambientLightSensorModel.publish?.publicationAddress == self.group.address {
    result?(true)
    DispatchQueue.main.async {
        self.configuring(lightNodes: self.group.nodes)
    }
    return
}
```

改为：

```swift
if ambientLightSensorModel.publish?.publicationAddress == self.group.address {
    result?(true)
    DispatchQueue.main.async {
        self.configuring(lightNodes: self.group.nodes) { [weak self] success in
            guard success else { return }
            self?.restoreGroupAutoAfterDaylightCalibration()
        }
    }
    return
}
```

publication set 成功时：

```swift
DispatchQueue.main.async {
    self.updateGroupLightSensor()
    self.configuring(lightNodes: self.group.nodes)
}
```

改为：

```swift
DispatchQueue.main.async {
    self.updateGroupLightSensor()
    self.configuring(lightNodes: self.group.nodes) { [weak self] success in
        guard success else { return }
        self?.restoreGroupAutoAfterDaylightCalibration()
    }
}
```

- [x] **Step 2: Verify calibration success callback remains single responsibility**

不要在 `calibrationBtnAction()` 的 successful block 中直接发 AUTO。原因：此时 profile 配置可能还没完成；AUTO 必须在 `sensorEnabled` 完成 publication 与 `configuring` 之后。

- [x] **Step 3: Check no duplicate AUTO in one success path**

一次校准成功只会进入一次 `sensorEnabled(...)`。确认没有在 `calibrationBtnAction()` 和 `sensorEnabled(...)` 同时发送 AUTO。

## Task 4: Preserve Failure And Retry Behavior

**Files:**
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

- [x] **Step 1: Failed node retry must not send AUTO on original failure**

`showCheckingCorrectFailure(...)` 展示时，原始配置 completion 返回 false，不发送 AUTO。

- [x] **Step 2: Retry failed nodes keeps completion behavior**

将当前 retry 行为：

```swift
self?.configuring(lightNodes: failedNodes)
```

改为继续传入同一个 completion：

```swift
self?.configuring(lightNodes: failedNodes, completion: completion)
```

这样原始失败不会发送 AUTO；如果 retry 后所有失败节点配置成功，则 completion 返回 true 并触发 AUTO。

- [x] **Step 3: Stop action must not send AUTO**

`stepConfiguring()` 设置 `stopConfig = true` 并停止发送时，最终 `failedNodes` 会包含未完成节点；completion 返回 false，不发送 AUTO。

## Task 5: Verification

**Files:**
- Verify only.

- [x] **Step 1: Swift compile check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.
- No Swift compile errors in `LightSensorCalibrationViewController.swift`.

- [x] **Step 2: Brand target impact check**

因为 `LightSensorCalibrationViewController.swift` 被多个品牌 target 引用，需要至少确认项目配置没有单 target 私有 API：

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

- [ ] **Step 3: Manual command sequence verification**

Use a daylight profile group with at least two light-sensor-capable devices:

1. Select profile `Occupancy sensing with daylight harvesting`.
2. Ensure no current calibrated sensor is selected.
3. Calibrate sensor A.
4. Observe command sequence:
   - SDK calibration commands complete.
   - Sensor A publication is set to group.
   - Profile configuration completes.
   - One `LightLCLightOnOffSetUnacknowledged(true)` is sent to group.
5. Repeat with `Vacancy sensing with daylight harvesting`.
6. Repeat with `Daylight harvesting (Closed loop)`.

Expected:

- Each profile sends AUTO restore once after successful configuration.
- No AUTO restore is sent before profile configuration finishes.

- [ ] **Step 4: Second sensor regression verification**

Use a group that already calibrated sensor A:

1. Select uncalibrated sensor B.
2. Confirm sensor A publication is disabled.
3. Calibrate sensor B.
4. Observe command sequence:
   - Sensor B calibration completes.
   - Sensor B publication is set to group.
   - Group profile configuration completes.
   - One `LightLCLightOnOffSetUnacknowledged(true)` is sent to group.

Expected:

- Group enters AUTO without manually pressing AUTO.
- Sensor A is no longer active publisher.
- Sensor B becomes `group.info.ambientLightSensorNodeAddress`.

- [ ] **Step 5: Failure path verification**

Force or simulate profile configuration failure after calibration.

Expected:

- Failure dialog still appears.
- No `LightLCLightOnOffSetUnacknowledged(true)` is sent.
- Retry behavior remains unchanged.

## Self-Review

- Spec coverage:
  - “所有 daylight profile” covered by `.occupancy_daylight`、`.vacancy_daylight`、`.daylight` guard.
  - “校准完成后立即触发 AUTO” implemented after sensor publication and profile configuration completion.
  - “第 2 个设备” covered because the same `sensorEnabled(...)` path handles newly calibrated and already calibrated selected sensors.
  - “Retry 成功后配置完成” covered by passing completion into retry configuring.
- Placeholder scan:
  - No placeholder markers remain.
  - Verification commands and expected results are explicit.
- Type consistency:
  - Existing names used: `LightSensorCalibrationViewController`、`configuring(lightNodes:)`、`sensorEnabled(sensor:resetCalibrated:result:)`、`LightLCLightOnOffSetUnacknowledged`、`Profile.ProfileType` cases.

## Commit Plan

After implementation and verification:

```bash
git add SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift docs/260608_1139_group_daylight_calibration_auto_plan.md
git commit -m "Fix daylight calibration auto restore"
```
