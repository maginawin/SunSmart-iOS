# EFC Recall Scene Debug Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference in `AGENTS.md`: use Inline Execution by default.

**Goal:** 在 Debug 模式下输出 EFC/Scene Recall 收包与 App 业务匹配日志，帮助区分设备未 recall、App 未收到、App 解析未命中和 UI 未更新。

**Architecture:** SDK 增加一个可单元测试的 recall scene 日志格式化 helper，并在 `NetworkManager.notifyAbout(newMessage:from:to:)` 通知 App delegate 前 Debug-only 输出。App 侧只增强 `EmergencyFireControllerSceneEventManager` 的 matched / ignored 日志解释，不改变当前 source + publish group 匹配规则。

**Tech Stack:** Swift, NordicSigMeshSDK Swift Package, XCTest, UIKit App project, iPhoneOS `xcodebuild`.

---

## File Structure

- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Debug/SceneRecallDebugLog.swift`
  - 只负责从 `SceneRecall` / `SceneRecallUnacknowledged` 生成一行诊断日志。
  - `line(for:source:destination:)` 不依赖 Debug 宏，便于单元测试。
  - `printIfNeeded(message:source:destination:)` 内部用 `#if DEBUG` 包住真实输出。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`
  - 在 SDK 成功解码 message 并通知 App delegate 前调用 helper。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`
  - 补充 recall scene 日志格式化测试。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift`
  - 统一 EFC scene 日志格式。
  - ignored 日志补充 reason，不改匹配行为。

## Task 1: SDK recall scene log helper and tests

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Debug/SceneRecallDebugLog.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

- [ ] **Step 1: Add failing tests for recall log formatting**

Append these tests inside `EmergencyFireVendorMessageTests` before the final closing brace:

```swift
    func testSceneRecallDebugLogFormatsEFCUnacknowledgedScene() {
        let line = SceneRecallDebugLog.line(
            for: SceneRecallUnacknowledged(.emergencyFireEmergencyTriggerScene),
            source: 0x1201,
            destination: MeshAddress(0xC123)
        )

        XCTAssertEqual(
            line,
            "[Scene Recall RX] type=SceneRecallUnacknowledged source=0x1201 target=0xC123 scene=0xFF20 special=true eventTrigger=true efc=powerLossTrigger"
        )
    }

    func testSceneRecallDebugLogFormatsRegularAcknowledgedScene() {
        let line = SceneRecallDebugLog.line(
            for: SceneRecall(0x1234),
            source: 0x1201,
            destination: MeshAddress(0xC123)
        )

        XCTAssertEqual(
            line,
            "[Scene Recall RX] type=SceneRecall source=0x1201 target=0xC123 scene=0x1234 special=false eventTrigger=false efc=none"
        )
    }

    func testSceneRecallDebugLogIgnoresNonRecallMessages() {
        let line = SceneRecallDebugLog.line(
            for: GenericOnOffStatus(true),
            source: 0x1201,
            destination: MeshAddress(0xC123)
        )

        XCTAssertNil(line)
    }
```

- [ ] **Step 2: Run the focused SDK test and verify it fails**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests/testSceneRecallDebugLogFormatsEFCUnacknowledgedScene
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
error: cannot find 'SceneRecallDebugLog' in scope
```

If `swift test` fails before compiling this test because of an unrelated existing UIKit or package issue, record the blocker and continue with the iPhoneOS SDK build in Task 4.

- [ ] **Step 3: Create the SDK helper**

Create `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Debug/SceneRecallDebugLog.swift`:

```swift
import Foundation

enum SceneRecallDebugLog {

    static func line(for message: MeshMessage, source: Address, destination: MeshAddress) -> String? {
        guard let recall = recallInfo(from: message) else {
            return nil
        }
        return "[Scene Recall RX] type=\(recall.type) source=0x\(source.hex) target=0x\(destination.hex) scene=0x\(recall.scene.hex) special=\(boolString(recall.scene.isSpecialScene)) eventTrigger=\(boolString(recall.scene.isEventTriggerScene)) efc=\(efcLabel(for: recall.scene))"
    }

    static func printIfNeeded(message: MeshMessage, source: Address, destination: MeshAddress) {
        #if DEBUG
        guard let line = line(for: message, source: source, destination: destination) else {
            return
        }
        print(line)
        #endif
    }

    private static func recallInfo(from message: MeshMessage) -> (type: String, scene: SceneNumber)? {
        if let recall = message as? SceneRecall {
            return ("SceneRecall", recall.scene)
        }
        if let recall = message as? SceneRecallUnacknowledged {
            return ("SceneRecallUnacknowledged", recall.scene)
        }
        return nil
    }

    private static func efcLabel(for scene: SceneNumber) -> String {
        switch scene {
        case SceneNumber.emergencyFireEmergencyTriggerScene:
            return "powerLossTrigger"
        case SceneNumber.emergencyFireFireTriggerScene:
            return "fireAlarmTrigger"
        case SceneNumber.emergencyFireRestoreScene:
            return "restore"
        default:
            return "none"
        }
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}
```

- [ ] **Step 4: Run the focused SDK tests and verify they pass**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests/testSceneRecallDebugLog
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
Test Suite 'EmergencyFireVendorMessageTests' passed
```

- [ ] **Step 5: Commit the SDK helper and tests**

Run:

```bash
git status --short
git add Sources/NordicSigMeshSDK/MeshLib/Debug/SceneRecallDebugLog.swift Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift
git commit -m "test: cover scene recall debug log"
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
2 files changed
```

## Task 2: SDK receive-path Debug output

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`

- [ ] **Step 1: Add the receive-path call before delegate notification**

In `NetworkManager.notifyAbout(newMessage:from:to:)`, place the helper call immediately before the existing global delegate callback:

```swift
        SceneRecallDebugLog.printIfNeeded(message: message, source: source, destination: destination)

        // Notify the global delegate.
        delegate?.networkManager(self, didReceiveMessage: message,
                                 sentFrom: source, to: destination)
```

This keeps the log at the point where SDK has already decoded `MeshMessage` and is about to notify App code.

- [ ] **Step 2: Static-check the insertion**

Run:

```bash
rg -n "SceneRecallDebugLog.printIfNeeded|Notify the global delegate" "Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift"
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
SceneRecallDebugLog.printIfNeeded(message: message, source: source, destination: destination)
// Notify the global delegate.
```

- [ ] **Step 3: Re-run the recall log tests**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests/testSceneRecallDebugLog
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
Test Suite 'EmergencyFireVendorMessageTests' passed
```

- [ ] **Step 4: Commit the receive-path hook**

Run:

```bash
git status --short
git add Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift
git commit -m "feat: log received scene recall messages"
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
1 file changed
```

## Task 3: App EFC match / ignore log clarity

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift`

- [ ] **Step 1: Add local match result helpers**

Inside `EmergencyFireControllerSceneEventManager`, replace the existing `matchingController(source:destination:) -> DeviceEmerFireData?` helper with a match result enum and reason-preserving helper:

```swift
    private enum ControllerMatchResult {
        case matched(DeviceEmerFireData)
        case failed(reason: String)
    }

    private func controllerMatchResult(source: Address, destination: Address) -> ControllerMatchResult {
        let controllers = controllersProvider()
        guard !controllers.isEmpty else {
            return .failed(reason: "noController")
        }

        var hasSourceMatch = false
        var hasDestinationMatch = false
        var hasLinkedController = false

        for controller in controllers {
            guard let node = controller.bindNode else {
                continue
            }
            hasLinkedController = true

            let sourceMatches = node.primaryUnicastAddress == source || node.contains(elementWithAddress: source)
            let destinationMatches = controller.publishGroupAddress == destination

            if sourceMatches && destinationMatches {
                return .matched(controller)
            }
            if sourceMatches {
                hasSourceMatch = true
            }
            if destinationMatches {
                hasDestinationMatch = true
            }
        }

        if !hasLinkedController {
            return .failed(reason: "noLinkedController")
        }
        if hasSourceMatch {
            return .failed(reason: "targetMismatch")
        }
        if hasDestinationMatch {
            return .failed(reason: "sourceMismatch")
        }
        return .failed(reason: "noMatchingController")
    }
```

- [ ] **Step 2: Add scene/address formatting helpers**

Add these helpers near `addressesDescription(_:)`:

```swift
    private static func sceneDescription(_ sceneNumber: SceneNumber) -> String {
        "0x\(sceneNumber.hex)"
    }

    private static func addressDescription(_ address: Address) -> String {
        "0x\(address.hex)"
    }
```

- [ ] **Step 3: Update ignored and matched logs without changing behavior**

In `handle(message:source:destination:)`, replace the existing controller guard block:

```swift
        let matchResult = controllerMatchResult(source: source, destination: destination)
        guard case .matched(let controller) = matchResult,
              let nodeAddress = controller.bindNodeAddress,
              let publishGroupAddress = controller.publishGroupAddress else {
            let reason: String
            if case .failed(let matchReason) = matchResult {
                reason = matchReason
            } else {
                reason = "invalidControllerData"
            }
            log("ignored reason=\(reason) source=\(Self.addressDescription(source)) target=\(Self.addressDescription(destination)) scene=\(Self.sceneDescription(sceneNumber))")
            return nil
        }
```

Replace the final matched log with:

```swift
        log("matched controller=\(controller.name) source=\(Self.addressDescription(source)) target=\(Self.addressDescription(destination)) scene=\(Self.sceneDescription(sceneNumber)) state=\(event.state)")
```

The event creation and `NotificationCenter.default.post(...)` call stay unchanged.

- [ ] **Step 4: Static-check the App log output shape**

Run:

```bash
rg -n "controllerMatchResult|ignored reason=|matched controller=|sceneDescription|addressDescription" SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire
```

Expected:

```text
controllerMatchResult
ignored reason=
matched controller=
sceneDescription
addressDescription
```

- [ ] **Step 5: Commit the App log clarity change**

Before staging, inspect current App worktree because this checkout already has unrelated EFC link changes:

```bash
git status --short
git diff -- SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift
git commit -m "feat: clarify EFC scene recall logs"
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire
```

Expected:

```text
1 file changed
```

Do not stage `AGENTS.md`, `LinkedEmerFireEditVC.swift`, `scripts/check_efc_controller_flows.sh`, or `docs/260622_1413_efc_link_associated_group_sync_plan.md`.

## Task 4: Verification

**Files:**
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Debug/SceneRecallDebugLog.swift`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`
- Verify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`
- Verify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift`

- [ ] **Step 1: Verify SDK diff is focused**

Run:

```bash
git diff --stat HEAD~2..HEAD
git diff --check HEAD~2..HEAD
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
SceneRecallDebugLog.swift
NetworkManager.swift
EmergencyFireVendorMessageTests.swift
```

and no `git diff --check` output.

- [ ] **Step 2: Verify App diff is focused**

Run:

```bash
git show --stat --oneline HEAD
git diff --check HEAD~1..HEAD
git status --short
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire
```

Expected:

```text
EmergencyFireControllerSceneEventManager.swift
```

`git status --short` may still show the pre-existing unrelated files, but should not show unstaged changes to `EmergencyFireControllerSceneEventManager.swift`.

- [ ] **Step 3: Run focused SDK tests**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests/testSceneRecallDebugLog
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
Test Suite 'EmergencyFireVendorMessageTests' passed
```

- [ ] **Step 4: Build the SDK for iPhoneOS**

Run:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 5: Build the SunSmart app for iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 6: Capture the final expected field checklist**

Run:

```bash
rg -n "Scene Recall RX|type=|source=0x|target=0x|scene=0x|special=|eventTrigger=|efc=|ignored reason=|matched controller=" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSceneEventManager.swift
```

Expected:

```text
Scene Recall RX
special=
eventTrigger=
efc=
ignored reason=
matched controller=
```
