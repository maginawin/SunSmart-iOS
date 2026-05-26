# Battery Power Switch Restore Failure Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery Power Switch 在 `Restore Device Data` 中恢复失败、旧 switch 失去绑定、新 BPS 不出现在 space 的问题。

**Architecture:** 先让 BPS restore 用旧 node 地址直接取得旧 `PJEightKeySwitchData`，不依赖旧 node 仍存在于 meshNetwork。然后把 BPS restore 从通用灯具 restore append 队列中分离，避免 `manualOverrideTimeout` 等灯具配置阻断 BPS Key Config / TX / LED。最后让 restore 页的红色叹号只反映非 BPS 的通用 node sync，BPS 本体同步状态交给 `PJEightKeySwitchData.syncState`。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SQLite repository, Xcode workspace `SunSmart.xcworkspace`

---

## Root Cause Analysis

### Evidence From Log

- 新入网节点地址是 `0x0184`，composition data 中 `companyIdentifier = 0x0A78`、`productIdentifier = 0x2A01`，这是 Battery Power Switch。
- Config AppKey / Model AppBind 全部成功，说明基础入网和 required model keybind 不是失败点。
- 日志没有出现 `batteryPowerSwitchKeyConfig`、`batteryPowerSwitchTxEnabled`、`batteryPowerSwitchLEDEnabled` 的发送记录。
- append 队列中出现了灯具逻辑的 `manualOverrideTimeout`：

```text
Sending SunricherVendorSet(function: ... manualOverrideTimeout(...)) ... to: 0184
Response ... not received (timeout)
❌ 消息发送失败 message: SunricherVendorSet(... manualOverrideTimeout ...)
```

- `manualOverrideTimeout` 后 append queue 继续/结束并进入 `添加成功`，但 restore 行显示红色叹号。点击重试会走 `.devices(syncFailedNodes)` 的通用同步页，不会执行 BPS Key Config / TX / LED。

### Root Cause

1. `MeshNetwork.add(node:)` 在新 node UUID 与旧 node UUID 相同时会移除旧 node：

```swift
if let oldNode = self.node(withUuid: node.uuid) {
    self.remove(node: oldNode)
}
```

2. 当前 `DeviceRestoreViewController.batteryPowerSwitchData(boundTo:)` 通过 `switchData.batteryPowerSwitchData` 转换旧 BPS 数据；这个 computed property 要求 `proxyNode?.isBatteryPowerSwitch == true`。

3. 同一个物理 BPS reset 后恢复时，旧 node 已被 SDK 移除，旧 `proxyNodeAddress` 对应的 node 查不到，`proxyNode` 为 nil，`batteryPowerSwitchData` 返回 nil。

4. BPS restore 分支没有进入，所以旧 switch 数据没有被持久化为 `proxyNodeAddress = newNode.primaryUnicastAddress`。结果是：
   - 旧 switch 仍指向旧地址，但旧 node 已被移除，UI 看起来像“失去关联设备”。
   - 新 node 没有关联到 `PJEightKeySwitchData`，所以不会作为恢复后的 BPS 出现在 space。
   - append 队列落入通用 restore 逻辑，给 BPS 下发灯具用 `manualOverrideTimeout` 并 timeout，造成红色叹号和通用重试失败。

---

## File Structure

- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - 修复旧 BPS 数据查找，不依赖旧 `proxyNode` 存活。
  - 增加 BPS restore 判断 helper。
  - 只把 BPS Key Config / TX / LED 的 append 失败计入 BPS restore syncState，忽略 `AttentionSet` 这类视觉反馈消息失败。
  - BPS restore append 队列只下发 BPS 本体配置和可选 Attention，不再混入 light/default generic restore messages。
  - restore 页 `.syncFailed` 判断排除 BPS node，避免 BPS 走 `.devices(...)` 通用同步入口。

- Verify only: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 确认 restore helper 仍复用旧 `linkGroupAddress`，不创建新虚拟组，不迁移 target subscription。

- Verify only: `../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh API/MeshNetwork+Nodes.swift`
  - 作为同 UUID 恢复时旧 node 被移除的原因依据，不修改 SDK。

---

### Task 1: Make Old BPS Data Lookup Independent Of Live Proxy Node

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Verify current lookup depends on `batteryPowerSwitchData`**

Run:

```bash
sed -n '498,510p' SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected: `batteryPowerSwitchData(boundTo:)` returns `switchData.batteryPowerSwitchData`.

- [ ] **Step 2: Replace `batteryPowerSwitchData(boundTo:)`**

Replace the method with:

```swift
    private func batteryPowerSwitchData(boundTo oldNode: Node) -> PJEightKeySwitchData? {
        guard let switchData = MeshNetworkManager.instance.switchs.first(where: {
            $0.proxyNodeAddress == oldNode.primaryUnicastAddress
        }) else {
            return nil
        }
        if let batteryPowerSwitchData = switchData as? PJEightKeySwitchData {
            return batteryPowerSwitchData
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: switchData)
    }
```

This keeps the old-address lookup but avoids the `proxyNode?.isBatteryPowerSwitch == true` guard, because the old node may already be removed by SDK replacement.

- [ ] **Step 3: Add BPS restore predicate helper**

Insert after `batteryPowerSwitchData(boundTo:)`:

```swift
    private func isBatteryPowerSwitchRestore(oldNode: Node, newNode: Node) -> Bool {
        BatteryPowerSwitchAddConfiguration.isSupportedAddNode(newNode)
            && batteryPowerSwitchData(boundTo: oldNode) != nil
    }
```

- [ ] **Step 4: Run static check**

Run:

```bash
rg -n "batteryPowerSwitchData\\(boundTo|isBatteryPowerSwitchRestore|switchData as\\? PJEightKeySwitchData|makeEightKeySwitch" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- `batteryPowerSwitchData(boundTo:)` appears as a helper and call sites.
- `switchData as? PJEightKeySwitchData` appears once.
- `PJEightKeySwitchRepository.shared.makeEightKeySwitch(from:)` appears once.
- `isBatteryPowerSwitchRestore(oldNode:newNode:)` appears as a helper.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "fix: locate restored battery switch data"
```

---

### Task 2: Separate BPS Restore Append Messages From Generic Restore

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Verify generic restore messages are currently sent to all nodes**

Run:

```bash
sed -n '672,718p' SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected: `LightLightnessSetUnacknowledged`, `newNode.getSyncData(type: .all)`, and `manualOverrideTimeout` run before `prepareBatteryPowerSwitchRestoreConfiguration(...)`.

- [ ] **Step 2: Add BPS branch before generic append messages**

In `DeviceRestoreViewController.swift`, insert this helper before `markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(_:)`:

```swift
    private func isBatteryPowerSwitchRestoreConfigurationMessage(_ message: MeshMessage) -> Bool {
        guard let message = message as? SunricherVendorSet else {
            return false
        }
        switch message.function {
        case .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnabled, .batteryPowerSwitchLEDEnabled:
            return true
        default:
            return false
        }
    }
```

- [ ] **Step 3: Only mark BPS own configuration message failures**

In `markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(_:)`, insert this guard before address lookup:

```swift
        guard isBatteryPowerSwitchRestoreConfigurationMessage(messageHandle.message) else {
            return
        }
```

The method should start as:

```swift
    private func markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(_ messageHandle: MeshMessageHandle) {
        guard isBatteryPowerSwitchRestoreConfigurationMessage(messageHandle.message) else {
            return
        }
        guard let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address else {
            return
        }
```

This prevents `AttentionSet` failures from marking BPS Key Config / TX / LED as failed.

- [ ] **Step 4: Add BPS branch before generic append messages**

In `appendMessagesBack`, after resolving `oldNode` and `addToGroup`, insert this block before `var appendMessages: [MeshMessageHandle] = []`:

```swift
            let restoringBatteryPowerSwitch = isBatteryPowerSwitchRestore(
                oldNode: oldNode,
                newNode: newNode
            )
```

- [ ] **Step 5: Route BPS restore to its own append queue**

Replace the existing append-message construction from `var appendMessages: [MeshMessageHandle] = []` through the `prepareBatteryPowerSwitchRestoreConfiguration(...)` call with:

```swift
            var appendMessages: [MeshMessageHandle] = []

            if restoringBatteryPowerSwitch {
                prepareBatteryPowerSwitchRestoreConfiguration(
                    oldNode: oldNode,
                    newNode: newNode,
                    appendMessages: &appendMessages
                )
                if let healthModel = newNode.healthModel {
                    appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
                }
                appendCompletion(appendMessages)
                return
            }

            // 入网后默认调为最大亮度
            if let model = newNode.lightnessModel {
                appendMessages.append(MeshMessageHandle(message: LightLightnessSetUnacknowledged(lightness: .max), model: model))
            }
            let syncDatas = newNode.getSyncData(type: .all)
            syncDatas.forEach({
                appendMessages.append(contentsOf: $0.getMessageHandles(node: newNode))
            })

            if addToGroup == nil {
                if let vendorModel = newNode.sunricherVendorModel {
                    appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max)), model: vendorModel))
                }
                if let powerOnOffSetupModel = newNode.powerOnOffSetupModel, newNode.lightLCModel != nil {
                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .restore), model: powerOnOffSetupModel))
                }
            }
            // 需要追加发送的消息
            if let ctlModel = newNode.ctlModel, newNode.temperatureModel != nil {
                appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
                newNode.lightCTLTemperatureRange = oldNode.lightCTLTemperatureRange
                newNode.changeControlPage = oldNode.changeControlPage
                newNode.absoluteCctRange = oldNode.absoluteCctRange
            }
```

The BPS branch must return before `manualOverrideTimeout`; otherwise one timeout can clear the append queue before BPS Key Config / TX / LED are sent.

- [ ] **Step 6: Preserve existing non-BPS behavior**

After the replacement, keep the existing final Attention block for non-BPS devices:

```swift
            // 添加成功后闪烁
            if let healthModel = newNode.healthModel {
                appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
            }
            appendCompletion(appendMessages)
```

- [ ] **Step 7: Run static check**

Run:

```bash
rg -n "isBatteryPowerSwitchRestoreConfigurationMessage|batteryPowerSwitchKeyConfig|batteryPowerSwitchTxEnabled|batteryPowerSwitchLEDEnabled|restoringBatteryPowerSwitch|manualOverrideTimeout|prepareBatteryPowerSwitchRestoreConfiguration|appendCompletion\\(appendMessages\\)|return" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- `isBatteryPowerSwitchRestoreConfigurationMessage` appears as a helper and one guard call.
- `restoringBatteryPowerSwitch` appears once as a local value and once in `if restoringBatteryPowerSwitch`.
- `prepareBatteryPowerSwitchRestoreConfiguration` appears inside the BPS branch before the generic `manualOverrideTimeout` block.
- The BPS branch calls `appendCompletion(appendMessages)` and `return`.
- `manualOverrideTimeout` remains only in the non-BPS path.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "fix: isolate battery switch restore messages"
```

---

### Task 3: Keep BPS Out Of Generic Restore Sync Failure UI

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Verify generic sync-failed checks include BPS**

Run:

```bash
rg -n "node.needSync|needSyncNodes = self.restoreNodes.filter" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected: one `addSuccess` check and one `addFinish` `needSyncNodes` filter include all nodes.

- [ ] **Step 2: Exclude BPS from addSuccess generic sync state**

Replace:

```swift
                if node.needSync && node.getNodeSyncProximityLighting() == nil {
                    addDevice.addState = .syncFailed
                }
```

with:

```swift
                if !node.isBatteryPowerSwitch,
                   node.needSync,
                   node.getNodeSyncProximityLighting() == nil {
                    addDevice.addState = .syncFailed
                }
```

- [ ] **Step 3: Exclude BPS from addFinish generic sync retry list**

Replace:

```swift
            let needSyncNodes = self.restoreNodes.filter({ $0.needSync })
```

with:

```swift
            let needSyncNodes = self.restoreNodes.filter({ !$0.isBatteryPowerSwitch && $0.needSync })
```

BPS own configuration failure is already represented by `PJEightKeySwitchData.syncState = .failed`, and the existing BPS switch UI routes that to `.batteryPowerSwitch(switchData)` sync. It must not be converted into `.devices(syncFailedNodes)`.

- [ ] **Step 4: Run static check**

Run:

```bash
rg -n "!node\\.isBatteryPowerSwitch|!\\$0\\.isBatteryPowerSwitch && \\$0\\.needSync|SyncDevicesViewController\\(type: \\.devices" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- addSuccess sync-failed check includes `!node.isBatteryPowerSwitch`.
- addFinish need-sync filter includes `!$0.isBatteryPowerSwitch && $0.needSync`.
- `SyncDevicesViewController(type: .devices(syncFailedNodes))` remains unchanged for non-BPS restore sync failures.

- [ ] **Step 5: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "fix: keep battery switch restore out of generic sync"
```

---

### Task 4: Verification

**Files:**
- Verify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Verify restore still reuses old virtual group**

Run:

```bash
rg -n "prepareRestoreSwitchData|sourceSwitchData\\.linkGroupAddress|ensureBatteryPowerSwitchLinkGroup|createGroup\\(" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- `prepareRestoreSwitchData` checks `sourceSwitchData.linkGroupAddress != nil`.
- `ensureBatteryPowerSwitchLinkGroup` appears only in normal/default add helpers, not inside `prepareRestoreSwitchData`.
- `createGroup(` does not appear in this file.

- [ ] **Step 2: Verify restore controller does not migrate target subscriptions**

Run:

```bash
rg -n "BatteryPowerSwitchTargetSubscription|getBatteryPowerSwitchTargetSubscriptionMessageHandles|getBatteryPowerSwitchSubscriptionMessageHandles|getBatteryPowerSwitchUnsubscriptionMessageHandles" SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected: no matches.

- [ ] **Step 3: Verify BPS append order**

Run:

```bash
sed -n '654,725p' SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

Expected:

- BPS branch calls `prepareBatteryPowerSwitchRestoreConfiguration(...)`.
- BPS branch appends optional `AttentionSet`.
- BPS branch calls `appendCompletion(appendMessages)` and `return`.
- `manualOverrideTimeout` appears after that return in the non-BPS branch.

- [ ] **Step 4: Run iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification with the failing BPS case**

Use the same BPS that produced the log:

1. Before restore, record old BPS switch id, old `proxyNodeAddress`, old `linkGroupAddress`, and selected target groups.
2. Reset the same physical BPS and enter `Restore Device Data`.
3. Restore the scanned BPS.
4. Confirm logs contain `batteryPowerSwitchKeyConfig` before any `manualOverrideTimeout`.
5. Confirm no `manualOverrideTimeout` is sent to the BPS node address.
6. Confirm the restore row completes without red exclamation when BPS Key Config / TX / LED succeed.
7. Confirm the old switch card remains the same business record.
8. Confirm `proxyNodeAddress` changes to the new node address.
9. Confirm `linkGroupAddress` is unchanged.
10. Confirm target groups are unchanged and do not enter target subscription sync.
11. Press physical BPS keys and confirm the existing target groups respond.

- [ ] **Step 6: Manual regression with a light restore**

1. Restore a normal light.
2. Confirm generic restore still sends light/default messages.
3. Confirm light restore still enters `.devices(...)` sync when `node.needSync` is true.

---

## Notes

- Do not modify `NordicSigMeshSDK` for this fix. The SDK removing old same-UUID nodes is established behavior and should be treated as an input to the app-level restore flow.
- Do not create a new virtual group for BPS restore.
- Do not migrate BPS target subscriptions in restore.
- Do not clear `unbindGroupAddresses` on BPS restore success; keep `clearRemovedGroups: false`.
