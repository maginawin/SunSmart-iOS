# M4 空间固件版本未刷新与云同步失败分析

日期：2026-09-30（UTC+8）。范围：根因分析及用户确认的 A/B/C 修复已实施；自动回归与 SunSmart generic iOS 构建通过，真实设备及服务器验收待用户执行。

## 结论

现有证据指向 App 的两端修改冲突处理不完整：Owner 保留未确认上传的本地状态，云端同时存在固件信息更新和不同的设备实例；上传前的成员协调只能处理严格受限的删除情形，其他冲突直接返回 `configurationUploadUnconfirmed`，没有转换为可完成的冲突恢复流程。普通导入也在该保护处提前退出，或因空间级时间戳判断而跳过，因此云端固件信息没有进入 Owner 数据库。

分析阶段已用修复前生产方法复现“GET 一次、POST 零次、返回 -2002、没有进入待审阅状态”。这不是通过关闭保护或强制上传可以安全解决的问题：两端各有另一端没有的设备实例，旧本地快照也携带旧固件信息。

证据边界：三份文件没有包含 App 沙盒中的恢复状态、上传回执、删除日志和 UserDefaults。因此可以确认数据分叉和代码缺陷，并复现同样的失败路径，但不能唯一确定现场卡在“已确认基线”还是某一笔 `prepared/accepted` 回执，也不能凭数据库推断操作者及其操作意图。

## 输入与工作状态

- 空间：`103F386B-E05D-497B-BB0D-9131B1E9CB6A`，名称 `3F-Office`。
- Site / Mesh UUID：`86BE1E82-2031-4846-B7E3-7025346CEB6B`。
- 输入目录：`/Users/maginawin/Desktop/tmp/cannot sync M4/`，包括服务器 JSON、`mesh.sqlite3`、`sunsmart.sqlite3`。
- 用户确认 JSON 从 Editor 账号抓取；响应中的 `role=editor` 不作为 Owner 权限错误证据。Owner 是否主动重新配网 L268 不确定。
- App 分支：`fix/delete-devices-260928`；HEAD：`cde663a99f8fb4d78c178a9db69c8938a9be23f3`。分析开始时工作树干净。
- 本地 SDK 映射：`SunSmartLocal.xcworkspace`、`.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；SDK HEAD：`2598bd169417b894dcb11ba7cf6c63185d7c5a66`，核对时无未提交修改。
- 数据库以只读方式访问；未调用真实服务器、未操作真机、未修改输入文件。本文不保存凭据或密钥内容。

## 数据比对

### 空间状态与时间线

| 记录 | 时间（UTC+8） | 含义 |
| --- | --- | --- |
| Owner `lastUploadCloudTimestamp=1790669734` | 09-29 16:15:34 | 本地记载的最后确认云端版本 |
| 云端 L90 `createdTimestamp=1790672445` | 09-29 17:00:45 | 云端设备实例的创建时间字段 |
| 云端 `updateTimestamp=1790731626` | 09-30 09:27:06 | 当前提供的云端空间版本 |
| 本地 L268 `createdTimestamp=1790732387` | 09-30 09:39:47 | 本地实例记录的创建时间字段 |
| Owner `lastUpdateTimestamp=1790732398` | 09-30 09:39:58 | 本地空间版本，比提供的云端版本大 772 秒 |

Owner 空间 `permission=1`（Owner）、`state=1`（正常），`lastUpdate > lastUploadCloudTimestamp`，故 `needUploadCloud=true`。Space 与 Site 均存有 `syncCloudError=-2002`；它是 App 定义的“无法确认云端同步结果”，不是服务器 HTTP 错误码。

空间时间戳代表整份空间的本地修改代次，不代表每台设备固件信息的新旧。L268 的创建时间不能证明是 Owner 本人主动配网；这里只把它视为本地实例的持久化字段。

### 固件信息

按 UUID 比较，两端共同 UUID 中有 91 台设备的 `firmwareID` 不同。其中用户问题最明显的一组为 PID `2802`：

| 数量 | Owner 本地 | 云端 |
| --- | --- | --- |
| 60 | `0201050000000000` → `2.1.5` | `0201060000000000` → `2.1.6` |
| 29 | `0200040000000000` → `2.0.4` | `0201060000000000` → `2.1.6` |

上述 89 台包含下面发生实例变化的 L90，不能将它当作“同一实例的普通固件字段更新”。其余 88 台 PID 2802 的实例身份一致。

另有 PID `2011` 的 L60、L112 固件字段不同：L60 云端为 `0201010011154000`，L112 云端为 `0900000000000000`，Owner 两者都是 `0200040000000000`。没有设备侧证据，本次不判定 L112 的云端版本是否合法，也不据此扩展固件协议修改。

这里确认的是服务器和本地保存值的差异；并非对 89 台设备实际运行固件逐台验收。

### 273 台并不意味着成员一致

| 对象 | Owner 本地 | 云端 | 判断 |
| --- | --- | --- | --- |
| L90 | UUID `5AB6836A-AE7A-4825-A549-7C95518597DA`，地址 `05AE` | 相同 UUID，地址 `15ED` | Device Key 也不同，属于不同配网实例 |
| L268 | UUID `4D6C37F3-9C01-46BC-B293-C80C63FE3943`，地址 `0D6C` | 无此 UUID | 本地独有，不能自动丢弃 |
| L271 | 无此 UUID | UUID `C812C465-3E04-4B70-B7ED-3B9AC1FB748F`，地址 `139C` | 云端独有；没有删除日志不能推定应恢复或删除 |

因此：UUID 集合差异是一进一出；按生产代码的 `UUID + address + Device Key 指纹` 标准，两端各有两个不匹配实例，其余 271 个实例一致。相同 UUID 不足以把 L90 的旧实例当成云端新实例。

### 已排除或校正的方向

- 两个 SQLite 文件 `PRAGMA quick_check` 均返回 `ok`，未发现文件结构损坏；这不等于业务状态已收敛。
- 对应空间的 NetKey、AppKey 索引及 Key 内容一致。不是当前样本缺失或错配空间网络密钥。
- 云端有 18 个 Group；本地 Mesh 数据库也是 18 个。App `groupInfos` 与显示摘要只有 16 个是因为另外两个是开关虚拟组 `CC82/CC83`，不能把差值 2 当成丢组。
- 对应 16 个实体组的已映射 Profile 字段、规范化后的 Profile Scenes 未发现差异；共同设备的组状态及订阅所对应的云端归组未发现差异。
- 直接对实际服务器 JSON 调用当前 `SpaceConfigurationIntegrityPolicy`：Profile、配置投影、Schedule targets、Scheduler snapshots、273 个实例结构校验均有效。
- 仅替换节点 `firmwareID` 不改变 `configurationData` 比较结果，固件升级本身不会触发这个逻辑配置比较失败。

## 代码链路与根因（修复前）

### 1. 固件显示是本地值，云端字段被整体导入门槛挡住

[DeviceInformationViewController.swift](../SunSmart/Main/Device/Controller/DeviceInformationViewController.swift) 的展示来自 `node.firmwareVersion`，SDK 从本地 `firmwareID` 解码。设备信息页还可以直接读取设备版本，但这不是 Space 云同步完成的证明。

[ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 中 `SpaceData.update` 的关键顺序：

1. 处理远端元数据、权限与本地删除恢复。
2. 执行 `reconcileCloudMembership`；失败时返回 `preserved("cloudMembershipNeedsReview")`。
3. 存在未完成上传、删除或恢复时继续保护本地状态。
4. 到达普通导入决策后，比较空间级 `updateTimestamp` 与本地 `lastUpdate`。
5. 只有实际导入才会走到节点的 `firmwareID` 赋值与持久化。

当前样本在第 2/3 步具备冲突条件；即使越过这两步，在没有其他恢复条件时，云端 `1790731626 < 本地 1790732398` 也会让第 4 步跳过整份导入。代码没有在此处独立合并同一实例的固件观察值。

### 2. “只发 GET 就停”的具体返回路径

[CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 在构造并发送上传请求前，先对空间执行 `SpaceConfigurationSafety.resumeUpload`。失败就 `finishConfigurationFailure` 并直接返回，因此不会产生 `/sync/spaceprops`。

[SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `resumeUpload` 有两条相关路径：

- 没有 pending submission，但有已确认成员/Scheduler 基线且本地 dirty：先 GET，再协调云端成员。
- 有 pending submission：先 GET 核对旧上传结果，再协调云端成员及配置，随后才有机会确认旧回执或上传新修改。

成员协调调用 [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 中 `SpaceCloudNodeRemovalPolicy.removed`。它只允许远端实例集合是基线实例集合的子集；新增实例、相同 UUID 换地址或换 Key 都不能被解释成“只删除”。这是必要的身份保护，不能删除该校验。

但目前这些情形通过 `Bool=false` 统一返回 `-2002`，没有记录需要人工审阅的原因。时间戳比待确认 submission 更旧等情况也会直接返回同一错误。普通导入因此停止，手动同步也停止。

### 3. 冲突没有进入可完成的恢复状态

`SpaceData.update` 虽然返回了名字为 `cloudMembershipNeedsReview` 的原因，却只调用 `recordSyncFailure`，不设置冲突 block。上传路径也直接返回错误。

[SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的 `updateSyncState` 只有在 `isBlocked` 等条件成立时才打开配置恢复界面。否则仍提供普通 `SYNC` 重试。结果是状态不改变时反复进入同一个 GET → -2002 分支。

这部分已通过提取当前生产方法的隔离运行确认，不仅是源码推断。

### 4. 现有“从云端恢复”入口也不能直接作为修复

`reloadConfigurationFromCloud` 调用 [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 的 `restoreConfiguration(authoritativeGET: true)`。

当前 `authoritativeGET` 只影响缺失服务器 Key 的修复分支，并不表示“用户确认以云端快照取代本地”。对于 active 空间，`activateImport` 不会清除旧 submission、删除意图或基线冲突，随后仍进入普通 `update`，再次被保护。

此外，`preserved(...)` 实际编码为 `status=.skipped`。恢复 UI 用 `status != .rejected && !isBlocked` 判断成功，存在未应用云端数据却清除错误、显示成功的路径。这个关联问题必须和冲突入口一起修复。

注意：Site 普通进入与 Space 普通 GET 也使用 `authoritativeGET: true`。不能把这个现有参数直接改成无条件强制覆盖，否则正常浏览也可能覆盖本地修改。

### 5. 单纯放行上传还会带出旧固件信息

[ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 将本地节点 `firmwareID`、`vid`、`compositionHash` 等随空间快照导出。回执的逻辑配置比较刻意排除节点缓存，`resumeUpload` 的 GET 也不会把固件字段合并进本地节点。

因此，只有固件差异时，配置比较可以通过，但本地仍保留旧固件值；随后上传将携带旧值。这是源代码可确认的请求内容风险。服务器最终是否覆盖、如何处理并发提交，需要服务端实现或请求回放证据，本次未验证。

## 隔离复现与验证边界（分析阶段）

分析工具位于 `/tmp/cannot-sync-m4-analysis/`，不属于业务代码变更。

- `main.swift` / `analyze`：只读实际 JSON 与 Mesh SQLite，直接运行生产配置及实例策略。确认远端数据有效、两端实例差异，以及固件变化不影响配置比较。
- `replay.py`：基于现有 `scripts/check_space_recovery_receipts.py` 提取未修改的生产恢复方法，构造明确的基线与本地未上传新增设备。网络和持久化边界使用现有 fixture。

| 场景 | resumeUpload 结果 | GET / POST | blocked / review |
| --- | --- | --- | --- |
| 远端只改固件，本地有新增设备 | success | 1 / 0 | false / false |
| 远端同 UUID 重新配网，本地有新增设备 | -2002 | 1 / 0 | false / false |
| 远端新增设备，本地有新增设备 | -2002 | 1 / 0 | false / false |
| 远端版本旧于待确认 submission | -2002 | 1 / 0 | false / false |

说明：测试止于 `resumeUpload`，第一行的 POST=0 不代表外层不会继续上传；其他行失败会让外层提前结束。重新配网场景继续调用生产导入前缀，得到 `preserved("cloudMembershipNeedsReview")`，节点未变，blocked 仍为 false。

复现使用可控基线，不是把当前数据库冒充当时的已确认基线。未运行 App 构建、真实网络上传、BLE 或真机体验验收。

## 建议修复方案（已确认并实施）

建议一次完成下列三个关联部分，复用现有恢复存储、checkpoint、导入事务和上传回执机制，不改固件协议，不直接修改现场数据库。

### A. 明确区分可重试、可协调和需要审阅的结果

在 `SpaceConfigurationSafety` 现有协调边界增加明确结果，避免一个 Bool 同时表示远端暂未追上、身份变化、配置冲突及持久化失败。

- 已确认实例的远端删除且其余配置满足现有约束：保持现有安全清理路径。
- 远端新增、重新配网或与本地并发修改产生真实冲突：保存最小诊断与待审阅原因，进入已有恢复 UI，停止无意义自动重试。
- 旧读回/暂不可确认的 submission：保留原回执，允许有限重试；不能直接当成成功，也不能仅因读到旧数据就强制覆盖。
- 网络失败、无权限、格式错误、持久化失败分别保留原语义，不误归为用户配置冲突。

DEBUG 诊断仅记录阶段、双方代次、submission phase、实例差异计数/地址或脱敏标识、具体拒绝原因，不记录 Key。

### B. 让明确选择的恢复真正完成，并能在重启后续接

为“用户明确选择的恢复”传递独立意图，普通 `authoritativeGET` 保持普通读取含义。

1. 展示两端差异，保存当前本地与 GET 快照，绑定账号、空间、网络身份及双方版本。
2. 审阅期间数据变化则重新准备，不能应用过期选择。
3. 对选择的恢复方案持久化独立恢复代次；只在该恢复范围内处理被取代的旧回执和冲突标记，不删除未经审阅的本地删除意图。
4. 先记录可重放导入候选，再复用双库事务、导入、完整性校验及基线更新。避免刚设置的保护状态阻断自身后续步骤。
5. 只有实际应用且两库、恢复状态均完成后才显示恢复成功；`skipped/preserved` 明确保持未完成。取消、失败、重启均不冒充成功。

此空间建议的恢复候选：保留本地独有 L268 的证据和记录；L90 作为新旧两个实例审阅，确认采用云端实例后同时更新地址、Key、元素与关联引用；L271 是否是本地有意删除，要读取删除日志或由用户确认，不能自动补回。不能用简单的全量云端覆盖丢掉 L268，也不能用全量本地覆盖回退 L90 与固件信息。

对于已存在可核验删除日志的记录继续按原语义处理；没有证据的成员冲突进入审阅。本次不承诺自动合并所有业务字段。

### C. 将固件观察值与空间配置修改分别协调

仅对空间/网络身份验证通过、且 `UUID + unicastAddress + Device Key 指纹` 完全一致的实例合并固件观察值。L90 必须先按 B 解决实例变化。

建议在现有 `SpaceRecoveryState` 中增加可选的、上次确认云端固件信息基线，记录确切实例及必要关联字段；在成功导入/读回时推进。用基线 B、本地 L、远端 R 比较：

- L=B、R 变化：采用远端观察值。
- R=B、L 变化：保留本地新观察值，允许随后上传。
- L=R：保持一致值。
- 两端都偏离基线且值不同：保留冲突，通过版本读取或审阅解决，不按版本号取最大值；固件可能合法降级或跨构建版本。

固件信息与必要的 VID/Composition 关联值要一起核对；不得为了刷新显示批量替换元素拓扑。应用云端观察值时保留其他本地未上传修改，不把一次云端读取伪装为新的用户配置修改，同时更新数据库、当前内存节点及页面展示，保证下一次导出不再携带旧缓存。

旧安装没有可靠基线时，只从能证明代次的完整存档恢复；证据不足走审阅或设备读取，不拿当前本地空间时间戳推断固件新旧。现场这份数据应先完成 B 的恢复选择，不能直接套三方比较。

该方案首先在 App 现有恢复层扩展，不预设需要 SDK 新 API；实施前核对固件相关字段在普通导入、直接读取及 BLE/Mesh DFU 成功路径的更新边界。若确认现有 SDK 不提供必要信息，再单独说明依赖变更。

## 影响范围与验证计划

共享使用方包括 Space 自动刷新/重试、Site 批量同步及进入空间、云端恢复、离开 Editor 前上传。应统一修复共享入口，避免仅修改 Space 提示。

重点回归：

1. 复现上述 4 类场景，断言请求序列、准确错误分类、是否进入恢复、dirty 状态及节点保存结果。
2. 本地新增 L268 + 云端 L90 新实例 + 固件更新；无证据时不丢本地节点、不复活明确删除节点、不确认旧 submission 为新版本。
3. 同一实例仅固件变化、本地同时改组/新增设备，验证安全合并和随后导出；补本地更新、远端更新、双端冲突、合法降级、无基线及空字段。
4. 已确认远端删除、未知上传结果、旧读回、合法空配置/旧回执、无权限、Key 不匹配仍受正确保护。
5. 恢复取消、两库写失败、重启续接、GET 后本地修改、切账号/离开空间，以及 `skipped/preserved` 不显示恢复成功。
6. 扩展现有回执、导入准备与数据库安全测试；如涉及字段投影，补充行为测试，不靠源码字符串断言替代。
7. Swift 实施完成后构建一次 `SunSmartLocal.xcworkspace` 的 SunSmart Debug generic iOS，使用本工作树稳定 DerivedData。共享逻辑影响五品牌；如不改变 target、资源归属或 SDK 公共 API，可选 SunSmart 作代表。若新增文案，补 English 与简体中文，并核对所有品牌归属。
8. 人工验收：Editor 更新固件/设备实例 → Owner 带本地修改进入 → 有明确同步或审阅结果 → 完成恢复后固件、成员与持久化一致 → 再进入与重启不重复报同一冲突。按项目规则由用户进行真实设备验收。

跨手机同时写入时，现有快照 API 缺少已核实的服务端条件写入契约。客户端修复应避免覆盖已经观察到的更新；要保证 GET 与 POST 间新的并发提交也绝不丢失，仍需另行核实服务端 revision/CAS 能力，不在本次未经核实地宣称已经解决。

## 现场尚缺的证据

若要把本次失败精确对应到某个 guard，需要该 Owner 同一时段、同一账号的 `Library/Application Support/SpaceConfigurationRecovery/` 对应空间状态与相关目录，重点为 submission/baseline、`device-deletions.json`、pending import，以及相关 UserDefaults 标记或 DEBUG 分支日志。它们不在两份 SQLite 中。

这些资料用于确认现场回执与 L271 的删除意图，不影响已确认的代码缺陷。当前结论不推定 L268 的创建操作者，不把从 Editor 抓取的 role 当成 Owner 收到的角色，也不将本地隔离复现当作真机及服务端验收。


## 实施结果（2026-09-30）

未修改 SDK、接口协议或原始现场文件。变更集中在现有 App 共享恢复、导入、上传协调层和 Space 恢复 UI；英文及简体中文同步补齐。未提交或推送 Git。

### A：冲突可区分、可进入恢复

`reconcileCloudMembership` 返回明确的 ready / retryLater / invalidRemote / persistenceFailed / review。新增实例、替换实例、配置或 Scheduler 冲突保存审阅原因；普通同步结束后可进入恢复界面，后台不继续无意义地自动重试。旧读回仍保留回执并允许重试，既有远端删除、单个服务器 Key 缺失修复及 verified 回执本地收尾路径均保留。

### B：带审阅快照的恢复

Space 冲突恢复先展示本地独有、实例替换及无删除证据的云端独有设备。用户明确采用云端配置，保留本地独有节点；对无证据的云端独有设备选择保留或排除，有确切实例删除证据的记录保持删除。这个选择也会采用其他云端业务设置，预览文案明确告知，并保留两侧备份。

写入前重新读取云端，并比对两侧完整相关配置、固件、时间戳及删除日志。保存本地/云端 JSON、旧恢复状态和数据库 checkpoint 后，持久化独立恢复代次及候选，旧回调失效。首次数据库写入前再检查快照；有变化则恢复原回执/基线并要求重新审阅。开始写入后保留候选，失败、退出或重启可续接；权限降级会归档旧恢复并停止回放。

继续复用现有 App 数据库事务、Mesh 保存、持久化读回和 checkpoint。两份数据库不是一个跨库原子事务；中断一致性依赖候选重放和持久化保护。恢复完成前检查固件读回，不以 skipped/preserved 显示成功。恢复后的合并版本仍为待上传状态，经 POST 后 GET 核对才清除错误及回执。旧回执另存为 `before-reviewed-state.json`，不会把它误记成已确认的新版本。

排除的云端节点同时清理场景、日程、日光传感器、开关代理/凭据及消防控制器绑定；Proximity/Trigger Zone 引用复用现有规范化机制。地址冲突仍拒绝恢复，不自动改地址或放宽 Device Key 校验。

### C：固件观察值按实例协调

增加可选固件基线和提交快照，兼容旧恢复状态。比较确切实例的 firmwareID、VID、Composition Hash；远端单边变化合并到数据库和当前内存节点，本地单边变化保留，双边变化或缺少可靠基线的不同值进入审阅，支持合法降级。缺字段视为未知，不清除已知本地值。固件 ID 接受现有 App 导入支持的 6/8 字节格式，不新增固件协议范围。

普通 Space/Site 导入和上传前 GET 共用协调。远端观察更新本身不制造本地配置修改；如果设备读取留下未上传的本地观察值，则保留上传意图。普通导入保护已存在的未上传本地设备/配置，即使云端空间时间戳更大也不整份覆盖；明确审阅的候选及权限要求的重新导入按各自恢复流程处理。上传读回同时验证提交的固件观察，避免业务配置相等就提前确认旧固件值。

SDK 复用原有 Node 编码、固件属性、版本设置及保存 API；没有新 SDK revision 或发布依赖。

## 实施验证

以下均针对本次工作树；后续改变代码或依赖时不能直接视为仍然通过。

| 验证 | 结果及范围 |
| --- | --- |
| `scripts/check_space_recovery_receipts.py` | 通过。运行提取的生产协调/恢复/导入准备逻辑：一 GET 无 POST 的冲突分类，普通刷新保护 dirty 新增设备，三方固件与降级/未知字段/缺基线，固件写失败，审阅取消不变更、云端/本地过期选择、首次写入前过期、中断候选重放、权限丢失、已知删除和最终上传确认；既有回执/旧数据/空配置/角色用例通过。网络与 Mesh 导入正文是隔离边界。 |
| `SpaceConfigurationIntegrityPolicyTests.swift` | 通过。配置、Scheduler/场景目标等原有用例及恢复候选引用清理、未知固件保留、地址碰撞拒绝。 |
| `scripts/check_space_protection_snapshot.py` | 通过。真实保护文件与损坏/权限/身份/并发失效；新增“仅有持久化恢复候选、尚无 pending-import 文件”也必须保护。 |
| `scripts/check_space_membership_lifecycle.py` | 通过。成员身份、恢复、退出及账号隔离等生产逻辑回归。 |
| `scripts/check_space_key_integrity.py` | 通过。网络身份、两 Space、错误 Key、保存失败及隔离。 |
| `scripts/check_configuration_database_safety.sh` | 通过。临时 SQLite WAL checkpoint、App 事务回滚及保存失败；不能等同于真机全量 Mesh 导入故障注入。 |
| `scripts/check_device_permanent_deletion_cleanup.sh` | 通过。既有删除持久状态及地址清理策略。 |
| 本地化与差异 | English/简体中文 strings 的 plutil 检查通过；五品牌引用相同资源及共享源码；`git diff --check` 通过。 |
| SunSmart generic iOS 构建 | 最终生产代码在 `SunSmartLocal.xcworkspace`、SunSmart、Debug、iphoneos、generic iOS、`CODE_SIGNING_ALLOWED=NO` 下 BUILD SUCCEEDED。SDK realpath 与输入记录相同且未修改。未运行 Simulator 或真机。 |

现场投影验证：`/tmp/cannot-sync-m4-recovery/main.swift` 以只读 Mesh SQLite 的真实节点 UUID、地址、Device Key、元素及固件作为输入，云端业务字段作骨架，直接执行生产候选策略。两种选择都保留 L268，L90 使用云端 `15ED` 新实例和 `2.1.6`；保留 L271 为 274 台，排除为 273 台。此验证不是完整 App 导出、双库全量恢复或服务器回放。原始 JSON/SQLite 未写入。

新增回归入口和夹具在现有 `Tests/Group/` 与脚本内，未新增 Xcode 测试工程或业务依赖。共享逻辑无品牌条件分支变化，代表 target 为 SunSmart；其余品牌没有重复构建。

## 最短人工验收

1. 使用本工作树构建的 App，在 Owner 进入该 Space 并同步：应进入明确的配置恢复，不能继续反复只发 GET 并报同一个未知同步错误。
2. 从云端恢复：预览应保留 L268、提示采用 L90 新实例。若没有本机删除证据，确认 L271 的保留/排除选择；先取消一次，成员和固件不应因取消而被替换。
3. 完成恢复并联网同步：检查 L268 保留、L90 实例与云端一致、相关 PID 2802 显示 `2.1.6`；确认后续上传及 GET 核对完成，而不是只看到 HTTP 成功或导入完成。
4. 退出重进及重启后再检查节点数、固件和同步状态；可另在恢复中断后重启，确认候选续接。再次进行 Editor 固件变更、Owner 同时保留本地配置修改，确认已知单边固件变化可以合并。

必要 DEBUG 观察点：`SpaceConfigurationSync` 的 stage/error/reason、`SpaceFirmwareObservation` 的更新/冲突数量与远端代次、`SpaceConfigurationReadback` 的读回结果。日志不新增完整密钥内容。真机 BLE、真实 Mesh 持久化、服务器并发窗口和 UI 实际体验仍待上述验收；本次未操作真实服务器或设备。
