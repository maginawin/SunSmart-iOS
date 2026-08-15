# Site 空态下拉刷新遮挡修复设计

## 问题与成功标准

Site 页面没有 Space 时，下拉刷新会在刷新回调中重新创建 `EmptyDataView`。刷新完成后，空态视图不得覆盖 Gateway 列表、Gateway 状态控件或 Review Sync 区域；All Spaces 与 Favourites 两个页签行为必须一致。

## 已确认根因

`SiteViewController.emptyFrame(for:spaces:)` 以 `UICollectionView.bounds` 作为空态 frame，再将 Gateway Header 高度累加到 `origin.y`。

正常静止时 `bounds.origin.y` 接近零，空态从 Gateway Header 下方开始。下拉刷新期间 `bounds.origin.y` 是负值；此时 `setupData()` 重新加载列表并调用 `updateEmptyView()`，空态 frame 捕获了该瞬时负偏移。刷新结束只恢复 Collection View 的滚动位置，不会重算已经创建的 `EmptyDataView.frame`，因此空态上移并遮挡 Header 内的 Gateway 控件。

该问题与 Gateway 数据、权限或状态解析无关，属于空态布局基准错误。

## 方案比较

### 方案 A：归一化空态纵坐标（采用）

空态 frame 保留 Collection View 当前的横向位置和尺寸，但纵坐标只由动态 Gateway Header 高度决定，不继承 `bounds.origin.y`。

优点：改动最小；恢复旧实现中纵坐标归零的语义；继续支持 Gateway List、Gateway Status 和 Review Sync 的动态组合高度；不改变通用 `EmptyDataView`。

### 方案 B：使用约束把空态固定在 Header 下方

将 Site 空态从 frame 布局改为 Auto Layout，并绑定到 Header 高度。

优点：后续尺寸变化更自动。缺点：需要调整通用空态 API 或在 Site 页面维护额外约束，改动面较大，并可能改变现有滚动与空态内容定位。

### 方案 C：刷新动画结束后延迟重建空态

等待 Refresh Control 完全复位后再次调用空态更新。

缺点：依赖 UIKit 动画时序，只规避当前触发方式，其他负 content offset 场景仍可能复现，因此不采用。

## 实现边界

- 在现有 `SiteGatewayHeaderLayoutPolicy` 中增加可独立测试的空态 frame 计算。
- `SiteViewController` 的共享 helper 调用该策略，因此同时覆盖 All Spaces 与 Favourites。
- 不修改 Gateway 列表、状态计算、权限、网络请求、刷新结束时机、通用 `EmptyDataView`、本地化和资源。
- 不触碰当前 `SunSmart.xcodeproj/project.pbxproj` 的未提交改动。

## 数据流

1. 用户在无 Space 的 Site 页面下拉刷新。
2. Collection View 在刷新期间产生负的 `bounds.origin.y`。
3. 服务器数据导入完成后，`setupData()` 重载 Collection View 并调用 `updateEmptyView()`。
4. 新策略忽略瞬时纵向 bounds 偏移，将空态起点设置为当前 Gateway Header 的完整高度。
5. EmptyDataView 始终从 Gateway Header 下方开始，不拦截 Header 内的 Gateway 控件。

## 测试与验收

- RED：增加布局策略测试，输入负 `bounds.origin.y`，断言输出 `origin.y` 等于 Header 高度；现有实现应无法满足该行为。
- GREEN：实现最小 frame 归一化并通过布局策略测试。
- 回归：运行 Site Gateway/Time Zone 聚焦检查脚本，确保动态 Header 与既有空态契约不回退。
- 静态质量：运行 `git diff --check`。
- 构建：按项目规则运行 SunSmart 的 generic iPhoneOS Debug 无签名构建。
- 自动化验证不等同于真机下拉刷新和视觉验收；最终仍需在真实设备上确认两个页签的触摸与显示。

## 规格自检

- 无占位内容或未决业务规则。
- 修复范围仅限 Site 空态 frame 计算。
- All Spaces 与 Favourites 的共享行为已明确。
- 不改变任何用户可见文案，因此不涉及国际化变更。
