# UART 消息页功能增强实施计划

> **给 agentic workers：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐项执行。步骤使用 checkbox（`- [ ]`）语法跟踪。

**目标：** 增强 UART 消息页，使其支持页面常亮、断线接管与重连、设备 Debug 会话级消息缓存、缓存裁剪和完整 txt 分享导出。

**架构：** `DebugBluetoothSession` 持有 UART 缓存、dropped 计数和接收状态，生命周期跟随设备 Debug 会话。`SpaceDebugUARTViewController` 读取 session 缓存并负责 UI、筛选、常亮、断线弹窗、重连和分享入口；导出文本和文件名由独立 helper 生成，避免页面控制器继续膨胀。

**Tech Stack：** Swift、UIKit、SnapKit、NordicSigMeshSDK、`UIActivityViewController`、`FileManager.default.temporaryDirectory`。

---

## 文件结构

- 修改：`SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`
  - 增加 UART 消息缓存、dropped 计数、裁剪逻辑、清空逻辑、会话级 Start/Stop 行为。
- 修改：`SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
  - 增加导出上下文模型 `SpaceDebugUARTLogExportContext`。
- 新增：`SunSmart/Main/Space/Debug/SpaceDebugUARTLogExporter.swift`
  - 负责生成 txt 内容、清理文件名、生成导出文件 URL。
- 修改：`SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`
  - 打开 UART 页面时传入 `space` 和 `item`，并让上级断线处理可被 UART 页面临时接管后恢复。
- 修改：`SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 使用 session 缓存，增加常亮、断线弹窗、重连、分享按钮、退出页面停止接收但不清缓存。
- 修改：`SunSmart/en.lproj/Localizable.strings`
  - 增加分享、导出、重连失败等文案。
- 修改：`SunSmart/zh-Hans.lproj/Localizable.strings`
  - 同步新增文案；UI 控件显示英文的保持英文。

---

## Task 1：把 UART 缓存上移到 DebugBluetoothSession

**Files:**
- Modify: `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`

- [ ] **Step 1：增加缓存常量和状态**

在 `DebugBluetoothSession` 的属性区增加：

```swift
private let uartMessageTrimThreshold = 100_000
private let uartMessageTrimTarget = 80_000
private var uartMessageHandler: ((SpaceDebugUARTMessage) -> Void)?

private(set) var uartMessages: [SpaceDebugUARTMessage] = []
private(set) var droppedUARTMessageCount = 0
private(set) var isReceivingUARTMessages = false
```

- [ ] **Step 2：增加缓存操作方法**

在 `DebugBluetoothSession` 中增加：

```swift
func cachedUARTMessages() -> [SpaceDebugUARTMessage] {
    return uartMessages
}

func clearUARTMessages() {
    uartMessages.removeAll()
    droppedUARTMessageCount = 0
}

private func appendUARTMessage(_ message: SpaceDebugUARTMessage) {
    uartMessages.append(message)
    trimUARTMessagesIfNeeded()
    uartMessageHandler?(message)
}

private func trimUARTMessagesIfNeeded() {
    guard uartMessages.count > uartMessageTrimThreshold else {
        return
    }
    let removeCount = uartMessages.count - uartMessageTrimTarget
    uartMessages.removeFirst(removeCount)
    droppedUARTMessageCount += removeCount
}
```

- [ ] **Step 3：改造 startUARTMessages**

把现有 `startUARTMessages(onMessage:completion:)` 调整为 session 内部先写缓存，再回调当前页面：

```swift
func startUARTMessages(
    onMessage: @escaping (SpaceDebugUARTMessage) -> Void,
    completion: @escaping (SpaceDebugUARTSupportViewState) -> Void
) {
    guard let proxy = MeshLibManager.manager.currentProxy else {
        completion(.disconnected)
        return
    }
    uartMessageHandler = onMessage
    isReceivingUARTMessages = true
    proxy.startDebugUARTMessages(onMessage: { [weak self] message in
        DispatchQueue.main.async {
            guard let self = self, self.isReceivingUARTMessages else {
                return
            }
            let viewMessage = SpaceDebugUARTMessage(text: message.text, timestamp: message.timestamp)
            self.appendUARTMessage(viewMessage)
        }
    }, completion: { [weak self] state in
        DispatchQueue.main.async {
            guard let self = self else {
                completion(Self.mapUARTState(state))
                return
            }
            let mappedState = Self.mapUARTState(state)
            if case .supported = mappedState {
                self.isReceivingUARTMessages = true
            } else {
                self.isReceivingUARTMessages = false
                self.uartMessageHandler = nil
            }
            completion(mappedState)
        }
    })
}
```

- [ ] **Step 4：改造 stop 和 finish**

把 `stopUARTMessages()` 改成停止接收但不清缓存：

```swift
func stopUARTMessages() {
    isReceivingUARTMessages = false
    uartMessageHandler = nil
    MeshLibManager.manager.currentProxy?.stopDebugUARTMessages()
}
```

在 `finish()` 中 `stopUARTMessages()` 后追加：

```swift
clearUARTMessages()
```

- [ ] **Step 5：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6：提交**

```bash
git add SunSmart/Main/Space/Debug/DebugBluetoothSession.swift
git commit -m "feat: cache debug uart messages in session"
```

---

## Task 2：新增 UART 日志导出模型和 formatter

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
- Create: `SunSmart/Main/Space/Debug/SpaceDebugUARTLogExporter.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1：新增导出上下文模型**

在 `SpaceDebugModels.swift` 末尾增加：

```swift
struct SpaceDebugUARTLogExportContext {
    let siteName: String
    let spaceName: String
    let groupName: String?
    let deviceName: String
    let macAddress: String
    let companyID: String
    let productID: String
    let address: String
    let versionIdentifier: String
    let model: String
    let deviceType: String
    let firmwareVersion: String
    let droppedMessageCount: Int
    let generatedAt: Date
}
```

- [ ] **Step 2：创建 exporter 文件**

创建 `SpaceDebugUARTLogExporter.swift`：

```swift
//
//  SpaceDebugUARTLogExporter.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import Foundation

enum SpaceDebugUARTLogExporter {
    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMddHHmmss"
        return formatter
    }()

    static func makeLogText(context: SpaceDebugUARTLogExportContext, messages: [SpaceDebugUARTMessage]) -> String {
        var lines: [String] = [
            "UART Debug Log",
            "",
            "Site Name: \(context.siteName)",
            "Space Name: \(context.spaceName)",
            "Group Name: \(context.groupName ?? "")",
            "Device Name: \(context.deviceName)",
            "MAC Address: \(context.macAddress)",
            "Company ID: \(context.companyID)",
            "Product ID: \(context.productID)",
            "Address: \(context.address)",
            "Version Identifier: \(context.versionIdentifier)",
            "Model: \(context.model)",
            "Device Type: \(context.deviceType)",
            "Firmware Version: \(context.firmwareVersion)",
            "Dropped Messages: \(context.droppedMessageCount)",
            "Generated At: \(logDateFormatter.string(from: context.generatedAt))",
            "",
            "Messages:"
        ]

        messages.forEach { message in
            lines.append("[\(logDateFormatter.string(from: message.timestamp))] \(message.text)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func makeFileURL(context: SpaceDebugUARTLogExportContext, messages: [SpaceDebugUARTMessage]) throws -> URL {
        let fileName = makeFileName(context: context)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let text = makeLogText(context: context, messages: messages)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static func makeFileName(context: SpaceDebugUARTLogExportContext) -> String {
        var components = [
            context.siteName,
            context.spaceName,
            context.groupName ?? "",
            context.deviceName,
            "uart",
            fileDateFormatter.string(from: context.generatedAt)
        ].compactMap { sanitizedFileNameComponent($0) }.filter { !$0.isEmpty }

        if components.isEmpty {
            components = ["uart-log", fileDateFormatter.string(from: context.generatedAt)]
        }

        return components.joined(separator: "-") + ".txt"
    }

    private static func sanitizedFileNameComponent(_ component: String) -> String? {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let invalidCharacters = CharacterSet(charactersIn: "/\\\\:*?\"<>|").union(.newlines)
        let cleaned = trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}
```

- [ ] **Step 3：构建验证**

在 `SunSmart.xcodeproj/project.pbxproj` 中把 `SpaceDebugUARTLogExporter.swift` 加入 Debug 分组和四个 App target 的 Sources。沿用现有 `SpaceDebugUARTViewController.swift` 与 `SpaceDebugUARTMessageCell.swift` 附近的 PBX 结构，新增文件引用和四个 build file：

```text
C8260516000001010000000A /* SpaceDebugUARTLogExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000B /* SpaceDebugUARTLogExporter.swift */; };
C8260516000001020000000A /* SpaceDebugUARTLogExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000B /* SpaceDebugUARTLogExporter.swift */; };
C8260516000001030000000A /* SpaceDebugUARTLogExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000B /* SpaceDebugUARTLogExporter.swift */; };
C8260516000001040000000A /* SpaceDebugUARTLogExporter.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000B /* SpaceDebugUARTLogExporter.swift */; };
C8260516000000010000000B /* SpaceDebugUARTLogExporter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpaceDebugUARTLogExporter.swift; sourceTree = "<group>"; };
```

在 Debug group 的 children 中追加：

```text
C8260516000000010000000B /* SpaceDebugUARTLogExporter.swift */,
```

在四个 Sources build phase 中分别追加对应 build file：

```text
C8260516000001010000000A /* SpaceDebugUARTLogExporter.swift in Sources */,
C8260516000001020000000A /* SpaceDebugUARTLogExporter.swift in Sources */,
C8260516000001030000000A /* SpaceDebugUARTLogExporter.swift in Sources */,
C8260516000001040000000A /* SpaceDebugUARTLogExporter.swift in Sources */,
```

- [ ] **Step 4：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5：提交**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugModels.swift SunSmart/Main/Space/Debug/SpaceDebugUARTLogExporter.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add debug uart log exporter"
```

---

## Task 3：调整设备页打开 UART 的参数和断线处理边界

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`

- [ ] **Step 1：保存 space**

在属性区增加：

```swift
private let space: SpaceData
```

把 init 改成：

```swift
init(session: DebugBluetoothSession, space: SpaceData, item: SpaceDebugNodeItem) {
    self.session = session
    self.space = space
    self.item = item
    super.init(nibName: nil, bundle: nil)
}
```

- [ ] **Step 2：调整调用方**

在 `SpaceDebugViewController.connect(_:)` 中把设备页初始化改为：

```swift
let detail = SpaceDebugDeviceViewController(session: self.session, space: self.space, item: item)
```

- [ ] **Step 3：提取上级断线处理安装方法**

在 `SpaceDebugDeviceViewController` 中增加：

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    installDisconnectHandler()
}

private func installDisconnectHandler() {
    session.onUnexpectedDisconnect = { [weak self] node in
        guard let self = self, node.primaryUnicastAddress == self.item.node.primaryUnicastAddress else {
            return
        }
        self.connectionState = .disconnected
        self.uartState = .disconnected
        self.render()
        self.showDisconnectedAlert()
    }
}
```

删除 `viewDidLoad()` 中直接设置 `session.onUnexpectedDisconnect = ...` 的旧代码块，避免 UART 页面返回后无法恢复。

- [ ] **Step 4：打开 UART 页面时传入上下文**

在 `openUARTAction()` 中改为：

```swift
let controller = SpaceDebugUARTViewController(session: session, space: space, item: item)
navigationController?.pushViewController(controller, animated: true)
```

- [ ] **Step 5：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6：提交**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugViewController.swift SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift
git commit -m "feat: pass debug uart export context"
```

---

## Task 4：UART 页面使用 session 缓存并接管断线/常亮

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`

- [ ] **Step 1：增加上下文和状态属性**

在属性区增加：

```swift
private let space: SpaceData
private let item: SpaceDebugNodeItem
private var previousIdleTimerDisabled = false
private var isShowingDisconnectAlert = false
private var shouldResumeReceivingAfterReconnect = false
```

把 init 改成：

```swift
init(session: DebugBluetoothSession, space: SpaceData, item: SpaceDebugNodeItem) {
    self.session = session
    self.space = space
    self.item = item
    super.init(nibName: nil, bundle: nil)
}
```

- [ ] **Step 2：从 session 初始化缓存**

把页面内 `messages` 初始化保留为空，但在 `viewDidLoad()` 的 `setupUI()` 后、`startMessages()` 前增加：

```swift
messages = session.cachedUARTMessages()
tableView.reloadData()
```

- [ ] **Step 3：增加常亮生命周期**

新增：

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    installDisconnectHandler()
}
```

在 `viewDidDisappear(_:)` 的退出分支中、`session.stopUARTMessages()` 后增加：

```swift
UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
```

同时保留退出 UART 页面停止接收、不清缓存的行为。

- [ ] **Step 4：接入 session 缓存回调**

在 `startMessages()` 的 onMessage 中，避免重复 append，因为 session 已经先写缓存；页面只同步 session 缓存并刷新：

```swift
let shouldScroll = self.scrollMode == .auto && self.messageMatchesFilter(message)
self.messages = self.session.cachedUARTMessages()
self.tableView.reloadData()
if shouldScroll {
    self.scrollToLatestVisibleMessage(animated: true)
}
```

在 `stopMessages()` 中保持：

```swift
isReceivingUARTMessages = false
session.stopUARTMessages()
updateReceiveButton()
```

在 `clearMessages()` 中改为：

```swift
session.clearUARTMessages()
messages = []
tableView.reloadData()
```

- [ ] **Step 5：实现 UART 页面断线弹窗**

新增：

```swift
private func installDisconnectHandler() {
    session.onUnexpectedDisconnect = { [weak self] node in
        guard let self = self, node.primaryUnicastAddress == self.item.node.primaryUnicastAddress else {
            return
        }
        self.handleUnexpectedDisconnect()
    }
}

private func handleUnexpectedDisconnect() {
    shouldResumeReceivingAfterReconnect = isReceivingUARTMessages
    isReceivingUARTMessages = false
    session.stopUARTMessages()
    updateReceiveButton()
    showDisconnectedAlert()
}

private func showDisconnectedAlert() {
    guard !isShowingDisconnectAlert else {
        return
    }
    isShowingDisconnectAlert = true
    SRAlertView(title: "notification".localizedString, message: "debug_connection_disconnected_message".localizedString, actions: [
        SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { [weak self] _ in
            self?.isShowingDisconnectAlert = false
        }),
        SRAlertAction(title: "debug_reconnect".localizedString, actionHandler: { [weak self] _ in
            self?.isShowingDisconnectAlert = false
            self?.reconnect()
        })
    ]).show()
}

private func reconnect() {
    session.reconnect { [weak self] success in
        guard let self = self else {
            return
        }
        if success {
            if self.shouldResumeReceivingAfterReconnect {
                self.startMessages()
            }
        } else {
            self.showReconnectFailedAlert()
        }
    }
}

private func showReconnectFailedAlert() {
    guard !isShowingDisconnectAlert else {
        return
    }
    isShowingDisconnectAlert = true
    SRAlertView(title: "failed".localizedString, message: "debug_reconnect_failed_message".localizedString, actions: [
        SRAlertAction(title: "alert_item_cancel".localizedString, style: .cancel, actionHandler: { [weak self] _ in
            self?.isShowingDisconnectAlert = false
        }),
        SRAlertAction(title: "debug_reconnect".localizedString, actionHandler: { [weak self] _ in
            self?.isShowingDisconnectAlert = false
            self?.reconnect()
        })
    ]).show()
}
```

- [ ] **Step 6：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7：提交**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift
git commit -m "feat: manage debug uart page lifecycle"
```

---

## Task 5：增加分享按钮和导出文件

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1：新增本地化文案**

在 `SunSmart/en.lproj/Localizable.strings` 的 `debug_uart_*` 附近增加：

```text
"debug_uart_share" = "Share";
"debug_reconnect_failed_message" = "Re-connect failed.";
"debug_uart_export_failed_message" = "Failed to export UART log.";
```

在 `SunSmart/zh-Hans.lproj/Localizable.strings` 的 `debug_uart_*` 附近增加：

```text
"debug_uart_share" = "Share";
"debug_reconnect_failed_message" = "重新连接失败。";
"debug_uart_export_failed_message" = "导出 UART 日志失败。";
```

- [ ] **Step 2：增加导航栏分享按钮**

在 `viewDidLoad()` 设置 title 后增加：

```swift
navigationItem.rightBarButtonItem = UIBarButtonItem(
    title: "debug_uart_share".localizedString,
    style: .plain,
    target: self,
    action: #selector(shareButtonTapped)
)
```

- [ ] **Step 3：生成导出上下文**

在 `SpaceDebugUARTViewController` 中增加：

```swift
private func makeExportContext() -> SpaceDebugUARTLogExportContext {
    let siteName = SiteData.load(siteId: space.siteId)?.name ?? "--"
    let node = item.node
    return SpaceDebugUARTLogExportContext(
        siteName: siteName,
        spaceName: space.name,
        groupName: item.groupName,
        deviceName: item.nodeName,
        macAddress: node.macAddressResult ?? node.macAddress ?? "--",
        companyID: node.companyIdentifier.map { String(format: "0x%04X", $0) } ?? "--",
        productID: node.productIdentifier.map { String(format: "0x%04X", $0) } ?? "--",
        address: "\(node.primaryUnicastAddress)",
        versionIdentifier: "\(node.versionSEQ)",
        model: node.modelName ?? "--",
        deviceType: item.category.title,
        firmwareVersion: node.firmwareVersion ?? node.distributionVersion ?? "--",
        droppedMessageCount: session.droppedUARTMessageCount,
        generatedAt: Date()
    )
}
```

- [ ] **Step 4：实现分享动作**

在 `SpaceDebugUARTViewController` 中增加：

```swift
@objc private func shareButtonTapped() {
    view.endEditing(true)
    if isReceivingUARTMessages {
        stopMessages()
    }
    let context = makeExportContext()
    let cachedMessages = session.cachedUARTMessages()

    do {
        let fileURL = try SpaceDebugUARTLogExporter.makeFileURL(context: context, messages: cachedMessages)
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popoverController = controller.popoverPresentationController {
            popoverController.barButtonItem = navigationItem.rightBarButtonItem
            popoverController.sourceView = view
            popoverController.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(controller, animated: true)
    } catch {
        XWHUDManager.showErrorTipHUD("debug_uart_export_failed_message".localizedString)
    }
}
```

- [ ] **Step 5：本地化文件语法检查**

Run:

```bash
plutil -lint SunSmart/en.lproj/Localizable.strings
plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

```text
SunSmart/en.lproj/Localizable.strings: OK
SunSmart/zh-Hans.lproj/Localizable.strings: OK
```

- [ ] **Step 6：构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7：提交**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: share debug uart logs"
```

---

## Task 6：四品牌构建和真机验证

**Files:**
- No code changes expected.

- [ ] **Step 1：四品牌构建**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四个命令均输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 2：真机验证 UART 页面生命周期**

在支持 UART 的设备上验证：

- 进入 UART 页面后屏幕不会自动熄灭。
- 收到消息后列表显示新消息。
- 点击 `Stop` 后不再接收/缓存新消息。
- 点击 `Start` 后继续接收新消息。
- 退出 UART 页面再进入，先展示之前缓存的消息。
- 退出设备 Debug 页面再重新进入 Debug 流程，旧缓存已清空。

- [ ] **Step 3：真机验证断线和重连**

在 UART 页面断开设备或关闭设备电源：

- 只出现 UART 页面的断线弹窗。
- 点击 `Cancel` 只关闭弹窗，不退出页面，不清缓存。
- 点击 `Re-connect` 成功后继续接收消息。
- 重连失败后出现失败提示，可再次点击 `Re-connect`。

- [ ] **Step 4：真机验证分享文件**

在 UART 页面点击 `Share`：

- 如果正在接收，按钮状态变为 `Start`。
- iOS 分享面板正常出现。
- 分享出的 txt 文件名符合 `<site>-<space>-<group>-<device>-uart-yyMMddHHmmss.txt`。
- txt 文件头包含 site name、space name、group name、mac address、company id、product id、address、version identifier、model、device type、firmware version、dropped messages。
- 消息按旧到新排列。
- 当前有 Filter 输入时，导出仍包含完整缓存消息。

- [ ] **Step 5：最终状态检查**

Run:

```bash
git status --short
```

Expected: 只剩用户已有的未跟踪文档，或工作区干净；不应有未提交代码改动。
