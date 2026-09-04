# Lumineux Europe Region Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Lumineux use Europe as its only/default server region and hide region selection, matching SLGSync behavior.

**Architecture:** Reuse the existing `Lumineux` compile-time brand condition in the three shared Swift branches that own available regions, launch defaulting, and menu options. Preserve Keychain values that already exist and avoid any unrelated brand-region refactor.

**Tech Stack:** Swift 5, UIKit, xcconfig compilation conditions, Ruby configuration checks, Xcode build system

## Global Constraints

- Lumineux uses Europe where SLGSync uses North America.
- Only a missing Keychain region is defaulted; existing values are not overwritten.
- The server-selection menu entry is hidden for Lumineux.
- Other targets keep their current behavior.
- No new user-visible text is introduced.
- Existing staged and unstaged workspace changes must be preserved.

---

### Task 1: Add and prove the Lumineux region contract

**Files:**
- Modify: `SunSmart/Common/Network/NetowrkReqeustApi.swift:640-648`
- Modify: `SunSmart/AppDelegate/AppDelegate.swift:46-58`
- Modify: `SunSmart/Main/Site/View/MainMenuView.swift:24-29`
- Test: `Tests/Branding/LumineuxRuntimeTests.swift`

**Interfaces:**
- Consumes: the existing `Lumineux` Swift compilation condition and `ServerRegion`, `Keychain`, `UserData`, and `MainMenuView.Options` behavior.
- Produces: Lumineux-only Europe region availability/defaulting and a menu without `.serverSelection`.

- [x] **Step 1: Write a failing Lumineux runtime contract**

  Update the real Lumineux UIKit test to assert `ServerRegion.defaultRegions` resolves to Europe only and the rendered `MainMenuView` has two rows (`user`, `about`) without the server-selection row.

- [x] **Step 2: Run the contract before implementation**

  Generate the existing temporary Lumineux test workspace and run only `LumineuxRuntimeTests/testEuropeRegionAndMenuWithoutServerSelection` on an available x86_64 simulator.

  Expected: FAIL because the production Lumineux app currently resolves four regions and renders three menu rows.

- [x] **Step 3: Implement the minimal conditional branches**

  Add `#elseif Lumineux` returning `[.europe]` in `ServerRegion.defaultRegions`; add a corresponding AppDelegate branch that writes `.europe` only for a missing Keychain value; extend the menu exclusion condition to `Archipelago || SylSmart || SLGSync || Lumineux`.

- [x] **Step 4: Re-run the Lumineux runtime contract**

  Re-run the same isolated XCTest invocation.

  Expected: PASS for the Europe-only region and two-row menu assertions.

- [x] **Step 5: Run project-level verification**

  Run: `bundle exec ruby scripts/check_lumineux_configuration.rb`

  Expected: `PASS: Lumineux target resolves its independent configuration and resources.`

  Run: `xcodebuild -workspace SunSmart.xcworkspace -scheme Lumineux -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

  Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 6: Review scope without committing**

  Run: `git diff --check` and inspect the diff for the three shared Swift files plus the two task documents. Do not stage, commit, clean, or alter existing user changes.

## Verification Results

- RED: the focused UIKit test failed with four actual regions instead of Europe only and three actual menu rows instead of two.
- GREEN: the same focused UIKit test passed on the iOS 18 iPhone 16 simulator, 1 test with 0 failures.
- Full runtime suite: 15 of 16 tests passed. The only failure is the pre-existing `icon-manifest.json` entry at index 61 missing its required `size` field in `testSharedNameAssetsResolveAtTheirNativeGeometry`; the Europe-region and menu tests passed.
- Runtime endpoint: the site-layout test reached `https://sunsmart-eu.mericher.com`, confirming the Lumineux Europe base URL is active.
- Layout: the exported English menu screenshot was visually checked; only User settings and About remain, with no clipping, overlap, or ambiguous constraints.
- Build: the signing-disabled Lumineux Debug build for `generic/platform=iOS` completed with `** BUILD SUCCEEDED **`.
- Existing checker limitation: `LumineuxConfigurationTests.rb` still expects `lumineux_launch_logo.imageset` at the catalog root and fails after the user's pre-existing asset grouping. The task did not modify that in-progress grouping/checker work.
