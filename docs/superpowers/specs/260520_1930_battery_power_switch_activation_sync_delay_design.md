# Battery Power Switch Activation Sync Delay Design

## 背景

Battery Power Switch 刚激活成功时，设备会处理 friend 转发来的网络中大量消息。此时 App 如果立刻继续发送 switch configuration，尤其是 Reset，Switch 可能无法识别该命令并直接过滤，导致后续配置失败或状态不稳定。

当前相关流程：

- `PJEightKeySwitchActivationFlow` 在等待激活时会立即发送一次 capability probe，并通过 `probeTimer` 周期性重试。
- 探测成功后，`showDetected()` 约 1 秒后进入 `SyncDevicesViewController`。
- `SyncDevicesViewController` 在 `.batteryPowerSwitch` 同步中，own configuration 的第一步是 `.batteryPowerSwitchReset`，Reset 成功后才允许 Key Config 和 Model Publication 继续。

## 目标

- 降低激活等待阶段 App 对 Battery Power Switch 的探测频率。
- 保证进入 Sync device(s) 页面后，Reset 不会过早下发给刚激活的 Switch。
- 当 switch configuration 失败后重新发送 Reset 时，也要再次等待。
- Reset 成功后给设备短暂处理 reset 事件的时间，再继续发送 Key Config。
- 等待过程不向用户展示倒计时或额外提示，保持现有同步 UI。

## 非目标

- 不改变 Battery Power Switch 的 profile、scene、target group 配置语义。
- 不改变配置失败后的最终状态判断：own configuration 失败仍然标记为 failed。
- 不改变 Add 阶段默认 switch configuration 的命令内容和成功/失败落盘策略。
- 不为普通灯具、普通动能开关、Fire Alarm、Gateway 等其他 Sync 类型增加等待。

## 方案

### 1. 激活等待 probe 间隔改为 3 秒

在 `PJEightKeySwitchActivationFlow.startWaiting()` 中：

- 保留首次立即 `sendProbe(for:)`。
- 将 `probeTimer` 的重复间隔从 `2` 秒调整为 `3` 秒。

这样用户触发激活后仍能尽快得到首次响应，同时后续探测频率降低，减少 Switch 刚激活阶段的额外压力。

### 2. 探测成功后进入 Sync 保持 1 秒

`PJEightKeySwitchActivationFlow.showDetected()` 中自动完成逻辑保持当前约 `1` 秒：

- 探测成功后快速关闭激活弹窗并进入 Sync 页面。
- 不在激活弹窗中额外等待，避免用户感觉成功后停顿过长。

真正保护设备的等待放在 Sync 页面发 Reset 之前执行。

### 3. Sync 页面 Reset 首发和重发前等待 3 秒

在 `SyncDevicesViewController` 中，仅对 `type == .batteryPowerSwitch` 且即将执行 `.batteryPowerSwitchReset` 的任务启用等待。

行为规则：

- 每次开始一轮 `startSync()` 时，设置 Reset 最早允许时间为当前时间后 `3` 秒。
- 当调度循环取到 `.batteryPowerSwitchReset` 时，如果当前时间早于最早允许时间，则后台等待剩余时间。
- 等待不更新 UI 倒计时，不改变当前同步状态展示。
- 如果页面初始化、数据准备或用户操作本身已经超过 3 秒，则 Reset 不额外等待。
- 如果 switch configuration 失败后用户重试，重新进入 BPS own configuration 流程时，再次设置新的最早允许时间，确保重发 Reset 前也等待 3 秒。
- 如果等待期间用户返回或取消同步，不应继续发送 Reset。

建议封装为内部 helper：

```swift
private func prepareBatteryPowerSwitchResetDelayForSyncIfNeeded()
private func waitBeforeBatteryPowerSwitchResetIfNeeded(for model: SyncCellModel)
```

`prepareBatteryPowerSwitchResetDelayForSyncIfNeeded()` 在每轮 `startSync()` 开始时调用；`waitBeforeBatteryPowerSwitchResetIfNeeded(for:)` 在实际发送 message handles 前调用。

### 4. Reset 成功后等待 500ms

当 `.batteryPowerSwitchReset` 的 result 判断为成功时：

- 保持现有成功判断和状态更新。
- 在允许 Key Config / Model Publication 继续前，等待 `500ms`。
- 等待不展示给用户。
- Reset 失败时不等待 500ms，直接走现有失败逻辑，标记 own configuration failed 并阻止后续 own configuration。

建议封装为内部 helper：

```swift
private func waitAfterBatteryPowerSwitchResetSuccessIfNeeded(for model: SyncCellModel)
```

该 helper 只在 Reset 成功路径触发。

## 数据流

1. 用户在 Battery Power Switch 页面点击 Save。
2. App 如果发现需要 own configuration，则展示激活弹窗。
3. 激活弹窗立即发送一次 capability probe；后续每 3 秒 probe。
4. 探测成功后，弹窗显示成功状态并在约 1 秒后进入 Sync device(s) 页面。
5. Sync 页面开始同步，记录 Reset 最早允许发送时间。
6. 调度到 Reset 时，若未到最早时间，则后台等待剩余时间。
7. Reset 发送并成功后，后台等待 500ms。
8. Key Config、Model Publication、target group add/remove 按既有依赖顺序继续。
9. 如果 configuration 失败后用户重试，再次执行第 5 步，Reset 重发前仍等待 3 秒。

## 错误处理

- 激活 probe 超时或失败：沿用现有 timeout / try again 行为。
- Reset 等待期间用户返回：同步流程不应继续发 Reset。
- Reset 失败：沿用现有 Battery Power Switch own configuration failed 逻辑。
- Key Config 或 Model Publication 失败：沿用现有 own configuration failed 逻辑。
- Target group add/remove 失败：沿用现有 target group 失败逻辑，不影响本次等待设计。

## 测试计划

### 静态检查

- 检查 `PJEightKeySwitchActivationFlow` 的 `probeTimer` 间隔为 `3` 秒。
- 检查 `showDetected()` 自动完成仍为 `1` 秒。
- 检查 `SyncDevicesViewController` 只对 `.batteryPowerSwitchReset` 做 Reset 前等待。
- 检查 Reset 成功路径存在 `500ms` settle。

### 构建验证

使用项目指定命令：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

期望输出包含：

```text
** BUILD SUCCEEDED **
```

### 手动 QA

- Battery Power Switch 等待激活时，首次 probe 仍立即发生，后续 probe 间隔约为 3 秒。
- 探测成功后约 1 秒进入 Sync device(s) 页面。
- Sync 页面进入后，Reset 最早约 3 秒后发送。
- 如果 Sync 数据准备已经耗时超过 3 秒，Reset 不再额外等待。
- Reset 成功后，Key Config 约 500ms 后继续。
- Reset 失败后重试，重发 Reset 前再次等待约 3 秒。
- 等待过程不显示额外倒计时或提示。
