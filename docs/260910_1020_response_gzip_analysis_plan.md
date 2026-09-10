# HTTP gzip 响应核查与更新计划

日期：2026-09-10。范围：当前 `fix` 工作树；本轮仅分析和规划，没有修改 App/SDK，没有发送业务接口请求或执行构建。

## 结论与当前实现

用户已测试确认 `/sitespace/get/siteprops`、`/sitespace/get/spaceprops` 支持 gzip 响应；服务器暂不支持 gzip 请求体。该结论作为本次规划输入，不推断其他接口或其他地区已经支持。

当前源码已经符合这两个查询接口的请求要求，无需重复添加头：

- `SunSmart/Common/Network/NetowrkReqeustApi.swift` 的 `headers`（约 618 行）为 `.siteInfo`、`.spaceInfo` 显式设置 `Accept-Encoding: gzip`；现有 `.siteUpload`、`.spaceUpload` 也设置同一响应协商头。
- 同文件 `task`（约 594 行）使用 `JSONEncoding.default`；无参数接口使用 `.requestPlain`。旧 gzip 请求体代码已注释，不执行。
- `SunSmart/Common/Network/NetworkRequest.swift` 的请求闭包（约 48 行）统一调用 `HTTPBodyEncoding.prepare`（约 537 行）。它清除请求 `Content-Encoding`，保持正文原始字节；两个同步路径额外清除旧 `Content-Length`。此路径也覆盖 `.siteAdd`。
- 现有 `Tests/Group/SiteEntryPerformanceTests.swift` 编码用例覆盖两个查询和两个同步路径：大小 JSON、UTF-8、正文不变、移除请求 Content-Encoding、保留 Accept-Encoding、重复准备。本轮只阅读测试，未运行。

因此应区分“当前工作树已有实现”与“设备上安装版本已包含该实现”。本轮没有核对设备 App 版本或抓取线上请求。

### 共享会话默认值

`NetworkRequest.swift` 使用 `URLSessionConfiguration.af.default`。本地 `Pods/Alamofire/Source/Extensions/URLSessionConfiguration+Alamofire.swift` 为会话安装默认 headers；`Pods/Alamofire/Source/Core/HTTPHeaders.swift`（约 349–367 行）的默认 Accept-Encoding 包含 `br`、`gzip`、`deflate`（按系统版本及权重生成）。

所以未进入显式 headers 分支的接口，不等于从未协商 gzip。后续新增显式 `Accept-Encoding: gzip` 是按已验证接口限定编码；是否减少流量，要比较实际响应与传输指标。计划保留其他接口现有默认行为，不全局改为 gzip 或 identity。

请求中的 Accept-Encoding 表示可接受的响应编码；请求中的 Content-Encoding 描述请求正文自身编码。响应端返回 Content-Encoding: gzip 是正常验收证据，与禁止压缩请求体不冲突。Accept-Encoding: gzip 也允许服务器返回普通 identity 响应，App 不应将这种响应判为错误。参见 [RFC 9110 §12.5.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-12.5.3) 与 [§8.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-8.4)。

## 候选接口与测试优先级

以下优先级根据当前 App 消费的数据结构推断，尚未测量各接口实际大小。统一由 `NetowrkReqeustApi` 发起的接口均为 **POST**，即使路径中含 `/get/`。路径追加到当前地区的 baseURL（包含 `/srv2`），请求保持原来的普通 JSON；复用现有合法身份及品牌请求头，不新增 Auth。

| 优先级 | 接口 / App case | 可能较大的数据及建议场景 | 当前调用证据 |
| --- | --- | --- | --- |
| 高 | `/sitespace/get/sitelist` / `.sites` | `data.sites[]`，逐项导入 Site；选 Site 多、Space 多的账号。是否携带全量节点需看实包，不能只凭导入函数判定。 | `SitesViewController.swift:298` |
| 高 | `/sitespace/share/receive` / `.receiveSite`、`.joinSpace` | 接收 Site 返回 `data.site` 并导入，另有 provisioner/exclusions；大 Site 转移优先。批量加入返回 `data.spaces[]` 结果列表，单 Space 加入目前忽略响应内容，收益需分场景测。**会改变归属/成员关系，使用专用测试 Site 和账号。** | `SharePermissionSelectionController.swift:131,189,270` |
| 高 | `/sitespace/ota/configfile` / `.devicesConfig` | 返回设备配置目录数组；型号数增加时增长。虽然名称含 configfile，当前业务按 JSON 数组读取，并非 ZIP 下载。 | `SitesViewController.swift:479` |
| 中 | `/sitespace/site/batchshare/list` / `.batchShareList` | `data.batchList[]` 内嵌 `spaces[]`；选择批次多、每批 Space 多的 Site。 | `ShareBacthListViewController.swift:64` |
| 中 | `/sitespace/share/info` / `.shareInfo` | 分享信息；批量分享的 `spaces[]` 最值得测试。App 对单 Space 和转移预览主要取摘要，不能认定它们返回全量配置。 | `SitesViewController.swift:402`；`SharePermissionSelectionController.swift:583` |
| 中 | `/sitespace/sapce/gateway/reference` / `.gatewayAssociationSpaceList` | `data.refSpaces[]`，网关关联 Space 列表；选关联 Space 多的网关。**路径的 sapce 是现有 API 拼写，测试时保留。** | `GatewayAssociatedSpacesController.swift:74`；`GatewayViewController.swift:638` |
| 较低 | `/sitespace/ota/history` / `.firmwareVersionList` | 固件版本数组与版本说明；选择历史版本多、说明长的产品。 | `FirmwareVersionHistoryController.swift:108` |
| 较低 | `/sitespace/space/singleshare` / `.spaceMembers` | `data.visitors[]`，访客很多时增长；同一路径也用于 `.spaceShare`，需按请求用途验证。 | `SpaceVisitorListViewController.swift:62` |
| 较低 | `/sitespace/get/activeuser` / `.spaceActiveMembers` | 活跃成员查询，通常规模有限；多人同时在线时测试。 | `SpaceViewController.swift:958` |
| 备用 | `/sitespace/site/gateways` / `.gatewayList` | API 枚举定义为 Site 网关列表；本次搜索未找到 App 业务调用点，返回规模也未证实，不作为首批 App 更新重点。 | `NetowrkReqeustApi.swift:346,571` |

### Apifox 参数参考

这里只列字段，不记录实际账号、密码、分享 token、品牌凭据或 Mesh 密钥。身份字段按原请求填写。

| 接口 | 普通请求参数 |
| --- | --- |
| `/sitespace/get/sitelist` | userId |
| `/sitespace/share/receive`，接收 Site | token、passwd、user（userId、username） |
| `/sitespace/share/receive`，加入 Space/批量加入 | token、passwd、roleName、user（userId、username） |
| `/sitespace/ota/configfile` | 当前 App 无参数、无正文 |
| `/sitespace/site/batchshare/list` | siteId、userId |
| `/sitespace/share/info` | token、userId |
| `/sitespace/sapce/gateway/reference` | siteId、gatewayId |
| `/sitespace/ota/history` | manufacturerId、deviceType、customerId；测试固件额外 profile=dev |
| `/sitespace/space/singleshare`，成员查询 | siteId、spaceId、userId |
| `/sitespace/get/activeuser` | siteId、spaceId |
| `/sitespace/site/gateways` | siteId |

### 暂不作为大 JSON 响应重点

- `/sitespace/sync/siteprops`、`/sitespace/sync/spaceprops`：请求正文大，不证明响应大；现有上传 case 已有 Accept-Encoding: gzip，保留普通 JSON 请求。`.siteAdd` 也走 sync/siteprops，但尚未显式设置该响应头，仍使用会话默认值；如测试同步响应，可同时记录创建与上传的区别。
- `/sitespace/retrieve/siteprops`：当前仅请求 timezone、imageId、siteName、updateTimestamp，属于 Edit Site 小字段查询，不能与 `/get/siteprops` 混同。
- `/sitespace/ota/latest` 和常见增删改/心跳/状态回执：没有证据表明优先级高于上述列表。
- `/sitespace/ota/download` 或服务器返回的固件 URL：App `ZipHandler` 使用独立 URLSession 下载 ZIP，部分 URL 交给网关下载；需要按实际下载方和文件格式单独评估，不纳入本次 JSON headers 分支。
- 当前 Energy Harvest 历史页面通过 `EnergyStatisticsStaticData.load(spaceId:)` 读本地数据库，本次未发现独立的大能耗历史 HTTP 查询入口。

## 服务器测试与回传记录

1. 查询类接口用相同账号、参数和稳定数据，分别设置 Accept-Encoding: identity 与 gzip。请求正文保持普通 JSON，均不添加请求 Content-Encoding；configfile 保持无正文。
2. 使用有足够数据的成功业务响应测试。HTTP 200 或小错误响应不足以证明大数据 gzip 路径可用；小响应没有压缩也可能只是阈值策略。
3. 记录响应 Content-Encoding、Content-Length（如有）、传输大小、解码后大小、耗时、HTTP 状态及业务码。Apifox 展示的格式化 JSON 可能已经解压，不能据展示内容断言未压缩。
4. 检查 gzip 解码后 JSON 业务字段与 identity 一致；动态时间戳可按字段解释差异。确认 Site/Space/成员/版本列表不丢项。
5. share/receive 有业务副作用，不对同一转移 token 机械重放两次。使用两组等价独立测试数据，或由服务器测试环境复位后比较；分别记录接收 Site、单 Space、批量 Space 的结果。
6. 按测试地区/域名记录能力。仅一个地区通过不能代表其他地区也通过。App 接入后使用现有 `[HTTP][Metrics]` 的 encoding、receivedBytes、decodedBytes 复核传输效果，并检查最终请求头。

建议回传格式：接口、场景、地区、HTTP/业务结果、响应 Content-Encoding、压缩传输字节、解码后字节、耗时、数据一致性。

## 后续实施计划

1. 保留 `.siteInfo`、`.spaceInfo` 已有显式 Accept-Encoding: gzip。根据用户测试结果，将通过的候选 case 加入共享 `NetowrkReqeustApi.headers` 分支；测试结论限定于某地区时，按实际覆盖范围决定策略。
2. 请求继续保持普通 JSON/现有无正文形式，保留 `HTTPBodyEncoding.prepare` 的请求 Content-Encoding 清理；不恢复真实 gzip 上传，不改 SDK、导入格式或 UI。
3. 使用 URLSession/Alamofire 现有响应解码链路，不在 JSON 解析前仅凭响应头再次手动 gunzip；验证 gzip 与 identity 都能进入现有业务解析。
4. 验证最终 URLRequest 的 Accept-Encoding 精确值、无请求 Content-Encoding、正文不变；覆盖已确认接口、新增接口及上传/创建兼容。复用现有编码回归检查，补充必要的候选接口契约覆盖。若将来纳入 Edit Site retrieve，应同步调整 `SitePropsAPIContractTests` 中将“未进入 gzip headers 分支”等同于普通 JSON 的旧断言。
5. 共享网络代码被 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 五个品牌 target 引用，实施后直接执行各 scheme 的 generic iPhoneOS Debug xcodebuild，关闭签名，不使用 Simulator；本次仅规划无需构建。
6. 真机验证相关列表/分享/导入流程及指标；构建和本地测试不能替代服务器压缩与业务结果验收。响应压缩改善传输量，不直接消除解码、数据库写入或 Mesh 导入耗时。

本轮交付：源码现状核查、候选接口清单、测试参数与更新计划。实际待新增接口由用户服务器测试结果确定。
