# Create Site 当前定位按钮方案与实施记录

日期：2026-11-02。已按用户确认方案完成 App 实施、行为回归及六个 Target 的 generic iOS Debug 构建；系统权限、真实定位与 UI 体验待人工验收。文末主线程权限检查优化已按确认方案实施，相关回归与 SunSmart generic iOS Debug 构建通过；本次优化未运行真机，也未重新构建其他品牌。

## 结论与需求边界

需求合理，可通过 App 内局部改动完成。复审发现原方案的大致位置与统一 60 秒有效期冲突，以及弹窗关闭、设置返回、重试回调归属和系统权限多品牌文案约束不足；本稿已修订。按钮只负责一次性获取手机当前位置并回填 Latitude / Longitude。无需 SDK、固件或服务器配套，也不涉及数据库迁移。

GPS 在本方案中指 Core Location 返回的系统当前位置，不限定卫星定位来源。只申请使用期间定位权限，不申请后台定位。Most accurate 是始终有背景的静态 Tag，不表示权限状态或本次测量已达到某个精度。

## 已确认的实现与设计依据

- `SunSmart/Main/Site/Controller/SiteCreateViewController.swift`：外层 UIButton 的事件只切换 isSelected；内部两个 UIButton 各自切换选中状态，未获取定位。改为一个可访问性按钮，内部图片、文字和 Tag 不单独处理点击，整个胶囊包括间隙都触发同一操作。保留外观，去掉选择态；可扩展触摸高度至至少 44pt，避免与输入框点击区域重叠。
- `SiteCreationDraft`：城市选择会覆盖经纬度、时区；切换国家仅清除城市来源的坐标。GPS 回填必须同时更新草稿与输入框，不能只改 UITextField。
- CREATE 从输入框收集值，经 `standardProperties()` 校验后交给 `SiteData.add`；已有 SiteStandardProperties、SQLite 保存/读取路径可承接坐标。定位成功本身不创建 Site、不触发保存或上传。
- `WiFiSSIDProvider` 唯一定位管理器用于申请权限并读取 SSID，没有坐标获取能力。直接复用会混合 Wi-Fi 回调与页面请求生命周期；本次保留其实现，为 Create Site 使用页面持有的轻量定位对象。系统权限是共享的，若 Wi-Fi 流程已取得权限，本页直接定位。
- 复用 `SRAlertView` 的展示/关闭机制，采用局部定制布局匹配设计，避免修改公共默认样式影响其他调用方。已有 `SRAlertAction.performsActionAfterDismiss` 可确保关闭完成后再申请系统权限。现有遮罩关闭不会通知页面，且带 actions 的普通弹窗未自动安装遮罩关闭手势；需在本次专用弹窗内明确处理关闭通知和遮罩交互，不能假设公共组件已覆盖。现有 `XWHUDManager.showSuccessTipHUD/showErrorTipHUD` 可直接复用，保持 Toast 图标约束。
- 当前系统权限用途仅描述读取 Wi-Fi 名称，且共享 InfoPlist.strings 写死 SunSmart，Lumineux 的字符串也与显示名 LumiSmart 不同。需补充自动填充 Site 坐标，并采用不含品牌名的用途句，更新英文、简中 InfoPlist.strings 与工程 fallback，避免其他 Target 系统弹窗正文出现错误品牌。
- 工程中该页面实际参与六个 target：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart。新增代码、图标、本地化和权限说明须核对这些 target 的归属。

Figma 已读取结构化设计和局部截图：

- [权限说明弹窗](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=753-10481)：实际弹窗节点 753:10676，紫色定位图标、标题、说明、Don't Allow / Allow。标题模板为 `Allow "App Name" to use your location?`；App Name 是动态占位，运行时按当前 Target 的实际 App 显示名填入，不固定为 SunSmart，也不原样显示 App Name。
- [拒绝后设置入口](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=753-12730)：实际弹窗节点 753:12925，底部整行 Location access denied 可点击并打开 App Settings；允许点遮罩关闭，避免强迫用户离开页面。
- [成功 Toast](https://www.figma.com/design/ffZ6mSpXLtHi3e7YdEmvMl/One-SunSmart?node-id=756-13850)：文案为 `Location detected.`，使用既有成功 Toast。

## 已确认的完整交互

| 当前条件/操作 | 行为 | 坐标处理 |
| --- | --- | --- |
| 已授权使用期间/始终允许 | 一次性请求位置 | 有效结果到达后同时更新两个输入框和草稿，再显示 Location detected. |
| 系统权限 notDetermined | 先显示 Figma 自定义说明弹窗 | 暂不改变 |
| 自定义弹窗 Don't Allow 或关闭 | 结束此次操作；不发系统权限请求，不弹拒绝 Toast | 保留原值；下次点击仍可显示说明弹窗 |
| 自定义弹窗 Allow | 弹系统授权框；允许一次或使用期间允许均继续定位 | 成功才更新 |
| 用户在系统授权框拒绝 | 显示 Location access denied.，不立即叠加设置弹窗 | 保留原值 |
| 点击时已是 denied | 显示 Figma 无权限弹窗；点底部行跳转本 App 设置 | 不先清空 |
| 从本次跳转的设置返回 | 同一创建页仍有效且已授权时，自动继续一次定位；仍拒绝则结束，不重复弹窗 | 成功才更新 |
| 系统定位总开关关闭 | 提示开启系统 Location Services；App 设置不是总开关入口，不无限请求权限 | 保留原值 |
| restricted（系统/管理限制） | 提示定位受限，允许继续手动输入；不宣称 App 设置一定能解除 | 保留原值 |
| 仅允许大致位置 | 接受系统返回的有效位置，不追加临时精确授权；Most accurate 仍为静态 Tag | 按普通成功回填；不保证测量精度 |
| 已授权但获取失败或超时 | 显示 Unable to get your location. Please try again.，恢复按钮可重试 | 保留原值 |

以上失败/限制提示均提供英文、简中本地化。两个弹窗仅是 App 自定义引导，不能替代系统权限框；判断可申请与否以系统当前授权状态为准，不用本地“曾申请”布尔值。这样可覆盖 Allow Once 过期和系统重置权限。

权限检查同时区分全局 Location Services 与本 App 授权状态。中途收到 denied 错误时重新检查两者，避免把总开关关闭误报为用户拒绝。定位管理器初始化或权限回调中仍为 notDetermined 时继续等待，不能当作拒绝；空闲时收到权限变化也不得自行触发定位或 Toast。

### 数据与竞争操作

1. 点击后收起键盘和国家/城市搜索；请求期间同一按钮显示轻量忙碌反馈、忽略重复点击，Tag 背景不变。其他字段和关闭入口仍可用。
2. 定位仅更新经纬度，不反向查询或修改国家、城市、时区、地址和邮编。用户需在 Site 实际位置使用该按钮；远程创建仍用城市或手工坐标。
3. GPS 结果视作一次显式用户输入，复用 `draft.editText` 的非城市来源语义；不增加持久化来源字段。切换国家不清除 GPS 坐标；之后选择不同城市沿用现有行为，用城市坐标覆盖。选择同一城市保持当前坐标。
4. 两个坐标作为一组更新。固定英文小数点，最多六位小数、去尾零，沿用城市坐标格式；合法的 0、负数和边界值允许，拒绝非有限/越界坐标。格式化位数不是精度保证。
5. 等待定位时用户开始手工编辑任一坐标、改变国家/城市、离开创建页、点击 CREATE 或切换账号/区域，应取消本次定位并使旧回调失效。手动输入与后续城市选择优先，晚到 GPS 不覆盖新意图。CREATE 使用当时有效的表单值，不因定位失败而被锁住。
6. 普通进入后台取消定位；从本次设置跳转返回的继续请求单独记录意图，只允许一次。系统权限框引起的短暂 inactive 不能当作退出取消；权限决定后仍需继续原操作。
7. 一次请求只产生一次完成结果和 Toast，关闭、取消不显示成功/失败 Toast。完成、失败、取消均停止定位与超时计时，恢复按钮。重新进入页面不自动发起定位。
8. 获取位置阶段以 15 秒为 App 等待上限（不包含用户阅读权限框和设置的时间），失败后可重试。校验坐标范围及有限值、水平精度为有限且非负；不设置统一的米级精度门槛。完整精度结果可采用 60 秒新鲜度限制；大致位置不沿用这一限制，接受当前有效请求由系统回调返回的位置，不能因为系统较慢的更新频率持续拒绝。两种模式均不直接使用 manager.location 的既有缓存替代本次请求，不跨页面复用旧成功结果。Apple 说明大致位置约每小时重新计算四次，故精度模式必须参与新鲜度判断；15 秒只是应用响应上限，不保证系统能在此时间内提供结果。

### 异步实施约束（复审补充）

- 用一个页面持有的轻量状态管理请求：空闲、自定义引导、等待系统权限、等待设置返回、获取位置。所有事件回到主线程串行处理；统一结束入口负责停止位置服务、移除计时、清理待返回标记、恢复按钮。仅获取位置阶段展示忙碌反馈；其他非空闲阶段也阻止重复点击。
- 用户点击 Allow 或设置入口后，复用关闭完成回调再执行下一步，执行前重新检查页面、账号/区域及请求身份。弹窗所有关闭路径（按钮、遮罩、被其他弹窗替换、页面退出）均须通知请求管理者且只通知一次；用户同意后正常关闭弹窗不能被误当作取消。
- 不把 GPS 取消逻辑直接塞进现有 `cancelLocationSearch()`：启动 GPS 本身就会调用它收起国家/城市搜索，必须避免本次操作取消自己。分别在坐标开始编辑、国家/城市实际改变、CREATE、关闭/离页等入口取消 GPS。
- 取消后重试必须隔离位置回调来源。单纯比较“当前 generation”不足以识别同一个 CLLocationManager 迟到的旧回调；每轮操作使用独立的 manager/delegate 会话身份，回调同时核验对象身份与请求标识。取消时停止并断开旧 delegate；旧计时器也必须绑定原请求身份。权限申请在系统层不能撤销，取消后的权限决定只改变系统状态，不再回填旧页面。
- 设置跳转前保存本次操作意图；打开失败需立即清理该意图并提示失败，不能等待不存在的返回。只有确实离开并回到当前页面时才消费一次返回意图。授权回调和 didBecomeActive 的不同到达顺序都必须只启动一次定位，不能两个入口各自 requestLocation。
- 定位授权 continuation 独立于 `resumeClock()` 的时区判断：页面无时区或时钟已运行都不能阻断定位继续。系统授权框导致 inactive 时保留请求，恢复 active 后继续；普通 didEnterBackground 取消，仅设置跳转保留返回意图。当前任务不持久化这一意图，App 被终止重启后不自动获取位置。
- 回填前再核验授权和页面有效性。结果与超时同时到达时只允许一方完成；取消后不排队弹 Toast。两坐标在同一主线程处理内成对写入草稿和控件，确认应用成功后才提示 Location detected.，即使数值与原值相同也视作本次定位成功。

## 最小实施范围

1. 调整 `SiteCreationLocationButton` 为单一 Button，绑定 requestCurrentLocation 入口；移除内部选项与互斥选择逻辑。
2. 增加 Create Site 专用轻量定位对象：权限分支、单次请求、超时、取消和请求标识。页面负责弹窗、设置跳转、前后台恢复、字段更新和 Toast。管理器与页面不共享 WiFiSSIDProvider 的 delegate。
3. 复用草稿修改入口；定位对象只返回合法经纬度，页面在主线程核验请求、页面、账号/区域与提交状态后成对应用。若抽取城市坐标格式化函数，限定为必要复用并回归所有调用方。
4. 基于现有弹窗实现两种内容状态，复用可匹配资源；缺失的定位权限图标从 Figma 获取并纳入共享资源。两个弹窗标题均使用本地化格式占位符，复用 `MacroDefinition.swift` 中的 `appName`（优先 CFBundleDisplayName，再 CFBundleName），不维护额外的 Target 名称映射。当前工程配置的显示名为 SunSmart、ACS by ALG（Archipelago）、SLG Sync Plus、SylSmart、LumiSmart（Lumineux）、H-Smart（HSmart）；以运行时 Bundle 的实际显示名为准。
5. 补齐普通文案和系统权限文案的英文/简中，以及六个 target 的代码、资源与配置归属。自定义弹窗通过 `appName` 格式化；系统用途文案不放未经 App 格式化的 `%@` 或字面量 App Name。用途句使用 `Your location is used to fill in site coordinates and display the connected Wi-Fi network name.` / `定位信息用于填写场所经纬度及显示当前连接的 Wi-Fi 网络名称。`，系统标题由系统展示 App 名称。不改 SDK、协议或云端接口。

## 设计规范差异（复审发现，未擅自改变已确认 UI）

Apple HIG 对系统权限弹窗前的自定义说明建议仅提供一个 Continue / Next 按钮，并明确不建议将该按钮称为 Allow。已确认 Figma 使用 Don't Allow / Allow，与该建议存在直接差异。技术上可以实现，但不能把它描述为符合 Apple 推荐的权限引导设计。

本次仍保留用户明确指定并确认的双按钮设计；若后续决定对齐平台建议，应修改该自定义说明层，而不改变系统拒绝、设置入口、坐标回填或 Toast 流程。这是设计取舍，不推断为必然审核失败，也不因此扩大实施范围。

## 验证和验收

- 扩展现有 `scripts/check_site_creation.sh` 相关行为测试：GPS 成对回填、数值格式/范围、国家切换保留非城市坐标、城市覆盖、保存参数。
- 对轻量请求控制逻辑注入权限/位置事件，覆盖允许、拒绝、取消、超时、重复点击、旧回调、设置返回和手动输入抢占；不以源码字符串匹配替代这些行为测试。重点时序：取消 A 后启动 B 再收到 A 的位置/错误/超时；初始化 notDetermined 回调；授权回调与恢复 active 两种顺序；弹窗遮罩关闭后重试；打开设置失败；无时区时从设置返回；普通后台取消和 App 重启；系统仅更改精度时不重复启动请求。
- 位置结果覆盖：合法的大致位置（包括超过 60 秒但属于本次系统返回的结果）、完整精度过旧结果、无效水平精度、零及负坐标、已有同值坐标、失败时两个原输入框均不变。验证实际生产请求控制逻辑，而不是仅测试一个未被页面使用的模型。
- 如有实际修改，共享资源/权限配置涉及跨品牌：开发阶段构建 SunSmart，稳定后覆盖实际六个受影响 target 的 generic iOS Debug 构建。先确认本地 workspace、scheme 和 SDK realpath；不使用 Simulator，不安装真机。
- 人工验收：点击图标、文字、Tag、空白区均可触发；首次 Don't Allow / Allow 与系统拒绝；已拒绝后设置授权返回；精确位置关闭、总开关关闭、失败重试；等待中编辑坐标或退出；成功后 CREATE 并重进确认坐标保存。核对六个 Target 的两个弹窗均显示实际 App Name，以及长名称/中英文布局、弹窗关闭、Toast 既有图标布局。
- 检查各品牌构建产物的 CFBundleDisplayName、英文/简中 InfoPlist.strings 与权限用途 fallback，而不只检查源码中的 appName；Debug/Release 配置文本均核对，未涉及条件编译差异时不额外做 Release 构建。VoiceOver 只识别一个按钮，Tag 无 selected trait，忙碌状态结束后可再次操作；至少 44pt 的触摸范围在容器 bounds 内有效，不侵入下方输入框。
- 已运行 `scripts/check_site_creation.sh`，六组 CLI 回归全部通过：Site 元数据、创建草稿、国家、时区、城市和新增定位请求生命周期。它们验证生产逻辑及隔离事件，不代表真实 Core Location 或 UIKit 运行验收。
- 六个 Target 均完成 generic iOS / Debug / CODE_SIGNING_ALLOWED=NO 构建：SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux、HSmart。最终样式调整后已补充受影响 Target 的增量构建。既有资源重名、弃用 API 等构建告警未纳入本次修改。
- 已逐一检查六个构建产物：App 显示名、中英文本地化占位及提示、系统定位用途说明、两个新图标的编译资源和尺寸均符合本次配置要求。`git diff --check`、工程及本地化 plist 语法检查通过。
- 未安装或运行真机；首次授权、Settings 返回、真实坐标精度和弹窗布局/VoiceOver 仍待人工验收。

## 平台依据

- [Apple requestWhenInUseAuthorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization())：仅 notDetermined 可请求；系统拒绝后不能再次弹系统授权；Allow Once 可过期，权限说明键必须存在。
- [Apple requestLocation](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation())：单次异步定位，可失败，可取消；系统可能返回低于期望精度的值。
- [Apple reducedAccuracy](https://developer.apple.com/documentation/corelocation/claccuracyauthorization/reducedaccuracy)：已授权也可能只允许较低精度。
- [Apple WWDC20: What's new in location](https://developer.apple.com/videos/play/wwdc2020/10660/)：大致位置更新频率较低，应用的超时判断须考虑 accuracyAuthorization。
- [Apple HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)：系统权限框之前的说明层推荐单一 Continue / Next 按钮。

已确认：接受大致位置；从本次设置返回后自动继续；保持当前城市选择对坐标的覆盖规则；App Name 按实际 Target 显示。复审补充已落实到实现及相关行为回归。


## 实施落点与人工验收

- `SiteCreateViewController.swift`：单一按钮、静态 Tag、44pt 最小触摸高度、忙碌反馈、坐标成对回填、取消入口及前后台衔接。
- `SiteCurrentLocationRequest.swift` / `SiteCurrentLocationProvider.swift`：页面独立请求生命周期与单次 Core Location 适配；每轮新建 provider，隔离迟到回调。权限授权仍由系统决定。
- `SiteLocationPermissionAlertView.swift`：两种 Figma 弹窗内容、动态 appName、关闭完成后的操作与统一取消通知；未修改公共 Toast 或其他弹窗默认样式。
- `SiteCreationDraft.applyCurrentLocation`：校验后成对更新为显式输入来源，保持已有国家/城市覆盖规则。新增英/简中文案和两张 Figma SVG，资源归属覆盖全部六个 Target。
- 工作分支 `feat/daylight-saving-261024`；2026-11-02 本次方案核对时，功能及暂存位置时效性修复已位于 HEAD `4802666e`，工作树在本次文档更新前干净。既有构建使用 `SunSmartLocal.xcworkspace`，SDK realpath 为约定 `nordic-sig-mesh-sdk-worktrees/one-dev`、revision `dbcf6f1`，SDK 无修改。CLI 构建目录为 `~/Library/Developer/Xcode/DerivedData/SunSmart-feat-daylight-saving-261024-cli`；后续实施构建前仍须核对实际依赖。

最短人工验收：

1. 创建 Site，在按钮文字、Tag、图标及胶囊内空白分别点击，确认均触发同一流程，Tag 背景始终存在。
2. 权限未决定时，先选 Don't Allow，确认原坐标不变且下次仍可申请；再选 Allow，在系统框分别验收允许和拒绝分支，拒绝只显示 Location access denied.。
3. 已拒绝时再次点击，点弹窗底部进入 App Settings；授权后返回原页应自动回填一次。仍未授权时返回，不重复弹窗。核对当前品牌 App Name。
4. 定位成功后两个坐标同时更新并显示 Location detected.；等待中手工编辑、退出或点击 CREATE，旧结果不得覆盖；关闭系统定位服务或失败时原值保留，按钮可重试。
5. 精确位置关闭时仍可接受有效的大致位置；GPS 回填后换国家保留坐标，选择不同城市改用城市坐标。创建后重进核对保存值，并检查中英文、长品牌名及 VoiceOver。

## 主线程权限检查优化方案与实施结果（2026-11-02）

### 结论与已证实范围

已保留主线程上的 CLLocationManager、请求状态机与 UI，只将必要的系统定位总开关查询异步执行；正常已授权路径不再查询该总开关。复用现有每轮独立 provider、请求 ID、取消入口和失败文案，在定位模块内部扩展访问状态，无需新增公共权限服务。

- 修复前，`SiteCurrentLocationProvider.servicesEnabled` 是直接调用 `CLLocationManager.locationServicesEnabled()` 的计算属性。`SiteCurrentLocationRequest.accessFailure()` 在主线程的启动、定位、授权变化、结果接收和恢复 active 等路径读取它。
- 已有生产状态机夹具在“已授权 → 初始化授权回调 → 位置结果”时序中观察到总开关读取 4 次、定位请求 1 次、完成回调 1 次。用户日志与这条调用链吻合；没有采集这次设备运行的逐条调用栈或耗时，不能据此声称已发生可见卡顿。
- Apple 说明创建 CLLocationManager 会触发初始授权回调；关闭系统定位总开关也会表现为 denied。`locationServicesEnabled()` 主要用于区分全局关闭与单个 App 被拒绝，并非每次定位的必需检查。
- `SiteCurrentLocationProviding` 的生产实现只有当前 provider，生产消费方只有创建 Site 页。WiFiSSIDProvider 仅负责 SSID，未调用这个总开关接口，也不共享本页 delegate；本次不改变它。六个品牌共享当前定位逻辑，无品牌专用分支。

平台依据：[总开关与 denied 的关系](https://developer.apple.com/documentation/corelocation/cllocationmanager/locationservicesenabled())、[初始与变更授权回调](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanagerdidchangeauthorization(_:))、[CLLocationManager 的 RunLoop 与 delegate 线程](https://developer.apple.com/documentation/corelocation/cllocationmanager)。

### 方案比较与选择

| 方案 | 影响 | 结论 |
| --- | --- | --- |
| 在每个 accessFailure 调用点分别增加异步查询 | 移除主线程阻塞，但保留重复查询，并把恢复、取消及乱序处理分散到多个入口 | 不选 |
| 将 servicesEnabled 改为长期缓存 Bool | 改动表面较小，但初始默认值及系统设置变化会导致误判 | 不选 |
| provider 集中解析访问状态，拒绝分支按需异步查询 | 已授权正常流程总开关查询为 0；保留两种拒绝原因及现有提示；并发处理集中在定位模块 | 推荐 |

### 必要改动与行为

1. provider 对外提供明确的访问状态，至少能区分“检查中”、系统 notDetermined、已授权、App 被拒绝、系统总开关关闭、受限制和不可用。用现有定位内部类型作必要扩展；检查中不能冒充 notDetermined，也不能用默认 true/false 替代。
2. 每轮仍创建独立 manager/provider，在主线程设置 delegate 并接收初始授权回调。等待期间请求必须处于非 idle 状态，阻止连续点击启动多轮请求；按钮复用现有忙碌反馈，不新增文案。初始授权已确定为 authorized 时直接进入定位；notDetermined 走已确认的自定义弹窗，restricted 保持限制提示。
3. 收到 denied 授权状态时，才在后台执行总开关查询：关闭则提示系统 Location Services，开启则按原流程处理 App 拒绝。收到 `CLError.denied` 时也要主动触发原因检查，即使授权属性尚未更新；不能只等待一个可能已到达或不会再到达的授权回调。
4. 后台仅执行总开关类方法；manager 初始化、授权申请、位置请求、状态修改和完成回调均留在主线程。查询完成后派发回主线程，读取当前授权状态并核对请求身份与授权版本，再发布访问状态。禁止用同步等待把后台查询结果取回主线程，也不把整个 manager 移入缺少 RunLoop 的普通后台队列。
5. 将 accessFailure 的同步总开关读取改为对已解析状态的判断。启动、授权决定、开始定位、定位结果、设置返回和暂存结果交付均使用同一规则；检查中应保存原流程意图/待处理结果，等状态明确后继续，不能提前成功或提前弹拒绝提示。
6. 接收位置及最终交付前仍在主线程读取当前 authorizationStatus；观察到拒绝或未完成的访问检查时先阻断成功交付。恢复 active、从本次设置返回、授权变化以及 denied 错误均重新评估访问状态。总开关结果只允许在当前操作的当前授权版本内复用，不跨操作或页面保存。

### 必须保持的时序与失败恢复

| 场景 | 预期行为 |
| --- | --- |
| 初始 denied，后台查询尚未返回 | 等待，既不弹 App Settings 引导，也不提前报系统总开关关闭 |
| 自定义 Allow 后系统拒绝 | 原请求显示拒绝提示；不立即追加 Settings 弹窗 |
| 已拒绝时再次点击 | 原有 Settings 引导仅在确认系统总开关开启后显示 |
| 本次 Settings 返回仍未授权 | 结束，不重复弹窗；已授权只恢复一次定位 |
| 系统权限框造成 inactive | 保留请求；状态可以更新，但弹窗、定位继续和结果交付等操作等 active 后再执行 |
| 定位结果与权限/服务查询竞争 | 保留先到的待处理结果，访问状态明确后决定交付；授权回调不得重新 requestLocation，也不得覆盖掉待处理结果 |
| 结果等待检查或 active 时超过 60 秒 | 继续在最终 deliver 校验完整精度位置，拒绝过期结果；大致位置例外保持 |
| 用户编辑、换国家/城市、CREATE、离页、账号/区域改变、普通后台 | 复用既有取消入口，所有待处理状态与后续回调失效，不产生 Toast 或回填 |
| 取消 A 后启动 B，A 的后台查询迟到 | 同时核对 operationID/provider 身份，忽略 A；不能改变 B 的按钮、提示或结果 |
| 同一次操作中授权版本变化，旧查询迟到 | 额外核对授权版本；旧版本返回 false 不能把新 authorized 状态改成 servicesDisabled |

查询去重仅适用于同一 provider、同一有效授权版本的在途查询。系统授权回调、恢复 active 的重新检查、denied 错误均建立新的观察版本，即使枚举值仍是 denied 也要使旧查询失效，避免漏掉总开关变化。新版本必须重新评估；已经开始的系统调用不假设能强制终止，取消/超时后只忽略其结果，避免通过全局串行等待阻断后续重试。

等待初始授权通知及拒绝原因检查已复用现有调度方式和 15 秒超时值；等待用户阅读自定义/系统权限框或停留 Settings 时不计时。开始定位仍保留原有 15 秒期限，定位期间发生的原因检查不得重新延长该期限。超时统一恢复 idle、保留输入值并允许重试；查询晚到不再恢复旧请求。15 秒是等待上限，不是已测得的系统调用耗时。定位结果已在 inactive 时通过检查并暂停计时后，若恢复 active 又需检查访问状态，会启动该次检查的等待上限；尚未完成的定位期限不被延长。

### 修改与验证边界

- 本次调整 `SiteCurrentLocationProvider.swift`、`SiteCurrentLocationRequest.swift`、现有 `SiteCurrentLocationRequestTests.swift`、页面对新增检查阶段的忙碌状态映射及原有回归脚本。只在现有定位协议增加必要异步状态/测试注入；不调整 UI 布局、国际化、项目资源、数据库、SDK、固件或服务器。
- 复用现有六组 Site 回归，新增行为测试：初始回调未到时连续点击；已授权正常流程总开关查询为 0、位置请求为 1；denied 与全局关闭的不同提示；denied 错误早于授权变化；同版本查询去重；旧操作/旧授权版本查询迟到；查询超时与重试；查询和位置结果乱序；Settings 返回和 inactive 恢复；59 秒位置再等 5 秒被拒绝、大致位置仍允许。
- 通过可控的异步服务查询结果驱动生产访问解析器和请求状态机，验证结果交付而非源码字符串；解析器位于现有请求模型文件，未增加公共权限服务。回归脚本同时编译生产 provider，并向其后台查询封装注入读取闭包，验证读取不在主线程、完成回到主线程；这没有执行真实系统总开关查询，不能证明真实 Core Location 已消除警告。
- 本次完成一次 SunSmart generic iOS Debug 构建；优化只有共享逻辑及忙碌状态映射，未重复其他品牌构建，未使用 Simulator 或自动操作设备。
- 最短人工验收：已授权时点击一次，确认只回填一次且不再出现该性能警告；分别在总开关关闭、App 拒绝、首次 Allow/拒绝及 Settings 授权返回时核对原提示；等待中退出/重试，旧查询不得回填。若需判断卡顿改善，用同一设备条件下的主线程 trace 比较，不能以警告消失替代耗时结论。

本次验证结果：

- `scripts/check_site_creation.sh` 六组回归通过；最后补充设置打开失败发生于 inactive、授权回调与 denied 错误先后到达的保护后，重新编译并运行定位组，全部通过。其余五组涉及的代码、配置和依赖未变化。
- 已授权正常流程的生产访问解析器总开关查询为 0、位置请求为 1；验证了同版本查询去重、旧操作/旧观察版本失效、检查超时与重试、后台查询/主线程完成，以及精确位置过期和大致位置例外。
- `SunSmartLocal.xcworkspace` / SunSmart / generic iOS / Debug / `CODE_SIGNING_ALLOWED=NO` 构建通过。已核对 SDK realpath 为 `nordic-sig-mesh-sdk-worktrees/one-dev`、revision `dbcf6f1`，SDK 工作树干净；未修改依赖、资源或 target 配置。
- `git diff --check` 通过。变更未提交；未安装或运行真机，真实授权弹窗、Settings 返回、性能警告消失及体验仍按上面的最短步骤人工验收。原 `[PJUIDebug]` 点击跟踪保持正常输出。
