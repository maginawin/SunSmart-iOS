# Content Display UI Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents unless the user explicitly requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `CCT quick buttons` and `Control style` modules to the Content Display settings page, with Space-backed state, i18n text, Owner/Editor editing, Visitor read-only behavior, and existing `.common` / `.slow` cloud sync.

**Architecture:** Keep the existing `ContentDisplayViewController` entry and table structure. Preserve `ContentDisplayViewCell` for `Device name display`, add focused cells for the CCT switch module and the Control style selector, and route all setting changes through the existing `spaceDataChangedNotificaitonName` + `SpaceChangeDataType.common` path.

**Tech Stack:** Swift, UIKit, SnapKit, `UITableView`, `UIImage(named:)`, `.strings` localization, existing `SpaceData`, existing `CloudSynchronizationManager`, Xcode iPhoneOS build.

---

## Scope Notes

- This plan implements only the settings page. It does not modify Device / Group control pages to consume `showCCTQuickButtons` or `controlType`.
- `SpaceData.showCCTQuickButtons` and `SpaceData.controlType` already exist in the data layer. Do not recreate data columns or import/export logic unless source checks show the prior implementation is missing.
- Cloud sync must use `SpaceChangeDataType.common`, which maps to `.slow` in `SpaceViewController`.
- Owner and Editor can update all 3 Content Display settings. Visitor can view current values but cannot change them.
- The 4 provided Control style image sets are already staged in `SunSmart/Assets.xcassets/Common`; do not rewrite the image files.
- Existing staged image resources must not be mixed into intermediate implementation commits unless the user asks to commit them with the UI work.

## Files

- Modify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`
  - Expand options from one module to three.
  - Configure module-specific cells.
  - Compute `isEditable` from `space.permission == .owner || space.permission == .editor`.
  - Continue posting `SpaceChangeDataType.common` for all setting changes.
- Modify: `SunSmart/Main/Space/View/ContentDisplayViewCell.swift`
  - Add an `isEditable` configuration for the existing switch cell so Visitor cannot toggle `Display device name prefix`.
- Create: `SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift`
  - Display the `CCT quick buttons` module.
  - Own the description label, separator, row label, switch, editability, and callback.
- Create: `SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift`
  - Display the `Control style` module.
  - Own two selectable cards and selected/unselected rendering.
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - Add English strings for the new module titles, descriptions, and card labels.
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - Add Simplified Chinese strings for the new module titles, descriptions, and card labels.

---

### Task 1: Confirm Data, Resources, and Localized Keys

**Files:**
- Read: `SunSmart/Common/Data/SpaceData.swift`
- Read: `SunSmart/Common/Data/Database.swift`
- Read: `SunSmart/Common/Data/ExportData.swift`
- Read: `SunSmart/Common/Data/ImportData.swift`
- Read: `SunSmart/Assets.xcassets/Common`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: Confirm Space fields already exist**

Run:

```sh
rg -n "showCCTQuickButtons|controlType|SpaceControlType" SunSmart/Common/Data/SpaceData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected: output includes `SpaceData.showCCTQuickButtons`, `SpaceData.controlType`, database read/write, export keys, and import keys. If any data-layer path is missing, stop and update the plan before implementation.

- [ ] **Step 2: Confirm image resources exist**

Run:

```sh
find "SunSmart/Assets.xcassets/Common" -maxdepth 2 -type f | rg "detailed control type image|simple control type image|purple selected|purple unselected" | sort
```

Expected: output includes PNG and `Contents.json` files for all 4 image sets.

- [ ] **Step 3: Add English localization keys**

Append these lines near the existing `content_display` keys in `SunSmart/en.lproj/Localizable.strings`:

```text
"cct_quick_buttons" = "CCT quick buttons";
"cct_quick_buttons_note" = "Show CCT preset quick buttons on device and group pages with color temperature capable devices.";
"show_cct_quick_buttons" = "Show CCT quick buttons";
"control_style" = "Control style";
"control_style_note" = "Choose how slider control are displayed on device and group pages.";
"simple_control_style" = "Simple";
"simple_control_style_note" = "Slider only";
"detailed_control_style" = "Detailed";
"detailed_control_style_note" = "Label + value";
```

- [ ] **Step 4: Add Simplified Chinese localization keys**

Append these lines near the existing `content_display` keys in `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"cct_quick_buttons" = "CCT 快捷按钮";
"cct_quick_buttons_note" = "在支持色温的设备和群组页面显示 CCT 预设快捷按钮。";
"show_cct_quick_buttons" = "显示 CCT 快捷按钮";
"control_style" = "控制样式";
"control_style_note" = "选择设备和群组页面中滑块控件的显示方式。";
"simple_control_style" = "简洁";
"simple_control_style_note" = "仅滑块";
"detailed_control_style" = "详细";
"detailed_control_style_note" = "标签 + 数值";
```

- [ ] **Step 5: Verify localization keys are present in both files**

Run:

```sh
rg -n "cct_quick_buttons|control_style|simple_control_style|detailed_control_style" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: each key appears once in `en.lproj` and once in `zh-Hans.lproj`.

- [ ] **Step 6: Commit localization changes**

Run:

```sh
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add content display setting strings"
```

Expected: commit succeeds and includes only the two `.strings` files.

---

### Task 2: Make the Existing Device Name Cell Read-Only for Visitor

**Files:**
- Modify: `SunSmart/Main/Space/View/ContentDisplayViewCell.swift`

- [ ] **Step 1: Add editable configuration to `ContentDisplayViewCell`**

In `ContentDisplayViewCell`, add this property near `switchValueCallback`:

```swift
    var isEditable: Bool = true {
        didSet {
            enableSwitch.isEnabled = isEditable
            optionsLabel.alpha = isEditable ? 1 : 0.55
            enableSwitch.alpha = isEditable ? 1 : 0.55
        }
    }
```

- [ ] **Step 2: Reset reusable callback and editability during reuse**

Add this method before `setupUI()`:

```swift
    override func prepareForReuse() {
        super.prepareForReuse()
        switchValueCallback = nil
        isEditable = true
    }
```

- [ ] **Step 3: Confirm the file compiles locally by source check**

Run:

```sh
swiftc -parse SunSmart/Main/Space/View/ContentDisplayViewCell.swift
```

Expected: this command may fail because project globals such as `ImportantText_Color` are not available to standalone `swiftc`; ignore missing project-symbol errors. It must not report syntax errors around `isEditable` or `prepareForReuse`.

- [ ] **Step 4: Commit existing cell editability**

Run:

```sh
git add SunSmart/Main/Space/View/ContentDisplayViewCell.swift
git commit -m "feat: make content display prefix setting read-only"
```

Expected: commit includes only `ContentDisplayViewCell.swift`.

---

### Task 3: Add the CCT Quick Buttons Switch Cell

**Files:**
- Create: `SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift`

- [ ] **Step 1: Create `ContentDisplaySwitchViewCell.swift`**

Create `SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift` with this content:

```swift
import UIKit

class ContentDisplaySwitchViewCell: UITableViewCell {

    var titleLabel: UILabel!
    private var bgView: UIView!
    private var noteLabel: UILabel!
    private var lineView: UIView!
    private var optionsLabel: UILabel!
    private var enableSwitch: UISwitch!

    var switchValueCallback: ((Bool) -> Void)?

    var note: String? {
        didSet {
            guard let note = note else {
                noteLabel.attributedText = nil
                return
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6
            noteLabel.attributedText = NSAttributedString(string: note, attributes: [.paragraphStyle: style])
        }
    }

    var optionTitle: String? {
        didSet {
            optionsLabel.text = optionTitle
        }
    }

    var isOn: Bool {
        get { enableSwitch.isOn }
        set { enableSwitch.setOn(newValue, animated: false) }
    }

    var isEditable: Bool = true {
        didSet {
            enableSwitch.isEnabled = isEditable
            optionsLabel.alpha = isEditable ? 1 : 0.55
            enableSwitch.alpha = isEditable ? 1 : 0.55
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        switchValueCallback = nil
        isEditable = true
    }

    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        switchValueCallback?(sender.isOn)
    }

    private func setupUI() {
        titleLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(17))
        }

        bgView = UIView()
        bgView.layer.cornerRadius = SCRYFrom(10)
        bgView.backgroundColor = .white
        bgView.clipsToBounds = true
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }

        noteLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        bgView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
        }

        lineView = UIView()
        lineView.backgroundColor = Line_Color
        bgView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalToSuperview()
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(1)
        }

        optionsLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        bgView.addSubview(optionsLabel)
        optionsLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(lineView.snp.bottom).offset(SCRYFrom(13))
            make.bottom.equalTo(SCRYFrom(-14))
            make.width.lessThanOrEqualTo(SCRXFrom(230))
        }

        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        bgView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalTo(optionsLabel)
        }
    }
}
```

- [ ] **Step 2: Source check the new file**

Run:

```sh
swiftc -parse SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift
```

Expected: this command may fail because project globals are unavailable to standalone `swiftc`; ignore missing project-symbol errors. It must not report syntax errors in the new class.

- [ ] **Step 3: Commit the CCT switch cell**

Run:

```sh
git add SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift
git commit -m "feat: add cct quick buttons setting cell"
```

Expected: commit includes only the new switch cell file.

---

### Task 4: Add the Control Style Selector Cell

**Files:**
- Create: `SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift`

- [ ] **Step 1: Create `ContentDisplayControlStyleViewCell.swift`**

Create `SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift` with this content:

```swift
import UIKit

class ContentDisplayControlStyleViewCell: UITableViewCell {

    var titleLabel: UILabel!
    private var bgView: UIView!
    private var noteLabel: UILabel!
    private var stackView: UIStackView!
    private var simpleCard: ControlStyleCardView!
    private var detailedCard: ControlStyleCardView!

    var selectionCallback: ((SpaceControlType) -> Void)?

    var selectedType: SpaceControlType = .simple {
        didSet {
            updateSelection()
        }
    }

    var note: String? {
        didSet {
            guard let note = note else {
                noteLabel.attributedText = nil
                return
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 6
            noteLabel.attributedText = NSAttributedString(string: note, attributes: [.paragraphStyle: style])
        }
    }

    var isEditable: Bool = true {
        didSet {
            simpleCard.isEnabled = isEditable
            detailedCard.isEnabled = isEditable
            simpleCard.alpha = isEditable ? 1 : 0.55
            detailedCard.alpha = isEditable ? 1 : 0.55
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectionCallback = nil
        selectedType = .simple
        isEditable = true
    }

    @objc private func selectSimple() {
        guard isEditable else { return }
        selectionCallback?(.simple)
    }

    @objc private func selectDetailed() {
        guard isEditable else { return }
        selectionCallback?(.detailed)
    }

    private func setupUI() {
        titleLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(17))
        }

        bgView = UIView()
        bgView.layer.cornerRadius = SCRYFrom(10)
        bgView.backgroundColor = .white
        bgView.clipsToBounds = true
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalToSuperview()
        }

        noteLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        bgView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
        }

        simpleCard = ControlStyleCardView(
            imageName: "simple control type image",
            title: "simple_control_style".localizedString,
            subtitle: "simple_control_style_note".localizedString
        )
        detailedCard = ControlStyleCardView(
            imageName: "detailed control type image",
            title: "detailed_control_style".localizedString,
            subtitle: "detailed_control_style_note".localizedString
        )

        simpleCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectSimple)))
        detailedCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectDetailed)))

        stackView = UIStackView(arrangedSubviews: [simpleCard, detailedCard])
        stackView.axis = .horizontal
        stackView.spacing = SCRXFrom(12)
        stackView.distribution = .fillEqually
        bgView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(22))
            make.height.equalTo(SCRYFrom(188))
            make.bottom.equalTo(SCRYFrom(-16))
        }

        updateSelection()
    }

    private func updateSelection() {
        simpleCard.isSelected = selectedType == .simple
        detailedCard.isSelected = selectedType == .detailed
    }
}

private class ControlStyleCardView: UIView {

    private let imageView = UIImageView()
    private let titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .regular)
    private let subtitleLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
    private let indicatorImageView = UIImageView()

    var isEnabled: Bool = true {
        didSet {
            isUserInteractionEnabled = isEnabled
        }
    }

    var isSelected: Bool = false {
        didSet {
            layer.borderColor = (isSelected ? Bar_Color : Line_Color).cgColor
            indicatorImageView.image = UIImage(named: isSelected ? "purple selected" : "purple unselected")
        }
    }

    init(imageName: String, title: String, subtitle: String) {
        super.init(frame: .zero)
        layer.cornerRadius = SCRYFrom(14)
        layer.borderWidth = 1
        backgroundColor = .white
        imageView.image = UIImage(named: imageName)
        imageView.contentMode = .scaleAspectFit
        titleLabel.text = title
        titleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .center
        setupUI()
        isSelected = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(17))
            make.right.equalTo(SCRXFrom(-17))
            make.top.equalTo(SCRYFrom(17))
            make.height.equalTo(SCRYFrom(68))
        }

        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(12))
            make.height.equalTo(SCRYFrom(21))
        }

        addSubview(subtitleLabel)
        subtitleLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(2))
            make.height.equalTo(SCRYFrom(18))
        }

        addSubview(indicatorImageView)
        indicatorImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(subtitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.width.height.equalTo(SCRYFrom(16))
        }
    }
}
```

- [ ] **Step 2: Source check the selector cell**

Run:

```sh
swiftc -parse SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift
```

Expected: this command may fail because project globals and `SpaceControlType` are unavailable to standalone `swiftc`; ignore missing project-symbol errors. It must not report syntax errors in the new file.

- [ ] **Step 3: Commit the selector cell**

Run:

```sh
git add SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift
git commit -m "feat: add control style setting cell"
```

Expected: commit includes only the new selector cell file.

---

### Task 5: Wire the Content Display Controller

**Files:**
- Modify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`

- [ ] **Step 1: Replace `Options` with three cases**

Replace the existing `Options` enum with this version:

```swift
    enum Options {
        case deviceNameDisplay
        case cctQuickButtons
        case controlStyle

        var title: String {
            switch self {
            case .deviceNameDisplay:
                return "device_name_display".localizedString
            case .cctQuickButtons:
                return "cct_quick_buttons".localizedString
            case .controlStyle:
                return "control_style".localizedString
            }
        }

        var reuseIdentifier: String {
            switch self {
            case .deviceNameDisplay:
                return "deviceNameDisplayCell"
            case .cctQuickButtons:
                return "switchCell"
            case .controlStyle:
                return "controlStyleCell"
            }
        }
    }
```

- [ ] **Step 2: Expand the options array and add editability**

Change the `options` property and add `isEditable`:

```swift
    private let options: [Options] = [.deviceNameDisplay, .cctQuickButtons, .controlStyle]

    private var isEditable: Bool {
        space.permission == .owner || space.permission == .editor
    }
```

- [ ] **Step 3: Register all cell types**

In `setupUI()`, replace the existing `register` call with:

```swift
        tableView.register(ContentDisplayViewCell.classForCoder(), forCellReuseIdentifier: Options.deviceNameDisplay.reuseIdentifier)
        tableView.register(ContentDisplaySwitchViewCell.classForCoder(), forCellReuseIdentifier: Options.cctQuickButtons.reuseIdentifier)
        tableView.register(ContentDisplayControlStyleViewCell.classForCoder(), forCellReuseIdentifier: Options.controlStyle.reuseIdentifier)
```

- [ ] **Step 4: Keep common save notification**

Keep `notifyContentDisplayChanged()` posting `.common`:

```swift
    private func notifyContentDisplayChanged() {
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.common
        )
    }
```

- [ ] **Step 5: Replace `cellForRowAt` with module-specific configuration**

Replace the current `cellForRowAt` method body with:

```swift
        let option = options[indexPath.row]

        switch option {
        case .deviceNameDisplay:
            let cell = tableView.dequeueReusableCell(withIdentifier: option.reuseIdentifier, for: indexPath) as! ContentDisplayViewCell
            cell.titleLabel.text = option.title
            cell.disableModeImageView.image = UIImage(named: "device_name_prefixes_hide")
            cell.enableModeImageView.image = UIImage(named: "device_name_prefixes_display")
            cell.note = "device_name_display_note".localizedString
            cell.optionsLabel.text = "display_device_name_prefix".localizedString
            cell.enableSwitch.isOn = space.displayDeviceNamePrefix
            cell.isEditable = isEditable
            cell.switchValueCallback = { [weak self] isOn in
                guard let self = self, self.isEditable else { return }
                guard self.space.displayDeviceNamePrefix != isOn else { return }
                self.space.displayDeviceNamePrefix = isOn
                self.notifyContentDisplayChanged()
            }
            return cell

        case .cctQuickButtons:
            let cell = tableView.dequeueReusableCell(withIdentifier: option.reuseIdentifier, for: indexPath) as! ContentDisplaySwitchViewCell
            cell.titleLabel.text = option.title
            cell.note = "cct_quick_buttons_note".localizedString
            cell.optionTitle = "show_cct_quick_buttons".localizedString
            cell.isOn = space.showCCTQuickButtons
            cell.isEditable = isEditable
            cell.switchValueCallback = { [weak self] isOn in
                guard let self = self, self.isEditable else { return }
                guard self.space.showCCTQuickButtons != isOn else { return }
                self.space.showCCTQuickButtons = isOn
                self.notifyContentDisplayChanged()
            }
            return cell

        case .controlStyle:
            let cell = tableView.dequeueReusableCell(withIdentifier: option.reuseIdentifier, for: indexPath) as! ContentDisplayControlStyleViewCell
            cell.titleLabel.text = option.title
            cell.note = "control_style_note".localizedString
            cell.selectedType = space.controlType
            cell.isEditable = isEditable
            cell.selectionCallback = { [weak self, weak cell] type in
                guard let self = self, self.isEditable else { return }
                guard self.space.controlType != type else { return }
                self.space.controlType = type
                cell?.selectedType = type
                self.notifyContentDisplayChanged()
            }
            return cell
        }
```

- [ ] **Step 6: Source check the controller**

Run:

```sh
swiftc -parse SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected: this command may fail because project globals and referenced cells are unavailable to standalone `swiftc`; ignore missing project-symbol errors. It must not report syntax errors in the changed switch or closures.

- [ ] **Step 7: Commit controller wiring**

Run:

```sh
git add SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
git commit -m "feat: wire content display settings"
```

Expected: commit includes only `ContentDisplayViewController.swift`.

---

### Task 6: Build and Verify

**Files:**
- Verify all touched files.

- [ ] **Step 1: Verify `.common` sync path remains in use**

Run:

```sh
rg -n "SpaceChangeDataType.common|SpaceChangeDataType.contentDisplay|syncSpace\\(level: \\.slow\\)|syncSpace\\(level: \\.promptly\\)" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected:

- `ContentDisplayViewController.swift` posts `SpaceChangeDataType.common`.
- No `SpaceChangeDataType.contentDisplay` appears.
- `SpaceViewController.swift` still maps `.common` to `.slow`.

- [ ] **Step 2: Verify Visitor read-only guards**

Run:

```sh
rg -n "isEditable|permission == \\.owner|permission == \\.editor|isEnabled = isEditable|guard let self = self, self.isEditable" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift SunSmart/Main/Space/View/ContentDisplayViewCell.swift SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift
```

Expected:

- Controller computes `isEditable` from owner/editor.
- Existing and new switch controls use `isEnabled = isEditable`.
- Control style cards use `isUserInteractionEnabled = isEditable`.
- All callbacks guard `self.isEditable`.

- [ ] **Step 3: Verify image names are referenced exactly**

Run:

```sh
rg -n "\"simple control type image\"|\"detailed control type image\"|\"purple selected\"|\"purple unselected\"" SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift
```

Expected: all 4 image names appear exactly once or more.

- [ ] **Step 4: Verify dirty diff before build**

Run:

```sh
git status --short
```

Expected: only intended implementation files are modified or staged, plus the pre-existing staged image resources and pre-existing untracked analysis doc. Do not revert or remove user-owned staged files.

- [ ] **Step 5: Run whitespace check**

Run:

```sh
git diff --check
git diff --cached --check
```

Expected: both commands produce no output.

- [ ] **Step 6: Run the required iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds. If build fails, fix only errors related to the touched Content Display, localization, or asset-reference files.

- [ ] **Step 7: Commit any final fixes**

Run:

```sh
git add SunSmart/Main/Space/Controller/ContentDisplayViewController.swift SunSmart/Main/Space/View/ContentDisplayViewCell.swift SunSmart/Main/Space/View/ContentDisplaySwitchViewCell.swift SunSmart/Main/Space/View/ContentDisplayControlStyleViewCell.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add content display UI settings"
```

Expected: commit includes only implementation files. If earlier tasks already committed all implementation files and this command has nothing to commit, keep the earlier commits and do not create an empty commit.

---

## Self-Review

- Spec coverage:
  - Settings page gets the two new modules: Tasks 3, 4, and 5.
  - `showCCTQuickButtons` and `controlType` initial state comes from `SpaceData`: Task 5.
  - Local save and cloud sync use existing `.common` / `.slow`: Task 5 and Task 6.
  - Owner/Editor editable and Visitor read-only: Tasks 2, 4, 5, and 6.
  - i18n text: Task 1.
  - Provided images: Tasks 1, 4, and 6.
  - No Device / Group control page consumption: Scope Notes and Files section exclude those files.
- Placeholder scan: no placeholder tokens or unspecified implementation steps remain.
- Type consistency:
  - `SpaceControlType.simple` and `.detailed` are used consistently.
  - `isEditable` is consistently computed in the controller and applied to all cells.
  - Sync remains `SpaceChangeDataType.common`; no new `contentDisplay` type is introduced.
