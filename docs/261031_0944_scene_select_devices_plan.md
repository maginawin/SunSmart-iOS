# Select devices、Settings 已选设备及预览开发方案

日期：2026-10-31。状态：原 UI 方案已确认并实施；按用户补充采用指定提示语。原实施与验证记录见下文；新增实时控制与导航动画优化方案已确认实施，记录位于文末。

## 目标与确认项

Create Scene → CREATE → Settings → Devices → Select devices 后显示完整的设备选择页面，左上角关闭返回 Settings 的 Devices 分类。本次范围包含选择完成后的 Settings，以及预览进行中和结束后的状态，按以下 Figma 节点实现：

- [初始折叠态 721:6792](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=721-6792)
- [展开与选中态 721:6893](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=721-6893)
- [DONE 返回 Settings 721:5091](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=721-5091)
- [Applying preview 721:6606](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=721-6606)
- [预览结束 721:6468](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=721-6468)

本轮调整：原方案“Settings 已选列表保持原样”不再适用。需要同时对齐选择页和 Settings 的 Devices 非空界面，并把设备预览的 HUD/结果弹窗改为页内提示卡及底部 Toast；场景详情和 Groups UI 保持现状。

已确认的交互语义：关闭选择页保留本轮选择及参数到 Settings 的内存草稿；DONE 校验后也返回 Settings，不保存场景、不进入 Sync。新建且零设备时允许关闭返回空态，DONE 沿用现有至少选择一台设备的限制。关闭 Settings 本身仍使用原有放弃编辑确认。关闭保留草稿的建议已随其余方案确认。

## 已核实事实

- 分支 `feat/device-scene-261028`，分析时 HEAD `17ca15a1`；首次分析工作树干净，本轮仅存在本方案文档的未跟踪改动。
- `SceneAddViewController.openDraftEditor` 将创建草稿交给 `SceneSettingsViewController`；已有场景编辑也复用该控制器。
- `selectDevices()` 当前只切换 `devicesView.selecting`；标题、Groups/Devices、底部 Select devices/Preview 仍属于 Settings。`closeAction()` 不区分选择页，会弹出放弃整个草稿的确认。
- Settings 已创建关闭和 DONE 两个 `UIBarButtonItem`，使用 `close` 资源、现有文字按钮初始化方法及 `withoutSharedBackground()`。无需创建另一套按钮。
- `SceneDraftSelection` 负责选择、参数、过滤及旧成员恢复；持久化与发送在后续保存链路。当前 `doneAction()` 已区分选择完成与场景保存。
- `SceneDevicesSelectionView` 同时用于 Settings 和 `SceneViewController` 的只读详情，`SceneDeviceSettingsCell` 也通过它共享。不能全局替换外观造成详情联动。
- 当前搜索栏高 44、分类头高 60、列表横向铺满、默认展开且有常驻筛选提示；与设计不同。
- 当前候选过滤同时处理显示和新增资格，未选中的离线设备被排除；设计展开态展示灰色离线设备。必须区分显示资格和加入资格，不能为展示而放宽加入条件。
- 当前 Settings Devices 非空态仍显示搜索栏、简单提示文字和底部 Select devices/Preview，删除按钮在行左侧；补充设计要求顶部 Selected devices 工具栏、页内提示卡、右侧删除按钮。
- Figma `721:5120` 开发注释明确：“一旦更改了任何参数，都提示，点击预览后提示消失”。不能把预览提醒写成始终显示的静态文案。
- 当前预览入口为 `previewAction → startSend(saving: false) → SceneSaveCoordinator.send(.preview)`；发送前可能读取未知场景容量/定时拓扑。当前使用 HUD，结束后 `received` 展示逐台结果弹窗，没有预览状态卡或已预览版本记录。
- Coordinator 复用 `SyncExecutionSession` 发送参数，报告 successful/failed/offline，并具有 generation、权限、身份及目标快照校验。Preview 不提交场景、不执行正式 Scene Store、不发布云变更。无须另写发送器。
- 当前 Settings DONE 是预检后提交配置/pending，再进入 Sync device(s) 正式同步；以代码及 `docs/261030_1614_scene_done_sync_plan.md` 为准。Figma 提示中的“send all settings before saving”是旧时序描述，不能据此回退保存流程。

## 实施方式

### 1. 页面与导航复用

在现有 Settings 控制器内明确区分 Settings / Select devices 页面状态，复用同一控制器、同一草稿和现有左右导航按钮实例。选择页面完整占据内容区，不再只是原页面的列表切换。无需增加独立 UINavigationController、叠加 sheet 或另一套导航按钮。

- 进入：收起键盘，标题改为 Select devices；隐藏分段控件、Settings 空态和底部 Select devices/Preview；列表顶部接导航安全区、底部接键盘/底部安全区。
- 关闭：优先退出选择页，恢复 Settings 标题、Devices 分类、新设计的已选列表或零设备空态；不调用退出整个创建流程的方法，不弹出整个草稿的放弃确认。
- DONE：选择页只执行选择完成校验并返回；Settings 原有 DONE 保存/Sync 路径保留。
- 在页面边界结束参数弹层并使旧回调失效，保留现有 revision/lifecycle 保护；不能通过切换页面使旧参数回调写入错误状态。
- 搜索只属于当前展示状态：离开选择页清空筛选及输入框，避免回到 Settings 后已选设备被隐形过滤；不清空选择和参数。

选择同控制器方案的原因：能够直接复用用户指定的按钮实例，也保留现有参数弹层、Identify、通知刷新与草稿所有权。独立控制器会需要拆分这些依赖，对本次需求没有必要收益。

### 2. 选择页外观

以 Figma 的 375pt 设计宽度为基准，采用现有 UIKit/SnapKit 自适应约束；系统状态栏和安全区继续交由系统处理。

| 部位 | 选择页要求 |
| --- | --- |
| 导航 | Select devices 居中；原 Settings 关闭、DONE 按钮原样复用 |
| 工具栏 | 高约 52pt，左右 16pt；白色圆角搜索框高 36pt、圆角 10pt；右侧已选总数、全部展开/折叠 |
| 列表 | 工具栏下 12pt、左右 16pt；白色整体卡片、16pt 圆角、细分隔线；超出屏幕可滚动 |
| 分类头 | 标准单行名称时高约 56pt；选择框、名称及 x/y selected、参数设置、展开箭头 |
| 设备行 | 常规双行高约 52pt；选择框、设备图标、名称/参数摘要、设置及 Identify；浅色行背景 |
| 字体与图标 | 分类名 14pt，分类计数及设备文字 12pt；视觉图标槽 30pt；按设计区分主文字、辅助文字和禁用态 |
| 初始状态 | 首次进入全部折叠；展开/折叠只影响显示；空分类保留 0/0，不显示虚构设备 |

选择页不占用常驻筛选说明行；筛选全选的范围通过选中控件的可访问性提示保留。复用已有搜索字段工厂，在选择页局部配置 36pt 高度及 Figma 图标，不修改共享搜索组件。图标逐项核对现有资源，完全匹配者直接复用，缺失才增加必要资源；实施中已核对资源原始尺寸、编译产物及源码布局槽位；实际屏幕像素对照仍待人工验收。

设计两图的搜索提示分别为 Search devices 与 Search devices & group，建议统一已有本地化 Search devices & groups，与实际支持设备名和分类名搜索一致。设计样例中个别分类勾选与计数不一致，实施时显示真实计数，不硬编码样例。

### 3. 选择与状态连续性

- 复用 `SceneDraftSelection` 的身份去重、已选参数、取消后重选恢复，以及当前 Space/网络归属检查。
- 选择页展示当前作用域内具有相应场景能力的设备，包含不可新增的离线行；已选或已有场景成员继续保留，缺失设备保留原身份以供移除。无关类型不因展示调整进入列表。
- 新增仍要求在线、绑定完成且具备现有必要模型；离线新增控件禁用。已选离线成员仍可取消，已有成员撤销移除沿用原规则。
- 搜索后的分类全选/取消仅作用当前匹配的合格候选；隐藏的选择保留。分类计数采用当前筛选内显示设备，顶部总数采用整份草稿的已选设备。
- 分类批量参数仅作用该分类已选设备；单台参数仍沿用先选择再编辑规则，不把图中的设置图标解释为隐式选中。Identify 沿用独立动作，离线禁用，在线仍执行现有连接、权限和紧急状态检查。
- 离线行可保留已有期望参数，不能用摘要推断实时灯态。未选离线行按设计弱化，避免显示误导性默认参数。
- 状态/分组通知刷新不能重置用户的折叠状态、选择及参数；空搜索、无结果、空分类、全空列表均可关闭返回。
- 选择变化不写数据库、不发送场景配置；只有显式 Identify 复用原有设备命令。保存、同步、导入导出格式及 SDK 均不变。

### 4. DONE 返回后的 Settings（721:5091）

复用现有分段控件及导航栏，不新增导航按钮。Devices 有成员时显示以下结构：

- 顶部工具栏左侧为 `Selected devices (N)`，右侧依次为播放预览、铅笔编辑选择、全部展开/折叠；图标槽 30pt、间隔 8pt。铅笔进入同一个 Select devices 页面，已选成员和参数回显。
- 此状态不显示搜索框和底部 Select devices/Preview 文字按钮。零成员时继续显示原 Devices 空态及 Select devices 入口。
- 工具栏下方按预览状态显示提示卡，再显示已选分类树；只展示有已选成员的分类。首次选择完成返回时展开已选分类，再次往返保存 Settings 自己的展开状态，新出现分类默认展开；与选择页的折叠状态分别维护。
- 分类头：名称及 `N selected` 在左，右侧为设置、删除、展开；设备行左侧为设备图标及名称/参数，右侧依次设置、删除、Identify。已选列表不保留左侧复选框/删除占位。
- 列表横向 16pt，整体白色圆角 16pt，浅色设备行与分隔线沿设计；长列表滚动，提示卡高度随本地化文本自适应。
- 分类删除继续复用现有确认与批量草稿移除；单台删除继续移除该身份对应的草稿成员。移除全部成员后立即回到空态并清理预览提示。
- 离线名称/图标/Identify 按设计弱化，但不得以灰色图标推导禁止移除：项目既有规则允许离线成员单台及分类移除，此能力保留。预期参数仍是草稿数据，不代表设备实时状态。

### 5. 预览状态及反馈（721:6606 / 721:6468）

在控制器维护轻量的预览状态，视图只负责呈现；不持久化、不修改场景数据格式。状态与草稿 revision、预览运行标识及页面生命周期绑定。建议状态如下：

| 条件/事件 | UI 与后续行为 |
| --- | --- |
| 首次完成设备选择；实际成员或参数发生变化 | 显示黄色 Preview recommended 卡片；允许直接 DONE，不强制预览 |
| 点击播放并接受请求 | 黄色卡切换为淡紫色 Applying preview，显示旋转进度图标及发送说明；列表保留，不出现居中发送 HUD |
| 需要读取容量/拓扑 | 仍在同一进度卡显示准备/读取信息，成功后接续同一轮发送；不另开第二轮，也不在尚未发送时假称已应用 |
| 本轮所有目标成功且结果非空 | 移除状态卡，列表上移，底部显示绿色 `Preview applied. Check all physical devices.` Toast；自动消失，无需 OK |
| 部分失败或离线 | 显示本轮成功、失败、离线数量及检查/重试提示，不显示“全部应用成功”；保留非成功状态卡及明确的“查看详情”入口，按需复用现有逐台结果弹窗，避免删除目前可用的失败诊断 |
| 无可执行目标、全部离线、预检失败或发送异常 | 显示准确失败/未应用说明，恢复可操作状态；不生成绿色成功 Toast，不标记本轮已预览 |
| 参数或成员再次改变 | 使旧预览状态失效，移除旧 Toast，重新显示黄色提醒；取消后未改值、仅搜索/折叠/无修改往返不重新提示 |
| 退出、后台、权限/拓扑变化等中断 | 沿用现有取消机制，清除 applying；返回前台或继续编辑时可重新预览，迟到回调不能恢复成功 UI |

推荐卡：主题橙色 15% 背景、16pt 圆角、左右 16pt/上下 12pt 内边距；32pt 图标背景；标题 14pt medium，正文 12pt/20pt 行高。Applying 卡沿同一结构换为主题紫色 6% 背景与进度图标。列表与卡片间距 16pt；无卡片时不保留空白占位。

底部 Toast 优先直接复用 `ToastStatusView` 的 `.siteUpdate` 外观：已有 13pt 圆角、16pt 图标/30pt 图标槽、15pt light 字体、44pt 最小高度和最大 343pt 宽度，接近本设计。核对图标后决定是否仅加可选资源参数；如需要主动清除旧 Toast，最小扩展为返回可移除实例或可取消句柄，保留现有调用默认行为。现有调用方包括 Site、Gateway、Device、Group，不能全局改默认样式或持续时间。将 Toast 放在当前页面，随退出/新预览/真实草稿变化清理，避免叠加或旧成功提示覆盖新状态。

预览期间禁用 DONE、重复播放、编辑选择、成员/参数修改及 Identify，避免同时控制和草稿漂移；列表仍可查看。左上角保持原关闭/放弃确认入口：若中断预览后选择 KEEP EDITING，必须恢复可操作且可重试状态，不能残留 Applying。切后台取消和断连终态同样覆盖。仅状态图变化不能代替真实发送完成回调；不使用固定延时或 `SceneExecuteAnimationView` 的完成动画作为成功依据。

具体实现优先复用现有 `draftChanged`、`startSend`、`received`、`failed`、`suspend` 及 Coordinator 的失效机制。草稿 setters 已对内容相同的修改保留 revision，可据此避免空操作重新提示。离线恢复、身份/能力或成员来源变化时，基于已捕获目标快照使相关预览结果失效；显示分组、搜索和折叠不能当作实际参数变化。

### 6. 设计与当前规则的差异处理

1. **保存提示文案（已确认）**：采用用户指定的 `Apply this draft first to check that every device reaches the expected state. You need to use DONE to send all settings before saving.`，同步简体中文。正式保存实现继续沿用现有 DONE → 提交 → Sync，不恢复已移除的保存前试灯确认流程。
2. **预览成功条件**：设计结束截图仍包含灰色离线设备。截图不能证明它已经应用成功；使用 Coordinator 的真实结果判定。全成功使用设计绿色 Toast，存在离线/失败采用同一反馈风格的明确非成功说明。预览失败本身不成为新的保存阻断，后续 DONE 仍执行现有校验和正式同步。
3. **离线删除**：设计个别删除图标灰显与既有允许离线移除规则存在表面差异。本次保留移除能力，不能为了静态图禁用必要的清理入口。
4. **关闭选择页**：仍建议保留本轮草稿并返回 Settings；新增三图确定了 DONE 和预览 UI，但没有补充关闭是否回滚。此项已随整体方案确认。

除提示语已按用户补充替换外，上述处理均已确认；未从静态 Figma 推断失败、取消和旧数据的未给出交互。

## 改动范围与关联影响

预计涉及：`SceneSettingsViewController.swift` 的页面/预览状态与反馈；`SceneDevicesSelectionView.swift` 的选择/已选/详情展示区分、工具栏和状态卡；`SceneDeviceSettingsCell.swift` 的两种编辑布局；显示资格拆分按需小幅扩展 `SceneDraftSelection.swift`。搜索外观仅在 Scene 调用方局部配置，Toast 返回实例供清除；新增状态及错误文案同步补英文/简体中文，缺失图标才新增资源。优先保持 Coordinator 和发送链路不变。

选择页与 Settings Devices 非空态均按各自设计调整；只读场景详情保持现有展示。创建和已有设备场景编辑共用入口，得到相同进入/返回及预览反馈；已有设备场景初次进入建议提示检查预览，空成员不提示。Groups 预览继续原反馈方式，不因共用 `received` 而被自动切换为设备样式；模板与正式保存链路不扩展功能。

全部品牌共享相关源码。纯共享逻辑且无品牌编译差异时用 SunSmart 代表构建；若增加资源或修改 target 配置，核对 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的归属，并按实际跨品牌编译风险补充验证。不修改固件、服务器或 SDK。

## 验证与交付边界

1. 复用 `scripts/check_scene_configuration.py --suite selection`，调整其对实际入口方法的夹具提取，并补充有行为意义的进入/关闭/DONE 测试：关闭保留草稿、空选择可关闭但新建 DONE 被拒绝、选择 DONE 不进入保存。
2. 覆盖离线显示但不可新增、已有离线成员取消/重选、筛选批量操作不影响隐藏选择、清除筛选不丢参数、退出后的迟到参数回调无效。
3. 在现有 Scene 测试中补预览展示状态行为：推荐→准备/发送→成功；修改后重新推荐；空操作不重新推荐；部分失败/离线/空结果不成功；重复点击；取消、KEEP EDITING、后台/断连和迟到回调；旧 Toast 清除。覆盖回执成功不持久化场景，预览失败不新增 DONE 阻断。
4. 运行受影响的 selection、save/Coordinator 回归与 `Tests/Scene/SceneDoneSyncFlowTests.py`，验证选择 DONE 只返回，Settings DONE 仍提交并进入 Sync，Preview 仍仅发送参数，Groups 保持原链路。按实际改动挑选必要套件，不机械全量重复。
5. 检查两种设备页面约束、复用 cell 状态重置、键盘、长名称、中英文及小屏；核对只读详情和共享搜索/Toast 使用方。五张设计逐态核对。源码检查不作为 UI 实测。
6. 完成实施后核对实际 workspace/scheme/SDK realpath，运行一次 SunSmart Debug generic iOS 编译；使用该工作树固定 DerivedData，不运行 Simulator、不自动操作真机。
7. 人工最短验收：创建→Devices→选择设备→DONE；核对已选工具栏、黄色提醒、右侧设置/删除/Identify；播放后检查紫色进度卡、完成后卡片收起和 Toast；修改单台/批量参数后黄色提醒重现，铅笔无修改返回不重现。补测离线/失败/取消重试、选择页关闭及零成员，最后确认 Settings DONE 进入原 Sync 流程。预览是否真实应用及物理灯效果由用户验收。

## 实施与验证记录

已实施选择页/Settings Devices 两种完整展示、复用导航按钮的进入和返回、离线显示与选择资格分离，以及推荐/准备/发送/成功/未完成预览状态。使用用户指定英文提示语并同步简体中文；保存链路、Groups 反馈、只读场景详情未纳入 UI 重做。新增 11 个 Figma 矢量资源；预览 Toast 复用现有样式，仅让既有 show 方法可返回实例以便清理。共享搜索组件无最终改动。

已通过：

- selection 套件 28 项检查及 DeviceNameFilterSession 测试：含关闭返回、草稿/参数保留、迟到参数回调拒绝，以及离线显示但不可新增。
- SceneDoneSyncFlowTests：运行生产入口/反馈方法和真实预览状态，覆盖推荐→发送→完成、重复点击、草稿/目标变化、失败/离线/空结果、预检失败及迟到回调、取消重试、选择 DONE 与正式 DONE 分流、Groups 结果弹窗。
- save 套件：保存事务、离线/移除、恢复、直接 Sync、权限、metadata、删除生命周期及 Coordinator 预览/取消回归。
- SceneDetailSyncDisplayTests 6 项检查；中英文 strings 格式检查及差异空白检查。
- 最终代码的 SunSmart Debug generic iOS 编译通过，使用 SunSmartLocal.xcworkspace、工作树固定 `SunSmart-feat-device-scene-261028-cli` DerivedData；未签名、未安装设备。
- 核对五个品牌资源归属；Lumineux 的既有合并脚本实际运行成功，11 个新图标合并后内容一致。SunSmart 已编译资源目录包含所有 11 个矢量图标，核对原始尺寸、引用和布局槽位。
- Lumineux Debug generic iOS 构建通过，验证合并资源的实际编译；之后仅补充离线设备参数图标的透明度表达式，使用同一共享代码路径并由 SunSmart 最终增量构建验证。Archipelago、SLG Sync Plus、SylSmart 本轮核对资源归属，未运行完整品牌构建；合入前按项目规则补齐需要的品牌构建。

SDK：本地映射为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ccdf101`，已有 MeshMessageManager.swift 修改及 MeshGroupControlSession.swift/check_group_control_session.py 未跟踪文件。本次未改 SDK，构建使用其现状；未新增 SDK API 或正式依赖变更。

待验收：五张 Figma 对应的真实屏幕布局、字号/长文案/触摸，以及 BLE 预览和 Identify 的实际设备反馈。未运行 Simulator 或自动真机。隔离逻辑回归及编译不等同实际 UI/实灯验收。

## 追加优化：Devices 实时控制与导航动画（已确认实施）

### 已核实原因与复用边界

当前 Settings 和 Select devices 共用 `editDevices`。调光弹窗未传入 `SceneExecuteDataPickerView.liveControl`，Relay 的 ON/OFF 控件也没有接实时事件，所以仅更新草稿。分类和单台设置均只回传身份数组，不能根据数组长度判断是否实时发送：Group 分类下只选一台时，分类头弹窗仍然不发送，只有单台设备入口才允许实时单播。

Settings 的 Groups 分类已接入 OFF、亮度、色温事件，使用 `MeshGroupControlSession` 处理组播最新值、结束值及取消；滑条采样间隔为 0.2 秒。按本任务的 Devices 范围，该既有分类行为保持不变，保留草稿类型必须为 Groups 的权限条件，不向 Devices 的分类头弹窗扩展组播。该 SDK 会话只接受普通组地址，不能直接用于单播。

现有 `LightGroupControlCommandSender.setNode*` 虽然默认 UNACK，但内部进入 `MeshAPI` 普通队列，不能沿用组会话的取消与淘汰语义。本次单播建议用已有 `MeshNetworkManager.send(UnacknowledgedMeshMessage, to: Model, completion:)`，在 Scene 局部复用命令构造和正确 Model 选择，直接发送，不加 ACK 等待、应用层重试或通用队列。该接口解析 Model 所属 Element 单播地址和绑定 AppKey，不把设备 Primary 地址当作所有模型的目的地址。

当前 `showDeviceSelection` 只切布局和标题，没有 push/present；仅补视图动画虽然改动更少，但无法形成真实页面进入/返回。推荐系统 push/pop，并复用现有编辑控制器的选择页模式和参数处理，避免两套弹窗逻辑。

### 目标与命令

Settings 的 Devices 分类和 Select devices 使用同一套明确的弹窗目标描述，区分单台设备入口与仅编辑目标值的分类头入口（Group / Not in group），并携带待写入草稿的已选身份集合。用户最新约束：只有单台设备弹窗实时控制，每次有效操作只发送一条 UNACK 单播命令，禁止遍历设备发送。

| 点击入口 | 实时发送 | 草稿写入范围 |
| --- | --- | --- |
| Group 分类头设置 | 不发送任何实时命令，仅批量编辑场景目标值 | 当前筛选范围内该分类已选成员，沿用现有选择规则 |
| 单台设备设置 | 向该设备对应 Model 所属 Element UNACK 单播 | 该已选设备 |
| Not in group 分类头设置 | 不发送任何实时命令，仅批量编辑场景目标值；实时调节需进入单台设备弹窗 | 下方设备对应的场景目标值，沿用当前筛选范围内该分类已选成员的草稿规则 |

Group 和 Not in group 的分类弹窗均不接入实时发送，既不组播、广播，也不逐台单播。例如组内 A/B/C 只选择 A，分类头调节只改 A 的场景草稿，三台物理设备均不受控制；点击 A 的单台设置才实时控制 A。分类下仅有一台设备也遵循同样规则。离线或缺失身份继续允许保留/编辑期望参数，单台设备不满足控制条件时不发送。

仅单台设备弹窗发送以下命令：OFF 使用 `GenericOnOffSetUnacknowledged(false)`；亮度使用 `LightLightnessSetUnacknowledged`；色温使用 `LightCTLTemperatureSetUnacknowledged`，deltaUV 为 0。单台 Relay ON/OFF 切换立即发送对应 Generic OnOff UNACK，初始化回显不发送；分类头 Relay 弹窗只编辑目标值。调光器 OFF 再次点击恢复亮度的行为复用现有弹窗。

Group / Not in group 分类头弹窗保留现有批量目标值编辑的能力与范围规则，不再为组播适配 Groups 分类的限制；单台采用设备能力及范围。写入 Devices 内存草稿时仍逐台规范化，这只是本地数据处理，不产生遍历发送；不增加 Group 场景成员或改变场景类型。

### 实时交互与状态保护

- 只有单台设备弹窗实时控制，每次有效事件仅发送一条对应 UNACK 单播命令；不遍历成员/Elements，不附带其他参数命令，不组合 ON 加亮度等多条发送。Group / Not in group 分类弹窗始终为零条命令。
- 滑动中沿用 0.2 秒采样，每个采样只发送当前改变的参数；抬手仅提交必要的最终值，避免同一结束事件重复发送；加减按钮每次只发一条。OFF 取消仍待发送的滑条动作，避免旧亮度紧随 OFF 发出。复用现有弹窗结束/取消事件，不另写一套手势。
- 每次发送核对可见页面、当前 Space/网络身份、权限、连接、设备/Group 归属和紧急控制限制。开始正式 Preview、DONE、切分类、切弹窗、页面退出、后台、断连或权限变化时停止采样、使本次弹窗回调失效，并取消已有 Groups 会话。单设备使用不经 App 普通队列的即时 UNACK 发送，不保留可重放任务；这类已发送的非分段 UNACK 不支持通过 SDK 句柄撤回。已发出的命令不能撤回；取消不向设备补发旧值，也不取消其他页面的发送。
- 单播不等待设备 ACK，不因发送完成更新为“设备已达到期望状态”，不增加失败弹窗、自动重试或离线积压。必要 DEBUG 诊断不含密钥。传输繁忙或丢包由用户继续调节/正式 Preview 检查，不把 UNACK 简化为保证成功。
- 参数弹窗仍按原确认规则更新草稿；单台 Relay CANCEL 取消草稿写入，但不会还原已发生的实时灯态。分类头弹窗只编辑草稿，无设备控制；仅打开/关闭、搜索、折叠不发命令。
- 单台实时调节一旦被接受发送，使之前的设备 Preview 成功状态失效、清除旧 Toast；即使随后取消参数写入，也不能保留可能已过时的成功状态。分类头弹窗仅在实际修改草稿后使旧 Preview 失效，取消且未改值不失效。单纯无修改往返继续保留原状态。选择页通过轻量回调通知父页失效，不调用已隐藏父页的弹窗方法。
- 正式 Preview 和 Settings DONE 的发送/保存/Sync 链路保持原机制，实时控制不写数据库、不执行 Scene Store、不改变导入导出格式。

### 导航方案

Settings → Select devices 使用 `pushViewController(..., animated: true)`；左上角关闭、选择页 DONE 使用动画 pop 返回同一个 Settings 实例。两页共享同一份内存 `SceneDraftSelection`，保留已确认的“关闭也保留选择和参数”语义；选择页 DONE 仅做现有完成校验，Settings DONE 才进入保存。新建零设备允许关闭，但选择页 DONE 仍按原规则拦截。

在现有 `SceneSettingsViewController` 增加专用选择页模式与共享草稿初始化入口，复用 `SceneDevicesSelectionView`、参数弹窗和实时控制处理。导航按钮复用现有配置方法、资源及样式，每页持有自己的按钮目标，不复制新外观。核对项目 NavigationViewController 默认返回按钮覆盖行为，确保选择页仍显示关闭按钮。

每个可见控制器管理自己的参数弹窗和发送生命周期，不能让选择页回调隐藏的 Settings 来打开弹窗：父页的 `viewWillDisappear` 已会使其生命周期失效。进入和返回时终止旧交互并防重复 push；前后台恢复只激活当前顶层页面。Settings 折叠状态保留，选择页搜索/折叠独立；返回时刷新共享草稿并清理筛选，避免隐藏选择。沿用现有关闭入口，不附加新的侧滑返回交互。

### 范围与验证

主要修改 Settings 控制器和 Devices 视图的设置事件载荷；按需要局部扩展弹窗 Relay 事件或 Scene 专用发送辅助。只读 Scene 详情与模板弹窗不启用实时发送；已有 Groups 行为保持一致。共享 App 代码影响所有品牌，无固件/后端修改，也不计划新增 SDK 修改。已有 Group 会话仍依赖本地 SDK `ccdf101` 加现存未提交会话实现，正式 SDK 发布待办继续保留。

以下为本轮验证范围；实际执行结果见文末，不能引用前述 UI 构建结果作为本次优化通过：

1. 在现有 Scene 测试中覆盖两个页面的 Group/单台/Not in group 路由，尤其“Group 只选一台也不发送”和单台选择正确 Model 所属 Element 单播；断言单台每次有效操作仅一条对应命令、无成员/Element 遍历发送，Group / Not in group 的所有操作均零条命令且批量草稿值正确。验证三种 UNACK 消息、范围限制、Relay 初始化不发送、结束事件无重复、OFF 后无旧滑条尾值。通过 `SceneGroupLiveControlTests.py` 回归 Settings 的 Groups 分类既有组播机制未受影响。
2. 覆盖拖动结束、加减、取消、断连/后台/退出/权限或身份改变、迟到回调；确认无应用层重试积压，实时控制不会写 Scene Store 或冒充正式 Preview 成功。
3. 覆盖 push/返回共享选择和参数、零设备关闭/DONE、重复进入、隐藏父页不能接收控制、返回后可继续编辑/Preview/保存；验证取消弹窗但已实时发送时旧 Preview 状态失效。
4. 运行受影响的 selection、DONE/Preview、保存及 Groups 实时控制回归；一轮生产修改完成后运行 SunSmart Debug generic iOS 构建。共享逻辑无品牌差异时不机械重复全部品牌；新增资源/配置时按项目规则扩大检查。
5. 用户人工验收两个页面单台设备的 OFF、亮度/色温拖动和加减、Relay ON/OFF，以及 push/pop 动画和保留状态；用 A/B/C 示例验证分类头只更新目标值、不改变物理灯态，单台设置只控制对应设备。编译与隔离测试不能替代物理灯态及动画体验验收。

用户最新调整：Settings 的 Devices 分类与 Select devices 中，Group 和 Not in group 均仅批量修改下方设备的场景目标值，不发送命令；仅单台设备弹窗通过 UNACK 实时控制，每次有效操作只发一条对应命令，禁止遍历发送。Settings 的 Groups 分类保留既有行为。导航方案保持不变；用户已确认继续，实施记录见下文。


### 本轮实施与验证记录（2026-10-31）

已按最终确认范围实施：

- 引入明确的分类/单台入口类型。Group 和 Not in group 分类头只批量编辑草稿，单成员分类也不启用发送；单台参数弹窗启用 UNACK，直接发送到对应 Model 所属 Element。不使用逐台发送循环、ACK 等待、App 普通队列或应用层重试。单台 Relay ON/OFF 接入同一生命周期保护。
- 滑条沿用 0.2 秒采样，每个有效事件最多一条对应命令；重复最终采样不重复发送。离线、身份替换、权限/紧急限制、后台、隐藏页面、旧草稿或旧弹窗回调不发送。单台实际发起控制会清除自己和父 Settings 的旧预览成功状态；分类仅在草稿实际变化时失效。
- Select devices 使用现有编辑控制器的专用模式，通过系统 push/pop 动画进入/返回，复用导航配置并共享内存草稿。关闭保留本轮选择/参数，DONE 沿用完成校验且不保存。过滤在返回时清理，两页折叠状态独立，隐藏父页不再被前台通知激活。
- 补充回归复现并修复：色温滑条被亮度加减接管后，关闭弹窗可能补发已取消的色温尾值。清理待发送的最终值标记，同时保留正常关闭活动手势时提交最终值。此修复位于共享 picker，对现有 Groups 使用方一并回归，不改变其组播机制。
- 没有新增资源、本地化文案、工程配置或 SDK 修改。SDK 来源与前述一致。工作树执行期间出现的 `Tests/Site/SiteUpdateToastUIContractTests.swift` 外部修改未触碰。

自动验证：

- selection 套件 35 项及 DeviceNameFilterSession 测试通过，覆盖共享草稿 push/pop、关闭/选择 DONE、新建空选择、筛选清理、迟到参数回调和分类/单台入口区分。
- `SceneDeviceLiveControlTests.py` 46 项通过：执行生产单播处理、目标路由和 picker 事件逻辑，验证命令数/模型 Element、去重、能力限制、错误不重试、旧生命周期/身份/权限阻断，以及 OFF/加减接管后的尾值清理和正常关闭的最终值提交。
- `SceneGroupLiveControlTests.py` 22 项通过；`SceneDoneSyncFlowTests.py` 通过；save 套件全部 7 组通过。前两套分别回归原 Groups 实时组播，以及选择完成与正式 Preview/DONE/Sync 的分流。
- 最终 SunSmart Debug generic iOS 编译通过（10:55:46），包含共享 picker 尾值修复；使用 SunSmartLocal.xcworkspace 和本工作树固定 DerivedData，CODE_SIGNING_ALLOWED=NO。差异空白检查通过。

待用户人工验收：在 Settings Devices 和 Select devices 分别操作 Group / Not in group，确认只变目标值、物理灯不动；打开单台设备弹窗操作 OFF、亮度/色温滑条及加减、Relay ON/OFF，确认只控制当前设备；检查 push/pop 体验、关闭/DONE 保留选择，返回后正常预览和保存。未运行 Simulator、未安装或自动运行真机；UNACK 发送和编译通过不等同设备已达到目标状态。
