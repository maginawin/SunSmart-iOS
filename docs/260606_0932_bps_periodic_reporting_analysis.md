# Battery/AC Power Switch Periodic Reporting Analysis

## 结论

- Battery Power Switch 和 AC Power Switch 的 More Settings 页面当前只展示 LED Indicator；Periodic Reporting 相关 card/slider 仍保留在代码中，但没有加入 view hierarchy。
- SAVE 和后续 Sync 不会下发 Periodic Reporting 命令。
- 原默认值是 `15min`，来源为 `PJEightKeySwitchMoreSettingsViewModel.State.default`。
- 已将保留字段默认值改为 `Disable`，并在编辑、More Settings、数据库读取/保存、分享导入元数据入口统一归一到 `Disable`。

## 下发链路核查

Power Switch 的同步任务只包含以下自有配置：

- `batteryPowerSwitchKeyConfig`
- `batteryPowerSwitchTxEnable`
- `batteryPowerSwitchLEDIndicator`
- `batteryPowerSwitchReset`

`SyncDevicesCellModel` 和 `SyncDevicesViewController` 中构造的 Vendor Set 也只包含：

- `.batteryPowerSwitchKeyConfig`
- `.batteryPowerSwitchTxEnabled`
- `.batteryPowerSwitchLEDEnabled`
- `.batteryPowerSwitchResetDefaults`

本地 SDK `SunricherVendorSet/Get/Status` 中也没有 Periodic Reporting 对应的 Battery Power Switch vendor function。

## 修改范围

- 默认值：`PJEightKeySwitchMoreSettingsViewModel.State.default` 从 `.fifteenMinutes` 改为 `.disabled`。
- 状态归一：新增 `reservingPeriodicReportingDisabled`，保留字段但强制业务入口使用 disabled。
- 编辑页：加载已有 Power Switch、构建待保存数据时归一。
- More Settings：进入和 Done 回传时归一。
- Repository：保存和读取 metadata 时归一。
- Share payload import：解析分享数据时归一。

## UI 状态

Periodic Reporting 仍作为预留功能保留在代码中；当前页面布局没有添加 periodic card/slider，所以 UI 上不可见。
