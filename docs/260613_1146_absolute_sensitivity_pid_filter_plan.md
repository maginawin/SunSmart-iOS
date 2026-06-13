# Absolute Sensitivity PID Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `0x0A78` 指定 PID 的设备统一不支持 Absolute Sensitivity，从而隐藏 Device Parameter Settings 三处相关入口。

**Architecture:** 在 `Node.supportMotionSensitivity` 共享能力判断中增加厂商 + PID 黑名单排除。Device Parameter Settings 的设备列表、Filter 弹窗和 Next 后参数页都继续复用该能力判断，不在 UI 控制器中重复 PID 规则。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - Responsibility: `Node` capability predicates. Add Absolute Sensitivity blacklist here so all consumers share the same rule.
- Verify only: `SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift`
  - Responsibility: device list row rendering. Confirm it still reads `device.supportMotionSensitivity`.
- Verify only: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`
  - Responsibility: device selection, reading parameters, filter data. Confirm Absolute Sensitivity still reads `node.supportMotionSensitivity`.
- Verify only: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
  - Responsibility: Next page parameter module construction. Confirm `.motionSensitivityRange` still depends on `node.supportMotionSensitivity`.

## Task 1: Add Shared PID Blacklist

**Files:**

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [x] **Step 1: Run baseline static check**

Run:

```bash
rg -n "0x2121|0x2122|0x2131|0x2132|0x2133|0x2491|0x2492|0x2493|0x2494" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected before implementation: no matches inside `supportMotionSensitivity`.

- [x] **Step 2: Add the blacklist helper and guard**

In `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`, update the `supportMotionSensitivity` block to this shape:

```swift
    private static let unsupportedMotionSensitivityProductIdentifiers: Set<UInt16> = [
        0x2121,
        0x2122,
        0x2131,
        0x2132,
        0x2133,
        0x2491,
        0x2492,
        0x2493,
        0x2494
    ]

    /// 是否支持移动感应灵敏度
    var supportMotionSensitivity: Bool {
        guard self.sunricherVendorModel != nil else {
            return false
        }
        if self.companyIdentifier == 0x0A78,
           let productIdentifier = self.productIdentifier,
           Self.unsupportedMotionSensitivityProductIdentifiers.contains(productIdentifier) {
            return false
        }
        return self.presenceDetectedSensorModel != nil
    }
```

Keep this inside the existing `Node` extension where `supportMotionSensitivity` already lives.

- [x] **Step 3: Verify blacklist is present**

Run:

```bash
rg -n "unsupportedMotionSensitivityProductIdentifiers|0x2121|0x2494|supportMotionSensitivity" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: the new private static set appears near `supportMotionSensitivity`, and all blacklist PIDs are present.

## Task 2: Verify Device Parameter Settings Still Uses Shared Capability

**Files:**

- Verify only: `SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift`
- Verify only: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift`
- Verify only: `SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`

- [x] **Step 1: Verify device list row uses shared capability**

Run:

```bash
rg -n "type: \\.motionSensitivityRange|isSupported: device\\.supportMotionSensitivity" SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift
```

Expected: `.motionSensitivityRange` row uses `device.supportMotionSensitivity`.

- [x] **Step 2: Verify filter and read flow use shared capability**

Run:

```bash
rg -n "node\\.supportMotionSensitivity|case \\.absoluteSensitivity|parameters\\.append\\(\\.motionSensitivityRange\\)" SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift
```

Expected: Absolute Sensitivity filter support and read parameter inclusion both still depend on `node.supportMotionSensitivity`.

- [x] **Step 3: Verify Next page parameter module uses shared capability**

Run:

```bash
rg -n "node\\.supportMotionSensitivity|parameterDatas\\.append\\(\\.init\\(type: \\.motionSensitivityRange" SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift
```

Expected: `.motionSensitivityRange` is only added for devices whose `supportMotionSensitivity` is true.

## Task 3: Build And Commit

**Files:**

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [x] **Step 1: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [x] **Step 2: Build iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 3: Review diff**

Run:

```bash
git diff -- SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: only the Absolute Sensitivity PID blacklist helper and guard are changed.

- [x] **Step 4: Commit implementation**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift docs/260613_1146_absolute_sensitivity_pid_filter_plan.md
git commit -m "fix: filter absolute sensitivity by PID"
```

Expected: one implementation commit containing the shared capability fix and this plan.

## Self-Review

- Spec coverage: Task 1 implements the `0x0A78` + PID blacklist in the shared capability predicate. Task 2 verifies all three requested UI entry points still consume that predicate. Task 3 verifies formatting, build, diff, and commit.
- Placeholder scan: no placeholder work remains.
- Type consistency: PID values use `UInt16`, matching `companyIdentifier` and `productIdentifier`.
