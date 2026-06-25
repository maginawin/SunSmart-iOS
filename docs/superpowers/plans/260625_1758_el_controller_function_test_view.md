# EL Controller Function Test View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `CID 0x0A78 / PID 0x24C1` 的 EL Controller 设备页中新增 Function Test 与 RX/TX Cable 两个本地 UI 状态循环卡片，并调整 Identify 按钮间距。

**Architecture:** 新增一个独立 UIKit 自定义 View `ELControllerFunctionTestView`，用 `Kind` 区分 Function Test 与 RX/TX Cable，用内部状态数组实现纯本地点击循环。`DeviceLightViewController` 只负责在 EL Controller 专用 UI 分支中创建、布局、显示和隐藏这两个卡片，不新增 mesh/vendor 命令。

**Tech Stack:** Swift、UIKit、SnapKit、Asset Catalog、Localizable.strings、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Create: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
  - Responsibility: 可复用的 EL Controller 本地测试卡片。封装 header、按钮、状态区域、loading spinner 和本地状态循环。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - Responsibility: 在 EL Controller 专用详情 UI 中接入两个卡片，调整 Identify 按钮间距，并在正常/离线/repair 状态下同步显隐。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - Responsibility: 新增英文用户可见文案。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Responsibility: 新增简体中文用户可见文案。
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - Responsibility: 将 `ELControllerFunctionTestView.swift` 加入与 `DeviceLightControlPanelView.swift` 相同的 group 与四个 app target source phase。
- Existing staged assets:
  - `SunSmart/Assets.xcassets/Common/function_test_icon.imageset`
  - `SunSmart/Assets.xcassets/Common/rx_tx_cable_icon.imageset`

## Scope Guard

- 不实现真实 Function Test 或 RX/TX Cable 协议。
- 不发送新增 mesh/vendor command。
- 不改变 `node.isEmergencySignController`、`node.isSupportVendorIdentify`、Relay 读写链路。
- 不改变普通 Light 页面布局。
- 不修改设备发现、设备分类、列表页或组页路由。

### Task 1: Add ELControllerFunctionTestView

**Files:**
- Create: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`

- [ ] **Step 1: Confirm spinner and asset dependencies exist**

Run:

```sh
rg -n "final class PJEightKeySwitchWaitingSpinnerView" SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift
find SunSmart/Assets.xcassets/Common -maxdepth 2 -name 'function_test_icon*' -o -name 'rx_tx_cable_icon*'
```

Expected:

```text
SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchActivationAlertView.swift:10:final class PJEightKeySwitchWaitingSpinnerView: UIView {
SunSmart/Assets.xcassets/Common/rx_tx_cable_icon.imageset
SunSmart/Assets.xcassets/Common/function_test_icon.imageset
```

- [ ] **Step 2: Create the custom view file**

Create `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift` with:

```swift
//
//  ELControllerFunctionTestView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/25.
//

import UIKit

final class ELControllerFunctionTestView: UIView {

    enum Kind {
        case functionTest
        case rxTxCable
    }

    private enum DisplayStyle {
        case neutral
        case waiting
        case success
        case warning
        case fault
    }

    private struct DisplayRow {
        let titleKey: String
        let style: DisplayStyle
    }

    private struct DisplayState {
        let buttonTitleKey: String
        let buttonAlpha: CGFloat
        let rows: [DisplayRow]
        let showsSpinner: Bool
    }

    private enum Constants {
        static let horizontalInset = SCRXFrom(16)
        static let headerTop = SCRYFrom(16)
        static let headerBottom = SCRYFrom(12)
        static let stateBottom = SCRYFrom(16)
        static let iconSize = SCRYFrom(16)
        static let tagHeight = SCRYFrom(20)
        static let buttonHeight = SCRYFrom(28)
        static let buttonMinWidth = SCRXFrom(56)
        static let buttonHorizontalPadding = SCRXFrom(18)
        static let singleStateHeight = SCRYFrom(52)
        static let faultStateHeight = SCRYFrom(40)
        static let rowSpacing = SCRYFrom(6)
        static let stateCornerRadius = SCRYFrom(14)
        static let cardCornerRadius = SCRYFrom(16)
        static let spinnerSize = SCRYFrom(24)
    }

    private let kind: Kind
    private var stateIndex = 0
    private let headerView = UIView()
    private let titleContainerView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let tagLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stateStackView = UIStackView()

    private var states: [DisplayState] {
        switch kind {
        case .functionTest:
            return [
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_function_test_start_prompt", style: .neutral)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "testing…",
                    buttonAlpha: 0.6,
                    rows: [.init(titleKey: "el_controller_function_test_awaiting", style: .waiting)],
                    showsSpinner: true
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_function_test_passed", style: .success)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_function_test_lamp_fault", style: .warning)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_function_test_battery_fault", style: .fault)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_function_test_circuit_fault", style: .fault)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [
                        .init(titleKey: "el_controller_function_test_lamp_fault", style: .warning),
                        .init(titleKey: "el_controller_function_test_battery_fault", style: .fault)
                    ],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [
                        .init(titleKey: "el_controller_function_test_lamp_fault", style: .warning),
                        .init(titleKey: "el_controller_function_test_circuit_fault", style: .fault)
                    ],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [
                        .init(titleKey: "el_controller_function_test_battery_fault", style: .fault),
                        .init(titleKey: "el_controller_function_test_circuit_fault", style: .fault)
                    ],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "Start",
                    buttonAlpha: 1,
                    rows: [
                        .init(titleKey: "el_controller_function_test_lamp_fault", style: .warning),
                        .init(titleKey: "el_controller_function_test_battery_fault", style: .fault),
                        .init(titleKey: "el_controller_function_test_circuit_fault", style: .fault)
                    ],
                    showsSpinner: false
                )
            ]
        case .rxTxCable:
            return [
                .init(
                    buttonTitleKey: "check",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_rxtx_start_prompt", style: .neutral)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "el_controller_rxtx_checking_button",
                    buttonAlpha: 0.6,
                    rows: [.init(titleKey: "el_controller_rxtx_checking_connection", style: .waiting)],
                    showsSpinner: true
                ),
                .init(
                    buttonTitleKey: "check",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_rxtx_connection_normal", style: .success)],
                    showsSpinner: false
                ),
                .init(
                    buttonTitleKey: "check",
                    buttonAlpha: 1,
                    rows: [.init(titleKey: "el_controller_rxtx_connection_fault", style: .fault)],
                    showsSpinner: false
                )
            ]
        }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        setupUI()
        applyCurrentState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShadowPath()
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = Constants.cardCornerRadius
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4

        setupHeader()
        setupStateStackView()
    }

    private func setupHeader() {
        addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
        }

        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .regular)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.backgroundColor = RGB(102, 103, 171)
        actionButton.layer.cornerRadius = Constants.buttonHeight * 0.5
        actionButton.contentEdgeInsets = UIEdgeInsets(
            top: 0,
            left: Constants.buttonHorizontalPadding * 0.5,
            bottom: 0,
            right: Constants.buttonHorizontalPadding * 0.5
        )
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        headerView.addSubview(actionButton)
        actionButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-Constants.horizontalInset)
            make.centerY.equalToSuperview().offset((Constants.headerTop - Constants.headerBottom) * 0.5)
            make.height.equalTo(Constants.buttonHeight)
            make.width.greaterThanOrEqualTo(Constants.buttonMinWidth)
        }

        headerView.addSubview(titleContainerView)
        titleContainerView.snp.makeConstraints { make in
            make.left.equalTo(Constants.horizontalInset)
            make.top.equalTo(Constants.headerTop)
            make.bottom.equalToSuperview().offset(-Constants.headerBottom)
            make.right.lessThanOrEqualTo(actionButton.snp.left).offset(SCRXFrom(-12))
        }

        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage(named: iconImageName)
        titleContainerView.addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
            make.width.height.equalTo(Constants.iconSize)
        }

        titleLabel.text = titleKey.localizedString
        titleLabel.textColor = RGB(30, 35, 41)
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .regular)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleContainerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }

        tagLabel.text = "el_controller_function_test_tag".localizedString
        tagLabel.textColor = RGB(102, 103, 171)
        tagLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .regular)
        tagLabel.textAlignment = .center
        tagLabel.backgroundColor = RGB(102, 103, 171, 0.12)
        tagLabel.layer.cornerRadius = Constants.tagHeight * 0.5
        tagLabel.clipsToBounds = true
        if kind == .functionTest {
            titleContainerView.addSubview(tagLabel)
            tagLabel.snp.makeConstraints { make in
                make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(8))
                make.centerY.equalToSuperview()
                make.height.equalTo(Constants.tagHeight)
                make.width.equalTo(SCRXFrom(28))
                make.right.equalToSuperview()
            }
        } else {
            titleLabel.snp.makeConstraints { make in
                make.right.equalToSuperview()
            }
        }
    }

    private func setupStateStackView() {
        stateStackView.axis = .vertical
        stateStackView.spacing = Constants.rowSpacing
        addSubview(stateStackView)
        stateStackView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.left.equalTo(Constants.horizontalInset)
            make.right.equalToSuperview().offset(-Constants.horizontalInset)
            make.bottom.equalToSuperview().offset(-Constants.stateBottom)
        }
    }

    private var iconImageName: String {
        switch kind {
        case .functionTest:
            return "function_test_icon"
        case .rxTxCable:
            return "rx_tx_cable_icon"
        }
    }

    private var titleKey: String {
        switch kind {
        case .functionTest:
            return "el_controller_function_test_title"
        case .rxTxCable:
            return "el_controller_rxtx_title"
        }
    }

    @objc private func actionButtonTapped() {
        stateIndex = (stateIndex + 1) % states.count
        applyCurrentState()
    }

    private func applyCurrentState() {
        let state = states[stateIndex]
        actionButton.setTitle(state.buttonTitleKey.localizedString, for: .normal)
        actionButton.alpha = state.buttonAlpha
        rebuildRows(state.rows, showsSpinner: state.showsSpinner)
        setNeedsLayout()
    }

    private func rebuildRows(_ rows: [DisplayRow], showsSpinner: Bool) {
        stateStackView.arrangedSubviews.forEach { view in
            stateStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        rows.enumerated().forEach { index, row in
            let isSingleRow = rows.count == 1
            let rowView = makeRowView(row, showsSpinner: showsSpinner && index == 0, isSingleRow: isSingleRow)
            stateStackView.addArrangedSubview(rowView)
            rowView.snp.makeConstraints { make in
                make.height.equalTo(isSingleRow ? Constants.singleStateHeight : Constants.faultStateHeight)
            }
        }
    }

    private func makeRowView(_ row: DisplayRow, showsSpinner: Bool, isSingleRow: Bool) -> UIView {
        let rowView = UIView()
        rowView.backgroundColor = backgroundColor(for: row.style)
        rowView.layer.cornerRadius = Constants.stateCornerRadius
        rowView.clipsToBounds = true

        let contentStack = UIStackView()
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = SCRXFrom(8)
        rowView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview().offset(SCRXFrom(16))
            make.right.lessThanOrEqualToSuperview().offset(SCRXFrom(-16))
        }

        var spinnerView: PJEightKeySwitchWaitingSpinnerView?
        if showsSpinner {
            let spinner = PJEightKeySwitchWaitingSpinnerView()
            contentStack.addArrangedSubview(spinner)
            spinner.snp.makeConstraints { make in
                make.width.height.equalTo(Constants.spinnerSize)
            }
            spinner.startAnimating()
            spinnerView = spinner
        }

        let label = UILabel()
        label.text = row.titleKey.localizedString
        label.textColor = textColor(for: row.style)
        label.font = UIFont.systemFont(ofSize: SCRYFrom(isSingleRow && row.style != .neutral && row.style != .waiting ? 14 : 12), weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 1
        contentStack.addArrangedSubview(label)

        spinnerView?.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return rowView
    }

    private func backgroundColor(for style: DisplayStyle) -> UIColor {
        switch style {
        case .neutral:
            return RGB(239, 239, 244)
        case .waiting:
            return RGB(102, 103, 171, 0.08)
        case .success:
            return RGB(52, 199, 89, 0.10)
        case .warning:
            return RGB(255, 149, 0, 0.10)
        case .fault:
            return RGB(255, 59, 48, 0.10)
        }
    }

    private func textColor(for style: DisplayStyle) -> UIColor {
        switch style {
        case .neutral:
            return RGB(148, 163, 184)
        case .waiting:
            return RGB(102, 103, 171)
        case .success:
            return RGB(0, 209, 124)
        case .warning:
            return RGB(255, 149, 0)
        case .fault:
            return RGB(255, 72, 49)
        }
    }

    private func updateShadowPath() {
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Constants.cardCornerRadius).cgPath
    }
}
```

- [ ] **Step 3: Verify source file contains both card types**

Run:

```sh
rg -n "enum Kind|functionTest|rxTxCable|PJEightKeySwitchWaitingSpinnerView|function_test_icon|rx_tx_cable_icon" SunSmart/Main/Device/View/ELControllerFunctionTestView.swift
```

Expected: output includes `enum Kind`, `.functionTest`, `.rxTxCable`, `PJEightKeySwitchWaitingSpinnerView`, `function_test_icon`, and `rx_tx_cable_icon`.

### Task 2: Add Localized Strings

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Confirm keys do not already exist**

Run:

```sh
rg -n "el_controller_function_test|el_controller_rxtx" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: no output.

- [ ] **Step 2: Append English strings**

Append to `SunSmart/en.lproj/Localizable.strings`:

```strings
"el_controller_function_test_title" = "Function Test";
"el_controller_function_test_tag" = "FT";
"el_controller_function_test_start_prompt" = "Tap \"Start\" to send command to device";
"el_controller_function_test_awaiting" = "Awaiting device response…";
"el_controller_function_test_passed" = "Test Passed";
"el_controller_function_test_lamp_fault" = "Lamp Fault";
"el_controller_function_test_battery_fault" = "Battery Fault";
"el_controller_function_test_circuit_fault" = "Circuit Fault";
"el_controller_rxtx_title" = "RX/TX Cable";
"el_controller_rxtx_checking_button" = "Checking...";
"el_controller_rxtx_start_prompt" = "Tap \"Check\" to test sign panel connection";
"el_controller_rxtx_checking_connection" = "Checking sign panel connection...";
"el_controller_rxtx_connection_normal" = "Connection Normal";
"el_controller_rxtx_connection_fault" = "Connection Fault";
```

- [ ] **Step 3: Append Simplified Chinese strings**

Append to `SunSmart/zh-Hans.lproj/Localizable.strings`:

```strings
"el_controller_function_test_title" = "功能测试";
"el_controller_function_test_tag" = "FT";
"el_controller_function_test_start_prompt" = "点击“开始”向设备发送命令";
"el_controller_function_test_awaiting" = "等待设备响应…";
"el_controller_function_test_passed" = "测试通过";
"el_controller_function_test_lamp_fault" = "灯具故障";
"el_controller_function_test_battery_fault" = "电池故障";
"el_controller_function_test_circuit_fault" = "回路故障";
"el_controller_rxtx_title" = "RX/TX 线缆";
"el_controller_rxtx_checking_button" = "检查中...";
"el_controller_rxtx_start_prompt" = "点击“检查”测试标志面板连接";
"el_controller_rxtx_checking_connection" = "正在检查标志面板连接...";
"el_controller_rxtx_connection_normal" = "连接正常";
"el_controller_rxtx_connection_fault" = "连接故障";
```

- [ ] **Step 4: Verify all localization keys are paired**

Run:

```sh
rg -n "el_controller_function_test|el_controller_rxtx" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 14 keys in English and the same 14 keys in Simplified Chinese.

### Task 3: Wire Cards Into DeviceLightViewController

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Add card properties**

In `DeviceLightViewController`, near `private var emergencySignIdentifyButton: UIButton?`, add:

```swift
    private var elFunctionTestView: ELControllerFunctionTestView?
    private var elRxTxCableView: ELControllerFunctionTestView?
```

- [ ] **Step 2: Add exact product guard**

In `DeviceLightViewController`, near `let node: Node`, add:

```swift
    private var supportsELControllerLocalFunctionViews: Bool {
        node.companyIdentifier == 0x0A78 && node.productIdentifier == 0x24C1
    }
```

- [ ] **Step 3: Replace Identify layout and add cards**

In `setupEmergencySignUI()`, replace the `identifyButton.snp.makeConstraints` block and the following assignment with:

```swift
        identifyButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(30))
            make.width.height.equalTo(isIPad ? 56 : 40)
        }
        emergencySignIdentifyButton = identifyButton

        if supportsELControllerLocalFunctionViews {
            let functionTestView = ELControllerFunctionTestView(kind: .functionTest)
            contentView.addSubview(functionTestView)
            functionTestView.snp.makeConstraints { make in
                make.top.equalTo(identifyButton.snp.bottom).offset(SCRYFit(30))
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            elFunctionTestView = functionTestView

            let rxTxCableView = ELControllerFunctionTestView(kind: .rxTxCable)
            contentView.addSubview(rxTxCableView)
            rxTxCableView.snp.makeConstraints { make in
                make.top.equalTo(functionTestView.snp.bottom).offset(SCRYFit(16))
                make.left.right.equalTo(functionTestView)
                make.bottom.lessThanOrEqualToSuperview().offset(SCRYFit(-8))
            }
            elRxTxCableView = rxTxCableView
        } else {
            identifyButton.snp.makeConstraints { make in
                make.bottom.lessThanOrEqualToSuperview().offset(SCRYFit(-8))
            }
        }
```

- [ ] **Step 4: Add helper for card visibility**

In `DeviceLightViewController`, near `updateEmergencySignData()`, add:

```swift
    private func setELControllerFunctionViewsHidden(_ hidden: Bool) {
        elFunctionTestView?.isHidden = hidden
        elRxTxCableView?.isHidden = hidden
    }
```

- [ ] **Step 5: Hide cards in non-normal states and show in normal state**

In `updateEmergencySignData()`:

1. After `emergencySignIdentifyButton?.isHidden = true` in the offline branch, add:

```swift
                setELControllerFunctionViewsHidden(true)
```

2. After `emergencySignIdentifyButton?.isHidden = false` in the online branch, add:

```swift
            setELControllerFunctionViewsHidden(false)
```

3. After `emergencySignIdentifyButton?.isHidden = true` in the repair branch, add:

```swift
            setELControllerFunctionViewsHidden(true)
```

- [ ] **Step 6: Verify no ordinary Light path references the new cards**

Run:

```sh
rg -n "ELControllerFunctionTestView|supportsELControllerLocalFunctionViews|setELControllerFunctionViewsHidden" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected:

```text
private var elFunctionTestView: ELControllerFunctionTestView?
private var elRxTxCableView: ELControllerFunctionTestView?
private var supportsELControllerLocalFunctionViews: Bool
let functionTestView = ELControllerFunctionTestView(kind: .functionTest)
let rxTxCableView = ELControllerFunctionTestView(kind: .rxTxCable)
private func setELControllerFunctionViewsHidden(_ hidden: Bool)
```

### Task 4: Add New Swift File To Xcode Project

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Confirm planned UUIDs are unused**

Run:

```sh
rg -n "C8F700002FAF00000000000[1-5]|ELControllerFunctionTestView.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected: no output.

- [ ] **Step 2: Add PBXBuildFile entries**

In `SunSmart.xcodeproj/project.pbxproj`, inside the `PBXBuildFile` section, add:

```pbxproj
		C8F700002FAF000000000002 /* ELControllerFunctionTestView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */; };
		C8F700002FAF000000000003 /* ELControllerFunctionTestView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */; };
		C8F700002FAF000000000004 /* ELControllerFunctionTestView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */; };
		C8F700002FAF000000000005 /* ELControllerFunctionTestView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */; };
```

- [ ] **Step 3: Add PBXFileReference entry**

In the `PBXFileReference` section, near `DeviceLightControlPanelView.swift`, add:

```pbxproj
		C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ELControllerFunctionTestView.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: Add file to Device/View group**

In group `C898EA6D2AC2D59C0023B480 /* View */`, add after `DeviceUpDownRatioControlView.swift`:

```pbxproj
				C8F700002FAF000000000001 /* ELControllerFunctionTestView.swift */,
```

- [ ] **Step 5: Add file to four Sources build phases**

Add the four build file IDs near the existing `DeviceLightControlPanelView.swift in Sources` / `DeviceUpDownRatioControlView.swift in Sources` entries:

```pbxproj
				C8F700002FAF000000000002 /* ELControllerFunctionTestView.swift in Sources */,
				C8F700002FAF000000000003 /* ELControllerFunctionTestView.swift in Sources */,
				C8F700002FAF000000000004 /* ELControllerFunctionTestView.swift in Sources */,
				C8F700002FAF000000000005 /* ELControllerFunctionTestView.swift in Sources */,
```

Each ID must appear in exactly one source phase. The four source phases are the same four phases that contain:

```text
C8D1C0012F10000000000001 /* DeviceLightControlPanelView.swift in Sources */
C8D1C0022F10000000000001 /* DeviceLightControlPanelView.swift in Sources */
C8D1C0032F10000000000001 /* DeviceLightControlPanelView.swift in Sources */
C8D1C0042F10000000000001 /* DeviceLightControlPanelView.swift in Sources */
```

- [ ] **Step 6: Verify project references**

Run:

```sh
rg -n "ELControllerFunctionTestView.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected: 10 lines:

- 4 `PBXBuildFile` lines
- 1 `PBXFileReference` line
- 1 group child line
- 4 source phase lines

### Task 5: Verify Assets, Formatting, And Build

**Files:**
- Existing staged assets:
  - `SunSmart/Assets.xcassets/Common/function_test_icon.imageset`
  - `SunSmart/Assets.xcassets/Common/rx_tx_cable_icon.imageset`
- All modified files from Tasks 1-4

- [ ] **Step 1: Verify resources are present**

Run:

```sh
find SunSmart/Assets.xcassets/Common/function_test_icon.imageset SunSmart/Assets.xcassets/Common/rx_tx_cable_icon.imageset -maxdepth 1 -type f | sort
```

Expected: `Contents.json`, `png`, `@2x.png`, and `@3x.png` files for both image sets.

- [ ] **Step 2: Run diff whitespace check**

Run:

```sh
git diff --check
```

Expected: no output.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Inspect final diff scope**

Run:

```sh
git status --short
git diff --stat
```

Expected modified or added files:

```text
SunSmart/Main/Device/View/ELControllerFunctionTestView.swift
SunSmart/Main/Device/Controller/DeviceLightViewController.swift
SunSmart/en.lproj/Localizable.strings
SunSmart/zh-Hans.lproj/Localizable.strings
SunSmart.xcodeproj/project.pbxproj
SunSmart/Assets.xcassets/Common/function_test_icon.imageset/...
SunSmart/Assets.xcassets/Common/rx_tx_cable_icon.imageset/...
```

- [ ] **Step 5: Commit implementation**

Run:

```sh
git add SunSmart/Main/Device/View/ELControllerFunctionTestView.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/function_test_icon.imageset SunSmart/Assets.xcassets/Common/rx_tx_cable_icon.imageset
git commit -m "feat: add EL Controller function test cards"
```

Expected: commit succeeds and includes only the implementation files and required icon assets.
