# Site Gateway Cloud Timezone Sync 需求完整性分析

## 1. 文档状态

- 日期：2026-08-15
- 状态：需求分析完成，触发范围与 Gateway 列表口径均已确认，等待架构设计确认
- 本轮范围：只分析现状、需求缺口和待确认项，不修改业务代码
- 目标接口：`/sitespace/gateway/datetime/update`、`/sitespace/request/status`
- UI 范围：Site 入口 `Time zone sync status` 弹窗中的 `GATEWAYS` 区域

## 2. 核心结论

当前需求方向明确，但还不能直接进入实施计划。至少需要先确认“哪些现有弹窗场景会自动启动 Gateway 云端同步”，随后再确认目标 Gateway 集合、Site 更新失败处理、结果落库/刷新以及生命周期口径。

当前源码行为与“只有 App 需要把 Site timezone 同步到服务器时才展示弹窗”的理解不一致：

- App timezone 胜出并上传 Cloud：展示弹窗，结果为 `Updated to server` 或 `Failed to update server`。
- Cloud timezone 胜出并更新 App：也展示弹窗，结果为 `Updated from server`。
- App 与 Cloud Site timezone 已一致，但授权 Gateway timezone 不一致：也展示弹窗，结果为 `Already in sync with server`。
- Visitor：静默采用 Cloud Site 数据，不展示弹窗，也不检查 Gateway。
- 两端 Site timezone 一致且授权 Gateway 也一致：不展示弹窗。

因此，第一项必须确认的是：新 Gateway 云端同步是覆盖上述全部现有可见弹窗场景，还是只覆盖 App 上传 Site timezone 的场景。

## 3. 当前源码事实

### 3.1 Site 入口状态决策

`SiteEntryTimeZoneSyncPolicy` 当前会产生以下与弹窗有关的决策：

- `showGatewayStatus`：Site timezone 相同，但授权 Gateway 有待同步项。
- `useRemote`：Cloud Site timezone 胜出并写入 App。
- `useLocal`：App Site timezone 胜出并提交服务器。

`SiteViewController.handleEntrySyncDecision` 会对以上三种决策统一排队展示 `SiteEntryTimeZoneSyncOverlay`。因此弹窗不是 `useLocal` 专属。

### 3.2 现有 Gateway 权限口径

当前已经实现权限范围计算：

- Owner：检查响应中的全部 Gateway。
- 非 Owner 且至少拥有一个 Editor Space：只检查 Editor Spaces 的 `gatewayId` 集合。
- 只有 Visitor Spaces：不检查 Gateway。
- 同一 Gateway 被多个 Editor Space 引用时按标准化 MAC 去重。
- 未知 Space role 不提升权限。

这部分可以直接作为新功能的权限基础，不应改用宽泛的本地可见列表重新推导。

### 3.3 现有 Gateway timezone 比较

当前已在导入 Site 响应前解析 `gateways[].macAddress` 和 `gateways[].timezoneOffset`，并按以下规则比较：

- 目标为最终仲裁后的 Site UTC offset 分钟数。
- Gateway offset 分钟数使用 `(timezoneOffset - 64) × 15` 转换。
- 缺失、非法或无法转换的 Gateway offset 按待同步处理。
- 本地存在尚未上传的有效 Gateway offset 时，当前逻辑可用本地 dirty 值覆盖旧 Cloud 值参与比较。

当前 `SiteEntryGatewaySummary` 只有 `noGateways`、`pending(count)`、`inSync`，只保存统计结果，没有保留弹窗逐行展示需要的 Gateway ID、名称和单项状态。

### 3.4 现有弹窗能力

`SiteEntryTimeZoneSyncOverlay` 当前的 Gateway 区域只有一张摘要卡：

- 无 Gateway。
- N 个 Gateway 待同步。
- 全部已同步。

当存在待同步 Gateway 时，当前显示 `LATER` 和 `REVIEW SYNC`，允许关闭或进入现场 BLE 同步页面；普通结果显示 `GOT IT`。新需求要求同步进行中不可关闭，全部终态后才显示 `DONE`，因此现有 Footer 状态和 Gateway UI 数据模型都需要重做，不能只替换两行文案。

### 3.5 网络层

项目网络入口是 `NetowrkReqeustApi + NetworkRequest`：

- 所有现有接口均通过 POST 和 JSON body。
- `NetworkRequest` 已把 HTTP/业务 code 非成功统一转换为失败。
- 新接口仍需要自己的严格响应解析，不能只把请求发出视为成功。
- `NetowrkReqeustApi` 的 path、diagnosticName、parameters 等穷举分支都需要同步增加新 case。

## 4. Figma 核查结果

已通过 Figma 结构化上下文确认以下设计语义：

- 成功行：16×16 成功图标、Gateway name、右侧 `Synced`，状态文字为辅助灰色。
- 失败行：16×16 失败图标、Gateway name、右侧 `Failed`，失败文字为 `#FF4831`。
- 进行中行：16×16 Loading 图标持续旋转、Gateway name、右侧 `Pushing…`。
- Gateway 卡顶部展示 `GATEWAYS` 与总数。
- 多个 Gateway 行之间有分隔线。
- 存在失败时，在 Gateway 卡下方增加失败统计卡，包含失败数量和 `Sync on-site via Bluetooth to complete.`。
- 所有 Gateway 得到终态后才展示底部 `DONE`。
- 完整设计是底部弹层，而当前实现是固定尺寸居中卡片；即使产品要求“只更新 GATEWAYS 相关组件”，为了容纳动态列表和 Footer，容器高度、滚动和底部约束也必须做最小配套调整。

Figma 连接器成功返回了成功行、失败行和完整结果弹窗；完整结果节点中也包含进行中行与失败统计卡。单独 Loading 节点与 No gateways 节点本次因连接令牌过期返回 401，尚未独立核对其精确尺寸。No gateways 的英文文案已由需求明确，且与项目早期设计文档一致。

## 5. 需求中已经完整的部分

- 两个接口路径、基础请求 body 和成功响应示例。
- 下发接口不传 timezone，由服务器使用当前 Cloud Site timezone。
- 下发成功后取得 `requestId`。
- 每 3 秒轮询一次。
- 3 分钟后把仍无终态的 Gateway 判定为失败。
- 下发接口直接失败时，全部目标 Gateway 判定失败。
- `Requested` 保持进行中；`Succeed` 成功；`Failed`、`Expired` 失败。
- `NIL` 和其他未知值不改变当前状态，最终可由超时收敛为失败。
- 只有 Owner 或 Editor Space 权限范围内的 Gateway 参与。
- 同步中不展示 `DONE`，所有目标得到终态后才允许关闭。
- 没有授权 Gateway 时展示 No gateways 空状态并允许 `DONE`。

## 6. 尚不完整或存在冲突的部分

### 6.1 弹窗和自动同步的触发范围

当前弹窗有三类可见业务场景，不只是 App 上传 Site timezone。需要明确：

- 新功能是否覆盖 `showGatewayStatus`、`useRemote`、`useLocal` 三种场景。
- 如果只覆盖 `useLocal`，是否要删除当前“Site 已一致但 Gateway 不一致也展示弹窗”的行为。
- 如果覆盖全部场景，`useLocal` 必须等待 Site timezone 上传成功后才能调用 Gateway 下发接口，否则服务器可能仍使用旧 Cloud Site timezone。

推荐覆盖全部现有可见弹窗场景，但必须把“Cloud Site timezone 已确认可作为目标”设为 Gateway 下发前置条件。具体顺序为：

- `showGatewayStatus`：App 与 Cloud Site timezone 已一致，可直接进入 Gateway 阶段。
- `useRemote`：先成功把 Cloud Site timezone 持久化到 App，再进入 Gateway 阶段。
- `useLocal`：先成功把 App Site timezone 更新到 Cloud，再进入 Gateway 阶段。
- 任一需要执行的 Site 更新失败：不得调用 Gateway 下发接口，本次待同步目标统一进入失败终态。

### 6.2 Site 更新失败时 Gateway 如何收口

当 `useLocal` 的 `/sitespace/update/siteprops` 失败时，Cloud Site timezone 不一定是 App 期望值。此时不能继续调用 Gateway 下发接口。

建议：

- 不调用 `/sitespace/gateway/datetime/update`。
- 把本次待同步 Gateway 全部标记 `Failed`，显示失败统计和 `DONE`。
- Site 行继续显示 `Failed to update server`。
- 失败说明仍引导用户通过现场 BLE 完成，但需要避免文案误导为“服务器已采用新时区”。

该口径已确认。

### 6.3 列表展示集合与接口目标集合

需求中的 N 同时被用于“有权限 Gateway 数量”和“需要同步 Gateway 数量”，两者可能不同。至少存在三种集合：

- 授权 Gateway。
- 授权且已与目标 timezone 一致的 Gateway。
- 授权且需要下发的 Gateway。

建议接口只发送第三类；弹窗列表也只展示本次下发目标，并在状态变化中从 `Pushing…` 变为 `Synced` 或 `Failed`。如果授权 Gateway 大于零但没有任何待同步目标，则展示全部已同步摘要并立即显示 `DONE`，不调用下发接口。

若产品希望列表展示全部授权 Gateway，则需要补充“进入弹窗前已经一致”的 Gateway 初始状态和 Header 数量口径。

### 6.4 Gateway 名称来源与缺失回退

远端比较快照当前只有 MAC 与 offset，没有名称。名称可在 Site 完整导入后用本地 `GatewayModel.name` 按 MAC 映射。

需要约定：

- 本地模型缺失或名称为空时显示原始 MAC，而不是空行或泛化 `Gateway`。该口径已确认。
- Editor Space 声明了 `gatewayId`，但 `gateways[]` 缺少对应对象时，当前策略会把它计为待同步；新接口虽然可使用 `gatewayId` 作为目标 MAC，但必须确认服务器允许这种不完整快照。
- Owner 响应中缺失有效 `macAddress` 的匿名 Gateway 无法下发，不能继续按普通可执行目标处理。

### 6.5 MAC 规范化与发送格式

当前比较只做去首尾空白和大小写归一。新接口要求实际 MAC 字符串，需要明确是否只接受 12 位无分隔符十六进制。

建议匹配键使用规范化小写值，发送时优先使用服务器响应中的原始非空 MAC；若服务器要求固定格式，再统一转为大写无分隔符。不要在没有服务端契约时擅自删除冒号或短横线。

### 6.6 `requestId` 和响应解析容错

示例是整数，但未声明范围和是否可能返回数字字符串。建议内部使用 Int64，并只接受正整数或可无损转换的正整数字符串；Bool、小数、零、负数均视为下发失败。

### 6.7 状态响应的异常数据

需要定义：

- MAC 大小写和首尾空白是否忽略：建议忽略。
- 同一 MAC 在一个响应中重复且状态冲突：建议终态优先，失败优先于成功只会掩盖真实成功，因此更稳妥的是把冲突视为未知并继续轮询，同时记录诊断日志。
- 响应包含本次目标之外的 MAC：忽略。
- 已进入终态后收到回退状态：忽略，终态不可逆。
- data 缺少某个目标：保持原状态，直到后续结果或超时。
- `NIL` 是字符串、JSON null 还是 key 缺失：三者都保持原状态。

### 6.8 轮询失败策略

需求只规定下发接口直接失败时全部失败，没有规定状态接口单次失败。

状态接口的网络错误、业务错误或结构错误都视为一次无结果，继续每 3 秒重试到 3 分钟截止。该口径已确认。若未来需要对鉴权或权限错误提前终止，应由服务端提供明确错误码契约后单独扩展。

### 6.9 超时起点与第一次轮询

建议：

- 3 分钟从成功取得合法 `requestId` 时开始。
- 第一次状态查询在 3 秒后发起，之后保持 3 秒节拍。
- 使用单调时钟判断截止时间，避免系统时间变化影响超时。
- 到达截止时间时，所有仍为进行中的目标一次性转为失败。

### 6.10 后台、销毁和重入

当前 Overlay 会锁定导航，但无法阻止 App 进入后台、进程被杀或内存释放。需求未规定 requestId 是否持久化。

本期不持久化 requestId，该口径已确认：

- 页面和进程存续时继续任务，后台时间仍计入 3 分钟总截止时间。
- Controller 销毁时取消本地轮询和 UI 回调。
- App 被杀后不恢复旧请求；再次进入 Site 时重新读取 Cloud Gateway timezone 决定是否创建新请求。
- 需要服务端确认重复下发是否幂等或可接受。

### 6.11 成功后的 App/Cloud 数据收敛

状态接口返回 `Succeed` 只证明服务器任务结果成功，不自动证明本次 `/get/siteprops` 快照已更新。若不刷新或更新本地真值，用户再次进入 Site 时可能仍被旧 `timezoneOffset` 判定为待同步。

建议所有 Gateway 终态后静默刷新一次 `/sitespace/get/siteprops`：

- 成功 Gateway 用最新 Cloud snapshot 收敛。
- 失败 Gateway 保持 Review sync/现场 BLE 入口。
- 刷新失败不改变本次已经展示的成功/失败终态，但保留后续重新校验机会。
- 不能仅凭状态响应臆造 Mesh Node 的完整 timestamp；除非服务端明确把该接口结果定义为可写入本地设备真值。

### 6.12 与现有 `REVIEW SYNC` / BLE 页面关系

新 Figma 的失败统计文案明确指向现场 Bluetooth。需要确认：

- 新弹窗完成后是否移除旧 Footer 的 `LATER` / `REVIEW SYNC`，统一只保留 `DONE`。
- `DONE` 后，失败 Gateway 是否继续通过 Site 页 `Review sync` Banner 进入现有 `SyncGatewaysViewController`。
- 全部成功时应清理过期的 Review sync 状态；否则 Site 页面可能继续显示旧 Banner。

建议：弹窗 Footer 按新设计统一为终态 `DONE`；失败项由 Site 页现有 Review sync 入口承接现场 BLE；全部成功后通过一次权威刷新清理 Review 状态。

### 6.13 UI 容量和文案

需要补齐：

- Gateway 很多时允许 Gateway 内容区域内部滚动；弹层向上增长时，顶部必须与 `safeArea.top` 保持足够间隔，不能覆盖系统安全区。该口径已确认。
- Gateway 名称过长时单行截断规则。
- Header 数量是目标数还是授权总数。
- `Syned` 是需求笔误；按 Figma 使用 `Synced`。该口径已确认。
- 当前弹窗标题 `Sync status` 改为 Figma 的 `Time zone sync status`。该口径已确认。
- Figma 的 `1 gateways failed` 语法不正确；国际化应采用单复数可表达的完整 Key，英文 1 使用 `1 gateway failed`，其他数量使用 `%d gateways failed`。

## 7. 推荐状态模型边界

后续确认后，建议把功能拆成三个独立单元：

### 7.1 Target Builder

输入为最终可信 Site timezone、远端权限快照、远端 Gateway offset 与本地 GatewayModel；输出为有稳定 MAC、显示名称、原始顺序和初始状态的目标列表。

职责：权限过滤、MAC 去重、offset 比较、名称映射。它不发网络请求，也不更新 UI。

### 7.2 Gateway Cloud Timezone Sync Coordinator

职责：

- 一次性提交目标 MAC 列表。
- 严格解析 requestId。
- 每 3 秒轮询并合并增量结果。
- 维护不可逆的 per-Gateway 状态：pushing、synced、failed。
- 处理直接失败、瞬时轮询失败、未知值、取消和 3 分钟超时。
- 通过主线程快照回调更新 UI。

Coordinator 不直接持有 UIKit View，不从可变 SiteData 反复推导目标。

### 7.3 Overlay Gateway Result View

职责：只根据不可变展示模型渲染 Gateway Header、行、失败统计、No gateways 和 Footer。

- 任一目标仍为 pushing：隐藏 Footer，禁止关闭。
- 所有目标终态：显示 `DONE`。
- 无授权 Gateway：显示 No gateways 和 `DONE`。
- 失败数大于零：显示失败统计卡。

## 8. 初步文件影响范围

确认需求后，预计涉及：

- `SunSmart/Common/Network/NetowrkReqeustApi.swift`：增加两个 POST API case、path、参数和诊断名。
- 新建 Site Gateway timezone API client/parser：隔离 requestId 与状态响应解析。
- 新建 Gateway 云端 timezone 同步 Coordinator：轮询、超时、取消和状态归并。
- `SiteEntryTimeZoneSyncResponseParser.swift` 或专用 Target Builder：保留可执行 Gateway identity，并与本地 display name 合并。
- `SiteEntryTimeZoneSyncPolicy.swift`：从摘要计数扩展为能构建本次目标列表，或把 Gateway 目标选择迁到独立纯策略。
- `SiteEntryTimeZoneSyncCoordinator.swift`：明确 Site 结果完成后何时允许启动 Gateway 同步。
- `SiteViewController.swift`：在 Site 导入完成、名称可解析后组装 Gateway 目标；管理 Overlay 生命周期和最终静默刷新。
- `SiteEntryTimeZoneSyncOverlay.swift`：替换 Gateway 摘要卡为动态列表/空状态/失败统计和新 Footer 状态。
- English、简体中文 Localizable.strings：补齐所有新文案与单复数。
- Assets 和 `SunSmart.xcodeproj`：只有现有 Loading/Success/Failure 资源无法匹配 Figma 时才新增，并同步核对四个品牌 target。
- Tests：API parser、Target Builder、Coordinator、Policy、Overlay contract、生命周期和多 target 工程归属。

## 9. 验证边界

后续实施至少需要：

- 纯策略测试：Owner、Editor/Visitor 混合 Space、重复 MAC、缺失 Gateway、非法 offset、已同步和待同步混合。
- API 解析测试：合法/非法 requestId、空 data、重复 MAC、未知状态、大小写、额外目标、终态回退。
- Coordinator 测试：3 秒节拍、180 秒超时、直接失败、轮询瞬时失败、取消、迟到响应、所有终态提前结束。
- UI contract：Pushing 时无 Footer，全部终态后有 `DONE`，No gateways、失败统计、长列表滚动、国际化文案。
- 回归当前 Site entry timezone policy、Site props persistence、Review sync 和 Overlay 导航锁。
- `plutil -lint` 检查 English 与简体中文 strings。
- `git diff --check`。
- 直接使用 `xcodebuild` 对 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 做 generic iPhoneOS Debug 无签名构建。
- 真服务器验收 requestId、状态值、重复请求、Editor 权限、Cloud snapshot 更新时间。
- 真机验收后台/前台、3 分钟超时、动态列表、不可关闭和 Bluetooth Review fallback。

自动测试和构建不能替代真实服务器、Gateway 在线链路、Cloud 状态落库与真机 UI 验收。

## 10. 第一项待确认

推荐保持当前弹窗触发范围不变，并在以下三种可见结果中都自动处理授权且需要同步的 Gateway：

- Site 已一致但 Gateway 不一致。
- Cloud timezone 更新到 App。
- App timezone 成功更新到 Cloud。

其中 App 更新 Cloud 的场景必须等 Site 更新成功后再下发 Gateway；Site 更新失败则不下发，并让目标 Gateway 以失败终态结束。

如果产品只希望在 App 上传 Site timezone 时启动 Gateway 同步，则必须同时决定如何处理当前另外两类可见弹窗，以及是否废弃“Site 已一致但 Gateway 待同步”的现有行为。

确认结果：采用推荐方案，保留全部三类现有可见弹窗场景，并以 Cloud Site timezone 已确认为 Gateway 下发前置条件。

## 11. 2026-08-15 已确认口径

- Site 更新失败时不得调用 Gateway 下发接口，本次待同步目标全部标记失败。
- Gateway 名称缺失时显示 MAC。
- 状态接口单次失败后继续按 3 秒节拍轮询，直到取得全部终态或达到 3 分钟总超时。
- 本期不持久化 requestId，App 重启后不恢复旧轮询。
- 成功状态文案使用 `Synced`。
- 弹窗标题改为 `Time zone sync status`。
- 长列表允许滚动；弹层顶部与 `safeArea.top` 保持足够间隔。

## 12. 下一项待确认：Gateway 列表与 Header 数量

推荐在弹窗中展示全部授权 Gateway：

- Header 数量等于去重后的授权 Gateway 总数。
- 已经与目标 timezone 一致的 Gateway 初始即显示 `Synced`。
- 需要同步的 Gateway 初始显示 `Pushing…`，并且只有这些 MAC 进入 `/sitespace/gateway/datetime/update`。
- 授权 Gateway 大于零但没有待同步目标时，不请求接口，全部行显示 `Synced` 并立即展示 `DONE`。
- 只有授权 Gateway 数量为零时才展示 `No gateways` 空状态。
- 失败统计只计算本次请求目标中最终失败的 Gateway。

这样可以让“有权限 Gateway 数量”“Header 数量”和“No gateways”语义保持一致，也完整覆盖“有授权 Gateway、但全部已经同步”的缺失分支。

确认结果：全部采用上述推荐口径。

## 13. 已确认架构方案

采用独立 Target Builder、API Client、Gateway Sync Coordinator 和 Overlay 展示模型的分层方案：

- 现有 Site timezone Policy/Coordinator 继续只负责 Site 仲裁、持久化与 Cloud 更新。
- Site 阶段成功后，由 Target Builder 生成全部授权 Gateway 行和实际待下发 MAC 子集。
- API Client 严格解析下发接口的 requestId 与状态接口结果。
- Gateway Sync Coordinator 独立负责下发、3 秒轮询、180 秒超时、状态合并和取消。
- Overlay 只根据展示模型渲染，不直接访问网络。
- SiteViewController 只负责串联 Site 阶段、Gateway 阶段、Overlay 生命周期和最终静默刷新。
- 全部 Gateway 终态后立即允许 `DONE`，静默 Site 刷新不阻塞弹窗关闭。

不采用把 Gateway 轮询并入现有 Site Coordinator，也不在 SiteViewController 中直接维护定时器和结果字典。

## 14. 已确认状态机与异常处理

- 每个授权 Gateway 保存标准化 MAC、接口发送用原始 MAC、显示名称、远端顺序和单项状态。
- 初始 offset 已一致的 Gateway 直接为 `Synced`；待同步项为 `Pushing…`；失败终态为 `Failed`。
- 单项终态不可逆，迟到或回退状态不得覆盖 `Synced` / `Failed`。
- 下发接口失败或 requestId 非法时，所有待同步项立即失败。
- 合法 requestId 使用正 Int64；从取得 requestId 起计算 180 秒，不持久化。
- 3 秒后首次轮询，之后保持 3 秒节拍；单次网络、业务或解析失败不改变状态，继续到总超时。
- MAC 匹配忽略大小写和首尾空白；额外 MAC 忽略。
- `Requested` 保持进行中，`Succeed` 转成功，`Failed` / `Expired` 转失败；`NIL`、null、缺失和其他值不更新。
- 同一轮同一 MAC 同时出现成功与失败终态时，本轮不更新并继续查询。
- 全部目标终态后立即停止；180 秒到达时剩余进行中项全部失败。
- 后台时间计入总超时，恢复后先检查 deadline；进程被杀或 Controller 销毁后不恢复旧任务。
- 使用 session token 隔离取消后的迟到响应。
- Site 更新失败时，已一致 Gateway 保持 `Synced`，只有待同步项变为 `Failed`，且不调用 Gateway 下发接口。

## 15. 已确认 UI、关闭行为与结果收敛

- 标题改为 `Time zone sync status`，Site 区域保留现有展示逻辑。
- Gateway Header 展示 `GATEWAYS` 和授权总数；行保持 Cloud 原始顺序。
- 长列表只滚动 Gateway 行，Header、失败统计和 `DONE` 保持可见；弹层最大高度不得越过 `safeArea.top + 16pt`。
- 名称单行截断，缺失时显示 MAC。
- 进行中、成功、失败分别展示 `Pushing…`、`Synced`、`Failed` 及对应图标；Loading 图标持续旋转。
- 失败数大于零时展示失败统计，并正确处理英文单复数。
- 无授权 Gateway 时展示 `No gateways` 和 `No gateways configured - no sync needed.`。
- 任一项仍在进行中时不展示 Footer，禁止返回、侧滑、背景点击或其他方式关闭。
- 全部终态或 No gateways 时只显示 `DONE`；删除当前 `LATER` / `REVIEW SYNC` Footer。
- `DONE` 关闭 Overlay、解除导航锁并继续原有 Site 入口导航。
- 全部成功时立即隐藏 Site 页 Review sync；存在失败时 Review sync 只保留失败数量并继续进入现有现场 Bluetooth 页面。
- 终态后静默刷新一次 `/get/siteprops`，但不阻塞 `DONE`。
- 本次成功 MAC 在当前 SiteViewController 生命周期内作为临时 offset override，避免服务器快照短暂延迟导致状态立即回退；Cloud 确认一致后清除。
- HTTP `Succeed` 不直接伪造或持久化 Mesh Node timestamp/timezone；现有现场 BLE Sync Gateways 页面不重构。
