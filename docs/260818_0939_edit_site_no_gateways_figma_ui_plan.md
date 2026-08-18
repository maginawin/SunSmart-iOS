# Edit Site 无 Gateway 状态 UI 开发方案

## 1. 目标

在 Edit Site 更新 Time Zone 后，当本次可配置 Gateway 集合为空、无需执行 Gateway 时区更新时，将 `GATEWAYS` 区域的 `No gateways` 空状态更新为 Figma `Content/GatewaysNoGateways` 的紧凑行式卡片。

本方案只调整结果页的空状态展示，不改变 Site 保存、Gateway 权限筛选、时区比较、Cloud API 调用、超时和完成按钮行为。

## 2. 当前状态与业务边界

- Edit Site 通过 `SiteTimeZoneSyncStatusView` 展示结果，并复用 `SiteEntryGatewayTimeZoneStatusView` 渲染 Gateway 区域。
- `SiteGatewayLocalTimeZoneTargetBuilder` 会保留所有有配置权限的 Gateway，并用 `requiresSync` 区分是否需要更新。
- 只有 Batch 的 `items` 为空时才显示 `No gateways`；有 Gateway 但时区已经一致时，仍显示对应的 `Synced` 行。
- 完整快照或 Gateway 检查不可用时使用 `Unable to check gateways`，不会降级为 `No gateways`。
- 当前工作树无未提交改动。

建议保持以上状态边界。Figma 文案明确是 `No gateways configured — no sync needed.`，因此不应把“存在 Gateway，但全部已经同步”折叠为 `No gateways`。

## 3. Figma 对照结论

参考节点：`420:11912` 中的 `Content/GatewaysNoGateways`（子节点 `420:11977`）。

目标结构：

- 卡片背景使用现有内容背景色 `#F8FAFC`，圆角 14pt。
- 卡片水平内边距 16pt、垂直内边距 8pt。
- 顶部显示 `GATEWAYS` Header，12pt，颜色 `#64748B`，不显示数量和分隔线。
- 下方为水平状态行，垂直内边距 8pt。
- 左侧为 32pt 圆形浅灰底座，背景为 `#94A3B8` 的 10% 透明度；内部 Gateway 图标为 16pt。
- 图标与文案间距 12pt。
- 右侧主文案为 `No gateways`，14pt、Light、颜色 `#1E2329`。
- 辅助文案为 `No gateways configured — no sync needed.`，12pt、Regular、颜色 `#94A3B8`。
- 默认字号下保持紧凑高度；Dynamic Type 或较窄宽度下允许文案换行并由 Auto Layout 自然增高。

现有 `time-zone-sync-status-gateway` SVG 与 Figma 图标的路径和渐变一致，可以直接复用。实现时移除当前强制黄色 Tint，在 32pt 浅灰圆形底座内按 16pt 渲染，无需新增或修改 Asset Catalog。

## 4. 推荐实现方案

### 4.1 调整空状态内部结构

修改 `SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`：

- 保留现有 `emptyStateView` 作为独立空状态卡片，不重构 Gateway 列表和失败卡片。
- 在空状态卡片内增加独立 Header Label，复用 `site_entry_sync_gateways_header`。
- 增加 32pt 圆形图标底座，将现有 Gateway SVG 以 16pt 原始渐变样式居中展示。
- 将标题和辅助说明改为右侧纵向文本区域并左对齐。
- 使用闭合的 Auto Layout 约束表达 16pt/8pt/12pt 间距，删除当前图标置顶居中、文案居中和 152pt 最小高度。
- 空状态高度继续通过 `systemLayoutSizeFitting` 测量；移除 152pt 高度下限，使父 `SiteTimeZoneSyncStatusView` 的现有 `preferredHeight` 回调自动收紧结果 Sheet。

### 4.2 文案与国际化

- 主文案改为复用现有 `site_no_gateways`。
- 辅助文案改为复用现有 `site_no_gateways_sync_needed`，其 English 已与 Figma 一致使用长破折号：`No gateways configured — no sync needed.`。
- 两个 Key 已同时存在 English 和简体中文翻译，本次无需新增本地化资源。
- 不修改 Site Entry 旧 Overlay 的 `site_entry_sync_*` 文案与行为。

### 4.3 无障碍

- `GATEWAYS` Header 作为 Header 元素暴露给 VoiceOver。
- 空状态行只朗读一次 `No gateways` 与辅助说明。
- 圆形底座和 Gateway 图标保持装饰性，不重复朗读。

## 5. 预计改动文件

- 修改：`SunSmart/Main/Site/View/SiteEntryGatewayTimeZoneStatusView.swift`
- 修改：`Tests/Site/SiteGatewayCloudTimeZoneUIContractTests.swift`
- 如父视图契约需要补充空状态高度联动断言，再最小修改：`Tests/Site/SiteTimeZoneUIContractTests.swift`

预计不修改：

- `SiteTimeZoneSyncStatusView.swift`
- Gateway 状态模型、Target Builder、同步 Coordinator 和 API Client
- English / 简体中文 `Localizable.strings`
- Asset Catalog、project.pbxproj、target 配置和依赖

## 6. 测试与验证计划

### 6.1 先更新契约并确认 RED

扩展 `SiteGatewayCloudTimeZoneUIContractTests`，锁定：

- 空状态包含独立 `GATEWAYS` Header 和紧凑水平状态行。
- 32pt 浅灰圆形底座、16pt 原始渐变 Gateway 图标、12pt 图文间距。
- 两行文案左对齐并支持 Dynamic Type/换行。
- 不再存在 152pt 空状态高度下限和居中纵向布局。
- 空状态复用 Edit Site 的两个现有本地化 Key。
- 空状态与 `.unavailable`、非空 Gateway 列表、失败统计仍为互斥布局。

生产代码修改前运行聚焦契约，预期因旧布局不符合目标而失败。

### 6.2 实现后验证 GREEN

- 运行完整 `scripts/check_site_sync_gateways.sh`。
- 运行 `git diff --check`。
- 直接运行 generic iPhoneOS Debug unsigned 构建，依次验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme。
- 核对最终 diff 只包含批准的 UIKit 空状态与测试文件。

### 6.3 手工验收场景

- Edit Site 修改 Time Zone，且无可配置 Gateway：显示 Figma 目标空状态并可立即点击 `DONE`。
- 有可配置 Gateway、全部已经同步：继续显示各 Gateway 的 `Synced` 行，不显示 `No gateways`。
- 有待更新 Gateway：`Pushing…`、`Synced`、`Failed` 和超时行为保持不变。
- Gateway 检查不可用：继续显示 `Unable to check gateways`，不误报 `No gateways`。
- English、简体中文、较大 Dynamic Type 和窄屏下无截断或约束冲突。

真机视觉、VoiceOver、Dynamic Type、真实 Cloud/Gateway 和 BLE/Mesh 行为不由静态契约或 unsigned build 证明，仍需单独验收。

## 7. 确认点

推荐按本方案实施，并确认以下语义保持不变：只有“可配置 Gateway 集合为空”显示 `No gateways`；“存在 Gateway，但本次均无需更新”继续显示 Gateway 的 `Synced` 行。
