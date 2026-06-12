# Space Content Display Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Do not use subagents unless the user explicitly requests them. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Space-level data persistence and cloud import/export support for `displayDeviceNamePrefix`, `showCCTQuickButtons`, and `controlType`.

**Architecture:** Treat Content Display settings as first-class `SpaceData` fields. Persist them in the existing `spaces` table, export/import them at the Space JSON root, and reuse the existing `spaceDataChangedNotificaitonName` + `SpaceChangeDataType.common` sync trigger. UI rows for the two new settings are out of scope, but the existing `Display device name prefix` row should start using the same sync trigger.

**Tech Stack:** Swift, SQLite.swift expressions, SwiftyJSON, existing `SpaceData` import/export, existing `CloudSynchronizationManager`, Xcode iPhoneOS build.

---

## Scope Notes

- There is no existing app unit test scheme in `SunSmart.xcworkspace -list`; do not create a new test target for this small data-layer change.
- Verification is compiler-driven plus targeted source checks and the final iPhoneOS build.
- Preserve the existing untracked file `docs/260610_1754_content_display_cloud_sync_analysis.md`; do not stage or modify it unless the user asks.

## Files

- Modify: `SunSmart/Common/Data/SpaceData.swift`
  - Add `SpaceControlType`.
  - Add `showCCTQuickButtons` and `controlType`.
  - Copy the two new fields in `copy()`.
- Modify: `SunSmart/Common/Data/Database.swift`
  - Add two column expressions.
  - Add columns during table creation.
  - Add old-database migration checks.
  - Load and save both new fields.
- Modify: `SunSmart/Common/Data/ExportData.swift`
  - Add the three Content Display fields to Space JSON root.
- Modify: `SunSmart/Common/Data/ImportData.swift`
  - Read the three Content Display fields from Space JSON root with compatibility defaults.
- Modify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`
  - Change the existing prefix switch save path to trigger `SpaceChangeDataType.common` instead of only `space.save()`.

## Cloud JSON Contract

The Space JSON root must include:

```json
{
  "displayDeviceNamePrefix": true,
  "showCCTQuickButtons": false,
  "controlType": "simple"
}
```

Field rules:

- `displayDeviceNamePrefix`: Boolean, default `true`.
- `showCCTQuickButtons`: Boolean, default `false`.
- `controlType`: String, default `"simple"`, allowed `"simple"` and `"detailed"`.
- Unknown `controlType` values are read as `"simple"`.

---

### Task 1: Add SpaceData Fields

**Files:**
- Modify: `SunSmart/Common/Data/SpaceData.swift`

- [ ] **Step 1: Confirm current fields are absent**

Run:

```sh
rg -n "showCCTQuickButtons|SpaceControlType|controlType" SunSmart/Common/Data/SpaceData.swift
```

Expected: no output.

- [ ] **Step 2: Add the control type enum**

In `SunSmart/Common/Data/SpaceData.swift`, add this enum near the other Space-level supporting types, before `class SpaceData`:

```swift
enum SpaceControlType: String {
    /// 简单的控制控件
    case simple
    /// 复杂的控制控件
    case detailed
}
```

- [ ] **Step 3: Add the two new SpaceData properties**

Near the existing `displayDeviceNamePrefix` property, change the block to:

```swift
    /// 是否显示设备前缀（默认true）  true：【group name - device name】 false：device name
    var displayDeviceNamePrefix: Bool = true
    /// 是否在色温控制控件中展示快捷按钮（默认false）
    var showCCTQuickButtons: Bool = false
    /// 控制控件类型（默认simple）
    var controlType: SpaceControlType = .simple
    /// 设备配置成功行为
    var deviceBlinkMode: DeviceBlinkMode = .none
```

- [ ] **Step 4: Copy the new fields**

In `copy()`, after `space.displayDeviceNamePrefix = self.displayDeviceNamePrefix`, add:

```swift
        space.showCCTQuickButtons = self.showCCTQuickButtons
        space.controlType = self.controlType
```

- [ ] **Step 5: Build to catch model errors**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: compile may still fail later if database references are not added yet, but it must not fail because `SpaceControlType` is malformed or unavailable in `SpaceData.swift`.

---

### Task 2: Persist Fields in the Local Database

**Files:**
- Modify: `SunSmart/Common/Data/Database.swift`

- [ ] **Step 1: Confirm database columns are absent**

Run:

```sh
rg -n "showCCTQuickButtons|controlType" SunSmart/Common/Data/Database.swift
```

Expected: no output before this task.

- [ ] **Step 2: Add SQLite expressions**

In `SpaceData.ExpressionKey`, after `displayDeviceNamePrefix`, add:

```swift
        static let showCCTQuickButtons = Expression<Bool>("showCCTQuickButtons")
        static let controlType = Expression<String>("controlType")
```

- [ ] **Step 3: Add columns when creating the table**

In `SpaceData.initDatabase()`, after:

```swift
            builder.column(ExpressionKey.displayDeviceNamePrefix, defaultValue: true)
```

add:

```swift
            builder.column(ExpressionKey.showCCTQuickButtons, defaultValue: false)
            builder.column(ExpressionKey.controlType, defaultValue: SpaceControlType.simple.rawValue)
```

- [ ] **Step 4: Add old-database migration checks**

After the existing `displayDeviceNamePrefix` migration block, add:

```swift
            // 是否存在”showCCTQuickButtons“属性
            if !columns.contains(where: { $0.name == "showCCTQuickButtons" }) {
                _ = try? SunSmartDataManager.shared.db?.run(SpaceData.spacesTable.addColumn(ExpressionKey.showCCTQuickButtons, defaultValue: false))
            }
            // 是否存在”controlType“属性
            if !columns.contains(where: { $0.name == "controlType" }) {
                _ = try? SunSmartDataManager.shared.db?.run(SpaceData.spacesTable.addColumn(ExpressionKey.controlType, defaultValue: SpaceControlType.simple.rawValue))
            }
```

- [ ] **Step 5: Load fields by site/space**

In `SpaceData.load(siteId:spaceId:)`, after:

```swift
                space.displayDeviceNamePrefix = row[ExpressionKey.displayDeviceNamePrefix]
```

add:

```swift
                space.showCCTQuickButtons = row[ExpressionKey.showCCTQuickButtons]
                space.controlType = SpaceControlType(rawValue: row[ExpressionKey.controlType]) ?? .simple
```

- [ ] **Step 6: Load fields by subnetwork**

In `SpaceData.load(subNetworkId:)`, after:

```swift
                newSpace.displayDeviceNamePrefix = row[ExpressionKey.displayDeviceNamePrefix]
```

add:

```swift
                newSpace.showCCTQuickButtons = row[ExpressionKey.showCCTQuickButtons]
                newSpace.controlType = SpaceControlType(rawValue: row[ExpressionKey.controlType]) ?? .simple
```

- [ ] **Step 7: Save fields**

In `SpaceData.save()`, after:

```swift
            ExpressionKey.displayDeviceNamePrefix <- self.displayDeviceNamePrefix,
```

add:

```swift
            ExpressionKey.showCCTQuickButtons <- self.showCCTQuickButtons,
            ExpressionKey.controlType <- self.controlType.rawValue,
```

- [ ] **Step 8: Build to verify persistence wiring**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds or reports only issues unrelated to the touched files. Any error referencing `showCCTQuickButtons`, `controlType`, `SpaceControlType`, or SQLite expression types must be fixed before continuing.

---

### Task 3: Add Space JSON Export and Import

**Files:**
- Modify: `SunSmart/Common/Data/ExportData.swift`
- Modify: `SunSmart/Common/Data/ImportData.swift`

- [ ] **Step 1: Confirm JSON fields are absent from export/import**

Run:

```sh
rg -n "displayDeviceNamePrefix|showCCTQuickButtons|controlType" SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected before this task: no output for these three JSON field names in `ExportData.swift` or `ImportData.swift`.

- [ ] **Step 2: Export all three fields**

In `SpaceData.export()`, after:

```swift
            spaceJsonData.updateValue(Int64(self.lastUpdate) , forKey: "updateTimestamp")
```

add:

```swift
            spaceJsonData.updateValue(self.displayDeviceNamePrefix, forKey: "displayDeviceNamePrefix")
            spaceJsonData.updateValue(self.showCCTQuickButtons, forKey: "showCCTQuickButtons")
            spaceJsonData.updateValue(self.controlType.rawValue, forKey: "controlType")
```

The resulting JSON root must match:

```json
{
  "displayDeviceNamePrefix": true,
  "showCCTQuickButtons": false,
  "controlType": "simple"
}
```

- [ ] **Step 3: Import all three fields**

In `SpaceData.update(spaceJsonData:initialize:)`, near the existing `deviceBlinkMode` and `triggerZones` imports, add this block before `deviceBlinkMode` is read:

```swift
            if let value = json["displayDeviceNamePrefix"].bool {
                self.displayDeviceNamePrefix = value
            }else {
                self.displayDeviceNamePrefix = true
            }
            if let value = json["showCCTQuickButtons"].bool {
                self.showCCTQuickButtons = value
            }else {
                self.showCCTQuickButtons = false
            }
            if let value = json["controlType"].string, let type = SpaceControlType(rawValue: value) {
                self.controlType = type
            }else {
                self.controlType = .simple
            }
```

- [ ] **Step 4: Verify JSON field locations by source search**

Run:

```sh
rg -n "displayDeviceNamePrefix|showCCTQuickButtons|controlType" SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected: all three field names appear in both export and import paths.

- [ ] **Step 5: Build to verify import/export code**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds or reports only issues unrelated to the touched files. Any error in `ExportData.swift` or `ImportData.swift` must be fixed before continuing.

---

### Task 4: Trigger Sync From Existing Content Display Save

**Files:**
- Modify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`

- [ ] **Step 1: Confirm current save path bypasses sync**

Run:

```sh
sed -n '92,110p' SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected before implementation: the callback assigns `self.space.displayDeviceNamePrefix = isOn` and calls `self.space.save()`.

- [ ] **Step 2: Add a shared change notification helper**

Inside `ContentDisplayViewController`, before the closing brace of the main class body and after `setupUI()`, add:

```swift
    private func notifyContentDisplayChanged() {
        NotificationCenter.default.post(
            name: .init(spaceDataChangedNotificaitonName),
            object: SpaceChangeDataType.common
        )
    }
```

- [ ] **Step 3: Update the existing prefix switch callback**

Replace the existing `.deviceNameDisplay` callback with:

```swift
        switch option {
        case .deviceNameDisplay:
            cell.enableSwitch.isOn = space.displayDeviceNamePrefix
            cell.switchValueCallback = {[weak self] isOn in
                guard let self = self else { return }
                guard self.space.displayDeviceNamePrefix != isOn else { return }
                self.space.displayDeviceNamePrefix = isOn
                self.notifyContentDisplayChanged()
            }
        }
```

- [ ] **Step 4: Verify the direct save call is gone from this controller**

Run:

```sh
rg -n "space\\.save\\(\\)" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected: no output.

- [ ] **Step 5: Verify the controller posts the common Space change**

Run:

```sh
rg -n "spaceDataChangedNotificaitonName|SpaceChangeDataType.common" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected: output includes both `spaceDataChangedNotificaitonName` and `SpaceChangeDataType.common`.

- [ ] **Step 6: Build to verify controller changes**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

---

### Task 5: Final Verification and Commit

**Files:**
- Verify: `SunSmart/Common/Data/SpaceData.swift`
- Verify: `SunSmart/Common/Data/Database.swift`
- Verify: `SunSmart/Common/Data/ExportData.swift`
- Verify: `SunSmart/Common/Data/ImportData.swift`
- Verify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`

- [ ] **Step 1: Verify all expected files changed**

Run:

```sh
git diff --name-only
```

Expected output includes only:

```text
SunSmart/Common/Data/SpaceData.swift
SunSmart/Common/Data/Database.swift
SunSmart/Common/Data/ExportData.swift
SunSmart/Common/Data/ImportData.swift
SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

The untracked `docs/260610_1754_content_display_cloud_sync_analysis.md` may still appear in `git status`; do not stage it.

- [ ] **Step 2: Verify JSON contract in code**

Run:

```sh
rg -n '"displayDeviceNamePrefix"|"showCCTQuickButtons"|"controlType"' SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift
```

Expected: each field appears in both export and import files.

- [ ] **Step 3: Verify no whitespace errors**

Run:

```sh
git diff --check
```

Expected: no output.

- [ ] **Step 4: Run final iPhoneOS build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Stage only implementation files**

Run:

```sh
git add SunSmart/Common/Data/SpaceData.swift SunSmart/Common/Data/Database.swift SunSmart/Common/Data/ExportData.swift SunSmart/Common/Data/ImportData.swift SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

- [ ] **Step 6: Verify staged files**

Run:

```sh
git diff --cached --name-only
```

Expected output:

```text
SunSmart/Common/Data/SpaceData.swift
SunSmart/Common/Data/Database.swift
SunSmart/Common/Data/ExportData.swift
SunSmart/Common/Data/ImportData.swift
SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

- [ ] **Step 7: Commit**

Run:

```sh
git commit -m "feat: add space content display settings"
```

Expected: commit succeeds.
