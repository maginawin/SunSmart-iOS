# Battery/AC Power Switch SAVE Stop 问题调查与修复计划

## 背景

用户期望：

- Battery Power Switch 和 AC Power Switch 在 SAVE 后进入 `Switch Configuration` 同步任务时，如果点击右上角 `Stop`，应立刻停止本轮 SAVE 流程。
- Stop 后本次任务应标记为未同步成功，不应继续在 `Switch Configuration` 左侧显示转圈。
- Stop 后保持在失败页，让用户选择 `re_sync` 或返回。
- 若 Stop 导致 `Switch Configuration` 未同步成功，应将本轮已生成的所有 own configuration 任务标记为同步失败；再次同步时，这些失败任务都需要重新同步。
- `TX Enable` 是 Power Switch 的 `enabled/disabled` 状态写入，应保留在 own configuration 任务列表中。

调查范围：

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- `SunSmart/Main/Group/Switch/Controller/GroupPowerSwitchesViewController.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/PJEightKeySwitchData.swift`

## 当前流程

1. Battery/AC Power Switch SAVE 会创建 `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`。
2. `SyncDevicesViewController` 根据 `switchData` 当前状态生成 `Switch Configuration` step。当前实现可能包含：
   - `Key Config`
   - `TX Enable`
   - `LED Indicator`
   其中 `TX Enable` 对应 `switchData.enabled` 的设备端写入。
3. 同步开始后，当前 task 会被置为 `.inSettings`，未开始的 task 为 `.wait`。
4. 右上角 `Stop` 进入 `rightItemAction()` 的 `.inSync` 分支，先 invalidate 当前 run，再调用 `MeshProxyMessageCommand.shared.stopSendMessage`。
5. 点击返回时，`backAction()` 会把 task 的 `state == .successful` 聚合为成功，其余 state 聚合为失败，再由外层 VC 决定是否 `markBatteryPowerSwitchSyncFailed` 或 `markBatteryPowerSwitchSyncSucceeded`。

## 不符合预期的地方

### 1. Stop 不会把正在执行的 task 标记为失败

位置：`SyncDevicesViewController.swift:1647`

当前 Stop 逻辑只处理 `state == .wait` 的 model，将其置为 `.failed`。正在执行中的 `Switch Configuration` task 是 `.inSettings`，不会被改为 `.failed`。

影响：

- 当前 task 继续保持 `.inSettings`。
- `SyncDeviceStepModel.state` 会因为子 task 仍在 `.inSettings` 而返回 `.inSettings`。
- `SyncDevicesModel.state` 也会继续返回 `.inSettings`。
- UI 左侧转圈不会立刻停止，符合用户观察到的现象。

相关聚合逻辑：

- `SyncDevicesCellModel.swift:1174`：step 只要有 `.inSettings` task，就会显示进行中。
- `SyncDevicesCellModel.swift:1094`：device 只要有 `.inSettings` step，就会显示进行中。

### 2. Stop 后异步回调仍可能继续改当前 task 状态

位置：`SyncDevicesViewController.swift:2033`

同步发送的完成回调中没有再次检查当前 `syncRunIdentifier` 是否仍有效，也没有检查 `syncState == .inSync` 后再写回 model 状态。

影响：

- Stop 虽然调用了 `invalidateCurrentSyncRun()`，但已发出的 `addMessage` completion 仍可能回调。
- completion 可能在 Stop 之后继续把当前 task 置为 `.successful` 或 `.failed`，并调用 `updateCell`。
- 这会让 Stop 后的 UI 和结果聚合取决于底层回调时序，不是稳定的“立即停止并失败”语义。

### 3. Stop 后“任务未同步成功”的持久化粒度不完整

位置：

- `GroupPowerSwitchesViewController.swift:508`
- `PJPreAddEightKeySwitchesVC.swift:640`

外层 VC 依赖 `backAction()` 聚合出的 `failedOperationTypes/successOperationTypes` 来决定：

- 有 own configuration 失败：标记 `syncState = .failed`
- 有 own configuration 成功且没有失败：标记整个 power switch 同步成功

但由于 Stop 当前没有强制把 `.inSettings` 置失败，且回调可能继续写状态，外层得到的结果可能不稳定。

### 4. TX Enable 是 switch enabled/disabled 状态写入，应保留

位置：

- `SyncDevicesViewController.swift:729`
- `SyncDevicesViewController.swift:740`
- `SyncDevicesViewController.swift:2394`
- `PJEightKeySwitchData.swift:168`

当前 `appendBatteryPowerSwitchItems()` 会读取 `switchData.needsBatteryPowerSwitchTxEnableSync`，并在需要时向 `ownConfigurationTasks` 添加 `TX Enable`。该任务下发的是 `SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(switchData.enabled))`，同步需求由 `appliedTxEnabled != enabled` 决定。

结论：

- `TX Enable` 不是 Key Config，但属于 Power Switch 本机 own configuration。
- SAVE 中如果 `enabled` 有变化，`TX Enable` 应继续保留在 `Switch Configuration` 内。
- Stop/失败重同步应把本轮已生成的 `TX Enable` 一并标记 failed，并在重试时重新同步。

### 5. 部分 own configuration 成功会提前污染“已应用”字段

位置：

- `SyncDevicesViewController.swift:2448`
- `PJEightKeySwitchData.swift:241`

`TX Enable` 和 `LED Indicator` 单项成功时，会立即写入：

- `appliedTxEnabled = enabled`
- `appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled`

如果后续 Stop 或其他 own configuration task 失败，本轮 own configuration 应视为未同步成功，但该单项 applied 字段已经被更新。

影响：

- 下一轮 SAVE 根据 `needsBatteryPowerSwitchTxEnableSync`、`needsBatteryPowerSwitchLEDIndicatorSync` 判断是否需要重发。
- 已提前写入 applied 的项目可能被认为无需同步。
- 这会导致再次同步不是重新同步本轮失败的所有 own configuration 任务。

### 6. 当前重同步逻辑和预期“本轮 own configuration 失败任务全部重试”不完全一致

位置：`SyncDevicesViewController.swift:2461`

当前有 `resetBatteryPowerSwitchConfigurationForResync()`，但它按 `isBatteryPowerSwitchSyncOperation` 重置所有 power switch sync 操作，包括 target subscription/unsubscription。

另一个普通重同步路径 `prepareDeviceForResync()` 会保留已成功 task，只重置非成功 task。这与“如果 own configuration 本轮失败，则本轮 own configuration 任务都应标记失败并重新同步”不一致。

期望更精确：

- Stop 导致 own configuration 失败后，应只把本轮 `Switch Configuration` 中已生成的 own configuration tasks 全部标记为 failed。
- 再次同步时基于这些 failed tasks 重新执行，而不是无条件把 `Key Config`、`TX Enable`、`LED Indicator` 全部重置为待发送。
- target group subscription 可继续依赖 `Switch Configuration` 成功后执行，但不应因为 own configuration Stop 而错误地复用部分成功状态。

## 根因结论

当前实现把 Stop 视为“停止队列中等待任务”，没有把“正在执行的任务”统一收敛为失败，也没有防止 Stop 后旧发送回调继续写 UI 状态。同时，power switch own configuration 的局部成功状态会提前写入 `applied*` 字段，导致本轮整体失败后下一轮无法保证重新同步本轮失败的所有 own configuration 任务。

因此当前实现不符合预期的核心点是：

1. Stop 不会立刻把 `.inSettings` 的 `Switch Configuration` task 置为 failed。
2. Stop 后旧回调仍可能修改 task 状态。
3. `TX Enable` 应保留在 own configuration 中，失败/Stop 时需要按本轮已生成任务一起标记 failed。
4. 本轮未完整成功时，单项 applied 状态可能被保留，导致下一轮跳过部分配置命令。
5. 重同步失败标记范围需要按“本轮已生成的 own configuration 任务”精准处理，而不是复用普通“保留成功任务”的逻辑。

## 修复方案

### 目标

- 点击 Stop 后，当前同步 run 立即失效。
- 所有本轮已生成的当前 power switch own configuration task，包括 `.inSettings`、`.wait`、`.none`，统一标记为 `.failed`。
- UI 立即进入 failure 状态，`Switch Configuration` 停止转圈。
- Stop 导致 own configuration 失败后，外层持久化 `syncState = .failed`。
- 再次同步时，只要 own configuration 曾失败，就重新同步本轮标记 failed 的所有 own configuration 任务。
- `TX Enable` 保留在 own configuration 任务列表中。
- 仅当整个 own configuration 成功后，才更新 power switch 的整体 applied 状态。

### 计划

#### 任务 1：收敛 Stop 状态

修改 `SyncDevicesViewController.rightItemAction()` 的 Stop 分支：

- 将所有 `.wait`、`.none`、`.inSettings` 的未完成 model/task 置为 `.failed`。
- 对 power switch own configuration 优先使用专门 helper，将本轮已生成的所有 own configuration task 置为 failed。
- Stop 后立即 reload UI 并进入 `.syncFailure`。

验收：

- Stop 后 `Switch Configuration` 不再显示 `.inSettings`。
- 左侧 loading 立即消失。

#### 任务 2：屏蔽 Stop 后旧回调写状态

在 `MeshProxyMessageCommand.shared.addMessage` completion 中补充 run 有效性判断：

- 如果当前 `syncRunIdentifier` 已失效，直接 signal semaphore 并返回，不再修改 model 状态。
- 如果 `syncState != .inSync`，也不再写 task/device 状态。

验收：

- Stop 后旧 completion 不会把 task 改回 successful。
- Stop 结果稳定，不依赖底层消息回调时序。

#### 任务 3：own configuration 失败时标记本轮任务全部失败并重新同步

调整 power switch own configuration 的成功/失败状态策略：

- Stop 或任一 own configuration 失败时，标记本轮 own configuration 整体失败。
- 本轮已生成的 own configuration tasks 全部标记为 `.failed`，包括本轮曾成功的 task。
- 下轮重试时，基于 failed tasks 重新同步这些本轮 own configuration 任务。
- 不无条件把 `Key Config`、`TX Enable`、`LED Indicator` 全部重置为待发送。
- 不使用普通 `prepareDeviceForResync()` 的“保留成功任务”逻辑处理 power switch own configuration。

验收：

- Stop 在 own configuration 任意任务期间发生，本轮已生成的 own configuration tasks 全部显示失败。
- 再次同步时，本轮 failed 的 own configuration tasks 都重新同步。

#### 任务 4：保留 TX Enable 并纳入失败重试语义

保留 `appendBatteryPowerSwitchItems()` 当前 TX Enable 生成逻辑：

- 继续在 `needsBatteryPowerSwitchTxEnableSync == true` 时生成 `TX Enable`。
- Stop 或任一 own configuration 失败时，本轮已生成的 `TX Enable` 也标记为 `.failed`。
- 重新同步时，本轮 failed 的 `TX Enable` 会随其他 own configuration tasks 一起重新同步。

验收：

- enabled 状态有变化时，Battery/AC Power Switch SAVE 后 `Switch Configuration` 仍显示 `TX Enable`。
- Stop/失败重同步会把本轮已生成的 `TX Enable` 标记 failed，并在重试时重新同步。

#### 任务 5：避免局部 applied 状态导致下一轮跳过命令

调整 `TX Enable` 和 `LED Indicator` 的 applied 写入策略：

- 不在单个 task 成功时立即持久化“整体已应用”语义。
- 仅当整个 `Switch Configuration` own configuration 成功后，调用整体成功标记。
- 如果需要保留运行时临时状态，应只保存在本轮内存状态，不影响下一轮 `needs*Sync` 判断。

验收：

- 本轮 Stop 后，即使某个单项命令曾经成功，下一轮仍不会因为 `appliedTxEnabled/appliedLEDIndicatorEnabled` 被提前更新而跳过命令。

#### 任务 6：补充验证

建议验证场景：

- Battery Power Switch：SAVE 后在 `Switch Configuration` 的 `Key Config` 转圈时点击 Stop。
- Battery Power Switch：`Key Config` 成功后、`TX Enable` 或 `LED Indicator` 期间点击 Stop。
- AC Power Switch：同上，但不需要 activation 前置流程。
- Battery/AC Power Switch：enabled 状态有变化时，确认 `Switch Configuration` 包含 `TX Enable`。
- Stop 后点击返回，确认列表或详情显示未同步成功。
- 再次 SAVE/Resync，确认本轮 failed 的 own configuration 任务均重新进入发送流程。

构建验证：

- 使用项目推荐命令：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 已确认交互

- Stop 后保持在失败页，让用户选择 `re_sync` 或返回。
