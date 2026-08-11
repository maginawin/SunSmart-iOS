# 设备 timestamp 与 timezoneOffset 更新链路分析

## 结论

- 设备返回 `TimeStatus` 后，SDK 立即把其中的时间和时区写入 Node，并调用 `savePropertys()` 更新本地 Node 属性表。
- 单纯收到 `TimeStatus` 不会直接创建云同步任务，因此不能据此认为服务器已经更新。
- 当后续发生 Space、Site 或 Gateway 云同步时，导出 Node JSON 才会把当前缓存的 `timestamp` 和 `timezoneOffset` 带到服务器。
- 从服务器下载并导入 Space 或 Gateway Node JSON 时，这两个字段也会反向写入本地 Node 数据库。

## 属性说明与换算

### timestamp

`timestamp` 来自设备返回的 `TimeStatus.time.seconds`，单位为秒。它表示设备在本次 `TimeStatus` 中报告的时间快照，不是普通的 Unix 时间戳，也不一定是生成或导出 JSON 的时间。该值保存后不会在 App 数据库中自行递增，只有收到新的 `TimeStatus` 或重新导入服务器 Node 数据时才会被替换。

SIG Mesh SDK 将该字段定义为从 `2000-01-01 00:00:00 TAI` 起累计的秒数。当前项目发送 `TimeSet` 时采用简化实现：使用当前 Unix 时间戳减去 `946684800`，并把 `taiDelta` 设为 `0`。因此解释当前 App 生成并保存的设备数据时，应采用以下项目换算公式：

- Unix 时间戳（秒）= `timestamp + 946684800`
- `timestamp` = Unix 时间戳（秒）`- 946684800`

这套项目公式没有单独计算 TAI 与 UTC 的闰秒差。若分析其他严格按照完整 TAI/UTC 规则生成的数据，不能直接假设仍适用该简化公式。

### timezoneOffset

`timezoneOffset` 是 SIG Mesh 的固定 UTC/GMT 偏移编码，不是分钟数，也不是 `Asia/Singapore`、`Asia/Shanghai` 等 IANA 时区标识。它不包含地区信息和未来夏令时规则。

- 编码步长：15 分钟，即 900 秒
- 零偏移基准：`0x40`，十进制为 `64`
- UTC 偏移秒数 = `(timezoneOffset - 64) × 900`
- UTC 偏移分钟数 = `(timezoneOffset - 64) × 15`
- UTC 偏移小时数 = `(timezoneOffset - 64) ÷ 4`
- `timezoneOffset` = UTC 偏移分钟数 `÷ 15 + 64`

将两项合并后，按当前项目规则计算设备当地墙上时间：

- 当地时间对应的秒值 = `timestamp + 946684800 + (timezoneOffset - 64) × 900`

实际使用 `DateFormatter` 等日期 API 时，应先用 `timestamp + 946684800` 得到绝对时间，再为格式化器设置解码后的时区；不要既手动加偏移，又让格式化器再次应用相同时区。

### 示例

设备 JSON：

- `timestamp = 839656755`
- `timezoneOffset = 96`，即十六进制 `0x60`

换算结果：

- Unix 时间戳：`839656755 + 946684800 = 1786341555`
- UTC 时间：`2026-08-10 05:59:15 UTC`
- UTC 偏移：`(96 - 64) × 15 = 480 分钟 = UTC+08:00`
- 设备当地时间：`2026-08-10 13:59:15 UTC+08:00`

`timezoneOffset = 96` 只能说明偏移为 `UTC+08:00`，无法仅凭该值判断设备属于新加坡、中国或其他采用相同偏移的地区。

## App 本地数据库更新时间

### 设备响应路径

App 或 SDK 向支持 Time Setup Model 的设备发送 `TimeSet`。设备返回 `TimeStatus` 后：

1. `time.tzOffset` 写入 `node.timezone`。
2. `time.seconds` 写入 `node.timestamp`。
3. 调用 `savePropertys()`。
4. Node 属性表中的 `timezoneOffset` 与 `timestamp` 随即更新。

当前会发送 `TimeSet` 的主要业务场景包括：

- 新增、配置或恢复设备时执行时间同步任务。
- 新增、修改或启用需要设备执行的日程时，在日程消息之前同步时间。
- 同步采集日程时。
- WiFi Gateway 成为当前 Proxy 且会话匹配、Key Bind 完成并存在 Time Setup Model 时；同一 Proxy 会话只执行一次。
- 调试入口广播同步所有设备时间。

只要收到合法 `TimeStatus`，SDK 的统一消息处理都会保存，不要求响应一定来自某一个特定页面。当前源码未发现业务代码主动发送 `TimeGet`。

### 服务器导入路径

下载 Space 或 Gateway Node JSON 时，如果 `timezoneOffset` 可解析为 `UInt8`，并且 `timestamp` 是大于等于零的整数，导入逻辑会赋值给 Node；随后把 Node 加入 Mesh Network 并保存到本地数据库。

## 服务器更新时间

收到 `TimeStatus` 并调用 `savePropertys()` 只更新本地 Node 属性表，同时刷新 Node 的本地 `lastUpdateTime`。该回调目前只用于清除设备同步状态缓存，没有直接调用 `CloudSynchronizationManager`。

服务器真正更新发生在以下云同步操作导出 Node JSON 时：

- `syncSpace`：通过 Space Upload 上传 Space 中的节点。
- `syncSite` 或首次 `siteAdd`：仅当本次同步包含对应 Space 时，节点才会随 Space 数据上传。
- `syncGateway`：Gateway Register 直接导出对应 Gateway Node。

Node JSON 只有在 `node.timezone` 非空时才同时写出 `timezoneOffset` 和 `timestamp`。

### 常见业务表现

- 日程或设备配置同步完成后通常会发送 Space 数据变更通知；设备类型变更使用 `promptly`，云同步等待时间为 0 秒。因此在网络正常、权限允许且请求成功时，这两个字段会随本次 Space 上传更新到服务器。
- WiFi Gateway 页面在 Proxy Ready 后完成 `TimeSet`/`TimeStatus`，只会立即更新本地 Node 数据。该完成回调不会自行触发 Gateway Register，因此服务器不会仅因这次自动校时而立即更新；需要等待后续 Gateway 数据变更、Gateway 注册，或其他包含该 Node 的云同步。
- 如果没有后续云同步、用户没有 Owner/Editor 权限、网络不可用或请求失败，服务器值可能继续保持旧数据。

## 关键源码证据

- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift:191-196`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift:712-722`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/TimeMessage.swift:39-55, 97-126`
- `nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift:1215-1226, 1316-1317`
- `SunSmart/Common/Data/ImportData.swift:1205-1207, 1399-1410, 1835-1837`
- `SunSmart/Common/Data/ExportData.swift:262-264, 699-701`
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:73-96, 127-150`
- `SunSmart/Main/Space/Controller/SpaceViewController.swift:60-116, 583-590`
- `SunSmart/Main/Device/Gateway/Model/WiFiGatewayTimeSyncCoordinator.swift:108-151, 184-190`
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:234-253`
