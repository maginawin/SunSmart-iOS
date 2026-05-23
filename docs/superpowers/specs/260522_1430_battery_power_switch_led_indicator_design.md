# Battery Power Switch LED Indicator 设计

## 背景

Battery Power Switch 的 Edit Switch 页面通过 `More Settings` 管理两个设置：

- `Periodic Reporting`
- `LED Indicator`

当前 `More Settings` 中的 `Done` 会把设置状态回传给 Edit 页，后续 `SAVE` 会通过 `PJEightKeySwitchRepository.save(...)` 持久化 `moreSettingsState`。这对纯本地设置可行，但 `LED Indicator` 已有设备协议：

```text
Vendor SET 0x4C 0x02 <enable>
```

该命令写入 Battery Power Switch 本机 NVS。新的目标是：`LED Indicator` 和现有 `Switch Enable` 一样，只有在 SAVE 后等待设备激活、协议下发成功，才持久化到本地数据库并触发云同步。

本次不处理旧 App 已保存但未下发的历史 LED 值。当前 App 会重新添加新的设备。

## 目标

- `Periodic Reporting` 在 `More Settings` 中隐藏，保留代码和数据字段，未来可以恢复显示继续使用。
- 新添加到 Space 的 Battery Power Switch 默认 `LED Indicator = Enabled`。
- 添加到 Space 阶段不额外下发 `SET 0x4C 0x02 0x01`，因为固件默认启用。
- `More Settings` 中修改 `LED Indicator` 后，`Done` 只更新 Edit 页编辑态，不保存数据库、不同步云、不发送命令。
- Edit Switch 点击 `SAVE` 后，如果 LED 目标值和已应用值不同，进入 `Save After Activation` / `激活后保存` 流程，下发 LED 指示开关命令。
- 只有 LED 命令成功后，才保存新的 `LED Indicator` 值到数据库并同步云。
- LED 命令失败、超时或用户返回时，不把新的 LED 目标值作为成功状态保存。

## 非目标

- 不实现 `GET 0x4C 0x02` 主动读取或设备真实状态校准。
- 不做旧数据迁移纠偏。
- 不改变 Monitor 页底部 `Switch Enable` 即时切换流程。
- 不实现 `Periodic Reporting` 协议下发。
- 不支持 v1.0.22 之前固件的兼容分支。

## 方案选择

采用独立 LED Indicator 应用状态。

`PJEightKeySwitchMoreSettingsViewModel.State.ledIndicatorEnabled` 继续表示 App 编辑目标值。新增独立应用状态，例如：

```text
appliedLEDIndicatorEnabled: Bool?
```

同步判断使用：

```text
needsBatteryPowerSwitchLEDIndicatorSync = appliedLEDIndicatorEnabled != moreSettingsState.ledIndicatorEnabled
```

这个方案和现有 `appliedTxEnabled` 一致，能清楚地区分“用户想要的目标值”和“设备已确认应用的值”，也方便在同步失败时回滚。

未采用的方案：

- 把 LED 状态混入 Key Config hash：会混淆按键功能配置和 LED 指示开关，不利于排查同步问题。
- SAVE 后直接在 Edit 页发送 LED 命令，不进入 SyncDevices：改动较少，但会绕开现有激活、重试、失败回滚和统一展示链路。

## UI 行为

### More Settings

`Periodic Reporting` UI 隐藏，但保留：

- `PeriodicReportingOption`
- `State.periodicReporting`
- SQLite 字段 `periodicReporting`
- 当前 slider view 组件和相关文案，除非实现时发现必须移除约束引用

隐藏方式应尽量局部，避免删除后续恢复需要的业务结构。

`LED Indicator` card 保持显示。用户切换后：

1. 只更新 `PJEightKeySwitchMoreSettingsController` 内部 view model。
2. 点击 `Done` 后回传给 Edit 页。
3. Edit 页更新编辑态和 SAVE 状态。
4. 不立即保存数据库，不发送 `0x4C 0x02`。

### Edit Switch SAVE

点击 `SAVE` 后统一判断 Battery Power Switch 本机配置是否需要同步：

- Key Config 是否变化
- Switch Enable 是否变化
- LED Indicator 是否变化

只要其中任意一项需要写 Battery Power Switch 本机 NVS，就需要 `Save After Activation` / `激活后保存` 弹窗。激活后进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。

本机配置顺序固定为：

```text
Key Config -> Switch Enable -> LED Indicator -> Target Groups
```

具体场景：

- 需要 Key Config + Switch Enable + LED Indicator：按完整顺序执行。
- 不需要 Key Config，但需要 Switch Enable 或 LED Indicator：仍需要激活弹窗，先发 Switch Enable，再发 LED Indicator，然后处理 target group。
- 不需要任何本机配置，仅需要 target group subscription/unsubscription：不需要激活弹窗，直接进入 Sync device(s)。

## 数据模型

`PJEightKeySwitchData` 增加 LED 应用状态：

```text
appliedLEDIndicatorEnabled: Bool?
```

推荐增加：

```text
needsBatteryPowerSwitchLEDIndicatorSync
markBatteryPowerSwitchLEDIndicatorSucceeded()
```

并将 `needsBatteryPowerSwitchSync` 扩展为包含：

- `needsBatteryPowerSwitchConfigurationSync`
- `needsBatteryPowerSwitchTxEnableSync`
- `needsBatteryPowerSwitchLEDIndicatorSync`
- `needSyncData`

`markBatteryPowerSwitchSyncSucceeded(...)` 在完整 Battery Power Switch 同步成功后，应同时更新：

- `appliedConfigHash = desiredConfigHash`
- `appliedTxEnabled = enabled`
- `appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled`

添加到 Space 默认值：

- `moreSettingsState.ledIndicatorEnabled = true`
- `appliedLEDIndicatorEnabled = true`

这表示 App 认为设备默认值已经满足，不需要添加阶段下发 `0x4C 0x02 0x01`。

## 持久化与回滚

### 成功边界

只有 SyncDevices 中 LED Indicator 命令成功后，才允许把新的 `moreSettingsState.ledIndicatorEnabled` 持久化到：

- `DeviceSwitchData`
- `PJEightKeySwitchRepository`
- 云同步触发通知

### Edit SAVE 失败

如果 SAVE 涉及任何 Battery Power Switch 本机配置，进入 Sync 前不要先持久化最终状态。

进入 Sync 前需要保存 SAVE 前快照，至少包含：

- `enabled`
- `moreSettingsState`

如果本机配置失败，或用户从 Sync 页面返回且 LED 未成功：

- 恢复 SAVE 前 `enabled`
- 恢复 SAVE 前 `moreSettingsState`
- 标记 sync failed
- 保存恢复后的状态
- 不把新的 LED 目标值同步到云

如果本机配置成功，但 target group 后续失败，应保留已成功应用的本机配置状态，并按现有逻辑处理 target group 的失败状态。

## SyncDevices 接入

新增 Battery Power Switch own configuration 同步项：

```text
batteryPowerSwitchLEDIndicator(switchData:)
```

对应 message：

```text
SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(switchData.moreSettingsState.ledIndicatorEnabled))
```

生成条件：

- 当前 switch 已关联真实 Battery Power Switch
- `needsBatteryPowerSwitchLEDIndicatorSync == true`
- proxy node 存在 vendor model

own configuration step 的任务顺序：

1. `Key Config`
2. `TX Enable`
3. `LED Indicator`

target group step 的 `relevanceStepModels` 继续依赖 own configuration step，确保 target group 在本机配置之后执行。

以下判断需要同步纳入 LED Indicator：

- 是否需要 Battery Power Switch 激活弹窗
- 是否属于 Battery Power Switch own configuration
- 是否属于 Battery Power Switch sync operation
- Sync 成功后是否更新应用状态
- Sync 失败或返回后是否恢复 SAVE 前快照

## SDK 协议支持

SDK 当前已有 `batteryPowerSwitchLEDEnabled` 的 SET/GET/status 入口，但 SET 成功 ACK 需要符合协议定义：

- `RET 0x4C 0x02 0x00`：SET 成功，3B，应该算成功，不要求带 `<enable>`
- `RET 0x4C 0x02 0x00 <enable>`：GET 成功，4B，才解析 `<enable>`

因此需要调整 `SunricherVendorStatus` 的 `.batteryPowerSwitchLEDEnabled` 解析逻辑，使 3B 成功 ACK 不被当作失败。

App 本次只发送 SET，不依赖 GET 状态校准。

## 验证计划

- 静态检查 `More Settings` 不再展示 `Periodic Reporting` card。
- 静态检查 `PeriodicReportingOption`、`State.periodicReporting`、SQLite 字段仍保留。
- 添加 Battery Power Switch 到 Space 后，本地默认 `LED Indicator = Enabled` 且 `appliedLEDIndicatorEnabled = true`。
- 添加阶段不产生 `SET 0x4C 0x02 0x01`。
- More Settings 修改 LED 后点击 `Done` 不保存数据库、不发送命令。
- 只修改 LED 后点击 `SAVE`，展示 `Save After Activation` / `激活后保存`。
- Sync 顺序为 `Key Config -> TX Enable -> LED Indicator -> Target Groups`。
- LED 命令成功后才保存新的 LED 值并触发刷新通知。
- LED 命令失败或返回时恢复 SAVE 前 LED 值，不同步新值到云。
- SDK status 解析接受 `RET 0x4C 0x02 0x00` 作为 SET 成功。
- iPhoneOS Debug build 通过：

```text
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
