# Space 降级提示 Cancel 后重复弹窗：分析与修复方案

日期：2026-11-03。分支：`feat/device-scene-261028`，HEAD：`3e305a4e`。调查开始时工作树无未提交改动；用户确认后已完成下述 App 修复，尚未提交。实施开始时已有其他任务的 `Assets-HSmart.xcassets` 与 `SunSmart.xcodeproj/project.pbxproj` 改动，本任务未修改这些文件。

## 实施结果

- 生产修改集中在 `SpaceViewController.swift`。云端与 Mesh 冲突共用待展示标记及当前弹窗弱引用；弹窗被替换后不会留下永久锁。动作校验弹窗身份，旧提示不能改变后续会话。
- Cancel 先同步停止当前 Space 跟踪并关闭自己的提示，再执行原导航返回。停止操作仍然幂等，且仅在 delegate 属于自身时解绑。
- 成员查询结果、排队的 Mesh 连接观察回调、Mesh 权限消息、超时和心跳结果均检查当前会话。Mesh 另检查网络 UUID、子网及 delegate 归属；接收处理统一回到主线程。
- 未结束权限选择时，另一路无冲突/失败响应不启动编辑占用或配置引导。导航窗口尚不可展示时保留冲突，进入可展示状态后再处理。
- 心跳权限失效的延迟返回和弹窗动作也检查页面是否仍属于原导航流程，避免旧动作影响重新进入的页面。
- Confirm 沿用现有临时禁用编辑权限与通知；正常 Visitor 心跳、网络失败策略及 Space 内子页面切换保留。没有修改 SDK、服务端、固件、协议或成员持久化格式。

### 已完成验证

| 检查 | 结果与边界 |
| --- | --- |
| `python3 scripts/check_space_presence_callbacks.py` | 26 个行为场景通过；直接执行提取的生产回调/清理/弹窗方法，以 UI、导航、定时器和网络替身控制时序 |
| `zsh scripts/check_site_space_mesh_context_ownership.sh` | 通过；这是现有源码契约检查，不代表 BLE 运行验收 |
| SunSmart Debug generic iOS | `SunSmartLocal.xcworkspace` 构建成功，`CODE_SIGNING_ALLOWED=NO`，未安装或运行 App |
| `git diff --check` 与新增文件空白检查 | 通过 |

26 个场景覆盖两路先后顺序、待决重复事件、Cancel 前后迟到响应、重入与旧动作、Confirm、展示延后及放弃进入、提示替换、无冲突/离线、Visitor/本地 Space、子页面跳转、心跳权限错误的正常与退出后路径、不同 Mesh 网络与 delegate 归属。

SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision 为 `dbcf6f1`，核对时无未提交差异。本次未新增 SDK API 依赖。CLI DerivedData 使用工作树固定目录 `SunSmart-feat-device-scene-261028-cli`。

首次 quiet 构建退出码为 0，但终端出现一条“command failed with exit code 0”矛盾诊断；检查构建活动日志为 `Build succeeded`，且本次控制器 object 与 App 可执行文件已更新。为消除此疑点，在相同代码、依赖和 DerivedData 下取消 quiet 做一次增量复核，明确得到 `BUILD SUCCEEDED`。未执行 clean 或清除缓存。构建仍有其他现存代码的捕获告警，本次未顺带修改。

待人工验收：Owner 保持进入 Space；Editor 进入后立即 Cancel，等待在途响应结束，返回页面不再出现降级提示；再进入仍提示，Confirm 后可只读控制。需要双手机及真实云端/BLE 验证，本次未自动操作真机。

## 结论

App 的权限冲突处理缺少当前 Space 会话的弹窗去重与取消失效保护。云端活跃成员查询、Mesh 权限回复均可调用同一个降级弹窗；Cancel 仅导航返回，没有立即终止会话。后到的冲突回调仍能创建挂在 Window 上的弹窗，因此可能在返回后的页面再次显示。

已通过实际生产弹窗方法的隔离执行验证这一缺陷。没有现场网络/BLE 时序日志，尚不能认定本次第一、第二个弹窗分别来自哪个来源；也未进行 UIKit 动画或双手机实测。

## 已确认的行为链

1. `SiteViewController.selectSpaceAction` 完成状态、密码和云数据检查后，`intoSpace` 创建 `SpaceViewController`。每次新建页面会将临时的 `disableEditorPermission` 重置为 false。
2. Space 在 `viewDidLoad` 启动云端 `spaceActiveMembers` 查询；连接 Mesh 后，KVO 回调发送用户权限查询并启动 5 秒超时。两个过程可以并行。
3. 云端响应中存在其他 Owner/Editor 时调用 `showTransferPermissionAlert`；Mesh 收到 Owner/Editor 权限回复时也调用它。
4. 弹窗入口只有 `!space.disableEditorPermission` 判断，没有“正在等待选择”“已经取消”“已经停止会话”或页面归属检查。`cloudPermissionValidation` 与 `meshPermissionValidation` 也没有组成跨来源互斥。
5. Cancel 只调用导航返回。停止在线跟踪要等到 `viewDidDisappear` 确认页面移出导航栈，存在退出动画窗口。即使停止方法已执行，云端响应和弹窗入口也不检查 `hasStoppedPresenceTracking`。
6. `SRAlertView.show` 直接将自身加入 Key Window，并替换已有同类弹窗；它不验证发起页面是否仍在当前流程。新弹窗不会因为旧 Space 页面退出而自动消失。

典型可解释时序：Mesh 冲突先显示提示 → 立即 Cancel、开始返回 → 尚未处理的云端查询返回冲突 → 旧 Space 对象仍可处理回调 → 第二个弹窗加入 Window。反向顺序也可能在退出清理前发生。快速 Cancel 更容易发生在另一个来源还未完成时；先后到达并非每次固定。

### 为什么已有机制未能阻止

- `stopUserAskTimer` 只停止超时计时器，不撤销已发出的 Mesh 查询，也不取消云端请求。
- `stopSpacePresenceTracking` 已能幂等停止心跳、权限查询计时器，并在 delegate 仍属于自身时解除 Mesh delegate；但已排队回调仍需消费端检查会话有效性。
- Mesh 连接 KVO 内排入主队列的代码也未检查停止状态，可能在清理后重新注册 delegate、发起查询。
- `SitesViewController` 的兜底只停止导航栈中残留的 Space；它没有替旧页面过滤云端回调，不能承担弹窗去重职责。
- Confirm 会设 `disableEditorPermission = true`，因此后续弹窗被现有 guard 拦截；Cancel 保持 false，不能达到同样效果。不能用 Cancel 时修改角色来伪装取消状态。
- `[weak self]` 只避免强持有，不表示用户已经取消；导航过渡或其他在途代码仍可能使旧页面存活。

导航边界：当前 Cancel 的代码目标是 `SiteViewController`（单个 Site），找不到时退一级；用户描述为返回 Sites。本次保留现有返回目标，修复返回后再次弹窗的问题，不据此改动页面路由。

## 已确认的修复方案

### 1. 在共享弹窗入口合并冲突事件

- 在当前 Space 页面维护本次权限选择的待决状态，创建弹窗前就置位，云端与 Mesh 统一经过该入口。
- 会话已停止、权限已失效、已经选择只读访问或该提示正在等待选择时，不再新建同一提示。
- 所有状态切换与 UI 操作在主线程串行执行；弹窗回调也检查仍属于当前有效会话，避免旧弹窗改变后续会话。
- 必要时保留自身弹窗引用，使离开时只清理本流程的提示；不通过全局隐藏所有弹窗解决，也不修改所有 `SRAlertView` 的通用行为。若提示被其他流程替换，需同步处理待决状态，避免留下无法继续的锁定状态。

### 2. Cancel 先终止会话，再导航返回

- Cancel 同步调用现有 `stopSpacePresenceTracking(reason: .leavingSpaceFlow)`，先使当前会话失效，再执行原导航返回；不等待动画完成才失效。
- 保留 `viewDidDisappear`、权限失效及 deinit 的幂等清理兜底。普通子页面 push、临时 modal 遮挡不能当作退出 Space。
- 不持久化“用户拒绝”，不修改 Owner/Editor 成员身份。重新主动进入时创建新会话，仍应正常检测冲突并提示。

### 3. 补齐同一权限/在线跟踪链的回调保护

- 活跃成员查询：请求开始和结果消费时检查会话。停止后无论成功冲突、成功无冲突还是失败，都不再弹窗、显示配置引导或恢复跟踪。
- Mesh 连接 KVO：在真正执行已排队的主线程闭包时重新检查，禁止退出后重新接管 delegate、发送查询或启动计时器。
- Mesh 权限接收、查询超时：拒绝已经停止会话的旧事件；保留当前 Space/网络归属校验，避免旧页面处理新 Space 的事件。
- 心跳：保留已有启动/发送保护，补结果消费保护，防止退出后的权限错误继续弹提示或导航。
- 不以取消 HTTP 请求代替结果检查；底层取消不能保证已排队回调不执行。优先复用现有停止标记，不引入全局权限管理器。
- 若增加可见性判断，不能简单在 `viewDidLoad` 请求回调中以 `view.window == nil` 丢弃有效冲突；进入动画前到达的结果应在当前会话首次可展示时处理。

### 4. 保留正常访问语义

Confirm 继续复用 `disableEditorPermission()` 和 `spacePermissionChangedNotificaitonName`，刷新设备、Group、Scene 等现有权限消费者；不改变成员身份、存储格式或云端接口。只读访问仍属于活跃会话，不能套用 Cancel 的“退出后忽略一切”处理。

无冲突、网络失败的现有进入策略保持；实际 Visitor、本地未上传 Space、正常页面内跳转仍应工作。本次不重新设计编辑占用协议或降级后的心跳角色策略。涉及相同共享控制器的品牌均受益；不需要固件、后端或 SDK 配套修改。

## 验证与验收

分析阶段的临时夹具从修复前源码提取 `showTransferPermissionAlert` 与 `disableEditorPermission`，以导航和弹窗替身执行，结果如下：

| 场景 | 当前结果 |
| --- | --- |
| 同一会话连续两个冲突事件、尚未选择 | 创建两个弹窗实例，缺少去重 |
| 首次弹窗 Cancel，模拟完成 presence stop，再收到冲突 | 再创建一个弹窗，复现失效保护缺失 |
| 首次弹窗 Confirm，再收到冲突 | 不再创建弹窗 |
| 新建 Space 页面再收到冲突 | 可以正常提示 |

夹具验证的是生产方法的决策行为，不是现场来源顺序或真实 UI；临时文件已随执行结束清理。没有找到现成覆盖本次双来源 Cancel 竞态的回归。历史构建与其他 Scene 回归不作为本问题验证结果。

已新增 `Tests/Space/SpacePresenceCallbackTests.swift` 与执行脚本 `scripts/check_space_presence_callbacks.py`，执行上述真实处理逻辑的轻量行为回归；生产方法及状态声明从控制器提取，仅将 Objective-C selector 语法适配为定时器替身的入口，不复制生产决策实现。

已核对本地 workspace/SDK 实际映射并完成上述验证。本次为共享控制器逻辑，无品牌差异编译路径，采用 SunSmart 代表构建，未重复其他品牌构建。

人工验收最短路径：Owner 保持在同一 Space → Editor 进入后立即 Cancel → 返回后等待超过 Mesh 5 秒探测窗口及在途网络响应完成，期间不再出现提示 → 再进入仍正常提示 → Confirm 后保留只读控制。联网且连接 Mesh 为主场景，补云端单独可用与 Mesh 单独可用；无 Owner 占用时 Editor 应正常进入。若需要日志，仅在 DEBUG 记录冲突来源、会话与选择/丢弃原因，不记录密码或密钥。

分析阶段未构建 App；确认实施后已完成构建及隔离回归。真实服务端/BLE 联调与最终 UI 体验仍待人工验收。

## 源码依据

- `SunSmart/Main/Space/Controller/SpaceViewController.swift`：初始化、`viewDidLoad`、`viewDidDisappear`、`addNotificaiton`、`checkTheSpaceMembersRequest`、`stopSpacePresenceTracking`、`heartbeatRequest`、`showTransferPermissionAlert`、Mesh 权限接收。
- `SunSmart/Common/View/SRAlertView.swift`：`show`、`dismiss`、`handleAction`。
- `SunSmart/Main/Site/Controller/SiteViewController.swift`：`selectSpaceAction`、`intoSpace`。
- `SunSmart/Main/Site/Controller/SitesViewController.swift`：`stopResidualSpacePresenceTracking`。
- `SunSmart/Common/Network/NetworkRequest.swift`：网络结果分发到主队列。
- `SunSmart/Common/Data/SpaceData.swift`：临时禁用编辑标记及各对象操作权限。
