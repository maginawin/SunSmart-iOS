# Battery/AC Power Switch 同步失败状态设计

## 背景

Battery Power Switch 和 AC Power Switch 的 SAVE 会进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。同步页会执行两类任务：

- Switch own configuration：`Key Config`、`TX Enable`、`LED Indicator`
- Target group mutation：`Group Subscription`、`Group Unsubscription`

用户预期是：只要本轮 SAVE 流程有任一任务失败，或者用户主动点击 `STOP`，对应 switch 都应持久化为未同步状态；返回 switches 列表后，该 switch 应显示未同步 icon。

本设计同时覆盖 Battery Power Switch 和 AC Power Switch。当前代码中两者共用 `.batteryPowerSwitch` 同步类型和 `PJEightKeySwitchData` 状态模型。

## 当前不符合预期

### STOP 只影响同步页 UI，不稳定持久化 switch 失败

`SyncDevicesViewController.rightItemAction()` 在同步中点击 `STOP` 后，会停止消息队列并把部分同步页 model 标记为失败。但 power switch 的持久化失败依赖外层 `backActionCallback` 对 operation result 的聚合。

当前外层只检查 own configuration 是否失败。若 `STOP` 发生在 group subscription/unsubscription 阶段，或者回调时序导致结果聚合不完整，switch 可能不会稳定进入 `syncState = .failed`。

### SAVE 任一 group 任务失败不一定标记 switch 未同步

三个入口都只用 `containsBatteryPowerSwitchOwnConfiguration(...)` 判断是否需要标记失败：

- `PJPreAddEightKeySwitchesVC`
- `PJEightKeySwitchMonitorVC`
- `GroupPowerSwitchesViewController`

这会漏掉 `batteryPowerSwitchTargetSubscription` 失败。实际 SAVE 的同步完整性不仅包括 switch 自身配置，也包括目标组订阅和退订。

### 列表未同步 icon 未按状态资源展示

`PJEightKeySwitchStatus` 已定义：

- `.syncIssueBoundSwitch -> eight_key_switch_sync_issue`
- `.repairRequiredMode -> eight_key_switch_repair_required`

并且资源已存在。但 `PJEightKeySwitchesViewCell.configure(...)` 当前使用 `eightKeySwitch.displayIconAssetName` 设置主图，没有使用 `displayStatus.iconAssetName`，所以未同步状态不会稳定展示为未同步 icon。

### `syncState = .failed` 不一定驱动 `displayStatus`

`PJEightKeySwitchData.displayStatus` 当前通过 `needsBatteryPowerSwitchSync` / `needSyncData` 判断是否显示 sync issue。若失败时 hash 或 applied 字段没有变化，单纯 `syncState = .failed` 可能不足以驱动列表进入 `.syncIssueBoundSwitch`。

## 目标

- 用户点击 `STOP` 后，本轮未完成同步视为失败，并将 switch 持久化为未同步。
- SAVE 中 own configuration、group subscription、group unsubscription 任一任务失败，都将 switch 持久化为未同步。
- 只有本轮 power switch 相关任务全部成功，才将 switch 标记为已同步。
- switches 列表内，未同步的 Battery/AC Power Switch 显示 `eight_key_switch_sync_issue` icon。
- 修复保持聚焦，不改变普通 Kinetic Switch、普通设备、schedule、profile、emergency fire 等同步语义。

## 推荐方案

采用统一 power switch 同步结果判定。

在 power switch 同步流程里，将以下 operation 都纳入本轮成功/失败判断：

- `.batteryPowerSwitchKeyConfig`
- `.batteryPowerSwitchTxEnable`
- `.batteryPowerSwitchLEDIndicator`
- `.batteryPowerSwitchTargetSubscription`

任一相关 operation 失败，或 STOP 导致相关 operation 未成功，都视为本轮 power switch 同步失败。外层入口据此调用 `markBatteryPowerSwitchSyncFailed(reason:)` 并持久化。只有没有任何相关失败且本轮完成成功时，才调用 `markBatteryPowerSwitchSyncSucceeded(...)`。

## 设计细节

### 1. 扩展 power switch operation 判定

`SyncDevicesViewController` 已有 `isBatteryPowerSwitchSyncOperation(_:)`，它已经覆盖 own configuration 和 target subscription/unsubscription。后续实现应复用这套语义，避免只检查 own configuration。

由于该 helper 当前是同步页私有方法，实施时应抽出一个小范围可复用判定，例如 `DeviceOperationType` extension 或 power switch 专用 helper，让同步页和三个外层入口使用同一套判断，避免复制后语义漂移。

外层 VC 的失败判断应从“是否包含 own configuration 失败”改为“是否包含 power switch sync operation 失败”。

成功判断也要对应调整：只有本轮没有 power switch sync operation 失败，并且同步页进入成功回调，才执行整体成功标记。

### 2. STOP 语义

点击 `STOP` 时：

- 当前 sync run 立即失效。
- `.none`、`.wait`、`.inSettings` 的未完成 model/task 统一标记为 `.failed`。
- 如果当前同步类型是 `.batteryPowerSwitch`，本轮已生成的 power switch sync operation 都应进入失败结果聚合。
- 同步页保持 failure 状态，让用户选择 re-sync 或返回。

`SyncDevicesViewController` 不直接承担数据库持久化；它可以修改本轮内存中的 `switchData.syncState`，最终仍由外层入口在返回/完成回调中持久化，保持现有 ownership。

STOP 后旧的异步 completion 不能再把本轮 task 改回 successful。已有 `syncRunIdentifier` 校验应继续作为保护，后续实现需确认 completion 写状态前都检查当前 run 仍有效。

### 3. 持久化语义

三个入口需要统一处理：

- `PJPreAddEightKeySwitchesVC`
- `PJEightKeySwitchMonitorVC`
- `GroupPowerSwitchesViewController`

处理规则：

- `failedOperationTypes` 包含任一 power switch sync operation：`markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)`。
- 没有失败，且同步成功回调触发：`markBatteryPowerSwitchSyncSucceeded()`。
- back/failure 回调中若只有部分成功，不得把整个 switch 标记为 synced。
- `mode == .deleteGroup` 的特殊回退逻辑保持现状，不扩大本次修复范围；但如果该模式后续需要保留删除失败状态，应另开设计。

### 4. 列表状态判断

Battery/AC Power Switch 的列表状态应把 `syncState != .synced` 作为未同步条件之一。

推荐逻辑：

- key bind 不完整仍优先显示 `.repairRequiredMode`。
- 已绑定 power switch：
  - `syncState != .synced` 或 `needsBatteryPowerSwitchSync == true` 时显示 `.syncIssueBoundSwitch`。
  - 否则按 `enabled` 显示 `.boundEnabled` 或 `.boundDisabled`。
- 非 power switch / Kinetic Switch 继续使用原有 `needSyncData` 判断。

这样可以确保 STOP 或 SAVE 失败已经持久化为 failed 后，即使 hash/applied 字段暂时一致，列表仍显示未同步。

### 5. 列表 icon 展示

`PJEightKeySwitchesViewCell` 应使用 `displayStatus.iconAssetName` 展示状态 icon，至少对以下状态生效：

- `.syncIssueBoundSwitch`
- `.repairRequiredMode`

普通 bound/unbound/disabled 状态可继续沿用现有基础图和背景/虚线样式，避免扩大 UI 改动。由于 `PJEightKeySwitchStatus.iconAssetName` 对普通状态也返回 `eight_key_switch_bound_enabled`，实现时可以直接使用 `status.iconAssetName`，并保留现有 `displayIconAssetName` 仅用于真实 power switch 节点图标场景时的同步页或详情页。

## 备选方案

### 方案 B：只改外层失败判断

只在三个入口把 `batteryPowerSwitchTargetSubscription` 加入失败判断。

优点是改动最少。缺点是 STOP 后状态、列表 icon、`syncState` 驱动 UI 的问题仍可能存在，不足以满足完整预期。

### 方案 C：重做同步状态机

为 power switch 引入独立 sync result model，由同步页直接输出 power switch 级别结果。

优点是语义清晰。缺点是会触碰 `SyncDevicesViewController` 的多业务共用结构，影响面大，不适合本次聚焦修复。

## 开发计划

1. 增加统一的 power switch sync operation 判断 helper，覆盖 own configuration 与 target subscription/unsubscription。
2. 调整三个入口的 `backActionCallback` 判断，任一 power switch sync operation 失败即标记 switch failed。
3. 检查并收敛 `STOP` 分支，确保 `.inSettings` 也进入 failed，且 power switch 失败能被结果聚合。
4. 调整 `PJEightKeySwitchData.displayStatus`，让 `syncState != .synced` 驱动 `.syncIssueBoundSwitch`。
5. 调整 `PJEightKeySwitchesViewCell`，未同步和 repair 状态使用状态 icon。
6. 验证编译和关键手动场景。

## 验收场景

- 在 `Switch Configuration` 期间点击 `STOP`，返回 switches 列表后显示未同步 icon。
- 在 `Group Subscription` 期间失败，返回 switches 列表后显示未同步 icon。
- 在 `Group Unsubscription` 期间失败，返回 switches 列表后显示未同步 icon。
- SAVE 全部任务成功后，switch 标记为 synced，列表不显示未同步 icon。
- 覆盖编辑页 SAVE、详情页 SAVE、group power switches SAVE 三个入口。
- 普通 Kinetic Switch 的旧 `needSyncData` 未同步逻辑不受影响。

## 验证命令

按项目规则，使用直接 `xcodebuild` 校验：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

不使用 shell 包装、不重定向日志、不使用 Simulator 做校验。
