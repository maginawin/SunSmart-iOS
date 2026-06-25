# EL Controller RX/TX Unknown State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Unknown runtime state for EL Controller RX/TX Connection State while keeping Unknown and Normal on the same online list icon.

**Architecture:** Extend the existing EL Controller runtime state enum from two states to three states. Keep the shared `Node` associated-object state as the single source of truth for Space list and detail page. Reuse the existing RX/TX idle detail UI for Unknown.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `Node` extensions, existing `ELControllerFunctionTestView` and helper.

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+ELControllerRxTx.swift`
  - Owns EL Controller CID/PID matching, runtime RX/TX state storage, state update notification, and list icon mapping.
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
  - Owns RX/TX Cable card display state enum and state-to-localized-key mapping.
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
  - Owns mapping from shared `Node.elControllerRxTxConnectionState` to RX/TX Cable card UI.
- Verify only: `SunSmart/Main/Device/View/DevicesViewCell.swift`
  - Already uses `device.elControllerLightsIconName` for online keybound devices and offline icon override for offline state.
- Verify only: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - Already updates shared RX/TX state from automatic Space read, including timeout/no valid response to Fault.

## Task 1: Extend RX/TX Runtime State

**Files:**
- Modify: `SunSmart/Common/Data/Node+ELControllerRxTx.swift`

- [ ] **Step 1: Inspect current state enum and icon mapping**

Run:

```bash
sed -n '1,90p' SunSmart/Common/Data/Node+ELControllerRxTx.swift
```

Expected: enum contains only `normal` and `fault`; default fallback is `.normal`; icon mapping sends `.fault` to `unsyncIconName`.

- [ ] **Step 2: Add Unknown enum case and make it the default**

Change `ELControllerRxTxConnectionState` to:

```swift
enum ELControllerRxTxConnectionState: Int {
    case unknown = 0
    case normal = 1
    case fault = 2
}
```

Change the getter fallback to:

```swift
return rawValue.flatMap(ELControllerRxTxConnectionState.init(rawValue:)) ?? .unknown
```

- [ ] **Step 3: Map Unknown to the normal online icon**

Change `elControllerLightsIconName` switch to:

```swift
switch elControllerRxTxConnectionState {
case .unknown, .normal:
    return iconName
case .fault:
    return unsyncIconName
}
```

- [ ] **Step 4: Run a focused compile check for Swift syntax through build later**

No standalone unit test target exists for this extension. Continue to Task 2, then validate with the full iPhoneOS build in Task 4.

- [ ] **Step 5: Commit runtime state change**

Run:

```bash
git add SunSmart/Common/Data/Node+ELControllerRxTx.swift
git commit -m "Add EL Controller RXTX unknown state"
```

Expected: commit succeeds with only `Node+ELControllerRxTx.swift` staged.

## Task 2: Show Unknown As RX/TX Idle Prompt On Detail Page

**Files:**
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`

- [ ] **Step 1: Inspect current RX/TX view state**

Run:

```bash
sed -n '20,155p' SunSmart/Main/Device/View/ELControllerFunctionTestView.swift
```

Expected: `RxTxState` contains `idle`, `checking`, `normal`, `fault`; `.idle` already maps to `el_controller_rxtx_start_prompt`.

- [ ] **Step 2: Rename RX/TX idle state to Unknown or add Unknown alias**

Preferred minimal change: add `unknown` and preserve `idle` only if other call sites still need it. Since RX/TX has no separate user-facing idle state after this requirement, replace `idle` with `unknown`.

Change the RX/TX enum to:

```swift
enum RxTxState {
    case unknown
    case checking
    case normal
    case fault
}
```

Change the display switch case from `.idle` to `.unknown`, keeping the same localized key:

```swift
case .unknown:
    return .init(
        buttonTitleKey: "el_controller_rxtx_check_button",
        buttonAlpha: 1,
        rows: [.init(titleKey: "el_controller_rxtx_start_prompt", style: .neutral)],
        showsSpinner: false
    )
```

Change RX/TX view initialization to:

```swift
case .rxTxCable:
    self.currentState = Self.rxTxDisplayState(.unknown)
```

- [ ] **Step 3: Map shared Unknown state to RX/TX Unknown UI**

In `ELControllerFunctionTestHelper.applyStoredRxTxState()`, change the switch to:

```swift
switch node.elControllerRxTxConnectionState {
case .unknown:
    updateRxTxState?(.unknown)
case .normal:
    updateRxTxState?(.normal)
case .fault:
    updateRxTxState?(.fault)
}
```

- [ ] **Step 4: Search for stale `.idle` RX/TX references**

Run:

```bash
rg -n "\\.idle|RxTxState" SunSmart/Main/Device/View/ELControllerFunctionTestView.swift SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: no `.idle` references remain for `RxTxState`; function-test idle references may still exist and are valid.

- [ ] **Step 5: Commit detail UI mapping change**

Run:

```bash
git add SunSmart/Main/Device/View/ELControllerFunctionTestView.swift SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
git commit -m "Show unknown EL Controller RXTX detail state"
```

Expected: commit succeeds with only the two RX/TX detail files staged.

## Task 3: Verify Existing Space Flow Still Matches Requirements

**Files:**
- Verify only: `SunSmart/Main/Device/View/DevicesViewCell.swift`
- Verify only: `SunSmart/Main/Device/Controller/DevicesViewController.swift`

- [ ] **Step 1: Confirm Space list still uses the shared icon helper for online devices**

Run:

```bash
rg -n "elControllerLightsIconName|offlineIconName|iconName" SunSmart/Main/Device/View/DevicesViewCell.swift
```

Expected:

- Online keybound path uses `device.elControllerLightsIconName`.
- Offline path still uses `device.offlineIconName`.

- [ ] **Step 2: Confirm automatic Space read still updates Normal/Fault only**

Run:

```bash
sed -n '288,330p' SunSmart/Main/Device/Controller/DevicesViewController.swift
```

Expected:

- Valid RX/TX status uses `status.status.isSuccessful ? .normal : .fault`.
- Invalid response or timeout uses `.fault`.
- No automatic path writes `.unknown` after startup.

- [ ] **Step 3: Check for compile-required switch updates**

Run:

```bash
rg -n "ELControllerRxTxConnectionState|elControllerRxTxConnectionState|elControllerLightsIconName" SunSmart
```

Expected: every switch over `elControllerRxTxConnectionState` handles `.unknown`, `.normal`, and `.fault`.

- [ ] **Step 4: Commit only if verification required code corrections**

If Task 3 reveals a missing `.unknown` case and a code correction is needed, commit it:

```bash
git add SunSmart/Common/Data/Node+ELControllerRxTx.swift SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
git commit -m "Handle EL Controller RXTX unknown state"
```

Expected: skip this step if no additional corrections are needed.

## Task 4: Final Verification

**Files:**
- Verify all modified source files and working tree.

- [ ] **Step 1: Check formatting and whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Verify no unintended files are modified**

Run:

```bash
git status --short
```

Expected: only intended files appear before final commit, or clean if all task commits are complete.

- [ ] **Step 3: Build iPhoneOS target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Report validation**

Summarize:

- Unknown default added.
- Space list icon mapping unchanged for Unknown/Normal and Fault still unsync.
- Detail page Unknown shows `Tap "Check" to test sign panel connection`.
- Timeout/no valid response still maps to Fault.
- iPhoneOS build result.

## Self-Review

- Spec coverage: covered Unknown default, list icon mapping, detail page prompt, automatic/manual RX/TX read behavior, timeout-as-Fault behavior, and non-goals.
- Placeholder scan: no red-flag placeholder steps remain.
- Type consistency: `ELControllerRxTxConnectionState.unknown` maps to `ELControllerFunctionTestView.RxTxState.unknown`; existing `.normal` and `.fault` names are preserved.
