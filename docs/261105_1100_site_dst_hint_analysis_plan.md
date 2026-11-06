# Create / Edit Site 夏令时提示组件需求分析与开发方案

状态：已按用户确认方案完成 App 实现及自动化验证；Create 既有测试失败与人工验收边界见第 8 节。

2026-11-06 追加：用户已确认并完成第 10 节的 Create / Edit / Gateway Next switch 展示调整，覆盖前文“原始 Next switch 透传”的历史要求。DST 回归与 SunSmart generic iOS 构建通过，真实页面验收待完成；记录见第 10.6 节。

## 1. 结论与范围

需求合理，现有时区模型、缓存及共用表单足以支持。建议新增一个可复用 UIKit View，在 Create/Edit 的共用表单接入，不新增请求、持久化结构或 DST 推算机制。

本轮用户已明确：**保留 Figma 展开区原文，将与当前 App 能力不一致的内容列为外部能力待确认项。** 这不构成新增 DST 开关、未来切换计划、服务器或固件修改的授权。

用户已确认本方案补充的展示边界：无快照隐藏、过期快照提示、标题保留、相同时区保留展开状态，以及有 Site Type 时的排列顺序。

## 2. 当前证据

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-daylight-saving-261024`。
- 分支：`feat/daylight-saving-261024`；HEAD：`7051230f74a2196843ab4db60f6d363827c51da0`；分析开始时工作区干净。
- `SunSmart/Main/Site/Controller/SiteCreateViewController.swift` 定义 `SiteFormViewController`，Create 与 `SiteEditViewController` 共用该表单；UI 使用 UIKit、UIStackView、SnapKit。
- 当前顺序为 Time Zone（含 Local time、Edit 的未同步提示）→ 条件显示的 Site Type → Description。
- `SiteFormViewController.updateTimeZone()` 统一处理订阅和显示。手动选择时区、城市带入时区、切换国家导致城市时区回退，均可到达此入口。
- `SunSmart/Common/Data/SiteTimeZoneValue.swift` 的 `SiteTimeZoneSnapshot` 已原样保存 `isDST/currentOffset/nextSwitch/switchesTo`，并校验 nextSwitch/switchesTo 成对为空或有效；不能直接使用拼接过的 `displayOffset` 填充三行摘要。
- `SiteTimeZoneService` / `SiteTimeZoneStore` 已支持按 IANA 共用缓存、异步持久化读取、合并请求、按自然日刷新、跨切换点刷新及前台恢复。失败保留原缓存；时间到达 nextSwitch 后旧快照不能再作为当前校时依据。
- 当前页面离开时移除观察，返回时重新订阅；回调检查当前 IANA 和账号/区域上下文。
- 实际工程包含 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个品牌 target，共用表单和 Service 均已归属六个 target。
- 本轮不触及 SDK；实施构建前按项目要求核对本地 workspace、scheme 和 SDK realpath，不复用历史构建结论。

Figma 已通过 connector 读取结构化设计及配套渲染：

- [非 DST 状态，764:6612](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=764-6612)：橙色 `Unactive` 标签。
- [DST 状态，764:6550](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=764-6550)：绿色 `Active` 标签。
- 两者均为展开态，结构相同，状态与示例值不同。用户第二条“未启用（is_dst=true）”按布尔值与 Active 设计理解为“当前处于夏令时”。is_dst 是状态，不是可操作开关。

## 3. 展示与交互契约

### 3.1 判定与布局

在当前接口契约下，以当前所选 IANA 对应的合法快照 `nextSwitch != nil` 决定展示；不按 isDST 决定支持与否，不用系统时区数据库或本地 offset 猜测支持情况。null 仅决定当前不展示，不缓存为永久不支持。

建议顺序：

- 常规：Time Zone 整组 → DST 提示 → Description。
- Site Type 可见：Time Zone 整组 → DST 提示 → Site Type → Description；不移动已有 Site Type 的相对顺序。
- 隐藏时不留空白卡片或额外占位间距。

建议折叠态保留 Figma 的时钟、`Daylight Saving Time · Auto` 标题、状态标签和展开箭头，作为操作入口；卡片内容仅显示三行摘要。展开时在摘要下显示分隔线、`How DST sync works`、`With gateway`、`Without gateway`、`Next DST switch` 及其完整说明。折叠后说明内容也退出无障碍读取顺序。

### 3.2 字段映射

| UI | 数据 | 展示规则 |
| --- | --- | --- |
| Current offset | currentOffset | 使用服务器/缓存字符串；isDST=true 时追加本地化 ` (DST)`（用户后续调整） |
| Next switch | nextSwitch | 原样显示，保留 ISO 时间、时区后缀和可能存在的小数秒，不转换成手机时区或 Figma 示例格式 |
| Switches to | switchesTo | 使用服务器/缓存字符串；isDST=false 时追加本地化 ` (DST)`（用户后续调整） |
| 状态标签 | isDST | true 使用 Active 外观，false 使用 Unactive 外观；保留设计原英文，增加对应中文本地化 |

日期解析仅复用现有快照有效性判断，不参与三个值的重排。除用户后续要求的 DST 后缀外，不重写原值，不假定 DST 差值总是一小时。

### 3.3 状态转换与失败边界（本方案建议）

| 条件/操作 | 结果 |
| --- | --- |
| 初次进入 Create/Edit，快照支持 DST | 默认折叠 |
| 无时区、无缓存、首次请求尚未返回 | 隐藏；保持既有 Time Zone 显示，不将未知解释成已证实不支持 |
| 快照 nextSwitch 为 null | 隐藏整个组件 |
| 同一 IANA 的内存/磁盘缓存命中、请求刷新 | 更新数据，保留用户当前展开状态 |
| 切换到另一 IANA | 立即清除旧时区展示与展开状态；使用新时区缓存/响应重新判定；支持则折叠显示 |
| A→B→A 或重新创建页面 | 默认折叠；不持久化每个时区的展开偏好 |
| 选择同一个 IANA，或进入选择页后取消返回 | 保留展开状态，不将观察者重建当作换时区 |
| 城市带入/国家回退使 IANA 改变 | 与手动换时区使用同一规则 |
| 请求失败，有旧快照且未跨已知切换点 | 保留缓存摘要及状态；延续既有重试策略 |
| 已跨 nextSwitch，或设备时间回拨到 requestedAt 之前 | 保留有 DST 信息的缓存摘要，但在标题区使用中性“需要刷新”状态替代 Active/Unactive，明确摘要是缓存、可能过期；不自行翻转 isDST 或交换 offsets |
| 刷新成功，新的 nextSwitch 为 null | 隐藏并清除展开状态；后续重新显示默认收起 |
| A 请求晚于切换 B 返回、页面退出、账号/区域变化 | 只允许更新所属 IANA 缓存；不得覆盖 B 页面或操作已失效页面 |

跨自然日但未跨已知切换点的缓存沿用既有可用性规则。无缓存失败不新增阻断弹窗，不影响既有表单提交条件；重试沿用重进页面、前台恢复和现有时区观察机制，不增加每秒失败重试。

“需要刷新”是异常态对 Figma 的必要补充；正常展开说明仍保留原文。原始 ISO 文本可能比示例长，摘要值允许换行，不能通过截断或改格式回避布局。

## 4. 方案选择与实现分工

推荐：**纯展示自定义 View + 现有共享表单/Service/Store**。

原因：两个页面已有同一入口，四字段及缓存机制也已存在。重复在两个控制器实现会产生行为差异；让 View 内部请求或新增缓存会重复所有权、重试和生命周期管理，且不利于后续网关复用。

1. 新增 `SunSmart/Main/Site/View/SiteDaylightSavingTimeView.swift`。
   - 负责标题、状态、三行摘要、展开说明、箭头、无障碍和自适应高度。
   - 接收展示数据及展开状态，不访问网络、SiteData、网关或 SDK，不发同步命令。
   - 回调用户展开/收起及布局变化，由宿主协调页面滚动。
   - 延用当前表单字体、色彩、尺寸与圆角习惯；匹配 Figma 的 10pt 圆角、细边框、摘要/说明内边距等结构，卡片总高随文本伸缩，不复制 487pt 固定高度。
   - 优先核对现有 disclosure 等资源是否与设计完全一致；不一致的时钟/切换图标从 Figma 导出为本地资源，并核对六品牌归属。
2. 新增轻量 `SiteDaylightSavingTimePresentation.swift`（名称实施时可沿项目约定调整）。
   - 只保存页面内瞬态 IANA/展开状态，生成显隐、原始摘要和有效/过期展示状态。
   - 独立于 UIKit，便于直接验证行为；不新增磁盘缓存或 Site 持久属性。
   - 区分 IANA 变化与同 IANA 刷新，避免页面重订阅就把用户展开状态重置。
3. 修改共用 `SiteFormViewController`。
   - 在 Time Zone 整组后插入自定义 View。
   - 在现有 `updateTimeZone()` 内读取同 IANA 快照并更新展示状态，覆盖所有时区变更入口。
   - 继续沿用当前观察者释放、弱引用和上下文校验，使用既有 Store 边界通知响应切换点，不增加组件专属定时器。
   - 检查展开/收起、异步显示/隐藏时 Description、键盘可视区及页面滚动位置。
4. 补齐 `SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings` 和必要图标资源；由本任务统一处理 `project.pbxproj` 的六 target 文件归属。

不需要变更 Site 保存、导入导出、云端属性、时区选择列表、设备校时与 SDK；本次只预留网关页面复用能力，不接入网关页面。展开状态不参与脏数据判定、保存或同步。

## 5. 外部说明契约与发布依赖

用户已选择保留 Figma 原文。以下属于产品文案依赖，不能以本次 App UI 完成证明能力成立：

| 原文承诺 | 已知 App 边界 | 责任方与验收方式 |
| --- | --- | --- |
| 有网关时自动向 Mesh 节点分发，无需手动同步 | App 可发起既有网关校时流程，无法仅从 App 源码证明服务器/网关后台自动执行 | 服务器/网关团队提供实际触发、离线重试及节点回读证据 |
| 提前同步下一次切换，节点到点自动执行 | 本次不实现未来 TimeZoneSet 调度；现有时区缓存刷新不等于设备定时执行 | 网关/固件团队说明命令与兼容范围，验证 App 关闭、跨 DST、节点离线重连及后续切换计划续期 |
| 切换后重新开关 DST 并重访所有 Spaces | 当前 App 无此开关，且本次没有新增开关授权 | 产品/App 负责人确认后续入口或文案发布安排；验证实际可操作路径及各 Space 节点状态 |

上述未确认项不阻塞提示组件的开发，但作为产品发布前待确认项保留。普通的方案确认不扩大到这些能力研发。沿用已有 [DST 数据与校时方案](260820_0414_site_timezone_dst_solution_analysis.md) 的外部验收边界。

## 6. 实施步骤与验收

待确认后按以下顺序推进：

1. 固定展示状态行为与用例，在现有 `Tests/Site/` 和脚本体系验证实际状态转换。
2. 实现自定义 View、共用表单接入、本地化和资源归属。
3. 运行相关最小回归：`scripts/check_site_dst.sh`、`scripts/check_site_creation.sh`、`scripts/check_site_props.sh`，将新增展示策略行为用例纳入相关脚本；检查工程和资源归属、字符串格式、`git diff --check`。
4. 核对本地 workspace/SDK 映射后构建 SunSmart Debug generic iOS 一次，`CODE_SIGNING_ALLOWED=NO`。新增共享文件/资源存在跨品牌编译风险，稳定后且合入前覆盖另外五个品牌；不跑 Simulator，不默认增加 Release。
5. 交付自动化结果和最短人工验收步骤；不自动操作真机，不 commit/push。

新增行为回归至少覆盖：

- nextSwitch 为 null 隐藏；isDST true/false 均显示，在对应 offset 后追加 DST 后缀，不修改底层快照原值。
- ISO 长时间字符串、半小时 DST、带小数秒字段的原值透传。
- 初始折叠→展开→同 IANA 刷新保持展开→换 IANA 收起→无 DST 隐藏→切回支持时区收起。
- 无缓存、缓存启动恢复、请求失败、跨切换点失败与恢复、旧请求晚到，使用真实 Snapshot 解析与 Codable 缓存边界；不只断言源码字符串。
- 城市选择、国家回退、同 IANA 取消返回的宿主行为；没有 UIKit 自动运行证据的部分明确转人工验收。

最短人工验收：在 Create 和 Edit 分别选择当前 DST、当前标准时但有下一次切换、无 DST 三类时区；核对三行服务器原值、状态颜色、默认收起与展开原文；快速换时区、选择城市、切换国家、进入选择页后取消、断网后重进；检查 iPhone 窄屏/iPad、中英文长文本、Description 聚焦及上下滚动。六品牌核对资源可见，含 Site Type 可见与不可见配置。

构建仅证明编译集成；离线用例仅证明其覆盖的数据/状态行为；真实 API、UIKit 体验及网关/固件能力分别验收。

## 7. 初次分析交付记录（实施前）

- 已完成：当前源码与 Git 状态核对、两个 Figma 节点读取、共享入口/缓存/回调/品牌归属分析、需求缺口和开发方案。
- 用户已确认：Figma 展开原文保留，外部能力列待确认。
- 尚未完成：用户批准完整方案、业务实施、回归与构建、真实 UI/API/设备验收。
- 本轮仅新增本文档，未修改业务代码、依赖或 SDK。

## 8. 已授权实施清单与执行记录

目标：Create/Edit 共用可复用 DST 提示，使用现有缓存及观察，不改变同步协议。技术栈：UIKit、SnapKit、Foundation 状态策略。Spec：本文第 1–6 节。执行方式：依项目规则在现有 worktree 由当前任务实施，不使用子代理、不 commit/push；进度直接维护本文。

重点检查：重复订阅不重置展开状态；隐藏后重新显示默认收起；旧 IANA 回调不能覆盖新选择；过切换点显示过期状态；原始 ISO 字符串换行不裁切。UIKit 运行效果留待人工验收，离线状态测试不能替代。

- [x] Task 1：新增 `Tests/Site/SiteDaylightSavingTimePresentationTests.swift`，先运行得到缺少实现的失败；实现 `SunSmart/Main/Site/Model/SiteDaylightSavingTimePresentation.swift`，接口为 `update(identifier:snapshot:at:)`、`toggleExpansion()`，输出 `content`、`isExpanded`。用真实 Snapshot 解析、Store 异步请求和磁盘 Codable 缓存验证显隐、原值、换区/重复刷新及过期/恢复。纳入 `scripts/check_site_dst.sh` 并得到 GREEN。
- [x] Task 2：新增 `SunSmart/Main/Site/View/SiteDaylightSavingTimeView.swift`，接口为 `render(_ presentation:)`、`onToggleExpansion`；Figma 三个 SVG 下载到共享 Assets，原文补齐中英文本地化；共用表单在 `updateTimeZone()` 接入，标题按钮驱动状态策略，布局变化通知宿主处理键盘滚动。共享文件加入六 target。
- [x] Task 3：运行 DST/Create/Props 回归；验证工程、资源和本地化，检查差异；核对 SDK 后串行构建六品牌 Debug generic iOS，记录结果与人工边界。Create 既有失败已独立复现并保留，详见下文。

实施开始：分支/HEAD 未变化，仅有上轮新增的本文档。已确认现有 linked worktree 与 `.local-sdk/nordic-sig-mesh-sdk` 指向约定的 `one-dev`；不修改 SDK。既有计划已获授权，不重复请求执行方式或方案批准。

### 执行证据与既有失败

- 既有 DST 基线 3 组通过；新增用例首先因缺少 `SiteDaylightSavingTimePresentation` 实现失败，实现后 DST 全部 4 组通过。新增用例实际经过 Store 异步发布和磁盘 Codable 缓存恢复；网络由完整响应夹具替代，未调用真实 API。
- `bash scripts/check_site_props.sh` 全部通过（含字段更新/回执、真实导入代码片段、失败重试、迟到响应及 Site 入口策略）。既有导入夹具仍有 unused uuid 警告。
- `bash scripts/check_site_creation.sh` 在 `Tests/Site/SiteCreationMetadataTests.swift:113` 失败，不能宣称整组通过。将该用例及所有五个生产源码输入从原始 HEAD 提取到独立临时目录重编译，复现相同失败；六个输入文件均与 HEAD 字节一致，本次未修改。
- 原有失败的具体分歧：`SitePropsEditPolicy.mergeRetrieve` 对相同 timestamp 的局部远端 city/cityId 数据按字段合并并清除已提供字段的 pending；该用例期望不完整/不匹配城市身份一律不持久化。此问题留作独立契约核对，本任务不改变合并业务或放宽断言。
- 在临时 shell 中运行原 Create 脚本首个失败用例之后的未改动命令，其余 8 个可执行测试组全部通过：Draft、Country catalog、Country store、Timezone catalog、City catalog、Current location、City response、City store。原脚本未删改或跳过其断言。
- 项目/资源检查已核对两个 Swift 文件各加入六个 target；15 个新中英 Key 及复用 Key 均有且唯一；SVG 根尺寸保持 14/14/20pt。Lumineux 使用原有合并脚本生成共享+品牌资源，未直接增加第二份资产目录。
- UI 按设计结构实现，披露按钮保留最小 44pt 点击高度，整体卡片与值文本自适应；运行布局、触控及 VoiceOver 尚待用户实测。
- SDK 来源为 `one-dev`，HEAD `4b4c0f56fa3e686dfb856923f8e90b0eae95b0e8`，实施开始时无未提交改动；本次没有使用新 SDK API或修改 SDK。

构建使用独立目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-dst-hint`，避免与其他 CLI/GUI 构建共用。命令为直接 `xcodebuild -workspace SunSmartLocal.xcworkspace -scheme '<品牌>' -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath '<上述目录>' -quiet CODE_SIGNING_ALLOWED=NO build`。不使用 Simulator、无真机安装、不 clean。

### 最终验证与交接

| 检查 | 结果 |
| --- | --- |
| DST 4 组 / Site Props 脚本 | 通过 |
| Create 完整脚本 | 失败于原有 Metadata 第 113 行；原始 HEAD 同样失败 |
| Create 其余 8 组独立继续执行 | 全部通过 |
| SunSmart / Lumineux / Archipelago / SylSmart / SLG Sync Plus / HSmart Debug generic iOS | 六个构建均 exit 0；各自 Xcode 构建记录 errors=0 |
| 六品牌实际 `.app` 产物 | 可执行文件存在；三个 DST 图标均进入 Assets.car，1x/2x/3x 像素尺寸正确；每种语言的 15 个新 Key 均存在 |
| 工程与 strings 语法、文件/资源归属、差异空白 | 通过 |

构建仍包含第三方弃用、Swift 兼容性和部分品牌既有重名资产等警告。部分构建输出含“command failed with exit code 0 but produced no further output”诊断，最终进程退出码、Xcode LogStoreManifest 的零错误记录及可执行产物均已交叉核对；未因此修改无关代码、清理缓存或重复构建。

最终复核覆盖共用表单的插入顺序、城市/国家/手动选择入口、弱引用与观察者释放、同 IANA 重订阅、缓存边界通知、过期标签、原值透传、隐藏内容的无障碍读取、资源归属；未发现本次范围内需继续修改的明确问题。未使用子代理，未提交或合并。

未验证：真实 API 返回与断网运行、UIKit 约束/滚动/触控/VoiceOver 真机体验，以及第 5 节的服务器/网关/固件承诺。未增加未来调度或 DST 开关。最短人工步骤仍为第 6 节；优先在 Create/Edit 各验证“支持→展开→另一支持时区自动收起→不支持隐藏”，再检查长 ISO 文本、中文和 Description 键盘状态。

交接：保持分支 `feat/daylight-saving-261024`、HEAD `7051230f74a2196843ab4db60f6d363827c51da0`；未提交差异为两个新 Swift 文件、一个新行为测试、共用表单接入、DST 脚本、两种本地化、三个图标 imageset、工程归属及本文档；后续追加调整见第 9 节。下一步由用户完成 UI/API 验收；城市元数据合并断言和外部文案承诺保持独立待办。

## 9. 用户追加调整：DST 后缀、白色背景与 Local time

本节覆盖初版中“两个 offset 完全不加后缀”的规则，其他展开/缓存/外部文案规则不变。

- `is_dst=false`：只在 Switches to 值后追加 ` (DST)`；`is_dst=true`：只在 Current offset 值后追加 ` (DST)`。复用现有 `site_time_zone_dst_suffix` 国际化 Key，只装饰 Presentation 文本，不改变 Snapshot、缓存、时间解析或同步参数；过期缓存按其原始 isDST 标记，保留“需要刷新”状态，不本地翻转。
- 按用户再次明确的范围：整体自定义 View（含标题区域）使用透明背景，仅灰色边框内的详情卡片使用白色背景；状态 badge 颜色不变。
- 正常 Local time 原本已通过 `effectiveOffset` 使用服务器 current_offset，但缺失/过期时会回退 catalogOffsetMinutes。本次移除 Local time 的静态目录回退：有效服务器/缓存 current_offset 才用于计算；无缓存、跨 nextSwitch、时间回拨或 IANA 不匹配时显示 `Local time: -- · Refresh required`（中文使用现有本地化）。同一次刷新使用相同 now 计算时间与 offset。Time Zone 选择行原有 offset 回退展示及校时有效性机制不变。
- `formattedLocalDate(at:)` 的业务调用方已核对，仅为 Create/Edit 共用表单；没有网关历史时间或其他页面使用方受到该方法变更影响。

验证：先观察到两个预期失败（DST 标记缺失、过期 Local time 仍回退静态值），再完成最小修复；`check_site_dst.sh` 4 组通过，覆盖两种 DST 状态、有效缓存、跨切换点、时钟回拨、无快照、错误 IANA 与 +05:45 分钟偏移。既有 UI contract 检查通过；其中关于时钟的源码拼写断言已由真实数值行为用例替代，页面生命周期检查保留。

本次没有更改依赖、品牌条件或资源归属，按纯共享逻辑规则只增加 SunSmart Debug generic iOS 代表构建；不机械重跑六品牌或上轮已证实的无关 Create 失败。界面白底与后缀的真实运行效果仍需用户验收。

追加构建结果：SunSmart Debug generic iOS exit 0，最新 Xcode 构建记录 errors=0、warnings=0；`git diff --check` 通过。未操作真机、未提交代码。

## 10. 2026-11-06 Next switch 展示换算方案（已确认实施）

### 10.1 结论与日期语义

推荐统一展示“下一次切换瞬间，按本快照 Current offset 表示的切换前钟表时间”，格式为 `yyyy-MM-dd hh:mm a`。它与 Current offset 一起说明旧钟表走到何时发生切换，Switches to 仍说明随后生效的 offset。切换瞬间本身不改变，也不由 App 重新推算下一次 DST 日期。

必须区分解析和展示：

1. 解析服务器 `next_switch` 时，保留 ISO 字符串自带的 offset，得到唯一的绝对时间。这个 offset 可以等于切换后的 offset，也可以是 UTC；不能要求它必须等于 Current offset 或 Switches to。
2. 展示该绝对时间时，使用同一个 Snapshot 的 `offsetMinutes` 创建固定偏移 TimeZone，表示切换前的钟表时间。不要仅替换字符串末尾的 offset，不要额外加减一小时。

用户示例的正确换算：

| 步骤 | 值 |
| --- | --- |
| 服务器 Next switch | `2027-04-30T01:00:00+03:00` |
| 同一绝对时间的 UTC 表示 | `2027-04-29T22:00:00Z` |
| 用 Current offset = UTC+09:00 展示 | **`2027-04-30 07:00 AM`** |

`+09:00 - +03:00 = 6 小时`，因此不会换算为 7 月 30 日。若 Current offset 是 `UTC+02:00`，同一个例子才会显示为 `2027-04-30 12:00 AM`。12 小时制午夜是 `12:00 AM`，中午是 `12:00 PM`，不存在 `00:00 AM`。

例如服务器用切换后的钟表表示某次春季切换：`03:00+02:00`，而 Current offset 是 `UTC+01:00`。解析后按 Current offset 显示 `02:00 AM`，表达“旧钟表到 02:00 时跳到 03:00”。秋季重复小时也用相同算法，无需单独分支。

依据：[RFC 3339 §4.2](https://www.rfc-editor.org/rfc/rfc3339#section-4.2) 规定以本地时间减去 offset 得到 UTC；字符串携带切换后 offset 并不代表服务器错误。该标准证明时间戳如何换算，不证明示例对应某个真实 IANA 的 DST 规则。

### 10.2 当前源码事实与相关路径

分析时间：2026-11-06 14:21（Asia/Singapore）。工作树 `feat-daylight-saving-261024`，分支 `feat/daylight-saving-261024`，HEAD `71dd7e0b`。开始时已有 `SunSmart.xcodeproj/project.pbxproj`、`SunSmart/en.lproj/Localizable.strings` 未提交修改，本轮未触碰。

| 环节 | 当前实现及本次影响 |
| --- | --- |
| Create / Edit | `SiteCreateViewController.swift` 内的 `SiteFormViewController.updateTimeZone()` 将选中 IANA 对应快照交给 Presentation；`SiteEditViewController` 继承共用表单 |
| Gateway | `GatewayViewController.updateGatewayDSTPresentation(at:)` 使用同一 Presentation；`WiFiGatewayViewController` 继承该入口，普通/4G 与 Wi-Fi 一并覆盖 |
| 响应与缓存 | `SiteTimeZoneService` → `SiteTimeZoneStore` → `SiteTimeZoneSnapshot`。Snapshot 已从原始 `next_switch` 解析 `nextSwitchDate`，支持小数秒；Codable 重载会重新解析并校验 |
| 当前问题位置 | `SiteDaylightSavingTimePresentation.update` 直接把 `snapshot.nextSwitch` 赋给 `Content.nextSwitch`；`SiteDaylightSavingTimeView.render` 只将 Content 设到 Label |
| 校时与失效边界 | `SiteTimeSetMessageFactory` 使用 `snapshot.nextSwitchDate` 生成未来切换目标；`isUsable` 在该绝对瞬间失效。展示改动不得改变这两个行为 |
| 当前测试 | `SiteDaylightSavingTimePresentationTests` 明确断言原始 ISO 字符串，包含 form、gateway、磁盘恢复路径；这些断言需随新需求更新，原值保留断言应放在 Snapshot/缓存层 |

现有共用 Presentation 足以完成需求，无需新增请求、观察者、独立缓存或持久状态。View 和三个页面宿主预计无需修改。

### 10.3 最小实施范围

1. 在 `SunSmart/Main/Site/Model/SiteDaylightSavingTimePresentation.swift` 内添加私有展示格式化方法，使用已解析的 `snapshot.nextSwitchDate` 与 `TimeZone(secondsFromGMT: snapshot.offsetMinutes * 60)`；`Content.nextSwitch` 改为格式化结果。继续保留 identifier 检查、显隐和展开规则。
2. 格式使用 Gregorian calendar、`en_US_POSIX`、`yyyy-MM-dd hh:mm a`，按本次要求固定两位月/日/小时及 AM/PM；AM/PM 由 formatter 生成，不拼接硬编码后缀。与现有 Local time 的固定英文 AM/PM 策略一致，三行标题继续使用已有中英国际化 Key。小数秒和秒只从显示中省略，不取整或改写 Date。
3. 不使用手机时区、静态时区目录或 `TimeZone(identifier:)` 格式化该行；IANA 在切换瞬间可能已采用新 offset，会改变本次“切换前钟表时间”的展示含义。
4. 不复用 `effectiveOffset(at: nextSwitchDate)` / `formattedLocalDate(at: nextSwitchDate)`：Snapshot 在切换点即失效，前者返回 nil，后者显示 `--`。这里直接使用同一快照的已校验 offset，计算已知切换点的展示值，不将其授权为该时刻可用的校时数据。
5. 不修改 `SiteTimeZoneSnapshot` 的解析、校验、原始字段、Codable、`isUsable`、请求/重试机制或 `SiteTimeSetMessageFactory`。保留 Current offset / Switches to 的 DST 后缀和状态规则。
6. 更新现有 `Tests/Site/SiteDaylightSavingTimePresentationTests.swift` 的行为用例与原始文本断言；沿用 `scripts/check_site_dst.sh`，不新增测试工程或依赖。

固定格式设置参考 [Apple QA1480](https://developer.apple.com/library/archive/qa/qa1480/_index.html)：固定格式需要明确 locale，避免系统日历和 12/24 小时偏好改变结果。本次选择固定格式是用户指定的展示需求；没有扩大为全 App 日期格式调整。

### 10.4 空值、失败和兼容性

- `next_switch` / `switches_to` 为合法 null：继续隐藏 DST 卡片，不生成虚构日期。
- 无缓存或首次请求失败：继续隐藏；非法响应沿用 Snapshot 校验，不回退到原始字符串或手机时区来掩盖错误。
- 有快照但刷新失败：继续按该快照的 Current offset 格式化其 Next switch。已过切换点或系统时间回拨时，保留原有 Refresh required 和缓存提示；不得把缓存时间宣称为最新的下一次切换。
- 刷新成功：三行从同一新 Snapshot 更新；下一次切换变为 null 时隐藏。换 IANA、旧请求晚到、取消选择和退出重进沿用现有身份与观察规则。
- 旧缓存重载：从原始 ISO 字符串恢复 `nextSwitchDate` 后按新格式展示，原始值和精度保持；没有迁移/回填或缓存版本变化。
- **数据库与 export JSON 无任何结构或字段语义变更**。Site.timezone、接口字段、缓存 CodingKeys/版本、导入导出、分享和同步协议均保持原契约；格式化文本仅属于非持久化 Content，不回写业务数据。
- 所有使用共享文件的品牌受益：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。没有新增资源、品牌条件或 SDK API；本次无 SDK、服务器或固件配套研发与发布依赖。
- 当前没有目标 Site 的真实 IANA、完整响应与服务端实现证据；不能仅凭 `+09:00` 与 `+03:00` 的差值判断真实 DST 规则是否正确。后续真实 API 验收需核对完整四字段和请求时间；若服务端绝对时间本身错误，由服务端负责人修正，App 展示换算不能修复错误计划。

### 10.5 验证计划与验收值

以下为换算夹具，刻意允许 identifier 与 offset 不一致，以证明展示服从服务器字段；它们不是对真实地区规则的断言。

| Current offset | 原始 Next switch | 预期展示 | 覆盖点 |
| --- | --- | --- | --- |
| `UTC+09:00` | `2027-04-30T01:00:00+03:00` | `2027-04-30 07:00 AM` | 用户示例 |
| `UTC+02:00` | `2027-04-30T01:00:00+03:00` | `2027-04-30 12:00 AM` | 午夜与 12 小时制 |
| `UTC+01:00` | `2027-03-28T03:00:00+02:00` | `2027-03-28 02:00 AM` | 向前切换 |
| `UTC-05:00` | `2027-11-07T01:00:00-06:00` | `2027-11-07 02:00 AM` | 向后切换 |
| `UTC+11:00` | `2027-04-04T01:30:00.123+10:30` | `2027-04-04 02:00 AM` | 半小时变化、小数秒 |
| `UTC-05:00` | `2027-01-01T02:00:00Z` | `2026-12-31 09:00 PM` | UTC 输入、跨日/月/年、PM |
| `UTC+05:45` | `2027-04-30T01:00:00Z` | `2027-04-30 06:45 AM` | 45 分钟偏移 |

实施后在已有行为测试内覆盖上述结果，并补同 offset、正向跨日、正午 `12:00 PM`。对 form 与 gateway 两种模式比较相同 Content；通过实际 Snapshot 解析与 Store/Codable 路径验证空值、失败、切换点前后、恢复、不同 IANA 晚到响应及重启重载。断言原始 ISO、`nextSwitchDate` 和有效性边界保持不变，避免测试只覆盖独立格式化函数。

执行 `bash scripts/check_site_dst.sh` 和 `git diff --check`。如实施范围保持仅共享 Presentation 与行为测试，一轮修改结束后按项目规则核对 local workspace / SDK 映射，再运行一次 SunSmart Debug generic iOS；不机械重跑六品牌或与此无关的校时传输回归。若实际需要改宿主、资源或依赖，依据新增影响补检查。

最短人工验收：

1. 同一时区分别进入 Create site、Edit site、普通/4G Gateway 和 Wi-Fi Gateway，核对 Next switch 数值一致、格式正确；Create/Edit 仍能展开，Gateway 仍只读。
2. 在窄屏、中英文、手机时区与 Site 不同以及系统 24 小时设置下核对显示和换行；日期不随手机时区改变。
3. 切换 IANA、取消后返回、退出重进；断网重进有缓存页面，核对旧值与 Refresh required；恢复网络后，三行切换到同一份最新响应。

分析阶段已完成：只读调用链核对；临时 Foundation 探针直接编译当时 Snapshot 与 Presentation，确认原先显示原始字符串；以上 7 个换算值全部符合预期，真实 Codable 往返保留原字符串与绝对瞬间，并确认 Snapshot 在切换点失效。临时文件已清理。

分析阶段未实施生产改动；用户随后明确“开始实施”，按本节执行。探针只验证本机 Foundation 数学换算及模型，不代表服务端/设备已验收。

### 10.6 实施与验证记录

用户授权：2026-11-06“开始实施”。分支与 HEAD 保持 `feat/daylight-saving-261024` / `71dd7e0b`。

实际修改仅为：

- `SunSmart/Main/Site/Model/SiteDaylightSavingTimePresentation.swift`：使用已解析的切换 Date 和快照固定 offset，生成 `yyyy-MM-dd hh:mm a`；保留原有状态、隐藏和展开逻辑。
- `Tests/Site/SiteDaylightSavingTimePresentationTests.swift`：将展示断言更新为新格式，补充 10 组日期行为、手机默认时区 UTC-10 / UTC+14、form / gateway 模式、切换点前后、原始时间戳与精度保留；在已有真实 Store / 磁盘缓存用例内检查失败、非法日期、恢复、不同 IANA 晚到及重启重载的显示结果。
- 本文档：记录已确认决定及交付证据。

未新增资源、持久字段或依赖，未修改页面宿主、Snapshot、Store、SDK 和校时工厂。既有工程文件及英文 strings 修改保留。

| 检查 | 结果及边界 |
| --- | --- |
| `bash scripts/check_site_dst.sh` | 4 组通过：Value、Snapshot、Store、Presentation；使用真实生产解析、Codable、异步 Store 与磁盘缓存，网络响应由夹具提供 |
| 日期与模式行为 | 10 组输入同时覆盖两种手机默认时区、form/gateway、有效与过期状态；用户示例输出 `2027-04-30 07:00 AM`。小数秒只省略显示，实际失效边界不取整 |
| 六 target 源文件归属 | 读取实际工程对象，各 target 的 Sources 都恰有一份共用 Presentation；无品牌条件差异，本轮采用 SunSmart 代表构建 |
| `git diff --check` | 通过 |
| SunSmart Debug generic iOS | `xcodebuild` exit 0；Xcode LogStoreManifest 记录 errors=0、warnings=119；SunSmart.app 可执行文件存在 |

SDK 映射已核对：`SunSmartLocal.xcworkspace` 引用 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；SDK HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，开始时工作树干净。本轮不写入 SDK，也未引入新 API。

最终核对：SDK HEAD 和干净状态保持不变；工程文件和英文 strings 的 SHA-256 与实施前一致，保留用户既有改动。构建输出的警告涉及未改动的 CryptoSwift / Moya / SDK / App 代码中的兼容性及弃用等问题；曾出现 `command failed with exit code 0 but produced no further output` 诊断，已用最终进程退出码、零错误构建记录及产物交叉核对，未因此改动无关代码、clean 或重复构建。

构建命令：

```bash
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-next-switch -quiet CODE_SIGNING_ALLOWED=NO build
```

人工待验收：第 10.5 节的三处完整页面路径（网关含普通/4G 与 Wi-Fi）、真实 API、窄屏与中英文、系统 24 小时设置和退出/断网重进体验。自动回归不能替代 UIKit / 真机验收；未安装或操作真机，未 commit / push。
