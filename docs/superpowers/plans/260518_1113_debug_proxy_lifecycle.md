# Debug Proxy Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 调整 Space Debug 的 Proxy 生命周期，使调试页复用正常控制的 Proxy 通路、仅在用户手动切换设备时断开当前 Proxy，并在退出调试页后恢复 Space 自动连接逻辑。

**Architecture:** 保持现有 `SpaceDebugViewController`、`SpaceDebugViewModel`、`DebugBluetoothSession` 边界。Debug session 不再在进入/退出时主动 `meshNetworkDisconnect()`，而是只维护“当前连接节点”状态、扫描 RSSI、手动切换连接，并在 Proxy 自然断开时阻止调试页内继续自动连接。Space 退出回调只在需要时恢复 `setNetworkConnected()`，避免当前 Proxy 仍连接时重建 `NetworkConnection`。

**Tech Stack:** Swift、UIKit、CoreBluetooth、NordicSigMeshSDK、Xcode workspace `SunSmart.xcworkspace`。

---

## 文件结构

- 修改 `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
  - 给 `SpaceDebugNodeItem` 增加 `isConnected` 和统一可点击判断。
- 修改 `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`
  - 维护当前连接地址，统一刷新行状态，确保扫描重置不清除连接态。
- 修改 `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`
  - 进入 Debug 不断开 Proxy；连接自然断开时停止自动重连扫描；手动切换时才断开当前 Proxy。
- 修改 `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`
  - 按当前连接状态渲染列表；已连接行直接进详情页；未扫描到行不可点；返回列表后不自动断开。
- 修改 `SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`
  - `Connected` 行展示和可点击逻辑。
- 修改 `SunSmart/Main/Space/Controller/SpaceViewController.swift`
  - Debug 退出回调只在当前 Mesh 未连接时恢复 `setNetworkConnected()`。

本工程没有现成 XCTest target；本计划不新增测试 target，避免扩大 target 配置影响面。每个任务用编译和代码级检查验证，最终用真实蓝牙场景验收。

---

### Task 1: 调整 Debug 列表状态模型

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugModels.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift`

- [ ] **Step 1: 检查当前状态模型**

Run:

```bash
sed -n '45,140p' SunSmart/Main/Space/Debug/SpaceDebugModels.swift
sed -n '1,130p' SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
```

Expected: 看到 `SpaceDebugNodeItem` 只有 `isConnecting` / `isFound`，`SpaceDebugViewModel` 没有连接地址状态。

- [ ] **Step 2: 更新 `SpaceDebugNodeItem`**

在 `SpaceDebugModels.swift` 的 `SpaceDebugNodeItem` 中加入连接状态和统一可点击判断。保留 `isFound` 的现有含义。

```swift
struct SpaceDebugNodeItem {
    let node: Node
    let displayOrder: Int
    var peripheral: CBPeripheral?
    var rssi: Int?
    var lastSeen: Date?
    var isConnecting: Bool = false
    var isConnected: Bool = false

    var address: Address {
        node.primaryUnicastAddress
    }

    var category: SpaceDebugDeviceCategory {
        SpaceDebugDeviceCategory(node: node)
    }

    var isFound: Bool {
        peripheral != nil && rssi != nil
    }

    var isAvailable: Bool {
        isConnected || isFound
    }
}
```

保留 `groupName`、`nodeName`、`displayTitle` 等现有计算属性，不改命名和本地化。

- [ ] **Step 3: 更新 ViewModel 连接状态维护**

在 `SpaceDebugViewModel` 中增加 `connectedAddress`，并让所有入口都通过同一个 helper 刷新 `isConnected`。

```swift
private var connectedAddress: Address?

func setConnectedNode(_ node: Node?) {
    setConnectedAddress(node?.primaryUnicastAddress)
}

func setConnectedAddress(_ address: Address?) {
    connectedAddress = address
    refreshConnectedState()
    onSnapshotChanged?()
}

func clearConnectedNode() {
    setConnectedAddress(nil)
}

func item(address: Address) -> SpaceDebugNodeItem? {
    itemsByAddress[address]
}

private func refreshConnectedState() {
    itemsByAddress = Dictionary(
        uniqueKeysWithValues: itemsByAddress.values.map { item in
            var next = item
            next.isConnected = item.address == connectedAddress
            return (next.address, next)
        }
    )
}
```

- [ ] **Step 4: 保证替换节点和重置扫描时保留连接态**

修改 `replaceNodes(_:)`，重新生成 items 后立即刷新连接态。

```swift
func replaceNodes(_ nodes: [Node]) {
    itemsByAddress = SpaceDebugViewModel.makeItems(nodes: nodes)
    refreshConnectedState()
    onSnapshotChanged?()
}
```

修改 `resetFoundState()`，只清空扫描信息和连接中状态，不清空 `isConnected`。

```swift
func resetFoundState() {
    itemsByAddress = Dictionary(
        uniqueKeysWithValues: itemsByAddress.values.map { item in
            var next = item
            next.peripheral = nil
            next.rssi = nil
            next.lastSeen = nil
            next.isConnecting = false
            next.isConnected = item.address == connectedAddress
            return (next.address, next)
        }
    )
    onSnapshotChanged?()
}
```

修改 `updateFoundNode(_:)`，更新 RSSI 后保持连接态。

```swift
func updateFoundNode(_ data: MeshNodePeripheralData) {
    let address = data.node.primaryUnicastAddress
    guard var item = itemsByAddress[address] else {
        return
    }
    item.peripheral = data.peripheral
    item.rssi = data.rssi.intValue
    item.lastSeen = Date()
    item.isConnected = address == connectedAddress
    itemsByAddress[address] = item
    scheduleSnapshotRefresh()
}
```

修改 `setConnecting(address:)`，避免连接中状态覆盖已连接标记。

```swift
func setConnecting(address: Address?) {
    itemsByAddress = Dictionary(
        uniqueKeysWithValues: itemsByAddress.values.map { item in
            var next = item
            next.isConnecting = address == item.address
            next.isConnected = item.address == connectedAddress
            return (next.address, next)
        }
    )
    if let address = address {
        scanState = .connecting(address)
    } else if case .connecting = scanState {
        scanState = .stopped
    }
    onSnapshotChanged?()
}
```

- [ ] **Step 5: 编译检查本任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 编译通过，或只出现与本任务无关的既有 warning。

- [ ] **Step 6: Commit**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugModels.swift SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
git commit -m "feat: track connected debug proxy row"
```

---

### Task 2: 改造 DebugBluetoothSession 生命周期

**Files:**
- Modify: `SunSmart/Main/Space/Debug/DebugBluetoothSession.swift`
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

- [ ] **Step 1: 检查当前断开逻辑**

Run:

```bash
sed -n '30,95p' SunSmart/Main/Space/Debug/DebugBluetoothSession.swift
sed -n '155,175p' SunSmart/Main/Space/Debug/DebugBluetoothSession.swift
```

Expected: 看到 `prepare()` 调用了 `meshNetworkDisconnect()` 和 `setMeshNetworkConnected(... connected: false)`，`finish()` 调用了 `close()` 和 `meshNetworkDisconnect()`。

- [ ] **Step 2: 修改 `prepare` 签名和进入行为**

把 `prepare` 改成回传当前已连接节点，不再断开当前 Proxy。

```swift
func prepare(completion: @escaping (Bool, Node?) -> Void) {
    DispatchQueue.main.async {
        MeshLibManager.manager.stopRefreshNodesRSSI()
        let currentNode = self.currentConnectedNodeInSpace()
        self.connectedNode = currentNode

        guard let manager = MeshLibManager.manager.meshNetworkManager else {
            completion(false, currentNode)
            return
        }

        manager.loadExtensionData { result in
            DispatchQueue.main.async {
                completion(result, currentNode)
            }
        }
    }
}
```

- [ ] **Step 3: 增加当前连接节点 helper**

在 `DebugBluetoothSession` 中增加 helper，只把当前 Space 的真实节点视为 Debug 已连接行。

```swift
func currentConnectedNodeInSpace() -> Node? {
    guard let node = MeshLibManager.manager.currentProxy?.node else {
        return nil
    }
    guard MeshNetworkManager.instance.realNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
        return nil
    }
    return node
}
```

- [ ] **Step 4: 手动切换前断开当前 Proxy**

修改 `connect(_:, completion:)`：如果目标已经是当前 Proxy，直接成功；否则手动断开当前 Proxy 后连接目标。这里使用 `close()`，因为可能存在 `currentProxy?.node` 缺失或不属于当前 Space 的情况；不要调用 `meshNetworkDisconnect()`。

```swift
func connect(_ item: SpaceDebugNodeItem, completion: @escaping (Bool) -> Void) {
    stopScan()

    if MeshLibManager.manager.currentProxy?.node?.primaryUnicastAddress == item.node.primaryUnicastAddress {
        connectedNode = item.node
        completion(true)
        return
    }

    if MeshLibManager.manager.currentProxy != nil {
        MeshLibManager.manager.close()
    }

    connectedNode = item.node
    isConnecting = true
    MeshLibManager.manager.connectProxy(node: item.node, peripheral: item.peripheral) { [weak self] success in
        DispatchQueue.main.async {
            self?.isConnecting = false
            if !success {
                self?.connectedNode = self?.currentConnectedNodeInSpace()
            } else {
                self?.connectedNode = item.node
            }
            completion(success)
        }
    }
}
```

- [ ] **Step 5: 调整重连行为**

保持设备页手动重连能力，但成功后刷新 `connectedNode`。

```swift
func reconnect(completion: @escaping (Bool) -> Void) {
    guard let node = connectedNode else {
        completion(false)
        return
    }
    isConnecting = true
    MeshLibManager.manager.connectProxy(node: node) { [weak self] success in
        DispatchQueue.main.async {
            self?.isConnecting = false
            if success {
                self?.connectedNode = node
            }
            completion(success)
        }
    }
}
```

- [ ] **Step 6: 修改 `finish()` 不断开仍可用 Proxy**

退出 Debug 时只停止 Debug 自己的扫描和 UART，不调用 `close()` 或 `meshNetworkDisconnect()`。

```swift
func finish() {
    guard !isEnding else {
        return
    }
    isEnding = true
    stopUARTMessages()
    clearUARTMessages()
    stopScan()
    connectedNode = nil
    meshConnectionObservation = nil
}
```

- [ ] **Step 7: Proxy 自然断开时阻止调试页内自动连接**

修改 `observeMeshConnection()` 的断开处理：当 Debug 正在运行且不是手动连接中，通知页面后调用 `close()` 停止 SDK 自动扫描替换 Proxy。此时 Proxy 已经断开，`close()` 用于停止自动连接流程，不是主动断开可用 Proxy。

```swift
private func observeMeshConnection() {
    meshConnectionObservation = MeshLibManager.manager.observe(\.isMeshNetworkConnected, options: [.new]) { [weak self] _, _ in
        guard let self = self else {
            return
        }
        DispatchQueue.main.async {
            guard !self.isEnding,
                  !self.isConnecting,
                  !MeshLibManager.manager.isMeshNetworkConnected,
                  let node = self.connectedNode else {
                return
            }
            self.connectedNode = nil
            self.onUnexpectedDisconnect?(node)
            MeshLibManager.manager.close()
        }
    }
}
```

- [ ] **Step 8: 更新 `prepareAndStartScan()` 调用签名**

在 `SpaceDebugViewController.prepareAndStartScan()` 中把 `session.prepare` 的 completion 改成接收当前连接节点，并写入 ViewModel。列表断开处理会在 Task 3 完整补齐，这一步只消除签名变更带来的编译错误。

```swift
session.prepare { [weak self] success, connectedNode in
    guard let self = self else {
        return
    }
    self.viewModel.replaceNodes(MeshNetworkManager.instance.realNodes)
    self.viewModel.setConnectedNode(connectedNode)
    guard self.viewModel.currentScanState == .preparing else {
        return
    }
    if success, self.viewModel.totalCount > 0 {
        self.startScan(reset: false)
    } else {
        self.viewModel.setScanState(.stopped)
        self.navigationItem.rightBarButtonItem?.title = "scan".localizedString
    }
}
```

- [ ] **Step 9: 编译检查本任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 编译通过，或只出现与本任务无关的既有 warning。

- [ ] **Step 10: Commit**


```bash
git add SunSmart/Main/Space/Debug/DebugBluetoothSession.swift SunSmart/Main/Space/Debug/SpaceDebugViewController.swift
git commit -m "feat: preserve proxy during debug session"
```

---

### Task 3: 更新 Debug 列表页面交互

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugViewController.swift`

- [ ] **Step 1: 完善 `prepareAndStartScan()` 的列表断开处理**

在 Task 2 已更新的 `session.prepare` completion 中加入 `installListDisconnectHandler()`，确保进入列表后由列表页接管断开事件。

```swift
session.prepare { [weak self] success, connectedNode in
    guard let self = self else {
        return
    }
    self.viewModel.replaceNodes(MeshNetworkManager.instance.realNodes)
    self.viewModel.setConnectedNode(connectedNode)
    self.installListDisconnectHandler()
    guard self.viewModel.currentScanState == .preparing else {
        return
    }
    if success, self.viewModel.totalCount > 0 {
        self.startScan(reset: false)
    } else {
        self.viewModel.setScanState(.stopped)
        self.navigationItem.rightBarButtonItem?.title = "scan".localizedString
    }
}
```

- [ ] **Step 2: 列表页恢复时安装断开处理**

增加 `viewWillAppear`，从设备页返回列表时重新接管列表断开处理。

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    installListDisconnectHandler()
    viewModel.setConnectedNode(session.currentConnectedNodeInSpace())
}
```

新增 handler。列表页收到自然断开后只更新 UI，不触发自动连接。

```swift
private func installListDisconnectHandler() {
    session.onUnexpectedDisconnect = { [weak self] node in
        guard let self = self else {
            return
        }
        if self.viewModel.currentScanState == .connecting(node.primaryUnicastAddress) {
            self.viewModel.setConnecting(address: nil)
        }
        self.viewModel.clearConnectedNode()
    }
}
```

- [ ] **Step 3: 调整扫描按钮重置行为**

保留当前连接态，`resetFoundState()` 已在 Task 1 处理连接状态。确认 `scanButtonTapped()` 不新增断开逻辑。

```swift
@objc private func scanButtonTapped() {
    switch viewModel.currentScanState {
    case .scanning, .preparing:
        stopScan()
    case .idle, .stopped:
        startScan(reset: true)
    case .connecting:
        break
    }
}
```

- [ ] **Step 4: 改造点击设备行**

替换 `connect(_:)`。已连接行直接进入详情；未扫描到行直接返回；未连接但 found 的行执行连接。

```swift
private func connect(_ item: SpaceDebugNodeItem) {
    if item.isConnected {
        stopScan()
        let detail = SpaceDebugDeviceViewController(session: session, space: space, item: item)
        navigationController?.pushViewController(detail, animated: true)
        return
    }

    guard item.isFound else {
        return
    }

    stopScan()
    viewModel.setConnecting(address: item.address)
    navigationItem.rightBarButtonItem?.isEnabled = false
    session.connect(item) { [weak self] success in
        guard let self = self else {
            return
        }
        self.viewModel.setConnecting(address: nil)
        self.navigationItem.rightBarButtonItem?.isEnabled = true
        if success {
            self.viewModel.setConnectedAddress(item.address)
            let detailItem = self.viewModel.item(address: item.address) ?? item
            let detail = SpaceDebugDeviceViewController(session: self.session, space: self.space, item: detailItem)
            self.navigationController?.pushViewController(detail, animated: true)
        } else {
            self.viewModel.setConnectedNode(self.session.currentConnectedNodeInSpace())
            self.showConnectionFailedAlert()
        }
    }
}
```

- [ ] **Step 5: 从详情页返回列表时保持停止扫描**

不在 `viewWillAppear` 自动调用 `startScan`。确认文件里没有新增这类代码。

Run:

```bash
rg -n "viewWillAppear|startScan\\(" SunSmart/Main/Space/Debug/SpaceDebugViewController.swift
```

Expected: `viewWillAppear` 只安装 handler 和刷新连接态，不调用 `startScan`。

- [ ] **Step 6: 编译检查本任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 编译通过，或只出现与本任务无关的既有 warning。

- [ ] **Step 7: Commit**

```bash
git add SunSmart/Main/Space/Debug/DebugBluetoothSession.swift SunSmart/Main/Space/Debug/SpaceDebugViewController.swift SunSmart/Main/Space/Debug/SpaceDebugViewModel.swift
git commit -m "feat: reuse proxy in debug device list"
```

---

### Task 4: 更新 Debug 设备行展示

**Files:**
- Modify: `SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift`

- [ ] **Step 1: 调整状态文案优先级**

在 `update(item:)` 中按 `Connecting`、`Connected`、`Found`、`Not Found` 的顺序设置状态。

```swift
if item.isConnecting {
    statusLabel.text = "connecting".localizedString
} else if item.isConnected {
    statusLabel.text = "debug_connected".localizedString
} else {
    statusLabel.text = item.isFound ? "debug_found".localizedString : "debug_not_found".localizedString
}
```

- [ ] **Step 2: 调整图标和可点击样式**

已连接行使用在线图标并可点击；未扫描到且未连接行置灰。

```swift
let active = item.isConnected || item.isFound
iconImageView.image = UIImage(named: active ? item.node.iconName : item.node.offlineIconName)

let enabled = item.isAvailable && !item.isConnecting
contentView.alpha = enabled ? 1.0 : 0.45
selectionStyle = enabled ? .gray : .none
isUserInteractionEnabled = enabled
```

- [ ] **Step 3: 保持 RSSI 展示逻辑**

不为 `Connected` 强制伪造 RSSI。当前 Proxy 有 RSSI 就展示，没有则 `--`。

```swift
if let rssi = item.rssi {
    signalStrengthView.setSignalStrength(rssi: rssi)
    rssiLabel.text = "\(rssi)dBm"
} else {
    signalStrengthView.setSignalStrength(rssi: -120)
    rssiLabel.text = "--"
}
```

- [ ] **Step 4: 编译检查本任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 编译通过。

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Main/Space/Debug/SpaceDebugDeviceCell.swift
git commit -m "feat: show connected debug proxy row"
```

---

### Task 5: 调整退出 Debug 后 Space 恢复逻辑

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1: 检查当前退出回调**

Run:

```bash
sed -n '1000,1015p' SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected: `openSpaceDebug()` 的 `onFlowFinished` 无条件调用 `setNetworkConnected()`。

- [ ] **Step 2: 避免当前 Proxy 仍连接时重建连接**

新增一个小 helper，让 Debug 退出时只在 Mesh 未连接时恢复自动连接；如果当前 Proxy 仍连接，正常控制直接复用。

```swift
private func restoreMeshConnectionAfterDebug() {
    guard !MeshLibManager.manager.isMeshNetworkConnected else {
        return
    }
    setNetworkConnected()
}
```

修改 `openSpaceDebug()`。

```swift
private func openSpaceDebug() {
    let vc = SpaceDebugViewController(space: space) { [weak self] in
        self?.restoreMeshConnectionAfterDebug()
    }
    navigationController?.pushViewController(vc, animated: true)
}
```

- [ ] **Step 3: 确认不引入新的自动连接入口**

Run:

```bash
rg -n "setNetworkConnected\\(|meshNetworkDisconnect\\(|MeshLibManager\\.manager\\.close\\(" SunSmart/Main/Space/Debug SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected:
- `DebugBluetoothSession.prepare()` 不再有 `meshNetworkDisconnect()`。
- `DebugBluetoothSession.finish()` 不再有 `meshNetworkDisconnect()`。
- `SpaceViewController` 只有退出 Debug 后的条件恢复逻辑。

- [ ] **Step 4: 编译检查本任务**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 编译通过。

- [ ] **Step 5: Commit**

```bash
git add SunSmart/Main/Space/Controller/SpaceViewController.swift
git commit -m "fix: restore mesh connection after debug only when needed"
```

---

### Task 6: 最终验证与手工验收

**Files:**
- Review only: `SunSmart/Main/Space/Debug/*.swift`
- Review only: `SunSmart/Main/Space/Controller/SpaceViewController.swift`

- [ ] **Step 1: 检查最终 diff**

Run:

```bash
git diff HEAD~4..HEAD -- SunSmart/Main/Space/Debug SunSmart/Main/Space/Controller/SpaceViewController.swift
```

Expected:
- Debug 进入不再主动断开当前 Proxy。
- Debug 退出不再主动 `meshNetworkDisconnect()`。
- 已连接行有 `Connected` 状态。
- 未扫描到行仍不可点击。

- [ ] **Step 2: 执行 SunSmart 编译**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 共享文件 target 风险检查**

Run:

```bash
rg -n "SpaceDebugModels.swift in Sources|SpaceDebugViewModel.swift in Sources|DebugBluetoothSession.swift in Sources|SpaceDebugViewController.swift in Sources|SpaceDebugDeviceCell.swift in Sources" SunSmart.xcodeproj/project.pbxproj
```

Expected: 这些 Debug 文件仍然存在于 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 的 Sources 列表；本次不需要修改 target 配置。

- [ ] **Step 4: 手工验收：进入 Debug 前已有 Proxy**

Manual:

1. 进入一个有设备的 Space，等待正常控制连接到 Proxy Node。
2. 打开右上角菜单并进入 `Debug`。
3. 观察当前 Proxy 对应设备行。

Expected:
- 进入 Debug 时 Proxy 不掉线。
- 对应行显示 `Connected`。
- 其它扫描到的设备显示 RSSI。
- 未扫描到设备置灰不可点。

- [ ] **Step 5: 手工验收：点击已连接行**

Manual:

1. 在 Debug 列表点击 `Connected` 行。
2. 进入调试设备页。

Expected:
- 不出现连接等待。
- 直接进入设备页。
- 设备页连接状态为 `Connected`。

- [ ] **Step 6: 手工验收：手动切换到其它已扫描设备**

Manual:

1. 返回 Debug 列表。
2. 点击一个显示 RSSI 且不是当前 Proxy 的设备行。

Expected:
- 当前 Proxy 先断开。
- 目标设备连接成功后进入调试设备页。
- 返回列表后目标行显示 `Connected`。

- [ ] **Step 7: 手工验收：调试页内 Proxy 自然断开**

Manual:

1. 在 Debug 页连接某个 Proxy。
2. 让该设备断电或离开连接范围。
3. 停留在 Debug 页观察。

Expected:
- Debug 页不自动连接新的 Proxy Node。
- 当前连接状态消失或设备页弹出断开提示。
- 只有用户点击已扫描到设备行时才开始新的连接。

- [ ] **Step 8: 手工验收：返回列表后扫描**

Manual:

1. 从调试设备页返回 Debug 列表。
2. 点击右上角 `Scan`。

Expected:
- 扫描继续更新 RSSI。
- 当前 Proxy 若仍连接，不被断开。
- 未扫描到的未连接设备仍不可点击。

- [ ] **Step 9: 手工验收：退出 Debug 回 Space**

Manual:

1. 从 Debug 列表返回 Space。
2. 观察正常控制页连接状态。

Expected:
- 如果当前 Proxy 仍连接，Space 继续复用该连接。
- 如果 Debug 内 Proxy 已断开，Space 恢复自动连接 Proxy Node。

- [ ] **Step 10: 最终提交**

如果 Task 1-5 由于中间编译依赖合并提交，最后确认提交历史清晰。

```bash
git status --short
git log --oneline -6
```

Expected:
- 工作树干净。
- 最近提交包含 Debug Proxy 生命周期相关改动。
