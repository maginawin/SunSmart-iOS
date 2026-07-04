# Lab Light Group Control TTL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Lab-only TTL override for phone-originated Light and Group control commands.

**Architecture:** Store the Lab setting in `LabSettings`, expose one optional TTL getter, and route only approved Light / Group command entry points through a small app-side helper. The helper passes `defaultTTL` to existing SDK `MeshAPI.sendMessage` calls without changing SDK global TTL or device Default TTL.

**Tech Stack:** Swift, UIKit, UserDefaults, NordicSigMeshSDK, shell contract scripts, iPhoneOS `xcodebuild`.

---

### Task 1: Contract Script

**Files:**
- Create: `scripts/check_lab_light_group_ttl.sh`

- [ ] **Step 1: Write a failing script**

Create a script that checks:
- `LabSettings` has `lightGroupControlTTLOverride`
- `LightGroupControlCommandSender.swift` exists
- Light and Group controllers call the helper
- `LightAckProgressTracker.send` accepts `defaultTTL`
- Lab localized strings exist in English and Simplified Chinese
- Known out-of-scope files do not reference the helper

- [ ] **Step 2: Run script to verify RED**

Run: `bash scripts/check_lab_light_group_ttl.sh`

Expected: FAIL because helper and settings do not exist yet.

### Task 2: Lab Settings and UI

**Files:**
- Modify: `SunSmart/Common/Data/LabSettings.swift`
- Modify: `SunSmart/Main/Site/Controller/LabViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add Lab settings**

Add UserDefaults-backed values:
- `overrideLightGroupControlTTL: Bool`
- `lightGroupControlTTL: UInt8`
- `lightGroupControlTTLOverride: UInt8?`

- [ ] **Step 2: Add Lab rows**

Add switch, TTL value row, and scope description. The description must say this affects only Light and Group control commands.

- [ ] **Step 3: Add localized strings**

Add English and Simplified Chinese keys for the switch, TTL row, and scope description.

### Task 3: Light / Group Command Helper

**Files:**
- Create: `SunSmart/Common/Data/LightGroupControlCommandSender.swift`
- Modify: `SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift`

- [ ] **Step 1: Add helper**

Create a helper that sends:
- node on/off
- node lightness
- node CCT
- node identify
- group on/off
- group lightness
- group CCT
- all lights on/off
- all lights lightness

Each method reads `LabSettings.lightGroupControlTTLOverride` and passes it as `defaultTTL`.

- [ ] **Step 2: Update ACK tracker**

Allow `LightAckProgressTracker.send` to accept `defaultTTL: UInt8? = nil` and pass it to `MeshAPI.sendMessage`.

### Task 4: Wire Approved Entry Points

**Files:**
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Modify: `SunSmart/Main/Group/Controller/GroupsViewController.swift`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Wire Light page**

Use the helper for single light on/off, all lights on/off, and all lights brightness.

- [ ] **Step 2: Wire Light detail**

Use the helper for single light on/off, brightness, CCT, and Identify.

- [ ] **Step 3: Wire Group pages**

Use the helper for group list on/off, group detail on/off, group brightness, group CCT, and group member single-light on/off.

### Task 5: Verification

**Files:**
- No production files unless verification finds a scoped issue.

- [ ] **Step 1: Run contract script**

Run: `bash scripts/check_lab_light_group_ttl.sh`

Expected: PASS.

- [ ] **Step 2: Run whitespace check**

Run: `git diff --check`

Expected: no output.

- [ ] **Step 3: Run iPhoneOS build**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: build succeeds.
