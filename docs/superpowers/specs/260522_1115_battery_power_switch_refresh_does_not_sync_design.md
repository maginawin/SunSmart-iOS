# Battery Power Switch Refresh Battery 不进入 SAVE 流程设计

## 背景

Battery Power Switch 的配置未完整时，在 Monitor 页面点击 refresh battery 按钮，App 当前会展示 `Save After Activation / 激活后保存` 弹窗。用户按下设备按键后，设备回复激活探测命令，App 会继续进入 Battery Power Switch 的 SAVE/Sync 流程。

这个行为会把“刷新电量”误变成“修复并下发配置”。用户点击 refresh battery 时，预期只是读取电池电量，不应隐式修改配置或进入 SAVE 流程。

## 调查结论

根因在 `PJEightKeySwitchMonitorVC.refreshMonitor()`：

1. 用户点击 Monitor 页 header 上的 refresh battery 按钮。
2. `refreshMonitor()` 先检查 `viewModel.needsBatteryPowerSwitchSync`。
3. 如果 Battery Power Switch 配置未完整，该值为 `true`。
4. 代码直接调用 `pushBatteryPowerSwitchSync()` 并返回。
5. 若 own configuration 需要同步，`pushBatteryPowerSwitchSync()` 会调用 `presentBatteryPowerSwitchActivation()`。
6. App 展示 `Save After Activation / 激活后保存` 弹窗。
7. 设备被按键激活并回复 capability probe 后，App 进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。

所以现场看到的不是 `Refresh Device / 刷新设备` 弹窗，而是 SAVE 后才应该出现的激活弹窗。

## 复现步骤

1. 准备一个 Battery Power Switch，使其处于配置未完整状态，例如：
   - 新增后尚未完成配置同步；
   - 或上次 Battery Power Switch own configuration 同步失败；
   - 或本地 `desiredConfigHash` 与 `appliedConfigHash` 不一致。
2. 进入该 Battery Power Switch 的 Monitor 页面。
3. 点击 header 上的 refresh battery 按钮。
4. App 展示 `Save After Activation / 激活后保存` 弹窗。
5. 多次按下设备任意按键。
6. 设备回复激活探测后，App 自动进入 Battery Power Switch 的 SAVE/Sync 流程。

## 预期判断

预期是合理的：refresh battery 是读操作，SAVE/Sync 是配置写操作，两者应该有明确入口边界。

即使配置未完整，用户点击 refresh battery 也只应该尝试读取电量。配置修复应由 Switch Edit 页面点击 SAVE，或未来明确的 sync/repair 入口触发。refresh battery 不应因为设备被激活、收到 capability response、收到 battery response 或没有收到任何命令而进入 SAVE/Sync。

## 目标

1. Monitor 页点击 refresh battery 时，始终走电量刷新流程。
2. 配置未完整时，refresh battery 仍展示 `Refresh Device / 刷新设备` 弹窗，而不是 `Save After Activation / 激活后保存`。
3. `Refresh Device` 弹窗期间收到有效 `GenericBatteryStatus` 只更新电量和更新时间。
4. `Refresh Device` 弹窗期间不能进入 Battery Power Switch SAVE/Sync 流程。
5. Switch Edit 页面点击 SAVE 后的激活和同步流程保持不变。

## 非目标

- 不改变 Battery Power Switch configuration 的命令内容。
- 不改变 `PJEightKeySwitchActivationFlow` 的激活探测协议和 3 秒 probe 间隔。
- 不改变 `PJEightKeySwitchBatteryRefreshFlow` 的 1 秒 `GenericBatteryGet` probe 间隔。
- 不新增显式 Sync/Repair 按钮。
- 不改变 target group 同步、配置失败重试和 sync issue 状态判断。

## 方案

采用方案 1：拆开 refresh battery 与 sync 入口。

调整 `PJEightKeySwitchMonitorVC.refreshMonitor()`：

- 移除 `needsBatteryPowerSwitchSync` 为 true 时调用 `pushBatteryPowerSwitchSync()` 的分支。
- 保留 `isRefreshing` 防重入。
- 保留 `informationNode` 检查。
- 始终创建并启动 `PJEightKeySwitchBatteryRefreshFlow`。

`pushBatteryPowerSwitchSync()`、`presentBatteryPowerSwitchActivation()`、`pushBatteryPowerSwitchSyncController()` 保留现有逻辑，但只由明确同步配置入口调用，例如 Switch Edit 页面 SAVE 后需要同步配置时。

## 数据流

### Monitor 页 Refresh Battery

1. 用户点击 refresh battery。
2. `refreshMonitor()` 检查是否正在刷新。
3. 获取 Battery Power Switch 对应 `Node`。
4. 展示 `Refresh Device / 刷新设备` 弹窗。
5. `PJEightKeySwitchBatteryRefreshFlow` 立即发送一次 `GenericBatteryGet`，等待期间每 1 秒重试。
6. 用户按设备按键多次，使低功耗设备醒来。
7. 收到有效 `GenericBatteryStatus` 后，保存 `batteryLevel` 和 `batteryLastUpdateTime`。
8. 刷新 Monitor 页 header 显示。
9. 弹窗显示 updated 并自动关闭。

该流程不读取或修改 `desiredConfigHash`、`appliedConfigHash`、`syncState`，也不进入 `SyncDevicesViewController`。

### Switch Edit 页面 SAVE

1. 用户进入 Switch Edit 页面并点击 SAVE。
2. 保存前检查和 desired configuration 准备保持现有行为。
3. 如果需要 Battery Power Switch own configuration，同步前展示 `Save After Activation / 激活后保存`。
4. 设备激活后进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。
5. 同步成功或失败后的状态标记、持久化、通知刷新和返回逻辑保持现有行为。

## 错误处理

- Refresh battery 时如果没有 `informationNode`，沿用现有 failed HUD。
- `GenericBatteryGet` 超时、未知电量或非法电量时，继续等待下一次 probe，直到弹窗超时。
- 用户取消 refresh battery 弹窗时，只停止 refresh flow，不触发配置同步。
- 配置未完整状态不阻止 refresh battery；页面仍可显示 sync issue。
- Edit SAVE 激活弹窗的 cancel、try again、timeout 行为保持现有实现。

## 测试与验证

### 静态检查

- `PJEightKeySwitchMonitorVC.refreshMonitor()` 不再引用 `needsBatteryPowerSwitchSync`。
- `PJEightKeySwitchMonitorVC.refreshMonitor()` 不再调用 `pushBatteryPowerSwitchSync()`。
- `pushBatteryPowerSwitchSync()` 和 `presentBatteryPowerSwitchActivation()` 仍保留，供明确同步配置入口使用。
- `PJEightKeySwitchBatteryRefreshFlow` 仍发送 `GenericBatteryGet`。
- `PJEightKeySwitchActivationFlow` 仍发送 `SunricherVendorGet(function: .batteryPowerSwitchCapability)`。

### 构建验证

运行项目指定命令：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

期望输出包含：

```text
** BUILD SUCCEEDED **
```

### 手动 QA

1. 配置未完整的 Battery Power Switch，在 Monitor 页点击 refresh battery，只展示 `Refresh Device / 刷新设备`。
2. 在上述弹窗中按设备按键并收到电量后，只更新电量，不进入 SAVE/Sync 页面。
3. 在上述弹窗中不按设备或超时，不进入 SAVE/Sync 页面。
4. Switch Edit 页面点击 SAVE，如果需要 own configuration，仍展示 `Save After Activation / 激活后保存`。
5. Edit SAVE 的激活弹窗检测到设备后，仍进入 Battery Power Switch 同步页面。

## 风险

- 配置未完整时，用户点击 refresh battery 不再被自动带到同步修复流程。该变化符合入口语义，但用户仍需要通过 Edit SAVE 或明确同步入口完成配置修复。
- 如果现有产品期望“点击 refresh 顺手修复配置”，本方案会改变这个隐式行为。该隐式行为与 refresh battery 的读操作语义冲突，因此不保留。

