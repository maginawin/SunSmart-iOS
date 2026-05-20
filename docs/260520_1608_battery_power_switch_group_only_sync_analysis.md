# Battery Power Switch Group-only Sync 分析

## 问题

- 仅修改 Battery Power Switch 的 group 列表时，当前保存流程会展示 Save After Activation 弹窗。
- 同步页会在 group subscription / unsubscription 任务之外，无条件追加 Battery Power Switch 自身的 Reset、Key Config、Model Publication。
- Save After Activation 弹窗刚展示时，内容尚未 apply，用户可能先看到一个空弹窗中的 loading 控件。

## 根因

- `batteryPowerSwitchDesiredConfigHash` 把 `bindGroupAddresses` 和 `unbindGroupAddresses` 纳入了 BPS 自身配置 hash，导致 group-only 变化被误判为自身 configuration 变化。
- `appendBatteryPowerSwitchItems` 在 `.batteryPowerSwitch` 同步类型下总是创建 Reset、Key Config、Model Publication。
- `isBatteryPowerSwitchConfigurationOperation` 把部分 target subscription 也视为 BPS configuration，使 RE-Sync 误触发 activation。
- `PJEightKeySwitchActivationFlow.start()` 在 `present` completion 后才调用 `startWaiting()`，弹窗展示动画期间没有完整内容。

## 合理边界

- BPS 自身配置负责按键映射和 Profile Client publication，发送目标是 BPS 自身，需要用户按键激活。
- Group 添加/删除只要求目标 group 内的设备订阅/退订 BPS 的虚拟 switch group，不需要唤醒 BPS。
- 需要重新下发 BPS 自身 configuration 的情况应限于会改变自身配置的输入：panel/profile、Scene Profile 的 scene target、link/appKey/enable 等影响自身 key config 或 publication 的数据。

## 优化方案

- 将 BPS 自身 configuration sync 与 target group subscription sync 分开判断。
- Group-only 保存时直接进入 Sync device(s)，只发送目标设备 subscription/unsubscription。
- 同步页仅在自身 configuration 需要同步时创建 Reset、Key Config、Model Publication，并把 target subscription 依赖到这些步骤；否则 target subscription 独立执行。
- RE-Sync 只有自身 configuration 失败时才先等待 activation 并全量重发自身 configuration；target subscription 失败只重试失败设备。
- Activation 弹窗在 present 前先 apply waiting content，避免初始空白/loading-only 状态。
