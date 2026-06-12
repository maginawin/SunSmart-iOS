# Hide Group Sensor Auto Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 group 详情页传感器区域隐藏 `group_auto` 状态小图标，同时保留右下角 `autoBtn` 的 AUTO 控制能力。

**Architecture:** 采用 UI 展示层隐藏方案，只改 `GroupSensorView.controlStateImageView` 的可见性，以及 `GroupViewController.updataSensorAutoStateUI()` 的显示出口。旧状态刷新、`LightLCLightOnOffStatus` 接收、`Node.lightControlOn` 和 AUTO 命令发送链路全部保留，便于后续新协议恢复。

**Tech Stack:** iOS, Swift, UIKit, SnapKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Main/Group/View/GroupSensorView.swift`
  - 负责 group 详情页传感器区域 UI。
  - 本次只让 `controlStateImageView` 初始化和刷新时保持隐藏。

- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 负责 group 详情页控制逻辑和 Mesh 消息回调。
  - 本次只调整 `updataSensorAutoStateUI()`，不改 `autoBtnAction(sender:)`。

- Reference: `docs/260610_1756_hide_group_sensor_auto_icon_plan.md`
  - 已确认的需求和推荐方案。

## Task 1: Hide Sensor Auto State Icon In GroupSensorView

**Files:**
- Modify: `SunSmart/Main/Group/View/GroupSensorView.swift`

- [ ] **Step 1: Capture current failing display path**

Run:

```bash
rg -n "controlStateImageView.isHidden = !sensor.lightControlOn|controlStateImageView = UIImageView" SunSmart/Main/Group/View/GroupSensorView.swift
```

Expected: output includes both lines:

```text
157:                    controlStateImageView.isHidden = !sensor.lightControlOn
464:        controlStateImageView = UIImageView(image: UIImage(named: "group_auto")?.withTintColor(.black))
```

This proves the current UI can still show `group_auto` when `sensor.lightControlOn == true`.

- [ ] **Step 2: Hide `controlStateImageView` at initialization**

In `SunSmart/Main/Group/View/GroupSensorView.swift`, find:

```swift
        controlStateImageView = UIImageView(image: UIImage(named: "group_auto")?.withTintColor(.black))
        topView.addSubview(controlStateImageView)
```

Change it to:

```swift
        controlStateImageView = UIImageView(image: UIImage(named: "group_auto")?.withTintColor(.black))
        controlStateImageView.isHidden = true
        topView.addSubview(controlStateImageView)
```

- [ ] **Step 3: Keep the icon hidden during ambient light sensor refresh**

In `SunSmart/Main/Group/View/GroupSensorView.swift`, find the ambient light branch:

```swift
                if let sensor = sensors.first(where: { $0.ambientLightSensorModel?.publish != nil && $0.sensorCalibrated && $0.steadyDaylightLux != nil && $0.state }) {
                    lightLuxLabel.text = "\(sensor.steadyDaylightLux!)lx"
                    lightLuxLabel.backgroundColor = RGB(245, 245, 245)

                    controlStateImageView.isHidden = !sensor.lightControlOn
                    startUpdateLuxTimer()
                }else {
                    controlStateImageView.isHidden = true
                    lightLuxLabel.text = nil
                    lightLuxLabel.backgroundColor = RGB(245, 245, 245)
                    controlStateImageView.tintColor = .black
                }
```

Change it to:

```swift
                if let sensor = sensors.first(where: { $0.ambientLightSensorModel?.publish != nil && $0.sensorCalibrated && $0.steadyDaylightLux != nil && $0.state }) {
                    lightLuxLabel.text = "\(sensor.steadyDaylightLux!)lx"
                    lightLuxLabel.backgroundColor = RGB(245, 245, 245)
                    controlStateImageView.isHidden = true
                    startUpdateLuxTimer()
                }else {
                    controlStateImageView.isHidden = true
                    lightLuxLabel.text = nil
                    lightLuxLabel.backgroundColor = RGB(245, 245, 245)
                    controlStateImageView.tintColor = .black
                }
```

Do not remove `controlStateImageView` or the `group_auto` asset reference.

- [ ] **Step 4: Verify no `lightControlOn` display dependency remains in GroupSensorView**

Run:

```bash
rg -n "controlStateImageView.isHidden = !sensor.lightControlOn" SunSmart/Main/Group/View/GroupSensorView.swift
```

Expected: no output, exit code `1`.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Group/View/GroupSensorView.swift
git diff --cached --check
git commit -m "fix: hide group sensor auto state icon"
```

Expected:

```text
[up-down-light <hash>] fix: hide group sensor auto state icon
```

## Task 2: Keep GroupViewController Auto State UI Exit Hidden

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Capture current controller display exit**

Run:

```bash
rg -n "private func updataSensorAutoStateUI|controlStateImageView.isHidden" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: output includes:

```text
633:    private func updataSensorAutoStateUI() {
635:            sensorView?.controlStateImageView.isHidden = !(group.info.ambientLightSensorNode?.lightControlOn ?? false)
637:            sensorView?.controlStateImageView.isHidden = true
```

This proves Mesh status callbacks can still ask the sensor view to show the icon.

- [ ] **Step 2: Force the controller update path to hide the icon**

In `SunSmart/Main/Group/Controller/GroupViewController.swift`, replace:

```swift
    private func updataSensorAutoStateUI() {
        if group.info.profile.type == .daylight {
            sensorView?.controlStateImageView.isHidden = !(group.info.ambientLightSensorNode?.lightControlOn ?? false)
        }else {
            sensorView?.controlStateImageView.isHidden = true
        }
    }
```

With:

```swift
    private func updataSensorAutoStateUI() {
        sensorView?.controlStateImageView.isHidden = true
    }
```

Do not modify:

```swift
    @objc private func autoBtnAction(sender: UIButton)
```

Do not modify:

```swift
        autoBtn = UIButton(normalImageName: isIPad ? "auto_big" : "auto", target: self, action: #selector(autoBtnAction))
```

- [ ] **Step 3: Verify the old controller display condition is gone**

Run:

```bash
rg -n "ambientLightSensorNode\\?\\.lightControlOn|profile.type == \\.daylight" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: no output related to `updataSensorAutoStateUI()`. Other matches elsewhere in the file are acceptable only if they are unrelated to `controlStateImageView`.

- [ ] **Step 4: Verify right-bottom auto button code remains present**

Run:

```bash
rg -n "autoBtnAction|LightLCLightOnOffSetUnacknowledged\\(true|autoBtn = UIButton" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: output still includes:

```text
774:    @objc private func autoBtnAction(sender: UIButton) {
790:        MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0), address: group.address.address)
1203:        autoBtn = UIButton(normalImageName: isIPad ? "auto_big" : "auto", target: self, action: #selector(autoBtnAction))
```

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git diff --cached --check
git commit -m "fix: keep group sensor auto state ui hidden"
```

Expected:

```text
[up-down-light <hash>] fix: keep group sensor auto state ui hidden
```

## Task 3: Final Verification

**Files:**
- Verify: `SunSmart/Main/Group/View/GroupSensorView.swift`
- Verify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Inspect final diff**

Run:

```bash
git diff HEAD~2..HEAD -- SunSmart/Main/Group/View/GroupSensorView.swift SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected:

- Diff only changes `controlStateImageView` visibility.
- Diff does not remove `refreshAutoState()`.
- Diff does not remove `LightLCLightOnOffStatus` handling.
- Diff does not modify `autoBtnAction(sender:)`.
- Diff does not modify right-bottom `autoBtn` initialization.

- [ ] **Step 2: Run whitespace checks**

Run:

```bash
git diff --check
git diff --cached --check
```

Expected: both commands produce no output and exit `0`.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build completes with:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 4: Manual UI verification**

Use a daylight harvesting (closed loop) group with an ambient light sensor.

Expected:

- Enter group detail page.
- Sensor area does not show the `group_auto` / `A` state icon.
- Trigger refresh or receive AUTO / non-AUTO state updates.
- Sensor area still does not show the `group_auto` / `A` state icon.
- Right-bottom `autoBtn` remains visible.
- Tapping right-bottom `autoBtn` still sends the group AUTO command.

- [ ] **Step 5: Confirm final worktree scope**

Run:

```bash
git status --short
```

Expected:

- No unstaged changes in `GroupSensorView.swift` or `GroupViewController.swift`.
- Unrelated pre-existing untracked files may remain untouched.
