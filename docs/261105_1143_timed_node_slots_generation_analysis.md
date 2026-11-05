# Timed nodeSlots.generation 移除结果

2026-11-05，已按用户确认的方案完成 App 和所用本地 SDK 改动。**旧 generation 自动忽略，下一次正常保存、导出或上传不再携带；新任务接管相关旧任务，旧任务不能继续回写。** 未提交、未发布，真机与服务器联调待验收。

## 1. 最终行为

| 操作/数据 | 现在的处理 |
| --- | --- |
| 添加定时 | 不再创建 generation；按原规则分配设备 slot |
| 更新定时 | 不再更新或比较 generation；同设备、同 slot 的新任务接管相关旧任务 |
| 删除定时 | 不依赖 generation；pendingRemoval 仍占槽，设备清理成功后才释放 |
| 旧项目 | 忽略旧 generation，接受 UUID、null、数字、对象、非法字符串或缺失；其他业务字段仍严格校验 |
| 保存、分享、备份和上传 | 仅去除 schedules[].nodeSlots[].generation，不删除其他模块同名字段 |
| 同步时机 | 不强制全量上传；下一次正常 Space/Site 上传请求不携带该字段 |
| 重启 | 不恢复已取消的内存任务，从现有持久配置重新生成必要同步任务 |

保留 `identity`、`slot`、`state` 和 `timedSchemaVersion=2`，不改数据库列、不清库、不重分配现有槽位。

原字段于 2026-10-08 的 `cf99bbd1` 引入，用于区分同槽前后两次绑定、拦截旧回调，并参与云端比较。**占槽保护由 pendingRemoval 负责；本次移除的是持久化的绑定代次。**

## 2. 新任务如何接管

App 新增 `TimedSchedulerTaskCoordinator`，SDK 新增仅存在于内存的 `MeshSchedulerTask`，不增加替代性的云端字段或数据库代次。

- 按 **meshUUID + networkID + 完整设备配网身份 + slot** 区分任务，collection 使用独立范围。其他设备、其他 slot 不受影响。
- 同一次操作的多 Model 清理与写入共用所有者；仅构造消息或页面预检不会取消正在执行的任务。
- 正式入队时接管，立即取消相关旧任务，移除 Proxy 和底层队列消息，停止实际异步发送与重试；旧发送停止后才放行后续发送。
- 发送前、响应、App 回写、完成回调和下一设备批次都检查有效性。旧成功/失败不回写、不回滚新 enabled、不删除新 Schedule，也不重新排队或续发旧批次。
- 批次回调按提交归属保存，避免后来追加的任务覆盖原回调；队列删项后按消息对象识别正在执行或准备中的任务，不依赖旧索引。
- 云端完整配置替换、网络重新加载、设备移除同样使旧任务失效；配置保存失败仍由原有持久配置和重试路径恢复。
- 保留当前操作的启停全失败回滚、部分成功和清理失败重试。清理进度保存不会取消操作自身。

可靠发送内部使用运行对象识别取消和超时，避免同地址、同参数的旧失败取消新请求。已取消任务的 Scheduler 物理观察不能继续当作可信快照，必要时重新完整读回。协调器和观察器只保留各资源最后的任务对象用于拦截旧回调，替换或网络失效时释放；不积累任务历史。

**无线报文已经发出后无法撤回。** 本次保证 App/SDK 的任务、重试和回写隔离，最终设备内容仍需真实读回验收。

## 3. 旧数据和历史恢复状态

`TimedSchedulerPayloadPolicy` 统一处理路径限定去字段、历史比较数据规范化和比较。实际 Space 上传、Site 新建/上传出口同时处理原始字典，避免旧备份或恢复上传重新带上该字段。

历史 `timedConfigurationBaseline`、prepared/accepted submission 的 `timedConfiguration` 在读取时幂等规范化，沿用现有原子保存。submission ID、timestamp、phase、权限、设备身份及 Space 自身 generation 保持原值；保存失败可重试，损坏数据不会被当作成功证据。

全配置快照也包含 schedules，因此比较版本从 6 升到 7。旧哈希只有在找到原始备份并验证其完全匹配后才能重建；缺失、错误或不属于本 Space 的备份仍走原有保护流程，不凭空放宽冲突检查。历史备份原件不改写。

只含目标 generation 差异时视为相同；slot、state、identity、业务时间或其他配置差异仍有效。

## 4. 主要改动位置

| 范围 | 入口 |
| --- | --- |
| 属性、旧数据、比较 | TimedSchedulerSlotPolicy.swift、SpaceConfigurationSafety.swift、SpaceConfigurationIntegrityPolicy.swift、NetowrkReqeustApi.swift |
| App 任务接管 | TimedSchedulerTaskCoordinator.swift、ScheduleServer.swift、Node+MessageHandles.swift、TimedSchedulerBindings.swift |
| 同类入口及失效 | SceneDeletionCascade.swift、SyncExecutionSession+Result.swift、Database.swift、ImportData.swift、MeshNetwork+SunSmart.swift |
| SDK 所有者、队列和读回 | MeshSchedulerTask.swift、MeshSchedulerObservation.swift、MeshMessageManager.swift、MeshProxyMessageCommand.swift、Node+Messages.swift |
| SDK 实际发送/取消 | NetworkManager.swift、AccessLayer.swift；使用可保留的原生 async 发送 Task，不改 callback 包装接口 |

新增 App 文件已加入六个 target。正式 project 仍引用远端 SDK `release`，未改为个人绝对路径。

## 5. 验证结果

以下回归在本次改动上通过：

| 执行位置 | 脚本 | 主要覆盖 |
| --- | --- | --- |
| App | check_timed_task_replacement.py | 正式接纳、同槽替换、多 Model、其他 slot/collection 保留、旧构造消息、生命周期失效、旧批次回调、启停回滚和部分成功 |
| App | check_timed_device_slots.py | 旧字段各类值、真实 Codable、Space/Site 请求参数及 JSON 编码、严格业务比较 |
| App | check_timed_slot_persistence.py | 实际 SQLite 写入/重开/保存、分配失败回滚、pendingRemoval、迟到回写及设备身份保护 |
| App | check_space_recovery_receipts.py | 真实恢复文件和原子保存、prepared/accepted 旧回执、升级失败重试与重开、完整性和权限检查 |
| App | check_scheduler_cloud_roundtrip.py | 70 个设备/140 个 Model 容器往返和 SDK 重载 |
| App | check_timed_delete_result.py | 删除失败、旧响应、确认清理后完成 |
| App | check_timed_empty_target_cloud_sync.py | 空 Group/Scene 目标上传意图及旧上传回执 |
| App | check_scene_deletion_cascade.py | Scene 级联回归，205 项通过 |
| SDK | check_scheduler_task_replacement.py | 真实发送注册、定向取消、可靠计时器、取消回调锁隔离、同端点交接、旧超时、Proxy 队列与回调归属 |
| SDK | check_group_control_session.py | 通用 Group 队列与 Scheduler 出队取消、busy 重试，22 项通过 |
| SDK | check_scheduler_readback.py | Scheduler 参数/来源匹配、旧缓存失效及完整读回，38 项通过 |

脚本通过 `python3 scripts/<脚本名>` 执行；SQLite/快照脚本使用可写的 Swift/Clang module cache。另通过依赖检查脚本、工程 plist 检查和两工作树 `git diff --check`。

夹具执行生产编解码、SQLite、恢复存储、协调器/业务回调及抽取的发送/队列逻辑；无线传输、部分节点/UI 环境和时钟采用可控边界。可靠计时器、发送注册与取消分别有行为用例，但并非真实 BLE 运行验收。

构建：SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux、HSmart 六个 scheme 的 Debug generic iOS 均通过。最后一次 SDK 内部取消锁修正后，相关回归和代表 target SunSmart 已重新通过；该修正不改变品牌接口或文件归属。使用 `SunSmartLocal.xcworkspace` 和固定 DerivedData 串行构建，`-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`，未使用 Simulator。编译仍有已有资源重名、废弃 API 等警告。

## 6. 发布依赖与人工验收

- App：`feat/device-scene-261028`，基线 `2354ac91db5f02820249b860dcbf08964477fe6a` 加本次未提交改动。
- SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，基线 `4b4c0f56fa3e686dfb856923f8e90b0eae95b0e8` 加本次未提交改动。App 发布前须先将这些 SDK API/行为发布到正式依赖；本地编译不代表远端 release 已具备它们。
- 仍强制要求 generation 的旧 App 可能拒绝新版数据，需同步升级；本次没有后端版本隔离或部署。

最短人工验收：

1. 打开带旧 generation 的项目，新增/修改/删除定时并触发正常上传，确认 Space 和 Site 请求中的 nodeSlots 均无该键，重启后展示保持一致。
2. 连续修改同一定时并快速切换启停；最终只保留最后意图，其他设备/slot 的任务继续完成。
3. 断开设备使删除失败，再重连重试；pendingRemoval 不提前释放，清理后各 Model 的物理 slot 与 App 一致。
4. 同步中替换云端配置或切换网络，等待旧响应；旧任务不得恢复旧配置或继续下一设备，重进后可从当前配置继续同步。

## 7. 服务器最小契约

服务器新增、更新、删除定时无需再生成、保留或比较 nodeSlots.generation；返回旧字段时新版 App 自动忽略，下次上传移除。

要让 App 展示和设备结果一致，仍须配套维护 `space.schedules`（含有效 identity/slot/state）、`space.spaceData.timedSchemaVersion=2`、`node.schedules`、`node.custProps.schedulerModelStates`、合适的 `space.updateTimestamp` 及关联 Group/Scene。`node.schedules[].id` 是设备物理 slot，不是业务 ID；物理快照只能记录设备已确认结果。

服务器/网关团队负责上述外部契约及设备执行一致性，本次仅实施 App 和所用 SDK，未修改外部代码、未部署，未执行真实服务器或 Mesh 联调。

## 8. 2026-11-05 审查问题修复

本轮修复两项 P2，沿用上述 App/SDK 分支及基线，保留既有未提交改动，未提交或发布。

- **正常清理被显示为失败**：同步完成回调在 Proxy reset 后释放 `pendingRemoval` 绑定并保存，原协调器把绑定消失当作新意图，取消刚成功的任务。现在保留发送时的绑定快照，仅在非 collection、原绑定为 pendingRemoval、目标/下发参数未变、队列空闲且所有 Scheduler Model 已确认该 slot 为空时保留回执。任务仍受槽位复用、配置替换及网络生命周期失效约束；没有新增持久字段。
- **Scheduler 失败后仍继续删除 Group**：生产发送完成回调继续报告当前失败，随后检查 `continuous`。为 false 时使用原 `breakSendMessages()` 标记后续消息失败并结束批次；为 true 时继续发送。

两个新增行为用例均先在修复前复现失败，修复后通过。App 用例执行生产协调器和 `releaseClearedBinding`，覆盖双 Model 成功回执、保存失败/重试、未知/部分清理、busy、缺失映射、配置替换及槽位复用。SDK 用例执行生产完成回调及中断/结束方法，覆盖超时和传输错误、continuous 两种值、后续失败回调、成功、取消和 reset 后迟到回调。同步 Session 原夹具缺少已有的 `schedulerTask`，本轮补齐并使用生产任务对象验证当前成功与取消后拒绝回写。

本轮通过 7 个回归脚本：

- App：`check_timed_task_replacement.py`、`check_timed_delete_result.py`、`check_timed_slot_persistence.py`、`check_sync_execution_session.py`。
- SDK：`check_scheduler_task_replacement.py`、`check_group_control_session.py`（22 项）、`check_scheduler_readback.py`（38 项）。

SQLite 脚本首次因默认 Clang module cache 不可写而阻塞，指定可写的 `CLANG_MODULE_CACHE_PATH` 和 `SWIFT_MODULECACHE_PATH` 后通过。两个工作树的 `git diff --check` 均通过。组合用例的保存结果、设备观察、传输和时钟仍采用可控边界；SQLite 保存/失败/重开由独立现有脚本覆盖，不代表真实 Mesh/UI 验收。

本轮 SunSmart 构建通过：`SunSmartLocal.xcworkspace` 映射到上述 `one-dev`，Debug、iphoneos、generic iOS、`CODE_SIGNING_ALLOWED=NO`，DerivedData 为 `SunSmart-feat-device-scene-261028-cli`。命令退出 0，Xcode 构建记录为 0 errors / 99 warnings。两处为各品牌共用的内部逻辑，没有新增 SDK 公共 API、资源或品牌配置，因此本轮仅构建代表 scheme SunSmart。

真机与云端联调本轮未执行。最短人工验收：

1. 在同步页面完成带 pendingRemoval 的定时清理：确认多 Model 均清空，页面显示成功；退出重进后不再生成该清理任务。
2. 删除 Group 时让 Scheduler 清理超时/失败：确认后续解除订阅不发送，清理状态保留；恢复连接重试后正常完成。

SDK 修复仍在本地未提交差异中，发布前需随原任务的 SDK 改动进入正式 `release` 依赖。
