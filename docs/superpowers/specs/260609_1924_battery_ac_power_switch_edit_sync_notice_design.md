# Battery/AC Power Switch Edit Sync Notice Design

## 背景

当前 battery power switch 和 ac power switch 在 switches 页面能正确展示需要同步或同步失败状态，但从 switches 页面长按进入 edit 页面后，Name 右侧没有展示与 Kinetic switch 相同的 `Device not synced` 控件组。

Kinetic switch 的 edit 页面已经在 Name 右侧展示该控件组，包含 `schedule_sync_failed` 图标和 `devices_not_synced` 文案，点击后进入同步页面。Battery/AC power switch edit 页面使用独立的 `PJPreAddEightKeySwitchesVC` 与 `PJEightKeySwitchEditorView`，当前没有对应控件。

## 需求确认

- Battery/AC power switch edit 页面需要在 Name 右侧展示 `Device not synced` 控件组。
- 控件组需要包含左侧图标，视觉与 Kinetic switch 保持一致。
- 点击控件组需要自动跳转到同步页面。
- 显示条件采用完整“需要同步”口径：只要 battery/ac power switch 当前需要同步就显示，不仅限于 `syncState == .failed`。

## 问题真实性

问题成立。

- Kinetic switch edit 页使用 `DeviceSwitchHeaderView.syncFailedBtn` 展示 `devices_not_synced` 文案和 `schedule_sync_failed` 图标。
- Battery/AC power switch edit 页使用 `PJEightKeySwitchEditorView`，Name 区域目前只有标题、输入框和清除按钮。
- Battery/AC power switch 已有同步状态判断与同步跳转能力，缺口集中在 edit 页 UI 显示和点击入口绑定。

## 推荐方案

在 `PJEightKeySwitchEditorView` 内新增 `syncFailedButton`，样式对齐 Kinetic switch：

- title 使用 `devices_not_synced`。
- title color 使用 `Red_Color`。
- normal image 使用 `schedule_sync_failed`。
- image position 使用 left，spacing 与 Kinetic 一致。
- 位置放在 Name 标题行右侧，与 `nameSectionLabel` 垂直居中。

在 `PJPreAddEightKeySwitchesVC` 内新增显隐与点击逻辑：

- edit 模式下读取 `currentEightKeySwitchData`。
- 当 `currentEightKeySwitchData?.needsBatteryPowerSwitchSync == true` 时显示。
- 新建页、未绑定真实 power switch、无需同步时隐藏。
- 点击时读取当前持久化/实时 switch 数据，若仍需同步，则调用既有 `pushBatteryPowerSwitchSync(_:)`。
- 点击提示进入同步页前不提交当前编辑中的未保存表单，避免把用户尚未保存的字段混入重试同步。

## 备选方案

### 方案 1：抽取通用 Device Not Synced 控件

把 Kinetic 和 Battery/AC 共用的按钮抽成通用 view 或 factory。

优点是复用更清晰；缺点是会触碰 Kinetic 现有稳定页面，当前需求不需要扩大改动面。

### 方案 2：复用 DeviceSwitchHeaderView

尝试在 Battery/AC edit 页直接复用 Kinetic 的 header。

不推荐。Battery/AC edit 页不是 table header 结构，强行复用会改变布局边界和页面结构，风险高于收益。

## 数据与状态口径

显示判断使用 `PJEightKeySwitchData.needsBatteryPowerSwitchSync`，该属性覆盖：

- power switch 自身配置未同步。
- Tx Enable 未同步。
- LED Indicator 未同步。
- target/group 等旧 switch 数据未同步。

这与 switches 页面展示同步问题的完整语义一致。

## 导航与回调

点击 `Device not synced` 后进入：

`SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`

继续复用 `PJPreAddEightKeySwitchesVC.pushBatteryPowerSwitchSync(_:)` 中已有的成功、失败、返回处理：

- 同步成功后标记同步成功并持久化。
- 同步失败后保留失败状态。
- 同步结果通过既有通知刷新 switches 页面和相关页面状态。

## 非目标范围

- 不调整 Kinetic switch edit 页现有实现。
- 不新增本地化 key。
- 不改变同步流程、同步 operation 或 `SyncDevicesViewController` 行为。
- 不改变 switches 列表页状态展示逻辑。
- 不处理未保存编辑内容的自动保存。

## 验证计划

- Battery power switch：构造或复用需要同步状态，长按进入 edit 页，确认 Name 右侧显示 `Device not synced`。
- AC power switch：构造或复用需要同步状态，长按进入 edit 页，确认 Name 右侧显示 `Device not synced`。
- 点击控件组进入同步页面。
- 同步成功后状态可刷新，edit 页或返回后的 switches 页面不再显示需要同步状态。
- 无需同步、新建、未绑定真实 power switch 的页面不显示控件组。
- 运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
