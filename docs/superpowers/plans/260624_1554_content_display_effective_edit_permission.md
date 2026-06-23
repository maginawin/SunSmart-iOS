# Content Display Effective Edit Permission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Per project preference, use Inline Execution unless the user explicitly requests subagents.

**Goal:** Hide `Site - Space - More - Content Display` unless the current Space session has effective edit capability, and keep the Content Display page read-only if permission changes while it is open.

**Architecture:** Use `space.deviceOperates.contains(.edit)` as the single permission truth for both More entry visibility and Content Display page editability. `SpaceMoreViewController` rebuilds its options when `spacePermissionChangedNotificaitonName` fires, preserving the long-press Mesh test entry. `ContentDisplayViewController` reloads its table on the same notification so existing cells immediately reflect the latest capability.

**Tech Stack:** Swift, UIKit, `UICollectionView`, `UITableView`, existing `SpaceData.deviceOperates`, existing `spacePermissionChangedNotificaitonName`, Xcode iPhoneOS build.

---

## Scope

Implement the approved spec:

- Spec: `docs/superpowers/specs/260624_1551_content_display_effective_edit_permission_design.md`
- Modify only:
  - `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
  - `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`
- Do not modify:
  - `SpaceData.swift`
  - data import/export/database files
  - localization files
  - image assets
  - `SunSmart.xcodeproj/project.pbxproj`
  - target configuration

## Files

- Modify: `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
  - Replace the fixed `options` array with permission-derived options.
  - Track whether the hidden Mesh test option has been enabled by long press.
  - Listen to `spacePermissionChangedNotificaitonName`.
  - Guard `.contentDisplay` selection with the same effective edit condition.

- Modify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`
  - Change `isEditable` to use `space.deviceOperates.contains(.edit)`.
  - Listen to `spacePermissionChangedNotificaitonName`.
  - Reload the table when permission changes.

## Task 1: Gate Content Display in Space More

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`

- [ ] **Step 1: Confirm the current unconditional entry**

Run:

```sh
rg -n "private var options|\\.contentDisplay|spacePermissionChangedNotificaitonName|deviceOperates.contains\\(\\.edit\\)" SunSmart/Main/Space/Controller/SpaceMoreViewController.swift
```

Expected before implementation:

- `private var options` contains `.contentDisplay`.
- The `.contentDisplay` selection branch has no `deviceOperates.contains(.edit)` guard.
- There is no `spacePermissionChangedNotificaitonName` observer in this file.

- [ ] **Step 2: Replace the fixed options state with derived options**

In `SpaceMoreViewController`, replace the current fixed `options` property:

```swift
    private var options: [Options] = [.ble, .deviceParameters, .energyData,
        //.triggerZone,
        .contentDisplay]
```

with:

```swift
    private var options: [Options] = []
    private var isMeshTestOptionEnabled = false

    private var canShowContentDisplay: Bool {
        space.deviceOperates.contains(.edit)
    }
```

- [ ] **Step 3: Add option building and notification observer helpers**

Add these methods inside the main `SpaceMoreViewController` class, after `viewDidLoad()` and before `setupCollectionView()`:

```swift
    private func makeOptions() -> [Options] {
        var currentOptions: [Options] = [.ble, .deviceParameters, .energyData]

        if isMeshTestOptionEnabled {
            currentOptions.insert(.mesh, at: 1)
        }

        if canShowContentDisplay {
            currentOptions.append(.contentDisplay)
        }

        return currentOptions
    }

    private func reloadOptions() {
        options = makeOptions()
        collectionView?.reloadData()
    }

    private func observeSpacePermissionChanges() {
        NotificationCenter.default.addObserver(
            forName: .init(spacePermissionChangedNotificaitonName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadOptions()
        }
    }
```

- [ ] **Step 4: Initialize options and observer from `viewDidLoad()`**

Update `viewDidLoad()` to call `reloadOptions()` before collection view setup and register the permission observer after setup:

```swift
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color

        reloadOptions()
        setupCollectionView()
        observeSpacePermissionChanges()
    }
```

- [ ] **Step 5: Preserve the long-press Mesh test option via derived state**

In `collectionViewLongPressAction(sender:)`, replace:

```swift
        guard !options.contains(.mesh) else {
            return
        }
        options.insert(.mesh, at: 1)
        collectionView.insertItems(at: [IndexPath(item: 1, section: 0)])
```

with:

```swift
        guard !isMeshTestOptionEnabled else {
            return
        }
        isMeshTestOptionEnabled = true
        options = makeOptions()
        collectionView.insertItems(at: [IndexPath(item: 1, section: 0)])
```

- [ ] **Step 6: Add a defensive guard for `.contentDisplay` selection**

In `collectionView(_:didSelectItemAt:)`, update the `.contentDisplay` case from:

```swift
        case .contentDisplay:
            let vc = ContentDisplayViewController(space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
```

to:

```swift
        case .contentDisplay:
            guard self.space.deviceOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                reloadOptions()
                return
            }
            let vc = ContentDisplayViewController(space: space)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
```

- [ ] **Step 7: Verify Space More static state**

Run:

```sh
rg -n "private var options|isMeshTestOptionEnabled|canShowContentDisplay|makeOptions|reloadOptions|observeSpacePermissionChanges|spacePermissionChangedNotificaitonName|case \\.contentDisplay|no_permission" SunSmart/Main/Space/Controller/SpaceMoreViewController.swift
```

Expected after implementation:

- `private var options: [Options] = []`
- `isMeshTestOptionEnabled` exists.
- `canShowContentDisplay` uses `space.deviceOperates.contains(.edit)`.
- `makeOptions()` appends `.contentDisplay` only behind `canShowContentDisplay`.
- `observeSpacePermissionChanges()` observes `spacePermissionChangedNotificaitonName`.
- `.contentDisplay` case has a `deviceOperates.contains(.edit)` guard.

## Task 2: Use Effective Edit Capability in Content Display

**Files:**
- Modify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`

- [ ] **Step 1: Confirm the current role-only editability**

Run:

```sh
rg -n "private var isEditable|space\\.permission == \\.owner|spacePermissionChangedNotificaitonName|reloadData" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected before implementation:

- `isEditable` checks `space.permission == .owner || space.permission == .editor`.
- There is no `spacePermissionChangedNotificaitonName` observer in this file.

- [ ] **Step 2: Change `isEditable` to effective edit capability**

Replace:

```swift
    private var isEditable: Bool {
        space.permission == .owner || space.permission == .editor
    }
```

with:

```swift
    private var isEditable: Bool {
        space.deviceOperates.contains(.edit)
    }
```

- [ ] **Step 3: Add permission-change observer helper**

Add this method inside the main `ContentDisplayViewController` class, after `viewDidLoad()` and before `back()`:

```swift
    private func observeSpacePermissionChanges() {
        NotificationCenter.default.addObserver(
            forName: .init(spacePermissionChangedNotificaitonName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tableView?.reloadData()
        }
    }
```

- [ ] **Step 4: Register the observer from `viewDidLoad()`**

Update the end of `viewDidLoad()` from:

```swift
        setupUI()
```

to:

```swift
        setupUI()
        observeSpacePermissionChanges()
```

- [ ] **Step 5: Verify closure guards still protect writes**

Run:

```sh
rg -n "cell\\.isEditable = isEditable|guard let self = self, self\\.isEditable else \\{ return \\}|space\\.displayDeviceNamePrefix =|space\\.showCCTQuickButtons =|space\\.controlType =" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected:

- All three cell configurations set `cell.isEditable = isEditable`.
- All three callbacks guard `self.isEditable` before mutating `space`.

- [ ] **Step 6: Verify Content Display static state**

Run:

```sh
rg -n "private var isEditable|deviceOperates.contains\\(\\.edit\\)|observeSpacePermissionChanges|spacePermissionChangedNotificaitonName|reloadData|space\\.permission == \\.owner" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
```

Expected after implementation:

- `isEditable` uses `space.deviceOperates.contains(.edit)`.
- `observeSpacePermissionChanges()` observes `spacePermissionChangedNotificaitonName`.
- The file no longer uses `space.permission == .owner` for Content Display editability.

## Task 3: Verify, Build, and Commit

**Files:**
- Verify: `SunSmart/Main/Space/Controller/SpaceMoreViewController.swift`
- Verify: `SunSmart/Main/Space/Controller/ContentDisplayViewController.swift`

- [ ] **Step 1: Confirm scope is limited**

Run:

```sh
git diff --name-only
```

Expected:

```text
SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
SunSmart/Main/Space/Controller/SpaceMoreViewController.swift
```

- [ ] **Step 2: Check for whitespace errors**

Run:

```sh
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 3: Run focused static checks**

Run:

```sh
rg -n "space\\.permission == \\.owner|space\\.permission == \\.editor" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift SunSmart/Main/Space/Controller/SpaceMoreViewController.swift
```

Expected:

- No matches in `ContentDisplayViewController.swift`.
- No new role-only permission check for `.contentDisplay` in `SpaceMoreViewController.swift`.

Run:

```sh
rg -n "deviceOperates.contains\\(\\.edit\\)|spacePermissionChangedNotificaitonName|\\.contentDisplay" SunSmart/Main/Space/Controller/ContentDisplayViewController.swift SunSmart/Main/Space/Controller/SpaceMoreViewController.swift
```

Expected:

- `SpaceMoreViewController.swift` uses `deviceOperates.contains(.edit)` for Content Display visibility and selection guard.
- `ContentDisplayViewController.swift` uses `deviceOperates.contains(.edit)` for `isEditable`.
- Both files observe `spacePermissionChangedNotificaitonName`.

- [ ] **Step 4: Build SunSmart for iPhoneOS**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Commit implementation**

Run:

```sh
git add SunSmart/Main/Space/Controller/SpaceMoreViewController.swift SunSmart/Main/Space/Controller/ContentDisplayViewController.swift
git commit -m "fix: gate content display by edit permission"
```

Expected:

- Commit contains only the two Swift files.
- Commit message has no Codex-related text.

## Manual QA Checklist

- [ ] Owner / Editor with effective edit capability sees `Content Display` in `Site - Space - More`.
- [ ] Visitor does not see `Content Display`.
- [ ] Owner / Editor who confirms downgrade due to another active editing user does not see `Content Display`.
- [ ] If More is already open and permission changes, `Content Display` is removed from the list.
- [ ] If Content Display is already open and permission changes, all three settings become non-editable.
- [ ] BLE, Device Parameter Settings, Energy Data, and the hidden Mesh long-press test entry still behave as before.

