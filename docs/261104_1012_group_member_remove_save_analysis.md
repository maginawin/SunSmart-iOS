# 组、场景与定时成员编辑：SAVE 拦截、一致性问题及修复方案

日期：2026-11-04；时间均为环境时间 UTC+08:00。

## 结论

当前分支存在可复现的 App 状态一致性问题：Group Members 保存时只把内存中 L3 的 `groupState` 改为 `.exitFailure`（待退组），没有保存 Node。紧接着的同步准备同时读取数据库快照和当前内存网络，数据库认为 G1 包含 L3，内存认为 G1 已排除 L3，因而触发 `cleanupPreparation / -2004`，阻断任务建立。

直接让这一问题变成用户可见阻断的提交是 **`eb189247`，2026-11-03 10:13:04，`fix: delete scene wrong alert issues`**。它开始处理此前被忽略的 cleanup 失败。应修复成员变更的持久化边界，保留真实异常的同步拦截。

用户确认后已于 2026-11-04 按下述方案实施 App 修复，未修改 SDK、服务器、固件或原始样本。新增的两库恢复与场景失败回滚已通过定向自动化；真机 BLE、UI 和服务器收敛仍待人工验收。实施与验证记录见文末。

补充检查组添加、场景和定时成员增删后，结论是：**并非全部操作都有相同根因**。组重新加入待退组成员会发生相反方向的同类比较失败；原无组设备加入还缺少目标组的持久化恢复信息。场景正常增删已有持久化机制，但外层最终 COMMIT 失败时会遗漏内存 Timed slots 回滚，需要小范围修复。定时成员编辑未发现独立同类问题。

| 操作 | 健康 Space 独立执行 | 同类问题与修复范围 |
| --- | --- | --- |
| 组删除成员 | 已复现 DB/live 成员集合不等 | 本次原始根因，补待退组状态保存及恢复。 |
| 组重新加入待退组成员 | 已复现 DB/live 成员集合反向不等 | DB 仍为 exitFailure、内存已恢复 inGroup；并入同一保存修复。 |
| 组添加原本无组的成员 | 通常不触发这条拓扑比较错误 | 目标组仅由当前 inNodes/页面上下文携带，首个订阅成功前退出会缺少恢复依据；并入加入意图持久化。仅保存 inGroup 不够。 |
| 场景添加/删除成员（组场景、设备场景） | 正常路径未发现同一根因 | 已有 App 配置、pending operations 和 SDK projection 恢复；另修外层最终 COMMIT 失败后遗留内存 slots 的缺口。 |
| 定时添加/删除成员（设备、组、场景目标） | 未发现独立同类根因 | 目标和 pendingRemoval 先持久化，保留原实现，补关联和失败路径回归。Profile 目标目前只读，不计为已支持的成员编辑。 |

同一 Space 若已因组编辑留下 DB/live 差异，随后场景或定时同步也可能被共享的全 Space cleanup 拦截。这是组根因的连带表现，不代表这些页面各自都漏了保存。

## 现场证据

输入文件：

- 操作前：`/Users/maginawin/Downloads/Space_Space 1_20261104_095638_671+0800.json`
- 日志：`/Users/maginawin/Desktop/remove L3 from G1 logs.txt`
- 操作后：`/Users/maginawin/Downloads/Space_Space 1_20261104_100359_220+0800.json`
- 服务器快照：`/Users/maginawin/Desktop/server data of remove L3 from G1.txt`

| 项目 | 操作前 App | 操作后 App | 操作后服务器 |
| --- | --- | --- | --- |
| G1 地址 | C000 | C000 | C000 |
| L3 主地址 | 0008 | 0008 | 0008 |
| L3 组地址 / 状态 | C000 / 1 | C000 / 1 | C000 / 1 |
| G1 逻辑成员（按持久数据） | 0002、0008 | 0002、0008 | 0002、0008 |
| Space updateTimestamp | 1793756623 | 1793757799 | 1793756623 |

操作后 `rawLocal.mesh.nodes` 中 L3 的 `groupState` 也为 1，证明不是导出展示层单独丢失状态。当前保存路径确实保存了部分 App 数据并推进 Space 时间，但待退组状态没有写入 Mesh 数据库。这里不能把“L3 仍在 G1”解释为整次操作已完整回滚。

前后导出的 Scene、Group 和逻辑 Schedule 内容没有发生对应退组变化；设备时间戳、SQLite 行 ID 及部分 Scheduler 数组排列有变化。L3 在 Schedule 1 / Schedule 2 的 `nodeSlots` 中已经是 `pendingRemoval`，操作前便如此，不能归因于这一次 SAVE，也不能据此删除它作为直接设备目标时仍需保留的任务。

两个 App 快照均显示：`issues=[]`、recovery 为 `active/writable`、membership 为 `joined`，无 pending import/upload/deletion cleanup。操作后的最后一次确认时间仍是 09:43:43，本地版本已到 10:03:19，最后失败记录为 10:03:32。服务器保持旧版本，与准备阶段被挡住的行为吻合；现有证据不支持“服务器先删除或破坏了 G1/L3 数据”。

操作前已有 09:40:19 的 `cleanupPreparation / -2004` 记录，说明该类失败早于本次样本中的操作。没有那一次完整日志，不能确认它与本次一定同因。

日志关键顺序：

1. `SceneSync stage=restoreReady scene=0`。
2. Space 导出：`networkReused` → `ProximityLightingExport ... repairs=0` → `end`。
3. `SpaceConfigurationSync stage=cleanupPreparation error=-2004 reason=none`。
4. 进入 `SyncDevicesViewController`。

之前的 `LightCTLGet` 超时目标是 `0011`（L5），不是 L3 的 `0008`。本次阻断分支的触发条件是本地拓扑不一致，日志中的 CTL 超时不是解释这次错误所必需的原因。日志未细分 cleanup 的每一个 guard，因此实际 guard 的定位来自源码链路及下述隔离复现，尚无修复后的真机证据。

## 完整触发链

1. `GroupMembersViewController.performSave` 计算新成员为 L1；先准备 Timed 绑定与 Proximity Lighting 拓扑。
2. `TimedSchedulerBindings.commit` 与 `ProximityLightingLifecycleCoordinator.commit` 保存 Schedule、GroupInfo、Space 和相关预配置。退组 closure 只执行 `node.groupState = .exitFailure`，没有 `node.save()`；重新勾选待退组设备时设 `.inGroup` 的路径也缺少相同保存。
3. 本机 SDK 的 `Node.groupState` setter 只是 associated object 赋值，不会持久化。实际 `groupState` 列由 `Node.save()` 写入 Mesh 数据库。`node.preConfiguration.save()` 保存 App 预配置，不能代替 Node 保存。
4. 页面随后创建 `.group(group, inNodes:, outNodes:)` 同步页面。`rebuildTaskPlan` 在建立任务前调用 `prepareForDeviceSync()`。
5. `SpaceSyncCleanupCoordinator.perform` 调用 `space.export(purpose: .cleanupInspection)`。`snapshotExportAuthorization` 先 `MeshNetwork.load`，导出中的 `networkReused` 只是复用这份刚从数据库读取的对象，不是复用 manager 的内存网络。因此这边 L3 仍为 `.inGroup`。
6. 同一次 cleanup 随后调用 `ProximityLightingTopologyContext.network(for:)`，相同 Space 优先取 `MeshNetworkManager.instance.meshNetwork`；`members` 明确排除 `.exitFailure`，所以这边 G1 只有 L1。
7. `SpaceSyncCleanupPolicy.equivalentTopology` 比较成员集合。即使 G1 不是邻近照明组，也比较成员；非邻近组只归一 relay 值。`{0002,0008}` 与 `{0002}` 不一致，返回 false。
8. defer 把无更具体原因的失败记为 `cleanupPreparation / configurationUnavailable`。同步页面收到错误，显示用户看到的文案，不建立本次退组下发任务。

相关源码入口：

- [GroupMembersViewController.swift](../SunSmart/Main/Group/Controller/GroupMembersViewController.swift)
- [ProximityLightingLifecycleCoordinator.swift](../SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift)
- [ExportData.swift](../SunSmart/Common/Data/ExportData.swift)
- [GroupProximityLightingData.swift](../SunSmart/Main/Group/Model/GroupProximityLightingData.swift)
- [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift)
- [SyncDevicesViewController.swift](../SunSmart/Main/Space/Controller/SyncDevicesViewController.swift)

## 什么时候引入

| 提交 | 时间 | 对本问题的作用 |
| --- | --- | --- |
| `544c30ce` | 2024-04-09 10:45 | 可追溯的旧写法：退组先只设置内存 `.exitFailure`，随后开始设备同步。当时没有当前的 DB/live 比较关口，不能把当前回归直接定年为 2024。 |
| `1d1f3cdb` | 2026-09-03 11:48 | 引入生命周期保存，保留只改内存 Node 状态的写法。 |
| `54804a09` | 2026-09-15 11:17 | 引入 cleanup 中数据库导出与当前内存拓扑的比较。旧保存方式开始可能导致 cleanup false；同步入口当时忽略 false，继续建任务。 |
| `cf99bbd1` | 2026-10-08 17:29 | 引入 Timed 保存事务与回滚，仍保留 Node 未保存的缺口。 |
| **`eb189247`** | **2026-11-03 10:13** | **由忽略 cleanup 返回值，改为收到 cleanupError 就显示错误并停止任务准备；是当前用户可见退组阻断的直接回归点。** |

`32625056`（09-08）的导出网络复用优化不是读源变化：优化前后导出都从数据库读取。11-03 最新的进入 Space 性能改动也不是上述硬拦截的首次引入点。

以上是当前 Git 历史中的归因。现场日志没有构建 revision，不能仅凭日志认定手机二进制恰好等于当前 HEAD。

## 补充调查：组添加、场景与定时

### 组添加需要区分两种状态

1. **重新加入待退组成员**：设备仍有 G1 订阅，数据库为 `.exitFailure`，Members SAVE 仅把内存改回 `.inGroup`。生产清理策略得到数据库 G1 `[2]`、内存 G1 `[2,8]`，同样失败。这与移除时是同一个持久化缺口，同样在 `eb189247` 开始硬拦截后影响正常进入同步。
2. **原无组设备新加入**：设备没有 G1 订阅，两侧成员集合仍都不包含它，故通常不会在同一 guard 失败。但 `extensionChanges` 会把内存状态纠正成数据库的 `.none`；同步页依靠临时 `.group(..., inNodes: addNodes, ...)` 仍可建立订阅任务。尚未有任何订阅成功就退出/重启时，GroupInfo、Node 和原页面之外没有保存目标 G1，无法仅靠重新加载恢复这次加入。

补充纯策略探针用原样本中的无组 L5 验证：即使假设把 `.inGroup` 写入数据库，只要还没有订阅，`normalize` 仍会把它规范回 `.none`，不会产生目标组。**原方案中“所有 addNodes 只保存 inGroup”不足以解决新加入恢复，需作下述修订。**

项目已有可复用机制：`NodeRestoreData.addGroupAddress`。Classic / Professional 设备添加在未加入组成功时已保存这一字段；`Node.getSyncData(.all)`、`getNeedSync`、Scheduler owner 和同步读取上下文会消费它，成功订阅的 ACK 路径会清除它。Members 保存目前没有写入这一字段。应扩展现有机制，保留恢复数据中其它参数，避免另造组归属协议或将未确认订阅伪装成已成功。

### 场景正常保存与异常回滚

- SceneSettings 的组/设备选择先改 draft；DONE 经 `SceneSaveCoordinator.saveForSync` 进入 `SceneConfigurationStore.commit`。
- 同一个 App 事务写入 `GroupInfo.sceneExecuteDatas`、`SceneInfo.configuration`、成员 write/remove pending operations 和关联 Timed slots。它不改 Node.groupState，因此不会独立制造 G1 那种拓扑差异。
- App 提交成功后才投影 SDK Scene。投影失败保留持久配置、revision 与 `projectionPending`，重启由 `restoreSceneProjections` 重试；导出也以 App Scene rows 为权威。复用这些现有机制即可，无需把组编辑的跨库恢复记录套到 Scene 上。
- **新确认缺陷**：`TimedSchedulerBindings.commit(plan)` 的内层 savepoint 已成功，但外层 `configurationTransaction` 最终 COMMIT 失败时，内层 catch 无法获知错误。Store 的失败 guard 只恢复 `previousGroups`，遗漏 `plan.schedules.nodeSlots`。
- 真实 SQLite commitHook 故障注入已复现：移除设备场景的最后成员，提交返回 persistence；数据库 slot 仍是 `assigned`，内存 slot 却残留 `pendingRemoval`。设备重新加入、组场景删除最后一组也复现相同数据库已回滚而内存未回滚的结果。后续同步/分配可能使用未提交的意图。此处不能直接等同为本次 `cleanupPreparation/-2004`，也没有证据表明普通保存都会触发。
- 新增、重新加入、删除组/设备场景成员共享该 Store.commit 外层失败分支；只要变更关联 Timed bindings，都应纳入回滚测试。该缺口可追到 `c1a7bd2a`，2026-10-30 08:12，`feat: device scene`。

生产 `SpaceData.load(subNetworkId:)` 每次创建独立对象，Timed commit 内更新 schema 的对象未发布为当前 Space；本缺陷不需要额外扩大到当前 Space 字段回滚。

### 定时已有持久化保障

`ScheduleAddViewController` 新增与编辑分别在保存和 DONE 路径中调用 `TimedSchedulerBindings.commit`，成功后才发布到 `manager.schedules`；编辑使用 original.copy。该 commit 把 active targets、`needDelete*`、`nodeSlots` 和 schema 保存在 SQLite savepoint 中，失败恢复 slots。导出及 cleanup 都读取持久化 Schedule。

删除目标把对应绑定转为 `pendingRemoval`；仍存在的设备不会被 `repairingStaleBindings` 因为退出目标集合而删除。重新加入恢复 assigned；物理清理回执前保留原 slot/generation。整条定时删除也先保存待删除意图。真实 SQLite 定向回归已覆盖重启、pending cleanup、失败回滚和晚回执，没有发现必须新增的 Timed 成员编辑修复。

相关入口：

- [SceneSettingsViewController.swift](../SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift)
- [SceneSaveCoordinator.swift](../SunSmart/Main/Scene/Model/SceneSaveCoordinator.swift)
- [SceneConfigurationStore.swift](../SunSmart/Main/Scene/Model/SceneConfigurationStore.swift)
- [ScheduleAddViewController.swift](../SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift)
- [TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift)
- [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)

## 修复方案与范围

目标：Members SAVE 成功后、设备 ACK 前，数据库与内存都表达相同的成员变更意图；加入目标可恢复，退组的设备实际订阅保留到成功回执。失败可重试，退出或重启不丢失已经保存的意图；Scene 保存失败不得遗留未提交的内存 Timed slots。

推荐在 App 的成员保存边界补齐显式持久化及失败恢复，复用 `Node.save()`、现有 Timed 事务、拓扑 lifecycle、任务重试和订阅 ACK 更新机制。

不建议恢复“忽略 cleanup 失败”：会同时放过真正的数据缺失、权限和恢复错误。仅把 cleanup 移到成员修改之前也不完整：可以避开这次比较，但退出重进及后台导出仍会读到旧状态。单纯让导出改读内存则会削弱对实际落盘数据的检查。

### 1. 保存成功边界

- 在 Group Members 的统一保存路径中处理所有 `exitNodes` 和 `addNodes`，包括多选移除、同次增删、重新加入处于 `.exitFailure` 的成员。配置引导共用本控制器，也应使用同一路径。
- 退组保存 `.exitFailure`；对仍有该组订阅的待退组设备，明确重新加入时保存 `.inGroup`。一并持久化本次已修改的 `requiredFunctionTypes` 等 Node 字段，保持已有预配置和 Timed 保存。
- 对原本无组的新成员，复用并保存 `restoreData.addGroupAddress` 表达待加入目标，实际成员状态仍由订阅及回执确定；不能只保存 `.inGroup`。更新现有 restoreData 对象中的组字段，保留校准、调光、过渡时间等其它待恢复参数。
- 将当前组的待加入记录纳入 Members 选中展示、增删差集和重试读取；若首次订阅前撤销加入，清除该加入意图，不伪造退订任务。另一组的未完成加入不得被无提示覆盖；校验目标组存在及网络归属。
- 复用已有订阅成功后的 addGroupAddress 清理路径；部分订阅成功后由真实订阅和现有同步检查继续补齐，失败/取消前不得清除唯一恢复依据。设备添加的 Classic / Professional 既有使用方加入兼容回归，不顺带重构其添加流程。
- 检查 SDK 保存结果，并重新读取对应 Node 验证身份及目标状态。只有本次所有必要写入和读回完成，才允许进入设备同步。
- 不预先删掉 Model 的订阅，不把成员状态写成 `.none`，不清空实际 Scene/Scheduler 缓存。现有 `ConfigModelSubscriptionDelete` 成功回执完成退组；失败继续保留 `.exitFailure`。

### 2. 两个数据库的失败与恢复

这是本次补保存必须处理的一致性边界：`SunSmartDataManager` 的 App savepoint 不会回滚 `Node.save()` 写入的 Mesh 数据库。不能只在 closure 末尾补一行保存，再假定现有 catch 已覆盖持久化回滚。

- 复用现有内存快照及 App savepoint；记录本次触及 Node 的旧/新状态及待加入目标，Node 写入失败或后续 App 提交失败时，恢复已写 Node，并核验读回。restoreData 是引用对象，旧值需独立复制，不能把同一个对象引用当成回滚快照。
- 为两库写入间退出/重启保留本操作专用的轻量恢复记录，放在 App 本地 SQLite，与 App 业务提交共用事务标记。记录限定到当前账号、Space、Group 和设备实例，保存必要旧/新字段，不记录完整密钥，不作为云端配置输出。
- 准备记录先持久化；App 事务内完成 App 数据、Node 写入及 committed 标记。重启看到准备态时恢复旧 Node 状态，看到已提交态时校验/补完目标 Node 状态；核验完成再删除记录。读回不一致或恢复失败继续拦截，不能静默当成功。
- 恢复入口先于 cleanup 的普通阻断和 DB/live 比较执行，并同步当前内存对象；检查记录中的设备实例和当前账号/Space，不能向被删除后重新配网的同地址设备重放。
- 保持单个成员保存负责写入；等待恢复期间禁止重复 SAVE 和任务下发。此记录只解决成员编辑跨库窗口，不扩展成通用事务框架。

这一点会比单纯补 `node.save()` 多少量 App 代码，但能覆盖本次写入新增的部分成功及重启窗口；不需要 SDK 新 API、数据库连接暴露或服务器字段。

### 3. Scene 最终提交失败回滚

- 在 `SceneConfigurationStore.commit` 开始外层事务前，保存 `plan.schedules` 对应的原 `nodeSlots`。
- 外层失败 guard 恢复 slots 和原 Group Scene 数据，不发布新的 Scene 配置，不启动 SDK projection/设备同步。覆盖事务 body 失败、内层 savepoint 失败及外层最终 COMMIT 失败；恢复操作应可重复。
- 成功路径维持原 pending operations、revision、projectionPending 与恢复机制。仅扩展已有回滚边界，不新建 Scene 日志或修改云端结构。
- 定时独立编辑无需套入新的 Scene/Group 保存层；对其与 Group/Scene 联动保留回归即可。

### 4. 关联入口及诊断

- `GroupServer.getNodeExitMessageHandles` 也设置 `.exitFailure`，但它处于消息生成阶段；核对所有调用方，确保已保存的意图不会被任务生成覆盖，也不要依赖建任务才首次保存。
- 保持普通 Group、Group Scene、直接设备 Scene/Timed 的目标语义：退出 Group 只能移除由该 Group 派生的目标；仍直接引用 L3 的任务继续保留。现有 pending slot 的 generation 不得无故重建。
- 保留 cleanup 的完整性检查。给拓扑等价失败增加独立 DEBUG 阶段和有限字段（组地址、两侧成员地址/数量、是否取当前网络），不再全部落为 `reason=none`；日志不含密钥或整份 JSON。
- 本次数据不需要自动修改服务器或批量重写历史 JSON。现有数据库未保存的退组选项无法从快照可靠推断；修复后由用户重新选择 L3 并 SAVE。已持久化的 `.exitFailure` 则按现有同步重试恢复。

预计修改集中在 Group Members 保存及其小范围持久化辅助、cleanup 恢复/诊断入口、SceneConfigurationStore 的外层失败回滚和相关测试；必要的本地恢复存储放入现有 App 数据层。共享代码影响五个品牌，未发现本路径的品牌差异；不改固件、后端或正式 SDK 依赖。

## 实施和验证清单

确认方案后按以下顺序实施，默认由主代理统一写入；不自动提交、推送或安装真机。

- [x] 补行为回归：执行实际成员保存，再从独立持久化读取路径取快照，不能让 DB/live 共用同一个 Node 替身。当前代码应重现 G1 两侧成员不等。
- [x] 实施成员持久化、返回值/读回验证、两库失败补偿与操作记录恢复；再接入同步前准备。
- [x] 覆盖 L3 从 G1 移除、一次移除多成员、同时增删、重新勾选待退组成员、G1 移除最后成员、无 Scene/Timed 的普通 Group。
- [x] 覆盖原无组设备加入、首个订阅 ACK 前取消/退出/重启、撤销未完成加入、已有其它 restoreData 字段及目标组消失/网络切换；确认只保存 inGroup 的旧方式会失败，新增目标恢复信息后可继续同步。
- [x] 覆盖有关联 Scene/Timed、直接设备目标重叠、已有 pendingRemoval，以及无关组和任务不变。正常导出/导入允许合法空组，不放宽权限、实例身份或坏数据校验。
- [x] 为 Scene 成员添加、删除、重新加入和删除最后成员补外层最终 COMMIT 失败注入；断言数据库、Scene/Group 内存及相关 Schedule slots 全部恢复。单独保留 SDK projection 失败后的重启恢复验证。
- [x] 覆盖每个 Node 保存失败、部分 Node 已写后失败、App 最终提交失败、补偿失败，以及准备态/提交态重启恢复；核验 App 表、Mesh 行、内存三者，而非只检查页面提示。
- [ ] 同步准备、取消和重试已有隔离回归；真实 BLE 离线/超时、退出重进及订阅成功 ACK 后变 `.none` 仍待人工验收。自动化已验证 SAVE 不会提前清除物理订阅。
- [x] 修正现有测试夹具与当前生产接口的脱节，再运行相关清理、同步准备、Timed 持久化和 Scene 拓扑回归。重点入口：`check_space_sync_cleanup.py`、`check_space_sync_readback_reuse.py`、`check_sync_preparation.py`、`check_timed_slot_persistence.py`、`check_scene_topology.py`；其余按实际改动选择，不全量机械扩张。
- [x] 一轮 Swift 修改稳定后，用现有 `SunSmartLocal.xcworkspace` 构建 SunSmart Debug generic iOS，关闭签名并使用本工作树稳定 DerivedData；本任务不使用 Simulator。若新增文件/资源有 target 归属风险，再覆盖受影响品牌构建。
- [ ] 人工验收：重新进入 Space → G1 Members 取消 L3 → SAVE，应进入并执行同步；中途退出/重启后仍可重试，成功后 L3 无 G1 订阅；再验证本地导出和服务器读回一致。此步骤必须由实际设备和云端结果验收，离线测试不能替代。

## 分析阶段验证结果与限制

1. `check_space_sync_cleanup.py --snapshot <服务器样本>` 通过，现有纯清理策略接受该快照，5 个设备、0 个 relay 兼容修复、0 个邻近照明设备变更。
2. 临时 Swift 探针读取三份原始样本，调用生产 `SpaceSyncCleanupPolicy.normalize/equivalentTopology`：均复现持久 G1 `[2,8]` 与模拟 SAVE 后内存 G1 `[2]` 不等；仅将 L3 持久状态改为 2 后相等，订阅内容不变。修改只发生在探针内存副本，没有改输入文件。
3. 临时提取生产 `perform`，用受控 I/O/拓扑适配验证不一致分支：一次 export、`cleanupPreparation`、无 cleanup 提交和 finish；正常及已有 readback/失败保护场景继续通过。这证明分支行为，不是完整 App 运行。
4. `check_sync_preparation.py` 的共享权限和 Site Gateway 子套件通过；Controller 子套件因夹具缺少 `permitsSceneReferences` 无法编译，整体脚本未通过。
5. `SpaceSyncReadbackReuseTests` 的现有替身缺少当前生产调用的 `recoverCloudMembershipIfNeeded`。本轮仅在临时副本补上受控 true 返回用于探针；没有修仓库夹具，也不宣称原脚本已通过。
6. 旧隔离测试没有覆盖真实 Members SAVE 到独立 Node 持久化再到 cleanup 的完整边界；其中拓扑替身默认使用相同常量快照，无法暴露本次差异。此前测试成功不能证明这条链路成立。
7. 补充组添加探针通过：重新加入待退组 L3 复现相反方向的拓扑不等；无组 L5 只保存 inGroup 会被生产清理策略规范回 none。加入意图退出丢失结论结合实际 Members 写入、重进选中逻辑及 NodeRestoreData 消费链得出，尚未做真机退出/重启复现。
8. 补充 Scene 临时探针运行生产 Store、Timed commit 和真实 SQLite 事务：设备最后成员移除、设备重新加入、组场景最后组移除均复现外层 COMMIT 失败后 diskRestored=true、liveRestored=false。正常设备/组场景移除最后成员再加入，验证了持久组关系、pending remove→write、同一 Timed slot pendingRemoval→assigned，以及 Node.groupState 不变。附加探针后的 save/coordinator 套件通过，现有 targets 套件 28 项通过；真实 SDK projection 和异步 cleanup 全链没有运行。
9. `check_timed_slot_persistence.py` 与本轮 `check_space_sync_cleanup.py` 通过；前者覆盖实际 Schedule SQLite 的重启、待清理、回滚、晚回执及 Group/Scene 联动。`check_timed_empty_target_cloud_sync.py` 因旧夹具缺少 Schedule.selectTargetType/profile 与 HUD.showTipHUD 无法编译，列入实施时验证夹具修复，不计为业务根因或已通过。

## 分析阶段工作区记录

- App：`feat/device-scene-261028`，HEAD `63c4776e`；开始分析时工作区干净，本轮仅新增本文档。
- 本机 workspace 映射已核对：`.local-sdk/nordic-sig-mesh-sdk` 指向 `nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK：HEAD `dbcf6f1`，已有 MeshProxyMessageCommand / SchedulerActionStatus 及独立 Scheduler 测试的未提交改动；本轮只读，未触碰。
- 已完成原因、历史和生产策略隔离验证；未实施修复，未构建，未做真实 BLE、UI、服务器联调。


## 实施结果（2026-11-04）

已完成以下 App 改动，尚未 commit/push：

- `GroupMemberPersistence` 统一持久化待退组、重新加入和首次加入意图。先保存操作专用的 App SQLite receipt，再在 App 事务中保存 Mesh 状态、Timed、Group/Space、预配置及开关代理移除意图，最后写 committed 标记。实际订阅保持到 ACK。
- prepared 记录恢复旧 Node 字段，committed 记录补完目标字段；每轮先核对账号、区域、Site/Space、网络、Group、Node UUID/地址/Device Key 指纹，再从新加载的 Mesh Node 写入并读回验证。记录不包含完整密钥，也不进入云端导出。SDK `Node.save()` 返回成功仍须经独立数据库读取验证。
- 故障补偿失败时保留 receipt、恢复界面中的旧状态并继续阻断编辑/同步；后续重试完成落盘恢复。App 已提交、仅 receipt 删除失败时保留已提交的 App 内存，不错误回滚业务配置，也不开始设备同步。
- 普通权限保护增加 receipt 检查；本次 Proximity 提交只可按自己的 prepared receipt ID 排除自身记录，其余原有保护保持有效。恢复先于 Space 扩展数据的 Scene 恢复、同步页 Scene 恢复与 cleanup 比较执行，避免自身阻断。
- Members 页面显示并重试本组待加入设备；撤销尚无任何实际订阅的加入时只清加入目标，不生成退订目标；保留其他 restore 字段。SDK restore codec 未编码的两个运行时字段在快照/回滚时单独保留，本次不修改 SDK 编码约定。
- 独立审查补充发现并修复：首个订阅 ACK 前删除目标 Group 后，残留加入目标不能把无组设备永久排除在其他组之外。只允许替换同网络/子网中已不存在的旧目标；保存时再用新加载的 Mesh 网络核对。尚存的其他 Group 意图、不同子网、不同设备实例仍拒绝覆盖。该场景先观察到回归失败，再修复通过。
- `SceneConfigurationStore` 在外层最终 COMMIT 失败时恢复 Timed slots；组与设备场景的成员移除/重新加入均覆盖原 slot、pendingRemoval 和 generation。普通定时成员编辑沿用已有机制。
- 增加 `topologyComparison` DEBUG 阶段诊断。清理比较、真实数据缺失、权限、导入/恢复保护均保留。

实施决定：原先在后台先行保存的开关代理移除字段移入同一 App 事务；保存期间禁用重复 SAVE。新增文件按已有 `GroupServer.swift` 的全部 6 个 target Sources 归属加入，不改变品牌编译条件，不新增依赖或本地化文案。

## 实施验证与验收边界

| 检查 | 结果与覆盖 |
| --- | --- |
| `check_group_member_persistence.py` | 通过。运行生产 Members 保存方法、成员持久化协调器、App transaction、SDK restore codec 和 cleanup normalize/equivalentTopology；App/Mesh 使用两份独立 SQLite 文件。覆盖移除/重新加入/全部移除、同次增删、待加入重启/取消、目标组删除、其它组保护、旧内存缺组但数据库仍有组、不同子网、部分 Mesh 写入失败、假成功读回失败、App body/最终 COMMIT 失败、补偿失败重试、prepared/committed 重启恢复、receipt 删除失败、替换设备身份、权限拒绝。UIKit/BLE、SDK Node 序列化和拓扑生命周期适配仍为测试边界。 |
| `check_scene_configuration.py --suite save` | 通过。实际 SQLite 外层最终 COMMIT 故障注入验证设备/组场景最后成员移除与重新加入的数据库和内存同步回滚；既有保存/协调器回归继续通过。 |
| `check_timed_slot_persistence.py` | 通过。真实 SQLite 的 Timed 绑定/失败回滚/重启、组退出、直接 Scene 重叠、pending slot/generation、晚回执及空目标保留。 |
| `check_space_sync_cleanup.py`、`check_scene_topology.py` | 通过。合法空配置、退出状态、保留物理观察值、拓扑比较与容量预检。 |
| `check_proximity_scoped_import.py` | 通过。实际 lifecycle、受保护清理、删除恢复、作用域隔离及批量清理。测试边界已兼容新增自身 receipt 参数。 |
| `check_sync_preparation.py`、`check_space_sync_readback_reuse.py` | 通过。修复原夹具漂移并补恢复失败前置拦截；权限/取消/重试/晚回调、持久读回失败继续阻断。Scene reference policy 在准备页套件中为可拒绝的受控边界，不将其等同为真实 Scene 删除全链验证。 |
| `check_timed_empty_target_cloud_sync.py` | 通过。修复 Profile 只读及 HUD 夹具漂移；空目标增删、删除失败与云端脏状态保持正确。 |
| `check_sync_task_builders.py` | 通过。Group 退出、场景删除所有权、同步依赖、成功/重试结果范围和网关关联空间契约。保留已有不可达 default 编译警告。 |
| SunSmart Debug generic iOS | 10:41 首次及审查修订后 10:46 最终增量构建均为 `BUILD SUCCEEDED`。入口 `SunSmartLocal.xcworkspace`，关闭签名，稳定 DerivedData `SunSmart-feat-device-scene-261028-cli`。未使用 Simulator 或安装设备。 |

本轮测试夹具使用匿名合成数据，没有复制用户导出的密钥/完整 JSON。新的实际控制器双库回归补上了旧测试将持久化和当前拓扑视作同一对象的缺口。自动化仍不能替代完整 App 的 BLE 传输、UI 或服务器联调。

SDK 来源保持 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`、HEAD `dbcf6f1`；其原有 MeshProxyMessageCommand / SchedulerActionStatus 和独立 Scheduler 测试差异未修改。本次没有新增 SDK API 发布依赖。其他品牌 Sources 归属已静态核对，未做其他品牌编译。

最短人工验收：

1. 退出重进 Space，G1 Members 取消 L3 → SAVE，应能进入同步；停止/返回再重试，待退组意图仍在，成功 ACK 后才消失实际订阅。
2. 重新加入仍待退组的 L3；另选无组设备加入，首个订阅成功前停止并重启，再开 Members 应仍选中。取消该待加入设备，不应产生退订任务；若旧组已删除，设备可选入新组。
3. 对有 Group/直接 Scene/Timed 重叠引用的设备重复增删，检查独立目标不被误删；合法空组、空场景/定时仍能保存。
4. 完成同步后导出 App 并核对服务器读回。真实设备、UI 与云端收敛待人工验收；本次不自动操作服务器或真机。

最终静态检查：`git diff --check` 与 `plutil -lint SunSmart.xcodeproj/project.pbxproj` 通过；新文件与 GroupServer 的 6 个 Sources 归属一致。独立审查发现的 P2 已复现并修复，其余主链未确认新的 P1/P2。未修改无关的 `docs/261104_1023_agents_simplification_proposal.md` 或已有 SDK 差异。
