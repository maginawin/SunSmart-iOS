# EFC Delete Return Others Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix successful EFC Delete from the EFC monitor page so it closes back to Others when the monitor was presented from Others, while preserving Others list refresh behavior.

**Architecture:** Keep the existing shared EFC delete flow intact. Add a narrow contract assertion for modal navigation dismissal, then update only `EmerFireAlarmMonitorVC.closeOrBack()` so it handles both self-presented and navigationController-presented root screens before falling back to pop.

**Tech Stack:** Swift, UIKit, existing `DeviceProtocol` delete helper, shell contract script, iPhoneOS `xcodebuild`.

---

## File Structure

- Modify: `scripts/check_efc_controller_flows.sh`
  - Responsibility: static contract guards for EFC flow regressions.
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
  - Responsibility: EFC monitor navigation and menu/delete routing.
- Reference only: `docs/260622_0953_efc_delete_return_others_design.md`
  - Responsibility: confirmed design and scope boundary.

## Task 1: Add Contract Guard

**Files:**
- Modify: `scripts/check_efc_controller_flows.sh`
- Reference: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`

- [ ] **Step 1: Add failing contract assertions**

Add these assertions near the existing EFC delete assertions in `scripts/check_efc_controller_flows.sh`, after the assertion that checks `deleteNodes(nodes: \[node\])`:

```bash
assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "navigationController?.presentingViewController != nil" \
  "EFC device page close/back must dismiss a presented navigation controller root after Delete."

assert_contains "SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift" \
  "navigationController?.dismiss(animated: true)" \
  "EFC device page close/back must dismiss the modal navigation controller when it is the presented container."
```

- [ ] **Step 2: Run contract and verify it fails**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: FAIL with `EFC device page close/back must dismiss a presented navigation controller root after Delete.`

- [ ] **Step 3: Commit contract guard**

Do not commit yet if implementing in the same session. Keep the guard and implementation in one focused commit after verification.

## Task 2: Fix EFC Monitor Close Logic

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift:138`

- [ ] **Step 1: Replace `closeOrBack()` with modal-container-aware logic**

Replace the existing method:

```swift
func closeOrBack() {
    if presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1 {
        dismiss(animated: true)
    } else {
        navigationController?.popViewController(animated: true)
    }
}
```

with:

```swift
func closeOrBack() {
    let isNavigationRoot = navigationController?.viewControllers.first === self
    if presentingViewController != nil && isNavigationRoot {
        dismiss(animated: true)
    } else if navigationController?.presentingViewController != nil && isNavigationRoot {
        navigationController?.dismiss(animated: true)
    } else {
        navigationController?.popViewController(animated: true)
    }
}
```

- [ ] **Step 2: Run contract and verify it passes**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
```

Expected: no output and exit code 0.

## Task 3: Verify Build and Diff

**Files:**
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
- Verify: `scripts/check_efc_controller_flows.sh`

- [ ] **Step 1: Check whitespace and patch shape**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 2: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Review final diff**

Run:

```bash
git diff -- scripts/check_efc_controller_flows.sh SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift
```

Expected:

- `scripts/check_efc_controller_flows.sh` only adds the two close/back contract assertions.
- `EmerFireAlarmMonitorRouting.swift` only changes `closeOrBack()`.
- No delete/reset/sync planner behavior changes.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add scripts/check_efc_controller_flows.sh SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift
git commit -m "fix: return to Others after EFC delete"
```

Expected: one focused commit with the contract and implementation.

## Self-Review

- Spec coverage: Task 1 covers the regression guard; Task 2 implements the selected shared close helper fix; Task 3 covers contract, diff hygiene, and iPhoneOS build.
- Placeholder scan: no placeholder markers are left in the plan.
- Scope check: the plan does not alter EFC delete/reset/sync cleanup, Others list source, localization, resources, targets, or dependencies.
