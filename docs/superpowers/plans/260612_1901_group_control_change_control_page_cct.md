# Group Control Change Control Page CCT Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Group control page show CCT controls only when at least one real CCT group member has `Change Control Page = Tunable White`.

**Architecture:** Keep the SDK-wide `effectiveSupportCct` semantics unchanged. Add a small `GroupViewController`-local CCT member collection for Group control display and route CCT visibility, range, local temperature updates, and limit warnings through that same collection.

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK, Xcode `xcodebuild`.

---

## File Structure

- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - Add Group control page-only CCT node helpers.
  - Replace CCT display/range/local update/limit checks to use those helpers.
- No new files.
- No localization, resource, target, dependency, database, SDK, Scene, Profile, or batch-control changes.

## Task 1: Add Group Control CCT Helpers

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Insert the helper properties near existing range properties**

Replace this block:

```swift
    private var currentGroupCCTRange: ClosedRange<Int> {
        let range = group.effectiveCctRange
        return Int(range.lowerBound)...Int(range.upperBound)
    }

    private var showsGroupControlPanel: Bool {
        group.supportLightness || group.effectiveSupportCct
    }
```

with:

```swift
    private var groupControlCCTNodes: [Node] {
        group.nodes.filter { $0.rawSupportCct && $0.effectiveChangeControlPage == .tunableWhite }
    }

    private var showsGroupControlCCT: Bool {
        !groupControlCCTNodes.isEmpty
    }

    private var currentGroupCCTRange: ClosedRange<Int> {
        let ranges = groupControlCCTNodes.map { $0.effectiveCctRange }
        guard let first = ranges.first else {
            return Int(NodeAbsoluteCctRange.defaultRange.lowerBound)...Int(NodeAbsoluteCctRange.defaultRange.upperBound)
        }
        let range = ranges.reduce(first) { result, range in
            min(result.lowerBound, range.lowerBound)...max(result.upperBound, range.upperBound)
        }
        return Int(range.lowerBound)...Int(range.upperBound)
    }

    private var showsGroupControlPanel: Bool {
        group.supportLightness || showsGroupControlCCT
    }
```

- [ ] **Step 2: Check helper compile dependencies**

Run:

```bash
rg -n "rawSupportCct|effectiveChangeControlPage|NodeAbsoluteCctRange" SunSmart/Main/Group/Controller/GroupViewController.swift /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
```

Expected:

- `GroupViewController.swift` contains the new helper references.
- SDK `Node+Propertys.swift` contains all three symbols.
- No implementation files outside `GroupViewController.swift` are changed.

## Task 2: Route Group CCT Display And Local State Through Helpers

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Update control panel CCT visibility**

In `updateControlPanel()`, replace:

```swift
            showsCCT: group.effectiveSupportCct,
```

with:

```swift
            showsCCT: showsGroupControlCCT,
```

- [ ] **Step 2: Update local CCT state application**

In `applyGroupCCTValue(_:)`, replace:

```swift
        group.nodes.filter { $0.effectiveSupportCct }.forEach {
            $0.temperature = $0.clampEffectiveCct(temperature)
        }
```

with:

```swift
        groupControlCCTNodes.forEach {
            $0.temperature = $0.clampEffectiveCct(temperature)
        }
```

- [ ] **Step 3: Update CCT limit warning membership**

In `showGroupCCTLimitMessageIfNeeded(target:)`, replace:

```swift
        let hasLimitedDevice = group.nodes
            .filter { $0.effectiveSupportCct }
            .contains { node in
                target < Int(node.effectiveCctRange.lowerBound) || target > Int(node.effectiveCctRange.upperBound)
            }
```

with:

```swift
        let hasLimitedDevice = groupControlCCTNodes.contains { node in
            target < Int(node.effectiveCctRange.lowerBound) || target > Int(node.effectiveCctRange.upperBound)
        }
```

- [ ] **Step 4: Verify all GroupViewController CCT control references are intentional**

Run:

```bash
rg -n "effectiveSupportCct|effectiveCctRange|groupControlCCTNodes|showsGroupControlCCT|currentGroupCCTRange|showGroupCCTLimitMessageIfNeeded|applyGroupCCTValue" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected:

- `showsGroupControlPanel` uses `showsGroupControlCCT`.
- `updateControlPanel()` uses `showsGroupControlCCT` for `showsCCT`.
- `currentGroupCCTRange` is computed from `groupControlCCTNodes`.
- `applyGroupCCTValue(_:)` updates `groupControlCCTNodes`.
- `showGroupCCTLimitMessageIfNeeded(target:)` checks `groupControlCCTNodes`.
- No remaining `group.effectiveSupportCct` use in `GroupViewController.swift`.

## Task 3: Verification

**Files:**
- Modify: none unless verification exposes a compile issue.

- [ ] **Step 1: Confirm no unintended broader CCT semantic changes**

Run:

```bash
git diff -- SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected:

- Diff only changes `GroupViewController.swift`.
- No SDK file changes.
- No Scene/Profile/batch-control file changes.
- No localization, resource, target, dependency, database, import/export, or cloud sync changes.

- [ ] **Step 2: Check whitespace**

Run:

```bash
git diff --check
```

Expected:

- No output.

- [ ] **Step 3: Build iPhoneOS SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build exits with status 0.
- Output includes `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "fix: respect change control page in group CCT display"
```

Expected:

- Commit succeeds.
- Commit does not include generated logs or unrelated untracked docs.

## Manual QA Matrix

Use an existing space with Group control page and CCT devices:

- Group has no real CCT devices: CCT controls hidden.
- Group has real CCT devices and all are `Single White`: CCT controls hidden.
- Group has at least one real CCT device set to `Tunable White`: CCT controls visible.
- Mixed `Single White` and `Tunable White` CCT devices: range and limit warning are based only on `Tunable White` CCT devices.
- Device control page still follows `singleDeviceDisplaySupportCct`.
- Scene/Profile/batch control behavior is unchanged from before this task.
