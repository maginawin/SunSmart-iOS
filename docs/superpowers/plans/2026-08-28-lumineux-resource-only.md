# Lumineux Resource-only Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for the bounded correction and review. User explicitly approved implementing available assets now; missing artwork is deferred, not a blocker. Do not ask for another implementation confirmation.

**Goal:** Replace available Figma icons through Lumineux-only same-name assets, undo the previous shared-code recoloring approach, and keep only the established brand theme branch.

**Architecture:** Existing UIKit code unchanged except a Lumineux branch in the existing four theme-color definitions. Figma exports live in Lumineux, catalog ordering and shared names follow SLGSync. No runtime image helper or view/layout branches.

**Tech Stack:** Swift/UIKit, Xcode asset catalogs, CocoaPods, Ruby/xcodeproj, XCTest.

## Global Constraints

- Work in the existing Lumineux checkout; do not create worktrees/branches or stage/commit/push. Baseline HEAD d6a34baae9a2e57890bee9da21a548dc97d07deb. Prior uncommitted changes belong to this task; preserve unrelated changes if found.
- Name Lumineux, Bundle ID com.azoula.sunsmart.Lumineux, Wen Xu Team JTD3WYUC58 remain. Keep required independent config, protocols, Pods membership and existing package pins.
- Only Bar_Color, Bottom_Done_Color, Title_Done_Color and Slider_Color get Lumineux RGB(77,115,138). Restore Purple_Color and all shared consumers.
- User supplied Figma P4AaSxu8SJe2Tf2gpyTFT9 nodes9338:252618,9338:259821,9338:290273,1038:38735. Use exact exported assets, never redraw/recolor or infer missing states. Root owns Figma reads/export and the asset catalog contents.
- Use existing resource names and logical dimensions. Preserve shared SunSmart and SLGSync assets, UI constraints, callbacks and business policies. Partial asset coverage is intentional; report unmatched/missing names.
- Server/cloud identity/space defaults, SDK/Bugly and agreement wording remain untouched. Actual layout tests required; no real device commands or cloud writes.

## Task 1: Resource-only correction and regression

**Files:** Existing modified SunSmart Swift files; Config/Lumineux/Base.xcconfig; Lumineux/Lumineux-LaunchScreen.storyboard; SunSmart.xcodeproj/project.pbxproj; existing Tests/Branding and branding scripts. Root exclusively owns Lumineux/Assets-Lumineux.xcassets and DesignAssets plus final documentation.

**Interfaces:** AppIcon, AccentColor, launch_logo and launch_logo_120 use same names as the shared catalog. Independent launch storyboard may use launch_logo. New icon assets retain original existing names. Root supplies manifest of confirmed Figma mappings and dimensions. Keep the current SLGSync catalog organization pending a user decision: actual Xcode 26.6 tests load SunSmart artwork with either input order. A minimal six-case asset compiler experiment also kept the original artwork for both orders and matched folder hierarchies. Do not claim that first/last catalog wins or add runtime helpers. A Lumineux-only build-time resource merge is a proposed alternative requiring confirmation because it differs from the requested SLGSync packaging.

- [ ] Before changes, update configuration/asset tests to expect AppIcon/AccentColor/launch_logo/launch_logo_120 in the Lumineux catalog and actual target settings; run and record expected failures for prior prefixed-only setup. Keep signing/protocol assertions.
- [ ] Restore 47 shared Swift files to their baseline content, only after verifying diffs match the previous Lumineux changes. Use apply_patch, not git reset/checkout. Restore the extra Purple_Color branch in MacroDefinition.swift, retaining only the nine-line Lumineux branch for the four theme colors and customId0x00.
- [ ] Change Lumineux's asset config and independent storyboard to the shared resource names. Keep SLGSync-style resource organization until the user confirms an isolated resource-merge build step; no other target semantic changes.
- [ ] Adapt prepare_lumineux_assets.swift to package the existing two original logos with shared names and no recoloring. Do not execute it while root owns catalog; notify root to run it. Keep logical88/120 sizes and opaque1024 AppIcon.
- [ ] Replace obsolete runtime-helper test expectations with actual UIImage(named:) and native control entry checks for only root-confirmed asset mappings. Remove tests whose only purpose was the rejected runtime helper/extra per-view styling. Preserve real Welcome/menu/Sites/protocol checks and add actual tab/nav/button asset geometry/state tests based on supplied manifest. No production test hooks.
- [ ] Root exports supplied Figma nodes read-only and packages available matching images into the independent catalog. Preserve shape/padding and logical dimensions, with no shared-code modifications; ambiguous matches stay deferred. Root reports exact packaged names to implementer for tests.
- [ ] Root runs config/asset checks, real UIKit layout tests in English and zh-Hans on SE/iPhone/iPad, signed Lumineux Release and SunSmart build. Tests must validate actual same-name resolution, not just existence of source images. Other brand source/resource semantic comparison must remain unchanged.
- [ ] Task reviewer receives full final diff, mapping manifest, test evidence and strict no-extra-shared-code constraints. Resolve concrete findings, then final whole-change review. No commits; retain scratch ledger since Git history will not record this work.
- [ ] Update missing-asset inventory with provided/implemented/unmatched counts and names; mark prior broad implementation documentation as superseded.
