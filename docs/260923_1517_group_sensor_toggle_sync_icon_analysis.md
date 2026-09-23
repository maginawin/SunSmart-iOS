# Group 传感器开关后设备图标短暂显示“需要同步”

日期：2026-09-23

## 结论

这是同步状态**计算中**被暂时画成**需要同步**的显示问题。开关成功后，设备属性写入和同步状态缓存失效会触发 Group 设备 Cell 刷新；异步 Group 同步核对尚未返回时，Cell 将 `nil`（未知）按 `true`（需要同步）选择图标。核对返回 `false` 后图标恢复。观察到图标消失，说明该次核对没有发现该设备需要同步 Group 数据，并不代表 App 曾执行一次补同步。

短暂提示符合当前代码的保守占位策略，但文案/图标语义对用户不准确。仅根据源码不能断言每次现场闪烁都由同一条通知触发；需要运行日志才能确定具体触发时间和持续时长。

## 代码链路

1. `SunSmart/Main/Group/Controller/GroupViewController.swift` 的 `occupancySensorTapAction` 发送 `SunricherVendorSet(function: .pirEnabled(enabled:))`。收到成功 Status 后设置 `sensor.pirEnabled`、`savePropertys()`、发布 `spaceDataChangedNotificaitonName`，并调用 `sensor.reloadSyncStateCache()`。此处没有启动 Group 重同步流程。
2. 本地 `SunSmartLocal.xcworkspace` 经 `.local-sdk/nordic-sig-mesh-sdk` 指向 `nordic-sig-mesh-sdk-worktrees/one-dev`（检查时 HEAD `ebbe1c9`）。该 SDK 的 `savePropertys()` 写入 `pirEnabled`，在秒级修改时间变化时发出 `deviceDataUpdateTimeChange`；Vendor 状态处理也有更新并保存 `pirEnabled` 的路径。`GroupViewController` 收到时间戳回调会清除节点同步状态缓存并刷新可见 Cell；收到一般设备数据更新则在其 1 秒 UI 刷新定时器中刷新对应 Cell。两者都是可能的列表刷新入口。
3. `SunSmart/Main/Device/View/DevicesViewCell.swift` 的 `refreshGroupSyncStatus` 先调用 `applyGroupSyncIcon`，再请求异步 `NodeSyncStatusRefresh.requestGroupData`。`applyGroupSyncIcon` 对 `groupSyncDisplay?.needsSync(for:) ?? true` 显示 `unsyncIconName`，因此未算出结果时就是“需要同步”图标。
4. `SunSmart/Common/Data/NodeSyncStatusRefresh.swift` 的 `GroupSyncDisplayState.needsSync` 仅在同一对象且 `SpacePageRevision` 仍有效时返回结果；属性数据库写入或 `NodeSyncStatusGeneration` 失效后返回 `nil`。异步结果返回后，回调再次设置图标。`Tests/Group/GroupDeviceSyncDisplayTests.swift` 明确验证了“pending Group read”先显示同步图标、完成后恢复普通图标的现有行为。
5. Group 设备图标取的是 `getNeedSyncGroup()`，不是设备的全部 `needSync`。`SunSmart/Common/Data/Node+SyncData.swift` 的 Group 判定会检查订阅、Profile、场景、日程等；对当前已在组内的 Occupancy 传感器，`pirEnabled` 开关本身不是这个判定的目标项。退出组失败的清理路径另有将 PIR 默认恢复启用的逻辑，不适用于题述已在组内的操作。

## 正确性边界

- 开关命令成功、配置持久化、云端数据变更通知，与 Group 同步核对是不同的动作。短暂图标消失仅证明 UI 最终读到 `getNeedSyncGroup() == false`；不能据此证明真机的占用上报行为、云端同步或其他设备状态。
- 如果图标最终持续存在，应检查实际 Group 同步差异或配置读取失败，不能统一当作显示闪烁处理。当前读取输入不可用时，同步状态读取器也会保守返回 `true`。
- App 成功回调只检查 Vendor Status 的 `isSuccessful`，随后保存本地值；其与设备实际功能行为的对应仍需真机验证。

## 优化方向

### 已确定的展示方向：未知时使用正常图标

按本次交互确认，Group 设备列表只使用两种图标：`needsSync == true` 显示“需要同步”；`false` 或尚未得到结果的 `nil` 显示正常图标，不另加“核对中”状态。异步结果若为 `true`，立即切换到“需要同步”；读取输入不可用而保守返回 `true` 时也照常显示“需要同步”。实现仅改变 `DevicesViewCell.applyGroupSyncIcon` 的未知态显示，不改变实际同步判定、请求和失效机制。这个 Cell 同时用于 Group 详情和 Members 页，因此两页的设备图标行为一致；Members 页的同步按钮仍沿用原有的保守判定。

此方案接受一个取舍：真实需要同步的设备在异步核对返回前也可能短暂显示正常图标。当前核对涉及保护数据读取、拓扑准备和主线程分片，通常可较快完成，但源码没有完成时限保证；不能将“很快”作为正确性前提。页面隐藏或 Cell 复用时请求可能取消，再次可见时会重新核对。

### 更深入：缩小状态失效和 Cell 刷新范围

对仅改变 `pirEnabled` 的操作，可评估是否只刷新底部传感器行、只触发必要的 Group 同步重算，避免无关的整 Cell 绑定或全局 revision 失效。本地 SDK 与 App 都存在保存该属性的路径，也可核查实际回调中是否重复写库。此方案影响共享状态更新和兼容性，优先级低于单纯修正未知态显示，实施前需核对其他 Group 页面及真实同步差异。

## 建议验收

在 Group 页对支持占用传感器的灯分别禁用、启用，覆盖命令成功和超时/失败：传感器行在请求期间提示处理中，成功后状态正确；设备图标在同步结果未知时保持正常，核对为 `false` 时继续正常；若制造真实 Group 配置差异，核对返回 `true` 后显示需要同步；滚动、Cell 复用和离线/重新进入页面不显示旧设备结果。自动化可复用 `GroupDeviceSyncDisplayTests`，但最终闪烁时长和传感器行为仍需真机体验验收。

## 实施与验证

- `DevicesViewCell.applyGroupSyncIcon` 在结果为 `nil` 时选用正常设备图标；结果为 `true` 时仍显示“需要同步”。
- 更新 `GroupDeviceSyncDisplayTests`，覆盖首次核对未知、旧结果失效、真实 Group 差异最终返回 `true`、离线和 Cell 复用。`python3 scripts/check_node_sync_status_refresh.py` 通过。
- `SunSmartLocal.xcworkspace` 的 SunSmart scheme，Debug、generic iOS、`CODE_SIGNING_ALLOWED=NO` 编译通过。变更位于所有品牌共用的 Cell，未涉及品牌编译条件或资源，因此本轮以 SunSmart 作为代表 target。
- 未进行真机 UI/传感器行为验收；需实际点击启用、禁用并观察 Group 页图标和底部传感器状态。
