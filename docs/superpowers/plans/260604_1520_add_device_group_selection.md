# Add Device Group Selection Restrictions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 当 Add Device 页面的目标选择为 Group 时，Switches 和 Others 分类设备继续展示，但不可选、不可单独 Add、不可进入批量或 candidate 入网队列。

**Architecture:** 复用 Classic 和 Professional 添加页现有的 `isSelectableDevice` / `applySelectableState` / `normalizeSelectionForCurrentTarget` 状态流，把 Group 目标禁选规则接入控制器层。UI 层只补齐 `DeviceAddViewCell` 的 Add 按钮 disabled 状态，不引入新的 policy 文件或跨模块重构。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 `ProvisioningDevice.DeviceSelectedState`、现有 `xcodebuild` iPhoneOS 构建校验。

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 负责 Classic 模式中当前目标、扫描设备、分类列表、全选和 Add Selected 的状态控制。
  - 新增 Group 目标下 switches/others 禁选判断。
  - 在批量添加入口补一层非 disabled 过滤。

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 负责 Professional 模式中 `scanDevices`、RSSI 分区、candidate 列表和添加目标状态。
  - 新增 Group 目标下 switches/others 禁选判断。
  - 在 candidate 进入添加流程前过滤不可选设备。

- Modify: `SunSmart/Main/Device/View/DeviceAddViewCell.swift`
  - 负责单行设备 UI。
  - 根据 `selectedState == .disabled` 禁用 Add 按钮并显示已有 disabled 图片。

- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 负责 Professional 候选弹层列表。
  - 补齐 disabled 设备的行点击和单行 Add 防线，避免弹层独立状态出现漏网入口。

- No Create: 本次不新增 Swift 文件、不新增本地化、不新增资源。

## Task 1: Classic Group Target Selection Rule

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: Inspect current Classic selection helpers**

Run:

```bash
rg -n "currentTargetSelection|isBlockedDeviceType|isAllowedDevice|isBlockedDevice|isSelectableDevice|applySelectableState|normalizeSelectionForCurrentTarget|addSelectedBtnClick" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: output includes the existing helper chain and confirms there is no Group-specific switches/others rule yet.

- [ ] **Step 2: Add Classic target and type helpers**

In `DeviceAddClassicModeController`, insert these helpers near `shouldBlockEmergencyControllerForCurrentTarget`:

```swift
    private var isAddingToGroupTarget: Bool {
        addToGroup != nil
    }

    private func shouldBlockDeviceTypeForGroupTarget(_ deviceType: Node.DeviceType) -> Bool {
        guard isAddingToGroupTarget else {
            return false
        }
        switch deviceType {
        case .switches, .dongle, .gateway, .emergencyController, .unknown:
            return true
        default:
            return false
        }
    }
```

- [ ] **Step 3: Wire the helper into Classic blocked type logic**

Update `isBlockedDeviceType(_:)` so Group-target blocking runs after `bindTarget` and before existing emergency/addBehavior checks:

```swift
    private func isBlockedDeviceType(_ deviceType: Node.DeviceType) -> Bool {
        if let bindTarget {
            return !bindTarget.allowedDeviceTypes.contains(deviceType)
        }
        if shouldBlockDeviceTypeForGroupTarget(deviceType) {
            return true
        }
        if shouldBlockEmergencyControllerForCurrentTarget, deviceType == .emergencyController {
            return true
        }
        return addBehavior?.blockedDeviceTypes.contains(deviceType) == true
    }
```

- [ ] **Step 4: Make Classic applySelectableState active for normal Group rules**

Change the guard in `applySelectableState(to:)` so Group target rules run even when `addBehavior` and `bindTarget` are nil:

```swift
        guard addBehavior != nil || bindTarget != nil || isAddingToGroupTarget else {
            return
        }
```

Expected behavior: when current target is Group, `applySelectableState` converts switches/others to `.disabled`; when target is Space and there is no special rule, old default flow remains unchanged.

- [ ] **Step 5: Filter Classic Add Selected against disabled devices**

Update `addSelectedBtnClick()` selection gathering:

```swift
        let selectedDevices = showDevices.filter({ $0.selectedState == .selected && isSelectableDevice($0) })
        let selectDevices = isSingleSelectionMode ? Array(selectedDevices.prefix(1)) : selectedDevices
```

Expected behavior: disabled devices cannot be submitted even if stale UI state exists.

- [ ] **Step 6: Run focused static check for Classic references**

Run:

```bash
rg -n "isAddingToGroupTarget|shouldBlockDeviceTypeForGroupTarget|selectedState == \\.selected && isSelectableDevice" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: output shows the two helpers and the filtered Add Selected expression in Classic.

## Task 2: Professional Group Target Selection Rule

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Inspect current Professional selection helpers**

Run:

```bash
rg -n "currentTargetSelection|isBlockedDeviceType|isSelectableDeviceType|isAllowedDevice|isBlockedDevice|isSelectableDevice|applySelectableState|normalizeSelectionForCurrentTarget|candidateView\\(_ view: DeviceAddCandidateDeviceListView, startAdd" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output includes the existing helper chain and candidate startAdd entry.

- [ ] **Step 2: Add Professional target and type helpers**

In `DeviceAddProfessionalModeController`, insert these helpers near `shouldBlockEmergencyControllerForCurrentTarget`:

```swift
    private var isAddingToGroupTarget: Bool {
        if case .group = addTarget {
            return true
        }
        return false
    }

    private func shouldBlockDeviceTypeForGroupTarget(_ deviceType: Node.DeviceType) -> Bool {
        guard isAddingToGroupTarget else {
            return false
        }
        switch deviceType {
        case .switches, .dongle, .gateway, .emergencyController, .unknown:
            return true
        default:
            return false
        }
    }
```

- [ ] **Step 3: Wire the helper into Professional blocked type logic**

Update `isBlockedDeviceType(_:)`:

```swift
    private func isBlockedDeviceType(_ deviceType: Node.DeviceType) -> Bool {
        if let bindTarget {
            return !bindTarget.allowedDeviceTypes.contains(deviceType)
        }
        if shouldBlockDeviceTypeForGroupTarget(deviceType) {
            return true
        }
        if shouldBlockEmergencyControllerForCurrentTarget, deviceType == .emergencyController {
            return true
        }
        return addBehavior?.blockedDeviceTypes.contains(deviceType) == true
    }
```

- [ ] **Step 4: Make Professional applySelectableState active for normal Group rules**

Change the guard in `applySelectableState(to:)`:

```swift
        guard addBehavior != nil || bindTarget != nil || isAddingToGroupTarget else {
            return
        }
```

- [ ] **Step 5: Harden Professional candidate startAdd**

Update candidate startAdd to filter disabled and blocked devices:

```swift
    func candidateView(_ view: DeviceAddCandidateDeviceListView, startAdd devices: [ProvisioningDevice]) {
        let selectableDevices = devices.filter { $0.selectedState != .disabled && isSelectableDevice($0) }
        let devicesToAdd = isSingleSelectionMode ? Array(selectableDevices.prefix(1)) : selectableDevices
        guard !devicesToAdd.isEmpty else {
            return
        }
        checkDeviceAddressesAreSufficient(devices: devicesToAdd)
    }
```

Expected behavior: switches/others cannot be added from candidate when target is Group, including stale candidate state after target changes.

- [ ] **Step 6: Run focused static check for Professional references**

Run:

```bash
rg -n "isAddingToGroupTarget|shouldBlockDeviceTypeForGroupTarget|selectableDevices|devicesToAdd" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output shows the two helpers and candidate startAdd filtering in Professional.

## Task 3: Disable Add Button for Disabled Devices

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceAddViewCell.swift`
- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

- [ ] **Step 1: Update base cell Add button state**

In `DeviceAddViewCell.device.didSet`, inside `case .none, .scaning`, replace the enabled-state block with:

```swift
                if device.addState == .scaning {
                    identifyBtn.isEnabled = false
                    addBtn.isEnabled = false
                    identifyBtn.layer.borderColor = RGB(156, 163, 175, 0.5).cgColor
                }else {
                    identifyBtn.isEnabled = true
                    addBtn.isEnabled = device.deviceType != .unknown && device.selectedState != .disabled
                    identifyBtn.layer.borderColor = Bar_Color.cgColor
                }
```

Expected behavior: disabled switches/others rows show the existing disabled Add image and cannot invoke `addBtnClick`.

- [ ] **Step 2: Preserve revoke button behavior in candidate scanning mode**

In `DeviceAddCandidateDeviceListView.tableView(_:cellForRowAt:)`, after the existing scanning/revoke image selection block, add:

```swift
        if device.selectedState == .disabled {
            cell.addBtn.isEnabled = false
        }
```

Expected behavior: when candidate view displays a disabled row, the Add/Revoke button is not clickable.

- [ ] **Step 3: Add candidate row disabled tap guard**

In `DeviceAddCandidateDeviceListView.tableView(_:didSelectRowAt:)`, before the existing guard for `.unselected` / `.selected`, add:

```swift
        if device.selectedState == .disabled {
            return
        }
```

Expected behavior: candidate list row taps do not toggle disabled devices.

- [ ] **Step 4: Add candidate single Add disabled guard**

In `DeviceAddCandidateDeviceListView.cell(_:deviceAdd:)`, before scanning/revoke behavior, add:

```swift
        guard device.selectedState != .disabled else {
            return
        }
```

Expected behavior: even if a disabled button click is triggered by stale UI, the delegate does not start Add.

- [ ] **Step 5: Run focused static check for UI guards**

Run:

```bash
rg -n "device\\.selectedState != \\.disabled|selectedState == \\.disabled" SunSmart/Main/Device/View/DeviceAddViewCell.swift SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
```

Expected: output shows Add button disabled logic in `DeviceAddViewCell` and candidate guard logic in `DeviceAddCandidateDeviceListView`.

## Task 4: Verify State Flow and Build

**Files:**
- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Verify: `SunSmart/Main/Device/View/DeviceAddViewCell.swift`
- Verify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

- [ ] **Step 1: Check formatting impact**

Run:

```bash
git diff -- SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/View/DeviceAddViewCell.swift SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
```

Expected: diff only contains focused helper additions, guard updates, filtering, and Add button enabled-state changes.

- [ ] **Step 2: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds. If the command fails because of signing, package resolution, or environment issues, capture the first concrete compiler error before making any code changes.

- [ ] **Step 3: Manual Classic verification**

Using a real add-device flow or available QA setup, verify:

```text
Classic / Space / Switches:
- scanned switch row shows selectable icon
- Add button is enabled

Classic / switch selected / change target to Group:
- switch row remains visible
- select icon changes to disabled
- Add button changes to disabled image and cannot be tapped
- Add Selected button does not include the switch

Classic / Group / Others:
- others rows remain visible
- select icon is disabled
- Add button is disabled

Classic / change target back to Space:
- switches and others rows become unselected and selectable when not adding
- Add button becomes enabled for supported non-unknown devices
```

- [ ] **Step 4: Manual Professional verification**

Using a real add-device flow or available QA setup, verify:

```text
Professional / Space:
- switches and others can be selected or added to candidate

Professional / change target to Group:
- switches and others in scan lists remain visible but disabled
- switches and others are removed from candidate
- candidate count excludes switches and others

Professional / Group scanning:
- newly scanned switches and others do not auto-enter candidate
- row Add button is disabled

Professional / change target back to Space:
- switches and others become unselected and selectable when not adding
```

- [ ] **Step 5: Commit implementation only**

Run:

```bash
git status --short
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/View/DeviceAddViewCell.swift SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
git commit -m "fix: block switch and other devices for group add target"
```

Expected: commit includes only the four implementation files. Existing unrelated modified files remain unstaged unless they are part of this task.

## Self-Review

- Spec coverage: the plan covers Classic, Professional, candidate cleanup, Add button disabled UI, Add Selected filtering, and iPhoneOS build verification.
- 占位内容扫描：计划中没有未完成要求，也没有延后实现段落。
- Type consistency: helper names are identical across Classic and Professional where possible: `isAddingToGroupTarget` and `shouldBlockDeviceTypeForGroupTarget(_:)`.
- Scope check: the plan stays within Add Device controllers and the shared device add cell/candidate view. It does not modify resource files, localization, target configuration, dependencies, or SDK code.
