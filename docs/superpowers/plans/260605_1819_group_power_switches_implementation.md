# Group Power Switches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 Site - Space - Group 右上角 `Switch` 入口，按 Kinetic / Battery Power / AC Power 三类展示和编辑当前 group 的 switch。

**Architecture:** 保留现有 Kinetic `GroupSwitchsViewController`，新增 Group-scoped `GroupPowerSwitchesViewController` 承载 Battery/AC Power Switch 列表、展开编辑、Enable、SAVE、Delete 和 Add Virtual。底层复用 `PJEightKeySwitchData`、`PJEightKeySwitchRepository`、8-key panel/more settings/scene controllers、activation flow 与 `SyncDevicesViewController(type: .batteryPowerSwitch)`。

**Tech Stack:** UIKit、Swift、SnapKit、NordicSigMeshSDK、SQLite 持久化、现有 `MeshNetworkManager` switch cache、Xcode project 多 target source membership。

**Execution Preference:** 本项目 AGENTS.md 指定完成计划后默认使用 `2. Inline Execution`，后续执行时使用 `superpowers:executing-plans`，不默认使用 subagents。

---

## File Structure

- Modify `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `pushToSwitch()` 改为展示 `PJSwitchesTypesVC`，按类型 push 对应页面。

- Modify `SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift`
  - 标题改为 `Kinetic Switch`。
  - `copySwitchs` 过滤为当前 group 下普通 Kinetic switch。
  - 底部按钮文案改为新 key `add_virtual_switch`。

- Create `SunSmart/Main/Group/Switch/Model/GroupPowerSwitchesViewModel.swift`
  - Battery/AC Group 页面状态、过滤、snapshot、虚拟 switch 创建、持久化、同步前状态准备。

- Create `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`
  - 折叠/展开 cell UI，内含 header、toggle、Panel/Group/Scene/More Settings rows、panel preview、Delete/Save buttons。

- Create `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
  - 页面容器、table view、add virtual、expand/collapse、row actions、enable/save/delete/sync flows。

- Modify `SunSmart/en.lproj/Localizable.strings`
  - 增加 `add_virtual_switch` 和 `not_linked_to_switch`。

- Modify `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加 `add_virtual_switch` 和 `not_linked_to_switch`。

- Modify `SunSmart.xcodeproj/project.pbxproj`
  - 把 3 个新增 Swift 文件加入与 `GroupSwitchsViewController.swift` / `PJEightKeySwitchMonitorVC.swift` 相同的四个 app target Sources。

---

### Task 1: Localized Text And Kinetic Page Scoping

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift`

- [ ] **Step 1: Add localized strings**

Add to `SunSmart/en.lproj/Localizable.strings` near existing switch keys:

```text
"add_virtual_switch" = "ADD VIRTUAL SWITCH";
"not_linked_to_switch" = "Not linked to switch";
```

Add to `SunSmart/zh-Hans.lproj/Localizable.strings` near existing switch keys:

```text
"add_virtual_switch" = "添加虚拟开关";
"not_linked_to_switch" = "未关联开关";
```

- [ ] **Step 2: Add Kinetic filtering helper**

In `GroupSwitchsViewController`, add this helper inside the class:

```swift
private func kineticSwitches(in group: Group) -> [DeviceSwitchData] {
    group.info.switchs.filter { switchData in
        guard switchData.bindGroupAddresses.contains(group.address.address) else {
            return false
        }
        if switchData is PJEightKeySwitchData {
            return false
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: switchData) == nil
    }
}
```

- [ ] **Step 3: Scope initial Kinetic data**

Replace this line in `viewDidLoad()`:

```swift
self.title = "switch".localizedString
```

with:

```swift
self.title = "kinetic_switch".localizedString
```

Replace this line in `viewDidLoad()`:

```swift
copySwitchs = group.info.switchs.map({ $0.copy() })
```

with:

```swift
copySwitchs = kineticSwitches(in: group).map { $0.copy() }
```

- [ ] **Step 4: Update bottom button title**

Replace in `setupUI()`:

```swift
addSwitchBtn = UIButton(title: "add_switch".localizedString, titleSize: 15, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(addSwitchBtnAction))
```

with:

```swift
addSwitchBtn = UIButton(title: "add_virtual_switch".localizedString, titleSize: 15, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(addSwitchBtnAction))
```

- [ ] **Step 5: Run static search**

Run:

```bash
rg -n "add_virtual_switch|not_linked_to_switch|kineticSwitches" SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: all three keys/helper references are present.

- [ ] **Step 6: Commit**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift
git commit -m "feat: scope group kinetic switches"
```

---

### Task 2: Group Switch Type Popup Navigation

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
- Depends on later class name: `GroupPowerSwitchesViewController`

- [ ] **Step 1: Replace `pushToSwitch()` implementation**

Replace current method:

```swift
@objc private func pushToSwitch() {
    
    let vc = GroupSwitchsViewController(group: group)
    vc.editable = space.groupOperates.contains(.edit)
    navigationController?.pushViewController(vc, animated: true)
}
```

with:

```swift
@objc private func pushToSwitch() {
    let controller = PJSwitchesTypesVC.makePopupViewController(
        onBack: nil,
        onKineticSwitch: { [weak self] in
            guard let self else { return }
            let vc = GroupSwitchsViewController(group: self.group)
            vc.editable = self.space.groupOperates.contains(.edit)
            self.navigationController?.pushViewController(vc, animated: true)
        },
        onBatterySwitch: { [weak self] in
            guard let self else { return }
            let vc = GroupPowerSwitchesViewController(group: self.group, kind: .battery, editable: self.space.groupOperates.contains(.edit))
            self.navigationController?.pushViewController(vc, animated: true)
        },
        onACSwitch: { [weak self] in
            guard let self else { return }
            let vc = GroupPowerSwitchesViewController(group: self.group, kind: .ac, editable: self.space.groupOperates.contains(.edit))
            self.navigationController?.pushViewController(vc, animated: true)
        }
    )
    present(controller, animated: false)
}
```

- [ ] **Step 2: Delay compile until controller exists**

Do not run full build after this task alone because `GroupPowerSwitchesViewController` is created in Task 5. Run this syntax-oriented search instead:

```bash
rg -n "GroupPowerSwitchesViewController|PJSwitchesTypesVC.makePopupViewController" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: three `GroupPowerSwitchesViewController` references and one popup factory reference.

- [ ] **Step 3: Commit**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: route group switch type selection"
```

---

### Task 3: Group Power Switch View Model

**Files:**
- Create: `SunSmart/Main/Group/Switch/Model/GroupPowerSwitchesViewModel.swift`

- [ ] **Step 1: Create view model file**

Create `GroupPowerSwitchesViewModel.swift` with:

```swift
//
//  GroupPowerSwitchesViewModel.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

struct GroupPowerSwitchesViewModel {

    struct Snapshot: Equatable {
        let panelType: PJEightKeySwitchPanelDefinition.PanelType
        let sceneNumbers: [SceneNumber?]
        let periodicReporting: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption
        let ledIndicatorEnabled: Bool
    }

    let group: Group
    let kind: PJEightKeyPowerSwitchKind

    var title: String {
        switch kind {
        case .battery:
            return "neightkeyswitches_battery_power_switch".localizedString.replacingOccurrences(of: "\n", with: " ")
        case .ac:
            return "neightkeyswitches_ac_power_switch".localizedString.replacingOccurrences(of: "\n", with: " ")
        }
    }

    var switches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs.compactMap { switchData in
            let eightKeySwitch: PJEightKeySwitchData?
            if let data = switchData as? PJEightKeySwitchData {
                eightKeySwitch = data
            } else {
                eightKeySwitch = PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: switchData)
            }
            guard let eightKeySwitch else {
                return nil
            }
            guard eightKeySwitch.powerSwitchKind == kind else {
                return nil
            }
            guard eightKeySwitch.bindGroupAddresses.contains(group.address.address) else {
                return nil
            }
            return eightKeySwitch
        }
    }

    func snapshot(for switchData: PJEightKeySwitchData) -> Snapshot {
        Snapshot(
            panelType: switchData.eightKeyPanelType,
            sceneNumbers: [
                switchData.sceneANumber,
                switchData.sceneBNumber,
                switchData.sceneCNumber,
                switchData.sceneDNumber
            ],
            periodicReporting: switchData.moreSettingsState.periodicReporting,
            ledIndicatorEnabled: switchData.moreSettingsState.ledIndicatorEnabled
        )
    }

    func groupSubtitle(for switchData: PJEightKeySwitchData) -> String {
        let names = switchData.bindGroups.map(\.name)
        return names.isEmpty ? "N/A" : names.joined(separator: ", ")
    }

    func sceneSubtitle(for switchData: PJEightKeySwitchData) -> String {
        guard switchData.eightKeyPanelType == .scene8Key else {
            return "N/A"
        }
        let names = [switchData.sceneA, switchData.sceneB, switchData.sceneC, switchData.sceneD].compactMap { $0?.name }
        return names.isEmpty ? "N/A" : names.joined(separator: ", ")
    }

    func detailText(for switchData: PJEightKeySwitchData) -> String {
        guard switchData.proxyNode?.isPowerSwitch == true else {
            return "not_linked_to_switch".localizedString
        }
        if let mac = switchData.proxyNode?.mac, !mac.isEmpty {
            return "MAC: \(mac)"
        }
        if let mac = switchData.enOceanMacAddress, !mac.isEmpty {
            return "MAC: \(mac)"
        }
        return "not_linked_to_switch".localizedString
    }

    func hasRealPowerSwitchLink(_ switchData: PJEightKeySwitchData) -> Bool {
        switchData.proxyNode?.isPowerSwitch == true
    }

    func hasSaveChanges(current: PJEightKeySwitchData, initial: Snapshot) -> Bool {
        snapshot(for: current) != initial
    }

    func makeSceneDatas(for switchData: PJEightKeySwitchData) -> [SwitchSceneData] {
        [
            .init(type: .sceneA, scene: switchData.sceneA),
            .init(type: .sceneB, scene: switchData.sceneB),
            .init(type: .sceneC, scene: switchData.sceneC),
            .init(type: .sceneD, scene: switchData.sceneD)
        ]
    }

    func apply(sceneDatas: [SwitchSceneData], to switchData: PJEightKeySwitchData) {
        sceneDatas.forEach { data in
            switch data.type {
            case .sceneA:
                switchData.sceneANumber = data.scene?.number
            case .sceneB:
                switchData.sceneBNumber = data.scene?.number
            case .sceneC:
                switchData.sceneCNumber = data.scene?.number
            case .sceneD:
                switchData.sceneDNumber = data.scene?.number
            }
        }
    }

    func persist(_ switchData: PJEightKeySwitchData) -> Bool {
        guard switchData.save(),
              PJEightKeySwitchRepository.shared.save(switchData) else {
            return false
        }
        if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
            MeshNetworkManager.instance.switchs[index] = switchData
        } else {
            MeshNetworkManager.instance.switchs.append(switchData)
        }
        return true
    }

    func makeVirtualSwitch() -> PJEightKeySwitchData? {
        guard MeshNetworkManager.instance.switchs.count < 16 else {
            return nil
        }
        let switchData = PJEightKeySwitchData(
            id: UUID().uuidString,
            enabled: true,
            name: MeshNetworkManager.instance.getNextSwitchName(),
            linkGroupAddress: nil,
            subLinkGroupAddress: nil,
            bindGroupAddresses: [group.address.address],
            sceneANumber: nil,
            sceneBNumber: nil,
            sceneCNumber: nil,
            sceneDNumber: nil,
            proxyNodeAddress: nil
        )
        switchData.maxKeyCount = 8
        switchData.panelType = .scenes_4key
        switchData.eightKeyPanelType = .scene8Key
        switchData.powerSwitchKind = kind
        switchData.moreSettingsState = .default
        switchData.syncState = .synced
        switchData.desiredConfigVersion = 0
        switchData.desiredConfigHash = ""
        switchData.appliedConfigHash = ""
        switchData.lastSyncFailedReason = nil
        switchData.lastSyncedAt = nil
        switchData.appliedTxEnabled = nil
        switchData.appliedLEDIndicatorEnabled = nil
        return switchData
    }

    func prepareDesiredConfigurationIfNeeded(_ switchData: PJEightKeySwitchData) -> Bool {
        guard switchData.proxyNode?.isPowerSwitch == true else {
            return true
        }
        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            return false
        }
        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        if switchData.needsBatteryPowerSwitchConfigurationSync {
            switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        }
        return true
    }
}
```

- [ ] **Step 2: Validate no accidental global deletes**

Run:

```bash
rg -n "deleteSwitch|delete\\(" SunSmart/Main/Group/Switch/Model/GroupPowerSwitchesViewModel.swift
```

Expected: no matches.

- [ ] **Step 3: Commit**

```bash
git add SunSmart/Main/Group/Switch/Model/GroupPowerSwitchesViewModel.swift
git commit -m "feat: add group power switch view model"
```

---

### Task 4: Group Power Switch Cell

**Files:**
- Create: `SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift`

- [ ] **Step 1: Create cell file**

Create `GroupPowerSwitchCell.swift` with:

```swift
//
//  GroupPowerSwitchCell.swift
//  SunSmart
//

import UIKit

final class GroupPowerSwitchCell: UITableViewCell {

    struct State {
        let name: String
        let detail: String
        let isEnabled: Bool
        let isExpanded: Bool
        let isPending: Bool
        let panelTitle: String
        let groupTitle: String
        let sceneTitle: String
        let showsSceneRow: Bool
        let panelDefinition: PJEightKeySwitchPanelDefinition
        let canSave: Bool
        let editable: Bool
    }

    var expandAction: (() -> Void)?
    var enableChanged: ((Bool) -> Void)?
    var panelAction: (() -> Void)?
    var groupAction: (() -> Void)?
    var sceneAction: (() -> Void)?
    var moreSettingsAction: (() -> Void)?
    var deleteAction: (() -> Void)?
    var saveAction: (() -> Void)?

    private let headerButton = UIControl()
    private let nameLabel = UILabel(text: nil, textColor: Title_Color, fontSize: 14)
    private let detailLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
    private let enableSwitch = UISwitch()
    private let arrowImageView = UIImageView(image: UIImage(named: "arrow_right"))
    private let stackView = UIStackView()
    private let panelRowView = PJEightKeySwitchInfoRowView(title: "panel".localizedString, accessory: .valueWithArrow)
    private let groupRowView = PJEightKeySwitchInfoRowView(title: "group".localizedString, accessory: .valueWithArrow)
    private let sceneRowView = PJEightKeySwitchInfoRowView(title: "scene".localizedString, accessory: .valueWithArrow)
    private let moreSettingsRowView = PJEightKeySwitchInfoRowView(title: "neightkeyswitches_more_settings".localizedString, accessory: .arrow)
    private let panelPreviewView = PJEightKeySwitchPanelView()
    private let actionRowView = UIView()
    private let deleteButton = UIButton(type: .custom)
    private let saveButton = UIButton(type: .custom)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        expandAction = nil
        enableChanged = nil
        panelAction = nil
        groupAction = nil
        sceneAction = nil
        moreSettingsAction = nil
        deleteAction = nil
        saveAction = nil
    }

    func configure(state: State) {
        nameLabel.text = state.name
        detailLabel.text = state.detail
        enableSwitch.isOn = state.isEnabled
        enableSwitch.isEnabled = state.editable && !state.isPending
        arrowImageView.transform = state.isExpanded ? CGAffineTransform(rotationAngle: -.pi / 2) : CGAffineTransform(rotationAngle: .pi / 2)

        stackView.isHidden = !state.isExpanded
        panelRowView.setValue(state.panelTitle)
        groupRowView.setValue(state.groupTitle)
        sceneRowView.setValue(state.sceneTitle)
        sceneRowView.isHidden = !state.showsSceneRow
        panelPreviewView.configure(definition: state.panelDefinition, mode: .preview)

        [panelRowView, groupRowView, sceneRowView, moreSettingsRowView].forEach {
            $0.isUserInteractionEnabled = state.editable
        }
        deleteButton.isEnabled = state.editable && !state.isPending
        saveButton.isEnabled = state.editable && state.canSave && !state.isPending
        saveButton.alpha = saveButton.isEnabled ? 1 : 0.35
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = Background_Color

        headerButton.backgroundColor = .white
        headerButton.addTarget(self, action: #selector(expandTapped), for: .touchUpInside)
        contentView.addSubview(headerButton)
        headerButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(64))
        }

        nameLabel.lineBreakMode = .byTruncatingTail
        headerButton.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.lessThanOrEqualTo(enableSwitch.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(SCRYFrom(12))
        }

        detailLabel.lineBreakMode = .byTruncatingTail
        headerButton.addSubview(detailLabel)
        detailLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.right.lessThanOrEqualTo(enableSwitch.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(6))
        }

        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableTapped), for: .valueChanged)
        headerButton.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-54))
            make.centerY.equalToSuperview()
        }

        arrowImageView.contentMode = .scaleAspectFit
        headerButton.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(30))
        }

        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.backgroundColor = Background_Color
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.top.equalTo(headerButton.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }

        [panelRowView, groupRowView, sceneRowView, moreSettingsRowView].forEach { row in
            row.backgroundColor = .white
            stackView.addArrangedSubview(row)
            row.snp.makeConstraints { make in
                make.height.equalTo(SCRYFrom(44))
            }
        }

        panelPreviewView.backgroundColor = .clear
        stackView.addArrangedSubview(panelPreviewView)
        panelPreviewView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(320))
        }

        actionRowView.backgroundColor = Background_Color
        stackView.addArrangedSubview(actionRowView)
        actionRowView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(72))
        }

        deleteButton.setImage(UIImage(named: "delete_3"), for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        actionRowView.addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(56))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(40))
        }

        saveButton.setImage(UIImage(named: "save"), for: .normal)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        actionRowView.addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-56))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(40))
        }

        panelRowView.tapAction = { [weak self] in self?.panelAction?() }
        groupRowView.tapAction = { [weak self] in self?.groupAction?() }
        sceneRowView.tapAction = { [weak self] in self?.sceneAction?() }
        moreSettingsRowView.tapAction = { [weak self] in self?.moreSettingsAction?() }
    }

    @objc private func expandTapped() {
        expandAction?()
    }

    @objc private func enableTapped() {
        enableChanged?(enableSwitch.isOn)
    }

    @objc private func deleteTapped() {
        deleteAction?()
    }

    @objc private func saveTapped() {
        saveAction?()
    }
}
```

- [ ] **Step 2: Verify asset names**

Run:

```bash
rg -n "\"save\"|\"delete_3\"" SunSmart -g '*.swift' -g '*.xcassets'
```

Expected: either image names exist in assets or existing image names differ. If they differ, update the two `setImage` calls to the existing asset names before continuing.

- [ ] **Step 3: Commit**

```bash
git add SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift
git commit -m "feat: add group power switch cell"
```

---

### Task 5: Group Power Switches Controller Base

**Files:**
- Create: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: Create controller shell with table and add button**

Create `GroupPowerSwitchesViewController.swift` with:

```swift
//
//  GroupPowerSwitchesViewController.swift
//  SunSmart
//

import UIKit
import NordicSigMeshSDK

final class GroupPowerSwitchesViewController: UIViewController {

    private var viewModel: GroupPowerSwitchesViewModel
    private let editable: Bool
    private var expandedSwitchIds: Set<String> = []
    private var editingSwitches: [String: PJEightKeySwitchData] = [:]
    private var initialSnapshots: [String: GroupPowerSwitchesViewModel.Snapshot] = [:]
    private var pendingSwitchIds: Set<String> = []
    private var activationFlow: PJEightKeySwitchActivationFlow?
    private var txEnableFlow: PJEightKeySwitchTxEnableFlow?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let bottomView = UIView()
    private let addButton = UIButton(type: .custom)

    init(group: Group, kind: PJEightKeyPowerSwitchKind, editable: Bool) {
        self.viewModel = GroupPowerSwitchesViewModel(group: group, kind: kind)
        self.editable = editable
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        setupUI()
        addNotificationObserver()
        updateEmptyUI()
    }

    deinit {
        txEnableFlow?.cancel()
        activationFlow = nil
    }

    private var switches: [PJEightKeySwitchData] {
        viewModel.switches
    }

    private func setupUI() {
        bottomView.backgroundColor = .white
        bottomView.isHidden = !editable
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }

        addButton.setTitle("add_virtual_switch".localizedString, for: .normal)
        addButton.setTitleColor(Title_Color, for: .normal)
        addButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        addButton.addTarget(self, action: #selector(addVirtualSwitchAction), for: .touchUpInside)
        bottomView.addSubview(addButton)
        addButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }

        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = SCRYFrom(64)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(GroupPowerSwitchCell.self, forCellReuseIdentifier: "powerSwitch")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(editable ? bottomView.snp.top : view.snp.bottom)
        }
    }

    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(switchsRefreshNotificationName), object: nil, queue: .main) { [weak self] _ in
            self?.tableView.reloadData()
            self?.updateEmptyUI()
        }
    }

    private func updateEmptyUI() {
        if switches.isEmpty {
            if tableView.frame.isEmpty {
                view.layoutIfNeeded()
            }
            tableView.showEmptyDataView(title: "no_switches".localizedString, tipText: "no_switches_message".localizedString, position: .center, bottomMargin: SCRYFit(100))
            tableView.emptyView?.backgroundColor = .clear
        } else {
            tableView.hideEmptyDataView()
        }
    }

    @objc private func addVirtualSwitchAction() {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = viewModel.makeVirtualSwitch() else {
            SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
            return
        }
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        expandedSwitchIds.insert(switchData.id)
        editingSwitches[switchData.id] = switchData.copy()
        initialSnapshots[switchData.id] = viewModel.snapshot(for: switchData)
        postSwitchChangedNotifications()
        tableView.reloadData()
        scrollToSwitch(id: switchData.id)
        updateEmptyUI()
    }

    private func postSwitchChangedNotifications() {
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
    }

    private func scrollToSwitch(id: String) {
        guard let index = switches.firstIndex(where: { $0.id == id }) else {
            return
        }
        tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .top, animated: true)
    }
}
```

- [ ] **Step 2: Add table data source and delegate**

Append to the same file:

```swift
extension GroupPowerSwitchesViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switches.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sourceSwitch = switches[indexPath.row]
        let switchData = editableSwitch(for: sourceSwitch)
        let cell = tableView.dequeueReusableCell(withIdentifier: "powerSwitch", for: indexPath) as! GroupPowerSwitchCell
        configure(cell, with: switchData)
        return cell
    }

    private func editableSwitch(for sourceSwitch: PJEightKeySwitchData) -> PJEightKeySwitchData {
        if let editingSwitch = editingSwitches[sourceSwitch.id] {
            return editingSwitch
        }
        let copy = sourceSwitch.copy()
        editingSwitches[sourceSwitch.id] = copy
        initialSnapshots[sourceSwitch.id] = viewModel.snapshot(for: sourceSwitch)
        return copy
    }

    private func configure(_ cell: GroupPowerSwitchCell, with switchData: PJEightKeySwitchData) {
        let initialSnapshot = initialSnapshots[switchData.id] ?? viewModel.snapshot(for: switchData)
        let state = GroupPowerSwitchCell.State(
            name: switchData.name,
            detail: viewModel.detailText(for: switchData),
            isEnabled: switchData.enabled,
            isExpanded: expandedSwitchIds.contains(switchData.id),
            isPending: pendingSwitchIds.contains(switchData.id),
            panelTitle: switchData.eightKeyPanelType.title,
            groupTitle: viewModel.groupSubtitle(for: switchData),
            sceneTitle: viewModel.sceneSubtitle(for: switchData),
            showsSceneRow: switchData.eightKeyPanelType == .scene8Key,
            panelDefinition: PJEightKeySwitchPanelDefinition.make(type: switchData.eightKeyPanelType),
            canSave: viewModel.hasSaveChanges(current: switchData, initial: initialSnapshot),
            editable: editable
        )
        cell.configure(state: state)
        cell.expandAction = { [weak self] in
            self?.toggleExpanded(switchId: switchData.id)
        }
        cell.enableChanged = { [weak self] isOn in
            self?.updateEnabled(isOn, for: switchData.id)
        }
        cell.panelAction = { [weak self] in
            self?.selectPanel(for: switchData.id)
        }
        cell.groupAction = { [weak self] in
            self?.showReadonlyGroups(for: switchData.id)
        }
        cell.sceneAction = { [weak self] in
            self?.selectScenes(for: switchData.id)
        }
        cell.moreSettingsAction = { [weak self] in
            self?.showMoreSettings(for: switchData.id)
        }
        cell.deleteAction = { [weak self] in
            self?.deleteGroupTarget(for: switchData.id)
        }
        cell.saveAction = { [weak self] in
            self?.saveSwitchChanges(for: switchData.id)
        }
    }

    private func toggleExpanded(switchId: String) {
        if expandedSwitchIds.contains(switchId) {
            expandedSwitchIds.remove(switchId)
        } else {
            expandedSwitchIds.insert(switchId)
        }
        reloadSwitch(id: switchId)
    }

    private func reloadSwitch(id: String) {
        guard let index = switches.firstIndex(where: { $0.id == id }) else {
            tableView.reloadData()
            return
        }
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
    }

    private func currentEditingSwitch(id: String) -> PJEightKeySwitchData? {
        if let editingSwitch = editingSwitches[id] {
            return editingSwitch
        }
        guard let sourceSwitch = switches.first(where: { $0.id == id }) else {
            return nil
        }
        return editableSwitch(for: sourceSwitch)
    }
}
```

- [ ] **Step 3: Add row action methods that do not sync yet**

Append these methods inside `GroupPowerSwitchesViewController`; Task 6 will fill enable/save/delete sync bodies.

```swift
private func ensureEditable() -> Bool {
    guard editable else {
        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
        return false
    }
    return true
}

private func selectPanel(for switchId: String) {
    guard ensureEditable(), let switchData = currentEditingSwitch(id: switchId) else { return }
    let vc = PJEightKeySwitchSelectPanelController(selectedPanelType: switchData.eightKeyPanelType)
    vc.selectPanelTypeCallback = { [weak self, weak switchData] type in
        guard let self, let switchData else { return }
        switchData.eightKeyPanelType = type
        switchData.panelType = type == .scene8Key ? .scenes_4key : .default_4key
        if type == .brightness8Key {
            switchData.sceneANumber = nil
            switchData.sceneBNumber = nil
            switchData.sceneCNumber = nil
            switchData.sceneDNumber = nil
        }
        self.reloadSwitch(id: switchId)
    }
    navigationController?.pushViewController(vc, animated: true)
}

private func showReadonlyGroups(for switchId: String) {
    guard let switchData = currentEditingSwitch(id: switchId) else { return }
    let vc = SwitchSelectGroupsViewController(groups: switchData.bindGroups, selectGroups: switchData.bindGroups)
    vc.editable = false
    navigationController?.pushViewController(vc, animated: true)
}

private func selectScenes(for switchId: String) {
    guard ensureEditable(), let switchData = currentEditingSwitch(id: switchId) else { return }
    guard switchData.eightKeyPanelType == .scene8Key else { return }
    let scenes = MeshNetworkManager.instance.scenes.filter { !DeviceEmerFireData.reservedSceneNumbers.contains($0.number) }
    let vc = SwitchSelectScenePageController(scenes: scenes, sceneDatas: viewModel.makeSceneDatas(for: switchData))
    vc.scenesSelectCallback = { [weak self, weak switchData] sceneDatas in
        guard let self, let switchData else { return }
        self.viewModel.apply(sceneDatas: sceneDatas, to: switchData)
        self.reloadSwitch(id: switchId)
    }
    navigationController?.pushViewController(vc, animated: true)
}

private func showMoreSettings(for switchId: String) {
    guard ensureEditable(), let switchData = currentEditingSwitch(id: switchId) else { return }
    let vc = PJEightKeySwitchMoreSettingsController(state: switchData.moreSettingsState)
    vc.settingsChanged = { [weak self, weak switchData] state in
        guard let self, let switchData else { return }
        switchData.moreSettingsState = state
        self.reloadSwitch(id: switchId)
    }
    navigationController?.pushViewController(vc, animated: true)
}

private func updateEnabled(_ enabled: Bool, for switchId: String) {
    guard ensureEditable() else {
        reloadSwitch(id: switchId)
        return
    }
}

private func saveSwitchChanges(for switchId: String) {
    guard ensureEditable() else { return }
}

private func deleteGroupTarget(for switchId: String) {
    guard ensureEditable() else { return }
}
```

- [ ] **Step 4: Commit**

```bash
git add SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
git commit -m "feat: add group power switch page"
```

---

### Task 6: Enable, Save, And Delete Flows

**Files:**
- Modify: `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`

- [ ] **Step 1: Add helper methods for source replacement and snapshots**

Add inside `GroupPowerSwitchesViewController`:

```swift
private func sourceSwitch(id: String) -> PJEightKeySwitchData? {
    switches.first(where: { $0.id == id })
}

private func restoreEditingState(from source: PJEightKeySwitchData) {
    editingSwitches[source.id] = source.copy()
    initialSnapshots[source.id] = viewModel.snapshot(for: source)
}

private func applyPersistedState(_ switchData: PJEightKeySwitchData) {
    editingSwitches[switchData.id] = switchData.copy()
    initialSnapshots[switchData.id] = viewModel.snapshot(for: switchData)
    postSwitchChangedNotifications()
    tableView.reloadData()
    updateEmptyUI()
}

private func setPending(_ isPending: Bool, switchId: String) {
    if isPending {
        pendingSwitchIds.insert(switchId)
    } else {
        pendingSwitchIds.remove(switchId)
    }
    reloadSwitch(id: switchId)
}
```

- [ ] **Step 2: Replace `updateEnabled` body**

Replace the stub `updateEnabled(_:for:)` with:

```swift
private func updateEnabled(_ enabled: Bool, for switchId: String) {
    guard ensureEditable(),
          pendingSwitchIds.contains(switchId) == false,
          let source = sourceSwitch(id: switchId) else {
        reloadSwitch(id: switchId)
        return
    }

    let switchData = source.copy()
    switchData.enabled = enabled

    guard viewModel.hasRealPowerSwitchLink(switchData) else {
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            reloadSwitch(id: switchId)
            return
        }
        applyPersistedState(switchData)
        return
    }

    setPending(true, switchId: switchId)
    if switchData.powerSwitchKind == .ac {
        sendACTxEnable(switchData)
    } else {
        sendBatteryTxEnableWithActivation(switchData)
    }
}
```

- [ ] **Step 3: Add TX Enable senders**

Add:

```swift
private func sendBatteryTxEnableWithActivation(_ switchData: PJEightKeySwitchData) {
    let flow = PJEightKeySwitchTxEnableFlow(
        presenter: self,
        switchData: switchData,
        enabled: switchData.enabled,
        onSucceeded: { [weak self, weak switchData] _ in
            guard let self, let switchData else { return }
            switchData.markBatteryPowerSwitchTxEnableSucceeded()
            if self.viewModel.persist(switchData) {
                self.applyPersistedState(switchData)
            } else {
                XWHUDManager.showErrorTipHUD("failed".localizedString)
            }
        },
        onFinished: { [weak self, weak switchData] in
            guard let self else { return }
            self.txEnableFlow = nil
            self.setPending(false, switchId: switchData?.id ?? "")
            if let switchData, let source = self.sourceSwitch(id: switchData.id) {
                self.restoreEditingState(from: source)
            }
        }
    )
    txEnableFlow = flow
    flow.start()
}

private func sendACTxEnable(_ switchData: PJEightKeySwitchData) {
    guard let node = switchData.proxyNode else {
        setPending(false, switchId: switchData.id)
        XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
        return
    }
    MeshBatteryPowerSwitchTxEnableSender().sendTxEnable(switchData.enabled, to: node) { [weak self, weak switchData] succeeded in
        DispatchQueue.main.async {
            guard let self, let switchData else { return }
            if succeeded {
                switchData.markBatteryPowerSwitchTxEnableSucceeded()
                if self.viewModel.persist(switchData) {
                    self.applyPersistedState(switchData)
                } else {
                    XWHUDManager.showErrorTipHUD("failed".localizedString)
                }
            } else {
                XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            }
            self.setPending(false, switchId: switchData.id)
            if let source = self.sourceSwitch(id: switchData.id) {
                self.restoreEditingState(from: source)
            }
        }
    }
}
```

- [ ] **Step 4: Replace `saveSwitchChanges` body**

Replace stub with:

```swift
private func saveSwitchChanges(for switchId: String) {
    guard ensureEditable(),
          pendingSwitchIds.contains(switchId) == false,
          let switchData = currentEditingSwitch(id: switchId),
          let initialSnapshot = initialSnapshots[switchId],
          viewModel.hasSaveChanges(current: switchData, initial: initialSnapshot) else {
        return
    }
    guard viewModel.prepareDesiredConfigurationIfNeeded(switchData) else {
        XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
        return
    }
    guard viewModel.hasRealPowerSwitchLink(switchData) else {
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        applyPersistedState(switchData)
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        return
    }
    guard switchData.needsBatteryPowerSwitchSync else {
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        applyPersistedState(switchData)
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        return
    }
    setPending(true, switchId: switchId)
    if switchData.requiresActivationBeforeOwnConfiguration {
        presentActivationThenSync(switchData)
    } else {
        pushPowerSwitchSync(switchData)
    }
}
```

- [ ] **Step 5: Add SAVE sync helpers**

Add:

```swift
private func presentActivationThenSync(_ switchData: PJEightKeySwitchData) {
    let flow = PJEightKeySwitchActivationFlow(
        presenter: self,
        switchData: switchData
    ) { [weak self, weak switchData] in
        guard let self, let switchData else { return }
        self.activationFlow = nil
        self.pushPowerSwitchSync(switchData)
    }
    activationFlow = flow
    flow.start()
}

private func pushPowerSwitchSync(_ switchData: PJEightKeySwitchData) {
    let vc = SyncDevicesViewController(type: .batteryPowerSwitch(switchData))
    vc.syncSuccessCallback = { [weak self, weak switchData] _ in
        guard let self, let switchData else { return }
        switchData.markBatteryPowerSwitchSyncSucceeded()
        if self.viewModel.persist(switchData) {
            self.applyPersistedState(switchData)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
        } else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
        self.setPending(false, switchId: switchData.id)
        self.navigationController?.popViewController(animated: true)
    }
    vc.backActionCallback = { [weak self, weak switchData] result in
        guard let self, let switchData else { return }
        let failedOperationTypes = result.flatMap(\.failedOperationTypes)
        let successOperationTypes = result.flatMap(\.successOperationTypes)
        if self.containsPowerSwitchOwnConfiguration(failedOperationTypes) {
            switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
        } else if self.containsPowerSwitchOwnConfiguration(successOperationTypes) {
            switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
        }
        if let source = self.sourceSwitch(id: switchData.id) {
            self.restoreEditingState(from: source)
        }
        self.setPending(false, switchId: switchData.id)
        self.navigationController?.popViewController(animated: true)
    }
    navigationController?.pushViewController(vc, animated: true)
}

private func containsPowerSwitchOwnConfiguration(_ operationTypes: [DeviceOperationType]) -> Bool {
    operationTypes.contains { operationType in
        guard case .configuration(_, let syncData) = operationType else {
            return false
        }
        switch syncData {
        case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 6: Replace `deleteGroupTarget` body**

Replace stub with:

```swift
private func deleteGroupTarget(for switchId: String) {
    guard ensureEditable(),
          pendingSwitchIds.contains(switchId) == false,
          let source = sourceSwitch(id: switchId) else {
        return
    }
    if viewModel.hasRealPowerSwitchLink(source) {
        SRAlertView(
            title: "notification".localizedString,
            message: "switchs_delete_message".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    self?.confirmDeleteGroupTarget(source)
                })
            ]
        ).show()
    } else {
        removeGroupTargetLocally(source)
    }
}
```

- [ ] **Step 7: Add Delete helpers**

Add:

```swift
private func removeGroupTargetLocally(_ source: PJEightKeySwitchData) {
    let switchData = source.copy()
    switchData.bindGroupAddresses.removeAll { $0 == viewModel.group.address.address }
    switchData.unbindGroupAddresses.removeAll { $0 == viewModel.group.address.address }
    guard viewModel.persist(switchData) else {
        XWHUDManager.showErrorTipHUD("failed".localizedString)
        return
    }
    expandedSwitchIds.remove(switchData.id)
    editingSwitches.removeValue(forKey: switchData.id)
    initialSnapshots.removeValue(forKey: switchData.id)
    postSwitchChangedNotifications()
    tableView.reloadData()
    updateEmptyUI()
}

private func confirmDeleteGroupTarget(_ source: PJEightKeySwitchData) {
    let switchData = source.copy()
    switchData.bindGroupAddresses.removeAll { $0 == viewModel.group.address.address }
    if !switchData.unbindGroupAddresses.contains(viewModel.group.address.address) {
        switchData.unbindGroupAddresses.append(viewModel.group.address.address)
    }
    guard viewModel.prepareDesiredConfigurationIfNeeded(switchData) else {
        XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
        return
    }
    setPending(true, switchId: switchData.id)
    if switchData.requiresActivationBeforeOwnConfiguration {
        presentActivationThenSync(switchData)
    } else {
        pushPowerSwitchSync(switchData)
    }
}
```

- [ ] **Step 8: Run static checks for forbidden global delete**

Run:

```bash
rg -n "deleteSwitch\\(|MeshNetworkManager\\.instance\\.deleteSwitch|\\.delete\\(" SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected: no match that deletes the switch record globally. Calls to local helper names are acceptable only if they remove group targets.

- [ ] **Step 9: Commit**

```bash
git add SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
git commit -m "feat: add group power switch flows"
```

---

### Task 7: Add New Files To Xcode Project

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Locate source phases and groups**

Run:

```bash
rg -n "GroupSwitchsViewController.swift|PJEightKeySwitchMonitorVC.swift|GroupPowerSwitchesViewController.swift|GroupPowerSwitchCell.swift|GroupPowerSwitchesViewModel.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected before editing: existing files appear; new files do not.

- [ ] **Step 2: Add PBXFileReference entries**

Use the existing `GroupSwitchsViewController.swift` group under `SunSmart/Main/Group/Switch/Controller`, `GroupSwitchPanelViewCell.swift` group under `SunSmart/Main/Group/Switch/View`, and `GroupSwitch.swift` group under `SunSmart/Main/Group/Switch/Model`.

Add three `PBXFileReference` rows:

```text
C8BE099331EBF36DB4714884 /* GroupPowerSwitchesViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GroupPowerSwitchesViewController.swift; sourceTree = "<group>"; };
C897B311461F95CC1204CFB1 /* GroupPowerSwitchCell.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GroupPowerSwitchCell.swift; sourceTree = "<group>"; };
C8DDDEEA0487D9E098DB078F /* GroupPowerSwitchesViewModel.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GroupPowerSwitchesViewModel.swift; sourceTree = "<group>"; };
```

These IDs were checked as absent before plan creation. Before inserting, verify they are still absent:

```bash
rg "C8BE099331EBF36DB4714884|C897B311461F95CC1204CFB1|C8DDDEEA0487D9E098DB078F|C8FF8A7E146827711D87F57C|C86FD24A1F7497BCD7CBF70C|C8CE7DF01894297033EBC6CF|C826963BB2B36ED1418055DC|C8BE7F69DA4DC8EA37C5763C|C81EB9D84928F87940B7B24C|C8C4BE7222BCF6C13E9CB18F|C85CFF76696BC2EE803E817B|C8F11B20959EC4093FFC9390|C869ED42D86CF9D971A59476|C896FE75CC379E7D64E3CC86|C8DE791ACB736AB07BBC9C56" SunSmart.xcodeproj/project.pbxproj
```

Expected: no matches before insertion.

- [ ] **Step 3: Add file refs to groups**

Insert:

```text
C8BE099331EBF36DB4714884 /* GroupPowerSwitchesViewController.swift */,
```

next to `GroupSwitchsViewController.swift` in the Controller group.

Insert:

```text
C897B311461F95CC1204CFB1 /* GroupPowerSwitchCell.swift */,
```

next to `GroupSwitchPanelViewCell.swift` / `GroupSwitchsHeaderView.swift` in the View group.

Insert:

```text
C8DDDEEA0487D9E098DB078F /* GroupPowerSwitchesViewModel.swift */,
```

next to `GroupSwitch.swift` in the Model group.

- [ ] **Step 4: Add PBXBuildFile rows for all app targets**

Existing shared Swift files are added to four Sources phases. Create four build files per new Swift file:

```text
C8FF8A7E146827711D87F57C /* GroupPowerSwitchesViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8BE099331EBF36DB4714884 /* GroupPowerSwitchesViewController.swift */; };
C86FD24A1F7497BCD7CBF70C /* GroupPowerSwitchesViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8BE099331EBF36DB4714884 /* GroupPowerSwitchesViewController.swift */; };
C8CE7DF01894297033EBC6CF /* GroupPowerSwitchesViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8BE099331EBF36DB4714884 /* GroupPowerSwitchesViewController.swift */; };
C826963BB2B36ED1418055DC /* GroupPowerSwitchesViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8BE099331EBF36DB4714884 /* GroupPowerSwitchesViewController.swift */; };
C8BE7F69DA4DC8EA37C5763C /* GroupPowerSwitchCell.swift in Sources */ = {isa = PBXBuildFile; fileRef = C897B311461F95CC1204CFB1 /* GroupPowerSwitchCell.swift */; };
C81EB9D84928F87940B7B24C /* GroupPowerSwitchCell.swift in Sources */ = {isa = PBXBuildFile; fileRef = C897B311461F95CC1204CFB1 /* GroupPowerSwitchCell.swift */; };
C8C4BE7222BCF6C13E9CB18F /* GroupPowerSwitchCell.swift in Sources */ = {isa = PBXBuildFile; fileRef = C897B311461F95CC1204CFB1 /* GroupPowerSwitchCell.swift */; };
C85CFF76696BC2EE803E817B /* GroupPowerSwitchCell.swift in Sources */ = {isa = PBXBuildFile; fileRef = C897B311461F95CC1204CFB1 /* GroupPowerSwitchCell.swift */; };
C8F11B20959EC4093FFC9390 /* GroupPowerSwitchesViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8DDDEEA0487D9E098DB078F /* GroupPowerSwitchesViewModel.swift */; };
C869ED42D86CF9D971A59476 /* GroupPowerSwitchesViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8DDDEEA0487D9E098DB078F /* GroupPowerSwitchesViewModel.swift */; };
C896FE75CC379E7D64E3CC86 /* GroupPowerSwitchesViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8DDDEEA0487D9E098DB078F /* GroupPowerSwitchesViewModel.swift */; };
C8DE791ACB736AB07BBC9C56 /* GroupPowerSwitchesViewModel.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8DDDEEA0487D9E098DB078F /* GroupPowerSwitchesViewModel.swift */; };
```

- [ ] **Step 5: Add build files to the same four PBXSourcesBuildPhase blocks as `GroupSwitchsViewController.swift`**

Find the four source phase entries that already contain:

```text
GroupSwitchsViewController.swift in Sources
```

Add the three matching new build file IDs to each of those four phase `files = (` lists:

```text
C8FF8A7E146827711D87F57C /* GroupPowerSwitchesViewController.swift in Sources */,
C8BE7F69DA4DC8EA37C5763C /* GroupPowerSwitchCell.swift in Sources */,
C8F11B20959EC4093FFC9390 /* GroupPowerSwitchesViewModel.swift in Sources */,
```

For the second source phase use:

```text
C86FD24A1F7497BCD7CBF70C /* GroupPowerSwitchesViewController.swift in Sources */,
C81EB9D84928F87940B7B24C /* GroupPowerSwitchCell.swift in Sources */,
C869ED42D86CF9D971A59476 /* GroupPowerSwitchesViewModel.swift in Sources */,
```

For the third source phase use:

```text
C8CE7DF01894297033EBC6CF /* GroupPowerSwitchesViewController.swift in Sources */,
C8C4BE7222BCF6C13E9CB18F /* GroupPowerSwitchCell.swift in Sources */,
C896FE75CC379E7D64E3CC86 /* GroupPowerSwitchesViewModel.swift in Sources */,
```

For the fourth source phase use:

```text
C826963BB2B36ED1418055DC /* GroupPowerSwitchesViewController.swift in Sources */,
C85CFF76696BC2EE803E817B /* GroupPowerSwitchCell.swift in Sources */,
C8DE791ACB736AB07BBC9C56 /* GroupPowerSwitchesViewModel.swift in Sources */,
```

- [ ] **Step 6: Verify project references**

Run:

```bash
rg -n "GroupPowerSwitchesViewController.swift|GroupPowerSwitchCell.swift|GroupPowerSwitchesViewModel.swift" SunSmart.xcodeproj/project.pbxproj
```

Expected: each file appears as 1 file reference, 1 group child, 4 build file rows, and 4 source phase entries.

- [ ] **Step 7: Commit**

```bash
git add SunSmart.xcodeproj/project.pbxproj
git commit -m "chore: add group power switch files to project"
```

---

### Task 8: Build Fixes And Verification

**Files:**
- Modify only files touched by compiler errors from Tasks 1-7.

- [ ] **Step 1: Run iPhoneOS build**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Fix compile errors from introduced code**

Only fix errors introduced by this plan. Common expected fixes:

```swift
// If Node.mac does not exist, replace MAC lookup in GroupPowerSwitchesViewModel.detailText with:
if let mac = switchData.enOceanMacAddress, !mac.isEmpty {
    return "MAC: \(mac)"
}
```

```swift
// If save/delete asset names differ, update GroupPowerSwitchCell setupUI to use existing image names from asset search:
deleteButton.setImage(UIImage(named: "<existing delete asset name>"), for: .normal)
saveButton.setImage(UIImage(named: "<existing save asset name>"), for: .normal)
```

Do not change unrelated formatting.

- [ ] **Step 3: Re-run build**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Static behavior checks**

Run:

```bash
rg -n "PJSwitchesTypesVC.makePopupViewController|GroupPowerSwitchesViewController" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected: Group `Switch` entry uses type popup and routes to Battery/AC page.

Run:

```bash
rg -n "MeshNetworkManager\\.instance\\.deleteSwitch|deleteSwitch\\(" SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected: no global switch delete call in Group Power Switch page.

Run:

```bash
rg -n "requiresActivationBeforeOwnConfiguration|PJEightKeySwitchActivationFlow|sendACTxEnable" SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift
```

Expected: Battery path uses activation; AC path uses direct TX enable.

- [ ] **Step 5: Manual QA checklist**

Use a local build or Simulator only for manual UI exploration after iPhoneOS build has passed:

- Group menu `Switch` opens three-type popup.
- `Kinetic Switch` page title is Kinetic Switch and does not show Battery/AC.
- Kinetic `ADD VIRTUAL SWITCH` creates a current-group virtual switch and expands it.
- Battery page shows only current-group Battery Power Switches.
- AC page shows only current-group AC Power Switches.
- Existing Battery/AC rows start collapsed.
- New Battery/AC virtual row expands immediately after add.
- Folded row shows name, MAC or Not linked, toggle, arrow.
- Expanded row does not allow name editing.
- Scene row appears only for Scene Panel and hides for Brightness Panel.
- Group row is read-only.
- SAVE disabled when Panel/Scene/More Settings unchanged.
- Virtual Enable saves locally.
- Battery real Enable/SAVE shows activation alert.
- AC real Enable/SAVE skips activation alert.
- Delete removes current group target but global Switches page still contains the switch.
- 16 total switches blocks Add Virtual.

- [ ] **Step 6: Commit build fixes**

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift SunSmart/Main/Group/Switch/View/GroupPowerSwitchCell.swift SunSmart/Main/Group/Switch/Model/GroupPowerSwitchesViewModel.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: verify group power switch pages"
```

If there are no changes after Step 3, skip this commit.

---

## Self-Review

- Spec coverage:
  - Type popup routing is covered by Task 2.
  - Kinetic filtering/title/button text is covered by Task 1.
  - Battery/AC data filtering, default collapsed state, add-expanded behavior and snapshots are covered by Tasks 3 and 5.
  - Folded/expanded UI is covered by Task 4.
  - Enable, SAVE and Delete flows are covered by Task 6.
  - 16 total switch limit is covered by Task 3 virtual creation and Task 8 manual QA.
  - Localization and shared target impact are covered by Tasks 1 and 7.
  - iPhoneOS build verification is covered by Task 8.

- Placeholder scan:
  - The plan contains no reserved placeholder words or intentionally incomplete sections.
  - Task 7 uses concrete pbxproj IDs and includes a validation command to catch collisions before insertion.

- Type consistency:
  - `GroupPowerSwitchesViewController` initializer used by `GroupViewController` matches Task 5.
  - `GroupPowerSwitchesViewModel.Snapshot` used by the controller matches Task 3.
  - Cell `State` fields used by the controller match Task 4.
  - Enable/SAVE/Delete helpers all use `PJEightKeySwitchData`, not `DeviceSwitchData`, preserving Power Switch metadata.
