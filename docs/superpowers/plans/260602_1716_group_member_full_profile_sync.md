# Group Member Full Profile Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a light is added to an existing group from group members, generate full profile configuration commands for the new member.

**Architecture:** Reuse the existing `GroupProfileSyncContext` and `forceFullProfileSync` path created for profile type switching. Extend the context so it can represent both profile type changes and member-added full sync, then pass a member-added context only to `inNodes` in `SyncDevicesViewController`.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`.

---

## Scope

Implement the approved spec:

- Design doc: `docs/superpowers/specs/260602_1705_group_member_full_profile_sync_design.md`
- Only affect manually adding light members through `GroupMembersViewController` -> `.group(group, inNodes: addNodes, outNodes: exitNodes)`
- Do not change `outNodes`, ordinary group sync/resync, scene, schedule, switch, proximity path, emergency fire controller, or UI flow

## File Structure

Modify:

- `SunSmart/Common/Data/Node+SyncData.swift`
  - Expand `GroupProfileSyncContext` so it can express the reason for forcing full profile sync.
  - Keep `shouldForceFullProfileSync` as the single property consumed by profile generation.

- `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
  - Update the profile type switch call site to create the new `GroupProfileSyncContext` shape.

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Create a member-added profile sync context for `inNodes`.
  - Pass it only to the `inNodes` loop.
  - Keep existing `profileSyncContext` for whole-group profile save only.

Do not create new source files. This avoids target membership churn across `SunSmart`, `Archipelago`, `SLG Sync Plus`, and `SylSmart`.

---

### Task 1: Baseline Source Checks

**Files:**
- Read: `SunSmart/Common/Data/Node+SyncData.swift`
- Read: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- Read: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Confirm current context shape**

Run:

```sh
rg -n "struct GroupProfileSyncContext|previousProfileType|savedProfileType|shouldForceFullProfileSync" SunSmart/Common/Data/Node+SyncData.swift
```

Expected before implementation:

```text
SunSmart/Common/Data/Node+SyncData.swift:12:struct GroupProfileSyncContext {
SunSmart/Common/Data/Node+SyncData.swift:13:    let previousProfileType: Profile.ProfileType
SunSmart/Common/Data/Node+SyncData.swift:14:    let savedProfileType: Profile.ProfileType
SunSmart/Common/Data/Node+SyncData.swift:16:    var shouldForceFullProfileSync: Bool {
```

- [ ] **Step 2: Confirm new-member path currently lacks profile sync context**

Run:

```sh
nl -ba SunSmart/Main/Space/Controller/SyncDevicesViewController.swift | sed -n '151,164p'
```

Expected before implementation:

```text
151                let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
153                outNodes?.forEach({ node in
154                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
160                inNodes?.forEach({ node in
161                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
```

- [ ] **Step 3: Confirm profile type switch call site**

Run:

```sh
nl -ba SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift | sed -n '246,253p'
```

Expected before implementation:

```text
247        let groupProfileSyncContext = group.flatMap { group -> GroupProfileSyncContext? in
248            guard let previousProfile = previousProfile,
249                  previousProfile.type != selectProfile.type else {
250                return nil
251            }
252            return GroupProfileSyncContext(previousProfileType: previousProfile.type, savedProfileType: selectProfile.type)
```

---

### Task 2: Expand GroupProfileSyncContext

**Files:**
- Modify: `SunSmart/Common/Data/Node+SyncData.swift:11-19`

- [ ] **Step 1: Replace the context struct**

In `SunSmart/Common/Data/Node+SyncData.swift`, replace the existing `GroupProfileSyncContext` with:

```swift
/// Context for group profile synchronization that needs behavior beyond normal diff-based sync.
struct GroupProfileSyncContext {
    enum Reason {
        case profileTypeChanged(previous: Profile.ProfileType, saved: Profile.ProfileType)
        case memberAdded
    }

    let reason: Reason

    var shouldForceFullProfileSync: Bool {
        switch reason {
        case .profileTypeChanged(let previous, let saved):
            return previous != saved
        case .memberAdded:
            return true
        }
    }
}
```

- [ ] **Step 2: Run a focused symbol search**

Run:

```sh
rg -n "GroupProfileSyncContext|previousProfileType|savedProfileType|reason:|memberAdded|profileTypeChanged" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected after Step 1 and before call-site updates:

```text
SunSmart/Common/Data/Node+SyncData.swift:12:struct GroupProfileSyncContext {
SunSmart/Common/Data/Node+SyncData.swift:14:        case profileTypeChanged(previous: Profile.ProfileType, saved: Profile.ProfileType)
SunSmart/Common/Data/Node+SyncData.swift:15:        case memberAdded
SunSmart/Common/Data/Node+SyncData.swift:18:    let reason: Reason
SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:252:            return GroupProfileSyncContext(previousProfileType: previousProfile.type, savedProfileType: selectProfile.type)
```

The old initializer is expected to remain only in `ProfileSettingsViewController` until Task 3.

---

### Task 3: Update Profile Type Switch Context Creation

**Files:**
- Modify: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:247-252`

- [ ] **Step 1: Update the existing profile type switch call site**

Replace:

```swift
        let groupProfileSyncContext = group.flatMap { group -> GroupProfileSyncContext? in
            guard let previousProfile = previousProfile,
                  previousProfile.type != selectProfile.type else {
                return nil
            }
            return GroupProfileSyncContext(previousProfileType: previousProfile.type, savedProfileType: selectProfile.type)
        }
```

With:

```swift
        let groupProfileSyncContext = group.flatMap { group -> GroupProfileSyncContext? in
            guard let previousProfile = previousProfile,
                  previousProfile.type != selectProfile.type else {
                return nil
            }
            return GroupProfileSyncContext(
                reason: .profileTypeChanged(previous: previousProfile.type, saved: selectProfile.type)
            )
        }
```

- [ ] **Step 2: Verify old initializer usage is gone**

Run:

```sh
rg -n "previousProfileType|savedProfileType|GroupProfileSyncContext\\(" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

```text
SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:<line>:            return GroupProfileSyncContext(
```

There should be no `previousProfileType:` or `savedProfileType:` matches.

---

### Task 4: Pass Full Profile Context to Added Members Only

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:151-162`

- [ ] **Step 1: Add the member-added context near the existing group profile context**

In the `.group(let group, let inNodes, let outNodes)` branch, replace:

```swift
                let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
```

With:

```swift
                let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
                let addedMemberProfileSyncContext: GroupProfileSyncContext? = addedNodes.isEmpty ? nil : .init(reason: .memberAdded)
```

- [ ] **Step 2: Pass it to the `inNodes` loop**

Replace:

```swift
                inNodes?.forEach({ node in
                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                })
```

With:

```swift
                inNodes?.forEach({ node in
                    let memberProfileSyncContext = addedNodes.contains(node) ? addedMemberProfileSyncContext : nil
                    let result = self.getSyncDeviceModel(
                        group: group,
                        node: node,
                        effectiveMemberCount: effectiveMemberCount,
                        profileSyncContext: memberProfileSyncContext
                    )
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                })
```

This keeps the behavior exact: only nodes that are genuinely new compared with `remainingNodes` get the full profile context.

- [ ] **Step 3: Verify `outNodes` still has no profile sync context**

Run:

```sh
nl -ba SunSmart/Main/Space/Controller/SyncDevicesViewController.swift | sed -n '151,177p'
```

Expected shape:

```text
let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
let addedMemberProfileSyncContext: GroupProfileSyncContext? = addedNodes.isEmpty ? nil : .init(reason: .memberAdded)

outNodes?.forEach({ node in
    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
...
inNodes?.forEach({ node in
    let memberProfileSyncContext = addedNodes.contains(node) ? addedMemberProfileSyncContext : nil
    let result = self.getSyncDeviceModel(
        group: group,
        node: node,
        effectiveMemberCount: effectiveMemberCount,
        profileSyncContext: memberProfileSyncContext
    )
```

---

### Task 5: Static Behavior Verification

**Files:**
- Read: `SunSmart/Common/Data/Node+SyncData.swift`
- Read: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Read: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`

- [ ] **Step 1: Verify all context reasons**

Run:

```sh
rg -n "profileTypeChanged|memberAdded|shouldForceFullProfileSync|forceFullProfileSync" SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
```

Expected:

```text
SunSmart/Common/Data/Node+SyncData.swift:<line>:        case profileTypeChanged(previous: Profile.ProfileType, saved: Profile.ProfileType)
SunSmart/Common/Data/Node+SyncData.swift:<line>:        case memberAdded
SunSmart/Common/Data/Node+SyncData.swift:<line>:    var shouldForceFullProfileSync: Bool {
SunSmart/Common/Data/Node+SyncData.swift:<line>:        case .profileTypeChanged(let previous, let saved):
SunSmart/Common/Data/Node+SyncData.swift:<line>:        case .memberAdded:
SunSmart/Common/Data/Node+SyncData.swift:<line>:        let forceFullProfileSync = profileSyncContext?.shouldForceFullProfileSync == true
SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:<line>:                let addedMemberProfileSyncContext: GroupProfileSyncContext? = addedNodes.isEmpty ? nil : .init(reason: .memberAdded)
SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift:<line>:                reason: .profileTypeChanged(previous: previousProfile.type, saved: selectProfile.type)
```

- [ ] **Step 2: Verify no ordinary group sync path was converted to full sync**

Run:

```sh
rg -n "let profileSyncContext = \\(inNodes == nil && outNodes == nil\\) \\? groupProfileSyncContext : nil|group.nodes.filter|profileSyncContext: profileSyncContext" SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected:

```text
SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:<line>:                let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:<line>:                group.nodes.filter({ node in !(outNodes?.contains(node) ?? false) }).forEach { node in
SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:<line>:                        profileSyncContext: profileSyncContext
```

- [ ] **Step 3: Verify `GroupMembersViewController` remains a pure caller**

Run:

```sh
rg -n "SyncDevicesViewController\\(type: \\.group\\(self\\.group, inNodes: addNodes, outNodes: exitNodes\\)\\)" SunSmart/Main/Group/Controller/GroupMembersViewController.swift
```

Expected:

```text
SunSmart/Main/Group/Controller/GroupMembersViewController.swift:<line>:                let vc = SyncDevicesViewController(type: .group(self.group, inNodes: addNodes, outNodes: exitNodes))
```

---

### Task 6: Build Verification

**Files:**
- Build: `SunSmart.xcworkspace`

- [ ] **Step 1: Run iPhoneOS Debug build**

Run exactly:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

Do not use a shell wrapper, log redirection, or Simulator for this verification.

- [ ] **Step 2: If build fails due to compile errors from this change, fix only the touched files**

Expected likely issues and fixes:

```text
Error: extra arguments at positions #1, #2 in call
Fix: replace old GroupProfileSyncContext(previousProfileType:savedProfileType:) call with GroupProfileSyncContext(reason:)
```

```text
Error: cannot infer contextual base in reference to member 'memberAdded'
Fix: use GroupProfileSyncContext(reason: .memberAdded) instead of .init(reason: .memberAdded)
```

After fixing, rerun the exact build command from Step 1.

---

### Task 7: Final Review and Commit

**Files:**
- Review: `SunSmart/Common/Data/Node+SyncData.swift`
- Review: `SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift`
- Review: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Commit: implementation changes only

- [ ] **Step 1: Review final diff**

Run:

```sh
git diff -- SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

Expected diff summary:

```text
Node+SyncData.swift:
- GroupProfileSyncContext now has Reason.profileTypeChanged and Reason.memberAdded
- shouldForceFullProfileSync still returns true for profile type changes and now true for member added

ProfileSettingsViewController.swift:
- profile type switch context uses reason: .profileTypeChanged(...)

SyncDevicesViewController.swift:
- inNodes loop passes member-added context only for addedNodes
- outNodes loop still does not pass profileSyncContext
- group.nodes loop still uses profileSyncContext only for whole-group profile save
```

- [ ] **Step 2: Confirm working tree scope**

Run:

```sh
git status --short
```

Expected:

```text
 M SunSmart/Common/Data/Node+SyncData.swift
 M SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift
 M SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
```

If the plan document is also modified during execution, include it only if the execution changed the plan itself.

- [ ] **Step 3: Commit implementation**

Run:

```sh
git add SunSmart/Common/Data/Node+SyncData.swift SunSmart/Main/Profile/Controller/ProfileSettingsViewController.swift SunSmart/Main/Space/Controller/SyncDevicesViewController.swift
git commit -m "fix: force full profile sync for added group members"
```

Expected:

```text
[sync-profiles <hash>] fix: force full profile sync for added group members
```

---

## Self-Review

Spec coverage:

- Added members get full profile sync: Task 4 passes `.memberAdded` context to `inNodes`.
- Deleted members unaffected: Task 4 and Task 5 verify `outNodes` does not receive context.
- Ordinary group sync/resync unaffected: Task 4 keeps existing `profileSyncContext` gate; Task 5 verifies it.
- Profile type switching remains available: Task 3 updates existing call site; Task 5 verifies `.profileTypeChanged`.
- Build verification included: Task 6.

Placeholder scan:

- No TBD, TODO, or unspecified implementation steps.
- Compile-fix examples are concrete and scoped to expected errors.

Type consistency:

- `GroupProfileSyncContext(reason:)` is introduced in Task 2 and used consistently in Tasks 3 and 4.
- `shouldForceFullProfileSync` remains the only consumed property in `Node.getNodeSyncProfiles(...)`.
- `memberProfileSyncContext` is optional and passed to the existing optional `profileSyncContext` parameter.

## Execution Preference

Project instructions prefer Inline Execution after plan writing. Use `superpowers:executing-plans` to execute this plan in the current session unless the user explicitly requests subagents.
