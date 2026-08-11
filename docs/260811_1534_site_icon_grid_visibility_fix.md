# Edit Site 的 Site Icon 列表可见性修复

## 问题

当 Site 的 Time Zone 为 `Not configured` 时，Edit Site 页面能显示 `Site Icon` 标题，但标题下方已有的 28 个图标没有显示。

## 根因

Site Icon 的 UICollectionView 初始高度被设置为 1pt，随后依赖 `viewDidLayoutSubviews` 获取列表宽度并更新高度。

Time Zone 未配置时，页面加载期间会把 Time Zone 容器从 80pt 收缩到 44pt。在该布局时序下，高度补算可能拿不到有效列表宽度并提前返回，使 UICollectionView 一直保留 1pt 高度，所有图标因此被裁剪。

## 修复

- 删除 1pt 占位高度和 `viewDidLayoutSubviews` 中的二次高度更新。
- 根据 4 列、28 个图标、行间距和列间距，使用 UICollectionView 自身宽度直接建立高度约束。
- 保留原来的正方形图标尺寸及 4 列布局，不改动 Time Zone、图标选择和保存流程。
- 增加 UI 契约回归，禁止重新引入 1pt 占位或生命周期补算，并要求列表高度直接关联列表宽度。

## 验证

- TDD 回归：新增断言后先失败，完成布局修复后通过。
- Time Zone 相关 7 个单元/契约测试全部通过。
- 以下 Debug、generic iPhoneOS、关闭签名构建均成功：
  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`
- 构建输出仍包含工程既有的资源名冲突、弃用 API 和重复编译项警告，本次未扩大范围处理。

## 尚需真机验收

- Time Zone 为 `Not configured` 时进入 Edit Site，确认 `Site Icon` 下显示完整图标列表。
- Time Zone 已配置时确认图标列表仍正常显示。
- 在不同屏幕宽度及横竖屏变化后确认图标保持 4 列并可完整滚动查看。
