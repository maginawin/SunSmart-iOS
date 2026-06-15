# Up Down Light View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` for inline execution unless the user explicitly requests subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `CID 0x0A78 / PID 0x2491` 单灯控制页新增符合 Figma 的 `UpDownLightView` 顶部 OnOff 控件，其他灯类型保持现状。

**Architecture:** 新增一个独立 UIKit `UIControl` 组件封装 Figma 布局、tag、tint 和 off 状态。`DeviceLightViewController` 只负责按设备能力选择旧顶部控件或新控件，并把现有亮度、色温、up/down ratio、OnOff 状态传入组件。Mesh 命令链路保持现有实现。

**Tech Stack:** Swift, UIKit, SnapKit, Xcode project `.pbxproj`, existing SunSmart image assets.

---

## File Structure

- Create: `SunSmart/Main/Device/View/UpDownLightView.swift`
  - 独立顶部控件，负责 Figma 结构、tint、tag、off 样式和点击事件。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 添加 `upDownLightView` 属性。
  - 在 setup 阶段创建并约束新控件。
  - 在 update 阶段按 `node.supportsUpDownRatioControl` 切换旧/新顶部控件。
  - 在亮度、色温、ratio 和回包刷新时同步更新新控件。
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - 把 `UpDownLightView.swift` 加入与 `DeviceUpDownRatioControlView.swift` 相同的 group 和 source build phases。
- Verification only: no product docs beyond this plan and existing design spec.

---

### Task 1: Add `UpDownLightView`

**Files:**
- Create: `SunSmart/Main/Device/View/UpDownLightView.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the Swift view file**

Create `SunSmart/Main/Device/View/UpDownLightView.swift` with this implementation:

```swift
//
//  UpDownLightView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/13.
//

import UIKit
import NordicSigMeshSDK

final class UpDownLightView: UIControl {

    struct Configuration: Equatable {
        let isOn: Bool
        let brightnessPercent: Int
        let temperaturePercent: Int
        let upRatio: Int
        let downRatio: Int
    }

    static var preferredSize: CGSize {
        let height = isIPad ? SCRYFit(238) : SCRYFit(200)
        return CGSize(width: height * 210.0 / 200.0, height: height)
    }

    private let upGrayImageView = UIImageView(image: UIImage(named: "up cct image")?.withTintColor(RGB(216, 216, 216), renderingMode: .alwaysOriginal))
    private let downGrayImageView = UIImageView(image: UIImage(named: "down cct image")?.withTintColor(RGB(216, 216, 216), renderingMode: .alwaysOriginal))
    private let upImageView = UIImageView(image: UIImage(named: "up cct image"))
    private let downImageView = UIImageView(image: UIImage(named: "down cct image"))
    private let separatorImageView = UIImageView(image: UIImage(named: "up down cct separator image"))
    private let upTagView = RatioTagView(iconName: "up cct tag icon")
    private let downTagView = RatioTagView(iconName: "down cct tag icon")

    private var configuration: Configuration?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ configuration: Configuration) {
        if self.configuration == configuration {
            return
        }
        self.configuration = configuration

        let upRatio = max(0, min(100, configuration.upRatio))
        let downRatio = max(0, min(100, configuration.downRatio))
        let brightnessPercent = max(0, min(100, configuration.brightnessPercent))
        let temperaturePercent = max(0, min(100, configuration.temperaturePercent))

        upTagView.valueText = "\(upRatio)%"
        downTagView.valueText = "\(downRatio)%"

        if configuration.isOn && brightnessPercent > 0 {
            let tintColor = Node.getCctMixColor(temperature100: temperaturePercent)
            upImageView.image = UIImage(named: "up cct image")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
            downImageView.image = UIImage(named: "down cct image")?.withTintColor(tintColor, renderingMode: .alwaysOriginal)
            upImageView.alpha = CGFloat(upRatio * brightnessPercent) / 10000.0
            downImageView.alpha = CGFloat(downRatio * brightnessPercent) / 10000.0
            let grayAlpha: CGFloat = (45...55).contains(temperaturePercent) ? 0.5 : 0
            upGrayImageView.alpha = grayAlpha
            downGrayImageView.alpha = grayAlpha
        } else {
            let offColor = RGB(216, 216, 216)
            upImageView.image = UIImage(named: "up cct image")?.withTintColor(offColor, renderingMode: .alwaysOriginal)
            downImageView.image = UIImage(named: "down cct image")?.withTintColor(offColor, renderingMode: .alwaysOriginal)
            upImageView.alpha = 1
            downImageView.alpha = 1
            upGrayImageView.alpha = 0
            downGrayImageView.alpha = 0
        }
    }

    private func setupUI() {
        [upGrayImageView, downGrayImageView, upImageView, downImageView].forEach { imageView in
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            addSubview(imageView)
        }

        separatorImageView.contentMode = .scaleToFill
        separatorImageView.isUserInteractionEnabled = false
        addSubview(separatorImageView)

        [upTagView, downTagView].forEach { tagView in
            tagView.isUserInteractionEnabled = false
            addSubview(tagView)
        }

        let scale = Self.preferredSize.height / 200.0

        upGrayImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(5 * scale)
            make.top.equalToSuperview()
            make.width.equalTo(200 * scale)
            make.height.equalTo(94 * scale)
        }
        upImageView.snp.makeConstraints { make in
            make.edges.equalTo(upGrayImageView)
        }

        downGrayImageView.snp.makeConstraints { make in
            make.left.width.height.equalTo(upGrayImageView)
            make.top.equalToSuperview().offset(106 * scale)
        }
        downImageView.snp.makeConstraints { make in
            make.edges.equalTo(downGrayImageView)
        }

        separatorImageView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalToSuperview().offset(96 * scale)
            make.width.equalTo(210 * scale)
            make.height.equalTo(8 * scale)
        }

        upTagView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(62 * scale)
            make.width.equalTo(64 * scale)
            make.height.equalTo(24 * scale)
        }

        downTagView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(114 * scale)
            make.width.equalTo(64 * scale)
            make.height.equalTo(24 * scale)
        }
    }
}

private final class RatioTagView: UIView {

    var valueText: String {
        get {
            valueLabel.text ?? ""
        }
        set {
            valueLabel.text = newValue
        }
    }

    private let backgroundView = UIView()
    private let iconView: UIImageView
    private let valueLabel = UILabel(text: "50%", textColor: RGB(39, 37, 54), fontSize: 12, fontWeight: .light)

    init(iconName: String) {
        iconView = UIImageView(image: UIImage(named: iconName))
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let scale = UpDownLightView.preferredSize.height / 200.0

        backgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.75)
        backgroundView.layer.cornerRadius = 10 * scale
        backgroundView.clipsToBounds = true
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(10 * scale)
            make.centerY.equalToSuperview()
            make.width.equalTo(6 * scale)
            make.height.equalTo(8 * scale)
        }

        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.8
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(20 * scale)
            make.centerY.equalToSuperview().offset(0.5 * scale)
            make.width.equalTo(36 * scale)
            make.height.equalTo(17 * scale)
        }
    }
}
```

- [ ] **Step 2: Add the file to the Xcode project**

Modify `SunSmart.xcodeproj/project.pbxproj` using the same locations as `DeviceUpDownRatioControlView.swift`:

```text
PBXBuildFile:
C8D1C0212F10000000000001 /* UpDownLightView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0202F10000000000001 /* UpDownLightView.swift */; };
C8D1C0222F10000000000001 /* UpDownLightView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0202F10000000000001 /* UpDownLightView.swift */; };
C8D1C0232F10000000000001 /* UpDownLightView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0202F10000000000001 /* UpDownLightView.swift */; };
C8D1C0242F10000000000001 /* UpDownLightView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0202F10000000000001 /* UpDownLightView.swift */; };

PBXFileReference:
C8D1C0202F10000000000001 /* UpDownLightView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpDownLightView.swift; sourceTree = "<group>"; };
```

Add `C8D1C0202F10000000000001 /* UpDownLightView.swift */` immediately after `DeviceUpDownRatioControlView.swift` in the Device View group.

Add the four build file IDs immediately after the matching `DeviceUpDownRatioControlView.swift in Sources` entries:

```text
C8D1C0212F10000000000001 /* UpDownLightView.swift in Sources */,
C8D1C0222F10000000000001 /* UpDownLightView.swift in Sources */,
C8D1C0232F10000000000001 /* UpDownLightView.swift in Sources */,
C8D1C0242F10000000000001 /* UpDownLightView.swift in Sources */,
```

- [ ] **Step 3: Run project file sanity checks**

Run:

```bash
rg -n "UpDownLightView.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected:

- 1 `PBXFileReference`.
- 4 `PBXBuildFile`.
- 1 group child entry.
- 4 source phase entries.

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Main/Device/View/UpDownLightView.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add up down light view"
```

---

### Task 2: Integrate `UpDownLightView` in the Single Light Control Page

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Add the view property**

Near the existing top light properties:

```swift
private var lightGrayBgView: UIImageView!
private var lightBgView: UIImageView!
private var lightImageBtn: UIButton!
private var upDownLightView: UpDownLightView!
```

- [ ] **Step 2: Change the OnOff action sender type**

Replace:

```swift
@objc private func onoffAction(sender: UIButton) {
```

with:

```swift
@objc private func onoffAction(sender: UIControl) {
```

Existing `UIButton` call sites still compile because `UIButton` subclasses `UIControl`, and the new `UpDownLightView` can reuse the same action.

- [ ] **Step 3: Create and constrain `UpDownLightView`**

After `lightImageBtn` is added in `setupUI()`, insert:

```swift
upDownLightView = UpDownLightView()
upDownLightView.isHidden = true
upDownLightView.addTarget(self, action: #selector(onoffAction), for: .touchUpInside)
contentView.addSubview(upDownLightView)
upDownLightView.snp.makeConstraints { make in
    make.centerX.equalTo(lightBgView)
    make.top.equalTo(lightGrayBgView)
    make.width.equalTo(UpDownLightView.preferredSize.width)
    make.height.equalTo(UpDownLightView.preferredSize.height)
}
```

- [ ] **Step 4: Add a helper to update the top visual state**

Add this helper near `updateControlPanel()`:

```swift
private func updateTopLightView(lightness100: Int, isLightOn: Bool) {
    if node.supportsUpDownRatioControl {
        lightGrayBgView.isHidden = true
        lightBgView.isHidden = true
        lightImageBtn.isHidden = true
        upDownLightView.isHidden = false

        let temperature100 = node.singleDeviceDisplaySupportCct
            ? node.getEffectiveTemperature100(temperature: node.temperature)
            : 50
        upDownLightView.configure(.init(
            isOn: isLightOn,
            brightnessPercent: lightness100,
            temperaturePercent: temperature100,
            upRatio: node.upRatio,
            downRatio: node.downRatio
        ))
        return
    }

    lightGrayBgView.isHidden = false
    lightBgView.isHidden = false
    lightImageBtn.isHidden = false
    upDownLightView.isHidden = true

    if isLightOn {
        lightImageBtn.isSelected = true
        onoffBtn.isSelected = true

        let progress = CGFloat(Float(lightness100) / 100.0) * 0.5
        var alpha = 0.5 + progress
        if node.singleDeviceDisplaySupportCct {
            let temperature100 = node.getEffectiveTemperature100(temperature: node.temperature)
            lightBgView.image = UIImage(named: "device_light_bg")?.withTintColor(Node.getCctMixColor(temperature100: temperature100))

            var garyBgAlpha: CGFloat = 0
            if temperature100 >= 45 && temperature100 <= 55 {
                garyBgAlpha = 0.5
                alpha = 1
            }
            if garyBgAlpha != lightGrayBgView.alpha {
                UIView.animate(withDuration: 0.25) {
                    self.lightGrayBgView.alpha = garyBgAlpha
                }
            }
        } else {
            lightBgView.image = UIImage(named: "device_light_bg")
        }
        lightBgView.alpha = alpha
    } else {
        lightImageBtn.isSelected = false
        onoffBtn.isSelected = false
        lightBgView.image = UIImage(named: "device_light_off_bg")
        lightBgView.alpha = 1
        if lightGrayBgView.alpha != 0 {
            UIView.animate(withDuration: 0.25) {
                self.lightGrayBgView.alpha = 0
            }
        }
    }
}
```

- [ ] **Step 5: Replace duplicated top visual logic in `updateData(...)`**

Replace the current `if isLightOn { ... } else { ... }` block inside `updateData(refreshControlPanel:)` with:

```swift
updateTopLightView(lightness100: lightness100, isLightOn: isLightOn)
```

Keep the following assignments after it:

```swift
brightnessLabel.text = lightnessText
cctLabel.text = "\(node.temperature)K"
upDownRatioView.upValue = node.upRatio
```

- [ ] **Step 6: Update `updateUI()` visibility rules**

After the existing support checks, add:

```swift
let usesUpDownLightView = node.supportsUpDownRatioControl
upDownLightView.isHidden = !usesUpDownLightView
lightGrayBgView.isHidden = usesUpDownLightView
lightBgView.isHidden = usesUpDownLightView
lightImageBtn.isHidden = usesUpDownLightView
```

Do not hide `brightnessView`, `cctView`, `upDownRatioView`, or `controlPanelView` beyond their existing rules.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: use up down light view on target device"
```

---

### Task 3: Refresh the New Top View During Up/Down Ratio Dragging

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Update the ratio callbacks**

Replace the current callbacks:

```swift
upDownRatioView.valueChanging = { [weak self] value in
    self?.node.upRatio = value
}
upDownRatioView.valueChanged = { [weak self] value in
    guard let self = self else { return }
    self.node.upRatio = value
    if let meshUUID = self.node.network?.uuid.uuidString {
        self.node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: self.node.primaryUnicastAddress)
    }
}
```

with:

```swift
upDownRatioView.valueChanging = { [weak self] value in
    guard let self = self else { return }
    self.node.upRatio = value
    self.updateData(refreshControlPanel: false)
}
upDownRatioView.valueChanged = { [weak self] value in
    guard let self = self else { return }
    self.node.upRatio = value
    self.updateData(refreshControlPanel: false)
    if let meshUUID = self.node.network?.uuid.uuidString {
        self.node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: self.node.primaryUnicastAddress)
    }
}
```

This makes the tag text and up/down alpha update while dragging, not only after leaving and re-entering the page.

- [ ] **Step 2: Commit**

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "fix: refresh up down light ratio preview"
```

---

### Task 4: Verify Build and Scope

**Files:**
- Read: `SunSmart/Main/Device/View/UpDownLightView.swift`
- Read: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
- Read: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Run whitespace check**

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Confirm only intended source files changed**

```bash
git diff --name-only HEAD~3...HEAD
```

Expected committed source/doc changes include:

```text
SunSmart/Main/Device/View/UpDownLightView.swift
SunSmart/Main/Device/Controller/DeviceLightViewController.swift
SunSmart.xcodeproj/project.pbxproj
```

Existing staged asset files may still appear in `git status`; they predate this implementation and should not be reverted or mixed into unrelated commits.

- [ ] **Step 3: Run iPhoneOS build**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual behavior checklist**

Use a `CID 0x0A78 / PID 0x2491` device in the single light control page:

- `UpDownLightView` is shown at the old top light position.
- Old center `lightImageBtn` icon is not visible.
- up tag and down tag remain visible when On and Off.
- Off state shows gray light-off style on both up/down images.
- Brightness slider changes up/down image alpha immediately.
- Color temp slider changes up/down image tint immediately.
- Up/down ratio slider changes tag text and relative alpha immediately.
- Tapping the top `UpDownLightView` toggles OnOff.
- A normal tunable white light still uses the old `lightGrayBgView + lightBgView + lightImageBtn` stack.

- [ ] **Step 5: Commit final verification note only if code changed after Task 3**

If Task 4 required any source fixes, commit them:

```bash
git add SunSmart/Main/Device/View/UpDownLightView.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: polish up down light view integration"
```

If no source fixes were needed, do not create an empty commit.

---

## Self-Review

- Spec coverage: Figma size, tag display, no `lightImageBtn`, OnOff tap, tint rules, ratio alpha, off hint/tint style, target PID gating, and ordinary lamp isolation are covered by Tasks 1-4.
- Placeholder scan: no incomplete marker words or unspecified implementation steps.
- Type consistency: `UpDownLightView.Configuration`, `preferredSize`, and `updateTopLightView(lightness100:isLightOn:)` are defined before use.
- Scope: no Auth, dependency, localization, or target setting changes beyond adding one Swift source file to the same existing targets as neighboring device view files.
