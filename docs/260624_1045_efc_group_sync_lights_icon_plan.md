# EFC Associated Groups 同步缺口与 Lights 底部同步图标方案

## 背景

上一份分析文档确认：`Site - Space - Main - Lights` 底部同步图标只看 Lights 页当前灯节点的 `Node.needSync`。点击后也只把 `devices.filter { $0.needSync }` 传给 `SyncDevicesViewController(type: .devices(...))`。

本次需求关注 EFC 设备的 associated groups：如果 associated group 里的灯设备没有成功订阅 EFC 内部 publish group，Lights 页面底部是否会像 profile、scene、schedule、switch 等同步缺口一样显示同步图标。

预期：需要显示，并且点击后能把这些 EFC group subscription 任务同步掉。

## 当前结论

问题真实存在：当前不会按预期显示。

原因是 EFC associated-group subscription 的检查只存在于 EFC 专用 planner 中，没有进入 Lights 底部图标依赖的 `Node.needSync` / `Node.getSyncData(type: .all)` 链路。

## 代码事实

### Lights 底部同步入口

`DeviceLightsViewController.loadDevices` 只加载 `deviceType == .light` 的真实节点。

`DeviceLightsViewController.updateUI` 在非编辑状态下使用：

- `devices.contains { $0.needSync }`

控制 `footerView.syncBtn.isHidden`。

`DeviceLightsViewController.functionDidClickSync` 使用：

- `devices.filter { $0.needSync }`
- `SyncDevicesViewController(type: .devices(syncDevices))`

因此只有 `Node.needSync == true` 的灯节点才会让底部图标显示并进入同步页。

### `Node.needSync` 当前不包含 EFC

`Node.needSync` 缓存并调用 `getNeedSync()`，并额外合并 `needSyncGroupData`。

`Node.getNeedSync()` 当前覆盖：

- key bind / initialize
- group subscribe / unsubscribe
- profile
- scene
- schedule
- switch proxy / linked switches
- proximity lighting
- restoreData 对比出来的部分 device parameters
- dongle / gateway 分支

`Node.getSyncData(type: .all)` 也只展开上述这些同步数据，没有 EFC associated-group subscription 相关数据。

### EFC 同步任务存在，但在专用链路中

`EmergencyFireControllerSyncPlanner` 已经能判断 associated group 里的节点是否缺 EFC publish group 订阅：

- 固定候选 model：Generic OnOff Server、Light Lightness Server、Light CTL Server、Light CTL Temperature Server、Light HSL Server、Light LC Server。
- 对 active associated group 内每个节点调用 `makeAssociateTasks(...)`。
- `makeAssociationSubscriptionTasks(...)` 检查 `!model.isSubscribed(to: publishGroup)`，缺订阅就生成 `ConfigModelSubscriptionAdd`。

这些任务当前会在两个路径出现：

- EFC Edit / LINK 后的 `SyncDevicesViewController(type: .emergencyFire(...))`
- Group Members 变更时 `SyncDevicesViewController(type: .group(...))` 内部附加的 `appendEmergencyFireControllerGroupMutationItems(...)`

但是它们不会被 Lights 页的 `devices.contains { $0.needSync }` 发现，也不会被 `.devices` 分支的 `node.getSyncData(type: .all)` 展开。

## 需求边界

本次建议处理 EFC associated groups 中两类灯设备侧同步缺口：

- 当某个灯所在 group 是 EFC 的 active associated group；
- 且该灯实际存在 EFC 需要订阅的候选 model；
- 且这些 model 尚未订阅到该 EFC 的内部 publish group；
- 则该灯应被视为需要同步，Lights 底部同步图标应显示；
- 当 EFC 配置变更导致某个 associated group 进入 pending cleanup；
- 且该 group 内灯设备仍订阅着 EFC 内部 publish group；
- 则该灯也应被视为需要同步，Lights 底部同步图标应显示，并执行退订。

点击 Lights 底部同步图标后，应把这些 EFC subscription 任务并入同一次 `SyncDevicesViewController(type: .devices(...))` 同步流程。

暂不建议把 EFC controller self-config 纳入 Lights 底部图标。controller self-config 属于 EFC 设备自身配置，仍由 EFC Edit / LINK / Add Device 等入口负责。

删除 EFC 设备本体时的 delete cleanup 不纳入 Lights 底部同步。它更像设备删除流程收尾，不是 Lights 页常规同步。

## 方案选项

### 方案 A：并入节点通用同步链路（推荐）

做法：

1. 在 EFC planner 附近新增一个 helper，用于按单个 light node 查询 EFC associated-group subscription 缺口。
2. 将该结果接入 `Node.getNeedSync()` / `getNeedSyncGroup(group:)`，让 `Node.needSync` 能识别 EFC subscription 缺口。
3. 将该结果接入 `Node.getSyncData(type: .all)`，新增 EFC subscription 同步数据。
4. 在 `SyncDevicesViewController.getSyncDeviceModel(group:nil,node:)` 中把该同步数据转换为 `DeviceOperationType.configuration(... .emergencyFireController(...))` step。
5. 同步成功后沿用现有 `node.updateData(...)` 和 `node.clearSyncStateCache()`，让下一次 `needSync` 重新计算并隐藏图标。

优点：

- 与 profile、scene、schedule、switch 的模型一致。
- Lights 页不用写特殊判断，底部 icon 继续只依赖 `Node.needSync`。
- 点击 icon 后仍走 `.devices` 通用同步页，用户体验一致。
- 后续其他入口只要复用 `Node.needSync` / `.devices`，也能自然得到 EFC subscription 状态。

风险：

- `Node+SyncData.swift` 会开始依赖 EFC sync 类型，需要注意 target 编译顺序和模块边界。
- 需要给 `NodeSyncData.level`、message handle、step 展开都补齐 EFC 分支。

### 方案 B：只在 Lights 页额外判断 EFC 缺口

做法：

1. `DeviceLightsViewController` 展示 icon 时使用 `node.needSync || node.hasEmergencyFireAssociationSyncIssue(...)`。
2. 点击同步时把普通 `needSync` 节点和 EFC 缺口节点一起传入或分别打开同步页。
3. `.devices` 分支额外 append EFC tasks。

优点：

- 改动相对局部，不需要让 `Node+SyncData` 依赖 EFC 类型。

缺点：

- `Node.needSync` 仍然不代表真实完整同步状态。
- 同步真值分散到 Lights 页和 SyncDevices 页，后续更容易出现显示与点击不一致。
- 不够符合“跟 profile、scene、schedule、switch 一样”的预期。

### 方案 C：保持 EFC 专用同步入口，只改 EFC cell/详情提示

做法：

继续只通过 EFC Others cell / Edit / LINK 后同步入口处理 associated-group subscription。

优点：

- 改动最少。

缺点：

- 不满足本次预期。
- 用户在 Lights 页面看不到关联灯的未同步状态。

## 推荐方案

推荐方案 A。

核心理由：本需求本质上是“灯设备缺少一个由 EFC 配置派生出来的 group subscription”，与已有 profile、scene、schedule、switch 同属于灯设备侧配置缺口。把它放进 `Node.needSync` 和 `Node.getSyncData(type: .all)`，才能让显示、点击、同步和成功后刷新保持同一套真值。

## 计划

1. 新增 EFC node-level sync helper
   - 输入：light node、当前 Space。
   - 输出：该 node 需要补齐的 EFC `associationSubscription` tasks，以及配置变更产生的 `associationCleanup` tasks。
   - 复用 `EmergencyFireControllerSyncPlanner.makeAssociateTasks(...)`，不复制 model 列表和订阅判断。
   - active associated group 生成订阅补齐任务。
   - pending unassociate group 生成退订清理任务。
   - 不处理删除 EFC 设备本体产生的 delete cleanup。

2. 扩展 `NodeSyncData`
   - 增加 EFC association 类型，保存 controller data 与 task 列表。
   - 为 `level` 设置与 switch subscription 接近的优先级。
   - `getMessageHandles(node:)` 返回 task message handles。

3. 扩展 `Node.getNeedSync()` / `getSyncData(type: .all)`
   - 当 node 是 light 且属于 EFC active associated group 时，检查缺失订阅。
   - 当 node 所在 group 是 EFC pending unassociate group 时，检查仍需退订的 EFC publish group 订阅。
   - 如果存在任务，`getNeedSync()` 返回 true。
   - `.all` 生成对应同步数据。

4. 扩展 `SyncDevicesViewController.getSyncDeviceModel(...)`
   - 把 EFC subscription 同步数据转成配置 step。
   - 使用现有 `DeviceOperationType.configuration(node:type:.emergencyFireController(task:data))`。
   - 同步成功后沿用现有节点 update/cache 清理逻辑。

5. 校验
   - 代码搜索确认 Lights icon 仍只依赖 `Node.needSync`，不引入页面级特殊判断。
   - 补充或更新 EFC contract 脚本，覆盖 EFC associated group subscription 纳入 `Node.getSyncData(type:.all)` 的结构。
   - 跑 `scripts/check_efc_controller_flows.sh`。
   - 跑 `git diff --check`。
   - 需要编译时按项目规则跑 iPhoneOS `xcodebuild`。

## 待确认点

请确认是否按推荐方案 A 实现。

确认后的 scope：

- 纳入 Lights 底部同步：EFC active associated group subscription 补齐。
- 纳入 Lights 底部同步：EFC 配置变更导致的 associated group pending cleanup，也就是退订灯设备对 EFC publish group 的订阅。
- 不纳入 Lights 底部同步：删除 EFC 设备本体时的 delete cleanup。

## 实现结果

已按方案 A 实现。

- EFC planner 新增 node-level association sync 查询，复用现有 EFC subscription / cleanup task 生成逻辑。
- `Node.needSync` / `Node.getSyncData(type: .all)` 已纳入 active associated group subscription 补齐和 associated group pending cleanup 退订。
- Lights 底部 icon 仍只依赖 `Node.needSync`，没有新增页面级特殊判断。
- 点击 Lights 底部同步图标后，EFC association subscription 会进入配置 section，pending cleanup 退订会进入 remove section。
- 删除 EFC 设备本体时的 delete cleanup 未纳入 Lights 底部同步。
