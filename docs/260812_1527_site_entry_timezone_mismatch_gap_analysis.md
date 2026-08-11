# Site 进入时区差异提示需求缺口分析

## 1. 结论

当前需求方向明确，但尚不完整，不能在不补充产品语义的情况下形成唯一实现。

已明确的主路径是：进入 Site 页面后，`/sitespace/get/siteprops` 成功；当前用户具备 Owner 或 Editor 权限；服务器 Site 时区与本地缓存不同；展示检查中弹窗至少 1 秒；切换到结果弹窗；用户点击 `GOT IT` 后关闭。请求失败、无权限、时区相同均保持现状。

服务器与本地 timezone 的版本仲裁规则已确认：

1. 服务器 `updateTimestamp` 严格大于本地 `site.lastUpdate` 时，采用服务器 timezone，不再反向同步到服务器。
2. 服务器 `updateTimestamp` 小于或等于本地 `site.lastUpdate` 时，采用本地 timezone，并由 App 显式发送到服务器。

本地 timezone 胜出后的 UI 与请求状态也已确认：

- 上传成功显示 `Updated to server`。
- 上传失败显示 `Failed to update server`，并保留 timezone pending。
- 检查中视图最短展示 1 秒；请求超过 1 秒时继续等待真实结果，不提前切换。

本期范围已确认：只实现 Site timezone 版本仲裁、必要的服务器回写和结果弹窗。Gateway 行只展示 `/get/siteprops` 返回的只读同步概况；不实现 `Review sync` 后的 Gateway Time Zone Sync 页面、BLE/Mesh 连接、单个 Gateway 同步、失败重试或完成流程。Gateway 同步功能后续单独立项。

## 2. 当前源码事实

### 2.1 Site 页面进入与请求链路

- Sites 列表点击 Site 后立即创建并 push `SiteViewController`。
- `SiteViewController.viewDidLoad()` 在联网且 Site 已上传时调用 `loadSiteRequest()`。
- `loadSiteRequest()` 请求 `.siteInfo(siteId:)`，对应 `/sitespace/get/siteprops`。
- 请求成功后在异步 `Task` 中调用 `site.update(siteJsonData:)`，随后刷新页面、处理地址、自动进入 Space，并按既有规则触发云同步。
- 同一请求还可能由下拉刷新、网络恢复、网关关联变化等入口再次触发，因此“进入 Site 页面时”不能简单等同于每一次 `loadSiteRequest()`。

### 2.2 现有时区合并行为

- `SiteData.update(siteJsonData:)` 先读取远端 `updateTimestamp`。
- 仅当远端时间更新，或属于初始化导入时，才覆盖 Site name、imageId、timezone 等属性。
- 服务端 timezone 缺失、为空或无法解析时，不清空本地 timezone。
- 该方法执行后再比较 `site.timezone`，在远端版本胜出的情况下会得到“相同”，无法发现请求前的差异。
- Edit Site 已有独立的 `SitePropsEditPolicy.mergeRetrieve`，会保护 `pendingSitePropsMask` 对应的本地待同步意图；`/get/siteprops` 的整包导入路径没有复用这套字段级 pending 合并策略。

### 2.3 权限模型

- `SiteData.permission` 支持 `.owner`、`.editor`、`.visitor`。
- `/get/siteprops` 导入时会根据回复中的 `role` 更新 Site 级 permission。
- `SiteData.permissionOperates` 的 Site 编辑权限当前仅对 Owner 开放；Site 级 Editor 与“任一 Space 具有 Editor 权限”是不同概念。
- 因而需求中的“Owner 或 Editor 权限”需要明确是服务器本次返回的 Site role，还是包含 Space editor 的有效操作能力。

### 2.4 现有同步状态弹窗

- 工程已有 `SiteTimeZoneSyncStatusView`，用于 Edit Site 提交 timezone 后展示 saving、success、failure 三种状态。
- 该视图是底部 sheet，现有文案是 `Saving to server…`、`Saved successfully`、`Saved failed`、`No gateways` 和 `DONE`。
- 新 Figma 是居中卡片，检查中与最终结果的尺寸、圆角、文案、层级和状态含义均与现有视图不同。
- 若直接修改现有视图，会同时改变 Edit Site 保存后的既有流程；若新增独立视图，可避免回归，但会产生少量相似 UI。

## 3. Figma 核对结果

### 3.1 节点 399:11417

- 名称：`Overlay/CheckingSyncStatus`。
- 全屏 40% 黑色遮罩，居中卡片。
- 卡片包含 56pt loading 区域、标题 `Checking sync status…`、说明 `Comparing server time zone and gateway configuration.`。
- 设计注释要求从服务器获取 Site 时区并与 App 当前 Site 时区比较，同时获取 Site 中网关的时区同步标识。
- 没有关闭按钮，不应允许点击遮罩关闭。

### 3.2 节点 399:11389

- 名称：`Screen/SyncStatusNoGateways`。
- 全屏 40% 黑色遮罩，居中 343×296pt 卡片。
- 标题为 `Sync status`。
- Site 行展示 `Site time zone · UTC+08:00` 和 `Updated from server`。
- Gateway 行固定展示 `Gateway time zone` 和 `No gateways to sync`。
- 底部按钮为 `GOT IT`。
- 该节点仅能表达“无网关”结果，不能表达网关已同步、未同步、部分同步或状态未知。

### 3.3 文件内已存在的相关变体

通过 Figma 文件内只读节点检索，还确认了以下设计：

- `399:11424`，`Modal/SyncStatusGatewaysOutOfSync`：Site 行为 `Updated from server`，Gateway 行为 `3 gateways need time zone sync`，操作为 `Later` 与 `Review sync`。
- `399:11362`，`Modal/SyncStatusAlreadyInSync`：Site 行为 `Already in sync with server`，Gateway 行同样展示待同步数量，操作为 `Later` 与 `Review sync`。
- `399:12443`，`Screen/SyncStatusFollowUp`：后续再次检查时展示 `Updated from server` 和待同步网关数量。
- `399:10604`、`399:10732`、`399:10840`、`399:10969`、`399:11097`、`399:11229`：网关同步 Overview、全部在附近、失败重试、同步中、部分成功和完成页面。
- `399:12175`、`399:12182`：单个 Gateway 的同步提示与同步中弹窗。

因此“存在网关且需要同步”的 UI 有设计依据，但完整 Gateway Sync 属于后续阶段。本期结果弹窗不能保留一个没有实现目标页面的 `Review sync` 按钮。

## 4. 尚未完整的需求

### 4.1 已确认的数据真值与覆盖规则

比较必须在整包导入覆盖本地属性之前完成，并使用以下规则：

| 条件 | 采用值 | 后续动作 |
|---|---|---|
| 远端 timestamp > 本地 timestamp | 远端 timezone | 持久化到本地；不再向服务器发送 timezone |
| 远端 timestamp < 本地 timestamp | 本地 timezone | 保留本地值；App 显式发送 timezone 到服务器 |
| 远端 timestamp == 本地 timestamp，timezone 相同 | 任一方，结果相同 | 不提示、不发送 |
| 远端 timestamp == 本地 timestamp，timezone 不同 | 本地 timezone | 保留本地值；App 显式发送 timezone 到服务器 |

这意味着版本优先级高于既有 `pendingSitePropsMask`：只要远端 timestamp 严格更新，远端 timezone 就是最终真值；否则本地 timezone 是最终真值并需要服务器收敛。

实现时还需要把以下工程细节固定下来：

- timezone 内容比较使用规范化后的 `SiteTimeZoneValue`，避免空格或等价格式造成误判。
- 当本地值胜出并上传时，更新请求必须使用一个严格大于本地和远端的 `updateTimestamp`，避免“同版本不同值”继续存在。
- 本地值胜出时必须显式建立 timezone pending/update snapshot；不能只依赖 `needUploadCloud`，因为 timestamp 相等时现有计算可能认为无需上传。
- 远端值只有在数据库持久化成功后，才能显示 `Updated from server`。
- 本地 timezone 胜出但上传失败时，需要保留 timezone pending，供后续重试。

已确认只有有效的 IANA timezone identifier 才参与正常 timestamp 仲裁：

- 本地无效、远端有效：采用远端 timezone 并持久化到本地，不上传服务器。
- 远端无效、本地有效：采用本地 timezone，并显式上传服务器。
- 两端都无效：维持现状，不显示弹窗，也不上传服务器。

### 4.2 权限口径

已确认 Owner/Editor 权限以本次成功的 `/get/siteprops` 回复中当前 Site 的 `role` 为准，因为它与“请求成功后判断当前用户权限”的时序一致，也避免使用过期本地权限。

- 不使用请求前本地 `site.permission` 作为本次判断依据。
- 不使用任一 Space 的 Owner/Editor 权限作为 Site 级权限依据。
- 不将 Space Editor 等同于 Site Editor。

### 4.3 触发范围与去重

已确认限定为“每个 `SiteViewController` 实例仅检查一次”：

- 以该实例首次成功的进入请求为触发点。
- 同一实例内的下拉刷新、网络恢复、网关关联刷新和 App 从后台返回均不重复检查或弹窗。
- 检查中或最终结果尚未关闭时，后续响应不得替换、叠加或再次展示弹窗。
- 离开 Site 页面后重新进入并创建新的 `SiteViewController` 实例时，可以再次检查。

### 4.4 一秒与异步结果

已确认“一秒”是最短展示时间：

- 服务器结果在 1 秒内准备完成，等待满 1 秒后切换。
- 服务器结果超过 1 秒，继续显示 checking，直到真实结果完成或达到 30 秒总超时。
- 达到 30 秒超时后，停止 checking，取消底层任务或忽略迟到响应，并切换为 `Failed to update server` 与 `GOT IT`。
- 本地 timezone 等待上传时发生超时，必须保留 pending，供后续既有机制重试。
- 不允许用固定延迟伪造成功结果。

### 4.5 网关结果矩阵

至少需要定义：

- Site 无网关。
- 全部网关时区已同步。
- 全部未同步。
- 部分已同步。
- 网关 timezone 或同步标识缺失：按“没有待同步 Gateway”处理。
- 网关状态解析失败但 Site 数据可用：按“没有待同步 Gateway”处理。

Figma 已提供待同步数量与 Review Sync 相关页面，但本期不接入完整 Review Sync 流程。已确认：

- 有待同步网关时显示动态文案 `N gateways need time zone sync`。
- 存在 Gateway 且全部已同步时显示 `All gateways are in sync`。
- 存在 Gateway，但服务器未返回有效同步标识或字段无法解析时，不展示 unavailable，直接显示 `All gateways are in sync`。
- 两种结果底部都只保留 `GOT IT`。
- 这些信息仅为服务器只读状态，不触发或改变 Gateway 同步状态。
- Figma 和当前源码均未定义该同步标识的 JSON 字段名；实现需通过独立响应适配器承接正式后端契约，契约不可用时不得猜测字段或改用本地 Mesh 状态。

### 4.6 交互与生命周期

- `Checking sync status...` 状态不可点击遮罩关闭，不提供操作按钮。
- 最终状态不可点击遮罩关闭，只能通过 `GOT IT` 关闭。
- 页面已离开、控制器释放或 Site 已切换时，立即取消迟到响应和 1 秒计时、移除弹窗，不展示迟到结果。
- 从 checking 开始到结果弹窗关闭前，禁止导航栏返回和侧滑返回。
- checking 任务增加 30 秒总超时，避免请求或回调异常时永久阻塞页面。
- 与当前 `XWHUDManager` 加载状态的先后关系需要定义，避免 HUD 与新弹窗叠加。
- `SRAlertView.show()` 会主动关闭已有 `SRAlertView`；是否允许新流程打断其他业务弹窗需要避免。

### 4.7 国际化与适配

- 新文案需增加 English 与简体中文。
- `UTC+08:00` 必须来自远端解析后的实际 timezone，不能写死。
- 需定义长 IANA ID、中文、Dynamic Type、iPad 尺寸和横竖屏行为。
- Figma 使用 SF Pro Display Light/Regular；UIKit 应优先映射工程现有系统字体与颜色规范。

## 5. 方案比较与选择

### 方案 A：独立进入检查协调器与独立弹窗（推荐）

- 在 Site 页面进入请求成功时，先构造请求前本地快照与远端只读快照。
- 独立策略对象负责权限、时区差异、pending、timestamp 和网关结果判定。
- 既有 Site 导入仍负责完整数据更新；协调器根据最终持久化结果生成弹窗模型。
- 新建专用居中 overlay，明确 `checking` 与结果状态；不修改 Edit Site 现有底部同步弹窗。

优点：触发边界清晰、测试容易、不会改变现有 Edit Site 弹窗。缺点：新增一个专用 UI，和已有状态视图存在少量相似结构。

### 方案 B：扩展现有 `SiteTimeZoneSyncStatusView`

- 为现有视图增加使用场景和更多状态，兼容底部 sheet 与居中卡片。
- Site 进入与 Edit Site 提交共用一个状态视图类。

优点：复用状态名称和部分行组件。缺点：一个类同时承担两套布局和两条业务链，容易回归现有保存流程，状态组合也更复杂。

### 方案 C：直接在 `SiteViewController` 内判断并拼装弹窗

- 在 `loadSiteRequest()` 内保存本地 timezone、解析回复、延迟 1 秒并展示自定义 view。

优点：改动文件少。缺点：继续放大已有超长控制器，数据合并、权限、计时、生命周期和 UI 强耦合，难以覆盖并发与回归测试，不推荐。

已确认采用方案 A。方案 B、方案 C 不进入本期实现。

## 6. 已确认的开发设计

### 6.1 架构与主数据流

已确认按方案 A 的以下边界展开：

1. 为 `/get/siteprops` 回复建立最小只读快照解析，不复用会立即修改模型的导入动作做比较。
2. `SiteViewController` 只负责捕获请求前本地快照、转交本次响应以及连接展示入口，不承载仲裁和计时逻辑。
3. 独立协调器负责每实例一次触发、既有 HUD 与新弹窗的展示顺序、1 秒最短展示、30 秒超时、导航锁定和迟到响应隔离。
4. 纯策略输入请求前本地状态、远端只读状态、本次 Site `role`、timestamp、pending 和 Gateway 状态，输出“不处理”“采用远端”或“采用本地并上传”。
5. 持久化和上传沿用既有 Site 能力；采用本地时显式建立 timezone pending，并使用严格更新的 timestamp。
6. 专用居中 overlay 独立于 `SRAlertView` 和 `SiteTimeZoneSyncStatusView`，只负责渲染 checking 与最终结果。

主流程为：请求失败、无有效权限或 timezone 相同时沿用现状；符合条件时在既有 HUD 结束后展示 checking 并锁定返回；按策略完成远端落库或本地上传；操作完成且已满 1 秒后展示结果，30 秒超时则展示失败；点击 `GOT IT` 后关闭并恢复返回能力，迟到响应不再改变结果。

后续开发还需增加 English、简体中文及四品牌 target 资源检查；先写策略和入口契约失败测试，再实现；最后运行 Site 聚焦测试、`git diff --check` 及四个品牌 generic iPhoneOS Debug 构建。

### 6.2 状态输出与错误处理

已确认按以下状态映射：

- 采用远端 timezone 且本地持久化成功：显示 `Updated from server`，不上传服务器。
- 采用本地 timezone 且上传成功：显示 `Updated to server`，清除对应 pending。
- 本地持久化失败、上传失败或 30 秒超时：进入统一失败态，显示 `Failed to update server`；尚未上传成功的本地 timezone 保留 pending。
- Gateway 状态独立生成只读结果行：无 Gateway 显示 `No gateways to sync`；有待同步显示 `N gateways need time zone sync`；全部同步或状态缺失、无法解析时显示 `All gateways are in sync`。
- `/get/siteprops` 失败、无 Owner/Editor 权限、timezone 相同或两端 timezone 都无效：不显示新弹窗，维持现状。
- 进入最终状态后，迟到响应不得覆盖结果；当前页面实例不再重新检查。

### 6.3 UI、弹窗互斥与生命周期

已确认按以下边界实现：

- 使用专用全屏遮罩和 Figma 居中卡片，不复用 `SRAlertView`。
- 先等待现有 HUD 或业务弹窗结束，再展示 `Checking sync status...`；1 秒最短展示和 30 秒超时均从 checking 实际显示时开始计算。
- checking 与结果态均不可点击遮罩关闭；从 checking 显示到结果弹窗关闭期间，禁止导航栏返回和侧滑返回。
- 不调用 `SRAlertView.show()`，不主动关闭其他业务弹窗。
- 最终结果仅保留 `GOT IT`；点击后移除遮罩、取消计时任务，并完整恢复进入前的导航状态。
- 控制器因外部流程释放或 Site 被切换时，立即清理弹窗与任务，不展示迟到结果。

### 6.4 测试、国际化与验收边界

已确认：

- 自动测试覆盖纯策略、每实例一次协调、1/30 秒计时、迟到响应、导航恢复、远端落库、本地上传和 pending。
- 新增 English 和简体中文本地化，并同步检查四品牌 target 的源码、资源和本地化 membership。
- 验证包含 Site 聚焦测试、`git diff --check` 和四品牌 generic iPhoneOS Debug 构建。
- 真机 UI、真实服务器和真实 Gateway 数据保留为人工验收；不把静态测试或构建成功表述为端到端通过。

明确排除：Gateway 时区 SET、BLE/Mesh 连接、附近 Gateway 扫描、Review Sync 列表、单个 Gateway 重试，以及 Gateway 同步完成度变更。

## 7. 建议验收矩阵

| 请求 | 权限 | 本地/远端 timezone | 本地 pending | 网关 | 预期 |
|---|---|---|---|---|---|
| 失败 | 任意 | 任意 | 任意 | 任意 | 完全维持现状 |
| 成功 | Visitor | 不同 | 无 | 任意 | 不提示 |
| 成功 | Owner/Editor | 相同 | 无 | 任意 | 不提示 |
| 成功 | Owner/Editor | 不同且远端 timestamp 更新 | 任意 | 无网关 | 采用远端、落库，不反向上传；checking 至少 1 秒，再展示 no gateways 结果 |
| 成功 | Owner/Editor | 不同且远端 timestamp 不更新 | 任意 | 无网关 | 采用本地并显式上传；成功显示 Updated to server，失败显示 Failed to update server 并保留 pending |
| 成功 | Owner/Editor | 不同 | 任意 | 有待同步网关 | 显示 `N gateways need time zone sync`；仅保留 GOT IT，不进入真实 Gateway Sync |
| 成功 | Owner/Editor | 不同 | 任意 | Gateway 全部已同步 | 显示 `All gateways are in sync`；仅保留 GOT IT |
| 成功 | Owner/Editor | 不同 | 任意 | Gateway 同步标识缺失或无法解析 | 显示 `All gateways are in sync`；不展示 unavailable，不阻塞 Site timezone 流程 |
| 成功 | Owner/Editor | 本地无效、远端有效 | 任意 | 任意 | 采用远端并持久化到本地，不上传服务器 |
| 成功 | Owner/Editor | 远端无效、本地有效 | 任意 | 任意 | 采用本地并显式上传服务器 |
| 成功 | Owner/Editor | 本地与远端均无效 | 任意 | 任意 | 维持现状，不提示、不上传 |
| 成功后 checking 超过 30 秒 | Owner/Editor | 需要处理 | 本地胜出时保留 | 任意 | 停止 checking，忽略迟到响应，显示 `Failed to update server` 与 GOT IT |
| 成功后页面退出 | Owner/Editor | 不同 | 无 | 任意 | 不展示迟到弹窗 |

## 8. 设计结论

需求语义、方案 A、架构、状态处理、UI 生命周期及验证边界均已逐项确认。正式设计规格见：`docs/260812_1740_site_entry_timezone_sync_design.md`。
