# Site 网关在线状态丢失分析

日期：2026-09-17。范围：分析用户提供的两份 JSON、进入 Site 的日志，并按用户确认实施最小修复。下文根因以修复前 HEAD 为基线；最终修改和验证记录见末节。

## 结论

服务端样本中，Gateway1 / Gateway2 已分别绑定 Space 1 / Space 2，网关和 Space 层的 `gatewayOnline` 均为 `true`。当前代码会先正确接收 Space 网关状态，再在设备归属校验之后用数据库重建的 Space 对象替换它。三个网关字段只保存在内存，数据库读写不包含它们，因此替换后变成 `nil / .notBound / nil`。

这条确定的代码路径能完整解释 All spaces 的 `0 / 0 / 2`、选中网关后的 `Internet Offline` 和 `Last online: --`。页面重新出现时另有一次相同替换，即使只修复导入末尾，返回页面仍会丢失状态。

日志中的 `serverUpdateTimestampNotNewer` 不是直接原因：在线元数据在配置版本比较之前已经应用。`needsRepair=false` 也不会阻止后续无条件重载。

## 分析基线

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-gateway`。
- 分支：`fix-gateway`；HEAD：`76a4e40498a64a8029ec2405ba1bdc75ffcef5cd`。开始分析时工作区干净。
- `SunSmartLocal.xcworkspace` 的 `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD 为 `a971027e08f9775d7a3f071a06f89be1c38ecc96`，读取时无未提交改动。
- 初始根因分析来自样本校验、代码调用链和 Git 历史。实施后已完成相关隔离回归与一次 SunSmart 构建，未连接真机或操作服务端，尚非修复后的运行验收。

## 样本核对

输入：

- [服务端响应](</Users/maginawin/Desktop/tmp/fix gateway server data.json>)。
- [App Site 导出](</Users/maginawin/Desktop/tmp/Site_Fix gateway_20260917_135715_805+0800.json>)。

两份文件的 Site UUID 相同。服务端角色为 owner。

| Space | 对应网关 | gatewayId / MAC | Space gatewayOnline | Gateway gatewayOnline | activate | AppKey index |
| --- | --- | --- | --- | --- | --- | --- |
| Space 1 | Gateway1 | E4768060E1C6 | true | true | true | 1 |
| Space 2 | Gateway2 | D9DFE3287AF4 | true | true | true | 2 |

每组关系均检查了 Space 的 `gatewayId`、网关 `macAddress` / `gatewayId` / `gatewayInfo.gatewayId`、`refSpaces`、`gatewayPreconfigured.associatedSpaces` 和 `subnetAppkeyIndexs`。身份、Space 引用和 Key index 一致；两份文件的 Space 网络密钥、应用密钥也相同，此处不记录密钥值。

服务端 Gateway1 的 `connectAt` 是 `2026-09-17T05:57:25.751Z`，Gateway2 是 `2026-09-17T05:57:30.700Z`；`status` 均为 null，但专门的 `gatewayOnline` 为 true。Space 的 `gatewayLastupdate` 均为 null。当前 UI 不读取网关层的 `connectAt` / `disconnectAt` / `status`。

两份 JSON 中 Space 1 / Space 2 的设备数均为 0、配置时间戳分别为 `1789609650` / `1789609655`；用户日志中的 Space 2 已变为 1 个设备、时间戳为 `1789625063`。导出 `capturedAt` 为 `2026-09-17T05:57:15Z`。因此不能把两份文件和后续日志视为同一时刻的完整快照；该差异不影响网关状态丢失链路的判断。

## 状态如何丢失

### 1. 服务端在线元数据已在版本判断前应用

[ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 `SpaceData.applyRemoteSpaceMetadata`（约 1634–1646 行）读取 Space 的 `gatewayId`、`gatewayOnline`、`gatewayLastupdate`。本样本得到：

- `relevanceGatewayId` = 对应网关 MAC。
- `gatewayStatus` = `.online`。
- `gatewayLastOnline` = nil；在线分支主动清空离线展示用的最后在线时间。

`SpaceData.update` 在约 1666 行调用此方法，配置版本判断在约 1830 行之后。因此日志中的 `.skipped` 只说明配置无需重复覆盖，并不代表在线状态没有读取。

[SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 的 `restoreConfiguration` 对非 rejected 结果调用 `applyConfigurationState(from:)`；该方法明确复制三个网关字段。当前日志的 skipped 路径不会在这里丢失它们。

### 2. 数据库存储不包含三个字段

[SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 定义三个运行期属性，默认分别为 nil、`.notBound`、nil。

[Database.swift](../SunSmart/Common/Data/Database.swift) 中 Space 表字段、`save()` 和 `load(siteId:spaceId:)` 均不包含这三个属性。`load` 会创建新的 `SpaceData`，不会返回原内存对象。即使刚刚调用过 `save()`，新实例仍然没有网关状态。

导出的 `_debugInspection.spaces[].rawLocal.app.spaces[]` 也没有这些列，与代码一致。

### 3. 导入末尾无条件替换在线对象

[ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 Site 更新先合并刚导入的 Space，随后约 911–919 行调用 `SiteDeviceOwnershipReconciler.reconcile`，并对所有 Space 调用 `SpaceData.load` 替换现有对象。

即使归属校验返回空变化集合，重载仍会执行。日志的 `needsRepair=false` 因而不能保护内存状态。重载后的两个 Space 都成为“未绑定”。

### 4. 页面生命周期也会重复丢失

[SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `viewWillAppear`（约 205–208 行）执行相同的全量替换，之后调用 `setupData()`。此外 `spacesRefreshChangeNotificationName` 的 Bool=true 分支约 397 行也直接从数据库重建 Site 的 Space 列表。

Git blame 显示，导入末尾和 `viewWillAppear` 的这两组无条件重载均由 `abfbe5a7`（2026-09-07，`fix: space trigger zone bugs`）引入。父提交没有这两组替换。通知回调的重载路径在此之前已存在。

## 三个现象的对应解释

| 现象 | 代码行为 | 本样本结果 |
| --- | --- | --- |
| All spaces 显示 0 / 0 / 2 | Header 按 `SpaceData.gatewayStatus` 统计在线、离线、未绑定 Space 数量 | 两个对象均 `.notBound`，所以 0 / 0 / 2 |
| 两个网关均 Internet Offline | `loadGatewaysData()` 通过 `relevanceGatewayId == gateway.mac` 找 Space；找不到时，已激活网关回退 `.offline` | 绑定 ID 已丢失，两个已激活网关都走离线回退 |
| Last online 为 -- | 只有匹配到离线 Space 时才从 `gatewayLastOnline` 生成时间；Header 对 nil 使用 `--` | 未找到匹配 Space，时间保持 nil |

相关实现位于 [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `loadGatewaysData()`（约 1502–1524 行）和 Header 配置（约 3460–3484 行）。

注意 All spaces 这里统计的是 Space 数量，并非网关数量。本例一对一，因此正确结果同样应为 `Internet Online: 2 / Internet Offline: 0 / No gateway: 0`；一个网关绑定多个 Space 时两者数量未必相同。

两个网关的 `gatewayPreconfigured.associatedSpaces` 有独立导入、保存和展示路径，所以“可以看到绑定的 Space”与“Space 自身的运行期 gatewayId 丢失”可以同时出现。

## 为什么 Wi-Fi 页面仍显示 Excellent

[WiFiGatewayViewController.swift](../SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift) 的 `applyWiFiRSSIStatus` 使用 BLE/Mesh 回读的 `WiFiGatewayRSSIStatus`：网络状态为 `.normal` 且 RSSI 大于 -60 dBm 时显示 `Excellent`。网络不可用时显示 `No Internet`，未知状态显示 Unknown。

因此这个 Excellent 在当前实现中包含网关报告网络正常和信号强两个条件，与服务端 `gatewayOnline=true` 相符。但它不写回 Site 的 `SpaceData.gatewayStatus`，无法修复被数据库重载清空的 Site 页状态。它也是另一个时刻、另一个来源的观测，不能单独代表持续 MQTT 在线。

## 如何理解 App 导出缺失的网关数据

当前导出是 `localConfigurationInspection`，`uploadable=false`，不等价于完整 `get/siteprops` 响应。

[ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 的 Site 导出不组装 `gateways`；Space 导出不组装 `gatewayId` / `gatewayOnline` / `gatewayLastupdate`。[DebugCloudJSONRecords.swift](../SunSmart/Common/Cloud/DebugCloudJSONRecords.swift) 的 `site()` 只读取 `sites`、`site_extensions`、`meshNetwork` 和 `exclusions`，没有导出网关表及 Site 主网节点。

所以导出中没有 `site.gateways` 不能证明本地网关模型不存在；`siteIssues=[]` 也不是网关在线状态检查通过。原始 Space 数据库记录没有网关字段，可以佐证“这些属性未持久化”，但导出无法直接记录当时页面内存里的在线状态。

## 用户确认的最小修复与验证边界

1. 修复 Space 数据库重载替换时丢失运行期网关元数据的问题。归属校验无变化时保留现有实例；确需重载变化的 Space 时，仅为同一 Site / Space / 网络身份保留有效的三个元数据字段。统一检查导入末尾、页面重新出现、Space 列表通知这三条路径。
2. 保留服务端明确解绑、owner 完整快照的孤儿关联清理、网关删除确认的权威结果，不把旧内存绑定复制回来。也不要用完整 `applyConfigurationState` 覆盖重载对象，否则可能覆盖刚修复的设备计数或配置。
3. 继续让在线状态更新独立于配置 `updateTimestamp`，无需通过强制重导配置或改服务器时间戳来修复本问题。网关层 `gatewayOnline` 的独立展示支持可另行评估，本例 Space 状态已足够，不是必须扩大范围的理由。
4. 覆盖正常在线、真实离线及最后在线时间、同版本配置、归属无变化/有变化、返回 Site、通知刷新、明确解绑和已删除网关。针对当前证据，核心验收是导入后和再次显示页面后仍为 2 / 0 / 0，两个已激活网关分别显示 Online。

已有 `SiteGatewayOnlineStateContractTests` 主要检查源码调用约定，未覆盖“在线元数据导入 → 数据库重建对象 → 页面投影”的行为链。本次补充了执行生产代码片段的行为回归，避免只依赖源码匹配断言。

## 实施与验证结果

修改保持在现有 App 文件内，没有新增数据库字段、SDK API、资源、依赖或工程配置：

- [SiteData.swift](../SunSmart/Common/Data/SiteData.swift) 增加 `reloadSpacesPreservingGatewayMetadata`，供三个入口共用。归属校验只重载发生变化的 Space，通知刷新仍完整更新列表。数据库重载后只保留同一 Site / Space / Mesh / 非空子网身份、正常生命周期的三个网关元数据字段，不覆盖新的设备计数、配置版本或权限。
- [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 与 [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 接入此方法。服务端解绑时同时清空最后在线时间。
- 复用 `GatewayDeletionContext.serverDeletionConfirmed` 检查删除回执；即使归属无变化、沿用当前内存实例，也会清理已确认删除的网关。一次刷新内同一网关只查询一次，保持已有的新网关实例识别规则。
- [状态回归入口](../scripts/check_site_gateway_online_state.sh) 接入新行为回归，并将旧的“四品牌”文件归属检查更新为工程现有的五品牌。没有修改品牌资源或 target 配置。

验证记录：

| 验证 | 结果与边界 |
| --- | --- |
| `python3 scripts/check_site_gateway_metadata_reload.py --revision HEAD` | 修复前生产代码按预期失败，首个失败为同版本在线元数据导入后的 All spaces 无法保持 2 / 0 / 0 |
| `bash scripts/check_site_gateway_online_state.sh` | 关联一致性测试、既有源码约定测试、新增 37 项行为检查以及五品牌文件归属检查全部通过 |
| `python3 scripts/check_gateway_deletion_context.py` | 既有删除回执与本地完成流程回归通过 |
| SunSmart generic iOS Debug | `SunSmartLocal.xcworkspace`、`iphoneos`、`CODE_SIGNING_ALLOWED=NO`，一次构建 `BUILD SUCCEEDED` |
| 真机页面验收 | 未执行，待用户操作 |

[新增回归脚本](../scripts/check_site_gateway_metadata_reload.py) 编译并执行实际生产元数据导入方法、三个重载入口和 Site 状态投影片段，测试夹具见 [SiteGatewayMetadataReloadTests.swift](../Tests/Site/SiteGatewayMetadataReloadTests.swift)。数据库替身每次返回不带网关元数据的新对象；SDK/UI、归属校验结果和删除回执查询为明确的替身边界。它不是完整 App 导入、BLE/MQTT 或 UIKit 运行验收。

本次是五个品牌共用且无品牌条件分支的逻辑修改，选 SunSmart 作为代表构建，未机械重复全部品牌。DerivedData 使用工作树稳定目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-gateway`。SDK 保持上述 revision 且未修改，不涉及远端 SDK 发布待办。

最短人工验收：在两个网关均在线时重新进入该 Site，确认 All spaces 为 `Internet Online: 2 / Internet Offline: 0 / No gateway: 0`；分别选中 Gateway1、Gateway2，均显示 `Internet Online`；进入网关详情后返回，确认状态仍保持。真实离线及断网恢复表现尚待设备环境验收。

交接状态：分支和 HEAD 不变；修改尚未提交。未完成项仅为真实设备页面验收。


## 2026-09-17 14:31 补充：真实离线网关 Last online 缺失

本节针对用户新提供的 `/sitespace/get/siteprops` 响应，仅分析并规划修复，尚未实施。此前末节“未完成项仅为真实设备页面验收”仅适用于在线元数据重载修复；新增 Last online 缺陷另需按本节实施和验证。当前分支仍为 `fix-gateway`，HEAD 为 `76a4e404`；原有三个 Swift 文件、回归入口、未跟踪测试和脚本的修改均保留。本轮只更新本分析文档，没有修改业务代码、SDK 或原有测试。

### 新样本结论

| 对象 | 服务端状态 | 时间来源 | 应展示 |
| --- | --- | --- | --- |
| Gateway1 / Space 1 | 两层 `gatewayOnline=false` | 网关 `disconnectAt=2026-09-17T06:26:52.401Z` | Internet Offline；当前分钟精度下 Last online 为 `2026-09-17 14:26` |
| Gateway2 / Space 2 | 两层 `gatewayOnline=true` | 保留了更早的 disconnectAt，但当前在线 | Internet Online，不显示历史断线时间 |

`Z` 明确表示 UTC。Gateway1 断线时刻是 Unix 秒 `1789626412.401`，按 `site.timezone=Asia/Shanghai (UTC+08:00)` 格式化为 `2026-09-17 14:26:52.401`。App 实际属性名是 `timezone`，不是 `timeZone`。

按“最后保持在线直到断开”的 UI 含义，应使用 disconnectAt；connectAt 是该次连接开始时间，不能替代最后在线。这里表示服务端记录的连接断开时刻，不证明设备在该毫秒物理断电；服务端如何检测断线、是否存在 keepalive 延迟，没有服务端实现或协议证据。网关 `timestamp` 属于另外的设备时间链路，Site/Space `updateTimestamp` 是配置版本，均不能代替 disconnectAt。`status=null`、`utcOffset=null` 不影响本例已经明确的 gatewayOnline 和 Site timezone。

### 已证实的代码根因

1. **字段来源不匹配。** `SpaceData.applyRemoteSpaceMetadata` 只在离线分支读取 `json["gatewayLastupdate"].int64`。新样本的两个 Space 均为 null，所以 Gateway1 得到 `.offline`，但 `gatewayLastOnline=nil`。全 App 查询未发现 connectAt/disconnectAt 的读取逻辑；Site 网关导入负责 Node 和 gatewayPreconfigured 等配置，没有把网关层断线时间传入展示链路。
2. **展示只依赖 Space 时间。** `SiteViewController.loadGatewaysData()` 找到第一个关联 Space 后，仅从 `space.gatewayLastOnline` 生成 `GatewayModel.lastOnlineTime`。Header 对 nil 输出 `--`，所以这份样本即使在线状态保留完全正常，仍会出现 `Internet Offline / Last online: --`。
3. **有时间后仍可能显示错时区。** 这里调用 `String.dateConvert(timestamp:dateFormat:)`，该函数没有设置 formatter.timeZone，默认使用手机时区，没有读取 site.timezone。手机恰好也是 UTC+08:00 时会掩盖这个问题。
4. **两个刷新入口空值不一致。** Header 初次配置用 `lastOnlineTime ?? "--"`，`updateGatewaySyncState` 用 `lastOnlineTime ?? ""`，因此同步状态变化还可能让 `--` 变成空白。这是附带的显示一致性问题，不是服务端时间丢失的原因。

现有未提交修复只解决“已经读到的 Space 网关字段在数据库重载时被清空”。它无法补出根本没有被读取的 disconnectAt。现有行为测试的离线样本人为提供了数字 gatewayLastupdate；日期方法使用返回原时间戳的替身，因此没有覆盖真实 null + ISO 时间组合，也没有验证日期或时区。

### 推荐的最小修复计划

**1. 在 Site 导入中补齐既有关联网关的运行期最后在线时间。**

- 在已有 gatewayDicts 入口构造同一 Site 响应内的网关时间索引，按规范化 gatewayId/MAC 匹配 Space.relevanceGatewayId。复用现有 MAC trim/大小写规则；同一记录身份冲突或重复记录冲突时不要任意取最后一项。
- 在 Space 成功导入、关联合法性清理完成后、最终重载之前，将匹配网关的合法 disconnectAt 填入离线 Space.gatewayLastOnline，复用当前运行期字段和重载保留机制。写入在 MainActor 上完成；不把补充逻辑放进并行 Space 任务中共享可变状态。
- 优先使用匹配且明确离线的网关 disconnectAt；没有合法新字段时保留既有合法 gatewayLastupdate 兼容路径；两者皆不可用则 nil。对空间/网关状态冲突，不从 disconnectAt 推断在线状态或覆盖当前绑定规则，不使用该冲突记录的历史时间。
- 解析支持带毫秒与不带毫秒的 ISO 8601，以及显式时区偏移。解析为绝对 Date，再规范化为现有 Int64 Unix 秒；保留当前分钟精度，无需为毫秒新增数据库字段。非法时间不得回退为 Date() 或零时间。
- 时间补齐独立于配置 updateTimestamp 和网关配置 dirty 合并结果；同版本的在线状态刷新仍需生效。在线、解绑和确认删除继续清空时间。owner 完整快照清理、editor/visitor 部分快照和删除回执保护维持现有语义；不得用网关列表重新创建不可见或已删除的 Space。

**2. 展示时显式使用 Site 时区。**

- 复用 SiteTimeZoneValue 对完整 timezone 字符串的解析；沿用当前工程的固定 offsetMinutes 语义，创建对应 TimeZone 后格式化 Last online，保持 `yyyy-MM-dd HH:mm`。
- 先解析 UTC/带偏移输入为绝对时间，仅在格式化时应用 Site 时区；不得先给 timestamp 加八小时再交给带时区 formatter，以免重复偏移。
- 当前 SiteTimeZoneValue.formattedLocalDate 的格式与此处不同；可以给已有格式化入口增加显式时区能力或增加局部参数化方法，不全局改变其他页面的默认时区行为。
- 缺失/无效 Site timezone 的旧数据，建议沿用现有 GatewayDetailTimeZoneResolver 的手机时区回退约定；配置了合法 Site timezone 时必须使用 Site。
- 编辑 Site 时区后重新生成 Last online 字符串并刷新相关 Header。原始 Unix 时间不变；核对 siteDidChange 与返回页面两条路径，避免保存的是格式化字符串而显示停留在旧时区。
- 现有项目仍采用固定 UTC offset；`docs/260820_0414_site_timezone_dst_solution_analysis.md` 讨论的 IANA/DST 迁移尚未体现在当前实现。此修复沿用现有产品规则。若要求历史日期遵循城市夏令时，应将其纳入已记录的统一时区方案，避免只在此标签引入不同语义。上海样本两种规则结果一致。

**3. 统一 Header 缺省值。**

- 初次配置和同步状态刷新都使用 `--`。在线分支不显示历史 disconnectAt，断线时间缺失时也不显示 connectAt、当前时间或上次格式化残留。
- 本次没有新增用户可见文案，复用 last_online 国际化 Key。

**4. 扩展现有行为回归，再构建一次 SunSmart。**

- 使用脱敏最小夹具覆盖本次真实组合：gatewayOnline=false、gatewayLastupdate=null、disconnectAt 含毫秒；验证导入后的时间值和 Header 文本。
- 覆盖新字段优先、旧数字字段回退、空值/非法值、无毫秒与显式偏移，以及在线响应仍带旧 disconnectAt。
- 覆盖同版本配置刷新、在线→离线→在线、同网关多个 Space、MAC 大小写、关联冲突、解绑/删除和三条重载路径。
- 日期回归直接执行实际解析/格式化代码；覆盖手机 UTC / Site +08:00、负偏移跨日、非整点偏移、Site 时区编辑后重算和缺时区回退，不再用返回原始时间戳的替身代替格式化验证。
- 复用现有状态/删除相关回归；生产 Swift 修改完成后，用映射核对后的 SunSmartLocal workspace 执行一次 SunSmart generic iOS Debug 构建。若只改共享逻辑且没有品牌编译差异，无需重复五品牌构建；若新增文件或工程归属，再核对所有受影响品牌配置。

范围说明：以上最小方案覆盖本样本及既有关联 Space 的网关。当前 UI 通过关联 Space 决定网关状态，因此“没有任何可见关联 Space，但 gateways 中有离线时间”的网关不能由这个桥接方案完整覆盖。若该场景也纳入本次需求，应改为 Site 持有按网关身份索引的运行期状态/时间，并让网关卡片直接投影该状态；这涉及状态来源优先级与生命周期，需作为明确扩展项规划，不能仅把时间写入稍后会由数据库重建的 GatewayModel。无需为解决本样本先重构整个状态模型。

### 本轮验证与待办

- 已只读核对导入、Space 重载保留、GatewayModel 数据库重建、Header 两个入口及 Site timezone 实现。
- 临时 Foundation 验证执行当前 SiteTimeZoneValue 与 String+Date 生产源码：Site 格式化结果为 `2026-09-17 14:26:52.401`；手机默认时区设为 UTC 后，现有 helper 输出 `2026-09-17 06:26`。仅启用 withInternetDateTime、不启用毫秒支持的 ISO8601DateFormatter 无法解析本样本。
- 未修改生产代码，未运行 App 构建或真机。本轮日期验证不能替代修复后的完整数据链路测试。
- 实施后最短人工验收：刷新 Site，Gateway1 显示 Internet Offline / Last online: 2026-09-17 14:26，Gateway2 显示 Internet Online；进入详情再返回、触发同步状态刷新后文本保持；手机使用不同于 Site 的时区时仍按 Site 显示。恢复在线后隐藏旧 Last online。


## 2026-09-17 14:39 Last online 修复实施与验证

用户已确认按上述最小方案修复。本节覆盖前一节的“尚未实施”状态。

### 最终改动

- 在已有 `SiteGatewayAssociationConsistencyPolicy.swift` 中增加 `SiteGatewayLastOnlineSnapshot`，解析同一 Site 响应内明确离线网关的 disconnectAt，兼容带毫秒、不带毫秒和显式 offset。网关 ID/MAC 统一去空白、忽略大小写；冲突身份或冲突重复记录不产生断线时间，相同重复记录允许继续。无效日期不回退为当前时间或 epoch。
- Site 导入在关联清理完成后，对本次成功导入、属于当前 Site 且正常/离线的 Space 补齐时间，再走既有重载保留及删除回执校验。补齐发生在 MainActor，独立于配置版本和网关配置上传状态。旧 gatewayLastupdate 保留秒/毫秒兼容并规范化为 Unix 秒；非正值保持未知。
- 在已有 `SiteTimeZoneValue` 增加网关 Last online 格式化入口，显式使用 Site 固定 offset 和 Gregorian 日期、`yyyy-MM-dd HH:mm` 格式；缺少有效 Site timezone 时使用手机时区。未修改现有 Local time 和 TimeSet 方法。
- Site 网关投影按规范化关联 ID 匹配，先清除旧展示时间，再按最新状态重建；两个 Header 更新入口均使用 `--`。Site 属性编辑回调调用既有 setupData，确保时区改变后重建展示字符串。
- 扩展现有 `SiteGatewayMetadataReloadTests` 和运行脚本，直接执行生产快照解析、元数据补齐、重载和日期格式化；不再用原时间戳字符串替代实际日期显示。测试进程用 `TZ=UTC` 提供可验证的不同手机时区。Foundation 的 NSTimeZone.default 不会改变 TimeZone.current，测试夹具已改用进程环境，没有为此修改生产回退行为。

没有新增生产文件、数据库字段、SDK API、资源、文案或依赖；修改的两个共享辅助文件原本已加入全部五品牌 Sources，工程归属保持不变。无关联 Space 的网关仍维持前述范围边界。

### 验证结果

| 检查 | 结果与边界 |
| --- | --- |
| `bash scripts/check_site_gateway_online_state.sh` | 既有关联一致性及源码约定检查通过；扩展行为回归共 76 项通过；五品牌已有文件归属检查通过 |
| `python3 scripts/check_gateway_deletion_context.py` | 通过，确认删除回执保护没有回归 |
| `zsh scripts/check_site_timeset_message_factory.sh` | SiteTimeSetMessageFactoryTests 与 SiteTimeZoneValueTests 通过，现有固定 offset 规则保持 |
| SunSmart generic iOS Debug | 使用 SunSmartLocal.xcworkspace、SunSmart scheme、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO，一次构建 BUILD SUCCEEDED |
| 真机 / UIKit 实际体验 | 未执行，待用户验收 |

首次用 bash 调用上述 zsh 专用 TimeSet 脚本时因 `${0:A:h:h}` shell 语法报错；按脚本 shebang 改用 zsh 后通过，不涉及源码修正。扩展行为测试使用真实生产片段和 SwiftyJSON/日期实现，SQLite、SDK、UIKit 和删除回执仍是明确的替身边界，不等同整 App 运行验收。

### 交接

- 分支仍为 `fix-gateway`。实施期间上一轮在线状态保留修复已由外部操作提交为 `da03fb6b`；本轮增量基于该 HEAD，尚未提交。
- 当前增量为 ImportData、SiteGatewayAssociationConsistencyPolicy、SiteTimeZoneValue、SiteViewController、现有行为测试及脚本，以及本文档。没有覆盖前一轮修改。
- SDK 来源：`.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `a971027`，核对时无未提交差异，本轮未修改，无远端 API 发布待办。
- 构建复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-gateway`；仅共享逻辑变化、没有品牌条件编译差异，选 SunSmart 代表构建。
- 最短人工验收：刷新样本 Site，Gateway1 应为 Internet Offline / Last online: 2026-09-17 14:26，Gateway2 为 Internet Online；进入详情返回、同步状态刷新后保持；手机时区与 Site 不同时仍按 Site 显示；修改 Site 时区后时间重算，网关恢复在线后隐藏历史 Last online。
