# Support Models AppKey Bind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SDK 在设备 composition 中实际存在 `0x1302` / `0x1309` 时，将它们加入 `supportModels`，从而复用现有 Space AppKey bind 链路。

**Architecture:** 在本地 `NordicSigMeshSDK` 的 `Node+SupportModels.swift` 增加一个通用 additional client AppKey bind helper，只收集实际存在的 Light Lightness Client 与 Light HSL Client。App 层不新增业务特例，现有 `getConfigMessageHandles()` 继续遍历 `supportModels` 生成 `ConfigModelAppBind`。

**Tech Stack:** Swift、NordicSigMeshSDK Swift Package、SwiftPM XCTest、Xcode workspace、SunSmart iPhoneOS build。

---

## 文件结构

- 新增 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SupportModelsAppKeyBindTests.swift`：focused unit tests，锁定 `0x1302` / `0x1309` 会进入 `supportModels`，`0x100A` / `0x100B` 不因本轮 helper 进入。
- 修改 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`：新增 additional client bind model ID 集合、all-elements 收集 helper，并在 `supportModels` 中去重追加。
- 不修改 App UI、EFC sync planner、vendor message、publication、subscription、本地化、资源或 target 配置。

## Task 1: 新增 SDK failing tests

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SupportModelsAppKeyBindTests.swift`

- [ ] **Step 1: 创建 focused test 文件**

新增文件，内容如下：

```swift
import XCTest
@testable import NordicSigMeshSDK

final class SupportModelsAppKeyBindTests: XCTestCase {

    func testAdditionalClientModelsAreCollectedFromAllElements() {
        let node = makeNode(
            elements: [
                [.lightLightnessClientModelId],
                [.lightHSLClientModelId],
                [.lightLightnessClientModelId, .lightHSLClientModelId]
            ]
        )

        XCTAssertEqual(models(in: node.additionalClientAppKeyBindModels, matching: .lightLightnessClientModelId).count, 2)
        XCTAssertEqual(models(in: node.additionalClientAppKeyBindModels, matching: .lightHSLClientModelId).count, 2)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightLightnessClientModelId).count, 2)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightHSLClientModelId).count, 2)
    }

    func testAdditionalClientModelsDoNotCreateMissingModels() {
        let node = makeNode(
            elements: [
                [.genericOnOffClientModelId],
                [.sceneClientModelId]
            ]
        )

        XCTAssertTrue(node.additionalClientAppKeyBindModels.isEmpty)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightLightnessClientModelId).count, 0)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightHSLClientModelId).count, 0)
    }

    func testPowerLevelModelsAreNotCollectedByAdditionalClientBindProfile() {
        let node = makeNode(
            elements: [
                [.genericPowerLevelSetupServerModelId],
                [.genericPowerLevelClientModelId]
            ]
        )

        XCTAssertTrue(node.additionalClientAppKeyBindModels.isEmpty)
        XCTAssertEqual(models(in: node.additionalClientAppKeyBindModels, matching: .genericPowerLevelSetupServerModelId).count, 0)
        XCTAssertEqual(models(in: node.additionalClientAppKeyBindModels, matching: .genericPowerLevelClientModelId).count, 0)
        XCTAssertEqual(models(in: node.supportModels, matching: .genericPowerLevelSetupServerModelId).count, 0)
        XCTAssertEqual(models(in: node.supportModels, matching: .genericPowerLevelClientModelId).count, 0)
    }

    func testAdditionalClientModelsAreNotDuplicatedWhenAlreadyCollectedByPowerSwitchProfile() {
        let node = Node(name: "Power Switch", unicastAddress: 0x1000, elements: 2)
        node.companyIdentifier = CompanyId
        node.productIdentifier = 0x2A11

        node.elements[0].add(model: Model(sigModelId: .healthServerModelId))
        node.elements[0].add(model: Model(modelId: .vensorServerModelId))
        node.elements.forEach { element in
            element.add(model: Model(sigModelId: .genericOnOffClientModelId))
            element.add(model: Model(sigModelId: .genericLevelClientModelId))
            element.add(model: Model(sigModelId: .sceneClientModelId))
            element.add(model: Model(sigModelId: .lightLightnessClientModelId))
            element.add(model: Model(sigModelId: .lightLCClientModelId))
            element.add(model: Model(sigModelId: .lightHSLClientModelId))
        }

        XCTAssertTrue(node.isPowerSwitchRequiredConfigurationSupported)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightLightnessClientModelId).count, 2)
        XCTAssertEqual(models(in: node.supportModels, matching: .lightHSLClientModelId).count, 2)
    }

    private func makeNode(elements elementModelIDs: [[UInt16]]) -> Node {
        let node = Node(name: "Test Node", unicastAddress: 0x1000, elements: UInt8(elementModelIDs.count))
        node.companyIdentifier = CompanyId
        node.productIdentifier = 0x2131

        for (index, modelIDs) in elementModelIDs.enumerated() {
            modelIDs.forEach { modelID in
                node.elements[index].add(model: Model(sigModelId: modelID))
            }
        }

        return node
    }

    private func models(in models: [Model], matching modelID: UInt16) -> [Model] {
        models.filter { $0.modelIdentifier == modelID && $0.companyIdentifier == nil }
    }
}
```

- [ ] **Step 2: 运行 focused test，确认当前失败**

Run:

```bash
swift test --filter SupportModelsAppKeyBindTests
```

Expected: FAIL，错误包含 `Value of type 'Node' has no member 'additionalClientAppKeyBindModels'`，或等价的编译失败。这个失败证明测试覆盖的是尚未实现的新 helper。

- [ ] **Step 3: 提交 failing tests**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Tests/NordicSigMeshSDKTests/SupportModelsAppKeyBindTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "test: add support models appkey bind coverage"
```

Expected: commit 成功，且只包含 `SupportModelsAppKeyBindTests.swift`。

## Task 2: 实现 additional client AppKey bind supportModels

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/SupportModelsAppKeyBindTests.swift`

- [ ] **Step 1: 在 `Node+SupportModels.swift` 顶部增加 additional profile 定义**

在 `private enum PowerSwitchProfile` 之后、`public extension Node` 之前加入：

```swift
private enum AdditionalClientAppKeyBindProfile {
    static let clientModelIDs: [UInt16] = [
        .lightLightnessClientModelId,
        .lightHSLClientModelId
    ]
}
```

- [ ] **Step 2: 在 Power Switch helper 后增加通用 client bind helper**

在 `isBatteryPowerSwitchRequiredModel(...)` 方法之后、`defaultTransitionTimeModel` 之前加入：

```swift
    /// 需要通过通用 Space AppKey 绑定的额外 Client Model ID。
    var additionalClientAppKeyBindModelIDs: [UInt16] {
        return AdditionalClientAppKeyBindProfile.clientModelIDs
    }

    /// 当前 Composition 中实际存在、且需要绑定 Space AppKey 的额外 Client Models。
    var additionalClientAppKeyBindModels: [Model] {
        var models: [Model] = []
        elements.forEach { element in
            additionalClientAppKeyBindModelIDs.forEach { modelID in
                guard let model = element.model(withSigModelId: modelID),
                      !models.contains(model) else {
                    return
                }
                models.append(model)
            }
        }
        return models
    }
```

- [ ] **Step 3: 在 `supportModels` 中追加 additional client models**

找到现有代码：

```swift
        powerSwitchProfileClientModels.forEach {
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
        additionalClientAppKeyBindModels.forEach {
            if !models.contains($0) {
                models.append($0)
            }
        }
```

- [ ] **Step 4: 运行 focused test，确认通过**

Run:

```bash
swift test --filter SupportModelsAppKeyBindTests
```

Expected: PASS。若失败，失败只应来自 model count、model ID 常量或去重逻辑；修正 `Node+SupportModels.swift` 后重复运行同一命令。

- [ ] **Step 5: 回归 Power Switch support model 测试**

Run:

```bash
swift test --filter PowerSwitchAppKeyBindSupportModelsTests
```

Expected: PASS。该回归确认 additional helper 没有破坏 Power Switch profile 的现有 all-elements bind 逻辑。

- [ ] **Step 6: 提交 SDK 实现**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: bind additional client support models"
```

Expected: commit 成功，且只包含 `Node+SupportModels.swift`。

## Task 3: 验证 App 集成构建

**Files:**
- Read: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire/Package.resolved`
- Verify: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire/SunSmart.xcworkspace`

- [ ] **Step 1: 检查 App 是否引用本地 SDK**

Run:

```bash
rg -n "nordic-sig-mesh-sdk|NordicSigMeshSDK|gitee.com/sunricher-i-os/nordic-sig-mesh-sdk" Package.resolved SunSmart.xcodeproj SunSmart.xcworkspace
```

Expected: 输出能说明当前工程的 `NordicSigMeshSDK` 来源。若仍是远程 `gitee.com/sunricher-i-os/nordic-sig-mesh-sdk.git`，需要先按项目 SDK Notes 将依赖切换到 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk` 后再构建。

- [ ] **Step 2: 运行 SunSmart iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 检查 App worktree diff**

Run:

```bash
git status --short
```

Expected: App worktree 不出现本轮代码改动。允许保留执行前已有的未跟踪文档或其他用户改动，但不要把它们提交到 SDK commit。

## Self-Review

- Spec coverage: Task 2 将实际存在的 `0x1302` / `0x1309` 加入 `supportModels`；Task 1 覆盖多 element、缺失 model、不绑定 `0x100A` / `0x100B`、Power Switch 去重；Task 3 覆盖 App 构建验收。
- Placeholder scan: 无 TBD、TODO、待定、占位步骤。
- Type consistency: 计划中使用的 `additionalClientAppKeyBindModelIDs`、`additionalClientAppKeyBindModels`、`SupportModelsAppKeyBindTests` 在 Task 1/2 定义一致；model ID 常量来自 SDK `Models.swift`。
