# Battery Power Switch Refresh Battery 优化设计

## 背景

Battery Power Switch 的 Refresh Device 弹窗用于刷新设备电量。当前流程在弹窗出现后立即发送一次 `GenericBatteryGet`，之后每 3 秒发送一次。实际使用中，用户只按一下设备按键时经常无法及时拿到电量，需要引导用户多次按键，同时提高 App 侧读取频率。

SAVE profile configuration 后的弹窗是等待设备激活流程，不能过快发送 probe。本次调整只针对 Refresh Device，不改变 SAVE profile configuration 的等待激活间隔。

## 当前实现

- Refresh Device 弹窗由 `PJEightKeySwitchBatteryRefreshFlow` 管理。
- 电量读取由 `MeshBatteryPowerSwitchBatteryReader` 发送 `GenericBatteryGet`。
- Refresh Device 当前等待期间每 3 秒调用一次 `sendProbe`。
- SAVE profile configuration 的等待激活由 `PJEightKeySwitchActivationFlow` 管理，也有独立的 3 秒 probe timer。
- Refresh Device 文案使用 `neightkeyswitches_refresh_message`：
  - 英文当前为 `Press any button on the device`
  - 简中当前为 `请按一下设备上的任意按键`

## 目标

1. Refresh Device 弹窗出现并进入等待后，继续保留首次立即发送 `GenericBatteryGet`。
2. Refresh Device 等待期间的后续发送间隔从 3 秒调整为 1 秒。
3. SAVE profile configuration 等待激活流程继续保持 3 秒发送间隔。
4. Refresh Device 弹窗提示调整为：
   - 英文：`Press any button on the device multiple times`
   - 简中：`请多次按下设备上的任意按键`

## 非目标

- 不修改 Battery Power Switch SAVE profile configuration 的等待激活流程。
- 不修改 `GenericBatteryGet` 的 timeout、解析逻辑或电量保存逻辑。
- 不修改 0x4C key configuration 的 retransmit、interval、transition 默认值。
- 不调整弹窗倒计时总时长，仍保持 60 秒。

## 方案

采用“区分命名常量”的小范围调整：

- 在 Refresh Device flow 中将 battery refresh probe 间隔显式命名为 1 秒。
- 在 SAVE activation flow 中保留 3 秒行为，必要时通过命名或验证明确它属于 activation probe，不和 refresh battery 混用。
- 修改 `neightkeyswitches_refresh_message` 的中英文文案。

该方案改动范围小，同时能降低后续把 refresh battery 和 activation 两个计时器混淆的风险。

## 数据流

Refresh Device 流程保持不变：

1. 用户点击 Refresh Device。
2. App 展示 Refresh Device 弹窗。
3. 弹窗进入 waiting 状态后立即发送一次 `GenericBatteryGet`。
4. 用户按下设备任意按键多次，设备被唤醒并响应电量状态。
5. App 在等待期间每 1 秒重试发送 `GenericBatteryGet`。
6. 收到有效 `GenericBatteryStatus` 后保存电量，弹窗显示 updated，并自动关闭。
7. 60 秒内未收到有效电量则显示 timeout。

## 错误处理

- 读取失败或收到未知电量时继续等待下一次 probe。
- 用户取消时停止 timer 并结束 refresh flow。
- 超时时停止 timer，并保持现有 timeout UI 与 retry 行为。
- 若保存电量回调返回失败，沿用现有逻辑显示 timeout。

## 测试与验证

- 静态检查 `PJEightKeySwitchBatteryRefreshFlow` 的 probe timer 间隔为 1 秒。
- 静态检查 `PJEightKeySwitchActivationFlow` 的 probe timer 间隔仍为 3 秒。
- 静态检查 `neightkeyswitches_refresh_message` 的英文和简中文案已更新。
- 运行 `SunSmart` 的 iPhoneOS Debug build，确认编译通过。

## 风险

- Refresh Device 在 60 秒内最多发送约 60 次 `GenericBatteryGet`，比原来的 20 次更频繁。该流程需要用户主动打开弹窗并按设备按键，范围可控。
- 若设备响应慢，1 秒间隔可能与单次 `GenericBatteryGet` 的 2.5 秒 timeout 重叠。现有实现允许并发等待回调，并用 generation 与 state 过滤过期结果；本次不改变这套保护机制。

