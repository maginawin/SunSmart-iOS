# EFC Mock 按钮未关联组提示方案

## 背景

真实 EFC 设备监控页的三个 Mock 按钮位于 `EmerFireAlarmMonitorVC.configureActions()`：

- `mockFireAlarmAction()`
- `mockPowerLossAction()`
- `mockRestoreAction()`

页面空态已经用 `groups.isEmpty` 展示 `Not associate with Group(s)!`，但三个 Mock action 目前只读取配置后直接发送亮度或恢复命令。现有发送链路会在缺少 publish group 时提示发布组错误，在关联组内没有设备时已有 `Not executed. No devices in associated groups.`，但没有覆盖“完全没有关联 group”这一层业务前置条件。

## 目标

当真实 EFC 设备页面处于 `Not associate with Group(s)!` 状态时，点击以下 Mock 按钮不发送 Mesh 命令，并通过 toast 提示：

`Not executed. Please link a group first.`

覆盖按钮：

- Mock fire alarm
- Mock power loss
- Mock restore

## 现有代码事实

- `EmerFireAlarmMonitorRendering.updateEmptyUI()` 在 `groups.isEmpty` 时显示 `Not associate with Group(s)!` 空态和 `Setting` 按钮。
- `EmerFireAlarmMonitorViewModel.activeAssociatedGroupAddresses()` 已从当前 config / device configuration 汇总 `activeLightLCGroupAddresses`。
- `EmerFireAlarmMonitorViewModel.activeAssociatedGroupsContainDevices` 当前用于 trigger / stop 的“关联组内是否有设备”判断。
- 三个 Mock action 共用 `sendBrightness(...)` 或 `lightLCOnAction(...)`，但 action 入口本身没有先判断是否有关联组。
- 本地化文件已有 `Not executed. Please link a device first.` 和 `Not executed. No devices in associated groups.`，还没有本次新增文案 key。

## 方案对比

### 方案 A：在三个 Mock action 入口加共享 guard

在 `EmerFireAlarmMonitorVC` 增加一个小的前置判断方法，例如 `guardMockActionHasAssociatedGroup()`，内部复用 `activeAssociatedGroupAddresses().isEmpty`。三个 Mock action 在读取配置或发送命令前先调用该 guard。

优点：

- 改动最小，行为只影响指定的三个 Mock 按钮。
- 不改变 trigger / stop、group cell 手动控制、publish group 获取和同步流程。
- 后续如果 Mock action 继续分支到不同发送函数，仍能保证入口一致。

缺点：

- trigger / stop 暂不获得同样提示；但这符合当前需求只点名 Mock 按钮。

### 方案 B：下沉到 `sendBrightness(...)` 和 `lightLCOnAction(...)`

在底层发送函数里统一判断是否有关联组。

优点：

- 能覆盖更多调用路径。

缺点：

- 会改变 trigger / stop、header action 等非本次点名路径，风险扩大。
- `lightLCOnAction(...)` 还被 stop / header status 使用，未确认这些路径是否应显示同一文案。

### 方案 C：只依赖 UI 禁用按钮

在空态时禁用或隐藏 Mock 按钮。

优点：

- 可以避免点击行为。

缺点：

- 不满足“点击时 toast 提示”的明确需求。
- 会改变可见交互，影响 UI 范围更大。

## 推荐方案

采用方案 A。

具体开发步骤：

1. 在 `EmerFireAlarmMonitorVC` 增加共享前置判断，判断 `activeAssociatedGroupAddresses().isEmpty`。
2. 判断为空时调用 `XWHUDManager.showTipHUD("Not executed. Please link a group first.".localizedString, isLineFeed: true)` 并返回 `false`。
3. 在 `mockFireAlarmAction()`、`mockPowerLossAction()`、`mockRestoreAction()` 读取配置前调用该 guard。
4. 在 `SunSmart/en.lproj/Localizable.strings` 添加英文 key：
   `Not executed. Please link a group first.`
5. 在 `SunSmart/zh-Hans.lproj/Localizable.strings` 添加中文翻译：
   `未执行。请先关联组。`
6. 更新 `scripts/check_efc_controller_flows.sh`，增加 contract，确保三个 Mock action 仍存在，并且监控页包含新的 group-first toast 文案。

## 行为边界

- 只处理真实 EFC 设备监控页三个 Mock 按钮。
- 不修改 Edit 页关联组逻辑。
- 不修改 EFC 同步、publish group、Scene、Light LC、vendor payload 或 AppKey 逻辑。
- 不改变现有 `Not executed. No devices in associated groups.`：当有关联组但组内没有设备时仍保留该提示。
- 不新增 Auth 信息。

## 验证计划

1. 运行 EFC controller flow contract：

   `bash scripts/check_efc_controller_flows.sh`

2. 检查空态文案和新增本地化 key：

   `rg -n "Not executed\\. Please link a group first|mockFireAlarmAction|mockPowerLossAction|mockRestoreAction" SunSmart/Main/Device/Device1.5/FireAlarm SunSmart/en.lproj SunSmart/zh-Hans.lproj`

3. 检查 diff 空白问题：

   `git diff --check`

4. iPhoneOS 编译验证：

   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 待确认

请确认是否按推荐方案 A 执行。
