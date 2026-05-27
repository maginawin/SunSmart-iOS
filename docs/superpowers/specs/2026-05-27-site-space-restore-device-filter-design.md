# Site 与 Space 恢复设备入口过滤设计

## 背景

当前 `DeviceRestoreViewController` 是通用恢复设备页面，被 Site 右上角菜单、Space 内添加设备弹窗、固件升级后的指定恢复等多个入口复用。现有 Site 入口会展示所有可恢复设备；Space 入口已有 `space != nil` 时排除 gateway 的扫描判断，但过滤规则分散在扫描流程里，缺少显式入口语义。

本次优化需要让不同入口展示不同设备范围：

- Site 右上角进入恢复设备数据后，只展示和恢复 gateway 设备。
- Site - Space 添加设备弹窗进入恢复设备数据后，只展示当前 space 中的非 gateway 设备。
- 其他恢复入口保持原行为。

## 目标

1. Site 右上角 `Restore Device` 页面仅展示 `node.deviceType == .gateway` 的设备。
2. Space 添加设备弹窗的 `Restore Device` 页面仅展示当前 `space` 内、且 `node.deviceType != .gateway` 的设备。
3. 过滤规则由入口显式传入，避免影响固件升级指定恢复、其他设备页恢复、自动恢复等流程。
4. 过滤逻辑集中在恢复页统一入口，避免扫描数据和指定数据两套路径行为不一致。

## 非目标

- 不修改恢复设备的配网、同步、deferred restore、battery power switch、gateway 云同步等业务流程。
- 不新增 UI 文案或本地化资源。
- 不调整设备类型识别逻辑，继续使用现有 `Node.DeviceType`。
- 不重构 `DeviceRestoreViewController` 的恢复主流程。

## 推荐方案

在 `DeviceRestoreViewController` 增加可选的恢复设备过滤策略。策略默认不过滤，入口按需要传入：

- Site 右上角入口传入 `.gatewaysOnly`。
- Space 添加设备弹窗入口传入 `.currentSpaceNonGateways`。
- 其他入口继续使用默认策略。

`RestoreMode` 继续只表达数据来源：`.default` 表示扫描恢复，`.specified(nodes:)` 表示指定节点恢复。设备类型和 space 归属过滤由独立策略负责，避免 `RestoreMode` 同时承担两类职责。

## 过滤规则

### Site 右上角入口

允许条件：

- `node.deviceType == .gateway`

不额外按 `space` 过滤。恢复成功后的 gateway 云同步流程保持现状，由 `SiteViewController.restoreDevice()` 的 `deviceRestoreCallback` 使用 `GatewayModel.resolve(node:)` 后调用 `gatewaysSyncToCloud`。

### Space 添加设备弹窗入口

允许条件：

- `node.deviceType != .gateway`
- `node.subNetworkId == space.meshNetworkId`

该入口只展示当前 space 的恢复对象。gateway 设备即使属于 site，也不在 space 入口展示或恢复。

### 默认入口

未传过滤策略时保持现有行为。固件升级指定恢复和其他复用入口不新增限制。

## 数据流

1. 入口创建 `DeviceRestoreViewController` 时传入 `restoreMode` 和过滤策略。
2. 恢复页开始扫描前调用 `setupDataSource()`：
   - `.default` 清空列表。
   - `.specified(nodes:)` 先排除已恢复节点，再应用过滤策略，最后按 `node.group` 组装 section。
3. `MeshAPI.startScanRecoverDevices` 回调返回 `unprovisionedDevice` 和旧 `node` 后：
   - 先检查 RSSI 下限。
   - 再应用恢复过滤策略。
   - 不通过的设备不进入 `sections` 或 `showSections`。
4. RSSI slider 只在已通过入口策略的设备中继续筛选展示，不承担设备类型或 space 归属判断。
5. 添加/恢复成功后继续走现有 `addDevice(_:)`、同步消息、回调和 UI 状态更新。

## 组件边界

### DeviceRestoreViewController

新增一个小型过滤策略类型，并提供内部判断函数，例如 `shouldIncludeRestoreNode(_:)`。该函数只依赖：

- `node.deviceType`
- `node.subNetworkId`
- 当前 `space?.meshNetworkId`
- 入口传入的过滤策略

恢复页内部所有新增或预置设备进入列表前都调用这个判断。

### SiteViewController

`restoreDevice()` 创建恢复页时传入 gateway-only 策略。回调逻辑不变。

### DevicesViewController

Space 内添加设备弹窗的 `devicesRestore()` 创建恢复页时传入 current-space non-gateway 策略。恢复成功后的 `devicesAddNotificationName` 通知逻辑不变。

## 错误处理与空态

- 如果过滤后没有设备，继续使用现有 `device_restore_empty_message`。
- 如果扫描过程中发现非目标类型设备，静默忽略，不弹错误。
- 如果 `space` 为空但入口传入 current-space 策略，则该策略不允许任何设备通过，以避免错误展示跨入口数据。正常代码路径不会触发此情况。

## 测试计划

1. 静态检查：
   - 确认 Site 入口传入 `.gatewaysOnly`。
   - 确认 Space 添加设备弹窗入口传入 `.currentSpaceNonGateways`。
   - 确认其他入口仍使用默认策略。
2. 手动或模拟验证：
   - Site 右上角恢复页扫描到 gateway 和非 gateway 时，只展示 gateway。
   - Space 添加设备弹窗恢复页扫描到 gateway、当前 space 非 gateway、其他 space 非 gateway 时，只展示当前 space 非 gateway。
   - 固件升级指定恢复仍能展示传入的指定设备，不受 Site/Space 菜单过滤影响。
3. 构建验证：
   - 使用项目约定的 `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`。

## 风险与缓解

- 风险：`node.subNetworkId` 数据缺失会导致 Space 入口过滤掉本应展示的设备。
  缓解：当前导入流程会给节点写入 `subNetworkId`；新增逻辑只用于 Space 入口，并以 `space.meshNetworkId` 为显式边界，避免展示其他 space 设备。

- 风险：过滤只加在扫描路径，未来指定恢复路径漏过滤。
  缓解：在 `setupDataSource()` 和扫描回调两处统一调用同一个判断函数。

- 风险：修改通用恢复页影响其他入口。
  缓解：过滤策略默认不过滤，只有 Site 和 Space 两个明确入口传入限制。

## 自检结论

- 无未决项或占位符。
- Site 与 Space 两个入口规则互不冲突。
- 范围聚焦在恢复页列表过滤，不改恢复执行流程。
- `gateway` 判断明确为 `node.deviceType == .gateway`，Space 归属判断明确为 `node.subNetworkId == space.meshNetworkId`。
