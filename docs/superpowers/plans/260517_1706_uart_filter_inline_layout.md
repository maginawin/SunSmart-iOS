# UART Filter Inline Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 UART 消息页顶部的 Contain / Ignore 筛选输入框改为同一行并排布局，移除 Label 和外置清除按钮，改用输入框自带清除按钮。

**Architecture:** 本次只修改 `SpaceDebugUARTViewController` 的 UI 组成、约束和输入框清除回调。过滤状态、过滤规则、消息缓存、分享导出、Clear、Auto / Manual 滚动语义保持不变。为避免依赖 `UITextField` 内置清除按钮是否触发 `editingChanged`，新增 `textFieldShouldClear(_:)` 兜底路径，并复用同一套刷新方法。

**Tech Stack:** Swift、UIKit、SnapKit、Xcode workspace `SunSmart.xcworkspace`

---

## 文件结构

- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 删除 Contain / Ignore 的 Label 属性、外置清除按钮属性、配置方法和 action。
  - 保留两个 `UITextField`，调整为同一行等宽布局。
  - 将 `clearButtonMode` 改为 `.always`。
  - 抽取过滤文本更新和列表刷新 helper，供输入变化与内置清除按钮共用。
  - 在 `UITextFieldDelegate` 中实现 `textFieldShouldClear(_:)`，确保点击内置清除按钮后状态和列表同步刷新。
- No change: 本地化 strings、资源、SDK、Pod、Swift Package 配置。

## Task 1: 重排 UART 筛选输入框并切换到内置清除按钮

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1: 记录当前静态检查基线**

Run:

```bash
rg -n "containFilterLabel|ignoreFilterLabel|containFilterClearButton|ignoreFilterClearButton|configureFilterClearButton|clearContainFilterTapped|clearIgnoreFilterTapped|clearButtonMode = \\.never|clearButtonMode = \\.always|textFieldShouldClear" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected:

- 能看到 `containFilterLabel`、`ignoreFilterLabel`、`containFilterClearButton`、`ignoreFilterClearButton`。
- 能看到 `configureFilterClearButton`、`clearContainFilterTapped`、`clearIgnoreFilterTapped`。
- 能看到 `clearButtonMode = .never`。
- 看不到 `clearButtonMode = .always`。
- 看不到 `textFieldShouldClear`。

- [ ] **Step 2: 删除多余 UI 属性**

在 `SpaceDebugUARTViewController` 顶部属性区，把现有筛选控件属性从：

```swift
private let containFilterLabel = UILabel()
private let containFilterTextField = UITextField()
private let containFilterClearButton = UIButton(type: .system)
private let ignoreFilterLabel = UILabel()
private let ignoreFilterTextField = UITextField()
private let ignoreFilterClearButton = UIButton(type: .system)
```

改为：

```swift
private let containFilterTextField = UITextField()
private let ignoreFilterTextField = UITextField()
```

- [ ] **Step 3: 删除 Label 和外置清除按钮的创建与添加**

在 `setupUI()` 中，删除这些代码：

```swift
configureFilterLabel(containFilterLabel, text: "debug_uart_contain".localizedString)
controlsContainerView.addSubview(containFilterLabel)

configureFilterClearButton(containFilterClearButton, action: #selector(clearContainFilterTapped))
controlsContainerView.addSubview(containFilterClearButton)

configureFilterLabel(ignoreFilterLabel, text: "debug_uart_ignore".localizedString)
controlsContainerView.addSubview(ignoreFilterLabel)

configureFilterClearButton(ignoreFilterClearButton, action: #selector(clearIgnoreFilterTapped))
controlsContainerView.addSubview(ignoreFilterClearButton)
```

保留并确认两个输入框仍被配置和添加：

```swift
configureFilterTextField(containFilterTextField, placeholder: "debug_uart_contain_placeholder".localizedString)
controlsContainerView.addSubview(containFilterTextField)

configureFilterTextField(ignoreFilterTextField, placeholder: "debug_uart_ignore_placeholder".localizedString)
controlsContainerView.addSubview(ignoreFilterTextField)
```

- [ ] **Step 4: 替换筛选区约束为并排等宽**

在 `setupUI()` 中，删除旧的 Label、外置清除按钮和上下两行输入框约束：

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

替换为：

```swift
containFilterTextField.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.top.equalTo(modeControl.snp.bottom).offset(SCRYFrom(8))
    make.height.equalTo(SCRYFrom(36))
    make.bottom.equalTo(SCRYFrom(-8))
}

ignoreFilterTextField.snp.makeConstraints { make in
    make.left.equalTo(containFilterTextField.snp.right).offset(SCRXFrom(8))
    make.right.equalTo(SCRXFrom(-16))
    make.top.equalTo(containFilterTextField)
    make.bottom.equalTo(containFilterTextField)
    make.width.equalTo(containFilterTextField)
}
```

Expected:

- 两个输入框同一行。
- 左右边距为 16。
- 中间间隔为 8。
- 两个输入框等宽。
- `controlsContainerView` 底部仍由筛选行 `bottom = -8` 撑开。

- [ ] **Step 5: 改为系统内置清除按钮**

在 `configureFilterTextField(_:placeholder:)` 中，把：

```swift
textField.clearButtonMode = .never
```

改为：

```swift
textField.clearButtonMode = .always
```

- [ ] **Step 6: 删除不再使用的外置按钮配置方法**

删除整个方法：

```swift
private func configureFilterLabel(_ label: UILabel, text: String) {
    label.text = text
    label.textColor = Title_Color
    label.font = FONTS(SCRXFrom(14))
}

private func configureFilterClearButton(_ button: UIButton, action: Selector) {
    button.setTitle(nil, for: .normal)
    button.setImage(UIImage(systemName: "xmark"), for: .normal)
    button.tintColor = SubText_Color
    button.imageView?.contentMode = .scaleAspectFit
    button.addTarget(self, action: action, for: .touchUpInside)
}
```

- [ ] **Step 7: 抽取过滤文本更新与列表刷新 helper**

在 `filterTextFieldChanged(_:)` 前添加：

```swift
private func updateFilterText(from textField: UITextField) {
    let trimmedText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if textField === containFilterTextField {
        containFilterText = trimmedText
    } else if textField === ignoreFilterTextField {
        ignoreFilterText = trimmedText
    }
}

private func refreshMessagesAfterFilterChange() {
    rebuildDisplayMessages()
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

把 `filterTextFieldChanged(_:)` 从：

```swift
@objc private func filterTextFieldChanged(_ sender: UITextField) {
    let trimmedText = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if sender === containFilterTextField {
        containFilterText = trimmedText
    } else if sender === ignoreFilterTextField {
        ignoreFilterText = trimmedText
    }

    rebuildDisplayMessages()
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

改为：

```swift
@objc private func filterTextFieldChanged(_ sender: UITextField) {
    updateFilterText(from: sender)
    refreshMessagesAfterFilterChange()
}
```

- [ ] **Step 8: 删除外置清除按钮 action**

删除整个方法：

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

- [ ] **Step 9: 增加内置清除按钮兜底回调**

在 `UITextFieldDelegate` extension 中，把现有内容从：

```swift
extension SpaceDebugUARTViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
```

改为：

```swift
extension SpaceDebugUARTViewController: UITextFieldDelegate {
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        textField.text = ""
        updateFilterText(from: textField)
        refreshMessagesAfterFilterChange()
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
```

Rationale:

- 返回 `false`，因为方法内部已经手动清空文本并刷新过滤状态。
- 避免 UIKit 默认清空流程再触发一次刷新，降低重复 reload 风险。

- [ ] **Step 10: 运行静态检查确认旧 UI 元素已移除**

Run:

```bash
rg -n "containFilterLabel|ignoreFilterLabel|containFilterClearButton|ignoreFilterClearButton|configureFilterLabel|configureFilterClearButton|clearContainFilterTapped|clearIgnoreFilterTapped|clearButtonMode = \\.never|clearButtonMode = \\.always|textFieldShouldClear|SCRXFrom\\(8\\)" SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
```

Expected:

- 不出现 `containFilterLabel`。
- 不出现 `ignoreFilterLabel`。
- 不出现 `containFilterClearButton`。
- 不出现 `ignoreFilterClearButton`。
- 不出现 `configureFilterLabel`。
- 不出现 `configureFilterClearButton`。
- 不出现 `clearContainFilterTapped`。
- 不出现 `clearIgnoreFilterTapped`。
- 不出现 `clearButtonMode = .never`。
- 出现 `clearButtonMode = .always`。
- 出现 `textFieldShouldClear`。
- 出现输入框中间间隔 `SCRXFrom(8)`。

- [ ] **Step 11: 运行格式与编译检查**

Run:

```bash
git diff --check
```

Expected:

- 无输出，退出码为 0。

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > /tmp/sun-smart-uart-filter-inline-layout.log 2>&1
```

Expected:

- 日志末尾包含 `** BUILD SUCCEEDED **`。

如果沙箱内出现 `CoreSimulatorService`、`Operation not permitted` 或 workspace 误报，使用相同命令申请提权后重跑，不要改用 `SunSmart.xcodeproj` 结果替代 workspace 验证。

- [ ] **Step 12: 手动验证清单**

在 App 中打开 UART 消息页，验证：

- 页面不再显示 `Contain` 与 `Ignore` Label。
- 两个筛选输入框显示在同一行。
- 两个输入框左右边距与顶部控制区一致。
- 两个输入框中间间隔约为 8。
- 两个输入框为空时也显示系统清除按钮。
- Contain 输入后，列表只显示包含该文本的消息。
- Ignore 输入后，列表排除包含该文本的消息。
- 同时输入 Contain 与 Ignore 时，列表同时满足包含和排除条件。
- 点击 Contain 输入框内置清除按钮只清空 Contain，并刷新列表。
- 点击 Ignore 输入框内置清除按钮只清空 Ignore，并刷新列表。
- Auto 模式下过滤变化后滚动到最新可见消息。
- Manual 模式下过滤变化后不主动滚动。
- Share 导出仍包含全部缓存消息。
- Clear 仍清除全部缓存消息。

- [ ] **Step 13: 提交代码变更**

Run:

```bash
git status --short
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "style: simplify uart filter layout"
```

Expected:

- commit 只包含 `SpaceDebugUARTViewController.swift`。
- commit message 不包含 codex 相关内容。

## 自审记录

- 规格覆盖：
  - 移除 Label：Task 1 Step 2、Step 3、Step 6、Step 10。
  - 移除外置清除按钮：Task 1 Step 2、Step 3、Step 6、Step 8、Step 10。
  - 两输入框同一行、等宽、左右 16、中间 8：Task 1 Step 4、Step 10、Step 12。
  - 内置清除按钮一直展示：Task 1 Step 5、Step 9、Step 12。
  - 保持过滤和滚动语义：Task 1 Step 7、Step 9、Step 12。
  - 构建验证：Task 1 Step 11。
- 占位检查：无占位词、无未决问题、无延后实现类步骤。
- 类型一致性：计划中使用的属性和方法名均来自当前 `SpaceDebugUARTViewController.swift` 或在本计划中新增定义。
