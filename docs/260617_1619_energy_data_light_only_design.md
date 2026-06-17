# Energy Data 仅展示 Lights 设备设计

## 背景

`Site - Space - More - Energy Data` 页面预期只面向 lights 类型设备。当前实际会把 Battery Power Switch 和 AC Power Switch 纳入 Energy Data，是因为页面使用 `MeshNetworkManager.instance.realNodes` 作为设备来源，没有按 `Node.DeviceType.light` 过滤。

## 当前页面实际展示范围

入口为 `SpaceMoreViewController` 的 `.energyData` 选项：

- `SylSmart` 直接打开 `EnergyStaticDataViewController`。
- 其他 target 打开 `EnergyDataViewController`，其中包含 `EnergyStaticDataViewController` 和 `EnergyTimeSeriesDataViewController`。

当前纳入 Energy Data 的设备来源：

- Static Data 采集：`EnergyStaticDataViewController.readMeshDevicesEnergy()` 直接读取 `MeshNetworkManager.instance.realNodes`。
- Static Data Device 页签：展示最近一次保存的 `EnergyStatisticsStaticData.deviceEnergyDatas`。
- Time Series 导出设备选择：`EnergyTimeSeriesDataViewController.viewDidLoad()` 直接把 `MeshNetworkManager.instance.realNodes` 赋给 `devices`。

因此当前实际可能展示或纳入的类型包括：

- `light`
- `switches`
- `sensor`
- `dongle`
- `gateway`
- `emergencyController`
- `unknown`

Battery Power Switch 和 AC Power Switch 在 `devices_config.json` 中的 `deviceCategory` 分别为 `BatteryPowerSwitch` 和 `ACPowerSwitch`，在 `Node.DeviceType` 中被映射为 `.switches`。它们会因为 `realNodes` 全量来源进入 Energy Data。

## 目标

Energy Data 入口下的设备范围统一收口为 lights：

- Static Data 采集只读取 lights。
- Static Data Device 页签只展示 lights。
- Time Series 导出设备选择只展示 lights。
- Battery Power Switch、AC Power Switch、sensor、dongle、gateway、emergencyController、unknown 不应出现在 Energy Data 的设备列表和采集范围中。

## 确认方案

采用方案 A：在 Energy Data 模块内建立 light-only 设备来源，不改全局 `realNodes` 语义。

核心规则：

- Energy Data 专用设备集合使用 `MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }`。
- Static Data 新采集只保存 lights 的能耗数据。
- Static Data 读取历史数据时，展示层过滤非 light 历史记录，避免旧数据中的 Battery/AC Power Switch 继续显示。
- Time Series 导出设备选择使用同一 light-only 范围。

## 不做的事

- 不修改 `MeshNetworkManager.instance.realNodes`。
- 不修改 `Node.DeviceType` 映射。
- 不修改 `devices_config.json` 中 Battery/AC Power Switch 的设备类型。
- 不做历史数据库迁移或删除旧采集记录。
- 不调整 Energy Data UI 文案和布局。

## 影响面

直接影响文件预计为：

- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`
- `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`

需要关注的 target：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

## 验收标准

- Space 中同时存在 light、Battery Power Switch、AC Power Switch 时，Energy Data 的 Static Data 采集只包含 light。
- Static Data 的 Device 页签不展示 Battery Power Switch 和 AC Power Switch。
- 旧采集记录里如果已有非 light 数据，Device 页签也不展示这些非 light 数据。
- Time Series 的导出设备选择只展示 lights。
- iPhoneOS 构建通过。

## 验证方式

优先执行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如果改动触及条件编译或 target 资源配置，再补充相关 target 的 iPhoneOS 构建验证。
