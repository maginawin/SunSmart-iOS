# 兴东2 owner 无法添加设备及编辑 Group 分析

## 结论

Space owner 身份正确，当前直接阻断原因是本地配置保护 `cloudConfigurationConflict`，不是服务器将当前用户降为 visitor。Site owner 身份不在这两份文件的证据范围内，不能由 Space owner 反推。

分析基于分支 `fix/llh-sync-261028`，HEAD `153bc667`。开始时工作树无未提交改动。本次只新增本文档，不修改业务代码。

## 输入与证据

- 服务器样本：`/Users/maginawin/Desktop/server data.txt`。
- 本地样本：`/Users/maginawin/Downloads/Space_兴东2_20261028_142843_701+0800.json`，导出时间 2026-10-28 14:28:43（UTC+8）。
- 服务器 `role=owner`，`owner.userId` 与导出顶层 `userId` 一致；本地 SQLite 快照 `permission=1`，对应 owner。
- 本地诊断：`blockedReason=cloudConfigurationConflict`；membershipPhase=joined、configurationInitialized=true、membershipNetworkMatches=true、recoveryPhase=active、recoveryAuthority=writable。
- pendingImport、pendingUpload、pendingDeletionCleanup 均为 false；prefersLocalMembership=true，表明保留了本机优先恢复标记，但不能据此推定此前所有上传或现场恢复已完成。
- 最近同步诊断为 `cleanupPreparation / -2005`，该错误对应 configurationReviewRequired。这个字段是最近失败，不是最初设置保护标记的完整日志。

| 项目 | 本地 | 服务器 |
| --- | --- | --- |
| 实际 nodes 数量 | 262 | 206 |
| deviceCount | 262 | 262 |
| updateTimestamp | 1793158065 | 1793158065 |
| groups / scenes / schedules / switches | 20 / 5 / 3 / 2 | 20 / 5 / 3 / 2 |

服务器 206 个节点均在本地存在，本地另有 56 个节点。样例：L65（2E33）、L80（2E39）、L152（2FB8）、L298（3235）、L500（411E）。两端网络密钥相同（不记录密钥内容）。除 nodes 外，导出与服务器共有字段一致。

共有节点中，85 个 timestamp 不同。206 个节点在本地导出的其他字段上与服务器一致；但服务器另带 props、spaceId、ttl、gatewayInfo 等字段，部分节点还带额外运行统计字段。不能将这些原始 JSON 差异全部认定为业务配置冲突。

## 行为链与比较风险

1. `ImportData.swift / applyRemoteSpaceMetadata` 读取 role；当前本地快照也已是 owner。
2. `SpaceConfigurationSafety.isBlocked` 检查持久化保护原因；cloudConfigurationConflict 足以返回 true。
3. `SpaceData.deviceOperates`、`groupOperates` 在保护状态下仅保留 control（满足正常状态及同步记录条件时）。因此 owner 也不再得到 add/edit/delete。
4. DeviceLights 等设备页面依据 deviceOperates 禁用添加；GroupViewController.moreClick 根据 groupOperates 决定是否放入编辑、成员等菜单。Scene/Schedule 等配置入口共享同一保护逻辑，也会受影响。
5. `reconcileSameVersionNodeRemoval` 对同时间戳、节点变少的响应先执行 Snapshot 比较；失败原因 notOnlyNodeRemoval 会写入 cloudConfigurationConflict。该处理先于 preserveLocalMembershipIfNeeded，因此已有 prefersLocalMembership 不会绕过此核对。
6. `SpaceCloudNodeRemovalPolicy.Snapshot.make` 对 Space 顶层使用字段白名单，但对每个 node 整体序列化后哈希；`removals` 要求所有保留节点哈希完全相等。按这两份样本构造比较时，服务器扩展字段及节点时间戳差异足以令比较失败。

已证实：保护标记、owner 身份、实际数据差异，以及上述原始比较存在接口表示差异导致拒绝的风险。尚未证实：首次设定保护标记时采用的持久化 removalSnapshot 内容；为何服务器少了 56 个节点；节点时间戳变化由哪个写入端造成。导出未包含完整历史比较快照，不能断言首次阻断一定只由 props 等扩展字段触发。

## 用户确认的业务规则（2026-10-28）

服务器完整 Space 响应中消失的已同步设备，按已加入其他 Space 处理，不再调查目标 Space 或要求用户逐个确认。设备集合以 nodes 为准，deviceCount 不参与完整性判断、删除判定或权限恢复判定；允许 Space 时间戳不变。前文关于设备去向的证据限制保留为分析记录，不再作为实施阻塞。

## 已确认实施方案

### 1. 分离设备归属与配置内容比较

扩展现有云端成员协调入口，依据同一 Space、同一网络的有效完整 GET 及已确认同步成员基线，计算已离开当前 Space 的节点。该集合的判定不再要求所有保留节点的原始 JSON 哈希相等，因此 props、服务器扩展字段、节点 timestamp 或缺省表示差异不会阻止成员清理。保留节点存在真实业务配置更新时，交回现有配置导入/冲突机制处理，不以成员清理为理由整体覆盖本机配置。

继续验证账户/Space/网络身份、节点 UUID、地址、Device Key 及 Elements 的有效性，拒绝字段缺失、类型错误、重复身份及旧请求跨代回调。明确空 nodes 数组是合法空空间，可移除全部已确认旧成员；缺少 nodes 字段不能解释为空。

历史完整原始哈希不再是执行成员移除的必要条件。优先复用已确认的 nodeIdentitiesBaseline / 已接受上传回执；旧数据可通过现有完整快照及模型身份资料补齐，而不是要求用户重新选择本机或云端。

本轮覆盖同版本减少，以及正常较新云端响应的对应成员协调路径，避免进入页面和上传前回读采用不同规则。更旧响应不能撤销更新的本机已确认成员状态。

### 2. 复用现有本地移除与清理

复用 DevicePermanentDeletionContext.removeCloudInstances 的持久化日志与重试流程，只移除当前 Space 的旧设备实例，不搜索或修改其目标 Space，不向已迁移设备发送 Node Reset 或重新配置命令。沿用云端移除分支对地址回收的处理，避免跨 Space 迁移后错误释放仍被使用的资源。

一并清理 Group 成员、Proximity 路径/Zone、Space Trigger Zone、Scene 引用、Schedule 设备目标及 nodeSlots、相关扩展记录；HDB 空间沿用其配置清理。重新计算真实设备及灯具数量，刷新当前 Mesh、页面数据与同步缓存。保留有效空 Group、Scene 或 Schedule 的既有处理语义，不额外删除业务对象。

### 3. 自动恢复已锁定空间

让旧 cloudConfigurationConflict、本机优先标记和旧比较快照可以进入该成员修复路径，避免保护状态反过来拦住自己的恢复。先备份及记录移除意图，再删除、清理、持久化并读回核验；成功后更新成员基线和相关恢复状态，撤销由本次成员差异产生的保护。

旧本机优先标记及待上传旧快照不得把已迁移节点重新上传回来。同步准备、回读和失败重试统一使用清理后的成员集，并确保后续自动上传有任务承接。

清理成功且没有独立权限/配置故障后立即恢复 owner/editor 的 add/edit/delete；不等待真实设备在线，不再要求用户在“使用本机数据”和“重新加载云端数据”之间选择。普通上传网络失败按既有重试处理，不重新制造本次成员差异保护。存储或清理失败保留日志，自动重试/下次进入恢复，不能先放开编辑再留下半清理状态。

### 4. 并发与合法新增边界

此规则针对已经确认属于云端版本、后来从响应中消失的旧成员。正在添加、尚未首次上传的本机新设备，不是已迁移旧成员，保留现有新增/上传生命周期，不能被并发 GET 误删。上传结果未确认时先完成回读判定，再协调旧成员，不从较旧请求推断新设备已迁移。

取消、退出空间、切换账户、重复响应、清理中进程退出均复用现有代次和持久化机制。visitor 不获得编辑权限；其他独立的密码验证、离开状态或无效配置保护不因本次成员修复被无条件清空。

### 5. 修改与验证范围

主要修改 SpaceConfigurationIntegrityPolicy、SpaceConfigurationSafety 及必要的 ImportData/同步清理协调接入；仅在现有删除清理有实际缺口时补齐 DevicePermanentDeletionCleanup。使用现有机制，不新增独立通用框架。预计无需修改 SDK 公共 API、固件或服务器，实施中如发现必须改变此边界，另行说明。

使用现有 SpaceRecoveryReceiptTests、导入准备和删除清理测试扩展行为覆盖：

- 本次真实样本脱敏后：262 → 206，deviceCount 仍为 262，Space 同时间戳，服务器扩展字段及 85 个节点时间戳变化，自动删除 56 个旧成员并恢复编辑。
- 旧 cloudConfigurationConflict + prefersLocalMembership 可自动恢复；历史快照不再因原始 JSON 哈希差异阻断。
- 关联引用清理及持久化重载、重复 GET、连续减少、合法空 nodes。
- 本机未上传新增保留；旧响应、身份错误、缺少 nodes、权限撤销不能误删或放权。
- 清理/保存失败后重试、取消/重进，以及上传回读不复活已迁移节点。
- 真实保留节点配置更新交由原有更新机制，不能被本次成员修复静默覆盖。

通过相关回归后运行一次 SunSmart Debug generic iOS 构建，先核对 SunSmartLocal 的 SDK 映射。共享逻辑无品牌差异时不机械重复五品牌构建。用户最终验收：进入兴东2后本地为 206 个实际设备，可添加设备及编辑 Group；退出重进保持正常，云端同步不带回那 56 个节点。

当前状态：用户已确认实施；实施与验证结果见下节。


## 实施结果（2026-10-28）

生产改动集中在 SpaceConfigurationIntegrityPolicy、SpaceConfigurationSafety、SpaceSyncCleanupCoordinator；沿用原有删除日志与关联引用清理，没有更改 SDK、固件或服务器。

- 比较快照增加版本，旧原始 JSON 哈希不会直接与新比较结果混用；优先从已确认完整快照重建，缺少完整快照时使用已确认成员身份、逻辑配置、Timed 和模型基线核对。
- deviceCount 不参与判定；支持同版本或较新版本的成员减少。过滤服务器运行观测和设备时钟 timestamp，并规范化样本中的合法空值/缺省表示。appKeyIndex 是 appKey.index 的冗余别名，缺失允许，显式矛盾仍拒绝。
- 保留实际设备配置变化、Group/Scene 配置变化、错误网络/身份、未确认上传等保护。不会把任意两份不同业务配置一概当作“仅成员减少”。
- 新增清理门禁前的旧成员冲突恢复入口，并修正没有待上传改动的受保护空间跳过 GET 的条件，确保已被锁定的空间也能开始恢复。
- 清理完成更新基线、移除本机优先标记及本次阻断原因，失效保护状态缓存；现有页面清理完成流程刷新列表及权限，原同步机制承接后续上传。

### 自动验证

- `check_space_recovery_receipts.py --owner-removal-sample <server JSON> <inspection JSON>` 通过。执行生产恢复与导入准备代码；真实样本验证先断网不删除、联网重试移除 56 个旧成员、剩余 206 个、旧冲突解除及继续准备上传；同时覆盖现有上传回读、失败重试、旧快照、未上传新增、空集合、连续移除、权限及代次隔离等回归。
- 测试通过路径参数读取现场文件，没有把用户数据或密钥拷贝到仓库；新增通用用例采用合成数据。该套件的 SDK/数据库删除为边界替身，不能据此声称真实 SQLite、Mesh 或服务器已完成验收。
- DeviceScheduleAddressCleanupTests 与 ProximityLightingLifecyclePolicyTests 通过，覆盖设备地址目标清理和路径/Zone 移除策略。
- `check_space_sync_cleanup.py` 内置行为回归通过。曾以现场服务器响应运行其附加样本检查：清理表示及幂等断言完成，但该检查最后要求 proximityMutations=0，现场数据不满足。这说明现场仍可能需要设备同步，不是所有设备已同步的证据；不将该附加检查记为通过。
- 最终 SunSmart Debug generic iOS 构建通过（2026-10-28 14:57，iphoneos27.1、CODE_SIGNING_ALLOWED=NO），使用稳定 DerivedData `SunSmart-fix-llh-sync-261028`。共享逻辑没有品牌编译分歧，本轮选 SunSmart 作为代表；未执行五品牌或 Release 构建。`git diff --check` 通过。
- SunSmartLocal 已确认映射到 `nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `9998967`，SDK 工作树无改动。本次不引入新 SDK API 或依赖发布要求。

### 人工验收

安装本次构建后联网进入兴东2：确认设备变为 206 个，添加入口可用，Group 菜单可编辑；退出重进保持正常；同步后不重新出现那 56 个设备。若设备存在 Unsync，按现场流程完成设备同步，不能以 App 已解除编辑保护代替 Mesh 下发验收。

未自动安装或运行真机，未向线上服务器提交现场数据，未提交 Git。
