# Site 入口同步弹窗 Figma 对齐实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `SiteEntryTimeZoneSyncOverlay` 的检查态与结果态准确匹配指定 Figma 节点。

**Architecture:** 保留单一 Overlay 和现有状态机，在 Overlay 内将两种状态拆成各自独立的固定规格卡片容器。使用共用 Asset Catalog 保存 Figma 导出的 Loading 与成功图标，不改变业务协调器和 Site 页面入口逻辑。

**Tech Stack:** Swift、UIKit、SnapKit、Asset Catalog、独立 Swift 契约测试、xcodebuild generic iPhoneOS。

## Global Constraints

- 仅修改 Site 入口同步弹窗视觉及相应测试、资源、文档。
- 不改变时区仲裁、超时和导航锁定行为。
- 不新增 Gateway、BLE 或 Mesh 同步。
- 新资源必须由四个品牌 target 共用。
- 不创建 Git commit。

---

### Task 1: 建立 Figma 视觉契约

**Files:**
- Modify: `Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`

**Interfaces:**
- Consumes: `SiteEntryTimeZoneSyncOverlay.swift` 源文件路径。
- Produces: 检查态与结果态的尺寸、圆角、间距、资源、按钮结构契约。

- [x] **Step 1: 添加旧实现无法满足的视觉契约断言**
- [x] **Step 2: 编译并运行契约测试，确认因 Figma 规格缺失而失败**

### Task 2: 对齐两个弹窗状态

**Files:**
- Modify: `SunSmart/Main/Site/View/SiteEntryTimeZoneSyncOverlay.swift`
- Create: `SunSmart/Assets.xcassets/Common/site_entry_sync_loading.imageset/Contents.json`
- Create: `SunSmart/Assets.xcassets/Common/site_entry_sync_loading.imageset/site_entry_sync_loading.svg`
- Create: `SunSmart/Assets.xcassets/Common/site_entry_sync_success.imageset/Contents.json`
- Create: `SunSmart/Assets.xcassets/Common/site_entry_sync_success.imageset/site_entry_sync_success.svg`

**Interfaces:**
- Consumes: 现有 `showChecking`、`showResult`、`dismiss` 和 `onGotIt` API。
- Produces: 与 Figma 节点 `399:11418`、`399:11390` 对齐的两态 Overlay。

- [x] **Step 1: 加入 Figma 原始 SVG 资源**
- [x] **Step 2: 重构检查态卡片为 302 × 188 pt 结构**
- [x] **Step 3: 重构结果态卡片为 343 × 296 pt 结构**
- [x] **Step 4: 保留动态状态文案、失败颜色、动画和交互行为**
- [x] **Step 5: 运行契约测试并确认通过**

### Task 3: 回归验证与交付记录

**Files:**
- Modify: `docs/260812_1841_site_entry_timezone_sync_implementation_summary.md`

**Interfaces:**
- Consumes: 完成后的 Overlay、资源与测试。
- Produces: 聚焦测试、四 target 构建和真实环境验收边界记录。

- [x] **Step 1: 运行全部 Site 入口时区同步聚焦测试**
- [x] **Step 2: 运行 `git diff --check` 和 Asset Catalog 检查**
- [x] **Step 3: 构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart**
- [x] **Step 4: 更新实施总结并报告真机视觉验收边界**
