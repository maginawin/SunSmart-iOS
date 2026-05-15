# Sensor Server Publication Retransmit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Sensor Server publication retransmit according to effective group member count whenever the existing profile sync path configures Sensor Server publication.

**Architecture:** Keep the change inside the existing group/profile sync pipeline. `NodeSyncType.group` carries an optional effective member count, `getNodeSyncProfiles` uses that count to decide the target `Publish.Retransmit` (`0...3` members use count `2` at `100 ms`; `4+` members use count `1` at `100 ms`), and `ProfileType.sensorEnabled` carries the retransmit into `ConfigModelPublicationSet`. Success checks compare both publication address and retransmit.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`, scheme `SunSmart`.

---

## File Structure

- Modify `SunSmart/Common/Data/Node+SyncData.swift`
  - Extend `NodeSyncType.group` with `effectiveMemberCount`.
  - Extend `ProfileType.sensorEnabled` with `retransmit`.
  - Add small helpers for Sensor Server publication retransmit and publication comparison.
  - Update `getSyncData(type:)` and `getNodeSyncProfiles(group:)` to use effective group member count.
- Modify `SunSmart/Common/Data/Node+MessageHandles.swift`
  - Use the retransmit value carried by `.sensorEnabled` when creating `ConfigModelPublicationSet`.
- Modify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Compute final intended member count for `.group(group, inNodes, outNodes)`.
  - Pass that count into group sync data generation.
- Modify `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - Update `.sensorEnabled` success check to compare publication address and retransmit.
- Modify `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`
  - Update the duplicate `.sensorEnabled` success check so the project compiles and behavior stays consistent.

No new Swift source files are created, so the Xcode project file does not need source membership edits.

---

### Task 1: Carry Effective Member Count Through Group Sync

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Inspect current group sync call sites**

Run:

```bash
rg -n "NodeSyncType|case group\\(|getSyncData\\(type: \\.group|getSyncDeviceModel\\(" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected: the enum case is `case group(_ group: Group?)`, `getSyncDeviceModel` calls `node.getSyncData(type: .group(group))`, and `.group(let group, let inNodes, let outNodes)` is where final member count can be computed.

- [ ] **Step 2: Extend `NodeSyncType.group`**

In `SunSmart/Common/Data/Node+SyncData.swift`, replace:

```swift
case group(_ group: Group?)
```

with:

```swift
case group(_ group: Group?, effectiveMemberCount: Int? = nil)
```

- [ ] **Step 3: Update `getSyncData(type:)` switch binding**

In `SunSmart/Common/Data/Node+SyncData.swift`, replace:

```swift
case .group(let group):
    guard let group = group ?? self.group else {
        return syncDatas
    }
```

with:

```swift
case .group(let group, let effectiveMemberCount):
    guard let group = group ?? self.group else {
        return syncDatas
    }
```

Then replace the profile sync call in that same `case`:

```swift
let syncProfiles = getNodeSyncProfiles(group: group)
```

with:

```swift
let syncProfiles = getNodeSyncProfiles(group: group, effectiveMemberCount: effectiveMemberCount)
```

- [ ] **Step 4: Add an effective count parameter to `getSyncDeviceModel`**

In `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`, replace:

```swift
private func getSyncDeviceModel(group: Group?, node: Node) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
```

with:

```swift
private func getSyncDeviceModel(group: Group?, node: Node, effectiveMemberCount: Int? = nil) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
```

Then replace:

```swift
syncDataTypes = node.getSyncData(type: .group(group))
```

with:

```swift
syncDataTypes = node.getSyncData(type: .group(group, effectiveMemberCount: effectiveMemberCount))
```

- [ ] **Step 5: Compute final intended member count in `.group` setup**

In `SyncDevicesViewController.setupDataSource()`, inside:

```swift
case .group(let group, let inNodes, let outNodes):
```

insert this immediately after the `case` line:

```swift
let currentNodes = group.nodes
let remainingNodes = currentNodes.filter { node in
    !(outNodes?.contains(node) ?? false)
}
let addedNodes = (inNodes ?? []).filter { node in
    !remainingNodes.contains(node)
}
let effectiveMemberCount = remainingNodes.count + addedNodes.count
```

Then replace all three calls in this case from:

```swift
let result = self.getSyncDeviceModel(group: group, node: node)
```

to:

```swift
let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
```

- [ ] **Step 6: Verify this task compiles far enough to catch signature mistakes**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pub-task1.log 2>&1
```

Expected: build may still fail because later tasks have not updated `getNodeSyncProfiles` or enum pattern matches. It must not fail with `getSyncDeviceModel` argument label errors after Step 5 is complete.

- [ ] **Step 7: Commit Task 1**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "Carry effective member count through group sync"
```

---

### Task 2: Add Sensor Server Publication Retransmit Helpers

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: Add helper extensions**

In `SunSmart/Common/Data/Node+SyncData.swift`, after the `NodeSyncData` enum and before `ProfileType`, add:

```swift
extension Group {
    
    func sensorServerPublicationRetransmit(effectiveMemberCount: Int? = nil) -> Publish.Retransmit {
        let memberCount = effectiveMemberCount ?? nodes.count
        guard memberCount <= 3 else {
            return Publish.Retransmit(1, timesWithInterval: 0.1)
        }
        return Publish.Retransmit(2, timesWithInterval: 0.1)
    }
    
}

extension Model {
    
    func isSensorServerPublicationConfigured(publishAddress: Address, retransmit: Publish.Retransmit) -> Bool {
        guard modelIdentifier == .sensorServerModelId, let publication = self.publish else {
            return false
        }
        return publication.publicationAddress.address == publishAddress && publication.retransmit == retransmit
    }
    
}
```

- [ ] **Step 2: Extend `ProfileType.sensorEnabled`**

In `ProfileType`, replace:

```swift
case sensorEnabled(sensorModels: [Model], publishAddress: Address, delay: TimeInterval = 0)
```

with:

```swift
case sensorEnabled(sensorModels: [Model], publishAddress: Address, delay: TimeInterval = 0, retransmit: Publish.Retransmit = .disabled)
```

- [ ] **Step 3: Extend `getNodeSyncProfiles` signature**

Replace:

```swift
func getNodeSyncProfiles(group: Group? = nil) -> [ProfileType] {
```

with:

```swift
func getNodeSyncProfiles(group: Group? = nil, effectiveMemberCount: Int? = nil) -> [ProfileType] {
```

- [ ] **Step 4: Compute target retransmit in `getNodeSyncProfiles`**

Inside `getNodeSyncProfiles(group:effectiveMemberCount:)`, after:

```swift
let publishAddress = group.address.address
```

add:

```swift
let publishRetransmit = group.sensorServerPublicationRetransmit(effectiveMemberCount: effectiveMemberCount)
```

- [ ] **Step 5: Verify helper symbols are visible**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pub-task2.log 2>&1
```

Expected: build may still fail on `.sensorEnabled` pattern matches that still expect three associated values. It must not fail with `sensorServerPublicationRetransmit` or `isSensorServerPublicationConfigured` not found.

- [ ] **Step 6: Commit Task 2**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "Add sensor server publication retransmit helpers"
```

---

### Task 3: Use Retransmit When Building Sensor Publication Messages

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`
- Modify: `SunSmart/Common/Data/Node+MessageHandles.swift`

- [ ] **Step 1: Update Sensor Server publication sync detection**

In `SunSmart/Common/Data/Node+SyncData.swift`, replace the ambient light sensor enable condition:

```swift
if group.info.ambientLightSensorNode?.primaryUnicastAddress == primaryUnicastAddress, let model = ambientLightSensorModel, model.publish?.publicationAddress != group.address { //光照传感器并且已校准
    enableSensorModels.append(model)
}
```

with:

```swift
if group.info.ambientLightSensorNode?.primaryUnicastAddress == primaryUnicastAddress,
   let model = ambientLightSensorModel,
   !model.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: publishRetransmit) { //光照传感器并且已校准
    enableSensorModels.append(model)
}
```

Replace the presence detected sensor enable condition:

```swift
if let model = presenceDetectedSensorModel, model.publish?.publicationAddress.address != publishAddress {
    enableSensorModels.append(model)
}
```

with:

```swift
if let model = presenceDetectedSensorModel,
   !model.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: publishRetransmit) {
    enableSensorModels.append(model)
}
```

- [ ] **Step 2: Pass retransmit into `.sensorEnabled`**

In `SunSmart/Common/Data/Node+SyncData.swift`, replace:

```swift
syncProfile.append(.sensorEnabled(sensorModels: enableSensorModels, publishAddress: publishAddress, delay: 0))
```

with:

```swift
syncProfile.append(.sensorEnabled(sensorModels: enableSensorModels, publishAddress: publishAddress, delay: 0, retransmit: publishRetransmit))
```

- [ ] **Step 3: Use retransmit in `ConfigModelPublicationSet`**

In `SunSmart/Common/Data/Node+MessageHandles.swift`, replace:

```swift
case .sensorEnabled(let sensorModels, let publishAddress, let delay):
```

with:

```swift
case .sensorEnabled(let sensorModels, let publishAddress, let delay, let retransmit):
```

Then replace:

```swift
let message = ConfigModelPublicationSet(Publish(to: MeshAddress(publishAddress), using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: period, retransmit: .disabled), to: $0)!
```

with:

```swift
let message = ConfigModelPublicationSet(Publish(to: MeshAddress(publishAddress), using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: period, retransmit: retransmit), to: $0)!
```

- [ ] **Step 4: Verify message generation compiles**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pub-task3.log 2>&1
```

Expected: build may still fail on success-check pattern matches in UI model files. It must not fail in `Node+MessageHandles.swift`.

- [ ] **Step 5: Commit Task 3**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift
git commit -m "Apply sensor server publication retransmit"
```

---

### Task 4: Update Success Checks For Full Publication Configuration

**Files:**
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

- [ ] **Step 1: Update normal sync success check**

In `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`, replace:

```swift
case .sensorEnabled(let sensorModels, let publishAddress, _):
    return !sensorModels.contains(where: { $0.publish?.publicationAddress.address != publishAddress })
```

with:

```swift
case .sensorEnabled(let sensorModels, let publishAddress, _, let retransmit):
    return !sensorModels.contains(where: {
        !$0.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: retransmit)
    })
```

- [ ] **Step 2: Update emergency fire duplicate success check**

In `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`, replace:

```swift
case .sensorEnabled(let sensorModels, let publishAddress, _):
    return !sensorModels.contains(where: { $0.publish?.publicationAddress.address != publishAddress })
```

with:

```swift
case .sensorEnabled(let sensorModels, let publishAddress, _, let retransmit):
    return !sensorModels.contains(where: {
        !$0.isSensorServerPublicationConfigured(publishAddress: publishAddress, retransmit: retransmit)
    })
```

- [ ] **Step 3: Find stale associated-value patterns**

Run:

```bash
rg -n "sensorEnabled\\(let sensorModels, let publishAddress, _\\)|sensorEnabled\\(let sensorModels, let publishAddress, let delay\\)" SunSmart
```

Expected: no matches.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pub-task4.log 2>&1
```

Expected: build succeeds. If it fails, inspect the last compiler errors with:

```bash
tail -80 /tmp/sun-smart-profile-pub-task4.log
```

- [ ] **Step 5: Commit Task 4**

```bash
git add SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
git commit -m "Check sensor publication retransmit in sync success"
```

---

### Task 5: Final Verification And Regression Scan

**Files:**
- Verify only; no expected source edits unless a previous task exposed a compile issue.

- [ ] **Step 1: Confirm the implementation preserves scope**

Run:

```bash
rg -n "sceneModel|sceneServer|sceneServerModelId|ConfigModelPublicationSet\\(|retransmit:" SunSmart/Common/Data SunSmart/Main/Space SunSmart/Main/Device/Device1.5/FireAlarm/Model
```

Expected:

- New `ConfigModelPublicationSet` behavior is limited to the existing `.sensorEnabled` path in `SunSmart/Common/Data/Node+MessageHandles.swift`.
- No new Scene Server publication path was added.
- Emergency fire Scene Client publication remains unchanged.

- [ ] **Step 2: Confirm effective member count flows only through group sync**

Run:

```bash
rg -n "effectiveMemberCount|sensorServerPublicationRetransmit|getNodeSyncProfiles\\(" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Group SunSmart/Main/Profile
```

Expected:

- `effectiveMemberCount` exists on `NodeSyncType.group`.
- `SyncDevicesViewController` passes the computed count for `.group(group, inNodes, outNodes)`.
- Existing profile save call sites do not need direct changes because they already route through `.group`.

- [ ] **Step 3: Run final build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pub-final.log 2>&1
```

Expected: build succeeds.

- [ ] **Step 4: Review the final diff**

Run:

```bash
git diff --stat HEAD~4..HEAD
git diff HEAD~4..HEAD -- SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected: changes are limited to the five planned files and match the design.

- [ ] **Step 5: Commit final verification note if any source fix was needed**

If Step 3 or Step 4 required a source fix, commit that fix:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Common/Data/Node+MessageHandles.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
git commit -m "Stabilize sensor publication retransmit sync"
```

If no source fix was needed in this task, do not create an empty commit.
