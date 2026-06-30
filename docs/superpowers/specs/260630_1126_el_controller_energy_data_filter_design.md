# EL Controller Energy Data 过滤设计

## 背景

`CID 0x0A78 / PID 0x24C1` 的 EL Controller 在 `devices_config.json` 中配置为 `deviceCategory: Lighting`，因此 `Node.deviceType` 会被解析为 `.light`。当前 Energy Data 模块已经做过 light-only 收口，但该规则仍会把 EL Controller 纳入能耗统计。

该设备不支持能耗统计，因此不应出现在 `Site - Space - More - Energy Data` 下的能耗展示、采集和导出相关页面中。

## 当前代码事实

- `SpaceMoreViewController` 的 `.energyData` 入口在 `SylSmart` target 打开 `EnergyStaticDataViewController`，其他 target 打开 `EnergyDataViewController`。
- `EnergyDataViewController` 包含 `EnergyStaticDataViewController` 和 `EnergyTimeSeriesDataViewController`。
- `EnergyStaticDataViewController` 当前使用 `MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .light }` 作为采集设备来源。
- `EnergyStaticDataViewController` 读取历史 Static Data 时，也按 `.light` 过滤 `DeviceTotalEnergyData`。
- `EnergyTimeSeriesDataViewController` 当前使用同样的 `.light` 条件作为导出设备候选来源。
- `Device Parameter Settings` 已通过 `node.supportSetParameter` 排除 `isEmergencySignController`，所以 EL Controller 不会进入参数页的 Energy Reporting 或 Rated Power 设置链路。

## 已确认方案

采用方案 A：在 Energy Data 模块内复用现有 `node.isEmergencySignController` 作为排除条件。

统一规则：

- 可参与 Energy Data 的节点必须是 `node.deviceType == .light`。
- 可参与 Energy Data 的节点必须不是 `node.isEmergencySignController`。
- 历史 Static Data 也必须用同一语义过滤，避免旧记录继续展示 EL Controller。

## 覆盖范围

本次设计覆盖以下能耗相关页面和链路：

- `Static Data` 分类下的 `Energy report` 选择 `Device` 时，不展示 EL Controller。
- 点击 `HARVEST NEW ENERGY DATA` 后进入的 `Harvest data` 页面，不展示也不读取 EL Controller。
- 历史 Static Data 中如已保存 EL Controller 记录，读取后也不展示。
- `Time Series Data` 的导出设备选择列表不展示 EL Controller。

## 不做的事

- 不修改 `devices_config.json` 中 `0x0A78 / 0x24C1` 的 `deviceCategory: Lighting`。
- 不修改 `Node.DeviceType` 映射。
- 不新增 `supportsEnergyData` 或类似设备能力判断。
- 不修改 `Node.isEmergencySignController` 的现有语义。
- 不影响 EL Controller 在 Lights、详情页 Relay、RX/TX、Function Test 等现有功能。
- 不做历史数据库迁移或删除旧采集记录，只在展示和读取入口过滤。

## 设计细节

`EnergyStaticDataViewController` 中的 live 设备来源需要从 light-only 调整为 light-and-not-emergency-sign-controller。该规则用于 `readMeshDevicesEnergy()`，因此 `ReadDevicesDataViewController(type: .harvestData(...))` 收到的节点列表会自然排除 EL Controller。

`EnergyStaticDataViewController` 的历史数据过滤也需要同步更新。当前 `isLightEnergyData(_:)` 会优先通过地址找到当前 mesh node，再判断 `deviceType == .light`；这里需要在命中当前 node 时额外排除 `node.isEmergencySignController`。如果无法通过地址找到 node，则根据 `productId` 查配置时，`0x24C1` 仍会被解析为 light，因此历史 fallback 也需要额外排除 `Node.isEmergencySignController(companyIdentifier:productIdentifier:)`。由于历史 `DeviceTotalEnergyData` 只有 `productId`，fallback 需要从 `MeshLibManager.manager.supportDeviceInfos` 中找到对应 `MeshDeviceConfigInfo.companyId/productId` 后执行同一静态判断。

`EnergyTimeSeriesDataViewController` 的导出候选设备来源需要使用相同规则，避免 EL Controller 出现在 export target 为 Device 时的选择列表。

## 影响文件

预计只需要改动：

- `SunSmart/Main/Energy/Controller/EnergyStaticDataViewController.swift`
- `SunSmart/Main/Energy/Controller/EnergyTimeSeriesDataViewController.swift`

## 验收标准

- Space 中同时存在普通 light 和 EL Controller 时，`Static Data > Energy report > Device` 只展示普通 light，不展示 EL Controller。
- 点击 `HARVEST NEW ENERGY DATA` 后，`Harvest data` 页面只包含普通 light，不包含 EL Controller。
- 新采集保存的 Static Data 不包含 EL Controller。
- 旧 Static Data 如包含 EL Controller，重新进入页面后不展示该设备，也不参与 Space / Group / Device 统计。
- `Time Series Data` 中选择 Device 导出时，不展示 EL Controller。
- Device Parameter Settings 入口行为保持现状。
- iPhoneOS 构建通过。

## 验证方式

执行：

`git diff --check`

执行 iPhoneOS 构建：

`xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如改动触发 target 条件编译差异，再补充受影响 target 的 iPhoneOS 构建。
