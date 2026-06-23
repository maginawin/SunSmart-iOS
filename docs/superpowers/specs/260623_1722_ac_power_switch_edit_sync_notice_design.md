# AC Power Switch Edit 同步提示设计

## 背景

AC power switch 的设备身份已由 `PJEightKeyPowerSwitchKind` 统一判断：

- Company ID：`0x0A78`
- Product IDs：`0x2A11`、`0x2A12`
- 对应 kind：`.ac`

当前 Site - Space - Main - Switches 列表会通过 `PJEightKeySwitchData.displayStatus` 展示 Battery/AC power switch 的同步异常状态。Edit 页面已有右上角 `devices_not_synced` 提示按钮和进入 `SyncDevicesViewController` 的基础能力，但按钮显示条件没有完全对齐列表状态，因此存在“列表显示需要同步，长按进入 Edit 后右上角没有同步入口”的边界问题。

## 目标

当 AC power switch 在 Site - Space - Main - Switches 中展示为需要同步状态时，长按进入 Edit 页面后，右上角显示同步提示：

- 文案 key：`devices_not_synced`
- English：`Devices not synced`
- 简体中文：复用现有 `设备未同步`
- 图标：复用 `schedule_sync_failed`

点击提示后进入同步页面，执行当前已保存/实时的 AC power switch 同步任务。

## 非目标

- 不新增 AC 专用同步页面。
- 不重构 Battery/AC power switch 的历史命名。
- 不把 Edit 页面未保存的表单修改混入同步任务。
- 不修改 Main - Switches 的列表布局或长按入口。
- 不修改 SDK、Mesh 协议或设备身份映射。

## 推荐方案

采用方案 A：收口共享判断，让 Main - Switches 与 Edit 页面使用同一套“power switch 是否应显示同步提示”的语义。

共享语义应覆盖：

- 仅真实 LINK 到 power switch 设备时生效。
- Battery/AC 均复用。
- 只要当前持久化 switch 数据处于需要同步状态，就显示提示。
- 判断结果应与 `displayStatus` 中进入 `.syncIssueBoundSwitch` 的条件保持一致。

这样可以避免 Edit 页只检查细分同步项，而遗漏 `syncState != .synced` 等列表已覆盖的状态。

## 数据与交互边界

### 显示条件

Edit 页面右上角提示仅在编辑已有 switch 时显示，Create 模式不显示。

对于 AC power switch：

- 未 LINK 的虚拟 AC power switch：不显示。
- 已 LINK，且 Main - Switches 显示为需要同步：显示。
- 已 LINK，但同步状态正常：不显示。

对于 Battery power switch：

- 保持现有设计，但显示条件同步收口到同一共享语义，避免 Battery 行为回退。

### 点击行为

点击右上角提示时，读取当前持久化/实时的 `PJEightKeySwitchData`，进入 `SyncDevicesViewController`。

如果用户在 Edit 页面已经修改名称、组、场景、更多设置但尚未保存，点击提示不应使用这些未保存表单值构造同步任务。

### AC 激活流程

AC power switch 不需要等待设备激活。

现有 `requiresActivationBeforeOwnConfiguration` 语义应保留：

- Battery power switch：需要时可进入 activation 流程。
- AC power switch：不进入 activation 流程，直接进入同步页。

实现时需要确认新入口和保存后同步入口都不会让 AC 走 activation。

## 影响范围

建议只触碰以下区域：

- `PJEightKeySwitchData`：新增或收口共享同步提示判断。
- `PJPreAddEightKeySwitchesVC`：Edit 页按钮显隐和点击 guard 改用共享判断。
- 必要时补充最小范围的命名辅助，避免页面层重复写 Battery/AC 判断。

不建议修改：

- `PJEightKeyPowerSwitchKind` 的 CID/PID 映射。
- `SyncDevicesViewController` 的 type 结构。
- Battery/AC 的同步任务生成逻辑。
- 本地化文案 key，因为 `devices_not_synced` 已存在。

## 验收用例

1. AC `0x2A11` 已 LINK，Main - Switches 显示需要同步，长按进入 Edit 后右上角显示 `Devices not synced`。
2. AC `0x2A12` 已 LINK，Main - Switches 显示需要同步，长按进入 Edit 后右上角显示 `Devices not synced`。
3. 点击 AC Edit 页右上角提示后进入同步页。
4. AC 点击右上角提示进入同步页时，不出现 Battery activation 流程。
5. AC 保存后如果需要同步 own configuration，也不出现 Battery activation 流程。
6. Edit 页存在未保存修改时，点击右上角提示同步当前持久化/实时 switch 数据，不混入未保存表单值。
7. Battery power switch 原有右上角提示和同步入口仍可用。
8. 未 LINK 的虚拟 AC power switch 不显示同步提示。

## 验证计划

- 代码检查：确认 Main - Switches 与 Edit 页使用同一同步提示语义。
- 代码检查：确认 AC 的 `requiresActivationBeforeOwnConfiguration` 仍为 false。
- 构建验证：执行 iPhoneOS `xcodebuild`，不使用 Simulator 校验。

## 自检

- 无待定项。
- 范围聚焦在 AC power switch Edit 同步提示，不包含离线状态、列表 UI 或 SDK 改造。
- 显示条件、点击数据来源、AC activation 边界已明确。
- 本地化复用现有 key，不新增用户可见硬编码文案。
