# Owner / visitor 进入 Space 的同步提示与 Mesh 连接分析

日期：2026-09-23。工作树：`fix`，当前 HEAD `89dc9c8a`（本轮分析期间 A 项已纳入此提交，原基线为 `2f874ed8`；本轮未执行提交操作）。本文记录两台手机的进入日志、本地 DEBUG 导出、owner / visitor 服务端读回，以及后续 A 项 App 修复和验证。A 项已完成 SunSmart generic iPhoneOS 构建；本轮 B 项只复核与规划，未由本任务自动操作真机。导出含网络和设备密钥，本文只记录字段与计数，不记录密钥值。

## 结论

1. 底部 `70/500` 与查找按钮之间的图标是设备配置同步按钮 `SpaceFunctionFooterView.syncBtn`，由 `NodeSyncStatusRefresh.request(nodes:)` 控制。visitor 的 70/70 个节点在本地 `nodePropertys.allSchedulerModelActions` 均为空数组；owner 的 70/70 个节点都有两个 Scheduler Setup Model 的状态容器，其中 68 个节点的有效条目与两台手机共有的旧式 `schedules` 内容相同，另两个节点为已知空容器。70 个节点均具有 Scheduler Setup Model，68 个节点属于已配置日程的目标组。`Schedule.schedulerSyncDifference` 在目标节点没有逐 Model 缓存时得到 `ownerModelUnknown`，`TimedSchedulerSyncDifference.needsSync` 将其视为 true，于是设备页显示同步图标。**这能解释 visitor 看到图标、owner 不看到的差异，但该图标本身不能证明设备配置实际不同。**visitor 没有编辑权限，同一按钮被禁用。
2. 17:19 时还存在一个独立、影响日程语义的缺口：启用的“午休”日程（ID 0，`selectTarget=2`，场景目标）在 owner 本地指向场景 `0006`，而 visitor 本地及 **owner、visitor 两种角色的旧云端响应**均为 `sceneAddress=null`。场景 `0006` 实际存在并覆盖五个组、68 个节点；两台手机的这些节点都有有效的 ID 0 日程条目。旧状态下，若 visitor 取得可信的逐 Model 状态，`Schedule.targets` 会把该日程视为不针对任何节点，`needsDelete` 可能把仍在节点上的有效条目判为待删。此前同时间戳的云端读取被两台手机跳过，故当时 owner 保留本地目标，visitor 保留空目标。两种角色旧读回一致，已排除本次 visitor 响应单独裁掉场景地址。App 已找到可产生 null 的具体代码路径：旧版 `Schedule.encode` 编码全局当前网络查得的 `scene?.number`，没有直接使用从数据库载入的 `sceneNumber`。在目标 Space 未处于全局活动网络时，这可能丢失原有场景地址；仍需历史上传摘要或服务端存储证据确认实际发生位置。
3. 此前仅凭 visitor 数据提出“`1000` / `1300` Model Publish 缺失直接导致图标”的判断已被 owner 导出推翻：**两台手机 70/70 个节点的 Publish 缺失情况相同**，而 App 在 Site 页面将运行时 `publishModelIDs` 设为空数组。Publish 缺失既不能解释两机差异，也不能据此要求重配全部设备。visitor 的云端响应同样缺少 Publish，只能说明本次该字段没有在 visitor 本地单独丢失。
4. 两份进入日志都只到自动连接同名代理 `SR9030BPIR` 的 `phase=connecting`；均无后续 BLE 连接回调、GATT 打开、Proxy Ready 或失败/超时。owner 能连接、visitor 不能连接是现场观察，**尚不能从日志定位 visitor 卡在 BLE、GATT、Proxy Filter 还是后续阶段**。两份本地配置的 Space NetKey/AppKey、70 个节点 UUID、Device Key、模型与绑定相同；visitor 云端响应的这些字段也与 visitor 本地相同。该证据降低了“visitor 拿到另一套 Space/节点密钥”的可能性，不能替代完整 Mesh 网络状态与连接阶段日志。上述日程差异及本地 4009 没有证据会阻断 BLE/GATT 连接。
5. 上述云端 null 指 17:34 与 17:59 的旧读回。owner 触发同步后，18:19 新云端读回为 `sceneAddress=0006`；18:28 visitor 比较视图与数据库也都为该目标，并已载入新时间戳 `1790158681`。因此 A 项现场数据已在云端及 visitor 本地收敛。visitor 的逐 Model 缓存仍 70/70 为空，底部同步图标继续出现与此独立状态一致；当前没有逐节点判因日志，不能断言这是唯一触发条件。用户确认图片更改是有意操作。
6. 按用户最新目标，本轮主线是防止以后 owner/editor 云同步及 visitor 导入再次丢失已有逐 Model 状态：补齐导出、服务端保存/读回、导入和本地重载的保真链路。现有“缺字段则未知、未知时读设备”的兼容规则应继续用于旧/异常数据，不能被当作新格式也必须丢弃完整状态的要求。上一轮优先扩展设备补读的方案撤回；现有问题数据的自动修复、后台补读和连接排障均不作为本轮实施前提。

## 证据与代码路径

- visitor `1711 enter space wil.txt`、owner `1746 owner enter space.txt`：两者 Space Info 均 HTTP 200，服务端和本地 `updateTimestamp=1790082755`，70 nodes、6 groups、3 scenes、2 schedules；导入均以 `serverUpdateTimestampNotNewer` 跳过。两个日志最后均有 `[MeshProxyConnection] ... phase=connecting` 与 `Connecting to SR9030BPIR...`，之后没有连接状态。不同手机的 CoreBluetooth peripheral UUID 不用于判断是否同一物理代理。
- visitor DEBUG 导出 `1719 Space_5F-Public area_20260923_171852_534+0800.json` 与 owner DEBUG 导出 `1747 Space_5F-Public area_20260923_174658_998+0800.json`：两份 `spaces[0]` 除 `nodes` 与 `schedules` 外的顶层字段一致；70 个节点按 UUID 对齐后，`elements`、Device Key、net/app key 绑定、地址、组归属及配置完成状态一致。节点 `schedules` 的内容按 ID 归一后 70/70 一致，28 个原始数组仅排序不同。其他节点可选属性存在差异，尚无证据把它们与这两个症状关联。
- 两份导出 `_debugInspection.spaces[0].rawLocal.mesh.nodePropertys`：visitor 70/70 的 `allSchedulerModelActions` 是 `[]`；owner 70/70 是两个 Model 容器。owner 68 个节点的容器条目合并后与其旧式 `schedulesData` 的 10 字节条目集合相同，另 2 个节点的容器明确为空。visitor 与 owner 比较视图均有相同的旧式节点日程；旧式条目不能代表逐 Model 的权威状态。
- `1734 space server data.txt`：`code=200`、`role=visitor`；`data.schedules[0].sceneAddress=null` 与 visitor 本地一致，owner 本地为 `0006`。云端 node payload 有旧式 `schedules`，没有 `allSchedulerModelActions`；现有 `ExportData.swift` 只序列化 `node.schedulerActions`，`ImportData.swift` 只恢复该旧式投影，本机 SDK 把逐 Model 缓存单独保存在 `nodePropertys.allSchedulerModelActions`。因此靠重新导入这份云端响应不能恢复 visitor 的逐 Model 状态，且会保留空场景目标。
- `1759 owner server space data.txt` 与 visitor 服务端返回均为 `code=200`，同一 Space ID、`updateTimestamp=1790082755`，70 nodes、6 groups、3 scenes、2 schedules。顶层 data 差异只有 `role`、owner 响应独有的 `visitorPasswd` 字段，以及 18 个节点的 `props.brightness` 值；后者包括 10 个 0.55→0.54、5 个 1.0→0.0、2 个 0.0→1.0、1 个 0.29→0.0。未输出密码值。按 UUID 对齐的节点在排除 `props` 后 70/70 完全一致；两次响应的日程和全部其他配置字段完全一致，ID 0 的 `sceneAddress` 都是 null。两次采样相隔约 25 分钟，亮度差异不能当作角色裁剪或配置缺失。
- `1819 new space server data.txt` 与 `1828 Space_5F-Public area 1_20260923_182809_961+0800.json`：visitor 导出与新服务端响应的共有 Space 顶层字段完全一致，名称、图片 ID 8、时间戳 `1790158681` 和两个日程目标一致；用户确认图片更新有意。visitor 数据库 `app.schedules` 中 ID 0 的 `sceneAddress=6`，不是只在导出编码时出现 `0006`。70 个节点的 UUID、Device Key、地址、模型、绑定和组归属均一致；35 个节点 `schedules` 数组顺序不同，按 ID 归一后 70/70 内容一致。全部节点本地 EnOcean 场景是四个 `0000` 默认槽位而服务端及 owner 旧本地为空数组；visitor 旧本地已有相同默认槽位。同步判定代码未读取这个字段，故此差异不能解释本次同步图标。
- 新 visitor 原始本地 `nodePropertys` 中，70/70 个 `allSchedulerModelActions` 仍为空；旧式 `schedulesData` 与 17:19 visitor、17:47 owner 均为 68 个节点各两条、另两个节点为空。原始字节因条目顺序而不同，但每节点按 10 字节条目归一后 70/70 相同。`_debugInspection` 无数据完整性问题，状态为 `joined` / `active`，无待导入、待删除。新 visitor 的本地 NetKey/AppKey 与 owner 旧本地相同；原始节点 `elements`、`appKeys`、`netKeys` 的编码字节可能不同，但解析后的结构 70/70 相同。
- `Space.export` 从当前目标 Space 的数据库读取 `Schedule.load(...)`，再使用 `jsonEncoder.encode(schedules)`；修复前 `Schedule.encode` 的 `sceneAddress` 来自 `self.scene?.number.hex`，而 `self.scene` 查询的是全局 `MeshNetworkManager.instance.scenes`，不是此次导出加载的 `meshNetwork.scenes`。因此导出目标 Space 与全局活动 Space 不一致时有确定的丢字段条件。现有两份现场日志没有覆盖产生云端数据的那次上传，不能据此断定它是唯一原因。
- `DeviceLightsViewController.updateUI` 请求 70 个节点的状态。`NodeSyncStatusRefresh` 对每个节点计算 `groupNeedsSync || node.getNeedSync()`，输入不可用时也会用 `finishUnavailable()` 回调 true。`Node.getNeedSyncGroup` / `getNeedSync` 检查日程；`Schedule.schedulerSyncDifference` 对目标节点缺少逐 Model 状态返回 `.ownerModelUnknown`，其 `needsSync=true`。这一链条足以形成 visitor 的可见提示，但日志没有打印每个节点的实际判定来源，其他保守兜底是否同时触发尚未排除。
- `Schedule.scene` 依赖 `sceneNumber`，`Schedule.targets(node:)` 依赖场景关联的组。visitor 旧数据中的 `sceneAddress=null` 曾令“午休”失去目标；18:28 本地为 `0006` 后，该风险已在此 Space 的当前数据中消失。`TimedSchedulerDeletePolicy.shouldDelete` 只在逐 Model 状态已知且条目有效、但节点不再是目标时返回 true；visitor 当前状态未知，不能宣称曾实际派生删除任务。
- visitor 入口另有 `[SpaceConfigurationSync] stage=cleanupPreparation error=4009`：`SpaceViewController.reconcileLegacyProximityLightingTopology` 对 visitor 调用了需要写权限的 `SpaceSyncCleanupCoordinator.prepare`，返回本地 `noSpacePermission`，不是 HTTP 4009。visitor 检查状态为 joined、active，无待导入/删除和阻塞；现无证据说明 4009 触发设备同步图标或 Mesh 连接失败，但它是不必要的错误日志。

## 逐 Model 状态缺失的根因追查

### 1. 信息在 App 导出边界就被省略

owner 的 DEBUG 导出同时包含两种视图：`_debugInspection.rawLocal` 直接检查本地数据库；`spaces[]` 调用 `Space.export(...)` 生成比较视图。前者拥有 70 个节点、140 个逐 Model 容器；后者的 70 个节点均没有逐 Model 字段，只含总计 136 条旧式日程。18:19 服务端响应也是 136 条旧式日程、没有逐 Model 字段；18:28 visitor 本地逐 Model 容器总计为 0。

`ExportData.swift` 的 Space 导出和单节点导出都仅遍历 `node.schedulerActions`，写出 `nodes[].schedules`。它没有编码 `node.allSchedulerModelEntrys`，因此没有记录每个条目属于哪个 Element / Scheduler Setup Model，也没有记录某个 Model 已确认没有条目。DEBUG 原始数据库附件不属于云端上传内容。该缺口在 App 导出阶段已可确认，不需要假设服务端按 visitor 角色裁剪；服务端能否保存未来新增字段仍需另行验证。

### 2. 导入只恢复旧式投影，并会丢掉既有的本地状态

`ImportData.swift` 的 Space 导入和单节点导入都把 `nodes[].schedules` 写入 `node.schedulerActions` / `scheduleIds`，没有设置 `allSchedulerModelEntrys`。SDK 中该属性默认 `[:]`，数据库加载也将 `schedulesData` 与 `allSchedulerModelActions` 分开处理，不从前者推断后者。

Space 完整导入还有明确的失效路径：`network.forceRemove(node:)` 调用 `node.delete()`，删除旧 `nodePropertys`；随后从 JSON 解码新 Node、恢复旧式日程，再通过 `network.add(node:)` → `node.save()` → `savePropertys()` 保存。新对象没有逐 Model 状态，所以保存为空。这意味着不止首次加入的 visitor 会未知：任何角色在实际应用完整云端导入后，原有的逐 Model 状态也可能被清掉。这是代码路径结论；现场没有“某台手机导入前已知、导入后未知”的成对快照，不能把该扩展条件说成已在现场复现。

### 3. 判定依赖迁移了，云端数据格式没有跟上

Git 历史中，2026-07-27 的 `2891ec03` 将 `Schedule.needsSync` 从检查 `node.schedulerActions[id]` 改为检查目标 Scheduler Model 的 `allSchedulerModelEntrys`，并检查另一个 Model 是否仍有残留。2026-07-31 的 `eafc6e7e` 将未知等情况明确拆成 `schedulerSyncDifference`。当前导出/导入的旧式 `schedules` 编解码则仍沿用原有结构，没有增加 Model 归属。

逐 Model 判定本身有必要：同一日程 ID 可出现在普通 Scheduler 和 Light LC Scheduler；`rebuildTimedSchedulerActions()` 只挑选逻辑 owner 的有效条目形成兼容视图，因此扁平数组不能反推另一个 Model 是空、未知还是有残留。不能靠给两个 Model 都复制旧式条目来补齐，否则会伪造设备状态。

### 4. 现有补读不能保证恢复

`SpaceSchedulerReadCoordinator` 在 Space 加载时创建，候选选择没有 owner/visitor 角色分支；它通过 `MeshAPI.getSchedule(index:nil, ...)` 逐 Model 读取设备。读成功的 `SchedulerStatus` / `SchedulerActionStatus` 会保存逐 Model 状态；SDK 对整节点读失败保留旧式投影并清掉该节点的逐 Model 结果，避免使用不完整读取。

但当前唯一注入的自动请求来自 `TimedViewController.viewDidAppear`，`SpaceSchedulerReadQueue.request()` 又在 Mesh 未连接时直接返回。Devices 页面出现没有发出此请求，也没有在该协调器中注册连接 Ready 后重新请求。故只看设备页、进入 Timed 时尚未连接，或一直不能连接，都可能长期维持未知。已有 owner 状态可能来自此前读设备、成功设置日程或新入网初始化；仅凭导出无法确定它是哪次操作生成的。

这也明确了与连接问题的关系：Mesh 未连接会阻止补读，从而让未知状态持续；现有证据没有证明逐 Model 状态缺失会造成 BLE/GATT 连接失败。

### 5. 按用户要求再次复核：修正证据边界

本节保留再次复核的证据。用户随后明确以未来云同步/导入不丢数据为目标；以下设备读取保护用于约束旧数据兼容和状态可信度，不作为强制补读新格式完整快照的理由。

- **状态确实没有跨云端传递。**重新统计 owner 为 140 个 Model 容器，其中 32 个已知空、108 个含条目；visitor 为 0。旧式条目两端均为 136 条。SDK 本地持久化测试可保留“已知空”，当前样本没有逐 Model 数据解码长度错误。
- **没有传递不等于可以把远端快照直接作为本地设备验证结果。**`TimedSchedulerOwnerPolicyTests.testAllUnknownSchedulerModelsNeedAuthoritativeRead` 明确要求状态仍未知的云端导入节点读取设备；该测试没有要求带完整、有效逐 Model 状态的新格式导入后仍必须未知。`testUnknownSchedulerModelDoesNotDelete` 明确禁止依据不完整 Model 状态生成删除。`ScheduleServer.deleteSchedule`、日程编辑、退组等入口也依赖该未知检查。把旧式数组或未经版本/来源验证的云端状态填入 `allSchedulerModelEntrys` 会使这些入口跳过补读，存在真实的行为变更风险。
- **完整导入使本地状态失效的路径成立。**但它同时避免沿用另一配置版本的旧设备状态。既有测试没有规定完整导入必须无条件保留缓存。因而本轮不将“强行保留旧缓存”作为修复，也不扩大修改网络身份、事务和导入保护。
- **补读生命周期缺口已用实际生产类复现。**隔离运行 `SpaceSchedulerReadQueue` 原始源码，以连接和读取边界替身注入：①未连接时 request，随后变为连接，发送批次仍为 0；②第一批完成前断连，再连接后剩余节点不继续；③显式再次 request 才恢复；④stop 后晚回调不再推进。前两项说明需求丢失/恢复缺口，后两项说明可复用现有机制。这不是 BLE 真机验收。
- **现有隔离回归通过。**`check_timed_scheduler_persistence.sh` 中持久化/整节点读完成测试通过；`check_timed_scheduler_single_owner.sh` 中 owner/cleanup/删除策略测试及调用链契约通过。契约检查不能代替实际 App/设备执行。
- **扩大自动读取前还有明确的共用队列风险。**SDK `MeshProxyMessageCommand.addMessage` 在忙时追加句柄，但会将新的非空回调替换进全局回调槽。现有补读仅在开始前检查 `isBusy`，不能保证后续前台操作不会改变补读回调。这是源码确认的机制风险，尚未做真实并发故障注入，不能写成已发生的现场原因。
- **现场边界。**现有资料仍不能证明 visitor 图标唯一来自日程未知，也不能确定手机安装包与当前工作树完全同版；新增 DEBUG 聚合判因应区分日程未知、真实差异与 `SyncUnavailable`。没有服务端实现或新增字段往返验证，不能承诺其会保存新增字段。

## 修复方案与实施状态

### A. 日程目标数据一致性

owner/visitor 角色的当前读回均为空，已排除本次按角色裁剪。先在 App 侧修复已确认的编码风险：`Schedule.encode` 保留已存储的 `sceneNumber`，上传前仍用目标 Space 的场景集做完整性检查，不能以全局活动网络的查询结果决定是否写出字段。同时对照最近一次 owner 上传前后的脱敏日程摘要及服务端存储值，确认历史数据是在 App 导出还是后续存储时丢失。对这份已受影响的 Space，由 owner 确认目标场景后通过现有同步机制修复云端数据；不能从节点条目或同名场景自动写回，因为还需保留身份、权限及时间戳完整性。回归覆盖非活动 Space 导出、owner/visitor、场景目标、缺字段旧数据、同时间戳内容差异及失败重试。

### B. 未来云同步与导入的逐 Model 状态完整性（最新方案）

**目标：owner/editor 当前已保存的逐 Model 状态，经过导出→云端保存/读回→visitor 首次或再次导入→数据库重载后，语义等价。**正常新格式导入不依赖再读取全部设备才能恢复上传前已存在的状态。云端传递的是上传端已记录的设备状态，不声称接收端刚完成了实时读取。

**范围：**优先修改 App 的 Space/Node 编解码和现有上传读回校验，并配套服务端字段保存约定。已有异常 visitor/Space 的自动迁移与修复、自动补读范围扩大、共用消息队列改造、BLE 连接修复、同步 UI 改版均移出本轮。设备读取保留为旧数据缺字段或明确异常时的既有后备路径。

#### B1. 补齐版本化字段，原有格式继续兼容

1. 在节点同步结构中增加可选的版本化逐 Model 状态；服务端代码核对后，字段确定为 `nodes[].custProps.schedulerModelStates`，复用已有 JSON TextField，不增加数据库列。容器以节点下的 Element 地址、Scheduler Setup Model 标识定位，保存该 Model 的原始日程条目。
2. 保留旧的 `nodes[].schedules` 作为旧客户端兼容字段，新字段保留 Model 归属、相同日程 ID 在不同 Model 的独立内容，以及已知空容器。尽量复用 SDK 现有条目编码与本地持久化格式，避免再次发生时间、月份、action、sceneNumber、transitionTime 的有损转换。
3. 明确三种语义：旧格式没有新字段表示未知；新字段中某 Model 缺席表示该 Model 未知；Model 容器存在但条目为空表示该 Model 已知空。不得用空数组给所有 Model 补造已知空状态。
4. 新字段只能记录上传端已经拥有的状态。导出目标 Space 的稳定数据快照；不从全局活动 Space 借数据，不凭业务日程推断设备 Model，不为导出额外读取设备。

#### B2. 确认服务端保存与版本混用规则

1. 在服务端实现或测试环境核实节点新字段会被存储并在 owner/editor/visitor 读回中保留；现有 HTTP 200 或原有字段往返不能代替此验证。未验证前不宣称 App 单改即可完成全链路修复。
2. 约定旧客户端再次上传时的处理：缺字段不能被服务端无条件解释为清空已有新字段，也不能不看相关配置变化就沿用旧快照。需结合节点身份、Model 结构及相关日程内容/版本决定保留或明确失效，并让新客户端能识别未知状态。
3. 若服务端不能支持安全的旧客户端写入兼容，则必须先确定能力/版本发布边界；不能在未协调的情况下加入使正常用户持续同步失败的新必填字段。
4. 本轮不手工修改现场 Space JSON，不依赖节点内容或同名场景自动回填现有坏数据。

#### B3. 导入并恢复到新 Node/Model 对象

1. Space 完整导入和单节点导入共用同一编解码/校验 helper，避免两条入口只修一条。先校验新字段，再进入既有导入事务。
2. 校验节点/Space 身份、Element 所属、Scheduler Setup Model 存在、容器重复、条目长度和 0–15 索引；不能用其他节点或旧实例的 Model 引用填充。
3. 节点重建后，将合法容器重新绑定到新 Node 下的实际 Model，恢复 `allSchedulerModelEntrys`，再走已有 `savePropertys()` 保存。已知空容器必须随重启保留。
4. 兼容旧 `schedules`，核对新旧视图能否表达同一逻辑日程。新格式自相矛盾或结构损坏不能静默当旧格式成功导入；沿用现有事务失败/完整性反馈，避免部分覆盖。没有新字段的合法旧数据仍按既有路径导入并保持未知。
5. 不无条件继承导入前的缓存，也不要求有效的新格式导入后必须再读设备。现有已知/未知判定、owner/cleanup 选择和删除语义继续适用：有效导入的数据提供已知状态，真正缺失的 Model 仍受未知保护。

#### B4. 用上传读回防止再次静默丢失

1. 复用 A 项提交回执机制，新增逐 Model 状态的规范化摘要；按节点身份、Element/Model、日程索引比较，忽略数组顺序，保留已知空与缺失的区别。
2. 新版本提交若声明携带新字段，服务端读回缺字段、丢容器、丢条目或改内容时不能确认该提交成功；保留现有失败/重试状态，输出脱敏原因。
3. 旧回执仍可读取，无新字段的旧数据不因新增校验被拒绝。同时间戳下新字段有差异也须纳入既有导入/读回决策，不能只因时间戳相等而忽略。
4. 字段保存/读回能力确认后再启用该校验，避免把服务端暂不支持的字段直接变成所有用户的新同步故障。

#### B5. 回归与影响边界

| 回归场景 | 验收结果 |
|---|---|
| owner 导出→模拟服务端保留→新 visitor 导入→数据库重载 | Model 身份、全部条目和已知空状态语义相等；不连接设备也能恢复快照 |
| 完整导入重建 Node、单节点导入、应用重启 | 使用新实例绑定，逐 Model 状态不再被默认空值覆盖 |
| 非活动 Space 导出、同一 ID 在多个 Model | 不串 Space，不合并不同 Model 的条目 |
| owner/editor/visitor、首次加入/删除后重新加入 | 授权范围、网络身份校验和现有写权限保持 |
| 旧字段缺失、部分 Model 未知、已知空、无日程 | 三种语义明确，旧格式可导入，不把未知标成已同步 |
| 服务端丢字段/条目、同时间戳差异、失败重试 | 新提交不被误确认；已有重试和旧回执兼容 |
| 旧客户端更新已存在新字段的 Space | 按已确认的服务端兼容契约保留或明确失效，无静默降级 |
| 日程创建、编辑、删除、退组/换组 | owner/cleanup 选择、真正未知状态的保护和真实残留检查通过原回归 |
| 控制灯、场景、Group、DFU | 本轮不新增 Mesh 请求或修改队列；相关共享逻辑行为回归通过 |

以当前 70 节点样本生成脱敏夹具，再加多 Model 同索引不同内容及已知空用例；核心验收是“新格式云端往返且重载后等价”，不能只测编码器输出某个字段，也不能靠后续读设备把缺失补好后才算通过。同步检查既有 `elements` / Model 绑定信息往返相等；目前样本未证明其他 Model 结构字段丢失，不据此扩大修复范围。

优先只改 App 公共 helper、导出/导入调用及回执摘要，不改日程执行算法、权限、UI 或 BLE/DFU；SDK 只有在现有公开 API 无法无损转换/保存时才做最小补充。实施后运行相关导入导出/回执、Scheduler 持久化与单 owner 回归，再按实际变化构建；如需 SDK 公共 API，记录 `one-dev` revision 与正式 release 发布待办。

**现场处理：**用户自行决定删除 visitor 后重新导入，不为现有坏数据设计自动迁移。重新导入能恢复完整状态的前提是：升级后的 owner/editor 已上传含逐 Model 状态的新数据，服务端已完整保存，新 visitor 使用支持该格式的 App。若仍导入当前缺字段的旧云端数据，删除重加本身不会生成这些 Model 状态。

**状态：App 侧 B1/B3/B4 已实施，回归和构建见文末。B2 的服务端新字段透传已通过本地实际映射函数验证；旧客户端覆盖兼容仍待服务端实施和联调。**上一版的自动补读和队列治理不在本轮范围。

### C. Mesh 连接阶段

获取两机在 `Connecting to SR9030BPIR...` 之后至少 30 秒的连续日志，尤其 visitor 的 BLE connect 成败、GATT 服务发现、Proxy Filter 确认、Ready/关闭/超时；记录手机 provisioner 地址、IV/sequence 与网络身份的脱敏摘要。若现有日志不足，先加受 `#if DEBUG` 限制的阶段诊断，再复现。只针对确认的失败阶段提出 BLE/SDK 或本地状态修复；涉及本机 SDK 时先核对 `SunSmartLocal.xcworkspace` 的实际映射及远端发布版本。

### D. visitor 入口 4009

作为独立的小修，若确认它影响用户反馈或排障，在 Space 入口仅让 owner/editor 执行引用清理，visitor 保留只读加载路径；增加角色回归。它不是前两项的既定根因，不应代替日程与 Mesh 排查。

## 验收边界

A 已提交于 `89dc9c8a`；后续核对时 B 的 App 改动已收录于 `b11d810e`，当前 `fix` 包含该提交。服务端按用户要求只做分析。C、D 未实施。两机 UI 状态、日程行为及 Mesh Ready 仍需现场验收。现有两份进入日志都不能证明连接的最终结果。

### A 项实施记录

- `Schedule.encode` 改为编码日程中已存储的 `sceneNumber`，即使当前全局活动网络不是目标 Space，仍能保留场景目标。
- 云端导出前，按本次目标 Space 导出的场景集校验场景日程的目标。缺失、指向不存在场景或重复日程 ID 时拒绝上传并保留同步错误；本地备份仍可保留原始配置供人工检查。
- 新上传回执单独保存按日程 ID 归一的目标摘要。读回时若服务端将 `sceneAddress` 变成 null，保留待确认回执并按现有机制重试；正确读回后才确认。旧版没有摘要的回执仍可解码，遵循既有兼容行为。
- 回归已覆盖非活动 Space 编码、空/错误目标、日程顺序变化、角色差异、读回丢字段、失败重试及旧回执解码。`SpaceConfigurationIntegrityPolicyTests`、`check_space_recovery_receipts.py`、`check_schedule_scene_target_export.py` 均通过；`SunSmartLocal.xcworkspace`、SunSmart Debug generic iPhoneOS 构建通过，SDK 映射指向 `one-dev`。未运行真机。
- 当前资料没有产生服务端这份历史数据时的 owner 上传请求体、读回摘要或服务端存储审计；两份进入日志均无上传事件。因此 App 编码风险已修复，但不能声称已确认历史 null 的唯一成因。
- owner 已在手机上通过改名触发一次云同步。`1819 new space server data.txt` 读回同一 Space，名称变为 `5F-Public area 1`，时间戳由 `1790082755` 推进到 `1790158681`；ID 0“午休”的 `sceneAddress` 从 null 变为 `0006`，与此前 owner 本地导出完全一致。ID 1 日程不变，Space NetKey/AppKey、70 个节点身份和静态配置、组、场景及 SpaceData 均未变化。`imageId` 由 7 变 8，用户确认这是有意更改。节点差异为时间戳、亮度、两处时区缓存及 37 个日程数组排序变化，日程条目按 ID 归一后没有语义变化。
- 18:28 visitor 导出进一步证明 A 项目标字段已从云端落到 visitor 本地数据库。它不证明 owner 手机已安装本次编码补丁，也不能追溯历史 null 的产生阶段；旧版 App 在目标 Space 处于活动网络时同样可能导出 `0006`。visitor 底部“需要同步”继续出现，与本地逐 Model 日程缓存缺失的 B 项问题一致；新服务端节点响应仍不携带该缓存，因此 A 项收敛不会自动消除图标。现有导出不能提供图标实际判因或 Mesh 连接阶段结果。

### B 项服务端核对与实施记录（2026-09-23）

#### 服务端事实

仓库 `/Users/maginawin/Developer/SunSmartDev/sunsmart-services`，核对 revision `28084fc`，本轮未修改仓库、未读取凭据、未连接数据库或调用线上写接口。

- `sitespace/views.py` 的 `sync_space_props` 经 `RolePermissionInst.get_writer` 后，调用 `present_spaces_sync` → `present_node_sync` → `build_node_data`。Site 全量上传也复用此链路。
- `services_4_space.py` 中 Space 级和 Node 级 `schedules` 均直接 `json.dumps` 保存；`snippet.py` 直接 `json.loads` 返回。未发现对 `sceneAddress` 的字段筛选或按 visitor 角色裁剪。因此服务端当前源码不支持“visitor 单独丢目标”的猜测，但仍不能追溯旧历史 null 的唯一来源。
- `build_node_data` 是显式字段列表，直接加节点顶层 `schedulerModelStates` 会被丢弃。已有 `Node.cust_props` TextField 可保存整个 `custProps` 对象；`node_outgoing` 会解码并返回它。`get_space` 对所有角色调用相同 `node_outgoing`，角色分支处理分享密码，不改节点日程字段。
- 现场 `1734`、`1759`、`1819` 三份云端响应各有 70/70 个节点包含 `custProps: {}`，说明现场接口也已返回该扩展列；尚未据此验证线上保存非空新快照的行为。
- **已复现的兼容缺口：**`build_node_data` 使用 `json.dumps(safe_get(node, 'custProps', {}))`，旧客户端缺字段时生成 `{}`；`present_node_sync` 又通过 `update(**node_data)` 全量覆盖此列。新客户端刚上传的 Model 状态会被随后旧客户端的全量上传清掉。
- 另一个入口 `sync/nodeprops` → `node_update` 在判断 JSON 列时使用原始 camelCase `k`，而列清单包含 snake_case `cust_props`，会让 `custProps` 绕过 `json.dumps`。当前 iOS 云同步未调用此接口；如服务端兼容补丁覆盖该写入口，应同时正确编码该字段。本轮不把这一旁路假设为现场根因。

#### App 已实施的最小链路

- 复用已有公共 Swift 文件，未调整 target/资源/依赖声明，也未修改 SDK。SDK 仍为本地 `one-dev`、revision `ebbe1c9`。
- `SchedulerModelSnapshot` schema 1 绑定 Node UUID、单播地址和 Device Key 指纹；每个容器记录 Element 地址、`1207` Model ID 和十字节原始条目（JSON 中为 Base64）。还记录 `legacyEntriesData`，使原有扁平视图在新格式导入时也保留原始月份和渐变时间；原有 `nodes[].schedules` 继续输出，供旧客户端使用。
- 新字段缺失走旧兼容路径，Model 未知；`models` 中缺席的 Model 仍未知；显式空容器为已知空。导出仅复制已存在的缓存，不发 Mesh 请求、不推算设备状态。
- Space 和单 Node 导出共用 adapter。Space 导出读取目标 Space 的稳定网络快照；本地缓存损坏、索引越界或身份不完整时拒绝输出新快照，避免把异常当空状态上传。
- Space 完整导入在事务前验证新字段和新 Node 的 Model 绑定；重建 Node 后恢复容器，再走原有数据库保存。事务读回检查实际持久化状态；失败走既有回滚/待恢复路径。单节点导入复用同一验证与恢复代码。
- 校验版本、节点/密钥身份、Element/Model 所属、重复容器、条目长度、重复索引、SDK action 合法值及新旧扁平视图一致性。保留各 Model 独立观察值，不把残留 Model 或未知 Model 合并成业务期望值。
- 新上传回执记录规范化的 Model 状态，读回丢字段、丢已知空容器或改变内容不能确认成功；旧回执缺少新增属性仍可解码。身份和权限保护沿用既有机制。
- 同时间戳下，远端新摘要与“上次导入/上传确认的云端摘要”不同才触发内容更新；该摘要单独存放，不与实时本地缓存比较。这样既能接收同时间戳的新内容，也不会仅因本机后来读取了设备就反复导入旧云端缓存。已有本地待上传业务修改仍按原规则保护。

#### 服务端兼容补丁建议（待确认实施）

应在发布到混用旧客户端的环境前处理，不能把当前 App 修复称为版本混用闭环已经完成：

1. 在已有节点更新处合并 `custProps`，保留其他功能的命名空间；`schedulerModelStates` 由新客户端明确提供时按新值替换并校验，不从业务日程或旧 `schedules` 推导逐 Model 状态。
2. 旧客户端没有该字段时，只有节点身份（含 Site/Space、UUID、Device Key、地址及重建代次）、Scheduler Model 结构/绑定与相关日程观察值未变化，才能保留已有有效快照。名称、图片等无关元数据变化不应抹掉它。
3. 身份/结构/日程内容变化或无法证明兼容时，明确移除旧的 `schedulerModelStates`，让新 App 按未知处理；不能沿用旧缓存伪造新设备或新配置已知。旧客户端无法提供逐 Model 的新观察，保证范围需明确依赖支持此格式的写入端。
4. 覆盖 Space/Site 全量更新及使用 `custProps` 的节点单独更新入口，保证 JSON 正确编码；保持现有 writer 校验、createdTimestamp 新旧判断、缓存失效及其他字段更新规则。并发读旧值再写新值需要在该节点更新的事务/锁内完成。
5. 回归新 owner/editor 上传与各角色读取、旧端只改名称、旧端改变日程/身份、显式未知/空容器、其他 `custProps` 命名空间、失败重试和并发覆盖。线上部署版本及数据库保存必须另做接口集成验收。

#### 验证与人工验收

- `check_scheduler_cloud_roundtrip.py --server-root .../sunsmart-services`：已通过。执行 App 的实际 snapshot adapter、SDK 实际条目 codec 和属性保存/加载代码片段，以及服务端实际 `build_node_data` / `node_outgoing`。70 节点合成夹具复用现场容器规模：140 个容器，32 个已知空、108 个含条目；无现场密钥或原始个人数据。覆盖十六个索引、跨 Model 同索引不同内容、顺序规范化、月份/渐变时间保真、旧数据、部分未知及坏数据拒绝。
- 边界：Node/Element 对象及数据库传输使用隔离替身；上述结果不等于真实 App SQLite 事务、Django ORM、在线接口或真机验收。
- 已有 Scheduler 持久化/完整读取、single-owner/cleanup、节点同步状态刷新，以及 A 项非活动 Space 场景目标编码回归通过。`check_space_recovery_receipts.py` 新增 owner/editor 上传丢字段、丢空容器、直接读回、失败重试、旧回执及 visitor 写权限保护用例通过，已有回执/角色/取消/导入准备回归通过。
- 最终代码通过 `SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iPhoneOS / `CODE_SIGNING_ALLOWED=NO` 构建；DerivedData 为 `SunSmart-fix-cli`。期间修正了一处闭包类型推断编译错误，最终复验退出码为 0。未运行 Simulator、真机或线上接口；共享文件没有品牌条件分支或 target/资源/SDK API 变更，本轮使用代表 target SunSmart 验证。
- `git diff --check` 通过。上轮验证时 App 代码与本文档尚未提交；后续核对已收录于 `b11d810e`。服务端和 SDK 工作树保持无改动。版本混用保护以及线上往返仍为明确未完成项。
- 最短人工验收：新版 owner 在目标 Space 上传一次 → 确认云端每个支持 Scheduler 的节点含 `custProps.schedulerModelStates` → 新版 visitor 首次加入或删除后重新加入 → 在未连接 Mesh 的情况下导出并重启再导出，比较节点身份、逐 Model 条目及空/未知语义。同步图标还会受其他配置差异影响，应检查实际判因；不能仅凭图标消失判定保真，也不能把本轮结果当作 BLE 连接修复。

### 后续核对：含义、引入时间与版本混用（2026-09-23）

#### 缺少新字段是否意味着日程不能导入

不是。`spaces[].schedules` 保存业务日程定义，`nodes[].schedules` 是旧的扁平设备缓存；二者在旧链路中已经传递。新增 `custProps.schedulerModelStates` 保存各个 Scheduler Setup Model 的已知观察状态及原始兼容投影，补齐 Model 归属、已知空与未知的区别。缺字段时 editor/visitor 仍能按旧路径导入业务日程，但无法由云端恢复逐 Model 状态；当前逐 Model 判定会将相关状态视为未知，可能继续显示需要同步或在编辑前要求既有设备读取。不能据此断言 Space 导入失败，也不能断言设备上已经下发的日程被删除或停止执行。

通过现有权限模型，新字段由具有上传权限的 owner/editor 随正常 Space/Site 同步提交，visitor 只读取。上传端也必须实际拥有相应 Model 的状态；单纯升级不能把其原有未知缓存变成已知。

#### 能定位到的历史起点

| 时间 / 提交 | 代码变化与意义 |
|---|---|
| SDK `68781c6`，2025-04-24 | 增加 `allSchedulerModelEntrys` 及本地缓存。App 的云端传输仍是扁平日程；此时已经存在传输保真缺口，但不能将所有后续 UI 症状追溯为此日已发生。 |
| App `2891ec03`，2026-07-27 | `Schedule.needsSync` 从读取 `node.schedulerActions[id]` 改为读取逻辑 owner 的 `allSchedulerModelEntrys`，并检查 cleanup Model。相同提交没有补齐云端编解码。这是本次“云端导入后因逐 Model 缺失而需要同步”可确认的代码引入点。 |
| App `eafc6e7e`，2026-07-31 | 引入 `schedulerSyncDifference`，细分未知、缺条目和残留状态；其父版本已使用逐 Model 判断，因此不能把 7 月 31 日误当成最早起点。 |
| App `b11d810e`，2026-09-23 | 补齐新格式导出/导入/持久化读回与上传回执；服务端旧客户端兼容仍未实施。 |

已从 `2891ec03^` 与 `2891ec03` 提取实际 `needsSync` 函数，用相同隔离输入执行：旧扁平日程与业务定义相同、逐 Model 缓存缺失时，提交前返回 false、提交后返回 true；给提交后的逻辑 owner 正确条目和 cleanup 已知空容器后返回 false。该证据验证条件与代码差异，不代表真实设备运行。首次受影响的发布版本/安装包仍需对照发布记录，Git 日期不等于上架日期。

#### 是否所有旧版本都需要升级，是否必须重新加入

- 不能笼统说每个旧版本、每台手机都会出现相同提示。早于上述判定切换的版本主要使用扁平缓存；之后包含该切换而没有云端修复的版本，在缺少 Model 状态时有本次风险。曾完整读取设备的本地副本可能暂时不表现出来，owner 完整导入重建节点也可能受影响。
- 要通过云端完整共享快照，写入端和读取端都需要识别新格式。旧 visitor 只读不会通过配置上传清空云端，但不会因服务端保留新字段就自动获得新版导入能力。
- 升级后的现有 visitor 通常可直接正常刷新。当前 `SpaceData.update` 能依据新增摘要处理同时间戳内容变化，并在完整导入时恢复新 Node 的 Model 状态；无需默认解除绑定。此前重新加入步骤用于干净的首次导入验收，不是所有用户的迁移要求。
- 如用户选择重新加入，应先确保新版 owner/editor 已上传有效快照且云端读回完整，再升级 visitor 后重新加入。云端仍缺字段或 visitor 仍是旧 App 时，删除重加不能生成缺失状态。

#### 不修改服务器时的可行范围

现有服务端已能透传非空 `custProps` 的本地代码测试通过，现场三份响应也有该列。若能够确保某 Space 的所有配置写入设备/账号都使用修复版本，可先不改服务器：升级全部 owner/editor 写入端 → 由持有完整状态的一端上传并确认读回 → 升级接收端并正常刷新。允许旧 visitor 暂时只读，但其自身体验尚未修复。仍需上线环境往返验收。

只升级一部 owner 手机不足以排除另一部旧 owner/editor 再次覆盖；修改名称、图片等导致的全量上传也能触发 `cust_props={}`。新版客户端的读回校验只验证本次上传当时的结果，不能阻止以后另一个旧客户端覆盖。定期重传或重新导入不是可靠的并发兼容措施。

如必须长期允许旧 owner/editor 继续写入，需要服务端保留/失效规则，或在服务端拒绝不支持版本的相关写入；仅新 App 无法约束独立旧客户端的请求。服务端补丁也无法重建旧客户端从未提交的逐 Model 数据：涉及日程/身份/结构变化且无法证明一致时应失效为未知；要获得旧端新配置后的完整快照，仍需升级写入端。A 项旧编码器可能再次丢 `sceneAddress` 也是独立的旧写入风险，单独保留 Model 字段并不能修复它。

本轮只增加上述分析与历史证据，未继续修改 App、SDK 或服务端业务代码；未执行线上写入或真机操作。

### 回退为扁平 `schedulerActions` 的可行性核对（2026-09-23）

**结论：可继续使用扁平兼容视图，但不建议恢复为所有设备的唯一同步依据。**当前现场 owner 导出重新统计为 70/70 个节点各有两个 `1207` Scheduler Setup Model；它们需要保留同一 index 在不同 Model 中的独立状态。7 月 27 日的逐 Model 判定承担真实功能，云端遗漏传输是需要补齐的另一段链路。

#### 只回退同步判断也会影响实际操作

`Schedule.needsSync` 同时被以下入口用于挑选实际写入目标：`getNeedSyncDatas`、`Node.getNodeSyncSchedules`、`GroupServer.swift` 中的绑定日程过滤，以及 `ScheduleServer.setEnabled`。因此全局改用扁平匹配并不只影响 footer 图标：判为不需要同步的节点可能不再生成 Scheduler 清理/写入任务。

App 的 `rebuildTimedSchedulerActions` 按当前逻辑 owner 提取兼容条目，不保留非 owner 的独立残留。两种状态可以形成相同的扁平值：目标 Model 的 index 0 都正确，但另一 Model 分别为空、或还保存旧 index 0。扁平值无法区分这两种状态，也无法证明另一个 Model 已经清空。

本轮从 `2891ec03^` 和当前 `HEAD` 提取实际判定函数，编译并执行隔离输入，结果如下；所有行的旧扁平条目都与业务期望相同：

| 输入 | 扁平旧判定 needsSync | 当前逐 Model 判定 needsSync |
|---|---:|---:|
| 目标 Model 正确，其他 Model 已知空 | false | false |
| 目标 Model 正确，其他 Model 有残留 | false | true |
| 旧扁平值仍匹配，但当前目标 Model 缺条目，条目在另一 Model | false | true |
| 云端导入后逐 Model 状态全未知 | false | true |

这证明直接回退会漏报已知残留/目标错位；隔离输入不是现场固件运行复现。

#### 功能影响边界

- **编辑和同步日程：**即使时间、动作相同，也可能需要清理其他 Model。仅比较扁平值会跳过必要工作；非 owner 清理失败后的重试同样可能被漏掉。
- **入组、退组、切换自动/手动 Profile：**当前 `Turn On` 在自动组使用 Light LC Scheduler，在无组或 Manual Control 情况使用普通 Scheduler。Model 迁移前后 entry 内容可以相同，扁平值没有迁移完成与否的信息，可能留下旧位置或漏掉新位置。
- **删除：**仅回退 `needsSync` 不会自动移除当前逐 Model 删除前读取和完成确认规则，用户仍可能遇到未知状态补读；若连这些规则一起回退，可能漏查其他 Model 的残留，削弱“全部相关 Model 清空后才完成删除”的保护。
- **现有设备执行：**仅改变 App 判定不会立即删除已下发到设备的日程；风险集中在随后是否正确识别差异、下发、迁移、清理与重试。普通开关灯、BLE 连接等不因这个判断替换而直接获得修复。
- **单 Model 设备：**在确认 Composition 只有一个 Scheduler、旧字段完整且身份/状态有效的约束下，可另外设计受限兼容；不能推广到当前双 Model 现场，也不能把旧字段缺失一律解释为已知空。

#### 建议

保留逐 Model 的操作判断和当前 B 的云端保真修复；扁平字段继续服务旧协议兼容。若只是需要调整 visitor 对未知状态的展示，可另行评估只读展示层，但不能让同一个展示降级规则改变写入/删除任务，也不能把未知描述为已经验证同步。

若考虑回退是为了避免服务端改造，优先采用前述“控制所有 owner/editor 写入端升级”的受控过渡方案；现有服务端已有新字段承载位置。允许旧写入端长期并存则需要兼容策略，回退扁平判断不能等价保留当前多 Model 功能。

本轮仅分析并更新本文档，未回退或修改任何 Swift、SDK、服务端业务代码；未构建或执行真机测试。

### 新版上传后的现场服务端数据核对（2026-09-23，21:02 文件）

**结论：`2102 new sspace server data.txt` 符合本次 A/B 的云端数据预期。**现场响应已实际携带完整逐 Model 快照，且与此前 owner 原始缓存相等。它补充了前文仅验证本地服务端映射的证据；新版 visitor 的实际导入、App 数据库重载和 UI 状态仍未由这份文件证明。

核对 App 为 `fix` / `b11d810e`。文件是 `code=200` 的服务端响应，角色为 owner，同一 Space 的更新时间为 `1790168499`（UTC+08:00，2026-09-23 21:01:39）。未调用线上接口、未写服务器、未输出原始密钥。

| 核对项 | 结果 |
|---|---|
| 规模与身份 | 70 个节点、6 个 Group、3 个场景、2 个业务日程；相对 18:19 响应，Space UUID、网络密钥及全部节点身份、设备密钥、地址与 Model 结构未变 |
| 新字段 | 70/70 节点包含 `custProps.schedulerModelStates`，全部为 schema 1 |
| Model 完整性 | 每节点两个 Scheduler Setup Model，140/140 容器均存在；32 个已知空、108 个含条目，当前样本没有缺席的未知 Model |
| 条目规模 | 28 个容器各两条、80 个容器各一条，共 136 条；每个 Model 的条目索引、长度、动作值校验通过 |
| 与 owner 原始缓存比较 | 按节点身份、Element 地址和条目 index 归一后，140/140 容器与 17:47 owner export 的 `rawLocal.mesh.nodePropertys[].allSchedulerModelActions` 逐字节相同，空容器也相同 |
| 旧格式兼容 | 70/70 节点的 `legacyEntriesData` 与 owner 原始 `schedulesData` 字节内容相等；合计 136 条，与云端 `nodes[].schedules` 数值字段一致 |
| 日程场景目标 | ID 0“午休”保留 `sceneAddress=0006`，场景存在；ID 1 是 Turn On 日程，`sceneAddress=null` 合法。目标校验通过 |

#### 相对 18:19 云端响应的其他差异

- Space 名称从 `5F-Public area 1` 改回 `5F-Public area`，更新时间推进；图片仍为 8。
- 70 个节点新增快照；60 个节点时间戳变化；26 个节点 `props.brightness` 变化；39 个节点的旧日程数组顺序变化，按 ID 归一后 70/70 节点日程语义相同。
- Group、场景、业务日程、SpaceData 完全相同；节点除上述字段外未变化。未发现这次上传引入的目标丢失、Model 缺失或配置语义变化。

#### 本轮验证与边界

直接将这份现场文件输入当前生产 `SchedulerModelSnapshot` 和场景目标校验代码：全部节点通过 schema、UUID/地址/Device Key 指纹、Composition 所属、条目及旧格式投影校验。随后执行生产 snapshot restore/export adapter、SDK 实际十字节 codec 和 SDK 属性保存/加载代码片段，重新创建 Node/Model 对象后再导出，140 个容器及兼容条目均相等。

以上使用隔离 Node/Element 和数据库传输边界；不等于新版 visitor 真机导入、完整 App SQLite 事务或重启验收。现场服务端响应证明新字段本次确已返回，未检查服务端数据库原始行或本次 owner 上传请求体；与历史 owner 缓存完全相等是本次保真判断的额外证据。

下一步只需新版 visitor 正常刷新后导出，确认原始本地逐 Model 状态仍为 140 个容器（32 空、108 有条目）并与这份云端快照相等；可按用户选择重新导入，但无需将解除绑定作为必需前提。若图标仍出现，应以实际差异判因，不能继续仅凭图标推断 Model 再次丢失。此前旧 owner/editor 全量上传可能清空 `custProps` 的版本混用风险仍存在；这次正确读回不能证明后续旧端覆盖已被防护。

本轮仅分析实际数据并更新本文档，没有修改 App、SDK 或服务端业务代码，没有执行 App 构建或真机操作。
