# UART Filter Clear Xmark Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change both UART filter clear buttons to use the SF Symbol `xmark`.

**Architecture:** `SpaceDebugUARTViewController` configures both Contain and Ignore filter clear buttons through one helper, `configureFilterClearButton(_:action:)`. Replace only the SF Symbol name in that helper so both buttons update together while preserving layout, color, size, and clear behavior.

**Tech Stack:** Swift, UIKit, SF Symbols, existing SunSmart Debug UART UI.

---

## File Structure

- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - Owns UART message page controls.
  - Contains `containFilterClearButton` and `ignoreFilterClearButton`.
  - Contains `configureFilterClearButton(_:action:)`, the shared helper that sets the clear button image.

- Read-only: `docs/260517_1627_uart_filter_clear_xmark_spec.md`
  - Defines the approved scope: replace `xmark.circle.fill` with `xmark` only.

---

### Task 1: Replace Filter Clear Button Icon

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift:231-238`

- [ ] **Step 1: Inspect the current icon helper**

Run: `sed -n '231,238p' SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

Expected: output shows:

```swift
private func configureFilterClearButton(_ button: UIButton, action: Selector) {
    button.setTitle(nil, for: .normal)
    button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    button.tintColor = SubText_Color
    button.imageView?.contentMode = .scaleAspectFit
    button.addTarget(self, action: action, for: .touchUpInside)
}
```

- [ ] **Step 2: Replace the SF Symbol name**

In `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`, replace the helper with:

```swift
private func configureFilterClearButton(_ button: UIButton, action: Selector) {
    button.setTitle(nil, for: .normal)
    button.setImage(UIImage(systemName: "xmark"), for: .normal)
    button.tintColor = SubText_Color
    button.imageView?.contentMode = .scaleAspectFit
    button.addTarget(self, action: action, for: .touchUpInside)
}
```

Expected: only the system image name changes; title clearing, tint color, image view content mode, target/action, constraints, and text field logic remain unchanged.

- [ ] **Step 3: Verify the icon replacement statically**

Run: `rg -n "xmark|xmark\\.circle\\.fill|configureFilterClearButton" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

Expected:

```text
SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift:<line>:    private func configureFilterClearButton(_ button: UIButton, action: Selector) {
SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift:<line>:        button.setImage(UIImage(systemName: "xmark"), for: .normal)
```

There should be no `xmark.circle.fill` result.

- [ ] **Step 4: Commit the icon change**

Run:

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "style: update uart filter clear icon"
```

Expected: commit succeeds with only `SpaceDebugUARTViewController.swift` staged.

---

### Task 2: Verify Build And Behavior

**Files:**
- Read: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: Run focused static verification**

Run: `rg -n "UIImage\\(systemName: \\\"xmark\\\"\\)|xmark\\.circle\\.fill|containFilterClearButton|ignoreFilterClearButton" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

Expected:

```text
SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift:<line>:    private let containFilterClearButton = UIButton(type: .system)
SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift:<line>:    private let ignoreFilterClearButton = UIButton(type: .system)
SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift:<line>:        button.setImage(UIImage(systemName: "xmark"), for: .normal)
```

There should be no `xmark.circle.fill` result.

- [ ] **Step 2: Build the SunSmart Debug iOS target**

Run: `/bin/zsh -lc "xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-uart-filter-xmark.log 2>&1"`

Expected: command exits with status `0`, and the build log ends with `** BUILD SUCCEEDED **`.

If the command fails because of sandboxed Xcode or CoreSimulator permissions, rerun the same command with elevated sandbox permissions.

- [ ] **Step 3: Check git state**

Run: `git status --short`

Expected: clean worktree after the implementation commit.

- [ ] **Step 4: Manual UI verification**

On a device or simulator that can enter the UART messages page:

1. Open Debug for a found device that supports UART.
2. Enter the UART messages page.
3. Confirm the Contain input clear button displays the SF Symbol `xmark`.
4. Confirm the Ignore input clear button displays the SF Symbol `xmark`.
5. Type text in Contain and tap its right-side button.
6. Confirm Contain is cleared and the message list refreshes.
7. Type text in Ignore and tap its right-side button.
8. Confirm Ignore is cleared and the message list refreshes.

Expected: only the button glyph changes; layout and clear behavior remain unchanged.

---

## Self-Review

- Spec coverage: Task 1 replaces `xmark.circle.fill` with `xmark`; Task 2 verifies both button declarations remain and the old symbol is gone.
- Scope: The plan changes only `SpaceDebugUARTViewController.swift`; it does not modify layout constraints, filtering behavior, localization, resources, or UART message logic.
- Type consistency: Existing identifiers `configureFilterClearButton`, `containFilterClearButton`, `ignoreFilterClearButton`, `SubText_Color`, and `UIImage(systemName:)` match current code.
