# Collection View Batch Update Crash Fix Plan

## 目标

修复 Bugly 中 `ScenesViewController` 和 `TimedViewController` 的 `UICollectionView` invalid batch updates 崩溃，避免在列表 item 数量已经变化时仍执行 `reloadItems` 局部刷新。

本计划只覆盖场景列表和日程列表的崩溃修复，不重构全局数据模型，不引入新的架构依赖，不修改 Auth 信息。

## 根因确认

当前两个列表页面都直接用全局可变数据作为 data source：

- `ScenesViewController.visibleScenes` 实时读取 `MeshNetworkManager.instance.scenes` 并过滤应急消防保留场景。
- `TimedViewController` 实时读取 `MeshNetworkManager.instance.schedules`。

同时，通知回调中会调用 `reloadItems`：

- `sceneDataUpdateNotificationName` -> `ScenesViewController.reloadCollectionItem(scene:)`
- `scheduleDataUpdateNotificationName` -> `TimedViewController.reloadCollectionItem(schedule:)`

当新增、删除、同步成功、返回同步页、保存设置等路径改变了全局数组数量后，collection view 的更新前数量和更新后 data source 数量不一致，而本次 UI 操作仍只是局部 reload，于是触发 UIKit 一致性断言。

## 修复策略

### 策略 1：列表页持有稳定快照

在列表控制器内维护页面级快照：

- `ScenesViewController` 增加 `scenes` 快照，来源仍是 `visibleScenes`。
- `TimedViewController` 增加 `schedules` 快照，来源仍是 `MeshNetworkManager.instance.schedules`。

collection view data source、cell 数据、点击、长按、item 高度、底部计数、空页面判断都使用页面快照。

### 策略 2：局部刷新只处理数量不变的内容变化

`reloadCollectionItem` 不再直接读取全局数组并调用 `reloadItems`。新的判断规则：

- 重新生成新快照。
- 如果新旧快照数量不同，更新快照并 `reloadData()`。
- 如果目标对象在旧快照或新快照中不存在，更新快照并 `reloadData()`。
- 如果目标对象 index 改变，更新快照并 `reloadData()`。
- 如果 collection view 当前 item 数和旧快照数量不一致，更新快照并 `reloadData()`。
- 只有数量一致、index 一致、collection view 当前数量一致时，才更新快照并 `reloadItems`。

### 策略 3：通知语义收紧

通知发送方按数据变化类型选择通知：

- 新增或删除场景/日程：发 refresh 通知。
- 纯内容变化且列表数量不变：可发 data update 通知。
- 不能确定是否影响数量：发 refresh 通知。

快照防御是主修复，通知语义审计是配套收敛，避免继续制造错误刷新路径。

## 修改范围

### 文件 1：`SunSmart/Main/Scene/Controller/ScenesViewController.swift`

改动点：

- 增加场景列表页面快照。
- `updateUI()` 刷新快照后再更新底部计数、空页面和 collection view。
- `updateScenesEmptyUI()` 改为使用快照数量判断。
- `reloadCollectionItem(scene:)` 改为“新旧快照对比 + 安全局部刷新/全量刷新兜底”。
- `numberOfItemsInSection`、`cellForItemAt`、`didSelectItemAt`、长按逻辑、添加上限判断改为使用快照。
- `createSceneCallback` 中不要只 `reloadData()`，需要同步刷新快照和 `space.sceneCount`。

保留点：

- `visibleScenes` 的应急消防保留场景过滤逻辑不变。
- 删除场景、执行场景、权限判断和 UI 布局不做无关重构。

### 文件 2：`SunSmart/Main/Timed/Controller/TimedViewController.swift`

改动点：

- 增加日程列表页面快照。
- `updateUI()` 刷新快照后再更新底部计数、空页面和 collection view。
- `updateEmptyUI()` 改为使用快照数量判断。
- `reloadCollectionItem(schedule:)` 改为“新旧快照对比 + 安全局部刷新/全量刷新兜底”。
- `numberOfItemsInSection`、`cellForItemAt`、`sizeForItemAt`、`didSelectItemAt`、添加上限判断改为使用快照。
- 启用/禁用日程会改变 cell 高度，若安全局部刷新仍有布局风险，直接全量刷新。

保留点：

- 日程保存、删除、同步逻辑不在本文件中重构。
- 不修改 `Schedule` 模型或 `ScheduleServer` 同步逻辑。

### 文件 3：`SunSmart/Main/Scene/Controller/SceneAddViewController.swift`

审计点：

- 创建场景成功后已经发 `scenesRefreshNotificationName`。
- 模板场景同步成功和返回时又发 `sceneDataUpdateNotificationName`。

计划：

- 对新增场景路径，后续同步成功/返回应继续使用 refresh，避免新增 item 走单项 data update。
- 若仅是同步状态或成员内容变化且场景已存在，才保留 data update。

### 文件 4：`SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`

审计点：

- `saveAction()` 和 `syncBtnAction()` 多处发送 `sceneDataUpdateNotificationName`。

计划：

- 设置页保存通常是修改已存在场景，可保留 data update。
- 但如果保存会触发列表可见数量变化，快照防御会兜底全量刷新。
- 不在本轮扩展修改场景业务模型，只保证列表层不崩溃。

### 文件 5：`SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift`

审计点：

- 新增日程时会先 append 到 `MeshNetworkManager.instance.schedules`。
- 新增/删除路径应发 `schedulesRefreshNotificationName`。
- 编辑路径才发 `scheduleDataUpdateNotificationName`。

计划：

- 保持新增、删除路径使用 refresh。
- 检查同步成功和返回回调中的 `self.schedule == nil || delete` 判断，确认新增和删除不会进入 data update。
- 对无法确定的路径改为 refresh。

## 执行步骤

### Task 1：修复场景列表快照和刷新防御

1. 在 `ScenesViewController` 增加页面快照。
2. 初始化或 `viewWillAppear` 时通过 `updateUI()` 重建快照。
3. 将 data source 和交互逻辑切换到快照。
4. 改造 `reloadCollectionItem(scene:)`，实现安全局部刷新和全量刷新兜底。
5. 手动检查空页面、底部计数、添加上限和编辑态。

### Task 2：修复日程列表快照和刷新防御

1. 在 `TimedViewController` 增加页面快照。
2. 初始化或 `viewWillAppear` 时通过 `updateUI()` 重建快照。
3. 将 data source、cell 高度和交互逻辑切换到快照。
4. 改造 `reloadCollectionItem(schedule:)`，实现安全局部刷新和全量刷新兜底。
5. 对启用/禁用日程优先使用全量刷新或确保局部刷新时 item 高度一致性安全。

### Task 3：审计通知发送点

1. 检查 `SceneAddViewController` 新增场景同步成功和返回路径。
2. 检查 `SceneSettingsViewController` 保存和同步路径。
3. 检查 `ScheduleAddViewController` 新增、编辑、删除、同步成功、同步返回路径。
4. 将“新增/删除/不确定数量变化”的 data update 调整为 refresh。
5. 不改动与崩溃无关的通知。

### Task 4：构建验证

运行：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

验收：

- `SunSmart` 主 target 编译通过。
- 若修改影响共享文件，应再检查其他品牌 target 的构建风险。

### Task 5：手动回归

场景列表：

- 已有 5 条以上场景时新增模板场景并完成同步。
- 已有 10 条以上场景时进入场景设置页修改成员并保存。
- 删除场景后返回列表。
- 编辑态下切换、删除、取消编辑。
- 应急消防保留场景仍不显示在普通场景列表中。

日程列表：

- 已有 6 条以上日程时新增需要同步的日程。
- 编辑已有日程并同步。
- 删除已有日程。
- 启用/禁用日程，确认 cell 高度和显示状态正确。

验收结果：

- 不再出现 `Invalid batch updates detected` 或 `invalid number of items`。
- 列表数量、空页面、底部计数与真实数据一致。
- 页面不可见期间收到通知，返回页面后能显示最新数据。

## 风险与取舍

- 不采用 diffable data source：当前目标是线上崩溃修复，局部快照和兜底刷新更小、更符合现有代码风格。
- 不统一重构通知系统：通知问题范围较大，本轮只收敛崩溃相关发送点。
- `reloadData()` 会减少局部动画，但可显著降低 collection view 一致性风险，适合该崩溃修复。
- 快照必须在所有读取 index 的路径使用一致，否则仍可能出现越界或刷新不一致。

## 推荐执行顺序

1. 先改 `ScenesViewController`，因为两个 Bugly 栈都指向它。
2. 再改 `TimedViewController`，复用同一安全刷新模式。
3. 最后审计通知发送点，避免新增和删除路径继续发 data update。
4. 构建验证后再做手动回归。
