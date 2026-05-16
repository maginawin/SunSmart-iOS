# Debug UART UI 展示窗口优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Debug / UART 消息页 UI 层展示窗口从最多 `1000` 条调整为最多 `2000` 条，并在超过上限后一次性裁剪最旧的 `500` 条。

**Architecture:** 只修改 `SpaceDebugUARTViewController` 的 UI 展示数组逻辑。Session 缓存、UART 接收、过滤规则、分享导出、Stop / Start、Clear、Auto / Manual 行为保持不变。

**Tech Stack:** Swift, UIKit, UITableView, Xcode workspace `SunSmart.xcworkspace`

---

## 文件结构

- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 调整 UART UI 展示上限常量。
  - 新增 UI 裁剪批量常量。
  - 调整 `appendDisplayMessageIfNeeded(_:)` 超限后的裁剪逻辑。
  - 保持 `rebuildDisplayMessages()` 从缓存中取最新 `2000` 条匹配消息。

不需要修改以下文件：

- `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`
- `SunSmart/Main/Space/Debug/SpaceDebugUARTLogExporter.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `SunSmart.xcodeproj/project.pbxproj`

## Task 1：调整 UI 展示窗口常量和裁剪逻辑

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1：确认当前实现位置**

Run:

```bash
rg -n "visibleMessageLimit|appendDisplayMessageIfNeeded|rebuildDisplayMessages|displayMessages.removeFirst" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected:

```text
SpaceDebugUARTViewController.swift:<line>:    private let visibleMessageLimit = 1_000
SpaceDebugUARTViewController.swift:<line>:    private func rebuildDisplayMessages() {
SpaceDebugUARTViewController.swift:<line>:    private func appendDisplayMessageIfNeeded(_ message: SpaceDebugUARTMessage) -> Bool {
SpaceDebugUARTViewController.swift:<line>:            displayMessages.removeFirst(displayMessages.count - visibleMessageLimit)
```

- [ ] **Step 2：调整展示上限并新增批量裁剪数量**

在 `SpaceDebugUARTViewController` 的常量区域，将：

```swift
private let visibleMessageLimit = 1_000
private let manualScrollSwitchThreshold: CGFloat = 30
```

改为：

```swift
private let visibleMessageLimit = 2_000
private let visibleMessageTrimCount = 500
private let manualScrollSwitchThreshold: CGFloat = 30
```

说明：

- `visibleMessageLimit` 表示 UI 层最多持有的展示消息数量。
- `visibleMessageTrimCount` 表示 UI 展示数组超过上限后，一次性删除的最旧消息数量。

- [ ] **Step 3：调整追加新消息后的超限裁剪逻辑**

在 `appendDisplayMessageIfNeeded(_:)` 中，将：

```swift
displayMessages.append(message)
if displayMessages.count > visibleMessageLimit {
    displayMessages.removeFirst(displayMessages.count - visibleMessageLimit)
}
return true
```

改为：

```swift
displayMessages.append(message)
if displayMessages.count > visibleMessageLimit {
    displayMessages.removeFirst(min(visibleMessageTrimCount, displayMessages.count))
}
return true
```

说明：

- 正常场景下，展示数组从 `2000` 追加到 `2001` 后会删除最旧的 `500` 条，剩余 `1501` 条。
- 使用 `min(visibleMessageTrimCount, displayMessages.count)` 避免异常情况下删除数量超过数组数量。
- 不修改 `rebuildDisplayMessages()`，因为它已经根据 `visibleMessageLimit` 从 Session 缓存中取最新匹配消息。

- [ ] **Step 4：静态检查改动范围**

Run:

```bash
git diff -- SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected:

- 只看到 `visibleMessageLimit` 从 `1_000` 改为 `2_000`。
- 只新增 `visibleMessageTrimCount = 500`。
- 只看到 `appendDisplayMessageIfNeeded(_:)` 超限裁剪改为按 `visibleMessageTrimCount` 批量删除。
- 不应出现 Session 缓存、分享导出、过滤规则、Auto / Manual 语义的改动。

- [ ] **Step 5：静态搜索确认没有误改缓存和导出逻辑**

Run:

```bash
rg -n "cachedUARTMessages|makeFileURL|clearUARTMessages|visibleMessageLimit|visibleMessageTrimCount|removeFirst" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift SunSmart/Main/Space/Debug/DebugBluetoothSession.swift SunSmart/Main/Space/Debug/SpaceDebugUARTLogExporter.swift
```

Expected:

- `visibleMessageLimit` 为 `2_000`。
- `visibleMessageTrimCount` 为 `500`。
- `SpaceDebugUARTViewController.swift` 中 Share 仍读取 `session.cachedUARTMessages()`。
- `DebugBluetoothSession.swift` 的缓存裁剪策略没有变化。
- `SpaceDebugUARTLogExporter.swift` 没有变化。

- [ ] **Step 6：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

允许出现项目已有 warning，例如重复 Compile Sources、GeneratedAssetSymbols 资源重名、历史 deprecated API warning。不能出现本次改动导致的 Swift 编译错误。

- [ ] **Step 7：提交代码改动**

Run:

```bash
git status --short
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "perf: tune uart display window trimming"
```

Expected:

```text
[www/feat/debug_260516 <hash>] perf: tune uart display window trimming
```

## Task 2：人工验证 UART 页面行为

**Files:**
- Verify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1：真机打开支持 UART 的设备**

在 iPhone 真机上进入：

```text
Site / Space -> 右上角菜单 -> Debug -> 连接支持 UART 的设备 -> UART
```

Expected:

- 页面正常进入 UART 消息页。
- 已有消息先从 Session 缓存展示。
- 新消息继续追加展示。

- [ ] **Step 2：验证 Auto 模式**

保持 `Auto` 模式并让设备持续输出高频 UART 消息。

Expected:

- 新消息持续展示。
- 列表自动滚动到最新可见消息。
- 当 UI 展示数组达到上限后，页面仍保持响应。
- 可见消息数量应维持在约 `1500` 到 `2000` 条之间，而不是无限增长。

- [ ] **Step 3：验证 Manual 模式**

切换到 `Manual` 模式，手动滚动到旧消息位置，并让设备继续输出 UART 消息。

Expected:

- 页面不会自动滚动到底部。
- 新消息仍按现有语义进入 UI 展示数组并触发刷新。
- 达到 UI 展示上限后，会批量裁剪旧消息，降低每条消息都触发旧消息裁剪的频率。

- [ ] **Step 4：验证过滤行为**

分别输入 Contain 和 Ignore 过滤内容。

Expected:

- Contain / Ignore 规则与现有行为一致。
- 修改过滤条件后，UI 最多展示最新 `2000` 条匹配消息。
- 过滤不影响 Session 缓存。

- [ ] **Step 5：验证 Share 行为**

点击右上角 `Share` 导出 txt。

Expected:

- 如果当前正在接收，Share 前仍会自动 Stop。
- txt 内容来自 Session 缓存，不只包含 UI 当前展示窗口。
- 文件头设备信息保持不变。

- [ ] **Step 6：最终状态检查**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:

- 工作区干净。
- 最近提交包含 `perf: tune uart display window trimming`。

