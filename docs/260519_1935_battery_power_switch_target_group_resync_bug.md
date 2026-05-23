# Battery Power Switch Target Group Resync Bug Analysis

## 现象

- 在 Battery Power Switch 中切换 Profile 后 SAVE，target groups 的亮度增加/减少可以正常控制。
- SAVE 后 target groups 显示为需要同步。
- 对 target groups 的 Group Profile 再执行 SAVE 后，Battery Power Switch 的亮度增加/减少会同时改变色温。

## 结论

用户的猜测方向是正确的，但触发点不是普通组订阅判断直接检查 CCT model，而是 Battery Power Switch 被混入了现有 EnOcean Switch 的同步路径。

Battery Power Switch 专属 SAVE 路径当前只给 target devices 的亮度相关 models 订阅 BPS 虚拟组，符合预期；但 Group/Profile SAVE 路径仍使用 `DeviceSwitchData.switchKeys` 和 SDK 的 EnOcean Switch 订阅逻辑。`DeviceSwitchData.switchKeys` 对 4-key panel 会生成 `cctUp/cctDown`，并且在 BPS 没有 `subLinkGroupAddress` 时会把 CCT action 的地址退回到 `linkGroupAddress`，也就是 BPS 的同一个虚拟组。

因此：

1. BPS SAVE 后，因为没有给 CCT Generic Level 订阅 BPS 虚拟组，普通 Group/Profile needSync 判断认为 target nodes 还缺 EnOcean Switch 的 CCT 订阅，所以 target groups 显示需要同步。
2. 用户对 target groups 重新 SAVE 时，普通 Group/Profile 同步流程会按 EnOcean Switch 逻辑下发 `ctlTemperatureLevelModel` 对 BPS 虚拟组的订阅。
3. 之后 BPS 发出的 Generic Level Delta/Move 到同一个虚拟组时，亮度 Generic Level 和 CCT Generic Level 都收到了消息，所以表现为亮度和色温同时变化。

## 关键证据

- `SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift`
  - `switchKeys` 对 `.default_4key` 和 `.scenes_4key` 都包含 `cctUp/cctDown`。
  - CCT action 使用 `subAddress ?? mainAddress`，BPS 没有 sub group 时会落到 `linkGroupAddress`。

- `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshEnOceanProxyServer.swift`
  - `getEnOceanSubscriptionMessageHandles(switchKeys:)` 遇到 `.cctUp/.cctDown` 会给 `ctlTemperatureLevelModel` 订阅 action address。
  - `.dimUp/.dimDown` 使用 `levelModel`，现在 SDK 的 `levelModel` 优先取 lightness element 下的 Generic Level，这一点本身是正确的。

- `SunSmart/Common/Data/Node+SyncData.swift`
  - `getNodeSyncSwitchs(group:switchData:)` 遍历 `group.info.switchs`，对所有 switch 使用 `getEnOceanSubscriptionMessageHandles(switchKeys:)` 判断是否需要同步。
  - 这里没有区分 BPS 与传统 EnOcean Switch。

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
  - Group/Profile SAVE 会通过 `getSyncDeviceModel(group:node:)` 展开 `.syncSwitchs`，最终仍然进入 `.enOceanSwitch` 同步任务。

- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
  - `.configuration(.enOceanSwitch)` 会继续调用 `node.getEnOceanSubscriptionMessageHandles(switchKeys:)` 生成消息。

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
  - BPS 专属 `getBatteryPowerSwitchSubscriptionMessageHandles` 已经具备正确方向：只添加 capability models，并删除非亮度 Generic Level 的 obsolete subscriptions。
  - 但这个专属方法目前只在 BPS SAVE 路径使用，未接管 Group/Profile SAVE 路径。

## 修复方案

推荐方案 A：把 BPS 从普通 EnOcean Switch 订阅判断与同步流程中隔离出来。

### 1. 增加 BPS switch data 判定

在 App 侧增加一个清晰的判定，例如 `DeviceSwitchData.isBatteryPowerSwitchData`：

- `proxyNode?.isBatteryPowerSwitch == true`
- 或 `self is PJEightKeySwitchData && proxyNode?.isBatteryPowerSwitch == true`

不要只根据 panel type 判断，因为普通 EnOcean Switch 也会使用 `.default_4key/.scenes_4key`。

### 2. 修正 needSync 判断

在以下路径遇到 BPS 时，不再调用 SDK 的 `getEnOceanSubscriptionMessageHandles(switchKeys:)`：

- `Node.getNodeSyncSwitchs(group:switchData:)`
- `DeviceSwitchData.getNeedSyncDatas(deleteSwitch:)`
- 必要时 `Group.getNodeAddMessageHandles(node:)`

BPS 应改为：

- 同步：`node.getBatteryPowerSwitchSubscriptionMessageHandles(switchGroup: bpsLinkGroup)`
- 解绑：`node.getBatteryPowerSwitchUnsubscriptionMessageHandles(switchGroup: bpsLinkGroup)`

这样 BPS SAVE 后，target groups 不会因为 CCT model 未订阅而继续显示需要同步。

### 3. 修正 Group/Profile SAVE 下发消息

在 Group/Profile SAVE 展开 `.syncSwitchs/.deleteSwitchs` 时，BPS 不应生成 `.enOceanSwitch` task 或不应让 `.enOceanSwitch` 使用 SDK EnOcean 消息。

可选实现：

- 优先方案：在 `SyncDevicesViewController.getSyncDeviceModel(group:node:)` 中，BPS 生成 `.batteryPowerSwitchTargetSubscription` task，带上明确的 target group。
- 辅助兜底：在 `SyncDevicesCellModel` 的 `.enOceanSwitch` 分支中检测 BPS，转用 BPS 专属 subscription/unsubscription helper。

建议两个都做：

- 前者保证 UI 和业务语义正确。
- 后者防止其他旧入口误用 `.enOceanSwitch` 时再次写入 CCT 订阅。

### 4. 修正成功状态判断

当前 `.batteryPowerSwitchTargetSubscription` 的 `isSuccessful` 直接返回 `true`，适合 BPS SAVE 中的强制重下发流程，但不适合 Group/Profile SAVE 用来判断是否仍需要同步。

建议补齐：

- configuration：判断 `getBatteryPowerSwitchSubscriptionMessageHandles(switchGroup:)` 是否为空。
- delete：判断 `getBatteryPowerSwitchUnsubscriptionMessageHandles(switchGroup:)` 是否为空。

注意不要使用 `includeExisting: true` 做成功判断，否则永远会生成消息。

### 5. 修复历史错误订阅

已被 Group/Profile SAVE 误订阅 CCT 的现场设备，需要能被自动修复。

当前 `getBatteryPowerSwitchSubscriptionMessageHandles` 已会把非 brightness 的 Generic Level model 作为 obsolete target 删除，因此只要 Group/Profile SAVE 也走 BPS helper，就能在后续同步中删除 CCT Generic Level 对 BPS 虚拟组的订阅。

BPS 自身 SAVE 也可以继续作为修复入口，因为它已经包含 target subscription step。

## 风险与注意点

- 不要修改 SDK 的 EnOcean Switch 通用逻辑。传统 EnOcean Switch 仍然需要 CCT Up/Down 行为。
- 不要把 BPS 的 `switchKeys` 简单改成 brightness-only；这个属性属于传统 switch 抽象，改它容易影响旧 UI、删除同步、导入导出或其它复用点。
- BPS 仍然只使用一个 `linkGroupAddress`，不要恢复 `subLinkGroupAddress`。
- BPS target group 同步需要继续清理 obsolete CCT Generic Level 订阅，否则已经被错误同步过的设备不会恢复。
- 若 target group 中设备不支持某个 capability model，应继续跳过，不应报错。

## 建议验证

1. BPS Profile 切换后 SAVE，target groups 不再显示需要同步。
2. BPS Profile 切换后 SAVE，按键 5/6 只改变亮度，不改变色温。
3. 对 target group 的 Group Profile SAVE 后，按键 5/6 仍只改变亮度。
4. 对已经误订阅 CCT 的设备，执行一次 BPS SAVE 或 Group/Profile SAVE 后，CCT Generic Level 对 BPS 虚拟组的订阅被删除。
5. 普通 EnOcean Switch 的 CCT Up/Down 行为不受影响。

