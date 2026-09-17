# Site Trigger Zone 设备待同步修复执行计划

日期：2026-09-14。状态：**用户已确认按本顺序执行，实施中**。本文以 [Save 后统一待同步分析](260914_1733_site_trigger_zone_save_pending_analysis_plan.md) 为问题基线，以 [阶段三同步流程修订方案](260914_1508_site_trigger_zone_stage3_sync_flow_revision.md) 中已确认的产品决策为约束；初版阶段三文档中“Save 后另点 Sync”的建议已被修订方案取代。

2026-09-14 进度调整：用户要求暂缓由其配合的真实设备测试，先完成 Debug Log，后续由用户自行测试并提供日志。3A 实物关卡仍未通过；目前只继续 3B 的只读准备，3C 设备发送和正式同步入口均保持关闭。详见 [测试 Site 范围](260914_1926_site_trigger_zone_3a_test_site_scope.md) 与 [目标指纹进度](260914_1937_site_trigger_zone_3b_fingerprint_progress.md)。

各阶段当前证据、未完成项及下一放行边界见 [阶段关卡核对](260914_2335_site_trigger_zone_stage_gate_audit.md)。

## 目标与完成判定

解决两个直接症状：Save 后不再把所有非空 Site Zones 无条件显示为“设备待同步”；每张 Zone 的同步入口不再指向缺少作用域说明的同一份全 Site 缓存预览。完整交付还必须让**操作栏 Save 的云确认目标真正进入可恢复的设备同步流程**，在按 Space 的设备配置经 ACK/必要读回确认后正确消除待同步状态。云保存、设备目标已应用、断开 App 后现场跨 Space 联动分别作为三个独立结果，不以其中一个代替另两个。

成功口径：两 Space 的真实设备可按各自 Group Profile 双向触发 Site Zone；Group Path、Group/Space Trigger Zone 的既有关系不被覆盖；部分失败、STOP、退出重进、连续 Save 均可恢复；无差异 Save 不制造任务；另一个手机没有可信设备证据时显示“未验证”，不误报“已同步”。

## 既定决策和本方案默认执行边界

- 复用并验证 Site 现有 Primary AppKey；以**整个 Space**为单位确定邻近照明转发 Key。任一设备已安装该 Site Primary AppKey，或本次 Site Zone 使该 Space 需要部署它，该 Space 的 Group Path、Group Trigger Zone、Space Trigger Zone 均以 Primary 为目标；非 Site 成员也可能需要 NetKey/AppKey/Model Bind。删除 Site Zone 不撤已安装 Key。
- Zone **操作栏** Save：完整云 `extensionData` POST 后由 GET 确认，冻结并落盘设备任务，再自动进入 `Sync device(s)`，预检通过后自动开始。**切 Zone/退出弹窗**中的 Save：只保存云端并继续原导航，设备任务保留，之后从同步图标恢复。云未确认、版本冲突或权限丢失时不发设备命令。
- 每个 Space 临时连接，先完成本 Space 必需的 Key/Bind 前置条件，再按 `Remove → Configuration` 执行，然后进入下一 Space；连接状态可见但不计设备进度。旧/新完整目标决定 Remove 范围，绝不按某 Zone 的旧成员直接清空节点邻居。
- 沿用此前已确认的测试边界：先在可回退测试 Site 建立仅含 `Space 1`、`Space 2` 的独立测试 Zone，不把已有跨 `Space 3` 的 Zone 当成两 Space 实物试验对象。指定 SDK 本地开发路径目前存在；真正修改 SDK 前仍需复核工作树。3A 实物关卡不通过时停止真实设备写入和正式入口发布。

## 分阶段实施

| 顺序 | 交付改动 | 阶段验收与停止条件 |
| --- | --- | --- |
| **P0 状态和文案纠偏** | 将 `SiteTriggerZoneViewController` 的 `!zone.isEmpty` 恒 pending 改为基于云目标、已知成员差异与**可信设备证据**的状态聚合。现有记录能证明有未应用变更时显示待同步；历史/远端非空 Zone 无本机回执或读回时显示“设备状态未验证”；空 Zone 无旧清理任务时无设备待办。初期图标明确标注“全 Site 只读预览”，修正 Save 提示，说明真实同步尚未开放。新增/修改英文与简体中文文案，保持旧数据兼容。 | 测试新建、未改动、重复 Save、空 Zone、旧成员待清理、另一手机首次打开和冲突场景；无一处把“无本地差异”直接判作设备成功。用 `MtestiPhone15` 检查卡片、图标、提示和中英文布局。此阶段**不发送设备配置**。 |
| **3A 云闭环与实物协议关卡** | 在上述测试 Site 再次确认完整、可解析且版本递增的 GET 回读；本次日志的 POST 200 和成功 Toast 可作线索，省略的 GET body 不能代替现场核对。建立并读回可恢复的原 Group Path 基线；核验 Primary NetKey/AppKey 身份、节点 Key 容量与 Bind、Vendor 转发 Key/TTL、邻居上限、跨 Space 无线连通，测试 App 断开、断电恢复和单遍部署中途失败。记录设备/固件兼容矩阵、读写结果和回退步骤，不记录 Key 值或新增 Auth 信息。 | 若服务端不能稳定提供权威目标，或固件/链路/原 Path 迁移不满足要求，**停在 3A**，输出问题和修正条件。若单遍按 Space 部署破坏原 Path/Zone，则改用“全部 Space 预部署 Key → 全部 Space 激活”的两轮连接方案，重新评估流程后再做发送器。 |
| **3B 完整目标与归属规划** | 在现有 `SiteTriggerZoneTopologyPolicy`、`TopologyReader`、`SyncPlanningPolicy` 的只读成果上补齐目标 TTL、明确的传输/转发 Key 引用、当前设备读回证据、旧/新完整目标差异、任务来源 Zone/Path/Space 及目标指纹。每个设备只有一个最终配置；Zone 页面显示本 Zone 及共享关系造成的实际影响，不把同一全 Site 计数复制到所有卡片。已删除 Zone 的旧清理工作归到 Site 级待办，不能因卡片消失而不可见。读回缺失、地址/权限/容量/Key 歧义时产出具体阻断原因。 | 纯逻辑用例覆盖跨 Space 同地址、Zone 交叠、非 Site 成员需 Primary Bind、共享邻居保留、删除旧 Zone、184/185 邻居、权限变化和无差异目标；缓存相等不能变成成功回执。 |
| **3C 任务账本与设备执行** | 在本机持久化 `siteId + operationId + 目标指纹 + spaceId + nodeUUID + Remove/Configuration 步骤`、来源和状态。状态含待执行、发送中、成功、失败、未知、阻断、已停止；连续 Save 保留最早仍需清理的旧关系依据。使用显式 Mesh/Space/传输 AppKey 会话发送必要 NetKey/AppKey/Bind、转发 Key、TTL、Enable/Relay/邻居命令；SDK 若已有可靠接口则复用，缺口才最小修改本地 SDK。每个 Space 开始和恢复时重验云目标、权限与会话；每步 ACK 与必要读回核对目标版本，旧 Space/旧操作回包不可确认新目标。 | 故障注入覆盖连接失败、ACK 丢失/迟到、进程重启、重复命令、权限撤销与目标变化；仅所有仍必要步骤确认后清理相应 `deviceSyncChanges`。STOP 不撤销已成功配置，未知结果重试前重新预检。 |
| **3D 同步页面和 Save 接线** | 复用现有 `SyncDevicesViewController` 的任务展示和操作方式，加入 Site 专用按 Space 分区与执行器；每个 Space 显示连接状态、Remove、Configuration、真实失败原因与可重试项。操作栏 Save 在云确认、任务持久化后自动进入并运行；云已确认但计划阻断仍进入页面展示原因而不发业务命令。无差异时显示 `No devices need syncing`，空 Zone 无清理任务时不弹空页。切换/退出弹窗 Save 只保留后续入口；已删除 Zone 的清理从 Site 级待办继续进入同步页。 | 真机检查自动跳转、STOP、部分失败提示、RE-Sync、页面退出重进、两种 Save 来源、中英文长文案和旋转/尺寸适配；进度只统计 Remove/Configuration 设备行，连接和 Key/Bind 子步骤不额外计数。 |
| **3E 防覆盖与发布关卡** | 将同一合并目标和 Space 级 Key 策略接入普通 Group Path、Group/Space Zone、Profile、Restore 与其他邻近照明写入口；目标不完整时阻断受影响的写入并保留原因。确认 Test、非空 Delete 的设备语义后再开放各自按钮；不顺手改变 Kinetic、Scene、Schedule 等无关配置。评估旧版客户端回写造成的覆盖风险。 | 聚焦测试和必要故障回归通过；直接 `xcodebuild` generic iPhoneOS 检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`、`Lumineux`，SDK 变更后逐 target 核查；`MtestiPhone15` 布局与真实设备测试覆盖跨 Space 双向触发、旧 Path/Zone 保留、断电/App 断开、失败重试、普通 Space Save/Restore。最终体验仍由人工确认。**3A～3E 全通过前不开放正式可发送 Site 同步入口。** |

## 状态契约和发布防线

- P0 的页面语义建议如下；“未验证”也应有可查看说明的状态入口，不能因现有 `TaskState.unknown` 不计入 `needsSync` 而直接消失：

| 条件 | P0 显示 | 完整同步实现后 |
| --- | --- | --- |
| 云目标尚未由 GET 确认 | 云同步待完成；设备命令禁用 | 同左 |
| 已确认新成员或旧成员清理依据，尚无对应设备回执 | 已保存到云端；设备配置尚不可用／待核验 | 自动进入同步页；未完成项显示待同步或阻断 |
| 既有非空 Zone、没有可信设备证据 | 设备状态未验证 | 读回后按完整目标显示待同步或完成 |
| 空 Zone 且没有旧设备清理依据 | 不显示设备待办 | 同左 |
| 最新目标全部经对应版本 ACK 和必要读回确认 | P0 不可能进入此状态 | 设备同步完成；清理该目标的待办 |

- **云状态**以 GET 回读确认的完整 `extensionData`、Site 身份和版本为准；POST 回显与 Node 缓存都不能替代云确认。同一时间戳不同内容、缺字段、旧草稿与服务器失配时沿用现有归档/阻断策略，不能为了启动设备任务再次上传旧目标。
- **设备状态**按最新完整目标和可信读回/对应版本回执判定。`deviceSyncChanges` 是旧成员清理依据，不是设备已成功的证明；不能简单删除 `!zone.isEmpty` 后把其他设备都标为完成。共享设备使未编辑的 Zone/Path 实际受影响时，应标注来源并共同显示待同步；无可信证据但也无已知差异时显示“未验证”。跨手机完成状态若没有服务端逐任务回执，只能重新读回或保持未验证，不能用本机账本伪装云端共识。
- **设备下发**只针对已确认云版本与完整拓扑；阻断原因区分服务器/权限/连接/固件能力/容量/设备状态未知。若发生部分成功，保留真实现场状态和待办，不声称自动回滚。每个阶段的诊断 Log 仅在 `#if DEBUG` 内，所有新增用户可见文案同时本地化英文和简体中文。

## 实施组织与评审点

按 P0 → 3A → 3B → 3C → 3D → 3E 顺序提交聚焦改动；每阶段记录代码范围、测试结果、设备状态和剩余阻断到 `docs/`。P0 可独立交付真实状态表达；3B 的只读完善可与 3A 的准备并行，但设备写入必须等 3A 通过。若 3A 需要更改一次/两次连接的既定流程，先更新本方案及验收用例再开发发送器。正式设备入口仅在 3E 验证完成后放开，不以构建成功或预览计数作为验收。

确认记录：用户已回复“确认按这个顺序执行”。测试 Zone 只覆盖 Space 1/2、操作栏 Save 自动同步、Space 级 Primary 策略和 3A 未通过不开放设备写入，均沿用此前已确认的决定。
