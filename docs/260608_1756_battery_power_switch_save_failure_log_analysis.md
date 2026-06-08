# Battery Power Switch Save Failure Log Analysis

## 结论

这段日志里，Battery Power Switch 的 `Save Switch Configuration` 失败更像是 App/SDK 消息并发与取消机制导致的假失败或竞态失败，不像是设备拒绝了 key config。

最可疑的根因是：等待激活探测使用 `SunricherVendorGet(.batteryPowerSwitchTxEnabled)`，即 Vendor GET `0x4C 0x03`。这个 probe 在进入 `SyncDevicesViewController` 后仍出现超时和取消；取消的是 GET opcode `0xF1780A`，但随后正在发送的 `SunricherVendorSet(.batteryPowerSwitchKeyConfig(button: 5))` 收到 `AccessError.cancelled`。SDK 的取消逻辑会按目标地址清理 `outgoingMessages` 和 `responseCallbacks`，因此同一节点 `0x001B` 上的 probe 取消可能误伤正在进行的 key config SET。

## 日志事实

1. 激活探测发送的是：

```text
SunricherVendorGet(function: .batteryPowerSwitchTxEnabled)
Access PDU opcode: 0xF1780A, parameters: 0x4C03
```

设备确实多次回复成功：

```text
Response Access PDU opcode: 0xF3780A, parameters: 0x4C030001
code: batteryPowerSwitchTxEnabled
isSuccessful: true
```

2. 进入同步页后，key config 已经开始发送，并且 button 0 到 button 4 以及 button 4 的 press / pressRelease 都成功收到：

```text
Response Access PDU opcode: 0xF3780A, parameters: 0x4C0000
code: batteryPowerSwitchKeyConfig
isSuccessful: true
```

3. 失败发生在 button 5：

```text
send message: SunricherVendorSet(... button: 5 ...)
Response to Access PDU (opcode: 0xF1780A, parameters: 0x4C03) not received (timeout)
Cancelling messages with op code: 15824906, sent from: 0001 to: 001B
消息发送失败 message: SunricherVendorSet(... button: 5 ...), error: cancelled
```

其中 `15824906` 等于 `0xF1780A`，也就是 GET，不是 key config SET。也就是说日志表面上失败的是 SET，但触发取消的是仍在超时的 activation probe GET。

4. App 打印 `完成` 并触发 Cloud Sync 成功后，设备又返回了 button 5 的 key config 成功响应：

```text
ACK seqZero: 1680, ackedSegments: 0x00000007
Response Access PDU opcode: 0xF3780A, parameters: 0x4C0000
code: batteryPowerSwitchKeyConfig
isSuccessful: true
```

这说明设备侧大概率已经收到并执行了最后一条 key config。App 侧失败更可能是回调/取消状态被提前标记，而不是设备真实配置失败。

## 代码证据

`MeshBatteryPowerSwitchActivationDetector` 当前用 `MeshAPI.sendMessage(... timeout: 1.5)` 发送 `batteryPowerSwitchTxEnabled` GET。这个 API 会先注册等待 `SunricherVendorStatus` 的 callback，再通过 `MeshMessageManager` 发送 acknowledged message。

SDK 中 `NetworkManager.cancel(messageWithHandler:)` 会：

- 调用 `accessLayer.cancel(handler)`。
- 从 `outgoingMessages` 移除 `handler.destination`。
- 按 `handler.destination.address` 移除 `responseCallbacks`。
- 对被移除的 response callback 回调 `AccessError.cancelled`。

另外 `MeshNetworkManager+Create.cancelNotifyCallback(...)` 也会按 source address 移除 `outgoingMessages` 和 `responseCallbacks`。由于 Vendor GET `0x4C03` 和 Vendor SET `0x4C00` 的响应都是同一个 `SunricherVendorStatus` opcode `0xF3780A`，只在 parameters 里区分 `0x4C03` 和 `0x4C00`，当前 callback/cancel 维度不足以隔离同一节点上的多个 vendor acknowledged 操作。

## 可能原因排序

1. 最高概率：activation probe GET 与 Sync key config SET 并发/重叠，GET 超时取消按目标节点清理回调，导致正在发送的 key config SET 被标记为 `cancelled`。

2. 高概率：`MeshAPI.sendMessage` 的 `timeout: 1.5` 对低功耗 Battery Power Switch 太短。日志显示 GET 虽然能收到 status，但仍出现 `Response to Access PDU ... not received (timeout)`，说明 send/wait 两套机制至少有一套没有正确完成，短超时放大了取消竞态。

3. 中概率：Sync 队列完成判断早于底层 segmented message 完全稳定。日志中 `完成` 和 Cloud Sync 出现在 button 5 的最终 ACK/status 之前，说明 App 状态推进和 mesh lower transport 收尾之间存在时间差。

4. 低概率：`Local Vendor Model model on Primary Element not bound to key` 不是本次直接失败原因。它每次成功 status 后都出现，但 button 0 到 button 4 仍被 App 识别为成功。不过它可能解释为什么部分 acknowledged send callback 没有如预期完成，建议作为次级 SDK 配置问题单独验证。

5. 很低概率：UI constraint warning 不是 mesh 保存失败原因。它只是进入页面时的 Auto Layout 噪声，和 `cancelled` 的 mesh 发送错误没有直接因果关系。

## 建议验证

1. 在 `MeshBatteryPowerSwitchActivationDetector` 的 completion、timeout、cancel 路径加临时日志，确认进入 Sync 页后是否仍有旧 probe 的 timeout/cancel 回调触发。

2. 在 `NetworkManager.cancel(messageWithHandler:)` 打印被移除的 `responseCallbacks` 当前 expected opcode，确认 GET cancel 是否移除了同节点正在等待的 SET response callback。

3. 在 `SyncDevicesViewController` 开始 key config 前确认 activation flow 已经停止所有 probe timer，并且没有未完成的 `MeshAPI.sendMessage` GET handle。

4. 复测时关注三个时间点：最后一次 `0x4C03` GET 发送时间、第一条 `0x4C00` SET 发送时间、GET timeout/cancel 时间。如果 cancel 落在 key config segmented SET 过程中，基本可确认该根因。

5. 如果要修复，优先方向应是让 activation probe 与 Sync 队列串行隔离，或者让 probe 使用不会取消同节点其他 response callback 的发送方式。不要只在 UI 层吞掉 `cancelled`，因为这会掩盖真正的队列竞态。
