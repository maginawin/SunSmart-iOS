# Create Scene — Settings Groups 实时控制分析与开发方案

日期：2026-10-30。状态：已按用户确认完成 App 与客户端 SDK 实施；自动化验证及构建结果见文末，实灯待人工验收。

## 结论与范围

需求合理：设置组场景时即时试灯，有助于选择亮度和色温。建议采用 200ms 最新值采样、松手优先提交最终值、OFF 接管旧控制。200ms 是本次建议的初始参数，真实顺滑度和组内一致性仍需实灯验证。

用户最新确认：本次 Groups 弹窗 OFF 按钮在关灯与最大允许亮度之间切换；关灯后再次点击恢复该组允许的最大亮度（受 highEndTrim 限制），同步切换按钮状态。亮度、色温的加减按钮每次点击也提交组播控制。控制失败不弹提示，用户观察实灯判断结果。

本次启用 Create Scene → Settings → Groups，以及已有 Scene → Settings 中真实 Group 的参数弹窗；两个入口显式开启同一个实时组控能力。Devices 单台/批量参数弹窗、Templates 参数弹窗维持原行为，即使设备按 Group 分类显示，也不向整个组发送控制。共享 Picker 仍默认不启用实时回调，仅真实 Group 编辑入口传入组播回调。

实时控制不等于保存场景：仍由遮罩关闭提交弹窗值至草稿，DONE 沿用发送、确认、持久化和正式同步流程。取消编辑不会自动恢复已经改变的实灯状态。

## 当前代码已证实的事实

| 环节 | 当前行为与影响 |
| --- | --- |
| `SceneSettingsViewController.editGroup` | 读取草稿/来源组参数，按组亮度上限及有效色温范围显示；弹窗结束时写草稿，没有即时组控。 |
| `SceneExecuteDataPickerView` | 普通 valueChanged 只刷新标签；OFF 在 0 与最大亮度之间切换；取消/关闭会取消两个滑条交互。OFF 当前只取消亮度滑条，需要在实时模式下接管两个滑条。 |
| `DeviceSliderFunctionView` | 已开启节流，向外提供 `(value, ended)` 回调；加减按钮也通过 ended=true 回调，可复用。 |
| `CustomDeviceSlider` | 默认 300ms；定时读取最新 pending 值且跳过未变化值；结束先清除定时器和 pending，再回调最终用户输入；取消默认不提交最终值。无需另建一套滑条采样定时器。 |
| `LightGroupControlCommandSender` | 已有组 OnOff、Lightness、CTL Temperature 的无 ACK 组播构造和发送方式。 |
| SDK `MeshAPI.sendMessage` → `MeshMessageManager` | 还有一层共享 FIFO，每 200ms 出队一个消息。新命令只替换同目标地址、同 opcode 的一个旧项；OFF 与亮度 opcode 不同，不能互相清理。 |
| SDK busy 重试 | 失败回调可把原 messageHandle 插回队头；没有弹窗所有权或代次检查。源码存在旧请求在被新值替代后重新入队的路径，是否现场发生尚未实测。 |
| SDK 取消接口 | 普通队列没有公开的会话级定向清理。`cancelAll` 会影响其他任务；底层 MessageHandle 取消也不能直接当成弹窗独占取消，SDK 注释明确存在按目的地址共享清理的边界。 |
| 保存/预览协调器 | 使用 `SyncExecutionSession` 与 `MeshProxyMessageCommand`，负责发送结果与保存流程；不适合拿全局批次停止代替实时滑条定向取消。 |

当前调用链：创建入口 → Settings.editGroup → Picker → DeviceSliderFunctionView → CustomDeviceSlider；拟新增实时事件从 Picker 返回 Settings，经组控制发送器进入 SDK 所有权明确的队列。关闭回调仍走 SceneDraftSelection，DONE 仍走 SceneSaveCoordinator/SceneConfigurationStore。

## 建议行为契约

| 操作 | 实时控制与清理 |
| --- | --- |
| 打开弹窗 | 只回显，不自动向灯发送初始值。 |
| 持续拖动亮度/色温 | 仅该弹窗的滑条设为 0.2s；每个采样周期最多提交一个最新有效值。没有变化则不重复发送，保留即时 UI 更新。 |
| 手指静止但仍按住 | 不重复发送相同值；200ms 是采样上限频率，不是持续刷包。 |
| 松手 | 停采样、丢弃本轮同属性未发旧值和旧重试资格，再提交一次 end 值；即使与最近采样相同也保留此最终提交；不再追加 100ms/200ms 补发。短于 200ms 的手势只提交最终值。 |
| OFF | 取消两个滑条的旧手势、定时器及本弹窗此前的待发实时控制，建立新的控制代次，当前开启时向组提交一次 `GenericOnOffSetUnacknowledged(false)`；当前关闭时取消旧实时会话，并提交一次最大允许亮度的 `LightLightnessSetUnacknowledged`，更新亮度标签及按钮状态。迟到的旧 end/busy 回调不能覆盖本次切换。 |
| 亮度 | 向当前组地址发 `LightLightnessSetUnacknowledged`，复用 Node 百分比换算及组 highEndTrim 限制。0 表示亮度为 0；大于 0 按现有组调光方式控制，不额外每次附加 ON。 |
| 色温 | 向当前组地址发 `LightCTLTemperatureSetUnacknowledged`，单位 K，deltaUV=0，复用有效范围裁剪。不因调色温自动发 ON/亮度；OFF 后只调色温不主动开灯。 |
| 加减/辅助功能调节 | 作为一次离散最终输入，清理同属性旧待发值并提交一次；取消被接管的旧滑条手势。 |
| 正常点遮罩关闭 | 先取消未结束手势，取当前值提交草稿；对尚未最终提交的用户改动完成一次最终控制。已提交的 end 值不重复发送。只允许最新已确认最终项短暂完成，完成后释放会话；禁止周期任务继续存在。 |
| cancel、页面退出、切组、切换场景类型、进入后台 | 失效实时会话并清除其未发送内容，不补发最终值，不在回到前台/重连后回放旧拖动。 |
| DONE/正式预览启动 | 先终止实时会话，屏蔽其迟到回调，再进入既有协调器，避免试灯旧值与保存前发送交错。 |

“全部清除”的建议精确定义：清除本次控制所替代的、仍由 App/SDK 持有且未交给传输层的旧命令。松手替代同一属性的历史值；OFF 替代本弹窗全部旧实时控制。不同组、其他页面、配置、同步、Scene Store 均不得清理。亮度和色温快速切换时，另一个属性已经确认但尚未发出的最新值仍应保留，避免调色温把刚选定的亮度吞掉；多指交互用属性/手势代次隔离。

“只发最后一次”指一次最终逻辑命令提交。采样命令可能已经发出，已交付 BLE/传输层的报文无法撤回；SDK/网络层自身的重复传输也不等于 App 再次提交。不能承诺清空所有空口报文，或无 ACK 组播保证每台灯收到。实际发送也会受 SDK 共享队列负载影响，不保证精确每 200ms 上空口。

## 权限、失败与数据边界

- 实时发送前核对编辑权限、当前 Space/网络、Group 对象仍有效、页面会话仍有效及 Mesh 连接；复用 SceneConfigurationStore 的访问检查和 Group 紧急控制限制。状态改变后取消会话，队列最终交付前也必须检查有效性，防止排队期间权限/网络已经改变。
- 紧急限制按既有 Group 判断整体拦截；空组仍可配置，离线设备仍可保留草稿。连接不可用时可继续修改草稿，但不积压待重连命令；按用户最新要求，实时控制失败或被拦截不弹提示，也不新增 `scene_live_control_failed` 文案。
- 仅对当前最新、仍有效命令允许有界 busy 重试；end、OFF、退出后，旧失败回调不得重入队。连接恢复后只响应新用户操作。
- 试灯不调用 Scene Store、不持久化同步成功、不改正式 Scene 参数；卡片继续显示期望参数。避免把试灯本地赋值当作实灯确认；既有状态回读可继续工作。
- 不改变历史场景 JSON、导入导出、云端格式或场景号分配；不需要历史数据迁移、固件或服务器配套。本方案仅 App 与客户端 SDK。

## 实现选择与最小完整改动

1. **复用滑条和消息构造，给 Picker 增加可选实时事件/结束事件及 OFF 策略。** 默认关闭实时能力，现有调用不受影响；创建及已有场景的 Groups 显式启用 200ms、OFF/最大亮度切换、结束与接管处理。UI 值更新与实时发送分离，避免初始化、回显、关闭重复触发命令。
2. **Settings 持有一次弹窗实时会话。** 绑定网络身份、Group、生命周期、属性及手势代次；复用访问检查、组能力和换算。管理正常关闭的最终值交付、强制取消、切后台/权限变化以及进入正式保存前的失效处理。薄的会话所有者只解决该场景，不另建通用控制框架。
3. **给现有 SDK 普通队列增加可选所有权与定向替代/取消能力。** 由 SDK 内部串行化入队、取出交付、取消及失败重入队的判定；按会话与属性代次丢弃过期项，OFF/会话结束能定向失效所有相关项。最终值替代旧采样后应获得下一次可用调度机会，不能排在一串已过期采样后面。新 API 默认不启用，已有普通调用保持行为。带所有权的去重不得误删其他会话/普通调用，同地址同 opcode 也要区分所属会话。
4. **控制公共 SDK API 的引入范围。** `LightGroupControlCommandSender` 可增加会话化发送重载或让窄的会话对象复用其消息构造；不要修改所有现有 Group 控制的默认语义。必要的新文件同步纳入受影响 target。

不建议只接上现有节流回调：可以即时试灯，但无法保证 OFF 清掉旧亮度、旧 busy 回调不回灌。也不建议在松手时调用全局取消。另建 App 直接发送队列虽可绕开普通 FIFO，但会另行承担 SDK 调度、回读、错误和底层取消边界，优先扩展既有队列。

实施顺序：先用可控调度/失败回调复现排队旧值和迟到 busy，再补 SDK 定向机制及测试；随后接入 App 实时会话和 UI 事件，最后做共享入口回归与构建。若实施中发现 SDK 最终交付边界仍无法原子隔离，先补证据并更新方案，不把只能清 UI 定时器的版本当完整实现。

## 验证与验收

自动化需覆盖真实生产行为的时序，不能只检查源码包含某个调用：

- 0/100/199/200ms 输入、同值去重、短拖动、end 紧邻 tick，最终值仅提交一次且其后没有旧采样。
- 队列阻塞、旧项已取出但尚未交付、旧 busy 回调在 end/OFF 后才回来：未交付旧项失效，旧重试不回灌；其他组、其他所有者及配置消息保留。
- 拖动中点 OFF 后再松手、OFF 连续切换、OFF 后调高亮度、两个滑条交错、加减接管、退出后旧回调、断线再连接。
- 关闭时最新值未采样与已结束两种情况；提交草稿与实时最终值一致，不重复 end；正式保存启动后旧会话失效。
- 上限裁剪、无 CCT、合法空组、紧急/权限失效；已有 Scene Settings 的 Group 弹窗可以实时组控；Devices、Templates 仍不实时组控。
- 复用 `Tests/UI/CustomDeviceSliderInteractionTests.py` 与 `scripts/check_scene_configuration.py` 中相关 Picker、draft、save coordinator 用例，补本次缺失的队列/实时交互夹具。SDK 增加所有权与晚回调测试，确认未启用新 API 的旧行为未受损。

构建：开发阶段 SunSmart / Debug / generic iOS / 不签名，使用现有 SunSmartLocal workspace 与稳定的本工作树 DerivedData；不使用 Simulator。新 SDK 公共 API 和共享文件会影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，以及实际工程中共享这些文件的 HSmart，稳定后合入前覆盖全部受影响品牌，并记录正式 SDK release 发布依赖。当前本机 SDK 能编译不代表远端 release 已具备 API。

人工最短验收：在含多灯的组连续拖动亮度和色温、快速松手、拖动中点击 OFF 并释放原手指、OFF 连续切换、调高亮度开灯，再退出重进及断线重连；检查响应、最终值、无旧值回跳/重亮、无后台续发。随后 DONE 保存并重新调用场景检查持久结果。无 ACK 组播的实际到达率、弱信号下最终一致性与 200ms 手感必须由实灯确认。

## 当前证据与交接

- App 分支 `feat/device-scene-261028`，HEAD `982abfaf`；调查开始时工作树干净。
- 本地 workspace 映射 `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；SDK HEAD `ccdf101`，调查时无未提交差异。实施前复核共享 SDK 写入占用。
- 分析阶段只读核对；实施阶段已补可控传输/定时器边界测试并构建。所有自动化结论均不代表实灯已收到组播。
- 已在上述 App 工作树及共享 SDK one-dev 实施；保持正式 project 的远端 release 配置。已有 Scene Settings 的 Group 编辑入口已按用户最新要求启用实时控制。本任务没有提交、推送或操作真机。


## 实施结果与验证记录

- 创建与已有场景 Settings 入口均显式开启实时组控；Picker 复用现有 200ms 采样及 ended 回调，亮度/色温加减均作为最终输入。OFF 取消两个滑条旧交互，在关灯与最大允许亮度间切换；恢复最大亮度时也取消整个旧实时会话，防止旧 OFF 或 CCT 请求重试覆盖新操作。普通 Device、Templates 调用保留原行为。
- Settings 管理独立会话，在进入后台、断线、权限/紧急状态通知、离开页面、切换模式/组及启动正式发送时失效。发送前及 SDK 交付前都核对当前可控状态。失败不弹提示，不声称组播实际送达。
- SDK 新增 `MeshGroupControlSession`，在普通队列中按所有者和属性替代旧值；最终输入获得优先调度。已经出队但尚未交给发送接口的旧项、迟到 busy 回调和全局取消前的旧项均受代次校验。仍有效的当前命令最多进行三次 busy 重试。
- SDK 所有权检查在主线程交付边界执行，普通队列入队/出队和全局取消代次使用既有 mutex；不调用按地址或全局取消去清理单个弹窗。已交给 MeshNetworkManager/蓝牙传输的报文不作撤回保证。
- 没有修改本地化资源、场景持久格式、服务器或固件。App 中发送重载限定在 Settings 文件，避免改变其他现有 Group 控制入口。

已通过的自动化检查：

| 验证 | 结果与边界 |
| --- | --- |
| `python3 Tests/UI/CustomDeviceSliderInteractionTests.py` | 127 checks；包含虚拟时钟 100/199/200ms 最新值采样、短拖动、end/tick 交错、双滑条 OFF、OFF 连续切换、亮度/CCT 加减、接管和关闭最终值。UIKit 跟踪与时钟为边界替身。 |
| `python3 Tests/Scene/SceneGroupLiveControlTests.py` | 22 checks；使用生产 Scene 详情 Settings 入口及实时处理函数，验证已有场景入口启用组控、只读/删除中拒绝进入；检查目标组、换算/裁剪、会话失效、断线静默不排队、权限/紧急/后台/Devices/已提交状态拦截。传输与页面环境为边界替身。 |
| SDK `python3 scripts/check_group_control_session.py` | 16 checks；使用生产队列与会话，检查去重、OFF 跨命令清理、出队未交付取消、迟到 busy、其他所有者/普通消息保留、跨属性最终值、有界重试、全局取消。定时调度和底层传输为边界替身。 |
| `check_scene_configuration.py --suite selection` | 21 项选择行为及 DeviceNameFilterSession 通过。 |
| `check_scene_configuration.py --suite save` | 保存、权限、metadata、删除生命周期及 coordinator 回归通过。 |
| `check_scene_configuration.py --suite integration` | 场景调用/反馈、pending、紧急状态和生命周期集成夹具通过。 |
| `check_scene_creation_flow.py` | 创建、持久化/导航顺序、失败/取消与旧回调回归通过。 |

构建：使用 `SunSmartLocal.xcworkspace`，Debug、iphoneos、generic/platform=iOS、`CODE_SIGNING_ALLOWED=NO`；DerivedData 为 `SunSmart-feat-device-scene-261028-cli`，各品牌串行。上一轮移除失败提示后的代码在 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 scheme 均编译通过。OFF 切换修正已复验交互与 Settings 行为测试，SunSmart generic iOS 增量构建通过。本轮又启用已有 Scene Settings 的同一 Group 弹窗入口，22 项入口/控制行为及 127 项交互检查通过；SunSmart generic iOS 增量构建通过。两次局部修正均无 SDK API、资源或品牌条件差异。首次受限环境构建未启动成功；核对 workspace 后，使用获准的 Xcode 服务访问权限重试通过，未安装或运行真机。存在工程既有的弃用、未使用变量、资源/重复编译项警告。

SDK 发布依赖：需要 `one-dev` 基线 `ccdf101` 加本次 `MeshMessageManager.swift` 修改及新 `MeshGroupControlSession.swift`；SDK 新增回归脚本为 `scripts/check_group_control_session.py`。这些改动目前未提交/未发布，正式 SDK release 尚不具备本次新 API；正式 App 集成前必须先发布 SDK。正式工程远端依赖配置和锁文件未调整。

尚未执行：实灯、真实 UIKit 多指/后台体验和弱信号组播验收。人工步骤沿用上节；分别从 Create Scene → Settings 与已有 Scene → Settings 打开 Group 弹窗，确认加减立即控制当前组、首次 OFF 后释放旧手指不重亮、再次点击恢复组最大允许亮度且按钮退出选中状态、继续点击重新关灯、松手后不回跳。失败不提示，由用户观察灯的状态判断。
