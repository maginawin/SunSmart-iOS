# Emergency Fire Dual Event Add/Edit Design

## 背景

本设计覆盖 Site - Space 中 Add -> Others -> Emer&Fire Alarm Controller 的虚拟设备创建页，以及 Emergency Fire Controller 的 Edit 虚拟设备、Edit 已绑定真实设备页面。

当前 App 已接入 Emergency Fire SDK v2 协议和同步接口，但编辑页仍保留旧的 Power Loss / Fire Alarm 二选一 UI 与单一 `workMode` 同步语义。本次需求要求 Fire Alarm 与 Power Loss 同时展示、同时可配置，并让一个 `Associate With Group(s)` 同时作用于两种 emergency function。

Figma 参考节点：

- `https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-drafts?node-id=136-8064&t=cZ9FzgOdGoln46oT-11`

若 Figma 与文字需求冲突，以文字需求为准；文字没有覆盖的 UI/交互细节需要继续确认。

## 目标

1. 添加虚拟 EFC、Edit 虚拟 EFC、Edit 已绑定真实 EFC 使用同一套双事件配置页面。
2. 移除 Power Loss 与 Fire Alarm 二选一逻辑，两者固定同时展示。
3. `Associate With Group(s)` 同时作用于 Power Loss Emergency 和 Fire Alarm Emergency。
4. 同空间内相同应急功能不能复用同一个 group。
5. 仅配置 associated groups 的亮度，不控制色温。
6. 使用 SDK v2 接口生成 Power Loss、Fire Alarm、Restore 三个 state 的 resend 和 action config。
7. 资源策略保持保守：优先复用现有图片资源；如果缺少图片资源，需要停止并向用户确认上传，不自行绘制替代图。

## 非目标

1. 不重做 Dongle、Battery Power Switch、AC Power Switch 添加流程。
2. 不实现完整 v2 action_type 高级编辑器。
3. 不新增 Auth 相关信息。
4. 不调整无关 target、资源、依赖或大范围格式化。
5. 不用 Simulator 作为最终构建校验。

## 方案选择

采用方案 A：在现有 Emergency Fire v2 基础上完整迁移到双事件语义。

旧 `workMode` 主导的单事件模型不能继续作为同步事实来源，否则 UI 显示两个事件但设备只同步一个事件。此版本 App 尚未发布，不需要兼容旧 `workMode` 或迁移旧配置。新保存路径以 Power Loss、Fire Alarm 两套 settings 同时有效为准。

## 数据模型设计

`EmergencyFireControllerConfiguration` 继续保留：

- `powerLossSettings`
- `fireAlarmSettings`

不再让单一 `workMode` 决定哪套 settings 生效，也不保留旧 `workMode` 作为兼容或迁移输入。新保存逻辑默认两套 settings 都有效。

需要调整的派生语义：

- `enabled`：新配置默认启用，只要存在 EFC 配置意图就下发 enabled。
- `activeLightLCGroupAddresses`：返回 Power Loss 与 Fire Alarm associated groups 的并集。
- `hasSyncIntent` / `hasSyncableConfiguration`：同时考虑两套 associated groups 和 pending cleanup。
- `resendParameters(for:)`：
  - `emergencyTrigger` 使用 Power Loss trigger interval/count。
  - `fireTrigger` 使用 Fire Alarm trigger interval/count。
  - `restore` 使用统一 Event Ends interval/count。
- `actionConfig(for:)`：
  - `emergencyTrigger` 派生 Power Loss brightness lightness action。
  - `fireTrigger` 派生 Fire Alarm brightness lightness action。
  - `restore` 根据 Event Ends action type 派生。

旧配置迁移：

- 不需要迁移旧配置。
- 不需要为旧 `workMode` 数据保留兼容解码逻辑。
- 实施时可以直接移除旧 `workMode` 作为配置事实来源。

## 默认值与范围

When The Emergency Event Occurs:

| 字段 | 默认值 | 范围 | 步进 |
| --- | --- | --- | --- |
| Fire Alarm Emergency brightness | 100% | 10%-100% | 1% |
| Power Loss Emergency brightness | 10% | 1%-100% | 1% |
| Repeatedly Send Emergency Control Every | 5s | 1-10s | 1s |

When The Emergency Event Ends:

| 字段 | 默认值 | 范围 | 步进 |
| --- | --- | --- | --- |
| Action type | Restore AUTO | Restore AUTO / Set Brightness to / None | - |
| Set Brightness to | 100% | 1%-100% | 1% |
| Resuming in | 2s | 0-120s | 1s |
| Send Count | 2 | 1-5 | 1 |

`Set Brightness to` 的 brightness 控件只在 action type 为 `Set Brightness to` 时展示。`Restore AUTO` 和 `None` 不展示 brightness 控件。

## UI 设计

三个入口复用 `LinkedEmerFireEditVC`：

- 添加虚拟设备：底部 `CREATE`。
- Edit 虚拟设备：底部 `LINK`。
- Edit 已绑定真实设备：底部 `LINKED`，保存后如配置变更进入同步。

页面顺序：

1. Name
2. Report To Gateway
3. Associate With Group(s)
4. When The Emergency Event Occurs
   - Fire Alarm Emergency brightness
   - Power Loss Emergency brightness
   - Repeatedly Send Emergency Control Every
5. When The Emergency Event Ends
   - Action type
   - Set Brightness to brightness, only when selected
   - Resuming in
   - Send Count

旧的 `Enable Power Loss Emergency`、`Enable Fire Alarm Emergency` toggle 不再展示。切换事件时清空另一类 groups 的旧逻辑必须删除。

旧 instruction cells 不再按原长列表展示；如需要说明文案，使用 section subtitle 形式，优先匹配 Figma：

- `Fire emergency take higher priority.`
- `Execution will only begin after all emergency events have ceased.`

## Group 选择与冲突规则

`Associate With Group(s)` 是一个全局选择，保存时同一组选中地址同时写入 Power Loss 和 Fire Alarm settings。

同空间内冲突规则：

- 如果其他 EFC 的 Power Loss 已关联 group A，当前 EFC 不能选择 group A。
- 如果其他 EFC 的 Fire Alarm 已关联 group A，当前 EFC 不能选择 group A。
- 因为当前页面全局选择会同时作用于两种 function，禁用集合取 Power Loss 占用与 Fire Alarm 占用的并集。
- Edit 当前设备时排除自身 `deviceId`。
- 虚拟设备和已绑定真实设备使用同一规则。

需要两层保护：

1. 组选择页传入 disabled group addresses，阻止用户选择。
2. 保存前 `validateBeforeSaving()` 再检查冲突，避免 UI 状态遗漏导致错误保存。

冲突提示可复用现有 `emer_fire_same_function_group_occupied`；如果语义不准确，再新增英文文案。

## 同步设计

同步层要从单一 active mode 改为双事件规划。

控制器自身任务：

- `emergencyEnabled`
- `emergencyResendParameters(.emergencyTrigger)`
- `emergencyResendParameters(.fireTrigger)`
- `emergencyResendParameters(.restore)`
- `emergencyActionConfig(.emergencyTrigger)`
- `emergencyActionConfig(.fireTrigger)`
- `emergencyActionConfig(.restore)`
- `emergencyRestoreDelay`

关联灯组任务：

- Associated groups 使用 Power Loss 与 Fire Alarm 的并集。
- 同一个 group 只生成一次订阅/cleanup 任务，避免重复 Scene Server / Light LC subscription。
- 对每个关联 group，仅配置 brightness 相关的 action，不控制色温。
- 删除或取消关联后，pending cleanup 仍按 mode 记录，但实际 cleanup 需要按 group 去重执行。

Restore action 派生：

- `Restore AUTO`：使用 Light LC On/Auto 语义，不派生 CTL 色温控制。
- `Set Brightness to`：派生 lightness action，brightness 默认 100%，范围 1%-100%。
- `None`：派生 invalid action。

## Add Device 绑定设计

创建虚拟 EFC 后，Edit 虚拟设备底部展示 `LINK`。点击后复用现有 `DeviceAddViewController`：

- `bindTarget = .emergencyFire(device)`
- allowed device type 限制为 `.emergencyController`
- selection mode 为 single
- 不允许 target/category 选择

绑定真实设备成功后：

- `DeviceEmerFireStore.bind(_:to:in:)` 写入 `bindNodeAddress`
- `isSynced = false`
- 返回 Edit 页面后展示 `LINKED`
- 若配置有 sync intent，后续 SAVE 进入 EFC sync

## 资源策略

实现 UI 时优先复用当前项目已有组件、图片资源、颜色、字体和 cell 风格。

如果 Figma 中某个图标或控件图片在现有 assets 中不存在：

1. 不手绘替代图。
2. 不新增临时 SVG 或自制图片。
3. 停止该资源相关实现并向用户确认需要上传的资源。

## 文件影响范围

预计修改：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditState.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireEditRow.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/ViewModels/LinkedEmerFireEditViewModel.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift`

可能新增：

- Event Ends action type cell，优先复用现有 cell 风格。
- 新本地化 key；如新增，需要同步检查相关 target 资源影响。

## 验证计划

1. 静态搜索确认旧二选一逻辑被清除：
   - 不能再有选择 Power Loss 时关闭 Fire Alarm 的逻辑。
   - 不能再有保存 Power Loss 时清空 Fire Alarm groups 的逻辑。
2. 检查默认值和范围：
   - Fire Alarm brightness 100%，10%-100%。
   - Power Loss brightness 10%，1%-100%。
   - Trigger interval 5s，1-10s。
   - Event Ends action 默认 Restore AUTO。
   - Set Brightness to 默认 100%，1%-100%。
   - Resuming in 2s，0-120s。
   - Send Count 2，1-5。
3. 检查 group 冲突：
   - 同空间其他 EFC 占用的 Power Loss / Fire Alarm groups 均不能选择。
   - 当前设备自身已选 groups 不被误禁用。
   - 保存前冲突 guard 生效。
4. 检查 sync planner：
   - Power Loss、Fire Alarm、Restore 三个 state 都生成 resend 和 action config。
   - 同一 selected group 不重复生成相同订阅任务。
   - 移除 group 后 pending cleanup 仍可执行并清理。
5. 跑 iPhoneOS 构建：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

6. 代码级核对三个入口：
   - Add virtual EFC -> CREATE。
   - Edit virtual EFC -> LINK。
   - Edit bound EFC -> LINKED / SAVE sync。

## 风险与处理

1. 旧 `workMode` 引用较多，移除时容易漏掉 monitor 或 sync planner 的单模式判断。
   - 处理：实施时按 `workMode`、`activeModeSettings`、`activeLightLCGroupAddresses`、`makeActiveMode` 关键词逐项清理。
2. 同一个全局 group 同时写入两套 settings，可能导致关联任务重复。
   - 处理：sync planner 以 group address 去重生成订阅任务，action config 仍按 state 分别生成。
3. Restore AUTO 的协议映射不能继续使用旧 CTL 默认。
   - 处理：明确改为 Light LC On/Auto 语义；如 SDK action 无法直接表达，需要在实施前再次确认协议映射。
4. 新 UI 所需图标可能缺失。
   - 处理：只复用已有资源；缺失时向用户确认，不自绘。

## 确认记录

当前设计已确认：

- 采用方案 A。
- Event Ends action 默认 `Restore AUTO`。
- `Set Brightness to` 默认 100%，范围 1%-100%。
- Figma 与文字冲突时，以文字需求为准。
- 缺少图片资源时向用户确认，不自行绘制。

无剩余待确认需求。
