# Edit Site 修改时区后出现 3 个网关任务：分析记录

日期：2026-09-23。工作树：`sun-smart-worktrees/fix`，分支 `fix`。初次分析 HEAD `e3856fc4`，新样本复核 HEAD `425d0a27`。

## 结论

**实施状态（2026-09-23）：A+B+C+D 已落地。用户反馈“测试没有问题”，15:44:32 的新导出确认本地 gateways 从 3 条变为 0 条；本次现场问题验收通过。实现、自动化验证及现场导出核对见文末。**

15:07 的新导出已确认：该 Site 的本地 `gateways` 表恰好保留 3 条网关记录，对应主网络 Node 全部不存在，Edit Site 时区同步仍把它们纳入任务。三条记录 lastUploadCloudTimestamp 都为 null，命中了现有远端导入清理的保留条件。可以确定当前任务来源；仍不能仅凭快照还原三条记录当年如何产生、是否经过完整删除操作。

已经证实的实现缺口：Edit Site 以本地 GatewayModel 构建候选，不检查 Node 是否存在；Owner 权限直接放行。Node 不存在导致时区未知，进一步被判为需要同步。普通 Site 网关列表却要求 Node 存在，因此出现“列表看不到、时区同步仍有任务”的不一致。任务入口未排除删除状态也是现状，但新样本的三条持久化待删除标记均为 0，不应再把它作为这次已证实原因。

初次分析仅运行隔离复现并增加本文档；没有修改业务代码、连接服务器或操作真机。随后按用户要求扩展了诊断导出，见末节。任务开始前已有 Database、SpaceSyncCleanupCoordinator、ProfilePersistence 等 6 个文件的未提交修改，保持原样。

## 首轮样本事实与局限

输入文件：

- `/Users/maginawin/Desktop/tmp/lan/site from server 0923.json`
- `/Users/maginawin/Desktop/tmp/lan/Site_5楼测试_20260923_143925_989+0800.json`

两份文件的 Site UUID 相同，名称均为“5楼测试”。

| 检查项 | 服务器回复 | 本地导出 |
| --- | --- | --- |
| Site 角色 | `owner` | 原始 sites 行 permission 为 1 |
| 网关 | `data.gateways = []`，明确空数组 | `site` 无 gateways 字段；原始诊断数据也没有 gateways 表 |
| Space 数量 | 8 | 8 |
| Space 网关关联 | 8 个 gatewayId 均为空字符串 | 导出业务数据未包含 gatewayId，不可据此判断实际运行关联 |
| 时区 | America/Argentina/Catamarca，UTC-03:00 | Africa/Abidjan，UTC+00:00 |
| Site updateTimestamp（UTC+08:00） | 2026-09-23 14:44:02 | 2026-09-23 14:37:59 |
| 导出捕获时间（UTC+08:00） | 未提供请求日志时间 | 2026-09-23 14:39:25 |

服务器样本与本地导出不是同一时刻、同一次时区修改后的同步快照，不能仅据时区不同判定同步失败。但两者足以明确：这份服务器网关列表并未提供 3 个网关。

服务器“5楼”Space 仍带有 2026-07-21 的 gatewayLastupdate，而 gatewayId 已为空。这与历史上存在网关关联相容，但既不能证明删除事件，也不能确定曾有 3 个网关。

本地导出缺项是当前导出范围所致：[SiteData.export](../SunSmart/Common/Data/ExportData.swift) 不导出 Site 网关集合；[DebugCloudJSONRecords.site](../SunSmart/Common/Cloud/DebugCloudJSONRecords.swift) 只读取 sites、site_extensions、meshNetwork、exclusions，未读取 gateways、Site 主网络 nodes/nodePropertys 或删除回执。不能把“导出没有网关”解释为“本地数据库没有网关”。

## 任务生成链路

1. [SiteEditViewController.finishTimeZoneCommit](../SunSmart/Main/Site/Controller/SiteEditViewController.swift) 创建 SiteTimeZoneEditSyncCoordinator，并注入 SiteGatewayLocalTimeZoneContextBuilder.make。
2. [SiteTimeZoneEditSyncCoordinator.run](../SunSmart/Main/Site/Model/SiteTimeZoneEditSyncCoordinator.swift) 先提交 Site 属性，再调用 makeTargets。这里没有先取得完整 get/siteprops 并以其网关集合过滤本地候选。
3. [SiteGatewayLocalTimeZoneContextBuilder](../SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneLocalContext.swift) 对 GatewayModel.load(siteId:) 的所有记录执行 map。resolveNode 返回 nil 不会排除候选，只会得到 currentOffsetMinutes=nil。
4. [GatewayModel.load 与数据库字段](../SunSmart/Common/Data/Database.swift) 仅按 Site/可选 MAC/地址查询，不过滤 serverDeletionPendingLocalReset，也不要求 Node 存在；原先的 Node 存在检查已经是注释。
5. [SiteData.canConfigureGateway](../SunSmart/Main/Device/Gateway/Model/GatewayModel.swift) 对 Owner 直接返回 true；这是权限判断，不是有效注册或删除状态判断。
6. [SiteGatewayLocalTimeZoneTargetBuilder](../SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift) 过滤无权限、空 MAC，并按规范化 MAC 去重。其余候选均成为目标；未知 offset 与目标 offset 不同，因此 requiresSync=true。
7. [批次状态](../SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneSyncState.swift) 为每个目标生成显示项，把 requiresSync=true 的 MAC 放入请求集合。提交成功后经 [APIClient](../SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneAPIClient.swift) 请求 `/sitespace/gateway/datetime/update`。

因此，若现场 App 运行此版本、画面确为上述结果列表，则 3 项意味着该次构建读到了至少 3 个可配置且规范化 MAC 不同的本地候选；不是一个 MAC 被大小写或重复数据库行扩成三项。现场没有提供 datetime/update 请求记录，不能据 UI 单独断言服务器实际创建了 3 个任务：Site 提交失败时也会用本地候选生成失败结果列表。

另一个入口 [SiteGatewayCloudTimeZoneTargetBuilder](../SunSmart/Main/Site/Model/SiteGatewayCloudTimeZoneTarget.swift) 对 Owner 使用远端 gateways 集合。对本次服务器样本，其目标数量为 0。两条入口使用不同数据来源。

## 为什么删除过的记录可能仍在

[SiteData.update 的网关清理](../SunSmart/Common/Data/ImportData.swift) 在 Owner、存在且可解析的完整 gateways 快照、主 Mesh Network 可加载的情况下，只清理同时满足以下条件的本地记录：

- lastUploadCloudTimestamp 非 nil，表示曾有成功上传记录；
- 服务器当前集合不含此 MAC；
- serverDeletionPendingLocalReset 为 false；
- GatewayDeletionContext.hasPendingDeletion 为 false。

这意味着“服务器为空”不会无条件清空本地 gateways。需要区分以下来源：

| 候选来源 | 如何残留 | 与时区任务的关系 |
| --- | --- | --- |
| 删除已到服务器、本地收尾失败或中断 | pending 标记/删除回执使导入清理保留，等待专门恢复流程 | 本地时区候选没有对应排除条件 |
| 旧记录 lastUploadCloudTimestamp 为 nil | 为保护新入网但尚未上传的合法记录，导入不直接删除 | 即使 Node 已缺失，仍进入候选并被视为未知时区 |
| 完整远端快照尚未完成导入，或数据库删除失败 | 本地表仍保留旧行 | Edit Site 自身不等待完整网关对账，读到旧行即可生成任务 |

普通的“曾成功上传、无待删除状态、完整 Owner 空快照已导入且删除成功”记录，本应被现有清理删除。因此不能只用“以前添加过”解释持续复现；应定位上述保留条件中的哪一个实际命中。

[GatewayDeletionContext.complete](../SunSmart/Main/Device/Gateway/Model/GatewayDeletionContext.swift) 先清理 Mesh Node，再处理 App 数据库内关联与 GatewayModel。后段失败时，代码确实允许出现 Node 已消失、GatewayModel 暂时仍在的状态，并保留回执供恢复。此处说明可达机制，不代表样本已证实发生过该失败。

[SiteViewController.loadGatewaysData](../SunSmart/Main/Site/Controller/SiteViewController.swift) 使用 compactMap 丢弃无 Node 的模型，而时区入口使用 map，这解释了两处 UI 可以看到不同数量。

## 隔离复现与证据边界

使用当前生产文件的真实解析器、两种 TargetBuilder 和 BatchState 编译执行临时 Swift 探针：`/tmp/site_gateway_timezone_0923_probe.swift`。

- 实际服务器 JSON → Owner 远端候选数量为 0。
- 3 条模拟本地候选，权限允许、MAC 不同、offset=nil → 显示 3 项，待请求 MAC 数量为 3。
- 对照：offset 已一致无需请求；无权限不产生目标；重复规范化 MAC 不扩增目标。

以上运行成功，验证的是目标生成机制。模拟 MAC 不来自现场数据库，不能用于确定真实三个网关。未运行完整 App 构建、UI、真实数据库删除恢复或网络请求验证；纯分析不需要 App 构建。

## 首轮建议与补证（已由末节新样本方案收窄）

1. 时区任务入口增加有效生命周期判断，排除已确认服务器删除、正在删除或待本地删除完成的记录。保留删除回执和恢复数据，不为隐藏任务直接删除它们。
2. 对仅本地存在且 Node 缺失的孤立记录，不因未知时区直接推导为有效同步对象。结合完整 Owner 网关快照确定有效对象；不能把缺字段、失败响应或 Editor/Visitor 的裁剪结果当权威空列表。
3. 追查残留本身的来源，再决定是否需要修复清理流程。不能删除全部 lastUploadCloudTimestamp=nil 的记录，否则会误伤新入网尚未注册成功的合法网关。
4. 当前最小补证是读取该 Site 的 gateways 安全字段（名称、MAC、地址、lastUpdateTimestamp、lastUploadCloudTimestamp、serverDeletionPendingLocalReset、syncCloudError），主网络 Node 是否存在及其身份匹配结果，以及删除回执阶段。无需导出任何密钥、MQTT 凭据或账号 Auth。
5. 对照该次 `/sitespace/gateway/datetime/update` 的 gateways 数组与 UI 名称，才能把“3 项”关联到具体历史设备，并区分只生成本地结果行还是已经实际提交云端请求。

若实施修复，直接覆盖：有效已注册网关、待注册新网关、无 Node 孤立记录、服务器已删除但本地待收尾、Owner 权威空快照，以及非 Owner/不完整快照。现有 LocalTimeZoneTarget 测试覆盖未知时区需要重试，却不区分“有效网关但未知时区”和“无效残留对象导致未知时区”，需要在上下文/生命周期入口补覆盖。

## 后续实施：补齐诊断导出（2026-09-23）

用户选择先补导出、再用真实数据定位。本轮只扩展 [DebugCloudJSONRecords](../SunSmart/Common/Cloud/DebugCloudJSONRecords.swift)，没有改变时区任务生成或网关清理行为。

完成时分支仍为 `fix`，HEAD 已由外部提交推进到 `425d0a27`（收录任务开始时的既有修改及初次分析文档）；本轮没有执行提交。本轮未提交内容为导出读取器、对应测试和本文档补充。

Site 页 Export JSON 的 `_debugInspection.rawSite` 新增：

- `gateways`：当前 Site 的数据库原始行，含名称、MAC、地址、关联 Space、上传时间、同步错误和 serverDeletionPendingLocalReset；不要求对应 Node 存在。
- `primaryMesh.meshUUID`、`primaryMesh.networkId`：本次主网络读取范围。
- `primaryMesh.nodes`：该 Site 主网络的节点原始行。
- `primaryMesh.nodePropertys`：主网络属性原始行，含 timezoneOffset、timestamp；独立读取，保留 Node 已缺失时的孤立属性行。
- `omittedColumns`：明确列出本次新增数据排除的凭据列：gateways 的 mqttServerInfo、registrationProtectionSnapshot；主网络 nodes 的 deviceKey；主网络 nodePropertys 的 gatewayInfo、enOceanProxySwitchKeys。

仍按当前 Site/主网络范围只读导出，不通过模型解码过滤坏数据；数据库存在但查询失败时抛错，不伪装成空数组。沿用已有快照版本检查。Space 单独导出的范围及用于服务器对照的 `site` 主体不变。

验证：

- `python3 scripts/check_debug_json_export.py` 通过，新增真实 SQLite 夹具覆盖孤立/待删除网关、损坏关联 Blob、主网与其他子网隔离、孤立属性、时区、凭据排除、不写数据库、旧库缺表及查询失败。
- `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / generic iOS / 无签名编译通过，DerivedData 为 `SunSmart-fix-cli`。首次沙箱调用无法正常打开 workspace，允许沙箱外执行后编译成功。
- SDK 映射核对为 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `ebbe1c9`，SDK 无未提交修改；未增加 SDK API 依赖。
- 五品牌共用这段逻辑，没有品牌条件或资源/工程配置改动，本次以 SunSmart 为代表构建。未安装或运行真机。

人工下一步：使用本轮版本，从“5楼测试”的 Site 页面执行 Export JSON（不是 Space 单独导出），保留问题现场后发来新文件。如果可同时取得相近时间的 get/siteprops，可以对照本地残留与服务器当前集合。新增数据可判断本地记录、主网 Node、待删除标记是否一致；本轮未增加删除回执导出，若标记与 Node 仍不足以定位收尾失败，届时再定向补该证据。

## 新样本复核与待确认修复方案

新文件：`/Users/maginawin/Desktop/tmp/lan/1508 Site_5楼测试_20260923_150725_525+0800.json`，capturedAt 为 2026-09-23 15:07:25（UTC+08:00）。本轮按用户要求只分析与规划，未修改业务代码；保留上一轮的导出增强及对应测试。

### 确认的数据

| 网关 MAC | 地址 | 主网络对应 Node | lastUploadCloudTimestamp | 待本地删除标记 |
| --- | --- | --- | --- | --- |
| CC9E27179B40 | 47 / 0x002F | 不存在 | null | 0 |
| E2F54FDEECEB | 53 / 0x0035 | 不存在 | null | 0 |
| F1ADFFA8B2C7 | 38 / 0x0026 | 不存在 | null | 0 |

三条记录均 name=Gateway、activate=0、lastUpdateTimestamp=1、associatedSpaces=[]、syncCloudError=null。主网络 nodes 和 nodePropertys 各只有手机地址 0x0001 一条记录，没有任何网关；8 个 Space 的导出节点中，也没有匹配上述地址或 MAC 的记录。

本地 Site 时区已为 America/Argentina/Catamarca (UTC-03:00)，Site updateTimestamp 和 lastUploadCloudTimestamp 均为 1790145842，pendingSitePropsMask=0。与此前服务器样本的 Site UUID、时区和 updateTimestamp 一致。此前服务器样本 gateways=[]，8 个 Space 均无 gatewayId；本轮未重新访问服务器，不把旧文件描述成实时响应。

### 闭合的因果链

1. 当前网关显示要求 GatewayModel 能在 Site 主网络中解析到 Node，因此这三条记录不显示。
2. Edit Site 使用本地表记录作为候选，Node 解析失败仅得到 nil 时区；Owner 权限允许，三个 MAC 各不相同，均通过候选过滤。
3. nil offset 与任意有效目标时区不相等，三个候选全部成为待同步目标。是否由 UTC+00:00 改为 UTC-03:00不是关键；任何有效新时区都会触发相同问题。
4. Owner 完整空网关快照的清理要求 lastUploadCloudTimestamp 非 nil。这三行均不满足，所以即使服务器已无网关，仍不会由该分支清理。

三条记录的“Gateway / lastUpdateTimestamp=1 / uploadTimestamp=null”与数据库旧表升级默认值吻合：name 缺列时填 Gateway，lastUpdateTimestamp 缺列时填 1，lastUploadCloudTimestamp 新增列默认空。因此更接近旧数据遗留，而不是可以直接断言“刚才删除到一半”。这只是历史来源线索，不能证明迁移或删除发生的具体时间；null 也不等于历史上从未成功注册。

### 推荐方案：让本地时区目标采用网关列表的 Node 存在条件

本次授权待确认的目标是：App 与服务器均无可见网关时，不生成同步网关时区任务。推荐按已证实原因做以下最小修复：

1. 在 `SiteGatewayLocalTimeZoneContextBuilder.make` 组装候选时明确记录“能否在该 Site 主网络解析到 Node”；在现有 `SiteGatewayLocalTimeZoneCandidate` 增加该条件，由 `SiteGatewayLocalTimeZoneTargetBuilder` 与权限、MAC 过滤一起执行。候选必须有对应 Node 才能成为目标，与 Site 列表的有效对象条件一致。这样可直接对生产筛选策略增加行为测试，而非只匹配源码字符串。
2. 保留有效 Node 的未知时区重试：Node 存在但 timezone 尚未读取时，仍应同步；不能把所有 nil offset 都当作应跳过。
3. 复用现有空目标流程：Site 属性照常保存/提交，网关结果行数量为 0，不调用 `/sitespace/gateway/datetime/update`，也不调用 `/sitespace/request/status`。结果页沿用既有 `site_no_gateways` / `site_no_gateways_sync_needed` 空态，不产生这三个网关的失败或重试项。
4. 保留数据库记录和现有上传/清理条件。删除 lastUploadCloudTimestamp=nil 的记录可能误伤真实新入网尚未上传的网关，不需要为了本次任务筛选去扩大删除规则。
5. 现有服务器驱动的 Owner 时区入口以远端 gateways 为候选，空数组本身已生成 0 个目标。此次不增加新的 get/siteprops 请求，也不把缺失字段、网络失败或非 Owner 裁剪列表推断成“没有网关”。

实施文件预计为 `SiteGatewayCloudTimeZoneLocalContext.swift`、`SiteGatewayCloudTimeZoneTarget.swift` 及相关现有 Tests/Site 测试；如运行脚本需要新增测试入口，沿用 `check_site_sync_gateways.sh`。不改 SDK、不增加依赖或新框架。

### 验证与验收

本轮已经执行：

- 临时探针 `/tmp/site_gateway_timezone_1508_probe.swift` 从真实导出读取三条记录与主网 Node 集合，投影为当前生产 TargetBuilder/BatchState 的输入：现行规则得 3 个任务、3 个请求 MAC；加入 Node 存在前置条件后得 0 个任务、0 个请求 MAC。此验证执行了真实目标策略，但并未运行完整 App 数据库加载链。
- 现有 `SiteTimeZoneEditSyncCoordinatorTests` 通过，其中空目标用例验证 Site 更新完成后网关 submit/status 均为零次调用。
- 未改业务代码、未运行本轮 App 构建或真机操作；上轮构建通过仅证明导出增强可编译。

确认实施后覆盖：

| 场景 | 预期 |
| --- | --- |
| 三条本地网关行，主网只有手机，Owner 远端空列表 | 0 个目标；Site 更新继续；无网关 update/status 请求 |
| 一个有效主网网关 + 三条孤立记录 | 仅有效网关进入任务 |
| Node 存在但时区未知 | 保留同步任务 |
| Node 存在且时区相同 | 不发送该网关时区更新 |
| Node 存在、uploadTimestamp=null 或 activate=false | 不仅因上传/激活标记而排除，保持真实新网关兼容 |
| MAC 重复、无配置权限、非 Owner 角色 | 保持现有去重与权限边界 |

运行相关目标策略/协调器回归与一次 SunSmart Debug generic iOS 构建。人工验收：在这份数据对应的 Site 修改时区并 Sync，Site 更新成功，结果为空网关状态，无 3 条 Gateway 同步任务或等待超时；再用有正常网关的 Site 确认原同步路径仍可用。

该节为第一版候选筛选方案。用户随后要求评估孤立记录清理，最新建议见下一节；尚未实施任务筛选或数据清理。

## 8 个场景 × 8 个维度：清除无 Node 网关记录的范围评估

复核日期：2026-09-23 15:19（UTC+08:00），HEAD `425d0a27`。用户倾向清理无意义的本地记录，要求先全面分析、再决定范围。本轮只更新本文档并执行既有隔离测试，没有改业务代码或真实数据库。

### 结论调整

赞成清除已确认孤立的 GatewayModel，而不仅是隐藏其时区任务。需要先区分“原始数据库确认不存在 Node”和“当前模型没有解析到 Node”：后者还可能由读错误、错误子网、正在导入、入网保存失败或删除中断造成。

建议将实施范围由“仅筛选任务”扩大为“确认孤立后清理本地记录 + 任务入口过滤 + 防止旧异步结果恢复已清理记录”。这三条现场记录是应清理的候选：无主网或已导出 Space 对应 Node、无关联 Space、无持久化待删除标记、旧服务器 Owner 样本无网关。但破坏性清理必须在运行时取得当前完整详情并检查原始存储和进行中操作，不能用离线 JSON 批量修改手机数据。

### 8×8 评估矩阵

横向维度：身份范围、Node 存储证据、云端权威性、生命周期、并发回写、关联数据、恢复策略、最终处置。纵向为 8 类会影响清理决策的场景。

| 场景 | 身份范围 | Node 存储证据 | 云端权威性 | 生命周期 | 并发回写 | 关联数据 | 恢复策略 | 最终处置 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1. 本次历史孤立记录 | 当前账号/区域/Site；MAC 与地址定位 | 原始查询成功，主网无 Node，其他子网无冲突 | 新完整 Owner 详情确认不存在 | 无入网/导入/注册/删除活动 | 删除前复核记录版本 | 清理该 MAC 的 Gateway 行和确认悬空的 Space 关联 | 可幂等重试，不复原垃圾记录 | 清理；不产生时区任务 |
| 2. 正常网关离线或未激活 | 有效设备身份 | Node 存在 | 可能已注册，也可能待上传 | 有效注册/入网生命周期 | 保留正常同步 | 保留关联配置 | 正常连接、注册或同步 | 保留；离线/未激活不是删除依据 |
| 3. 新入网/快加未稳定 | 新实例，旧记录可能同 MAC | 内存与落库可能暂不同步；保存也可能失败 | 注册前服务器暂缺很正常 | 入网/持久化/注册中 | 不与当前操作争写 | 预配置与关联可能仍需重试 | 原流程重试或明确失败处理 | 暂缓清理，不能按 null 上传时间删除 |
| 4. 服务器有网关、本地缺 Node | 应核对远端设备实例 | 本地缺失或损坏 | 完整详情明确存在 | 需要导入/恢复 | 导入完成后再对账 | Gateway 内可能有本地未提交信息 | 优先补齐 Node，按既有合并策略处理 | 不作孤立删除 |
| 5. 查错范围、读取失败或权限裁剪 | 可能错账号/区域/子网，或权限不足 | nil/空数组不等于原始无记录 | 摘要、缺字段、Editor/Visitor 不能证明不存在 | 未能确认 | 不启动破坏性动作 | 全部保留 | 修正上下文/等成功读取 | 禁止自动清理；任务可跳过无效候选 |
| 6. 网关删除中断 | 使用回执中的原设备身份 | Node 可能已先删除 | 已有服务器删除确认回执 | prepared/serverDeleted/completed 分阶段 | 遵守现有删除锁和活跃标记 | 可能仍有场景、定时、地址等收尾 | 由 GatewayDeletionContext.resume 完成 | 恢复原删除流程，不直接删行掩盖未完成项 |
| 7. Reset 后重加或地址复用 | 同 MAC/地址不等于同一入网实例 | 新 Node 或另一子网记录可能占用地址 | 旧响应可能不含新实例 | 新旧生命周期交替 | 记录变化即中止旧清理 | 不按旧地址清理新设备数据 | 保留新 Node、使用现有身份校验 | 冲突时保留并诊断 |
| 8. 清理失败或旧回调迟到 | 需验证当前记录仍是原候选 | 查询证据可能已过期 | 旧请求结果不能覆盖新对账结论 | 回调/导入/重加可能交错 | 稳定窗口、条件删除及落库前复核 | 本地关联与 Gateway 行原子提交 | 失败回滚、下次重试，不能假成功 | 暂缓或重试；禁止旧结果把记录写回 |

### 会改变方案的源码证据

1. SDK `MeshDatabase.swift` 的 `Node.load` 使用 `try?` 包裹查询，失败会返回空集合。因此既有 `Node.load(...).isEmpty` 或 `resolveNode == nil` 足以排除任务候选，却不适合作为删除数据库记录的唯一证据。清理应使用可抛错的原始存在性查询，区分 present / absent / unavailable；数据库或表不可用属于 unavailable。
2. [SiteDeviceAddViewController](../SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift) 先调用 node.save，再保存 GatewayModel，随后注册服务器。这些是不同存储/异步步骤，且调用点未检查 node.save 的返回值。不能声称当前生产路径在任何时候都不会出现“业务行存在、Node 尚未成功落库”。本轮没有证据表明现场三条历史行来自此失败。
3. [SiteData.update](../SunSmart/Common/Data/ImportData.swift) 在异步 Node.import 后重新检查删除锁，替换旧 Node 并保存新 Node/GatewayModel；缺 Node 且服务器存在时也有替换/恢复路径。清理必须在已接受详情的网关导入阶段完成之后，而非插进模型 load/getter、列表 compactMap 或异步导入中途。
4. [GatewayDeletionContext.complete](../SunSmart/Main/Device/Gateway/Model/GatewayDeletionContext.swift) 先移除 Mesh Node，之后在 App 数据库事务里清理关联与 GatewayModel。后段失败时 GatewayModel 仍有恢复价值，现有 resume 会继续完成。仅删除 Gateway 行并不能替代完整收尾。
5. [GatewayServerAuthorizationService](../SunSmart/Main/Device/Gateway/Model/GatewayServerAuthorizationService.swift) 在网络回复后通过 persist 调用 gateway.save；[CloudSynchronizationManager](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 在成功/失败回调也会调用 gateway.save。GatewayModel.save 使用 INSERT OR REPLACE。无 Node 孤立清理不天然具有删除回执，直接 SQL 删除之后旧对象仍可能重新插入，必须覆盖这个入口。
6. 现有 `GatewayModel.delete` 按 Site+MAC 删除，数据库句柄为 nil 时可直接返回 true，也没有“记录仍为此次读取的版本”的条件。新清理不能将其返回 true 单独视作已完成，应显式确认数据库可用、条件删除及读取结果；不必借此重写所有删除调用。
7. `SiteData.update` 同时由 Site 列表 import 和 Site 详情刷新进入，现有 isComplete 主要由 Owner+gateways 可解析决定。扩大清理时需明确详情来源，不能仅凭 Owner 摘要中的 gateways=[] 触发新增清理。
8. 项目已有原始节点身份读取（SiteDeviceOwnershipStore）、ConfigurationSnapshotRevision、网关同步状态、注册 actor 和删除回执，可据此构造定向保护。现有同步查询只按 MAC 比较，清理准入还需核对 Site/账号/区域；单独套用锁或检查一次“当前无任务”并不能证明跨数据库、异步回写全过程安全。

### 最终推荐的实施边界

**A. 保留时区任务有效性过滤。** 无有效主网 Node 的本地行不生成时区目标；Node 存在但时区未知仍允许同步。即使离线、清理失败或暂不具备删除证据，也满足“没有可用网关时不生成三个幽灵任务”。

**B. 增加明确入口的孤立 Gateway 清理。** 在当前 Site 的新鲜、已接受、完整 Owner `get/siteprops` 详情完成网关导入后执行；使用详情来源标记或明确调用点，不让普通 GatewayModel.load 产生写入副作用。清理要求同时满足：

- 账号、区域、Site、主网络上下文稳定，数据库/表读取成功；
- 原始 Node 表中无对应主网节点，也没有同 MAC/地址出现在本 Site 其他子网的身份冲突；仅主网查不到不能直接删；
- 权威详情不含该网关；若服务器仍有则走现有导入/恢复；
- 无活跃入网、导入、注册、同步或删除操作；有删除回执/待删除标记则交还原删除恢复流程，回执损坏则暂缓；
- 删除前重新读取的行仍是同一候选，期间变化则跳过。

满足这些条件后，lastUploadCloudTimestamp=null 不再保护真正的孤立行，不以 lastUpdateTimestamp=1/name=Gateway 作为通用删除条件。这样既能清掉现场三条历史行，也不把“null 上传时间”误解释为垃圾数据。

**C. 清理数据范围。** 删除当前 Site+该 MAC 对应的 gateways 原始行（包括行内关联、缓存与凭据），并利用已有权威 Space 关联清理机制处理该 MAC 的悬空关联。App 数据库内涉及的改动要原子提交，删除失败保留可重试状态。此次样本没有网关 NodePropertys，不需要跨 Mesh 数据库补删；不依据缺失 Node 猜测地址范围、回收地址或批量删除灯具/场景/定时。若现场后续发现这类遗留引用，应根据身份和回执另行处理。

**D. 防止再次写回。** 清理与导入/注册的准入、旧请求完成和保存边界须有一致约束。复用已有生命周期/版本机制，排除进行中工作，异步结果落库前验证原记录和 Node 生命周期仍有效；旧详情响应不能在新的清理结果后重新导入被判定不存在的旧实例。不能只靠最后一次 Node 查询或只取消 UI 任务。新入网创建记录保留正常入口，不制造 nodeUUID 为空的“已删除设备回执”去阻止未来同 MAC 重新添加。

改动会涉及 Site 详情导入/对账入口、定向数据库读取与条件清理、时区候选策略，以及注册/同步回写的必要验证。先复用现有机制；仅在验证暴露必要缺口时补最小保护，不创建全局垃圾回收框架或全面改造 Mesh SDK。

### 验证闭环与结束条件

本轮 `python3 scripts/check_gateway_deletion_context.py` 通过，现有生产删除适配器的隔离测试覆盖缺 Node 的 pending 删除恢复、失败重试、重加身份保护与账号隔离。该证据支持复用恢复路径；不是拟议孤立清理已经实现或通过。

实施必须覆盖矩阵 8 类场景，并重点增加：

- 用现场三条记录的脱敏最小夹具：确认无 Node 且完整 Owner 远端空 → 清理 3 行，再次读取为 0，时区 API 为零次；再次清理仍成功且无额外写入。
- Node 查询失败/缺表、主网加载不全、其他子网存在匹配、权限裁剪、详情缺字段 → 0 次删除。
- 活跃入网/注册/导入、服务器仍有、真实 Node 但未上传或未激活 → 保留。
- 待删除回执 → 走恢复流程；旧回执不得影响新实例。
- 查询后重加、延迟注册成功/失败、旧详情迟到 → 不删新记录、不重新插入已清理旧记录。
- App 关联清理或行删除失败 → 原子回滚/明确失败；任务入口仍不生成无 Node 网关任务。

只对当前 Site 按次批量读取并复用结果，不在每个 Cell、每次 load 或高频时区刷新内扫描全库。实施后运行定向行为/SQLite 故障注入回归和一次 SunSmart Debug generic iOS 编译；最终由用户复现、重启 App 并再次导出确认 gateways=[]、无三个时区任务，并验证正常网关和同 MAC 重加。

确认前建议范围为 A+B+C+D。用户随后回复“确认按这四部分实施”，以下记录实施结果。


## 已确认范围的实施记录

日期：2026-09-23。App 分支 `fix`，基线 HEAD `425d0a27`；未提交。保留此前诊断导出增强和其他任务文件。本次不修改 SDK、工程依赖、UI 文案或服务器数据。

### 四部分落地

| 部分 | 实现与边界 |
| --- | --- |
| A 时区目标过滤 | `SiteGatewayLocalTimeZoneContextBuilder` 将主网 Node 是否可解析传给目标策略；没有 Node 不生成目标。有效 Node 的未知时区继续同步，权限、去重和已有偏移比较保持原逻辑。 |
| B 确认孤立后清理 | 网络层给新发出的 Site 详情记录账号、区域、Site、清理版本和活动版本。`SiteData.update` 完成导入且保存成功后进入对账；列表摘要、访客/编辑者、缺失/不合法 gateways、过期响应和未完成导入不准入。原始 SQLite 读取本 Site 所有子网的地址和 MAC；只清理远端缺失、没有任何对应 Node 或身份冲突的网关行。null 上传时间不再阻止此类清理。 |
| C 原子清行及关联状态 | App 数据库事务内复核候选身份、数据库版本与活动状态，条件删除；任何错误整体回滚。成功提交后清除对应 Space 的 `relevanceGatewayId`、`gatewayStatus`、`gatewayLastOnline`（它们是内存字段，不是 spaces 表列）。不删除 Mesh 节点、地址池、场景或定时。 |
| D 旧结果不能复活 | 共享保存入口验证账号/区域及每个 MAC 的清理版本，复制对象保留原 token；原始读取开始前记录版本，避免旧行被赋予新的有效 token。注册发请求前及结果持久化前再次检查；清理前发出的旧 Site 回复在导入入口被拒绝，防止关联字段复活。新入网的新对象和清理后发出的新请求仍可恢复同 MAC 的合法新实例。 |

保护复用现有删除锁、删除回执、网关同步状态及 SDK 数据库 revision。入网页面存续期间、注册请求执行期间及其他 Site 导入进行中均暂缓清理；进行过入网/注册的旧详情即使稍后才返回，也不能据其缺失项删除。删除回执存在或损坏时保留记录，交由原删除恢复路径处理。

新增版本信息仅在进程内使用，不写入服务器或生成虚假的设备删除回执。App 重启后旧对象和旧请求也随进程结束；已经删除的网关行不会由这套机制恢复。

### 自动化验证

- `scripts/check_gateway_orphan_cleanup.py` 通过：生产 SQL 与生产清理适配器运行在真实 SQLite 上，仅替换账号、Mesh 服务和任务状态等平台依赖。覆盖三条样本行清理、幂等、其他 Site、跨子网地址/MAC 冲突、服务器仍有、待删除/同步中、入网/导入/注册活动、权限与详情来源、缺字段、读取错误、候选变化、事务删除失败回滚、旧对象/旧响应失效与同 MAC 新版本放行。
- 七组相关时区测试通过：LocalTimeZoneTarget、CloudTimeZoneTarget、LocalTimeZoneContextContract、CloudTimeZoneSyncState、CloudTimeZoneSyncCoordinator、CloudTimeZoneSessionCoordinator、TimeZoneEditSyncCoordinator。三条孤立候选得到零目标；有效 Node 的未知时区得到正常目标；空目标不发送网关 submit/status 请求。这是分层行为验证，未宣称已运行完整 App 网络链。
- `scripts/check_gateway_deletion.sh`、`scripts/check_gateway_multi_role_consistency.sh`、`scripts/check_space_membership_lifecycle.py` 通过。删除恢复和多角色脚本在最终数据库/导入保护补齐后再次通过。
- `git diff --check` 通过。
- 完整 `scripts/check_site_sync_gateways.sh` 未通过：第一个布局用例要求 112 pt，而当前生产最小宽度为 100 pt。这两个文件相对 HEAD 均无改动，是本次修改之外的基线不一致；未修改布局或测试期望，单独执行上述相关时区用例。不能将本轮报告为整套脚本通过。
- 构建：使用 `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO`。本地 SDK realpath 为 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ebbe1c9`，无未提交差异；使用已有 `databaseReadRevision` API，没有新增 SDK API 或发布依赖。最终增量构建于 2026-09-23 15:40（UTC+08:00）返回 `BUILD SUCCEEDED`，覆盖最后补齐的读取版本与旧 Site 回复拦截。五品牌共享该逻辑且无新编译分支/工程资源差异，本轮按项目规则验证代表 scheme SunSmart。

### 最短人工验收

1. 使用修复版，以 Owner 进入“5楼测试”，等待新一次 Site 详情刷新结束。在原始数据库及最新服务器仍与样本一致的条件下，DEBUG 应出现 `[GatewayOrphanCleanup] ... removed=3`；再次导出应见 `gateways=[]`。若正有入网/注册/删除工作或读取失败，则先保留，下一次满足条件的详情刷新再清理。
2. Edit Site 修改 Time Zone 后 Sync：Site 更新正常，不出现三条 Gateway 时区任务；重启后重复并导出，记录仍为空。
3. 正常带网关的 Site 仍能同步；有效 Node 但时区未知时仍有任务。同 MAC 重新入网应能正常保存、注册和展示。

实施阶段未自动安装 App、操作真机或请求真实服务器；后续用户现场测试结果见下一节。隔离测试、generic iOS 编译和真实设备/服务器收敛分别作为不同证据。


## 用户现场验收与新导出核对

日期：2026-09-23。用户反馈“测试没有问题”，提供 `/Users/maginawin/Desktop/tmp/1545 Site_5楼测试_20260923_154432_664+0800.json`。文件实际 capturedAt 为 `2026-09-23T07:44:32Z`（UTC+08:00 15:44:32）。本轮核对时工作树为 `fix`，HEAD `35e1cced`（`fix: wrong gateways list`），开始时工作树干净；本轮仅更新验收记录，没有修改业务代码、重新构建或操作设备。

与 15:07:25 的旧导出对比：

| 核对项 | 修复前 | 用户测试后的导出 |
| --- | --- | --- |
| Site UUID | `D7CA28AE-0134-4AFD-9AB1-3389AC5C111F` | 相同 |
| 原始 `rawSite.gateways` | 3 条 | 明确空数组，0 条 |
| 三个旧 MAC | CC9E27179B40、E2F54FDEECEB、F1ADFFA8B2C7 | 新 JSON 全部字段的字符串值中均未找到精确匹配 |
| 主网 Node | iPhone，地址 1 | 仍只有 iPhone，地址 1 |
| 主网 networkId | `0968AA474D4F8AAE` | 相同 |
| Site 时区 | America/Argentina/Catamarca (UTC-03:00) | America/Adak (UTC-10:00) |
| lastUpdateTimestamp / lastUploadCloudTimestamp | 1790145842 / 1790145842 | 1790149465 / 1790149465 |
| pendingSitePropsMask / syncCloudError | 0 / null | 0 / null |
| Site 诊断 issues | 空数组 | 空数组 |
| Space 数量 | 8 | 8 |

结论：新导出直接证明三条孤立 Gateway 数据已实际清除，Site 的本地修改版本与已上传版本一致、没有待提交属性或同步错误。结合用户操作测试反馈，本次“无网关却出现三个时区任务”的现场问题验收通过。

范围说明：新导出不是新的 `get/siteprops` 服务器响应，因此“上传完成”证据来自本地持久化标记及用户测试反馈，本轮没有独立请求服务器。用户没有逐项列出重启、正常网关和同 MAC 重加的操作，本记录不将这些边界场景额外标为已完成真机验收。

附带对比：各 Space 的 Group/Scene/Schedule 数量保持一致；“5楼”Space 的 Node 数量从 1 增至 3，其余 Space 数量一致，不能据此宣称全部业务数据逐字段不变。既有 proximityLighting 诊断条目与旧导出一致，没有扩大本次修复范围。导出里的 `uploadable=false` 是诊断文件格式固定标记，不是 Site 上传失败状态。
