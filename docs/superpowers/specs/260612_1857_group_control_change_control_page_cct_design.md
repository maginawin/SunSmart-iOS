# Group Control Change Control Page CCT 显示设计

## 背景

`Site - Space - More Settings - Device Parameter Settings - Change Control Page` 当前提供两个 CCT 设备控制页语义：

- `Single White`：单设备控制页不展示色温控制。
- `Tunable White`：单设备控制页展示色温控制。

当前单设备控制页表现符合预期，但 Group control page 不符合新的业务预期。Group control page 需要从组内设备能力集合中判断是否展示色温控件，并且只把真实 CCT 设备中选择 `Tunable White` 的设备计入 Group 控制页的色温展示集合。

## 当前代码事实

- SDK 中 `Node.rawSupportCct` 表示设备真实 Mesh CCT 能力，当前实现为 `temperatureModel != nil`。
- SDK 中 `Node.effectiveSupportCct` 当前等同于 `rawSupportCct`，不受 `changeControlPage` 影响。
- SDK 中 `Node.singleDeviceDisplaySupportCct` 为 `rawSupportCct && effectiveChangeControlPage != .singleWhite`。
- `DeviceLightViewController.updateControlPanel()` 使用 `node.singleDeviceDisplaySupportCct` 设置 `showsCCT`，所以单设备控制页会受 `Change Control Page` 影响。
- `GroupViewController.updateControlPanel()` 使用 `group.effectiveSupportCct` 设置 `showsCCT`，所以只要组内存在真实 CCT 设备，Group 页就会展示色温控件，即使这些 CCT 设备都选择了 `Single White`。
- `GroupViewController` 是多个入口复用的 group control page，包括 Group 列表、Scene 页面和部分设备监控入口跳转到组详情时都会进入同一个控制器。
- 6 月 1 日已有设计将 Scene、Profile、批量控制等跨设备或自动化入口定义为继续使用真实 CCT 能力，不受 `Single White` 影响。本轮设计不覆盖这些入口。

## 问题判断

问题属实。

当前 Group control page 仍按真实 CCT 能力展示色温控件，没有按组内 CCT 设备的 `Change Control Page` 合集判断：

- 组内有真实 CCT 设备但全部为 `Single White` 时，当前仍展示色温控件。
- 组内有任一真实 CCT 设备为 `Tunable White` 时，当前展示色温控件，这个结果符合预期。
- 组内没有真实 CCT 设备时，当前不展示色温控件，这个结果符合预期。

## 目标

- Group control page 使用独立的 Group 控制页 CCT 显示集合判断色温控件。
- 若组内任一真实 CCT 设备选择 `Tunable White`，展示色温 slider、quick buttons 和 detailed CCT 输入入口。
- 若组内真实 CCT 设备全部选择 `Single White`，隐藏色温控件。
- 若组内没有真实 CCT 设备，隐藏色温控件。
- 所有进入同一个 `GroupViewController` 的入口保持一致。
- 保持单设备控制页当前行为不变。
- 保持 Scene、Profile、批量设备控制等非 Group control page 入口当前跨设备 CCT 语义不变。

## 非目标

- 不修改 SDK 中 `Node.effectiveSupportCct` 的语义。
- 不修改 `Group.effectiveSupportCct` 的全局语义。
- 不修改 Scene 创建、Scene 设置、Scene 执行、Profile、同步判断或批量控制入口的 CCT 能力判断。
- 不修改 `Device Parameter Settings` 的 UI、保存、导入导出或云同步逻辑。
- 不新增数据库字段、云端字段或 Auth 信息。
- 不调整 Group 页布局、quick buttons 样式、Simple/Detailed 控件样式或本地化文案。

## 方案选择

采用方案 A：只在 `GroupViewController` 中增加 Group control page 专用的 CCT 显示能力判断。

备选方案不采用：

- 修改 `Group.effectiveSupportCct`：会影响所有依赖 Group CCT 能力的入口，包括 Scene/Profile，范围过大。
- 修改 SDK `Node.effectiveSupportCct`：会回滚 6 月 1 日的能力拆分语义，影响最大。

## 设计

在 `GroupViewController` 中定义 Group control page 专用 CCT 节点集合，语义为：

真实支持 CCT 且 `effectiveChangeControlPage == .tunableWhite` 的组内设备。

后续 Group control page 的 CCT 展示和交互都基于这组节点，而不是直接使用 `group.effectiveSupportCct`：

- `showsGroupControlPanel`：亮度能力仍使用 `group.supportLightness`；CCT 能力改为判断 Group control page 专用 CCT 节点集合是否为空。
- `updateControlPanel()`：`showsCCT` 改为使用 Group control page 专用 CCT 节点集合判断。
- `currentGroupCCTRange`：改为使用 Group control page 专用 CCT 节点集合的 `effectiveCctRange` 并集；集合为空时保留默认范围作为兜底，避免隐藏状态下读取 range 崩溃或异常。
- `applyGroupCCTValue(_:)`：只更新 Group control page 专用 CCT 节点集合的本地 `temperature`。
- `showGroupCCTLimitMessageIfNeeded(target:)`：只检查 Group control page 专用 CCT 节点集合的 range。

Group CCT 命令仍沿用当前行为，通过 `MeshAPI.setGroupColorTemperatureState(address:temperature:)` 发送到 group address。原因是本轮目标是修复 Group control page 的显示与本地状态判断，不改变 Mesh group address 控制语义。

## 数据流

1. 用户在 Device Parameter Settings 中设置某个真实 CCT 设备的 `Change Control Page`。
2. 保存逻辑继续写入 `node.changeControlPage`，并走现有本地保存和空间同步链路。
3. 单设备控制页继续读取 `node.singleDeviceDisplaySupportCct`。
4. Group control page 进入或刷新时，从 `group.nodes` 计算 Group control page 专用 CCT 节点集合。
5. Group control page 根据该集合决定是否展示 CCT 控件，并根据该集合计算 CCT range、更新本地 temperature 和提示 range limit。

## 影响范围

直接影响：

- `GroupViewController` 内的 Group control page CCT 显示、CCT range、本地状态更新和 range limit 提示。

通过同一个控制器间接受影响：

- Group 列表进入组详情。
- Scene 页面进入组详情。
- 其他跳转到 `GroupViewController(space:group:)` 的监控或设备入口。

不受影响：

- 单设备控制页。
- 设备列表 Cell、Header、设备详情、DALI 单设备页。
- Scene 创建、Scene 设置、Scene 执行。
- Profile。
- 批量设备控制。
- Device Parameter Settings。

## 验收标准

- 组内无真实 CCT 设备时，Group control page 不展示色温控件。
- 组内有真实 CCT 设备但全部为 `Single White` 时，Group control page 不展示色温控件。
- 组内有任一真实 CCT 设备为 `Tunable White` 时，Group control page 展示色温控件。
- 混合组中 `Single White` CCT 设备不参与 Group control page 的 CCT range 并集、本地 temperature 更新和 range limit 提示。
- 混合组中 `Tunable White` CCT 设备参与 Group control page 的 CCT range 并集、本地 temperature 更新和 range limit 提示。
- Group 页亮度控制、On/Off、Auto、Emergency block、Simple/Detailed 和 CCT quick buttons 既有行为不变。
- Scene/Profile/批量控制仍按当前真实 CCT 能力语义运行，不跟随本轮 Group control page 显示规则。
- iPhoneOS 构建通过：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 实现风险

- `GroupViewController` 中 CCT 显示、range、本地状态更新和提示需要使用同一组专用节点集合，避免只修显示但交互仍按真实 CCT 设备处理。
- 如果后续业务要求 Scene/Profile/批量控制也跟随 `Change Control Page` 合集语义，需要另起设计，因为这会改变 6 月 1 日确认过的跨设备能力规则。
- Group address CCT 命令仍会发送到 group address，本轮不改变底层 Mesh 广播语义；本地 UI 状态只按 `Tunable White` CCT 设备更新。

## 后续计划入口

用户确认本规格后，下一步使用 `superpowers:writing-plans` 编写实现计划。按当前项目偏好，默认使用 Inline Execution 在当前会话执行，不使用 subagents。
