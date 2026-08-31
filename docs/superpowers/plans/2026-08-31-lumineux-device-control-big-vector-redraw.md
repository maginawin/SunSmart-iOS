# Lumineux Device and Group Control Big Vector Redraw Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incorrect Lumineux 56pt Device and Group control off/on icons with independently rendered sharp 2x and 3x PNGs matching the approved 40pt icons.

**Architecture:** Temporary Swift CoreGraphics renderers draw normalized circles and power-symbol paths directly on each target pixel canvas. Focused image contracts prove the old Device and Group resources fail before replacement and pass afterward; temporary UIKit tests validate the real 56pt button state layouts on iPad without leaving test-source changes in the repository.

**Tech Stack:** Swift, CoreGraphics, ImageIO, XCTest/UIKit, Xcode asset catalogs.

## Global Constraints

- Do not resize the approved 80px or 120px PNGs to produce the big assets.
- Render 112x112 and 168x168 independently from the same normalized vector geometry.
- Use sRGB `#4D738A`, transparent off-state background, solid blue on-state circle, round line caps, and a white on-state power glyph.
- Scale all geometry and line widths by exactly `56 / 40 = 1.4` relative to the approved standard icons.
- Leave the universal 1x slot empty and remove the stale incorrect 1x PNG.
- Modify only the Device and Group off/on `_big` imagesets; preserve all existing user changes and do not commit or push generated assets.

---

### Task 1: Establish the failing Device big-icon contract

**Files:**
- Create temporarily: `/private/tmp/lumineux_device_control_big_contract.swift`
- Read: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off.imageset`
- Read: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on.imageset`
- Test: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off_big.imageset`
- Test: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on_big.imageset`

**Interfaces:**
- Consumes: approved standard 2x/3x PNG geometry and the four current big PNG paths.
- Produces: a command-line contract that exits nonzero when a big icon uses stale filled-off artwork, wrong dimensions, a non-empty 1x slot, or a visible-extent ratio differing from its standard icon by more than 2%.

- [x] **Step 1: Add the temporary contract**

Implement a Swift script using `CGImageSourceCreateImageAtIndex` and an RGBA `CGContext`. For each scale 2 and 3, assert:

```swift
check(big.width == 56 * scale && big.height == 56 * scale, "wrong big canvas")
check(abs(visibleExtent(big) / Double(big.width) - visibleExtent(standard) / Double(standard.width)) <= 0.02,
      "big visible geometry differs from standard")
check(alpha(bigOff, x: bigOff.width / 2, y: bigOff.height / 2) <= 8,
      "off big center must remain transparent")
check(rgb(bigOn, x: bigOn.width / 2, y: bigOn.height / 2) == (77, 115, 138),
      "on big center must use Lumineux blue")
```

Decode both `Contents.json` files and require the universal 1x entry to omit `filename`.

- [x] **Step 2: Run the contract against the current bug assets**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-big-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-big-swift-cache \
xcrun swift /private/tmp/lumineux_device_control_big_contract.swift
```

Expected: FAIL because the current off-big center is opaque gray and both big icons retain the old 80%-extent artwork/1x entries.

### Task 2: Render and replace the two Device big assets

**Files:**
- Create temporarily: `/private/tmp/render_lumineux_device_control_big.swift`
- Modify: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off_big.imageset/Contents.json`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off_big.imageset/device_control_off_big@2x.png`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off_big.imageset/device_control_off_big@3x.png`
- Delete: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_off_big.imageset/device_control_off_big@1x.png`
- Modify: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on_big.imageset/Contents.json`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on_big.imageset/device_control_on_big@2x.png`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on_big.imageset/device_control_on_big@3x.png`
- Delete: `Lumineux/Assets-Lumineux.xcassets/Device/device_control_on_big.imageset/device_control_on_big@1x.png`

**Interfaces:**
- Consumes: normalized 120-unit geometry measured from the approved standard 3x icons.
- Produces: `renderIcon(side:isOn:destination:)`, which writes one direct-rendered RGBA PNG for a specified target side.

- [x] **Step 1: Implement the temporary CoreGraphics renderer**

Use an RGBA sRGB bitmap context with antialiasing enabled. For each side in `[112, 168]`, calculate `unit = CGFloat(side) / 120`. Draw the outer state and glyph directly:

```swift
let blue = CGColor(red: 77.0 / 255, green: 115.0 / 255, blue: 138.0 / 255, alpha: 1)
let outerLineWidth = 2.4 * unit
let glyphLineWidth = 6.0 * unit

if isOn {
    context.setFillColor(blue)
    context.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
} else {
    context.setStrokeColor(blue)
    context.setLineWidth(outerLineWidth)
    let inset = outerLineWidth / 2
    context.strokeEllipse(in: CGRect(x: inset, y: inset,
                                     width: CGFloat(side) - outerLineWidth,
                                     height: CGFloat(side) - outerLineWidth))
}

context.setStrokeColor(isOn ? CGColor(gray: 1, alpha: 1) : blue)
context.setLineWidth(glyphLineWidth)
context.setLineCap(.round)
context.move(to: CGPoint(x: 60 * unit, y: 93 * unit))
context.addLine(to: CGPoint(x: 60 * unit, y: 72 * unit))
context.strokePath()
context.addArc(center: CGPoint(x: 60 * unit, y: 61.5 * unit),
               radius: 29.5 * unit,
               startAngle: 134.5 * .pi / 180,
               endAngle: 405.5 * .pi / 180,
               clockwise: false)
context.strokePath()
```

Write each `CGImage` with `CGImageDestinationCreateWithURL(..., "public.png", ...)`. Render 2x and 3x independently; never use one output as the input for another.

- [x] **Step 2: Run the renderer**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-big-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-big-swift-cache \
xcrun swift /private/tmp/render_lumineux_device_control_big.swift
```

Expected: four output PNGs written directly to the two `_big.imageset` directories.

- [x] **Step 3: Align the asset-catalog scale contract**

Edit both `Contents.json` files so the 1x dictionary contains only `idiom: universal` and `scale: 1x`. Keep the existing 2x/3x filenames. Delete the two stale 1x PNGs explicitly.

- [x] **Step 4: Re-run the focused image contract**

Run the Task 1 command again.

Expected: PASS for dimensions, empty 1x slots, normalized visible extents, transparent off center, and blue on center.

### Task 3: Verify Device sharpness and real 56pt UIKit layout

**Files:**
- Create temporarily: `Tests/Branding/LumineuxDeviceControlBigRuntimeTests.swift`
- Remove after validation: `Tests/Branding/LumineuxDeviceControlBigRuntimeTests.swift`
- Inspect: the four generated PNGs and exported XCTest attachments.

**Interfaces:**
- Consumes: compiled `device_control_off_big` and `device_control_on_big` images from the Lumineux catalog.
- Produces: two iPad screenshots from a real 56x56 `UIButton`, one normal and one selected.

- [x] **Step 1: Add a temporary UIKit layout test**

Create an `@MainActor XCTestCase` that constructs the real project initializer:

```swift
let button = UIButton(normalImageName: "device_control_off_big",
                      selectedImageName: "device_control_on_big")
button.translatesAutoresizingMaskIntoConstraints = false
host.view.addSubview(button)
NSLayoutConstraint.activate([
    button.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
    button.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
    button.widthAnchor.constraint(equalToConstant: 56),
    button.heightAnchor.constraint(equalToConstant: 56)
])
host.view.layoutIfNeeded()
XCTAssertEqual(button.bounds.size, CGSize(width: 56, height: 56))
XCTAssertFalse(button.hasAmbiguousLayout)
XCTAssertEqual(button.currentImage?.size, CGSize(width: 56, height: 56))
```

Attach off and selected screenshots with `UIGraphicsImageRenderer(bounds: button.bounds)`.

- [x] **Step 2: Generate the temporary runtime workspace and run the iPad test**

Use an available iPad Pro 11-inch simulator from `xcrun simctl list devices available`, then run only `LumineuxDeviceControlBigRuntimeTests` with `ARCHS=x86_64`, automatic package resolution disabled, and the existing `SourcePackages` cache.

Expected: 1 test passed, no layout ambiguity, both images resolve at 56pt.

- [x] **Step 3: Export and inspect the attachments**

Use `xcresulttool export attachments`, then inspect both PNGs at original detail. Require a centered circular control, crisp single-pixel antialias transition, no clipping, and matching off/on geometry.

- [x] **Step 4: Run repository checks**

Run:

```bash
swift Tests/Branding/LumineuxAssetTests.swift
git diff --check
```

The broad asset test may report the already-staged empty-1x migration for standard Device/Group icons; distinguish that pre-existing contract update from the focused big-icon contract. `git diff --check` must pass.

- [x] **Step 5: Remove temporary files and inspect final scope**

Delete the temporary renderer, image contract, temporary XCTest file, and generated test workspace. Verify that this task added changes only under the two Device `_big.imageset` directories; preserve all other staged user changes. Do not commit or push the generated resources.

### Task 4: Render, replace, and verify the two Group big assets

**Files:**
- Create temporarily: `/private/tmp/lumineux_group_control_big_contract.swift`
- Create temporarily: `/private/tmp/render_lumineux_group_control_big.swift`
- Read: `Lumineux/Assets-Lumineux.xcassets/Group/group_off.imageset`
- Read: `Lumineux/Assets-Lumineux.xcassets/Group/group_on.imageset`
- Modify: `Lumineux/Assets-Lumineux.xcassets/Group/group_off_big.imageset/Contents.json`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Group/group_off_big.imageset/group_off_big@2x.png`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Group/group_off_big.imageset/group_off_big@3x.png`
- Delete: `Lumineux/Assets-Lumineux.xcassets/Group/group_off_big.imageset/group_off_big@1x.png`
- Modify: `Lumineux/Assets-Lumineux.xcassets/Group/group_on_big.imageset/Contents.json`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Group/group_on_big.imageset/group_on_big@2x.png`
- Replace: `Lumineux/Assets-Lumineux.xcassets/Group/group_on_big.imageset/group_on_big@3x.png`
- Delete: `Lumineux/Assets-Lumineux.xcassets/Group/group_on_big.imageset/group_on_big@1x.png`
- Create temporarily: `Tests/Branding/LumineuxGroupControlBigRuntimeTests.swift`

**Interfaces:**
- Consumes: approved `group_off/on` 2x/3x PNG geometry and the current Group big PNGs.
- Produces: four independently rendered Group PNGs plus focused image and UIKit evidence for `group_off_big` and `group_on_big`.

- [ ] **Step 1: Add and run the failing Group image contract**

Decode the standard and big Group images with `CGImageSourceCreateImageAtIndex`, draw them into an sRGB RGBA context, and assert for scales 2 and 3:

```swift
check(big.width == 56 * scale && big.height == 56 * scale, "wrong Group big canvas")
check(abs(visibleExtent(big) / Double(big.width) - visibleExtent(standard) / Double(standard.width)) <= 0.02,
      "Group big visible geometry differs from standard")
check(alpha(bigOff, x: bigOff.width / 2, y: bigOff.height / 2) <= 8,
      "Group off big center must remain transparent")
check(rgb(bigOn, x: bigOn.width / 2, y: bigOn.height / 2) == (77, 115, 138),
      "Group on big center must use Lumineux blue")
```

Require both Group big universal 1x entries to omit `filename`, then run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-group-big-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-group-big-swift-cache \
xcrun swift /private/tmp/lumineux_group_control_big_contract.swift
```

Expected: FAIL because the old Group off-big center is opaque gray and both old Group big images retain approximately 80% visible extent.

- [ ] **Step 2: Implement and run the Group CoreGraphics renderer**

Create an sRGB RGBA context for each side in `[112, 168]`, calculate `unit = CGFloat(side) / 120`, and draw each output directly with this geometry:

```swift
let blue = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                   components: [77.0 / 255, 115.0 / 255, 138.0 / 255, 1])!
let outerLineWidth = 2.4 * unit
let glyphLineWidth = 6.0 * unit

if isOn {
    context.setFillColor(blue)
    context.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
} else {
    context.setStrokeColor(blue)
    context.setLineWidth(outerLineWidth)
    let inset = outerLineWidth / 2
    context.strokeEllipse(in: CGRect(x: inset, y: inset,
                                     width: CGFloat(side) - outerLineWidth,
                                     height: CGFloat(side) - outerLineWidth))
}

context.setStrokeColor(isOn ? CGColor(colorSpace: context.colorSpace!,
                                      components: [1, 1, 1, 1])! : blue)
context.setLineWidth(glyphLineWidth)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 60 * unit, y: 93 * unit))
context.addLine(to: CGPoint(x: 60 * unit, y: 72 * unit))
context.strokePath()
context.addArc(center: CGPoint(x: 60 * unit, y: 61.5 * unit),
               radius: 29.5 * unit,
               startAngle: 134.5 * .pi / 180,
               endAngle: 405.5 * .pi / 180,
               clockwise: false)
context.strokePath()
```

Write `group_off_big@2x.png`, `group_off_big@3x.png`, `group_on_big@2x.png`, and `group_on_big@3x.png` directly with `CGImageDestinationCreateWithURL`. Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/lumineux-group-big-clang-cache \
SWIFT_MODULECACHE_PATH=/private/tmp/lumineux-group-big-swift-cache \
xcrun swift /private/tmp/render_lumineux_group_control_big.swift
```

- [ ] **Step 3: Align the Group asset-catalog contract and re-run the image contract**

Keep the existing 2x/3x filenames, leave each universal 1x dictionary without `filename`, and ensure the stale 1x PNGs are absent. Re-run the Step 1 command.

Expected: PASS for dimensions, visible extents, transparency, brand color, and empty 1x slots.

- [ ] **Step 4: Run the real 56pt Group UIKit layout test**

Create a temporary `@MainActor XCTestCase` using the production initializer:

```swift
let button = UIButton(normalImageName: "group_off_big",
                      selectedImageName: "group_on_big")
button.translatesAutoresizingMaskIntoConstraints = false
host.view.addSubview(button)
NSLayoutConstraint.activate([
    button.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
    button.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
    button.widthAnchor.constraint(equalToConstant: 56),
    button.heightAnchor.constraint(equalToConstant: 56)
])
host.view.layoutIfNeeded()
XCTAssertEqual(button.bounds.size, CGSize(width: 56, height: 56))
XCTAssertFalse(button.hasAmbiguousLayout)
XCTAssertEqual(button.currentImage?.size, CGSize(width: 56, height: 56))
```

Attach normal and selected 56pt screenshots. Generate the temporary branding workspace and run only `LumineuxGroupControlBigRuntimeTests` on the available iPad Pro 11-inch iOS 18 simulator with x86_64 and package updates disabled.

Expected: 1 test passed; both compiled Group big images resolve at 56pt with no ambiguous layout.

- [ ] **Step 5: Export screenshots, run repository checks, and clean up**

Export both XCTest attachments and inspect them at original detail for centered full-canvas circles, matching off/on geometry, round caps, no clipping, and no interpolation blur. Run:

```bash
swift Tests/Branding/LumineuxAssetTests.swift
git diff --check
```

The broad asset test may still stop at its existing forced `filename` unwrap for Retina-only 1x slots; report that separately from the focused Group contract and UIKit result. Delete the temporary renderer, contract, XCTest file, generated workspace, result bundle, attachments, and module caches. Confirm that Group PNG changes are limited to the two Group `_big.imageset` directories while all existing staged user changes remain intact. Do not commit or push generated resources.
