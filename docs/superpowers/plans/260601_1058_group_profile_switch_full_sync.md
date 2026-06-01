# Group Profile Switch Full Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a group switches from Profile A to Profile B, keep existing group/profile save flow but generate full Profile B configuration commands for all group members.

**Architecture:** Add a small sync context that records profile type changes at save time, pass it through `SyncDevicesViewController` into `Node` profile sync generation, and use it only to bypass profile configuration diff checks. Existing cleanup commands, task dependencies, retry behavior, and non-profile sync domains stay unchanged.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing SunSmart sync models, Xcode `xcodebuild`.

---

## File Structure

- Modify `SunSmart/Common/Data/Node+SyncData.swift`
  - Add `GroupProfileSyncContext`.
  - Add optional `profileSyncContext` parameters to profile sync generation entry points.
  - Bypass selected diff checks only when `shouldForceFullProfileSync` is true.

- Modify `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - Build the context before `saveActionCallback` mutates the group profile.
  - Push sync UI when type switching even if current diff checks report no pending sync.
  - Assign the context to `SyncDevicesViewController`.

- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Store `groupProfileSyncContext`.
  - Pass it only for normal group profile save (`inNodes == nil && outNodes == nil`), not add/remove-member flows.

- No new test target
  - Repository currently has no XCTest target. Verification uses focused code inspection plus `iphoneos` build, matching project constraints and avoiding target/config churn.

---

### Task 1: Add Profile Sync Context Type

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Add `GroupProfileSyncContext` near `NodeSyncType`**

In `SunSmart/Common/Data/Node+SyncData.swift`, insert after imports and before `enum NodeSyncType`:

```swift
/// Context for group profile synchronization that needs behavior beyond normal diff-based sync.
struct GroupProfileSyncContext {
    let previousProfileType: Profile.ProfileType
    let savedProfileType: Profile.ProfileType

    var shouldForceFullProfileSync: Bool {
        previousProfileType != savedProfileType
    }
}
```

- [ ] **Step 2: Add context storage to sync controller**

In `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`, near `profileSensorProtectionContext`, add:

```swift
    /// Group profile switch context. Only applies to normal group profile SAVE, not member add/remove flows.
    var groupProfileSyncContext: GroupProfileSyncContext?
```

- [ ] **Step 3: Build to verify the context type compiles**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Commit Task 1**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: add group profile sync context"
```

---

### Task 2: Pass Profile Sync Context Through Group Sync

**Files:**
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: Capture the context before group profile mutation**

In `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`, replace the existing `previousProfile` / `sensorProtectionContext` block with:

```swift
        let previousProfile = group?.info.profile
        let groupProfileSyncContext = group.flatMap { group -> GroupProfileSyncContext? in
            guard let previousProfile = previousProfile,
                  previousProfile.type != selectProfile.type else {
                return nil
            }
            return GroupProfileSyncContext(previousProfileType: previousProfile.type, savedProfileType: selectProfile.type)
        }
        let sensorProtectionContext = group.flatMap { group -> ProfileSensorProtectionContext? in
            guard let previousProfile = previousProfile else {
                return nil
            }
            return ProfileSensorProtectionContext(group: group, previousProfile: previousProfile, savedProfile: selectProfile)
        }
```

- [ ] **Step 2: Push sync UI for type switches even when old diff says no sync**

In the same method, replace:

```swift
        if let group = group, group.nodes.contains(where: { $0.needSync }) {
            let vc = SyncDevicesViewController(type: .group(group, inNodes: nil, outNodes: nil))
            vc.profileSensorProtectionContext = sensorProtectionContext
```

with:

```swift
        if let group = group,
           group.nodes.contains(where: { $0.needSync }) || (groupProfileSyncContext?.shouldForceFullProfileSync == true && !group.nodes.isEmpty) {
            let vc = SyncDevicesViewController(type: .group(group, inNodes: nil, outNodes: nil))
            vc.profileSensorProtectionContext = sensorProtectionContext
            vc.groupProfileSyncContext = groupProfileSyncContext
```

- [ ] **Step 3: Thread the context through `getSyncDeviceModel`**

Change the helper signature from:

```swift
    private func getSyncDeviceModel(group: Group?, node: Node, effectiveMemberCount: Int? = nil) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
```

to:

```swift
    private func getSyncDeviceModel(
        group: Group?,
        node: Node,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil
    ) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
```

Inside that function, replace:

```swift
            syncDataTypes = node.getSyncData(type: .group(group, effectiveMemberCount: effectiveMemberCount))
```

with:

```swift
            syncDataTypes = node.getSyncData(
                type: .group(group, effectiveMemberCount: effectiveMemberCount),
                profileSyncContext: profileSyncContext
            )
```

- [ ] **Step 4: Pass context only for normal group SAVE**

In `setupDataSource()` inside the `.group(let group, let inNodes, let outNodes)` case, before iterating group nodes, add:

```swift
                let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
```

Then in the `group.nodes.filter` loop, replace:

```swift
                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
```

with:

```swift
                    let result = self.getSyncDeviceModel(
                        group: group,
                        node: node,
                        effectiveMemberCount: effectiveMemberCount,
                        profileSyncContext: profileSyncContext
                    )
```

Do not pass `profileSyncContext` to the `outNodes` or `inNodes` loops.

- [ ] **Step 5: Add optional context to `Node.getSyncData`**

In `SunSmart/Common/Data/Node+SyncData.swift`, change:

```swift
    func getSyncData(type: NodeSyncType) -> [NodeSyncData] {
```

to:

```swift
    func getSyncData(type: NodeSyncType, profileSyncContext: GroupProfileSyncContext? = nil) -> [NodeSyncData] {
```

Inside the `.group` case, replace:

```swift
            let syncProfiles = getNodeSyncProfiles(group: group, effectiveMemberCount: effectiveMemberCount)
```

with:

```swift
            let syncProfiles = getNodeSyncProfiles(
                group: group,
                effectiveMemberCount: effectiveMemberCount,
                profileSyncContext: profileSyncContext
            )
```

- [ ] **Step 6: Add optional context to `getNodeSyncProfiles`**

Change:

```swift
    func getNodeSyncProfiles(group: Group? = nil, effectiveMemberCount: Int? = nil) -> [ProfileType] {
```

to:

```swift
    func getNodeSyncProfiles(
        group: Group? = nil,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil
    ) -> [ProfileType] {
```

Do not change diff behavior in this task. The new parameter is threaded through so the build remains green before Task 3 changes generation rules.

- [ ] **Step 7: Build to catch call-site regressions**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 8: Commit Task 2**

```bash
git add SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Common/Data/Node+SyncData.swift
git commit -m "feat: pass profile sync context"
```

---

### Task 3: Force Full Profile B Configuration Generation

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: Read force flag in `getNodeSyncProfiles`**

After `let groupProfile = group.info.profile`, add:

```swift
        let forceFullProfileSync = profileSyncContext?.shouldForceFullProfileSync == true
```

- [ ] **Step 2: Force high/low end trim when supported**

Replace:

```swift
                if lightnessSetupModel != nil && (groupLightnessRange.lowerBound != minLightness || groupLightnessRange.upperBound != maxLightness) {
                    syncProfile.append(.highLowEndTrim(range: groupLightnessRange))
                }
```

with:

```swift
                if lightnessSetupModel != nil && (forceFullProfileSync || groupLightnessRange.lowerBound != minLightness || groupLightnessRange.upperBound != maxLightness) {
                    syncProfile.append(.highLowEndTrim(range: groupLightnessRange))
                }
```

- [ ] **Step 3: Force day/night lux trigger condition commands when Profile B uses them**

In the night-data block, replace the condition:

```swift
                            if coodition == nil || coodition!.maxLux != targetLux || coodition!.useCalibrationValues != nightData.useCalibrationValues || coodition!.destination != sceneDestination || coodition!.sceneNumber != nightData.sceneData.sceneNumber {
```

with:

```swift
                            if forceFullProfileSync || coodition == nil || coodition!.maxLux != targetLux || coodition!.useCalibrationValues != nightData.useCalibrationValues || coodition!.destination != sceneDestination || coodition!.sceneNumber != nightData.sceneData.sceneNumber {
```

In the day-data block, replace:

```swift
                            if coodition == nil || coodition!.minLux != targetLux || coodition!.useCalibrationValues != dayData.useCalibrationValues || coodition!.destination != sceneDestination || coodition!.sceneNumber != dayData.sceneData.sceneNumber {
```

with:

```swift
                            if forceFullProfileSync || coodition == nil || coodition!.minLux != targetLux || coodition!.useCalibrationValues != dayData.useCalibrationValues || coodition!.destination != sceneDestination || coodition!.sceneNumber != dayData.sceneData.sceneNumber {
```

- [ ] **Step 4: Pass force flag to light data sync generation**

Replace:

```swift
                    let lightSyncProfiles = getNodeLightDataSyncProfiles(group: group, groupLightData: lightControlData, lightLCProperty: lightLCProperty)
```

with:

```swift
                    let lightSyncProfiles = getNodeLightDataSyncProfiles(
                        group: group,
                        groupLightData: lightControlData,
                        lightLCProperty: lightLCProperty,
                        forceFullProfileSync: forceFullProfileSync
                    )
```

- [ ] **Step 5: Force power-up and sensitivity when supported**

In the `switch groupProfile.powerUpState` block, update the three branches:

```swift
            case .off:
                if powerUpState != .off {
                    syncProfile.append(.powerOnState(state: .off))
                }
            case .restore:
                if powerUpState != .restore {
                    syncProfile.append(.powerOnState(state: .restore))
                }
            case .definedLightLevel(let level):
                let profileType = ProfileType.powerOnState(state: .definedLightLevel(level), cct: groupProfile.powerUpCct)
                let targetCct = profileType.targetPowerUpCct(for: self)
                let setCct = targetCct.map { $0 != self.defaultCct } ?? false
                if powerUpState != .default || Node.getLightness(lightness100: Int(level)) != defalutLightness || setCct {
                    if let targetCct = targetCct {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level), cct: targetCct))
                    }else {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level)))
                    }
                }
            }
```

to:

```swift
            case .off:
                if forceFullProfileSync || powerUpState != .off {
                    syncProfile.append(.powerOnState(state: .off))
                }
            case .restore:
                if forceFullProfileSync || powerUpState != .restore {
                    syncProfile.append(.powerOnState(state: .restore))
                }
            case .definedLightLevel(let level):
                let profileType = ProfileType.powerOnState(state: .definedLightLevel(level), cct: groupProfile.powerUpCct)
                let targetCct = profileType.targetPowerUpCct(for: self)
                let setCct = targetCct.map { $0 != self.defaultCct } ?? false
                if forceFullProfileSync || powerUpState != .default || Node.getLightness(lightness100: Int(level)) != defalutLightness || setCct {
                    if let targetCct = targetCct {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level), cct: targetCct))
                    }else {
                        syncProfile.append(.powerOnState(state: .definedLightLevel(level)))
                    }
                }
            }
```

Then replace:

```swift
                if self.motionSensitivity != resultValue {
                    syncProfile.append(.sensitivity(value: resultValue))
                }
```

with:

```swift
                if forceFullProfileSync || self.motionSensitivity != resultValue {
                    syncProfile.append(.sensitivity(value: resultValue))
                }
```

- [ ] **Step 6: Add force flag to `getNodeLightDataSyncProfiles`**

Change:

```swift
    func getNodeLightDataSyncProfiles(group: Group, groupLightData: Profile.LightControlData, lightLCProperty: LightLCProperty) -> [ProfileType] {
```

to:

```swift
    func getNodeLightDataSyncProfiles(
        group: Group,
        groupLightData: Profile.LightControlData,
        lightLCProperty: LightLCProperty,
        forceFullProfileSync: Bool = false
    ) -> [ProfileType] {
```

- [ ] **Step 7: Force Light LC / Vendor profile properties**

In `getNodeLightDataSyncProfiles`, update each diff check to include `forceFullProfileSync`. The resulting conditions should be:

```swift
        if forceFullProfileSync || lightLCProperty.mode == nil || !lightLCProperty.mode! {
            syncProfile.append(.mode(enabled: true))
        }
```

```swift
            if forceFullProfileSync || lightLCProperty.occupancyMode == nil || !lightLCProperty.occupancyMode! {
                syncProfile.append(.occupancyMode(enabled: true))
            }
```

```swift
            if forceFullProfileSync || lightLCProperty.occupancyMode == nil || lightLCProperty.occupancyMode! {
                syncProfile.append(.occupancyMode(enabled: false))
            }
```

```swift
        if forceFullProfileSync || lightLCProperty.manualOverrideEnabled == nil || !lightLCProperty.manualOverrideEnabled! || lightLCProperty.manualOverrideTimeout != manualOverrideTimeout ||  lightLCProperty.manualControlState != manualOverrideState {
            syncProfile.append(.manualOverrideTimeout(enabled: true, manualOverrideState: manualOverrideState, second: groupProfile.manualOverrideTimeout))
        }
```

```swift
            if forceFullProfileSync || lightLCProperty.manualControlMode == nil || !lightLCProperty.manualControlMode! {
                syncProfile.append(.manualControl(enabled: true))
            }
```

```swift
            if forceFullProfileSync || lightLCProperty.manualControlMode ?? true {
                syncProfile.append(.manualControl(enabled: false))
            }
```

```swift
                if forceFullProfileSync || lightLCProperty.lightAutoAdjustEnabled == nil || !lightLCProperty.lightAutoAdjustEnabled! {
                    syncProfile.append(.lightAutoAdujustEnabled(enabled: true))
                }
```

```swift
                if forceFullProfileSync || lightLCProperty.lightAutoAdjustEnabled == nil || lightLCProperty.lightAutoAdjustEnabled! {
                    syncProfile.append(.lightAutoAdujustEnabled(enabled: false))
                }
```

- [ ] **Step 8: Force level/lux/time/adjust-speed profile properties**

In `getNodeLightDataSyncProfiles`, update all profile property comparisons to include `forceFullProfileSync`.

For level/lux checks, each condition should follow this pattern:

```swift
if forceFullProfileSync || lightLCProperty.luxLevelOn == nil || lightLCProperty.luxLevelOn! != level {
    syncProfile.append(.occupancyLux(lux: level))
}
```

```swift
if forceFullProfileSync || lightLCProperty.lightnessOn == nil || lightLCProperty.lightnessOn! != Node.getLightness(lightness100: level) {
    syncProfile.append(.occupancyLevel(value: level))
}
```

Apply the same pattern to:

- `luxLevelProlong` / `.vacantLux`
- `lightnessProlong` / `.vacantLevel`
- `luxLevelStandby` / `.standbyLux`
- `lightnessStandby` / `.standbyLevel`
- daylight auto-min `lightnessOn`
- daylight auto-min `lightnessProlong`
- daylight auto-min `lightnessStandby`
- default uncalibrated occupancy/vacant/standby level checks
- `.taskLevel` occupancy lux / level

For timing checks, each condition should follow this pattern:

```swift
if forceFullProfileSync || lightLCProperty.timeFadeOn == nil || lightLCProperty.timeFadeOn! != min(second * 1000, 0xFFFFFE) {
    syncProfile.append(.t1(second: second))
}
```

Apply the same pattern to `t2`, `t3`, `t4`, and `t5`.

For adjust speed, replace the existing condition with:

```swift
            if forceFullProfileSync ||
                lightLCProperty.regulatorKid == nil || lightLCProperty.regulatorKid!.roundf2 != regulatorData.regulatorKid.roundf2 ||
                lightLCProperty.regulatorKiu == nil || lightLCProperty.regulatorKiu!.roundf2 != regulatorData.regulatorKiu.roundf2 ||
                lightLCProperty.regulatorKpd == nil || lightLCProperty.regulatorKpd!.roundf2 != regulatorData.regulatorKpd.roundf2 ||
                lightLCProperty.regulatorKpu == nil || lightLCProperty.regulatorKpu!.roundf2 != regulatorData.regulatorKpu.roundf2 ||
                lightLCProperty.regulatorAccuracy == nil || lightLCProperty.regulatorAccuracy! != regulatorData.regulatorAccuracy {
                syncProfile.append(.adjustSpeed(speed: groupProfile.adjustSpeed))
            }
```

- [ ] **Step 9: Build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 10: Commit Task 3**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "feat: fully sync switched group profiles"
```

---

### Task 4: Verification And Regression Checks

**Files:**
- Inspect: `SunSmart/Common/Data/Node+SyncData.swift`
- Inspect: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- Inspect: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Verify context is only assigned by Profile SAVE**

Run:

```bash
rg -n "groupProfileSyncContext|GroupProfileSyncContext" SunSmart
```

Expected:

```text
SunSmart/Common/Data/Node+SyncData.swift:...
SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:...
SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:...
```

There should be no assignment from group member add/remove controllers.

- [ ] **Step 2: Verify member add/remove path does not receive forced context**

Inspect `SyncDevicesViewController.setupDataSource()` and confirm:

```swift
let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
```

and confirm the `inNodes` / `outNodes` loops call:

```swift
let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
```

without `profileSyncContext`.

- [ ] **Step 3: Verify cleanup remains before new Profile scene config**

Inspect `getNodeSyncProfiles(...)` and confirm this order inside `lightLCSetupModel != nil`:

```swift
syncProfile.append(.highLowEndTrim(range: groupLightnessRange))
syncProfile.append(.lightControlDelete(sceneNumber: sceneExecuteData.sceneNumber))
syncProfile.append(.profileToggleTriggerConditionLuxDelete(id: condition.index))
scenes.forEach { profileScene in
    ...
}
```

Expected: cleanup generation still precedes `scenes.forEach`.

- [ ] **Step 4: Verify same-type save still uses diff behavior**

Inspect `ProfileSettingsViewController` and confirm:

```swift
previousProfile.type != selectProfile.type
```

is required to create `GroupProfileSyncContext`.

Inspect `Node+SyncData.swift` and confirm `forceFullProfileSync` only becomes true from:

```swift
let forceFullProfileSync = profileSyncContext?.shouldForceFullProfileSync == true
```

- [ ] **Step 5: Run final build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Check working tree**

Run:

```bash
git status --short
```

Expected: only intentional source changes remain, plus any pre-existing untracked analysis document if it was not committed:

```text
?? docs/260601_0949_site_space_group_profile_save_analysis.md
```

- [ ] **Step 7: Commit verification-ready state**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "feat: force full sync on group profile switches"
```

---

## Self-Review

- Spec coverage: covered type-switch trigger, unchanged same-type/member flows, full Profile B generation, preserved cleanup ordering, unchanged error handling, and `iphoneos` build verification.
- Placeholder scan: no placeholder markers are used.
- Type consistency: `GroupProfileSyncContext`, `profileSyncContext`, and `forceFullProfileSync` names are consistent across tasks.
- Scope check: single subsystem, limited to group profile save/sync flow.
