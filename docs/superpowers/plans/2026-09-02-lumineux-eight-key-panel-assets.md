# Lumineux Eight-Key Panel Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Lumineux-only 2x/3x overrides for the Scene and Brightness eight-key panel preview images without changing shared SunSmart assets or production Swift.

**Architecture:** Add two same-named image sets to the Lumineux source catalog under the shared business group name `EightKeySwitches1.5`. The existing Lumineux build-time merger will replace the matching common image sets by asset name, while other targets continue using the common catalog.

**Tech Stack:** Xcode Asset Catalog, JSON asset metadata, Swift static resource contract, Ruby temporary test-workspace generator.

## Global Constraints

- Use only the four supplied 2x/3x PNG files; do not generate or populate 1x images.
- Preserve the supplied PNG bytes without resizing, re-encoding, recoloring, or redrawing.
- Do not modify `SunSmart/Assets.xcassets`, production Swift, other brand catalogs, dependencies, or Xcode target configuration.
- Preserve all existing unrelated working-tree changes.
- Do not stage, commit, or push Git changes.
- Per user instruction, do not run tests, builds, simulators, or device validation; the user will perform final real-device validation.

---

### Task 1: Extend the Lumineux resource contract

**Files:**
- Modify: `Tests/Branding/LumineuxAssetTests.swift`
- Modify: `scripts/make_lumineux_test_workspace.rb`

**Interfaces:**
- Consumes: `AssetGroupManifest`, `ProvidedGroupedAsset`, and the existing `providedDirectory` source-oracle convention.
- Produces: a 131-set Lumineux catalog contract containing `Scene Panel (8 key)` and `Brightness Panel (8 key)` in `EightKeySwitches1.5`.

- [x] **Step 1: Register the new business group and asset names in the static contract**

Add `EightKeySwitches1.5` to `expectedGroups`, and add these mappings to `expectedAssetGroups`:

```swift
"Brightness Panel (8 key)": "EightKeySwitches1.5",
"Scene Panel (8 key)": "EightKeySwitches1.5",
```

Change the exact discovered catalog count from 129 to 131.

- [x] **Step 2: Add exact supplied-PNG contracts**

Add a two-entry `providedEightKeyPanelAssets` array using the existing `ProvidedGroupedAsset` structure:

```swift
let providedEightKeyPanelAssets: [ProvidedGroupedAsset] = [
    .init(group: "EightKeySwitches1.5", name: "Brightness Panel (8 key)", pixels: [
        2: (686, 640), 3: (1029, 960)
    ], hashes: [
        2: "6bfbdaa3ed5b078963224e97949d103cd77eef2521c9dbb844ae08c1421335b6",
        3: "85ac4b8145bac7601a15e551aa060b71341ac2348ef81414442170b76a5297eb"
    ]),
    .init(group: "EightKeySwitches1.5", name: "Scene Panel (8 key)", pixels: [
        2: (686, 640), 3: (1029, 960)
    ], hashes: [
        2: "6335ec2c238c8ddbb3d75c1e2ae23a58d88e9d0dcb1eeea9817bcac5b73befda",
        3: "2283d349c95df775d59ebbfbd8dd1cee7dc09b00f85a00ec1ba8e43d7e5d824a"
    ])
]
```

Assert that the array contains exactly two assets, include it in the existing supplied-assets byte/size loop, and update the final informational print to 131 asset groups.

- [x] **Step 3: Keep temporary test-workspace metadata consistent**

Change `scripts/make_lumineux_test_workspace.rb` so its complete Lumineux reference catalog guard expects 131 sets instead of 129. Do not run the generator.

### Task 2: Add the Lumineux source and catalog images

**Files:**
- Create: `Lumineux/DesignAssets/Provided/EightKeySwitches1.5/Brightness Panel (8 key)@2x.png`
- Create: `Lumineux/DesignAssets/Provided/EightKeySwitches1.5/Brightness Panel (8 key)@3x.png`
- Create: `Lumineux/DesignAssets/Provided/EightKeySwitches1.5/Scene Panel (8 key)@2x.png`
- Create: `Lumineux/DesignAssets/Provided/EightKeySwitches1.5/Scene Panel (8 key)@3x.png`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Brightness Panel (8 key).imageset/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Brightness Panel (8 key).imageset/Brightness Panel (8 key)@2x.png`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Brightness Panel (8 key).imageset/Brightness Panel (8 key)@3x.png`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Scene Panel (8 key).imageset/Contents.json`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Scene Panel (8 key).imageset/Scene Panel (8 key)@2x.png`
- Create: `Lumineux/Assets-Lumineux.xcassets/EightKeySwitches1.5/Scene Panel (8 key).imageset/Scene Panel (8 key)@3x.png`
- Modify: `Lumineux/DesignAssets/asset-groups.json`

**Interfaces:**
- Consumes: the four user-supplied PNGs and `LumineuxAssetMerger.apply_brand_sets` name-based override behavior.
- Produces: two Lumineux image sets resolved by the existing `UIImage(named: "Scene Panel (8 key)")` and `UIImage(named: "Brightness Panel (8 key)")` calls.

- [x] **Step 1: Preserve the supplied source artwork**

Copy the four inputs byte-for-byte into `Lumineux/DesignAssets/Provided/EightKeySwitches1.5`, renaming `8 keys2` to `Scene Panel (8 key)` and `8 keys` to `Brightness Panel (8 key)` while retaining the `@2x`/`@3x` suffixes.

- [x] **Step 2: Create the two Retina-only image sets**

Create an unnamespaced group `Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Each imageset must use this three-slot structure, substituting its exact asset name:

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

Copy the corresponding preserved source PNGs into each imageset without transforming them.

- [x] **Step 3: Register the group and assets in the design manifest**

Add `EightKeySwitches1.5` to the ordered `groups` array and add:

```json
"Brightness Panel (8 key)": "EightKeySwitches1.5",
"Scene Panel (8 key)": "EightKeySwitches1.5"
```

to `assets`.

### Task 3: Hand off for user verification

**Files:**
- Inspect only the exact paths created or modified by Tasks 1 and 2.

**Interfaces:**
- Consumes: completed file changes.
- Produces: a concise inventory for user-run real-device testing.

- [x] **Step 1: Report implementation scope without executing validation**

List the two Lumineux image sets, their input mapping, and the resource-contract/configuration files changed. Explicitly state that tests, builds, simulators, and real-device validation were not run at the user's request.
