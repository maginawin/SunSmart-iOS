# Sequence / Trigger Zone SAVE 立即同步分析与修复

## 需求

当页面显示 `Devices not synced` 时：

- `Group > Path > Sequence / Trigger Zone` 点击 `SAVE` 后进入 `Sync device(s)`，并自动开始同步。
- `Space > More > Trigger Zone` 点击 `SAVE` 后进入 `Sync device(s)`，并自动开始同步。

## 原因分析

### Group Path

Sequence 与 Trigger Zone 由 `GroupPathSequencePageController` 统一持有和保存。`saveAction()` 会合并两个子页面的编辑副本，使用当前完整 Space 拓扑生成 Plan，再对当前 Group 的全部设备调用 `getNodeSyncProximityLighting`。

页面顶部 `Devices not synced` 也使用同一个 Plan 和同一个 `makeSyncDatas` 判断。因此，只要该提示代表确实存在设备差异，点击 `SAVE` 就会得到非空任务并进入 `SyncDevicesViewController(.proximityLightingPath)`。

SAVE 未传 `reSync: true`。同步页初始状态为 `.inSync`，数据源构建完成后会自动调用 `startSync()`。因此 Group 的 Sequence 和 Trigger Zone 原逻辑已满足“进入页面并自动开始同步”。

### Space Trigger Zone

Space 页面顶部 `Devices not synced` 使用 `buildAllSyncDatas` 检查当前完整拓扑中的所有未同步设备。

但旧 `saveAction()` 使用 `affectedDeviceAddresses(oldSpaceZones:newSpaceZones:)`，只为本次编辑涉及的成员创建任务。当页面已有未同步设备、用户没有修改 Zone 就直接点击 `SAVE` 时，受影响地址为空，SAVE 会把任务判定为空并直接退出，不会进入同步页。

根因是同一页面的状态判断与 SAVE 使用了不同的任务范围：

- 状态提示：全部未同步设备。
- SAVE：仅本次编辑影响的设备。

## 修复

Space Trigger Zone 的 `saveAction()` 改为直接复用 `buildAllSyncDatas(using:)`：

- 与 `Devices not synced` 的判断范围保持一致。
- 无论未同步状态来自本次编辑还是之前失败的任务，只要拟保存拓扑下仍有设备差异，就进入 `Sync device(s)`。
- 仍使用默认 `reSync: false`，同步页加载后自动开始任务。
- 没有实际设备差异时仍走原有无任务成功分支。
- 容量超限、保存持久化、Cloud Dirty、同步成功退出和失败停留行为不变。

本次未修改 SDK、本地化、资源、Target 配置或依赖。

## 回归覆盖

扩展 `SpaceTriggerZoneFollowupContractTests`，锁定：

- Group Sequence / Trigger Zone 的统一 SAVE 使用完整 Group 未同步任务，并创建自动启动的同步页。
- Space Trigger Zone 的 SAVE 使用 `buildAllSyncDatas`，并创建自动启动的同步页。
- `SyncDevicesViewController` 在 `.inSync` 初始状态下自动调用 `startSync()`。

更新 `PathTopologyPersistenceContractTests`，将 Space SAVE 的旧“仅本次编辑成员”契约替换为“全部未同步 eligible devices”契约。

## 验收边界

源码契约和 iPhoneOS 构建可以证明任务范围、页面接线、自动启动条件和编译兼容；不能证明真实 BLE / Mesh 链路中的设备 ACK 与最终持久状态。

真机需分别验证：

1. Group Path 的 Sequence 页面显示 `Devices not synced`，不做编辑点击 `SAVE`。
2. Group Path 的 Trigger Zone 页面显示 `Devices not synced`，不做编辑点击 `SAVE`。
3. Space Trigger Zone 显示 `Devices not synced`，不做编辑点击 `SAVE`。
4. 三条路径都应进入 `Sync device(s)` 并自动开始任务；全部成功后提示完成并按既有导航规则退出。
5. 断开 BLE 或制造部分任务失败，确认停留在同步页并允许后续重新同步。

## 已完成验证

- `scripts/check_path_topology_persistence.sh`：通过。
  - Path topology persistence contracts：通过。
  - Proximity Lighting topology policy tests：通过。
  - Space Trigger Zone follow-up contracts：通过。
- `git diff --check`：通过。
- SunSmart Debug、通用 iPhoneOS、关闭签名构建：通过。
- Archipelago Debug、通用 iPhoneOS、关闭签名构建：通过。
- Lumineux Debug、通用 iPhoneOS、关闭签名构建：通过。
- SylSmart Debug、通用 iPhoneOS、关闭签名构建：通过。
- SLG Sync Plus Debug、通用 iPhoneOS、关闭签名构建：通过。

构建只有工程既有的 AppIntents 元数据跳过警告。真实设备上的 BLE / Mesh ACK、失败重试和最终设备状态仍需真机验收。
