# Site Review sync 空态触摸修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 本项目按 AGENTS.md 使用 `superpowers:executing-plans` Inline Execution，不启用 subagents。

**Goal:** 让 Site 页面空态始终从动态 Gateway Header 底部开始，避免未绑定 Space 的 Gateway 选中后由 `EmptyDataView` 截获 `Review sync` 点击。

**Architecture:** 新增一个 Foundation-only 纯布局策略，统一计算 Gateway list、Gateway status 和 Review sync 组合后的 Header 高度。`SiteViewController` 的 supplementary header 和 All Spaces/Favorites 空态 frame 共用该策略，并在 Review 状态变化后重新计算空态 frame。

**Tech Stack:** Swift、UIKit、UICollectionView supplementary view、Foundation-only standalone `swiftc` tests、source contract tests、Xcode generic iPhoneOS builds。

## 全局约束

- 所有回复、计划、总结默认使用简体中文；UI 文案保持现有 English 与简体中文，不新增文案。
- 当前年份按 2026 年处理。
- 保持改动聚焦，不修改 Gateway 权限、Space 绑定、时区判定、Sync gateways 数据选择或导航规则。
- 不修改 `EmptyDataView` 全局交互行为，不修改 SDK、依赖、本地化或资源。
- 新增 Swift 文件加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 App target。
- 保留 worktree 中已有的 Gateway Information 等无关未提交改动，只暂存本计划明确列出的文件。
- 遵循 TDD：先写失败测试并观察预期失败，再写最小生产实现。
- iOS 构建直接使用 `xcodebuild`、generic iPhoneOS 和 `CODE_SIGNING_ALLOWED=NO`；不用 shell 包装、日志重定向或 Simulator。

---

## 文件结构

- Create: `SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift` — Foundation-only 的 Header 高度纯策略。
- Create: `Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift` — 四种可见组合的行为测试。
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift` — Header 高度、空态 frame 和 Review 状态变化接线。
- Modify: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift` — 验证共享策略接线、动态空态和四 target membership。
- Modify: `scripts/check_site_sync_gateways.sh` — 将新增纯策略测试加入聚合验证。
- Modify: `SunSmart.xcodeproj/project.pbxproj` — 新布局策略加入四个 App target。
- Create: `docs/260814_1624_site_review_sync_empty_state_touch_implementation_summary.md` — 最终实现和验证边界总结。

### Task 1: 建立纯 Header 高度策略

**Files:**
- Create: `Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift`
- Create: `SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift`

**Interfaces:**
- Consumes: 已按屏幕缩放计算的 `gatewayListHeight`、`gatewayStatusHeight`、`reviewSyncHeight`，以及两个可见状态 Bool。
- Produces: `SiteGatewayHeaderLayoutPolicy.height(gatewayListHeight:gatewayStatusHeight:reviewSyncHeight:showsGatewayStatus:showsReviewSync:) -> CGFloat`。

- [ ] **Step 1: 写纯策略失败测试**

创建 `Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift`：

```swift
import Foundation

@main
struct SiteGatewayHeaderLayoutPolicyTests {

    static func main() {
        require(height(status: false, review: false) == 48)
        require(height(status: true, review: false) == 96)
        require(height(status: true, review: true) == 160)
        require(height(status: false, review: true) == 112)
        print("SiteGatewayHeaderLayoutPolicyTests passed")
    }

    private static func height(
        status: Bool,
        review: Bool
    ) -> CGFloat {
        SiteGatewayHeaderLayoutPolicy.height(
            gatewayListHeight: 48,
            gatewayStatusHeight: 48,
            reviewSyncHeight: 64,
            showsGatewayStatus: status,
            showsReviewSync: review
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String = "Unexpected Site Gateway Header height",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift -o /tmp/SiteGatewayHeaderLayoutPolicyTests
```

Expected: 编译失败，错误包含 `cannot find 'SiteGatewayHeaderLayoutPolicy' in scope`。

- [ ] **Step 3: 写最小纯策略实现**

创建 `SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift`：

```swift
import Foundation

enum SiteGatewayHeaderLayoutPolicy {

    static func height(
        gatewayListHeight: CGFloat,
        gatewayStatusHeight: CGFloat,
        reviewSyncHeight: CGFloat,
        showsGatewayStatus: Bool,
        showsReviewSync: Bool
    ) -> CGFloat {
        gatewayListHeight +
            (showsGatewayStatus ? gatewayStatusHeight : 0) +
            (showsReviewSync ? reviewSyncHeight : 0)
    }
}
```

- [ ] **Step 4: 运行测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift -o /tmp/SiteGatewayHeaderLayoutPolicyTests
/tmp/SiteGatewayHeaderLayoutPolicyTests
```

Expected: 输出 `SiteGatewayHeaderLayoutPolicyTests passed`。

- [ ] **Step 5: 提交纯策略与测试**

```bash
git add SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift
git commit -m "test: add site gateway header layout policy"
```

### Task 2: 让 Header 与空态共用动态高度

**Files:**
- Modify: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Modify: `scripts/check_site_sync_gateways.sh`
- Modify: `SunSmart.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 的 `SiteGatewayHeaderLayoutPolicy.height(...)`。
- Produces: `siteGatewayHeaderHeight(for:) -> CGFloat` 和 `emptyFrame(for:spaces:) -> CGRect`；两种 CollectionView 的 Header 与空态共用同一高度真值。

- [ ] **Step 1: 扩充接线契约并确认它能捕获当前缺陷**

修改 `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`：

1. 删除旧的 `headerH += SCRYFrom(64)` 断言。
2. 增加以下行为接线断言：

```swift
require(siteController.contains("SiteGatewayHeaderLayoutPolicy.height("))
require(
    siteController.contains("private func siteGatewayHeaderHeight(") &&
        occurrences(of: "siteGatewayHeaderHeight(for:", in: siteController) == 2,
    "Header size and empty frame must share one height calculation"
)
require(
    occurrences(of: "emptyFrame(", in: siteController) == 4,
    "Three empty states must use the shared empty frame helper"
)
require(
    !siteController.contains("SCRYFrom(96)"),
    "Empty states must not retain the pre-review fixed header offset"
)
let reviewStateSetter = sourceSection(
    in: siteController,
    from: "private func setTimeZoneReviewState(",
    to: "private func setEntrySyncNavigationLocked("
)
require(
    appearsInOrder(
        [
            "timeZoneReviewState = state",
            "favouritesCollectionView.reloadData()",
            "updateEmptyView()"
        ],
        in: reviewStateSetter
    ),
    "Review state changes must refresh existing empty frames"
)
```

3. 增加 `appearsInOrder(_:in:)` helper：

```swift
private static func appearsInOrder(
    _ needles: [String],
    in text: String
) -> Bool {
    var searchStart = text.startIndex
    for needle in needles {
        guard let range = text.range(
            of: needle,
            range: searchStart..<text.endIndex
        ) else {
            return false
        }
        searchStart = range.upperBound
    }
    return true
}

private static func sourceSection(
    in source: String,
    from start: String,
    to end: String
) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(
              of: end,
              range: startRange.upperBound..<source.endIndex
          ) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}
```

4. 增加四 target membership 断言，使用未占用的固定 ID `F2608140000000000002900...2904`：

```swift
require(
    occurrences(
        of: "SiteGatewayHeaderLayoutPolicy.swift in Sources",
        in: project
    ) == 8,
    "Header layout policy must belong to all four app targets"
)
for targetSuffix in 1...4 {
    require(
        occurrences(
            of: "F260814000000000000290\(targetSuffix) /* SiteGatewayHeaderLayoutPolicy.swift in Sources */",
            in: project
        ) == 2,
        "Header layout policy must be declared and referenced by target \(targetSuffix)"
    )
}
```

- [ ] **Step 2: 运行 Review sync 契约并确认 RED**

Run:

```bash
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: 运行失败，首先报告 Header 与空态尚未共享高度计算，或新文件尚未加入四个 target。

- [ ] **Step 3: 在 Controller 中建立唯一 Header 高度入口**

在 `SiteViewController` 的空态方法附近增加：

```swift
private func siteGatewayHeaderHeight(
    for spaces: [SpaceData]
) -> CGFloat {
    let showsReviewSync: Bool
    if case .review = timeZoneReviewState {
        showsReviewSync = true
    } else {
        showsReviewSync = false
    }
    return SiteGatewayHeaderLayoutPolicy.height(
        gatewayListHeight: SCRYFrom(48),
        gatewayStatusHeight: SCRYFrom(48),
        reviewSyncHeight: SCRYFrom(64),
        showsGatewayStatus: shouldShowGatewayStatus(for: spaces),
        showsReviewSync: showsReviewSync
    )
}

private func emptyFrame(
    for collectionView: UICollectionView,
    spaces: [SpaceData]
) -> CGRect {
    var frame = collectionView.bounds
    frame.origin.y += siteGatewayHeaderHeight(for: spaces)
    return frame
}
```

将 `referenceSizeForHeaderInSection` 的分散加法替换为：

```swift
let spaces = collectionView == allSpacesCollectionView
    ? allSpaces
    : favouriteSpaces
return CGSize(
    width: headerW,
    height: siteGatewayHeaderHeight(for: spaces)
)
```

- [ ] **Step 4: 三处空态统一使用动态 frame**

在 `updateEmptyView()` 中：

- Site 完全没有 Spaces 的 All Spaces 空态使用 `emptyFrame(for: allSpacesCollectionView, spaces: allSpaces)`，删除手工 `frame.origin.y` 和 `showGatewayModels.count` 判断。
- Site 有 Spaces、但当前 Gateway 过滤结果为空的 All Spaces 空态使用同一个 `emptyFrame`。
- Favorites 空态使用 `emptyFrame(for: favouritesCollectionView, spaces: favouriteSpaces)`。

最终三处调用都显式传入共享 frame，例如：

```swift
allSpacesCollectionView.showEmptyDataView(
    frame: emptyFrame(
        for: allSpacesCollectionView,
        spaces: allSpaces
    ),
    title: "no_spaces_title".localizedString,
    bottomMargin: SCRYFrom(32)
)
```

- [ ] **Step 5: Review 状态变化后刷新既有空态 frame**

在 `setTimeZoneReviewState(_:)` 完成两个 CollectionView 的 layout invalidation 和 reload 后调用：

```swift
updateEmptyView()
```

这覆盖首次 Site import 先执行 `setupData()`、后产生 `.review` 状态的时序，避免空态保留 hidden 状态下的旧 frame。

- [ ] **Step 6: 新布局策略加入四个 App target**

修改 `SunSmart.xcodeproj/project.pbxproj`：

- File reference：`F2608140000000000002900`。
- 四个 build file：`F2608140000000000002901...2904`。
- 加入 Site/Model group。
- 分别加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 Sources phase。
- 不改 Build Settings、资源或依赖。

- [ ] **Step 7: 聚合脚本加入纯策略测试**

在 `scripts/check_site_sync_gateways.sh` 首个现有测试之前加入：

```bash
swiftc -parse-as-library \
  SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift \
  Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift \
  -o /tmp/SiteGatewayHeaderLayoutPolicyTests
/tmp/SiteGatewayHeaderLayoutPolicyTests
```

- [ ] **Step 8: 运行聚焦测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift -o /tmp/SiteGatewayHeaderLayoutPolicyTests
/tmp/SiteGatewayHeaderLayoutPolicyTests
swiftc -parse-as-library Tests/Site/SiteTimeZoneReviewSyncContractTests.swift -o /tmp/SiteTimeZoneReviewSyncContractTests
/tmp/SiteTimeZoneReviewSyncContractTests SunSmart/Main/Site/View/SiteTimeZoneReviewSyncView.swift SunSmart/Main/Site/View/SiteGatewayHeaderView.swift SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart/Main/Site/Controller/SyncGatewaysViewController.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
bash scripts/check_site_sync_gateways.sh
```

Expected: 分别输出 `SiteGatewayHeaderLayoutPolicyTests passed`、`SiteTimeZoneReviewSyncContractTests passed` 和 `SiteSyncGateways checks passed`。

- [ ] **Step 9: 提交 Controller 接线修复**

```bash
git add SunSmart/Main/Site/Controller/SiteViewController.swift Tests/Site/SiteTimeZoneReviewSyncContractTests.swift scripts/check_site_sync_gateways.sh SunSmart.xcodeproj/project.pbxproj
git commit -m "fix: keep site empty state below header"
```

### Task 3: 完整验证与交付总结

**Files:**
- Create: `docs/260814_1624_site_review_sync_empty_state_touch_implementation_summary.md`

**Interfaces:**
- Consumes: Tasks 1-2 的实现和测试结果。
- Produces: 可审计的静态验证、四 target 构建证据和真机验收边界。

- [ ] **Step 1: 运行完整聚合测试与 diff 检查**

Run:

```bash
bash scripts/check_site_sync_gateways.sh
git diff --check
```

Expected: 聚合测试输出 `SiteSyncGateways checks passed`，`git diff --check` 无输出且退出码为 0。

- [ ] **Step 2: 直接构建四个 generic iPhoneOS target**

依次运行：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四次均以 `** BUILD SUCCEEDED **` 和退出码 0 结束。

- [ ] **Step 3: 保存实施总结**

创建 `docs/260814_1624_site_review_sync_empty_state_touch_implementation_summary.md`，记录：

- 根因是 `EmptyDataView` 固定 96pt 起点覆盖动态 Review sync Header，而非导航 guard。
- 新共享布局策略及 All Spaces/Favorites/Review 状态变化接线。
- RED 与 GREEN 的实际命令和结果。
- 四 target generic iPhoneOS 构建结果。
- 真机仍需复测 Overview、无绑定 Space Gateway、已绑定 Gateway、Site 无 Space、Favorites 为空五种交互。

- [ ] **Step 4: 提交实施总结**

```bash
git add docs/260814_1624_site_review_sync_empty_state_touch_implementation_summary.md
git commit -m "docs: summarize site review sync touch fix"
```

- [ ] **Step 5: 最终范围审计**

Run:

```bash
git status --short
git show --stat --oneline HEAD~2..HEAD
```

Expected: 本任务提交只包含计划中列出的实现、测试、工程引用、脚本和总结；用户原有 Gateway Information 等未提交文件保持未暂存、未提交。
