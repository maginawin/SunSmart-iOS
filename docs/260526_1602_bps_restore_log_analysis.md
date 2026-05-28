# BPS Restore Log Analysis

## 结论

这次日志整体符合预期，没有看到前一轮失败的关键问题。

- 新入网节点是 Battery Power Switch：primary address `0x0194`，CID `0x0A78`，PID `0x2A01`，8 elements。
- 配网、AppKey Add、Model App Bind 均返回 `Success`。
- BPS restore append 分支已进入，日志中出现 `batteryPowerSwitchKeyConfig`、`batteryPowerSwitchTxEnabled`、`batteryPowerSwitchLEDEnabled`，且都收到成功状态。
- 日志中没有看到 `manualOverrideTimeout` 被发送到 BPS `0x0194`，说明普通灯具 append 队列已经没有混入 BPS restore。
- Key Config 使用的目标地址是 `49163`，即 `0xC00B`，符合“复用旧虚拟组”的恢复策略。
- `GenericBatteryGet` 在添加成功后返回 `batteryLevel: 48`，说明后续电量读取也成功。

## 需要注意但不是当前失败点

- 开始配网前的 `ConfigDefaultTtlGet(), error: cancelled` 出现在 provision 前，随后配网和配置全部继续成功。它更像是扫描/识别阶段的旧 pending message 被取消，不是 BPS restore 失败点。
- 多处 `Local ... model on Primary Element not bound to key` 是 Nordic SDK 在本地 client model 未绑定 app key 时的日志提示；对应 response 已经被解密并回调到业务层，不表示发送失败。
- `XPC connection invalid` 出现在添加成功后，且不影响后续 `GenericBatteryGet` 成功返回，暂不作为 Mesh 恢复问题处理。
- 日志只证明已发送的 key config 都成功。若旧 BPS 预期还有更多按键动作，需要和旧 `PJEightKeySwitchData` 的实际 key 配置数量对比，确认不是旧数据本身没有配置。

## 建议的人工复核点

1. Space 中旧 BPS 卡片是否仍是同一个业务记录。
2. `proxyNodeAddress` 是否已从旧地址更新为 `0x0194`。
3. `linkGroupAddress` 是否仍为 `0xC00B`。
4. 物理按键是否能控制原来绑定的目标设备。
5. 恢复完成 UI 是否不再显示红色叹号。
