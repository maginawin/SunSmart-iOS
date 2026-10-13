# Editor 无法恢复 Space：Timed 格式丢失分析与修复方案

日期：2026-10-13。修订：14:38，按用户最新指示改为“缺失字段补默认值，保留并展示全部定时”。状态：App 端简化修复、7 项相关离线回归和 SunSmart generic iOS Debug 编译已通过；未修改 SDK、服务端或现场数据。

## 1. 结论

直接原因已用现场 JSON 和当前生产校验代码复现：服务器返回 **17 条业务日程（id 0…16），但缺少 `spaceData.timedSchemaVersion` 和全部 `schedules[].nodeSlots`**。App 将缺版本的数据按 legacy v1 解释；v1 中业务 id 就是设备槽位，只允许 0…15，因此返回 `invalidTimedPayload`。修复前的 v2 支持超过 16 条业务日程，但导入时要求每个目标都有设备槽位映射。

当前 editor 本地仅有 Space 身份及网络信息，配置尚未完成初始化。重试持续读到相同不完整格式，无法恢复。`Saved Space Copies` 是副本导出分享入口，没有执行恢复的代码。无需先 Leave Space；离开后再加入也不能修复服务器上的同一份数据。

**形成这类数据的一条路径已在序列化边界复现：新版生成 v2 → 旧版 App 解码并重新导出/上传 → 版本和映射丢失 → 新版 editor 导入失败。** 旧版真实 Schedule 编解码器输出的日程数组与现场服务器数组完全相同。用户不确定是否混用过旧版或 Web；没有最后写入请求或审计记录，不能把上述路径当作已经确认的现场操作历史，也不能断言线上服务器主动删字段。

**本次最终方案：识别旧客户端整体丢失 Timed 新字段的形态，补 `timedSchemaVersion=2` 和每条日程的 `nodeSlots=[]`，保留全部日程并正常导入、展示。** 空数组明确表示尚未分配设备槽位；后续同步沿用既有分配与容量检查。撤掉此前未提交的 Timed 隔离状态、专用恢复按钮及额外权限限制，业务修改仅涉及两个生产文件。

补默认值解决的是导入和展示，不等于恢复已经丢失的物理绑定。设备已有定时不会被导入操作清除；若实际槽位已满，后续分配仍可能提示容量不足。本次不通过猜测绑定或自动清空设备来规避该检查。

## 2. 证据与分析基线

- 工作树：`feat-timed-limited-261008`；分支：`feat/timed-limited-261008`；HEAD：`504eefb1155c1064a7088053190e97209a1c3839`。开始分析时工作树干净。
- App 导出：`/Users/maginawin/Desktop/doing/cgy timed/Space_Space 1_20261013_093715_158+0800.json`。
- 服务器响应：`/Users/maginawin/Desktop/doing/cgy timed/server data.json`；同目录 `issues.md` 为空。
- 本机 SDK 映射为 `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2598bd1`，干净；本轮未修改 SDK；App 构建使用此本地映射。
- 只读核对本地后端 `/Users/maginawin/Developer/SunSmartDev/sunsmart-services`，HEAD `df617d8`，干净。这里只代表该源码版本，不代表线上部署。
- 文档不保存密钥、账号名、完整原始报文；临时探针只在内存读取现场 JSON，没有复制其敏感内容到仓库。

| 项目 | 本地 App | Server GET |
|---|---|---|
| Space | Space 1，同一 UUID | Space 1，同一 UUID |
| Network/App Key | 与服务端对象一致 | 与本地对象一致 |
| 成员状态 | `joined`；网络匹配；`configurationInitialized=false` | `role=editor` |
| 恢复状态 | `active`、`writable`，未请求解绑 | — |
| 配置数量 | nodes/groups/schedules 均为空 | 2 nodes、1 group、17 schedules |
| 时间戳 | `lastUpdate=0`，`lastUploadCloudTimestamp=null` | `updateTimestamp=1791599030` |
| 本地恢复依据 | 无 complete snapshot、无 pending import/upload/deletion、四类 baseline 均缺失 | — |
| Timed 格式 | 空配置，默认版本 1 | 未声明版本；17 条均无 nodeSlots |

服务端 payload 的 create/update 值换算为 UTC+08 分别是 2026-10-10 08:57:53、10:23:50。它们是报文字段，不是已经核实的服务端请求审计时间，不能单凭此锁定最后写入者。

该 App 文件是 `_debugInspection.purpose=localConfigurationInspection`、`uploadable=false` 的诊断导出；`comparisonPayloadAvailable=true` 或 `issues=[]` 不代表完整配置可恢复。不能把里面的空数组当成权威配置回传。

## 3. 完整触发链

### 3.1 进入与导入

1. `SiteViewController.selectSpaceAction` 对在线云 Space 发起 `loadSpaceReqeust`，GET `/sitespace/get/spaceprops`。
2. `SpaceData.restoreConfiguration`（`SpaceMembershipCoordinator.swift`）校验成员与网络身份，保存明确尚未初始化的 Space 行，再调用 `update`。这解释了为什么本地有身份和 Key、没有配置。
3. `SpaceData.update`（`ImportData.swift`）在业务数据替换之前检查 Timed schema、canonical 和 `[Schedule]` 解码。现场报文在这一前置门禁被拒绝，尚未进入 `beginImport`，所以本地 `pendingImport=false` 与失败并不矛盾。
4. `TimedSchedulerPayloadPolicy.schema` 对缺 `timedSchemaVersion` 返回 1；`canonical` 的 v1 分支要求 `id < 16` 且不带 nodeSlots。id 16 违反规则。
5. 即使仅放宽 canonical，`Scheduler.swift` 的实际 Codable 仍要求 `nodeSlots != nil || id < 16`；现场数组在 `Index 16.nodeSlots` 解码失败。单改一处条件不能恢复有效映射。
6. `SpaceRecoveryViewController.message` 没有处理 `invalidTimedPayload`，落入 `space_recovery_unavailable`，显示用户提供的通用提示。
7. 未成功应用配置就不会设置 membership initialized，也没有完整云确认时间。离线进入还会被 `intoSpace` 的首次导入保护拦截。

这不是等待后台恢复能自动结束的状态；相同输入会稳定失败。保护本身阻止了空 editor 配置覆盖服务器，不能通过强设 initialized、清空保护标志或伪造上传时间绕过。

### 3.2 17 条并未超出任一设备的容量

- L1 / `0002`：业务 id 0…15，共 16 条；设备快照有物理 slot 0…15。
- L2 / `138A`：业务 id 16，共 1 条；设备快照记录在物理 slot 0，周掩码 36、08:00、action 0。
- 两台设备的 `custProps.schedulerModelStates` 均通过当前生产 `SchedulerModelSnapshot.decode/validate`。
- L2 正确关系应由业务映射表达“id 16 → 该设备 slot 0”，而不是把 16 直接下发为设备 index。

物理快照不能完整替代业务映射：L1 的业务 id 2/3/9、6/7、11/14 各有重复时间/动作定义，单凭内容无法唯一对应；快照也不包含原 binding generation 和完整 pending-removal 意图。因此本轮构造的 v2 数据仅用于证明格式边界，不能当作已获证实的无损修复副本。

### 3.3 Retry / Saved Space Copies / Leave

- Retry 再次 GET 并走同一导入；服务器未变时继续拒绝。
- Saved Space Copies 列出当前账号/区域副本，点击只打开 `UIActivityViewController`。没有导入、应用配置、云端修复或解除保护操作。
- 当前 editor 没有 `last-complete-export.json`，不能从本机空配置恢复这 17 条日程。
- Leave 用于退出成员关系及本地清理，不是修复手段。本任务不需要离开、删除 Space 或重置设备。

## 4. 数据怎样变成这样，以及如何复现

### 4.1 修复前已执行的确定性边界复现

使用临时 Swift harness 编译当前 `TimedSchedulerSlotPolicy.swift`，并提取当前生产导入前置 guard、实际 Schedule 解码器、SchedulerModelSnapshot 和 Recovery message 分支。只有 UI/设备/数据库等无关对象被替身替代，没有启动 App 或访问服务器。

| 输入变体 | 生产校验结果 | 含义 |
|---|---|---|
| 原始 server data | schema 1；canonical false；`invalidTimedPayload`；Schedule 解码失败于第 17 项 nodeSlots | 现场拒绝点已复现 |
| 仅在内存去掉 id 16 | Timed 前置校验通过 | 锁定该边界；不是建议删除日程 |
| 仅保留 id 16 | 同样失败 | 与分组数量和总数组规模无关 |
| 只补 timedSchemaVersion=2 | 仍失败 | 缺全部 nodeSlots，不能只加版本号 |
| 内存构造完整 v2：A id→同号 slot，B id16→slot0 | Timed 前置校验通过 | v2 能表达此容量分布；映射为诊断构造 |
| 上一变体再次去掉版本和 nodeSlots | 重现 invalidTimedPayload | 字段丢失足以稳定触发 |
| invalidTimedPayload 的 UI 映射 | `space_recovery_unavailable` | 通用提示来源已复现 |

### 4.2 旧 App 降级写回的源码证据与探针

以引入此功能的 `cf99bbd1` 的父提交 `6d0b1bbd213e553e50c752667dba79b969b6fd7f` 代表不认识 v2 的代码：

- 旧 `Scheduler.swift` 把 id 解码为 Int，不拒绝 16；CodingKeys 不含 nodeSlots，重新编码时丢失该字段。
- 旧 `ExportData.swift` 重建 spaceData，只放 proximityLightingSchemaVersion 与 triggerZones，不保留 timedSchemaVersion。
- 旧导入的 Schedule 数组解码没有新版范围/映射校验，因此上述旧版具备“读入17条，再不完整地导出17条”的条件。
- 用旧版真实 Schedule 编解码器处理诊断构造的完整 v2，结果为 `decodedCount=17`、`maxID=16`、`nodeSlotsAfterEncode=0`，并且 `legacyEncodedSchedulesEqualSuppliedServer=true`。
- 当前 App 正常导出会编码 nodeSlots、写出 timedSchemaVersion，并在出口校验 canonical；当前请求封装直接传递 Space payload，没有在此过滤这两个字段。
- 本地后端 `present_spaces_sync` 对整个 schedules/spaceData 做 JSON 序列化保存，`space_outgoing` 整体解码返回；该路径未见 Timed 防降级检查。它会保存已经被客户端投影成旧格式的数据，但没有证据说明线上主动删除了原本完整的字段。

### 4.3 人工端到端复现步骤（待测试环境执行）

1. 在独立测试 Space，用新版客户端建立 A、B 两台支持 Scheduler 的设备；为 A 创建16条，再为 B 创建第17条，B 使用自己的 slot 0。
2. 上传并检查原始请求及 GET：此时必须是 timedSchemaVersion 2，并带完整 nodeSlots。如果第一次 GET 已缺字段，就在这里定位 App 请求、实际部署的后端写入/返回和其他消费者，不继续预设旧版原因。
3. 在可控旧版客户端上导入同一测试 Space，做一次触发全 Space 上传的元数据修改并同步；不需要在旧版编辑或执行第17条定时。记录实际上传是否删除上述两类字段。
4. 若服务端接受该降级写入，检查 GET 仍有17条但缺版本/映射。
5. 用修复前新版、尚无完整本地配置的 editor 进入：应得到 `invalidTimedPayload`，UI 显示通用恢复提示；Retry 仍失败；Saved Copies 无恢复动作。
6. 已有完整本地 v2 的客户端也可能在入口请求失败或云回读冲突处受阻，但本地完整数据应保留；不要为复现卸载或清除真实来源手机。

本轮完成的是步骤涉及的序列化/校验边界复现，不宣称已经执行上述真实设备与服务器流程。Web、其他平台、过渡测试版或线上 DTO 过滤也可能造成相同结果，需要最后写入请求证据区分。

最短取证：核对该 Space 最近一次成功写入的客户端版本/User-Agent、请求中的 timedSchemaVersion、nodeSlots 数量，以及对应 GET。由持有服务端日志的团队只读提供字段摘要即可；目前无需用户回忆完整操作过程。

## 5. 最终调整方案与实现

用户最新指示取代此前的整域隔离方案：不增加恢复流程，缺失部分采用默认值后展示。当前实现不新增恢复状态、页面、按钮、文案或通用框架。

### 5.1 兼容范围及默认值

| 输入 | 处理 |
|---|---|
| schema 缺失或为 1，全部日程缺 nodeSlots，存在 id ≥ 16 | 保留每条业务日程，补 schema 2，每条 nodeSlots 补空数组 |
| 合法 legacy id 0…15 | 原样导入，保留原来的 legacy 语义 |
| 完整 v2 | 原样保留所有绑定、generation、pendingRemoval |
| v2 中明确提供的空绑定数组 | 作为未分配的期望配置导入，沿现有逻辑判定需要同步 |
| 未知 schema、显式 null/畸形绑定、重复业务 ID、同设备真实 slot 冲突、非法时间或身份 | 继续拒绝，兼容函数不修正已有错误值 |
| 同一设备期望定时和待删除保留合计超过 16 | 保留原有容量校验，不因空间总数量放宽单设备协议限制 |

不改日程 ID、名称、时间、星期、enabled、目标、Profile 或删除引用，不改 nodes 中的 Scheduler 快照，不将业务 ID 对 16 取模。全部缺失的绑定统一补空，不能把前 16 条继续当成可信 legacy 物理绑定，否则 id 0 可能误认另一设备上 id 16 的 slot 0。

此前的只读探针已证明后一风险：截取前 16 条按 legacy 规划，在 L2 得到 `logicalID=0, slot=0, state=pendingRemoval`，生产删除策略返回 true。此次空绑定方案的回归验证该状态不再产生任何物理槽位归属或删除判断。

### 5.2 修改入口和共享链路

1. `TimedSchedulerPayloadPolicy.fillingMissingBindings` 实现上述窄范围缺字段兼容。函数只返回规范化副本；原始数据不原地修改。
2. `SpaceData.update` 在前置 Schedule 解码，以及持久导入/中断重试选定的来源进入正常清理之前补默认值；继续执行原有权限、身份、拓扑、Profile、Model 快照、事务与读回检查。`canDecodeConfigurationImport` 的用户确认导入路径使用相同处理。
3. `schema` 和 `canonical` 使用相同规范化语义，使原始云 GET、规范化本地数据、上传及回读证据可比较；避免补值成功后又因缺失字段与空数组不相等反复阻塞。
4. 文件导入/导出也使用同一默认语义，修复后的文件继续使用现有 v2 envelope。普通合法 legacy 文件格式不变。
5. 仅取消 v2 的“每个目标导入前必须已有绑定”要求；已有绑定的节点身份、slot 范围、唯一性及单设备容量检查继续保留。

只有 `ImportData.swift` 和 `TimedSchedulerSlotPolicy.swift` 有生产代码差异。没有修改 SDK API、服务端接口、固件、品牌配置或国际化资源。五品牌共享这些代码，无品牌条件分支，代表构建使用 SunSmart。

### 5.3 导入后的行为与边界

- `TimedViewController` 仍从正常 schedules 集合显示全部 17 条，不隐藏列表，不增加专门的恢复页。目标存在但 `slot(on:) == nil` 时，现有 `schedulerSyncDifference` 返回 `ownerEntryMissing`，按现有界面逻辑显示需要同步。
- 恢复完成后不再因为本次字段缺失施加空间级编辑限制；设备、分组、场景等继续走原有角色权限与保护机制。会联动 Timed 槽位分配的配置操作仍受已有容量检查约束。
- 真正发送定时前仍调用 `TimedSchedulerBindings.prepare/commit`，只分配确认空闲的物理槽位；已知被占用或未读取完成的槽位不会凭默认值被覆盖。
- 没有绑定的日程不会通过 `needsDelete` 将业务 ID 当成设备槽位；已下发到设备的历史定时可能继续运行。由于历史绑定已经丢失，本次不承诺能直接编辑/删除所有旧设备定时，也不自动进行设备定时重置。
- 默认值随正常数据库及 schema 2 导出持久化；无随机恢复 generation，不新增“进入兼容模式/退出兼容模式”状态。重试和重启继续复用原有导入事务及 receipt。
- 本次识别依赖仍有 id ≥ 16。旧客户端若把所有高 ID 日程也删除，使数据与合法 legacy 完全相同，则无法仅凭该 payload 判断其历史来源；本次不猜测此类数据。

## 6. 验证记录

以下验证针对本次简化后的代码；前一版隔离方案的验证不作为本次证据。

| 验证 | 结果与覆盖 |
|---|---|
| `check_timed_device_slots.py --snapshot` | 通过。重现新数据被旧格式整体剥离字段；现场 17 条全部保留，节点原始数据不变；默认值幂等、canonical 往返、v2 backup、非法字段/真实冲突/单设备超量仍拒绝 |
| `check_timed_slot_persistence.py` | 通过。新夹具运行生产 Schedule 编解码、SQLite 保存/重载、绑定和删除策略；17 条空绑定不被猜测为物理槽位；容量失败不改记录，空闲后可按设备分别分配；原有 pendingRemoval、late reply、组退出及失败回滚回归通过 |
| `check_space_recovery_receipts.py` | 通过。owner/editor 初次导入准备、原始旧格式 pending import 重试、baseline 完成和默认值上传回读；原有权限、持久化失败、过期回调和导入保护回归通过 |
| `check_cloud_node_import.py --snapshot` | 通过。现场两个节点的 SDK 可选字段解码和生产 staging 边界 |
| `check_space_sync_cleanup.py --snapshot` | 通过。现场两个节点，relayAliases=0、proximityMutations=0，其他字段保留 |
| `check_proximity_scoped_import.py` | 通过。共享导入/清理、空 Zone、作用域、失败重试和删除保护 |
| `check_sync_execution_session.py` | 通过。生产 Session 调度、写回、停止重试、迟到回调及授权变化 |
| SunSmart generic iOS Debug | 通过，`BUILD SUCCEEDED` / exit 0；本地 workspace/SDK 映射已核对，SDK `2598bd1` 且无差异 |
| `git diff --check` | 通过 |

首轮 quiet 构建 exit 0，但输出含一条“command failed with exit code 0”诊断；为消除结果歧义，按相同代码、配置和 DerivedData 做了一次普通增量构建，明确得到 `BUILD SUCCEEDED` / exit 0。未清理共享缓存。

测试范围说明：导入准备/receipt 测试使用真实生产方法，但完整 Mesh 数据导入和网络仍为替身；SQLite 测试使用真实数据库及 Schedule 编解码，Profile 类型为替身、该复现夹具为无 Profile 日程。现场文件仅内存读取，不复制私密字段进仓库。上述结果不等于 App 真机运行或真实云端往返验收。

保留修正了既有隔离夹具缺少 nodeSlots、reviewedCloudImport 和 applyMessageHandle 的适配，这些只为运行相关回归，不是新增产品行为。

## 7. 最短人工验收及交接

1. owner/editor 均更新到包含本修复的版本。当前 editor 不用 Leave Space，点 Retry Recovery：预期完成空间导入，Timed 显示 17 条，检查名称、时间和目标均与云端相符。
2. 退出重进或重启：预期仍显示 17 条，缺失绑定的条目按现有未同步状态展示，不再次弹出由本次字段缺失导致的恢复阻断。
3. 修改一个普通名称并正常同步云端，再由另一新版客户端读取：预期设备、分组、场景、17 条定时均保留，云端正常导出携带 schema 2 和空/已分配 nodeSlots。
4. 在独立测试空间验证定时同步：占满且归属丢失的槽位应提示容量问题并不改写；设备槽位确认空闲后，现有同步应能分配并下发。确认导入本身不发送清空旧定时的操作。

未自动运行真机，未操作现场账号、服务器或设备。所有修改尚未提交。仅更新 owner/editor 可以避免已核实的旧 App 写回链路，但不会还原此前丢失的历史绑定；还须保证没有其他旧客户端继续写入同一 Space。
