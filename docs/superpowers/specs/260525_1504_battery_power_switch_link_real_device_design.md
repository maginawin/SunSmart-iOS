# Battery Power Switch 虚拟设备 LINK 真实设备设计

## 背景

Battery Power Switch 已支持 pre-create，用户可以先在本地创建一个未关联真实设备的虚拟 BPS，并在编辑页保留 `LINK` 入口。当前真实 BPS 新增流程会根据 PID 创建默认 switch 数据：

- `0x2A01` 默认 `Scene Panel (8 key)`。
- `0x2A02` 默认 `Brightness Panel (8 key)`。

但虚拟 BPS 在 LINK 前允许用户切换 profile、选择 groups/scenes、调整 Enable 和 More Settings。因此 LINK 真实设备时，不能再让真实设备 PID 覆盖虚拟设备当前配置。

## 已确认需求

- LINK 真实设备时支持两个 PID：`0x2A01`、`0x2A02`。
- PID 只用于判断真实设备是合法 Battery Power Switch。
- 如果虚拟 BPS 当前 profile 与真实 PID 默认 profile 不一致，仍允许绑定，不提示、不阻断。
- LINK 后以虚拟 BPS 当前配置作为目标配置下发。
- LINK 成功后，原虚拟 BPS 升级为已关联真实设备，不新建第二条 BPS。
- LINK 时立即下发当前虚拟配置，包括 profile、Enable、LED Indicator、虚拟 link group、已选择的 target groups/scenes。
- 如果 BPS 自身配置失败，保留已绑定关系并标记 sync failed，后续通过现有同步链路修复。

## 非目标

- 不改变普通添加真实 Battery Power Switch 的默认 PID 到 profile 映射。
- 不限制真实 PID 和虚拟 profile 必须一致。
- 不新增新的 profile 类型。
- 不重构现有扫描、provision、key bind 主流程。
- 不新增 Auth 信息。
- 不修改依赖、target 配置或品牌资源。

## 需求真实性与可行性

需求真实性成立。现有代码已经在 `Node.batteryPowerSwitchPanelType` 中维护两个 PID 的默认 profile：

- `0x2A01` -> `.scene8Key`
- `0x2A02` -> `.brightness8Key`

这只是“真实设备首次新增”的默认行为。虚拟 BPS 的业务语义是用户先配置目标开关，再把一个真实 BPS 绑定到该配置，因此 LINK 场景应以虚拟 BPS 的 `eightKeyPanelType` 为准。

可行性成立。当前 key config 由 `PJEightKeySwitchData.batteryPowerSwitchKeyConfigurations(appKeyIndex:)` 根据 `eightKeyPanelType` 生成，并未在 App 代码层按 PID 禁止 Scene/Brightness 互换。只要真实 node 是支持的 BPS，配置下发可以按虚拟 profile 生成。

## 方案选择

采用方案 A：把 LINK 作为“把真实 node 绑定到现有虚拟 BPS”。

LINK 添加成功后，不创建新 BPS，而是将真实 node 的 `primaryUnicastAddress` 写入原虚拟 BPS 的 `proxyNodeAddress`，确保 `linkGroupAddress` 存在，并按虚拟 BPS 当前配置生成配置任务。

不采用“先按 PID 创建新 BPS，再迁移虚拟配置”的方案，因为中间态容易出现两条 BPS，失败回滚复杂，且本地 switch id 变化会影响从编辑页或详情页返回后的刷新。

不采用“只绑定 node，不立即同步”的方案，因为用户已确认 LINK 后应立即完整下发配置，避免 LINK 成功但设备不可用。

## 核心数据规则

LINK 成功后，原虚拟 BPS 继续使用同一个 `id`。

需要保留并作为下发目标的字段：

- `name`
- `enabled`
- `eightKeyPanelType`
- `panelType`
- `bindGroupAddresses`
- `sceneANumber`
- `sceneBNumber`
- `sceneCNumber`
- `sceneDNumber`
- `moreSettingsState.ledIndicatorEnabled`

需要在绑定时写入或刷新的字段：

- `proxyNodeAddress = node.primaryUnicastAddress`
- `maxKeyCount = 8`
- `linkGroupAddress` 不存在时创建虚拟 group
- `subLinkGroupAddress = nil`
- `desiredConfigHash` 按当前虚拟配置重新计算
- `desiredConfigVersion` 至少递增到 `1`
- `syncState = .pending`
- `appliedConfigHash = ""`
- `lastSyncFailedReason = nil`

如果用户选择的是 `Scene Panel (8 key)`，即使真实 PID 是 `0x2A02`，也继续生成 Scene Profile 的 key config。如果用户选择的是 `Brightness Panel (8 key)`，即使真实 PID 是 `0x2A01`，也继续生成 Brightness Profile 的 key config。

## 添加流程接入

`PJPreAddEightKeySwitchesVC.linkAction()` 应从“打开 Switches 单选添加流程”升级为“打开带绑定目标的添加流程”。

建议新增：

- `AddDeviceBindTarget.batteryPowerSwitch(PJEightKeySwitchData)`

`addBehavior` 继续只承载通用添加限制：

- `allowsTargetSelection = false`
- `allowsCategorySelection = false`
- `allowedTypes = [.switches]`
- `selectionMode = .single`

`bindTarget` 承载具体业务目标：

- `emergencyFire`：真实设备必须是 `.emergencyController`。
- `batteryPowerSwitch`：真实设备必须满足 `isBatteryPowerSwitch == true`。

现有 `AddDeviceBindTarget.allowedDeviceTypes` 只能按 `Node.DeviceType` 判断，而 BPS 和普通 switches 都是 `.switches`。因此需要给 bind target 增加更细粒度判断能力，例如：

- 对扫描设备判断：是否允许当前 `ProvisioningDevice`。
- 对入网后 node 判断：是否允许当前 `Node`。

Classic / Professional 两套添加页面都应使用同一套 bind target 判断：

- 扫描列表中非 BPS switches 置灰或不可选。
- 单选模式只允许一个合法 BPS 进入添加。
- 添加完成后，如果 bind target 是 BPS，则走绑定已有虚拟 BPS 逻辑。
- 普通 site 添加真实 BPS 仍走现有新建 BPS 逻辑。

`PJDevicesEightKeyAddContainerController` 需要把 `bindTarget` 从 `PJDevicesAddEntryContext` 透传到 `DeviceAddViewController`。

## 绑定与配置下发

建议在 `BatteryPowerSwitchAddConfiguration` 中新增“绑定已有虚拟 BPS”的 prepare 方法，而不是修改 `MeshNetworkManager.createDefaultSwitch(forBatteryPowerSwitch:)`。

普通新增真实 BPS 继续走现有逻辑：

- 根据 PID 创建默认 profile。
- 创建默认 switch 数据。
- 下发默认 key config。

LINK 已有虚拟 BPS 走新逻辑：

1. 验证 node 是支持的 Battery Power Switch。
2. 验证 node 未被其他 switch 的 `proxyNodeAddress` 使用。
3. 基于传入的虚拟 `PJEightKeySwitchData` copy 或原对象更新绑定字段。
4. 确保 `linkGroupAddress` 存在；如果 group address 不足，则绑定前失败。
5. 按当前虚拟配置计算 desired config。
6. 保存基础 switch 和 8-key metadata。
7. 更新 `MeshNetworkManager.instance.switchs` 中同 id 的对象。
8. 生成入网 append messages。

LINK 场景的 BPS 自身配置应至少包含：

- Key Config：按当前虚拟 profile / scenes / linkGroup 生成。
- TX Enable：按当前 `enabled` 下发。
- LED Indicator：按当前 `moreSettingsState.ledIndicatorEnabled` 下发。

Target group subscription 不建议塞进入网 append messages。它需要让目标 group 内各灯节点订阅 BPS 的 link group，范围可能较大，应继续复用现有 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`。

## 成功处理

如果 BPS 入网和自身配置都成功：

- 调用现有成功标记逻辑，将 `syncState` 标记为 `.synced`。
- 写入 `appliedConfigHash = desiredConfigHash`。
- 写入 `appliedTxEnabled = enabled`。
- 写入 `appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled`。
- 保存基础 switch 和 metadata。
- 发送 `switchsRefreshNotificationName`。
- 发送 `spaceDataChangedNotificaitonName`。
- 添加页通过 `deviceAddCallback` 回传新增 node。
- 编辑页刷新当前 switch 数据，`LINK` 按钮变为 `LINKED`。

如果没有 target group subscription 需要同步，提示 `done!` 并结束 LINK 流程。

如果存在 target group subscription 需要同步，建议由 `PJPreAddEightKeySwitchesVC` 在添加完成 callback 后 push 现有 `SyncDevicesViewController(type: .batteryPowerSwitch(...))`，让用户看到同步进度。同步成功后提示 `done!` 并回到上一层。

## 失败处理

地址或虚拟 group 不足：

- 在写入 `proxyNodeAddress` 前失败。
- 不改变虚拟 BPS。
- 虚拟 BPS 仍保持 `Unlinked`。
- 显示现有 group/address 不足提示。

真实设备入网失败：

- 不改变虚拟 BPS。
- 虚拟 BPS 仍保持 `Unlinked`。

BPS 已被其他 switch 绑定：

- 阻止绑定。
- 不覆盖其他 switch。
- 提示类似现有 `switch_proxy_exist` 的冲突文案。

入网成功但 BPS 自身配置失败：

- 保留 `proxyNodeAddress`。
- 保留 `linkGroupAddress` 和用户目标配置。
- 标记 `syncState = .failed`。
- 写入 `lastSyncFailedReason = "sync_failed".localizedString`。
- 保存到数据库。
- 后续通过现有同步链路修复。
- 编辑页显示 `LINKED`，详情页不再显示 `Unlinked`，列表显示 sync issue。

## 页面刷新

`PJPreAddEightKeySwitchesVC` 在 LINK 添加完成回调中需要：

- 从 `MeshNetworkManager.instance.switchs` 重新读取当前 switch id。
- 重建 view model。
- 更新 LINK 按钮状态。
- 必要时进入 target group subscription sync。

如果用户从详情页进入 Edit 再 LINK，完成后返回详情页时，详情页应通过通知或重新读取 switch 数据刷新：

- Status 不再显示 `Unlinked`。
- 菜单恢复真实 BPS 行为。
- Enable 与 More Settings 进入真实设备同步语义。

## 影响范围

预计修改集中在：

- `SunSmart/Main/Device/Controller/DeviceAddViewController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddClassicModeController.swift`
- `SunSmart/Main/Device/Controller/DeviceAddProfessionalModeController.swift`
- `SunSmart/Main/Device/Device1.5/Common/Flow/PJDevicesAddEntryContext.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Add/Controller/PJDevicesEightKeyAddContainerController.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Model/BatteryPowerSwitchAddConfiguration.swift`

不建议修改：

- `MeshNetworkManager.createDefaultSwitch(forBatteryPowerSwitch:)` 的普通新增语义。
- PID 到默认 profile 的映射。
- target 配置、依赖或品牌资源。

## 测试计划

静态检查：

- LINK 入口传入 `AddDeviceBindTarget.batteryPowerSwitch`。
- Classic / Professional 两套添加页面都能按 `isBatteryPowerSwitch` 限制选择。
- 普通新增真实 BPS 仍调用默认创建路径。
- BPS LINK 路径不会新建第二条 switch。
- LINK 路径会生成 Key Config、TX Enable、LED Indicator。
- Target group subscription 仍走现有 sync 页面。

手动 QA：

- 虚拟 BPS 为 Scene Profile，LINK 到 `0x2A01`，成功绑定并下发 Scene 配置。
- 虚拟 BPS 为 Scene Profile，LINK 到 `0x2A02`，允许绑定，仍下发 Scene 配置。
- 虚拟 BPS 为 Brightness Profile，LINK 到 `0x2A01`，允许绑定，仍下发 Brightness 配置。
- 虚拟 BPS 为 Brightness Profile，LINK 到 `0x2A02`，成功绑定并下发 Brightness 配置。
- 虚拟 BPS Enable Off，LINK 后下发 TX Enable false，保存后详情页 Enable 为 Off。
- 虚拟 BPS LED Indicator Off，LINK 后下发 LED false，保存后 More Settings 保持 Off。
- 虚拟 BPS 已选择 groups，LINK 后自身配置成功，再进入 target subscription sync。
- 真实 BPS node 已被其他 BPS 绑定时，阻止绑定，不覆盖原数据。
- 普通 site 添加真实 BPS，仍按 PID 默认 profile 新建，不受 LINK 逻辑影响。

构建验证：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
