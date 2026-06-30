# EFC Working Mode 弹窗样式优化设计

## 背景

EFC 设备的 Create/Edit 页已经新增 `Emergency Mode` 行，用于展示和选择 Working Mode。当前点击该行后使用普通 `SRAlertView` 展示选项，样式与 Add Device 页点击 `Add Device(s) to` 右侧按钮后的目标选择浮层不一致。

本次优化只调整 Working Mode 的选择弹窗样式和选项文案，不改变 Working Mode 的协议、保存、云同步、同步任务、UI 控件过滤逻辑。

## 已确认需求

- 点击 `Emergency Mode` 行里的 Working Mode 值时，弹出 App 支持的 Working Mode 列表。
- 弹窗样式与 Add Device 页 `Add Device(s) to` 目标选择弹窗保持一致。
- 弹窗只展示以下 3 个英文选项：
  - `Power Loss Only`
  - `Fire Alarm Only`
  - `Power Loss & Fire Alarm`
- 当前 Working Mode 对应的行需要展示选中态。
- 点击空白处关闭弹窗。
- App 仍不展示 `Disabled` 选项。

`Fire Alarm` 是本需求确认后的 UI 文案。此前的错误拼写已修正，实施时不要使用错误拼写。

## 当前代码事实

- Add Device 的目标选择弹窗实现为 `DeviceAddTargetSelectView`。
- `DeviceAddTargetSelectView` 的关键交互和样式：
  - 全屏透明遮罩。
  - 点击遮罩 dismiss。
  - 深灰色内容浮层。
  - 圆角内容容器。
  - 表格行展示选项。
  - 当前选中项使用浅色背景。
- EFC Working Mode 当前入口在 `LinkedEmerFireEditVC+Table.swift` 的 `showWorkingModeSelection()`。
- 当前 EFC Working Mode 弹窗使用 `SRAlertView`，需要替换。

## 方案

采用方案 A：新增 EFC 专用 Working Mode 单选浮层，不改 Add Device 现有 `DeviceAddTargetSelectView`。

原因：

- 改动范围最小，只影响 EFC Create/Edit 页。
- 不触碰 Add Device 目标选择流程，降低回归风险。
- 可以复刻 Add Device 浮层视觉，同时保留 EFC 专用的三项单选语义。

不采用通用化重构，因为这次需求只要求一个小型单选弹窗。抽象 `DeviceAddTargetSelectView` 会扩大影响面到 Classic/Professional Add Device 流程，不符合本次优化范围。

## 组件设计

新增一个 EFC 专用视图，例如 `EmergencyFireWorkingModeSelectView`。

职责：

- 接收 anchor point，用于确定浮层显示位置。
- 接收当前 `EmergencyFireWorkingMode`。
- 接收可选模式列表，固定为 `.powerLossOnly`、`.fireAlarmOnly`、`.powerLossAndFireAlarm`。
- 接收选择回调。
- 展示三行 Working Mode 选项。
- 点击选项后回调选中的 mode，然后关闭浮层。
- 点击遮罩直接关闭，不改变选中值。

该组件只负责选择 UI，不负责保存状态、刷新表格、触发同步任务。

## UI 与交互

显示位置：

- 点击 `Emergency Mode` 行时，使用该 cell 在 window 中的 frame 计算 anchor。
- 浮层显示在该行下方，水平位置尽量靠近右侧当前值区域。
- 横向位置使用与 Add Device 弹窗一致的安全边距 clamp，避免超出屏幕。

样式：

- 遮罩背景透明。
- 内容背景使用 Add Device 目标选择弹窗同款深灰色。
- 内容圆角使用同款半径。
- 行高使用同款高度。
- 行文字为白色、轻字重。
- 当前选中项显示浅色选中背景。
- 不显示取消按钮。

交互：

- 点击 `Power Loss Only`：更新为 `.powerLossOnly`，关闭弹窗，刷新表格。
- 点击 `Fire Alarm Only`：更新为 `.fireAlarmOnly`，关闭弹窗，刷新表格。
- 点击 `Power Loss & Fire Alarm`：更新为 `.powerLossAndFireAlarm`，关闭弹窗，刷新表格。
- 点击空白处：关闭弹窗，不更新 Working Mode。

## 数据流

`LinkedEmerFireEditVC+Table.swift` 仍是入口：

1. 用户点击 `.emergencyMode` 行。
2. VC 计算 cell anchor point。
3. VC 调用 `EmergencyFireWorkingModeSelectView.show(...)`。
4. 用户选择某个 mode。
5. 回调中调用 `state.updateWorkingMode(mode)`。
6. VC `tableView.reloadData()`。
7. 原有 `visibleRows` 根据 `state.workingMode` 过滤 `Power Loss` / `Fire Alarm` 相关控件。

保存、云同步、真实设备同步仍走现有 Working Mode 数据流，不在本次修改中调整。

## 本地化

英文文案需要更新为：

- `"efc_working_mode_power_loss_only" = "Power Loss Only";`
- `"efc_working_mode_fire_alarm_only" = "Fire Alarm Only";`
- `"efc_working_mode_power_loss_and_fire_alarm" = "Power Loss & Fire Alarm";`

中文文案保持现有语义即可，不因本次英文笔误修正调整中文。

## 验证方案

- 更新 `scripts/check_efc_controller_flows.sh`：
  - 检查 `showWorkingModeSelection()` 不再使用 `SRAlertView`。
  - 检查新增 Working Mode 专用浮层存在。
  - 检查浮层支持点击遮罩关闭。
  - 检查当前项有选中态。
  - 检查英文文案为 `Fire Alarm Only` 和 `Power Loss & Fire Alarm`。
- 运行 `bash scripts/check_efc_controller_flows.sh`。
- 运行 `git diff --check`。
- 运行 iPhoneOS 构建：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 非目标

- 不修改 `EmergencyFireWorkingMode` 枚举 raw value。
- 不修改 `0x4D/0x05` 协议。
- 不修改云同步、云分享或同步任务生成逻辑。
- 不修改 Add Device 目标选择弹窗本身。
- 不展示 `Disabled`。
