# Lumineux Branding Implementation Plan

> SUPERSEDED / 历史计划：用户已明确改为 SLGSync 同名资源方案。以下前缀资源、运行时图片处理、额外控件改色和旧 102 次测试不再代表当前工作区。请执行 `docs/superpowers/plans/2026-08-28-lumineux-resource-only.md`，不要重新应用本计划的 Task 2。

> **For agentic workers:** Use superpowers:subagent-driven-development for the two implementation tasks and task-scoped review. User-approved design: `docs/superpowers/specs/2026-08-28-lumineux-branding-design.md`.

**Goal:** 接入独立 Lumineux target 品牌配置、真实 Logo 和蓝色主题，保持其他品牌和未确认的业务策略不变。

**Architecture:** UIKit/SnapKit 共享业务代码；独立 xcconfig、plist、entitlements、Asset Catalog 和协议资源；仅 Lumineux 的主题与品牌图片分支改变表现。

**Tech Stack:** Swift 5、UIKit、SnapKit、CocoaPods、Swift Package、Xcode 26.6、Ruby/xcodeproj、iOS Simulator。

**Status (2026-08-28):** 本轮实现和限定范围复核完成。17 项实际 UIKit 测试在 3 种设备、2 种语言下合计 102 次通过；五个品牌构建通过，Lumineux Release 保留 Wen Xu 签名。未进行真机安装/启动；共享插图、部分提示图标/转圈配色及其他明确排除项见设计文档。保持当前分支和所有未提交改动。

## Global Constraints

- 工作目录 `/Users/sr/Documents/SunSmart/sun-smart`，当前分支 `Lumineux`；原位完成，不创建分支、不提交、不推送、不切换工作树。
- App 名称 `Lumineux`，Bundle ID `com.azoula.sunsmart.Lumineux`，Team `JTD3WYUC58` 保留。
- 主色、按钮色、滑块色 `#4D738A` = RGB `(77,115,138)`。
- 不修改服务器、请求头 appKey/appSecret、服务器选择入口、空间默认值、Bugly 或 SDK 源码。
- 两份 Lumineux 协议保持与 SLGSync 原件逐字节相同；文本替换和翻译排除。
- 保留其他品牌资源和运行行为。新增可见文案必须 English + 简体中文。
- 必须有真实 UIKit 布局验证；静态检查和编译成功不能代替。
- 本计划中的 Git review 以工作区 diff 为依据；所有提交步骤由上述不提交约束取代。

## Task 1: 独立工程配置和资源归属

**Files:**
- Create `Config/Lumineux/{Base,Debug,Release}.xcconfig`。
- Create `Lumineux/Lumineux-Info.plist`、`Lumineux/Lumineux.entitlements`、`Lumineux/{en,zh-Hans}.lproj/InfoPlist.strings`。
- Create `Lumineux/Lumineux-LaunchScreen.storyboard`。
- Modify `SunSmart.xcodeproj/project.pbxproj`、`Podfile`、生成的 Podfile.lock（仅必要校验和）。
- Tests under `Tests/Branding` and `scripts/check_lumineux_configuration.rb`。
- Controller supplies `Lumineux/Assets-Lumineux.xcassets` during this task; do not overwrite these asset files.

**Interfaces:** Asset names `LumineuxAppIcon`, `LumineuxAccentColor`, `lumineux_launch_logo`, `lumineux_launch_logo_120`. Theme implementation consumes the `Lumineux` Swift compile condition. Existing shared Localizable.strings retained; InfoPlist.strings is target-specific.

- [x] Add configuration test(s) first. Resolve the actual Xcode target/configuration/resource relationships, not source-line greps. The regression caught is an app whose built display name, identity or resources belong to SunSmart despite selecting Lumineux. Record expected RED against the current target.
- [x] Base includes Common/AppBase and declares the following values; remove conflicting Lumineux target-level overrides so the intended values are effective:

```xcconfig
#include "../Common/AppBase.xcconfig"
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = JTD3WYUC58
CURRENT_PROJECT_VERSION = 1
MARKETING_VERSION = 1.0.0
PRODUCT_BUNDLE_IDENTIFIER = com.azoula.sunsmart.Lumineux
INFOPLIST_FILE = Lumineux/Lumineux-Info.plist
INFOPLIST_KEY_CFBundleDisplayName = Lumineux
INFOPLIST_KEY_UILaunchStoryboardName = Lumineux-LaunchScreen
ASSETCATALOG_COMPILER_APPICON_NAME = LumineuxAppIcon
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = LumineuxAccentColor
CODE_SIGN_ENTITLEMENTS = Lumineux/Lumineux.entitlements
```

- [x] Debug includes its own Pods debug xcconfig then Base, sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG Lumineux`; Release uses release Pods and `Lumineux`.
- [x] Preserve Bluetooth central/peripheral background modes, UIDesignRequiresCompatibility, and Wi-Fi entitlement. Localize location, Bluetooth, camera and photo-library permission descriptions in English and zh-Hans; identify this app as Lumineux in location text.
- [x] LaunchScreen uses `lumineux_launch_logo` with aspect-fit and explicit 88 × 88 centered constraints, retaining the existing vertical center offset 25. Do not edit SLGSync storyboard.
- [x] Lumineux Resources contains its new catalog, launch screen, localized InfoPlist.strings and its two copied HTML files, plus existing common assets/Localizable. Remove only its references to SunSmart launch screen, shared InfoPlist.strings and SunSmart protocol resources. Replace the copied Info.plist file reference with a repository-relative reference; do not delete the original root file.
- [x] Add `target 'Lumineux'` under Common in Podfile; run `pod install --no-repo-update` using existing dependencies. Ensure framework and embed scripts use Lumineux Pods; no redundant SunSmart Pods framework links remain on Lumineux.
- [x] Reuse the existing registered NordicSigMeshSDK release package reference for Lumineux; remove only its duplicate orphan remote reference if needed. Update the existing SDK dependency checker for all five app targets where needed, without touching SDK source or pin revisions.
- [x] Run configuration checks GREEN, plist lint, actual Debug and Release build settings; record evidence. Report all changed paths for review. Do not commit.

## Task 2: 品牌颜色、Logo 入口和界面表现

**Files:**
- Modify `SunSmart/Common/Macro/MacroDefinition.swift` and focused UIImage/UIButton helpers if needed.
- Modify `SunSmart/Main/Base/WelcomeViewController.swift`, `SunSmart/Main/Site/View/MainMenuView.swift` and only brand-color consumers required by the approved scope.
- Add relevant real UIKit tests in `Tests/Branding`; controller runs them in a temporary test harness when full app hosting is needed.
- No project, Pods, policy or network edits in this task.

**Interfaces:** Assets and flag are supplied by Task 1; use `lumineux_launch_logo` and `lumineux_launch_logo_120` only for Lumineux and existing names for all other builds. Existing layout and business interactions remain.

- [x] Write a behavior test first for actual themed controls/image loading. Expected RED: a Lumineux-built selected segment/action/slider is still purple or orange, or uses SunSmart logo. Do not add text-matching tests as the sole evidence.
- [x] Add the brand branch with exact values:

```swift
#elseif Lumineux
let Bar_Color = RGB(77, 115, 138)
let Bottom_Done_Color = RGB(77, 115, 138)
let Title_Done_Color = RGB(77, 115, 138)
let Slider_Color = RGB(77, 115, 138)
let customId: UInt8 = 0x00
```

- [x] Wire the two in-app Logo readers conditionally. Welcome image has explicit logical 120 × 120 size and aspect-fit for Lumineux so high-resolution input does not expand the layout. Menu retains the existing SCRYFrom(88) square geometry and preserves aspect ratio.
- [x] Check remaining `RGB(102,103,171)` and `Purple_Color` consumers for brand usage. Route brand presentation through a Lumineux-aware value that returns the exact previous purple for all non-Lumineux builds. Preserve semantic colors, fade percentages and control callbacks.
- [x] Handle brand-colored icons without swizzling UIImage or blindly tinting multicolor charts/illustrations. Prefer exact assets or a focused helper for verified monochrome images; preserve non-brand colors and image geometry. Cover Sites selected favourite/add, selection indicators, scanning and relevant control state imagery. If an image needs bespoke artwork beyond the supplied design, report the concrete remaining asset instead of pretending a blanket tint is equivalent.
- [x] Sites uses its existing cell/segmented control and data path; no sample sites or unrelated layout redesign. Scope auxiliary color changes to Lumineux only where required to align the supplied reference.
- [x] Run focused tests GREEN and document non-Lumineux preservation and remaining image limitations for review. Do not commit.

## Task 3: 集成、实际布局与交付验证

**Files:** `Tests/Branding` runtime layout tests/harness; `scripts` runner if useful; implementation summary under `docs`. Temporary generated Xcode test project, build products and screenshots stay in this plan's ignored workspace or `/private/tmp`.

- [x] Build Lumineux Debug and Release against the existing cached SDK; do not update Package.resolved. Build other four app schemes to check shared Swift changes.
- [x] Use a temporary XCTest host/harness to exercise real production UIKit views and inspect geometry, resource resolution, colors and snapshots. Test iPhone SE, a regular iPhone and iPad, English and zh-Hans. Keep test-only plumbing out of production AppDelegate.
- [x] Verify launch/Welcome/menu/Sites, primary buttons, disabled/selected states and sliders; check ambiguous/unsatisfiable constraints and overlapping content. Capture PNG evidence and inspect it.
- [x] Verify both protocol entry points resolve the copied Lumineux HTML files; confirm byte equality with SLG originals and preserve deferred content status.
- [x] Check signing settings without changing the account. Signed generic-iOS Release build and signature integrity passed; actual device installation, launch and hardware verification were not performed and are not reported as passed.
- [x] Run task reviews plus a final review, resolve concrete findings, and update spec status/summary with implemented scope, exact verification commands/results and any environment limits. No commit or push.
