# EFC Information Name 问题分析与修复计划

## 背景

在 EFC 设备页面右上角选项菜单中选择 Information 后，会进入共享的 `DeviceInformationViewController`。当前问题是 Information 页面展示的 Name 与 EFC 设备页、Others 列表、Edit 页面中的 EFC 设备 name 不一致。

预期行为：Information 页面中的 Name 应与当前 EFC 设备的实际业务名称一致。

## 代码事实

1. EFC 设备页菜单入口在 `EmerFireAlarmMonitorRouting.makeInformationMenuItem()`。
   - 当前入口传入的是 `currentDevice?.bindNode`。
   - 创建 `DeviceInformationViewController` 时只传了 `node`、group override 和隐藏 scene，没有传 `nameOverride`。

2. 共享 Information 页面 `DeviceInformationViewController.setupDeviceInfoDataSource()` 的 Name 来源是：
   - 优先 `nameOverride`
   - 否则 `node.name`
   - 如果没有 override 且当前 Space 开启 group prefix，会再拼接 `group.name-name`

3. EFC 设备页自身展示的 name 来源不是 `node.name`。
   - `EmerFireAlarmMonitorVC.viewDidLoad()` 使用 `currentDevice?.name ?? currentConfig?.deviceName`。
   - `EmerFireAlarmMonitorRendering.applySavedConfig()` 使用 `config.deviceName`。
   - Others 列表和 EFC 卡片也围绕 `DeviceEmerFireData.name` 展示。

4. EFC Edit 保存逻辑在 `LinkedEmerFireEditViewModel.apply(_:to:)` 中只更新 `DeviceEmerFireData.name = config.deviceName`。
   - 这里没有同步写回 `device.bindNode?.name`。
   - 因此用户改过 EFC 名称后，`DeviceEmerFireData.name` 与绑定的 `Node.name` 可能分叉。

5. 同类已有做法：8-key switch 的 Information 入口同样复用 `DeviceInformationViewController`，但传了 `nameOverride: viewModel.title`，避免共享页面误用底层 node name。

## 根因判断

问题真实存在。

直接根因是 EFC Information 入口没有向共享 Information 页面传入 EFC 业务名称 override，导致页面回退显示绑定 `Node.name`。EFC 的真实展示名称保存在 `DeviceEmerFireData.name` / `LinkedEmerFireConfig.deviceName`，而不是完全依赖 `Node.name`。

更深层原因是 EFC 是“本地业务配置 + 绑定真实 Mesh Node”的组合对象：用户看到和编辑的是 EFC 业务对象名称；Information 页面是普通设备信息页，默认从普通 Mesh Node 读取 Name。两者数据源不同，入口没有显式桥接。

## 推荐方案

采用最小修复：只在 EFC Information 入口传 `nameOverride`，让共享 Information 页面显示当前 EFC 业务名称。

优先级：

1. `viewModel.currentConfig?.deviceName`
2. `currentDevice?.name`
3. `node.name ?? ""`

原因：

- `currentConfig` 是监控页当前 UI 已应用的最新快照，能覆盖刚从 Edit 保存通知回来的名称。
- `currentDevice.name` 是持久化 EFC 业务对象名称。
- `node.name` 只作为最后兜底，避免异常情况下空白。
- 不需要修改共享 Information 页面默认逻辑，避免影响 Light、Gateway、Power Switch 等其他入口。
- 不需要在保存 EFC 名称时强制写回 `Node.name`，避免改变 Mesh Node 通用命名语义和云/导入链路的影响面。

## 影响范围

预计只修改：

- `SunSmart/Main/Device/Device1.5/FireAlarm/Controller/EmerFireAlarmMonitorRouting.swift`

不修改：

- `DeviceInformationViewController` 的通用逻辑
- EFC name 存储结构
- `Node.name` 保存语义
- 本地化资源
- target 配置和依赖

## 验证计划

1. 静态检查：
   - 确认 EFC Information 创建 `DeviceInformationViewController` 时传入 `nameOverride`。
   - 确认其他 `DeviceInformationViewController` 入口不受影响。

2. Contract 检查：
   - 如现有 `scripts/check_efc_controller_flows.sh` 覆盖菜单入口，补充或确认它能检查 EFC Information 的 `nameOverride`。

3. 构建验证：
   - 运行 iPhoneOS build：
     `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

4. 手工验证：
   - 进入 EFC Edit，修改 Name 并保存。
   - 回到 EFC 设备页面，打开 Information。
   - 确认 Information 页面 Name 与 EFC 页面标题 / Others 列表显示一致。

## 待确认

推荐按“仅 EFC Information 入口传 `nameOverride`”实施。确认后我会按该方案做最小代码改动，并按上面的验证计划执行。
