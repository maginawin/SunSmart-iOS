# Battery Power Switch BLE OTA Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `Firmware Update via BLE` 页面中，仅为 Battery Power Switch 类型设备展开态增加可折叠 OTA 激活提示。

**Architecture:** 将类型判断与提示展开状态放在 `FirmwareUpdateTypeData`，将提示 UI 封装在 `BleFirmwareTypeUpdateViewCell` 内部，避免影响 controller 和其他设备类型。提示视图插入在 `deviceNumberView` 与 `deviceTableView` 之间，通过 SnapKit 高度约束和 collection view layout invalidation 支持折叠/展开自适应。

**Tech Stack:** UIKit、SnapKit、NordicSigMeshSDK、项目现有 `localizedString`、现有 asset catalog 图片 `arrow_fold_down` / `arrow_fold_up`。

---

## File Structure

- Modify: `SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift`
  - 增加 Battery Power Switch 类型判断。
  - 增加提示展开状态，默认 `false`。
- Modify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
  - 新增 Battery Power Switch OTA 提示视图。
  - 将提示视图插入到 `deviceNumberView` 和 `deviceTableView` 中间。
  - 仅 Battery Power Switch 且类型卡片展开时显示。
  - 点击提示视图切换 `arrow_fold_down` / `arrow_fold_up` 与文本行数。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 新增英文提示文案 key。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增同 key，值使用产品要求的英文原文，避免中文翻译改变含义。

## Task 1: Add Data Flags And Localized Text

**Files:**
- Modify: `SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add Battery Power Switch UI state to firmware type data**

In `SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift`, add the state and computed type check inside `class FirmwareUpdateTypeData`, after `var isShow: Bool = false`:

```swift
    /// Battery Power Switch OTA提示是否展开
    var isBatteryPowerSwitchOTAHintExpanded: Bool = false
    
    /// 是否为Battery Power Switch类型
    var isBatteryPowerSwitchType: Bool {
        return nodes.contains(where: { $0.isBatteryPowerSwitch })
    }
```

- [ ] **Step 2: Add localized text key**

Append this key near the existing firmware OTA strings in `SunSmart/en.lproj/Localizable.strings`:

```text
"battery_power_switch_ota_hint" = "Battery-powered devices need to be activated before the upgrade can be performed.Press 'Button 2'and 'Button ON' on the device to wake it up for the update. Then click refresh.The device has a 60s activation time.Activation and upgrade must be completed within this timeframe.";
```

Append the same key and value near the existing firmware OTA strings in `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"battery_power_switch_ota_hint" = "Battery-powered devices need to be activated before the upgrade can be performed.Press 'Button 2'and 'Button ON' on the device to wake it up for the update. Then click refresh.The device has a 60s activation time.Activation and upgrade must be completed within this timeframe.";
```

- [ ] **Step 3: Run focused search checks**

Run:

```bash
rg -n "battery_power_switch_ota_hint|isBatteryPowerSwitchOTAHintExpanded|isBatteryPowerSwitchType" SunSmart/Main/Firmware SunSmart/en.lproj SunSmart/zh-Hans.lproj
```

Expected:

- `FirmwareUpdateTypeData.swift` contains both new properties.
- Both Localizable files contain `battery_power_switch_ota_hint`.

- [ ] **Step 4: Commit Task 1**

```bash
git add SunSmart/Main/Firmware/Model/FirmwareUpdateTypeData.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add battery power switch OTA hint metadata"
```

## Task 2: Build The Hint View In The BLE OTA Cell

**Files:**
- Modify: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`

- [ ] **Step 1: Add view properties**

In `BleFirmwareTypeUpdateViewCell`, add these properties after `private var deviceNumberView: UIView!` and related labels:

```swift
    /// Battery Power Switch OTA提示
    private var batteryPowerSwitchOTAHintContainerView: UIView!
    private var batteryPowerSwitchOTAHintLabel: UILabel!
    private var batteryPowerSwitchOTAHintButton: UIButton!
    private var batteryPowerSwitchOTAHintHeightConstraint: Constraint?
    private var batteryPowerSwitchOTAHintBottomSpacingConstraint: Constraint?
```

Add `Constraint` support by updating the imports:

```swift
import UIKit
import NordicSigMeshSDK
import SnapKit
```

If `Constraint` is already available through project-wide imports and `import SnapKit` is unnecessary for this file, keep the import anyway because this file directly stores a SnapKit `Constraint`.

- [ ] **Step 2: Update reload logic for hint state**

In `func reload()`, compute the hint state before the `if firmwareTypeData.isShow` branch:

```swift
        let showsBatteryPowerSwitchOTAHint = firmwareTypeData.isShow && firmwareTypeData.isBatteryPowerSwitchType
        batteryPowerSwitchOTAHintContainerView.isHidden = !showsBatteryPowerSwitchOTAHint
        batteryPowerSwitchOTAHintLabel.numberOfLines = firmwareTypeData.isBatteryPowerSwitchOTAHintExpanded ? 0 : 1
        batteryPowerSwitchOTAHintButton.setImage(UIImage(named: firmwareTypeData.isBatteryPowerSwitchOTAHintExpanded ? "arrow_fold_up" : "arrow_fold_down"), for: .normal)
        batteryPowerSwitchOTAHintHeightConstraint?.update(offset: showsBatteryPowerSwitchOTAHint ? batteryPowerSwitchOTAHintHeight : 0)
        batteryPowerSwitchOTAHintBottomSpacingConstraint?.update(offset: showsBatteryPowerSwitchOTAHint ? SCRYFrom(8) : 0)
```

Add a private computed height in the class:

```swift
    private var batteryPowerSwitchOTAHintHeight: CGFloat {
        guard firmwareTypeData?.isBatteryPowerSwitchOTAHintExpanded == true else {
            return SCRYFrom(50)
        }
        let availableWidth = contentView.bounds.width > 0 ? contentView.bounds.width - SCRXFrom(32) - SCRXFrom(40) - SCRXFrom(38) : SCREEN_WIDTH - SCRXFrom(32) - SCRXFrom(40) - SCRXFrom(38)
        let text = "battery_power_switch_ota_hint".localizedString as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = SCRYFrom(20)
        paragraphStyle.maximumLineHeight = SCRYFrom(20)
        let textHeight = text.boundingRect(
            with: CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: UIFont.systemFont(ofSize: FontFit(13), weight: .light),
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        ).height
        return max(SCRYFrom(50), ceil(textHeight) + SCRYFrom(32))
    }
```

- [ ] **Step 3: Insert the hint UI between count and table**

In `setupUI()`, after `upgradedLabel.snp.makeConstraints` and before `deviceTableView = UITableView(...)`, add:

```swift
        batteryPowerSwitchOTAHintContainerView = UIView()
        batteryPowerSwitchOTAHintContainerView.backgroundColor = RGB(255, 243, 227)
        batteryPowerSwitchOTAHintContainerView.layer.cornerRadius = SCRYFrom(15)
        batteryPowerSwitchOTAHintContainerView.layer.masksToBounds = true
        batteryPowerSwitchOTAHintContainerView.isHidden = true
        batteryPowerSwitchOTAHintContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(batteryPowerSwitchOTAHintAction)))
        contentView.addSubview(batteryPowerSwitchOTAHintContainerView)
        batteryPowerSwitchOTAHintContainerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-12))
            make.top.equalTo(deviceNumberView.snp.bottom)
            batteryPowerSwitchOTAHintHeightConstraint = make.height.equalTo(0).constraint
        }
        
        batteryPowerSwitchOTAHintLabel = UILabel(text: "battery_power_switch_ota_hint".localizedString, textColor: RGB(100, 116, 139), fontSize: 13, fontWeight: .light)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = SCRYFrom(20)
        paragraphStyle.maximumLineHeight = SCRYFrom(20)
        batteryPowerSwitchOTAHintLabel.attributedText = NSAttributedString(
            string: "battery_power_switch_ota_hint".localizedString,
            attributes: [
                .font: UIFont.systemFont(ofSize: FontFit(13), weight: .light),
                .foregroundColor: RGB(100, 116, 139),
                .paragraphStyle: paragraphStyle
            ]
        )
        batteryPowerSwitchOTAHintLabel.numberOfLines = 1
        batteryPowerSwitchOTAHintLabel.lineBreakMode = .byTruncatingTail
        batteryPowerSwitchOTAHintContainerView.addSubview(batteryPowerSwitchOTAHintLabel)
        batteryPowerSwitchOTAHintLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-50))
            make.top.equalTo(SCRYFrom(16))
            make.bottom.lessThanOrEqualTo(SCRYFrom(-16))
        }
        
        batteryPowerSwitchOTAHintButton = UIButton(normalImageName: "arrow_fold_down", target: self, action: #selector(batteryPowerSwitchOTAHintAction))
        batteryPowerSwitchOTAHintContainerView.addSubview(batteryPowerSwitchOTAHintButton)
        batteryPowerSwitchOTAHintButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(10))
            make.width.height.equalTo(SCRYFrom(30))
        }
```

Then update the table top constraint from:

```swift
            make.top.equalTo(deviceNumberView.snp.bottom)
```

to:

```swift
            batteryPowerSwitchOTAHintBottomSpacingConstraint = make.top.equalTo(batteryPowerSwitchOTAHintContainerView.snp.bottom).offset(0).constraint
```

- [ ] **Step 4: Add tap handler**

Add this action near the existing `pinchAction()`:

```swift
    /// Battery Power Switch OTA提示展开/收起
    @objc private func batteryPowerSwitchOTAHintAction() {
        guard firmwareTypeData.isBatteryPowerSwitchType, firmwareTypeData.isShow else {
            return
        }
        firmwareTypeData.isBatteryPowerSwitchOTAHintExpanded.toggle()
        reload()
        delegate?.cell(self, didShowDevices: firmwareTypeData.isShow)
    }
```

- [ ] **Step 5: Run focused build check for Swift syntax**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Commit Task 2**

```bash
git add SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
git commit -m "feat: add battery power switch BLE OTA hint view"
```

## Task 3: Tighten Layout Behavior And Regression Checks

**Files:**
- Modify if needed: `SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift`
- Read only: `SunSmart/Main/Firmware/Controller/BleFirmwareUpdateViewController.swift`

- [ ] **Step 1: Verify collection layout invalidation path**

Confirm `BleFirmwareUpdateViewController.cell(_:didShowDevices:)` already invalidates layout:

```swift
            UIView.animate(withDuration: 0.2) {
                self.collectionView.collectionViewLayout.invalidateLayout()
                self.collectionView.layoutIfNeeded()
            }
```

No controller code change is needed if this block is present.

- [ ] **Step 2: Ensure non-Battery Power Switch devices keep zero hint height**

In `reload()`, keep this exact behavior:

```swift
        let showsBatteryPowerSwitchOTAHint = firmwareTypeData.isShow && firmwareTypeData.isBatteryPowerSwitchType
        batteryPowerSwitchOTAHintContainerView.isHidden = !showsBatteryPowerSwitchOTAHint
        batteryPowerSwitchOTAHintHeightConstraint?.update(offset: showsBatteryPowerSwitchOTAHint ? batteryPowerSwitchOTAHintHeight : 0)
        batteryPowerSwitchOTAHintBottomSpacingConstraint?.update(offset: showsBatteryPowerSwitchOTAHint ? SCRYFrom(8) : 0)
```

Expected:

- `isShow == false`: hint hidden and height `0`.
- non-Battery Power Switch: hint hidden and height `0`.
- Battery Power Switch expanded: hint visible and height based on folded/expanded state.

- [ ] **Step 3: Check asset references are present**

Run:

```bash
rg -n "arrow_fold_down|arrow_fold_up" SunSmart/Assets.xcassets SunSmart/Main/Firmware/View/BleFirmwareTypeUpdateViewCell.swift
```

Expected:

- `SunSmart/Assets.xcassets/Common/arrow_fold_down.imageset/Contents.json`
- `SunSmart/Assets.xcassets/Common/arrow_fold_up.imageset/Contents.json`
- `BleFirmwareTypeUpdateViewCell.swift`

- [ ] **Step 4: Check no other firmware type UI files changed**

Run:

```bash
git diff --name-only HEAD
```

Expected changed files after Task 2 commits are limited to files from Task 1 and Task 2 only if the task commits have not been made; after commits, output is empty. Do not modify `MeshFirmwareTypeUpdateViewCell.swift`, `BleFirmwareUpdateViewController.swift`, or asset catalogs for this feature.

## Task 4: Final Verification

**Files:**
- Read only: changed files from Tasks 1-2.

- [ ] **Step 1: Run final build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with no compile errors.

- [ ] **Step 2: Manual UI checklist**

Run the app on a normal development device or simulator only for visual inspection after the required iphoneos build passes. Navigate to `Site - Space - More - Firmware Update via BLE`.

Expected:

- Battery Power Switch card expanded: hint appears above `Select all`.
- Default hint state: one line, tail truncation, right button image `arrow_fold_down`, button size 30x30.
- Expanded hint state: full text wraps, right button image `arrow_fold_up`, button size 30x30.
- Tapping the hint or its button toggles state without changing selected devices.
- Light, sensor, gateway, emergency controller, AC Power Switch, and other non-Battery Power Switch types do not show the hint and retain current spacing.
- iPhone and iPad widths keep the hint inside the card with no clipped text in expanded state.

- [ ] **Step 3: Final status check**

Run:

```bash
git status --short
```

Expected:

- Empty output if all task commits were made.
- If uncommitted files remain, they are only intentional implementation files from this plan.
