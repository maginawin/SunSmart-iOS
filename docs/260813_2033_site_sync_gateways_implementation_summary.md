# Site Sync Gateways 实施总结

## 交付范围

- `Sync status` 弹窗与 Site `Review sync` 组件统一进入 `Sync gateways` 页面。
- 页面使用进入时冻结的 Site timezone 与 Gateway 目标集合，目标总数只统计 timezone offset 尚未更新的 Gateway。
- 持续通过 BLE 扫描目标 Gateway，按 Site Gateway 顺序展示 Nearby 与 Other；15 秒有效扫描时间未收到 RSSI 后回落为 `No signal`。
- 单次只允许一台 Gateway 执行同步；写入内容包含 App 当前日期时间与目标 timezone offset，并以匹配的 typed `Time Status` 作为设备成功依据。
- Device 成功后立即持久化本地 Node 的 `timestamp`、`timezone`，更新页面进度和分组，并显示 Figma 指定 Toast 文案。
- 云端回写复用 `.syncGateway` 与 `/sitespace/sapce/gateway/regist`，不等待云端完成即可计为 Device `Synced`；客户端使用 generation 防止并发回写丢失更新。
- Done、Back、完成的侧滑返回与前后台切换统一清理扫描和页面生命周期；已经发出的 Time Set 仍允许迟到 `Time Status` 完成本地持久化与云端入队。
- 新增文案已同步 English 与简体中文；新增共享源码已加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## 关键口径

- 页面展示与 BLE 目标使用 `app.site.timezone`，进入前要求其与最新 cloud Site timezone 一致。
- `Synced` 的真值是有效、非零且 offset 匹配的 `Time Status` 加本地 Node 持久化成功，不等待 HTTP/MQTT 云端收敛。
- `gateway/regist` 的 `updateTimestamp` 不作为服务器业务字段，仅用于 App 本地 dirty generation；不联动修改 `SiteData.lastUpdate`。
- Toast 只复用现有 `ToastStatusView` 的 `.siteUpdate` 样式，文案为 `%@ sync failed. Try again.` 与 `%@ time zone updated.`。

## 验证结果

- `./scripts/check_site_sync_gateways.sh`：全部通过，覆盖 Context、权限范围、状态机、RSSI、BLE attempt、generation、Cloud Bridge、入口、UI、国际化与既有 timezone contract。
- `plutil -lint SunSmart.xcodeproj/project.pbxproj`：通过。
- `git diff --check`：通过。
- iPhoneOS generic build：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 均通过。
- SDK standalone `ExplicitTimeSetInputTests`：通过。
- `NordicSigMeshDemo` iPhoneOS generic build：通过。

## 尚需真实环境验收

- 真机连续扫描、RSSI 变化与 15 秒 `No signal` 转移。
- 真实 Gateway 连接、完整时间与 timezone offset 写入、typed `Time Status`、失败 Retry 和退出后的迟到响应。
- `/sitespace/sapce/gateway/regist` 对 `timestamp`、`timezoneOffset` 的真实服务器持久化，以及离线重试、并发 generation 和重新进入 Site 后的最终收敛。
- 四品牌 App 的最终视觉、动态字体、安全区和 Toast 位置。
