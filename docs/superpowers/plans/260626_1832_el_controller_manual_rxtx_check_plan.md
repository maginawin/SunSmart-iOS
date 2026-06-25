# EL Controller Manual RX/TX Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove automatic RX/TX Cable Connection reads from Space entry and make manual Check the only RX/TX read path for EL Controller devices.

**Architecture:** Keep `Node.elControllerRxTxConnectionState` as the shared runtime state. Reset supported EL Controller nodes to Unknown when `DevicesViewController` is created for a Space. Remove the old automatic Space read methods and observer, while preserving `ELControllerFunctionTestHelper.checkRxTxCable()` as the only GET RX/TX entry.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing mesh notification flow.

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - Remove Space-level automatic RX/TX Cable Connection read scheduling.
  - Reset EL Controller RX/TX runtime state to Unknown when entering Space.
- Verify only: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
  - Keep manual RX/TX Check as the only command sender for `.elControllerRxTxCableConnection`.
- Verify only: `SunSmart/Common/Data/Node+ELControllerRxTx.swift`
  - Confirm Unknown is already the default runtime state and list icon mapping remains correct.

## Task 1: Reset RX/TX State On Space Entry

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`

- [ ] **Step 1: Inspect the Space entry lifecycle**

Run:

```bash
sed -n '120,190p' SunSmart/Main/Device/Controller/DevicesViewController.swift
```

Expected: `viewDidLoad()` calls `addObservation()` before the Space loading and permission flow.

- [ ] **Step 2: Add an Unknown reset call in `viewDidLoad()`**

Add this call immediately after `addObservation()`:

```swift
resetELControllerRxTxConnectionStates()
```

Expected local shape:

```swift
addObservation()
resetELControllerRxTxConnectionStates()
```

- [ ] **Step 3: Add the reset helper**

Add this private method near the observation helpers:

```swift
private func resetELControllerRxTxConnectionStates() {
    MeshNetworkManager.instance.realNodes
        .filter { $0.supportsELControllerRxTxConnectionState }
        .forEach { $0.updateELControllerRxTxConnectionState(.unknown) }
}
```

Expected behavior:

- Only EL Controller nodes with CID `0x0A78`, PID `0x24C1` are reset.
- Existing `updateELControllerRxTxConnectionState(_:)` posts `deviceStateUpdateNotificationName` only when the state actually changes.
- Nodes that are already Unknown do not produce unnecessary notifications.

- [ ] **Step 4: Commit Space-entry reset**

Run:

```bash
git add SunSmart/Main/Device/Controller/DevicesViewController.swift
git commit -m "Reset EL Controller RXTX state on space entry"
```

Expected: commit succeeds with only `DevicesViewController.swift` staged.

## Task 2: Remove Space Automatic RX/TX Read

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`

- [ ] **Step 1: Remove old automatic read state**

Delete these properties:

```swift
private var hasRequestedELControllerRxTxConnectionState = false
private var deviceStateUpdateObserver: NSObjectProtocol?
```

- [ ] **Step 2: Remove deinit cleanup for the deleted observer**

Delete this block from `deinit`:

```swift
if let deviceStateUpdateObserver {
    NotificationCenter.default.removeObserver(deviceStateUpdateObserver)
}
```

- [ ] **Step 3: Remove first-connect automatic RX/TX scheduling**

Delete this call from the first Mesh connection branch:

```swift
self.scheduleInitialELControllerRxTxConnectionCheckIfNeeded()
```

Expected: `getMeshDistribution()` remains, and the later schedule-time sync logic remains unchanged.

- [ ] **Step 4: Remove state-update observer used only for automatic RX/TX read**

Delete this observer registration from `addObservation()`:

```swift
deviceStateUpdateObserver = NotificationCenter.default.addObserver(
    forName: .init(deviceStateUpdateNotificationName),
    object: nil,
    queue: .main
) { [weak self] notification in
    self?.scheduleInitialELControllerRxTxConnectionCheckIfNeeded(sourceNode: notification.object as? Node)
}
```

Expected: Device list child controllers still listen to `deviceStateUpdateNotificationName` themselves, so list refresh after manual Check remains available.

- [ ] **Step 5: Remove automatic RX/TX read helper methods**

Delete these methods from `DevicesViewController.swift`:

```swift
private func scheduleInitialELControllerRxTxConnectionCheckIfNeeded(sourceNode: Node? = nil) { ... }
private func requestInitialELControllerRxTxConnectionState() { ... }
private func requestELControllerRxTxConnectionState(node: Node, vendorModel: Model) { ... }
```

Expected: `DevicesViewController.swift` no longer sends `SunricherVendorGet(function: .elControllerRxTxCableConnection)`.

- [ ] **Step 6: Commit automatic read removal**

Run:

```bash
git add SunSmart/Main/Device/Controller/DevicesViewController.swift
git commit -m "Remove automatic EL Controller RXTX read"
```

Expected: commit succeeds with only `DevicesViewController.swift` staged.

## Task 3: Verify Manual Check Is The Only RX/TX Read Path

**Files:**
- Verify only: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- Verify only: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
- Verify only: `SunSmart/Common/Data/Node+ELControllerRxTx.swift`

- [ ] **Step 1: Confirm automatic methods are gone**

Run:

```bash
rg -n "scheduleInitialELControllerRxTxConnectionCheckIfNeeded|requestInitialELControllerRxTxConnectionState|requestELControllerRxTxConnectionState|hasRequestedELControllerRxTxConnectionState|deviceStateUpdateObserver" SunSmart/Main/Device/Controller/DevicesViewController.swift
```

Expected: no output.

- [ ] **Step 2: Confirm only manual helper sends RX/TX GET**

Run:

```bash
rg -n "SunricherVendorGet\\(function: \\.elControllerRxTxCableConnection\\)|elControllerRxTxCableConnection" SunSmart/Main/Device SunSmart/Common
```

Expected:

- `ELControllerFunctionTestHelper.checkRxTxCable()` sends `SunricherVendorGet(function: .elControllerRxTxCableConnection)`.
- `ELControllerFunctionTestHelper.handleStatus(_:)` still handles `.elControllerRxTxCableConnection`.
- No `DevicesViewController.swift` match remains for sending RX/TX GET.

- [ ] **Step 3: Confirm Unknown default and UI mapping remain**

Run:

```bash
sed -n '1,80p' SunSmart/Common/Data/Node+ELControllerRxTx.swift
sed -n '155,180p' SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
```

Expected:

- `ELControllerRxTxConnectionState` contains `.unknown`, `.normal`, `.fault`.
- Getter fallback is `.unknown`.
- Unknown and Normal map to `iconName`; Fault maps to `unsyncIconName`.
- Detail helper maps shared `.unknown` to RX/TX card `.unknown`.

- [ ] **Step 4: Commit only if verification required code corrections**

If Task 3 reveals a missing correction, commit the correction:

```bash
git add SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift SunSmart/Common/Data/Node+ELControllerRxTx.swift
git commit -m "Keep EL Controller RXTX manual check only"
```

Expected: skip this step if no corrections are needed.

## Task 4: Final Verification

**Files:**
- Verify all modified source files and working tree.

- [ ] **Step 1: Check formatting and whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Verify working tree state**

Run:

```bash
git status --short
```

Expected: clean if all task commits are complete.

- [ ] **Step 3: Build iPhoneOS target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Report validation**

Summarize:

- Space entry no longer auto-reads RX/TX Cable Connection.
- Space entry resets EL Controller RX/TX state to Unknown.
- Manual Check remains the only RX/TX GET sender.
- Manual Check success/failure/timeout behavior remains unchanged.
- iPhoneOS build result.

## Self-Review

- Spec coverage: covered removal of first-connect automatic read, removal of state-update补触发, Space-entry Unknown reset, manual Check preservation, UI mapping, and validation.
- Placeholder scan: no red-flag placeholder steps remain.
- Type consistency: all planned code uses existing `Node.updateELControllerRxTxConnectionState(.unknown)` and existing `ELControllerFunctionTestHelper.checkRxTxCable()`.
