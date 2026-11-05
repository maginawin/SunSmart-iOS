# 网关 DST 摘要与时钟一致性开发方案

> 状态：阶段 1、阶段 2（含准备失败恢复补修）已接收；用户授权后续任务改为本 session 内继续，阶段 3 的集成复核、剩余品牌构建和交接现已完成，证据见第 14 节。真实 UI/API/Mesh 验收仍待用户完成；两项既有检查失败独立保留，不宣称全部测试通过。
> 后续 UI 反馈：按用户要求改为复用 Create site 标题与图标，并修正 Time Zone 最小行高和换行，记录见第 15 节。第 9–14 节的独立网关图标记录仅描述当时交付状态。
> 执行方式：使用 Superpowers `executing-plans` 按批准阶段实施；不使用子代理，不自动 commit/push，不自动操作真机。

**Goal：** 网关页在 Time Zone 与 Gateway/Local/Off by 之间展示不可展开的 DST 摘要，展示和校时均与 Create site 的有效 current offset 一致。

**Architecture：** 扩展已有 `SiteDaylightSavingTimeView` 的展示模式，复用 Presentation、Service、Store、SiteTimeZoneValue 和现有校时协调器。仅补齐网关宿主的布局、刷新和异步结果一致性，不新增 DST 请求、缓存或持久状态。

**Tech Stack：** Swift、UIKit、SnapKit、现有 Foundation 行为测试及 shell/python 检查脚本。

**Spec：** 本文第 2–4 节；Create/Edit 已确认的字段规则参照 [原组件方案第 9 节](261105_1100_site_dst_hint_analysis_plan.md)，历史实现记录不替代当前源码。

## 1. 当前证据与范围

- 分析时间：2026-11-05，Asia/Singapore。
- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024`。
- 分支：`feat/daylight-saving-261024`；HEAD：`2a200bea97e7767507c20a0e55bde3c205c97f42`；开始分析时 App 工作区干净。
- 本轮只新增本文档；未改生产代码、测试、SDK、依赖或工程配置，未运行构建和回归。
- 页面入口：`SiteViewController` 按网关类型打开 `GatewayViewController` 或其子类 `WiFiGatewayViewController`。两个入口共用 Time Zone/Clock 实现；当前只有目标网关 Proxy Ready 时显示这些区块。
- `SiteFormViewController.updateTimeZone()` 位于 `SunSmart/Main/Site/Controller/SiteCreateViewController.swift`，Create/Edit 共用。其 `displayOffset`、`effectiveOffset(at:)` 与 `formattedLocalDate(at:)` 是本次对齐基准。
- 网关 `.timeZone` 已使用 `SiteTimeZoneValue.displayOffset`；Local 已使用 `GatewayDetailTimeZoneResolver`，有效 Site 分支最终读取 `effectiveOffset(at:)`。不是完全缺少 current offset 支持。
- `GatewayDetailClockCore.offBySeconds` 已按 Gateway 墙上时间减 Local 墙上时间计算；`GatewayDetailClockCoordinator` 已有 TimeSet、最终 TimeGet、offset/时间容差校验、失败恢复和本地保存。
- `synchronizeGatewayClock()` 已调用 `SiteTimeZoneService.prepareClock`；`SiteTimeSetMessageFactory.sendPrepared` 当前还包含既有 TimeZoneSet 补充发送。必须保留，不能按旧文档“未实现未来切换”描述回退现有能力。
- 现有网关观察者在环境变化时会清空状态并重读；读/同步进行中只刷新 Time Zone。展示使用缓存的 offBy，成功 UI 还可能延迟到至少一秒。这些边界需要行为用例确认新旧 offset 不混用，当前仅据源码识别风险，未声称已复现运行故障。
- 现有 `GatewayDetailClockRuntimeContractTests` 有源码文本断言，不能替代异步/时间边界行为证据。
- 本地 workspace 已存在，`.local-sdk/nordic-sig-mesh-sdk` 指向约定 `one-dev`。当前 SDK HEAD 为 `3dbd5566a300422aab47e2dd20c77164f887b22b`，存在其他任务未提交的 MeshLibManager/Heartbeat/Timer/ProxyCommand 及对应测试、脚本改动。本任务只读、不得覆盖；构建前重新记录实际 SDK 状态与写入负责人，依赖变化时不能复用旧构建结果。
- 工程实际含六品牌：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。

## 2. 需求完整性与建议补齐的验收口径

总体合理；以下补齐边界已获用户确认，作为实施与验收契约。

| 项目 | 建议契约 |
| --- | --- |
| 支持 DST 的判定 | 与 Create/Edit 相同，以当前 IANA 的合法快照具有 nextSwitch/switchesTo 为展示依据；isDST 只决定 Active/Unactive，不决定显隐。不另用系统时区库推断支持能力。 |
| 正常顺序 | Time Zone 标题及原时区行 → DST 摘要卡片 → Gateway → Local → Off by / Sync clock。无摘要时不留空白区块。 |
| 页面范围 | 共用网关详情，覆盖普通/4G 与 Wi-Fi；保留现有 Proxy Ready 显示条件及权限边界，不扩展离线网关页和独立 Information 页。 |
| “Time Zone 下面内容相同” | 时区 IANA、offset 文案及 DST 数据规则与 Create/Edit 相同；保留网关已有布局和 Local 行，不再额外复制一行 Create site 的 Local time。 |
| Time Zone 行高与换行 | 最小高度与网关 Name 行相同（`SCRYFrom(44)`）；名称和 offset 可换行，内容较长时自动撑高，不截断。 |
| 不可展开 | 隐藏箭头；普通点击、VoiceOver 激活均不能展开；说明区不进入布局或无障碍顺序；标题不再声明为可展开按钮。仍显示标题、状态及三行摘要。 |
| 两种宿主样式 | Create/Edit 保留当前透明标题区、白色有边框详情卡片和可展开行为；网关使用 Figma 的一体白色圆角摘要卡片、标题与摘要间细分隔线。 |
| Current offset / Switches to | 沿用 Presentation：isDST=true 只在 Current offset 后追加本地化 DST；isDST=false 只在 Switches to 后追加。不改快照原值，不假定差值总是一小时。 |
| Next switch | 与 Create/Edit 一样保留服务器原始字符串、时区后缀及小数秒，允许换行。Figma 示例日期格式不覆盖现有业务契约。 |
| 首次无快照、未返回或无 DST | 隐藏摘要；不把未知视为永久不支持，不闪现其他 IANA 的旧内容。 |
| 请求失败但缓存仍可用 | 继续使用有效缓存的状态、摘要和 current offset，按现有 Service 重试。 |
| 快照跨切换点/时间回拨后失效 | 保留带“需要刷新”的缓存摘要；Local/Off by 无法可靠计算时显示未知，不使用 catalog offset、旧 current offset 或未来 switchesTo 冒充当前值。有效 Site 不因请求失败改用手机时区。 |
| 无/非法 Site 时区的历史数据 | 保留现有网关/TimeSet 的手机 fallback 兼容范围；这与“有效 Site 临时无快照”不同。各入口必须使用同一 fallback 结果；不扩大为 Site 配置修复或写回。 |
| 数据刷新 | 首次出现、磁盘缓存恢复、刷新成功、切换点、前台恢复、重进页面都更新摘要与时间；晚到回调不得污染失效页面、其他 Site/IANA 或新 Proxy 会话。 |
| 同步动作 | 摘要只读，不触发自动校时；Sync clock 与原有 Sync required/自动提示入口共用准备、发送及结果校验。快照不可用时用户可通过既有动作重试，失败结束 loading 并提示，不发送过期 offset。 |

### 2.1 Figma 证据与差异处理

用户链接的 `655:911` 是画布级入口。已通过 connector 获取结构，进一步读取以下两个摘要节点的结构化设计与工具渲染，未使用 Computer Use：

- [Active summary，767:6677](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=767-6677)。
- [Inactive summary，767:6702](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=767-6702)。

共同结构：343pt 示例宽度、10pt 圆角白色卡片、约 46pt 标题、16pt 时钟槽、右侧状态 badge、0.5pt 分隔线、摘要水平内边距 16pt、12pt 字号和三行内容。136.5pt 是短示例文本的总高度，不作为固定高度；长 ISO 字符串、中英文及 iPad 需自适应。

Inactive 设计里的示例值仍是 `UTC-04:00 (DST)` → `UTC-05:00`，与未生效状态不一致。采用设计外观，业务数据服从 Create/Edit 的真实 isDST/offset 规则；保留现有国际化 `Unactive`，不顺手改文案。

## 3. 方案选择与维护成本

推荐 A：扩展现有 View + Presentation 的显示模式，网关共用控制器接入。

- View 提供初始化样式（拟定 `.formDisclosure` 默认、`.gatewaySummary`）；Presentation 增加默认允许展开的配置，网关配置禁止展开，`toggleExpansion()` 对其无效。具体命名允许实施者遵循项目约定，行为不能改变。
- 样式在实例创建时固定，避免 `render` 的相等短路跳过样式更新。创建网关摘要不接入展开回调；无障碍也按只读处理。
- 数据、DST 后缀、过期状态继续由同一 Presentation 生成；View 不访问网络、Site 或 Mesh。
- 网关通过轻量 UITableViewCell 宿主承载组件，新增条件 section 位于 `.timeZone` 和 `.clock` 之间；所有 section 的 data source、header/height、reload、选择处理及 Wi-Fi 的 section 插入都一并核对。隐藏/显示用稳定的区块更新策略，避免 table 数量失配；0.5 秒时钟 tick 不重载整个表。
- 优先使用已有文件内私有宿主，避免为一个 cell 新增工程文件。按用户后续反馈，网关直接复用 Create/Edit 的 `site_dst_title`、14pt `site_dst_clock` 和标题颜色/图文间距，不保留独立网关图标；Figma 16pt 图标差异服从此复用要求。

备选 B：独立网关 DST View，仅复用 Presentation。优点是表单布局完全隔离；缺点是复制三行、状态、过期文案和无障碍维护。已有控件可扩展，当前无必要采用。

不采用 View 内请求、独立缓存或另一套时区算法：现有 Service/Store 已负责请求合并、持久化、重试及边界通知；新增机制会增加生命周期与一致性成本。本方案仅新增页面瞬态展示配置和必要的时间采样/失效状态，不新增磁盘模型。

## 4. 时钟一致性契约与风险

1. 对有效 Site，在相同 `now` 下，Create/Edit 的有效 current offset、网关 Local 使用的 offset、Off by 的目标 offset 和本次 Sync clock 发送/读回校验目标一致。Time Zone 的双 offset 展示不参与数值解析。
2. Off by 语义保持 `Gateway wall time - Local wall time`，保留现有正负号、30 秒显示容差及最终同步 offset 一致性校验；不顺手改变自动提示触发策略。
3. Gateway 行反映网关真实采样及合理走时，不能仅因 Site 目标 offset 更新就一起跳到新目标、掩盖未同步。若采样已失效，可清除并按既有流程重新读取；不能拿旧 offBy 搭配新 Local。若保留样本投影，必须记录采样时刻，不能把旧 sample 当作当前时刻反复作差产生漂移。
4. 覆盖“TimeGet 期间快照更新”“Sync 准备/发送/读回期间跨切换点”“成功反馈延迟期间目标改变”“断连/离开后晚到回调”。重新比较当前目标与操作身份；失效结果不能触发成功 toast、成功回调或覆盖当前显示。需要重读时合并为一次，避免每次缓存通知重复 Mesh 请求。
5. 当前 `read` 完成时直接使用 `SiteTimeZoneValue(storageValue: target.identifier)?.offsetMinutes`，与 Resolver 的手机 fallback 路径不同。阶段 2 用行为证据确认并统一该路径，不能只修 Local 标签。
6. 继续使用既有 coordinator、InformationClockLease、失败恢复、持久化与 SiteViewController 成功回调。TimeSet ACK、最终 TimeGet 校验、后续 TimeZoneSet 及其真实到点执行是不同证据层级；本任务不重定义补充发送的成功策略，不承诺固件或云端能力已验收。

重点验证的五类输入：无快照/非法旧值、已过切换点缓存、非整小时及半小时 DST、操作中目标变化、退出/断连后晚到响应。每类均纳入下列所属阶段，UIKit 与真实协议传输不能由源码断言替代。

## 5. 分阶段任务与停止条件

### 阶段 1：只读 DST 摘要及网关 UI 接入

**输入：** 用户批准本文第 2 节的展示、显隐和设计差异规则。

**主要文件：**

- `SunSmart/Main/Site/View/SiteDaylightSavingTimeView.swift`
- `SunSmart/Main/Site/Model/SiteDaylightSavingTimePresentation.swift`
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `Tests/Site/SiteDaylightSavingTimePresentationTests.swift`
- 必要时已有资源、国际化和工程归属；WiFiGatewayViewController 以兼容核对为主。

**交付接口：** 默认表单行为不变；网关固定只读模式；Presentation 仍以 `update(identifier:snapshot:at:)` 生成内容；网关宿主在统一展示刷新入口传入当前 IANA/快照/时间。

- [x] 核对最新目录、分支/HEAD、App 未提交差异及 SDK 映射/写入状态，记录基线，不覆盖其他任务。
- [x] 在已有 Presentation 行为测试中增加“网关模式不能展开、两种模式共享数据及过期规则、默认表单仍可展开”的用例。沿用真实 Snapshot 解析、Store 异步发布和 Codable 恢复夹具。
- [x] 扩展组件样式并接入共用网关详情；补齐条件 section、自适应高度、Cell 复用、无障碍和观察者初次渲染/重进刷新。
- [x] 运行 `bash scripts/check_site_dst.sh`、`bash scripts/check_gateway_information_time.sh`、`bash scripts/check_gateway_scroll_performance.sh`、`git diff --check`。已有文本 contract 与新行为冲突时改为对业务不变量的校验，不删除保护掩盖失败。
- [x] 核对资源/六品牌文件归属；按第 6 节构建 SunSmart Debug generic iOS 一次。若本阶段引入资源或 target 配置风险，稳定后合入前补受影响品牌，记录待办。
- [x] 更新本文阶段记录，交付变更文件、验证、未完成项与手工验收步骤后停止，不进入阶段 2。

本阶段不改变校时算法或协议。若 UI 验证暴露时钟边界问题，记录并留给阶段 2，不声称完整需求已完成。

### 阶段 2：Local、Off by、Sync clock 一致性及边界补齐

**输入：** 本 session 已接受阶段 1 交付，并提供本阶段提示词；沿用已经确认的方案。

**主要文件：**

- `SunSmart/Main/Device/Gateway/Model/GatewayDetailClockCoordinator.swift`
- `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift`
- `Tests/Device/GatewayDetailClockCoreTests.swift`
- `Tests/Device/GatewayDetailClockRuntimeContractTests.swift`
- `scripts/check_gateway_information_time.sh`
- 可在 `Tests/Device/` 增加小型时钟异步行为用例并接入已有脚本；不建立临时 Xcode 工程。

**依赖只读优先：** SiteTimeZoneValue、Service/Store、SiteTimeSetMessageFactory、SiteViewController 结果消费入口。只在本任务行为确实需要时最小调整共享入口，不扩大为全站重构或 SDK 修改。

**交付不变量：** 同一次状态刷新消费一致的时区目标；读/同步结果携带或验证操作身份及目标；旧 offBy 不得在新 target 下继续呈现为有效。

- [x] 对照第 4 节，先补能复现差异的数值/异步用例；已满足要求的代码保留，只补缺失边界。
- [x] 用有效 current offset 对齐展示、计算、准备和结果消费；保留缺失/非法 Site fallback，同时阻止有效 Site 无可用快照时误回退。
- [x] 在现有状态模型/协调器内补最小失效和收敛处理；处理读/同步繁忙时的目标变化及延迟成功反馈，不另建平行状态机。
- [x] 用真实 Snapshot 解析与可控时钟验证：Active/Unactive、UTC、+05:45、半小时 DST；无缓存、有效缓存、过期失败/恢复；旧值带 UTC 后缀；非法/缺失 Site；样本时差符号及 ±30/31 秒边界。
- [x] 用可控响应顺序验证：TimeGet 期间 offset 更新、Sync 读回期间跨切换点、成功展示延迟期间变化、断连/退出、失败重试；验证最终成功回调只能对应当前有效目标，并保留失败恢复。若夹具未执行真实 coordinator/发送边界，明确未覆盖之处，不用纯策略通过冒充集成通过。
- [x] 运行 `bash scripts/check_site_dst.sh`、`bash scripts/check_gateway_information_time.sh`、`bash scripts/check_site_timeset_message_factory.sh`、`bash scripts/check_gateway_detail_proxy_ready_state.sh`、`git diff --check`；如改 TimeSet 调用或发送边界，追加 `bash scripts/check_site_timeset_call_sites.sh`、`python3 scripts/check_site_dst_transmission.py`。
- [x] 一轮生产代码修改后完成一次 SunSmart Debug generic iOS；更新本文证据及剩余人工路径后停止。

### 阶段 3：集成复核与人工验收交接

**授权范围：** 默认只读 review；不顺手实施新问题。发现阻塞问题返回本 session 决定修复任务。

- [x] 对阶段 1/2 合并后的实际差异核对完整路径、两类网关、Create/Edit 回归及 SiteViewController 成功状态消费。
- [x] 按实际代码/配置/SDK 是否变化决定复用验证结果；仅补缺失检查，不机械重跑全部测试/六品牌构建。
- [x] 如新增资源/target/公共依赖带来跨品牌风险，完成尚欠品牌构建；纯共享逻辑无品牌差异时保留代表构建证据。
- [x] 交付问题列表、未验证项及下列最短人工步骤，更新本文后停止；实际 UI/API/Mesh 由用户验收。

## 6. 验证条件与人工步骤

构建前核对 `SunSmartLocal.xcworkspace`、SunSmart scheme、SDK realpath 和当前差异。采用工作树与任务区分的 DerivedData，同目录构建串行；不 clean、不杀其他进程。

```bash
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-gateway-dst -quiet CODE_SIGNING_ALLOWED=NO build
```

不跑 Simulator、不自动安装真机。构建若受共享 SDK 修改影响，先定位，记录 blocker 并继续独立检查，不改 SDK 绕过；没有对应代码/配置/依赖快照的历史结果不当作当前验证。

原组件文档记录了 Create suite 的既有 `SiteCreationMetadataTests.swift:113` 失败，本轮未重跑确认。若实施确实触及共用表单需重跑相关检查，先对照当前基线，不修改无关城市合并逻辑或放宽断言。

最短人工验收（记录分支、HEAD/未提交差异和实际构建）：

1. 用同一 Site 分别进入普通/4G 与 Wi-Fi 网关详情，目标 Proxy Ready 后核对 Time Zone → DST → Gateway/Local/Off by；断连后符合原显隐规则。
2. 覆盖当前 Active、当前标准时但有下一次切换、无 DST 三类有效响应；对照 Create/Edit 同一时区数据，核对后缀、状态、原始 Next switch。触摸及 VoiceOver 激活均不能展开；Create/Edit 仍可展开。
3. 使用窄屏、iPad、中英文长 ISO 文本检查换行/圆角/间距；反复滚动，检查复用内容和 Sync clock loading 不被时钟 tick 重建。
4. 对网关保留旧 offset、Site 已有新 current offset 的情形，确认 Local 为目标当地时间，Gateway 保留真实网关时间，Off by 正负正确。点击 Sync clock，成功须完成既有读回验证并回传正确 offset。
5. 覆盖请求失败、过期缓存、重进/前台恢复、读/同步中断连和退出；不得显示旧结果成功或在不可用快照下发送旧 offset。跨切换点和失败时序无法在真实环境稳定复现的，保留自动夹具证据并明确人工未覆盖。

本任务没有外部代码或部署工作。真实网关对 TimeZoneSet 的接受、到点自动切换以及服务器后台行为仍需对应团队/设备证据，App 构建与离线回归不能替代。

## 7. 新 session 提示词与回传规则

以下为前两阶段的历史交接提示词。用户在阶段 2 补修回传后已将后续执行方式改为本 session 继续；阶段 3 直接在此执行，不再生成下一 session 提示词。

### 阶段 1 正式提示词（方案已确认）

```text
@Superpowers 执行已确认网关 DST 方案的阶段 1，完成后停止，不自动进入阶段 2。

工作树：/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024
计划：docs/261105_1533_gateway_dst_clock_plan.md

请先读取 AGENTS.md 和计划。使用 executing-plans，在当前 worktree 实施，不使用子代理。只核对可能变化的目录、分支/HEAD、未提交差异、SDK 映射和写入状态；沿用已确认的展示、数据和范围决定，不重新讨论执行方式。

本阶段：扩展 SiteDaylightSavingTimeView/Presentation 的只读摘要模式；在共用 GatewayViewController 的 Time Zone 与 Gateway/Local/Off by 之间接入，覆盖 Wi-Fi 继承入口。按计划复用现有 Service/Store，保持 Create/Edit 原展开行为、原始 Next switch 和 DST 后缀规则。Figma 采用 767:6677 / 767:6702 的摘要外观；业务值按 Create site，不照抄 Inactive 示例数据。

执行阶段 1 的必要行为测试、布局/资源归属检查与 SunSmart Debug generic iOS 构建。不修改阶段 2 的校时算法；发现相关问题记录到原计划。SDK 当前有其他任务未提交改动，只读核对，不覆盖；不改固件/服务器，不 commit/push/merge，不操作真机。

更新原计划的阶段 1 记录，并回传：分支/HEAD及未提交差异、改动文件与行为、验证命令/结果/夹具边界、构建和 SDK 来源、未完成项/发现问题、最短人工步骤。最后停止，等待我把结果返回规划 session。
```

### 后续阶段的提示词生成约束

- 阶段 2：须先接受阶段 1，提示词引用本计划第 4 节和阶段 2；仅授权时钟一致性补齐，带入阶段 1 留下的具体问题、当前 HEAD 和验证结果，不重新设计摘要 UI。
- 阶段 3：须先接受阶段 2，提示词明确只读集成 review；说明可以复用哪些证据、尚欠哪些检查，发现问题先回传，不自动修复。

各阶段统一回传模板：目标与完成范围；分支/HEAD和实际未提交文件；SDK 路径/revision/相关差异；通过/失败/未运行检查及原因；自动化覆盖与真实 UI/API/Mesh 边界；遗留问题；建议下一步。记录直接追加本文，不为每个阶段另建重复总结。

## 8. 授权与阶段记录

- [x] 用户确认本文方案与补齐边界（2026-11-05：“确认，继续”）。
- [x] 阶段 1 已授权，正式提示词已交付。
- [x] 阶段 1 已执行；本 session 已核对返回结果，限定范围结论见第 10 节。
- [x] 阶段 2 正式提示词已交付，供用户在新 session 执行单个阶段。
- [x] 阶段 2 已执行并回传；本 session 已核对，发现第 12 节补修项。
- [x] 阶段 2 补修已完成并获本 session 接收（第 14 节）。
- [x] 阶段 3 已授权在本 session 继续并完成集成复核、剩余五品牌构建和交接（第 14 节）。
- [ ] 用户完成真实 UI/API/Mesh 验收（与上述自动化交付分开记录）。

当前未完成：真实运行验收；五 target 静态断言与 Create Metadata 两项既有检查问题作为独立待办保留。阶段 3 授权范围内工作已完成，无新的 session 提示词或自动实施阶段；本轮只读复核、补充构建并更新本文，未修改业务代码。


## 9. 阶段 1 执行交付（2026-11-05 18:12，Asia/Singapore）

**结论：** 阶段 1 已实现并完成指定行为回归、布局/资源静态检查及一次 SunSmart Debug generic iOS 构建。未进入阶段 2；未操作真机、Simulator、固件或服务器，未 commit/push/merge。UIKit 实际布局、VoiceOver 和真实 API/Mesh 仍待人工验收。Create suite 既有失败仍在；不能据此交付声称全部测试或完整时钟一致性需求已通过。

### 9.1 最新基线、变更及 SDK

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024`。
- 分支：`feat/daylight-saving-261024`；开始与结束 HEAD 均为 `c210afc8fdfd73518dcfba6d10096d64e4ae45e8`。相较规划基线已合入 Scene 分支，实施以当前源码为准。
- 入场已有：`SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved` 修改（远端 release revision 从 `4b4c0f56` 改为 `2809c540`），以及未跟踪的本计划。锁文件差异完整保留，没有修改依赖声明。
- 实际入口：`SunSmartLocal.xcworkspace`，SunSmart scheme；`xcodebuild -list` 解析的 SDK 为本工作树 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK 分支 `one-dev`、HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，开始、构建前和结束均干净。规划时的未提交 SDK 改动已不在当前状态；本任务未写 SDK、未使用新增 SDK API。Git 无法给出其他活动任务的写入负责人，本任务始终只读，构建前后未观察到 SDK 变化。

结束时全部未提交文件：

| 文件 | 归属 |
| --- | --- |
| `SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved` | 入场已有，原样保留 |
| `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift` | 本阶段修改 |
| `SunSmart/Main/Site/Model/SiteDaylightSavingTimePresentation.swift` | 本阶段修改 |
| `SunSmart/Main/Site/View/SiteDaylightSavingTimeView.swift` | 本阶段修改 |
| `Tests/Site/SiteDaylightSavingTimePresentationTests.swift` | 本阶段修改 |
| `SunSmart/Assets.xcassets/Site/gateway_dst_clock.imageset/Contents.json` | 本阶段新增 |
| `SunSmart/Assets.xcassets/Site/gateway_dst_clock.imageset/gateway_dst_clock.svg` | 本阶段新增 |
| `docs/261105_1533_gateway_dst_clock_plan.md` | 原未跟踪计划，本阶段更新 |

### 9.2 实现与关键差异

- Presentation 新增不可变 `allowsExpansion`（默认 true）；网关使用 false，`toggleExpansion()` 无效。默认 Create/Edit 的展开、同 IANA 保持、换 IANA 收起等规则不变。
- View 初始化时固定 `.formDisclosure` / `.gatewaySummary`。网关采用一体白色圆角卡片、0.5pt 分隔线、约 46pt 自适应标题、16pt 时钟槽及三行摘要；标题使用静态 UIView 无按钮 trait/激活动作，箭头不进入布局，帮助说明不创建、不进入无障碍顺序。表单保留原透明标题、白色有边框详情卡片、14pt 原图标和点击展开。
- 两个 Figma 节点均已通过 connector 获取结构与渲染。仅采用外观；Inactive 值仍遵循真实 `isDST`，不复制设计里的示例错误。原始 Next switch（含时区后缀与小数秒）保留并允许换行；过期仍显示历史三行和“需要刷新”，不自行翻转 DST 值。
- 共用 GatewayViewController 在 `.timeZone` 与 `.clock` 之间按 Presentation 内容插入 `.daylightSavingTime`；普通/4G 共用此控制器，Wi-Fi 在 `super.sections` 的 `.clock` 后插入网络区块，顺序兼容。原 Proxy Ready/权限边界保留。
- 文件内私有 Cell 承载组件，自适应高度、复用时清空旧展示；摘要消失时移除整个 section 及其间距。拓扑变化时一次 `reloadData()`，同拓扑内容变化仅 reload 摘要 section；0.5 秒 tick 原样保留，只更新可见时钟行，不重建 Sync clock 操作行。
- 直接读取既有 Service/Store 快照；viewWillAppear、Proxy Ready 更新前取当前值，订阅后立即补一次渲染，覆盖“可用内存缓存无新通知”；磁盘恢复、成功更新、过期/时间回拨、前台恢复继续由现有 Store 通知驱动。移除观察者沿用页面生命周期，回调增加页面可见和当前 IANA 校验。
- 新增图标是 Figma 原始 16×16 SVG，未改写原图标或路径；所有文案复用已有中英 Key。没有数据库、export JSON、Snapshot、缓存或 API 数据结构变更，没有新增请求/持久状态，没有更改校时算法、协议发送或同步成功策略。

### 9.3 验证命令、结果与覆盖边界

| 命令/检查 | 本次结果 |
| --- | --- |
| `bash scripts/check_site_dst.sh` | 4 组通过。新增只读用例先出现缺失接口编译失败；补齐接口但未加 guard 时，明确失败于 `Gateway summary cannot expand, including stale cache`；加 guard 后通过 |
| `bash scripts/check_gateway_information_time.sh` | 全部通过，包括 Coordinator/Core 行为、既有 runtime/rows contract、FastAdd、Wi-Fi 自动加载、Proxy Ready 无 TimeSet 及 strings lint |
| `bash scripts/check_gateway_scroll_performance.sh` | 通过；这是源码 contract，不是实际帧率测试 |
| `bash scripts/check_site_creation.sh` | **既有失败仍复现**：`SiteCreationMetadataTests.swift:113`，exit 133；脚本在第一组停止，后续组未运行 |
| `git diff --exit-code HEAD --` 后接 Create metadata 脚本全部编译输入文件 | exit 0，证明本次失败对应的测试及生产输入均未改；未修改城市合并逻辑或放宽断言 |
| `swiftc -parse-as-library Tests/Site/SiteTimeZoneUIContractTests.swift -o /tmp/GatewayDSTSiteTimeZoneUIContractTests`，再按 `scripts/check_site_sync_gateways.sh` 末尾两组参数调用 | 两组通过：共用 Create/Edit 路由/生命周期源码 contract，以及本地化/工程归属 contract |
| `plutil -lint SunSmart.xcodeproj/project.pbxproj`、`git diff --check` | 通过 |
| Python 解析 pbxproj/strings/资产 JSON 与 SVG；调用 `Lumineux/Scripts/merge_assets.rb` 到本计划独立临时目录 | 六品牌三个 Swift 文件和共享 strings 归属通过；两种语言各 19 个复用 Key 唯一存在；五品牌直接共享 Assets，Lumineux 合并后新 SVG 与源文件字节相同；16pt 尺寸、资源非空、调用点和布局槽核对通过 |

行为夹具直接运行真实 Snapshot 解析、Presentation、Store 异步发布及 Codable 磁盘读写；两种模式分别覆盖首次无快照、不同 IANA 晚到结果、有效缓存失败、过期失败/恢复、持久缓存重启和内存缓存重选，并验证原始小数秒、半小时 DST、Active/Unactive 后缀及不展开。布局检查覆盖条件 section、header/footer、自动高度、长值换行约束、只读 accessibility、Cell 复用及 Wi-Fi 插入位置。

**边界：** Foundation 夹具没有实例化 UIKit 控制器、真实网络 Service 请求、真实 UITableView/VoiceOver，也没有执行 Mesh 异步收发。网关既有 runtime/scroll 检查含源码文本断言，不能替代时序或真机体验证据。本阶段没有新增临时 Xcode 测试工程，没有测帧率或运行窄屏/iPad UI。

### 9.4 构建结果

执行第 6 节原命令：

```bash
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-gateway-dst -quiet CODE_SIGNING_ALLOWED=NO build
```

- 结果 **exit 0**；产物已生成。Xcode `Logs/Build/LogStoreManifest.plist` 对应记录 `63688B3E-D4BB-42D4-90AB-90177B17EED2`：**0 errors / 119 warnings**。
- 输出曾包含 CryptoSwift `command failed with exit code 0 but produced no further output` 的异常诊断；最终退出状态与 Xcode 构建记录均确认成功。警告包括 CryptoSwift Swift 6 兼容性及 SDK/第三方弃用信息，未在本阶段修改这些依赖。
- 最初沙箱内 `xcodebuild -list` 无法识别存在且 XML 有效的 workspace；提升执行权限后，实际 workspace、scheme、本地 SDK 均成功解析，随后完成上述构建。没有切换正式入口、clean、清共享缓存或安装设备。
- 新增共享资源已做六品牌归属和 Lumineux 实际合并核对；本阶段按授权仅构建 SunSmart。**合入前尚需其他五品牌 Debug generic iOS 资源编译验证**，可由阶段 3 根据届时实际状态完成，不默认增加 Release。

### 9.5 阶段 2 事项与人工交接

本轮源码复核仍看到以下既有边界，**未做异步行为复现、未修改**，按授权留给阶段 2：

1. `gatewayClockEnvironmentDidChange()` 在 read/sync 繁忙时只刷新 Time Zone（本次还刷新摘要），没有失效旧 offBy；Local tick 可能消费新 target，Gateway 投影和旧 offBy 的一致性仍需阶段 2 行为证据。
2. Coordinator `read()` 成功时重新通过 `SiteTimeZoneValue(storageValue: target.identifier)?.offsetMinutes` 取值，与 Resolver 的缺失/非法 Site 手机 fallback 路径仍不同。
3. 延迟同步成功 closure 校验 presentation ID，但没有重新比较当前 target；退出/断连、目标更新及跨切换点期间的回调与 toast 一致性仍按原计划处理。

本阶段由实施者自审，未使用子代理；未发现需要继续扩大阶段 1 修改的明确问题。执行技能的 `task-start` 无法识别中文“阶段 1”标题，直接以原阶段清单为 brief，并在本计划专属忽略目录记录 ledger；没有改变授权范围。保留当前工作树与未提交改动，等待规划 session 核对，不启动阶段 2。

最短人工验收：

1. 同一 Site 分别进入普通/4G 与 Wi-Fi 详情，Proxy Ready 后检查 **Time Zone → DST → Gateway/Local/Off by**；无快照/无 DST 不留摘要空白，断连遵循原显隐。
2. 对照 Create/Edit 的 Active、Unactive 数据，核对 DST 后缀、原始 Next switch；网关触摸/VoiceOver 均不展开且不读说明，Create/Edit 仍能展开。
3. 中英文、窄屏/iPad、长 ISO 值反复滚动，核对换行、圆角、间距和复用内容；0.5 秒 tick 不重建 Sync clock loading。
4. 有效缓存下请求失败及重进应保留内容；过期/时间回拨应显示需要刷新，成功刷新后恢复；退出再进不得闪现另一 IANA。时钟算法与 Mesh 时序验收按阶段 2/3 继续，不把本次 UI 交付当作校时已验收。

## 10. 规划 session 阶段 1 核对与阶段 2 交接

**结论：阶段 1 可接收，进入阶段 2。** 本轮检查未发现阶段 1 范围内阻塞后续实施的明确问题；这不是 UIKit、VoiceOver、真实 API/Mesh 或整项需求已通过的结论。

### 10.1 本轮直接核对证据

- 当前分支、HEAD 与回传一致：`feat/daylight-saving-261024` / `c210afc8fdfd73518dcfba6d10096d64e4ae45e8`；未提交文件范围与第 9.1 节一致。未修改任何生产代码、测试、资源或锁文件，只更新本计划。
- 当前 SDK realpath 为约定 `one-dev`，HEAD 为 `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，`git status --short` 为空。
- 逐项核对三个生产 Swift 文件和测试的实际 diff：默认表单模式与固定只读网关模式分离；View 和 Presentation 均阻止展开；静态标题无按钮行为，说明不加入网关布局；初次/重进刷新、IANA 回调校验、动态 section 及 Wi-Fi 插入顺序均覆盖。
- 核对 `.daylightSavingTime` 的 cell、自动高度、header/footer、选择处理及共用圆角配置；时钟 tick 没有新增整表 reload。实际 UIKit 自动高度、滚动、触摸及无障碍仍需运行证据。
- 为直接确认新增共享行为，重跑 `bash scripts/check_site_dst.sh`，4 组全部通过；`git diff --check` 通过。其他已交付回归未重复运行；不重跑已知无关 Create 失败。
- 直接读取 Xcode Build LogStoreManifest，记录 `63688B3E-D4BB-42D4-90AB-90177B17EED2` 的 workspace/scheme/Debug 与交付一致，记录为 0 errors / 119 warnings，SunSmart.app 可执行文件存在。本轮没有重建；历史进程 exit 0 仍来自阶段 1 执行记录。
- 其余五品牌资源构建保留到阶段 3/合入前。Create Metadata 既有失败独立保留，不扩大本任务修复范围。

### 10.2 阶段 2 必须落到行为用例的源码风险

1. `gatewayClockEnvironmentDidChange()` 在 read/sync 进行中仅刷新时区与摘要；时钟行使用新 target 及缓存 offBy，目标变化时的失效/重读策略必须统一。
2. Coordinator `read()` 直接从 `target.identifier` 构造 SiteTimeZoneValue 获取 offset，缺失/非法 Site 的手机 fallback 没有沿用 Resolver，需覆盖真实读取结果消费路径。
3. `scheduleGatewayClockSyncCompletion()` 的延迟 closure 仅以 presentation ID 过滤，必须结合当前目标、页面生命周期及 Proxy 会话检查。`finishGatewayConnectionSession()` 与 coordinator 的 operation/lease/回调清理需要一起追踪，不只给 toast 加判断。

上述是源码定位的待复现风险，本轮未执行异步收发复现。阶段 2 先用数值和可控时序夹具证实，再最小修复；若某条已有其他机制保障，给出证据，不为满足计划字面重复增加状态。

### 10.3 阶段 2 正式提示词

```text
@Superpowers 执行已确认网关 DST 方案的阶段 2，完成后停止，不进入阶段 3。

工作树：/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024
计划：docs/261105_1533_gateway_dst_clock_plan.md

先读取 AGENTS.md 和计划，重点为第 4 节、阶段 2 清单及第 9–10 节交接。使用 executing-plans，在当前工作树实施，不使用子代理。阶段 1 已获规划 session 接收，沿用已确认的 UI/字段/范围决定，不重新讨论方案或执行方式。

接手基线：App 分支 feat/daylight-saving-261024，HEAD c210afc8fdfd73518dcfba6d10096d64e4ae45e8；阶段 1 的三个生产 Swift 文件、测试、网关图标和计划尚未提交，另有入场已存在的 Package.resolved 修改。SDK one-dev HEAD 2809c540be3b965a6a847ee4586ac46faf2ca2b5，在规划核对时干净。先核对最新状态及实际映射，保留所有已有改动，不回滚或重新实现阶段 1。

本阶段目标：同一有效 Site 的 Time Zone/DST 摘要、Local、Off by、Sync clock 统一消费有效 current offset；既有正常路径保留，补齐失败与异步边界。

先补可复现的数值/时序用例，再最小修复以下路径：
1. read/sync 期间时区快照变化，旧 Off by 不得与新 Local/target 混用；Gateway 行不能跟随目标跳时而掩盖未同步。需要重新读取时合并为一次，不因每个缓存通知重复发送 Mesh 命令。
2. 统一 GatewayDetailTimeZoneResolver 与 coordinator read 的目标来源，保留缺失/非法 Site 的既有手机 fallback；有效 Site 无快照或过期时不能回退目录/手机/未来 offset 校时。
3. Sync 准备、排队、发送、读回及延迟成功反馈均检查当前目标和操作身份；覆盖跨切换点、断连重连、退出及晚到回调。失效操作不得发布成功 toast/回传确认、覆盖新状态或让 loading/lease 残留。

从 GatewayViewController、GatewayDetailClockCoordinator 沿 Service/Store、SiteTimeSetMessageFactory 和 SiteViewController 成功结果消费入口核对完整链路。优先在已有状态/协调器内处理，不另建平行状态机或持久化机制。保留普通/4G 与 Wi-Fi 共用行为、0.5 秒可见时间刷新、原按钮交互、30 秒容差、模型绑定与最终 TimeGet 校验、失败恢复、既有 TimeZoneSet 补充发送及成功策略。不修改阶段 1 摘要设计，不更改无关自动提示策略。

验证至少覆盖：Active/Unactive、UTC、+05:45、半小时 DST、无/有效/过期缓存、旧格式与非法/缺失 Site、Off by 正负及 ±30/31 秒；读期间快照变化、同步跨切换点、延迟成功期间目标变化、断连/退出及失败重试。使用真实 Snapshot 解析与可控时间/响应顺序；夹具须运行生产策略和实际结果消费代码，不能复制一套测试实现。若真实 coordinator/持久化/传输边界不能自动覆盖，明确限制，不以源码字符串断言代替异步行为验证。

按计划运行相关回归，一轮生产修改后构建 SunSmart Debug generic iOS 一次。若改动调用/发送边界，追加计划指定的 TimeSet 调用与传输检查；如果新增共享 Swift 文件，核对所有受影响 target 归属。其他五品牌资源构建仍列阶段 3 待办；Create Metadata 既有失败不顺手修复。不跑 Simulator，不自动操作真机，不改 SDK/固件/服务器，不 commit/push/merge。

更新原计划，回传分支/HEAD/未提交差异、SDK 来源、每条风险的复现与处理、验证命令/结果/夹具边界、构建结果、剩余人工验收及未解决问题。区分编译、离线行为、UIKit 和真实 Mesh 证据。完成阶段 2 后停止，等待我把结果返回规划 session。
```

## 11. 阶段 2 执行交付（2026-11-05，Asia/Singapore）

**范围：** 阶段 2 已实施；新增行为回归通过。Proxy Ready 检查存在下述基线静态断言失败，不声称全部脚本通过。最终构建结果见 11.4。仅执行本阶段并自审，未进入阶段 3，等待规划 session 核对。本轮未 commit/push/merge、未操作真机或 Simulator，未写 SDK、固件或服务器。无数据库、export JSON、Snapshot/API/缓存结构变更；新增字段仅为页面/操作瞬态身份。

### 11.1 基线、来源与差异

- 分支 `feat/daylight-saving-261024`，App HEAD 始终 `c210afc8fdfd73518dcfba6d10096d64e4ae45e8`。
- `SunSmartLocal.xcworkspace` / `SunSmart` scheme；`xcodebuild -list` 解析本工作树 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为约定 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`。开始和最终核对均干净；本任务只读，没有新增 SDK API 或发布依赖。其他活动任务写入负责人不能从 Git 判断。
- 第 9.1 节阶段 1 文件、图标及入场 Package.resolved 差异保留；没有重新实现摘要 UI。GatewayViewController 在阶段 1 基础上追加本阶段行为。
- 阶段 2 生产文件：`GatewayDetailClockCoordinator.swift`、`GatewayViewController.swift`、`SiteTimeSetMessageFactory.swift`。
- 阶段 2 测试/脚本：`Tests/Device/GatewayDetailClockCoreTests.swift`、`Tests/Site/SiteTimeSetMessageFactoryTests.swift`、`scripts/check_gateway_information_time.sh`；新增 `scripts/check_gateway_clock_async.py`、`scripts/check_gateway_clock_consumption.py`。同时更新本计划；没有新增共享 Swift 文件或工程归属变化。

### 11.2 复现、最小修复与保留策略

| 风险 | 修改前直接行为证据 | 处理及最终结果 |
| --- | --- | --- |
| read 的手机 fallback 与 Resolver 分叉 | 真实 coordinator 的 read 成功回调返回 nil Off by，断言失败 | read 使用捕获目标的 offset；结果前比较同一 Resolver 目标。缺失/非法 Site 保持手机 fallback，有效 Site 无快照/过期保持 nil，不借目录或未来 offset 校时 |
| read 期间目标变化 | 请求后移除有效快照，旧 read 仍发布 success | 操作 ID、目标及 Proxy session 均校验后才持久化/发布；失效恢复备份并失败 |
| busy 时旧 Off by 搭配新 Local | 执行生产 `gatewayClockEnvironmentDidChange`，同步/读取繁忙时旧 offBy 未清除 | 目标改变立即取消旧操作、释放 lease、清空样本/loading/pending sync；新目标重读一次。同目标缓存通知不重复发送。Gateway 暂显未知，避免随新 Local 跳时掩盖未同步 |
| 退出与重连 | `finishPage()` 后 lease 仍占用；同地址换 session 后旧最终读回仍成功 | finishPage 立即取消释放并恢复备份；每个操作固定 Proxy session；页面关闭/断连/新 Ready session 清理操作、准备身份和展示身份。晚到旧响应不能结束新 lease 或发布结果 |
| 延迟成功反馈 | 生产延迟 completion 执行前改变目标，仍发布 toast 和成功回传 | 延迟消费同时核对 presentation ID、目标、可见性、页面结束标记及 Proxy session；失效结果清理 loading，不发布成功 |
| 跨切换点、排队和失败重试 | 原 sync target 校验已能拒绝无效目标，未为此重建状态机 | 保留既有保护；补实际 coordinator 可控时间跨 next_switch、取消排队后发送有效性为 false、晚到回调、失败恢复/重试用例，均通过 |
| 旧格式/空值发送身份 | Factory resolution 将旧格式规范化、空字符串转 nil；与 Site 原值比较所需身份不一致，新增测试失败 | resolution 保留输入 storageValue，仍以解析后的 IANA/有效快照计算数值。旧 UTC 后缀不参与 offset 计算；空值继续手机 fallback。仅修瞬态身份，不改 Site 数据 |
| 系统时间变化而 offset 不变 | 本轮通知去重实现下，新行为用例失败 | 系统时间/系统时区通知强制重读；Store 缓存通知仍按目标合并，保留原系统校时恢复能力 |

准备任务有独立 UUID 与 Proxy session 校验；Store 为该准备刷新快照时保留准备任务，避免刷新本身取消用户的 Sync 操作。断连/退出则立即使准备身份失效。排队的 Sync 在启动前再次核对展示 ID 和当前目标。

Service/Store 链路已只读核对：snapshotProvider 来自 Store，Store 负责磁盘恢复、请求合并、过期/边界通知与失败重试；不新建缓存或请求机制。TimeSet 工厂保留 prepareForTransmission、transmissionIsValid、responseIsValid 以及补充 TimeZoneSet；其补充 ACK 不升级为成功前提。仍要求模型绑定、TimeSet 返回、最终 TimeGet offset 一致及 ±30 秒容差。

SiteViewController 的 `recordGatewayDetailTimeZoneConfirmation` 本来就校验页面会话、网关 ID 和当前有效 Site offset；本轮通过抽取执行该真实方法验证有效确认、错误网关、错误 offset 和旧 session，不改该入口，也不允许手机 fallback 写成有效 Site 的确认状态。普通/4G 与 Wi-Fi 共用父类路径、0.5 秒可见行更新、原按钮和自动提示策略保留。

### 11.3 验证命令、结果与夹具边界

| 检查 | 结果 |
| --- | --- |
| `bash scripts/check_site_dst.sh` | 4 组通过（真实 Snapshot、Store、Presentation 和磁盘 Codable） |
| `bash scripts/check_gateway_information_time.sh` | 通过；含既有 Core/runtime/rows/FastAdd/Wi-Fi 和新增两组行为脚本 |
| `zsh scripts/check_site_timeset_message_factory.sh` | Factory 与 Value 通过；新增旧格式/空值身份用例先失败后通过。脚本使用 zsh 的路径语法，按 shebang 执行 |
| `zsh scripts/check_site_timeset_call_sites.sh` | 通过；最初按计划文字用 bash 调用报 `A: unbound variable`，确认脚本是 zsh 后正确调用通过 |
| `python3 scripts/check_site_dst_transmission.py` | 真实 SDK handle、普通队列与 FastAdd 发送边界夹具通过 |
| `bash scripts/check_gateway_detail_proxy_ready_state.sh` | 两组行为通过，含 19 个 connection lifecycle 场景；随后静态工程计数失败：期望 10 条（五 target），当前为 12 条（六 target）。工程与脚本相对 HEAD 均无改动，不放宽断言掩盖基线问题；其后单一 file reference 断言未由该次脚本执行 |
| `bash scripts/check_gateway_scroll_performance.sh` | 源码 contract 通过，不代表实际帧率 |
| `plutil -lint SunSmart.xcodeproj/project.pbxproj`、`git diff --check` | 通过 |

新增 coordinator 夹具编译完整生产 coordinator（仅移除 SDK 条件导入），运行真实 InformationClockLease、MeshTimeConversion 与 Snapshot 解析。外部 Node/模型绑定/API/数据库/云同步以边界桩替代，控制响应顺序与 Resolver 时间；覆盖正常、fallback、read 变更、跨切换点、退出、同地址重连、取消后旧响应、TimeGet/TimeSet 失败、重试和排队发送有效性。新 Core 用例覆盖 UTC、+05:45、半小时 DST、Active/Unactive、合法无缓存、切换点过期、非法/缺失 Site 及 -31 秒；已有用例覆盖其他 ±30/31 与正负号。

消费夹具直接抽取执行 GatewayViewController 的目标失效、清理、延迟成功方法及 SiteViewController 确认方法，使用真实 ClockState/Resolver；没有复制一套结果消费算法。包含目标改变、延迟期退出/重连、同目标通知去重和系统时间强制重读。

**不能由上述结果替代的边界：** 未实例化 UIKit 控制器/UITableView、未执行真实 SiteTimeZoneService HTTP 请求、App 工厂异步准备到真实 GATT 的完整联合链路、实际 SQLite save/云同步、真实绑定 ACK/TimeStatus 路由。coordinator 夹具的 TimeSet 工厂是可控边界桩，SDK 发送检查是另一夹具，两者不是端到端传输证明。SDK 入站 TimeStatus 会先更新 Node 缓存，本轮没有模拟该真实 SDK 副作用与晚到包的交错，不能据此保证实际 Node 缓存不会被其他收包路径更新；需要真实 Mesh 验收。没有修改 SDK 来处理这一边界。

Create Metadata 既有失败未重跑、未修改；其他五品牌资源编译与 UIKit/API/Mesh 仍留给阶段 3/人工验收，不以本轮通过结果替代。

### 11.4 构建

使用第 6 节同一条 SunSmart Debug generic iOS 命令和稳定 DerivedData。沙箱内 `-list` 再次出现 workspace 无法识别，提升权限后确认 workspace、SunSmart scheme 和本地 SDK 映射。没有切换正式入口、clean、删除缓存或操作设备。

首次构建 exit 0；其后新增空字符串身份修复，第二次构建 exit 0；收尾行为用例又发现同 offset 系统时间通知必须保留强制重读，修复后执行最终构建。因此实际发生三次构建，额外两次均由新的具体修复触发，未扩大品牌或配置矩阵。最终构建 **exit 0**，Xcode 记录 `FE0BFFFB-9430-4A51-83C2-C9233E647E50`：**0 errors / 5 warnings**。警告来自未修改的 SiteViewController capture/default 分支；未为此扩大修复。最终 SDK status 干净，App HEAD 未变。

### 11.5 未解决项与最短人工验收

- 规划 session 尚未接收本阶段；阶段 3 未执行。
- Proxy Ready 脚本五 target 旧断言失败、Create Metadata 已知失败独立保留；其他五品牌资源构建仍待阶段 3。
- 真实 SDK 入站副作用、网络、数据库、GATT 与 UIKit 联合生命周期尚未验证，见 11.3，不声称绝对无竞态。
- 人工使用本分支本轮未提交构建：普通/4G 和 Wi-Fi 各进入一次；让网关保留旧 offset、Site 刷新为新 current offset，确认 Local 为目标时间，Gateway 不随目标直接跳时，失效期间未知，重读后 Off by 符号正确。
- 点击 Sync，覆盖读期间点击、跨切换点、失败后重试；成功只能在最终读回验证后出现。断连重连、退出再进入、成功反馈延迟内变更目标，旧操作不得提示成功、回传确认或留下 loading。
- 改变手机系统时间但保持相同时区，确认重新读取；重复同一缓存通知不持续发送 TimeGet。有效 Site 无快照/过期不得使用手机或未来 offset；旧格式、空时区/非法时区的 fallback 与发送身份另行核对。
- 回到 Site 确认已同步网关投影只接受当前页面会话/网关/有效目标；真实 TimeZoneSet 接受及到点切换仍需设备证据。完成本次回传后停止，等待规划 session。

## 12. 规划 session 阶段 2 核对与补修（2026-11-05 19:06，Asia/Singapore）

**结论：暂不接收阶段 2，不进入阶段 3。** 已有改动与新增夹具的覆盖范围基本符合交接，但在本阶段明确承诺的“失败恢复/清除失效 loading”范围内复现了一条遗漏。不是回退全部阶段 2，也未据此扩大到 SDK 或外部系统修复。

### 12.1 已复现问题：准备失败后 Sync clock 无法直接重试

- 位置：`GatewayViewController.swift` 的 `GatewayClockOffsetCell.actionButtonTapped()`（核对时第 2809 行）与 `synchronizeGatewayClock()`（第 1951 行，nil 分支第 1966 行）。
- 条件：目标 Proxy Ready；有效 Site 无可用快照/缓存已过期；之前的读取已完成，目标已被记录；点击 Sync clock 后，`prepareClock` 刷新失败并返回 nil，Store 通知中的目标仍与原目标相同。
- 触发链：Cell 点击立即 `updateSyncingAppearance(isSyncing: true)`，禁用按钮；控制器等待 prepare；Store 同目标通知被 `gatewayClockObservedTarget` 去重，不刷新 clock section；prepare 返回 nil 仅显示错误并退出，虽然 `preparingGatewayDST` 已恢复 false，Cell 没有收到非 syncing 状态。
- 结果：错误提示已出现，但按钮继续 loading 且禁用。0.5 秒 tick 只更新 Gateway/Local 两行，不更新操作行，因此不能依靠 tick 恢复；必须额外重载/重进才可能恢复重试。
- 优先级：P2，阻塞阶段 2 的失败恢复验收。该准备失败路径此前就不完整，本轮要求明确涵盖它；不声称它必然由阶段 2 新引入。

本轮在临时目录用 `swiftc -parse-as-library` 编译运行最小行为夹具，直接抽取当前生产 `actionButtonTapped`、`synchronizeGatewayClock`、`gatewayClockEnvironmentDidChange`、`invalidateGatewayClockOperation`，未修改生产方法体。Service 用 MainActor 可控失败及同目标通知替代，Cell 渲染边界记录 loading/enabled，section reload 映射回实际状态刷新。输出为：

```text
prepare_failed=true, preparing=false, reloads=0, button_enabled=false, cell_loading=true, sync_started=0
REPRODUCED: prepare failure leaves Sync clock disabled and loading
```

夹具验证真实准备/通知结果消费控制流，未实例化 UIKit、调用 HTTP 或发送 Mesh；实际按钮状态映射另与生产 `updateSyncingAppearance` 核对。临时夹具执行完删除，没有在仓库增加未授权测试文件。后续补修应将相应行为纳入已有可维护测试脚本。

### 12.2 其他核对结果

- 当前 App HEAD `c210afc8fdfd73518dcfba6d10096d64e4ae45e8`；SDK HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5` 且状态干净，均与交接一致。
- 重新运行 `python3 scripts/check_gateway_clock_async.py`，9 个模式通过；`python3 scripts/check_gateway_clock_consumption.py`，5 个模式通过。后者未抽取准备方法或按钮点击，因此没有覆盖上述失败。这些通过结果不被否定，但不能扩展为整条交互验证。
- 直接核对 Xcode 记录 `FE0BFFFB-9430-4A51-83C2-C9233E647E50`：SunSmartLocal / SunSmart / Debug，0 errors / 5 warnings。本轮未重建，历史 exit 0 来自实施记录；三次构建的后两次有明确新修复触发，无需因此重复构建。
- Proxy Ready 脚本的失败确实是既有五 target 文本计数：脚本与 pbxproj 相对 HEAD 均无差异。通过 `plutil -convert json` 解析 PBXNativeTarget → PBXSourcesBuildPhase → PBXBuildFile → PBXFileReference，SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六品牌各恰有一份 `GatewayDetailProxyConnectionState.swift`，唯一 file reference。无当前 target 漏归属证据，完整脚本仍应如实记录失败。
- 不在本轮修改上述静态断言；独立列为检查脚本维护事项。阶段 3 可复用当前结构化核对方法补充归属证据，不能把原脚本写为通过。
- SDK 入站 TimeStatus 的缓存副作用、真实数据库/HTTP/GATT/UI 等仍按第 11.3 节保留未覆盖边界，未提升为已验证或另行修复。
- 本轮只更新本文档，未修改业务代码、测试、SDK、依赖或图标。

### 12.3 补修范围与验收

只补齐 Sync 准备阶段退出时的可见状态恢复，沿用已有准备 ID/Proxy 会话/页面身份及同步状态机制，不新增持久状态或平行状态机。

必须覆盖：

1. prepare 返回 nil，含同目标 Store 通知与没有额外通知：结束 loading、按钮可重试、错误提示合理，不能发送 TimeSet。
2. 失败后再次点击，可进入新的准备流程并正常同步；准备成功不能被提前复位或丢失操作。
3. 旧准备响应在断连/离开/新准备后晚到：不得复位新操作的 loading、显示旧错误或启动发送。处理其他早退时先核对谁拥有当前 UI 状态，不能把所有 guard 失败简单改为无条件全局刷新。
4. 现有读中点击、pending sync、成功/失败反馈和最短 Syncing 展示策略不退化；不更改阶段 1 UI 样式。

### 12.4 阶段 2 补修正式提示词

```text
@Superpowers 补修网关 DST 方案阶段 2 的准备失败恢复遗漏，完成后停止，不进入阶段 3。

工作树：/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024
计划：docs/261105_1533_gateway_dst_clock_plan.md

先读取 AGENTS.md、计划第 11–12 节，使用 executing-plans；这是原阶段 2 失败恢复范围内的补修，不重新规划、不使用子代理。核对当前分支/HEAD/未提交差异及 SDK 映射，保留阶段 1/2 全部已有改动和 Package.resolved。

规划 session 已复现：GatewayClockOffsetCell 点击先置 loading；prepareClock 失败返回 nil，目标未变化时 Store 通知被去重；控制器仅提示需要刷新，未恢复操作行，按钮持续禁用。详细触发链和夹具输出见第 12.1 节。

先在已有消费行为脚本中加入运行真实按钮点击、准备方法和状态恢复逻辑的失败用例，再最小修复。必须验证 nil 准备结果可恢复重试、失败后成功、旧准备晚到不能清除新操作状态；覆盖同目标通知/无通知，以及退出/断连/重连。不能只测试 preparingGatewayDST 已为 false，也不能仅断言源码存在 reload。不要对过期 preparation ID 无条件刷新或清除新操作。

沿用既有准备身份及状态机制，不重写摘要 UI、不更改 offset/协议/自动提示策略。保留现有读中点击、pending sync、最短 Syncing 展示和成功回调保护。

执行受影响消费行为回归、check_gateway_information_time.sh、check_gateway_scroll_performance.sh 和 git diff --check，一轮生产修改后构建 SunSmart Debug generic iOS 一次。未改动的 Factory/DST/SDK 发送结果可在确认输入未变后复用，避免机械全量重跑。

五 target 静态断言是已确认的基线脚本问题，本次不改；Create Metadata、其他五品牌构建和真实 UI/API/Mesh 边界继续独立保留。不写 SDK/固件/服务器，不 commit/push/merge，不操作真机。

更新原计划，回传复现与修复前后行为、改动文件、验证结果/夹具边界、构建结果及未解决项。完成后停止，等待我将结果返回规划 session 再决定进入阶段 3。
```


## 13. 阶段 2 准备失败恢复补修交付（2026-11-05 19:15，Asia/Singapore）

**结论：本次补修已完成，等待规划 session 核对；阶段 3 未执行。** 使用 executing-plans，按第 12.4 节执行，未重新规划、未使用子代理。仅自审本次补修差异及相关准备/读/同步消费链，没有把自审视为独立 review。没有 commit/push/merge、操作真机或 Simulator、修改 SDK/固件/服务器。

### 13.1 基线与改动范围

- App 分支 `feat/daylight-saving-261024`，HEAD `c210afc8fdfd73518dcfba6d10096d64e4ae45e8` 未变，沿用原隔离工作树。
- 本地入口 `SunSmartLocal.xcworkspace` / `SunSmart` scheme；`xcodebuild -list` 确认包解析为本工作树 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。SDK HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，入场及构建后均干净；本任务不写 SDK。
- 对入场文件内容做 SHA-256 快照核对，本轮只修改 `GatewayViewController.swift`、`scripts/check_gateway_clock_consumption.py` 及本文档。阶段 1/2 其他生产、测试、图标、工程资源和入场 `Package.resolved` 差异保留。
- 无数据库、export JSON、API、缓存结构或持久状态变更；没有新增状态机、SDK API、文案或品牌分支。

### 13.2 修复前后行为与所有权

扩展原消费脚本，先运行新增测试再修改生产代码。最终有效 RED 运行的 19 个模式中，4 个因可见 loading 未恢复而失败：无通知的 nil 准备结果、同目标通知后的 nil 结果、失败后重试、准备期间 Site 改变后早退。其余模式通过，包括旧 nil/成功响应晚到的保护。扩展夹具时将原 `readGatewayClock` 空桩换成生产方法，因此原 busy 用例改为断言旧同步结束且新目标真实 read 已开始，避免将正常新读取误判为 loading 未清理。

| 路径 | 修复前 | 修复后行为证据 |
| --- | --- | --- |
| prepare 返回 nil，无 Store 通知 | 错误已提示、准备标志清除，按钮仍禁用且 loading | 按钮 enabled、spinner 隐藏/动画停止、标题恢复；错误一次；同步启动次数为 0 |
| prepare 返回 nil，同目标 Store 通知 | 通知被去重，无行刷新，持续 loading | 通知仍去重；由当前准备失败分支恢复操作行，不依赖额外通知 |
| 失败后再次点击 | 第二次点击被禁用按钮拦截 | 启动新准备；成功后启动同步、保留最短 Syncing 展示，再发布一次成功及回传 |
| 同一准备任务期间 Site 改变 | 页面上下文 guard 早退，按钮仍 loading | 当前准备 ID 仍匹配时恢复操作行，不提示旧错误、不启动同步 |
| 退出/断连后的旧准备、重连后新准备/新同步期间旧准备 | 既有身份保护有效 | 旧 nil 与成功结果均不额外刷新行、不清除新 ID/loading、不提示错误、不启动额外同步 |
| 读取中点击、同步失败 | 既有 pending/失败机制 | 等真实 read completion 后仅启动一次同步；失败反馈后按钮可用；成功反馈仍受最短展示及身份保护 |

修复只位于 `synchronizeGatewayClock()`：保留最前面的 preparation ID 相等校验；拥有当前准备 ID 的任务清除准备标志后，在页面/Proxy/Site 上下文不再有效或 prepared 为 nil 时刷新 `.clock`。nil 分支继续显示既有本地化错误。过期 ID 在这些副作用之前直接退出，不无条件清除操作或刷新新 UI。成功分支及 `synchronizePreparedGatewayClock`、pending sync、读/发送/延迟完成方法均未改动。

GREEN 输出（无通知和同目标通知均一致）：

```text
prepare_failed=true, preparing=false, button_enabled=true, cell_loading=false, sync_started=0
```

### 13.3 验证、复用与覆盖边界

| 检查 | 本轮结果 |
| --- | --- |
| `python3 scripts/check_gateway_clock_consumption.py` | 19/19 模式通过；原 5 个 + 新增 14 个，含失败后重试、实际按钮/标题/spinner 状态、8 个旧响应交错模式、读中 pending、同步失败及至少约一秒的展示检查 |
| `bash scripts/check_gateway_information_time.sh` | 完整通过；包括 Core/runtime/rows/FastAdd/Wi-Fi、9 个 coordinator 异步模式及上述消费行为模式 |
| `bash scripts/check_gateway_scroll_performance.sh` | 源码 contract 通过；不代表真实帧率 |
| `git diff --check` | 通过 |
| Factory / DST / SDK 发送检查 | 本轮未重复执行；核对入场哈希与原交接，Factory、Service/Store、Value、Snapshot、coordinator、对应测试/脚本、工程/依赖内容未变，SDK revision 及干净状态一致；沿用第 11 节的限定结果，不扩展为本次 UI 联合验收 |

消费脚本直接抽取生产 `actionButtonTapped`、Cell `update` / `updateSyncingAppearance`、控制器操作行绑定、`synchronizeGatewayClock`、准备后同步、read、发送入口及延迟消费方法，使用真实 ClockState/Resolver。断言检查按钮 enabled、spinner 可见性、动画边界调用、标题、错误/成功反馈及同步启动次数，非仅检查 preparing 标志或源码含 reload。

**夹具边界：** 未实例化 UIKit/UITableView；表格 reload 映射为执行抽取的生产操作行绑定，View/动画对象为属性桩。Service 以可控 continuation 提供 nil/非 nil 准备结果并单独触发同目标通知，未执行真实 HTTP/Store refresh/磁盘恢复联合链路。coordinator 的 read/synchronize I/O 是可控边界桩，故“准备失败不发送”直接证明的是没有进入同步发送入口；实际 TimeSet/GATT 行为仍由既有独立 coordinator/发送测试限定覆盖。退出/断连由夹具设置对应页面/会话状态并调用真实共享 `invalidateGatewayClockOperation`，未执行完整 UIKit/蓝牙通知生命周期。真实 SDK 入站 TimeStatus 缓存副作用、SQLite/云同步、ACK 与收包交错仍按第 11.3 节保留未覆盖边界。

自审核对了：ID 校验位于所有新增恢复副作用之前；nil 分支不进入同步；正常成功分支未增加提前复位；同目标去重不变；普通/4G 与 Wi-Fi 继续共用父类；未触及摘要样式、0.5 秒时间行更新、资源/target 归属或自动提示策略。

### 13.4 构建与停止项

按第 6 节命令，本轮生产修改完成后仅执行 **一次** SunSmart Debug generic iOS 构建：**exit 0，0 errors / 0 warnings**。Xcode 构建记录 `F67E6A49-6070-4F9D-BA50-66B7117C99C1`，`SunSmartLocal` / `SunSmart` / `Debug`。这是本轮增量构建记录，不表示历史五条 warning 已被修复。沿用稳定 DerivedData；未 clean、切换正式入口或清理缓存。

- 阶段 2 仍等待规划 session 接收，阶段 3 未执行。
- 五 target 静态断言维护项未修改/未重跑，仍保留第 12.2 节六品牌结构化归属证据，不能把原脚本标记为通过。
- Create Metadata 已知问题未修改/未重跑；其他五品牌构建和真实 UI/API/Mesh 验收仍未完成。
- 最短人工验收：在本分支未提交构建的普通/4G 与 Wi-Fi 网关详情，目标 Proxy Ready 且有效 Site 无可用快照时，让准备请求失败；点击 Sync clock 应提示错误并恢复按钮。恢复请求后再次点击，应完成同步。准备期间断连/退出，再重连进入新操作，旧响应不得干扰新 loading、提示旧错误或额外发送。

补修交付到此停止，不进入阶段 3，不自动执行人工步骤。

## 14. 阶段 2 补修接收与阶段 3 最终交付（2026-11-05，Asia/Singapore）

**结论：阶段 2 补修接收，阶段 3 已完成。** 用户明确要求“就在这个 session 继续后面的任务”，因此本规划 session 直接完成集成复核和其余五品牌构建。本轮未发现该功能差异内新的明确阻塞问题；这不是整条分支所有历史提交的审查结论，也不代表实际 UIKit/API/Mesh 已验收。

### 14.1 执行范围与当前状态

- App：`feat/daylight-saving-261024`，HEAD `c210afc8fdfd73518dcfba6d10096d64e4ae45e8`，本轮前后未变。
- SDK：`.local-sdk/nordic-sig-mesh-sdk` realpath 为约定 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，前后工作区均干净；只读使用。
- 本轮仅更新本文档。对入场的 14 个生产/测试/脚本/图标/锁文件差异做 SHA-256 快照，构建后全部一致；保留阶段 1/2 和 Package.resolved 原有改动。
- 无数据库、export JSON、API、缓存结构或持久状态变更。未操作真机/Simulator，未使用 Computer Use、子代理，未 commit/push/merge、clean 或清共享缓存。
- 执行方式沿用 executing-plans，但遵循用户的单人、只读 review/必要构建范围；原计划和本节作为执行记录，不额外创建重复计划或新业务修复任务。

### 14.2 补修接收与集成复核证据

1. 直接复核 `synchronizeGatewayClock()`：只有持有当前 preparation ID 的响应才清除准备状态并恢复操作行；nil/上下文早退均能退出可见 loading，旧 ID 在所有新增 UI 副作用之前退出。
2. 本 session 重新运行 `python3 scripts/check_gateway_clock_consumption.py`，**19/19 场景通过**。包含无通知/同目标通知准备失败、失败重试、Site 变化、pending sync、同步失败、旧 nil/成功响应交错及延迟结果；输出确认 `button_enabled=true, cell_loading=false, sync_started=0`。夹具边界仍遵循第 13.3 节，不视为 UIKit 实测。
3. 核对阶段 1/2 最终差异与调用链：Site 页面入口 → 普通/4G/Wi-Fi 共用网关控制器 → 只读摘要/表单可展开模式 → Service/Store → current offset Resolver → coordinator 的准备/读取/同步/lease → TimeSet 工厂 → SiteViewController 成功确认。保留 Proxy Ready、失败恢复、原始 Next switch、DST 后缀、0.5 秒时间行更新和既有补充 TimeZoneSet 策略。
4. 核对 `SiteTimeSetTimeZoneResolution.storageValue` 保留原始存储身份仅作用于操作有效性比较，数值仍来自合法快照；旧 UTC 后缀不参与 current offset 计算，未写回 Site 持久数据。
5. 核对 Create/Edit 共用表单默认模式、两种 View 样式的布局/无障碍结构、网关条件 section 全部表格入口、Wi-Fi 在 clock 后插入网络区块，以及 Site 成功确认的页面会话/网关 ID/有效 offset 校验。没有重新实现其他页面。
6. `plutil -convert json` 解析真实工程引用关系：GatewayViewController、GatewayDetailClockCoordinator、SiteTimeSetMessageFactory、SiteDaylightSavingTimePresentation、SiteDaylightSavingTimeView、GatewayDetailProxyConnectionState 均为唯一 file reference，六品牌各恰有一次 Sources 归属。
7. 原完整网关回归、DST、Factory、TimeSet 调用/发送、滚动 contract 等结果按第 11/13 节限定复用；本轮没有相关生产或测试输入变化，SDK 也未变化，不机械重跑。`git diff --check` 本轮通过。

### 14.3 六品牌构建及实际资源产物

先执行 `xcodebuild -list -workspace SunSmartLocal.xcworkspace`，确认六品牌 scheme 及包解析确实来自本工作树 `.local-sdk`。本轮命令直接运行成功，未再遇到之前的沙箱 workspace 识别问题。

其余五品牌依次串行执行，每品牌一次：

```bash
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme '<品牌>' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-gateway-dst -quiet CODE_SIGNING_ALLOWED=NO build
```

| Scheme | 本轮处理 | 结果 | Xcode warnings | Xcode 构建记录 UUID |
| --- | --- | --- | --- | --- |
| SunSmart | 复用第 13 节、直接核实记录和产物 | 记录 0 errors；原执行 exit 0 | 0（上轮增量记录） | `F67E6A49-6070-4F9D-BA50-66B7117C99C1` |
| Archipelago | 本轮构建一次 | exit 0 / 0 errors | 274 | `BCF3BD81-9DED-4AA2-AB89-6C9A705904C6` |
| SLG Sync Plus | 本轮构建一次 | exit 0 / 0 errors | 342 | `47112A0F-F51C-45F0-960E-291AD24EB54D` |
| SylSmart | 本轮构建一次 | exit 0 / 0 errors | 283 | `50B92273-CB1B-41DB-A2C1-E30A54051003` |
| Lumineux | 本轮构建一次 | exit 0 / 0 errors | 84 | `FDF81BE7-80C3-413C-8B27-0A52B27E2DC1` |
| HSmart | 本轮构建一次 | exit 0 / 0 errors | 88 | `4CAE6B6D-A86D-4DB5-B3D1-7666E9702E45` |

Xcode 数据来自上述 DerivedData 的 `Logs/Build/LogStoreManifest.plist`。本轮读取六份实际 `.app`，确认可执行文件非空且链接时间位于对应构建记录时段；通过 `xcrun assetutil --info` 检查每份 Assets.car 中 `gateway_dst_clock` 的 1x/2x/3x 图像为 16/32/48 像素，且两种语言的 DST 标题、状态、三行字段及刷新提示 Key 都存在。Lumineux 同样核对实际合并后的 `.app`，不是仅看源文件归属。

警告主要涉及未修改的品牌重复资源、第三方弃用、原有 Swift 警告及个别重复编译文件/Info.plist 资源配置。HSmart 输出另有两条 `command failed with exit code 0 but produced no further output` 诊断，最终进程 exit 0、Xcode 主记录 0 errors、可执行文件在本次构建中完成链接并具有所需资源，三者已交叉核对；没有为消除这些诊断修改无关代码或重复构建。不同品牌/增量范围的 warning 数不能用于宣称警告被修复。

### 14.4 未完成项与最短人工验收

**独立保留的检查问题：**

- `check_gateway_detail_proxy_ready_state.sh` 的五 target 文本计数断言过时；第 12.2/14.2 节已结构化验证六品牌归属。本轮没有修改脚本，也不能将其完整执行结果写为通过。可另行将检查维护为明确六品牌 Sources 归属断言。
- Create Metadata 的 `SiteCreationMetadataTests.swift:113` 既有失败未修复、未重跑。城市元数据合并契约不属于网关 DST 范围，不能通过放宽测试并入本次交付。

**真实运行尚未验证：** UIKit 自适应高度/滚动/VoiceOver；真实 HTTP 与 Store/磁盘恢复联合流程；实际 SQLite/云同步；GATT/绑定 ACK/TimeStatus 路由及 SDK 入站 Node 缓存副作用；真实 TimeZoneSet 接受和到点切换。自动化回归和六品牌构建均不替代这些证据。

用户最短步骤（使用当前分支未提交构建，记录网关类型、时区及 API/设备结果）：

1. 普通/4G、Wi-Fi 各进入一次；Proxy Ready 后核对 Time Zone → DST → Gateway/Local/Off by。Active、Unactive、无 DST 三类与 Create/Edit 对照；网关不可展开，Create/Edit 仍可展开；长 ISO 字符串在窄屏/iPad/中文下不裁切。
2. 有效 Site 无可用快照时让准备请求失败：点击 Sync clock 后应提示错误、恢复按钮；恢复请求再次点击可同步。准备期间退出/断连再重连发起新操作，旧响应不能干扰新 loading 或提示旧成功/错误。
3. 网关保留旧 offset、Site 获取新 current offset：Local 采用目标当地时间，Gateway 不能随目标一起跳时掩盖未同步；重读后 Off by 正负正确。同步成功须完成既有读回验证并向 Site 回传当前确认。补查跨切换点、系统时间变化及真实 SDK 收包交错。

本次授权工作到此完成，代码和资源保持未提交状态；无需再开新的实施 session。后续真实验收发现问题再按证据处理，两个既有检查问题仍作为独立待办。

## 15. UI 反馈修正：复用图标与 Time Zone 行高（2026-11-05）

### 原因与改动

- 用户反馈要求直接沿用 Create site 的标题和图标。此前为匹配 Figma 的 16pt 时钟单独导出了 `gateway_dst_clock`；这里不需要独立资产，现删除其 imageset 两个文件，统一使用已有 `site_dst_clock`（14pt）、`site_dst_title`、标题颜色和 6pt 图文间距。网关继续只读，Create/Edit 展开行为保持。
- Time Zone 虽使用 `automaticDimension`，标题只有上下各 10pt 的约束，没有最小高度，因此短名称可能低于 Name 的 44pt。另一个问题是设置了多行，但继承了 UILabel 的截断模式。现给标题补充最小 24pt 高度，连同上下间距保证行高至少 `SCRYFrom(44)`；名称和 offset 都明确按词换行、不限行，内容较长时自动撑高。
- 接手分支仍为 `feat/daylight-saving-261024`，HEAD 已由前轮基线推进至 `79a7420654e46225b966e4efab2b1563f0d3ebd2`，入场工作区干净。本轮修改两个生产 Swift 文件、删除两个专用图标文件并更新本文档；不修改 SDK、依赖、时钟计算或持久数据。

### 验证与边界

- `bash scripts/check_site_dst.sh`：四组通过。
- `bash scripts/check_gateway_information_time.sh`：完整通过，包含 19 个消费行为场景。
- `bash scripts/check_gateway_scroll_performance.sh`：通过。
- 六品牌资源归属复核：五品牌直接使用共享资产目录；Lumineux 使用既有合并脚本。在临时输出目录执行真实合并，确认共享图标与源文件字节相同，独立网关图标不存在。最初按所有品牌直接引用共享目录的检查假设不适用于 Lumineux，已按实际合并入口核对。
- SunSmart Debug generic iOS：首次沙箱内执行在 workspace 加载阶段 exit 66，未进入编译；已确认 workspace XML 和 SDK realpath 正确，使用相同命令获准在沙箱外构建后 exit 0。构建记录 `CBE97374-C9F9-435A-9991-D721D008A332`；直接检查实际 `.app/Assets.car`，确认 `site_dst_clock` 存在、`gateway_dst_clock` 已移除。`git diff --check` 通过。
- SDK 仍为 `one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，只读使用。六品牌上轮构建是修改前证据；本轮采用代表 scheme 构建和资源归属/实际合并验证，不宣称六品牌本轮均重建。
- 真实 UIKit 排版未运行；现有回归不验证屏幕上的实际高度。人工只需在普通/4G、Wi-Fi 网关各核对：短 Time Zone 行至少与 Name 等高，长 IANA/offset 在窄屏及 iPad 完整换行，DST 标题和图标与 Create site 一致且网关仍不可展开。
