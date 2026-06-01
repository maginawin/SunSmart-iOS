# Power Switch 分享/导入修复总结

## 背景

根据 `docs/260601_1357_power_switch_share_import_analysis.md` 与用户确认，采用方案 A：在分享数据的 `switches[]` 中为 Battery Power Switch 与 AC Power Switch 内嵌 `powerSwitch` payload。当前 App 尚未正式发布，不兼容旧测试数据。

## 实现范围

- 导出：普通开关保持原结构；Power Switch 额外导出 `powerSwitch` payload。
- 导入：只有存在合法 `powerSwitch` payload 且与真实 proxy node 类型一致时，才重建 `PJEightKeySwitchData` 与 `PJEightKeySwitchRepository` metadata。
- 数据策略：不使用 PID 补偿创建 metadata；payload 缺失或非法时按普通 `DeviceSwitchData` 导入。
- 权限：八键 Power Switch 编辑入口和编辑页交互统一受 `space.deviceOperates` 控制。

## Payload 内容

- `schemaVersion`
- `powerSwitchKind`
- `eightKeyPanelType`
- `moreSettings.periodicReporting`
- `moreSettings.ledIndicatorEnabled`
- `sync.syncState`
- `sync.desiredConfigVersion`
- `sync.desiredConfigHash`
- `sync.appliedConfigHash`
- `sync.lastSyncFailedReason`
- `sync.lastSyncedAt`
- `battery.level`
- `battery.lastUpdateTime`
- `applied.txEnabled`
- `applied.ledIndicatorEnabled`

## 修改文件

- `SunSmart/Common/Data/ExportData.swift`
- `SunSmart/Common/Data/ImportData.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift`

## 验证

已执行 iPhoneOS Debug 构建：

- `SunSmart`：通过
- `Archipelago`：通过
- `SylSmart`：通过
- `SLG Sync Plus`：通过

构建过程中仍存在项目既有资源、配置和废弃 API warning；本次新增代码未引入阻塞构建的问题。
