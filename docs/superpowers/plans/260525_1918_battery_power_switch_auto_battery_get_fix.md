# Battery Power Switch Auto Battery Get Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery Power Switch 添加成功后自动 `GenericBatteryGet` 不稳定生效的问题，并保持变更只作用于 `0x2A01` / `0x2A02` Battery Power Switch。

**Architecture:** 将自动电量读取从单个设备 `addSuccess` 阶段移出，改为先在 finalize 阶段记录 pending read request，再在整体 `addFinish` 之后短延迟执行读取。读取完成或超时后再断开对应 Battery Power Switch proxy，避免 Add Manager reset 的 `MeshMessageManager.cancelAll()` 清空消息和等待回调。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、Bluetooth Mesh `GenericBatteryGet` / `GenericBatteryStatus`、SQLite repository、Xcode `xcodebuild`。

---

## File Structure

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 增加 `InitialBatteryReadRequest`。
  - 增加 addFinish 后读取并断开的静态 helper。
  - 将旧的立即读取 helper 改为 request-based private helper。
- Modify `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 记录 Classic Add 中的 pending Battery Power Switch 电量读取项。
  - finalize 返回 request，不直接发送 `GenericBatteryGet`。
  - addFinish 后调用后置读取/断开 helper。
- Modify `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 与 Classic Add 保持同样行为。

当前工作区已有以下未提交改动，执行本计划时不要回退它们：

- `PJEightKeySwitchRefreshAlertController.swift` 中 reader 已改用 `address` 发送。
- `PJEightKeySwitchRepository.swift` 中 `saveBattery(...)` 已同步更新内存缓存。

---

### Task 1: 增加 addFinish 后读取并断开的 BPS helper

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Replace the immediate initial battery read helper**

In `BatteryPowerSwitchAddConfiguration.swift`, replace the existing public method:

```swift
    static func readInitialBatteryLevelIfPossible(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) {
        guard isSupportedAddNode(node) else {
            return
        }

        MeshBatteryPowerSwitchBatteryReader().readBatteryLevel(from: node) { level in
            guard let level else {
                return
            }
            DispatchQueue.main.async {
                let timestamp = Int64(Date().timeIntervalSince1970)
                guard PJEightKeySwitchRepository.shared.saveBattery(
                    level: level,
                    lastUpdateTime: timestamp,
                    for: switchData
                ) else {
                    return
                }
                NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            }
        }
    }
```

with:

```swift
    struct InitialBatteryReadRequest {
        let switchData: PJEightKeySwitchData
        let nodeAddress: Address
    }

    static func makeInitialBatteryReadRequest(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> InitialBatteryReadRequest? {
        guard isSupportedAddNode(node) else {
            return nil
        }
        return InitialBatteryReadRequest(
            switchData: switchData,
            nodeAddress: node.primaryUnicastAddress
        )
    }

    static func readInitialBatteryLevelsAndDisconnect(
        _ requests: [InitialBatteryReadRequest],
        fallbackDisconnectNodes: [Node],
        delay: TimeInterval = 0.5
    ) {
        let requestAddresses = Set(requests.map { $0.nodeAddress })
        fallbackDisconnectNodes
            .filter { $0.isBatteryPowerSwitch && !requestAddresses.contains($0.primaryUnicastAddress) }
            .forEach { MeshLibManager.manager.disconnectProxy(node: $0) }

        guard !requests.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            readInitialBatteryLevelsIfPossible(requests) {
                requests.forEach {
                    disconnectBatteryPowerSwitchNode(address: $0.nodeAddress)
                }
            }
        }
    }

    private static func readInitialBatteryLevelsIfPossible(
        _ requests: [InitialBatteryReadRequest],
        completion: @escaping () -> Void
    ) {
        readInitialBatteryLevelsIfPossible(
            requests,
            index: 0,
            completion: completion
        )
    }

    private static func readInitialBatteryLevelsIfPossible(
        _ requests: [InitialBatteryReadRequest],
        index: Int,
        completion: @escaping () -> Void
    ) {
        guard requests.indices.contains(index) else {
            completion()
            return
        }

        let request = requests[index]
        readInitialBatteryLevelIfPossible(for: request) {
            readInitialBatteryLevelsIfPossible(
                requests,
                index: index + 1,
                completion: completion
            )
        }
    }

    private static func readInitialBatteryLevelIfPossible(
        for request: InitialBatteryReadRequest,
        completion: @escaping () -> Void
    ) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: request.nodeAddress),
              isSupportedAddNode(node) else {
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        MeshBatteryPowerSwitchBatteryReader().readBatteryLevel(from: node) { level in
            DispatchQueue.main.async {
                defer { completion() }
                guard let level else {
                    return
                }
                let timestamp = Int64(Date().timeIntervalSince1970)
                guard PJEightKeySwitchRepository.shared.saveBattery(
                    level: level,
                    lastUpdateTime: timestamp,
                    for: request.switchData
                ) else {
                    return
                }
                NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            }
        }
    }

    private static func disconnectBatteryPowerSwitchNode(address: Address) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              isSupportedAddNode(node) else {
            return
        }
        MeshLibManager.manager.disconnectProxy(node: node)
    }
```

Why: the new public surface collects a stable `switchData + nodeAddress` request before Add Manager reset, then performs the actual `GenericBatteryGet` after reset has had time to run.

- [ ] **Step 2: Verify helper symbols**

Run:

```bash
rg -n "InitialBatteryReadRequest|makeInitialBatteryReadRequest|readInitialBatteryLevelsAndDisconnect|private static func readInitialBatteryLevelIfPossible|disconnectBatteryPowerSwitchNode" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected output includes all five symbols in `BatteryPowerSwitchAddConfiguration.swift`.

---

### Task 2: Move Classic Add auto read to addFinish after reset window

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`

- [ ] **Step 1: Add pending request storage**

In `DeviceAddClassicModeController.swift`, immediately below:

```swift
    /// 添加成功的节点
    private var addSuccessNodes: [Node] = []
```

add:

```swift
    private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
```

- [ ] **Step 2: Replace the old BPS disconnect helper**

Replace the existing method:

```swift
    private func disconnectBatteryPowerSwitchNodes(_ nodes: [Node]) {
        nodes.filter { $0.isBatteryPowerSwitch }.forEach {
            MeshLibManager.manager.disconnectProxy(node: $0)
        }
    }
```

with:

```swift
    private func finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect() {
        let requests = pendingBatteryPowerSwitchInitialBatteryReads
        pendingBatteryPowerSwitchInitialBatteryReads.removeAll()
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelsAndDisconnect(
            requests,
            fallbackDisconnectNodes: addSuccessNodes
        )
    }
```

- [ ] **Step 3: Make finalize return a pending read request**

Replace the full `finalizeBatteryPowerSwitchAddConfiguration(for:)` method with:

```swift
    private func finalizeBatteryPowerSwitchAddConfiguration(
        for node: Node
    ) -> BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest? {
        guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) else {
            return nil
        }

        guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] else {
            if bindToBatteryPowerSwitch != nil {
                failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
                failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
                return nil
            }

            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
                return BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
                    for: fallbackSwitchData,
                    node: node
                )
            }
            return nil
        }

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

        let request = BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
            for: switchData,
            node: node
        )

        batteryPowerSwitchAddConfigurations.removeValue(forKey: node.primaryUnicastAddress)
        failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
        failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
        return request
    }
```

- [ ] **Step 4: Store the request in addSuccess**

In the `addSuccess` closure, replace:

```swift
                if node.isBatteryPowerSwitch {
                    finalizeBatteryPowerSwitchAddConfiguration(for: node)
                }
```

with:

```swift
                if node.isBatteryPowerSwitch,
                   let request = finalizeBatteryPowerSwitchAddConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
```

- [ ] **Step 5: Use the post-finish read/disconnect path**

In the `addFinish` closure, replace:

```swift
            self.disconnectBatteryPowerSwitchNodes(self.addSuccessNodes)
```

with:

```swift
            self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
```

- [ ] **Step 6: Verify Classic no longer directly sends initial Battery Get**

Run:

```bash
rg -n "pendingBatteryPowerSwitchInitialBatteryReads|finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect|readInitialBatteryLevelIfPossible|disconnectBatteryPowerSwitchNodes|readInitialBatteryLevelsAndDisconnect" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
```

Expected:

- `pendingBatteryPowerSwitchInitialBatteryReads` appears in the property, helper, and addSuccess path.
- `finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect` appears in the helper and addFinish path.
- `readInitialBatteryLevelsAndDisconnect` appears once.
- No `readInitialBatteryLevelIfPossible` match in this file.
- No `disconnectBatteryPowerSwitchNodes` match in this file.

---

### Task 3: Move Professional Add auto read to addFinish after reset window

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Add pending request storage**

In `DeviceAddProfessionalModeController.swift`, immediately below:

```swift
    /// 添加成功的节点
    private var addSuccessNodes: [Node] = []
```

add:

```swift
    private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
```

- [ ] **Step 2: Replace the old BPS disconnect helper**

Replace the existing method:

```swift
    private func disconnectBatteryPowerSwitchNodes(_ nodes: [Node]) {
        nodes.filter { $0.isBatteryPowerSwitch }.forEach {
            MeshLibManager.manager.disconnectProxy(node: $0)
        }
    }
```

with:

```swift
    private func finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect() {
        let requests = pendingBatteryPowerSwitchInitialBatteryReads
        pendingBatteryPowerSwitchInitialBatteryReads.removeAll()
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelsAndDisconnect(
            requests,
            fallbackDisconnectNodes: addSuccessNodes
        )
    }
```

- [ ] **Step 3: Make finalize return a pending read request**

Replace the full `finalizeBatteryPowerSwitchAddConfiguration(for:)` method with:

```swift
    private func finalizeBatteryPowerSwitchAddConfiguration(
        for node: Node
    ) -> BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest? {
        guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) else {
            return nil
        }

        guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] else {
            if bindToBatteryPowerSwitch != nil {
                failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
                failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
                return nil
            }

            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
                return BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
                    for: fallbackSwitchData,
                    node: node
                )
            }
            return nil
        }

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

        let request = BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
            for: switchData,
            node: node
        )

        batteryPowerSwitchAddConfigurations.removeValue(forKey: node.primaryUnicastAddress)
        failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
        failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
        return request
    }
```

- [ ] **Step 4: Store the request in addSuccess**

In the `addSuccess` closure, replace:

```swift
                if node.isBatteryPowerSwitch {
                    finalizeBatteryPowerSwitchAddConfiguration(for: node)
                }
```

with:

```swift
                if node.isBatteryPowerSwitch,
                   let request = finalizeBatteryPowerSwitchAddConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
```

- [ ] **Step 5: Use the post-finish read/disconnect path**

In the `addFinish` closure, replace:

```swift
            self.disconnectBatteryPowerSwitchNodes(self.addSuccessNodes)
```

with:

```swift
            self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
```

- [ ] **Step 6: Verify Professional no longer directly sends initial Battery Get**

Run:

```bash
rg -n "pendingBatteryPowerSwitchInitialBatteryReads|finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect|readInitialBatteryLevelIfPossible|disconnectBatteryPowerSwitchNodes|readInitialBatteryLevelsAndDisconnect" SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- `pendingBatteryPowerSwitchInitialBatteryReads` appears in the property, helper, and addSuccess path.
- `finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect` appears in the helper and addFinish path.
- `readInitialBatteryLevelsAndDisconnect` appears once.
- No `readInitialBatteryLevelIfPossible` match in this file.
- No `disconnectBatteryPowerSwitchNodes` match in this file.

---

### Task 4: Focused verification and build

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Verify only the request-based initial read remains**

Run:

```bash
rg -n "readInitialBatteryLevelIfPossible|readInitialBatteryLevelsAndDisconnect|makeInitialBatteryReadRequest|pendingBatteryPowerSwitchInitialBatteryReads|disconnectBatteryPowerSwitchNodes" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- `readInitialBatteryLevelIfPossible` appears only in `BatteryPowerSwitchAddConfiguration.swift` as a private request-based helper.
- `readInitialBatteryLevelsAndDisconnect` appears in `BatteryPowerSwitchAddConfiguration.swift`, `DeviceAddClassicModeController.swift`, and `DeviceAddProfessionalModeController.swift`.
- `makeInitialBatteryReadRequest` appears in `BatteryPowerSwitchAddConfiguration.swift` and both add controllers.
- `pendingBatteryPowerSwitchInitialBatteryReads` appears only in both add controllers.
- `disconnectBatteryPowerSwitchNodes` has no matches.

- [ ] **Step 2: Verify manual Refresh Battery path still uses the existing reader**

Run:

```bash
rg -n "PJEightKeySwitchBatteryRefreshFlow|MeshBatteryPowerSwitchBatteryReader|GenericBatteryGet|readBatteryLevel" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift
```

Expected:

- `MeshBatteryPowerSwitchBatteryReader` still exists.
- `GenericBatteryGet()` still appears in that file.
- No add controller path appears in this output.

- [ ] **Step 3: Build SunSmart for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build ends with `** BUILD SUCCEEDED **`.
- No Swift compile errors about `InitialBatteryReadRequest`, the private recursive overloads, or missing `MeshLibManager`.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "fix: delay battery switch initial battery read"
```

Expected:

- Commit contains only the three implementation files.
- Existing unrelated/uncommitted docs and the existing reader/repository edits are not accidentally staged unless they are intentionally part of the same fix.

---

## Manual QA

Use a real `0x2A01` or `0x2A02` Battery Power Switch:

1. Add the Battery Power Switch through Classic Add.
2. Confirm logs show `GenericBatteryGet()` after addFinish, not during append message handling.
3. If the device returns valid `GenericBatteryStatus`, open the Battery Power Switch detail page and confirm battery level and update time are shown.
4. Repeat through Professional Add.
5. Add a non-BPS device and confirm no new automatic Battery Get is logged.
6. Confirm the Battery Power Switch BLE connection disconnects after the automatic read succeeds or times out.

## Spec Coverage Self-Review

- BPS-only scope: covered by `isSupportedAddNode(...)`, request creation, and static disconnect filtering.
- Avoid Add Manager `cancelAll()`: covered by addFinish delayed helper.
- Preserve add success behavior: reading remains best-effort and does not alter success/fail lists.
- Preserve manual refresh: no changes planned in refresh flow.
- Preserve OTA disconnect: no changes planned in firmware update controller.
- Verification: static `rg`, focused manual QA, and direct `xcodebuild` are included.
