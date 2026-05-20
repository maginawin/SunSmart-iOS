# Battery Power Switch Re-Sync Configuration Design

## 背景

Battery Power Switch 的 `Sync device(s)` 页面当前按通用同步逻辑处理 Re-Sync：只重置失败的设备、步骤或任务，已成功的任务保持成功状态。这对普通设备是合理的增量重试，但不适合 Battery Power Switch 的 configuration 链路。

Battery Power Switch 的 configuration 由一组有顺序依赖的命令组成：

1. `Reset`
2. `Key Config`
3. `Model Publication`
4. target group `Group Subscription`

如果其中任意一步失败，设备端实际配置状态可能已经部分变化。新的需求是：只要 Battery Power Switch 的 configuration 失败，用户点击 `RE-Sync` 时必须先等待设备激活，激活成功后从 `Reset` 开始重新下发完整 configuration。

## 当前问题

### Re-Sync 没有重发 Model Publication

当前 `prepareDeviceForResync(_:)` 和 `prepareStepForResync(_:)` 会保留 `.successful` task，只把非成功 task 重置为 `.none`。因此如果 `Model Publication` 在上一轮被标记为成功，后续其他 configuration 步骤失败后再 Re-Sync，不会重新下发 `Model Publication`。

这不是 publication 本身的特殊逻辑导致，而是通用 Re-Sync 的增量策略导致。

### Model Publication 成功判断不真实

`.batteryPowerSwitchModelPublication` 当前在 `DeviceOperationType.isSuccessful` 中无条件返回 `true`。这会导致只要消息发送层认为完成，业务层不会再校验 BPS Profile Client Models 的 publication 是否确实指向目标 link group，也不会校验 retransmit 是否为 `1 / 200ms`。

### Publication 存在不必要等待

`.batteryPowerSwitchModelPublication` 的 message handles 当前使用 `includeExisting: true`，即使某个 Client Model 的 publication 已经正确，也会重复下发 `ConfigModelPublicationSet` 并等待 acknowledged status。

BPS Composition 中最多有 8 个 element，每个 element 可能包含 5 个 Profile Client Models。全量重发 publication 最多会产生 40 条 acknowledged config message。已正确的 publication 不需要重复等待。

## 目标

1. Battery Power Switch configuration 任意一步失败后，Re-Sync 必须全量重发 configuration。
2. 全量重发前必须复用已有 activation alert，等待设备激活成功。
3. 从 `Reset` 开始重发完整 configuration，不跳过上一轮成功过的 `Key Config`、`Model Publication` 或 `Group Subscription`。
4. 非 Battery Power Switch 或非 configuration 失败，继续使用现有“只重试失败项”的通用逻辑。
5. `.batteryPowerSwitchModelPublication` 必须做真实状态校验。
6. BPS 自身单播 configuration 要 fail-fast：`Reset`、`Key Config` 或 `Model Publication` 的第一条消息失败后，后续同一 BPS 自身 configuration 任务直接标失败，不继续浪费时间。
7. `Model Publication` 下发时跳过已正确的 publication，减少不必要的 acknowledged 等待。

## 方案

采用 SyncDevicesViewController 内的 Battery Power Switch 专用 Re-Sync 分支。

### 失败范围判断

仅当当前页面类型是 `.batteryPowerSwitch` 时启用专用逻辑。

把 Battery Power Switch configuration 定义为 operation type 属于以下任一项：

- `.configuration(_, .batteryPowerSwitchReset)`
- `.configuration(_, .batteryPowerSwitchKeyConfig)`
- `.configuration(_, .batteryPowerSwitchModelPublication)`
- `.configuration(_, .batteryPowerSwitchTargetSubscription)`

其中 target subscription 在页面上属于 configuration section。remove section 中的 target unsubscription 虽然也是 `.batteryPowerSwitchTargetSubscription(..., unsubscribe: true)`，但它属于 remove 语义，Re-Sync 仍按现有失败项重试，不触发全量 configuration。

实现上应通过 section 归属或 `unsubscribe` 值区分：

- `unsubscribe == false`：属于 configuration 全量重试范围。
- `unsubscribe == true`：属于 remove/unsubscription，保留增量重试。

### 顶部 RE-Sync

当 `syncState == .syncFailure` 且用户点击顶部 `RE-Sync`：

1. 收集当前选中的失败设备。
2. 如果选中项中包含 Battery Power Switch configuration 失败：
   - 不直接调用 `startSync()`。
   - 先启动 `PJEightKeySwitchActivationFlow`。
   - detected 自动关闭后，重置全部 Battery Power Switch configuration models/tasks。
   - 设置 `syncState = .inSync`。
   - 调用 `startSync()`。
3. 如果选中项不包含 Battery Power Switch configuration 失败：
   - 保留现有通用逻辑，只重置选中的失败项。

### 单个设备或步骤 Re-Sync

当用户在失败设备或失败步骤上点击 Re-Sync：

1. 如果该设备或步骤属于 Battery Power Switch configuration：
   - 先启动 activation flow。
   - detected 后重置整个 Battery Power Switch configuration。
   - 从 `Reset` 开始同步。
2. 如果不属于 Battery Power Switch configuration：
   - 保留现有 `prepareDeviceForResync(_:)` 或 `prepareStepForResync(_:)` 行为。

### 全量重置规则

Battery Power Switch configuration 全量重置时：

- BPS 自身设备的 `Reset`、`Key Config`、`Model Publication` steps 全部置为 `.none`。
- target group subscription 中 `unsubscribe == false` 的 devices/steps/tasks 全部置为 `.none`。
- 相关 `isFineshed`、`isSelected`、`failedCount` 需要恢复到可重新执行状态。
- remove section 或 `unsubscribe == true` 的失败项不参与全量 configuration reset。

这样 `getNextHandleModel()` 会重新从 `Reset` 开始取任务，并按已有 relevance step 顺序继续执行。

### Activation Flow

复用已有 `PJEightKeySwitchActivationFlow`：

- waiting：60s 倒计时，每 2s 发送一次 `batteryPowerSwitchCapability` probe。
- detected：短暂展示成功状态后自动关闭。
- no response：允许 Cancel 或 Try Again。

Re-Sync detected 后才开始重发 configuration。Cancel 或 no response 不会启动同步。

### Model Publication 状态校验

`.batteryPowerSwitchModelPublication` 不再无条件成功。

校验条件：

- 当前 node 必须是对应 `switchData.proxyNode`。
- `switchData.linkGroup` 必须存在。
- `node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: includeExisting: false)` 必须为空。

该 helper 已经基于目标 `Publish` 对比现有 model publication。目标 `Publish` 包含：

- address：`switchData.linkGroup`
- app key：当前 Application Key
- ttl：当前网络 default TTL
- period：disabled
- retransmit：`count = 1`、`interval = 200ms`

因此 helper 为空表示所有 BPS Profile Client Models 的 publication 已经符合目标配置。

### Model Publication 发送优化

`.batteryPowerSwitchModelPublication` 的 message handles 改为使用 `includeExisting: false`。

效果：

- 首次配置或 reset 后，仍会发送缺失/不匹配的 publication。
- Re-Sync 全量重发时，如果 reset 导致 publication 被清空，仍会重新下发。
- 如果设备端 publication 已经正确，不再重复发送最多 40 条 acknowledged config message。
- 空 message handles 会由现有 `operationSuccessful` 判定标记成功；配合真实状态校验，只有实际 publication 正确时才成功。

### BPS 自身单播 Fail-Fast

BPS 自身单播 configuration 包括：

- `Reset`
- `Key Config`
- `Model Publication`

这些步骤都发送到 BPS 自身，且设备需要先被用户激活。若其中某一步的第一条消息超时或发送失败，通常说明设备已经睡眠或不可达，继续发送后续 key config / publication 只会等待超时。

设计为：

1. 当 BPS 自身单播 configuration task 失败时，记录当前 BPS configuration 已 fail-fast。
2. 当前同步轮次中，后续 BPS 自身单播 configuration task 直接标记为 `.failed`，不再调用 `MeshProxyMessageCommand.shared.addMessage`。
3. target group subscription 不属于 BPS 自身单播配置，不使用该 fail-fast 标记；但由于它依赖 BPS 自身 steps，当前置 step 失败时现有 relevance 逻辑会阻止其继续执行。
4. 用户再次 Re-Sync 时，先重新激活，清空 fail-fast 标记，再从 `Reset` 开始。

## 非目标

- 不改变其他 `SyncType` 的 Re-Sync 策略。
- 不改变 remove/unsubscription 的增量重试策略。
- 不改变 activation alert 的视觉样式。
- 不新增 Battery Power Switch 协议字段解析。
- 不优化 target group subscription 的消息数量。

## 测试重点

1. Battery Power Switch configuration 中 `Reset` 失败后，点击 `RE-Sync` 会先弹 activation alert。
2. activation detected 后，重新从 `Reset` 开始，而不是只重试失败项。
3. `Model Publication` 上一轮成功但其他 configuration 步骤失败时，Re-Sync 后仍会重新进入完整 configuration 流程。
4. `.batteryPowerSwitchModelPublication` 在 publication 不匹配时不能被业务层判定为成功。
5. 已正确的 publication 不重复生成 message handles。
6. BPS 自身单播第一条消息失败后，后续 key config / publication 不继续等待超时。
7. 非 BPS 或 remove/unsubscription 失败仍保持现有增量 Re-Sync 行为。

## 风险

- `Publish` equality 若受 SDK 内部字段影响，需要确认 `getBatteryPowerSwitchPublicationMessageHandles(... includeExisting: false)` 对 retransmit、ttl、period、app key 的比较稳定。
- 如果设备 reset 后不会清空 publication，则 Re-Sync 的 Model Publication 可能因已正确而快速成功。这符合“全量流程从 reset 开始”的业务要求，因为 publication 校验确认了目标状态已正确。
- Fail-fast 必须限定在当前同步轮次，不能污染下一次用户 Re-Sync。
