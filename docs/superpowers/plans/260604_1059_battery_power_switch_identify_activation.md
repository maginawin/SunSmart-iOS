# Battery Power Switch Identify Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the Battery Power Switch monitor page Identify action so it waits for device activation, then keeps sending standard SIG Mesh identify every 3 seconds until the user cancels.

**Architecture:** Add a focused `PJEightKeySwitchIdentifyFlow` beside the existing activation and TX enable flows. It reuses the existing activation alert UI and activation detector, but owns its own waiting, detected, identifying, timeout, retry, and cancel state machine. The monitor page only starts and retains the flow.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `PJEightKeySwitchActivationAlertController`, existing `MeshBatteryPowerSwitchActivationDetector`, existing localization strings.

---

## File Structure

- Modify `SunSmart/en.lproj/Localizable.strings`
  - Add Identify-specific title and in-progress strings near existing `neightkeyswitches_activation_*` strings.
- Modify `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Add matching Simplified Chinese strings in the same key group.
- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - Add `PJEightKeySwitchIdentifySending`.
  - Add `MeshBatteryPowerSwitchIdentifySender`.
  - Add `PJEightKeySwitchIdentifyFlow`.
- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - Retain the identify flow.
  - Start the flow from the right-menu Identify action.
  - Cancel the flow in `deinit`.

The project does not expose a focused App XCTest target for this controller. Verification uses static code checks and the required iPhoneOS build.

---

### Task 1: Add Identify Localized Strings

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add English strings**

In `SunSmart/en.lproj/Localizable.strings`, insert these keys immediately after `neightkeyswitches_activation_timeout`:

```swift
"neightkeyswitches_identify_title" = "Identify Device";
"neightkeyswitches_identifying" = "Identifying...";
```

- [ ] **Step 2: Add Simplified Chinese strings**

In `SunSmart/zh-Hans.lproj/Localizable.strings`, insert these keys immediately after `neightkeyswitches_activation_timeout`:

```swift
"neightkeyswitches_identify_title" = "识别设备";
"neightkeyswitches_identifying" = "正在识别...";
```

- [ ] **Step 3: Verify both localizations exist exactly once**

Run:

```sh
rg -n '"neightkeyswitches_identify_title"|"neightkeyswitches_identifying"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: four matching lines total, two in `SunSmart/en.lproj/Localizable.strings` and two in `SunSmart/zh-Hans.lproj/Localizable.strings`.

- [ ] **Step 4: Commit localization changes**

```sh
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add battery switch identify strings"
```

---

### Task 2: Add Identify Flow

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: Add identify sender protocol and implementation**

In `PJEightKeySwitchActivationAlertController.swift`, add this block after `MeshBatteryPowerSwitchTxEnableSender` and before `PJEightKeySwitchActivationFlow`:

```swift
protocol PJEightKeySwitchIdentifySending: AnyObject {
    func sendIdentify(to node: Node)
}

final class MeshBatteryPowerSwitchIdentifySender: PJEightKeySwitchIdentifySending {

    func sendIdentify(to node: Node) {
        MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)
    }
}
```

- [ ] **Step 2: Add the identify state machine**

In the same file, add this class after `PJEightKeySwitchActivationFlow` and before `PJEightKeySwitchTxEnableFlow`:

```swift
final class PJEightKeySwitchIdentifyFlow {

    private enum State {
        case idle
        case waiting
        case detected
        case identifying
        case noResponse
        case cancelled
    }

    private weak var presenter: UIViewController?
    private let switchData: PJEightKeySwitchData
    private let detector: PJEightKeySwitchActivationDetecting
    private let sender: PJEightKeySwitchIdentifySending
    private let onFinished: () -> Void
    private let titleText = "neightkeyswitches_identify_title".localizedString
    private var alertController: PJEightKeySwitchActivationAlertController?
    private var countdownTimer: Timer?
    private var probeTimer: Timer?
    private var identifyTimer: Timer?
    private var startIdentifyWorkItem: DispatchWorkItem?
    private var remainingSeconds = 60
    private var generation = UUID()
    private var state: State = .idle

    init(
        presenter: UIViewController,
        switchData: PJEightKeySwitchData,
        detector: PJEightKeySwitchActivationDetecting = MeshBatteryPowerSwitchActivationDetector(),
        sender: PJEightKeySwitchIdentifySending = MeshBatteryPowerSwitchIdentifySender(),
        onFinished: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.switchData = switchData
        self.detector = detector
        self.sender = sender
        self.onFinished = onFinished
    }

    deinit {
        stopTimers()
        startIdentifyWorkItem?.cancel()
    }

    func start() {
        let controller = PJEightKeySwitchActivationAlertController()
        controller.actionHandler = { [weak self] index in
            self?.handleAction(at: index)
        }
        alertController = controller
        controller.apply(content: waitingContent())
        presenter?.present(controller, animated: true) { [weak self] in
            self?.startWaiting()
        }
    }

    func cancel() {
        state = .cancelled
        generation = UUID()
        stopTimers()
        startIdentifyWorkItem?.cancel()
        alertController?.dismiss(animated: true) { [weak self] in
            self?.onFinished()
        }
    }

    private func startWaiting() {
        generation = UUID()
        state = .waiting
        remainingSeconds = 60
        startIdentifyWorkItem?.cancel()
        stopTimers()
        applyWaitingContent()
        sendActivationProbe(for: generation)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendActivationProbe(for: self.generation)
        }
    }

    private func tickCountdown() {
        guard case .waiting = state else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            showNoResponse()
        } else {
            applyWaitingContent()
        }
    }

    private func sendActivationProbe(for flowGeneration: UUID) {
        guard case .waiting = state, let node = switchData.proxyNode else { return }
        detector.sendActivationProbe(to: node) { [weak self] detected in
            DispatchQueue.main.async {
                guard let self,
                      detected,
                      self.generation == flowGeneration,
                      case .waiting = self.state else {
                    return
                }
                self.showDetected()
            }
        }
    }

    private func showDetected() {
        state = .detected
        generation = UUID()
        stopTimers()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_activation_detected".localizedString,
            statusStyle: .success,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
        let workItem = DispatchWorkItem { [weak self] in
            self?.startIdentifying()
        }
        startIdentifyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func startIdentifying() {
        guard case .detected = state else { return }
        state = .identifying
        generation = UUID()
        stopTimers()
        applyIdentifyingContent()
        sendIdentify()
        identifyTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.sendIdentify()
        }
    }

    private func sendIdentify() {
        guard case .identifying = state, let node = switchData.proxyNode else { return }
        sender.sendIdentify(to: node)
    }

    private func showNoResponse() {
        state = .noResponse
        generation = UUID()
        stopTimers()
        startIdentifyWorkItem?.cancel()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_activation_timeout".localizedString,
            statusStyle: .failure,
            actions: [
                .init(title: "cancel".localizedString.uppercased(), style: .normal),
                .init(title: "try_again".localizedString.uppercased(), style: .primary)
            ]
        ))
    }

    private func applyWaitingContent() {
        alertController?.apply(content: waitingContent())
    }

    private func applyIdentifyingContent() {
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_identifying".localizedString,
            statusStyle: .loading,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
    }

    private func waitingContent() -> PJEightKeySwitchActivationAlertView.Content {
        .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: String(format: "neightkeyswitches_activation_waiting_format".localizedString, remainingSeconds),
            statusStyle: .loading,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        )
    }

    private func handleAction(at index: Int) {
        switch state {
        case .waiting, .detected, .identifying:
            cancel()
        case .noResponse:
            if index == 0 {
                cancel()
            } else {
                startWaiting()
            }
        case .idle, .cancelled:
            cancel()
        }
    }

    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        probeTimer?.invalidate()
        probeTimer = nil
        identifyTimer?.invalidate()
        identifyTimer = nil
    }
}
```

- [ ] **Step 3: Verify the flow uses enable/disable activation detection**

Run:

```sh
rg -n "PJEightKeySwitchIdentifyFlow|MeshBatteryPowerSwitchActivationDetector|batteryPowerSwitchCapability|GenericBatteryGet" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- `PJEightKeySwitchIdentifyFlow` exists.
- `MeshBatteryPowerSwitchActivationDetector` is the default detector for identify flow.
- `batteryPowerSwitchCapability` appears in the existing detector.
- `GenericBatteryGet` does not appear in this file for identify flow.

- [ ] **Step 4: Verify identifying has no timeout countdown**

Run:

```sh
rg -n "case identifying|identifyTimer|scheduledTimer\\(withTimeInterval: 3|remainingSeconds <= 0" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- `case identifying` exists.
- `identifyTimer` is scheduled with `withTimeInterval: 3`.
- `remainingSeconds <= 0` remains tied to waiting countdown logic, not to the identifying state.

- [ ] **Step 5: Commit identify flow**

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
git commit -m "feat: add battery switch identify activation flow"
```

---

### Task 3: Wire Identify Flow Into Monitor Page

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Retain the identify flow**

Near the existing flow properties, change:

```swift
private var activationFlow: PJEightKeySwitchActivationFlow?
private var batteryRefreshFlow: PJEightKeySwitchBatteryRefreshFlow?
private var txEnableFlow: PJEightKeySwitchTxEnableFlow?
```

to:

```swift
private var activationFlow: PJEightKeySwitchActivationFlow?
private var batteryRefreshFlow: PJEightKeySwitchBatteryRefreshFlow?
private var txEnableFlow: PJEightKeySwitchTxEnableFlow?
private var identifyFlow: PJEightKeySwitchIdentifyFlow?
```

- [ ] **Step 2: Start the flow from identifyAction**

Replace the current `identifyAction()` body:

```swift
private func identifyAction() {
    guard let node = viewModel.informationNode else {
        return
    }
    MeshAPI.identify(address: node.primaryUnicastAddress, attentionTimer: 6)
}
```

with:

```swift
private func identifyAction() {
    guard viewModel.informationNode != nil else {
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        return
    }

    let flow = PJEightKeySwitchIdentifyFlow(
        presenter: self,
        switchData: viewModel.switchData,
        onFinished: { [weak self] in
            self?.identifyFlow = nil
        }
    )
    identifyFlow = flow
    flow.start()
}
```

- [ ] **Step 3: Cancel the flow on controller deinit**

Change the current `deinit`:

```swift
deinit {
    batteryRefreshFlow?.cancel()
    txEnableFlow?.cancel()
    activationFlow = nil
}
```

to:

```swift
deinit {
    batteryRefreshFlow?.cancel()
    txEnableFlow?.cancel()
    identifyFlow?.cancel()
    activationFlow = nil
}
```

- [ ] **Step 4: Verify direct one-shot identify was removed from monitor action**

Run:

```sh
rg -n "identifyAction|MeshAPI.identify|PJEightKeySwitchIdentifyFlow|identifyFlow" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- `identifyAction` creates `PJEightKeySwitchIdentifyFlow`.
- `identifyFlow?.cancel()` appears in `deinit`.
- `MeshAPI.identify` no longer appears in `PJEightKeySwitchMonitorVC.swift`.

- [ ] **Step 5: Commit monitor wiring**

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: route battery switch identify through activation"
```

---

### Task 4: Final Verification

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Verify command selection**

Run:

```sh
rg -n "GenericBatteryGet|batteryPowerSwitchCapability|PJEightKeySwitchIdentifyFlow|MeshAPI.identify" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
```

Expected:

- `batteryPowerSwitchCapability` appears through `MeshBatteryPowerSwitchActivationDetector`.
- `PJEightKeySwitchIdentifyFlow` appears in both flow file and monitor file.
- `MeshAPI.identify` appears in `MeshBatteryPowerSwitchIdentifySender`.
- `GenericBatteryGet` does not appear in either file.

- [ ] **Step 2: Verify user-visible state strings**

Run:

```sh
rg -n '"neightkeyswitches_identify_title"|"neightkeyswitches_identifying"|"neightkeyswitches_activation_detected"|"neightkeyswitches_activation_timeout"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- Both new identify strings exist in English and Simplified Chinese.
- The flow references `neightkeyswitches_identify_title`, `neightkeyswitches_identifying`, `neightkeyswitches_activation_detected`, and `neightkeyswitches_activation_timeout`.

- [ ] **Step 3: Verify existing enable/disable flow still compiles against unchanged names**

Run:

```sh
rg -n "final class PJEightKeySwitchTxEnableFlow|sendActivationProbe\\(for|sendTxEnable\\(for|showSucceeded\\(\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
```

Expected:

- `PJEightKeySwitchTxEnableFlow` still exists.
- Its `sendActivationProbe`, `sendTxEnable`, and `showSucceeded` methods still exist.

- [ ] **Step 4: Run the required iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 5: Review final git status**

Run:

```sh
git status --short
```

Expected:

- Clean working tree after task commits, or only unrelated user changes that were present before implementation.

---

## Manual QA Checklist

- [ ] On a real linked Battery Power Switch monitor page, tap the right menu and select `Identify`.
- [ ] Confirm the bottom dialog title is `Identify Device`.
- [ ] Confirm the activation instruction matches the enable/disable flow for the panel type.
- [ ] Confirm waiting text counts down from 60 seconds and shows `CANCEL`.
- [ ] Without activating the switch, confirm timeout shows `No response detected`, `CANCEL`, and `TRY AGAIN`.
- [ ] Tap `TRY AGAIN` and confirm the flow returns to `Waiting for switch activation (60s)...`.
- [ ] Activate the switch and confirm `Device Activation Detected` appears for about 1 second.
- [ ] Confirm the state changes to `Identifying...` and remains there until `CANCEL`.
- [ ] Confirm App-side Mesh logs show SIG Mesh identify sent roughly every 3 seconds during `Identifying...`.
- [ ] Tap `CANCEL` and confirm identify messages stop.
- [ ] Re-test enable/disable once to confirm its activation dialog and save behavior still works.
- [ ] Re-test Refresh Device once to confirm refresh battery behavior still works.
