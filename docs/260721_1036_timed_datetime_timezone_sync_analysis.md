# Site - Space - Timed 的 Date-Time 与时区同步分析

## 1. 分析结论

当前 App 在 `Site → Space → Timed` 配置设备定时时，Date-Time 与时区的同步结论如下：

1. **保存并实际同步一条“启用”的设备定时时，App 会先向目标设备发送标准 Bluetooth Mesh `Time Set`，再发送 `Scheduler Action Set`。**
2. **Date-Time 与时区不是两条独立命令。** 当前实现用一条 `Time Set` 同时携带当前时间和 Time Zone Offset。
3. **使用的是手机当前系统时间和手机当前系统时区。** 时间来自 `Date()`；时区来自 `TimeZone.current`。
4. **协议里发送的是当前 UTC offset，不是 `Asia/Singapore`、`Europe/London` 这类时区标识。** Offset 以 15 分钟为步长编码。因此设备只获得同步当刻的偏移值，不会自行掌握该地区未来的夏令时规则。
5. **并非进入 Timed 页面就同步。** 直接进入页面、查看定时列表、只修改名称、删除定时或把定时关闭，都不会通过定时保存链发送 `Time Set`。
6. **除保存定时外，Space 首次连上 Mesh 时还有一次广播同步。** 当 App 判断“设备侧存在 schedule slot”且“本地至少有一个启用定时”时，连接成功 3 秒后向 All Nodes 广播 `Time Set`。
7. **当前所谓的“每天同步一次”并未真正生效。** `SpaceData` 虽然定义了超过 24 小时的 `needSyncDate`，但当前没有调用方；连接后的广播逻辑也没有读取它。

## 2. 当前工程与 SDK 真值层

本次分析以当前 worktree 的源码为准。`SunSmart.xcodeproj` 当前通过 `XCLocalSwiftPackageReference` 引用：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

因此，时间消息的最终构造逻辑应以该本地 SDK 的 `Node.setLocalTimeMessage()` 为真值层，而不是只看 App 的调用点。

## 3. Site - Space - Timed 的直接同步链路

### 3.1 页面入口

`SpaceViewController` 的第 4 个分页（index 3）创建 `TimedViewController(space:)`。`TimedViewController` 新增或编辑定时后，使用 `ScheduleAddViewController` 保存配置。

### 3.2 新增定时

新增时，`ScheduleAddViewController.saveBtnAction()` 先创建并保存 `Schedule`。如果目标包含真实设备，则调用 `pushToSyncDevices(schedule:)`，进入 `SyncDevicesViewController(type: .schedule(schedule))`。

`SyncDevicesViewController` 加载完同步数据源后，在初始 `syncState == .inSync` 时自动调用 `startSync()`。因此正常新增链路是：

`SAVE → 保存本地 Schedule → 打开 Sync Devices → 自动开始设备同步`

不是仅保存本地，也不需要用户在 Sync Devices 页面再次点击开始。

### 3.3 编辑定时

编辑完成时，App 保存新的 `Schedule`，再比较设备缓存中的 `schedulerActions` 与新的 `schedulerEntry`：

- 有设备数据差异：进入 Sync Devices，并自动同步。
- 只有名称等不影响设备配置的字段变化：直接完成，不下发 Mesh 消息。

### 3.4 单台设备的消息顺序

同步任务最终转换为：

`DeviceOperationType.configuration(node:type:.schedule)`

随后调用 `Schedule.getMessageHandles(node:delete:false)`。其顺序为：

1. 如果定时已启用，并且节点存在 `timeModel`，加入 `Time Set`。
2. 加入该定时对应的 `Scheduler Action Set`。

因此每台需要同步的目标设备收到的逻辑顺序是：

`Time Set → Scheduler Action Set`

`Time Set` 是 acknowledged message，opcode 为 `0x5C`，预期响应为 `Time Status`（opcode `0x5D`）。同步队列默认等待响应；单条消息超时后会标记失败，但默认继续处理后续消息。

## 4. 哪些 Timed 操作会发送 Time Set

| 操作 | 是否发送 Time Set | 条件/说明 |
| --- | --- | --- |
| 新增并启用定时 | 是 | 目标中存在需同步设备，且该设备有 `timeModel` |
| 编辑启用定时的时间、周期、动作或目标 | 是 | 仅对需要新增/更新定时数据的目标设备发送 |
| 把定时从关闭切换为开启 | 是 | 开启后的 `Schedule.enabled == true`，同步该定时时先发送 |
| Sync Devices 中重试失败的启用定时 | 是 | 重建消息时会重新生成当前时间和当前时区 |
| 新增但保持关闭的定时 | 否 | 仍会下发 disabled scheduler entry，但不会插入 Time Set |
| 把定时从开启切换为关闭 | 否 | 只下发 disabled scheduler entry |
| 删除定时 | 否 | 只发送无效/删除用的 scheduler entry |
| 只修改定时名称 | 否 | 名称不属于设备 scheduler 数据，无需同步设备 |
| 只进入或查看 Timed 页面 | 否 | 页面生命周期没有时间同步调用 |
| 目标没有 `timeModel` | 否 | Scheduler Action 仍可能发送，但该目标不会经过此链获得时间 |

需要注意：编辑时，如果某台设备只是被移出目标，删除该设备定时的链路不会额外发送 `Time Set`；新加入或定时内容发生变化的目标设备才走启用定时的配置链。

## 5. Space 连接后的额外时间同步

除 Timed 保存链外，`DevicesViewController` 还监听 `MeshLibManager.isMeshNetworkConnected`。

在该 controller 生命周期内第一次观察到 Mesh 连接成功时，如果同时满足：

1. 至少一台真实节点的 `scheduleIds.count > 0`；
2. App 本地至少存在一条 `enabled == true` 的 Schedule；

则 App 延迟 3 秒执行：

`MeshAPI.sendMessage(TimeSet, address: .allNodes)`

也就是说，这次不是只给某一条定时的目标设备单播，而是向 All Nodes 广播。真正支持相应 Time Server/Setup Server 的节点才会处理该标准消息。

### 5.1 “首次连接”的准确含义

`firstConnectionNetwork` 初始为 `true`，首次连接成功后立即改为 `false`，没有在断开时恢复。因此它表示：

- 每个 `DevicesViewController` 实例生命周期内最多执行一次；
- 同一 controller 内再次断线重连，不会再次执行；
- 退出并重新创建 Space 页面后，新 controller 可再次执行；
- 它不是持续定时器，也不是每 24 小时自动执行一次。

### 5.2 24 小时判断目前是死逻辑

`SpaceData.needSyncDate` 会计算：

`当前时间 - lastSyncDateTimestamp > 24 小时`

但当前仓库中没有任何代码读取 `needSyncDate`。`syncTimeNodes()` 虽然会更新 `lastSyncDateTimestamp` 并调用 `space.save()`，但 `SpaceData.save()` 并未将该字段写入数据库。

所以当前行为不能描述为“每天同步一次”。真实行为是“满足定时条件时，每个 Devices controller 实例首次观察到 Mesh 连接成功后广播一次”。

### 5.3 Debug 构建的额外行为

在 `#if DEBUG` 下，首次连接后的广播之外，App 还会在连接成功 5 秒后选择第一台定时相关节点，通过 `MeshAPI.syncNodeTime(address:)` 再单播一次 `Time Set`，用于 OTA 后设备丢失时间的调试。

Release 构建没有这次 5 秒后的额外单播。

## 6. Date-Time 的来源与编码

本地 SDK 的 `Node.setLocalTimeMessage()` 在消息被构造时执行：

1. 读取 `Date().timeIntervalSince1970`，即手机当前系统时间。
2. 减去 `946684800`，把 Unix 1970 epoch 转换为当前实现使用的 2000 epoch 秒数。
3. 将小数秒转换为 1/256 秒的 `subSecond`。
4. 创建 `TaiTime`：
   - `uncertainty = 0`
   - `authority = false`
   - `taiDelta = 0`
   - `tzOffset = TimeZone.current`

因此它没有读取云端时间、网关时间或单独的 NTP 结果；它直接信任手机系统时间。如果手机时间被手动设置错误，设备会收到相同的错误时间。

消息是在同步任务实际生成 `messageHandles` 时创建的，因此新增/编辑同步或重试时会重新读取当时的手机时间和时区，而不是复用创建 Schedule 时保存的时间戳。

## 7. 时区是否为手机当前时区

**是。** 当前代码明确传入 `TimeZone.current`。

更准确地说，设备收到的是手机当前系统时区在同步当刻对应的 GMT/UTC offset：

- 编码单位是 15 分钟；
- 编码公式为 `UTC offset 秒数 / 900 + 0x40`；
- 不携带地区/城市时区名称；
- 不携带未来 DST 切换规则。

这意味着：

- 手机切换到另一个时区后，设备不会因为手机设置变化而立即自动更新；必须再次触发 Time Set。
- 对有夏令时的地区，同步当下的 offset 是正确的，但设备是否能在未来 DST 切换时自行变化，不能由这条消息中的城市规则保证；当前 App 需要在切换后再次同步才能明确刷新 offset。
- 当前连接广播有助于 App 重进 Space 后刷新，但不能保证在 App 长期停留、同一 controller 内断线重连或后台跨越 DST 时立即刷新。

## 8. 其他会复用 Time Set 的相关链路

虽然不属于本次 `Timed` 页面直接保存入口，当前工程中以下业务也会构造 `Node.setLocalTimeMessage()`：

- 全量/专项 Sync Devices 同步 Schedule；
- 集合型 Schedule 同步；
- 设备恢复时恢复其 Schedule；
- Group 保存过程中，为新增/更新的绑定 Schedule 配置设备；
- Emergency Fire Controller 的相关同步。

这些链路使用相同的 SDK 构造器，因此 Date-Time 和时区来源仍然是发送当刻的手机系统时间与 `TimeZone.current`。

## 9. 风险与建议

### 9.1 当前行为风险

1. **时区/DST 变化没有可靠的长期刷新策略。** 当前 24 小时判断没有接入实际触发链。
2. **连接广播没有按目标设备过滤。** 满足条件后向 All Nodes 发送，而不是只对启用定时的目标节点发送。
3. **设备缺少 Time Model 时仍可能写入 Schedule。** 此时设备的时间基础是否正确依赖固件已有状态。
4. **手机系统时间是唯一时间源。** 手机手动时间错误会直接传播给设备。
5. **Debug 与 Release 行为不同。** Debug 在首次连接后比 Release 多一次单播 Time Set，分析抓包或固件日志时需要区分构建配置。

### 9.2 如需改进，建议的最小方向

本报告不修改代码。若后续要修正行为，建议优先明确产品期望，再在以下两种策略中选择：

- **连接事件策略：** 每次有效 Mesh 重连时，只向存在启用定时且支持 Time Setup 的目标设备同步。
- **时区变化策略：** 监听系统时区/显著时间变化，在 Mesh 可用时重新同步相关设备。

同时应删除或真正接入 `needSyncDate`，并决定 `lastSyncDateTimestamp` 是否需要持久化，避免代码注释与真实行为继续不一致。

## 10. 关键代码证据

### App

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`：Timed 页面入口。
- `SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift`：新增/编辑保存及进入 Sync Devices。
- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`：页面加载后自动开始同步、按任务生成消息并发送。
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`：Schedule 配置映射到 `schedule.getMessageHandles()`。
- `SunSmart/Common/Data/Node+MessageHandles.swift`：启用定时的 `Time Set → Scheduler Action Set` 顺序。
- `SunSmart/Main/Device/Controller/DevicesViewController.swift`：首次连接 3 秒后广播同步，以及 Debug 的 5 秒单播。
- `SunSmart/Common/Data/SpaceData.swift`：未被使用的 24 小时判断。
- `SunSmart/Common/Data/Database.swift`：`lastSyncDateTimestamp` 未持久化。

### 本地 NordicSigMeshSDK

- `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`：`Node.setLocalTimeMessage()` 使用 `Date()` 与 `TimeZone.current`。
- `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/TimeMessage.swift`：时间字段及 15 分钟时区 offset 编解码。
- `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Time and Scenes/TimeSet.swift`：`Time Set` opcode、10-byte 参数和 `Time Status` 响应类型。
- `Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`：Time Server / Time Setup Server model 的节点能力入口。

