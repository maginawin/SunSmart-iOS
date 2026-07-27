# Group Profile 显示定时任务同步影响分析

## 结论

此次 Scheduler 更新会间接影响 Group 的“需要同步”状态和同步任务列表，但没有修改 Group Profile 参数的生成或协议写入逻辑。

当前观察到“Group 需要同步，里面全部是定时任务”与代码改动存在直接因果关系。它不是 Group Profile 数据本身异常，而是 Group 同步入口同时聚合 Profile、Scene、Schedule、Switch 等多类任务；新的 Schedule 同步判定把旧缓存状态视为需要重新确认或迁移。

## 触发链路

1. `Node.getSyncData(type: .group)` 在检查 Profile 之后，还会调用 `getNodeSyncSchedules(group:)`。
2. 有待同步日程时，会追加 `.syncSchedules`，因此整个 Group 被标记为需要同步。
3. 同步页面把 `.syncSchedules` 展开成独立的 Schedule 任务，所以列表中可以只出现定时任务而没有 Profile 任务。
4. Group 同步消息通过统一的 Schedule 消息生成入口发送。

## 根因

旧逻辑只读取扁平缓存 `schedulerActions[index]`；新逻辑为了识别普通 Scheduler 与 Light LC Scheduler 中的重复 entry，改为要求：

1. Action Owner Model 中存在与目标一致的 entry；
2. 每个非 Owner Model 的状态都已知；
3. 非 Owner 同 index 没有有效 entry。

旧版本保存的节点经常只有扁平 `schedulerActions`，而没有完整的 `allSchedulerModelEntrys[model]`。此时即使设备中的日程实际上正确，新逻辑也会因 Owner 或非 Owner Model 缓存未知而返回“需要同步”。

因此升级后既有日程可能被一次性列为待同步；Auto/On、Off、Scene Recall 都可能出现，双 Scheduler 与缺少 Model-aware 缓存的单 Scheduler 设备也可能出现。

## 对 Group Profile 的实际影响

- Profile 参数、场景生成、传感器配置与 Light LC Profile 写入逻辑没有被此次修复修改。
- Schedule 与 Profile 共用 Group 同步入口，所以 Schedule 状态会影响 Group 的总同步标记和任务列表。
- SchedulerActionSet 只写 Scheduler Model，不会直接覆盖 Group Profile 属性。
- 双 Scheduler 设备执行这些任务时，会按最终策略清理非 Owner，并向 Action Owner 重写日程。

## 状态是否合理

从设备一致性角度，这是保守的一次性迁移：未知的非 Owner 可能保存着旧残留，重新同步可以清除潜在的重复 entry。

从 UI 与升级体验角度，这是明确的行为变化：缓存未知被直接表现为“Group 未同步”，即使尚未证明设备真实不一致。因此不能简单视为完全无影响。

## 成功后的预期

同步成功回调会把 `MessageHandle.model` 传入节点缓存更新：

- 非 Owner 清理成功后创建已知的空 Model 缓存；
- Owner 写入成功后保存目标 entry；
- 清除同步状态缓存并重新计算。

如果全部 Scheduler 消息成功，同一批 Schedule 任务应从 Group 待同步列表消失。

如果完成同步后相同任务仍然存在，则不是预期的一次性迁移，需检查：

1. 非 Owner 清理是否超时或失败；
2. Owner 写入是否失败；
3. 完成回调是否保存了正确的来源 Model；
4. 设备返回的 entry 是否与目标 `schedulerEntry` 不一致。

## 当前判断

现象与本次改动相关，不能归因于 Group Profile 功能本身。最可能原因是既有日程缺少 Model-aware 缓存，被新的严格判定统一标记为待迁移。

当前未修改代码。若产品不接受升级后大量 Group 出现一次性待同步，需要另行设计“先读取双 Model 真值，再决定是否显示未同步”或兼容旧缓存的迁移策略。
