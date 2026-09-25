# 空间 33：设备重置后云端移除旧归属的同步修复方案

分析日期：2026-09-24。时间均为 UTC+08:00。

## 结论

**修订结论：旧 Space 本地保留了已经失效的两台设备，而同步保护把服务端移除旧归属当作上传数据丢失，导致恢复无法继续。** 用户补充确认：L5（0EFC）和 L1（0F02）手动重置后已添加到其他 Space，服务端会移除原 Space 的节点。该操作可以发生在同一或不同手机、同一或不同 Site。

因此本例目标是：**旧 Space 从 5 台修正为剩余 3 台，清理失效引用，完成当前 Space 同步后恢复 More 功能。** 不应把本地五台重新上传恢复到旧 Space。云端 `deviceCount` 仍为 5 是统计与实际节点数组不一致；有效成员判断以通过验证的 `nodes` 为依据，最终上传修正统计。

Space 的持久权限仍是 Owner；More 的“无权限”是同一同步保护的错误呈现。主修复放在设备成员与同步收敛，不以改提示或给 Owner 绕过保护作为解决办法。

按用户新约束：**仅使用当前 Space 的云端完整快照、本地数据及提交/确认记录，不查询其他 Space 或 Site 来寻找新归属。** 同一/不同手机、同一/不同 Site 使用相同处理规则。

服务器自动移除旧归属的业务行为来自用户补充，未独立查看服务端实现。当前方案明确采用这一业务语义；不再把“找到目的 Space”或补齐原始上传日志作为修复本流程的前置条件。此前建议“先改提示、再用本机五台恢复”的方案已撤回。

用户已确认按本方案实施。App 修改及相关回归已完成，构建结果见文末实施记录；未操作用户真机或服务端数据。

## 输入与基准

- 分支：`fix/daily-260924`。
- HEAD：`2826232fdb00f4007a05f5c885aba045bdfcdd3c`。
- 开始时工作树干净。
- 日志：[1734 enter space.txt](</Users/maginawin/Desktop/tmp/1736/1734 enter space.txt>)。
- 本地数据：[Space_空间 33_20260924_173513_484+0800.json](</Users/maginawin/Desktop/tmp/1736/Space_空间 33_20260924_173513_484+0800.json>)。
- Site：`6A0CFFEB-2288-4753-983E-D21027690234`。
- Space：`58E6A579-897F-49CC-89AA-190D619FD917`。
- Submission：`F0E82741-3D0B-41DA-925C-04CC2FFC8F95`。

## 已证实的原因

### 1. 为什么处于待同步或同步失败状态

本地数据库导出显示：

| 项目 | 值 | 含义 |
| --- | --- | --- |
| permission | 1 / Owner | 不是 Visitor |
| requiresPasswordVerification | 0 | 没有持久密码复核拦截 |
| lastUpdateTimestamp | 1790242123 / 17:28:43 | 当前本地配置版本 |
| lastUploadCloudTimestamp | 1790241743 / 17:22:23 | 最后确认的同步版本 |
| syncCloudError | -2002 | configurationUploadUnconfirmed |
| blockedReason | uploadReadbackConflict | 回读配置冲突 |
| membershipPhase / recoveryPhase | joined / active | 未处于离开或删除阶段 |
| pendingImport / pendingDeletionCleanup | false / false | 此样本不是导入或删除清理未完成 |

`SpaceData.needUploadCloud` 依据本地版本晚于确认版本，判定仍需同步。日志还显示同一笔提交停留在 `accepted`，未达到 `verified`。该阶段是持久恢复记录的状态；存在旧记录迁移路径，不能仅凭它还原最初那次上传响应。

日志第 93、120、147 行及第 214、242、269 行是两轮各三次回读，均包含：

- `submitted=1790242123 localTimestamp=1790242123 remoteTimestamp=1790242123`。
- `submittedNodes=5 remoteNodes=3 remoteDeviceCount=5`。
- `missingRemoteNodes=2 extraRemoteNodes=0`。
- `scheduleTargetsMatch=true schedulerModelsMatch=false`。
- `canonicalEqual=false`，差异仅为逻辑配置中两个成员缺失。

日志第 152、274 行记录 `blocked ... reason=uploadReadbackConflict`。HTTP 200、业务码 200 只证明读取成功，时间戳相同也不能证明内容相同。

`CloudSynchronizationManager` 在生成新上传请求前调用 `resumeUpload`。回读不一致时结束本轮，因此普通重试会继续核验旧提交。当前日志请求清单只有 `siteInfo`、`spaceInfo`，未出现新上传；重新进入页面不能自动补回缺失节点。

如果“同步状态”指设备列表的“需要同步”：`Node.computeNeedSyncGroup` 在 Space 配置不可用时直接返回 true；设备同步执行器也会被相同保护阻止启动。它不能证明每台设备的 Mesh 参数都存在差异。日志未包含点击设备同步的完整过程，因此不另行认定某条 BLE 配置命令失败。

如果指导航栏加载状态：`.wait/.inProgress` 会显示加载；已知配置冲突时 `updateSyncState` 优先显示失败并进入配置恢复。现有日志能证明重复核验后失败，不能证明存在永久加载动画故障。

源码：[SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift)、[SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)、[CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift)、[Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)、[SyncExecutionSession.swift](../SunSmart/Main/Space/Model/SyncExecutionSession.swift)、[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)。

### 2. 缺失的具体设备

按生产诊断方法计算本地 UUID 的 SHA-256 前 8 字节，与日志缺失集合匹配：

| 本地名称 | 单播地址 | 所属组 | UUID 哈希前缀 | 回读情况 |
| --- | --- | --- | --- | --- |
| L2 | 0EED | C024 | f616a862b4db01c0 | 存在 |
| L3 | 0EF0 | C024 | fccf01626757fd9b | 存在 |
| L4 | 0EF3 | C024 | 5e30427bd3c987ad | 存在 |
| L5 | 0EFC | C028 | 6433d87012cef2ce | 缺失 |
| L1 | 0F02 | 未入组 | af7908c13f625c45 | 缺失 |

生产比较器直接从响应 `nodes` 计算数量和成员，没有按在线状态或 `configComplete` 过滤。缺项不是离线过滤，也不是 HTTP 正文日志截断造成的计数错误。

### 3. 为什么 Owner 被提示无权限

`SpaceData` 的操作集合同时受角色、会话状态和配置安全状态约束：

- `bleOTAOperates` 遇到 `isBlocked` 返回空集合。
- `deviceOperates` 遇到 `isBlocked` 最多保留 `.control`，不会包含 `.edit`。
- `SpaceMoreViewController` 对 BLE 升级和参数设置只判断是否含 `.edit`；失败一律提示 `no_permission`。

因此本例是“有 Owner 角色，但旧成员未收敛引发配置冲突，暂时禁止写入”。**主问题是同步未识别服务端撤销旧归属，界面又把配置拦截混成角色无权限。** 修复同步后应恢复正常操作；仅按 Owner 放行会绕开其他仍需保留的保护。

源码：[SpaceMoreViewController.swift](../SunSmart/Main/Space/Controller/SpaceMoreViewController.swift)、[SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift)、[SiteData.swift](../SunSmart/Common/Data/SiteData.swift)。

### 4. 为什么重新进入仍不恢复

`ImportData.update` 会先更新远端权限元数据，再在 `preservesLocalChanges` 为真时保留本地配置。未完成提交足以触发该分支。

日志 `preserved pending local deletion/recovery` 是通用保护日志，不等于用户执行了删除。本地导出明确没有待完成删除清理。当前保留本地五台设备，避免把缺少两台的回读直接当作完整权威配置覆盖进来。

源码：[ImportData.swift](../SunSmart/Common/Data/ImportData.swift)。

## 离线核验与证据边界

使用 `xcrun swiftc` 编译当前生产 [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 与临时只读探针，读取用户原文件：

1. 本地导出的逻辑配置哈希为 `0516aa4e4856bca4`，与日志提交哈希相同。
2. 仅从副本移除 L5、L1，哈希变为 `45212cc26939c7f2`，与日志远端哈希相同。
3. 差异路径精确复现为 `memberships.count`、`memberships[3]`、`memberships[4]`。
4. 本地 Scheduler Model 快照可被生产代码解析；移除两台节点会复现 `schedulerModelsMatch=false`，日程目标仍匹配。因此该 false 可由节点缺失解释，不必另假设日程内容损坏。
5. 完整配置与自身比较通过，缺两台的配置比较失败。

这些结果验证的是生产逻辑比较行为；哈希为诊断截断值，且逻辑配置不覆盖所有原始字段，不能声称整个云端 JSON 已逐字段验证。原始响应正文被日志限制为约 3000 字符，完整节点正文不可独立读取。

当前 `spaceInfo` 网络解码直接解析 JSON，随后只增加 membership 上下文，没有发现删除节点的转换；上传 API 也直接包装已准备的 Space payload。这与用户补充的服务端移除行为相容。

### 修订调查发现的两个缺口

1. **现有恢复依赖跨 Space 迁移证据。** `SiteDeviceOwnershipReconciler` 只扫描同 Site 的本地 Space，依赖同 MAC 的新旧实例。日志 `needsRepair=false` 表示本轮没有检测到这类本地重复，并不表示两台设备仍属于旧 Space。`readbackConfiguration` 又只认可 deletion journal 中 `replacement != nil`、已清理且晚于旧提交的记录，所以当前 Space 的云端缺项本身不能推进恢复。此次不扩大该扫描器范围，新增当前 Space 快照驱动的清理来源。
2. **已有迁移兼容只处理成员，没有覆盖 Scheduler 快照。** `readbackConfiguration` 可以排除旧成员；`resumeUpload` 的 `modelsMatch` 仍把完整旧 `submission.schedulerModelStates` 与云端比较，`finishSubmission` 也保存原始旧 Scheduler 基线。合法移除设备后，两边仍可能是五台与三台，继续失败或留下错误基线。

第二点已经隔离复现：复用现有 `check_space_recovery_receipts.py` 的生产方法提取和测试边界，在内存注入临时探针，使用本例节点与 Scheduler 快照，模拟两台已完成的迁移清理记录。现有不含 Scheduler 快照的迁移用例通过；带本例快照时 `resumeUpload` 仍拒绝。仅在测试状态中排除两台旧实例的 Scheduler 快照，回读即可确认，较新的清理记录仍保留等待后续上传。没有修改生产或仓库测试文件，也没有据此声称真实服务器流程已验证。

源码：[SiteDeviceOwnershipReconciler.swift](../SunSmart/Common/Data/SiteDeviceOwnershipReconciler.swift)、[DeviceScheduleAddressCleanup.swift](../SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift)、[DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)、[SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)。

BLE 日志中的 CTL Client 未绑定提示属于另一条消息处理路径；它不能解释发生在此前的云端成员缺失。此轮不据此扩大 SDK 修改范围。

## 已确认方案

### A. 当前 Space 的成员归属规则

**云端完整回读决定其已覆盖版本中的设备是否仍属于当前 Space；本机尚未上传的新实例继续保留。** 按本任务确认的服务端语义，已覆盖版本中的节点缺失视为旧归属撤销，不必查到设备的新归属。

判定基于当前 Space 的云端 `nodes`、最后确认基线、待确认提交和当前本地实例，不依赖 `deviceCount`，不简单使用“本地减云端”删除所有差集。

| 情形 | 处理 |
| --- | --- |
| 节点属于最后确认版本或已接受提交；有效云端回读覆盖该版本，但节点已不存在 | 记录当前 Space 的云端移除依据，清理对应旧实例 |
| 本机新添加，尚未包含在上述已确认/已接受版本 | 保留并继续正常上传 |
| 旧提交之后同一物理设备又形成新本地入网实例 | 按 UUID、地址及可用的 Device Key 指纹区分实例；不套用旧实例的删除依据 |
| 回读版本早于相关已确认/已接受版本 | 不据此删除，保留等待/重试 |
| 上传仍是 prepared、结果未知或被明确拒绝 | 不把“未上传到云端”解释为“云端移除”；沿用结果恢复流程 |
| HTTP/业务失败、缺少 nodes 字段、数据类型错误、身份/完整性校验失败 | 不形成移除依据 |
| 合法完整快照明确为 nodes=[]，且覆盖相应已提交版本 | 允许所有已失效旧实例收敛为空 Space，不用过期 deviceCount 阻止 |

服务端可能只移除节点而不推进旧 Space 时间戳，本例就是回读与提交时间相同，因此不能要求必须出现更大的时间戳；但相等必须结合已覆盖提交、正确作用域、完整有效载荷及剩余配置校验，不能仅凭时间戳判成功。

**协议含义与边界：** 当前接口没有给出专门的迁移/删除凭据。从单份同版本缺项响应，App 无法进一步区分“服务端主动撤销归属”与“服务端错误返回了有效但不完整的列表”。本方案按用户确认的业务行为，把符合上述条件的当前 Space `nodes` 作为成员权威；不声称已经获取了目的 Space 或服务端删除事件证明。复用现有恢复检查点保留清理前数据。未来若有服务端成员版本或删除标记，可增强判定，但本修复不以新增接口为前提。

没有可靠基线且无法区分已提交与本地新加的历史数据，继续保留保护，不进行无差别清空；不为处理这种不明状态查询其他 Space。旧 submission 的兼容迁移需检查现有快照可恢复的实例与版本信息，缺信息不能伪造已接受证明。

### B. 复用现有持久清理，增加云端移除来源

1. 在当前 Space 导入与上传回读的共同边界执行上述判断。已有 pending submission 时，要先识别允许的云端成员移除，再进入严格比较；不能被 `preservesLocalChanges` 的整块保留直接跳过。复用已取得的当前 Space 响应，不额外跨 Space 获取数据。
2. 扩展现有 `SpaceDeletionJournal`，用可选字段记录“云端移除旧归属”来源：作用域、回读/基线版本、相关提交、精确旧实例及清理阶段。与 `replacement` 迁移来源并列，兼容已有日志，**不伪造目标 Space**。
3. 复用现有持久删除与拓扑事务，清理旧节点、节点属性、Group 成员、Scene 元素地址、Scheduler 活跃/待删除地址、Sequence、Group/Space Trigger Zone、传感器绑定、Switch Proxy、分发缓存等实际引用。保留 Group/Scene/Schedule 容器和其他设备。
4. 此流程只撤销当前 Space 中的失效记录，不发送 Mesh Reset，不重置物理设备、不切到其他网络；对 Site 级 Gateway 等共享记录不能照搬普通永久删除的连带删除规则。
5. 更新 deviceCount/luminairesCount，清除节点同步缓存，复用完成通知刷新当前 Space、More 与返回 Site 后的数据源。刷新必须读取已持久化结果，不能只依赖某次协调器返回的变化集合。
6. 写入或清理失败保留日志，重启/重试按原作用域和旧实例继续；在异步回读后重新校验账户、区域、Space 世代、提交标识及本地版本，避免用过期响应清理新实例。

### C. 同步收尾必须覆盖成员、Scheduler 与引用

1. 由同一组已确认云端移除记录生成受限比较视图：从旧提交期望中排除对应成员、对应 Scheduler Model 快照，以及只由这些旧实例造成的已知引用差异。
2. 剩余节点身份、Device Key 快照、NetKey/AppKey、Group/Profile、其他场景/日程/拓扑继续验证；不删除或忽略不相关差异，不因为“少了设备”就返回成功。重置后的新实例与旧实例不是同一配置身份，不要求不同入网实例的 Device Key 相等，也不能把旧凭据恢复给新实例。
3. `finishSubmission` 的授权基线和 `schedulerModelStatesBaseline` 同步使用经过本次明确移除收敛的结果，避免比较时排除、落盘时又保存旧五台快照。
4. 较早提交完成核验后，较新的本地引用/数量清理继续保持待上传，使用新版本上传三台的完整配置；新的回读确认后再结束本轮同步。不得先上传原五台，也不得在只完成本地删除时显示云同步成功。
5. 若云端有其他新增设备或独立配置变更，交给现有导入/冲突处理，不把本任务扩成任意配置的自动合并。没有冲突且当前本地无额外编辑时，沿用正常权威导入；存在独立本地修改时保留其现有保护。

### D. More 的验收要求

- 本例正常闭环是：旧 Space 显示三台 → 云同步成功 → Owner 可以进入 BLE Firmware Update 和 Device Parameter Settings。
- 不给 Owner 增加绕过同步保护的特权，也不以“无权限”文案替换作为主交付。
- 清理/回读仍在进行或真实失败时，入口不能误报角色无权限；复用同步状态/恢复入口作必要反馈。真实 Visitor、会话编辑锁、OTA 分发等既有约束保持有效。
- 仅在所需反馈没有可复用文案时补 English/简体中文，检查品牌资源归属；不扩展为独立 UI 重构。

## 实施与验证范围

主要修改入口：[SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)、[SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift)、[DeviceScheduleAddressCleanup.swift](../SunSmart/Common/Data/DeviceScheduleAddressCleanup.swift)、[DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)、[ImportData.swift](../SunSmart/Common/Data/ImportData.swift)。同步队列和页面只作必要接入/刷新；不扩大跨 Space 扫描，不修改 SDK 为默认方案。

最小行为回归：

1. 本例 5 → 3，含真实形状 Scheduler 快照和既有 accepted 提交；删除 L5/L1 旧记录及引用，保留其余三台，数量最终为 3，新回读完成并恢复 More。
2. 同手机/异手机、同 Site/异 Site，目的 Space 不在本地或不可访问时，处理不依赖目的地数据。
3. 移除旧设备同时本地有未提交新设备、提交后再添加的新实例：保留新实例及独立编辑，上传不复活旧实例。
4. 单台/多台/全部移除；deviceCount 过期但合法 nodes 列表有效；缺字段、畸形数组、过期版本、错误 Space/密钥、未知上传结果不能触发误删。
5. 剩余节点 Scheduler/Device Key 或无关 Profile 差异仍被拦截；旧格式缺可选字段按原兼容规则处理。
6. 中断在“记录意图、删除节点、清理引用、确认旧提交、上传新清理”各阶段后可恢复，重复处理幂等；失败不伪报成功。
7. 当前页、重新进入 Space、返回 Site、已打开的 More 均刷新持久化结果；云同步完成与剩余真实设备的 Mesh 参数同步分别验收。

优先扩展现有 `check_space_recovery_receipts.py` 和删除/拓扑执行回归；无需单独创建测试工程。Swift 生产修改完成后核对 workspace 与 SDK realpath，完成相关回归并运行一次 SunSmart generic iOS Debug 编译；品牌范围按实际配置/资源风险确定。

最终设备及服务器验收由用户完成：手动重置 A 中的设备 → 任意手机添加到 B → 回到 A 同步 → A 仅保留实际三台、B 设备不受影响 → A 两个 More 入口可用 → 重启再次确认。代码、隔离测试与编译不能替代此真实闭环。

## 实施记录（2026-09-24）

### 实际修改

- 在当前 Space 导入前、已有提交的回读阶段，以及有确认基线的离线上传前，共用 `reconcileCloudMembership`。无待保留本地改动时继续走已有完整导入；有独立配置差异时保留冲突，不自动合并。
- 提交与确认基线持久化 UUID、主地址、Device Key 指纹和元素地址。旧 accepted 记录可从完整 Scheduler 快照恢复实例身份；新迁移的未知结果记录明确禁止作为移除依据。
- 云端移除依据先写入 deletion journal，再删除旧节点并执行现有引用清理。写入失败、节点删除失败、中断均保留可恢复状态；同 UUID 的新地址实例保留，同地址但不同 Device Key 的实例不自动删除。清理版本至少为云端版本加一。
- 旧提交比较与完成落盘均投影掉相同旧实例，包括 Scheduler 快照、Sequence 和 Zone 引用。旧提交确认后，新清理版本仍待上传，只有其回读确认才清除 journal。
- 若移除首次出现在新 POST 的回读中，云同步任务会继续上传并核验新清理版本，不能在旧提交确认后直接回调同步成功；复用已有完整配置上传和提交恢复方法。
- 云端成员撤销不删除 Site 级 Gateway 关联；不发送物理 Reset，不新增目的 Space/Site 查询。
- Space 完成清理后刷新当前子页；同步完成触发已有权限状态刷新。More 重现时也刷新选项，Owner 因配置保护受限时复用 `configuration_sync_unavailable`，真实角色/会话/OTA 限制继续保留。未新增文案或品牌资源。
- 修改一个既有源码契约测试的截取起点：原先错误定位到 Site 的 `update`，现在精确定位 Space 的 `update(spaceJsonData:)`。行为验证仍由生产方法执行回归负责。

### 自动验证

- `zsh scripts/check_device_permanent_deletion_cleanup.sh`：通过，旧 journal 格式和日程地址清理回归。
- `python3 scripts/check_space_protection_snapshot.py`：通过，持久保护读取、作用域/损坏/权限和缓存世代。
- `python3 scripts/check_node_sync_status_refresh.py`：通过，设备/Group/Scene/Timed 同步状态刷新及失效、取消行为。
- `bash scripts/check_path_topology_persistence.sh`：通过；包含真实生产清理上下文、拓扑规则、导入前置与上传恢复逻辑，SDK、网络和 App 数据库通过隔离边界控制。最后补充同步任务收尾后，`python3 scripts/check_space_recovery_receipts.py` 定向复跑通过。
- SunSmart generic iPhoneOS Debug：首次构建及最后补充同步任务收尾后的增量构建均 `BUILD SUCCEEDED`，`CODE_SIGNING_ALLOWED=NO`。未执行 Simulator 或真机安装。
- `git diff --check`：通过。构建和隔离回归存在既有编译提示，未将无警告作为验证结论。

新增行为用例覆盖 5→3、全部旧成员移除、过期 `deviceCount`、旧 accepted 格式、当前页导入后恢复提交、重复回读、未上传的新设备、已有确认基线下离线修改、prepared/未知结果、过期/残缺响应、剩余设备 Device Key/Scheduler 差异、无关配置差异、删除失败重试、同 UUID 新地址保留，以及清理版本后续上传确认。

构建入口为 `SunSmartLocal.xcworkspace`，SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision 为 `a05b86979e605c830e3ba932a71b41c11866337f`，SDK 工作树干净且未修改。使用本工作树固定的 `SunSmart-fix-daily-260924-cli` DerivedData，未改正式依赖配置。共享逻辑无品牌条件分支变化，未改变资源归属，构建选 SunSmart 代表 target。

### 待人工验收

用本分支构建进入原 Space 33 并同步：应由五台收敛为三台，完成后 Owner 能进入 BLE Firmware Update 和 Device Parameter Settings；退出重进并返回 Site 检查数量。另一 Space 中已重新入网的两台设备应保持正常。剩余设备的 Mesh 参数同步与云同步分别检查。

再复测“任意手机手动重置 → 加入另一 Space（含另一 Site）→ 原 Space 同步”，确认不依赖目的 Space 是否在本机缓存。上述自动验证及 generic iOS 构建不代表真实服务器、BLE 和界面体验已验收。未 commit/push。
