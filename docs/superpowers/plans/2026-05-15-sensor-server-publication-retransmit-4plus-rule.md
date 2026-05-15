# Sensor Server Publication Retransmit 4 Plus Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change Sensor Server publication retransmit so groups with `4+` effective members use retransmit count `1` at `100 ms`, while groups with `0...3` effective members keep retransmit count `2` at `100 ms`.

**Architecture:** Keep the existing publication retransmit plumbing from the prior implementation. Only update the group-size rule inside `Group.sensorServerPublicationRetransmit(effectiveMemberCount:)`; the existing effective member count flow, `.sensorEnabled` associated value, message generation, and success checks already consume the helper result.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`, scheme `SunSmart`.

---

## File Structure

- Modify `SunSmart/Common/Data/Node+SyncData.swift`
  - Change only `Group.sensorServerPublicationRetransmit(effectiveMemberCount:)`.
  - Preserve the existing `0...3` behavior.
  - Change the `4+` behavior from `.disabled` to `Publish.Retransmit(1, timesWithInterval: 0.1)`.
- Verify `SunSmart/Common/Data/Node+MessageHandles.swift`
  - No source edit expected. It should continue using the retransmit carried by `.sensorEnabled`.
- Verify `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - No source edit expected. It should continue passing the final intended effective member count.
- Verify `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - No source edit expected. It should continue checking expected retransmit for success.
- Verify `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`
  - No source edit expected. It should continue mirroring the normal sync success check.

No new Swift source files are created, so the Xcode project file does not need source membership edits.

---

### Task 1: Update 4 Plus Member Retransmit Rule

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift`

- [ ] **Step 1: Inspect the current helper**

Run:

```bash
sed -n '92,112p' SunSmart/Common/Data/Node+SyncData.swift
```

Expected: `sensorServerPublicationRetransmit(effectiveMemberCount:)` returns `Publish.Retransmit(2, timesWithInterval: 0.1)` for `memberCount <= 3` and currently returns `.disabled` for larger groups.

- [ ] **Step 2: Write the minimal implementation**

In `SunSmart/Common/Data/Node+SyncData.swift`, replace:

```swift
func sensorServerPublicationRetransmit(effectiveMemberCount: Int? = nil) -> Publish.Retransmit {
    let memberCount = effectiveMemberCount ?? nodes.count
    guard memberCount <= 3 else {
        return .disabled
    }
    return Publish.Retransmit(2, timesWithInterval: 0.1)
}
```

with:

```swift
func sensorServerPublicationRetransmit(effectiveMemberCount: Int? = nil) -> Publish.Retransmit {
    let memberCount = effectiveMemberCount ?? nodes.count
    guard memberCount <= 3 else {
        return Publish.Retransmit(1, timesWithInterval: 0.1)
    }
    return Publish.Retransmit(2, timesWithInterval: 0.1)
}
```

- [ ] **Step 3: Confirm the helper has no old large-group disabled branch**

Run:

```bash
sed -n '92,112p' SunSmart/Common/Data/Node+SyncData.swift
rg -n 'return \\.disabled|sensorServerPublicationRetransmit|Publish\\.Retransmit\\(1, timesWithInterval: 0\\.1\\)|Publish\\.Retransmit\\(2, timesWithInterval: 0\\.1\\)' SunSmart/Common/Data/Node+SyncData.swift
```

Expected:

- The helper returns `Publish.Retransmit(1, timesWithInterval: 0.1)` in the `memberCount > 3` branch.
- The helper still returns `Publish.Retransmit(2, timesWithInterval: 0.1)` for `memberCount <= 3`.
- Any remaining `return .disabled` matches unrelated code, not `sensorServerPublicationRetransmit(effectiveMemberCount:)`.

- [ ] **Step 4: Commit Task 1**

```bash
git add SunSmart/Common/Data/Node+SyncData.swift
git commit -m "Update large group publication retransmit"
```

---

### Task 2: Verify Existing Plumbing Still Uses The Helper Result

**Files:**
- Verify: `SunSmart/Common/Data/Node+SyncData.swift`
- Verify: `SunSmart/Common/Data/Node+MessageHandles.swift`
- Verify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Verify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

- [ ] **Step 1: Confirm effective member count still reaches profile sync**

Run:

```bash
rg -n 'effectiveMemberCount|getNodeSyncProfiles\\(group: group, effectiveMemberCount: effectiveMemberCount\\)|sensorServerPublicationRetransmit\\(effectiveMemberCount: effectiveMemberCount\\)' SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

- `NodeSyncType.group` has `effectiveMemberCount: Int? = nil`.
- `SyncDevicesViewController` computes `effectiveMemberCount` from remaining plus added nodes in `.group(group, inNodes, outNodes)`.
- `node.getSyncData(type: .group(group, effectiveMemberCount: effectiveMemberCount))` passes the count.
- `getNodeSyncProfiles(group:effectiveMemberCount:)` calls `group.sensorServerPublicationRetransmit(effectiveMemberCount: effectiveMemberCount)`.

- [ ] **Step 2: Confirm message generation still uses `.sensorEnabled` retransmit**

Run:

```bash
rg -n 'case \\.sensorEnabled\\(let sensorModels, let publishAddress, let delay, let retransmit\\)|retransmit: retransmit|ConfigModelPublicationSet\\(Publish' SunSmart/Common/Data/Node+MessageHandles.swift
```

Expected: `ConfigModelPublicationSet(Publish(... retransmit: retransmit), to: ...)` is used in the `.sensorEnabled` path.

- [ ] **Step 3: Confirm success checks still compare expected retransmit**

Run:

```bash
rg -n 'isSensorServerPublicationConfigured\\(publishAddress: publishAddress, retransmit: retransmit\\)|case \\.sensorEnabled\\(let sensorModels, let publishAddress, _, let retransmit\\)' SunSmart/Main/Space/Model/SyncDevicesCellModel.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift
```

Expected: both sync success check implementations compare publication address and retransmit through `isSensorServerPublicationConfigured`.

- [ ] **Step 4: Verify docs no longer describe 4 plus groups as disabled**

Run:

```bash
rg -n 'More than `3`|more than `3`|more than 3|disabled for larger|retransmit disabled|three-device threshold' docs/superpowers/specs/2026-05-15-sensor-server-publication-retransmit-design.md docs/superpowers/plans/2026-05-15-sensor-server-publication-retransmit.md
```

Expected: no matches.

- [ ] **Step 5: Run final build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-profile-pub-4plus-build.log 2>&1
```

Expected: build succeeds.

- [ ] **Step 6: Review final diff**

Run:

```bash
git diff --stat HEAD~1..HEAD
git diff HEAD~1..HEAD -- SunSmart/Common/Data/Node+SyncData.swift
```

Expected:

- Source behavior change is limited to `Group.sensorServerPublicationRetransmit(effectiveMemberCount:)`.
- The committed source diff describes `0...3 => count 2 / 100 ms` and `4+ => count 1 / 100 ms`.

- [ ] **Step 7: Commit Task 2 only if verification required a source or doc fix**

If Step 1 through Step 6 required a fix, commit that fix:

```bash
git add SunSmart/Common/Data/Node+SyncData.swift docs/superpowers/specs/2026-05-15-sensor-server-publication-retransmit-design.md docs/superpowers/plans/2026-05-15-sensor-server-publication-retransmit.md docs/superpowers/plans/2026-05-15-sensor-server-publication-retransmit-4plus-rule.md
git commit -m "Stabilize large group publication retransmit rule"
```

If no fix was needed in this task, do not create an empty commit.
