# Group Members Light Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Group - Members` show the same device category as `Space - Main - Lights`.

**Architecture:** Keep the existing `GroupMembersViewController.viewWillAppear` data flow. Narrow the existing `isVisibleGroupMemberNode(_:)` helper so it only returns `true` for `node.deviceType == .light`; the existing group membership filter remains unchanged.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode workspace `SunSmart.xcworkspace`.

---

### Task 1: Update Members Device Type Filter

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupMembersViewController.swift`

- [ ] **Step 1: Inspect the current filter**

Run:

```bash
sed -n '92,134p' SunSmart/Main/Group/Controller/GroupMembersViewController.swift
```

Expected: `viewWillAppear` filters `MeshNetworkManager.instance.realNodes` through `isVisibleGroupMemberNode(_:)`, and `isVisibleGroupMemberNode(_:)` currently excludes only `.gateway` and `.emergencyController`.

- [ ] **Step 2: Change the filter to match Lights**

Replace `isVisibleGroupMemberNode(_:)` with:

```swift
    private func isVisibleGroupMemberNode(_ node: Node) -> Bool {
        return node.deviceType == .light
    }
```

This keeps the existing `($0.group == nil || $0.group?.address.address == group.address.address)` condition untouched in `viewWillAppear`.

- [ ] **Step 3: Inspect the diff**

Run:

```bash
git diff -- SunSmart/Main/Group/Controller/GroupMembersViewController.swift
```

Expected: only `isVisibleGroupMemberNode(_:)` changed.

- [ ] **Step 4: Build SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add SunSmart/Main/Group/Controller/GroupMembersViewController.swift
git commit -m "fix: filter group members to lights"
```

Expected: commit contains only the focused Swift change.

## Self-Review

- Spec coverage: implements the approved rule that Members only shows devices from the same type category as `Space - Main - Lights`.
- Scope: does not change `Space - Main - Lights`, `Space - Switches`, group detail member grid, device deletion, or SDK code.
- Placeholder scan: no placeholders or deferred implementation steps.
- Type consistency: uses existing `Node.deviceType` and `.light` symbols already used by `DeviceLightsViewController`.
