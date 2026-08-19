# Site Time Zone 夏令时问题分析与解决方案

## 结论

当前问题的根因不是 `all_utc_timezones.json` 少了一个夏令时布尔值，而是 App 将 JSON 中的静态 `utcOffset` 保存为 Site 的长期业务真值。

正确的数据语义应调整为：

- Site 的长期真值是 IANA 时区标识，例如 `America/Chicago`；
- `UTC-05:00` 或 `UTC-06:00` 是这个时区在某一个具体日期的派生结果；
- UI、Local time、Gateway 待同步判断和 Mesh `TimeSet` 都必须针对同一个目标日期，从 IANA 规则动态计算当前 offset；
- JSON 可继续承担列表分组、搜索和城市元数据职责，但其中的静态 `utcOffset` 不能继续作为运行时真值。

只把 Chicago 在 JSON 中从 `-06:00` 改成 `-05:00` 不能解决问题，因为 2026-11-01 夏令时结束后又会错误。

## 当前源码证据

### 1. JSON 保存的是标准时偏移

`SunSmart/all_utc_timezones.json` 中 `America/Chicago` 为：

- `utcOffset = -06:00`
- `abbr = CST`

这描述的是标准时间，不包含日期规则。

### 2. Catalog 将静态偏移直接构造成 Site 值

`SiteTimeZoneCatalogEntry.value` 直接使用 `ianaId + utcOffset` 创建 `SiteTimeZoneValue`。手机默认时区精确命中 Catalog 时也直接返回该静态值。

因此在 2026 年夏季，即使手机时区是 `America/Chicago`，新建 Site 仍会保存 `America/Chicago (UTC-06:00)`。

### 3. Site 值把 offset 作为固定字段

`SiteTimeZoneValue` 当前包含 `ianaId` 与固定 `offsetMinutes`，并据此完成：

- `displayOffset`；
- `storageValue`；
- Mesh offset 可编码判断；
- `formattedLocalDate`。

`formattedLocalDate` 明确使用 `TimeZone(secondsFromGMT:)`，不会调用 IANA 的夏令时规则。

### 4. TimeSet 同样使用固定 offset

`SiteTimeSetMessageFactory.resolve` 从保存值读取固定 `offsetMinutes`，再创建 `TimeZone(secondsFromGMT:)`。因此 Chicago 夏季向 Gateway 或灯具下发的仍是 `UTC-06:00`。

### 5. 同步状态全部按固定 offset 比较

Site Entry、Review Sync、Sync Gateways、Gateway 云端确认等链路均把 `targetTimeZone.offsetMinutes` 与 Gateway 当前/远端 offset 比较。

因此若只修 Edit Site 显示，系统仍会出现以下不一致：

- 页面显示 `UTC-05:00`，但 TimeSet 下发 `UTC-06:00`；
- Gateway 实际为 `UTC-05:00`，却被判断为待同步；
- Site 云端字符串因季节偏移变化被误判为用户修改了时区。

## Foundation 验证

使用系统 `TimeZone(identifier: "America/Chicago")` 验证：

| 日期 | 系统计算 offset | DST |
| --- | ---: | --- |
| 2026-01-15 | UTC-06:00 | 否 |
| 2026-08-20 | UTC-05:00 | 是 |
| 2026-11-01 06:59:59 UTC | UTC-05:00 | 是 |
| 2026-11-01 07:00:00 UTC | UTC-06:00 | 否 |

Foundation 已提供所需时区规则，不应在 App JSON 中自行维护美国、欧洲等地区的 DST 日期表。

## 推荐数据模型

### 长期身份

以 `ianaId` 作为 Site timezone 的稳定身份和相等判断依据。

例如以下两个值表示同一个 Site 时区，而不是两次用户配置：

- `America/Chicago (UTC-06:00)`
- `America/Chicago (UTC-05:00)`

括号中的 offset 只能视为快照或兼容字段。

### 日期派生值

所有需要 offset 的地方必须显式提供目标日期，再通过 IANA `TimeZone` 计算：

- 当前 UI：以当前 `Date` 计算；
- `TimeSet`：以消息实际生成时的 `Date` 计算；
- Gateway 是否待同步：以本次检查时的同一日期快照计算；
- 未来 DST 切换：以转换发生日期计算新旧 offset。

同一事务必须共享同一个日期快照，避免刚好跨越 DST 切换点时 UI、判断和下发使用不同结果。

### 无效 IANA 的兼容回退

服务器可能已有无法被当前系统识别的 IANA 标识。建议：

- IANA 有效：动态派生 offset；
- IANA 无效但旧字符串 offset 合法：保留固定 offset 兼容行为，并记录诊断；
- IANA 与旧 offset 不一致：IANA 规则优先，旧 offset 仅作为历史快照；
- `Etc/GMT±N` 仍按其 IANA 固定规则处理，不额外套用 DST。

## 云端与本地兼容策略

### 推荐的最终协议

服务器最好将 Site timezone 作为结构化字段保存：

- 稳定字段：`ianaId`；
- 可选诊断快照：`offsetMinutes` 和快照时间；
- 不由服务器把某次 offset 当作时区身份。

如果暂时不能改服务器，第一阶段可继续读写现有 `ianaId (UTC±HH:mm)` 字符串，但业务相等判断只比较规范化后的 `ianaId`，括号 offset 在上传时写入当前日期的派生值。需要注意：这会导致旧版本 App 仍把动态 offset 当固定值，因此 App/服务器/旧版本兼容策略必须在上线前确认。

### 旧数据迁移

不建议启动时批量把所有 Site 标记为用户待同步。建议采用惰性规范化：

1. 读取旧字符串并保留 `ianaId` 与 legacy offset；
2. 运行时动态计算 effective offset；
3. 只有用户实际修改时区，或已有合法 Site props 同步事务时，才回写规范化值；
4. 同一 `ianaId` 的季节 offset 改变，不生成 Site timezone pending，不提升 Site 属性更新时间戳。

## UI 调整边界

### Time Zone 列表

- 列表中的 offset 使用当前日期动态计算；
- 搜索 offset 也应匹配当前动态 offset；
- JSON 静态 offset 可作为额外搜索别名保留，避免用户按标准时偏移搜索不到。

### Edit Site

- 标题继续显示 IANA 名称；
- 右侧 offset 和 Local time 都使用 IANA 时区动态格式化；
- App 进入前台、页面重新可见以及系统时区数据库更新后重新计算；
- 不需要每 0.5 秒重新解析 IANA，只需复用 `TimeZone`，时间文本按现有定时器刷新。

## Gateway 与 Mesh 的关键限制

Bluetooth Mesh 设备当前持有的是数值 offset，不会因为保存了 `America/Chicago` 而自行获得完整 IANA 规则。因此修正 App 计算只解决“本次下发正确”，不能自动保证设备在下一次 DST 切换后自行更新。

当前 SDK 已提供 `TimeZoneSet`，可携带“下一 offset + 生效 TAI 时间”，但当前 App 业务路径主要使用 `TimeSet`，没有建立 DST 未来转换调度。可分两个阶段：

### 第一阶段：当前时间正确

- 所有 `TimeSet` 在消息生成时动态计算 effective offset；
- Site/Gateway 待同步判断使用当前 effective offset；
- App 在进入 Site、连接 Gateway、Proxy Ready、执行 Timed/设备同步时发现季节偏移变化，则提示或执行现有同步流程。

这能保证用户再次使用 App 或重新连接时纠正设备，但不能保证无人打开 App 时按转换点自动切换。

### 第二阶段：转换点自动生效

如果固件完整支持 Time Zone Server 状态与计划切换，可在设备同步时：

1. 下发当前 `TimeSet`；
2. 根据 IANA 规则求下一次 DST transition；
3. 计算 transition 后的新 offset；
4. 下发 `TimeZoneSet`，让设备在指定 TAI 时间切换；
5. 读取 `TimeZoneStatus`，验证 current、next 和切换时间；
6. 每次转换后继续安排下一次转换。

这一阶段必须先用实际 Gateway、灯具和固件确认 `0x823C/0x823D` 的支持、持久化、重启行为和 TAI 语义，不能仅凭 SDK 有消息类型就认定设备可用。

对于持续联网的 Wi-Fi/4G Gateway，也可以由云端按 Site IANA 时区在转换点推送；这比依赖 App 在前台更可靠，但需要服务器和 Gateway 运行时共同支持。

## 建议实施顺序

1. 先修改 `SiteTimeZoneValue` 语义：身份与 effective offset 分离，所有派生 API 接受日期。
2. 修改 Catalog、列表、Edit Site 与 Local time，验证 Chicago 夏季/冬季显示。
3. 修改 Site props 比较与合并：同 IANA、不同季节 offset 不再视为用户配置冲突。
4. 修改全部 TimeSet 工厂和 Gateway pending/confirmation 判断，统一使用同一日期快照的 effective offset。
5. 增加旧格式与无效 IANA 的兼容测试。
6. 完成四个品牌 target 的 iPhoneOS 构建。
7. 再单独评估并实机验证 `TimeZoneSet` 的未来 DST 自动切换能力。

## 必测场景

- Chicago：2026-01-15 为 `UTC-06:00`，2026-08-20 为 `UTC-05:00`；
- Chicago：2026-11-01 转换点前后相差一小时；
- New York、London、Sydney：覆盖不同地区和南半球规则；
- Singapore、Kathmandu、Etc/UTC：无 DST 和 15/45 分钟 offset；
- 同 IANA、旧云端 offset 与当前 effective offset 不同：不产生 Site 属性冲突；
- Gateway 当前 offset 与有效 offset 相同：不显示待同步；
- TimeSet ACK/TimeStatus 返回值与当前 effective offset 一致才成功；
- 无效 IANA + 合法 legacy offset：继续可展示和下发，但有诊断；
- DST 切换时 App 在前台、后台、未运行，以及 Gateway/灯具重启后的行为。

## 仍需产品/协议确认

1. 云端是否允许把 `timezone` 改为只保存 IANA，或增加结构化字段？
2. 是否必须保证 App 未运行时，Gateway/灯具也能在 DST 转换点自动更新？
3. 现有已上线旧版本 App 如何解释服务器返回的动态 offset？
4. 哪些设备型号真实支持并持久化 `TimeZoneSet` 的 future transition？

在这四项确认前，建议先批准第一阶段的“当前 effective offset 正确”改造，不直接假设设备具备自动 DST 调度能力。
