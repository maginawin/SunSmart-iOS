# Battery Power Switch Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `Restore Device Data` 在恢复 Battery Power Switch 时复用旧虚拟组，把旧 BPS 配置直接下发给新入网 BPS，并保持其它设备恢复流程不变。

**Architecture:** 在 `BatteryPowerSwitchAddConfiguration` 增加 BPS restore preparation helper，专门负责用旧 switch 数据生成恢复后的 switch 数据和本体配置消息。`DeviceRestoreViewController` 在现有恢复流程中识别旧 BPS 业务记录和新 BPS node，只在 append messages 阶段下发 Key Config / TX / LED，不迁移 target group subscription。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SQLite repository, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 新增 BPS restore preparation error 和 helper。
  - 新增 restore configuration message helper。
  - 扩展 `markSucceeded`，允许恢复成功时不清空 `unbindGroupAddresses`。

- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - 增加 BPS restore pending state。
  - 用旧 node 地址定位旧 `PJEightKeySwitchData`。
  - 在 add append messages 阶段下发 BPS 本体配置。
  - 在 add success 阶段持久化恢复结果。
  - 在 add finish 阶段复用 BPS 电量读取与断连 helper。

- Verify only: `docs/superpowers/specs/2026-05-26-battery-power-switch-restore-design.md`
  - 作为需求和验收标准来源，不修改。

---

### Task 1: Add Battery Power Switch Restore Helper

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Run static check to prove restore helper is absent**

Run:

```bash
rg -n "RestorePreparationError|prepareRestoreSwitchData|restoreConfigurationMessageHandles|markSucceeded\\(_ switchData: PJEightKeySwitchData, clearRemovedGroups" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected: no matches.

- [ ] **Step 2: Add restore preparation error**

In `BatteryPowerSwitchAddConfiguration.swift`, insert this enum after `LinkPreparationError`:

```swift
    enum RestorePreparationError: Error {
        case unsupportedNode
        case alreadyLinked(String)
        case missingLinkGroup

        var message: String {
            switch self {
            case .unsupportedNode:
                return "Cannot add, type mismatch"
            case .alreadyLinked(let name):
                return String(format: "switch_proxy_exist".localizedString, name)
            case .missingLinkGroup:
                return "group_address_insufficient_message".localizedString
            }
        }
    }
```

- [ ] **Step 3: Add restore switch data preparation helper**

In `BatteryPowerSwitchAddConfiguration.swift`, insert this method after `prepareLinkedSwitchData(sourceSwitchData:node:)`:

```swift
    static func prepareRestoreSwitchData(
        sourceSwitchData: PJEightKeySwitchData,
        node: Node
    ) -> Result<PJEightKeySwitchData, RestorePreparationError> {
        guard isSupportedAddNode(node) else {
            return .failure(.unsupportedNode)
        }

        if let existingSwitch = MeshNetworkManager.instance.switchs.first(where: {
            $0.id != sourceSwitchData.id && $0.proxyNodeAddress == node.primaryUnicastAddress
        }) {
            return .failure(.alreadyLinked(existingSwitch.name))
        }

        guard sourceSwitchData.linkGroupAddress != nil else {
            return .failure(.missingLinkGroup)
        }

        let switchData = sourceSwitchData.copy()
        switchData.proxyNodeAddress = node.primaryUnicastAddress
        switchData.maxKeyCount = 8
        switchData.subLinkGroupAddress = nil
        switchData.batteryLevel = nil
        switchData.batteryLastUpdateTime = nil
        switchData.appliedConfigHash = ""
        switchData.appliedTxEnabled = nil
        switchData.appliedLEDIndicatorEnabled = nil
        switchData.lastSyncFailedReason = nil

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        return .success(switchData)
    }
```

- [ ] **Step 4: Add restore configuration message helper**

In `BatteryPowerSwitchAddConfiguration.swift`, insert this method after `linkedConfigurationMessageHandles(for:node:)`:

```swift
    static func restoreConfigurationMessageHandles(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> [MeshMessageHandle] {
        linkedConfigurationMessageHandles(for: switchData, node: node)
    }
```

- [ ] **Step 5: Extend markSucceeded without changing existing callers**

Replace the current `markSucceeded(_:)` method with:

```swift
    @discardableResult
    static func markSucceeded(_ switchData: PJEightKeySwitchData, clearRemovedGroups: Bool = true) -> Bool {
        switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: clearRemovedGroups)
        return persist(switchData)
    }
```

Existing normal add and LINK callers keep the default `clearRemovedGroups: true`. BPS restore will call `clearRemovedGroups: false`.

- [ ] **Step 6: Run static check for helper additions**

Run:

```bash
rg -n "RestorePreparationError|prepareRestoreSwitchData|restoreConfigurationMessageHandles|markSucceeded\\(_ switchData: PJEightKeySwitchData, clearRemovedGroups" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- `RestorePreparationError` appears once as the enum declaration.
- `prepareRestoreSwitchData` appears once as a method declaration.
- `restoreConfigurationMessageHandles` appears once as a method declaration.
- `markSucceeded(_ switchData: PJEightKeySwitchData, clearRemovedGroups: Bool = true)` appears once.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "feat: prepare battery switch restore data"
```

---

### Task 2: Wire BPS Restore Into DeviceRestoreViewController

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Run static check to prove restore controller has no BPS restore state**

Run:

```bash
rg -n "pendingBatteryPowerSwitchInitialBatteryReads|batteryPowerSwitchRestoreConfigurations|prepareBatteryPowerSwitchRestoreConfiguration|finalizeBatteryPowerSwitchRestoreConfiguration|finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected: no matches.

- [ ] **Step 2: Add BPS restore state properties**

In `DeviceRestoreViewController.swift`, add these properties near `private var restoreNodes: [Node] = []`:

```swift
    private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
    private var batteryPowerSwitchRestoreConfigurations: [Address: PJEightKeySwitchData] = [:]
    private var failedBatteryPowerSwitchRestoreAddresses: Set<Address> = []
    private var failedBatteryPowerSwitchRestoreReasons: [Address: String] = [:]
```

- [ ] **Step 3: Add helper to finish BPS battery read and disconnect**

In `DeviceRestoreViewController.swift`, insert this helper before `// MARK: - Device Restore`:

```swift
    private func finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(fallbackDisconnectNodes: [Node]) {
        let requests = pendingBatteryPowerSwitchInitialBatteryReads
        pendingBatteryPowerSwitchInitialBatteryReads.removeAll()
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelsAndDisconnect(
            requests,
            fallbackDisconnectNodes: fallbackDisconnectNodes
        )
    }
```

- [ ] **Step 4: Add helper to locate old BPS data**

In `DeviceRestoreViewController.swift`, insert this helper after `finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(fallbackDisconnectNodes:)`:

```swift
    private func batteryPowerSwitchData(boundTo oldNode: Node) -> PJEightKeySwitchData? {
        guard let switchData = MeshNetworkManager.instance.switchs.first(where: {
            $0.proxyNodeAddress == oldNode.primaryUnicastAddress
        }) else {
            return nil
        }
        return switchData.batteryPowerSwitchData
    }
```

- [ ] **Step 5: Add helper to prepare BPS restore append messages**

In `DeviceRestoreViewController.swift`, insert this helper after `batteryPowerSwitchData(boundTo:)`:

```swift
    private func prepareBatteryPowerSwitchRestoreConfiguration(
        oldNode: Node,
        newNode: Node,
        appendMessages: inout [MeshMessageHandle]
    ) {
        guard let sourceSwitchData = batteryPowerSwitchData(boundTo: oldNode) else {
            return
        }

        switch BatteryPowerSwitchAddConfiguration.prepareRestoreSwitchData(
            sourceSwitchData: sourceSwitchData,
            node: newNode
        ) {
        case .success(let switchData):
            batteryPowerSwitchRestoreConfigurations[newNode.primaryUnicastAddress] = switchData
            let handles = BatteryPowerSwitchAddConfiguration.restoreConfigurationMessageHandles(
                for: switchData,
                node: newNode
            )
            if handles.isEmpty {
                failedBatteryPowerSwitchRestoreAddresses.insert(newNode.primaryUnicastAddress)
                failedBatteryPowerSwitchRestoreReasons[newNode.primaryUnicastAddress] = "sync_failed".localizedString
            } else {
                appendMessages.append(contentsOf: handles)
            }
        case .failure(let error):
            failedBatteryPowerSwitchRestoreAddresses.insert(newNode.primaryUnicastAddress)
            failedBatteryPowerSwitchRestoreReasons[newNode.primaryUnicastAddress] = error.message
        }
    }
```

- [ ] **Step 6: Add helper to mark append message failures**

In `DeviceRestoreViewController.swift`, insert this helper after `prepareBatteryPowerSwitchRestoreConfiguration(oldNode:newNode:appendMessages:)`:

```swift
    private func markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(_ messageHandle: MeshMessageHandle) {
        guard let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address else {
            return
        }
        guard batteryPowerSwitchRestoreConfigurations[address] != nil else {
            return
        }
        failedBatteryPowerSwitchRestoreAddresses.insert(address)
        failedBatteryPowerSwitchRestoreReasons[address] = "sync_failed".localizedString
    }
```

- [ ] **Step 7: Add helper to finalize BPS restore persistence**

In `DeviceRestoreViewController.swift`, insert this helper after `markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(_:)`:

```swift
    private func finalizeBatteryPowerSwitchRestoreConfiguration(
        for node: Node
    ) -> BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest? {
        guard let switchData = batteryPowerSwitchRestoreConfigurations[node.primaryUnicastAddress] else {
            failedBatteryPowerSwitchRestoreAddresses.remove(node.primaryUnicastAddress)
            failedBatteryPowerSwitchRestoreReasons.removeValue(forKey: node.primaryUnicastAddress)
            return nil
        }

        let failed = failedBatteryPowerSwitchRestoreAddresses.contains(node.primaryUnicastAddress)
        if failed {
            BatteryPowerSwitchAddConfiguration.markFailed(
                switchData,
                reason: failedBatteryPowerSwitchRestoreReasons[node.primaryUnicastAddress]
                    ?? switchData.lastSyncFailedReason
                    ?? "sync_failed".localizedString
            )
        } else {
            BatteryPowerSwitchAddConfiguration.markSucceeded(switchData, clearRemovedGroups: false)
        }

        let request = BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
            for: switchData,
            node: node
        )

        batteryPowerSwitchRestoreConfigurations.removeValue(forKey: node.primaryUnicastAddress)
        failedBatteryPowerSwitchRestoreAddresses.remove(node.primaryUnicastAddress)
        failedBatteryPowerSwitchRestoreReasons.removeValue(forKey: node.primaryUnicastAddress)
        return request
    }
```

- [ ] **Step 8: Call BPS restore preparation from appendMessagesBack**

In `DeviceRestoreViewController.addDevice(_:)`, inside `appendMessagesBack`, after the CCT restore block and before the commented composition hash block, add:

```swift
            prepareBatteryPowerSwitchRestoreConfiguration(
                oldNode: oldNode,
                newNode: newNode,
                appendMessages: &appendMessages
            )
```

The resulting local order should be:

```swift
            if let ctlModel = newNode.ctlModel, newNode.temperatureModel != nil {
                appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
                newNode.lightCTLTemperatureRange = oldNode.lightCTLTemperatureRange
                newNode.changeControlPage = oldNode.changeControlPage
                newNode.absoluteCctRange = oldNode.absoluteCctRange
            }

            prepareBatteryPowerSwitchRestoreConfiguration(
                oldNode: oldNode,
                newNode: newNode,
                appendMessages: &appendMessages
            )
```

- [ ] **Step 9: Add appendMessageFailedBack to restore flow**

In `DeviceRestoreViewController.addDevice(_:)`, after the existing `appendMessageSuccessBack` closure and before `addSuccess`, add:

```swift
        } appendMessageFailedBack: { [weak self] messageHandle in
            self?.markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(messageHandle)
```

The closure boundary should read:

```swift
        } appendMessageSuccessBack: { messageHandle in
            // existing success cache update block remains unchanged
        } appendMessageFailedBack: { [weak self] messageHandle in
            self?.markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(messageHandle)
        } addSuccess: { [weak self] addDevice in
```

- [ ] **Step 10: Finalize BPS restore in addSuccess**

In `DeviceRestoreViewController.addDevice(_:)`, inside `addSuccess`, after `node.save()` and before the existing `if node.needSync ...` block, add:

```swift
                if let request = finalizeBatteryPowerSwitchRestoreConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
```

BPS 本体配置失败只持久化到 `PJEightKeySwitchData.syncState = .failed`。不要把 `addDevice.addState` 改为 `.syncFailed`，因为 restore 页的同步按钮会进入 `.devices(...)` 通用同步页，该路径不会处理 BPS 的 Key Config / TX / LED。后续重试继续使用现有 BPS 同步入口。

The surrounding code should keep the existing name restore and `restoreNodes.append(node)` behavior:

```swift
                node.save()
                if let request = finalizeBatteryPowerSwitchRestoreConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
                // 恢复数据不包括邻近照明邻居关系，因涉及邻居节点，需要各设备恢复后再去外部同步数据
                if node.needSync && node.getNodeSyncProximityLighting() == nil {
                    addDevice.addState = .syncFailed
                }
                self.restoreNodes.append(node)
```

- [ ] **Step 11: Finish BPS battery read and disconnect in addFinish**

In `DeviceRestoreViewController.addDevice(_:)`, inside `addFinish`, after the existing `spaceDataChangedNotificaitonName` notification and before the automation restore block, add:

```swift
            let addedBatteryPowerSwitchNodes = self.restoreNodes.filter { $0.isBatteryPowerSwitch }
            self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(
                fallbackDisconnectNodes: addedBatteryPowerSwitchNodes
            )
```

The surrounding code should read:

```swift
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))

            let addedBatteryPowerSwitchNodes = self.restoreNodes.filter { $0.isBatteryPowerSwitch }
            self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(
                fallbackDisconnectNodes: addedBatteryPowerSwitchNodes
            )

            // 是否自动化恢复流程
            if self.automationRestore {
```

- [ ] **Step 12: Run static checks for restore wiring**

Run:

```bash
rg -n "pendingBatteryPowerSwitchInitialBatteryReads|batteryPowerSwitchRestoreConfigurations|prepareBatteryPowerSwitchRestoreConfiguration|finalizeBatteryPowerSwitchRestoreConfiguration|finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect|appendMessageFailedBack" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- `pendingBatteryPowerSwitchInitialBatteryReads` appears as a property, in finish helper, and in addSuccess.
- `batteryPowerSwitchRestoreConfigurations` appears as a property and in prepare/failure/finalize helpers.
- `prepareBatteryPowerSwitchRestoreConfiguration` appears as a helper and one call in `appendMessagesBack`.
- `finalizeBatteryPowerSwitchRestoreConfiguration` appears as a helper and one call in `addSuccess`.
- `finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect` appears as a helper and one call in `addFinish`.
- `appendMessageFailedBack` appears in the restore flow.

- [ ] **Step 13: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "feat: restore battery switch configuration"
```

---

### Task 3: Verification

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- Verify: `docs/superpowers/specs/2026-05-26-battery-power-switch-restore-design.md`

- [ ] **Step 1: Verify BPS restore reuses old virtual group and does not create one**

Run:

```bash
rg -n "prepareRestoreSwitchData|ensureBatteryPowerSwitchLinkGroup|createGroup\\(|linkGroupAddress" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- `prepareRestoreSwitchData` appears.
- `prepareRestoreSwitchData` checks `sourceSwitchData.linkGroupAddress != nil`.
- `prepareRestoreSwitchData` does not call `ensureBatteryPowerSwitchLinkGroup`.
- `prepareRestoreSwitchData` does not call `createGroup`.

- [ ] **Step 2: Verify restore path does not migrate target subscriptions**

Run:

```bash
rg -n "BatteryPowerSwitchTargetSubscription|getBatteryPowerSwitchTargetSubscriptionMessageHandles|getBatteryPowerSwitchSubscriptionMessageHandles|getBatteryPowerSwitchUnsubscriptionMessageHandles" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected: no matches.

- [ ] **Step 3: Verify restore success preserves removed group cleanup state**

Run:

```bash
rg -n "markSucceeded\\(switchData, clearRemovedGroups: false\\)|clearRemovedGroups: false" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- One call in `DeviceRestoreViewController.swift` using `clearRemovedGroups: false`.
- One method signature in `BatteryPowerSwitchAddConfiguration.swift` accepting `clearRemovedGroups`.

- [ ] **Step 4: Verify other add flows still use default BPS success behavior**

Run:

```bash
rg -n "BatteryPowerSwitchAddConfiguration.markSucceeded\\(switchData\\)" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- One match in `DeviceAddClassicModeController.swift`.
- One match in `DeviceAddProfessionalModeController.swift`.
- Neither call passes `clearRemovedGroups: false`.

- [ ] **Step 5: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verification checklist**

Use a real or lab BPS recovery flow:

1. Create or use an existing BPS with target groups configured.
2. Record its `linkGroupAddress` and target groups.
3. Put a replacement BPS into restore flow through `Restore Device Data`.
4. Confirm the restored BPS keeps the same switch card and does not create a second switch.
5. Confirm `proxyNodeAddress` is the new node address.
6. Confirm `linkGroupAddress` is unchanged.
7. Confirm target lights do not enter a new group subscription sync flow.
8. Press real BPS keys and confirm the original target groups respond.
9. Confirm ordinary light restore still enters the existing generic sync flow when needed.

- [ ] **Step 7: Commit verification fixes if build required changes**

If Task 3 found and fixed build issues, run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "fix: verify battery switch restore"
```

Expected: commit only occurs when Task 3 changed source files.
