# EMSign Cell Icon Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 EMSign 在线 cell 在 Lights、Group、Group Members 三处使用与离线态一致的图标垂直位置。

**Architecture:** 使用现有 `Node.isEmergencySignController` 分支在 cell 渲染层调整 top 约束。`DevicesViewCell` 覆盖 Lights 与 Group Members；`GroupDeviceViewCell` 负责 Group 详情页的尺寸变体。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift`
  - 通用圆形设备 cell，负责 Lights 和 Group Members 的图标位置。
- Modify: `SunSmart/Main/Group/View/GroupDeviceViewCell.swift`
  - Group 详情页圆形设备 cell，覆盖通用 cell 的图标尺寸和 top 位置。

## Task 1: Align EMSign Icon in Shared Device Cell

**Files:**
- Modify: `SunSmart/Main/Device/View/DevicesViewCell.swift:55-57`

- [ ] **Step 1: Change the online top constraint to branch on EMSign**

Replace:

```swift
iconImageView.snp.updateConstraints { make in
    make.top.equalTo(SCRYFrom(12))
}
```

with:

```swift
iconImageView.snp.updateConstraints { make in
    make.top.equalTo(device.isEmergencySignController ? SCRYFrom(24) : SCRYFrom(12))
}
```

This keeps ordinary online lights at `SCRYFrom(12)` while making online EMSign use the existing offline/repair `SCRYFrom(24)` position.

- [ ] **Step 2: Static check shared cell alignment**

Run:

```bash
nl -ba SunSmart/Main/Device/View/DevicesViewCell.swift | sed -n '53,62p'
```

Expected:
- The online `iconImageView` top constraint uses `device.isEmergencySignController ? SCRYFrom(24) : SCRYFrom(12)`.
- The existing EMSign branch still hides `progressView`.

## Task 2: Align EMSign Icon in Group Detail Cell

**Files:**
- Modify: `SunSmart/Main/Group/View/GroupDeviceViewCell.swift:25-31`

- [ ] **Step 1: Change the Group online top constraint to branch on EMSign**

Replace:

```swift
if device.isKeybindComplete && device.state {
    iconImageView.snp.updateConstraints { make in
        make.top.equalTo(SCRYFrom(10))
    }
}else {
    iconImageView.snp.updateConstraints { make in
        make.top.equalTo(SCRYFrom(17))
    }
}
```

with:

```swift
if device.isKeybindComplete && device.state {
    iconImageView.snp.updateConstraints { make in
        make.top.equalTo(device.isEmergencySignController ? SCRYFrom(17) : SCRYFrom(10))
    }
}else {
    iconImageView.snp.updateConstraints { make in
        make.top.equalTo(SCRYFrom(17))
    }
}
```

This keeps ordinary online group lights at `SCRYFrom(10)` while making online EMSign use the existing group offline/repair `SCRYFrom(17)` position.

- [ ] **Step 2: Static check Group cell alignment**

Run:

```bash
nl -ba SunSmart/Main/Group/View/GroupDeviceViewCell.swift | sed -n '24,32p'
```

Expected:
- The online Group cell top constraint uses `device.isEmergencySignController ? SCRYFrom(17) : SCRYFrom(10)`.
- The offline/repair branch remains `SCRYFrom(17)`.

## Task 3: Verification and Commit

**Files:**
- Verify and commit only.

- [ ] **Step 1: Review focused diff**

Run:

```bash
git diff -- SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Group/View/GroupDeviceViewCell.swift
```

Expected:
- Only the two top-constraint expressions changed.
- No command logic, progress visibility, icon assets, or unrelated formatting changed.

- [ ] **Step 2: Run whitespace diff check**

Run:

```bash
git diff --check
```

Expected:
- Exit code 0 with no output.

- [ ] **Step 3: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:
- `** BUILD SUCCEEDED **`
- Existing project warnings may remain, but no new compile errors.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add SunSmart/Main/Device/View/DevicesViewCell.swift SunSmart/Main/Group/View/GroupDeviceViewCell.swift
git commit -m "fix: align EMSign cell icons"
```

Expected:
- Commit succeeds with only the two implementation files staged.

## Self-Review

- Spec coverage: Task 1 covers Lights and Group Members via `DevicesViewCell`; Task 2 covers Group detail via `GroupDeviceViewCell`; Task 3 covers diff, whitespace, and build verification.
- Placeholder scan: no unresolved placeholder language is present.
- Type consistency: plan uses existing `device.isEmergencySignController`, `iconImageView`, `SCRYFrom`, `DevicesViewCell`, and `GroupDeviceViewCell`.
