# EL Controller 第 20 轮 Function Test 失败日志分析

日期：2026-10-14。初始范围：用户提供的 Xcode 日志、当前 App 与实际映射的 SDK 源码、隔离时序复现。用户随后选择方案 3（下文方案 C），已完成两处 App 生命周期修复；实施与验证结果见文末。SDK、固件和服务器未修改，未操作真机。

## 结论与证据等级

1. **日志已证实**：按所贴片段第一次 `actionButtonTapped` 开始计数，第 20 轮的启动请求（App network seq=151）发生 `error: cancelled`。设备随后返回 `45 07 00 0E`；后续状态查询返回 testing 状态 `0x0E`，表明不能将该 cancelled 理解为设备未收到启动命令。
2. **日志已证实**：该轮仍发送了设备状态 GET（seq=152，`45 01`）和测试结果 GET（seq=153，`45 03`），两者均收到设备应答；随后发送 Exit（seq=154）。因此“这一轮 App 完全没有下发获取指令”与完整日志不符。是否未在固件期望的时间窗口内获取，日志没有时间戳，不能判断。
3. **当前源码与隔离复现已证实**：等待 Start ACK 时调用 `startPageSession()`，会因新的 Device Status GET 取消旧启动请求的回调；App 将 nil 回调直接显示为 `Test Failed`。迟到 Start ACK 在通用消息入口被消费但不恢复轮询；随后收到 Device Status `0x0E` 才恢复 Awaiting 并重新安排 7 秒后的结果查询。
4. **现场触发的高置信推断**：异常附近恰有 NavigationViewController、DeviceLightViewController 的 `viewDidAppear` 跟踪记录，后续也多出页面初始化所使用的状态查询。页面重新显示触发 `viewWillAppear → startPageSession`，与上述竞争链吻合。但日志未记录 `viewWillAppear`、调用栈、会话编号或当时系统操作，尚不能断言是什么具体操作引起页面重新显示。
5. 当前源码没有第 20 次阈值或次数上限；这是请求与页面生命周期时序重叠的缺陷。隔离复现在第一次测试就能触发，不要求积累到第 20 次。

## 代码基线

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-timed-limited-261008`。
- 分支：`feat/timed-limited-261008`；HEAD：`b78463e9c034c05a244886e69ddfc8966f902acb`。
- 调查开始时 App 工作树干净。
- `SunSmartLocal.xcworkspace` 引用 `.local-sdk/nordic-sig-mesh-sdk`；符号链接实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`2598bd169417b894dcb11ba7cf6c63185d7c5a66`；工作树干净。
- 用户日志未附测试安装包的 App/SDK revision；源码级判断基于上述当前基线，不能据此证明现场安装包 revision 完全相同。

## 日志时间线

App 地址 `0x00C8`，EL Controller 地址 `0x00C9`（十进制 201）。两个方向的 Network SEQ 分别由发送方维护，不把它们当作同一个事务编号。

| 轮次 | App 发送 SEQ 与内容 | 设备回复 | 特征 |
| --- | --- | --- | --- |
| 19 | 146 状态 GET → 147 Start → 148 结果 GET → 149 Exit | 对应 142～145，均有回复 | 常规流程 |
| 20 | 150 状态 GET → 151 Start → 152 额外状态 GET → 153 结果 GET → 154 Exit | 对应 146～150，均有回复 | Start 等待被 cancelled，出现页面显示日志 |
| 21 | 155 状态 GET → 156 Start → 157 结果 GET → 158 Exit | 对应 151～154，均有回复 | 恢复常规流程 |

第 20 轮展开：

| 顺序 | 关键证据 | 可得结论 |
| --- | --- | --- |
| 1 | App seq=150：GET `F1780A / 45 01`；设备 seq=146：`45 01 00 03` | Start 前置检查得到 normal 状态 |
| 2 | App seq=151：SET `F0780A / 45 07`，有 Network PDU 与 `->` | 启动命令进入实际发送链 |
| 3 | 发送附近出现 `enter controller=NavigationViewController`、`enter controller=DeviceLightViewController` | tracer 记录的是 `viewDidAppear`，不是新的按钮点击，也不能单凭这行判定新建了控制器 |
| 4 | `消息发送失败 ... elControllerStartFunctionTest, error: cancelled` | 本地请求回调被取消；不是设备返回非零错误码 |
| 5 | 设备 seq=147：`45 07 00 0E` | ret=00，启动应答成功；取消后设备应答仍到达 App |
| 6 | App seq=152：GET `45 01`；设备 seq=148：`45 01 00 0E` | App 重新查询状态，设备处于 Function testing |
| 7 | App seq=153：GET `45 03`；设备 seq=149：`45 03 00 00 01` | 测试结果获取已发送，结果也已收到 |
| 8 | App seq=154：SET `45 08`；设备 seq=150：`45 08 00 03` | 退出测试请求及应答完成 |

普通 VIEW tap 日志没有 `control action=actionButtonTapped`，不能计为又启动了一轮测试。Awaiting 时按钮会禁用，点击探针仍可能记录底下的 UIView。

## 失败提示的代码链

### 1. 页面再次显示会另发状态查询

`SunSmart/Main/Device/Controller/DeviceLightViewController.swift`：

- `viewWillAppear` 第 128～137 行：设置消息 delegate、更新数据、调用 EL helper 的 `startPageSession()`。
- `viewWillDisappear` 第 144～147 行：调用 `stopPageSession()`。
- 第 827～861 行：仅对 CID `0x0A78` / PID `0x24C1` 绑定 Function Test、RX/TX 两张卡片和同一个 helper。

`SunSmart/Main/Device/View/ELControllerFunctionTestHelper.swift`：

- `startPageSession` 第 31～56 行：无论当前是否在等待 Start，都先置 `isActive=true`、重置 UI，再发送 Device Status GET。
- `stopPageSession` 第 59～64 行：只关闭活动状态和轮询、重置 UI；没有请求世代标识，不能区分重进前后的回调。
- Start 前状态检查正常时进入 `sendStartFunctionTest`，成功 ACK 后才建立结果轮询。

### 2. SDK 新查询会取消同设备的旧等待

SDK `MeshLib/MeshAPI.swift` 第 1291～1311 行，带 result 的 `sendMessage`：

1. 调用 `cancelNotifyCallback(responseOpCode, source)`。
2. 注册新的 `waitFor`。
3. 才将新请求加入发送队列。
4. 对等待异常统一调用 `result(nil)`，App 收不到 cancelled / timeout 的区别。

SDK `MeshLib/MeshNetwork/MeshNetworkManager+Create.swift` 第 149～171 行：

- 删除相同源地址、相同响应 opcode 的等待回调，调用 `.failure(AccessError.cancelled)`。
- 另按地址删除 `responseCallbacks[address]` 并调用 cancelled；该发送回调的删除甚至没有按 vendor 子命令区分。
- EL Device Status、Start、Result、RX/TX 等应答均使用 `0xF3780A`，当前等待匹配不检查 `45 01 / 45 07 / 45 03` 子命令。

SDK `MeshLib/Manager/MeshMessageManager.swift` 第 189～198 行将发送回调异常打印为日志中的“消息发送失败 ... cancelled”。这条日志可以在 PDU 已发送、设备已经执行后出现，不能解释为物理发送完全没有发生。

新查询是先取消/注册等待，再排队真正发送。因此取消日志出现在 seq=152 的 `send message` 日志之前，完全符合实现。

### 3. App 将通信取消显示成测试失败

helper 第 113～133 行：启动回调只要不是成功的 Start Status，就将 UI 改为 `.failed` 并返回，不建立结果轮询。`ELControllerFunctionTestView` 第 130 行附近将其映射为 `el_controller_function_test_failed`（English：`Test Failed`；简体中文：`测试失败`）。

`isActive` 只是一个布尔值。页面退出又重进后它重新变成 true，旧启动回调异步切回主线程时仍可通过 guard，从而把新页面状态写成失败；即便不先 stop，只重复 startPageSession，也能取消并显示失败。

### 4. 迟到 ACK 与恢复查询

- helper 的 `handleStatus` 第 186～188 行对 Start/Exit Status 直接返回，不依据迟到 Start ACK 恢复流程。
- 原有 Start waiter 已被删除；新 Device Status waiter 又只按地址和 opcode 匹配，可能先被迟到的 Start ACK 消费，之后其具体 code 校验失败。
- 页面通用 delegate 仍会独立收到真正的 Device Status `0x0E`，`applyDeviceStatus` 将 UI 改为 Awaiting，并安排结果轮询。
- 当前轮询为 7 秒一次、首次也等待 7 秒；GET 超时为 1.8 秒。日志无时间戳，不能计算此次恢复多花了多少时间，不能验证是否满足固件内部超时窗口。

## 关联观察与影响边界

1. **结果报文不是一次偶发的不同结果。** 所贴结果均为 `45 03 00 00 01`。当前 SDK 解析为 `ret=00`、`validity=00`（有效）、`faultBits=01`（lampFault=true）。App 显示 `Lamp Fault`，不会由此走 `.failed`。命令的 `isSuccessful=true` 也不等于 Function Test 通过。若现场应当完全无灯具故障，需另由固件团队核对这个 bit；不能将它归因于本次 cancelled。
2. **Local Vendor Model not bound to key 不是本次单次失败的证据。** 正常轮次同样出现；SDK 解码后仍进入全局接收通知，日志也确有 `message: ...`。绑定警告可能有独立影响，但不能由它解释这一轮的 cancelled，当前无需修改 AppKey 绑定。
3. **LightLightnessGet 没有对应本次异常。** 它出现在其他正常轮次，返回 opcode 为 `0x824E`；第 20 轮取消附近未出现。当前证据不支持将它认定为触发者。
4. **重复 Exit 是另一个已存在的一致性问题。** seq=97/98、135/136 各连续发送两次 `45 08`。同一 Result 会从请求 callback 与全局 delegate 两条路径进入 `handleFunctionTestResultStatus`，每次都调用 `exitFunctionTest()`；没有结果已消费保护。隔离复现产生两次 Exit 调用，真实发送队列的重复过滤和时序可使其只实际发出一次，也可能发两次。这不是第 20 轮的首要触发证据。用户后续明确收窄为下滑关闭操作，本轮不纳入此问题。
5. seq=95 的 Start 应答尾字节为 `03`，其余主要为 `0E`；该条 ret 仍为 `00`，当前 SDK 对 Start 尾部状态不解析，App 不据此报 failed，不能将它当作这次取消的原因。
6. 关联入口除页面自动查询和 Function Test 外，还有同 helper 的 RX/TX Check；两张卡片分别禁用自己的按钮，同设备 Vendor 等待通道仍可能竞争。这是关联风险；依用户后续收窄要求，本轮不扩展为通用请求串行化或 RX/TX 并发修复。
7. 直接 UI 影响范围是各品牌共用的 EL Controller 详情页；普通 Light 页面不使用这个 helper。SDK 的取消机制为共享行为，如选择改 SDK，需单独评估其他调用方，不能直接移除所有取消逻辑。

## 首次分析的综合修复建议（尚未实施，已由下方收窄方案替代本轮范围）

- 在现有 helper 内管理页面会话和测试阶段。重复出现时保留正在进行的测试；确实离开再回来时使旧回调失效，并有序恢复设备状态，避免初始查询抢占 Start 等待。
- 同设备的相关 Vendor 请求按业务阶段串行；协调自动状态查询、Function Test 和 RX/TX Check。仅增加一个 isActive 判断或固定延时不够。
- 启动通信结果不确定时，使用受控状态核对来恢复；设备实际 testing 时继续取结果，避免直接宣告设备测试失败。恢复不能依赖无关联的下一条消息，也不应盲目重发 Start。
- callback 和通用 delegate 应共享同一轮次/阶段校验；迟到 Start ACK、Device Status、Result 不应覆盖新轮状态。结果展示与 Exit 收尾每轮只执行一次。
- 优先完成 App 层修复；若需要 SDK 返回取消原因或支持更细的响应匹配，另行列明 SDK 共享影响、revision 和正式依赖发布要求。固件和服务器不属于本次实施范围。
- 诊断日志使用 DEBUG、单调时间、页面实例/会话/测试轮次、请求子命令、取消原因及 UI 状态变化；不打印密钥。这样可以核对“没有获取”究竟是没有调用、没有实际发出，还是发出时间晚于固件要求。

## 2026-10-14 用户补充后的收窄方案

用户推测：页面支持下滑关闭，点击按钮时可能轻微误滑；手势最终取消，肉眼不明显。用户要求本轮只解决该操作导致的问题，不扩大修复范围。该解释与日志吻合，尚未自动操作真机验证。

定向核对结果：`DeviceLightsViewController.collectionLongPressAction` 将详情页装入 `NavigationViewController` 后 present；这是模态容器的关闭手势。项目 Gateway 页面已经使用容器的 `isModalInPresentation` 临时保护操作，也已使用 transitionCoordinator 的取消判断来决定是否结束会话，可以沿用其 UIKit 用法，不需要修改公共导航组件。

| 方案 | 行为 | 修改范围与取舍 |
| --- | --- | --- |
| A：EL 页面固定禁止下滑关闭 | 通过返回按钮关闭；页面内容仍可正常滚动 | 最小。仅对当前 EL 页面所处模态容器生效，离开至其他页面时恢复原策略；用户失去该页下滑关闭入口 |
| B：Function Test 进行期间禁止下滑关闭 | 从点击 Start、前置检查到等待结果期间保护；结束或启动失败后恢复；返回按钮仍可主动关闭 | 较小。可复用现有测试状态通知更新容器策略，但需覆盖状态恢复及所有结束分支；仅保护测试时段 |
| C：保留下滑关闭，修正取消手势时的生命周期（推荐） | 下滑后取消时，继续原测试；真正关闭时才结束页面会话 | 小。仅修改 DeviceLightViewController 中 EL helper 的会话起止和 helper 重复启动保护，保留既有交互 |

方案 C 的必要配对改动：

1. EL helper 不在 `viewWillDisappear` 刚进入关闭动画时就 stop/reset。将这部分清理延后至确认页面消失的 `viewDidDisappear`；Controller 其他逻辑保持原有位置。
2. `startPageSession()` 对仍活动的页面会话重复调用直接返回，避免取消下滑后的 `viewWillAppear` 重置 UI、另发 Device Status GET。
3. 真正关闭后仍 stop，随后真正重新进入仍初始化并查询设备状态；离线/未绑定时原有 stop 路径保留。

这两点必须配套：仅延后 stop 而不防重复 start，仍会新增查询；仅防重复 start 而仍在 willDisappear stop，取消手势返回时仍被认为是新会话。

本轮明确不包含 SDK 等待匹配调整、通用请求队列、重复 Exit、Lamp Fault、RX/TX 并发修复或固件修改。方案 C 也不宣称解决所有跨会话迟到回调问题。

最小验收：正常一次 Function Test；Start 应答前及等待结果时分别轻微下滑后松手，UI 和原轮询连续且不新增页面初始化 GET；真正下滑关闭与返回按钮关闭仍结束会话；再次打开正确恢复；普通设备页面保持既有操作。实施后需相关隔离回归及一次 SunSmart generic iOS Debug 构建，真实手势体验由用户验收。

UIKit 依据：[交互转场取消会重新触发原页面 viewWillAppear](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator/notifywheninteractionchanges%28_%3A%29)、[isModalInPresentation 阻止交互式关闭](https://developer.apple.com/documentation/uikit/uiviewcontroller/ismodalinpresentation)。

## 初始分析阶段验证与后续验收

已执行隔离 Swift 时序复现，使用未修改的生产 helper、SDK `MeshAPI.sendMessage` 回调实现、`cancelNotifyCallback`、`notifyCallback` 及结果值模型；UI、Node 和实际网络传输/注册由夹具替代。保持真实 7 秒轮询间隔。

| 场景 | 观察结果 |
| --- | --- |
| 正常启动 → Start ACK → 等待 7 秒 → Result | 无 failed；发出结果 GET，展示 Lamp Fault |
| 等待 Start ACK 时重复 startPageSession → 迟到 ACK → Device Status 0x0E | 确定出现 cancelled 与一次 failed；迟到 Start ACK 单独不能恢复；0x0E 后恢复结果 GET |
| 等待 Start ACK 时 stopPageSession 后 startPageSession | 同样出现一次 failed；证明 isActive 不足以隔离旧会话回调 |
| Result 同时经 callback / delegate 交付 | 每个场景均产生两次 Exit 调用，确认收尾未幂等 |

执行退出码为 0，三个场景断言均通过。夹具仅保存在临时目录 `/var/folders/y1/phq8m2pd29jf7bwfcmq1j9j80000gn/T/el-function-test-analysis-w6ms2f5t/main.swift`；不作为正式回归工程。它证明当前代码可在指定交错下产生该行为，不能证明现场 UIKit 的具体触发操作或真实 BLE 时延。首次 Swift 执行受默认 ModuleCache 写权限限制，指定现有可写 ModuleCache 后完成；未清理缓存。

初始分析阶段没有修改 Swift 生产代码，因此当时未执行 App 构建、Simulator 或真机运行；后续实施的构建结果见文末。

首次分析提出的现场核对项（修复范围与验收已以上方收窄方案为准）：

1. 确认 Test Failed 出现时是否有页面遮挡/返回、系统面板或其他导致页面重新显示的操作，并取得对应 App/SDK revision。
2. 固件团队按地址与报文核对该轮 `45 07`、`45 01`、`45 03` 的收发时间；若“未获取”指超时窗口，提供期望窗口和 firmware 时间戳，与 App 对齐。无需修改固件来验证本分析。
3. 后续修复回归覆盖正常连续测试、Start 待应答时重复进入/退出再入、迟到 ACK、RX/TX 交错、结果重复交付，以及真正无响应时的结束/重试；再由用户完成真实设备验收。

## 方案 3 实施结果（2026-10-14）

用户已明确选择方案 3；本轮生产代码仅修改两处：

- `DeviceLightViewController`：EL helper 的 `stopPageSession()` 从 `viewWillDisappear` 移到 `viewDidDisappear`。其他消失处理仍保留原位置，取消下滑时不提前结束 EL 会话。
- `ELControllerFunctionTestHelper.startPageSession()`：已活动时直接返回。取消下滑重新触发 `viewWillAppear` 时，保留 UI、正在等待的 Mesh 回调和现有轮询，不另发初始化查询。

SDK、公共导航组件、协议、轮询间隔、结果判定和 RX/TX 流程未改。两处共享 App 逻辑没有品牌条件分支变化，选 SunSmart 做代表构建。未提交 Git。

### 自动化验证

沿用本任务临时 Swift 夹具，提取生产 helper 全部实现和 Controller 的三个生命周期方法进行行为回放；UIKit 容器、数据更新、Node 及网络传输由桩替代。使用原始 7 秒 Timer，未通过缩短间隔使测试通过。

同一组断言对修改前 HEAD 与修改后代码分别执行：

- 修改前：退出码 1，稳定复现 `Start cancelled → UI failed`，失败断言为取消下滑不得额外发送状态 GET。
- 修改后：退出码 0，输出 `ALL EL FUNCTION TEST LIFECYCLE REGRESSIONS PASSED`。

修改后验证覆盖：

1. 首次进入正常查询，normal 状态仍允许启动 Function Test。
2. Start ACK 待返回时取消下滑：UI 不重置，不额外查询，不取消 Mesh 等待。
3. 等待约 5 秒时取消下滑：原 7 秒到期仍发送结果 GET，轮询计时不重启。
4. Result GET 等待回包时取消下滑：原请求继续，结果可正常显示。
5. 已显示测试结果后取消下滑：结果不被清空。
6. 真正消失后停止轮询；页面关闭期间到达的状态不更新 UI 或重启轮询。
7. 真正重新进入时重新查询；返回 testing 状态后恢复结果轮询。

夹具文件：临时目录 `el-function-test-analysis-w6ms2f5t` 下的 `regression-before.swift`、`regression-after.swift`。这是生产逻辑隔离回放，不能代替 UIKit 实际手势和 BLE 运行验收。既有重复 Exit 不在本轮范围，夹具仍可观察到该行为。

### 构建与检查

- `git diff --check` 通过。
- `SunSmartLocal.xcworkspace`、`SunSmart` scheme、Debug、`-sdk iphoneos`、`-destination 'generic/platform=iOS'`、`CODE_SIGNING_ALLOWED=NO`：`BUILD SUCCEEDED`，退出码 0。
- 复用工作树专用 DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-timed-limited-261008`。
- 构建解析确认使用 `.local-sdk/nordic-sig-mesh-sdk`，SDK revision 仍为前述 `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，没有 SDK 改动。

### 待人工验收

在手机上进入 EL Controller 页面，点击 Start 后分别在启动应答阶段和等待结果阶段轻微下滑再松手：预期不出现 Test Failed 或 UI 重置，原测试继续。然后分别通过完整下滑和返回按钮关闭，再次打开确认状态能恢复；顺带确认普通设备详情页关闭正常。

本轮未安装或运行真机，未使用 Simulator；App 编译通过与隔离回放通过不代表实际手势体验已验收。
