# Restore Device Data 恢复耗时与命令流程分析

日期：2026-09-20。本文前半部分保留修复前的日志和版本分析；用户确认后的实施与验证记录见末尾“修复实施”。分析阶段未修改业务代码，实施阶段未操作真机。

## 结论

1. **已定位现场最主要的长等待：单设备恢复队列混入其他节点的邻居配置，但 Fast Add transmitter 不支持发送到这些节点。** 日志中的 `Sending Network PDU` 不等于已经通过蓝牙发出。第一次有 3 个、第三次有 2 个这样的请求；按 SDK 的 10 秒 ACK 超时，分别引入约 30 秒、20 秒串行等待，与观测耗时吻合。
2. **第二次的 7.62 秒不能作为完整恢复的健康基准。** 该次在 Unack 调光之后收到迟到的 Firmware Status，SDK 提前结束追加队列；组订阅及邻居配置没有发送，后续明确报告同步失败，由用户手动 SYNC 补齐。
3. **三次均有首条 deferred Profile 命令回复没有被队列确认的问题。** LightLightnessRangeSet 已收到成功 Status，但队列最后仍显示 missing。现有代码会等待单地址约 8 秒的外层定时器，再依赖已更新的业务状态兜底成功。Fast Add 完成回调与 reset 的顺序存在 delegate 覆盖竞态，是高度吻合的原因；缺少 delegate/逐命令时间日志，不能把竞态实际发生时序及 8 秒精确实测写成已证实。
4. **不能据此断言这些问题由 1.2.3 之后新引入。** 仓库 1.2.3 标签已经包含以上核心代码。当前 SDK 确有普通 Proxy 连接等待上限从 15 秒变为 80 秒的变化，但本组三份日志没有显示这段连接等待被触发。当前慢点已查明；与旧版的同条件性能差异仍未闭环。

## 证据范围与版本

- App：`fix`，HEAD `ddc1e8a9`；分析前工作树干净。
- 本地 workspace：`SunSmartLocal.xcworkspace`，`.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- 本地 SDK：`a971027e08f9775d7a3f071a06f89be1c38ecc96`，无未提交修改；正式 workspace 的 Package.resolved 也锁定该 revision。
- 用户提供较快基准：App 1.2.3。仓库 annotated tag `1.2.3` 指向 `047b9d68a92f86d467e072a2cb1c6c2f3b423074`，日期 2026-09-10，工程 MARKETING_VERSION 为 1.2.3；SDK pin 为 `a6246b1b0409824a3227a9c7cad8140219feb182`。
- 日志未提供正在测试的 App 构建号/SDK revision。结论以日志可见行为与当前对应源码交叉核对，不声称已证明安装包与工作树逐字一致。
- 原始文件：`/Users/maginawin/Desktop/tmp/restore log 1st.txt`、`restore log 2nd.txt`、`restore log 3rd.txt`。文档只摘录必要业务证据，不复制密钥或整段原始报文。

## 可直接计算的时间

| 日志 | 固件（用户提供） | 本次新主地址 | 配网成功 → SDK 添加成功 | 其他节点邻居请求超时 |
| --- | --- | --- | ---: | --- |
| 1st | 1.3.38 | 003D | 40.870667 秒 | 0025、002B、0034，共 3 次 |
| 2nd | 1.3.38，同一设备再次恢复 | 0040 | 7.618385 秒 | 此阶段没有；但追加配置被提前跳过 |
| 3rd | 2.1.1，另一设备 | 0043 | 31.387806 秒 | 002B、0037，共 2 次 |

时间锚点分别为日志 1 的 L14/L1277、日志 2 的 L36/L982、日志 3 的 L14/L1032。上述时间**不包含扫描、初次连接、配网本身，也不包含“添加成功”后继续运行的 Profile 恢复和人工 SYNC**。三份日志大多数行没有时间戳，不能据此给出页面从点击到最终完成的精确总耗时。

按当前源码扣除 3×10 秒、2×10 秒的预期超时后，第一次和第三次的该阶段剩余约 10.87 秒和 11.39 秒。这个接近的余量支持“跨节点超时是主要增量”的解释，不构成逐阶段实测，也不能据此比较两个固件的真实性能。

## A. 跨设备命令放入错误的发送通道：已证实

实际链路：

1. `DeviceRestoreViewController.addDevice` 在配网完成后迁移旧节点数据及 Proximity Lighting 引用（L2275–2286）。
2. `appendMessagesBack` 除了恢复本设备，还将 `lifecycleResult.syncDatas` 中所有非本节点的命令追加到 SDK 的 `appendMessages`（L2359–2365）。
3. SDK 配网成功时把全局 transmitter 切换为 `MeshFastAddDeviceManager`（`MeshFastAddDeviceManager.swift` L1259）。
4. 该 transmitter 的 `send(data,pdu,type)` 只按 PDU destination 查找 `addingOperations` 中正在添加的设备及其 element，然后执行 `try operation?.send(...)`（L296–303）。本页面每次传入一个恢复设备，其他存量节点没有匹配 operation；这里既不发送，也不抛错。
5. Access Layer 仍建立 ACK context，重发、等待超时；`MeshLibManager.initConfig` 设置 10 秒 ACK 超时（L1452）。SDK 失败回调移除当前追加任务后继续下一个（FastAdd L904–916），因此多个不可发送任务串行累加。

现场证据：

- 1st L1048–1210：向 0025 配置邻居 `[0028]`，最后 timeout/cancelled；L1211–1225：002B；L1226–1262：0034。
- 3rd L991–1005：002B；L1006–1020：0037。
- 每个请求均有一次 Access 层重发。五个等待区间均没有普通 Proxy 的 `log: ->` 写出记录；更关键的证据是上述 transmitter 源码不具备对应路由。不能用日志 `Sending Network PDU` 认定远端收到命令后不响应。
- 第一、第三次本恢复节点的邻居设置都返回成功。第一份后续普通 Proxy 的 LightCTLGet 对这些存量节点也能收到响应，因此不应首先归因于设备离线或固件不支持。
- `cancelled` 紧跟 Access timeout，是 SDK timeout 内部取消 handle 后产生的错误回调，不代表用户点击取消。

另一个放大因素：`ProximityLightingLifecycleCoordinator.makeResult` L328–352 使用旧/新拓扑的全部候选节点生成 `syncDatas`，不是仅使用 `affectedDeviceAddresses`。L382–393 依各节点当前缓存差异生成任务，因此一次恢复还可能带入既有未完成的邻居同步。没有恢复前 topology/cache 快照，无法判定这五个请求各自属于必要迁移还是历史积压。

这类队列还有 45 秒附加阶段总超时（FastAdd L656）。更多跨设备未响应任务可能碰到总预算；本组三次未见该总超时，属于源码风险，不是现场已发生事实。

## B. 第二次漏发追加配置：已证实，解释“快但需再 SYNC”

日志顺序：

- 2nd L963–964：向 0040 发送 `LightLightnessSetUnacknowledged`。
- L977–980：0041 返回先前的 `FirmwareUpdateInformationStatus`；该地址是本节点第二个 element。
- L982：立即记录 SDK 添加成功。
- 这段之前没有 C003 的 8 条组订阅，没有本设备的邻居设置，也没有末尾的 AttentionSet。
- L1279–1280：App 明确记录 `subscribeGroup(C003),otherSync` 尚未完成。
- 用户 L1486 点击 SYNC；L1495–1613 才发送 8 条订阅，L1614–1628 才完成邻居设置。

对应机制：

- `MeshMessageHandle.allAddresss` 对 Unack 返回空数组（`MeshProxyMessageCommand.swift` L521–524）；`isFinished` 通过已回复数+未回复数与地址数比较，初始即 `0 >= 0`（L580–581）。
- FastAdd 的接收分支在消息匹配前执行 `guard let messageHandle = appendMessages.first, !messageHandle.isFinished else { deviceAddSuccessHandle(); return }`（L1031–1034）。
- 因此等待 Unack 的 0.3 秒本地推进期间，只要收到本节点的迟到消息，就可能将整个追加队列当作完成；`resetPropertys` 会清空剩余任务（L563）。现场 Firmware Status 的顺序与此完全吻合。

这不是把完整恢复优化到了 7.62 秒，而是未发送完整配置。此问题必须与耗时修复一起处理，不能以更早显示成功作为性能验收。

## C. 已 ACK 的首条 Profile 命令仍等队列结束：现象证实，delegate 竞态高度可疑

三份日志都先收到成功的 `LightLightnessRangeStatus(min:655,max:65535)`，随后出现：

`Ignore deferred handle false ... operation=true, response=false, reliableOperation=true ... missing=<当前设备>`。

对应位置：1st L1281–1296；2nd L989–1010；3rd L1039–1076。下一条才开始 LightLCModeSet。三次均没有 `Retry deferred restore task`；这里不是重复发 Range Set。

当前 deferred 配置使用 `ackMessageTimeout:7`（Restore L1642）。`MeshProxyMessageCommand.sendMessages` 的外层定时器为 `allAddresss.count + acknowledgedMessageTimeout`（L276），单地址约 8 秒。即使底层已收到 ACK 并更新 node 状态，若队列 delegate 丢了回复，也要等外层定时器将 handle 标记 missing，再由 App 的 reliable operation 状态兜底成功。

可疑生命周期链：

1. FastAdd 在全部设备完成时先调用 `deviceAddFinishBack`，然后才 `reset()`（L249–251）。
2. App 的 addFinish 立即启动 deferred Profile 队列（Restore L2495）。
3. 新队列异步注册自己为 `MeshLibManager.messageDelegate`（ProxyCommand L126–150）。
4. FastAdd 的 reset 仍会将该 delegate 恢复成自己的旧值（L270–271），有机会覆盖新队列。

首条命令丢失队列响应、之后命令恢复正常，符合这个竞态；但原始日志没有 delegate identity、注册/清理时刻和命令计时，**实际覆盖发生点尚需最小诊断或受控回归确认**。`Local ... not bound to key` 也不能单独作为该次超时的结论：日志已证明消息解密、Status 和 node 状态更新成功。

## 命令和完成判定核对

- 本设备基本链路为 Composition → AppKey 添加/Model 绑定 → Sensor/Firmware/Composition Hash 查询 → 温度范围查询/调亮 → 组订阅/邻居 → Attention → deferred Profile。日志中对应当前设备的配置 Status 主要为 Success，未见 Profile 的负 ACK。
- Profile 的亮度范围、LC Mode/Occupancy、手动覆盖、自动亮度选项、7 条 LC Property、SceneStore、PowerUp Restore、运动灵敏度均可在日志找到；第一/第三次不是固件普遍拒绝恢复命令。18 是计划任务数，不能直接等同于最终发送 18 个网络请求。
- SceneRecall 被有意过滤（每次 count=1），不是漏发异常；Attention 参数 6 是设备提示时长，代码收到 Status 后即继续，没有主动等待闪烁 6 秒。
- 1st/2nd 分别有 43 条 Model App Bind，3rd 有 42 条，其中 0x1206 存在重复绑定；全部有成功回复，属于可后续检查的冗余，不足以解释 20–30 秒差值，不建议先靠减少绑定掩盖主要问题。
- `shouldMarkRestoredNodeSyncFailed` L1114–1117 在存在待同步邻居时直接返回 false，会跳过对其他恢复项的检查；注释仍称跨节点邻居由外部同步，与当前追加跨节点命令的行为不一致。这是独立的成功判定漏洞；本组三次没有足够证据宣称它导致了某次错误成功。
- `添加成功` 是 SDK Fast Add 阶段完成，不是所有恢复配置已完成；HTTP 200 仅表示云端请求成功，不是设备恢复完成证明。

## 与 1.2.3 的比较边界

| 项目 | 1.2.3 → 当前的结果 | 能否解释本次慢点 |
| --- | --- | --- |
| Restore 页面追加跨节点命令、deferred 流程 | 已存在；页面实际差异仅错误提示 Key | 能解释当前样本，不能作为新版新增证据 |
| SDK FastAdd 路由、Unack 完成分支 | 两 revision 源码无差异 | 同上 |
| 邻居 lifecycle 全候选任务生成 | makeResult/makeSyncDatas 范围无变化 | 不支持“新版刚扩大该队列”结论 |
| 普通 Proxy 连接预算 | ProxyCommand 从 15 秒改为 readyResultTimeout=80 秒 | 新版确实可能在连接不就绪时更久；本组日志无触发证据 |
| SDK TAI 时间变换 | 有变化 | 本组恢复未见 TimeSet/日程恢复，不是已见慢点 |
| Site Trigger Zone 合并、缺失 Group 清理、Sensor Publication TTL | 周边同步有变更 | 本组三次无法证明这些分支导致耗时变化；lifecycle 显式 topologyPlan 路径不会走普通查询的 Site 合并 |

跨节点 append 在 App `1d1f3cdb`（2026-09-03）已经加入，该提交是 1.2.3 标签祖先，不能误报为 1.2.3 之后的回归。

另外，日志大量 App 出站 Access Network PDU 的 TTL 为 **127**，而 FastAdd 代码传入 TTL 0。当前 Lab 全局 TTL 覆盖具有最高优先级，与此一致；仅据日志不能读取实际 Lab 开关值。它会影响重发间隔及空中转发负荷，是 A/B 对比必须控制的条件，但不会修复“transmitter 找不到 operation”，也不是本次多次 10 秒超时的必要前提。ACK/control PDU 的 TTL 5 与 Access 请求 TTL 应分开看。

三次本地 export 的已记录耗时约 7.9–8.7 毫秒，未发现它们构成几十秒阻塞的证据；不能因此排除日志未覆盖的其他阶段。

## 建议修复边界与最短验证

以下是待实施建议，本轮没有修改代码：

1. **先修正确发送路径。** FastAdd append 仅放本恢复节点及其 element 的命令；其他节点的必要邻居更新保持 pending，在普通 Proxy 恢复就绪后通过现有跨节点同步机制处理，单独记录结果。保留引用迁移的一致性，不能直接删除这些同步需求或伪装为已同步。也不建议先缩短全局超时。
2. **修 Unack 的完成推进。** Unack 只由发送完成路径推进当前任务，迟到 Status 不得结束整个 append 队列；推进需确认仍为原任务，避免延迟回调推进了下一条。覆盖现场“Unack 后迟到 Firmware Status”的时序。
3. **修 FastAdd → deferred 的回调所有权交接。** 在通知完成前完成旧队列清理，或明确按 owner 恢复 delegate；不能用任意增加 sleep 解决。覆盖首条 Range Status 已到却未记成功，以及连续任务交接。
4. **收紧完成判定。** 排除由外部处理的邻居任务时，只排除该项，不能跳过订阅/Profile 等必要恢复项。跨设备未完成状态与本设备完成状态分别保留。

最小自动回归应覆盖：本机恢复队列不接受他机目的地址；他机 pending 不丢失；迟到响应不跳过订阅；首条 ACK 能立即推进；失败/取消仍保留必要待同步状态。实现稳定后按项目规则做相关回归及一次代表 scheme generic iOS 编译；这些均不能代替真实 Mesh 验收。

用户侧最短对比：同一设备、相同 Space/Group/Profile/Path/Zone 初始数据、相同 Proxy 和 Lab TTL，分别用 1.2.3 与当前构建手动重置后恢复。记录点击、配网完成、本设备追加完成、普通 Proxy Ready、Profile 完成、最终 UI 状态的时间。两个固件分别观察；恢复前状态须可复原，连续恢复改变地址和 pending topology，不能只因为硬件相同就视作同条件 A/B。

诊断优先记录每阶段起止、命令类型/目标地址/耗时、发送 owner、回复是否被当前任务消费；DEBUG 限定、不记录密钥。当前日志已足以安排上述聚焦修复；若要将剩余“1.2.3 比当前快”的差异归因到某个新提交，则还需要上述同条件时间证据。

## 修复实施（2026-09-20，用户确认后）

### 已改行为

- App 保留 `migrateProximityLightingReferences` 的目标拓扑迁移与持久化，移除将其他节点的同步任务追加到 Fast Add 的字典及发送逻辑。本设备的订阅、邻居和 Profile 照常恢复；其他节点通过现有 Group/Space 同步入口收敛。没有把这些节点标记为已同步，也没有新增自动跨设备重试来继续阻塞本页面。
- App 不再因为本设备存在邻居差异就跳过整个完成检查。本设备邻居、组订阅、Profile 等未完成时仍显示需要同步。
- SDK FastAdd 在发送入口验证目的地址属于当前操作节点，transmitter 找不到对应操作时返回错误，避免静默不发而等待 ACK 超时。
- SDK FastAdd 只允许匹配的 ACK 回复推进追加队列；Unack 仅由自身发送完成推进。发送结果、0.3 秒延迟推进和 busy 重试校验当前 handle 身份及阶段，旧回调不会移走下一条命令；每次真正移除任务时重置其重试计数。
- SDK FastAdd 在交出批次完成回调前恢复 transmitter、delegate 并清理旧状态。单节点成功也先清理本操作再回调。显式停止时由停止流程统一完成，避免 normal finish 与 stop finish 重复清理新启动的 Proxy 队列。
- SDK Proxy 队列将入口和状态变更串行放到主队列，去掉后台注册 delegate 与 `sleep(0.1)` 的交接依赖。各结束路径统一先保存结果、同步清理 timer/delegate/timeout，再调用 completion；0.1 秒缓存收尾回调用批次 ID 防止影响重入的新批次。timer 在发送前建立，取消旧 timer 不再异步追赶新批次。
- 没有修改 ACK 超时参数、Lab TTL 或普通 Proxy 的连接预算，也没有修改远端 SDK 依赖声明。

### 验证与已知限制

- SDK 新增 `Tests/Standalone/RestoreQueueLifecycleTests.swift` 与 `scripts/check_restore_queue_lifecycle.sh`，直接编译实际 `MeshFastAddDeviceManager.swift`、`MeshProxyMessageCommand.swift`，只替换无线、模型和配网边界。已通过：Unack 残留 Status 不提前完成；重复 Unack 完成不消费下一条；他机目的地址立即失败而本机后续命令仍执行；FastAdd 完成后启动 Proxy；Proxy 完成回调重入下一批；停止只完成一次；旧 0.1 秒回调不清理替换批次；全局 timeout 在回调前恢复。
- App 现有真实 topology/planner/coordinator 隔离回归新增“恢复地址 0002 → 0008，peer 仍缓存旧邻居时保持 pending；普通同步重建能找到 0008，成功更新后才无差异”的场景，已通过。相应旧源码契约“必须在 FastAdd 追加跨设备任务”已改为正确边界。
- `check_path_topology_persistence.sh` 的 Path、topology policy、lifecycle policy、integration contracts、review contracts、配置完整性及 scoped import 执行部分通过。该组合脚本最后调用的 `check_space_recovery_receipts.py` **未通过编译**：其编译输入缺少已有 `SiteGatewayLastOnlineSnapshot`（定义于 `SunSmart/Common/Data/SiteGatewayAssociationConsistencyPolicy.swift`）。相关脚本和业务源文件本轮均未修改；没有为这项无关夹具依赖问题扩大修改范围，不能把整个组合脚本记录为通过。
- `check_device_restore_transition_time.sh` 的 11 个 pending-target、3 个 cleanup 场景及接线检查通过。
- 同一 SDK 队列夹具用修复前 HEAD 源码（仅将 UIKit import 替换为 Foundation 以适配宿主编译）运行，确实失败于 `Unack stale response must not complete FastAdd before remaining ACK`；最终修复源码包含取消路径和重试计数调整，全部通过。
- SunSmart / Debug / generic iOS 使用本地 SDK 的构建通过；取消路径补丁后的最终增量构建也通过（退出码 0）。无新增 SDK 公共 API、资源或品牌编译条件，未机械重复五品牌构建。构建和隔离测试不证明真实设备恢复耗时已改善。

### SDK 交付与人工验收

- App 基线：`fix@ddc1e8a9` 加本轮未提交修改。
- SDK 基线：`one-dev@a971027e08f9775d7a3f071a06f89be1c38ecc96` 加上述两个生产文件与两个测试/脚本文件的未提交修改。本任务没有提交、推送或发布 SDK。
- 本地验证入口是 `SunSmartLocal.xcworkspace`。正式 `SunSmart.xcworkspace` 的远端 pin 仍是原 revision，**尚不包含 SDK 队列修复**。正式交付需先发布 SDK 修复 revision，再更新 App pin；不能将只提交 App 的版本视为完整修复版本。
- 最短人工验收：分别用两种固件手动重置后恢复，检查本设备无需因漏发再手动补齐订阅/Profile；日志不再在 FastAdd 阶段向其他节点逐条等超时；首条 Range Status 不再出现“收到成功但等待 missing 兜底”。如 Group/Space 有邻居待同步，使用其现有 SYNC，确认成功后消除差异；停止恢复再重试也应正常。最终耗时仍需按前述相同数据和 TTL 条件实测。
