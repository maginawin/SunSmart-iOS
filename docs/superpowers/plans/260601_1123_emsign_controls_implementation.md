# EMSign Controls Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 EMSign 设备在 Lights 与 Group 相关设备控件中保持 ON 视觉、不显示亮度/色温条、点击不发送单设备控制命令，并将单设备页 Identify 图标换为 `Identify`。

**Architecture:** 使用现有 `Node.isEmergencySignController` 作为唯一产品识别入口。展示规则放在 `DevicesViewCell`，让 `GroupDeviceViewCell` 自动继承；点击拦截放在各页面 `didSelectItemAt` 的最早安全入口，避免普通灯和组级控制行为受影响。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`
  - 负责 Site - Space - Main - Lights、Group Members 等复用圆形设备控件的基础渲染。
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - 负责 Lights 列表单设备点击控制。
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - 负责 Group 详情页设备控件点击控制。
- Modify: `SunSmart/Main/Group/Controller/GroupMembersViewController.swift`
  - 负责 Group Members/组成员管理页设备控件点击控制。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 负责 EMSign 单设备 Identify-only 页面。

## Task 1: EMSign Cell Display

**Files:**
- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift:32-86`

- [ ] **Step 1: Add EMSign display branch in `device.didSet`**

In `DevicesViewCell.device.didSet`, inside `if device.isKeybindComplete { ... if device.state { ... } }`, insert an EMSign branch before the existing `if device.isOn { ... } else { ... }` block:

```swift
if device.isEmergencySignController {
    nameLabel.textColor = Title_Color
    backgroundColor = .white
    progressView.isHidden = true
    progressView.setProgress(0, animated: false)
    device.lastLightness = 0
} else if device.isOn {
    nameLabel.textColor = Title_Color
    var lightness100 = Node.getLightness100(lightness: device.lightness)
    if device.isOn, device.lightness == 0, let trunOffLightness = device.trunOffLightness {
        lightness100 = Node.getLightness100(lightness: trunOffLightness)
    }

    progress = lightness100

    if device.lastLightness != device.lightness {
        device.lastLightness = device.lightness
        progressAnimation = true
    }
} else {
    nameLabel.textColor = RGB(148, 163, 184)
    backgroundColor = RGB(226, 226, 226)
    progress = 0
}
```

- [ ] **Step 2: Prevent progress bar from being re-shown for EMSign**

Replace the existing progress visibility assignment:

```swift
progressView.isHidden = !device.supportDimming
```

with:

```swift
progressView.isHidden = device.isEmergencySignController || !device.supportDimming
```

Keep `progressView.setProgress(Int(progress), animated: progressAnimation)` and progress color logic unchanged for ordinary lights.

- [ ] **Step 3: Static check for display branch**

Run:

```bash
rg -n "isEmergencySignController|progressView.isHidden" SunSmart/Main/Device/View/DevicesViewCell.swift
```

Expected:
- One EMSign branch in `device.didSet`.
- The progress visibility expression includes `device.isEmergencySignController`.

## Task 2: Lights List Click Interception

**Files:**
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift:972-1016`

- [ ] **Step 1: Add EMSign no-op before emergency block and repair flow**

In `collectionView(_:didSelectItemAt:)`, inside the device-click branch, directly after:

```swift
let node = devices[indexPath.row - 1]
```

insert:

```swift
guard !node.isEmergencySignController else {
    return
}
```

This placement ensures EMSign taps do not show emergency block HUD, do not repair, do not query On/Off, do not mutate state, and do not send commands.

- [ ] **Step 2: Static check Lights interception**

Run:

```bash
nl -ba SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift | sed -n '970,982p'
```

Expected:
- `let node = devices[indexPath.row - 1]`
- Then `guard !node.isEmergencySignController else { return }`
- Then existing `showEmergencyControlBlockedIfNeeded(node: node)` guard.

## Task 3: Group Detail Click Interception

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift:1311-1330`

- [ ] **Step 1: Add EMSign no-op before emergency block**

In `collectionView(_:didSelectItemAt:)`, directly after:

```swift
let node = group.nodes[indexPath.item]
```

insert:

```swift
guard !node.isEmergencySignController else {
    return
}
```

This keeps Group-level controls unchanged while making EMSign single-device taps inert.

- [ ] **Step 2: Static check Group detail interception**

Run:

```bash
nl -ba SunSmart/Main/Group/Controller/GroupViewController.swift | sed -n '1311,1320p'
```

Expected:
- `let node = group.nodes[indexPath.item]`
- Then `guard !node.isEmergencySignController else { return }`
- Then existing `showEmergencyControlBlockedIfNeeded()` guard.

## Task 4: Group Members Click Interception

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:612-628`

- [ ] **Step 1: Add EMSign no-op at the start of member device selection**

In `collectionView(_:didSelectItemAt:)`, directly after:

```swift
let node = nodes[indexPath.item]
```

insert:

```swift
guard !node.isEmergencySignController else {
    return
}
```

This prevents EMSign member cells from entering repair/offline OnOff query or single-device On/Off control.

- [ ] **Step 2: Static check Group Members interception**

Run:

```bash
nl -ba SunSmart/Main/Group/Controller/GroupMembersViewController.swift | sed -n '612,622p'
```

Expected:
- `let node = nodes[indexPath.item]`
- Then `guard !node.isEmergencySignController else { return }`
- Then existing keybind/offline checks.

## Task 5: EMSign Identify Icon

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift:668-674`

- [ ] **Step 1: Change Identify button asset name**

Replace:

```swift
let identifyButton = UIButton(normalImageName: "device_identify", target: self, action: #selector(emergencySignIdentifyAction))
```

with:

```swift
let identifyButton = UIButton(normalImageName: "Identify", target: self, action: #selector(emergencySignIdentifyAction))
```

Keep the existing constraint:

```swift
make.width.height.equalTo(SCRYFit(40))
```

- [ ] **Step 2: Static check Identify asset and size**

Run:

```bash
nl -ba SunSmart/Main/Device/Controller/DeviceLightViewController.swift | sed -n '666,674p'
```

Expected:
- Button uses `normalImageName: "Identify"`.
- Width and height remain `SCRYFit(40)`.

## Task 6: Build Verification

**Files:**
- Verify only.

- [ ] **Step 1: Review focused diff**

Run:

```bash
git diff -- SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Controller/GroupMembersViewController.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected:
- Only EMSign display/click interception and Identify icon changes appear.
- No unrelated formatting churn.

- [ ] **Step 2: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:
- `** BUILD SUCCEEDED **`
- Existing project warnings may remain, but no new compile errors.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Controller/GroupMembersViewController.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "fix: optimize EMSign device controls"
```

Expected:
- Commit succeeds with only the five implementation files staged.

## Self-Review

- Spec coverage: Task 1 covers ON visual and hidden progress bars; Tasks 2-4 cover no-op taps in Lights, Group detail, and Group Members; Task 5 covers Identify icon and 40x40 size; Task 6 covers diff and build verification.
- Placeholder scan: no unresolved placeholder language is present.
- Type consistency: all references use existing `Node.isEmergencySignController`, `progressView`, `DevicesViewCell`, `GroupDeviceViewCell`, and existing controller method names.
