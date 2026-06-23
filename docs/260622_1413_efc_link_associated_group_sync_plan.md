# 虚拟 EFC LINK 后按 Associated Groups 触发 Sync 的分析与修复方案

## 背景

虚拟 EFC 设备在 Edit 页面 LINK 真实 EFC 后，需要根据当前 `Associate with group(s)` 决定是否进入 `Sync device(s)`：

- 无 associate groups：LINK 成功后停留在 Edit 页面。
- associate groups 全部有 members：LINK 成功后进入 `Sync device(s)`，下发真实组成员的 Model 订阅配置。
- associate groups 全部为空 groups：LINK 成功后停留在 Edit 页面，因为没有可下发的组订阅任务。
- associate groups 混合有 members 与空 groups：LINK 成功后进入 `Sync device(s)`，只展示并同步有 members 的 groups；空 groups 不展示任务。

## 当前代码事实

### LINK 后 Sync 入口

`LinkedEmerFireEditVC.openSyncAfterLinkedDeviceIfNeeded()` 当前以三个条件判断是否进入 Sync：

- 当前 EFC 存在。
- 已绑定真实设备。
- `device.configuration.hasSyncIntent == true`。

之后调用 `EmergencyFireControllerSyncPlanner.makeAssociatedGroupItems()` 生成 associated group items，只要 items 非空就 push `SyncDevicesViewController`。

这说明当前 gate 判断的是“是否有关联 group item”，不是“是否存在真实可下发任务”。

### Associated group item 生成

`EmergencyFireControllerSyncPlanner.makeAssociatedGroupItems()` 当前会遍历 `activeLightLCGroupAddresses`，每个 group 都返回一个 `EmergencyFireControllerSyncItem`。

当 group 没有 members 时：

- `group.nodes` 为空。
- 展开的 `tasks` 为空。
- 但函数仍返回一个 `tasks` 为空的 item。

这会导致“全部空组”场景在入口层看起来有 items，但实际没有任何可下发命令。

### Sync 页面展示

`SyncDevicesViewController.appendEmergencyFireControllerItems(...)` 对非 controller item 会按 `item.tasks` 分组成 device models。

当 `item.tasks` 为空时：

- `deviceModels` 为空。
- 该 group 不会被 append 到 UI。

所以空 group 当前不会展示成 Sync 任务。混合场景下，有 members 的 groups 会展示，空 groups 会被 UI 层丢掉。

### Sync 成功后的返回行为

LINK 触发的 Sync 当前只设置 `syncSuccessCallback` 做数据刷新和通知，不会主动关闭 Sync 页面。

SAVE 触发的 Sync 才会在成功回调中调用 `finishAfterSuccessfulSaveSync()`，从而返回上一层或关闭页面。

因此，如果实测 “LINK 进入 Sync 后成功自动回到 Edit 页面”，当前代码本身不能直接解释这一点；更像是：

- 实际走到了 SAVE 同步路径；或
- 用户点击了 Sync 页返回按钮；或
- 还有其他外部路径触发了关闭。

## 与测试结果的符合情况

| 场景 | 当前代码是否能解释 | 结论 |
| --- | --- | --- |
| 无 associate groups | 能解释 | `hasSyncIntent` 为 false 时不会进入 Sync，符合预期。 |
| 全部有 members | 能解释进入 Sync | 会生成真实 tasks 并进入 Sync，符合进入 Sync 的预期；但 LINK 路径不应自动返回 Edit，若实测自动返回，需要确认实际触发路径。 |
| 全部空 groups | 能解释异常 | planner 返回空任务 items，入口误判为需要 Sync；Sync 页面又没有可展示任务，可能表现成直接完成或返回。入口 gate 不严谨。 |
| 混合 groups | 基本能解释 | 有 members 的 groups 会展示并同步，空 groups 会被 UI 层跳过；但空任务 item 仍被传入 Sync 页面，语义不干净，建议在进入 Sync 前过滤。 |

## 根因

当前 LINK 后的 Sync 入口把 “associated group item 非空” 当成 “存在需要同步的组订阅任务”。

但对 EFC associated groups 来说，真正的 Sync 任务应该是：

- group 存在；
- group 内存在真实成员；
- planner 能为这些成员生成 Model subscription tasks。

空 group 只有配置关系，没有真实目标设备，也没有可下发的 Model 订阅命令。因此它不应该触发 Sync 页面，也不应该造成空任务成功。

## 推荐修复方案：方案 A

在 `LinkedEmerFireEditVC.openSyncAfterLinkedDeviceIfNeeded()` 中收紧 LINK 后进入 Sync 的条件：

1. 保持现有前置条件：
   - EFC 已绑定真实设备。
   - 当前配置存在 sync intent。

2. 调用 `makeAssociatedGroupItems()` 后，先过滤掉 `tasks` 为空的 associated group item。

3. 如果过滤后没有任何 item：
   - 不进入 `SyncDevicesViewController`。
   - LINK 完成后停留在 Edit 页面。
   - 对“全部空组”按“没有可下发组订阅任务”处理。

4. 如果过滤后存在 item：
   - 只把过滤后的 items 传给 `SyncDevicesViewController`。
   - Sync 页面只展示有 members 且有真实下发任务的 groups。
   - 空 groups 不展示任务。

5. LINK 触发的 Sync 成功后暂不新增自动关闭逻辑，保持当前 LINK 路径只刷新数据；如果产品预期是“Sync 成功后必须停留在 Sync 成功页”，该方案正好符合。如果产品预期是“Sync 成功后自动回 Edit”，则需要单独明确后再改成功回调。

## 不推荐方案

### 方案 B：在 Planner 内全局过滤空任务 item

优点是数据源更干净。

缺点是会影响所有调用 `makeAssociatedGroupItems()` 的入口，当前需求只明确 LINK 后行为，先在 LINK 入口过滤影响面更小。

### 方案 C：只在 SyncDevicesViewController 内处理空页面

优点是改动集中在 Sync 页。

缺点是入口仍会错误地认为有 Sync 任务，可能继续出现空任务成功、空进度或错误跳转语义。

## 验证计划

1. 静态 contract：
   - LINK 后 `openSyncAfterLinkedDeviceIfNeeded()` 必须过滤空 `tasks` items。
   - LINK 后传入 `SyncDevicesViewController` 的 items 不能包含空任务 associated group。

2. 手工回归：
   - 无 associate groups：LINK 成功后停留 Edit。
   - 全部有 members：LINK 成功后进入 Sync，展示并下发 group member Model subscription。
   - 全部空 groups：LINK 成功后停留 Edit，不进入空 Sync。
   - 混合 groups：LINK 成功后进入 Sync，只展示有 members 的 groups；空 groups 不展示。

3. 构建验证：
   - 使用 iPhoneOS `xcodebuild` 验证 `SunSmart` Debug 构建。

## 待确认点

需要确认 LINK 触发的 Sync 成功后的页面行为：

- 选项 1：成功后停留在 Sync 成功页，用户手动返回 Edit。
- 选项 2：成功后自动回到 Edit 页面。

从当前代码看，LINK 路径更接近选项 1；SAVE 路径才会自动关闭。
