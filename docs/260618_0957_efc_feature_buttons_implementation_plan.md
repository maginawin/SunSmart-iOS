# EFC Feature Buttons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Figma EFC feature buttons group in `EmerFireAlarmMoniView` and wire its mock buttons to direct EFC publish-group control commands.

**Architecture:** Keep UI rendering in `EmerFireAlarmMoniView` and command decisions in `EmerFireAlarmMonitorVC`. Reuse existing Mesh command APIs, EFC configuration models, image assets, and Group AUTO loading artwork without adding a new abstraction layer.

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, Xcode iPhoneOS build.

---

## File Structure

- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerIconName.swift`
  - Add new action icon constants for `efc_identify`, `mock_fire_alarm`, `mock_power_loss`, and `mock_restore`.
- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift`
  - Change the action view from a 3-button horizontal stack to a 4-button feature group: one primary Identify row and one mock button row.
  - Keep button loading state, per-button debouncing, and callback ownership inside the view.
- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
  - Configure four action items.
  - Add helper methods for mock fire alarm, mock power loss, mock restore, brightness sending, current configuration lookup, and publish-group command sending.
- No new resources are expected because the required assets already exist under `SunSmart/Assets.xcassets/FireAlarm1.5`.

## Task 1: Add EFC Feature Icon Names

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerIconName.swift`
- Test: static source/resource check

- [ ] **Step 1: Verify asset names exist**

Run:

```sh
find SunSmart/Assets.xcassets/FireAlarm1.5 -maxdepth 2 -type d \( -name 'efc_identify.imageset' -o -name 'mock_fire_alarm.imageset' -o -name 'mock_power_loss.imageset' -o -name 'mock_restore.imageset' \)
```

Expected output includes:

```text
SunSmart/Assets.xcassets/FireAlarm1.5/efc_identify.imageset
SunSmart/Assets.xcassets/FireAlarm1.5/mock_power_loss.imageset
SunSmart/Assets.xcassets/FireAlarm1.5/mock_fire_alarm.imageset
SunSmart/Assets.xcassets/FireAlarm1.5/mock_restore.imageset
```

- [ ] **Step 2: Replace action constants**

In `EmergencyFireControllerIconName.swift`, replace the `Monitor.Action` block with:

```swift
enum Action {
    static let identify = "efc_identify"
    static let mockFireAlarm = "mock_fire_alarm"
    static let mockPowerLoss = "mock_power_loss"
    static let mockRestore = "mock_restore"
    static let powerLossTrigger = "yingjimoni"
    static let powerLossStop = "yingjimonitc"
    static let fireTrigger = "yjhjmn"
    static let fireStop = "yjhjstop"
}
```

- [ ] **Step 3: Verify constant references**

Run:

```sh
rg -n "mockFireAlarm|mockPowerLoss|mockRestore|efc_identify|mock_fire_alarm|mock_power_loss|mock_restore" SunSmart/Main/Device/Device1.5/FireAlarm
```

Expected: new constants exist in `EmergencyFireControllerIconName.swift`; controller references are added in Task 3.

## Task 2: Rebuild `EmerFireAlarmMoniView` Layout

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift`
- Test: static layout check

- [ ] **Step 1: Update layout constants**

Replace the `Layout` enum with:

```swift
private enum Layout {
    static let buttonSize = SCRXFrom(40)
    static let mockButtonSpacing = SCRXFrom(24)
    static let rowSpacing = SCRYFrom(28)
    static let actionCount = 4
}
```

- [ ] **Step 2: Make buttons transparent and create four buttons**

Replace the `buttons` property with:

```swift
private lazy var buttons: [ActionButton] = (0..<Layout.actionCount).map { index in
    let button = ActionButton(type: .custom)
    button.backgroundColor = .clear
    button.layer.borderWidth = 0
    button.imageView?.contentMode = .scaleAspectFit
    button.tag = index
    button.addTarget(self, action: #selector(handleButtonTap(_:)), for: .touchUpInside)
    button.snp.makeConstraints { make in
        make.width.height.equalTo(Layout.buttonSize)
    }
    return button
}
```

- [ ] **Step 3: Replace one horizontal stack with primary and mock stacks**

Replace the current `stackView` property with these three properties:

```swift
private lazy var primaryStackView: UIStackView = {
    let stackView = UIStackView(arrangedSubviews: [buttons[0]])
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.distribution = .equalCentering
    return stackView
}()

private lazy var mockStackView: UIStackView = {
    let stackView = UIStackView(arrangedSubviews: Array(buttons[1...3]))
    stackView.axis = .horizontal
    stackView.alignment = .center
    stackView.spacing = Layout.mockButtonSpacing
    return stackView
}()

private lazy var stackView: UIStackView = {
    let stackView = UIStackView(arrangedSubviews: [primaryStackView, mockStackView])
    stackView.axis = .vertical
    stackView.alignment = .center
    stackView.spacing = Layout.rowSpacing
    return stackView
}()
```

- [ ] **Step 4: Keep feature group centered and height-driven**

Keep `setupUI()` structure, but ensure it uses the new vertical `stackView`:

```swift
private func setupUI() {
    backgroundColor = .clear

    addSubview(stackView)
    stackView.snp.makeConstraints { make in
        make.center.equalToSuperview()
        make.top.bottom.equalToSuperview()
    }
}
```

- [ ] **Step 5: Remove border restoration in normal state**

Update the hidden and normal branches in `configure(actions:)` / `updateButton(_:at:)` so buttons never restore a border:

```swift
button.layer.borderWidth = 0
```

and in `updateButton(_:at:)` use:

```swift
if isProgress {
    button.layer.borderWidth = 0
    button.setImage(UIImage(named: isIPad ? "group_auto_progress_big" : "group_auto_progress")?.withTintColor(Bar_Color, renderingMode: .alwaysOriginal), for: .normal)
    button.layer.addRotationAnimation(duration: 1, repeatCount: 10, animationKey: "loading")
} else {
    button.layer.borderWidth = 0
    button.layer.removeAnimation(forKey: "loading")
    if index < actionItems.count {
        button.setImage(actionItems[index].image?.withRenderingMode(.alwaysOriginal), for: .normal)
    }
}
```

- [ ] **Step 6: Verify layout constants**

Run:

```sh
rg -n "actionCount|rowSpacing|mockButtonSpacing|SCRYFrom\\(28\\)|SCRXFrom\\(24\\)|backgroundColor = \\.clear|borderWidth = 0" SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift
```

Expected: constants and transparent/no-border button setup are present.

## Task 3: Wire Four Monitor Actions

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift`
- Test: static command-path check

- [ ] **Step 1: Configure all four action items**

Replace `configureActions()` action array with:

```swift
let actions: [EmerFireAlarmMoniView.ActionItem] = [
    .init(
        image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.identify),
        borderColor: nil,
        action: { [weak self] in
            self?.identifyAction() ?? false
        }
    ),
    .init(
        image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.mockFireAlarm),
        borderColor: nil,
        action: { [weak self] in
            self?.mockFireAlarmAction() ?? false
        }
    ),
    .init(
        image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.mockPowerLoss),
        borderColor: nil,
        action: { [weak self] in
            self?.mockPowerLossAction() ?? false
        }
    ),
    .init(
        image: UIImage(named: EmergencyFireControllerIconName.Monitor.Action.mockRestore),
        borderColor: nil,
        action: { [weak self] in
            self?.mockRestoreAction() ?? false
        }
    )
]
```

- [ ] **Step 2: Set `moniView` top spacing to 28**

In `setupUI()`, change the `moniView` top constraint to:

```swift
make.top.equalTo(collectionView.snp.bottom).offset(SCRYFrom(28))
```

- [ ] **Step 3: Add mock action methods**

Add these methods near `lightLCOnAction()`:

```swift
@discardableResult
func mockFireAlarmAction() -> Bool {
    guard let configuration = currentEmergencyConfiguration() else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    return sendBrightness(configuration.fireAlarmSettings.triggerBrightness, logName: "mock fire alarm")
}

@discardableResult
func mockPowerLossAction() -> Bool {
    guard let configuration = currentEmergencyConfiguration() else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    return sendBrightness(configuration.powerLossSettings.triggerBrightness, logName: "mock power loss")
}

@discardableResult
func mockRestoreAction() -> Bool {
    guard let configuration = currentEmergencyConfiguration() else {
        XWHUDManager.showTipHUD("failed".localizedString + " !", isLineFeed: true)
        return false
    }
    switch configuration.restoreSettings.actionType {
    case .restoreAuto:
        return lightLCOnAction(logName: "mock restore auto")
    case .setBrightness:
        return sendBrightness(configuration.restoreSettings.brightness, logName: "mock restore brightness")
    case .none:
        print("[EFC] mock restore none")
        return true
    }
}
```

- [ ] **Step 4: Add brightness and config helpers**

Add these helpers near `publishGroupAddressForAction()`:

```swift
@discardableResult
private func sendBrightness(_ brightness: Int, logName: String) -> Bool {
    guard canOperateEmergencyActions else {
        XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
        return false
    }
    guard let publishGroupAddress = publishGroupAddressForAction() else {
        return false
    }
    let clampedBrightness = min(max(brightness, 0), 100)
    let lightness = Node.getLightness(lightness100: clampedBrightness)
    print("[EFC] \(logName) brightness=\(clampedBrightness), lightness=\(lightness), publishGroup=\(String(format: "0x%04X", publishGroupAddress))")
    MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: publishGroupAddress)
    return true
}

private func currentEmergencyConfiguration() -> EmergencyFireControllerConfiguration? {
    currentConfig?.configuration ?? currentDevice?.configuration
}
```

- [ ] **Step 5: Allow log names for LC ON without changing current callers**

Change `lightLCOnAction()` to accept a defaulted log name:

```swift
@discardableResult
func lightLCOnAction(logName: String = "light LC ON") -> Bool {
    guard canOperateEmergencyActions else {
        XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
        return false
    }
    guard let publishGroupAddress = publishGroupAddressForAction() else {
        return false
    }
    print("[EFC] \(logName) publishGroup=\(String(format: "0x%04X", publishGroupAddress))")
    MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true), address: publishGroupAddress)
    return true
}
```

- [ ] **Step 6: Verify command paths**

Run:

```sh
rg -n "mockFireAlarmAction|mockPowerLossAction|mockRestoreAction|sendBrightness|LightLightnessSetUnacknowledged|LightLCLightOnOffSetUnacknowledged|restoreSettings.actionType|publishGroupAddressForAction|SCRYFrom\\(28\\)" SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
```

Expected: all four action methods and command types are present; `moniView` top offset is 28.

## Task 4: Validate and Commit Implementation

**Files:**
- Verify all modified files
- Test: static checks, diff check, iPhoneOS build

- [ ] **Step 1: Check changed files**

Run:

```sh
git status --short
```

Expected changed files:

```text
 M SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift
 M SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerIconName.swift
 M SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift
```

- [ ] **Step 2: Run whitespace check**

Run:

```sh
git diff --check
```

Expected: no output, exit code 0.

- [ ] **Step 3: Run focused source checks**

Run:

```sh
rg -n "efc_identify|mock_fire_alarm|mock_power_loss|mock_restore|mockFireAlarmAction|mockPowerLossAction|mockRestoreAction|SCRYFrom\\(28\\)|SCRXFrom\\(24\\)|LightLightnessSetUnacknowledged|LightLCLightOnOffSetUnacknowledged" SunSmart/Main/Device/Device1.5/FireAlarm
```

Expected: icon names, layout constants, and command methods are visible in the three modified files.

- [ ] **Step 4: Build SunSmart for iPhoneOS**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit implementation**

Run:

```sh
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorVC.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerIconName.swift SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniView.swift
git commit -m "feat: update EFC feature buttons"
```

Expected: commit succeeds and includes only the three implementation files.

## Self-Review

- Spec coverage: UI image changes, 28/28/24 spacing, transparent buttons, Group AUTO loading, mock brightness actions, restore action branching, and validation are covered.
- Placeholder scan: no unresolved placeholders remain.
- Type consistency: all method names referenced in controller action closures are defined in Task 3; icon constants referenced in Task 3 are defined in Task 1.
