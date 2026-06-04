# Virtual Power Switch 虚线状态分析

## 背景

在 `Site - Space - Switches` 中，用户看到的虚线设备表示虚拟或未绑定实体。Add Device 页的 `Add Device(s) to` 下拉菜单需要展示 Battery Power Switch 和 AC Power Switch 中同样处于虚线状态的虚拟设备，但不应把 EnOcean Switch 纳入 Battery/AC 虚拟目标。

## 虚线判断

- 普通 EnOcean Switch 使用 `DeviceSwitchesViewCell.updateUI()`：
  - `switche.proxyNode != nil`：实线。
  - `switche.proxyNode == nil`：虚线。
- Battery/AC Power Switch 使用 `PJEightKeySwitchesViewCell.applyStatus()`：
  - 先读取 `PJEightKeySwitchData.displayStatus`。
  - 当 `displayStatus.needsDashedBorder == true` 时展示虚线。
  - `needsDashedBorder` 只对应 `.unboundEnabled` 和 `.unboundDisabled`。

## 根因

此前 Add Device 的筛选条件为 `proxyNode?.isPowerSwitch != true`。这个条件存在两个问题：

1. 只判断 proxy node，会把没有 proxy node 但有 EnOcean MAC 的开关误认为可添加的 Battery/AC 虚拟目标。
2. 没有直接复用 Switches 页面中 Battery/AC 自己的虚线状态口径，导致列表展示和 Add Device 下拉菜单展示不一致。

另外，`PJEightKeySwitchData.displayStatus` 原先将 `proxyNodeAddress != nil` 视为 bound。若旧数据残留了无效 proxy address，但实际已无有效 power switch node，会让状态判断偏离真实绑定关系。

## 修复口径

- Battery/AC 的 bound 状态改为：
  - 有效 `proxyNode?.isPowerSwitch == true`，或
  - 存在 `enOceanMacAddress`。
- Add Device 下拉菜单筛选改为复用：
  - `PJEightKeySwitchData.displayStatus.needsDashedBorder`

这样 `Add Device(s) to` 会展示 Battery/AC 中与 Switches 页面虚线状态一致的虚拟设备，同时排除 EnOcean-only 设备。
