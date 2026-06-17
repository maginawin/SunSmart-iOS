# EFC Restore Exclusion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** EFC devices must not appear in Restore Device Data and must not enter the Restore flow.

**Architecture:** Keep the change at the Restore candidate boundary. `DeviceRestoreViewController.shouldIncludeRestoreNode(_:)` becomes the single gate that excludes `.emergencyController` in both default and current-space restore modes. Existing EFC restore helper code remains in place as defensive compatibility but is no longer reachable from the Restore page candidate flow.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing shell contract script, iPhoneOS `xcodebuild`.

---

### Task 1: Contract Guard

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Write the failing contract**

Replace the old positive EFC Restore wiring assertions with assertions that require `DeviceRestoreViewController.shouldIncludeRestoreNode(_:)` to exclude `.emergencyController`.

- [ ] **Step 2: Run contract to verify it fails**

Run: `bash scripts/check_efc_controller_flows.sh`

Expected: FAIL because `DeviceRestoreViewController.swift` still allows `.emergencyController` in Restore candidates.

### Task 2: Restore Filter

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Implement minimal filter change**

Update `shouldIncludeRestoreNode(_:)` so `.all` returns false for EFC nodes and `.currentSpaceNonGateways` also excludes EFC nodes.

- [ ] **Step 2: Run contract to verify it passes**

Run: `bash scripts/check_efc_controller_flows.sh`

Expected: PASS with `EFC controller flow contracts passed.`

### Task 3: Verification

**Files:**
- Verify: full working tree diff and iPhoneOS build

- [ ] **Step 1: Check whitespace**

Run: `git diff --check`

Expected: no output and exit code 0.

- [ ] **Step 2: Build SunSmart for iPhoneOS**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`.
