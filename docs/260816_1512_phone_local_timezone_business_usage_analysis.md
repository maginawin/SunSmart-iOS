# 手机本地 Timezone 当前业务使用审计

## 1. 结论

按当前 TimeSet/设备时间同步范围审计，编译进四个 App target 的生产调用点中，已经没有业务无条件直接调用无参 TimeSet API、始终使用手机本地 timezone。

手机本地 timezone 目前有三种使用边界：

1. Site timezone 缺失或无效时，统一 TimeSet 工厂有条件回退手机 timezone；
2. 新建 Site，以及克隆一个 timezone 为 `nil` 的 Site 时，用手机 timezone 生成新 Site 的初始默认值；
3. SDK 兼容 API、SDK 旧日程入口和未编译旧源码中仍保留无参手机 timezone 逻辑，但当前 App 生产流程没有调用这些入口。

## 2. TimeSet 中有条件回退手机 timezone 的业务

`SiteTimeSetMessageFactory` 的公开入口默认接收 `TimeZone.current` 作为 fallback 输入。只有以下情况才会使用它：

- 找不到 Node 对应的本地 Site；
- `site.timezone` 为 `nil` 或空白；
- `site.timezone` 格式不能被 `SiteTimeZoneValue` 解析；
- Site offset 不是 Mesh 可精确编码的 15 分钟倍数；
- Site offset 超出 Mesh 可编码范围。

触发 fallback 后，只影响该次 TimeSet 解析/任务规划，不回写 `site.timezone`，不保存 Site，也不上传 Cloud。

所有统一工厂覆盖的业务都可能在上述异常条件下使用手机 timezone：

1. 普通 Timed 日程新增、编辑和启用；
2. Group 日程同步；
3. 通用 Node 日程同步；
4. Sync Devices 时间同步；
5. Device Restore 的时间同步前置任务；
6. Device Group deferred/Fast Add 后续同步；
7. Collection Schedule 单条配置、批量同步和恢复；
8. Gateway Fast Add 时间初始化；
9. 首次 Mesh 连接后的 `.allNodes` 自动 TimeSet 广播；
10. DEBUG 首个日程 Node 时间同步；
11. Sync Gateways：正常目标来自有效 `SiteTimeZoneValue`，通常使用 Site；只有目标 offset 本身不可被 Mesh 精确编码时才会落入工厂的手机 fallback。

这些业务不是“直接绕过 Site 使用手机 timezone”，而是共享同一个受控 fallback 策略。

## 3. TimeSet 之外直接用手机 timezone 初始化 Site 的业务

### 3.1 新建 Site

`SiteData.add(name:)` 创建本地 Site 时，调用 `SiteTimeZoneCatalog.phoneDefaultValue()`，将手机当前 timezone 映射为 `IANA (UTC±HH:mm)` 并在首次 `site.save()` 前写入 `site.timezone`。

这是新 Site 的初始化默认值，不是旧 Site 的 TimeSet fallback，也不是进入旧 Site 时自动修复数据。

### 3.2 克隆 Site

`SiteData.cloneData()` 默认继承原 Site timezone。只有原 Site timezone 为 `nil` 时，才调用 `SiteTimeZoneCatalog.phoneDefaultValue()` 为克隆出来的新 Site 填入手机 timezone。

该逻辑不会修改原 Site，但会使新克隆 Site 不再保持 `nil`。

## 4. 当前 App 未使用的手机 timezone 默认入口

### 4.1 SDK 无参动态 TimeSet handle

`Node.makeLocalTimeSetMessageHandle(model:)` 在每次生成报文时使用 `Date()` 和 `TimeZone.current`。当前 App 生产代码不再直接调用它；App 使用带显式 `timeZone` 的 overload。

### 4.2 SDK 无参 syncNodeTime

`MeshAPI.syncNodeTime(address:)` 会转发到显式 overload，并传入 `.current`。当前 App 的 DEBUG 路径已经显式传入统一工厂解析出的 timezone，没有使用无参版本。

### 4.3 SDK 旧 MeshScheduleServer

`MeshScheduleServer.setSchedule` 在 Node timestamp 为 0 时使用无参动态 handle，因此会用手机 timezone。当前 App 没有调用 `MeshAPI.setSchedule`/该 SDK 业务入口，普通 Timed 使用 App 自己的 `ScheduleServer`。

### 4.4 未编译的 Emergency Fire 旧源码

`EmerFireAlarmSyncCellModel.swift` 仍有无参 `Node.setLocalTimeMessage()`，但该文件未加入四个 App target，当前线上使用共享 `SyncDevicesCellModel`，因此不是当前生产业务。

### 4.5 TaiTime 未知值

SDK 的空 `TaiTime()` 会把 `tzOffset` 初始化为 `TimeZone.current`，但当前用途是解析未知/空 `TimeStatus` 的占位状态，不是主动发送 TimeSet 的业务来源。

## 5. 与“旧 Site 不自动更新”的关系

当前 TimeSet fallback 不会更新旧 Site 的 `site.timezone`，符合已确认需求。

需要单独注意：新建 Site 和克隆 Site 是数据创建流程，它们会使用手机 timezone 作为新对象的默认值。其中克隆旧 Site 且原值为 `nil` 时，会给克隆出来的新 Site填入手机默认值，但不会回写原 Site。若产品要求“克隆也必须保留 `nil`，强制用户进入 Edit Site 选择”，这是一个尚未包含在当前 TimeSet fallback 需求中的额外规则，需要单独调整创建/克隆契约。

## 6. 非本次范围

App 中的 `Calendar.current`、`Locale.current`、未显式设置 timezone 的日期格式化等会影响普通 UI 日期展示或日历计算，但它们不参与 Mesh TimeSet 的 timezone 来源，本审计没有把这些通用显示逻辑列为设备时间同步业务。
