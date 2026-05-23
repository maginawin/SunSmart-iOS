# Battery Power Switch ACK And Target Group Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Battery Power Switch 切换 Profile 后 App 显示配置成功但设备不能控制的问题，并避免未变化 target groups 被错误加入任务列表。

**Architecture:** 在 SDK 消息调度层补齐 ACK 与当前命令的精确匹配，避免同一节点同一 response opCode 的 Vendor/Publication ACK 串位导致假成功。App 侧 BPS target group 同步恢复差异语义，只对缺失订阅、真实删除和 obsolete cleanup 生成任务。

**Tech Stack:** Swift、NordicSigMeshSDK Swift Package、SunSmart iOS UIKit 工程、BLE Mesh Config/Vendor 消息。

---

### Task 1: SDK ACK 匹配测试

**Files:**
- Create: `../../../nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`
- Modify: `../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift`

- [ ] **Step 1: 写失败测试**

新增测试覆盖：

```swift
import XCTest
@testable import NordicSigMeshSDK

final class MeshMessageHandleResponseMatchingTests: XCTestCase {

    func testVendorStatusMustMatchCurrentVendorCommandCode() {
        let resetHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchResetDefaults),
            address: 0x0003
        )
        let keyConfigStatus = SunricherVendorStatus(parameters: Data([0x4C, 0x00, 0x00]))!
        let resetStatus = SunricherVendorStatus(parameters: Data([0x4C, 0x01, 0x00, 0x08, 0x05, 0x02]))!

        XCTAssertFalse(resetHandle.matchesResponse(keyConfigStatus, from: 0x0003))
        XCTAssertTrue(resetHandle.matchesResponse(resetStatus, from: 0x0003))
    }

    func testPublicationStatusMustMatchCurrentPublicationModel() {
        let network = MeshNetwork(name: "Test", provisioner: Provisioner(name: "Tester", allocatedUnicastRange: [AddressRange(0x0001...0x199A)], allocatedGroupRange: [], allocatedSceneRange: []))
        let node = Node(
            name: "Node",
            unicastAddress: 0x0003,
            elements: [
                Element(
                    name: "Element",
                    location: .unknown,
                    models: [
                        Model(sigModelId: .genericOnOffClientModelId),
                        Model(sigModelId: .genericLevelClientModelId)
                    ]
                )
            ]
        )
        network.add(node: node)
        let appKey = ApplicationKey(name: "App Key", index: 0, key: Data(repeating: 1, count: 16))
        network.add(applicationKey: appKey)
        MeshNetworkManager.instance.meshNetwork = network

        let element = node.elements[0]
        let onOffModel = element.model(withSigModelId: .genericOnOffClientModelId)!
        let levelModel = element.model(withSigModelId: .genericLevelClientModelId)!
        let publish = Publish(to: MeshAddress(0xC123), using: appKey, usingFriendshipMaterial: false, ttl: 5, period: .disabled, retransmit: .disabled)
        let onOffMessage = ConfigModelPublicationSet(publish, to: onOffModel)!
        let levelStatus = ConfigModelPublicationStatus(responseTo: ConfigModelPublicationSet(publish, to: levelModel)!, with: publish)
        let onOffStatus = ConfigModelPublicationStatus(responseTo: onOffMessage, with: publish)
        let handle = MeshMessageHandle(message: onOffMessage, address: node.primaryUnicastAddress)

        XCTAssertFalse(handle.matchesResponse(levelStatus, from: node.primaryUnicastAddress))
        XCTAssertTrue(handle.matchesResponse(onOffStatus, from: node.primaryUnicastAddress))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter MeshMessageHandleResponseMatchingTests`

Expected: 编译失败或测试失败，因为 `MeshMessageHandle.matchesResponse(_:from:)` 尚不存在。

### Task 2: SDK ACK 匹配实现

**Files:**
- Modify: `../../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift`

- [ ] **Step 1: 增加匹配 helper**

在 `public extension MeshMessageHandle` 中新增：

```swift
func matchesResponse(_ response: MeshMessage, from source: Address) -> Bool {
    guard responseOpCode == response.opCode,
          allAddresss.contains(source),
          !isFinished else {
        return false
    }

    if let vendorStatus = response as? SunricherVendorStatus {
        return matchesVendorStatus(vendorStatus)
    }

    if let publicationStatus = response as? ConfigModelPublicationStatus,
       let request = message as? ConfigAnyModelMessage {
        return publicationStatus.elementAddress == request.elementAddress &&
            publicationStatus.modelIdentifier == request.modelIdentifier &&
            publicationStatus.companyIdentifier == request.companyIdentifier
    }

    return true
}
```

并增加私有 helper 匹配 `SunricherVendorSet/Get` 的 `responseCommand`。

- [x] **Step 2: 使用 helper 替换收到响应时的粗匹配**

把 `MeshProxyMessageCommand` 中收到消息时的 `first(where:)` 条件替换为：

```swift
sendMessageHandles.first(where: { $0.matchesResponse(message, from: node.primaryUnicastAddress) })
```

发送失败回调拿到的是“发出去的消息”而不是“收到的响应”，不能复用 `matchesResponse(_:from:)`；该路径继续按 outgoing acknowledged message 的 response opCode 和目标节点定位 handle。

- [ ] **Step 3: 运行 SDK 测试确认通过**

Run: `swift test --filter MeshMessageHandleResponseMatchingTests`

Expected: PASS。当前 CLI `swift test` 在本地 SDK 包会先因 iOS-only `UIKit` 依赖无法在 macOS SwiftPM 测试环境编译而中断，因此实际通过 App iOS build 覆盖 SDK 编译链路。

### Task 3: BPS Target Group 差异同步

**Files:**
- Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- Modify: `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`

- [ ] **Step 1: 修改任务生成**

在 `makeBatteryPowerSwitchTargetGroupModel` 中，订阅方向改为默认差异语义：

```swift
let handles = unsubscribe
    ? node.getBatteryPowerSwitchUnsubscriptionMessageHandles(switchGroup: switchGroup)
    : node.getBatteryPowerSwitchSubscriptionMessageHandles(switchGroup: switchGroup)
```

- [ ] **Step 2: 修改实际下发**

在 `.batteryPowerSwitchTargetSubscription` 的 `messageHandles` 分支中移除 `includeExisting: true`：

```swift
messageHandles.append(contentsOf: node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(switchData: switchData, unsubscribe: unsubscribe))
```

- [ ] **Step 3: 静态检查**

Run: `rg -n "batteryPowerSwitchTargetSubscription|getBatteryPowerSwitchSubscriptionMessageHandles\\(switchGroup: switchGroup, includeExisting: true\\)" SunSmart/Main/Space`

Expected: target subscription 下发路径不再使用 `includeExisting: true`；reset 后 model publication 仍保留 `includeExisting: true`。

### Task 4: Verification

**Files:**
- Verify only.

- [ ] **Step 1: SDK 单测**

Run: `swift test --filter MeshMessageHandleResponseMatchingTests`

Expected: PASS。

- [ ] **Step 2: App 构建**

Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 3: 最终检查**

Run: `git diff --check`

Expected: 无输出。
