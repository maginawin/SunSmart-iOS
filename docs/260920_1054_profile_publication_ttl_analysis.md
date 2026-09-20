# Group Profile publication TTL 与跨楼层感应范围分析

日期：2026-09-20。本文保留最初分析与确认方案；以下分析描述修复前基线。

**最新状态：用户确认后已完成 App 修复，行为回归及 SunSmart generic iOS 构建通过；Fast Add 综合脚本存在已复现于原 HEAD 的空 Path 契约失败，详情见末尾实施记录。未操作设备，跨楼层效果待现场验收。**

## 结论

1. 当前 Occupancy sensing Group 会为具有 Presence Sensor Model 的设备生成标准 Model Publication 配置，目标为灯组地址。实际消息构造使用 App SDK 的 `networkParameters.defaultTtl`，当前 SDK 初始化明确设为 **5 / 0x05**，不是 `0xFF`，也不读取目标设备的 `defaultTTL`。
2. 因而“设备 Default TTL 已改为 15 或更大，但传感器仍只能控制附近设备”的猜测有直接源码依据。若现场该 Sensor Model 的 Publish TTL 仍为 5，修改设备 Default TTL 不会扩大这条 publication 的跳数预算。
3. 这是已证实的配置策略问题；尚不能仅凭源码认定它是现场故障的唯一原因。需要读回真正触发感应的设备、正确 element 上的 Sensor Server publication，并做仅改变 TTL 的对照。楼层数不等于 Mesh 跳数，15 不保证覆盖 40 层。
4. 相同写法影响 Occupancy、Vacancy、Occupancy with daylight harvesting、Vacancy with daylight harvesting、Daylight harvesting 五类 profile 的相应传感器发布。Manual 不主动建立这类发布；两类 Proximity Lighting 使用独立私有邻居机制，不能直接套用标准 Publish TTL 的结论。
5. 同步判定只比较组地址和 retransmit，不检查 TTL、AppKey、Friendship flag、period。因此旧 TTL 可以被认为“已同步”，只修改消息构造还不能完整修复已部署设备。

## 分析基线

- App：`fix-gateway`，HEAD `b33b61a9b1eee62db6efad6bc8ac0cfdf36d8b0f`；分析开始工作区干净。
- 本地入口：`SunSmartLocal.xcworkspace` → `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`a971027e08f9775d7a3f071a06f89be1c38ecc96`，无未提交改动；正式 workspace 的 `Package.resolved` 同样锁定此 revision。
- 这些是本机当前代码事实。现场 App 版本、固件版本和设备实际读回尚未提供。

## 配置链与完整参数

`Node.getNodeSyncProfiles` → `.sensorEnabled` → `ProfileType.getMessageHandles` → `ConfigModelPublicationSet` → `ConfigModelPublicationStatus` → `model.publish` 缓存。

Presence 与 Ambient Light 通过对应 Device Property 识别 Sensor Server（SIG Model ID `0x1100`）所在 element，不能只凭节点 primary address 猜测 Sensor Model 的 element address。没有对应传感器 Model 的灯具不会生成该 Model 的发布任务。当前通用消息构造在 `.sensorEnabled` 分支前还要求存在 Light LC/Light LC Setup Model；对于独立传感器，应额外核对组成数据和其实际执行入口，本次跨楼层灯组的结论以正常灯具配置链为主。

| 字段 | 当前普通 Profile 同步值 |
| --- | --- |
| Publish Address | `group.address.address` |
| AppKey Index | 当前 Space 使用的 `currentApplicationKey.index`，不是硬编码 0 |
| Friendship Credentials Flag | `false` / 0 |
| Publish TTL | `networkParameters.defaultTtl`；当前初始化为 `0x05` |
| Publish Period | `.disabled`，编码 `0x00`；本入口 `delay = 0` |
| Publish Retransmit Count，组成员 ≤ 3 | 2，首次发送加 2 次重发，共 3 次 |
| Publish Retransmit Count，组成员 > 3 | 1，首次发送加 1 次重发，共 2 次 |
| Publish Retransmit Interval | 100 ms，Interval Steps = 1 |
| Count 与 Interval 的组合字节 | 小组 `0x0A`，大组 `0x09` |

成员数来自显式 `effectiveMemberCount`，否则读取同步上下文成员数，再退回 `group.nodes.count`；不是可用中继数量或在线传感器数量。大组再大也不进一步调整此处的次数和间隔。

Period 为 0 关闭的是该字段控制的周期性发布，不表示禁止感应事件发布。事件产生、PIR/RADAR Action Publication 开关以及 Sensor Cadence/固件自己的行为属于其他状态。Publication retransmit 是每条发布消息的额外重发，不是收到 ACK 后再决定重试，不是配置命令的超时重试，也不是 Network Transmit 或 Relay Retransmit。

编码证据：SDK 的 `ConfigModelPublicationSet.parameters` 直接追加 `publish.ttl`，没有把数值 5 替换为 `0xFF`。SIG Model 的 Access PDU 为 `03 + ElementAddress(LE) + PublishAddress(LE) + AppKeyIndex/CredentialFlag + TTL + Period + Retransmit + ModelID(LE)`。Sensor Server 的 ModelID 尾部为 `00 11`；当前大组该段参数为 `05 00 09`，建议 TTL 策略下为 `FF 00 09`，地址和 Key Index 必须来自实际配置。

## 为什么修改设备 Default TTL 不解决当前 publication

Bluetooth SIG Mesh Protocol §4.2.3.5 定义：Publish TTL = `0xFF` 时，模型发布使用源节点的 Default TTL；具体数值则作为模型发布 TTL。`0xFF` 是继承标记，不是 255 跳。§4.2.3.6–7 定义 publication 额外重发次数及 `(steps + 1) × 50 ms` 间隔。

官方依据：[Bluetooth SIG Mesh Protocol 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MshPRT_v1.1/out/en/index-en.html)。本地 SDK `Publish` 的注释与该语义一致。

例如，源设备 Default TTL = 15、Sensor Server Publish TTL = 5 时，发布仍使用 5。将 Publish TTL 设为 `0xFF` 后才使用源设备的 15。中继的 Default TTL 并不会在转发途中把原消息 TTL 补回 15；中继沿途递减消息自身 TTL。只增加接收灯或中继节点的 Default TTL 也不能补偿源头的 publication 限制。

设备 Information 页的 `InformationTTLMeshService.setTTL` 仅发送 `ConfigDefaultTtlSet`，没有同时修改 Model Publication，符合两个不同状态的协议边界。

## App 全开全关为何仍能成功

普通组开关使用 `LightGroupControlCommandSender.setGroupOnOff`，发送 `GenericOnOffSet[Unacknowledged]`；AUTO 使用 Light LC OnOff。它们由 App 发起，不使用感应源的 Sensor Model publication。

当前 SDK 发送 Access Message 的 TTL 优先级是：Lab 全局发送覆盖值 → 本条消息显式 TTL → 本地 Provisioner Node Default TTL → SDK `networkParameters.defaultTtl`。`LabSettings.applyOutgoingMeshTTLOverride` 修改独立覆盖值，不修改 `networkParameters.defaultTtl`，更不会改写 publication 配置负载。

因此，即使 Lab 中已把 App 发送 TTL 调高，传感器 publication 仍可被写成 5。实际现场 Lab 配置未知，不能假定已经开启。即使 App 与传感器 TTL 相同，不同注入位置/Proxy 路径也会改变覆盖范围。

“App 能控制所有设备”说明该次 App 控制链能够到达设备，不足以证明 Sensor Status 的源点路径、消息处理状态及发布参数均正确。手动开关可能触发 Manual Override，现场对照测试前还要恢复 AUTO，避免把手动抑制误认为收不到感应消息。

## 全部 Group Profile 对照

| Profile | Presence publication 到灯组 | Ambient Light publication 到灯组 | 同类 TTL 风险 |
| --- | --- | --- | --- |
| Occupancy sensing | 有 Presence Model 时配置 | 不启用，清理已有 Ambient 发布 | 有 |
| Vacancy sensing | 有 Presence Model 时配置 | 不启用，清理已有 Ambient 发布 | 有；表现应按手动开、自动关语义评估 |
| Occupancy sensing with daylight harvesting | 配置 | 为选定光照传感器配置 | 两条都有 |
| Vacancy sensing with daylight harvesting | 配置 | 为选定光照传感器配置 | 两条都有 |
| Daylight harvesting | 不建立 Presence 到本灯组的发布 | 为选定光照传感器配置 | 光照发布有 |
| Manual control | 不建立，清理指向本组的 Presence 发布 | 不建立，清理已有 Ambient 发布 | 无该主动配置路径 |
| Proximity Lighting | 不建立，清理指向本组的 Presence 发布 | 不建立 | 使用私有邻居触发链，另行分析 |
| Proximity Lighting with Photocell | 不建立，清理指向本组的 Presence 发布 | 不建立标准 Daylight group publication | 同上 |

`Profile.ProfileType.occupancyType` 为 PIR Action Publication 保护等用途把 Proximity 两类也列为 true，但 `getNodeSyncProfiles` 用的是自己局部枚举的四种 occupancy 类型。不能依据同名属性就推断 Proximity 会向整个灯组发布标准 Presence。

光照传感器的选择与校准有效性共同影响最终日光控制；publication 条件直接判断选定设备，光照控制启用另看校准状态，不能把代码中的“已校准”注释当成该 publication 分支的完整条件。

## 其他写入入口与旧数据漏检

| 入口 | 行为及影响 |
| --- | --- |
| `Node+MessageHandles` 的 `.sensorEnabled` | TTL=5，组规模重发策略；五种相关 profile 共用 |
| `LightSensorCalibrationViewController.commitCalibrationSensorSelection` / `sensorEnabled` | TTL=5，组规模重发策略；地址相同就不重写，TTL 错误可被跳过 |
| `GroupViewController.viewDidAppear` | 选定 Ambient 的地址不匹配时，写 TTL=5、period=0、retransmit disabled；这是仍生效的入口 |
| `GroupViewController.sensorPublishCheck` | 函数体也写 TTL=5、retransmit disabled，但当前找到的调用已注释；不能算作正在执行的故障路径 |
| Calibration rollback | 按原 `Publish` 快照恢复；保留原字段符合回滚语义，不能无条件改写 |

`isSensorServerPublicationConfigured` 的 strict 模式只检查 Sensor Server 类型、地址和 retransmit；legacy 模式进一步允许 `.disabled` 的旧重发配置。Need Sync 使用 legacy 模式，任务成功检查使用 strict 模式，两者均不检查 TTL、AppKey、Friendship flag、Period。`forceFullProfileSync` 也没有绕过 publication 这段判断。

因此可能出现：设备缓存 TTL=5，地址/重发正确 → 不显示 Need Sync → SAVE/完整 Profile 同步仍不生成 publication 任务。即便重发不正确导致重写，当前消息构造仍写回 5。

SDK 收到成功的标准 `ConfigModelPublicationSet` / `Get` Status 会更新 `model.publish`，不存在这里必然丢掉 TTL 的解码问题；缺口在 App 的目标比较。当前缓存仍不能取代现场新鲜读回。

相邻范围：EFC Scene publication 和 Kinetic Proxy publication 当前已使用 `0xFF`，不能说所有 publication 都有这个问题。SDK 通用 `publishNode`、部分入网/状态上报入口仍使用 SDK TTL，但它们并非本次 Group Profile 感应链，后续若扩大整改，应按用途分别审查。

Proximity 私有配置另有 TTL：通用 Node 同步和 Space 同步保留 `ttl: 0`；`GroupServer.getNodeAddMessageHandles` 的私有邻居配置仍传 SDK TTL=5。该字段属于私有 `0x41/0x02`，与标准 Model Publication 不是同一状态。本地协议表只列出 TTL 字段，未定义其 `0xFF` 特殊语义；不能凭标准 publication 规则直接改动。现有 `check_device_default_ttl_payloads.sh` 文本期望 Group Add 为 `0xFF`，与当前源码不符；本次未运行该脚本，也未将这一旁支认定为现场 Occupancy 问题的原因。

## 最短现场验证

1. 选择一台能稳定触发、但远端不亮的源设备，记录源楼层与近/远观察点。读取其真正 Presence Sensor Server element 的 `ConfigModelPublicationGet`，并读取源节点 `ConfigDefaultTtlGet`。记录地址、AppKey Index、TTL、Period、Count/Interval 和固件版本；不记录密钥内容。
2. 若 Publish TTL=5 且 Default TTL≥15，先保留其他 publication 字段，仅把该源的 Publish TTL 改为 `0xFF`，读取 Status/Get 确認成功。此步骤为建议现场操作，本次未执行。
3. 恢复 AUTO，固定源设备和观察点重复触发，比较改动前后近端与远端响应。若范围明显扩大，能确认原 publication TTL 对现场故障有直接贡献；若可恢复为 5 并重现，则证据更强。
4. 若没有改善，核对实际出站 Sensor Status 的初始 TTL、源的 Action Publication 开关、远端是否收到对应状态、接收相关模型组绑定/订阅及 LC Occupancy/Manual Override 状态，再排查中继连续性和密集触发拥塞。

固定跳数不足通常产生相对稳定的空间边界；拥塞可能造成更随机的遗漏，但两者可以并存。现有大组重发 1 次不扩大跳数；不建议同时加 TTL、重发次数和间隔，否则难以确定因果，也可能增加网络负荷。

## 建议修复边界（尚未实施）

1. 将五类 profile 共用的 Sensor publication TTL 目标改为 `0xFF`，同步覆盖光照校准提交/启用和组页面的生效补写入口。
2. 在任务生成、Need Sync 和任务成功判定的共享比较点加入 TTL 目标检查，使旧 TTL=5 可被重新下发；legacy 兼容可以保留已有重发策略，但不能继续忽略错误 TTL。AppKey、flag、period 的完整一致性也应纳入 review，避免破坏有意的旧格式兼容。
3. 保持当前组地址、Key、period 和按组规模重发策略，先单独解决 TTL 继承；不修改全局 App 发送 TTL，不顺带改私有 Proximity TTL 或其他 SDK 发布入口。
4. 用行为测试覆盖旧 TTL=5 触发修复、正确 `0xFF` 不重复配置、设备 Default TTL 变化时仍继承、启用光照旁路，以及 legacy 重发兼容。代码完成后再做代表品牌 generic iOS 构建；跨楼层效果仍由现场对照验收。

## 关键源码索引

- App：[Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)：`sensorServerPublicationRetransmit`、`isSensorServerPublicationConfigured`、`getNodeSyncProfiles`、Need Sync。
- App：[Node+MessageHandles.swift](../SunSmart/Common/Data/Node+MessageHandles.swift)：`.sensorEnabled` 标准配置负载及私有 Proximity 配置。
- App：[SyncDevicesCellModel.swift](../SunSmart/Main/Space/Model/SyncDevicesCellModel.swift)：任务发送和 `ProfileType.isSuccessful`。
- App：[LightSensorCalibrationViewController.swift](../SunSmart/Main/Group/Controller/LightSensorCalibrationViewController.swift)、[GroupViewController.swift](../SunSmart/Main/Group/Controller/GroupViewController.swift)：校准与页面补写入口。
- App：[InformationTTLMeshService.swift](../SunSmart/Main/Device/InformationTTLMeshService.swift)、[LabSettings.swift](../SunSmart/Common/Data/LabSettings.swift)、[LightGroupControlCommandSender.swift](../SunSmart/Common/Data/LightGroupControlCommandSender.swift)：设备 Default TTL 与 App 发送路径。
- SDK：`Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift` 的 `initConfig`；`nRFMeshProvision/Mesh Model/Publish.swift`；`Mesh Messages/Foundation/Configuration/ConfigModelPublicationSet.swift`；`Layers/OutgoingAccessMessageTtlPolicy.swift`；`Layers/Foundation Layer/ConfigurationClientHandler.swift`。

验证边界：完成当前源码、SDK 编码、正式依赖 revision 和 SIG 定义的交叉核对；仅新增本文档，未运行构建、未执行设备读写、未取得现场抓包，尚未确认 40 层实际覆盖结果。

## 开发方案（2026-09-20，待用户确认实施）

用户已确认上述修复边界，并要求先规划开发方案再确认。当前阶段仅更新本文档，生产代码与 SDK 尚未修改。复核 App HEAD、SDK HEAD 均与分析基线相同，唯一未提交文件为本文档。

### 目标与实现约束

- 五类相关 Group Profile 的 Presence/Ambient Sensor publication，凡本次配置写入都使用 `0xFF`，继承源设备 Default TTL。
- 本地缓存中旧 TTL（不仅是 5，任何非 `0xFF` 值）可触发既有 Need Sync / SAVE 同步；成功后不因 TTL 重复同步。
- 仅在现有传感器 publication 范围内修改。Manual/两类 Proximity 的启用、禁用规则不变；私有 Proximity TTL、EFC、Kinetic、SDK 通用发布与 App/Lab 发送 TTL 不纳入本次修改。
- SDK 已支持 `0xFF` 的编码、解析与缓存，无需新增 API、修改 one-dev 或调整依赖 revision。
- 本次不改变设备 Default TTL 数值，不新增全网后台扫描或升级后批量写设备；迁移沿现有组同步及明确的光照校准操作完成。

### 开发步骤与文件范围

| 步骤 | 修改位置 | 预期行为 |
| --- | --- | --- |
| 1. 统一 TTL 目标 | `Node+SyncData.swift` 附近现有 Sensor publication 辅助逻辑 | 定义局部共享目标 `0xFF`，复用既有文件，避免散落字面值或引入通用框架 |
| 2. 修复比较与消息构造 | `Node+SyncData.swift`、`Node+MessageHandles.swift` | 在已有模型类型/地址比较上加入 TTL 比较；`.sensorEnabled` 写统一 TTL；strict 与 legacy 的重发规则保持原样 |
| 3. 核对任务终态 | `SyncDevicesCellModel.swift`、`EmerFireAlarmSyncCellModel.swift` 及 Fast Add 调用方 | 复用共享比较，使缓存仍返回旧 TTL 时不能仅凭 Status Success 判定任务完成；调用方若已复用该方法则不重复修改 |
| 4. 覆盖光照配置入口 | `LightSensorCalibrationViewController.swift` | 提交选择/明确启用时将原地址匹配判断补充 TTL；同地址旧 TTL 仍会下发。新写入 TTL=`0xFF`，其他参数沿各入口既有策略 |
| 5. 覆盖页面补写 | `GroupViewController.swift` | 生效的 `viewDidAppear` 补写使用统一 TTL；保留当前“publication 地址缺失/不匹配才自动补写”的触发条件。已有同地址旧 TTL 由 Need Sync/SAVE 修复 |
| 6. 回归与交付 | `Tests/Group/`、必要的相关 `scripts/check_*`、本文档 | 增加与风险相关的行为用例，完成代表 scheme 构建，记录结果和人工验收步骤 |

`sensorPublishCheck` 当前未被调用：只同步其现存有效代码中的 TTL 构造值，防止将来调用时重新写入 5；不恢复该函数的调用，不处理其中无关历史注释。

### 参数兼容与回滚决定

1. **普通 Profile 同步**保持 ≤3 个成员额外重发 2 次、>3 个成员额外重发 1 次、间隔 100 ms。strict 仍要求匹配目标重发配置。
2. **Need Sync 的 legacy 模式**继续接受旧 `.disabled` 重发，但 TTL 必须为 `0xFF`。例如旧 TTL=5、重发 disabled 仍需同步；同步后会按当前 Profile 的既有目标写入重发配置，这沿用原来的 strict 同步行为。
3. **光照校准入口**保留原先的地址判断语义并补 TTL，不顺带增加重发不匹配就重写的条件；实际写入继续使用现有组规模重发策略。成功分支增加目标地址/TTL 的缓存终值核对，防止收到成功状态但仍保持旧 TTL 时继续推进。失败沿现有错误/回滚路径处理。
4. **组页面补写**仍保留该入口原来的 `.disabled` 重发配置；本次不将页面补写改为按组规模重发，不扩大打开页面时自动下发范围。
5. **校准事务失败**仍恢复完整原 publication 快照，含原 TTL、地址、Key、period、retransmit；原快照若为 TTL=5，也必须如实恢复，之后仍由同步判定标记待修复。不得以“修复 TTL”为由破坏回滚原状态的含义。
6. **AppKey、Friendship flag、period**检查其读写和既有约束，但本轮不新增这三个字段的严格迁移/拦截规则，避免把 TTL 修复扩大成全字段配置迁移。写入时仍使用各入口原来的当前 AppKey、flag=0、既有 period。

### 旧设备修复与失败处理

1. 更新 App 后，组同步状态按本地 `model.publish` 判断；旧 TTL 会使对应传感器需要同步。
2. 用户通过现有 SAVE/Sync 流程下发 `0xFF`；新加入成员、Profile 切换继续使用相同共享逻辑。
3. 只有回包更新后的 publication 地址、TTL 和该同步任务要求的重发配置满足目标，才确认对应任务成功。设备离线、超时、返回失败或 TTL 仍旧时，沿现有失败/重试机制保留未完成状态。
4. 不为本次修复新增全量 Publication Get。若本地缓存与设备实际配置不同，现场验收使用新鲜 Get 读回确认；无法以本地缓存断言全网已迁移。
5. TTL=0xFF 后，修改源设备 Default TTL 无需再次修改 publication；App 只验证保留继承标记，实际固件是否使用新的 Default TTL 由现场测试证明。

### 最小有效验证

新增/扩展行为测试直接执行生产策略或提取的生产方法；不以源码字符串匹配作为 TTL 行为正确的主要证据，也不创建临时 Xcode 工程。

| 用例 | 验收点 |
| --- | --- |
| 原配置地址/重发均正确、TTL=5 或其他具体值 | strict/legacy 均识别待同步；能产生 publication 修复任务 |
| TTL=0xFF、地址/重发均正确 | 不因 TTL 重复下发 |
| TTL=0xFF、旧重发 disabled | legacy 兼容继续成立；strict 保持既有目标要求 |
| 无 publication / 错组地址 | 继续建立正确发布，TTL=0xFF |
| 3 与 4 个有效成员边界 | 重发分别为 2/1 次，间隔均 100 ms |
| Presence 与 Ambient 配置负载 | TTL 字段为 0xFF，原地址、Key、flag、period 与各入口重发策略不变 |
| 同地址旧 TTL 的光照校准 | 不再提前返回已启用；成功后保存目标状态 |
| 写入失败、成功 Status 但旧 TTL 终值、失败后重试 | 不误报目标完成；保留失败并允许重试 |
| 校准切换失败与回滚 | 完整恢复旧 publication；不破坏传感器选择/校准提交顺序 |
| 组页面已有同地址旧 TTL | 页面进入不新增自动写入；Need Sync/SAVE 可以修复 |
| 设备 Default TTL=15/更大，或改变 App SDK/Lab TTL | 配置负载仍为 0xFF，不复制这些数值；此用例不声称验证固件实际出站 TTL |
| Manual / 两类 Proximity | 保持原传感器发布启用/禁用范围 |

优先扩展 `Tests/Group/CalibrationModeControlBehaviorTests.py` 的记录式消息夹具，使其保留 TTL 和失败终值，并补校准事务覆盖；为共享 publication 策略补小型行为用例及运行入口。复用与改动直接相关的 `check_fast_add_dual_scene_verification.sh`、`check_night_calibration_workflow.sh`、`check_sensor_calibration_workflow.sh`，这些现有源码契约检查仅作为接线回归补充。

完成一轮实现与相关回归后，使用已映射的 `SunSmartLocal.xcworkspace`，执行一次 SunSmart Debug generic iOS 构建，参数为 `-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`；DerivedData 使用工作树固定目录 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-gateway-cli`。本次为共享 Swift 逻辑，无品牌分支、资源或 SDK 公共 API 改动，默认以 SunSmart 代表验证；实施中若发现实际跨品牌编译差异再调整范围。

现场人工验收沿上文“最短现场验证”，重点读回旧组源设备 TTL=0xFF，并固定源点观察近/远端。自动化与构建通过不代表 1–40 楼覆盖已通过。现有 `check_device_default_ttl_payloads.sh` 的私有 Proximity 分支期望与源码不符属于已知范围外基线差异，不为让该脚本通过而修改私有协议代码。

### 完成条件

- 生产改动、相关行为回归和代表 scheme 构建完成，保留其他任务差异。
- 在本文档更新实际修改、测试/构建结果及仍待现场确认项。
- 不自动提交、推送、安装或运行真机。
- **当前停在方案确认：用户确认本节方案后才开始实施。**

## 实施记录（2026-09-20）

用户已确认实施上述方案。本节取代前述“待确认/尚未实施”的阶段状态，前文保留为分析和方案记录。

### 已完成改动

- 在 `Node+SyncData.swift` 增加局部 `SensorPublicationPolicy.ttl = 0xFF` 和 Sensor Model 的地址/TTL 目标检查。原 strict/legacy 完整检查复用此目标检查，继续沿用原重发兼容规则。
- `.sensorEnabled`、光照校准提交/启用、组页面补写和未启用的 `sensorPublishCheck` 函数体统一使用该 TTL。页面补写仍仅由地址不匹配触发，其 `.disabled` 重发策略不变。
- 同地址旧 TTL 不再使光照校准提前判为已启用。校准写入的完成判断额外检查缓存中的地址/TTL；若返回成功但 TTL 未生效，进入既有失败或事务回滚分支。
- `SyncDevicesCellModel`、`EmerFireAlarmSyncCellModel`、Fast Add 已复用共享检查，自动获得旧 TTL 检测，无需重复修改调用方。
- 组地址、Key、flag、period、重发次数/间隔、校准原快照回滚和其他 Profile 启用/禁用条件保持原有行为。
- 生产代码仅修改 4 个 App Swift 文件。SDK、依赖、资源、本地化、Proximity 私有 TTL 和 App/Lab 发送 TTL 均未修改；没有引入新 SDK API 或发布待办。

### 验证结果

| 验证 | 结果与边界 |
| --- | --- |
| `python3 Tests/Group/SensorPublicationBehaviorTests.py` | 385 项行为/负载断言通过。执行提取的生产比较、相关任务生成分支、消息构造、任务终值检查、页面补写以及当前 SDK 重发/负载编码代码，使用模型值夹具；不是完整 App 或固件运行 |
| `python3 Tests/Group/CalibrationModeControlBehaviorTests.py` | 575 项断言通过。涵盖原校准流程及新增同地址旧 TTL 修复、成功状态但 TTL 未应用、重试、校准提交及完整快照回滚；回调为同步夹具，不覆盖真实 BLE/异步时序 |
| `zsh scripts/check_night_calibration_workflow.sh` | 通过；既有校准接线契约检查 |
| `zsh scripts/check_sensor_calibration_workflow.sh` | 通过；既有校准接线契约检查 |
| `bash scripts/check_fast_add_dual_scene_verification.sh` | **整体未通过**。前置 checkpoint/Timed Scheduler 检查及本次 publication 相关检查通过，之后在空 Path 源码契约失败；详见下文 |
| SunSmart Debug generic iOS | **BUILD SUCCEEDED**，退出码 0；使用本地 workspace、固定 DerivedData、`CODE_SIGNING_ALLOWED=NO`，未使用 Simulator |
| `git diff --check` | 通过 |

行为回归覆盖 TTL=0/5/15/127/255、strict 与 legacy、3/4 个成员边界及大组、全部 8 种 Profile 的发布范围、旧配置任务生成/应用后不重复生成、正确 element/key/TTL/period/retransmit 字节、空配置/错误地址、App 与源设备 TTL 改变仍写入继承标记，以及页面不会因同地址旧 TTL 自动写入。

新增负载夹具提取部分 Profile 逻辑，尚未消费后续使用的 `daylightEnabled`，因此该隔离编译有一条“变量已写但未读”的夹具警告；不涉及生产修改。新增测试位于 `Tests/Group/`，未建立临时 Xcode 工程或修改工程配置。

构建使用 `SunSmartLocal.xcworkspace` / `SunSmart` / `Debug` / `iphoneos` / `generic/platform=iOS`，DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-gateway-cli`。输出确认解析到 `.local-sdk/nordic-sig-mesh-sdk`；SDK 仍为 `a971027e08f9775d7a3f071a06f89be1c38ecc96` 且工作区干净。构建后生产代码未再修改，无品牌条件或资源变更，未重复构建其他品牌。

### 既有检查失败的确认

Fast Add 综合脚本失败信息：`FAIL: empty Path must continue to produce an empty path iteration`。脚本要求在 `Node+SyncData.swift` 中存在特定 `for path in proximityLightingPath?.paths ?? []` 源码文本，当前文件不包含该写法。

将 `git show HEAD:SunSmart/Common/Data/Node+SyncData.swift` 导出到临时文件，仅把脚本的 `node_sync` 输入切换为该修改前版本，重复运行同一脚本，得到相同失败和退出码 1。其他被该脚本读取的 App 文件及脚本本身均未被本次修改。因此本次新增修改不是该断言失败的来源。此结果只确认基线源码契约不符，不据此判断 Path 运行行为有错，也没有改动 Path 业务或放宽测试。

### 交付与现场验收

代码和自动化验证已完成；保留上述综合脚本的既有失败记录。未提交或推送，未安装或运行真机。

升级后对原 Occupancy 大组执行 SAVE/Sync。读取实际触发源的正确 Sensor Server element publication，确认 TTL=`0xFF` 且源 Default TTL 为现场所需值；恢复 AUTO 后在同一源点重复感应，比较近端和远端。设备离线/配置失败应保留待同步，重试后再读回。

本次未引入全量 Publication Get，Need Sync 依据缓存；如设备与缓存可能不一致，以现场新鲜读回为准。1–40 楼的真实覆盖、固件对 Default TTL 的实际使用及密集触发稳定性仍待人工验收。
