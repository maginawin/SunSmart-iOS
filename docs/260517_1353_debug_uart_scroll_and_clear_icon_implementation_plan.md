# Debug UART 清除图标与手动滚动切换 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 Debug / UART 消息页的过滤清除按钮视觉，并在用户手动拖动消息列表超过 `30pt` 时自动切换到 `Manual` 模式。

**Architecture:** 改动限制在 `SpaceDebugUARTViewController`。清除按钮继续复用现有 UIButton，只把文字展示改为 SF Symbols；滚动切换只在 `UITableViewDelegate` 的用户拖动回调中判断，不影响程序自动滚动、过滤、缓存、导出和接收链路。

**Tech Stack:** iOS UIKit、Swift、SnapKit、UITableView、SF Symbols、Xcode build。

---

## 文件结构

- 修改：`SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 负责 Debug UART 页面 UI、过滤输入、消息列表展示、滚动模式和接收控制。
  - 本次在该文件内完成全部改动，不新增文件。

## 验证命令

计划完成后运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

期望结果：输出包含 `** BUILD SUCCEEDED **`。

---

### Task 1: 替换过滤清除按钮为 SF Symbols 图标

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: 定位当前清除按钮配置**

查看 `configureFilterClearButton(_:action:)`，确认当前仍是文字 `x`：

```swift
private func configureFilterClearButton(_ button: UIButton, action: Selector) {
    button.setTitle("x", for: .normal)
    button.setTitleColor(SubText_Color, for: .normal)
    button.titleLabel?.font = FONTS(SCRXFrom(16))
    button.addTarget(self, action: action, for: .touchUpInside)
}
```

- [ ] **Step 2: 替换为 SF Symbols 图标配置**

将 `configureFilterClearButton(_:action:)` 替换为：

```swift
private func configureFilterClearButton(_ button: UIButton, action: Selector) {
    button.setTitle(nil, for: .normal)
    button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    button.tintColor = SubText_Color
    button.imageView?.contentMode = .scaleAspectFit
    button.addTarget(self, action: action, for: .touchUpInside)
}
```

保持现有约束不变：

```swift
containFilterClearButton.snp.makeConstraints { make in
    make.right.equalTo(SCRXFrom(-16))
    make.centerY.equalTo(containFilterTextField)
    make.width.height.equalTo(SCRXFrom(30))
}
```

```swift
ignoreFilterClearButton.snp.makeConstraints { make in
    make.right.equalTo(containFilterClearButton)
    make.centerY.equalTo(ignoreFilterTextField)
    make.width.height.equalTo(containFilterClearButton)
}
```

- [ ] **Step 3: 编译验证图标 API 可用**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

期望结果：输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 提交 Task 1**

运行：

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "style: update uart filter clear icons"
```

---

### Task 2: 用户拖动超过 30pt 自动切换 Manual

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: 增加拖动阈值和状态**

在现有属性附近：

```swift
private let visibleMessageLimit = 1_000
private var messages: [SpaceDebugUARTMessage] = []
private var displayMessages: [SpaceDebugUARTMessage] = []
private var scrollMode: UARTScrollMode = .auto
```

调整为：

```swift
private let visibleMessageLimit = 1_000
private let manualScrollSwitchThreshold: CGFloat = 30
private var messages: [SpaceDebugUARTMessage] = []
private var displayMessages: [SpaceDebugUARTMessage] = []
private var scrollMode: UARTScrollMode = .auto
private var userDragStartContentOffsetY: CGFloat?
private var hasSwitchedToManualForCurrentDrag = false
```

- [ ] **Step 2: 增加列表可滚动判断**

在 `scrollToLatestVisibleMessage(animated:)` 后面增加：

```swift
private var canScrollMessagesVertically: Bool {
    let verticalInset = tableView.adjustedContentInset.top + tableView.adjustedContentInset.bottom
    return tableView.contentSize.height + verticalInset > tableView.bounds.height
}
```

这个判断用于避免内容不足一屏时，用户拉动弹性区域也触发 `Manual`。

- [ ] **Step 3: 增加切换和重置 helper**

在 `canScrollMessagesVertically` 后面增加：

```swift
private func switchToManualModeForUserDragIfNeeded(currentOffsetY: CGFloat) {
    guard scrollMode == .auto,
          !hasSwitchedToManualForCurrentDrag,
          let dragStartContentOffsetY = userDragStartContentOffsetY else {
        return
    }

    let dragDistance = abs(currentOffsetY - dragStartContentOffsetY)
    guard dragDistance > manualScrollSwitchThreshold else {
        return
    }

    scrollMode = .manual
    modeControl.selectedSegmentIndex = 1
    hasSwitchedToManualForCurrentDrag = true
}

private func resetUserDragTracking() {
    userDragStartContentOffsetY = nil
    hasSwitchedToManualForCurrentDrag = false
}
```

- [ ] **Step 4: 增加 UIScrollViewDelegate 回调**

在 `UITableViewDataSource, UITableViewDelegate` extension 中，`cellForRowAt` 后面增加：

```swift
func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView === tableView, canScrollMessagesVertically else {
        resetUserDragTracking()
        return
    }

    userDragStartContentOffsetY = scrollView.contentOffset.y
    hasSwitchedToManualForCurrentDrag = false
}

func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === tableView, scrollView.isDragging else {
        return
    }

    switchToManualModeForUserDragIfNeeded(currentOffsetY: scrollView.contentOffset.y)
}

func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    guard scrollView === tableView, !decelerate else {
        return
    }

    resetUserDragTracking()
}

func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    guard scrollView === tableView else {
        return
    }

    resetUserDragTracking()
}
```

关键点：

- `scrollView.isDragging` 保证只有用户拖动会进入判断。
- 程序调用 `scrollToRow` 不满足 `isDragging`，不会误切换。
- 拖动结束后重置本次拖动状态。

- [ ] **Step 5: 编译验证滚动回调实现**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

期望结果：输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 提交 Task 2**

运行：

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "feat: switch uart logs to manual on drag"
```

---

### Task 3: 最终验证与人工验收清单

**Files:**
- Verify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: 查看最终 diff**

运行：

```bash
git diff HEAD~2..HEAD -- SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

期望结果：

- `configureFilterClearButton(_:action:)` 使用 `UIImage(systemName: "xmark.circle.fill")`。
- 新增 `manualScrollSwitchThreshold`，值为 `30`。
- 新增用户拖动状态字段。
- 新增 `scrollViewWillBeginDragging`、`scrollViewDidScroll`、`scrollViewDidEndDragging`、`scrollViewDidEndDecelerating`。
- 没有修改 UART 接收、缓存、导出、断线重连逻辑。

- [ ] **Step 2: 运行最终构建**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

期望结果：输出包含 `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 真机人工验收**

在 Debug / UART 消息页执行：

- `Contain` 与 `Ignore` 清除按钮显示为 SF Symbols 关闭图标。
- 输入框为空时，两个清除按钮仍然可见。
- 点击 `Contain` 清除按钮只清除 `Contain` 输入，不影响 `Ignore`。
- 点击 `Ignore` 清除按钮只清除 `Ignore` 输入，不影响 `Contain`。
- `Auto` 模式下收到新消息仍自动滚动到最新可见消息。
- `Auto` 模式下轻微拖动不超过 `30pt`，仍保持 `Auto`。
- `Auto` 模式下拖动超过 `30pt`，分段控件自动切到 `Manual`。
- 切到 `Manual` 后，新消息不再自动滚动到底部。
- 手动点回 `Auto` 后，页面立即滚动到最新可见消息。
- 自动滚动、过滤刷新、Clear、Share 不会误切换到 `Manual`。

- [ ] **Step 4: 收尾状态检查**

运行：

```bash
git status --short
```

期望结果：没有未提交业务代码。若只有日志文件或构建产物，不提交；若存在本计划产生的源码改动，先确认是否已包含在 Task 1 或 Task 2 提交中。
