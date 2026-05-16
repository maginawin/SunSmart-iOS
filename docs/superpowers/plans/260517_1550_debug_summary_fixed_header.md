# Debug Summary Fixed Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Debug page so the top summary row stays fixed while the device list scrolls underneath it.

**Architecture:** Move `SpaceDebugSummaryView` out of `UITableView.tableHeaderView` and make it a sibling of the table view in `SpaceDebugViewController`. Keep all scan state, count rendering, list grouping, sorting, and connection behavior unchanged.

**Tech Stack:** Swift, UIKit, SnapKit, `UITableView`, existing SunSmart Debug UI classes.

---

## File Structure

- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
  - Owns Debug page layout.
  - Will add `summaryView` directly to the root view.
  - Will constrain `tableView` below `summaryView`.
  - Will stop assigning `summaryView` as `tableHeaderView`.

- Read-only: `SunSmart/Main/Space/Debug/SpaceDebugSummaryView.swift`
  - Keeps the existing summary row visual style and `update(state:found:total:)` API.
  - No changes required.

- Read-only: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`
  - Keeps existing scan state, found count, section grouping, and stable ordering.
  - No changes required.

---

### Task 1: Fix Debug Summary Layout

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift:56-70`

- [ ] **Step 1: Inspect the current layout ownership**

Run: `sed -n '56,70p' SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

Expected: output shows `tableView.tableHeaderView = summaryView` and `tableView.snp.makeConstraints { make in make.edges.equalToSuperview() }`.

- [ ] **Step 2: Move `summaryView` to the root view**

In `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`, replace the body of `setupUI()` with:

```swift
private func setupUI() {
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "stop".localizedString, style: .plain, target: self, action: #selector(scanButtonTapped))

    view.addSubview(summaryView)
    summaryView.snp.makeConstraints { make in
        make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
        make.left.right.equalToSuperview()
        make.height.equalTo(SCRYFrom(68))
    }

    tableView.backgroundColor = Background_Color
    tableView.separatorStyle = .none
    tableView.rowHeight = SCRYFrom(72)
    tableView.register(SpaceDebugDeviceCell.self, forCellReuseIdentifier: SpaceDebugDeviceCell.reuseIdentifier)
    tableView.dataSource = self
    tableView.delegate = self
    view.addSubview(tableView)
    tableView.snp.makeConstraints { make in
        make.top.equalTo(summaryView.snp.bottom)
        make.left.right.bottom.equalToSuperview()
    }
}
```

Expected: `summaryView` is no longer assigned to `tableView.tableHeaderView`, and the table view top edge starts below the summary view.

- [ ] **Step 3: Verify the old table header assignment is gone**

Run: `rg -n "tableHeaderView|make\\.edges\\.equalToSuperview\\(\\)" SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

Expected: no `tableHeaderView` match in `SpaceDebugViewController.swift`; no `make.edges.equalToSuperview()` match for the Debug table layout.

- [ ] **Step 4: Commit the layout change**

Run:

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugViewController.swift
git commit -m "fix: keep debug summary fixed"
```

Expected: commit succeeds with only `SpaceDebugViewController.swift` staged.

---

### Task 2: Verify Build And Behavior

**Files:**
- Read: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
- Read: `SunSmart/Main/Space/Debug/SpaceDebugSummaryView.swift`

- [ ] **Step 1: Run static checks for the fixed layout**

Run: `rg -n "summaryView\\.snp\\.makeConstraints|safeAreaLayoutGuide|summaryView\\.snp\\.bottom|tableHeaderView" SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

Expected:

```text
SunSmart/Main/Space/Debug/SpaceDebugViewController.swift:<line>:        summaryView.snp.makeConstraints { make in
SunSmart/Main/Space/Debug/SpaceDebugViewController.swift:<line>:            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
SunSmart/Main/Space/Debug/SpaceDebugViewController.swift:<line>:            make.top.equalTo(summaryView.snp.bottom)
```

There should be no `tableHeaderView` result.

- [ ] **Step 2: Build the SunSmart Debug iOS target**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-debug-summary-fixed-header.log 2>&1"`

Expected: command exits with status `0`.

If it fails, inspect the build log:

Run: `tail -80 /tmp/sun-smart-debug-summary-fixed-header.log`

Expected: the final errors point to concrete compile issues; fix only issues caused by this layout change.

- [ ] **Step 3: Check the git state**

Run: `git status --short`

Expected: clean worktree after the implementation commit, or only intentionally uncommitted files if the user asked not to commit.

- [ ] **Step 4: Manual UI verification**

On a device or simulator that can enter the Space Debug page:

1. Enter a Space and open `Debug`.
2. Confirm the summary row is visible at the top.
3. Scroll the device list downward.
4. Confirm the summary row stays fixed.
5. Confirm `Lights / Switches / Sensors / Others` section headers still scroll as part of the list.
6. Confirm found count and scan state still update.
7. Tap a found device and confirm the existing connection flow still starts.

Expected: only the summary row is fixed; list behavior and connection behavior are unchanged.

---

## Self-Review

- Spec coverage: The plan fixes the summary row by moving it out of `tableHeaderView`, keeps section headers scrolling, and avoids changes to scan, ViewModel, localization, UART, and detail pages.
- Scope: The implementation touches only `SpaceDebugViewController.swift`, matching the confirmed recommendation.
- Type consistency: Existing identifiers `summaryView`, `tableView`, `SpaceDebugDeviceCell.reuseIdentifier`, `scanButtonTapped`, `SCRYFrom`, and `view.safeAreaLayoutGuide.snp.top` match current code patterns.
