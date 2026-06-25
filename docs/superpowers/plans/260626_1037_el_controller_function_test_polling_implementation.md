# EL Controller Function Test Polling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an App-layer helper that polls EL Controller Function Test results every 2 seconds after Start succeeds or Device Status reports Function testing, and stops/reset UI when the page disappears.

**Architecture:** Add a focused `ELControllerFunctionTestHelper` under the Device View area to own EL Controller status flow, polling timer, Mesh command sending, and status-to-UI mapping. Keep `DeviceLightViewController` responsible only for creating the helper, wiring UI actions, forwarding received vendor status, and coordinating page lifecycle.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SIG Mesh Sunricher Vendor `0x45`, `Timer`, `xcodebuild` iPhoneOS verification.

---

## File Structure

- Create: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
  - Responsibility: EL Controller page-session state machine, `GET 0x01`, `SET 0x07`, `GET 0x03` polling, `GET 0x00`, status parsing, timer cleanup, UI callback dispatch.
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - Responsibility: create and own helper, bind cards to helper actions, call helper on `viewWillAppear` / `viewWillDisappear`, forward `SunricherVendorStatus`.
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - Responsibility: add helper file reference and include it in the same four app target source phases as `ELControllerFunctionTestView.swift`.

No SDK source changes are required; SDK already exposes `SunricherVendorGet`, `SunricherVendorSet`, `ELControllerDeviceStatus`, and `ELControllerFunctionTestResult`.

---

### Task 1: Add EL Controller Function Test Helper

**Files:**
- Create: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`

- [ ] **Step 1: Create helper file**

Create `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift` with this implementation:

```swift
//
//  ELControllerFunctionTestHelper.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/26.
//

import Foundation
import NordicSigMeshSDK

final class ELControllerFunctionTestHelper {

    var updateFunctionTestState: ((ELControllerFunctionTestView.FunctionTestState) -> Void)?
    var updateRxTxState: ((ELControllerFunctionTestView.RxTxState) -> Void)?
    var showOfflineMessage: (() -> Void)?

    private let node: Node
    private var isActive = false
    private var resultPollingTimer: Timer?
    private var isResultRequestInFlight = false

    init(node: Node) {
        self.node = node
    }

    deinit {
        stopFunctionTestResultPolling()
    }

    func startPageSession() {
        isActive = true
        resetUI()

        guard canSendCommands,
              let vendorModel = node.sunricherVendorModel else {
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .elControllerDeviceStatus),
            model: vendorModel,
            timeout: 3
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerDeviceStatus,
                      status.status.isSuccessful,
                      case .elControllerDeviceStatus(let deviceStatus) = status.status.parameters else {
                    return
                }
                self.applyDeviceStatus(deviceStatus)
            }
        }
    }

    func stopPageSession() {
        isActive = false
        stopFunctionTestResultPolling()
        resetUI()
    }

    func startFunctionTest() {
        guard canSendCommands else {
            showOfflineMessage?()
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            updateFunctionTestState?(.failed)
            return
        }

        isActive = true
        stopFunctionTestResultPolling()
        updateFunctionTestState?(.awaiting)

        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .elControllerStartFunctionTest),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerStartFunctionTest,
                      status.status.isSuccessful else {
                    self.updateFunctionTestState?(.failed)
                    return
                }
                self.updateFunctionTestState?(.awaiting)
                self.startFunctionTestResultPolling()
            }
        }
    }

    func checkRxTxCable() {
        guard canSendCommands else {
            showOfflineMessage?()
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            updateRxTxState?(.fault)
            return
        }

        updateRxTxState?(.checking)
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .elControllerRxTxCableConnection),
            model: vendorModel,
            timeout: 5
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerRxTxCableConnection,
                      status.status.isSuccessful else {
                    self.updateRxTxState?(.fault)
                    return
                }
                self.updateRxTxState?(.normal)
            }
        }
    }

    @discardableResult
    func handleStatus(_ status: SunricherVendorStatus, sentFrom source: Address) -> Bool {
        guard isActive, isExpectedSource(source) else {
            return false
        }

        switch status.status.code {
        case .elControllerRxTxCableConnection:
            updateRxTxState?(status.status.isSuccessful ? .normal : .fault)
            return true
        case .elControllerDeviceStatus:
            guard status.status.isSuccessful,
                  case .elControllerDeviceStatus(let deviceStatus) = status.status.parameters else {
                return true
            }
            applyDeviceStatus(deviceStatus)
            return true
        case .elControllerFunctionTestResult:
            handleFunctionTestResultStatus(status)
            return true
        case .elControllerStartFunctionTest,
                .elControllerExitFunctionTest:
            return true
        default:
            return false
        }
    }

    private var canSendCommands: Bool {
        node.isKeybindComplete && node.state
    }

    private func resetUI() {
        updateFunctionTestState?(.idle)
        updateRxTxState?(.idle)
    }

    private func applyDeviceStatus(_ deviceStatus: ELControllerDeviceStatus) {
        if deviceStatus.isFunctionTesting {
            updateFunctionTestState?(.awaiting)
            startFunctionTestResultPolling()
        } else {
            stopFunctionTestResultPolling()
            updateFunctionTestState?(.idle)
        }
    }

    private func startFunctionTestResultPolling() {
        stopFunctionTestResultPolling()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.requestFunctionTestResult()
        }
        RunLoop.main.add(timer, forMode: .common)
        resultPollingTimer = timer
    }

    private func stopFunctionTestResultPolling() {
        resultPollingTimer?.invalidate()
        resultPollingTimer = nil
        isResultRequestInFlight = false
    }

    private func requestFunctionTestResult() {
        guard isActive,
              !isResultRequestInFlight,
              let vendorModel = node.sunricherVendorModel else {
            return
        }

        isResultRequestInFlight = true
        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .elControllerFunctionTestResult),
            model: vendorModel,
            timeout: 1.8
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isResultRequestInFlight = false
                guard self.isActive else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerFunctionTestResult else {
                    self.updateFunctionTestState?(.awaiting)
                    return
                }
                self.handleFunctionTestResultStatus(status)
            }
        }
    }

    private func handleFunctionTestResultStatus(_ status: SunricherVendorStatus) {
        guard status.status.isSuccessful,
              case .elControllerFunctionTestResult(let result) = status.status.parameters else {
            updateFunctionTestState?(.awaiting)
            return
        }

        stopFunctionTestResultPolling()
        applyFunctionTestResult(result)
    }

    private func applyFunctionTestResult(_ result: ELControllerFunctionTestResult) {
        guard result.isValid else {
            updateFunctionTestState?(.invalid)
            return
        }
        guard result.hasFault else {
            updateFunctionTestState?(.passed)
            return
        }
        updateFunctionTestState?(.faults(
            lamp: result.lampFault,
            battery: result.batteryFault,
            circuit: result.circuitFault
        ))
    }

    private func isExpectedSource(_ source: Address) -> Bool {
        if source == node.primaryUnicastAddress {
            return true
        }
        return node.sunricherVendorModel?.parentElement?.unicastAddress == source
    }
}
```

- [ ] **Step 2: Review helper behavior against the spec**

Run:

```bash
rg -n "startPageSession|stopPageSession|startFunctionTestResultPolling|timeout: 1.8|elControllerDeviceStatus|elControllerFunctionTestResult" SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
```

Expected: output includes all of these entries:

- `func startPageSession()`
- `func stopPageSession()`
- `private func startFunctionTestResultPolling()`
- `timeout: 1.8`
- `.elControllerDeviceStatus`
- `.elControllerFunctionTestResult`

- [ ] **Step 3: Commit helper file**

Run:

```bash
git add SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift
git commit -m "feat: add EL Controller function test helper"
```

Expected: commit succeeds with one new Swift file.

---

### Task 2: Wire Helper Into DeviceLightViewController

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Add helper property**

In `DeviceLightViewController`, near the existing EL Controller views:

```swift
private var elFunctionTestView: ELControllerFunctionTestView?
private var elRxTxCableView: ELControllerFunctionTestView?
private var elControllerFunctionTestHelper: ELControllerFunctionTestHelper?
```

- [ ] **Step 2: Start helper when page appears**

Replace `viewWillAppear(_:)` with:

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    MeshLibManager.manager.messageDelegate = self
    // 更新数据
    updateData()

    if supportsELControllerLocalFunctionViews {
        elControllerFunctionTestHelper?.startPageSession()
    }

    if !node.isEmergencySignController, node.ambientLightSensorModel != nil {
        getNodeAmbientSensorLux()
    }
}
```

- [ ] **Step 3: Stop helper when page disappears**

Replace the commented `viewDidDisappear` block with this real lifecycle method:

```swift
override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)

    elControllerFunctionTestHelper?.stopPageSession()
}
```

Keep `deinit` unchanged so it still restores `MeshLibManager.manager.messageDelegate`.

- [ ] **Step 4: Create helper and bind card actions**

Inside `setupEmergencySignUI()`, replace the current EL Controller card setup block with:

```swift
if supportsELControllerLocalFunctionViews {
    let functionTestView = ELControllerFunctionTestView(kind: .functionTest)
    contentView.addSubview(functionTestView)
    functionTestView.snp.makeConstraints { make in
        make.top.equalTo(identifyButton.snp.bottom).offset(SCRYFit(30))
        make.left.equalTo(SCRXFrom(16))
        make.right.equalTo(SCRXFrom(-16))
    }
    elFunctionTestView = functionTestView

    let rxTxCableView = ELControllerFunctionTestView(kind: .rxTxCable)
    contentView.addSubview(rxTxCableView)
    rxTxCableView.snp.makeConstraints { make in
        make.top.equalTo(functionTestView.snp.bottom).offset(SCRYFit(16))
        make.left.right.equalTo(functionTestView)
        make.bottom.lessThanOrEqualToSuperview().offset(SCRYFit(-8))
    }
    elRxTxCableView = rxTxCableView

    let helper = ELControllerFunctionTestHelper(node: node)
    helper.updateFunctionTestState = { [weak functionTestView] state in
        functionTestView?.applyFunctionTestState(state)
    }
    helper.updateRxTxState = { [weak rxTxCableView] state in
        rxTxCableView?.applyRxTxState(state)
    }
    helper.showOfflineMessage = {
        XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
    }
    elControllerFunctionTestHelper = helper

    functionTestView.onAction = { [weak self] in
        self?.elControllerFunctionTestHelper?.startFunctionTest()
    }
    rxTxCableView.onAction = { [weak self] in
        self?.elControllerFunctionTestHelper?.checkRxTxCable()
    }

    setELControllerFunctionViewsHidden(!node.isKeybindComplete || !node.state)
}
```

- [ ] **Step 5: Stop helper when emergency sign UI becomes unavailable**

In `updateEmergencySignData()`, update the offline and not-keybound branches so they stop the helper before hiding the cards:

```swift
guard node.state else {
    elControllerFunctionTestHelper?.stopPageSession()
    emergencySignIdentifyButton?.isHidden = true
    setELControllerFunctionViewsHidden(true)
    view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
    return
}
```

And in the `else` branch for `node.isKeybindComplete == false`, add this before hiding views:

```swift
elControllerFunctionTestHelper?.stopPageSession()
emergencySignIdentifyButton?.isHidden = true
setELControllerFunctionViewsHidden(true)
```

- [ ] **Step 6: Replace local EL Controller command handlers**

Delete these methods from `DeviceLightViewController`:

- `startELControllerFunctionTest()`
- `checkELControllerRxTxCable()`
- `applyELControllerFunctionTestResult(_:)`

Replace `handleELControllerVendorStatus(_:sentFrom:)` with:

```swift
private func handleELControllerVendorStatus(_ status: SunricherVendorStatus, sentFrom source: Address) {
    guard supportsELControllerLocalFunctionViews else { return }
    elControllerFunctionTestHelper?.handleStatus(status, sentFrom: source)
}
```

- [ ] **Step 7: Verify controller no longer owns protocol flow**

Run:

```bash
rg -n "startELControllerFunctionTest|checkELControllerRxTxCable|applyELControllerFunctionTestResult|elControllerFunctionTestHelper|handleELControllerVendorStatus" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected:

- No matches for `private func startELControllerFunctionTest`.
- No matches for `private func checkELControllerRxTxCable`.
- No matches for `private func applyELControllerFunctionTestResult`.
- Matches exist for `elControllerFunctionTestHelper`.
- `handleELControllerVendorStatus` exists and delegates to helper.

- [ ] **Step 8: Commit controller wiring**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: wire EL Controller polling helper"
```

Expected: commit succeeds with only `DeviceLightViewController.swift` modified.

---

### Task 3: Add Helper To All App Targets

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add PBXBuildFile entries**

In the `PBXBuildFile` section next to `ELControllerFunctionTestView.swift in Sources`, add:

```text
C8F700102FAF000000000002 /* ELControllerFunctionTestHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700102FAF000000000001 /* ELControllerFunctionTestHelper.swift */; };
C8F700102FAF000000000003 /* ELControllerFunctionTestHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700102FAF000000000001 /* ELControllerFunctionTestHelper.swift */; };
C8F700102FAF000000000004 /* ELControllerFunctionTestHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700102FAF000000000001 /* ELControllerFunctionTestHelper.swift */; };
C8F700102FAF000000000005 /* ELControllerFunctionTestHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700102FAF000000000001 /* ELControllerFunctionTestHelper.swift */; };
```

- [ ] **Step 2: Add PBXFileReference entry**

In the `PBXFileReference` section next to `ELControllerFunctionTestView.swift`, add:

```text
C8F700102FAF000000000001 /* ELControllerFunctionTestHelper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ELControllerFunctionTestHelper.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add helper to the Device View group**

In the group that already contains `ELControllerFunctionTestView.swift`, add the helper after the view:

```text
C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */,
C8F700102FAF000000000001 /* ELControllerFunctionTestHelper.swift */,
C8D1C0202F10000000000001 /* UpDownLightView.swift */,
```

- [ ] **Step 4: Add helper to the four source phases**

In each source phase where `ELControllerFunctionTestView.swift in Sources` already appears, add the matching helper build file immediately after it:

```text
C8F700002FAF000000000002 /* ELControllerFunctionTestView.swift in Sources */,
C8F700102FAF000000000002 /* ELControllerFunctionTestHelper.swift in Sources */,
```

```text
C8F700002FAF000000000003 /* ELControllerFunctionTestView.swift in Sources */,
C8F700102FAF000000000003 /* ELControllerFunctionTestHelper.swift in Sources */,
```

```text
C8F700002FAF000000000004 /* ELControllerFunctionTestView.swift in Sources */,
C8F700102FAF000000000004 /* ELControllerFunctionTestHelper.swift in Sources */,
```

```text
C8F700002FAF000000000005 /* ELControllerFunctionTestView.swift in Sources */,
C8F700102FAF000000000005 /* ELControllerFunctionTestHelper.swift in Sources */,
```

- [ ] **Step 5: Verify project references**

Run:

```bash
rg -n "ELControllerFunctionTestHelper.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected: exactly 10 matches:

- 4 `PBXBuildFile` entries.
- 1 `PBXFileReference` entry.
- 1 group child entry.
- 4 source phase entries.

- [ ] **Step 6: Commit project file**

Run:

```bash
git add SunSmart.xcodeproj/project.pbxproj
git commit -m "build: add EL Controller helper to targets"
```

Expected: commit succeeds with only project file changes.

---

### Task 4: Build And Regression Verify

**Files:**
- Verify: `SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Verify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Check working tree and whitespace**

Run:

```bash
git status --short
git diff --check
```

Expected:

- `git status --short` prints nothing.
- `git diff --check` prints nothing.

- [ ] **Step 2: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify key behavior through code search**

Run:

```bash
rg -n "timeout: 1.8|startPageSession\\(\\)|stopPageSession\\(\\)|viewWillDisappear|elControllerDeviceStatus|elControllerFunctionTestResult|elControllerRxTxCableConnection" SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected:

- Helper contains `timeout: 1.8` for Function Test Result polling.
- Controller calls `startPageSession()` in `viewWillAppear`.
- Controller calls `stopPageSession()` in `viewWillDisappear`.
- Helper handles `elControllerDeviceStatus`.
- Helper handles `elControllerFunctionTestResult`.
- Helper handles `elControllerRxTxCableConnection`.

- [ ] **Step 4: Final status check**

Run:

```bash
git status --short
```

Expected: prints nothing.

---

## Manual Device Verification Matrix

Use this matrix when a physical EL Controller is available:

- Enter page with device in Normal status:
  - Expected: Function Test default UI, RX/TX Cable default UI, no Function Test Result polling after Device Status response.
- Enter page with device already Function testing:
  - Expected: Function Test shows `Awaiting device response...`, RX/TX Cable default UI, App sends `GET 0x03` roughly every 2 seconds.
- Tap Start:
  - Expected: App sends `SET 0x07`; when ACK is `45 07 00` or `45 07 00 0E`, UI stays Awaiting and `GET 0x03` polling starts.
- During polling, one `GET 0x03` times out:
  - Expected: UI stays Awaiting and polling continues.
- Device returns `45 03 00 00 00`:
  - Expected: Function Test shows Passed and polling stops.
- Device returns `45 03 00 01 00`, `45 03 00 02 00`, or `45 03 00 04 00`:
  - Expected: Function Test shows corresponding lamp, battery, or circuit fault and polling stops.
- Device returns `45 03 00 <faultBits> 07`:
  - Expected: Function Test shows Invalid result and polling stops.
- Push another page or pop this page while polling:
  - Expected: polling stops immediately; returning to this page resets both cards and starts with `GET 0x01`.

---

## Self-Review Notes

- Spec coverage:
  - Page entry `GET 0x01`: Task 1 helper `startPageSession`.
  - Start ACK then polling: Task 1 helper `startFunctionTest`.
  - 2-second result polling: Task 1 helper timer and `timeout: 1.8`.
  - Single poll failure keeps Awaiting: Task 1 `handleFunctionTestResultStatus`.
  - Page disappear stop/reset: Task 2 `viewWillDisappear`, Task 1 `stopPageSession`.
  - RX/TX default reset and check flow: Task 1 `resetUI` and `checkRxTxCable`.
  - Helper isolation: Task 1 and Task 2 delete controller-owned protocol flow.
  - Four target membership: Task 3.
- Placeholder scan: no red-flag placeholder markers are present.
- Type consistency:
  - Uses existing `ELControllerFunctionTestView.FunctionTestState` and `RxTxState`.
  - Uses existing SDK APIs: `SunricherVendorGet`, `SunricherVendorSet`, `SunricherVendorStatus`, `ELControllerDeviceStatus`, `ELControllerFunctionTestResult`.
