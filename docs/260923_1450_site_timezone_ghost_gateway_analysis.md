# Edit Site 修改时区后出现 3 个网关任务：分析记录

日期：2026-09-23。工作树：`sun-smart-worktrees/fix`，分支 `fix`，HEAD `e3856fc4`。

## 结论

最符合当前代码与现场现象的解释是：该 Site 的本地 `gateways` 表还保留着网关记录，Edit Site 时区同步把这些记录纳入任务。它们可能来自历史删除未完整收尾，也可能是未成功注册到服务器的旧记录。现有两份 JSON 不能证明具体是哪 3 个网关、是否曾删除。

已经证实的实现缺口：Edit Site 以本地 GatewayModel 构建候选，不检查 Node 是否存在，也不排除删除状态；Owner 权限直接放行。Node 不存在导致时区未知，进一步被判为需要同步。普通 Site 网关列表却要求 Node 存在，因此可以出现“列表看不到、时区同步仍有任务”的不一致。

本次仅分析、运行隔离复现并增加本文档；没有修改业务代码、连接服务器或操作真机。任务开始前已有 Database、SpaceSyncCleanupCoordinator、ProfilePersistence 等 6 个文件的未提交修改，保持原样。

## 样本事实与局限

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

## 建议的最小修复边界与补证

1. 时区任务入口增加有效生命周期判断，排除已确认服务器删除、正在删除或待本地删除完成的记录。保留删除回执和恢复数据，不为隐藏任务直接删除它们。
2. 对仅本地存在且 Node 缺失的孤立记录，不因未知时区直接推导为有效同步对象。结合完整 Owner 网关快照确定有效对象；不能把缺字段、失败响应或 Editor/Visitor 的裁剪结果当权威空列表。
3. 追查残留本身的来源，再决定是否需要修复清理流程。不能删除全部 lastUploadCloudTimestamp=nil 的记录，否则会误伤新入网尚未注册成功的合法网关。
4. 当前最小补证是读取该 Site 的 gateways 安全字段（名称、MAC、地址、lastUpdateTimestamp、lastUploadCloudTimestamp、serverDeletionPendingLocalReset、syncCloudError），主网络 Node 是否存在及其身份匹配结果，以及删除回执阶段。无需导出任何密钥、MQTT 凭据或账号 Auth。
5. 对照该次 `/sitespace/gateway/datetime/update` 的 gateways 数组与 UI 名称，才能把“3 项”关联到具体历史设备，并区分只生成本地结果行还是已经实际提交云端请求。

若实施修复，直接覆盖：有效已注册网关、待注册新网关、无 Node 孤立记录、服务器已删除但本地待收尾、Owner 权威空快照，以及非 Owner/不完整快照。现有 LocalTimeZoneTarget 测试覆盖未知时区需要重试，却不区分“有效网关但未知时区”和“无效残留对象导致未知时区”，需要在上下文/生命周期入口补覆盖。
