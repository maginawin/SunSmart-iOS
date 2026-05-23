# Battery Power Switch Activation Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Battery Power Switch SAVE 需要下发配置前，展示符合 Figma 的激活弹窗，60s 内每 2s 轮询 capability GET，检测到设备激活后再进入现有同步流程。

**Architecture:** 复用现有 `PJEightKeySwitchActivationAlertView/Controller`，把它改成可配置状态弹窗；在 `PJEightKeySwitchActivationAlertController.swift` 内新增轻量 flow，负责倒计时、轮询、取消和自动进入同步。SAVE 调用方只创建 flow，不直接管理 Timer 或 Mesh 回调。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift`
  - 保留 Figma 底部 sheet 布局。
  - 新增 `Content`、`StatusStyle`、`Action` 配置模型。
  - 提供 `apply(content:)`，一次性更新标题、副标题、状态行和按钮。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`
  - 移除 controller 内部倒计时 Timer。
  - 保留 modal presentation 和按钮回调。
  - 新增 `PJEightKeySwitchActivationFlow`、`PJEightKeySwitchActivationDetecting`、`MeshBatteryPowerSwitchActivationDetector`。
  - flow 负责 60s 倒计时、2s capability 轮询、detected/no response/cancel/try again。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - 删除 demo result 切换。
  - Battery Power Switch 需要同步时，先展示 activation flow。
  - flow detected 自动完成后再调用现有 `pushBatteryPowerSwitchSync(_:)`。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - `pushBatteryPowerSwitchSync()` 在准备并持久化 desired config 后，先展示 activation flow，再进入现有同步页面。

- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 新增 `try_again`，用于 Figma 的 `TRY AGAIN`。

- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增 `try_again` 中文文案。

当前工程没有 XCTest target，本计划不新增测试 target，避免扩大工程配置范围。每个实现任务用编译和代码路径检查验证；flow 通过可注入 detector 保持后续可测。

---

### Task 1: Refactor Activation Alert View Into Configurable Content

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift`

- [ ] **Step 1: Record current references before editing**

Run:

```bash
rg -n "PJEightKeySwitchActivationAlertView|statusLabel|updateMessage|applyWaitingLayout|applyDualButtonLayout|retryButton" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected:

- References are limited to the activation/refresh alert controllers and the view file.
- This confirms the refactor can stay local.

- [ ] **Step 2: Add configurable content types inside `PJEightKeySwitchActivationAlertView`**

Add these nested types near the top of `PJEightKeySwitchActivationAlertView`:

```swift
    enum StatusStyle {
        case loading
        case success
        case failure
    }

    enum ActionStyle {
        case normal
        case primary
    }

    struct Action {
        let title: String
        let style: ActionStyle
    }

    struct Content {
        let title: String
        let message: String
        let statusText: String
        let statusStyle: StatusStyle
        let actions: [Action]
    }
```

Keep the existing `waitingSpinnerView`, `statusIconView`, `cancelButton`, and `retryButton`; they will be reused as the first and second action buttons.

- [ ] **Step 3: Replace fixed button setup with `apply(content:)`**

Add this method to `PJEightKeySwitchActivationAlertView`:

```swift
    func apply(content: Content) {
        titleLabel.text = content.title
        updateMessage(content.message)
        statusLabel.text = content.statusText
        apply(statusStyle: content.statusStyle)
        apply(actions: content.actions)
        viewLayoutIfNeeded()
    }

    private func apply(statusStyle: StatusStyle) {
        statusLabel.textColor = RGB(100, 116, 139)
        switch statusStyle {
        case .loading:
            waitingSpinnerView.isHidden = false
            waitingSpinnerView.startAnimating()
            statusIconView.isHidden = true
            statusIconView.image = nil
        case .success:
            waitingSpinnerView.stopAnimating()
            waitingSpinnerView.isHidden = true
            statusIconView.isHidden = false
            statusIconView.image = UIImage(systemName: "checkmark.circle")
            statusIconView.tintColor = RGB(16, 185, 129)
        case .failure:
            waitingSpinnerView.stopAnimating()
            waitingSpinnerView.isHidden = true
            statusIconView.isHidden = false
            statusIconView.image = UIImage(systemName: "exclamationmark.circle")
            statusIconView.tintColor = RGB(239, 68, 68)
        }
    }

    private func apply(actions: [Action]) {
        let normalizedActions = Array(actions.prefix(2))
        let firstAction = normalizedActions.first
        let secondAction = normalizedActions.dropFirst().first

        cancelButton.setTitle(firstAction?.title, for: .normal)
        cancelButton.setTitleColor(color(for: firstAction?.style ?? .normal), for: .normal)
        retryButton.setTitle(secondAction?.title, for: .normal)
        retryButton.setTitleColor(color(for: secondAction?.style ?? .primary), for: .normal)

        if secondAction == nil {
            buttonMiddleLineView.isHidden = true
            retryButton.isHidden = true
            cancelButton.snp.remakeConstraints { make in
                make.left.right.top.equalToSuperview()
                make.height.equalTo(Constants.buttonHeight)
            }
        } else {
            buttonMiddleLineView.isHidden = false
            retryButton.isHidden = false
            cancelButton.snp.remakeConstraints { make in
                make.left.top.equalToSuperview()
                make.right.equalTo(buttonMiddleLineView.snp.left)
                make.height.equalTo(Constants.buttonHeight)
            }
        }
    }

    private func color(for style: ActionStyle) -> UIColor {
        switch style {
        case .normal:
            return RGB(64, 79, 102)
        case .primary:
            return RGB(102, 103, 171)
        }
    }

    private func viewLayoutIfNeeded() {
        setNeedsLayout()
        layoutIfNeeded()
    }
```

If `UIButton.setTitleColor(color, for:)` does not compile because this codebase only uses the UIKit signature, use:

```swift
cancelButton.setTitleColor(color(for: firstAction?.style ?? .normal), for: .normal)
retryButton.setTitleColor(color(for: secondAction?.style ?? .primary), for: .normal)
```

- [ ] **Step 4: Align Figma colors and dimensions**

In the same file, update the existing view constants and colors:

```swift
        static let fullContainerHeight = SCRYFrom(356)
        static let contentHeight = SCRYFrom(266)
        static let buttonHeight = SCRYFrom(53)
```

Update these colors:

```swift
        view.backgroundColor = RGB(248, 250, 252)
```

```swift
        view.backgroundColor = UIColor.black.withAlphaComponent(0.30)
```

```swift
        let label = UILabel(text: "neightkeyswitches_save_after_activation".localizedString, textColor: RGB(46, 49, 93), fontSize: 17, fontWeight: .regular, fit: false)
```

Inside `updateMessage(_:)`, use:

```swift
                .foregroundColor: RGB(148, 163, 184),
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
```

Keep the top corner radius at 15 or 16. If changing it, use:

```swift
        view.layer.cornerRadius = 15
```

- [ ] **Step 5: Remove obsolete layout methods only after callers are migrated**

Do not delete `applyWaitingLayout()` and `applyDualButtonLayout()` in this task if `PJEightKeySwitchRefreshAlertController` still uses them. Leave them in place until Task 2 and Task 6 compile cleanly.

- [ ] **Step 6: Build-check the view refactor**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds, or failures point only to old controller call sites that still need Task 2 migration.

- [ ] **Step 7: Commit Task 1**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift
git commit -m "refactor: make switch activation alert configurable"
```

---

### Task 2: Convert Activation Alert Controller To Presentation-Only Controller

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: Remove demo countdown ownership from the controller**

Delete these members from `PJEightKeySwitchActivationAlertController`:

```swift
    enum State: Equatable {
        case waiting(remainingSeconds: Int)
        case detected
        case timeout
    }

    var cancelAction: (() -> Void)?
    var retryAction: (() -> Void)?

    private let panelType: PJEightKeySwitchPanelDefinition.PanelType
    private var countdownTimer: Timer?
    private var remainingSeconds = 60
```

Replace the initializer with:

```swift
    var actionHandler: ((Int) -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
```

Remove `deinit`, `startWaiting()`, `showDetected()`, `showTimeout()`, `apply(state:)`, and `invalidateTimer()` from this controller.

- [ ] **Step 2: Add a public content update method**

Add:

```swift
    func apply(content: PJEightKeySwitchActivationAlertView.Content) {
        contentView.apply(content: content)
    }
```

- [ ] **Step 3: Route button taps by index**

Replace `cancelButtonAction()` and `retryButtonAction()` with:

```swift
    @objc private func firstButtonAction() {
        actionHandler?(0)
    }

    @objc private func secondButtonAction() {
        actionHandler?(1)
    }
```

In `setupUI()`, update targets:

```swift
        contentView.cancelButton.addTarget(self, action: #selector(firstButtonAction), for: .touchUpInside)
        contentView.retryButton.addTarget(self, action: #selector(secondButtonAction), for: .touchUpInside)
```

- [ ] **Step 4: Keep the controller non-dismissible by background**

Do not add any tap recognizer to `contentView.backgroundView`.

Keep:

```swift
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
```

- [ ] **Step 5: Build-check the controller migration**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build may fail in `PJPreAddEightKeySwitchesVC` and `PJEightKeySwitchRefreshAlertController` because they still call `startWaiting()` or `showDetected()`. Those failures are expected until Task 4 and Task 6.

- [ ] **Step 6: Commit Task 2**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
git commit -m "refactor: separate activation alert presentation"
```

---

### Task 3: Add Battery Power Switch Activation Flow

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift`

- [ ] **Step 1: Add Nordic import**

At the top of `PJEightKeySwitchActivationAlertController.swift`, add:

```swift
import NordicSigMeshSDK
```

- [ ] **Step 2: Add detection protocol**

Append this protocol below `PJEightKeySwitchActivationAlertController`:

```swift
protocol PJEightKeySwitchActivationDetecting: AnyObject {
    func sendActivationProbe(to node: Node, completion: @escaping (Bool) -> Void)
}
```

- [ ] **Step 3: Add Mesh detector**

Append:

```swift
final class MeshBatteryPowerSwitchActivationDetector: PJEightKeySwitchActivationDetecting {

    func sendActivationProbe(to node: Node, completion: @escaping (Bool) -> Void) {
        guard let vendorModel = node.sunricherVendorModel else {
            completion(false)
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .batteryPowerSwitchCapability),
            model: vendorModel,
            timeout: 1.5
        ) { response in
            guard let status = response as? SunricherVendorStatus else {
                completion(false)
                return
            }
            completion(status.status.isSuccessful && status.status.code == .batteryPowerSwitchCapability)
        }
    }
}
```

This matches `Vendor RET 0x4C 0x01 0x00` by checking SDK status success and response code. It does not inspect `buttonCount`, `triggerCount`, or `configVersion`.

- [ ] **Step 4: Add flow class**

Append:

```swift
final class PJEightKeySwitchActivationFlow {

    private enum State {
        case idle
        case waiting
        case detected
        case noResponse
        case cancelled
    }

    private weak var presenter: UIViewController?
    private let switchData: PJEightKeySwitchData
    private let detector: PJEightKeySwitchActivationDetecting
    private let onDetectedCompleted: () -> Void
    private let titleText = "neightkeyswitches_save_after_activation".localizedString
    private var alertController: PJEightKeySwitchActivationAlertController?
    private var countdownTimer: Timer?
    private var probeTimer: Timer?
    private var autoProceedWorkItem: DispatchWorkItem?
    private var remainingSeconds = 60
    private var generation = UUID()
    private var state: State = .idle

    init(
        presenter: UIViewController,
        switchData: PJEightKeySwitchData,
        detector: PJEightKeySwitchActivationDetecting = MeshBatteryPowerSwitchActivationDetector(),
        onDetectedCompleted: @escaping () -> Void
    ) {
        self.presenter = presenter
        self.switchData = switchData
        self.detector = detector
        self.onDetectedCompleted = onDetectedCompleted
    }

    deinit {
        stopTimers()
        autoProceedWorkItem?.cancel()
    }

    func start() {
        let controller = PJEightKeySwitchActivationAlertController()
        controller.actionHandler = { [weak self] index in
            self?.handleAction(at: index)
        }
        alertController = controller
        presenter?.present(controller, animated: true) { [weak self] in
            self?.startWaiting()
        }
    }

    private func startWaiting() {
        generation = UUID()
        state = .waiting
        remainingSeconds = 60
        autoProceedWorkItem?.cancel()
        stopTimers()
        applyWaitingContent()
        sendProbe(for: generation)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickCountdown()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sendProbe(for: self.generation)
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

    private func sendProbe(for probeGeneration: UUID) {
        guard case .waiting = state, let node = switchData.proxyNode else { return }
        detector.sendActivationProbe(to: node) { [weak self] detected in
            DispatchQueue.main.async {
                guard let self,
                      detected,
                      self.generation == probeGeneration,
                      case .waiting = self.state else {
                    return
                }
                self.showDetected()
            }
        }
    }

    private func showDetected() {
        state = .detected
        stopTimers()
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: "neightkeyswitches_activation_detected".localizedString,
            statusStyle: .success,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
        let workItem = DispatchWorkItem { [weak self] in
            self?.completeDetected()
        }
        autoProceedWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func showNoResponse() {
        state = .noResponse
        stopTimers()
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
        alertController?.apply(content: .init(
            title: titleText,
            message: switchData.eightKeyPanelType.activationInstruction,
            statusText: String(format: "neightkeyswitches_activation_waiting_format".localizedString, remainingSeconds),
            statusStyle: .loading,
            actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
        ))
    }

    private func handleAction(at index: Int) {
        switch state {
        case .waiting:
            cancel()
        case .detected:
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

    private func completeDetected() {
        guard case .detected = state else { return }
        alertController?.dismiss(animated: true) { [weak self] in
            self?.onDetectedCompleted()
        }
    }

    private func cancel() {
        state = .cancelled
        generation = UUID()
        stopTimers()
        autoProceedWorkItem?.cancel()
        alertController?.dismiss(animated: true)
    }

    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        probeTimer?.invalidate()
        probeTimer = nil
    }
}
```

- [ ] **Step 5: Build-check the new flow**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- If `SunricherVendorStatus.Status.code` is not externally accessible, move `MeshBatteryPowerSwitchActivationDetector` into an extension/file where it can access the SDK public API, or switch success check to:

```swift
if case .batteryPowerSwitchCapability = status.status.parameters {
    completion(status.status.isSuccessful)
} else {
    completion(false)
}
```

This still ignores actual returned count/version values.

- [ ] **Step 6: Commit Task 3**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift
git commit -m "feat: add battery switch activation flow"
```

---

### Task 4: Connect Activation Flow To Pre-Add SAVE

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Remove demo-only state**

Delete:

```swift
    private enum ActivationDemoOutcome {
        case detected
        case timeout
    }
```

Delete:

```swift
    private weak var activationAlertController: PJEightKeySwitchActivationAlertController?
    private var nextActivationDemoOutcome: ActivationDemoOutcome = .detected
```

Add:

```swift
    private var activationFlow: PJEightKeySwitchActivationFlow?
```

- [ ] **Step 2: Route sync through activation flow**

In `submitBatteryPowerSwitch(_:)`, replace:

```swift
        pushBatteryPowerSwitchSync(switchData)
```

with:

```swift
        presentBatteryPowerSwitchActivation(for: switchData)
```

- [ ] **Step 3: Replace demo alert methods**

Delete `presentActivationAlert(for:)` and `scheduleActivationDemoResult(on:outcome:)`.

Add:

```swift
    private func presentBatteryPowerSwitchActivation(for switchData: PJEightKeySwitchData) {
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: switchData
        ) { [weak self, weak switchData] in
            guard let self, let switchData else { return }
            self.activationFlow = nil
            self.pushBatteryPowerSwitchSync(switchData)
        }
        activationFlow = flow
        flow.start()
    }
```

- [ ] **Step 4: Remove old real-device activation branch**

In `submitAction()`, after non-Battery Power Switch persistence, remove this branch:

```swift
        guard !hasRealDeviceLink(switchData) else {
            presentActivationAlert(for: switchData)
            return
        }
```

This old branch used the demo alert for real-device links. Battery Power Switch now uses `submitBatteryPowerSwitch(_:)`; non-Battery real-device links should not show the Battery Power Switch activation alert.

- [ ] **Step 5: Keep cancel behavior data-safe**

Do not change the existing sequence in `submitBatteryPowerSwitch(_:)` before `presentBatteryPowerSwitchActivation(for:)`:

```swift
        persistSwitchData(switchData)
        switchSavedAction?(switchData)
        postSwitchDataChangedNotifications()
        initialSnapshot = makeSnapshot()
```

This keeps the SAVE data prepared once. If the user cancels activation, the sync state remains pending and a later SAVE can retry.

- [ ] **Step 6: Build-check pre-add integration**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- No references remain to `ActivationDemoOutcome`, `presentActivationAlert`, or `scheduleActivationDemoResult`.

Confirm:

```bash
rg -n "ActivationDemoOutcome|presentActivationAlert|scheduleActivationDemoResult|nextActivationDemoOutcome" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected: no output.

- [ ] **Step 7: Commit Task 4**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "feat: require activation before battery switch sync"
```

---

### Task 5: Connect Activation Flow To Monitor SAVE Sync

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Add activation flow storage**

Add this property:

```swift
    private var activationFlow: PJEightKeySwitchActivationFlow?
```

- [ ] **Step 2: Split sync push into activation and actual sync**

Rename the existing `pushBatteryPowerSwitchSync()` body into two methods:

```swift
    private func pushBatteryPowerSwitchSync() {
        guard viewModel.prepareBatteryPowerSwitchDesiredConfigIfNeeded() else {
            XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
            return
        }
        viewModel.persist()
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        presentBatteryPowerSwitchActivation()
    }

    private func presentBatteryPowerSwitchActivation() {
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: viewModel.switchData
        ) { [weak self] in
            guard let self else { return }
            self.activationFlow = nil
            self.pushBatteryPowerSwitchSyncController()
        }
        activationFlow = flow
        flow.start()
    }

    private func pushBatteryPowerSwitchSyncController() {
        let vc = SyncDevicesViewController(type: .batteryPowerSwitch(viewModel.switchData))
        vc.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            self.viewModel.switchData.markBatteryPowerSwitchSyncSucceeded()
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        vc.backActionCallback = { [weak self] result in
            guard let self else { return }
            let hasFailedOperations = result.contains { !$0.failedOperationTypes.isEmpty }
            self.viewModel.switchData.markBatteryPowerSwitchSyncFailed(reason: hasFailedOperations ? "sync_failed".localizedString : nil)
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
            self.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
```

Keep the success/failure callback behavior identical to the current implementation.

- [ ] **Step 3: Build-check monitor integration**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- `PJEightKeySwitchMonitorVC` compiles.
- Existing sync success/failure behavior is still present.

- [ ] **Step 4: Commit Task 5**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift
git commit -m "feat: gate monitor sync on switch activation"
```

---

### Task 6: Preserve Refresh Alert Or Migrate Its Call Sites

**Files:**
- Modify if needed: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift`
- Modify if needed: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift`

- [ ] **Step 1: Check refresh alert compile impact**

Run:

```bash
rg -n "PJEightKeySwitchRefreshAlertController|applyWaitingLayout|applyDualButtonLayout|startWaiting|showUpdated|showTimeout" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected:

- `PJEightKeySwitchRefreshAlertController` may still rely on old view methods.
- The view can keep `applyWaitingLayout()` and `applyDualButtonLayout()` for compatibility.

- [ ] **Step 2: If refresh alert uses old view methods only, leave them**

Keep these compatibility methods in `PJEightKeySwitchActivationAlertView`:

```swift
    func applyWaitingLayout() {
        buttonMiddleLineView.isHidden = true
        retryButton.isHidden = true
        cancelButton.snp.remakeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(Constants.buttonHeight)
        }
    }

    func applyDualButtonLayout() {
        buttonMiddleLineView.isHidden = false
        retryButton.isHidden = false
        cancelButton.snp.remakeConstraints { make in
            make.left.top.equalToSuperview()
            make.right.equalTo(buttonMiddleLineView.snp.left)
            make.height.equalTo(Constants.buttonHeight)
        }
    }
```

Do not migrate refresh behavior in this task unless the build requires it. Refresh is outside the Battery Power Switch SAVE activation scope.

- [ ] **Step 3: If refresh alert calls removed controller APIs, restore compatibility only there**

If `PJEightKeySwitchRefreshAlertController` fails because it expected methods from `PJEightKeySwitchActivationAlertController`, update it to own its own timer and call `contentView.apply(content:)` directly. Keep its existing user-visible behavior:

```swift
contentView.apply(content: .init(
    title: "refresh".localizedString,
    message: "",
    statusText: "neightkeyswitches_activation_waiting_format".localizedString,
    statusStyle: .loading,
    actions: [.init(title: "cancel".localizedString.uppercased(), style: .normal)]
))
```

Use the actual existing refresh title/message strings from `PJEightKeySwitchRefreshAlertController`; do not introduce Battery Power Switch activation wording into refresh.

- [ ] **Step 4: Build-check compatibility**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Activation alert, refresh alert, pre-add editor, and monitor all compile.

- [ ] **Step 5: Commit Task 6 if files changed**

If this task changed files:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift
git commit -m "fix: keep switch refresh alert compatible"
```

If no files changed, skip the commit.

---

### Task 7: Add TRY AGAIN Localization

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add English key**

Add near the existing `retry` key in `SunSmart/en.lproj/Localizable.strings`:

```text
"try_again" = "Try Again";
```

- [ ] **Step 2: Add Simplified Chinese key**

Add near the existing `retry` key in `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"try_again" = "重试";
```

- [ ] **Step 3: Verify keys**

Run:

```bash
rg -n '"try_again"|"retry"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- Both files contain `try_again`.
- Existing `retry` key remains unchanged.

- [ ] **Step 4: Build-check localization**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

- [ ] **Step 5: Commit Task 7**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "chore: add try again localization"
```

---

### Task 8: Final Verification

**Files:**
- Verify: all files modified by Tasks 1-7

- [ ] **Step 1: Confirm no demo activation logic remains**

Run:

```bash
rg -n "ActivationDemoOutcome|nextActivationDemoOutcome|scheduleActivationDemoResult|presentActivationAlert" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected: no output.

- [ ] **Step 2: Confirm capability GET is the activation probe**

Run:

```bash
rg -n "batteryPowerSwitchCapability|sendActivationProbe|PJEightKeySwitchActivationFlow" SunSmart/Main/Device/Device1.5/NEightKeySwitches -g '!user-temp/**'
```

Expected:

- `MeshBatteryPowerSwitchActivationDetector` sends `SunricherVendorGet(function: .batteryPowerSwitchCapability)`.
- `PJEightKeySwitchActivationFlow` checks success without inspecting returned count/version values.

- [ ] **Step 3: Confirm alert cannot dismiss by tapping blank area**

Run:

```bash
rg -n "backgroundView.*addGestureRecognizer|UITapGestureRecognizer|overFullScreen|modalTransitionStyle" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchActivationAlertController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift
```

Expected:

- `overFullScreen` is present.
- No tap recognizer is added to the activation alert background.

- [ ] **Step 4: Run final iPhoneOS build**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build succeeds.

- [ ] **Step 5: Manual UI verification**

Use a Battery Power Switch profile that needs sync and verify:

- Brightness profile waiting subtitle is `Press 'Button 75%' and 'Button ON' to activate the device.`
- Scene profile waiting subtitle is `Press 'Button 2' and 'Button ON' to activate the device.`
- Waiting starts at 60s and decrements every second.
- Capability GET is retried every 2s while waiting.
- A successful `Vendor RET 0x4C 0x01 0x00` response shows `Device Activation Detected`.
- Detected auto-closes after about 1s and opens `SyncDevicesViewController`.
- Detected `CANCEL` closes only the popup and does not open sync.
- No response at 60s shows `No response detected` with `CANCEL` and `TRY AGAIN`.
- `TRY AGAIN` restarts from 60s.
- Waiting `CANCEL` closes the popup and a later SAVE starts a fresh countdown.

- [ ] **Step 6: Commit final verification notes if docs changed**

If implementation adds a short verification note under `docs/`, commit it:

```bash
git add docs
git commit -m "docs: record battery switch activation verification"
```

If no docs are added, skip this step.

---

## Self-Review

- Spec coverage: The plan covers the configurable popup, Figma three-state layout, non-dismissible background, 60s countdown, 2s capability polling, success condition `Vendor RET 0x4C 0x01 0x00`, detected auto-close into `SyncDevicesViewController`, cancel behavior, try again behavior, profile-specific subtitles, localization, and build verification.
- Scope check: The work stays within the existing NEightKeySwitches UI and existing Battery Power Switch sync path. It does not modify SDK protocol definitions or replace `SyncDevicesViewController`.
- Test gap: The project has no XCTest target, so this plan uses build verification, code-path checks, and manual UI verification. The detector protocol keeps the flow injectable if a test target is introduced later.
