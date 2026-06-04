# Battery Power Switch Unlinked Virtual Device Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 当旧 battery power switch 的 `proxyNodeAddress` 指向无效 node 或非 battery power switch node 时，自动把旧设备降级为虚拟 BPS，并在 switches 列表中显示虚线外框。

**Architecture:** 在 `MeshNetworkManager` 的 switch 数据维护层增加归一化方法，集中清理失效的 BPS proxy 关系。网络加载后执行一次保证冷启动一致性，switches 列表刷新前执行一次轻量兜底，UI 继续复用现有 `PJEightKeySwitchData.displayStatus` 与 `PJEightKeySwitchesViewCell` 虚线外框逻辑。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, SQLite-backed local data, Xcode workspace `SunSmart.xcworkspace`

---

## File Structure

- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - Add `normalizeInvalidBatteryPowerSwitchProxyLinks(notify:)`.
  - Call it after `DeviceSwitchData.load(...)`.
  - Keep the method near switch creation/deletion helpers because it maintains switch proxy lifecycle.
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
  - Call the normalization method before deriving count, refresh availability, and collection contents.
- No new resources, no localization changes, no target/project setting changes.

## Constraints

- Only process switches that can be converted to `PJEightKeySwitchData`.
- Only process `powerSwitchKind == .battery`.
- Only clear `proxyNodeAddress`; keep name, enabled state, link group, scene fields, bind/unbind groups, battery fields, sync fields, and more settings.
- Do not change AC power switch behavior. AC offline state is not an invalid proxy.
- Do not merge old and new BPS devices.

---

### Task 1: Add BPS Proxy Normalization

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:835-869`

- [ ] **Step 1: Insert the normalization helper before `deleteSwitch(switchData:)`**

In `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`, add this method after `createDefaultSwitch(forBatteryPowerSwitch:)` and before `deleteSwitch(switchData:)`:

```swift
    @discardableResult
    func normalizeInvalidBatteryPowerSwitchProxyLinks(notify: Bool = false) -> Bool {
        guard let meshNetwork else {
            return false
        }

        var didChange = false

        for index in self.switchs.indices {
            let currentSwitch = self.switchs[index]
            let batteryPowerSwitch: PJEightKeySwitchData?
            if let eightKeySwitch = currentSwitch as? PJEightKeySwitchData {
                batteryPowerSwitch = eightKeySwitch
            } else {
                batteryPowerSwitch = PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: currentSwitch)
            }

            guard let batteryPowerSwitch,
                  batteryPowerSwitch.powerSwitchKind == .battery,
                  let proxyNodeAddress = batteryPowerSwitch.proxyNodeAddress else {
                continue
            }

            let proxyNode = meshNetwork.node(withAddress: proxyNodeAddress)
            guard proxyNode?.isBatteryPowerSwitch != true else {
                if !(currentSwitch is PJEightKeySwitchData) {
                    self.switchs[index] = batteryPowerSwitch
                }
                continue
            }

            batteryPowerSwitch.proxyNodeAddress = nil
            guard PJEightKeySwitchRepository.shared.save(batteryPowerSwitch),
                  batteryPowerSwitch.save() else {
                continue
            }

            self.switchs[index] = batteryPowerSwitch
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

- [ ] **Step 2: Inspect the inserted method**

Run: `rg -n "normalizeInvalidBatteryPowerSwitchProxyLinks|powerSwitchKind == \\.battery|isBatteryPowerSwitch != true" SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

Expected:
- One method definition.
- One guard that restricts handling to `.battery`.
- One invalid proxy check using `isBatteryPowerSwitch != true`.

- [ ] **Step 3: Commit Task 1**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: normalize invalid battery switch proxy links"
```

Expected: commit succeeds with only `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` staged.

---

### Task 2: Run Normalization After Switch Data Load

**Files:**
- Modify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:630-631`

- [ ] **Step 1: Add the load-time call**

Change this block:

```swift
            self.switchs = DeviceSwitchData.load(meshUUID: uuid, meshNetworkId: subNetworkId)
            self.dongles = DeviceDongleData.load(meshUUID: uuid, meshNetworkId: subNetworkId)
```

to:

```swift
            self.switchs = DeviceSwitchData.load(meshUUID: uuid, meshNetworkId: subNetworkId)
            self.normalizeInvalidBatteryPowerSwitchProxyLinks()
            self.dongles = DeviceDongleData.load(meshUUID: uuid, meshNetworkId: subNetworkId)
```

- [ ] **Step 2: Verify the load-time call is non-notifying**

Run: `rg -n "DeviceSwitchData\\.load|normalizeInvalidBatteryPowerSwitchProxyLinks\\(" SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

Expected:
- The call immediately follows `DeviceSwitchData.load(...)`.
- The load-time call uses default `notify: false`, so startup/subnetwork load does not post UI notifications while loading.

- [ ] **Step 3: Commit Task 2**

Run:

```bash
git add SunSmart/Common/Data/MeshNetwork+SunSmart.swift
git commit -m "fix: normalize battery switches after load"
```

Expected: commit succeeds.

---

### Task 3: Add Switches List Fallback Trigger

**Files:**
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift:211-214`

- [ ] **Step 1: Call normalization at the start of `updateUI()`**

Change the beginning of `updateUI()` from:

```swift
    private func updateUI() {
        
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.switchs.count)/16", for: .normal)
        updateRefreshControlAvailability()
```

to:

```swift
    private func updateUI() {
        
        MeshNetworkManager.instance.normalizeInvalidBatteryPowerSwitchProxyLinks()
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.switchs.count)/16", for: .normal)
        updateRefreshControlAvailability()
```

Do not pass `notify: true` here. `updateUI()` already owns the local reload path, and posting `switchsRefreshNotificationName` from inside its observer path can cause redundant refreshes.

- [ ] **Step 2: Verify the page fallback call is present**

Run: `rg -n "normalizeInvalidBatteryPowerSwitchProxyLinks|private func updateUI" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

Expected:
- One call inside `updateUI()`.
- No `notify: true` in `DeviceSwitchesViewController.swift`.

- [ ] **Step 3: Commit Task 3**

Run:

```bash
git add SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
git commit -m "fix: refresh battery switch virtual state in list"
```

Expected: commit succeeds.

---

### Task 4: Static Behavior Checks

**Files:**
- Verify: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- Verify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
- Verify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchesViewCell.swift`

- [ ] **Step 1: Confirm only BPS is normalized**

Run:

```bash
rg -n "powerSwitchKind == \\.battery|isACPowerSwitch|state == false|device_ACPowerSwitch_offline" SunSmart/Common/Data/MeshNetwork+SunSmart.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:
- Normalization checks `.battery`.
- AC offline icon logic remains only in `PJEightKeySwitchData.displayIconAssetName`.
- No normalization branch checks `node.state == false`.

- [ ] **Step 2: Confirm virtual BPS still renders as dashed BPS cell**

Run:

```bash
rg -n "makeEightKeySwitch|displayStatus|needsDashedBorder|PJEightKeySwitchesViewCell" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchStatus.swift SunSmart/Main/Device/Device1.5/NEightKeySwitches/View/PJEightKeySwitchesViewCell.swift
```

Expected:
- `DeviceSwitchesViewController` still converts metadata-backed switch data to `PJEightKeySwitchData`.
- `displayStatus` still returns unbound status when `proxyNodeAddress == nil`.
- `needsDashedBorder` is true for unbound states.
- `PJEightKeySwitchesViewCell` still applies dashed border from status.

- [ ] **Step 3: Confirm no resources, localization, target config, or dependency files changed**

Run: `git diff --name-only HEAD~3...HEAD`

Expected:
- Only these files appear:
  - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

---

### Task 5: Build Verification

**Files:**
- Verify: project build

- [ ] **Step 1: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:
- Build exits with status 0.
- No Swift compile errors from `normalizeInvalidBatteryPowerSwitchProxyLinks`.

- [ ] **Step 2: Check final git status**

Run: `git status --short`

Expected:
- Clean working tree, or only user-owned unrelated changes.

---

### Task 6: Manual Scenario Verification

**Files:**
- Manual verification only.

- [ ] **Step 1: Verify invalid proxy becomes virtual BPS**

Manual steps:
1. Use a site/space containing an existing real battery power switch.
2. Make the old switch's `proxyNodeAddress` invalid by reproducing the real scenario: manually reset the physical BPS and add it again as a new device.
3. Open the space switches list.

Expected:
- The newly added BPS appears as a normal real battery power switch.
- The old BPS remains in the switches list.
- The old BPS uses the battery power switch icon.
- The old BPS cell has a dashed border.
- Tapping the old BPS opens `PJEightKeySwitchMonitorVC`.

- [ ] **Step 2: Verify delete behavior for old virtual BPS**

Manual steps:
1. Enter edit mode in switches list.
2. Delete the old dashed BPS.

Expected:
- Delete completes through local virtual-device path.
- No real BPS reset is sent for the old virtual BPS.
- The new real BPS remains in the list.

---

## Implementation Notes

- The plan intentionally does not introduce a new `isVirtualBatteryPowerSwitch` flag. Virtual state is derived from existing data: BPS metadata plus missing/invalid real proxy.
- `PJEightKeySwitchRepository.shared.save(batteryPowerSwitch)` is called before `batteryPowerSwitch.save()` because metadata save does not alter proxy data. If base switch save fails, the method skips memory replacement to avoid presenting a state that did not persist.
- `notify` exists for future callers that need global refresh after a background normalization. Current planned callers use `notify: false` to avoid notification loops.

## Final Verification Checklist

- [ ] Invalid BPS proxy is cleared.
- [ ] AC power switch proxy is never cleared by this feature.
- [ ] Ordinary kinetic switch behavior is unchanged.
- [ ] Old BPS remains metadata-backed and opens BPS monitor.
- [ ] Old BPS displays dashed border in switches list.
- [ ] SunSmart iPhoneOS Debug build passes.
