# Scene 删除引用限制与重复提示分析

日期：2026-11-03。分析基线：`feat/device-scene-261028`，HEAD `b1bab004`；开始分析时工作树无未提交修改。第 1～4 节保留当时分析快照；用户已于本日批准按第 5 节方案实施，第 6 节记录首轮实现与验证；第 7～8 节记录随后真机失败的身份匹配修复；第 9～10 节记录删除耗时分析及已批准的命令精简、SDK 短响应修复。

## 结论

- Timed / Switch 引用阻止 Scene 删除的限制首次加入于 **2026-10-29 15:12:20 +0800**，提交 `a3fa935ee6116e1db3862eee7a8ced2c66370b7f`，标题 `feat: you can add more scenes now`。
- 重复提示来自新引用拦截与旧失败恢复 UI 的组合：底层弹引用提示并调用通用失败回调；详情页显示删除失败，1.5 秒后跳同步页；同步成功回调再次删除，同一引用仍存在，再次弹窗。
- 加入限制前允许有引用的场景进入删除；直接删除与失败后的同步补偿处理不一致，没有完整的 Timed / Switch 自动解除及设备确认闭环。
- 当前保护目的合理，但当前反馈与跳转不匹配拒绝原因。业务引用拒绝发生在删除意图创建之前，不应自动进入普通 Scene 同步重试。

## 1. 引入时间与目的

通过 `git log -S scene_delete_referenced`、`git blame` 与提交前后对比确认：

| 时间 / 提交 | 变化 |
| --- | --- |
| 2024-01-19，`0475c3fc` | 详情页已经使用“删除失败提示 → 延迟 1.5 秒 → 同步页”的恢复流程。 |
| 2026-10-29，`a3fa935e` | 开放更多 Scene 时新增 `referenceNames`、引用弹窗及拒绝删除；未同步修改上述页面失败分支。 |
| 2026-10-30，`c1a7bd2a` | Device Scene 引入持久删除意图和统一同步会话，继续保留引用拒绝；引用收集复用 `SceneConfigurationStore`。 |
| 2026-11-03，`eb189247` | 标题为 `fix: delete scene wrong alert issues`，实际处理同步准备阶段权限、Restore、删除重试错误的归因等；没有修复本次两个 Scene 页面对引用拒绝的处理。 |

[容量分析方案](261029_1418_space_scene_capacity_analysis_proposal.md) 的“4.4 删除、回收与历史数据”已写明：有效定时/开关引用存在时拒绝删除，先修改或移除引用并同步，再允许删除；不自动删除定时和开关业务记录。

背景是 Scene Number 会复用。若旧定时或开关仍持有旧编号，新场景采用同一编号时，旧动作可能控制新场景。这里只能确认代码与方案针对该风险设计，不能据此声称具体固件已实测发生误触发。

## 2. 当前完整触发链

1. [SceneServer](../SunSmart/Main/Scene/Model/SceneServer.swift) 的 `deleteScene` 调用 `referenceNames`。
2. [SceneConfigurationStore](../SunSmart/Main/Scene/Model/SceneConfigurationStore.swift) 的 `deletionReferenceNames` 收集：
   - Timed 当前 `sceneNumber`；
   - Timed 待清理的 `needDeleteSceneNumbers`；
   - Switch A / B / C / D 保存的场景编号；
   - 设备缓存中仍有效、指向该编号的 Scheduler Model Entry。
   业务 Timed / Switch 的检查没有按 `enabled` 过滤；保存着该编号即可阻断。提示中因此也可能包含设备名称。
3. 有引用时，底层先显示 `scene_delete_referenced`，再调用只有 Scene 参数、没有失败原因的 `failed` 回调。此时尚未执行 `prepareDeletion`，没有因本次删除创建 `isDeleting` 意图，也没有发送本次 Scene Delete。
4. [SceneViewController](../SunSmart/Main/Scene/Controller/SceneViewController.swift) 的详情页失败分支无条件显示 `scene_delete_failed`，1.5 秒后 push `SyncDevicesViewController(type: .scene(scene))`。
5. 同步页执行普通 Scene 同步；由于本次尚未建立删除意图，并不会自动修改当前有效 Timed / Switch 业务引用。可能没有任务，也可能执行原有 Scene / 定时配置同步。
6. [SyncDevicesViewController](../SunSmart/Main/Space/Controller/SyncDevicesViewController.swift) 在同步完成且状态为成功时触发 `syncSuccessCallback`。详情页回调再次调用 `SceneServer.deleteScene`，仍被相同引用拒绝，于是再次出现引用弹窗和删除失败提示。

第二次引用弹窗不是同步页独立新增的引用检查，而是它的成功回调重新调用删除入口。无任务时也可能快速进入成功回调，解释了看起来“刚跳过去又弹窗”的表现；现场时序未通过运行日志复现。

[ScenesViewController](../SunSmart/Main/Scene/Controller/ScenesViewController.swift) 列表页有同类问题，但跳转条件不同：失败后仅当 `scene.needSyncGroups.count > 0` 才打开同步页。其同步成功回调还会先显示 Done，再以空回调重新删除，因此存在同步成功与最终删除结果不一致的反馈风险。

## 3. 限制加入前怎样处理

对比基线为 `a3fa935e^`，即 `55bb8079`。

### 3.1 直接删除

旧 `SceneServer.deleteScene`：

1. 取场景关联的、存在设备的 Groups。
2. 对这些组发送组地址 `SceneDelete(scene.number)`；没有这些组时直接删除本地 Scene。
3. 根据响应清设备缓存；成功组删除场景关系，失败组标记 `waitDelete`。
4. 满足成功条件后调用 `network.remove(scene:)`，再调用 `scene.deleteExtension()`。

这条直接路径不检查 Timed / Switch 引用，也不统一改写这些业务对象，不主动发送解除 Switch 场景动作的任务。

### 3.2 Timed

- 旧 `Schedule.sceneNumber` 保存编号，`scene` 通过当前 Scene 列表查找。Scene 被移除后，`scene` 会返回 nil，但保存的编号不会由直接删除路径主动清空。
- 旧 [SyncSceneScheduleTaskBuilder](../SunSmart/Main/Space/Model/SyncSceneScheduleTaskBuilder.swift) 的删除设备分支确实有补偿：对相关设备先删除 `scene.info.bindSchedules` 对应的 Scheduler，再删除 Scene。因此不能说旧版完全没有处理关联定时。
- 该补偿依赖进入待删除设备同步路径；直接删除成功不会自动走一遍此流程。它删除的是设备上的定时配置，也不等于删除 Timed 业务记录。
- 旧版已经有通用 [SpaceSyncCleanupCoordinator](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift)：在同步等清理边界，可清空指向已不存在 Scene 的定时编号，并为已观测到残留定时的设备记录待清理目标。它属于后续修复，不是场景删除前必须完成的统一确认。

### 3.3 Switch

- 旧 [DeviceSwitchData](../SunSmart/Main/Device/Switches/Model/DeviceSwitchData.swift) 的 `sceneANumber` 至 `sceneDNumber` 保存原编号；`sceneA` 至 `sceneD` 按当前 Scene 列表解析。
- 删除 Scene 后，解析出的 Scene 可以变成 nil；场景删除路径没有主动将这些编号置空。
- 动能开关的按键配置通过 `sceneA?.number` 等派生；以后重新同步时配置可能相应变化，但删除 Scene 时没有强制完成这一步。
- 上述通用清理的 Switch 分支处理 Group / Proxy 关系，没有对应的 A / B / C / D Scene 编号清理。
- 所以旧版表现为“可以删除，关联项失去可解析场景”，不能等同于“所有引用和设备动作已经解除”。编号再次出现时，保留的业务编号还可能重新解析到新 Scene。

### 3.4 旧清理顺序还有一个独立缺陷

旧 SDK `MeshNetwork.remove(scene:)` 会断开 `scene.meshNetwork`，而 App 的 `scene.deleteExtension()` 首先要求 `scene.network` 非空。旧调用顺序因此可能直接跳过扩展清理。

已只读核对本机 SDK 映射为 `nordic-sig-mesh-sdk-worktrees/one-dev`，并核对 SDK `ccdf101^` 的旧 `MeshNetwork+Scenes.swift`，断开 network 的行为此前已存在。这里只补充说明旧版不能作为完整清理基准，不将此独立问题扩大成本次实施。

## 4. 建议与验证边界

最小修复方向是区分“引用阻止删除”和“删除已开始但设备清理未完成”：引用阻止时仅显示一次明确原因，留在原页面；只有已准备的删除确实需要设备清理时才进入删除同步恢复。详情和列表必须一起处理，同步完成也不能先报删除成功再检查最终结果。

若产品希望恢复“一次确认直接删除关联场景”，需要另行明确 Timed 保留为空还是删除、Switch 仅解除引用还是改变动作，再设计先持久化解除意图、同步确认、清场景和释放编号的连续流程。单纯去掉 guard 会重新暴露旧引用与编号复用风险。

本次证据来自当前代码、历史提交、原方案及现有测试源码。现有 `SceneDeletionFlowTests` 覆盖“引用存在时不进入物理删除”的服务行为；其 UI 是边界替身，不能覆盖两个真实控制器的弹窗与导航组合。本次未运行测试、构建或真机，未修改 App / SDK / 固件 / 后端代码。

## 5. 级联删除开发方案讨论（2026-11-03 追加）

本节为用户已批准的级联删除方案，取代上一节仅修正提示的最小建议。

### 已确认的产品选择

- 用户希望允许删除有引用的 Scene，自动生成引用清理任务。
- 用户已明确选择：**同时删除直接以该 Scene 为目标的 Timed**，避免留下无目标定时。
- Switch 建议只移除精确匹配该 Scene 的 A/B/C/D 动作，保留开关、组绑定、其他场景动作与长按等无关功能；该建议包含在本轮问题说明中。
- 已改成 Scene 2 或其他目标、仅残留 Scene 1 清理记录的 Timed，必须保留新配置，仅清旧引用。

### 5.1 建议的用户流程

1. 原有删除确认一次性列明影响：删除哪些 Timed、清除哪些开关动作。
2. 确认后先可靠保存整批删除意图。Scene 不再可执行、编辑或被新 Timed / Switch 选择；关联 Timed 进入删除状态，开关目标动作清空。
3. 有连接时复用现有执行器运行清理任务；需要电池开关唤醒时，在同一同步流程中按设备引导激活，不在多个业务页之间往返。
4. 无连接、部分失败、STOP 或离页时保留 `Deletion pending` / `Sync required` 状态及重试入口。不能把“已接受删除请求”报成“设备全部删除完成”，也不能再次显示“仍被引用，先手工修改”。
5. 只有引用清理和设备 Scene 清理全部确认后才最终移除 Scene、删除关联 Timed 业务记录并释放编号。建议清理未完成时保留一条不可执行的待删除 Scene，避免任务不可发现；是否视觉隐藏可另做产品选择，不影响底层保留编号。

### 5.2 必须包含的清理范围

| 条件 | 对哪些目标做什么 | 复用与补齐 |
| --- | --- | --- |
| Timed 当前以被删 Scene 为目标，含已禁用 Timed | 捕获其全部有效/待移除设备 slot 及实际 Scheduler Model；按现有定时删除机制清条目，完成后删 Timed 业务记录 | 复用 `ScheduleServer` 的删除语义、`TimedSchedulerBindings` 的身份/slot/待删除状态；将准备、执行与完成分开以便统一事务，不直接并发调用多个带独立传输的 `deleteSchedule` |
| Timed 已改选其他目标，但 `needDeleteSceneNumbers` 或设备条目仍指向旧 Scene | 对旧目标清理；对仍要保留的同一 slot 更新为新期望值，保留新 Timed | 不能见到同一 slot 就清空，必须核对当前所有者和新期望值；完成后移除旧引用 |
| 已知设备存在仍 Recall 被删编号的 Scheduler 条目，但业务引用已丢失 | 按设备身份、Element/Model、slot 和当前回读值确认旧编号后，清除精确匹配的残留条目 | 不遍历删除所有定时；无法确认 slot 所有权或身份时先读取并保留待处理状态，不假定无任务等于成功 |
| 动能开关 A/B/C/D 精确引用 Scene | 修改按键期望配置，并同步持有旧动作的当前 Proxy；若旧 Proxy 尚待解绑，完成其既有清理或精确清除旧动作 | 复用按键差异生成与 Proxy 同步；不能用 `deleteSwitch: true`，否则会删除整个开关绑定 |
| AC / Battery Power Switch 精确引用 Scene | 更新开关本体 Key Config，对相关 click 写现有 `.disabled` 配置，保留其他按键和设置 | 复用 `PJEightKeySwitchData` 的 desired/applied hash 与版本、现有 Key Config 发送；电池设备保留激活流程 |
| Scene 已下发或仍有待清理残留 | 沿现有 Scene resolver/删除上下文覆盖设备成员、组成员、原地址、待移除身份及可确认的残留；按现有能力判断清相应 Scene Elements | 复用 Scene 删除任务；设备模式也须核对成员之外的已知旧残留，不仅当前 UI 显示成员 |
| 全部设备清理确认 | 事务删除 SceneInfo、组内对应场景配置、相关 Timed 记录，更新设备缓存/同步状态/云数据与列表 | 最终释放必须同时核对新引用、清理依赖和原有 Scene pending，不能只依赖 `pendingOperations.isEmpty` |

固定 Group Profile 的 LC 场景与 EFC `0xFF20/0xFF21/0xFF22` 状态事件号不属于普通 Scene 1，不应顺带删除。删除 Scene 也不需要解绑整个 Group、删除灯、移除所有 Switch 订阅或释放其他场景的配置。

### 5.3 已发现的额外引用边界

`LinkedEmerFireConfig.EmergencyFireControllerActionPreset` 能通过 Codable 保存 `.sceneRecall(SceneNumber)`，并由 trigger action 生成设备配置；当前常规 UI 未找到设置普通 Scene 的入口，默认走 brightness，尚无现场数据证明存在这类引用。

开发时引用扫描应识别此类**精确匹配的自定义 EFC 动作**，不能因为常规 UI 不提供就静默漏掉。若存在，需在删除影响列表中明确提示并确认对该动作的处理；建议清除对应 Recall 动作、保留其余应急配置。不能简单设 `triggerActionPreset = nil`，因为 nil 会回退成亮度动作。具体禁用方式应复用已有 `.invalid` / 同步语义并验证，不能宣称当前已经支持该级联场景。此项为条件范围，未授权改变无关应急行为。

### 5.4 最小完整实现结构

**A. 持久化删除依赖。** 继续由 `SceneConfigurationStore` 拥有删除意图，给当前 Scene 配置增加必要的引用清理依赖。只记录本次所需的 Timed ID、设备身份/Model/slot、Switch ID/相关动作及目标身份、操作代次/确认进度，不保存凭据或完整密钥。Scene 标记、Timed 删除准备、Switch 期望配置、开关元数据和清理依赖应一次事务提交；失败回滚内存与持久化后不发消息。

单靠将 `sceneNumber` 置空不够：业务引用一旦消失，当前 `deletionReferenceNames` 就无法判断仍有哪些 Proxy 或 Power Switch 尚未收到新动作。现有 `ScenePendingOperation` 只有灯端 write/remove 身份，也不能表示开关清理完成；需要有可恢复的依赖证据。

**B. 复用任务与执行器。** 扩展 Scene 同步计划生成：先引用清理，再 Scene 删除，最后本地提交；前置失败时后续删除不得报完成。普通设备同步、删除重试、重启加载也要识别这些依赖，不能只修 Scene 页面。关联设备可能不在 Scene 的灯成员里，应显式加入 Proxy / Power Switch / 历史 Scheduler 目标。

当前 `SyncExecutionSession.batteryPowerSwitchDataForSync` 仅识别 `.batteryPowerSwitch` 类型，并且激活/失败标记/完成状态围绕单个开关维护。把 Key Config 任务直接放入 `.scene` 列表不等于完整复用。建议按具体任务所属开关维护小范围上下文和激活顺序，复用现有单开关流程，兼容一个 Scene 关联多个开关。`SyncSwitchTaskBuilder` 的单 `switchProxy` 展示位也不能反复覆盖，应使用设备行或独立步骤承载多个 Proxy。

**C. UI 统一。** 详情与列表共同接收“未能保存 / 已进入待删除 / 完全完成”的结果，底层不再直接弹引用拒绝框后调用通用 failed。取消确认不改数据；确认后 STOP 仅暂停执行，不撤销已经下发的部分清理。同步完成回调不重复发起一次新的删除，而是收敛同一删除意图。

### 5.5 关键恢复与兼容规则

- 当前 active references 与本删除意图的 pending cleanup 分开判断：自己的待清理引用不能阻断自己的执行，但新建/旧草稿保存出来的引用必须在写入边界拒绝。
- 待删除期间修改关联 Timed / Switch，必须复核当前值、版本和任务所有权；不得用旧任务覆盖新场景动作。失败/迟到回执仅结算相同身份与操作代次，不能污染新配置。
- 当前列表为空、设备离线、Model 缓存未知、设备同地址重加，都不代表清理完成。历史未下发且有可靠证据的合法空项应允许本地完成；不能强制每个空 Scene 都联网。
- 新依赖要随 SQLite、Space/Site 导入导出、分享和云回读保留。现有 `schemaVersion = 1` 对未知字段可忽略，老 App 的最终删除逻辑只检查旧字段；因此不能仅增加可选字段而维持同一版本并声称安全兼容。
- 推荐为新删除依赖使用可识别的新配置版本，新 App 继续读旧格式；旧 App 遇到含新语义的配置应拒绝不兼容编辑/导入，不能漏掉依赖后释放编号。具体最小升级范围在实施前定稿；不默认给所有无变化场景升级。需要确认各客户端发布兼容和服务器完整保留扩展字段，未确认前不声称云端闭环完成。
- 沿用既有可用传输通道；不能把网关接收任务当作设备清理确认。电池唤醒等依赖本地交互的流程沿用其能力限制；不新增固件或服务器能力，不改变其配置。
- 发现身份不明、损坏历史数据时仍可保留删除意图并说明具体待处理项；不能为追求立即消失跳过编号保留和身份保护。

### 5.6 实施顺序、难度与验证

评估为中等偏复杂的跨模块改动。发送 Scene Delete、清 Scheduler、更新按键均已有实现；主要工作是依赖持久化、混合同步中的多开关上下文、失败恢复和格式兼容，不需要新建通用任务框架。

1. 先落删除影响收集、事务准备、引用清理依赖与编解码，补正常/失败/重启恢复行为测试。
2. 接入 Timed、动能 Proxy、AC/Battery Key Config 与 Scene 任务顺序，核对设备/Group/Scene 同步、回执与最终释放入口。
3. 统一两个删除 UI、单次确认与待同步展示；English/简体中文国际化；补真实控制器的结果与导航回归。

必要验证包括：多个 Timed/多个开关引用同一 Scene；开关其他动作保持；Timed 已改选其他 Scene 但有旧残留；禁用引用；无业务对象的已知 Scheduler 残留；空场景；离线/部分失败/STOP/退出重进/进程重启；当前和旧 Proxy；电池开关取消激活；迟到回执、同地址新身份、旧编辑草稿；持久化中途失败；导入导出/云回读保留依赖；删除完成前编号不可复用。EFC 自定义引用若进入实施范围，单独验证其动作变更。

复用 Scene deletion/configuration、Timed slot/delete、Switch 与 Sync 执行器相关现有测试，新增真正覆盖上述风险的用例。Swift 实施结束后按项目要求构建 SunSmart generic iOS Debug；共享资源/工程配置有跨品牌风险时补相应品牌。真实灯、Proxy、AC/Battery 开关验收由用户执行，自动化与构建不替代设备行为。

方案讨论时曾观察到其他 Timed/Group/Restore 修改；实施前已重新核对：分支 `feat/device-scene-261028`，HEAD `fa686441`，工作树干净。这些既有修改已经进入基线，本次保留 Profile Timed 保护。


## 6. 实施结果（2026-11-03）

### 最终行为

- 列表和详情都只显示一次确认，分别列出将删除的 Timed 和将清除动作的设备。确认取消不写数据；已进入删除状态后重试不再重复确认。
- 删除请求在一次 App SQLite 事务中保存 Scene 删除意图、直接引用 Timed 的删除状态、Switch/EFC 期望配置和持久任务。保存失败不发消息、不跳转同步页。
- 有连接则进入一次同步页；离线、STOP、激活取消和失败保留 `Deletion pending`。任务及 Scene 编号在成功确认前一直保留。
- 已改选其他 Scene/设备的 Timed 保留；清理旧 slot 时核对当前 owner、Model 和最新配置，必要时写回它的新期望值。
- 动能开关仅重写受影响按键，保留长按和其他按键；Power Switch 复用 Key Config，按任务激活电池开关。旧 Proxy 或已解除 Group 时仅禁用已捕获的按钮，不把局部成功当作全部 TX/LED 等配置成功。
- 条件性识别自定义 EFC 的精确 `.sceneRecall`，仅把对应 trigger action 改成 `.invalid`；默认亮度、固定 Profile/EFC 状态事件保持原语义。
- Device / Group 同步可恢复同一删除意图。引用清理确认后执行 Scene 删除；所有回执和最终本地事务完成后，才移除 Scene/直接引用 Timed 并释放编号。SDK 已删而 App 最终事务失败时，数据库 tombstone 仍保护 Scene 编号和关联 Timed ID。

### 清理顺序与恢复边界

1. 对所有已知 Scene 成员、旧清理对象、已观察到的残留设备及关联 Timed 绑定，逐个 Scheduler Setup Model 回读 16 个 slot。
2. 按回读值清理精确旧编号及直接删除 Timed 所属 slot；对合法新 owner 写入其当前期望值。按当前/旧 Proxy、Power 本体、EFC 绑定身份清理动作。
3. 引用依赖全部确认后，复用现有 Scene 删除上下文清理灯端寄存器。
4. 事务删除 Scene 扩展记录、组内对应场景配置及直接引用 Timed；保留改选后的 Timed 并移除其旧 Scene 清理记录。

任务检查 Space、设备 UUID/地址/Key fingerprint、Scene revision 与当前业务配置（同时核对持久记录与内存对象）；SDK 普通重加同地址不会继承清理身份，只有现有显式 Restore receipt 可以迁移引用身份。配置改变、旧回执、部分 ACK、数据库失败均不能清掉依赖。重试先重新回读，避免使用上轮旧命令。普通设备/组任务排除已被专用删除计划接管的 SceneDelete，避免消费同一回执两次。

旧 Switch/Group Switch 编辑入口和监测页现在必须保存成功才能更新 manager；单开关/Timed 同步准备、激活后的发送前以及 Power Add/Restore 共享命令生成均检查 Scene 引用。持久化导入边界与 live 下发边界分开，避免正常导入的保存顺序被过早拦截。

身份缺失、未知旧 Proxy 按键配置等不能被空消息误判为完成，会保留 pending；这类历史异常需恢复原设备或完成现有明确的设备移除/Restore 流程。不能仅因设备离线或列表暂时为空就释放编号。

### 格式与外部依赖

新删除意图使用 `SceneConfiguration.schemaVersion = 2`；普通场景仍为 v1，新客户端兼容 v1。v2 必须带完整删除依赖，解码校验身份、地址、slot、按键范围与重复项。旧客户端会拒绝它不认识的版本，避免忽略依赖后提前删除。

此次只修改 App；本地 SDK 来源为 `one-dev`，revision `dbcf6f1`，无 SDK 修改。不需要新增固件或服务器接口。云端仍须完整保留 Scene 扩展字段；本次离线编解码/SQLite 测试不能证明实际服务端、混用旧客户端或分享链路已经验收。

### 自动化验证

- Scene 原有 10 个 suite、删除生命周期（真实 Store/SQLite、SDK 边界替身）通过；旧“有引用必拒删”断言已由级联行为用例替代。
- 新 cascade suite 84 项通过，模型 suite 28 项通过。cascade 编译整份真实 `SceneDeletionCascade` 与 codec，SDK/存储使用受控替身，覆盖准备回滚、精确消息、新 owner、Power/EFC、失败/重试、迟到回执、未知身份、成员外残留及最终清理。
- 两个真实控制器的删除/同步收尾方法回归通过，覆盖一次确认、离线、不重复提交、失败不自动跳转及 pending 重试；UIKit/导航/服务为替身，不能代表真机布局验收。
- 引用准入 29 项通过，覆盖 Switch/Group/Monitor 保存失败、待删除或已不存在的 Scene、Timed 待删除 ID、Power Add/Restore 下发阻断。
- Sync 执行器与任务构建回归通过，包含多开关激活、取消、迟到回调、空消息和重试前置顺序。
- Timed delete-result、device-slots 回归通过；`git diff --check` 通过。
- SunSmart、Archipelago、SylSmart、SLG Sync Plus、Lumineux、HSmart 六个 scheme 的 generic iOS Debug 构建通过；最终变更后已串行完成增量复核。使用 `SunSmartLocal.xcworkspace`，禁用签名，未使用 Simulator 或真机。构建仍有项目既有资源重复/废弃 API 等警告，本次未扩大处理范围。

### 最短人工验收

1. Scene 1 关联两个 Timed（含禁用项）、一个动能开关和一个 AC/Battery 开关；另一按键绑定 Scene 2。删除 Scene 1，确认只出现一次，并列明影响。
2. 同步成功后确认 Scene 1 和直接引用 Timed 消失；原按键不再召回 Scene 1，Scene 2 按键和长按仍工作。
3. 让一个 Proxy/开关离线或取消激活，再退出/重启：保留待删除状态及任务；重新联网重试后完成。清理结束前不能复用原 Scene 编号。
4. 将某个 Timed 先改成 Scene 2、留有 Scene 1 旧设备配置，再删 Scene 1：该 Timed 保留且最终执行 Scene 2。
5. 上传/下载或分享包含待删除任务的数据，确认 pending 依赖完整保留；旧版本客户端拒绝不支持的配置。条件性 EFC 自定义场景动作另做设备验收。

未自动连接或操作真机；无线命令效果、最终 UI 体验、实际云回读及新旧客户端混用仍待人工/联调验收。当前修改未提交。


## 7. 真机仍然删除失败：身份大小写不一致（2026-11-03）

### 结论与本轮边界

分析阶段基线：`feat/device-scene-261028`，HEAD `27c6c930`（之前为级联删除提交 `1f25188b`）；开始分析时工作树干净。当时没有修改业务代码或 SDK，没有运行 App 构建；先在临时目录用真实指纹算法、Scene codec 和级联生产代码复现缺陷，并验证临时候选比较方式。用户随后要求修复，落地结果见第 8 节。

**Scene 删除依赖在持久化时规范为大写身份，新增级联任务却用运行时原始小写指纹做字符串精确比较。结果是 pending 仍在、可执行引用清理任务为零，Scene Delete 又被 pending 保护阻止，从而立即失败。** 这是首轮实现遗漏，和用户日志的执行形态一致。提供的响应截断了 Scene 配置本体，未能逐字段独立检查现场 Scene 28 的所有依赖；不把这份截断日志当作完整设备/云数据样本。

### 日志证据

- `scene=28 stage=taskSelected address=14`：选中 Scene 28 的任务，地址打印为十进制 14，即 `0x000E`。
- 紧接着 `commandsBuilt count=0`、`taskRejected reason=emptySceneHandles`、`noNextTask`、`syncFailure`。这轮没有到达 `submitCommands`，因此不是 Scene Delete 已发出后设备拒绝/超时。
- 随后 HTTP 上传、回读 `confirmed` 只证明配置上传/比较完成；回读中的 Group Scene 28 仍为 `state=2`，SDK 定义为 `waitDelete`，仍是待删除状态。
- 末尾 `proximityLightingTrigger` 是来自 `0x0014` 的另一条主动业务消息，回复为 GenericOnOffStatus。其 Local Vendor Model 绑定提示出现在删除失败之后，不能解释前面生成零条命令。
- `failedModels=2` 统计包含组、设备、步骤、任务等 UI 层级，不等于两台物理设备删除失败。没有引用步骤时，同一失败设备及其所属组就能占两项。
- `startRequested` 与后续执行 run ID 不同，是 start 创建新轮次的现有行为，不足以证明并发或串台。

### 代码完整因果链

1. `SchedulerModelSnapshot.keyFingerprint` 在 `SpaceConfigurationIntegrityPolicy.swift` 中使用 `%02x` 输出小写 SHA256 字符串；`Node.timedSchedulerIdentity` 保留这个格式，供已有 Timed slot 绑定使用。
2. `SceneConfiguration.identity` 则将 UUID、地址、指纹全部转成大写。`normalized()` 会把 `deletionReferences.pending.identity` 也规范化；`prepareDeletion` 在保存之前就调用了它，因此首次删除即可触发，不需要等云导入或重启。
3. `SceneDeletionCascade.appendTasks` 以原始 `node.timedSchedulerIdentity == reference.identity` 查找节点，小写和大写不相等，直接 `continue`。依赖并没有被删除，但执行计划缺失了引用清理设备行。
4. 普通 Scene 目标解析使用已有 `sceneConfigurationIdentity`，能正确找到相同节点。因此灯端 SceneDelete 任务仍会被创建；因为上一步引用任务为空，也没有可关联的前置 step。
5. `Scene.getDeleteMessageHandles` 第一行检查 `!SceneDeletionCascade.hasPending(info)`。pending 没有被执行清掉，这里静默返回空数组，执行器按 `emptySceneHandles` 拒绝。这与本次日志中缺少 `deleteReservationOrContext` 诊断吻合。

同一遗漏还存在于 `SceneDeletionTask.isCurrent`、`invalidateIncompleteSchedulerRead`，以及 `SceneConfigurationStore.prepareDeletion` 的 `cleanupNodes` 收集。最后一处会漏掉成员外已知残留设备的额外 Scheduler 回读范围；不能只改 UI 或删除一个保护条件。

### 临时复现结果

使用虚构输入生成指纹，不使用、不输出用户 Mesh 密钥。执行当前完整 `SceneDeletionCascade.swift` 和真实 `SceneConfiguration.swift`；Node、存储及 Sync 展示结构沿用现有测试替身。

| 临时运行版本 | pending | 清理设备行 / 步骤 | 任务身份校验 | 一个 Scheduler Model 的回读命令 |
| --- | --- | --- | --- | --- |
| 当前生产代码 | 保留 | 0 / 0 | false | 0 |
| 只规范任务查找的临时候选 | 保留 | 1 / 2 | false | 0 |
| 查找及任务身份比较统一规范的临时候选 | 保留 | 1 / 2 | true | 16 |

三组都分别验证了首次 normalized 之后和 encode/decode 重载之后，结果一致。没有执行无线发送或完整 App 删除收尾。

### 为什么首轮测试没有发现

`SceneDeletionCascadeTestSupport.Node` 默认指纹为大写重复 `A`；引用与运行时身份天然相同。同时实际 Store suite 与 cascade suite 各自隔离：前者使用无引用边界替身，后者的 `markDeleting` 没有像真实 `prepareDeletion` 那样先把内存 configuration 替换成 normalized 结果。已有模型测试验证了大小写规范化，但没有将该结果接到真实引用任务生成和身份守卫。因此首轮测试通过没有覆盖这条跨模块路径。

### 建议修复范围

- Scene 侧引用创建/聚合、节点查找、当前任务校验、取消/失败时回读缓存失效，以及额外 cleanupNodes 收集，统一复用已有 `node.sceneConfigurationIdentity` / `SceneConfiguration.identity`。
- 保留共享 `timedSchedulerIdentity` 和现有 Timed slot 数据的原格式，不全局把 fingerprint 改成大写；UUID、地址、指纹三个字段仍需完整匹配，不降级为只比较地址。
- 保留“引用未清理不得发送最终 SceneDelete/释放编号”的保护。现有正常 pending 记录本身不需要丢弃或重新建 Scene，修复后重新进入同步页重建计划即可尝试恢复；同时核对旧删除意图是否缺少成员外 Scheduler 依赖，不能用空任务直接补成成功。
- 在静默跳过引用和生成空删除命令处补少量 DEBUG 原因与计数，例如 pending 数量、身份是否可解析、Scene Setup Model 是否存在；不打印密钥或完整指纹。
- 必要回归：实际小写指纹 → 真实 normalized 保存 → 引用任务生成 → 回读/解除 → SceneDelete；SQLite 重载后相同链路；仅修 lookup 仍不够的守卫场景；同地址换 Key/换 UUID 仍拒绝；部分回读失败的缓存失效；只选组重试时不漏所需前置任务。

以上为实施前的根因分析和修复范围。不得删除 pending 检查或清空数据库来绕过此问题。

## 8. 身份匹配、存量任务恢复与失败重试修复（2026-11-03）

本轮修改基于 `27c6c930`，已落入当前工作树，未提交；只修改 App 共享逻辑、相关回归与本文档。本地 SDK 仍为 `one-dev` / `dbcf6f1`，无 SDK 改动，无固件或服务器接口变更。

### 行为变化

- Scheduler、动能开关、Power Switch、EFC 的引用创建、聚合、查找、执行校验和回读失败缓存失效，统一使用已有 Scene 规范身份。保留 Timed slot 原始身份格式；仍完整比较 UUID、地址与 Key 指纹。
- 对旧版已经保存的 v2 待删除记录，在重入同步准备或 Space 恢复时，补齐仍有物理 Scene 删除任务的设备所缺失的 Scheduler 回读依赖。补任务先事务落库再更新 live Scene；失败回滚，忙碌时不改计划。保留 Scene revision、已有任务 generation 和引用 ID，不变更存储 schema。
- 只补仍有物理删除 pending、且当前节点完整身份一致的对象。物理删除已确认后不重新创建依赖；相同地址但 UUID/Key 改变的设备不继承旧任务。若引用清理已成功但物理删除尚未完成，重新进入时允许保守回读一次，不能将缺失记录直接判为成功。
- 引用清理失败时，其阻塞的 SceneDelete 显示为失败，可从灯所在组选择重试；只选组、步骤或 SceneDelete 任务，也会恢复所需的外部引用前置任务，按“重新回读 → 清理 → SceneDelete”继续。已完成的引用和无关失败任务不随之重跑。
- 引用未确认时仍不发送最终 SceneDelete、不释放编号。为找不到引用节点、缺少 Scene Setup Model、引用 pending 阻挡命令补充 DEBUG 原因日志，不记录密钥或完整指纹。

### 验证结果与边界

- 新增真实指纹算法 → Scene normalized → 编解码重载 → 任务创建/执行/回执链路。原级联代码运行同一回归为 **134 通过、21 失败**；修复后 cascade suite 为 **165 通过、0 失败**。包含四类引用、部分回读失败/取消/重试缓存失效、换 UUID/Key 拒绝、Timed 原始身份保留、存量补任务幂等及 Store 失败回滚。
- `check_scene_deletion_flow.py` 通过：真实 Store/SQLite 的既有删除生命周期、离线重载、残留对象、迟到/失败 ACK、取消、事务回滚与 SDK/App 中断恢复。该套件明确隔离引用清理；新增 cascade 套件执行真实级联与 Store 补任务方法，但存储/SDK/UI 为替身，不能替代无线验收。
- `check_sync_execution_session.py`、`check_sync_task_builders.py` 通过。新增六个实际 Session 调度场景（回读/清理失败 × 组/步骤/任务重试），验证前置顺序和无关任务隔离。
- `check_timed_device_slots.py`、`git diff --check` 通过。
- `SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iOS / 禁用签名构建通过。生产修改为各品牌共用且无条件分支的逻辑，无资源、target 或 SDK 依赖改动，本轮选 SunSmart 代表编译。仍有项目既有捕获语义等 warning；未运行 Simulator、真机或实际云回读。

### 最短现场复测

1. 使用本轮新构建，退出当前同步页，再进入已有待删除 Scene 的同步页面。无需重建 Scene、清库或改编号。应生成对应引用清理任务，先完成它们，再执行 SceneDelete。
2. 使一个引用设备离线导致失败，再恢复在线；只选择灯所在组重试，确认外部引用任务也被恢复，成功后 Scene 与直接引用它的 Timed 被删除，其他开关动作保留。
3. 同步中断后退出重进，确认继续待删除任务；所有确认完成前不能复用原编号。若仍失败，保留新增 SceneSync 原因及任务阶段日志定位。

真实设备命令效果、页面体验及实际云端往返仍待人工验收，不由本轮编译和隔离回归替代。

## 9. 单设备关联 Timed 的删除耗时与命令精简分析（2026-11-03）

分析输入：`/Users/maginawin/Desktop/remove scnee in timed.txt`。本节只分析并规划，没有修改 App/SDK 代码、运行构建或操作设备。当前 App HEAD 为 `fa78db90`；分析开始时看到的上一轮暂存修改已包含在该提交中，本轮未执行提交。`SunSmartLocal.xcworkspace` 的 SDK 实际映射为 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `dbcf6f1`，SDK 工作树干净。

### 9.1 结论与精确统计

**Scene 31 本次删除共提交 35 条业务命令，加上 5 次重发，日志记录了 40 次 Access/Network 发送。主要额外开销是对两个 Scheduler Element 的全部 16 个槽逐个读取；建议改为占用位图查询后按需读取。按本次返回状态，正常无重发时预计为 6 条命令，比 35 条减少 29 条，约 83%。**

统计分别使用 `send message:`、`Sending Access PDU`、`Resending Access PDU` 与 `Sending Network PDU` 交叉核对；同一命令的不同协议层日志不重复计数。40 次是此日志可见的 App/SDK 发送，不是包含设备回复、Mesh Relay 或无线底层重传的完整空口抓包统计。

| 执行顺序 | 目的地址 | 命令及参数 | 初次发送 | 重发 |
| --- | --- | --- | ---: | ---: |
| 1 | `0x000E`（十进制 14） | `SchedulerActionGet(index: 0...15)`，opcode `0x8248` | 16 | 4 |
| 2 | `0x0010`（十进制 16） | `SchedulerActionGet(index: 0...15)`，opcode `0x8248` | 16 | 1 |
| 3 | `0x000E` | `SchedulerActionSet(index: 0, action: noAction, sceneNumber: 0)`，opcode `0x60` | 1 | 0 |
| 4 | `0x000E` | `SceneDelete(scene: 31)`，opcode `0x829E` | 1 | 0 |
| 5 | `0x0010` | `SceneDelete(scene: 31)`，opcode `0x829E` | 1 | 0 |
| 合计 | | | **35** | **5** |

- 重发分别为 `0x000E` 的 index 1、5、11、13，以及 `0x0010` 的 index 8；不是又执行了一遍删除业务。
- 三批发送数依次为 `32 → 1 → 2`，对应读取、清理定时、删除场景；三批均有成功回执，末尾为 `finished state=syncSuccess failedModels=0`。
- 32 次读取中，仅 `0x000E / index 0` 返回完整有效条目，执行 `sceneRecall(31)`；其余 31 次返回仅含 index 的短状态。
- 两条 Scene Delete 均返回 Success。`0x000E` 返回空 Scene Register；`0x0010` 保留 `FF00/FF01/FF02`，不含 31。该日志支持本次命令完成，不证明之后定时触发、编号复用或云端往返均已验收。
- `install devices=2` 是计划中的两行任务：引用清理行和 Scene 删除行，二者 `address=14`；不能解释为两个物理设备。发送到 14 和 16 的操作分别落在该节点的两个 Element。

### 9.2 为什么一个设备仍然慢

[SceneDeletionCascade](../SunSmart/Main/Scene/Model/SceneDeletionCascade.swift) 的 `.read` 阶段固定遍历 `node.schedulerSetupModels × (0..<16)`。虽然准备删除时已保存关联 Timed 的 `reference.slots`，当前读取阶段没有利用槽位或设备占用信息缩小范围；已知缓存为空也仍会执行全槽读取。相关测试还明确要求双 Model 生成 32 条 Action Get，因此这是既有策略，不是本次任务意外重复。

这项保守策略用于发现旧场景残留：Scene 当前/历史成员、成员之外的已知残留节点，以及关联 Timed 的绑定都可能包含需要清理的 Scheduler。只按当前 Timed 的 index 盲清一个槽，会遗漏业务记录已经改变或丢失的旧 Recall，因此应优化查询方式，保留必要的目标覆盖。

SDK 的 `MeshProxyMessageCommand` 在收到匹配回包后才推进下一条，失败时还需等待超时；本次 32 次往返占 35 条初始命令的约 91%。日志没有逐条时间戳，不能计算删除总耗时或把 5 次重发准确换算成秒。导出计时约为毫秒级，现有证据不足以认定云请求是本次主要瓶颈。

两个 Scene Delete 地址不同，属于当前整场景删除对所有 Scene Setup Server Element 的覆盖，不是同地址重复。单凭删除后的 Register 不能证明 `0x0010` 在删除前一定不含 31。首轮保留这两条；额外查询 Register 再省一次 Delete 通常不减少往返。

### 9.3 推荐命令流程：本例预计 6 条

Bluetooth Mesh Model 规范 §5.2.3.2 / §5.3.5.2.2 规定，Scheduler Status 的位图表示哪些槽存在定义；§5.3.5.2.4 允许未定义槽的 Action Status 省略条目，仅返回补齐的 index。依据：[Bluetooth SIG Mesh Model 1.1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。

1. 对本次清理节点中每个包含 Scheduler Setup Server（`0x1207`）的 Element，向其单播地址发送 `SchedulerGet`（`0x8249`），接收 `SchedulerStatus`（`0x824A`）。本例两条，目标 `0x000E`、`0x0010`。
2. 仅对各 Element 回包位图中为 1 的槽，向同一 Element 发送 `SchedulerActionGet(index)`。若位图均为 0，跳过本节。本例预计只有 `0x000E / index 0`，一条。
3. 所有位图及所列条目读取成功后，复用现有所有权判断：清理被删 Scene 或捕获的待删槽；若槽已归属其他有效 Timed，恢复当前 owner 应有配置，保留该 Timed。所有写操作继续使用带 ACK 的 `SchedulerActionSet`。本例一条，把 `0x000E / index 0` 设为 `noAction`。
4. 引用清理回执完成后，对所有应清理的 Scene Setup Server Element 发送带 ACK 的 `SceneDelete(31)`。本例两条。
5. 所有依赖及 Scene 删除成功后，再完成本地 Timed/Scene 清理与编号释放，沿用现有持久化和同步流程。

本例合计 `2 + 1 + 1 + 2 = 6`。这是基于现有 Action Status 推导的目标值；原日志没有 Scheduler Get，仍需现场确认该设备两个 Element 的位图分别正确返回 `0x0001`、`0x0000`。实际存在更多定时时，需要读取所有占用槽来确认是否残留被删编号，数量按实际占用增加；两个 Model 全满时，查询为 34 条，位图策略主要改善稀疏配置。

### 9.4 复用方式与关联影响

SDK 的 `MeshScheduleServer.getSchedule(index: nil)` 已实现“每 Model 读位图 → 为该 Model 追加占用槽详情”的机制，`ScheduleServer` 和 `SpaceSchedulerReadCoordinator` 已使用它。Scene 删除目前另走固定全槽任务，没有复用这个策略。

建议最小 App 改动是在既有 `SceneDeletionTask` 和 `SyncExecutionSession` 内拆分“位图 → 详情 → 清理”依赖阶段，通过现有成功回调收集本轮各 Element 的位图与条目；继续走同一串行发送通道。不要从已在运行的 Scene batch 直接启动另一个顶层 `MeshAPI.getSchedule` 调用：它也操作共享队列和 batch 回调，需要保留本轮任务归属、完成条件及 STOP 语义。

需要同时满足：

- 只有位图及位图要求的详情全部成功，才能建立完整、可信的本轮 Model 快照。不能仅凭 `allSchedulerModelEntrys[model] != nil` 判断完成；SDK 收到部分状态时就可能创建这个字典。
- 位图为 0 是合法空配置，应允许零条详情读取并继续；位图缺失、解析失败或任一详情读取失败仍保留 pending，阻止最终 Scene 删除。
- 取消、断连、重试及迟到回包不能把部分读取变成完整缓存；重新读取时清除本轮旧位图，保留既有身份、revision、所有权检查。写失败后的重试仍从新读取开始。
- 默认不复用跨会话旧缓存免读。重新进入或重启后沿用现有待删除意图重新查询，无需为本次性能优化改变存储 schema；不新增固件/服务器接口。
- 修改共享任务后，Scene 详情/列表、无界面删除入口、设备/Group 同步及恢复重试都受益。同步选择重试与依赖传播必须覆盖新增读取阶段，开关/EFC 清理语义保持现状。

不建议本轮仅按已知 index 直接发送“一条禁用 + 两条删除”：其命令虽少，但缺少未知残留和当前 owner 的确认。先完成 6 条方案即可去掉本次绝大多数额外往返，后续确有更高性能需求再设计可信缓存免读条件。

### 9.5 关联缺陷：空槽响应解析与 continuation

日志中有 **31 条 `UnknownMessage(opCode: 0x00005F, parameters: 单字节 index)`，以及 31 次 `SWIFT TASK CONTINUATION MISUSE`**。这些短响应符合上述未定义槽协议；本地 SDK 的 `SchedulerActionStatus.init(parameters:)` 只接受 10 字节，因而不能解析该合法空槽状态。

代码还解释了“上层继续成功、下层却告警”的可能路径：`MeshMessageHandle.matchesResponse` 对 Scheduler 当前只比较 opcode/来源等通用条件，因此 UnknownMessage 仍能让 batch 记为成功并推进；`NetworkManager.notifyAbout` 的单次请求回调只接收类型化 `MeshResponse`，短响应未走该分支，后续同地址请求可能覆盖尚未恢复的 continuation。这与日志告警时机和数量吻合，但没有另做异步竞态复现，不能将全部耗时归因于该路径。

这是需单独跟踪的 SDK 兼容缺陷；位图读取会避开稳定空槽的 31 次请求，但不能宣称已修复 SDK。若本轮后续授权包含 SDK 关联修复，应覆盖短/完整状态解析、空槽缓存清除、index 与 Element 的精确匹配，以及正常/取消/迟到回包只完成一次。SDK 有改动时需记录 revision 和正式依赖发布待办。App 的命令精简可独立实施。

### 9.6 验证边界

本轮已核对日志计数、实际 App/SDK 调用链及权威协议；没有运行修改后的自动化或真机测试，因为尚未实施。

后续必要验证：

- 用两个 Scheduler Model、一个有效槽的行为夹具验证完整序列确为 6 条；双空位图允许继续；多占用槽、成员外残留及其他 Timed owner 配置保留。
- 验证位图失败、详情失败、写失败、STOP、迟到回复、同地址换身份、只选 Group 重试、退出重进与持久化失败时，均不提前释放删除依赖或 Scene 编号。
- 使用既有 Scene cascade / deletion flow、Sync execution / task builder 及 Timed slot 回归，新增断言针对实际回包驱动的命令序列；不再把固定 32 条读取视为正确性要求。生产代码完成后按项目规则构建 SunSmart Debug generic iOS 一次。
- 人工在相同设备、相同关联 Timed、相同连接条件下前后对比：记录开始/结束时间、初始命令数和重发数，确认两个位图正确、删除完成、其他定时保留。性能验收以实际耗时为准，命令数减少 83% 不等于耗时一定减少 83%。

## 10. 命令精简与空槽短响应修复结果（2026-11-03）

用户已批准按第 9 节推荐流程优化和修复。本轮基于 App `fa78db90`、本地 SDK `one-dev / dbcf6f1`，修改均未提交；正式工程的远端依赖声明未改变，无固件、服务器或配置部署变更。

### 最终行为

- Scene Scheduler 清理改为每 Element 一条 `SchedulerGet`，只对位图中占用的槽读取详情。仍使用原来的“读取 → 清理”两个任务步骤；读取步骤在同一 Session 内发送位图和详情两个串行批次，位图成功不会提前完成任务或解除删除依赖。
- 本轮单独收集各 Model 的位图和条目，以实际类型化回包为依据；缺失位图/详情、错误 index、旧批次回调或 revision 变化均不能认可完整读取。全部完成后建立本轮缓存，包含权威空 Model，避免直接使用之前缓存推定无残留。
- 双空位图不生成 Action Get；占用槽在详情读取时变空也可正确继续。取消、失败和重试沿用既有未知缓存恢复，重试从新位图开始。Scene 删除、开关/EFC 依赖、持久删除意图及编号释放规则保持现有机制。
- SDK 支持合法的 1 字节 `SchedulerActionStatus`，保留其短编码，映射为空条目以复用现有缓存清除；原 10 字节完整状态兼容。该短响应现在是正式 `MeshResponse`，可以完成原来等待的请求 continuation。
- Scheduler 单播回执必须来自实际目标 Element，不能把另一个 Element 的来源替换成 Primary 地址；Action Get 校验 index，Action Set 校验 index 和完整回显参数。其他消息既有 Primary fallback 行为未改。

对日志对应的两个 Scheduler Element、一个有效槽、两个 Scene Setup Element，目标发送序列为 **2 条位图 → 1 条详情 → 1 条定时清除 → 2 条 Scene Delete，共 6 条初始命令**。若有更多占用槽或无线重发，实际条数随之增加。

### 验证结果

| 范围 | 结果与证据边界 |
| --- | --- |
| `check_scene_deletion_cascade.py` | **204 通过、0 失败**。执行生产级联代码，新增位图/详情回包驱动覆盖：双空、单槽、缺回包、错误 index、槽变空、STOP/迟到、重试、配置变化；保留原所有权与身份回归。SDK/存储边界使用替身。 |
| `check_sync_execution_session.py` | 通过。生产 Session 和生产回执分支验证位图后继续详情、详情完成后才结束任务，以及详情失败、STOP、重复完成、失效回调；原组/步骤/任务重试和恢复回归通过。 |
| SDK `scripts/check_scheduler_readback.py` | **35 通过、0 失败**。运行生产 codec、Scheduler 回执匹配/路由、缓存更新及 NetworkManager 收包/取消方法；覆盖全部 16 个短状态、畸形长度/填充、现场完整状态、错误 Element/index/旧 Set 值、空缓存和 checked continuation 正常/取消各完成一次。无线及其他无关消息分支为边界替身。 |
| 同一 SDK 测试替换为旧 codec | **7 通过、16 失败**，16 个合法空槽短状态均不能解析，证明新增回归能发现原缺陷。 |
| `check_scene_deletion_flow.py` | 通过。真实 SQLite/生产删除生命周期，含持久化失败、退出重进、离线/重启、残留对象、迟到/失败 ACK、多 Element 回执及 SDK/App 收尾中断；引用级联由上述专项覆盖。 |
| `check_sync_task_builders.py`、`check_timed_device_slots.py` | 通过。覆盖共享计划、重试依赖、Timed slot 所有权、旧数据和待删除绑定。 |
| App / SDK `git diff --check` | 通过。 |
| App 构建 | `SunSmartLocal.xcworkspace` / SunSmart / Debug / `iphoneos27.1` / generic iOS / 禁用签名，**BUILD SUCCEEDED**。DerivedData 使用 `SunSmart-feat-device-scene-261028-cli`。 |

构建使用上述本地 SDK 未提交差异。改动为各品牌共用的逻辑和内部 SDK 实现，无新公开 API、品牌条件、资源或 target 变更，本轮选择 SunSmart 代表编译；没有运行 Simulator 或真机。日志已有 capture/metadata 等 warning，不作为本次命令效果证据。

### SDK 发布依赖与最短人工验收

SDK 未提交差异位于 `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshProxyMessageCommand.swift`、`Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Messages/Time and Scenes/SchedulerActionStatus.swift`；另新增 `Tests/Standalone/SchedulerReadbackBoundaries.swift`、`Tests/Standalone/SchedulerReadbackTests.swift` 与 `scripts/check_scheduler_readback.py`。

正式 App 发布前需将这套 SDK 修复提交、验证并发布到正式依赖的 `release` 分支，再记录实际 revision；目前不能把本地构建通过表述为远端 SDK 已具备修复。本轮没有执行提交、推送或发布。

人工用当前本地 workspace 构建在原设备上删除同类 Scene：检查批次为 `2 → 1 → 1 → 2`、末尾同步成功，31 次空槽 UnknownMessage/continuation 告警不再出现；确认关联 Timed 消失，其他定时不变。再验证一次读取中断后退出重进能继续完成。记录前后总耗时及重发数；真实耗时改善、无线效果、最终 UI 和云端往返仍待人工验收。
