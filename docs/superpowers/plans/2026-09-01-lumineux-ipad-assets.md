# Lumineux iPad Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce 14 crisp Lumineux @2x/@3x PNG files for the seven approved resource sets without scaling an iPhone raster into an iPad raster.

**Architecture:** A temporary Swift/AppKit utility will recolor chromatic pixels in existing full-resolution iPad geometry templates while preserving every transparent, white, and gray pixel. Each scale is generated from its matching @2x or @3x template. A second verification mode will validate dimensions, Alpha, palette replacement, and unchanged grid geometry before a labeled preview is produced.

**Tech Stack:** Swift 5, AppKit `NSBitmapImageRep`, PNG, existing Xcode asset catalog resources.

## Global Constraints

- Do not modify `Lumineux/Assets-Lumineux.xcassets` during this delivery.
- Do not upscale a completed @2x image to create @3x, or upscale an iPhone image to create an iPad image.
- Preserve transparent backgrounds and all white/gray chart-grid pixels.
- Use Lumineux core blue `#5E869C`, extracted from the current Lumineux source PNGs.
- Generate exactly seven `.imageset` folders with @2x and @3x PNGs, for 14 PNGs total.
- Save deliverables under `output/lumineux-ipad-assets/`.

---

## File Map

- Create temporarily: `/private/tmp/lumineux_asset_rebuilder.swift` — deterministic recoloring, PNG export, validation, and preview generation.
- Create: `output/lumineux-ipad-assets/Group/auto_big.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/Profile/profile_chart_daylight_ipad.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/Profile/profile_chart_manual_control_ipad.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/Profile/profile_chart_occupancy_ipad.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/Profile/profile_chart_occupancy_daylight_ipad.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/Profile/profile_chart_occupancy_standby.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/Profile/profile_chart_occupancy_standby_ipad.imageset/` — two PNGs and `Contents.json`.
- Create: `output/lumineux-ipad-assets/lumineux-ipad-assets-preview.png` — labeled visual review sheet.
- Create: `output/lumineux-ipad-assets/verification.txt` — machine-readable verification summary.

### Task 1: Build deterministic PNG recoloring utility

**Files:**
- Create temporarily: `/private/tmp/lumineux_asset_rebuilder.swift`

**Interfaces:**
- Consumes: repository root and `AssetJob(template2x, template3x, outputSet, output2x, output3x, size2x, size3x)` values.
- Produces: `recolor(job: AssetJob, scale: Scale) throws -> URL` and `verify(job: AssetJob, scale: Scale, output: URL) throws -> VerificationResult`.

- [ ] **Step 1: Add an executable preflight test**

The utility must run `preflight()` before generation and fail unless all 14 template files exist and their dimensions match the exact job table. Expected dimensions:

```swift
let expected: [String: (Int, Int)] = [
    "auto_big@2x.png": (112, 112),
    "auto_big@3x.png": (168, 168),
    "profile_chart_daylight_ipad@2x.png": (980, 467),
    "profile_chart_daylight_ipad@3x.png": (1470, 701),
    "profile_chart_manual_control_ipad@2x.png": (980, 467),
    "profile_chart_manual_control_ipad@3x.png": (1470, 701),
    "profile_chart_occupancy_ipad@2x.png": (980, 467),
    "profile_chart_occupancy_ipad@3x.png": (1470, 701),
    "profile_chart_occupancy_daylight_ipad@2x.png": (980, 467),
    "profile_chart_occupancy_daylight_ipad@3x.png": (1470, 701),
    "profile_chart_occupancy_standby@2x.png": (424, 467),
    "profile_chart_occupancy_standby@3x.png": (636, 701),
    "profile_chart_occupancy_standby_ipad@2x.png": (980, 467),
    "profile_chart_occupancy_standby_ipad@3x.png": (1470, 701),
]
```

- [ ] **Step 2: Run preflight before implementation and confirm it fails**

Run:

```bash
swift -module-cache-path /private/tmp/codex-swift-cache /private/tmp/lumineux_asset_rebuilder.swift preflight
```

Expected: failure stating that `recolor(job:scale:)` and output validation are not implemented.

- [ ] **Step 3: Implement pixel classification and recoloring**

For every template pixel, preserve its Alpha. Treat a pixel as chromatic only when `max(r,g,b) - min(r,g,b) >= 12`; replace its RGB with `(94, 134, 156)` and preserve all non-chromatic RGBA bytes exactly. Load and write with `NSBitmapImageRep`, then encode with `.png` and no lossy properties.

```swift
func recolored(_ color: NSColor) -> NSColor {
    guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }
    let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    guard (channels.max()! - channels.min()!) * 255 >= 12 else { return rgb }
    return NSColor(
        calibratedRed: 94.0 / 255.0,
        green: 134.0 / 255.0,
        blue: 156.0 / 255.0,
        alpha: rgb.alphaComponent
    )
}
```

Use SLGSync geometry for every job except `profile_chart_occupancy_standby_ipad`, which uses the standard-size SunSmart 980×467 and 1470×701 templates instead of SLGSync's historical 982×467 and 1473×701 files.

- [ ] **Step 4: Implement non-destructive output creation**

Create the seven approved `.imageset` directories under `output/lumineux-ipad-assets/`, write their two PNGs, and copy the matching `Contents.json` from the selected template resource set. Refuse to write any path containing `Lumineux/Assets-Lumineux.xcassets`.

- [ ] **Step 5: Run preflight and utility self-tests**

Run:

```bash
swift -module-cache-path /private/tmp/codex-swift-cache /private/tmp/lumineux_asset_rebuilder.swift self-test
```

Expected: `PASS preflight`, `PASS chromatic recolor`, `PASS neutral preservation`, and `PASS protected output path`.

### Task 2: Generate all approved @2x and @3x PNGs

**Files:**
- Create: the seven output `.imageset` folders listed in the file map.

**Interfaces:**
- Consumes: `recolor(job:scale:)` from Task 1 and the current SLGSync/SunSmart geometry templates.
- Produces: 14 PNGs using Lumineux core blue `#5E869C`.

- [ ] **Step 1: Run generation**

Run:

```bash
swift -module-cache-path /private/tmp/codex-swift-cache /private/tmp/lumineux_asset_rebuilder.swift generate /Users/sr/Documents/SunSmart/sun-smart
```

Expected: seven `GENERATED <imageset>` lines and `14 PNG files written`.

- [ ] **Step 2: Verify file count and resource metadata**

Run:

```bash
find output/lumineux-ipad-assets -type f -name '*.png' ! -name '*preview*' | sort
find output/lumineux-ipad-assets -type f -name 'Contents.json' | sort
```

Expected: 14 resource PNGs and seven `Contents.json` files.

### Task 3: Validate image fidelity and create preview

**Files:**
- Create: `output/lumineux-ipad-assets/verification.txt`
- Create: `output/lumineux-ipad-assets/lumineux-ipad-assets-preview.png`

**Interfaces:**
- Consumes: the 14 generated PNGs and their original geometry templates.
- Produces: `VerificationResult` entries and a labeled review sheet.

- [ ] **Step 1: Implement strict validation**

For each output/template pair, require:

```swift
output.width == expected.width
output.height == expected.height
output.hasAlpha == true
output.transparentPixelCount > 0
output.opaquePixelCount > 0
output.dominantChromaticRGB == (94, 134, 156)
output.greenTemplatePixelCount == 0
output.neutralPixelsEqualTemplate == true
output.alphaBytesEqualTemplate == true
```

Write one line per PNG to `verification.txt`, followed by `PASS 14/14`.

- [ ] **Step 2: Run verification**

Run:

```bash
swift -module-cache-path /private/tmp/codex-swift-cache /private/tmp/lumineux_asset_rebuilder.swift verify /Users/sr/Documents/SunSmart/sun-smart
```

Expected: exit 0 and final line `PASS 14/14`.

- [ ] **Step 3: Generate a labeled preview sheet**

Draw each @2x output on a dark neutral checkerboard, scale it down only for preview display, and label it with its asset name and source pixel dimensions. Save the preview at 2000 px width; this preview is not an app resource.

- [ ] **Step 4: Inspect the preview and representative originals**

Open the preview plus `auto_big@3x`, `profile_chart_occupancy_daylight_ipad@2x`, and `profile_chart_occupancy_standby_ipad@2x` at original detail. Confirm no green pixels, no opaque background, no blurred grid, and no misplaced chart/person elements.

- [ ] **Step 5: Check repository scope**

Run:

```bash
git status --short
git diff --check
```

Expected: only the implementation plan and the independent `output/lumineux-ipad-assets/` delivery appear; `Lumineux/Assets-Lumineux.xcassets` remains unchanged.
