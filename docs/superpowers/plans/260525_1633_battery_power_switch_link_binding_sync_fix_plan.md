# Battery Power Switch LINK Binding Sync Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复虚拟 Battery Power Switch LINK 真实设备后仍显示未关联、且真实开关不能控制 target groups 的问题。

**Architecture:** 把 LINK 后的绑定结果作为同一条 BPS 数据写回数据库和 `MeshNetworkManager.instance.switchs` 内存缓存，确保编辑页回调读取到 linked BPS。然后复用现有 `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 执行 target group subscription，不新增协议或同步通道。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 Mesh provisioning、`PJEightKeySwitchData`、`BatteryPowerSwitchAddConfiguration`、`SyncDevicesViewController`。

---

## File Structure

- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
  - 让 BPS LINK finalize 的持久化逻辑同时更新基础 switch 表、8-key metadata 表和 `MeshNetworkManager.instance.switchs` 内存缓存。
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
  - LINK 完成回调只在确认已读取到 linked BPS 后才提示 `done!` 或进入 target sync，避免旧缓存导致假成功。

---

### Task 1: Persist Linked BPS Back To Memory Cache

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

- [ ] **Step 1: Inspect current finalize persist methods**

Run:

```bash
rg -n "static func markSucceeded|static func markFailed|private static func persist" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- `markSucceeded(_:)` and `markFailed(_:reason:)` call the private `persist(_:)`.
- `persist(_:)` currently only writes database tables and does not update `MeshNetworkManager.instance.switchs`.

- [ ] **Step 2: Replace the three persist-related methods**

In `BatteryPowerSwitchAddConfiguration.swift`, replace `markSucceeded(_:)`, `markFailed(_:reason:)`, and `persist(_:)` with:

```swift
    @discardableResult
    static func markSucceeded(_ switchData: PJEightKeySwitchData) -> Bool {
        switchData.markBatteryPowerSwitchSyncSucceeded()
        return persist(switchData)
    }

    @discardableResult
    static func markFailed(_ switchData: PJEightKeySwitchData, reason: String?) -> Bool {
        switchData.markBatteryPowerSwitchSyncFailed(reason: reason)
        return persist(switchData)
    }

    @discardableResult
    private static func persist(_ switchData: PJEightKeySwitchData) -> Bool {
        guard switchData.save(),
              PJEightKeySwitchRepository.shared.save(switchData) else {
            return false
        }

        if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
            MeshNetworkManager.instance.switchs[index] = switchData
        } else {
            MeshNetworkManager.instance.switchs.append(switchData)
        }

        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        return true
    }
```

This keeps the existing callers compatible because the returned `Bool` is discardable.

- [ ] **Step 3: Verify no callers require signature changes**

Run:

```bash
rg -n "BatteryPowerSwitchAddConfiguration\\.markSucceeded|BatteryPowerSwitchAddConfiguration\\.markFailed" SunSmart/Main/Device SunSmart/Common
```

Expected:

- Classic and Professional finalize paths call these methods.
- No compile-time caller changes are needed because return values are optional to use.

- [ ] **Step 4: Verify the cache update exists**

Run:

```bash
rg -n "MeshNetworkManager\\.instance\\.switchs\\[index\\] = switchData|switchsRefreshNotificationName|spaceDataChangedNotificaitonName" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
```

Expected:

- The new `persist(_:)` updates an existing same-id switch or appends if missing.
- The method posts switch and space refresh notifications.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift
git commit -m "fix: persist linked battery switch cache"
```

---

### Task 2: Prevent False Done After LINK Completion

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`

- [ ] **Step 1: Inspect the current LINK completion callback**

Run:

```bash
rg -n "private func handleBatteryPowerSwitchLinkCompleted|private func isBatteryPowerSwitchLinked|private func pushBatteryPowerSwitchSync" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- `handleBatteryPowerSwitchLinkCompleted()` refreshes the view model, then may show `done!` based on `syncState` and `needSyncData`.

- [ ] **Step 2: Replace `handleBatteryPowerSwitchLinkCompleted()`**

In `PJPreAddEightKeySwitchesVC.swift`, replace the complete `handleBatteryPowerSwitchLinkCompleted()` method with:

```swift
    private func handleBatteryPowerSwitchLinkCompleted() {
        refreshEditingStateFromCurrentSwitchData()
        guard let switchData = currentEightKeySwitchData,
              isBatteryPowerSwitchLinked(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
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

This prevents the old unlinked cached object from producing a false `Done`. After Task 1, the expected path is that `currentEightKeySwitchData` is already linked; this guard is a safety check and a regression signal.

- [ ] **Step 3: Verify the callback requires a linked BPS**

Run:

```bash
rg -n "handleBatteryPowerSwitchLinkCompleted|isBatteryPowerSwitchLinked\\(switchData\\)|pushBatteryPowerSwitchSync\\(switchData\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- `handleBatteryPowerSwitchLinkCompleted()` contains `isBatteryPowerSwitchLinked(switchData)`.
- It calls `pushBatteryPowerSwitchSync(switchData)` only after the linked check and `needSyncData` check.

- [ ] **Step 4: Commit Task 2**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
git commit -m "fix: guard battery switch link completion"
```

---

### Task 3: Verify LINK Data Flow And Build

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Verify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`

- [ ] **Step 1: Verify LINK uses linked preparation and ordinary add still uses default preparation**

Run:

```bash
rg -n "prepareLinkedSwitchData|prepareSwitchData\\(for: node\\)|finalizeBatteryPowerSwitchAddConfiguration" SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
```

Expected:

- Both Classic and Professional have a `prepareLinkedSwitchData` branch when `bindToBatteryPowerSwitch` exists.
- Both Classic and Professional still have a `prepareSwitchData(for: node)` branch for ordinary BPS add.
- Both controllers call `finalizeBatteryPowerSwitchAddConfiguration(for:)` after node add success.

- [ ] **Step 2: Verify target sync can run from the editor callback**

Run:

```bash
rg -n "refreshEditingStateFromCurrentSwitchData|isBatteryPowerSwitchLinked\\(switchData\\)|switchData\\.needSyncData|pushBatteryPowerSwitchSync\\(switchData\\)" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift
```

Expected:

- The callback refreshes from current switch data.
- The callback requires linked BPS.
- The callback pushes `SyncDevicesViewController(type: .batteryPowerSwitch(...))` through `pushBatteryPowerSwitchSync(switchData)` when `needSyncData` is true.

- [ ] **Step 3: Verify no whitespace errors**

Run:

```bash
git diff --check
```

Expected:

- No output.
- Exit code `0`.

- [ ] **Step 4: Build the SunSmart iOS target**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build exits with code `0`.
- Output contains `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Check final git state**

Run:

```bash
git status --short
```

Expected:

- No uncommitted source changes.

---

## Manual Verification Checklist

- [ ] Create a virtual Battery Power Switch.
- [ ] Change profile, groups, scenes, Enable, and LED Indicator.
- [ ] From Edit, tap `LINK`.
- [ ] Add a real Battery Power Switch and finish connect.
- [ ] Confirm the original virtual BPS becomes linked and no longer shows `Unlinked`.
- [ ] If target groups were selected, confirm the app enters the existing sync page after LINK.
- [ ] After target sync succeeds, confirm the real Battery Power Switch controls the selected target groups.
- [ ] Confirm no second Battery Power Switch appears in the switch list.
