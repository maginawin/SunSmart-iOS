# Lumineux Common Retina Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the six approved Lumineux Common 2x/3x PNG pairs as source-preserved brand overrides, with no generated 1x artwork.

**Architecture:** Keep original Retina bytes under `Lumineux/DesignAssets/Provided/Common`, copy the same bytes into six grouped `.imageset` directories, and register the final asset names in `asset-groups.json`. The existing build-time merger remains unchanged and replaces the common sets atomically by name.

**Tech Stack:** Xcode asset catalogs, Swift/CoreGraphics static tests, XCTest/UIKit runtime tests, Ruby catalog merger and validators.

## Global Constraints

- Integrate only `filter_selected`, `menu_select`, `order_down`, `order_up`, `server_select`, and `user_big`.
- Do not integrate `value_buoy` or `select_3`.
- Preserve supplied 2x/3x PNG bytes exactly; keep the universal 1x slot empty and do not generate a 1x file.
- Do not modify shared Swift behavior, layout constraints, the merger, Xcode project resources, or any non-Lumineux asset catalog.
- Preserve the current uncommitted Europe-region and other user changes; do not stage or commit overlapping files during implementation.

---

### Task 1: Establish failing source, catalog, and UIKit contracts

**Files:**
- Modify: `Tests/Branding/LumineuxAssetTests.swift`
- Modify: `Tests/Branding/LumineuxRuntimeTests.swift`

**Interfaces:**
- Consumes: the approved source-to-asset mapping and existing `assetSetURL`, `contents`, `image`, `assertResolvedImageMatchesLumineuxSource`, `show`, `descendants`, and `snapshot` helpers.
- Produces: a static byte/scale contract and a real UIKit layout/source test that fail while the six Lumineux overrides are absent.

- [ ] **Step 1: Add the six Common mappings to the static expected mapping**

Insert these entries into `expectedAssetGroups` in `LumineuxAssetTests.swift`:

```swift
"filter_selected": "Common",
"menu_select": "Common",
"order_down": "Common",
"order_up": "Common",
"server_select": "Common",
"user_big": "Common",
```

Change the mapping failure message from `approved 75-resource mapping` to `approved 81-resource mapping`.

- [ ] **Step 2: Add an exact Retina-source contract**

Add this manifest below the existing `auto` source test, but keep its logic separate because these six assets intentionally have no populated 1x entry:

```swift
let providedCommonDirectory = providedDirectory.appendingPathComponent("Common")
let providedCommonAssets: [(name: String, points: Int, hashes: [Int: String])] = [
    ("filter_selected", 30, [
        2: "7cc3af31b9f828c33d7765d96fc994843ffbca6d244474ae27326da10f3aafbb",
        3: "d49d67ea0137cd5c292ac421acbca80acb989d462e88e53a91f91ce2db33ddbb"
    ]),
    ("menu_select", 30, [
        2: "51fef836f1866e60b602ca435294a001abad681855d07e38b7ef95c7e9d29b05",
        3: "6b6e29ab8be3581095143edc8395bf065ffc88308edf532f271501e2f11d9bc3"
    ]),
    ("order_down", 30, [
        2: "cf7cff430c9ff3bd08ef60e461a740fc43d0d460ee3e1098acb17f0a1ce08d98",
        3: "a381f2c1266f7fa7fff2c0f60b5083f4d89accc43fe59c7b818e9640d14bb492"
    ]),
    ("order_up", 30, [
        2: "5eef3c88c7cbf77f8d472b2256efb2b5791af8224fd8407c762e46ae5cf1eede",
        3: "ddaeb1db793212aebaf7b1f28af29afc0f9531f60e2e8749ced29ac147c7443f"
    ]),
    ("server_select", 30, [
        2: "b17653195109f25d9ec08df9454a6976e314f1c50055c8c1c5d6b7cccd49c61b",
        3: "067222632c85ea3c9f3e35f9a046c280844015fc48e96b0c3dddb5333e6f216a"
    ]),
    ("user_big", 88, [
        2: "6c7d79fe8c5757fbdf067820f2c810a7792325b040ec7cef5beb7372b5bbd0f7",
        3: "c0063e0e178986fd318c08bfd3de7af92e4298233e197c3f467005f8606b159b"
    ])
]
```

For every entry, assert all of the following:

```swift
let entries = try contents(named: asset.name)["images"] as! [[String: String]]
check(entries.count == 3, "Expected empty 1x plus supplied 2x/3x for \(asset.name)")
check(entries.first { $0["scale"] == "1x" }?["filename"] == nil,
      "\(asset.name) must not generate a 1x file")
for scale in 2...3 {
    let source = providedCommonDirectory.appendingPathComponent("\(asset.name)@\(scale)x.png")
    let sourceData = try Data(contentsOf: source)
    let digest = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
    check(digest == asset.hashes[scale], "Supplied \(asset.name) @\(scale)x bytes changed")
    let filename = entries.first { $0["scale"] == "\(scale)x" }?["filename"]
    check(filename == "\(asset.name)@\(scale)x.png", "Unexpected filename for \(asset.name)")
    let catalogData = try Data(contentsOf: assetSetURL(named: asset.name).appendingPathComponent(filename!))
    check(catalogData == sourceData, "Catalog must preserve \(asset.name) @\(scale)x bytes")
    let pixels = try image(named: asset.name, filename: filename!)
    check(pixels.width == asset.points * scale && pixels.height == asset.points * scale,
          "Incorrect logical canvas for \(asset.name) @\(scale)x")
}
```

- [ ] **Step 3: Add a real UIKit source and layout test**

Add `testProvidedCommonRetinaAssetsFitProductionControls()` to `LumineuxRuntimeTests.swift`. The test must:

```swift
for name in ["filter_selected", "menu_select", "order_down", "order_up", "server_select", "user_big"] {
    try assertResolvedImageMatchesLumineuxSource(UIImage(named: name), name: name)
}

let user = UserSettingsViewController()
show(NavigationViewController(rootViewController: user))
let userIcon = try XCTUnwrap(descendants(user.view).compactMap { $0 as? UIImageView }
    .first { $0.image?.size == CGSize(width: 88, height: 88) })
try assertResolvedImageMatchesLumineuxSource(userIcon.image, name: "user_big")
XCTAssertFalse(userIcon.hasAmbiguousLayout)
snapshot(window, "Provided-common-user")

let server = ServerSelectionViewController()
show(NavigationViewController(rootViewController: server))
let serverCell = try XCTUnwrap(descendants(server.view).compactMap { $0 as? ServerSelectionViewCell }.first)
try assertResolvedImageMatchesLumineuxSource(serverCell.selectedImageView.image, name: "server_select")
XCTAssertFalse(serverCell.selectedImageView.hasAmbiguousLayout)
snapshot(window, "Provided-common-server")

let space = SpaceData(name: "Common asset layout", id: "common-asset-space",
                      siteId: "common-asset-site", create: 0, isFavourite: false,
                      permission: .owner, sourceType: .create,
                      meshUUID: "common-asset-mesh", meshNetworkId: "common-asset-network")
let energy = EnergyStaticDataViewController(space: space)
show(NavigationViewController(rootViewController: energy))
let buttons = descendants(energy.view).compactMap { $0 as? UIButton }
let filter = try XCTUnwrap(buttons.first { image($0.image(for: .selected), matchesNamed: "filter_selected") })
let order = try XCTUnwrap(buttons.first {
    image($0.image(for: .normal), matchesNamed: "order_down") &&
    image($0.image(for: .selected), matchesNamed: "order_up")
})
try assertResolvedImageMatchesLumineuxSource(filter.image(for: .selected), name: "filter_selected")
try assertResolvedImageMatchesLumineuxSource(order.image(for: .normal), name: "order_down")
try assertResolvedImageMatchesLumineuxSource(order.image(for: .selected), name: "order_up")
XCTAssertFalse(filter.hasAmbiguousLayout)
XCTAssertFalse(order.hasAmbiguousLayout)
snapshot(window, "Provided-common-energy-controls")
```

Use `TitleSelectView.show(...)`, find the tag-100 overlay in `window`, lay it out, and assert its selected cell image matches `menu_select`; take a `Provided-common-title-select` snapshot. Do not change application persistence, server selection, account data, or Mesh state.

- [ ] **Step 4: Run the static test and verify RED**

Run:

```sh
swift Tests/Branding/LumineuxAssetTests.swift
```

Expected: FAIL because the approved 81-resource mapping and six source/catalog sets do not exist yet. The failure must not be a Swift syntax or environment error.

- [ ] **Step 5: Run the focused UIKit test and verify RED**

Run the existing temporary branding workspace command from `Tests/Branding/README.md`, adding:

```sh
-only-testing:LumineuxBrandingTests/LumineuxRuntimeTests/testProvidedCommonRetinaAssetsFitProductionControls
```

Expected: FAIL because the independently compiled Lumineux reference catalog cannot resolve at least one of the six new names. Record the result bundle under a new `/private/tmp/lumineux-common-retina.*` directory.

---

### Task 2: Add the approved 2x/3x sources and grouped image sets

**Files:**
- Create: `Lumineux/DesignAssets/Provided/Common/{filter_selected,menu_select,order_down,order_up,server_select,user_big}@{2,3}x.png`
- Create: `Lumineux/Assets-Lumineux.xcassets/Common/{filter_selected,menu_select,order_down,order_up,server_select,user_big}.imageset/Contents.json`
- Create: the matching 12 catalog PNG files inside those image sets
- Modify: `Lumineux/DesignAssets/asset-groups.json`

**Interfaces:**
- Consumes: the exact source mapping and hashes locked by Task 1.
- Produces: six complete Lumineux brand override sets with empty 1x slots, discoverable by the existing merger and validators.

- [ ] **Step 1: Copy and rename the source bytes**

Create `Lumineux/DesignAssets/Provided/Common` and copy only the approved pairs:

```text
Property 1=filter       -> filter_selected
images/select           -> menu_select
Property 1=order_down   -> order_down
Property 1=order_up     -> order_up
images/select_2         -> server_select
images/user             -> user_big
```

Use binary copies; do not process the PNGs. Do not copy `images/select_3`.

- [ ] **Step 2: Create six two-scale image sets**

For each asset name, copy the renamed 2x/3x source bytes into its Common image set and add this exact `Contents.json` shape:

```json
{
  "images" : [
    {
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "ASSET_NAME@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "ASSET_NAME@3x.png",
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

Replace only `ASSET_NAME`; never add an `@1x.png` file or a 1x filename.

- [ ] **Step 3: Register the six Common mappings**

Add the six mappings from Task 1 to `Lumineux/DesignAssets/asset-groups.json`, keeping the existing alphabetical/group organization and all current mappings unchanged.

- [ ] **Step 4: Run GREEN static and catalog tests**

Run:

```sh
swift Tests/Branding/LumineuxAssetTests.swift
ruby scripts/validate_lumineux_asset_groups.rb \
  Lumineux/Assets-Lumineux.xcassets \
  Lumineux/DesignAssets/asset-groups.json
ruby Tests/Branding/LumineuxGeneratorTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxConfigurationTests.rb
```

Expected: all commands exit 0; the catalog reports 81 asset sets total, including 79 imagesets, one AppIcon, and one AccentColor.

- [ ] **Step 5: Run the focused UIKit test and verify GREEN**

Recreate the temporary test workspace after adding the assets, then run the focused test from Task 1. Expected: PASS on iPhone and iPad representative simulators, with no ambiguous layout assertion and four retained screenshots.

- [ ] **Step 6: Inspect the implementation checkpoint without committing**

Run:

```sh
git status --short
git diff --check
git diff -- Lumineux/DesignAssets/asset-groups.json \
  Tests/Branding/LumineuxAssetTests.swift \
  Tests/Branding/LumineuxRuntimeTests.swift
```

Confirm no shared/non-Lumineux catalog, merger, generator, Xcode project, or `select_3` file changed. Do not stage or commit because `LumineuxRuntimeTests.swift` already contains unrelated user work.

---

### Task 3: Update inventory and complete layout/build verification

**Files:**
- Modify: `docs/lumineux-missing-assets.md`
- Modify: `Tests/Branding/README.md`

**Interfaces:**
- Consumes: the verified 81-set Lumineux catalog and retained UIKit screenshots.
- Produces: current inventory counts and reproducible verification evidence without overstating device acceptance.

- [ ] **Step 1: Update the missing-resource inventory**

In `docs/lumineux-missing-assets.md`:

- Record the six supplied Common resources and their final source mappings.
- Change coverage inside the 94-resource brand scope from 37 to 43.
- Change remaining pending resources from 57 to 51.
- Change provided resource total from 70 to 76.
- Change Common pending count from 7 to 1 and leave only `value_buoy` in that section.
- Leave every other category and pending name unchanged.

- [ ] **Step 2: Update the branding verification README**

In `Tests/Branding/README.md`:

- Change the catalog summary from 73 to 79 imagesets and from 75 to 81 total sets.
- Change the supplied-icon summary from 66 to 72, specifying 65 Figma assets plus 7 user-supplied Retina PNG assets.
- Document that these six Common sets intentionally contain an empty 1x slot and exact 2x/3x bytes.
- Add the new static and UIKit verification evidence after fresh commands finish.
- Change the pending total from 57 to 51.

- [ ] **Step 3: Run the complete English and Simplified Chinese UIKit matrix**

Use the exact workspace-generation and `xcodebuild` commands in `Tests/Branding/README.md` for iPhone SE 3, iPhone 16, and iPad Pro 11 M4. Run English first, then `test-without-building` for `zh-Hans`/`CN`. Export attachments and manually inspect the new screenshots for correct artwork, clipping, overlap, logical size, and ambiguous constraints.

Expected: all non-negative tests pass; new Common screenshots show the Lumineux blue artwork and remain within their production controls. Record expected-failure negative controls separately from actual failures.

- [ ] **Step 4: Run full static regression and dependency checks**

Run:

```sh
export LUMINEUX_SOURCE_PACKAGES_DIR=/Users/sr/Library/Developer/Xcode/DerivedData3/SunSmart-gzeywntloehznchfwsjhwyxxsoot/SourcePackages
ruby Tests/Branding/LumineuxConfigurationTests.rb
ruby Tests/Branding/LumineuxMergeTests.rb
ruby Tests/Branding/LumineuxGeneratorTests.rb
swift Tests/Branding/LumineuxAssetTests.swift
bash scripts/check_nordic_sdk_dependency.sh
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 5: Build Lumineux and verify the merged artifact**

Build the `Lumineux` scheme from `SunSmart.xcworkspace` using a new isolated directory under `/Users/sr/Library/Developer/Xcode/DerivedData3`, normal signing settings, `generic/platform=iOS`, and no `-allowProvisioningUpdates`. Verify:

- build exits 0;
- `codesign --verify --deep --strict` exits 0;
- the generated merged catalog contains 695 total sets, with 81 matching Lumineux and 614 retaining public resources;
- all six new 2x/3x sets match the source hashes;
- no 1x PNG exists for the six new sets;
- no duplicate asset warning appears.

Do not install or launch the app on a real device.

- [ ] **Step 6: Final scope audit**

Run:

```sh
git status --short
git diff --check
git diff --name-only
```

Confirm the diff is limited to the approved Lumineux source/catalog files, group manifest, branding tests, and two inventory documents, while all pre-existing Europe-region changes remain present and unaltered. Leave implementation changes uncommitted for user review.
