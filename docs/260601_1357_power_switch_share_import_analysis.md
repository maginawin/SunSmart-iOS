# Battery/AC Power Switch 分享与导入完整性分析

## 结论

当前实现不满足 Battery Power Switch 与 AC Power Switch 在分享/导入中的全功能恢复要求。

核心问题是：分享导出只导出 `DeviceSwitchData` 通用字段，导入也只恢复 `DeviceSwitchData`，没有导出/导入 `PJEightKeySwitchRepository` 中的 Power Switch 专属 metadata。更严重的是，导入前会删除当前子网所有 switch 数据，同时删除八键 Power Switch 专属表数据；随后只保存通用 switch，导致已存在的 Battery/AC Power Switch metadata 也会丢失。

因此导入后节点本身仍可通过 PID 识别为 Battery/AC Power Switch，但对应 switch 记录无法恢复为 `PJEightKeySwitchData`，App 会退化为普通动能开关数据路径。

## 证据

- `SpaceData.export()` 从 `DeviceSwitchData.load(...)` 读取 switch 列表，导出的 `switches` 只包含 `id`、`name`、`enabled`、通用 `panelType`、场景、proxy、link group、bind/unbind group、EnOcean 信息等字段。没有导出 `powerSwitchKind`、八键面板类型、more settings、sync state/hash、电池电量、Tx/LED applied state 等字段。
  - `SunSmart/Common/Data/ExportData.swift:145`
  - `SunSmart/Common/Data/ExportData.swift:535`
  - `SunSmart/Common/Data/ExportData.swift:623`

- `SpaceData.update(spaceJsonData:)` 导入 `switches` 时只创建 `DeviceSwitchData`，没有创建 `PJEightKeySwitchData`，也没有写 `PJEightKeySwitchRepository`。
  - `SunSmart/Common/Data/ImportData.swift:1481`
  - `SunSmart/Common/Data/ImportData.swift:1486`
  - `SunSmart/Common/Data/ImportData.swift:1535`

- 导入前调用 `DeviceSwitchData.deleteSwitchs(...)`，该方法同时删除通用 switch 表与 `PJEightKeySwitchRepository` 专属表。
  - `SunSmart/Common/Data/ImportData.swift:1534`
  - `SunSmart/Common/Data/Database.swift:2473`
  - `SunSmart/Common/Data/Database.swift:2474`

- `DeviceSwitchData.batteryPowerSwitchData` 需要 `proxyNode.isPowerSwitch == true` 且能从 `PJEightKeySwitchRepository` 查到 metadata。导入后没有 metadata，所以这里会返回 nil。
  - `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift:210`
  - `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift:217`

- `PJEightKeySwitchRepository.save(_:)` 才保存 Power Switch 专属字段，当前导入流程没有调用它。
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift:185`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift:192`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Repositories/PJEightKeySwitchRepository.swift:205`

## 功能影响

### Battery Power Switch

导入后不能完整恢复：

- 无法恢复为八键 Power Switch 卡片与监控页，因为列表页通过 `PJEightKeySwitchRepository.makeEightKeySwitch(from:)` 判断是否为八键 Power Switch。
- 电池电量、更新时间、刷新入口会丢失。
- more settings 中的 LED indicator、periodic reporting 状态会丢失。
- `syncState`、`desiredConfigHash`、`appliedConfigHash`、`lastSyncFailedReason`、`lastSyncedAt` 会丢失，无法延续导入前的同步状态。
- `appliedTxEnabled` 与 `appliedLEDIndicatorEnabled` 会丢失，Tx/LED 是否需要补同步无法准确判断。
- target group 订阅同步会走普通 EnOcean switch 分支，而不是 Battery Power Switch 专属 target subscription 分支。

关键分支：

- Power Switch 专属同步依赖 `batteryPowerSwitchData != nil`。
  - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1565`
  - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1584`
  - `SunSmart/Common/Data/Node+SyncData.swift:1418`
- metadata 丢失后会落到普通 EnOcean 订阅逻辑。
  - `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1587`
  - `SunSmart/Common/Data/Node+SyncData.swift:1430`

### AC Power Switch

AC Power Switch 也不能完整恢复：

- `powerSwitchKind == .ac` 不会被恢复到 switch metadata。
- AC 专属显示状态、offline icon、下拉刷新 heartbeat 节点集合依赖八键 Power Switch 数据恢复，导入后会退化为普通 switch。
- AC 与 Battery 共用的八键配置、target group 订阅、Tx/LED applied 状态等同样不会恢复。

节点本身仍可通过 PID 识别为 AC Power Switch，但 switch 层缺 metadata，因此 UI 与同步链路不会按 AC Power Switch 运行。

## 权限限制

分享/导入的 Space 权限本身有实现：

- 导入时会读取 `role` 并设置 `owner` / `editor` / 默认 `visitor`。
  - `SunSmart/Common/Data/ImportData.swift:783`
  - `SunSmart/Common/Data/ImportData.swift:842`
- `SpaceData.deviceOperates` 对 visitor、禁用 editor、Mesh OTA 中的情况只开放 control，不开放 add/edit/delete。
  - `SunSmart/Common/Data/SpaceData.swift:212`
  - `SunSmart/Common/Data/SpaceData.swift:216`
- 八键 Power Switch 监控页的更多菜单会按 `deviceOperates` 控制 edit/delete。
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:55`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJEightKeySwitchMonitorVC.swift:60`

但八键 Power Switch 仍存在一个权限绕过风险：

- Switch 列表长按八键 Power Switch 时，直接进入 `PJPreAddEightKeySwitchesVC` 编辑器，没有先检查 `space.deviceOperates.contains(.edit)`。
  - `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift:420`
  - `SunSmart/Main/Device/Switches/Controller/DeviceSwitchesViewController.swift:422`
- `PJPreAddEightKeySwitchesVC` 的保存、LINK、提交路径本身没有权限 guard。
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift:137`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift:141`
  - `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift:264`

所以权限限制不是完整闭环。普通点击监控页的 edit/delete 菜单受限，但长按编辑入口可能绕过 visitor / disabled editor 限制。

## 与分享/云同步路径的关系

当前分享和云同步上传都会走 `space.export()` 或 `site.export(spaceIds:)`。因此这个问题不只影响手动导入分享，也会影响通过云端同步恢复的 Space 数据。

关键入口：

- 批量分享/解绑前上传：`SunSmart/Main/Share/Controller/ShareAuthorityViewController.swift:612`
- editor 解绑前上传：`SunSmart/Main/Space/Controller/SpaceViewController.swift:654`
- `site.export(spaceIds:)` 内部调用 `space.export()`。
  - `SunSmart/Common/Data/ExportData.swift:109`

## 需要补齐的能力

建议后续修复至少覆盖：

1. 在 `switches` 导出结构中增加 Power Switch 专属字段：power switch kind、八键 panel type、more settings、sync metadata、battery info、applied Tx/LED state。
2. 导入时根据专属字段或 proxy node PID 重建 `PJEightKeySwitchData`，并同步保存 `DeviceSwitchData` 与 `PJEightKeySwitchRepository`。
3. 兼容旧分享数据：没有专属字段但 proxy node 是 `0x2A01` / `0x2A02` / `0x2A11` / `0x2A12` 时，至少按 PID 推断 kind 与 panel type，并创建默认 metadata。
4. 修复列表长按八键 Power Switch 编辑入口的权限检查，或让 `PJPreAddEightKeySwitchesVC` 接收只读/不可编辑状态并在保存、LINK、删除入口统一 guard。
5. 修复后需要覆盖 Battery 与 AC 两类 PID、owner/editor/visitor、disabled editor、Mesh OTA distribution 中的权限行为。
