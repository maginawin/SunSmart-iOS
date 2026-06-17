# EFC Status Content List 设计方案

## 背景

EFC 设备页展开后的 `EmerFireAlarmStatusSetView` 目前展示 4 行：

- `Power supply fails`
- `Power is restored`
- `Fire alarm occurs`
- `Fire alarm stops`

Figma 节点 `155:8556` 的 content list 只保留 3 行，并把恢复类信息合并为一个统一的结束事件：

- `Fire alarm occurs`
- `Power supply fails`
- `Emergency event ends`

本次目标是让 App 展开列表对齐 Figma content list，同时保持 EFC 监控页的状态轮询、header 图标、手动控制和 bottom drawer 展开交互不变。

## 推荐方案

采用方案 A：轻微扩展 `EmerFireAlarmStatusSetView` 的 item/cell 展示模型，让一个列表 item 支持多组 detail/value。

原因：

- 可以按 Figma 第三行展示 `Action` 和 `Resuming in:` 两组信息。
- 普通两行 item 仍可复用同一个 cell，不需要新增专用 cell。
- 数据映射仍集中在 `EmerFireAlarmMonitorState.statusItems(for:)`，避免把配置解释逻辑扩散到 view 层。

## 目标展示

展开后的 content list 固定展示 3 行，顺序如下：

1. `Fire alarm occurs`
   - `Set Brightness To:` -> `configuration.fireAlarmSettings.triggerBrightness`
2. `Power supply fails`
   - `Set Brightness To:` -> `configuration.powerLossSettings.triggerBrightness`
3. `Emergency event ends`
   - `Action` -> 根据 `configuration.restoreSettings.actionType` 动态显示
   - `Resuming in:` -> `configuration.restoreSettings.resumingSeconds`

第三行的 `Action` 值规则：

- `.restoreAuto` 显示 `Auto`
- `.setBrightness` 显示 `Set Brightness to N%`
- `.none` 显示 `None`

## 范围

需要调整：

- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/EmerFireAlarmMonitorState.swift`
  - 生成 3 个 item。
  - 移除 monitor content list 对 `power_is_restored` 和 `fire_alarm_stops` 的输出。
  - 生成 `Emergency event ends` 的动态 action 和恢复秒数。
- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusSetView.swift`
  - item 模型从单组 `subtitle/value` 扩展为多组 detail/value。
  - table view 仍使用当前 cell。
- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusItemCell.swift`
  - 支持渲染 1 组或 2 组 detail/value。
  - 保持现有 title、辅助文字、右侧 value 的视觉风格。
- `SunSmart/en.lproj/Localizable.strings`
  - 新增 `emergency_event_ends`。
  - 复用已有 `action`、`resuming_in`、`set_brightness_to`。
  - 若需要显示 action value，新增最小必要本地化 key。

不调整：

- `EmerFireAlarmStatusSetView` 的展开/收起 shell、高度、shade 和 legend header。
- `EmerFireAlarmMonitorRendering.updateStatusSetRows(for:)` 的实时状态映射。
- EFC Mesh 协议、同步 planner、数据库模型和编辑页保存逻辑。
- 其他 target 的资源和配置，除非本地化检查发现共享 strings 需要同步。

## UI 结构

`EmerFireAlarmStatusItemCell` 保持单一 cell 类型。每行左侧是 title 和 detail label 列，右侧是 value label 列。

普通 item 只有一组 detail/value：

- 左侧：title + subtitle
- 右侧：value

`Emergency event ends` 有两组 detail/value：

- 左侧：title + `Action` + `Resuming in:`
- 右侧：action value + seconds value

cell 高度继续由 Auto Layout 自动计算，避免固定高度在第三行多一组文本时截断。

## 数据流

1. `EmerFireAlarmMonitorVC.updateStatusSetView()` 调用 `viewModel.statusItems()`。
2. `EmerFireAlarmMonitorState.statusItems(for:)` 从 `LinkedEmerFireConfig.configuration` 生成 3 行 item。
3. `EmerFireAlarmStatusSetView.updateItems(_:)` 保存 item 并刷新 table view。
4. `EmerFireAlarmStatusItemCell.configure(with:)` 根据 item 内 detail/value 数量渲染对应行。

配置改变后仍走当前 notification/render 流，不新增监听或状态源。

## 验证标准

- 展开列表只展示：
  - `Fire alarm occurs`
  - `Power supply fails`
  - `Emergency event ends`
- 展开列表不再展示：
  - `Power is restored`
  - `Fire alarm stops`
- `Fire alarm occurs` 使用 fire alarm trigger brightness。
- `Power supply fails` 使用 power loss trigger brightness。
- `Emergency event ends` 同时展示 action 和 resuming seconds。
- `restoreAuto`、`setBrightness`、`none` 三种 action type 有明确文本输出。
- iPhoneOS `xcodebuild` 编译通过。

## 风险与边界

- 第三行新增一组 detail/value 后可能增加 cell 高度；使用 automatic dimension 可以规避截断，但实现后需要检查展开 panel 内容是否仍完整显示。
- 本次只更新 monitor 展开列表。编辑页、同步页和协议层仍保留当前语义。
- Figma 的 content list 文案为英文；按项目约定 UI 文案默认英文，本次只补英文 key。
