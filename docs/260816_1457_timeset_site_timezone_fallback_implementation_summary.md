# TimeSet 使用 Site Timezone 与手机时区回退实施总结

## 1. 实施结果

已按确认的方案 A 完成实现：App 当前编译进四个品牌 target 的 TimeSet 生产路径，统一优先读取本地 `site.timezone`，用手机发送时的当前 `Date` 生成绝对时间，并用 Site 中保存的固定 UTC offset 生成 TimeSet 的时区字段。

当本地 Site 不存在、`site.timezone` 为 `nil`/空白/格式错误，或 offset 不能被 Mesh 的 15 分钟步长精确编码时，本次 TimeSet 改用手机当前时区。该 fallback 只存在于报文规划结果中，不会修改 Site 对象、不会调用 `site.save()`、不会设置 pending Site Props，也不会触发 Cloud update。

本轮保持既有 TimeSet 触发权限、发送目标和业务入口，不扩展处理 Visitor 权限边界。

## 2. 统一解析与报文生成

新增 `SiteTimeSetMessageFactory`，统一负责：

- 从显式 `siteId` 或 Node 所属 Mesh Network UUID 读取本地 Site；
- 解析 `site.timezone` 保存值；
- 校验 offset 是否能被 TimeSet 精确编码；
- Site 不可用时只对本次报文回退手机时区；
- 生成即时 TimeSet 或发送时刷新 `Date` 的动态消息 handle；
- 提供 Site、手机 fallback 及 fallback 原因，供测试和 DEBUG 诊断使用；
- 当 Site 与手机 offset 都不能被 Mesh 精确编码时返回失败，不截断、不四舍五入、不静默改为 UTC。

`SiteTimeZoneValue` 增加 Mesh offset 可编码性判断。未知 IANA identifier 不在 TimeSet 层单独判无效：设备实际只消费保存值中的固定 offset；Site 数据格式和 IANA 的统一治理仍属于 Site 数据校验层。

工厂文件已加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 Sources build phase。

## 3. 已迁移的 TimeSet 路径

以下当前运行路径已改为统一工厂：

1. 普通 Timed 新增、编辑和启用日程；
2. Group 同步日程；
3. 通用 Node 日程同步；
4. Collection Schedule 批量同步与单条配置；
5. Sync Devices 的时间同步前置任务；
6. Device Restore 和 Group deferred/Fast Add 中的时间同步任务；
7. 首次 Mesh 连接后的 `.allNodes` 自动时间广播；
8. DEBUG 首个日程 Node 单播时间同步；
9. Gateway Fast Add 初始化 TimeSet；
10. Sync Gateways 的 Gateway TimeSet；
11. 当前无运行入口的 Node restore helper，避免未来启用时绕过统一工厂。

旧的 `EmerFireAlarmSyncCellModel.swift` 仍有无参 TimeSet 文本，但该文件未加入四个 App target，线上实现使用共享 `SyncDevicesCellModel`，因此本轮未修改这份失效源码。

## 4. 失败与依赖处理

TimeSet 是 enabled schedule 和 Collection Schedule 的前置条件。若 Site 与手机时区都不能生成可编码 TimeSet：

- 普通 Timed 单设备批次标记失败，不继续写依赖当前时间的 enabled schedule；
- Group、通用 Node restore/sync 只保留不依赖 TimeSet 的日程；
- Collection Schedule 不发送后续 `SchedulerActionSet`；
- Sync Devices、Restore、deferred 和 Fast Add checkpoint 明确记录规划失败；
- 自动 `.allNodes` 广播与 DEBUG 单播只跳过并输出 DEBUG 诊断，不更新自动同步时间戳；
- Gateway Fast Add 不生成 TimeSet 初始化项，但不回滚已经完成的 provisioning。

disabled/delete cleanup 的既有行为不因 TimeSet 失败而被额外阻断。

## 5. SDK 依赖边界

App 当前通过本地 Swift Package 引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。

本次 App 实现依赖该 SDK 工作树中已有、尚未提交的显式时区动态 TimeSet API：

- 显式 `TimeZone` 的动态 TimeSet handle；
- 每次真实 prepare/send 刷新 `Date`；
- 显式 `TimeZone` 的 `syncNodeTime` overload；
- 原无参 API 继续保留兼容行为。

这些 SDK 改动在本轮开始前已存在，本轮没有覆盖、撤回、提交或推送。交付 App 改动时必须同时交付或先落地对应 SDK API，否则 App 不能独立编译。

## 6. 自动验证结果

以下聚焦验证均通过：

- Site TimeSet resolver/factory tests；
- 编译调用点与四 target membership contract；
- Timed single-owner 与时间同步 contract；
- Fast Add task checkpoint 与 dual-scene verification；
- Device Restore transition/time-sync contract；
- Gateway Information、Gateway Fast Add、Sync Gateways 与 no-TimeSet contracts；
- Site timezone value contract；
- SDK explicit TimeSet dynamic provider test；
- App 与 SDK 的 `git diff --check`；
- `SunSmart.xcodeproj/project.pbxproj` 的 `plutil -lint`。

四个品牌 target 均使用 generic iPhoneOS Debug、关闭代码签名直接构建成功：

- `SunSmart`；
- `Archipelago`；
- `SLG Sync Plus`；
- `SylSmart`。

构建仍包含工程已有的弃用 API、重复资源/Compile Sources 和 actor isolation 等 warning，本轮没有扩大范围处理这些既有 warning。

## 7. 尚未覆盖的验收边界

当前证据证明静态契约、聚焦测试和四品牌 iPhoneOS 编译通过，不等同于以下端到端结果：

- 未连接真机验证手机与 Site 不同时区时的实际设备墙上时间；
- 未抓取 BLE/Mesh `TimeSet 0x5C` 和 `TimeStatus 0x5D` 报文；
- 未验证断线、ACK 超时、重试与重新连接时的设备状态；
- 未验证 SQLite 中旧 Site timezone 在 fallback 后保持不变；
- 未验证 Gateway Cloud readback 或服务器同步结果；
- Visitor 的自动 TimeSet 权限边界保持现状，尚未收紧。

建议真机重点覆盖 Site 为有效跨时区值、`nil`、格式错误和 `UTC+08:01` 四类数据，并分别检查设备 offset、当前时间、重试行为以及本地 Site 数据没有被回写。
