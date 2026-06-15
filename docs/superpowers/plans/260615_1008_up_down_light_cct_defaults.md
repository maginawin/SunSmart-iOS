# Up Down Light CCT Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not use subagent-driven execution unless the user explicitly asks for subagents.

**Goal:** Make `CID 0x0A78 / PID 0x2491` keep `Tunable White` as the default Change Control Page while using `2700K...5000K` as the default Absolute CCT Range.

**Architecture:** The source of truth stays in `NordicSigMeshSDK` `Node` derived defaults. Split the existing single-white product predicate from the CCT range default predicate so `0x2491` can use the narrow CCT range without becoming a Single White default product. The App continues to read `Node.defaultChangeControlPage`, `Node.defaultAbsoluteCctRange`, and `Node.effectiveCctRange` without UI-specific overrides.

**Tech Stack:** Swift, XCTest, NordicSigMeshSDK Swift Package, SunSmart iOS workspace, Xcode `xcodebuild`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift` | New focused XCTest coverage for CCT default value contracts. |
| `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift` | Existing SDK `Node` CCT default properties. Add a range-specific predicate and update `defaultAbsoluteCctRange`. |
| `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light/docs/superpowers/specs/260615_0959_up_down_light_cct_defaults_design.md` | Approved design reference. No implementation changes needed. |

## Task 1: Add Failing SDK Tests

**Files:**
- Create: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`

- [ ] **Step 1: Create the CCT default value test file**

Create `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift` with:

```swift
import XCTest
@testable import NordicSigMeshSDK

final class NodeCctDefaultValueTests: XCTestCase {

    func testUpDownLightKeepsTunableWhiteDefaultAndUsesNarrowCctRange() {
        let node = makeNode(productIdentifier: 0x2491)

        XCTAssertFalse(node.isSingleWhiteDefaultCctProduct)
        XCTAssertEqual(node.defaultChangeControlPage, .tunableWhite)
        XCTAssertEqual(node.effectiveChangeControlPage, .tunableWhite)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
    }

    func testExistingSingleWhiteDefaultProductsRemainSingleWhiteWithNarrowCctRange() {
        [UInt16(0x2013), UInt16(0x24B1)].forEach { productIdentifier in
            let node = makeNode(productIdentifier: productIdentifier)

            XCTAssertTrue(node.isSingleWhiteDefaultCctProduct)
            XCTAssertEqual(node.defaultChangeControlPage, .singleWhite)
            XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
            XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
        }
    }

    func testOtherCctProductsKeepTunableWhiteAndStandardCctRange() {
        let node = makeNode(productIdentifier: 0x24A1)

        XCTAssertFalse(node.isSingleWhiteDefaultCctProduct)
        XCTAssertEqual(node.defaultChangeControlPage, .tunableWhite)
        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.standardDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, NodeAbsoluteCctRange.standardDefaultRange)
    }

    func testConfiguredAbsoluteCctRangeOverridesUpDownLightDefault() {
        let node = makeNode(productIdentifier: 0x2491)
        node.absoluteCctRange = 3000...4500

        XCTAssertEqual(node.defaultAbsoluteCctRange, NodeAbsoluteCctRange.singleWhiteDefaultRange)
        XCTAssertEqual(node.effectiveCctRange, 3000...4500)
    }

    private func makeNode(productIdentifier: UInt16) -> Node {
        let node = Node(name: "CCT Light", unicastAddress: 0x1000, elements: 3)
        node.companyIdentifier = 0x0A78
        node.productIdentifier = productIdentifier
        return node
    }
}
```

- [ ] **Step 2: Run the new test and verify it fails for `0x2491`**

Run from SDK root:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter NodeCctDefaultValueTests
```

Expected: the new suite fails on `testUpDownLightKeepsTunableWhiteDefaultAndUsesNarrowCctRange`, because current `defaultAbsoluteCctRange` for `0x2491` is `2700...6500` instead of `2700...5000`.

## Task 2: Split the SDK Default Predicates

**Files:**
- Modify: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Test: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`

- [ ] **Step 1: Add a range-specific default predicate**

In `Node+Propertys.swift`, replace the current CCT default block:

```swift
    var isSingleWhiteDefaultCctProduct: Bool {
        guard companyIdentifier == 0x0A78, let productIdentifier else {
            return false
        }
        return productIdentifier == 0x2013 || productIdentifier == 0x24B1
    }
    
    var defaultChangeControlPage: NodeChangeControlPage {
        isSingleWhiteDefaultCctProduct ? .singleWhite : .tunableWhite
    }
    
    var defaultAbsoluteCctRange: ClosedRange<UInt16> {
        isSingleWhiteDefaultCctProduct ? NodeAbsoluteCctRange.singleWhiteDefaultRange : NodeAbsoluteCctRange.standardDefaultRange
    }
```

with:

```swift
    var isSingleWhiteDefaultCctProduct: Bool {
        guard companyIdentifier == 0x0A78, let productIdentifier else {
            return false
        }
        return productIdentifier == 0x2013 || productIdentifier == 0x24B1
    }
    
    var isNarrowDefaultCctRangeProduct: Bool {
        guard companyIdentifier == 0x0A78, let productIdentifier else {
            return false
        }
        return isSingleWhiteDefaultCctProduct || productIdentifier == 0x2491
    }
    
    var defaultChangeControlPage: NodeChangeControlPage {
        isSingleWhiteDefaultCctProduct ? .singleWhite : .tunableWhite
    }
    
    var defaultAbsoluteCctRange: ClosedRange<UInt16> {
        isNarrowDefaultCctRangeProduct ? NodeAbsoluteCctRange.singleWhiteDefaultRange : NodeAbsoluteCctRange.standardDefaultRange
    }
```

- [ ] **Step 2: Run the focused SDK tests**

Run from SDK root:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter NodeCctDefaultValueTests
```

Expected: PASS. The `0x2491` node keeps `.tunableWhite` but now gets `NodeAbsoluteCctRange.singleWhiteDefaultRange`.

- [ ] **Step 3: Run existing related SDK tests**

Run from SDK root:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
swift test --filter PowerSwitchAppKeyBindSupportModelsTests
```

Expected: PASS. This guards against accidental product predicate fallout around existing `0x2013` usage in SDK tests.

- [ ] **Step 4: Commit SDK changes**

Run from SDK root:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
git status --short
git diff --check
git add Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
git commit -m "fix: set up down light default cct range"
```

Expected: the commit contains only `Node+Propertys.swift` and `NodeCctDefaultValueTests.swift`.

## Task 3: Verify SunSmart Uses the SDK Rule

**Files:**
- Read: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light/SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift`
- Read: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light/SunSmart.xcodeproj/project.pbxproj`

- [ ] **Step 1: Confirm SunSmart is using the local SDK package path**

Run from App worktree:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light
rg -n "XCLocalSwiftPackageReference|nordic-sig-mesh-sdk|defaultCctRangeDataForSelection|defaultChangeControlPageForSelection" SunSmart.xcodeproj/project.pbxproj SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift
```

Expected:

```text
SunSmart.xcodeproj/project.pbxproj:... XCLocalSwiftPackageReference "/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk"
SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift:... defaultChangeControlPageForSelection
SunSmart/Main/Device/Parameter/Controller/DeviceParameterSettingsController.swift:... defaultCctRangeDataForSelection
```

- [ ] **Step 2: Confirm there is no App-side `0x2491` override needed**

Run from App worktree:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light
rg -n "0x2491|defaultAbsoluteCctRange|isNarrowDefaultCctRangeProduct|isSingleWhiteDefaultCctProduct" SunSmart /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift -g '*.swift'
```

Expected:

```text
SunSmart/Common/Data/Node+Capability.swift:... companyIdentifier == 0x0A78 && productIdentifier == 0x2491
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/.../Node+Propertys.swift:... isNarrowDefaultCctRangeProduct
/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/.../Node+Propertys.swift:... productIdentifier == 0x2491
```

The App should not contain a new Device Parameter Settings special case for `0x2491`.

- [ ] **Step 3: Check App worktree whitespace without staging existing image resources**

Run from App worktree:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light
git diff --check
git diff --cached --check -- docs/superpowers/plans/260615_1008_up_down_light_cct_defaults.md
```

Expected: no whitespace errors. Existing staged `up down cct` image resources may still appear in `git status`; do not reset or commit them as part of this task.

- [ ] **Step 4: Build SunSmart for iPhoneOS**

Run from App worktree:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`.

## Task 4: Final Review

**Files:**
- Review: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift`
- Review: `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift`
- Review: `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light/docs/superpowers/plans/260615_1008_up_down_light_cct_defaults.md`

- [ ] **Step 1: Verify SDK diff scope**

Run from SDK root:

```bash
cd /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk
git show --stat --oneline HEAD
```

Expected: latest SDK commit is `fix: set up down light default cct range` and includes only:

```text
Sources/NordicSigMeshSDK/MeshLib/Node/Node+Propertys.swift
Tests/NordicSigMeshSDKTests/NodeCctDefaultValueTests.swift
```

- [ ] **Step 2: Verify App worktree staged resources were not changed by this implementation**

Run from App worktree:

```bash
cd /Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/up-down-light
git status --short
```

Expected: any remaining staged `SunSmart/Assets.xcassets/up down cct/...` files are pre-existing user changes and are not included in this implementation's SDK commit.

- [ ] **Step 3: Summarize verification evidence**

Final response should include:

```text
SDK focused test: swift test --filter NodeCctDefaultValueTests -> PASS
SDK related test: swift test --filter PowerSwitchAppKeyBindSupportModelsTests -> PASS
Whitespace: git diff --check -> PASS
App build: xcodebuild ... CODE_SIGNING_ALLOWED=NO build -> BUILD SUCCEEDED
SDK commit: <hash> fix: set up down light default cct range
```

If any command fails, stop and report the exact failure instead of claiming completion.

## Self-Review

- Spec coverage: Task 1 locks expected default behavior, Task 2 implements SDK source of truth, Task 3 verifies App integration and iPhoneOS build, Task 4 verifies scope and final evidence.
- Placeholder scan: clean; all tasks include concrete files, code, commands, and expected outcomes.
- Type consistency: plan uses existing `NodeChangeControlPage`, `NodeAbsoluteCctRange`, `defaultChangeControlPage`, `defaultAbsoluteCctRange`, `effectiveCctRange`, and adds one new SDK predicate `isNarrowDefaultCctRangeProduct`.
