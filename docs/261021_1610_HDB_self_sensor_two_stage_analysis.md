# HDB 自身感应与两段调光排查

最新实施：2026-10-22 00:59，用户已确认方案，见文末「DeleteAll → Add 修复实施与验证」。已统一全 element Zone 目标先 DeleteAll，再 Add 基础订阅及 Zones，并修复跨 element 缓存、FEFD 恢复条件、部分失败/取消持久化及 STOP 等待期的在途回执。118 个逐请求中断重放场景、关联回归及五品牌 generic iOS Debug 编译通过；真机回读与二段式运行待用户验收。App/SDK 均未提交，新增 SDK API 尚待发布到正式 release。下文各时间点记录保留供追溯，不代表最新实施状态。

日期：2026-10-21，更新至 22:03。分支 `feat/HDB-261020`，当前 HEAD `146469a6`。用户实测确认 reset 后重新添加感应成功；本轮进一步对齐 Sensor Publication 重传规则，结果见文末。18:37 节保留正常入组实包对照，21:41 节保留上轮订阅修复记录；此前实施和验证记录对应各自时间点。本轮仅调整 App 及相关回归，未修改 SDK、固件或服务器，未提交 Git，未操作真机。

历史记录说明：下文 16:30 的补绑实施记录保留供追溯，但当前源码中没有该 HDB 补绑任务，最新导出也仍显示 LC element 的 Generic OnOff 未绑定。本轮不能据该历史记录宣称当前版本已经补绑或沿用其验证结论；当前状态以本轮源码和最新样本核对为准。

## 结论与证据边界

最新 16:58:36 样本中的 Presence Sensor 位于 0011，发布到 C0BF；LC 位于 0013，订阅 C0BF，两者均绑定 AppKey 3。没有 Sensor element 选错、发布/接收组地址不一致的缓存证据。用户反馈 Auto 手动能亮，约 10～13 秒后看似熄灭，再次感应不亮；该时长符合当前 1 秒 RampUp、10 秒 Hold、2 秒 RampDown，可能已经进入 5% Dim。尚缺少实际 Presence 事件、灯具亮度及 LC 运行状态，不能唯一确认根因，也不能据传感器指示灯判断消息已到达 LC。

本地 workspace 指向 `nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `8c5af55`，工作树干净。以下均按当前源码核对；历史文档中的现场样本不作为本次设备的当前状态。

## 修复前行为链（最新变更见文末）

1. 当前 `HDBDeviceSyncContext` 按 SIG Sensor Server（1100）存在与否确定 Sensor 能力；`HDBConfigurationStore.ensureSensorGroup` 从普通组地址池分配并保存设备 sensorGroupId。只有属性识别完整且唯一匹配 004D 时才创建 publication；识别不完整则不猜 element、不生成 publication，也不因此保持 HDB publication 待同步。标准配网 readiness 不在此次改动范围内。
2. `HDBDevicePreparationPolicy.plan` 为 Sensor Server 配置 publication 目标，为所有 LC Server（130F）配置自身 sensorGroupId 订阅。准备阶段直接 Add 的目标是 LC Server，不能说此阶段分别向三个 Model 都发送了 Add。
3. SDK `Models.relatedModels` 与 `ConfigurationClientHandler` 按同 element 的模型扩展关系联动 LC、LC Setup、Generic OnOff 的订阅缓存。缓存联动不等同于对三个模型分别完成设备回读。
4. `HDBDeviceSyncContext.zoneSensorTargets` 将同 element 的相关目标纳入 Sensor 保留集合。Zone 全量同步对这些目标分别发送消息：非主 LC 共享表需要 FEFD 时先全部 Overwrite FEFD，再 Add sensorGroupId，再 Add Zones；不需要 FEFD 的 Sensor 表以 sensorGroupId 为 Overwrite 起点。空 Zones 也执行保留 Sensor 的计划。
5. 初始化还发送 Occupancy Mode=true、LC Mode=true、T4=0xFFFFFE、manualControl=false、lightAutoAdjustEnabled=false、无限 manual override timeout，以及保存的亮度/渐变/Hold，最后发送 Auto。App 是否收到这些 ACK 与设备是否正确运行两段调光是不同层次的证据。
6. `HDBLightingConfigurationService.set` 检查初始化签名及 SDK 缓存中的 Sensor 链路，然后只发送本次选择的字段。修改亮度、时间不会顺带切回 Auto；Auto 对应 `LightLCLightOnOffSet(true)`，不包含 `LightLCModeSet(true)`、Occupancy Mode 或订阅修复。
7. `isPrepared` 不是实时设备检查；它依赖初始化签名及 LC 订阅/Sensor 发布缓存。普通 Sync 在签名已完成且缓存链路满足时不会无条件重做基础初始化。Zone pending 才生成全量 Zone 计划。若设备真实状态与缓存不同，不能保证普通 Sync 必然发现。
8. HDB 已在普通 Group Profile 同步入口隔离，当前主链不会继续按普通 Group Profile 重写 HDB 参数；此结论不涵盖设备收到的所有外部控制或固件内部状态变化。

## 优先核对项

### 用户补充的实际表现

单播 Set Lighting Control=Auto 后设备能够进入第一段；灯随后熄灭，再次感应到人不亮。此信息说明 App 主动控制至少能驱动亮灯，调查优先收敛到“感应自动触发”而非单播命令完全未送达。不能由一次亮灯推断 LC Mode、Occupancy Mode、Sensor 发布与接收均正确。

优先区分两类情况：

1. **Occupancy Mode 未实际开启。** 现有普通 Profile 代码明确将 occupancy 与 vacancy 分开设置此状态；HDB 初始化期望 true，但后续 Auto Set 不重发它。若设备实值为 false，手动启动有效而人体感应不自动启动与该状态相符，仍需回读确认，不能直接判定。
2. **Presence Sensor 至 LC 的触发链未生效。** 直接 LC Light OnOff 命令不经过 Sensor 发布/组订阅链，因此 Auto 能亮完全不能排除 sensorGroupId 缺订阅或 publication 错误。应优先检查 130F 的实际列表，再逐一检查同 element 的 1310/1000；SDK 联动缓存不能代替硬件回读。

另外，“熄灭”不能直接等同于进入了正确的 Dim 阶段：当前 HDB Dim 映射至 Lightness Prolong，T4 初始化为 0xFFFFFE。若 Dim=0，进入第二亮度本来就会呈现熄灭；若 Dim>0 却很快完全熄灭，应同时核对 Dim、T4 和控制状态，不能只查订阅。需记录从 Auto 到熄灭的时长及是否有人持续移动，以辨别状态转换。这里不对用户所说第一段/第二段强行重新编号。

本次另比对普通 Profile 的 Sensor 启用路径：同样通过 ConfigModelPublicationSet 配置 Sensor Server，未发现 HDB 在此处遗漏一个独立“启用 Sensor”的消息。仍未取得本次实时回读，未修改生产逻辑。

| 检查 | 应有证据 | 可区分的问题 |
| --- | --- | --- |
| 构建及恢复过程 | 是否使用当前修复版本、添加/Sync 是否完整结束 | 历史失败状态尚未恢复 |
| 实际 Sensor 发布 | Presence Sensor Server 的 publication address 等于该设备 sensorGroupId，AppKey 正确 | 有感应但消息未送到目标组 |
| 实际接收订阅 | 对 LC 所在 element 的 130F、1310、1000 分别 Subscription Get；列表含自身 sensorGroupId，需要时同时含 FEFD | 真实漏订阅、被覆盖、缓存与固件不一致 |
| LC 控制状态 | 单播 Lighting Control Get 中 LCMode=true；必要时另读 Occupancy Mode | 基础控制未启用；Auto Set 并不修复 Mode |
| 运行控制 | 明确对该设备执行 Auto Set，而非只修改页面选择或只 Set Intensity/Time | 仍处于 Force/手动控制，页面草稿不等于实际模式 |
| 两段参数 | 单播 Get 的 Bright、Dim、Hold、RampUp、RampDown 与意图相符 | 发送完成但设备未实际应用参数 |
| 感应事件 | 实际 Presence 事件及连续无人时的时间线 | 无事件、持续占用延长保持时间、固件自身事件未驱动 LC |

现有单播 Lighting Control Get 可读取 LC Mode、LC Light OnOff、Lightness；不包含 Subscription List、Publication、Occupancy Mode 的实时读取。Broadcast/Multicast Get 展示保存值，不能作为硬件回读。LC Light OnOff 本身也不是完整的 Auto/Force 状态枚举。

建议先用单播确认 LC Mode 与参数，再核对实际发布和三个模型的订阅列表。如果缺少 sensorGroupId，再沿最新 Add/Overwrite/DeleteAll 与 ACK 定位丢失位置；如果发布、订阅、Mode、Occupancy 和 Auto 均确认正常，则继续检查感应事件进入 LC 的设备端行为。设备端配合仅提供接口与日志，不修改固件。

## 验证

`python3 scripts/check_hdb_integration.py --subelement` 本次通过：生产 Context/Zone planner/Task 与实际 SDK readiness getter，覆盖有无 Sensor、0/8 Zones、共享表、失败恢复和 FEFD 保留。无线、部分模型缓存及持久化使用边界替身，因此不能证明现场设备订阅或感应效果正常。

未构建（无生产代码修改），未操作真机，未执行服务器联调。待补信息：当前设备版本与添加/Sync 结果、Auto/Force 选择、一直亮/一直暗/仅超时不变暗的具体表现，以及最新设备回读或日志。

## 16:17:46 Export 样本核对

来源：`/Users/maginawin/Desktop/doing/wwd/Space_Space 2_20261021_161746_818+0800.json`。`capturedAt=2026-10-21T08:17:46Z`（本地 16:17:46）。对比正常导出与 `_debugInspection.spaces[0].rawLocal.mesh` 的本地数据库快照；没有把文件内云同步 readback diagnostic 当作设备 Mesh 实时回读。

### Element 与地址

节点主地址 0008，PID 2502、VID 0003，三个 element；地址等于 0008 加 element index。

| Element index / 地址 | Model / 功能 | AppKey index | 发布地址 | 订阅 |
| --- | --- | --- | --- | --- |
| 0 / 0008 | 1100 Presence Sensor（004D） | 2 | C07F | 空 |
| 0 / 0008 | 1000 主 Generic OnOff | 2 | 无 | 空 |
| 1 / 0009 | 1100 Ambient Sensor（004E） | 2 | C07F | 空 |
| 2 / 000A | 1100 Energy Sensor（0072） | 2 | 无 | 空 |
| 2 / 000A | 130F LC Server | 2 | 无 | FEFD、C07F |
| 2 / 000A | 1310 LC Setup Server | 2 | 无 | FEFD、C07F |
| 2 / 000A | 1000 LC Generic OnOff | **空** | 无 | FEFD、C07F |

`sensorTypes=[004D,004E,0072]` 与 rawLocal 的 sensorsType 字节一致。SDK MeshDatabase 按 Sensor Model 的 element 顺序恢复这一映射；本样本三项齐全。因此 000A Sensor 无 publication 不是“人体传感器配错到了 0008”：000A 在此记录中是能耗 Sensor。

`sensorGroupId=49279=0xC07F`。整个 composition 只有 000A 上存在 130F/1310。HDB Auto 路由按 130F 实例选择 Model，单播地址取 target.elementAddress；所以当前代码结合这份 composition 会把 Auto 发到 000A。配置消息发往节点主地址 0008 是另一回事：Subscription/Publication 消息 payload 携带实际 element，不能仅凭配置报文外层目的地址认为选错 LC。

原始 SQLite elements 与正常导出 elements 完全相等；上述 publication、subscription、bind 不是 export 层改写产生的差异。

### 已有状态与未观测状态

原始 LC 缓存为 Mode=true、Occupancy Mode=true、manualControl=false、lightAutoAdjustEnabled=false、manualOverrideEnabled=true、timeout=4294967295。HDB 初始化签名无 pending 前缀；Zone 状态 synced。前述“Occupancy Mode 可能未开启”缺乏本样本支持，应降低优先级；缓存仍不能证明设备此刻实值。

Bright=80%（52428）、Dim≈5%（3276）、Hold=10 秒、RampUp=1 秒、RampDown=2 秒、T4=0xFFFFFE。业务意图与 LC 参数缓存一致。不能把用户观察的灭灯直接解释为 Dim=0：本样本明确是 5%；低亮度看起来熄灭与真正进入 Standby 需要亮度/状态或运行证据区分。

原始 timeOccupancyDelay、timeFadeStandbyAuto、timeFadeStandbyManual 均为 null；它们表示缺少缓存观测，并非零。原始 lightnessStandby/luxLevelStandby 也为 null，正常 export 补成了 0，不能用这个 0 证明设备实际 Standby 参数。motionSensitivity 未记录，pirEnabled=1。未保存 LC 场景及 lux 条件。

### 已确认的绑定缺口与因果边界

000A/1000 的 bind=[] 是明确事实。SDK `supportModels` 只加入 `onoffModel`，而 `getFunctionModel` 返回节点按 element 顺序找到的首个 1000，即 0008/1000；App `Node+MessageHandles` 的普通绑定与 SDK `isKeybindComplete` 都基于 supportModels，因此 000A/1000 不在这部分绑定/完整判定范围内。HDB Zone 策略仍会给它发订阅配置，形成“有订阅、无绑定”的快照。

这说明该 Generic OnOff 实例没有 AppKey 2 的绑定记录，并解释了为何整体可以显示准备完成。但 HDB Auto 本次用的是已绑定的 130F，Presence 发布也使用 AppKey 2；不能凭 1000 未绑定就断言它必然阻断 130F 接收 Sensor Status。是否存在设备特定耦合需要消息/固件行为证据，不能把补绑定当作已经证实的修复。

### 最小后续诊断

1. 在感应时确认 Presence Sensor Status：来源是否 0008，目的是否 C07F，Property 004D 是否报告有人，使用的 AppKey 是否为 2。App 没观察到组播不等于设备没发布，需要有效抓包/设备日志路径。
2. 硬件回读 000A/130F 的 subscriptions、Mode、Occupancy Mode，以及 LC Setup 的 Occupancy Delay（003A）和 Prolong（003B），区分缓存正确与设备真实运行条件。
3. 如事件已产生且以上实值正确，再由固件团队只读核对自身 Sensor 事件送达本地 LC 的处理与状态转换；无需调整 LC element。
4. 对 000A/1000 的 AppKey 缺口独立评估：若验证或产品契约要求绑定，后续方案覆盖 HDB 必要模型的绑定、readiness、旧设备 Sync 恢复与普通 Site 隔离；本次仅分析，不直接修改 SDK 或扩大标准设备绑定范围。

本轮完成 JSON 解析、raw/export 交叉核对与源码定位，未重跑前轮无代码变化的隔离回归，未构建、未操作真机。

## 已授权 App 补绑实现与验证（16:30）

### 最近变更核对

最近 HDB 提交 `5f90fbcd`、`215fe006`、`355632ee` 增加或调整准备任务、消息校验、订阅阶段和 FEFD 保留，没有改变 SDK 普通 Generic OnOff 的选择逻辑。`d04d226e..355632ee` 的 `Node+MessageHandles.swift` 无差异。当前 SDK `8c5af55` 中 `supportModels` 只加入首个 `onoffModel`；这段选择在可追溯基线 `1ed243e`（2023-08-31）就已存在。基线 blame 不是证明它在那一天首次引入。

结论：不是最近把 LC OnOff 的 AppKey 绑定删掉了，而是新 HDB 流程沿用了只绑定首个 OnOff 的既有模型列表，未补齐 LC element 的另一个实例。

### 实施边界与行为

- 从现有 HDB preparation plan 推导“与 130F 同 element 的 1000”，不按固定 element index，也不把其他 element 的 OnOff 全部加入。
- App 的 HDB 准备/Sync 链先补缺失的 Space AppKey 绑定，再继续 Sensor subscription/publication、初始化和 Zone 任务。配置消息目标是节点主地址，payload 指明 LC element 和 1000。
- 新增 `ConfigModelAppBind` 的严格 ACK 校验：成功状态、element、AppKey index、Model 必须匹配。使用现有 SDK API，无新依赖、无 SDK 改动。
- 缺绑纳入 HDB readiness，Lighting Configuration 和需要准备完成的 Zone Set 不再把它视作 ready；补绑成功不阻断后续阶段。Standard Site 不生成此任务。
- 目标集合是计算属性，不改变 preparation plan 的 Codable 内容和既有初始化签名。旧 HDB 设备可通过普通 Sync 只补绑定，保持已有参数、初始化身份与已完成 Zone 状态；不强制重播 Auto。
- 失败、无 ACK、错 ACK 不结算成功。成功 ACK 后必须保存 Node；保存失败撤销本次新增的本地绑定完成记录，使再次 Sync 仍能补绑。保留其他 AppKey，不发送 Unbind，不清除 publication。
- 复用现有 HDB preparation 本地化文案；未新增文件工程归属、资源或编译分支。共享生产代码覆盖五品牌，采用 SunSmart 代表编译，不机械重复五品牌。

针对当前样本，补绑消息为 `ConfigModelAppBind`（803D）：外层目的 0008，element=000A、AppKey index=2、Model=1000；预期 AppStatus（803E）成功。其参数为 `0A 00 02 00 00 10`，不包含 AppKey 内容。

### 本次验证

以下六项通过：

| 检查 | 与本次相关的覆盖 |
| --- | --- |
| `check_hdb_integration.py --subelement` | 复现 SDK 普通 readiness 忽略 LC OnOff；有/无 Sensor 的旧设备补绑；错误 element/key/model ACK、失败、无 ACK、Node 保存失败、重建 context 重试；保留其他 Key 和原配置；Standard 旁路；既有 FEFD/Zone 订阅回归 |
| `check_hdb_integration.py --add-execution` | 新设备先补绑，再 Sensor 链路、初始化、Zone，最后结算添加；外部 revision 变化仍拒绝旧回执 |
| `check_hdb_integration.py --device-tasks` | 多模型 ACK、参数恢复、失败与迟到回执、Mode/Auto 顺序 |
| `check_hdb_integration.py --device-sync` | HDB/Standard 类型、准备计划、Sensor/空 Zone、身份和恢复 |
| `check_hdb_integration.py` | 生产 Store/Service/Executor、共享订阅、空目标、保存失败和迟到回复 |
| `check_hdb_lighting_configuration_service.py` | 控制前的绑定/准备检查、非 LC element 的额外 OnOff 不阻断 Force Off、取消/重入及元数据隔离 |

测试仍以 SDK/数据库/无线边界替身配合生产 HDB 代码，不能证明硬件感应链路。新增夹具纠正了原 `supportModels` 替身把所有 OnOff 都视为普通绑定目标的假设，直接覆盖本样本的漏绑场景。控制测试中主 OnOff 与 LC 共 element，缺绑现在提前返回 notPrepared；已同步调整该预期，保持拒绝且不发送的行为验证。

SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建退出码 0。DerivedData 使用固定 `SunSmart-feat-HDB-261020`；SDK 映射仍为 one-dev、HEAD 8c5af55，工作树干净。编译出现现有 weak/implicit-strong-capture 警告，未扩展修复。`git diff --check` 通过。未自动安装或运行真机，未做云端/服务器联调。

### 最短人工验证

1. 使用本次 App 构建，进入 Space → Lights，对已有 0008 设备执行 Sync，无需删除重加。
2. 确认 Sync 成功；再次导出或设备回读应看到 `000A/1000.bind` 包含 2，`130F/1310/1000` 的 C07F/FEFD 订阅保留。DEBUG 日志可见 `[HDB][DeviceTask] kind=binding` 的 planned/persisted。
3. 单播 Auto Set，等待进入 Dim，再次人体感应应回到 Bright。若仍不触发，继续上节 Sensor Status/Occupancy Delay/设备 LC 状态诊断，不再把 App 补绑定等同于根因已解决。

## 16:58:36 Export 与现场表现复核（17:10 更新）

### 样本与现场表现

- 文件：`/Users/maginawin/Desktop/doing/wwd/Space_Space 3_20261021_165836_042+0800.json`。
- 捕获时间：2026-10-21 16:58:36（+0800），Space 3，节点 0011，PID 2502、VID 0003，firmwareID `0103260020461D00`。
- 用户反馈：「Auto 手动能亮，熄灭后再次感应不亮」；感应判断来自传感器指示灯，约 10～13 秒后熄灭。
- 本轮未取得无线 Sensor Status、灯具当前 Lightness、LC 内部状态或运行中的 manual override 回读。

### 已证实的配置记录

| Element / 地址 | Model / 属性 | AppKey 绑定 | Publication | Subscription |
| --- | --- | --- | --- | --- |
| 0 / 0011 | 1100 Presence / 004D | 3 | C0BF，AppKey 3 | 空 |
| 1 / 0012 | 1100 Ambient / 004E | 3 | 无 | 空 |
| 2 / 0013 | 1100 Energy / 0072 | 3 | 无 | 空 |
| 2 / 0013 | 130F LC Server | 3 | 无 | FEFD、C0BF |
| 2 / 0013 | 1310 LC Setup Server | 3 | 无 | FEFD、C0BF |
| 2 / 0013 | 1000 Generic OnOff | **空** | 无 | FEFD、C0BF |

`sensorTypes=[004D,004E,0072]` 识别完整，`sensorGroupId=49343=0xC0BF`。仅 Presence 发布符合本次 preparation 改动，不能把 LC element 上的 Energy Sensor 当作人体传感器。64 个组地址唯一；63 个 Lighting Zone 位于 C080～C0BE，与 C0BF 不冲突。设备 Lighting Zones 为空且 synced，不代表没有自身 Sensor 接收组。

原始 SQLite elements 与正常 export elements 完全相同；原始 HDB 内容与 export HDB 内容完全相同。初始化签名不是 pending，Lighting Configuration 和 Zone 状态均为 synced。这些只能支持 App 已有配置/同步记录；云端 readback confirmed 和 debug issues 为空不能证明设备当前实际配置或感应链路正常。同 element 的订阅缓存可能由 SDK relatedModels 联动，仍不能替代硬件订阅列表回读。

| 参数 | 保存值 | 对症状的含义 |
| --- | --- | --- |
| LC Mode / Occupancy Mode | true / true | 没有缓存显示关闭；实值尚未回读 |
| Bright / Dim | 80% / 约 5% | Dim 不是 0，但肉眼可能认为已熄灭 |
| RampUp / Hold / RampDown | 1 / 10 / 2 秒 | 合计 13 秒，与现场约 10～13 秒相符 |
| Prolong（003B） | 0xFFFFFE | 与 HDB 目标一致；不是另一个约 10 秒的保持值 |
| manualControlMode / lightAutoAdjustEnabled | false / false | 没有保存启用手动配置或日光调节的证据 |
| manualOverrideEnabled / timeout | true / 0xFFFFFFFF | 配置了无限手动保持；是否当前处于手动覆盖未知 |
| Occupancy Delay（003A） | 原始值 null | 没有观测值，不能按 0 推断 |
| pirEnabled | 原始值 1，导出 true | 可能来自 SDK 默认值，不能证明设备 action publish 已开启 |

`lightnessStandby`、`luxLevelStandby` 原始值均为 null，SDK 解码时补成 0。因此正常导出的 Standby=0 不能证明设备当前进入 Standby 或已确认其实际参数。`manualControlState=0` 是手动延迟结束后的目标状态配置；Vendor Set 成功时 SDK 从请求回填该值，它不是设备当前的 `is_manual`。

### 源码解释与根因边界

1. **Auto 能亮绕过了 Sensor 触发链。** `HDBLightingMessages.message(.auto)` 发送 `LightLCLightOnOffSet(true)`；路由选择 0013/130F。它能解释一次亮灯，但不能证明 0011 的传感器随后产生了 004D Status，也不能证明该事件经 C0BF 送达本地 LC。再次 Auto 不会顺带重配 Occupancy Mode 或清查全部基础状态。
2. **时间线更符合 Bright 向 Dim 过渡，尚不能认定 Off。** 1+10+2=13 秒，Dim=3276/65535≈5%。需要亮度回读或提高 Dim 的短测，才能区分低亮度输出与真正 Standby。它仍不能解释再次感应不回 Bright，后者是本轮重点。
3. **硬件指示灯不能证明发布成功。** 本地厂商协议的 0x46/0x01 控制 action publish，默认 1；SDK 的 `pirEnabled` getter 与数据库默认也为 true。HDB preparation 目前不显式配置或读取该开关。这里是诊断盲区，不是已证实设备把开关关闭，也不据此直接增加初始化写入。
4. **无限手动保持只是条件性嫌疑。** 当前没有 `is_manual` 实值，不能由 timeout=0xFFFFFFFF 判定传感器被手动覆盖屏蔽。协议 GET 0x32 返回实际 `is_manual`（0 非手动、1 手动），与导出 `manualControlState` 是不同数据。
5. **0013/1000 的缺绑是确定的 App 配置覆盖缺口，但因果关系未证实。** SDK `supportModels` 只收录首个 `onoffModel`，本设备为 0011/1000；当前 HDB preparation 没有额外补绑 0013/1000。130F 和 Presence 均已绑定 AppKey 3，Auto 使用 130F，所以不能从 1000 的缺绑直接推导 Sensor Status 必然无法驱动 LC。其设备特定耦合需由实际行为证明。

据此，本次可以收敛到「感应事件生成/发布 → LC 接收 → LC 运行状态允许触发」链路，不能仅凭 export 在三者之间唯一定位。当前记录不支持继续更换 Sensor element、给 Ambient/Energy 增加 publication，或把 Dim=5 改称 Dim=0。

### 最短验证路径与责任边界

1. 用户可暂将 Dim 提高到 20%～30%，再明确执行一次 Auto，观察约 13 秒后是否稳定进入 Dim、再次感应能否回 Bright；也可回读实际 Lightness。该测试只区分「看似熄灭」与真实 Off，不等于修复感应触发。
2. 取得一次有效感应事件证据：源 0011、目标 C0BF、AppKey index 3、Sensor property 004D 报告有人。需要能观察该组消息的抓包或设备日志；App 未收到组播本身不能证明设备未发布。
3. 若没有 Presence 发布，先 GET 厂商 0x46/0x01 的 action publish 实值，再由设备团队核对硬件事件到 Sensor Status 的产生过程。传感器指示灯不是这个证据的替代物。
4. 若已有 Presence 发布，回读 0013/130F 的 Subscription、LC Mode、Occupancy Mode，以及 003A Occupancy Delay、003B Prolong；同时 GET 厂商 0x32 的 `is_manual`。外发包正常也不能单独证明同节点的本地 LC 已接收，需要设备团队核对本地事件送达和 LC 状态转换。
5. 只有发现具体差异后再确定 App 修复边界。若设备配置实值符合目标且事件已进入 LC，固件侧仅记录接口/行为证据并交对应团队处理；本任务不修改固件或服务器。

### 核对来源与验证范围

- App：`SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift`、`HDBDeviceSyncService.swift`、`HDBLightingMessages.swift`，以及 `SunSmart/Common/Data/HDBDevicePreparationPolicy.swift`、`HDBConfiguration.swift`。
- SDK：本地 one-dev 中的 `Node+SupportModels.swift`、`Node+Propertys.swift`、`MeshDatabase.swift`、`VendorServerDelegate.swift`；用于核对绑定选择、默认值、持久化与 ACK 回填语义。
- 协议：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/sunricher_protocol_vendor.md` 中 0x46/0x01 action publish 和 GET 0x32 手动重载状态。协议存在不等于该固件版本的接口已经现场验证。

本轮完成最新 JSON 解析、原始数据库/导出一致性比对和相关源码核对。未修改业务代码，未构建、未重跑既有代码测试，未操作真机；前轮 publication 改动的构建或隔离回归不作为感应成功的证据。旧 Space 2 文件本轮已不可访问，历史样本只保留在前文，不声称重新比对了两份原文件。

## 固件核对：Sensor 功能与 Auto 命令（2026-10-21 18:00）

本节记录 Auto 修改前的源码行为；HDB 固定 1 秒渐变已在下文 18:12 实施中移除，其他固件分析继续适用。

### 结论与版本边界

1. Sensor Server 的功能由固件注册的 Sensor Property 类型及取值/发布回调决定。Model ID 0x1100 只表示 Sensor Server；element 顺序、与 LC 共处一个 element、发布到哪个组，均不能单独决定它是人体、光照还是能耗传感器。
2. 当前 HDB Auto 发送 Light LC Light OnOff Set(true)，使用 LC Server 0x130F；这份固件也支持对 LC 同 element 的 Generic OnOff Server 0x1000 发送 true，二者都会清除手动覆盖并进入同一个 LC turn_on。没有依据要求把当前 Auto 改成 Generic OnOff。
3. 主灯 element 的 Generic OnOff 是另一个实例，走手动亮度控制路径；不能把它与 LC element 的 OnOff 混用。
4. Auto 是启动/重新触发 LC 状态机的 On 事件，不替代 LC Mode、Occupancy Mode、分段参数或 Sensor 链路配置。LC 已禁用时，两个 On 入口都不能自行启用 LC。
5. 当前 HDB Auto 显式发送 1 秒 Transition Time；固件优先使用该值。要让主动 Auto 使用保存的 RampUp，应省略 Transition Time/Delay 字段。本轮只记录该行为差异，没有修改 App。

只读源码基线：

- 固件目录 `/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware`，分支 master，HEAD `585c45a`，工作树干净。提交日期为 2026-08-20；VERSION 文件为 2.8.0。
- App 当前分支与 HEAD 如文首；原有两处生产代码及 Tests 的未提交改动保持不变。
- App 本地 SDK 映射到 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55`，工作树干净。
- 固件当前选中的编译宏是 PRODUCT_9033A_MW_V_54L15；本轮根据历史现场 PID 0x2502 另行追踪 PRODUCT_DONGLE_DEMO_54L15 分支，没有切换宏或构建。分析覆盖的是该仓库中的产品源码，不能证明现场 firmwareID 与此提交完全一致。本轮未重新读取现场 JSON。

### Sensor 功能怎样确定

固件链路为：产品宏 → 产品 main 文件的 `_elements[]` → `SR_MODEL_SENSOR_*_SRV()` → 对应 `bt_mesh_sensor_srv` 的 sensors 数组 → 每个 sensor 的 `.type`、`.get` 和发布函数。

PID 0x2502 在 `include/sunsmart_config.h` 的 PRODUCT_DONGLE_DEMO_54L15 分支启用 PIR、BH1730 光照和 CCT；对应 `src/main_demo.c` 的 composition。以 0 为起点的 element index 如下：

| Element index / 地址 | 注册实例 | Sensor Property（本份源码） | 同 element 的相关模型 |
| --- | --- | --- | --- |
| 0 / A | `_sensor_pir_srv` | 0x004D Presence Detected | 主灯 CTL/Lightness/Generic OnOff |
| 1 / A+1 | `_sensor_amb_srv` | 0x004E Present Ambient Light Level；0x0055 Present Illuminance | CTL Temperature |
| 2 / A+2 | `_sensor_energy_srv` | 0x0072 Precise Total Device Energy Use；0x0080 Active Energy Loadside | LC Server、LC Setup、LC Generic OnOff |

这里 A 是设备主单播地址。`main_9036t.c` 则把 LC 放在 index 1，与 Ambient 共 element，因此不能把 Demo 的 LC index 2 规则推广到所有产品。

依据：

- `src/main_demo.c` 第 162–201 行：三个 element 的实例挂载。
- `src/mod_sensor_pir_srv.c` 第 27–76 行：Presence 类型、读值及事件发布。
- `src/mod_sensor_amb_srv.c` 第 152–199 行：bottom/top 两个属性和两个 getter。
- `src/mod_sensor_energy_srv.c` 第 134–201 行：两个能耗属性和 getter。
- 数值 Property ID 与本地 iOS SDK `DeviceProperty.swift` 交叉核对。

App 应对每个 0x1100 所在 element 发送 Sensor Descriptor Get（0x8230，不携带 Property 时查询全部），由 Sensor Descriptor Status（0x51）的来源地址和完整 Property 列表建立映射。Sensor Status 也携带 Property ID；不是读取到任意 0x1100 就能推断其功能。

当前 SDK `Node+Messages.swift` 第 296–308 行仅使用 `descriptors.first?.property`，`sensorModelTypes` 是一个 Model 对一个 Property。这解释了导出通常呈现 `[004D,004E,0072]`，但它不是固件完整属性清单：本份源码的 Ambient 和 Energy 实例各有两个属性。当前 HDB preparation 按 004D 选人体实例，对本 Demo 的单 Property Presence 成立；未来遇到同一 Server 多 Property 且 Presence 非首项时，当前表示不充分，不能据首项排除人体能力。本次不扩大 SDK 实施范围。

### Auto 的精确命令及三个入口的差异

| 命令 | 目标实例 | 本份固件行为 |
| --- | --- | --- |
| Light LC Light OnOff Set(true)，0x829A；无响应版本 0x829B | LC 所在 element 的 0x130F | `light_onoff_set` 清除手动覆盖，调用 `turn_on(..., true)` |
| Generic OnOff Set(true)，0x8202；无响应版本 0x8203 | LC 所在 element 的 0x1000 | LC `onoff_set` 清除手动覆盖，调用 `turn_on(..., false)` |
| Generic OnOff Set(true)，0x8202 | 主灯所在 element 的 0x1000 | Lightness `onoff_set` 调用手动控制，并恢复 last lightness；不是 LC Auto |

固件 `include/sr_light_ctrl_srv.h` 第 134–146 行将 LC 自己的 Generic OnOff、LC Server 和 LC Setup 放入同一组模型。两条 LC On 路径分别见 `src/sr_light_ctrl_srv.c` 第 1273–1312、1975–1995 行；共同入口 `turn_on` 在第 671 行开始。其第三个参数名为 `pub_gen_onoff`，控制状态发布，不代表不同调光模式；两种消息的响应、发布和传入渐变参数仍有差异，不能称为完全相同的报文。

主灯 OnOff 见 `src/sr_lightness_srv.c` 第 764–786 行，调用 `sr_lightness_srv_manual_control_with_reason`。后者根据手动覆盖/手动开启配置进入相应状态，或禁用 LC。这是必须区分目标 element 的原因。

当前 App：

- HDB `HDBLightingMessages.message(.auto)` 发 0x829A/0x829B，参数为 On=1、TID、TransitionTime=.default、Delay=0。
- `HDBLightingConfigurationPolicy` 将 Auto 对应到 0x130F，单播使用实际 target.elementAddress；组播使用目标组地址。不能只发到节点主地址。
- `.default` 在本地 SDK `MeshAPI.swift` 第 1513–1515 行明确定义为 1 秒，编码为 0x41。因此 HDB 当前单播 Auto 的 Access 消息是 `82 9A 01 <TID> 41 00`，组播版本为 `82 9B 01 <TID> 41 00`。TID 由发送机制管理，不应固定重复。
- 如果需要使用 LC 已保存的 Fade On/RampUp，则对应命令为 `LightLCLightOnOffSet(true)`，Access 消息 `82 9A 01 <TID>`；无响应版本为 `82 9B 01 <TID>`。固件 `transition_get` 和 `turn_on` 在无可选字段时才选择 `srv->cfg.fade_on`。
- 普通 Group Auto 也显式带 `.default`；Device Lights 的全部 Auto 使用不带可选字段的构造方法并发往子 element 广播组。两个入口的渐变参数并不完全一致。

因此，保存 RampUp=5 秒时，当前 HDB 按钮 Auto 的首次启动会优先用 1 秒；后续 Presence 触发走 `turn_on(srv, NULL, true)`，使用保存的 RampUp。这个差异不能解释「后续完全没有感应触发」，但会影响对 Auto 初始渐变的验收。

Nordic 官方文档也把 Generic OnOff Client → LC 扩展的 Generic OnOff、LC Client → LC Light OnOff 列为两条 On 事件入口；具体厂商手动覆盖行为仍以本地固件为准：[Light Lightness Control Server](https://nrfconnectdocs.nordicsemi.com/ncs/latest/nrf/libraries/bluetooth/mesh/light_ctrl_srv.html)。

### 多段运行及后续感应所需条件

1. 配置 LC Setup 的 On/Prolong/Standby 亮度，以及 Fade On、Run/Hold、Fade、Prolong、Fade Standby 等时间。HDB 使用 On=Bright、Prolong=Dim，并将 Prolong 时间设为 0xFFFFFE；该固件解码为 0xFFFFFFFF 毫秒。源码中仍会启动计时器，本轮不把它断言为数学意义的无限时间。
2. LC Mode 必须为 true。`turn_on` 开头检查 `is_enabled`，禁用时返回 -EBUSY；OnOff 本身不代替 Mode Set。HDB 初始化是先参数、后 LC Mode、最后 Auto。
3. Auto 触发后，状态机依次 Fade On → On/Hold → Fade to Prolong → Prolong，之后按计时配置进入 Standby；不是 App 定时逐段下发亮度。
4. 要从稳定 Standby 由人体自动启动，需要 Occupancy Mode=true，且未被 manual-on、manual override 等状态拦截。On/Prolong 中的感应续时与 Standby 自动启动条件不同，不能概括成 Occupancy Mode=false 时所有感应均失效。
5. Sensor Status 路径要求 Presence 发布与 LC 接收的地址、AppKey 和订阅匹配。`handle_sensor_status` 直接在 LC Server 的 opcode 表中处理 Sensor Status，按 Property ID 分流；Presence > 0 进入 occupancy 处理，Ambient 0x004E 进入光照调节分支，Energy 不在该接收分流列表。不能因为 Energy 与 LC 共 element，就让 Energy 替代 Presence 触发。
6. 固件另有 Proximity Lighting 本地入口：`src/proximity_lighting.c` 的人体回调仅在 `_settings.enable` 开启时，直接向本地 LC 注入 Presence。当前没有该开关实值，不能假定自身 PIR 总会绕过发布/订阅链直接控制 LC。

关于既有 0013/1000 缺绑疑问：在 LC 的 Auto 与 Sensor Status 处理函数中，没有把 LC Generic OnOff 的绑定作为调用 `turn_on` 的前置检查。选择 Generic OnOff 控制时需要配置它自己的 AppKey 绑定；当前使用 130F 的 Auto 则不能仅因 1000 缺绑就判为命令错误。以上是源码入口证据，不替代底层收包和现场状态验证。

### 本轮验证与未完成项

完成只读追踪：产品/element composition、Sensor 类型和回调、App Descriptor 映射、HDB/普通 Auto 消息与路由、SDK 编码、固件两种 LC On 路径、主灯手动路径、状态机计时与 Sensor 分流。仅更新本分析文档，未修改 App、SDK、固件或服务器，未运行构建或真机。

如需继续定位现场感应不恢复：确认运行固件对应源码版本；在一次 Auto 和再次人体触发期间获取已有日志 `Set Light OnOff`、`Set Generic OnOff`、`Sensor src ... dst ... id ...`、`ignore sensor...` 及 LC params。当前结论足以确定命令类别与目标选择，但不能确认现场 Sensor 消息已送达，也不能据此宣称感应问题已经修复。

## HDB Auto 使用设备 RampUp 与添加 preparation 核对（2026-10-21 18:12）

### 已授权修改

用户确定主动 Auto 使用设备保存的 RampUp。本轮修改两个 HDB 生产入口：

- `HDBLightingMessages.message(.auto)`：改用不带 Transition Time/Delay 的构造方法；覆盖添加初始化、Lighting Configuration 的单播/组播/广播。
- `HDBLightingZoneService.control(.auto)`：Zone 控制同样省略可选字段。

单播 Access 消息为 `82 9A 01 <TID>`；无响应版本为 `82 9B 01 <TID>`。保留原目标、On 值、ACK 校验和 SDK 的 TID 管理。设备保存的 RampUp 不需要迁移；已初始化设备下次 Auto 即使用新报文，不要求重做 preparation。普通 Group Auto 本次未修改。

两文件为五品牌共享代码，没有品牌独立编译分支、资源归属或依赖变更，采用 SunSmart 代表构建。原有 Presence publication 生产与 Tests 差异保留；未修改 SDK 或固件。

### 添加时是否实际安排 LC Mode=true

答案为是，属于 UI 名称为 `hdb_preparation` 的 `.initialization` 任务。内部枚举 `.preparation` 则专指 Sensor 发布/订阅任务；不能因 LC Mode 不在这个枚举分支中就认为未下发。

完整入口：Classic / Professional 添加控制器 → 标准 FastAdd 完成、回执应用 → `HDBDeviceAddCompletion.run` → `prepareIntent` → `SyncTaskPlanBuilder` → `HDBDeviceSyncService.makeSteps` → `.initialization` → `makeHandles`。

关键依据：

1. `HDBPreparationTarget.init(model:)` 对每个 0x130F 设置 `occupancyMode=true, mode=true`，与是否有 Sensor 无关。
2. `HDBLightingMessages.preparation` 将这两个值编码成 `LightLCOccupancyModeSet(true)` 和 `LightLCModeSet(true)`，目标为实际 LC Model。
3. `HDBDeviceSyncTask.makeHandles` 按顺序组织：其他基础配置/Occupancy Mode → Bright、Dim、RampUp、RampDown、Hold → LC Mode=true → Auto。每个相关模型按其 element 路由。
4. `receive` 对 LC Mode Status 的参数进行严格匹配；`persist` 要求任务 handle 全部成功且收到匹配 ACK，才能保存完成初始化签名。失败、取消、错 ACK 或签名保存失败不结算完整准备成功。
5. 添加协调器在标准配置失败或未完成绑定时不启动 HDB 后半段；最终仍有待同步则显示失败/未完成，普通 Sync 可继续恢复。初始化签名已完成后，普通 Sync 不无条件重发 LC Mode；它也不是实时回读设备 LC 状态。

标准 FastAdd 对未加入普通 Group 的灯具仍有 `LightLCModeSet(false)`，Classic 与 Professional 均如此；随后 HDB preparation 再设 true。因此日志先看到 false 并不等于 HDB 最终关闭 LC，必须继续确认后半段 true/Auto 与任务结算。

### 添加时是否启用了传感器

需要区分四层配置：

| 项目 | 当前 HDB 添加是否下发 | 含义 |
| --- | --- | --- |
| LC Mode=true | 是 | 启用 LC 控制器 |
| Occupancy Mode=true | 是 | 允许人体占用事件从 Standby 自动启动 |
| Presence Publication 与 LC Subscription | 有 Sensor 时建立接收链；仅在完整且唯一识别 004D 时配置该实例发布 | 让人体消息发送到设备 sensorGroupId，LC 订阅同一地址 |
| 厂商 `pirEnabled=true`，0x46/0x01 action publish | 没有作为 HDB 添加准备项发送，也没有在此流程回读 | PIR 动作发布开关仍依赖固件默认/已保存状态 |

Presence 属性缺失/未识别完整时，当前 preparation 会跳过 Publication，不猜 element、不额外保持 HDB Publication 待同步；标准入网 readiness 仍保留其自身条件。Ambient 与 Energy 不由 HDB 添加配置 Publication。另有 `lightAutoAdjustEnabled=false`，表示关闭光照自动调节，与启用人体 Occupancy Mode 不矛盾。

对 `pirEnabled` 的核对不限于 HDB 文件：标准添加追加消息、SDK 标准发现、共享 Sync/Profile 链中，没有新 HDB 设备无条件开启它的路径。普通 Group Profile 的暂时禁用/恢复机制使用另一套 context；HDB 添加明确传入 nil。共享 Sync 在退出普通 Group 失败等恢复场景可能生成 `.pirEnabled(true)`，这不是新 HDB 添加的准备保证。

本份固件 `bsp_pir.c` 的 `_enable` 默认 1，但会从 `pir/enable` 持久存储恢复；PIR 定时处理在 `_enable` 为真时才分发人体事件。0x46/0x01 Set 修改并保存此值。因此「LC/Occupancy 已启用」「Publication 已配置」「SDK 缓存 pirEnabled=true」均不能替代该开关的实时证据。

本轮只分析传感器启用状态，不新增 `pirEnabled` 准备命令。如果后续确定要求强制启用，应另行覆盖设备能力判断、ACK、readiness/重试及既有初始化签名恢复，不能仅在页面补一次发送。

### 本轮验证

- `check_hdb_lighting_messages.py`：生产 Auto 方法与实际映射 SDK 的编码器，确认 0x829A/0x829B 均只有 On+TID；沿用 LC Mode/Occupancy Mode 真值及参数/ACK 回归。
- `check_hdb_zone_control.py`：实际 Zone 控制入口省略渐变字段，其他控制、权限及急停限制保留。
- `check_hdb_integration.py --device-tasks`：参数在 Mode 前、Mode 在 Auto 前；部分失败、恢复、迟到/错误 ACK 等现有回归通过。
- `check_hdb_integration.py --add-execution`：实际添加协调器和任务规划/持久化链通过；无线与 Session 边界仍为替身。
- SunSmartLocal / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建退出码 0。固定 DerivedData 为 `SunSmart-feat-HDB-261020`；SDK one-dev `8c5af55`，未修改。

真实渐变与感应仍待用户验收：设 RampUp=3 秒并 Set 成功，再执行 HDB 单播 Auto 或 Zone Auto，观察从低亮度向 Bright 是否按保存时长渐变。传感器动作发布开关是否实际开启、感应是否送达 LC，本轮没有设备回读或运行证据。

## 与普通 Group Occupancy 添加流程对比（2026-10-21 18:20）

### 结论

当前 HDB 添加并没有遗漏 LC Mode=true、Occupancy Mode=true 或末尾 Auto。与普通 Occupancy Group 相比，已证实的主要差异为：自身专用感应组与共享组的消息来源不同、HDB 未下发感应灵敏度、基础参数覆盖较少、手动覆盖超时更长、Sensor Publication 不重传。它们是有条件的排查方向，尚无运行证据将其中一项确认为现场根因。

针对此前“Auto 后亮起、约 10～13 秒后变暗、有人时不恢复”的表现，应先定位 Presence 事件是否产生、是否到达 LC、是否被 LC 拦截。当前代码已足以排除“必须把 Auto 换成 LC element Generic OnOff 才能感应”的推断。历史样本的 Pub/Sub 缓存匹配，也不足以确认设备实际运行链路畅通。

### 实际添加路径和差异

普通灯具入组使用 `GroupProfileSyncContext(reason: .memberAdded)`，触发完整 Profile 参数同步。快速添加将标准初始化/订阅与 Profile 后续任务分开；不能只比较 FastAdd 的前半段。HDB 在标准添加后执行独立 preparation，且被普通 Profile 同步入口隔离。

| 配置或行为 | 新设备加入普通 Occupancy Group | HDB 添加 |
| --- | --- | --- |
| LC Mode / Occupancy Mode | 完整 Profile 写 true / true | 基础初始化写 true / true，最后激活 Auto |
| 人体消息来源 | Presence 发到 Group 地址；组内接收灯具可以响应其他节点的事件 | 唯一识别的 Presence 发到本设备 sensorGroupId；本设备 LC 订阅该地址 |
| Sensor 实例识别 | 选择 `presenceDetectedSensorModel` | 要求所有 Sensor 类型已知，且至多一个 004D；未识别完整时跳过 Publication |
| Publication | period disabled；成员数 ≤3 时 retransmit=2，否则=1，间隔 100 ms | period disabled；retransmit disabled |
| 感应灵敏度 | 新成员完整同步写 Profile 灵敏度，默认 95%，编码 0xF332 | preparation 没有写入或回读灵敏度，依赖设备默认/已保存值 |
| `pirEnabled` 动作发布开关 | 普通新成员流程并非无条件发送 true；Profile 编辑保存时有独立保护/恢复流程 | 添加 context 为 nil，没有该保护/恢复流程，也不主动写 true |
| 手动覆盖 | 开启，使用 Profile 超时；默认 600 秒，超时目标 Standby | 开启，间隔 0xFFFFFFFF 毫秒，目标 Standby |
| LC 参数覆盖 | 按 Profile 写 On/Prolong/Standby、T1～T5，并同步亮度范围；支持的设备还同步 LC 场景/清理旧触发条件 | 写 Bright、Dim、RampUp、Hold、RampDown，固定 T4=0xFFFFFE；未显式设置 Standby、T5、亮度范围、灵敏度 |
| 已准备后的重新同步 | 新成员/类型切换强制完整 Profile；普通同步依据缓存差异 | 初始化签名已完成则不会无条件重发基础配置，Pub/Sub 也主要依据 SDK 缓存 |

HDB 当前 Auto 仍是 `82 9A 01 <TID>`，Zone Auto 为 `82 9B 01 <TID>`，均省略可选渐变字段。普通 Group Auto 的显式 1 秒渐变差异只能解释主动开灯的渐变时间，不能单独解释后续人体事件完全无效。

“启用传感器”有两个不同命令：Profile 的 `.sensorEnabled` 是 `ConfigModelPublicationSet`；`.pirEnabled(true)` 才是厂商 `0x46/0x01` 动作发布开关。不能把两个名字当成同一层配置。

补充核对：`ProfileSensorProtectionContext` 不仅用于类型切换，也可由已有 Profile 的编辑保存创建；`SyncTaskPlanBuilder` 仅在 `inNodes == nil && outNodes == nil` 的相应组同步中追加临时禁用/目标恢复。前一类型不是 occupancy、目标为 occupancy 时开启符合能力条件的传感器；原来已经是 occupancy 时仅恢复初始记录为开启的传感器。因此，“改成 Occupancy 后正常”和“新设备直接加入已有 Occupancy Group 后正常”不是完全相同的对照实验。

### 可能原因，按现场定位优先级排序

1. **Presence 没有实际到达本机 LC。** 普通组可能由其他节点触发，掩盖被测设备自身发布的问题；HDB 对自身链路的依赖更直接。此前样本为 0011/1100(004D) → C0BF → 0013/130F，AppKey 均为 3，缓存没有明显地址错误，但仍需确认真实 Publication、Subscription、绑定及 Sensor Status。若 Sensor 类型识别不完整，当前 HDB 会跳过 Publication；历史样本类型完整，不支持将此分支认定为该样本的原因。
2. **LC 收到了 Presence，但处于手动覆盖等拒绝状态。** 固件 occupancy 入口会在 `MANUALLY_OVERRIDED` 时忽略人体事件，并重新计时。HDB 的 0xFFFFFFFF 毫秒使此状态很难自然恢复，普通 Profile 默认 600 秒。Auto 会清除此标志，因此必须有 Auto 后再次进入覆盖的证据，不能只凭超时设置就认定根因。主灯 element 的 Generic OnOff/亮度手动控制与 LC element Auto 必须分开检查；外部控制或场景也应按实际时序核对。
3. **动作发布开关关闭，或感应灵敏度保留了不适合当前场景的值。** HDB 没有保证这两个实际状态。普通 Group 新成员会写灵敏度，这是明确差异；若对照流程包含 Profile 编辑/类型切换，还可能额外执行 `pirEnabled=true`。但 PID2502 对应源码的 `_enable` 默认 1、灵敏度默认 65535，而且初始化确实应用灵敏度到 PWM；不能声称固件必须先接收 0x40 才会工作。若设备确实完成恢复默认且指示灯来自固件 PIR 回调，此方向优先级下降。
4. **设备实际状态与初始化签名/缓存不一致，或残留了 HDB 没覆盖的旧配置。** 标准无组 FastAdd 先关闭 LC，HDB 后半段才开启；后半段未成功时必须看待同步/失败状态。正常完成后若设备状态后来被更改，HDB 普通 Sync 不保证重新读取或重写全部基础参数。普通 Group 完整 Profile 对 Standby、T5、亮度范围、LC 场景等覆盖更多。此方向对未彻底恢复默认、跨 Profile 复用设备更有意义；Standby/T5 缺写本身不解释“Prolong 中正值 Presence 完全不触发”。
5. **观察条件不一致，或无线丢包。** 普通 Profile 默认 Hold 为 1200 秒，历史 HDB 样本为 10 秒；普通组保持亮着不等于已经证明人体续时有效。HDB 的 5% Dim 也可能视觉上像熄灭，应区分 Prolong 与 Standby。Publication 重传差异会影响跨设备事件可靠性，但自身正常本地回送不依赖无线收回，不能把无重传当作本机持续失败的首要解释。

两个不宜当作差异根因的项：普通 Occupancy Profile 同样没有在此路径明确设置 Occupancy Delay；LC 130F 接收 Sensor Status 和 Auto 的处理函数也没有把同 element 的 1000 是否绑定作为前置条件。若改发 Generic OnOff，才需额外保证其自身绑定，不能据此反推当前 LC 命令错误。

### 固件消息链补充证据

- `src/bsp_pir.c` 的动作回调受 `_enable` 控制，并恢复 `pir/enable` 和 `pir/settings`。检测持续有效时会再次报告，不是仅依赖 Publication Period；所以 period disabled 不等于关闭人体上报。
- `src/mod_sensor_pir_srv.c` 的 `pir_handler` 调用发布函数后更新 LED_1；发布调用没有检查返回结果。若用户看到的正是这个 LED，它最多说明回调执行，不能证明 Sensor Status 成功到达 LC；独立传感器模块的指示灯证据更弱。
- `patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/access.c` 的 `bt_mesh_has_addr` 会查本机 element 的订阅组；`net.c` 的 `bt_mesh_net_send` 对匹配地址调用 `net_loopback`，随后送入本地接收链。源码明确存在自身组地址回送，不能断言 Mesh 不支持本机 Sensor 控制本机 LC。内存分配失败会记录 `Unable to allocate loopback`，但现场没有该日志，不能凭此推定资源故障。
- `src/sr_light_ctrl_srv.c` 的 `handle_sensor_status` 先检查 LC enabled，再按 Property ID 解析；正值 Presence 进入 occupancy 处理，后者还检查手动覆盖、manual-on、Occupancy Mode 和状态机阶段。

以上依赖所提供固件源码。实际运行 firmwareID 与该源码/构建配置的对应关系仍未确认。

### 最短对照与下一步边界

1. 用同一台设备，普通 Occupancy Group 仅保留这一台有感应设备；将 Bright/Dim/Hold/RampUp/RampDown 设为与 HDB 相同。离开至变暗，再进入，确认真正发生一次人体触发恢复，避免其他传感器和长 Hold 干扰比较。
2. 对比两次实际设备状态：LC Mode、Occupancy Mode、Presence Publication、LC Subscription 与 AppKey、`pirEnabled`、灵敏度、手动覆盖配置。导出 JSON 仅是缓存依据，不替代设备回读。
3. 保留一次 Auto → 变暗 → 人体触发的时序日志：PIR `status:1` → 发布/本地接收 → LC `Sensor src ... dst ... id ...` → `ignore sensor(...)` 或状态转换。先判定“未产生/未到达”还是“到达但拒绝”，再决定 App 修复项。

现阶段不建议直接把整个 Group Profile 初始化复制到 HDB：会改变 HDB 两段调光、超长 Prolong 与手动覆盖语义。若确认要补灵敏度或动作发布开关，需要分别定义默认值/设备能力、真实返回格式、ACK 与重试、旧初始化签名如何重新执行；若问题在固件运行链路，则由固件团队提供日志/修复并联调，App 不代改固件。

### 本轮核对范围

只读核对普通成员添加、完整 Profile 任务生成、Profile 保存保护机制、HDB preparation 与 Auto、SDK 组订阅、固件 PIR/发布/本机回送/LC 接收和拒绝条件。主要 App 入口为 `DeviceGroupDeferredSyncPlanner.swift`、`Node+SyncData.swift`、`Node+MessageHandles.swift`、`SyncDevicesCellModel.swift`、`SyncTaskPlanBuilder.swift`、`HDBConfiguration.swift`、`HDBDeviceSyncContext.swift`、`HDBDeviceSyncService.swift`。本轮仅更新本文件；没有修改生产代码、运行构建、操作真机或确认现场根因。

## 标准 Site 成功入组日志与 HDB 发布订阅对照（2026-10-21 18:37）

### 新证据与对上一轮判断的收窄

用户提供 `/Users/maginawin/Desktop/doing/wwd/add to group and OK.txt`，明确说明标准 Site 直接添加到 Occupancy Group 后能够正常运行。对照 HDB 仍使用此前 16:58:36 导出样本，加上当前源码；尚没有 HDB 同阶段的完整配置/人体消息日志。本节严格区分标准侧实际发包与 HDB 侧源码计划/缓存。

两份材料的设备 UUID 相同，PID=0x2502、VID=0x0003；标准日志 Firmware Information 返回的 firmwareID 与 HDB 导出相同，均为 `0103260020461D00`。重新入网后地址不同：标准为 0002/0003/0004，HDB 为 0011/0012/0013，比较时应按 element index 对齐。

本次日志能够排除上一轮的三个默认值假设：标准侧实际 Hold=5 秒而非默认 1200 秒；实际 manual override timeout=0xFFFFFFFF，与 HDB 相同；日志末尾多次收到来源 0002、目标 C000 的 Presence=true，确实来自被测设备自身。不能再把本例解释成“其他传感器代触发”“长 Hold 掩盖问题”或“两边覆盖超时不同”。用户确认的正常运行结果与这些实包证据合并使用，但 App 收到 Sensor Status 仍不是 LC 内部状态日志。

### 1. 标准 Site 实际配置流程

按日志中的 Access PDU 与 Success 回执还原：

1. 绑定 AppKey 1：三个 element 的 1100/1101，以及 0004 的 130F/1310 等模型均有成功回执。
2. 标准子 element 广播订阅：0003/1306 Add FEFD（第 449～457 行）；0004/130F Add FEFD（第 458～466 行）。
3. Descriptor：0002 返回 004D Presence；0003 返回 004E Ambient + 0055 Illuminance；0004 返回 0072 Energy + 0080 Active Energy。对应第 467～519 行。
4. 入组：依次向以下八个对象发送 Subscription Add C000，全部收到 Success（第 570～641 行）。

| element | Model | 订阅目标 |
| --- | --- | --- |
| 0002，index 0 | 1000 Generic OnOff | C000 |
| 0002，index 0 | 1300 Light Lightness | C000 |
| 0002，index 0 | 1303 Light CTL | C000 |
| 0003，index 1 | 1306 CTL Temperature | C000 |
| 0004，index 2 | 130F Light LC Server | C000 |
| 0002，index 0 | 1100 Presence Sensor Server | C000 |
| 0003，index 1 | 1100 Ambient/Illuminance Sensor Server | C000 |
| 0004，index 2 | 1100 Energy Sensor Server | C000 |

5. 仅向 **0002/1100 Presence** 配置 Publication（第 642～662 行）：地址 C000、AppKey 1、TTL=255、Credentials=false、Period=disabled、Retransmit=2 次/100 ms。报文为 `03 02 00 00 C0 01 00 FF 00 0A 00 11`。没有给另外两个 Sensor Server 配置 Publication。
6. 写 Profile：LC Mode=true、Occupancy Mode=true、manualControl=false、lightAutoAdjust=false、覆盖超时 0xFFFFFFFF；On/Prolong/Standby=100/50/0%，T1～T5=2/5/2/0/2 秒；保存 FF00 场景，写灵敏度 95%。本文件没有发送 0x829A/0x829B、0x8202/0x8203，也没有 `pirEnabled=true` Set。
7. 进入普通 Group 页后，Proxy Accept List 增加 C000（第 1050～1051 行）；第 1144 行起出现多次 `SensorStatus(Presence Detected=True), src=0002, dst=C000`。

因此成功案例的实际人体链为：0002/1100 发布 Presence → C000 → 0004/130F 消费。额外 Sensor Server 的 Subscription 不代表它们也配置了发布，或参与了人体数据的生成。

标准订阅列表来自 `SiteViewController` 设置的 `groupSubscriptionModelIDs`，SDK `Node.getSubscribeToGroupMessages` 遍历 `supportModels` 生成 Add。标准 Profile 的 Presence Publication 另由 `Node+SyncData.getNodeSyncProfiles` 和 `Node+MessageHandles` 生成。日志里八次 C000 Add 与此链路一致。

### 2. 当前 HDB 的配置流程与对象

HDB 标准入网阶段仍执行绑定、Descriptor 发现及非主 element 的 FEFD 订阅。随后 `HDBDeviceAddCompletion` 在标准完成且 readiness 满足后进入独立任务：

1. `ensureSensorGroup` 分配设备独占地址，历史样本为 C0BF。
2. `HDBDevicePreparationPolicy.subscriptionTargets` 仅选择 130F，因此 preparation 发 **0013/130F Add C0BF**。
3. `publicationTargets` 只选择唯一 004D 所在 1100，因此发 **0011/1100 Publication=C0BF**。AppKey 3、TTL=255、Credentials=false、Period=disabled、Retransmit=disabled。
4. 初始化基础参数、LC Mode/Occupancy Mode，最后 Auto。
5. 若 `lightingZonesStatus=pending`，继续执行 Zone 全量重建；新设备即使 Zones 为空也会规划。当前代码先对 LC 同 element 的 1000/130F/1310 全部 Overwrite FEFD，再对这些对象全部 Add C0BF，随后处理其他目标的清空或 Zone 地址。空 Zone 下主 element 的 1000/1300/Vendor 会 DeleteAll；1100 不属于 Zone requiredTargets。

第 5 步由 `zoneSensorTargets`、`zoneBroadcastTargets` 与 `HDBLightingZonePolicy.operations` 联合决定。当前实现已经按“先完成所有同表 Overwrite，再 Add Sensor 地址”的顺序保护 LC 接收组；源码没有显示随后又无条件清掉该 LC Sensor 地址的路径。但设备真实最终表需回读，尤其不能只检查第 2 步的 Add 成功。

所有 Configuration 消息发送给节点主地址，由 payload 的 elementAddress/modelId 指定要操作的对象。HDB 把 Subscription 消息发到 0011、payload 写 0013/130F 是正确的配置服务器路由，不能因此说发错 element。

历史 HDB 导出结果如下：

| 相对对象 | 标准成功日志 | HDB 历史缓存 / 当前目标 |
| --- | --- | --- |
| index 0 /1100 Presence Publication | C000，AppKey 1，重传 2 次 | C0BF，AppKey 3，不重传 |
| index 1/2 /1100 Publication | 无对应 Set | 无 Publication |
| index 2 /130F Subscription | FEFD + C000 | FEFD + C0BF |
| index 0/1/2 /1100 Subscription | 都 Add C000 | 都为空，HDB 不给它们加 C0BF |
| index 0 /1000、1300、1303 | Add C000 | 空 Zone 样本中为空 |
| index 1 /1306 | FEFD + C000 | FEFD |
| index 2 /1000、1310 Subscription | 未单独向它们 Add C000；由相关模型规则共享 | 缓存为 FEFD+C0BF；Zone 重建会逐个操作 |

普通组使用 C000、HDB 使用 C0BF 本身没有问题，两者都是普通组地址；关键是发布和 LC 接收使用同一个地址和 AppKey。App 的内部 `Group.isVirtual` 标记也不改变本轮已构造的 C0BF 数值地址、普通 Subscription Add 与 Publication 消息。

### 3. 哪些差异能说明问题，哪些还不能

**已证实的主要差异是订阅范围和后续修改方式，而不是 Presence 发布错 element。** 标准对多个控制模型和三个 Sensor Server 做组订阅，HDB 对独占感应组只建立 LC 接收链；标准本次只有 Add（共 10 次，其中 2 次 FEFD），没有 Delete/Overwrite，HDB 后续还有全表重建。

仅凭标准侧给 1100 订阅、HDB 没有，就断言“必须给三个 Sensor Server 都订阅才能触发 LC”，证据不足。所提供固件中，`sr_light_ctrl_srv.c` 将 Sensor Status 的处理入口注册在 **130F**；`access.c` 按 opcode 找接收模型，再检查该模型的 AppKey 和目标组订阅。同 element 扩展模型共享订阅查询，但 `find_group_mod_visitor` 明确跳过其他 element。按这条源码链，130F 自己正确订阅就能接收 Presence，并未以三个 1100 都订阅为前置条件。

当前可成立的排查优先级：

1. **确认 Zone 重建后的 130F 真实订阅。** 若 C0BF 已不在设备表中，问题落在配置生命周期/重建结果，而不是首次 Publication 的对象选择；现有缓存不能替代最终 Subscription Get。也应同时回读 Presence Publication 和两端 AppKey。
2. **确认真实发布是否存在。** 正常日志已经证实 `0002 → C000`，HDB 缺少对应 `0011 → C0BF` 的运行证据。可观察设备已有日志或在有相应监听条件时观察 App 收包。
3. **对缺少 Sensor Server Subscription 做单变量对照。** 若最终 LC 订阅、Publication 均正确，可保持其他参数不动，仅给 HDB 的三个 1100 加同一个 C0BF，检查是否恢复；此操作是待执行的诊断建议，不是已证明必要的修复。若恢复，应核对运行固件对 Sensor 订阅的额外依赖；若无变化，继续查发布返回值/本机回送/LC 拒绝原因。不要同时补全部 Profile 参数，避免失去因果区分。
4. Publication 重传 2 次与 0 次可另做单变量对照，但设备本地回送源码独立于手机是否收到无线消息，不能直接把不重传判为本机持续失效的原因。

**手机 Proxy Filter 是第三层配置，必须与设备模型订阅分开。** 普通 `GroupViewController.proxyFilterAddGroup` 会加 C000，日志也实际出现该命令；当前 HDB 页面/添加链没有为 sensorGroupId 做对应监听配置。HDB App 看不到 Sensor Status，可能只是代理没有转发给手机；这不等于 LC 没收到，也不是设备离线自动运行的必要前提。

成功日志也没有对 index 2 的 Generic OnOff 1000 发送 AppKey Bind，LC 接收则绑定了 130F/1310。不能继续把 HDB 的 LC element 1000 缺绑作为两边行为不同的直接证据。

### 4. 三段调光参数的独立差异与结论边界

本次标准 Profile 实际为 On=100%、Prolong=50%、Standby=0%，T4=0；状态机仍会经过相应阶段，但没有稳定停留的 Prolong。历史 HDB 为 Bright=80%、Dim=5%、T4=0xFFFFFE，固件解码为 0xFFFFFFFF ms，且没有显式写 Standby/T5。两套行为不能预期完全相同的第三段到达时间；这项差异不解释“有效 Presence 无法让 Dim 回 Bright”。

最终结论：发布者和 LC 消费者的类型/element 对齐正确；标准确实比 HDB 多订阅三个 Sensor Server 及主灯控制模型，且没有 HDB 的后续 Overwrite/DeleteAll 重建。尚不能把订阅对象较少直接定为根因。最有区分力的证据是 HDB 全部任务结束后的真实 Pub/Sub，以及一次自身 Presence 的发送/LC 接收记录；本轮没有这些 HDB 实包，不能声称已定位唯一故障。

本轮只读分析日志、历史导出和当前 App/SDK/固件源码，更新本文件并检查文档格式；未修改业务代码、未执行诊断 Set、未构建或操作真机。此前测试/构建记录不外推至当前其他任务新增的未提交修改。

## 新入网跳过空 Zone 重建并补齐 Sensor Server 订阅：确认方案（2026-10-21 21:29）

### 用户要求和判断

用户明确设备已重置后重新加入 HDB，希望添加时不再执行没有必要的空 Zone 订阅重建；增加所有 SIG Sensor Server 0x1100 对 sensorGroupId 的订阅，sensorGroupId 为空则不生成该订阅；不在 preparation 或 Zone 完成后增加设备回读。本轮仅分析和规划，不实施。

两项调整合理：已知重置且目标 Zone 为空时，设备已满足空 Zone 目标，不必再 Overwrite/DeleteAll；补齐三个 Sensor Server 的订阅可对齐标准成功案例中的这部分配置。该调整有明确的流程与对照依据，但尚未证明缺少 Sensor Server 订阅是感应故障的唯一根因，验收仍需重置重加后的真实表现。

边界为“已知重新配网、目标 Zone 为空”，不能扩展成“凡是 Zones 为空就跳过”。用户把非空 Zones 清为空，需要真的删除旧订阅；恢复设备时若保留了非空 Zone 目标，也仍需下发恢复。

### 已查明的现有成因与使用方

1. `HDBDeviceConfiguration.lightingZonesStatus` 默认 `.pending`。
2. `HDBDeviceSyncService.prepareIntent` 首次建立初始化身份会调用 `HDBConfigurationStore.restoreDevice`；后者无条件把 Zone 状态改为 `.pending`。因此只改新建记录默认值仍会被后续覆盖。
3. `makeSteps` 无条件请求 `context.zoneOperations`，Zone policy 看到 pending 后即生成重建，包含空目标。
4. `prepareIntent` 不仅由添加调用，普通 Sync 的 `prepareIntents` 也会调用；plan 签名变化不等于设备真的重置。`HDBDeviceAddCompletion.run` 则由 Classic、Professional 和 Device Restore 在标准入网完成后调用，适合作为明确的重新配网上下文。
5. `restoreDevice` 还被 Device Restore 的资料迁移直接调用。其非空 Zone 恢复语义必须保留。
6. `pendingLinks` 同时供 preparation、`isPrepared`、`canSetZones` 使用。`canSetZones` 目前无差别放行所有缺失订阅，假设 Zone 会修复它们；新增 1100 订阅后这个假设不再成立。

### 修复一：记录重置后的空 Zone 已满足目标

在新配网/恢复完成链中明确传递“订阅已重置”的事实，建立初始化 intent 时一并处理 Zone 状态，沿用现有存储字段与 revision 机制，不增加云端 schema：

| 场景 | Zone 状态及任务 |
| --- | --- |
| 新添加、已重置、没有保存的 Zone 成员 | 持久化空目标 `.synced`，不生成 Zone 重建 |
| 已重置恢复、保存的 Zone 成员为空 | 同上 |
| 已重置恢复、保存的 Zone 成员非空 | `.pending`，保留 Zone 恢复 |
| 用户将已有 Zone 成员清空 | `.pending`，保留实际清空任务 |
| 已发出过 Zone 变更，失败/取消后为空 pending | 保留 pending 和重试，不用“空值”替代成功 |
| 普通 Sync、重新计算 preparation 签名 | 不因签名变化把已确认的空 synced 强制变回 pending，也不把真实待清理的空 pending 改成 synced |

具体处理位置优先为 `HDBDeviceAddCompletion` → `prepareIntent` / `restoreDevice` 的共享状态边界。不要在 `makeSteps` 里简单过滤空 Zone，也不要全局更改 DTO 默认值或解码缺省来伪造完成。

空 Zone 的 `.synced` 只表示“无 Zone 成员需要下发”。Sensor Subscription、Publication 和 LC 初始化仍由自己的 ACK/签名决定 readiness；它们任何一步失败，设备仍需同步。已保存空目标状态应在失败重试、退出重进后保留；签名保存失败也不能无条件重新制造空 Zone 重建。

标准入网已有 FEFD 订阅，LC 对 sensorGroupId 的 Add 仍属于 preparation，所以取消这轮空 Zone 重建不会取消这两项必要配置。实施测试需确认这一点。

### 修复二：preparation 增加全部 0x1100 订阅

优先扩展现有 `HDBDevicePreparationPolicy.subscriptionTargets`，复用 `.preparation(.subscription(target))`、消息构造、严格 ACK、串行依赖、缓存持久化和失败重试，不另建发送器或独立同步系统。

- 订阅集合为原有 LC 130F 接收目标，加当前 composition 中全部 `companyIdentifier == nil && modelIdentifier == 0x1100` 实例；按 element/model 去重并保持稳定顺序。
- 不依据 Sensor Property 筛选新增订阅：Presence、Ambient、Energy，以及类型尚未识别的 1100，均属于订阅对象。Vendor 恰好使用 0x1100 不纳入；不额外向 1101 发命令。
- sensorGroupId 非空时发送 `ConfigModelSubscriptionAdd`；为空时不生成新增 Sensor Server 订阅，不猜地址、不发送地址 0。
- 继续使用现有 sensorGroupId 分配机制。正常有 Sensor 的新设备会先分配地址；分配失败仍保留 preparation 未完成/可重试，不能因为新增任务跳过而把整台设备标成准备成功。用户的“为空不订阅”不解释为取消地址分配或放宽整体完整性检查。
- 配置消息发到节点主地址，payload 指定各 Sensor 的实际 element 和 1100。保留现有绑定前置条件和 `ConfigModelSubscriptionStatus` 的地址/model/status 严格校验。
- 已存在的目标订阅按现有缓存差量逻辑跳过；部分成功只重试尚未完成的目标。不增加 Subscription Get、Publication Get、Sensor Get 或其他结束回读。
- Publication 仍仅配置唯一识别的 Presence Sensor；Ambient/Energy 不增加 Publication，未知属性跳过 Publication 的既定规则保留。TTL、重传、PIR 动作开关、灵敏度、LC 时间/亮度参数均不顺带修改。

预计新设备主链为：标准入网 → sensorGroupId 分配 → LC 及全部 1100 的 Subscription Add → Presence Publication → 参数/LC Mode/Auto → 完成。初始 Zone 为空时没有后续 Zone 重建。

### 必须同时处理的联动

**Zone readiness：** `canSetZones` 不再把所有 `.subscription` 缺项都当成 Zone 能修复。仅当缺项目标确实属于当前 Zone 计划负责重建的 LC 接收对象时才允许放行；缺失 1100 订阅应保持 preparation 未完成，先由同步补齐，再允许应用非空 Zones。现有“清空 Zones 用于恢复/清理”的路径仍可执行，但不能把设备整体 readiness 一起结算成功。

**Zone 保留范围：** 不把 1100 加进 `HDBLightingZonePolicy.requiredTargets`。否则会让每次 Zone 编辑给 Sensor Server 订阅全部 Zone 地址，扩大本次需求。现有 Zone 重建只操作控制模型，三个 1100 及其同 element 的 1101 订阅表不属于该集合；继续保持这条边界，并测试编辑、清空、重试后 Sensor 的 sensorGroupId 不被删除。LC 共享表的 FEFD/sensorGroupId 保留机制继续沿用。

**初始化签名：** plan 内包含 subscriptionTargets，新增 1100 会改变签名。沿用既有签名检测与恢复机制，但不得把“签名不相等”当成设备已重置、进而跳过真正的空 Zone 清理。按既定范围以重置重加入验收，不新增旧设备 schema 迁移，也不使用原签名绕过新增订阅要求。

### 预计改动与验证

生产改动集中在 `HDBDevicePreparationPolicy.swift`、`HDBDeviceSyncService.swift`、`HDBConfigurationStore.swift`、`HDBDeviceAddCompletion.swift`；按复用需要在 `HDBDeviceSyncContext.swift` 提供目标查询。Zone policy 的既有重建算法原则上保留，不扩大它的控制对象。保持当前其他任务对 MAC、单播配置等未提交修改。

复用现有 HDB preparation、device-sync、device-tasks、add-execution、Zone integration 测试，重点覆盖：

1. 三个不同 element 的 1100 都 Add sensorGroupId；Publication 只有 004D；未知属性仍订阅；Vendor 1100 被排除；nil 地址没有新增订阅消息。
2. 新入网空 Zone 在实际任务规划中没有 `.zone`、Overwrite/DeleteAll；仍有 LC/Sensor Add、Publication、Mode 和 Auto；标准 FEFD 保留；无结束 Get。
3. 1100 Add 超时/失败/错 element ACK/取消/迟到回复不结算完成；重试补齐；缺项不能被非空 Zone Apply 绕过。
4. 已重置且有保存成员的恢复继续重建；主动从非空清为空继续清理；空 Zone 清理失败重试继续保留；保存失败/签名保存失败/重进后状态连续。
5. 后续添加、修改、清空 Zones 保留所有 1100 的 sensorGroupId，同时保留 LC 的 FEFD 与 sensorGroupId，不把 Zone 地址分配给 Sensor Server。

实施完成后运行上述相关脚本、`git diff --check`，再核对本地 SDK 映射并构建一次 SunSmart generic iOS。共享逻辑无品牌差异时不机械重复五品牌；不自动操作真机。人工验收为重置重加、确认只有必要 Add/Set、等待 Dim 后人体触发回 Bright，再编辑/清空 Zones 后复测。验收不要求增加自动回读。

21:29 规划时状态：方案待实施；仅更新本分析文档，未运行回归或构建，未下发设备命令。用户随后确认实施，以下记录覆盖最新代码和验证结果。

## 新入网订阅修复实施与验证（2026-10-21 21:41）

### 已完成的 App 改动

| 位置 | 最终行为 |
| --- | --- |
| `HDBDeviceAddCompletion` | Classic、Professional、Device Restore 的标准入网完成后，通过共享入口明确传入 `subscriptionsWereReset: true`。 |
| `HDBDeviceSyncService.prepareIntent`、`HDBConfigurationStore.restoreDevice` | 已知重置且目标 Zones 为空时持久化 `.synced`；保存的非空 Zones 仍设为 `.pending` 并恢复。普通 Sync 默认不声明重置，保留空 synced 和真正待清理的空 pending。 |
| `HDBDevicePreparationPolicy` | 原 LC 130F 订阅之外，增加 composition 中全部 SIG 1100，按 element 去重排序；复用现有 Subscription Add、严格 ACK 和差量重试。 |
| `HDBDeviceSyncService.canSetZones` | 仅放行 Zone 重建本身能修复的 LC 接收订阅缺项；1100 缺项保持 preparation 未完成并阻止非空 Zone Apply。主动清空 Zones 的恢复路径保留。 |

没有修改 Zone policy 的控制对象集合；后续 Zone 配置不会把 Zone 地址加入 1100，也不会删除它们的 sensorGroupId。Presence-only Publication、LC Mode、Auto 及既有参数保持原路径。没有添加 preparation 或 Zone 结束后的任何 Get/回读。

`sensorGroupId == nil` 时不构造或发送新增订阅。仍沿用现有分配机制；有 Sensor 但分配失败时保持可重试的未完成状态，不猜地址，也不把 nil 当成整体 preparation 成功。已成功保存的“重置后空目标”在签名保存失败和重新打开后的普通 Sync 中保持；若在该状态首次持久化之前即失败，普通 Sync 无法取得重置证据时继续采用原有保守恢复，不推定设备已清空。

新增订阅会改变现有 plan 签名。存量设备再次 Sync 时沿用原有初始化失效及恢复机制；不引入 schema 迁移、不放宽旧签名，也不把签名变化视为设备重置。

### 自动化验证

以下均在本次代码状态运行并通过：

- `python3 scripts/check_hdb_device_preparation.py`：策略、device-sync、device-tasks、add-completion、add-execution、subelement 六组检查。
- `python3 scripts/check_hdb_integration.py`：实际 Store/Zone Service/Executor 的完整重建、清空、失败恢复、严格 ACK 和迟到回复。
- `python3 scripts/check_hdb_lighting_configuration_service.py`：共享 readiness 下的单播、多 element 回执、空/待同步 Zones、失败/取消/重试。
- 完善非空 Zone Apply 拦截和无回读断言后，单独重跑 `--add-execution` 通过；`git diff --check` 通过。

新增回归覆盖三个 element 的 1100 全部订阅、唯一 Presence 发布、Vendor 1100 排除、未知属性仍订阅、nil 地址分配失败；新设备任务不含 Zone/Overwrite/DeleteAll；超时和错 element ACK 不完成目标，重试仅保留缺项；签名保存失败重进、非空恢复和真实空目标清理。新增、清空 Zone 后三个 Sensor 私有组订阅保留，且标准 FEFD readiness 持续成立。

这些测试运行生产策略、状态存储、协调器和任务代码；Mesh 无线、数据库/云端及部分消息对象由测试边界替代，subelement 测试嵌入本机映射 SDK 的实际 `isKeybindComplete`。不能视为设备或云端运行验收。

SunSmart 构建：`SunSmartLocal.xcworkspace` / `SunSmart` / Debug / generic iOS / `CODE_SIGNING_ALLOWED=NO`，DerivedData 为 `SunSmart-feat-HDB-261020`。本地 SDK 指向 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `8c5af55`，无 SDK 改动。此次直接 `xcodebuild` 退出码 0，最新构建记录为 0 errors、34 warnings，App 可执行文件更新于 21:40:56。控制台出现一次 “command failed with exit code 0” 的工具诊断，核对同次 Xcode Build Log 后未发现构建错误；没有据此重跑、清缓存或修改无关代码。

四处生产改动均为共享逻辑，没有新增资源、依赖、target 配置或品牌条件分支，本轮采用 SunSmart 代表构建。未运行 Simulator 或其他品牌构建，未自动操作真机。

### 最短人工验收

1. 重置同一设备，重新加入 HDB；初始 Zones 为空。确认发送各 element 1100 及 LC 的 sensorGroupId Add，仅 Presence 设置 Publication，随后完成初始化；没有空 Zone 重建或结束回读。
2. 等待进入 Dim，人体触发后检查能否回 Bright，并确认 RampUp 使用设备保存值。
3. 配置一个 Zone，再清空 Zone，重复感应；必要时中断一次 preparation 后普通 Sync，检查只补缺失订阅且最终完成。

现场感应是否恢复尚未验证。此次完成的是已确认的配置流程调整，不将缺少 1100 订阅宣称为已证实的唯一固件根因；既有 T4 等调光时序也未在本轮改变。

## 实测反馈与 Publication 重传对齐（2026-10-21 22:03）

用户反馈上轮版本：未 reset 的设备直接修复后感应仍无效，接受该结果；reset 后重新添加成功。这是用户提供的设备验收结果，覆盖上轮配置流程调整，尚不单独证明哪一项配置差异导致故障。

本轮按用户要求配置 sensorGroupId 的 Model Publication：period disabled，组内设备数 ≤3 时 retransmit count=2，否则 count=1，间隔均为 100 ms。标准入口的计数来源保留 effectiveMemberCount → 同步快照 → Group.nodes 的优先顺序；阈值规则提取至既有 `SensorPublicationPolicy.retransmit(memberCount:)`，HDB 和 standard 共用。

HDB 当前 sensorGroupId 是单台设备独占的自身感应组，配置中有唯一地址所有者；多个 element、三个 Sensor Server、Space 内其他设备及 Lighting Zones 都不增加该私有组的成员数。因此 HDB 传入成员数 1，实际配置为 count=2、100 ms。没有用 SDK 的普通 Group.nodes 统计 HDB 私有组：该入口按普通 group 归属统计，不代表 HDB 私有感应组成员。未来若新增跨设备订阅私有感应组的业务，需要同时扩展这项成员语义；本轮不预建该功能。

生产改动仅涉及 `Node+SyncData.swift` 和 `HDBDeviceSyncService.swift`。Publication 写入和 pendingLinks/readiness 使用同一目标值；旧 disabled、错误次数/间隔或启用周期发布会进入补写。已完成初始化的设备只需补写 Publication，初始化签名不变，不会因此重新发送 LC 参数/Auto 或重建空 Zones。匹配 ACK 后持久化并消除待同步状态，错误重传参数 ACK 不结算完成。TTL 继续 0xFF，Presence-only Publication 和无结束回读的要求保留。

验证已通过：

- `Tests/Group/SensorPublicationBehaviorTests.py`：1769 项 App/SDK 行为与报文断言，含成员数 1/3/4/1000 的阈值、100 ms 编码及标准流程兼容行为。
- `check_hdb_device_preparation.py` 的六组检查；新增覆盖 Space 有其他设备时私有组仍为 1、旧发布参数只补一项 Publication、period 检查、错误参数 ACK 拒绝、成功后不重复补写。
- `check_hdb_integration.py`、`check_hdb_lighting_configuration_service.py`、`check_hdb_zone_control.py`、`check_hdb_space_creation.py`，以及 `git diff --check`。
- SunSmartLocal / SunSmart / Debug / generic iOS / 禁用签名构建一次，退出码 0，最新构建记录 0 errors、8 warnings。本地 SDK 仍为 one-dev `8c5af55`，工作树干净；无品牌条件或资源/依赖配置变化。

HDB 回归夹具改为加载实际 App Publication policy 和本地 SDK Retransmit 类型，避免只验证固定禁用重传的替身；无线和数据库等边界仍是替身。没有自动执行真机验收，不能据离线断言宣称无线性能已经对齐。最短后续验收：对已正常工作的 reset 重加设备执行普通 Sync，确认 Publication Set 的 period=0、retransmit=0x0A（count=2、100 ms），并复测人体触发；无须为这一项参数补写再次 reset，也不增加任务结束回读。

## L1/L2：仅 Apply Lighting Zones 后不能从 Dim 回 Bright（2026-10-21 22:22）

### 结论及样本范围

用户确认：L1 添加后只配置 Lighting Configuration，二段式正常；L2 还 Apply Lighting Zones，之后感应无法从 Dim 返回 Bright，期间没有操作 Zone On/Off/亮度。因此本次不把 Zone 手动控制作为现场触发原因。

本次来源：`/Users/maginawin/Desktop/doing/wwd/Space_Space 1_20261021_221300_365+0800.json`，capturedAt 为 `2026-10-21T14:13:00Z`。同时比较 `spaces[0].nodes` 和 `_debugInspection.spaces[0].rawLocal.mesh.nodes`，两台设备的 elements 完全一致；HDB 配置也与 rawLocal 一致。它们都是本地配置/ACK 缓存快照，不是本次对设备逐模型执行 Subscription Get 的结果。没有 L2 Apply 前的同设备快照或本次 Apply 无线日志；L1/L2 是不同物理设备的操作对照。

**归一化各自 sensorGroupId 后，L2 比 L1 没有少任何已有订阅，只增加 C001/C002。当前证据不支持“Lighting Zones 完成后忘记补回自身感应订阅”。** 已证实的流程风险是重建先破坏再恢复 LC 感应链；是否因此触发设备内部状态异常、或者设备真实列表与缓存不同，目前仍是待验证假设。

### 导出差分

两台 composition 相同，PID=`2502`、VID=`0003`、firmwareID=`0103260020461D00`，AppKey index 均为 1。

| 项目 | L1，正常 | L2，Apply 后异常 |
| --- | --- | --- |
| 主地址 / LC 地址 | 0011 / 0013 | 000E / 0010 |
| 自身 sensorGroupId | C040 | C041 |
| Lighting Zones | 空，synced | Zone 1=C001、Zone 2=C002，synced |
| Presence 1100 发布 | 主 element → C040 | 主 element → C041 |
| 三个 element 的 1100/1101 订阅 | 都保留 C040 | 都保留 C041 |
| LC element 的 1000/130F/1310 | FEFD、C040 | FEFD、C041、C001、C002 |
| 主 element 的 1000/1300/Vendor 及相关控制模型 | 空 | C001、C002 |
| 第二 element 的 1002/1306 | FEFD | FEFD |
| LC Mode / Occupancy Mode / PIR enabled | true / true / true | true / true / true |
| Bright / Dim / Hold | 80% / 20% / 10s | 80% / 5% / 20s |
| RampUp / RampDown / T4 | 1s / 2s / 0xFFFFFE | 相同 |

LC property 字典的差异只有 lightnessProlong 和 timeRunOn，分别匹配上述 Dim/Hold。它们会改变暗段亮度和保持时间，本身不构成“有效 Presence 不能再次触发 Bright”的证据；后续同设备对照应固定这些参数。

两台 LC element 的 Generic OnOff 1000 都没有 AppKey bind；130F/1310 有绑定。L1 能正常运行，因此不能把这个共同状态当成本次 L2 差异的原因。两台 Presence Publication 都是 period disabled、retransmit count=0 / interval=50ms；当前 App 最新目标为 count=2 / 100ms，说明样本尚未反映该补写结果，但这同样不是两台的差异。不能将最新本地代码参数直接当作样本已执行参数，也不能仅凭该字段断言运行 App 的具体版本。

### Apply 具体破坏和恢复什么

入口是 [HDBLightingZoneDeviceViewController](../SunSmart/Main/Space/HDB/Controller/HDBLightingZoneDeviceViewController.swift) 的 Apply，经 [HDBLightingZoneService](../SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift) 保存 pending 意图，再由 [HDBDeviceSyncContext](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift) 和 [HDBLightingZonePolicy](../SunSmart/Common/Data/HDBLightingZonePolicy.swift) 生成全量重建计划。独立 Apply、失败后的 retry 和普通 Sync 的 pending Zone 恢复共用这套 planner。

对 L2 当前 topology 和 Zone 1/2，计划为 18 条订阅请求：

| 顺序 | 目标 | 操作 | 对原状态的影响 |
| --- | --- | --- | --- |
| 1，3 条 | 0010 的 1000/130F/1310 | 全部 Overwrite FEFD | 保留广播地址，但临时移除 C041 和旧 Zones；相关模型共享表会被反复覆盖 |
| 2，3 条 | 同上 | 全部 Add C041 | 补回自身 Presence 的 LC 接收链；这些 Add 之后不再覆盖该共享表 |
| 3，3 条 | 000E 的 1000/1300/0A780001 | 全部 Overwrite C001 | 清除该表旧地址；空 Zone 时改为 DeleteAll |
| 4，9 条 | LC 三个目标 Add C001，全部六个目标 Add C002 | Add | 完成 Zone 1/2，LC 最终为 FEFD+C041+C001+C002 |

**已经补齐的内容：** LC 接收表的 sensorGroupId、需要的子 element FEFD、当前选择的全部 Zones。

**不直接修改的内容：** 三个 Sensor 1100/1101 的订阅、Presence Publication、AppKey 绑定、第二 element 1306 的 FEFD。SDK 已知共享规则没有把 Sensor 表与上述控制表连在一起，最新导出也符合该范围。无需因为没有再向 Sensor 发 Add，就推断其原订阅被删除；更没有依据把 C001/C002 加到全部 Sensor Server。

**不会通用保留的内容：** 被重建控制表中，既不属于当前 Zones、又不属于受保护 sensorGroupId/FEFD 的其他订阅。主 element 的 Generic/Lightness/Scene/CTL 等同 element 相关模型也受共享表影响，Vendor 表则独立重建。如果存在普通 Group、其他业务组或固件额外地址，它们会被替换且不自动补回。本次正常 L1 这些表原本为空，没有证据将这类地址丢失认定为本次原因。

**存在的中断窗口：** 第一阶段后、第二阶段 Add 成功前，LC 暂时没有 C041，Presence 组消息可能无法被正常接收。若失败或取消停在这里，可持续缺订阅，当前实现会保留 pending 供重试。L2 本次导出为 synced 且已恢复 C041，不符合缓存可见的“停在该阶段”状态。短时中断本身不足以解释成功结束后持续不能触发，需要额外设备运行证据。

### 为什么最终 JSON 正确仍不能排除设备侧问题

本机 SDK `one-dev` HEAD 为 `8c5af55`，映射正确且只读核对时工作区干净。`ConfigurationClientHandler.swift` 在成功收到 SubscriptionStatus 后，按请求类型修改请求模型及同 element relatedModels 的缓存；这些缓存被保存并导出。因而三个相关模型同时出现 C041 不能等价于逐个独立设备回读。

Zone service 逐请求验证 status success、element、model/company、address，再按阶段持久化，最后标记 synced；它确认这些配置请求的回执，不确认人体事件已送入 LC。流程结束没有重新下发 LC Mode、Occupancy Mode、Auto，也不重新应用 Lighting Configuration。这是现有职责划分，**尚不能把“没有重发 Auto”直接认定为遗漏或修复依据**：订阅命令是否改变了固件运行态尚未证实。

普通 Sync 的 preparation 检查依赖初始化签名和本地链路缓存；已有 synced Zones 不无条件重建。对本样本，最新代码会检测旧 Publication 重传参数并补写，但不能据此保证发现或恢复缓存之外的 LC 状态故障。

只读交叉核对已有固件 `/Users/maginawin/Developer/SunSmartDev/sunsmart-fireware` HEAD `585c45a`：

- `src/main_demo.c` 注册三个 element 的 Presence/Ambient/Energy Sensor；`src/sr_light_ctrl_srv.c` 将 Sensor Status 接收入口注册在 LC，并定义 LC→OnOff、LC Setup→LC 及跨 element Lightness 扩展。
- 现有 `access.c` 的共享组查询明确跳过其他 element，接收时按 opcode、AppKey 和目标组筛选；未发现 Sensor 与 Generic/LC 的额外共享注册。
- 未找到 Overwrite/DeleteAll 直接调用 LC disable/reset/解绑的证据。配置服务器 `cfg_srv.c` 属外部 SDK，本地未提供，无法完整排除该实现的副作用。LC reset callback 是节点 reset，不能当作订阅 DeleteAll 的 callback。
- 现场 firmwareID 与该源码 revision 的对应关系未确认，以上只作链路交叉证据，不据此断言现场固件实现已被完全覆盖。本任务没有修改固件或服务器。

### 收敛建议与验收边界

现阶段不建议继续盲补 Sensor/主灯订阅，也不建议把全部 Lighting Configuration 重发作为通用处理。优先保留失败 L2，做最小单变量定位：

1. 若可取得一次性设备诊断，核对失败状态的 `0010/130F` 实际 Subscription List 是否有 C041，以及 `000E/1100` 实际 Publication；必要时扩展到 1000/1310、三个 1100 和 LC Mode/Occupancy。只是本次诊断，不增加每次 Apply 结束后的自动回读。
2. 保持 Zones 和参数不变，仅对 L2 执行一次单播 Lighting Control Auto Set；等它再次进入 Dim 后，再测试人体是否能回 Bright。仅 Auto 命令让灯亮不算恢复证据。若重复人体触发恢复，则优先调查重建前后 LC 状态；若不恢复，继续核对实际 Presence 发送和 LC 接收，而非把问题归结为 Auto 未重发。
3. 若问题稳定发生在纯 Apply 路径，App 值得对照验证的调整是只 Add 新 Zones、Delete 移除的 Zones，使 sensorGroupId 和 FEFD 全程不被清空。该方向可消除已知中断窗口，但尚未证明能修复现场持续失效；实施需同时覆盖 Apply、retry、普通 Sync、清空 Zones 和取消后恢复，不能只换页面按钮路径。历史缓存与设备不一致时的修复仍需明确边界，不能直接把旧 full rebuild 删除而无恢复方案。

本轮完成 JSON/rawLocal 对比、App/SDK 链路审查和有限固件只读核对。`python3 scripts/check_hdb_integration.py --subelement` 本轮通过，覆盖现有 0/8 Zones、有/无 Sensor、共享表、FEFD、失败重进恢复；它使用生产 planner/context/task 和实际 SDK readiness getter，但 relatedModels/无线/数据库等仍有替身，不能验证固件内部 Overwrite 副作用。没有新增业务代码或测试文件，没有构建或操作真机，没有取得现场 Apply 报文及真实 Subscription Get。

任务期间检测到外部提交将 App HEAD 从 `146469a6` 推进到 `b7cd24d8`，内容为原有 Publication 重传改动；本次涉及的 ZonePolicy、Context、ZoneService 和 PreparationPolicy 无提交间差异，分析结论不受影响。本次仅更新此文档，不提交 Git。

## 设备回读证实 LC 订阅丢失：跨 element 清表与修复规划（2026-10-22 00:20）

状态：分析与方案，尚未实施。用户提供的 Read Subscriptions 结果，是本次设备侧证据；未收到完整诊断报告和 Apply 无线报文。本轮不修改 App/SDK 生产代码、固件或服务器，不操作真机。

### 1. 结论与对上轮判断的修正

用户在 Set Lighting Zones 后再清空，读到 `0010/1000、130F、1310` 的 App saved 均为 C041/FEFD，而 device actual 均为空；正常设备配置 Zones 后也会发生。**本次已不只是怀疑短时感应中断，而是实际最终订阅丢失。** 130F 缺少自身 Presence 发布目的地址 C041，足以破坏 Dim → Bright 的人体触发接收链；FEFD 同时缺失还影响 App 约定的子 element 广播控制。

已找到与现场一致的具体机制：**LC 先补齐，主 element 后清表；后面的清表沿跨 element 模型扩展环删除 LC 订阅，而 App SDK 只更新同 element 缓存。** 在实际生产 planner 上分别模拟设备清表范围和 SDK 缓存范围，可以精确重现“非空 Zones 只剩 Zone 地址，空 Zones 完全为空，App 却一直有 C041/FEFD”。

上轮“补回 C041 后不再覆盖该共享表”的表述只检查了 App 按 element 划分的表，未覆盖设备全扩展环的清除语义，需要修正。`find_group` 只查询同 element，不能推导 `Overwrite/DeleteAll` 也只清同 element。上一轮常规回归也只模拟 SDK 同 element 缓存，无法发现这类分歧。

证据边界：本地固件明确具有跨 element 扩展环，公开 Zephyr 配置服务明确具有相应清表语义，现场回读与隔离复现一致；但现场固件所使用的 `cfg_srv.c` revision 尚未提供，因此不声称已逐指令核对现场二进制。App 可以独立修正当前顺序缺陷，不等待或擅自修改固件。

### 2. 三个模型及两个组地址的作用

| 对象 | 本设备中的作用 | 本次缺失的含义 |
| --- | --- | --- |
| element 2 / 0010 / 1000，Generic OnOff Server | LC 控制器的通用开关入口，与主 element 直接控制灯的 1000 是不同实例 | 与同 element LC/Setup 共享订阅关系；三个 empty 不能简单理解成三条彼此无关的故障 |
| 0010 / 130F，Light LC Server | LC Mode、Occupancy Mode、LC Light OnOff；接收 Sensor Status 并处理 Presence 事件 | 缺 C041 后，发往 C041 的 Presence 不再满足该模型的组地址接收条件，这是人体触发链的关键缺项 |
| 0010 / 1310，Light LC Setup Server | 配置 Bright/Dim、Hold、Fade 等 LC Property，通过扩展关系关联 LC | 订阅为空不等于参数被清零；单播参数配置仍可能正常，因此 Lighting Configuration 能成功不排除订阅断链 |
| C041 | L2 独占的自身感应组，主 element 的 Presence Sensor 向它发布 | 应在清空所有 Lighting Zones 后仍保留于 LC 接收表；其他设备应使用各自保存的 sensorGroupId，不硬编码此值 |
| FEFD | 项目/SDK 约定的 Subelement Broadcast 组地址 | 非用户 Zone，清空 Zones 不应将它从需要的子 element 广播接收表移除 |

不把 LC 1000 的 AppKey bind 空值认定为本次原因：正常 L1 曾有相同状态，且本次是设备实际订阅从有到无。也不通过重发 Auto 或修改调光时间掩盖缺失；Auto 命令不能替代订阅修复。

### 3. 成因证据与完整时序

App 的 [HDBLightingZonePolicy](../SunSmart/Common/Data/HDBLightingZonePolicy.swift) 目前按 broadcast → sensor → reset → add 执行：

1. 对 LC 三个模型逐个 `Overwrite FEFD`。
2. 对同三个模型逐个 `Add C041`。
3. 对主 element 的 1000、1300 和 Vendor 执行 `Overwrite 第一个 Zone`；清空 Zones 时则执行 `DeleteAll`。
4. 有 Zones 才继续 Add Zone 地址；此阶段不再补 FEFD/C041。

本地固件 `src/sr_light_ctrl_srv.c` 明确将 130F 与主 element 的 1300、LC element 的 1000 相连，并将 1310 关联 130F。`patches/nrf_3.2.4/zephyr/subsys/bluetooth/mesh/access.c` 的 `bt_mesh_model_extensions_walk` 遍历整个环，不自行筛 element；同 element 限制只在特定查询 visitor 内。

对缺少的配置服务器实现，交叉核对了 [Zephyr v4.2.0 cfg_srv.c](https://github.com/zephyrproject-rtos/zephyr/blob/v4.2.0/subsys/bluetooth/mesh/cfg_srv.c#L1028-L1144)：Overwrite/DeleteAll 的清理 visitor 没有 element 过滤，且遍历扩展环；Get 的列表 visitor 则筛选 element。这个差异为上述失效机制提供了公开实现依据，但该版本不是已经确认的现场固件版本。

因此，**第 3 步的主 element 1300 已足以把第 2 步刚补好的 LC 表清空**，无需假设 Vendor 或 Sensor 有额外共享。若还有 Zone Add，最后只恢复 Zones；若清空 Zones，第 3 步就成为最终设备状态。

App SDK 的 `ConfigurationClientHandler` 对成功 SubscriptionStatus 只更新请求模型及同 element relatedModels，因而第 3 步不清 App 内 LC 的缓存。所有命令都可以返回成功：后一次命令把先前结果删除不代表先前 ACK 错误。Zone service 又只在最后依据 ACK 标记 synced，所以出现“synced + App 正确 + 设备缺项”。

新增 Diagnostics 使用 `updatesLocalState=false`，校验响应类型、element、model 和成功状态后直接读取 `SubscriptionList.addresses`；当前 SDK codec 读取真实状态字节。它没有把失败响应默认为成功空列表，也没有用 SDK 缓存替代 actual。诊断读取不自动覆盖 saved，因此两列保持差异符合设计。

### 4. 推荐本次最小完整修复

**保留现有全量目标与重试机制，但把所有破坏性写入与最终 Add 严格分开。** 不只是交换两个现有 stage；必须保证最后一次 Overwrite/DeleteAll 之后，完整目标中的每一个必要地址都有显式 Add。

| 阶段 | 要做的事 | 必须保持的约束 |
| --- | --- | --- |
| A：全局清表 | 完成本设备全部目标上的 Overwrite/DeleteAll，保留各目标现有清表种类和种子地址 | 这里的“全局”指本设备本次 Zone 任务，不涉及其他设备。种子地址可能再被后续跨 element 清除，不能依赖它作为最终结果 |
| B：恢复基础订阅 | 对 broadcastTargets 无条件 Add FEFD，对 sensorTargets 无条件 Add 当前 sensorGroupId | 即使 App 缓存已显示存在，也必须发 Add；空 Zones 也执行。此后不得再有任何 Overwrite/DeleteAll |
| C：完整添加 Zones | 向全部 Zone targets Add 每一个当前目标 Zone | 包括以前依靠 Overwrite 留下的第一个 Zone，不能继续跳过这些目标 |
| D：完成 | 全部必要请求身份匹配、成功 ACK、持久化成功后才 synced | 失败/取消保持 pending，重试从 A 开始重放；旧回执不得完成新意图 |

关键实现细节：

- 主要修改共享 planner，保持独立 Apply、`retry(nodeUuid:)`、普通 Sync 的 pending Zone 路径和非空设备恢复都采用同一顺序。不要只给页面追加末尾 Add。
- 不能把阶段 A 简化成对全部模型 DeleteAll：普通 Sync 的 `HDBDeviceSyncTask.makeHandles` 依赖 `isKeybindComplete`，若 App 缓存 FEFD 被清空，可能阻断自己的后续修复。保留 LC 当前 Overwrite FEFD 的清表方式，同时在阶段 B 再显式 Add，回归检查每个 ACK 后的 readiness。
- 不改 SDK 的同 element 缓存规则来假装修复设备；也不将跨 element 接收订阅列表错误合成一张。设备最终修复靠实际 Add 命令完成。
- 不扩大 Zone 地址订阅对象集合，不给三个 Sensor 添加 Zone 地址，不重置亮度/时间、Mode/Auto 或 Publication。当前 PID2502 的 1306 只与自身 Generic Level 关联，未发现它属于主灯/LC 清表环，不无依据增加其修复操作；现有 Sensor 1100 表也未发现进入此环。
- 保留现有失败和 pending 语义，不新增 hdb schema、清理日志或数据库迁移。旧故障设备保留现有 Zones 选择再次 Apply，即可强制重放；空目标也会补回 FEFD/感应组，无需 reset。缓存仍为 synced 的设备不能指望普通 Sync 自动发现，明确以同目标 Apply 作为本次存量恢复入口；pending 状态继续由普通 Sync 恢复。
- 沿用现有权限、身份/revision、共享通道、严格 ACK 及取消处理；标准 Site 不改。相关业务逻辑为五品牌共享，若实施不新增文件/资源/依赖或品牌条件，采用 SunSmart 代表编译。

该方案仍保留配置过程中的短暂感应中断，不承诺配置过程无缝；它解决已证实的最终订阅丢失。在当前证据下，不需要为假设的内部 LC 状态问题扩大为控制器重新初始化。

### 5. 与按地址增删方案的比较

按地址 Delete/Add 可以避免全表清除，是可选的后续方向；但本次不优先采用，因为 `replacingZones` 会覆盖旧成员。只依据 old/new 内存差量，在失败、再次编辑、退出重进后可能失去待删除的旧 Zone 信息。可靠实施至少需要持久清理集合，或在每次事务开始读取实际订阅，再生成删除计划；不能只凭已经证明会失真的 App 缓存推断设备无残留。枚举 63 个未选 Zone 全量 Delete 则会明显增加报文数。

本次全局清表→完整 Add 复用已有持久意图和从头重建恢复，改动范围更小，且无需新增每次 Apply 前/结束后的回读。诊断按钮继续作为人工验收入口。若后续产品要求配置过程中持续感应，再单独规划增量事务。

### 6. 已完成的隔离验证与实施后验收

本轮临时夹具直接编译生产 `HDBConfiguration.swift` 和 `HDBLightingZonePolicy.swift`；设备侧按跨 element 全环清表模拟，App 侧按同 element 缓存模拟。结果：

| 当前生产计划 | App LC 最终值 | 模拟设备 LC 最终值 |
| --- | --- | --- |
| 2 Zones，18 条请求 | C001/C002/C041/FEFD | C001/C002 |
| 0 Zones，9 条请求 | C041/FEFD | 空 |

随后只在临时夹具中重排计划并补全 Add，未改生产文件：0/1/2/8 Zones 最终均为目标 Zones + C041/FEFD；从“缓存已有、设备为空”起步，在每个请求位置中断后完整重放，共 118 个隔离场景收敛。缓存 FEFD 在每次模拟 ACK 后仍满足恢复所需条件。对应请求数为 12/18/24/60；空 Zones 比现有多 3 条，非空多 6 条，未引入回读。

这证明候选算法能修复所建模机制，不等于已实施或真机通过。实施时需要将这类行为回归正式放进现有 Tests/HDB，不能继续用同一份状态同时代表 SDK 缓存和设备实际订阅。

实施后最小自动化范围：共享 planner/Zone executor、subelement、device-task 与 add/recovery 的相关既有检查；新增覆盖跨 element 清表、真实表为空但缓存正确、0/1/2/8 Zones、Sensor/nil 合法边界、主 LC/多 element、错误 ACK、每阶段失败/取消/重试及重启后目标替换。确认没有晚于恢复阶段的破坏性请求，且非空首个 Zone 在全部目标得到 Add。生产 Swift 修改完成后构建一次 SunSmartLocal / SunSmart / Debug / generic iOS / 禁用签名；不运行 Simulator 或自动真机。

最短人工验收：

1. 已故障 L2 不 reset，保持空 Zones 再 Apply；Read Subscriptions 应看到三个 LC 模型 actual 恢复 C041/FEFD，且没有旧 Zone。
2. 添加 Zone 1/2 后回读，应为 C041/FEFD/C001/C002；再清空，应回到 C041/FEFD。对正常设备重复，确认不再被破坏。
3. 每次 Apply 后等待进入 Dim，再触发人体回 Bright；重启 App 后保留相同结果。需要验证设备持久化时再单独断电重启设备。
4. 配置中断后重试，确认 pending → synced 的转换及设备实际最终表，不能只看 App Export JSON。

当前工作树在本轮期间由外部提交推进至 `b50ca4c4`（新增 HDB Diagnostics）；Zone planner 的变更仅为等价提取 `isZoneTarget`，上述操作顺序未变。SDK 仍为 one-dev `8c5af55` 加既有诊断 codec/只读 Get 未提交差异，本轮未改 SDK。该诊断功能的正式 SDK 发布待办继续保留，详见 [诊断实施记录](261021_2330_HDB_device_diagnostics_plan.md)。本轮只更新此分析文档，不构建、不提交 Git。

## 纯 DeleteAll → Add 方案评估与修订计划（2026-10-22 00:37）

状态：用户要求分析和规划，尚未授权实施。本轮只更新本文档；App HEAD 为 `b50ca4c4`，未改业务代码、SDK、固件或服务器，未操作真机。

### 1. 推荐结论及替代范围

推荐采纳用户提出的纯 DeleteAll → Add 方案。它把“删除旧状态”和“建立最终状态”分开，空 Zones 与非空 Zones 使用相同机制，不再依赖 Overwrite 的种子地址或第一个 Zone 特例，失败后也能从头重放同一计划。

可靠性的关键是**所有清表完成后才开始 Add，且 Add 覆盖全部必要最终订阅**，不是 DeleteAll 的清除范围比 Overwrite 小。两者都可能沿同一模型扩展环清表；单纯替换命令仍会保留原顺序缺陷，并暴露 FEFD 缺失后的恢复自阻断。

因此，此处替代上一节“保留 LC Overwrite FEFD 以维持 readiness”的折中建议。正确方向是如实清除 App 缓存，并让已授权的订阅恢复任务能够在自己创建的中间状态继续执行。不能继续用缓存保留 FEFD 来规避 readiness。

该方案仍有清表至基础订阅恢复之间的感应中断窗口，失败后可能延续至重试完成；目标是成功后的最终一致和中断后的可恢复，不承诺无线配置永不失败或配置过程中无缝感应。

### 2. element 0 是否会清掉其他 element 的相同 Model

**可能跨 element 清除，但“Model ID 相同”不是判断条件。** 应按具体模型实例及其扩展关系判断，实例标识包含 element address、model identifier 和 company identifier。

| 当前设备对象 | 清表影响判断 | App 处理要求 |
| --- | --- | --- |
| 主 element 1300 与 LC element 130F/1310/1000 | 本地固件存在跨 element 扩展链；主 1300 清表可清除 LC 表，符合现场 actual empty | DeleteAll ACK 后，跨 element 清除该链缓存；全部清表结束后恢复 LC 的 FEFD、自身感应组和目标 Zones |
| 不同 element 的同名 1000 | 同名本身不共享；当前主灯与 LC 可经 Lightness/LC 扩展链相连 | 不按 Model ID 批量清整个节点，不按 element 边界漏清扩展链 |
| 第二个 element 的 1306/1002 | 已核对 1306 仅扩展自身 Generic Level；与 CTL 的 correspondence 不等于加入清表扩展环 | 当前不因主灯/LC 清表移除或重建它们的 FEFD |
| 三个 element 的 1100/1101 Sensor 实例 | 未加入主灯/LC 扩展环，三个相同 ID 不构成彼此共享 | 保留现有 Sensor 表及 Publication，不添加 Zone 地址 |
| Vendor 0A78/0001 | SDK 不提供 Vendor 扩展图，现有证据也未证明其与 SIG 共享 | 作为自己的 Zone 目标清表并恢复，不臆造 Vendor/SIG 共享关系 |

上节链接的 Zephyr 实现说明 DeleteAll 的全扩展环清除与 Add/Get 的同 element 共享并不对称。现场 cfg_srv revision 尚未确认，因此这些缓存规则应限定在本次已有证据的 HDB 重建路径，不趁此全局改写标准 Site 的 SDK 配置回调。

这里“所有 elements 的 DeleteAll”指**本设备各 element 上，本次 Zone 重建拥有的目标模型**，不是对节点的所有 Model 一律 DeleteAll。先前识别出的 Zone 目标范围保持不变；清表影响分析则必须覆盖目标之外的相关模型。

### 3. 计划生成：一个清表阶段，之后只 Add

统一修改 [HDBLightingZonePolicy](../SunSmart/Common/Data/HDBLightingZonePolicy.swift) 与 [HDBDeviceSyncContext](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncContext.swift)：

1. 从当前有效设备及保存的目标计算 Zone targets、每个清表目标的完整扩展影响集合，以及需要恢复的基础订阅。使用现有 `relatedModels`，不新建独立模型能力表；不按跨 element 扩展环合并成只发一条 DeleteAll，以兼容共享范围不同的设备实现。
2. **Reset：** 对全部 Zone targets 逐个 DeleteAll。当前 L2 共 6 个目标。此阶段不 Add FEFD、不 Add sensorGroupId，也不 Add 第一个 Zone；全部请求成功后才允许下一阶段。
3. **Restore broadcast：** 对需要恢复的子 element 广播接收表 Add FEFD。
4. **Restore sensor：** 对 LC 接收表 Add 该设备保存的 sensorGroupId。无 Sensor 的合法设备跳过此项；有 Sensor 但缺少组分配时沿用既有错误与准备流程，不硬编码 C041。
5. **Add Zones：** 对全部 Zone targets Add 每一个选中 Zone，包括第一个。空 Zones 只省略此阶段，不能省略前面的基础恢复。
6. **Complete：** 全部阶段 ACK 严格匹配且保存成功，才将本次 intent 标记 synced；最后阶段可能是 broadcast、sensor 或 reset，不能以“有 Zone Add”作为完成前提。

基础恢复范围按既有业务规则确定，不能直接把旧缓存所有地址 Add 回去，否则会恢复本来要求删除的旧 Zones。对扩展影响集合内、不属于 Zone targets 的模型，也要核对是否有必须保留的 FEFD/感应接收需求；若有，纳入基础恢复集合，而不扩大 Zone 地址的接收对象。当前样本的三个 LC 目标覆盖基础恢复，1306/Sensor 不受此清表影响。需要恢复的基础接收表与现有 Zone 目标列表在内存计划中区分，不新增持久化 schema。

所有 Add 均无条件发实际报文，不依据 App 缓存“已有地址”跳过。对当前 6 个目标、3 个广播及 3 个感应目标，0/1/2/8 Zones 分别为 12/18/24/60 条请求；这是计划计算，不是本轮真机计数。

### 4. 缓存与部分失败：只记录已确认结果

在 HDB 范围复用一个订阅回执处理入口，由独立 Apply 的 [HDBLightingZoneService](../SunSmart/Main/Space/HDB/Model/HDBLightingZoneService.swift) 与普通 Sync 的 [HDBDeviceSyncTask](../SunSmart/Main/Space/HDB/Model/HDBDeviceSyncService.swift) 共同调用：

- 只有当前 session、设备实例、地址、DeviceKey、网络、权限、intent/revision 均有效，且 ACK 的 status、element、model/company、address 严格匹配时才投影清表结果。
- DeleteAll 成功：对请求模型加完整 `relatedModels` 去重后调用现有公开 `unsubscribeFromAll()`，包括其他 element 和不在 Zone targets 中的相关模型。不能只清同 element，也不能用 `subscriptions` 映射出的已知 Group 列表逐项删除，以免漏掉未映射的原始地址。
- Add 成功：保留 SDK 原有同 element 共享更新；不得把 LC 的 FEFD/C041 镜像到整个跨 element 扩展环。Get/Diagnostics 继续使用现有只读观察语义，不将诊断改为自动修改 saved。
- 每条已确认 ACK 更新内存，阶段结算时保存已确认变化，包括阶段部分失败；取消应在 transport stop 结算后、身份仍有效时保存本次已确认变化。当前 direct service 的 `guard receipt.successful else { return }` 会漏掉部分成功持久化，必须同时修正；普通任务已有先保存节点再判断整阶段结果的基础，应复用而非分叉语义。
- 没收到 ACK 的设备状态视为未知，不预写“已经清空/已经添加”。整个 intent 在发送前已持久化为 pending；失败、保存失败或进程中断不标 synced，恢复时从 Reset 完整重放，不依赖阶段内进度。旧 intent/旧设备的迟到回执不得覆盖新状态。

缓存投影本身可使用现有 SDK API，不需要为它新增 SDK API，也不需要修改固件。全局 SDK `ConfigurationClientHandler` 的其他使用方暂不改变。

### 5. 必须消除 FEFD 清空后的任务自阻断

本轮临时复现直接编译生产 `HDBDeviceSyncTask` 与实际 SDK `Node.isKeybindComplete` getter：成功执行全部 DeleteAll 并持久化后，`isKeybindComplete == false`；再创建 FEFD Add 任务，`makeHandles()` 得到空数组。该结果证明仅重排和换报文无法完成普通 Sync 路径。

`isKeybindComplete` 除 AppKey 绑定，还检查初始化信息、Publication、指定子 element FEFD、Sensor 类型与固件元数据。因此不能把它整体移除，也不应在 App 复制一份会逐渐漂移的 readiness 判断。

推荐的最小客户端 SDK 配套：在 `Node+Config.swift` 复用原判断，增加只读检查入口，允许调用方提供**指定模型实例的待恢复 FEFD 检查豁免集合**。现有无参数 `isKeybindComplete` 保持严格语义；其他所有条件不变，模型实例必须属于当前 Node。该集合由有效 HDB 计划中确实会补回 FEFD 的接收表推导，不能用“忽略整个节点订阅”的 Boolean，也不能写入虚假 FEFD 缓存。

App 将此入口限于正在执行的 `.zone` 恢复任务，包括部分清表失败后的后续重放；仍保留当前身份、权限、DeviceKey、AppKey、绑定、初始化及 intent 校验。非 Zone 的 preparation/initialization/configuration/cleanup 不普遍放宽。独立 Apply 沿用其已有入口合法性规则，合法空 Zones 不因新增恢复检查被误拒；不能借此让未完成密钥绑定的新设备执行普通控制。

普通 Sync 重进链路要一起验证：`prepareIntents`、`SyncTaskPlanBuilder`、`hdbAwaitingInitialization` 当前仍使用严格 readiness。允许它们沿用标准初始化补 FEFD 后进入 HDB 的现有顺序，不为本次修复全局旁路标准初始化；但进入 HDB Reset 后，后续 `.zone` Add 必须使用上述受限恢复检查，避免再次自阻断。新设备添加完成时，已知订阅 reset 且目标为空的优化仍保留，不无条件增加清表。

该方案需要在实际映射的 `one-dev` SDK 工作树增加小范围 readiness API，而不仅是 App 修改。实施前核对 SDK 目录、未提交诊断差异和写入所有权，保留已有工作；记录新的 SDK revision/未提交差异及 release 发布待办。正式工程继续引用远端 release，不改为个人绝对路径。

### 6. 实施顺序、存量恢复与验证

建议按以下顺序完成一轮最小完整修改：

1. 将已发现的跨 element 清表及 FEFD 自阻断复现纳入现有 Tests/HDB；设备实际表与 App 缓存分开模拟，验证结果而非源码字符串。
2. 先补 SDK 受限 readiness 检查及等价性验证：无豁免时与原 getter 一致，指定 FEFD 缺失允许恢复，缺绑定/Publication/元数据仍拒绝。
3. 修改共享 planner，统一 DeleteAll → 基础 Add → 全量 Zones Add；同步两个执行入口的清表缓存和部分失败持久化，保留共享 transport、严格 ACK、取消与 intent 机制。
4. 验证 Apply、retry、普通 Sync、退出重进和新设备恢复共同使用完整计划；再处理必要的阶段名称/现有测试预期，不顺手改控制命令或业务参数。
5. 完成相关自动化后构建。开发阶段使用 SunSmartLocal / SunSmart / Debug / generic iOS / 禁用签名；由于本方案新增共享 SDK API，稳定后交付合入前覆盖全部五品牌编译，记录实际 SDK 来源与发布依赖。不运行 Simulator 或自动真机。

存量故障设备无需 reset：保持现有选择（包括空 Zones）再 Apply/retry，即可强制执行完整恢复。原状态为 pending 的设备继续由普通 Sync 恢复。缓存已错误标为 synced 的设备不会仅靠现有缓存扫描自动发现，明确使用同目标 Apply 作为本次存量修复入口；暂不增加每次 Apply 的自动回读或全项目批量迁移。

必要行为回归：0/1/2/8 Zones、有/无 Sensor、同 element/跨 element 扩展及同 ID 独立实例；受影响的非 Zone 缓存清空与必要基础恢复；从 App 有 F/S 而设备空表开始；每个请求位置中断后重放；清表部分成功/超时/错误 ACK/取消、保存失败、重启再编辑 Zones、旧 intent 迟到回执；确认完整清表后没有任何破坏性操作，最终 FEFD/C041 与目标 Zones 正确且旧 Zones 消失。特别覆盖真实 SDK readiness、两个执行入口及标准初始化后进入 HDB 的衔接。

人工验收保持上节最短步骤：故障 L2 空目标 Apply 后回读 LC 三模型 actual 为 C041/FEFD；加 Zone 1/2 后增加 C001/C002；清空后仅保留基础地址；每次从 Dim 再感应回 Bright。对正常设备重复并做一次中断重试。实际地址使用该设备自己的 sensorGroupId；同时确认 1306、Sensor Publication/订阅未受破坏。

本轮已验证的是生产任务在真实 readiness getter 下的自阻断复现，以及源码/现场证据对应关系。上一节的 118 个重放场景属于保留 Overwrite 的临时候选算法，不能作为本节纯 DeleteAll + 新缓存/readiness 实现已通过的证据；本节完整方案尚未实现或运行回归，也未构建和真机验收。

## DeleteAll → Add 修复实施与验证（2026-10-22 00:59）

用户已确认上述方案，本轮完成 App 与客户端 SDK 实施；未修改固件、服务器或正式远端依赖配置，未提交 Git、安装 App 或操作真机。

### 实际实现

- **共享计划**：移除 HDB Zone 的 Overwrite 命令分支。Reset 一次包含本设备各 element 的全部 Zone targets，后续仅有 FEFD Add、sensorGroupId Add 和全量 Zone Add。空目标仍恢复基础订阅；不以缓存已有地址跳过发送。当前样本请求数仍为 0/1/2/8 Zones 对应 12/18/24/60 条。
- **清表影响与基础恢复**：复用 SDK `relatedModels` 推导完整清表影响。成功 DeleteAll 回执后，HDB 统一回执处理器调用 `unsubscribeFromAll()` 清除跨 element 关联缓存；Add 继续使用 SDK 同 element 共享规则。若清表影响到不在 Zone targets 中的必要广播接收表，仅恢复其 FEFD，不向其添加 Zone。当前正常 1306/Sensor 表仍不受主灯/LC 清表影响。
- **恢复检查**：SDK `Node+Config.swift` 新增 `isKeybindComplete(restoringSubelementSubscriptionsFor:)`，复用原检查，仅允许指定且确属本 Node 的模型临时缺少 FEFD。原 `isKeybindComplete` 仍严格。App 仅对有效 `.zone` 任务传入该计划广播恢复目标的同 element 接收集合；绑定、Publication、Sensor 元数据等仍检查。
- **部分失败持久化**：每条严格匹配的 ACK 更新缓存并登记 dirty，阶段结束保存已确认变化，包括部分失败。普通 Sync 保留 dirty HDB task 集合，在共享停止/退出/配置失效结算入口补存，避免一个设备保存失败后被后续设备覆盖。采用阶段/结算保存，不为每条 Add 执行整节点数据库写入。
- **取消与在途回执**：独立 Apply 保持 busy 至 transport STOP 和缓存保存结算完毕。STOP 等待期间，当前唯一 attempt 的严格 ACK 仅更新缓存；普通 Sync 使用 `cacheOnly` 接收模式并显式禁止完成任务。STOP 完成后立即关闭资格，旧 attempt 回执不能清掉重试已恢复的缓存。全部 ACK 已到但尚未批次完成时取消，也只保存缓存、保持 pending。
- **身份与意图分离**：新命令、正常回执及 synced 完成仍检查完整 intent/revision；停止结算保存已经确认的物理结果时，只检查原账户/网络/节点/地址/DeviceKey/权限身份，避免修改 Zone 目标后丢弃已确认缓存。保存函数不修改新目标、不把旧任务标记 synced。

主要生产变更为 `HDBConfiguration`、`HDBLightingZonePolicy`、`HDBDeviceSyncContext`、`HDBDeviceSyncService`、`HDBLightingZoneService/Executor` 与 `SyncExecutionSession` 的 HDB 回执/结算分支。普通任务不获得 FEFD 豁免；Diagnostics 的只读查询行为保持原样。

### 本轮验证结果

先添加回归，确认旧代码无法满足全清表屏障；实施中另补 `Cancel → 在途 DeleteAll ACK → STOP 完成` 回归，并先复现跨 element 缓存未清的问题，再修复至通过。

| 验证入口 | 结果及覆盖 |
| --- | --- |
| `check_hdb_configuration.py`、`check_hdb_lighting_zone_execution.py` | 通过：全量计划、空目标、首 Zone 完整 Add、严格 ACK、阶段失败屏障、取消与共享通道 |
| `check_hdb_integration.py --subelement` | 通过：真实 SDK readiness getter；设备实际表与 App 缓存分开；纯 DeleteAll 生产计划的 118 个逐请求中断重放场景；0/1/2/8 Zones、有/无 Sensor；跨 element 与非 Zone 基础接收恢复 |
| 同一 subelement 回归的故障边界 | 通过：缺 FEFD 可恢复；外来模型、缺绑定、缺 Publication、缺 Sensor 元数据仍拒绝；部分阶段成功保存；保存失败保持 dirty；取消前/STOP 等待期 ACK、全部 ACK 后取消、同目标重试旧回执及身份/契约失效 |
| `check_hdb_integration.py`、`--device-tasks`、`--device-sync` | 通过：独立 Service 与共享任务、pending/重放、严格回执、准备链及初始化恢复、失败持久化 |
| `check_hdb_integration.py --add-execution`、`--add-completion` | 通过：新设备添加及已清空订阅的空目标基线、依赖失败、取消和持久 readiness 衔接 |
| `check_sync_execution_session.py` | 通过：生产 HDB ACK 分支接入真实 Session 调度；stop/close/配置失效结算、多个 dirty task、STOP 等待期仅缓存 ACK、晚回执隔离；共享 Coordinator 回归通过 |
| `check_hdb_diagnostics.py`、`check_hdb_lighting_configuration_service.py`、`check_hdb_zone_control.py` | 通过：诊断仍只读，Lighting Configuration/Zone 控制入口、权限与 ACK 行为未被订阅重建扩展 |
| `check_hdb_import_recovery.py` | 通过：旧配置、空值、导入与持久目标恢复边界 |
| App 与 SDK `git diff --check` | 通过 |

本轮 118 场景直接运行新的生产 planner/task，不是引用前述保留 Overwrite 的候选结果。无线、模型扩展图及数据库在隔离回归中仍有边界替身；不能据此称真实设备订阅或数据库运行体验已经验收。

最终生产代码使用 `SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。串行复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-HDB-261020`，以 Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO 完成 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux **五品牌 BUILD SUCCEEDED**。未运行 Simulator 或真机；这些构建均包含最终 STOP 在途 ACK 修复。

### SDK 交付与人工验收

App 基线 `b50ca4c4`，本轮修改留在当前工作树。SDK 基线 `8c5af55`，本轮只新增 `Sources/NordicSigMeshSDK/MeshLib/Node/Node+Config.swift` 的 14 行差异，保留原有诊断 codec/只读 Get 的 7 个生产文件和对应未提交测试脚本。正式 SDK release 必须同时具备诊断 API 与本次 readiness API，再交付引用它的 App；本地五品牌构建不代表远端依赖已经发布。

用户最短验收：

1. 故障 L2 无需 reset，保持空 Zones 再 Apply，Read Subscriptions 应看到 LC 1000/130F/1310 的 actual 恢复 C041/FEFD。
2. 加 Zone 1/2 后回读应增加 C001/C002，再清空应只保留 C041/FEFD。对正常设备重复，确认 1306 和 Sensor 表未被破坏。
3. 每次等待进入 Dim，再触发人体，应能回到 Bright；中断 Apply 后重试，并重启 App 检查 pending/synced 与实际列表。

实际地址按各设备自己的 sensorGroupId；配置期间仍存在短暂感应中断。对缓存已误标 synced 的存量故障，本次以同目标 Apply/retry 强制修复，不新增自动批量迁移或每次 Apply 自动回读。
