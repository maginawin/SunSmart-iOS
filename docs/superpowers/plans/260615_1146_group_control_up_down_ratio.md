# Group Control Up/Down Ratio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 group control page 中为包含 up/down light 的组增加 up/down ratio mode button，并复用单灯页 ratio 控件批量持久化所有 up/down light 成员的 `upRatio`。

**Architecture:** 改动集中在 `GroupViewController`，不修改模型层能力判断、不新增 Mesh 命令。按钮区改为 stack view 管理 2/3 个按钮，ratio 控件复用 `DeviceUpDownRatioControlView`，最终数据仍保存到每个 `Node.PreConfiguration.upRatio`。

**Tech Stack:** UIKit, SnapKit, NordicSigMeshSDK, SQLite-backed `Node.PreConfiguration`

---

## File Structure

- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 增加 group 页 ratio UI 状态。
  - 增加 up/down light 成员筛选。
  - 增加 ratio button、`DeviceUpDownRatioControlView` 和按钮 stack layout。
  - 绑定 ratio 控件回调，将值写入并保存到所有 up/down light 成员。
  - 在左右滑切 group 时重置 ratio UI 状态。
- No new production files.
- No new test target files; this repo 当前没有覆盖该 UIKit 页面交互的可运行单元测试目标，本任务使用 focused build 和手动回归清单验证。

## Task 1: Add Group Ratio State Helpers

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:18-105`

- [ ] **Step 1: Add ratio UI properties near existing view properties**

Insert these properties after `private var autoBtn: UIButton!`:

```swift
private let controlButtonsStackView = UIStackView()
private var upDownRatioModeBtn: UIButton!
private var upDownRatioControlView: DeviceUpDownRatioControlView!
private var isUpDownRatioModeSelected = false
private var groupUpRatioValue = 50
```

- [ ] **Step 2: Add ratio computed properties near `showsGroupControlPanel`**

Insert these computed properties after `showsGroupControlPanel`:

```swift
private var upDownRatioNodes: [Node] {
    group.nodes.filter { $0.supportsUpDownRatioControl }
}

private var showsUpDownRatioModeButton: Bool {
    !upDownRatioNodes.isEmpty
}
```

- [ ] **Step 3: Add reset and value helper methods**

Insert these methods before `updateUI()`:

```swift
private func resetGroupUpDownRatioState() {
    isUpDownRatioModeSelected = false
    groupUpRatioValue = 50
}

private func applyGroupUpRatioValue(_ value: Int) {
    let clampedValue = max(0, min(100, value))
    groupUpRatioValue = clampedValue
    upDownRatioNodes.forEach { node in
        node.upRatio = clampedValue
    }
    upDownRatioControlView.upValue = clampedValue
}

private func saveGroupUpRatioValue(_ value: Int) {
    applyGroupUpRatioValue(value)
    upDownRatioNodes.forEach { node in
        if let meshUUID = node.network?.uuid.uuidString {
            node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
        }
    }
}
```

- [ ] **Step 4: Run syntax-focused build check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: add group up down ratio state"
```

## Task 2: Replace Button Positioning With Stack Layout

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:1355-1406`

- [ ] **Step 1: Configure `controlButtonsStackView` before creating OnOff button**

In `setupUI()`, after the `pageControl` constraints and before `var offImageName = "group_off"`, add:

```swift
controlButtonsStackView.axis = .horizontal
controlButtonsStackView.alignment = .center
controlButtonsStackView.distribution = .equalSpacing
controlButtonsStackView.spacing = isIPad ? SCRXFrom(60) : SCRXFrom(40)
contentView.addSubview(controlButtonsStackView)
controlButtonsStackView.snp.makeConstraints { make in
    make.centerX.equalToSuperview()
    make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(isIPad ? 64 : 20))
}
```

- [ ] **Step 2: Move `onoffBtn` into the stack view**

Replace:

```swift
contentView.addSubview(onoffBtn)
onoffBtn.snp.makeConstraints { make in
    if isIPad {
        make.width.height.equalTo(56)
        make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-40))
        make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(64))
    }else {
        make.centerX.equalToSuperview().offset(SCRXFrom(-40))
        make.top.equalTo(collectionView.snp.bottom).offset(SCRYFit(20))
    }
}
```

with:

```swift
controlButtonsStackView.addArrangedSubview(onoffBtn)
onoffBtn.snp.makeConstraints { make in
    make.width.height.equalTo(isIPad ? 56 : 40)
}
```

- [ ] **Step 3: Move `autoBtn` into the stack view**

Replace:

```swift
contentView.addSubview(autoBtn)
autoBtn.snp.makeConstraints { make in
    make.centerY.equalTo(onoffBtn)
    if isIPad {
        make.width.height.equalTo(56)
        make.left.equalTo(onoffBtn.snp.right).offset(SCRXFrom(60))
    }else {
        make.left.equalTo(onoffBtn.snp.right).offset(SCRXFrom(40))
    }
}
```

with:

```swift
controlButtonsStackView.addArrangedSubview(autoBtn)
autoBtn.snp.makeConstraints { make in
    make.width.height.equalTo(isIPad ? 56 : 40)
}
```

- [ ] **Step 4: Add `upDownRatioModeBtn` as the third arranged button**

After the `autoBtn` constraints, add:

```swift
upDownRatioModeBtn = UIButton(
    normalImageName: "up down ratio button - unselected",
    selectedImageName: "up down ratio button - selected",
    target: self,
    action: #selector(upDownRatioModeBtnClick)
)
upDownRatioModeBtn.isHidden = true
controlButtonsStackView.addArrangedSubview(upDownRatioModeBtn)
upDownRatioModeBtn.snp.makeConstraints { make in
    make.width.height.equalTo(isIPad ? 56 : 40)
}
```

- [ ] **Step 5: Add the button action**

Insert this action near `autoBtnAction(sender:)`:

```swift
@objc private func upDownRatioModeBtnClick(sender: UIButton) {
    isUpDownRatioModeSelected.toggle()
    updateUpDownRatioUI()
}
```

- [ ] **Step 6: Run build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 7: Commit Task 2**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: add group ratio mode button"
```

## Task 3: Add And Layout The Ratio Control

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:1394-1406`

- [ ] **Step 1: Create `DeviceUpDownRatioControlView` before `controlPanelView` constraints**

After `contentView.addSubview(controlPanelView)` and before `controlPanelView.snp.makeConstraints`, add:

```swift
upDownRatioControlView = DeviceUpDownRatioControlView()
upDownRatioControlView.isHidden = true
contentView.addSubview(upDownRatioControlView)
upDownRatioControlView.snp.makeConstraints { make in
    if isIPad {
        make.left.equalTo(SCRXFrom(107))
        make.right.equalTo(SCRXFrom(-107))
    }else {
        make.left.right.equalTo(collectionView)
    }
    make.top.equalTo(controlButtonsStackView.snp.bottom).offset(SCRYFit(20))
}
```

- [ ] **Step 2: Replace static `controlPanelView` top constraint**

Replace the current `controlPanelView.snp.makeConstraints` block:

```swift
controlPanelView.snp.makeConstraints { make in
    if isIPad {
        make.left.equalTo(SCRXFrom(107))
        make.right.equalTo(SCRXFrom(-107))
    }else {
        make.left.right.equalTo(collectionView)
    }
    make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(8))
    make.bottom.equalToSuperview().offset(-(collapsedSensorViewHeight + SCRYFit(20)))
}
```

with:

```swift
controlPanelView.snp.makeConstraints { make in
    if isIPad {
        make.left.equalTo(SCRXFrom(107))
        make.right.equalTo(SCRXFrom(-107))
    }else {
        make.left.right.equalTo(collectionView)
    }
    make.top.equalTo(controlButtonsStackView.snp.bottom).offset(SCRYFit(8))
    make.bottom.equalToSuperview().offset(-(collapsedSensorViewHeight + SCRYFit(20)))
}
```

- [ ] **Step 3: Add `updateUpDownRatioUI()`**

Insert this method after `updateControlPanel()`:

```swift
private func updateUpDownRatioUI() {
    let showsModeButton = showsUpDownRatioModeButton
    if !showsModeButton {
        isUpDownRatioModeSelected = false
        groupUpRatioValue = 50
    }

    upDownRatioModeBtn.isHidden = !showsModeButton
    upDownRatioModeBtn.isSelected = showsModeButton && isUpDownRatioModeSelected

    let showsRatioControl = showsModeButton && isUpDownRatioModeSelected
    upDownRatioControlView.isHidden = !showsRatioControl
    upDownRatioControlView.upValue = groupUpRatioValue

    controlPanelView.snp.remakeConstraints { make in
        if isIPad {
            make.left.equalTo(SCRXFrom(107))
            make.right.equalTo(SCRXFrom(-107))
        }else {
            make.left.right.equalTo(collectionView)
        }
        if showsRatioControl {
            make.top.equalTo(upDownRatioControlView.snp.bottom).offset(SCRYFit(isIPad ? 16 : 8))
        } else {
            make.top.equalTo(controlButtonsStackView.snp.bottom).offset(SCRYFit(8))
        }
        make.bottom.equalToSuperview().offset(-(collapsedSensorViewHeight + SCRYFit(20)))
    }
}
```

- [ ] **Step 4: Call `updateUpDownRatioUI()` from `updateUI()`**

In `updateUI()`, after:

```swift
updateControlPanel()
```

add:

```swift
updateUpDownRatioUI()
```

- [ ] **Step 5: Run build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: show group up down ratio control"
```

## Task 4: Bind Ratio Control Persistence

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:884-938`

- [ ] **Step 1: Bind ratio callbacks in `bindSliderAciton()`**

At the end of `bindSliderAciton()`, after `controlPanelView.editCCTRequested`, add:

```swift
upDownRatioControlView.valueChanging = { [weak self] value in
    guard let self else { return }
    self.applyGroupUpRatioValue(value)
}

upDownRatioControlView.valueChanged = { [weak self] value in
    guard let self else { return }
    self.saveGroupUpRatioValue(value)
}
```

- [ ] **Step 2: Keep ratio UI current after brightness changes**

In `applyGroupBrightnessValue(_:)`, after updating all nodes:

```swift
updateUpDownRatioUI()
```

The final method should include:

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
    updateUpDownRatioUI()
}
```

- [ ] **Step 3: Keep ratio UI current after CCT changes**

In `applyGroupCCTValue(_:)`, before `return temperature`, add:

```swift
updateUpDownRatioUI()
```

The final method should include:

```swift
@discardableResult
private func applyGroupCCTValue(_ value: Int) -> UInt16 {
    let range = currentGroupCCTRange
    let clampedValue = max(range.lowerBound, min(range.upperBound, value))
    let temperature = UInt16(clampedValue)
    group.cct = Int(temperature)
    groupControlCCTNodes.forEach {
        $0.temperature = $0.clampEffectiveCct(temperature)
    }
    updateUpDownRatioUI()
    return temperature
}
```

- [ ] **Step 4: Run build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: persist group up down ratio"
```

## Task 5: Reset State On Group Swipe And Refresh Entries

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:167-212`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:796-868`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:1240-1260`
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:1588-1597`

- [ ] **Step 1: Reset ratio state when swiping to previous group**

In `groupPreviousSwipeAction()`, after:

```swift
self.group = previousGroup
```

add:

```swift
resetGroupUpDownRatioState()
```

- [ ] **Step 2: Reset ratio state when swiping to next group**

In `groupNextSwipeAction()`, after:

```swift
self.group = nextGroup
```

add:

```swift
resetGroupUpDownRatioState()
```

- [ ] **Step 3: Refresh ratio UI after OnOff local update**

In `onoffBtnClick(sender:)`, after:

```swift
controlPanelView.setBrightnessValue(group.isOn ? Node.getLightness100(lightness: group.lightness) : 0)
```

add:

```swift
updateUpDownRatioUI()
```

- [ ] **Step 4: Refresh ratio UI after AUTO local update**

In `autoBtnAction(sender:)`, after:

```swift
onoffBtn.isSelected = group.isOn
```

add:

```swift
updateUpDownRatioUI()
```

- [ ] **Step 5: Refresh ratio UI after device item reload**

In `reloadCollectionItem(node:)`, after:

```swift
updateControlPanel()
```

add:

```swift
updateUpDownRatioUI()
```

- [ ] **Step 6: Refresh ratio UI after switch action messages**

In `didReceiveMessage`, inside the `if isSwitchAction` branch, after:

```swift
updateControlPanel()
```

add:

```swift
updateUpDownRatioUI()
```

- [ ] **Step 7: Run build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: PASS.

- [ ] **Step 8: Commit Task 5**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "fix: refresh group up down ratio state"
```

## Task 6: Final Verification

**Files:**
- Verify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Verify: `docs/superpowers/specs/260615_1137_group_control_up_down_ratio_design.md`
- Verify: `docs/superpowers/plans/260615_1146_group_control_up_down_ratio.md`

- [ ] **Step 1: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 2: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual QA checklist**

Use a group without up/down light:

```text
Expected: only OnOff and AUTO buttons are visible.
Expected: no up/down ratio mode button is visible.
Expected: controlPanelView starts at the same vertical position as before.
```

Use a group with at least one `supportsUpDownRatioControl` member:

```text
Expected: OnOff, AUTO, and up/down ratio mode buttons are visible.
Expected: ratio mode button starts unselected.
Expected: tapping ratio mode button selects it and shows DeviceUpDownRatioControlView.
Expected: tapping ratio mode button again hides DeviceUpDownRatioControlView.
Expected: opening a child page and returning keeps the current selected state and ratio value.
Expected: swiping to another group resets ratio mode to unselected and value to 50/50.
Expected: changing ratio writes the same upRatio to every supportsUpDownRatioControl member.
Expected: changing ratio does not write upRatio to non-up/down light members.
```

- [ ] **Step 4: Final status**

Run:

```bash
git status --short
```

Expected: only intentional implementation changes are present, or clean if all task commits were created.
