# Scene Group OFF Button Theme Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Scene Group bottom sheet OFF button derive its selected, unselected, and border colors from the current target's theme instead of fixed SunSmart RGB values.

**Architecture:** Keep the existing `SceneExecuteDataPickerView` state and slider data flow unchanged. Route all OFF button styling through `updateOffButtonState()` using `Bar_Color`, add a standalone source contract for fast red-green verification, and extend the existing Lumineux UIKit suite to verify real rendered colors and layout.

**Tech Stack:** Swift 5, UIKit, SnapKit, standalone Swift contract tests, XCTest, Xcode iOS Simulator.

## Global Constraints

- Selected OFF uses `Bar_Color` background, white text, and no border.
- Unselected OFF uses white background, `Bar_Color` text, and `Bar_Color.withAlphaComponent(0.6)` border.
- Preserve the button title, size, corner radius, state logic, tap behavior, lightness behavior, Scene persistence, preview, Mesh control, and CCT capability handling.
- Do not change image assets, slider colors, unrelated hard-coded colors, target configuration, dependencies, signing, or localization.
- UI completion requires real layout testing; compilation and source checks alone are insufficient.

---

### Task 1: Theme the Scene Group OFF button with red-green UI coverage

**Files:**
- Create: `Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift`
- Modify: `Tests/Branding/LumineuxRuntimeTests.swift`
- Modify: `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift:100-105,224-227`

**Interfaces:**
- Consumes: compile-time brand value `Bar_Color: UIColor`; existing `SceneExecuteDataPickerView.show(...)`; existing `LumineuxRuntimeTests.assertBlue(_:alpha:file:line:)`.
- Produces: unchanged Scene picker API and interaction behavior; OFF button styles derived only from `Bar_Color`.

- [ ] **Step 1: Add the failing standalone theme contract**

Create `Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift`:

```swift
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Expected SceneExecuteDataPickerView source path")
}

let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)

require(
    source.contains("offBtn.backgroundColor = isOff ? Bar_Color : .white"),
    "Selected OFF background must use the current brand Bar_Color"
)
require(
    source.contains("offBtn.setTitleColor(isOff ? .white : Bar_Color, for: .normal)"),
    "Unselected OFF title must use the current brand Bar_Color"
)
require(
    source.contains("offBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.6).cgColor"),
    "Unselected OFF border must derive from the current brand Bar_Color"
)
require(
    source.contains("titleColor: Bar_Color"),
    "OFF button initialization must not start with a fixed SunSmart title color"
)
require(
    !source.contains("offBtn.backgroundColor = isOff ? RGB(102, 103, 171) : .white") &&
        !source.contains("offBtn.layer.borderColor = RGB(147, 148, 196).cgColor"),
    "Scene OFF styling must not retain the fixed SunSmart RGB values"
)

print("SceneExecuteDataPickerThemeContractTests passed")

func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else { fatalError(message) }
}
```

- [ ] **Step 2: Run the contract and verify RED**

Run:

```sh
swift Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift \
  SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
```

Expected: exit non-zero with `Selected OFF background must use the current brand Bar_Color`, because production still contains `RGB(102, 103, 171)`.

- [ ] **Step 3: Add the real Lumineux UIKit regression before changing production code**

Add this test method to `LumineuxRuntimeTests`:

```swift
func testSceneGroupOffButtonUsesLumineuxThemeAndKeepsLayout() throws {
    SceneExecuteDataPickerView.show(
        lightness: 50,
        isOn: true,
        cct: 4500,
        showCct: true,
        showDelete: false,
        picker: nil
    )

    let picker = try XCTUnwrap(
        window.subviews.compactMap { $0 as? SceneExecuteDataPickerView }.last
    )
    defer { picker.removeFromSuperview() }
    window.layoutIfNeeded()
    picker.layoutIfNeeded()

    let offButton = try XCTUnwrap(
        descendants(picker).compactMap { $0 as? UIButton }
            .first { $0.title(for: .normal) == "OFF" }
    )
    let container = try XCTUnwrap(offButton.superview)

    XCTAssertEqual(offButton.bounds.width, SCRXFrom(52), accuracy: 0.5)
    XCTAssertEqual(offButton.bounds.height, SCRYFrom(32), accuracy: 0.5)
    XCTAssertEqual(offButton.layer.cornerRadius, SCRYFrom(10), accuracy: 0.5)
    XCTAssertFalse(offButton.hasAmbiguousLayout)
    assertContained(offButton, in: container)
    XCTAssertEqual(offButton.backgroundColor, .white)
    assertBlue(offButton.titleColor(for: .normal))
    assertBlue(UIColor(cgColor: try XCTUnwrap(offButton.layer.borderColor)), alpha: 0.6)
    XCTAssertEqual(offButton.layer.borderWidth, 1, accuracy: 0.01)

    offButton.sendActions(for: .touchUpInside)

    assertBlue(offButton.backgroundColor)
    XCTAssertEqual(offButton.titleColor(for: .normal), .white)
    XCTAssertEqual(offButton.layer.borderWidth, 0, accuracy: 0.01)
    XCTAssertFalse(offButton.hasAmbiguousLayout)
    assertContained(offButton, in: container)
    snapshot(window, "Scene-group-off-theme")
}
```

- [ ] **Step 4: Implement the minimal theme-derived styling**

In `updateOffButtonState()`, replace only the three fixed color assignments:

```swift
private func updateOffButtonState() {
    let isOff = !isOn
    offBtn.backgroundColor = isOff ? Bar_Color : .white
    offBtn.setTitleColor(isOff ? .white : Bar_Color, for: .normal)
    offBtn.layer.borderWidth = isOff ? 0 : 1
    offBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.6).cgColor
}
```

In `setupUI()`, initialize the OFF title from the theme and remove the duplicate fixed border color assignment:

```swift
offBtn = UIButton(
    title: "OFF",
    titleSize: 12,
    titleWeight: .medium,
    titleColor: Bar_Color,
    target: self,
    action: #selector(offBtnAction)
)
offBtn.layer.cornerRadius = SCRYFrom(10)
```

Keep the existing `updateOffButtonState()` call after the slider setup so initial border width and color still come from the same state renderer.

- [ ] **Step 5: Run the fast contract and verify GREEN**

Run:

```sh
swift Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift \
  SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
```

Expected: `SceneExecuteDataPickerThemeContractTests passed` and exit 0.

- [ ] **Step 6: Prove the regression contract detects the original bug**

Save only the production-file change to a temporary patch, reverse it, run the contract, then restore the same patch:

```sh
git diff --binary \
  --output=/private/tmp/scene-off-theme-production.patch \
  -- SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
git apply -R /private/tmp/scene-off-theme-production.patch
swift Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift \
  SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
git apply /private/tmp/scene-off-theme-production.patch
swift Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift \
  SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift
```

Expected: the first Swift run exits non-zero with the expected `Bar_Color` message; after restoring the patch, the second run prints `SceneExecuteDataPickerThemeContractTests passed`. Do not use `git checkout`, `git reset`, or any command that could discard unrelated work.

- [ ] **Step 7: Run the focused Lumineux UIKit test on iPhone and iPad**

Create an isolated generated test workspace and reuse the existing locked package checkout:

```sh
scene_off_tmp="$(mktemp -d /private/tmp/scene-off-theme.XXXXXX)"
ruby scripts/make_lumineux_test_workspace.rb "$scene_off_tmp/runtime"
xcodebuild \
  -workspace "$scene_off_tmp/runtime/LumineuxBranding.xcworkspace" \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=1B4321CD-F455-4252-8504-105435A02C9A,arch=x86_64' \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath "$scene_off_tmp/DerivedData" \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath "$scene_off_tmp/result.xcresult" \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testSceneGroupOffButtonUsesLumineuxThemeAndKeepsLayout \
  -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: two executions of the focused test pass with zero failures and zero skips.

- [ ] **Step 8: Export and inspect the layout attachments**

Run:

```sh
xcrun xcresulttool get test-results summary --path "$scene_off_tmp/result.xcresult"
xcrun xcresulttool export attachments \
  --path "$scene_off_tmp/result.xcresult" \
  --output-path "$scene_off_tmp/screenshots"
```

Inspect both `Scene-group-off-theme` attachments. Confirm the OFF button stays inside the bottom sheet, remains 52×32 scaled points with unchanged corner radius, and displays Lumineux `#4D738A` rather than SunSmart `#6667AB`; reject completion for clipping, overlap, ambiguous layout, or a wrong color.

- [ ] **Step 9: Run relevant static and repository verification**

Run:

```sh
ruby Tests/Branding/LumineuxMergeTests.rb --name test_adds_brand_only_app_icon_and_accent_color
git diff --check
git status --short
```

Expected: focused merge test passes, `git diff --check` exits 0, and status lists only the new Scene contract, the Lumineux runtime test, the Scene picker implementation, and this implementation plan if it has not already been committed.

- [ ] **Step 10: Review and commit the focused implementation**

Inspect `git diff` and confirm there are no behavior, constraint, image, project, dependency, or unrelated theme changes. Then stage explicit paths:

```sh
git add \
  Tests/Scene/SceneExecuteDataPickerThemeContractTests.swift \
  Tests/Branding/LumineuxRuntimeTests.swift \
  SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift \
  docs/superpowers/plans/2026-08-31-scene-off-button-theme-color.md
git diff --cached --check
git diff --cached --name-status
git commit -m "fix: theme Scene Group OFF button"
```

Expected: one focused local commit; do not push without a separate explicit request.
