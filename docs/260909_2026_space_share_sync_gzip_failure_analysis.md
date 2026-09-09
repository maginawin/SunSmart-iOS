# Space 分享前云同步失败分析与解决方案

日期：2026-09-09。范围：用户提供日志及当前 `fix` 工作树源码；本次仅分析、记录方案，未修改业务代码、SDK 或服务器，未向生产同步接口发送请求。

## 结论

直接故障是请求压缩能力不匹配：App 对 Site/Space 上传自动使用真实 gzip，当前服务链路却将压缩字节直接作为 UTF-8 JSON 解析，因此两个上传接口均返回 HTTP 400。修复传输契约是恢复同步的第一步。

另有一项放大重试成本的 App 行为：明确的 JSON 解析拒绝没有清除本次待确认提交回执；重试前反复读取旧云配置，再次发送相同编码的请求，继续失败。

目前不能确定缺失解压发生在反向代理、请求中间件还是业务 parser，也不能仅凭日志认定服务器数据库丢失数据。需要服务端入口日志/部署配置定位具体层。

## 日志证据

| 项目 | 观察 | 含义 |
| --- | --- | --- |
| Site 上传 | `/sitespace/sync/siteprops`，`syncSpaceCount=0`，gzip 请求体 34,370 bytes | 即使不携带 Space 全量配置，Site 上传也触发同一错误 |
| Space 上传 | `/sitespace/sync/spaceprops`，兴东，gzip 请求体 297,940 / 290,796 bytes | 实际压缩已发生，不是仅误写请求头 |
| 编码诊断 | `declaredContentEncodingGzip=true`、`actualBodyGzip=true` | 请求头与发送字节一致 |
| 上传响应 | HTTP 400，`code="parse_error"`，`UTF-8 ... byte 0X8B in position 1` | JSON 解析前没有正确完成请求解压 |
| 查询响应 | `get/siteprops`、`get/spaceprops` 为 HTTP 200，gzip 响应解码成功 | 读取链路可用，不能据此推断上传解压能力 |
| 回读结果 | submitted/local timestamp=1788868768，remote timestamp=1788762647 | 日志持续读到较旧云配置 |
| 内容差异 | 本地/云端均 500 Nodes，但云端多出 2 个身份、缺少 2 个身份；Groups 17 对 16 | 数量相同不能说明配置同步完成 |

gzip 的前两个标识字节为 `1F 8B`，与 position 1 的 `0X8B` 完全对应，参见 [RFC 1952 §2.3.1](https://www.rfc-editor.org/rfc/rfc1952.html#section-2.3.1)。请求中的 `Content-Encoding` 描述请求体编码；`Accept-Encoding` 用于协商响应编码，参见 [RFC 9110 §8.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-8.4) 与 [§12.5.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-12.5.3)。响应支持 gzip 不意味着服务端能够解析 gzip 请求体。

## 源码与完整失败链路

1. `SunSmart/Main/Site/Controller/SiteViewController.swift` 的 `shareSpace`（约 2116 行）检查同步任务及 `space.needUploadCloud`。需要上传时入队 `syncSpace` 或 `syncSite`，提示先同步并返回，尚未进入 `spaceShare/shareInfo` 请求。
2. `SunSmart/Common/Data/SpaceData.swift:126` 通过本地更新时间与已上传时间判断 `needUploadCloud`。上传失败无法推进确认状态，下一次分享继续经过同步门槛。
3. `SunSmart/Common/Cloud/CloudSynchronizationManager.swift:974` 在重试上传前调用 `resumeUpload`；约 1016 行持久化即将提交的配置回执，再执行网络请求。`phase=prepared` 只说明已准备并记录提交，不证明服务端已接收。
4. `NetowrkReqeustApi.swift` 的 `task` 先用 `JSONEncoding.default` 生成 JSON；真正压缩发生在 `NetworkRequest.swift:48` 的 request closure 所调用的 `HTTPBodyEncoding.prepare`（约 521 行）。它按 URL 后缀匹配两个 sync 接口，只要请求体达到 1024 bytes 就 gzip，没有按服务器地区或已验证能力判断。
5. 上传被 HTTP 400 拒绝。`NetworkRequest.swift:140` 把字符串业务码 `parse_error` 按整数读取为 0，所以日志出现 `errorCode=0`；HTTP 400 和响应文本仍被保留，0 不是成功。
6. `SpaceConfigurationSafety.swift:415` 的 `rejectSubmission` 仅对若干权限/资源错误清除提交回执，通用 `.apiError` 的解析失败不在其中，因此本次 `prepared` 回执保留。
7. 下次重试由 `resumeUpload`（约 461 行）先回读最多三次，每次间隔 0.5 秒。只有配置匹配才确认成功；若第三次仍不匹配、回执为 `prepared`，且远端仍匹配最后确认基线，则允许移除旧回执并重传；否则保留冲突保护。日志里三次 mismatch 后出现新 export/upload，与这条基线回退路径吻合，但日志未直接打印基线匹配结果。
8. 重传仍自动 gzip，再次 HTTP 400。新旧两组 submissionId 表示不同提交回执，不表示已有一次上传成功。

当前日志开头已有旧 `prepared` 回执，其最初请求不在这段日志中，无法证明那次历史失败也由 gzip 引起。本次新上传的 gzip 400 及其后续循环则有完整证据。

## 回读及其他日志的边界

- Group 个数、配置散列及节点身份差异足以说明未收敛。按数组下标打印的 Group 字段差异，在 Group 集合不同的情况下也可能包含对齐错位；后续应按 Group address、Node UUID 对齐分析，不能把每一行下标差异都解释为同一个对象被改坏。
- `differencesShown=24 scanLimited=true` 表示差异展示截断，不能认为只有 24 处。
- `preserved pending local deletion/recovery` 是保留本地待处理状态，不能据此认定发生了新的删除操作。应保留本地配置、删除日志及恢复信息，不能通过清缓存、强制拉云覆盖或手工标记同步成功绕过问题。
- `invalidRemoteTopology` 属于另一个 Space（ID 前缀 `78F5111F`）：远端 59、本地 60 Nodes，且存在 sequence 修复项。应单独检查路径引用与节点归属；它不是兴东上传 UTF-8 400 的原因。`hardErrors=[:]` 并不代表可以忽略未应用的拓扑修复。
- `ProximityLightingExport groups=0` 统计的是 Proximity Lighting 导出部分，不能直接等同整个 Space 的 Groups 数组为空。
- Site 导入约 12.17 秒、部分主线程 export 约 2.85 秒会加重卡顿和等待，但不会导致服务端把 gzip 当 JSON。
- UIScene、全屏/方向、空 App Group、系统连接元数据及启动测量警告，没有证据与本次 HTTP 400 有直接因果关系。

## 推荐解决方案

### P0：恢复上传传输兼容

优先在 App 共享 `HTTPBodyEncoding` 入口将这两个同步接口默认恢复为普通 UTF-8 JSON 请求体，同时不声明 `Content-Encoding: gzip`，继续保留 `Content-Type: application/json` 和 `Accept-Encoding: gzip`。必须同时调整请求体和头，不能只删请求头而继续发送压缩字节。

这项修改同时覆盖 Site 同步、Space 同步以及调用同一入口的品牌；不需要改分享业务、Mesh 同步或 SDK。当前逻辑跨地区生效，后续若保留压缩，必须以服务端/地区和接口已验证支持为前提，不能假定各品牌后端同步部署。

代价是上传流量增加。500 节点请求应验证实际未压缩体积、服务端请求大小限制及耗时；当前默认请求超时为 10 秒，不应未经测量就把超时作为根因或直接放大。

长期服务端方案是在进入 JSON parser 前按 Content-Encoding 解压请求体，支持正常 identity JSON 和真实 gzip，对损坏压缩体明确拒绝并限制解压后大小。先核实已发布旧客户端是否存在 gzip 请求头配普通 JSON 的历史形态，如存在则设计有限兼容。所有业务实例、地区及代理链路部署一致并验收后，App 才按能力启用压缩。

### P1：区分明确拒绝与结果未知

- 网络层保留字符串业务码（如 `parse_error`）和 HTTP 状态，为恢复层提供明确分类，避免只剩整数 0。
- 对已确认在解析阶段拒绝、没有进入业务写入的错误，结束本次提交回执；保留本地脏状态、待同步配置及删除/恢复日志。下一次同步可直接按兼容编码重新提交。
- 清理必须匹配 account、region、site、space、生命周期和 submissionId，防止旧请求回调影响新提交。
- 不能把所有 400/4xx、超时、断网或 5xx 一概当作“未写入”；结果未知时仍需要现有回读保护。不对结果未知的 POST 自动盲目换编码重发。
- 已持久化的旧 `prepared` 回执可能没有明确失败证据。保留现有基线匹配恢复路径；若基线不符，保留冲突并比较本地/远端配置，不能批量清掉历史回执。

### P2：保留分享一致性门槛

成功条件仍是业务上传成功后回读配置匹配，再推进确认时间和同步状态。HTTP 200、节点数量相同、拿到 shareCode 都不能单独替代配置验收。不放宽 Node UUID、Groups、Profile 等一致性检查。

## 验证计划

1. 更新 `Tests/Group/SiteEntryPerformanceTests.swift` 的编码用例：当前只验证“大请求必须 gzip”及压缩往返无损，没有服务端能力契约验证。改为覆盖默认 JSON、已验证能力下的 gzip、两个同步接口、小/大请求、Header/Body 一致及响应压缩保留。
2. 补充恢复行为测试：明确 parse_error 不遗留本次未知回执；超时/5xx 保留回读；旧回调不修改新回执；历史 prepared 基线匹配可安全重传，真正冲突继续保护。
3. 验证共享网络层影响的所有品牌 target，按工程规则直接运行 generic iPhoneOS `xcodebuild`，不使用 Simulator。
4. 使用授权测试数据，在实际服务端验证 Site-only、兴东类似的 500 节点 Space、首次失败后重试及重启恢复。先确保上传不再 400，再验证回读散列/身份/配置一致、确认时间推进、pending 解除。
5. 真机验证完整操作：进入 Site → Space 更多菜单 → Share → 提示同步 → 同步成功 → 再次 Share → 展示分享页面；由另一个授权客户端读取并核对配置。现有分享入口同步后会 return，应按实际交互再次触发分享验证。
6. `78F5111F` 的拓扑异常独立验收，不以本次 gzip 修复宣称所有 Space 数据问题解决。

本次完成的是日志与源码分析。未执行构建、未改变服务器、未做真机/服务端验收，修复效果仍须以上述验证确认。
