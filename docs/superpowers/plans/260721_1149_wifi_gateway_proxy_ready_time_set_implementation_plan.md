# WiFi Gateway Proxy Ready 后 Time Set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 每个 Proxy/GATT 会话完成 Proxy Filter 后发送一次手机当前 Date-Time 和时区，并在结束后再启动页面自动 WiFi 请求。

**Architecture:** NordicSigMeshSDK 在 Proxy Filter 真值点发布带节点地址和稳定会话 ID 的通用 `ProxyReadyContext`，并保留当前有效快照。App 共享 Gateway 基类只负责把匹配当前节点的 Ready 上下文转交给窄 Hook；WiFi Gateway 使用跨页面共享的协调器按会话去重，并用页面级门闩串行化 Time Set 与自动 WiFi 状态加载。

**Tech Stack:** Swift 5、UIKit、NordicSigMeshSDK、Bluetooth Mesh Time Model、Swift Package XCTest、现有 shell/`swiftc` 聚焦测试、Xcode iPhoneOS 构建。

## Global Constraints

- 只影响 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway；其他 Gateway 子类保持现状。
- Time Set 必须发生在 Proxy Filter 完成之后、自动 `43 12`/`43 0E` 请求之前。
- 时间消息在发送时使用 `Node.setLocalTimeMessage()`，其数据源为发送时 `Date()` 和 `TimeZone.current`。
- 每个 Proxy/GATT 会话最多尝试一次；同会话失败不立即重试，新会话允许重试。
- 成功、失败、超时、Key Bind 未完成或缺少 Time Setup Model 都必须放行页面；旧会话和其他节点事件只能忽略，不能放行当前会话。
- App 不发送 `TimeRoleGet` 或 `TimeRoleSet`，不改变固件决定的 Time Role。
- 不新增用户可见 HUD、Alert、Toast 或本地化文案。
- SDK 事件必须保持通用，不包含 CID/PID 或 WiFi Gateway 业务判断。
- App 已通过 `XCLocalSwiftPackageReference` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`；实施时保留该本地依赖，不重复切换。
- 新增 App Swift 文件必须加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
- 不修改 WiFi 私有协议格式，不顺手重构其他 Gateway、DFU 或 Mesh 消息发送逻辑。
- 日志不得输出 AppKey、NetKey、WiFi 密码或其他 Auth 信息。
- App 与 SDK 是两个 Git 仓库；每个任务只提交本任务对应仓库的聚焦变更。

---

## File Structure

### NordicSigMeshSDK 仓库

- Create: `Sources/NordicSigMeshSDK/MeshLib/Manager/ProxyReadyContext.swift` — 通用 Ready 上下文及线程安全会话注册表。
- Modify: `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift` — 观察者 API、当前快照，以及 GATT 打开/Proxy Filter 完成/断开时的生命周期接线。
- Create: `Tests/NordicSigMeshSDKTests/ProxyReadyRegistryTests.swift` — 会话稳定性、快照替换和失效测试。

### SunSmart App 仓库

- Create: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift` — 纯会话门闩和运行时 Time Set 协调器。
- Create: `Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift` — 不依赖 UIKit/SDK 的会话门闩聚焦测试。
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift` — 订阅通用 Proxy Ready，并提供默认空 Hook。
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` — 接入时间同步前置阶段并门控自动 WiFi 请求。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — 将协调器加入四个 App target。
- Create: `scripts/check_wifi_gateway_time_sync.sh` — 聚焦测试和架构静态守卫。

---

### Task 1: SDK Proxy 会话注册表

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/ProxyReadyRegistryTests.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/ProxyReadyContext.swift`

**Interfaces:**
- Consumes: SDK 的 `Address` 类型和 Foundation `UUID`/`ObjectIdentifier`。
- Produces: `public struct ProxyReadyContext: Equatable`；内部 `ProxyReadyRegistry.beginSession(for:)`、`markReady(for:nodeAddress:)`、`closeSession(for:)`、`invalidateAll()` 和 `currentContext`。

- [ ] **Step 1: 写会话注册表失败测试**

创建 `ProxyReadyRegistryTests.swift`：

```swift
import XCTest
@testable import NordicSigMeshSDK

final class ProxyReadyRegistryTests: XCTestCase {
    private final class BearerToken {}
    private var retainedBearers: [BearerToken] = []

    private func makeBearerID() -> ObjectIdentifier {
        let bearer = BearerToken()
        retainedBearers.append(bearer)
        return ObjectIdentifier(bearer)
    }

    func testRepeatedReadyForSameBearerKeepsSessionID() {
        let registry = ProxyReadyRegistry()
        let bearerID = makeBearerID()

        registry.beginSession(for: bearerID)
        let first = registry.markReady(for: bearerID, nodeAddress: 0x1201)
        let second = registry.markReady(for: bearerID, nodeAddress: 0x1201)

        XCTAssertEqual(first, second)
        XCTAssertEqual(registry.currentContext, first)
    }

    func testNewBearerCreatesNewSessionAndReplacesSnapshot() {
        let registry = ProxyReadyRegistry()
        let firstBearerID = makeBearerID()
        let secondBearerID = makeBearerID()

        let first = registry.markReady(for: firstBearerID, nodeAddress: 0x1201)
        let second = registry.markReady(for: secondBearerID, nodeAddress: 0x1202)

        XCTAssertNotEqual(first.sessionID, second.sessionID)
        XCTAssertEqual(registry.currentContext, second)
    }

    func testClosingOldBearerDoesNotClearCurrentSnapshot() {
        let registry = ProxyReadyRegistry()
        let oldBearerID = makeBearerID()
        let currentBearerID = makeBearerID()

        _ = registry.markReady(for: oldBearerID, nodeAddress: 0x1201)
        let current = registry.markReady(for: currentBearerID, nodeAddress: 0x1202)
        registry.closeSession(for: oldBearerID)

        XCTAssertEqual(registry.currentContext, current)
    }

    func testClosingCurrentBearerClearsSnapshot() {
        let registry = ProxyReadyRegistry()
        let bearerID = makeBearerID()

        _ = registry.markReady(for: bearerID, nodeAddress: 0x1201)
        registry.closeSession(for: bearerID)

        XCTAssertNil(registry.currentContext)
    }

    func testInvalidateAllClearsEverySession() {
        let registry = ProxyReadyRegistry()
        let bearerID = makeBearerID()

        let oldContext = registry.markReady(for: bearerID, nodeAddress: 0x1201)
        registry.invalidateAll()

        XCTAssertNil(registry.currentContext)
        let newContext = registry.markReady(for: bearerID, nodeAddress: 0x1201)
        XCTAssertNotEqual(oldContext.sessionID, newContext.sessionID)
    }
}
```

- [ ] **Step 2: 运行测试并确认因类型不存在而失败**

Run:

```bash
swift test --filter ProxyReadyRegistryTests
```

Expected: FAIL，错误包含 `cannot find 'ProxyReadyRegistry' in scope` 或 `cannot find type 'ProxyReadyContext' in scope`。

- [ ] **Step 3: 实现最小线程安全注册表**

创建 `ProxyReadyContext.swift`：

```swift
import Foundation

public struct ProxyReadyContext: Equatable {
    public let nodeAddress: Address
    public let sessionID: UUID

    public init(nodeAddress: Address, sessionID: UUID) {
        self.nodeAddress = nodeAddress
        self.sessionID = sessionID
    }
}

final class ProxyReadyRegistry {
    private let lock = NSLock()
    private var sessionIDs: [ObjectIdentifier: UUID] = [:]
    private var currentBearerID: ObjectIdentifier?
    private var storedCurrentContext: ProxyReadyContext?

    var currentContext: ProxyReadyContext? {
        lock.lock()
        defer { lock.unlock() }
        return storedCurrentContext
    }

    @discardableResult
    func beginSession(for bearerID: ObjectIdentifier) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        if let sessionID = sessionIDs[bearerID] {
            return sessionID
        }
        let sessionID = UUID()
        sessionIDs[bearerID] = sessionID
        return sessionID
    }

    @discardableResult
    func markReady(for bearerID: ObjectIdentifier, nodeAddress: Address) -> ProxyReadyContext {
        lock.lock()
        defer { lock.unlock() }
        let sessionID = sessionIDs[bearerID] ?? UUID()
        sessionIDs[bearerID] = sessionID
        let context = ProxyReadyContext(nodeAddress: nodeAddress, sessionID: sessionID)
        currentBearerID = bearerID
        storedCurrentContext = context
        return context
    }

    func closeSession(for bearerID: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        sessionIDs.removeValue(forKey: bearerID)
        if currentBearerID == bearerID {
            currentBearerID = nil
            storedCurrentContext = nil
        }
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        sessionIDs.removeAll()
        currentBearerID = nil
        storedCurrentContext = nil
    }
}
```

- [ ] **Step 4: 运行聚焦测试并确认通过**

Run:

```bash
swift test --filter ProxyReadyRegistryTests
```

Expected: `ProxyReadyRegistryTests` 5 个测试全部 PASS，0 failures。

- [ ] **Step 5: 提交 SDK 注册表**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Manager/ProxyReadyContext.swift Tests/NordicSigMeshSDKTests/ProxyReadyRegistryTests.swift
git commit -m "feat: add proxy ready session context"
```

---

### Task 2: SDK Proxy Ready 观察者与生命周期接线

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:30-67`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:396-438`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:1214-1297`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:1579-1634`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift:1658-1665`

**Interfaces:**
- Consumes: Task 1 的 `ProxyReadyContext` 和 `ProxyReadyRegistry`。
- Produces: `MeshLibManager.GlobalProxyReadyObserver`、`currentProxyReadyContext`、`addGlobalProxyReadyObserver(_:)`、`removeGlobalProxyReadyObserver(_:)`。

- [ ] **Step 1: 在现有注册表测试中加入公共上下文等值契约测试**

在 `ProxyReadyRegistryTests` 增加：

```swift
func testPublicContextEqualityIncludesAddressAndSession() {
    let sessionID = UUID()
    XCTAssertEqual(
        ProxyReadyContext(nodeAddress: 0x1201, sessionID: sessionID),
        ProxyReadyContext(nodeAddress: 0x1201, sessionID: sessionID)
    )
    XCTAssertNotEqual(
        ProxyReadyContext(nodeAddress: 0x1201, sessionID: sessionID),
        ProxyReadyContext(nodeAddress: 0x1202, sessionID: sessionID)
    )
}
```

- [ ] **Step 2: 在 `MeshLibManager` 增加观察者存储与只读快照**

在现有 Global observer 属性旁加入：

```swift
public typealias GlobalProxyReadyObserver = (_ context: ProxyReadyContext) -> Void
private let proxyReadyRegistry = ProxyReadyRegistry()
private var globalProxyReadyObservers: [UUID: GlobalProxyReadyObserver] = [:]
private let globalProxyReadyObserversLock = NSLock()

public var currentProxyReadyContext: ProxyReadyContext? {
    proxyReadyRegistry.currentContext
}
```

在 `addGlobalConnectionObserver` 附近加入完整 API：

```swift
@discardableResult
public func addGlobalProxyReadyObserver(_ observer: @escaping GlobalProxyReadyObserver) -> UUID {
    let id = UUID()
    globalProxyReadyObserversLock.lock()
    globalProxyReadyObservers[id] = observer
    globalProxyReadyObserversLock.unlock()
    return id
}

public func removeGlobalProxyReadyObserver(_ id: UUID?) {
    guard let id else { return }
    globalProxyReadyObserversLock.lock()
    globalProxyReadyObservers.removeValue(forKey: id)
    globalProxyReadyObserversLock.unlock()
}

private func currentGlobalProxyReadyObservers() -> [GlobalProxyReadyObserver] {
    globalProxyReadyObserversLock.lock()
    let observers = Array(globalProxyReadyObservers.values)
    globalProxyReadyObserversLock.unlock()
    return observers
}

private func publishProxyReady(_ context: ProxyReadyContext) {
    let observers = currentGlobalProxyReadyObservers()
    guard !observers.isEmpty else { return }
    delegateQueue.async {
        observers.forEach { $0(context) }
    }
}
```

- [ ] **Step 3: 把 GATT 会话打开、Ready 和失效接到注册表**

在 `bearerDidOpen(_:)` 入口加入：

```swift
if let proxyBearer = bearer as? GattBearer {
    proxyReadyRegistry.beginSession(for: ObjectIdentifier(proxyBearer))
}
```

在 `bearer(_:didClose:)` 入口加入：

```swift
if let proxyBearer = bearer as? GattBearer {
    proxyReadyRegistry.closeSession(for: ObjectIdentifier(proxyBearer))
}
```

将 `proxyFilterUpdated` 的目标 Proxy 解析和发布顺序调整为：

```swift
guard let readyProxy = connection?.proxies.last,
      let nodeAddress = MeshNetworkManager.instance.proxyFilter.proxy?.primaryUnicastAddress else {
    return
}
readyProxy.nodeAddress = nodeAddress

self.whitelistConfigTimer?.invalidate()
self.whitelistConfigTimer = nil

if self.isMeshNetworkConnected,
   (connection?.proxies.count ?? 0) > 1 {
    connection?.disconnectCurrent()
    if self.delegate != nil, let meshNetworkManager = self.meshNetworkManager {
        self.delegateQueue.async {
            self.delegate?.meshNetworkManager(
                meshNetworkManager,
                proxyDidReplace: (self.currentProxy ?? self.connection)!
            )
        }
    }
}

let readyContext = proxyReadyRegistry.markReady(
    for: ObjectIdentifier(readyProxy),
    nodeAddress: nodeAddress
)
publishProxyReady(readyContext)

if self.isMeshNetworkConnected {
    return
}
```

保留后续首次连接的 `updateMeshNetworkConnectionState(true)`、delegate 和 heartbeat 逻辑，不复制也不提前返回这些语句。

在蓝牙关闭分支中，在连接状态更新前加入：

```swift
proxyReadyRegistry.invalidateAll()
```

在 `close()` 调用 `connection?.close()` 前加入同样的同步失效，确保页面读取不到等待 didClose 的旧快照：

```swift
proxyReadyRegistry.invalidateAll()
connection?.close()
```

- [ ] **Step 4: 运行 SDK 聚焦测试和完整测试**

Run:

```bash
swift test --filter ProxyReadyRegistryTests
swift test
```

Expected: 聚焦测试 6 个测试 PASS；完整 `NordicSigMeshSDKTests` 0 failures。

- [ ] **Step 5: 构建 SDK Demo 的 iPhoneOS target**

Run:

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshDemo -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: 提交 SDK 生命周期接线**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift Tests/NordicSigMeshSDKTests/ProxyReadyRegistryTests.swift
git commit -m "feat: publish proxy ready lifecycle"
```

---

### Task 3: App 会话去重协调器与聚焦测试

**Files:**
- Create: `Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift`
- Create: `SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: SDK `ProxyReadyContext`、`Node.timeSetupModel`、`Node.setLocalTimeMessage()`、`MeshAPI.sendMessage`。
- Produces: `WiFiGatewayTimeSyncSessionGate`；`WiFiGatewayTimeSyncCoordinator.shared.synchronize(context:node:completion:)`；结果 `completed`、`skipped`、`failed`、`ignored`。

- [ ] **Step 1: 写会话去重失败测试**

创建 `WiFiGatewayTimeSyncCoordinatorTests.swift`：

```swift
import Foundation

@main
struct WiFiGatewayTimeSyncCoordinatorTests {
    static func main() {
        testFirstAttemptStartsAndDuplicateJoins()
        testFinishedSessionReturnsStoredResult()
        testNewSessionStartsAgain()
        print("WiFiGatewayTimeSyncCoordinatorTests passed")
    }

    private static func testFirstAttemptStartsAndDuplicateJoins() {
        var gate = WiFiGatewayTimeSyncSessionGate()
        let sessionID = UUID()
        precondition(gate.begin(sessionID: sessionID) == .start)
        precondition(gate.begin(sessionID: sessionID) == .join)
    }

    private static func testFinishedSessionReturnsStoredResult() {
        var gate = WiFiGatewayTimeSyncSessionGate()
        let sessionID = UUID()
        precondition(gate.begin(sessionID: sessionID) == .start)
        gate.finish(sessionID: sessionID, result: .success)
        precondition(gate.begin(sessionID: sessionID) == .finished(.success))
    }

    private static func testNewSessionStartsAgain() {
        var gate = WiFiGatewayTimeSyncSessionGate()
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        precondition(gate.begin(sessionID: firstSessionID) == .start)
        gate.finish(sessionID: firstSessionID, result: .failed)
        precondition(gate.begin(sessionID: secondSessionID) == .start)
    }
}
```

- [ ] **Step 2: 编译测试并确认类型不存在**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift -o /tmp/WiFiGatewayTimeSyncCoordinatorTests
```

Expected: FAIL，错误包含输入文件不存在或 `cannot find 'WiFiGatewayTimeSyncSessionGate' in scope`。

- [ ] **Step 3: 创建纯门闩和运行时协调器**

创建 `WiFiGatewayTimeSyncCoordinator.swift`。文件顶层先放可被 `swiftc` 独立验证的纯状态：

```swift
import Foundation

struct WiFiGatewayTimeSyncSessionGate {
    enum Result: Equatable {
        case success
        case skipped
        case failed
    }

    enum BeginDecision: Equatable {
        case start
        case join
        case finished(Result)
    }

    private var syncingSessions: Set<UUID> = []
    private var finishedSessions: [UUID: Result] = [:]

    mutating func begin(sessionID: UUID) -> BeginDecision {
        if let result = finishedSessions[sessionID] {
            return .finished(result)
        }
        if syncingSessions.contains(sessionID) {
            return .join
        }
        syncingSessions.insert(sessionID)
        return .start
    }

    mutating func finish(sessionID: UUID, result: Result) {
        syncingSessions.remove(sessionID)
        finishedSessions[sessionID] = result
        if finishedSessions.count > 16,
           let evictedSessionID = finishedSessions.keys.first(where: { $0 != sessionID }) {
            finishedSessions.removeValue(forKey: evictedSessionID)
        }
    }
}
```

随后在同一文件追加运行时实现；`#if canImport` 让独立 `swiftc` 只编译纯门闩：

```swift
#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK

final class WiFiGatewayTimeSyncCoordinator {
    enum Outcome {
        case completed
        case skipped
        case failed
        case ignored
    }

    typealias TimeSender = (_ message: TimeSet, _ model: Model, _ completion: @escaping (Bool) -> Void) -> Void

    static let shared = WiFiGatewayTimeSyncCoordinator()

    private var gate = WiFiGatewayTimeSyncSessionGate()
    private var waiters: [UUID: [(Outcome) -> Void]] = [:]
    private let timeSender: TimeSender

    init(timeSender: @escaping TimeSender = WiFiGatewayTimeSyncCoordinator.sendTime) {
        self.timeSender = timeSender
    }

    func synchronize(
        context: ProxyReadyContext,
        node: Node,
        completion: @escaping (Outcome) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let manager = MeshLibManager.manager
        guard Node.isWiFiGateway(
            companyIdentifier: node.companyIdentifier,
            productIdentifier: node.productIdentifier
        ),
        context.nodeAddress == node.primaryUnicastAddress,
        manager.currentProxyReadyContext == context,
        manager.currentProxy?.nodeAddress == context.nodeAddress else {
            completion(.ignored)
            return
        }

        switch gate.begin(sessionID: context.sessionID) {
        case .join:
            waiters[context.sessionID, default: []].append(completion)
        case .finished(let result):
            completion(outcome(for: result))
        case .start:
            waiters[context.sessionID] = [completion]
            guard node.isKeybindComplete, let model = node.timeSetupModel else {
                finish(context: context, result: .skipped, outcome: .skipped)
                return
            }
            let message = Node.setLocalTimeMessage()
            let timeZone = TimeZone.current
            print("WiFiGateway TimeSet start address=\(context.nodeAddress.hex) session=\(context.sessionID) timezone=\(timeZone.identifier) offset=\(timeZone.secondsFromGMT())")
            timeSender(message, model) { [weak self] success in
                DispatchQueue.main.async {
                    self?.finish(
                        context: context,
                        result: success ? .success : .failed,
                        outcome: success ? .completed : .failed
                    )
                }
            }
        }
    }

    private func finish(
        context: ProxyReadyContext,
        result: WiFiGatewayTimeSyncSessionGate.Result,
        outcome: Outcome
    ) {
        gate.finish(sessionID: context.sessionID, result: result)
        let callbacks = waiters.removeValue(forKey: context.sessionID) ?? []
        print("WiFiGateway TimeSet finish address=\(context.nodeAddress.hex) session=\(context.sessionID) result=\(result)")
        callbacks.forEach { $0(outcome) }
    }

    private func outcome(for result: WiFiGatewayTimeSyncSessionGate.Result) -> Outcome {
        switch result {
        case .success:
            return .completed
        case .skipped:
            return .skipped
        case .failed:
            return .failed
        }
    }

    private static func sendTime(
        message: TimeSet,
        model: Model,
        completion: @escaping (Bool) -> Void
    ) {
        MeshAPI.sendMessage(message: message, model: model, timeout: 10) { response in
            completion(response is TimeStatus)
        }
    }
}
#endif
```

- [ ] **Step 4: 运行独立门闩测试**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift -o /tmp/WiFiGatewayTimeSyncCoordinatorTests
/tmp/WiFiGatewayTimeSyncCoordinatorTests
```

Expected: 输出 `WiFiGatewayTimeSyncCoordinatorTests passed`。

- [ ] **Step 5: 把协调器加入四个 App target**

在 `SunSmart.xcodeproj/project.pbxproj` 增加以下文件和构建引用：

```text
C8F6A2012FA3000000000001 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A2052FA3000000000005 /* WiFiGatewayTimeSyncCoordinator.swift */; };
C8F6A2022FA3000000000002 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A2052FA3000000000005 /* WiFiGatewayTimeSyncCoordinator.swift */; };
C8F6A2032FA3000000000003 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A2052FA3000000000005 /* WiFiGatewayTimeSyncCoordinator.swift */; };
C8F6A2042FA3000000000004 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8F6A2052FA3000000000005 /* WiFiGatewayTimeSyncCoordinator.swift */; };
C8F6A2052FA3000000000005 /* WiFiGatewayTimeSyncCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WiFiGatewayTimeSyncCoordinator.swift; sourceTree = "<group>"; };
```

在 `C8F89D3B2E3CBCF800FA1544 /* Model */` 的 children 中加入：

```text
C8F6A2052FA3000000000005 /* WiFiGatewayTimeSyncCoordinator.swift */,
```

分别在四个 Sources phase 加入：

```text
/* C88553B12DE6B44C00C8B688 - Archipelago */
C8F6A2012FA3000000000001 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */,

/* C886E0012E30DE4900D0C3A6 - SylSmart */
C8F6A2022FA3000000000002 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */,

/* C896B9A02A930BA800217512 - SunSmart */
C8F6A2032FA3000000000003 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */,

/* C8BB65AF2ED3F056000C63EE - SLG Sync Plus */
C8F6A2042FA3000000000004 /* WiFiGatewayTimeSyncCoordinator.swift in Sources */,
```

完成后运行：

```bash
rg -n "WiFiGatewayTimeSyncCoordinator\.swift in Sources \*/," SunSmart.xcodeproj/project.pbxproj
```

Expected: 精确出现 4 条以 `in Sources */,` 结尾的 build phase 记录；四条 BuildFile 定义都指向同一个 FileReference。

- [ ] **Step 6: 提交 App 协调器基础**

```bash
git add SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add wifi gateway time sync coordinator"
```

---

### Task 4: Gateway 共享 Proxy Ready 窄 Hook

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:45-47`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:83-116`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:200-205`
- Modify: `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:1034-1043`

**Interfaces:**
- Consumes: Task 2 的 `MeshLibManager.addGlobalProxyReadyObserver` 和 `currentProxyReadyContext`。
- Produces: 子类可覆写的 `func gatewayProxyDidBecomeReady(_ context: ProxyReadyContext)`，默认空实现。

- [ ] **Step 1: 先在计划中的静态守卫命令验证 Hook 尚不存在**

Run:

```bash
rg -n "gatewayProxyDidBecomeReady|addGlobalProxyReadyObserver" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
```

Expected: 无匹配，命令退出码为 1。

- [ ] **Step 2: 注册观察者并处理晚订阅快照**

在属性区增加：

```swift
private var proxyReadyObserverID: UUID?
```

在 `viewDidLoad()` 中、`setNetworkConnected()` 之前调用：

```swift
registerProxyReadyObserver()
```

在控制器主体加入：

```swift
private func registerProxyReadyObserver() {
    proxyReadyObserverID = MeshLibManager.manager.addGlobalProxyReadyObserver { [weak self] context in
        self?.handleProxyReady(context)
    }
    if let context = MeshLibManager.manager.currentProxyReadyContext {
        handleProxyReady(context)
    }
}

private func handleProxyReady(_ context: ProxyReadyContext) {
    guard context.nodeAddress == node.primaryUnicastAddress else { return }
    gatewayProxyDidBecomeReady(context)
}
```

- [ ] **Step 3: 添加默认空 Hook 并清理观察者**

在现有 `gatewayOnlineStateDidUpdate` Hook 附近增加：

```swift
func gatewayProxyDidBecomeReady(_ context: ProxyReadyContext) {}
```

在 `deinit` 的 `MeshLibManager.manager.close()` 前增加：

```swift
MeshLibManager.manager.removeGlobalProxyReadyObserver(proxyReadyObserverID)
proxyReadyObserverID = nil
```

- [ ] **Step 4: 运行静态核验并构建 SunSmart**

Run:

```bash
rg -n "addGlobalProxyReadyObserver|currentProxyReadyContext|gatewayProxyDidBecomeReady|removeGlobalProxyReadyObserver" SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四类接线均有匹配；构建输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 提交共享 Hook**

```bash
git add SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift
git commit -m "feat: expose gateway proxy ready hook"
```

---

### Task 5: WiFi Gateway Time Set 前置门闩

**Files:**
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:45-69`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:92-115`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:220-230`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:272-278`
- Modify: `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:474-495`

**Interfaces:**
- Consumes: Task 3 的 `WiFiGatewayTimeSyncCoordinator`；Task 4 的 `gatewayProxyDidBecomeReady` Hook。
- Produces: `requestAutomaticWiFiLoad(forceReload:)`、`finishTimeSyncBarrier(context:outcome:)`；保证 Time Set 结束前不调用自动 `loadNetworkConnectivityFromGateway()` 或启动 RSSI 自动轮询。

- [ ] **Step 1: 在门闩测试中加入加载顺序测试**

在 `WiFiGatewayTimeSyncCoordinatorTests` 增加纯加载门闩测试调用：

```swift
testAutomaticLoadWaitsForTimeSync()
testIgnoredContextDoesNotOpenBarrier()
testNewSessionRequiresNewBarrier()
```

并加入实现：

```swift
private static func testAutomaticLoadWaitsForTimeSync() {
    var gate = WiFiGatewayAutomaticLoadGate()
    let sessionID = UUID()
    gate.request(forceReload: true)
    precondition(gate.markReady(sessionID: sessionID) == .reload)
    precondition(gate.markReady(sessionID: sessionID) == nil)
}

private static func testIgnoredContextDoesNotOpenBarrier() {
    var gate = WiFiGatewayAutomaticLoadGate()
    gate.request(forceReload: true)
    precondition(gate.pendingIntent == .reload)
    precondition(gate.consumeIfReady() == nil)
}

private static func testNewSessionRequiresNewBarrier() {
    var gate = WiFiGatewayAutomaticLoadGate()
    let firstSessionID = UUID()
    let secondSessionID = UUID()
    gate.request(forceReload: false)
    precondition(gate.markReady(sessionID: firstSessionID) == .resume)
    gate.request(forceReload: true)
    precondition(gate.consumeIfReady() == nil)
    precondition(gate.markReady(sessionID: secondSessionID) == .reload)
}
```

- [ ] **Step 2: 运行测试并确认加载门闩类型不存在**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift -o /tmp/WiFiGatewayTimeSyncCoordinatorTests
```

Expected: FAIL，错误包含 `cannot find 'WiFiGatewayAutomaticLoadGate' in scope`。

- [ ] **Step 3: 在协调器文件增加纯加载门闩**

把以下类型放在 `#if canImport(NordicSigMeshSDK)` 之前：

```swift
struct WiFiGatewayAutomaticLoadGate {
    enum Intent: Int, Equatable {
        case resume
        case reload
    }

    private(set) var pendingIntent: Intent?
    private var readySessionID: UUID?
    private var consumedSessionID: UUID?

    mutating func request(forceReload: Bool) {
        let intent: Intent = forceReload ? .reload : .resume
        if let pendingIntent, pendingIntent.rawValue >= intent.rawValue {
            return
        }
        pendingIntent = intent
    }

    mutating func markReady(sessionID: UUID) -> Intent? {
        if readySessionID != sessionID {
            readySessionID = sessionID
            consumedSessionID = nil
        }
        return consumeIfReady()
    }

    mutating func consumeIfReady() -> Intent? {
        guard let readySessionID,
              consumedSessionID != readySessionID,
              let pendingIntent else {
            return nil
        }
        self.pendingIntent = nil
        consumedSessionID = readySessionID
        return pendingIntent
    }

    mutating func resetForOffline() {
        pendingIntent = nil
        consumedSessionID = nil
    }
}
```

- [ ] **Step 4: 在 WiFi Gateway 页面接入 Hook 和协调器**

增加属性：

```swift
private let timeSyncCoordinator = WiFiGatewayTimeSyncCoordinator.shared
private var automaticLoadGate = WiFiGatewayAutomaticLoadGate()
private var activeTimeSyncContext: ProxyReadyContext?
```

覆写 Ready Hook：

```swift
override func gatewayProxyDidBecomeReady(_ context: ProxyReadyContext) {
    activeTimeSyncContext = context
    timeSyncCoordinator.synchronize(context: context, node: node) { [weak self] outcome in
        self?.finishTimeSyncBarrier(context: context, outcome: outcome)
    }
}

private func finishTimeSyncBarrier(
    context: ProxyReadyContext,
    outcome: WiFiGatewayTimeSyncCoordinator.Outcome
) {
    guard activeTimeSyncContext == context,
          MeshLibManager.manager.currentProxyReadyContext == context else {
        return
    }
    if case .ignored = outcome {
        return
    }
    if let intent = automaticLoadGate.markReady(sessionID: context.sessionID) {
        performAutomaticWiFiLoad(intent)
    }
}
```

- [ ] **Step 5: 将自动加载入口全部经过门闩**

增加统一入口：

```swift
private func requestAutomaticWiFiLoad(forceReload: Bool) {
    automaticLoadGate.request(forceReload: forceReload)
    if let intent = automaticLoadGate.consumeIfReady() {
        performAutomaticWiFiLoad(intent)
    }
}

private func performAutomaticWiFiLoad(_ intent: WiFiGatewayAutomaticLoadGate.Intent) {
    guard node.state, node.isKeybindComplete else {
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    if intent == .resume, networkConnectState == .connected {
        startWiFiRSSIStatusRefresh()
        return
    }
    guard !isNetworkOperationInProgress, !isWiFiRequestInProgress else { return }
    loadNetworkConnectivityFromGateway()
}
```

将 `viewWillAppear` 中直接 `startWiFiRSSIStatusRefresh()` / `loadNetworkConnectivityFromGateway()` 的分支替换为：

```swift
if node.state,
   !isNetworkOperationInProgress,
   !isWiFiRequestInProgress {
    requestAutomaticWiFiLoad(forceReload: false)
}
```

将 `gatewayOnlineStateDidUpdate` 改为：

```swift
override func gatewayOnlineStateDidUpdate(_ isOnline: Bool) {
    if !isOnline {
        automaticLoadGate.resetForOffline()
        activeTimeSyncContext = nil
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    guard node.isKeybindComplete else {
        hideNetworkConnectivityForOfflineGateway()
        return
    }
    requestAutomaticWiFiLoad(forceReload: true)
}
```

Time Set 进行期间不设置 `activeWiFiRequest`，但所有自动请求和自动 RSSI 启动均被 Ready 门闩挡住；用户可见区域尚未自动加载时没有新增 HUD 或提示。

- [ ] **Step 6: 运行门闩测试并确认通过**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift -o /tmp/WiFiGatewayTimeSyncCoordinatorTests
/tmp/WiFiGatewayTimeSyncCoordinatorTests
```

Expected: 输出 `WiFiGatewayTimeSyncCoordinatorTests passed`。

- [ ] **Step 7: 构建 SunSmart 验证真实 SDK 接口和控制器接线**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`；现有 `public extension Node` 已暴露 `timeSetupModel` 和 `setLocalTimeMessage()`，不得把 TimeSet 编码逻辑复制到 App。

- [ ] **Step 8: 提交 WiFi 页面串行化**

```bash
git add SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift
git commit -m "feat: sync wifi gateway time after proxy ready"
```

---

### Task 6: 聚焦守卫、全 target 构建和真机交付检查

**Files:**
- Create: `scripts/check_wifi_gateway_time_sync.sh`

**Interfaces:**
- Consumes: Tasks 1-5 的最终文件和项目接线。
- Produces: 一条可重复运行的 App 聚焦校验命令；不新增运行时代码接口。

- [ ] **Step 1: 创建聚焦检查脚本**

创建并赋予执行权限：

```bash
chmod +x scripts/check_wifi_gateway_time_sync.sh
```

脚本完整内容：

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

coordinator="SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift"
coordinator_test="Tests/Device/WiFiGatewayTimeSyncCoordinatorTests.swift"
gateway_controller="SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift"
wifi_controller="SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift"
project="SunSmart.xcodeproj/project.pbxproj"

swiftc -parse-as-library "$coordinator" "$coordinator_test" -o /tmp/WiFiGatewayTimeSyncCoordinatorTests
/tmp/WiFiGatewayTimeSyncCoordinatorTests

rg -n "addGlobalProxyReadyObserver|currentProxyReadyContext|gatewayProxyDidBecomeReady|removeGlobalProxyReadyObserver" "$gateway_controller" >/dev/null || fail "Gateway proxy ready hook wiring missing"
rg -n "override func gatewayProxyDidBecomeReady|timeSyncCoordinator\.synchronize|finishTimeSyncBarrier" "$wifi_controller" >/dev/null || fail "WiFi Gateway time sync hook missing"
rg -n "requestAutomaticWiFiLoad|performAutomaticWiFiLoad|automaticLoadGate" "$wifi_controller" >/dev/null || fail "Automatic WiFi load barrier missing"
rg -n "Node\.setLocalTimeMessage\(\)|TimeZone\.current|TimeStatus" "$coordinator" >/dev/null || fail "Current Date-Time/timezone acknowledged Time Set path missing"
rg -n "TimeRole(Get|Set)|TimeRoleSet|TimeRoleGet" "$coordinator" "$gateway_controller" "$wifi_controller" && fail "App must not configure Time Role"

source_membership_count="$(rg -c "WiFiGatewayTimeSyncCoordinator\.swift in Sources \*/," "$project" || true)"
[[ "$source_membership_count" == "4" ]] || fail "Coordinator must belong to all four App targets"

rg -n "XCLocalSwiftPackageReference.*nordic-sig-mesh-sdk|relativePath = \"/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk\"" "$project" >/dev/null || fail "App must keep local NordicSigMeshSDK reference during implementation"

echo "PASS: WiFi Gateway Proxy Ready Time Set checks"
```

- [ ] **Step 2: 运行 App 聚焦检查与既有 WiFi Gateway 回归脚本**

Run:

```bash
scripts/check_wifi_gateway_time_sync.sh
scripts/check_wifi_gateway_network_connectivity.sh
scripts/check_wifi_gateway_sig_mesh_status_header.sh
```

Expected: 三个脚本均输出 `PASS`，无 `FAIL`。

- [ ] **Step 3: 运行 SDK 最终验证**

在 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 运行：

```bash
swift test --filter ProxyReadyRegistryTests
git diff --check
git status --short
```

Expected: 聚焦测试 0 failures；`git diff --check` 无输出；工作区只包含本任务明确保留的改动，SDK 实施提交后应为空。

- [ ] **Step 4: 依次构建四个 App target**

在 App 仓库逐条运行，不使用 shell 包装、重定向或 Simulator：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四条命令分别输出 `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 检查代码差异和 Time Role 禁止项**

Run:

```bash
git diff --check
git diff --stat
rg -n "TimeRole(Get|Set)|TimeRoleSet|TimeRoleGet" SunSmart/Main/Device/Gateway
git status --short
```

Expected: `git diff --check` 无输出；Time Role 搜索无匹配；差异仅包含计划列出的 App 文件和原先保留的未跟踪分析报告。

- [ ] **Step 6: 真机验证消息顺序和会话边界**

按以下矩阵记录 App debug log 和 Mesh 抓包：

1. 首次进入页面：每个新 Proxy session 精确一条 `Time Set (0x5C)`，随后才出现 `43 12` 和 `43 0E`。
2. 同一会话退出再进入：协调器返回既有结果，不再发送 `0x5C`，页面仍能加载。
3. 断开再连接：session ID 改变，新会话重新发送一条 `0x5C`。
4. 从其他 Proxy 切换到目标网关：旧节点 Ready 被忽略，目标网关 Ready 后发送一条 `0x5C`。
5. Time Status 正常返回：记录 success，无用户 HUD，然后加载 WiFi 状态。
6. Time Set 超时/失败：记录 failed，无用户 HUD、不立即重试，然后加载 WiFi 状态。
7. 缺少 Time Setup Model 或 Key Bind 未完成：记录 skipped，不发送 Time Role，页面不被阻塞。
8. 手机切换时区后新建会话：抓包中的 Time Set 时区偏移与 `TimeZone.current.secondsFromGMT()` 一致。

Expected: 所有场景符合矩阵；抓包中没有 `Time Role Get/Set` opcode；日志不包含 WiFi 密码、AppKey 或 NetKey。

- [ ] **Step 7: 提交聚焦检查脚本**

```bash
git add scripts/check_wifi_gateway_time_sync.sh
git commit -m "test: guard wifi gateway time sync flow"
```

- [ ] **Step 8: 最终提交边界核验**

App 仓库运行：

```bash
git log --oneline -5
git status --short
```

SDK 仓库运行：

```bash
git log --oneline -4
git status --short
```

Expected: App 包含协调器、共享 Hook、页面串行化、守卫脚本四类聚焦提交；SDK 包含会话上下文和 Ready 生命周期两类聚焦提交；两个仓库均无意外修改。App 原有 `docs/260721_1036_timed_datetime_timezone_sync_analysis.md` 若仍未被用户要求提交，应继续保持未跟踪，不混入实现提交。

---

## Spec Coverage Self-Review

- Proxy Filter 真值点：Task 2 在 `proxyFilterUpdated` 发布 Ready，未使用原始 `connectProxy` completion。
- 通用 SDK 边界：Task 1-2 只使用节点地址和 session ID，不包含 CID/PID。
- 晚订阅：Task 2 提供 `currentProxyReadyContext`，Task 4 注册后立即读取快照。
- 目标节点匹配：Task 4 按单播地址过滤；Task 3 再校验型号、上下文和当前 Proxy。
- 每会话一次：Task 1 提供稳定会话 ID；Task 3 跨页面共享门闩并缓存终态。
- 发送时手机时间和时区：Task 3 在 `.start` 分支即时调用 `Node.setLocalTimeMessage()` 并记录 `TimeZone.current`。
- 无 Time Role：Global Constraints、Task 3 实现和 Task 6 禁止项共同覆盖。
- acknowledged 串行：Task 5 在 barrier 完成前拦截自动加载和 RSSI 自动启动，Task 6 抓包验证顺序。
- 失败不阻塞：Task 3 将 success/skipped/failed 都通知等待者；Task 5 仅 `ignored` 不放行。
- 旧会话不污染：Task 2 使快照失效；Task 5 在 completion 再比对 `activeTimeSyncContext` 和 SDK 当前快照。
- 其他 Gateway 不变：Task 4 Hook 默认空实现，只有 WiFi 子类覆写。
- 四 target：Task 3 增加 membership，Task 6 静态计数并执行四个 iPhoneOS build。
- 真机条件：Task 6 覆盖首次、重进、重连、切换、成功、失败、模型缺失和时区变化。
