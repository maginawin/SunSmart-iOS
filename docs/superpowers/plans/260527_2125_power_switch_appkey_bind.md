# Power Switch AppKey Bind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 AC Power Switch 与 Battery Power Switch 在添加成功后，对基础 5 个共同按键 Client Models 使用同一套 all-elements AppKey bind 逻辑，并让 AC required model bind 失败时添加失败。

**Architecture:** 在本地 `NordicSigMeshSDK` 的 `Node+SupportModels.swift` 中新增 Power Switch profile 能力层，用 PID 识别 `0x2A01` / `0x2A02` / `0x2A11` / `0x2A12`。`supportModels` 统一追加 Power Switch 基础 5 个 Client Models 的 all-elements 实例，`MeshFastAddDeviceManager` 的强失败判断从 Battery-only 改为 Power Switch required configuration；Battery Server 仅在 Battery PID 下作为额外 required model。

**Tech Stack:** Swift、NordicSigMeshSDK Swift Package、SwiftPM XCTest、Xcode workspace、多品牌 iOS target。

---

## 文件结构

- 新增 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift`：用 focused unit tests 锁定 AC/Battery Power Switch 的基础 5 个 Client Models all-elements 收集、required models 和非 Power Switch 隔离行为。
- 修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`：新增 Power Switch PID/profile helper，拆分 Battery 额外 required model，并让 `supportModels` 使用 `powerSwitchProfileClientModels`。
- 修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`：把 Battery-only 强失败判断改为 Power Switch required model 判断。
- 不修改 App UI、Power Switch 数据模型、vendor key config、publication、subscription。

## Task 1: 新增 SDK failing tests

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift`

- [ ] **Step 1: 创建 Power Switch support model 测试文件**

新增文件，内容如下：

```swift
import XCTest
@testable import NordicSigMeshSDK

final class PowerSwitchAppKeyBindSupportModelsTests: XCTestCase {

    private let profileClientModelIDs: [UInt16] = [
        .genericOnOffClientModelId,
        .genericLevelClientModelId,
        .sceneClientModelId,
        .lightLightnessClientModelId,
        .lightLCClientModelId
    ]

    func testBatteryPowerSwitchCollectsProfileClientsFromAllElementsAndRequiresBatteryServer() {
        let node = makePowerSwitchNode(productIdentifier: 0x2A01, includesBatteryServer: true)

        XCTAssertTrue(node.isPowerSwitchProduct)
        XCTAssertTrue(node.isBatteryPowerSwitchProduct)
        XCTAssertTrue(node.isPowerSwitchRequiredConfigurationSupported)
        assertContainsEightModelsPerProfileClientID(node.powerSwitchProfileClientModels)

        XCTAssertEqual(models(in: node.powerSwitchRequiredModels, matching: .healthServerModelId).count, 1)
        XCTAssertEqual(models(in: node.powerSwitchRequiredModels, matching: .genericBatteryServerModelId).count, 1)
        XCTAssertEqual(models(in: node.powerSwitchRequiredModels, matching: .genericOnOffClientModelId).count, 8)
        XCTAssertEqual(vendorModels(in: node.powerSwitchRequiredModels).count, 1)
    }

    func testACPowerSwitchCollectsProfileClientsFromAllElementsWithoutBatteryServer() {
        let node = makePowerSwitchNode(productIdentifier: 0x2A11, includesBatteryServer: false)

        XCTAssertTrue(node.isPowerSwitchProduct)
        XCTAssertFalse(node.isBatteryPowerSwitchProduct)
        XCTAssertTrue(node.isPowerSwitchRequiredConfigurationSupported)
        assertContainsEightModelsPerProfileClientID(node.powerSwitchProfileClientModels)

        XCTAssertEqual(models(in: node.powerSwitchRequiredModels, matching: .healthServerModelId).count, 1)
        XCTAssertEqual(models(in: node.powerSwitchRequiredModels, matching: .genericBatteryServerModelId).count, 0)
        XCTAssertEqual(models(in: node.powerSwitchRequiredModels, matching: .lightLightnessClientModelId).count, 8)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightLightnessClientModelId).count, 8)
        XCTAssertEqual(vendorModels(in: node.powerSwitchRequiredModels).count, 1)
    }

    func testACPowerSwitchRequiredModelMatchesElementAndModelIdentifier() throws {
        let node = makePowerSwitchNode(productIdentifier: 0x2A12, includesBatteryServer: false)
        let lightnessModel = try XCTUnwrap(node.elements[7].model(withSigModelId: .lightLightnessClientModelId))

        XCTAssertTrue(node.isPowerSwitchRequiredModel(
            elementAddress: node.elements[7].unicastAddress,
            modelIdentifier: .lightLightnessClientModelId,
            companyIdentifier: nil
        ))
        XCTAssertTrue(node.powerSwitchRequiredModels.contains(lightnessModel))
        XCTAssertFalse(node.isPowerSwitchRequiredModel(
            elementAddress: node.elements[0].unicastAddress,
            modelIdentifier: .genericBatteryServerModelId,
            companyIdentifier: nil
        ))
    }

    func testNonPowerSwitchDoesNotCollectPowerSwitchProfileClients() {
        let node = makePowerSwitchNode(productIdentifier: 0x2013, includesBatteryServer: true)

        XCTAssertFalse(node.isPowerSwitchProduct)
        XCTAssertFalse(node.isBatteryPowerSwitchProduct)
        XCTAssertFalse(node.isPowerSwitchRequiredConfigurationSupported)
        XCTAssertTrue(node.powerSwitchProfileClientModels.isEmpty)
        XCTAssertTrue(node.powerSwitchRequiredModels.isEmpty)
    }

    func testPowerSwitchWithoutProfileClientSetIsNotRequiredConfigurationSupported() {
        let node = makePowerSwitchNode(
            productIdentifier: 0x2A11,
            includesBatteryServer: false,
            includesProfileClients: false
        )

        XCTAssertTrue(node.isPowerSwitchProduct)
        XCTAssertFalse(node.isPowerSwitchRequiredConfigurationSupported)
        XCTAssertTrue(node.powerSwitchProfileClientModels.isEmpty)
        XCTAssertTrue(node.powerSwitchRequiredModels.isEmpty)
    }

    private func makePowerSwitchNode(
        productIdentifier: UInt16,
        includesBatteryServer: Bool,
        includesProfileClients: Bool = true
    ) -> Node {
        let node = Node(name: "Power Switch", unicastAddress: 0x1000, elements: 8)
        node.companyIdentifier = CompanyId
        node.productIdentifier = productIdentifier

        node.elements[0].add(model: Model(sigModelId: .healthServerModelId))
        node.elements[0].add(model: Model(modelId: .vensorServerModelId))

        if includesBatteryServer {
            node.elements[0].add(model: Model(sigModelId: .genericBatteryServerModelId))
        }

        if includesProfileClients {
            node.elements.forEach { element in
                profileClientModelIDs.forEach { modelID in
                    element.add(model: Model(sigModelId: modelID))
                }
            }
        }

        return node
    }

    private func assertContainsEightModelsPerProfileClientID(
        _ models: [Model],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(models.count, 40, file: file, line: line)
        profileClientModelIDs.forEach { modelID in
            XCTAssertEqual(
                self.models(in: models, matching: modelID).count,
                8,
                "Expected eight models for \(modelID.hex)",
                file: file,
                line: line
            )
        }
    }

    private func models(in models: [Model], matching modelID: UInt16) -> [Model] {
        models.filter { $0.modelIdentifier == modelID && $0.companyIdentifier == nil }
    }

    private func vendorModels(in models: [Model]) -> [Model] {
        models.filter { $0.modelId == .vensorServerModelId }
    }
}
```

- [ ] **Step 2: 运行 focused test，确认当前失败**

在 SDK 根目录运行：

```bash
swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter PowerSwitchAppKeyBindSupportModelsTests
```

Expected: FAIL。失败应来自 `Node` 没有 `isPowerSwitchProduct`、`isBatteryPowerSwitchProduct`、`isPowerSwitchRequiredConfigurationSupported`、`powerSwitchProfileClientModels`、`powerSwitchRequiredModels` 或 `isPowerSwitchRequiredModel` 成员。

- [ ] **Step 3: 提交 failing tests**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "test: cover power switch appkey bind models"
```

## Task 2: 实现 SDK Power Switch profile 能力层

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift`

- [ ] **Step 1: 在 `Node+SupportModels.swift` 顶部新增 PID/profile 定义**

在 `import Foundation` 后、`public extension Node` 前加入：

```swift
private enum PowerSwitchProfile {
    static let companyIdentifier: UInt16 = CompanyId
    static let batteryProductIdentifiers: Set<UInt16> = [0x2A01, 0x2A02]
    static let acProductIdentifiers: Set<UInt16> = [0x2A11, 0x2A12]
    static let profileClientModelIDs: [UInt16] = [
        .genericOnOffClientModelId,
        .genericLevelClientModelId,
        .sceneClientModelId,
        .lightLightnessClientModelId,
        .lightLCClientModelId
    ]

    static var productIdentifiers: Set<UInt16> {
        batteryProductIdentifiers.union(acProductIdentifiers)
    }
}
```

- [ ] **Step 2: 替换 Battery-only profile block**

在 `Node+SupportModels.swift` 中找到从注释 `/// Battery Power Switch 两种 Profile 需要绑定的所有按键 Client Model ID。` 到 `isBatteryPowerSwitchRequiredModel(...)` 的整段实现，替换为：

```swift
    /// 是否为 Battery / AC Power Switch 产品。
    var isPowerSwitchProduct: Bool {
        guard companyIdentifier == PowerSwitchProfile.companyIdentifier,
              let productIdentifier else {
            return false
        }
        return PowerSwitchProfile.productIdentifiers.contains(productIdentifier)
    }

    /// 是否为 Battery Power Switch 产品。
    var isBatteryPowerSwitchProduct: Bool {
        guard companyIdentifier == PowerSwitchProfile.companyIdentifier,
              let productIdentifier else {
            return false
        }
        return PowerSwitchProfile.batteryProductIdentifiers.contains(productIdentifier)
    }

    /// Power Switch Profile 需要绑定的基础按键 Client Model ID。
    var powerSwitchProfileClientModelIDs: [UInt16] {
        return PowerSwitchProfile.profileClientModelIDs
    }

    /// Power Switch Profile 需要绑定的所有按键 Client Model。
    var powerSwitchProfileClientModels: [Model] {
        guard isPowerSwitchRequiredConfigurationSupported else {
            return []
        }
        return powerSwitchAvailableProfileClientModels
    }

    /// 当前 Composition 中实际存在的 Power Switch Profile Client Models。
    var powerSwitchAvailableProfileClientModels: [Model] {
        var models: [Model] = []
        elements.forEach { element in
            powerSwitchProfileClientModelIDs.forEach { modelID in
                guard let model = element.model(withSigModelId: modelID),
                      !models.contains(model) else {
                    return
                }
                models.append(model)
            }
        }
        return models
    }

    /// 是否具备 Power Switch Profile 所需的全部基础 Client Model 类型。
    var hasPowerSwitchProfileClientModelSet: Bool {
        return powerSwitchProfileClientModelIDs.allSatisfy { modelID in
            elements.contains { $0.model(withSigModelId: modelID) != nil }
        }
    }

    /// 是否匹配 Power Switch 添加成功前必须完成的关键 Composition 能力集合。
    var isPowerSwitchRequiredConfigurationSupported: Bool {
        guard isPowerSwitchProduct,
              healthModel != nil,
              sunricherVendorModel != nil,
              hasPowerSwitchProfileClientModelSet else {
            return false
        }
        if isBatteryPowerSwitchProduct {
            return batteryModel != nil
        }
        return true
    }

    /// Power Switch 添加成功前必须绑定当前 AppKey 的关键 Model。
    var powerSwitchRequiredModels: [Model] {
        guard isPowerSwitchRequiredConfigurationSupported,
              let healthModel = healthModel,
              let vendorModel = sunricherVendorModel else {
            return []
        }

        var models = [healthModel, vendorModel]
        if isBatteryPowerSwitchProduct, let batteryModel = batteryModel {
            models.append(batteryModel)
        }
        models.append(contentsOf: powerSwitchAvailableProfileClientModels)
        return models
    }

    /// 判断配置状态是否属于 Power Switch 的关键 Model。
    func isPowerSwitchRequiredModel(elementAddress: Address, modelIdentifier: UInt16, companyIdentifier: UInt16?) -> Bool {
        return powerSwitchRequiredModels.contains { model in
            model.parentElement?.unicastAddress == elementAddress &&
            model.modelIdentifier == modelIdentifier &&
            model.companyIdentifier == companyIdentifier
        }
    }

    /// Battery Power Switch 两种 Profile 需要绑定的所有按键 Client Model ID。
    var batteryPowerSwitchProfileClientModelIDs: [UInt16] {
        return powerSwitchProfileClientModelIDs
    }

    /// Battery Power Switch 两种 Profile 需要绑定的所有按键 Client Model。
    var batteryPowerSwitchProfileClientModels: [Model] {
        guard isBatteryPowerSwitchRequiredConfigurationSupported else {
            return []
        }
        return powerSwitchAvailableProfileClientModels
    }

    /// 当前 Composition 中实际存在的 Battery Power Switch Profile Client Models。
    var batteryPowerSwitchAvailableProfileClientModels: [Model] {
        return powerSwitchAvailableProfileClientModels
    }

    /// 是否具备 Battery Power Switch Profile 所需的全部 Client Model 类型。
    var hasBatteryPowerSwitchProfileClientModelSet: Bool {
        return hasPowerSwitchProfileClientModelSet
    }

    /// 是否匹配 Battery Power Switch 的关键 Composition 能力集合。
    var isBatteryPowerSwitchRequiredConfigurationSupported: Bool {
        return isBatteryPowerSwitchProduct && isPowerSwitchRequiredConfigurationSupported
    }

    /// Battery Power Switch 添加成功前必须绑定当前 AppKey 的关键 Model。
    var batteryPowerSwitchRequiredModels: [Model] {
        return isBatteryPowerSwitchRequiredConfigurationSupported ? powerSwitchRequiredModels : []
    }

    /// 判断配置状态是否属于 Battery Power Switch 的关键 Model。
    func isBatteryPowerSwitchRequiredModel(elementAddress: Address, modelIdentifier: UInt16, companyIdentifier: UInt16?) -> Bool {
        return batteryPowerSwitchRequiredModels.contains { model in
            model.parentElement?.unicastAddress == elementAddress &&
            model.modelIdentifier == modelIdentifier &&
            model.companyIdentifier == companyIdentifier
        }
    }
```

- [ ] **Step 3: 让 `supportModels` 追加 Power Switch all-elements models**

在 `supportModels` 中把：

```swift
        batteryPowerSwitchProfileClientModels.forEach {
            if !models.contains($0) {
                models.append($0)
            }
        }
```

替换为：

```swift
        powerSwitchProfileClientModels.forEach {
            if !models.contains($0) {
                models.append($0)
            }
        }
```

- [ ] **Step 4: 运行 focused test，确认 Node 层行为通过**

在 SDK 根目录运行：

```bash
swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter PowerSwitchAppKeyBindSupportModelsTests
```

Expected: PASS。若仍失败，失败只能与 model count、PID 判断或 required models 集合有关；修正 `Node+SupportModels.swift` 后重复运行同一命令。

- [ ] **Step 5: 提交 SDK Node 能力层实现**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: bind power switch profile models by pid"
```

## Task 3: 扩展添加流程强失败判断

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift`

- [ ] **Step 1: 修改添加失败 reset/delete 判断**

在 `deviceAddFailHandle(error:)` 中把：

```swift
let shouldFailAdd = self.mustKeybindFinish || node.isBatteryPowerSwitchRequiredConfigurationSupported
```

替换为：

```swift
let shouldFailAdd = self.mustKeybindFinish || node.isPowerSwitchRequiredConfigurationSupported
```

- [ ] **Step 2: 重命名并扩展 status 失败判断 helper**

把 `shouldFailBatteryPowerSwitchKeybind(message:node:)` 整个函数替换为：

```swift
    private func shouldFailPowerSwitchKeybind(message: MeshMessage, node: Node?) -> Bool {
        guard let node = node,
              node.isPowerSwitchRequiredConfigurationSupported else {
            return false
        }
        if message is ConfigAppKeyStatus {
            return true
        }
        guard let status = message as? ConfigModelAppStatus else {
            return false
        }
        return node.isPowerSwitchRequiredModel(
            elementAddress: status.elementAddress,
            modelIdentifier: status.modelIdentifier,
            companyIdentifier: status.companyIdentifier
        )
    }
```

- [ ] **Step 3: 重命名并扩展发送失败判断 helper**

把 `shouldFailBatteryPowerSwitchKeybindFailure(message:node:)` 整个函数替换为：

```swift
    private func shouldFailPowerSwitchKeybindFailure(message: MeshMessage, node: Node?) -> Bool {
        guard let node = node,
              node.isPowerSwitchRequiredConfigurationSupported else {
            return false
        }
        if message is ConfigAppKeyAdd {
            return true
        }
        guard let bind = message as? ConfigModelAppBind else {
            return false
        }
        return node.isPowerSwitchRequiredModel(
            elementAddress: bind.elementAddress,
            modelIdentifier: bind.modelIdentifier,
            companyIdentifier: bind.companyIdentifier
        )
    }
```

- [ ] **Step 4: 更新 helper call sites**

在 `MeshFastAddDeviceManager.swift` 中替换两个调用：

```swift
shouldFailBatteryPowerSwitchKeybind(message: message, node: node)
```

改为：

```swift
shouldFailPowerSwitchKeybind(message: message, node: node)
```

并把：

```swift
shouldFailBatteryPowerSwitchKeybindFailure(message: message, node: node)
```

改为：

```swift
shouldFailPowerSwitchKeybindFailure(message: message, node: node)
```

- [ ] **Step 5: 确认不再有旧 helper 调用残留**

Run:

```bash
rg -n "shouldFailBatteryPowerSwitchKeybind|isBatteryPowerSwitchRequiredConfigurationSupported" Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift
```

Expected: no output。

- [ ] **Step 6: 运行 SDK focused tests**

在 SDK 根目录运行：

```bash
swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter PowerSwitchAppKeyBindSupportModelsTests
```

Expected: PASS。

- [ ] **Step 7: 提交添加流程失败判断变更**

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: require power switch appkey bind completion"
```

## Task 4: SDK 回归验证

**Files:**
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

- [ ] **Step 1: 运行新增 focused tests**

在 SDK 根目录运行：

```bash
swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter PowerSwitchAppKeyBindSupportModelsTests
```

Expected: PASS，输出包含 `Executed 5 tests` 或 SwiftPM 等价通过摘要。

- [ ] **Step 2: 运行现有 Battery Power Switch vendor tests**

在 SDK 根目录运行：

```bash
swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter BatteryPowerSwitchVendorMessageTests
```

Expected: PASS。该测试确认本次没有破坏 Battery Power Switch vendor message 编解码。

- [ ] **Step 3: 运行现有 response matching tests**

在 SDK 根目录运行：

```bash
swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter MeshMessageHandleResponseMatchingTests
```

Expected: PASS。该测试确认 config/vendor response 匹配基础行为未被影响。

- [ ] **Step 4: 检查 SDK diff 聚焦**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --stat HEAD~3..HEAD
```

Expected: 只包含：

```text
Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift
Sources/NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift
Tests/NordicSigMeshSDKTests/PowerSwitchAppKeyBindSupportModelsTests.swift
```

## Task 5: App 多品牌 target 编译验证

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify: `SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: 确认 App workspace 使用本地 SDK**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -list
```

Expected: resolved packages 中包含：

```text
NordicSigMeshSDK: /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk @ local
```

- [ ] **Step 2: 编译 SunSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 3: 编译 Archipelago**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 编译 SylSmart**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: 编译 SLG Sync Plus**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

## Task 6: 最终检查与总结

**Files:**
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`
- Verify: `/Users/maginawin/Developer/iOS/YKH/sun-smart/.worktrees/k8-ac-260527`

- [ ] **Step 1: 检查 SDK 工作树状态**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected: no output。若有构建产物或无关改动，不要提交；先判断是否由测试/构建生成。

- [ ] **Step 2: 检查 App 工作树未混入实现改动**

Run:

```bash
git status --short
```

Expected: 仍只看到本任务开始前已有的 AC 资源、AC 分析文档、protocols 文件，以及本计划文档；不应出现新的 App 业务代码改动。

- [ ] **Step 3: 汇总验证结果**

在最终回复中列出：

```text
SDK commits:
- test: cover power switch appkey bind models
- feat: bind power switch profile models by pid
- fix: require power switch appkey bind completion

Verification:
- swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter PowerSwitchAppKeyBindSupportModelsTests: PASS
- swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter BatteryPowerSwitchVendorMessageTests: PASS
- swift test --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk --triple arm64-apple-ios15.0-simulator --filter MeshMessageHandleResponseMatchingTests: PASS
- xcodebuild SunSmart: PASS
- xcodebuild Archipelago: PASS
- xcodebuild SylSmart: PASS
- xcodebuild SLG Sync Plus: PASS
```

若任一命令失败，最终回复改为列出失败命令、首个关键错误和下一步建议，不声明完成。

## Self-Review

- Spec coverage：Task 2 覆盖 PID 识别、基础 5 个 all-elements model 收集、Battery Server 仅 Battery 额外处理；Task 3 覆盖 AC required bind 失败时添加失败；Task 4/5 覆盖 SDK 和多品牌 App 验证。
- Placeholder scan：计划中没有 `TBD`、`TODO`、未命名测试类或未指定命令。
- Type consistency：计划统一使用 `powerSwitchProfileClientModels`、`isPowerSwitchRequiredConfigurationSupported`、`powerSwitchRequiredModels`、`isPowerSwitchRequiredModel`，旧 Battery helper 仅作为兼容 alias 保留。
