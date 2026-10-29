# Space 场景数量开放：分析与推荐方案

日期：2026-10-29。状态：已按确认方案完成 App 与本地 SDK 实施、相关离线回归及五品牌 Debug generic iOS 构建。未提交 Git，未操作真机或线上服务。数据库表结构、场景 JSON 格式不变；旧安装升级、真实 Mesh 和线上往返仍待人工/联调验收。最终交付与边界见第 9 节。

## 1. 结论

建议取消 Space 的固定 16 条场景上限，保留每个场景现有的固定 Scene Number，改为在关联目标发生变化时，按设备检查不同场景的占用。某一目标设备无法容纳新增场景时，整次关系变更不保存，明确列出设备、原因与处理办法。

与 timed 相比，不需要建立“业务场景 ID → 每设备物理 slot”映射。需要复用 timed 的候选拓扑预检、提交前复检、事务保存及失败重试机制，并补齐场景实际占用读取和删除确认。不能仅移除两个页面的 count < 16。

已确认范围：开放场景数量，覆盖场景添加 Group、设备加入这些 Group、设备恢复及重试；本次不新增“直接选择单个设备加入场景”的 UI/数据模型。

## 2. 实施前核实的事实（历史基线）

### 2.1 ID 与设备容量

| 对象 | 协议含义 | 当前工程含义 |
| --- | --- | --- |
| 定时索引 | Schedule Register 的物理索引为 0～15，共 16 条 | 当前分支已把 Schedule.id 与每设备 slot 分离；业务定时可以超过 16 条 |
| 场景编号 | Scene Number 为 0x0001～0xFFFF；0 禁用 | 保留 UInt16 number；创建后编辑、同步和 Recall 均使用同一 number |
| 场景容量 | 每个 Scene Register 为 16 项；保存已有编号更新原项 | “每台设备最多 16 个普通业务场景”作为本次产品上限，同时不能超过实际目标 Register 的可用容量 |
| 普通编号分配 | 协议编号范围不等于项目可分配范围 | SDK 把 0xFF00 及以上视为特殊场景，普通场景应限定在 0x0001～0xFEFF 内的已授权分配范围 |

规范依据：[Bluetooth SIG Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)，5.1.3.1、5.1.4.2、5.2.3.4。规范限制以 Server/Register 实例为单位，不是以 Space 为单位，也不能据此推定全部多 Element 设备只有一个 Register。

当前普通场景下发使用 node.sceneSetupModel；LC 场景有独立的 lightLCSceneSetupModel 选择。是否共用实际 Register 应按目标 Element 判断，不能简单将所有 LC 特殊场景加到普通场景数量，也不能因其为特殊编号就忽略同一 Register 中的真实占用。EFC 的 FF20/FF21/FF22 在当前 App 用作事件通知，代码明确不再写入灯端 Scene Store，不应凭编号自动扣除三个容量。

### 2.2 现有限制和复用点

- ScenesViewController 限制新增数量并显示 count/16；SpaceNewCreationProcessController 连续创建引导也限制 16 条。
- getNextSceneName 仅查找 Scene1～Scene16，全部占用后返回 Scene1，开放数量时必须一起修正。
- SceneAddViewController 模板创建直接写 GroupInfo.sceneExecuteDatas；SceneSettingsViewController 的 DONE/SAVE 已接入 TimedSchedulerBindings 的拓扑预检与保存事务。必须同时覆盖这两个入口。
- SceneInfo.groups 从 GroupInfo 的执行数据反查。当前未发现直接选择单个设备加入场景的业务入口；Scene.addresses 主要由设备回执维护，不能当作用户期望的直接成员配置。
- TimedSchedulerBindings.prepareTopology 支持拟提交的组成员/场景组集合，排除非明确重新加入的 exitFailure 成员；commit 将 Timed 预留与调用者变更放入同一 SQLite savepoint。关系对象内存仍需调用者恢复。
- Scene 增加 Group 也可能使设备新增该场景关联的多条定时，必须同时检查 Scene 容量与 Scheduler 容量。新增依赖保持先 Scene 后 Schedule，移除保持先 Schedule 后 Scene。

### 2.3 现在是否回收场景 ID

会。创建使用 SDK 的 customNextAvailableScene，从当前 Provisioner 已分配范围中查找 SQLite 中未使用的编号；查重范围为 Mesh/Site，而非只看当前 Space。场景正式删除后，SQLite Scene 记录被移除，之后自动分配可以再次选择该编号。这是本地编号复用，不等于每删一条就向服务器归还地址。

当前删除按 scene.info.groups 执行；失败组保留 waitDelete，以便重试。但这不构成全部物理残留、历史孤立设备、关联定时和开关已清理的证明。不能把“记录已删除，所以编号可用”直接当作安全回收条件。

另已从调用顺序确认：SceneServer 先 network.remove(scene:)，SDK 会断开 Scene 的 network 引用，之后 scene.deleteExtension() 开头依赖该引用的 guard 可能直接返回。实施中应先固定所需网络身份并在事务中完成扩展清理，不能维持当前顺序再声称删除闭环完整。

另有必要联动：Site 部分解绑路径用 16 - usedSceneAddresses.count 计算场景地址归还数量，再传给 suffix。开放后该值可能为负，存在运行时失败风险。必须移除该固定配额假设；最小安全策略为仍有可编辑 Space 时保留现有未用场景地址池，不按 Space 数量推算归还；全部退出/删除时继续按实际授权且可释放的地址集合处理。若以后需要主动缩减地址池，另按实际分配记录实现。

### 2.4 不能只数 sceneExecuteDatas

- Group 执行数据表示期望配置；设备 sceneExecuteDatas 表示本地执行缓存；两者都不天然等于当前设备完整 Register。
- 当前没有统一的“未知 / 已知空 / 已知非空”场景 Register 状态。旧数据缺字段不能当作设备没有场景。
- SDK SceneClientHandler 收到 SceneRegisterStatus 会自动创建未知普通 Scene，并更新 Scene.addresses。直接增加 RegisterGet 查询可能把设备残留或其他 Space 的编号变成当前 Space 的业务场景。
- SDK 部分 SceneStore/Delete 回执处理没有先验证 status 就更新执行缓存；MeshProxyMessageCommand 的相关通路也不能仅凭收到同类响应证明操作成功。这里是源码证据，尚无本轮固件运行复现。

因此推荐包含小范围客户端 SDK 修正：读取 Register 不生成业务 Scene；Store/Delete 按状态与返回列表核验成功，再更新执行缓存。范围仅限场景链路，不泛化重写所有协议处理。

## 3. 方案比较

| 方向 | 代价与结果 | 建议 |
| --- | --- | --- |
| 页面解限，关联时只数 Group/设备本地缓存 | 改动少，但漏掉加组成员、残留占用、未知状态及失败回执，无法保证不超额 | 不采用 |
| 固定 Scene ID + 统一目标/容量校验 + 可靠删除确认 | 保留现有协议身份，补齐关联入口和真实失败边界；需要少量 App/客户端 SDK 协作 | 用户已确认 |
| 仿 timed 给同一场景分配不同设备编号 | 增加映射、持久化、定时/开关 Recall 转换，破坏统一编号组播优势 | 与用户目标不符，不采用 |

用户已确认此方向及范围；实施授权保留，不再次询问是否采用原方案。实施前先明确以下存储和兼容边界，随后细化实施计划。

### 3.1 实施前存储与兼容性说明

已核实：SDK 的 scenes 表保存 number/name/addresses 及网络归属，App 的 sceneInfos 表保存 number/imageId 等扩展信息，唯一身份均沿用 meshUUID + number；这些表均没有 16 行容量限制。云端 scenes 数组保留 number/name/imageId，组关联及执行参数在 groups[].scenesDatas 中，现有 waitDelete 已进入 Codable、SQLite 和云导出。因此解除数量限制本身不要求重建场景表、重新编号、添加每设备 slot 映射或批量重写旧场景。

存储实施边界如下：

| 数据 | 实施约束 |
| --- | --- |
| 原场景编号、名称、图标、网络归属 | 保留原字段和含义，旧记录不重新编号、不重建项目 |
| 组关联、亮度/色温等执行参数 | 保留已有结构和取值，不因升级自动重新下发或删除 |
| 既有 waitDelete | 复用并正确恢复，不因升级当作 normal 或已完成 |
| Register 容量观测 | 新增运行状态；旧数据没有观测时是 unknown，不是空 Register。只有有效设备读回才能建立可信状态。是否落本地可选缓存，在实施计划中按恢复需要收敛；云下载的旧观测不能直接视为当前设备事实 |
| 现有格式无法表达的清理意图 | 只补必要的可选字段/记录，使用兼容默认值；必须完整接通 SQLite、导入导出、恢复及版本保护后才能启用，不承诺整个方案完全零字段变更 |

兼容性目标是“新版读取旧场景项目”：保留旧安装数据库升级、旧云项目、旧分享/备份导入以及合法空场景；不要求用户重新创建 Group/Scene。读取新增关联所需的设备容量可能要求连接设备，但不会因尚未读取就清空原场景。旧项目原有的数据完整性/权限保护继续生效，不因兼容而放行损坏数据。

这不等于“旧版 App 可以安全编辑新版项目”。旧版没有新的容量、失败回执和编号回收保护；如果新增持久字段，旧版还可能在写回时丢失这些字段。发布前必须核验其他客户端和线上字段往返，必要时复用既有版本/能力保护。当前不能宣称双向兼容或线上配套已完成。

以上是已核实的存储现状与实施约束，尚不是迁移测试通过的结论。验收需固定旧数据样本，检查升级/导入前后编号、参数和关系一致，覆盖 waitDelete、缺少新字段、数据库重开、32 条场景往返和失败回滚。

## 4. 推荐行为规则

### 4.1 Space 与 Scene ID

1. Space 不再设置固定 16 条上限；数量显示实际总数，默认名称继续生成 Scene17、Scene18 等，不重命名已有场景。
2. 保留所有已有合法 Scene Number，不重排、不因增减成员重新编号。同一场景向所有目标发送同一编号。
3. 仅从本 Provisioner 已授权且 Site 范围未占用的普通编号中分配，排除待删除/保留记录以及特殊范围。
4. 地址池耗尽时复用现有 applyAddress(siteId, type: .scene, number:) 接口，建议按现有 16 个的批量补充策略申请。申请数是预分配批次，不是 Space 上限。先验证返回范围合法、无冲突并持久化授权，再创建；请求失败保留输入，不生成半条场景。离线只有已有授权空闲编号时才能继续。
5. 可复用编号量仍受整个 Site 的地址池与授权范围约束；产品表述为“取消 Space 固定 16 条限制”，不承诺无限数量或无限规模性能。

### 4.2 容量计算

以设备配网身份为对象，以固定 Scene Number 去重，不按 Group 数、重复关联次数或设备 Element 数重复计数。候选场景集合包括变更后仍需保存的场景，以及尚未确认删除的占用；设备真实 Register 的残留编号参与物理容量判断。

必须同时满足：

- 每台设备本次拟保留的普通业务场景最多 16 个。
- 每个实际发送目标 Register 中，已存在项与尚需新增项取并集后不超过其容量。位于其他独立 Register 的 LC 场景不混算；同一 Register 中的保留或未知来源编号不凭空忽略。
- 关联的 Timed 拓扑预检通过。

已在设备上存在同一个 Scene ID 时更新参数不增加占用。当前已满 16 条或历史数据超额时，允许改名、修改原有场景参数、移除成员、删除及清理重试；禁止进一步增加占用。历史超额不得静默截断成前 16 条。

空场景、空 Group 不占设备容量，可创建超过 16 条；之后设备加入时按该 Group 的全部场景检查。无 Scene Server 能力的设备不算可存储场景的目标；能力尚未知则先读取 Composition，不能当作不支持而绕过校验。

### 4.3 提交与失败

1. 选择 Group 时用当前期望配置尽早提示；最终 DONE/SAVE 用完整拟提交集合检查。
2. 实际容量未知或缓存已失效时，读取目标 Scene Register。查询只更新设备观测，不能创建、删除或重命名业务场景。读取失败保留输入并提示连接后重试，不把未知当成空闲。
3. 异步读取回来核对当前 Site/Space、节点身份、页面操作代次，并重新计算候选集合，防止取消、切 Space、设备重配后的迟到回调提交。
4. 保存前再次检查 Scene + Timed；在同一事务内保存关系、待清理意图及 Timed 预留。失败恢复数据库和内存，不预先留下部分 Group 绑定。相同设备的配置操作串行或复用已有执行中保护。
5. 容量预检失败：整次用户关系变更拒绝，不跳过满容量设备后保存其余目标。传输已经开始后的设备离线或部分失败：保留已保存意图和已成功设备结果，显示待同步，继续原有重试，不宣称设备动作可原子回滚。
6. 配网在获取完整能力前可能已经成功；此时容量不允许入组，应保留已入网设备，阻止后续组配置并明确失败原因，不自动反配网。

### 4.4 删除、回收与历史数据

- 从设备移除某个 Scene ID：需要删除时保留待清理占用，收到匹配身份/Element/当前操作的有效返回，且 Register 确认该 ID 不再存在，才释放。超时、取消、重启和迟到回执不能提前释放。
- 整体删除场景：先处理场景关联定时、开关配置及仍可能 Recall 旧编号的引用，再清设备场景；清理完成后删除业务记录并允许编号复用。建议最小安全行为为：存在有效定时/开关引用时拒绝删除并列出引用，用户先修改或移除引用并完成设备同步，再重试删除；不自动删除用户的定时和开关业务记录。已有待删除引用未同步完成时，同样保留编号，不允许复用。
- 未下发过的合法空场景，在确认无控制引用和设备残留后可直接删除。不能仅凭缺少设备执行缓存判断“从未下发”。
- 设备复位成功可以清除该旧配网身份对应的占用；Force Delete 不能证明物理复位，未知设备残留不得被当作可安全清理。
- 优先复用现有 Scene/Group waitDelete、设备恢复与配置持久化机制。若现有格式不能保存整体删除和孤立残留的清理意图，再增加最小字段及版本保护；不预建类似 Timed 的 slot 映射框架。
- 导入旧 0/1/16 条以及合法空配置继续兼容；缺少 Register 观测表示 unknown。新格式/新增待删除字段必须通过本地重启、Space/Site 导入导出、分享及云回读完整保留。损坏、重复或跨 Space 冲突的编号明确拒绝，保留原配置。
- 其他客户端可绕过新版容量校验；不能把当前旧格式可解码当作旧版可安全编辑的证明。新旧端混编的发布策略需结合是否新增持久字段确认，优先复用项目已有能力/版本保护，不另造一套兼容体系。

### 4.5 用户提示

容量不足的提示至少包含 Group 名、阻塞设备名及简短地址（重名时可区分）、已占用/待清理数量。完整名单可展开，不能只显示无法操作。

建议英文文案语义（实施时复用可用 Key，补齐英文和简体中文）：

> Cannot add this group. Lamp A (1201) already uses 16 scenes. Remove this device from an existing scene and sync the removal, or choose another group.

有待清理占用时单独提示先完成删除同步；存在未知设备记录时提示连接设备读取/同步，不能一律说“已关联 16 个场景”。提供可查看关联场景和待清理项的操作路径，避免建议用户只从 Space 删一个无关场景。

## 5. 最小完整实施边界

| 范围 | 必须覆盖 |
| --- | --- |
| 列表与创建 | ScenesViewController、SceneAddViewController 的模板/自定义、连续创建引导、默认名称、编号池不足处理 |
| 场景编辑 | SceneSettingsViewController DONE/SAVE/重复 SAVE；整次候选目标检查，保留输入 |
| 组与设备 | GroupMembersViewController 全批预检/提交复检、GroupServer 公共加组、Classic/Professional/Fast Add 延后规划、设备恢复 |
| 同步与读状态 | SyncSceneScheduleTaskBuilder、SyncDeviceTaskBuilder、Node+SyncData、发送前防线、Scene-only 设备以及 Scene → Timed 依赖 |
| 删除与编号 | SceneServer、Scene.deleteExtension、Group waitDelete、定时/开关引用、Site 解绑地址回收，重试与编号保留 |
| SDK | 场景 Register 只读观测、状态与返回列表验证、避免未知编号自动生成业务场景、避免失败 Store/Delete 改写成功缓存 |
| 数据与兼容 | SQLite、导入导出/恢复、版本保护；新字段仅在现有持久机制不足时引入并同步全链路 |
| 品牌 | SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 共享行为；新文件与双语资源检查归属 |

若用户要求本次同时新增直接设备场景，需要扩展：直接成员的期望配置与执行参数、与 Group 重复命中时的参数优先级、移出 Group 后直接成员保留、直接成员恢复/删除、Scene Recall 目标、Timed 的场景目标展开、列表/同步状态及云字段。此部分是实质新增需求，不靠增加一处设备选择器解决。

建议确认方向后按三个实施块推进：①编号池/容量规则与设备观测；②全部关系入口、同步及删除闭环；③UI/国际化与兼容回归。各块共享同一写入负责人，不自动提交。

## 6. 验证与外部边界

最小行为验证集合：

| 用例 | 预期 |
| --- | --- |
| A、B 两组各一台设备，各关联 16 个不同场景 | Space 可有 32 条，设备各 16，编号保持 Site 唯一 |
| 设备从 15 到 16，再尝试第 17 条 | 第 16 条允许，第 17 条整次拒绝，列出具体设备 |
| 一个选择批次含可加入与已满设备 | 不产生部分 Group/场景关系；原输入仍在 |
| 满容量设备编辑既有场景、重试原 ID、减少目标 | 可继续，不误判成新增 |
| 空组先关联 17 个场景，再加入设备 | 空组配置合法；加设备时拒绝；无 Scene 能力设备不误拦 |
| Scene 未满，但新增 Group 会使其关联 Timed 超额 | 同样整次拒绝，明确提示定时容量原因 |
| 删除部分成功、断网、取消、重启、迟到回执 | 未清占用与编号仍保留，成功清理后才能复用 |
| Store 返回 registerFull；Delete 响应但列表仍含 ID | 不写成功缓存、不宣称同步成功、不释放占用 |
| Register unknown、known empty、外来残留/特殊编号 | 分别处理，不因读取生成 New Scene 或跨 Space 绑定 |
| 新旧设备同地址、恢复/重配、exitFailure 后重新加入 | 按身份和明确操作检查，不复用旧设备清理回执 |
| Scene17、编号池耗尽、并发申请/返回冲突、部分解绑 >16 | 命名有效，编号分配失败不留半成品，回收计算不为负 |
| 定时与开关仍引用待删除 ID，随后尝试编号复用 | 先清理引用，不能让旧 Recall 激活新场景 |
| 旧配置、新配置、空配置的 SQLite 重开与云/文件往返 | 编号、关系、清理意图不丢失；损坏导入不覆盖原配置 |

优先扩展现有 Tests/Scene、Tests/Timed 与相关 scripts/check_* 的行为夹具，加入针对新策略/回执的必要测试；源码匹配只作为接线补充。实施完成运行相关回归并构建一次 SunSmart Debug generic iOS。由于预计涉及 SDK 公共行为、新 Swift 文件和双语资源，稳定后且合入前覆盖全部受影响品牌编译；不使用 Simulator，不自动操作真机。

真实 Mesh 验收由用户执行：两设备各 16 条、第 17 条拒绝、Group 部分设备已满、断连删除后重试、场景定时与开关 Recall、旧安装升级与多客户端读回。构建与离线夹具不能替代这些验收。

外部配套仅记录、不实施：

- 后端团队确认既有 scene 地址申请接口允许追加、按 Site/Provisioner 保证不重叠并排除特殊范围；Space 场景数组/计数超过 16 可完整往返。未核验线上实现。
- 如新增持久字段或旧客户端存在不保真写回，由后端/其他客户端团队配合能力门禁和完整回读；没有证据时不宣称无需配套。
- 固件团队提供涉及产品的 Composition/Register 样本，验证满容量返回、删除列表及普通/LC 实际存储边界。本方案不修改固件或推定所有型号都已满足。
- SDK 修改只在现有 one-dev；执行前重新核对共享写入状态，记录最终 revision/差异及正式 release 待发布依赖。实施结果及正式发布依赖见第 9 节。

## 7. 分析阶段证据与起始基线

App：feat/device-scene-261028，HEAD 55bb8079；开始时工作树干净。本地 SunSmartLocal.xcworkspace 存在，.local-sdk/nordic-sig-mesh-sdk 指向 one-dev；只读核对 SDK HEAD 9998967、工作树干净。本节记录分析时的状态；最终构建与回归结果见第 9 节。

- [之前的 timed 分析与实施记录](261008_1424_space_timed_per_device_limit_analysis_plan.md)：沿用容量、拓扑与恢复经验，当前事实已与本分支核对。
- [场景列表](../SunSmart/Main/Scene/Controller/ScenesViewController.swift)、[创建](../SunSmart/Main/Scene/Controller/SceneAddViewController.swift)、[设置](../SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift)、[删除](../SunSmart/Main/Scene/Model/SceneServer.swift)。
- [拓扑预检与事务](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift)、[组成员](../SunSmart/Main/Group/Controller/GroupMembersViewController.swift)、[配网延后同步](../SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift)。
- [场景/定时任务顺序](../SunSmart/Main/Space/Model/SyncSceneScheduleTaskBuilder.swift)、[成员与地址回收](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)、[云导出](../SunSmart/Common/Data/ExportData.swift)。
- SDK：Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Foundation Layer/SceneClientHandler.swift；MeshLib/Manager/MeshProxyMessageCommand.swift；MeshLib/Node/Node+SupportModels.swift；MeshLib/Group/Group+LightLCScenes.swift。具体失败需在实施时以回执夹具固定，不能把静态分析写成真机复现。

## 8. 已授权实施计划与进度

执行方式：主代理在当前隔离工作树统一实施，使用 superpowers:executing-plans；本节同时作为进度记录，不另建重复计划或自动提交。SDK one-dev 由本任务主代理单独写入，正式远端依赖保持不变。开始时另有用户文件 docs/261029_1425_proximity_lighting_video_prompt.md，保持不动。

Ruling：Register 观测采用 Element 实例上的可选运行缓存，不编码到 SQLite/云数据；重新加载或断线后为未知。继续保留原 Scene 记录与 Group waitDelete 表达未完成删除，不新增 Scene slot 映射或仅为观测升级云 schema。代价为首次变更需读取设备，收益是旧数据格式不迁移且不信任跨客户端旧观测。

### Task 1：设备 Register 与容量规则

- [x] 先增加行为夹具，覆盖 15→16、16→17、重复 ID、原项更新/减少、未知与已知空、真实残留与特殊编号、Store 满/列表缺项、Delete 未清。
- [x] 新增 App `Common/Data/SceneCapacityPolicy.swift`，接口 `validate(previous:desired:observed:)` 按 Set<UInt16> 验证只增加占用的变更；新增 SDK `MeshLib/Scene/SceneRegisterPolicy.swift` 验证原始状态和目标编号。
- [x] SDK Element 新增可选 observedSceneRegister；SceneClientHandler 对 Register 只更新已有业务对象并记录完整观测，Store/Delete 仅在有效确认后改变执行缓存；MeshProxyMessageCommand 对场景错误回执报告失败。
- [x] 验证命令 scripts/check_scene_capacity.sh；包含新策略行为与 SDK 回执策略。失败必须先观察，随后实现至通过。

### Task 2：共享关系预检、创建与地址池

- [x] 新增 App `Common/Data/SceneCapacity.swift`，共享 `validateTopology(group:members:addingMembers:scene:sceneGroups:)`、`readUnknownState(nodes:completion:)`；在 Timed 拓扑预检和组成员保存前组合调用，提交前再验证。
- [x] Scene 模板创建先预检再事务保存，Scene DONE/SAVE 共用容量读取；Group 公共添加、配网及恢复保留设备级发送防线。
- [x] 去掉 Space 场景数限制和 count/16；默认名不限制 16；复用 scene 地址申请，验证返回地址并持久化后重试创建，保护过期异步回调；修正解绑回收负数。
- [x] 新双语错误提示列出设备及解决办法；新 Swift 文件加入五品牌 Sources。运行容量及相关 Timed/Group 回归。

### Task 3：删除与同步闭环

- [x] 以真实 Register 检查场景 Store/Delete 结果；失败不能空任务成功；保留原场景编号到全部受影响设备确认清空。
- [x] 删除前拒绝仍有 Timed/开关引用的场景；清理覆盖场景地址与 Group 成员，先保存 waitDelete，取消/失败留待重试；捕获网络身份后事务删除扩展与 Scene 行。
- [x] 加入旧场景 Codable/空配置、删除部分失败、重试及迟到回调隔离行为验证；复用原 Timed SQLite 重开与回滚测试。场景完整旧安装升级、进程重启后的物理删除恢复仍待真机验收，不能由这些夹具替代。

### Task 4：集成验证与交付

- [x] 执行相关 check_* 回归、diff 检查、项目与资源归属检查；主代理完成所有实施后进行一次独立审查，修复重要问题并运行对应回归。
- [x] 本地 workspace / SunSmart / Debug / generic iOS 构建；SDK公共行为及新增资源稳定后覆盖其余四品牌，不自动安装真机。
- [x] 记录 SDK revision/差异、远端 release 待办、真实设备/线上云往返待验收；只报告实测结果，不将源码检查或隔离夹具称为完整验收。

Review Focus：批量容量不足不留下部分关系；设备已满仍可编辑已有 ID；未知缓存/历史 waitDelete 不清空旧项目；原编号复用不会被旧引用再次 Recall；异步读回/分配结果不能提交到已切换的 Space。


## 9. 最终实施与验证记录

### 9.1 存储与兼容结论

- SQLite 表、数据库版本与场景 JSON 格式均未调整；没有 Scene→设备 slot 新映射，不要求迁移、重编号或重建旧场景。继续使用 Scene 行、SceneInfo、Group sceneExecuteDatas 及其 waitDelete 保存原有业务配置/未完成清理。
- SDK Element 新增 observedSceneRegister 可选运行状态，未加入 Codable 或 SQLite。旧数据载入、App 重启、Mesh 完全断线后未知；新增占用前读取设备。已存储同一编号的参数更新及减少关系不会被全局满容量误拦。
- 新版旧数据读取的隔离证据包括旧场景缺省参数、waitDelete、空数组、32 条执行参数编码往返；未以此代替完整旧安装数据库升级、文件导入/分享或线上服务器实测。
- 旧版 App 不具备新容量及删除保护，仍不能承诺旧版可以安全编辑超过 16 条的新项目。各客户端及服务端发布策略须联调确认。

### 9.2 已落地行为

- Space 列表/创建取消固定 16 条限制；名称可继续递增，编号由 Site 共享授权池分配，普通编号范围保持 1…FEFF。删除确认前保留编号；池耗尽复用既有 applyAddress scene 接口追加 16 个，验证完整 Provisioner 数据再保存。兼容 lowAddress/highAddress、firstScene/lastScene 和整数列表格式。
- Scene 创建/编辑、Group 成员批量保存与公共加组、设备恢复/配置发送前共用容量校验。按设备去重期望编号，与已观测普通 Scene Register（含待清理残留）合并检查。任一设备无法新增则整次关系提交拒绝，双语提示设备及处理办法；Timed 的独立容量保护继续执行。
- Scene Register 读取不创建陌生 New Scene 业务记录；Store/Delete 的状态码和目标编号返回列表必须同时符合预期才能记成功。Fast Add 的响应检查同样执行。
- 场景整体删除检查定时/开关引用，覆盖原地址、Group 成员及当前已观测残留设备的 Scene Setup Elements。先持久化 waitDelete；部分失败保留业务场景与编号。再次删除只处理尚未确认移除的目标，网络/节点身份变化或观测失效时拒绝完成。
- 部分解绑且仍有可编辑 Space 时保留共享 Scene 地址池，取消旧的“每 Space 16 减已用数”回收计算；全部解绑继续走原有剩余地址回收。
- 独立只读审查后修正：已有 ID 更新误拦、旧地址响应形状、无需新增时多余读取、删除漏掉观测残留。另将断线失效放入 SDK 公共连接生命周期，覆盖无批量任务时断线。

### 9.3 自动化证据与限制

2026-10-29 执行并通过：

| 检查 | 覆盖与边界 |
| --- | --- |
| check_scene_capacity.sh | 15/16/17、重复 ID、已有更新/减少、未知/空、残留、编号边界、SDK Store/Delete 策略 |
| check_scene_topology.py | 执行生产拓扑投影；两设备各 16/共 32、整批拒绝、exit 恢复、已有 ID、旧地址格式、只在新增时读取 |
| check_scene_register_and_legacy.py | 执行生产 Register 分支和 SceneExecuteData Codable；陌生/特殊编号、无效响应、空 Register、旧默认值、waitDelete、32 条往返 |
| check_scene_deletion_flow.py | 执行生产 SceneServer；部分失败/重试、未知读取失败、断线观测失效、切换 Space 迟到回调、引用阻断、存储失败、组外残留；传输与存储是可控边界替身，不是 SQLite/真机测试 |
| check_timed_device_slots.py、check_timed_slot_persistence.py、check_schedule_scene_target_export.py | Timed 容量、旧格式、真实 SQLite 重开/回滚、Scene 目标与恢复。SQLite 夹具隔离 Scene 容量入口，Scene 策略由上述专门测试验证 |
| check_node_sync_status_refresh.py | Group/Scene/Timed 同步显示、失效/取消/重用；修正测试边界缺少已有 controlPanelView 的问题，未改相关生产 UI |
| check_fast_add_dual_scene_verification.sh、check_scene_delete_capability.sh | Fast Add 现有任务检查点及普通/LC 双场景、Scene-only 删除能力回归 |
| git diff --check、plutil | App/SDK 差异空白检查；工程文件及英/简中文案语法 |

SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 均通过 SunSmartLocal.xcworkspace 的 Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO 构建。使用固定 DerivedData 串行执行，未使用 Simulator。四个品牌首次 quiet 输出出现 Xcode 的“command failed with exit code 0”诊断但进程为 0；保持代码/依赖不变，用普通输出增量复核，均明确返回 BUILD SUCCEEDED，没有该诊断。现有弃用、weak 捕获及品牌资源告警未纳入本功能修改。

### 9.4 依赖与发布待办

- App 基线 feat/device-scene-261028 / 55bb8079；本任务改动保留工作区，未提交。
- 本地 SDK one-dev 基线 9998967，加本任务未提交差异：SceneRegisterPolicy、Element 观测、SceneClientHandler、MeshProxyMessageCommand、MeshFastAddDeviceManager、MeshLibManager 断线失效、customNextAvailableScene 及 MeshNetwork.remove 的持久化失败处理。
- SunSmartLocal 的 SDK realpath 为 /Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev；正式 project 仍使用原远端 release 配置。合入/发布 App 前必须先将这些 SDK 改动发布到正式依赖，当前远端 release 尚不能据本地构建视为已具备新 API。
- 未修改固件、服务器或其他客户端。后端需确认现有 scene 地址追加接口的 Site 唯一性/合法范围，以及超过 16 条场景完整上传下载；固件需按实际型号确认 Register 容量、满容量错误与删除确认。

最短人工验收：

1. 两组各一台设备，各存 16 条不同场景，Space 显示 32 条；第 17 条整次拒绝并列出满设备，已有场景改参数仍可同步。
2. 空组先关联 17 条，再尝试加入设备；确认拒绝、没有部分关系残留，Scene-only 设备也受保护。
3. 断开其中一台后删除场景，确认编号/待清理配置保留；重连重试，全部成功后才能复用。补做退出页面、App 重启、切换 Space。
4. 定时/开关仍引用场景时删除被拒绝；完成引用修改同步后可删除，旧 Recall 不触发新场景。
5. 用实际旧项目验证升级/导入前后编号、参数、关系及 waitDelete；新项目超过 16 条后云端/分享完整往返，并验证地址池耗尽后的追加。
