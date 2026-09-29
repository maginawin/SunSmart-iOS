# Jesse Test space 云同步失败分析

日期：2026-09-29。状态：已完成现场分析及用户确认的修复，相关回归和 SunSmart Debug generic iPhoneOS 构建通过；未请求线上接口，未操作真机。下文分析保留修复前证据，末节记录实施结果。

## 结论

修复前确认的上传阻断点是 `Schedule 1`（日程索引 0）的 `selectTarget=2`、`sceneAddress=null`。App 的云端导出校验把它判为 `missingSceneTarget:0`，记录 `configurationExportInvalid`（-2003），随后返回 nil，无法生成 Space 上传请求。现场本地数据库保存的错误正是 -2003，两份 DEBUG 导出也明确记录同一日程问题。

这份空目标既存在于云端，也已经写入本地数据库，并非此次导出时临时丢失。现有 UI 和数据模型支持保存 `.scene(nil)`，自动引用清理也可能在场景不存在时清空引用；2026-09-23 新增的上传限制没有区分空目标配置与上传过程中丢失原有目标。因此，在保留现有“允许无目标日程”语义的前提下，这是上传校验与现有业务状态不一致的兼容问题。

用户先确认业务规则：允许保留并同步空目标日程；仍拦截有效目标在同步中丢失，随后确认完整方案实施。实现保留明确的空目标，同时继续比较提交与读回的目标摘要。空目标日程仍无执行目标，不推断它本来指向哪个场景。

## 环境与输入

- App 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix-jesse-sync-260929`。
- 分支：`fix/jesse-sync-260929`；HEAD：`3ea9f40a2f3a60683d377afcb98e88d7181ac24e`。调查开始时工作树干净。
- `SunSmartLocal.xcworkspace` 的 `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD 为 `2598bd1`，检查时无未提交改动。本方案不需要 SDK 修改。
- 输入目录：`/Users/maginawin/Desktop/tmp/jesse-sync-290929/`。
- 云端样本：`get-spaceprops.json`。
- Site 导出：`Site_TEST ONLY ._20260929_090510_078+0800.json`。
- Space 导出：`Space_Test space_20260929_090528_128+0800.json`。

原始文件不复制到仓库；本文不保存凭据或密钥。以下时间均为 UTC+08:00。样本文件的完整 App 版本/构建号未知，代码路径按上述当前分支核对。

## 三份数据交叉证据

Site 导出中的 Test space 与独立 Space 导出的业务 payload 完全相同。两者分别采集于 2026-09-29 09:05:10 和 09:05:28。

| 项目 | 云端 | App 本地 |
| --- | --- | --- |
| 空间 | Test space，同一 UUID | 同一 UUID |
| Schedule 1 | id 0、启用、Scene 类型、sceneAddress=null | 业务导出及原始 schedules 表均为空 |
| 场景 | 0001 / Scene 1、0002 / PPT | 相同 |
| nodes | 0 | 0，原始 Mesh nodes 表也为空 |
| deviceCount | 2 | 导出为 0 |
| Groups | 31，包括 C001 / Group 2 | 30，没有 C001 |
| Weekend auto（id 1） | profiles 包含 C001 | 已移除 C001 引用 |
| Switch 2、Switch 3 | bindGroupAddresses=[C001] | bindGroupAddresses=[] |
| 更新时间 | 1789726128，2026-09-18 18:08:48 | 1790578167，2026-09-28 14:49:27 |
| 本地最后确认上传时间 | — | 1789726128，与云端一致 |
| DEBUG 问题 | — | schedules: missingSceneTarget:0 |
| 本地错误 | — | syncCloudError=-2003 |

其他相关事实：

- 云端与本地 NetKey、AppKey 对象分别完全一致。本次节点集合为空，没有 Device Key 可用于节点层面对比。
- 云端角色为 owner；本地 membershipPhase=joined、recoveryPhase=active、configurationInitialized=true，pendingImport 和 pendingDeletionCleanup 均为 false。
- Site 的七个 Space 中，仅 Test space 在本次 DEBUG 导出记录了完整性问题。
- Group C002 的本地 `proximityLightingPath` 比云端多出空的默认 paths/zones 结构。它不是本次复现的日程校验错误。
- 云端 `deviceCount=2` 与云端自身 `nodes=[]` 不一致，应在后续成功上传/读回时核对收敛；三份文件均没有这两个节点的实体，不能据计数推断应恢复哪些设备。
- 本地 C001 缺失及关联引用清除与一次组删除后的结果一致，但文件不能证明具体操作历史。修复应保留这些本地差异，避免用旧云端覆盖后让组和绑定重新出现。

## 代码因果链

1. [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 的 `.syncSpace` 先执行清理准备，再调用 `space.export(purpose: .cloudSync)`。导出失败时返回 nil，只有导出成功才创建 `.spaceUpload`。
2. [ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 从目标 Space 的数据库加载日程，编码为 payload，再执行 `SpaceConfigurationIntegrityPolicy.scheduleTargetIssue`。出现问题时记录 `exportScheduleTarget` / `configurationExportInvalid` 并返回 nil。DEBUG inspection 则保留数据供分析，因此“能导出 DEBUG JSON”不代表可上传。
3. [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 对所有 `selectTarget==2` 的日程要求 `sceneAddress` 为字符串且存在于当前 Space 的 scenes 中。它不区分启用/停用、明确空目标或传输丢目标。样本在 id 0 处必然失败。
4. [NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift) 将 `configurationExportInvalid` 映射为 -2003，与原始本地记录一致。
5. [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 不会替空目标猜选场景。现有 [SpaceSyncCleanupPolicy.swift](../SunSmart/Common/Data/SpaceSyncCleanupPolicy.swift) 对两份样本都返回 `didChange=false`，重试不会修复它。
6. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的普通更新路径不会用更旧的云端时间覆盖较新的本地配置；即使强制导入这份云端，其日程目标仍为空，也无法消除该错误。

Site 包含该 Space 的上传也复用 Space 导出链路，因此问题可能影响包含它的 Site 同步，但不据此断言其他六个 Space 自身也存在同样错误。

## 为什么空目标能够出现

有三个可确认的代码条件，但现有资料不能还原样本最初产生空值的唯一历史：

- [ScheduleAddView.swift](../SunSmart/Main/Timed/View/ScheduleAddView.swift) 的 `isCompletion` 只检查已选择目标类型、动作和时间；`.scene(nil)` 不会因未选具体场景而失败。[ScheduleScenesView.swift](../SunSmart/Main/Timed/View/ScheduleScenesView.swift) 的确认回调接受可选 Scene。[ScheduleAddViewController.swift](../SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift) 会用 `scene?.number` 保存日程。因此不需要假设异常网络，就能产生此类本地数据。
- 同步清理中的 `extensionChanges` 会将不再存在的 Scene 引用清为空，并维护相关待清理设备引用。现有生命周期也能产生空目标。
- 历史 [Scheduler.swift](../SunSmart/Main/Timed/Model/Scheduler.swift) 编码通过全局活动网络查询 `scene?.number`，导出非活动 Space 时存在目标丢失条件。提交 `4176abe6`（2026-09-23）改成编码已存储的 `sceneNumber`，同时增加严格上传校验。当前编码已修复，但无法恢复数据库中已经丢失的值。样本云端时间早于该提交；这使历史编码问题成为可能来源，而非已证实来源。

现有两个场景都不能提供足够证据确定 Schedule 1 原先应指向 0001 还是 0002。不得自动选择其中一个或把历史空值伪装为已恢复。

## 离线验证结果与边界

使用临时 Swift harness，直接编译当前生产 `SpaceConfigurationIntegrityPolicy`、`SpaceSyncCleanupPolicy` 和其拓扑依赖，读取现场文件；不改原始 JSON、不连接服务器或设备。

| 输入变体 | 云端样本 | 本地样本 |
| --- | --- | --- |
| 原样执行日程校验 | missingSceneTarget:0 | missingSceneTarget:0 |
| 执行现有自动清理后 | didChange=false，错误仍在 | didChange=false，错误仍在 |
| 仅把 id 0 enabled 改为 false（内存中） | 仍失败 | 仍失败 |
| 仅在内存中给 id 0 指向存在的 0001 | 日程校验和目标摘要生成通过 | 同左 |
| 仅在内存中移除 id 0 | 日程校验通过 | 同左 |

这些变体用于定位阻断字段，不是对用户数据的修复，也不构成替用户选择 Scene 1 的建议。

已有 `scripts/check_schedule_scene_target_export.py` 通过，证实当前生产编码在没有全局活动 Scene 查找结果时仍能保留已存的场景地址，已存 nil 则仍编码为 null。

以上是修复前的离线定位结果，证明该字段足以触发上传阻断；它们不验证完整 App、全部恢复基线、线上上传/读回或 BLE 行为。分析阶段没有执行 iOS 构建或真机测试；后续实施验证见末节。

## 已确认修复范围

推荐沿用现有空目标日程语义，收敛到共享校验及目标读回摘要，不改变网络身份、权限、完整配置快照或设备同步策略。

1. **共享校验区分明确为空与无效引用。** 在 `SpaceConfigurationIntegrityPolicy.scheduleTargetIssue` 中允许 Scene 类型日程的显式 `sceneAddress=null`。非空值仍必须为对应目标 Space 中已有 Scene 的地址字符串；重复 ID、错误类型和缺字段保持校验。校验器不把损坏的非空引用转换为空。
2. **空目标参与完整的上传确认。** `scheduleTargetsData` 为明确空目标生成稳定摘要。当前提交、直接读回和恢复回执均复用这一入口；空→空可确认，有效地址→空、空→其他地址、任务缺失或目标变化均不能确认。核对 `prepareSubmission`、`readUploadedConfiguration`、`resumeUpload` 的行为，不能只删掉 Export 层检查。
3. **保留现场业务数据。** 不自动删除或停用 Schedule 1，不猜选场景；保留 Group 2 删除及关联清理结果。无目标日程依旧没有执行目标。如果用户希望它实际执行，再由用户在 Timed 中选择正确场景。
4. **范围与文件。** 预计生产修改集中在 `SpaceConfigurationIntegrityPolicy.swift`；回归补到 `SpaceConfigurationIntegrityPolicyTests.swift` 与 `SpaceRecoveryReceiptTests.swift`。现有 `Scheduler.swift` 编码修复保持。无需新协议字段、SDK API、数据库迁移或新恢复子系统；如实施时发现调用者存在额外阻断，再以证据确定最小补充范围。

已排除的备选方案：坚持“Scene 日程必须有具体场景”，在新增/编辑处同步收紧校验，并对存量日程明确提示补选或删除。这会改变现有可保存的状态，需要相应界面与国际化处理；在用户完成处理前，此 Space 仍不能上传。用户选择保留空目标，因此本轮不采用此方向。单纯放开 Export 返回值不足以解决后续回执生成失败，直接清除错误标志也不会修复数据链路。

### 实施后的验证与验收

- 策略行为：空 Space、有效 Scene、显式空目标（启用及停用）、不存在 Scene、错误类型、缺字段、重复 ID、非 Scene 类型日程均覆盖。
- 读回/重试：空→空成功；非空→空和空→非空拒绝确认；读回失败后保留回执，后续正确读回收敛；旧回执继续兼容。新增用例使用脱敏合成数据。
- 现场复核：通过外部文件路径重跑样本策略；期望原样通过目标校验，业务内容和本地删除差异不被改变。
- 运行相关日程编码、完整性策略与恢复回执回归；生产 Swift 修改稳定后，构建一次 `SunSmartLocal.xcworkspace` 的 SunSmart Debug generic iPhoneOS，禁用签名。共享逻辑无品牌分支，不机械重复五品牌构建。
- 用户最终验收：目标 Space 点一次云同步 → 成功后重进仍无云同步失败 → 再取 `get/spaceprops`，核对日程保留且空目标仍为空、C001 及其绑定不恢复、nodes 与 deviceCount 收敛、确认上传时间推进。HTTP 成功本身不替代读回一致性验收。

旧版临时处理：若尚未安装修复版本，用户可在 Timed 中为 Schedule 1 补选确实需要的场景，或明确决定删除该日程后再试云同步。仅停用日程不能绕过旧版校验；不建议强制覆盖本地或重新加入 Space，以免丢失尚未上传的变更。

## 实施与验证结果

用户确认后，生产改动仅位于 `SpaceConfigurationIntegrityPolicy.swift`：Scene 类型日程的显式 `NSNull` 视为可保存的空目标，其他类型错误、缺字段、无效 Scene 引用和重复 ID 继续拒绝。空目标沿用已有 `scheduleTargetsData` 的空字符串摘要表示，保留日程 ID 和目标类型，因此无需变更回执格式或修改调用者。

未修改日程业务内容、上传/恢复状态机、数据库、UI、协议或 SDK。现场原始文件未被修改。App HEAD 仍为 `3ea9f40a`，本地 SDK 仍为 `one-dev` / `2598bd1`；没有提交或推送。

### 自动化证据

- 先补回归并运行旧生产实现：`SpaceConfigurationIntegrityPolicyTests` 在“显式空目标应合法”处失败；`check_space_recovery_receipts.py` 在“空目标应能创建持久上传回执”处失败。确认是预期行为失败后才修改生产校验。
- 修改后，完整 `SpaceConfigurationIntegrityPolicyTests` 通过。新增覆盖启用/停用空目标、无 Scene 的空目标、JSON 往返、空目标后续条目的校验、错误类型、缺字段和空目标重复 ID。
- 完整 `scripts/check_space_recovery_receipts.py` 通过。新增用例执行生产回执与读回函数，验证空目标提交、网络失败保留回执、空→具体场景/字段缺失/日程删除拒绝确认、正确读回重试后清除回执并更新确认时间；已有具体场景→空目标失败重试与旧回执兼容覆盖继续通过。
- `scripts/check_schedule_scene_target_export.py` 通过，已有场景地址仍从日程持久值编码，不依赖全局活动 Scene 查询。
- 临时离线 harness 读取两份现场云端/本地快照，执行生产校验与目标摘要：两份原样通过、JSON 读回摘要一致，日程 0 仍为空，调用前后业务 JSON 相同。未将现场敏感数据加入测试或仓库。
- `git diff --check` 通过。回执测试编译有测试替身枚举导致的既有 `default will never be executed` 警告，没有测试失败。

### 构建证据与剩余验收

直接执行 `xcodebuild`，workspace=`SunSmartLocal.xcworkspace`、scheme=`SunSmart`、configuration=`Debug`、sdk=`iphoneos`、destination=`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`。固定 DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-jesse-sync-260929`，使用当前 iPhoneOS 27.0 SDK。

构建退出码为 0，并生成新的 `SunSmart.app/SunSmart`。命令输出包含 `the following command failed with exit code 0 but produced no further output` 异常提示，因此进一步核对 Xcode 的 `Logs/Build/LogStoreManifest.plist`：该次构建记录为 0 errors、121 warnings、0 test failures，产物时间为 2026-09-29 10:14:34。警告涉及既有依赖/未修改文件的 Swift 兼容、捕获及废弃 API；没有为消除警告修改无关代码，没有重跑构建或清理缓存。

这些结果证明本次 App 代码可编译和相关隔离行为通过，不等同于真实云端或 BLE 验收。待用户使用该构建在 Test space 同步一次，核对成功后重进状态，以及服务端日程空目标、C001 删除、关联绑定、设备计数和确认时间是否按前述要求收敛。
