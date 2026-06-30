# EFC Working Mode Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the EFC Working Mode `SRAlertView` with an Add Device target-picker style single-selection popup.

**Architecture:** Keep the change scoped to the EFC edit table flow. Add a private `EmergencyFireWorkingModeSelectView` in `LinkedEmerFireEditVC+Table.swift` so no Xcode project source-list changes are required. The popup owns presentation and selection UI only; `LinkedEmerFireEditState` remains the source of truth for selected Working Mode.

**Tech Stack:** Swift, UIKit, SnapKit, existing `EmergencyFireWorkingMode`, existing `scripts/check_efc_controller_flows.sh`, iPhoneOS `xcodebuild`.

---

## File Structure

- Modify `scripts/check_efc_controller_flows.sh`
  - Add contract checks for the new popup, selected row state, backdrop dismiss, and exact English Working Mode labels.
- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
  - Add `SnapKit` and `NordicSigMeshSDK` imports.
  - Replace `showWorkingModeSelection()` with an anchored popup call.
  - Add private `EmergencyFireWorkingModeSelectView` and `EmergencyFireWorkingModeSelectCell` types at the bottom of the file.
- No planned changes to `DeviceAddTargetSelectView`.
- No planned changes to protocol, sync, cloud, or Working Mode persistence.

## Task 1: Contract Guard For Working Mode Popup

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add failing contract checks**

Add these assertions after the existing `.emergencyMode` edit-page assertion and before monitor visibility assertions:

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "EmergencyFireWorkingModeSelectView.show" \
  "EFC Working Mode must use the Add Device picker-style popup."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "selectedMode: state.workingMode" \
  "EFC Working Mode popup must receive the current selected mode."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "modes: state.selectableWorkingModes" \
  "EFC Working Mode popup must only show App-supported modes."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "@objc private func dismiss" \
  "EFC Working Mode popup must support tapping the blank area to close."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "selectedBackground.isHidden = !selected" \
  "EFC Working Mode popup must show a selected row state."

assert_not_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift" \
  "SRAlertView(" \
  "EFC Working Mode selection must not use the old alert style."

assert_contains "SunSmart/en.lproj/Localizable.strings" \
  '"efc_working_mode_fire_alarm_only" = "Fire Alarm Only";' \
  "English Working Mode label must be Fire Alarm Only."

assert_contains "SunSmart/en.lproj/Localizable.strings" \
  '"efc_working_mode_power_loss_and_fire_alarm" = "Power Loss & Fire Alarm";' \
  "English Working Mode label must be Power Loss & Fire Alarm."
```

- [ ] **Step 2: Run contract script to verify RED**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL because `EmergencyFireWorkingModeSelectView.show` does not exist yet and `SRAlertView(` still exists in `LinkedEmerFireEditVC+Table.swift`.

## Task 2: Implement The EFC Working Mode Popup

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`

- [ ] **Step 1: Add imports**

Change the top of the file to include SnapKit and the SDK type:

```swift
import UIKit
import SnapKit
import NordicSigMeshSDK
```

- [ ] **Step 2: Pass the selected row index path into the popup presenter**

Change the `.emergencyMode` branch in `didSelectRowAt`:

```swift
case .emergencyMode:
    showWorkingModeSelection(at: indexPath)
```

- [ ] **Step 3: Replace `SRAlertView` presenter with anchored popup presenter**

Replace `showWorkingModeSelection()` with:

```swift
private func showWorkingModeSelection(at indexPath: IndexPath) {
    let window = UIApplication.shared.keyWindow()
    let anchorPoint: CGPoint
    if let cell = tableView.cellForRow(at: indexPath) {
        let frame = cell.convert(cell.bounds, to: window)
        anchorPoint = CGPoint(
            x: frame.maxX - SCRXFrom(220),
            y: frame.maxY + SCRYFrom(2)
        )
    } else {
        anchorPoint = CGPoint(
            x: SCREEN_WIDTH - SCRXFrom(236),
            y: kNavigationHeight
        )
    }

    EmergencyFireWorkingModeSelectView.show(
        anchorPoint: anchorPoint,
        modes: state.selectableWorkingModes,
        selectedMode: state.workingMode
    ) { [weak self] mode in
        guard let self else { return }
        self.state.updateWorkingMode(mode)
        self.tableView.reloadData()
    }
}
```

- [ ] **Step 4: Add private popup view and cell**

Add this code after the existing `LinkedEmerFireEditVC` table extension:

```swift
private final class EmergencyFireWorkingModeSelectView: UIView {

    private enum Layout {
        static let menuWidth = SCRXFrom(220)
        static let rowHeight = SCRYFrom(45)
        static let horizontalInset = SCRXFrom(16)
        static let cornerRadius = SCRYFrom(12)
    }

    private let modes: [EmergencyFireWorkingMode]
    private let selectedMode: EmergencyFireWorkingMode
    private let selectionHandler: (EmergencyFireWorkingMode) -> Void

    private lazy var shadeView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(102, 102, 102)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = Layout.rowHeight
        tableView.showsVerticalScrollIndicator = false
        tableView.isScrollEnabled = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(EmergencyFireWorkingModeSelectCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()

    private init(
        anchorPoint: CGPoint,
        modes: [EmergencyFireWorkingMode],
        selectedMode: EmergencyFireWorkingMode,
        selectionHandler: @escaping (EmergencyFireWorkingMode) -> Void
    ) {
        self.modes = modes
        self.selectedMode = selectedMode
        self.selectionHandler = selectionHandler
        super.init(frame: UIScreen.main.bounds)
        setupUI(anchorPoint: anchorPoint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func show(
        anchorPoint: CGPoint,
        modes: [EmergencyFireWorkingMode],
        selectedMode: EmergencyFireWorkingMode,
        selectionHandler: @escaping (EmergencyFireWorkingMode) -> Void
    ) {
        let view = EmergencyFireWorkingModeSelectView(
            anchorPoint: anchorPoint,
            modes: modes,
            selectedMode: selectedMode,
            selectionHandler: selectionHandler
        )
        UIApplication.shared.keyWindow().addSubview(view)
        view.showAnimation()
    }

    private func setupUI(anchorPoint: CGPoint) {
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let contentHeight = min(CGFloat(modes.count) * Layout.rowHeight, SCREEN_HEIGHT / 2)
        let left = min(
            max(Layout.horizontalInset, anchorPoint.x),
            SCREEN_WIDTH - Layout.menuWidth - Layout.horizontalInset
        )
        let maxTop = max(Layout.horizontalInset, SCREEN_HEIGHT - contentHeight - Layout.horizontalInset)
        let top = min(max(Layout.horizontalInset, anchorPoint.y), maxTop)

        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(left)
            make.top.equalTo(top)
            make.width.equalTo(Layout.menuWidth)
            make.height.equalTo(contentHeight)
        }

        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func showAnimation() {
        contentView.alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.contentView.alpha = 1
        }
    }

    @objc private func dismiss() {
        UIView.animate(withDuration: 0.2) {
            self.contentView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}

extension EmergencyFireWorkingModeSelectView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        modes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! EmergencyFireWorkingModeSelectCell
        let mode = modes[indexPath.row]
        cell.configure(title: mode.localizedTitle, selected: mode == selectedMode)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectionHandler(modes[indexPath.row])
        dismiss()
    }
}

private final class EmergencyFireWorkingModeSelectCell: UITableViewCell {

    private let titleLabel = UILabel(text: nil, textColor: .white, fontSize: 14, fontWeight: .light)
    private let selectedBackground = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, selected: Bool) {
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        selectedBackground.isHidden = !selected
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        selectedBackground.backgroundColor = RGB(216, 216, 216, 0.1)
        selectedBackground.layer.cornerRadius = SCRYFrom(5)
        contentView.addSubview(selectedBackground)
        selectedBackground.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(8))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(4))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualToSuperview().offset(-SCRXFrom(16))
        }
    }
}
```

- [ ] **Step 5: Run contract script to verify GREEN**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: PASS with `EFC controller flow contracts passed.`

## Task 3: Final Verification

**Files:**
- Verify only; no planned source edits.

- [ ] **Step 1: Check formatting and whitespace**

Run:

```bash
git diff --check
```

Expected: no output, exit code 0.

- [ ] **Step 2: Build iPhoneOS target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git diff --stat
git diff -- scripts/check_efc_controller_flows.sh SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift
```

Expected: only the contract script and EFC edit table file changed for implementation.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add scripts/check_efc_controller_flows.sh SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift
git commit -m "feat: add EFC working mode popup"
```

Expected: implementation commit created after contract and build pass.

## Self-Review

- Spec coverage: The plan replaces `SRAlertView`, preserves Add Device code, adds Add Device-style popup visuals, shows three App-supported options, marks selected row, dismisses on blank tap, and leaves sync/protocol/cloud unchanged.
- Placeholder scan: No placeholder markers.
- Type consistency: `EmergencyFireWorkingModeSelectView.show`, `selectedMode`, `modes`, and `EmergencyFireWorkingModeSelectCell.configure(title:selected:)` are consistently named across tasks and contract checks.
