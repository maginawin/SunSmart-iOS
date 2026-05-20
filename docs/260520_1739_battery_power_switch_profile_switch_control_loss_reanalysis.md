# Battery Power Switch Profile Switch Control Loss Reanalysis

## 反馈后的约束

已排除“用户未正确激活 / 设备只进入短 wake 窗口”作为主因：

- 用户实际操作正确。
- 设备真实进入 activated 状态。
- 后续 Battery Power Switch configuration 命令返回成功。

因此新的分析前提是：activation 已成功，APP 也收到了若干成功 ACK，但 SAVE 后 Battery Power Switch 仍不能控制设备。

## 当前最可疑根因：ACK 与当前命令关联过宽

`MeshProxyMessageCommand` 当前按如下条件把收到的响应匹配到正在等待的 handle：

- `responseOpCode == message.opCode`
- 源地址属于该 handle 目标地址
- handle 未完成

对 `SunricherVendorStatus`，这意味着所有 Vendor RET `0x33` 只要来自同一个 Battery Power Switch，就可能被当前等待中的任意 Vendor SET/GET 认为是自己的 ACK。当前代码只在匹配后检查：

- `vendorMessage.status.isSuccessful`

没有检查：

- 当前发送的是 `Vendor SET 0x4C 0x00` Key Config，收到的是否也是 `0x4C 0x00`。
- 当前发送的是 `Vendor SET 0x4C 0x01` Reset Defaults，收到的是否也是 `0x4C 0x01`。
- 当前发送的是其他 Vendor SET/GET，收到的是否属于对应 response code。

这会导致一种符合现象的错误：

1. Profile 切换触发 Battery Power Switch 自身配置。
2. APP 发送 reset。
3. 某个来自同一设备、同样是 Vendor RET `0x33` 的成功响应被误匹配为 reset 成功。
4. APP 提前继续发送 key config / publication。
5. 真正 reset ACK 或其它 ACK 再误匹配到后续命令，形成“APP 认为命令成功，但设备端实际执行顺序/覆盖结果不等于 APP 认为的顺序”。
6. 如果 reset 实际在某些 key config 之后生效，可能清掉刚写入的按键配置；如果 publication ACK 串位，可能遗漏某些 Profile Client Model Publication。
7. UI 显示成功，但设备端缺少按键配置或 publication，最终按键不能控制 target devices。

这个根因也解释了为什么“configuration 命令成功”仍可能不代表设备最终配置正确：当前成功判定可能只是收到了同源同 opCode 的成功 ACK，而不是严格确认该 ACK 对应当前命令。

## 为什么 Profile 切换更容易触发

Profile 切换会执行最危险的命令链：

- `Vendor SET 0x4C 0x01` reset defaults
- 多条 `Vendor SET 0x4C 0x00` key config
- 多条 Config Model Publication Set

其中 reset 的破坏性最高：一旦 APP 误判 reset 已完成并提前下发 key config，后续真实 reset 可能把配置清空。

首次添加 target group 时通常不会反复触发 reset，或者配置链路更短，所以更容易达到预期效果。后续仅切换 Profile 会从 reset 开始重建配置，任何 ACK 串位都会直接影响最终控制能力。

## 与 target group 任务错误的关系

`includeExisting: true` 导致现存 target groups 被错误加入任务列表，这仍然需要修复。

它可能不是“不能控制”的唯一根因，但会放大问题：

- Profile-only SAVE 本应只处理 Battery Power Switch 自身配置。
- 错误加入 target group 任务会拉长同步流程。
- 更长的流程增加 ACK 串位、超时、重复状态的概率。
- target device 任务失败还可能掩盖 Battery Power Switch 自身配置链路的问题。

## 可能影响的其他操作

只要使用 `MeshProxyMessageCommand` 连续发送同一类响应 opCode 的命令，都存在类似风险。

Battery Power Switch 高风险场景：

- 更新 Panel/Profile 类型。
- Scene Profile 更新 Scene 目标。
- Configuration 失败后的 RE-Sync，从 reset 开始全量重发。
- 任何未来新增的 BPS Vendor SET/GET 配置链。

非 BPS 也可能受影响：

- 其它连续发送 `SunricherVendorSet/Get` 的同步流程，如果多个命令共享 Vendor RET `0x33` 且只靠 `opCode` 匹配，理论上也可能被错误 ACK 标记成功。
- 连续 Config Model Publication Set 也存在类似的粗匹配风险，因为同一节点的 publication status response opCode 相同。当前 Battery Power Switch reset 后会强制发送大量 Profile Client Model Publication，因此也属于高风险链路。

## 修复方案建议

### 方案 A：先修 BPS 关键链路，降低影响范围

推荐作为当前任务的第一步。

1. 修复 BPS target group task：
   - 生成任务和实际下发都使用差异语义，不对已存在订阅使用 `includeExisting: true`。
2. 在 `SyncDevicesViewController` 的 BPS 自身配置链路中增加更严格的成功判定：
   - Vendor reset/key config 成功必须确认 `SunricherVendorStatus.status.code` 与当前发送命令的 `responseCommand` 一致。
   - Model Publication 成功必须确认 `ConfigModelPublicationStatus` 的 `elementAddress/modelIdentifier/companyIdentifier` 与当前 publication command 对应。
3. 如果某条 ACK 不匹配当前命令，不应把当前 handle 标记成功；继续等待正确 ACK 或超时失败。

优点：

- 改动聚焦 Battery Power Switch 受影响链路。
- 避免大范围改 SDK 消息调度行为。
- 能直接验证 Profile 切换后 reset/key config/publication 是否真实逐条成功。

风险：

- 如果当前 SDK 不容易在 App 层拦截每条响应并验证，需要小幅修改本地 SDK 的 `MeshProxyMessageCommand`。

### 方案 B：在 SDK 层修复通用 ACK 匹配

更彻底，但影响面更大。

1. `MeshProxyMessageCommand` 对 `SunricherVendorStatus` 增加 response code 匹配。
2. 对 `ConfigModelPublicationStatus`、`ConfigModelSubscriptionStatus` 等同 opCode 状态，尽量匹配 element/model/address。
3. 所有现有同步流程受益，但需要更完整回归。

优点：

- 修复根层问题。
- 其它 Vendor 配置流程也会减少“假成功”。

风险：

- SDK 调度层是通用路径，改动需要更谨慎验证。

## 当前建议

先执行方案 A，同时保留后续把 ACK 匹配上移到 SDK 通用层的可能性。

验证重点：

1. Profile-only SAVE 不再展示现存 target group 任务。
2. Reset ACK 必须匹配 `0x4C 0x01`。
3. Key Config ACK 必须匹配 `0x4C 0x00`。
4. Model Publication ACK 必须匹配当前 element/model。
5. SAVE 成功后，按键实际能控制原 target groups。
6. 故意制造错误 ACK 或超时时，不允许把 BPS configuration 标记成功。

