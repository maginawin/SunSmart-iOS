# UART Debug 页面展示优化实施计划

> **给执行代理的要求：** 使用 `superpowers:executing-plans` 按任务逐项执行。本计划使用 checkbox 语法跟踪进度，每个任务完成并验证后提交一次。

**目标：** 优化 UART 消息页面的展示密度、时间显示、自动滚动、暂停接收、清除消息和文本过滤能力。

**架构：** 不修改 SDK 和设备协议，只在 SunSmart App 的 UART 页面维护页面状态。`SpaceDebugUARTViewController` 负责控制区、接收状态、过滤和滚动；`SpaceDebugUARTMessageCell` 负责单条消息的紧凑展示和 Datetime 格式。

**技术栈：** UIKit、SnapKit、现有 `DebugBluetoothSession`、现有 `SRAlertView`、现有本地化字符串。

---

## 文件结构

- 修改：`SunSmart/Main/Space/Debug/SpaceDebugUARTMessageCell.swift`
  - 调整 Datetime 格式、圆角、行内间距。
  - `update` 方法改为每条消息都显示时间。
- 修改：`SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 新增顶部控制区。
  - 新增 `Auto / Manual`、`Stop / Start`、`Clear`、文本过滤状态。
  - 列表数据源改为使用过滤后的可见消息。
- 修改：`SunSmart/en.lproj/Localizable.strings`
  - 增加英文控制区和清除确认文案。
- 修改：`SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加中文控制区和清除确认文案。

---

## Task 1：调整 UART 消息 Cell 展示

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTMessageCell.swift`

- [ ] **Step 1：更新 DateFormatter**

将 `dateFormatter` 改为固定 Debug 格式：

```swift
private static let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return dateFormatter
}()
```

- [ ] **Step 2：调整 update 方法**

将方法签名从：

```swift
func update(message: SpaceDebugUARTMessage, showTimestamp: Bool)
```

改为：

```swift
func update(message: SpaceDebugUARTMessage) {
    timestampLabel.isHidden = false
    timestampLabel.text = Self.dateFormatter.string(from: message.timestamp)
    bubbleLabel.text = message.text
}
```

- [ ] **Step 3：压缩行内间距并调整圆角**

在 `setupUI()` 中调整约束和圆角：

```swift
timestampLabel.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.right.lessThanOrEqualTo(SCRXFrom(-16))
    make.top.equalTo(SCRYFrom(4))
}

bubbleView.layer.cornerRadius = SCRXFrom(9)

bubbleView.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.top.equalTo(timestampLabel.snp.bottom).offset(SCRYFrom(2))
    make.width.lessThanOrEqualToSuperview().multipliedBy(0.72)
    make.bottom.equalTo(SCRYFrom(-4))
}
```

- [ ] **Step 4：提交**

运行：

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTMessageCell.swift
git commit -m "feat: compact debug uart message cells"
```

---

## Task 2：新增 UART 页面控制区和页面状态

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1：新增状态和控件属性**

在 `SpaceDebugUARTViewController` 内增加：

```swift
private enum UARTScrollMode {
    case auto
    case manual
}

private let controlsContainerView = UIView()
private let modeControl = UISegmentedControl(items: [
    "debug_uart_auto".localizedString,
    "debug_uart_manual".localizedString
])
private let receiveButton = UIButton(type: .system)
private let clearButton = UIButton(type: .system)
private let filterTextField = UITextField()

private var messages: [SpaceDebugUARTMessage] = []
private var scrollMode: UARTScrollMode = .auto
private var isReceivingUARTMessages = false
private var filterText = ""

private var visibleMessages: [SpaceDebugUARTMessage] {
    guard !filterText.isEmpty else {
        return messages
    }
    return messages.filter { message in
        message.text.range(of: filterText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
```

删除旧的：

```swift
private var didStartMessages = false
```

- [ ] **Step 2：调整 viewDidLoad 和 setupUI**

`viewDidLoad()` 保持 `setupUI()` 后调用 `startMessages()`。

将 `tableView` 初始化从 `.grouped` 改为 `.plain`，减少默认 header/footer 空白：

```swift
private let tableView = UITableView(frame: .zero, style: .plain)
```

`setupUI()` 内新增控制区配置：

```swift
controlsContainerView.backgroundColor = Background_Color
view.addSubview(controlsContainerView)
controlsContainerView.snp.makeConstraints { make in
    make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
    make.left.right.equalToSuperview()
}

modeControl.selectedSegmentIndex = 0
modeControl.addTarget(self, action: #selector(modeControlChanged(_:)), for: .valueChanged)
controlsContainerView.addSubview(modeControl)

receiveButton.setTitle("debug_uart_stop".localizedString, for: .normal)
receiveButton.addTarget(self, action: #selector(receiveButtonTapped), for: .touchUpInside)
controlsContainerView.addSubview(receiveButton)

clearButton.setTitle("debug_uart_clear".localizedString, for: .normal)
clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
controlsContainerView.addSubview(clearButton)

filterTextField.placeholder = "debug_uart_filter_placeholder".localizedString
filterTextField.borderStyle = .roundedRect
filterTextField.clearButtonMode = .whileEditing
filterTextField.returnKeyType = .done
filterTextField.delegate = self
filterTextField.addTarget(self, action: #selector(filterTextFieldChanged(_:)), for: .editingChanged)
controlsContainerView.addSubview(filterTextField)
```

控制区布局使用两行：

```swift
modeControl.snp.makeConstraints { make in
    make.top.equalTo(SCRYFrom(8))
    make.left.equalTo(SCRXFrom(16))
}

clearButton.snp.makeConstraints { make in
    make.centerY.equalTo(modeControl)
    make.right.equalTo(SCRXFrom(-16))
}

receiveButton.snp.makeConstraints { make in
    make.centerY.equalTo(modeControl)
    make.right.equalTo(clearButton.snp.left).offset(SCRXFrom(-12))
}

filterTextField.snp.makeConstraints { make in
    make.top.equalTo(modeControl.snp.bottom).offset(SCRYFrom(8))
    make.left.equalTo(SCRXFrom(16))
    make.right.equalTo(SCRXFrom(-16))
    make.height.equalTo(SCRYFrom(36))
    make.bottom.equalTo(SCRYFrom(-8))
}
```

table 约束改为位于控制区下方：

```swift
view.addSubview(tableView)
tableView.snp.makeConstraints { make in
    make.top.equalTo(controlsContainerView.snp.bottom)
    make.left.right.bottom.equalToSuperview()
}
```

table 配置改为更紧凑：

```swift
tableView.estimatedRowHeight = SCRYFrom(48)
tableView.contentInset = UIEdgeInsets(top: SCRYFrom(4), left: 0, bottom: SCRYFrom(8), right: 0)
```

- [ ] **Step 3：实现接收状态切换**

替换 `startMessages()`：

```swift
private func startMessages() {
    guard !isReceivingUARTMessages else {
        return
    }
    isReceivingUARTMessages = true
    updateReceiveButton()

    session.startUARTMessages(onMessage: { [weak self] message in
        guard let self = self, self.isReceivingUARTMessages else {
            return
        }
        let shouldScroll = self.scrollMode == .auto && self.messageMatchesFilter(message)
        self.messages.append(message)
        self.tableView.reloadData()
        if shouldScroll {
            self.scrollToLatestVisibleMessage(animated: true)
        }
    }, completion: { [weak self] state in
        guard let self = self else {
            return
        }
        if case .supported = state {
            return
        }
        self.isReceivingUARTMessages = false
        self.updateReceiveButton()
        self.showUARTUnavailableAlert(state: state)
    })
}
```

新增：

```swift
private func stopMessages() {
    guard isReceivingUARTMessages else {
        return
    }
    isReceivingUARTMessages = false
    session.stopUARTMessages()
    updateReceiveButton()
}

private func updateReceiveButton() {
    let title = isReceivingUARTMessages ? "debug_uart_stop".localizedString : "debug_uart_start".localizedString
    receiveButton.setTitle(title, for: .normal)
}

@objc private func receiveButtonTapped() {
    if isReceivingUARTMessages {
        stopMessages()
    } else {
        startMessages()
    }
}
```

- [ ] **Step 4：实现 Auto / Manual**

新增：

```swift
@objc private func modeControlChanged(_ sender: UISegmentedControl) {
    scrollMode = sender.selectedSegmentIndex == 0 ? .auto : .manual
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: true)
    }
}
```

替换旧的 `scrollToLatestMessage()` 为：

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

删除旧的 `shouldShowTimestamp(at:)`。

- [ ] **Step 5：实现文本过滤**

新增：

```swift
@objc private func filterTextFieldChanged(_ sender: UITextField) {
    filterText = sender.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    tableView.reloadData()
    if scrollMode == .auto {
        scrollToLatestVisibleMessage(animated: false)
    }
}

private func messageMatchesFilter(_ message: SpaceDebugUARTMessage) -> Bool {
    guard !filterText.isEmpty else {
        return true
    }
    return message.text.range(of: filterText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
}
```

增加 `UITextFieldDelegate`：

```swift
extension SpaceDebugUARTViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
```

- [ ] **Step 6：实现 Clear 确认**

新增：

```swift
@objc private func clearButtonTapped() {
    SRAlertView(title: "debug_uart_clear".localizedString, message: "debug_uart_clear_message".localizedString, actions: [
        .cancelAction,
        SRAlertAction(title: "debug_uart_clear".localizedString, actionHandler: { [weak self] _ in
            self?.clearMessages()
        })
    ]).show()
}

private func clearMessages() {
    messages.removeAll()
    tableView.reloadData()
}
```

- [ ] **Step 7：调整 DataSource**

`numberOfRowsInSection` 改用 `visibleMessages.count`。

`cellForRowAt` 改用：

```swift
let message = visibleMessages[indexPath.row]
cell.update(message: message)
```

删除 `titleForHeaderInSection` 方法，减少列表上方空白。

- [ ] **Step 8：调整生命周期停止逻辑**

`viewDidDisappear` 和 `deinit` 中仍调用 `session.stopUARTMessages()`，但同时保持 `isReceivingUARTMessages = false`，避免页面退出后状态误用：

```swift
isReceivingUARTMessages = false
session.stopUARTMessages()
```

- [ ] **Step 9：提交**

运行：

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "feat: add debug uart view controls"
```

---

## Task 3：新增本地化文案

**Files:**
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1：新增英文文案**

在现有 `debug_uart_*` 附近追加：

```text
"debug_uart_auto" = "Auto";
"debug_uart_manual" = "Manual";
"debug_uart_stop" = "Stop";
"debug_uart_start" = "Start";
"debug_uart_clear" = "Clear";
"debug_uart_filter_placeholder" = "Filter messages";
"debug_uart_clear_message" = "Clear cached UART messages?";
```

- [ ] **Step 2：新增中文文案**

在现有 `debug_uart_*` 附近追加：

```text
"debug_uart_auto" = "Auto";
"debug_uart_manual" = "Manual";
"debug_uart_stop" = "Stop";
"debug_uart_start" = "Start";
"debug_uart_clear" = "Clear";
"debug_uart_filter_placeholder" = "Filter messages";
"debug_uart_clear_message" = "是否清除已缓存的 UART 消息？";
```

说明：按钮和输入框按规格 UI 文案使用英文；确认消息使用中文本地化。

- [ ] **Step 3：检查 strings 语法**

运行：

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

预期：两个文件都输出 `OK`。

- [ ] **Step 4：提交**

运行：

```bash
git add SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add debug uart control strings"
```

---

## Task 4：构建验证

**Files:**
- Verify only

- [ ] **Step 1：检查工作区状态**

运行：

```bash
git status --short
```

预期：只有本任务无关的既有未跟踪文档，或工作区干净。

- [ ] **Step 2：构建 SunSmart**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 3：构建 Archipelago**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 4：构建 SylSmart**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 5：构建 SLG Sync Plus**

运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 6：手动真机验证清单**

在支持 UART 的设备上验证：

- 默认进入 UART 页面为 `Auto`，收到新消息后滚动到底部。
- 每条消息显示 `yyyy-MM-dd HH:mm:ss.SSS`。
- 消息气泡圆角明显小于旧版，消息之间间距约为 `8`。
- 切换 `Manual` 后，新消息继续进入列表但不自动滚动。
- 切回 `Auto` 后滚动到最新可见消息。
- 点击 `Stop` 后按钮变 `Start`，新消息不保存、不展示。
- 点击 `Start` 后按钮变 `Stop`，继续接收恢复之后的新消息。
- 点击 `Clear` 后选择 `Cancel`，消息不清除。
- 点击 `Clear` 后选择 `Clear`，已缓存消息清空。
- `Clear` 后接收状态、过滤文本、Auto/Manual 模式保持不变。
- 输入过滤文本，列表只显示包含该文本的消息。
- 过滤忽略大小写，忽略输入前后空格，保留输入中间空格。

- [ ] **Step 7：提交验证记录**

如果构建或手动验证过程中需要修正代码，修正后单独提交：

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift SunSmart/Main/Space/Debug/SpaceDebugUARTMessageCell.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: polish debug uart view controls"
```

如果没有代码修正，不需要提交。

---

## 自检

- 规格覆盖：已覆盖间距、Datetime、圆角、Auto/Manual、Stop/Start、Clear、文本过滤。
- 作用范围：仅涉及 UART 页面和本地化文案，不改 SDK，不改 target 配置。
- 风险点：`Stop` 依赖 SDK 停止 notification；设备端仍可能继续发送，但 App 不保存、不展示 Stop 期间消息。
- 验证策略：本地化语法检查，加四个品牌 target 的 iOS Debug 构建，最后做真机 UART 手动验证。
