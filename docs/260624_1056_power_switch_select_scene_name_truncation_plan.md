# Power Switch Select Scene Name Truncation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 AC/Battery Power Switch 的 Select Scene 页面中超长 Scene name 覆盖右侧选择按钮的问题。

**Architecture:** 仅在 `SwitchSelectSceneViewController` 的 cell 配置处补齐局部布局约束，不修改 `CustomTableViewCell` 通用实现。保留现有 Scene 选择、取消选择、editable tint、callback 和页面复用逻辑。

**Tech Stack:** Swift, UIKit, SnapKit, UITableView, SunSmart iOS workspace.

---

## File Structure

- Modify: `SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift`
  - 责任：Select Scene 页面 table cell 配置。只在 `tableView(_:cellForRowAt:)` 中限制 scene name label 的最大宽度和尾部截断。
- Do not modify: `SunSmart/Common/View/CustomTableViewCell.swift`
  - 原因：该通用 cell 被多处页面复用，本次需求只修 Select Scene 页。
- Reference only: `docs/260624_1052_power_switch_select_scene_name_truncation_design.md`
  - 责任：已确认的设计与验收标准。

## Task 1: Confirm Current Layout Baseline

**Files:**
- Inspect: `SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift`
- Inspect: `SunSmart/Common/View/CustomTableViewCell.swift`

- [ ] **Step 1: Re-read Select Scene cell configuration**

Run:

```bash
nl -ba SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift | sed -n '138,168p'
```

Expected: output shows `cell.cellStyle = .icon`, `cell.titleLabel.text = scene.name`, `cell.iconImageView.image = selectImage`, and `cell.iconX = tableView.width - 30 - SCRXFrom(8)`.

- [ ] **Step 2: Re-read CustomTableViewCell iconX behavior**

Run:

```bash
nl -ba SunSmart/Common/View/CustomTableViewCell.swift | sed -n '132,142p'
```

Expected: output shows `iconX` updates `iconImageView` left and remakes `titleLabel` constraints with only left and centerY.

- [ ] **Step 3: Confirm no unrelated workspace changes**

Run:

```bash
git status --short
```

Expected: empty output before source edits.

## Task 2: Apply Local Select Scene Label Constraint

**Files:**
- Modify: `SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift`

- [ ] **Step 1: Update the cell configuration**

In `tableView(_:cellForRowAt:)`, after setting `cell.iconX`, add local label behavior and constraints so the final cell code contains this sequence:

```swift
        cell.iconX = tableView.width - 30 - SCRXFrom(8)
        cell.titleLabel.numberOfLines = 1
        cell.titleLabel.lineBreakMode = .byTruncatingTail
        cell.titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.iconImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        cell.titleLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(cell.iconImageView.snp.left).offset(-SCRXFrom(8))
        }
```

Keep these existing lines unchanged:

```swift
        cell.cellStyle = .icon
        cell.titleLabel.text = scene.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        let isSelect = sceneData.scene == scene
        let selectImage = UIImage(named: isSelect ? "schedule_target_select" : "schedule_target_select_un")
        if self.editable {
            cell.iconImageView.image = selectImage
        }else {
            cell.iconImageView.image = selectImage?.withTintColor(RGB(216, 216, 216))
        }
        cell.arrowImageView.isHidden = true
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.selectionStyle = .none
```

- [ ] **Step 2: Confirm the source diff is focused**

Run:

```bash
git diff -- SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift
```

Expected: diff only changes `SwitchSelectSceneViewController.swift`, and only the cell layout configuration around `cell.iconX`.

## Task 3: Static Verification

**Files:**
- Verify: `SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift`
- Verify: `SunSmart/Common/View/CustomTableViewCell.swift`

- [ ] **Step 1: Confirm truncation and 8pt spacing are present**

Run:

```bash
rg -n "byTruncatingTail|lessThanOrEqualTo\\(cell\\.iconImageView\\.snp\\.left\\).*SCRXFrom\\(8\\)|setContentCompressionResistancePriority" SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift
```

Expected: output includes the new truncation, trailing, and compression resistance lines in `SwitchSelectSceneViewController.swift`.

- [ ] **Step 2: Confirm CustomTableViewCell was not modified**

Run:

```bash
git diff -- SunSmart/Common/View/CustomTableViewCell.swift
```

Expected: empty output.

- [ ] **Step 3: Check whitespace**

Run:

```bash
git diff --check
```

Expected: empty output.

## Task 4: iPhoneOS Build Verification

**Files:**
- Build: `SunSmart.xcworkspace`

- [ ] **Step 1: Run the project-preferred iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build completes with `** BUILD SUCCEEDED **`.

- [ ] **Step 2: If build fails, inspect only relevant errors**

Run no alternate shell wrapper. Read the command output directly and only change source if the failure points to the new `SwitchSelectSceneViewController.swift` edit.

Expected: unrelated pre-existing build errors must be reported separately and not fixed as part of this task.

## Task 5: Commit Source Fix

**Files:**
- Commit: `SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift`

- [ ] **Step 1: Review final diff**

Run:

```bash
git diff --stat
git diff -- SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift
```

Expected: only `SwitchSelectSceneViewController.swift` source fix appears.

- [ ] **Step 2: Commit**

Run:

```bash
git add SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift
git commit -m "fix: truncate switch select scene names"
```

Expected: commit succeeds with only the source fix.

## Self-Review

- Spec coverage: Task 2 implements single-line tail truncation and the 8pt right spacing. Task 3 checks the implementation stayed local. Task 4 covers required iPhoneOS build verification.
- Placeholder scan: no unresolved placeholder instructions remain.
- Type consistency: all referenced symbols already exist in the project: `titleLabel`, `iconImageView`, `iconX`, `SCRXFrom`, `byTruncatingTail`, SnapKit `remakeConstraints`.
- Scope check: no localization, resources, target settings, dependencies, or shared `CustomTableViewCell` behavior are changed.
