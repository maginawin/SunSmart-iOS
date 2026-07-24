# Fast Add 双场景同步结果校验修复设计

## 1. 目标

修复新设备在 Add Device 页面直接加入 `Proximity/Predictive lighting with photocell` 组时，所有 Mesh 配置均成功，但设备仍显示 `sync_failed` 图标的问题。

本修复只调整 Add Device 快速加入组流程中的校验时机与结果汇总方式：

- 覆盖 Classic Add Device；
- 覆盖 Professional Add Device；
- 保留既有消息发送顺序；
- 保留组成员数变化对应的严格传感器发布重传校验；
- 不修改空 Path、邻居列表下发或 Group 页面 `SET Path` 的产品行为。

## 2. 问题定义

Photocell Profile 会连续下发 Night 和 Day 两套 Light LC 配置。每套配置都包含属性写入和场景保存，但设备的 `node.lightLCProperty` 只表示最近一次写入的当前属性。

当前 Fast Add 流程将所有同步任务的消息句柄扁平化发送，并在整个批次结束后重新检查所有历史 `verificationOperations`。Day 任务结束后，当前属性已经是 Day 值；此时重新检查 Night 任务，会错误地使用 Day 当前属性与 Night 期望值比较，导致 `hasVerificationFailure == true`。

Group 页面没有相同误判，因为它按场景编号检查 `lightControlSceneExecuteDatas` 中的最终持久化数据，而不是用 Day 当前属性回查 Night 历史任务。

## 3. 范围

### 3.1 包含

- Fast Add 计划中的同步任务边界建模；
- 每个同步任务完成时即时校验并固化结果；
- Fast Add 最终结果基于消息结果和固化的任务结果汇总；
- Classic 与 Professional 两个入口接入同一套共享结果追踪逻辑；
- 针对双场景覆盖、真实失败和严格重传校验的回归测试；
- 相关共享品牌 target 的 iPhoneOS 编译验证。

### 3.2 不包含

- 不改变 Proximity/Predictive Lighting Mesh 协议；
- 不修改 NordicSigMeshSDK；
- 不改变 Path 为 `nil` 或空数组时下发空邻居列表的行为；
- 不阻止未配置 Path 的组添加设备；
- 不取消 Group 页面独立的 `SET Path` 提示；
- 不修改普通 Group Sync 的 `needSyncGroupData` 计算；
- 不把 Fast Add 校验降级为 `legacyCompatible`；
- 不重构无关的 Add Device 或 Group 模块。

## 4. 方案选择

### 4.1 采用：任务完成时即时校验

Fast Add 继续使用一个有序的追加消息队列，但计划同时保留每个同步任务对应的消息范围和 `DeviceOperationType`。

当某个任务的最后一条消息收到成功回调时：

1. SDK 已先用响应更新 Node；
2. App 立即执行该任务的 `operationType.isSuccessful`；
3. 将结果固化到本次 Fast Add 会话；
4. 再继续后续任务。

Night 的校验因此发生在 Day 开始写入之前，不会被 Day 的最终当前属性覆盖。

SDK 当前执行顺序已经满足该设计：ACK 响应先更新 Node，再调用 App 的追加消息成功回调，随后才移除当前消息并发送下一条消息。本修复不需要改变 SDK。

### 4.2 不采用：批次结束后调用 `getNeedSyncGroup`

该方案虽然改动较小，也与 Group 页面最终状态计算接近，但普通组差异计算对传感器发布重传使用 `legacyCompatible`。Fast Add 当前需要根据加入后的有效成员数执行 `strictTarget` 校验，否则可能重新引入组成员超过 3 个后发布重传次数未收敛却被判成功的问题。

### 4.3 不采用：扩展全局 Profile 校验以携带 Scene Number

该方案可以让 Night 和 Day 在批次结束后分别读取场景缓存，但需要扩展共享 `ProfileType` 或 `DeviceOperationType` 的上下文，并影响普通同步流程。相较于只修 Fast Add 校验时机，影响范围更大。

## 5. 架构设计

### 5.1 复用既有 Deferred Task 边界

Light 类型的 Fast Add 计划已经通过 `DeviceGroupDeferredSyncPlanner.makePlan` 得到：

- `immediateMessageHandles`；
- 有独立 `DeviceOperationType` 和有序消息句柄的 `deferredTasks`。

本修复直接复用这些既有 `deferredTasks` 作为校验边界，不重新定义同步任务，也不重新生成消息句柄。每个 deferred task 的最后一个实际发送句柄就是该任务的校验检查点。

### 5.2 共享检查点追踪器

新增一个只负责检查点状态的轻量追踪器，由 Fast Add 计划持有。每个检查点包含：

- 对应 deferred task 的最后一个消息句柄；
- 在该检查点执行 `DeviceOperationType.isSuccessful` 的校验闭包；
- 检查点状态：等待、成功或失败。

追踪器通过消息句柄对象身份匹配成功回调。当回调命中检查点时立即执行校验，并固化结果；已经进入终态的检查点不能被重复回调改写。

追踪器不发送 Mesh 消息、不更新 Node、不更新 UI，也不负责 EFC 特殊流程。消息发送失败仍由两个控制器现有的 `failedFastAddGroupSyncNodeAddresses` 记录，避免扩大本次改动。

### 5.3 批次末校验的保留范围

Light Fast Add 的 deferred operations 从批次末 `verificationOperations` 中移除，改由检查点追踪器负责。以下校验方式保持现状：

- immediate sync data 继续在批次结束时读取最终 Node 状态；
- Sensor Fast Add 没有连续 Light LC 双场景覆盖问题，继续使用现有批次末校验；
- EFC 继续使用现有独立结果集合。

这样既消除 Night 被 Day 覆盖的误判，又避免重写所有设备类型的计划生成逻辑。

如果某个 deferred operation 过滤 `SceneRecall` 后没有实际消息句柄，沿用现有 Deferred Planner 行为，不生成检查点，也不把它作为本次 Fast Add 的待完成任务。

### 5.4 控制器接入

Classic 与 Professional 控制器继续通过 SDK 的追加消息成功和失败回调接收结果，但不再分别维护批次末历史状态回查逻辑。

两个控制器只负责：

- 在现有同步 `node.updateData` 之后，把成功的消息句柄交给检查点追踪器；
- 继续用现有集合记录失败的消息句柄；
- 在设备添加结束时询问检查点追踪器是否存在等待或失败；
- 将结果与现有 EFC 校验结果合并；
- 根据最终结果设置 `.success` 或 `.syncFailed`。

控制器不自行判断 Night、Day、传感器发布或 Proximity 的具体业务状态。

## 6. 数据流

1. 用户选择目标组并开始添加设备。
2. App 以 `.memberAdded` 上下文生成完整组同步数据。
3. Fast Add Planner 生成有序任务及扁平化追加消息队列。
4. SDK 按当前顺序逐条发送追加消息。
5. 对每条 ACK 消息，SDK 先更新 Node，再回调 App。
6. 当消息句柄命中 deferred task 的检查点时，追踪器立即校验该任务并固化结果。
7. 普通消息成功不触发额外检查点校验。
8. SDK 继续发送下一任务的消息。
9. 全部追加消息结束后，控制器汇总消息失败、任务校验失败和 EFC 失败。
10. 只有存在真实失败时才显示 `sync_failed`。

## 7. 失败处理

### 7.1 消息失败

任一属于组同步任务的追加消息失败，两个控制器继续通过现有失败地址集合记录。后续消息是否继续发送沿用 SDK 当前策略，最终 Add Device 显示 `.syncFailed`。

### 7.2 状态校验失败

任务消息全部成功，但任务边界的 `DeviceOperationType.isSuccessful` 返回 false，该任务固化为状态校验失败，最终显示 `.syncFailed`。

这会继续捕获以下真实问题：

- 模型订阅没有收敛；
- Night 或 Day 属性没有按期望更新；
- Scene Store 没有成功反映到 Node；
- Motion Sensitivity 返回值不匹配；
- Proximity 状态或邻居列表不匹配；
- 传感器发布重传次数与有效成员数的严格目标不匹配。

### 7.3 重复或迟到回调

已进入终态的检查点不再重新校验或改写结果。重复成功回调只能被幂等忽略，避免后续 Node 状态覆盖已经固化的校验结果。

### 7.4 未完成检查点

设备添加结束时，任何仍处于等待状态的检查点都按失败处理。无法映射到检查点的普通成功回调不改变检查点状态，并继续沿用现有消息成功处理。

## 8. 兼容性要求

### 8.1 空 Path

当 `proximityLightingPath == nil` 或 Path 为空时：

- 目标 `neighborAddresses` 仍为 `[]`；
- 仍下发启用 Proximity 且邻居数量为 0 的消息；
- 设备响应成功并且 Node 收敛时，任务校验成功；
- Group 页面继续显示独立的 `SET Path` 提示。

### 8.2 传感器发布重传

Fast Add Planner 继续使用加入设备后的 `effectiveMemberCount` 计算发布重传目标，并使用 `strictTarget` 校验。不得改用普通 Group Sync 的 `legacyCompatible` 结果作为 Fast Add 最终成功依据。

### 8.3 多品牌 target

修改位于共享代码路径，至少需要检查：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

如果某个 scheme 在当前 workspace 不存在，应以 `xcodebuild -workspace SunSmart.xcworkspace -list` 的实际结果为准，并在验证报告中说明。

## 9. 测试设计

### 9.1 共享追踪器单元测试

新增聚焦 Fast Add 任务边界的测试，覆盖：

1. Night 任务在 Day 开始前校验成功，Day 后续覆盖当前属性后，Night 结果仍保持成功；
2. Night 任务边界校验失败，后续 Day 成功不能覆盖失败；
3. 重复成功回调不改变已固化结果；
4. 普通非检查点消息不会错误完成其他任务；
5. 未收到检查点回调时，最终结果为失败；
6. 所有检查点成功时，最终结果为成功。

### 9.2 严格重传回归测试

覆盖有效成员数从 3 增加到 4 的场景：

- 计划仍生成新的严格发布重传目标；
- Node 保持旧重传值时，Fast Add 结果必须失败；
- Node 更新为新目标时，任务才成功。

### 9.3 双入口契约测试

检查 Classic 和 Professional：

- 使用同一个 Fast Add 计划与结果追踪器；
- 成功回调均在同步 Node 更新后转交检查点追踪器；
- 失败回调继续记录现有组同步失败集合；
- 添加完成时均以消息失败、检查点结果、保留的最终校验和 EFC 结果汇总；
- 不再对 deferred operations 执行批次末历史状态回查。

### 9.4 空 Path 回归检查

验证本修复没有改变：

- `getNodeSyncProximityLighting` 对空 Path 生成空邻居列表；
- Group 页面仍通过原有条件显示 `SET Path`；
- 不新增“无 Path 禁止添加”的分支。

### 9.5 构建验证

对 workspace 中实际存在的相关 scheme 使用 generic iPhoneOS、关闭签名执行 Debug 构建。构建成功只证明编译与链接通过，不代表真机 Mesh 行为已验收。

## 10. 真机验收

至少执行以下场景：

1. 创建没有 Path 的 `Proximity/Predictive lighting with photocell` 组；
2. 从 Classic Add Device 直接把设备加入该组；
3. 确认全部同步响应成功后设备显示成功状态，不出现 `sync_failed`；
4. 返回 Group 页面，确认设备正常展示，并保留 `SET Path` 提示；
5. 使用 Professional Add Device 重复验证；
6. 配置有效 Path 后重复添加，确认邻居列表正常下发；
7. 人为制造一个真实同步失败，确认 Add Device 仍显示 `sync_failed`；
8. 使用第 4 个成员触发传感器发布重传目标变化，确认未收敛时仍能显示失败。

## 11. 成功标准

- 双场景全部成功时，Add Device 与 Group 页面均不报告设备待同步；
- Day 当前属性不再使已经成功的 Night 任务变为失败；
- 真实消息失败或状态未收敛仍显示 `sync_failed`；
- Classic 与 Professional 行为一致；
- 严格传感器发布重传校验没有回退；
- 空 Path 和 `SET Path` 行为完全保持现状；
- 不修改 SDK、协议、持久化结构或无关模块。

## 12. 参考

- 问题分析：`docs/260724_1225_proximity_photocell_fast_add_sync_icon_analysis.md`
- Fast Add Planner：`SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- Classic Add Device：`SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- Professional Add Device：`SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- Profile 生成与组差异计算：`SunSmart/Common/Data/Node+SyncData.swift`
- 操作成功判定：`SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- SDK 回调顺序：`NordicSigMeshSDK/MeshLib/Manager/MeshFastAddDeviceManager.swift`
