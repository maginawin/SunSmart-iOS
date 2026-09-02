# Sequence / Trigger Zone SAVE 后 AUTO 行为与 Space 页面退出优化

## 结论

当前两类 SAVE 成功都不会主动让设备进入 Group 页面所称的 `AUTO` 模式：

- `Group > Path > Sequence / Trigger Zone`：不会自动进入 `AUTO`。
- `Space > More > Trigger Zone`：不会自动进入 `AUTO`。

这里需要区分两种协议语义：

- Path / Trigger Zone 保存同步的是 Proximity Lighting 的 Enabled、Relay Number 和 Neighbor Addresses。
- Group 页面 `AUTO` 按钮发送的是 `LightLCLightOnOffSetUnacknowledged(true)`，用于触发 Light LC 运行态进入 Auto。

Neighbor Set 中携带 `enabled = true`，或单独发送 `proximityLightingEnabled(true)`，只表示启用 Proximity Lighting 功能，不能等同于发送 Group `AUTO` 命令。

因此，SAVE 成功后设备可能因为保存前本来就在 Auto 而继续保持 Auto，但当前 SAVE 流程本身不保证、也不主动切换到 Auto。

## Group Path SAVE 调用链

`GroupPathSequencePageController.saveAction()` 同时收集 Sequence 和 Group Trigger Zone 的拟保存数据，然后通过统一拓扑 Planner 生成设备差异任务。

设备任务只可能是：

- `proximityLightingNeighbor`
- `proximityLightingRelayNumber`
- `proximityLightingEnabled`

无任务时页面直接返回；有任务时进入 `SyncDevicesViewController(.proximityLightingPath)`。全部任务成功后只显示成功提示并返回 Group 页面，没有发送 `LightLCLightOnOffSetUnacknowledged(true)`。

返回 `GroupViewController` 后，页面生命周期只会刷新 UI；Daylight 场景中的 `refreshAutoState()` 发送的是 `LightLCLightOnOffGet()` 查询，也不是 Auto Set。

## Space Trigger Zone SAVE 调用链

`SpacePathTriggerZoneController.saveAction()` 保存清理后的 Space Zone，并以 Group Sequence、Group Trigger Zone 和 Space Trigger Zone 的合并拓扑生成受影响设备任务。

无任务时仅完成本地保存、Cloud Dirty 标记和通知；有任务时进入 `SyncDevicesViewController(.spaceTriggerZones)`。该同步类型同样只构造 Proximity Lighting 的 Neighbor、Relay 和 Enabled 任务。成功回调此前只有成功提示与页面栈操作，没有 Group `AUTO` 命令。

## 页面退出问题原因

`SpaceMoreViewController` 通过一个新的模态 `NavigationViewController` 打开 `SpacePathTriggerZoneController`。

旧实现的两个成功分支都调用 `popViewController`：

- 无同步任务时，Trigger Zone 是该导航容器的根页面，Pop 没有可返回页面，可能不退出。
- 有同步任务时，Pop 只会从 Sync Devices 返回 Trigger Zone，不会回到下面的 `Space > More`。

正确返回 `Space > More` 的方式是关闭承载 Trigger Zone 的整个模态导航容器。

## 本次实现

在 `SpacePathTriggerZoneController` 中统一通过 `exitToSpaceMore()` 关闭模态导航容器，并接入两条成功路径：

1. 没有设备同步任务：完成本地保存与通知后立即退出。
2. 有设备同步任务：仅在全部任务成功回调后退出；保留现有成功 HUD 的 1 秒展示节奏。

以下行为保持不变：

- 邻居容量校验失败时不保存、不退出。
- 设备同步失败时停留在 Sync Devices 页面，继续支持失败处理与重新同步。
- Group Path 保存后的导航行为不变。
- 两类 SAVE 均不新增自动进入 `AUTO` 的命令。
- 不修改本地化、资源、Target 配置、依赖或 NordicSigMeshSDK。

## 回归覆盖与验收边界

`SpaceTriggerZoneFollowupContractTests` 新增以下契约：

- Space More 必须以模态导航容器打开 Space Trigger Zone。
- 无设备任务的 SAVE 成功分支必须退出到 Space More。
- 设备同步成功分支必须退出到 Space More。
- 两条成功分支不得继续使用 `popViewController`。
- 退出实现必须关闭模态导航容器。

自动化契约和通用真机构建可以证明源码接线与编译兼容，不能证明真实设备当前运行态、Mesh 命令执行结果或用户实际看到的模态转场。真机验收应覆盖：无改动保存、仅新增空 Zone、有设备任务且全部成功、部分失败后重试、容量超限，以及返回后仍显示同一个 `Space > More` 页面。

## 已完成验证

- Path topology persistence contracts：通过。
- Proximity Lighting topology policy tests：通过。
- Space Trigger Zone follow-up contracts：通过，包含本次两条 SAVE 成功退出契约。
- `git diff --check`：通过。
- SunSmart Debug、通用 iPhoneOS、关闭签名构建：通过。
- Archipelago Debug、通用 iPhoneOS、关闭签名构建：通过。
- Lumineux Debug、通用 iPhoneOS、关闭签名构建：通过。
- SylSmart Debug、通用 iPhoneOS、关闭签名构建：通过。
- SLG Sync Plus Debug、通用 iPhoneOS、关闭签名构建：通过。

构建只出现工程既有的 AppIntents 元数据跳过等警告。尚未执行真实设备 Mesh 状态和实际模态导航交互验收。
