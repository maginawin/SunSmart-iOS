# Proximity/Predictive lighting with photocell 组内快速添加设备后显示同步失败图标分析

## 1. 结论

本次设备已经成功完成配网、加入组、双场景 Profile 配置、Motion Sensitivity 配置以及空 Path 对应的邻近照明配置。Add device 页面右侧显示的 `sync_failed` 图标是一次**本地结果校验误判**，不是设备实际仍有待同步数据，也不是加入组失败。

高置信度根因是：

1. Add device 快速添加流程把 `Proximity/Predictive lighting with photocell` 的 Night、Day 两套 Light LC 场景配置连续下发；
2. Day 配置最后执行，将设备当前 `lightLCProperty` 覆盖为 Day 的值；
3. 快速添加流程在全部命令结束后，重新校验计划中所有历史 `ProfileType`；
4. Night 的亮度属性校验读取的是已经被 Day 覆盖的当前 `node.lightLCProperty`，因此 Night 任务被判定失败；
5. `plan.hasVerificationFailure` 令 Add device 页面把设备状态设置为 `.syncFailed`，显示 `sync_failed` 图标；
6. Group 页面重新按最终持久化状态计算 `node.needSyncGroupData`。Night/Day 场景均已分别保存，组订阅、Sensitivity、邻近照明空邻居列表也已收敛，因此没有显示需要同步。

换句话说，两处 UI 使用了不同的判断时机和真值源：

| 页面 | 判断方式 | 本次结果 |
| --- | --- | --- |
| Add device | 全部命令完成后，回看快速添加计划中的每一个历史操作 | Night 操作被 Day 当前状态覆盖，误判 `.syncFailed` |
| Group / Members | 根据最终 Node、场景缓存、组配置重新计算 `needSyncGroupData` | 最终状态已收敛，不需要同步 |

## 2. 问题范围

- Group Profile：`Proximity/Predictive lighting with photocell`
- Group Address：`0xC000`
- 新设备 Primary Unicast Address：`0x0082`
- CID：`0x0A78`
- PID：`0x2502`
- Path：未配置，因此目标邻居列表为空
- 日志：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/fix/add to group failed.txt`
- 当前 worktree：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix`
- 工作区在分析前无未提交改动

## 3. 日志证据

### 3.1 配网和加入组成功

日志第 599、608、617、626、635、644、653、662 行显示，设备各相关 Model 对 `0xC000` 的 `ConfigModelSubscriptionAdd` 均返回：

- `ConfigModelSubscriptionStatus`
- `status: Success`
- `address: 49152`，即 `0xC000`

因此设备加入组的 Mesh Subscription 阶段没有失败。

日志第 1181 行明确输出“添加成功”。随后第 1184 行开始正常执行 Site 云同步。第 1182、1183 行的 `XPC connection invalid` 出现在“添加成功”之后，与组同步判定无直接关系。

### 3.2 Night 和 Day 两套场景均保存成功

Night 配置先写入：

- 第 785 行：Lightness On = `65535`
- 第 798 行：Lightness Prolong = `32767`
- 第 811 行：Lightness Standby = `19660`
- 第 889 行：`SceneStore(scene: 65281)`，即 `0xFF01`
- 第 898、899 行：场景 `0xFF01` 保存返回 `Success`

随后 Day 配置覆盖设备当前 Light LC 属性：

- 第 998 行：Lightness On = `0`
- 第 1011 行：Lightness Prolong = `0`
- 第 1024 行：Lightness Standby = `0`
- 第 1102 行：`SceneStore(scene: 65282)`，即 `0xFF02`
- 第 1111、1112 行：场景列表为 `[65281, 65282]`，证明 Night、Day 两个场景均已保存在设备中

因此，设备最终当前 `lightLCProperty` 是 Day 的 `0/0/0`，但 Scene 缓存中同时存在 Night `0xFF01` 和 Day `0xFF02`。

### 3.3 Motion Sensitivity 成功

日志第 1137 行下发：

- `motionSensitivity(62258)`
- 十六进制为 `0xF332`

第 1154、1156 行返回：

- `isSuccessful: true`
- `motionSensitivity(value: 62258, ...)`

请求值与返回值完全一致，不是同步失败来源。

### 3.4 未配置 Path 时，App 仍会下发空邻居列表，且设备返回成功

日志第 1157 行下发：

- `proximityLightingNeighborSet`
- `enabled: true`
- `relay: 2`
- `ttl: 0`
- `relayAppKeyIndex: 1`
- `neighborAddresses: []`

第 1158 行 Access PDU：

- Opcode：`F0 78 0A`
- Parameters：`41 02 01 00 01 02 00 00`
- 最后一个 `00` 是邻居数量，符合空 Path 的空邻居列表

第 1165 行设备响应 Parameters：`41 02 00`；第 1166、1168 行明确解析为：

- `ResponseCode.proximityLightingNeighborSet`
- `isSuccessful: true`

因此“未配置 Path”使本次目标邻居列表为空，但该命令自身成功，不是 Add device 图标出现的直接原因。

## 4. 源码数据流

### 4.1 新成员会强制生成完整 Profile 同步任务

`DeviceAddClassicModeController` 和 `DeviceAddProfessionalModeController` 都为新组成员传入：

- `GroupProfileSyncContext(reason: .memberAdded)`

`GroupProfileSyncContext.shouldForceFullProfileSync` 对 `.memberAdded` 固定返回 `true`，随后 `getNodeSyncProfiles` 使用该值生成 Night、Day 的完整 Profile 任务。

相关位置：

- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:61-63, 1352-1360`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:129-131, 1380-1388`
- `SunSmart/Common/Data/Node+SyncData.swift:12-26, 845-846`

### 4.2 Photocell Profile 会生成两个不同的 Light LC 场景

`getNodeSyncProfiles` 对 `proximityLightingWithPhotocell`：

1. 移除 General Scene；
2. 分别遍历 Night、Day Profile Scene；
3. 为每个 Scene 计算独立的 Light LC 属性；
4. 依次下发并执行 `lightControlStore`。

在正常差异计算中，代码会从 `lightControlSceneExecuteDatas` 按 Scene Number 取出每个场景自己的缓存，分别判断 Night、Day 是否已经收敛。

相关位置：

- `SunSmart/Common/Data/Node+SyncData.swift:928-930`
- `SunSmart/Common/Data/Node+SyncData.swift:956-1029`
- `SunSmart/Common/Data/Node+SyncData.swift:1056-1060`

### 4.3 快速添加流程将任务扁平化后，只在最后统一校验

`DeviceGroupFastAddSyncPlanner` 将 immediate handles 与所有 deferred task handles 合并成一个 `appendMessageHandles` 列表，同时保留全部 `verificationOperations`。

全部命令执行结束后：

- `hasVerificationFailure` 遍历全部历史操作并读取此刻的 Node 当前状态；
- `resolveFastAddGroupSyncFailed` 只要发现任意 verification failure，就返回失败；
- Add device 将 `addDevice.addState` 设置为 `.syncFailed`；
- `DeviceAddViewCell` 对 `.syncFailed` 显示图片资源 `sync_failed`。

相关位置：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:34-46`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:59-78`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:419-436`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:514-526`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:1464-1493`
- `SunSmart/Main/Device/View/DeviceAddViewCell.swift:152-162`

### 4.4 Night 历史任务为什么会被误判

`ProfileType.isSuccessful(node:)` 对以下任务统一读取 `node.lightLCProperty`：

- Occupancy Level
- Vacant Level
- Standby Level
- T1～T5
- Mode / Occupancy Mode
- Manual Override

相关位置：

- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift:913-958`

本次 Night 期望值为 `65535 / 32767 / 19660`，但整个批次完成后当前 `node.lightLCProperty` 已是 Day 的 `0 / 0 / 0`。因此 Night 中至少以下校验必然为 false：

- `occupancyLevel`
- `vacantLevel`
- `standbyLevel`

这足以使 `plan.hasVerificationFailure == true`，即使所有 Mesh 响应都成功。

代码中原有的 deferred runner 会在每个 task 完成后立即执行 `task.operationType.isSuccessful`，再进入下一个 task；这种 task-scoped 校验不会被后续 Day 状态覆盖。当前 Add device 快速添加路径没有使用这一执行方式，而是扁平化后在批次末尾统一校验。

相关位置：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:307-323`
- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift:340-370`

Git 历史显示，批次末统一校验逻辑由提交 `8b974342`（2026-06-15，`fix: adding 3 more lights to a group will need to sync`）引入。这一改动解决多灯快速加入组的同步覆盖问题，但对“同一设备在一个批次内连续保存多个不同 Light LC 场景”的校验时机考虑不足。

## 5. 为什么 Group 页面没有同步提示

Group 和 Members 页面不使用 Add device 的临时 `ProvisioningDevice.addState`。

它们分别根据以下状态显示同步入口或设备未同步图标：

- `group.needSync`
- `node.needSyncGroupData`

相关位置：

- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:112-115`
- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:455-456`
- `SunSmart/Main/Group/Controller/GroupMembersViewController.swift:585-586`
- `SunSmart/Main/Group/Controller/GroupViewController.swift:1562-1564`
- `SunSmart/Main/Group/Controller/GroupViewController.swift:1835-1836`

最终状态重新计算时：

1. 组订阅已完整；
2. Night 场景 `0xFF01` 已保存；
3. Day 场景 `0xFF02` 已保存；
4. Motion Sensitivity 已等于 `62258`；
5. 空 Path 对应的期望邻居列表是 `[]`；
6. 设备已启用邻近照明，Relay Count 已是 `2`，邻居列表也为 `[]`。

所以 `getNodeSyncProximityLighting` 返回 `nil`，Profile 差异计算也没有剩余任务，Group 页面正确地不显示同步提示。

## 6. Path 未配置的实际语义

当前代码没有把“Path 未配置”当作同步失败或禁止添加设备的条件。

`getNodeSyncProximityLighting` 中原本可能用于中止的 Path guard 已被注释；当 `proximityLightingPath` 为 `nil` 或为空时：

1. Path 和 Zone 遍历都为空；
2. 目标 `neighborAddresses` 保持 `[]`；
3. App 仍会下发 `proximityLightingNeighborSet(enabled: true, relay: 2, neighborAddresses: [])`；
4. 命令成功后，本地 Node 状态与该空列表收敛。

相关位置：

- `SunSmart/Common/Data/Node+SyncData.swift:1598-1618`
- `SunSmart/Common/Data/Node+SyncData.swift:1620-1664`
- `SunSmart/Common/Data/Node+SyncData.swift:1669-1685`

Group 页面针对空 Path 使用的是独立的业务提示：显示 `SET` 和 `group_set_the_path_sequence`，而不是复用同步失败入口。

相关位置：

- `SunSmart/Main/Group/Controller/GroupViewController.swift:782-788`

因此需要区分：

- “Path 尚未配置”：组级业务配置未完成，页面提示用户设置 Path；
- “设备需要同步”：设备 Mesh 状态与当前组配置存在差异；
- 本次 Add device `sync_failed`：快速添加的历史任务校验误判。

## 7. 影响范围

### 已确认影响

- Classic Add device
- Professional Add device
- 将新 Light 直接加入 `Proximity/Predictive lighting with photocell` 组
- Night、Day 两个场景的 Light LC 属性不同

### 潜在影响

问题本质是“一个批次内的后置配置覆盖前置配置使用的共享当前状态”，因此不仅限于空 Path。

凡是快速添加计划中包含多个 Scene/Profile task，并且最终统一校验仍读取共享 `node.lightLCProperty` 的场景，都可能出现：

- Add device 显示 `sync_failed`
- 回到 Group 页面却没有待同步

当前未发现覆盖 `DeviceGroupFastAddSyncPlanner` 多场景最终校验的自动化测试。

## 8. 建议修复方向

本报告不修改代码。建议后续修复时遵循以下优先级：

1. Add device 对多场景 Profile 恢复 task-scoped 校验：每个 Night/Day task 完成后立即校验，再执行下一个 task；
2. 或让场景相关 Profile 校验读取对应 Scene Number 的 `lightControlSceneExecuteDatas[].lightControlData`，不要统一读取最终当前 `node.lightLCProperty`；
3. 批次完成后的 UI 结果应区分“消息发送失败”和“最终状态未收敛”，并尽量与 Group 页面的 `needSyncGroupData` 使用同一最终真值；
4. 为以下用例补充测试：
   - 新设备加入 Photocell 组；
   - Night 与 Day 的 On / Prolong / Standby 值不同；
   - Path 为 `nil`、空 Path、有效 Path；
   - Classic 与 Professional 两种 Add device 流程；
   - 所有消息成功时 Add device 必须显示 success；
   - 任一真实配置未收敛时 Add device 与 Group 页面都必须显示待同步；
5. 如果产品定义要求“未设置 Path 时不得启用邻近照明”，应单独确认协议与产品语义，再决定是否恢复 Path guard。该业务规则与本次误判根因是两个问题，不建议混在同一个修复中。

## 9. 验证边界

本次完成：

- 完整检查提供的 1227 行运行日志；
- 对照 Classic / Professional Add device 快速添加流程；
- 对照 Profile 任务生成、最终校验、Node 状态差异计算；
- 对照 Group / Members 页面同步提示的显示条件；
- 检查相关 Git 历史与本地 SDK 响应状态更新逻辑。

本次未执行：

- 未修改业务代码；
- 未运行构建；
- 未使用真机重新复现；
- 未添加临时日志打印具体失败的 `verificationOperation`。

日志与源码已经能够确定 Night 当前态被 Day 覆盖后触发最终统一校验失败；若进入修复阶段，建议先增加一次仅用于验证的失败 operation 明细日志，再按 task-scoped 校验方案实现。
