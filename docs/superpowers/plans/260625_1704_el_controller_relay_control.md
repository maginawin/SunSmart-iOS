# EL Controller Relay Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `CID 0x0A78 / PID 0x24C1` 的 EL Controller 详情页右上角显示并复用现有 Relay 控件，同时保持其他 EM Sign 特例不变。

**Architecture:** 在 `Node` 上新增一个详情页专用能力判断，避免改变 `isEmergencySignController` 的既有语义。`DeviceLightViewController` 统一通过该能力判断控制 `relaySwitch` / `relayLabel` 的可见性，并继续使用现有 `MeshAPI.getReplyState` 与 `MeshAPI.setReplyState` 链路。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+Capability.swift`
  - Responsibility: 放置窄范围设备能力判断。新增 `supportsLightDetailRelayControl`，只服务 Light 详情页 Relay 显示能力，不替代 `isEmergencySignController`。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - Responsibility: 设备详情 UI。新增 Relay UI 状态 helper，并把现有直接按 `isEmergencySignController` 隐藏 Relay 的逻辑收口到 helper。
- No new files.
- No localization/resource/target/dependency changes.

## Scope Guard

- Do not rename or weaken `Node.isEmergencySignController`.
- Do not change `Node.isSupportVendorIdentify`.
- Do not change `DeviceLightsViewController` / `GroupViewController` / `GroupMembersViewController` list and group click blocking.
- Do not restore brightness, CCT, On/Off, lux, profile, or parameter settings for `0x24C1`.

### Task 1: Add Light Detail Relay Capability

**Files:**
- Modify: `SunSmart/Common/Data/Node+Capability.swift:46-52`

- [ ] **Step 1: Run preflight search**

Run:

```sh
rg -n "supportsLightDetailRelayControl|supportsUpDownRatioControl|isEmergencySignController" SunSmart/Common/Data/Node+Capability.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

```text
SunSmart/Common/Data/Node+Capability.swift:46:    var supportsUpDownRatioControl: Bool {
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1845:    static func isEmergencySignController(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1974:    var isEmergencySignController: Bool {
```

`supportsLightDetailRelayControl` should not exist before this task.

- [ ] **Step 2: Add the computed property**

In `SunSmart/Common/Data/Node+Capability.swift`, replace the tail of the extension with:

```swift
    var supportsUpDownRatioControl: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x2491
    }

    var supportsLightDetailRelayControl: Bool {
        if !isEmergencySignController {
            return true
        }
        return companyIdentifier == 0x0A78 && productIdentifier == 0x24C1
    }

}
```

- [ ] **Step 3: Verify the capability is isolated**

Run:

```sh
rg -n "supportsLightDetailRelayControl|isEmergencySignController" SunSmart/Common/Data/Node+Capability.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

```text
SunSmart/Common/Data/Node+Capability.swift:50:    var supportsLightDetailRelayControl: Bool {
SunSmart/Common/Data/Node+Capability.swift:51:        if !isEmergencySignController {
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1845:    static func isEmergencySignController(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> Bool {
SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1974:    var isEmergencySignController: Bool {
```

- [ ] **Step 4: Commit**

Run:

```sh
git add SunSmart/Common/Data/Node+Capability.swift
git commit -m "feat: add EL Controller relay capability"
```

Expected: one commit containing only `Node+Capability.swift`.

### Task 2: Use Capability in Light Detail Relay UI

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift:93-97`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift:175-183`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift:710-716`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift:736-743`

- [ ] **Step 1: Add Relay helper methods**

In `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`, insert these methods immediately before `private func updateControlPanel()`:

```swift
    private func updateRelayControlState() {
        relaySwitch.isOn = node.features?.relay == .enabled
        updateRelayControlVisibility()
    }

    private func updateRelayControlVisibility() {
        let shouldHideRelayControl = !node.supportsLightDetailRelayControl
        relaySwitch.isHidden = shouldHideRelayControl
        relayLabel.isHidden = shouldHideRelayControl
    }
```

- [ ] **Step 2: Use the helper in `viewDidLoad`**

Replace:

```swift
        relaySwitch.isHidden = node.isEmergencySignController
        relayLabel.isHidden = node.isEmergencySignController
```

With:

```swift
        updateRelayControlState()
```

Keep this line unchanged directly below it:

```swift
        MeshAPI.getReplyState(address: node.primaryUnicastAddress, result: nil)
```

- [ ] **Step 3: Update Relay state before emergency UI returns**

Replace the start of `updateData(refreshControlPanel:)` with:

```swift
    private func updateData(refreshControlPanel: Bool = true) {
        updateRelayControlState()

        if node.isEmergencySignController {
            updateEmergencySignData()
            return
        }

        if node.isKeybindComplete {
```

This removes the old duplicated line:

```swift
        self.relaySwitch.isOn = node.features?.relay == .enabled
```

- [ ] **Step 4: Preserve Relay visibility in EM Sign setup**

In `setupEmergencySignUI()`, replace:

```swift
        relaySwitch.isHidden = true
        relayLabel.isHidden = true
```

With:

```swift
        updateRelayControlState()
```

- [ ] **Step 5: Preserve Relay visibility during EM Sign data refresh**

In `updateEmergencySignData()`, replace:

```swift
        relaySwitch.isHidden = true
        relayLabel.isHidden = true
```

With:

```swift
        updateRelayControlState()
```

- [ ] **Step 6: Verify there are no emergency-specific Relay hides left**

Run:

```sh
rg -n "relay(Switch|Label)\\.isHidden|supportsLightDetailRelayControl|updateRelayControlState|updateRelayControlVisibility" SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Common/Data/Node+Capability.swift
```

Expected:

```text
The output contains one supportsLightDetailRelayControl definition in Node+Capability.swift.
The output contains updateRelayControlState calls in DeviceLightViewController.swift.
The output contains one updateRelayControlState definition in DeviceLightViewController.swift.
The output contains one updateRelayControlVisibility definition in DeviceLightViewController.swift.
The only relaySwitch.isHidden assignment is relaySwitch.isHidden = shouldHideRelayControl.
The only relayLabel.isHidden assignment is relayLabel.isHidden = shouldHideRelayControl.
```

No result should contain `relaySwitch.isHidden = true`, `relayLabel.isHidden = true`, or `relaySwitch.isHidden = node.isEmergencySignController`.

- [ ] **Step 7: Commit**

Run:

```sh
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: show relay for EL Controller detail"
```

Expected: one commit containing only `DeviceLightViewController.swift`.

### Task 3: Final Verification

**Files:**
- Verify only: `SunSmart/Common/Data/Node+Capability.swift`
- Verify only: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Check changed file scope**

Run:

```sh
git diff --stat HEAD~2..HEAD
```

Expected:

```text
SunSmart/Common/Data/Node+Capability.swift
SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Only these two implementation files should appear in the stat output.

- [ ] **Step 2: Check whitespace**

Run:

```sh
git diff --check HEAD~2..HEAD
```

Expected: no output and exit code 0.

- [ ] **Step 3: Verify protected behavior was not edited**

Run:

```sh
git diff HEAD~2..HEAD -- SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Controller/GroupMembersViewController.swift
```

Expected: no output.

- [ ] **Step 4: Build iPhoneOS**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Final status**

Run:

```sh
git status --short
```

Expected: no unstaged or untracked implementation changes. The plan document may be present only if it has not already been committed.
