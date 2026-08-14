# Site Sync Gateways 需求完整性分析

## 结论

当前需求已经覆盖主要页面状态和核心交互，但还不能直接进入实施计划。UI 状态、排序、15 秒 RSSI 失效和单网关串行同步已经较完整；真正缺失的是同步成功的业务真值、云端回写边界、页面数据快照来源、取消语义，以及若干异常状态。

本轮只做源码、Figma 和协议路径分析，不修改业务代码。

## 已核对的现状

### 入口与现有页面

- `SyncGatewaysViewController` 已经创建，但目前只有标题和白色背景，尚未实现页面、扫描和同步逻辑。
- Site 页 `Review sync` 组件已经可以 push 空的 `Sync gateways` 页面。
- `Sync status` 弹窗的 `REVIEW SYNC` 当前只关闭弹窗，没有进入 `Sync gateways`，与本次需求不一致。
- 当前未提交改动还包含 Site 首次时区检查、Review sync 组件、双 Header 布局、国际化和契约测试；后续实施必须在这些改动上增量开发，不可覆盖或重做。

### Figma 状态

已通过 Figma 结构化设计核对以下节点：

- 主页面、全部网关在附近、部分网关在附近。
- 无 Nearby gateway 提示。
- 单个 Gateway 的 Syncing、其他按钮 disabled、Retry、Synced。
- 失败 Toast、成功 Toast、顶部进度变化。

Figma 页面可以归纳为四个固定区域：Site time zone 卡片、On-site sync 提示、动态 Gateway Sections、固定 Bottom Action Bar。Nearby 和 Other 是同一批目标 Gateway 根据运行时状态推导出的两个投影，不应维护两份可互相漂移的数据。

### Site 与 Gateway 数据

- `SiteEntryTimeZoneSyncResponseParser` 当前只保留远端 Gateway 的标准化 MAC 和 `timezoneOffset`，数组顺序仍然存在，但没有保留 Gateway 名称和其他展示字段。
- 本地 `GatewayModel` 提供名称、MAC、Mesh 地址和运行期 Node；数据库查询没有显式排序，不能用本地加载顺序代替 `site.gateways` 的服务器顺序。
- 因此页面输入必须保留远端 Gateway 数组顺序，再按标准化 MAC 关联本地 `GatewayModel` 和 Node。
- Owner、Editor、Visitor 的可见范围应继续复用现有 Review policy：Owner 使用全部 Gateway；Editor 只使用 Editor Space 绑定的 Gateway；Visitor 不应进入该页面。

### App Site time zone 与 Cloud Site time zone

不能简单假定任意时刻 `app.site.timezone` 都必然等于本次可信的 `cloud.site.timezone`：

- `SiteData.update(siteJsonData:)` 只有在服务器 `updateTimestamp` 大于本地 `site.lastUpdate`，或初始化时，才用服务器值覆盖本地 Site 属性。
- Site 入口协调器还可能判定使用本地值并上传服务器，或使用服务器值覆盖本地。
- 页面 Review 状态当前保存的是本次协调后的可信 `serverTimezone` 和待同步数量，但没有保存完整 Gateway 列表。

推荐方向不是在目标页面再次二选一读取原始 App 或 Cloud，而是在 Site 入口协调完成后构造不可变的 `SyncGatewaysContext`。Context 中的 target time zone 使用本次已解析并确认的 Site time zone；正常情况下它应与 `app.site.timezone` 一致，若不一致则不允许静默启动同步，应重新协调或拒绝进入。

换言之：业务语义可以采用 App 已协调后的 Site time zone，但实现上应把它作为进入页面时的明确快照传入，不能在同步过程中反复读取可变的 `site.timezone`，也不能持有过期的原始 cloud response。

### BLE 扫描与连接

- 现有 SDK 的 `refreshNodesRSSI(withWaitFor:nodeScan:finished:)` 可以持续扫描已入网 Node，并回传 Node、Peripheral 和 RSSI。
- 该扫描器是 `MeshLibManager` 的全局单例能力；开始新扫描会停止既有 RSSI 扫描，退出页面也必须只结束本页面拥有的会话并忽略迟到回调。
- 已有 `connectProxy(node:peripheral:result:)` 可以使用扫描得到的 Peripheral 连接指定 Gateway。
- 连接与页面持续扫描共用底层蓝牙管理器，实施时需要定义“连接前暂停页面扫描、连接完成后恢复扫描”的会话边界；是否能在 Mesh 消息发送期间并行扫描仍需真机验证。

### 时间与时区消息

- 当前 `Node.setLocalTimeMessage()` 创建标准 SIG `Time Set`，Opcode 为 `0x5C`，消息本身同时包含当前时间和 time-zone offset，并等待 `Time Status`。
- 当前实现固定使用 `Date()` 和 `TimeZone.current`，不能满足“使用 Site target timezoneOffset”的要求。
- 标准 `Time Zone Set`，Opcode 为 `0x823C`，只设置将来生效的时区偏移，不会同时刷新当前日期时间；仅发送它不满足需求。
- 推荐使用一个显式传入 `Date` 与 Site target fixed offset 的 `Time Set`，以一个 `Time Status` ACK 作为 BLE 事务结果。这样可同时更新网关日期时间与时区，并避免两个 ACK 事务产生部分成功状态。
- Site 的目标 offset 应按 `SiteTimeZoneValue.offsetMinutes` 创建固定 GMT offset，不应在发送瞬间重新使用手机 `TimeZone.current`。

## 推荐状态模型

每个目标 Gateway 只保存一份状态，Section 和 Cell 由状态推导：

- 同步状态：pending、syncing、failed、synced。
- 邻近状态：last RSSI、last seen monotonic time、Peripheral。
- 展示规则：未同步且 15 秒内有 RSSI 的 Gateway 位于 Nearby；未同步但无有效 RSSI 的 Gateway 位于 Other；synced 永远位于 Other，但仍持续刷新 RSSI。
- syncing Gateway 在事务结束前固定保留在 Nearby，避免扫描短暂中断导致 Cell 跨 Section 跳动。
- Nearby 按远端 `site.gateways` 顺序。
- Other 先显示未同步，再显示 synced；两个分组内部都按远端顺序。
- 同一时刻最多一个 syncing；其他 Nearby action disabled。

## 需要补齐的业务口径

### 1. 同步成功真值与云端回写

当前最关键的缺口。需要明确：

- 收到 Gateway 的 `Time Status` 是否立即算成功并增加顶部进度；还是必须继续把新的 `timezoneOffset` 更新到云端并等待服务器成功响应。
- 如果 BLE 成功但云端更新失败，Cell 应显示 Synced、Retry，还是新的“等待云端”状态。
- 如果不由 App 写云端，Gateway 是否会通过 MQTT/其他既有链路自行上报，以及页面何时认定云端已收敛。
- Site 页的 Review sync 状态何时减少或隐藏；只更新当前页面内存会导致下次刷新仍按旧 cloud offset 再次提示。

### 2. 页面输入快照与刷新

- 进入页面后是否固定使用进入时的 Site/Gateway 快照，还是需要继续请求 `siteInfo` 刷新云端状态。
- 页面停留期间 Site time zone 如果在其他入口发生变化，当前任务应取消还是继续使用进入时快照。
- 远端 Gateway 有记录但本地缺少 GatewayModel/Node 时，名称、地址和可同步性如何展示。

### 3. 取消语义

- Back、侧滑返回和 Done 都应停止扫描、失效 15 秒计时器、取消等待回调并断开本页主动连接的 Gateway。
- 已经发到 Mesh 的 `Time Set` 无法撤回；退出后只能忽略迟到 ACK，禁止它继续更新已销毁页面或弹 Toast。
- 需要明确退出后是否恢复进入页面前的自动 Mesh 连接状态。推荐只断开本页主动切换的 Proxy，然后恢复 SDK 的正常自动连接。

### 4. 异常状态

至少还需定义：

- Bluetooth 未授权、关闭或 SDK 当前不能扫描。
- connect timeout、Time Status timeout、Gateway 缺少 Time Setup Model、Gateway 不支持指定 Proxy 连接。
- 扫描中 App 进入后台再回前台。
- 当前 target Gateway 在同步过程中被移出 Site 或失去 Editor 权限。
- 初始目标数量为 0，或打开页面前云端状态已经全部完成。

### 5. 文案冲突

- Figma 失败 Toast 是 Gateway-specific 文案，成功 Toast 是 Gateway time-zone-specific 文案。
- 需求文字要求复用 `Sync failed. Please retyr.` 和 `Site updated.`，但当前工程已有的 `sync_failed` 只有 `Sync failed`，没有 `Please retry`；`site_updated_toast` 是 `Site updated.`。
- 后续计划必须以产品确认的最终英文为准，并同步简体中文。不能同时声称复用旧 Key 又使用 Figma 的不同文案。

## 初步验证边界

实施后至少需要：

- 纯状态机测试：Section 投影、排序、15 秒失效、串行同步、Retry、进度和退出失效。
- Parser/Context 测试：权限范围、MAC 去重、远端顺序、本地关联缺失、Site time zone 一致性。
- 协议构造测试：目标 fixed offset、当前 Date、Time Set 参数和 Time Status 成功条件。
- Source/UI 契约：两个入口、国际化、四 target 文件引用、Toast 和页面清理。
- 四品牌 generic iPhoneOS Debug build。
- 真机专项：持续 BLE 广播、连接目标 Gateway、Time Set/Time Status、RSSI 15 秒切换、后台恢复、退出时取消、Gateway 或云端最终状态。静态测试和构建不能替代这部分验收。

## 当前待确认的第一项

收到 Gateway 的 `Time Status` 后，是否还必须由 App 调用服务器接口写回该 Gateway 的 `timezoneOffset` 并等待成功，才计入 `updated`；还是 BLE ACK 即计入成功，云端由 Gateway 的既有上报链路最终同步？

## 2026-08-13 补充决策：BLE 成功与云端收敛分层

### 产品状态

采用“有效 `Time Status` + 本地持久化成功即设备 Synced”的口径，不等待云端响应：

- `Time Status` 必须包含非零时间，并且返回的时区 offset 与本次 Site target offset 一致；只判断消息类型不足以证明写入正确。
- 使用响应中的 `TimeStatus.time.seconds` 和 `TimeStatus.time.tzOffset` 更新本地 Node。这里的 `timestamp` 是从 2000-01-01 起算的 Mesh TAI seconds，不是 Unix timestamp。
- 本地 Node 保存成功后，Cell 进入 Synced、顶部 updated 立即加一、显示成功 Toast。
- 云同步失败不得把 Cell 改回 Retry，因为 Retry 的含义是重新执行 BLE；此时 Gateway 设备已经完成更新。

### 本地脏标记

现有 SDK 在处理任意 `TimeStatus` 时已经会更新 `node.timezone`、`node.timestamp` 并调用 `savePropertys()`；后者还会更新 Unix seconds 语义的 `node.lastUpdateTime`。页面同步协调器仍应拿到 typed `TimeStatus` 并显式校验结果，避免当前只用 `response is TimeStatus` 的宽松成功条件。

Gateway 云同步还需要独立的 durable marker：

- 将 `GatewayModel.lastUpdate` 单调递增为 `max(now, lastUpdate + 1, lastUploadCloudTimestamp + 1)`，不能直接写当前秒数，否则同一秒内可能仍被判定为不需要上传。
- 保存 GatewayModel 后再入云同步队列。
- 云成功只更新 `GatewayModel.lastUploadCloudTimestamp` 并清理 cloud error；云失败保留 dirty marker，供后续重试。

### 上传接口核对

当前源码与“像其他 Node 一样直接走 `/sitespace/sync/siteprops`”并不一致：

- `/sitespace/sync/siteprops` 对应 `.syncSite`，上传 Site 属性及可选 Spaces；Gateway 不属于 Site export 的顶层输出。
- Space export 会包含普通 Node，但不能据此保证顶层 Gateway 会通过 Site props 正确更新。
- 当前 Gateway 的既有上传操作是 `.syncGateway(gateway:node:)`，它导出完整 Gateway Node 与 `gatewayPreconfigured`，实际调用 `/sitespace/sapce/gateway/regist`，并以 `GatewayModel.lastUpdate` 作为服务器更新版本。
- 该链路已经用于 Gateway restore 与 firmware update 后的 Gateway 数据回写，因此从当前客户端结构看，它比泛化的整 Site `/sync/siteprops` 更符合既有边界。

推荐优先复用 `.syncGateway`，但需要服务器契约确认 `/sitespace/sapce/gateway/regist` 对“已存在 Gateway 的 Node 属性更新”是幂等 upsert，并会持久化 `timezoneOffset` 与 `timestamp`。如果服务器明确要求 `/sitespace/sync/siteprops`，则应先补充专门的 Gateway payload 契约；不能直接调用现有 `.syncSite` 并假设顶层 Gateway 字段会被上传。

**已确认决策：** 直接复用现有 `.syncGateway(gateway:node:)`，云端接口固定为 `/sitespace/sapce/gateway/regist`；不使用 `/sitespace/sync/siteprops` 上传本次 Gateway time-zone 变更。

### 云重试与再次进入 Site

当前 `CloudSynchronizationManager` 在 Gateway 上传失败后会移除同步 Handle，只留下 `GatewayModel.needUploadCloud` 和错误；工程中没有通用的 Gateway dirty 自动重放逻辑。本功能需要补齐：

- 网络恢复、本页面后续操作或再次进入 Site 时，重新 enqueue dirty Gateway。
- 同一 Gateway 的云请求合并，使用最新的 `lastUpdate` 和 Node export。
- 再次进入 Site 计算 Review 状态时，应合并 cloud snapshot 与可信本地 dirty 状态。如果本地 Node offset 已等于当前 Site target，且该 Gateway 正在等待云上传，就不能再次要求用户执行 BLE。
- 页面 `updated` 和 `still need attention` 只统计设备同步状态；cloud pending 不计入需要用户到现场处理的数量。

### 推荐分层状态

每个 Gateway 同时维护两个相互独立的轴：

- Device sync：pending、syncing、failed、synced。
- Cloud sync：clean、pending、uploading、failed。

UI Cell 的 Sync、Syncing、Retry、Synced 只由 Device sync 驱动。Cloud sync 复用现有 Site/Gateway 云错误呈现或后台重试，不在该 Cell 中伪装成 BLE 失败。

**已确认决策：** BLE 已成功而 `.syncGateway` 云上传失败时，Cell 仍保持 Synced，进度仍计入成功，不显示本页失败 Toast；保留 Gateway dirty 状态供后续重试。

## 2026-08-13 补充分析：Site、Gateway 与 Node 时间戳边界

### 当前源码行为

`.syncGateway` 使用的是 `GatewayModel.lastUpdate`：

- 请求参数 `updateTimestamp` 取自 `gateway.lastUpdate`。
- 请求成功后只把 `gateway.lastUploadCloudTimestamp` 更新为 `gateway.lastUpdate`，并保存 GatewayModel。
- 不会修改 `SiteData.lastUpdate` 或 `SiteData.lastUploadCloudTimestamp`。
- 当前响应解析只消费 MQTT authorization 字段，没有消费服务器 Site update timestamp。

`TimeStatus` 使用的是 Mesh Node 数据：

- SDK 收到 `TimeStatus` 后更新 `Node.timezone` 与 `Node.timestamp` 并调用 `savePropertys()`。
- `Node.timestamp` 是 Mesh TAI seconds；`GatewayModel.lastUpdate` 和 `SiteData.lastUpdate` 是 Unix seconds 语义的业务版本。三者不能混用。
- App 数据模型没有 `SiteData.gateways` 数组属性。服务器 `site.gateways[*].timestamp/timezoneOffset` 在本地对应 Mesh Network 中的 Gateway Node，并通过独立 GatewayModel 关联，而不是写入 SiteData 内的列表。

### 不建议直接更新 `app.site.updateTimestamp`

Gateway register 可能在服务器内部推进父级 Site 的 `updateTimestamp`，但客户端不能用 `gateway.lastUpdate` 猜测服务器最终的 Site timestamp：

- 两者可能不是同一个版本值。
- `SiteData.update(siteJsonData:)` 只有在远端 Site timestamp 大于本地 Site timestamp 时才覆盖 Site name、image、timezone 等父级属性。
- 如果客户端提前把 `SiteData.lastUpdate` 抬高到一个未经服务器确认的值，下一次权威 Site 快照可能因为不再满足 `remote > local` 而无法应用。
- 修改 `SiteData.lastUpdate` 还可能令 `site.needUploadCloud` 变为 true，意外触发整 Site 上传。

因此 Gateway 更新成功后不应直接修改 `SiteData.lastUpdate`。本地立即更新的对象应限定为 Node 与 GatewayModel；Site 页面内的 Review 进度使用本次任务状态即时更新。

### 推荐收敛方式

- 每个 Gateway BLE 成功后立即更新 Node，并推进 `GatewayModel.lastUpdate`，enqueue `.syncGateway`。
- `.syncGateway` 成功后只确认该 Gateway 的上传版本。
- 一批 Gateway 云请求结束后最多执行一次 `/sitespace/get/siteprops`，获取服务器权威的 Site timestamp 与完整 Gateway snapshot，再沿用现有 `SiteData.update(siteJsonData:)` 合并。
- 不为每个 Gateway 单独刷新 Site，避免多余请求和页面抖动。
- 如果服务器未来在 gateway register 响应中返回权威完整 Site/Gateway 版本，也只能按服务器返回值合并，不能用客户端 Gateway timestamp 推导 Site timestamp。

### `.syncGateway` 现有并发版本风险

当前 `GatewayServerAuthorizationService` 会按 `siteId + gateway.mac` 合并进行中的请求，而 `CloudSynchronizationHandle` 成功时读取的是可变的 `gateway.lastUpdate`。如果旧请求进行期间同一 Gateway 又发生新变化，新调用可能 join 旧请求，随后错误地把最新 `lastUpdate` 标记为已上传。

本功能计划需要将请求版本快照化：

- 入队时捕获 `requestedUpdateTimestamp`。
- 成功只把 `lastUploadCloudTimestamp` 推进到该请求实际提交的版本。
- 完成后若 `gateway.lastUpdate > uploadedVersion`，再次 enqueue 最新 Gateway 数据。
- 不能让旧请求的成功确认覆盖更新后的 dirty 状态。

### 服务器契约补充

用户已确认 `/sitespace/sapce/gateway/regist` 请求体中的 `updateTimestamp` 在服务器端没有任何作用，不参与覆盖、冲突检测或版本判断。因此：

- 方案不再把该参数描述为服务器 Gateway 版本。
- 不使用它推导或更新服务器与 App 的 Site `updateTimestamp`。
- 现有 `GatewayModel.lastUpdate/lastUploadCloudTimestamp` 如继续保留，只作为客户端 dirty generation 与重试确认标记。
- 并发安全仍需要捕获客户端请求 generation 或 payload snapshot；原因是要避免旧请求完成后错误清除较新的本地 dirty 状态，与服务器是否读取 `updateTimestamp` 无关。

**已确认决策：** 一批 Gateway 云请求结束后最多静默刷新一次 `/sitespace/get/siteprops`，通过权威快照更新 Site 与 Gateway；不直接修改本地 `SiteData.lastUpdate`。

## 2026-08-13 补充决策：退出后的迟到 Time Status

- Back、侧滑返回或 Done 均立即停止页面扫描、15 秒 RSSI 计时、尚未发起的连接/同步步骤以及所有 UI 回调。
- 如果 `Time Set` 尚未发送，则取消后不产生同步结果。
- 如果 `Time Set` 已经发送，消息无法从设备侧撤回；页面退出只结束展示任务，不阻断底层事务收敛。
- 退出后收到与本次 target offset 匹配的有效 `Time Status`，仍完成 Node 本地持久化并 enqueue `.syncGateway`，但不得更新已关闭页面、改变已释放的 Cell/进度或显示 Toast。
- 超时、无 ACK、无效时间或 offset 不匹配均不认定成功。

## 2026-08-13 补充决策：Gateway 同步 Toast

- 只复用现有 `ToastStatusView` 的样式、位置和动画，不复用 `site_updated_toast` 或现有通用失败文案。
- 失败英文为动态 Gateway 名称插值：`Gateway name sync failed. Try again.`
- 成功英文为动态 Gateway 名称插值：`Gateway name time zone updated.`
- 实际展示时用当前 Gateway display name 替换 `Gateway name`。
- 新增参数化国际化 Key，并同步 English、简体中文；不得拼接多个已翻译片段。
- Toast 只对应 BLE/Time Status 结果；后台 `.syncGateway` 的失败不显示本页 Toast。

## 2026-08-13 补充决策：同步期间扫描与 RSSI 失效计时

- 用户点击某个 Gateway 的 Sync 或 Retry 后，暂停实际的全局 BLE RSSI 扫描，再进入该 Gateway 的连接与 Time Set 事务；避免扫描与 Proxy 连接竞争同一个 BLE manager。
- 暂停期间冻结所有 Gateway 的 RSSI 展示和 15 秒无信号计时，不得因为 App 主动暂停扫描而把其他 Gateway 判为 No signal。
- 正在同步的 Gateway 保持在 Nearby gateways，Cell 显示 Syncing；其他 Nearby Gateway 的 Sync 按钮保持不可用。
- 本次事务以成功、失败或超时收敛后，恢复 BLE RSSI 扫描，并从暂停前的累计值继续计算无广播时长。
- 15 秒阈值只累计“扫描实际处于运行状态”的时长；累计满 15 秒仍未收到该 Gateway 广播时，才将其判为 No signal。未同步 Gateway 随即从 Nearby gateways 移到 Other gateways；已同步 Gateway 留在 Other gateways 并更新为 No signal 展示。
- 页面中的旋转搜索图标可以在同步期间继续显示，表达整个 Sync gateways 任务仍在进行；它不作为底层扫描当前一定处于运行状态的技术指示器。
- Back、侧滑返回或 Done 会结束扫描会话并清除冻结的计时状态，不在页面退出后恢复扫描。

## 2026-08-13 补充决策：采用独立状态机与协调器架构

采用方案 A，将页面展示、任务状态、BLE 扫描、单 Gateway 时间同步和云端回写拆分为边界明确的组件：

- `SyncGatewaysContext`：进入页面时生成的不可变任务上下文，保存 Site 标识与名称、目标时区快照、需要同步的 Gateway 清单以及云端 `site.gateways` 原始顺序。
- 页面状态模型：为每个目标 Gateway 保存设备同步状态、云同步状态、RSSI/最后发现时间和当前 Peripheral；统一派生 Nearby、Other、顶部进度、attention 数量和按钮可用性。
- 扫描会话：独占本页面的 BLE RSSI 扫描生命周期，处理开始、暂停、恢复、有效扫描时间累计、15 秒 No signal 转换和页面退出清理。
- 时间同步协调器：串行处理单 Gateway 的扫描暂停、连接、显式时间与目标 offset 写入、typed `Time Status` 校验以及成功/失败/超时收敛；同时保留页面退出后已发送事务的迟到响应收敛能力。
- Gateway 云同步桥接层：在 BLE 成功并完成本地 Node/GatewayModel 持久化后复用 `.syncGateway`，按请求 generation 确认 dirty 状态，并在本批云请求收敛后合并为最多一次权威 Site 快照刷新。
- `SyncGatewaysViewController`：只负责 UIKit 视图构建、状态渲染、用户事件转发、Toast 展示和页面关闭，不直接持有 Mesh 事务规则。

该方案避免把扫描回调、15 秒计时、页面生命周期、BLE ACK 与云上传结果集中到 ViewController，也不把时区同步耦合进 Gateway OTA 专用流程。

### 已确认的数据与展示真值边界

- `SyncGatewaysContext` 在 Site 数据协调完成后创建，使用当时有效的 `app.site.timezone` 作为不可变任务快照；若 App 与最新 Cloud Site timezone 不一致，则先刷新并重新协调，不静默选择一方继续同步。
- 只有进入页面时 `timezoneOffset` 与目标不一致的 Gateway 才进入本次任务。原本已经一致的 Gateway 不计入进度，也不展示在 Nearby 或 Other；本页内同步成功的 Gateway 仍保留在任务中并移动到 Other。
- 每条 Gateway 状态同时保存稳定身份与云端顺序、device sync、cloud sync、RSSI/Peripheral/有效未发现时长以及同步 attempt 标识。
- Nearby、Other、顶部进度、attention 数量和按钮可用性全部由页面状态模型派生；数据库模型、BLE 回调与 ViewController 不得各自维护独立的 UI 真值。
- Nearby 为未同步且有有效信号的 Gateway，正在 Syncing 的 Gateway 固定保留在其中；Other 先展示未同步且 No signal 的 Gateway，再展示已同步 Gateway，各组均保持云端顺序。
- 任一 Gateway 处于 Syncing 时，其他 Sync/Retry 按钮不可用。Cloud sync 状态不改变 Nearby/Other、设备进度或 BLE 按钮状态。

### 已确认的扫描与单 Gateway 同步事务

- 页面级扫描会话只处理本次目标 Gateway；发现时更新 RSSI 与 Peripheral，并将该 Gateway 的有效未发现时长归零。所有回调携带会话标识，旧会话或已关闭页面的回调不得改变状态。
- No signal 使用单调时钟并只累计实际扫描时间。failed Gateway 丢失信号后进入 Other，再次发现时回到 Nearby 并保持 Retry；已同步 Gateway 始终留在 Other，只更新 RSSI 或 No signal 展示。
- Sync/Retry 开始时先将目标置为 Syncing，再暂停实际扫描、冻结所有 RSSI 失效计时并连接目标 Gateway。
- Time Set 在即将发送时读取 App 当前 `Date`，使用任务上下文中的目标 offset，不能使用 `TimeZone.current`，也不能只发送 Time Zone Set。
- 只有 typed `Time Status` 中时间有效且 offset 与目标一致才成功。成功后立即持久化目标 Node 的 `timestamp/timezoneOffset`、更新设备进度并显示动态成功 Toast；随后推进 GatewayModel dirty generation 并异步 enqueue `.syncGateway`。
- 连接、发送、超时、无效时间或 offset 不匹配均进入 failed 并显示动态失败 Toast。事务收敛并释放连接资源后立即恢复扫描，不等待云上传。

### 已确认的退出生命周期与云端收敛

- Done 与导航栏 Back 在关闭页面前执行幂等 finish；侧滑返回只在交互式转场确认完成后 finish，取消手势不得误停扫描。不能依赖 `deinit` 或普通 `viewWillDisappear` 作为唯一退出边界。
- finish 立即停止扫描、RSSI 计时和尚未发送 Time Set 的事务，并拒绝后续 UI 更新与 Toast。
- Time Set 已发送时，页面与 attempt 解绑，但底层事务可以在原定超时内收敛。有效匹配的 Time Status 仍持久化 Node 并 enqueue `.syncGateway`；attempt 超时或终止后的旧回调一律忽略。
- `.syncGateway` 入队时捕获 payload/generation；成功只确认实际提交的 generation，发现更新 dirty generation 时继续 enqueue。失败保留 dirty，不回退设备状态，也不显示本页失败 Toast。
- 网络恢复、再次进入 Site 或后续相关操作会重试 dirty Gateway。同一批云请求收敛后最多静默刷新一次 `/sitespace/get/siteprops`。
- 权威快照可覆盖已经 clean 的 Gateway；对于仍处于本地 dirty 的 Gateway，保留本地已经由有效 Time Status 确认的 `timestamp/timezoneOffset`，避免旧云数据重新触发现场同步。
- 不直接修改 `SiteData.lastUpdate`；`gateway/regist` 请求中的 `updateTimestamp` 不参与服务器版本判断，只保留客户端 generation 语义。

### 已确认的页面组件、入口与国际化

- `Sync status` 弹窗的 `REVIEW SYNC` 与 Site 页 `Review sync` 组件统一调用同一页面构建/路由方法；前者先关闭弹窗再 push，二者共享 `SyncGatewaysContext` 构建口径。
- Site time-zone 卡片使用参数化的 Site 名称 + 本地化 time-zone 标题、快照化 `UTC±HH:mm` 和本次目标 Gateway 的设备进度。目标数为 0 时不应进入页面。
- On-site sync Alert 固定展示 Figma 内容，优先复用现有主题、图标和组件。
- Nearby Header 的搜索图标在页面任务存续期持续动画；无 Nearby 时显示 Figma 空态文案，不新增手动 Rescan。
- Other 先显示未同步且 No signal 的 Gateway，再显示 Synced Gateway；attention 使用剩余数量插值，全部完成时隐藏。无 Cell 且无 attention 时隐藏整个 Section。
- Bottom action bar 固定于安全区底部，内容独立滚动。Done 始终可用，执行 finish 后关闭页面，不要求全部完成。
- Toast 只复用 `ToastStatusView` 视觉样式；成功与失败使用带 Gateway display name 的完整参数化国际化 Key。English 与简体中文同步维护，不拼接翻译片段。
- 共享 UI、资源、本地化和工程文件引用需同步检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。
