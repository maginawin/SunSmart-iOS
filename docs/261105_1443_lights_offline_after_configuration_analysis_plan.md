# Group/Timed/Scene 配置后异常 Offline：分析、修复与验证

> **最新状态（2026-11-05 16:48）：第 10 节五项任务已实施，相关行为回归及一次 SunSmart Debug generic iPhoneOS 构建通过。** 普通配置上传仅按服务器业务结果收尾，无自动配置前读、回读或导入；实际编辑权限确认后的新 Space 进入会话集中核对，有 dirty 才上传并回读。实现、验证及边界见第 11 节。未操作真机、未提交代码；SDK 保持只读。第 8 节现场证据保留，第 8.4 节旧方案不执行。

> **2026-11-05 15:50 日志复核更新：现场仍有另一条未修复路径。** 新日志证明上传回读会走等版本完整导入，替换 live Node，丢失运行时在线状态；此前 SDK timer 修复没有覆盖这条边界。详见第 8 节。本次仅分析并更新文档，未修改 App/SDK 业务代码，未运行构建或真机。

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

**初次分析时尚未证实首次离线事件。** 当时没有运行日志，不能把“同步期间超时”“迟到超时”“短暂代理断连”中的某一种宣布为唯一根因。普通保存路径未发现直接清空 live Node 状态，但该结论不覆盖云上传后的完整导入。2026-11-05 新日志已补上这条证据，见第 8 节；不再沿用“没有发现节点替换”作为本次现场结论。

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

## 8. 2026-11-05：两台灯加入 Group 的现场日志分析（待实施）

### 8.1 检查基线及证据边界

- 日志：`/Users/maginawin/Desktop/add 2 lights into a group logs.txt`，按逻辑行计 945 行；文件末尾无换行，`wc -l` 显示 944。
- App：`feat/device-scene-261028`，HEAD `185265a35b84f2df5f5ce802d827b3f315794136`；开始时工作区干净。
- 本地 workspace 映射仍为 `one-dev`，SDK HEAD `3dbd5566a300422aab47e2dd20c77164f887b22b`，已有暂存的 presence/计时器/批量发送修复和相关夹具。本次只读这些差异，不改动其暂存状态。
- 日志未标明构建 revision，以下为日志事件与当前源码交叉核对；没有现场对象地址、完整心跳 deadline 或逐行墙钟时间，不能精确计算离线持续秒数。HTTP body 在源日志中已截断，不能用它证明两轮完整配置完全相等。
- 文档只记录请求类型、版本、命令和状态，不复制请求凭据、密钥或原始 body。

### 8.2 两台灯同时暂时离线的原因

**结论：配置上传后的回读完整替换 Node，丢失尚在运行时对象上的在线证据。这条路径无需心跳超时，也不经过已有的 offline 原因日志。**

| 日志行 | 事件 | 判断 |
| --- | --- | --- |
| 36 起、47 起 | 订阅配置下发，设备返回成功状态 | 设备在配置过程中确实有通信，不能把“执行同步”当作离线原因 |
| 583–584 | 地址 `0x0005` 返回 SceneRegisterStatus Success | 对应设备的次级 Element 仍在应答 |
| 585–627 | 向 `0x0003` 设置 Restore，上电状态命令重发后超时 | 仅能确认这一条命令失败，不能推出两台设备离线 |
| 742–759 | 第一轮回读：local/submitted/remote 均为 `1793864732`，`conflict=false`，仍完整导入 | 相同版本也进入替换路径 |
| 889–906 | 第二轮回读：三者均为 `1793864738`，再次完整导入 | 返回 Group 前又一次替换 |
| 913–914 | 返回 Group，`recoveryQuery count=2 total=2` | 共享恢复器发现两台灯需要补查 |
| 915–944 | 查询 `0x0006`、`0x0003`，两者均回 LightCTLStatus | 实际可以通信 |
| 945 | `transitions=receivedMessage:online=2 connected=true busy=false` | 两台 Node 都发生 false → true，符合用户看到的先离线再在线 |

直接源码链：

1. `SpaceConfigurationSafety.swift:262–291` 的 `prefersNewerCloud` 有明确的等版本云端优先策略，用来处理 Web 不递增 timestamp 的编辑；`resumeUpload` 收到上传回读时在 `1531` 先尝试 `importNewerCloudIfNeeded`。
2. `ImportData.swift:2116–2125` 在 Mesh UUID 和 subnet 匹配时使用 live network；`2247–2249` 允许等版本完整覆盖。
3. 同文件 `2438–2445` 移除全部非本地 provisioner 节点，再经 `CloudNodeImport.decode` 创建新 Node；`2703` 将新对象加入 network。不是只读备份，也不是单纯刷新 UI。
4. SDK `Node+Propertys.swift:241` 的 `state` 是对象关联的运行时 Bool，默认 false，不属于云配置。新对象没有旧对象的在线证据。
5. 已修复的 `MeshNodeTimerManager` 将 deadline/generation 绑定 network 和 Node 对象；替换对象后旧 timer 在身份复核处失效。这正确防止地址复用污染，却不能自动把旧证据移交给同一设备的新对象。
6. Group 返回时 `refreshOfflineNodes` 查询新对象，接收有效消息后变回在线。因此只加强页面刷新仍会先闪 Offline。

需求解释：同一网络中的同一设备，只要有效在线证据未过期，保存、上传、回读和页面切换都不应把它置离线。现有实现还会在明确离线报告、蓝牙关闭/所有代理断连时置离线；这些与配置导入不同。本次建议保留这些既有明确失联语义，不将单条配置 ACK 超时当作整台设备、更不能当作整组离线。若产品要求连明确断连也必须等到原心跳期限，则是单独的状态语义调整。

### 8.3 HTTPS 数量和来源

以 `[HTTP][Request]` 计数，**7 次请求，而不是 URL 出现的 14 次**。同一请求还有 Response、Metrics、Decode 日志；CloudSync Request/Success 是外层记录，不是额外请求。

| 顺序 | 日志行 | API | 用途 |
| --- | --- | --- | --- |
| 1 | 592 | `/sitespace/user/hb` | 用户在 Space 中的会话心跳；不是灯具 Mesh 心跳 |
| 2 | 630 | `/sitespace/get/spaceprops` | 首轮上传前基线/权限/冲突核对 |
| 3 | 675 | `/sitespace/sync/spaceprops` | 首轮同步结束后的配置及结果上传 |
| 4 | 699 | `/sitespace/get/spaceprops` | 上传后的回读确认，随后导入 |
| — | 764–765 | 用户点击 `resyncBtnAction` | 两轮之间确实存在手动重试 |
| 5 | 777 | `/sitespace/get/spaceprops` | 重试结束后的下一轮上传前核对 |
| 6 | 822 | `/sitespace/sync/spaceprops` | 第二轮上传 |
| 7 | 846 | `/sitespace/get/spaceprops` | 第二轮回读确认，随后导入 |

当前不是逐条 Mesh ACK 上传：`SyncExecutionSession.finishRun` 在本轮补偿/收尾后发送一次 `spaceDataChangedNotificaitonName`。但 `604–606` 没有检查配置或已持久化结果是否真的改变，成功和失败轮次都会发送；`SpaceViewController.swift:660–665` 收到后调用 `commitLocalChangeForCloudSync`，`80–83` 以及 `128–132` 无条件推进 lastUpdate，再以 `.promptly` 入队。

因此需区分：

- **必要上传：** 初次成员配置、成功 ACK 导致结果变化、失败/取消后已有部分成功，均可能需要上传最终已持久化状态。不能只允许全部成功时上传，否则云端丢失真实进度和重试状态。
- **可精简：** 没有配置/结果变化的空重试或重复完成通知不应制造新版本、再走一轮 3 请求。当前存在这条无条件触发路径。
- **不可从本日志直接删掉的请求：** 上传前读取用于当前版本/权限/身份冲突判断；上传后读取用于确认服务器实际保存的配置。HTTP 200 不能替代后者。现有接口没有在上传响应中提供足够的完整确认信息；不把删除两次读取作为最小修复。
- 用户心跳在 `SpaceViewController.startHeartbeatTimer` 中每 30 秒执行，独立于配置上传；本段只出现一次，无频繁重复的证据。

正常一轮有变化且无冲突/网络失败时，当前安全机制预算为 **1 次基线读取 + 1 次上传 + 1 次回读**，用户会话心跳单独计。真正有结果变化的失败轮及重试轮可以各一轮，不能预先承诺本日志 7 次全部压成 1 次。

关联风险：764–765 行点击重试后至第二轮上传结束，没有新的 Mesh 配置发送/ACK 日志；这证明日志中看不到失败命令被补发，不足以认定设备重试已成功，也不足以证明两轮完整 payload 相同。导入替换 Node/Group 后，仍打开的同步页持有旧任务和对象引用，需要纳入回归，检查是否正确重建任务、是否错误地把空任务判成功。没有据此宣布具体重试根因已证实。

### 8.4 推荐修复范围（分析建议，尚未实施）

采用共享导入边界修复在线证据，并按实际变化合并云上传；只修 Group UI 或保存后强设在线均不能满足要求。

1. **在线证据移交归 SDK 共享管理器负责。** App 在 live 导入的节点替换边界请求交接，同 Mesh/subnet、相同 UUID、地址/Elements 及设备身份一致才允许继承；身份凭据只比较，不记录。移交原有在线证据与剩余 deadline，取消旧 timer generation，再将原期限绑定到新对象。不能仅复制 `state=true`，也不能因为导入而重新给满一个心跳周期。
2. **失败和竞争完整性。** 在实际替换前读取最新证据；导入提交成功才发布新对象状态。回滚保留旧状态/期限；异步期间的新消息、明确离线、断连、切网优先，不能被旧快照覆盖。新设备、删除重加、地址复用、已过期或无有效证据的节点不得继承在线；到原 deadline 仍能正常离线。
3. **按真实结果决定上传。** 复用现有 dirty/待上传状态与配置比较，在共享执行会话完成处合并本轮变化；保留成员保存带来的待上传意图、部分 ACK 成果和失败/取消后的待重试配置。无变化不递增 timestamp；已有 pending upload/未确认回读仍继续原恢复流程。重试期间合并尚未发出的同 Space 任务，已经发送的请求正常收尾，后续真实变化进入下一代，避免取消导致回执丢失。
4. **检查导入后的重试对象归属。** 使用当前 live 节点及现有配置代次验证重建必要任务，保留已成功且未变化的目标，必须重发尚未成功的操作；不能因旧对象失效或 handle 为空宣称成功。
5. **保留前读/回读的安全意义。** 可另评估“完全匹配本次提交的回读仅确认回执、不重导入”，但不能仅凭 timestamp 相等就跳过导入；该项目允许同版本云端编辑，必须覆盖内容、权限、身份与待恢复事务。它不是单独解决所有导入丢失在线证据的办法，首轮不依赖此优化。

现有机制不足及维护成本：在线状态属于旧 Node，计时器也只认旧对象，没有合法导入交接能力；新增能力仅围绕现有 SDK presence/timer 所有者，不另建全局长期在线缓存。上传使用现有同步会话、待上传状态和回执机制，增加本轮变更判断，不新建持久上传队列。

**数据库及 export JSON 结构变更清单：无。** 不增加/改变表、字段、JSON Key、类型、默认值、语义或迁移；只补运行时对象交接和上传触发条件，无需结构 demo。若实施中发现必须改变持久结构，先另行列清单、demo 并确认，不沿用本方案授权。

共享代码涉及五品牌，无 UI 文案或资源变化。可能涉及 SDK 新公共桥接能力，须记录实现 revision，并先发布正式依赖后再集成远端构建；不修改固件、服务器或运行配置。

### 8.5 后续最小验证与交付界限

- **复现与回归：** 两个在线 Node → 真实 CloudNodeImport 解码/导入替换 → Group 读取新 live Node；在线状态和原 deadline 应保持。不能只用手写 Node 替身、源码文本检查宣称验证了导入边界。
- **生命周期：** 原期限到期、原本离线、同地址不同设备、切网/退出、导入失败回滚、导入期间收到新消息或断连、旧 timer 已排队；新对象和旧任务不能相互污染。
- **同步结果：** 正常成功、部分失败、STOP、失败重试、无变化重试、上传期间再次修改、HTTP 失败和回读失败恢复；无变化无新 POST，有变化每轮至多一轮正常上传。已有 pending 回执即使业务无变化也必须继续恢复。
- **关联路径：** Group Members 自动返回、Lights、Timed、Scene 共用导入与执行会话，针对共用边界覆盖；失败命令必须有真实发送及 ACK/失败证据，不能只看云成功。
- **构建/真机：** 实施后运行相关现有 SDK presence、App sync session/配置回执回归并补真实导入边界夹具；按改动风险构建代表 scheme，若新增 SDK 公共 API 则稳定后核对五品牌编译。真机由用户复测两台灯加入 Group、单条命令失败再重试、重进 Group/Lights；核对不闪 Offline、无变化不重复上传、真实断电仍按期限离线。
- **本次完成项：** 日志请求计数、顺序分析、源码调用链与工作树/SDK 映射核对、更新原文档。没有新测试、构建、真机/服务器操作，也没有修改业务代码或提交。

## 9. 上传回读历史与用户指定的简化方向（2026-11-05）

### 9.1 Git 历史核实

以下时间为 Git 提交时间，UTC+8。已直接核对提交 diff；不是仅依据历史文档或提交标题。

| 时间 | 提交 | 实际变化 |
| --- | --- | --- |
| 2026-09-07 15:01:04 | `d4e4e4364a0c16f33d81f25b7cfd90d0274c2601`，`fix: space trigger zone sync issues` | 首次在普通上传成功后增加 Space GET，比较提交配置与云端配置；用于 Profile、Path/Zone、成员配置完整性确认。当时尚未把普通回读变成完整导入 |
| 2026-09-08 11:02:44 | `abfbe5a710107897eea56b8267422e860a0cf162`，`fix: space trigger zone bugs` | 将确认扩展为持久 submission 与 `resumeUpload` 恢复；作者时间为 9 月 7 日 17:46:06，与提交时间不同 |
| 2026-09-11 18:44:41 | `f14aea3967ec765359f1adda1fed7c8998c85ff7`，`feat: don't check after sync OK` | 明确取消正常成功后的回读，改为 `finishAcceptedSubmission` 本地收尾；已 accepted 的旧回执同样直接收尾，未知结果恢复当时仍保留 GET |
| 2026-09-23 16:57:10 | `38ec384057b35cc340e0d95686fda490e86ce277`，`fix: improve key missed issue` | 密钥完整性修复中重新把成功分支改为 `resumeUpload`，并要求 submission 达到 verified 才能完成；从此普通成功上传又需回读 |
| 2026-11-02 18:01:15 | `32c768371933d56fc24e2b94670c2678ce0679fd`，`fix： owner sync with editor` | 在上传前读取及上传后回读中加入 `importNewerCloudIfNeeded`，可选择较新云端快照并完整导入 |
| 2026-11-04 13:48:57 | `eb9caaf3`，`fix: sync issues of Xie YY` | 将云端选择从严格较新扩展到等版本；这是本次同版本回读也重建 live Node 的直接相关扩展 |

9 月 23 日恢复回读的具体背景见 `docs/260923_1603_space_sync_500_missing_key_analysis.md`：当时处理 Site 转出/转回导致本地子网 Key 缺失、上传不完整配置等问题，将 Key 指纹纳入回执确认，并把正常成功和未知结果都纳入 GET 核对。它属于 App 侧后来添加的防护策略，并非上传接口自身要求每次必须 GET。

9 月 11 日的旧方案与实现文档分别为 `docs/260911_1828_sync_success_direct_confirmation_plan.md`、`docs/260911_1836_sync_success_direct_confirmation_implementation.md`。可复用其中“只确认实际提交版本”的原则，但不能整体 revert：之后已有成员、删除、Timed、Scene 等必要修复。

### 9.2 当前行为约定与最小调整

采纳用户提出的收敛方向，以本节替代第 8.4 节对普通上传的建议。此前“每次上传前读/回读必须保留”的表述是对现状的过强约束；本轮明确调整。

| 场景 | 目标行为 |
| --- | --- |
| 从外部进入 Space，身份为 owner/editor，并已取得实际编辑权限 | 集中完成必要的配置核对；有待上传内容时上传，成功后做一次正常回读确认。无变化不制造上传。失败就标记失败，不用继续回读把失败改判成功 |
| visitor，或 owner/editor 选择只读进入、编辑权被其他用户占用/已被禁用 | 不启动上述上传及回读确认。正常只读数据加载与权限验证仍按用途保留 |
| Group/Timed/Scene/设备配置结束、普通手动同步及重试 | 本地检查 → 上传 → 按网络层业务结果成功/失败收尾；不为这次上传额外 GET，也不调用自动云端替换导入 |
| 返回 Group/Lights、子页返回 Space、普通前台/网络恢复 | 不冒充新一次进入 Space，不启动进入时的核对流程；需要补传时走普通上传 |
| 普通上传失败、HTTP 错误、业务拒绝、断网或超时 | 保留本地修改，标记同步失败；不发 GET 尝试确认成功。后续重试上传，或下次具备权限进入 Space 时集中核对 |

“进入 Space”以新的进入会话且实际编辑权限确定为边界，不直接放在每次 `viewDidAppear`。现有 `canEditing` 不包含全部动态编辑权条件，不能只判断 role 或单用这个属性；需沿用密码、成员有效性和 `disableEditorPermission` 等真实权限判断。`init` 会将禁用标志复位，因此也不能刚创建控制器就当作已通过编辑权检查。

为满足“一次普通上传只发一次配置请求”，普通上传前由 `resumeUpload(preparingUpload: true)` 触发的云端核对也应一并移到进入流程；只删上传后的 GET 仍会发生读取、替换和导入。网络层 `.success` 沿用已有 HTTP/业务解析规则，不把 HTTP 200 携带业务错误当作成功。

实施需要覆盖共享云管理器中的 Space、Site 内嵌 Space、批量/首次创建、解绑前上传、前台/网络恢复与旧回执入口，避免仅修一个调用点后其他入口继续绕回 `resumeUpload`。保留本地完整性检查、权限校验、删除日志和导入事务；不在普通上传回调中触发这些机制的远端读取或配置替换。

成功只确认本次请求提交的版本：上传 A 时本地又产生 B，A 成功不得清掉 B；本地保存失败保留本地收尾恢复依据。旧 accepted/verified 回执复用既有状态完成兼容，不伪造 verified；未知结果不再在普通上传入口自动 GET。首次 Site 创建未获得资源的历史中断应在集中进入/恢复边界处理，不能误把它当作一个已创建 Site 的正常上传。

这样可以直接消除本次“添加设备 → 普通上传回读 → 替换 Node → 闪离线”的触发链，先不增加 SDK presence 移交 API 或独立状态缓存。进入时仍需避免在用户已经开始 Mesh 配置后迟到导入；权限确定、配置核对、允许编辑的顺序必须明确。其他真实导入路径若还有在线状态丢失，按实际证据单独处理，不扩大本次方案。

明确取舍：普通上传的成功含义为服务器业务确认接受，不再实时检查服务器是否静默丢字段；配置一致性核对集中到进入流程。这是用户指定的策略调整。

### 9.3 数据与验证边界

- 预计无需修改 SDK、数据库或 export JSON 结构。保留现有字段及 accepted/verified 的含义，仅改变收尾条件和调用时机；不新增持久化队列。若实现需要变更任何持久字段语义或格式，仍先展示清单及 demo 再确认。
- 复用现有回执/云上传/同步会话测试，重点验证普通成功/失败/超时均无前读、回读及导入；实际提交版本确认；旧回执不造成持续阻塞；真正进入且具备编辑权才触发核对，子页返回不重复。
- 回归原始两台灯添加到 Group、失败后重试，以及 Scene/Timed 的共用上传路径。普通一轮有变更的上传预算为 1 次配置写请求；用户会话心跳和必要权限请求另计。
- 本轮只核实 Git 历史并更新本方案，未修改业务代码、运行测试、构建或真机；第 8 节日志事实仍成立。

## 10. Space 上传流程简化实施计划（2026-11-05 16:03，用户已确认方案）

> **执行方式：** 新 session 单代理依序实施；使用 `superpowers:executing-plans`，遵循项目规则，不启用子代理、不自动 commit/push。第 9 节是已确认规格，第 8 节保留现场证据；第 8.4 节旧实施方向不执行。无需重新讨论已确认的成功边界和回读范围。

**目标：** 普通配置同步每次有变化时只上传，按业务成功/失败直接收尾；将云端核对集中到具备实际编辑权限的新一次 Space 进入流程，消除配置后普通上传替换 live Node 导致的离线闪烁。

**架构：** 复用现有云任务队列、submission、本地持久化和进入权限判断。正常上传准备成为纯本地流程，入口核对使用明确的调用路径；不设置全局“允许回读”开关，不新增持久同步队列，不改写整个恢复系统。保留本地事务恢复与身份保护，阻止普通上传间接调用远端恢复/导入。

**技术：** Swift/UIKit、现有 NetworkRequest/CloudSynchronizationManager、SQLite/本地恢复文件、Python 驱动的 Swift 行为夹具。规格为本文件第 9 节；共五个串行任务，中间只做相关回归，整轮稳定后构建一次。

### 10.1 接管基线与全局约束

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`；分支 `feat/device-scene-261028`；HEAD `185265a35b84f2df5f5ce802d827b3f315794136`。
- 当前 App 仅本文件为未提交修改，它属于本次分析/计划，应继续保留并更新。接管后先核对最新状态，不 reset/clean，不覆盖后来出现的其他改动。
- `SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk` realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- **SDK 最新核对已变化：** HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`（`fix: offline bugs`），工作区干净。此前第 8 节的暂存差异是历史状态，不照旧处理。本计划不写 SDK，不新增 SDK API。
- 数据库及 export JSON 结构变更清单：无。保留 accepted=服务器已接受、verified=已回读确认的含义，不能为了复用旧代码把 accepted 伪造为 verified。若需要任何表/字段/JSON/持久语义变更，先展示清单与 demo，停止该部分等待确认；普通内部函数调整无需再次确认。
- 不改固件、服务器、部署、依赖声明、品牌资源或用户文案；不扩大到 Site Props 专用更新/回显合同。这里的 Site 范围是现有全量配置上传及其中包含的 Spaces。
- 保留既有明确失联和心跳过期行为；不在上传成功时把所有设备设为在线，不添加 presence 复制机制。
- “业务成功”沿用当前 NetworkRequest 结果解析；失败含业务拒绝、HTTP 错误、断网和超时。本地保存失败也要报告，不能把保存失败假装成功。
- 正常只读页面加载、权限请求、用户主动选择云端恢复不属于上传确认 GET；保留用途，但不能让普通上传自动进入这些路径。

### 10.2 文件分工和核对重点

| 文件 | 本次责任 |
| --- | --- |
| `SunSmart/Common/Data/SpaceConfigurationSafety.swift` | accepted 直接收尾、旧回执兼容；普通本地准备与进入时远端核对拆开；解绑前上传同规则 |
| `SunSmart/Common/Cloud/CloudSynchronizationManager.swift` | 普通上传无 GET/导入、提交版本归属、入口回读意图与队列合并隔离、批量和恢复入口 |
| `SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift` | 保留本地事务/引用清理，把远端基线与成员恢复从普通清理链移出 |
| `SunSmart/Common/Data/ExportData.swift` | 核对 cloudSync 导出到 prepareUpload 的间接联网；仅必要接线，不改 export 结构 |
| `SunSmart/Main/Space/Controller/SpaceViewController.swift` | 实际编辑权确定后的单次入口核对；退出取消、子页返回不重复；普通数据变更上传 |
| `SunSmart/Main/Site/Controller/SiteViewController.swift` | 核对 selectSpaceAction/loadSpaceReqeust/intoSpace 的既有读取与新入口核对复用；批量/解绑同规则 |
| `SunSmart/Main/Share/Controller/ShareAuthorityViewController.swift` | 核对批量解绑上传是否走统一收尾，仅必要时修改 |
| `SunSmart/Main/Space/Model/SyncExecutionSession.swift`、`SyncExecutionSession+Result.swift`、`SyncRetryPolicy.swift` | 轮次真实变化才通知上传；配置失败重试不空跑、不重做已成功目标 |
| `SunSmart/Main/Group/Controller/GroupMembersViewController.swift` | 仅核对保存→同步→自动返回验收链，避免另加页面补丁 |

实施时需优先防住的五类输入，各归属下列任务：

1. 上传 A 期间又编辑 B，A 迟到成功只能确认 A（任务 1/2）。
2. 历史 accepted/prepared 回执、服务器成功但本地写失败、首次创建资源未落库（任务 1/2）。
3. owner/editor 尚未取得实际编辑权、选择只读、检查中途失权或退出（任务 3）。
4. 普通清理/导出/前台恢复/批量解绑间接触发 GET，或入队合并把入口策略传播给其他 Space（任务 2/3）。
5. Group 失败重试无新命令却成功、无变化再上传、局部成功数据被去重丢弃（任务 4）。

### 任务 1：恢复 accepted 直接确认，明确旧回执处理

**修改：** `SpaceConfigurationSafety.swift`。**测试：** `Tests/Group/CloudUploadConfirmationTests.swift`、`Tests/Group/SpaceRecoveryReceiptTests.swift`、`scripts/check_space_recovery_receipts.py`。

**接口：** 复用 `finishAcceptedSubmission(_ context: SpaceRecoveryState, space: SpaceData) -> Bool`，成功路径不得联网；保留 `resumeUpload(_:preparingUpload:)` 的远端核对能力，后续限制到明确进入/恢复用途。内部辅助函数的命名可由实施者按现有代码确定。

- [x] 添加行为用例并先确认旧实现失败：prepared → markSubmissionAccepted → finishAcceptedSubmission 应成功，本次 GET=0，确认提交版本，清理对应 submission；不生成 verified。
- [x] 添加 A=100 上传期间本地改为 B=101 的用例：确认时间为 100，101 仍 dirty；切账号/区域/Space 代次后旧成功不写新状态。
- [x] 调整统一本地收尾接受 accepted 或 verified；删除/恢复记录仅确认本次覆盖的版本，保留更新的修改与未完成项。
- [x] 旧 accepted/verified 只重试本地收尾。prepared/超时未知不得当成功，也不在普通入口联网；保留业务 dirty，解除对应旧 submission 对合法重新上传的阻塞，不能全局清目录或清除导入/身份保护。
- [x] 模拟 Space.save/恢复文件写入失败、重新加载后恢复：accepted 仍可本地收尾，不丢本轮成功证据，不重复提交已确认旧版本；多 Space 部分保存失败不回滚已成功项。
- [x] 执行 `python3 scripts/check_space_recovery_receipts.py`，要求 exit 0；只改已被本次需求替换的“accepted 必须回读”预期，保留进入核对、真实恢复、身份与删除保护用例。

**交付判定：** 直接确认及持久恢复语义独立通过；此时尚不能宣称普通调用链已经无 GET。

### 任务 2：切断所有普通配置上传的自动前读、回读和导入

**修改：** CloudSynchronizationManager、SpaceConfigurationSafety、SpaceSyncCleanupCoordinator；必要时 ExportData 及批量解绑调用方。**测试：** 现有 `Tests/Cloud/DeviceAddCloudBatchTests.swift`、`scripts/check_device_add_cloud_batch.py`；补 `Tests/Cloud/SpaceUploadFlowTests.swift` 和 `scripts/check_space_upload_flow.py`，复用已有夹具材料。

**接口约定：** 普通 `addSynchronizationHandle(operation:level:result:)` 默认且固定为服务器响应确认。若入口流程需要给 handle 增加内部确认策略，只增加运行时枚举（例如 `SpaceUploadConfirmation.serverResponse / entryReadback`）及显式入口参数；不持久化，不通过全局变量切换，不让普通调用方自动升级为入口回读。任务 3 消费该入口能力。

- [x] 先补完整调用链用例：执行生产云任务调度→本地准备/导出→上传→结果收尾，断言普通成功、业务失败、HTTP 失败、超时均为配置写请求 1 次、配置 GET 0 次、远端 restore/import 0 次。网络可替身，但不能同时把整个 prepare/resume/finish 替成恒成功来证明链路。
- [x] 调整云任务：普通上传不调用上传前 `resumeUpload(preparingUpload: true)`，成功后调用任务 1 的直接确认；失败保留 dirty 和同步失败，不因后续 GET 改判成功。
- [x] 查清并移出间接联网点：`SpaceSyncCleanupCoordinator.perform` 的 `recoverUpgradeBaselineIfNeeded`、`recoverCloudMembershipIfNeeded`、`verifySyncCleanupBaseline`，以及 `prepareUpload`→`readUploadedConfiguration`。普通清理只做本地检查/事务恢复/引用整理；需要远端处理的真实旧状态留到进入或显式恢复，不整体放宽保护。
- [x] 覆盖 syncSpace、syncSite 内嵌 Spaces、addSpaces、首次 siteAdd、解绑前 uploadBeforeUnbind、配网批次收尾、手动同步、后台/网络恢复和旧任务重试。首次创建正常成功保存返回资源，不配置回读；创建结果未知且缺少必要资源时明确失败，留到进入/显式恢复，不盲目重复创建。
- [x] Site 内只确认 payload 中的 Spaces；同 Space 重复待发任务继续合并。新增入口策略若存在，不与普通任务相互覆盖，不因 Site 批次给无关 Space 增加回读。
- [x] 验证旧回执的读写使用真实临时目录并重新加载；至少有一条用例把生产云调度与生产收尾逻辑串起来，补足现有两个脚本分别替身对方边界的缺口。
- [x] 运行 `python3 scripts/check_space_upload_flow.py`、`python3 scripts/check_device_add_cloud_batch.py`、`python3 scripts/check_space_sync_cleanup.py`；要求 exit 0，并记录仍被替身替代的 App SQLite/UIKit/网络边界。

**交付判定：** 普通一轮有变化上传只有一个配置写请求，成功/失败均不自动 GET/导入；相关本地恢复与清理仍有效。

### 任务 3：将核对集中在实际编辑权确定后的 Space 进入流程

**修改：** SpaceViewController、SiteViewController；复用任务 2 的显式入口上传能力。**测试：** 新增 `Tests/Space/SpaceEntrySyncTests.swift`、`scripts/check_space_entry_sync.py`；现有 `Tests/Space/SpacePresenceCallbackTests.swift`。

**接口约定：** 在现有 SpaceViewController 增加单一 `@MainActor private func reconcileEntryConfigurationIfNeeded()` 入口及本次进入的运行时任务/完成标记；退出时失效。复用现有角色、密码、云端/本地编辑权判断，函数名可按项目风格微调，但不得把触发点散放到各个配置页。

- [x] 用生产入口判断/调度代码测试：owner 与 editor 获得实际编辑权各触发一次；visitor、只读进入、编辑权冲突尚未解决、密码未通过都不触发；role 或 init 重置 disableEditorPermission 本身不能放行。
- [x] 在当前权限决策完成处接线，区分“尚未完成权限判断”和“确定不可编辑”；不要只依赖 canEditing，也不要让旧回读阻塞标记阻止入口解决其自身。离线进入保持既有离线能力，不偷偷转成上传成功；重新联网不能仅凭 network callback 重做入口流程。
- [x] 正常进入已有加载数据可用则复用，避免重复读取。必要远端核对、待上传处理及成功后的回读在本次入口内完成；无 dirty 不制造写请求。上传失败立即返回失败，不再回读；成功后的核对失败按入口失败提示，不进入无限自动重试。
- [x] 入口核对结束前不启动会与配置导入冲突的 Mesh 配置/自动修复；任务每次 await 后复核当前账号、Space、权限和进入会话。退出/切 Space/失权取消，迟到响应不能导入已进入编辑的现场。
- [x] 测试子页返回、反复 viewDidAppear、前后台切换、重复权限回调均不重复执行；真正退出后再次进入建立新会话。只读用户的正常数据加载不受影响。
- [x] 执行 `python3 scripts/check_space_entry_sync.py`、`python3 scripts/check_space_presence_callbacks.py`、`python3 scripts/check_space_membership_lifecycle.py`，要求 exit 0。提取生产方法测试，不另建手写的平行权限状态机来冒充验证。

**交付判定：** 只有具备真实编辑权的新入口能做上传回读；配置操作开始后不再有入口任务迟到替换节点。

### 任务 4：按真实同步结果上传，覆盖 Group 失败重试

**修改：** SyncExecutionSession、其 Result/Tasks 边界、SyncRetryPolicy 及 SpaceViewController 的变更通知入口，仅改行为所必需部分。**测试：** `Tests/Sync/SyncExecutionSessionTests.swift`、`Tests/Sync/SyncExecutionSessionFixtures.swift`、`scripts/check_sync_execution_session.py`，及任务 2 的云调用链夹具。

**接口约定：** 保留 `publishesCloudChange`、`finishRun(_:publishesCompletion:forcedState:)`、现有数据变更通知和 dirty 机制；变更判断属于本轮执行会话，不能变成持久新字段。只有产生新的配置/持久结果才推进版本，但本轮之前成员保存已产生的 dirty 必须照常提交。

- [x] 复现并断言：有成员修改的初次同步必须上传；部分 ACK 成功后失败/STOP 仍提交真实结果；零变化重复完成或空重试不制造新 timestamp/POST。
- [x] 复用已有保存/ACK 结果汇总本轮变化，不在每个 ACK 全量 export/哈希；收尾只发一次必要通知，保留更新内容的后续轮次。
- [x] 对现场 `GenericOnPowerUpSet(Restore)` 失败后重试加用例：失败目标生成并交付真实待发送 handle；成功需满足对应 ACK/结果条件，仍失败则不得自动成功返回。已成功且未变化的其他目标不重复同步。
- [x] 首先验证取消普通导入后旧对象问题是否消失；仅有复现证据才修改重试逻辑，不因日志疑点重写整个任务生成器。
- [x] 联合验证“两个原在线 Node→配置执行→普通上传成功/失败→返回 Group”：无 cloud import、live Node 身份不变、未过期在线状态不被上传改写；原本离线节点仍离线。不得仅以 UI 源码检查替代此行为证据。
- [x] 运行 `python3 scripts/check_sync_execution_session.py` 与任务 2 的 flow 回归，要求 exit 0；Scene/Timed 共用会话与上传路径纳入夹具输入，不机械复制五份相同测试。

**交付判定：** 无变化不重复上传，有变化和部分成功不漏上传；设备重试、云上传成功、在线状态三个结果保持独立。

### 任务 5：最终验证、构建与交付

- [x] 自行检查差异和调用图：普通入口不可经 export/cleanup/旧回执恢复绕回 GET；入口模式不可被普通合并任务继承。按本节五类风险复核，更新对应测试记录，不启用子代理。
- [x] 任务 1–4 已通过且代码仍适用的结果可复用，不全部机械重跑。额外运行 `python3 scripts/check_space_key_integrity.py`、`bash scripts/check_nordic_sdk_dependency.sh`、`git diff --check`，确认本地 Key 完整性保护及依赖未退化。
- [x] 一轮 Swift 修改稳定后运行一次代表性构建（不使用 Simulator、不自动操作真机）：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-upload-simplification CODE_SIGNING_ALLOWED=NO build
```

- [x] 默认无需五品牌全构建：本次是共享逻辑且不改 SDK API/依赖/资源；若实施实际引入跨品牌编译条件或资源风险，才扩展。SDK 映射错误先诊断，不静默换正式 workspace，不 clean/删共享缓存。
- [x] 更新本文件勾选项、最终 App/SDK revision、改动文件和验证结果；报告测试、generic 构建、真实运行各自边界。不得把现有回归通过声称为本次真机通过。

最短人工验收由用户执行：

1. owner/editor 正常进入 Space，另做一次只读进入；核对只有实际获得编辑权的入口执行必要核对，反复返回子页不重复。
2. 两台在线灯加入 Group，成功自动返回 Group，再返回 Lights：没有“先全离线后恢复”；原本真正离线的灯不被假设为在线。
3. 制造一条设备配置失败，重试：只补失败/必要前置命令，ACK 成功才成功；普通上传每轮有变化时 1 次配置写请求，无配置前读/回读。用户心跳和权限请求独立计数。
4. 普通上传模拟服务器业务失败或断网：显示失败、保留修改、不追加 GET；恢复后重试成功。再测一次上传等待期间继续编辑，新修改不被旧成功清掉。
5. Scene/Timed 各完成一轮同步，确认普通上传规则一致；真正退出再进入 Space 才重新执行入口核对。

**结束条件：** 五项任务完成、必要行为回归和 SunSmart generic 构建通过、交接记录更新；随后交付人工验收步骤并停止，不自动提交或操作真实设备。环境阻塞先完成其他可做工作，报告具体未验证项。

### 10.3 新 session 提示词

以下提示词可直接复制；已授权实施，不需要再确认第 9 节业务选择：

```text
@Superpowers 请实施已确认的“Space 上传流程简化”方案。

工作树：/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028
任务文档：docs/261105_1443_lights_offline_after_configuration_analysis_plan.md

先读 AGENTS.md 和任务文档顶部、第 9 节、第 10 节；第 8 节仅用于日志证据，第 8.4 节旧方案已废弃。用户已确认方案，本次授权执行第 10 节五项任务及必要验证，无需再次讨论成功边界或普通上传是否回读。使用 superpowers:executing-plans 单代理依序实施，不启用子代理。

核心要求：仅在新的 Space 进入会话、owner/editor 身份且实际编辑权限已确定后集中核对；有变化才上传，成功后回读。其他配置上传按服务器业务成功/失败直接收尾，无自动前读、回读或导入；失败/超时保留本地修改与失败状态。子页返回、前台/网络恢复不是重新进入。普通上传成功只确认实际提交版本，不清掉等待期间的新编辑；旧回执、本地保存失败、Site 内嵌 Space、解绑及批量上传均须覆盖。不要用新增 SDK presence 复制机制修补普通上传替换 Node。

先核对目录、分支、HEAD、未提交差异和 SDK realpath。交接时 App HEAD 为 185265a35b84f2df5f5ce802d827b3f315794136，只有任务文档未提交；SDK one-dev HEAD 为 2809c540be3b965a6a847ee4586ac46faf2ca2b5 且干净。状态可能已有变化，以现场为准，保留其他任务改动；不修改共享 SDK。

无需新数据库/export JSON 结构。若发现必须变更持久字段或语义，先按 AGENTS.md 提交清单和可解析 demo 再确认；普通代码细节由你决定，沿已确认范围继续。仅改 App，不改固件/后端/部署，不 commit/push/merge，不自动操作真机。

使用现有行为回归，并补计划要求的生产调用链边界测试，不能只改源码断言或让关键准备/收尾全用恒成功替身。完成必要验证后，用 SunSmartLocal.xcworkspace 对 SunSmart 做一次 Debug generic iPhoneOS、禁用签名构建，不用 Simulator。更新原任务文档，交付改动、自动验证、未验证项和最短人工步骤。不要为形式扩大重构或重复验证。
```

计划自查：第 9 节全部规则已映射任务 1–4；五类重点风险均有所属测试；任务 5覆盖构建与人工边界。计划阶段只核对源码/脚本/工作树并写文档，未声称任何新增用例或修复已经完成。


## 11. Space 上传流程简化实施与交接（2026-11-05 16:48）

### 11.1 完成范围

第 10 节五项任务已完成；第 9 节业务选择未改变。单代理执行并自行审查完整差异，未启用子代理、未 commit/push/merge、未操作真机。

- `SpaceConfigurationSafety.swift`：accepted/verified 均可直接确认各自提交版本，不伪造 verified；普通入口用 `resumeLocalUpload` 本地处理历史回执，未知 prepared 保留 dirty 后允许重新提交，未完成导入/身份/删除保护仍生效。真实旧身份未初始化时保留进入核对要求。`uploadBeforeUnbind` 同样无自动 GET；远端核对集中在显式 `uploadForEntry`/恢复边界。
- `CloudSynchronizationManager.swift`：Space、Site 内嵌 Space、addSpaces 和配网批次均使用纯本地准备及直接确认；只确认实际 payload 的 Space，部分本地保存失败保留其 accepted 回执。没有待上传版本时不制造写请求。首次 Site 创建缺少必要地址资源则失败；历史创建结果未知的普通任务不重新创建，进入核对时才读取 Site 并恢复资源。
- `SpaceSyncCleanupCoordinator.swift`：普通清理继续执行本地事务恢复、引用规范化和持久校验；移出升级基线、成员恢复和清理基线的网络读取。未核对的旧状态保持保护，等待进入/显式恢复，不放宽完整性约束。`ExportData.swift` 无需改动，原调用的 `prepareUpload` 已变为纯本地。
- `SpaceViewController.swift`、`SiteViewController.swift`：新增单一入口门控及任务，只有实际编辑权限决策完成、网络数据可用后才启动；保留密码、角色、云成员冲突和 Mesh 权限判断。进入期间禁用配置交互，完成前不启动自动拓扑修复；退出、失权、切账号后的迟到结果不能恢复编辑。已有正常加载结果直接传给入口复用。子页返回、前台及网络恢复不建立新进入会话。
- 入口任务通过云管理器的运行时 reservation 串行等待同 Site/Space 的在途写入，并暂缓冲突队列；释放后普通任务仍保持服务器响应确认，不继承入口回读。入口回读单次失败即收尾，不自动无限重试。
- `SyncExecutionSession`、`+Result`、`SyncExecutionEnvironment`：汇总本轮 ACK/结果及收尾，必要通知仅发一次；空轮次/重复完成不推进版本，原先已 dirty 的成员配置照常提交。部分 ACK 后失败或 STOP 保留已取得结果。Restore 命令生成与原重试策略通过行为验证，因此 **未修改 `SyncRetryPolicy` 或重写任务生成器**。
- `Database.swift` 增加 `saveCloudSyncOutcome`，只更新已有云确认时间和同步错误列，避免旧 Space 对象的整行保存覆盖上传期间另一对象保存的新版配置。确认时间单调递增，调用方的 `lastUpdate` 同步到最新持久版本。

**数据结构变更清单：无。** 数据库表/列、export JSON、回执字段及 accepted/verified 含义均未修改；上述新增内容仅为运行时调度状态和现有列的定向写入。SDK/API、品牌资源、本地化及依赖声明未改变。

实施判断记录：

1. 遵照用户单代理、不提交要求，以自行审查及本原文档交接替代技能默认的子代理审查/提交流程；自查不等于独立第二人 review。
2. 入口专用 API 与普通云任务分离，复用队列暂缓机制解决相互等待；若此边界遗漏调用方会有并发恢复风险，已用真实云管理器的重叠入口/普通批次回归核对。
3. 新增定向数据库 outcome 写入是满足“旧成功不覆盖新修改”所需的最小关联修改；没有新增持久机制，真实 SQLite 回归覆盖并发字段保留、单调确认、失败和重开。

### 11.2 自动化结果与边界

以下均在本次执行中运行并 exit 0；代码未发生相关后续变化的结果复用，未做全仓库机械重跑。

| 检查 | 结果与关键覆盖 |
| --- | --- |
| `python3 scripts/check_space_recovery_receipts.py` | 58 组 PASS 输出；accepted 本地收尾先观察到失败再通过；100→101 新修改、回执/本地写失败、代次/权限/导入保护、旧格式及真实文件重开。原先用于显式远端恢复的测试改名调用入口 API，保留严格 Key/配置冲突覆盖 |
| `python3 scripts/check_space_upload_flow.py` | 生产配置上传任务体→生产本地准备→真实临时目录 submission→生产收尾；业务失败、HTTP 层失败、超时及成功均 1 写/0 GET/0 restore；旧 prepared 重新提交，accepted/verified 只本地收尾；新修改、账号切换、批量部分保存失败。另编译并执行生产 SQLite outcome 方法，验证新名称/101 版本不被旧 100 回执覆盖、错误状态保存、失败写入及数据库重开 |
| `python3 scripts/check_device_add_cloud_batch.py` | 真实 Manager/Handle/配网批次调度；1/10 台、排队合并、STOP、离线恢复、上传中新一代、入口 reservation 与普通 Site 批次相互隔离、创建资源显式恢复 |
| `python3 scripts/check_space_sync_cleanup.py` | 本地引用、Profile 1…8、ALL alias、幂等性及非法快照保护通过 |
| `python3 scripts/check_space_entry_sync.py` | 提取生产入口门控和任务：owner/editor 一次、只读/密码/冲突/离线、加载完成后执行、重复回调、退出/切账号/失权后的迟到完成 |
| `python3 scripts/check_space_presence_callbacks.py` | 27 个生产 presence 回调场景通过 |
| `python3 scripts/check_space_membership_lifecycle.py` | 身份、离开/重进、坏配置恢复、保存失败及迟到回包隔离通过 |
| `python3 scripts/check_sync_execution_session.py` | 19 组 PASS 输出；空/重复收尾先失败再通过；既有 dirty、部分 ACK/STOP、Scene/Timed 共享结果和取消隔离；生产 `GenericOnPowerUpSet(Restore)` 工厂＋成功条件＋Session/Retry，连续失败真实重发，ACK 成功才完成，已成功目标不重发 |
| `python3 scripts/check_space_key_integrity.py` | 本地 Key、跨 Space 合并、Site 旧快照、身份/保存失败保护通过 |
| `bash scripts/check_nordic_sdk_dependency.sh` / `git diff --check` | 通过 |

夹具边界：HTTP/服务器响应、UIKit 导航及设备传输使用替身；flow 使用真实上传任务体和恢复文件实现，导出调用真实 prepare，**未同时将 prepare/resume/finish 替成恒成功**。本地引用清理/SDK 网络加载仍由专项夹具覆盖；flow 中两在线一离线的 Node 对象是运行时边界替身，用来验证普通上传没有调用导入、替换对象或改写状态，不代表真实 SDK 在线计时器验收。SQLite outcome 已执行真实文件数据库，不等同于完整 App 数据库/导入事务端到端验收。

执行中修复了已有批量夹具缺少 `standardProperties` 和 `preparingUpload` 参数的接口漂移；SQLite 夹具默认 clang module cache 不可写，改用该夹具临时目录后通过。没有删除共享缓存或修改 SDK。

### 11.3 构建、版本与剩余验收

- App 分支 `feat/device-scene-261028`，HEAD 仍为 `185265a35b84f2df5f5ce802d827b3f315794136`；本节所列源码、夹具、脚本及原任务文档为本任务未提交差异。没有覆盖其他任务改动。
- SDK realpath 仍为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，结束核对工作区干净；本次未写 SDK。
- 按第 10 节原命令执行 **一次** `SunSmartLocal.xcworkspace` / `SunSmart` / Debug / `generic/platform=iOS` / `CODE_SIGNING_ALLOWED=NO` 构建，16:48 得到 `BUILD SUCCEEDED`，exit 0；本机 SDK 为 iphoneos27.1。未使用 Simulator。使用专用 DerivedData `SunSmart-feat-device-scene-261028-upload-simplification`。
- 改动为共享逻辑；五品牌受同一逻辑影响，无新资源归属、品牌条件、SDK API 或依赖风险，因此按计划只构建代表 target SunSmart。
- **未验证：真实服务器业务/延迟响应、实际 BLE 配置和在线状态、UIKit 完整操作体验；其他品牌未单独构建。** 本轮未部署、未修改后端/固件、未安装或运行个人设备。

最短人工验收沿用第 10 节末尾五步：owner/editor/只读进入与子页返回；两台在线灯加入 Group 后返回 Group/Lights；Restore 失败后重试只补失败目标；普通上传失败及上传中继续编辑；Scene/Timed 各一轮并真正退出重进。预期普通每轮有变化仅一次配置写、无配置 GET/导入，失败保留 dirty，新修改不被旧成功清除；心跳/权限请求另计。

## 12. Review 四项修复与验证（2026-11-05 17:20）

四项 review 已修复，以下结果针对本轮代码；真实服务器、BLE 和 UIKit 完整交互仍待人工验收。沿用第 10 节已授权方案，未改成功边界，未使用子代理或提交代码。

### 12.1 修复与关联影响

1. **P1 入口权限被配置保护阻断**：云成员请求及 Mesh 编辑权探测按角色、密码和当前会话权限判断，不再用包含配置保护的 `deviceOperates` 阻止探测。配置恢复仍经过原有完整性/成员/回执检查；visitor、密码待验证及禁用编辑不能借此取得编辑权。身份限制的当前入口直接完成只读判定。
2. **P2 入口期间失权导致任务和页面未收尾**：完成回调先隔离取消、过期会话、退出和账号/区域变化；当前会话即使被降为 visitor、密码待验证或禁用编辑，也会清理任务、标记完成、恢复页面交互、保存及显示错误。只读结果不启动自动修复；权限被撤销的 `waitDeleted` 复用现有退出处理，并通知子页更新权限。
3. **P2 首次 Site 创建顺序**：入口 reservation 内先处理父 Site。已留下首次创建时间的沿用 `siteInfo` 恢复；尚未创建的复用生产 `CloudSynchronizationHandle` 执行 `.syncSite` → `.siteAdd`、业务响应及地址资源校验，成功后才核对 Space。首次创建使已有入口配置快照失效。创建失败或缺资源不继续 Space 流程，不立即重放暂缓队列；已发出的创建在退出途中仍可保存确认结果，但取消的入口不继续核对子 Space。同 Site 入口互斥，避免父创建重复。
4. **P2 恢复后的 Site 内存/持久状态不一致**：当前入口完成时重载页面持有的 Site；普通 `.syncSite` 在执行及“首次创建结果未知”判断前重载 Site，保留任务选中的 Space。三个 Site 失败写回入口共用 `saveCloudSyncFailure`，读取最新 Site 后保存错误，避免旧实例整行覆盖已恢复的上传时间及更新后的表单字段。Site 恢复的网络等待结束后也重新读取 Site，再写确认时间。

**数据结构变更清单：无。** 未新增或修改数据库字段、export JSON、回执结构或字段语义；新增方法只合并现有持久状态。业务代码仅修改 `SpaceViewController.swift` 和 `CloudSynchronizationManager.swift`；沿用已有测试脚本和夹具，更新本原文档。SDK、依赖声明、资源及品牌条件未修改。相关共享逻辑影响所有品牌，代表构建使用 SunSmart。

### 12.2 自动验证

先观察到四个失败：配置保护阻断云权限请求、当前会话失权未完成、入口第一条请求不是 Site 创建、独立 Site 实例恢复后下一次编辑仍被拒绝；修复后以下命令均 exit 0：

- `python3 scripts/check_space_presence_callbacks.py`：32 场景，新增受保护 owner/editor 的云及 Mesh 权限探测，以及密码/禁用/visitor 仍被限制且完成只读判定。
- `python3 scripts/check_space_entry_sync.py`：生产入口任务体；角色降级、密码、禁用编辑、撤权在成功/失败结果下均完成收尾，错误提示、只读不修复、活动 Site 刷新；退出/取消/账号/区域变化的迟到结果隔离。
- `python3 scripts/check_device_add_cloud_batch.py`：生产 Manager/Handle；首次创建先于 Space、延迟队列不重复创建、服务器拒绝、缺少资源、取消期间已发创建的确认保存；独立 Site 实例的恢复、下一次编辑及挂起任务失败不覆盖新状态。保留原批次、离线、排队合并及代次回归。
- `python3 scripts/check_space_upload_flow.py`：生产上传任务、真实磁盘回执及本地准备/收尾，另执行真实 SQLite Space outcome 写入；新 Site 错误保存方法直接提取生产实现。夹具补齐其依赖后通过。
- `python3 scripts/check_space_recovery_receipts.py`：58 组 PASS，包含旧回执、合法空配置、角色/身份、取消、重开和本地持久化失败恢复。
- `python3 scripts/check_space_membership_lifecycle.py`：成员状态、坏配置恢复、保存失败、迟到回包及账号隔离通过。
- `bash scripts/check_nordic_sdk_dependency.sh`、`git diff --check`：通过。

夹具边界：Manager 测试中的 Site 加载明确返回独立实例，避免共享对象掩盖问题，但数据库、HTTP、SDK 地址资源应用仍为替身；入口测试的 UIKit、权限元数据变化和服务返回为替身。真实 SQLite 检查针对 Space outcome，未覆盖整个 Site 数据库→SDK provisioner→服务器链路。恢复测试使用真实文件回执和生产恢复逻辑，不能替代真实服务验收。恢复/flow 夹具有已有的 `default will never be executed` 编译警告，无测试失败。

### 12.3 构建与交接

- App 分支仍为 `feat/device-scene-261028`，HEAD `185265a35b84f2df5f5ce802d827b3f315794136`；保留接手时所有未提交差异。本轮没有 commit/push/merge。
- `.local-sdk/nordic-sig-mesh-sdk` realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，工作区干净，本轮未写入 SDK。
- 沙箱内 `xcodebuild -list` 因 Xcode 服务访问限制误报 workspace 无效；核对文件和映射后，在沙箱外成功解析同一 workspace/scheme，未切换入口或清理缓存。
- 使用第 10 节命令执行一次 SunSmart / Debug / iphoneos27.1 / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建，17:19 获得 `BUILD SUCCEEDED`，exit 0。DerivedData 沿用该工作树专用目录。未使用 Simulator、未安装或运行真机；其他品牌未单独构建。

最短人工验收：

1. owner/editor 进入带未确认上传保护的 Space，分别在 Mesh 连接/未连接条件下操作；应完成权限判定并开始必要恢复，页面不持续锁定。
2. 入口核对期间让服务器降级角色、要求重新验证密码或撤权；应显示错误并完成只读/退出收尾，不能继续编辑。
3. 新建 Site/Space 后立即进入，观察 Site 创建及地址响应先完成；模拟创建失败后退出重进，应保留本地数据和可恢复状态。
4. 恢复一次创建结果未知的 Site，在 Space 已无需补传时直接做下一次编辑；应正常上传，Site 上传时间及地址资源不回退。退出及账号切换后旧回调不得恢复当前页面编辑。
