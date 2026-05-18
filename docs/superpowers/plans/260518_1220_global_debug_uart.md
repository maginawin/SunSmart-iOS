# Global Debug UART Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Debug UART 接收从 UART 页面生命周期迁移为当前 Site 运行期内的全局功能，按设备缓存并支持单设备分享。

**Architecture:** 新增 `SpaceDebugUARTManager` 作为唯一状态源，负责全局接收开关、当前 Proxy 评估、按设备缓存、LRU 淘汰和页面通知。`DebugBluetoothSession` 继续负责扫描、连接、重连和断线，Debug 列表页、设备页、UART 页只通过 manager 读写 UART 状态。Site/Space/App 生命周期负责绑定或清理 manager。

**Tech Stack:** Swift、UIKit、SnapKit、NordicSigMeshSDK、CoreBluetooth、现有 `SRAlertView` / `XWHUDManager` / `UIActivityViewController`。

---

## 文件结构

- Create: `SunSmart/Main/Space/Debug/SpaceDebugUARTManager.swift`
  - 运行期单例，保存全局 UART 接收状态、设备缓存、LRU 淘汰、Proxy UART 通知订阅。
- Modify: `SunSmart.xcodeproj/project.pbxproj`
  - 将新建 manager 文件加入 Debug group，并加入 4 个品牌 target 的 Sources。
- Modify: `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`
  - 移除 UART 缓存职责，连接/重连成功后触发 manager 评估当前 Proxy，`finish()` 不再 Stop/Clear 全局 UART。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`
  - 维护哪些设备有 UART 缓存，用于列表行展示分享按钮。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
  - 给 `SpaceDebugNodeItem` 增加 `hasUARTCache`。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`
  - 增加分享按钮、delegate，避免分享点击触发行连接。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
  - 增加接收 UART 开关；订阅 manager；分享设备缓存；未连接可用设备连接前弹确认。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`
  - UART 支持检查后触发 manager 评估；进入 UART 页保持现有路由。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
  - 去掉页面私有 Start/Stop/cache 语义，改读写 manager；分享不 Stop；退出不 Stop。
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTLogExporter.swift`
  - 如现有 API 足够则不改；只在需要支持列表页按设备导出上下文时保持复用。
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - 进入 Space / 自动连接成功 / 退出 Debug 回 Space 时绑定当前 Space 并触发 manager 评估。
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
  - Space 首次自动连接成功时触发 manager 评估。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
  - 进入 Site 时激活 Site；返回站点列表或切换 Site 时清理当前 Site UART 状态。
- Modify: `SunSmart/AppDelegate/AppDelegate.swift`
  - App 终止时主动停止 UART 通知并清空缓存。
- Modify: `SunSmart/en.lproj/Localizable.strings`
  - 新增 Debug UART 接收开关、连接确认文案。
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 新增对应中文文案。

## Task 1: 新增全局 UART Manager 核心

**Files:**
- Create: `SunSmart/Main/Space/Debug/SpaceDebugUARTManager.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`

- [ ] **Step 1: 创建 manager 文件和核心类型**

Create `SunSmart/Main/Space/Debug/SpaceDebugUARTManager.swift` with this structure:

```swift
import Foundation
import NordicSigMeshSDK

struct SpaceDebugUARTDeviceKey: Hashable {
    let siteId: String
    let spaceId: String
    let address: Address
}

enum SpaceDebugUARTManagerEvent {
    case stateChanged
    case messageAppended(SpaceDebugUARTDeviceKey, SpaceDebugUARTMessage)
    case bufferChanged(SpaceDebugUARTDeviceKey)
    case allCleared
}

struct SpaceDebugUARTDeviceBuffer {
    var messages: [SpaceDebugUARTMessage] = []
    var droppedMessageCount: Int = 0
    var lastActiveAt: Date = Date()
}

final class SpaceDebugUARTManager {
    static let shared = SpaceDebugUARTManager()

    private let perDeviceMessageTrimThreshold = 100_000
    private let perDeviceMessageTrimTarget = 80_000
    private let deviceBufferLimit = 30

    private var observers: [UUID: (SpaceDebugUARTManagerEvent) -> Void] = [:]
    private var buffers: [SpaceDebugUARTDeviceKey: SpaceDebugUARTDeviceBuffer] = [:]
    private var activeSiteId: String?
    private weak var activeSpace: SpaceData?
    private var currentKey: SpaceDebugUARTDeviceKey?
    private var currentEvaluationID = UUID()
    private var meshConnectionObservation: NSKeyValueObservation?

    private(set) var isReceiveEnabled = false
    private(set) var currentSupportState: SpaceDebugUARTSupportViewState = .disconnected
    private(set) var isCurrentProxyNotifying = false

    private init() {
        observeMeshConnection()
    }
}
```

- [ ] **Step 2: 将新文件加入 Xcode project**

Modify `SunSmart.xcodeproj/project.pbxproj`.

Add build file entries near existing `SpaceDebugUARTLogExporter.swift in Sources` entries:

```text
		C8260516000001010000000B /* SpaceDebugUARTManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000C /* SpaceDebugUARTManager.swift */; };
		C8260516000001020000000B /* SpaceDebugUARTManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000C /* SpaceDebugUARTManager.swift */; };
		C8260516000001030000000B /* SpaceDebugUARTManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000C /* SpaceDebugUARTManager.swift */; };
		C8260516000001040000000B /* SpaceDebugUARTManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8260516000000010000000C /* SpaceDebugUARTManager.swift */; };
```

Add file reference near existing Debug file references:

```text
		C8260516000000010000000C /* SpaceDebugUARTManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpaceDebugUARTManager.swift; sourceTree = "<group>"; };
```

Add the file reference to the `Debug` group after `SpaceDebugUARTLogExporter.swift`:

```text
				C8260516000000010000000C /* SpaceDebugUARTManager.swift */,
```

Add each build file to the four `PBXSourcesBuildPhase` lists that already contain the corresponding Debug sources:

```text
				C8260516000001010000000B /* SpaceDebugUARTManager.swift in Sources */,
				C8260516000001020000000B /* SpaceDebugUARTManager.swift in Sources */,
				C8260516000001030000000B /* SpaceDebugUARTManager.swift in Sources */,
				C8260516000001040000000B /* SpaceDebugUARTManager.swift in Sources */,
```

Place each one in the same target source list as the nearby `SpaceDebugUARTLogExporter.swift in Sources` entry with the matching `101` / `102` / `103` / `104` prefix.

- [ ] **Step 3: 增加 public 读取和观察接口**

Append these methods inside `SpaceDebugUARTManager`:

```swift
@discardableResult
func observe(_ observer: @escaping (SpaceDebugUARTManagerEvent) -> Void) -> UUID {
    let token = UUID()
    observers[token] = observer
    observer(.stateChanged)
    return token
}

func removeObserver(_ token: UUID?) {
    guard let token else { return }
    observers[token] = nil
}

func key(siteId: String, spaceId: String, address: Address) -> SpaceDebugUARTDeviceKey {
    SpaceDebugUARTDeviceKey(siteId: siteId, spaceId: spaceId, address: address)
}

func key(space: SpaceData, node: Node) -> SpaceDebugUARTDeviceKey {
    key(siteId: space.siteId, spaceId: space.id, address: node.primaryUnicastAddress)
}

func cachedMessages(for key: SpaceDebugUARTDeviceKey) -> [SpaceDebugUARTMessage] {
    buffers[key]?.messages ?? []
}

func droppedMessageCount(for key: SpaceDebugUARTDeviceKey) -> Int {
    buffers[key]?.droppedMessageCount ?? 0
}

func hasCache(for key: SpaceDebugUARTDeviceKey) -> Bool {
    !(buffers[key]?.messages.isEmpty ?? true)
}

func cachedKeys(siteId: String, spaceId: String) -> Set<Address> {
    Set(buffers.keys
        .filter { $0.siteId == siteId && $0.spaceId == spaceId && hasCache(for: $0) }
        .map(\.address))
}

private func notify(_ event: SpaceDebugUARTManagerEvent) {
    observers.values.forEach { $0(event) }
}
```

- [ ] **Step 4: 增加 Site/Space 生命周期接口**

Append these methods:

```swift
func activateSite(_ siteId: String) {
    if activeSiteId != siteId {
        resetAll()
        activeSiteId = siteId
    }
}

func endSite(_ siteId: String) {
    guard activeSiteId == siteId else { return }
    resetAll()
    activeSiteId = nil
    activeSpace = nil
}

func setActiveSpace(_ space: SpaceData) {
    activateSite(space.siteId)
    activeSpace = space
}

func resetAll() {
    stopCurrentNotifications()
    isReceiveEnabled = false
    currentSupportState = .disconnected
    currentKey = nil
    buffers.removeAll()
    notify(.allCleared)
    notify(.stateChanged)
}
```

- [ ] **Step 5: 增加接收开关和清理接口**

Append these methods:

```swift
func setReceiveEnabled(_ enabled: Bool, space: SpaceData?) {
    isReceiveEnabled = enabled
    if let space {
        setActiveSpace(space)
    }
    if enabled {
        evaluateCurrentProxy(space: space ?? activeSpace)
    } else {
        stopCurrentNotifications()
        notify(.stateChanged)
    }
}

func clearMessages(for key: SpaceDebugUARTDeviceKey) {
    guard buffers[key] != nil else { return }
    buffers[key]?.messages.removeAll()
    buffers[key]?.droppedMessageCount = 0
    buffers[key]?.lastActiveAt = Date()
    notify(.bufferChanged(key))
    notify(.stateChanged)
}
```

- [ ] **Step 6: 增加 Proxy 评估和通知订阅逻辑**

Append these methods:

```swift
func evaluateCurrentProxy(space: SpaceData?) {
    if let space {
        setActiveSpace(space)
    }

    guard let space = space ?? activeSpace else {
        stopCurrentNotifications()
        currentSupportState = .disconnected
        currentKey = nil
        notify(.stateChanged)
        return
    }

    guard activeSiteId == nil || activeSiteId == space.siteId else {
        stopCurrentNotifications()
        currentSupportState = .disconnected
        currentKey = nil
        notify(.stateChanged)
        return
    }

    guard let proxy = MeshLibManager.manager.currentProxy,
          let node = proxy.node,
          MeshNetworkManager.instance.realNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
        stopCurrentNotifications()
        currentSupportState = .disconnected
        currentKey = nil
        notify(.stateChanged)
        return
    }

    let key = key(space: space, node: node)
    currentKey = key
    currentSupportState = .checking
    notify(.stateChanged)

    let evaluationID = UUID()
    currentEvaluationID = evaluationID
    proxy.discoverDebugUARTService { [weak self] state in
        DispatchQueue.main.async {
            guard let self, self.currentEvaluationID == evaluationID else { return }
            let mappedState = Self.mapUARTState(state)
            self.currentSupportState = mappedState
            guard case .supported = mappedState else {
                self.stopCurrentNotifications()
                self.notify(.stateChanged)
                return
            }
            if self.isReceiveEnabled {
                self.startNotifications(proxy: proxy, key: key)
            } else {
                self.notify(.stateChanged)
            }
        }
    }
}

private func startNotifications(proxy: GattBearer, key: SpaceDebugUARTDeviceKey) {
    ensureBufferExists(for: key)
    buffers[key]?.lastActiveAt = Date()
    isCurrentProxyNotifying = true
    notify(.stateChanged)

    proxy.startDebugUARTMessages(onMessage: { [weak self] message in
        DispatchQueue.main.async {
            guard let self, self.isReceiveEnabled, self.currentKey == key else { return }
            let viewMessage = SpaceDebugUARTMessage(text: message.text, timestamp: message.timestamp)
            self.append(viewMessage, for: key)
        }
    }, completion: { [weak self] state in
        DispatchQueue.main.async {
            guard let self else { return }
            let mappedState = Self.mapUARTState(state)
            self.currentSupportState = mappedState
            self.isCurrentProxyNotifying = mappedState == .supported && self.isReceiveEnabled
            self.notify(.stateChanged)
        }
    })
}

private func stopCurrentNotifications() {
    isCurrentProxyNotifying = false
    MeshLibManager.manager.currentProxy?.stopDebugUARTMessages()
}
```

- [ ] **Step 7: 增加缓存追加、LRU 淘汰和 KVO**

Append these methods:

```swift
private func ensureBufferExists(for key: SpaceDebugUARTDeviceKey) {
    if buffers[key] != nil {
        buffers[key]?.lastActiveAt = Date()
        return
    }
    if buffers.count >= deviceBufferLimit,
       let keyToRemove = buffers.min(by: { $0.value.lastActiveAt < $1.value.lastActiveAt })?.key {
        buffers.removeValue(forKey: keyToRemove)
        notify(.bufferChanged(keyToRemove))
    }
    buffers[key] = SpaceDebugUARTDeviceBuffer(lastActiveAt: Date())
    notify(.bufferChanged(key))
}

private func append(_ message: SpaceDebugUARTMessage, for key: SpaceDebugUARTDeviceKey) {
    ensureBufferExists(for: key)
    buffers[key]?.messages.append(message)
    buffers[key]?.lastActiveAt = Date()
    trimMessagesIfNeeded(for: key)
    notify(.messageAppended(key, message))
}

private func trimMessagesIfNeeded(for key: SpaceDebugUARTDeviceKey) {
    guard let count = buffers[key]?.messages.count, count > perDeviceMessageTrimThreshold else {
        return
    }
    let removeCount = count - perDeviceMessageTrimTarget
    buffers[key]?.messages.removeFirst(removeCount)
    buffers[key]?.droppedMessageCount += removeCount
    notify(.bufferChanged(key))
}

private func observeMeshConnection() {
    meshConnectionObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, _ in
        DispatchQueue.main.async {
            guard let self else { return }
            if MeshLibManager.manager.isMeshNetworkConnected {
                self.evaluateCurrentProxy(space: self.activeSpace)
            } else {
                self.stopCurrentNotifications()
                self.currentSupportState = .disconnected
                self.currentKey = nil
                self.notify(.stateChanged)
            }
        }
    }
}

private static func mapUARTState(_ state: DebugUARTSupportState) -> SpaceDebugUARTSupportViewState {
    switch state {
    case .supported:
        return .supported
    case .unsupported:
        return .unsupported
    case .disconnected:
        return .disconnected
    case .discoveryFailed(let message):
        return .failed(message)
    }
}
```

- [ ] **Step 8: 给 `SpaceDebugNodeItem` 增加缓存标记**

Modify `SunSmart/Main/Space/Debug/SpaceDebugModels.swift` inside `SpaceDebugNodeItem`:

```swift
var hasUARTCache: Bool = false
```

- [ ] **Step 9: 编译验证当前新增类型**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build may fail only because call sites still use old `DebugBluetoothSession` UART APIs. If failure includes missing manager imports or syntax errors in `SpaceDebugUARTManager.swift`, fix those before continuing.

- [ ] **Step 10: Commit**

```bash
git add SunSmart.xcodeproj/project.pbxproj SunSmart/Main/Space/Debug/SpaceDebugUARTManager.swift SunSmart/Main/Space/Debug/SpaceDebugModels.swift
git commit -m "feat: add global debug uart manager"
```

## Task 2: 从 DebugBluetoothSession 迁移 UART 职责

**Files:**
- Modify: `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`

- [ ] **Step 1: 删除 session 私有 UART 缓存状态**

Remove these properties from `DebugBluetoothSession`:

```swift
private let uartMessageTrimThreshold = 100_000
private let uartMessageTrimTarget = 80_000
private var uartMessageHandler: ((SpaceDebugUARTMessage) -> Void)?

private(set) var uartMessages: [SpaceDebugUARTMessage] = []
private(set) var droppedUARTMessageCount = 0
private(set) var isReceivingUARTMessages = false
```

- [ ] **Step 2: 删除旧 UART 接收和缓存方法**

Remove these methods from `DebugBluetoothSession`:

```swift
func startUARTMessages(
    onMessage: @escaping (SpaceDebugUARTMessage) -> Void,
    completion: @escaping (SpaceDebugUARTSupportViewState) -> Void
)

func stopUARTMessages()
func cachedUARTMessages() -> [SpaceDebugUARTMessage]
func clearUARTMessages()
private func appendUARTMessage(_ message: SpaceDebugUARTMessage)
private func trimUARTMessagesIfNeeded()
```

Keep `checkUARTSupport(completion:)` and `mapUARTState(_:)` because the device page can still use them for support display.

- [ ] **Step 3: 连接成功后触发 manager 评估**

In `connect(_ item:completion:)`, inside the `success` branch, add:

```swift
SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
```

The success block should read:

```swift
if !success {
    self?.connectedNode = self?.currentConnectedNodeInSpace()
} else {
    self?.connectedNode = item.node
    SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self?.space)
}
```

If Swift rejects optional `self?.space`, unwrap `self` before the branch:

```swift
guard let self = self else {
    completion(success)
    return
}
```

- [ ] **Step 4: 重连成功后触发 manager 评估**

In `reconnect(completion:)`, when `success` is true, add:

```swift
SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
```

- [ ] **Step 5: `finish()` 不再停止或清理全局 UART**

Change `finish()` to remove:

```swift
stopUARTMessages()
clearUARTMessages()
```

`finish()` should still stop scan, clear `connectedNode`, and release KVO.

- [ ] **Step 6: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: remaining failures should be old UART page call sites referencing removed session APIs. No failures should come from `DebugBluetoothSession.swift`.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Debug/DebugBluetoothSession.swift
git commit -m "refactor: move uart state out of debug session"
```

## Task 3: 接入 Debug 列表页开关、缓存标记和分享按钮

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 本地化新增文案**

Add to `SunSmart/en.lproj/Localizable.strings` near existing debug UART keys:

```text
"debug_uart_receive_messages" = "Receive UART Messages";
"debug_connect_proxy_title" = "Connect Proxy Node";
"debug_connect_proxy_message" = "Connect to this Proxy Node for debugging?";
"debug_switch_proxy_message" = "This will disconnect the current Proxy Node and connect to the selected device.";
```

Add to `SunSmart/zh-Hans.lproj/Localizable.strings`:

```text
"debug_uart_receive_messages" = "接收 UART 消息";
"debug_connect_proxy_title" = "连接 Proxy Node";
"debug_connect_proxy_message" = "是否连接此 Proxy Node 进行调试？";
"debug_switch_proxy_message" = "这会断开当前 Proxy Node，并连接所选设备。";
```

- [ ] **Step 2: ViewModel 维护 UART 缓存地址集合**

In `SpaceDebugViewModel`, add:

```swift
private var uartCachedAddresses: Set<Address> = []
```

Add method:

```swift
func setUARTCachedAddresses(_ addresses: Set<Address>) {
    uartCachedAddresses = addresses
    onSnapshotChanged?()
}
```

When building sections or returning `item(at:)`, ensure each item receives:

```swift
item.hasUARTCache = uartCachedAddresses.contains(item.address)
```

If the file currently returns values directly from `itemsByAddress`, add a helper:

```swift
private func decorate(_ item: SpaceDebugNodeItem) -> SpaceDebugNodeItem {
    var item = item
    item.hasUARTCache = uartCachedAddresses.contains(item.address)
    return item
}
```

Use `decorate` in `item(at:)`, `item(address:)`, and `sections()`.

- [ ] **Step 3: 给 cell 增加 delegate 和分享按钮**

In `SpaceDebugDeviceCell.swift`, add above the class:

```swift
protocol SpaceDebugDeviceCellDelegate: AnyObject {
    func spaceDebugDeviceCellDidTapShare(_ cell: SpaceDebugDeviceCell)
}
```

Inside class add:

```swift
weak var delegate: SpaceDebugDeviceCellDelegate?
private let shareButton = UIButton(type: .system)
```

In `setupUI()`, configure:

```swift
shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
shareButton.tintColor = Bar_Color
shareButton.addTarget(self, action: #selector(shareButtonTapped), for: .touchUpInside)
contentView.addSubview(shareButton)
shareButton.snp.makeConstraints { make in
    make.right.equalTo(SCRXFrom(-16))
    make.centerY.equalToSuperview()
    make.size.equalTo(CGSize(width: SCRXFrom(36), height: SCRYFrom(36)))
}
```

Move `signalStrengthView` and `rssiLabel` constraints so their right edge is:

```swift
make.right.equalTo(shareButton.snp.left).offset(SCRXFrom(-8))
```

Add action:

```swift
@objc private func shareButtonTapped() {
    delegate?.spaceDebugDeviceCellDidTapShare(self)
}
```

In `update(item:)`, add:

```swift
shareButton.isHidden = !item.hasUARTCache
```

- [ ] **Step 4: Debug 列表页增加 UART 开关 UI**

In `SpaceDebugViewController`, add properties:

```swift
private let uartReceiveContainerView = UIView()
private let uartReceiveLabel = UILabel()
private let uartReceiveSwitch = UISwitch()
private var uartObserverToken: UUID?
```

In `setupUI()`, insert the container between `summaryView` and `tableView`:

```swift
uartReceiveContainerView.backgroundColor = Background_Color
view.addSubview(uartReceiveContainerView)
uartReceiveContainerView.snp.makeConstraints { make in
    make.top.equalTo(summaryView.snp.bottom)
    make.left.right.equalToSuperview()
    make.height.equalTo(SCRYFrom(48))
}

uartReceiveLabel.font = Font_Medium_Size(14)
uartReceiveLabel.textColor = Title_Color
uartReceiveLabel.text = "debug_uart_receive_messages".localizedString
uartReceiveContainerView.addSubview(uartReceiveLabel)
uartReceiveLabel.snp.makeConstraints { make in
    make.left.equalTo(SCRXFrom(16))
    make.centerY.equalToSuperview()
}

uartReceiveSwitch.addTarget(self, action: #selector(uartReceiveSwitchChanged(_:)), for: .valueChanged)
uartReceiveContainerView.addSubview(uartReceiveSwitch)
uartReceiveSwitch.snp.makeConstraints { make in
    make.right.equalTo(SCRXFrom(-16))
    make.centerY.equalToSuperview()
}

tableView.snp.remakeConstraints { make in
    make.top.equalTo(uartReceiveContainerView.snp.bottom)
    make.left.right.bottom.equalToSuperview()
}
```

- [ ] **Step 5: Debug 列表页订阅 manager**

In `viewDidLoad()` after `bindViewModel()`:

```swift
SpaceDebugUARTManager.shared.setActiveSpace(space)
bindUARTManager()
```

Add:

```swift
private func bindUARTManager() {
    uartObserverToken = SpaceDebugUARTManager.shared.observe { [weak self] _ in
        guard let self else { return }
        self.uartReceiveSwitch.isOn = SpaceDebugUARTManager.shared.isReceiveEnabled
        let addresses = SpaceDebugUARTManager.shared.cachedKeys(siteId: self.space.siteId, spaceId: self.space.id)
        self.viewModel.setUARTCachedAddresses(addresses)
    }
}
```

In `deinit` before `finishFlow()` or after it:

```swift
SpaceDebugUARTManager.shared.removeObserver(uartObserverToken)
```

Add switch action:

```swift
@objc private func uartReceiveSwitchChanged(_ sender: UISwitch) {
    SpaceDebugUARTManager.shared.setReceiveEnabled(sender.isOn, space: space)
}
```

- [ ] **Step 6: cell delegate and row sharing**

In `cellForRowAt`, set:

```swift
cell.delegate = self
```

Add extension:

```swift
extension SpaceDebugViewController: SpaceDebugDeviceCellDelegate {
    func spaceDebugDeviceCellDidTapShare(_ cell: SpaceDebugDeviceCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        shareUARTLog(for: viewModel.item(at: indexPath), sourceView: cell)
    }
}
```

Add sharing method:

```swift
private func shareUARTLog(for item: SpaceDebugNodeItem, sourceView: UIView) {
    let key = SpaceDebugUARTManager.shared.key(space: space, node: item.node)
    let messages = SpaceDebugUARTManager.shared.cachedMessages(for: key)
    guard !messages.isEmpty else { return }
    let context = makeExportContext(item: item, droppedMessageCount: SpaceDebugUARTManager.shared.droppedMessageCount(for: key))
    do {
        let fileURL = try SpaceDebugUARTLogExporter.makeFileURL(context: context, messages: messages)
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popoverController = controller.popoverPresentationController {
            popoverController.sourceView = sourceView
            popoverController.sourceRect = sourceView.bounds
        }
        present(controller, animated: true)
    } catch {
        XWHUDManager.showErrorTipHUD("debug_uart_export_failed_message".localizedString)
    }
}
```

Add context helper by moving the UART page context code shape into list page:

```swift
private func makeExportContext(item: SpaceDebugNodeItem, droppedMessageCount: Int) -> SpaceDebugUARTLogExportContext {
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
        droppedMessageCount: droppedMessageCount,
        generatedAt: Date()
    )
}
```

- [ ] **Step 7: 未连接设备连接前确认**

In `tableView(_:didSelectRowAt:)`, replace direct `connect(viewModel.item(at: indexPath))` with:

```swift
let item = viewModel.item(at: indexPath)
if item.isConnected {
    connect(item)
} else {
    confirmConnect(item)
}
```

Add:

```swift
private func confirmConnect(_ item: SpaceDebugNodeItem) {
    guard item.isFound else { return }
    let hasCurrentProxy = MeshLibManager.manager.currentProxy != nil
    let message = hasCurrentProxy ? "debug_switch_proxy_message".localizedString : "debug_connect_proxy_message".localizedString
    SRAlertView(title: "debug_connect_proxy_title".localizedString, message: message, actions: [
        .cancelAction,
        SRAlertAction(title: "confirm".localizedString, actionHandler: { [weak self] _ in
            self?.connect(item)
        })
    ]).show()
}
```

- [ ] **Step 8: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: failures may remain in `SpaceDebugUARTViewController.swift` because it still calls old session UART APIs. The Debug list, cell, view model, and strings should compile.

- [ ] **Step 9: Commit**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift SunSmart/Main/Space/Debug/SpaceDebugViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: add debug uart list controls"
```

## Task 4: 改造 UART 消息页为全局状态消费者

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift`

- [ ] **Step 1: 替换 UART 页私有接收状态字段**

In `SpaceDebugUARTViewController`, remove:

```swift
private var isReceivingUARTMessages = false
private var shouldResumeReceivingAfterReconnect = false
```

Add:

```swift
private let uartKey: SpaceDebugUARTDeviceKey
private var uartObserverToken: UUID?
```

In `init(session:space:item:)`, after assigning properties:

```swift
self.uartKey = SpaceDebugUARTManager.shared.key(space: space, node: item.node)
```

- [ ] **Step 2: 分享按钮改为 SF Symbol**

Replace the right bar button setup in `viewDidLoad()`:

```swift
navigationItem.rightBarButtonItem = UIBarButtonItem(
    image: UIImage(systemName: "square.and.arrow.up"),
    style: .plain,
    target: self,
    action: #selector(shareButtonTapped)
)
```

- [ ] **Step 3: 页面加载时读取 manager 缓存，不主动 Start**

Replace:

```swift
messages = session.cachedUARTMessages()
rebuildDisplayMessages()
tableView.reloadData()
startMessages()
```

with:

```swift
SpaceDebugUARTManager.shared.setActiveSpace(space)
messages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
rebuildDisplayMessages()
tableView.reloadData()
bindUARTManager()
updateReceiveButton()
```

- [ ] **Step 4: 增加 manager 观察**

Add:

```swift
private func bindUARTManager() {
    uartObserverToken = SpaceDebugUARTManager.shared.observe { [weak self] event in
        guard let self else { return }
        self.updateReceiveButton()
        switch event {
        case .messageAppended(let key, let message) where key == self.uartKey:
            self.handleAppendedMessage(message)
        case .bufferChanged(let key) where key == self.uartKey:
            self.reloadMessagesFromManager(scrollIfNeeded: self.scrollMode == .auto)
        case .allCleared:
            self.reloadMessagesFromManager(scrollIfNeeded: false)
        case .stateChanged, .messageAppended, .bufferChanged:
            break
        }
    }
}

private func handleAppendedMessage(_ message: SpaceDebugUARTMessage) {
    let shouldScroll = scrollMode == .auto && messageMatchesFilter(message)
    let previousMessageCount = messages.count
    messages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
    if messages.count < previousMessageCount {
        rebuildDisplayMessages()
        tableView.reloadData()
    } else if appendDisplayMessageIfNeeded(message) {
        tableView.reloadData()
    }
    if shouldScroll {
        scrollToLatestVisibleMessage(animated: true)
    }
}

private func reloadMessagesFromManager(scrollIfNeeded: Bool) {
    messages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
    rebuildDisplayMessages()
    tableView.reloadData()
    if scrollIfNeeded {
        scrollToLatestVisibleMessage(animated: false)
    }
}
```

- [ ] **Step 5: Start/Stop 改为全局开关**

Replace `startMessages()` and `stopMessages()` with:

```swift
private func startMessages() {
    SpaceDebugUARTManager.shared.setReceiveEnabled(true, space: space)
    updateReceiveButton()
}

private func stopMessages() {
    SpaceDebugUARTManager.shared.setReceiveEnabled(false, space: space)
    updateReceiveButton()
}
```

Replace `updateReceiveButton()` with:

```swift
private func updateReceiveButton() {
    let title = SpaceDebugUARTManager.shared.isReceiveEnabled ? "debug_uart_stop".localizedString : "debug_uart_start".localizedString
    receiveButton.setTitle(title, for: .normal)
}
```

`receiveButtonTapped()` can keep its current shape but should branch on `SpaceDebugUARTManager.shared.isReceiveEnabled`.

- [ ] **Step 6: Clear 当前设备缓存**

Replace `clearMessages()` with:

```swift
private func clearMessages() {
    SpaceDebugUARTManager.shared.clearMessages(for: uartKey)
    messages.removeAll()
    displayMessages.removeAll()
    tableView.reloadData()
}
```

- [ ] **Step 7: 页面退出和 deinit 不 Stop**

In `viewDidDisappear(_:)`, keep idle timer restore but remove:

```swift
isReceivingUARTMessages = false
session.stopUARTMessages()
```

In `deinit`, remove any `session.stopUARTMessages()` call and add:

```swift
SpaceDebugUARTManager.shared.removeObserver(uartObserverToken)
```

- [ ] **Step 8: 断线处理不关闭全局接收**

Replace `handleUnexpectedDisconnect()` with:

```swift
private func handleUnexpectedDisconnect() {
    updateReceiveButton()
    showDisconnectedAlert()
}
```

In `reconnect()`, after reconnect success:

```swift
SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: space)
```

Do not auto-call `startMessages()` here; manager will start if `isReceiveEnabled == true`.

- [ ] **Step 9: 分享不 Stop，使用 manager 快照**

In `shareButtonTapped()`, remove:

```swift
if isReceivingUARTMessages {
    stopMessages()
}
```

Replace:

```swift
let cachedMessages = session.cachedUARTMessages()
```

with:

```swift
let cachedMessages = SpaceDebugUARTManager.shared.cachedMessages(for: uartKey)
```

In `makeExportContext()`, replace dropped count:

```swift
droppedMessageCount: SpaceDebugUARTManager.shared.droppedMessageCount(for: uartKey),
```

- [ ] **Step 10: 设备页支持检查后评估当前 Proxy**

In `SpaceDebugDeviceViewController.checkUARTSupport()` completion, after:

```swift
self.uartState = state
self.render()
```

add:

```swift
if case .supported = state {
    SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
}
```

- [ ] **Step 11: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: no references remain to `session.startUARTMessages`, `session.stopUARTMessages`, `session.cachedUARTMessages`, `session.clearUARTMessages`, or `session.droppedUARTMessageCount`.

- [ ] **Step 12: Commit**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugUARTViewController.swift SunSmart/Main/Space/Debug/SpaceDebugDeviceViewController.swift
git commit -m "feat: use global uart state in debug pages"
```

## Task 5: 接入 Space、Site 和 App 生命周期

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`
- Modify: `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `SunSmart/AppDelegate/AppDelegate.swift`

- [ ] **Step 1: Space 进入时绑定 active space**

In `SpaceViewController.viewDidLoad()` or after `space` is initialized and before `setNetworkConnected()` can run, add:

```swift
SpaceDebugUARTManager.shared.setActiveSpace(space)
```

- [ ] **Step 2: Space 自动连接完成后评估 Proxy**

In `SpaceViewController.setNetworkConnected()`, inside `manager.loadExtensionData` success path after `self.reloadData()`, add:

```swift
SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
```

In `restoreMeshConnectionAfterDebug()`, change:

```swift
guard !MeshLibManager.manager.isMeshNetworkConnected else {
    return
}
setNetworkConnected()
```

to:

```swift
guard !MeshLibManager.manager.isMeshNetworkConnected else {
    SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: space)
    return
}
setNetworkConnected()
```

- [ ] **Step 3: DevicesViewController 首次连接成功后评估 Proxy**

In `DevicesViewController.addObservation()`, inside:

```swift
if MeshLibManager.manager.isMeshNetworkConnected, self.firstConnectionNetwork {
```

after `self.firstConnectionNetwork = false`, add:

```swift
SpaceDebugUARTManager.shared.setActiveSpace(self.space)
SpaceDebugUARTManager.shared.evaluateCurrentProxy(space: self.space)
```

- [ ] **Step 4: Site 激活和退出清理**

In `SiteViewController.viewWillAppear(_:)`, after `setupData()` add:

```swift
SpaceDebugUARTManager.shared.activateSite(site.id)
```

In `backAction()`, before popping or dismissing, add:

```swift
SpaceDebugUARTManager.shared.endSite(site.id)
```

In `deinit`, before `MeshLibManager.manager.meshNetworkDisconnect()` logic, add:

```swift
SpaceDebugUARTManager.shared.endSite(site.id)
```

This ensures returning to site list or replacing the visible Site clears UART state.

- [ ] **Step 5: App 终止时清理**

In `AppDelegate`, add:

```swift
func applicationWillTerminate(_ application: UIApplication) {
    SpaceDebugUARTManager.shared.resetAll()
}
```

- [ ] **Step 6: 编译验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Controller/SpaceViewController.swift SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/AppDelegate/AppDelegate.swift
git commit -m "feat: bind debug uart to site lifecycle"
```

## Task 6: 最终验证与修正

**Files:**
- Verify all files touched in Tasks 1-5.

- [ ] **Step 1: 静态检查旧行为已移除**

Run:

```bash
rg -n "startUARTMessages|stopUARTMessages|cachedUARTMessages|clearUARTMessages|droppedUARTMessageCount|isReceivingUARTMessages|shouldResumeReceivingAfterReconnect" SunSmart/Main/Space/Debug
```

Expected:

- No references to removed `DebugBluetoothSession` UART cache APIs.
- `droppedUARTMessageCount` may appear only in `SpaceDebugUARTManager.swift`, `SpaceDebugUARTLogExporter.swift`, and export context creation.
- `isReceivingUARTMessages` and `shouldResumeReceivingAfterReconnect` do not appear.

- [ ] **Step 2: 静态检查分享按钮符号**

Run:

```bash
rg -n "square.and.arrow.up|debug_uart_share" SunSmart/Main/Space/Debug SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
```

Expected:

- `square.and.arrow.up` appears in `SpaceDebugDeviceCell.swift` and `SpaceDebugUARTViewController.swift`.
- `debug_uart_share` is no longer used by the UART page right bar button.

- [ ] **Step 3: 构建验证**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. Existing warnings are acceptable if unrelated to touched files.

- [ ] **Step 4: 手动验证清单**

On a device with at least two Proxy Nodes where one supports UART:

```text
1. 进入 Site，再进入 Space，打开 Debug。
2. 确认 Debug 列表页“接收 UART 消息”默认关闭。
3. 开启开关，若当前 Proxy 支持 UART，确认 UART 页能看到新消息。
4. 点击 UART 页 Share，确认不会 Stop，返回页面后仍继续追加消息。
5. 返回 Debug 列表，再返回 Space，保持 App 在 Space，确认仍继续接收当前 Proxy UART 消息。
6. 回到 Debug 列表，确认有缓存的设备行显示 square.and.arrow.up 分享按钮。
7. 点击设备行分享按钮，确认只弹分享，不进入连接流程。
8. 点击另一个已扫描到但未连接的设备行，确认先弹连接确认；取消不切换，确认才切换。
9. Clear 当前设备缓存，确认其它设备缓存分享按钮和日志不受影响。
10. 连接或启用第 31 个支持 UART 且需要缓存的新设备，确认最久未活跃设备缓存被清除。
11. 返回站点列表，再进入同一 Site/Space，确认接收开关关闭且旧缓存为空。
```

- [ ] **Step 5: 最终状态检查**

Run:

```bash
git status --short
git log --oneline -6
```

Expected:

- `git status --short` clean after final commit.
- Recent commits include the five implementation commits and the plan/spec commits.

- [ ] **Step 6: Commit final fixes if any**

If Steps 1-4 required fixes, commit them:

```bash
git add SunSmart/Main/Space/Debug SunSmart/Main/Space/Controller/SpaceViewController.swift SunSmart/Main/Device/Controller/DevicesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/AppDelegate/AppDelegate.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "fix: verify global debug uart behavior"
```

If no fixes were required, do not create an empty commit.
