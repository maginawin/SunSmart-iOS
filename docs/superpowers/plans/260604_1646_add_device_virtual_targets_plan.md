# Add Device Virtual Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Add Device 页面支持选择未绑定虚拟 Battery/AC Power Switch、Emergency Controller、Dongle 作为添加目标，并在 Classic、Professional、Candidate 列表中统一限制可添加设备、分类切换和批量控件展示。

**Architecture:** 复用现有 Add Device controller 状态，不新增 Xcode target 文件。扩展现有 target selection enum、下拉视图、设备匹配 helper，并在 Classic、Professional、Candidate 三处接入同一套“当前目标是否虚拟设备”的 UI 与过滤规则。LINK 入口继续用 `addBehavior.allowsTargetSelection == false` 保持目标不可切换；普通入口允许切换 Add Device(s) to。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、现有 `ProvisioningDevice` associated properties、现有 `xcodebuild` iPhoneOS 构建校验。

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
  - 扩展 `AddDeviceBindTarget` 的 power switch 匹配逻辑，补 panel/product id 校验。
  - 保持 LINK 入口当前 `addBehavior.allowsTargetSelection == false` 行为。

- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`
  - 给扫描设备补 power switch panel 类型 helper，供 `AddDeviceBindTarget.allows(_:)` 和列表 disabled 判断复用。

- Modify: `SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift`
  - 扩展下拉数据结构，支持 Battery Power Switch、AC Power Switch、Emergency Controller、Dongle 分组。

- Modify: `SunSmart/Main/Device/View/DeviceAddViewCell.swift`
  - 增加控制设备行左侧选择按钮隐藏的属性。

- Modify: `SunSmart/Main/Device/View/DeviceAddBottomView.swift`
  - 增加隐藏底部批量控件的轻量方法，不改变其它使用方默认表现。

- Modify: `SunSmart/Main/Device/View/DeviceAddSelectAllViewCell.swift`
  - 增加隐藏 Professional 主列表 select all cell 内批量控件的方法。

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 接入虚拟目标下拉、目标切换、自动分类、分类锁定、disabled、批量控件隐藏、行选择按钮隐藏。

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 主列表和 Candidate 弹层同步接入虚拟目标策略。

- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 接收当前目标 UI 规则，隐藏虚拟目标批量控件和行选择按钮；Group 目标继续保留批量控件。

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 在 LINK 绑定 helper 层补 panel/product id 校验，避免 LINK 入口绕过规则。

## Task 1: Target Matching Helpers

**Files:**
- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Inspect current power switch matching references**

Run:

```bash
rg -n "powerSwitchKind|isPowerSwitch|panelType\\(|batteryPowerSwitchPanelType|AddDeviceBindTarget|prepareLinkedSwitchData" SunSmart/Main/Device SunSmart/Common -S
```

Expected: output shows `ProvisioningDevice.powerSwitchKind`, `Node.batteryPowerSwitchPanelType`, `AddDeviceBindTarget.allows`, and `BatteryPowerSwitchAddConfiguration.prepareLinkedSwitchData`.

- [ ] **Step 2: Add provisioning-device panel helper**

In `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`, near `var powerSwitchKind`, add:

```swift
    var powerSwitchPanelType: PJEightKeySwitchPanelDefinition.PanelType? {
        return PJEightKeyPowerSwitchKind.panelType(productIdentifier: pid)
    }
```

This mirrors `Node.batteryPowerSwitchPanelType` for unprovisioned scan results.

- [ ] **Step 3: Tighten AddDeviceBindTarget matching**

In `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`, update `AddDeviceBindTarget.allows(_ device:)` for `.batteryPowerSwitch` to:

```swift
        case .batteryPowerSwitch(let switchData):
            return device.powerSwitchKind == switchData.powerSwitchKind &&
                device.powerSwitchPanelType == switchData.eightKeyPanelType
```

Update `AddDeviceBindTarget.allows(_ node:)` for `.batteryPowerSwitch` to:

```swift
        case .batteryPowerSwitch(let switchData):
            return node.powerSwitchKind == switchData.powerSwitchKind &&
                node.batteryPowerSwitchPanelType == switchData.eightKeyPanelType
```

The existing case name remains unchanged even though it also carries AC power switch data; renaming it would create unnecessary churn.

- [ ] **Step 4: Tighten LINK helper validation**

In `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`, update both `prepareLinkedSwitchData(sourceSwitchData:node:)` and `prepareRestoreSwitchData(sourceSwitchData:node:)`.

Replace this guard in each method:

```swift
        guard node.powerSwitchKind == sourceSwitchData.powerSwitchKind else {
            return .failure(.unsupportedNode)
        }
```

with:

```swift
        guard node.powerSwitchKind == sourceSwitchData.powerSwitchKind,
              node.batteryPowerSwitchPanelType == sourceSwitchData.eightKeyPanelType else {
            return .failure(.unsupportedNode)
        }
```

- [ ] **Step 5: Run focused static check**

Run:

```bash
rg -n "powerSwitchPanelType|batteryPowerSwitchPanelType == sourceSwitchData.eightKeyPanelType|device.powerSwitchKind == switchData.powerSwitchKind" SunSmart/Main/Device SunSmart/Common -S
```

Expected: output shows the new provisioning helper, updated bind target matching, and updated linked/restore validation.

- [ ] **Step 6: Commit target matching helpers**

Run:

```bash
git add SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "fix: validate virtual switch add targets"
```

Expected: commit succeeds with only these three files staged.

## Task 2: Target Selection View Supports Virtual Sections

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift`

- [ ] **Step 1: Inspect current selection view structure**

Run:

```bash
sed -n '1,280p' SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift
```

Expected: output shows `DeviceAddTargetSelection`, `Row`, `SectionKind`, `reloadRows()`, and `didSelectRowAt`.

- [ ] **Step 2: Extend selection enum and rows**

In `DeviceAddTargetSelectView.swift`, update `DeviceAddTargetSelection`:

```swift
enum DeviceAddTargetSelection {
    case space
    case group(Group)
    case batteryPowerSwitch(PJEightKeySwitchData)
    case acPowerSwitch(PJEightKeySwitchData)
    case emergencyFire(DeviceEmerFireData)
    case dongle(DeviceDongleData)
}
```

Update private `Row`:

```swift
    private enum Row {
        case space
        case header(SectionKind)
        case group(Group)
        case batteryPowerSwitch(PJEightKeySwitchData)
        case acPowerSwitch(PJEightKeySwitchData)
        case emergencyFire(DeviceEmerFireData)
        case dongle(DeviceDongleData)
    }
```

- [ ] **Step 3: Extend section kinds**

Replace `SectionKind` with:

```swift
    private enum SectionKind: CaseIterable {
        case group
        case batteryPowerSwitch
        case acPowerSwitch
        case emergencyFire
        case dongle

        var title: String {
            switch self {
            case .group:
                return "\("group".localizedString):"
            case .batteryPowerSwitch:
                return "Battery Power Switch:"
            case .acPowerSwitch:
                return "AC Power Switch:"
            case .emergencyFire:
                return "\("Emergency Controller".localizedString):"
            case .dongle:
                return "\("dongle".localizedString):"
            }
        }
    }
```

No localization keys are added in this task; UI prototype text remains English per project instruction.

- [ ] **Step 4: Add stored arrays and init parameters**

Add stored properties:

```swift
    private let batteryPowerSwitches: [PJEightKeySwitchData]
    private let acPowerSwitches: [PJEightKeySwitchData]
```

Update `init(...)` and `static func show(...)` signatures to include:

```swift
        batteryPowerSwitches: [PJEightKeySwitchData],
        acPowerSwitches: [PJEightKeySwitchData],
```

Assign them in `init`:

```swift
        self.batteryPowerSwitches = batteryPowerSwitches
        self.acPowerSwitches = acPowerSwitches
```

Pass them from `show(...)` into the initializer.

- [ ] **Step 5: Append rows in required order**

Update `reloadRows()` so rows are created in this order:

```swift
        rows = [.space]
        appendRows(for: .group, itemsIsEmpty: groups.isEmpty)
        if expandedSections.contains(.group) {
            rows.append(contentsOf: groups.map { .group($0) })
        }
        appendRows(for: .batteryPowerSwitch, itemsIsEmpty: batteryPowerSwitches.isEmpty)
        if expandedSections.contains(.batteryPowerSwitch) {
            rows.append(contentsOf: batteryPowerSwitches.map { .batteryPowerSwitch($0) })
        }
        appendRows(for: .acPowerSwitch, itemsIsEmpty: acPowerSwitches.isEmpty)
        if expandedSections.contains(.acPowerSwitch) {
            rows.append(contentsOf: acPowerSwitches.map { .acPowerSwitch($0) })
        }
        appendRows(for: .emergencyFire, itemsIsEmpty: emergencyFireDevices.isEmpty)
        if expandedSections.contains(.emergencyFire) {
            rows.append(contentsOf: emergencyFireDevices.map { .emergencyFire($0) })
        }
        appendRows(for: .dongle, itemsIsEmpty: dongles.isEmpty)
        if expandedSections.contains(.dongle) {
            rows.append(contentsOf: dongles.map { .dongle($0) })
        }
```

- [ ] **Step 6: Update selected, title, and didSelect handling**

Add cases to `isSelected(_:)`:

```swift
        case (.batteryPowerSwitch(let lhs), .batteryPowerSwitch(let rhs)):
            return lhs.id == rhs.id
        case (.acPowerSwitch(let lhs), .acPowerSwitch(let rhs)):
            return lhs.id == rhs.id
```

Add cases to `title(for:)`:

```swift
        case .batteryPowerSwitch(let switchData):
            return switchData.name
        case .acPowerSwitch(let switchData):
            return switchData.name
```

Add cases to `didSelectRowAt`:

```swift
        case .batteryPowerSwitch(let switchData):
            selectionHandler(.batteryPowerSwitch(switchData))
            dismiss()
        case .acPowerSwitch(let switchData):
            selectionHandler(.acPowerSwitch(switchData))
            dismiss()
```

- [ ] **Step 7: Run focused static check**

Run:

```bash
rg -n "batteryPowerSwitch|acPowerSwitch|batteryPowerSwitches|acPowerSwitches" SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift
```

Expected: output shows enum cases, row cases, section cases, arrays, show/init parameters, row appending, and selection handling.

- [ ] **Step 8: Commit target selection view changes**

Run:

```bash
git add SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift
git commit -m "feat: show virtual add targets"
```

Expected: commit succeeds with only `DeviceAddTargetSelectView.swift` staged.

## Task 3: Shared UI Control Hooks

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceAddViewCell.swift`
- Modify: `SunSmart/Main/Device/View/DeviceAddBottomView.swift`
- Modify: `SunSmart/Main/Device/View/DeviceAddSelectAllViewCell.swift`

- [ ] **Step 1: Add row selection hiding to DeviceAddViewCell**

In `DeviceAddViewCell`, add a property near `delegate`:

```swift
    var hidesSelectionControl: Bool = false
```

In `device.didSet`, replace the `switch device.selectedState` block with:

```swift
            if hidesSelectionControl {
                selectImageView.isHidden = true
            } else {
                switch device.selectedState {
                case .unselected:
                    selectImageView.isHidden = false
                    selectImageView.image = UIImage(named: "device_select_un")
                case .selected:
                    selectImageView.isHidden = false
                    selectImageView.image = UIImage(named: "device_select")
                case .disabled:
                    selectImageView.isHidden = true
                }
            }
```

- [ ] **Step 2: Add batch controls method to DeviceAddBottomView**

In `DeviceAddBottomView`, add this method before `setupUI()`:

```swift
    func setBatchControlsHidden(_ hidden: Bool) {
        selectAllBtn.isHidden = hidden
        selectAllLabel.isHidden = hidden
        selectCountLabel.isHidden = hidden
        addSelectedBtn.isHidden = hidden
    }
```

This hides only select-all/add-selected controls and leaves the view available for existing layout constraints.

- [ ] **Step 3: Add batch controls method to DeviceAddSelectAllViewCell**

In `DeviceAddSelectAllViewCell`, add:

```swift
    func setSelectionControlsHidden(_ hidden: Bool) {
        selectBtn.isHidden = hidden
        selectAllLabel.isHidden = hidden
        countLabel.isHidden = hidden
    }
```

The candidate button remains controlled by controller logic because Professional main mode uses it to move selected devices to Candidate Device List.

- [ ] **Step 4: Run focused static check**

Run:

```bash
rg -n "hidesSelectionControl|setBatchControlsHidden|setSelectionControlsHidden" SunSmart/Main/Device/View -S
```

Expected: output shows the three new UI hooks.

- [ ] **Step 5: Commit shared UI control hooks**

Run:

```bash
git add SunSmart/Main/Device/View/DeviceAddViewCell.swift SunSmart/Main/Device/View/DeviceAddBottomView.swift SunSmart/Main/Device/View/DeviceAddSelectAllViewCell.swift
git commit -m "feat: support hiding add selection controls"
```

Expected: commit succeeds with only these three view files staged.

## Task 4: Classic Mode Target Policy

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: Add target computed helpers**

In `DeviceAddClassicModeController`, near `bindToBatteryPowerSwitch`, add:

```swift
    private var isVirtualAddTarget: Bool {
        bindTarget != nil || bindToDongle != nil
    }

    private var hidesBatchSelectionControls: Bool {
        isVirtualAddTarget
    }

    private var lockedCategoryIndexForCurrentTarget: Int? {
        if bindToBatteryPowerSwitch != nil {
            return 1
        }
        if bindToEmerFire != nil || bindToDongle != nil {
            return 3
        }
        return nil
    }

    private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs.compactMap { $0 as? PJEightKeySwitchData }
            .filter { $0.proxyNodeAddress == nil && $0.powerSwitchKind == .battery }
    }

    private var unboundACPowerSwitches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs.compactMap { $0 as? PJEightKeySwitchData }
            .filter { $0.proxyNodeAddress == nil && $0.powerSwitchKind == .ac }
    }

    private var unboundEmergencyFireDevices: [DeviceEmerFireData] {
        DeviceEmerFireStore.shared.devices(in: space).filter { $0.bindNodeAddress == nil }
    }

    private var unboundDongles: [DeviceDongleData] {
        MeshNetworkManager.instance.dongles.filter { $0.bindNodeAddress == nil }
    }
```

- [ ] **Step 2: Update currentTargetSelection**

Update `currentTargetSelection` so battery/ac virtual switches are represented separately:

```swift
        if let bindToBatteryPowerSwitch {
            return bindToBatteryPowerSwitch.powerSwitchKind == .ac ?
                .acPowerSwitch(bindToBatteryPowerSwitch) :
                .batteryPowerSwitch(bindToBatteryPowerSwitch)
        }
```

Place this before the emergency fire case.

- [ ] **Step 3: Add reusable target application**

Add this helper near `normalizeSelectionForCurrentTarget()`:

```swift
    private func clearSelectedDevicesForVirtualTargetIfNeeded(previousWasVirtual: Bool) {
        guard isVirtualAddTarget, !previousWasVirtual else {
            return
        }
        scanDevices.forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        showDevices.forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
    }

    private func applyTargetSelection(_ selection: DeviceAddTargetSelection) {
        let previousWasVirtual = isVirtualAddTarget
        switch selection {
        case .space:
            addToGroup = nil
            bindToDongle = nil
            bindTarget = nil
        case .group(let group):
            addToGroup = group
            bindToDongle = nil
            bindTarget = nil
        case .batteryPowerSwitch(let switchData), .acPowerSwitch(let switchData):
            addToGroup = nil
            bindToDongle = nil
            bindTarget = .batteryPowerSwitch(switchData)
        case .emergencyFire(let device):
            addToGroup = nil
            bindToDongle = nil
            bindTarget = .emergencyFire(device)
        case .dongle(let dongle):
            addToGroup = nil
            bindToDongle = dongle
            bindTarget = nil
        }
        clearSelectedDevicesForVirtualTargetIfNeeded(previousWasVirtual: previousWasVirtual)
        normalizeSelectionForCurrentTarget()
        applyLockedCategoryForCurrentTarget()
    }

    private func applyLockedCategoryForCurrentTarget() {
        guard let index = lockedCategoryIndexForCurrentTarget else {
            return
        }
        showDeviceTypes = deviceTypes(forCategoryIndex: index)
        categoryView.selectItem(at: index)
        let filteredDevices = scanDevices.filter { selectRSSIRange.contains($0.rssi.intValue) }
        showDevices = filteredDevices.filter { showDeviceTypes.contains($0.deviceType) }
    }
```

- [ ] **Step 4: Update category selection lock**

Update `shouldAllowCategorySelection(at:)` so virtual targets lock category:

```swift
    private func shouldAllowCategorySelection(at index: Int) -> Bool {
        if let lockedCategoryIndex = lockedCategoryIndexForCurrentTarget {
            return index == lockedCategoryIndex
        }
        guard let addBehavior else {
            return true
        }
        if addBehavior.allowsCategorySelection {
            return true
        }
        guard let initialCategoryIndex else {
            return false
        }
        return index == initialCategoryIndex
    }
```

Existing `showAddBehaviorTip()` already uses the LINK text `You can't choose other devices.` when configured by LINK entry. If `addBehavior` is nil for normal virtual targets, add a fallback in `showAddBehaviorTip()`:

```swift
    private func showAddBehaviorTip() {
        let tip = addBehavior?.forbiddenSelectionTip ?? "You can't choose other devices."
        guard !tip.isEmpty else {
            return
        }
        XWHUDManager.showTipHUD(tip, isLineFeed: true)
    }
```

- [ ] **Step 5: Replace target select popup call**

In `addDeviceTargetBtnClick`, use `DeviceAddTargetSelectView.show(...)` for the normal selectable-target path and pass all virtual arrays:

```swift
            DeviceAddTargetSelectView.show(
                anchorPoint: menuPoint,
                groups: MeshNetworkManager.instance.groups,
                batteryPowerSwitches: unboundBatteryPowerSwitches,
                acPowerSwitches: unboundACPowerSwitches,
                emergencyFireDevices: unboundEmergencyFireDevices,
                dongles: unboundDongles,
                selectedTarget: currentTargetSelection
            ) { [weak self] selection in
                guard let self else { return }
                self.applyTargetSelection(selection)
                sender.setTitle(self.currentTargetName, for: .normal)
                self.tableView.reloadData()
                self.updateFooterViewState()
                self.updateUIState()
            }
            return
```

Keep existing `appointGroup != nil`, `forceBindToDongle != nil`, and `shouldAllowTargetSelection()` checks before showing the popup.

- [ ] **Step 6: Update currentTargetName**

Ensure current target name prioritizes bind target and dongle:

```swift
    private var currentTargetName: String {
        if let bindTarget {
            return bindTarget.name
        }
        if let bindToDongle {
            return bindToDongle.name
        }
        if let groupName = addToGroup?.name {
            return groupName
        }
        return space.name
    }
```

- [ ] **Step 7: Hide row selection control in Classic cells**

In `cellForRowAt`, set `hidesSelectionControl` before assigning `device`:

```swift
        cell.hidesSelectionControl = hidesBatchSelectionControls
        cell.device = device
```

When manually updating `cell.selectImageView.image` in `didSelectRowAt`, guard the update:

```swift
            if !hidesBatchSelectionControls, let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
```

- [ ] **Step 8: Hide Classic footer batch controls for virtual targets**

At the start of `updateFooterViewState()`, add:

```swift
        footerView.setBatchControlsHidden(hidesBatchSelectionControls)
        guard !hidesBatchSelectionControls else {
            footerView.selectAllBtn.isSelected = false
            footerView.addSelectedBtn.isEnabled = false
            return
        }
```

At the start of `selectAllBtnClick(sender:)` and `addSelectedBtnClick()`, add:

```swift
        guard !hidesBatchSelectionControls else {
            sender.isSelected = false
            return
        }
```

For `addSelectedBtnClick()`, use:

```swift
        guard !hidesBatchSelectionControls else {
            return
        }
```

- [ ] **Step 9: Run Classic static checks**

Run:

```bash
rg -n "isVirtualAddTarget|hidesBatchSelectionControls|lockedCategoryIndexForCurrentTarget|unboundBatteryPowerSwitches|applyTargetSelection|applyLockedCategoryForCurrentTarget|setBatchControlsHidden|hidesSelectionControl" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: output shows all Classic helpers and call sites.

- [ ] **Step 10: Commit Classic target policy**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
git commit -m "feat: apply virtual targets in classic add"
```

Expected: commit succeeds with only Classic controller staged.

## Task 5: Professional Mode Target Policy

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Add Professional target helpers**

Add helpers equivalent to Classic near `bindToBatteryPowerSwitch`:

```swift
    private var isVirtualAddTarget: Bool {
        if bindTarget != nil {
            return true
        }
        if case .dongle = addTarget {
            return true
        }
        return false
    }

    private var hidesBatchSelectionControls: Bool {
        isVirtualAddTarget
    }

    private var lockedCategoryIndexForCurrentTarget: Int? {
        if bindToBatteryPowerSwitch != nil {
            return 1
        }
        if bindToEmerFire != nil {
            return 3
        }
        if case .dongle = addTarget {
            return 3
        }
        return nil
    }

    private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs.compactMap { $0 as? PJEightKeySwitchData }
            .filter { $0.proxyNodeAddress == nil && $0.powerSwitchKind == .battery }
    }

    private var unboundACPowerSwitches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs.compactMap { $0 as? PJEightKeySwitchData }
            .filter { $0.proxyNodeAddress == nil && $0.powerSwitchKind == .ac }
    }

    private var unboundEmergencyFireDevices: [DeviceEmerFireData] {
        DeviceEmerFireStore.shared.devices(in: space).filter { $0.bindNodeAddress == nil }
    }

    private var unboundDongles: [DeviceDongleData] {
        MeshNetworkManager.instance.dongles.filter { $0.bindNodeAddress == nil }
    }
```

- [ ] **Step 2: Update currentTargetSelection**

Add battery/ac selection before emergency fire:

```swift
        if let bindToBatteryPowerSwitch {
            return bindToBatteryPowerSwitch.powerSwitchKind == .ac ?
                .acPowerSwitch(bindToBatteryPowerSwitch) :
                .batteryPowerSwitch(bindToBatteryPowerSwitch)
        }
```

- [ ] **Step 3: Add target apply helpers**

Add:

```swift
    private func clearSelectedDevicesForVirtualTargetIfNeeded(previousWasVirtual: Bool) {
        guard isVirtualAddTarget, !previousWasVirtual else {
            return
        }
        (scanDevices + inRSSIDevices + remainingRSSIDevices + candidateDevices).forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
    }

    private func applyTargetSelection(_ selection: DeviceAddTargetSelection) {
        let previousWasVirtual = isVirtualAddTarget
        switch selection {
        case .space:
            addTarget = .space(space)
            bindTarget = nil
        case .group(let group):
            addTarget = .group(group)
            bindTarget = nil
        case .batteryPowerSwitch(let switchData), .acPowerSwitch(let switchData):
            addTarget = .space(space)
            bindTarget = .batteryPowerSwitch(switchData)
        case .emergencyFire(let device):
            addTarget = .space(space)
            bindTarget = .emergencyFire(device)
        case .dongle(let dongle):
            addTarget = .dongle(dongle)
            bindTarget = nil
        }
        clearSelectedDevicesForVirtualTargetIfNeeded(previousWasVirtual: previousWasVirtual)
        normalizeSelectionForCurrentTarget()
        applyLockedCategoryForCurrentTarget()
    }

    private func applyLockedCategoryForCurrentTarget() {
        guard let index = lockedCategoryIndexForCurrentTarget else {
            return
        }
        deviceTypes = deviceTypes(forCategoryIndex: index)
        setupDevicesData()
    }

    private func deviceTypes(forCategoryIndex index: Int) -> [Node.DeviceType] {
        switch index {
        case 0:
            return [.light]
        case 1:
            return [.switches]
        case 2:
            return [.sensor]
        case 3:
            return [.dongle, .gateway, .emergencyController, .unknown]
        default:
            return [.light]
        }
    }
```

Before adding `deviceTypes(forCategoryIndex:)`, run `rg -n "deviceTypes\\(forCategoryIndex" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`. If the method already exists, update the existing method to match the body above instead of adding a duplicate.

- [ ] **Step 4: Update Professional category lock**

Find Professional category selection handling. Add a guard equivalent to:

```swift
        if let lockedCategoryIndex = lockedCategoryIndexForCurrentTarget,
           index != lockedCategoryIndex {
            XWHUDManager.showTipHUD(addBehavior?.forbiddenSelectionTip ?? "You can't choose other devices.", isLineFeed: true)
            return false
        }
```

Use the existing `WMMenuViewDelegate` method shape in the file.

- [ ] **Step 5: Hide Professional main select-all and row controls**

In `cellForRowAt`, for `DeviceAddSelectAllViewCell`:

```swift
            selectCell.setSelectionControlsHidden(hidesBatchSelectionControls)
            if hidesBatchSelectionControls {
                selectCell.selectBtn.isSelected = false
                selectCell.candidateBtn.isEnabled = false
            }
```

For `DeviceAddViewCell` rows, set before `cell.device = device`:

```swift
            cell.hidesSelectionControl = hidesBatchSelectionControls
```

In `DeviceAddSelectAllViewCellDelegate` methods, add guards:

```swift
        guard !hidesBatchSelectionControls else {
            return
        }
```

This guard belongs at the start of `cell(_:selectAllAction:)` and `selectAllCellCandidateAction(_:)`.

- [ ] **Step 6: Replace candidate target selection popup**

In `candidateView(_:selectAddDevicesTarget:currentDeviceTypes:)`, replace the virtual-emergency-only `DeviceAddTargetSelectView.show(...)` call with:

```swift
            DeviceAddTargetSelectView.show(
                anchorPoint: touchPoint,
                groups: MeshNetworkManager.instance.groups,
                batteryPowerSwitches: unboundBatteryPowerSwitches,
                acPowerSwitches: unboundACPowerSwitches,
                emergencyFireDevices: unboundEmergencyFireDevices,
                dongles: unboundDongles,
                selectedTarget: currentTargetSelection
            ) { [weak self] selection in
                guard let self else { return }
                self.applyTargetSelection(selection)
                view.addTarget = self.addTarget
                view.addTargetNameOverride = self.addTargetNameOverride
                view.hidesBatchSelectionControls = self.hidesBatchSelectionControls
                view.lockedCategoryIndex = self.lockedCategoryIndexForCurrentTarget
                view.candidateDevices = self.candidateDevices
                self.tableView.reloadData()
            }
            return
```

Keep `shouldAllowTargetSelection()` guard so LINK entry cannot switch targets.

- [ ] **Step 7: Pass virtual UI state when showing candidate list**

In the method that calls `candidateView.show()`, set before `show()`:

```swift
        candidateView.hidesBatchSelectionControls = hidesBatchSelectionControls
        candidateView.lockedCategoryIndex = lockedCategoryIndexForCurrentTarget
```

- [ ] **Step 8: Run Professional static checks**

Run:

```bash
rg -n "isVirtualAddTarget|hidesBatchSelectionControls|lockedCategoryIndexForCurrentTarget|applyTargetSelection|setSelectionControlsHidden|hidesSelectionControl|batteryPowerSwitches|acPowerSwitches" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output shows helper definitions and Professional call sites.

- [ ] **Step 9: Commit Professional target policy**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "feat: apply virtual targets in professional add"
```

Expected: commit succeeds with only Professional controller staged.

## Task 6: Candidate Device List UI Rules

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

- [ ] **Step 1: Add public state properties**

In `DeviceAddCandidateDeviceListView`, near `addTargetNameOverride`, add:

```swift
    var hidesBatchSelectionControls: Bool = false {
        didSet {
            updateUIState()
            tableView?.reloadData()
        }
    }

    var lockedCategoryIndex: Int?
```

- [ ] **Step 2: Lock candidate category selection**

Uncomment or add `menuView(_:shouldSelesctedIndex:)`:

```swift
    func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        if let lockedCategoryIndex, index != lockedCategoryIndex {
            XWHUDManager.showTipHUD("You can't choose other devices.", isLineFeed: true)
            return false
        }
        return true
    }
```

- [ ] **Step 3: Hide candidate footer batch controls for virtual targets**

At the start of `updateFooterViewState()`, add:

```swift
        footerView.setBatchControlsHidden(hidesBatchSelectionControls)
        guard !hidesBatchSelectionControls else {
            footerView.selectAllBtn.isSelected = false
            footerView.addSelectedBtn.isEnabled = false
            return
        }
```

At the start of `selectAllBtnClick(sender:)`:

```swift
        guard !hidesBatchSelectionControls else {
            sender.isSelected = false
            return
        }
```

At the start of `addSelectedBtnClick()`:

```swift
        guard !hidesBatchSelectionControls else {
            return
        }
```

- [ ] **Step 4: Hide candidate row selection controls**

In candidate `cellForRowAt`, set before `cell.device = device`:

```swift
        cell.hidesSelectionControl = hidesBatchSelectionControls
```

When manually updating `cell.selectImageView.image` in `didSelectRowAt`, guard it:

```swift
            if !hidesBatchSelectionControls, let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
```

- [ ] **Step 5: Preserve Group target behavior**

Verify no code sets `hidesBatchSelectionControls = true` for `.group`. The property must only be set from controller `hidesBatchSelectionControls`, whose value is true only for virtual targets.

Run:

```bash
rg -n "hidesBatchSelectionControls = true|hidesBatchSelectionControls =|lockedCategoryIndex =" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
```

Expected: assignments come from controller state, not from group-specific code.

- [ ] **Step 6: Commit candidate UI rules**

Run:

```bash
git add SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
git commit -m "feat: apply virtual target rules to candidates"
```

Expected: commit succeeds with only candidate list view staged.

## Task 7: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run static consistency checks**

Run:

```bash
rg -n "DeviceAddTargetSelectView.show" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
rg -n "hidesBatchSelectionControls|hidesSelectionControl|lockedCategoryIndexForCurrentTarget|setBatchControlsHidden|setSelectionControlsHidden" SunSmart/Main/Device -S
rg -n "powerSwitchPanelType|batteryPowerSwitchPanelType == sourceSwitchData.eightKeyPanelType" SunSmart/Main/Device SunSmart/Common -S
```

Expected:

- Both Classic and Professional use the expanded `DeviceAddTargetSelectView.show(...)`.
- Classic, Professional, and Candidate all reference virtual target UI hiding.
- Power switch panel matching exists for scan devices and linked node validation.

- [ ] **Step 2: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: clean working tree after all task commits.

- [ ] **Step 4: Manual QA checklist**

Use a device/app state with at least one unbound virtual Battery Power Switch, AC Power Switch, Emergency Controller, and Dongle when possible.

Check:

- Site - Space - Main -> Add Device -> Add Device(s) to shows Space, Group, Battery Power Switch, AC Power Switch, Emergency Controller, Dongle only when each section has items.
- Selecting virtual Battery/AC auto-selects Switches and blocks Lights/Sensors/Others with `You can't choose other devices.`
- Selecting virtual Emergency Controller/Dongle auto-selects Others and blocks Lights/Switches/Sensors.
- Virtual target hides bottom Select all/Add selected controls and row left selection buttons in Classic.
- Virtual target hides Professional main Select All cell controls and row left selection buttons.
- Virtual target hides Candidate Device List bottom Select all/Add selected controls and row left selection buttons.
- Group target still shows batch controls and row left selection buttons; disabled Switches/Others are not selected by select all and cannot be submitted.
- LINK entry target remains fixed and cannot switch Add Device(s) to.
- Power switch product id panel mismatch is disabled before Add and rejected by linked helper if reached.

- [ ] **Step 5: Final summary**

Record:

- Build result.
- Any manual QA cases not run because fixture data was unavailable.
- Latest commit hashes for implementation tasks.
