# Lumineux Bluetooth Required Asset Override Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Lumineux-only `bluetooth_required` image-set override from the two supplied Retina PNGs while preserving shared assets and existing layout behavior.

**Architecture:** Keep `BluetoothRequiredViewController` unchanged and rely on the existing `UIImage(named: "bluetooth_required")` lookup. Add a complete same-named image set to the Lumineux catalog; the existing build-phase merger replaces the common set by logical asset name. Update the catalog contract, temporary UIKit reference bundle count, and a real-view layout test so static bytes, merged output, and runtime geometry are independently verified.

**Tech Stack:** Xcode Asset Catalogs, Swift/ImageIO/CryptoKit contract tests, Ruby catalog merger and validators, XCTest/UIKit, `xcodebuild`.

## Global Constraints

- Only Lumineux receives the override; `SunSmart/Assets.xcassets` and other brands remain unchanged.
- Use `/Users/sr/Documents/SunSmart/assets/new3/images/empty_1@2x.png` and `empty_1@3x.png` without re-encoding.
- Preserve the current `UIImage(named: "bluetooth_required")` call and all production layout constraints.
- Preserve the user's existing `space_empty@2x.png` and `space_empty@3x.png` modifications.
- Do not update dependencies, commit, or push.
- Run actual UIKit layout verification and inspect its screenshot; build success alone is insufficient.

---

### Task 1: Add a focused failing resource contract

**Files:**
- Create: `Tests/Branding/LumineuxBluetoothRequiredAssetTests.swift`

**Interfaces:**
- Consumes: the repository root and the approved logical asset name `bluetooth_required`.
- Produces: a standalone contract that verifies the brand group mapping, asset metadata, exact bytes, Retina dimensions, and alpha-capable PNGs.

- [ ] **Step 1: Create the focused test before adding the asset**

The test must load `Lumineux/DesignAssets/asset-groups.json`, require `assets.bluetooth_required == "Space"`, then inspect `Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset`. It must require these exact variants:

```swift
let expected: [Int: (filename: String, width: Int, height: Int, sha256: String)] = [
    2: ("bluetooth_required@2x.png", 480, 388,
        "82f42e27406d67bff533811bdb51d9d739354978ddb048a3689bf805e046db4d"),
    3: ("bluetooth_required@3x.png", 720, 582,
        "379ff2bf589091e8b64bd14ae12e934b552fe26efae8b83fa4fb36a08f7f4c3d")
]
```

Require a universal empty 1x entry, populated universal 2x/3x entries, exact SHA-256 values, exact pixel sizes via ImageIO, and an alpha mode other than `.none`, `.noneSkipFirst`, or `.noneSkipLast`.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
swift -module-cache-path /private/tmp/lumineux-bluetooth-module-cache \
  Tests/Branding/LumineuxBluetoothRequiredAssetTests.swift
```

Expected: non-zero with `bluetooth_required must be registered in the Space group` because the Lumineux mapping and image set do not exist yet.

### Task 2: Add the Lumineux-only image set and make the focused contract green

**Files:**
- Modify: `Lumineux/DesignAssets/asset-groups.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset/bluetooth_required@2x.png`
- Create: `Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset/bluetooth_required@3x.png`

**Interfaces:**
- Consumes: the two approved `empty_1` input PNGs.
- Produces: a complete `bluetooth_required.imageset` that the Lumineux merger substitutes at the common asset's original path.

- [ ] **Step 1: Register the brand asset group**

Add this entry to the `assets` object in `asset-groups.json`:

```json
"bluetooth_required": "Space"
```

- [ ] **Step 2: Create matching universal asset metadata**

Create `Contents.json` with:

```json
{
  "images" : [
    {
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "bluetooth_required@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "bluetooth_required@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Copy the approved PNG bytes under the logical asset filenames**

Run exact-path copies; do not use an image conversion command:

```sh
cp /Users/sr/Documents/SunSmart/assets/new3/images/empty_1@2x.png \
  Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset/bluetooth_required@2x.png
cp /Users/sr/Documents/SunSmart/assets/new3/images/empty_1@3x.png \
  Lumineux/Assets-Lumineux.xcassets/Space/bluetooth_required.imageset/bluetooth_required@3x.png
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Task 1 Swift command again.

Expected: exit 0 and `Lumineux bluetooth_required asset tests passed`.

### Task 3: Align catalog contracts and add real UIKit layout coverage

**Files:**
- Modify: `Tests/Branding/LumineuxAssetTests.swift`
- Modify: `Tests/Branding/LumineuxRuntimeTests.swift`
- Modify: `scripts/make_lumineux_test_workspace.rb`
- Modify: `Tests/Branding/README.md`

**Interfaces:**
- Consumes: the new brand image set and existing independent reference-catalog runtime oracle.
- Produces: current 129-set catalog bookkeeping plus `testBluetoothRequiredPageUsesLumineuxOverrideWithoutLayoutAmbiguity()`.

- [ ] **Step 1: Update the comprehensive static contract**

In `LumineuxAssetTests.swift`:

- add `"bluetooth_required": "Space"` to `expectedAssetGroups`;
- change the approved/discovered catalog count from 128 to 129;
- add `bluetooth_required` to `emptyStates` with logical size 240 × 194 and the Task 1 hashes;
- rename the tuple label/message from Figma-only `node` wording to generic `source` wording, using `provided empty_1` for the new entry;
- change the distinct empty-state count from 4 to 5 and the final status text to 129 asset groups and 5 exact empty states.

- [ ] **Step 2: Update the temporary XCTest reference catalog count**

In `make_lumineux_test_workspace.rb`, change the exact expected brand-set count from 128 to 129 in both the condition and diagnostic.

- [ ] **Step 3: Add the real-page runtime layout test**

Add this test to `LumineuxRuntimeTests` using existing helpers:

```swift
func testBluetoothRequiredPageUsesLumineuxOverrideWithoutLayoutAmbiguity() throws {
    let controller = BluetoothRequiredViewController()
    show(NavigationViewController(rootViewController: controller))
    defer { SRAlertView.hide() }

    let emptyView = try XCTUnwrap(controller.view.emptyView)
    let imageView = try XCTUnwrap(emptyView.imageView)
    let titleLabel = try XCTUnwrap(emptyView.titleLabel)
    let tipLabel = try XCTUnwrap(emptyView.tipLabel)

    XCTAssertEqual(titleLabel.text, "Bluetooth required")
    XCTAssertEqual(tipLabel.text, "Turn on bluetooth to use the app.")
    XCTAssertEqual(imageView.image?.size, CGSize(width: 240, height: 194))
    try assertResolvedImageMatchesLumineuxSource(imageView.image, name: "bluetooth_required")

    for view in [emptyView, imageView, titleLabel, tipLabel] {
        XCTAssertFalse(view.hasAmbiguousLayout, "Ambiguous Bluetooth-required layout: \(type(of: view))")
        assertContained(view, in: controller.view)
    }
    let titleFrame = titleLabel.convert(titleLabel.bounds, to: controller.view)
    let imageFrame = imageView.convert(imageView.bounds, to: controller.view)
    let tipFrame = tipLabel.convert(tipLabel.bounds, to: controller.view)
    XCTAssertLessThan(titleFrame.maxY, imageFrame.minY)
    XCTAssertLessThanOrEqual(imageFrame.maxY, tipFrame.minY)
    snapshot(window, "Bluetooth-required-page")
}
```

The popup continues to use the pre-existing `SRAlertView` presentation path; this asset-only change verifies the production page hierarchy and resolved illustration without changing or duplicating alert lifecycle behavior in the temporary test host.

- [ ] **Step 4: Update only the README's current-state counts**

Change the current catalog summary to 127 imagesets plus AppIcon/AccentColor = 129 sets, reference catalog = 129, extra packaged = 34, provided total = 124, merged split = 129 Lumineux + 566 Common. Preserve dated historical records below the current summary.

- [ ] **Step 5: Run focused and structural checks**

Run:

```sh
swift -module-cache-path /private/tmp/lumineux-bluetooth-module-cache \
  Tests/Branding/LumineuxBluetoothRequiredAssetTests.swift
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxGeneratorTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby scripts/validate_lumineux_asset_groups.rb \
  Lumineux/Assets-Lumineux.xcassets \
  Lumineux/DesignAssets/asset-groups.json
```

Expected: all focused/structural commands exit 0. Run the comprehensive asset test separately and retain the exact pre-existing `space_empty` failure boundary:

```sh
swift -module-cache-path /private/tmp/lumineux-bluetooth-module-cache \
  Tests/Branding/LumineuxAssetTests.swift
```

Expected current-worktree baseline: it reaches the empty-state section and fails at the user's existing `space_empty` canvas/hash contract, not at `bluetooth_required` registration, metadata, size, or hash checks.

### Task 4: Verify merged bytes, actual layout, build, and final scope

**Files:**
- Verify only; no additional production files.

**Interfaces:**
- Consumes: the completed source catalog and runtime layout test.
- Produces: fresh evidence for brand-only merging, page geometry, screenshot appearance, asset compilation, and preserved worktree scope.

- [ ] **Step 1: Merge into a dedicated temporary derived directory**

Run:

```sh
DERIVED_FILE_DIR=/private/tmp/lumineux-bluetooth-merge \
  ruby Lumineux/Scripts/merge_assets.rb \
  SunSmart/Assets.xcassets \
  Lumineux/Assets-Lumineux.xcassets \
  /private/tmp/lumineux-bluetooth-merge/LumineuxAssets/Assets-Lumineux-Merged.xcassets
```

Require exactly one `bluetooth_required.imageset` in the output, located at the common set's `Space/bluetooth_required.imageset` path. Compare output 2x/3x SHA-256 values to Task 1 and confirm the common source PNG hashes remain unchanged.

- [ ] **Step 2: Generate the temporary test workspace**

Run with Homebrew Ruby so `xcodeproj` is available:

```sh
PATH=/opt/homebrew/opt/ruby/bin:$PATH \
  ruby scripts/make_lumineux_test_workspace.rb \
  /private/tmp/lumineux-bluetooth-runtime
```

- [ ] **Step 3: Run the focused UIKit test on phone and tablet simulators**

Use currently available simulator identifiers resolved by `xcrun simctl list devices available`. Reuse the pinned SourcePackages directory without updating dependencies:

```sh
xcodebuild \
  -workspace /private/tmp/lumineux-bluetooth-runtime/LumineuxBranding.xcworkspace \
  -scheme LumineuxBranding -configuration Debug \
  -destination 'platform=iOS Simulator,id=5E6F7D5C-CC01-4760-8D6E-2489835F1748,arch=x86_64' \
  -destination 'platform=iOS Simulator,id=1B4321CD-F455-4252-8504-105435A02C9A,arch=x86_64' \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath /private/tmp/lumineux-bluetooth-runtime-derived \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath /private/tmp/lumineux-bluetooth-layout.xcresult \
  -only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testBluetoothRequiredPageUsesLumineuxOverrideWithoutLayoutAmbiguity \
  -parallel-testing-enabled NO -jobs 4 \
  test CODE_SIGNING_ALLOWED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: both destinations pass with zero test failures and retain a screenshot attachment.

- [ ] **Step 4: Export and inspect the screenshot**

Run:

```sh
xcrun xcresulttool export attachments \
  --path /private/tmp/lumineux-bluetooth-layout.xcresult \
  --output-path /private/tmp/lumineux-bluetooth-layout-screenshots
```

Inspect each exported PNG at original detail. Require the title above the supplied blue-gray gateway/Bluetooth illustration, the tip below it, no cropping, no overlap, and no off-screen content. The popup remains on its existing `SRAlertView` path and is outside this resource-only layout assertion.

- [ ] **Step 5: Run a signing-disabled Lumineux build**

Run:

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme Lumineux \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/lumineux-bluetooth-build \
  -clonedSourcePackagesDirPath /Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`, with no duplicate-asset or actool error involving `bluetooth_required`.

- [ ] **Step 6: Verify final diff and preserved user changes**

Run:

```sh
git diff --check
git status --short
git diff -- Lumineux/DesignAssets/asset-groups.json \
  Tests/Branding/LumineuxAssetTests.swift \
  Tests/Branding/LumineuxRuntimeTests.swift \
  Tests/Branding/README.md \
  scripts/make_lumineux_test_workspace.rb
```

Require the two pre-existing `space_empty` modifications to remain present and unchanged from their starting SHA-256 values (`ce4138...` and `41c3fe...`). Confirm no changes to `SunSmart/Assets.xcassets`, `SunSmart.xcodeproj/project.pbxproj`, or `Package.resolved`. Do not commit or push.
