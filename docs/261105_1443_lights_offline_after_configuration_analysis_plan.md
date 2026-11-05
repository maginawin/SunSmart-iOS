# Group/Timed/Scene 配置后异常 Offline：分析、修复与验证

> 状态：已按后续“这个也需要修复”指示实施 App/SDK 修复；定向回归及品牌编译验证通过；真实设备验收、SDK 正式发布和既有 Restore 夹具缺口待完成。
> 使用 Superpowers 调试、计划执行、TDD 和完成前验证；遵循用户规则直接执行，不启用子代理、不自动提交、不操作真机。

**目标：** Group Members 配置结束自动返回 Group 时，以及 Timed、Scene 等操作后返回 Main → Lights，不因过期状态或迟到回调错误显示 Offline；真实断电、断连仍正常显示离线。

**实施方向：** 修正 SDK 共享在线状态判定的超时竞争，并在 App 可见页面返回时补齐有条件的状态查询。复用现有心跳机制，不持久化在线状态，不修改固件/后端，不改配置同步结果与重试语义。

**技术范围：** Swift/UIKit、App 页面生命周期、本地 NordicSigMeshSDK 的心跳及离线计时器。本文件同时作为分析依据和后续实施计划。

## 1. 结论与尚缺证据

用户已补充确认：**Members 配置完成自动回到 Group 时设备已显示离线；随后返回 Lights 仍全部离线，下拉刷新后恢复。** 因此配置结束的共用恢复链路必须覆盖 Group 当场展示，不能等到 Lights 才恢复。

以下问题为修复前基线分析，当前实现见第 5 节。

已通过源码和可控边界夹具确认：

1. **返回页面自动补查缺失。** Lights 的 `viewDidAppear` 只消费已有 `needsNodeStateRefresh`；Group/Timed/Scene 同步完成没有建立该标记。此前标记已消费后，正常返回不会查询设备状态，下拉刷新则会查询。
2. **SDK 旧超时可以覆盖新的在线证据。** 离线 timer 到期后先失效，再将实际置离线操作排入另一条队列。两者之间收到正常消息并续期，旧回调仍能把节点设为离线；它也没有捕获网络/节点实例，切换网络后的同地址节点可被影响。
3. **忙碌保护不在离线最终判定处。** 当前忙碌延时依赖心跳发送回调每次加 3 秒；已到期或已排队的离线回调不会重新核对 busy、当前有效计时器和更新后的 deadline。
4. **All 可控与 Offline 并不矛盾。** All 默认发往 `.allNodes` 的 `GenericOnOffSetUnacknowledged`，不要求每个节点 `state == true`，也不以逐设备 ACK 更新在线证据。能控制证明相应灯具收到了命令，不能单凭该操作让全部设备在线。

**尚未证实：这次现场首次把全部节点置为 false 的事件。** 没有此次运行日志，不能把“同步期间超时”“迟到超时”“短暂代理断连”中的某一种直接宣布为本次唯一根因。下拉恢复支持“在线状态判断/恢复链路问题”，但不能区分这些触发源。普通保存路径没有发现主动替换整个 live Mesh/Node 列表或清空全部 `Node.state` 的代码；读库快照与 live manager 分离，不据此规划状态复制机制。

实施已补充 DEBUG 聚合诊断区分 timeout、explicitOffline、sharedHeartbeat、bearerClosed、bluetoothOff、receivedMessage 与 recoveryQuery；首次现场事件仍需用户复测日志确认。

## 2. 当前检查基线

- App：`feat/device-scene-261028`，HEAD `b6f56743b9ebd09f46544ed6ebed3cde1eee6611`。
- App 开始时仅有其他任务未跟踪目录 `docs/261105_1429_space_timed_json_demo/`；保留。
- `SunSmartLocal.xcworkspace` 引用 `.local-sdk/nordic-sig-mesh-sdk`，realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK 开始时 HEAD：`c8ef744d9591b57511f96db7362c931978a707a5`。上一轮分析交付时其他任务已推进到 `3dbd5566a300422aab47e2dd20c77164f887b22b`（`fix time zones issues`），工作区干净；本轮关注的五个心跳、计时器、MeshLib 和批量发送文件相对初始 HEAD 无差异，分析与夹具结果仍适用。
- SDK 开始时已有其他任务改动：`MeshNetworkManager+DeviceLeave.swift` 修改、`MeshNetworkManager+TimeZoneSet.swift` 未跟踪；上一轮分析始终只读，未执行该提交；本次实施前已重新核对 SDK 为该 HEAD 且工作区干净。
- 上一轮分析时曾出现其他任务文档 `docs/261105_1429_space_timed_json_contract.md`；本次期间该文件不再出现在未跟踪清单中，本任务未操作该文件。
- 正式依赖仍应保持远端 `release`，未来 SDK 修复需要单列发布 revision；本地构建不能替代正式依赖发布。

## 3. 修复前触发链与代码证据（行号对应分析基线）

### 3.1 页面展示与控制

| 环节 | 当前实现与位置 | 影响 |
| --- | --- | --- |
| Offline 图标 | `SunSmart/Main/Device/View/DevicesViewCell.swift`，`device.didSet` 读取 `device.state` | 与 Group Unsync、云同步状态是不同字段 |
| 返回 Main → Lights | `DeviceLightsViewController.swift:108–125`：重新取 live devices，再消费 pending refresh | 重绘本身不会产生在线证据 |
| 自动查询门槛 | 同文件 `296–320`：须 pending、页面可见、window 存在、Mesh 已连接 | 没有 pending 就不会查询 |
| 下拉刷新 | 同文件 `refresh → getNodesState → MeshNodeHeartbeatManager.refresh` | 会重新取得实际状态；符合用户反馈 |
| 数据更新 | 同文件 `741`、`1642`：可见 Cell 使用消息对应 Node 重绘 | 本轮未发现固定只画旧图标的独立缺陷 |
| All | 同文件 `501`、`634`、`652`；`Common/Data/LightGroupControlCommandSender.swift:36` | 可发送全网 UNACK，不以全部节点在线为门槛 |

`Node.state` 在 SDK `MeshLib/Node/Node+Propertys.swift:241` 是对象关联的运行时布尔值，默认 false。它不是用户配置，也不适合持久化为重启后的在线事实。

### 3.2 共享心跳与离线判断

SDK 文件路径相对于 `one-dev/Sources/NordicSigMeshSDK/`：

- `MeshLib/Manager/MeshNodeHeartbeatManager.swift:79–121`：普通模式周期为 `min(180, max(节点数 × 0.3 × 3, 60))` 秒；开始后为节点建立约两个周期的离线期限。
- 同文件 `297–324`：心跳发送时遇到 `MeshNetworkManager.busy`，把本次发送推迟 3 秒，并延后所有离线 timers。
- `MeshLib/Manager/MeshLibManager.swift:1341`：busy 包括批量配置、配网、Key Bind、校准、固件升级等；不仅是 Group Members。
- `MeshNodeHeartbeatManager.swift:461–489`：显式 offline 消息可置 false；普通有效接收消息恢复 true 并续期。
- `MeshNodeTimerManager.swift:27–60`：最终超时仅按 address 查**此刻**全局网络，然后无条件置 false；没有 timer generation、deadline、新消息或网络身份复核。
- `MeshNodeStateTimerManager.swift:154–196`：`NodeStateTimerContext` 到期时先 `invalidate()`，后执行回调；对已失效 context 调 `timerDelay` 不会重新创建底层 timer。
- `MeshLibManager.swift:1800–1829`、`2179–2195`：代理全部断开/蓝牙关闭也会批量置 false。真实断连行为必须保留；是否存在本次短暂断连，需要日志确认。

可复现的竞争顺序：

1. 旧 timer 到期、失效，将置离线操作排队。
2. 新消息到达，节点恢复/保持在线，尝试给旧 context 续期。
3. 已排队旧操作继续执行，移除 context 并写入 `state = false`。
4. 回到 Lights，没有 pending 则不立即查询；下拉查询后再收到状态，恢复在线。

这个顺序证明实现存在问题，不证明此次现场必然走了该顺序。忙碌检查缺口同理：通常的心跳忙碌延时能起保护作用，不能把“只要 busy 就一定离线”作为结论。

### 3.3 操作覆盖范围

| 用户操作 | 进入的共享链路 | 本轮判断 |
| --- | --- | --- |
| Group 新增/更新 Members | `GroupMembersViewController.swift:435–504` → `.group` Sync → `SyncExecutionSession` → `MeshProxyMessageCommand` | 用户已报告自动返回 Group 即离线，并确认 Lights 下拉恢复；共享缺陷可影响 |
| Timed 新建/编辑后同步 | `ScheduleAddViewController.swift:517` → `.schedule` Sync | 相同风险，尚未真机复现 |
| Timed 启用/禁用、删除 | `TimedViewController` → `ScheduleServer`；后者在 `337` 直接走共享批量发送，失败后也可进入 Sync 页面 | 相同风险；不是只修编辑页即可覆盖 |
| Scene 保存后同步 | `SceneSettingsViewController.swift:777–823` → `.scene` Sync | 相同风险，尚未真机复现 |
| Scene 预览/参数发送 | `SceneSaveCoordinator.begin` → `SyncExecutionSession` | 同一 SDK 状态风险；preview 不发云变更通知，不能把云变更通知当唯一恢复触发 |
| Profile、设备参数、开关绑定、Proximity Path、Space Trigger Zone、设备同步 | `SyncDevicesViewController.SyncType:1122–1156` → 同一发送与心跳机制 | 具备相同风险；新增持久化字段或各页面独立补丁没有必要 |
| 配网/Key Bind、校准、OTA | SDK busy 的其他来源 | 共享计时器风险适用；正常重启/断连造成的离线不应掩盖 |
| 仅改名称等不发 Mesh 消息的保存 | 不因保存本身进入批量 Mesh busy | 未发现该保存直接清空 state；若离开期间已超时，返回补查缺口仍可能显现 |

Group/Timed/Scene 配置数据的失败、恢复回执和同步 pending 状态应保持原语义，不能把配置 ACK/上传成功当作所有灯在线。

## 4. 方案比较与推荐

| 方案 | 效果与代价 | 判断 |
| --- | --- | --- |
| 仅 Lights 每次返回全量刷新 | 可自动完成用户当前的下拉动作；仍会先显示错误 Offline，旧回调仍可再次覆盖；反复进入会增加查询和 RSSI 成本 | 不作为完整修复 |
| SDK 修正超时有效性 + App 有条件补查 | 修复错误状态写入，在真实断连/历史状态过期后自动恢复查询；覆盖各类共享入口 | **已实施** |
| 新增独立在线状态缓存或整体改为三态 UI | 涉及所有读取方、状态迁移、UI 和长期维护 | 当前证据不要求，暂不采用 |

不把保存成功时直接设全部在线作为方案，这会把真实离线设备也显示在线。

## 5. 已实施的最小完整修复

### SDK：状态判定和恢复归共享所有者

- `MeshNodeTimerManager.swift`：每个有效超时绑定 live Network/Node 对象、generation 和单调时钟 deadline；在主线程复核后才置离线。续期新建有效 timer，已排队的旧回调不能覆盖新证据；切网、删除重加和取消同样失效。真实 BackgroundTimer/主队列夹具补充了实际异步边界。
- busy 到期及心跳 busy 延时都会保留“需要重新探测”的运行时标记。解除 busy 后把请求交给共享心跳协调器，给现有正常超时周期的应答机会；没有回复仍会离线。没有直接设置所有设备在线。
- `MeshNodeHeartbeatManager.swift`：接收消息与超时判定统一到主线程；跨队列回调重新验证网络和节点身份。stop 清理在线超时与恢复会话。显式离线、在线报告和普通有效消息保留原语义。
- 新公开入口 `refreshOfflineNodes()` 将配置结束和页面返回的请求合并：等待 busy 解除，只查询离线且适合轮询的节点，以及 busy 期间延期、需要再确认的节点；常规轮询将请求按 live Node 身份合并到尚未发送的队尾，保留待发顺序及当前发送定时器；重复请求按查询交给消息发送器的时刻冷却 5 秒。手动 `refresh(nodes:)` 仍保留优先刷新语义，publish 模式仍走原广播路径。不改变常规心跳周期、单播 Get、0.3 秒发送间隔，也不触发 RSSI 扫描。
- `MeshProxyMessageCommand.reset()` 统一申请恢复，因此 Group/Timed/Scene、参数、Profile 等共用批量发送入口的成功、失败、停止都覆盖；不依赖业务成功回调或云端通知，不修改同步 pending、ACK 和重试结果。
- 新公开通知 `MeshNodeHeartbeatManager.nodePresenceDidChange` 在主线程发送，且过滤失效节点；不依赖单一页面 messageDelegate。真实断连/蓝牙关闭仍置离线并发送通知。DEBUG 只输出原因和聚合数量，不输出密钥。

### App：返回 Group 就恢复，页面共享在线证据

- Group、Lights、Timed、Scene 详情/编辑页可见时请求同一个共享恢复入口；配置完成自动回 Group 已由 SDK 统一结束入口覆盖，Group 的出现调用是正常重进的补充。
- Space 生命周期内监听 SDK presence 通知，验证 Mesh UUID、networkId 和 live Node 身份后，转发已有 `deviceStateUpdateNotificationName`；退出 Space 时取消监听并拒绝迟到通知。
- Group 将该通知合并到已有 dirty/UI timer；Lights、Scene 沿用现有状态通知刷新，避免配置页改变 delegate 后漏刷新。
- Timed 设备/Group 目标选择面板接收在线变更并重画。已保存的离线设备恢复在线后解除旧的禁止取消选择状态，保留当前选择，不重新读取配置。隐藏/关闭面板不更新。
- Timed/Scenes 列表本身不展示单设备 Offline；详情/目标选择和随后返回 Group/Lights 共用以上修复，不新增列表独立轮询器。

### 数据、依赖和范围

**数据库及 export JSON 结构变更清单：无。** 没有修改表、字段、JSON Key、默认值、字段含义、序列化、导入导出或迁移；新增状态只存在于运行时计时器/查询协调器，因此不需要历史数据迁移。

App 仍使用正式远端 `release` 声明，本地构建映射到 `one-dev`，基线为 `3dbd5566a300422aab47e2dd20c77164f887b22b` 加本次未提交差异：`MeshNodeTimerManager.swift`、`MeshNodeHeartbeatManager.swift`、`MeshLibManager.swift`、`MeshProxyMessageCommand.swift`。App 使用两个新增 SDK 公共符号，上游正式 `release` 必须先包含此次 SDK 修复，才能使用远端依赖构建此 App；发布 revision 尚不存在，未提交、推送或发布。

同一共享实现影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；没有新增资源、本地化、品牌条件或 App 工程文件。固件、网关、服务器无配套修改要求。其他任务的文档和执行期间出现的 `AGENTS.md` 改动均保留。

## 6. 验证记录

新增回归先复现失败，再验证修复：旧 expiry 覆盖在线、busy 到期、心跳 busy 延时结束后的探测空档、配置结束未申请恢复、无页面 delegate 时漏通知、Lights 无 pending 返回不查询。

| 验证 | 结果与边界 |
| --- | --- |
| SDK `python3 scripts/check_node_offline_lifecycle.py` | 通过：正常超时/续期、排队旧回调、busy 恢复、切网、同地址删除重加、主/次级 Element 地址复用、取消；另用真实 BackgroundTimer 和 main queue 覆盖到期、续期、换网。模型/无线是替身 |
| SDK `python3 scripts/check_node_presence_recovery.py` | 通过：等待 busy、合并 offline 与延期在线节点、节流、重试、网络隔离、电池设备过滤、不伪造在线、无页面 delegate 时仍通知 |
| SDK `python3 scripts/check_node_presence_messages.py` | 通过：执行生产接收函数，真实 background→main 队列；显式离线/在线、普通消息、次级 Element 离线取消 primary timer、排队时替换网络/节点；消息和传输边界是替身 |
| SDK `python3 scripts/check_scheduler_task_replacement.py` | 通过：现有传输/批量任务取消与回调归属；新增配置结束申请恢复且重复结束不重复请求的断言 |
| App `python3 scripts/check_lights_presence_refresh.py` | 通过：可见返回无 pending 自动申请恢复、不启动 RSSI；手动刷新和隐藏 pending 行为保留 |
| App `python3 scripts/check_space_presence_callbacks.py` | 27 个场景通过，包含生产通知注册/转发、重复注册、失效节点、不同 subnet、退出后迟到通知；UIKit/网络替身 |
| App `python3 scripts/check_timed_schedule_selection.py` | 通过：目标选择、原离线保护、取消/隐藏；新增 presence 回调恢复图标/取消锁定且不丢选择、不启动配置读取 |
| App `bash scripts/check_lights_all_control_cooldown.sh` | 通过：All 命令/冷却/Cell 复用/可见性；未改 ACK/UNACK |
| App `python3 scripts/check_sync_execution_session.py` | 通过：共享同步成功/失败/STOP/重试/迟到回调等；有原夹具 default 不可达 warning |
| App `python3 scripts/check_scene_sync_read_performance.py` | 通过：53/500 节点缓存和读取复用、失效、deadline/resume；不能代表真实 App 性能 |
| App `python3 scripts/check_timed_list_sync_display.py` | 通过：成功/部分失败/回滚/hidden/reuse/取消/作用域；补齐原夹具缺失的现有 selectTargetType 边界，有原 weak 变量 warning |
| App `bash scripts/check_group_page_ui_refresh_coalescing.sh` | 通过；源码契约检查，不等于 UIKit 行为验收 |
| App `bash scripts/check_nordic_sdk_dependency.sh`、App/SDK `git diff --check` | 通过；本地 realpath 已核对 |
| SDK `bash scripts/check_restore_queue_lifecycle.sh` | **未通过、非本修复回归**：先遇到缓存目录写权限，改用可写 module cache 后暴露旧夹具缺 Node.elements、prepareTransmission、SceneRegisterStatus 等。用 HEAD 三个原文件在临时目录编译复现相同错误。没有修改 FastAdd 业务代码绕过；共享 Proxy 相关验证由上面的 Scheduler 边界回归覆盖，但不声称 Restore 全套通过 |

编译使用 `SunSmartLocal.xcworkspace`、Debug、`-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`，DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-presence`，同目录串行。SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的新增 SDK API 接入构建均 exit 0。最终自行差异复核补充了主地址被新设备复用为次级 Element 的边界：两个回归先失败后通过，修正只涉及 SDK 内部计时器取消地址，不改变公共 API/品牌配置；按共享纯逻辑规则再用 SunSmart 构建，exit 0。已有 CryptoSwift/Swift 6 兼容、deprecated UI、资源重复等 warning 未在本任务中扩展修复。没有运行 Simulator 或真实设备，也没有验证实际 Mesh/服务器交互。

自行差异复核覆盖计时器生存期、配置结束的成功/失败/STOP、通知会话归属、Group 自动返回与 Timed/Scene 可见刷新、真实离线语义、查询合并和正式 SDK 依赖边界。用户禁止子代理，因此没有委派独立审查。未展开固件/服务器、云端恢复完整链路和真实无线时序，原因是本次没有改动这些入口且缺少运行证据；这些限制不视为通过。

### 2026-11-05：P2 重复恢复请求阻碍队尾查询

本轮仅修复该 P2：自动恢复不再调用会重排队首的手动刷新路径，复用原 `heartbeatNodes/current` 队列并去重合并待发节点，不增加持久状态或公共 API。发送前跳过已删除、替换或不再属于 `realNodes` 的对象，避免队尾停滞。数据库及 export JSON 结构无变更；demo 校验路径问题未处理。

扩展 SDK `check_node_presence_recovery.py`，实际执行生产恢复、合并、手动刷新、发送及 heartbeat Timer 函数。修复前，30 节点每隔 5.1 秒恢复的夹具在首轮 9 秒只覆盖前 17 个节点，随后重复查询前部；修复后首轮按序覆盖 30 个节点，连续 51 秒恢复也覆盖全部节点。额外覆盖 busy 后冷却、重试、新节点追加、保持定时器 deadline、手动刷新优先级、切网、删除/同地址替换、轮询资格变化及 publish 兼容；补充真实 Foundation Timer/run loop 排空检查。51 秒场景使用受控时钟，模型、延迟恢复调度和无线发送器是替身，9 秒表示进入消息发送器的时间，不代表无线送达或设备恢复在线耗时。

本轮 SDK recovery、offline lifecycle、presence messages、scheduler replacement，以及 App lights presence、SDK dependency 检查和两工作树差异检查通过。SunSmart 使用 `SunSmartLocal.xcworkspace`、Debug、generic iPhoneOS、禁用签名构建，DerivedData 为 `SunSmart-feat-device-scene-261028-presence-queue`。首轮及最终增量构建均 exit 0；首轮有既有兼容/弃用 warning 和伴随 exit code 0 的 SwiftCompile 诊断，最终增量无诊断输出。无新增品牌分支、资源或公共 API，未重复构建其余品牌。未运行真机或真实 Mesh 验收，未 commit/push。

最短人工复测：在约 30 个离线节点的 Space，每隔约 5 秒返回 Lights/Group，持续约 1 分钟；让列表前部若干节点持续不应答，后部节点保持可通信，确认后部能收到查询并恢复在线；再检查手动下拉及配置 busy 结束后的恢复。

## 7. 最短人工验收与剩余事项

1. 同一 Space 保留两台在线灯，另让一台灯真实断电；记下初始状态。
2. Group Members 添加/移除一台在线灯，等待同步自动返回 **Group**，不下拉：在线灯不应被配置流程批量标记离线；再返回 **Main → Lights**，状态应一致。确有旧离线状态时应自动查询恢复，断电灯保持离线。
3. 分别更新 Timed、Scene；检查自动返回页、目标选择面板/场景详情以及 Lights；各做一次正常完成和一次 STOP/失败后返回。
4. 复测较长同步及代理断连再恢复：真实断连可显示离线，重连后自动收敛；旧超时不能在新回复之后再次写 Offline。快速重复切页不应连续重复查询或产生 RSSI 扫描。
5. All 仍可控制在线灯。若再现，保留 `[NodePresence]` 聚合日志与操作时刻，重点看首次批量 Offline 的 reason；现场首个触发事件尚未从用户日志证实。

合入/发布前待办：用户真机确认完整 Group/Timed/Scene 路径；SDK 正式 release 发布并记录 revision；Restore 旧夹具缺口单独修复。当前未 commit/push/merge，不把自动回归或编译通过等同于现场验收。
