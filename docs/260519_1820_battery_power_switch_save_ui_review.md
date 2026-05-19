# Battery Power Switch SAVE UI Review

## 背景

参考 Figma `SAVE progress` 页面与当前 `SyncDevicesViewController`、Battery Power Switch Edit/SAVE 实现，评估 Battery Power Switch 在 SAVE 时不符合预期的 UI 与流程。

Figma Code Connect 建联因 Figma 认证 token 过期失败；本次评估使用 Figma Desktop 截图和 metadata 作为设计依据。

## 设计侧观察

- 页面标题为 `Sync device(s)`，右上角为 `STOP`。
- 列表包含 `Configuration` 与 `Remove` 分区。
- `Configuration` 中先展示 switch 相关配置对象，再展示 target groups 及其设备。
- `Remove` 中展示需要移除订阅关系的 group 及设备。
- 底部展示同步完成进度。

## 当前实现

- Battery Power Switch SAVE 入口在 `PJPreAddEightKeySwitchesVC.submitBatteryPowerSwitch(_:)`。
- 需要同步时 push `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`。
- BPS 同步数据由 `SyncDevicesViewController.appendBatteryPowerSwitchItems(to:switchData:)` 构建。
- BPS switch 本体被建成一个 `SyncDevicesModel`，步骤包含 `Reset` 与 `Key Config`。
- target groups 通过 `makeBatteryPowerSwitchTargetGroupModel(...)` 构建为 `SyncDevicesGroupModel`。
- removed target groups 目前也追加到同一个 `configurationSection.groups`。

## 确定问题

### 1. Switch 图标未使用 `device_BatteryPowerSwitch`

当前 BPS switch 本体行使用：

- `switchData.displayIconAssetName`

该属性按 8-key switch 展示状态返回：

- `eight_key_switch_bound_enabled`
- `eight_key_switch_sync_issue`
- `eight_key_switch_repair_required`

这适合 Switch 分类页卡片的状态展示，但不适合 SAVE 同步页中的设备类型图标。SAVE 页应使用真实 mesh node 的设备图标：

- `switchNode.iconName`
- 对 PID `0x2A01` / `0x2A02` 应解析为 `device_BatteryPowerSwitch`

### 2. Removed target groups 未进入 Remove 分区

当前 BPS 的 removed groups 被追加到 `configurationSection.groups`，因此 UI 上会混在 `Configuration` 下。

这与 Figma 不一致，也与现有 EnOcean Switch / Group SAVE 的语义不一致。现有同步页中删除/退订类操作使用 `removeSection`，配置/订阅类操作使用 `configurationSection`。

### 3. BPS switch 本体行的层级与 Figma 有差异

Figma 中 switch 相关内容呈现为一个 switch 类型行加一个具体 switch 设备行。当前 BPS 直接展示具体 switch 设备行，并在运行时展开 `Reset` / `Key Config` 步骤。

这个差异可以优化，但风险高于图标与 Remove 分区：

- 若复用 `SyncDevicesSwitchProxyModel` 建 parent/child 层级，需要确认底部进度是否应计入 switch child。
- 当前通用进度统计不计入 `switchProxy.deviceModel`，贸然改动会影响 EnOcean Switch。
- 因用户要求现存 SAVE 功能优先，应先避免全局改动。

### 4. Panel 选择后未立即返回

`PJEightKeySwitchSelectPanelController.tableView(_:didSelectRowAt:)` 当前只更新 `selectedPanelType`、reload table、触发 callback。Edit 页面 UI 会更新，但选择页不会自动 pop。

用户要求“选择 Panel 就立刻返回并更新 UI”，当前不符合。

## 推荐修复方案

### 方案 A：低风险对齐现有 SAVE 模式

优先修复确定问题：

- BPS SAVE 页 switch 本体行图标改为 `switchNode.iconName`，fallback 到 `device_BatteryPowerSwitch`。
- BPS removed target groups 追加到 `removeSection.groups`。
- Panel 选择后立即 pop 返回 Edit 页面；即使选择当前已选 panel，也直接返回。
- 暂不新增 switch parent/child 层级，避免影响通用进度统计与 EnOcean Switch。

优点：

- 改动小。
- 与现有 EnOcean / Group SAVE 的 Remove / Configuration 语义一致。
- 不触碰通用同步页进度统计，风险最低。

不足：

- BPS switch 本体行层级仍不完全等同 Figma。

### 方案 B：完全贴近 Figma 层级

在 BPS 分支增加 switch parent row 与 child device row：

- parent row 显示 `Battery Power Switch` / `SIG Mesh Switch` 类型标题。
- child row 显示具体 switch name，并承担 `Reset` / `Key Config` steps。
- 底部进度需要显式计入 child row。

优点：

- 更贴近 Figma 视觉层级。

风险：

- 需要调整通用 `SyncDevicesSectionModel` 或 `SyncDevicesViewController` 的进度统计。
- 如果全局调整，可能影响 EnOcean Switch 的 SAVE 进度展示。
- 如果仅为 BPS 定制，通用同步页会出现更多分支。

## 推荐结论

建议先采用方案 A。

原因：

- 用户明确要求“符合现存的 SAVE 功能优先级更高”。
- 当前已确认的 bug 是图标、Remove 分区、Panel 选择返回，这些都可以低风险修复。
- switch parent/child 层级属于视觉增强，应在拿到可验证的当前 App 截图后单独评估。

## 验证建议

- 静态检查 BPS switch sync item 不再使用 `displayIconAssetName`。
- 静态检查 BPS removed target groups 被追加到 `removeSection`。
- 静态检查 Panel selection controller 选择后会 pop。
- 编译 `SunSmart` iphoneos Debug。
- 手动验证：
  - Edit 页面点击 Panel，选择任一 panel 后立即返回，panel row 与 preview 已更新。
  - SAVE 页 BPS switch 行显示 `device_BatteryPowerSwitch` 图标。
  - 新增订阅显示在 Configuration，退订显示在 Remove。
