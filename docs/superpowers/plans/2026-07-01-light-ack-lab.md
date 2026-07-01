# Light ACK Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted Lab switch that displays ACK progress dialogs only for selected Main Lights and Light detail ACK control commands.

**Architecture:** Keep the feature App-side and page-scoped. Add a small `LabSettings` persistence wrapper, a Lab settings page, a focused ACK progress alert/tracker pair, then replace only the confirmed ACK send sites with tracked equivalents when the Lab switch is enabled.

**Tech Stack:** UIKit, SnapKit, UserDefaults, NordicSigMeshSDK, existing `CustomTableViewCell`, existing `MeshAPI.sendMessage(... result:)`.

---

## File Map

- Create `SunSmart/Common/Data/LabSettings.swift`
  - Owns persisted Lab flags.
  - Provides default `false` for `displayLightAckDetails`.
- Create `SunSmart/Main/Site/Controller/LabViewController.swift`
  - Displays the Lab table and `Display light ACK details` switch.
- Modify `SunSmart/Main/Site/Controller/UserSettingsViewController.swift`
  - Adds the `Lab` row and pushes `LabViewController`.
- Create `SunSmart/Main/Device/Lights/View/LightAckProgressAlertView.swift`
  - Shows a manually dismissible progress alert and updates message text.
- Create `SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift`
  - Formats command text, presents/updates the alert, and sends tracked ACK messages.
- Modify `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - Tracks only online single-light `GenericOnOffSet`.
- Modify `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - Tracks ACK on/off, brightness ended/manual, CCT ended/quick/manual, and vendor identify.
- Modify `SunSmart/en.lproj/Localizable.strings`
  - Adds Lab and ACK progress strings.
- Modify `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Adds Simplified Chinese translations.
- Modify `SunSmart.xcodeproj/project.pbxproj`
  - Adds new Swift files to the `SunSmart` target.

## Task 1: Lab Setting Persistence

**Files:**
- Create: `SunSmart/Common/Data/LabSettings.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the Lab settings wrapper**

Create `SunSmart/Common/Data/LabSettings.swift`:

```swift
//
//  LabSettings.swift
//  SunSmart
//

import Foundation

enum LabSettings {

    private static let displayLightAckDetailsKey = "lab_display_light_ack_details"

    static var displayLightAckDetails: Bool {
        get {
            UserDefaults.standard.bool(forKey: displayLightAckDetailsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayLightAckDetailsKey)
            UserDefaults.standard.synchronize()
        }
    }
}
```

- [ ] **Step 2: Add the new file to the Xcode project**

Add `LabSettings.swift` to `SunSmart.xcodeproj/project.pbxproj` under the existing `SunSmart/Common/Data` group and include it in the `SunSmart` target sources build phase. Use the surrounding `Common/Data/*.swift` entries as the template for `PBXFileReference`, `PBXBuildFile`, group children, and `PBXSourcesBuildPhase`.

- [ ] **Step 3: Build check for the new file**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds, or any failure is unrelated to `LabSettings.swift`.

- [ ] **Step 4: Commit**

Run:

```bash
git add SunSmart/Common/Data/LabSettings.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add Lab settings persistence"
```

## Task 2: User Settings Lab Entry

**Files:**
- Modify: `SunSmart/Main/Site/Controller/UserSettingsViewController.swift`
- Create: `SunSmart/Main/Site/Controller/LabViewController.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add row modeling to User settings**

In `UserSettingsViewController`, add this private enum inside the class:

```swift
    private enum Row: Int, CaseIterable {
        case name
        case lab
    }
```

Update the table data source:

```swift
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }
```

- [ ] **Step 2: Update User settings cells**

Replace the current `cellForRowAt` body with:

```swift
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .arrow
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.contentLabel.textColor = SubText_Color
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.selectionStyle = .none

        switch Row(rawValue: indexPath.row) {
        case .name:
            cell.titleLabel.text = "name".localizedString
            cell.contentLabel.text = UserData.currentUserName
        case .lab:
            cell.titleLabel.text = "lab".localizedString
            cell.contentLabel.text = nil
        case .none:
            cell.titleLabel.text = nil
            cell.contentLabel.text = nil
        }

        return cell
```

- [ ] **Step 3: Route row selection**

Replace the current `didSelectRowAt` body with:

```swift
        switch Row(rawValue: indexPath.row) {
        case .name:
            SRAlertView(title: "name".localizedString, messageColor: Red_Color, inputText: UserData.currentUserName, inputFieldStyle: .init(borderColor: RGB(220, 220, 220)), actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, closeAlert: false)]) { text, validRange in
                if !validRange && !text.isEmpty {
                    return "text_length_exceeded".localizedString
                }
                return nil
            } inputDoneBack: { [weak self] name in
                self?.updateUserInfoReqeust(userName: name)
            }.show()
        case .lab:
            navigationController?.pushViewController(LabViewController(), animated: true)
        case .none:
            break
        }
```

- [ ] **Step 4: Create the Lab page**

Create `SunSmart/Main/Site/Controller/LabViewController.swift`:

```swift
//
//  LabViewController.swift
//  SunSmart
//

import UIKit

final class LabViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case displayLightAckDetails
    }

    private lazy var tableView: UITableView = {
        let tableV = UITableView()
        tableV.rowHeight = SCRYFrom(44)
        tableV.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableV.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: 0, bottom: 0, right: 0)
        tableV.dataSource = self
        tableV.delegate = self
        tableV.separatorStyle = .none
        tableV.backgroundColor = Background_Color
        return tableV
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "lab".localizedString
        view.backgroundColor = Background_Color

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.bottom.equalToSuperview()
        }
    }
}

extension LabViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.cellStyle = .switch
        cell.titleLabel.text = "display_light_ack_details".localizedString
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        cell.contentLabel.text = nil
        cell.enabledSwitch.isOn = LabSettings.displayLightAckDetails
        cell.switchActionCallback = { enabled in
            LabSettings.displayLightAckDetails = enabled
            cell.enabledSwitch.isOn = enabled
        }
        cell.selectionStyle = .none
        return cell
    }
}
```

- [ ] **Step 5: Add LabViewController to the Xcode project**

Add `LabViewController.swift` to the existing `SunSmart/Main/Site/Controller` group and the `SunSmart` target sources build phase.

- [ ] **Step 6: Build check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds, or any failure is unrelated to `UserSettingsViewController` and `LabViewController`.

- [ ] **Step 7: Commit**

Run:

```bash
git add SunSmart/Main/Site/Controller/UserSettingsViewController.swift SunSmart/Main/Site/Controller/LabViewController.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add Lab page entry"
```

## Task 3: Localization

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Add English strings**

Append near the existing end of `SunSmart/en.lproj/Localizable.strings`:

```text
"lab" = "Lab";
"display_light_ack_details" = "Display light ACK details";
"light_ack_sent_format" = "Sent %@";
"light_ack_command_format" = "Command 0x%06X";
"light_ack_result_ok_format" = "Result %@ OK";
"light_ack_result_failed_format" = "Result %@ Failed";
"light_ack_result_timeout_format" = "Result %@ Timeout";
"light_ack_response_format" = "Response %@";
```

- [ ] **Step 2: Add Simplified Chinese strings**

Append near the existing end of `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"lab" = "Lab";
"display_light_ack_details" = "Display light ACK details";
"light_ack_sent_format" = "已发送 %@";
"light_ack_command_format" = "命令 0x%06X";
"light_ack_result_ok_format" = "结果 %@ 成功";
"light_ack_result_failed_format" = "结果 %@ 失败";
"light_ack_result_timeout_format" = "结果 %@ 超时";
"light_ack_response_format" = "回复 %@";
```

- [ ] **Step 3: Duplicate key check**

Run:

```bash
rg -n '"(lab|display_light_ack_details|light_ack_sent_format|light_ack_command_format|light_ack_result_ok_format|light_ack_result_failed_format|light_ack_result_timeout_format|light_ack_response_format)"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: each key appears once in English and once in Simplified Chinese.

- [ ] **Step 4: Commit**

Run:

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: localize Lab ACK details"
```

## Task 4: ACK Progress Alert and Tracker

**Files:**
- Create: `SunSmart/Main/Device/Lights/View/LightAckProgressAlertView.swift`
- Create: `SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the updateable alert view**

Create `SunSmart/Main/Device/Lights/View/LightAckProgressAlertView.swift`:

```swift
//
//  LightAckProgressAlertView.swift
//  SunSmart
//

import UIKit

final class LightAckProgressAlertView: UIView {

    private static weak var current: LightAckProgressAlertView?

    private let shadeView = UIView()
    private let contentView = UIView()
    private let titleLabel = UILabel(text: nil, textColor: Title_Color, fontSize: 15, fontWeight: .medium, fit: false)
    private let messageLabel = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
    private let closeButton = UIButton(title: "close".localizedString, titleSize: 15, titleWeight: .light, titleColor: Bar_Color)

    static func show(title: String, message: String) -> LightAckProgressAlertView? {
        let window = UIApplication.shared.windows.first { $0.isKeyWindow }
        guard let window = window else { return nil }

        current?.dismiss()

        let alert = LightAckProgressAlertView(frame: window.bounds)
        alert.update(title: title, message: message)
        window.addSubview(alert)
        alert.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        current = alert
        return alert
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
    }

    func dismiss() {
        removeFromSuperview()
    }

    private func setupUI() {
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(8)
        contentView.layer.masksToBounds = true
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(36))
            make.right.equalTo(SCRXFrom(-36))
            make.centerY.equalToSuperview()
            make.height.greaterThanOrEqualTo(SCRYFrom(160))
        }

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.left.equalTo(SCRXFrom(24))
            make.right.equalTo(SCRXFrom(-24))
        }

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .left
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20))
            make.left.right.equalTo(titleLabel)
        }

        let lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(messageLabel.snp.bottom).offset(SCRYFrom(20))
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
        }

        closeButton.addTarget(self, action: #selector(closeButtonAction), for: .touchUpInside)
        contentView.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(lineView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(52))
        }
    }

    @objc private func closeButtonAction() {
        dismiss()
    }
}
```

- [ ] **Step 2: Create the tracker**

Create `SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift`:

```swift
//
//  LightAckProgressTracker.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

struct LightAckCommandContext {
    let title: String
    let opcode: UInt32
}

final class LightAckProgressTracker {

    static let shared = LightAckProgressTracker()

    private var alertView: LightAckProgressAlertView?
    private var activeCommandId = UUID()
    private var activeLines: [String] = []

    private init() {}

    static func deviceName(_ node: Node) -> String {
        if let name = node.name, !name.isEmpty {
            return name
        }
        return String(format: "0x%04X", node.primaryUnicastAddress)
    }

    static func context(deviceName: String, commandDescription: String, opcode: UInt32) -> LightAckCommandContext {
        return LightAckCommandContext(title: "\(deviceName) \(commandDescription)", opcode: opcode)
    }

    func send(message: StaticAcknowledgedMeshMessage, model: Model, context: LightAckCommandContext) {
        let commandId = UUID()
        activeCommandId = commandId
        activeLines = [
            String(format: "light_ack_sent_format".localizedString, context.title),
            String(format: "light_ack_command_format".localizedString, context.opcode)
        ]
        alertView = LightAckProgressAlertView.show(title: context.title, message: activeLines.joined(separator: "\n"))

        MeshAPI.sendMessage(message: message, model: model) { [weak self] response in
            DispatchQueue.main.async {
                self?.finish(commandId: commandId, context: context, response: response)
            }
        }
    }

    private func finish(commandId: UUID, context: LightAckCommandContext, response: StaticMeshResponse?) {
        guard commandId == activeCommandId else { return }

        if let response = response {
            if let vendorStatus = response as? SunricherVendorStatus, !vendorStatus.status.isSuccessful {
                activeLines.append(String(format: "light_ack_result_failed_format".localizedString, context.title))
            } else {
                activeLines.append(String(format: "light_ack_result_ok_format".localizedString, context.title))
            }
            activeLines.append(String(format: "light_ack_response_format".localizedString, String(describing: type(of: response))))
        } else {
            activeLines.append(String(format: "light_ack_result_timeout_format".localizedString, context.title))
        }

        alertView?.update(title: context.title, message: activeLines.joined(separator: "\n"))
    }
}
```

- [ ] **Step 3: Add the new files to the Xcode project**

Add `LightAckProgressAlertView.swift` and `LightAckProgressTracker.swift` to their matching groups and include both in the `SunSmart` target sources build phase.

- [ ] **Step 4: Build check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds, or failures identify concrete type/import issues in the two new files.

- [ ] **Step 5: Commit**

Run:

```bash
git add SunSmart/Main/Device/Lights/View/LightAckProgressAlertView.swift SunSmart/Main/Device/Lights/Model/LightAckProgressTracker.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add light ACK progress tracker"
```

## Task 5: Wire Main Lights Single-Light ACK On/Off

**Files:**
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`

- [ ] **Step 1: Add a tracked send helper**

Add this private method inside `DeviceLightsViewController`:

```swift
    private func sendLightItemOnOffCommand(node: Node) {
        guard LabSettings.displayLightAckDetails else {
            MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
            return
        }

        guard let model = node.onoffModel else { return }

        let deviceName = LightAckProgressTracker.deviceName(node)
        let commandDescription = node.isOn ? "on".localizedString : "off".localizedString
        let context = LightAckProgressTracker.context(
            deviceName: deviceName,
            commandDescription: commandDescription,
            opcode: GenericOnOffSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: GenericOnOffSet(node.isOn),
            model: model,
            context: context
        )
    }
```

- [ ] **Step 2: Replace only the online single-light ACK send**

In `collectionView(_:didSelectItemAt:)`, replace:

```swift
                MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
```

with:

```swift
                sendLightItemOnOffCommand(node: node)
```

Leave the offline branch unchanged:

```swift
                MeshAPI.getNodeOnOffState(address: node.primaryUnicastAddress)
```

- [ ] **Step 3: Build check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds and `GenericOnOffGet` offline path remains untouched.

- [ ] **Step 4: Commit**

Run:

```bash
git add SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift
git commit -m "feat: show light ACK details from Lights list"
```

## Task 6: Wire Light Detail ACK Commands

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Add ACK helper methods**

Add these private methods inside `DeviceLightViewController`:

```swift
    private var lightAckDeviceName: String {
        LightAckProgressTracker.deviceName(node)
    }

    private func sendLightDetailOnOffCommand() {
        guard LabSettings.displayLightAckDetails else {
            MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
            return
        }

        guard let model = node.onoffModel else { return }

        let commandDescription = node.isOn ? "on".localizedString : "off".localizedString
        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: commandDescription,
            opcode: GenericOnOffSet.opCode
        )
        LightAckProgressTracker.shared.send(message: GenericOnOffSet(node.isOn), model: model, context: context)
    }

    private func sendLightDetailBrightnessCommand(percent: Int, lightness: UInt16) {
        guard LabSettings.displayLightAckDetails else {
            MeshAPI.setNodeLightnessState(address: node.primaryUnicastAddress, lightness: lightness, ack: true)
            return
        }

        guard let model = node.lightnessModel else { return }

        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: "\("brightness".localizedString) \(percent)%",
            opcode: LightLightnessSet.opCode
        )
        LightAckProgressTracker.shared.send(message: LightLightnessSet(lightness: lightness), model: model, context: context)
    }

    private func sendLightDetailCCTCommand(temperature: UInt16) {
        guard LabSettings.displayLightAckDetails else {
            MeshAPI.setNodeColorTemperatureState(address: node.primaryUnicastAddress, temperature: temperature, ack: true)
            return
        }

        guard let model = node.temperatureModel else { return }

        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: "\(temperature)K",
            opcode: LightCTLTemperatureSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: LightCTLTemperatureSet(temperature: temperature, deltaUV: 0),
            model: model,
            context: context
        )
    }

    private func sendTrackedVendorIdentifyCommand(model: Model) {
        guard LabSettings.displayLightAckDetails else {
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: model)
            return
        }

        let context = LightAckProgressTracker.context(
            deviceName: lightAckDeviceName,
            commandDescription: "identify".localizedString,
            opcode: SunricherVendorSet.opCode
        )
        LightAckProgressTracker.shared.send(
            message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))),
            model: model,
            context: context
        )
    }
```

- [ ] **Step 2: Wire on/off**

In `onoffAction(sender:)`, replace:

```swift
        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn, ack: true)
```

with:

```swift
        sendLightDetailOnOffCommand()
```

- [ ] **Step 3: Wire brightness slider ended only**

In `bindSliderAction()`, replace the brightness throttle send:

```swift
            MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: ended)
```

with:

```swift
            if ended {
                self.sendLightDetailBrightnessCommand(percent: value, lightness: lightness)
            } else {
                MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: false)
            }
```

- [ ] **Step 4: Wire CCT slider ended only**

In `bindSliderAction()`, replace the CCT throttle send:

```swift
            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: temperature, ack: ended)
```

with:

```swift
            if ended {
                self.sendLightDetailCCTCommand(temperature: temperature)
            } else {
                MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: temperature, ack: false)
            }
```

- [ ] **Step 5: Wire quick CCT and manual input**

In `applyCCTQuickButtonValue(_:)`, replace:

```swift
        MeshAPI.setNodeColorTemperatureState(address: node.primaryUnicastAddress, temperature: UInt16(clampedValue), ack: true)
```

with:

```swift
        sendLightDetailCCTCommand(temperature: UInt16(clampedValue))
```

In `showBrightnessInputAlert()`, replace the ACK brightness send with:

```swift
            self.sendLightDetailBrightnessCommand(
                percent: value,
                lightness: Node.getLightness(lightness100: value)
            )
```

In `showCCTInputAlert()`, replace:

```swift
            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: temperature, ack: true)
```

with:

```swift
            self.sendLightDetailCCTCommand(temperature: temperature)
```

- [ ] **Step 6: Wire vendor identify only**

In `sendIdentifyCommand()`, replace the vendor branch send:

```swift
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: vendorModel)
```

with:

```swift
            sendTrackedVendorIdentifyCommand(model: vendorModel)
```

Leave the non-vendor branch unchanged:

```swift
        MeshAPI.identify(address: node.primaryUnicastAddress)
```

- [ ] **Step 7: Build check**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds. The code still sends unack messages while sliders are moving and sends tracked ACK messages only when `ended == true`.

- [ ] **Step 8: Commit**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: show light ACK details from light page"
```

## Task 7: Final Verification

**Files:**
- Read-only verification across the modified files.

- [ ] **Step 1: Confirm scope with grep**

Run:

```bash
rg -n 'LightAckProgressTracker|LabSettings.displayLightAckDetails|GenericOnOffGet|SetUnacknowledged|AttentionSetUnacknowledged' SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected:

- `LightAckProgressTracker` appears only in Main Lights and Light detail code.
- `GenericOnOffGet` remains in the offline branch.
- `SetUnacknowledged` sends remain for slider movement and other unack paths.
- `AttentionSetUnacknowledged` is not converted into a tracked ACK path.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Build iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Manual QA checklist**

Run the App and verify:

- User settings shows `Name` and `Lab`.
- `Name` editing still works.
- `Lab` opens the Lab page.
- `Display light ACK details` defaults off on a fresh install.
- Toggling the switch persists across leaving and reopening the Lab page.
- With the switch off, Main Lights and Light detail behavior matches the old behavior and no ACK dialog appears.
- With the switch on, online single light item On/Off shows the progress dialog.
- With the switch on, offline light item click does not show the progress dialog.
- With the switch on, Light detail On/Off shows the progress dialog.
- With the switch on, brightness slider movement does not show the dialog until the slider ends.
- With the switch on, brightness manual input shows the dialog.
- With the switch on, CCT slider movement does not show the dialog until the slider ends.
- With the switch on, CCT quick button and manual input show the dialog.
- With the switch on, vendor Identify shows the dialog.
- Non-vendor Identify does not show the dialog because it remains unacknowledged.

- [ ] **Step 5: Final commit if verification required changes**

If verification required source changes after Task 6, commit them:

```bash
git add SunSmart SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: finalize light ACK Lab behavior"
```
