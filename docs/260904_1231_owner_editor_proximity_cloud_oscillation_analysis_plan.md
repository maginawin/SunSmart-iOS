# Owner / Editor 邻近照明反复同步与拓扑丢失分析、修复计划

## 1. 结论摘要

本次问题不是单一的 Mesh 指令失败，也不是 Editor 权限判断错误，而是四条缺陷链叠加：

1. **新版邻近照明 Cloud Schema 尚未获得服务端完整往返保证，App 已按全量快照启用并上传。** App 导出明确包含 `proximityLightingSchemaVersion = 1`、Space `triggerZones`、Group `proximityLightingPath` 和 Node 邻近照明已观测状态；日志中的 GET 导入从未进入 schema 1 分支，首次 Editor 导入后 `spaceZones` 变为 0，说明服务端返回不是 App 导出的完整 schema 1 快照。
2. **Editor 的 Group Profile 存在本地持久化失败后静默降级。** 同一个 `C000 / Group 1` 在不同上传中出现多个随机 Profile ID，并从 `type = 7` 邻近照明退化为默认 `type = 1`。源码中 `GroupInfo` 先保存 Profile 引用、随后保存 Profile，但两个返回值都被忽略；导出前重新加载失败时又用默认 Profile 替换内存对象。当前分支还缺少对历史 `profiles.regulatorAccuracy NOT NULL` 列的兼容，符合此前已确认的跨分支数据库失败模式。
3. **Scheduler 删除任务来自“不知道设备状态”而不是当前业务确实存在对应定时。** Cloud 只恢复扁平 `node.schedulerActions`，没有恢复每个 Scheduler Setup Model 的 `allSchedulerModelEntrys` 已知空/已知值状态；`needsDelete` 把任一 Model 为 unknown 直接判为需要删除，于是 Space 中两个全局 Schedule 槽位 0、1 被对每个 Group 的设备重复清理。
4. **两台手机使用客户端秒级 `updateTimestamp` 和整份 Space 最后写入覆盖，冲突不可检测。** 相同时间戳时，App 只比较 Node、Group、Scene、Schedule 等数量；内容不同但数量相同就跳过导入。Owner 和 Editor 因此各自保留旧内容，完成 Mesh 同步后又把整份本地快照上传，形成来回覆盖和反复提示同步。

因此，目前不能只修复 Proximity UI 或某个 `needSync` 判断。需要同时处理数据保护、本地事务、服务端字段/revision 契约和 Scheduler unknown 语义。

## 2. 分析范围与边界

- 工作树：`trigger-zone-july`
- 当前基线：`903ff66e`
- 日志目录：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/⭐️ trigger-zone-july/logs`
- 日志：Owner / Editor 共 7 份，覆盖进入 Space、同步 Group 1、Group 2、Group 3及再次交叉进入/同步。
- 本轮只分析源码、Git 历史、既有测试和日志；未修改业务代码，未调用真实服务器写接口，未执行真实 Mesh 设备操作。
- 当前日志的 HTTP body 被截断到约 3033 字符，无法逐字段保存完整请求/响应原文；下述“服务端字段缺失”同时使用了导入分支日志、导出摘要和导入后状态变化作为证据，不仅依赖截断的 body 文本。

## 3. 日志还原

### 3.1 Editor 同步 Group 1

`editor sync group 1.txt` 显示：

- 对 `008C`、`008F`、`0099`、`009C` 的 Scheduler 槽位 0、1分别发送删除，总计 8 个逻辑删除目标。
- 对 4 个设备发送完整 Profile 相关配置，并发送 `proximityLightingEnabled(false)`；设备均成功响应。
- 上传前摘要为 `groups=2 paths=0 groupZones=0 spaceZones=0 pending=3`。
- 同一上传的 `C000 / Group 1` 为 `type=1`，没有 `proximityLightingNumber`，没有 `proximityLightingPath`。
- `/sitespace/sync/spaceprops` 返回业务成功。

这不是单纯“Editor 看到错误图标”：Editor 实际把 Group 1 的邻近照明关闭，并把缺少 Group Path 和 Space Trigger Zone 的整份 Space 快照上传了服务器。

### 3.2 Editor 同步 Group 2 / Group 3

`editor sync group 2.txt` 显示：

- `009F` 删除 Scheduler 槽位 0、1。
- 发送 `proximityLightingNeighborSet(enabled: true, relay: 3, neighborAddresses: [])`。
- 上传前 `pending=2`，说明 Group 3 仍待处理。

`editor sync group 3.txt` 显示：

- `00A2`、`00A5` 删除 Scheduler 槽位 0、1。
- 两台设备分别发送 `proximityLightingNeighborSet(enabled: true, relay: 2, neighborAddresses: [])`。
- 上传前 `pending=0`。

因此 Group 2、3 的红色同步状态主要不是 Profile 本身，而是 Scheduler unknown 清理和被导入为空的邻居目标。

### 3.3 Owner 导入 Editor 快照

`owner enter space.txt` 显示：

- Server `updateTimestamp=1788493713`，Owner 本地为 `1788492985`，因此应用服务器快照。
- 导入后出现 `[ProximityLightingImport] convergencePending=3`。
- 紧接着导出摘要为 `groups=2 paths=0 groupZones=0 spaceZones=25 pending=0`。
- GET 返回中的 `C000 / Group 1` 已是 `type=1`、无 Path。

这里揭示两个不同结果：

- Group Profile 和 Group Path 被服务器快照覆盖，Owner 接收到了 Editor 的退化数据。
- Owner 原有的 25 个 Space Trigger Zone 因“无 schema 的旧快照更新保留本地字段”而暂时留在 Owner 手机；这并不表示 Cloud 已保存或会向新 Editor 返回这些 Zone。

`owner sync gropu 1.txt` 随后再次对 Group 1 四台设备清理 Scheduler 0、1，并上传完整 Space。

### 3.4 再次交叉进入后的反复

`owner enter space and sync group 1 again .txt` 显示：

- Server 与本地时间戳均为 `1788494181`，Group/Node/Schedule 数量相同。
- 导入被标记为 `serverUpdateTimestampNotNewer` 并跳过。
- Owner 仍再次对 Group 1 四台设备删除 Scheduler 0、1。

`editor enter space and sync group 1 again.txt` 显示：

- Editor 应用服务器快照后，Group Path 容器重新出现：上传前摘要为 `groups=3 paths=32 groupZones=32`。
- 但 `spaceZones=0`，Owner 的 Space Trigger Zone 没有随 GET 恢复到 Editor。
- Editor 又对 Group 1 四台设备删除 Scheduler 0、1，并发送 4 个空邻居的 Neighbor Set。

这就是用户看到的“Owner 同步后 Editor 还要同步、Editor 同步后 Owner 又要同步”的直接日志闭环。

## 4. 根因详解

### 4.1 P0：Cloud Schema / 服务端能力与 App 发布顺序不匹配

App 的 `SpaceData.export()` 会无条件输出：

- `proximityLightingSchemaVersion = 1`
- `triggerZones`，包括显式空数组
- 合格 Group 的 `proximityLightingPath`
- Node 的 `proximityLightingEnabled`、`proximityLightingRelayCount`、`proximityLightingNeighborAddresses`

但七份日志没有任何一次 `[ProximityLightingImport] schema=1 ...`。这说明 `/sitespace/get/spaceprops` 返回未携带可识别的 version 1。现有兼容分支把它当成旧快照：

- 已有 Space：缺失 `triggerZones` 时保留本机旧值。
- 首次导入的 Editor：缺失 `triggerZones` 时初始化为 `[]`。
- Group 数据会被整体删除重建，缺失的 `proximityLightingPath` 没有可保留对象。
- Node 数据也会整体替换，缺失的已观测状态退回默认/unknown。

此前计划已经明确要求“服务端先上线字段保留和 revision，再启用 version 1 App”；实施报告也明确标记 P2-5 服务端契约和双客户端黑盒验证未完成。本次问题正是该未完成门禁在真实 Owner / Editor 场景中的落地表现。

### 4.2 P0：全量 Space 写入会把不完整 Editor 快照变成服务器事实

`spaceUpload` 始终发送 `SpaceData.export()` 的完整 Space，不是字段补丁。Cloud Manager 收到 HTTP 200 后只更新 `lastUploadCloudTimestamp`，没有读回校验，也没有验证服务器是否完整保存并返回新增字段。

所以流程成为：

1. Editor 首次导入不完整快照。
2. App 用默认/空值计算 Need Sync。
3. Editor 完成 Mesh 指令。
4. 同步成功通知将 Space 标记为新一代数据。
5. Editor 把不完整本地模型作为完整 Space 上传。
6. Owner 下一次接受该快照，或在冲突时保留旧快照并再次反向覆盖。

### 4.3 P0：Profile 保存失败未进入事务，导出又静默制造默认 Profile

当前导入顺序为：

1. 删除当前 Space 的全部 `GroupInfo` 和 `Profile`。
2. 从 JSON 构造 Group / Profile。
3. `saveExtension()` 先保存 `GroupInfo.profileId`，再保存 `Profile`。
4. 两次保存结果都被忽略。

导出前又执行 `GroupInfo.load(...) ?? GroupInfo(...)`。若 Profile 行没有成功保存，`GroupInfo.load` 会保留构造时的默认 Profile；默认类型是 `type=1`，ID 是新 UUID。日志中同一个 `C000` 先后上传 Profile ID：

- `314BF2F6-4956-4380-9231-B7121034DA6D`
- `57F85D80-8723-43A9-BCA1-FB73DE16F13D`
- `7095B005-7BFA-4E03-9A96-FD93944D5442`

这不可能是稳定 Cloud Profile 的正常行为，和上述默认对象回退路径完全一致。

当前日志截取范围没有包含最初导入时的 SQLite 错误，因此还需在原 Editor 数据库上补一条数据库诊断才能把具体 SQL 错误从“高置信”提升为“直接确认”。但当前分支确实未声明/写入平行 `accuracy` 版本曾创建的非空 `regulatorAccuracy` 列；从该版本覆盖安装后，`INSERT OR REPLACE` 会因缺少非空列失败。此兼容缺口必须修复，且不能继续忽略保存结果。

### 4.4 P1：Scheduler unknown 被当成“确认存在，需要删除”

当前 Cloud Node 只显式导出/导入扁平 `schedules`，并恢复 `node.schedulerActions`。用于支持普通 Scheduler 与 Light LC Scheduler 单一归属的 `allSchedulerModelEntrys` 是 SDK 的关联属性和本地数据库状态，没有在 App Cloud 载荷中表达每个 Model 的：

- unknown
- known empty
- known entries

`Schedule.needsDelete` 只要发现任一 Scheduler Setup Model 没有缓存，就直接返回 true。因此从 Cloud 重建的 Node 会对 Space 内每个全局 Schedule 产生删除任务，即使这个 Schedule 从未关联当前 Group / Node。

日志中所有 7 台灯都对槽位 0、1执行 `SchedulerActionSet(noAction)`，证明这些是清理任务，不是 App 新建了两个定时。当前策略还存在误删风险：unknown 不等于设备上确认存在，直接向所有 Scheduler Model 写 noAction 可能清掉本地快照没有表达但设备实际仍有效的槽位。

### 4.5 P1：相同时间戳与浅摘要无法检测内容冲突

Space 变更使用秒级客户端时间戳，并通过本机 `lastUpdate + 1` 保证单机递增；两台手机从相同基线独立递增时仍会产生同一个值。

导入在相同时间戳时只比较以下数量：设备、普通 Group、Scene、Schedule、Switch、EFC。它不比较：

- Profile ID、类型与参数
- Group Path / Trigger Zone 内容
- Space Trigger Zone 内容
- Node 邻近照明已观测状态
- Scheduler 每 Model 状态

所以内容已不同但数量不变时仍会输出 `serverUpdateTimestampNotNewer`。Owner 再次进入时 `1788494181 == 1788494181` 并跳过，就是直接证据。随后任一手机同步成功都会把自己的旧内容提升为下一代整份快照，造成乒乓覆盖。

## 5. 对用户问题逐项回答

### 5.1 为什么 Owner 分享的 proximity groups 在 Editor 上显示需要同步？

不是分享权限导致，至少有三类数据在 Editor 上不一致：

- Group 1 Profile 本地落库失败后退回 `type=1`，因此对原本已启用的设备生成完整 Profile 改写和 Proximity Disable。
- Group 2 / Group 3 的 Node 邻近照明已观测状态与拓扑目标不一致，因此生成空邻居 Neighbor Set。
- 所有 Group 的 Scheduler Model 状态从 Cloud 导入后为 unknown，被错误解释为需要删除槽位 0、1。

### 5.2 为什么 Editor 同步后 Group Path、Group Trigger Zone、Space Trigger Zone 消失？

- Group Path / Group Trigger Zone 属于 `GroupInfo.proximityLightingPath`。Profile 退化为非邻近类型后，导出按规则省略该 Group 的 Path；其他缺失 Path 的 Group 也会在全量导入重建时变为 nil。
- Space Trigger Zone 属于 `SpaceData.triggerZones`。服务端 GET 没有返回可识别的 schema 1 完整字段，首次 Editor 导入会把缺失字段初始化为空。
- Editor 完成同步后上传整份 Space，空值/省略字段随之覆盖服务器，数据从“本机缺失”升级为“跨手机丢失”。

### 5.3 为什么出现 Scheduler 同步任务？

这些是删除任务，不是创建任务。日志中的 payload 对应 Scheduler 槽位 0、1的 noAction。根因是 Cloud 没有传递 Scheduler 每 Model 的已知状态，而源码把 unknown 直接判为需要删除。只要 Space 中全局 `schedules` 数组仍有 ID 0、1，即使当前 Group / Node 不在目标中，也会生成清理任务。

### 5.4 为什么出现邻近照明任务？Cloud 数据是否不完整？

是，现有日志已经证明 Cloud 往返结果不足以重建另一台手机的完整状态：

- Owner 导出有 `spaceZones=25`，Editor 应用后又导出 `spaceZones=0`。
- Editor 第一次同步前只有 `groups=2 paths=0 groupZones=0 spaceZones=0`。
- Owner 导入后出现 `convergencePending=3`，说明服务器 Node 已观测状态与目标拓扑不一致。
- GET 导入没有一次识别为 schema 1。

需要服务端完整 body/数据库记录确认具体是 DTO 白名单、持久化列、权限裁剪还是旧快照覆盖；但“不完整或已被旧写入覆盖”的结果已经确认。

### 5.5 是否还有其他类似问题？

有，分为已确认与高风险面：

**已确认同类问题：**

- 非邻近 Group Profile 也会受 Profile SQLite 保存失败影响，退回默认 `type=1`，不只 Proximity Group。
- 任意 Scheduler 类型，包括普通 Scheduler 与 Light LC Scheduler，在跨手机 Cloud 重建后都可能因 unknown 产生误删任务。
- 任何不改变数组数量的 Profile、Path、Zone、Node 属性变化都可能被相同时间戳和浅摘要漏掉。

**需要专项回归的高风险面：**

- `GroupInfo` 的 daylight sensor、scene execute data、PWM、Path 等扩展字段。
- Node 的 Scene、Scheduler、PIR、Motion Sensitivity、Calibration、Proximity、Switch 等已观测/扩展状态。
- 旧版 App、Owner、Editor 对 GET/UPLOAD 字段是否存在权限裁剪，以及 `/siteprops` 与 `/spaceprops` 是否使用不同 DTO 白名单。
- Scene / Switch / EFC 等使用“目标定义 + Node 本地缓存”判断 Need Sync 的功能，也可能产生同类跨手机假同步或反向覆盖。

这些风险不能从本轮七份日志直接全部定性为线上已发生，但共享同一全量替换、缺失字段和冲突机制，必须纳入修复后的 Cloud 契约测试。

## 6. 建议修复计划

### 阶段 A：P0 数据保护，先阻止继续丢数据

目标是在服务端修复前，避免 Editor 把不完整快照继续覆盖 Owner：

1. 为 Space 保存持久化的 Cloud snapshot completeness / schema capability 状态。
2. 首次导入若缺少 `proximityLightingSchemaVersion = 1` 或 version 1 必需字段，不得把 Proximity Path / Zone 解释为空并继续整份上传。
3. 对已有本地数据的手机保留 last-known-good 拓扑；对首次 Editor 没有可保留数据的情况，将相关编辑/同步入口置为不可写并显示国际化错误，而不是生成 Disable/空 Neighbor Set。
4. Cloud Manager 在 snapshot 不完整、Profile/GroupInfo 持久化失败或发生版本冲突时，禁止 `spaceUpload`，保留 dirty/error 状态。
5. Scheduler Model 为 unknown 时不得直接执行删除；先进入读取/验证流程或显示待验证状态。

阶段 A 是正式服务端修复前的止损措施，不承担恢复已经丢失的 Path/Zone。

### 阶段 B：P0 本地 Profile / GroupInfo 原子持久化

1. 兼容历史 `profiles.regulatorAccuracy` 非空列：声明、读取并按既有值或兼容默认值写回，但不扩展 Accuracy UI 或 Mesh 功能。
2. 将 Profile 与 GroupInfo 保存放进同一数据库事务：先保证 Profile 可写，再写 GroupInfo 引用；任一步失败都回滚。
3. `saveExtension()`、生命周期 Coordinator 和 Cloud 导入必须消费保存结果，失败时停止 Mesh、Cloud Dirty 完成态、页面跳转和上传。
4. 导出时 Profile 引用解析失败要 fail closed，不能用新 UUID 的默认 Profile 替换业务数据后上传。
5. 导入不能先删整表再逐项尽力保存；应在 staging 中解析、校验并事务替换，失败保留 last-known-good。
6. 增加不含 Auth 的结构化日志：Space、Group Address、Profile ID、数据库 schema 版本、保存阶段和错误码。

### 阶段 C：P0 服务端字段与并发契约，服务端先上线

接口范围至少覆盖：

- `/sitespace/sync/siteprops`
- `/sitespace/sync/spaceprops`
- `/sitespace/get/siteprops`
- `/sitespace/get/spaceprops`

契约要求：

1. Owner 与 Editor 在业务数据字段上返回同一完整 Space 快照；权限字段可以不同，但不能裁剪拓扑/设备配置字段。
2. 原样存储和返回 `proximityLightingSchemaVersion`、`triggerZones`、每个 Group 的 `proximityLightingPath`、Node 邻近照明已观测状态。
3. 区分字段 absent 与显式空数组；schema 1 缺少必需字段应拒绝，不得静默当空。
4. 引入服务端生成的 `revision` / ETag 或等效 CAS。上传携带 base revision，过期写入返回冲突，不接受静默 last-write-wins。
5. 上传成功后 App 必须 read-after-write，并校验 revision、schema 和关键摘要后才能清除 Cloud Dirty。
6. 旧 App 上传不得删除服务器已有的新字段；必要时采用字段级 patch 或按领域拆分 revision。

发布顺序必须为：服务端兼容与黑盒验证 → App 打开 schema 1 写入 → 双客户端验收。不能再次先发 App、后补服务端。

### 阶段 D：P1 Scheduler 云模型与 unknown 语义

1. 为 Cloud 增加版本化的 Scheduler Model 状态，按 Element Address、Model Identifier、slot 表达 known entries 和 known empty；不能只保留扁平 `schedulerActions`。
2. 旧载荷导入时保持 unknown，不把 unknown 当 residual entry。
3. 对需要清理但状态 unknown 的设备，先读 Scheduler Register / Action；只对确认存在的槽位发送 noAction。
4. 只有显式 tombstone、已知 residual entry 或设备读取证据才能生成删除任务。
5. 同步成功后持久化每 Model known-empty 状态，并将其与逻辑 Schedule 定义分开版本化上传。
6. 验证普通 Scheduler 与 Light LC Scheduler 的 owner/cleanup 模型，不得清除另一 Model 中合法任务。

该阶段优先在 App 层序列化现有 SDK 状态；若必须修改 NordicSigMeshSDK，本地开发路径存在，但实施前需再次确认当前 App 的远程 `release` revision 和所有引用 target 的联动发布。

### 阶段 E：P1 通用冲突和已观测状态模型

1. 将逻辑目标与设备已观测状态拆成独立 revision，避免一次 Mesh ACK 推动整份 Space 覆盖无关 Profile/Path/Zone。
2. 用服务端 revision 取代客户端秒级时间戳作为跨手机权威顺序；保留时间戳只用于展示/诊断。
3. 相同 revision 但 payload digest 不同必须视为协议错误或冲突，不能用数量摘要放行或跳过。
4. Conflict 后只读回、合并明确可合并的字段；Path/Zone 顺序结构不能按数组下标自动拼接。
5. 已观测 Node 状态携带来源、观测 revision/时间，旧客户端不得覆盖更新观测。

### 阶段 F：数据恢复与迁移

1. 先冻结受影响 Space 的自动上传，导出 Owner 与 Editor 各自 last-known-good 数据。
2. 从 Owner 仍保留的数据、服务器历史版本或备份恢复 Group Profile、Group Path、Group Trigger Zone、Space Trigger Zone。
3. 不可仅从设备 Neighbor 表反推完整 UI 拓扑：Neighbor 集合不能恢复 Sequence 顺序、Zone 容器编号或空 Point。
4. 清理服务器上由默认 Profile / 空拓扑产生的错误 revision，再让两台手机从同一权威快照重新导入。
5. 最后读取真实设备 Scheduler、Enabled、Relay、Neighbors 并执行一次受控收敛。

## 7. 自动化与验收矩阵

### 7.1 数据库与 App 测试

- 用含 `regulatorAccuracy NOT NULL` 的历史数据库启动当前版本，导入三个 Proximity Group，Profile ID 和类型保持稳定。
- 注入 Profile、GroupInfo、SpaceData 任一保存失败，确认无 Mesh 指令、无 Cloud 上传、无页面假成功。
- 导出遇到悬空 Profile 引用必须失败，不生成默认 Profile。
- 首次 Editor 导入缺 schema / triggerZones / group path / Node observed state 时拒绝可写状态，已有 Owner 本地数据保持不变。

### 7.2 Scheduler 测试

- 全局存在 Schedule 0、1，但与当前 Group / Node 无关；Cloud 首次导入不得直接生成删除。
- unknown、known empty、known residual、普通 Model、Light LC Model 分别验证。
- 读取确认 residual 后只删除正确 Model/slot；合法另一 Model 条目保留。
- 同步、退出 Space、重启、另一台手机导入后不重复删除。

### 7.3 双客户端 Cloud 测试

1. Owner 配置三个 Proximity Group、非空 Sequence、Group Trigger Zone、Space Trigger Zone并完成真实设备同步。
2. Owner 上传后 GET 的 schema、Profile、Path、Zone、Node observed state 与上传语义一致。
3. 全新安装的 Editor 首次进入：页面数据一致，若设备已同步则所有 Group 无红色同步状态。
4. Editor 不做变更直接退出，不产生 Space 上传。
5. Editor 做一个明确变更并同步；Owner 再进入后只看到该变更，不出现反向同步。
6. 两台手机从同一 revision 同时修改，第二次上传必须收到 conflict，不能覆盖。
7. Owner/Editor 分别通过 `/siteprops` 和 `/spaceprops` 刷新，结果一致。
8. 旧 App 与新 App 交替上传，新字段不丢失。

### 7.4 真实设备验收

- 读取每个相关 Node 的 Scheduler 0...15、普通/Light LC Model、Proximity Enabled、Relay 和完整 Neighbors。
- 验证 Group 1、2、3 与跨 Group Space Zone 的关系两端。
- 验证 App 重启、两台手机切换、Proxy 切换、同步部分失败和重试。
- 分别记录 Cloud 配置成功、HTTP/ACK 成功、本地持久化成功和真实设备最终状态，任一层不能替代其他层。

### 7.5 构建与共享 target

实施完成后执行现有聚焦测试、数据库迁移/Cloud fixture/Scheduler 新测试、`git diff --check`，并按项目规则直接构建：

- SunSmart
- Archipelago
- Lumineux
- SylSmart
- SLG Sync Plus

不使用 Simulator。真实 UI、双客户端服务端和 BLE/Mesh 验收单独记录。

## 8. 当前测试为什么没有拦住

当前 `bash scripts/check_path_topology_persistence.sh` 全部通过，包括生命周期、拓扑、Space Trigger Zone 和 review regression 契约。但现有测试主要证明源码结构和纯策略：

- 没有真实 `/siteprops`、`/spaceprops` 完整往返 fixture。
- 没有首次 Editor 在服务端裁剪 schema 字段后的导入测试。
- 没有 Owner / Editor 从同一时间戳分叉再交错上传测试。
- 没有历史 `regulatorAccuracy NOT NULL` 数据库 migration 测试。
- 没有 Cloud 导入后 Scheduler Model unknown 的行为测试。

其中现有契约还明确锁定了“无 schema 首次导入把 `triggerZones` 设为空”的兼容行为；在服务端仍裁剪 schema 的现状下，这一兼容分支正是新 Editor 数据丢失入口。

## 9. 建议确认的实施范围

建议按以下顺序实施，不把问题缩成单一 Proximity UI 修补：

1. 先实施阶段 A、B：App 数据止损和 Profile 原子持久化。
2. 同时推动阶段 C：服务端字段、revision、旧版本兼容和 read-after-write；服务端通过后才开放完整写入。
3. 随后实施阶段 D：Scheduler unknown 改为 read-before-delete，并补齐每 Model Cloud 状态。
4. 再实施阶段 E：通用冲突与逻辑/已观测状态拆分。
5. 最后按阶段 F 恢复当前测试 Space，并执行双手机、服务器和真实 Mesh 验收。

若只做 App 侧临时兼容而不修改服务端 revision，能够停止部分数据丢失，但不能从根本上消除 Owner / Editor 整份快照乒乓覆盖；若只修服务端字段而不修 Profile 持久化和 Scheduler unknown，红色同步与误删任务仍会存在。

## 10. 本轮状态

- 已完成日志与源码分析。
- 已运行现有邻近照明聚焦脚本，全部 PASS；该结果同时证明现有覆盖未包含本次跨手机场景。
- 未修改业务代码、SDK、本地化、资源、target 或依赖。
- 未执行 iOS 构建，因为本轮没有业务代码变更。
- 等待确认修复范围后再实施。
