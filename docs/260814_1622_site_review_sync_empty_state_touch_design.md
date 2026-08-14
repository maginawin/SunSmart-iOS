# Site Review sync 空态触摸修复设计

## 背景与复现

Site 页面存在需要同步时区的 Gateway 时，会在 Gateway Header 中显示 `Review sync` 提示卡片。

稳定复现路径：

1. Site 内存在两个需要同步时区的 Gateway。
2. Gateway 未绑定任何 Space。
3. 选择 `Overview` 时，点击 `Review sync` 可以进入 `Sync gateways`。
4. 选择任意未绑定 Space 的 Gateway 时，`Review sync` 仍然可见，但点击没有响应。
5. 给该 Gateway 绑定一个 Space 后，点击恢复正常。

## 根因

选择具体 Gateway 后，页面会把当前显示的 Space 数组过滤为该 Gateway 所绑定的 Spaces。未绑定 Space 时，显示数组为空，`updateEmptyView()` 因而向 CollectionView 添加 `EmptyDataView`。

当前空态视图使用固定纵向起点：

- Site 本身存在 Spaces 时，空态从 96pt 开始。
- Site 本身没有 Spaces 时，仅根据是否存在可见 Gateway 增加 48pt。
- Favorites 为空时同样使用固定的 96pt 或 0pt。

与此同时，Gateway Header 的实际高度是动态的：

- Gateway list：48pt。
- Gateway status：可见时增加 48pt。
- `Review sync`：可见时增加 64pt。

在本次复现场景中，`Review sync` 从约 96pt 开始，而后添加的 `EmptyDataView` 也从 96pt 开始。空态视图位于更高的视图层级并接收触摸，因此覆盖了 `Review sync` 卡片的交互区域。卡片仍可透过透明背景看到，但按钮事件无法到达。

Overview 或已绑定 Space 的 Gateway 不会产生这一覆盖关系，所以导航行为正常。`showSyncGatewaysPage()` 的导航条件不是本次问题的断点。

## 目标

- 空态区域始终从当前实际 Gateway Header 底部开始。
- `Review sync` 卡片的可见区域与可交互区域保持一致。
- Header 高度和空态起点使用同一套布局规则，避免固定数值再次漂移。
- 同时覆盖 All Spaces、Favorites、Site 无 Space、选中无绑定 Space Gateway 等空态组合。
- 不改变 Gateway 权限、Space 绑定、时区判定、Sync gateways 数据选择或导航规则。

## 方案

采用共享 Header 高度计算的最小修复。

新增一个无副作用的布局策略，根据以下两个动态状态计算 Header 高度：

- 是否显示 Gateway status。
- 是否显示 `Review sync`。

Gateway list 保持现有基础高度。Gateway Header 的 `referenceSizeForHeaderInSection` 和空态视图 frame 的纵向起点共同消费该计算结果。

空态布局分别使用对应页面当前的显示 Space 数组计算：

- All Spaces 使用 `allSpaces`。
- Favorites 使用 `favouriteSpaces`。

这保证空态起点与相同 CollectionView 的 Header 可见状态一致，而不是继续依赖 48pt、96pt 等分散的固定偏移。

## 不采用的方案

### 禁用 EmptyDataView 触摸

虽然可以让点击穿透，但错误的布局重叠仍然存在；以后空态增加按钮时还会产生新的冲突。

### 调整 Header 与 EmptyDataView 的层级

CollectionView supplementary view 会复用和重建，手动维护层级容易随滚动、刷新和复用失效，并且没有消除错误的 frame。

### 修改导航条件

点击事件当前没有到达 Header 回调，导航逻辑尚未执行。修改导航条件不能修复触摸拦截。

## 测试设计

先增加失败回归测试，再修改生产代码。

纯布局策略测试覆盖：

- 仅 Gateway list 时，Header 高度为 48pt。
- Gateway list 和 Gateway status 可见时，高度为 96pt。
- Gateway list、Gateway status 和 `Review sync` 同时可见时，高度为 160pt。
- Gateway status 隐藏但 `Review sync` 可见时，高度为 112pt。

Controller 契约测试覆盖：

- Header size 和 All Spaces 空态 frame 使用同一个高度计算入口。
- Favorites 空态 frame 使用对应 Favorites 状态的高度计算结果。
- 不再使用固定 96pt 作为空态起点。
- `Review sync` 仍绑定到现有 `showSyncGatewaysPage()`，不修改业务路由。

现有 `scripts/check_site_sync_gateways.sh` 必须继续通过。

## 构建与验收边界

静态验证包括：

- 新增布局策略测试。
- Site Review sync 与 Sync gateways 现有聚合测试。
- `git diff --check`。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 的 generic iPhoneOS Debug 构建，关闭代码签名。

自动化测试和构建可以验证布局规则、代码接线和多 target 编译，但不能完全替代真机触摸命中验收。真机应复测：

- Overview 点击 `Review sync`。
- 选择无绑定 Space 的 Gateway 后点击 `Review sync`。
- Gateway 绑定 Space 后点击 `Review sync`。
- Site 完全没有 Spaces 时点击 `Review sync`。
- Favorites 为空时点击 `Review sync`。

## 改动范围

改动限定为：

- 新增 Foundation-only 的 `SiteGatewayHeaderLayoutPolicy.swift`，承载共享 Header 高度规则，并加入四个 App target。
- `SiteViewController` 的 Header 高度和空态 frame 计算。
- 新增对应纯策略测试，并扩充现有 Controller 契约测试。
- 将新增纯策略测试接入 `scripts/check_site_sync_gateways.sh`。

不修改 `EmptyDataView` 全局行为，不修改本地化、资源、SDK 或依赖。工程文件只增加新布局策略对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 的 Sources 引用，不改变其他 target 配置。
