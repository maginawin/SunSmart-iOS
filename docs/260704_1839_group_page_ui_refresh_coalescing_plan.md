# Group 页面 UI 合并刷新开发方案

## 结论

用户提出的方向是正确的：Group 页面在大设备数量和高频 sensor publish 下，不应该每收到一条状态消息就立即写 UI。更稳的做法是把 Mesh 收包后的状态更新和 UI 刷新拆开：

- 数据层仍然立即记录最新状态。
- UI 层只在固定节奏或关键交互点刷新。
- 滚动期间只累计 dirty state，不做非必要 UI 写入。
- 用户主动操作 UI 时立即刷新一次，并顺延下一次定时刷新，避免连续两次刷新撞到滚动。

但不建议把它做成零散的 `Timer + reload`。推荐在 `GroupViewController` 内做一个页面级 `GroupUIRefreshCoordinator` 或等价的私有刷新调度模块，统一管理设备列表、sensor 列表、group control summary 三类 UI 的刷新节奏。

## 当前代码证据

### 设备列表

当前 `GroupViewController` 已经做过第一轮收口：

- sensor-only message 不再进入设备 collection/control panel 刷新。
- `nodeIndexByAddress`、CCT nodes、up/down ratio nodes 已在页面层缓存。
- `DeviceUpDownRatioControlView` 的布局冲突已修掉。

但以下路径仍会在非 sensor-only 消息或外部 `deviceDataUpdate` 时直接写 UI：

- `reloadCollectionItem(node:)`
- `reloadVisibleGroupDeviceItems()`
- `collectionView.reloadData()`
- `updateGroupControlSummaryIfNeeded()`

这些在滚动期间仍可能和 collection view 滚动争主线程。

### Sensor 状态列表

`GroupSensorView.reloadSensorData(sensor:sensorType:)` 目前每条 sensor 状态都会立即：

- 更新顶部 occupancy / lux 状态。
- 查找 sensor index。
- 如果 cell 可见，直接更新 cell。
- 重启 cell 或 header 上的 occupy/lux timer。

展开底部 sensor 列表后，sensor table 正在滚动时仍然会被高频状态消息打断。这解释了为什么第一轮修复后，展开 sensor 列表仍然卡。

### 一个必须注意的边界

`SunricherVendorSet.proximityLightingTrigger` 现在的逻辑是：

- 临时把 `sensorNode.occupancyState = true`
- 立即刷新 sensor UI
- 再把 `occupancyState = false`

如果改成延迟刷新，不能只等到下次 UI flush 时从 `Node` 读取状态，否则这个瞬时触发会丢失。调度器必须记录这类 sensor event 的待刷新快照，或者把“触发态持续显示一段时间”的逻辑交给 `GroupSensorView` 内部处理。

## 方案比较

### 方案 A：只给 sensor 列表加节流

做法：

- `GroupSensorView.reloadSensorData(...)` 内部做 1 秒合并。
- table 正在滚动时延后刷新。

优点：

- 改动少。
- 能直接缓解展开 sensor 列表后的卡顿。

缺点：

- 设备列表、group control、switch action 等 UI 刷新仍是分散的。
- 后续如果 collection view 仍卡，还要再做一套类似逻辑。
- controller 和 view 各自节流，容易出现刷新顺序不一致。

不推荐作为主方案，只适合作为临时止血。

### 方案 B：Group 页面统一 UI refresh coordinator（推荐）

做法：

- 在 `GroupViewController` 页面层新增统一刷新调度器。
- Mesh message / deviceDataUpdate 到来时，只更新 Node 数据和 dirty state。
- 每 `refreshUIInterval` 秒 flush 一次 UI，默认 `1`。
- 如果 collection view 或 sensor table 正在滚动，则跳过本次 flush，只保留 dirty state。
- 滚动结束、用户点击设备、用户拖动亮度/CCT/up-down ratio、打开/关闭 sensor drawer 时，立即 flush 相关 UI，并顺延下一次定时 flush。

优点：

- 设备列表和 sensor 列表共享同一节奏。
- 可以明确区分 passive mesh update 和 user action update。
- 对大 group 和高频 sensor publish 更稳。
- 改动仍局限在 Group 页面，不需要改 SDK 或全局模型。

缺点：

- 比单点节流改动更多。
- 需要仔细处理 transient sensor event、switch action、manual UI 操作的即时反馈。

推荐采用。

### 方案 C：全局设备状态 store + diff-driven UI

做法：

- 把设备和 sensor 状态统一纳入全局 store。
- 各页面订阅状态 diff，按可见性和节流策略刷新。

优点：

- 长期架构最干净。
- 多页面可复用。

缺点：

- 影响面太大。
- 当前需求只针对 Group 页面，不适合作为本轮修复。

不推荐本轮做。

## 推荐设计

### 1. 新增 Group 页面刷新状态

刷新状态保留在 `GroupViewController` 内，不进入全局模型。

需要记录：

- dirty device addresses：哪些设备格子需要刷新。
- dirty sensor addresses + sensor type：哪些 sensor cell/header 需要刷新。
- group summary dirty：是否需要刷新 on/off、brightness、CCT、up/down ratio control。
- full collection reload pending：switch action 或 group-wide action 是否需要整列表刷新。
- full sensor reload pending：sensor 集合变化时是否需要整表刷新。
- is device collection scrolling。
- is sensor table scrolling。
- last immediate flush time / next timer flush policy。

`refreshUIInterval` 默认 `1` 秒。建议先作为 `GroupViewController` 私有常量，后续如果需要实验开关，再接入 LabSettings。

### 2. Mesh message 只记录 dirty state

`didReceiveMessage` 保持立即调用 `node.updateData(message:)`，但不直接写 UI。

规则：

- `SensorStatus`：记录对应 sensor address 和 sensor type dirty；不直接调用 `sensorView.reloadSensorData(...)`。
- `SunricherVendorSet.proximityLightingTrigger`：记录一个 presence trigger event，不能只依赖 `Node.occupancyState` 的最终值。
- `LightLCLightOnOffStatus`：记录 sensor header/control state dirty。
- light on/off、lightness、CCT、scene、switch action：记录 device dirty 或 full collection reload pending，并标记 group summary dirty。
- `deviceDataUpdate`：记录对应 device dirty 和 group summary dirty。

用户主动操作仍走 immediate path：

- 点击设备开关后，立即刷新这个 visible device item 和 group summary。
- 拖动 group brightness / CCT / up-down ratio 时，继续保持即时视觉反馈。
- 用户操作触发的即时刷新完成后，跳过或顺延下一次 timer flush。

### 3. Timer flush 策略

定时器只在页面可见时运行。

每次 tick：

- 如果没有 dirty state，什么都不做。
- 如果 collection view 或 sensor table 正在滚动，跳过 UI 写入，保留 dirty state。
- 如果不在滚动，按 dirty state 做最小刷新：
  - full collection reload pending 优先使用 `collectionView.reloadData()`。
  - 否则只刷新可见 dirty device cell。
  - full sensor reload pending 使用 `sensorView.reloadData` 或等价接口。
  - 否则只刷新可见 dirty sensor cell/header。
  - group summary dirty 才刷新 group control summary。

这里的“跳过下一次更新 UI”建议实现为“immediate flush 后重置下一次 timer 的有效刷新时间”，而不是简单丢弃 dirty state。这样不会丢设备状态，只是避免刚交互完马上又刷一次。

### 4. 滚动状态接入

设备 collection view：

- `scrollViewWillBeginDragging`：标记 device collection scrolling。
- `scrollViewDidEndDragging` 且不会 decelerate：结束滚动并立即 flush 一次。
- `scrollViewDidEndDecelerating`：结束滚动并立即 flush 一次，同时更新 pageControl。

Sensor table view：

- 给 `GroupSensorViewDelegate` 增加 table scroll 状态回调，或给 `GroupSensorView` 暴露轻量闭包。
- `GroupSensorView` 内部 table 开始拖拽、结束拖拽、结束减速时通知 `GroupViewController`。
- controller 统一决定是否 flush。

建议优先用 delegate 方法，保持项目现有风格。

### 5. GroupSensorView 接口调整

为避免 controller 直接操作 table cell 细节，建议给 `GroupSensorView` 增加小接口：

- 批量刷新 dirty sensor events。
- 刷新 sensor header 状态。
- 判断某 sensor cell 是否可见后再更新。
- 必要时整表 reload。

同时保留现有 `reloadSensorData(sensor:sensorType:)` 的行为给用户主动操作或同步结果使用，但 Mesh 高频上报路径不再直接调用它。

### 6. 验证策略

静态回归脚本新增检查：

- `SensorStatus` 不直接调用 `sensorView?.reloadSensorData(...)`。
- `didReceiveMessage` 中存在 dirty marking / scheduler 入口。
- 存在 `refreshUIInterval` 默认值。
- 存在 collection view 和 sensor table scroll 状态 gating。
- immediate flush 后存在跳过或顺延下一次 timer flush 的逻辑。

构建验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

手工验证：

- 83 设备 group 中滑动 collection view，滚动期间不被 sensor publish 打断。
- 展开 sensor 状态列表后滑动 table，滚动期间不被 sensor publish 打断。
- 停止滚动后，最新设备/sensor 状态能在 1 秒内刷新到 UI。
- 用户点击设备、拖动 group brightness/CCT/up-down ratio 后，UI 立即反馈。
- proximity trigger 仍能短暂显示 triggered 状态，不因延迟刷新丢失。
- group switch action、scene action 后，设备列表最终状态正确。

## 推荐实施范围

第一轮只做方案 B 的页面级调度，不进入全局架构：

1. 在 `GroupViewController` 增加刷新调度状态和 `refreshUIInterval`。
2. 改 `didReceiveMessage` / `deviceDataUpdate` 为 dirty marking。
3. 改设备 collection view 滚动回调，滚动结束 flush。
4. 给 `GroupSensorView` 增加 sensor table 滚动回调与批量刷新接口。
5. 接入 timer flush 和 immediate flush。
6. 增加静态回归脚本检查。
7. 跑 diff check 和 iPhoneOS build。

暂不做：

- 全局状态 store。
- 全局 device cell / AdaptiveTextView 性能重构。
- SDK 收包链路调整。
- LabSettings UI 配置项。

## 需要确认

建议确认采用方案 B。

如果确认，我会按上面的第一轮范围写实施计划并开始改代码。`refreshUIInterval` 先作为 Group 页面私有默认值 `1` 秒；如果后续需要现场调参，再单独接 LabSettings。
