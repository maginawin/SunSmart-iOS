# Profile PIR Target Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Group Profile SAVE disable all PIR sensors before configuration, then enable only the sensors required by the old/new Profile relationship and the SAVE-time PIR state snapshot.

**Architecture:** Keep the protection flow inside the existing `SyncDevicesViewController` sync queue. `ProfileSensorProtectionContext` owns the old/new Profile types, PIR-capable sensor snapshot, and target enable calculation. `SyncDevicesViewController` uses ordinary ACK `NodeSyncData.pirEnabled` tasks for both front disable and post target enable.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, existing `MeshProxyMessageCommand` sync queue, Xcode workspace build validation.

---

## File Structure

- Modify `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - Capture the old Profile before `saveActionCallback?(selectProfile)` mutates `group.info.profile`.
  - Build `ProfileSensorProtectionContext` with old Profile and new Profile.
- Modify `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - Store SAVE-time PIR snapshot.
  - Calculate post-target enable addresses from old/new Profile relationship.
  - Make `.profileSensorProtectionDisable` produce ACK `pirEnabled(false)` message handles.
- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Stop intercepting front disable as unack/no-wait.
  - Keep lifecycle markers for front disable and post enable fallback.
  - Remove now-unused no-wait sender and manual interval.

There is no existing XCTest target in this workspace. Validation will use targeted code inspection plus an `xcodebuild` compile check, and the implementation should keep decision logic small enough to audit directly.

---

### Task 1: Capture SAVE-Time PIR Snapshot

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:60`
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:251`

- [ ] **Step 1: Replace `ProfileSensorProtectionContext` stored data and initializer**

In `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`, replace the current `ProfileSensorProtectionContext` property block and initializer with:

```swift
final class ProfileSensorProtectionContext {
    
    private weak var group: Group?
    let previousProfileType: Profile.ProfileType
    let savedProfileType: Profile.ProfileType
    private let sensorNodeAddresses: Set<Address>
    private let initiallyEnabledSensorAddresses: Set<Address>
    private var preDisableStarted = false
    private var fallbackTargetStateStarted = false
    private var targetStateTaskAddresses: Set<Address> = []
    
    init?(group: Group, previousProfile: Profile, savedProfile: Profile) {
        let sensorNodes = group.sensorNodes.filter { $0.supportsProfileSensorProtection }
        guard !sensorNodes.isEmpty else {
            return nil
        }
        
        self.group = group
        self.previousProfileType = previousProfile.type
        self.savedProfileType = savedProfile.type
        self.sensorNodeAddresses = Set(sensorNodes.map { $0.primaryUnicastAddress })
        self.initiallyEnabledSensorAddresses = Set(sensorNodes.filter { $0.pirEnabled }.map { $0.primaryUnicastAddress })
    }
```

Remove the old `static let operationInterval` line; front disable will no longer sleep manually.

- [ ] **Step 2: Replace `sensorNodes` so it uses the snapshot address set**

In the same class, replace the current `sensorNodes` computed property with:

```swift
    var sensorNodes: [Node] {
        return group?.sensorNodes.filter {
            sensorNodeAddresses.contains($0.primaryUnicastAddress) && $0.supportsProfileSensorProtection
        } ?? []
    }
```

- [ ] **Step 3: Add target enable address calculation**

In the same class, add this computed property before `remainingTargetStateMessageHandles()`:

```swift
    private var targetEnableAddresses: Set<Address> {
        guard savedProfileType.occupancyType else {
            return []
        }
        
        if previousProfileType.occupancyType {
            return initiallyEnabledSensorAddresses
        }
        
        return sensorNodeAddresses
    }
```

- [ ] **Step 4: Update `targetEnableNodes` to filter by target addresses**

Replace `targetEnableNodes(excluding:)` with:

```swift
    private func targetEnableNodes(excluding excludedAddresses: Set<Address>) -> [Node] {
        return sensorNodes.filter {
            targetEnableAddresses.contains($0.primaryUnicastAddress)
            && !excludedAddresses.contains($0.primaryUnicastAddress)
        }
    }
```

- [ ] **Step 5: Update context creation to pass old and new Profile**

In `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`, replace:

```swift
        let sensorProtectionContext = group.map { ProfileSensorProtectionContext(group: $0, savedProfile: selectProfile) }
```

with:

```swift
        let previousProfile = group?.info.profile
        let sensorProtectionContext = group.flatMap { group -> ProfileSensorProtectionContext? in
            guard let previousProfile = previousProfile else {
                return nil
            }
            return ProfileSensorProtectionContext(group: group, previousProfile: previousProfile, savedProfile: selectProfile)
        }
```

- [ ] **Step 6: Inspect expected behavior before continuing**

Run:

```bash
rg -n "ProfileSensorProtectionContext\\(|previousProfileType|initiallyEnabledSensorAddresses|targetEnableAddresses|operationInterval" SunSmart/Main
```

Expected:
- `ProfileSensorProtectionContext(` call site uses `previousProfile:` and `savedProfile:`.
- `operationInterval` has no matches.
- Snapshot fields exist only inside `SyncDevicesCellModel.swift`.

### Task 2: Convert Front Disable To ACK Queue Task

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:360`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:422`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:1570`

- [ ] **Step 1: Make `.profileSensorProtectionDisable` produce ACK message handles**

In both `DeviceOperationType.messageHandles` switch branches, replace:

```swift
            case .profileSensorProtectionDisable:
                break
```

with:

```swift
            case .profileSensorProtectionDisable:
                messageHandles.append(contentsOf: NodeSyncData.pirEnabled(false).getMessageHandles(node: node))
```

This must be done once in the `.delete` branch and once in the `.configuration` branch so the enum remains symmetric.

- [ ] **Step 2: Stop intercepting disable as no-wait**

In `SyncDevicesViewController.completeProfileSensorProtectionTaskIfNeeded(for:)`, replace the `.profileSensorProtectionDisable` case:

```swift
            case .profileSensorProtectionDisable:
                profileSensorProtectionContext?.markPreDisableStarted()
                let isSuccessful = sendProfileSensorProtectionDisable(node: node)
                Thread.sleep(forTimeInterval: ProfileSensorProtectionContext.operationInterval)
                taskModel.state = isSuccessful ? .successful : .failed
                if !isSuccessful {
                    taskModel.failedCount += 1
                }
                updateCell(model: taskModel)
                return true
```

with:

```swift
            case .profileSensorProtectionDisable:
                profileSensorProtectionContext?.markPreDisableStarted()
                return false
```

This preserves the lifecycle marker but allows the ordinary ACK queue to send and validate the command.

- [ ] **Step 3: Delete the no-wait sender**

Remove the entire method from `SyncDevicesViewController`:

```swift
    private func sendProfileSensorProtectionDisable(node: Node) -> Bool {
        guard let vendorModel = node.sunricherVendorModel else {
            return false
        }

        let message = SunricherVendorSetUnacknowledged(function: .pirEnabled(enabled: false))
        do {
            try MeshNetworkManager.instance.send(message, to: vendorModel, completion: nil)
            node.pirEnabled = false
            node.savePropertys()
            node.clearSyncStateCache()
            return true
        } catch {
            print("profile PIR disable no-wait send failed: \(error)")
            return false
        }
    }
```

- [ ] **Step 4: Inspect ACK-only disable path**

Run:

```bash
rg -n "profileSensorProtectionDisable|sendProfileSensorProtectionDisable|SunricherVendorSetUnacknowledged\\(function: \\.pirEnabled|operationInterval" SunSmart/Main/Space
```

Expected:
- `.profileSensorProtectionDisable` message handles use `NodeSyncData.pirEnabled(false)`.
- `sendProfileSensorProtectionDisable` has no matches.
- `operationInterval` has no matches.
- `SunricherVendorSetUnacknowledged(function: .pirEnabled` has no matches in the Profile SAVE protection path.

### Task 3: Verify Target-State Matrix And Build

**Files:**
- Review: `docs/superpowers/specs/2026-05-15-profile-save-sensor-protection-design.md`
- Review: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Review: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- Review: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Check the seven target-state scenarios against code**

Use the `targetEnableAddresses` logic to verify:

```swift
// old PIR, new PIR:
// target = initiallyEnabledSensorAddresses

// old non-PIR, new PIR:
// target = sensorNodeAddresses

// new non-PIR:
// target = []
```

Expected mapping:
- PIR Profile parameters, all enabled before SAVE -> all enabled after SAVE.
- PIR Profile parameters, partly enabled before SAVE -> same subset enabled after SAVE.
- PIR Profile parameters, all disabled before SAVE -> none enabled after SAVE.
- non-PIR -> PIR -> all PIR-capable sensors enabled after SAVE.
- PIR -> non-PIR -> none enabled after SAVE.
- PIR -> PIR -> same SAVE-before enabled subset after SAVE.
- non-PIR -> non-PIR -> none enabled after SAVE.

- [ ] **Step 2: Check ordinary `.pirEnabled` de-duplication remains scoped**

Inspect `SyncDevicesViewController.getSyncDeviceModel(...)` around the `.pirEnabled(let enabled)` case. It should still skip ordinary `pirEnabled` tasks when `profileSensorProtectionContext != nil`:

```swift
            case .pirEnabled(let enabled):
                if profileSensorProtectionContext != nil {
                    break
                }
```

Expected: no duplicate ordinary `pirEnabled(true/false)` task runs during the dedicated SAVE Profile protection sequence.

- [ ] **Step 3: Build the app**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build exits `0`.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "Apply profile PIR target snapshot rules"
```

Expected: one implementation commit containing only the three source files.

---

## Self-Review

- Spec coverage: the plan implements SAVE-time snapshot, old/new Profile target matrix, ACK front disable, ACK post enable, ordinary task de-duplication, and no-context behavior for groups without PIR-capable sensors.
- No placeholders: every edit step names exact files and concrete code.
- Type consistency: `Profile.ProfileType`, `Address`, `NodeSyncData.pirEnabled`, `profileSensorProtectionContext`, and existing lifecycle marker names match current source.
