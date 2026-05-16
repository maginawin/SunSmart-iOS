# Debug 顶部摘要固定设计

## 背景

Debug 页面顶部摘要条当前通过 `SpaceDebugViewController` 的 `tableView.tableHeaderView` 展示。该摘要条包含扫描状态和 `Found / Total` 计数，例如中文环境下的 `已停止` 与 `已找到 x / y`。

由于它属于 table view 的滚动内容，用户向下滚动设备列表时，摘要条会跟随列表滚走。Debug 页面扫描设备时需要持续观察扫描状态和 found count，因此摘要条应固定在页面顶部。

## 目标

- 将 Debug 页面顶部摘要条固定在页面顶部。
- 设备列表在摘要条下方滚动。
- `Lights / Switches / Sensors / Others` 分组标题仍保持当前列表行为，继续跟随设备列表滚动。
- 保留现有摘要条样式、扫描状态文案、found count 更新、设备列表排序和连接行为。

## 非目标

- 不修改 `SpaceDebugSummaryView` 的视觉样式。
- 不修改扫描、停止扫描、重新扫描或连接逻辑。
- 不修改 `SpaceDebugViewModel` 的分组、排序、found 状态或 RSSI 更新逻辑。
- 不调整本地化文案。
- 不影响 Debug 详情页和 UART 页面。

## 确认方案

采用固定 sibling 布局方案：

`SpaceDebugViewController` 根视图包含两个同级子视图：

- 顶部固定的 `summaryView`
- 下方滚动的 `tableView`

`summaryView` 从 `tableView.tableHeaderView` 移出，直接添加到控制器根视图。`tableView` 的顶部约束改为连接到 `summaryView.snp.bottom`，底部、左右继续贴合父视图。

选择原因：

- 改动范围最小，只改变布局归属，不碰业务状态。
- 摘要条脱离 table view 滚动内容后，固定行为由 Auto Layout 自然保证。
- 分组标题仍属于 table view，不会改变用户已确认的列表滚动行为。
- 避免手动处理 `contentOffset` 或 table header 悬停，降低维护成本。

## 设计细节

### 布局

`SpaceDebugViewController.setupUI()` 调整为：

1. 先配置并添加 `summaryView` 到 `view`。
2. 设置 `summaryView` 顶部贴合 `view.safeAreaLayoutGuide.snp.top`，左右贴合父视图，高度保持当前约 `SCRYFrom(68)`。
3. 配置并添加 `tableView` 到 `view`。
4. `tableView` 顶部约束到 `summaryView.snp.bottom`，左右和底部贴合父视图。
5. 删除 `tableView.tableHeaderView = summaryView`。

`SpaceDebugSummaryView` 内部仍保留当前 container inset、白色背景、圆角、状态 label 与计数 label。

### 数据与刷新

`reloadSnapshot()` 继续执行：

- `summaryView.update(state:found:total:)`
- `tableView.reloadData()`

摘要条固定后，found count 和扫描状态仍由同一个 ViewModel snapshot 驱动，不新增状态源。

### 滚动行为

用户滚动设备列表时：

- 顶部摘要条保持可见。
- 设备 cell 正常滚动。
- `Lights / Switches / Sensors / Others` 分组标题仍由 table view 管理，不做固定处理。

## 风险与处理

如果直接把 tableView 继续约束到父视图边缘，会被固定摘要条遮挡。因此需要明确把 tableView 顶部约束到 `summaryView` 底部。

如果没有使用 safe area，导航栏下方可能出现遮挡风险。因此摘要条顶部应贴合 safe area 顶部。

如果后续摘要条高度变化，tableView 顶部约束仍可跟随摘要条底部，无需额外同步 content inset。

## 验证计划

- 静态检查 `SpaceDebugViewController` 不再设置 `tableView.tableHeaderView = summaryView`。
- 静态检查 `summaryView` 被添加到控制器根视图，并拥有固定顶部和高度约束。
- 静态检查 `tableView` 顶部约束到 `summaryView.snp.bottom`。
- 构建 `SunSmart` Debug iOS target，确认无编译错误。
- 真机或模拟器检查 Debug 页面：
  - 向下滚动设备列表时，摘要条保持在顶部。
  - 分组标题仍随列表滚动。
  - 扫描状态和 found count 仍正常刷新。
  - 点击已找到设备的连接行为不变。
