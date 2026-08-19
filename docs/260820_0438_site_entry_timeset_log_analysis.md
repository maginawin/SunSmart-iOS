# 进入 Site 后的 TimeSet 日志分析

## 结论

本次日志中**没有发送广播 `TimeSet`**。

日志中虽然存在目的地址为 `FFFF` 的广播，但对应消息是：

- `SunricherVendorGet(function: currentActiveDistribution)`
- Access opcode：`0xF1780A`
- 目的地址：`FFFF`（All Nodes）

它用于查询当前活动的 Mesh Firmware Distribution，不是设备时间同步。

## 日志证据

本次可见的 Access 消息如下：

| 消息 | Opcode | 目标地址 | 类型 |
| --- | --- | --- | --- |
| `ExternalVendorMessage(parameters: 0x0101)` | `0xFF780A` | `FEFF` | 厂商消息 |
| `SunricherVendorGet(currentActiveDistribution)` | `0xF1780A` | `FFFF` | 厂商广播 |
| `LightCTLGet` | `0x825D` | `0008` | 单播查询 |
| `LightCTLGet` | `0x825D` | `000C` | 单播查询 |

日志中没有出现以下任一 `TimeSet` 发送特征：

- `send message: TimeSet ... address: 65535`
- `Sending TimeSet ... to: FFFF`
- `Sending Access PDU (opcode: 0x5C, ...)`

SDK 中标准 Mesh `TimeSet` 的 opcode 明确为 `0x5C`，响应类型为 `TimeStatus`（`0x5D`）。

## 为什么这次进入后没有广播 TimeSet

`DevicesViewController` 只会在当前控制器生命周期内首次连接 Mesh 时检查一次自动同步条件。只有同时满足下面两个条件，才会延迟 3 秒调用 `syncTimeNodes()`：

1. 至少一个真实 Node 的 `scheduleIds` 非空；
2. 本地至少存在一个启用的 Schedule。

本次日志明确显示：

- `serverArrayCounts ... schedules=0`
- `localCounts ... schedules=0`

因此第二个条件确定不成立，不会进入 `syncTimeNodes()`；也就不会执行 `MeshAPI.sendMessage(message: message, address: .allNodes)`。

需要注意：`Space heartbeat started` 及后续 `/sitespace/user/hb` 是服务器在线心跳，每 30 秒执行一次，与 Mesh `TimeSet` 无关。

## 判定边界

此结论只针对用户提供的这段完整日志。它能够证明该片段内没有 App/SDK 记录到 `TimeSet` 发送；不能据此证明其他控制器生命周期、创建 Schedule 后重新进入、或其他业务入口永远不会发送 `TimeSet`。
