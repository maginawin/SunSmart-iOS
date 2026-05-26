# Battery Power Switch Fire And Forget Reset Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除真实 Battery Power Switch 时，`ConfigNodeReset()` 必须在本地移除 node 之前真实交给 mesh access layer 发送，同时保持不等待 `ConfigNodeResetStatus` 的删除语义。

**Architecture:** 在本地 `NordicSigMeshSDK` 增加一个不等待 response 的 config message 发送路径，由 `MeshAPI.resetNodeWithoutWaitingForStatus(address:)` 包装。SunSmart BPS 删除代码改用该 API，而不是把 reset 放进 `MeshMessageManager` 队列，避免队列稍后发送时目标 node 已被 `forceRemove`。

**Tech Stack:** Swift 5.8、Swift Package `NordicSigMeshSDK`、Bluetooth Mesh `ConfigNodeReset`、UIKit app target `SunSmart`。

---

### Task 1: Add Failing SDK API Test

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshAPIResetNodeWithoutWaitingTests.swift`

- [x] **Step 1: Write the failing test**

```swift
import XCTest
@testable import NordicSigMeshSDK

final class MeshAPIResetNodeWithoutWaitingTests: XCTestCase {

    func testResetNodeWithoutWaitingForStatusThrowsWhenMeshNetworkIsMissing() {
        XCTAssertThrowsError(
            try MeshAPI.resetNodeWithoutWaitingForStatus(address: 0x0003)
        ) { error in
            XCTAssertTrue(error is MeshNetworkError)
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter MeshAPIResetNodeWithoutWaitingTests`

Expected: FAIL because `MeshAPI.resetNodeWithoutWaitingForStatus(address:)` does not exist.

Actual: `swift test` did not reach the missing API failure because the existing SwiftPM build compiles for macOS and fails on SDK code that imports `UIKit`.

### Task 2: Add SDK Fire-And-Forget Config Send Path

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/MeshNetworkManager+Callbacks.swift`

- [x] **Step 1: Allow config sends without reliable response context**

Change `AccessLayer.send(_ message: ConfigMessage, ...)` to accept `awaitResponse: Bool = true`.

```swift
func send(_ message: ConfigMessage,
          from element: Element, to destination: Address,
          withTtl initialTtl: UInt8?,
          awaitResponse: Bool = true) {
    ...
    if awaitResponse {
        createReliableContext(for: pdu, sentFrom: element, withTtl: initialTtl, using: keySet)
    }
    networkManager.upperTransportLayer.send(pdu, withTtl: initialTtl, using: keySet)
}
```

- [x] **Step 2: Add NetworkManager fire-and-forget config send**

Add an internal method that inserts `outgoingMessages`, calls `accessLayer.send(..., awaitResponse: false)`, and returns immediately.

```swift
@discardableResult
func sendWithoutWaitingForResponse(_ configMessage: AcknowledgedConfigMessage,
                                   from element: Element,
                                   to destination: Address,
                                   withTtl initialTtl: UInt8?) throws -> MessageHandle {
    let meshAddress = MeshAddress(destination)
    let busy = mutex.sync {
        guard !outgoingMessages.contains(meshAddress) else {
            return true
        }
        outgoingMessages.insert(meshAddress)
        return false
    }
    guard !busy else {
        throw AccessError.busy
    }
    accessLayer.send(configMessage, from: element, to: destination, withTtl: initialTtl, awaitResponse: false)
    return MessageHandle(for: configMessage, sentFrom: element.unicastAddress, to: meshAddress, using: self)
}
```

- [x] **Step 3: Add MeshNetworkManager validation wrapper**

Add `MeshNetworkManager.sendWithoutWaitingForResponse(...)` with the same destination, source, key, device key and TTL validation used by the existing acknowledged config send method, then call the new `NetworkManager` method.

### Task 3: Add Public MeshAPI Wrapper

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshAPI.swift`

- [x] **Step 1: Add public reset API**

```swift
@discardableResult
public static func resetNodeWithoutWaitingForStatus(address: Address, defaultTTL: UInt8? = nil) throws -> MessageHandle {
    try MeshNetworkManager.instance.sendWithoutWaitingForResponse(ConfigNodeReset(), to: address, withTtl: defaultTTL)
}
```

- [x] **Step 2: Run the SDK test**

Run: `swift test --filter MeshAPIResetNodeWithoutWaitingTests`

Expected: PASS.

Actual: blocked by the same existing SwiftPM/macOS `UIKit` compile error; iOS `xcodebuild` is used as the effective compile verification.

### Task 4: Use New API In BPS Delete

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/sun-smart/.worktrees/k8-switch-260519/SunSmart/Common/Data/MeshNetwork+SunSmart.swift`

- [x] **Step 1: Replace queued reset send**

Change `silentlyResetBatteryPowerSwitchIfNeeded(_:)` to:

```swift
private func silentlyResetBatteryPowerSwitchIfNeeded(_ node: Node?) {
    guard let node else {
        return
    }
    do {
        try MeshAPI.resetNodeWithoutWaitingForStatus(address: node.primaryUnicastAddress)
    } catch {
        print("Failed to send Battery Power Switch reset node: \(error)")
    }
}
```

- [x] **Step 2: Verify no queued BPS reset remains**

Run: `rg -n "MeshAPI\.sendMessage\(message: ConfigNodeReset\(\)" SunSmart ../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib`

Expected: no BPS delete usage remains.

### Task 5: Verification

**Files:**
- Verify SDK tests.
- Verify iOS build for `SunSmart`.

- [x] **Step 1: Run focused SDK test**

Run: `swift test --filter MeshAPIResetNodeWithoutWaitingTests`

Expected: PASS.

Actual: blocked by existing SwiftPM/macOS `UIKit` compile error.

- [x] **Step 2: Run broader SDK tests if feasible**

Run: `swift test`

Expected: PASS. If unrelated tests fail, capture exact failure.

Actual: skipped after focused `swift test` showed the package cannot compile for macOS because SDK sources import `UIKit`.

- [x] **Step 3: Build SunSmart**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.

Actual: BUILD SUCCEEDED.

---

## Self-Review

- Spec coverage: addresses the observed `Unknown destination Node` by avoiding queued reset before local node removal.
- Scope: only SDK reset send path and BPS delete call site change.
- Placeholder scan: no TODO/TBD placeholders.
- Type consistency: public API returns `MessageHandle` and throws `Error`, matching existing send APIs.
