# Test Space 待同步、同步失败分析与修复方案

> 方案更新：用户补充要求在同步校验时清理不存在设备、不存在 Group 和 Group Profile 变更造成的同步异常。第 7～9 节已由 [同步校验统一清理修订方案](260915_1012_sync_validation_stale_reference_cleanup_plan.md) 取代；本文数据证据及根因分析保留。

## 1. 结论与待确认事项

**本次阻塞的核心是 Group 3（C00D）的历史邻近照明路径残留，以及现有恢复流程未覆盖这种残留。**

- App 和云端均保存了 Group 3 的 `profile.type = 1`，同时保留 `proximityLightingPath`。类型 1 是 Occupancy + Daylight；项目只允许类型 7/8 使用邻近照明路径。
- App 已记录 `blockedReason = invalidRemoteTopology`、`pendingDeletionCleanup = true`、`syncCloudError = -2003`。
- 本地更新时间晚于最后成功同步时间，所以云同步一直待完成。Space 被阻塞还会让组内设备显示需要同步，并阻止设备同步启动。
- 普通云同步在本地导出阶段失败；重新加载云端也无法解决同一份无效路径。现有本地修复入口又明确排除了“移除不适用组的完整路径”，形成无法自行恢复的状态。

**建议实施：保留本机当前设备列表，提供范围明确的失效路径修复，清理 Group 3 的残留路径，再恢复设备删除收尾和正常云同步。** 本案例预期保留 L2，不从旧云端重新导入 L1；设备删除的实际依据必须是 App 内持久化删除记录，不能仅凭两个文件的设备数量差异认定。

本次按用户要求仅完成分析、隔离验证和方案，业务代码、App 数据及服务器数据均未修改。确认方案后再实施。

## 2. 分析输入与关键证据

- App 导出：`/Users/maginawin/Downloads/tmp/Space_Test_20260915_095829_738+0800.json`。
- 云端响应：`/Users/maginawin/Downloads/tmp/space cloud.json`，对应 `/sitespace/get/spaceprops`。
- Space：Test，ID 为 `BF43EC23-D9B8-4D68-85D6-438A924575F7`。
- 代码基准：当前工作区，分析结束时 HEAD 为 `2e875e1f`。
- 本文时间统一使用 UTC+08:00。

| 项目 | App | 云端 | 含义 |
| --- | --- | --- | --- |
| 更新时间 | 1789435323，2026-09-15 09:22:03 | 1787911228，2026-08-28 18:00:28 | 本地存在尚未成功上传的更新 |
| 本地最后成功同步时间 | 1787911228 | 与云端更新时间一致 | 待同步判定有明确时间戳依据 |
| Mesh 业务节点 | 1：L2 / 0167 | 2：L1 / 019B、L2 / 0167 | 云端还保留本机已经不存在的 L1 |
| Group 数量 | 15：7 个普通组、8 个虚拟组 | 相同 | 不是整个组列表缺失 |
| L2 组成员信息 | C00B，groupState = 1 | 相同 | 当前 L2 属于 Group 1 |
| Group 3 Profile | type = 1 | 相同 | 非邻近照明类型 |
| Group 3 路径 | 2 条路径，每条为 374、383、0；2 个 Zone，分别引用 374、383 | 完全相同 | 这是双方已有的历史残留 |
| Space 扩展 | schemaVersion = 1，triggerZones = [] | spaceData = {} | 新旧版本表达差异 |
| 本地阻塞原因 | invalidRemoteTopology | 不适用 | 曾拒绝导入无效云端拓扑 |
| 删除收尾 | pendingDeletionCleanup = true | 不适用 | 至少存在未完成清理或无法读取的删除记录 |
| 本地保存错误 | -2003 | GET 返回 code = 200 | -2003 是 App 的配置导出失败错误 |

其他核对结果：

- 两边网络密钥对象、应用密钥对象相同；本文不记录密钥内容。
- 场景、日程、开关、应急消防控制器数组相同；L2 双方共有字段的值全部相同。
- Group 3 在双方均无现存节点成员。残留引用 374/383 即 0176/017F，不属于任一现存节点的元素地址；也不是云端 L1 的 019B～019D。
- Profile 的额外差异只有本地补出的 `calibrationMode = none` 和 `targetNightBrightness = 50`。这可能影响严格快照比较，但不是本次导入拓扑拒绝或 -2003 的直接原因，不纳入本次修复范围。
- 两边 Profile 均通过现有 Profile 完整性校验。类型 1 使用光照值，不能把相关大于 100 的字段误判为百分比越界。
- 路径中的 0 是合法空位；原始 SQLite JSON 中的空对象对应空地址。问题在于整个路径不适用于类型 1，不是空位编码损坏。
- App 文件是 DEBUG 检查快照，明确标记 `uploadable = false`。能导出此文件不代表普通云同步能够生成有效上传载荷；调试导出特意保留了错误配置以便排查。

## 3. 为什么 App 提示需要同步

### 3.1 云同步待完成

`SpaceData.needUploadCloud` 按本地更新时间与最后成功同步时间比较，并排除访客。

本例 1789435323 大于 1787911228，且本机为 Owner，因此结果为 true。这个提示并不是通过逐字段比较两份 JSON 得出的。

导航栏还单独检查 `SpaceConfigurationSafety.isBlocked`。本例既有阻塞原因，也有未完成删除清理，满足阻塞条件，会进入配置恢复入口。

### 3.2 设备也可能显示需要同步

`Node.getNeedSyncGroup` 在配置不可用时直接返回 true。配置可用性检查的是整个 Space 的保护状态，因此即使 L2 自身字段与云端一致、它属于 Group 1，Group 3 的异常仍能让 L2 显示需要同步。

这表示当前配置需要先恢复到可处理状态，不能仅据此断言 L2 的硬件参数发生了变化。

代码依据：

- [SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift)：`needUploadCloud`、`showSyncCloudError`。
- [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)：`updateSyncState`。
- [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)：`getNeedSyncGroup`。
- [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)：`isBlocked`、`configurationAvailable`。

## 4. 为什么点击同步失败

### 4.1 云端拓扑无法导入

`ProximityLightingImportPreflight.parse` 发现 Group 的 Profile 不属于 7/8、却带有路径时直接拒绝。随后预检降级结果带上 `invalidProximityExtensionPayload` 警告。

已有本地可用数据时，导入策略保留本地快照，并记录 `invalidRemoteTopology`。这与导出文件中的阻塞原因一致。

`blockedReason` 只保留首次原因，所以后续删除清理失败不一定会覆盖它。本例两个状态可以同时存在。

### 4.2 普通云同步在生成请求前失败

调用链为：同步 Space → `getNetworkApi` → `space.export(purpose: .cloudSync)`。

1. 普通导出检查到 Space 被阻塞，直接返回 nil。
2. 即使仅移除阻塞标志，拓扑归一化仍产生 `ineligibleGroup[49165]`。普通导出禁止顺带应用这类修复，仍会返回 nil。
3. 同步管理器把导出失败转为 `configurationExportInvalid`，错误码为 -2003。
4. 在这条路径中，尚未构造并发出 `/sitespace/sync/spaceprops` 上传请求。

因此，此次保存的错误和代码路径指向 App 本地阻塞。云端 GET 返回 success 仅说明读取接口成功，不能证明点击同步时上传成功，也不能说明配置满足 App 的拓扑约束。

### 4.3 若点击的是设备同步

`SyncExecutionSession.start` 首先检查 `currentConfigurationAvailable`。本例会直接进入 syncFailure，并显示现有“邻近照明数据无效，未执行导入”文案；不会继续执行设备配置任务。

该文案在设备同步上下文不够准确，需要在修复时改为引导先处理 Space 配置。单独解决云上传错误而不恢复 Space 配置状态，设备同步仍然不可执行。

代码依据：

- [ImportData.swift](../SunSmart/Common/Data/ImportData.swift)：`ProximityLightingImportPreflight.parse`、`hasValidationIssues`、`.preserveLocalSnapshot`。
- [ExportData.swift](../SunSmart/Common/Data/ExportData.swift)：`SpaceData.export` 的阻塞和未应用修复检查。
- [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift)：`getNetworkApi`、`finishExportFailure`、配置上传任务。
- [NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift)：`configurationExportInvalid = -2003`。
- [SyncExecutionSession.swift](../SunSmart/Main/Space/Model/SyncExecutionSession.swift)：`start`、`processNext`。

## 5. 为什么现有恢复流程无法解除

| 路径 | 本例结果 |
| --- | --- |
| 重试云同步 | Space 阻塞，导出返回 nil |
| 自动整理历史拓扑 | `hasDestructiveRepairs = true`，禁止自动应用 |
| 使用本机完整配置恢复 | 受保护检查仍不能导出有未应用路径修复的配置；且存在未完成删除清理 |
| 本地引用修复 | `canReviewReferenceRepair` 明确排除 `removedIneligibleGroupTopology`，恢复预览无法生成 |
| 继续设备删除清理 | 删除只允许移除已确认删除设备的地址；归一化还会删掉无关的 C00D 路径，超出删除范围，提交失败 |
| 重新加载云端 | 有删除记录时先保留本地；即便没有此保护，云端相同的无效路径也不能通过正常导入 |

删除提交要求“仅应用已确认删除地址后的快照”等于“归一化后的快照”。C00D 残留让二者不相等，因此删除收尾无法完成。不能通过放宽普通删除权限，让删除设备顺带清理其他历史配置。

代码依据：

- [ProximityLightingTopologyReconciler.swift](../SunSmart/Main/Group/Model/ProximityLightingTopologyReconciler.swift)：`normalize`、`canReviewReferenceRepair`。
- [ProximityLightingLifecycleCoordinator.swift](../SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift)：`commit` 中 `confirmedDeletionAddresses` 的范围约束。
- [DevicePermanentDeletionCleanup.swift](../SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift)：`complete`、清理后的持久化读回和 journal 更新。
- [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)：`referenceRepairReview`、`applyReferenceRepair`、`authorizeLocalRecovery`、`preservesLocalChanges`。

### 尚不能由文件证明的历史

- 两份快照不包含历史操作日志，不能确定是哪一版 App、哪次 Profile 修改留下了路径。云端快照更新时间已是 8 月 28 日，能确认该不一致不是本次 DEBUG 导出创造的。
- 当前 Profile 修改流程已经通过生命周期事务清理不适用路径，因此本次重点是历史数据恢复；实施时补回归覆盖，检查是否还有绕过该流程的写入口。
- DEBUG 文件没有导出完整 `device-deletions.json`，不能确认待清理记录的 UUID、阶段和替代设备信息。L1 在本机缺失且存在删除待收尾，与上述路径相符，但不能据此证明 journal 一定只涉及 L1。
- 未取得点击同步时的完整请求日志；-2003 与代码可以解释已保存的失败状态，不能据此排除更早曾发生其他独立网络错误。

## 6. 已完成的隔离验证

使用现有 `scripts/check_proximity_scoped_import.py` 的编译方式，在 `/tmp/space_test_20260915_probe.py` 中临时加入本案例验证，实际调用生产导入预检、拓扑归一化及 Profile 校验代码。

| 检查 | App 快照 | 云端快照 |
| --- | --- | --- |
| Profile 校验 | 通过 | 通过 |
| 原始拓扑导入预检 | 拒绝，invalidProximityExtensionPayload | 相同 |
| 归一化结果 | 仅 ineligibleGroup[49165]，无 hardError | 相同 |
| 现有引用修复是否允许 | false | false |
| 以 L1 元素地址演示删除范围约束 | 删除后快照与归一化快照不相等 | 相同 |
| 仅在内存副本移除 C00D.proximityLightingPath | 拓扑导入预检通过 | 通过 |

验证已通过。SDK 解码和存储边界使用现有测试替身，并补齐 Profile 类型枚举；删除范围验证使用云端 L1 的元素地址演示，没有伪造或修改 App 的真实删除记录。没有执行真机同步、没有运行完整 App UI，也没有上传任何输入数据。

## 7. 推荐修复方案

### 7.1 提供范围明确的历史失效路径修复

扩展恢复能力，单独识别“完整有效 Profile 为非 7/8，但存在可解码邻近照明路径”的情况。不要直接把所有 `removedIneligibleGroupTopology` 都放入通用引用清理白名单。

本次修复条件：

- Space、Profile、路径数据可完整读取，拓扑无 hardError。
- 组身份和 Profile 类型明确，修复范围可以精确列出。
- 本案例仅处理 C00D，保持 type = 1，移除其不再适用的路径和组内邻近照明 Zone。
- 保留其他组、Profile 参数、场景、开关、日程及现有节点成员关系。
- 存在无法解码的配置、异常归属或未完成导入时，继续保留阻塞，并说明具体原因。

在现有恢复入口展示具体变更预览，包括 Group 3、将移除的 2 条路径和 2 个组内 Zone，以及本机/云端节点数量差异。用户选择本机配置后再执行，不在普通导出或普通 GET 导入中隐式修改数据。

### 7.2 打通修复、删除收尾、上传的顺序

1. 获取并验证当前权限、Space 身份、恢复 generation、配置版本及删除 journal。
2. 保存本地和云端修复前快照、数据库 checkpoint，并持久化修复意图，确保中断后仍保留用户选定的数据来源。
3. 复核预览期间本机和云端没有变化；变更时重新生成预览。
4. 在事务内仅提交已确认的失效路径修复，读回验证，不提前清除整个 Space 的保护状态。
5. 重放原有设备删除 journal；仅对有持久化删除依据且节点确已移除的记录完成清理，保留原有删除范围约束。
6. 完整导出、拓扑校验、清理读回均成功后，再走本机恢复授权及正常上传流程。
7. 上传成功且本地确认持久化成功后，更新最后同步时间、确认相应删除记录；失败则保留恢复进度和重试能力。
8. 刷新设备同步状态，重新计算真实需要下发的设备任务。

推荐以本机当前设备列表作为本次恢复来源。**不把 L1 从旧云端重新导回，也不仅凭云端多一个节点就发送硬件 Reset。** 如果实际删除 journal 与该意图不符，应保留现场并显示具体差异。

仅修服务器的路径字段不能完整解决本机已有残留和删除阻塞，所以不作为主方案。预计无需修改服务器协议或 Nordic SDK。

### 7.3 让提示对应真实处理动作

- 配置阻塞时展示需要修复的组和原因，复用当前恢复弹窗。
- 设备同步失败文案改为说明 Space 配置需要先修复，避免将其描述为蓝牙失败或导入操作失败。
- DEBUG 诊断补出被拒绝的路径和阶段，避免仅有 `invalidProximityExtensionPayload`。所有新增 Log 必须处于 `#if DEBUG` 内。
- 新增或修改文案同时补英文和简体中文；检查共享资源涉及的全部品牌 target。

### 7.4 防止同类残留再次产生

对当前 7/8 → 非邻近照明类型的 Profile 切换补回归验证：Profile 与路径清理应在同一事务完成，重启后仍不残留。普通导入、普通导出继续保持现有校验；不为历史修复全面放松数据完整性要求。

### 7.5 预期修改范围

| 文件/模块 | 修改目的 |
| --- | --- |
| ProximityLightingTopologyReconciler | 提供失效路径修复分类与明确范围 |
| ProximityLightingLifecycleCoordinator | 接受经过确认的修复范围；维持普通删除和导入保护 |
| SpaceConfigurationSafety | 修复预览、快照复核、断点恢复及解除阻塞顺序 |
| SpaceViewController | 现有恢复入口展示具体修复内容 |
| SyncExecutionSession / 文案 | 配置阻塞时给出正确引导 |
| ImportData | 对不适用路径保留可定位原因，继续拒绝未确认的数据变更 |
| Tests/Group 与现有检查脚本 | 本案例及保护边界回归 |

除非实现中出现明确缺口，不改上传接口、压缩链路、SDK、密钥配置和无关模块。

## 8. 实施后的验证与验收

### 自动化验证

- 脱敏复现本案例：type = 1、残留路径、云端额外 L1、本机 L2、删除待收尾。
- 普通导入与普通导出仍拒绝原始异常；显式修复只移除 C00D 路径，普通组和节点保持正确。
- 修复后删除收尾成功；上传前保护本机删除，上传成功才确认对应记录。
- 覆盖修复过程中退出/重启、事务失败、上传失败、权限变化、云端或本机预览后变更，确保不会错误清除保护或覆盖新配置。
- 类型 7/8 的有效路径、有效 Space Zone 不被清理；无法解码、重复归属、容量异常仍被拦截。
- 删除其他设备不能顺带应用未经确认的历史路径清理。
- 新旧 schema 均覆盖；不把 0 空位或合法光照值判错。
- 验证 7/8 → 1 的正常 Profile 保存及重启后的持久化结果。

### 构建与真机

- 共享业务代码和本地化涉及 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux，按实际文件归属检查五个 target。
- 直接使用 `xcodebuild`，iphoneos SDK、generic/platform=iOS、关闭签名校验；不使用 Simulator。
- 恢复弹窗和文案变化需在允许的真机 MtestiPhone15 上实际运行，检查中英文、内容较长时的显示与按钮布局。其他个人设备由用户操作。
- 对测试 Space 实际执行恢复，确认 L2、7 个普通组及现有 Profile 保留，L1 不被旧云端恢复。
- 同步后读取 `/sitespace/get/spaceprops`，确认新版本、不含 C00D 失效路径及正确节点列表；重新进入 App 后不再因本问题提示配置阻塞。
- 检查设备同步重新计算后能够正常开始；如仍有真实硬件参数待同步，完成对应任务验证。最终体验由人工确认。

## 9. 请求确认

是否按以上方案实施：**以本机当前设备列表为准，新增明确范围的历史路径修复，清理 Group 3 的失效邻近照明数据，随后依据真实删除记录完成收尾并同步云端？**
