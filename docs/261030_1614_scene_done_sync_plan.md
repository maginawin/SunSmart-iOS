# Scene DONE 统一进入同步页面：待确认方案

日期：2026-10-30。App 实施及相关自动化验证已完成；独立审查已完成，发现项已补回归修复；真实 UI/实灯待人工验收。

用户已确认优化方案，并在历史行为核对后条件确认命令链；本次保留原有不额外发送 TimeSet 的行为。

## 实施前确认：单台设备加入/移出场景的命令

以下是当前 App 及本地 SDK 的代码行为，拟复用；不是固件实测结论。加入/移出指场景成员变化，不是配网、退组或 Node Reset。以下命令均为有响应单播，目的地址为对应 Model 所在 Element 的单播地址，不是组地址，也不保证都是 Primary Element。

### 加入或更新场景

1. 目标 Scene Register 未知时，向 node.sceneSetupModel 所在 Element 发 SceneRegisterGet；读取失败或容量不允许则不继续 Store。该读取可能已经由保存前预检完成。
2. 按参数及能力选择一条设置命令：OFF → GenericOnOffSet(false)；ON 且支持有效 CTL → LightCTLSet(lightness=目标亮度, temperature=裁剪后的 Kelvin, deltaUV=0, transitionTime=immediate, delay=0)；否则支持亮度 → LightLightnessSet(lightness=目标亮度, transitionTime=immediate, delay=0)；否则 → GenericOnOffSet(true)。发送给 node.onoffModel/ctlModel/lightnessModel 对应 Element。亮度是既有换算/trim 后的 Mesh 值。
3. 参数命令成功后，向 node.sceneSetupModel（Scene Setup Server 0x1204）所在 Element 发 SceneStore(scene=当前场景号)。参数失败不发 Store。当前普通场景加入只使用 SDK 按 Element 顺序找到的首个 Scene Setup Server，不遍历所有 Elements，也不额外调用 SceneRecall。
4. 若有需同步的绑定日程，每条日程使用设备分配的 slot（0…15）：先对所有非 Owner Scheduler Setup Server 的同 slot 发 SchedulerActionSet(empty entry)，再向 Owner 发 SchedulerActionSet(slot, 日程 entry)。entry 来自当前日程的启用状态、时间、星期、动作、渐变和场景号，不写固定示例值。场景任务失败则后续依赖日程不执行。

### 从场景移除

1. 没有绑定日程则跳过本步。对每条绑定日程的设备 slot，遍历设备所有 Scheduler Setup Server（0x1207，包括 Primary Element 上存在的该 Model），逐一单播 SchedulerActionSet(slot, empty entry)。empty entry 的 action=noAction、month=0、dayOfWeek=0、sceneNumber=0、transitionTime=unknown，其余日期时间字段为 any。只清本日程 slot，不清全部槽位。
2. 日程清理成功后，向 node.sceneSetupModel 所在 Element 发 SceneDelete(scene=当前场景号)。无绑定日程时直接执行。不会为移除发送 OFF，也不改变 Group 订阅。
3. 本需求是移除成员，仅删除普通场景目标 Model。当前“删除整个 Scene”另有 isDeleting 分支，会遍历所有含 Scene Setup Server 的 Elements；本次不混用该分支。

### 附加读取与限制

- 保存前 Scheduler 拓扑未知且影响槽位分配时，现有预检可发送 SchedulerGet，并按状态读取 SchedulerActionGet；这些是读取，不是加入场景固定追加的写命令。
- 当前 .scene 专用任务构建器没有加入 TimeSet；不能把 .devices 同步中的一次校时行为算进本场景链路。若要求场景关联日程同步时也校时，需要另行明确纳入本次范围。
- 不发 ConfigModelSubscriptionAdd/Delete、ConfigAppKeyAdd 或 ConfigNodeReset。失败保留 pending，重试可能重发对应命令；不以发送完成替代成功回执。

源码依据：Node+MessageHandles.swift 的 Scene/Schedule 扩展、SceneCommandBuilder.parameterHandles、SyncSceneScheduleTaskBuilder、SyncExecutionSession.send、SceneCapacity.readUnknownState；本地 SDK MeshMessageHandle.targetAddress 与 Node+SupportModels。

## 目标与建议

Create scene 选择 Groups 后的 DONE，以及已有 Scene → Settings 的 DONE，统一为：冻结本次编辑 → 校验并保存配置和 pending → 进入 Sync device(s) → 自动执行本场景完整同步任务。去掉保存路径上的“发送确认”和“发送结果后确认保存”，Preview 仍独立试灯。

建议直接复用现有 SceneConfigurationStore、SyncDevicesViewController(.scene)、SyncSceneScheduleTaskBuilder 和 SyncExecutionSession。另一种做法是在 Sync 页面内搬入现有“预发送—确认—保存—正式发送”两阶段流程，但会重复发送参数、增加页面状态与取消边界，不推荐。用户尚未确认推荐方案。

## 已证实的原因与关联入口

- SceneAddViewController 自定义创建先 createEmpty，再进入 SceneSettingsViewController(mode: .members)；模板创建也进入同一编辑器，自动保存通过 beginSaveOnAppearance 调用 DONE。
- SceneSettingsViewController.doneAction 对非空目标弹 scene_send；startSend(.beforeSave) 只发送参数；received 再弹 scene_confirm_save；confirm 才落盘并在后台 startFormal。当前不是缺少场景同步能力，而是保存流程仍绑定试灯确认。
- SceneSaveCoordinator 仅该编辑器使用；它同时负责 Preview、确认快照和后台正式同步，需要拆开保存入口与预览，不能只删弹窗调用后直接绕过校验。
- Store.commit 已写入全部当前目标的 write pending，并合并旧成员、旧目标和历史 pending 形成 remove pending；支持相同 revision 重试与 projectionPending 恢复。
- SyncSceneScheduleTaskBuilder 遍历真实设备，分别生成写入、移除任务。写入先场景后关联日程，移除先关联日程后场景。Sync 页面已有自动启动、STOP、失败重试及离开清理。
- Settings.viewWillDisappear 会 cancel 自己的 coordinator；因此正式任务必须交给 Sync 页面独立持有，不能继续后台 startFormal 并同时 push 页面。
- Scene 详情中的现有 pushToSyncDevicesVc 带有删除场景成功回调，不能复用这个导航方法作为保存入口。

## 行为与任务边界

1. DONE 结束输入并停止本编辑器实时组控，防重复点击，固定 draft revision。Devices 内部的选择完成按钮维持结束选择语义；页面级保存采用统一流程。
2. 校验权限、Space/网络归属、来源版本、目标能力、紧急状态，以及提交需要的 Scheduler 拓扑。保留场景编号申请与持久化失败处理。读取或申请期间退出、后台、草稿失效后，旧回调不得保存或导航。
3. 提交配置及 pending。只有 ready 才交给 Sync 页面；projectionPending 留在可重试状态，同 revision 修复投影，不能重复分配场景号或把落盘失败当成功。
4. 同步目标是本场景选中 Groups 内所有符合既有场景能力规则的设备，加上退出本场景的旧设备、历史待清理设备及受影响的绑定日程。保留身份去重、冲突检查和退出失败设备规则，不扩展到设备其他无关配置或其他场景。
5. 任务清单基于提交后的场景，由已有 builder 生成并展示。避免编辑器和页面分别维护不一致的清单；进入页面前已确定提交目标与 pending，页面准备阶段构建实际执行模型，完成后自动开始。
6. 离线设备仍属于待同步目标，失败不能计为完成；恢复连接后沿既有 Re-sync 重试。Scene Register 未知状态及容量检查复用正式执行器；删除/写入成功以正式回执和持久化结果为准。
7. 合法空组或清空已有成员仍可保存并进入同步页：有旧任务则执行清理，确实零任务时显示完成，不伪造设备成功。未选择任何成员的新草稿维持既有校验。
8. 同步失败、STOP、退出或重启不回滚已保存意图；未完成 pending 保留。建议从同步页返回时，已有场景回详情，创建流程完成创建导航，不回到可重复提交的旧草稿；Space 新建向导保留既有后续流程。
9. 正常保存不再展示试灯发送/结果确认弹窗。权限、持久化、容量等真实错误仍需反馈；已有设备身份恢复确认属于另一安全边界，不随本次删除。Preview 仍可显示试灯结果，且不保存场景。

## 最小实施范围

- SceneSettingsViewController：DONE 保存交接、导航收尾和生命周期；Preview 独立。
- SceneSaveCoordinator：提供无需预发送确认的保存能力，保留来源/版本/目标检查、幂等提交；保存路径不再自行启动正式 session。
- SceneAddViewController：仅在创建/模板回调及导航衔接需要时调整；保持先创建空场景的既有入口行为。
- 优先直接使用 Sync 页面现有 API。若回调或零任务展示确实不足，才做窄扩展，并回归其他同步入口。任务 builder/Store 原有 pending 机制优先复用。
- 本次预期仅 App 改动，不新增 SDK API、持久格式或固件/服务器配套。保留当前未提交实时组控修改。

## 验证与验收

使用现有 SceneSaveCoordinator、SceneSaveFlow、SceneCreationFlow、SceneIntegration 及任务构建相关夹具，增加行为验证：DONE 不预发送、提交后只有一套正式任务、写入/移除及日程完整、重复点击、离线/失败重试、STOP/退出晚回调、无编号申请、projectionPending 同 revision 恢复、空组与清空成员、旧格式、权限或成员变化、Preview 不落盘。

联动回归 Groups/Devices、创建/已有场景/模板及 Space 新建向导；不因共用入口让 Devices 保留旧保存弹窗。Sync 页面若有共享改动，覆盖其他入口的默认行为。

实施完成后运行相关回归并构建一次 SunSmart Debug generic iOS，先核对本地 workspace 和 SDK realpath。共享纯逻辑没有品牌条件差异时不机械重复全部品牌。无 Simulator、自动真机操作。

人工验收：多组创建后 DONE 直接进入同步页；修改参数、移除组再 DONE，确认清理及写入任务；离线一台后重试；STOP/退出重进；最后实际调用场景检查灯与关联日程。编译与隔离夹具不能证明真实设备保存成功。

## 当前基线

App 分支 feat/device-scene-261028，HEAD 982abfaf。已有未提交 SceneAdd/Settings/View、SceneExecuteDataPickerView 和实时组控测试/文档属于前一任务，本轮未改动。当前分析以该工作树实际源码为准；实施前重新核对差异与 SDK 映射。

## 条件确认与实施步骤

2026-10-30 已核对 eba3d3d8a 的两个父提交（7b0c4c26、a2f7fec3）：Scene 专用 builder 与 Schedule.getMessageHandles 在两边一致，均不含 TimeSet。用户的条件确认已满足，本次不增加校时。设备已有有效时间时可执行定时；时间未知/错误时，写入日程成功不保证按时触发，这是保留的既有边界。

实施使用当前隔离工作树，由主代理写入，不提交或推送。沿用本文已批准设计，按 executing-plans/TDD 执行，记录覆盖同一文档，避免额外计划文件。

- [x] Task 1：SceneSaveCoordinator 增加 saveForSync(draft:) → SceneCommitResult。无需 preview/confirm 即提交，保留 revision 幂等与投影恢复，只返回已保存场景，不启动后台正式 session。用现有 SQLite 保存夹具验证无发送、pending、重复提交、权限及投影恢复。运行 check_scene_configuration.py --suite save，预期通过。
- [x] Task 2：Settings DONE 通过现有预检后调用上述接口，ready 后 push SyncDevicesViewController(.scene)，移除保存确认弹窗。同步页返回收尾创建/编辑导航；Preview 沿用试灯结果。用生产方法提取夹具验证 DONE/预览分流、ready/pending、重复点击、导航回调及申请编号晚回调。运行对应新增夹具和 check_scene_address_request.py、check_scene_creation_flow.py，预期通过。
- [x] Task 3：复验 selection/integration/sync 与实时组控夹具；使用当前 SunSmartLocal workspace、SunSmart Debug generic iOS 和稳定 DerivedData 构建；独立只读审查本轮差异。更新交付记录。

接口核对：Task 2 消费 Task 1 的 ready(scene)/projectionPending(number)，只有 ready 移交页面；Sync 页面独立拥有正式 session，Settings 消失取消不会停止页面 session。危险边界：持久失败不得导航、旧回调不得导航、Sync 返回不得重入旧草稿、取消不得清 pending、实时组控不得继续覆盖 Store。真机表现待用户验收。


## 实施与验证记录

- SceneSaveCoordinator 新增 saveForSync，只落盘并返回 ready/pending；Settings DONE 使用它，正式发送仅由 Sync 页面启动。原 send/confirm 协调器接口保留既有行为供原有回归覆盖，本次 UI 不再调用 beforeSave/confirm/startFormal。
- 两个入口以及模板/Devices 共用新的保存流程。正常保存无两次确认弹窗；Preview 仍只发送试灯参数。合法空目标也进入同步页处理旧成员清理或零任务完成。
- Sync 页面返回：创建流程退出创建/继续 Space 向导，已有场景回前一详情页；不会回到已提交草稿重复保存。保存失败或 projectionPending 不跳转；成功投影重试才交接。命令生成器、资源、SDK 与后端配置未改。Sync 页面及 Session 仅追加下述待同步终态保护。
- RED：新增保存测试最初因缺少 saveForSync API 编译失败；新增 DONE 夹具执行旧生产方法时明确报 FAIL: DONE has no send/confirm dialog。实现后均通过。
- GREEN：check_scene_configuration.py 的 save/sync/selection/integration 均通过；含真实 SQLite 保存、pending/投影恢复和既有命令/依赖测试。新 SceneDoneSyncFlowTests.py 14 项通过；check_scene_address_request.py 16 项通过；check_scene_creation_flow.py 通过。
- 已有实时组控回归 SceneGroupLiveControlTests.py 22 项、CustomDeviceSliderInteractionTests.py 127 项通过。夹具运行生产方法、以 UI/HTTP/传输边界替身控制时序，不能替代 UIKit 导航或实灯。
- 调整地址测试边界后，创建夹具首次编译失败，原因是脚本复用的前置代码误带入不需要的 AllocationCoordinator；只修正脚本提取范围，随后创建夹具通过。
- SunSmartLocal.xcworkspace / SunSmart / Debug / iphoneos / generic/platform=iOS / CODE_SIGNING_ALLOWED=NO 构建通过；DerivedData 使用 SunSmart-feat-device-scene-261028-cli。保留工程既有警告（含 AppIntents metadata 提取提示）。没有安装或运行真机。
- SDK 映射为 one-dev，HEAD ccdf101，既有 MeshMessageManager/MeshGroupControlSession 未提交修改来自前一任务；本轮没有修改 SDK。没有新增跨品牌资源、编译条件或公共 SDK API，本轮代表 scheme 为 SunSmart。
- git diff --check 通过。无 commit/push；前一任务差异保持原样。

人工最短验收：Create scene 选多个 Groups 后 DONE，检查直接进入 Sync device(s)；已有 Scene Settings 修改参数/移除组后 DONE，检查写入及删除任务；离线一台、STOP、返回再同步；确认 Preview 不保存，最后 Recall 检查灯的实际状态。新成员定时执行须确保设备时间有效，本次没有新增校时。


独立审查发现并修复一项 P2：旧成员身份已不存在时，builder 可能没有可执行任务，而持久化清理仍未完成；旧后台完成回调有 !scene.needSync 检查，移交页面后需保留该保护。Session.finishRun 现在仅在 Scene.needSync=false 时报告成功；无可执行失败行但仍 pending 时，Sync 页面显示已有国际化文案“已保存，部分设备待同步”，隐藏无效全选。没有改变命令或目标范围。

补测先复现 zero executable tasks must not hide unresolved scene intent 失败，再修复并通过 check_sync_execution_session.py（真实 Session，Scene 状态边界替身）。另在 check_scene_configuration.py --suite sync 中运行真实 resolver、builder、Scene.needSync，验证缺失旧身份产生零任务但仍 pending，移除 pending 后才能完成。两层夹具不冒充整 App 运行。补测脚本首次提取到 Group 同名属性导致编译失败，定向限定 Scene 扩展后修正。

扩展验证：check_sync_task_builders.py、check_sync_run_lifecycle.py 通过，覆盖其他同步入口的构建、依赖、停止/重试/补偿及跨页面发送通道；末次生产代码变更后 SunSmart generic iOS Debug 再构建通过。没有未处理的审查缺陷；既有容量未知且离线时仍会阻止保存，属于本次保留的安全预检。不存在可执行目标的历史 pending 需设备身份恢复或既有清理机制处理，不能凭空给设备发送。

## 2026-10-30 实测失败：日志分析与待确认修复步骤

状态：只读调查完成，尚未修改业务代码。日志来源 `/Users/maginawin/Desktop/save scene failed.txt`，约 400 行；原日志含敏感字段，本文仅记录场景号、组地址、参数及阶段，不复制完整响应体。

### 已证实事实

- 用户补充：Sync device(s) 已列出两个 Group 及组下设备，设备均为失败状态。因此排除本次为“任务全部过滤、零任务失败”。
- 第 295–297 行为 DONE 点击；第 359 行进入 SyncDevicesViewController。
- 第 394 行服务器回读的两组 scenesDatas 均包含场景 13：C000 为 ON、亮度 43908、2700K；C001 为 ON、亮度 65535、6500K。末尾 readback confirmed、CloudSync Success，说明保存配置并上传/回读成功，不代表设备写入成功。
- 整份日志只有 DONE 前的 6 条组播实时调节发送；从 DONE 起，没有可见的 BLE 发送、SceneRegisterGet、单播参数设置、SceneStore 或对应设备状态回执。不能据此归因固件拒绝、SceneStore ACK 超时或缺少 TimeSet；但日志缺少连接与任务分支信息，也不能仅凭“未记录发送”断言蓝牙一直正常。
- 两组参数已形成设备任务，失败范围收敛到页面计划被统一标失败，或执行器在首次正式发送前拒绝。现有日志没有 resume、失败原因、任务进入状态或 handles 数量，无法唯一确定是哪一条 guard。

### 仍需区分的实际生产路径

1. `SceneRestoreConfirmation` 出错返回 false，页面以 resume=false 构建计划；builder/installTaskPlan 会将设备直接标 failed，不发送。现有实现把取消/恢复阻塞折叠为 Bool，错误原因不进入任务记录。
2. `SyncExecutionSession.processNext` 在配置不可用、Bluetooth 不可用、Scene 容量验证失败或场景 handles 为空时，不发送并转失败。任务规划时成功不保证执行时权限/场景来源/组关系仍有效；getSyncMessageHandles 内部 guard 失败会返回空数组。
3. `prepareDeletionRetries` 失败发生在安装新计划之前，首进通常不会生成当前两组行，因此按用户补充降低优先级。之前怀疑的零任务 finishRun 分支也已排除；不删除 needSync 防误报保护。

额外源码核对：Scene 普通同步不会仅因 node.state=false 或 configComplete=false 自动跳过发送；日志片段中的 configComplete=false 不能单独当作根因。保存路径与同步页面中 Scene.validateAccess 的调用位置不同，仍需记录执行时实际结果，不能臆测权限变化或云端干扰。

### 建议实施顺序（待用户确认）

1. 先补必要的 DEBUG 失败诊断，不改变命令与校验：
   - 页面恢复检查结果、resume、计划版本、sceneNumber、设备/任务数量；恢复错误和用户取消分开记录。
   - Session 每次失败只记录首个明确阶段/原因：configurationUnavailable、bluetoothUnavailable、capacityUnknown/full、emptySceneHandles、planInvalidated、transportFailure。
   - Scene 命令生成失败区分当前场景不存在、scope/权限、身份或成员关系不匹配、projectionPending、缺少所需 Model、pending 持久化失败。只记录节点地址与原因枚举，不打印 Device Key、密钥指纹或原始网络对象。
   - 记录“进入发送接口”和终态，区分准备失败、已发未确认与已确认。
2. 用原始“两组各有设备、创建空 Scene 后选择两组、DONE”路径建立覆盖生产 coordinator→builder→operation message factory→Session 的回归；保留真实 Scene 身份、权限和 pending 校验，UI/传输作为边界替身。已有 DONE 夹具用简化 coordinator/resolver，只证明导航分流，不能证明上述整链可发送，这也是上一轮验证的缺口。
3. 根据复现或补充日志命中的第一失败分支实施最小修复：若是可恢复的准备阶段，完成既有准备并重新校验后再安装/启动；若是无效/缺失命令，修复实际产生原因并保留显式错误；真实权限撤销、容量满或身份变化仍应拒绝。不得改成空 handles 成功、删掉容量/身份校验，或只把 UI 改成成功。
4. 同时检查已有 Scene Settings DONE、手动 Re-sync、退出重进、投影恢复、STOP 与旧回调。已保存的场景 13 保留同编号和 pending，不要求删除重建或重新配网。
5. 确认修复后运行相关行为回归及 SunSmart generic iOS 构建；用户从同一已保存场景重试，日志应出现逐设备参数设置成功后 SceneStore，再确认设备回执与实际 Recall。

本轮未运行 App 构建或真机；未修改生产/测试代码。当前不能给出唯一根因或声称已修复。建议批准先补上述窄诊断与复现，证实第一失败条件后在原场景保存/同步范围内修复；不增加 TimeSet，不更改固件或后端。

## 2026-10-30 补充诊断实施记录

用户已授权“补充诊断”。本次仅添加 DEBUG 诊断及对应测试替身支持，不改变同步命令、发送顺序、重试或权限/容量/身份校验，不增加 TimeSet。

- 统一前缀 `[SceneSync]`：记录恢复检查、取消与错误、清理准备、计划安装及设备任务状态。
- 执行器记录配置/Bluetooth/容量拒绝、命令数量、参数与后续命令提交、回调结果、计划失效和终态；用 run 标识串联同一轮执行。提交日志仅表示调用发送接口，不代表设备收到或执行成功。
- 命令生成及保存访问检查记录首个拒绝原因，覆盖缺少 Model、场景/参数缺失、权限或 Scope 不可用、身份/投影/成员不匹配、紧急状态及持久化失败。只输出地址、数量、状态与受控错误枚举，不输出网络对象或密钥。
- 保存与同步相关回归通过；额外以 `-D DEBUG` 编译并执行保存、同步命令和真实 Session 夹具，诊断分支可编译且回归通过。DEBUG 夹具最初缺少生产类型的测试替身声明，补齐后通过；没有为适配测试放宽生产规则。
- 最后一次生产代码变更后，SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS 构建通过。`git diff --check` 通过。未操作真机、未修改 SDK、未 commit/push。

下一步人工复现：使用当前分支 Debug 包，按原路径选择两个 Groups 后点击 DONE，收集从点击前到失败后的全部 `[SceneSync]` 日志，不只保留最后一行。已有场景可以从 Settings DONE 或 Re-sync 重试，无需删除重建。根据首个失败分支再确定最小修复；原问题目前尚未确认根因或修复。整条创建路径与真实设备运行仍待现场日志验证。

### 六行 HTTPS URL 的计数澄清

用户补充重试时看到 get/get、sync/sync、get/get 六行 URL。`NetworkLoggerPlugin` 在 `[HTTP][Request]` 和 `[HTTP][Response]` 各打印一次 URL，因此 URL 行数不能当作请求数。已提供日志的 DONE 后片段可直接核实：第 309/321 行为第一对请求/响应（Metrics task=16），349/362 为第二对（task=17），374/386 为第三对（task=18），实际共三个请求。

正常单轮 Space 上传依次为：读取云端基线以校验权限与配置冲突；上传完整 Space 配置；回读确认提交结果。Group 和设备作为 Space 配置内容一起上传，不按 Group 或设备各发一套 HTTPS 请求。这里接口路径中的 get 表示读取用途，实际 HTTP method 仍为 POST。

新重试片段仅给出了 URL；若同样来自上述 Request/Response 日志，则也是三个请求。没有证据表明本次存在两轮重复上传，因此不据此修改云同步调度。正常单轮三个请求不等于所有异常情况下硬性最多三个：回读未一致时现有逻辑最多尝试三次回读，期间产生新配置也可能需要后续上传。云端上传成功仍不能证明 Mesh 场景同步成功，原失败继续以 `[SceneSync]` 诊断为准。

## 新日志根因确认与修复范围（待确认实施）

来源：`/Users/maginawin/Desktop/new sync scene devices logs.txt`，277 行。本轮只读分析和临时夹具复现，未修改生产/测试代码，未构建或操作真机。

### 已确认的失败链

- 第 4–21 行：场景 13 恢复检查通过，清理准备通过，安装两个设备和两个 pending 的同步计划。
- 地址 5、8 分别在第 36–38、59–61 行返回成功的 SceneRegisterStatus，寄存器均为空，容量读取成功。现场 BLE 查询和回执可达。
- 第 40、63 行：两台设备均触发 `reservationRejected reason=notWriteTarget`；之后命令数为 0，执行器以 `emptySceneHandles` 拒绝并在第 68 行结束失败。没有发出参数设置或 SceneStore。
- 第 168–184 行再次重试仍命中相同拒绝。`taskRows=0 / steps=0` 不是零任务：没有关联日程时，设备行本身承载 Scene 操作，不生成子步骤行。`failedModels=4` 统计包含父级模型，也不表示四台设备。

### 代码根因

`SchedulerModelSnapshot.keyFingerprint` 使用 `%02x` 生成小写指纹，`Node.timedSchedulerIdentity` 原样保留；`SceneConfiguration.identity` 把 UUID、地址及指纹全部转换为大写，Scene 持久化、resolver 和 context 使用这个规范形式。身份结构的自动 Equatable/Hashable 比较区分大小写。

`SceneCommandBuilder.reserveGroupOperation` 直接使用原始 `node.timedSchedulerIdentity` 与规范化 pending 和 targets 比较：先找不到已有 write，再判定不在目标列表，返回 false。这是 App 对同一身份表示不一致造成的误拒绝，不是设备离组、容量满、固件拒绝、HTTP 请求次数或缺少 TimeSet。

临时夹具复用生产 resolver、SceneCommandBuilder、SceneMessageContext 及 getSyncMessageHandles，配置两个 Group、地址 5/8、场景 13、规范化 pending：

| 输入指纹表示 | resolver 目标数 | 每台设备命令数 | Session 同类原始身份查找 | context 内规范化匹配 |
| --- | --- | --- | --- | --- |
| 小写（生产格式） | 2 | 0，重现 notWriteTarget | false | true |
| 大写（原测试格式） | 2 | 2，参数命令 + SceneStore | true | true |

夹具执行成功，未将任何实际密钥或指纹写入日志/文档。此前 `SceneTargetTestSupport` 的默认指纹为大写 A，掩盖了生产格式差异；原回归通过不能证明本路径在真实设备身份下正确。

### 必须一起修复的范围

只改 reservation 不完整：`SyncExecutionSession.validatePlan`、`received`、`applyResult` 仍用原始设备身份查找 Scene context 的大写身份，会继续在发送前或回执/回写阶段拒绝。

建议沿用现有 `SceneConfiguration.identity`，在 Scene 使用设备身份的边界统一规范化，并完整保留 UUID、地址、密钥指纹、Scope、revision 与 operation generation 校验。可增加窄的 Scene 身份访问属性供相关调用复用，不改变共享 `timedSchedulerIdentity` 的返回格式或全局 Equatable/Hashable，以免破坏已有 Scheduler slot/恢复数据契约。

同一类不一致还出现在 SceneSaveCoordinator Preview、Node 场景删除 pending 筛选、Scene Settings Identify，以及 SceneConfigurationStore 的 Restore 验证、已验证恢复和确认身份比较。属于本次同根问题的关联修复范围；这些路径目前是源码证据，不冒充本次日志已运行。应检查全部 Scene 身份边界，已规范化的 resolver/context 继续复用。

### 验证与恢复

1. 固化小写生产指纹的两组两设备回归，覆盖规范化持久 pending、resolver、任务生成和实际命令 factory，确保先复现再修复；补充大小写等价和真实身份变化仍拒绝。
2. 覆盖真实 Session 的发送前验证、参数 ACK 后 Store、结果落盘与 pending 清除、失败重试、STOP/退出晚回调；同步回归 Preview、删除/重加、Identify 与 Restore 的身份边界。测试替身不得继续只用大写身份。
3. 保持现有 Scene 存储大写格式，无需重建场景或配网；场景 13 当前 pending 可在修复后继续 Re-sync。确认失败与取消不丢 pending，真正更换设备密钥不能误继承旧任务。
4. 修改完成后运行相关 Scene/Sync 回归及 SunSmart generic iOS Debug 构建。用户在原场景重试：应先见参数命令成功，再见 SceneStore 成功，pending 清除，最后 Recall 验证灯的实际状态。

本次只需 App 修复；不增加 TimeSet、不改 SDK/固件/后端、不删除安全校验。当前已确认根因并完成隔离复现，尚未实施修复。

## 身份规范化修复交付

用户已确认按上述建议实施，本轮修复完成。

- 新增窄的 `Node.sceneConfigurationIdentity`，直接复用既有 Scene 规范化及合法性校验。reservation、Preview、Identify、Session 发送前检查/ACK/结果回写、删除 pending 筛选、Restore 持久身份检查/重放/确认候选统一使用它。共享 Scheduler 身份、持久格式、Scene 命令顺序和 TimeSet 策略均保持原样。
- 保留 Scope、UUID、地址、完整密钥指纹、revision 和 pending generation 的校验；仅大小写差异视为同一身份，真实密钥变化仍拒绝旧任务。现有场景及 Restore receipt 无需迁移，场景 13 的 pending 可原地重试。
- RED：新两组设备回归在未修代码上明确报 `FAIL lowercase production identity must generate parameters + SceneStore for both groups`。修复后通过，并验证 pending generation 重用、大小写等价、真实密钥变化拒绝以及删除任务发现。
- Session 夹具由整数身份改为真实 `TimedSchedulerNodeIdentity`/`SceneConfiguration` 和生产规范化属性；验证小写身份的初次发送、ACK、参数成功后 Store、结果回写，及真实换钥匙拒绝。仍替代 SceneMessageContext 和部分协议/存储边界，不能称作完整 App 链路验收。
- Preview 测试使用小写指纹；Restore/删除测试使用小写新身份，覆盖取消/确认、被确认身份再次变化、COMMIT/receipt 写入失败、重进重放、旧 ACK 拒绝和幂等。Identify 运行生产 Settings 方法及选择列表查找方法，覆盖小写、缺失身份、权限拒绝及旧身份查找失效。
- 已通过：Scene `sync/save/integration/targets`（targets 28 项）、`check_scene_deletion_flow.py`、`check_sync_execution_session.py`、`check_sync_task_builders.py`、`check_sync_run_lifecycle.py`、DONE 流程 14 项。独立只读审查未发现本轮必须追加修复的问题；`git diff --check` 通过。
- SunSmartLocal.xcworkspace / SunSmart / Debug / generic iOS / CODE_SIGNING_ALLOWED=NO 构建通过（2026-10-30 17:28）。SDK realpath 仍为 one-dev、HEAD ccdf101，未更改其既有工作区差异；没有新增 SDK API、依赖/资源或品牌条件差异，因此本轮使用代表 scheme SunSmart。

未自动操作真机，未 commit/push。人工最短验收：使用当前分支 Debug 包打开已有场景 13，进入 Sync device(s) 重试；预期两台设备均依次完成参数设置和 SceneStore，页面成功且 pending 清除，再 Recall 检查灯的实际状态。若仍失败，保留本轮 `[SceneSync]` 日志继续定位，不需删除场景或重新配网。

## 用户实测通过与成功退出建议

用户报告测试通过，提供 `/Users/maginawin/Desktop/new sync scene logs .txt`（225 行）。已核对：地址 5 的参数回执为亮度 43908/2700K，地址 8 为 65535/6500K；两台均在参数成功后发送 SceneStore(13)，返回 Success 且 scenes=[13]（第 74、128 行），对应结果 `applied=true`（第 76、130 行）。第 132 行终态 `syncSuccess`、`failedModels=0`。当前 Session 的成功判定还检查 scene.needSync，因此日志表明本次 pending 已清；实际 Recall 体验以用户验收为准，不从 Store 回执额外推定。

用户询问全部任务成功后是否应主动关闭同步页。建议 Create scene / Scene Settings DONE 进入的同步页全部成功后自动完成导航；失败、STOP 或仍 pending 保留页面供重试。当前 Settings.openSyncPage 只设置 backActionCallback，没有设置 syncSuccessCallback，公共同步页成功时仅更新显示并调用成功回调，因此现在需手动返回。

建议最小实现：Settings.openSyncPage 复用同一份创建/编辑收尾逻辑，供成功与手动返回两个回调调用，并保证只收尾一次。创建继续原创建/Space 向导，编辑回原详情；无需回到已提交草稿，也无需等待云端后台上传。其他同步入口自行决定导航，不按 `.scene` 类型一律自动返回：Scene 列表/详情中的部分同类型入口成功后还会执行删除逻辑，不能覆盖其回调。无需增加固定延时或确认弹窗；如展示成功提示，复用已有国际化文案。

待用户确认后实施成功退出行为；本次仅核对日志与规划。验证覆盖创建/编辑成功、失败后重试成功、STOP/残留 pending、不重复退出及晚回调，并保留其他入口行为。

### 成功自动退出已实施

用户确认后，Settings.openSyncPage 的成功与手动返回回调已共用同一 finish 闭包，并通过 didFinish 保证只收尾一次。创建沿用 finishCreation（含 Space 向导），编辑沿用返回原详情；公共 Sync 页面和其他调用方未修改。失败/停止仍不触发成功回调，残留 pending 继续由已有 Session 成功保护拦截，不等待云端上传。

新增回归先在旧代码上复现“successful retry automatically skips committed Settings”失败；修改后 DONE 流程共 21 项通过，执行生产 openSyncPage 及公共页 onCompleted 闭包，覆盖创建/编辑成功、失败后成功、成功与手动返回重复到达、退出后的旧完成回调。UIKit 导航与传输使用替身；Session 的 STOP/pending 判定未修改，复用上轮相同代码的回归结果。

SunSmartLocal / SunSmart Debug generic iOS 构建及 git diff --check 通过。此次新增业务改动仅成功退出回调接线和幂等保护；没有 SDK 修改、真机操作或 Git 提交。待人工验收创建 DONE 与编辑 DONE 成功后自动离开，失败/STOP 留在同步页。

## 未修改 Settings 不重复生成同步任务

用户建议：此前同步已成功，Settings 没有更新时不再生成同步任务。已实施。

原因：SceneDraft 每次进入编辑器都会产生新的 revision；原 commit 无内容相等判断，会将全部当前目标重新写成 pending write。现在 Store.sceneIfUnchanged 在权限、Scope 和来源校验后比较当前与草稿的实际内容及图标，而非比较草稿 revision；共享 commit 也复用该判断，未修改时不写数据库、不重建 pending、不重写 SDK 投影。

Settings DONE 在预读容量/日程前分流：

- 内容未变且当前 needSync=false、无持久 pending：直接退出 Settings，预创建流程沿用原创建/向导收尾，不打开同步页。
- 内容未变但仍有同步工作或 pending：直接交给同步页处理当前状态，不重新提交、替换 revision 或生成新的任务代次。
- 内容有实际变化：沿用现有保存和同步流程。修改后恢复原值视为未修改；新建未分配场景仍正常保存。权限变化、过期来源和未恢复的投影不会被无修改分支绕过。

验证：旧实现分别复现“unchanged Settings must preserve existing revision and pending generations”和“unchanged synced Settings closes once without save or Sync page”失败。修复后 DONE 26 项、Scene save（真实 SQLite）、创建流程、删除/Restore 回归全部通过。覆盖已完成/仍 pending、改回原值、图标变化、旧 Group 格式不升级/重写、过期来源、投影阻断及权限限制。UI/传输仍使用边界替身。

SunSmartLocal / SunSmart Debug generic iOS 构建通过（2026-10-30 17:53），git diff --check 通过。未修改 SDK、未操作真机、未提交 Git。人工验收：已同步场景进入 Settings 不改动直接 DONE，应直接返回；改变参数后 DONE 仍应进入同步页；上次失败的场景不改动 DONE，应继续处理待同步任务。

## 部分组修改时只生成必要任务

用户补充：两个组此前均已同步成功，只修改一个组时另一个组仍产生任务。原因是上一轮只处理整份内容未修改；实际内容变更的 commit 仍对 snapshot.targets 全量生成 write。

已将共享 SceneConfigurationStore.commit 改为逐设备比较当前旧目标与新目标（完整身份、模式、实际参数及 Group 附加配置），并结合当前持久 pending 和设备确认缓存：

- 未改目标、无 pending 且缓存匹配：不生成 write。
- 目标新增/改变、删除后重加、确认缓存缺失/不匹配：生成 write。
- 目标未改但 write 尚未完成：保留原任务 generation；仍需同步的关联日程继续按已有 builder 处理。
- 移除成员：保留必要 remove；未完成 remove 沿用原 generation。读取当前提交状态，避免编辑期间已确认完成的 write/remove 被草稿旧数据恢复。

同一规则覆盖 Group 与 Devices 模式。Scheduler 既有 slot/generation 不因参数更新而改变；不增加 TimeSet，不修改任务发送/ACK 安全规则。未修改组的既有成功状态不因另一个组参数更新而被重置。

独立审查发现并补齐关联预检边界：SceneTargetResolver.resolve(draft:) 原先还使用草稿历史 cleanup，会把已完成删除当作额外容量占用。现仅在来源 revision 相同时使用当前 cleanup 并核对 Scope；旧来源仍由既有 validateSource 拒绝。未完成和未解析的清理继续保留，已完成清理不再阻断其他成员的合法修改。

验证：新增回归在旧逻辑先复现“changing one group must not schedule an unchanged confirmed group”失败；容量边界先复现“completed removal must not reserve capacity in draft preflight”失败，修复后通过。实际运行生产 Store、resolver、容量/Scheduler 预检、SQLite 持久化与任务 builder，覆盖两组只改一个、未改组离线但已确认、pending 保留、缺失/过期缓存、新增/重加、编辑期间 ACK、持久重读、稳定/待同步日程、移除一个组、直接设备增量，以及删除完成后容量空余/满 16 个/未知。协议传输与硬件仍为替身，不代替真机验收。

最终通过：Scene save/sync/targets（28 项）、删除/Restore 流程（含以上增量用例）、DONE 26 项；审查问题修复后复核未发现新增必要修复项。最后生产代码变更后 SunSmartLocal / SunSmart Debug generic iOS 构建通过（2026-10-30 18:07），git diff --check 通过。无 SDK 修改、自动真机操作或 Git 提交。

人工验收：两组均同步成功后，只改第一组目标值并 DONE，Sync device(s) 应只列出第一组需要更新的设备；第二组若仍有失败任务/关联日程待同步，应保留其真实任务。移除第一组时保留其必要清理，第二组不重复写入。
