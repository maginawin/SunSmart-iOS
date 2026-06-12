# Group Control Content Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference is Inline Execution.

**Goal:** Update the Group control page to consume Space Content Display settings for CCT quick buttons and Simple/Detailed control style.

**Architecture:** Reuse `DeviceLightControlPanelView` on `GroupViewController` and keep group-specific state, Mesh commands, emergency guards, and limit warnings inside the controller. Add a scrollable bottom control region only, so the existing group members collection, On/Off button, Auto button, group swipe gestures, and collapsed `GroupSensorView` remain structurally stable.

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`.

---

## File Map

| File | Responsibility |
|---|---|
| `SunSmart/Main/Group/Controller/GroupViewController.swift` | Replace direct group sliders with `DeviceLightControlPanelView`, add bottom-only scroll container, wire group brightness/CCT commands and limit warning |
| `SunSmart/en.lproj/Localizable.strings` | Add English group CCT limit warning |
| `SunSmart/zh-Hans.lproj/Localizable.strings` | Add Simplified Chinese group CCT limit warning |

No test target is used for this screen. Verification is source-level checks plus the required iPhoneOS `xcodebuild`.

---

### Task 1: Add Group CCT Limit Localization

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add the English string**

Add this entry near the existing `cct_limit_reached_message` key in `SunSmart/en.lproj/Localizable.strings`:

```text
"group_cct_limit_reached_message" = "Some devices have reached their color temperature limit.";
```

- [ ] **Step 2: Add the Simplified Chinese string**

Add this entry near the existing CCT limit key in `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"group_cct_limit_reached_message" = "部分设备已达到色温限制。";
```

- [ ] **Step 3: Verify both keys exist once**

Run:

```bash
rg -n '"group_cct_limit_reached_message"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: exactly two matches, one in each localization file.

- [ ] **Step 4: Commit localization**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add group cct limit message"
```

---

### Task 2: Replace Group Sliders With Reusable Control Panel Layout

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Replace old slider properties**

In `GroupViewController`, replace these properties:

```swift
private var lightnessSlider: BuoySliderView!
private var cctSlider: BuoySliderView!
```

with:

```swift
private var controlScrollView: UIScrollView!
private var controlContentView: UIView!
private var controlPanelView: DeviceLightControlPanelView!
```

- [ ] **Step 2: Add control panel computed helpers**

Add these helpers inside `GroupViewController`, near the existing stored properties:

```swift
private var collapsedSensorViewHeight: CGFloat {
    SCRYFrom(40) + kSafeAreaBottomHeight
}

private var currentGroupBrightnessRange: ClosedRange<Int> {
    let data = group.info.profile.lightControlData
    return data.lowEndTrim...data.highEndTrim
}

private var currentGroupCCTRange: ClosedRange<Int> {
    let range = group.effectiveCctRange
    return Int(range.lowerBound)...Int(range.upperBound)
}

private var showsGroupControlPanel: Bool {
    group.supportLightness || group.effectiveSupportCct
}
```

- [ ] **Step 3: Replace slider creation in `setupUI()`**

In `setupUI()`, remove the creation and constraints for `lightnessSlider` and `cctSlider`. Specifically remove the block that starts with:

```swift
lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
```

and ends after the `cctSlider.snp.makeConstraints` block.

Insert this block in the same location, after `autoBtn` constraints and before `calibrateBtn` creation:

```swift
controlScrollView = UIScrollView()
controlScrollView.alwaysBounceVertical = false
controlScrollView.delaysContentTouches = false
controlScrollView.showsVerticalScrollIndicator = false
view.addSubview(controlScrollView)
controlScrollView.snp.makeConstraints { make in
    if isIPad {
        make.left.equalTo(SCRXFrom(107))
        make.right.equalTo(SCRXFrom(-107))
    } else {
        make.left.right.equalTo(collectionView)
    }
    make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(30))
    make.bottom.equalToSuperview().offset(-collapsedSensorViewHeight)
}

controlContentView = UIView()
controlScrollView.addSubview(controlContentView)
controlContentView.snp.makeConstraints { make in
    make.edges.equalToSuperview()
    make.width.equalTo(controlScrollView)
}

controlPanelView = DeviceLightControlPanelView()
controlContentView.addSubview(controlPanelView)
controlPanelView.snp.makeConstraints { make in
    make.top.left.right.bottom.equalToSuperview()
}
```

- [ ] **Step 4: Add `updateControlPanel()`**

Add this method near `updateUI()`:

```swift
private func updateControlPanel() {
    controlScrollView.isHidden = !showsGroupControlPanel
    controlPanelView.isHidden = !showsGroupControlPanel
    guard showsGroupControlPanel else {
        return
    }

    let brightnessValue = group.isOn ? Node.getLightness100(lightness: group.lightness) : 0
    let cctRange = currentGroupCCTRange
    controlPanelView.configure(.init(
        controlType: space.controlType,
        showCCTQuickButtons: space.showCCTQuickButtons,
        showsBrightness: group.supportLightness,
        showsCCT: group.effectiveSupportCct,
        brightnessValue: brightnessValue,
        brightnessRange: currentGroupBrightnessRange,
        cctValue: max(cctRange.lowerBound, min(cctRange.upperBound, group.cct)),
        cctRange: cctRange
    ))
}
```

The `brightnessValue` uses `0` when the group is off to preserve the current `onoffBtnClick` behavior where the old slider was explicitly set to zero.

- [ ] **Step 5: Replace slider refresh in `updateUI()`**

In `updateUI()`, replace this existing block:

```swift
let data = group.info.profile.lightControlData
lightnessSlider.slider.limitRange = data.lowEndTrim...data.highEndTrim
lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
if group.effectiveSupportCct {
    cctSlider.updateCctRange(group.effectiveCctRange)
    cctSlider.value = Int(group.clampEffectiveCct(UInt16(group.cct)))
    cctSlider.isHidden = false
}else {
    cctSlider.isHidden = true
}
```

with:

```swift
updateControlPanel()
```

- [ ] **Step 6: Verify old setup references are gone**

Run:

```bash
rg -n "lightnessSlider|cctSlider" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected at this point: matches may still remain in action handlers and refresh paths. There should be no matches in `setupUI()` and no property declarations for `lightnessSlider` or `cctSlider`.

- [ ] **Step 7: Commit layout replacement**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: add group control panel layout"
```

---

### Task 3: Wire Group Control Panel Actions And State Updates

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Replace `bindSliderAciton()` content**

Keep the existing method name `bindSliderAciton()` to avoid unrelated call-site churn. Replace its entire body with:

```swift
private func bindSliderAciton() {
    controlPanelView.brightnessValueChanged = { [weak self] value in
        guard let self else { return }
        guard !self.showEmergencyControlBlockedIfNeeded() else {
            self.updateControlPanel()
            return
        }
        self.applyGroupBrightnessValue(value)
    }

    controlPanelView.brightnessThrottleValueChanged = { [weak self] value, ended in
        guard let self else { return }
        guard !self.showEmergencyControlBlockedIfNeeded() else {
            self.updateControlPanel()
            return
        }
        self.sendGroupBrightnessValue(value, ended: ended)
    }

    controlPanelView.cctValueChanged = { [weak self] value in
        guard let self else { return }
        guard !self.showEmergencyControlBlockedIfNeeded() else {
            self.updateControlPanel()
            return
        }
        _ = self.applyGroupCCTValue(value)
    }

    controlPanelView.cctThrottleValueChanged = { [weak self] value, ended in
        guard let self else { return }
        guard !self.showEmergencyControlBlockedIfNeeded() else {
            self.updateControlPanel()
            return
        }
        let temperature = self.applyGroupCCTValue(value)
        MeshAPI.setGroupColorTemperatureState(address: self.group.address.address, temperature: temperature)
        if ended {
            self.reloadVisibleGroupDeviceItems()
            self.showGroupCCTLimitMessageIfNeeded(target: value)
        }
        self.refreshAutoState()
    }

    controlPanelView.cctQuickButtonValueSelected = { [weak self] value in
        self?.applyGroupCCTQuickButtonValue(value)
    }

    controlPanelView.editBrightnessRequested = { [weak self] in
        self?.showGroupBrightnessInputAlert()
    }

    controlPanelView.editCCTRequested = { [weak self] in
        self?.showGroupCCTInputAlert()
    }
}
```

- [ ] **Step 2: Add brightness helpers**

Add these methods near `bindSliderAciton()`:

```swift
private func applyGroupBrightnessValue(_ value: Int) {
    let clampedValue = max(currentGroupBrightnessRange.lowerBound, min(currentGroupBrightnessRange.upperBound, value))
    let lightness = Node.getLightness(lightness100: clampedValue)
    group.lightness = lightness
    group.isOn = lightness > 0
    onoffBtn.isSelected = group.isOn
    group.nodes.forEach {
        $0.isOn = lightness > 0
        $0.lightness = lightness
    }
}

private func sendGroupBrightnessValue(_ value: Int, ended: Bool) {
    let clampedValue = max(currentGroupBrightnessRange.lowerBound, min(currentGroupBrightnessRange.upperBound, value))
    let lightness = Node.getLightness(lightness100: clampedValue)
    MeshAPI.setGroupLightnessState(address: group.address.address, lightness: lightness)
    if ended {
        reloadVisibleGroupDeviceItems()
    }
    refreshAutoState()
}
```

- [ ] **Step 3: Add CCT helpers and limit detection**

Add these methods near the brightness helpers:

```swift
@discardableResult
private func applyGroupCCTValue(_ value: Int) -> UInt16 {
    let range = currentGroupCCTRange
    let clampedValue = max(range.lowerBound, min(range.upperBound, value))
    let temperature = UInt16(clampedValue)
    group.cct = Int(temperature)
    group.nodes.filter { $0.effectiveSupportCct }.forEach {
        $0.temperature = $0.clampEffectiveCct(temperature)
    }
    return temperature
}

private func applyGroupCCTQuickButtonValue(_ value: Int) {
    guard !showEmergencyControlBlockedIfNeeded() else {
        updateControlPanel()
        return
    }
    let temperature = applyGroupCCTValue(value)
    controlPanelView.setCCTValue(Int(temperature))
    MeshAPI.setGroupColorTemperatureState(address: group.address.address, temperature: temperature)
    reloadVisibleGroupDeviceItems()
    showGroupCCTLimitMessageIfNeeded(target: value)
    refreshAutoState()
}

private func showGroupCCTLimitMessageIfNeeded(target: Int) {
    let targetValue = UInt16(max(0, min(Int(UInt16.max), target)))
    let hasLimitedDevice = group.nodes
        .filter { $0.effectiveSupportCct }
        .contains { node in
            targetValue < node.effectiveCctRange.lowerBound || targetValue > node.effectiveCctRange.upperBound
        }
    guard hasLimitedDevice else {
        return
    }
    XWHUDManager.showTipHUD("group_cct_limit_reached_message".localizedString, isLineFeed: true)
}

private func reloadVisibleGroupDeviceItems() {
    CATransaction.setDisableActions(true)
    collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
    CATransaction.commit()
}
```

- [ ] **Step 4: Add Detailed input alerts**

Add these methods near the control helpers:

```swift
private func showGroupBrightnessInputAlert() {
    guard !showEmergencyControlBlockedIfNeeded() else {
        updateControlPanel()
        return
    }
    let range = currentGroupBrightnessRange
    showIntegerInputAlert(
        title: "brightness".localizedString,
        range: range
    ) { [weak self] value in
        guard let self else { return }
        self.controlPanelView.setBrightnessValue(value)
        self.applyGroupBrightnessValue(value)
        self.sendGroupBrightnessValue(value, ended: true)
    }
}

private func showGroupCCTInputAlert() {
    guard !showEmergencyControlBlockedIfNeeded() else {
        updateControlPanel()
        return
    }
    let range = currentGroupCCTRange
    showIntegerInputAlert(
        title: "color_temp".localizedString,
        range: range
    ) { [weak self] value in
        guard let self else { return }
        let temperature = self.applyGroupCCTValue(value)
        self.controlPanelView.setCCTValue(Int(temperature))
        MeshAPI.setGroupColorTemperatureState(address: self.group.address.address, temperature: temperature)
        self.reloadVisibleGroupDeviceItems()
        self.showGroupCCTLimitMessageIfNeeded(target: value)
        self.refreshAutoState()
    }
}

private func showIntegerInputAlert(title: String, range: ClosedRange<Int>, confirm: @escaping (Int) -> Void) {
    SRAlertView(
        title: title,
        inputText: nil,
        inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: 5, textAlignment: .center, showClear: true),
        actions: [.cancelAction, SRAlertAction(title: "COMFIRM".localizedString, style: .default)],
        textValueChangedBack: nil
    ) { text in
        guard let value = Int(text) else {
            XWHUDManager.showTipHUD("illegal_input".localizedString, isLineFeed: true)
            return
        }
        let clamped = max(range.lowerBound, min(range.upperBound, value))
        confirm(clamped)
    }.show()
}
```

This input helper intentionally mirrors `DeviceLightViewController` and uses the existing `"COMFIRM"` localization key.

- [ ] **Step 5: Replace old slider updates in button handlers**

In `onoffBtnClick(sender:)`, replace:

```swift
lightnessSlider.value = group.isOn ? Node.getLightness100(lightness: group.lightness) : 0
```

with:

```swift
controlPanelView.setBrightnessValue(group.isOn ? Node.getLightness100(lightness: group.lightness) : 0)
```

In `autoBtnAction(sender:)`, replace:

```swift
lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
```

with:

```swift
controlPanelView.setBrightnessValue(Node.getLightness100(lightness: group.lightness))
```

There are two old `lightnessSlider` references in `autoBtnAction`: one active and one commented. Remove the commented old reference instead of updating it.

- [ ] **Step 6: Replace old slider updates in refresh paths**

In `reloadCollectionItem(node:)`, replace:

```swift
if group.isOn != onoffBtn.isSelected {
    lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
}
onoffBtn.isSelected = group.isOn
//        cctSlider.value = group.cct
```

with:

```swift
if group.isOn != onoffBtn.isSelected {
    controlPanelView.setBrightnessValue(Node.getLightness100(lightness: group.lightness))
}
onoffBtn.isSelected = group.isOn
updateControlPanel()
```

In the `didReceiveMessage` branch for `isSwitchAction`, replace:

```swift
if group.isOn != onoffBtn.isSelected {
    lightnessSlider.value = Node.getLightness100(lightness: group.lightness)
}
onoffBtn.isSelected = group.isOn
```

with:

```swift
if group.isOn != onoffBtn.isSelected {
    controlPanelView.setBrightnessValue(Node.getLightness100(lightness: group.lightness))
}
onoffBtn.isSelected = group.isOn
updateControlPanel()
```

- [ ] **Step 7: Verify all old slider references are removed**

Run:

```bash
rg -n "lightnessSlider|cctSlider" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: no output.

- [ ] **Step 8: Commit action wiring**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: wire group content display controls"
```

---

### Task 4: Build Verification And Regression Checks

**Files:**
- Verify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Check focused diff**

Run:

```bash
git diff --stat
git diff -- SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: only the Group controller and two localization files have unstaged changes if the previous task commits were skipped; otherwise no unstaged diff.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check
git diff --cached --check
```

Expected: no output.

- [ ] **Step 3: Check old slider removal**

Run:

```bash
rg -n "lightnessSlider|cctSlider" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: no output.

- [ ] **Step 4: Check required string usage**

Run:

```bash
rg -n "group_cct_limit_reached_message" SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: one usage in `GroupViewController.swift` and one definition in each localization file.

- [ ] **Step 5: Build SunSmart for iPhoneOS**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Review acceptance criteria manually from source**

Check these source facts after implementation:

- `GroupViewController.updateControlPanel()` uses `space.controlType`.
- `GroupViewController.updateControlPanel()` uses `space.showCCTQuickButtons`.
- `GroupViewController.updateControlPanel()` uses `group.effectiveCctRange`.
- `controlScrollView.top` is constrained to `onoffBtn.snp.bottom` with `SCRYFit(30)`.
- `controlScrollView.bottom` offsets by `-collapsedSensorViewHeight`.
- `showGroupCCTLimitMessageIfNeeded(target:)` is called from quick button, CCT slider ended, and Detailed CCT input.
- `showGroupCCTLimitMessageIfNeeded(target:)` checks each CCT node's own `effectiveCctRange`, not just `group.effectiveCctRange`.

- [ ] **Step 7: Final commit if needed**

If Tasks 1-3 were not committed individually, commit the final implementation:

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: support group content display controls"
```

If Tasks 1-3 already produced commits and Step 1 shows no remaining diff, skip this step.
