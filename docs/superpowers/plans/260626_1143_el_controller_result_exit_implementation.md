# EL Controller Result Exit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After EL Controller Function Test returns a terminal result, keep the visible result UI, stop polling, and send Exit Function Test as a fire-and-forget command.

**Architecture:** Keep the behavior inside `ELControllerFunctionTestHelper`, where all Function Test result handling already converges. Update only the invalid result localization text in both supported languages; do not change SDK protocol types or page lifecycle reset behavior.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Sunricher Vendor `0x45`, iPhoneOS `xcodebuild`.

---

## File Structure

- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
  - Responsibility: Send `SET 0x08 Exit Function Test` after a successful `GET/RET 0x03` result has been applied to UI.
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - Responsibility: Update invalid result copy to `Result Invalid - Device in DT or battery depleted`.
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Responsibility: Update invalid result copy to `结果无效 - 设备处于 DT 或电池电量耗尽`.

No project file or SDK changes are required.

---

### Task 1: Send Exit After Terminal Function Test Result

**Files:**
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`

- [ ] **Step 1: Update terminal result handling**

Replace `handleFunctionTestResultStatus(_:)` with:

```swift
private func handleFunctionTestResultStatus(_ status: SunricherVendorStatus) {
    guard status.status.isSuccessful,
          case .elControllerFunctionTestResult(let result) = status.status.parameters else {
        updateFunctionTestState?(.awaiting)
        return
    }

    stopFunctionTestResultPolling()
    applyFunctionTestResult(result)
    exitFunctionTest()
}
```

- [ ] **Step 2: Add fire-and-forget Exit helper**

Add this method after `applyFunctionTestResult(_:)` and before `isExpectedSource(_:)`:

```swift
private func exitFunctionTest() {
    guard isActive,
          let vendorModel = node.sunricherVendorModel else {
        return
    }

    MeshAPI.sendMessage(
        message: SunricherVendorSet(function: .elControllerExitFunctionTest),
        model: vendorModel
    )
}
```

- [ ] **Step 3: Verify helper source**

Run:

```bash
rg -n "exitFunctionTest\\(\\)|elControllerExitFunctionTest|applyFunctionTestResult\\(result\\)" SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
```

Expected:

- `handleFunctionTestResultStatus(_:)` calls `applyFunctionTestResult(result)`.
- `handleFunctionTestResultStatus(_:)` calls `exitFunctionTest()`.
- `exitFunctionTest()` sends `SunricherVendorSet(function: .elControllerExitFunctionTest)`.
- `exitFunctionTest()` does not pass a completion callback.

- [ ] **Step 4: Commit helper change**

Run:

```bash
git add SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
git commit -m "feat: exit EL Controller function test after result"
```

Expected: commit succeeds with only `ELControllerFunctionTestHelper.swift` modified.

---

### Task 2: Update Invalid Result Localizations

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Update English invalid result text**

In `SunSmart/en.lproj/Localizable.strings`, replace:

```text
"el_controller_function_test_invalid" = "Invalid Result";
```

with:

```text
"el_controller_function_test_invalid" = "Result Invalid - Device in DT or battery depleted";
```

- [ ] **Step 2: Update Simplified Chinese invalid result text**

In `SunSmart/zh-Hans.lproj/Localizable.strings`, replace:

```text
"el_controller_function_test_invalid" = "结果无效";
```

with:

```text
"el_controller_function_test_invalid" = "结果无效 - 设备处于 DT 或电池电量耗尽";
```

- [ ] **Step 3: Verify localization values**

Run:

```bash
rg -n "el_controller_function_test_invalid" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

```text
SunSmart/en.lproj/Localizable.strings:<line>:"el_controller_function_test_invalid" = "Result Invalid - Device in DT or battery depleted";
SunSmart/zh-Hans.lproj/Localizable.strings:<line>:"el_controller_function_test_invalid" = "结果无效 - 设备处于 DT 或电池电量耗尽";
```

- [ ] **Step 4: Commit localization change**

Run:

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: clarify EL Controller invalid result text"
```

Expected: commit succeeds with only two localization files modified.

---

### Task 3: Verify Build And Behavior Surface

**Files:**
- Verify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Check status and whitespace**

Run:

```bash
git status --short
git diff --check
```

Expected:

- `git status --short` prints nothing.
- `git diff --check` prints nothing.

- [ ] **Step 2: Verify critical code path**

Run:

```bash
rg -n "stopFunctionTestResultPolling\\(\\)|applyFunctionTestResult\\(result\\)|exitFunctionTest\\(\\)|elControllerExitFunctionTest|Result Invalid - Device in DT or battery depleted|结果无效 - 设备处于 DT 或电池电量耗尽" SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- `handleFunctionTestResultStatus(_:)` still stops polling.
- `handleFunctionTestResultStatus(_:)` still applies the result UI.
- `handleFunctionTestResultStatus(_:)` now calls `exitFunctionTest()`.
- `exitFunctionTest()` sends `.elControllerExitFunctionTest`.
- Both localization files contain the updated invalid result text.

- [ ] **Step 3: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Final status check**

Run:

```bash
git status --short
```

Expected: prints nothing.

---

## Manual Device Verification Matrix

- `GET 0x03` returns pass:
  - Expected: Function Test UI shows `Test Passed`; App sends `SET 0x08`; UI stays Passed.
- `GET 0x03` returns lamp fault:
  - Expected: Function Test UI shows `Lamp Fault`; App sends `SET 0x08`; UI stays Lamp Fault.
- `GET 0x03` returns battery fault:
  - Expected: Function Test UI shows `Battery Fault`; App sends `SET 0x08`; UI stays Battery Fault.
- `GET 0x03` returns circuit fault:
  - Expected: Function Test UI shows `Circuit Fault`; App sends `SET 0x08`; UI stays Circuit Fault.
- `GET 0x03` returns invalid:
  - Expected: Function Test UI shows `Result Invalid - Device in DT or battery depleted`; App sends `SET 0x08`; UI stays Invalid.
- One `GET 0x03` request times out or returns failure:
  - Expected: UI stays Awaiting; polling continues; no Exit is sent.
- Page is popped or another page is pushed:
  - Expected: Function Test UI resets to default because `stopPageSession()` runs.
- Page is opened again:
  - Expected: Function Test starts from default UI and runs `GET 0x01 Device Status`.

---

## Self-Review Notes

- Spec coverage:
  - Terminal result sends Exit: Task 1.
  - UI keeps current result after Exit: Task 1 sends Exit after `applyFunctionTestResult(result)` and does not reset UI.
  - Exit fire-and-forget: Task 1 uses non-ack `MeshAPI.sendMessage`.
  - Invalid copy update: Task 2.
  - Page leave reset unchanged: no changes to `stopPageSession()`, verified in Task 3 and manual matrix.
- Placeholder scan: no red-flag placeholder markers are present.
- Type consistency:
  - Uses existing `SunricherVendorSet(function: .elControllerExitFunctionTest)`.
  - Uses existing localization key `el_controller_function_test_invalid`.
