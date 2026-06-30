# EFC Comprehensive Status Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make EFC device page status rendering respect the `0x4D/0x04 enable_mode` bitmap returned by the device.

**Architecture:** Preserve the real `enable_mode` in `NordicSigMeshSDK` instead of collapsing it to a Bool. Keep App rendering logic centralized in `EmerFireAlarmMonitorStateMapper.displayState(status:)`, where invalid modes and disabled mode silently map to Normal State.

**Tech Stack:** Swift, NordicSigMeshSDK vendor message parser, SunSmart UIKit view model, Bash contract scripts, XCTest for SDK parser coverage, iPhoneOS `xcodebuild` verification.

---

## File Structure

- Modify SDK parser/model: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
  - Responsibility: parse `0x4D/0x04`, expose `enableMode`, optional `workingMode`, active flags, and debug flags.
- Modify SDK tests: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`
  - Responsibility: lock the new 8-byte response shape, valid mode parsing, and invalid mode parsing.
- Modify App mapper: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
  - Responsibility: convert SDK comprehensive status into EFC monitor display states.
- Create App contract script: `scripts/check_efc_comprehensive_status_mapping.sh`
  - Responsibility: guard the mode-aware mapper shape in a repo without an App XCTest target.

Before touching SDK files, run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
```

Expected current unrelated dirty files may include:

```text
 M Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
 M Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
```

Do not stage or modify those files for this task.

---

### Task 1: Add SDK Parser Tests

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

- [ ] **Step 1: Update the existing comprehensive status assertion**

Inside `testEmergencyFireV2StatusParsing()`, replace the existing `let comprehensiveStatus = ...` block with:

```swift
        let comprehensiveStatus = SunricherVendorStatus(parameters: Data([0x4D, 0x04, 0x00, 0x03, 0x01, 0x00, 0x01, 0x00]))
        XCTAssertEqual(comprehensiveStatus?.status.isSuccessful, true)
        if case .emergencyComprehensiveStatus(let status) = comprehensiveStatus?.status.parameters {
            XCTAssertEqual(status.enableMode, 0x03)
            XCTAssertEqual(status.workingMode, .powerLossAndFireAlarm)
            XCTAssertEqual(status.enabled, true)
            XCTAssertEqual(status.fireActive, true)
            XCTAssertEqual(status.emergencyActive, false)
            XCTAssertEqual(status.everEmergency, true)
            XCTAssertEqual(status.everFire, false)
            XCTAssertEqual(status.everTriggered, true)
        } else {
            XCTFail("Expected emergency comprehensive status")
        }
```

- [ ] **Step 2: Add mode matrix coverage**

Insert this test method before `func testSceneRecallDebugLogFormatsEFCUnacknowledgedScene()`:

```swift
    func testEmergencyFireComprehensiveStatusParsesEnableModeBitmap() {
        struct Case {
            let payload: Data
            let expectedEnableMode: UInt8
            let expectedWorkingMode: EmergencyFireWorkingMode?
            let expectedEnabled: Bool
            let expectedFireActive: Bool
            let expectedEmergencyActive: Bool
            let expectedEverEmergency: Bool
            let expectedEverFire: Bool
            let expectedEverTriggered: Bool
        }

        let cases: [Case] = [
            .init(
                payload: Data([0x4D, 0x04, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00]),
                expectedEnableMode: 0x00,
                expectedWorkingMode: .disabled,
                expectedEnabled: false,
                expectedFireActive: true,
                expectedEmergencyActive: true,
                expectedEverEmergency: false,
                expectedEverFire: false,
                expectedEverTriggered: false
            ),
            .init(
                payload: Data([0x4D, 0x04, 0x00, 0x01, 0x01, 0x01, 0x01, 0x00]),
                expectedEnableMode: 0x01,
                expectedWorkingMode: .powerLossOnly,
                expectedEnabled: true,
                expectedFireActive: true,
                expectedEmergencyActive: true,
                expectedEverEmergency: true,
                expectedEverFire: false,
                expectedEverTriggered: true
            ),
            .init(
                payload: Data([0x4D, 0x04, 0x00, 0x02, 0x01, 0x00, 0x00, 0x01]),
                expectedEnableMode: 0x02,
                expectedWorkingMode: .fireAlarmOnly,
                expectedEnabled: true,
                expectedFireActive: true,
                expectedEmergencyActive: false,
                expectedEverEmergency: false,
                expectedEverFire: true,
                expectedEverTriggered: true
            ),
            .init(
                payload: Data([0x4D, 0x04, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01]),
                expectedEnableMode: 0x03,
                expectedWorkingMode: .powerLossAndFireAlarm,
                expectedEnabled: true,
                expectedFireActive: true,
                expectedEmergencyActive: true,
                expectedEverEmergency: true,
                expectedEverFire: true,
                expectedEverTriggered: true
            ),
            .init(
                payload: Data([0x4D, 0x04, 0x00, 0x09, 0x01, 0x01, 0x00, 0x00]),
                expectedEnableMode: 0x09,
                expectedWorkingMode: nil,
                expectedEnabled: false,
                expectedFireActive: true,
                expectedEmergencyActive: true,
                expectedEverEmergency: false,
                expectedEverFire: false,
                expectedEverTriggered: false
            )
        ]

        cases.forEach { item in
            let status = SunricherVendorStatus(parameters: item.payload)
            XCTAssertEqual(status?.status.isSuccessful, true)
            if case .emergencyComprehensiveStatus(let detail) = status?.status.parameters {
                XCTAssertEqual(detail.enableMode, item.expectedEnableMode)
                XCTAssertEqual(detail.workingMode, item.expectedWorkingMode)
                XCTAssertEqual(detail.enabled, item.expectedEnabled)
                XCTAssertEqual(detail.fireActive, item.expectedFireActive)
                XCTAssertEqual(detail.emergencyActive, item.expectedEmergencyActive)
                XCTAssertEqual(detail.everEmergency, item.expectedEverEmergency)
                XCTAssertEqual(detail.everFire, item.expectedEverFire)
                XCTAssertEqual(detail.everTriggered, item.expectedEverTriggered)
            } else {
                XCTFail("Expected emergency comprehensive status for payload \(item.payload as NSData)")
            }
        }
    }
```

- [ ] **Step 3: Run the focused SDK test and confirm it fails for the right reason**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests.testEmergencyFireComprehensiveStatusParsesEnableModeBitmap
```

Expected: failure because `EmergencyFireComprehensiveStatus` does not yet expose `enableMode`, `workingMode`, `everEmergency`, or `everFire`.

If `swift test` fails earlier with an unrelated UIKit/module error, keep the failure text for the final notes and continue to Task 2. Do not change SDK package structure for this task.

---

### Task 2: Implement SDK `enable_mode` Parsing

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift`

- [ ] **Step 1: Replace `EmergencyFireComprehensiveStatus`**

Replace the current struct with:

```swift
public struct EmergencyFireComprehensiveStatus {
    public let enableMode: UInt8
    public let fireActive: Bool
    public let emergencyActive: Bool
    public let everEmergency: Bool
    public let everFire: Bool

    public var workingMode: EmergencyFireWorkingMode? {
        EmergencyFireWorkingMode(rawValue: enableMode)
    }

    public var enabled: Bool {
        guard let workingMode else { return false }
        return workingMode != .disabled
    }

    public var everTriggered: Bool {
        everEmergency || everFire
    }

    public init(
        enableMode: UInt8,
        fireActive: Bool,
        emergencyActive: Bool,
        everEmergency: Bool,
        everFire: Bool
    ) {
        self.enableMode = enableMode
        self.fireActive = fireActive
        self.emergencyActive = emergencyActive
        self.everEmergency = everEmergency
        self.everFire = everFire
    }

    public init(
        workingMode: EmergencyFireWorkingMode,
        fireActive: Bool,
        emergencyActive: Bool,
        everEmergency: Bool,
        everFire: Bool
    ) {
        self.init(
            enableMode: workingMode.rawValue,
            fireActive: fireActive,
            emergencyActive: emergencyActive,
            everEmergency: everEmergency,
            everFire: everFire
        )
    }

    public init(enabled: Bool, fireActive: Bool, emergencyActive: Bool, everTriggered: Bool) {
        self.init(
            workingMode: enabled ? .powerLossAndFireAlarm : .disabled,
            fireActive: fireActive,
            emergencyActive: emergencyActive,
            everEmergency: everTriggered,
            everFire: everTriggered
        )
    }
}
```

- [ ] **Step 2: Update `0x4D/0x04` parser offsets**

In the `.emergencyComprehensiveStatus` case, replace the current `guard data.count >= 7` block and initializer with:

```swift
                    guard data.count >= 8 else {
                        self.isSuccessful = false
                        self.parameters = nil
                        break
                    }
                    self.parameters = .emergencyComprehensiveStatus(.init(
                        enableMode: data.read(fromOffset: 3),
                        fireActive: (data.read(fromOffset: 4) as UInt8) > 0,
                        emergencyActive: (data.read(fromOffset: 5) as UInt8) > 0,
                        everEmergency: (data.read(fromOffset: 6) as UInt8) > 0,
                        everFire: (data.read(fromOffset: 7) as UInt8) > 0
                    ))
```

- [ ] **Step 3: Run focused SDK tests**

Run:

```bash
swift test --filter EmergencyFireVendorMessageTests
```

Expected: all `EmergencyFireVendorMessageTests` pass, unless the local SDK package still has an unrelated UIKit/module test environment failure.

- [ ] **Step 4: Run SDK iPhoneOS build**

Run:

```bash
xcodebuild -project /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/NordicSigMeshDemo/NordicSigMeshDemo.xcodeproj -scheme NordicSigMeshSDK -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Commit SDK parser changes only**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk status --short
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift Tests/NordicSigMeshSDKTests/EmergencyFireVendorMessageTests.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "fix: parse EFC comprehensive status mode"
```

Expected: only the two EFC SDK files are committed. Existing unrelated SDK dirty files remain unstaged.

---

### Task 3: Add App Mapper Contract

**Files:**
- Create: `scripts/check_efc_comprehensive_status_mapping.sh`

- [ ] **Step 1: Create the contract script**

Create `scripts/check_efc_comprehensive_status_mapping.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    echo "  expected pattern: $pattern" >&2
    echo "  in file: $file" >&2
    exit 1
  fi
}

assert_contains "$STATE_FILE" "switch status.workingMode" \
  "EFC comprehensive status mapping must branch on device-returned enable_mode."

assert_contains "$STATE_FILE" "case .some(.disabled), .none:" \
  "Disabled and invalid EFC enable_mode must silently display Normal State."

assert_contains "$STATE_FILE" "case .some(.powerLossOnly):" \
  "Power Loss Only mode must have an explicit mapper branch."

assert_contains "$STATE_FILE" "return status.emergencyActive ? .emergencyTriggered : normalState()" \
  "Power Loss Only mode must only respond to em_active."

assert_contains "$STATE_FILE" "case .some(.fireAlarmOnly):" \
  "Fire Alarm Only mode must have an explicit mapper branch."

assert_contains "$STATE_FILE" "return status.fireActive ? .fireTriggered : normalState()" \
  "Fire Alarm Only mode must only respond to fire_active."

assert_contains "$STATE_FILE" "case .some(.powerLossAndFireAlarm):" \
  "Combined mode must have an explicit mapper branch."

assert_contains "$STATE_FILE" "if status.fireActive {" \
  "Combined mode must keep Fire Alarm priority."

assert_contains "$STATE_FILE" "if status.emergencyActive {" \
  "Combined mode must fall back to Power Loss when fire_active is false."

echo "EFC comprehensive status mapping contracts passed."
```

- [ ] **Step 2: Run the script and confirm it fails**

Run:

```bash
bash scripts/check_efc_comprehensive_status_mapping.sh
```

Expected: `FAIL: EFC comprehensive status mapping must branch on device-returned enable_mode.`

---

### Task 4: Implement App Mode-Aware Mapping

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
- Test: `scripts/check_efc_comprehensive_status_mapping.sh`

- [ ] **Step 1: Replace `displayState(status:)`**

Replace the current method body with:

```swift
    static func displayState(status: EmergencyFireComprehensiveStatus) -> EmerFireAlarmMonitorDisplayState {
        switch status.workingMode {
        case .some(.disabled), .none:
            return normalState()
        case .some(.powerLossOnly):
            return status.emergencyActive ? .emergencyTriggered : normalState()
        case .some(.fireAlarmOnly):
            return status.fireActive ? .fireTriggered : normalState()
        case .some(.powerLossAndFireAlarm):
            if status.fireActive {
                return .fireTriggered
            }
            if status.emergencyActive {
                return .emergencyTriggered
            }
            return normalState()
        }
    }
```

- [ ] **Step 2: Run the App contract script**

Run:

```bash
bash scripts/check_efc_comprehensive_status_mapping.sh
```

Expected:

```text
EFC comprehensive status mapping contracts passed.
```

- [ ] **Step 3: Run existing EFC contract scripts**

Run:

```bash
bash scripts/check_efc_controller_flows.sh
bash scripts/check_efc_status_content_list.sh
bash scripts/check_efc_i18n.sh
```

Expected:

```text
EFC status content list contracts passed.
PASS: no targeted EFC hardcoded strings found.
```

`check_efc_controller_flows.sh` is long and prints only on failure; a zero exit code is the pass signal.

---

### Task 5: Final Verification and App Commit

**Files:**
- Modify: `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
- Create: `scripts/check_efc_comprehensive_status_mapping.sh`
- Existing plan: `docs/260630_2018_efc_comprehensive_status_mode_plan.md`

- [ ] **Step 1: Run whitespace check**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 2: Run SunSmart iPhoneOS build**

Run:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 3: Confirm App repo diff scope**

Run:

```bash
git status --short
git diff --stat
```

Expected App repo changed files:

```text
 M SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift
?? scripts/check_efc_comprehensive_status_mapping.sh
```

The plan document may already be committed before implementation starts.

- [ ] **Step 4: Commit App mapper changes**

Run:

```bash
git add SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift scripts/check_efc_comprehensive_status_mapping.sh
git commit -m "fix: map EFC status by enable mode"
```

Expected: App mapper and contract script are committed without unrelated files.

---

## Self-Review

- Spec coverage: SDK preserves `enable_mode`; App maps by mode; invalid mode displays Normal; `ever_em` and `ever_fire` are parsed but not used by UI; scope excludes edit/sync/delete/mock flows.
- Placeholder scan: no task uses TBD, TODO, or deferred implementation language.
- Type consistency: plan uses `enableMode`, `workingMode`, `everEmergency`, `everFire`, `fireActive`, and `emergencyActive` consistently across SDK parser, SDK tests, and App mapper.
