# EL Controller Professional Manual Add Filter Change Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow `isEmergencySignController = true` devices to appear in Professional mode manual and RSSI range categories, while keeping them hidden from motion sensing and light sensing.

**Architecture:** Keep the behavior in `DeviceAddProfessionalModeController.isVisibleDeviceInCurrentAddMode(_:)`, the existing shared visibility predicate for scan sections, candidate display, candidate count, scan auto-candidate checks, and candidate revoke return flow. Only change the `.manual` branch from filtering emergency sign controllers to allowing them.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SunSmart Professional Add Device flow.

---

## Files

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Reference only: `docs/superpowers/specs/260630_1458_el_controller_professional_manual_add_filter_change_design.md`

## Testing Strategy

The target logic is a private UIKit controller helper driven by BLE `ProvisioningDevice` scan data, so there is no existing isolated unit-test harness for this exact behavior. Verification will use source inspection, whitespace validation, iPhoneOS build validation, and manual BLE acceptance on a real EL Controller device.

## Task 1: Allow Manual Mode Visibility

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Confirm current manual filtering**

Run:

```bash
sed -n '279,293p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: `.manual` currently returns `!isEmergencySignController`, while `.rssiRange` returns `true`.

- [ ] **Step 2: Update the helper**

In `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`, replace the switch body inside `isVisibleDeviceInCurrentAddMode(_:)` with:

```swift
        switch addMode {
        case .manual, .rssiRange:
            return true
        case .motionSensing, .lightSening:
            return !isEmergencySignController && (device.deviceType == .light || device.deviceType == .sensor)
        }
```

This allows EL Controller devices in manual and RSSI range, while keeping motion/light filtering unchanged.

- [ ] **Step 3: Inspect call sites remain centralized**

Run:

```bash
rg -n "isVisibleDeviceInCurrentAddMode|displayedCandidateDevices|displayedCandidateCount|syncCandidateDevicesForCurrentAddMode" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- `displayedCandidateDevices` still filters through `isVisibleDeviceInCurrentAddMode(_:)`.
- `setupDevicesData()` still filters `scanDevices` through `isVisibleDeviceInCurrentAddMode(_:)`.
- scan auto-candidate logic still checks `isVisibleDeviceInCurrentAddMode(newDevice)`.
- candidate revoke flow still uses `isVisibleDeviceInCurrentAddMode(device)` before returning a revoked device to visible scan sections.

- [ ] **Step 4: Commit the source change**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: show EL Controller in manual add mode"
```

Expected: one focused source commit containing only this helper change.

## Task 2: Verify Build and Behavior

**Files:**
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Run whitespace validation**

Run:

```bash
git diff --check HEAD~1..HEAD
```

Expected: no output and exit code `0`.

- [ ] **Step 2: Run iPhoneOS build validation**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Manual BLE acceptance**

On a real `CID 0x0A78 / PID 0x24C1` EL Controller, verify:

- Professional mode > Add based on manual: the device is visible.
- Professional mode > Add based on RSSI range: the device is visible.
- Professional mode > Add based on motion sensing: the device is not visible.
- Professional mode > Add based on light sensing: the device is not visible.
- Ordinary light and sensor devices still appear in motion sensing and light sensing according to the existing `.light || .sensor` rule.

- [ ] **Step 4: Final status check**

Run:

```bash
git status --short
git log --oneline -4
```

Expected:

- No unrelated modified files.
- Latest source commit is `fix: show EL Controller in manual add mode`.
- The design and plan commits remain separate from the source commit.
