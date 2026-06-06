# Group Power Switch UI Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align Battery Power Switch and AC Power Switch group pages with the working Kinetic switch page for collapsed height, expanded rows, panel styling, row arrows, and expand/collapse behavior.

**Architecture:** Convert `GroupPowerSwitchesViewController` from one table row per switch to one table section per switch, matching `GroupSwitchsViewController`. Keep Battery/AC business logic in the existing controller/view model, and replace only the table presentation layer. Add Battery/AC-specific header and expanded cells inside the existing compiled `GroupPowerSwitchCell.swift` file to avoid Xcode project file churn.

**Tech Stack:** UIKit, UITableView, SnapKit, existing SunSmart UI constants/assets, `PJEightKeySwitchData`, `PJEightKeySwitchPanelView`, `CustomTableViewCell`.

---

## File Structure

- Modify `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`
  - Replace the current single expanded cell implementation with focused Battery/AC table components:
    - `GroupPowerSwitchHeaderView`: `UITableViewHeaderFooterView`, visually aligned with `GroupSwitchsHeaderView`.
    - `GroupPowerSwitchPanelPreviewCell`: `UITableViewCell`, wraps `PJEightKeySwitchPanelView` in a Kinetic-style white bordered panel container.
    - `GroupPowerSwitchActionCell`: `UITableViewCell`, owns delete/save buttons and mirrors Kinetic action placement.
- Modify `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
  - Convert table layout to sections.
  - Add a private expanded row enum.
  - Register new header/cell types and `CustomTableViewCell`.
  - Move expand/collapse from `didSelectRowAt` to header-only callbacks.
  - Keep existing save/delete/enable/panel/group/scene/more settings logic intact.
- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift`
  - Align right arrow constraints with `CustomTableViewCell` so Battery/AC edit switch rows use the same arrow resource, size, and right position as Kinetic rows.

## Task 1: Align Edit Row Arrow Constraints

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift`

- [ ] **Step 1: Inspect current arrow constraints**

Run:

```sh
sed -n '1,150p' SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift
sed -n '260,315p' SunSmart/Common/View/CustomTableViewCell.swift
```

Expected: `PJEightKeySwitchInfoRowView` uses `arrow_right` with `right = -12` and forced `16x16`, while `CustomTableViewCell` uses `arrow_right` with `right = -8` and natural image size.

- [ ] **Step 2: Add a helper for Kinetic-style arrow placement**

In `PJEightKeySwitchInfoRowView`, add this helper inside the class:

```swift
    private func makeKineticArrowConstraints() {
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
    }
```

- [ ] **Step 3: Use the helper for `.arrow` and `.valueWithArrow`**

Replace both direct `arrowImageView.snp.makeConstraints` blocks with:

```swift
            makeKineticArrowConstraints()
```

For `.valueWithArrow`, keep `valueLabel` to the left of the arrow:

```swift
            valueLabel.snp.makeConstraints { make in
                make.right.equalTo(SCRXFrom(-36))
                make.centerY.equalToSuperview()
                make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(8))
            }
```

Expected: edit switch page rows still show values where required, but the arrow itself matches Kinetic rows.

- [ ] **Step 4: Commit after Task 1**

Run:

```sh
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift
git commit -m "fix: align power switch edit row arrows"
```

Expected: commit includes only `PJEightKeySwitchInfoRowView.swift`.

## Task 2: Replace Single Power Switch Cell With Focused Table Components

**Files:**
- Modify: `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`

- [ ] **Step 1: Replace `GroupPowerSwitchCell` with `GroupPowerSwitchHeaderView`**

Replace the current `GroupPowerSwitchCell` class with a `GroupPowerSwitchHeaderView` that uses this shape:

```swift
final class GroupPowerSwitchHeaderView: UITableViewHeaderFooterView {

    struct State {
        let name: String
        let detailText: String
        let isEnabled: Bool
        let isExpanded: Bool
        let isEditable: Bool
        let isEnablePending: Bool
    }

    var expandAction: (() -> Void)?
    var enableAction: ((Bool) -> Void)?

    private let titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)
    private let detailLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
    private let arrowImageView = UIImageView(image: UIImage(named: "arrow_down"))
    private let enableSwitch = UISwitch()
    private let enableButton = UIButton()
    private let lineView = UIView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        expandAction = nil
        enableAction = nil
    }

    func configure(state: State) {
        titleLabel.text = state.name
        detailLabel.text = state.detailText
        enableSwitch.isOn = state.isEnabled
        enableSwitch.alpha = state.isEnablePending ? 0.45 : 1
        enableButton.isEnabled = state.isEditable && !state.isEnablePending
        arrowImageView.image = UIImage(named: state.isExpanded ? "arrow_up" : "arrow_down")
    }
}
```

- [ ] **Step 2: Implement Kinetic-matching header layout**

Add `setupUI()` with these constraints:

```swift
    private func setupUI() {
        contentView.backgroundColor = .white

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(13))
        }

        detailLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(detailLabel)
        detailLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(5))
            make.right.lessThanOrEqualTo(enableSwitch.snp.left).offset(SCRXFrom(-12))
        }

        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }

        enableSwitch.onTintColor = Bar_Color
        enableSwitch.tintColor = RGB(207, 207, 207)
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }

        enableSwitch.addSubview(enableButton)
        enableButton.snp.makeConstraints { make in
            make.edges.equalTo(enableSwitch)
        }

        lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }
```

- [ ] **Step 3: Wire header actions**

Add:

```swift
    private func bindActions() {
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(expandButtonAction)))
        enableButton.addTarget(self, action: #selector(enableButtonAction), for: .touchUpInside)
    }

    @objc private func expandButtonAction() {
        expandAction?()
    }

    @objc private func enableButtonAction() {
        enableAction?(!enableSwitch.isOn)
    }
```

- [ ] **Step 4: Add `GroupPowerSwitchPanelPreviewCell`**

Append this cell in the same file:

```swift
final class GroupPowerSwitchPanelPreviewCell: UITableViewCell {

    private let panelContainerView: UIView = {
        let view = UIView()
        view.layer.borderColor = RGB(220, 220, 220).cgColor
        view.layer.borderWidth = 0.6
        view.layer.cornerRadius = 15
        view.backgroundColor = .white
        return view
    }()

    private let panelPreviewView = PJEightKeySwitchPanelView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(definition: PJEightKeySwitchPanelDefinition) {
        panelPreviewView.configure(definition: definition, mode: .preview)
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = Background_Color
        contentView.backgroundColor = Background_Color

        contentView.addSubview(panelContainerView)
        panelContainerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(288))
        }

        panelContainerView.addSubview(panelPreviewView)
        panelPreviewView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(8), left: SCRXFrom(8), bottom: SCRYFrom(8), right: SCRXFrom(8)))
        }
    }
}
```

- [ ] **Step 5: Add `GroupPowerSwitchActionCell`**

Append:

```swift
final class GroupPowerSwitchActionCell: UITableViewCell {

    var deleteAction: (() -> Void)?
    var saveAction: (() -> Void)?

    private let deleteButton = UIButton(normalImageName: "switch_delete")
    private let saveButton = UIButton(normalImageName: "switch_save")

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        deleteAction = nil
        saveAction = nil
    }

    func configure(isEditable: Bool, isSaveEnabled: Bool) {
        deleteButton.isEnabled = isEditable
        deleteButton.alpha = isEditable ? 1 : 0.35
        saveButton.isEnabled = isEditable && isSaveEnabled
        saveButton.setImage(UIImage(named: isSaveEnabled ? "switch_save" : "switch_save_un"), for: .normal)
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = Background_Color
        contentView.backgroundColor = Background_Color

        contentView.addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(56))
            make.top.equalTo(SCRYFrom(16))
            make.height.equalTo(40)
        }

        saveButton.setImage(UIImage(named: "switch_save_un"), for: .disabled)
        contentView.addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-56))
            make.centerY.height.equalTo(deleteButton)
        }
    }

    private func bindActions() {
        deleteButton.addTarget(self, action: #selector(deleteButtonAction), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveButtonAction), for: .touchUpInside)
    }

    @objc private func deleteButtonAction() {
        deleteAction?()
    }

    @objc private func saveButtonAction() {
        saveAction?()
    }
}
```

- [ ] **Step 6: Commit after Task 2**

Run:

```sh
git add SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift
git commit -m "refactor: add power switch table components"
```

Expected: commit includes only `GroupPowerSwitchCell.swift`.

## Task 3: Convert Group Power Switch Table To Sections

**Files:**
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: Add row enum**

Inside `GroupPowerSwitchesViewController`, add:

```swift
    private enum Row: Equatable {
        case panel
        case group
        case scene
        case moreSettings
        case panelPreview
        case actions
    }
```

- [ ] **Step 2: Update table registration**

Replace the current table registration:

```swift
        tableView.register(GroupPowerSwitchCell.self, forCellReuseIdentifier: "powerSwitch")
```

with:

```swift
        tableView.register(CustomTableViewCell.self, forCellReuseIdentifier: "info")
        tableView.register(GroupPowerSwitchPanelPreviewCell.self, forCellReuseIdentifier: "panelPreview")
        tableView.register(GroupPowerSwitchActionCell.self, forCellReuseIdentifier: "actions")
        tableView.register(GroupPowerSwitchHeaderView.self, forHeaderFooterViewReuseIdentifier: "header")
```

- [ ] **Step 3: Add helper methods for sections and rows**

Add:

```swift
    private func switchData(section: Int) -> PJEightKeySwitchData {
        viewModel.switchData(at: section)
    }

    private func rows(for switchData: PJEightKeySwitchData) -> [Row] {
        var rows: [Row] = [.panel, .group]
        if viewModel.showsSceneRow(for: switchData) {
            rows.append(.scene)
        }
        rows.append(contentsOf: [.moreSettings, .panelPreview, .actions])
        return rows
    }
```

- [ ] **Step 4: Replace data source methods**

Replace the `UITableViewDataSource` implementation with section-based methods:

```swift
    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.switchDatas.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let switchData = switchData(section: section)
        return expandedSwitchIDs.contains(switchData.id) ? rows(for: switchData).count : 0
    }
```

- [ ] **Step 5: Add `viewForHeaderInSection`**

Add:

```swift
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupPowerSwitchHeaderView
        let switchData = switchData(section: section)
        let switchID = switchData.id
        headerView.configure(state: .init(
            name: switchData.name,
            detailText: viewModel.detailText(for: switchData),
            isEnabled: switchData.enabled,
            isExpanded: expandedSwitchIDs.contains(switchID),
            isEditable: editable,
            isEnablePending: pendingEnableSwitchIDs.contains(switchID)
        ))
        headerView.expandAction = { [weak self] in
            self?.toggleExpanded(id: switchID)
        }
        headerView.enableAction = { [weak self] enabled in
            self?.startEnableUpdate(id: switchID, enabled: enabled)
        }
        return headerView
    }
```

- [ ] **Step 6: Add section heights**

Add:

```swift
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        SCRYFrom(64)
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0.01
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }
```

- [ ] **Step 7: Replace `cellForRowAt`**

Use row-specific cells:

```swift
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let switchData = switchData(section: indexPath.section)
        let row = rows(for: switchData)[indexPath.row]

        switch row {
        case .panel, .group, .scene, .moreSettings:
            let cell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! CustomTableViewCell
            configureInfoCell(cell, row: row, switchData: switchData)
            return cell
        case .panelPreview:
            let cell = tableView.dequeueReusableCell(withIdentifier: "panelPreview", for: indexPath) as! GroupPowerSwitchPanelPreviewCell
            cell.configure(definition: PJEightKeySwitchPanelDefinition.make(type: switchData.eightKeyPanelType))
            return cell
        case .actions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "actions", for: indexPath) as! GroupPowerSwitchActionCell
            let switchID = switchData.id
            cell.configure(isEditable: editable, isSaveEnabled: viewModel.hasSaveChanges(switchData))
            cell.deleteAction = { [weak self] in self?.deleteSwitch(id: switchID) }
            cell.saveAction = { [weak self] in self?.saveSwitch(id: switchID) }
            return cell
        }
    }
```

- [ ] **Step 8: Add `configureInfoCell`**

Add:

```swift
    private func configureInfoCell(_ cell: CustomTableViewCell, row: Row, switchData: PJEightKeySwitchData) {
        cell.selectionStyle = .none
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.titleX = SCRXFrom(32)
        cell.cellStyle = .arrow

        switch row {
        case .panel:
            cell.titleLabel.text = "panel".localizedString
            cell.contentLabel.text = switchData.eightKeyPanelType.title
        case .group:
            cell.titleLabel.text = "group".localizedString
            cell.contentLabel.text = viewModel.groupTitle(for: switchData)
        case .scene:
            cell.titleLabel.text = "scene".localizedString
            cell.contentLabel.text = viewModel.sceneTitle(for: switchData)
        case .moreSettings:
            cell.titleLabel.text = "neightkeyswitches_more_settings".localizedString
            cell.contentLabel.text = nil
        case .panelPreview, .actions:
            break
        }
    }
```

- [ ] **Step 9: Add row heights**

Add:

```swift
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let switchData = switchData(section: indexPath.section)
        let row = rows(for: switchData)[indexPath.row]
        switch row {
        case .panelPreview:
            return SCRYFrom(84) + SCRXFrom(288)
        case .actions:
            return SCRYFrom(64)
        case .panel, .group, .scene, .moreSettings:
            return SCRYFrom(44)
        }
    }
```

- [ ] **Step 10: Replace `didSelectRowAt`**

Replace the current implementation that toggles expansion with:

```swift
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let switchData = switchData(section: indexPath.section)
        let row = rows(for: switchData)[indexPath.row]

        guard editable || row == .group || row == .panelPreview else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }

        switch row {
        case .panel:
            selectPanel(id: switchData.id)
        case .group:
            showGroups(id: switchData.id)
        case .scene:
            selectScenes(id: switchData.id)
        case .moreSettings:
            moreSettings(id: switchData.id)
        case .panelPreview, .actions:
            break
        }
    }
```

Expected: only the section header expands/collapses. Bottom panel and action cells do not collapse the switch.

- [ ] **Step 11: Update row insert/delete/reload helpers**

Change row operations to section operations:

```swift
        tableView.insertSections(IndexSet(integer: index), with: .top)
```

in add flow, and:

```swift
        tableView.reloadSections(IndexSet(integer: index), with: animation)
```

in `reloadSwitch(id:animation:)`, and:

```swift
        tableView.deleteSections(IndexSet(integer: index), with: .fade)
```

in `removeSwitchRow(id:)`.

- [ ] **Step 12: Commit after Task 3**

Run:

```sh
git add SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
git commit -m "refactor: align power switch group table layout"
```

Expected: commit includes only `GroupPowerSwitchesViewController.swift`.

## Task 4: Verify Behavior And Build

**Files:**
- Verify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
- Verify: `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift`

- [ ] **Step 1: Search for stale single-cell references**

Run:

```sh
rg -n "GroupPowerSwitchCell|powerSwitch|didSelectRowAt|moreSettingsTitle\\(|valueWithArrow" SunSmart/Main/Group/Switch SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchEditorView.swift
```

Expected:

- No active `GroupPowerSwitchCell.self` registration remains.
- `didSelectRowAt` in `GroupPowerSwitchesViewController` routes rows and does not toggle expansion.
- `moreSettingsTitle(for:)` may remain in the view model but is no longer used by the group page.
- `PJEightKeySwitchEditorView.moreSettingsRowView` remains `.arrow`.

- [ ] **Step 2: Build SunSmart for iPhoneOS**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: If build fails, inspect diagnostics and fix only touched files**

Use the compiler output to fix type or registration errors in:

```text
SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift
SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchInfoRowView.swift
```

Do not refactor unrelated files.

- [ ] **Step 4: Final status check**

Run:

```sh
git status --short
git log --oneline -4
```

Expected: only intentional changes are present; commits are focused and do not include unrelated working tree files.
