# Space Delete Cloud Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 Lights / Switches / Others 后，立即把 Space 标记为本地待上传并排队云同步，避免重新进入 Space 时被旧云端 payload 恢复已删除数据。

**Architecture:** 在现有 `SpaceViewController.swift` 中为 `SpaceData` 增加共享本地变更提交 helper，避免新增 Swift 文件和 target membership 变更。删除入口完成本地数据移除后直接调用 helper，不再依赖 `spaceDataChangedNotificaitonName` 作为唯一 dirty/sync 入口；`SpaceViewController` 原通知观察者也复用同一个 helper，保持非删除路径语义一致。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、现有 `CloudSynchronizationManager`、现有 shell contract scripts、iPhoneOS `xcodebuild`。

---

## File Structure

- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - Add `SpaceChangeDataType.cloudSyncLevel`.
  - Add `SpaceData.commitLocalChangeForCloudSync(site:changeType:)`.
  - Replace the existing `spaceDataChangedNotificaitonName` observer body with the shared helper.
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`
  - Replace delete-success `space.deviceCount/luminairesCount/save` + `spaceDataChangedNotificaitonName` posts with direct helper calls.
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`
  - Replace `spaceDataChangedNotificaitonName` post in `deleteCache(switchData:)` with direct helper call.
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
  - Replace manual Space count save + `spaceDataChangedNotificaitonName` post in `finishDeleteOthersItem()` with direct helper call.
- Create: `scripts/check_space_delete_cloud_restore.sh`
  - Static contract guarding helper existence and delete-entry adoption.
- Test/Verify:
  - `bash scripts/check_space_delete_cloud_restore.sh`
  - `git diff --check`
  - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

---

### Task 1: Add Shared Space Local Change Committer

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1: Add sync-level mapping and SpaceData helper near `SpaceChangeDataType`**

Insert this code immediately after the `SpaceChangeDataType` enum:

```swift
fileprivate extension SpaceChangeDataType {
    var cloudSyncLevel: SyncLevel {
        switch self {
        case .common:
            return .slow
        case .device, .network:
            return .promptly
        }
    }
}

extension SpaceData {
    func commitLocalChangeForCloudSync(site currentSite: SiteData? = nil, changeType: SpaceChangeDataType) {
        refreshSummaryCountsFromCurrentMesh()

        guard permission == .owner || permission == .editor else {
            save()
            return
        }

        markSpaceUploadNeeded()
        guard let site = currentSite ?? SiteData.load(siteId: siteId) else {
            save()
            return
        }

        switch changeType {
        case .device:
            enqueueSpaceSync(site: site, level: changeType.cloudSyncLevel)
        case .common:
            enqueueSpaceSync(site: site, level: changeType.cloudSyncLevel)
        case .network(let type):
            switch type {
            case .ivIndex:
                CloudSynchronizationManager.shared.addSynchronizationHandle(
                    operation: .syncSite(site: site),
                    level: changeType.cloudSyncLevel
                )
            case .address:
                site.markSiteUploadNeededForSpaceAddressChange()
                CloudSynchronizationManager.shared.addSynchronizationHandle(
                    operation: .syncSite(site: site, syncSpaces: [self]),
                    level: changeType.cloudSyncLevel
                )
            }
        }
    }

    private func refreshSummaryCountsFromCurrentMesh() {
        let nodes = MeshNetworkManager.instance.realNodes
        deviceCount = nodes.count
        luminairesCount = nodes.filter { $0.deviceType == .light }.count
        groupCount = MeshNetworkManager.instance.groups.count
        sceneCount = MeshNetworkManager.instance.scenes.count
        scheheduleCount = MeshNetworkManager.instance.schedules.count
        switchesCount = MeshNetworkManager.instance.switchs.count
    }

    private func markSpaceUploadNeeded() {
        let now = Int64(Date().timeIntervalSince1970)
        lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)
        save()
    }

    private func enqueueSpaceSync(site: SiteData, level: SyncLevel) {
        if site.uploadCloud {
            CloudSynchronizationManager.shared.addSynchronizationHandle(
                operation: .syncSpace(space: self),
                level: level
            )
        } else {
            CloudSynchronizationManager.shared.addSynchronizationHandle(
                operation: .syncSite(site: site, syncSpaces: site.spaces),
                level: level
            )
        }
    }
}

fileprivate extension SiteData {
    func markSiteUploadNeededForSpaceAddressChange() {
        let now = Int64(Date().timeIntervalSince1970)
        lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)
        save()
    }
}
```

- [ ] **Step 2: Replace the SpaceViewController notification observer body**

In `SpaceViewController.addNotificationObserver()`, replace the current `spaceDataChangedNotificaitonName` observer block:

```swift
NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: .main) {[weak self] notification in
    guard let self = self, let type = notification.object as? SpaceChangeDataType, self.space.permission == .owner || self.space.permission == .editor else { return }
    self.space.lastUpdate = Int64(Date().timeIntervalSince1970)
    self.space.save()
    switch type {
    case .device:
        self.syncSpace(level: .promptly)
    case .common:
        self.syncSpace(level: .slow)
    case .network(let type):
        if type == .ivIndex {
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: self.site), level: .promptly)
        }else if type == .address {
            self.site.lastUpdate = Int64(Date().timeIntervalSince1970)
            self.site.save()
//                    DispatchQueue.global().async {
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: self.site, syncSpaces: [self.space]), level: .promptly)
//                    }
        }
    }
}
```

with:

```swift
NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: .main) { [weak self] notification in
    guard let self,
          let type = notification.object as? SpaceChangeDataType else {
        return
    }
    self.space.commitLocalChangeForCloudSync(site: self.site, changeType: type)
}
```

- [ ] **Step 3: Remove now-unused private syncSpace helper if the compiler reports it unused**

After replacing the observer, `private func syncSpace(level:)` may no longer be referenced in `SpaceViewController.swift`. If `rg -n "syncSpace\\(" SunSmart/Main/Space/Controller/SpaceViewController.swift` shows only the function definition, delete this block:

```swift
/// 同步space
private func syncSpace(level: SyncLevel) {
    // site已上传服务器
    if self.site.uploadCloud {
        // 同步space
        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: level)
    }else {
        // 未上传服务器，site、space一起上传
        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: level)
    }
}
```

- [ ] **Step 4: Commit Task 1**

```bash
git add SunSmart/Main/Space/Controller/SpaceViewController.swift
git commit -m "fix: centralize space local cloud changes"
```

---

### Task 2: Update Lights Delete Flow

**Files:**
- Modify: `SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift`

- [ ] **Step 1: Replace immediate count save after successful reset addresses**

Find this block inside `deleteNodes()` after `successAddressList.forEach`:

```swift
self.selectedAddresss.removeAll(where: { successAddressList.contains($0) })
self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
self.space.luminairesCount = self.devices.count
self.space.save()
```

Replace it with:

```swift
self.selectedAddresss.removeAll(where: { successAddressList.contains($0) })
if !successAddressList.isEmpty {
    self.space.commitLocalChangeForCloudSync(site: self.site, changeType: .network(type: .address))
}
```

- [ ] **Step 2: Remove all-success `spaceDataChangedNotificaitonName` post**

In the `failAddressList.isEmpty` branch, delete this direct sync notification:

```swift
// 通知space数据修改
//                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
```

Do not replace it; the helper call from Step 1 already marked the Space dirty and enqueued cloud sync.

- [ ] **Step 3: Replace partial-success cancel branch sync notification**

Inside the `alert_item_cancel` action, replace this block:

```swift
if successAddressList.count > 0 {
    // 通知space数据修改
//                            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
}
```

with:

```swift
if !successAddressList.isEmpty {
    self?.space.commitLocalChangeForCloudSync(site: self?.site, changeType: .network(type: .address))
}
```

- [ ] **Step 4: Replace force-delete count save with helper**

Inside the `force_delete` action, replace:

```swift
self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
self.space.luminairesCount = self.devices.count
self.space.save()

XWHUDManager.showSuccessTipHUD("done!".localizedString)
// 通知space数据修改
NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
```

with:

```swift
self.space.commitLocalChangeForCloudSync(site: self.site, changeType: .network(type: .address))

XWHUDManager.showSuccessTipHUD("done!".localizedString)
```

- [ ] **Step 5: Run static grep check for old Lights address notification**

Run:

```bash
rg -n "spaceDataChangedNotificaitonName\\), object: SpaceChangeDataType\\.network\\(type: \\.address\\)" SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift
```

Expected: no output.

- [ ] **Step 6: Commit Task 2**

```bash
git add SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift
git commit -m "fix: mark space dirty after light delete"
```

---

### Task 3: Update Switches Delete Flow

**Files:**
- Modify: `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

- [ ] **Step 1: Replace sync notification in `deleteCache(switchData:)`**

Replace:

```swift
MeshNetworkManager.instance.deleteSwitch(switchData: switchData)
NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
```

with:

```swift
MeshNetworkManager.instance.deleteSwitch(switchData: switchData)
space.commitLocalChangeForCloudSync(changeType: .device)
NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
```

- [ ] **Step 2: Run static grep check for old Switches sync notification**

Run:

```bash
rg -n "spaceDataChangedNotificaitonName" SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
```

Expected: no output.

- [ ] **Step 3: Commit Task 3**

```bash
git add SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift
git commit -m "fix: mark space dirty after switch delete"
```

---

### Task 4: Update Others Delete Flow

**Files:**
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`

- [ ] **Step 1: Replace manual count save in `finishDeleteOthersItem()`**

Replace:

```swift
space.deviceCount = MeshNetworkManager.instance.realNodes.count
space.luminairesCount = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }.count
space.save()
reloadShowItems()
```

with:

```swift
space.commitLocalChangeForCloudSync(changeType: .network(type: .address))
reloadShowItems()
```

- [ ] **Step 2: Remove old sync notification in `finishDeleteOthersItem()`**

Delete this line:

```swift
NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
```

Keep these refresh notifications:

```swift
NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
```

- [ ] **Step 3: Run static grep check for old Others sync notification**

Run:

```bash
rg -n "spaceDataChangedNotificaitonName" SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
```

Expected: no output.

- [ ] **Step 4: Commit Task 4**

```bash
git add SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift
git commit -m "fix: mark space dirty after others delete"
```

---

### Task 5: Add Static Contract Script

**Files:**
- Create: `scripts/check_space_delete_cloud_restore.sh`

- [ ] **Step 1: Create contract script**

Create `scripts/check_space_delete_cloud_restore.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SPACE_FILE="$ROOT_DIR/SunSmart/Main/Space/Controller/SpaceViewController.swift"
LIGHTS_FILE="$ROOT_DIR/SunSmart/Main/Device/Lights/Controller/DeviceLightsViewController.swift"
SWITCHES_FILE="$ROOT_DIR/SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift"
OTHERS_FILE="$ROOT_DIR/SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift"
SENSORS_FILE="$ROOT_DIR/SunSmart/Main/Device/Sensors/Controller/DeviceSensorsViewController.swift"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "Missing pattern: $pattern" >&2
    echo "File: $file" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if grep -Fq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "Unexpected pattern: $pattern" >&2
    echo "File: $file" >&2
    exit 1
  fi
}

assert_contains "$SPACE_FILE" "func commitLocalChangeForCloudSync(site currentSite: SiteData? = nil, changeType: SpaceChangeDataType)" \
  "SpaceData must expose a shared local-change cloud commit helper."
assert_contains "$SPACE_FILE" "lastUpdate = max(now, lastUpdate + 1, (lastUploadCloudTimestamp ?? 0) + 1)" \
  "Space dirty timestamp must become newer than the last upload timestamp, even within the same second."
assert_contains "$SPACE_FILE" "site.markSiteUploadNeededForSpaceAddressChange()" \
  "Address-changing deletes must also dirty the parent Site before syncSite."
assert_contains "$SPACE_FILE" "self.space.commitLocalChangeForCloudSync(site: self.site, changeType: type)" \
  "SpaceViewController notification observer must reuse the shared helper."

assert_contains "$LIGHTS_FILE" "self.space.commitLocalChangeForCloudSync(site: self.site, changeType: .network(type: .address))" \
  "Lights delete flow must directly mark Space dirty after local node deletion."
assert_not_contains "$LIGHTS_FILE" "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))" \
  "Lights delete flow must not rely on the Space data-changed notification for cloud dirtying."

assert_contains "$SWITCHES_FILE" "space.commitLocalChangeForCloudSync(changeType: .device)" \
  "Switches delete flow must directly mark Space dirty after deleting switch data."
assert_not_contains "$SWITCHES_FILE" "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)" \
  "Switches delete flow must not rely on the Space data-changed notification for cloud dirtying."

assert_contains "$OTHERS_FILE" "space.commitLocalChangeForCloudSync(changeType: .network(type: .address))" \
  "Others delete flow must directly mark Space dirty after deleting node-backed items."
assert_not_contains "$OTHERS_FILE" "NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))" \
  "Others delete flow must not rely on the Space data-changed notification for cloud dirtying."

assert_contains "$SENSORS_FILE" "collectionView.showEmptyDataView(title: \"no_sensors\".localizedString" \
  "Sensors page should remain an empty-state page with no delete flow in this task."

echo "PASS: Space delete cloud restore contracts hold."
```

- [ ] **Step 2: Make script executable**

Run:

```bash
chmod +x scripts/check_space_delete_cloud_restore.sh
```

- [ ] **Step 3: Run contract script**

Run:

```bash
bash scripts/check_space_delete_cloud_restore.sh
```

Expected:

```text
PASS: Space delete cloud restore contracts hold.
```

- [ ] **Step 4: Commit Task 5**

```bash
git add scripts/check_space_delete_cloud_restore.sh
git commit -m "test: add space delete restore contract"
```

---

### Task 6: Final Verification

**Files:**
- Verify only; no planned source edits.

- [ ] **Step 1: Run contract script**

Run:

```bash
bash scripts/check_space_delete_cloud_restore.sh
```

Expected:

```text
PASS: Space delete cloud restore contracts hold.
```

- [ ] **Step 2: Run diff whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git status --short
git log --oneline -n 6
```

Expected:

- Working tree is clean after the task commits.
- Recent commits include:
  - `fix: centralize space local cloud changes`
  - `fix: mark space dirty after light delete`
  - `fix: mark space dirty after switch delete`
  - `fix: mark space dirty after others delete`
  - `test: add space delete restore contract`

- [ ] **Step 5: Manual QA checklist**

Use a cloud-backed owner/editor Space:

1. In `Site - Space - Main - Lights`, delete all Lights devices.
2. Return to Site.
3. Confirm Space Item shows zero devices.
4. Immediately click the same Space Item again.
5. Confirm deleted devices do not reappear in `Main - Lights`.
6. Repeat equivalent checks for `Main - Switches` and `Main - Others` with available delete-capable items.
7. Confirm `Main - Sensors` remains unchanged as an empty-state page.

---

## Self-Review

- Spec coverage:
  - Lights delete restore risk is covered by Task 2.
  - Switches delete restore risk is covered by Task 3.
  - Others delete restore risk is covered by Task 4.
  - Sensors no-op scope is covered by Task 5 contract and manual QA.
  - Shared local dirty/sync contract is covered by Task 1.
- Completeness scan:
  - No incomplete steps or undefined helper names remain.
- Type consistency:
  - `commitLocalChangeForCloudSync(site:changeType:)` is introduced before all call sites.
  - `SpaceChangeDataType.cloudSyncLevel` is introduced before helper usage.
  - `SiteData.markSiteUploadNeededForSpaceAddressChange()` is introduced before helper usage.
