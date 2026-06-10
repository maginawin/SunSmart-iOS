# Device Light Content Display Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference is Inline Execution.

**Goal:** Update the single-device light control page to consume Space Content Display settings for CCT quick buttons and Simple/Detailed control style.

**Architecture:** Add a reusable UIKit `DeviceLightControlPanelView` that owns slider layout, Detailed labels/value buttons, and CCT quick buttons without depending on `Node` or `MeshAPI`. `DeviceLightViewController` remains responsible for reading `SpaceData`/`Node`, clamping values, updating device state, presenting input alerts, and sending Mesh commands. The panel is added to all app targets so the later Group implementation can reuse it.

**Tech Stack:** Swift, UIKit, SnapKit, NordicSigMeshSDK, Xcode project `SunSmart.xcodeproj`, workspace `SunSmart.xcworkspace`.

---

## File Map

| File | Responsibility |
|---|---|
| `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift` | New reusable control panel with Simple/Detailed slider layout and CCT quick buttons |
| `SunSmart/Main/Device/Controller/DeviceLightViewController.swift` | Replace direct bottom slider ownership with the panel, add scroll container and input alert handling |
| `SunSmart/en.lproj/Localizable.strings` | Add `color_temp` if absent |
| `SunSmart/zh-Hans.lproj/Localizable.strings` | Add `color_temp` if absent |
| `SunSmart.xcodeproj/project.pbxproj` | Add the new Swift file to the Device View group and all app target Sources phases |

No test target exists in this workspace. Verification is source checks plus iPhoneOS `xcodebuild`.

---

### Task 1: Create Reusable Control Panel

**Files:**
- Create: `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift`

- [ ] **Step 1: Create the new Swift file**

Create `SunSmart/Main/Device/View/DeviceLightControlPanelView.swift` with this content:

```swift
//
//  DeviceLightControlPanelView.swift
//  SunSmart
//
//  Created by SunSmart on 2026/6/11.
//

import UIKit

final class DeviceLightControlPanelView: UIView {

    struct Configuration: Equatable {
        var controlType: SpaceControlType
        var showCCTQuickButtons: Bool
        var showsBrightness: Bool
        var showsCCT: Bool
        var brightnessValue: Int
        var brightnessRange: ClosedRange<Int>
        var cctValue: Int
        var cctRange: ClosedRange<Int>

        var cctQuickButtonValues: [Int] {
            if cctRange.upperBound >= 6500 {
                return [2700, 3000, 3500, 4000, 5000, 6500]
            }
            return [2700, 3000, 3500, 4000, 5000]
        }

        var showsQuickButtons: Bool {
            showCCTQuickButtons && showsCCT
        }
    }

    var brightnessValueChanged: ((Int) -> Void)?
    var brightnessThrottleValueChanged: ((Int, Bool) -> Void)?
    var cctValueChanged: ((Int) -> Void)?
    var cctThrottleValueChanged: ((Int, Bool) -> Void)?
    var editBrightnessRequested: (() -> Void)?
    var editCCTRequested: (() -> Void)?

    private let stackView = UIStackView()
    private let simpleBrightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
    private let simpleCCTSlider = BuoySliderView(frame: .zero, functionType: .cct())
    private let detailedBrightnessView = DetailedControlSliderView(functionType: .level())
    private let detailedCCTView = DetailedControlSliderView(functionType: .cct())
    private let quickButtonsView = CCTQuickButtonsView()

    private var configuration: Configuration?
    private var suppressCallbacks = false

    var currentBrightnessValue: Int {
        configuration?.brightnessValue ?? 0
    }

    var currentCCTValue: Int {
        configuration?.cctValue ?? 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
        suppressCallbacks = true
        configureSliderValues(configuration)
        rebuildArrangedViews(configuration)
        suppressCallbacks = false
    }

    func setBrightnessValue(_ value: Int) {
        guard var configuration else { return }
        let clamped = max(configuration.brightnessRange.lowerBound, min(configuration.brightnessRange.upperBound, value))
        configuration.brightnessValue = clamped
        configure(configuration)
    }

    func setCCTValue(_ value: Int) {
        guard var configuration else { return }
        let clamped = max(configuration.cctRange.lowerBound, min(configuration.cctRange.upperBound, value))
        configuration.cctValue = clamped
        configure(configuration)
    }

    private func setupUI() {
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = SCRYFrom(16)
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        [simpleBrightnessSlider, simpleCCTSlider].forEach { slider in
            slider.slider.interval = 0.3
            slider.snp.makeConstraints { make in
                make.height.equalTo(SCRYFrom(40))
            }
        }

        simpleCCTSlider.slider.step = 10
        detailedCCTView.slider.step = 10
    }

    private func bindActions() {
        simpleBrightnessSlider.valueChangedCallback = { [weak self] value in
            self?.handleBrightnessValueChanged(value)
        }
        simpleBrightnessSlider.valueThrottleChangedCallback = { [weak self] value, ended in
            self?.handleBrightnessThrottleValueChanged(value, ended: ended)
        }
        simpleCCTSlider.valueChangedCallback = { [weak self] value in
            self?.handleCCTValueChanged(value)
        }
        simpleCCTSlider.valueThrottleChangedCallback = { [weak self] value, ended in
            self?.handleCCTThrottleValueChanged(value, ended: ended)
        }

        detailedBrightnessView.valueChanged = { [weak self] value in
            self?.handleBrightnessValueChanged(value)
        }
        detailedBrightnessView.throttleValueChanged = { [weak self] value, ended in
            self?.handleBrightnessThrottleValueChanged(value, ended: ended)
        }
        detailedBrightnessView.editRequested = { [weak self] in
            self?.editBrightnessRequested?()
        }

        detailedCCTView.valueChanged = { [weak self] value in
            self?.handleCCTValueChanged(value)
        }
        detailedCCTView.throttleValueChanged = { [weak self] value, ended in
            self?.handleCCTThrottleValueChanged(value, ended: ended)
        }
        detailedCCTView.editRequested = { [weak self] in
            self?.editCCTRequested?()
        }

        quickButtonsView.valueSelected = { [weak self] value in
            guard let self else { return }
            self.setCCTValue(value)
            self.handleCCTValueChanged(value)
            self.handleCCTThrottleValueChanged(value, ended: true)
        }
    }

    private func configureSliderValues(_ configuration: Configuration) {
        configureBrightnessSlider(simpleBrightnessSlider, configuration: configuration)
        configureBrightnessSlider(detailedBrightnessView.sliderView, configuration: configuration)
        configureCCTSlider(simpleCCTSlider, configuration: configuration)
        configureCCTSlider(detailedCCTView.sliderView, configuration: configuration)

        detailedBrightnessView.configure(
            title: "brightness".localizedString,
            valueText: "\(configuration.brightnessValue)%",
            range: configuration.brightnessRange,
            value: configuration.brightnessValue
        )
        detailedCCTView.configure(
            title: "color_temp".localizedString,
            valueText: "\(configuration.cctValue)K",
            range: configuration.cctRange,
            value: configuration.cctValue
        )
        quickButtonsView.configure(values: configuration.cctQuickButtonValues, selectedValue: configuration.cctValue)
    }

    private func configureBrightnessSlider(_ sliderView: BuoySliderView, configuration: Configuration) {
        sliderView.slider.minimumValue = Float(configuration.brightnessRange.lowerBound)
        sliderView.slider.maximumValue = Float(configuration.brightnessRange.upperBound)
        sliderView.slider.limitRange = configuration.brightnessRange
        sliderView.value = configuration.brightnessValue
    }

    private func configureCCTSlider(_ sliderView: BuoySliderView, configuration: Configuration) {
        sliderView.updateCctRange(UInt16(configuration.cctRange.lowerBound)...UInt16(configuration.cctRange.upperBound))
        sliderView.value = configuration.cctValue
    }

    private func rebuildArrangedViews(_ configuration: Configuration) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch configuration.controlType {
        case .simple:
            if configuration.showsBrightness {
                stackView.addArrangedSubview(simpleBrightnessSlider)
            }
            if configuration.showsCCT {
                stackView.addArrangedSubview(simpleCCTSlider)
            }
        case .detailed:
            if configuration.showsBrightness {
                stackView.addArrangedSubview(detailedBrightnessView)
            }
            if configuration.showsCCT {
                stackView.addArrangedSubview(detailedCCTView)
            }
        }

        if configuration.showsQuickButtons {
            stackView.addArrangedSubview(quickButtonsView)
        }
    }

    private func handleBrightnessValueChanged(_ value: Int) {
        guard !suppressCallbacks else { return }
        updateStoredBrightness(value)
        brightnessValueChanged?(value)
    }

    private func handleBrightnessThrottleValueChanged(_ value: Int, ended: Bool) {
        guard !suppressCallbacks else { return }
        brightnessThrottleValueChanged?(value, ended)
    }

    private func handleCCTValueChanged(_ value: Int) {
        guard !suppressCallbacks else { return }
        updateStoredCCT(value)
        cctValueChanged?(value)
    }

    private func handleCCTThrottleValueChanged(_ value: Int, ended: Bool) {
        guard !suppressCallbacks else { return }
        cctThrottleValueChanged?(value, ended)
    }

    private func updateStoredBrightness(_ value: Int) {
        guard var configuration else { return }
        configuration.brightnessValue = max(configuration.brightnessRange.lowerBound, min(configuration.brightnessRange.upperBound, value))
        self.configuration = configuration
        detailedBrightnessView.updateValueText("\(configuration.brightnessValue)%")
    }

    private func updateStoredCCT(_ value: Int) {
        guard var configuration else { return }
        configuration.cctValue = max(configuration.cctRange.lowerBound, min(configuration.cctRange.upperBound, value))
        self.configuration = configuration
        detailedCCTView.updateValueText("\(configuration.cctValue)K")
        quickButtonsView.configure(values: configuration.cctQuickButtonValues, selectedValue: configuration.cctValue)
    }
}

private final class DetailedControlSliderView: UIView {

    let sliderView: BuoySliderView
    var valueChanged: ((Int) -> Void)?
    var throttleValueChanged: ((Int, Bool) -> Void)?
    var editRequested: (() -> Void)?

    private let titleLabel = UILabel(text: "", textColor: RGB(100, 116, 139), fontSize: 14, fontWeight: .light)
    private let valueButton = UIButton(type: .system)

    var slider: CustomDeviceSlider {
        sliderView.slider
    }

    init(functionType: DeviceSliderFunctionView.FunctionType) {
        sliderView = BuoySliderView(frame: .zero, functionType: functionType)
        super.init(frame: .zero)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, valueText: String, range: ClosedRange<Int>, value: Int) {
        titleLabel.text = title
        updateValueText(valueText)
        sliderView.slider.minimumValue = Float(range.lowerBound)
        sliderView.slider.maximumValue = Float(range.upperBound)
        sliderView.slider.limitRange = range
        sliderView.value = value
    }

    func updateValueText(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: FONTS(SCRYFrom(14)),
            .foregroundColor: RGB(46, 49, 93),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        valueButton.setAttributedTitle(NSAttributedString(string: text, attributes: attributes), for: .normal)
    }

    private func setupUI() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
        }

        valueButton.contentHorizontalAlignment = .right
        valueButton.addTarget(self, action: #selector(valueButtonClick), for: .touchUpInside)
        addSubview(valueButton)
        valueButton.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
        }

        addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }

        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(57))
        }
    }

    private func bindActions() {
        sliderView.valueChangedCallback = { [weak self] value in
            self?.valueChanged?(value)
        }
        sliderView.valueThrottleChangedCallback = { [weak self] value, ended in
            self?.throttleValueChanged?(value, ended)
        }
    }

    @objc private func valueButtonClick() {
        editRequested?()
    }
}

private final class CCTQuickButtonsView: UIView {

    var valueSelected: ((Int) -> Void)?

    private let stackView = UIStackView()
    private var buttons: [UIButton] = []
    private var values: [Int] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(values: [Int], selectedValue: Int) {
        self.values = values
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        values.enumerated().forEach { index, value in
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = FONTS(SCRYFrom(12))
            button.layer.cornerRadius = SCRYFrom(16)
            button.layer.borderWidth = 1
            button.setTitle("\(value)K", for: .normal)
            button.addTarget(self, action: #selector(buttonClick(sender:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
            button.snp.makeConstraints { make in
                make.width.equalTo(SCRXFrom(48))
                make.height.equalTo(SCRYFrom(32))
            }
            buttons.append(button)
        }

        updateSelection(selectedValue)
    }

    private func setupUI() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
        }
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(32))
        }
    }

    private func updateSelection(_ selectedValue: Int) {
        buttons.enumerated().forEach { index, button in
            let isSelected = values[index] == selectedValue
            button.backgroundColor = isSelected ? RGB(102, 103, 171) : .white
            button.layer.borderColor = isSelected ? RGB(102, 103, 171).cgColor : RGB(236, 236, 236).cgColor
            button.setTitleColor(isSelected ? .white : RGB(102, 103, 171), for: .normal)
        }
    }

    @objc private func buttonClick(sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        valueSelected?(values[sender.tag])
    }
}
```

- [ ] **Step 2: Check new file for accidental framework coupling**

Run:

```bash
rg -n "Node|MeshAPI|DeviceLightViewController|GroupViewController" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected: no output.

- [ ] **Step 3: Commit the standalone panel file**

Run:

```bash
git add SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
git commit -m "feat: add light control panel view"
```

Expected: commit succeeds.

---

### Task 2: Add the New Swift File to All App Targets

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Inspect nearby project entries**

Run:

```bash
rg -n "DeviceSliderFunctionView.swift|DeviceLightControlViewCell.swift|DeviceLightViewController.swift|PBXSourcesBuildPhase" SunSmart.xcodeproj/project.pbxproj
```

Expected: output includes file references, Device View group membership, and 4 app target source build phases for `Archipelago`, `SylSmart`, `SunSmart`, and `SLG Sync Plus`.

- [ ] **Step 2: Add `DeviceLightControlPanelView.swift` file reference and build entries**

Edit `SunSmart.xcodeproj/project.pbxproj` by adding:

```text
/* PBXBuildFile section */
C8D1C0012F10000000000001 /* DeviceLightControlPanelView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0002F10000000000001 /* DeviceLightControlPanelView.swift */; };
C8D1C0022F10000000000001 /* DeviceLightControlPanelView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0002F10000000000001 /* DeviceLightControlPanelView.swift */; };
C8D1C0032F10000000000001 /* DeviceLightControlPanelView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0002F10000000000001 /* DeviceLightControlPanelView.swift */; };
C8D1C0042F10000000000001 /* DeviceLightControlPanelView.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8D1C0002F10000000000001 /* DeviceLightControlPanelView.swift */; };

/* PBXFileReference section */
C8D1C0002F10000000000001 /* DeviceLightControlPanelView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeviceLightControlPanelView.swift; sourceTree = "<group>"; };
```

Add `C8D1C0002F10000000000001 /* DeviceLightControlPanelView.swift */,` in the same group that currently contains `DeviceSliderFunctionView.swift` and `DeviceLightControlViewCell.swift`.

Add one build file entry to each app target Sources build phase:

```text
C8D1C0012F10000000000001 /* DeviceLightControlPanelView.swift in Sources */,
C8D1C0022F10000000000001 /* DeviceLightControlPanelView.swift in Sources */,
C8D1C0032F10000000000001 /* DeviceLightControlPanelView.swift in Sources */,
C8D1C0042F10000000000001 /* DeviceLightControlPanelView.swift in Sources */,
```

Use one entry per Sources phase. Do not add it to non-app or nonexistent test targets.

- [ ] **Step 3: Verify project registration**

Run:

```bash
rg -n "DeviceLightControlPanelView.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected: 6 lines:

```text
4 PBXBuildFile entries
1 PBXFileReference entry
1 PBXGroup child entry
```

- [ ] **Step 4: Commit project registration**

Run:

```bash
git add SunSmart.xcodeproj/project.pbxproj
git commit -m "chore: add light control panel to app targets"
```

Expected: commit succeeds.

---

### Task 3: Replace Direct Slider Ownership in DeviceLightViewController

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Replace bottom slider properties with scroll and panel properties**

In `DeviceLightViewController`, replace:

```swift
    private var lightnessSlider: BuoySliderView!
    private var cctSlider: BuoySliderView!
```

with:

```swift
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var controlPanel: DeviceLightControlPanelView!
```

- [ ] **Step 2: Add scroll container at the start of `setupUI()`**

At the beginning of `private func setupUI()`, before creating `lightGrayBgView`, add:

```swift
        scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(view)
            make.height.greaterThanOrEqualTo(view).priority(.low)
        }
```

- [ ] **Step 3: Move existing main content subviews into `contentView`**

Inside `setupUI()`, change these direct additions from `view` to `contentView`:

```swift
        contentView.addSubview(lightGrayBgView)
        contentView.addSubview(lightBgView)
        contentView.addSubview(lightImageBtn)
        contentView.addSubview(brightnessView)
        contentView.addSubview(cctView)
        contentView.addSubview(onoffBtn)
        contentView.addSubview(relaySwitch)
        contentView.addSubview(relayLabel)
```

Keep empty-state overlays on `view`; only the normal light control content moves into `contentView`.

- [ ] **Step 4: Replace `cctSlider` and `lightnessSlider` creation with `controlPanel`**

Remove the current `cctSlider` and `lightnessSlider` creation/constraint blocks in `setupUI()`.

After `onoffBtn` has been created and constrained, add:

```swift
        controlPanel = DeviceLightControlPanelView()
        contentView.addSubview(controlPanel)
        controlPanel.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
            } else {
                make.left.equalTo(SCRXFrom(28))
                make.right.equalTo(SCRXFrom(-28))
            }
            make.top.equalTo(onoffBtn.snp.bottom).offset(SCRYFit(isIPad ? 28 : 36))
            make.bottom.equalToSuperview().offset(SCRYFit(-34) - kSafeAreaBottomHeight)
        }
```

The final ordering in `setupUI()` must be:

1. lamp/status views
2. `onoffBtn`
3. `controlPanel`
4. relay controls

- [ ] **Step 5: Update `onoffBtn` constraints to no longer depend on `lightnessSlider`**

Replace the current `onoffBtn.snp.makeConstraints` block with:

```swift
        onoffBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if isIPad {
                make.width.height.equalTo(56)
                make.top.equalTo(brightnessView.snp.bottom).offset(SCRYFit(94))
            } else {
                make.top.equalTo(brightnessView.snp.bottom).offset(SCRYFit(96))
            }
        }
```

Expected: the power button keeps its Figma vertical position, and the control panel starts below it.

- [ ] **Step 6: Update brightness status constraints to use `contentView`**

In `updateUI()`, when remaking `brightnessView` constraints for CCT devices, replace `view.snp.centerX` with `contentView.snp.centerX`:

```swift
                    make.right.equalTo(contentView.snp.centerX).offset(SCRXFrom(-42))
```

- [ ] **Step 7: Compile-check references**

Run:

```bash
rg -n "lightnessSlider|cctSlider" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: output may still exist before callback migration. Do not commit until Task 4 removes or replaces all direct references.

---

### Task 4: Wire Panel Configuration, Value Updates, and Mesh Commands

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Replace `updateSliderValue()` implementation**

Replace:

```swift
    private func updateSliderValue() {
        lightnessSlider.value = Node.getLightness100(lightness: node.lightness)
        cctSlider.value = Int(node.clampEffectiveCct(node.temperature))
    }
```

with:

```swift
    private func updateSliderValue() {
        configureControlPanel()
    }
```

- [ ] **Step 2: Add `configureControlPanel()`**

Add this method near `updateSliderValue()`:

```swift
    private func configureControlPanel() {
        let brightnessRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
        let cctRange = node.effectiveCctRange
        let configuration = DeviceLightControlPanelView.Configuration(
            controlType: space.controlType,
            showCCTQuickButtons: space.showCCTQuickButtons,
            showsBrightness: node.supportDimming,
            showsCCT: node.singleDeviceDisplaySupportCct,
            brightnessValue: node.isOn ? Node.getLightness100(lightness: node.lightness) : 0,
            brightnessRange: brightnessRange,
            cctValue: Int(node.clampEffectiveCct(node.temperature)),
            cctRange: Int(cctRange.lowerBound)...Int(cctRange.upperBound)
        )
        controlPanel.configure(configuration)
    }
```

- [ ] **Step 3: Replace `bindSliderAction()` implementation**

Replace the existing `bindSliderAction()` body with:

```swift
    private func bindSliderAction() {
        controlPanel.brightnessValueChanged = { [weak self] value in
            self?.applyBrightnessValue(value)
        }
        controlPanel.brightnessThrottleValueChanged = { [weak self] value, ended in
            guard let self = self else { return }
            let lightness = Node.getLightness(lightness100: value)
            MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: ended)
        }
        controlPanel.cctValueChanged = { [weak self] value in
            self?.applyCCTValue(value)
        }
        controlPanel.cctThrottleValueChanged = { [weak self] value, ended in
            guard let self = self else { return }
            let temperature = self.node.clampEffectiveCct(UInt16(value))
            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: temperature, ack: ended)
        }
        controlPanel.editBrightnessRequested = { [weak self] in
            self?.showBrightnessInputAlert()
        }
        controlPanel.editCCTRequested = { [weak self] in
            self?.showCCTInputAlert()
        }
    }
```

- [ ] **Step 4: Add local state update helpers**

Add these methods below `bindSliderAction()`:

```swift
    private func applyBrightnessValue(_ value: Int) {
        let brightnessRange = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
        let clampedValue = max(brightnessRange.lowerBound, min(brightnessRange.upperBound, value))
        let lightness = Node.getLightness(lightness100: clampedValue)
        if clampedValue == 0 {
            node.trunOffLightness = node.lightness
        }
        node.lightness = lightness
        node.isOn = lightness > 0
        updateData()
        controlPanel.setBrightnessValue(clampedValue)
    }

    private func applyCCTValue(_ value: Int) {
        let temperature = node.clampEffectiveCct(UInt16(value))
        node.temperature = temperature
        updateData()
        controlPanel.setCCTValue(Int(temperature))
    }
```

- [ ] **Step 5: Replace old slider visibility logic in `updateUI()`**

In `updateUI()`, remove direct `lightnessSlider.isHidden` and `cctSlider.isHidden` assignments.

Keep status labels visible/hidden with:

```swift
        cctView.isHidden = !node.singleDeviceDisplaySupportCct
        brightnessView.isHidden = !node.supportDimming
        configureControlPanel()
```

Preserve the existing `brightnessView` constraint remake for devices that support both brightness and CCT.

- [ ] **Step 6: Verify direct slider references are gone**

Run:

```bash
rg -n "lightnessSlider|cctSlider" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: no output.

- [ ] **Step 7: Commit controller panel wiring**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: use light control panel on device page"
```

Expected: commit succeeds.

---

### Task 5: Add Detailed Input Alerts

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Add integer parsing helper**

Add below `applyCCTValue(_:)`:

```swift
    private func integerInputValue(from text: String?) -> Int? {
        guard let text = text else { return nil }
        let valueText = text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "K", with: "")
            .replacingOccurrences(of: "k", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valueText.isEmpty else { return nil }
        return Int(valueText)
    }
```

- [ ] **Step 2: Add brightness alert**

Add below `integerInputValue(from:)`:

```swift
    private func showBrightnessInputAlert() {
        let range = Node.getLightness100(lightness: node.lightnessRange.lowerBound)...Node.getLightness100(lightness: node.lightnessRange.upperBound)
        let currentValue = controlPanel.currentBrightnessValue
        SRAlertView(
            title: "brightness".localizedString,
            inputText: "\(currentValue)%",
            inputFieldStyle: .init(placeholder: "\(range.lowerBound)~\(range.upperBound)", keyboardType: .numberPad),
            actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString)]
        ) { [weak self] text, _ in
            guard self?.integerInputValue(from: text) != nil else {
                return "illegal_input".localizedString
            }
            return nil
        } inputDoneBack: { [weak self] text in
            guard let self = self, let value = self.integerInputValue(from: text) else { return }
            let clampedValue = max(range.lowerBound, min(range.upperBound, value))
            self.applyBrightnessValue(clampedValue)
            let lightness = Node.getLightness(lightness100: clampedValue)
            MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: true)
        }.show()
    }
```

- [ ] **Step 3: Add CCT alert**

Add below `showBrightnessInputAlert()`:

```swift
    private func showCCTInputAlert() {
        let range = Int(node.effectiveCctRange.lowerBound)...Int(node.effectiveCctRange.upperBound)
        let currentValue = controlPanel.currentCCTValue
        SRAlertView(
            title: "color_temp".localizedString,
            inputText: "\(currentValue)",
            inputFieldStyle: .init(placeholder: "\(range.lowerBound)~\(range.upperBound)", keyboardType: .numberPad),
            actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString)]
        ) { [weak self] text, _ in
            guard self?.integerInputValue(from: text) != nil else {
                return "illegal_input".localizedString
            }
            return nil
        } inputDoneBack: { [weak self] text in
            guard let self = self, let value = self.integerInputValue(from: text) else { return }
            let clampedValue = max(range.lowerBound, min(range.upperBound, value))
            self.applyCCTValue(clampedValue)
            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: UInt16(clampedValue), ack: true)
        }.show()
    }
```

- [ ] **Step 4: Verify alert keys exist**

Run:

```bash
rg -n '"brightness"|"confirm"|"cancel"|"illegal_input"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: both localization files contain these keys.

- [ ] **Step 5: Commit alert handling**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: add detailed light input alerts"
```

Expected: commit succeeds.

---

### Task 6: Add `color_temp` Localization

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Check whether `color_temp` already exists**

Run:

```bash
rg -n '"color_temp"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected before change: no output.

- [ ] **Step 2: Add English localization**

In `SunSmart/en.lproj/Localizable.strings`, near `"color_temperature"`, add:

```text
"color_temp" = "Color Temp";
```

- [ ] **Step 3: Add Simplified Chinese localization**

In `SunSmart/zh-Hans.lproj/Localizable.strings`, near `"color_temperature"`, add:

```text
"color_temp" = "色温";
```

- [ ] **Step 4: Verify localization keys**

Run:

```bash
rg -n '"color_temp"' SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

```text
SunSmart/en.lproj/Localizable.strings:<line>:"color_temp" = "Color Temp";
SunSmart/zh-Hans.lproj/Localizable.strings:<line>:"color_temp" = "色温";
```

- [ ] **Step 5: Commit localization**

Run:

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add color temp localization"
```

Expected: commit succeeds.

---

### Task 7: Final Verification

**Files:**
- Verify: all changed files

- [ ] **Step 1: Verify scope**

Run:

```bash
git diff --name-only 017148d5..HEAD
```

Expected changed files are limited to:

```text
SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
SunSmart/Main/Device/Controller/DeviceLightViewController.swift
SunSmart/en.lproj/Localizable.strings
SunSmart/zh-Hans.lproj/Localizable.strings
SunSmart.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Verify quick button values**

Run:

```bash
rg -n "4500K|4500|2700, 3000, 3500, 4000, 5000, 6500|2700, 3000, 3500, 4000, 5000" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected:

```text
2700, 3000, 3500, 4000, 5000, 6500
2700, 3000, 3500, 4000, 5000
```

No `4500` output should appear.

- [ ] **Step 3: Verify panel stays reusable**

Run:

```bash
rg -n "Node|MeshAPI|DeviceLightViewController|GroupViewController" SunSmart/Main/Device/View/DeviceLightControlPanelView.swift
```

Expected: no output.

- [ ] **Step 4: Verify unrelated pages were not modified**

Run:

```bash
git diff --name-only 017148d5..HEAD | rg "GroupViewController|DeviceLightBasicController|DeviceLightsViewController"
```

Expected: no output.

- [ ] **Step 5: Run whitespace checks**

Run:

```bash
git diff --check 017148d5..HEAD
```

Expected: no output.

- [ ] **Step 6: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 7: Commit final fixes if verification required any**

If Task 7 found and fixed issues, run:

```bash
git add SunSmart/Main/Device/View/DeviceLightControlPanelView.swift SunSmart/Main/Device/Controller/DeviceLightViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: finalize device light control display"
```

Expected: commit succeeds only if there were additional fixes. If there were no fixes, skip this step.
