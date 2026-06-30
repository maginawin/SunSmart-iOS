# EL Controller Professional Add Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure EL Controller devices identified by `isEmergencySignController = true` appear only in Professional mode's Add based on RSSI range category.

**Architecture:** Keep the fix in `DeviceAddProfessionalModeController`'s existing mode-visibility helper so scan list grouping, candidate display, candidate count, revoke flow, and scan auto-candidate checks continue to share one source of truth. Preserve `devices_config.json` and `Node.isEmergencySignController` semantics.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing SunSmart Add Device Professional flow.

---

## Files

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Reference only: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Reference only: `SunSmart/devices_config.json`
- Reference only: `docs/superpowers/specs/260630_1146_el_controller_professional_add_filter_design.md`

## Testing Strategy

This behavior sits inside a private UIKit controller helper and depends on `ProvisioningDevice` objects produced by BLE scan callbacks. There is no existing isolated unit-test harness for `DeviceAddProfessionalModeController` visibility logic. Verification will therefore use:

- Source-backed pre/post inspection of the exact helper and call sites.
- `git diff --check`.
- iPhoneOS `xcodebuild` using the workspace command required by project rules.
- Manual BLE acceptance on a real `CID 0x0A78 / PID 0x24C1` device.

## Task 1: Update Professional Mode Visibility Predicate

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Confirm the current broad visibility rule**

Run:

```bash
sed -n '270,288p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: `isVisibleDeviceInCurrentAddMode(_:)` allows `.motionSensing` and `.lightSening` when `device.deviceType == .light || device.deviceType == .sensor`, and returns `true` for `.manual, .rssiRange`.

- [ ] **Step 2: Replace the helper with the narrow emergency-sign rule**

In `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`, replace the existing `isVisibleDeviceInCurrentAddMode(_:)` implementation with:

```swift
    private func isVisibleDeviceInCurrentAddMode(_ device: ProvisioningDevice) -> Bool {
        let isEmergencySignController = Node.isEmergencySignController(
            companyIdentifier: device.cid,
            productIdentifier: device.pid
        )

        switch addMode {
        case .rssiRange:
            return true
        case .manual:
            return !isEmergencySignController
        case .motionSensing, .lightSening:
            return !isEmergencySignController && (device.deviceType == .light || device.deviceType == .sensor)
        }
    }
```

This keeps RSSI range behavior unchanged while hiding emergency sign controllers from manual, motion sensing, and light sensing.

- [ ] **Step 3: Inspect the call sites remain centralized**

Run:

```bash
rg -n "isVisibleDeviceInCurrentAddMode|displayedCandidateDevices|displayedCandidateCount|syncCandidateDevicesForCurrentAddMode" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- `displayedCandidateDevices` still filters through `isVisibleDeviceInCurrentAddMode(_:)`.
- `setupDevicesData()` still filters `scanDevices` through `isVisibleDeviceInCurrentAddMode(_:)`.
- scan auto-candidate logic still checks `isVisibleDeviceInCurrentAddMode(newDevice)`.
- candidate revoke flow still uses `isVisibleDeviceInCurrentAddMode(device)` before returning a revoked device to the visible scan sections.

- [ ] **Step 4: Commit the source change**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: filter EL Controller professional add modes"
```

Expected: one focused commit containing only the Professional Add Mode visibility change.

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

- Professional mode > Add based on RSSI range: the device is visible and can be selected.
- Professional mode > Add based on manual: the device is not visible.
- Professional mode > Add based on motion sensing: the device is not visible.
- Professional mode > Add based on light sensing: the device is not visible.
- Ordinary light and sensor devices still appear in motion sensing and light sensing according to the existing `.light || .sensor` rule.

- [ ] **Step 4: Final status check**

Run:

```bash
git status --short
git log --oneline -3
```

Expected:

- No unrelated modified files.
- Latest source commit is `fix: filter EL Controller professional add modes`.
- The earlier plan/spec commits remain separate from the source commit.
