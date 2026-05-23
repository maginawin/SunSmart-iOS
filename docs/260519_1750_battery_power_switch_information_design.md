# Battery Power Switch Information 页面设计

## 背景

`PJEightKeySwitchMonitorVC` 右上角菜单当前已有 `Information` 入口占位，但尚未实现跳转。Battery Power Switch 的 Information 页面样式需要与 light 类型设备的 information 保持一致，内容按 Battery Power Switch 的业务语义展示。

本次设计只覆盖从 `PJEightKeySwitchMonitorVC` 右上角菜单进入 Information 页面，不进入实现。

## 已确认语义

Battery Power Switch 本身是一个 Mesh node，不需要额外 proxy node。当前实现中为了复用 `DeviceSwitchData` / EnOcean Switch 数据结构，Battery Power Switch 创建开关数据时会把自身 `Node.primaryUnicastAddress` 写入 `switchData.proxyNodeAddress`。因此对 Battery Power Switch 来说，`switchData.proxyNode` 实际解析到的是 Battery Power Switch 自己。

`enOceanMacAddress` 是沿用 EnOcean Switch 数据结构产生的字段名，不作为 Battery Power Switch Information 页的 MAC 数据源。Information 页展示真实 Battery Power Switch 自身的 mesh node information，MAC 使用 `node.macAddressResult`。

虚拟 Battery Power Switch 不展示 Information 选项。虚拟设备短按和长按都进入 Edit 页面，只有真实 Battery Power Switch 才有机会从右上角菜单点击 Information。

## 目标

1. 真实 Battery Power Switch 的右上角菜单展示 `Information`。
2. 虚拟 Battery Power Switch 的右上角菜单不展示 `Information`。
3. 点击 `Information` 后进入与 light information 样式一致的信息页。
4. Device 区展示 Battery Power Switch 自身 mesh node 信息。
5. Group 和 Scene 展示口径与 Edit 页一致，使用摘要文本。
6. 不改变普通 light information 和 FireAlarm information 的既有展示。

## 非目标

- 不新增虚拟 Battery Power Switch 的 Information 页面。
- 不改变 Battery Power Switch 的同步、配置、Profile 保存流程。
- 不调整 `proxyNodeAddress` 字段命名或数据库结构。
- 不重构普通 light information 页面。
- 不新增独立 Battery Power Switch 详情信息表样式。

## 方案选择

采用复用 `DeviceInformationViewController` 的方案。

原因：

- 现有 light information 的样式、section header、cell、MAC 复制、RSSI 刷新都已集中在 `DeviceInformationViewController`。
- FireAlarm 已经通过参数复用该 controller，继续扩展它符合现有项目模式。
- Battery Power Switch 需求主要是内容差异，不需要新 UI。
- 新建独立 controller 会复制表格和交互逻辑，后续样式容易偏离 light information。

## 入口规则

入口位于 `PJEightKeySwitchMonitorVC.moreAction()`。

菜单构建规则：

- `viewModel.switchData.proxyNode?.isBatteryPowerSwitch == true` 时，追加 `Information` 菜单项。
- 上述条件不满足时，不追加 `Information` 菜单项。
- 点击 `Information` 时再次 guard `informationNode`，避免菜单构建后数据被删除或节点变空导致 crash。

导航规则：

- 点击后使用当前导航栈 push `DeviceInformationViewController`。
- 不触发同步。
- 不修改 `PJEightKeySwitchData`。
- 不刷新或保存本地配置。

## ViewModel 边界

建议在 `PJEightKeySwitchMonitorViewModel` 增加只读 helper，避免 VC 内出现过多业务判断：

- `isRealBatteryPowerSwitch`：判断 `switchData.proxyNode?.isBatteryPowerSwitch == true`。
- `informationNode`：返回 Battery Power Switch 自身 `Node`，即 `switchData.proxyNode`。
- `informationGroupText`：返回 target group names 摘要，空时返回 `nil`。
- `informationSceneText`：Scene Profile 下返回 scene names 摘要，空时返回 `nil`。
- `showsInformationSceneSection`：仅 Scene Profile 返回 `true`。

这些 helper 只读，不产生副作用。

## DeviceInformationViewController 扩展

保持默认初始化行为不变，新增轻量配置能力：

- 支持覆盖 Device rows，用于 Battery Power Switch 固定展示 Device 区字段。
- 继续支持 `groupTextOverride`，用于 Group section 摘要。
- 增加 Scene section 摘要模式，支持 `sceneTextOverride`。
- `showsSceneSection` 继续控制 Scene section 是否出现。

默认调用方不传新增配置时，普通 light / gateway / FireAlarm information 展示保持不变。

## Device 区字段

Device 区数据源为 `switchData.proxyNode` 解析出的 Battery Power Switch 自身 `Node`。

字段顺序固定如下：

1. `Name`
2. `MAC`
3. `PID`
4. `Address`
5. `Version Identifier`
6. `Model`
7. `Device Type`
8. `Firmware`
9. `Signal strength`

字段来源：

- `Name`：与现有 light information 一致，使用 node name，并保留当前 space 的设备名前缀规则。
- `MAC`：使用 `node.macAddressResult`，并保留复制功能。
- `PID`：使用 `node.productIdentifier`，格式为 `0xXXXX`，缺失时为 `--`。
- `Address`：使用 `node.primaryUnicastAddress`。
- `Version Identifier`：使用 `node.versionIdentifier`，缺失时为 `--`。
- `Model`：使用 `node.modelName`，缺失时为 `--`。
- `Device Type`：使用 `node.categoryName`，缺失时为 `--`。
- `Firmware`：使用 `node.firmwareVersion`，缺失时为 `--`。
- `Signal strength`：使用 `node.rssi`，有值时展示 `XdB`，缺失时为 `--`。

Battery Power Switch 的 Device 区不沿用现有 `#if DEBUG` 隐藏 PID / Address / Version Identifier 的规则，因为需求明确要求这些字段展示。

## Group 区字段

Group section 使用 Edit 页同口径的 target groups 摘要。

展示规则：

- 有 target groups：展示 `switchData.bindGroups.map(\.name).joined(separator: ", ")`。
- 没有 target groups：展示 `Not yet linked to a group`。

Group section 不展开多行明细。

## Scene 区字段

Scene section 只在 Scene Profile 中展示。

展示规则：

- `switchData.eightKeyPanelType == .scene8Key`：显示 Scene section。
- `switchData.eightKeyPanelType == .brightness8Key`：不显示 Scene section。
- Scene Profile 有配置 scene：展示 Scene A-D 中已配置 scene 的 names 摘要，使用逗号拼接。
- Scene Profile 没有配置 scene：展示 `Not yet linked to a scene`。

Scene section 不使用 light information 的 scene 明细行，不展示 brightness / CCT 等执行详情。

## 空态与错误处理

- 虚拟设备没有 Information 菜单入口。
- 点击时如果 `informationNode` 为空，直接不打开页面，或提示 `failed`。
- Device 字段缺失统一显示 `--`。
- Group 空态文案使用 `Not yet linked to a group`。
- Scene 空态文案使用 `Not yet linked to a scene`。
- 文案优先走本地化；如果项目暂时没有对应 key，可按现有模式使用英文字符串 `.localizedString`。
- RSSI 刷新继续使用 `DeviceInformationViewController.refreshRSSI()`；刷新不到当前节点时 Signal strength 显示 `--`。

## 测试与验证

需要覆盖以下验证点：

1. 虚拟 Battery Power Switch 菜单不显示 `Information`。
2. 真实 Battery Power Switch 菜单显示 `Information`。
3. 点击 `Information` push 到与 light information 样式一致的页面。
4. Device 区展示 9 个字段，顺序正确。
5. `MAC` 展示 `node.macAddressResult`，不是 `switchData.enOceanMacAddress`。
6. `PID`、`Address`、`Version Identifier` 在非 DEBUG 也展示。
7. Scene Profile 有 scenes 时，Scene section 显示 scene names 摘要。
8. Scene Profile 无 scenes 时，Scene section 显示 `Not yet linked to a scene`。
9. Brightness Profile 不显示 Scene section。
10. 有 target groups 时，Group section 显示 Edit 页同口径摘要。
11. 无 target groups 时，Group section 显示 `Not yet linked to a group`。
12. 普通 light information 展示不回归。
13. FireAlarm information 展示不回归。
14. `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 编译通过。

## 自检结论

- 本设计聚焦 Information 页面入口和展示内容，不涉及同步、添加、删除或配置保存。
- Battery Power Switch 的 `proxyNodeAddress` 复用语义已明确：对 BPS 来说它指向自身 mesh node。
- MAC 来源已明确为 `node.macAddressResult`。
- Group / Scene 采用 Edit 页摘要口径，不复用 light scene 明细行。
- 普通 light / FireAlarm information 默认行为保持不变。
