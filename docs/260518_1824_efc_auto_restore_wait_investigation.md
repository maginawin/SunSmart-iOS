# EFC AUTO 同步等待行为调查

## 结论

当前 EFC 同步设备页里的 `AUTO` 命令发完后没有真实 ACK/status 可等。它使用的是 `LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)`，属于 unacknowledged group control message。

同步页之所以看起来要等很久，是因为它走了通用 `MeshProxyMessageCommand.addMessage(...)` 队列。该队列无论消息是否需要回复，都会安排一次 `sendMessageWaitTimeout`。EFC 同步页传入的 `ackTimeout(for:)` 普通任务是 15 秒，因此 unack 的 `AUTO` 会等到约 15 秒 timeout 后才进入 finished 回调，然后同步页才把该任务标记为成功。

## 证据

### 1. AUTO 命令本身没有 ACK

Planner 中生成的是：

```swift
LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)
```

发送目标是 group 地址。这与 group 页面 Auto 按钮一致。

### 2. MeshProxyMessageCommand 只按 AcknowledgedMeshMessage 计算响应地址

`MeshMessageHandle.allAddresss` 的实现：

```swift
guard self.message is AcknowledgedMeshMessage, let destinationAddress = self.address ?? self.model?.parentElement?.parentNode?.primaryUnicastAddress else {
    return []
}
```

所以 `AUTO` 这种 unack message 的 `allAddresss` 是空数组。

### 3. 但发送队列仍统一等待 timeout

`MeshProxyMessageCommand.sendMessages()` 发送后会统一执行：

```swift
let dealy = TimeInterval(messageHandle.allAddresss.count * 1) + self.acknowledgedMessageTimeout
self.perform(#selector(self.sendMessageWaitTimeout), with: nil, afterDelay: TimeInterval(dealy))
```

对 `AUTO` 来说 `allAddresss.count == 0`，所以 delay 就是 `acknowledgedMessageTimeout`。

### 4. EFC 同步设备页普通任务 timeout 是 15 秒

`SyncDevicesViewController.ackTimeout(for:)`：

```swift
isEmergencyFireControllerDeleteCleanup(model) ? 5 : 15
```

`AUTO` 不是 delete cleanup，因此等待 15 秒。

## 与 group 页面 Auto 的差异

group 页面 Auto 按钮直接调用：

```swift
MeshAPI.sendMessage(message: LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0), address: group.address.address)
```

这个路径只把消息放入 `MeshMessageManager` 发送队列，不进入同步页的 `MeshProxyMessageCommand` 等待流程，因此 UI 上不会等 15 秒。

## 影响

- `AUTO` 命令没有设备回复可验证，当前同步页等待的不是设备执行结果。
- 当前等待只是 `MeshProxyMessageCommand` 对 unack message 的通用 timeout 行为。
- 如果有多个 group，每个 group 的 `AUTO` 都可能多等约 15 秒，因此总耗时会明显变长。

## 建议

推荐对 EFC `autoRestore` 做专项处理：

1. 仍保留同步页顺序，确保 `AUTO` 在每个 group 关联任务之后执行。
2. 发送 `autoRestore` 时使用 `MeshAPI.sendMessage` 或等价的直接 enqueue 方式。
3. 发送后等待 300ms，让组播命令有时间进入无线发送流程，再标记该 task 成功，不等待 ACK/status。
4. 文案上仍显示 `AUTO`，但它的成功语义应理解为“命令已提交发送队列”，不是“设备已回报 Auto 状态”。

不建议把 `AUTO` 改成 acknowledged message 来等结果，因为 group 页面当前行为就是 unack Auto，而且 group 地址下多节点的 ACK 聚合会引入额外复杂度和失败噪音。
