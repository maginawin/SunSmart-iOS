# Emergency & Fire Controller 功能完整性核查报告

## 范围

本次只检查 Emergency & Fire Controller 在以下流程中的实现完整性：

- Add device
- Add virtual device
- Edit device
- Bind to a new device
- Restore device

不检查 Emergency & Fire Controller 设备页功能，包括监控页、实时状态页、设备页内控制交互。

## 总结

结论：未完全完善。

当前代码已经具备主流程骨架：可以从 Add 菜单创建虚拟 EFC，可以在通用 Add Device 中识别真实 `EmergencyController`，可以把真实 EFC 绑定到虚拟 EFC，Edit 页可以保存一组最小 v2 配置并进入 EFC 专用同步页。但 Restore device 缺少 EFC 专用恢复逻辑，Add Device 添加灯到 EFC 已关联 group 时不会补 EFC 订阅/场景，Edit 页仍是第一阶段能力，不是完整 v2 action editor。

| 功能 | 当前状态 | 结论 |
| --- | --- | --- |
| Add device | 普通添加真实 EFC、选择未绑定虚拟 EFC 作为目标、绑定后刷新入口均存在 | 基本可用，但 group-add 场景缺 EFC 联动同步 |
| Add virtual device | 主 Add 菜单可进入 `LinkedEmerFireEditVC(space:)`，保存本地 `DeviceEmerFireData` | 基本可用 |
| Edit device | 可编辑名称、关联组、Fire/Power Loss 亮度、触发间隔、Restore action/resuming/send count，并在已绑定且配置变化时进入同步 | 部分完成，不是完整 v2 配置能力 |
| Bind to a new device | 编辑页会保存虚拟配置并打开单选 Add Device，只允许 `.emergencyController` | 基本可用，但绑定后未自动进入 EFC 完整同步 |
| Restore device | Restore 列表会包含 current space 的非 Gateway 设备，因此 EFC 可被普通恢复流程扫到 | 未完成，缺 EFC 本地配置迁移和专用同步 |

## 代码事实

### Add device

`0x0A78 / 0x2131` 已在 `SunSmart/devices_config.json` 映射为 `EmergencyController`。通用 Add Device 的绑定目标也已经支持 EFC：

- `SunSmart/Main/Device/Controller/DeviceAddViewController.swift:36-84` 定义 `AddDeviceBindTarget.emergencyFire`，允许的设备类型为 `.emergencyController`。
- `SunSmart/Main/Device/View/DeviceAddTargetSelectView.swift:23-50` 的目标选择弹层包含 `emergencyFire` 分组。
- `SunSmart/Main/Device/Controller/DevicesViewController.swift:458-478` 的普通 Add Device 入口设置 `allowsEmergencyFireVirtualTargetSelection: true`。
- `DeviceAddClassicModeController` 在 provisioning 完成和 append 阶段会对 `.emergencyController` 调用 `DeviceEmerFireStore.bind(...)` 或 `ensureDevice(...)`，并为普通新增 EFC 追加 Scene Client / Light LC Client publication。对应代码在 `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:1218-1240`。
- Professional 模式有同等逻辑，见 `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:1242-1263`。

缺口：当 Add Device 目标是某个 group，并且这个 group 已被某个 EFC 关联时，新加入的灯只走 `DeviceGroupFastAddSyncPlanner.makePlan(...)`，不会调用 `EmergencyFireControllerSyncPlanner.makeGroupMutationItems(...)`。Classic 证据在 `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift:1270-1279`，Professional 证据在 `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift:1293-1301`。这会导致新灯没有订阅 EFC 内部 publish group，也没有写入 EFC 保留场景。

对比：手动 Group Members 变更已经在 `SyncDevicesViewController` 接入 EFC group mutation，见 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:196-200` 和 `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift:819-840`。因此 Add Device group-add 缺的是复用这条已存在链路。

### Add virtual device

`DevicesViewController.addAction` 的 Others 分支会进入 `showEmerFireCreatePage()`，直接打开 `LinkedEmerFireEditVC(space:)`，见 `SunSmart/Main/Device/Controller/DevicesViewController.swift:369-403`。

保存时 `LinkedEmerFireEditVC.createVirtualDevice()` 会创建并保存 `DeviceEmerFireData`、刷新 Others 列表并触发 space common 变更，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift:132-145`。

当前 Add virtual 的功能主链路成立，但 `Report To Gateway` 仍是固定的 `Waiting for setup` 展示和点击 HUD，未看到网关选择/绑定逻辑，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift:49-63`。

### Edit device

Edit 页可见行包括名称、Report To Gateway、关联组、Fire/Power Loss 亮度、触发间隔、Restore action 和 Restore timing，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC+Table.swift:13-25`。

保存时如果已有真实绑定节点且配置变化，会进入 `SyncDevicesViewController(type: .emergencyFire(...))`，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift:102-121`。EFC 同步 planner 会生成 Enable、Resend、Action Config、Restore Delay 以及关联 group/cleanup 任务，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData+Sync.swift:174-247` 和 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmergencyFireControllerSyncPlanner.swift:85-98`。

缺口：

- `EmergencyFireControllerConfiguration.enabled` 当前硬编码为 `true`，没有 UI 和持久化字段表达禁用状态，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift:176-180`。
- v2 action preset 模型已支持多种 action 类型，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift:50-82`，但 `triggerActionPreset` 注释明确写着当前 UI 未暴露，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift:98-108`。当前触发动作只通过亮度派生，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift:256-261`。
- Restore action 只暴露 `Restore AUTO`、`Set Brightness to`、`None`，而不是完整 action editor。当前 restore settings 字段见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/LinkedEmerFireConfig.swift:148-157`。
- Report To Gateway 未实现真实选择或保存。

### Bind to a new device

编辑页的 Link 操作会先保存当前虚拟配置，再打开 `DeviceAddViewController`，设置 `bindTarget = .emergencyFire(device)`、只允许 Others 类别、阻止 dongle/gateway/unknown，并强制 single selection，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/LinkedEmerFireEditVC.swift:182-219`。

通用 Add 容器在符合绑定目标的节点添加成功后会自动关闭并回调，见 `SunSmart/Main/Device/Controller/DeviceAddViewController.swift:218-250`。Store 绑定后会把 `isSynced` 置为 `false`，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift:100-110`。

缺口：绑定成功后只是刷新编辑页，没有立即进入 EFC 专用同步页。用户需要再点同步入口或再次保存触发同步。对于已有 group 配置的虚拟 EFC，这会留下“已绑定但未下发 Enable/Resend/Action/Restore Delay/关联灯组任务”的中间状态。

### Restore device

Restore 主入口使用 `restoreFilter: .currentSpaceNonGateways`，因此 EFC 作为非 Gateway 会被包含，见 `SunSmart/Main/Device/Controller/DevicesViewController.swift:514-518` 和 `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:379-389`。

问题在后续恢复逻辑：

- `DeviceRestoreViewController` 文件内没有 `DeviceEmerFireStore`、`.emergencyFire` 或 `EmergencyFireControllerSyncPlanner` 引用。
- provisioning 完成时对所有恢复节点设置 `node.requiredFunctionTypes = [.lightLCScene, .lightLCScheduler]`，没有像 Add Device 一样排除 `.emergencyController`，见 `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:1648-1676`。
- append 阶段走普通 `newNode.getSyncData(type: .all)` 和普通 restore sync，见 `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:1681-1734`。
- restore 成功后只保存新 node、追加到 `restoreNodes`，没有迁移 `DeviceEmerFireData.bindNodeAddress`，也没有保留 EFC 的 `configuration/publishGroupAddress/isSynced` 语义，见 `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift:1776-1798`。
- `Node.updateResoreData(oldNode:resoreGroup:)` 只迁移 group、传感器校准、动能开关 proxy、邻近照明、schedule、dongle 等普通业务对象，没有 EFC 配置迁移，见 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:2531-2623`。

风险：恢复 EFC 后，旧 `DeviceEmerFireData` 仍可能指向旧节点地址；`DeviceEmerFireStore.mergeRealEmergencyControllers(...)` 后续看到新真实 EFC 没有匹配的本地配置，会创建一条默认配置记录，见 `SunSmart/Main/Device/Device1.5/FireAlarm/Model/DeviceEmerFireData.swift:138-156`。这可能造成旧配置丢失、重复 EFC 卡片、关联 group/publish group 不一致。

## 修复方案与计划

### P0：补齐 Restore device 的 EFC 专用恢复

目标：恢复真实 EFC 后，保留原本的 EFC 本地配置，更新绑定地址，并能完成 EFC 专用同步。

计划：

1. 在 `DeviceEmerFireStore` 增加 restore helper：按 `oldNode.primaryUnicastAddress` 查找已有 `DeviceEmerFireData`，找到后把 `bindNodeAddress` 更新为 `newNode.primaryUnicastAddress`，保留 `configuration`、`publishGroupAddress`、`reportToGateway`、pending cleanup；找不到时再 `ensureDevice(for:in:)`。
2. 在 `DeviceRestoreViewController.provisionCompleteCallback` 中识别 `oldNode.deviceType == .emergencyController || addDevice.deviceType == .emergencyController`，跳过 `requiredFunctionTypes = [.lightLCScene, .lightLCScheduler]`。
3. 在 restore append 或 restore success 后调用上面的 helper，并将恢复后的 EFC 标记为 `isSynced = false`。
4. 对恢复出的 EFC 进入 `SyncDevicesViewController(type: .emergencyFire(..., persistsSyncResult: true, changedFromConfiguration: nil))`，或至少把它纳入恢复后的 sync failure/Sync 按钮队列，确保 `EmergencyFireControllerSyncPlanner.makeItems()` 执行。
5. 发送 `deviceOthersRefreshNotificationName`、`.deviceEmerFireDataDidChange`、`linkedEmerFireConfigDidChange`，避免 Others 列表和 proxy filter 使用旧状态。
6. 验证：准备一个已配置 group/restore action 的 EFC，删除/恢复后确认本地只保留一条 EFC 配置，名称、关联组、restore action、publishGroupAddress 不丢失，并能完成 EFC 同步。

### P1：补齐 Add Device 添加灯到 EFC 关联 group 的同步

目标：通过 Add Device 把新灯加入已被 EFC 关联的 group 时，立即补齐该灯对 EFC 内部 publish group 的订阅和保留场景写入。

计划：

1. 抽出一个可复用 helper，把 `EmergencyFireControllerSyncPlanner.makeGroupMutationItems(group:addNodes:exitNodes:space:)` 转成 Add Device append 阶段可用的 message handles。
2. 在 `DeviceAddClassicModeController` 和 `DeviceAddProfessionalModeController` 的 group append 阶段，在 `DeviceGroupFastAddSyncPlanner.makePlan(...)` 后追加 EFC group mutation plan。
3. 复用现有 fast-add sync failure 记录机制，EFC mutation 失败时把对应 add device 标为 `.syncFailed`，不要静默成功。
4. 验证：先创建 EFC 并关联 group，再通过 Add Device 直接添加新 light 到该 group，确认 append messages 包含 Scene Server subscription、Light LC subscription、trigger scene store，以及失败时 UI 显示 sync failed。

### P1：绑定真实 EFC 后进入完整同步闭环

目标：虚拟 EFC bind to a new device 成功后，用户不用额外再找同步入口。

计划：

1. 在 `LinkedEmerFireEditVC.linkRealDeviceAction()` 的 `deviceAddCallback` 中刷新 store 后，判断 `device.bindNode != nil` 且 `device.hasSyncableConfiguration == true`。
2. 满足条件时 push 或 present `SyncDevicesViewController(type: .emergencyFire(data: device, items: nil, persistsSyncResult: true, changedFromConfiguration: nil))`。
3. 若没有关联 group 和 pending cleanup，则保持当前刷新并关闭行为，避免空配置无意义同步。
4. 验证：预创建虚拟 EFC，配置 group 后 Link 真实设备，添加成功应直接进入 EFC sync；无 group 的虚拟 EFC Link 后不强制同步。

### P2：补齐 Edit device 的完整 v2 配置能力

目标：从“最小可同步配置页”升级为完整 v2 配置页。

计划：

1. 把 `enabled` 从硬编码改为 `EmergencyFireControllerConfiguration` 的持久化字段，并在 Edit 页提供启用/禁用控制。
2. 为 Power Loss 和 Fire Alarm 的 trigger action 暴露 action preset editor，覆盖 `EmergencyFireControllerActionPreset` 当前已有的 action 类型。
3. 保持现有简单亮度 UI 作为 lightness action 的快捷编辑，不破坏现有默认值。
4. 实现 Report To Gateway 的真实选择/保存/同步语义；若当前版本不准备支持，应隐藏或改文案，不能继续显示固定 `Waiting for setup`。
5. 验证：对每种 action 类型保存后，`SunricherVendorSet(function: .emergencyActionConfig(...))` payload 与 SDK `EmergencyFireActionConfig` 一致。

### P3：清理或补齐未接入的 FireAlarm 专用容器

目标：避免未来使用旧 factory 时行为缺字段。

计划：

1. `PJDevicesFireAlarmAddContainerController` 当前未传 `context.bindTarget` 给 `DeviceAddViewController`，而 EightKey 同类容器有传。若 FireAlarm factory 后续要用于 link 流程，需要补传。
2. `EmerFireAlarmAddProfessionalVC` 当前是空壳。若不再使用，应标记废弃或删除引用；若计划作为新版 Add 页面，应补齐真实实现。
3. `PJDevicesRestoreFlowFactory` 当前没有调用方。若要作为 EFC restore 专用入口，需要和 P0 的 restore helper 一起接入；否则不要把它当作已实现功能。

## 建议执行顺序

1. 先做 P0 Restore device。这个缺口风险最高，可能造成配置丢失和重复 EFC 记录。
2. 再做 P1 Add Device group mutation。这个影响 EFC 关联 group 后续新增灯的安全联动。
3. 同批做 P1 Link 后自动同步，收敛“已绑定但未下发”的中间状态。
4. 最后做 P2/P3，完善完整协议能力和清理旧容器。

## 本次未做

- 未修改业务代码。
- 未运行 iPhoneOS build。本次是静态代码核查和分析报告输出。
- 未检查 Emergency & Fire Controller 设备页功能。
