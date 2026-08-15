# Site 空态下拉刷新遮挡修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Site 无 Space 时下拉刷新后 EmptyDataView 覆盖 Gateway 列表、Gateway 状态和 Review Sync 控件的问题。

**Architecture:** 在既有 `SiteGatewayHeaderLayoutPolicy` 中增加纯布局函数，将空态纵坐标与 Collection View 的瞬时滚动偏移解耦。`SiteViewController` 保留共享 `emptyFrame` 入口，使 All Spaces 与 Favourites 使用同一修复，不改变通用 EmptyDataView 或 Gateway 业务状态。

**Tech Stack:** Swift、UIKit、CoreGraphics、现有命令行 Swift 合约测试、Xcode generic iPhoneOS build。

## 全局约束

- 所有文档使用简体中文；不新增用户可见文案。
- 保持改动聚焦，不修改 Gateway 数据、权限、网络请求、刷新结束时机或通用 `EmptyDataView`。
- 不修改或提交当前已有的 `SunSmart.xcodeproj/project.pbxproj` 工作区改动。
- 测试必须先 RED 后 GREEN。
- iOS 构建直接运行 `xcodebuild`，使用 generic iPhoneOS 且关闭签名，不使用 shell 包装、日志重定向或 Simulator。

---

## 文件结构

- `Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift`：增加下拉刷新负纵向偏移的行为回归测试。
- `SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift`：提供不依赖滚动偏移的空态 frame 计算。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：将现有共享空态 helper 接到布局策略。
- `docs/260815_1405_site_empty_state_refresh_fix_design.md`：已确认的设计依据，不再修改。
- `docs/260815_1407_site_empty_state_refresh_fix_implementation_plan.md`：本实施计划。

### Task 1：空态 frame 布局策略 RED-GREEN

**Files:**
- Modify: `Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift`
- Modify: `SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift`

**Interfaces:**
- Consumes: `CGRect`、动态计算后的 `headerHeight`。
- Produces: `SiteGatewayHeaderLayoutPolicy.emptyStateFrame(collectionBounds: CGRect, headerHeight: CGFloat) -> CGRect`。

- [x] **Step 1：写入失败回归测试**

在 `main()` 中增加对负纵向偏移场景的调用，并加入以下测试函数：

```swift
private static func testEmptyStateFrameIgnoresVerticalBoundsOffset() {
    let bounds = CGRect(x: -16, y: -72, width: 390, height: 700)

    let frame = SiteGatewayHeaderLayoutPolicy.emptyStateFrame(
        collectionBounds: bounds,
        headerHeight: 96
    )

    require(frame.origin.x == -16)
    require(frame.origin.y == 96)
    require(frame.size == bounds.size)
}
```

该测试捕获三类回归：继续累加负 `bounds.origin.y`、错误改变横向 content inset 对应的位置、错误缩放空态尺寸。

- [x] **Step 2：运行测试并确认 RED**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift -o /tmp/SiteGatewayHeaderLayoutPolicyTests
```

Expected: 编译失败并明确报告 `SiteGatewayHeaderLayoutPolicy` 没有 `emptyStateFrame` 成员；失败原因必须是待实现行为缺失。

- [x] **Step 3：写入最小实现**

在 `SiteGatewayHeaderLayoutPolicy` 中增加：

```swift
static func emptyStateFrame(
    collectionBounds: CGRect,
    headerHeight: CGFloat
) -> CGRect {
    var frame = collectionBounds
    frame.origin.y = headerHeight
    return frame
}
```

- [x] **Step 4：运行测试并确认 GREEN**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift -o /tmp/SiteGatewayHeaderLayoutPolicyTests
/tmp/SiteGatewayHeaderLayoutPolicyTests
```

Expected: 输出 `SiteGatewayHeaderLayoutPolicyTests passed`。

### Task 2：接入 Site 两个页签的共享空态 helper

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Test: `Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift`
- Test: `Tests/Site/SiteTimeZoneReviewSyncContractTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `emptyStateFrame(collectionBounds:headerHeight:)`。
- Produces: `SiteViewController.emptyFrame(for:spaces:)` 对 All Spaces 与 Favourites 返回稳定纵坐标的 frame。

- [x] **Step 1：替换 helper 内的瞬时偏移累加**

将现有 `emptyFrame(for:spaces:)` 实现替换为：

```swift
return SiteGatewayHeaderLayoutPolicy.emptyStateFrame(
    collectionBounds: collectionView.bounds,
    headerHeight: siteGatewayHeaderHeight(for: spaces)
)
```

保留三个既有调用点，确保 Site 全空、Gateway 筛选后为空、Favourites 为空均走相同 helper。

- [x] **Step 2：运行布局策略与现有空态接线回归**

Run:

```bash
swiftc -parse-as-library SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift -o /tmp/SiteGatewayHeaderLayoutPolicyTests
/tmp/SiteGatewayHeaderLayoutPolicyTests
bash scripts/check_site_sync_gateways.sh
```

Expected: 布局策略测试与 SiteSyncGateways 聚焦检查全部通过。

- [x] **Step 3：检查差异范围**

Run:

```bash
git diff --check
git status --short
git diff -- SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift SunSmart/Main/Site/Controller/SiteViewController.swift
```

Expected: 无空白错误；生产与测试差异仅涉及三份目标文件；`project.pbxproj` 仍是未纳入本任务的既有改动。

### Task 3：共享 target 构建验证与交付

**Files:**
- Verify only: `SunSmart.xcworkspace`

**Interfaces:**
- Consumes: Task 2 完成后的源代码。
- Produces: 四个品牌 target 的静态编译证据与明确的真机验收边界。

- [x] **Step 1：构建 SunSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [x] **Step 2：构建 Archipelago**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [x] **Step 3：构建 SLG Sync Plus**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [x] **Step 4：构建 SylSmart**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `BUILD SUCCEEDED`。

- [x] **Step 5：最终复核与提交**

```bash
git diff --check
git status --short
git add SunSmart/Main/Site/Model/SiteGatewayHeaderLayoutPolicy.swift Tests/Site/SiteGatewayHeaderLayoutPolicyTests.swift SunSmart/Main/Site/Controller/SiteViewController.swift docs/260815_1407_site_empty_state_refresh_fix_implementation_plan.md
git commit -m "fix: keep site empty state below gateway header"
```

Expected: 提交只包含本任务的实现、测试与计划文档；既有 `project.pbxproj` 改动保持未提交。交付总结必须注明自动化和 generic iPhoneOS 构建不等于真机下拉刷新、触摸与视觉验收。

## 计划自检

- 设计中的 All Spaces、Favourites、动态 Header、负偏移、最小改动和真机边界均有对应任务。
- 测试 API 与生产 API 均为 `emptyStateFrame(collectionBounds:headerHeight:)`，类型一致。
- 没有未决实现项；每一步均包含具体文件、命令和预期结果。
