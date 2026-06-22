# EFC iPad Layout And Cloud Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align EFC items in iPad Others with Lights sizing/centering and make EFC Edit cloud synchronization explicitly verifiable, including sync-result state persistence.

**Architecture:** Keep the existing UIKit collection layout and Space cloud sync architecture. Fix the iPad layout at `DeviceOthersViewController`, keep EFC cloud sync on the existing `.device` promptly path, and strengthen `scripts/check_efc_controller_flows.sh` so future changes cannot silently remove the contract.

**Tech Stack:** Swift, UIKit, SnapKit, existing `AlignCenterFlowLayout`, existing `SpaceData` import/export, existing `CloudSynchronizationManager`, Bash contract script, Xcode iPhoneOS build.

---

## File Structure

- Modify `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
  - Responsibility: Others page layout and item interactions.
  - Change: use the same layout variables as Lights for iPad item spacing, row count, and content inset.

- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift`
  - Responsibility: EFC sync task lifecycle and persisted sync status.
  - Change: after a persisted sync result is saved, notify Space data changed as `.device` so the `isSynced` state and related EFC data enter cloud upload.

- Modify `scripts/check_efc_controller_flows.sh`
  - Responsibility: static contract guard for EFC flows.
  - Change: add assertions for iPad Others layout parity, EFC export payload, EFC import guard, EFC Edit promptly sync, and sync-success cloud notification.

No new app modules, resources, localization keys, Auth data, or target configuration changes are required.

---

### Task 1: Add Contract Guards Before Changing Code

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add iPad Others layout contract assertions**

Insert these assertions near the existing `DeviceOthersViewController.swift` assertions:

```bash
assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "flowLayout.minimumLineSpacing = itemMargin" \
  "Others page must use the shared itemMargin for line spacing so iPad EFC items match Lights."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "flowLayout.minimumInteritemSpacing = itemMargin" \
  "Others page must use the shared itemMargin for interitem spacing so iPad EFC items match Lights."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "flowLayout.itemRowCount = columnNum" \
  "Others page must tell AlignCenterFlowLayout the configured column count."

assert_contains "SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift" \
  "collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(50 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: 0, right: collectionViewMargin)" \
  "Others page iPad content inset must match Lights so EFC cards have the same width budget."
```

- [ ] **Step 2: Add EFC cloud sync contract assertions**

Insert these assertions near the existing EFC import/export assertions:

```bash
assert_contains "SunSmart/Common/Data/ExportData.swift" \
  "spaceJsonData.updateValue(emergencyFireControllerDicts, forKey: \"emergencyFireControllers\")" \
  "Space export must include EFC controllers in cloud payload."

assert_contains "SunSmart/Common/Data/ExportData.swift" \
  "dict.updateValue(configuration, forKey: \"configuration\")" \
  "Space export must include EFC controller configuration."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift" \
  "spaceDataChangedNotificaitonName" \
  "Persisted EFC sync result must trigger Space cloud sync."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift" \
  "SpaceChangeDataType.device" \
  "Persisted EFC sync result must use promptly device cloud sync."
```

- [ ] **Step 3: Run contract script and verify it fails**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
FAIL: Others page must use the shared itemMargin for line spacing so iPad EFC items match Lights.
```

The first failure proves the contract detects the current layout bug before implementation.

- [ ] **Step 4: Commit contract guards**

Run:

```bash
git add scripts/check_efc_controller_flows.sh
git commit -m "test: guard efc layout and cloud sync contracts"
```

---

### Task 2: Align iPad Others Layout With Lights

**Files:**
- Modify: `SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Replace hard-coded Others flow layout spacing**

In `setupUI()`, replace:

```swift
flowLayout = AlignCenterFlowLayout()
flowLayout.minimumLineSpacing = SCRXFrom(16)
flowLayout.minimumInteritemSpacing = SCRXFrom(16)
flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
```

with:

```swift
flowLayout = AlignCenterFlowLayout()
flowLayout.minimumLineSpacing = itemMargin
flowLayout.minimumInteritemSpacing = itemMargin
flowLayout.itemRowCount = columnNum
flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: collectionViewMargin, right: 0)
```

- [ ] **Step 2: Add Lights-style content inset to Others collection view**

After creating `collectionView`, add:

```swift
collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(50 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: 0, right: collectionViewMargin)
```

Keep the existing background color, cell registrations, gestures, data source, and delegate unchanged.

- [ ] **Step 3: Run contract script and verify layout assertions pass**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
```

The script should exit 0 with no output.

- [ ] **Step 4: Commit layout fix**

Run:

```bash
git add SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift scripts/check_efc_controller_flows.sh
git commit -m "fix: align efc others ipad layout"
```

---

### Task 3: Persist EFC Sync Result To Cloud

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Add a local cloud-sync notification helper**

Inside `EmerFireAlarmControllerSyncVC`, add this private helper near `finishSync(success:)`:

```swift
private func notifySpaceDataChangedForPersistedResult() {
    NotificationCenter.default.post(
        name: .init(spaceDataChangedNotificaitonName),
        object: SpaceChangeDataType.device
    )
}
```

- [ ] **Step 2: Notify after persisted sync result save**

In `finishSync(success:)`, replace:

```swift
if persistsSyncResult {
    DeviceEmerFireStore.shared.save(data)
}
```

with:

```swift
if persistsSyncResult {
    DeviceEmerFireStore.shared.save(data)
    notifySpaceDataChangedForPersistedResult()
}
```

This keeps non-persisted sync flows unchanged and only uploads state after the local EFC record was actually saved.

- [ ] **Step 3: Run contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
```

The script should exit 0 with no output.

- [ ] **Step 4: Commit sync-result cloud notification**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift scripts/check_efc_controller_flows.sh
git commit -m "fix: upload efc sync result state"
```

---

### Task 4: Verify Cloud Payload And Import Contract

**Files:**
- Inspect: `SunSmart/Common/Data/ExportData.swift`
- Inspect: `SunSmart/Common/Data/ImportData.swift`
- Test: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Confirm export contains EFC configuration**

Run:

```bash
rg -n "emergencyFireControllerDicts|emergencyFireControllers|dict.updateValue\\(configuration, forKey: \"configuration\"\\)" SunSmart/Common/Data/ExportData.swift
```

Expected output includes:

```text
let emergencyFireControllerDicts = DeviceEmerFireData
dict.updateValue(configuration, forKey: "configuration")
spaceJsonData.updateValue(emergencyFireControllerDicts, forKey: "emergencyFireControllers")
```

- [ ] **Step 2: Confirm import only overwrites when EFC payload exists**

Run:

```bash
rg -n "json\\[\"emergencyFireControllers\"\\]\\.exists\\(\\)|DeviceEmerFireData.deleteAll|controllerJson\\[\"configuration\"\\]" SunSmart/Common/Data/ImportData.swift
```

Expected output includes:

```text
if json["emergencyFireControllers"].exists() {
DeviceEmerFireData.deleteAll(meshUUID: meshUUID, networkId: self.meshNetworkId)
if let configurationDict = controllerJson["configuration"].dictionaryObject,
```

- [ ] **Step 3: Run full EFC contract script**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected:

```text
```

The script should exit 0 with no output.

---

### Task 5: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Check working tree diff**

Run:

```bash
git status --short
git diff --check
```

Expected:

```text
```

`git diff --check` should exit 0. `git status --short` should show only intentional changes if a previous task was not committed.

- [ ] **Step 2: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Manual QA handoff**

Use this checklist for manual verification:

```text
1. iPad: open Devices > Lights and note item size/centering.
2. iPad: open Devices > Others and confirm EFC item size/centering matches Lights.
3. Owner: edit EFC configuration and save.
4. Owner: wait for cloud sync success or no pending cloud sync indicator.
5. Editor: re-enter Space or manually trigger Space data pull.
6. Editor: open EFC Edit and confirm latest configuration is visible.
7. Editor: edit EFC configuration and save.
8. Owner: re-enter Space or manually trigger Space data pull.
9. Owner: open EFC Edit and confirm latest configuration is visible.
```

- [ ] **Step 4: Final commit if needed**

If Task 4 or Task 5 produced committed-code changes, run:

```bash
git add SunSmart/Main/Device/Others/Controller/DeviceOthersViewController.swift SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmControllerSyncVC.swift scripts/check_efc_controller_flows.sh
git commit -m "fix: finalize efc ipad layout cloud sync"
```

If all implementation tasks were already committed, skip this step.

---

## Self-Review

- Spec coverage: iPad Others layout parity is covered by Task 1 and Task 2. EFC Edit cloud upload and sync-result state persistence are covered by Task 1, Task 3, and Task 4. Existing import/export behavior and no same-page realtime push boundary are preserved.
- Placeholder scan: no red-flag placeholders remain.
- Type consistency: all referenced files and symbols already exist in the project: `DeviceOthersViewController`, `EmerFireAlarmControllerSyncVC`, `spaceDataChangedNotificaitonName`, `SpaceChangeDataType.device`, `SpaceData.export()`, and `SpaceData.update(spaceJsonData:)`.
