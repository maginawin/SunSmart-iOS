# Toast 文字与图标垂直对齐修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task in the current session. Inline execution is required; do not use subagents unless the user explicitly changes that instruction. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 `ToastStatusView` 中成功/失败图标与文字的视觉垂直中心错位，同时保持 Standard 与 Site Update 的既有尺寸和行为。

**Architecture:** 保留现有水平 `UIStackView` 作为横向布局边界。Standard 继续使用字体自然行高和 `.center`；Site Update 移除会偏移字形基线的 paragraph 强制行高，改为在显式 22 pt UILabel 区域中使用自然字体绘制，由 StackView 统一垂直居中。

**Tech Stack:** Swift、UIKit、SnapKit、Foundation-only source contract、Xcode generic iPhoneOS build。

## Global Constraints

- 修复所有实际存在错位的成功/失败 Toast，不修改图标资源。
- Standard 保持 14 pt 图标、13 pt Medium 字体、最多两行和动态高度。
- Site Update 保持 30 pt 图标容器、16 pt 图标、15 pt Light 字体和 22 pt 文字区域。
- 不使用固定 transform 或 baseline offset 魔法值。
- 不修改文案、展示位置、动画、时长、Site 更新判定或返回 Sites 时序。
- 不修改本地化、Asset Catalog、target 配置或依赖。
- 直接使用 generic iPhoneOS 构建，不使用 shell 包装、日志重定向或 Simulator。
- 保留 worktree 既有改动；不格式化或重构无关代码。
- 不执行 Git commit、push 或 merge。
- 自动 contract 和 build 不等于真机视觉验收。

---

## File Structure

### 修改

- `Tests/Site/SiteUpdateToastUIContractTests.swift`
  - 增加 Standard/Site Update 垂直居中契约，禁止 Site Update 再使用 paragraph 强制行高。
- `SunSmart/Common/View/ToastStatusView.swift`
  - Site Update 使用自然字体绘制和显式 22 pt 文字区域；Standard 保持原布局。

### 新增

- `docs/260811_1646_toast_vertical_alignment_fix_summary.md`
  - 记录 RED/GREEN、回归、四品牌构建与真机待验收边界。

---

### Task 1: 以失败契约锁定垂直居中规则

**Files:**

- Modify: `Tests/Site/SiteUpdateToastUIContractTests.swift:30-78`
- Reference: `SunSmart/Common/View/ToastStatusView.swift:83-202`

**Interfaces:**

- Consumes: `testComponent(arguments:)` 已读取的 `toast` 源码字符串和现有 `substring(in:from:through:)` helper。
- Produces: Standard 与 Site Update 两个 setup section 的独立 source contract。

- [ ] **Step 1: 分离两个外观的源码区段**

在 `testComponent(arguments:)` 读取 `toast` 后增加：

```swift
let standard = substring(
    in: toast,
    from: "private func setupStandardUI",
    through: "private func setupSiteUpdateUI"
)
let siteUpdate = substring(
    in: toast,
    from: "private func setupSiteUpdateUI",
    through: "// MARK: - Show"
)
```

- [ ] **Step 2: 增加 Standard 共同中心契约**

```swift
require(
    standard.contains("stackView.alignment = .center") &&
        standard.contains("messageLabel.text = message") &&
        !standard.contains("baselineOffset") &&
        !standard.contains("CGAffineTransform"),
    "Standard Toast must center natural-height text and icon without visual offsets"
)
```

- [ ] **Step 3: 增加 Site Update 自然字体与 22 pt 区域契约**

```swift
require(
    siteUpdate.contains("messageLabel.text = message") &&
        siteUpdate.contains("messageLabel.font = font") &&
        siteUpdate.contains("messageLabel.snp.makeConstraints") &&
        siteUpdate.contains("make.height.equalTo(22)") &&
        siteUpdate.contains("stackView.alignment = .center") &&
        !siteUpdate.contains("minimumLineHeight") &&
        !siteUpdate.contains("maximumLineHeight") &&
        !siteUpdate.contains("messageLabel.attributedText") &&
        !siteUpdate.contains("baselineOffset") &&
        !siteUpdate.contains("CGAffineTransform"),
    "Site Update Toast must center natural-height text in its 22pt text area without visual offsets"
)
```

- [ ] **Step 4: 编译并运行 component contract，确认 RED**

Run：

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
```

Expected：FAIL，错误为 Site Update 尚未使用自然字体和显式 22 pt 文字区域；Standard 契约先通过。

- [ ] **Step 5: Review checkpoint**

确认只修改 contract，生产源码尚未变化；不提交 Git。

---

### Task 2: 最小修复 Site Update 文字行盒

**Files:**

- Modify: `SunSmart/Common/View/ToastStatusView.swift:169-196`
- Test: `Tests/Site/SiteUpdateToastUIContractTests.swift`

**Interfaces:**

- Consumes: Task 1 对 `messageLabel.text`、`font`、22 pt 高度和无 paragraph 强制行高的契约。
- Produces: 保持 API 不变的 `setupSiteUpdateUI(message:type:)`。

- [ ] **Step 1: 移除 paragraph 强制行高**

删除 `NSMutableParagraphStyle`、`minimumLineHeight`、`maximumLineHeight` 和 `messageLabel.attributedText` 配置。

- [ ] **Step 2: 使用自然字体绘制**

将文字配置收敛为：

```swift
let font = UIFont.systemFont(ofSize: 15, weight: .light)
messageLabel.text = message
messageLabel.font = font
messageLabel.textColor = .white
messageLabel.textAlignment = .center
messageLabel.numberOfLines = 1
```

- [ ] **Step 3: 固定 Site Update 文字区域高度**

在 `messageLabel` 加入 StackView 后增加：

```swift
messageLabel.snp.makeConstraints { make in
    make.height.equalTo(22)
}
```

图标容器仍为 30 pt，StackView 仍为 `.center`，因此 22 pt 文字区域与图标共享中心。

- [ ] **Step 4: 运行 component contract，确认 GREEN**

Run：

```bash
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
```

Expected：`SiteUpdateToastUIContractTests passed`。

- [ ] **Step 5: 运行 routing contract**

Run：

```bash
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：`SiteUpdateToastUIContractTests passed`。

- [ ] **Step 6: Review checkpoint**

确认生产改动仅涉及 Site Update 文字布局；Standard 配置、Toast API、资源和调用点无变化。

---

### Task 3: 回归与四品牌构建

**Files:**

- Verify: `Tests/Site/SiteUpdateToastUIContractTests.swift`
- Verify: `Tests/Site/SiteTimeZoneUIContractTests.swift`
- Verify: `SunSmart/Common/View/ToastStatusView.swift`
- Create: `docs/260811_1646_toast_vertical_alignment_fix_summary.md`

**Interfaces:**

- Consumes: Task 2 的 Toast 布局结果。
- Produces: focused contract、diff 健康度、四个 target generic iPhoneOS build 和人工验收边界记录。

- [ ] **Step 1: 编译并运行 Toast 两种 contract**

Run：

```bash
swiftc -parse-as-library Tests/Site/SiteUpdateToastUIContractTests.swift -o /tmp/SiteUpdateToastUIContractTests
/tmp/SiteUpdateToastUIContractTests component SunSmart/Common/View/ToastStatusView.swift SunSmart/Assets.xcassets/Common/site_update_toast_success.imageset/Contents.json SunSmart/Assets.xcassets/Common/site_update_toast_failure.imageset/Contents.json
/tmp/SiteUpdateToastUIContractTests routing SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj
```

Expected：两次均输出 `SiteUpdateToastUIContractTests passed`。

- [ ] **Step 2: 回归 Time Zone UI contracts**

Run：

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/SiteTimeZoneUIContractTests
/tmp/SiteTimeZoneUIContractTests SunSmart/Main/Site/Controller/SiteEditViewController.swift SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift SunSmart/Main/Site/View/SiteTimeZoneSelectionCell.swift SunSmart/Main/Site/View/SiteTimeZoneSyncStatusView.swift SunSmart/Main/Site/Controller/SitesViewController.swift SunSmart/Main/Site/Controller/SiteViewController.swift
/tmp/SiteTimeZoneUIContractTests SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/all_utc_timezones.json
```

Expected：两次均输出 `SiteTimeZoneUIContractTests passed`。

- [ ] **Step 3: 检查 diff 健康度和授权边界**

Run：

```bash
git diff --check
git status --short
```

Expected：`git diff --check` 无输出；status 保留既有改动，只新增本计划授权的测试、Toast 和文档变化。

- [ ] **Step 4: 构建 SunSmart**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 5: 构建 Archipelago**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 6: 构建 SLG Sync Plus**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 7: 构建 SylSmart**

Run：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected：`BUILD SUCCEEDED`。

- [ ] **Step 8: 写入实现总结**

总结记录：根因、RED/GREEN 输出、Standard 未改动边界、四品牌构建结果、既有警告，以及成功/失败和中英文真机视觉仍待确认。

- [ ] **Step 9: Final review checkpoint**

不提交 Git；交付源码、测试、设计、计划与总结文档。
