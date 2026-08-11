# Time Zone 搜索框背景偏灰修复总结

## 1. 修复结果

已按确认的方案 A 完成最小修复：保留 `UISearchTextField`，关闭其默认系统 `roundedRect` 外观，再继续使用现有白色背景、10pt 圆角和 0.5pt 边框。

该改动避免系统搜索框样式在显式白色背景上继续绘制 RGB(242, 242, 242) 的灰色填充。UIKit 像素探针显示，无系统边框样式时最终可见填充为 RGB(255, 255, 255)。

## 2. 本轮改动

### 生产代码

- `SunSmart/Main/Site/Controller/SiteTimeZoneSelectionViewController.swift`
  - 在现有白色背景配置之前，将 `searchField.borderStyle` 设为无系统边框样式。
  - 未修改控件类型、搜索图标、clear button、键盘、布局约束或搜索逻辑。

### 回归契约

- `Tests/Site/SiteTimeZoneUIContractTests.swift`
  - 要求先关闭系统边框样式，再绘制白色背景和项目圆角。
  - 禁止在该配置段通过背景图或 UIKit 私有子视图绕过系统样式。

### 文档

- `docs/260811_1615_time_zone_search_field_background_fix_plan.md`
- `docs/260811_1627_time_zone_search_field_background_fix_summary.md`

## 3. TDD 证据

### RED

新增回归契约后、修改生产代码前，完整 Time Zone UI contract 按预期失败：

`Time Zone search field must disable the system rounded style before drawing its white background`

### GREEN

生产代码增加最小外观配置后，同一完整 Time Zone UI contract 通过。

## 4. 自动验证

以下 7 项 focused tests/contracts 均通过，退出码均为 0：

- `SiteTimeZoneValueTests`
- `SiteTimeZoneCatalogTests`
- `SitePropsEditPolicyTests`
- `SiteTimeZonePersistenceContractTests`
- `SitePropsAPIContractTests`
- `SiteTimeZoneUIContractTests`：完整 UI 路由
- `SiteTimeZoneUIContractTests`：本地化、资源与四 target 归属

UIKit 运行时像素探针结果：

- 系统 `roundedRect` + `.white`：RGB(242, 242, 242)
- 无系统边框样式 + `.white`：RGB(255, 255, 255)

以下四个 scheme 均使用 Debug、generic iPhoneOS、关闭签名方式构建成功，退出码均为 0：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

`git diff --check` 通过。

## 5. 变更边界

- 未新增或修改用户可见文案、本地化和资源。
- 未修改 target 配置、依赖、SDK、数据库、服务器接口或 Mesh 行为。
- 未修改 Time Zone 页面其他布局、数据与交互。
- 保留了当前 worktree 中 modal dismissal、Site update toast、资源及其他并行未提交改动。
- 未执行 Git commit、push 或 merge。

## 6. 尚需真机验收

当前证据可证明 UIKit 渲染假设、源码契约与四 target 编译成立，但不替代真机验收。建议重点确认：

- 搜索框内部与下方白色列表卡片视觉一致。
- 圆角、边框、搜索图标、placeholder 和 clear button 位置正常。
- 输入、清空、Return Search、列表过滤及键盘拖动收起行为正常。
