# Brightness Trim Slider Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 恢复设备控制页和组控页亮度滑条 0...100 总轨道、low/high trim 灰色禁用段，以及不可滑入禁用区的旧行为。

**Architecture:** 保持现有 `DeviceLightControlPanelView.Configuration.brightnessRange` 语义不变，将它解释为可交互 trim range；新增内部亮度总轨道范围 0...100。只修改共享控制面板，设备页继续传 `node.lightnessRange`，组控页继续传 `group.info.profile.lightControlData.lowEndTrim...highEndTrim`，Proximity/Predictive lighting with photocell 继续使用顶层 effective trim。

**Tech Stack:** Swift、UIKit、现有 `CustomDeviceSlider.limitRange`、iPhoneOS `xcodebuild` 验证。

---

### Task 1: 恢复亮度 slider 总轨道与禁用灰段

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift`
- Verify: source check, `git diff --check`, iPhoneOS build

- [ ] **Step 1: 运行 RED source check**

Run:

```bash
rg -n "brightnessTrackRange" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected: FAIL, because current implementation has no fixed 0...100 brightness track range.

- [ ] **Step 2: 修改共享控制面板**

In `DeviceLightControlPanelView`:

```swift
private static let brightnessTrackRange = 0...100
```

Update brightness slider setup so `minimumValue` and `maximumValue` use `brightnessTrackRange`, while `limitRange` remains `configuration.brightnessRange`.

Update detailed brightness configure call to pass the same 0...100 track range. Do not change CCT configuration.

- [ ] **Step 3: 运行 GREEN source check**

Run:

```bash
rg -n "brightnessTrackRange" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected: PASS, showing the shared fixed brightness track range exists.

- [ ] **Step 4: 静态检查**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 5: iPhoneOS 构建验证**

Run:

```bash
xcodebuild -project SunSmart.xcodeproj -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.
