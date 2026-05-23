# Battery Power Switch Key Config Delay Design

## 背景

上次方案 B 已经完成 Battery Power Switch 激活和 Sync 阶段的节奏保护：

- 等待激活时，capability probe 间隔调整为 3 秒。
- 探测成功后进入 Sync device(s) 页面前保持 1 秒。
- Sync device(s) 页面针对 Battery Power Switch Reset 增加首发保护，Reset 不早于页面同步开始后 3 秒。
- Reset 成功后等待 500ms，再继续后续配置。

新的设备行为判断是：Battery Power Switch 刚激活后容易过滤过早下发的配置命令，但 Reset 本身不应再作为配置流程的一部分。保护窗口仍然需要保留，但应移动到 Key Config 前后。

## 目标

- 移除 Battery Power Switch 添加阶段的 Reset 命令。
- 移除 Sync device(s) 阶段 Battery Power Switch own configuration 中的 Reset step。
- 将 Sync 阶段的 3 秒首发保护移动到 Key Config 前。
- Key Config 成功后等待 500ms，再继续 Model Publication、target group add/remove。
- 保持激活 probe 间隔 3 秒、探测成功后进入 Sync 保持 1 秒不变。
- 等待过程不展示给用户，不新增倒计时或提示文案。

## 非目标

- 不删除 `batteryPowerSwitchReset` 的 enum case 或底层 message handle 支持，避免扩大影响面。
- 不改变 Battery Power Switch profile、scene、target group 的业务语义。
- 不改变普通设备、普通开关、Emergency Fire Controller、Gateway 等其他 Sync 类型。
- 不改变添加成功但 switch configuration 失败时的展示语义。

## 推荐方案

采用方案 1：完全从 Battery Power Switch 添加和 Sync 配置流程中移除 Reset，下发节奏保护绑定到 Key Config。

### Add 阶段

`BatteryPowerSwitchAddConfiguration` 不再生成 `batteryPowerSwitchResetDefaults` 消息。添加设备后的默认 switch configuration 直接从 Key Config 开始，再继续现有 publication/config 流程。

如果 Key Config 或后续配置失败，仍按现有业务结论处理：设备添加成功，但 switch configuration 未同步。

### Sync 阶段

`SyncDevicesViewController.appendBatteryPowerSwitchItems` 中，当 `needsBatteryPowerSwitchConfigurationSync == true` 时，只创建：

- `Key Config`
- `Model Publication`

不再创建 `Reset` step。`Model Publication` 依赖 `Key Config`。target group add/remove 继续依赖 own configuration steps，确保 switch 自身配置成功后再处理组关系。

### Key Config 首发保护

每次进入 `startSync()` 时，如果当前同步类型是 `.batteryPowerSwitch`，记录 Key Config 最早允许发送时间为当前时间后 3 秒。

调度循环取到 `.batteryPowerSwitchKeyConfig` 时：

- 如果当前时间早于最早允许时间，后台等待剩余时间。
- 如果页面准备、用户操作或前置任务已经耗时超过 3 秒，不额外等待。
- 如果等待期间用户返回或取消同步，不继续发送 Key Config。
- 如果 switch configuration 失败后用户重试，重新进入 `startSync()` 并重新计算 3 秒等待。

### Key Config 成功后处理窗口

`.batteryPowerSwitchKeyConfig` 成功后，在后台等待 500ms，再允许后续任务继续。

这个等待用于让设备处理 Key Config 事件，替代旧方案中 Reset 成功后的 500ms 处理窗口。Key Config 失败时不等待，直接沿用 own configuration failed 逻辑。

## 状态与命名

现有 `batteryPowerSwitchConfigurationResetCompleted` 语义需要调整，不能继续代表 Reset 完成。实现时应改为 Key Config 完成语义，例如 `batteryPowerSwitchKeyConfigurationCompleted`。

相关 helper 也应从 Reset 命名调整为 Key Config 命名：

- Reset earliest date 改为 Key Config earliest date。
- wait before Reset 改为 wait before Key Config。
- wait after Reset success 改为 wait after Key Config success。
- Reset configuration 判断改为 Key Config configuration 判断。

底层 `.batteryPowerSwitchReset` 支持可以保留，但不再参与当前 Add 和 Sync 流程。

## 数据流

1. 用户添加或保存 Battery Power Switch。
2. 如果需要激活，激活弹窗立即发送首次 capability probe，后续每 3 秒 probe。
3. 探测成功后，弹窗显示成功状态，并在约 1 秒后进入 Sync device(s) 页面。
4. Sync 开始时记录 Key Config 最早允许发送时间。
5. 调度到 Key Config 时，若未到最早时间，则后台等待剩余时间。
6. Key Config 发送成功后，后台等待 500ms。
7. Model Publication 继续执行。
8. target group add/remove 继续按既有顺序执行。
9. 如果 Key Config 或 Model Publication 失败，own configuration 标记失败，后续依赖任务不继续。

## 错误处理

- 激活 probe 超时或失败：沿用现有 timeout / try again 行为。
- Key Config 等待期间用户返回或取消同步：当前同步轮次失效，不继续下发。
- Key Config 失败：沿用 own configuration failed 逻辑，并阻止 Model Publication 与依赖的 target group 操作。
- Model Publication 失败：沿用 own configuration failed 逻辑。
- target group add/remove 失败：沿用现有 target group 失败逻辑。

## 测试计划

### 静态检查

- 确认 `PJEightKeySwitchActivationFlow` 的 probe 间隔仍为 3 秒。
- 确认 `showDetected()` 自动进入 Sync 的等待仍为 1 秒。
- 确认 `BatteryPowerSwitchAddConfiguration` 不再生成 Reset 消息。
- 确认 `SyncDevicesViewController` 不再创建 BPS Reset step。
- 确认 3 秒等待只绑定到 `.batteryPowerSwitchKeyConfig`。
- 确认 500ms 等待只在 `.batteryPowerSwitchKeyConfig` 成功后执行。

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

- Battery Power Switch 激活等待页首次 probe 仍立即发生，后续约每 3 秒 probe。
- 探测成功后约 1 秒进入 Sync device(s) 页面。
- Add 阶段 switch configuration 不再先发 Reset。
- Sync device(s) 页面不再显示或执行 Reset step。
- Sync 中 Key Config 最早约 3 秒后发送。
- Key Config 成功后约 500ms 再继续 Model Publication。
- Key Config 失败后重试，再次等待约 3 秒后重发 Key Config。
- 等待过程无额外倒计时或提示。
