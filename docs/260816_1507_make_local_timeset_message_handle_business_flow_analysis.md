# makeLocalTimeSetMessageHandle 当前业务流程分析

## 1. 结论

`Node.makeLocalTimeSetMessageHandle` 不是独立业务入口，而是 SDK 用于创建“发送时才生成 TimeSet”的动态 `MeshMessageHandle`。它解决的核心问题是：日程同步、设备恢复或 Fast Add 等任务可能先排队、稍后发送，不能在任务创建时把当前时间冻结在一条静态 TimeSet 中。

当前存在两个 overload：

- `makeLocalTimeSetMessageHandle(model:)`：发送时使用 `Date()` 和 `TimeZone.current`。当前 App 业务代码不再直接调用；它只剩在 SDK 旧 `MeshScheduleServer.setSchedule` 中使用，而当前 App 没有调用该 SDK 日程设置入口。
- `makeLocalTimeSetMessageHandle(model:timeZone:)`：发送时刷新 `Date()`，但使用调用方显式传入的时区。当前 App 由 `SiteTimeSetMessageFactory` 统一调用这一 overload。

因此，在当前 App 中提到 `makeLocalTimeSetMessageHandle`，主要指第二个、带显式时区的版本。

## 2. 当前 App 调用链

当前调用链为：

业务任务生成消息 → `SiteTimeSetMessageFactory` 读取并解析本地 `site.timezone` → 生成显式固定 offset → `makeLocalTimeSetMessageHandle(model:timeZone:)` → 消息队列在真实发送前调用 `prepareMessageForSend()` → provider 重新生成当前时间的 TimeSet → 发往对应 Time Model Element。

若 Site timezone 缺失或不可用，工厂只对本次任务改用手机时区；不会由该方法修改或保存 Site 数据。

## 3. 使用该动态 handle 的业务流程

### 3.1 普通 Timed 日程

- 用户新增、编辑或启用普通日程；
- `ScheduleServer` 按目标设备生成批次；
- enabled schedule 在 `SchedulerActionSet` 前插入一个动态 TimeSet；
- 删除或 disabled schedule 不要求 TimeSet；
- 同一设备批次最多生成一次 TimeSet。

### 3.2 Group 日程同步

- Group 中绑定的日程需要同步到成员 Node；
- `GroupServer` 在需要当前时间的 enabled schedule 前生成动态 TimeSet；
- 若 TimeSet 无法规划，只跳过依赖时间的日程，独立清理任务仍可继续。

### 3.3 通用 Node 同步与恢复 helper

- `NodeSyncData.syncSchedules` 用于通用设备同步路径；
- `NodeSyncData.syncCollectionSchedules` 用于 Collection Schedule 批量同步；
- `Node.getResoreMessageHandles` 中也使用该动态 handle，但当前唯一调用已被注释，属于防止未来恢复入口重新启用后绕过 Site timezone 的预防性迁移。

### 3.4 Sync Devices

- `SyncDevicesViewController` 为有 enabled schedule 的设备生成 `.timeSynchronization` 前置任务；
- `SyncDevicesCellModel` 通过动态 handle 下发 TimeSet；
- 后续依赖当前时间的 schedule 任务只有在前置时间同步可执行时才继续。

### 3.5 Device Restore

- Restore 在恢复 enabled schedule 前插入 `.timeSynchronization` 任务；
- 该任务复用 `SyncDevicesCellModel`，因此最终使用同一个动态 handle；
- 重试时保留 handle/任务语义，同时重新生成发送时的当前时间。

### 3.6 Group deferred 与 Fast Add 后续同步

- `DeviceGroupDeferredSyncPlanner` 会生成 `.timeSynchronization` 和 Collection Schedule 任务；
- 这些任务复用 `SyncDevicesCellModel` 的消息生成逻辑；
- Fast Add checkpoint 依赖原 handle identity，但每次真实发送仍会刷新 TimeSet 内容。

### 3.7 Collection Schedule

- Dongle/Collection Scheduler 的单条配置、批量同步、Restore 和 deferred 流程都会先生成动态 TimeSet；
- TimeSet 后才发送 `SchedulerActionSet`；
- TimeSet handle 缺失时不会继续写依赖时间的 Collection Schedule。

### 3.8 Gateway Fast Add 初始化

- 4G/Wi-Fi Gateway Fast Add 完成基础配置后，`GatewayFastAddTimeInitialization` 通过 `SiteTimeSetMessageFactory.makePlan` 创建动态 TimeSet handle；
- 真实发送时刷新当前时间；
- 后续用 `TimeStatus` 中的非零 timestamp 和实际目标 offset 判断初始化是否成功；
- TimeSet 失败不回滚已经完成的 Gateway provisioning。

## 4. 不使用该 handle 的 TimeSet 流程

以下路径虽然也发送 TimeSet，但不是通过 `makeLocalTimeSetMessageHandle`：

- 首次 Mesh 连接后的 `.allNodes` 自动广播：直接生成即时 TimeSet 并广播；
- DEBUG 首个日程 Node 同步：调用显式时区的 `MeshAPI.syncNodeTime`；
- Sync Gateways：`GatewayTimeSyncCoordinator` 直接生成 TimeSet，并根据返回的 `TimeStatus` 校验目标 offset。

这三类路径不应被算作该动态 handle 的业务调用点。

## 5. SDK 发送时语义

`MeshMessageHandle` 内部保存 `messageProvider`。普通消息队列 `MeshMessageManager` 和 Fast Add 队列 `MeshFastAddDeviceManager` 都会在实际发送前调用 `prepareMessageForSend()`，触发 provider 重新生成报文。

对显式时区 overload 而言：

- 当前时间在每次 prepare/send 时刷新；
- 时区 offset 使用任务规划时由 Site 工厂确定的值；
- 发送目标是传入 `model` 所属 Element，而不是 `.allNodes` 广播；
- 生成的是 acknowledged `TimeSet`，协议上期望设备返回 `TimeStatus`。
