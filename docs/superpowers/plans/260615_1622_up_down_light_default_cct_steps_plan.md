# Up Down Light CCT Default Steps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `CID 0x0A78 / PID 0x2491` up down light 在添加、restore、replace 成功后读取并保存 `CCT default steps`，让 `Absolute CCT Range` 默认值和 Reset 有设备返回值作为根值。

**Architecture:** SDK 负责 `0x53 / 0x01` GET/RET 的类型化编码解析，并把 steps 作为 `Node` 本地持久化属性参与 `defaultAbsoluteCctRange` 计算。App 侧新增一个共享 post-add reader，Classic Add、Professional Add、Restore / Replace 都在完成通知前调用它，读取失败时保存 fallback steps `5` 并继续原流程。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK Swift Package、XCTest、SIG Mesh Vendor Message、SQLite-backed SDK node property persistence。

---

## File Map

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`
  - 覆盖 `CCT default steps` GET 编码、RET 解析、失败和非法返回。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`
  - 覆盖 `[0x53, 0x01]` 与 `[0x53, 0x02]` response matching 不串包。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
  - 覆盖 `0x2491` steps `5/6` 到默认 CCT range 的映射，以及显式 `absoluteCctRange` 优先级。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - 新增 `VendorFunctionGet.upDownLightDefaultCctSteps` 编码。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 新增 `VendorUpDownLightCode.defaultCctSteps`、`ResponseCode.upDownLightDefaultCctSteps`、`FunctionParameters.upDownLightDefaultCctSteps(UInt8)` 与解析。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
  - 新增 `Node.upDownLightDefaultCctSteps` 本地属性和 `defaultAbsoluteCctRange` 映射。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`
  - 增加 SQLite column load/save/migration，持久化 steps。
- Create: `SunSmart/Main/Device/Model/UpDownLightDefaultCctStepsReader.swift`
  - 添加成功后的共享读取 helper。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
  - 在完成 callback 和通知前读取并保存 steps。
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
  - 同 Classic，复用 reader。
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
  - Restore / Replace 完成通知前读取并保存新节点 steps。

---

### Task 1: SDK Failing Tests

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`

- [ ] **Step 1: Add protocol tests for default CCT steps**

Append these tests inside `UpDownLightVendorMessageTests` before `testUpDownLightAddsVendorModelSubscriptionForGroupControl()`:

```swift
func testUpDownLightDefaultCctStepsGetEncoding() {
    XCTAssertEqual(
        SunricherVendorGet(function: .upDownLightDefaultCctSteps).parameters,
        Data([0x53, 0x01])
    )
}

func testUpDownLightDefaultCctStepsStatusParsing() {
    let steps5 = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x00, 0x05]))
    XCTAssertEqual(steps5?.status.isSuccessful, true)
    XCTAssertEqual(steps5?.status.code, .upDownLightDefaultCctSteps)
    if case .upDownLightDefaultCctSteps(let steps) = steps5?.status.parameters {
        XCTAssertEqual(steps, 5)
    } else {
        XCTFail("Expected up down light default CCT steps 5")
    }

    let steps6 = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x00, 0x06]))
    XCTAssertEqual(steps6?.status.isSuccessful, true)
    XCTAssertEqual(steps6?.status.code, .upDownLightDefaultCctSteps)
    if case .upDownLightDefaultCctSteps(let steps) = steps6?.status.parameters {
        XCTAssertEqual(steps, 6)
    } else {
        XCTFail("Expected up down light default CCT steps 6")
    }

    let setError = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x01, 0x05]))
    XCTAssertEqual(setError?.status.isSuccessful, false)
    XCTAssertEqual(setError?.status.errorCode, 0x01)
    XCTAssertNil(setError?.status.parameters)

    let shortStatus = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x00]))
    XCTAssertEqual(shortStatus?.status.isSuccessful, false)
    XCTAssertNil(shortStatus?.status.parameters)

    let invalidStatus = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x00, 0x07]))
    XCTAssertEqual(invalidStatus?.status.isSuccessful, false)
    XCTAssertNil(invalidStatus?.status.parameters)
}
```

- [ ] **Step 2: Add response matching test**

Append this test inside `MeshMessageHandleResponseMatchingTests` after `testUpDownLightVendorStatusMustMatchCurrentVendorCommandCode()`:

```swift
func testUpDownLightDefaultCctStepsVendorStatusMustMatchCurrentVendorCommandCode() {
    let defaultStepsHandle = MeshMessageHandle(
        message: SunricherVendorGet(function: .upDownLightDefaultCctSteps),
        address: 0x0003
    )
    let defaultStepsStatus = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x00, 0x05]))!
    let upRatioStatus = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x00, 0x32]))!

    XCTAssertTrue(defaultStepsHandle.matchesResponse(defaultStepsStatus, from: 0x0003))
    XCTAssertFalse(defaultStepsHandle.matchesResponse(upRatioStatus, from: 0x0003))
}
```

- [ ] **Step 3: Replace fixed 0x2491 CCT default test with steps-based tests**

In `NodeCctDefaultValueTests.swift`, replace `testUpDownLightKeepsTunableWhiteDefaultAndUsesNarrowCctRange()` and `testConfiguredAbsoluteCctRangeOverridesUpDownLightDefault()` with:

```swift
func testUpDownLightKeepsTunableWhiteDefaultAndUsesFiveStepCctRangeByDefault() {
    let node = makeNode(productIdentifier: 0x2491)

    XCTAssertFalse(node.isSingleWhiteDefaultCctProduct)
    XCTAssertEqual(node.defaultChangeControlPage, .tunableWhite)
    XCTAssertEqual(node.effectiveChangeControlPage, .tunableWhite)
    XCTAssertEqual(node.upDownLightDefaultCctSteps, 5)
    XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
    XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
}

func testUpDownLightSixDefaultCctStepsUsesStandardCctRange() {
    let node = makeNode(productIdentifier: 0x2491)
    node.upDownLightDefaultCctSteps = 6

    XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
    XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.standardDefaultRange)
}

func testUpDownLightInvalidDefaultCctStepsFallsBackToFiveStepRange() {
    let node = makeNode(productIdentifier: 0x2491)
    node.upDownLightDefaultCctSteps = 7

    XCTAssertEqual(node.upDownLightDefaultCctSteps, 5)
    XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
    XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
}

func testConfiguredAbsoluteCctRangeOverridesUpDownLightDefaultSteps() {
    let node = makeNode(productIdentifier: 0x2491)
    node.upDownLightDefaultCctSteps = 6
    node.absoluteCctRange = 3000...4500

    XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
    XCTAssertEqual(node.effectiveCctRange, 3000...4500)
}
```

- [ ] **Step 4: Run SDK tests to verify failure**

Run:

```bash
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter UpDownLightVendorMessageTests
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter MeshMessageHandleResponseMatchingTests/testUpDownLightDefaultCctStepsVendorStatusMustMatchCurrentVendorCommandCode
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter NodeCctDefaultValueTests
```

Expected:

- First command fails because `.upDownLightDefaultCctSteps` does not exist.
- Second command fails because `.upDownLightDefaultCctSteps` does not exist.
- Third command fails because `Node.upDownLightDefaultCctSteps` does not exist.

- [ ] **Step 5: Commit failing tests**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "test: cover up down light CCT default steps"
```

---

### Task 2: SDK Vendor Protocol Implementation

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: Add GET function mapping**

In `SunricherVendorGet.swift`, add a command mapping:

```swift
case .upDownLightDefaultCctSteps: return .upDownLightDefaultCctSteps
```

Place it next to `.upDownLightUpRatio`.

Add the enum case near the existing up down light GET case:

```swift
/// 获取 up down light 的 CCT default steps。
case upDownLightDefaultCctSteps
```

- [ ] **Step 2: Add status code enums**

In `SunricherVendorStatus.swift`, update `VendorUpDownLightCode`:

```swift
/// CCT default steps
case defaultCctSteps = 0x01
/// Up ratio
case upRatio = 0x02
```

In the `ResponseCode.init?(parameters:)` up down light switch, add:

```swift
case VendorUpDownLightCode.defaultCctSteps.rawValue:
    self = .upDownLightDefaultCctSteps
```

Add `ResponseCode` case near `.upDownLightUpRatio`:

```swift
/// Up down light CCT default steps
case upDownLightDefaultCctSteps
```

Add `ResponseCode.code` mapping:

```swift
case .upDownLightDefaultCctSteps:
    return [VendorOpCode.upDownLight.rawValue, VendorUpDownLightCode.defaultCctSteps.rawValue]
```

- [ ] **Step 3: Add function parameter case**

In `FunctionParameters`, add:

```swift
/// Up down light CCT default steps
case upDownLightDefaultCctSteps(UInt8)
```

- [ ] **Step 4: Parse default CCT steps response**

In `SunricherVendorStatus.init(parameters:)`, add this branch next to `.upDownLightUpRatio`:

```swift
case .upDownLightDefaultCctSteps:
    guard isSuccessful, data.count >= 4 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    let steps: UInt8 = data.read(fromOffset: 3)
    guard steps == 5 || steps == 6 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    self.parameters = .upDownLightDefaultCctSteps(steps)
```

- [ ] **Step 5: Run protocol tests**

Run:

```bash
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter UpDownLightVendorMessageTests
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter MeshMessageHandleResponseMatchingTests/testUpDownLightDefaultCctStepsVendorStatusMustMatchCurrentVendorCommandCode
```

Expected: both commands pass.

- [ ] **Step 6: Commit SDK protocol implementation**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add up down light CCT default steps protocol"
```

---

### Task 3: SDK Node Persistence And Default Range

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`

- [ ] **Step 1: Add Node associated key and property**

In `Node+Propertys.swift`, add an associated key:

```swift
static var upDownLightDefaultCctSteps: UInt8 = 0
```

Add the property in `public extension Node` near `absoluteCctRange`:

```swift
var upDownLightDefaultCctSteps: UInt8 {
    get {
        objc_getAssociatedObject(self, &AssociatedKeys.upDownLightDefaultCctSteps) as? UInt8 ?? 5
    } set {
        let normalizedValue: UInt8 = newValue == 6 ? 6 : 5
        objc_setAssociatedObject(self, &AssociatedKeys.upDownLightDefaultCctSteps, normalizedValue, .OBJC_ASSOCIATION_RETAIN)
    }
}
```

- [ ] **Step 2: Update defaultAbsoluteCctRange**

Replace `defaultAbsoluteCctRange` with:

```swift
var defaultAbsoluteCctRange: ClosedRange<UInt16> {
    if supportsUpDownRatioControl {
        return upDownLightDefaultCctSteps == 6
            ? NodeAbsoluteCctRange.standardDefaultRange
            : NodeAbsoluteCctRange.singleWhiteDefaultRange
    }
    return isNarrowDefaultCctRangeProduct ? NodeAbsoluteCctRange.singleWhiteDefaultRange : NodeAbsoluteCctRange.standardDefaultRange
}
```

- [ ] **Step 3: Add database column**

In `MeshDatabase.swift`, add an expression key in the node properties expression section:

```swift
static let upDownLightDefaultCctSteps = Expression<Int?>("upDownLightDefaultCctSteps")
```

Add it to the create-table builder with other optional node property columns:

```swift
builder.column(PropertyExpressionKey.upDownLightDefaultCctSteps)
```

Add a migration check near the other `absoluteCctRange` migrations:

```swift
// 是否存在“upDownLightDefaultCctSteps”属性
if !columns.contains(where: { $0.name == "upDownLightDefaultCctSteps" }) {
    _ = try? database?.run(Node.nodePropertysTable.addColumn(PropertyExpressionKey.upDownLightDefaultCctSteps))
}
```

- [ ] **Step 4: Load and save steps**

In the node property row-to-node load section, add:

```swift
if let steps = row[PropertyExpressionKey.upDownLightDefaultCctSteps] {
    self.upDownLightDefaultCctSteps = steps == 6 ? 6 : 5
}
```

In the node property setters passed to insert/update, add:

```swift
PropertyExpressionKey.upDownLightDefaultCctSteps <- Int(self.upDownLightDefaultCctSteps),
```

- [ ] **Step 5: Run node default tests**

Run:

```bash
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter NodeCctDefaultValueTests
```

Expected: pass.

- [ ] **Step 6: Run focused SDK tests**

Run:

```bash
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter UpDownLightVendorMessageTests
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter MeshMessageHandleResponseMatchingTests/testUpDownLightDefaultCctStepsVendorStatusMustMatchCurrentVendorCommandCode
```

Expected: pass.

- [ ] **Step 7: Commit node persistence**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: persist up down light CCT default steps"
```

---

### Task 4: App Shared Default Steps Reader

**Files:**
- Create: `SunSmart/Main/Device/Model/UpDownLightDefaultCctStepsReader.swift`

- [ ] **Step 1: Create shared reader**

Create `SunSmart/Main/Device/Model/UpDownLightDefaultCctStepsReader.swift`:

```swift
//
//  UpDownLightDefaultCctStepsReader.swift
//  SunSmart
//
//  Created by Codex on 2026/6/15.
//

import Foundation
import NordicSigMeshSDK

enum UpDownLightDefaultCctStepsReader {
    private static let fallbackSteps: UInt8 = 5

    static func readAndSave(
        for nodes: [Node],
        timeout: TimeInterval = 7,
        completion: @escaping () -> Void
    ) {
        let targetNodes = nodes.filter { $0.supportsUpDownRatioControl }
        guard !targetNodes.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        targetNodes.forEach { node in
            group.enter()
            readAndSave(for: node, timeout: timeout) {
                group.leave()
            }
        }

        group.notify(queue: .main, execute: completion)
    }

    private static func readAndSave(
        for node: Node,
        timeout: TimeInterval,
        completion: @escaping () -> Void
    ) {
        guard let vendorModel = node.sunricherVendorModel else {
            save(fallbackSteps, for: node)
            completion()
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorGet(function: .upDownLightDefaultCctSteps),
            model: vendorModel,
            timeout: timeout
        ) { response in
            let steps: UInt8
            if let status = response as? SunricherVendorStatus,
               status.status.isSuccessful,
               case .upDownLightDefaultCctSteps(let value) = status.status.parameters {
                steps = value
            } else {
                steps = fallbackSteps
            }
            save(steps, for: node)
            completion()
        }
    }

    private static func save(_ steps: UInt8, for node: Node) {
        node.upDownLightDefaultCctSteps = steps
        _ = node.savePropertys()
    }
}
```

- [ ] **Step 2: Compile-check reader**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: if SDK tasks are complete, build progresses past `UpDownLightDefaultCctStepsReader.swift`. If it fails because the new file is not in target membership, add the file to `SunSmart.xcodeproj/project.pbxproj` under the `SunSmart` shared source target using the same group/source build phase pattern as nearby `SunSmart/Main/Device/Model/*.swift` files, then rerun.

- [ ] **Step 3: Commit reader**

```bash
git add SunSmart/Main/Device/Model/UpDownLightDefaultCctStepsReader.swift SunSmart.xcodeproj/project.pbxproj
git commit -m "feat: add up down light CCT default steps reader"
```

If `SunSmart.xcodeproj/project.pbxproj` did not change, omit it from `git add`.

---

### Task 5: App Add And Restore Integration

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Modify: `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`

- [ ] **Step 1: Wrap Classic add completion**

In `DeviceAddClassicModeController.swift`, inside `addFinish` after `finishGroupDeferredSyncPlans(successDevices:)` completes, wrap the existing final body with:

```swift
self.finishGroupDeferredSyncPlans(successDevices: successList) { [weak self] in
    guard let self = self else { return }
    UpDownLightDefaultCctStepsReader.readAndSave(for: self.addSuccessNodes) { [weak self] in
        guard let self = self else { return }
        self.deviceStateCallback?(false)
        self.deviceAddCallback?(self.addSuccessNodes)

        self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
        self.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count
        self.space.switchesCount = MeshNetworkManager.instance.switchs.count
        self.space.save()
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
        NotificationCenter.default.post(name: .init(devicesAddNotificationName), object: nil)
        if self.addSuccessNodes.contains(where: { [.dongle, .gateway, .emergencyController, .unknown].contains($0.deviceType) }) {
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        }
        if self.addSuccessNodes.contains(where: { $0.deviceType == .emergencyController }) {
            NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
        }
        if self.addSuccessNodes.contains(where: { $0.isPowerSwitch }) {
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
    }
}
```

- [ ] **Step 2: Wrap Professional add completion**

In `DeviceAddProfessionalModeController.swift`, wrap its `addFinish` final body with `UpDownLightDefaultCctStepsReader.readAndSave`:

```swift
self.finishGroupDeferredSyncPlans(successDevices: successList) { [weak self] in
    guard let self = self else { return }
    UpDownLightDefaultCctStepsReader.readAndSave(for: self.addSuccessNodes) { [weak self] in
        guard let self = self else { return }
        self.deviceAddCallback?(self.addSuccessNodes)
        self.deviceStateCallback?(false)

        self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
        self.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count
        self.space.switchesCount = MeshNetworkManager.instance.switchs.count
        self.space.save()
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
        NotificationCenter.default.post(name: .init(devicesAddNotificationName), object: nil)
        if self.addSuccessNodes.contains(where: { [.dongle, .gateway, .emergencyController, .unknown].contains($0.deviceType) }) {
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        }
        if self.addSuccessNodes.contains(where: { $0.deviceType == .emergencyController }) {
            NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
        }
        if self.addSuccessNodes.contains(where: { $0.isPowerSwitch }) {
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
    }
}
```

The reader must run before both callbacks and notifications.

- [ ] **Step 3: Split restore completion into pre-read and post-read phases**

In `DeviceRestoreViewController.swift`, replace `finishDeviceRestoreAdd(successList:failList:)` with these two methods:

```swift
private func finishDeviceRestoreAdd(
    successList: [ProvisioningDevice],
    failList: [ProvisioningDevice]
) {
    UpDownLightDefaultCctStepsReader.readAndSave(for: restoreNodes) { [weak self] in
        self?.finishDeviceRestoreAddAfterDefaultCctStepsRead(
            successList: successList,
            failList: failList
        )
    }
}

private func finishDeviceRestoreAddAfterDefaultCctStepsRead(
    successList: [ProvisioningDevice],
    failList: [ProvisioningDevice]
) {
    // 添加完成后检查是否有设备需要同步
    let needSyncNodes = restoreNodes.filter({
        shouldMarkRestoredNodeSyncFailed($0, phase: .batchFinish)
    })
    if needSyncNodes.count > 0 {
        needSyncNodes.forEach({ node in
            if let device = successList.first(where: { $0.address == node.primaryUnicastAddress }) {
                device.addState = .syncFailed
            }
        })
        tableView.reloadData()
        updateUIState()
    }

    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))

    let addedBatteryPowerSwitchNodes = restoreNodes.filter { $0.isBatteryPowerSwitch }
    finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(
        fallbackDisconnectNodes: addedBatteryPowerSwitchNodes
    )

    // 是否自动化恢复流程
    if automationRestore {
        if failList.count > 0 && automationRetryCount > 0 {
            automationRetryCount -= 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self = self, self.automationRestore else { return }
                self.addSelectedBtnClick()
            }
        } else {
            // 恢复设备后是否有同步失败的设备
            if allDevices.contains(where: { $0.addState == .syncFailed }) {
                syncBtnAction()
            } else {
                dismiss()
            }
        }
    }
}
```

This ensures restore / replace saves the new device default steps before space changed notification and automation flow continuation.

- [ ] **Step 4: Static check integration points**

Run:

```bash
rg -n "UpDownLightDefaultCctStepsReader.readAndSave" SunSmart/Main/Device/Controller SunSmart/Main/Device/Model
```

Expected output includes exactly these controller files:

```text
SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift
SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift
SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
```

- [ ] **Step 5: Build app**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 6: Commit app integration**

```bash
git add SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift
git commit -m "feat: read up down light CCT default steps after add"
```

---

### Task 6: Final Verification

**Files:**
- Verify only; no expected source edits.

- [ ] **Step 1: Run SDK focused tests**

Run:

```bash
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter UpDownLightVendorMessageTests
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter MeshMessageHandleResponseMatchingTests/testUpDownLightDefaultCctStepsVendorStatusMustMatchCurrentVendorCommandCode
swift test --package-path /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk --filter NodeCctDefaultValueTests
```

Expected: all pass.

- [ ] **Step 2: Run app static checks**

Run:

```bash
rg -n "upDownLightDefaultCctSteps|upDownLightDefaultCctSteps\\(|defaultCctSteps|UpDownLightDefaultCctStepsReader" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources SunSmart
rg -n "UpDownLightDefaultCctStepsReader.readAndSave" SunSmart/Main/Device/Controller
git diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
```

Expected:

- SDK search shows protocol enum, parser, node property, database load/save.
- App search shows reader and three controller call sites.
- Both diff checks produce no output.

- [ ] **Step 3: Run iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 4: Review diffs**

Run:

```bash
git diff --stat
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --stat
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected:

- App repo only contains the reader and three add/restore controller changes, unless `project.pbxproj` was needed for target membership.
- SDK repo only contains vendor protocol, node persistence/defaults, and tests.
- No unrelated files are modified.

- [ ] **Step 5: Final summary**

Report:

- SDK test commands and pass/fail result.
- iPhoneOS build result.
- App commit hash for reader/integration commits.
- SDK commit hashes for protocol/persistence commits.
- Any verification that could not be run and why.
