# Add Device 虚拟 Power Switch 数据源差异分析

## 结论

`Site - Space - Switches` 中展示的 switches，和 Add Device 中 `Add Device(s) to` 下拉菜单过滤虚拟 Battery/AC Power Switch 时使用的 switches，不是完全相同的业务列表。

两者底层都从 `MeshNetworkManager.instance.switchs` 出发，但 Switches 页面展示时会把普通 `DeviceSwitchData` 通过 `PJEightKeySwitchRepository` 临时转换成 `PJEightKeySwitchData`；Add Device 下拉菜单当前只保留数组里原本就是 `PJEightKeySwitchData` 的对象。

因此会出现：

- 新创建的虚拟 Battery/AC Power Switch 能展示在 Add Device 下拉菜单中；
- 旧数据如果仍以 `DeviceSwitchData` 存在，但 repository 中有 8-key metadata，则能在 Switches 页面展示为虚线 Battery/AC Power Switch；
- 同一条旧数据在 Add Device 下拉菜单中会被 `compactMap { $0 as? PJEightKeySwitchData }` 过滤掉。

## 关键代码

Switches 页面：

- `DeviceSwitchesViewController.collectionView(_:cellForItemAt:)` 使用 `MeshNetworkManager.instance.switchs[indexPath.item]`
- `eightKeySwitchData(for:)` 逻辑：
  - 如果当前对象已经是 `PJEightKeySwitchData`，直接使用；
  - 否则调用 `PJEightKeySwitchRepository.shared.makeEightKeySwitch(from:)`，只要 repository 有 metadata，也会转换成 `PJEightKeySwitchData` 展示。

Add Device 下拉菜单：

- Classic Mode 的 `unboundBatteryPowerSwitches` / `unboundACPowerSwitches`
- Professional Mode 的 `unboundBatteryPowerSwitches` / `unboundACPowerSwitches`

当前逻辑都是：

- 从 `MeshNetworkManager.instance.switchs` 出发；
- 先 `compactMap { $0 as? PJEightKeySwitchData }`；
- 再判断 `isUnboundVirtualPowerSwitchAddTarget` 和 `powerSwitchKind`。

这个 `compactMap` 会丢掉“可由 repository 转换为 8-key switch，但当前 runtime 类型仍是 `DeviceSwitchData`”的旧数据。

## 虚线展示条件

Battery/AC Power Switch cell 的虚线展示来自 `PJEightKeySwitchData.displayStatus.isVirtualSwitch`：

- `.unboundEnabled`
- `.unboundDisabled`

也就是说，Switches 页面里看到的 Battery/AC 虚线设备，只要能通过 repository 转换成 `PJEightKeySwitchData`，理论上也应该能进入 Add Device 的虚拟目标候选。

## 推荐修复

把 Add Device 下拉菜单收集 Battery/AC 虚拟目标的逻辑与 Switches 页面统一：

- 不要只使用 `compactMap { $0 as? PJEightKeySwitchData }`；
- 改为复用同类转换逻辑：
  - 已经是 `PJEightKeySwitchData` 时直接返回；
  - 否则调用 `PJEightKeySwitchRepository.shared.makeEightKeySwitch(from:)`；
- 再统一过滤：
  - `displayStatus.isVirtualSwitch`
  - `powerSwitchKind == .battery` 或 `.ac`

这样旧虚拟 Battery/AC Power Switch 和新创建的虚拟 Battery/AC Power Switch 会按同一规则展示。

## 注意点

不要直接复用 `DeviceSwitchData.batteryPowerSwitchData` 作为 Add Device 下拉候选转换入口，因为它当前要求 `proxyNode?.isPowerSwitch == true`。对于未绑定的虚拟目标，这个条件通常不成立，会继续漏掉未绑定虚拟设备。
