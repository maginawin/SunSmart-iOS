# Debug 设备列表稳定排序设计

## 背景

当前 Debug 页面展示设备列表时，会在扫描到设备广播后把已找到的设备移动到列表前面。这个行为来自 `SpaceDebugViewModel.sections()` 中对 `isFound` 的优先排序。

扫描期间设备会持续更新 RSSI 和 found 状态，如果列表位置随 found 状态变化，用户正在点击某个设备时可能因为 row 移动而点到错误设备，进而连接错误设备。

## 目标

- Debug 页面设备列表顺序稳定，不因为扫描到广播、RSSI 更新或 found 状态变化而改变设备位置。
- 列表按进入 Debug 页面时 `MeshNetworkManager.instance.realNodes` 的原始顺序展示。
- 保留现有设备分类：`Lights / Switches / Sensors / Others`。
- 保留扫描状态展示、RSSI 展示、found count、连接入口和连接行为。

## 确认方案

采用稳定顺序方案：Debug ViewModel 在生成列表 item 时记录每个设备的原始顺序索引，后续分组内始终按这个索引排序。

选择原因：

- 最符合“不要因为广播信号改变点击位置”的安全目标。
- 改动范围小，只影响 Debug 页面列表排序。
- 扫描更新仍可以通过地址快速更新设备状态，不需要重写 ViewModel 数据结构。
- 不受 `space.deviceSortType == .rssi` 影响，避免 Debug 页面又因为信号强度排序出现位置跳动。

## 非目标

- 不修改 Site / Space / Main 中设备列表的排序逻辑。
- 不继承 Main 页面中可能保存的 RSSI 排序。
- 不根据设备名称重新排序。
- 不改变设备分类顺序。
- 不改变扫描、停止扫描、连接、UART 入口和设备信息页逻辑。

## 设计细节

### 数据结构

`SpaceDebugNodeItem` 增加一个仅供 Debug 列表排序使用的顺序字段，例如 `displayOrder`。

`SpaceDebugViewModel.makeItems(nodes:)` 使用 `nodes.enumerated()` 生成 item，记录每个 node 在 `realNodes` 中的原始下标。

### 列表排序

`SpaceDebugViewModel.sections()` 保持现有分类逻辑：

```text
Lights
Switches
Sensors
Others
```

每个分类内部按 `displayOrder` 从小到大排序。

扫描到设备广播时，`updateFoundNode(_:)` 只更新：

- peripheral
- RSSI
- last seen
- found 状态

不更新 `displayOrder`，也不把已找到设备移动到前面。

### 交互行为

- 已找到设备仍显示 RSSI 和信号强度。
- 未找到设备仍显示空信号状态。
- 未找到设备点击后仍不连接。
- 已找到设备点击后仍按当前逻辑停止扫描并连接。
- found count 仍按 found 状态统计。

## 风险与处理

如果 `realNodes` 本身的顺序在不同页面刷新后发生变化，Debug 页面只以进入页面并 `replaceNodes` 时拿到的 `realNodes` 顺序为准。进入 Debug 页面后的扫描更新不会重新排序。

如果后续新增设备分类，仍应保持“分类顺序固定、分类内按原始列表顺序”的规则。

## 验证计划

- 静态检查 `sections()` 不再按 `isFound` 或 `displayTitle` 排序。
- 静态检查 `updateFoundNode(_:)` 不改变 item 的原始顺序字段。
- 构建 `SunSmart` Debug iOS target，确认无编译错误。
- 真机测试 Debug 页面扫描：
  - 扫描到设备广播后，设备 row 不上移。
  - RSSI 和信号强度仍刷新。
  - 点击已找到设备仍可连接。
  - 点击未找到设备仍不会连接。
