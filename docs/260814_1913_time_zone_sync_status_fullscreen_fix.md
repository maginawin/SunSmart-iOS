# Time Zone Sync Status 全屏覆盖修复

## 结论

已将 Time Zone Sync Status 的承载层级从来源页面 view 改回 active window。状态卡在 Edit Site 完全关闭后展示，遮罩覆盖包括 navigation bar 在内的整个界面；底层仍保留发起编辑的 Sites 或 Site 页面。

普通 Site Update Toast 继续由来源页面 view 承载，不受本次修复影响。

## 根因

来源页路由调整时，Time Zone 状态卡被显式添加到回调提供的 `SiteViewController.view` 或 `SitesViewController.view`。该 view 的布局区域位于 navigation bar 下方，因此状态卡的边缘约束只能覆盖页面内容区域，无法遮住 navigation bar。

`SiteTimeZoneSyncStatusView` 已有参数为空的展示路径，会选择当前 active window 并约束到 window 四边。本次无需修改状态视图本身。

## 修复

- `finishTimeZoneCommit` 仍先等待 Edit Site modal 完全关闭；
- 展示状态卡时不再传入来源页 view，改用既有 active window 路径；
- 来源页面导航契约保持不变：Site 入口不 pop，Sites 入口仍停留 Sites；
- 普通更新结果仍在来源页展示 Toast。

## TDD 证据

先更新 `SiteTimeZoneUIContractTests`，要求：

- Time Zone 状态卡调用参数为空的展示方法；
- 不允许传入来源结果 host；
- 状态视图仍通过 active window fallback 选择全屏宿主。

新契约在生产修改前按预期失败；完成最小修改后通过。随后重新运行普通 Toast routing 契约并通过，证明两类结果的承载策略没有混淆。

## 验证边界

本次回归结果：

- Site Edit alert transition、Time Zone UI、Site Update Toast、Site props policy/API/persistence 共 9 个聚焦检查通过；
- `git diff --check` 通过；
- SunSmart、Archipelago、SLG Sync Plus、SylSmart 的 Debug generic iPhoneOS 构建均为 `BUILD SUCCEEDED`；
- 串行构建期间未出现旧文件缺失或 `build.db` 锁定。

源码契约和 generic iPhoneOS 构建只能验证静态集成。仍需在 iPhone 与 iPad 真机确认遮罩确实覆盖 navigation bar，并验证 saving、success、failure 三种状态及两个 Edit Site 入口的实际动画层级。
