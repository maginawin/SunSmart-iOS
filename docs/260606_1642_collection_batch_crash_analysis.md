# Collection View Batch Update Crash Analysis

## 背景

Bugly 中的 3 条崩溃都是 `NSInternalInconsistencyException`，触发点均在 `UICollectionView` 执行局部刷新时，UIKit 校验到 data source 更新前后的 item 数量与本次 batch update 描述不一致。

涉及页面：

- `SunSmart/Main/Scene/Controller/ScenesViewController.swift`
- `SunSmart/Main/Timed/Controller/TimedViewController.swift`
- 通知发送方包括 `SceneAddViewController`、`SceneSettingsViewController`、`ScheduleAddViewController`

## 共同根因

列表控制器的 data source 没有持有稳定的页面快照，而是直接读取全局可变数据：

- `ScenesViewController` 的数量来自 `visibleScenes`，它实时过滤 `MeshNetworkManager.instance.scenes`。
- `TimedViewController` 的数量来自 `MeshNetworkManager.instance.schedules`。

同时，通知回调中会执行局部刷新：

- `sceneDataUpdateNotificationName` 触发 `ScenesViewController.reloadCollectionItem(scene:)`
- `scheduleDataUpdateNotificationName` 触发 `TimedViewController.reloadCollectionItem(schedule:)`

局部刷新本身只适用于“item 内容变化，item 数量不变”。但当前业务中，新增、删除、同步成功、同步失败返回、设置页保存等路径会直接修改全局 scenes 或 schedules 数组，或者改变 `visibleScenes` 的过滤结果。于是 collection view 在一次局部刷新期间看到：

- 更新前 item 数是旧值。
- 更新后 data source 返回的是全局数组的新值。
- 本次操作却只声明了 reload item，或没有声明 insert/delete。

这会触发 UIKit 的内部一致性断言并崩溃。

## 崩溃 1：ScenesViewController，5 -> 1

崩溃信息：

- 更新前：1 section，[5]
- 更新后：1 section，[1]
- 更新操作：delete item 0、insert item 0
- 栈顶业务方法：`ScenesViewController.reloadCollectionItem(scene:)`
- 通知来源：`SceneAddViewController.pushToSyncDeviceVc(scene:)` 的同步成功回调

关键链路：

1. `SceneAddViewController` 创建场景后先发 `scenesRefreshNotificationName`。
2. 模板创建并完成同步后，又发 `sceneDataUpdateNotificationName`。
3. `ScenesViewController` 收到 data update 后调用 `reloadItems`。
4. 此时 `visibleScenes` 对应的全局 scenes 列表已经不是 collection view 更新前的 5 条，而变成 1 条。
5. UIKit 将 `reloadItems` 视作删除再插入同一 item，但 data source 总数额外减少 4 条，因此崩溃。

判断：

这不是 cell 内容渲染问题，而是把“列表结构变化”误走成了“单个 item 内容变化”的刷新路径。

## 崩溃 2：TimedViewController，6 -> 7

崩溃信息：

- 更新前：section 0 有 6 条
- 更新后：section 0 有 7 条
- 更新操作：0 inserted、0 deleted、0 moved
- 栈顶业务方法：`TimedViewController.reloadCollectionItem(schedule:)`
- 通知来源：`ScheduleAddViewController.pushToSyncDevices(schedule:delete:)`

关键链路：

1. `ScheduleAddViewController.saveBtnAction()` 新增日程时，保存成功后直接 append 到 `MeshNetworkManager.instance.schedules`。
2. 新增日程如需同步，会进入 `pushToSyncDevices`。
3. 同步成功或返回时，按当前代码意图新增路径应发 `schedulesRefreshNotificationName`。
4. 但 Bugly 栈显示实际进入了 `scheduleDataUpdateNotificationName` 的局部刷新路径。
5. `TimedViewController.reloadCollectionItem(schedule:)` 执行时，data source 已经从 6 条变 7 条，本次局部刷新没有声明新增 item，因此崩溃。

判断：

这类崩溃说明通知语义和数据变化不一致：数据源数量已增加，但 UI 收到的是“更新单项”的通知，或通知到达时序与新增 refresh 交错。

## 崩溃 3：ScenesViewController，10 -> 15

崩溃信息：

- 更新前：section 0 有 10 条
- 更新后：section 0 有 15 条
- 更新操作：1 inserted、1 deleted
- 栈顶业务方法：`ScenesViewController.reloadCollectionItem(scene:)`
- 通知来源：`SceneSettingsViewController.saveAction()`

关键链路：

1. `SceneSettingsViewController.saveAction()` 修改场景成员和场景执行数据。
2. 保存或同步完成后发 `sceneDataUpdateNotificationName`。
3. `ScenesViewController` 进入 `reloadCollectionItem(scene:)`。
4. 局部刷新期间，`visibleScenes` 从 10 条变成 15 条。
5. `reloadItems` 的内部 delete/insert 只能表达“同一个 item 重载”，不能覆盖额外新增 5 条场景，因此崩溃。

判断：

这个崩溃与崩溃 1 是同一类，只是方向相反：崩溃 1 是全局数据减少，崩溃 3 是全局数据增加。两者都证明 `visibleScenes` 不是稳定快照，不能直接支撑局部刷新。

## 修复方案

### 首选方案：列表页面维护稳定快照

在 `ScenesViewController` 中新增页面级 `scenes` 快照，在 `TimedViewController` 中新增页面级 `schedules` 快照。collection view 的 data source、cell 读取、点击、长按、计数显示均使用快照，而不是每次实时读取全局数组。

刷新策略：

- 全量刷新：重新生成快照，然后 `reloadData()`。
- 单项刷新：先比较旧快照和新快照的数量及对应元素位置。
- 只有当数量不变、目标 item 仍在同一 index 且 collection view 当前 item 数匹配快照时，才调用 `reloadItems`。
- 只要数量变化、index 不存在、index 改变、collection view 正在 batch update 或窗口不可见，就退回全量刷新。

优点：

- 从根上消除 UIKit 更新前后 data source 不稳定的问题。
- 修复 Scenes 和 Timed 两个页面的同类崩溃。
- 不依赖猜测具体通知顺序，容错更强。

### 配套方案：收紧通知语义

通知发送方应严格区分：

- 新增或删除 item：只发 refresh 通知。
- 仅修改名称、开关状态、同步状态、显示内容且 item 数不变：可发 data update 通知。
- 无法确定是否影响数量：发 refresh 通知。

需要重点检查：

- `SceneAddViewController.pushToSyncDeviceVc(scene:)`
- `SceneSettingsViewController.saveAction()`
- `SceneSettingsViewController.syncBtnAction()`
- `ScheduleAddViewController.pushToSyncDevices(schedule:delete:)`
- `ScheduleAddViewController.viewDidClickSyncFailedAction(_:)`

### 防御方案：局部刷新前做一致性校验

即使采用快照，也应在 `reloadCollectionItem` 前加防御条件：

- 目标 item 必须存在于当前快照。
- `collectionView.numberOfSections` 至少为 1。
- `collectionView.numberOfItems(inSection: 0)` 必须等于当前快照数量。
- 如果 collection view 不在 window 上，记录待刷新状态，不做局部刷新。
- 不满足条件时执行全量刷新或延迟到下次 `viewWillAppear`。

## 实施计划

### Task 1：ScenesViewController 快照化

文件：`SunSmart/Main/Scene/Controller/ScenesViewController.swift`

步骤：

1. 增加页面级 scenes 快照，初始化和 `updateUI()` 时从 `visibleScenes` 重建。
2. 将 data source、cellForItem、点击、长按、数量显示、上限判断改为读取快照。
3. 调整 `reloadCollectionItem(scene:)`：先生成新快照，与旧快照比较；数量或 index 变化则全量刷新；仅内容变化才局部刷新。
4. 保留 `visibleScenes` 作为生成快照的来源，不改变全局数据模型。

### Task 2：TimedViewController 快照化

文件：`SunSmart/Main/Timed/Controller/TimedViewController.swift`

步骤：

1. 增加页面级 schedules 快照。
2. 将 data source、cellForItem、sizeForItem、didSelect、数量显示、上限判断改为读取快照。
3. 调整 `reloadCollectionItem(schedule:)`：数量或 index 变化时全量刷新，只有数量不变且目标 index 稳定时局部刷新。
4. 保证 enable/disable 操作仍能刷新对应 cell 高度；高度变化如果触发布局不稳定，也回退全量刷新。

### Task 3：通知语义审计

文件：

- `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`
- `SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift`
- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift`

步骤：

1. 标记每个通知发送点是新增、删除、纯内容更新还是无法确定。
2. 新增/删除统一发 refresh。
3. 纯内容更新保留 data update。
4. 如果同一路径已经先修改全局数组，再进入同步页，后续同步成功不得再发错误类型的 data update。

### Task 4：验证

推荐验证方式：

1. 直接运行 iOS 真机构建校验：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
2. 手动验证场景：
   - 5 条以上场景时新增模板场景并完成同步。
   - 10 条以上场景时进入场景设置页修改成员，保存并同步。
   - 删除场景后返回场景列表。
3. 手动验证日程：
   - 6 条以上日程时新增需要同步的日程。
   - 编辑已有日程并同步。
   - 删除已有日程。
4. 验证期望：
   - 不再出现 collection view invalid update 崩溃。
   - 列表数量、空页面、底部计数与实际数据一致。
   - 编辑态和普通态下刷新行为一致。

## 风险点

- Scenes 页面当前 `visibleScenes` 会过滤应急消防保留场景，快照化时必须继续沿用该过滤逻辑。
- Timed 页面 item 高度依赖 `schedule.enabled`，局部刷新可能伴随 layout 更新；如果高度变化仍触发异常，启用/禁用也应优先全量刷新。
- 多 target 共用这些 Swift 文件，修复后至少需要检查 `SunSmart` 主 target；如时间允许，再检查其他品牌 target 是否受影响。
