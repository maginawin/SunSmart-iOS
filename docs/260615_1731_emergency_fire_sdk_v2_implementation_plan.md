# Emergency Fire SDK v2 Protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Project preference is Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SDK Emergency Fire `0x4D` protocol implementation with the v2 wire format for `0x01...0x07`, dropping the old v1.3.6 API.

**Architecture:** Keep the existing `SunricherVendorGet`, `SunricherVendorSet`, and `SunricherVendorStatus` message entry points. Replace old Emergency Controller public types with v2 `EmergencyFire*` types, make old App call sites fail at compile time, and lock the new wire format with SDK unit tests.

**Tech Stack:** Swift, XCTest, NordicSigMeshSDK vendor message layer, local SDK path `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`.

---

## File Structure

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift`
  - Rewrite the existing tests from old v1.3.6 assertions to v2 wire-format assertions.
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - Rename Emergency Fire subcode semantics.
  - Replace old mode/index/resend/status structs with v2 model structs.
  - Add action type and action config encoding/decoding helpers.
  - Update status parsing for `0x01...0x07`.
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
  - Replace old Emergency Controller GET cases with v2 cases.
  - Encode GET payloads for `0x01...0x07`.
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
  - Replace old Emergency Controller SET cases with v2 cases.
  - Encode SET payloads for resend, enabled, restore delay, and action config.

## Task 1: Rewrite SDK Tests for v2 Wire Format

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift`

- [ ] **Step 1: Replace the test file with v2 expectations**

Replace the full file with:

```swift
import XCTest
@testable import NordicSigMeshSDK

final class EmergencyControllerVendorMessageTests: XCTestCase {

    func testEmergencyFireV2GetEncoding() {
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencySceneConfig(stateIndex: .emergencyTrigger)).parameters,
            Data([0x4D, 0x01, 0x00])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencyDetailStatus).parameters,
            Data([0x4D, 0x02])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencyResendParameters(stateIndex: .restore)).parameters,
            Data([0x4D, 0x03, 0x02])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencyComprehensiveStatus).parameters,
            Data([0x4D, 0x04])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencyEnabled).parameters,
            Data([0x4D, 0x05])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencyRestoreDelay).parameters,
            Data([0x4D, 0x06])
        )
        XCTAssertEqual(
            SunricherVendorGet(function: .emergencyActionConfig(stateIndex: .fireTrigger)).parameters,
            Data([0x4D, 0x07, 0x01])
        )
    }

    func testEmergencyFireV2SetEncoding() {
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyResendParameters(.init(stateIndex: .restore, intervalSeconds: 5, count: 10))).parameters,
            Data([0x4D, 0x03, 0x02, 0x05, 0x00, 0x0A, 0x00])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyEnabled(true)).parameters,
            Data([0x4D, 0x05, 0x01])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyEnabled(false)).parameters,
            Data([0x4D, 0x05, 0x00])
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyRestoreDelay(seconds: 2)).parameters,
            Data([0x4D, 0x06, 0x02])
        )

        let invalid = EmergencyFireActionConfig(
            stateIndex: .fireTrigger,
            action: .invalid,
            stage1Target: 0xC001,
            stage2Target: 0xC002,
            appKeyIndex: 0x0000,
            ttl: 10,
            transitionTime: 0,
            delay: 0
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyActionConfig(invalid)).parameters,
            Data([0x4D, 0x07, 0x01, 0xFF, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00])
        )

        let lightness = EmergencyFireActionConfig(
            stateIndex: .emergencyTrigger,
            action: .lightness(0xFFFF),
            stage1Target: 0xC001,
            stage2Target: 0xC002,
            appKeyIndex: 0x0000,
            ttl: 10,
            transitionTime: 0,
            delay: 0
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyActionConfig(lightness)).parameters,
            Data([0x4D, 0x07, 0x00, 0x06, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0xFF, 0xFF])
        )

        let ctl = EmergencyFireActionConfig(
            stateIndex: .restore,
            action: .ctl(lightness: 0x8000, temperature: 6500, deltaUV: 0),
            stage1Target: 0xC001,
            stage2Target: 0xC002,
            appKeyIndex: 0x0000,
            ttl: 10,
            transitionTime: 0,
            delay: 0
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyActionConfig(ctl)).parameters,
            Data([0x4D, 0x07, 0x02, 0x07, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x80, 0x64, 0x19, 0x00, 0x00])
        )

        let hsl = EmergencyFireActionConfig(
            stateIndex: .fireTrigger,
            action: .hsl(lightness: 0xFFFF, hue: 0, saturation: 0xFFFF),
            stage1Target: 0xC001,
            stage2Target: 0xC002,
            appKeyIndex: 0x0000,
            ttl: 10,
            transitionTime: 0,
            delay: 0
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyActionConfig(hsl)).parameters,
            Data([0x4D, 0x07, 0x01, 0x09, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF])
        )

        let levelDelta = EmergencyFireActionConfig(
            stateIndex: .emergencyTrigger,
            action: .levelDelta(-1000),
            stage1Target: 0xC001,
            stage2Target: 0xC002,
            appKeyIndex: 0x0000,
            ttl: 10,
            transitionTime: 0,
            delay: 0
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyActionConfig(levelDelta)).parameters,
            Data([0x4D, 0x07, 0x00, 0x02, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x18, 0xFC, 0xFF, 0xFF])
        )

        let powerLevel = EmergencyFireActionConfig(
            stateIndex: .restore,
            action: .powerLevel(0x1234),
            stage1Target: 0xC001,
            stage2Target: 0xC002,
            appKeyIndex: 0x0000,
            ttl: 10,
            transitionTime: 0,
            delay: 0
        )
        XCTAssertEqual(
            SunricherVendorSet(function: .emergencyActionConfig(powerLevel)).parameters,
            Data([0x4D, 0x07, 0x02, 0x0C, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x34, 0x12])
        )
    }

    func testEmergencyFireV2StatusParsing() {
        let sceneStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x01, 0x00, 0x01, 0x02, 0xC0, 0x21, 0xFF]))
        XCTAssertEqual(sceneStatus?.status.isSuccessful, true)
        if case .emergencySceneConfig(let config) = sceneStatus?.status.parameters {
            XCTAssertEqual(config.stateIndex, .fireTrigger)
            XCTAssertEqual(config.stage2Target, 0xC002)
            XCTAssertEqual(config.sceneNumber, 0xFF21)
        } else {
            XCTFail("Expected emergency scene config parameters")
        }

        let detailStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x02, 0x00, 0xE8, 0x03, 0xD0, 0x07, 0x01, 0x00, 0x01, 0x01, 0x00]))
        XCTAssertEqual(detailStatus?.status.isSuccessful, true)
        if case .emergencyDetailStatus(let detail) = detailStatus?.status.parameters {
            XCTAssertEqual(detail.fireMillivolts, 1000)
            XCTAssertEqual(detail.emergencyMillivolts, 2000)
            XCTAssertEqual(detail.fireActive, true)
            XCTAssertEqual(detail.emergencyActive, false)
            XCTAssertEqual(detail.powerLossLevel, 1)
            XCTAssertEqual(detail.powerLossInputActive, true)
            XCTAssertEqual(detail.emergencyAdcActive, false)
        } else {
            XCTFail("Expected emergency detail status parameters")
        }

        let resendStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x02, 0x05, 0x00, 0x0A, 0x00]))
        XCTAssertEqual(resendStatus?.status.isSuccessful, true)
        if case .emergencyResendParameters(let parameters) = resendStatus?.status.parameters {
            XCTAssertEqual(parameters.stateIndex, .restore)
            XCTAssertEqual(parameters.intervalSeconds, 5)
            XCTAssertEqual(parameters.count, 10)
        } else {
            XCTFail("Expected emergency resend parameters")
        }

        let comprehensiveStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x04, 0x00, 0x01, 0x01, 0x00, 0x01]))
        XCTAssertEqual(comprehensiveStatus?.status.isSuccessful, true)
        if case .emergencyComprehensiveStatus(let status) = comprehensiveStatus?.status.parameters {
            XCTAssertEqual(status.enabled, true)
            XCTAssertEqual(status.fireActive, true)
            XCTAssertEqual(status.emergencyActive, false)
            XCTAssertEqual(status.everTriggered, true)
        } else {
            XCTFail("Expected emergency comprehensive status")
        }

        let enabledStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x05, 0x00, 0x01]))
        XCTAssertEqual(enabledStatus?.status.isSuccessful, true)
        if case .emergencyEnabled(let enabled) = enabledStatus?.status.parameters {
            XCTAssertEqual(enabled, true)
        } else {
            XCTFail("Expected emergency enabled")
        }

        let restoreDelayStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x06, 0x00, 0x78]))
        XCTAssertEqual(restoreDelayStatus?.status.isSuccessful, true)
        if case .emergencyRestoreDelay(let seconds) = restoreDelayStatus?.status.parameters {
            XCTAssertEqual(seconds, 120)
        } else {
            XCTFail("Expected emergency restore delay")
        }

        let actionAck = SunricherVendorStatus(parameters: Data([0x4D, 0x07, 0x00, 0x01, 0x09]))
        XCTAssertEqual(actionAck?.status.isSuccessful, true)
        if case .emergencyActionConfigAck(let ack) = actionAck?.status.parameters {
            XCTAssertEqual(ack.stateIndex, .fireTrigger)
            XCTAssertEqual(ack.actionType, .hsl)
        } else {
            XCTFail("Expected emergency action config ack")
        }

        let actionConfig = SunricherVendorStatus(parameters: Data([0x4D, 0x07, 0x00, 0x01, 0x09, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF]))
        XCTAssertEqual(actionConfig?.status.isSuccessful, true)
        if case .emergencyActionConfig(let config) = actionConfig?.status.parameters {
            XCTAssertEqual(config.stateIndex, .fireTrigger)
            XCTAssertEqual(config.stage1Target, 0xC001)
            XCTAssertEqual(config.stage2Target, 0xC002)
            XCTAssertEqual(config.appKeyIndex, 0)
            XCTAssertEqual(config.ttl, 10)
            XCTAssertEqual(config.transitionTime, 0)
            XCTAssertEqual(config.delay, 0)
            XCTAssertEqual(config.action, .hsl(lightness: 0xFFFF, hue: 0, saturation: 0xFFFF))
        } else {
            XCTFail("Expected emergency action config")
        }

        let invalidActionConfig = SunricherVendorStatus(parameters: Data([0x4D, 0x07, 0x00, 0x02, 0xFF]))
        XCTAssertEqual(invalidActionConfig?.status.isSuccessful, true)
        if case .emergencyActionConfig(let config) = invalidActionConfig?.status.parameters {
            XCTAssertEqual(config.stateIndex, .restore)
            XCTAssertEqual(config.action, .invalid)
        } else {
            XCTFail("Expected invalid emergency action config")
        }
    }

    func testEmergencyFireV2StatusErrorsAndInvalidPayloads() {
        let errorStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x05, 0x04, 0x02]))
        XCTAssertEqual(errorStatus?.status.isSuccessful, false)
        XCTAssertEqual(errorStatus?.status.errorCode, 0x04)
        XCTAssertNil(errorStatus?.status.parameters)

        let invalidStateIndex = SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x03, 0x05, 0x00, 0x0A, 0x00]))
        XCTAssertEqual(invalidStateIndex?.status.isSuccessful, false)
        XCTAssertNil(invalidStateIndex?.status.parameters)

        let invalidActionType = SunricherVendorStatus(parameters: Data([0x4D, 0x07, 0x00, 0x01, 0x0D]))
        XCTAssertEqual(invalidActionType?.status.isSuccessful, false)
        XCTAssertNil(invalidActionType?.status.parameters)

        let shortActionParams = SunricherVendorStatus(parameters: Data([0x4D, 0x07, 0x00, 0x01, 0x09, 0x01, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x0A, 0x00, 0x00, 0xFF]))
        XCTAssertEqual(shortActionParams?.status.isSuccessful, false)
        XCTAssertNil(shortActionParams?.status.parameters)

        let oldModeActiveStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x04, 0x00, 0x01, 0x01]))
        XCTAssertEqual(oldModeActiveStatus?.status.isSuccessful, false)
        XCTAssertNil(oldModeActiveStatus?.status.parameters)
    }
}
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test --filter EmergencyControllerVendorMessageTests`

Expected:

- Build fails because v2 symbols such as `EmergencyFireStateIndex`, `emergencyComprehensiveStatus`, and `emergencyActionConfig` do not exist yet.

- [ ] **Step 3: Commit the failing test**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && git add Tests/NordicSigMeshSDKTests/EmergencyControllerVendorMessageTests.swift && git commit -m "Test emergency fire v2 vendor messages"`

## Task 2: Replace Emergency Fire SDK Types with v2 Models

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: Replace the old Fire Emergency subcode enum**

In `SunricherVendorStatus.swift`, replace `VendorFireEmergencySceneCode` with:

```swift
/// Emergency Fire v2 subcodes under vendor opcode 0x4D.
public enum VendorFireEmergencySceneCode: UInt8 {
    case sceneConfig = 0x01
    case detailStatus = 0x02
    case resendParameters = 0x03
    case comprehensiveStatus = 0x04
    case enabled = 0x05
    case restoreDelay = 0x06
    case actionConfig = 0x07
}
```

- [ ] **Step 2: Replace old Emergency Controller structs**

In `SunricherVendorStatus.swift`, replace `EmergencyControllerMode`, `EmergencyControllerSceneIndex`, `EmergencyControllerSceneConfig`, `EmergencyControllerDetailStatus`, `EmergencyControllerResendParameters`, and `EmergencyControllerCurrentModeStatus` with:

```swift
public enum EmergencyFireStateIndex: UInt8, Equatable {
    case emergencyTrigger = 0
    case fireTrigger = 1
    case restore = 2
}

public enum EmergencyFireActionType: UInt8, Equatable {
    case onOff = 0x01
    case levelDelta = 0x02
    case levelMove = 0x03
    case sceneRecall = 0x04
    case lightControlOnOff = 0x05
    case lightness = 0x06
    case ctl = 0x07
    case ctlTemperature = 0x08
    case hsl = 0x09
    case hslHue = 0x0A
    case hslSaturation = 0x0B
    case powerLevel = 0x0C
    case invalid = 0xFF
}

public enum EmergencyFireAction: Equatable {
    case onOff(UInt8)
    case levelDelta(Int32)
    case levelMove(Int16)
    case sceneRecall(SceneNumber)
    case lightControlOnOff(UInt8)
    case lightness(UInt16)
    case ctl(lightness: UInt16, temperature: UInt16, deltaUV: Int16)
    case ctlTemperature(temperature: UInt16, deltaUV: Int16)
    case hsl(lightness: UInt16, hue: UInt16, saturation: UInt16)
    case hslHue(UInt16)
    case hslSaturation(UInt16)
    case powerLevel(UInt16)
    case invalid

    public var actionType: EmergencyFireActionType {
        switch self {
        case .onOff: return .onOff
        case .levelDelta: return .levelDelta
        case .levelMove: return .levelMove
        case .sceneRecall: return .sceneRecall
        case .lightControlOnOff: return .lightControlOnOff
        case .lightness: return .lightness
        case .ctl: return .ctl
        case .ctlTemperature: return .ctlTemperature
        case .hsl: return .hsl
        case .hslHue: return .hslHue
        case .hslSaturation: return .hslSaturation
        case .powerLevel: return .powerLevel
        case .invalid: return .invalid
        }
    }

    public var parameterData: Data {
        switch self {
        case .onOff(let value):
            return Data([value])
        case .levelDelta(let delta):
            return Data() + UInt32(bitPattern: delta)
        case .levelMove(let delta):
            return Data() + UInt16(bitPattern: delta)
        case .sceneRecall(let sceneNumber):
            return Data() + sceneNumber
        case .lightControlOnOff(let value):
            return Data([value])
        case .lightness(let lightness):
            return Data() + lightness
        case .ctl(let lightness, let temperature, let deltaUV):
            return Data() + lightness + temperature + UInt16(bitPattern: deltaUV)
        case .ctlTemperature(let temperature, let deltaUV):
            return Data() + temperature + UInt16(bitPattern: deltaUV)
        case .hsl(let lightness, let hue, let saturation):
            return Data() + lightness + hue + saturation
        case .hslHue(let hue):
            return Data() + hue
        case .hslSaturation(let saturation):
            return Data() + saturation
        case .powerLevel(let power):
            return Data() + power
        case .invalid:
            return Data()
        }
    }
}

public struct EmergencyFireSceneConfig {
    public let stateIndex: EmergencyFireStateIndex
    public let stage2Target: Address
    public let sceneNumber: SceneNumber

    public init(stateIndex: EmergencyFireStateIndex, stage2Target: Address, sceneNumber: SceneNumber) {
        self.stateIndex = stateIndex
        self.stage2Target = stage2Target
        self.sceneNumber = sceneNumber
    }
}

public struct EmergencyFireDetailStatus {
    public let fireMillivolts: UInt16
    public let emergencyMillivolts: UInt16
    public let fireActive: Bool
    public let emergencyActive: Bool
    public let powerLossLevel: UInt8
    public let powerLossInputActive: Bool
    public let emergencyAdcActive: Bool

    public init(fireMillivolts: UInt16, emergencyMillivolts: UInt16, fireActive: Bool, emergencyActive: Bool, powerLossLevel: UInt8, powerLossInputActive: Bool, emergencyAdcActive: Bool) {
        self.fireMillivolts = fireMillivolts
        self.emergencyMillivolts = emergencyMillivolts
        self.fireActive = fireActive
        self.emergencyActive = emergencyActive
        self.powerLossLevel = powerLossLevel
        self.powerLossInputActive = powerLossInputActive
        self.emergencyAdcActive = emergencyAdcActive
    }
}

public struct EmergencyFireResendParameters {
    public let stateIndex: EmergencyFireStateIndex
    public let intervalSeconds: UInt16
    public let count: UInt16

    public init(stateIndex: EmergencyFireStateIndex, intervalSeconds: UInt16, count: UInt16) {
        self.stateIndex = stateIndex
        self.intervalSeconds = intervalSeconds
        self.count = count
    }
}

public struct EmergencyFireComprehensiveStatus {
    public let enabled: Bool
    public let fireActive: Bool
    public let emergencyActive: Bool
    public let everTriggered: Bool

    public init(enabled: Bool, fireActive: Bool, emergencyActive: Bool, everTriggered: Bool) {
        self.enabled = enabled
        self.fireActive = fireActive
        self.emergencyActive = emergencyActive
        self.everTriggered = everTriggered
    }
}

public struct EmergencyFireActionConfigAck {
    public let stateIndex: EmergencyFireStateIndex
    public let actionType: EmergencyFireActionType

    public init(stateIndex: EmergencyFireStateIndex, actionType: EmergencyFireActionType) {
        self.stateIndex = stateIndex
        self.actionType = actionType
    }
}

public struct EmergencyFireActionConfig: Equatable {
    public let stateIndex: EmergencyFireStateIndex
    public let action: EmergencyFireAction
    public let stage1Target: Address
    public let stage2Target: Address
    public let appKeyIndex: UInt16
    public let ttl: UInt8
    public let transitionTime: UInt8
    public let delay: UInt8

    public init(stateIndex: EmergencyFireStateIndex, action: EmergencyFireAction, stage1Target: Address = 0, stage2Target: Address = 0, appKeyIndex: UInt16 = 0, ttl: UInt8 = 0xFF, transitionTime: UInt8 = 0, delay: UInt8 = 0) {
        self.stateIndex = stateIndex
        self.action = action
        self.stage1Target = stage1Target
        self.stage2Target = stage2Target
        self.appKeyIndex = appKeyIndex
        self.ttl = ttl
        self.transitionTime = transitionTime
        self.delay = delay
    }

    public var data: Data {
        Data([stateIndex.rawValue, action.actionType.rawValue]) +
        stage1Target +
        stage2Target +
        appKeyIndex +
        ttl +
        transitionTime +
        delay +
        action.parameterData
    }
}
```

- [ ] **Step 3: Update `FunctionParameters` cases**

In `SunricherVendorStatus.swift`, replace old cases:

```swift
case emergencySceneConfig(EmergencyControllerSceneConfig)
case emergencyDetailStatus(EmergencyControllerDetailStatus)
case emergencyResendParameters(EmergencyControllerResendParameters)
case emergencyCurrentModeStatus(EmergencyControllerCurrentModeStatus)
case emergencyMode(EmergencyControllerMode)
case emergencyRestoreDelay(seconds: UInt8)
```

with:

```swift
case emergencySceneConfig(EmergencyFireSceneConfig)
case emergencyDetailStatus(EmergencyFireDetailStatus)
case emergencyResendParameters(EmergencyFireResendParameters)
case emergencyComprehensiveStatus(EmergencyFireComprehensiveStatus)
case emergencyEnabled(Bool)
case emergencyRestoreDelay(seconds: UInt8)
case emergencyActionConfigAck(EmergencyFireActionConfigAck)
case emergencyActionConfig(EmergencyFireActionConfig)
```

- [ ] **Step 4: Run tests and verify new type errors remain limited to encoding/decoding**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test --filter EmergencyControllerVendorMessageTests`

Expected:

- Build still fails because `VendorFunctionGet`, `VendorFunctionSet`, and status decoding still reference old cases.
- Errors should no longer complain that `EmergencyFireStateIndex` or `EmergencyFireActionConfig` is missing.

- [ ] **Step 5: Commit the type replacement**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift && git commit -m "Replace emergency fire vendor types with v2 models"`

## Task 3: Update GET and SET Encoding

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift`
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: Update response-code mapping in `FunctionParameters.code`**

In `SunricherVendorStatus.swift`, update the `FunctionParameters.code` emergency cases to:

```swift
case .emergencySceneConfig:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.sceneConfig.rawValue]
case .emergencyDetailStatus:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.detailStatus.rawValue]
case .emergencyResendParameters:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.resendParameters.rawValue]
case .emergencyComprehensiveStatus:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.comprehensiveStatus.rawValue]
case .emergencyEnabled:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.enabled.rawValue]
case .emergencyRestoreDelay:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.restoreDelay.rawValue]
case .emergencyActionConfigAck, .emergencyActionConfig:
    return [VendorOpCode.fireEmergencyScene.rawValue, VendorFireEmergencySceneCode.actionConfig.rawValue]
```

- [ ] **Step 2: Update GET cases and command mapping**

In `SunricherVendorGet.swift`, replace old Emergency Fire `VendorFunctionGet` cases with:

```swift
case emergencySceneConfig(stateIndex: EmergencyFireStateIndex)
case emergencyDetailStatus
case emergencyResendParameters(stateIndex: EmergencyFireStateIndex)
case emergencyComprehensiveStatus
case emergencyEnabled
case emergencyRestoreDelay
case emergencyActionConfig(stateIndex: EmergencyFireStateIndex)
```

Update the `command` switch emergency section to:

```swift
case .emergencySceneConfig: return .emergencySceneConfig
case .emergencyDetailStatus: return .emergencyDetailStatus
case .emergencyResendParameters: return .emergencyResendParameters
case .emergencyComprehensiveStatus: return .emergencyComprehensiveStatus
case .emergencyEnabled: return .emergencyEnabled
case .emergencyRestoreDelay: return .emergencyRestoreDelay
case .emergencyActionConfig: return .emergencyActionConfig
```

- [ ] **Step 3: Update GET payload encoding**

In `VendorFunctionGet.data`, replace the old emergency case with:

```swift
case .emergencySceneConfig(let stateIndex):
    return data + stateIndex.rawValue
case .emergencyResendParameters(let stateIndex):
    return data + stateIndex.rawValue
case .emergencyActionConfig(let stateIndex):
    return data + stateIndex.rawValue
```

Keep other emergency GET cases using the default `return data`.

- [ ] **Step 4: Update SET cases and command mapping**

In `SunricherVendorSet.swift`, replace old Emergency Fire `VendorFunctionSet` cases with:

```swift
case emergencyResendParameters(EmergencyFireResendParameters)
case emergencyEnabled(Bool)
case emergencyRestoreDelay(seconds: UInt8)
case emergencyActionConfig(EmergencyFireActionConfig)
```

Update `command` and `responseCommand` mappings:

```swift
case .emergencyResendParameters: return .emergencyResendParameters
case .emergencyEnabled: return .emergencyEnabled
case .emergencyRestoreDelay: return .emergencyRestoreDelay
case .emergencyActionConfig: return .emergencyActionConfig
```

- [ ] **Step 5: Update SET payload encoding**

In `VendorFunctionSet.data`, replace old emergency cases with:

```swift
case .emergencyResendParameters(let parameters):
    return data + parameters.stateIndex.rawValue + parameters.intervalSeconds + parameters.count
case .emergencyEnabled(let enabled):
    return data + (enabled ? 0x01 : 0x00)
case .emergencyRestoreDelay(let seconds):
    return data + seconds
case .emergencyActionConfig(let config):
    return data + config.data
```

- [ ] **Step 6: Run tests and verify encoding tests pass while parsing may fail**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test --filter EmergencyControllerVendorMessageTests/testEmergencyFireV2GetEncoding`

Expected:

- GET encoding test passes.

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test --filter EmergencyControllerVendorMessageTests/testEmergencyFireV2SetEncoding`

Expected:

- SET encoding test passes.

- [ ] **Step 7: Commit encoding changes**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorSet.swift Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift && git commit -m "Encode emergency fire v2 vendor messages"`

## Task 4: Update STATUS Decoding

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`

- [ ] **Step 1: Add action parsing helper**

In `SunricherVendorStatus.swift`, add this helper near the Emergency Fire model types:

```swift
private enum EmergencyFireActionParser {
    static func parse(actionType: EmergencyFireActionType, data: Data, offset: Int) -> EmergencyFireAction? {
        switch actionType {
        case .onOff:
            guard data.count >= offset + 1 else { return nil }
            return .onOff(data.read(fromOffset: offset))
        case .levelDelta:
            guard data.count >= offset + 4 else { return nil }
            let raw: UInt32 = data.read(fromOffset: offset)
            return .levelDelta(Int32(bitPattern: raw))
        case .levelMove:
            guard data.count >= offset + 2 else { return nil }
            let raw: UInt16 = data.read(fromOffset: offset)
            return .levelMove(Int16(bitPattern: raw))
        case .sceneRecall:
            guard data.count >= offset + 2 else { return nil }
            return .sceneRecall(data.read(fromOffset: offset))
        case .lightControlOnOff:
            guard data.count >= offset + 1 else { return nil }
            return .lightControlOnOff(data.read(fromOffset: offset))
        case .lightness:
            guard data.count >= offset + 2 else { return nil }
            return .lightness(data.read(fromOffset: offset))
        case .ctl:
            guard data.count >= offset + 6 else { return nil }
            let lightness: UInt16 = data.read(fromOffset: offset)
            let temperature: UInt16 = data.read(fromOffset: offset + 2)
            let deltaUVRaw: UInt16 = data.read(fromOffset: offset + 4)
            return .ctl(lightness: lightness, temperature: temperature, deltaUV: Int16(bitPattern: deltaUVRaw))
        case .ctlTemperature:
            guard data.count >= offset + 4 else { return nil }
            let temperature: UInt16 = data.read(fromOffset: offset)
            let deltaUVRaw: UInt16 = data.read(fromOffset: offset + 2)
            return .ctlTemperature(temperature: temperature, deltaUV: Int16(bitPattern: deltaUVRaw))
        case .hsl:
            guard data.count >= offset + 6 else { return nil }
            return .hsl(
                lightness: data.read(fromOffset: offset),
                hue: data.read(fromOffset: offset + 2),
                saturation: data.read(fromOffset: offset + 4)
            )
        case .hslHue:
            guard data.count >= offset + 2 else { return nil }
            return .hslHue(data.read(fromOffset: offset))
        case .hslSaturation:
            guard data.count >= offset + 2 else { return nil }
            return .hslSaturation(data.read(fromOffset: offset))
        case .powerLevel:
            guard data.count >= offset + 2 else { return nil }
            return .powerLevel(data.read(fromOffset: offset))
        case .invalid:
            return .invalid
        }
    }
}
```

- [ ] **Step 2: Update response code mapping from subcode to FunctionParameters**

In the logic that maps `VendorFireEmergencySceneCode` to `FunctionParameters`, replace old cases with:

```swift
case VendorFireEmergencySceneCode.sceneConfig.rawValue:
    self = .emergencySceneConfig
case VendorFireEmergencySceneCode.detailStatus.rawValue:
    self = .emergencyDetailStatus
case VendorFireEmergencySceneCode.resendParameters.rawValue:
    self = .emergencyResendParameters
case VendorFireEmergencySceneCode.comprehensiveStatus.rawValue:
    self = .emergencyComprehensiveStatus
case VendorFireEmergencySceneCode.enabled.rawValue:
    self = .emergencyEnabled
case VendorFireEmergencySceneCode.restoreDelay.rawValue:
    self = .emergencyRestoreDelay
case VendorFireEmergencySceneCode.actionConfig.rawValue:
    self = .emergencyActionConfig
```

- [ ] **Step 3: Update `0x01` scene config decoding**

Replace the old `.emergencySceneConfig` parser with:

```swift
case .emergencySceneConfig:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 8,
          let stateIndex = EmergencyFireStateIndex(rawValue: data.read(fromOffset: 3)) else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    let stage2Target: Address = data.read(fromOffset: 4)
    let sceneNumber: SceneNumber = data.read(fromOffset: 6)
    self.parameters = .emergencySceneConfig(.init(stateIndex: stateIndex, stage2Target: stage2Target, sceneNumber: sceneNumber))
```

- [ ] **Step 4: Update `0x02` detail status decoding**

Replace the old `.emergencyDetailStatus` parser construction with:

```swift
self.parameters = .emergencyDetailStatus(.init(
    fireMillivolts: data.read(fromOffset: 3),
    emergencyMillivolts: data.read(fromOffset: 5),
    fireActive: (data.read(fromOffset: 7) as UInt8) > 0,
    emergencyActive: (data.read(fromOffset: 8) as UInt8) > 0,
    powerLossLevel: data.read(fromOffset: 9),
    powerLossInputActive: (data.read(fromOffset: 10) as UInt8) > 0,
    emergencyAdcActive: (data.read(fromOffset: 11) as UInt8) > 0
))
```

Keep the existing length guard `data.count >= 12`.

- [ ] **Step 5: Update `0x03` resend decoding**

Replace the old `.emergencyResendParameters` parser with:

```swift
case .emergencyResendParameters:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 8,
          let stateIndex = EmergencyFireStateIndex(rawValue: data.read(fromOffset: 3)) else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    self.parameters = .emergencyResendParameters(.init(
        stateIndex: stateIndex,
        intervalSeconds: data.read(fromOffset: 4),
        count: data.read(fromOffset: 6)
    ))
```

- [ ] **Step 6: Update `0x04` comprehensive status decoding**

Replace the old `.emergencyCurrentModeStatus` parser with:

```swift
case .emergencyComprehensiveStatus:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 7 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    self.parameters = .emergencyComprehensiveStatus(.init(
        enabled: (data.read(fromOffset: 3) as UInt8) > 0,
        fireActive: (data.read(fromOffset: 4) as UInt8) > 0,
        emergencyActive: (data.read(fromOffset: 5) as UInt8) > 0,
        everTriggered: (data.read(fromOffset: 6) as UInt8) > 0
    ))
```

- [ ] **Step 7: Update `0x05` enabled decoding**

Replace the old `.emergencyMode` parser with:

```swift
case .emergencyEnabled:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 4 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    let enabled: UInt8 = data.read(fromOffset: 3)
    guard enabled <= 1 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    self.parameters = .emergencyEnabled(enabled > 0)
```

- [ ] **Step 8: Keep and tighten `0x06` restore delay decoding**

Use:

```swift
case .emergencyRestoreDelay:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 4 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    let seconds: UInt8 = data.read(fromOffset: 3)
    guard seconds <= 120 else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    self.parameters = .emergencyRestoreDelay(seconds: seconds)
```

- [ ] **Step 9: Add `0x07` action config decoding**

Add this parser case:

```swift
case .emergencyActionConfig:
    guard isSuccessful else {
        self.parameters = nil
        break
    }
    guard data.count >= 5,
          let stateIndex = EmergencyFireStateIndex(rawValue: data.read(fromOffset: 3)),
          let actionType = EmergencyFireActionType(rawValue: data.read(fromOffset: 4)) else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    if data.count == 5 {
        if actionType == .invalid {
            self.parameters = .emergencyActionConfig(.init(stateIndex: stateIndex, action: .invalid))
        } else {
            self.parameters = .emergencyActionConfigAck(.init(stateIndex: stateIndex, actionType: actionType))
        }
        break
    }
    guard data.count >= 14,
          let action = EmergencyFireActionParser.parse(actionType: actionType, data: data, offset: 14) else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    self.parameters = .emergencyActionConfig(.init(
        stateIndex: stateIndex,
        action: action,
        stage1Target: data.read(fromOffset: 5),
        stage2Target: data.read(fromOffset: 7),
        appKeyIndex: data.read(fromOffset: 9),
        ttl: data.read(fromOffset: 11),
        transitionTime: data.read(fromOffset: 12),
        delay: data.read(fromOffset: 13)
    ))
```

- [ ] **Step 10: Run full Emergency Fire SDK tests**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test --filter EmergencyControllerVendorMessageTests`

Expected:

- All tests in `EmergencyControllerVendorMessageTests` pass.

- [ ] **Step 11: Commit decoding changes**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && git add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift && git commit -m "Decode emergency fire v2 vendor statuses"`

## Task 5: Verify SDK and Capture App Breakage Surface

**Files:**
- No code file edits expected in the App repository during this task.

- [ ] **Step 1: Run targeted SDK test**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test --filter EmergencyControllerVendorMessageTests`

Expected:

- `EmergencyControllerVendorMessageTests` passes.

- [ ] **Step 2: Run broader SDK test suite if targeted tests pass**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk && swift test`

Expected:

- Swift package test suite passes, or unrelated pre-existing failures are captured with exact failing test names and errors.

- [ ] **Step 3: Run App iPhoneOS build to surface old API call sites**

Run from App worktree:

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected:

- Build may fail because App still references old SDK API names.
- Capture the first set of Emergency Fire related errors, especially references to:
  - `EmergencyControllerMode`
  - `EmergencyControllerSceneIndex`
  - `EmergencyControllerResendParameters`
  - `EmergencyControllerCurrentModeStatus`
  - `.emergencyMode`
  - `.emergencyCurrentModeStatus`

- [ ] **Step 4: Summarize App migration surface for the handoff**

In the final implementation summary, include:

- The exact SDK targeted test command and whether it passed.
- The exact SDK full test command and whether it passed.
- The exact App iPhoneOS build command and whether it passed.
- If the App build fails from expected SDK API removal, list the first Emergency Fire related compile errors with file path, old symbol, and v2 replacement concept.

- [ ] **Step 5: Run whitespace check in App worktree**

Run:

`cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/emergency-fire && git diff --check`

Expected:

- No whitespace errors.

## Execution Notes

- Execute tasks in order.
- Do not modify App UI or App EFC sync logic in this plan.
- Treat App compile failures after SDK API removal as expected discovery for the next App-layer plan.
- Keep commits scoped to the SDK repository unless the final evidence section is added to the App worktree documentation.

## Self-Review

- Spec coverage: The plan covers v2 types, GET encoding, SET encoding, STATUS decoding, action config, errors, tests, and verification.
- Scope: The plan is limited to SDK protocol layer and does not include App UI or App sync implementation.
- Type consistency: All new symbols use the `EmergencyFire*` prefix and remove old `EmergencyControllerMode` / `EmergencyControllerSceneIndex` protocol semantics.
