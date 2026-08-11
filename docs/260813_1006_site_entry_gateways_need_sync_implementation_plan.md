# Site 入口 Gateway 待同步状态实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task with Inline Execution. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `SiteEntryTimeZoneSyncOverlay` 增加对齐 Figma `399:11362` 的 `gatewaysNeedSync` 状态，并向 `SiteViewController` 暴露 `REVIEW SYNC` 回调。

**Architecture:** 保留 Overlay 和 `showResult(_:)` 统一入口，在 Overlay 内根据 `SiteEntryTimeZoneResult.gateway` 将 `.pending` 映射为带关联结果的 `gatewaysNeedSync` 状态。复用现有结果卡主体，只切换 Gateway 指示器与底部按钮组；Controller 继续负责关闭、取消任务、解除导航锁定和继续既有入口导航。

**Tech Stack:** Swift、UIKit、SnapKit、Asset Catalog、Figma SVG、独立 `swiftc` 契约测试、`xcodebuild` generic iPhoneOS。

## Global Constraints

- UI 文案支持 English 和简体中文国际化。
- 只修改 Overlay、Site Controller、本地化、共用 Asset Catalog、聚焦测试和文档。
- 不修改 Coordinator、服务器接口、时区仲裁、超时、导航锁定策略或 Gateway 同步业务。
- 不实现 `REVIEW SYNC` 后续页面，不发送 Gateway、BLE 或 Mesh 指令。
- 保留 `checking`、普通 `result`、`GOT IT` 的既有行为。
- 不新增 Auth 信息，不格式化无关文件，不创建 Git commit。
- 共用资源需验证四个品牌 target。

---

### Task 1: 建立失败契约

**Files:**
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**
- Consumes: Overlay、本地化、Site Controller、工程和警告 imageset 路径。
- Produces: 新状态、自动选择、双按钮、警告资源、国际化和 Controller 回调契约。

- [x] **Step 1: 添加状态与状态选择断言**

要求源码包含 `case gatewaysNeedSync(SiteEntryTimeZoneResult)`，并让 `showResult(_:)` 在 `.pending` 时调用 `update(state: .gatewaysNeedSync(result))`。该断言捕获 `.pending` 错误进入普通结果页的缺陷。

- [x] **Step 2: 添加 UI 与回调断言**

要求 Overlay 包含 `onLater`、`onReviewSync`、`laterButtonDidTap`、`reviewSyncButtonDidTap`、`site_entry_sync_warning`、`RGB(225, 113, 0)`，并要求三组按钮按状态互斥显示。要求 Controller 绑定两个新回调，且 Review 入口调用 `finishEntrySyncOverlay()`。

- [x] **Step 3: 添加国际化与资源断言**

将 `site_entry_sync_later`、`site_entry_sync_review_sync` 加入 English 和简体中文“恰好定义一次且 Overlay 消费”的 Key 列表。测试参数从 6 个扩为 7 个，读取警告 imageset 的 `Contents.json`，要求引用 `site_entry_sync_warning.svg`；同时检查 SVG 资源名在 Overlay 中被消费。

- [x] **Step 4: 编译并运行契约，确认 RED**

```bash
swiftc -parse-as-library Tests/Site/SiteEntryTimeZoneSyncContractTests.swift -o /tmp/SiteEntryTimeZoneSyncContractTests
/tmp/SiteEntryTimeZoneSyncContractTests SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift SunSmart/en.lproj/Localizable.strings SunSmart/zh-Hans.lproj/Localizable.strings SunSmart/Main/Site/Controller/SiteViewController.swift SunSmart.xcodeproj/project.pbxproj SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
```

Expected: 因缺少 `gatewaysNeedSync` 或警告资源而失败，不得是参数数量、测试语法或错误路径。

---

### Task 2: 实现 Overlay 与 Figma UI

**Files:**
- Modify: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
- Modify: `SunSmart/en.lproj/Localizable.strings`
- Modify: `SunSmart/zh-Hans.lproj/Localizable.strings`
- Create: `SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json`
- Create: `SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/site_entry_sync_warning.svg`
- Test: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**
- Consumes: `SiteEntryTimeZoneResult`、`GatewaySummary.pending(Int)` 和现有 Overlay 生命周期 API。
- Produces: `State.gatewaysNeedSync(SiteEntryTimeZoneResult)`、`onLater`、`onReviewSync` 与 Figma 双按钮警告态。

- [x] **Step 1: 添加 Figma 警告资源**

下载节点 `399:11379` 的原始 SVG，确认 16 × 16 viewBox 和 `#E17100` 描边后原样加入共用 Asset Catalog。`Contents.json` 沿用 `site_entry_sync_success.imageset` 的 universal 1x + vector preservation 结构。

- [x] **Step 2: 扩展状态与回调 API**

```swift
enum State: Equatable {
    case checking
    case gatewaysNeedSync(SiteEntryTimeZoneResult)
    case result(SiteEntryTimeZoneResult)
}

var onGotIt: (() -> Void)?
var onLater: (() -> Void)?
var onReviewSync: (() -> Void)?
```

`showResult(_:)` 对 `.pending` 进入 `.gatewaysNeedSync(result)`，对 `.noGateways` 和 `.inSync` 进入 `.result(result)`。

- [x] **Step 3: 复用结果内容并切换 Gateway 指示器**

`.result` 与 `.gatewaysNeedSync` 共享 Site/Gateway 文案填充。新状态的 Gateway 行使用 `RGB(225, 113, 0)` 文字、10% 同色图标底和 `UIImage(named: "site_entry_sync_warning")`；普通结果继续使用绿色成功图标，Site 失败继续使用红色失败样式。

- [x] **Step 4: 实现两种 Footer 模式**

保留 60 pt 高 `gotItButton`，新增等宽 `laterButton` 和 `reviewSyncButton` 以及 1 pt 居中竖分隔线。`LATER` 使用 `RGB(64, 79, 102)`，`REVIEW SYNC` 使用 `RGB(102, 103, 171)`，两者均为 15 pt Light。`checking` 隐藏全部按钮；普通 `result` 仅显示 `GOT IT`；`gatewaysNeedSync` 仅显示双按钮。

- [x] **Step 5: 添加动作与本地化**

```swift
@objc private func laterButtonDidTap() {
    guard case .gatewaysNeedSync = state else { return }
    onLater?()
}

@objc private func reviewSyncButtonDidTap() {
    guard case .gatewaysNeedSync = state else { return }
    onReviewSync?()
}
```

English 使用 `LATER` / `REVIEW SYNC`；简体中文使用 `稍后` / `查看同步`。

- [x] **Step 6: 重跑契约，确认失败点推进到 Controller 回调**

重复 Task 1 Step 4 命令。Expected: Overlay、资源和本地化断言通过，只剩 Controller 尚未绑定新回调。

---

### Task 3: 绑定 Controller 回调

**Files:**
- Modify: `SunSmart/Main/Site/Controller/SiteViewController.swift`
- Test: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**
- Consumes: `onLater`、`onReviewSync`、`finishEntrySyncOverlay()`。
- Produces: 两个按钮均关闭弹窗；`handleEntrySyncReview()` 作为后续业务入口。

- [x] **Step 1: 绑定新回调**

```swift
overlay.onLater = { [weak self] in
    self?.finishEntrySyncOverlay()
}
overlay.onReviewSync = { [weak self] in
    self?.handleEntrySyncReview()
}
```

- [x] **Step 2: 添加 Review 扩展点**

```swift
private func handleEntrySyncReview() {
    finishEntrySyncOverlay()
}
```

本次该入口只关闭、解锁并继续既有导航；后续业务从此处扩展，Overlay 不依赖导航或同步服务。

- [x] **Step 3: 运行契约，确认 GREEN**

重复 Task 1 Step 4 命令。Expected: 输出 `SiteEntryTimeZoneSyncContractTests passed`。

- [x] **Step 4: 执行变异检查**

确认测试能分别捕获：删除 `.pending` 分支、交换按钮回调、删除警告资源、让普通结果显示双按钮、让 Review 绕过 `finishEntrySyncOverlay()`。缺失的保护先补断言，并重新经历 RED/GREEN。

---

### Task 4: 回归、构建与交付记录

**Files:**
- Create: `docs/260813_HHmm_site_entry_gateways_need_sync_implementation_summary.md`

**Interfaces:**
- Consumes: 完成后的 Overlay、Controller、资源、本地化和测试。
- Produces: 静态契约、构建结果和真机验收边界记录。

- [x] **Step 1: 运行三个 Site 入口同步聚焦测试**

分别编译并运行 `SiteEntryTimeZoneSyncPolicyTests`、`SiteEntryTimeZoneSyncCoordinatorTests`、`SiteEntryTimeZoneSyncContractTests`，使用既有计划 `docs/260812_1743_site_entry_timezone_sync_implementation_plan.md` 中已经验证的 `swiftc -parse-as-library` 输入集合。Expected: 三项均输出 `passed`。

- [x] **Step 2: 检查资源和差异**

```bash
jq empty SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/Contents.json
xmllint --noout SunSmart/Assets.xcassets/Common/site_entry_sync_warning.imageset/site_entry_sync_warning.svg
git diff --check
git status --short
```

Expected: 资源 JSON 与差异检查通过，状态仅包含本计划文件和已批准的设计、计划文档。

- [x] **Step 3: 依次构建四个品牌 target**

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme Archipelago -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme 'SLG Sync Plus' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace SunSmart.xcworkspace -scheme SylSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: 四项分别输出 `** BUILD SUCCEEDED **`；不使用 Simulator、shell 包装或日志重定向。

- [x] **Step 4: 写入实施总结并最终检查**

记录修改范围、Figma 节点、按钮关闭与回调行为、聚焦测试、四品牌构建，以及未通过真机验证的视觉、触摸、动画和未来 Review 业务。最后重新运行 `git diff --check`，检查 `git diff --stat` 与 `git status --short`，确认没有无关改动且没有 commit。
