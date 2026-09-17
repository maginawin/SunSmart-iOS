# Site Trigger Zone 首期需求核对与开发方案（待确认）

日期：2026-09-09。工作树：`site-trigger-zone`，本轮核对 HEAD：`b66e54a1`。本轮只新增本文，不修改 App、SDK、服务端、配置或设备状态。

参考：

- [跨 Space 能力分析](260909_0934_site_trigger_zone_brainstorm_analysis.md)
- [Key 作用域与权限补强分析](260909_0959_site_trigger_zone_key_scope_permissions_analysis.md)
- [Figma：Spaces / Site Menu / Trigger Zone Entry](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=600-7782)

## 用户确认后的调整

- 接口中的 Site 扩展字段统一命名为 `extensionData`，其内部仍为 `triggerZones` 数组；不改动代表完整 Site 对象的 Swift 类型和局部变量名。

- 已确认开始实施，Site Zone 总数上限由 32 调整为 100；Space 上限仍为 32。
- 所有角色均保留当前菜单项的显示条件，Trigger Zone 统一追加至末尾。缺失的菜单项不补齐。下文原待确认的 Editor 特殊插入规则被本条替代。
- 其余首期范围与即时保存规则已确认。
- 接口最终边界：Site Trigger Zone 页面添加、更新、删除，只调用 `/sitespace/update/siteprops`，提交 `props.extensionData` 及必要的更新时间，不在该页面触发整份 Site 上传；Site 页面继续调用 `/sitespace/sync/siteprops` 同步整个 Site，完整保留 `extensionData`。此前关于从全量请求中排除 `extensionData` 的建议已撤回，未实施。
- 两种提交路径共用 Site 扩展数据存储。全量导出读取最新持久化数据；较早请求的成功响应不能清除其后产生的 Zone 修改。失败后的 Zone 重试仍走属性更新接口。
- 用户自行手动验证；除非用户另行明确要求，不再主动运行构建、测试、真机验证或接口联调。下文验收矩阵作为手动验收参考。
- 行级保存调整：Site Zone 被选中后，操作顺序为 Test、Reset、Delete、Save；Save 位于 Delete 右侧且样式一致。Save 以当前 zoneId 为操作范围，不将其他 Zone 的未保存版本一并提交。导航栏仍只有 +，创建空 Zone 和删除的原有即时提交方式保持。跨 Space 成员、权限预检和 Mesh 配置待后续适配，不以当前云端属性保存代替设备同步。

## 1. 结论与本期边界

需求方向合理，可以作为独立的第一期：Site 菜单入口、Site Trigger Zone 列表、批量创建空 Zone、选择与操作区域、Add to Zone x 面板，以及 Site 级持久化和云端往返。

还需要确认菜单顺序冲突、空 Zone 的 Test/Reset 行为，以及即时保存和服务器兼容语义。仅在 JSON 增加一个数组不足以完成持久化、失权处理和多端同步。

建议本期完成：

1. 按 Site 中任一 Space 的有效 Owner/Editor 权限显示入口；不依赖当前 Gateway/Favourites 筛选结果。
2. 独立 Site 控制器，标题 `Trigger Zone`，右上角只保留 `+`；首次无数据时显示空态，重进时读取已保存数据。
3. Site 内 Zone 总数最多 100；每次追加数量为 1 至剩余容量，确认后立即保存。
4. 选择 Zone 后展示 Test、Reset、Delete、Save 和 `Add to Zone x` 面板。
5. 本期只有空成员 Zone：Test/Reset 显示但禁用，Delete 可用且二次确认；面板展示和展开/收起正常，实际成员添加留到后续。
6. Site 数据模型、数据库迁移、导入导出、云同步、缺字段兼容和失败重试形成闭环。

后续阶段继续遵循前两份文档：完整成员空间摘要、全部成员 Spaces 的编辑权限、Group Profile 优先、整条 Path 同转发 Key、合并拓扑与设备同步。本期不激活这些 Mesh 功能，因此也不展示 Space 控制器的 `Devices not synced` 或进入其 Sync Devices 流程。

“内容是空的”理解为新 Site 默认没有 Zone，不是每次进入都丢弃已有 Zone。“同样的添加弹窗”理解为当前 Space Trigger Zone 的数量输入弹窗；本工程尚无 Site Trigger Zone 控制器。

## 2. Figma 与当前菜单核对

已通过 Figma connector 获取节点 `600:7782` 的结构化信息，并进一步读取 `600:7884`（Site Menu Surface）的设计上下文。

设计菜单顺序确实为 Edit Site、Delete Site、Share & Authority、Transfer Site、Restore Device、Firmware Update、Trigger Zone。Surface 宽 144、行高 30、行间距 2、圆角 8；Trigger Zone 图标容器命名为 `menu_trigger_zone`。当前 App 使用 `MenuPopView`，菜单宽为 `SCRXFrom(154)`。建议保留现有菜单组件、品牌主题与缩放规则，仅追加/插入新项，不为此次需求整体重做菜单尺寸。

当前资源目录没有 `menu_trigger_zone`，仅有 `Space/trigger_zone` 等资源。实施时从该 Figma 节点导出真实图标，按要求新增共享资源 `menu_trigger_zone`，检查五个品牌 target 的资源可见性。

### Restore Device / Firmware Update 的实际显示条件

| 菜单项 | 当前源码条件 | 说明 |
| --- | --- | --- |
| Restore Device | `showGatewayModels` 非空，且 `site.permissionOperates` 包含 restoreDevice | showGatewayModels 是可配置网关集合，不是 Site 所有网关 |
| Firmware Update | `firmwareUpdateGatewayModels` 非空，且包含 firmwareUpdate 权限 | Site Owner 使用 gatewayModels；非 Owner 使用 showGatewayModels 中已关联 Space 的网关 |
| 两项操作权限 | Site Owner 具有；非 Owner 如存在 Editor Space，也具有 | Editor 不是必然只有 Share & Authority |

因此，“需要有 Gateway 才能展示”方向正确，但不充分；还要有相应权限与符合条件的网关。两项分别计算，不能假设总是同时出现，也不应在新增 Trigger Zone 时改变现有条件。

### 菜单顺序建议

用户的“底部新增”和“只是 Editor 就放在 Share&Authority 下面”，在 Editor 能管理网关时存在冲突。建议采用更具体的 Editor 规则优先，并保留其原有网关菜单：

| 场景 | Trigger Zone 位置 |
| --- | --- |
| Site Owner，网关菜单均存在，且有符合条件的 Space | Firmware Update 后 |
| Site Owner，无网关菜单，且有符合条件的 Space | Transfer Site 后 |
| 非 Site Owner，但有 Owner/Editor Space | 紧接 Share & Authority；若原有 Restore/Firmware 项可见，继续排列在新项之后 |
| 特殊情况仅有一个网关操作项，Site Owner | 当前实际菜单的末尾 |
| 无有效 Owner/Editor Space，包括零 Space 的 Site Owner | 不显示入口 |

这是一项待确认的产品选择。如要求所有角色始终位于最底部，则 Editor 有网关时应改为放在网关菜单之后。

源码：`SiteViewController.swift:125`、`:335`、`:1516`；`SiteData.swift:175`。

## 3. 权限：入口、创建与已有 Zone 分开判断

### 入口与新建空 Zone

- 遍历当前 Site 完整的已知 Space 集合，不用筛选后的 allSpaces、favouriteSpaces 或当前 Gateway 页面数据。
- 任一 Space 的有效角色为 Owner/Editor 即有入口。Site Owner 本身不绕过“至少一个 Space”的要求。
- 已删除、已失权、密码失效待验证的 Space 不能提供有效编辑授权；当前 `SpaceData.canEditing` 可作为基础，但不能把本地缓存当作服务器永久有效授权。
- 临时编辑占用不改变角色，不把 Editor 显示成 Visitor；实际修改前另行检查授权和必要的占用条件。
- 页面进入后失去最后一个有效编辑权限，应终止新的写入并刷新页面状态；返回 Site 后菜单隐藏。正在上传的旧响应不能在失权、切账号、切地区或 Site 删除后覆盖新状态。
- 离线可浏览缓存和保留本地待提交修改；重连发布时必须由服务器重新授权，不能以离线缓存绕过远端权限。

### 未来有成员的 Zone

前文已经确定：必须具有该 Zone **全部成员 Spaces** 的 Owner/Editor 权限才能编辑。当前只需要任一 Space 权限的规则用于“入口和创建空 Zone”，不能用于批量重写全部已有 Zone。

空 Zone 没有成员 Spaces，建议采用与新建相同的权限规则进行删除；这意味着其他符合条件的 Editor 也能管理这些 Site 共享空 Zone，不额外引入创建者私有权限。

如果本期 App 收到未来版本的非空成员或未知 schema 数据，应保留原始数据并限制不支持的修改，不把它裁成空 Zone，也不调用 Space 的测试/重置/删除设备链路。无权限 Space 的 `Visitor` / `No access` 摘要与完整成员适配仍属于下一期。

现有 `SiteData.needUploadCloud` 依赖 Site role 非 Visitor；新入口则按子 Space 权限判断。必须核对服务端 Site role 与 Space role 的组合，避免界面允许创建、后台却永远不安排上传。新同步调度需显式覆盖 Site Zone 待提交状态，不能只复用这一布尔值。

## 4. 完整交互与保存语义

| 操作 | 建议行为 |
| --- | --- |
| 首次打开无 Zone | 显示现有空态文案和 Add trigger zone；只保留右上角 + |
| 点击 + 或 Add trigger zone | 调用同一个数量输入入口 |
| 已有 N 个 Zone | 弹窗允许输入 1…(100−N)，不是每次都允许再加 100 个 |
| 已满 100 个 | 不创建输入弹窗，沿用剩余容量提示 |
| 输入空值、0、负数、小数、非数字或超过剩余量 | 校验失败，不改变本地/远端数据；确认时再次计算剩余容量 |
| CANCEL | 不改变数据 |
| CONFIRM | 创建指定数量的空 Zone，每个获得稳定独立 ID；一次本地事务提交；成功后刷新列表并排队上传 |
| 选择 Zone | 使用现有业务选中视觉，显示操作按钮，展开 Add to Zone x；切换选择时更新索引 |
| Test | 空 Zone 禁用；不显示虚假的测试成功，也不下发 Mesh 命令 |
| Reset | 语义为清空成员、保留 Zone 本身；空 Zone 禁用 |
| Delete | 二次确认后删除该 Zone 并即时持久化；取消无变化；删除已选项后清除选择 |
| Save | 选中行显示在 Delete 右侧，仅提交当前 zoneId 的属性更新；其他 Zone 保留服务器版本，失败重试保持原 Zone 范围 |
| 删除最后一个 Zone | 回到空态；明确保存/同步空数组 |
| 返回或重启 | 从持久化状态恢复列表；已确认创建/删除无需再次 SAVE |
| 本地保存失败 | 不显示创建/删除成功，保持此前列表并提示失败 |
| 云端失败或离线 | 已落库数据保留为待提交，显示可理解的云同步状态并支持重试 |

建议 Zone 显示名称继续为 `Zone 1`、`Zone 2`，按列表顺序派生；删除后顺序可连续重排，但 zoneId 永不随显示编号变化。首期不增加重命名、拖动排序和自动选中新项等额外交互。

现有 Space 页面采用草稿加 SAVE：addZone 只修改 setZones，saveAction 才经 ProximityLightingLifecycleCoordinator 提交。Site 去掉导航栏 SAVE 后，创建与删除改为即时提交；本轮新增的行级 Save 仅负责当前 Zone 的更新。

现有 Add to Zone x 是页面底部可展开/收起的视图，不是数量输入 Alert。建议复用其外观、标题和尺寸变化方式，首期内容仅展示占位/原有静态结构，设备操作不可执行；不能接入会读取当前 Mesh、自动添加设备或 Identify 的旧 delegate。

现有 Space 空 Zone 已禁用 Test/Reset（控制器 viewForHeaderInSection）；真实 Test 还会先向相关 Group 发 OFF，再依次控制灯。因此“展示行操作按钮”可以在本期实现，“对成员执行真实测试”必须等待跨 Space 成员和路由适配。

本期统一使用已有 `confirm` 国际化 Key，英文值为正确的 `CONFIRM`；不沿用当前 Space 数量弹窗中的 `COMFIRM` 拼写错误 Key，也不顺带批量修改其他页面文案。

## 5. Site 数据结构和本地持久化

保留用户指定的 JSON 层级：Site 对象顶层 `extensionData`，其内 `triggerZones` 为数组；它与 `spaces[].spaceData.triggerZones` 分别存储，不互相投影或覆盖。

建议 App 中增加 `SiteExtensionData` 和独立 `SiteTriggerZone`。现有业务实体已经叫 `SiteData`，新增嵌套类型不再复用同名。Site 通过独立 extensionData 属性管理，再映射为 JSON 的 extensionData。

| 字段/概念 | 首期建议 |
| --- | --- |
| extensionData.triggerZones | 默认 []，数组顺序为展示顺序 |
| 每个 Zone 的 zoneId | 稳定 UUID，创建一次后复制/上传/回读均保持；不是数组索引 |
| 每个 Zone 的 members | 新建时 []，不沿用仅有 groupAddress/deviceAddress 的 Space Item |
| extensionData.schemaVersion | 建议增加，用于区分可理解的格式；缺失按约定的首版解析 |
| 远端配置版本/条件写入令牌 | 用于多 Editor 并发控制；最终名称、层级、服务器更新规则需在接口契约确定 |
| 本地 pending 状态 | 持久化变更快照/基准版本/操作标识和失败状态，不向 JSON 混入 UI 选择状态 |

前两份文档提及的成员稳定身份、依赖版本、Key、TTL 和同步回执是后续跨 Space 功能的设计约束。本期不提前创建假成员、假空间或生成任何 Auth/密钥。成员数组字段名与 schema/revision 的具体服务端命名需冻结后实施。

数据库在 sites 表增加可空的 Site 扩展数据列及必要的 pending 元数据；覆盖建表、增量迁移、loadAll、load、save、copy 和删除清理。旧数据库无列/旧记录无值时加载为默认空对象。

本地已存在但解析失败的数据，需记录损坏/不支持状态并保留原始内容；禁止自动转为空数组后上传。序列化失败或数据库不可用时返回明确失败，不能因可选数据库调用未执行而把 CONFIRM 标为成功。

Site save 当前使用 insert-or-replace。新增字段必须补全所有读写路径；也要防止另一个持有旧 Site 实例的页面保存基本信息时，把刚保存的 Zone 数据覆盖掉。建议 Site 扩展变更通过按 Site ID 的统一存储入口提交，基本属性与 Zone 各自按字段更新，避免无关模块大范围改造。

## 6. 接口、云同步与并发

### 已核对的当前包装

| 接口 | 当前 App 结构 | 本期接入点 |
| --- | --- | --- |
| /sitespace/sync/siteprops | 请求体中的 site 为 SiteData.export 结果 | 新字段实际位于请求 site.extensionData；所有复用 Site export 的上传路径需兼容 |
| /sitespace/get/siteprops | Site 页面读取响应 data 中的 Site 对象 | 读取 data.extensionData；沿用 Site 身份与版本验证 |
| /sitespace/retrieve/siteprops | 请求 props 显式指定字段；响应读取 data.props | 支持后需主动请求 extensionData 并解析 data.props.extensionData |
| /sitespace/update/siteprops | 请求 props 按字段构造 | 支持后发送 props.extensionData，不能顺带修改 Site 名称/时区/图片 |

特别注意：当前 update 响应解析的是 `data.updateTimestamp` 等字段，并非 `data.props`；retrieve 才解析 `data.props`。用户提到增加 `props.extensionData`，不能据此假设四个请求和响应结构完全相同。实施前需接口样例确认 update 新字段的回包位置。

此外，首次 Site 创建及 addSpaces 会复用 Site 导出；要核对 /sitespace/add/site 是否接受新字段，以及分享/转让/重新加入返回的数据是否携带该字段，避免主 GET 可用但其他入口遗漏。

### 推荐提交过程

1. 取得完整的 Site 扩展数据和基准版本，确认本次创建/删除权限与数量上限。
2. 按稳定 zoneId 形成操作；本地数据与 pending 元数据一起持久化。成功后刷新 UI。
3. 每个 Site 的配置写入顺序执行，捕获请求快照和操作 ID；失败保留 pending，切账号/地区/Site 生命周期后使旧任务失效。
4. Zone 页面及其失败重试固定使用 `/sitespace/update/siteprops`，不回退到全量同步。Site 页面的原有全量同步流程继续使用 `/sitespace/sync/siteprops` 并携带 `extensionData`。get/retrieve 用于读取和确认；服务端版本条件写入能力仍需根据实际契约接入。
5. 服务器成功后核对返回配置，或通过 get/retrieve 回读核对 Zone ID、数量、顺序与版本，再清除对应 pending。HTTP 成功或仅回显时间戳不足以证明服务端保存了 extensionData。
6. 若上传期间又产生新修改，只确认已发送的快照，不能清掉新一轮 pending。名称/时区更新成功也不能误清 Zone pending，反之亦然。

### 服务器必须明确的契约

- 旧请求没有 extensionData：保留服务器已有 Site 扩展数据。只有携带明确且获授权的 triggerZones: [] 才代表清空。
- 普通 Site 属性写入不得用旧副本覆盖 Zone；新 App 同样应保留自己不认识的扩展字段或采用服务器字段级合并。
- 具有任一有效 Space 编辑权限的用户可以创建/删除空 Zone；该权限不能同时放开 Edit/Transfer Site 等原有 Owner 操作。
- 后续含成员 Zone 必须按 zoneId 校验实际变更及其全部成员权限；不能因为允许写 extensionData 就允许覆盖无权 Zone。
- 两个 Editor 都基于 99 个 Zone 添加一个时，服务器必须原子检查版本和总数。发生冲突时重新拉取并重新计算，不静默覆盖，也不能超过 100。
- 重试操作以稳定 ID/操作 ID 去重；删除不能被迟到快照重新带回。首期可用条件版本加操作重放实现，不强制引入完整设备同步账本。
- 初版读取字段缺失与“接口尚未支持”要能辨别；本地 pending 不能因为旧服务器忽略字段而被确认成功。

仅有本地递增 updateTimestamp 不能证明具备跨手机并发保护。本轮未读取服务端实现，也未调用实际接口，以上是需落实的接口要求，不是对现有服务端能力的断言。

## 7. 新旧版本兼容结论

### 旧 App 读取新 Site

当前基线的 Site 导入使用 SwiftyJSON 按字段读取 uuid、siteName、netKey 等，并不拒绝未识别的顶层字段。在原有字段名称、类型和含义不变的前提下，新增 extensionData 通常不会影响旧 Site/Space 的解析与展示；旧 App 不会显示 Site Trigger Zone。

这属于当前源码结论，未验证所有历史 App 包。兼容测试需使用实际仍受支持的旧版本。

不能据此承诺数据完全安全：旧 App 不保存也不导出 extensionData；若服务端采用整份替换，旧 App 编辑名称、新增 Space 或上传 Site 可能擦掉新 Zone。必须由服务器保证缺字段保留。旧 App 在同一数据库上降级运行还可能因 insert-or-replace 丢失新列内容；数据库降级兼容不包含在“旧 App 导入新 JSON”的承诺内。

本期仅为空 Zone 元数据，不改变设备拓扑；后续启用跨 Space 同步后，旧 App 的 Group/Space SAVE 可能覆盖设备邻居表或转发 Key，仍按前两份文档处理版本与固件边界，不能声称加字段就解决了设备兼容。

### 新 App 读取旧 Site

| 输入情况 | 处理 |
| --- | --- |
| 首次导入，缺 extensionData 或缺 triggerZones | 默认 extensionData.triggerZones = []，不改变原 Site/Space 功能；不因默认值自动发起清空上传 |
| 已有本地 Zone，后续响应缺 extensionData/triggerZones | 表示未提供，不代表删除；保留已有值和 pending |
| 明确返回有效空数组 | 在版本更新且无未解决本地冲突时应用清空 |
| 明确返回合法非空数组 | 验证 schema、ID 唯一性、容量和版本后导入 |
| null、错误类型、重复 ID、超限或未知 schema | 根据已明确契约处理；未约定 null 等价缺失前，不自行清空；错误/不支持的数据保留并阻止覆盖上传 |

现有 Site update 用顶层 lastUpdate 判断是否更新。新字段若被单独更新或首次补发，必须明确相应版本推进及“本地此前未加载该字段”的处理，避免整个 Site 时间戳相等时永久跳过 Site Zone 导入。

## 8. 实施顺序与预计影响文件

| 步骤 | 工作与完成条件 |
| --- | --- |
| 1. 冻结本期规则和接口 | 确认本文末尾三项 UI/保存规则；固定 Zone 字段、四接口样例、缺字段合并、Editor 授权、条件写入与回读语义 |
| 2. 建立数据闭环 | 新增 SiteExtensionData / SiteTriggerZone / 统一存储与提交入口；数据库迁移、copy、导入导出、损坏保护及 pending 恢复通过针对性测试 |
| 3. 接入 Site 云同步 | 接 sync/get；按服务端能力接 update/retrieve；与现有 SiteProps 字段和待提交状态协调，验证重复提交、旧响应、冲突与失权 |
| 4. 实现菜单和控制器 | 新建 SiteTriggerZoneViewController；复用行/标题/空态/数量弹窗/添加面板的展示能力；所有创建和删除立即持久化 |
| 5. 资源与多品牌验证 | 新增 menu_trigger_zone；复用英文和简体中文 Key；核对新 Swift 文件和资源属于全部受影响 target |
| 6. 联调与实际布局验收 | 完成服务器往返与新旧客户端覆盖测试、真机 iPhone/iPad UI；再交付首期，不把构建通过当作布局/服务器验收完成 |

预计修改范围：

- `SunSmart/Main/Site/Controller/SiteViewController.swift`：菜单与导航。
- 新增 `SunSmart/Main/Site/TriggerZone/` 下的模型、控制器及必要展示适配。
- `SunSmart/Common/Data/SiteData.swift`、`Database.swift`、`ImportData.swift`、`ExportData.swift`：Site 扩展数据完整生命周期。
- `SunSmart/Main/Site/Model/SitePropsAPIClient.swift`、`SitePropsEditPolicy.swift`、`SitePropsEditCoordinator.swift`，以及 `NetowrkReqeustApi.swift`、`CloudSynchronizationManager.swift` 的必要接入点：字段合并、路由与确认状态。
- 共享 Assets、英文/简体中文资源，以及工程 target membership（确有需要时）。

不继承或整体复制 SpacePathTriggerZoneController 的业务实现；它混有 Space 草稿、全局 Mesh delegate、成员过滤、拓扑清理和设备同步。优先复用现有视图，通过最小的展示适配满足 Site，不改变原 Group/Space 行为。

## 9. 验收矩阵

### 数据与权限

- 旧数据库升级、首次导入旧 Site、导入含新字段的 Site、copy、重启与重新进入均保留正确数据。
- 创建 1、99、100 个，已满、剩余 1 个、非法输入、重复确认、删除首/中/末 Zone；Zone ID 稳定，编号正确。
- Owner/Editor/Visitor 混合、零 Space、只有 Owner Space 的非 Site Owner、密码失效、权限撤销、筛选隐藏可编辑 Space 等入口矩阵。
- 本地编码/写盘失败、离线重启、上传失败重试、上传期间再创建/删除、迟到 GET/响应、多手机冲突、切账号/地区与 Site 删除。
- 旧 App 读取新 Site 后编辑旧属性并上传，新 App 回读仍保留 Zone；新 App 读旧响应不清空已有 Zone。
- 明确 [] 可传播删除；损坏/未知数据不清空；Site 新字段不影响原 Space Trigger Zone、名称、图片、时区和已有 pending。
- 服务端暂不支持新字段时不误报成功；以真实回读验证保存，而非仅验证 HTTP 状态。

### UI 与设备边界

- 真机 iPhone/iPad：空态、新建列表、Zone 100、选中切换、Add to Zone x 展开/收起、删除后高度与标题更新。
- 检查完整约束链：安全区—列表—底部添加面板；空态绑定动态列表容器；横竖屏/iPad 分屏后重新布局。右上角 + 在去除 SAVE 后正确靠右，菜单不越界。
- 中英文、长文本、键盘展示与收起、返回再进入、云端失败提示与重试完整路径。
- 空 Zone Test/Reset 禁用；占位添加面板不会发灯控、扫描自动加设备或改邻居/Key；Group/Space 原页面不变。
- 本期 SDK 不需修改。共享代码/资源涉及 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，按要求直接运行各 scheme 的 generic iPhoneOS xcodebuild；不使用 Simulator，不用 shell 包装或重定向。
- 前份文档记录的 `check_site_space_mesh_context_ownership.sh` 精确文本断言失败应在实施时重新核对当前基线；本轮未重跑，不能沿用旧失败断言推导当前运行时问题。

## 10. 请确认的产品选择

1. **Editor 顺序**：按更具体的要求，Trigger Zone 紧跟 Share & Authority；现有可见的 Restore/Firmware 项继续保留在其后。Site Owner 则放当前菜单末尾。
2. **首期交互范围**：只创建空 Zone；选中后显示 Test/Reset/Delete/Save，空 Zone 的 Test/Reset 禁用；Add to Zone x 先展示面板，实际成员添加和跨 Space 测试下一期实现。
3. **即时保存**：CONFIRM 和 Delete 确认后立即本地保存并提交云同步；离线/失败保留待提交状态与重试入口，返回无需 SAVE；Site Zone 总量上限 100。

接口契约是开发/联调依赖：尤其需要服务端确认缺字段保留、Editor 对 extensionData 的独立授权、并发条件写入和 update 响应结构。可先完成已确认的模型与本地 UI，但服务端契约和真实回读未验证前，不能将云同步部分标为完成。

**本轮证据边界**：已读取当前工作树源码、两份给定文档与 Figma 结构化设计；没有修改业务代码、运行构建、真机布局测试、服务器联调或 Mesh 下发。两份原分析文档保持不变。
