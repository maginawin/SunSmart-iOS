# Change Control Page CCT Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference is Inline Execution.

**Goal:** 调整 `Change Control Page` 的 CCT 能力语义，使 `Single White` 只影响单设备 UI 展示，Group、Scene、Profile、批量控制等跨设备入口继续按真实 CCT Model 开放 CCT。

**Architecture:** 在本地 `NordicSigMeshSDK` 的 `Node` 属性层拆分能力语义：`effectiveSupportCct` 改为跨设备/自动化语义，等同真实 CCT Model 能力；新增 `singleDeviceDisplaySupportCct` 表示受 `Change Control Page` 影响的单设备 UI 展示能力。App 侧只把单设备页面、Header、Cell 和单设备详情改用新属性，其余 Group、Scene、Profile、批量控制路径继续使用 `effectiveSupportCct`。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、本地 Swift Package 引用、Xcode workspace `SunSmart.xcworkspace`。

---

## File Map

| 文件 | 责任 |
|---|---|
| `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` | 定义 CCT 能力语义；新增单设备展示能力属性 |
| `SunSmart/Main/Device/Controller/DeviceLightViewController.swift` | 单灯主控制页继续按 Single White 隐藏 CCT |
| `SunSmart/Main/Device/Controller/DeviceLightBasicController.swift` | 单灯基础控制页和单设备场景展示继续按 Single White 隐藏 CCT |
| `SunSmart/Main/Device/View/DeviceLightHeaderView.swift` | 单设备 Header 继续按 Single White 隐藏 CCT |
| `SunSmart/Main/Device/View/DevicesViewCell.swift` | 设备 Cell 继续按 Single White 不展示 CCT 属性/颜色 |
| `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift` | 单设备信息页的场景信息继续按 Single White 隐藏 CCT |
| `SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift` | DALI 单设备页继续按 Single White 隐藏 CCT |
| `docs/superpowers/plans/260601_1724_change_control_page_cct_capability.md` | 实现计划文档 |

---

### Task 1: Update SDK CCT Capability Semantics

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`

- [ ] **Step 1: Inspect the current SDK capability block**

Run:

```bash
sed -n '138,182p' /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: output contains `rawSupportCct`, `effectiveChangeControlPage`, and current `effectiveSupportCct` returning `rawSupportCct && effectiveChangeControlPage != .singleWhite`.

- [ ] **Step 2: Change the capability block**

In `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`, replace this block:

```swift
    var effectiveSupportCct: Bool {
        rawSupportCct && effectiveChangeControlPage != .singleWhite
    }
    
    var effectiveCctRange: ClosedRange<UInt16> {
        absoluteCctRange ?? defaultAbsoluteCctRange
    }
```

with:

```swift
    /// Cross-device and automation CCT capability.
    /// Change Control Page only affects single-device UI display.
    var effectiveSupportCct: Bool {
        rawSupportCct
    }
    
    /// Single-device UI display capability.
    /// Single White keeps CCT hidden on individual device pages and cells.
    var singleDeviceDisplaySupportCct: Bool {
        rawSupportCct && effectiveChangeControlPage != .singleWhite
    }
    
    var effectiveCctRange: ClosedRange<UInt16> {
        absoluteCctRange ?? defaultAbsoluteCctRange
    }
```

- [ ] **Step 3: Verify SDK symbols**

Run:

```bash
rg -n "effectiveSupportCct|singleDeviceDisplaySupportCct|rawSupportCct && effectiveChangeControlPage" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected:

```text
rawSupportCct
effectiveSupportCct
singleDeviceDisplaySupportCct
rawSupportCct && effectiveChangeControlPage != .singleWhite
```

`effectiveSupportCct` should return `rawSupportCct`.

- [ ] **Step 4: Check SDK diff**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff -- Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected: only the capability semantic block changed.

---

### Task 2: Update Single-Device UI Call Sites

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceLightBasicController.swift`
- Modify: `SunSmart/Main/Device/View/DeviceLightHeaderView.swift`
- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
- Modify: `SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift`

- [ ] **Step 1: Replace single-device capability checks**

Run this before editing to list the current single-device references:

```bash
rg -n "effectiveSupportCct" SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
```

Expected: references exist in the listed files.

Change only these single-device files so each `node.effectiveSupportCct`, `self.node.effectiveSupportCct`, or `device.effectiveSupportCct` used for UI display/row count/light type becomes the corresponding `singleDeviceDisplaySupportCct` property.

Use these replacement examples exactly:

```swift
if node.singleDeviceDisplaySupportCct {
    cctSlider.isHidden = false
    cctView.isHidden = false
} else {
    cctSlider.isHidden = true
    cctView.isHidden = true
}
```

```swift
return node.singleDeviceDisplaySupportCct ? 2 : 1
```

```swift
if device.singleDeviceDisplaySupportCct {
    progressView.progressColor = Node.getCctMixColor(temperature100: device.getEffectiveTemperature100(temperature: device.temperature))
} else {
    progressView.progressColor = RGB(156, 163, 175)
}
```

```swift
if node.singleDeviceDisplaySupportCct {
    lightType = .cct(range: node.effectiveCctRange)
} else if node.lightnessModel != nil {
    lightType = .lightness
} else {
    lightType = .onOff
}
```

- [ ] **Step 2: Verify single-device files no longer use cross-device capability**

Run:

```bash
rg -n "effectiveSupportCct" SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
```

Expected: no output.

- [ ] **Step 3: Verify single-device display capability appears in all intended files**

Run:

```bash
rg -n "singleDeviceDisplaySupportCct" SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
```

Expected: output includes all six files.

- [ ] **Step 4: Check App diff**

Run:

```bash
git diff -- SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
```

Expected: only `effectiveSupportCct` to `singleDeviceDisplaySupportCct` replacements in single-device UI files.

---

### Task 3: Verify Cross-Device Paths Still Use Effective CCT Capability

**Files:**
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Verify: `SunSmart/Main/Group/Model/GroupServer.swift`
- Verify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
- Verify: `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`
- Verify: `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
- Verify: `SunSmart/Main/Scene/Controller/ScenesViewController.swift`
- Verify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

- [ ] **Step 1: Confirm Group/Scene/Profile still use `effectiveSupportCct`**

Run:

```bash
rg -n "effectiveSupportCct" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Model/GroupServer.swift SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Scene/Controller/SceneAddViewController.swift SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift SunSmart/Main/Scene/Controller/ScenesViewController.swift SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
```

Expected: output remains in these cross-device files. These references are intentional because `effectiveSupportCct` now means real CCT capability for cross-device and automation flows.

- [ ] **Step 2: Confirm Device Parameter Settings still uses raw capability**

Run:

```bash
rg -n "rawSupportCct" SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift SunSmart/Main/Device/Parameter/Controller/DeviceParameterDevicesViewController.swift SunSmart/Main/Device/Parameter/View/DeviceParameterDeviceCell.swift
```

Expected: Device Parameter Settings paths still use `rawSupportCct` for Change Control Page and Absolute CCT Range availability.

- [ ] **Step 3: Confirm no cross-device file was accidentally moved to single-device display semantics**

Run:

```bash
rg -n "singleDeviceDisplaySupportCct" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Group SunSmart/Main/Device/Lights SunSmart/Main/Scene SunSmart/Main/Profile SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Common/Data/Node+SyncData.swift
```

Expected: no output.

---

### Task 4: Build and Regression Verification

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify: local Swift Package `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

- [ ] **Step 1: Check both git worktrees before build**

Run:

```bash
git status --short
```

Expected: only App files from Task 2 are modified, plus this plan document if it has not been committed yet.

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: only `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` is modified.

- [ ] **Step 2: Build SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Build other app schemes that reference NordicSigMeshSDK**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Final static verification**

Run:

```bash
rg -n "singleDeviceDisplaySupportCct" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
```

Expected: SDK property plus single-device UI references are present.

Run:

```bash
rg -n "effectiveSupportCct" SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
```

Expected: no output.

Run:

```bash
rg -n "effectiveSupportCct" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Model/GroupServer.swift SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Scene/Controller/SceneAddViewController.swift SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift SunSmart/Main/Scene/Controller/ScenesViewController.swift SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
```

Expected: cross-device references remain.

---

### Task 5: Commit Changes

**Files:**
- Commit in SDK repo: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Commit in App repo: single-device UI files and plan document

- [ ] **Step 1: Commit SDK change**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: split cct capability semantics"
```

Expected: SDK commit succeeds.

- [ ] **Step 2: Commit App change**

Run:

```bash
git add docs/superpowers/plans/260601_1724_change_control_page_cct_capability.md SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/Main/Device/Controller/DeviceLightBasicController.swift SunSmart/Main/Device/View/DeviceLightHeaderView.swift SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Device/Controller/DeviceInformationViewController.swift SunSmart/Main/Device/Dali/Controller/DaliMasterViewController.swift
git commit -m "fix: keep cct available outside single device pages"
```

Expected: App commit succeeds.

- [ ] **Step 3: Confirm clean status**

Run:

```bash
git status --short
```

Expected: no output.

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: no output.

---

## Manual QA Checklist

Use a device that has real CCT/CTL Temperature Model and set `Change Control Page = Single White`.

- [ ] Single device control page does not show CCT.
- [ ] Device Cell only shows brightness percentage and does not show CCT attributes.
- [ ] Device information/basic control single-device scene details do not show CCT.
- [ ] DALI single device page does not expose CCT for Single White display mode.
- [ ] Group page shows CCT if the group contains at least one real CCT device.
- [ ] Group CCT control updates real CCT devices and does not target pure DIM devices.
- [ ] Scene Settings group attribute popup shows CCT.
- [ ] Scene sync does not keep reporting needSync because of CCT on Single White CCT devices.
- [ ] Profile Power On Custom shows CCT and syncs CCT to real CCT devices.

---

## Self-Review

Spec coverage:

- Single-device pages keep hiding CCT: Task 2 and final static verification.
- Group/Scene/Profile/batch control use real CCT model: Task 1 changes `effectiveSupportCct`, Task 3 verifies cross-device references remain.
- Device Parameter Settings continues raw capability: Task 3 Step 2.
- Multi-target SDK impact checked: Task 4 builds SunSmart, Archipelago, SLG Sync Plus, and SylSmart.

Placeholder scan:

- No unresolved placeholder markers are present.

Type consistency:

- The new SDK property is consistently named `singleDeviceDisplaySupportCct`.
- Existing `rawSupportCct`, `effectiveSupportCct`, `effectiveChangeControlPage`, and `effectiveCctRange` names match current code.
