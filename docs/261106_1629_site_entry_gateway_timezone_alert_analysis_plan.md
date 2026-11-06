# Site 进入时网关时区误报分析与修复方案

> 状态：推荐方案已获用户确认并实施；相关回归及自行复核已完成，SunSmart / Debug / generic iOS 构建通过。网关总脚本存在已确认的既有布局断言失败；真实 API/UIKit/Mesh 验收待用户完成。
> 工作树：`feat-daylight-saving-261024`；分支：`feat/daylight-saving-261024`；HEAD：`3359fea7f63e58d5991121a52181c55cd20437d9`。开始时工作区干净。
> 执行约束：已按 `superpowers:executing-plans` 在本 session 内实施，不使用子代理、不自动提交。

**Goal：** 只有当前证据确实表明网关需要同步时，才显示待同步计数及 `REVIEW SYNC`；弹窗、Site 提示、网关名称颜色和同步列表使用一致的判断。

**Architecture：** 复用 `SiteTimeZoneService/Store` 的缓存、请求合并和通知；把 Site 属性仲裁与网关当前状态计算分开。准备结束、结果展示和点击分别校验当前状态，保留既有确认值与 dirty 数据保护。

**Tech Stack：** Swift、UIKit、Foundation 行为测试、现有 shell 检查。

**Spec：** 用户已确认“准备有效 offset + 当前统一评估 + 明确路由结果”；本文第 5–7 节为实施契约，结果见第 9 节。

## 1. 结论与证据边界

已确认修复前代码存在一条完整缺陷链：**当前时区 offset 尚未加载 → 被判为网关 pending → 缓存在等待期间就绪 → 弹窗仍展示旧计数 → 点击按新 offset 得到空列表并直接返回。** 这能解释同一 Site 首次进入偶发、重进又正常，以及实际无需同步却收到提示的现象。

受控复现执行了真实磁盘 JSON 缓存读写、异步 Store 发布、响应解析器、Entry Policy、Entry Coordinator 和同步列表 descriptor policy。结果为：弹窗结果 `pending(1)`，当前同步目标数 `0`，Site banner 为 hidden；暖缓存重新进入是 `noAction`。整个复现没有网关通信、Site 保存或上传，也没有 DST HTTP 请求。

**对这一次现场事件的判断：高度吻合上述竞态，但不能仅凭日志断言已唯一定位。** 日志没有打印当时的 IANA、目标 offset、缓存就绪时间、entry decision 和路由 return 原因；HTTP body 也已截断。受控复现中的 `America/New_York` 是合成输入，不能把日志中的 Washington D.C. 当作实际 timezone 字段。

分析阶段只新增本文档；诊断夹具在 `/tmp/sunsmart-entry-sync-analysis.yaLRNW/EntrySyncRaceProbe.swift`，没有修改 App、SDK、测试工程或依赖。

## 2. 现场日志说明了什么

输入文件：`/Users/maginawin/Desktop/sync gateway alert logs.txt`。仅引用必要字段，不复制原始响应中的凭据、密钥或用户标识。

| 日志位置 | 已证实事实 | 不能由此推出的结论 |
| --- | --- | --- |
| 4–13、64–75 | 进入 Site 后请求 `siteInfo`，HTTP/business code 均为 200 | 不代表网关已经同步或当前 offset 已准备好 |
| 74 | 响应含 1 个网关，`timezoneOffset=44`；当前 App 解码为 `(44-64)×15=-300` 分钟，即 UTC-05:00 | Site 当前目标 offset 未出现在未截断部分；无法单凭这一字段证明一致或不一致 |
| 74 | `tzStatus=NIL`、`utcOffset=null` 等字段出现 | Entry Parser 实际比较 `timezoneOffset`，不检查这些任务状态字段；它们不是弹窗的直接来源 |
| 126–170 | Site 导入完成，内部 Space 导入约 0.12 秒，Site 导入约 0.195 秒 | 这是云数据导入，并非向网关下发时区命令 |
| 171–173 | 进入 `SiteViewController`，点击落到 `SiteEntryTimeZoneSyncOverlay.reviewSyncDidTap` | 日志缺少其后具体路由判定，无法直接知道命中了哪条 guard |
| 14–125 | `GatewayItemView` 宽度为零时发生布局约束冲突 | 没有证据把约束告警归为此次弹窗误报/路由退出原因；按钮事件确实已到达 |

所给片段没有网关时区更新或 TimeSet/TimeGet 的通信证据，也没有 DST 请求记录。磁盘缓存恢复就能触发本次复现，因此“没有 DST HTTP 日志”不排除缓存竞态。日志结尾只有点击事件，没有导航完成日志；“点击后只关闭”的运行结果来自用户观察。

## 3. 当前完整流程

### 3.1 何时检查，何时弹窗

1. `SiteViewController.viewDidLoad` 在手机有网络且 Site 已上传时调用 `loadSiteRequest → performSiteLoad(.interactive)`。
2. `/siteprops` 返回后，先取得本地 Site 属性快照并解析远端快照；**此时尚未等待时区服务准备完成**。
3. `entrySyncCoordinator.prepare` 在每个控制器实例中只消费一次响应。它先生成包含网关计数的 decision，随后才执行异步 `site.update(...)` 导入。
4. 导入后刷新列表和 banner，再把之前的 decision 放入 `PendingEntrySyncPresentation`。页面初次出现完成且有 window 后展示 `Checking sync status…`。
5. `entrySyncCoordinator.run` 执行 Site 属性仲裁，至少展示 1 秒 checking；整体运行另有 30 秒超时。返回的网关摘要仍是 decision 内的旧摘要。
6. Controller 将返回结果交给 `entrySyncOverlay.showResult`。只有 Site 操作未失败且摘要为 pending，才显示 `LATER / REVIEW SYNC`；其他结果显示 `GOT IT`。

| 条件 | Entry decision / 展示 |
| --- | --- |
| Owner/有效 Editor；本地与远端 IANA 相同；网关摘要有 pending | `showGatewayStatus`；即使 Site 本身无需保存，也显示 checking 和 Sync status |
| 本地无有效 timezone，远端有 | `useRemote`，保存本地 Site 后展示结果 |
| 本地有 timezone，远端没有；或两者不同且远端时间戳不比本地新 | `useLocal`，尝试上传本地 Site timezone 后展示结果 |
| 两者不同且远端时间戳更大 | `useRemote`，采用服务器 Site timezone 后展示结果 |
| 两边都无 timezone；或 IANA 相同且无待同步网关 | `noAction`，不显示 Entry 弹窗 |
| Visitor 范围 | 采用服务器 Site 属性的静默路径；不显示此网关检查弹窗 |
| 首次成功响应的 data/快照解析失败 | 消费首次机会，不显示本次 Entry 弹窗；同一控制器后续刷新通常只更新页面状态 |
| 请求失败 | 不显示本次 Entry 弹窗；failure 分支本身不消费首次机会，后续成功请求仍可能触发检查 |
| Site 仅本地未上传，或进入时无网络 | 不发起这次在线 Entry 检查 |

角色范围并非只读 Site 的 role：Owner 覆盖远端网关列表；其他角色若持有 Editor Space，只覆盖这些 Space 关联的网关；没有 Editor Space 才按 Visitor 处理。未关联 Space 的网关仍属于 Owner 检查范围。离线网关也不会因离线自动从比较范围移除。

`prepare` 的“一次”是控制器实例级，并非 Site 永久标记；退回列表再重新打开会创建新实例。静默网关回收刷新也会经过 `prepare`，但不执行弹窗展示；若它先消费响应，会影响此实例后续是否弹窗。此路径属于一般行为边界，现场无证据表明发生。

### 3.2 pending 如何得出

`SiteEntryTimeZoneSyncPolicy.gatewaySummary` 调用共享 TargetBuilder：

- 目标：Site IANA 对应的**当前可用服务器时区快照**的 offset。
- 网关值优先级：本会话已确认 offset → 本地待上传 offset → 远端 `timezoneOffset`。
- 网关 offset 缺失或重复记录相互矛盾时，按未知值处理；在目标已知时仍会要求复核。
- **当前 target 为 nil 也被设置为 `requiresSync=true`，因此所有范围内网关都被计入 pending。**

`SiteTimeZoneValue.offsetMinutes` 在无缓存、缓存尚未恢复、跨 DST 切换点或时钟回拨导致快照不可用时返回 nil。目录中的 offset 只用于显示；即使界面显示了 UTC 文案，也不证明比较所需的有效 offset 已经就绪。

Entry 弹窗只是 App 根据快照比较出来的状态，不是从网关“待执行任务队列”读到的任务。当前进入流程不会自动下发网关时区，也不自动调用云端网关时间更新 API。真正的网关同步属于进入 `Sync gateways` 后的流程；它也与网关详情页手动校时入口不同。

### 3.3 点击 REVIEW SYNC 后为何可能只有关闭

当前顺序为：`handleEntrySyncReview → finishEntrySyncOverlay → showSyncGatewaysPage`。先关闭弹窗、解除导航锁，再重算同步页面上下文。

| 当前路由条件 | 实际结果 | 评价 |
| --- | --- | --- |
| 有合法目标且仍有待同步 descriptors | push `SyncGatewaysViewController` | 正常 |
| `latestTimeZoneRemoteSnapshot == nil` | 隐藏 review 状态后 return | 缺少当前快照，不等于已同步；当前无用户反馈 |
| projection 为 hidden | return | 包括 Visitor、缺少本地/远端 timezone、本地与远端 IANA 不同且无有效显式 context、显式 context 与本地 IANA 不符 |
| Site 主 Mesh 网络既未在 manager 中就绪、又不能从存储加载 | return | 数据不可用，不等于无需同步；当前无用户反馈 |
| 最新 targets 为空 | 隐藏 banner/context 后 return | 当前确实无任务时不进入空列表合理，但先前 pending 弹窗已过期 |
| 没有 navigationController | 可选 push 不执行 | 常规 Site 页面应有导航容器；未见现场证据 |

**不是“缺一个 GatewayModel/Node 就必然空列表”**：descriptor policy 会保留权限范围内的待同步行，只将 `isSyncable=false`。完全缺失主 Mesh 网络才会在更外层直接 return。

`finishEntrySyncOverlay` 还会调用 `continuePostImportNavigationIfNeeded`，可能执行新增 Space、申请地址、自动进入指定 Space，再尝试 push 同步页。此处存在导航意图竞争，修复点击路径时应一起约束；现场来自普通 Site 点击，没有证据说明本次是该竞争。

## 4. 缺陷链与随机感的来源

### 4.1 已复现的主要缺陷

| 顺序 | 状态 |
| --- | --- |
| T0 | 本地/服务器 IANA 相同；网关已是目标 offset，但 App 的时区内存快照未准备好 |
| T1 | Entry prepare 读到 target=nil，共享 builder 产生 `pending(1)`，摘要存入 decision |
| T2 | 磁盘缓存或 DST 响应就绪，当前 target 与网关相同 |
| T3 | 观察者更新 banner；若弹窗还未挂载，或正处于 `.checking`，弹窗刷新直接返回 |
| T4 | 旧 decision 经过 checking 最短显示期，Controller 仍 `showResult(entryResult)`，显示 1 个待同步 |
| T5 | 点击后重算：目标已知且相同，descriptor 数为 0；弹窗先关闭，路由直接结束 |

三个缺陷互相配合：

1. **未知值被误称为确定的不一致。** `SiteGatewayCloudTimeZoneTarget.swift:158` 把 nil target 当成 requiresSync。
2. **异步通知没有在结果交付时补算。** `SiteViewController.swift:964–975` 在未挂载/checking 时跳过 overlay 更新；`829` 直接展示旧结果。
3. **展示与动作没有共同的最终状态校验。** `1065–1100` 先关闭再计算，结果已改变或数据不可用时均静默退出。

相关改变可追溯到提交 `030a6d41`（timezone new API and format）：目标 offset 变为可空、nil 计为 requiresSync，并添加了 checking 时跳过的观察刷新。这里是代码演变证据，不意味着该提交的所有时区行为有问题。

### 4.2 为什么同一 Site 有时正常

- **时区缓存先就绪**：第一次比较就是一致，直接 `noAction`。
- **缓存在 decision 之后、弹窗结果之前就绪**：最容易出现本次“旧弹窗 + 空列表”。导入、页面转场、至少 1 秒 checking 都扩大了这个窗口。
- **缓存在结果展示之后就绪**：观察者可能把弹窗更新为不需要同步并换成 `GOT IT`；用户看到的表现又不同。
- **缓存一直失败或不可用**：当前实现仍可能显示 pending，但点击会保留候选行；这是“未知误报”的另一种表现，不一定只关闭。
- **同一进程暖缓存重进**：无需再等磁盘/HTTP，通常不出现误报。
- **数据真的变化**：服务器、dirty/confirmed、本地权限或 Site IANA 变化也能让前后判断不同。现有日志未证明这些分支，本次不扩大为服务器/固件问题。

同类边界：Entry 的 local context 只捕获符合目标的 dirty 覆盖；列表 builder 从当前模型读取所有待上传 node offset，且路由另使用 confirmed 层。结果展示必须统一当前有效输入，不能只修某个按钮或把固定等待时间调长。

## 5. 复现步骤与本次验证

### 5.1 用户可执行的概率复现

1. 选择一个已有网关、Site 和网关时区已一致的 Site。用 Owner，或有对应 Editor Space 权限的账号。
2. 结束 App 后重新启动，立即进入该 Site；尽量不要先进入相同 IANA 的其他页面，使当前进程没有提前准备该时区。
3. 若出现 checking → 提示网关需要同步，留意 Site 顶部是否已无 review 提示、网关名称是否已恢复正常。
4. 点击 `REVIEW SYNC`，观察是否仅关闭；退回 Site 列表再进入同一个 Site作对照。

这是时序相关步骤，**不保证每次出现**；仅在 siteInfo 的比较先于 offset 准备、offset 又赶在最终展示前可用时命中核心窗口。不建议通过修改网关时区制造“真实任务”，那会改变复现前提。

### 5.2 已执行的确定性离线复现

夹具：`/tmp/sunsmart-entry-sync-analysis.yaLRNW/EntrySyncRaceProbe.swift`。仅使用合成 Site/Gateway ID，无真实密钥。

1. 用生产 `SiteTimeZoneCache` 序列化并保存当前 UTC-05:00 快照。
2. 新建生产 Store，以信号量暂缓其实际磁盘读取；provider 此时读不到内存 offset。
3. 用生产 parser 解析 `timezoneOffset=44`，用生产 Coordinator prepare 得到 `showGatewayStatus(pending=1)`。
4. 开始真实 Coordinator 异步 run，以注入 sleeper 控制最短显示期；在该期间释放磁盘读取并收到真实 Store 通知。
5. 释放最短显示期；检查真实 Coordinator 结果仍 pending，重新调用生产 target/descriptor policy 已无候选。
6. 用暖缓存新建 Coordinator 检查为 noAction；另以网关 UTC-04:00 对照，确认真实差异仍 pending。

输出摘要：

```text
COLD: offset=nil, decision=showGatewayStatus(pending=1)
CACHE DURING CHECKING: offset=-300, notifications=1, HTTP=0
RESULT: gateway=pending(1), fresh route targets=0, banner=hidden, Site writes=0, uploads=0
WARM REENTRY: decision=noAction
REAL MISMATCH CONTROL: gateway=-240, target=-300, pending=1
UNAVAILABLE CONTROL: absent offset is still classified pending
```

夹具真实经过 JSON 序列化、磁盘恢复和异步 Coordinator 边界。**UIKit overlay/导航、Site/SDK 数据库导入、`SyncGatewaysContextBuilder` 的 SDK 部分不在夹具中执行**；checking 时跳过通知及 route guard 是当前源码证据，完整 UI 现象仍需真机确认。

| 本轮检查 | 结果与边界 |
| --- | --- |
| 上述 Swift 行为探针 | 通过“旧摘要/新目标不一致”的缺陷复现断言；并不表示 bug 已修复 |
| `bash scripts/check_site_props.sh` | 通过；含 Site 属性、生产导入提取夹具、Entry Policy/Coordinator。导入夹具有一条未使用 uuid 的既有警告 |
| `bash scripts/check_site_dst.sh` | 通过；Value、Snapshot、Store、DST Presentation |
| App 构建、真实 API、UIKit、BLE/网关 | 未执行；本轮无生产修改，不构建或操作真机 |

既有 Entry 测试安装立即可用的 `SiteDSTFixtures`；Store 的异步缓存测试与 Entry 的最短显示期测试各自运行，尚未组合覆盖此次交错。

## 6. 已确认的修复行为与取舍

### 6.1 方案比较

| 方案 | 收益与不足 |
| --- | --- |
| 只在 showResult 前重算一次 | 能修复一部分旧计数，但 offset 仍未知时继续误报，点击前变化与失败反馈仍缺失 |
| **准备有效 offset + 当前统一评估 + 明确路由结果（推荐）** | 同时覆盖未知误报、checking 期间失效、点击时状态变化；复用现有服务，不新增缓存/持久化 |
| 强制跳转或增加固定延时 | 空页面/重复同步或换一种概率出现；没有解决未知和不一致的区别，不采用 |

### 6.2 已确认契约

- Site 属性仲裁保留原权限、时间戳、pending 保存和失败恢复规则；不能因网关评估刷新重复上传 Site。
- 有合法 IANA 但当前 offset 暂不可用时，进入“等待/无法检查”状态，不能说“全部已同步”，也不能说“所有网关需要同步”。
- 复用 `SiteTimeZoneService.prepare` 的缓存恢复、请求合并及现有请求超时；只在目标需要时准备，不增加固定延时或无界重试。
- IANA 已一致且只需检查网关时，准备成功后如无待同步目标，不展示 Sync status 结果弹窗；已有 checking 可正常结束。
- 若真正发生 Site 属性同步，保留其成功/失败结果；网关状态用完成时的当前值独立呈现。准备失败时显示“无法检查/需要刷新”，只允许关闭或显式重试，不出现带虚假计数的 Review。具体文案实施时按项目国际化规则确定。
- 结果展示前、DST 发布后以及 Review 点击时，复用同一入口评估：Site/IANA、权限范围、有效 offset、当前 remote、dirty/confirmed、显式失败 context。
- 单次评估固定一个采样时刻/offset，避免在同一轮中多次读取动态 getter 得到不同依据；到动作边界仍重新校验，不能用旧 snapshot 强行同步。
- Review 点击得到“确实为空”时收敛 banner/名称颜色，给予“当前无需同步”的轻量反馈；数据未准备好/主网络不可用/权限变化使用明确反馈，不能都表现为关闭。
- Review 导航不先执行普通关闭的自动进入 Space 逻辑；`LATER/GOT IT` 保留其原有后续导航职责。
- 保留“目标已知但网关 offset 缺失/冲突”需要复核的既有语义，不把所有 nil 都当作无需同步；保留真实失败任务和旧数据兼容。

不能直接全局把 TargetBuilder 的 `target=nil` 改成 `requiresSync=false`：编辑 Site 的云端同步会用此 builder 生成失败状态，`SiteGatewayCloudTimeZoneSessionCoordinator` 也用 nil 阻止下发并保留失败。应在 Entry/review 的评估层显式表示未就绪，保护共享调用方；若调整共享返回类型，须同步覆盖这些调用方而不改其业务契约。

### 6.3 范围和维护成本

- 无数据库、export JSON、字段默认值、迁移或持久化语义变更；不新增磁盘缓存。
- 仅新增必要的内存评估状态和路由结果，复用既有 session token、服务和 TargetBuilder。当前机制的不足是一个 pending Bool 同时承担了“不一致”和“目标未知”，而结果 snapshot 跨越了异步阶段。
- 不需要 SDK、固件、服务器或协议配套；不修改 Mesh 命令、ACK/UNACK 或重试次数。现场依然需要真实 API/UI 验收。
- 共享 Site 页面覆盖各品牌，含工程实际存在的 HSmart；本方案无新增品牌特定资源/配置。实施前核对最新 workspace/SDK 映射，代表 scheme 为 SunSmart；若新增资源/target 配置导致跨品牌编译风险，再补对应品牌构建。

## 7. 实施任务与验收

### Task 1：先固化跨边界行为复现

**文件：** `Tests/Site/SiteEntryTimeZoneSyncCoordinatorTests.swift`、`SiteEntryTimeZoneSyncPolicyTests.swift`、必要的组合测试文件；接入 `scripts/check_site_props.sh` 或 `check_site_dst.sh`。

- [x] 将本轮真实缓存恢复探针整理为正式行为用例，期望冷缓存一致时不返回确定 pending；确认当前代码先失败。
- [x] 覆盖缓存通知在 prepare 前、prepare 后/showChecking 前、checking 中、结果后四个位置；暖缓存对照保持 noAction。
- [x] 覆盖目标未知且请求失败、快照过期/跨切换点、网关真实不同、网关值缺失/重复冲突；检查未知不得映射成已同步。

### Task 2：拆开 Site 仲裁与当前网关评估

**文件：** `SiteEntryTimeZoneSyncPolicy.swift`、`SiteEntryTimeZoneSyncCoordinator.swift`、`SiteViewController.swift`；必要时调整 `SiteGatewayCloudTimeZoneLocalContext.swift` 复用输入提取。

**接口约束：** 建议在现有 Entry Policy 中增加 `SiteEntryGatewayEvaluation`（待准备/不可用/已评估摘要及 IDs），以显式采样 offset 作为评估输入；它是内存类型。Coordinator 的 Site 仲裁只执行一次，结果交付阶段取得最新 evaluation，不重新执行 `useLocal/useRemote`。具体签名在实施时保持现有工程风格。

- [x] 在 Entry 初次决策中分离有效 offset 准备与确定 pending，复用现有 Service；等待期间允许已有取消/离开机制生效。
- [x] 最终展示、banner 和名称颜色通过同一评估入口取得目标 IDs；保留 confirmed 优先级和 dirty 恢复，不用过期导入前摘要覆盖新值。
- [x] 接入现有 token，校验 Site/IANA/页面仍有效；退出/切换 Site/取消后的回调不能弹窗或覆盖新会话。
- [x] 在 unknown 准备失败后，显式重试或后续有效通知仍可重新评估；不得被 `hasConsumedEntryResponse` 永久吞掉，也不得重复 Site 写入。
- [x] 跑 Task 1 行为用例和 `bash scripts/check_site_props.sh`、`bash scripts/check_site_dst.sh`。

### Task 3：修复 Review 动作与反馈

**文件：** `SiteViewController.swift`、`SiteEntryTimeZoneSyncOverlay.swift`、`Tests/Site/SiteEntryTimeZoneSyncContractTests.swift`、`SiteTimeZoneReviewSyncContractTests.swift`；需要新文案时同步 `en.lproj/Localizable.strings` 和 `zh-Hans.lproj/Localizable.strings`。

**接口约束：** 路由准备需区分 ready(context)、noPending 和 unavailable(reason)，不能再用无返回值的 guard 把所有原因吞掉。明确“关闭 overlay”和“继续默认导航”两个调用意图；只有存在合法目标才 push。

- [x] 结果展示前复核当前摘要，checking 中收到的通知必须在终态体现。
- [x] Review 点击先准备动作结果，再按结果关闭/反馈/push；不触发普通关闭的自动进入 Space 分支。
- [x] 覆盖 Reviewer 点击前 pending→0、权限变化、主 Mesh 网络缺失、navigation 不可用、真正 pending→同步页；模型/Node 缺失仍保留不可同步行。
- [x] 同范围检查 header 的 Review、Overview/Favorites 和网关颜色，防止入口间状态不一致。
- [x] 更新既有源码 contract，只把它作为连线辅助；不得用字符串断言代替上面的行为时序用例。

### Task 4：必要验证与人工验收

- [x] 跑前述两组脚本，以及涉及共享网关入口时的 `bash scripts/check_site_sync_gateways.sh`；若出现既有失败，记录实际失败与本次修改关系，不扩大清理范围。
- [x] 核对 workspace、scheme 和 SDK realpath，一轮修改完成后 SunSmart / Debug / generic iOS 构建一次，禁用签名；不使用 Simulator、不自动安装真机。
- [ ] 用户真机：冷启动/暖重进的一致 Site 均无误报；真实改时区后 pending 数正确，Review 打开同步页；准备失败有明确状态；弹窗期间数据变为一致时不留下失效 Review。
- [ ] 对 Owner、Editor 子集、Visitor、无网关、未绑定 Space 的网关，以及取消/退出重进各做对应最小检查。真正失败的网关重试不能被新评估吞掉。

**补充 DEBUG 诊断（实施时）：** 只在关键状态转移记录 session、脱敏 Site/Gateway ID、IANA、准备状态、有效 offset、decision/summary、pending 数、路由结果；置于 `#if DEBUG`，不输出密钥或完整响应，不逐秒刷日志。这样下次现场日志可直接区分 unknown 误报、数据已收敛和网络数据不可用。

## 8. 当前交接

- 用户已授权推荐方案；App 实施及对应测试完成，未 commit/push。
- 本地 workspace：`SunSmartLocal.xcworkspace`；SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；SDK HEAD：`2809c540be3b965a6a847ee4586ac46faf2ca2b5`，实施前工作区干净。本任务只读 SDK。
- App HEAD 保持 `3359fea7f63e58d5991121a52181c55cd20437d9`；本任务改动均未提交。没有数据库/export JSON、依赖、工程配置变更。
- 按用户不使用子代理的要求，最终复核由本任务自行完成；检查了权限范围、未知 offset、当前/显式目标、dirty/confirmed 优先级、取消、导入后刷新和路由意图。
- 不扩展修复既有 Header 布局断言；其基线失败证据见下节。
- 后续继续更新本文，不另建重复计划或总结。

## 9. 实施记录与验证结果

### 9.1 已落地行为

1. `SiteEntryGatewayEvaluation` 在现有 Policy 文件中集中产生摘要及 pending IDs。无有效 offset 时返回 unavailable；真实不一致、缺失/冲突的网关 offset 仍要求复核。一次评估固定 offset，列表接收同一份 evaluation。
2. Entry Coordinator 复用注入的 `SiteTimeZoneService.prepare`，完成 Site 仲裁、时区准备及最短展示期后再计算结果。已一致的纯网关检查不展示结果弹窗；未知不显示虚假计数或 Review。
3. 页面观察者更新 Overlay、banner；名称颜色与同步列表取同一评估。导入前仅用于恢复的 dirty 数据与当前用于比较的 dirty 数据分别保留，confirmed 仍具有最高优先级。
4. Review 先决定 ready / noPending / unavailable，再关闭或跳转。无需同步、上下文变化、数据不可用各有反馈；该路径不再触发默认的自动进入 Space。Got it/Later 保留原后续导航。
5. Site 上传成功后保留明确目标；即使旧远端 Site timezone 缺失，合法显式目标仍可进入同步页。重试候选中已经与有效 offset 一致的目标会被移除，真实差异/失败候选继续保留。
6. 静默 Site 刷新不抢占交互进入检查机会；首次检查准备失败后，用户刷新 Site 仍会重试准备。准备取消/页面退出后的晚到结果不再发布旧弹窗。
7. 新增三个 en/zh-Hans 文案；新增关键结果和路由的 DEBUG 日志，使用截短 Site/session ID，不打印凭据或完整响应。

### 9.2 验证

| 检查 | 结果 |
| --- | --- |
| `SiteEntryGatewayEvaluationTests` | 先观察到 unknown→pending 的失败，再转绿；真实磁盘缓存恢复、Checking 中通知、prepare 后/展示前更新、暖缓存、准备失败/重试、取消晚到、DST 失效、Owner/Editor/Visitor、缺字段/重复冲突、dirty/confirmed 和路由原因均通过 |
| `SiteEntryGatewayHostTests` | 执行生产 Controller/Overlay 方法的提取夹具；晚到刷新移除旧 Review、上传完成后旧远端快照、各路由反馈、Review 不触发默认导航、普通关闭继续导航均通过 |
| `bash scripts/check_site_props.sh` | 通过，已接入上述两个行为套件；保留既有导入夹具的 unused uuid 警告 |
| `bash scripts/check_site_dst.sh` | 通过 |
| `bash scripts/check_site_sync_gateways.sh` | 总脚本停于既有 `SiteGatewayHeaderLayoutPolicyTests.swift:193` 的 `Keep equal shares with a 112 pt minimum` 断言，exit 133；用 `git show HEAD:<file>` 提取未修改的 Policy/Tests 后独立编译，复现相同失败 |
| 网关总脚本其余检查 | 隔离执行其余 25 次测试调用全部通过；最终边界修正后再次通过受影响的 SyncState、Session、EditSync、Entry/Review/NameColor contract 检查 |
| 工程/本地化归属 | 六个品牌 target 均使用现有共享 en/zh-Hans `Localizable.strings`；没有新增资源归属或编译配置风险，因此选 SunSmart 代表构建 |
| `git diff --check` | 通过 |
| `plutil -lint` 中英文资源 | 通过 |
| SunSmart / Debug / generic iOS | 通过；构建活动日志明确为 `Build succeeded`，Manifest 为 0 errors / 119 warnings；产物已生成。构建末段终端输出未保留，以上结果通过对应的已结束 Xcode 构建记录核实 |

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-entry-review CODE_SIGNING_ALLOWED=NO
```

测试边界：新的缓存用例真实经过序列化/磁盘及异步 Store/Coordinator；Host 夹具执行生产方法，但用轻量对象替代 UIKit 渲染、导航容器及 Mesh 数据来源。未自动连接、安装或操作真机；真实 API、UI 动画/布局、SDK 数据库导入联动和 BLE/网关通信不能由这些离线结果代替。

### 9.3 最短人工验收

1. 网关与 Site 时区已一致：冷启动立即进入，再退出重进；两次都不应提示虚假 pending。
2. 时区准备失败/离线：只显示无法检查的说明，不出现虚假 Review；恢复网络并刷新 Site 后状态恢复。
3. 使用确有时区差异的 Site：pending 数与页面提示/网关颜色一致，Review 进入 `Sync gateways`；无权限或数据不可用时给出对应反馈。
4. 弹窗等待中缓存恢复、或显示后状态变为一致：不保留失效 Review。若点击瞬间才发现无需同步，显示轻量提示，不打开空列表，也不自动进入 Space。
