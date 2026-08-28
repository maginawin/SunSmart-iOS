# Lumineux Asset Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Lumineux use deterministic same-name brand resources without editing shared application code or other targets.

**Architecture:** Generate a single complete catalog from common resources plus complete Lumineux asset-set overrides under `DERIVED_FILE_DIR`. A Lumineux-only build phase generates it, and the native Xcode asset compiler consumes only that catalog. Test scripts and the existing temporary UIKit harness validate the full path.

**2026-08-28 sandbox correction:** Normal Library-based DerivedData reproduces denied recursive output writes in both the merger and CocoaPods framework embedding. Keep the merger/output path unchanged and set `ENABLE_USER_SCRIPT_SANDBOXING=NO` only on Lumineux Debug/Release. Verify the full device build in Library, not just a `/tmp` probe; see `Tests/Branding/README.md`.

**Tech Stack:** Ruby standard library, existing xcodeproj development tooling, Xcode 26.6, UIKit/XCTest, iOS 15.0 minimum.

## Global Constraints

- Work in the existing Lumineux checkout. Do not stage, commit, push, switch branches, create worktrees, or discard any pre-existing edits.
- Do not edit shared SunSmart Swift/Objective-C, shared source assets, SLGSync/Archipelago/SylSmart resources, or any other target's build configuration/phases.
- Keep app name `Lumineux`, Bundle ID `com.azoula.sunsmart.Lumineux`, Team `JTD3WYUC58`, and the existing four theme colors `#4d738a` unchanged.
- Keep all asset names, supplied artwork, independent protocols, signing, entitlements, dependencies and SDK pins unchanged. Server/cloud/default-space settings and protocol wording remain deferred.
- New generated catalogs exist only in the build directory, not as a complete checked-in resource copy. Missing Lumineux artwork uses the common catalog.
- UI completion requires actual UIKit layout tests and screenshot inspection, not compilation or source checks alone. Never weaken a source oracle merely to make a mismatch pass.
- No new user-visible app text is needed. Existing English and Simplified Chinese behavior must be preserved.

---

### Task 1: Safe whole-set catalog merge

**Files:**
- Create: `Lumineux/Scripts/merge_assets.rb`
- Create: `Tests/Branding/LumineuxMergeTests.rb`

**Interfaces:**
- Consumes source catalog directories and one output path with basename `Assets-Lumineux-Merged.xcassets`.
- Produces `LumineuxAssetMerger.merge(common:, brand:, output:)` and a CLI accepting exactly three positional arguments in that order. Requiring the Ruby file must not execute the CLI.
- CLI uses Ruby standard library only, returns nonzero with a useful error on invalid input, and prints a concise success summary.

Task-specific constraints are the Global Constraints above. This task owns only its two files plus its report.

- [x] Write failing real-filesystem Minitest tests first. Hand-authored fixtures must put common `Common/logo.imageset` and brand root `logo.imageset` in different folders, include an obsolete common @3x file, and assert the final single logo set contains exactly the brand files and JSON, while an unrelated common set remains byte-identical. Example contract:

```ruby
LumineuxAssetMerger.merge(common: common, brand: brand, output: output)
matches = Dir.glob(File.join(output, '**/logo.imageset'))
assert_equal 1, matches.size
assert_equal 'brand pixels', File.binread(File.join(matches.first, 'logo@2x.png'))
refute File.exist?(File.join(matches.first, 'old@3x.png'))
```

- [x] Run `ruby Tests/Branding/LumineuxMergeTests.rb` before implementation, recording the expected failure for the missing merger rather than an unrelated fixture error.
- [x] Implement only the merger contract. Index supported asset sets by name, reject duplicate names within each input, and reject mismatched asset types. Preserve common hierarchy and metadata; replace entire sets at the common relative path and add new brand sets once. Explicitly support `.imageset`, `.colorset`, `.appiconset`; if namespace metadata is not supported, reject `provides-namespace: true` with an actionable error. Validate inputs before replacing a previous valid output.
- [x] Guard output operations against source paths, their ancestors/descendants, broad paths, wrong basename, and symlink redirection. Do not follow source symlinks. Only remove previous generated content after establishing ownership/scope; avoid deleting arbitrary existing directories. Rebuild from current inputs so deleted overrides revert to common and removed brand-only items disappear.
- [x] Add and run focused tests for brand-only assets, AppIcon/AccentColor, deleted/changed overrides on the second run, source immutability, duplicate names, malformed/missing JSON, incompatible types, invalid paths and symlinks. Use actual files/CLI results, not assertions about source text.
- [x] Run the full merger test file and `ruby -c Lumineux/Scripts/merge_assets.rb`; record RED/GREEN evidence and self-review. Do not commit.

### Task 2: Lumineux-only native Xcode integration and actual resource verification

**Files:**
- Modify: `SunSmart.xcodeproj/project.pbxproj` (Lumineux resource/build references only)
- Modify: `scripts/check_lumineux_configuration.rb`
- Modify if needed: `Tests/Branding/LumineuxRuntimeTests.swift`, `scripts/make_lumineux_test_workspace.rb`
- Modify: `Tests/Branding/README.md`, `docs/lumineux-missing-assets.md`
- Use unchanged: `Tests/Branding/LumineuxAssetTests.swift`, `Tests/Branding/LumineuxConfigurationTests.rb`

**Interfaces:**
- Consumes Task 1 CLI: `ruby Lumineux/Scripts/merge_assets.rb COMMON BRAND OUTPUT`.
- Produces generated `$(DERIVED_FILE_DIR)/LumineuxAssets/Assets-Lumineux-Merged.xcassets` and native Resources reference with source tree `DERIVED_FILE_DIR`, path `LumineuxAssets/Assets-Lumineux-Merged.xcassets`.
- Native Xcode asset compiler still generates AppIcon files, partial Info.plist and Assets.car. A fresh standalone probe has verified that a generated catalog can be referenced this way on the current Xcode.

Task-specific constraints are the Global Constraints above. This task must not edit the merger without coordinating a test-backed finding from Task 1.

- [x] Update configuration tests first so the current two-catalog Lumineux build fails: Resources must contain the generated reference instead of either original catalog; the merge build phase must declare its source inputs and generated output and precede resource compilation. Evaluate PBX objects/effective settings, not literal source lines.
- [x] Add the Lumineux-only merge phase. Script body invokes the merger with quoted build variables:

```sh
set -eu
/usr/bin/ruby "${SRCROOT}/Lumineux/Scripts/merge_assets.rb" \
  "${SRCROOT}/SunSmart/Assets.xcassets" \
  "${SRCROOT}/Lumineux/Assets-Lumineux.xcassets" \
  "${DERIVED_FILE_DIR}/LumineuxAssets/Assets-Lumineux-Merged.xcassets"
```

- [x] Declare inputs for the script and two catalogs, and output for the dedicated generated directory/catalog. Run the phase on every build to catch nested modifications/additions/removals. Keep script sandboxing enabled if supported by declared directory permissions; do not change global project settings. Add only the generated catalog to Lumineux Resources, retaining the original file references and other targets. Do not manually generate AppIcon metadata or modify signing.
- [x] Run configuration and merger tests. Use a new temporary XCTest workspace and entirely new DerivedData with the existing locked SourcePackages cache, package updates disabled, x86_64 iOS 18 simulator (Bugly's existing arm64 slice is device-only). Start with one SE test run to locate any failures, then run the full English/Simplified Chinese three-device matrix.
- [x] If correct merged images differ from raw source PNG solely because of compiler color/premultiplication, make the oracle an independently compiled, Lumineux-only reference catalog in the test bundle. Keep exact decoded pixel comparison, validate the reference source itself, and run a negative control against the shared-only catalog so a wrong image still fails. Never compare the same main-bundle lookup to itself or add production hooks.
- [x] Verify initial build, subsequent build and source add/remove behavior; ensure the effective actool command has one merged catalog and no duplicate-name warnings. Verify all 54 supplied icon sets and both logos, AppIcon/AccentColor metadata, native navigation and existing UIKit layout/interaction tests. Inspect screenshots.
- [x] Build SunSmart Debug for regression and Lumineux Release for a generic device using the user's existing signature without provisioning updates; verify signing and Info.plist/AppIcon metadata. No real device operations or SDK changes.
- [x] Update README and missing-resource list with actual evidence, leaving 69 missing artwork groups and deferred product decisions explicit. Do not claim success for unrun or failing checks. Do not commit.
