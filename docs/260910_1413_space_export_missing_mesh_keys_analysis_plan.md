# Space 导出缺少 netKey / appKey：根因、变更追溯与修复计划

日期：2026-09-10。工作区：site-trigger-zone；HEAD：c8a64d92。本文仅分析和规划，不修改 App、SDK、设备容器或服务端数据。

后续状态：用户已授权实施。已完成范围、构建结果及“保护现存项目、不自动迁移冲突索引”的边界见 `260910_1432_space_mesh_keys_fix_and_compatibility.md`；下文保留规划时的分析记录，第三阶段现场迁移未实施。

## 1. 结论

用户通过接口排查确认，上传 Space JSON 缺少 netKey / appKey 是此次服务端错误的原因。对容器原始快照、SQLite 数据库和源码的独立核对已确认字段确实缺失；此前 gzip 是待验证假设，不再作为本案主因。

没有发现近期提交删除了这两个字段。实际链路为：

1. 同一个 Site 下，已有 Space 1 和目标 Space 1 trigger 使用相同 NetKey Index=1 / AppKey Index=1，但密钥值不同。
2. 本地 Mesh 数据库只保存已有 Space 1 的 Key，没有目标 Space 的 Key。
3. 导入代码仅按 NetKey index 判断已存在；索引相同即跳过 NetKey 与 AppKey 写入，却仍允许 Space 指向远端派生的 Network ID。
4. 导出按 Space.meshNetworkId 查找 NetKey，结果为 nil；依赖它查找 AppKey，也得到 nil。
5. 两处可选编码失败被静默忽略，netKey、appKey、appKeyIndex 都不写入，但函数继续返回配置。云上传与恢复检查没有拦截这一缺失。

因此，字段在本地构造 JSON 时就没有加入，不是压缩、HTTP 日志脱敏或服务端收到后删除。只加 gzip 兼容处理不能解决本案。

## 2. 现场证据

数据来源为用户导出的 `.xcappdata`，读取 SQLite 使用 mode=ro。未打印、复制到仓库或修改密钥值。

目标恢复目录：`d5c04296e7a45541ef578d216b003a116cbf60fdcc42805adc2f867630d1720d`。

| 文件 | updateTimestamp | netKey / appKey |
| --- | --- | --- |
| unvalidated-import.json | 1788515247 | 均存在 |
| before-reference-repair-remote.json | 1788515247 | 均存在 |
| before-local-recovery-remote.json | 1788515247 | 均存在 |
| before-reference-repair-local.json | 1788515247 | 均缺失 |
| last-complete-export.json | 1789019619 | 均缺失，appKeyIndex 也缺失 |

容器共 10 份 last-complete-export.json，只有目标 Space 这一份同时缺少两把 Key。修复前本地预览就已经缺少它们，因此不是清理 Zone 引用时才丢失。

### 2.1 密钥身份与索引冲突

Site：`7FF83E38-E50E-4C2E-BBCB-68F5CDC2E50E`。

| 对象 | Space ID | NetKey index | Network ID | 本地 Mesh 数据库存在 |
| --- | --- | --- | --- | --- |
| 主网络 | — | 0 | 677022DC73A7608D | 是 |
| Space 1 | A494918B-AAC3-4C13-B032-66CD0241099F | 1 | 9374BBD78BFA1F66 | 是 |
| Space 2 | BB11EF0E-790C-40E6-9454-33DD8DFCF419 | 3 | 46E1663B84D1DAFB | 是 |
| Space 1 trigger | E335D681-CB9B-48C1-8A6F-223706D4E70D | 1 | AF566D68DE2263A0 | 否 |

使用本地 libcrypto AES-CMAC，按当前 SDK Crypto.calculateK3 的算法派生 Network ID；CMAC 原语先通过公开空消息测试向量。目标远端 NetKey 派生出的 AF566D68DE2263A0 与 spaces.subNetworkKey 完全一致，本地三把 NetKey 均不匹配。这里 subNetworkKey 数据库列保存的是 Network ID，而不是原始密钥。

目标远端 AppKey index=1、boundNetKey=1，且 Key 值与本地 index=1 AppKey 不同。目标两个设备的 netKeys / appKeys 引用也都是 index=1，因此不能只把 JSON 里的索引改成另一个数字。

目标恢复目录的初始 Mesh 检查点和修复前检查点同样只有本地 0、1、3 三套索引对应的密钥，没有目标密钥。初始 App 检查点尚未包含目标 Space 行，后续检查点包含目标 Space 行但 Mesh Key 仍不存在。这与“导入新 Space 身份，但未成功注册密钥”的路径一致。检查点不是完整事件审计，不能据此断言首次发生的精确时间或操作者。

## 3. 哪次代码改动引入

| 提交 | 时间（提交记录时区 +0800） | 作用与归因 |
| --- | --- | --- |
| 14f727f4 | 2024-06-21 10:00 | 引入当前沿用的可选 Key 编码写入方式；编码不到字典就忽略，没有失败返回。是缺字段仍可导出的历史缺口 |
| 23b4bbba | 2024-09-20 15:10 | Space 导入新增按 NetKey index 去重，命中后跳过两把 Key，随后仍设置 meshNetworkId。是本案同索引不同密钥无法入库的核心逻辑来源 |
| e841e42c | 2024-12-16 09:18 | 导出改从 MeshNetwork.load 返回对象查找 Key，沿用按 Network ID 查找及缺失静默忽略；没有删除 JSON 字段 |
| 3ec92f99 | 2025-01-13 11:46 | 新增“子网 key 丢失”修复分支，但继续按 index 去重，不能修复索引碰撞；已有 NetKey 但只缺 AppKey 的情形也不能由外层条件覆盖 |
| fd520c93 | 2026-09-04 18:00 | 拓扑验证存在问题且有本地快照时提前保留返回，位置在后续补 Key 分支之前 |
| 6c496837 | 2026-09-07 17:10 | 将 destructive repairs 纳入 hasValidationIssues，本案三处悬空引用会触发前述提前返回 |
| d4e4e436 / abfbe5a7 等恢复改动 | 2026-09-07 | 当前本地恢复、引用修复、提交比较关注业务拓扑，未要求完整密钥对，缺 Key 的快照仍可能进入恢复和上传 |
| 32625056 | 2026-09-08 16:58 | 增加同版本 MeshNetwork 复用和真实 gzip；Key 查找/写入块未改变。当前持久数据库本就缺目标 Key，重新 load 也无法补出，因此不能归因为复用或 gzip 删除字段 |

需区分：上述可追溯的是代码缺陷引入时间，不是该设备第一次丢失字段的运行时间。现有证据不足以将整个问题归因于单次近期提交。

## 4. 当前保护为何没有挡住

- `SpaceSnapshotExportIntegritySnapshot` 检查 Group 与孤立成员，没有包含密钥完整性。
- `ProximityLightingExport repairs=0` 仅表示拓扑没有待应用修复，不保证上传 JSON 完整。
- `prepareUpload` / `recordSnapshot` 保存的所谓 last-complete-export 未校验密钥对。
- `prepareSubmission` 检查 uuid、timestamp、nodes 和 configurationData；configurationData 仅比较 groups、memberships、triggerZones，没有密钥字段。
- `referenceRepairReview` 虽已读取有 Key 的远端快照，但本地修复和恢复授权没有单独校验或恢复密钥。

不应把“密钥不能打印到 diff 日志”等同于“不需要验证密钥”。可以进行内存精确比较或持久化私有摘要，同时让对外诊断只输出状态、索引、公开 Network ID。

## 5. 是否影响 sync site

会，取决于是否携带该 Space：

| 操作 | 调用链 | 影响 |
| --- | --- | --- |
| syncSpace | space.export(.cloudSync) → spaceUpload | 当前目标已复现缺字段 |
| syncSite，syncSpaces 包含目标 | site.export(spaceIds) → 每个 space.export(.cloudSync) → siteUpload | site.spaces[] 内同样缺 Key，可能使整次 Site 写入失败；当前日志未提供该接口的实际失败响应 |
| addSpaces | site.export(spaceIds) → siteUpload | 共用同一缺口 |
| 初次上传 Site，并携带 Spaces | site.export(spaceIds) → siteAdd | 同一嵌套 Space 风险 |
| 仅同步 Site 元数据，syncSpaces=[] | 不调用目标 Space 导出 | 不会因这次 Space Key 缺失产生同样的嵌套缺字段；其他校验仍可能失败 |
| 本地备份、引用修复预览、恢复导出 | space.export 默认 .localBackup | 也可能产生缺 Key 的快照，本案已有证据 |

Site 根级 netKey/appKey 与 Space 的不是同一层。SiteData.export 对主网络 Key 查找已有 guard，所以不能把“site 根级有 Key”当成“site.spaces 每项都完整”。根级序列化也应要求成功后才返回。

## 6. 修复计划（待确认，未实施）

### 第一阶段：统一阻断缺字段快照，覆盖全部上传入口

1. 增加共享的 Space 密钥解析/校验策略，必须取得正确 NetKey、正确绑定的 AppKey，并保证两者成功编码。校验 Space 身份、Network ID、索引范围、绑定关系和必要的节点引用。
2. 缺 NetKey、缺 AppKey、同索引不同 Key、绑定错误、无法编码分别返回明确结果。不得取全局 currentNetworkKey、主网络 Key 或数组第一项兜底。
3. `SpaceData.export` 在网络对象确定后、生成和落盘正常导出前做检查，失败即不产生可上传的 payload。正常情况下强制同时写 netKey、appKey、appKeyIndex。
4. 在 prepareUpload / prepareSubmission 增加共享校验，避免恢复旧快照或其他入口绕过导出；对 Site 携带的每个 Space 检查，任何一项无效则整次不发送，不默默丢掉失败 Space。
5. 本地诊断检查点可以保留不完整现场，但须标明用途；不可再把缺 Key 快照当成完整备份。修复失败不得覆盖上一份经验证的完整快照、清空 pending 或更新成功时间戳。

### 第二阶段：修正导入与恢复的密钥一致性

1. 将 Site 导入、Space 导入及“子网 key 丢失”补偿中分散的索引判断统一为结果明确的策略：精确一致、无冲突可补齐、Key Refresh、缺失、索引冲突。
2. 分别检查 NetKey 和 AppKey；NetKey 存在不代表 AppKey 存在。只有同索引且密钥身份/绑定确实一致时才复用；Key Refresh 按当前 SDK 的 phase / oldKey 语义处理，不能当成普通覆盖。
3. 没有索引碰撞的缺失密钥，可在远端 Site/Space 身份、权限、Network ID 与绑定关系验证通过后修复。校验和持久化失败应明确返回，不能只更新 Space.meshNetworkId 或成功时间戳。
4. 拓扑保护和密钥状态分别诊断：invalidRemoteTopology 不应隐藏缺 Key / 冲突。可以在拓扑提前返回前完成只读密钥预检；实际写入通过受控恢复流程，避免破坏现有“保留本地配置”的语义。
5. await 前后重验 account / region / Site / Space 身份与恢复 generation；持久化后重载验证，再允许导出。SDK 与 App 分属两个数据库，不宣称一个 App savepoint 能让两者原子提交；沿用恢复记录处理失败与重试。

### 第三阶段：本次同索引冲突的实际恢复

本案不是“补一把缺失 Key”即可完成。当前 SDK 的 ApplicationKey.boundNetworkKey 和多个查询按 KeyIndex 找 NetKey，在同一 Site MeshNetwork 中直接追加两把 index=1 的不同 NetKey 会产生歧义；覆盖已有 index=1 又会破坏 Space 1。

推荐先核对该 Site 三个 Space 的完整服务端密钥归属及创建/复制/导入来源，再确定索引冲突的合法处理方式：

- 若当前产品契约要求同一 Site 内索引唯一：明确报告历史冲突，修复产生冲突的创建/复制/导入路径；现场修复必须包含真实设备的 NetKey/AppKey 索引、Model bind、Provisioner/Gateway 及云配置迁移，不能只改服务端或上传 JSON 索引。
- 若产品本就允许不同 Space 独立使用相同 index：需要按 Space / Network ID 隔离完整密钥集及 SDK 运行上下文，持久化、导入、导出、恢复、网关和控制查找都要使用该范围。只增加一个供 HTTP 使用的 Key 缓存不能视为完整运行修复。

第一阶段和无冲突补齐可以先做；必须明确它们只会阻止本案发出错误请求，不会自动消除现场索引冲突。本案恢复完成需包含第三阶段选定分支的验证，不得把“500 变成本地校验失败”标为完整修复。

### 验证计划

- 有效 Key 对：完整字段、appKeyIndex、绑定关系与节点引用保持一致。
- 缺 NetKey、只缺 AppKey、同索引同 Key、同索引不同 Key、错误绑定、Key Refresh、过期异步上下文。
- 拓扑需修复同时 Key 缺失：保留原拓扑并单独报告 Key 状态；不产生无 Key 上传或完整备份。
- syncSpace、syncSite 多 Space、addSpaces、初次 siteAdd、恢复重试覆盖同一个校验；任一携带 Space 无效时不发送部分 Site。
- 旧 last-complete-export 缺 Key / pending 恢复：不盲目重传或清除恢复状态，不覆盖已有合法完整快照。
- 使用脱敏现场等价数据构建回归：同一 Site 下两个 Space 的 index=1、Network ID 不同；既能重现缺字段，也能验证另一 Space 的 Key 未被修改。
- 修复实施后运行聚焦策略/真实序列化测试及五个共享 scheme 的直接 generic iPhoneOS xcodebuild：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。若需要修改 SDK，仅使用存在的 one-dev 路径，并检查五个引用 target；不使用 Simulator，不自动真机测试。
- 服务端验收分别验证 syncSpace 与带目标 Space 的 syncSite 上传及回读；真机密钥迁移与 Mesh/Gateway 控制由另行授权的设备验收完成，编译和 HTTP 200 不能替代。

## 7. 本轮验证与限制

完成：10 份导出快照清点；目标 5 份恢复 JSON 对比；当前数据库与两个检查点只读检查；Key 值只在内存比较；Network ID 派生核验；App 和 SDK 源码/Git 追溯。未执行 App 构建、真实 Mesh 操作或生产请求。

当前 Package.resolved 固定 SDK a6246b1b0409824a3227a9c7cad8140219feb182，本地 one-dev HEAD 与其一致；SDK 读取结论据此核对，但并未凭此推断手机包一定来自当前源码。

上一轮生成 Apifox 文件时只验证了“与原快照一致”和 gzip 解压一致，没有验证服务端必填 Key，是分析遗漏。生成文件忠实保留了这项缺失，应视为失败样本，不能再称为字段齐全的正常请求。本文不自动补入密钥或覆盖那些诊断样本。

## 8. 关键源码

- `SunSmart/Common/Data/ExportData.swift:482`：NetKey / AppKey 查找与可选写入。
- `SunSmart/Common/Data/ExportData.swift:324`：Site 遍历并导出 Spaces。
- `SunSmart/Common/Data/ExportData.swift:229`：Site 主网络 Key 查找。
- `SunSmart/Common/Data/ImportData.swift:168`：拓扑 repairs 纳入验证问题。
- `SunSmart/Common/Data/ImportData.swift:1730`：保留本地快照提前返回。
- `SunSmart/Common/Data/ImportData.swift:1793`：子网 Key 补偿及索引去重。
- `SunSmart/Common/Data/ImportData.swift:2049`：正式导入的索引去重。
- `SunSmart/Common/Data/SpaceConfigurationSafety.swift:381`：提交校验。
- `SunSmart/Common/Data/SpaceConfigurationSafety.swift:808`：上传前准备。
- `SunSmart/Common/Data/SpaceConfigurationSafety.swift:927`：引用修复预览及后续应用。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:76`：syncSite、syncSpace、addSpaces 路由。
- SDK `MeshLib/MeshDatabase.swift:200`：按 Site 载入密钥数组。
- SDK `nRFMeshProvision/Mesh API/ApplicationKey+NetworkKey.swift:74`：AppKey 按索引解析绑定 NetKey。
