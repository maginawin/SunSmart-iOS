# Create / Edit Site 城市接口、按国家缓存与 Site 城市字段方案

创建：2026-11-03；更新：2026-11-04。状态：App 实现、相关回归与六品牌构建完成；真实 API / UIKit 待人工验收。执行记录见第 12 节。

将城市数据源切换到 `/sitespace/common/cities`，以国家 `code` 管理进程级共享请求及持久缓存；Site 的 `city` 保存城市记录的原始 `name`，整数 `cityId` 保存城市身份，界面通过 ID 匹配目录后按 App 语言显示本地化名称。复用现有城市模型、搜索组件、草稿联动及网络层；国家接口已有实现保持其现有行为，不将两个服务重构为通用缓存框架。

## 1. 已确认要求与建议边界

- 请求参数使用 countries 的国家 `code`，例如 `{"country_code":"US"}`，不能传国家显示名称。
- 缓存 key 为国家 code；每个国家独立控制首次请求、缓存及重试，不使用一个全局城市请求标记。
- 无有效缓存且请求失败时，明确点击城市输入框可重试；已有有效缓存时刷新失败继续使用缓存，本进程不再查询该国家，下一次 App 进程首次使用该国家时再刷新。
- 用户已确认“gjson”指 HTTP **gzip** 响应压缩。
- 用户已选择：**确定国家后立即预加载；Edit 进入时已有国家也加载**。新建页面尚未选择国家时不请求城市，不预取所有国家。
- 生命周期指进程启动到终止；后台恢复、网络恢复、页面重建、账号/分区切换均不重置已使用国家的请求次数。
- 用户已确认：**删除旧城市目录及其 App 打包引用，不作离线兜底**，不用旧城市文件预填接口缓存；同名候选用坐标区分，仅搜索接口返回名称，合法空列表作为成功缓存。网络请求成功后的持久缓存继续支持离线使用。
- 用户补充：Site `city` 对应城市接口记录的 `name`，`cityId` 对应记录的 `id`；服务器已调整 sync/get/update/retrieve 四个 siteprops 接口。**存储字段不等于显示标题**：主要通过 `cityId` 查找城市目录记录。用户最终确认中文按 `names_json.zh-Hans → names_json.en → name` 回退，其他语言按 `names_json.en → name` 回退；名称表缺失或无可用项也显示匹配记录的 name。
- 用户进一步明确：旧项目缺少 `cityId` 或 `city`，按没有匹配城市处理，显示 `Not configured`（中文使用既有“未配置”）；不显示旧数字字符串，不从旧 `city` 推导 ID，也不自动补齐字段。
- 本次必须扩展 Site 模型、SQLite 列、四接口字段映射及共用导入导出链路；不新增城市必填约束。仅 App 端，不修改 SDK、服务器、固件及其运行配置。

## 2. 实施前现状与影响范围

- 当前工作树为 `feat-daylight-saving-261024`，分支 `feat/daylight-saving-261024`。分析开始时 HEAD 为 `63c4776e`，countries 接入处于暂存状态；交付前重新核对，这些改动已归入 `1298ba2e`（`feat: /sitespace/common/countries`，非本轮操作）。本方案以当前 countries 实现为基线，工作树仅新增本文档。
- Create / Edit 共用 `SiteFormViewController`。城市下拉使用 `cityLoader`，Edit 名称回显另用 `cityDisplayLoader`，两者当前均读取打包目录。接入时必须合并数据来源，避免搜索与回显分别发请求。
- `CountryRegionCatalogStore` 已有进程共享、后台磁盘读写、有效响应全量替换、无缓存失败点击重试、在途合并及请求身份校验。其单目录实现可以参考，但直接套用不足以处理多个国家。
- `CityCatalog` 已提供稳定 ID、中英文回退、英文排序、搜索和同名区分。`CityCatalogLoader` 现有后台搜索、120 ms 输入防抖、取消及最近两个国家内存缓存；搜索组件已有 query/context/generation ticket、结果刷新和只改已选标题的接口。
- 当前 `SiteFormDraft.selectCity` 将 ID 字符串写入 `city`，`resolveStoredCity` 用它反查目录回显。本次改成独立保存原始名称和整数 ID，并改用新 `cityId` 匹配目录回显；目录刷新可以更新本地化标题，但不能改写已存名称、ID、坐标或时区。
- 当前 `SiteData` / `SiteStandardProperties` 只有 `city: String?`，SQLite 只有同名文本列，没有 `cityId`；props 请求键、变更掩码、Patch 解析和回执确认均依赖该共享模型。新增 ID 必须贯通这些使用方，不能只在网络字典增加字段。
- 城市目录资源共 251 个文件、39,406,689 字节，六个品牌 target 均有资源引用：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。生成脚本和现有测试也引用旧目录，需区分运行时与离线工具用途。

### 样本与只读接口证据

2026-11-03 读取 `/Users/maginawin/Desktop/US cities.json`，并使用正常 TLS 校验对用户指定 URL 发送一次只读 POST，显式请求 gzip：

| 项目 | 核对结果 |
| --- | --- |
| 响应 | HTTP 200，业务 `code: 200`，`data` 为数组 |
| 压缩 | `Content-Encoding: gzip`、`Vary: Accept-Encoding` |
| 传输 / 解压后 | 564,563 / 3,528,942 字节，传输量减少约 84% |
| 内容 | 21,016 项，与用户样本 JSON 完全一致 |
| 字段 | `id` 为整数；`latitude` / `longitude` 为字符串；其余为 `name`、`names_json`、`timezone` |
| 身份及坐标 | ID 唯一且均为正数；坐标均有限且范围合法 |
| 旧目录兼容 | 美国全部 ID、names、timezone 与本地美国目录相同；样本全部时区均能匹配 App 时区目录 |
| 名称覆盖 | 14,260 项无中文名称；英文同名组 2,600 个，涉及 9,257 项 |
| 缺失内容 | 无行政区、行政区名称表及 aliases；旧美国目录有 2,906 项包含搜索别名 |

这是中国分区 US 的一次命令行观测，不代表 App 已接入、其他国家/分区已验证或所有网络条件均能按时完成。

2026-11-04 只读核对 `/Users/maginawin/Desktop/sync site demo.json`：外层包含 `site`，其 `city` 为字符串 `shenzhen`，`cityId` 为整数 `1880252`。样本用于确认字段与类型，不根据名称推断国家、坐标或时区是否相符。本任务文档与测试仅提取必要的非敏感字段，不复制样本中的网络密钥、账号或其他身份信息。

## 3. 方案选择与复用

已向用户比较两种请求时机：

| 方案 | 收益与代价 | 结论 |
| --- | --- | --- |
| 确定国家即预加载，Edit 有国家即加载 | 打开城市框时更可能已有结果；选国家但不选城市时也会请求 | 用户已选择 |
| 首次点击城市框时加载，Edit 有城市才为回显加载 | 减少未使用城市功能的请求；首次展开需等待 | 未选择 |

实现采用专用 `CityCatalogStore` / Service 按 code 管理数据，沿用国家服务的状态规则和既有原子文件写入机制。城市每国可合法为空、数据量较大且存在多个独立请求，先不改造国家服务的类型与 API，避免为本需求引入通用框架及 countries 行为联动。

保留 `CityCatalog` 的展示/索引能力；将 `CityCatalogLoader` 的磁盘来源替换为共享服务快照，保留每个使用方独立的搜索取消和防抖。网络请求由共享服务持有，不由某个搜索任务持有。Edit 进入时按国家预加载，回显通过共享快照的 ID 索引查找，搜索消费同一快照；不为回显再次请求或遍历全量搜索结果。可删除独立的 `cityDisplayLoader` 实例，但必须保留并调整按 ID 解析已选标题的行为。

## 4. 请求、压缩与解析契约

1. 在 `NetowrkReqeustApi` 增加 `siteCities(countryCode:region:)`，路径 `/sitespace/common/cities`，方法 POST，JSON body 仅需 `country_code`；`/srv2` 继续由分区 baseURL 提供。
2. 请求开始时捕获国家 code 与当前 `ServerRegion`。请求 URL、回调所属国家及缓存写入目标始终使用捕获值，不能在返回时读取当前页面国家。沿用品牌请求头、当前 10 秒超时和总时限入口，不关闭 TLS 校验，不增加自动重试或跨区备用请求。
3. cities 显式添加 `Accept-Encoding: gzip`。请求正文很小，继续发普通 JSON，不设置请求 `Content-Encoding: gzip`，也不手动填写 Host/Connection。
4. 压缩响应沿用现有 URLSession/Alamofire 传输链路及 JSON 处理，不在业务解析层重复 gunzip。合法 identity JSON 仍可解析；若联调发现未压缩，按服务端压缩契约缺失处理，不能把“请求头已添加”当作压缩验收通过。
5. 复用已有 DEBUG 响应头和 `NetworkTransferMetricsMonitor` 的 receivedBytes / decodedBytes。无需逐城市日志，不打印完整响应；现有大响应正文省略逻辑继续生效。
6. 目录适配层严格要求 HTTP 成功、业务 `code == 200`、`data` 为数组。`data: []` 是有效空目录，可缓存并视为本轮成功；字段缺失、null、类型错误、业务失败不能当空目录。
7. 记录映射与校验：

| 服务端字段 | App 映射和约束 |
| --- | --- |
| `id` | 正整数，同一国家不得重复；保持 `geonames:<id>` 的 UI 身份，Site 的 `cityId` 保存为整数 |
| `name` | 非空原始名称，单独保存在城市记录及缓存中；用户选择后原样写入 Site `city`，不改大小写、不使用本地化名称或同名区分后缀替代 |
| `names_json` | 保留原始语言键及整个字段是否存在，用于下拉和已选标题；不能将缺少的 en/zh-Hans 自动填成 name；完整名称表和 name 用于搜索 |
| `latitude` / `longitude` | 接受样本的数字字符串及 JSON 数值；转换为有限 Double 并验证 ±90 / ±180，禁止转换失败时默认为 0 |
| `timezone` | 非空 IANA 字符串；选中时沿用现有时区目录匹配，不能凭坐标或手机时区猜测 |
| 国家归属 | 从本次请求的 code 注入；响应无国家字段，不从城市名称反推 |

8. `names_json` 缺失/null 或语言项不足时按第 5 节回退到该城市记录的原始 name；不因此拒绝目录，也不把 name 写入名称表冒充翻译。语言项缺失、null 或空白视为该语言不可用；名称表本身或非空语言项类型错误、原始 name 缺失/空白、无效 ID/坐标等仍拒绝整批。即使 names_json.en 存在，也不反向拼造缺失的原始 name。未知未来字段忽略。
9. 时区字符串非空但本地目录不支持时，保留城市目录记录，选中失败且不更改草稿，沿用现有失败提示。本次不自动扩充时区或修改 DST 算法；其他国家样本若出现此情况，列为目录契约联调项。
10. 解析、排序、索引、持久化与搜索继续在后台执行，主线程只发布状态和应用仍有效的 UI 结果。沿用现有网络入口，不为单个接口重写通用网络层。

## 5. 展示与兼容性

用户已确认以下显示回退顺序。只有按 cityId 匹配成功后才执行此表；表中的 name 始终指匹配城市记录的 name，不把 Site.city 当显示兜底：

| 城市记录的名称状态 | 中文 App | 其他语言 App |
| --- | --- | --- |
| en 与 zh-Hans 均可用 | zh-Hans | en |
| 仅 en 可用 | en | en |
| 仅 zh-Hans 可用 | zh-Hans | name |
| names_json 存在但两项均不可用，包括空对象 | name | name |
| names_json 缺失或为 null | 目录记录的 name | 目录记录的 name |

即：中文 `zh-Hans → en → name`；其他语言 `en → name`，不回退到 zh-Hans。空白或 null 语言值按缺失处理。缺少翻译是正常数据情形，不能拒绝整国目录或发起额外网络请求。美国样本中 14,260 项没有 zh-Hans，将按上述规则显示 en。

- 新选择国家只来自 countries 的 `code`。Edit 的历史两位大写代码可直接用于 cities，不以本轮 countries 成功或仍包含该代码为前提；历史自由文本/非法代码仅保留展示和保存，不转换为请求参数或缓存文件路径。
- 保持稳定排序：非空 names_json.en 优先作为排序键，缺失时用原始 name，仅用于排序、不改变显示回退。相同排序键按 ID 稳定排列。同名项不合并、不丢弃 ID；因接口缺行政区，使用已有经纬度后缀区分，如 `Springfield (39.7817, -89.6501)`；名称加坐标仍冲突时再附城市 ID。
- 搜索依据接口返回的 `name` 和 `names_json`，保留大小写、全半角、变音符号折叠。旧目录独有的 aliases 不再搜索命中，此展示差异已确认，不混入旧目录内容。
- 网络成功全量替换该国目录，其他国家不变；不合并保留旧候选。失败保留上次有效快照。
- 已选城市框与下拉候选共用目录的名称解析和同名区分规则。Site/草稿的 `city` 与 `cityId` 均存在且非空/有效，并能在当前国家目录中按 ID 匹配时，才展示目录记录的本地化标题；不直接显示 Site 的 `city` 或数字 ID。存储名称与目录 `name` 文本不同不阻止 ID 匹配，也不按名称反查其他记录。
- 历史 `city: "1880252"` 且缺少 `cityId`、只有 `cityId` 没有 `city`、两者都没有，或当前国家目录中未匹配到 ID，均显示 `Not configured` / `未配置`。不从旧 city 解析 ID、不自动填充 city，也不要求用户重选后才能编辑其他合法字段。
- 无可用目录时，收起的城市框暂显示 `Not configured`，不以 Site 的原始 city 兜底；展开列表继续按请求状态显示 Loading / 失败重试提示。已有有效缓存时立即用缓存匹配回显；有效数据到达后再补齐本地化标题。
- 新目录成功替换并删除已选 ID 时，已选框转为 `Not configured`，旧候选不可再选；刷新失败但旧缓存仍有效时继续按旧缓存显示。未匹配只影响展示，保留持久名称、ID、坐标和时区，不自动清空、不产生提交脏字段。
- 目录刷新或 App 语言变化可以更新已选标题及候选列表，但不改已保存名称、ID、坐标、时区或 query。用户明确选择时，才从当前同一条记录写入 `city = name`、`cityId = id`；选择后的标题仍为本地化标题。
- 重选相同 ID 时，若原始名称变化则仅明确更新名称及成对提交；坐标/时区按现有“相同城市不重设”规则保留。不能用只比较 ID 的早退跳过用户此次确认的名称。
- 只有用户明确切换到不同国家时，才清空 `city` 和 `cityId` 及城市派生值，保留手动/GPS 坐标及相应手动时区；选择同一国家不重置草稿。
- 新增城市专用失败 Key，同步英文与简体中文：`Unable to load cities. Tap the city field to try again.` / `无法加载城市列表，请点击城市输入框重试。` 继续复用 Loading、无城市及搜索无结果文案，不修改其他功能的通用失败提示。

## 6. 按国家缓存及请求状态

### 缓存结构

- 共享服务按 code 保存状态；建议磁盘位置 `Library/Application Support/CityCatalog/v1/US.json`。文件包含 schemaVersion、countryCode、fetchedAt 及完整规范化城市记录，包括原始 name 与各可用语言名称；缺失/null 的 names_json 可以规范化为空名称表，因为均按相同规则回退。读取时校验国家归属，缓存往返不能改变语言回退行为。
- key 不附带国家名称、账号或服务器分区。不同品牌由各自 App 沙盒隔离；缓存不进入 Site 数据、云端同步、分享或导出，目录排除系统备份。
- 只接受两位 ASCII 大写国家代码作为文件 key，不将任意历史文本拼入路径。不硬编码 249 个国家或当前 manifest 白名单。
- 无 TTL，最后成功快照持续可用。仅在整批校验成功后原子写入并替换目录；文件不存在、损坏或版本不支持视为无有效缓存，不覆盖其他国家文件。
- 磁盘写入失败仍发布新内存快照，旧磁盘文件保持；本轮视为请求成功，不为写入失败重新查询。
- 保留现有最近两国的内存目录缓存思路，但请求次数/状态不能随 LRU 淘汰。当前使用中的目录与未成功落盘的新快照额外保留，不能因淘汰使已成功请求又变成无缓存；回访已淘汰国家只读磁盘，不再网络刷新。成功后若外部存储损坏也不自动重置本轮请求次数。

### 每个国家的状态与触发

`notStarted → loadingCache → requesting → succeeded / failed`；只有“failed 且该次失败时没有可用快照”的用户明确点击允许重新进入 requesting。请求次数和重试资格单独保存在进程状态中，不能因内存淘汰或后续磁盘读取失败重新获得资格。有效空目录同样是可用快照，不能以 `entries.isEmpty` 判定无缓存。

| 场景 | 行为 |
| --- | --- |
| 新建尚无国家 | 不请求 cities，点击城市提示先选国家 |
| 新选国家 / Edit 已有合法代码 | `startIfNeeded(code)`：后台读取该国缓存，然后自动刷新一次 |
| 该国有缓存且刷新进行中 | 即时展示并允许搜索、选择缓存目录 |
| 该国有缓存且刷新失败 | 保留缓存；本进程再次点击、重进页面、切回国家均不重试 |
| 该国无缓存且进行中 | 展开后显示 Loading；点击与其他页面共享在途请求 |
| 该国无缓存且失败 | 显示城市重试文案；点击未聚焦或已聚焦的输入框均可再请求一次 |
| 该国成功（含空目录或落盘失败） | 使用新快照，不再次网络请求 |
| 切换到另一国家 | 另一国家独立读取/刷新；原国家的请求可完成并缓存 |
| A → B → A / Create → Edit | 共享各国在途请求和本进程结果，不按页面重新请求 |
| 新进程首次使用该国 | 再次加载缓存并自动刷新一次，不一次性刷新全部历史缓存 |

- 键盘输入、清空搜索、国家名称刷新、程序 reload、网络恢复及回前台不是重试手势。仅 `prepareForInteraction` 和 `onActiveInputTap` 接入无缓存失败重试。
- 每国请求分配独立 request ID；同一回调最多接收一次。超时后的迟到成功/失败不能覆盖重试结果、写错国家文件或改变新请求状态。
- 取消搜索、离页和页面销毁只取消该使用方搜索及订阅，不取消共享请求。搜索 A 的取消不能取消其他页面的预加载或搜索。

## 7. UI 异步一致性

1. 共用表单在确定国家后调用城市服务预加载；Edit 初始化已有国家时调用同一入口。预加载、ID 回显和后续搜索共用该国请求与快照；即使旧项目缺少城市字段，仍可按既定时机预加载该国家，供用户重新选择。
2. 服务发布该国新版本时，先使旧展示 ticket 失效，按当前 query 重新搜索。搜索回调同时核对国家、目录版本和现有 query ticket；不能让较慢的旧缓存搜索覆盖新目录。
3. `onSelect` 使用当前国家的最新目录再次查找 ID，不依赖旧 `activeCityCatalog`；已被新目录删除的行不能在刷新间隙选入草稿。
4. 将 `resolveStoredCityDisplay` 调整为校验两个 Site 字段后，从共享目录按 `cityId` 查找，使用统一语言规则生成标题。结果发布前核对当前国家、cityId、city 非空状态和目录版本；匹配/未匹配都通过 `updateSelectedTitle` 更新或清除显示标题，不用 `replaceSelection` 打断正在展开的搜索。不得调用 `selectCity` 重新套用持久字段或默认值。
5. 页面可见、账号/分区/权限有效、App active 且未提交时才应用结果。离页解除订阅；重新可见、恢复 active 或结束提交时读取现有快照补齐显示，不因此刷新网络。
6. 国家目录刷新仅更新国家标题及城市列表的国家说明，不清空城市、不重新请求城市。国家请求失败不妨碍已有合法国家 code 使用其城市缓存或请求。

## 8. Site `city` / `cityId` 数据链路（2026-11-04 补充，已确认）

### 字段、模型与数据库

| 位置 | `city` | `cityId` |
| --- | --- | --- |
| Site API / 导入导出 JSON | 字符串名称，来源为城市记录的 `name` | JSON 整数，来源为城市记录的 `id`；不能发数字字符串或 `geonames:` 前缀 |
| `SiteData` / `SiteStandardProperties` | 保留 `String?`，修改其业务含义及注释 | 新增 `Int?`，与 `CityCatalog.Record.id` 保持一致 |
| `SiteFormDraft` | 独立的原始名称值，不直接用于 UI 标题，避免与当前 `city: CityCatalog.Entry?` 混淆 | 独立整数 ID；按该 ID 查找目录，生成 UI selectedID 时转换成命名空间字符串 |
| SQLite `sites` | 保留现有 TEXT 列及原值 | 新增可空 INTEGER 列；旧行默认 NULL |

- 城市记录分别保留原始 name 和 names_json：原始 name 用于 Site 提交，并在已确认的语言回退顺序中作为最终显示值。草稿中已选目录项可保留为内部状态，但不承担持久名称/ID 的唯一来源，也不能让旧目录项绕过当前快照匹配。
- 数据库沿用 `initDatabase` 的缺列添加机制，覆盖新建表、已有表加列、loadAll/load、persistedPropsState、保存前数据库合并和写回；Site 副本通过 `standardProperties` 一起携带名称/ID。
- **只做新增列的结构升级，不做旧数据转换**：不把旧 `city` 中的数字搬到 `cityId`，不清库、不补名称、不重写已有城市值。打开旧记录和添加新列不能制造待上传字段。
- 保持数据库拥有标准字段的现有规则：旧 Site 实例的普通 `save()` 必须从数据库合并并保留较新的 `city` / `cityId`；仅明确 Patch 能改写或清空。失败事务不能留下只写了一半的名称/ID。
- `cityId` 非空时要求正整数且在 Swift/SQLite 可存储范围内；拒绝 Bool、小数、溢出、负数/0、数字字符串和无效类型。`city` 保持字符串/null 解析；不将数值型 `city` 自动转换成新 ID。

### 四接口及共用导入导出

复用 `SiteStandardProperties` 的统一序列化与 Patch，不为四个接口分别建立城市映射：

| 接口 | App 入口 | 必要行为 |
| --- | --- | --- |
| `/sitespace/sync/siteprops` | `siteAdd` / `siteUpload` → `SiteData.export` | 新建 Site、完整上传及新增 Space 所带 Site 数据，均在 `site` 对象发送名称和整数 ID；未设置时沿用标准属性的 null 表达 |
| `/sitespace/get/siteprops` | `siteInfo` → `SiteData.import/update` | 在持久化前解析两字段，沿用现有版本/pending/事务约束；完整下载、恢复与分享接收等复用入口同步受益 |
| `/sitespace/update/siteprops` | `SitePropsAPIClient.update` | 用户城市选择变化时，在同一 `props` 请求发送 `city` 和 `cityId`；不同国家导致清空时两者都发 null |
| `/sitespace/retrieve/siteprops` | `sitePropsRetrieve` → `SitePropsAPIClient.retrieve` | 在 `SiteStandardProperties.keys` 增加 `cityId`，使请求明确索取该字段；解析 `data.props` 后用于草稿及持久化 |

- `ExportData` 共享的本地导出/分享数据也输出这两个字段，`ImportData` 统一接收；不只修线上 update 而遗留全量同步或文件往返。权限、网络身份、Mesh 内容和导入版本门禁不变。
- 各字段继续采用已有 Patch 语义：**缺字段保留，显式 null 清空**。例如只返回 `city` 是名称补丁，不凭此推断 `cityId`；只返回 `cityId` 也不反查/改写名称。两者都缺失时现有记录均保留，新记录均为空。
- 入站局部 Patch 的字段存在性与出站用户选择分开：用户明确选城市必须成对写入，普通局部响应不自动扩展字段。旧数据允许只有名称或只有 ID；这不导致导入/其他字段编辑失败，但缺任一字段时城市展示为 `Not configured`。
- 示例 JSON 只是新字段演示，不用其不相关字段构造完整 Site 上传；实施时制作最小且脱敏的字段/接口响应夹具。

### 变更检测、失败重试与回执

- `SitePropsFieldMask` 保留现有 bit 定义，追加 `.cityId`（当前可用位 `1 << 10`），补齐 standardFields、差异比较、Patch 输出/应用及确认逻辑，不改变已存 bit 的含义。
- 表单产生的城市变更按名称与 ID 成组提交：任一变化都让本次城市变更带上两字段，避免同名不同 ID 或同 ID 改名称时只提交其中一个。未改城市的普通编辑不夹带打开页面时的旧名称/ID。
- 对本次成组提交，update 回执及后续 retrieve 的 pending 消除必须同时确认名称、ID 和适用时间戳；仅名称相同、仅 ID 相同、缺任一字段或旧版本响应都不能清除本次未确认状态。
- 保留既有离线提交、失败后 pending、再次进入读取、重试及迟到响应保护。重新选择其他城市后，旧请求回执不能覆盖新名称/ID，也不能清掉新请求的待同步状态。
- 完整 sync 的上传确认继续沿用现有已提交版本确认，不额外假设服务器会回显整份 Site；测试旧上传任务回执调用 `save()` 时不会把数据库中的新 `cityId` 或名称覆盖/清空。
- 自动预加载、目录刷新、恢复 active、重新打开表单和 UI 语言切换只重算匹配结果及显示标题，不把存储名称改成本地化标题，也不触发城市字段上传。用户明确选择才写城市记录的原始 `name`。

## 9. 必要修改与实施顺序

确认本设计后使用 Superpowers writing-plans 将可执行任务继续补充在本文件，不另建重复计划；不自动 commit。

| 顺序 | 范围 | 目的 |
| --- | --- | --- |
| 1 | `SitePropsEditPolicy.swift`、`SiteData.swift`、`Database.swift`，APIClient/Coordinator 与导入导出接线 | 定义名称/整数 ID、新增可空列、Patch/掩码/回执一致性；先覆盖四接口及真实 SQLite 往返 |
| 2 | `NetowrkReqeustApi.swift`、`CityCatalog.swift`、API 解析夹具与测试 | 接口/分区/gzip 接线、保留原始 name、合法空目录、无行政区的同名区分 |
| 3 | 新增 `CityCatalogStore.swift`、`CityCatalogService.swift` 及状态测试 | 按国家共享请求、缓存、重试、内存目录与进程次数分离、迟到回调保护 |
| 4 | `SiteCreationDraft.swift`、`SiteCreateViewController.swift` 共用表单、搜索 Loader；必要时最小扩展搜索状态接口 | 按 ID 匹配和本地化回显、未匹配展示、原始名称/ID 成对选择、预加载、最新目录选择验证、取消和恢复 |
| 5 | 中英文 Localizable、六品牌 source/resource membership、旧城市目录与专用生成工具/测试 | 城市重试提示、新文件归属、实际删除旧城市资源及失效依赖 |
| 6 | 相关回归、工程/资源核对及 generic iOS Debug 构建 | 验证新数据源、Site 四接口与数据库往返、原 countries / 草稿行为 |

资源处理已确认：删除仓库内 `SunSmart/CityCatalog/`，移除六品牌资源引用及运行时 bundle/manifest 读取；不保留其完整副本作为测试兜底。同步清理只服务旧目录的 `generate_site_city_catalog.py`、`simplify_city_names.swift`、`site_city_name_overrides.json`、`SiteCityGeneratorTests.py` 及检查脚本调用。城市测试改用 API/cache 夹具，必要数据出处与许可说明随夹具保留。`all_utc_timezones.json`、countries 服务及独立国家测试仍保留。

## 10. 验证边界

优先扩展 `Tests/Site/CityCatalogTests.swift`，增加城市 Store 行为测试，接入 `scripts/check_site_creation.sh`；扩展 SiteCreationMetadata、SitePropsAPIResponseParser、SiteStandardPropsIntegration/Persistence 等既有测试。复用 `scripts/check_site_props.sh` 和包含真实 SQLite 持久化测试的 `scripts/check_site_hdb_persistence.py`；必要时跑 `scripts/check_site_transfer.py` 核对共用导入边界。夹具包括 US API 样本和小型失败/空目录/新 Site 字段样本，不能打包进 App。

- **解析与展示：** US 全量样本、数字字符串/数值坐标、0 坐标、双语/仅英文/仅中文/两项皆无/空对象/缺失或 null 的 names_json，以及语言项为空白/null；语言切换和缓存往返采用同一显示规则；不因没有 en 拒绝合法记录，不把 name 填成缺少的翻译。另覆盖合法空数组、重复/非法 ID、坏坐标/字段类型、业务失败、重名及坐标也相同、未知时区选择失败且草稿不变。
- **缓存与次数：** 不同国家独立；预加载、点击及多个 Create/Edit 页面并发仅一次；有效/空/损坏缓存；有缓存刷新失败不重试；无缓存每次明确点击可重试；成功全量替换；落盘失败可用；新服务实例模拟新进程；LRU 回访不重发、未落盘快照不丢失。
- **竞态与恢复：** US → CN → US、慢旧搜索与新目录替换、旧请求超时后成功/失败晚到、连续点击、取消搜索、离页重进、Create/Edit 共用、后台或提交期间返回；旧选项删除后点击不能成功。
- **草稿与历史数据：** 按 cityId 匹配且两个字段完整才显示本地化标题；缺任一字段、旧数字 city 无 ID、ID 无匹配均显示 Not configured；city 与目录 name 不同但 ID 匹配仍能回显；中文候选选中后标题本地化、提交仍为原始 name；同名不同 ID、同 ID 改名、改国家两字段同时清空；目录移除已选项清除显示但保留持久值；手动/GPS 值不被异步覆盖。
- **四接口及回执：** sync/add 导出名称和数值 ID，get 完整导入，retrieve 请求明确含 cityId，update 城市变更发送一对字段；缺字段与 null 分别处理；名称/ID 任一不匹配或缺失均不能确认成组提交；失败重试、同名城市、取消/迟到响应及未改城市的旧编辑草稿不覆盖当前数据。
- **真实 SQLite：** 旧表缺列升级，旧 city 原样保留且 cityId 为 NULL；新增/导入两字段后关闭重开、导出再次解析；局部 Patch、显式清空、旧实例 save、旧上传回执、pending 重启恢复及事务失败回滚均保持两字段正确。仅结构升级不产生迁移上传。
- **网络与资源：** 验证 POST、JSON 参数、固定分区、gzip 请求头及普通 JSON 请求体；核对六品牌新文件与本地化归属、构建包无旧 CityCatalog/测试样本、仍有时区资源。运行工程语法、国际化及 diff 检查。
- **构建：** 实施时核对 SunSmartLocal workspace 和 one-dev SDK realpath，使用稳定 DerivedData；先 SunSmart generic iOS Debug。由于新增 source 与删除六品牌资源引用，稳定后覆盖六个受影响品牌 Debug。分析阶段不构建，不运行 Simulator，不自动安装真机。
- **人工最短路径：** 选 US 等待后打开城市框；断网验证有缓存可选且回显本地化标题；清除测试缓存/新安装后断网失败，再联网点击已聚焦城市框重试；快速 US/CN 切换；新选城市保存并重进，切换中英文核对显示与持久名称/ID；打开缺 cityId 或 city 的旧项目，确认显示 Not configured 且不改经纬度/时区；真实重启验证重新刷新。通过现有 DEBUG metrics 确认 App 的 gzip 实际传输；四个 Site 接口用测试 Site 验证真实往返。

## 11. 外部契约及本轮交付状态

- countries 已有文档记录各分区国家一致；这不能证明城市接口也一致。本方案按用户的 code-only key 要求设计，前提是四分区提供同一公共城市身份和目录语义。请求仍走用户当前分区。
- 后端负责：四分区部署同路径，接收 `country_code`，返回一致且稳定的城市 ID、名称、坐标和 IANA 时区；成功无城市返回 `data: []`；正确协商 gzip 并声明响应编码。App 团队不实施后端改动。
- 上线前验收：核对四分区及代表性国家的参数、空结果、ID/时区兼容和 gzip。当前仅确认中国分区 US 样本，其他分区/国家未验证；无需因此阻塞可独立完成的 App 解析、缓存、UI 和离线测试。
- 用户已确认服务器四个 Site 接口调整；App 按新契约实施，不安排后端开发。四分区的新字段落盘与返回类型、null 清空、局部字段回执及真实往返仍需联调验收；本轮没有调用会修改真实 Site 的接口。
- 行政区/aliases 补充不是发布前提；已确认按接口现有名称和坐标提供候选展示。
- 2026-11-03 已完成城市源码链路、US 样本与旧目录比对、资源引用及一次线上只读 gzip 请求。2026-11-04 补充核对新 Site 样本、四接口共用字段路径、SQLite/事务、草稿、同步回执及相关回归入口，更新同一文档。
- 上述两轮分析阶段没有修改业务代码、运行 App 测试、构建或真机；过往 countries 验证不视为 cities 或新 Site 字段接入已通过。实施从 `1298ba2e` 开始，当前验证记录见第 12 节。
- 原城市接口/缓存方案及本次显示规则均已确认：Site 原始名称/ID 与 UI 标题分开，依赖 ID 匹配；中文 zh-Hans → en → name，其他语言 en → name；缺 cityId 或 city、或未匹配时显示 Not configured。

## 12. Implementation Plan 与执行记录

执行：Superpowers writing-plans → executing-plans / TDD，由主代理在现有隔离工作树实施。Spec 为本文第 1～11 节。用户已明确授权实施，不重复请求计划或执行方式确认；遵循项目规则不自动 commit。本文兼作任务 ledger，不另建重复文档。

目标：城市 API 与缓存接入，Site 名称/整数 ID 全链路一致，本地化显示与持久值分离。技术栈：Swift / UIKit / Moya-Alamofire / Foundation / SQLite.swift。

全局约束：仅 App；六品牌；无 bundle fallback；code-only 缓存；首次预加载、无缓存失败点击重试；中文 zh-Hans → en → name，其他语言 en → name；旧值不迁移；仅 generic iOS Debug 构建；不操作真机或线上 Site 写入。

Review Focus：城市字段成对变更但入站 Patch 保留独立存在性；旧实例/旧回执不得抹掉 cityId；内存淘汰不能重置请求次数；目录刷新和搜索交错不得选入旧候选；只缺中文/英文不应拒绝目录或改写原始 name。分别由任务 1、2、3 的行为测试覆盖。

### Task 1: Site 城市字段贯通

文件：SitePropsEditPolicy.swift、SiteData.swift、Database.swift、SitePropsEditCoordinator.swift、CloudSynchronizationManager.swift；现有 SiteCreationMetadata / SiteProps / SiteStandardPropsIntegration / Persistence 测试。

接口：`SiteStandardProperties.cityId: Int?`、`SiteData.cityId: Int?`；`.cityId` 使用 bit 10；增加城市变更组扩展供提交使用，原 `changedFields` / Patch 仍保留单字段存在性。JSON 的 cityId 为整数/null，SQLite 为可空 INTEGER。

- [x] 先写行为测试：两字段往返、非法 ID、null/missing、同名不同 ID 成对提交、缺 ID 的回执不确认；运行观察缺失 cityId 行为失败。
- [x] 实现模型、序列化、Patch、掩码与提交分组，以及数据库所有读写入口；不转换旧 city。
- [x] 扩展真实 SQLite 用例：旧表加列、重启、旧实例保存、清空及回执保护。运行 `bash scripts/check_site_props.sh`、`python3 scripts/check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk`，预期所有相关组 PASS。

### Task 2: 城市目录 API、语言和快照缓存

文件：CityCatalog.swift、新增 CityCatalogStore.swift / CityCatalogService.swift、NetowrkReqeustApi.swift、CityCatalogTests.swift、新增 CityCatalogStoreTests.swift、API fixture、check_site_creation.sh。

接口：`CityCatalog(response: [String: Any], countryCode: String) throws`、`cacheData(fetchedAt:)`、`entry(id:)`、`displayTitle(for:language:)`；store 提供按 countryCode 的 `startIfNeeded`、`retryIfUnavailable`、`catalog`、`phase`、`revision`、观察/解除与当前使用国家保留。搜索 Loader 接收不可变 catalog，保持每个消费者自己的取消任务。

- [x] 先覆盖服务器样本、中文/其他语言全部 fallback、合法空列表、无效字段、同名区分及缓存往返；观察旧离线解析失败。
- [x] 实现模型和 `.siteCities(countryCode:region:)`，POST / gzip 响应协商、原始 name 保留、后台解析/搜索。
- [x] 先覆盖国家独立、去重、失败重试、写失败、迟到回调、LRU 回访及新进程，观察 store 缺失失败，再实现专用服务。
- [x] 运行更新后的 `bash scripts/check_site_creation.sh`，预期目录/缓存与既有国家测试 PASS。

### Task 3: 表单与回显

文件：SiteCreationDraft.swift、SiteCreateViewController.swift、必要的 SiteLocationSearchState.swift；CityCatalogTests / SiteCreationDraftTests。

接口：草稿 `cityName: String?`、`cityID: Int?`；`resolvedCity(in:)` 仅在两个字段完整且国家/ID 匹配时返回记录；选城市写 name/id，重选相同 ID 只更新名称，不重设坐标时区。表单按国家订阅 store，更新标题不用 replaceSelection 打断查询。

- [x] 先覆盖旧值 Not configured、按 ID 本地化、同 ID 改名、国家切换及手动值保护；观察旧 city-ID 语义失败。
- [x] 接入预加载/无缓存点击重试、共享搜索和回显、目录 revision 与 query ticket 检查、最新目录选择、离页与 active 恢复。
- [x] 运行 creation / props 回归，预期全部相关行为 PASS；UIKit 真实触摸仍留人工验收。

### Task 4: 资源与最终验证

文件：project.pbxproj、en/zh-Hans Localizable、旧 CityCatalog 目录及专用生成工具/测试；本文执行记录。

- [x] 删除已授权旧目录及专用工具，保留时区与国家资源；新增失败文案及六品牌源文件归属。
- [x] 运行相关回归、工程/本地化/资源及 diff 检查，核对 SDK realpath / revision / 未提交状态。
- [x] 串行构建六品牌 generic iOS Debug，复用稳定 DerivedData；完成独立只读审查和必要修正；记录真实 API / UIKit 待验收项。

### Ledger

- 起点：HEAD 1298ba2e；仅本文档未跟踪。现有 linked worktree，未创建新分支或改写 SDK。
- Pre-flight：Task 1 的 Int? ID 与 Task 2 的 Record.id 一致；Task 3 仅使用 ID 生成 UI 字符串，不持久化命名空间。Task 2 的空目录属于有效快照；Task 3 无匹配时不产生字段修改。
- Ruling：按用户已有确认直接执行、主代理唯一写入、保留未提交交付；进度记录在本文件，覆盖技能默认的另建计划/频繁提交流程。
- 基线命令修正：SQLite 脚本要求 SDK 参数，首次不带参仅产生 IndexError；改用上文完整命令，不属于业务回归失败。

- Task 1：模型/Patch/JSON/SQLite及更新字段分组已完成；先观察 cityId 被旧解析忽略的失败，再通过类型、缺失/null、名称/ID成对提交与 ACK/retrieve 验证。SQLite 加列不转换旧数字 city、不产生 pending；独立旧对象保存仍保留新 ID。
- Task 2：US 21016 条 API 样本与语言/坐标/坏数据/空目录测试通过；store 的按国家去重、冷失败重试、旧缓存保留、新进程刷新、晚到回调、LRU回读及写失败保留测试通过。仅测试目录保留 US API 夹具及许可；未复制含凭据的 Site demo。
- Task 3：共用 Create/Edit 预加载、首次聚焦/已聚焦点击重试、目录版本与查询 ticket、最新记录选择、标题刷新及 App active 门禁已接入。草稿与显示分离，语言回退、旧项目缺字段、同 ID 改名、手动/GPS 值保护和取消搜索行为测试通过。UIKit真实事件链仍待人工验收。
- Task 4：旧目录 251 个文件及专用生成工具/测试已删除；六品牌均检查 CityCatalog/Store/Service 三文件恰好归属一次，时区/国家与本地化资源仍保留，API测试夹具未归入App。工程与中英 strings 的 plutil、git diff --check通过。
- 独立审查：城市/UI 和 Site持久化/回执各一次只读审查。修复搜索completion在inactive期间仍可更新列表的门禁缺口；真实SQLite复现旧full-upload回执覆盖新城市pending及版本的P1后，改为确认前恢复数据库最新表单状态，再只确认已提交版本。保留原始timezone，失败回滚基于当前数据库状态；新增old SiteUpload/Add ACK、失败、重启、paired retry用例由RED变GREEN。修复后只读复核未发现新的明确可行动问题。
- 关联保护：历史仅含city位的pending在真正重试时扩成city/cityId一对，保留原city及原待提交时间，不自动迁移；补充retrieve缺名称/缺ID/错误ID不能确认pending的行为测试。入站独立Patch语义保持不变。
- 最终回归：`bash scripts/check_site_creation.sh`、`bash scripts/check_site_props.sh`、`python3 scripts/check_site_hdb_persistence.py .local-sdk/nordic-sig-mesh-sdk`、`python3 scripts/check_site_transfer.py` 均通过。回执共用入口的 `python3 scripts/check_space_recovery_receipts.py` 也通过（含 Site-only、addSpaces、初始时区与保存失败）。SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六品牌最终代码均通过 generic iOS Debug 构建，使用 iPhoneOS SDK、关闭签名；未使用 Simulator 或安装真机。
- 构建环境：SunSmartLocal workspace，SDK realpath `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `dbcf6f1a7014320331f3cccdc0a46edc1a0baa88`。SDK存在既有 MeshProxyMessageCommand/SchedulerActionStatus 修改和三个 SchedulerReadback 测试/脚本未跟踪项，本次没有改动；不依赖新增SDK API。稳定 DerivedData 为 `SunSmart-feat-daylight-saving-261024-cli`。
- 验证过程修正：资源检查跳过没有fileRef的Package build项；回执综合脚本不接受SDK目录位置参数，改为无参运行；SQLite旧失败回滚断言改为已同步的当前数据库确认时间，而不是过期对象的旧值。未据此修改无关业务。循环包装的xcodebuild遭遇workspace/环境访问失败，恢复逐条直接xcodebuild，并显式指定工作目录。

- 构建包复核：六个 .app 均有可执行文件、时区资源和新增中英文重试文案；均无旧 CityCatalog 目录与测试 JSON。Xcode正常移除了增量产物里的旧目录，无需 clean。
- 构建告警：既有资产符号重名、重复编译条目、Info.plist资源引用、弃用API和capture警告未纳入本次修改。部分quiet输出出现“command failed with exit code 0”诊断，命令实际返回0；用普通输出复核相关品牌的最终 BUILD SUCCEEDED，不把该文字当作业务代码失败。
- 交付：全部改动留在当前 `feat/daylight-saving-261024` 工作树，未commit/push/merge，未清理其他分支或缓存。没有修改SDK/后端/固件。真实四接口往返、四分区城市一致性、App gzip传输及UIKit点击/语言/生命周期验收仍按第10～11节执行；自动化与编译结果不替代这些运行验收。
