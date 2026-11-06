# 创建 Site 与 Space 时 siteprops 请求次数分析

日期：2026-11-06。分支：`feat/daylight-saving-261024`，HEAD：`59be4df7ffe3427af1fad1a45a6514e2813eb1ed`。

分析使用当前工作树（包含已有未提交修改）和本轮用户贴出的日志。只新增本文档，不修改 App、SDK、数据库或 export JSON 结构，不操作服务器。

## 1. 结论与缺失证据

**这份日志显示一次 App 业务上传：创建 Site 时携带一个 Space，一次请求成功。两行 HTTP Metrics 不是两次业务调用的证据。**

同时，代码确实有两个入队入口：创建 Site 后上传 Site，以及完成 Space 表单后上传新增 Space。是否产生两次 HTTP 上传取决于第一个任务是否已经发出。当前日志不能证明第二个请求发生，也不能还原底层为什么产生两条 transaction metrics。

还发现一个需要单独复现的边界：旧任务已发出 HTTP、尚未确认时，新建 Space 可能取消并替换旧任务，但 Swift Task 的取消没有连接到该异步请求的底层 Cancellable。不能把“取消旧队列项”视为“服务器没有收到旧请求”。这不是本次日志已经证实的触发原因。

## 2. 日志计数应分层看

| 日志 | 本次数量 | 含义 |
| --- | --- | --- |
| `[CloudSync][Request]` | 1 | 同步层准备发出一次业务请求 |
| `[HTTP][Request]` | 1 | 网络插件记录同一次请求；不是另一次请求 |
| `[HTTP][Metrics] task=21` | 2 行 | 同一个 URLSession task 的 transaction 统计 |
| `[HTTP][Response]` | 1 | 一次最终响应，HTTP 200、业务码 200 |
| `[CloudSync][Success]` | 1 | 同步层完成处理 |
| `SiteImportTiming ... scope=export:<同一个 Space>` | 3 组 | 本地数据导出，不是 HTTP 请求 |

该请求的 `operation=syncSite`、`apiTarget=siteAdd`、`syncSpaceCount=1`，所以是“Site 和 Space 一起上传”，不是必须再发一次 Space 请求。

`NetworkTransferMetricsMonitor` 在 `NetworkRequest.swift:590` 的一次回调内遍历 `metrics.transactionMetrics`，每条都打印同一个 `task.taskIdentifier`。Apple 将其定义为一个任务执行期间各次 request-response transaction 的统计数组，一个 task 可以有多条统计：[Apple transactionMetrics 文档](https://developer.apple.com/documentation/foundation/urlsessiontaskmetrics/transactionmetrics)。

这里第一条 `receivedBytes=0, decodedBytes=0`，第二条为 `154/145`。这些值不能单独证明有两次 POST 到达服务器，更不能证明两次业务写入。现有日志没有记录 transaction 序号、`resourceFetchType`、HTTP 状态、重定向数量和发送字节，无法区分具体的网络加载过程。`encoding=identity` 还可能来自 response 为 nil 时的默认值（`NetworkRequest.swift:594`），不能由它推断第一条已经收到响应。

`nw_connection...unconnected` 提示与统计日志相邻，但不足以确认发生了重试、重定向或重复业务提交。请求体 gzip 压缩与这些统计行的数量没有已证实的因果关系。

## 3. 两个业务入口及队列行为

### 创建 Site

1. `SiteCreateViewController.submitForm` 调用 `SiteData.add`，保存本地 Site，再关闭表单并回调。
2. `SitesViewController.showCreatedSite` 打开 `SiteViewController(addSite: true)`，调用 `startCreatedSiteSynchronization`。
3. 入队 `.syncSite(site: site)`，其默认 `syncSpaces=[]`，级别 `.normal`。
4. `.normal` 的延迟为 5 秒，由主队列定时器触发。

代码：`SiteCreateViewController.swift:1187`；`SitesViewController.swift:663、675`；`CloudSynchronizationManager.swift:42、223、1193`。

### 创建 Space

1. Site 页首次显示，`viewDidAppear` 消耗 `addSite` 标记，自动打开 Space 表单。
2. `InfoEditViewController.doneBtnClick` 执行 `doneCallback`。
3. `SiteViewController.addSpace` 调用共享 `site.addSpace` 保存 Space。
4. 如果页面 Site 的 `uploadCloud` 为 true，入队 `.addSpaces(site, [space])`；否则入队 `.syncSite(site, site.spaces)`。同样等待 5 秒。

代码：`SiteViewController.swift:248、1792、1823`；`InfoEditViewController.swift:110`；`MeshNetwork+SunSmart.swift:89`。

### 为什么两个入口不一定产生两次请求

普通入队会查找匹配操作，取消并移除旧任务，再创建新任务。旧 `.syncSite(site, [])` 与新 `.syncSite(site, [space])` 可以匹配，因为比较规则允许旧任务的 Space 列表为空。因此，初次 Site 上传尚在等待时提交 Space，会用包含 Space 的任务替换旧任务，并重新等待 5 秒。

这里准确地说是“取消旧任务后替换”，不是两个普通任务共享同一次完成回调。代码位置：`CloudSynchronizationManager.swift:60、700、723、736`。

| 提交 Space 时的状态 | 请求表现 |
| --- | --- |
| 创建 Site 的任务仍未发出 | 旧任务被替换；正常路径只发一次 `siteAdd`，含一个 Space。与本次日志一致，但缺少入队时间，无法直接证明具体操作间隔。 |
| Site 已成功上传 | 先前已发过不含 Space 的 `siteAdd`；新增 Space 通常走 `addSpaces → siteUpload`，再发一次同路径请求。两次业务内容不同。 |
| 创建 Site 的 HTTP 已发出、还没有确认 | 新任务可能替换旧任务，但已发出的 HTTP 仍可完成。新任务生成 API 时如果本地已确认 Site，则用 `siteUpload`；如果仍未确认，可能仍用 `siteAdd`。需要慢网时序复现，不能根据本日志判定。 |

`siteAdd` 和 `siteUpload` 都映射到 `/sitespace/sync/siteprops`；`addSpaces` 当前也生成 `siteUpload`。所以只看 URL 无法判断是重复创建、首次创建后补充 Space，还是同一业务请求的不同日志层。

代码：`CloudSynchronizationManager.swift:84、125`；`NetowrkReqeustApi.swift:300、420、428`。API 生成前还会重读本地 Site，因此最终 `apiTarget` 比仅观察 UI 入队分支更可靠。

## 4. 三次导出的来源

当前上传准备路径中，同一个 Space 正常就有三次导出：

| 次序 | 作用 | 入口 |
| --- | --- | --- |
| 1 | 导出原始本地配置，检查/规范化同步引用和拓扑 | `SpaceSyncCleanupCoordinator.swift:171`，`.cleanupInspection` |
| 2 | 重读保存的 Space 后再次导出，复核清理结果和保存状态 | 同文件 `:226`，`.cleanupInspection` |
| 3 | 生成最终 Site 请求中包含的 Space 数据 | `ExportData.swift:369`，`.cloudSync` |

`getNetworkApi` 先执行 `prepareBatch`，再执行 `site.export`，与用户日志中的三组导出后才出现请求一致。`networkReused` 指复用 Mesh 网络对象，不是复用或重发 HTTP 请求。

日志未包含 export purpose 或调用栈，因此上述三组与具体 trace UUID 的逐一映射是基于代码顺序的解释；日志本身只能直接确认发生三次本地导出。

## 5. 已发出请求的取消边界

以下为当前源码可确认的事实：

- 普通替换逻辑未要求旧任务处于 `.wait`，因此可能替换 `.inProgress` 任务（`CloudSynchronizationManager.swift:723`）。
- `cancel()` 会取消 `configurationUploadTask`，也调用 `requestHandle?.cancel()`（`:1180`）。
- 配置上传实际使用 `await NetworkRequest.shared.request(api)`（`:1520`）。该异步封装通过 continuation 调用 callback 版本，未把返回的 Cancellable 交给当前 handle，也未连接 Swift Task 取消（`NetworkRequest.swift:78`）。
- 请求回调后仍可能先确认已成功的 Site，再在 `:1545` 检查 Task 取消。保留已成功创建所分配的资源有其业务必要性，不能简单丢弃所有晚到回执。

因此若后续拿到两组真正的 Request，应先区分“首次创建成功后新增 Space”的正常两次上传与“第一次尚未确认就替换任务”的交错。若确认后者，最小修复方向应是让同 Site 的首次创建与后续增量串行衔接、保留创建回执及失败/未知结果恢复；仅延长 5 秒或仅取消底层 HTTP 都不能证明服务器未执行首次创建。

本轮未实施这个方向，也不以代码审查代替真实网络复现。

## 6. 最短后续验证与范围

无需因两条 Metrics 直接修改业务同步逻辑。先按同一个 Site 分别观察：

1. 创建 Site 后快速提交 Space：预期等待中的任务被替换，看到一组包含 Space 的 `siteAdd` Request。
2. 等第一次 Site 上传成功后再提交 Space：预期 `siteAdd(syncSpaceCount=0)` 后有一次包含 Space 的 `siteUpload`。
3. 首次 Site 上传已发送但未返回时提交 Space：记录两次 Request 的 `operation/apiTarget/syncSpaceCount` 及成功、失败、取消时序，确认是否命中进行中替换。

若只需解释两条 Metrics，最小诊断是给现有 DEBUG 日志补充 task/transaction 序号、resourceFetchType、statusCode、redirectCount、请求发送字节和关键起止时间；如需证明服务器实际收到了几次，仍需相应访问记录或抓包证据。无需输出请求体、凭据或密钥。

已完成：当前工作树入口、普通队列替换、API 映射、三次导出和网络日志实现核对，并核对 Apple 指标定义。未执行：App 构建、真机操作、真实 HTTP 重放、服务器检查及慢网取消回归。按分析任务规则不构建。

新增 Space 后 Site 内存时间与保存时间不一致造成同步图标的问题，继续以[已有分析第 11 节](261106_1044_created_site_sync_badge_analysis.md)为准；不能把图标误显示等同于实际又发了一次请求。本轮没有关闭或修改该问题。
