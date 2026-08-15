# Site 空态下拉刷新遮挡修复总结

## 结果

已修复 Site 页面无 Space 时下拉刷新后 EmptyDataView 覆盖 Gateway 列表、Gateway 状态和 Review Sync 控件的问题。All Spaces 与 Favourites 共用同一修复路径。

## 根因

下拉刷新期间 `UICollectionView.bounds.origin.y` 为负值。原空态 helper 在该瞬时值上累加动态 Gateway Header 高度，并以结果创建 EmptyDataView；Refresh Control 复位不会重算已经创建的空态 frame，因此空态永久上移并挡住 Header。

## 改动

- `SiteGatewayHeaderLayoutPolicy` 新增纯布局计算，保留 Collection View 横向位置与尺寸，并将空态纵坐标固定为完整 Header 高度。
- `SiteViewController.emptyFrame(for:spaces:)` 接入该策略，三个既有空态入口继续共享动态 Header 计算。
- 增加负 `bounds.origin.y` 回归测试，同时验证横向位置与尺寸未被改变。
- 未修改 Gateway 数据、权限、网络请求、刷新时机、通用 EmptyDataView、本地化、资源或 target 配置。

## TDD 证据

- RED：新增测试后编译明确失败，原因是 `SiteGatewayHeaderLayoutPolicy` 缺少 `emptyStateFrame`。
- GREEN：增加最小布局策略后输出 `SiteGatewayHeaderLayoutPolicyTests passed`。
- 完整聚焦回归输出 `SiteSyncGateways checks passed`。

## 构建证据

以下 generic iPhoneOS Debug 无签名构建均输出 `BUILD SUCCEEDED`：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建仍报告既有警告，包括 AppIntents 元数据跳过、部分品牌 Info.plist 位于 Copy Bundle Resources，以及个别 FSCalendar 重复源文件；未发现与本次布局改动相关的新错误。

## 验收边界

命令行回归测试与 generic iPhoneOS 构建证明布局策略、接线契约和四 target 编译通过，但不等同于真机上的下拉刷新动画、触摸命中与视觉验收。仍应在真实设备上分别检查 All Spaces 与 Favourites 的无 Space 场景。

## 工作区保护

本任务未修改或纳入已有 `SunSmart.xcodeproj/project.pbxproj` 改动，也未纳入并行产生的 `docs/260815_1407_ipad_gateway_timezone_prompt_analysis.md`。
