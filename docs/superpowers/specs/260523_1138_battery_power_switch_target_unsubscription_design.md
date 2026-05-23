# Battery Power Switch Target Unsubscription Bug Design

## 背景

用户复现路径：

1. 添加 light 设备，并添加到 Group A。
2. 添加 Battery Power Switch，并将 Group A 加入目标控制组。
3. Battery Power Switch 当前可以正常控制 light。
4. 从 Group A 的 members 中移除该 light。
5. Sync device(s) 页面出现 `0/2 Remove Switch`，任务持续失败。

这次修复范围需要覆盖所有 Battery Power Switch target group 订阅和退订相关路径，而不是只修补当前复现入口。

## 现状分析

`Remove Switch` 是通用 `.deleteSwitchs` 步骤的 UI 文案。对传统 EnOcean/Kinetic switch，它表示从目标设备上移除开关订阅；对 Battery Power Switch，它实际表示让目标设备退订 Battery Power Switch 的虚拟组。

当前代码已经把 Battery Power Switch 接入了旧 switch 同步框架：

- `Node.getNodeNeedDeleteSwitchs()` 在设备退出组或 switchData 标记待解绑组时，检查目标设备是否仍订阅 Battery Power Switch 的虚拟组。
- `SyncDevicesViewController` 在 `.deleteSwitchs` 中遇到 Battery Power Switch 时，会生成 `.delete(node:type: .batteryPowerSwitchTargetSubscription(... unsubscribe: true))`。
- `DeviceOperationType.isSuccessful` 会用 `getBatteryPowerSwitchTargetSubscriptionMessageHandles(... unsubscribe: true).isEmpty` 判断退订是否完成。

直接问题在于消息生成不一致：

- `.configuration + .batteryPowerSwitchTargetSubscription` 会生成订阅或退订消息。
- `.delete + .batteryPowerSwitchTargetSubscription` 当前被归入 Battery Power Switch 自身配置分支后直接跳过，没有生成退订消息。

因此 UI 有任务，成功判定也要求订阅清除，但实际没有下发对应退订命令，导致 `Remove Switch` 持续失败。`0/2` 大概率代表该 light 上两个 Battery Power Switch target capability models 仍需退订，而不是两个 switch。

## 目标

修复 Battery Power Switch target group 退订路径，使以下场景语义一致：

- 从 group members 移除 light。
- Battery Power Switch 编辑页移除 target group。
- 删除 Battery Power Switch 时清理 target devices 订阅。
- Group/Profile SAVE 触发的 Battery Power Switch target subscription 差异同步。

修复后：

- Battery Power Switch target group 退订任务必须实际下发 `ConfigModelSubscriptionDelete` 或 virtual address delete。
- 成功判定必须只在目标设备已退订 BPS 虚拟组后通过。
- `unbindGroupAddresses` 只在对应 group 的目标设备都清理完成后移除，不能因 Battery Power Switch 自身配置成功而提前清空。
- 传统 EnOcean/Kinetic switch 的订阅、代理绑定和删除逻辑保持不变。

## 非目标

- 不重构整个 switch 同步框架。
- 不修改 Battery Power Switch 自身 Key Config、TX Enable、LED Indicator 的协议语义。
- 不改变 Battery Power Switch 支持的 target capability model 集合。
- 不新增 Auth 信息。
- 不处理 `user-temp/`。

## 推荐方案

采用 Battery Power Switch target subscription 专用修复，保留现有 `deleteSwitchs` 数据流。

### 1. 修正 delete 分支消息生成

在 `DeviceOperationType.messageHandles` 的 `.delete` 分支中，为 `.batteryPowerSwitchTargetSubscription` 单独生成消息：

- `unsubscribe == true` 时生成 target model 退订消息。
- 如果未来误传 `unsubscribe == false`，仍按 action 中的方向生成差异消息，避免 configuration/delete 两边语义再次分叉。

Battery Power Switch 自身配置类型仍不在 `.delete` 分支执行。

### 2. 统一 target subscription 成功判定

保持 `DeviceOperationType.isSuccessful` 对 `.batteryPowerSwitchTargetSubscription` 的现有差异判定：

- 订阅：目标设备缺失的 BPS 虚拟组订阅为空，才算成功。
- 退订：目标设备仍需退订的 BPS 虚拟组订阅为空，才算成功。

修复点只应补齐消息生成，不应放宽成功判定。

### 3. 收紧 removed group 清理规则

Battery Power Switch 自身配置成功不应自动代表 target group remove 成功。

保留现有 `Node.updateData(...)` 在 virtual group delete 成功后按 group 检查并清理 `unbindGroupAddresses` 的规则：

- 只有当某个待解绑 group 内没有节点仍需要退订该 BPS 虚拟组时，才移除该 group address。
- 如果退订失败，保留 `unbindGroupAddresses`，便于下次同步继续修复。

审视 BPS 专属同步成功回调，避免在包含 target group remove 的同步中无条件 `clearRemovedGroups`。如果本次同步确实有 removed groups，成功清理应以每个 target unsubscription 成功后的状态为准。

### 4. 改善 BPS 任务展示语义

传统 switch 保持 `Remove Switch`。

Battery Power Switch target unsubscription 在可行范围内展示为更准确的任务名称，例如 `Group Unsubscription`。如果为了最小改动暂不新增本地化 key，也至少避免把 BPS 专属 target 操作误认为代理或传统机械能开关删除。

## 数据流

### Group members 移除 light

1. `GroupMembersViewController` 将被移除 light 标记为 `groupState = .exitFailure`。
2. `SyncDevicesViewController(type: .group(... outNodes: ...))` 展开该 node 的同步数据。
3. `getNodeNeedDeleteSwitchs()` 从 Group A 的 `allSwitchs` 找到绑定或待解绑的 Battery Power Switch。
4. 如果 light 仍订阅 BPS 虚拟组，生成 `.deleteSwitchs`。
5. UI 生成 BPS target unsubscription task。
6. 修复后，`.delete + .batteryPowerSwitchTargetSubscription` 下发退订消息。
7. 退订成功后，node subscription 状态更新；如果 Group A 内所有相关节点均已清理，移除对应 `unbindGroupAddresses`。

### Battery Power Switch 编辑页移除 target group

1. 编辑保存时，旧 target group 差集进入 `unbindGroupAddresses`。
2. `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 为 removed groups 生成 target unsubscription tasks。
3. 修复后，这些任务实际下发退订消息。
4. 只有 target unsubscription 成功后，removed group 状态才被清理。

### 删除 Battery Power Switch

1. 删除 switch 时，`getNeedSyncDatas(deleteSwitch: true)` 遍历当前绑定 groups。
2. 对 BPS target devices 生成退订任务。
3. 修复后，退订任务实际下发。
4. 传统 switch proxy 清理逻辑不受影响。

## 错误处理

- 如果某个目标设备离线或退订失败，任务保持 failed。
- `unbindGroupAddresses` 保留失败 group，后续 Sync Issue 或重新同步可以继续修复。
- Battery Power Switch 自身配置失败时，仍按现有逻辑标记 own configuration failed，并阻止依赖它的自身配置任务继续误报成功。
- Target unsubscription 失败不应把 Battery Power Switch 自身配置标记为失败，二者状态应分开处理。

## 测试与验证

建议优先做代码级验证，再做 iOS build：

1. 搜索所有 `batteryPowerSwitchTargetSubscription` 分支，确认 `.delete` 和 `.configuration` 都能生成 target subscription 差异消息。
2. 手动审查 `getNodeNeedDeleteSwitchs()`、`getNeedSyncDatas(deleteSwitch:)`、`appendBatteryPowerSwitchItems(...)` 三个入口，确认 BPS 不再回落到传统 EnOcean switchKeys 订阅逻辑。
3. 添加或更新单元测试时，覆盖：
   - BPS target unsubscription action 在 `.delete` 下返回非空 message handles。
   - 传统 EnOcean switch delete 仍走 `getEnOceanUnSubscriptionMessageHandles`。
   - target unsubscription 未全部成功时不清空 `unbindGroupAddresses`。
4. 运行直接 iOS 构建：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 风险

- Battery Power Switch 使用了传统 switch 数据结构，修复必须避免影响 EnOcean/Kinetic switch。
- `unbindGroupAddresses` 是失败重试依据，不能在未验证 target devices 清理成功前清空。
- UI 文案调整如果新增本地化 key，需要同步检查相关 target 资源影响。

## 验收标准

- 按用户复现路径，从 Group A members 移除 light 后，`Remove Switch` 或等价 BPS unsubscription 任务可以下发并完成。
- 任务成功后，light 不再订阅该 Battery Power Switch 的虚拟组。
- 如果退订失败，下次同步仍能看到并重试对应 target group remove 任务。
- Battery Power Switch 自身配置成功不会掩盖 target group remove 失败。
- 传统 EnOcean/Kinetic switch 删除、代理解绑、目标组订阅行为不回归。
