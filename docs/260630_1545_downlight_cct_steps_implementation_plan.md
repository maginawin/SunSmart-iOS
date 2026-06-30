# Downlight CCT Steps Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in this session. Steps use checkbox (`- [ ]`) syntax for tracking. Per repo preference, do not use subagent-driven execution unless the user explicitly requests it.

**Goal:** Add `upDownLightDefaultCctSteps` support for Downlight `CID 0x0A78 / PID 0x2492` without enabling up/down ratio controls.

**Architecture:** Keep up/down ratio and CCT-steps capability as separate concepts. SDK owns persisted `upDownLightDefaultCctSteps` and CCT range derivation; App owns post-provisioning reader selection and must select both `0x2491` and `0x2492` for CCT steps reads.

**Tech Stack:** Swift, UIKit app target, local Swift Package `NordicSigMeshSDK`, XCTest specifications, iPhoneOS `xcodebuild` verification.

---

## File Structure

- Modify SDK test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
  - Add Downlight-specific CCT default tests beside the existing Up/Down Light tests.
- Modify SDK implementation: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
  - Extend `isUpDownLightDefaultCctStepsProduct` from only `0x2491` to `0x2491` and `0x2492`.
- Modify App capability: `SunSmart/Common/Data/Node+Capability.swift`
  - Add a dedicated `supportsUpDownLightDefaultCctSteps` computed property.
  - Keep `supportsUpDownRatioControl` unchanged.
- Modify App reader: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
  - Filter nodes with `supportsUpDownLightDefaultCctSteps`.

Do not modify:

- `SunSmart/devices_config.json`
- Up/down ratio UI files
- Group up/down ratio control
- Vendor group subscription code

---

### Task 1: Add Failing SDK Tests for Downlight CCT Steps

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`

- [ ] **Step 1: Add Downlight tests after `testUpDownLightDefaultCctStepsStatusUpdatesNodeCachedSteps()`**

Insert this block before `private func makeNode(productIdentifier: UInt16) -> Node`:

```swift
    func testDownlightKeepsTunableWhiteDefaultAndUsesFiveStepCctRangeByDefault() {
        let node = makeNode(productIdentifier: 0x2492)

        XCTAssertFalse(node.isSingleWhiteDefaultCctProduct)
        XCTAssertTrue(node.isUpDownLightDefaultCctStepsProduct)
        XCTAssertEqual(node.defaultChangeControlPage, .tunableWhite)
        XCTAssertEqual(node.effectiveChangeControlPage, .tunableWhite)
        XCTAssertEqual(node.upDownLightDefaultCctSteps, 5)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
    }

    func testDownlightSixDefaultCctStepsUsesStandardCctRange() {
        let node = makeNode(productIdentifier: 0x2492)
        node.upDownLightDefaultCctSteps = 6

        XCTAssertTrue(node.isUpDownLightDefaultCctStepsProduct)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.standardDefaultRange)
    }

    func testDownlightInvalidDefaultCctStepsFallsBackToFiveStepRange() {
        let node = makeNode(productIdentifier: 0x2492)
        node.upDownLightDefaultCctSteps = 7

        XCTAssertTrue(node.isUpDownLightDefaultCctStepsProduct)
        XCTAssertEqual(node.upDownLightDefaultCctSteps, 5)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
    }

    func testDownlightConfiguredAbsoluteCctRangeOverridesDefaultSteps() {
        let node = makeNode(productIdentifier: 0x2492)
        node.upDownLightDefaultCctSteps = 6
        node.absoluteCctRange = 3000...4500

        XCTAssertTrue(node.isUpDownLightDefaultCctStepsProduct)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, 3000...4500)
    }

    func testDownlightSixDefaultCctStepsIgnoresLegacyFiveStepAbsoluteRange() {
        let node = makeNode(productIdentifier: 0x2492)
        node.absoluteCctRange = NodeAbsoluteCctRange.singleWhiteDefaultRange
        node.upDownLightDefaultCctSteps = 6

        XCTAssertTrue(node.isUpDownLightDefaultCctStepsProduct)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.standardDefaultRange)
    }

    func testDownlightDefaultCctStepsStatusUpdatesNodeCachedSteps() {
        let node = makeNode(productIdentifier: 0x2492)
        let status = SunricherVendorStatus(parameters: Data([0x53, 0x01, 0x00, 0x06]))!

        node.updateNodeStatus(message: status, source: node.primaryUnicastAddress)

        XCTAssertTrue(node.isUpDownLightDefaultCctStepsProduct)
        XCTAssertEqual(node.upDownLightDefaultCctSteps, 6)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
    }
```

- [ ] **Step 2: Run the focused SDK test command to capture current failure**

Run:

```bash
swift test --filter NodeCctDefaultValueTests/testDownlightKeepsTunableWhiteDefaultAndUsesFiveStepCctRangeByDefault
```

Expected before implementation:

- Preferred failure: assertion failure because `0x2492` is not yet an `isUpDownLightDefaultCctStepsProduct`.
- Known environment fallback: SwiftPM may fail during compile with `no such module 'UIKit'`. If this happens, record it as the existing SDK test environment limitation and continue with implementation plus iPhoneOS build verification.

---

### Task 2: Add Downlight to SDK CCT Steps Product Predicate

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`

- [ ] **Step 1: Replace `isUpDownLightDefaultCctStepsProduct`**

Replace the current property:

```swift
    var isUpDownLightDefaultCctStepsProduct: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x2491
    }
```

with:

```swift
    var isUpDownLightDefaultCctStepsProduct: Bool {
        guard companyIdentifier == 0x0A78, let productIdentifier else {
            return false
        }
        return productIdentifier == 0x2491 || productIdentifier == 0x2492
    }
```

- [ ] **Step 2: Verify no SDK database code change is needed**

Check this line remains unchanged in `MeshDatabase.swift`:

```swift
PropertyExpressionKey.upDownLightDefaultCctSteps <- self.isUpDownLightDefaultCctStepsProduct ? Int(self.upDownLightDefaultCctSteps) : nil,
```

Reason: once `isUpDownLightDefaultCctStepsProduct` includes `0x2492`, existing persistence automatically includes Downlight.

- [ ] **Step 3: Run the SDK CCT tests**

Run:

```bash
swift test --filter NodeCctDefaultValueTests
```

Expected after implementation:

- Preferred result: tests pass.
- Known environment fallback: if SwiftPM fails with `no such module 'UIKit'`, do not treat that as feature failure. Continue and rely on app iPhoneOS build plus `git diff --check`.

- [ ] **Step 4: Check SDK diff whitespace**

Run:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff --check
```

Expected:

```text
```

No output means the check passed.

---

### Task 3: Add App-Side CCT Steps Capability and Use It in Reader

**Files:**
- Modify: `SunSmart/Common/Data/Node+Capability.swift`
- Modify: `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`

- [ ] **Step 1: Add dedicated App capability**

In `SunSmart/Common/Data/Node+Capability.swift`, insert this property immediately after `supportsUpDownRatioControl`:

```swift
    var supportsUpDownLightDefaultCctSteps: Bool {
        guard companyIdentifier == 0x0A78, let productIdentifier else {
            return false
        }
        return productIdentifier == 0x2491 || productIdentifier == 0x2492
    }
```

Keep `supportsUpDownRatioControl` exactly as:

```swift
    var supportsUpDownRatioControl: Bool {
        companyIdentifier == 0x0A78 && productIdentifier == 0x2491
    }
```

- [ ] **Step 2: Update Reader node filtering**

In `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`, replace:

```swift
        let supportedNodes = nodes.filter { $0.supportsUpDownRatioControl }
```

with:

```swift
        let supportedNodes = nodes.filter { $0.supportsUpDownLightDefaultCctSteps }
```

- [ ] **Step 3: Confirm no ratio UI references were widened**

Run:

```bash
rg -n "supportsUpDownRatioControl|supportsUpDownLightDefaultCctSteps" SunSmart
```

Expected:

- `supportsUpDownRatioControl` still appears in device detail and group ratio UI/control paths.
- `supportsUpDownLightDefaultCctSteps` appears only in `Node+Capability.swift` and `DeviceGroupDeferredSyncPlanner.swift`.

- [ ] **Step 4: Check App diff whitespace**

Run:

```bash
git diff --check
```

Expected:

```text
```

No output means the check passed.

---

### Task 4: Build and Regression Verification

**Files:**
- Verify: `SunSmart.xcworkspace`
- Verify: local SDK `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

- [ ] **Step 1: Verify local SDK package reference is still active**

Run:

```bash
rg -n "XCLocalSwiftPackageReference|nordic-sig-mesh-sdk" SunSmart.xcodeproj/project.pbxproj
```

Expected includes:

```text
XCLocalSwiftPackageReference "/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk"
relativePath = "/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk";
```

- [ ] **Step 2: Build the iPhoneOS app target**

Run exactly:

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Review final diffs for scope**

Run:

```bash
git diff -- SunSmart/Common/Data/Node+Capability.swift SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk diff -- Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
```

Expected:

- App diff only adds `supportsUpDownLightDefaultCctSteps` and switches Reader filtering.
- SDK diff only adds `0x2492` to CCT steps product handling and adds tests.
- No changes to `devices_config.json`.
- No widening of `supportsUpDownRatioControl`.

- [ ] **Step 4: Commit implementation if verification passes**

Stage only the implementation files:

```bash
git add SunSmart/Common/Data/Node+Capability.swift SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
```

Commit messages:

```bash
git -C /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk commit -m "feat: add downlight cct steps defaults"
git commit -m "feat: read downlight cct steps after provisioning"
```

If the user does not want commits during execution, skip this step and report the exact staged or unstaged files.

---

## Self-Review

Spec coverage:

- Adds Downlight `CID 0x0A78 / PID 0x2492` to CCT steps support: Task 2.
- Reads steps after Classic add / Professional add / Restore add: Task 3 keeps existing reader call sites and changes only filtering.
- Does not enable up/down ratio: Task 3 preserves `supportsUpDownRatioControl`; Task 4 verifies usage.
- Persists and restores steps: Task 2 relies on existing `MeshDatabase` predicate path after extending SDK product predicate.
- Device Parameter Settings default range follows steps: Task 2 updates SDK source of truth and Task 1 tests it.
- Does not edit local `devices_config.json`: File Structure and Task 4 scope check.

Placeholder scan:

- No reserved marker words or ambiguous implementation steps.

Type consistency:

- App property name is consistently `supportsUpDownLightDefaultCctSteps`.
- SDK property name remains existing `isUpDownLightDefaultCctStepsProduct`.
- Test helper remains existing `makeNode(productIdentifier:)`.
