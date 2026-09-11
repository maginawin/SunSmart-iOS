# 大 JSON 请求体接口与服务端 gzip 支持优先级

日期：2026-09-10。范围：当前 fix 工作树。依据为 API 参数构造器、业务调用、导出逻辑以及仓库内既有故障记录。本轮只分析和新增文档，未修改 App/SDK，未发送业务请求，未重复运行构建。

## 结论

优先让服务器支持两个全量配置接口：`/sitespace/sync/siteprops`、`/sitespace/sync/spaceprops`。第二批考虑地址回收、Space 解绑和网关注册。其余批量操作仅在条目数量较大时有明显收益，应先测实际正文大小。

这份清单描述“值得支持”的范围，不是“服务端已经支持”的结论。用户此前确认的是 gzip 响应能力，当前仍没有请求 gzip 已通过测试的新证据。App 继续发送普通 JSON，不把仅添加 Content-Encoding 请求头作为压缩实现。

## 第一优先级：全量配置同步

| POST 路径 | App case / 请求 envelope | 增长来源与触发场景 | 优先级 |
| --- | --- | --- | --- |
| `/sitespace/sync/spaceprops` | spaceUpload；siteId、spaceId、spaces=[完整 Space]、userId | Space 的 nodes、groups、switches、emergencyFireControllers、scenes、schedules；节点还包含模型、场景执行和日程等嵌套字段。设备多、组配置复杂、路径/场景多时体积增长。普通同步以及解绑前保存都可能触发。 | P0 |
| `/sitespace/sync/siteprops` | siteUpload；site、user。首次 siteAdd 额外包含 devicesInSetle | Site 的 provisioner.usedAddresses、地址分配范围、exclusions，加上本次指定同步的 site.spaces 中每个完整 Space；涵盖 Site 同步、首次上传、批量添加 Space、批量解绑前补同步。 | P0 |

源码证据：

- `SunSmart/Common/Network/NetowrkReqeustApi.swift:396`：Site 创建/同步 envelope；`:418`：Space 同步 envelope。
- `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:73`：syncSite 按 cloud 状态选择 siteUpload 或 siteAdd；syncSpace 导出完整 Space；addSpaces 通过 siteUpload 提交。
- `SunSmart/Common/Data/ExportData.swift:223`：Site 导出；`:267` usedAddresses；`:290` exclusions；`:310` 仅导出 spaceIds 指定的 Spaces。
- `SunSmart/Common/Data/ExportData.swift:933`：Space 全量集合写入 JSON；节点内还写入 scenesDatas、schedules 等。
- `SunSmart/Common/Data/SpaceConfigurationSafety.swift:567`：单 Space 解绑前保存使用 spaceUpload。
- `SunSmart/Main/Share/Controller/ShareAuthorityViewController.swift:613`：批量解绑前有待同步 Space 时，先通过 siteUpload 保存。

两个重要边界：

1. Site 同步**不必然每次上传全部 Spaces**。正常 syncSite 默认 syncSpaces=[]，仍会提交 Site 地址数据；显式选中的 Spaces 才会完整导出。不能把它描述为每次发送整个 Site 所有节点。
2. 只改少量设备/配置不代表网络正文是字段增量：当前 Space 上传仍以完整 Space 快照为单位。gzip 可以减小传输量，但不改变导出、服务端解析及全量写入成本。

### 已有体积证据

仓库 `docs/260909_2026_space_share_sync_gzip_failure_analysis.md` 记录的历史日志显示：

- Site-only（syncSpaceCount=0）gzip 正文为 **34,370 bytes**。
- 一个 500 Nodes 的 Space，两次 gzip 正文为 **297,940 / 290,796 bytes**。
- 当时真实 gzip 请求均遭遇 UTF-8 parser 的 HTTP 400 parse_error。

这些是 **2026-09-09 文档记录的历史压缩后字节数**，本轮未复测，也没有可据此计算压缩比的对应原始 JSON 字节数。它们直接说明两个同步路径已出现值得优化的上传体量，不能作为当前服务器请求解压已修复的证据。

## 第二优先级：地址集合与完整网关 Node

| POST 路径 | App case | 可能较大的正文内容 | 建议测试场景 |
| --- | --- | --- | --- |
| `/sitespace/address/release` | recyclingAddress | addrLists.device/group/scene 逐项整数数组、exclusions 内按 IV Index 分组的地址数组、可选 provisioner | 大网络回收未用地址、回收积累的废弃地址、多次操作积累的待回收集合 |
| `/sitespace/space/unbind` | unbindSpaces | spaces ID 列表，以及与 address/release 相同的 addrLists、exclusions、provisioner | 批量退出多个 Space，尤其退出全部 Spaces、回收全部剩余地址的分支 |
| `/sitespace/sapce/gateway/regist` | gatewayRegister | 完整 node，包括 elements/models、netKeys/appKeys、绑定和订阅数据；部分调用还添加 gatewayPreconfigured.associatedSpaces 等 | 关联 Space 多、模型绑定复杂的网关注册/同步；普通小网关作为对照 |

`sapce`、`regist` 为当前服务端路径拼写，不能改成推测的标准单词。

源码证据：

- `NetowrkReqeustApi.swift:493,527`：解绑和回收均把数组直接放入请求，没有在该构造层分批发送。
- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:274`：getRecycleAddressData 获取可用设备/组/场景地址；退出全部 Spaces 时提交全部剩余地址及相应 exclusions（约 305–338 行）。部分分支仅回收较小子集，因此不能说每次解绑请求都很大。
- `SunSmart/Main/Site/Controller/SiteViewController.swift:2406,2425,2446`：多条地址回收业务入口。
- `NetowrkReqeustApi.swift:581`、`CloudSynchronizationManager.swift:116`：网关注册携带 node；`ExportData.swift:954` 从完整 Node 编码生成字典；`:1119` 补充网关预配置及 associatedSpaces。
- `SunSmart/Main/Device/Gateway/Model/GatewayCloudSyncGenerationPolicy.swift:522`：关联保护合并 netKeys、appKeys、elements 等数据。

地址列表比仅传起止范围更容易增长；回收请求应列为独立验收项。网关注册通常只有一个 Node，其量级不应直接等同于多节点 Space。以上三个接口本轮没有真实正文大小记录，排序是源码推断。

## 第三优先级：批量操作

| POST 路径 | App case | 增长字段 | 当前使用情况 |
| --- | --- | --- | --- |
| `/sitespace/space/bulk/changepass` | spacesPasswordSet | spaces[]，每项为 Space ID 和对应密码字段 | 有业务调用 |
| `/sitespace/space/batchshare` | spacesShare | spaces[]，Space ID 列表 | 有业务调用 |
| `/sitespace/spaces/delete` | spacesDelete（另有单项 spaceDelete） | spaces[]，Space ID 列表 | 有业务调用 |
| `/sitespace/space/permis/bulk/reclaim` | clearSpaceMembers | reclaimUserList[]，用户 ID 列表 | 有业务调用 |
| `/sitespace/site/permis/bulk/reclaim` | clearSpacesMembers | spaces[]，Space ID 列表 | 有业务调用 |
| `/sitespace/gateway/datetime/update` | gatewayDateTimeUpdate | gateways[]，网关标识列表 | 有业务调用 |
| `/sitespace/space/visitpass/enable` | spacesVisitorPasswordEnabled | spaces[]，Space ID/密码字段及 enable | 仅保留 API 定义，当前检索到的业务调用已注释；列为备用 |

这些都是条目数增长型正文，不包含每个 Space 的完整配置。建议服务端共用请求解压能力，但客户端最终是否压缩应按序列化后的字节数判断；少量 ID 不值得与全量配置同等优先处理。不能仅按名称含 bulk/batch 就判定为大请求。

## 通常无需作为 gzip 上传重点的接口

- siteInfo、spaceInfo、sites、shareInfo、gatewayList、gatewayAssociationSpaceList、firmwareVersionList 等查询：响应可以很大，但请求只是少量 ID/查询条件。
- `/sitespace/share/receive`：接收 Site/批量 Space 的响应可能大，请求只包含 token、passwd、user，以及加入 Space 时的 roleName。
- `/sitespace/site/ownertrans`：只上传 Site ID、密码及用户 ID，并不发送整个 Site 数据。
- `/sitespace/update/siteprops`：虽接受 props 字典，当前 `SitePropsAPIClient.swift:55` 仅发送 updateTimestamp 及选中的 siteName、imageId、timezone，不是完整 Site 上传。
- `/sitespace/address/claim`：申请时发送数量 number，不发送所有地址数组；与 release 不同。
- `/sitespace/space/singleshare`：当前请求为 ID、角色、密码等小字段；成员列表大属于响应侧。
- `/temporary/device/alert/add`：`SimulateFaultRequest.swift` 是单个设备的告警和元数据，desc/location 当前为空，无批量告警或大附件正文。
- `/sitespace/ota/configfile`：当前 App 无请求正文；固件 ZIP 下载也不属于 JSON 上传。

## 服务端支持与验收建议

先覆盖 P0 两个路径，再覆盖 P1 三个路径，最后按真实批量规模决定 P2。推荐在这些路由进入 JSON parser 前统一处理请求编码，保持当前业务 envelope、字段及身份校验。

1. 无 Content-Encoding 的普通 JSON 继续兼容；gzip 请求必须先完整解压与校验，再按 JSON 处理。Content-Type 仍为 application/json；Content-Encoding 描述实际编码后的正文，不能只有 gzip 头却发送普通 JSON。规范见 [RFC 9110 §8.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-8.4)。
2. 验证真实 gzip、截断 gzip、有效 gzip 内无效 JSON、超限正文；明确压缩字节和解压后字节的上限，不让 parser 失败形成部分业务写入。若请求编码不支持，明确拒绝；不能只返回成功状态就宣称完整数据已接收。
3. 各地区以及代理到业务实例的完整链路都要验收。大请求测试保留全部业务字段，以正常普通 JSON 为对照，并回读确认节点、组、地址、网关关联或权限结果。
4. 回收、解绑、批量删除/改权限都有业务副作用；测试使用独立数据。不要将“gzip 失败就自动用 JSON 重发”作为客户端默认策略；超时或结果不明确时先判断是否已写入，沿用现有回执/回读保护。
5. 未来 App 接入按“已验证接口/地区 + 原始正文大小阈值 + 压缩确实变小”选择编码，不能仅按响应 gzip 支持推断。阈值需根据实际采样确定，本轮不指定固定值。
6. 记录 endpoint、场景、原始正文 bytes、gzip bytes、压缩耗时、请求耗时、业务结果及回读一致性；不记录完整配置或凭据。目前响应指标不足以量化上传收益。

App 当前 `NetworkRequest.swift:538` 统一移除请求 Content-Encoding，因此未来启用时须同时调整最终请求准备逻辑，真正压缩最终正文并设置匹配的头，避免只改 API headers 后被移除，也避免解码/压缩重复执行。此处仅为后续实施边界，本轮不改。

两个同步接口的既有 Apifox 方案见 [服务端同步接口修复清单](260909_2033_server_sync_gzip_apifox_acceptance.md)。现有 `scripts/prepare_apifox_sync_fixture.py` 只接受 Site/Space 同步 envelope，不能直接用于地址回收或网关注册，需要另行扩展工具后使用。

## 本轮交付与限制

已完成当前 App 请求构造和主要正文来源的源码分析；保留之前已实现的 Accept-Encoding 改动。本轮仅新增本文，不修改传输行为，不提交 Git。

P0 有历史大正文证据；P1/P2 仅有结构和调用链证据，尚无真实上传大小或压缩收益测量。服务器请求 gzip 能力仍需独立确认。
