# 光感测试 Space 持续同步失败分析与修复方案

日期：2026-09-29。状态：已按用户确认方案完成修复，相关回归、两份现场样本离线复核及 SunSmart Debug generic iPhoneOS 构建通过；未请求线上接口、未操作真机。下文保留修复前分析，末节记录实施结果。

## 结论

本次直接阻断原因是本机持久化的 `legacySpaceZoneDeletionNeedsReview` 保护标志。当前导入代码将“存在 Zone 条目”当成“存在需要保护的 Zone 成员配置”：本地有 5 个 `items=[]` 的空 Trigger Zone，旧云端 `spaceData={}`，因而被误判为云端将删除本地有效区域。

这个状态会持续，因为现有自动恢复仅处理 `upgradeBaselineNeedsImport`，同步准备又不允许在 `legacySpaceZoneDeletionNeedsReview` 下继续。即使单独修正导入判断、或者清掉标志，现有升级基线仍区分“5 个空 Zone”和“旧格式未提供 Zone”，下一次上传可能转为 `upgradeBaselineNeedsImport` 再次阻断。

建议同时修复导入判断、升级兼容比较和存量误拦截恢复。保留本地空 Zone 的数量与顺序，只在旧格式迁移比较中认可无成员配置的等价性；正式提交后的读回确认保持严格。

## 输入与代码状态

- 云端响应：`/Users/maginawin/Desktop/tmp/jesse-sync-290929/get spaceprops.txt`。
- App 导出：`/Users/maginawin/Desktop/tmp/jesse-sync-290929/Space_光感测试_20260929_102804_590+0800.json`。
- Space：光感测试，UUID `520E5BEE-49EE-4F4E-A371-16A3FB1503C4`。
- 工作树：`fix-jesse-sync-260929`；分支：`fix/jesse-sync-260929`。
- 开始分析时 HEAD 为 `3ea9f40a`，已有日程空目标相关的三份代码/测试差异和另一份分析文档。本轮全部保留。分析期间这些内容由外部操作形成提交 `6fc37a2d415eca807b315ede6761374852cb9bc9`（`fix: empty scene timed cannot sync`）；离线复现针对这一当前代码状态。该提交不是本轮创建的。
- 本地 workspace 与 SDK 映射存在，`.local-sdk/nordic-sig-mesh-sdk` 指向既定 `one-dev`。本方案无需 SDK 改动；本轮未构建，未对 SDK revision 作验收结论。

原始文件含网络密钥等敏感数据，不复制到仓库或合成回归夹具。以下只记录非敏感结构与比较结果。

## 文件证据

| 项目 | 云端响应 | App 本地导出 |
| --- | --- | --- |
| UUID、名称、创建时间 | 相同 | 相同 |
| updateTimestamp | 1788531202 | 1788531202 |
| 最后确认云端时间 | — | 原始 spaces 表为 1788531202 |
| 设备 | nodes=[]，deviceCount=0 | 相同；原始 Mesh nodes 表也为空 |
| Group | C008、C009 两个普通组，C00A、C00B 两个开关虚拟组 | 完全相同，包括 Profile 与场景数据 |
| Scene | 0007 / 半亮、0008 / 背光 | 完全相同 |
| Schedule | [] | [] |
| Switch | 开关1；绑定 C009，链接 C00A/C00B，场景 0007/0008 | 完全相同 |
| NetKey、AppKey | 与本地对应对象完全相同 | 相同，不记录密钥值 |
| spaceData | {} | schemaVersion=1，triggerZones 为 5 个 items=[] |

所有双方共有顶层字段中，唯一不同的是 `spaceData`。云端额外含角色、网关等服务端元数据，本地额外含 `appKeyIndex`，不把这些单边字段误报成配置丢失。上述时间戳为 UTC+08:00 的 2026-09-04 22:13:22；App 快照时间为 2026-09-29 10:28:04。

DEBUG 状态进一步提供直接证据：

- `blockedReason=legacySpaceZoneDeletionNeedsReview`。
- `membershipPhase=joined`、`configurationInitialized=true`、`recoveryPhase=active`。
- `pendingImport=false`、`pendingDeletionCleanup=false`、`comparisonPayloadAvailable=true`、`issues=[]`。
- 原始本地 `triggerZones` 数据库 blob 解码后同样是 5 个空条目，并非导出临时补出的数据。
- 原始 `syncCloudError=null`。这不否定保护阻断：页面直接检查 `isBlocked` 就能显示失败，错误枚举不是唯一依据。离线执行当前同步准备对应错误为 `configurationReviewRequired` / -2005，但文件不能证明现场曾记录过该错误码。

该 Space 没有 Schedule，因此前一份 Test space 的 `missingSceneTarget:0` 修复不能解决本次问题。样本也不支持把问题归因为设备数量不一致、密钥不一致、HTTP 请求失败或服务端丢设备。

## 代码因果链

1. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 `SpaceData.update` 在时间戳决定是否需要覆盖之前，调用 `legacySpaceZoneDeletionNeedsReview(..., hasLocalZones: !self.triggerZones.isEmpty)`。本地数组长度是 5，参数为 true，即使 5 个条目均无成员。
2. [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 遇到旧格式无 schema、无 triggerZones 或空数组时返回需要人工复核。因此同一时间戳的 GET 也足以触发本次拦截，无需发生实际配置覆盖。
3. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `block` 将首个原因持久化到按账号、区域、Site Mesh 和网络标识隔离的 UserDefaults；后续普通重试不会自动移除。
4. [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的 `updateSyncState` 优先检查 `isBlocked` 并显示失败/恢复入口。因此“业务配置没有待上传变化”“syncCloudError 为空”与“页面持续失败”可以同时成立。
5. [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 在同步前先调用 `recoverUpgradeBaselineIfNeeded`。该函数仅识别 `upgradeBaselineNeedsImport`，对本次原因直接返回 true，未读取本地、未发 GET、未解除保护。
6. 随后的 `canCleanSyncReferences` 原因白名单不包含本次标志，准备失败。[CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 的 `.syncSpace` 因此不能进入 `.spaceUpload`；Export/prepareUpload 也有保护门禁。
7. 即使绕过上述标志，`upgradeConfigurationData` 只会把旧格式缺失的 triggerZones 补为 `[]`，不会把 5 个空条目视为无成员配置；当前 `upgradeRecoveryConfiguration` 也保留该差异。因此必须一起修复升级比较，不能仅把导入条件改成成员判断。

现有 Space 入口、前台恢复和显式同步都可到达 cleanup coordinator，应在这个共享入口复用恢复机制，不为页面单独增加清标志逻辑。正常“重新加载云端数据”仍经过 `restoreConfiguration → update`，对同样的旧云端和本地空条目可能再次触发拦截，不能作为必然有效的解除方法。

## 空 Zone 从何而来：已知与未知

[SpaceTriggerZone.swift](../SunSmart/Main/Space/TriggerZone/Model/SpaceTriggerZone.swift) 的 default(count:) 可以创建空条目。[SpacePathTriggerZoneController.swift](../SunSmart/Main/Space/TriggerZone/Controller/SpacePathTriggerZoneController.swift) 允许添加指定数量 Zone，保存通过既有生命周期协调器进行；清除无效成员也会保留 Zone 条目。

因此空条目是模型可保存的合法状态，不应被当作损坏配置。文件不能还原这 5 个条目最初来自用户添加、历史版本行为还是成员清理，也不能证明最初设置保护标志时的 App 构建版本。当前文件和生产逻辑足以复现此次误判及持续阻断，无需推测唯一操作历史。

## 离线复现结果

使用临时 harness 复用 `scripts/check_space_recovery_receipts.py` 的隔离环境，直接编译当前完整性策略、拓扑清理策略和生产恢复/上传准备方法。输入通过外部路径读取；网络、数据库和 checkpoint 使用原有测试边界；执行结束删除临时产物。不修改现场文件或实际 App 数据。

| 检查 | 结果 |
| --- | --- |
| 现场云端 + 本地 Zone 数量条件 | 当前导入策略返回需要复核 |
| 仅将参数改为“是否存在成员”的内存实验 | 返回不需要复核，5 个 Zone 共 0 个成员 |
| 两份原样 Profile、Schedule、拓扑检查 | 均通过；normalize 的 didChange=false |
| 当前严格配置、升级基线、升级恢复比较 | 两份均不相等 |
| 仅在内存中把本地全空 Zone 数组换成 [] | 升级基线和升级恢复比较均相等，定位到这一差异 |
| 持久标志为本次原因，执行当前恢复函数 | 返回 true，但仍 blocked；本地读取=0、GET=0 |
| 随后执行 cleanup 资格/prepareUpload | 均不允许，配置错误映射为 -2005 |
| 不设旧标志，合成相同身份和确认时间，保留两侧 Zone 差异 | prepareUpload 再次生成 upgradeBaselineNeedsImport，失败为 -2005 |

最后一项使用现有测试身份替身及合成密钥，隔离验证 Zone 差异的影响；不能把它当作真实网络身份或服务器验收。内存中移除空条目仅用于定位，不是建议删除用户的 5 个 Zone。

## 推荐修复范围

### 1. 导入保护判断实际成员

- 将 `hasLocalZones` 明确为“本地存在成员配置”，由 typed Zone 的 items 判断。
- 本地仅有可正确解码的空条目，远端是已知合法旧格式缺失/空值时，不生成删除有效配置保护。
- 本地任一 Zone 含成员，旧端省略区域信息仍保留原有保护；本地解码失败、远端结构损坏或未知 schema 继续阻断，不能把解析失败当成空。
- 保留 schema 1 显式清空的既有语义，保留 Zone 数量和顺序；不要自动删除空 Zone 或改动用户配置来消除比较差异。

### 2. 升级比较兼容全空 Zone

- 在升级基线/历史保护恢复的专用比较中，将已验证的“旧格式缺失”“空数组”“全部仅含合法空 items 的 Zone 条目”规范化为同一无成员表示；限于已知字段与受支持 schema。
- 只改变比较副本，不改持久化 payload。任一 Zone 有成员时，完整数组、成员与顺序继续参加比较，不对混合数组删除空槽或重排。
- `configurationData`、提交回执和上传后 GET 读回继续严格比较：提交 5 个空 Zone 而读回少条目/缺字段/多成员时，仍不能确认上传成功。

### 3. 安全解除已经产生的误拦截

- 在既有共享恢复链路中识别本次精确原因，复用现有升级恢复的抓取、快照和持久化机制；不把它简单加入清理白名单，也不在启动时无条件删除 UserDefaults。
- 自动恢复前要求本地全部 Zone 确认无成员、无解码失败，无未上传修改；本地更新时间与最后确认时间一致。
- 重新 GET 同一 Space，检查远端身份和确认版本，以及非 Zone 业务配置一致。校验网络密钥、节点 UUID/地址/Device Key；不能仅凭时间相同就清除保护。本次双方 nodes=[]，节点比较应支持合法空集合。
- 保留现有权限、membership、账号/区域、generation、取消、同秒改动复查与两次本地读取；存在 pending import、submission、删除/引用清理或解绑等状态时不走此快捷恢复。
- 快照与基线持久化成功后，才移除精确误拦截标志、更新保护代次并清理相应错误/缓存；读回失败或其他真实差异继续保留保护。恢复不得凭本地操作伪造上传确认时间。
- 原因是 `upgradeBaselineNeedsImport` 且同样只有全空 Zone 表达差异的历史空间，复用升级比较后也应可恢复。其他原因继续按原策略处理。

预计生产修改集中在 `ImportData.swift`、`SpaceConfigurationIntegrityPolicy.swift`、`SpaceConfigurationSafety.swift`，必要时调整 `SpaceSyncCleanupPolicy.swift` 的比较入口。沿用 coordinator，不新增恢复子系统；不需要 SDK API、协议、数据库迁移、服务端修改或 UI 文案。

## 实施后的最小验证与验收

1. 完整性策略：旧格式缺失/[] 对 0、1、5 个合法空 Zone 的兼容；含成员保持保护；混合空槽顺序不变；错误类型/缺 items/未知 schema/本地解析失败拒绝。
2. 真实生产恢复方法的隔离回归：已持久化本次标志能恢复；相同时间真实 Profile/Scene/Switch/节点或密钥差异不恢复；失败 GET、权限变化、pending 操作、取消和同秒编辑保持保护，后续合格重试可收敛。持久化失败不得提前放行。
3. 正式回执：5 个空 Zone 提交后完整读回可确认；字段丢失、数量/顺序变化或成员变化仍不确认。旧回执兼容保持。
4. 导入链需覆盖实际传入成员判断和再次 GET 不复发。现有 `check_space_recovery_receipts.py` 的导入替身只执行 update 的异步准备前缀，没有执行本次出错的 continuation 段；不能仅凭该脚本通过就声称导入条件已覆盖。
5. 用这两份现场文件离线复核，并运行对应完整性策略、cleanup 和恢复回执现有回归。Swift 修改完成后构建一次 SunSmartLocal / SunSmart / Debug / generic iPhoneOS，禁用签名；纯共享逻辑无品牌分支时不机械做五品牌构建。
6. 用户验收：修复版本进入“光感测试”并触发正常同步/重试，保护状态应解除；退出重进、再 GET 不复发；原有组/场景/开关及 5 个空 Zone 保留。若执行了上传，核对服务端 schema 1、Zone 数组及上传后读回确认；若只是证明已有配置等价，不要求无故推进上传时间。

分析阶段仅证明根因和策略缺口。现有“使用本机数据”是整空间替换的人工恢复路径，不作为本方案的自动处理；普通重试、删组、改日程或清缓存均不能替代针对性修复。

## 实施结果

用户确认后，生产修改集中于三份文件：

- `ImportData.swift`：删除保护改为检查实际 Zone 成员；本地解码失败仍视为需要保护。旧格式无 schema 的 `triggerZones=[]` 在非初始化导入中与字段缺失一样保留现有 Zone，防止通过导入检查后又清除空条目。schema 1 显式清空和首次初始化保持原语义。
- `SpaceConfigurationIntegrityPolicy.swift`：迁移比较验证 Zone 结构，折叠合法且仅含空 items 的全空条目；未知 Zone 字段、混合成员/空槽和顺序继续保留在比较中。规范化只发生在比较副本，正式配置比较和上传回执没有放宽。
- `SpaceConfigurationSafety.swift`：既有恢复函数同时处理精确的空 Zone 历史原因。该原因仅在确认本地无 Zone 成员时参与自动恢复；复用 fresh GET、确认版本、权限及 pending 操作门禁、两次本地读取、checkpoint 和基线持久化。补充节点完整身份对照，包括 Device Key 指纹和 element 地址；不一致或缺失继续保留保护。成功后解除保护，保留原配置和最后确认时间。

未修改 SDK、协议、数据库 schema、UI、国际化文案或服务器。未提交或推送。HEAD 保持 `6fc37a2d`；构建使用既有 `SunSmartLocal.xcworkspace`，SDK realpath 为既定 `one-dev`，SDK HEAD 为 `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，核对时无未提交改动。

### 自动化证据

- 新回归先在原生产实现上失败：完整性策略在“全空 Zone 应与旧格式缺失等价”处失败；恢复测试在“5 个空 Zone 应能解除保护”处失败，均为预期业务断言。
- 完整 `SpaceConfigurationIntegrityPolicyTests` 通过：0/1/5 个空条目、旧/新 schema、混合数组顺序、未知字段、无效 items/地址、严格读回及已有日程兼容覆盖通过。
- 完整 `scripts/check_space_recovery_receipts.py` 通过：两种历史原因、owner/editor、空节点/有效节点、身份及配置差异、失败 GET 后重试、pending 操作、取消/同秒编辑/权限变化、持久化失败；新空 Zone 回执在丢字段、数量变化和成员变化时拒绝确认，完整读回后可重试成功。
- 扩展该脚本执行真实导入 Zone 拦截片段，验证连续 GET 对 0/1/5 个空条目不再设保护；含成员或本地解码失败仍拦截。测试仍使用 SDK/数据库边界替身，不宣称覆盖整个 App importer。
- `scripts/check_space_sync_cleanup.py` 通过，已有完整快照清理、幂等和异常输入行为保持。
- `scripts/check_proximity_scoped_import.py --snapshot <本次云端文件>` 通过：执行生产 preflight、实际 Zone 字段赋值及生命周期提交，确认旧端缺字段/[] 保留 5 个空条目且不制造本地修改；初始化和 schema 1 清空正常，现场云端通过 preflight。
- 临时离线 harness 直接读取两份现场文件，分别注入两种历史原因，执行生产恢复函数及 `prepareUpload`：均可解除保护并通过上传门禁，保存的完整本地快照与输入逐字节规范序列化结果一致，5 个空条目保留；严格配置比较仍能区分旧云端缺字段与本地 5 个空条目。网络和存储使用现有测试边界，未访问服务器或设备；临时数据随 harness 结束清理。
- `git diff --check` 通过。恢复回执编译仍有测试替身枚举引起的既有 `default will never be executed` 警告，没有对应测试失败。

### 构建与剩余验收

直接执行一次 `xcodebuild`：workspace=SunSmartLocal、scheme=SunSmart、configuration=Debug、sdk=iphoneos、destination=generic/platform=iOS、CODE_SIGNING_ALLOWED=NO，固定 DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-jesse-sync-260929`。命令退出码 0，产物更新时间为 2026-09-29 10:49:19（UTC+08:00）。本次为共享逻辑，无新增品牌条件分支，因此没有机械重复五品牌或 Release 构建。

尚待用户真实验收：安装本次构建，进入“光感测试”触发同步/重试，确认失败标志解除；退出重进并再次读取云端，确认不复发，组、场景、开关及本地 5 个空 Zone 保留。若发生上传，再确认云端完整读回一致。离线策略、隔离恢复和构建结果不能代替这一步。
