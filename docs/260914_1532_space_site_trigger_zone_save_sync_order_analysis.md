# Space 与 Site Trigger Zone：Save、云保存和设备任务状态分析

日期：2026-09-14。状态：只读代码分析及阶段三方案补充；未修改业务代码、SDK、云数据或设备配置。

## 结论

**Space Trigger Zone 的 Save 先写本地，不先等云。** `SpacePathTriggerZoneController.saveAction()` 构造拓扑计划，调用 `ProximityLightingLifecycleCoordinator.commit`；后者在本地配置事务内标记 Space 待云上传，并保存 Zone/Group/Space。随后控制器取 `result.syncDatas`，有差异就进入 `SyncDevicesViewController` 发送设备任务，没有差异则发 `.common` 通知并返回。设备同步页完成一次运行后会发 `.device` 通知，Space 页面观察者据此排队云上传；返回 Space 页面时若仍有待上传，也可再次触发云同步。因此严格顺序是**本地目标先提交**，设备与云端各自推进；不能概括为“先云后设备”，也不能保证云一定在设备结束后才开始。

Space 的设备结果由当次同步页的任务状态及 SDK Node 观测状态区分：成功回包更新 Node 状态，任务行标成功；失败行标失败。回到 Space Trigger Zone 时 `updateSyncFailedState()` / `syncFailedBtnAction()` 重新按当前拓扑目标和 Node 的 Enable、Relay、邻居状态生成差异，仍有差异就显示 `Devices not synced` 并允许重试。`SyncResultCollector` 汇总当次页面的成功/失败操作，但该控制器没有保存一份可跨 Space、跨重启关联到目标版本的逐任务回执。当前邻近照明差异也未包含转发 AppKey 和 TTL，因此这一套不能直接用于 Site 阶段三。

**Site Trigger Zone 现有阶段二流程不同：** `SiteTriggerZoneCoordinator.synchronize()` 把完整 `extensionData` 提交云端，再经 GET 回读确认；`SiteTriggerZoneState.receive()` 在确认时保存每个 Zone 的 `previousMembers` / `targetMembers` 到 `deviceSyncChanges`。这只表达“成员目标已云确认且设备待同步”，没有设备任务行、ACK/失败、阻断原因或完成指纹。当前 Site 页面只用它显示设备待同步提示。

## 已核对的代码位置

| 环节 | 依据 |
| --- | --- |
| Space Save 的本地提交与跳转 | `SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift` 的 `saveAction()`；`SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift` 的 `commit()`、`apply()`。 |
| Space 云上传标记与排队 | `SunSmart/Main/Space/Controller/SpaceViewController.swift` 的 `markLocalChangePendingCloudSync()`、`commitLocalChangeForCloudSync()` 和变更通知观察者；`SyncExecutionSession.finishRun()` 完成时发 `.device`。 |
| Space 设备成功/失败与重算 | `SyncExecutionSession+Result.swift` 的 `applyResult()`、`finishOperation()`；`SpacePathTriggerZoneController.updateSyncFailedState()`；`Node+SyncData.getNodeSyncProximityLighting()`。 |
| Site 云确认后保留成员变更 | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneCoordinator.swift` 的 `performSynchronization()`；`SiteTriggerZoneData.swift` 的 `SiteTriggerZoneState.receive()` 和 `deviceSyncChanges`。 |

## 对阶段三 Save 后自动同步的建议

Site 保持**云确认目标在前、设备执行在后**。原因是 Site Zone 跨 Space、有多个编辑者；若先写设备而云保存失败，现场设备会应用一个未被 Site 云数据承认的版本。云先成功而设备部分失败是可管理状态，但必须显式记录，不能把两个“成功”合并成一个结果。

每次云端 GET 确认一个 Zone 目标后，先把该目标的操作 ID、完整旧/新成员、依赖快照、目标指纹与**按 Space 排好的设备任务**持久化，再跳转同步页并自动运行。每条 `Remove`/`Configuration` 任务至少绑定 siteId、zoneId、spaceId、稳定 nodeUUID、目标版本/指纹、步骤与来源；连接 Space 是临时执行步骤，不是可勾选设备任务。任务状态分为待执行、执行中、已确认成功、明确失败、结果未知、因连接/权限/前置步骤被阻断。只在 ACK 与目标状态校验均成立时标为已确认成功；超时或丢 ACK 不能伪装失败后盲目重发，也不能标成功。每次状态变化落盘，防止页面退出或进程中断丢失成功/失败归属。

聚合状态独立计算：云目标 `pending / confirmed / conflict`；设备目标 `pending / partial / completed / unknown / blocked`。同一 Space 内 Remove 和 Configuration 分别保留结果；一个设备的 Remove 成功、Configuration 失败时仅后者待重试，不抹掉前者。重试按**当前最新目标**重新预检并补齐必要 Key/Bind 前置步骤，已确认成功且目标指纹未变的任务跳过；旧版本迟到 ACK 不更新新目标。Site Zone 只在所有实际受影响设备的目标都确认应用后显示设备同步完成并清理相应 `deviceSyncChanges`；云保存成功但仍有失败时继续显示“Saved to cloud / Device sync pending”。

| Site 本次结果 | 页面与持久状态 |
| --- | --- |
| 云 POST 或 GET 回读未确认 | 不发设备命令；保留云 pending/冲突和成员草稿/快照，留在 Site 页面。 |
| 云已确认、部分设备成功 | 成功任务有目标指纹回执；失败/未知/阻断任务保留，Zone 与对应 Space/Path/Zone 显示需要同步。 |
| 云已确认、全部设备任务已确认 | 设备目标完成；按目标版本清理待同步变更，仍需现场联动验收才能宣称功能生效。 |
| Save 后目标再次改变 | 创建新目标版本；旧成功仅在设备最终目标指纹完全相同时可复用，不能让旧运行结果确认新版本。 |

现有 `deviceSyncChanges` 只保存 Zone 级成员前后值，应作为新任务账本的**输入和旧设备清理依据**，不应在跳转同步页时直接清空。账本至少要在本机跨重启恢复；若要求另一手机准确看到每台设备的已同步/失败状态，还需要服务端回执契约或可信的逐设备现场校验。当前 `siteprops` 完整对象接口没有已确认的逐任务回执和 CAS 契约，不能把本地成功结果自动当作跨手机云端共识，也不宜把每条 ACK 都直接写回完整 `extensionData`。

对 [阶段三同步流程修订方案](260914_1508_site_trigger_zone_stage3_sync_flow_revision.md) 的具体补充：操作栏 Save 的自动跳转发生在云 GET 确认且任务快照已持久化之后；同步页的设备失败不撤销已确认云目标，而是留下明确的 per-task 待同步状态。切 Zone/退出未保存弹窗中的 Save 仍按用户已确认的例外，只完成云保存并继续原导航，之后由 Sync 图标恢复设备同步。
