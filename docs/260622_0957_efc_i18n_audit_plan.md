# EFC 页面国际化审计与修复计划

## 范围

本次只分析 Emergency & Fire Controller 相关的用户可见页面和从这些页面进入的子页面：

- 添加 EFC 虚拟设备：`DevicesViewController.showEmerFireCreatePage()` 打开的 `LinkedEmerFireEditVC` create mode，以及 Others 添加弹窗入口。
- 编辑 EFC 设备页面：`LinkedEmerFireEditVC` 与 `LinkedEmerFireEditVC+Table`。
- 编辑页进入的子页面：关联组选择页、绑定真实设备的 Add Device 页面、保存后进入的 EFC sync 页面。
- EFC 设备页右上角菜单进入的子页面：Edit、Delete cleanup sync、Information、Refresh。

不纳入本次修复范围：

- 调试日志、`print`、`fatalError`、内部 notification name。
- 已废弃或演示性质的旧页面，例如 `EmerFireAlarmDevicesController` 中的固定 `EFC1` demo 数据，除非后续确认仍可从生产入口访问。

## 结论

当前 EFC 相关 UI 仍存在未国际化内容。问题主要分三类：

1. 直接硬编码英文且用户可见。
2. 已调用 `.localizedString`，但 `zh-Hans` 缺少对应 key。
3. 共用入口组件不是 EFC 专属，但 EFC 流程会触达，需要一并修复。

右上角菜单本身的 `edit`、`delete`、`information`、`refresh` 已走本地化；主要问题在菜单进入后的 Edit / Sync / Information 文案。

## 问题清单

### 添加 EFC 虚拟设备

入口弹窗：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/OthersViewController.swift`
  - `Emer&Fire Alarm\nController`：添加 Others 设备弹窗里的 EFC 入口，硬编码英文。

创建页本体复用 Edit 页，因此以下 Edit 页问题也会影响添加虚拟设备。

### 编辑 EFC 设备页面

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
  - `Emer&Fire Controller`：create mode 导航标题，硬编码英文。
  - `Edit`：edit mode 导航标题，硬编码英文，应复用已有 `edit` key。
  - `LINKED`：已绑定 toast，硬编码英文。
  - `You can't choose other devices.`：绑定真实 EFC 设备时的禁止选择提示，硬编码英文。
  - `Cannot add, type mismatch`：绑定真实 EFC 设备时的类型不匹配提示，硬编码英文。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
  - `Waiting for setup`：Report To Gateway 右侧状态和 toast，硬编码英文。
  - `When The Emergency Event Occurs:`：说明区标题，硬编码英文。
  - `Fire emergency take higher priority.`：说明区内容，硬编码英文。
  - `When The Emergency Event Ends:`：说明区标题，硬编码英文。
  - `Execution will only begin after all emergency events have ceased.`：说明区内容，硬编码英文。
  - `Restore AUTO`、`Set Brightness To`、`None`：恢复动作选项，硬编码英文；其中部分可复用现有 key，但当前代码未使用。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`
  - `Power Loss Emergency`：步进卡标题，硬编码英文。
  - `Set Brightness To:`：字段标题，硬编码英文。
  - `Repeatedly Send Emergency Control Every`：步进卡标题，硬编码英文。
  - `Set Brightness To`：恢复亮度标题，硬编码英文。
  - `Resuming in:`：恢复倒计时标题，硬编码英文。
  - `Send Count (5-second interval):`：发送次数标题，硬编码英文。

- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireNameCell.swift`
  - `Name`：名称字段标题，硬编码英文；应复用已有 `name` key。

- `SunSmart/Main/Device/Device1.5/FireAlarm/views/PJLinkedStaOpertionsView.swift`
  - `LINKED`、`LINK`：底部绑定状态按钮，硬编码英文。

### 编辑页进入的子页面

关联组选择页：

- `select_group(s)`、`Not selectable. This group is already associated with a device of the same type.` 已走本地化，且 `zh-Hans` 有翻译。

绑定真实设备 Add Device 页面：

- `LinkedEmerFireEditVC.linkRealDeviceAction()` 中的 `forbiddenSelectionTip` 和 `forbiddenDeviceTypeTip` 是硬编码英文，属于该子流程的用户可见 toast。
- `DeviceAddTargetSelectView` 是共用目标选择组件，EFC 添加/绑定流程可能触达：
  - `Space` 硬编码英文，应复用 `space`。
  - `Battery Power Switch:`、`AC Power Switch:` 硬编码英文，应新增或复用对应 power switch key。

保存后 EFC sync 页面：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
  - `Publication`、`Enable`、`Resend`、`Restore Delay`、`Action Config`、`Lightness Group`、`LC Group`、`Group Subscription`、`Group Cleanup`、`Delete Cleanup`、`Delete Configuration` 是 `EmergencyFireControllerSyncTaskKind.rawValue`，当前 sync cell 直接显示 raw value。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
  - `Scene Publication`、`Trigger Resend`、`Restore Resend`、`Restore Delay`、`Enable`、`Emergency Action`、`Fire Action`、`Restore Action` 等任务 title 硬编码英文。当前 sync cell 主要显示 kind raw value，但这些 title 仍属于同步模型的用户可见数据，应一起本地化或确认不展示后删除冗余。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`
  - `Group Cleanup` 等 local-only cleanup 任务标题硬编码英文。

### 右上角菜单进入的子页面

EFC Monitor 页面：

- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmStatusLegendHeaderView.swift`
  - `Triggered`、`Resume`、`Inactive`：底部 Status & Settings legend，硬编码英文。

- `SunSmart/Main/Device/Device1.5/FireAlarm/views/EmerFireAlarmMoniHead.swift`
  - 初始化默认 `Fire Alarm Emergency` 硬编码英文。运行时会被 `renderRealState` 覆盖，但初始 frame 仍建议本地化，避免短暂闪现。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`
  - Information 页 `emptyGroupText: "Not yet linked to a group".localizedString` 已调用本地化，但当前 strings 未发现对应 key，需要补齐。

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlan.swift`
  - `The device needs to be repaired.` 在 `EmergencyFireControllerPublishGroupError.errorDescription` 中直接返回英文。已有 `device_repair_message`，应改为复用该 key。

Monitor 里以下文案已走本地化且 `zh-Hans` 已有翻译：

- `Status Set`
- `Warning`
- `Go Setting`
- gateway warning 长说明
- `Not executed. Please link a device first.`
- `Not executed. Please link a group first.`
- `Not executed. No devices in associated groups.`
- `Uncontrollable in emergency situations`
- `Are you sure to delete the EFC device?`

## zh-Hans 缺失或需新增的重点 key

已有英文 key 但 `zh-Hans` 缺失：

| Key | 建议简体中文 |
| --- | --- |
| `emergency_event_ends` | 紧急事件结束 |
| `set_brightness_to_value` | 设置亮度为 %@ |
| `restore_auto` | 自动 |
| `restore_none` | 无 |

建议新增 EFC 专用 key：

| 建议 key | 英文 | 简体中文 |
| --- | --- | --- |
| `efc_entry_title` | Emer&Fire Alarm\nController | 应急火警\n控制器 |
| `efc_controller_title` | Emer&Fire Controller | 应急火警控制器 |
| `efc_waiting_for_setup` | Waiting for setup | 等待设置 |
| `efc_event_occurs_title` | When The Emergency Event Occurs: | 当紧急事件发生时： |
| `efc_event_occurs_tip` | Fire emergency take higher priority. | 火警应急优先级更高。 |
| `efc_event_ends_title` | When The Emergency Event Ends: | 当紧急事件结束时： |
| `efc_event_ends_tip` | Execution will only begin after all emergency events have ceased. | 所有紧急事件结束后才会开始执行。 |
| `efc_power_loss_emergency` | Power Loss Emergency | 断电应急 |
| `efc_repeatedly_send_emergency_control_every` | Repeatedly Send Emergency Control Every | 每隔以下时间重复发送应急控制 |
| `efc_send_count_5_second_interval` | Send Count (5-second interval): | 发送次数（每 5 秒间隔）： |
| `efc_restore_auto` | Restore AUTO | 恢复自动控制 |
| `efc_link` | LINK | 关联 |
| `efc_linked` | LINKED | 已关联 |
| `efc_forbidden_other_devices` | You can't choose other devices. | 不能选择其它设备。 |
| `efc_type_mismatch` | Cannot add, type mismatch | 无法添加，设备类型不匹配。 |
| `efc_not_yet_linked_group` | Not yet linked to a group | 尚未关联到组 |
| `efc_status_triggered` | Triggered | 已触发 |
| `efc_status_resume` | Resume | 恢复 |
| `efc_status_inactive` | Inactive | 未激活 |

建议新增 sync 相关 key：

| 建议 key | 英文 | 简体中文 |
| --- | --- | --- |
| `efc_sync_publication` | Publication | 发布配置 |
| `efc_sync_enable` | Enable | 启用状态 |
| `efc_sync_resend` | Resend | 重发参数 |
| `efc_sync_restore_delay` | Restore Delay | 恢复延迟 |
| `efc_sync_action_config` | Action Config | 动作配置 |
| `efc_sync_lightness_group` | Lightness Group | 亮度组订阅 |
| `efc_sync_lc_group` | LC Group | LC 组订阅 |
| `efc_sync_group_subscription` | Group Subscription | 组订阅 |
| `efc_sync_group_cleanup` | Group Cleanup | 组清理 |
| `efc_sync_delete_cleanup` | Delete Cleanup | 删除清理 |
| `efc_sync_delete_configuration` | Delete Configuration | 删除配置 |
| `efc_sync_scene_publication` | Scene Publication | 场景发布配置 |
| `efc_sync_trigger_resend` | Trigger Resend | 触发重发 |
| `efc_sync_restore_resend` | Restore Resend | 恢复重发 |
| `efc_sync_emergency_action` | Emergency Action | 断电应急动作 |
| `efc_sync_fire_action` | Fire Action | 火警动作 |
| `efc_sync_restore_action` | Restore Action | 恢复动作 |

共用 Add Target 组件建议补齐：

| 建议 key | 英文 | 简体中文 |
| --- | --- | --- |
| `battery_power_switch_title` | Battery Power Switch | 电池供电开关 |
| `ac_power_switch_title` | AC Power Switch | AC 供电开关 |

## 修复方案

### Task 1: 补齐 strings

修改：

- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`

动作：

- 先补齐 `zh-Hans` 中已存在英文 key 但缺失的翻译：`emergency_event_ends`、`set_brightness_to_value`、`restore_auto`、`restore_none`。
- 新增 EFC 专用 key，避免继续使用长英文原文作为 key。
- 新增 sync task key，后续由 enum / task title 转换使用。
- 新增 Add Target 组件需要的 power switch title key。

注意：

- 保留现有英文文案作为 `en` 值，避免影响英文 UI。
- 简体中文优先使用产品语义一致的短文案，避免底部 drawer、legend 和按钮被撑宽。

### Task 2: 修复添加虚拟 EFC 和 Edit 主页面

修改：

- `OthersViewController.swift`
- `LinkedEmerFireEditVC.swift`
- `LinkedEmerFireEditVC+Table.swift`
- `LinkedEmerFireEditState.swift`
- `EmerFireNameCell.swift`
- `PJLinkedStaOpertionsView.swift`
- `EmerFireSelectionCell.swift` 中恢复亮度字段标题如需复用 key，也一起调整。

动作：

- 添加 Others 弹窗 EFC 入口使用 `efc_entry_title`。
- create mode title 使用 `efc_controller_title`；edit mode title 使用已有 `edit`。
- Edit 表格所有固定标题、说明、恢复动作选项、Report To Gateway 状态、Name label 改为本地化。
- Link/Linked 底部按钮和 toast 改为本地化。
- 绑定真实设备流程的禁止选择/类型不匹配 toast 改为本地化。

### Task 3: 修复 Monitor 和右上角菜单子页面

修改：

- `EmerFireAlarmStatusLegendHeaderView.swift`
- `EmerFireAlarmMoniHead.swift`
- `EmerFireAlarmMonitorRouting.swift`
- `EmergencyFireControllerSyncPlan.swift`

动作：

- Legend 文案改为 `efc_status_triggered`、`efc_status_resume`、`efc_status_inactive`。
- Monitor header 默认值改为 `Fire Alarm Emergency`.localizedString 或新 key。
- Information 页 empty group 文案补 key 并使用本地化。
- `EmergencyFireControllerPublishGroupError.missingSceneClientModel` 等 repair 文案复用 `device_repair_message`。

### Task 4: 修复 EFC sync 子页面文案

修改：

- `EmergencyFireControllerSyncPlan.swift`
- `DeviceEmerFireData+Sync.swift`
- `EmergencyFireControllerSyncPlanner.swift`
- `EmerFireAlarmControllerSyncVC.swift`

动作：

- 给 `EmergencyFireControllerSyncTaskKind` 增加本地化 title 入口，sync cell 显示本地化 title，不直接显示 raw value。
- Controller task title 使用 sync 相关 key；如果 UI 最终只展示 kind title，也仍建议把 title 数据改为本地化，避免后续展开详情时漏出英文。
- `EmergencyFireControllerState.taskTitle` 改为本地化或新增用于 task title 的本地化方法。

### Task 5: 修复 EFC 相关共用入口组件

修改：

- `DeviceAddTargetSelectView.swift`

动作：

- `Space` 改用已有 `space`。
- `Battery Power Switch:`、`AC Power Switch:` 改用新增 key 后拼接冒号，或直接新增带冒号 key。

### Task 6: 回归检查

静态检查：

- 用 `rg` 复查 EFC 相关文件中残留的用户可见英文硬编码，重点匹配：
  - `Waiting for setup`
  - `When The Emergency Event`
  - `Restore AUTO`
  - `Repeatedly Send Emergency`
  - `LINKED`
  - `Triggered`
  - `Scene Publication`
  - `Group Cleanup`
  - `Emer&Fire`

构建验证：

- 按项目规则运行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如修改共用 Add Target 或 strings，建议至少额外确认其它品牌 target 是否受影响：

- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

手工 UI 验证：

- 简体中文环境下，从 Devices > Add > Others > EFC 进入添加虚拟设备页。
- 简体中文环境下，进入 EFC Edit，检查标题、Name、Report To Gateway、Associated Groups、说明卡、亮度卡、恢复动作卡、Link/Linked。
- 从 Edit 进入 Select Groups、Bind to new device、Save 后 Sync。
- 从 EFC device page 右上角进入 Edit、Information、Delete cleanup Sync。

## 风险与边界

- `zh-Hans` 目前已有一批 EFC 翻译，但 key 命名混用英文原文和业务 key。本次建议新增清晰的 EFC 专用 key，后续可逐步迁移旧 key，但不要在本次顺手重命名无关 FireAlarm 文案。
- `DeviceAddTargetSelectView` 是共享组件，修复时要确认 Battery/AC Power Switch 添加流程仍显示合理。
- `EmergencyFireControllerSyncTask.title` 当前不一定在所有 cell 中展示，但它是 sync 数据模型的一部分，建议和 `kind` 一起本地化，避免后续 UI 展开时再次漏英文。
