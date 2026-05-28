# Battery Power Switch Pre-Create 设计

## 背景

当前添加设备入口已经有 `Switches` 类型选择弹窗，用户选择 `Battery Power Switch` 后仍显示 `under_development`。项目中同时已经存在较完整的 8-key / Battery Power Switch 本地模型、编辑页、列表 cell、More Settings 和真实设备同步链路。

本次目标是在 `site - space - 添加设备 - Switches - Battery Power Switch` 路径下支持创建一个未绑定真实设备的 Battery Power Switch。该虚拟开关先保存本地配置，后续用户再通过 LINK 绑定真实 Battery Power Switch，并在绑定后决定虚拟 group 与同步。

## 已确认需求

- UI 按 Figma 节点 `65:4805` 的底部上浮窗布局实现，使用项目现有 UIKit / SnapKit / 主题色与组件。
- 默认名称沿用现有 Switch 新增逻辑，即 `MeshNetworkManager.instance.getNextSwitchName()`。
- 默认 Enable 为 On。
- 默认 Profile 为 Scene Profile，UI 行名沿用现有 `Panel`，默认值显示 `Scene Panel (8 key)`。
- 默认 Group 为 `N/A`，保留选择 group 能力。
- 默认 Scene 为 `N/A`，保留选择 scene 能力。
- More Settings 中 `LED Indicator` 默认为 Enabled。
- 下方 switch profile preview cell 使用现有真实 Battery Power Switch 的同一套 8-key preview 控件。
- 点击 CREATE 后只在本地创建未绑定真实设备的 Battery Power Switch。
- pre-create 阶段不分配虚拟 group，后续绑定真实设备后再确定虚拟 group。

## 非目标

- 不实现真实 Battery Power Switch 的扫描、绑定和完整同步新流程。
- 不在 pre-create 阶段创建 Mesh virtual group。
- 不在 pre-create 阶段发送 Mesh / BLE 命令。
- 不调整 Battery Power Switch 已有 Key Config、TX Enable、LED Indicator、target group subscription 同步协议。
- 不新增 Auth 信息，不改 target 配置、依赖或品牌资源。

## 方案选择

采用复用 `PJPreAddEightKeySwitchesVC` 并增加明确 create 类型的方案。

现有 `PJPreAddEightKeySwitchesVC`、`PJPreAddEightKeySwitchesViewModel`、`PJEightKeySwitchEditorView`、`PJEightKeySwitchPanelView` 已覆盖本次 Figma 结构：Name、Enable、Panel、Group、Scene、More Settings、8-key preview 和底部 CREATE。复用这些组件可以保证 pre-create 页面和真实 Battery Power Switch 编辑页保持同一套行为。

新增一个明确的创建类型，例如 `PJPreAddEightKeySwitchesViewModel.CreationKind`：

- `kineticSwitch`：保留现有普通 pre-created switch 行为。
- `batteryPowerSwitch`：本次新增 Battery Power Switch pre-create 行为。

不采用新建专用 VC，因为会重复 Name、Enable、Panel、Group、Scene、More Settings、preview 与保存逻辑，后续真实 BPS 编辑页更新时容易分叉。不采用完全复用现有 create 模式而不区分类型，因为 Battery Power Switch 需要专属 metadata、默认 Scene Profile、LED 默认值和后续 LINK 语义，混在普通 switch create 中会让绑定真实设备后的边界不清晰。

## UI 设计

入口沿用当前路径：

1. Space 页面点击添加。
2. 添加设备弹窗选择 `Switches`。
3. `PJSwitchesTypesVC` 中选择 `Battery Power Switch`。
4. 展示 `PJPreAddEightKeySwitchesVC` 的 Battery Power Switch pre-create 模式。

页面行为：

- 标题为 `Switch`。
- create 模式右上角使用关闭按钮，底部显示 `CREATE`。
- Name 文本框预填现有 next switch name。
- Enable switch 默认打开。
- Panel 行默认 `Scene Panel (8 key)`，点击进入现有 panel/profile 选择页。
- Group 行默认 `N/A`，点击进入现有 group 多选页。
- Scene 行默认 `N/A`，Scene Profile 下显示并点击进入现有 scene 选择页。
- More Settings 行进入现有 More Settings 页面，`LED Indicator` 默认 Enabled。
- Preview 使用 `PJEightKeySwitchPanelView` 和 `PJEightKeySwitchPanelDefinition`，不创建新的 preview 控件。

Figma 中的 `Panel` 行承载业务上的 Battery Power Switch profile。实现和文档统一称为 `Panel`，并在业务描述中说明它对应 BPS profile/panel type。

## 数据模型

Battery Power Switch pre-create 点击 CREATE 后构造 `PJEightKeySwitchData`：

- `id` 使用新的 UUID。
- `enabled` 取页面当前值，默认 true。
- `name` 取页面当前值，默认来自 `getNextSwitchName()`。
- `maxKeyCount = 8`。
- `eightKeyPanelType` 默认 `.scene8Key`，可由 Panel 选择变更。
- `panelType` 映射到 `DeviceSwitchData.PanelType`，Scene 8-key 对应 `.scenes_4key`，Brightness 8-key 对应 `.default_4key`。
- `bindGroupAddresses` 保存用户选择的 groups，默认空数组。
- `sceneANumber`、`sceneBNumber`、`sceneCNumber`、`sceneDNumber` 保存用户选择的 scenes，默认 nil。
- `moreSettingsState.ledIndicatorEnabled = true`，除非用户在 More Settings 中改动。
- `proxyNodeAddress = nil`。
- `linkGroupAddress = nil`。
- `subLinkGroupAddress = nil`。

同步状态采用 `syncState = .synced`。该本地虚拟 BPS 当前没有真实 node、没有虚拟 group，也没有可执行设备同步任务。标记为 pending 会让列表或后续逻辑误以为需要立即同步。后续绑定真实设备后，再创建虚拟 group、计算 desired config hash，并把同步状态切到 pending。

## 持久化

CREATE 成功时保存两处：

- `DeviceSwitchData.save()`：写入基础 `switchs` 表，让 Switches 列表能显示这条 switch。
- `PJEightKeySwitchRepository.shared.save(...)`：写入 `pjEightKeySwitchs` metadata，让列表能通过 repository 识别成 `PJEightKeySwitchData` 并使用 8-key / BPS cell。

保存成功后：

- 将数据追加到 `MeshNetworkManager.instance.switchs`。
- 发送 `switchsRefreshNotificationName`。
- 发送 `spaceDataChangedNotificaitonName`，object 沿用现有 `PJPreAddEightKeySwitchesVC` 保存路径的 `SpaceChangeDataType.common`。
- 显示现有成功提示并关闭页面。

保存失败时应显示错误提示并停留页面，避免用户点击 CREATE 后静默关闭。实现时只做最小增强，不重构现有 `persistSwitchData` 大范围行为。

## 后续绑定边界

本期只保证 pre-create 数据为后续绑定留下正确边界，不实现完整绑定新流程。

未绑定 BPS 的编辑页应继续显示 LINK：

- LINK 入口沿用 `PJPreAddEightKeySwitchesVC.linkAction()`。
- 编辑未绑定 BPS 时，`proxyNodeAddress == nil`，因此 LINK 可用。
- 绑定成功后才写入 `proxyNodeAddress`。
- 绑定成功后才创建或确认 `linkGroupAddress`。
- 虚拟 group 命名可继续沿用现有 `switchData.name + "-Group"`。
- 创建/确认虚拟 group 后再计算 Battery Power Switch desired config hash。
- 再根据 Key Config、TX Enable、LED Indicator、target group subscription 进入现有激活与 `SyncDevicesViewController(type: .batteryPowerSwitch(...))` 流程。

用户在 pre-create 阶段选择的 groups、scenes、panel/profile、More Settings 都作为目标配置保留，后续绑定真实设备后统一下发。

## 删除行为

未绑定 Battery Power Switch 删除时应走本地删除：

- 因为 `proxyNodeAddress == nil` 且 `linkGroupAddress == nil`，不需要进入设备同步。
- 删除应清理基础 `switchs` 记录。
- 删除应通过 `MeshNetworkManager.deleteSwitch(switchData:)` 或现有删除路径清理 `PJEightKeySwitchRepository` metadata。
- 删除后刷新 Switches 列表并发送现有数据变化通知。

## 错误处理

- switch 总数达到 16：阻止创建，显示现有 `switchs_overrun_message`。
- 名称为空：显示现有 `name_empty`。
- 名称重复：显示现有 `name_already_exists`。
- Group 默认空是合法状态。
- Scene 默认空是合法状态。
- 没有可用虚拟 group 地址不影响 pre-create，因为本期不分配虚拟 group。
- 本地保存失败：显示错误提示，不关闭页面。

## 测试计划

静态检查：

- `DevicesViewController.addAction` 中 Battery Power Switch 分支不再显示 `under_development`，而是打开 BPS pre-create 页面。
- BPS pre-create 模式默认值为 Name、Enable On、Scene Panel、Group N/A、Scene N/A、LED Indicator Enabled。
- CREATE 路径不调用 `ensureBatteryPowerSwitchLinkGroup`。
- CREATE 路径不进入 `SyncDevicesViewController`。
- CREATE 路径保存基础 switch 表和 `PJEightKeySwitchRepository` metadata。
- 新增数据满足 `proxyNodeAddress == nil`、`linkGroupAddress == nil`、`syncState == .synced`。

手动 QA：

- 从 Space 添加入口选择 Switches，再选择 Battery Power Switch，页面展示与 Figma 主体一致。
- 进入页面后默认值符合需求。
- 可选择 Panel/Profile、Group、Scene、More Settings。
- 点击 CREATE 后 Switches 列表新增 8-key / Battery Power Switch cell。
- 点击新增 cell 能进入详情或编辑，不崩溃。
- 编辑未绑定 BPS 时 LINK 可见。
- 删除未绑定 BPS 只走本地删除，不进入无意义同步。

构建验证：

- 直接执行项目推荐命令：`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。

## 影响范围

预计修改集中在：

- `SunSmart/Main/Device/Controller/DevicesViewController.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/ViewModel/PJPreAddEightKeySwitchesViewModel.swift`
- `SunSmart/Main/Device/Device1.5/NEightKeySwitches/Controller/PJPreAddEightKeySwitchesVC.swift`
- 必要时小范围调整 `PJEightKeySwitchEditorView` 或 `DeviceBottomActionView` 以贴近 Figma create UI。

不需要修改本地化资源、品牌 target 资源、依赖或 target 配置。若实现时发现需要新增/修改本地化 key，应同步检查所有相关 target 的资源引用。
