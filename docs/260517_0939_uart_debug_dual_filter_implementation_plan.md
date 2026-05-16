# UART Debug 双过滤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 UART 消息页的单个 `Filter messages` 输入框改为 `Contain` 和 `Ignore` 两个 UI 层过滤输入框，并保持缓存和分享导出不受过滤影响。

**Architecture:** 过滤状态继续保存在 `SpaceDebugUARTViewController` 内，只影响 `visibleMessages` 的计算。`DebugBluetoothSession`、UART 接收、缓存、Stop / Start、Clear 和 Share 不改语义。页面新增两个输入行，每行由 label、text field、永远可见的 clear button 组成。

**Tech Stack:** Swift、UIKit、SnapKit、现有本地化 `Localizable.strings`、`xcodebuild`。

---

## 文件结构

- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 负责双过滤 UI、输入状态、过滤匹配、清除按钮行为和 Auto / Manual 刷新行为。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 增加 `Contain`、`Ignore` 两个英文 UI 文案，以及两个英文输入框 placeholder。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加 `Contain`、`Ignore` 两个中文环境下仍显示英文的 UI 文案，以及两个简体中文输入框 placeholder。

当前工程没有 XCTest target，本计划不新增测试 target。验证使用集中函数自查、`SunSmart` iOS 真机构建和手动验收用例完成。

## Task 1: 增加本地化文案

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 在英文 strings 中增加两个 key**

在 `SunSmart/en.lproj/Localizable.strings` 的 UART 文案附近加入：

```text
"debug_uart_contain" = "Contain";
"debug_uart_ignore" = "Ignore";
"debug_uart_contain_placeholder" = "Message must contain";
"debug_uart_ignore_placeholder" = "Message must not contain";
```

- [ ] **Step 2: 在简体中文 strings 中增加两个 key**

在 `SunSmart/zh-Hans.lproj/Localizable.strings` 的 UART 文案附近加入：

```text
"debug_uart_contain" = "Contain";
"debug_uart_ignore" = "Ignore";
"debug_uart_contain_placeholder" = "消息必须包含";
"debug_uart_ignore_placeholder" = "消息必须不包含";
```

说明：Debug UART 页现有 `Auto`、`Manual`、`Stop`、`Clear`、`Share` 在中文环境中也显示英文，因此这里保持一致。

- [ ] **Step 3: 检查新增 key 是否只出现一处**

Run:

```bash
rg -n "debug_uart_contain|debug_uart_ignore" SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: 每个文件各出现 `debug_uart_contain`、`debug_uart_ignore`、`debug_uart_contain_placeholder`、`debug_uart_ignore_placeholder` 一次。

- [ ] **Step 4: 提交文案改动**

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add uart filter labels"
```

## Task 2: 实现双过滤 UI 和过滤逻辑

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: 替换属性声明**

在 `SpaceDebugUARTViewController` 中，将单个 `filterTextField` 和 `filterText` 替换为双过滤控件和状态。

目标代码形态：

```swift
private let containFilterLabel = UILabel()
private let containFilterTextField = UITextField()
private let containFilterClearButton = UIButton(type: .system)
private let ignoreFilterLabel = UILabel()
private let ignoreFilterTextField = UITextField()
private let ignoreFilterClearButton = UIButton(type: .system)
private let tableView = UITableView(frame: .zero, style: .plain)

private var messages: [SpaceDebugUARTMessage] = []
private var scrollMode: UARTScrollMode = .auto
private var isReceivingUARTMessages = false
private var containFilterText = ""
private var ignoreFilterText = ""
```

- [ ] **Step 2: 更新 `visibleMessages` 和 `messageMatchesFilter(_:)`**

将过滤集中到一个函数中：

```swift
private var visibleMessages: [SpaceDebugUARTMessage] {
    return messages.filter { messageMatchesFilter($0) }
}

private func messageMatchesFilter(_ message: SpaceDebugUARTMessage) -> Bool {
    if !containFilterText.isEmpty,
       message.text.range(of: containFilterText, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
        return false
    }

    if !ignoreFilterText.isEmpty,
       message.text.range(of: ignoreFilterText, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
        return false
    }

    return true
}
```

- [ ] **Step 3: 增加过滤控件配置 helper**

在 `setupUI()` 附近增加三个 helper，保持两个输入框配置一致：

```swift
private func configureFilterLabel(_ label: UILabel, text: String) {
    label.text = text
    label.textColor = Title_Color
    label.font = FONTS(SCRXFrom(14))
}

private func configureFilterTextField(_ textField: UITextField, placeholder: String) {
    textField.placeholder = placeholder
    textField.borderStyle = .roundedRect
    textField.clearButtonMode = .never
    textField.keyboardType = .asciiCapable
    textField.returnKeyType = .done
    textField.autocorrectionType = .no
    textField.spellCheckingType = .no
    textField.smartQuotesType = .no
    textField.smartDashesType = .no
    textField.smartInsertDeleteType = .no
    textField.delegate = self
    textField.addTarget(self, action: #selector(filterTextFieldChanged(_:)), for: .editingChanged)
}

private func configureFilterClearButton(_ button: UIButton, action: Selector) {
    button.setTitle("x", for: .normal)
    button.setTitleColor(SubText_Color, for: .normal)
    button.titleLabel?.font = FONTS(SCRXFrom(16))
    button.addTarget(self, action: action, for: .touchUpInside)
}
```

- [ ] **Step 4: 用双过滤控件替换 `setupUI()` 中的单输入框配置**

删除当前 `filterTextField` 的配置、添加和约束逻辑，改为添加 6 个控件：

```swift
configureFilterLabel(containFilterLabel, text: "debug_uart_contain".localizedString)
controlsContainerView.addSubview(containFilterLabel)

configureFilterTextField(containFilterTextField, placeholder: "debug_uart_contain_placeholder".localizedString)
controlsContainerView.addSubview(containFilterTextField)

configureFilterClearButton(containFilterClearButton, action: #selector(clearContainFilterTapped))
controlsContainerView.addSubview(containFilterClearButton)

configureFilterLabel(ignoreFilterLabel, text: "debug_uart_ignore".localizedString)
controlsContainerView.addSubview(ignoreFilterLabel)

configureFilterTextField(ignoreFilterTextField, placeholder: "debug_uart_ignore_placeholder".localizedString)
controlsContainerView.addSubview(ignoreFilterTextField)

configureFilterClearButton(ignoreFilterClearButton, action: #selector(clearIgnoreFilterTapped))
controlsContainerView.addSubview(ignoreFilterClearButton)
```

- [ ] **Step 5: 设置两行过滤 UI 的 SnapKit 约束**

将原 `filterTextField.snp.makeConstraints` 替换为：

```swift
containFilterLabel.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.top.equalTo(modeControl.snp.bottom).offset(SCRYFrom(8))
    make.width.equalTo(SCRXFrom(58))
    make.centerY.equalTo(containFilterTextField)
}

containFilterClearButton.snp.makeConstraints { make in
    make.right.equalTo(SCRXFrom(-16))
    make.centerY.equalTo(containFilterTextField)
    make.width.height.equalTo(SCRXFrom(30))
}

containFilterTextField.snp.makeConstraints { make in
    make.left.equalTo(containFilterLabel.snp.right).offset(SCRXFrom(8))
    make.right.equalTo(containFilterClearButton.snp.left).offset(SCRXFrom(-4))
    make.top.equalTo(modeControl.snp.bottom).offset(SCRYFrom(8))
    make.height.equalTo(SCRYFrom(36))
}

ignoreFilterLabel.snp.makeConstraints { make in
    make.left.equalTo(containFilterLabel)
    make.width.equalTo(containFilterLabel)
    make.centerY.equalTo(ignoreFilterTextField)
}

ignoreFilterClearButton.snp.makeConstraints { make in
    make.right.equalTo(containFilterClearButton)
    make.centerY.equalTo(ignoreFilterTextField)
    make.width.height.equalTo(containFilterClearButton)
}

ignoreFilterTextField.snp.makeConstraints { make in
    make.left.equalTo(containFilterTextField)
    make.right.equalTo(containFilterTextField)
    make.top.equalTo(containFilterTextField.snp.bottom).offset(SCRYFrom(6))
    make.height.equalTo(containFilterTextField)
    make.bottom.equalTo(SCRYFrom(-8))
}
```

- [ ] **Step 6: 替换输入变化处理**

将 `filterTextFieldChanged(_:)` 改为根据 sender 更新对应状态：

```swift
@objc private func filterTextFieldChanged(_ sender: UITextField) {
    let trimmedText = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if sender === containFilterTextField {
        containFilterText = trimmedText
    } else if sender === ignoreFilterTextField {
        ignoreFilterText = trimmedText
    }

    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

- [ ] **Step 7: 增加两个清除 action**

在其他 `@objc` action 附近增加：

```swift
@objc private func clearContainFilterTapped() {
    containFilterTextField.text = ""
    containFilterText = ""
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}

@objc private func clearIgnoreFilterTapped() {
    ignoreFilterTextField.text = ""
    ignoreFilterText = ""
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

- [ ] **Step 8: 确认键盘收起路径仍覆盖控制按钮**

检查以下 action 仍保留 `view.endEditing(true)`：

```swift
@objc private func modeControlChanged(_ sender: UISegmentedControl)
@objc private func receiveButtonTapped()
@objc private func clearButtonTapped()
@objc private func shareButtonTapped()
```

Expected: 点击 Auto、Manual、Stop、Start、Clear、Share 都会收起键盘。两个过滤 `[x]` 不强制收起键盘。

- [ ] **Step 9: 检查旧单过滤属性已清理**

Run:

```bash
rg -n "private let filterTextField|private var filterText\\b|debug_uart_filter_placeholder" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected: `SpaceDebugUARTViewController.swift` 中不再出现旧的 `private let filterTextField` 和 `private var filterText`；strings 文件中旧 `debug_uart_filter_placeholder` 可以保留未使用，避免无关本地化清理。

- [ ] **Step 10: 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: Build Succeeded.

- [ ] **Step 11: 提交 UI 和过滤逻辑改动**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "feat: add uart dual message filters"
```

## Task 3: 最终验证和手动验收

**Files:**
- Verify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
- Verify: `SunSmart/en.lproj/Localizable.strings`
- Verify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 运行最终构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: Build Succeeded.

- [ ] **Step 2: 检查最终 diff**

Run:

```bash
git diff --stat HEAD~2..HEAD
git status --short
```

Expected: 只包含 UART 双过滤相关提交；工作区干净。

- [ ] **Step 3: 执行手动验收**

在真机 Debug UART 页面验证：

```text
1. Contain 输入 abc，只展示包含 abc/ABC/Abc 的消息。
2. Ignore 输入 noise，只展示不包含 noise/NOISE/Noise 的消息。
3. Contain 输入 abc，Ignore 输入 noise，只展示包含 abc 且不包含 noise 的消息。
4. Contain 输入 "  abc  "，效果等同 abc。
5. Contain 输入 "a  b"，中间两个空格保留为匹配内容。
6. 两个输入框都为空时展示全部缓存消息。
7. 点击 Contain 行 [x] 只清除 Contain，不清除 Ignore。
8. 点击 Ignore 行 [x] 只清除 Ignore，不清除 Contain。
9. Contain 为空时，简体中文环境显示 placeholder：消息必须包含。
10. Ignore 为空时，简体中文环境显示 placeholder：消息必须不包含。
11. 英文环境下两个 placeholder 分别显示 Message must contain 和 Message must not contain。
12. Auto 模式下修改过滤条件后滚动到最新可见消息。
13. Manual 模式下修改过滤条件后不主动滚动。
14. 点击 Auto、Manual、Stop、Start、Clear、Share 时键盘收起。
15. Share 导出的 txt 包含全部缓存消息，不受当前过滤条件影响。
16. Clear 清除全部缓存消息，不只清除当前可见消息。
```

- [ ] **Step 4: 如手动验收发现布局过挤，做最小布局修正**

优先调整 `containFilterLabel` 固定宽度或输入框右侧间距，不改变过滤逻辑。修正后重新执行 Step 1 和 Step 3 中相关用例。

- [ ] **Step 5: 提交验证修正**

如果 Step 4 有代码改动：

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "fix: polish uart dual filter layout"
```

如果 Step 4 没有代码改动，不创建空提交。

## 规格覆盖自查

- 双输入框：Task 2 覆盖。
- `Contain text` 必须包含：Task 2 覆盖。
- `Ignore text` 必须不包含：Task 2 覆盖。
- 两者同时配置必须同时满足：Task 2 覆盖。
- 单独配置任一条件只判断该条件：Task 2 覆盖。
- 都不配置不过滤：Task 2 覆盖。
- trim 前后空格、中间空格保留：Task 2 覆盖。
- ASCII 键盘、无联想纠正：Task 2 覆盖。
- 输入框 placeholder：Task 1 和 Task 2 覆盖。
- `[x]` 永远展示并清除当前输入：Task 2 覆盖。
- 只作为 UI 层筛选，缓存和分享导出不受影响：Task 2 保持过滤只作用于 `visibleMessages`，Task 3 手动验收覆盖。
