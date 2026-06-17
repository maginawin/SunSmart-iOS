# EFC Restore 更新日志分析

## 结论

本次核心配置写入符合预期：App 对 EFC3 写入了 `Event Ends` 的 `set brightness to 2%`、`Resuming in 3s`、`Send Count 3 times`，三条 EFC vendor SET 都收到了成功 ACK。

但如果“没有其他更新”指的是“整个 Mesh 过程中不能再有任何配置类消息”，日志里并不完全满足：完成前三条 EFC 参数后，还出现了一条 `ConfigModelSubscriptionDelete`。这条不是 EFC 参数更新，而是关联灯的订阅清理，和 `restoreAuto` 切到 `setBrightness` 后不再需要 Scene/Light LC 恢复通道相符。

另外，日志中的 `SWIFT TASK CONTINUATION MISUSE` 不是预期业务日志。它出现在完成后的状态刷新阶段，不影响前面三条 SET 已成功的判断，但如果稳定复现，需要单独排查 SDK 的 `waitFor(messageWithOpCode:from:to:timeout:)` 异步等待路径。

## 关键证据

### 1. Send Count 3 times

日志发送：

`SunricherVendorSet(function: emergencyResendParameters(stateIndex: restore, intervalSeconds: 5, count: 3))`

wire payload：

`0x4D030205000300`

拆解：

- `4D 03`：Emergency Fire resend parameters
- `02`：restore state
- `05 00`：interval = 5s
- `03 00`：count = 3

设备回复：

`0x4D030002`

解析为 `emergencyResendParametersAck(stateIndex: restore, responseCode: 0)`，成功。

说明：当前 App 的 restore resend 参数本身就是完整 payload，代码固定 `intervalSeconds = 5`，只改 send count 时也会随包带上 interval。这不是额外业务字段变更。

### 2. Event Ends action set brightness to 2%

日志发送：

`emergencyActionConfig(stateIndex: restore, action: lightness(1310), stage1Target: 0xCD27, stage2Target: 0xCD27, appKeyIndex: 1, ttl: 255)`

wire payload：

`0x4D07020627CD27CD0100FF00001E05`

拆解重点：

- `4D 07`：Emergency Fire action config
- `02`：restore state
- `06`：lightness action
- `27 CD / 27 CD`：目标 publish group `0xCD27`
- `01 00`：appKeyIndex 1
- `FF`：TTL 255
- `1E 05`：lightness `0x051E = 1310`

`1310` 对应约 2% lightness。设备回复：

`0x4D07000206`

解析为 `emergencyActionConfigAck(stateIndex: restore, actionType: lightness)`，成功。

### 3. Resuming in 3s

日志发送：

`SunricherVendorSet(function: emergencyRestoreDelay(seconds: 3))`

wire payload：

`0x4D0603`

设备回复：

`0x4D0600`

解析为 `emergencyRestoreDelay` 成功 ACK。

### 4. 不是 EFC 参数更新的额外消息

日志中还有：

`ConfigModelSubscriptionDelete(address: 52519, elementAddress: 90, modelIdentifier: 4611)`

其中 `52519 = 0xCD27`，是 EFC3 的内部 publish group。`elementAddress = 0x005A`，`modelIdentifier = 0x1203`。

这条来自关联组订阅清理逻辑：当 restore action 不再是 `restoreAuto`，planner 会清理不再需要的 Scene / Light LC 订阅。因此它不是“又改了一个 EFC 配置字段”，而是本次 action 类型变化带来的 Mesh 订阅副作用。

### 5. 完成后的刷新和云同步

`完成` 后出现的 `emergencyComprehensiveStatus` GET、`CloudSync` 上传、`DeviceParameterUploadNodeProbe`、`SceneRecallUnacknowledged`，不属于本次三项设置写入：

- status GET 是状态刷新。
- cloud upload 中 EFC3 已持久化为 `actionType=setBrightness`、`brightness=2`、`resumingSeconds=3`、`sendCount=3`。
- `proximityLightingTrigger` 和 `SceneRecallUnacknowledged` 是其他节点的 Mesh 流量。

## 判断

按“用户可见 EFC 配置字段”判断：符合预期，没有看到额外的 EFC 参数被写入。

按“底层 Mesh 配置消息”判断：不完全是只有三条，额外有一条订阅删除，但它是 `setBrightness` 模式下的清理动作，当前代码逻辑上合理。

需要关注的异常只有 `SWIFT TASK CONTINUATION MISUSE`。它不是这次配置是否写成功的反证，但不是正常日志。
