# Group Add PIR Publication Sync 设计

## 背景

从 Group Members 页进入 Add device，扫描并添加带 PIR 功能的 light 到非 Manual Control profile 的 group 后，添加完成返回 Members / Main - Lights 时，可能有 1 个设备展示为需要同步。

已验证现象：

- 同时添加 2 个设备到 group members，添加完成后有 1 个设备显示需要同步。
- 同时添加 3 个设备到 group members，添加完成后同样有 1 个设备显示需要同步。
- 点击 Main - Lights 左下角同步按钮后，只补发 1 条 `ConfigModelPublicationSet`，设备即恢复正常。
- 补发命令目标是待同步设备的 SIG Sensor Server model `0x1100`，publication 指向目标 group `0xC008`，并使用 `2 times every 100 ms` retransmit。

这说明残留的待同步项不是完整 profile、scene、schedule 或 switch 任务，而是某个带 PIR 设备的 Sensor Server publication 没有在 Add Device 的 group deferred sync 阶段完成。

## 当前代码路径

Group Members 空页 Add device 入口：

- `GroupMembersViewController.updateEmptyUI()`
- 创建 `DeviceAddViewController(space:)`
- 设置 `addVc.appointGroup = self.group`

Add Device group deferred sync 路径：

- `DeviceAddClassicModeController`
- `DeviceAddProfessionalModeController`
- `DeviceGroupDeferredSyncPlanner.makePlan(node:group:)`
- `DeviceGroupDeferredSyncPlanner.run(plans:completion:)`

同步判定路径：

- `GroupMembersViewController` 使用 `node.needSyncGroupData` 展示 unsync 图标。
- `node.needSyncGroupData` 进入 `Node.getNeedSyncGroup()`
- `getNeedSyncGroup()` 调用 `getNodeSyncProfiles(group:sensorPublicationSyncMode: .legacyCompatible)`
- 非 Manual Control profile 中，带 PIR 的设备会检查 `presenceDetectedSensorModel` 的 Sensor Server publication 是否指向 group。
- 如果 publication 未配置到 group，则生成 `.sensorEnabled(...)`，页面显示需要同步。

日志中的补发命令：

- `ConfigModelPublicationSet(elementAddress: ..., modelIdentifier: 4352, publish: 0xC008, retransmit: 2 times every 100 ms)`

对应代码：

- `Node+SyncData.swift` 的 `.sensorEnabled(...)`
- `Node+MessageHandles.swift` 将 `.sensorEnabled` 转为 `ConfigModelPublicationSet`

## 根因判断

问题真实存在，且更符合 Add Device 批量收尾时的 deferred plan 执行边界问题。

当前 `finishGroupDeferredSyncPlans()` 会：

1. 读取 `pendingGroupDeferredSyncPlans` 到局部 `plans`。
2. 立即清空 `pendingGroupDeferredSyncPlans`。
3. 调用 `DeviceGroupDeferredSyncPlanner.run(plans:)`。

如果批量添加中某个设备的 `addSuccess` 回调晚于 `addFinish` 开始执行收尾，或者 success / finish 回调顺序在多设备场景下不是严格“所有 success 都先于 finish”，后到的设备会把 deferred plan 追加到已经被清空的 pending 数组。本轮 `run(plans:)` 不会包含这个 plan，最终这个设备的 Sensor Server publication 没有下发。

同时，`DeviceGroupDeferredSyncPlanner.makePlan(node:group:)` 直接调用：

`node.getSyncData(type: .group(group))`

没有传入 `GroupProfileSyncContext(reason: .memberAdded)`。这让 Add Device 路径和 Members 手动添加已有设备路径不一致。后者在 `SyncDevicesViewController` 中已经会对新增成员传入 `.memberAdded`，强制生成新增成员应补齐的 profile 配置。

## 目标

- 同时添加多个带 PIR 的 light 到 group members 后，所有成功添加的设备都完成 Sensor Server publication deferred sync。
- Add Device 自动入组路径与 Members 手动添加已有成员路径使用一致的新增成员 profile 同步语义。
- 添加完成后不再残留 1 个设备需要通过 Main - Lights 同步按钮补发 publication。
- Classic 和 Professional 两种 Add Device 模式行为一致。
- 不隐藏 Members / Main - Lights 的待同步提示，不改变待同步判定本身。

## 非目标

- 不改 UI 文案、本地化、资源或 target 配置。
- 不改变 Manual Control profile 的业务规则。
- 不改变非 light、gateway、dongle、switch、Emergency Fire Controller 添加流程。
- 不把 Add Device 成功变成必须等待完整 group sync 成功才算 provision 成功；deferred sync 失败仍保留现有待同步语义。
- 不重构 `DeviceGroupDeferredSyncPlanner` 的任务模型。

## 方案 A

采用“收敛 deferred plan 收集边界 + 传入 member-added profile context”的修复。

### 1. 补齐 planner 的新增成员上下文

扩展：

- `DeviceGroupDeferredSyncPlanner.makePlan(node:group:)`

为：

- `DeviceGroupDeferredSyncPlanner.makePlan(node:group:profileSyncContext:)`

默认值为 `nil`，保持非新增成员调用兼容。

Add Device light + group 路径调用时传：

- `GroupProfileSyncContext(reason: .memberAdded)`

这样 planner 内部调用：

- `node.getSyncData(type: .group(group), profileSyncContext: profileSyncContext)`

使 `.sensorEnabled(...)`、Light LC mode、occupancy mode、manual override、manual control、light auto adjust、level/lux/timing 等新增成员 profile 项和 Members 手动添加路径一致。

### 2. 避免 pending plans 快照过早

Classic 和 Professional 当前都在 `addFinish` 中调用 `finishGroupDeferredSyncPlans`。该方法不应只执行当时快照中的 pending plans 后直接完成，而应确保本轮所有成功添加到 group 的 light 节点都已经形成 deferred plan。

推荐实现：

- `finishGroupDeferredSyncPlans` 接收 `addFinish` 回调提供的 `successList`。
- 执行前根据 `successList` 的设备地址反查 `MeshNetworkManager` 中的成功 node，并与已有 `addSuccessNodes` 合并。
- 根据合并后的成功 node 与当前 group 重新补齐缺失的 light + group deferred plans。
- 用 node primary unicast address 去重，避免已由 `addSuccess` 添加的 plan 重复执行。
- 补齐缺失 plan 时，同步把对应 `ProvisioningDevice` 加入待标记 success 的集合，避免 deferred sync 期间 UI 状态提前完成或漏标。
- 补齐时同样使用 `.memberAdded` profile context。
- 然后再统一调用 `DeviceGroupDeferredSyncPlanner.run(plans:)`。

这样即使某个 plan 没有在 `addSuccess` 阶段进入 pending 数组，或某个 `addSuccess` 回调晚于 `addFinish` 开始收尾，`addFinish` 阶段仍能基于最终成功列表补齐。

### 3. 完成回调顺序保持不变

保留现有顺序：

1. 执行 deferred plans。
2. 标记 pending group deferred sync devices 为 success。
3. 调用 `deviceAddCallback`。
4. 更新 space 统计、发送 refresh notification。
5. 继续 power switch 初始电量读取和断开流程。

这样页面刷新和 Cloud sync 发生在本轮 deferred sync 尝试之后。

## 错误处理

- deferred task 成功：继续调用 `node.updateData(message:isSuccess:)`，更新本地 publication/profile 缓存。
- deferred task 失败：继续调用 `group.updateGroupSyncState()`，让现有 UI 展示需要同步。
- 如果补齐 plan 时发现设备已不在目标 group 或没有 deferred tasks，则跳过。
- 不伪造成功状态；待同步提示仍由 `needSyncGroupData` 计算。

## 测试与验证

手工验证：

1. 创建非 Manual Control profile 的新 group。
2. 从 Members 空页点击 Add device。
3. 同时 Add Selected 2 个带 PIR 的 light。
4. 添加完成后返回 Members / Main - Lights，确认没有单个设备残留需要同步。
5. 重复同时添加 3 个带 PIR 的 light，确认没有单个设备残留需要同步。
6. 若人为制造 deferred sync 失败，确认对应设备仍展示需要同步，点击 Main - Lights 同步按钮可补齐。
7. 添加不带 PIR 的 light 到 group，行为不变。
8. 添加 light 到 Manual Control profile group，行为不变。

静态验证：

- Classic 和 Professional 都传入 `.memberAdded`。
- `DeviceGroupDeferredSyncPlanner.makePlan` 支持可选 `profileSyncContext`。
- `finishGroupDeferredSyncPlans` 在执行前会基于 `successList` 和 `addSuccessNodes` 补齐缺失 plan。
- plan 去重基于 node primary unicast address。
- Members 手动添加已有设备的 `SyncDevicesViewController` 行为不被改变。

构建验证：

```sh
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

不使用 Simulator 作为本次校验依据。

## 风险

- `.memberAdded` 会让 Add Device group deferred sync 的 profile 命令更完整，命令数量可能增加。
- 若多设备添加底层回调顺序还有其它异步边界，补齐逻辑必须以最终成功节点为准，不能依赖 pending 数组本身完整。
- 需要避免重复执行同一设备的 deferred plan，否则可能增加不必要的 Mesh 流量。
