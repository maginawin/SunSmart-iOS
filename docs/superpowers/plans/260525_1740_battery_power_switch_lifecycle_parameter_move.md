# Battery Power Switch Lifecycle, Parameter Filter And Level Move Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Battery Power Switch 入网电池读取、真实设备删除 reset 与本地 Node 清理、Device Parameter Settings 过滤 Switch 类型，以及长按 dimming 约 10 秒全程变化。

**Architecture:** 保持改动在现有 BPS 专属路径内：新增/LINK 后通过 `BatteryPowerSwitchAddConfiguration` 触发 best-effort 电池读取；删除时在 `MeshNetworkManager.deleteSwitch(switchData:)` 中识别真实 BPS 并执行 fire-and-forget reset、本地 Node 清理和地址级云同步通知；参数页能力通过 `Node.supportSetParameter` 统一排除 `.switches`；profile 长按速度只改 `PJEightKeySwitchData` 生成的 BPS key configuration。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、SQLite.swift repository、Bluetooth Mesh `GenericBatteryGet` / `GenericBatteryStatus` / `ConfigNodeReset`、Xcode `xcodebuild`。

---

## File Structure

- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 增加入网后 best-effort 电池读取 helper，复用 `MeshBatteryPowerSwitchBatteryReader`，成功时写入 `PJEightKeySwitchRepository`。
- Modify `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 普通新增与 LINK 完成 finalize 时调用电池读取 helper。
- Modify `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 与 Classic Add 保持同样行为。
- Modify `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - 删除真实 BPS 时静默发送 `ConfigNodeReset`、删除真实 Node、触发地址级云同步通知。
  - `Node.supportSetParameter` 排除 `.switches`。
- Modify `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - 拆分 click delta 与 press move 常量，将 press move 调整为 `6553`。

项目中没有独立 XCTest 测试 target：`rg --files | rg 'Tests|Test|\\.xctest'` 未发现可运行测试束。本计划使用 focused static checks、行为代码审查和直接 iOS build 作为验证闭环。

---

### Task 1: 入网和 LINK 后 best-effort 读取 BPS 电池电量

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: 写入电池读取 helper**

In `BatteryPowerSwitchAddConfiguration.swift`, add this method after `linkedConfigurationMessageHandles(...)` and before `markSucceeded(_:)`:

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

Why: `MeshBatteryPowerSwitchBatteryReader` already owns `GenericBatteryGet` / `GenericBatteryStatus` parsing. The helper only persists successful `0...100` values and ignores all failures.

- [ ] **Step 2: Classic Add fallback path 也读取电池**

In `DeviceAddClassicModeController.swift`, inside `finalizeBatteryPowerSwitchAddConfiguration(for:)`, replace the fallback success block:

```swift
            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
            }
            return
```

with:

```swift
            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
                BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(
                    for: fallbackSwitchData,
                    node: node
                )
            }
            return
```

- [ ] **Step 3: Classic Add normal/LINK finalize 后读取电池**

In the same `finalizeBatteryPowerSwitchAddConfiguration(for:)`, after the `if failedBatteryPowerSwitchAddConfigurationAddresses.contains(...) { ... } else { ... }` block and before removing `batteryPowerSwitchAddConfigurations`, add:

```swift
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(
            for: switchData,
            node: node
        )
```

The resulting block should look like:

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

        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(
            for: switchData,
            node: node
        )

        batteryPowerSwitchAddConfigurations.removeValue(forKey: node.primaryUnicastAddress)
```

- [ ] **Step 4: Professional Add fallback path 也读取电池**

In `DeviceAddProfessionalModeController.swift`, make the same fallback replacement as Step 2:

```swift
            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
                BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(
                    for: fallbackSwitchData,
                    node: node
                )
            }
            return
```

- [ ] **Step 5: Professional Add normal/LINK finalize 后读取电池**

In the same Professional `finalizeBatteryPowerSwitchAddConfiguration(for:)`, add the same helper call after `markFailed` / `markSucceeded` and before dictionary cleanup:

```swift
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelIfPossible(
            for: switchData,
            node: node
        )
```

- [ ] **Step 6: 验证入网电池读取代码路径**

Run:

```bash
rg -n "readInitialBatteryLevelIfPossible|saveBattery\\(|MeshBatteryPowerSwitchBatteryReader" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- `BatteryPowerSwitchAddConfiguration.swift` contains exactly one `readInitialBatteryLevelIfPossible` method.
- Classic and Professional controllers both call `readInitialBatteryLevelIfPossible` in the fallback path.
- Classic and Professional controllers both call `readInitialBatteryLevelIfPossible` after `markFailed` / `markSucceeded`.
- `saveBattery(` appears only in the helper, not in Add Controllers.

- [ ] **Step 7: Commit Task 1**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
git commit -m "feat: read battery after battery switch add"
```

---

### Task 2: 删除真实 BPS 时 fire-and-forget reset、本地 Node 清理和地址级云同步

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 在 `deleteSwitch(switchData:)` 捕获真实 BPS node**

In `MeshNetwork+SunSmart.swift`, inside `func deleteSwitch(switchData: DeviceSwitchData)`, after:

```swift
        guard let meshUUID = self.meshNetwork?.uuid.uuidString else { return }
```

add:

```swift
        let realBatteryPowerSwitchNode = switchData.proxyNode?.isBatteryPowerSwitch == true
            ? switchData.proxyNode
            : nil
        silentlyResetBatteryPowerSwitchIfNeeded(realBatteryPowerSwitchNode)
```

This captures the node before the method clears Switch linkage data.

- [ ] **Step 2: 删除 Switch 数据后清理真实 BPS node**

In the same method, after:

```swift
        self.switchs.removeAll(where: { $0.id == switchData.id })
```

add:

```swift
        removeRealBatteryPowerSwitchNodeIfNeeded(realBatteryPowerSwitchNode)
```

- [ ] **Step 3: 删除 link groups 后触发 BPS 专属刷新和地址级云同步**

In the same method, after the `switchGroups.forEach { group in ... }` block, add:

```swift
        notifyRealBatteryPowerSwitchDeletedIfNeeded(realBatteryPowerSwitchNode)
```

The bottom of the method should keep the existing group cleanup and then notify only when a real BPS was removed.

- [ ] **Step 4: 增加私有 helper**

Still in `MeshNetwork+SunSmart.swift`, inside the `extension MeshNetworkManager` that contains `deleteSwitch(switchData:)`, add these private methods after `deleteSwitch(switchData:)` and before `deleteDongle(dongleData:)`:

```swift
    private func silentlyResetBatteryPowerSwitchIfNeeded(_ node: Node?) {
        guard let node else {
            return
        }
        MeshAPI.sendMessage(message: ConfigNodeReset(), address: node.primaryUnicastAddress)
    }

    private func removeRealBatteryPowerSwitchNodeIfNeeded(_ node: Node?) {
        guard let node else {
            return
        }
        node.deleteExtension()
        self.meshNetwork?.forceRemove(node: node)
    }

    private func notifyRealBatteryPowerSwitchDeletedIfNeeded(_ node: Node?) {
        guard node != nil else {
            return
        }
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.network(type: .address)
        )
    }
```

Why:

- `MeshAPI.sendMessage(message:address:)` queues one reset message and does not install a response wait in this flow.
- `node.deleteExtension()` mirrors existing real-device delete cleanup.
- `forceRemove(node:)` removes node memory and database records.
- `.network(type: .address)` ensures cloud sync includes address and device-list changes, independent of caller notifications.

- [ ] **Step 5: 验证真实 BPS 删除代码路径**

Run:

```bash
rg -n "silentlyResetBatteryPowerSwitchIfNeeded|removeRealBatteryPowerSwitchNodeIfNeeded|notifyRealBatteryPowerSwitchDeletedIfNeeded|ConfigNodeReset\\(\\)|SpaceChangeDataType\\.network\\(type: \\.address\\)" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- All three helper methods appear.
- `ConfigNodeReset()` appears in the silent reset helper.
- `.network(type: .address)` appears in `notifyRealBatteryPowerSwitchDeletedIfNeeded`.

- [ ] **Step 6: 验证未绑定虚拟 BPS 不触发 reset 或 Node 删除**

Run:

```bash
rg -n "realBatteryPowerSwitchNode = switchData\\.proxyNode\\?\\.isBatteryPowerSwitch == true" SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- The capture expression is present.
- Because `realBatteryPowerSwitchNode` becomes `nil` when there is no BPS proxy node, all three helper calls return without action for unlinked virtual BPS.

- [ ] **Step 7: Commit Task 2**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "feat: reset battery switch on delete"
```

---

### Task 3: Device Parameter Settings 排除所有 Switch 类型设备

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [ ] **Step 1: 修改 `Node.supportSetParameter`**

In `MeshNetwork+SunSmart.swift`, replace:

```swift
        if self.deviceType == .dongle || self.deviceType == .gateway || self.deviceType == .emergencyController {
            return false
        }
```

with:

```swift
        if self.deviceType == .switches ||
            self.deviceType == .dongle ||
            self.deviceType == .gateway ||
            self.deviceType == .emergencyController {
            return false
        }
```

This makes `DeviceCategorysViewController` naturally exclude Kinetic Switch, Battery Power Switch, and future Switch types because it already filters with `node.supportSetParameter`.

- [ ] **Step 2: 验证参数页入口仍依赖 `supportSetParameter`**

Run:

```bash
rg -n "supportSetParameter|deviceType == \\.switches" SunSmart/Main/Device/Parameter/Controller/DeviceCategorysViewController.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- `DeviceCategorysViewController` still filters with `node.supportSetParameter`.
- `Node.supportSetParameter` now explicitly returns false for `.switches`.

- [ ] **Step 3: Commit Task 3**

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: hide switches from device parameters"
```

---

### Task 4: BPS long-press level move 调整为约 10 秒全程

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: 拆分 dimming constants**

In `PJEightKeySwitchData.swift`, inside `private extension PJEightKeySwitchData`, replace:

```swift
    static let dimmingStepLevel: Int16 = 13107
```

with:

```swift
    static let dimmingDeltaStepLevel: Int16 = 13107
    static let dimmingMoveStepLevel: Int16 = 6553
```

- [ ] **Step 2: 更新 `dimmingConfigurations(address:appKeyIndex:)`**

Replace the whole method:

```swift
    func dimmingConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        [
            dimmingConfiguration(button: 4, trigger: .click, level: Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .press, level: Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .click, level: -Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .press, level: -Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex)
        ]
    }
```

with:

```swift
    func dimmingConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        [
            dimmingConfiguration(button: 4, trigger: .click, level: Self.dimmingDeltaStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .press, level: Self.dimmingMoveStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .click, level: -Self.dimmingDeltaStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .press, level: -Self.dimmingMoveStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex)
        ]
    }
```

- [ ] **Step 3: 验证 click 与 press 参数分离**

Run:

```bash
rg -n "dimmingDeltaStepLevel|dimmingMoveStepLevel|dimmingStepLevel" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:

- `dimmingDeltaStepLevel` appears in click rows.
- `dimmingMoveStepLevel` appears in press rows.
- `dimmingStepLevel` no longer appears.

- [ ] **Step 4: Commit Task 4**

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "fix: tune battery switch dimming move speed"
```

---

### Task 5: 整体验证和收尾

**Files:**
- Verify only unless a previous task exposes a compile issue.

- [ ] **Step 1: 检查所有需求关键点**

Run:

```bash
rg -n "readInitialBatteryLevelIfPossible|ConfigNodeReset\\(\\)|SpaceChangeDataType\\.network\\(type: \\.address\\)|deviceType == \\.switches|dimmingMoveStepLevel" SunSmart/Main/Device/Device1.5/NEightKeySwitches SunSmart/Main/Device/Controller SunSmart/Common/Data/MeshNetwork+SunSmart.swift
```

Expected:

- Initial battery helper and Add Controller calls are present.
- Delete path sends `ConfigNodeReset()` and posts `.network(type: .address)` for real BPS deletion.
- `supportSetParameter` excludes `.switches`.
- BPS dimming move constant is `6553`.

- [ ] **Step 2: 检查无格式错误**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: 直接 iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build exits 0.
- Output includes `** BUILD SUCCEEDED **`.
- Existing AppIntents metadata warnings are acceptable if no new compile errors are present.

- [ ] **Step 4: 最终状态检查**

Run:

```bash
git status --short
```

Expected: no unstaged or uncommitted source changes.

- [ ] **Step 5: 手动验证清单**

Use a device flow when hardware is available:

- Add a real Battery Power Switch normally. If it responds to `GenericBatteryGet`, detail page should later show a saved battery level.
- Add a virtual Battery Power Switch, then LINK it to a real Battery Power Switch. If it responds to `GenericBatteryGet`, the same virtual Switch record should receive the battery level.
- Delete a linked real Battery Power Switch. The App should show Done immediately; online hardware should reset; offline or inactive hardware should not block deletion.
- Re-enter `Site - Space - More - Device Parameter Settings`; Kinetic Switch and Battery Power Switch should not appear.
- Save or re-sync BPS profile and confirm long-press dimming feels near 10 seconds from 0% to 100%.

- [ ] **Step 6: Commit verification fixes if needed**

Only run this if Step 3 exposes a compile-only fix that was not already committed:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "fix: complete battery switch lifecycle changes"
```

Expected: commit is created only if verification required source changes.
