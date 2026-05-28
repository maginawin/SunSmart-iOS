# Battery Power Switch LINK 绑定与 Target Sync 修复设计

## 背景

当前已实现虚拟 Battery Power Switch 进入 `LINK` 添加流程，并能在添加页筛选真实 Battery Power Switch。实测步骤如下：

1. 添加虚拟 Battery Power Switch，并修改名称、Profile、Group、Scene、Enable、LED Indicator 等属性。
2. 在虚拟 Battery Power Switch 编辑页点击 `LINK`。
3. 进入查找设备页面，找到真实 Battery Power Switch 并完成 connect。
4. 页面提示 `Done`。

预期结果是原虚拟 Battery Power Switch 升级为已绑定真实设备，并且真实开关可以控制已选择的 target groups。

实际结果是：

- 列表和详情仍显示为未关联的虚拟 Battery Power Switch。
- 真实 Battery Power Switch 已经入网，但不能控制 target groups。

## 根因分析

上一轮实现完成了添加入口、设备筛选和入网 append message 生成，但没有完成绑定结果的统一落点。

LINK 场景中，`BatteryPowerSwitchAddConfiguration.prepareLinkedSwitchData` 基于原虚拟 BPS 创建了一个 `copy()`，并把真实 node 的 `primaryUnicastAddress` 写入副本的 `proxyNodeAddress`。后续 `markSucceeded` / `markFailed` 只保存了副本到数据库和 metadata 表，没有把 `MeshNetworkManager.instance.switchs` 中同 `id` 的原虚拟 BPS 替换成这个绑定后的副本。

因此添加完成回调回到编辑页后，`PJPreAddEightKeySwitchesVC` 从 `MeshNetworkManager.instance.switchs` 重新读取当前 switch id，读到的仍是旧的未绑定对象。这个旧对象没有 `proxyNodeAddress` / `linkGroupAddress` 的最新状态，也不会被判断为 linked BPS。

这同时解释了 target groups 不能控制的问题。真实 BPS 控制 target groups 依赖两步：

1. 给真实 BPS 下发 key config，使按键发布到 `linkGroupAddress`。
2. 让 target groups 中的目标节点订阅这个 `linkGroupAddress`。

上一轮实现可能执行了第 1 步，但编辑页回调读取到旧对象后，`switchData.needSyncData` 为空，未进入 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`，导致第 2 步没有执行。真实 BPS 已经入网，但目标灯没有订阅它的 link group，所以不能控制 target groups。

## 已确认方案

采用方案 A：把 LINK 结果写回原虚拟 BPS 的同一条数据，并同步更新内存缓存。

核心原则：

- 原虚拟 BPS 的 `id` 不变。
- LINK 后不新建第二条 BPS。
- 成功或部分失败时，绑定关系都必须落到同一条 BPS 数据上。
- 数据库和 `MeshNetworkManager.instance.switchs` 必须保持一致。
- 编辑页回调必须读取到 linked BPS，再决定是否进入 target groups 同步。

## 修复设计

### 1. 统一持久化入口

在 `BatteryPowerSwitchAddConfiguration` 中扩展当前私有 `persist(_:)` 行为，让它同时完成：

- `switchData.save()`
- `PJEightKeySwitchRepository.shared.save(switchData)`
- 用同 `id` 的 `switchData` 替换 `MeshNetworkManager.instance.switchs` 中的旧对象
- 如果内存中不存在同 `id` 数据，则追加到 `switchs`

这应与 `PJPreAddEightKeySwitchesVC.persistSwitchData(_:)` 的语义一致，避免添加流程和编辑流程出现两套缓存规则。

### 2. finalize 阶段保证缓存已更新

Classic 和 Professional 添加流程中，`finalizeBatteryPowerSwitchAddConfiguration(for:)` 已经在真实 BPS 入网成功后调用：

- 配置成功时调用 `BatteryPowerSwitchAddConfiguration.markSucceeded(switchData)`。
- 配置失败时调用 `BatteryPowerSwitchAddConfiguration.markFailed(switchData, reason:)`。

修复后，这两个方法不仅标记 sync 状态和写库，还必须把绑定后的 `switchData` 写回内存缓存。这样添加完成 callback 执行时，编辑页已经可以从 `MeshNetworkManager.instance.switchs` 读取到 linked BPS。

### 3. 编辑页回调继续复用现有同步链路

`PJPreAddEightKeySwitchesVC.handleBatteryPowerSwitchLinkCompleted()` 保持现有职责，但依赖修复后的缓存状态：

1. `refreshEditingStateFromCurrentSwitchData()` 重新读取同 `id` BPS。
2. 如果读取到 linked BPS 且 `syncState == .synced`：
   - 如果 `needSyncData == false`，提示 `done!`。
   - 如果 `needSyncData == true`，push `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`。
3. target groups 订阅成功后，由现有 `pushBatteryPowerSwitchSync` 成功回调标记同步成功、保存并提示 `done!`。

这一步不新增 target subscription 逻辑，只确保现有同步链路可以拿到正确的 linked BPS 数据。

### 4. 失败语义

真实 BPS 入网失败：

- 不调用 finalize。
- 原虚拟 BPS 不改变。
- 仍显示 `Unlinked`。

真实 BPS 入网成功，但自身配置消息失败：

- 保留 `proxyNodeAddress`。
- 保留 `linkGroupAddress` 和用户选择的 profile / groups / scenes。
- `syncState = .failed`。
- `lastSyncFailedReason = "sync_failed".localizedString`。
- 写入数据库和内存缓存。
- UI 不再显示 `Unlinked`，而是显示 linked 设备的 sync issue。

target groups subscription 失败：

- 使用现有 `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 失败语义。
- 保留绑定关系。
- 让现有重同步入口处理后续恢复。

### 5. 通知刷新

LINK finalize 后需要确保现有通知能覆盖列表、详情和空间统计刷新：

- `switchsRefreshNotificationName`
- `spaceDataChangedNotificaitonName`

如果当前添加流程已经在 addFinish 中发送这些通知，可以不新增重复通知；如果 callback 时机早于通知刷新，则需要在 finalize 后补发一次 switch refresh，保证编辑页和上层列表读到最新状态。

## 非目标

- 不改变普通添加真实 Battery Power Switch 的 PID 默认 profile 逻辑。
- 不改变 `0x2A01` / `0x2A02` 的合法性判断。
- 不新增 target group subscription 协议。
- 不改变 Kinetic switch 的 LINK 流程。
- 不重构添加设备主流程。
- 不修改 Auth、依赖、target 配置或品牌资源。

## 验收标准

手动验证：

1. 创建虚拟 Battery Power Switch，修改 profile、groups、scenes、Enable、LED Indicator。
2. 从编辑页点击 `LINK`，添加真实 Battery Power Switch。
3. 入网和自身配置成功后，原虚拟 BPS 显示为 `LINKED`，不再显示 `Unlinked`。
4. 如果选择了 target groups，LINK 完成后进入现有同步页同步 target groups。
5. target groups 同步成功后，真实 Battery Power Switch 可以控制目标组。
6. App 返回列表或详情后，仍显示同一条 BPS 已绑定真实设备。
7. 不产生第二条 Battery Power Switch。

静态验证：

- `BatteryPowerSwitchAddConfiguration.markSucceeded` 和 `markFailed` 最终都会更新数据库与 `MeshNetworkManager.instance.switchs`。
- Classic 和 Professional 添加流程都通过同一套 finalize 逻辑写回 linked BPS。
- 普通真实 BPS 添加仍走 `prepareSwitchData(for:)`，LINK 场景仍走 `prepareLinkedSwitchData(sourceSwitchData:node:)`。

构建验证：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
