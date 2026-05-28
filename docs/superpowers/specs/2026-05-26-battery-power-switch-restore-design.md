# Battery Power Switch Restore 设计

## 背景

`Site - Space` 的添加设备弹窗已有 `Restore Device Data` 入口。当前恢复页通过 `DeviceRestoreViewController` 扫描待恢复设备，并在新设备 provision 完成后调用 `node.updateResoreData(oldNode:resoreGroup:)` 恢复通用 node 数据。

Light 类型设备能通过现有 `getSyncData(type: .all)` 和后续 `SyncDevicesViewController` 补齐组、profile、scene、schedule 等配置。Battery Power Switch 的关键配置不在普通 node sync 数据里，而在 `PJEightKeySwitchData` / `DeviceSwitchData` 中，因此当前通用恢复链路不能完整恢复 BPS。

当前 BPS 还有一个硬约束：添加完成后 App 会主动断开 Battery Power Switch。恢复流程不能依赖添加完成后再给 BPS 本体补发配置；BPS 本体配置必须放在 add append messages 阶段完成。

## 当前实现结论

恢复页当前没有 BPS 专属分支：

- `DeviceRestoreViewController.addDevice(_:)` 只调用通用 `updateResoreData(oldNode:resoreGroup:)`。
- `getResoreMessageHandles(oldNode:)` 在恢复 append message 中处于注释状态。
- `updateResoreData` 只处理传统 EnOcean switch proxy，不处理 `PJEightKeySwitchData`。
- BPS 普通添加和 LINK 真实设备已经有专属 helper：`BatteryPowerSwitchAddConfiguration`。
- BPS target group 订阅依赖 `switchData.linkGroupAddress`，如果保留旧虚拟组，target 灯具不需要重新订阅。

## 已确认方案

采用“复用旧虚拟组”的恢复方案。

恢复 BPS 时，不分配新的 virtual group，不迁移 target 设备订阅。App 找到旧 BPS 业务记录后，把旧 BPS 的 `linkGroupAddress` 直接配置给新入网的 BPS。新 BPS 的 key config 继续发布到旧虚拟组，现有 target 设备已经订阅旧虚拟组，因此恢复完成后可以继续控制原 target groups。

该方案只作用于 Battery Power Switch。其他类型设备恢复流程保持不变。

## 识别规则

恢复流程中有两个 node：

- `oldNode`：恢复列表中的旧 Mesh node，用于定位旧业务数据。
- `newNode`：本次 provision 完成后新加入的 node，用于承载恢复后的真实设备。

BPS 恢复需要同时满足两个条件：

1. 用旧地址定位旧 BPS 记录：存在 `PJEightKeySwitchData`，且 `switchData.proxyNodeAddress == oldNode.primaryUnicastAddress`。
2. 用新 node 校验设备类型：`BatteryPowerSwitchAddConfiguration.isSupportedAddNode(newNode)` 为 true。

旧地址不用于判断新旧设备是否相同；它只用于定位哪一条 BPS 配置要被恢复。新地址只在定位成功后写入：

- `switchData.proxyNodeAddress = newNode.primaryUnicastAddress`

CID/PID 或 `isBatteryPowerSwitch` 只能判断设备类型，不能区分同一 space 内多台 BPS 的业务配置归属，因此不能替代旧地址匹配。

## 数据恢复规则

恢复后的 BPS 保留原业务记录的同一个 `id`。

保留旧值：

- `name`
- `enabled`
- `eightKeyPanelType`
- `panelType`
- `bindGroupAddresses`
- `unbindGroupAddresses`
- `sceneANumber`
- `sceneBNumber`
- `sceneCNumber`
- `sceneDNumber`
- `moreSettingsState`
- `linkGroupAddress`

恢复时刷新：

- `proxyNodeAddress = newNode.primaryUnicastAddress`
- `maxKeyCount = 8`
- `subLinkGroupAddress = nil`
- `desiredConfigHash` 按当前 BPS 配置重新计算
- `syncState = .pending`
- `lastSyncFailedReason = nil`

不恢复旧设备电量：

- `batteryLevel`
- `batteryLastUpdateTime`

原因是恢复后的 BPS 是新的物理设备，旧电量不代表新设备状态。添加完成后的 best-effort battery get 可以继续按现有 BPS helper 更新新设备电量。

## 配置下发

BPS 本体配置必须加入恢复页的 add append messages。

恢复 BPS append messages 至少包含：

- Key Config：由恢复后的 `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 生成，目标仍是旧 `linkGroupAddress`。
- TX Enable：按 `switchData.enabled` 下发。
- LED Indicator：按 `switchData.moreSettingsState.ledIndicatorEnabled` 下发。

不下发 target group subscription：

- target 灯具已经订阅旧虚拟组。
- 新 BPS 使用旧虚拟组发布命令后，target 灯具无需变更。
- 避免在 BPS 添加完成断开后再做大范围配置。

## 成功处理

如果 BPS 入网和本体配置 append messages 都成功：

- 保存恢复后的 `PJEightKeySwitchData` 到基础 switch 表。
- 保存 8-key metadata。
- 替换 `MeshNetworkManager.instance.switchs` 中同 `id` 的旧对象。
- 调用现有成功标记语义时不得清空 `unbindGroupAddresses`，因为本恢复方案不执行 target unsubscription。
- 使 `appliedConfigHash = desiredConfigHash`。
- 同步 `appliedTxEnabled` 和 `appliedLEDIndicatorEnabled`。
- 发送 switch 刷新和 space 数据变化通知。
- 不创建第二条 BPS。
- 不创建新的 virtual group。
- 不修改 target 设备订阅。

## 失败处理

找不到旧 BPS 业务记录：

- 不进入 BPS 恢复分支。
- 继续使用现有通用恢复逻辑。

新 node 不是支持的 BPS：

- 不覆盖旧 BPS 记录。
- 当前恢复设备标记为 sync failed。

旧 BPS 缺少 `linkGroupAddress`：

- 不能执行“复用旧虚拟组”恢复。
- 保留旧 BPS 记录。
- 标记本次 BPS 配置失败。

BPS 本体配置消息失败：

- 保留恢复后的 `proxyNodeAddress`。
- 保留旧 `linkGroupAddress` 和用户配置。
- `syncState = .failed`。
- `lastSyncFailedReason = "sync_failed".localizedString`。
- UI 显示为已绑定但有 sync issue，后续由现有 BPS 同步入口修复。

target group subscription 不参与本次恢复，不新增迁移失败状态。

## 非目标

- 不改变 light、gateway、dongle、EFC 等其它设备恢复流程。
- 不新增 BPS virtual group。
- 不迁移 target 设备订阅。
- 不删除旧 virtual group。
- 不重构 `MeshFastAddDeviceManager` 或全局 add flow。
- 不修改 SDK、依赖、target 配置、本地化或品牌资源。
- 不新增 Auth 信息。

## 影响范围

预计改动集中在：

- `DeviceRestoreViewController`
- `BatteryPowerSwitchAddConfiguration`
- 在 `BatteryPowerSwitchAddConfiguration` 中新增一个 BPS restore preparation helper

应复用现有 BPS 持久化语义，保持 `switchData.save()`、`PJEightKeySwitchRepository.shared.save(...)` 和 `MeshNetworkManager.instance.switchs` 一致。

## 验收标准

手工验证：

1. 恢复旧 BPS 到新的真实 BPS。
2. Switch 列表仍只有原来那条 BPS，不产生第二条 BPS。
3. BPS 名称、profile、groups、scenes、enable、LED 设置保持不变。
4. `proxyNodeAddress` 更新为新 node 地址。
5. `linkGroupAddress` 保持旧值。
6. 不创建新的 virtual group。
7. target 灯具不进入重新订阅流程。
8. 真实 BPS 按键可以继续控制原 target groups。
9. 配置失败时保留绑定关系并显示 sync issue。
10. 普通 light 恢复行为保持不变。

静态验证：

- BPS 恢复分支使用旧 node 地址定位旧 `PJEightKeySwitchData`。
- BPS 恢复分支使用新 node 判断 `isSupportedAddNode`。
- append messages 中包含 Key Config、TX Enable、LED Indicator。
- target subscription helper 不在 BPS restore 路径中被调用。
- 其它设备类型不经过 BPS restore helper。

构建验证：

- 使用项目要求的 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。
