# Power Switch Monitor Enable Readonly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 禁止 AC Power Switch 和 Battery Power Switch 监控页底部 Settings 行的 Switch Enable `UISwitch` 点击生效，同时保留正常 `UISwitch` 视觉样式和后续重新启用该功能的业务代码。

**Architecture:** 改动集中在 `PJEightKeySwitchMonitorStatusSetView`。通过透明 `UIControl` 覆盖底部 `enableSwitch` 消费触摸事件，保持 `enableSwitch.isEnabled = true` 用于维持视觉样式；不删除控制器里的 Tx Enable 更新流程。

**Tech Stack:** Swift, UIKit, SnapKit, Xcode iPhoneOS build.

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
  - 负责底部 Settings 面板 UI。
  - 新增透明触摸拦截层。
  - 保持 `UISwitch` 只展示状态，不响应用户点击。
- Verify only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`
  - 保留 `startTxEnableUpdate(_:)`、Battery / AC Tx Enable 和未链接虚拟开关本地更新流程。

### Task 1: Add Readonly Touch Shield

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`

- [ ] **Step 1: Confirm current event path**

Run:

```sh
rg -n "enableSwitch|enableValueChanged|enableChanged|startTxEnableUpdate" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected:

- `PJEightKeySwitchMonitorStatusSetView.swift` contains `enableSwitch`, `enableValueChanged(_:)`, and `enableChanged`.
- `PJEightKeySwitchMonitorVC.swift` binds `bottomView.enableChanged` to `startTxEnableUpdate(_:)`.

- [ ] **Step 2: Add a transparent UIControl property**

In `PJEightKeySwitchMonitorStatusSetView`, after the existing `enableSwitch` declaration:

```swift
let enableSwitch = UISwitch()
private let enableSwitchTouchShield = UIControl()
```

- [ ] **Step 3: Keep UISwitch visually enabled during configure**

Replace the current `configure(state:)` switch section:

```swift
enableSwitch.setOn(state.isEnabled, animated: false)
enableSwitch.isEnabled = !state.isPending
```

with:

```swift
enableSwitch.setOn(state.isEnabled, animated: false)
enableSwitch.isEnabled = true
enableSwitchTouchShield.isHidden = false
```

This preserves normal on/off visuals and keeps the shield active during both pending and non-pending states.

- [ ] **Step 4: Add the shield above enableSwitch**

After the existing `enableSwitch.snp.makeConstraints` block, add:

```swift
enableSwitchTouchShield.backgroundColor = .clear
contentView.addSubview(enableSwitchTouchShield)
enableSwitchTouchShield.snp.makeConstraints { make in
    make.edges.equalTo(enableSwitch)
}
```

The shield must be added after `enableSwitch` so it sits above the switch and consumes touches.

- [ ] **Step 5: Confirm the business path remains in place**

Run:

```sh
rg -n "enableValueChanged|enableChanged|startTxEnableUpdate|sendACTxEnable|updateUnlinkedVirtualEnable" SunSmart/Main/Device/Device1.5/NEightKeySwitches
```

Expected:

- `enableValueChanged(_:)` still exists.
- `bottomView.enableChanged` binding still exists.
- `startTxEnableUpdate(_:)`, `sendACTxEnable(_:)`, and `updateUnlinkedVirtualEnable(_:)` still exist.

### Task 2: Static Verification and Build

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift`

- [ ] **Step 1: Inspect the final diff**

Run:

```sh
git diff -- SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
```

Expected:

- Only `PJEightKeySwitchMonitorStatusSetView.swift` changes.
- The diff adds `enableSwitchTouchShield`.
- The diff keeps `enableSwitch.isEnabled = true`.
- The diff does not remove `enableSwitch.addTarget(...)` or `enableValueChanged(_:)`.

- [ ] **Step 2: Run whitespace validation**

Run:

```sh
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit implementation**

Run:

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchMonitorStatusSetView.swift
git commit -m "fix: make power switch monitor enable readonly"
```

Expected:

- Commit contains only the monitor status view change.
- Design and implementation commits remain separate.
