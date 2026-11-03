# Scene 删除引用限制与重复提示分析

日期：2026-11-03。分析基线：`feat/device-scene-261028`，HEAD `b1bab004`；开始分析时工作树无未提交修改。第 1～4 节保留当时分析快照；用户已于本日批准按第 5 节方案实施，第 6 节记录最终实现与验证。

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
