# Site Space Group Switch 页面优化设计

## 背景

当前 Site - Space - Group 右上角菜单中的 `Switch` 入口会直接进入 `GroupSwitchsViewController`。该页面本质上是 Group 视角的 Kinetic Switch 编辑页，支持普通 `DeviceSwitchData` 的 group、scene、proxy、panel 与保存/删除流程。

项目中 Battery Power Switch 与 AC Power Switch 已统一使用 `PJEightKeySwitchData` 承载，并通过 `powerSwitchKind` 区分 `.battery` 与 `.ac`。两类 Power Switch 已有独立的 8-key 面板、更多设置、激活等待、TX Enable、同步与虚拟设备逻辑。因此本需求不应新增设备族，而应新增一个 Group-scoped Power Switch 页面，把现有 Power Switch 能力接入 Group 局部编辑场景。

Figma 参考：

- Switch 类型选择弹窗：`80:5170`
- Battery Power Switch 默认收起列表：`81:6216`
- Battery Power Switch 展开编辑列表：`81:5902`

## 已确认规则

- Battery/AC 的 Group Switch 展开页不允许修改 switch name，只展示名称。
- Battery/AC 的 Group Switch 展开页允许修改 Panel、Scene、More Settings，并支持 Enable、Delete、Save。
- Scene 行保留，仅在 Scene Panel 类型下显示并可编辑；Brightness Panel 下隐藏。
- AC Power Switch 页底部 `ADD VIRTUAL SWITCH` 创建 AC 虚拟 switch，默认 Scene Panel，并把 target group 设置为当前 group。
- Battery/AC 新增 virtual switch 之后，新增的 switch 默认展开。
- 已有列表进入页面时，Battery/AC switch 默认全部收起。

## 目标

- Group 菜单点击 `Switch` 后先展示三类型弹窗：Kinetic Switch、Battery Power Switch、AC Power Switch。
- Kinetic Switch 进入现有 Group switch 页面，但标题改为 `Kinetic Switch`，并过滤出当前 group 内的普通 Kinetic Switch。
- Battery Power Switch 进入新的 Group-scoped Battery Power Switch 页面。
- AC Power Switch 进入新的 Group-scoped AC Power Switch 页面。
- Battery/AC 页面只展示 target group 包含当前 group 的对应类型 switch。
- Battery/AC 页面支持折叠/展开 cell，折叠与展开状态均显示 Enable toggle。
- Battery/AC Enable toggle 独立于 SAVE 流程：
  - 虚拟设备直接本地保存。
  - 真实 Battery 展示 `Save After Activation` 后发送 TX Enable。
  - 真实 AC 不等待激活，直接发送 TX Enable 或进入后续同步流程。
- Battery/AC SAVE 只处理 Panel、Scene、More Settings 变更，不处理 enabled 变更。
- Battery/AC Delete 只从当前 group 移除该 switch，不删除全局 switch。
- 三种 switch 共用 16 个总数上限。
- 所有 switch 页面底部按钮文案改为 `ADD VIRTUAL SWITCH`。

## 非目标

- 不改全局 Switches 页的设备列表与监控页入口。
- 不新增 Power Switch 数据模型。
- 不改变 Battery/AC 的 PID、设备族识别、link 真实设备流程。
- 不在 Group Power Switch 页面提供 name 编辑、LINK/UNLINK 或真实设备信息页入口。
- 不改变 Mesh 协议和 NordicSigMeshSDK。
- 不做无关 UI 重构。

## 推荐方案

采用新增 `GroupPowerSwitchesViewController` 的方案。该控制器只负责 Group-scoped Battery/AC Power Switch 列表与局部编辑，底层复用现有 Power Switch 的模型、组件和同步能力。

该方案边界清晰：

- Group 入口和列表状态由新页面承载。
- 设备数据仍来自 `MeshNetworkManager.instance.switchs`。
- Power Switch 业务仍使用 `PJEightKeySwitchData`、`PJEightKeySwitchRepository` 和现有同步 controller。
- Delete 在新页面内解释为“移除当前 target group”，不会误用全局删除设备语义。
- Enable 独立流程不会污染现有 SAVE snapshot。

不采用把 `PJPreAddEightKeySwitchesVC` 参数化成 Group 模式的方案，因为该页面是全局创建/编辑 switch 页面，包含 name、group 可变、LINK、完整 delete 等语义。强行复用会产生大量 group-mode 分支，并增加全局 Switch 编辑页回归风险。

不采用继续扩展 `GroupSwitchsViewController` 承载三类 switch 的方案，因为该文件当前围绕 Kinetic Switch 同步和 proxy 语义组织；Battery/AC 的 8-key own config、activation、TX Enable、more settings 与 panel preview 差异较大，混入后会让职责继续膨胀。

## 入口与导航

`GroupViewController.pushToSwitch()` 改为展示已有 `PJSwitchesTypesVC.makePopupViewController(...)`。

弹窗分流：

- `Kinetic Switch`：push `GroupSwitchsViewController(group:)`。
- `Battery Power Switch`：push `GroupPowerSwitchesViewController(group: group, kind: .battery)`。
- `AC Power Switch`：push `GroupPowerSwitchesViewController(group: group, kind: .ac)`。

弹窗视觉复用现有 `PJSwitchesTypesVC`，其当前三项布局已与 Figma 的选择弹窗一致。

Kinetic 页标题改为 `Kinetic Switch`。Battery 页标题为 `Battery Power Switch`。AC 页标题为 `AC Power Switch`。

## 数据过滤

Kinetic 页继续使用 `GroupSwitchsViewController`，但数据源应过滤：

- `bindGroupAddresses` 包含当前 group address。
- 不是 `PJEightKeySwitchData`。
- 不能通过 `PJEightKeySwitchRepository.shared.makeEightKeySwitch(from:)` 转换为 Power Switch。

Battery/AC 页从 `MeshNetworkManager.instance.switchs` 过滤：

- 当前 switch 可转换为 `PJEightKeySwitchData`。
- `powerSwitchKind` 等于当前页面 kind。
- `bindGroupAddresses` 包含当前 group address。

列表按 `MeshNetworkManager.instance.switchs` 当前顺序展示。新增虚拟 switch 保存到全局数组后，页面插入该 switch 并默认展开。

## Battery/AC 列表 UI

默认进入 Battery/AC 页面时，所有已有 switch 均为收起状态。

折叠 cell：

- 第一行展示 switch name，单行截断。
- 第二行展示真实设备 MAC；未绑定真实 node 时展示 `Not linked to switch`。
- 右侧始终显示 Enable toggle。
- 右侧显示展开箭头。
- 点击 toggle 只触发 Enable 流程；点击其它区域切换展开/收起。

展开 cell：

- 顶部仍展示 name、MAC/Not linked、Enable toggle 与收起箭头。
- `Panel` 行可点击，进入 `PJEightKeySwitchSelectPanelController`。
- `Group` 行可点击，进入只读 group 列表；不允许修改 target groups。
- `Scene` 行仅在 Scene Panel 类型下显示，点击进入 `SwitchSelectScenePageController`。
- `More Settings` 行进入 `PJEightKeySwitchMoreSettingsController`。
- Panel preview 复用 `PJEightKeySwitchPanelView`，根据 panel type 和 scene 配置实时刷新。
- Delete 与 Save 图标按钮展示在 panel preview 下方。
- SAVE 无变更时禁用；有变更时启用。

## Enable 流程

Enable toggle 独立于 SAVE，不写入 SAVE snapshot。

虚拟 Battery/AC：

1. 用户切换 toggle。
2. 更新 `switchData.enabled`。
3. 保存 base switch 与 `PJEightKeySwitchRepository` metadata。
4. 更新内存数组。
5. 刷新当前 cell，并发送 `switchsRefreshNotificationName` 与 `spaceDataChangedNotificaitonName`。

真实 Battery：

1. 用户切换 toggle。
2. 页面进入 pending 状态，防止重复点击。
3. 展示 `Save After Activation`，复用 `PJEightKeySwitchTxEnableFlow`。
4. 成功后调用 `markBatteryPowerSwitchTxEnableSucceeded()`，保存并刷新。
5. 取消或失败时恢复原 toggle 值。

真实 AC：

1. 用户切换 toggle。
2. 页面进入 pending 状态。
3. 不展示激活等待，直接发送 TX Enable 或进入现有 AC 直发流程。
4. 成功后保存并刷新。
5. 失败时恢复原 toggle 值。

## SAVE 流程

SAVE snapshot 只包含：

- Panel type。
- Scene 1-4，仅 Scene Panel 类型参与。
- More Settings。

SAVE snapshot 不包含：

- Name。
- Target groups。
- Enabled。

无变更时 SAVE 禁用。

虚拟 Battery/AC：

1. 用户点击 SAVE。
2. 更新 `PJEightKeySwitchData` 的 panel、scene、more settings。
3. 保存 base switch 与 metadata。
4. 更新内存数组和当前 cell。
5. 刷新 snapshot，SAVE 重新禁用。

真实 Battery：

1. 用户点击 SAVE。
2. 计算是否需要 own configuration sync、LED Indicator sync 或 target sync。
3. 如需 own configuration sync，准备 desired hash/config。
4. 需要下发时展示 `Save After Activation`。
5. 激活后进入 `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`。
6. 成功后标记 sync succeeded，保存数据并刷新。
7. 用户退出同步页或失败时，恢复进入编辑前的 Panel、Scene、More Settings 状态。

真实 AC：

1. 用户点击 SAVE。
2. 计算同步需求。
3. 不展示激活等待，直接进入同步流程。
4. 成功后保存并刷新。
5. 用户退出同步页或失败时，恢复进入编辑前状态。

如果变更只影响本地 metadata，且不需要下发，则直接保存。

## Delete 流程

Delete 在 Battery/AC Group 页面中的语义是“从当前 group 移除该 switch”，不是删除 switch 设备。

虚拟 Battery/AC：

1. 用户点击 Delete。
2. 从 `bindGroupAddresses` 移除当前 group address。
3. 清理同 group 的 pending `unbindGroupAddresses`，避免虚拟设备产生不必要待同步状态。
4. 保存 base switch 与 metadata。
5. 从当前列表移除该 cell。
6. 发送刷新通知。

真实 Battery：

1. 用户点击 Delete。
2. 弹确认框。
3. 确认后从 `bindGroupAddresses` 移除当前 group，并把当前 group 加入 `unbindGroupAddresses`。
4. 展示 `Save After Activation`。
5. 激活后进入 `SyncDevicesViewController(type: .batteryPowerSwitch(switchData))`，执行 target group 退订。
6. 成功后从当前列表移除。
7. 取消、退出或失败时恢复原 bind group 状态，列表仍展示该设备。

真实 AC：

1. 用户点击 Delete。
2. 弹确认框。
3. 确认后从 `bindGroupAddresses` 移除当前 group，并加入 `unbindGroupAddresses`。
4. 不展示激活等待，直接进入同步流程。
5. 成功后从当前列表移除。
6. 取消、退出或失败时恢复原 bind group 状态。

## ADD VIRTUAL SWITCH

新增本地化 key 表示 `ADD VIRTUAL SWITCH`，避免直接修改 `add_switch` 影响其它入口。

Kinetic 页：

- 保持当前 `GroupSwitchsViewController.addVirtualSwitch()` 行为。
- 创建普通 `DeviceSwitchData.default()`。
- 自动把当前 group address 写入 `bindGroupAddresses`。
- 保存后插入列表并默认展开。

Battery 页：

- 检查 `MeshNetworkManager.instance.switchs.count < 16`。
- 创建 `PJEightKeySwitchData`。
- `powerSwitchKind = .battery`。
- 默认 `Scene Panel (8 key)`。
- `bindGroupAddresses = [currentGroup.address.address]`。
- 未绑定真实 node。
- `syncState = .synced`，desired/applied hash 清空。
- 保存 base switch 与 metadata。
- 插入当前列表并默认展开。

AC 页：

- 与 Battery 相同，但 `powerSwitchKind = .ac`。
- 默认 Scene Panel。
- 纯虚拟本地保存，不等待设备激活。
- 插入当前列表并默认展开。

上限规则：

- Kinetic、Battery、AC 三类一起统计 16 个上限。
- 超限提示沿用 `switchs_overrun_message`。
- Group-scoped Delete 只是解除当前 group，不减少全局 switch 总数。

## 权限与错误处理

- 无编辑权限时，禁止 Enable、Panel、Scene、More Settings、Delete、Save、Add Virtual，并提示 `no_permission`。
- switch 总数达到 16 时，阻止 Add Virtual 并提示 `switchs_overrun_message`。
- 真实 Power Switch 保存或同步前如果需要 link group 但组地址不足，提示 `group_address_insufficient_message`。
- 真实设备需要下发但 mesh 未连接时，提示 `device_notconnect_message`。
- 虚拟设备本地保存不依赖 mesh 连接。
- 同步失败时保持原有 sync state 和失败提示，本次未保存变更恢复到进入编辑前状态。
- 列表为空时使用当前页面空态风格，标题按页面类型区分。
- MAC 无法取得时降级展示 `Not linked to switch`，避免空白副标题。

## 影响范围

预计涉及：

- `SunSmart/Main/Group/Controller/GroupViewController.swift`
  - `Switch` 菜单入口改为展示三类型选择弹窗。

- `SunSmart/Main/Group/Switch/Controller/GroupSwitchsViewController.swift`
  - 标题改为 Kinetic Switch。
  - 数据过滤为当前 group 内普通 Kinetic Switch。
  - 底部按钮文案改为 `ADD VIRTUAL SWITCH`。

- 新增 Group Power Switch 页面相关文件：
  - `GroupPowerSwitchesViewController`
  - Group Power Switch cell/view model 或等价小组件。

- 复用或小范围抽取：
  - `PJEightKeySwitchPanelView`
  - `PJEightKeySwitchSelectPanelController`
  - `PJEightKeySwitchMoreSettingsController`
  - `SwitchSelectScenePageController`
  - `PJDeviceGroupSelectionViewController`
  - `PJEightKeySwitchTxEnableFlow`
  - `PJEightKeySwitchActivationFlow`
  - `SyncDevicesViewController(type: .batteryPowerSwitch)`

- 本地化：
  - 新增或复用 `ADD VIRTUAL SWITCH`。
  - 新增或复用 `Not linked to switch`。
  - 修改中英文 strings 后需检查共享 target 影响。

## 验证计划

手动功能验证：

- Group 菜单点击 `Switch` 后展示三类型弹窗。
- 弹窗 Back/关闭行为正常。
- Kinetic 只显示当前 group 的普通 Kinetic Switch。
- Kinetic `ADD VIRTUAL SWITCH` 创建并绑定当前 group，新增后默认展开。
- Battery 只显示当前 group 的 Battery Power Switch。
- Battery `ADD VIRTUAL SWITCH` 创建 Battery 虚拟 switch，新增后默认展开。
- AC 只显示当前 group 的 AC Power Switch。
- AC `ADD VIRTUAL SWITCH` 创建 AC 虚拟 switch，新增后默认展开。
- 已有 Battery/AC 列表进入页面时默认全部收起。
- 折叠 cell 显示 name、Enable toggle、MAC 或 Not linked。
- 展开 cell 中 Panel、Scene、More Settings 可编辑，Group 只读。
- Scene Panel 显示 Scene 行，Brightness Panel 隐藏 Scene 行。
- SAVE 无变更禁用，有变更启用。
- 虚拟 Battery/AC Enable 直接保存。
- 真实 Battery Enable/SAVE 展示激活等待。
- 真实 AC Enable/SAVE 不展示激活等待。
- Battery/AC Delete 后当前页不再显示该 switch，但全局 Switches 页仍保留该设备。
- 三类 switch 总数达到 16 时禁止新增。

静态检查：

- Enable 状态不参与 Group Power Switch SAVE snapshot。
- Group scoped Delete 不调用全局 delete switch 流程。
- AC 分支不进入 activation flow。
- Battery 分支继续使用 activation flow。
- Kinetic 过滤不会显示 Battery/AC Power Switch。

构建验证：

```bash
xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

如果本地化、资源或 target 配置变更影响共享资源，需要同步检查 `Archipelago`、`SLG Sync Plus`、`SylSmart` 相关 target。

## 风险

- Group scoped Delete 与全局 Delete 语义不同，必须避免复用全局删除 action。
- Enable 与 SAVE 都可能触发 Power Switch 同步，必须通过 pending 状态防止重复下发。
- 真实 Battery 的取消/失败恢复需要保存进入编辑前 snapshot，避免半保存状态。
- 本地化 key 若直接复用 `add_switch` 可能影响其它页面，因此应新增专用 key。
