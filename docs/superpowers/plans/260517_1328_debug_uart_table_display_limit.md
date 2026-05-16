# Debug UART Table Display Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Limit the Debug UART table to the latest 1000 displayable messages while preserving the existing 100000-message session cache and full Share export.

**Architecture:** Keep the cache policy in `DebugBluetoothSession` unchanged. Add a UI-only `displayMessages` snapshot in `SpaceDebugUARTViewController`, rebuild it when filters change, and incrementally append matching new messages during live receive. The current page has both `Contain` and `Ignore` filters, so the display limit applies after both filters are evaluated.

**Tech Stack:** Swift, UIKit, UITableView, SnapKit, existing Debug Bluetooth session and UART exporter.

---

## File Structure

- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - Owns table display state.
  - Adds a fixed `visibleMessageLimit` of 1000.
  - Adds `displayMessages` as the table data source.
  - Keeps `messages` as the current full session cache snapshot.
  - Keeps Share export reading `session.cachedUARTMessages()`.

No new files, resources, localizations, target settings, Pod dependencies, or SDK changes are required.

## Current Source Notes

`SpaceDebugUARTViewController` currently has two filters:

- `containFilterText`: message must contain this text when non-empty.
- `ignoreFilterText`: message must not contain this text when non-empty.

The existing `visibleMessages` computed property filters the full `messages` array on every table data source access. This is the behavior to replace.

The repository does not currently expose an app test target in the workspace, so implementation verification is compile-based plus focused manual runtime checks. Keep the implementation small and pure enough that behavior is easy to inspect.

---

### Task 1: Add UI Display Snapshot State

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: Replace the computed `visibleMessages` with stored display state**

Find this existing block near the controller properties:

```swift
private var messages: [SpaceDebugUARTMessage] = []
private var scrollMode: UARTScrollMode = .auto
private var isReceivingUARTMessages = false
private var containFilterText = ""
private var ignoreFilterText = ""
private let previousIdleTimerDisabled: Bool
private var isShowingDisconnectAlert = false
private var shouldResumeReceivingAfterReconnect = false

private var visibleMessages: [SpaceDebugUARTMessage] {
    return messages.filter { messageMatchesFilter($0) }
}
```

Replace it with:

```swift
private let visibleMessageLimit = 1_000
private var messages: [SpaceDebugUARTMessage] = []
private var displayMessages: [SpaceDebugUARTMessage] = []
private var scrollMode: UARTScrollMode = .auto
private var isReceivingUARTMessages = false
private var containFilterText = ""
private var ignoreFilterText = ""
private let previousIdleTimerDisabled: Bool
private var isShowingDisconnectAlert = false
private var shouldResumeReceivingAfterReconnect = false
```

- [ ] **Step 2: Add helpers for rebuilding and incrementally appending display messages**

Add these methods below `updateReceiveButton()` and above `scrollToLatestVisibleMessage(animated:)`:

```swift
private func rebuildDisplayMessages() {
    var latestMessages: [SpaceDebugUARTMessage] = []

    for message in messages.reversed() {
        guard messageMatchesFilter(message) else {
            continue
        }
        latestMessages.append(message)
        if latestMessages.count == visibleMessageLimit {
            break
        }
    }

    displayMessages = Array(latestMessages.reversed())
}

@discardableResult
private func appendDisplayMessageIfNeeded(_ message: SpaceDebugUARTMessage) -> Bool {
    guard messageMatchesFilter(message) else {
        return false
    }

    displayMessages.append(message)
    if displayMessages.count > visibleMessageLimit {
        displayMessages.removeFirst(displayMessages.count - visibleMessageLimit)
    }
    return true
}
```

These helpers deliberately scan from the end of `messages` so filtering stops as soon as the latest 1000 matches are found.

- [ ] **Step 3: Update initial page load to populate `displayMessages`**

Find this block in `viewDidLoad()`:

```swift
setupUI()
messages = session.cachedUARTMessages()
tableView.reloadData()
startMessages()
```

Replace it with:

```swift
setupUI()
messages = session.cachedUARTMessages()
rebuildDisplayMessages()
tableView.reloadData()
startMessages()
```

- [ ] **Step 4: Compile-check the syntax locally**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build reaches compile phase without errors from `SpaceDebugUARTViewController.swift`. If unrelated signing or dependency warnings appear, do not change unrelated project files.

---

### Task 2: Wire Live Receive, Filtering, Clearing, and Table Data Source

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: Update live message receive handling**

Find the `session.startUARTMessages(onMessage:)` callback body:

```swift
guard let self = self, self.isReceivingUARTMessages else {
    return
}
let shouldScroll = self.scrollMode == .auto && self.messageMatchesFilter(message)
self.messages = self.session.cachedUARTMessages()
self.tableView.reloadData()
if shouldScroll {
    self.scrollToLatestVisibleMessage(animated: true)
}
```

Replace it with:

```swift
guard let self = self, self.isReceivingUARTMessages else {
    return
}
let shouldScroll = self.scrollMode == .auto && self.messageMatchesFilter(message)
let previousMessageCount = self.messages.count
self.messages = self.session.cachedUARTMessages()

if self.messages.count < previousMessageCount {
    self.rebuildDisplayMessages()
    self.tableView.reloadData()
    if shouldScroll {
        self.scrollToLatestVisibleMessage(animated: true)
    }
    return
}

guard self.appendDisplayMessageIfNeeded(message) else {
    return
}

self.tableView.reloadData()
if shouldScroll {
    self.scrollToLatestVisibleMessage(animated: true)
}
```

This preserves correctness when `DebugBluetoothSession` trims from more than 100000 cached messages down to 80000. It also avoids table refreshes when filters are active and the new message is not displayable.

- [ ] **Step 2: Update auto-scroll to use `displayMessages`**

Find:

```swift
private func scrollToLatestVisibleMessage(animated: Bool) {
    let messages = visibleMessages
    guard !messages.isEmpty else {
        return
    }
    let indexPath = IndexPath(row: messages.count - 1, section: 0)
    tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
}
```

Replace it with:

```swift
private func scrollToLatestVisibleMessage(animated: Bool) {
    guard !displayMessages.isEmpty else {
        return
    }
    let indexPath = IndexPath(row: displayMessages.count - 1, section: 0)
    tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
}
```

- [ ] **Step 3: Clear both cache snapshots**

Find:

```swift
private func clearMessages() {
    session.clearUARTMessages()
    messages.removeAll()
    tableView.reloadData()
}
```

Replace it with:

```swift
private func clearMessages() {
    session.clearUARTMessages()
    messages.removeAll()
    displayMessages.removeAll()
    tableView.reloadData()
}
```

- [ ] **Step 4: Rebuild display data when either filter changes**

Find the end of `filterTextFieldChanged(_:)`:

```swift
tableView.reloadData()
if scrollMode == .auto {
    scrollToLatestVisibleMessage(animated: false)
}
```

Replace it with:

```swift
rebuildDisplayMessages()
tableView.reloadData()
if scrollMode == .auto {
    scrollToLatestVisibleMessage(animated: false)
}
```

- [ ] **Step 5: Rebuild display data when clearing the Contain filter**

Find `clearContainFilterTapped()`:

```swift
@objc private func clearContainFilterTapped() {
    containFilterTextField.text = ""
    containFilterText = ""
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

Replace it with:

```swift
@objc private func clearContainFilterTapped() {
    containFilterTextField.text = ""
    containFilterText = ""
    rebuildDisplayMessages()
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

- [ ] **Step 6: Rebuild display data when clearing the Ignore filter**

Find `clearIgnoreFilterTapped()`:

```swift
@objc private func clearIgnoreFilterTapped() {
    ignoreFilterTextField.text = ""
    ignoreFilterText = ""
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

Replace it with:

```swift
@objc private func clearIgnoreFilterTapped() {
    ignoreFilterTextField.text = ""
    ignoreFilterText = ""
    rebuildDisplayMessages()
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

- [ ] **Step 7: Point the table data source at `displayMessages`**

Find:

```swift
func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return visibleMessages.count
}

func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: SpaceDebugUARTMessageCell.reuseIdentifier, for: indexPath) as! SpaceDebugUARTMessageCell
    let message = visibleMessages[indexPath.row]
    cell.update(message: message)
    return cell
}
```

Replace it with:

```swift
func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return displayMessages.count
}

func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: SpaceDebugUARTMessageCell.reuseIdentifier, for: indexPath) as! SpaceDebugUARTMessageCell
    let message = displayMessages[indexPath.row]
    cell.update(message: message)
    return cell
}
```

- [ ] **Step 8: Confirm Share still exports the full session cache**

Inspect `shareButtonTapped()` and leave this line unchanged:

```swift
let cachedMessages = session.cachedUARTMessages()
```

Do not replace it with `messages` or `displayMessages`.

- [ ] **Step 9: Compile-check the full change**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

---

### Task 3: Focused Verification and Commit

**Files:**
- Verify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: Search for stale `visibleMessages` references**

Run:

```bash
rg -n "visibleMessages" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected: no output.

- [ ] **Step 2: Search for table data source references**

Run:

```bash
rg -n "displayMessages|visibleMessageLimit|cachedUARTMessages" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected:

```text
SpaceDebugUARTViewController.swift:<line>:    private let visibleMessageLimit = 1_000
SpaceDebugUARTViewController.swift:<line>:    private var displayMessages: [SpaceDebugUARTMessage] = []
SpaceDebugUARTViewController.swift:<line>:        messages = session.cachedUARTMessages()
SpaceDebugUARTViewController.swift:<line>:    displayMessages = Array(latestMessages.reversed())
SpaceDebugUARTViewController.swift:<line>:    displayMessages.append(message)
SpaceDebugUARTViewController.swift:<line>:    if displayMessages.count > visibleMessageLimit {
SpaceDebugUARTViewController.swift:<line>:        displayMessages.removeFirst(displayMessages.count - visibleMessageLimit)
SpaceDebugUARTViewController.swift:<line>:    guard !displayMessages.isEmpty else {
SpaceDebugUARTViewController.swift:<line>:    let indexPath = IndexPath(row: displayMessages.count - 1, section: 0)
SpaceDebugUARTViewController.swift:<line>:        self.messages = self.session.cachedUARTMessages()
SpaceDebugUARTViewController.swift:<line>:    displayMessages.removeAll()
SpaceDebugUARTViewController.swift:<line>:        let cachedMessages = session.cachedUARTMessages()
SpaceDebugUARTViewController.swift:<line>:        return displayMessages.count
SpaceDebugUARTViewController.swift:<line>:        let message = displayMessages[indexPath.row]
```

Line numbers may differ. The important checks are:

- `cachedUARTMessages()` still appears in `shareButtonTapped()`.
- Table data source reads `displayMessages`.
- `visibleMessageLimit` is 1000.

- [ ] **Step 3: Manual runtime verification on a device or simulator with UART-capable hardware**

Open Debug UART messages for a connected node and verify:

```text
1. With no filters, incoming messages still appear in chronological order.
2. Switching Auto / Manual scroll still works.
3. Entering Contain text shows only messages containing that text.
4. Entering Ignore text hides messages containing that text.
5. Clearing either filter refreshes the list immediately.
6. Share still produces a log file with all cached messages available in the session.
```

For a high-volume check, keep the page open long enough to receive more than 1000 messages. At 3 to 5 messages per second this takes roughly 4 to 6 minutes. Confirm the UI remains responsive and the newest messages remain visible in Auto mode.

- [ ] **Step 4: Review the final diff**

Run:

```bash
git diff -- SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected:

```text
Only SpaceDebugUARTViewController.swift changes.
No localization, resource, project, Pod, or SDK files change.
Share export still uses session.cachedUARTMessages().
```

- [ ] **Step 5: Commit the implementation**

Run:

```bash
git status --short
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "perf: limit debug uart table messages"
```

Expected:

```text
1 file changed
```

The commit message must not contain any codex-related footer or generated-by line.
