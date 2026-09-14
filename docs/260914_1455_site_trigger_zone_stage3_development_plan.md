# Site Trigger Zone 阶段三：设备同步与跨 Space 联动开发方案

日期：2026-09-14。状态：**初版；后续确认及 Save 后同步流程以[修订方案](260914_1508_site_trigger_zone_stage3_sync_flow_revision.md)为准。** 本次仅规划，未修改业务代码、SDK、云数据或设备配置。按用户最新说明，阶段一和阶段二均已执行完成；阶段二既有记录中的“发布验收未完成”是当时状态，不作为本方案对当前交付状态的判断。

## 目标与完成口径

把阶段二已确认到云端的 Site Zone 成员变更，转换为可预检、可执行、可中断恢复的设备配置任务。两个或更多 Space 的真实设备在 App 断开后仍按各自 Group Profile 触发 Site Zone；原 Group Path、Group/Space Zone、Kinetic 等配置不能被新的 Site 同步覆盖。云保存、设备已配置、现场联动验证三种结果分别呈现。只在真实设备与服务端验收通过后，才宣布“加入并生效”。

阶段三不是单次页面接线：建议依次交付 **3A 协议可行性 → 3B 合并目标 → 3C SDK/传输与账本 → 3D 同步入口和恢复 → 3E 生命周期与发布验收**。3A 若发现固件不支持目标转发或现场物理链路不足，停止设备写入实现，先形成协议/固件修正结论。

## 已确认基线与直接影响

| 现状 | 阶段三必须补齐 |
| --- | --- |
| 阶段二在云端 GET 确认后，将每个 Zone 的 `previousMembers` / `targetMembers` 留在 `SiteTriggerZoneState.deviceSyncChanges`；界面显示设备待同步。 | 将成员差异升级为有版本和来源的设备目标与任务；只有目标全部确认应用后才能清除对应待同步记录。连续多次 Save 需保留最早未清理成员与最新目标。 |
| `ProximityLightingTopologyPolicy` 当前按单 Space 的地址和 Group/Space Zone 生成邻居、Enable、Relay 目标，上限为 184 个邻居；不含 Site 关系、Key、TTL。 | 用稳定 `(siteId, spaceId, nodeUUID)` 身份建立跨 Space 图，再投影每个 Space 的实际设备地址；Group Path、Group/Space/Site Zone 共同求最终目标。缺失/歧义身份或容量超限时禁止下发，不能按同数值短地址跨 Space 合并。 |
| `NodeSyncData` 的邻居差异比较不含转发 Key/TTL；`SyncDevicesCellModel`、`GroupServer` 和共用消防同步入口直接取全局 `currentApplicationKey`。 | 目标显式包含转发 AppKey、TTL、传输上下文。单独变化也生成任务；所有会写邻近照明配置的入口使用同一合并目标，防止后续 Space Save/Restore 将 Site 关系覆盖。 |
| `SyncDevicesViewController` 有 Group Path、Space Zone 类型，但没有 Site 跨 Space 类型；现有页面 Session 结果不足以覆盖跨重启设备级状态。 | 复用展示与执行骨架，加入 Site 专用按 Space 分区、稳定任务 ID、步骤依赖和持久化回执。STOP、失败、未知结果、重试分别表达。 |
| 指定本地 SDK 路径 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` 已存在；工程中五个品牌 target 引用 SDK。 | 修改 SDK 前核对该路径、版本和工作树；SDK 变更后检查所有引用 target 的编译与相关运行流程。不得靠页面切换推断发送所用 Key。 |

已有 [Key 作用域与权限分析](260909_0959_site_trigger_zone_key_scope_permissions_analysis.md) 给出的约束继续有效：同一 Group Path 的设备必须同转发 Key；共享设备及交叠的 Zone 建议并入同一个 Key 范围；触发仍遵循所属 Group Profile；编辑 Zone 需要其全部成员 Spaces 的 Owner/Editor 权限，而设备下发还需覆盖**实际写入的额外 Spaces**。本方案不新增认证数据，也不把 `currentApplicationKey` 的兜底值当作已验证的目标 Key。

## 3A：协议、现场与云闭环关卡

1. 在可回退的测试 Site 建立至少两个 Space，每个 Space 至少一条三灯 Group Path 和一个合格感应源；记录设备 PID、固件、原有 Key/Bind、转发 Key、TTL、邻居及可达 Proxy，不在正式 Site 试探写入。先只读确认阶段二 `extensionData` 全量保存、GET 回读和 `deviceSyncChanges` 重进恢复。若 2026-09-14 的 [SAVE 失败日志分析](260914_1445_site_trigger_zone_save_failure_log_analysis.md) 仍对应当前版本，先定位回读结果；POST 回显不能替代云确认。
2. 依据现有 Primary NetKey/AppKey 和各 Space Key 的真实绑定，验证设备能保留 Space 业务 Key，同时安装/绑定统一转发 Key；分别测试一条 Path 全员同 Key、跨 Space 双向触发、Relay/TTL、重启及 App 断开。确认单设备一份邻近照明转发配置、消息由固件使用指定 Key 的实际行为、最大邻居和 Key/Bind 容量。
3. 对照无线覆盖核对中继节点是否具备必要 NetKey 与 Relay 能力。共享 Key 不等于跨楼层/隔墙可达；现场链路不足时不得把配置 ACK 当作联动通过。

**关卡输出：** 设备/固件兼容矩阵、可复现命令与结果、统一 Key/TTL 取值、迁移影响范围和失败回退办法。未通过即停在此关卡，不上线可发送 Site 配置的入口。

## 3B：跨 Space 合并目标与预检

- 从已云确认的全部 Site Zones、受影响 Spaces 的 Group Path/Group Zone/Space Zone、当前 Group Profile 和设备快照构建只读计划。图节点用稳定身份，地址仅在目标 Space 当前快照内解析；同一设备出现多处只生成一份最终配置。整条 Group Path 同 Key；共享设备导致的连通范围合并，Site 关联范围统一转发 Key，完全无交集的 Space 设备维持原模式。对重复地址、失效 Group/Profile、设备搬组、Zone 交叠、断点 Path、184/185 邻居边界给出明确失败原因。
- 每设备目标至少记录 site/space/mesh 身份、目标设备及元素、来源关系、Enable、Relay、邻居、TTL、转发 AppKey 引用、所需 NetKey/AppKey/Model Bind、目标指纹与依赖版本。成员移除或 Zone 删除应比较**旧、新完整合并目标**，不能按旧成员列表直接清空邻居或撤 Key。初期保留已安装 Key，退出 Site Zone 后仍按完整剩余关系决定转发模式，避免逐节点回退破坏 Path。
- 预检完整依赖快照、设备能力/容量、当前云版本、编辑权限及实际写入 Space 的占用状态；缺项则保持 pending 并给出可操作原因。阶段二接受的 `siteprops` 无 CAS 并发风险仍存在；设备规划不能把 GET→POST→GET 当作原子锁。发布期间建议同一 Site 串行编辑、编辑前刷新，执行前重新计算目标版本。

**完成判定：** 纯逻辑测试证明无 Site Zone 时结果与现有单 Space 计划一致；跨 Space 同地址、多 Zone/Path 交叠、变更 Profile、删除/地址复用、容量超限、缺失或失权 Space 均产生确定目标或安全阻断。

## 3C：显式传输、顺序与持久化回执

- 在指定本地 SDK 中先检查现有显式 AppKey/NetKey 发送能力；仅补足必要的发送适配。把“本次配置命令的传输 Key”和“设备后续转发使用的 Key”分开，任务绑定目标 Mesh UUID、Space NetKey、传输 AppKey、节点/Model 与计划版本。每步发送和 ACK 回来时重校验会话身份，旧 Space 的回包不能确认新任务。若 SDK 已有等价可靠接口，直接复用，不另造通道。
- 按依赖执行：先使统一范围内的必要接收节点具备 NetKey/AppKey/Model Bind，再下发转发 Key、TTL 和合并邻居；只有全范围接收条件满足才激活新的跨 Space 目标。按 Space 串行切换 Proxy；不让异步 Site 拉取或页面全局 `currentApplicationKey` 改变计划意图。设备无原子提交能力，部分成功时保留现场不一致状态与后续恢复任务，不声称自动回滚成功。
- 持久账本以 operationId、目标指纹/版本、稳定节点身份和步骤为键，记录待执行、发送中、ACK 成功、失败、结果未知、停止及时间。ACK 丢失只表示未知，重试前查询/比较已知状态并重新预检；成功回执不得确认较新的目标。仅在所有仍必要步骤确认后，将对应 `deviceSyncChanges` 标为已应用/可清理。账本应保护已保存成员变更的旧清理依据，覆盖进程中断与连续 Save。

**完成判定：** 注入连接切换、ACK 丢失/迟到、重复 Key、权限撤销、进程重启和目标更新，验证幂等恢复、无越权写入、无旧版本误确认；单独 Key/TTL 差异必须形成任务。

## 3D：Site 同步交互与恢复

- 云保存继续独立完成；成功后保留设备待同步状态，用户从 Site Zone 的 Sync 入口进入按 Space 分区的同步页。首次同步与已完成云保存的重进恢复走同一计划入口；仅云端已确认且预检通过才开放发送。进度按设备数显示，设备详情显示步骤与原因。
- 复用现有 Sync Devices 的 `Configuration` / `Remove`、STOP、选择后 RE-SYNC 交互。STOP 只停止**后续**发送，已在途结果仍归属原 operationId；返回页面保留 pending/失败/未知状态。选择重试项时自动包含必要的 Key/Bind 前置步骤；不能只重发最后一条邻居命令。普通网络失败、权限不足、设备能力不足和容量超限分别显示，不把它们归为“通信范围”。
- 非空 Zone Delete 在完成清理规划后开放：先保存删除意图与旧成员/目标证据，再安排设备清理；离线成员与失败清理保留待办。Test 只有在目标设备版本已同步且现场验证语义明确后开放；阶段三前半程继续禁用。

**完成判定：** 两 Space 部分失败、STOP/退出/重进、选择重试、再次 Save 产生新目标均能正确展示、恢复和隔离旧任务；英文和简体中文文案完整，生产 UIKit 布局在允许的真机核对。

## 3E：旧入口防覆盖与发布验收

- 将共享合并目标接入 Group Path、Group/Space Zone、Group Profile、普通 Sync Devices、GroupServer、设备 Restore 与延迟同步等邻近照明写入口；受影响节点的 Site 投影缺失或版本不可靠时阻止该部分写入并保留待同步原因。仅限邻近照明字段；Kinetic Publication、Scene、Schedule 等仍沿原业务 Key 与路径。Profile 切出、成员增删、设备替换/地址复用、Space 删除/移出、导入恢复和多 Zone 重叠都需重新规划，旧成员清理证据不能随本地对象删除而消失。
- 分层验证：逻辑/契约测试与脚本；直接 `xcodebuild` 的 generic iPhoneOS 构建检查 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 受影响 target；真机布局/交互；至少两个 Space 真实设备做双向感应、Path/Zone 交叠、断电重启、App 断开、失败重试、保存后普通 Group/Space Save 与 Restore 回归。SDK 变更后逐一检查五个引用 target 的相关运行流程。最终体验由人工确认。
- 发布前确认旧版 App 对受影响设备的写入约束。旧客户端可能回写 Space-only 邻居或转发 Key；仅靠新客户端与 Site 云数据无法阻止。没有可执行的现场升级/使用规范或固件保护时，不宣称旧版兼容。

## 需要确认的实施取舍

1. **Key 策略：** 建议先验证并复用 Site 现有 Primary AppKey 作为 Site 关联范围的统一转发 Key，不新建专用 Key；各 Space Key 保留用于原业务与配置传输。若现有 Primary Key 的分发范围或固件能力不满足要求，回到本关卡重新设计，不静默生成新 Key。
2. **发布节奏：** 3A 必须先用测试 Site 与实物验证。3B～3C 可独立评审，但在 3D 和 3E 全部通过前不开放正式设备同步入口；阶段二云保存与“设备待同步”继续可用。
3. **Save 与 Sync：** 建议 Save 只确认云数据，不自动发送设备命令；用户从明确的 Sync 入口启动。STOP 不撤销已应用配置，失败或未知结果保留并可选择重试。
4. **退出和重叠：** 建议允许 Site Zone 与现有 Path/Zone 共享设备，由合并目标决定唯一设备配置；删除最后一个 Site Zone 后保留已安装 Key，并仅在完整剩余关系要求时调整转发模式。涉及真正撤 Key、失效 Group 替换、已删除/移出 Space 的清理授权，需另定产品/服务端规则后再开放相应修复操作。

用户确认上述四项后，按 3A 起步。若对任何一项有不同选择，先更新本方案和验收场景，再开始相应设备写入开发。
