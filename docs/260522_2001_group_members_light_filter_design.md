# Group Members 设备过滤修复设计

## 背景

当前问题出现在 `Site - Space - Group - Members` 页面：Members 中展示了一个早已删除的 `0x2A01` 开关设备，但该设备不在 `Space - Switches` 分类中。

现有代码中，`GroupMembersViewController` 的数据源来自 `MeshNetworkManager.instance.realNodes`，当前只排除 `.gateway` 和 `.emergencyController`，其余设备类型都会进入候选列表。`Space - Switches` 的数据源是 `MeshNetworkManager.instance.switchs`，与 Members 的 `realNodes` 不是同一条数据链路。因此，某个开关缓存从 `switchs` 删除后，仍可能作为 Mesh node 留在 `realNodes` 中，并通过 group subscription 出现在 Members。

## 当前过滤链路

### Group - Members

入口：`GroupMembersViewController.viewWillAppear`

当前过滤逻辑：

- 从 `MeshNetworkManager.instance.realNodes` 读取所有真实节点。
- 通过 `isVisibleGroupMemberNode(_:)` 排除 `.gateway`、`.emergencyController`。
- 保留未加入任何组的节点，或已经属于当前 group 的节点。
- `selectNodes` 根据 `node.group != nil` 计算选中状态。

问题点：

- `.switches`、`.sensor`、`.dongle`、`.unknown` 当前都可能进入 Members。
- `node.group` 来自 node model subscriptions，只要节点仍订阅普通 group，就可能被视为该组成员。

### Space - Main - Lights

入口：`DeviceLightsViewController.loadDevices`

当前过滤逻辑：

- 从 `MeshNetworkManager.instance.realNodes` 读取真实节点。
- 只保留 `node.deviceType == .light` 的节点。

### Space - Switches

入口：`DeviceSwitchesViewController`

当前过滤逻辑：

- 直接展示 `MeshNetworkManager.instance.switchs`。
- 该列表来自 `DeviceSwitchData` 缓存，不等同于 Mesh node 列表。

## 修复目标

`Group - Members` 中仅展示能在 `Space - Main - Lights` 分类下展示的设备。

具体规则：

- Members 候选设备必须满足 `node.deviceType == .light`。
- 保留原有组关系过滤：只展示未加入任何组的节点，或已经属于当前 group 的节点。
- 不调整 `Space - Main - Lights`、`Space - Switches`、`GroupViewController` 组详情网格的数据源。
- 不在本次修复中清理历史 Mesh node、修复 `0x2A01` 的设备配置、或改变 `DeviceSwitchData` 删除流程。

## 推荐设计

在 `GroupMembersViewController.isVisibleGroupMemberNode(_:)` 中改为只允许 `.light`：

- `.light` 返回 `true`。
- 其它所有 `Node.DeviceType` 返回 `false`。

这样 Members 与 `Space - Main - Lights` 共享同一设备类型口径，并继续复用现有 `viewWillAppear` 中的 group membership 条件。

## 方案可信度

该方案可信，原因是它与现有 Lights 分类的实现保持一致，改动点也集中在 Members 页面展示过滤，不影响设备删除、开关列表、组同步或 Mesh SDK。

但它解决的是页面口径一致性，不是历史数据清理。如果某个历史节点由于设备配置缺失而被 `Node.deviceType` 默认识别为 `.light`，它仍会同时出现在 Lights 和 Members。本次按已确认范围不处理该类数据清理问题。

## 测试计划

1. 静态检查 `GroupMembersViewController` 过滤逻辑，确认 Members 只允许 `.light`。
2. 运行 iOS 编译：
   `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
3. 手工回归：
   - 进入 `Space - Main - Lights`，记录展示设备。
   - 进入某个 `Group - Members`。
   - 确认 Members 候选设备只来自 Lights 分类。
   - 确认未入组灯可添加，当前组内灯保持选中。
   - 确认已删除的 Switches 缓存设备不再因 `.switches` 类型出现在 Members。

## 不在本次范围

- 不修改 `Node.deviceType` 的默认 `.light` 行为。
- 不新增历史脏数据清理。
- 不调整 `GroupViewController` 的已有成员展示。
- 不修改 `DeviceSwitchData` 删除链路。
