# Site Review sync 空态触摸修复实施总结

## 结果

已修复 Site 页面选择未绑定 Space 的 Gateway 后，`Review sync` 卡片可见但无法点击进入 `Sync gateways` 的问题。

## 根因

选择具体 Gateway 后，页面会只展示该 Gateway 绑定的 Spaces。未绑定 Space 时显示数组为空，`updateEmptyView()` 会向 CollectionView 添加 `EmptyDataView`。

原实现给空态使用固定 96pt 等纵向起点，而动态 Gateway Header 在 Gateway list、Gateway status 和 `Review sync` 同时可见时高度为 160pt。空态从 96pt 开始并位于更高层级，覆盖了 `Review sync` 的交互区域，因此按钮事件无法到达 Header 回调。

Overview 或 Gateway 绑定 Space 后不会出现同一空态覆盖关系，所以点击正常。导航 guard 不是本次问题的断点。

## 实现

- 新增 Foundation-only 的 `SiteGatewayHeaderLayoutPolicy`，统一计算 Gateway list、Gateway status 和 `Review sync` 组合后的 Header 高度。
- `referenceSizeForHeaderInSection` 改为使用共享高度策略。
- All Spaces 的两类空态与 Favorites 空态统一从对应 CollectionView 的实际 Header 底部开始。
- Review 状态从 hidden 变化为 review 后重新计算空态 frame，覆盖首次 Site import 先创建空态、后显示 Review 卡片的时序。
- 新策略加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 App target。
- 未修改 `EmptyDataView` 全局交互、Gateway 权限、Space 绑定、时区判定、Sync gateways 目标选择、导航、本地化、资源、SDK 或依赖。

## TDD 证据

### RED 1：纯布局策略

首次只编译 `SiteGatewayHeaderLayoutPolicyTests.swift`，按预期失败：

`cannot find 'SiteGatewayHeaderLayoutPolicy' in scope`

加入最小纯策略后，测试输出：

`SiteGatewayHeaderLayoutPolicyTests passed`

覆盖结果：

- 仅 Gateway list：48pt。
- Gateway list 与 Gateway status：96pt。
- Gateway list、Gateway status 与 `Review sync`：160pt。
- Gateway status 隐藏但 `Review sync` 可见：112pt。

### RED 2：Controller 接线

先扩充 `SiteTimeZoneReviewSyncContractTests`，现有 Controller 按预期触发 fatal error，证明契约捕获了固定空态偏移和未共享高度的问题。

完成 Controller、工程引用和脚本接线后，输出：

- `SiteGatewayHeaderLayoutPolicyTests passed`
- `SiteTimeZoneReviewSyncContractTests passed`
- `SiteSyncGateways checks passed`

## 完整验证

### 聚合测试

执行 `bash scripts/check_site_sync_gateways.sh`，以下测试全部通过：

- Header layout policy。
- Sync gateways context、state、scan session。
- Gateway Time sync coordinator。
- Gateway cloud generation 与 cloud bridge。
- Site entry timezone policy、contract。
- Review sync contract。
- Sync gateways UI contract。
- 既有 Site timezone UI contract。

最终输出：`SiteSyncGateways checks passed`。

### Diff 检查

执行 `git diff --check`，退出码为 0，无格式错误。

### Generic iPhoneOS 构建

使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 直接构建：

| Scheme | 结果 |
| --- | --- |
| SunSmart | BUILD SUCCEEDED |
| Archipelago | BUILD SUCCEEDED |
| SLG Sync Plus | BUILD SUCCEEDED |
| SylSmart | BUILD SUCCEEDED |

构建仅出现现有的 AppIntents metadata skip warning，没有编译错误。

## 提交与工作区保护

- `1fd7c35e test: add site gateway header layout policy`
- `ab209004 fix: keep site empty state below header`

`project.pbxproj` 原本含有 Gateway Information 等未提交 target 改动。本任务只把 `SiteGatewayHeaderLayoutPolicy` 的 10 行工程引用写入 Git index 并提交，未把用户原有工程改动带入本任务提交。其他既有未提交文件保持原状。

## 验收边界

自动化测试验证了布局数值、Controller 接线、四 target membership 和编译，但不能完全替代真机触摸命中。

真机仍需复测：

- Overview 点击 `Review sync`。
- 选择未绑定 Space 的 Gateway 后点击 `Review sync`。
- Gateway 绑定 Space 后点击 `Review sync`。
- Site 完全没有 Spaces 时点击 `Review sync`。
- Favorites 为空时点击 `Review sync`。
