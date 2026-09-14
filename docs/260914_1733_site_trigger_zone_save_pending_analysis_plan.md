# Site Trigger Zone Save 后统一待同步：原因与修复规划

日期：2026-09-14。范围：依据用户提供的 Save 日志、当时工作树代码和既有阶段三方案进行只读分析；这是修复前的问题基线。后续实施进度见 [P0 与 3A/3B 进度](260914_1806_site_trigger_zone_p0_and_3a_progress.md)。

## 结论与日志解释

1. 本次操作栏 Save 先将页面成员草稿提交到本地 Zone 状态，协调器再 GET 当前 Site、POST 完整 `extensionData.triggerZones`，最后再次 GET 核对。日志中 POST 的 HTTP 200、业务码 200 只证明服务端接受请求；用户实际看到成功提示，说明当前代码最终走到协调器的成功分支。该分支在按行 Save 时要求 GET 回读的完整 `serverData` 与提交目标一致。由于日志省略了最后 GET 的 body，不能仅靠日志文本独立核对每个成员，但可以确认没有在这条路径中发送 Site Zone 配置命令。POST 携带全部 Zone 是完整 `extensionData` 替换接口的要求，不表示每张 Zone 都被本次单行 Save 改动。
2. 添加设备时出现的 `AttentionSetUnacknowledged(attentionTimer: 5)` 对应页面 `MeshAPI.identify(address:)`，是选中设备后的闪灯识别。它在 Save 之前发出，不是邻居、转发 Key、TTL 或 Model Bind 的 Site Zone 同步。
3. 当前页面直接以 `!zone.isEmpty || deviceSyncChanges 包含该 zoneId` 判定设备待同步；成功 Toast 又使用同一条件。因此任何非空 Zone，即使本次没有编辑、设备以后真的配置成功、或者再次按 Save，都会继续显示 `Saved to cloud. Device sync pending.`。云端 `pending` 与设备待同步是两个状态；前者可被 GET 消除，后者目前没有真实设备成功回执来消除。`deviceSyncChanges` 仅在云回读确认成员变化时保留旧/新成员依据，反向改回原成员可抵消差异，但设备执行完成不会清除它。
4. 所有 Zone 的同步图标都接到同一个无 Zone 参数的 `showDeviceSyncPreview()`。它读取**全部已云确认 Site Zones 与全部 Spaces**，对本机 Node 缓存和完整目标做只读比较；弹窗只有 OK，没有连接、发送、STOP 或重试入口。缓存观测的 `forwardKey`、`ttl` 固定为未知，证据类型为 `.cache`；规划器会标记未验证/缺少状态，并可能把启用的设备列为 `Configuration` 候选。故该预览的计数是全 Site 的推测性任务，不是所点 Zone 的专属待办，更不是已确认的设备差异或执行结果。
5. 现阶段 Site Zone 的设备同步**尚未实现**。现有 Save、页面重进、点击图标或重复 Save 均无法触发真实 Site Zone 同步。设备未配置前，不能根据云保存成功推断跨 Space 触发生效。现有 Space Trigger Zone 的 Sync Devices 流程也不能直接当作 Site 的替代入口，因为它不处理 Site 的完整合并目标、Space 级 Primary AppKey、跨 Space 顺序和持久逐任务回执。

## 直接代码依据

| 观察 | 位置 |
| --- | --- |
| Save 提交并在 GET 后核对所选 Zone 的完整云目标 | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneViewController.swift` 的 `saveZone` / `synchronize`；`SiteTriggerZoneCoordinator.swift` 的 `performSynchronization` |
| 云确认时记录成员旧/新值，当前无设备完成回执 | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneData.swift` 的 `SiteTriggerZoneState.receive` / `recordDeviceSyncChanges` |
| 非空 Zone 恒为设备 pending、Toast 共用此条件 | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneViewController.swift` 的 `reload` / `synchronize` |
| 所有图标共用全 Site 弹窗且只有 OK | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneContentView.swift` 的 `syncTap`；`SiteTriggerZoneViewController.swift` 的 `showDeviceSyncPreview` |
| 缓存观测缺少 Key/TTL、规划只读 | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneTopologyReader.swift` 的 `read`；`SiteTriggerZoneSyncPlanningPolicy.swift` 的 `makeRecoveryPlan` |
| 添加设备时发送识别消息 | `SunSmart/Main/Site/TriggerZone/SiteTriggerZoneViewController.swift` 的 `addMember` |

## 修复顺序

1. **先修正状态语义和预览范围。** 云状态只表示 POST+GET 确认；设备状态拆成未验证、待执行、部分完成、阻断、已确认完成。不能只把非空恒 pending 改成“只有 `deviceSyncChanges` 才 pending”，否则另一手机或历史云 Zone 在没有本地差异记录时会被误标为已同步。每张 Zone 的图标要么明确显示“全 Site 预览”，要么携带 zoneId、源关系和受影响设备范围，同时在共享 Space/设备使其他 Zone 真正受影响时显示依赖原因。只读阶段的文案应明确“设备配置尚不可用，预览未验证”，避免暗示存在可操作的 Sync。
2. **通过阶段 3A 实物协议关卡。** 在可回退测试 Site 核对 Primary NetKey/AppKey/Model Bind、设备 Key 容量、转发 Key 与 TTL 的真实读写、跨 Space 感应和现有 Group Path/Zone 过渡影响；未通过之前保持发送入口关闭。当前日志中的识别消息不能充当此验证。
3. **冻结完整目标并持久化任务。** 云回读确认后，合并全部 Site/Space/Group Path/Trigger Zone 关系，按 Space 级 Primary 策略生成唯一设备终态和来源归属；保留旧成员清理依据、目标版本/指纹、操作 ID、权限及拓扑快照。先只读预检；缺地址、权限、Key/Bind、容量或设备状态证据时标明阻断，不发送不完整命令。
4. **实现跨 Space 执行与回执。** 操作栏 Save 云确认后自动进入 Sync device(s) 并按 Space 顺序执行其 Remove、Configuration；切 Zone/退出弹窗中的 Save 仍只完成云保存并继续导航，之后可从同步图标恢复。连接 Space 是临时步骤；任务状态和 ACK/读回按目标指纹落盘，支持 STOP、失败/未知重试和迟到 ACK 隔离。仅在所有仍必要的设备步骤确认到最新目标后，清除对应待同步依据并显示完成；不把缓存相等或请求发出当作成功。
5. **防旧入口覆盖并验收。** 将合并目标纳入普通 Group Path、Group/Space Zone、Restore 等邻近照明写入口，避免后续单 Space 保存覆盖 Site 关系。验证两 Space、多 Zone 共享设备、无差异 Save、部分失败、再次 Save、跨重启恢复、非 Site 成员 Key/Bind、旧客户端影响；检查所有 SDK 引用 target 的构建及允许真机的布局与实际联动。最终体验仍需人工确认。

修复顺序与 [阶段三同步流程修订方案](260914_1508_site_trigger_zone_stage3_sync_flow_revision.md) 和 [Save 与同步顺序分析](260914_1532_space_site_trigger_zone_save_sync_order_analysis.md) 一致。本轮仅运行 `bash scripts/check_site_trigger_zones.sh`，现有数据、UI 策略、候选和只读拓扑测试均通过；它们不能证明设备同步已实现或现场联动成功。
