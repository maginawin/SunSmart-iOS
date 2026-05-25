# Profile Power Up CCT Range Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Profile Power Up 的组级 `powerUpCct` 保持统一保存值，同时同步到每台设备时按设备自身有效 CCT range 夹紧并正确判定同步成功。

**Architecture:** 在现有 `ProfileType` 同步类型旁增加一个小型设备目标 helper，集中表达 Power Up CCT 的设备级目标语义。`Node+SyncData`、`SyncDevicesCellModel`、`EmerFireAlarmSyncCellModel` 复用该 helper，避免发送目标和成功判定再次分叉。

**Tech Stack:** Swift、UIKit iOS app、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## File Structure

- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
  - `ProfileType` enum 定义在这里。
  - 新增 `ProfileType.targetPowerUpCct(for:)` helper。
  - 修改 `Node.getSyncProfileData(group:effectiveMemberCount:)` 中 `.definedLightLevel` 的 CCT 目标生成逻辑。

- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - 普通 Sync device(s) 页面通过 `ProfileType.isSuccessful(node:)` 判定 Profile 同步结果。
  - 修改 `.powerOnState` 成功判定，按设备目标 CCT 比较。

- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`
  - Fire Alarm 同步模型中有一份同名 `ProfileType.isSuccessful(node:)` 判定。
  - 同步修改，保持与普通 Sync device(s) 行为一致。

- Read-only reference: `SunSmart/Common/Data/Node+MessageHandles.swift`
  - 已在发送 `LightCTLDefaultSet` 时使用 `node.clampEffectiveCct(defaultCct)`。
  - 本次不需要改变发送层，只保留它作为防御性保护。

- Read-only reference: `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - `SceneExecuteData.deviceTarget(for:)` 和 `isSynced(with:for:)` 是本次设计参考。

---

### Task 1: Add Profile Power Up Device Target Helper

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: Locate `ProfileType` enum**

Open `SunSmart/Common/Data/Node+SyncData.swift` and find:

```swift
enum ProfileType {
```

The enum contains:

```swift
case powerOnState(state: Profile.PowerUpState, cct: UInt16? = nil)
```

- [ ] **Step 2: Add helper below `ProfileType` enum**

Add this extension after the `ProfileType` enum declaration, before the next unrelated extension or type declaration:

```swift
extension ProfileType {
    func targetPowerUpCct(for node: Node) -> UInt16? {
        guard case .powerOnState(.definedLightLevel(_), let cct) = self,
              let cct = cct,
              node.effectiveSupportCct else {
            return nil
        }
        return node.clampEffectiveCct(cct)
    }
}
```

This helper preserves group-level `powerUpCct` while deriving the actual value that a specific device should store.

- [ ] **Step 3: Run a syntax build checkpoint**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds, or any failure is unrelated to `targetPowerUpCct(for:)`.

- [ ] **Step 4: Commit helper**

Run:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "fix: add profile power up cct target helper"
```

---

### Task 2: Use Device Target CCT When Generating Profile Sync Items

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: Find current `.definedLightLevel` sync generation**

In `Node.getSyncProfileData(group:effectiveMemberCount:)`, find:

```swift
case .definedLightLevel(let level):
    let setCct = (ctlModel != nil && groupProfile.powerUpCct != self.defaultCct)
    if powerUpState != .default || Node.getLightness(lightness100: Int(level)) != defalutLightness || setCct {
        if setCct {
            syncProfile.append(.powerOnState(state: .definedLightLevel(level), cct: groupProfile.powerUpCct))
        }else {
            syncProfile.append(.powerOnState(state: .definedLightLevel(level)))
        }
    }
```

- [ ] **Step 2: Replace it with device-target-aware logic**

Replace the block with:

```swift
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
```

This makes the sync item carry the actual device target CCT. For a device with max `5000K`, a group-level `6500K` becomes `5000K` before the item is used by the UI and message layer.

- [ ] **Step 3: Build checkpoint**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Commit sync generation change**

Run:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "fix: clamp profile power up cct per device"
```

---

### Task 3: Update Ordinary Sync Success Judgement

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: Find `.powerOnState` success check**

Find this code in `ProfileType.isSuccessful(node:)`:

```swift
case .powerOnState(let state, let cct):
    switch state {
    case .off:
        return node.powerUpState == .off
    case .restore:
        return node.powerUpState == .restore
    case .definedLightLevel(let level):
        return node.powerUpState == .default && node.defalutLightness == Node.getLightness(lightness100: Int(level)) && (cct == nil || cct != nil && cct == node.defaultCct)
    }
```

- [ ] **Step 2: Replace the defined-light-level comparison**

Replace the `.definedLightLevel` case body with:

```swift
case .definedLightLevel(let level):
    guard node.powerUpState == .default,
          node.defalutLightness == Node.getLightness(lightness100: Int(level)) else {
        return false
    }
    guard let targetCct = self.targetPowerUpCct(for: node) else {
        return true
    }
    return targetCct == node.defaultCct
```

The full switch should now treat missing CCT as intentional for devices that do not effectively support CCT.

- [ ] **Step 3: Build checkpoint**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Commit ordinary sync judgement change**

Run:

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift
git commit -m "fix: compare profile power up cct by device target"
```

---

### Task 4: Update Fire Alarm Sync Success Judgement

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

- [ ] **Step 1: Find duplicate `.powerOnState` success check**

Find this code in `ProfileType.isSuccessful(node:)`:

```swift
case .powerOnState(let state, let cct):
    switch state {
    case .off:
        return node.powerUpState == .off
    case .restore:
        return node.powerUpState == .restore
    case .definedLightLevel(let level):
        return node.powerUpState == .default && node.defalutLightness == Node.getLightness(lightness100: Int(level)) && (cct == nil || cct != nil && cct == node.defaultCct)
    }
```

- [ ] **Step 2: Replace the defined-light-level comparison**

Replace the `.definedLightLevel` case body with:

```swift
case .definedLightLevel(let level):
    guard node.powerUpState == .default,
          node.defalutLightness == Node.getLightness(lightness100: Int(level)) else {
        return false
    }
    guard let targetCct = self.targetPowerUpCct(for: node) else {
        return true
    }
    return targetCct == node.defaultCct
```

This keeps Fire Alarm sync state aligned with the ordinary Sync device(s) page.

- [ ] **Step 3: Build checkpoint**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Commit Fire Alarm sync judgement change**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
git commit -m "fix: align emergency sync power up cct judgement"
```

---

### Task 5: Final Verification and Review

**Files:**
- Read: `docs/superpowers/specs/260525_0940_profile_power_up_cct_range_design.md`
- Review: all modified files

- [ ] **Step 1: Check for remaining raw CCT comparisons in Profile sync success**

Run:

```bash
rg -n "cct == node.defaultCct|groupProfile.powerUpCct != self.defaultCct|powerUpCct\\)" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected:

- No remaining `cct == node.defaultCct` in the two `isSuccessful(node:)` implementations.
- No remaining `groupProfile.powerUpCct != self.defaultCct` in `Node+SyncData.swift`.
- Any remaining `powerUpCct` references should be group-level storage or helper inputs, not direct device success comparison.

- [ ] **Step 2: Run final iOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Manual reasoning checklist**

Confirm these cases from the implementation:

```text
Group Profile powerUpCct = 6500K

Device A effectiveCctRange = 2700K...6500K
targetPowerUpCct(for: A) == 6500K
success requires node.defaultCct == 6500K

Device B effectiveCctRange = 2700K...5000K
targetPowerUpCct(for: B) == 5000K
success requires node.defaultCct == 5000K

Device C effectiveSupportCct == false
targetPowerUpCct(for: C) == nil
success ignores CCT and checks only powerUpState/default lightness
```

- [ ] **Step 4: Review diff**

Run:

```bash
git diff --stat HEAD~4..HEAD
git diff HEAD~4..HEAD -- SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected:

- Changes are limited to the planned files.
- No unrelated formatting churn.
- `Node+MessageHandles.swift` remains unchanged unless a compile error forced a minimal adjustment.

- [ ] **Step 5: Commit final verification note if needed**

If final review requires small cleanup, commit it:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
git commit -m "fix: finalize profile power up cct range handling"
```

Skip this commit if Task 1-4 commits already contain the complete clean implementation.

---

## Plan Self-Review

- Spec coverage: The plan preserves group-level `Profile.powerUpCct`, clamps per device for sync generation, ignores CCT for ineffective CCT devices, updates ordinary and Fire Alarm sync judgement, and includes final build verification.
- Placeholder scan: No placeholder markers or open implementation placeholders remain.
- Type consistency: The plan uses existing `ProfileType.powerOnState(state:cct:)`, `Profile.PowerUpState.definedLightLevel`, `Node.effectiveSupportCct`, `Node.clampEffectiveCct(_:)`, `node.defaultCct`, and `node.defalutLightness`.
- Test strategy: This workspace has no existing XCTest test files or test scheme discovered by `rg --files`; the plan avoids adding project configuration churn and uses focused build plus code-path verification.
