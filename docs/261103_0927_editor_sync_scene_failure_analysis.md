# Visitor 重新以 Editor 导入后，设备同步误报删除场景失败

日期：2026-11-03。分支：`feat/device-scene-261028`。分析基于当前代码，结束时 HEAD 为 `f645cf33`。本轮只分析和运行临时诊断夹具，没有修改业务代码、正式测试或 SDK。

## 结论与证据边界

已证实：Lights 底部同步进入的是通用设备同步页，但该页在生成任务前无条件执行 Scene 恢复检查和删除重试准备。权限、Space 上下文、恢复状态、Scene 数据读取等任一检查失败，都可能最终显示 `failed to delete scene`。因此，该提示不能证明设备执行过 Scene Delete，更不能证明 Owner 一定删除过场景。

已在隔离夹具复现“Editor 的同步按钮允许点击，进入准备流程后误报删除场景失败”，包括零 Scene 情况。已验证正常 Owner/Editor，以及待写入、待删除 Scene 的生产导入和重试逻辑均可通过准备。

尚未确定：现场具体是哪一个前置条件失败。输入是用户对视频操作的描述，没有视频文件、DEBUG 日志、空间导出或测试 App 的 build 标识；用户已确认没有日志。不能将“Visitor 解绑后残留只读权限”或“残留删除任务”直接写成现场根因，也不能承诺仅按正常角色切换步骤就必现。当前代码的误报和失败恢复缺口已足够规划修复；现场触发原因仍需定向复测。

## 复现步骤

### 还原反馈的业务路径：待人工重放

准备两个账号 A、B，A 为 Owner，B 初始为 Visitor；同一 Space 至少有一台灯。建议另有一台可保持 Mesh 连接的设备，避免把整网离线作为唯一变量。

1. A 先让目标灯完成基本配置。随后让目标灯离线，编辑它所在 Group 的 Profile 或普通 Scene，保存但不要让设备完成同步；也可在同步中 STOP。回到 `Site → Space → Lights`，确认底部出现未同步图标。
2. 确认这份待同步配置已经上传云端。设备同步失败和配置上传成功是两件事；若云端未更新，B 不一定能看到相同待同步状态。
3. B 以 Visitor 导入并进入相同 Space，确认可以看到未同步图标。当前代码的图标可见性由设备 `needSync` 决定，Visitor 仍可看到，但按钮应不可点击。
4. B 退出并解绑这个 Space，等待解绑成功、列表移除；再通过有效分享，以 Editor 身份输入相应授权密码重新导入。单 Space 与批量导入先以现场实际入口为准。
5. B 进入同一 `Site → Space → Lights`，待列表加载，点击底部未同步图标。
6. 观察是否进入 `Sync device(s)` 并立即提示 `failed to delete scene`；同时记录任务列表是否为空、RE-SYNC 是否有效、退出重进后是否恢复。设备保持离线可以保留待同步状态，但没有必要通过真正执行删除来触发本误报。

上述步骤用于还原报告；要稳定出现当前代码里的误报，还必须命中下一节的异常状态之一。若正常导入完成后无弹窗，属于有效对照，不能为了“复现”把同步失败或角色变更本身判为故障。

### 已完成的确定性代码复现

临时探针：`/tmp/sunsmart_sync_entry_probe_261103.py`。复用现有 `check_scene_deletion_flow.py` 框架，执行生产权限属性、`SceneConfigurationStore`、`SceneRestoreConfirmation`、真实临时 SQLite，以及从同步控制器原样提取的删除准备 `do/catch`。网络、UIKit 导航、完整 Membership/Recovery 生命周期由夹具替代；不操作用户 Space。

| 输入状态 | 底部按钮权限判断 | 准备结果 |
| --- | --- | --- |
| 正常 Owner，零 Scene | 允许 | 进入后续任务生成，无提示 |
| 正常 Editor，零 Scene | 允许 | 进入后续任务生成，无提示 |
| Editor，但 recovery authority 为 readOnly | 允许 | `recoveryNotWritable`，最后提示删除场景失败 |
| Editor，但 recovery authority 为 waitingForAuthorization | 允许 | 同上 |
| Editor，但 requiresPasswordVerification 为 true | 允许 | `storedSpaceNotEditable`，最后提示删除场景失败 |
| 页面对象为 Editor，持久化 Space 仍为 Visitor | 页面判断允许 | `storedSpaceNotEditable`，最后提示删除场景失败 |
| 当前 Space 控制器无法解析 | 页面判断允许 | `activeSpaceMissingOrChanged`，最后提示删除场景失败 |
| 普通 Scene 配置损坏，没有删除意图 | 允许 | persistence 失败，最后提示删除场景失败 |
| Visitor 对照 | 禁用 | 强制进入夹具时权限拒绝；正常 UI 不应允许进入 |
| 已阻断配置对照 | 禁用 | 强制进入夹具时 `configurationUnavailable` |
| Owner 待写入 Scene 导出，Visitor 接收，Editor 以正常权限重导入 | 允许 | 保留 revision/待写入操作，准备成功，待同步任务仍可生成 |
| Owner 待删除 Scene 同样导出、接收及重导入 | 允许 | 保留删除意图及操作 generation，恢复清理投影，待删除任务仍可生成 |

12 个用例最终全部通过各自预期断言。失败用例均捕获到先 `scene_restore_pending`、后 `scene_delete_failed` 的提示调用；这解释了为什么视频可能只看到最后一条。真实 UI 显示顺序与停留时间未验证。

## 原因与完整调用链

### 1. 底部图标不专属于 Scene 删除

`DeviceLightsViewController.updateUI` 使用 `NodeSyncStatusRefresh` 决定图标是否隐藏，使用 `space.deviceOperates.contains(.edit)` 决定是否启用。`Node.getStandardNeedSync` 会检查 Key Bind、Group/Profile、Scene 写入或删除、Timed、开关与邻近照明等状态。

`functionDidClickSync` 选择 `devices.filter { $0.needSync }`，创建 `.devices(syncDevices)` 类型的 `SyncDevicesViewController`。因此“Owner 和 Visitor 都有该图标”只能说明各端推导出有未完成配置，不能识别失败的具体命令，也不代表两端均执行失败过。

### 2. 通用同步准备被 Scene 权限检查覆盖

同步页 `viewDidLoad → rebuildTaskPlan` 顺序是：

1. `SceneRestoreConfirmation.presentIfNeeded`：先恢复 verified receipt，再检查待确认 Restore。
2. `pendingRestoreConfirmations` 在确认是否存在相关 receipt 之前调用 `validateAccess`。即使没有 Scene/Restore，也会检查权限。
3. Restore 检查异常统一显示 `scene_restore_pending`，调用 `completion(false)`。同步页仍继续 `rebuildTaskPlan(resume: false, confirmSceneRestore: false)`。
4. 等待 `SpaceSyncCleanupCoordinator.prepareCurrentSpace()`；返回的 Bool 被忽略。
5. 无条件调用 `SceneConfigurationStore.prepareDeletionRetries()`。它在读取待删除记录之前先调用 `validateAccess`，随后读取当前 Space 的全部普通 Scene 配置。
6. 任意异常进入唯一 catch：显示 `scene_delete_failed`，设置 `.syncFailure`，直接返回。此时尚未执行 `SyncTaskPlanBuilder.build()`、安装列表或开始本次同步命令。

`validateAccess` 检查主线程、Mesh/子网、配置完整性、持久化 Space、活动 Space、两者编辑权限及 recovery 的 active/writable 状态；目前所有授权/上下文拒绝都折叠为 `.unavailable`，页面无法按原因展示恢复方式。

### 3. 按钮与实际执行条件不一致

`SpaceData.deviceOperates` 检查 membership、配置阻断、Visitor、临时禁用编辑和 OTA；它没有直接检查 `requiresPasswordVerification` 和 recovery authority。

Scene 的执行校验额外要求 `canEditing`、持久化及活动 Space 一致、recovery writable。`isBlocked` 也不等同于 recovery writable。因此存在“页面按 Editor 启用按钮，但真正执行仍被拒绝”的确定状态组合。临时探针已复现这些组合，但没有证明现场由哪条导入时序创建了它们。

### 4. 失败后普通 RE-SYNC 不能重做准备

当前异常分支没有安装任务列表，也没有调用统一的状态 UI 刷新。普通 `.devices` 的 RE-SYNC 只重试已选中的失败设备行；列表尚未生成时没有可重试设备。HDB 分支会重新建计划，普通灯分支不会。因此即使随后权限恢复，当前页也可能需要退出重进才能继续。

### 5. 重新导入没有固有的“必须失败”规则

已只读核对以下上下游：

- 单 Space/批量加入：成功后通过 `authorizeJoin` 建立新 membership，并设置所选权限和授权状态。
- 解绑：`finishLeave` 完成本地删除，Recovery 通过 retired/archive 与后续 `activateImport` 隔离新一轮导入。
- 导入：`applyRemoteSpaceMetadata` 接收服务器角色；`reconcileAuthority` 在条件满足时恢复 writable；完整恢复结果通过 `applyConfigurationState` 回写活动对象。
- Scene：`importRecords` 刻意允许 Visitor 接收未完成意图；执行仍由权限检查保护。任务状态随配置共享是预期行为，不能在 Visitor 导入时清空 pendingOperations 来消除图标。

上述正常链路没有仅因“曾是 Visitor”就拒绝 Editor 的规则。缺少现场日志时，优先验证权限恢复/页面与存储状态不一致；同时保留 cleanup 后配置被阻断、活动 Space 获取失败、Scene 持久化异常等候选原因。当前代码已有对应 DEBUG 日志，不需要先修改服务器或固件。

## 建议修复方案：待实施

### 必须解决的 App 问题

1. **统一同步准备与权限反馈。** 在共享同步入口复用现有 membership、配置保护和实际权限判断，区分未授权、等待密码、配置不可用、上下文已改变；底部按钮和点击时复核采用一致的规则。执行边界仍复核，防止按钮刷新后权限变化。核对设备/Group/Scene/Profile/Timed/HDB/Restore 使用方的合法上下文，不把所有类型机械限制为 Scene 编辑。
2. **区分“无相关工作、用户取消、准备失败”。** Restore 没有相关 receipt、Scene 没有删除意图时，不产生操作专属错误。通用授权/数据完整性检查仍保留；有损坏数据不能伪装成空配置。Restore 准备失败应结束本轮准备并保留明确原因，不能随后再用删除失败覆盖；用户取消保留取消语义。
3. **让错误对应真实阶段。** 在现有错误路径中保留拒绝原因，权限或配置异常复用合适的现有国际化文案，例如 `configuration_sync_unavailable`；仅真实的 Scene 删除准备/执行失败使用删除类提示。补充文案时同步 English、简体中文及品牌资源归属。
4. **恢复当前页的可重试状态。** 记录任务计划是否安装；准备失败时停止加载、刷新失败/返回 UI。权限和配置恢复后，普通设备的 RE-SYNC 应重新执行准备与建计划。保留已安装计划的现有失败行重试逻辑，不能对每次重试重新生成 Scene revision/generation。
5. **正确处理异步准备结果。** 不再静默丢弃 cleanup 的实际阻断原因；但不能简单将每个 `false` 都视为必须终止，因为它还包含待上传等延后条件。按当前 protection/error 状态决定继续或提示。等待前后核对同一 Space、账号、子网与恢复生命周期；离页、切换空间、旧回调晚到不继续建计划或覆盖新状态。

优先改动点是 `SyncDevicesViewController.swift`、`SceneServer.swift`、`SceneConfigurationStore.swift`，以及按需复用/小幅扩展的 Space 权限和准备接口；UI 入口只接入共享结果。无需新建同步框架，也不只在 Lights 页面屏蔽弹窗。

### 现场触发原因的修复边界

在以上回归中追加真正的 Visitor → 解绑完成 → Editor 导入生命周期用例，检查 DB Space、活动 Space、membership generation 与 recovery authority 同步收敛。

- 如果证实正常重新授权成功后仍留下旧只读/等待状态，在已有 `authorizeJoin → restoreConfiguration → reconcileAuthority → applyConfigurationState` 链路修复持久化或回写顺序；授权与完整导入失败时不得强行设 writable。
- 如果证实是 Space 控制器解析失败，使用当前页面的实际导航/Space 上下文并核对网络身份；不能移除活动 Space 校验或用全局任意 Space 兜底。
- 如果是数据损坏或数据库失败，沿原恢复机制显示准确错误、保留配置和任务，不删除 Scene 或重建空数据来绕过。

这些是依证据选择的修复分支；本轮不同时重写全部导入/权限机制。所有品牌共享相关逻辑；默认只涉及 App，无 SDK 新 API、协议、后端或固件变更。既有 revision、operation generation、Scene 编号保留与迟到 ACK 防护继续生效，无批量历史数据迁移需求。

## 验证与验收

实施时将临时探针中有效用例接入现有测试，并补共享页面的行为验证：

- 普通设备同步、Group/Profile/Timed 同步：零 Scene、无 Restore、合法旧格式及无待删除任务，均不能误报删除失败。
- 正常 Owner/Editor；Visitor 只读；密码待验证、recovery 只读/等待、页面与持久化权限不一致；保护失效前不发送命令。
- Owner 的未完成写入/删除意图经过 Visitor 接收、解绑、Editor 重导入和重启恢复后保留；有效授权后能继续同步，实际成功前不释放 Scene 编号或误标已完成。
- Restore 用户取消与准备异常分别处理；失败只提示一次；无任务列表时恢复权限再 RE-SYNC 能建计划。
- 存储失败、配置阻断、离页/切换 Space、迟到回调与未完成导入：不串 Space、不抹任务、不绕过完整性保护。

优先使用 Scene deletion/configuration、Sync task/session、Space membership/recovery 现有脚本，按实际修改选择必要子集。一轮 Swift 修改完成后构建一次 SunSmart Debug / generic iOS；涉及跨品牌资源或配置时再覆盖受影响品牌。

人工最短验收：重放前述两账号步骤；确认 Visitor 图标可见但不可执行，正常 Editor 能进入并同步；真正未授权时显示对应提示；恢复后无需清空或重新创建空间即可重试；返回、重进和重启后待同步状态一致。

本轮未构建 App、未运行真机、未调用线上服务。隔离夹具验证不代表真实分享/解绑/云端往返、UIKit 体验或设备执行已经验收。
