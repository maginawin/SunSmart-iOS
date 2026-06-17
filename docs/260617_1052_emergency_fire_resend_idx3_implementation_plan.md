# Emergency Fire Resend idx3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Project preference is Inline Execution.

**Goal:** 让 SDK 完整支持 Emergency Fire `0x4D/0x03 state_idx=3`，并让 App 触发事件重发参数只下发一条 `idx=3` SET，restore resend 继续使用 `idx=2`。

**Architecture:** SDK 负责协议表达和 status 解析，App 只表达业务意图。SDK 扩展 `EmergencyFireStateIndex` 和 resend ACK 模型，保留 `idx=0/1/2`，新增 `idx=3` 的 SET/GET/STATUS 测试；App sync 层新增 trigger resend helper，将原先 `emergencyTrigger + fireTrigger` 两条 resend task 合并为一条 `Trigger Resend` task。

**Tech Stack:** Swift, UIKit, NordicSigMeshSDK vendor messages, XCTest, SunSmart iOS App, Xcode iPhoneOS build.

---

## File Structure

- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`
  - 负责 SDK vendor message 编码/解析回归测试。
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - 负责 `EmergencyFireStateIndex`、`EmergencyFireResendParametersAck`、`FunctionParameters` 和 `0x4D/0x03` status parser。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
  - 负责 App 本地 EFC 配置到 SDK resend 参数的转换 helper。
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
  - 负责 App EFC 同步任务生成，将 trigger resend 合并为 `idx=3`。
- Optional Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - 仅当 sync task title/detail 展示依赖旧 `Emergency/Fire Resend` 语义时调整展示文案；先检查，非必要不改。

## Task 1: SDK idx=3 失败测试

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

- [ ] **Step 1: Add failing GET encoding assertion**

In `testEmergencyFireV2GetEncoding()`, after the existing restore resend GET assertion:

```swift
XCTAssertEqual(
    SunricherVendorGet(function: .emergencyResendParameters(stateIndex: .emergencyAndFireSync)).parameters,
    Data([0x4D, 0x03, 0x03])
)
```

- [ ] **Step 2: Add failing SET encoding assertion**

In `testEmergencyFireV2SetEncoding()`, after the existing restore resend SET assertion:

```swift
XCTAssertEqual(
    SunricherVendorSet(function: .emergencyResendParameters(.init(stateIndex: .emergencyAndFireSync, intervalSeconds: 5, count: 0xFFFF))).parameters,
    Data([0x4D, 0x03, 0x03, 0x05, 0x00, 0xFF, 0xFF])
)
```

- [ ] **Step 3: Add failing successful status parsing assertions**

In `testEmergencyFireV2StatusParsing()`, after the existing `resendStatus` GET STATUS assertion:

```swift
let syncedResendStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x03, 0x05, 0x00, 0xFF, 0xFF]))
XCTAssertEqual(syncedResendStatus?.status.isSuccessful, true)
if case .emergencyResendParameters(let parameters) = syncedResendStatus?.status.parameters {
    XCTAssertEqual(parameters.stateIndex, .emergencyAndFireSync)
    XCTAssertEqual(parameters.intervalSeconds, 5)
    XCTAssertEqual(parameters.count, 0xFFFF)
} else {
    XCTFail("Expected emergency/fire synced resend parameters")
}
```

In the `resendSetAcks` list, add the `idx=3` ACK:

```swift
let resendSetAcks: [(Data, EmergencyFireStateIndex)] = [
    (Data([0x4D, 0x03, 0x00, 0x00]), .emergencyTrigger),
    (Data([0x4D, 0x03, 0x00, 0x01]), .fireTrigger),
    (Data([0x4D, 0x03, 0x00, 0x02]), .restore),
    (Data([0x4D, 0x03, 0x00, 0x03]), .emergencyAndFireSync)
]
```

- [ ] **Step 4: Add failing ret=5 inconsistency assertion**

In `testEmergencyFireV2StatusErrorsAndInvalidPayloads()`, replace the current `invalidStateIndex` expectation for `idx=3` with a true invalid index, then add `ret=5` coverage:

```swift
let invalidStateIndex = SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x00, 0x04, 0x05, 0x00, 0x0A, 0x00]))
XCTAssertEqual(invalidStateIndex?.status.isSuccessful, false)
XCTAssertNil(invalidStateIndex?.status.parameters)

let inconsistentSyncedResend = SunricherVendorStatus(parameters: Data([0x4D, 0x03, 0x05, 0x03]))
XCTAssertEqual(inconsistentSyncedResend?.status.isSuccessful, false)
XCTAssertEqual(inconsistentSyncedResend?.status.errorCode, 0x05)
if case .emergencyResendParametersAck(let ack) = inconsistentSyncedResend?.status.parameters {
    XCTAssertEqual(ack.stateIndex, .emergencyAndFireSync)
    XCTAssertEqual(ack.responseCode, 0x05)
} else {
    XCTFail("Expected emergency/fire synced resend inconsistency ack")
}
```

- [ ] **Step 5: Run SDK test command and verify it fails for missing SDK support**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests
```

Expected:

- It may fail early with `no such module 'UIKit'` in this local SDK package. If so, record that SwiftPM cannot verify this UIKit-coupled package and continue to the SDK iPhoneOS build in later tasks.
- If SwiftPM reaches compilation, expected failure is missing `.emergencyAndFireSync` or missing `responseCode` on `EmergencyFireResendParametersAck`.

- [ ] **Step 6: Commit failing SDK tests if they compile far enough**

Only commit if the test file is syntactically valid in Xcode build context. If SwiftPM stops at UIKit before compiling tests, defer the commit until Task 2 verifies with Xcode.

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "test: cover emergency fire resend sync index"
```

## Task 2: SDK idx=3 implementation

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

- [ ] **Step 1: Add SDK state index case**

In `EmergencyFireStateIndex`, add `emergencyAndFireSync = 3`:

```swift
public enum EmergencyFireStateIndex: UInt8, Equatable {
    case emergencyTrigger = 0
    case fireTrigger = 1
    case restore = 2
    case emergencyAndFireSync = 3
}
```

- [ ] **Step 2: Extend resend ACK model with response code**

Replace `EmergencyFireResendParametersAck` with:

```swift
public struct EmergencyFireResendParametersAck {
    public let stateIndex: EmergencyFireStateIndex
    public let responseCode: UInt8

    public init(stateIndex: EmergencyFireStateIndex, responseCode: UInt8 = 0) {
        self.stateIndex = stateIndex
        self.responseCode = responseCode
    }
}
```

This preserves existing callers that only pass `stateIndex`.

- [ ] **Step 3: Update resend parser to preserve failed idx=3 ACK information**

In the `.emergencyResendParameters` case inside `SunricherVendorStatus.Status.init?(data:)`, replace the current block with:

```swift
case .emergencyResendParameters:
    guard let stateIndex = EmergencyFireStateIndex(rawValue: data.read(fromOffset: 3)) else {
        self.isSuccessful = false
        self.parameters = nil
        break
    }
    guard data.count >= 8 else {
        if data.count == 4 {
            self.parameters = .emergencyResendParametersAck(.init(stateIndex: stateIndex, responseCode: status))
        } else {
            self.isSuccessful = false
            self.parameters = nil
        }
        break
    }
    guard isSuccessful else {
        self.parameters = .emergencyResendParametersAck(.init(stateIndex: stateIndex, responseCode: status))
        break
    }
    self.parameters = .emergencyResendParameters(.init(
        stateIndex: stateIndex,
        intervalSeconds: data.read(fromOffset: 4),
        count: data.read(fromOffset: 6)
    ))
```

This keeps normal GET STATUS as `EmergencyFireResendParameters`, and maps failed `ret=5 idx=3` to an ACK-like status carrying `responseCode=5`.

- [ ] **Step 4: Verify existing ACK tests still pass**

Check existing assertions that read:

```swift
XCTAssertEqual(ack.stateIndex, expectedStateIndex)
```

No change is required because `responseCode` has a default value and existing tests do not need to assert it for `ret=0`.

- [ ] **Step 5: Build SDK on iPhoneOS**

Run:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit SDK implementation**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: support emergency fire resend sync index"
```

Expected: commit includes only the SDK status/model/test changes for `idx=3`.

## Task 3: App resend helper

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`

- [ ] **Step 1: Add trigger sync resend helper**

In `EmergencyFireControllerConfiguration`, after `resendParameters(for:)`, add:

```swift
func triggerResendParameters() -> EmergencyFireResendParameters {
    .init(
        stateIndex: .emergencyAndFireSync,
        intervalSeconds: powerLossSettings.triggerIntervalSeconds,
        count: powerLossSettings.triggerCount
    )
}
```

This uses the App's single trigger resend business value. The edit state already writes the same value to power loss and fire alarm settings.

- [ ] **Step 2: Add changed-only helper**

In the same extension, add:

```swift
func triggerResendParametersEqual(to other: EmergencyFireControllerConfiguration?) -> Bool {
    guard let other else {
        return false
    }
    let lhs = triggerResendParameters()
    let rhs = other.triggerResendParameters()
    return lhs.stateIndex == rhs.stateIndex &&
        lhs.intervalSeconds == rhs.intervalSeconds &&
        lhs.count == rhs.count
}
```

- [ ] **Step 3: Keep restore helper unchanged**

Do not change existing `resendParameters(for: .restore)` behavior:

```swift
return .init(
    stateIndex: state.sdkStateIndex,
    intervalSeconds: 5,
    count: restoreSettings.sendCount
)
```

- [ ] **Step 4: Build-check App compile after helper addition**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

- Build may fail before Task 4 because sync code still references old generation logic, but helper should not introduce type errors once SDK local package is updated.
- If build fails due package resolution or unrelated target settings, record exact error before continuing.

## Task 4: App sync task generation

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- Optional Modify: `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`

- [ ] **Step 1: Replace resend task loop with trigger + restore resend tasks**

In `makeControllerSyncTasks(...)`, replace the resend part inside `EmergencyFireControllerState.allCases.forEach` with a separate trigger resend block before the action-config loop:

```swift
let triggerResend = configuration.triggerResendParameters()
if oldConfiguration == nil || !configuration.triggerResendParametersEqual(to: oldConfiguration) {
    tasks.append(EmergencyFireControllerSyncTask(
        title: "Trigger Resend",
        kind: .resend,
        address: node.primaryUnicastAddress,
        messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyResendParameters(triggerResend)), model: vendorModel)],
        changedOnly: onlyChangedKeyParameters
    ))
}

let restoreResend = configuration.resendParameters(for: .restore)
let oldRestoreResend = oldConfiguration?.resendParameters(for: .restore)
if oldConfiguration == nil || !resendParametersEqual(oldRestoreResend, restoreResend) {
    tasks.append(EmergencyFireControllerSyncTask(
        title: "Restore Resend",
        kind: .resend,
        address: node.primaryUnicastAddress,
        messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyResendParameters(restoreResend)), model: vendorModel)],
        changedOnly: onlyChangedKeyParameters
    ))
}
```

- [ ] **Step 2: Keep action config loop over all states**

After the new resend blocks, keep an `EmergencyFireControllerState.allCases.forEach` loop for action configs only:

```swift
EmergencyFireControllerState.allCases.forEach { state in
    let actionConfig = configuration.actionConfig(
        for: state,
        targetAddress: publishGroupAddress,
        appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index,
        ttl: MeshNetworkManager.instance.networkParameters.defaultTtl
    )
    let oldActionConfig = oldConfiguration?.actionConfig(
        for: state,
        targetAddress: publishGroupAddress,
        appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index,
        ttl: MeshNetworkManager.instance.networkParameters.defaultTtl
    )
    if oldConfiguration == nil || oldActionConfig != actionConfig {
        tasks.append(EmergencyFireControllerSyncTask(
            title: "\(state.taskTitle) Action",
            kind: .actionConfig,
            address: node.primaryUnicastAddress,
            messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyActionConfig(actionConfig)), model: vendorModel)],
            changedOnly: onlyChangedKeyParameters
        ))
    }
}
```

- [ ] **Step 3: Confirm restore delay block remains after action config loop**

The existing restore delay block should remain unchanged:

```swift
if oldConfiguration == nil || oldConfiguration?.restoreDelaySeconds() != configuration.restoreDelaySeconds() {
    tasks.append(EmergencyFireControllerSyncTask(
        title: "Restore Delay",
        kind: .restoreDelay,
        address: node.primaryUnicastAddress,
        messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyRestoreDelay(seconds: configuration.restoreDelaySeconds())), model: vendorModel)],
        changedOnly: onlyChangedKeyParameters
    ))
}
```

- [ ] **Step 4: Check sync display code for assumptions**

Run:

```bash
rg -n "Emergency Resend|Fire Resend|Trigger Resend|\\.resend|kind: \\.resend" SunSmart/Main/Device SunSmart/Main/Space
```

Expected:

- `DeviceEmerFireData+Sync.swift` should show `Trigger Resend` and `Restore Resend`.
- If `SyncDevicesViewController.swift` only uses `.resend` generically, leave it unchanged.
- If it hardcodes `Emergency Resend` or `Fire Resend`, update the display to accept `Trigger Resend`.

- [ ] **Step 5: Commit App implementation**

Run:

```bash
git status --short
git add SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift
git commit -m "feat: sync emergency fire resend with idx3"
```

If `SyncDevicesViewController.swift` was modified in Step 4, include it in `git add`.

## Task 5: Full verification

**Files:**
- Verify only unless build failures require scoped fixes.

- [ ] **Step 1: Search for old trigger resend generation**

Run:

```bash
rg -n "Emergency Resend|Fire Resend|resendParameters\\(for: state\\)|EmergencyFireControllerState\\.allCases\\.forEach" SunSmart/Main/Device/Device1.5/FireAlarm
```

Expected:

- No resend SET generation remains inside a loop over all three states.
- `EmergencyFireControllerState.allCases` may still exist for action config generation.

- [ ] **Step 2: Search SDK idx=3 coverage**

Run:

```bash
rg -n "emergencyAndFireSync|responseCode|0x03, 0x03|0x05, 0x03" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests
```

Expected:

- `emergencyAndFireSync` appears in SDK source and tests.
- `responseCode` appears on `EmergencyFireResendParametersAck` and the ret=5 test.

- [ ] **Step 3: Build SDK**

Run:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Build App**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Check whitespace and repo state**

Run:

```bash
git diff --check
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected:

- `git diff --check` has no output.
- App repo only has intended changes, or is clean after commits.
- SDK repo only has intended changes, or is clean after commits.

- [ ] **Step 6: Final summary**

Report:

- SDK now supports `idx=3` SET/GET/STATUS parsing.
- SDK ret=5 inconsistency is represented as unsuccessful resend ACK/status with `stateIndex = .emergencyAndFireSync`.
- App trigger resend now sends one `idx=3` task.
- App restore resend remains `idx=2, N=5, M=sendCount`.
- Exact build commands run and their result.

## Self-Review

- Spec coverage: SDK SET/GET/SET STATUS/GET STATUS `idx=3`, ret=5 parsing, App trigger merge, restore unchanged, SDK idx=0/1 retained, build verification are each covered by tasks.
- Placeholder scan: no placeholder markers remain.
- Type consistency: plan uses `.emergencyAndFireSync` consistently across SDK tests, SDK enum, App helper, and sync generation.
