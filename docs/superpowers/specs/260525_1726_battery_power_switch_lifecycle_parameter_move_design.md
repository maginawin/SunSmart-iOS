# Battery Power Switch Lifecycle, Parameter Filter And Level Move 设计

## 背景

本次需求继续完善 Battery Power Switch 的真实设备生命周期和配置行为，范围包含四件事：

- Battery Power Switch 普通入网和虚拟设备 LINK 到真实设备后，尝试读取一次当前电池电量。
- 删除已绑定真实 Battery Power Switch 时，静默发送 reset，并按真实设备删除处理本地数据和云同步。
- `Site - Space - More - Device Parameter Settings` 不展示 Switch 类型设备。
- 优化 Battery Power Switch profile 中长按 dimming 的 level move 参数，使 0% 到 100% 约 10 秒。

现有代码已经具备以下基础：

- `BatteryPowerSwitchAddConfiguration` 负责新增和 LINK 时的 BPS Switch 数据准备、默认配置下发和 sync 状态保存。
- `DeviceAddClassicModeController` 与 `DeviceAddProfessionalModeController` 都在 BPS 入网成功后调用 `finalizeBatteryPowerSwitchAddConfiguration(for:)`。
- `MeshBatteryPowerSwitchBatteryReader` 已通过 `GenericBatteryGet` / `GenericBatteryStatus` 读取 BPS 电池电量。
- `MeshNetworkManager.deleteSwitch(switchData:)` 是 Switch 本地删除的公共清理入口。
- `Node.supportSetParameter` 是 Device Parameter Settings 入口判断设备是否支持参数设置的关键能力。
- `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 生成 BPS profile key configuration。

## 目标

1. BPS 入网或 LINK 成功后，尽力读取一次电池电量；成功则保存为最近一次电量，失败不影响入网或 LINK 成功。
2. 删除已绑定真实 BPS 时，不再只删除 Switch 数据；需要静默发送 reset，并删除本地真实 Node。
3. Device Parameter Settings 对所有 Switch 类型设备统一不可见，包括 Kinetic Switch、Battery Power Switch 和后续 Switch 类型设备。
4. BPS 长按 dimming 的 move speed 调整到约 10 秒完成 0% 到 100%。

## 非目标

- 不改变普通手动 Refresh Battery 弹窗流程、文案、超时和重试规则。
- 不把入网电池读取加入新增设备的 append message 队列。
- 不要求删除 BPS 时 reset 一定成功。
- 不改变未绑定虚拟 BPS 的删除行为。
- 不改变 BPS click dimming 的 20% 单步 delta。
- 不新增 UI 页面或可见提示。

## 设计方案

采用聚焦现有 BPS 专属路径的方案：

- 入网电池读取放在 BPS finalize 之后独立执行，失败静默忽略。
- 删除 reset 放在 BPS 删除分支中 fire-and-forget，随后立即继续本地删除。
- Device Parameter Settings 通过 `Node.supportSetParameter` 统一排除 `.switches`。
- 长按 dimming 只调整 BPS key configuration 的 move 参数。

这个方案改动集中，符合现有职责边界，也避免把 best-effort 行为引入同步任务成败判断。

## 入网后电池读取

普通新增真实 BPS 和虚拟 BPS LINK 到真实设备都需要覆盖。

流程如下：

1. BPS provisioning 成功。
2. Add Controller 调用 `finalizeBatteryPowerSwitchAddConfiguration(for:)`。
3. 现有逻辑先根据配置下发结果执行 `markSucceeded` 或 `markFailed`，并保存 Switch 状态。
4. 如果本次入网最终能关联到 `PJEightKeySwitchData`，并且 node 是支持的真实 BPS，则发起一次独立电池读取。
5. 读取成功时，使用现有 repository 保存 `batteryLevel` 和 `batteryLastUpdateTime`，并更新内存对象。
6. 读取失败、超时、无 battery model、返回未知电量或非法电量时，不展示提示，不改变新增或 LINK 结果。

读取逻辑复用 `MeshBatteryPowerSwitchBatteryReader` 的现有规则：发送 `GenericBatteryGet`，只接受 `GenericBatteryStatus` 中已知且 `0...100` 的电量。

入网流程的成功与否仍以 BPS 配置结果为准。电池读取只是附加数据采集，不参与 `syncState`、`appliedConfigHash` 或用户最终 Done 的判断。

## 删除真实 BPS

删除已绑定真实 Battery Power Switch 时，按真实设备删除处理，而不是只按虚拟 Switch 删除处理。

流程如下：

1. 调用 `MeshNetworkManager.deleteSwitch(switchData:)`。
2. 如果 `switchData.proxyNode` 是真实 Battery Power Switch，则先尝试发送一条 `ConfigNodeReset` 到该 node address。
3. reset 不等待返回结果，不处理 ACK，不设置额外超时，不展示进度，不影响删除成功判断。
4. App 立即继续删除本地 Switch 数据、BPS metadata、link virtual group、sub link group 和本地节点订阅。
5. 同时删除对应真实 BPS node 本地缓存，使 Space 不再留下已 reset 或即将 reset 的真实 node。
6. 真实 BPS 删除完成后，明确触发 `switchsRefreshNotificationName` 和 `spaceDataChangedNotificaitonName` 的 `.network(type: .address)`。

选择 `.network(type: .address)` 的原因是：真实 BPS 删除同时改变设备列表和地址占用，不应依赖调用方碰巧发了 `.common` 或 `.device`。该通知会让 Site + 当前 Space 走 promptly 云同步，覆盖设备数据、地址数据和 Switch 数据变化。

未绑定真实 node 的虚拟 BPS 不发送 reset，也不删除 Node，继续保持现有虚拟 Kinetic switch 风格：只删除本地 Switch 数据并触发普通 Switch/Space 刷新。

## Device Parameter Settings 过滤

`Site - Space - More - Device Parameter Settings` 不展示 Switch 类型设备。

规则下沉到 `Node.supportSetParameter`：

- 如果 `node.deviceType == .switches`，返回不支持。
- 其余设备继续沿用现有条件，包括 vendor model、product identifier、dongle、gateway、emergency controller 等判断。

这样入口页和后续参数页面不需要维护 PID 黑名单，也不需要识别具体 Switch 产品名。只要设备在 `devices_config.json` 中归类为 `Switches` 或现有映射能得到 `.switches`，都会被自动排除。

预期影响：

- Kinetic Switch 不展示。
- Battery Power Switch 不展示。
- 后续其他 Switch 类型设备不展示。
- Lighting、Sensor 等原本支持参数设置的设备不受影响。

## BPS 长按 level move 参数

现有 BPS dimming 配置中，button 4/5 同时使用 `13107` 作为 click delta 和 press move 参数。`13107` 约等于 20% 的 level step，适合作为 click 单步，但不适合作为长按 move speed。

新的参数拆分为两类：

- click delta：保持 `13107`，继续表示单击约 20% 调光步进。
- press move：改为约 `6553`，按 Generic Level 全范围 `65535 / 10` 估算，使 0% 到 100% 约 10 秒。

配置结果：

- button 4 click：level delta `+13107`。
- button 4 press：level move `+6553`。
- button 4 pressRelease：level move `0`，停止。
- button 5 click：level delta `-13107`。
- button 5 press：level move `-6553`。
- button 5 pressRelease：level move `0`，停止。

这只影响 BPS profile 配置下发，不改变 App 监控页中间模拟点击的单次 dimming 行为。

## 错误处理

- 入网电池读取失败静默忽略，不改变新增、LINK、sync 或 Done 结果。
- 删除真实 BPS 时 reset 发送失败、设备离线、设备未激活或无响应都视为删除流程成功，App 不展示错误。
- 删除真实 BPS 的本地 Node 清理失败时，应避免留下不一致状态；实现计划中需要明确使用现有 node 删除/force remove 能力并确认数据库、内存和地址缓存同步。
- Device Parameter Settings 过滤后，如果一个 Space 只有 Switch 类型设备，应展示现有空设备状态。
- 长按 move 参数调整后，旧设备只有在重新保存或同步 BPS profile 后才会收到新参数。

## 测试与验证

建议验证以下场景：

1. 普通新增真实 BPS，配置成功，若设备返回有效 `GenericBatteryStatus`，Switch 详情页显示最近一次电量。
2. 普通新增真实 BPS，电池读取超时或未知电量，新增仍显示成功，电量保持未获取状态。
3. 虚拟 BPS LINK 到真实 BPS，LINK 成功后也尝试读取电池，成功则保存到同一条 Switch 数据。
4. 删除已绑定真实 BPS，App 立即完成删除；在线设备收到 reset 后自动重置；离线或未激活设备不影响 App 删除成功。
5. 删除真实 BPS 后，Switch 列表、Space 设备计数、真实 Node 列表和云同步任务均按地址级变化刷新。
6. 未绑定虚拟 BPS 删除仍保持原有本地删除行为。
7. Device Parameter Settings 中不再出现 Kinetic Switch、Battery Power Switch 或其他 `.switches` 设备。
8. BPS profile 保存或同步后，检查 key configuration 中 press move 参数为约 `±6553`，pressRelease 仍为 `0`。
9. iOS 构建通过。

