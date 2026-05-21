# Battery Power Switch Dim Click Transaction Design

## 背景

Battery Power Switch 设备页中间开关面板会模拟真实开关，把按钮功能发送到内部虚拟组。当前 dim up/down 单击后，第一次通常能生效，但连续单击只会生效一次。用户怀疑是同按钮 `200ms` 单击过滤导致。

检查现有实现后，`200ms` 过滤只按按钮 index 保存上一次点击时间，超过 `200ms` 后会放行同一按钮的下一次点击。该过滤不足以解释“连续点击 6 秒内只生效一次”的现象。

更直接的原因是 `GenericDeltaSetUnacknowledged` 在 SDK 中声明 `continueTransaction = true`。AccessLayer 会在 6 秒事务窗口内复用同一个 TID。对于连续发送相同 `delta = +13107` 或 `delta = -13107` 的单击场景，目标设备可能把后续消息当作同一事务内的重复或非新增变化处理，因此表现为只有第一次产生亮度变化。

## 目标

- 保留同一个按钮 `200ms` 单击过滤，继续防止误触和过密组播。
- 修复 dim up/down 单击连续触发只生效一次的问题。
- 每一次被过滤器放行的 dim up/down 单击都应作为独立 `±20%` 调光操作。
- 不改变真实 Battery Power Switch profile 配置逻辑。
- 不改变当前 haptic 和按钮按压动画行为。

## 非目标

- 不调整 dim step 数值。继续使用 `±13107`，约等于 `±20%`。
- 不移除单击过滤。
- 不改 SDK 中 `GenericDeltaSetUnacknowledged` 的全局默认语义。
- 不改变长按调光弹窗、AUTO 弹窗、亮度条发送时机。
- 不新增 App 层重发机制。

## 设计

推荐方案是在 `PJEightKeySwitchVirtualGroupControlSender` 中只针对中间面板模拟发送的 dim up/down 单击消息设置新事务语义。

当前 dim up/down 单击发送：

- Dim Up：`GenericDeltaSetUnacknowledged(delta: +13107)`
- Dim Down：`GenericDeltaSetUnacknowledged(delta: -13107)`

调整后仍使用相同消息和 delta，但在发送前将该消息的 `continueTransaction` 设置为 `false`。这样 AccessLayer 会为每次有效单击分配新的 TID，目标设备会把每次单击视为独立事务，而不是同一事务的延续。

同按钮 `200ms` 过滤保持不变：

- 如果用户在 `200ms` 内连续点击同一个按钮，只响应第一次。
- 如果用户超过 `200ms` 再点同一个 dim up/down 按钮，应再次发送新 TID 的 delta 命令。
- 不同按钮之间不共享过滤时间。

真实 Battery Power Switch profile 配置保持不变：

- key config 仍然写入 `levelDelta ±13107`。
- 不改变设备固件实际按键发包语义。
- 本次只修复 App 页面模拟设备发送到虚拟组的行为。

## 备选方案

### 全局修改 SDK 默认值

可以把 SDK 中 `GenericDeltaSetUnacknowledged.continueTransaction` 默认值改为 `false`。该方案风险较大，会影响所有 Generic Delta 调用点，可能破坏需要事务延续的连续 delta 场景，因此不采用。

### 移除 200ms 过滤

移除过滤不能解决 6 秒事务窗口内 TID 复用问题，只会增加误触和组播压力，因此不采用。

## 验收标准

1. 单击 dim up 后，发送 `GenericDeltaSetUnacknowledged(delta: +13107)`，并使用新事务。
2. 超过 `200ms` 后再次单击 dim up，应再次产生约 `+20%` 变化。
3. 单击 dim down 同理，应支持连续多次约 `-20%` 变化。
4. `200ms` 内连续点击同一按钮仍被过滤。
5. Scene、brightness、ON、OFF、AUTO、长按亮度弹窗和长按 AUTO 弹窗行为不变。
6. 真实 Battery Power Switch profile key config 不变。
7. 当前 haptic 和按钮动画行为不变。

## 验证计划

- 静态检查 `PJEightKeySwitchMonitorVC.swift` 中 dim up/down 消息创建路径，确认只对模拟发送的 `GenericDeltaSetUnacknowledged` 设置 `continueTransaction = false`。
- 静态检查 `keyTapThrottleInterval` 仍为 `0.2`。
- 使用 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 验证编译。
- 手工验证真实或测试网络中 dim up/down 连续单击行为。

