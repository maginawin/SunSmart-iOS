# EL Controller Vendor 0x45 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `NordicSigMeshSDK` 中完整建模 Sunricher Vendor `0x45` 协议，并把当前 App 的 EL Controller Function Test 与 RX/TX Cable 卡片接到真实 Mesh 命令和设备上报。

**Architecture:** SDK 负责协议编解码、ACK 匹配与状态解析，不限制设备 PID；App 只在 `CID 0x0A78 / PID 0x24C1` 的当前设备详情页调用这些 SDK API。Function Test 的启动使用 SET ACK 判断命令是否被接受，成功后不轮询，使用 `MeshLibManagerMessageDelegate` 接收 `RET 0x03` 主动上报；RX/TX Cable 使用 GET ACK 的 `ret` 判定结果。

**Tech Stack:** Swift、UIKit、NordicSigMeshSDK、XCTest、SnapKit、SIG Mesh Vendor Model。

---

## 执行偏好

本项目已确认使用 Inline Execution。用户确认本计划后，在当前会话使用 `superpowers:executing-plans` 逐任务执行；除非用户明确要求，不启用 subagents。

## 已确认协议决策

- SDK 继续使用现有 vendor opcode 常量：`SET 0xF0780A`、`GET 0xF1780A`、`RET 0xF3780A`；实际 Access Opcode wire 为 `F0/F1/F3 78 0A`。
- Access payload 格式为 `[0x45] [sub] [data...]`，RET 为 `[0x45] [sub] [ret] [data...]`。
- SDK 层实现全协议，不按 PID 限制；App UI 层继续只在 `CID 0x0A78 / PID 0x24C1` 页面展示和调用。
- SET `0x07` 成功后进入 Function Testing，等待设备主动上报 `RET 0x03`，不做 App 侧结果超时，不做轮询。
- SET `0x08` 需要 SDK 支持，但当前 UI 不展示 Exit，也不在离开页面时自动发送 Exit。
- RX/TX Cable `RET 0x00` 只看 `ret`：`0` 是成功，其他是失败。
- GET `0x01` 的 `status` 中 `0x0E` 表示 Function Testing，其余值按 Normal status 处理。
- GET/RET `0x03` 的两字节结果为 `faultBits` 与 `validity`：bit0 lamp、bit1 battery、bit2 circuit；`validity == 0x00` 有效，`validity == 0x07` 无效。

## 文件结构

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/ELControllerVendorMessageTests.swift`
  - 新增 SDK 协议测试，覆盖 SET/GET 编码、RET 解析、短包判定、同一 vendor RET opcode 下的子码匹配。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 扩展 `VendorOpCode`、新增 `VendorELControllerCode`、扩展 `ResponseCode` 与 `FunctionParameters`，解析 `ELControllerDeviceStatus` 与 `ELControllerFunctionTestResult`。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
  - 新增 Function Test start/exit SET 命令。
- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - 新增 RX/TX Cable、Device Status、Function Test Result GET 命令。
- `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
  - 将当前本地循环展示改成外部状态驱动，提供按钮回调和公开状态更新方法。
- `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`
  - 绑定两张卡片按钮到 SDK 命令，使用 `MeshLibManagerMessageDelegate` 处理 `SunricherVendorStatus` 上报。
- `SunSmart/en.lproj/Localizable.strings`
  - 补齐 Function Test / RXTX 按钮、失败和无效结果文案。
- `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 补齐对应简体中文文案。

## Task 1: SDK 协议测试

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/ELControllerVendorMessageTests.swift`

- [ ] **Step 1: 写入失败测试**

```swift
import XCTest
@testable import NordicSigMeshSDK

final class ELControllerVendorMessageTests: XCTestCase {

    func testSetEncoding() {
        XCTAssertEqual(
            SunricherVendorSet(function: .elControllerStartFunctionTest).parameters,
            Data([0x45, 0x07])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .elControllerExitFunctionTest).parameters,
            Data([0x45, 0x08])
        )
    }

    func testGetEncoding() {
        XCTAssertEqual(
            SunricherVendorGet(function: .elControllerRxTxCableConnection).parameters,
            Data([0x45, 0x00])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .elControllerDeviceStatus).parameters,
            Data([0x45, 0x01])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .elControllerFunctionTestResult).parameters,
            Data([0x45, 0x03])
        )
    }

    func testSetAckParsing() {
        let startAck = SunricherVendorStatus(parameters: Data([0x45, 0x07, 0x00]))
        XCTAssertEqual(startAck?.status.isSuccessful, true)
        XCTAssertEqual(startAck?.status.code, .elControllerStartFunctionTest)
        XCTAssertNil(startAck?.status.parameters)

        let exitAck = SunricherVendorStatus(parameters: Data([0x45, 0x08, 0x00]))
        XCTAssertEqual(exitAck?.status.isSuccessful, true)
        XCTAssertEqual(exitAck?.status.code, .elControllerExitFunctionTest)
        XCTAssertNil(exitAck?.status.parameters)

        let failedStartAck = SunricherVendorStatus(parameters: Data([0x45, 0x07, 0x02]))
        XCTAssertEqual(failedStartAck?.status.isSuccessful, false)
        XCTAssertEqual(failedStartAck?.status.errorCode, 0x02)
        XCTAssertNil(failedStartAck?.status.parameters)
    }

    func testRxTxCableParsing() {
        let success = SunricherVendorStatus(parameters: Data([0x45, 0x00, 0x00]))
        XCTAssertEqual(success?.status.isSuccessful, true)
        XCTAssertEqual(success?.status.code, .elControllerRxTxCableConnection)
        XCTAssertNil(success?.status.parameters)

        let failure = SunricherVendorStatus(parameters: Data([0x45, 0x00, 0x05]))
        XCTAssertEqual(failure?.status.isSuccessful, false)
        XCTAssertEqual(failure?.status.errorCode, 0x05)
        XCTAssertNil(failure?.status.parameters)
    }

    func testDeviceStatusParsing() {
        let normal = SunricherVendorStatus(parameters: Data([0x45, 0x01, 0x00, 0x03]))
        XCTAssertEqual(normal?.status.isSuccessful, true)
        XCTAssertEqual(normal?.status.code, .elControllerDeviceStatus)
        if case .elControllerDeviceStatus(let status) = normal?.status.parameters {
            XCTAssertEqual(status.rawValue, 0x03)
            XCTAssertFalse(status.isFunctionTesting)
        } else {
            XCTFail("Expected EL Controller device status")
        }

        let testing = SunricherVendorStatus(parameters: Data([0x45, 0x01, 0x00, 0x0E]))
        if case .elControllerDeviceStatus(let status) = testing?.status.parameters {
            XCTAssertEqual(status.rawValue, 0x0E)
            XCTAssertTrue(status.isFunctionTesting)
        } else {
            XCTFail("Expected EL Controller function testing status")
        }

        let other = SunricherVendorStatus(parameters: Data([0x45, 0x01, 0x00, 0xAA]))
        if case .elControllerDeviceStatus(let status) = other?.status.parameters {
            XCTAssertEqual(status.rawValue, 0xAA)
            XCTAssertFalse(status.isFunctionTesting)
        } else {
            XCTFail("Expected EL Controller normal status for unknown raw value")
        }

        let shortSuccess = SunricherVendorStatus(parameters: Data([0x45, 0x01, 0x00]))
        XCTAssertEqual(shortSuccess?.status.isSuccessful, false)
        XCTAssertNil(shortSuccess?.status.parameters)
    }

    func testFunctionTestResultParsing() {
        let passed = SunricherVendorStatus(parameters: Data([0x45, 0x03, 0x00, 0x00, 0x00]))
        XCTAssertEqual(passed?.status.isSuccessful, true)
        XCTAssertEqual(passed?.status.code, .elControllerFunctionTestResult)
        if case .elControllerFunctionTestResult(let result) = passed?.status.parameters {
            XCTAssertEqual(result.faultBits, 0x00)
            XCTAssertTrue(result.isValid)
            XCTAssertFalse(result.hasFault)
            XCTAssertFalse(result.lampFault)
            XCTAssertFalse(result.batteryFault)
            XCTAssertFalse(result.circuitFault)
        } else {
            XCTFail("Expected EL Controller function test result")
        }

        let allFaults = SunricherVendorStatus(parameters: Data([0x45, 0x03, 0x00, 0x07, 0x00]))
        if case .elControllerFunctionTestResult(let result) = allFaults?.status.parameters {
            XCTAssertEqual(result.faultBits, 0x07)
            XCTAssertTrue(result.isValid)
            XCTAssertTrue(result.hasFault)
            XCTAssertTrue(result.lampFault)
            XCTAssertTrue(result.batteryFault)
            XCTAssertTrue(result.circuitFault)
        } else {
            XCTFail("Expected EL Controller fault result")
        }

        let invalid = SunricherVendorStatus(parameters: Data([0x45, 0x03, 0x00, 0x00, 0x07]))
        if case .elControllerFunctionTestResult(let result) = invalid?.status.parameters {
            XCTAssertFalse(result.isValid)
            XCTAssertFalse(result.hasFault)
        } else {
            XCTFail("Expected EL Controller invalid result")
        }

        let shortSuccess = SunricherVendorStatus(parameters: Data([0x45, 0x03, 0x00, 0x01]))
        XCTAssertEqual(shortSuccess?.status.isSuccessful, false)
        XCTAssertNil(shortSuccess?.status.parameters)
    }

    func testUnknownSubcodeIsRejected() {
        XCTAssertNil(SunricherVendorStatus(parameters: Data([0x45, 0x02, 0x00])))
    }

    func testVendorStatusMustMatchELControllerCommandCode() {
        let startHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .elControllerStartFunctionTest),
            address: 0x0003
        )
        let startAck = SunricherVendorStatus(parameters: Data([0x45, 0x07, 0x00]))!
        let rxTxAck = SunricherVendorStatus(parameters: Data([0x45, 0x00, 0x00]))!

        XCTAssertTrue(startHandle.matchesResponse(startAck, from: 0x0003))
        XCTAssertFalse(startHandle.matchesResponse(rxTxAck, from: 0x0003))

        let resultHandle = MeshMessageHandle(
            message: SunricherVendorGet(function: .elControllerFunctionTestResult),
            address: 0x0003
        )
        let result = SunricherVendorStatus(parameters: Data([0x45, 0x03, 0x00, 0x00, 0x00]))!
        let deviceStatus = SunricherVendorStatus(parameters: Data([0x45, 0x01, 0x00, 0x0E]))!

        XCTAssertTrue(resultHandle.matchesResponse(result, from: 0x0003))
        XCTAssertFalse(resultHandle.matchesResponse(deviceStatus, from: 0x0003))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
swift test --filter ELControllerVendorMessageTests
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: FAIL，错误包含 `type 'VendorFunctionSet' has no member 'elControllerStartFunctionTest'` 或 `type 'ResponseCode' has no member 'elControllerStartFunctionTest'`。

- [ ] **Step 3: 提交测试**

```bash
git add Tests/NordicSigMeshSDKTests/ELControllerVendorMessageTests.swift
git commit -m "test: add EL Controller vendor protocol coverage"
```

## Task 2: SDK 协议实现

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`

- [ ] **Step 1: 在 `SunricherVendorStatus.swift` 增加 EL Controller 主码、子码和解析数据类型**

在 `VendorOpCode` 的 `led = 0x44` 后加入：

```swift
    /// EL Controller function test / RXTX cable
    case elController = 0x45
```

在 `VendorUpDownLightCode` 前加入：

```swift
/// EL Controller code
public enum VendorELControllerCode: UInt8 {
    case rxTxCableConnection = 0x00
    case deviceStatus = 0x01
    case functionTestResult = 0x03
    case startFunctionTest = 0x07
    case exitFunctionTest = 0x08
}

public struct ELControllerDeviceStatus: Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public var isFunctionTesting: Bool {
        rawValue == 0x0E
    }
}

public struct ELControllerFunctionTestResult: Equatable {
    public let faultBits: UInt8
    public let validity: UInt8

    public init(faultBits: UInt8, validity: UInt8) {
        self.faultBits = faultBits
        self.validity = validity
    }

    public var isValid: Bool {
        validity == 0x00
    }

    public var lampFault: Bool {
        (faultBits & 0x01) != 0
    }

    public var batteryFault: Bool {
        (faultBits & 0x02) != 0
    }

    public var circuitFault: Bool {
        (faultBits & 0x04) != 0
    }

    public var hasFault: Bool {
        isValid && (lampFault || batteryFault || circuitFault)
    }
}
```

- [ ] **Step 2: 扩展 `ResponseCode`**

在 `init?(opcode:subcode:)` 中增加 `case .elController`：

```swift
        case .elController:
            switch subcode {
            case VendorELControllerCode.rxTxCableConnection.rawValue:
                self = .elControllerRxTxCableConnection
            case VendorELControllerCode.deviceStatus.rawValue:
                self = .elControllerDeviceStatus
            case VendorELControllerCode.functionTestResult.rawValue:
                self = .elControllerFunctionTestResult
            case VendorELControllerCode.startFunctionTest.rawValue:
                self = .elControllerStartFunctionTest
            case VendorELControllerCode.exitFunctionTest.rawValue:
                self = .elControllerExitFunctionTest
            default:
                return nil
            }
```

在 `ResponseCode` 枚举的 Up Down Light 前增加：

```swift
    /// EL Controller RX/TX Cable connection
    case elControllerRxTxCableConnection
    /// EL Controller device status
    case elControllerDeviceStatus
    /// EL Controller function test result
    case elControllerFunctionTestResult
    /// EL Controller start function test
    case elControllerStartFunctionTest
    /// EL Controller exit function test
    case elControllerExitFunctionTest
```

在 `ResponseCode.code` switch 的 Up Down Light 前增加：

```swift
        case .elControllerRxTxCableConnection:
            return [VendorOpCode.elController.rawValue, VendorELControllerCode.rxTxCableConnection.rawValue]
        case .elControllerDeviceStatus:
            return [VendorOpCode.elController.rawValue, VendorELControllerCode.deviceStatus.rawValue]
        case .elControllerFunctionTestResult:
            return [VendorOpCode.elController.rawValue, VendorELControllerCode.functionTestResult.rawValue]
        case .elControllerStartFunctionTest:
            return [VendorOpCode.elController.rawValue, VendorELControllerCode.startFunctionTest.rawValue]
        case .elControllerExitFunctionTest:
            return [VendorOpCode.elController.rawValue, VendorELControllerCode.exitFunctionTest.rawValue]
```

- [ ] **Step 3: 扩展 `SunricherVendorStatus.Status.init(data:)` 的参数解析**

在设置 `self.code = responseCode` 后、`if data.count >= 4` 前增加短包判定：

```swift
            if status == 0 {
                switch responseCode {
                case .elControllerDeviceStatus where data.count < 4:
                    self.isSuccessful = false
                    self.parameters = nil
                    return
                case .elControllerFunctionTestResult where data.count < 5:
                    self.isSuccessful = false
                    self.parameters = nil
                    return
                default:
                    break
                }
            }
```

在 `if data.count >= 4` 的 switch 中、Up Down Light 前增加：

```swift
                case .elControllerRxTxCableConnection,
                        .elControllerStartFunctionTest,
                        .elControllerExitFunctionTest:
                    self.parameters = nil
                case .elControllerDeviceStatus:
                    guard isSuccessful else {
                        self.parameters = nil
                        break
                    }
                    let rawStatus: UInt8 = data.read(fromOffset: 3)
                    self.parameters = .elControllerDeviceStatus(.init(rawValue: rawStatus))
                case .elControllerFunctionTestResult:
                    guard isSuccessful else {
                        self.parameters = nil
                        break
                    }
                    let faultBits: UInt8 = data.read(fromOffset: 3)
                    let validity: UInt8 = data.read(fromOffset: 4)
                    self.parameters = .elControllerFunctionTestResult(.init(faultBits: faultBits, validity: validity))
```

在 `FunctionParameters` 的 Up Down Light 前增加：

```swift
    //****** EL Controller *****/
    /// EL Controller device status
    case elControllerDeviceStatus(ELControllerDeviceStatus)
    /// EL Controller function test result
    case elControllerFunctionTestResult(ELControllerFunctionTestResult)
```

- [ ] **Step 4: 扩展 `SunricherVendorSet.swift`**

在 `VendorFunctionSet.data` switch 的 Up Down Light 前增加：

```swift
        case .elControllerStartFunctionTest,
                .elControllerExitFunctionTest:
            return data
```

在 `VendorFunctionSet.command` switch 的 Up Down Light 前增加：

```swift
        case .elControllerStartFunctionTest: return .elControllerStartFunctionTest
        case .elControllerExitFunctionTest: return .elControllerExitFunctionTest
```

在 `VendorFunctionSet` 枚举的 Up Down Light 前增加：

```swift
    //********** EL Controller ***********/
    /// Start Function Test
    case elControllerStartFunctionTest
    /// Exit Function Test
    case elControllerExitFunctionTest
```

- [ ] **Step 5: 扩展 `SunricherVendorGet.swift`**

在 `VendorFunctionGet.command` switch 的 Up Down Light 前增加：

```swift
        case .elControllerRxTxCableConnection: return .elControllerRxTxCableConnection
        case .elControllerDeviceStatus: return .elControllerDeviceStatus
        case .elControllerFunctionTestResult: return .elControllerFunctionTestResult
```

在 `VendorFunctionGet` 枚举的 Up Down Light 前增加：

```swift
    //********** EL Controller ***********/
    /// Check RX/TX Cable Connection
    case elControllerRxTxCableConnection
    /// Get Device Status
    case elControllerDeviceStatus
    /// Get Function Test Result
    case elControllerFunctionTestResult
```

- [ ] **Step 6: 运行 SDK 聚焦测试**

Run:

```bash
swift test --filter ELControllerVendorMessageTests
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: PASS。若 `swift test` 被 UIKit 或既有包测试环境阻塞，记录第一条阻塞错误，继续执行 Task 5 的 iPhoneOS build 验证。

- [ ] **Step 7: 提交 SDK 实现**

```bash
git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift
git commit -m "feat: add EL Controller vendor protocol"
```

## Task 3: App 卡片改成协议驱动状态

**Files:**
- Modify: `SunSmart/Main/Device/View/ELControllerFunctionTestView.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`

- [ ] **Step 1: 替换本地循环状态为外部状态 API**

在 `ELControllerFunctionTestView` 的 `Kind` 后增加：

```swift
    enum FunctionTestState {
        case idle
        case awaiting
        case passed
        case faults(lamp: Bool, battery: Bool, circuit: Bool)
        case invalid
        case failed
    }

    enum RxTxState {
        case idle
        case checking
        case normal
        case fault
    }
```

把 `stateIndex` 属性替换为：

```swift
    var onAction: (() -> Void)?
    private var currentState: DisplayState
```

把 `private var states: [DisplayState]` 整段替换为这些工厂方法：

```swift
    private static func functionTestDisplayState(_ state: FunctionTestState) -> DisplayState {
        switch state {
        case .idle:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_start_prompt", style: .neutral)],
                showsSpinner: false
            )
        case .awaiting:
            return .init(
                buttonTitleKey: "el_controller_function_test_testing_button",
                buttonAlpha: 0.6,
                rows: [.init(titleKey: "el_controller_function_test_awaiting", style: .waiting)],
                showsSpinner: true
            )
        case .passed:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_passed", style: .success)],
                showsSpinner: false
            )
        case .faults(let lamp, let battery, let circuit):
            var rows: [DisplayRow] = []
            if lamp {
                rows.append(.init(titleKey: "el_controller_function_test_lamp_fault", style: .warning))
            }
            if battery {
                rows.append(.init(titleKey: "el_controller_function_test_battery_fault", style: .fault))
            }
            if circuit {
                rows.append(.init(titleKey: "el_controller_function_test_circuit_fault", style: .fault))
            }
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: rows.isEmpty ? [.init(titleKey: "el_controller_function_test_passed", style: .success)] : rows,
                showsSpinner: false
            )
        case .invalid:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_invalid", style: .warning)],
                showsSpinner: false
            )
        case .failed:
            return .init(
                buttonTitleKey: "el_controller_function_test_start_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_function_test_failed", style: .fault)],
                showsSpinner: false
            )
        }
    }

    private static func rxTxDisplayState(_ state: RxTxState) -> DisplayState {
        switch state {
        case .idle:
            return .init(
                buttonTitleKey: "el_controller_rxtx_check_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_rxtx_start_prompt", style: .neutral)],
                showsSpinner: false
            )
        case .checking:
            return .init(
                buttonTitleKey: "el_controller_rxtx_checking_button",
                buttonAlpha: 0.6,
                rows: [.init(titleKey: "el_controller_rxtx_checking_connection", style: .waiting)],
                showsSpinner: true
            )
        case .normal:
            return .init(
                buttonTitleKey: "el_controller_rxtx_check_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_rxtx_connection_normal", style: .success)],
                showsSpinner: false
            )
        case .fault:
            return .init(
                buttonTitleKey: "el_controller_rxtx_check_button",
                buttonAlpha: 1,
                rows: [.init(titleKey: "el_controller_rxtx_connection_fault", style: .fault)],
                showsSpinner: false
            )
        }
    }
```

把 `init(kind:)` 改为：

```swift
    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .functionTest:
            self.currentState = Self.functionTestDisplayState(.idle)
        case .rxTxCable:
            self.currentState = Self.rxTxDisplayState(.idle)
        }
        super.init(frame: .zero)
        setupUI()
        applyCurrentState()
    }
```

新增公开状态方法：

```swift
    func applyFunctionTestState(_ state: FunctionTestState) {
        guard kind == .functionTest else { return }
        currentState = Self.functionTestDisplayState(state)
        applyCurrentState()
    }

    func applyRxTxState(_ state: RxTxState) {
        guard kind == .rxTxCable else { return }
        currentState = Self.rxTxDisplayState(state)
        applyCurrentState()
    }
```

把 `applyCurrentState()` 第一行改为：

```swift
        let state = currentState
```

把 `actionButtonTapped` 改为：

```swift
    @objc private func actionButtonTapped() {
        guard actionButton.isEnabled else { return }
        onAction?()
    }
```

在 `applyCurrentState()` 设置按钮标题后增加：

```swift
        actionButton.isEnabled = !state.showsSpinner
```

- [ ] **Step 2: 补齐本地化文案**

在 `SunSmart/en.lproj/Localizable.strings` 的 EL Controller 文案块中加入：

```text
"el_controller_function_test_start_button" = "Start";
"el_controller_function_test_testing_button" = "Testing...";
"el_controller_function_test_invalid" = "Invalid Result";
"el_controller_function_test_failed" = "Test Failed";
"el_controller_rxtx_check_button" = "Check";
```

在 `SunSmart/zh-Hans.lproj/Localizable.strings` 的 EL Controller 文案块中加入：

```text
"el_controller_function_test_start_button" = "开始";
"el_controller_function_test_testing_button" = "测试中...";
"el_controller_function_test_invalid" = "结果无效";
"el_controller_function_test_failed" = "测试失败";
"el_controller_rxtx_check_button" = "检查";
```

- [ ] **Step 3: 静态检查调用点**

Run:

```bash
rg -n "\"Start\"|\"testing…\"|\"check\"|stateIndex|states" SunSmart/Main/Device/View/ELControllerFunctionTestView.swift
```

Expected: 没有输出。

- [ ] **Step 4: 提交 UI 状态改造**

```bash
git add SunSmart/Main/Device/View/ELControllerFunctionTestView.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings
git commit -m "feat: make EL Controller cards protocol driven"
```

## Task 4: App 命令发送与主动上报处理

**Files:**
- Modify: `SunSmart/Main/Device/Controller/DeviceLightViewController.swift`

- [ ] **Step 1: 在创建两张卡片时绑定按钮动作**

在 `setupEmergencySignUI()` 创建 `functionTestView` 后增加：

```swift
            functionTestView.onAction = { [weak self] in
                self?.startELControllerFunctionTest()
            }
```

在创建 `rxTxCableView` 后增加：

```swift
            rxTxCableView.onAction = { [weak self] in
                self?.checkELControllerRxTxCable()
            }
```

- [ ] **Step 2: 增加命令发送方法**

在 `setELControllerFunctionViewsHidden(_:)` 后加入：

```swift
    private func startELControllerFunctionTest() {
        guard supportsELControllerLocalFunctionViews, node.isKeybindComplete, node.state else {
            XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            elFunctionTestView?.applyFunctionTestState(.failed)
            return
        }

        elFunctionTestView?.applyFunctionTestState(.awaiting)
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .elControllerStartFunctionTest), model: vendorModel) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerStartFunctionTest,
                      status.status.isSuccessful else {
                    self.elFunctionTestView?.applyFunctionTestState(.failed)
                    return
                }
                self.elFunctionTestView?.applyFunctionTestState(.awaiting)
            }
        }
    }

    private func checkELControllerRxTxCable() {
        guard supportsELControllerLocalFunctionViews, node.isKeybindComplete, node.state else {
            XWHUDManager.showTipHUD("device_offline_message".localizedString, isLineFeed: true)
            return
        }
        guard let vendorModel = node.sunricherVendorModel else {
            elRxTxCableView?.applyRxTxState(.fault)
            return
        }

        elRxTxCableView?.applyRxTxState(.checking)
        MeshAPI.sendMessage(message: SunricherVendorGet(function: .elControllerRxTxCableConnection), model: vendorModel) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let status = response as? SunricherVendorStatus,
                      status.status.code == .elControllerRxTxCableConnection,
                      status.status.isSuccessful else {
                    self.elRxTxCableView?.applyRxTxState(.fault)
                    return
                }
                self.elRxTxCableView?.applyRxTxState(.normal)
            }
        }
    }
```

- [ ] **Step 3: 增加上报处理方法**

在 Step 2 的方法后加入：

```swift
    private func handleELControllerVendorStatus(_ status: SunricherVendorStatus, sentFrom source: Address) {
        guard supportsELControllerLocalFunctionViews else { return }
        var expectedSources: [Address] = [node.primaryUnicastAddress]
        if let vendorAddress = node.sunricherVendorModel?.parentElement?.unicastAddress, vendorAddress != node.primaryUnicastAddress {
            expectedSources.append(vendorAddress)
        }
        guard expectedSources.contains(source) else { return }

        switch status.status.code {
        case .elControllerRxTxCableConnection:
            elRxTxCableView?.applyRxTxState(status.status.isSuccessful ? .normal : .fault)
        case .elControllerDeviceStatus:
            guard status.status.isSuccessful,
                  case .elControllerDeviceStatus(let deviceStatus) = status.status.parameters else {
                return
            }
            if deviceStatus.isFunctionTesting {
                elFunctionTestView?.applyFunctionTestState(.awaiting)
            }
        case .elControllerFunctionTestResult:
            guard status.status.isSuccessful,
                  case .elControllerFunctionTestResult(let result) = status.status.parameters else {
                elFunctionTestView?.applyFunctionTestState(.failed)
                return
            }
            applyELControllerFunctionTestResult(result)
        case .elControllerStartFunctionTest,
                .elControllerExitFunctionTest:
            break
        default:
            break
        }
    }

    private func applyELControllerFunctionTestResult(_ result: ELControllerFunctionTestResult) {
        guard result.isValid else {
            elFunctionTestView?.applyFunctionTestState(.invalid)
            return
        }
        guard result.hasFault else {
            elFunctionTestView?.applyFunctionTestState(.passed)
            return
        }
        elFunctionTestView?.applyFunctionTestState(.faults(
            lamp: result.lampFault,
            battery: result.batteryFault,
            circuit: result.circuitFault
        ))
    }
```

- [ ] **Step 4: 接入 `MeshLibManagerMessageDelegate`**

在 `meshNetworkManager(_:didReceiveMessage:sentFrom:to:)` 开头加入：

```swift
        if let status = message as? SunricherVendorStatus {
            handleELControllerVendorStatus(status, sentFrom: source)
        }
```

完整方法结构为：

```swift
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        if let status = message as? SunricherVendorStatus {
            handleELControllerVendorStatus(status, sentFrom: source)
        }

        if let node = manager.meshNetwork?.node(withAddress: source), !node.isProvisioner {
            node.updateData(message: message)
            if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
                updateData()
            }
        }
    }
```

- [ ] **Step 5: 静态检查 App 接入**

Run:

```bash
rg -n "elControllerStartFunctionTest|elControllerRxTxCableConnection|elControllerFunctionTestResult|handleELControllerVendorStatus|applyELControllerFunctionTestResult" SunSmart/Main/Device/Controller/DeviceLightViewController.swift
```

Expected: 输出包含新增发送方法和 delegate 上报处理。

- [ ] **Step 6: 提交 App 接入**

```bash
git add SunSmart/Main/Device/Controller/DeviceLightViewController.swift
git commit -m "feat: wire EL Controller vendor commands"
```

## Task 5: 验证与收尾

**Files:**
- Check: SDK working tree
- Check: App working tree

- [ ] **Step 1: 检查补丁空白**

Run:

```bash
git diff --check
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: 没有输出。

Run:

```bash
git diff --check
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/BL9036T-PCBA
```

Expected: 没有输出。

- [ ] **Step 2: 运行 SDK 聚焦测试**

Run:

```bash
swift test --filter ELControllerVendorMessageTests
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: PASS。若 `swift test` 被 UIKit 或既有包测试环境阻塞，最终总结中写出阻塞命令和首条错误。

- [ ] **Step 3: 构建 SDK Demo iPhoneOS**

Run:

```bash
xcodebuild -project NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 构建 SunSmart iPhoneOS**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Workdir:

```text
/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/BL9036T-PCBA
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 5: 汇总最终行为**

确认最终实现满足：

- Function Test `Start` 发送 `F0 78 0A | 45 07`，ACK 成功后卡片保持 `Awaiting device response...`。
- Function Test 结果只由 `F3 78 0A | 45 03 00 <faultBits> <validity>` 或同结构 GET 应答驱动，不新增轮询。
- RX/TX `Check` 发送 `F1 78 0A | 45 00`，`ret == 0` 显示 `Connection Normal`，非 0 或超时显示 `Connection Fault`。
- SDK 支持 `GET 0x01`、`GET 0x03`、`SET 0x08`，当前 UI 不主动调用 `GET 0x01`、`GET 0x03`、`SET 0x08`。
- App UI 调用仍由 `supportsELControllerLocalFunctionViews` 限制在当前产品，SDK 无 PID 限制。

## 自审

- 规格覆盖：Task 1 和 Task 2 覆盖 SET/GET/RET 编解码、`ret` 语义、Function Test result 两字节解析和同 opcode 子码匹配；Task 3 和 Task 4 覆盖当前页面 UI 调用和上报处理；Task 5 覆盖 SDK 与 App 验证。
- 类型一致性：计划统一使用 `VendorELControllerCode`、`ELControllerDeviceStatus`、`ELControllerFunctionTestResult`、`elControllerStartFunctionTest`、`elControllerExitFunctionTest`、`elControllerRxTxCableConnection`、`elControllerDeviceStatus`、`elControllerFunctionTestResult`。
- 监听策略：主动上报走 `MeshLibManagerMessageDelegate`，不注册长生命周期 `waitFor`，避免与 `MeshAPI.sendMessage` 对同一 `RET 0xF3780A` 的一次性 ACK 回调互相取消。
