# Sensor Calibrate SIGTRAP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复光照传感器校准中 `MeshSensorCalibrateManager.setCalibrateRate()` 因 `UInt16` 下溢/溢出触发 `SIGTRAP` 的崩溃。

**Architecture:** 采用双层防护：App 层在用户输入进入 SDK 前拦截明显不合法的开/关灯照度值，SDK 层对所有倍率与拐点计算做安全算术边界处理。SDK 不再依赖调用方保证输入正确，异常数据统一走既有 `CalibrateError` 失败回调。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Swift Package tests、xcodebuild。

---

## File Structure

- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`
  - 职责：校准页用户输入校验与提示。
  - 本次只在 `calibrationBtnAction()` 入口增加开/关灯照度关系校验。

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
  - 职责：传感器自动校准流程、拐点搜索、倍率计算。
  - 本次增加安全差值计算，避免 `UInt16` 直接做可能溢出/下溢的加减法。

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SensorCalibrateMathTests.swift`
  - 职责：覆盖校准倍率和阈值比较的纯数学边界行为。
  - 计划将可测逻辑抽成 SDK 内部静态 helper，避免测试直接驱动蓝牙/Mesh 流程。

## Current Root Cause

Bugly 栈落在：

- `NordicSigMeshSDK.MeshSensorCalibrateManager.setCalibrateRate()`
- 上层为 `setLightingAndSensorInflectionPoint()` async 任务。

当前高风险代码点：

- `ambientLightOnLux - ambientLightOffLux`
- `lightOnLux - lightOffLux`
- `baseLux + threshold`

`UInt16` 在 Swift 中发生下溢/溢出会触发运行时 trap。App 入口当前只校验 `onLux/offLux` 是否在 `UInt16` 范围内，没有校验 `onLux > offLux`。当用户输入反了，或现场读数异常导致开灯照度不大于关灯照度，就会在 SDK 中崩溃。

## Task 1: Add SDK Math Helpers and Tests

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SensorCalibrateMathTests.swift`

- [ ] **Step 1: Add failing tests for safe unsigned math**

Create `SensorCalibrateMathTests.swift` with tests for these cases:

- `positiveDifference(120, 100)` returns `20`.
- `positiveDifference(100, 100)` returns `nil` when strict positive is required.
- `positiveDifference(80, 100)` returns `nil` and does not trap.
- `isAtLeastWithThreshold(value: 12, base: 10, threshold: 2)` returns `true`.
- `isAtLeastWithThreshold(value: 11, base: 10, threshold: 2)` returns `false`.
- `isAtLeastWithThreshold(value: UInt16.max, base: UInt16.max, threshold: 2)` returns `false` and does not trap.
- `clampedRate(numerator: 100, denominator: 10)` returns `1000`.
- `clampedRate(numerator: 10000, denominator: 1)` returns `5000`.

Run:

`swift test --filter SensorCalibrateMathTests`

Expected before implementation:

- FAIL because helper methods do not exist.

- [ ] **Step 2: Add internal helper methods**

In `MeshSensorCalibrateManager`, add internal static helpers close to the class definition:

- `positiveDifference(_ lhs: UInt16, _ rhs: UInt16) -> UInt16?`
  - returns `nil` when `lhs <= rhs`.
  - returns `lhs - rhs` after converting to `Int`.

- `nonNegativeDifference(_ lhs: UInt16, _ rhs: UInt16) -> UInt16?`
  - returns `nil` when `lhs < rhs`.
  - returns `lhs - rhs` after converting to `Int`.

- `isAtLeastWithThreshold(value: UInt16, base: UInt16, threshold: UInt16) -> Bool`
  - compare with `Int(value) >= Int(base) + Int(threshold)`.
  - avoid `base + threshold` on `UInt16`.

- `clampedRate(numerator: UInt16, denominator: UInt16, maxRate: Int = 5000) -> UInt16`
  - compute `Double(max(numerator, 1)) / Double(max(denominator, 1)) * 100`.
  - clamp to `0...maxRate`.

Keep helpers `internal` so the SDK test target can access them through `@testable import NordicSigMeshSDK`.

- [ ] **Step 3: Run helper tests**

Run:

`swift test --filter SensorCalibrateMathTests`

Expected:

- PASS.

## Task 2: Harden `setCalibrateRate()`

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SensorCalibrateMathTests.swift`

- [ ] **Step 1: Replace unsafe differences**

In `setCalibrateRate()`:

- Replace `ambientLightOnLux - ambientLightOffLux` with `positiveDifference(ambientLightOnLux, ambientLightOffLux)`.
- Replace `lightOnLux - lightOffLux` with `positiveDifference(lightOnLux, lightOffLux)`.
- If either difference is `nil`, set `calibrateError = .inflectionPointError`, call `calibrateFailed()`, and return before sending `.daylightCalibrateRate`.

Rationale:

- Calibration rate is only meaningful when both App measured lux and sensor lux increase after lights turn on.
- Equal or reversed values should fail gracefully instead of producing zero/negative rate or crashing.

- [ ] **Step 2: Use helper for rate calculation**

Compute:

- `ambientLightRateValue` from `clampedRate(numerator: ambientLightOffLux, denominator: max(lightOffLux, 1))`.
- `sensorRateValue` from `clampedRate(numerator: ambientDelta, denominator: sensorDelta)`.

Do not perform direct `UInt16` subtraction in this method.

- [ ] **Step 3: Run SDK tests**

Run:

`swift test --filter SensorCalibrateMathTests`

Expected:

- PASS.

## Task 3: Harden Inflection Point Math

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshSensorCalibrateManager.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SensorCalibrateMathTests.swift`

- [ ] **Step 1: Replace `baseLux + threshold` checks**

In these methods:

- `findTurningPointEfficiently(zeroPoint:threshold:)`
- `fineSearchInSegment(before:current:baseLux:threshold:)`
- `checkTurningPointWithNewData(_:historicalData:baseLux:threshold:)`

Replace checks shaped like `value >= baseLux + threshold` with:

- `MeshSensorCalibrateManager.isAtLeastWithThreshold(value: value, base: baseLux, threshold: threshold)`

- [ ] **Step 2: Replace inflection point subtraction with safe differences**

In `setLightingAndSensorInflectionPoint()`:

- Keep the existing `guard onPoint.lux >= offPoint.lux`.
- Compute `minLuxDelta` using `nonNegativeDifference(resultPoint.lux, offPoint.lux)`.
- Compute `maxLuxDelta` using `nonNegativeDifference(onPoint.lux, offPoint.lux)`.
- If either delta is `nil`, set `.inflectionPointError`, call `calibrateFailed()`, and return.
- Use those deltas for `.daylightCalibrateIlluminanceInflectionPoint` and `sensorCalibrationData`.

This prevents `resultPoint.lux - offPoint.lux` from trapping if the search result is lower than the zero point.

- [ ] **Step 3: Run SDK tests**

Run:

`swift test --filter SensorCalibrateMathTests`

Expected:

- PASS.

## Task 4: Add App-Level Input Guard

**Files:**
- Modify: `SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift`

- [ ] **Step 1: Add guard in `calibrationBtnAction()`**

After existing `onLux/offLux` range validation and before firmware version check:

- Require `onLux > offLux`.
- If validation fails, show the existing `"checking_correct_failure".localizedString` message through `showCalibrationFailed(message:)`.
- Return before calling `showConnecting()` or `MeshSensorCalibrateManager.manager.calibrate(...)`.

Rationale:

- Avoid adding localized strings in this fix because resource changes affect all brand targets.
- Existing message already maps to “检查安装是否正确后重试”，适合开/关照度关系不成立的失败路径。

- [ ] **Step 2: Manually verify control flow by reading**

Confirm invalid input returns before:

- `showConnecting()`
- `MeshSensorCalibrateManager.manager.calibrate(...)`

Confirm valid input still reaches the existing SDK call.

## Task 5: Verification

**Files:**
- Verify modified SDK and App files only.

- [ ] **Step 1: Run targeted SDK test**

From `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

`swift test --filter SensorCalibrateMathTests`

Expected:

- PASS.

- [ ] **Step 2: Run broader SDK test if time allows**

From `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`:

`swift test`

Expected:

- PASS, or document unrelated pre-existing failures with exact failing test names.

- [ ] **Step 3: Build main App target**

From `/Users/maginawin/Developer/iOS/YKH/sun-smart/.worktrees/k8-ac-260527`:

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected:

- `** BUILD SUCCEEDED **`

- [ ] **Step 4: Optional brand-target build check**

Because SDK is shared across targets, if the change is ready for release, also build:

- `Archipelago`
- `SylSmart`
- `SLG Sync Plus`

Use the same `iphoneos generic/platform=iOS CODE_SIGNING_ALLOWED=NO build` shape.

## Manual Regression Checklist

- [ ] 输入 `onLux < offLux`：不进入连接/校准流程，不崩溃，显示失败提示。
- [ ] 输入 `onLux == offLux`：不进入连接/校准流程，不崩溃，显示失败提示。
- [ ] 输入 `onLux > offLux`：继续原有校准流程。
- [ ] 传感器无响应：仍走原有连接失败/校准失败提示。
- [ ] 灯光对传感器无有效影响：仍走原有 `checking_correct_failure` 提示。
- [ ] 校准成功后：仍清理 `daylightCalibrationData`、重启传感器启用流程、发送 `spaceDataChangedNotificaitonName`。

## Self-Review

- Spec coverage: 覆盖 Bugly `SIGTRAP` 主因 `ambientLightOnLux - ambientLightOffLux`，同时覆盖同一流程中其他 `UInt16` 风险点。
- Placeholder scan: 无待定步骤；每个任务都有文件、动作、命令和期望结果。
- Type consistency: 使用现有 `UInt16`、`CalibrateError`、`showCalibrationFailed(message:)`、`MeshSensorCalibrateManager` 类型，不引入新依赖。
