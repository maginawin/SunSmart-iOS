# EFC Status Content List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 EFC 设备页展开后的 `EmerFireAlarmStatusSetView` content list 从 4 行调整为 Figma 指定的 3 行，并支持 `Emergency event ends` 的动态 action/resuming 信息。

**Architecture:** 先新增源码 contract 脚本锁定 content list 行数、顺序和已移除文案，再扩展 status item/cell 模型为多组 detail/value。业务数据仍由 `EmerFireAlarmMonitorState.statusItems(for:)` 统一生成，view 只负责渲染。

**Tech Stack:** Swift, UIKit, SnapKit, Bash contract script, Xcode iPhoneOS build.

---

## File Structure

- Create: `scripts/check_efc_status_content_list.sh`
  - 用源码 contract 验证 status content list 的目标文案、移除项、动态 action 分支和 cell 多行 detail/value 支持。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
  - 调整 `statusItems(for:)` 输出 3 行。
  - 添加 restore action 文案映射 helper。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift`
  - 把 item 模型从 `subtitle/value` 扩展为多组 `details`。
  - 继续使用当前 table view 和 `EmerFireAlarmStatusItemCell`。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusItemCell.swift`
  - 支持 1 组或 2 组 detail/value。
  - 使用垂直 stack view 保持 Auto Layout 自动高度。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 新增 `emergency_event_ends`、`restore_auto`、`restore_none`、`set_brightness_to_value`。

## Task 1: Add Content List Contract

**Files:**
- Create: `scripts/check_efc_status_content_list.sh`

- [ ] **Step 1: Write the failing contract script**

Create `scripts/check_efc_status_content_list.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  expected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  unexpected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

STATE_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift"
SET_VIEW_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift"
CELL_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusItemCell.swift"
STRINGS_FILE="SunSmart/en.lproj/Localizable.strings"

assert_contains "$STATE_FILE" '"fire_alarm_occurs".localizedString' \
  "Status list must display Fire alarm occurs."
assert_contains "$STATE_FILE" '"power_supply_fails".localizedString' \
  "Status list must display Power supply fails."
assert_contains "$STATE_FILE" '"emergency_event_ends".localizedString' \
  "Status list must display Emergency event ends."
assert_contains "$STATE_FILE" 'restoreActionTitle(for:' \
  "Status list must derive a dynamic restore action title."
assert_contains "$STATE_FILE" 'case .restoreAuto:' \
  "Restore AUTO must have an explicit display value."
assert_contains "$STATE_FILE" 'case .setBrightness:' \
  "Set brightness restore must have an explicit display value."
assert_contains "$STATE_FILE" 'case .none:' \
  "None restore must have an explicit display value."

assert_not_contains "$STATE_FILE" '"power_is_restored".localizedString' \
  "Status list must not display Power is restored."
assert_not_contains "$STATE_FILE" '"fire_alarm_stops".localizedString' \
  "Status list must not display Fire alarm stops."

assert_contains "$SET_VIEW_FILE" 'struct DetailViewModel' \
  "Status set view item model must support multiple detail/value rows."
assert_contains "$SET_VIEW_FILE" 'details:' \
  "Status set view must pass detail/value rows to the cell."
assert_contains "$CELL_FILE" 'detailStackView' \
  "Status item cell must render multiple detail/value rows."
assert_contains "$CELL_FILE" 'rightValueStackView' \
  "Status item cell must align multiple right-side values."

assert_contains "$STRINGS_FILE" '"emergency_event_ends" = "Emergency event ends";' \
  "English strings must include Emergency event ends."
assert_contains "$STRINGS_FILE" '"restore_auto" = "Auto";' \
  "English strings must include Auto restore action."
assert_contains "$STRINGS_FILE" '"restore_none" = "None";' \
  "English strings must include None restore action."
assert_contains "$STRINGS_FILE" '"set_brightness_to_value" = "Set Brightness to %@";' \
  "English strings must include Set Brightness action format."

echo "EFC status content list contracts passed."
```

- [ ] **Step 2: Run the contract and verify it fails**

Run: `bash scripts/check_efc_status_content_list.sh`

Expected: FAIL on the first missing target introduced by this plan, such as `emergency_event_ends` or `DetailViewModel`.

- [ ] **Step 3: Commit the failing contract**

```bash
git add scripts/check_efc_status_content_list.sh
git commit -m "test: add EFC status content list contract"
```

## Task 2: Extend Item and Cell Rendering

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusItemCell.swift`

- [ ] **Step 1: Extend status set item models**

In `EmerFireAlarmStatusSetView.swift`, replace the private `StatusItem` and public `ItemViewModel` definitions with:

```swift
private struct StatusItem {
    let kind: RowKind
    let title: String
    let details: [DetailViewModel]
}

struct DetailViewModel {
    let subtitle: String
    let value: String
}

struct ItemViewModel {
    let kind: RowKind
    let title: String
    let details: [DetailViewModel]
}
```

Then update `updateItems(_:)`:

```swift
func updateItems(_ items: [ItemViewModel]) {
    self.items = items.map {
        StatusItem(kind: $0.kind, title: $0.title, details: $0.details)
    }
    tableView.reloadData()
}
```

Then update `cellForRowAt`:

```swift
let item = items[indexPath.row]
cell.configure(with: .init(title: item.title, details: item.details))
return cell
```

- [ ] **Step 2: Extend status item cell view model**

In `EmerFireAlarmStatusItemCell.swift`, replace `ViewModel` with:

```swift
struct ViewModel {
    let title: String
    let details: [EmerFireAlarmStatusSetView.DetailViewModel]
    let statusImageName: String?

    init(
        title: String,
        details: [EmerFireAlarmStatusSetView.DetailViewModel],
        statusImageName: String? = nil
    ) {
        self.title = title
        self.details = details
        self.statusImageName = statusImageName
    }
}
```

- [ ] **Step 3: Replace single subtitle/value labels with stacks**

In `EmerFireAlarmStatusItemCell.swift`, replace `subtitleLabel` and `valueLabel` with:

```swift
private lazy var detailStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.alignment = .leading
    stackView.spacing = SCRYFrom(4)
    return stackView
}()

private lazy var rightValueStackView: UIStackView = {
    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.spacing = SCRYFrom(4)
    return stackView
}()
```

Add helpers:

```swift
private func makeSubtitleLabel(text: String) -> UILabel {
    let label = UILabel(text: text, textColor: AssistText_Color, fontSize: 11, fontWeight: .light)
    label.numberOfLines = 1
    return label
}

private func makeValueLabel(text: String) -> UILabel {
    let label = UILabel(text: text, textColor: Bar_Color, fontSize: 13, fontWeight: .light)
    label.textAlignment = .right
    label.numberOfLines = 1
    return label
}

private func resetStackView(_ stackView: UIStackView) {
    stackView.arrangedSubviews.forEach { view in
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
    }
}
```

Update `configure(with:)`:

```swift
func configure(with viewModel: ViewModel) {
    titleLabel.text = viewModel.title
    resetStackView(detailStackView)
    resetStackView(rightValueStackView)

    viewModel.details.forEach { detail in
        detailStackView.addArrangedSubview(makeSubtitleLabel(text: detail.subtitle))
        rightValueStackView.addArrangedSubview(makeValueLabel(text: detail.value))
    }

    statusImageView.image = viewModel.statusImageName.flatMap { UIImage(named: $0) }
    statusImageView.isHidden = viewModel.statusImageName == nil
}
```

- [ ] **Step 4: Update cell constraints**

In `setupUI()`, replace constraints that reference `valueLabel` and `subtitleLabel` with:

```swift
contentView.addSubview(rightValueStackView)
rightValueStackView.snp.makeConstraints { make in
    make.right.equalToSuperview().offset(-Layout.horizontalInset)
    make.bottom.equalToSuperview().offset(-Layout.bottomInset)
}

contentView.addSubview(statusImageView)
statusImageView.snp.makeConstraints { make in
    make.right.equalTo(rightValueStackView.snp.left).offset(-SCRXFrom(10))
    make.centerY.equalTo(rightValueStackView)
    make.width.height.equalTo(SCRXFrom(14))
}

contentView.addSubview(titleLabel)
titleLabel.snp.makeConstraints { make in
    make.left.equalToSuperview().offset(Layout.horizontalInset)
    make.top.equalToSuperview().offset(Layout.topInset)
    make.right.lessThanOrEqualTo(statusImageView.snp.left).offset(-SCRXFrom(12))
}

contentView.addSubview(detailStackView)
detailStackView.snp.makeConstraints { make in
    make.left.equalTo(titleLabel)
    make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(6))
    make.right.lessThanOrEqualTo(statusImageView.snp.left).offset(-SCRXFrom(12))
    make.bottom.equalToSuperview().offset(-Layout.bottomInset)
}
```

- [ ] **Step 5: Run compile check for changed Swift files**

Run: `git diff --check`

Expected: no output.

## Task 3: Update Status Content Data

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`

- [ ] **Step 1: Add English strings**

In `SunSmart/en.lproj/Localizable.strings`, add near the FireAlarm strings:

```text
"emergency_event_ends" = "Emergency event ends";
"restore_auto" = "Auto";
"restore_none" = "None";
"set_brightness_to_value" = "Set Brightness to %@";
```

- [ ] **Step 2: Replace statusItems output**

In `EmerFireAlarmMonitorState.swift`, replace `statusItems(for:)` with:

```swift
static func statusItems(for config: LinkedEmerFireConfig) -> [EmerFireAlarmStatusSetView.ItemViewModel] {
    let powerLossSettings = config.configuration.powerLossSettings
    let fireAlarmSettings = config.configuration.fireAlarmSettings
    let restoreSettings = config.configuration.restoreSettings
    return [
        .init(
            kind: .fireTrigger,
            title: "fire_alarm_occurs".localizedString,
            details: [
                .init(
                    subtitle: "set_brightness_to".localizedString,
                    value: "\(fireAlarmSettings.triggerBrightness)%"
                )
            ]
        ),
        .init(
            kind: .powerLossTrigger,
            title: "power_supply_fails".localizedString,
            details: [
                .init(
                    subtitle: "set_brightness_to".localizedString,
                    value: "\(powerLossSettings.triggerBrightness)%"
                )
            ]
        ),
        .init(
            kind: .fireStop,
            title: "emergency_event_ends".localizedString,
            details: [
                .init(
                    subtitle: "action".localizedString,
                    value: restoreActionTitle(for: restoreSettings)
                ),
                .init(
                    subtitle: "resuming_in".localizedString,
                    value: "\(restoreSettings.resumingSeconds)s"
                )
            ]
        )
    ]
}
```

- [ ] **Step 3: Add restore action title helper**

Add this helper inside `EmerFireAlarmMonitorStateMapper`:

```swift
private static func restoreActionTitle(for settings: EmergencyFireControllerRestoreSettings) -> String {
    switch settings.actionType {
    case .restoreAuto:
        return "restore_auto".localizedString
    case .setBrightness:
        return String(
            format: "set_brightness_to_value".localizedString,
            "\(settings.brightness)%"
        )
    case .none:
        return "restore_none".localizedString
    }
}
```

- [ ] **Step 4: Run the content-list contract**

Run: `bash scripts/check_efc_status_content_list.sh`

Expected: `EFC status content list contracts passed.`

- [ ] **Step 5: Commit model and cell implementation**

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusItemCell.swift SunSmart/en.lproj/Localizable.strings
git commit -m "fix: update EFC status content list"
```

## Task 4: Full Verification

**Files:**
- Read: `scripts/check_efc_controller_flows.sh`
- Read: `scripts/check_efc_status_content_list.sh`

- [ ] **Step 1: Run existing EFC flow contract**

Run: `bash scripts/check_efc_controller_flows.sh`

Expected: `EFC controller flow contracts passed.`

- [ ] **Step 2: Run new content list contract**

Run: `bash scripts/check_efc_status_content_list.sh`

Expected: `EFC status content list contracts passed.`

- [ ] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Check final diff hygiene**

Run: `git status --short`

Expected: clean worktree after commits.

Run: `git diff --check HEAD~2..HEAD`

Expected: no output.

## Self-Review

- Spec coverage: Task 1 locks the 3 target rows and removed rows; Task 2 implements multi detail/value rendering; Task 3 maps fire, power loss, and emergency event end data; Task 4 verifies contracts and iPhoneOS build.
- Placeholder scan: no `TBD`, `TODO`, deferred implementation, or unspecified validation steps remain.
- Type consistency: `DetailViewModel`, `details`, `restoreActionTitle(for:)`, and localization keys are defined before use and match across tasks.
