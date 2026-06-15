# Up Down Light Up Ratio Vendor Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `NordicSigMeshSDK` 增加 up down light up ratio Vendor 协议，并把现有单设备页与 group control 的 Up/Down Ratio 控件接入 SET 下发。

**Architecture:** SDK 继续复用现有 `SunricherVendorSet/Get/Status` 集中式 Vendor 协议模型，只新增 `0x53 / 0x02` 的编码、解码和测试。App 层不改 UI 结构：单设备页在 slider 结束后发送 ACK SET，失败或超时回滚；group control 在 slider 结束后向组地址发送一次组播 SET，默认成功并更新本地缓存。

**Tech Stack:** Swift 5.8, NordicSigMeshSDK Swift Package, UIKit, SunSmart iOS app, XCTest, xcodebuild.

---

## File Structure

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 增加 `VendorOpCode.upDownLight`、`VendorUpDownLightCode`、`ResponseCode.upDownLightUpRatio`、`FunctionParameters.upDownLightUpRatio`，并解析 RET。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
  - 增加 `VendorFunctionSet.upDownLightUpRatio(UInt8)`，编码 `[0x53, 0x02, upRatio]`。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - 增加 `VendorFunctionGet.upDownLightUpRatio`，编码 `[0x53, 0x02]`。
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`
  - 覆盖 SET/GET 编码、ACK/失败/GET 返回解析、短包和越界返回。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`
  - 覆盖 `[0x53, 0x02]` response matching。
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 单设备 up ratio SET：拖动中只刷新 UI，拖动结束发送 ACK SET，失败或超时回滚。
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - group control up ratio SET：拖动中只刷新 UI，拖动结束向 group address 发送组播 SET，默认成功保存本地缓存。

## Scope Notes

- 当前 App 工程已经通过 `SunSmart.xcodeproj/project.pbxproj` 指向本地 SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- 本地 SDK 当前已有 3 个未提交 manager 层改动：`MeshAddDeviceManager.swift`、`MeshFirmwareUpdateManager.swift`、`MeshLibManager.swift`。本计划不触碰这些文件。
- SDK GET 能力会完整实现和测试；App 本次只接入 SET 下发，不在页面进入时新增强制 GET 行为。

---

### Task 1: SDK Vendor Protocol Encoding

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`

- [ ] **Step 1: Write failing encoding tests**

Create `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift` with this initial content:

```swift
import XCTest
@testable import NordicSigMeshSDK

final class UpDownLightVendorMessageTests: XCTestCase {

    func testUpDownLightUpRatioSetEncoding() {
        XCTAssertEqual(
            SunricherVendorSet(function: .upDownLightUpRatio(0)).parameters,
            Data([0x53, 0x02, 0x00])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .upDownLightUpRatio(50)).parameters,
            Data([0x53, 0x02, 0x32])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .upDownLightUpRatio(100)).parameters,
            Data([0x53, 0x02, 0x64])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .upDownLightUpRatio(255)).parameters,
            Data([0x53, 0x02, 0x64])
        )
    }

    func testUpDownLightUpRatioGetEncoding() {
        XCTAssertEqual(
            SunricherVendorGet(function: .upDownLightUpRatio).parameters,
            Data([0x53, 0x02])
        )
    }
}
```

- [ ] **Step 2: Run encoding tests and verify they fail**

Run:

```bash
swift test --filter UpDownLightVendorMessageTests
```

from:

```bash
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: FAIL with compile errors that `upDownLightUpRatio` is not a member of `VendorFunctionSet` and `VendorFunctionGet`.

- [ ] **Step 3: Add Vendor opcode and response code definitions**

In `SunricherVendorStatus.swift`, add this case to `VendorOpCode` after `fireEmergencyScene`:

```swift
    /// Up down light
    case upDownLight = 0x53
```

Add this enum near the other Vendor code enums:

```swift
/// Up down light code
public enum VendorUpDownLightCode: UInt8 {
    /// Up ratio
    case upRatio = 0x02
}
```

In `ResponseCode.init(opcode:subcode:)`, add this switch branch before the final closing of the outer switch:

```swift
        case .upDownLight:
            switch subcode {
            case VendorUpDownLightCode.upRatio.rawValue:
                self = .upDownLightUpRatio
            default:
                return nil
            }
```

Add this case to `ResponseCode` near the device feature cases:

```swift
    /// Up down light up ratio
    case upDownLightUpRatio
```

In `public extension ResponseCode var code`, add:

```swift
        case .upDownLightUpRatio:
            return [VendorOpCode.upDownLight.rawValue, VendorUpDownLightCode.upRatio.rawValue]
```

- [ ] **Step 4: Add SET function encoding**

In `SunricherVendorSet.swift`, add this branch to `VendorFunctionSet.data`:

```swift
        case .upDownLightUpRatio(let value):
            return data + min(value, 100)
```

Add this branch to `VendorFunctionSet.command`:

```swift
        case .upDownLightUpRatio:
            return .upDownLightUpRatio
```

Add this case to `VendorFunctionSet`:

```swift
    /// Up down light 的 up ratio，范围 0...100。
    case upDownLightUpRatio(UInt8)
```

- [ ] **Step 5: Add GET function encoding**

In `SunricherVendorGet.swift`, add this branch to `VendorFunctionGet.command`:

```swift
        case .upDownLightUpRatio:
            return .upDownLightUpRatio
```

Add this case to `VendorFunctionGet`:

```swift
    /// 获取 up down light 的 up ratio。
    case upDownLightUpRatio
```

- [ ] **Step 6: Run encoding tests and verify they pass**

Run:

```bash
swift test --filter UpDownLightVendorMessageTests
```

Expected: PASS for `testUpDownLightUpRatioSetEncoding` and `testUpDownLightUpRatioGetEncoding`.

- [ ] **Step 7: Commit SDK encoding changes**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add up down light up ratio vendor encoding"
```

Before committing, confirm the staged diff does not include the existing manager-layer files.

---

### Task 2: SDK Vendor Status Parsing And Response Matching

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift`

- [ ] **Step 1: Add failing status parsing tests**

Append these tests to `UpDownLightVendorMessageTests.swift`:

```swift
    func testUpDownLightUpRatioStatusParsing() {
        let setAck = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x00]))
        XCTAssertEqual(setAck?.status.isSuccessful, true)
        XCTAssertEqual(setAck?.status.code, .upDownLightUpRatio)
        XCTAssertNil(setAck?.status.parameters)

        let setError = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x01]))
        XCTAssertEqual(setError?.status.isSuccessful, false)
        XCTAssertEqual(setError?.status.errorCode, 0x01)
        XCTAssertNil(setError?.status.parameters)

        let getStatus = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x00, 0x64]))
        XCTAssertEqual(getStatus?.status.isSuccessful, true)
        XCTAssertEqual(getStatus?.status.code, .upDownLightUpRatio)
        if case .upDownLightUpRatio(let ratio) = getStatus?.status.parameters {
            XCTAssertEqual(ratio, 100)
        } else {
            XCTFail("Expected up down light up ratio")
        }

        let shortGetStatus = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x00]))
        XCTAssertEqual(shortGetStatus?.status.isSuccessful, true)
        XCTAssertNil(shortGetStatus?.status.parameters)

        let invalidGetStatus = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x00, 0x65]))
        XCTAssertEqual(invalidGetStatus?.status.isSuccessful, false)
        XCTAssertNil(invalidGetStatus?.status.parameters)
    }
```

- [ ] **Step 2: Add failing response matching test**

Append this test to `MeshMessageHandleResponseMatchingTests.swift`:

```swift
    func testUpDownLightVendorStatusMustMatchCurrentVendorCommandCode() {
        let upRatioHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .upDownLightUpRatio(75)),
            address: 0x0003
        )
        let upRatioStatus = SunricherVendorStatus(parameters: Data([0x53, 0x02, 0x00]))!
        let otherVendorStatus = SunricherVendorStatus(parameters: Data([0x4C, 0x02, 0x00]))!

        XCTAssertTrue(upRatioHandle.matchesResponse(upRatioStatus, from: 0x0003))
        XCTAssertFalse(upRatioHandle.matchesResponse(otherVendorStatus, from: 0x0003))
    }
```

- [ ] **Step 3: Run parsing tests and verify they fail**

Run:

```bash
swift test --filter UpDownLightVendorMessageTests
swift test --filter MeshMessageHandleResponseMatchingTests/testUpDownLightVendorStatusMustMatchCurrentVendorCommandCode
```

Expected: `UpDownLightVendorMessageTests` fails because `FunctionParameters.upDownLightUpRatio` does not exist and parsing returns no parameter.

- [ ] **Step 4: Add FunctionParameters case**

In `SunricherVendorStatus.swift`, add this case to `FunctionParameters`:

```swift
    //****** Up Down Light *****/
    /// Up down light up ratio
    case upDownLightUpRatio(UInt8)
```

- [ ] **Step 5: Parse up ratio status**

In `SunricherVendorStatus.Status.init?(data:)`, add this branch inside the `if data.count >= 4 { switch responseCode { ... } }` switch:

```swift
                case .upDownLightUpRatio:
                    guard isSuccessful else {
                        self.parameters = nil
                        break
                    }
                    let ratio: UInt8 = data.read(fromOffset: 3)
                    guard ratio <= 100 else {
                        self.isSuccessful = false
                        self.parameters = nil
                        break
                    }
                    self.parameters = .upDownLightUpRatio(ratio)
```

Keep the existing behavior for 3-byte SET ACKs: when `data.count == 3`, the initializer must leave `parameters = nil` and preserve `isSuccessful`.

- [ ] **Step 6: Run SDK message tests**

Run:

```bash
swift test --filter UpDownLightVendorMessageTests
swift test --filter MeshMessageHandleResponseMatchingTests
```

Expected: PASS.

- [ ] **Step 7: Commit SDK parsing changes**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/UpDownLightVendorMessageTests.swift Tests/NordicSigMeshSDKTests/MeshMessageHandleResponseMatchingTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: parse up down light up ratio vendor status"
```

Before committing, confirm the staged diff does not include the existing manager-layer files.

---

### Task 3: Single Device Up Ratio ACK And Rollback

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: Add state for the last confirmed ratio**

In `DeviceLightViewController`, add this property near `private var upDownRatioView`:

```swift
    private var confirmedUpRatioValue = 50
```

In `init(space:node:)`, set it after `self.node = node`:

```swift
        self.confirmedUpRatioValue = node.upRatio
```

- [ ] **Step 2: Add helper methods for optimistic apply, persistence, rollback, and ACK send**

Add these methods near `bindSliderAction()`:

```swift
    private func applyLocalUpRatioValue(_ value: Int) {
        let clampedValue = max(0, min(100, value))
        node.upRatio = clampedValue
        updateData(refreshControlPanel: false)
    }

    private func saveLocalUpRatioValue(_ value: Int) {
        node.upRatio = max(0, min(100, value))
        if let meshUUID = node.network?.uuid.uuidString {
            node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
        }
    }

    private func rollbackUpRatioValue() {
        node.upRatio = confirmedUpRatioValue
        upDownRatioView.upValue = confirmedUpRatioValue
        updateData(refreshControlPanel: false)
    }

    private func sendUpRatioValue(_ value: Int) {
        let clampedValue = max(0, min(100, value))
        applyLocalUpRatioValue(clampedValue)

        guard let vendorModel = node.sunricherVendorModel else {
            rollbackUpRatioValue()
            ToastStatusView.show(in: view, message: "configuration_failed".localizedString, type: .failure)
            return
        }

        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .upDownLightUpRatio(UInt8(clampedValue))),
            model: vendorModel,
            timeout: 7
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.isSuccessful,
                      status.status.code == .upDownLightUpRatio else {
                    self.rollbackUpRatioValue()
                    ToastStatusView.show(in: self.view, message: "configuration_failed".localizedString, type: .failure)
                    return
                }

                self.confirmedUpRatioValue = clampedValue
                self.saveLocalUpRatioValue(clampedValue)
                self.updateData(refreshControlPanel: false)
            }
        }
    }
```

- [ ] **Step 3: Change ratio callbacks to avoid sending during drag**

Replace the existing `upDownRatioView.valueChanging` and `valueChanged` closures in `bindSliderAction()` with:

```swift
        upDownRatioView.valueChanging = { [weak self] value in
            self?.applyLocalUpRatioValue(value)
        }
        upDownRatioView.valueChanged = { [weak self] value in
            self?.sendUpRatioValue(value)
        }
```

This preserves local UI updates during drag and sends exactly once when `DeviceUpDownRatioControlView` reports `valueChanged`.

- [ ] **Step 4: Verify App code compiles through Swift typechecking**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build proceeds past `DeviceLightViewController.swift` without type errors for `.upDownLightUpRatio`.

- [ ] **Step 5: Commit single-device App changes**

Run:

```bash
git status --short
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: send up ratio from device control"
```

---

### Task 4: Group Control Up Ratio Multicast SET

**Files:**
- Modify: `SunSmart/Main/Group/Controller/GroupViewController.swift`

- [ ] **Step 1: Add group multicast send helper**

Replace the current `saveGroupUpRatioValue(_:)` method with:

```swift
    private func saveGroupUpRatioValue(_ value: Int) {
        let clampedValue = max(0, min(100, value))
        MeshAPI.sendMessage(
            message: SunricherVendorSet(function: .upDownLightUpRatio(UInt8(clampedValue))),
            address: group.address.address
        )

        applyGroupUpRatioValue(clampedValue)
        upDownRatioNodes.forEach { node in
            if let meshUUID = node.network?.uuid.uuidString {
                node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
            }
        }
    }
```

This uses the existing fire-and-forget `MeshAPI.sendMessage(message:address:)` overload. It does not wait for RET and does not roll back local state.

- [ ] **Step 2: Keep drag behavior local-only**

Confirm the group callbacks in `bindSliderAciton()` have this shape:

```swift
        upDownRatioControlView.valueChanging = { [weak self] value in
            guard let self else { return }
            self.applyGroupUpRatioValue(value)
        }

        upDownRatioControlView.valueChanged = { [weak self] value in
            guard let self else { return }
            self.saveGroupUpRatioValue(value)
        }
```

If they differ, replace them with the snippet above. `valueChanging` must not call `MeshAPI`.

- [ ] **Step 3: Verify App build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds for the `SunSmart` scheme.

- [ ] **Step 4: Commit group App changes**

Run:

```bash
git status --short
git add SunSmart/Main/Group/Controller/GroupViewController.swift
git commit -m "feat: send group up ratio multicast"
```

---

### Task 5: Final Verification And Documentation Check

**Files:**
- Read: `docs/superpowers/specs/260615_1155_up_down_light_up_ratio_vendor_protocol_design.md`
- Read: `docs/superpowers/plans/260615_1352_up_down_light_up_ratio_vendor_protocol_implementation_plan.md`

- [ ] **Step 1: Run focused SDK tests**

Run:

```bash
swift test --filter UpDownLightVendorMessageTests
swift test --filter MeshMessageHandleResponseMatchingTests/testUpDownLightVendorStatusMustMatchCurrentVendorCommandCode
```

from:

```bash
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: PASS.

- [ ] **Step 2: Run full SDK tests if focused tests pass**

Run:

```bash
swift test
```

from:

```bash
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: PASS. If unrelated pre-existing tests fail, capture exact failing test names and error text before deciding whether the failure is in scope.

- [ ] **Step 3: Run App iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

from:

```bash
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Check whitespace**

Run:

```bash
git diff --check
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
```

Expected: no output.

- [ ] **Step 5: Confirm implementation matches spec**

Check these facts directly in code:

```bash
rg -n "upDownLight|upDownLightUpRatio|VendorUpDownLightCode" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor
rg -n "sendUpRatioValue|rollbackUpRatioValue|confirmedUpRatioValue|upDownLightUpRatio" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
rg -n "saveGroupUpRatioValue|upDownLightUpRatio|MeshAPI.sendMessage" SunSmart/Main/Group/Controller/GroupViewController.swift
```

Expected:

- SDK contains `VendorOpCode.upDownLight = 0x53`.
- SDK contains `VendorUpDownLightCode.upRatio = 0x02`.
- SDK encodes SET as `[0x53, 0x02, value]` and GET as `[0x53, 0x02]`.
- Single device uses `sendUpRatioValue` only from `valueChanged`.
- Single device has rollback path for timeout or unsuccessful `SunricherVendorStatus`.
- Group control sends `SunricherVendorSet(function: .upDownLightUpRatio(...))` to `group.address.address` from `saveGroupUpRatioValue`.
- Group control does not wait for ACK or inspect `SunricherVendorStatus`.

- [ ] **Step 6: Final status report**

Report:

- SDK commits created.
- App commits created.
- Focused SDK test result.
- Full SDK test result.
- iPhoneOS build result.
- Any pre-existing dirty SDK files that remain untouched.
