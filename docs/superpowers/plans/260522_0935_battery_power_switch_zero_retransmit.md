# Battery Power Switch Zero Retransmit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change Battery Power Switch v1.0.22 key configuration defaults from application retransmit `1/200ms` to single-send `0/0`, while keeping the 16B wire and `transition=0xFF`.

**Architecture:** The SDK owns the 0x4C key configuration wire encoding and parsing, so the default byte change belongs in `BatteryPowerSwitchKeyConfiguration`. The App owns sync detection, so its desired config hash must change to force already-configured devices to re-sync with the new `0/0/FF` payload. Refresh battery remains unchanged because it uses `GenericBatteryGet`, not 0x4C key configuration retransmit fields.

**Tech Stack:** Swift, iOS, `NordicSigMeshSDK` Swift Package, XCTest, Xcodebuild.

---

## File Structure

- Modify SDK: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`
  - Owns vendor message byte-level tests for 0x4C SET and status parsing.
- Modify SDK: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - Owns `BatteryPowerSwitchKeyConfiguration` default values, 16B parsing, and 16B encoding.
- Modify App: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`
  - Owns Battery Power Switch desired config hash and key configuration generation.

## Task 1: Update SDK Tests For Zero Retransmit

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`

- [ ] **Step 1: Change expected SET bytes to `00 00 FF`**

In `testBatteryPowerSwitchSetEncoding()`, replace the three expected payload tails from:

```swift
0xFF, 0x01, 0x03, 0xFF
```

to:

```swift
0xFF, 0x00, 0x00, 0xFF
```

The full expected payloads should become:

```swift
Data([0x4C, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x34, 0x12, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF])
```

```swift
Data([0x4C, 0x00, 0x04, 0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF])
```

```swift
Data([0x4C, 0x00, 0x01, 0x00, 0x08, 0x00, 0xFF, 0xBF, 0x00, 0x00, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF])
```

- [ ] **Step 2: Change status fixture and assertions to `0/0/FF`**

In `testBatteryPowerSwitchStatusParsing()`, replace the `keyStatus` fixture with:

```swift
let keyStatus = SunricherVendorStatus(parameters: Data([0x4C, 0x00, 0x00, 0x02, 0x00, 0x05, 0x00, 0x00, 0x00, 0x34, 0x12, 0x23, 0xC1, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF]))
```

Change these assertions:

```swift
XCTAssertEqual(config.retransmitCount, 1)
XCTAssertEqual(config.retransmitInterval, 3)
```

to:

```swift
XCTAssertEqual(config.retransmitCount, 0)
XCTAssertEqual(config.retransmitInterval, 0)
```

Keep:

```swift
XCTAssertEqual(config.transition, 0xFF)
```

- [ ] **Step 3: Run the focused SDK test and record the expected failure**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Working directory:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected before implementation:

```text
XCTAssertEqual failed
```

If SwiftPM fails earlier with:

```text
error: no such module 'UIKit'
```

record that as the current SDK test runner limitation and continue with the implementation. This package has iOS-only sources that may not compile under macOS SwiftPM tests.

- [ ] **Step 4: Commit SDK test changes**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "test: expect battery switch zero retransmit"
```

Expected:

```text
[wwd/dev <hash>] test: expect battery switch zero retransmit
```

## Task 2: Change SDK Default Encoding

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/BatteryPowerSwitchVendorMessageTests.swift`

- [ ] **Step 1: Change initializer defaults**

In `BatteryPowerSwitchKeyConfiguration.init(...)`, replace:

```swift
retransmitCount: UInt8 = 1,
retransmitInterval: UInt8 = 3,
transition: UInt8 = 0xFF
```

with:

```swift
retransmitCount: UInt8 = 0,
retransmitInterval: UInt8 = 0,
transition: UInt8 = 0xFF
```

Do not change `data` encoding. It must remain:

```swift
var data: Data {
    Data([button, trigger.rawValue, type.rawValue, value]) + level + sceneId + address + appKeyIndex + Data([ttl, retransmitCount, retransmitInterval, transition])
}
```

Do not change `init?(data:)`. It must continue reading the actual status bytes:

```swift
self.retransmitCount = data.read(fromOffset: 13)
self.retransmitInterval = data.read(fromOffset: 14)
self.transition = data.read(fromOffset: 15)
```

- [ ] **Step 2: Run static SDK checks**

Run:

```bash
rg -n "retransmitCount: UInt8 = 1|retransmitInterval: UInt8 = 3|0xFF, 0x01, 0x03, 0xFF" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests
```

Expected:

```text
no output
```

Run:

```bash
rg -n "retransmitCount: UInt8 = 0|retransmitInterval: UInt8 = 0|0xFF, 0x00, 0x00, 0xFF" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests
```

Expected:

```text
matches in SunricherVendorStatus.swift and BatteryPowerSwitchVendorMessageTests.swift
```

- [ ] **Step 3: Run the focused SDK test**

Run:

```bash
swift test --filter BatteryPowerSwitchVendorMessageTests
```

Working directory:

```text
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
```

Expected if SwiftPM can compile the package:

```text
Test Suite 'BatteryPowerSwitchVendorMessageTests' passed
```

Acceptable known limitation:

```text
error: no such module 'UIKit'
```

If the known limitation appears, continue to App build verification in Task 4 because Xcodebuild compiles the SDK as an iOS package.

- [ ] **Step 4: Commit SDK implementation**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: default battery switch retransmit to zero"
```

Expected:

```text
[wwd/dev <hash>] fix: default battery switch retransmit to zero
```

## Task 3: Update App Desired Config Hash

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

- [ ] **Step 1: Change hash marker**

In `batteryPowerSwitchDesiredConfigHash(appKeyIndex:)`, replace:

```swift
"keyConfigWire=16,retransmit=1/200,transition=FF",
```

with:

```swift
"keyConfigWire=16,retransmit=0/0,transition=FF",
```

This hash change is required so devices that previously applied `1/200` are marked pending and receive the new key configuration on the next sync.

- [ ] **Step 2: Run App static checks**

Run:

```bash
rg -n "keyConfigWire=16,retransmit=1/200|retransmit=1/200" SunSmart
```

Expected:

```text
no output
```

Run:

```bash
rg -n "keyConfigWire=16,retransmit=0/0,transition=FF" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
```

Expected:

```text
one match in batteryPowerSwitchDesiredConfigHash(appKeyIndex:)
```

- [ ] **Step 3: Commit App hash change**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift
git commit -m "fix: resync battery switch zero retransmit"
```

Expected:

```text
[wwd/feat/k8-switch <hash>] fix: resync battery switch zero retransmit
```

## Task 4: Verify App Build And Workspace State

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify SDK local dependency: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

- [ ] **Step 1: Build SunSmart for iPhoneOS**

Run directly, without shell wrapping and without output redirection:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

The output should show the local SDK path:

```text
NordicSigMeshSDK: /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk @ local
```

- [ ] **Step 2: Final static verification**

Run:

```bash
rg -n "retransmitCount: UInt8 = 1|retransmitInterval: UInt8 = 3|0xFF, 0x01, 0x03, 0xFF" /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests SunSmart
```

Expected:

```text
no output
```

Run:

```bash
rg -n "GenericBatteryGet\\(|PJEightKeySwitchBatteryRefreshFlow|MeshBatteryPowerSwitchBatteryReader" SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchRefreshAlertController.swift
```

Expected:

```text
matches showing refresh battery still uses GenericBatteryGet
```

- [ ] **Step 3: Confirm both repositories are clean**

Run:

```bash
git status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected:

```text
no output from both commands
```

## Self-Review

- Spec coverage: Task 1 and Task 2 cover SDK 16B default encoding and parsing assertions. Task 3 covers App hash migration from `1/200` to `0/0`. Task 4 covers build verification and confirms refresh battery remains on `GenericBatteryGet`.
- Placeholder scan: Plan contains no placeholder work items; each change step includes exact strings, files, commands, and expected results.
- Type consistency: The plan consistently uses SDK properties `retransmitCount`, `retransmitInterval`, and `transition`; protocol terms remain `retransmit_count`, `retransmit_interval`, and `transition`; App hash uses `keyConfigWire=16,retransmit=0/0,transition=FF`.
