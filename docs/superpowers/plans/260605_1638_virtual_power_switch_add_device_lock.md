# Virtual Power Switch Add Device Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery/AC Power Switch 与 Others 虚拟设备在 Add Device 中可连续 LINK 多个真实设备的问题，并让 AC 旧无效绑定与 Battery 一样归一化为虚拟设备。

**Architecture:** 在 `ProvisioningDevice` 添加共享添加状态判断，供 Classic、Professional、Candidate Device List 复用。保留现有 Add Device controller 架构，只在 start-add 和行按钮状态处加入虚拟目标锁。扩展现有 power switch proxy normalize 逻辑，同时覆盖 battery 与 ac。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Add Device controllers、iPhoneOS `xcodebuild` 构建验证。

---

## File Structure

- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`
  - 增加 `blocksVirtualTargetSingleAdd`，统一判断 `.wait`、`.addConnecting`、`.adding`、`.success` 是否会锁住虚拟目标。

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 更新 `normalizeInvalidBatteryPowerSwitchProxyLinks(notify:)`，同时处理 Battery 与 AC 的无效 `proxyNodeAddress`。

- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`
  - 增加 `virtualTargetAddLocked` 属性。
  - 锁住时禁用候选列表中空闲设备的单行 `+`。
  - 单行 `+` 回调前做最终锁校验。

- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 增加虚拟目标锁判断。
  - Classic Stop 后列表单行 `+` 前拒绝第二次 LINK。
  - cell 渲染时根据锁状态禁用其它可点击 `+`。

- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 增加虚拟目标锁判断。
  - 同步锁状态到 Candidate Device List。
  - Professional 主列表和 Candidate 弹层都拒绝第二次 LINK。

## Task 1: Add Shared Add-State Helper

**Files:**
- Modify: `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`

- [ ] **Step 1: Inspect current add-state enum**

Run:

```bash
sed -n '1,120p' SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift
```

Expected: output shows `ProvisioningDevice.DeviceAddState` with `.wait`, `.addConnecting`, `.adding`, `.success`, `.failed`.

- [ ] **Step 2: Add helper on `ProvisioningDevice.DeviceAddState`**

In `SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift`, after the `DeviceAddState` enum closing brace, add:

```swift
    var blocksVirtualTargetSingleAdd: Bool {
        switch self {
        case .wait, .addConnecting, .adding, .success:
            return true
        default:
            return false
        }
    }
```

The enum should become:

```swift
    enum DeviceAddState {
        /// 无
        case none
        /// 扫描中
        case scaning
        /// 等待添加
        case wait
        /// identify连接中
        case identifyConnecting
        /// identify等待
        case identifyWait
        /// identify中
        case identifying
        /// identify失败
        case identifyFail
        /// 添加设备连接中
        case addConnecting
        /// 添加中（provisioning+keybind）
        case adding
        /// 添加成功
        case success
        /// 添加失败
        case failed
        /// 同步失败
        case syncFailed

        var blocksVirtualTargetSingleAdd: Bool {
            switch self {
            case .wait, .addConnecting, .adding, .success:
                return true
            default:
                return false
            }
        }
    }
```

- [ ] **Step 3: Verify helper compiles syntactically by search**

Run:

```bash
rg -n "blocksVirtualTargetSingleAdd" SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift
```

Expected: output shows one definition inside `ProvisioningDevice.DeviceAddState`.

- [ ] **Step 4: Commit helper**

Run:

```bash
git add SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift
git commit -m "fix: add virtual target add-state helper"
```

Expected: commit succeeds with only `ProvisioningDevice+Add.swift` staged.

## Task 2: Normalize Battery And AC Invalid Proxy Links

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: Inspect current normalization**

Run:

```bash
sed -n '873,915p' SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: output shows `normalizeInvalidBatteryPowerSwitchProxyLinks(notify:)` currently guards `batteryPowerSwitch.powerSwitchKind == .battery`.

- [ ] **Step 2: Replace normalization body**

In `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`, replace the full `normalizeInvalidBatteryPowerSwitchProxyLinks(notify:)` method with:

```swift
    @discardableResult
    func normalizeInvalidBatteryPowerSwitchProxyLinks(notify: Bool = false) -> Bool {
        guard let meshNetwork else {
            return false
        }

        var didChange = false

        for index in self.switchs.indices {
            let currentSwitch = self.switchs[index]
            let powerSwitch: PJEightKeySwitchData?
            if let eightKeySwitch = currentSwitch as? PJEightKeySwitchData {
                powerSwitch = eightKeySwitch
            } else {
                powerSwitch = PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: currentSwitch)
            }

            guard let powerSwitch,
                  let proxyNodeAddress = powerSwitch.proxyNodeAddress else {
                continue
            }

            let proxyNode = meshNetwork.node(withAddress: proxyNodeAddress)
            let proxyMatchesKind: Bool
            switch powerSwitch.powerSwitchKind {
            case .battery:
                proxyMatchesKind = proxyNode?.isBatteryPowerSwitch == true
            case .ac:
                proxyMatchesKind = proxyNode?.isACPowerSwitch == true
            }

            guard !proxyMatchesKind else {
                if !(currentSwitch is PJEightKeySwitchData) {
                    self.switchs[index] = powerSwitch
                }
                continue
            }

            powerSwitch.proxyNodeAddress = nil
            guard PJEightKeySwitchRepository.shared.save(powerSwitch),
                  powerSwitch.save() else {
                continue
            }

            self.switchs[index] = powerSwitch
            didChange = true
        }

        guard didChange, notify else {
            return didChange
        }

        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.common
        )
        return didChange
    }
```

- [ ] **Step 3: Verify AC branch exists**

Run:

```bash
rg -n "proxyMatchesKind|isACPowerSwitch|isBatteryPowerSwitch" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected: output includes `proxyMatchesKind = proxyNode?.isACPowerSwitch == true` and `proxyMatchesKind = proxyNode?.isBatteryPowerSwitch == true`.

- [ ] **Step 4: Commit normalization**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: normalize ac power switch proxy links"
```

Expected: commit succeeds with only `MeshNetwork+SunSmart.swift` staged.

## Task 3: Add Candidate Device List Lock UI

**Files:**
- Modify: `SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift`

- [ ] **Step 1: Inspect candidate list hooks**

Run:

```bash
sed -n '60,130p' SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
sed -n '821,980p' SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
```

Expected: output shows `hidesSelectionControls`, `cellForRowAt`, and `cell(_:deviceAdd:)`.

- [ ] **Step 2: Add lock property**

In `DeviceAddCandidateDeviceListView`, after `hidesSelectionControls`, add:

```swift
    var virtualTargetAddLocked: Bool = false {
        didSet {
            guard virtualTargetAddLocked != oldValue else { return }
            tableView.reloadData()
        }
    }
```

- [ ] **Step 3: Disable idle row add buttons while locked**

In `tableView(_:cellForRowAt:)`, after the existing `if device.selectedState == .disabled { cell.addBtn.isEnabled = false }` block, add:

```swift
        if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
            cell.addBtn.isEnabled = false
        }
```

The relevant end of the cell setup should read:

```swift
        if device.selectedState == .disabled {
            cell.addBtn.isEnabled = false
        }
        if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
            cell.addBtn.isEnabled = false
        }
        cell.delegate = self
        return cell
```

- [ ] **Step 4: Guard single add callback**

In `cell(_:deviceAdd:)`, after the scanning/revoke branch and before the max-device-count guard, add:

```swift
        guard !virtualTargetAddLocked else {
            return
        }
```

The sequence should read:

```swift
        if state == .scanning && (isRefresh || lightSeningMode) {
            delegate?.candidateView(self, candidateRevoke: [device])
            return
        }
        guard !virtualTargetAddLocked else {
            return
        }
        // space只能添加200个设备
```

- [ ] **Step 5: Verify candidate lock hooks**

Run:

```bash
rg -n "virtualTargetAddLocked|blocksVirtualTargetSingleAdd" SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
```

Expected: output shows one property, one cell disable check, and one callback guard.

- [ ] **Step 6: Commit candidate view lock**

Run:

```bash
git add SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift
git commit -m "fix: lock candidate virtual target adds"
```

Expected: commit succeeds with only `DeviceAddCandidateDeviceListView.swift` staged.

## Task 4: Lock Classic Virtual Target Adds

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: Inspect Classic hooks**

Run:

```bash
sed -n '90,125p' SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
sed -n '1550,1660p' SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
sed -n '2040,2080p' SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: output shows `isVirtualAddTarget`, `cellForRowAt`, `updateUIState`, and `cell(_:deviceAdd:)`.

- [ ] **Step 2: Add Classic lock helpers**

After `hidesBatchSelectionControls`, add:

```swift
    private var virtualTargetAddLocked: Bool {
        guard isVirtualAddTarget else {
            return false
        }
        return scanDevices.contains { $0.addState.blocksVirtualTargetSingleAdd }
    }

    private func canStartVirtualTargetAdd() -> Bool {
        guard isVirtualAddTarget else {
            return true
        }
        return !virtualTargetAddLocked
    }
```

- [ ] **Step 3: Disable Classic row buttons while locked**

In `tableView(_:cellForRowAt:)`, after `cell.device = device`, add:

```swift
        if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
            cell.addBtn.isEnabled = false
        }
```

The cell body should include:

```swift
        cell.hidesSelectionControl = hidesBatchSelectionControls
        cell.device = device
        if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
            cell.addBtn.isEnabled = false
        }
        cell.delegate = self
        return cell
```

- [ ] **Step 4: Refresh table when lock-affecting UI state changes**

In `updateUIState()`, after the `switch state { ... }` block and before the method returns, add:

```swift
        tableView.visibleCells.forEach { cell in
            guard let cell = cell as? DeviceAddViewCell,
                  let indexPath = tableView.indexPath(for: cell),
                  let device = showDevices[safe: indexPath.row] else {
                return
            }
            cell.hidesSelectionControl = hidesBatchSelectionControls
            cell.device = device
            if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
                cell.addBtn.isEnabled = false
            }
        }
```

This keeps visible rows in sync when the first device changes to `.addConnecting` or `.success`.

- [ ] **Step 5: Guard Classic single add**

In `cell(_:deviceAdd:)`, after the `state == .scanning` guard and before the max-device-count guard, add:

```swift
        guard canStartVirtualTargetAdd() else {
            return
        }
```

The sequence should read:

```swift
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_add".localizedString)
            return
        }
        guard canStartVirtualTargetAdd() else {
            return
        }
        // space只能添加200个设备
```

- [ ] **Step 6: Verify Classic lock hooks**

Run:

```bash
rg -n "virtualTargetAddLocked|canStartVirtualTargetAdd|blocksVirtualTargetSingleAdd" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: output shows helper definitions, cell disable logic, visible-cell refresh, and single-add guard.

- [ ] **Step 7: Commit Classic lock**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
git commit -m "fix: lock classic virtual target adds"
```

Expected: commit succeeds with only `DeviceAddClassicModeController.swift` staged.

## Task 5: Lock Professional Virtual Target Adds

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Inspect Professional hooks**

Run:

```bash
sed -n '160,185p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
sed -n '672,686p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
sed -n '2260,2300p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
sed -n '2408,2438p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
sed -n '2604,2618p' SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output shows `isVirtualAddTarget`, `syncCandidateTargetState`, main-list `cellForRowAt`, main-list `cell(_:deviceAdd:)`, and candidate `startAdd`.

- [ ] **Step 2: Add Professional lock helpers**

After `hidesBatchSelectionControls`, add:

```swift
    private var virtualTargetAddLocked: Bool {
        guard isVirtualAddTarget else {
            return false
        }
        return (scanDevices + candidateDevices).contains {
            $0.addState.blocksVirtualTargetSingleAdd
        }
    }

    private func canStartVirtualTargetAdd() -> Bool {
        guard isVirtualAddTarget else {
            return true
        }
        return !virtualTargetAddLocked
    }
```

- [ ] **Step 3: Sync lock to Candidate Device List**

In `syncCandidateTargetState()`, after `candidateView.hidesSelectionControls = hidesBatchSelectionControls`, add:

```swift
        candidateView.virtualTargetAddLocked = virtualTargetAddLocked
```

The target state sync should include:

```swift
        candidateView.addTarget = addTarget
        candidateView.addTargetNameOverride = addTargetNameOverride
        candidateView.hidesSelectionControls = hidesBatchSelectionControls
        candidateView.virtualTargetAddLocked = virtualTargetAddLocked
        candidateView.lockedCategorySelectionTip = forbiddenSelectionTip
```

- [ ] **Step 4: Keep Candidate lock updated on UI changes**

In `updateUIState()`, after `candidateView.state = state`, add:

```swift
        candidateView.virtualTargetAddLocked = virtualTargetAddLocked
```

- [ ] **Step 5: Disable Professional main-list row buttons while locked**

In Professional main-list `tableView(_:cellForRowAt:)`, after `cell.device = device`, add:

```swift
            if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
                cell.addBtn.isEnabled = false
            }
```

The relevant cell body should include:

```swift
            cell.hidesSelectionControl = hidesBatchSelectionControls
            cell.device = device
            if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
                cell.addBtn.isEnabled = false
            }
            cell.selectionStyle = .none
            cell.addBtn.setImage(UIImage(named: "device_add_candidate"), for: .normal)
```

If setting `cell.addBtn.setImage` comes after the disable check in the current file, keep the image setup and put the disable check after image setup so `isEnabled` remains false.

- [ ] **Step 6: Guard Professional main-list candidate action**

In `cell(_:deviceAdd:)`, after the disabled-state guard and before the `isSingleSelectionMode` branch, add:

```swift
        guard canStartVirtualTargetAdd() else {
            return
        }
```

The sequence should read:

```swift
        if device.selectedState == .disabled {
            showDisabledDeviceTip(device)
            return
        }
        guard canStartVirtualTargetAdd() else {
            return
        }
        // 单选模式下候选列表只保留一个设备，默认业务仍复用原有候选流程。
```

- [ ] **Step 7: Guard Professional Candidate start-add**

In `candidateView(_:startAdd:)`, after `devicesToAdd` is calculated and before `guard !devicesToAdd.isEmpty`, add:

```swift
        guard canStartVirtualTargetAdd() else {
            return
        }
```

The method should start:

```swift
    func candidateView(_ view: DeviceAddCandidateDeviceListView, startAdd devices: [ProvisioningDevice]) {
        let selectableDevices = devices.filter { $0.selectedState != .disabled && isSelectableDevice($0) }
        let devicesToAdd = isSingleSelectionMode ? Array(selectableDevices.prefix(1)) : selectableDevices
        guard canStartVirtualTargetAdd() else {
            return
        }
        guard !devicesToAdd.isEmpty else {
            return
        }
        checkDeviceAddressesAreSufficient(devices: devicesToAdd)
    }
```

- [ ] **Step 8: Verify Professional lock hooks**

Run:

```bash
rg -n "virtualTargetAddLocked|canStartVirtualTargetAdd|blocksVirtualTargetSingleAdd" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output shows helper definitions, Candidate sync, UI-state update, main-list disable logic, main-list guard, and Candidate start-add guard.

- [ ] **Step 9: Commit Professional lock**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: lock professional virtual target adds"
```

Expected: commit succeeds with only `DeviceAddProfessionalModeController.swift` staged.

## Task 6: Static Verification And Build

**Files:**
- Verify only.

- [ ] **Step 1: Verify no uncommitted changes before final checks**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 2: Verify AC normalization and virtual target helper coverage**

Run:

```bash
rg -n "proxyMatchesKind|isACPowerSwitch|isBatteryPowerSwitch|displayStatus\\.isVirtualSwitch|unboundVirtualPowerSwitchAddTargets" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output shows AC and battery proxy validation in `MeshNetwork+SunSmart.swift`, and target collection still uses `displayStatus.isVirtualSwitch` through `unboundVirtualPowerSwitchAddTargets`.

- [ ] **Step 3: Verify all add-lock entrances**

Run:

```bash
rg -n "virtualTargetAddLocked|canStartVirtualTargetAdd|blocksVirtualTargetSingleAdd" SunSmart/Main/Device/Model/ProvisioningDevice+Add.swift SunSmart/Main/Device/View/DeviceAddCandidateDeviceListView.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: output shows the shared helper plus lock usage in Candidate, Classic, and Professional.

- [ ] **Step 4: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build exits 0. Warnings may appear; no compile errors.

- [ ] **Step 5: Commit verification note only if code changed during verification**

If build fixes required edits, commit those edits with:

```bash
git add <changed-files>
git commit -m "fix: finish virtual target add lock"
```

Expected: no commit is needed if Task 1-5 already pass build.

