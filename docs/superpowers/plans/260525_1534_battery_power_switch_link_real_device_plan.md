# Battery Power Switch Link Real Device Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现虚拟 Battery Power Switch 通过 `LINK` 绑定真实 Battery Power Switch，并按虚拟设备当前配置完成自身配置与后续同步。

**Architecture:** 在现有添加设备流程中扩展 `AddDeviceBindTarget`，让 LINK 流程携带目标虚拟 BPS，并在 Classic / Professional 添加路径中复用同一套绑定逻辑。普通新增真实 BPS 继续按 PID 创建默认 profile；LINK 场景只用 PID 判断合法设备，目标 profile、Enable、LED 和 groups/scenes 全部来自虚拟 BPS 当前配置。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Mesh provisioning / SyncDevices 流程、现有 `PJEightKeySwitchData` / `BatteryPowerSwitchAddConfiguration`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
  - 扩展 `AddDeviceBindTarget`，增加 BPS 绑定目标、扫描设备判断、node 判断和绑定完成关闭逻辑。
- Modify: `SunSmart/Main/Device/Device1.5/Common/Flow/PJDevicesAddEntryContext.swift`
  - 给添加入口 context 增加 `bindTarget`，并提供默认值，保持现有调用兼容。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Add/Controller/PJDevicesEightKeyAddContainerController.swift`
  - 将 `bindTarget` 透传到老添加控制器。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 增加“绑定已有虚拟 BPS”的 prepare 方法、错误类型和 LINK 场景配置 message handles。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - Classic 添加路径识别 BPS bind target，限制可选设备，并在 append messages 阶段绑定已有虚拟 BPS。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - Professional 添加路径做与 Classic 相同的绑定接入。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - LINK 前保存当前编辑态，传入 BPS bind target，添加完成后刷新编辑页并触发 target group 同步。

---

### Task 1: Add Bind Target Plumbing

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
- Modify: `SunSmart/Main/Device/Device1.5/Common/Flow/PJDevicesAddEntryContext.swift`
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Add/Controller/PJDevicesEightKeyAddContainerController.swift`

- [ ] **Step 1: Replace `AddDeviceBindTarget` with a BPS-aware enum**

In `DeviceAddViewController.swift`, replace the complete `AddDeviceBindTarget` enum with:

```swift
/// 添加后需要绑定到的外部业务对象。
enum AddDeviceBindTarget {
    case emergencyFire(DeviceEmerFireData)
    case batteryPowerSwitch(PJEightKeySwitchData)

    var name: String {
        switch self {
        case .emergencyFire(let device):
            return device.name
        case .batteryPowerSwitch(let switchData):
            return switchData.name
        }
    }

    var allowedDeviceTypes: [Node.DeviceType] {
        switch self {
        case .emergencyFire:
            return [.emergencyController]
        case .batteryPowerSwitch:
            return [.switches]
        }
    }

    var shouldCloseAfterBinding: Bool {
        switch self {
        case .emergencyFire, .batteryPowerSwitch:
            return true
        }
    }

    func allows(_ device: ProvisioningDevice) -> Bool {
        switch self {
        case .emergencyFire:
            return device.deviceType == .emergencyController
        case .batteryPowerSwitch:
            return device.isBatteryPowerSwitch
        }
    }

    func allows(_ node: Node) -> Bool {
        switch self {
        case .emergencyFire:
            return node.deviceType == .emergencyController
        case .batteryPowerSwitch:
            return node.isBatteryPowerSwitch
        }
    }
}
```

- [ ] **Step 2: Update binding close and filtering logic**

In `DeviceAddViewController.swift`, replace `shouldCloseAfterBinding` with:

```swift
private var shouldCloseAfterBinding: Bool {
    bindTarget?.shouldCloseAfterBinding == true
}
```

Replace `handleDeviceAddCallback(nodes:)` with:

```swift
private func handleDeviceAddCallback(nodes: [Node]) {
    addSuccessNodes.append(contentsOf: nodes)
    guard !didNotifyDeviceAddCallback,
          shouldCloseAfterBinding,
          let bindTarget,
          nodes.contains(where: { bindTarget.allows($0) }) else {
        return
    }
    finishBindingFlowIfNeeded()
}
```

Replace the first two lines inside `finishBindingFlowIfNeeded()` that compute `boundNodes` with:

```swift
guard let bindTarget else {
    return
}
let boundNodes = addSuccessNodes.filter { bindTarget.allows($0) }
```

Add this helper inside `DeviceAddViewController`, below `finishBindingFlowIfNeeded()`:

```swift
private func closeBindingFlow(animated: Bool, completion: @escaping () -> Void) {
    let hostController = parent ?? self
    if let navigationController = hostController.navigationController,
       navigationController.viewControllers.last === hostController,
       navigationController.viewControllers.first !== hostController {
        navigationController.popViewController(animated: animated)
        completion()
    } else {
        hostController.dismiss(animated: animated, completion: completion)
    }
}
```

In `finishBindingFlowIfNeeded()`, replace:

```swift
dismiss(animated: true) {
    callback?(addedNodes)
}
```

with:

```swift
closeBindingFlow(animated: true) {
    callback?(addedNodes)
}
```

- [ ] **Step 3: Add `bindTarget` to add entry context**

Replace `PJDevicesAddEntryContext` in `PJDevicesAddEntryContext.swift` with:

```swift
struct PJDevicesAddEntryContext {
    let source: PJDevicesEntrySource
    let space: SpaceData
    let title: String?
    let appointGroup: Group?
    let bindTarget: AddDeviceBindTarget?
    let addBehavior: PJDevicesAddBehavior?

    init(
        source: PJDevicesEntrySource,
        space: SpaceData,
        title: String?,
        appointGroup: Group?,
        bindTarget: AddDeviceBindTarget? = nil,
        addBehavior: PJDevicesAddBehavior?
    ) {
        self.source = source
        self.space = space
        self.title = title
        self.appointGroup = appointGroup
        self.bindTarget = bindTarget
        self.addBehavior = addBehavior
    }
}
```

- [ ] **Step 4: Pass `bindTarget` through the eight-key add container**

In `PJDevicesEightKeyAddContainerController.swift`, inside `viewDidLoad()`, after `vc.appointGroup = context.appointGroup`, add:

```swift
vc.bindTarget = context.bindTarget
```

- [ ] **Step 5: Verify compile surface for Task 1**

Run:

```bash
rg -n "batteryPowerSwitch\\(|bindTarget = context.bindTarget|func allows\\(_ device: ProvisioningDevice\\)|func allows\\(_ node: Node\\)" SunSmart/Main/Device
```

Expected:

- `AddDeviceBindTarget` contains the BPS case and both `allows` methods.
- `PJDevicesEightKeyAddContainerController` passes `context.bindTarget`.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Device1.5/Common/Flow/PJDevicesAddEntryContext.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Add/Controller/PJDevicesEightKeyAddContainerController.swift
git commit -m "feat: pass battery switch bind target"
```

---

### Task 2: Add Battery Power Switch Link Preparation

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Add a link preparation error type**

Inside `BatteryPowerSwitchAddConfiguration`, below `enum BatteryPowerSwitchAddConfiguration {`, add:

```swift
    enum LinkPreparationError: Error {
        case unsupportedNode
        case alreadyLinked(String)
        case insufficientGroupAddress

        var message: String {
            switch self {
            case .unsupportedNode:
                return "Cannot add, type mismatch"
            case .alreadyLinked(let name):
                return String(format: "switch_proxy_exist".localizedString, name)
            case .insufficientGroupAddress:
                return "group_address_insufficient_message".localizedString
            }
        }
    }
```

- [ ] **Step 2: Add linked switch preparation**

Inside `BatteryPowerSwitchAddConfiguration`, below `prepareSwitchData(for:)`, add:

```swift
    static func prepareLinkedSwitchData(
        sourceSwitchData: PJEightKeySwitchData,
        node: Node
    ) -> Result<PJEightKeySwitchData, LinkPreparationError> {
        guard isSupportedAddNode(node) else {
            return .failure(.unsupportedNode)
        }

        if let existingSwitch = MeshNetworkManager.instance.switchs.first(where: {
            $0.id != sourceSwitchData.id && $0.proxyNodeAddress == node.primaryUnicastAddress
        }) {
            return .failure(.alreadyLinked(existingSwitch.name))
        }

        let switchData = sourceSwitchData.copy()
        switchData.proxyNodeAddress = node.primaryUnicastAddress
        switchData.maxKeyCount = 8
        switchData.panelType = switchData.eightKeyPanelType == .scene8Key ? .scenes_4key : .default_4key
        switchData.subLinkGroupAddress = nil

        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            return .failure(.insufficientGroupAddress)
        }

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        switchData.appliedConfigHash = ""
        switchData.lastSyncFailedReason = nil
        return .success(switchData)
    }
```

- [ ] **Step 3: Add LINK configuration message handles**

Inside `BatteryPowerSwitchAddConfiguration`, below `defaultConfigurationMessageHandles(for:node:)`, add:

```swift
    static func linkedConfigurationMessageHandles(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> [MeshMessageHandle] {
        guard isSupportedAddNode(node),
              node.primaryUnicastAddress == switchData.proxyNodeAddress,
              let vendorModel = node.sunricherVendorModel else {
            return []
        }

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        var handles = switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
            let handle = MeshMessageHandle(
                message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)),
                model: vendorModel
            )
            handle.continuous = false
            return handle
        }

        let txHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(switchData.enabled)),
            model: vendorModel
        )
        txHandle.continuous = false
        handles.append(txHandle)

        let ledHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(switchData.moreSettingsState.ledIndicatorEnabled)),
            model: vendorModel
        )
        ledHandle.continuous = false
        handles.append(ledHandle)

        return handles
    }
```

- [ ] **Step 4: Verify Task 2 statically**

Run:

```bash
rg -n "LinkPreparationError|prepareLinkedSwitchData|linkedConfigurationMessageHandles|batteryPowerSwitchTxEnabled|batteryPowerSwitchLEDEnabled" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- The new error type exists.
- The linked prepare method exists.
- LINK handles include Key Config, TX Enable, and LED Indicator.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "feat: prepare linked battery switch config"
```

---

### Task 3: Integrate Classic And Professional Add Flows

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Add BPS bind helpers to both add controllers**

In both `DeviceAddClassicModeController.swift` and `DeviceAddProfessionalModeController.swift`, add this property near `bindToEmerFire`:

```swift
    private var bindToBatteryPowerSwitch: PJEightKeySwitchData? {
        if case .batteryPowerSwitch(let switchData) = bindTarget {
            return switchData
        }
        return nil
    }
```

In both files, add this dictionary near `failedBatteryPowerSwitchAddConfigurationAddresses`:

```swift
    private var failedBatteryPowerSwitchAddConfigurationReasons: [Address: String] = [:]
```

- [ ] **Step 2: Add provisioning-device selection helper in both controllers**

In both files, add these helpers near `isSelectableDeviceType(_:)`:

```swift
    private func isAllowedDevice(_ device: ProvisioningDevice) -> Bool {
        if let bindTarget {
            return bindTarget.allows(device)
        }
        return isAllowedDeviceType(device.deviceType)
    }

    private func isBlockedDevice(_ device: ProvisioningDevice) -> Bool {
        if let bindTarget {
            return !bindTarget.allows(device)
        }
        return isBlockedDeviceType(device.deviceType)
    }

    private func isSelectableDevice(_ device: ProvisioningDevice) -> Bool {
        isAllowedDevice(device) && !isBlockedDevice(device)
    }
```

In both files, replace the Battery Power Switch limit check at the top of `applySelectableState(to:)` with:

```swift
        if bindToBatteryPowerSwitch == nil,
           device.isBatteryPowerSwitch,
           MeshNetworkManager.instance.switchs.count >= 16 {
            device.selectedState = .disabled
            return
        }
```

In both files, replace the selectable check inside `applySelectableState(to:)` with:

```swift
        if isSelectableDevice(device) {
            if device.selectedState == .disabled {
                device.selectedState = .unselected
            }
        } else {
            device.selectedState = .disabled
        }
```

- [ ] **Step 3: Skip new-switch count limits for BPS LINK**

In both files, replace `isBatteryPowerSwitchLimitExceeded(for:)` with:

```swift
    private func isBatteryPowerSwitchLimitExceeded(for devices: [ProvisioningDevice]) -> Bool {
        guard bindToBatteryPowerSwitch == nil else {
            return false
        }
        let batteryPowerSwitchCount = devices.filter { $0.isBatteryPowerSwitch }.count
        return batteryPowerSwitchCount > 0 && MeshNetworkManager.instance.switchs.count + batteryPowerSwitchCount > 16
    }
```

- [ ] **Step 4: Replace BPS append-message preparation in both controllers**

In both files, find the block that starts with:

```swift
if BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node),
   let switchData = BatteryPowerSwitchAddConfiguration.prepareSwitchData(for: node) {
```

Replace that entire BPS block with:

```swift
            if BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) {
                if let bindToBatteryPowerSwitch {
                    switch BatteryPowerSwitchAddConfiguration.prepareLinkedSwitchData(
                        sourceSwitchData: bindToBatteryPowerSwitch,
                        node: node
                    ) {
                    case .success(let switchData):
                        batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] = switchData
                        let handles = BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(
                            for: switchData,
                            node: node
                        )
                        if handles.isEmpty {
                            failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
                            failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress] = "sync_failed".localizedString
                        } else {
                            appendMessages.append(contentsOf: handles)
                        }
                    case .failure(let error):
                        failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
                        failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress] = error.message
                    }
                } else if let switchData = BatteryPowerSwitchAddConfiguration.prepareSwitchData(for: node) {
                    batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] = switchData
                    let handles = BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(
                        for: switchData,
                        node: node
                    )
                    if handles.isEmpty {
                        failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
                        failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress] = "sync_failed".localizedString
                    } else {
                        appendMessages.append(contentsOf: handles)
                    }
                }
            }
```

- [ ] **Step 5: Preserve virtual BPS when LINK preparation did not produce switch data**

In both files, replace the fallback `guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] else` block inside `finalizeBatteryPowerSwitchAddConfiguration(for:)` with:

```swift
        guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] else {
            if bindToBatteryPowerSwitch != nil {
                failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
                failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
                return
            }

            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
            }
            return
        }
```

Then replace the failure branch in `finalizeBatteryPowerSwitchAddConfiguration(for:)` with:

```swift
        if failedBatteryPowerSwitchAddConfigurationAddresses.contains(node.primaryUnicastAddress) {
            BatteryPowerSwitchAddConfiguration.markFailed(
                switchData,
                reason: failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress]
                    ?? switchData.lastSyncFailedReason
                    ?? "sync_failed".localizedString
            )
        } else {
            BatteryPowerSwitchAddConfiguration.markSucceeded(switchData)
        }
```

At the end of `finalizeBatteryPowerSwitchAddConfiguration(for:)`, after removing the address from `failedBatteryPowerSwitchAddConfigurationAddresses`, add:

```swift
        failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
```

- [ ] **Step 6: Record BPS append-message failures with reasons**

In both files, inside `appendMessageFailedBack`, replace:

```swift
self.failedBatteryPowerSwitchAddConfigurationAddresses.insert(address)
```

with:

```swift
self.failedBatteryPowerSwitchAddConfigurationAddresses.insert(address)
self.failedBatteryPowerSwitchAddConfigurationReasons[address] = "sync_failed".localizedString
```

- [ ] **Step 7: Replace provisioning-device filters that only use device type**

In `DeviceAddProfessionalModeController.swift`, replace:

```swift
self.isSelectableDeviceType(newDevice.deviceType)
```

with:

```swift
self.isSelectableDevice(newDevice)
```

In `DeviceAddProfessionalModeController.swift`, replace each filter fragment:

```swift
self.isSelectableDeviceType(device.deviceType)
```

with:

```swift
self.isSelectableDevice(device)
```

Run:

```bash
rg -n "isSelectableDeviceType\\((newDevice|device)\\.deviceType\\)" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected: no matches.

In `DeviceAddClassicModeController.swift`, replace:

```swift
if isAllowedDeviceType(device.deviceType) && !isBlockedDeviceType(device.deviceType) {
```

with:

```swift
if isSelectableDevice(device) {
```

Then run:

```bash
rg -n "isAllowedDeviceType\\(device\\.deviceType\\)|isBlockedDeviceType\\(device\\.deviceType\\)" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected: no matches in code paths that receive a `ProvisioningDevice`.

- [ ] **Step 8: Verify Task 3 statically**

Run:

```bash
rg -n "bindToBatteryPowerSwitch|failedBatteryPowerSwitchAddConfigurationReasons|prepareLinkedSwitchData|linkedConfigurationMessageHandles|isSelectableDevice\\(_ device: ProvisioningDevice\\)|guard bindToBatteryPowerSwitch == nil" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Both add controllers contain the BPS bind target helper.
- Both add controllers use `prepareLinkedSwitchData` and `linkedConfigurationMessageHandles`.
- Both add controllers preserve failure reasons.
- Both add controllers skip new-switch count limits when `bindToBatteryPowerSwitch` is present.

- [ ] **Step 9: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "feat: link virtual battery switch during add"
```

---

### Task 4: Wire LINK From The Battery Switch Editor

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Add editor validation helper**

In `PJPreAddEightKeySwitchesVC.swift`, add this method near `submitAction()`:

```swift
    private func validateEditorInput() -> Bool {
        if viewModel.sourceSwitchData == nil, MeshNetworkManager.instance.switchs.count >= 16 {
            SRAlertView(
                title: "notification".localizedString,
                message: "switchs_overrun_message".localizedString,
                actions: [SRAlertAction(title: "GOT_IT".localizedString)]
            ).show()
            return false
        }

        guard !viewModel.deviceName.isAllInputTextEmpty() else {
            XWHUDManager.showTipHUD("name_empty".localizedString, isLineFeed: true)
            return false
        }

        guard !(MeshNetworkManager.instance.isSwitchTautonym(name: viewModel.deviceName) && viewModel.deviceName != viewModel.sourceSwitchData?.name) else {
            XWHUDManager.showTipHUD("name_already_exists".localizedString, isLineFeed: true)
            return false
        }

        return true
    }
```

Then replace the duplicate validation block at the top of `submitAction()` with:

```swift
        guard validateEditorInput() else {
            return
        }
```

- [ ] **Step 2: Add LINK preparation helper**

Add this method near `linkAction()`:

```swift
    private func prepareSwitchDataForLink() -> PJEightKeySwitchData? {
        view.endEditing(true)
        guard validateEditorInput() else {
            return nil
        }

        let switchData = viewModel.buildSwitchData()
        guard !hasRealDeviceLink(switchData) else {
            refreshEditingStateFromCurrentSwitchData()
            return currentEightKeySwitchData
        }

        if switchData.linkGroupAddress == nil,
           MeshAPI.getAvailableGroupAddresses(meshUUID: viewModel.space.meshUUID, subnetworkId: viewModel.space.meshNetworkId).isEmpty {
            XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
            return nil
        }

        guard persistSwitchData(switchData) else {
            showSaveFailedTip()
            return nil
        }

        switchSavedAction?(switchData)
        postSwitchDataChangedNotifications()
        initialSnapshot = makeSnapshot()
        refreshEditingStateFromCurrentSwitchData()
        return currentEightKeySwitchData ?? switchData
    }
```

- [ ] **Step 3: Replace `linkAction()`**

Replace the complete `linkAction()` method with:

```swift
    @objc private func linkAction() {
        guard let switchData = prepareSwitchDataForLink() else {
            return
        }

        let context = PJDevicesAddEntryContext(
            source: .eightKeySwitch,
            space: viewModel.space,
            title: "add_device".localizedString,
            appointGroup: nil,
            bindTarget: .batteryPowerSwitch(switchData),
            addBehavior: .init(
                allowsTargetSelection: false,
                allowsCategorySelection: false,
                allowedTypes: [.switches],
                blockedDeviceTypes: [],
                selectionMode: .single,
                forbiddenSelectionTip: "You can't choose other devices.",
                forbiddenDeviceTypeTip: "Cannot add, type mismatch"
            )
        )
        let controller = PJDevicesAddFlowFactory.make(context: context)
        if let legacyController = controller as? PJDevicesLegacyContainerController {
            legacyController.deviceAddCallback = { [weak self] _ in
                self?.handleBatteryPowerSwitchLinkCompleted()
            }
        }
        navigationController?.pushViewController(controller, animated: true)
    }
```

- [ ] **Step 4: Add LINK completion handler**

Add this method near `refreshEditingStateFromCurrentSwitchData()`:

```swift
    private func handleBatteryPowerSwitchLinkCompleted() {
        refreshEditingStateFromCurrentSwitchData()
        guard let switchData = currentEightKeySwitchData else {
            return
        }

        guard switchData.syncState == .synced else {
            return
        }

        guard switchData.needSyncData else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            return
        }

        pushBatteryPowerSwitchSync(switchData)
    }
```

- [ ] **Step 5: Verify Task 4 statically**

Run:

```bash
rg -n "prepareSwitchDataForLink|batteryPowerSwitch\\(switchData\\)|handleBatteryPowerSwitchLinkCompleted|validateEditorInput" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- LINK action passes `.batteryPowerSwitch(switchData)`.
- LINK completion refreshes edit state.
- LINK completion pushes existing BPS sync when target group data needs syncing.

- [ ] **Step 6: Commit Task 4**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "feat: link battery switch from editor"
```

---

### Task 5: Build And Regression Verification

**Files:**
- No source edits expected.

- [ ] **Step 1: Verify no second BPS creation in LINK path**

Run:

```bash
rg -n "prepareSwitchData\\(for: node\\)|prepareLinkedSwitchData|createDefaultSwitch\\(forBatteryPowerSwitch" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- `prepareLinkedSwitchData` is used only inside the bind target branch.
- `prepareSwitchData(for:)` remains available for ordinary BPS add.
- `createDefaultSwitch(forBatteryPowerSwitch:)` is not changed into the LINK implementation path.

- [ ] **Step 2: Verify PID still only controls ordinary default profile**

Run:

```bash
rg -n "batteryPowerSwitchPanelType|case 0x2A01|case 0x2A02|eightKeyPanelType" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- `Node.batteryPowerSwitchPanelType` still maps `0x2A01` to Scene and `0x2A02` to Brightness.
- LINK preparation does not read `node.batteryPowerSwitchPanelType` to override `sourceSwitchData.eightKeyPanelType`.

- [ ] **Step 3: Verify BPS LINK message coverage**

Run:

```bash
rg -n "batteryPowerSwitchKeyConfig|batteryPowerSwitchTxEnabled|batteryPowerSwitchLEDEnabled" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- `linkedConfigurationMessageHandles` includes all three own configuration message types.

- [ ] **Step 4: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build exits with status `0`.
- Output contains `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Inspect final diff**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected:

- Only expected source files are modified if Task 5 is running before the final commit.
- No localization, resource, target configuration, dependency, or unrelated formatting changes appear.

- [ ] **Step 6: Commit verification-only adjustments if any source changed during verification**

If Task 5 required a compile fix, commit only that fix:

```bash
git add SunSmart/Main/Device/Controller/DeviceAddViewController.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/Device1.5/Common/Flow/PJDevicesAddEntryContext.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Add/Controller/PJDevicesEightKeyAddContainerController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "fix: stabilize battery switch link flow"
```

Expected:

- A commit is created only when verification required an additional source fix.
- If no source changed during verification, no commit is created in this step.

---

## Manual QA Checklist

- [ ] 虚拟 BPS 为 `Scene Panel (8 key)`，LINK 到 PID `0x2A01`，成功绑定并下发 Scene 配置。
- [ ] 虚拟 BPS 为 `Scene Panel (8 key)`，LINK 到 PID `0x2A02`，允许绑定，仍下发 Scene 配置。
- [ ] 虚拟 BPS 为 `Brightness Panel (8 key)`，LINK 到 PID `0x2A01`，允许绑定，仍下发 Brightness 配置。
- [ ] 虚拟 BPS 为 `Brightness Panel (8 key)`，LINK 到 PID `0x2A02`，成功绑定并下发 Brightness 配置。
- [ ] 虚拟 BPS Enable Off，LINK 后下发 TX Enable false，保存后详情页 Enable 为 Off。
- [ ] 虚拟 BPS LED Indicator Off，LINK 后下发 LED false，保存后 More Settings 保持 Off。
- [ ] 虚拟 BPS 已选择 groups，LINK 后自身配置成功，再进入 target subscription sync。
- [ ] 真实 BPS node 已被其他 BPS 绑定时，阻止绑定，不覆盖原数据。
- [ ] 普通 site 添加真实 BPS，仍按 PID 默认 profile 新建，不受 LINK 逻辑影响。
