# Space 无法保存提示：原因与默认配置修复

日期：2026-10-22。分支：`feat/HDB-261020`。初始分析 HEAD 为 `f93859f7`；实施期间外部提交推进到 `b72e627e`，此前已有的 HDB v2 格式改动已纳入该基线。本任务没有执行提交或回退。

首轮结论：Space 1 的直接原因是 HDB v2 数据中残留旧 Zone 字段，并非已证实的手机存储故障。两份样本的 63 个 Zone 均使用数字 `groupAddress`；当前代码要求十六进制字符串 `groupId`。本地解码失败后，进入 Space 的恢复流程在导入前普通保存处被拦截，产生用户看到的提示。

另有独立问题：服务器 `nodes=[]`，但 `deviceCount=2` 且 HDB 引用了两个设备；本地 Mesh 保存了这两个设备。即使修正 Zone 字段，该服务器副本仍不能通过完整引用校验。

用户已确认实施，并明确：**云端 Nodes 变化时以服务器为准，包含空数组，不保留仅本地存在的设备来阻止同步。** 当前实现从最新 GET 建立恢复副本，修复 HDB 格式/属性并移除失去云端 Node 的 HDB 设备引用。本样本修复后的目标是 **63 个 Zone、0 个设备**。下文前 3 节保留原始样本分析，后续节描述实际实施。


续修结论（Space 2）：18:06 导出的本地 HDB 与新服务器样本一致，均为完整 schema v1。首轮实现只支持 v2 混合字段，默认修复在版本检查处直接失败；不是新发现的手机存储故障。已将已知 v1 和损坏 v2 收敛到同一恢复流程，复用现有设备配置工厂，Space 2 的目标为 **63 Zone、1 个云端设备**。普通加载和上传回读继续严格要求 v2。详见第 8 节。

重进续修结论：原恢复流程已覆盖数据库并读回校验，但列表保留了修复前的 Space 对象，且重进时会先对尚未更新的旧云端 HDB 做冲突检查。这两条路径都可能重新阻断已完成的修复。现已同步列表缓存，并在普通冲突检查之前识别持久化的恢复记录，保留已落库配置。云端 Nodes 真实变化仍以服务器为准；详见第 9 节。

## 1. 样本证据

输入：

- App：`/Users/maginawin/Desktop/doing/wwd/Space_Space 1_20261022_171030_398+0800.json`
- Server：`/Users/maginawin/Desktop/doing/wwd/hdb server spaceprops.txt`

App 文件为诊断导出，`_debugInspection.uploadable=false`，不能把顶层只有名称和 UUID 的 `spaces[0]` 当作完整配置。实际数据库数据在 `_debugInspection.spaces[0].rawLocal`。

| 核对项 | 结果 |
| --- | --- |
| 本地 HDB | `rawLocal.app.spaces[0].hdb.json` |
| 服务器 HDB | `data.spaceData.hdb` |
| 两端 HDB | 结构和值相同，schemaVersion 均为 2 |
| Zone 目录 | 63 个，zoneId 1～63；旧 `groupAddress` 数字 49153～49215，即 C001～C03F；缺少 `groupId` |
| HDB 设备 | 2 个，Primary Address 000E、0011；设备级地址、Model ID、MAC 等已采用新格式 |
| 本地 Mesh | 2 个设备、65 个 Group；63 个 Zone Group，2 个 Sensor Group C040/C041 |
| 服务器 Mesh | `nodes=[]`，65 个 Group，`deviceCount=2`；HDB 设备引用无对应 Node |
| Space、网络身份 | 两端 Space UUID、NetKey、AppKey 一致；仅记录比较结果，不复制密钥 |
| 时间 | 本地版本、最后确认版本、服务端版本均为 1792659103，即 2026-10-22 16:51:43 +08:00 |
| 阻断状态 | `blockedReason=invalidStoredHDB`；`comparisonPayloadAvailable=false` |
| 最近同步失败 | `cleanupPreparation`、`error=-2005`，记录于 17:08:24；这是 App 配置审查错误，不是 HTTP 错误码 |
| 恢复状态 | membership=joined、network matches=true、phase=active、authority=writable、initialized=true |
| 待处理记录 | pendingImport/upload/deletionCleanup 均为 false；有完整历史导出快照，但本样本未包含该快照内容 |

本样本中的 `triggerZones=null`、设备 `lightingZones=[]`、dimIntensity=0/5、holdTime=10/30 都不是本次错误。设备无 Zone 成员是合法状态，不能为了修复而给设备自动分配 Zone。

这与 2026-10-21 的缺少 `broadcast` 问题不同；本次是 **v2 根版本与旧 Zone 字段混用**。样本未提供安装包 revision、上传请求原文或完整进入日志，无法确定混合格式由哪个 App 构建或外部写入产生，也不能据此认定服务器篡改了字段。

## 2. 为什么显示“无法保存在本机”

当前源码链路：

1. `HDBLightingZone.init(from:)` 明确拒绝出现 `groupAddress`，要求 `groupId` 为 4 位十六进制字符串；本样本在这里抛出 `invalidData`。
2. `SpaceData.load` 的两个加载入口捕获错误，设置 `hdbLoadFailed=true`，记录 `invalidStoredHDB`；原始 SQLite BLOB 保留。
3. Site 点击 Space，通过 `loadSpaceReqeust` 获取 `/sitespace/get/spaceprops`，再调用 `restoreConfiguration`。
4. `restoreConfiguration` 复制本地 Space，准备身份/恢复状态后，先执行 `candidate.save()`，随后才会调用云端业务配置 `update`。
5. `SpaceData.save()` 首先拒绝 `hdbLoadFailed`；即使只把内存标记清掉，普通保存也会再次加载旧行，因 `storedSpace.hdbLoadFailed` 被拒绝。
6. 该失败被返回为 `configurationPersistenceFailed`；恢复页将其映射到用户提供的整句提示。

因此，当前样本不断点击 Retry Recovery 不能改变损坏的本地输入。即使云端提供完整合法配置，当前“先普通保存损坏候选，再导入”的顺序也可能阻止它进入真正的恢复事务。这是同类恢复必须处理的关联问题。

生产模型隔离复现：

| 操作 | 结果 |
| --- | --- |
| 原样解码本地 HDB | `invalidData` |
| 原样解码服务器 HDB | `invalidData` |
| 仅在内存中将 63 个旧字段替换为 `groupId`，保留地址数值与其他内容 | 解码、HDB 校验、编码再解码均通过 |
| 修正后 HDB + 本地实际 Nodes/Groups 引用投影 | 引用校验通过，保留 63 Zone、2 Device |
| 修正后 HDB + 原服务器 Nodes/Groups | 引用校验失败，因为找不到两个设备的 Node |
| 保留本地拓扑，将两个设备灯光设置替换为 App defaults | HDB/引用校验通过；这是候选可行性验证，未写入真实数据 |

以上引用验证使用生产 `validateReferences`；本地 Node/Group 投影取自诊断导出的 UUID、地址、Composition 和 isVirtual。没有执行完整 SDK Node 导入、完整 Space 导出或手机数据库恢复。

## 3. 其他哪些原因会显示同一句提示

恢复页把三个原因合并成这句文案：`configurationPersistenceFailed`、`configurationStagingFailed`、`configurationReferenceStagingFailed`。

| 条件 | 触发环节 | 默认属性能否解决 |
| --- | --- | --- |
| 本地 HDB 旧版本、缺必填字段、错误类型、非法 MAC/地址、重复 Zone、非法成员、错误 Model/命令元数据、参数越界等 | 本地解码/validate 失败；进入时普通保存拒绝 | 仅能修复有明确依据的格式/派生字段和有已定义默认值的属性；身份与无法确定的拓扑不能猜测 |
| 本地 `triggerZones` BLOB 解码失败 | `triggerZonesLoadFailed` 直接阻止 `save()` | 不能只清空数组；要连同 Group/设备拓扑核对。本轮默认修复不自动重置该模块 |
| 候选内存正常但数据库行 HDB 已损坏 | 普通保存重新加载旧行时拒绝 | 必须走验证后的恢复写入；仅清除内存标记无效 |
| 旧页面提交 HDB 修改，但持久化基线已被另一操作更新 | `configurationForSave` 冲突拒绝 | 应重载后重新预览，不能用默认值覆盖新修改 |
| HDB/Trigger Zone 编码失败、App 数据库未打开、SQLite 写入/锁/磁盘等故障 | `save()` 返回 false | 默认值通常无效；保留原数据并提供重试 |
| membership/recovery 文件读取、替换等抛错 | `restoreConfiguration` 的 catch | 不能把状态文件故障当作配置属性问题处理 |
| App/Mesh 检查点、pending-import 或引用清理原文暂存失败 | 两种 staging failure | 先解决存储/文件问题；备份失败不得继续替换 |
| 导入事务中 Group/Profile/Schedule/Space 等保存失败，或 HDB/Timed/Proximity/Mesh 读回不一致 | 事务最终统一返回 persistence failure | 需区分真实写入故障与数据/拓扑不一致；不能全局改成忽略错误 |

边界：只有云端 HDB 不合法、本地正常时，通常到 `invalidHDBPayload` 后显示通用恢复提示，而非必然显示本句。网络不可用、身份冲突、恢复收尾失败也有各自文案。本样本缺 Node 是潜在的下一处阻断，尚不能把它说成手机上本次最先发生的报错。

## 4. 实际修复行为

恢复页新增 `Fix with default configuration`（简体中文“使用默认配置修复”），Space 内已有配置恢复弹窗也使用同一入口。

确认文案明确：使用最新云端配置；云端空设备列表有效；仅保存在手机上的设备会从 Space 移除；保留备份；替换的灯光参数在后续设备同步中应用。取消不会执行恢复。

修复规则：

- 普通加载、导入与上传回读继续严格校验 v2。显式修复识别已知 v1 及 v2 + 旧 `groupAddress` 形态，统一重建为当前 `groupId` 等 v2 字段。
- 仅使用当前 GET 的 Nodes、Groups、HDB。云端不存在的 HDB 设备条目移除，不拼回本地 Node；同地址但 UUID 已换的设备同样按云端处理。
- Zone 必须对应云端实际非虚拟 Group；已被云端移除的 Group 不再作为 HDB Zone 目标。名称缺失时使用已有国际化默认名，不能重新分配或猜测地址。
- 根据云端 Node 的地址、MAC、Composition 重建设备派生信息，调用日常配置使用的 `HDBConfigurationStore.deviceConfiguration(node:)`，包含 SDK Model Extend 关系决定的广播目标；不另写一套 Model 分配规则。
- 保留合法的灯光值、合法空成员、可选 null/缺字段。损坏的灯光值才取对应默认值；非法状态改为 pending；编码时按已校验 Model 元数据重新生成命令字段。普通解码仍拒绝错误数据。
- 缺失或错误类型的 `nodes` 不等于合法空数组。未知 HDB schema、无法确定的身份/Model/地址等仍拒绝自动修复；不编造网络密钥和设备。
- 本机坏 HDB/Trigger Zone 行已有明确成员身份时，不再要求先普通保存该坏行才能进入完整导入。新成员仍先建立 canonical 身份，禁止提前上传。
- 显式选定的云端恢复副本跳过本地 Profile/成员冲突协调。导入后检查数据库中的设备 UUID 集合与选定云端完全一致，包括空集合，防止删除未落盘却报告成功。

App 当前默认值：

| 属性 | 默认值 |
| --- | --- |
| Lighting Control | Auto |
| Failsafe Delay | 5 min，仅 App 元数据 |
| Dim / Bright Intensity | 20% / 80% |
| Ramp Up / Ramp Down | 1 s / 2 s |
| Hold Time | 30 s |
| Install Date | 无默认日期 |

此次采用“只修复异常项”，没有对仍然有效的远端设备执行全部参数重置。本例两个设备因云端 Nodes 为空而被移除，已无需恢复它们的灯光参数。

## 5. 保存、重试与云端收敛

复用现有检查点、reviewed-cloud-import、pending-import、导入事务和上传回读机制：

1. 获取最新 Space GET，重新核对账号/区域、权限、密码、成员状态和网络密钥身份。仅有效 owner/editor 可发起默认修复；进行中的导入/删除清理使用原重试路径。
2. 在内存中修复所选云端副本，完成 HDB 引用、Group/Node/Schedule 解码和配置校验；保存 App/Mesh SQLite 检查点后持久记录云端选择。备份失败时不替换业务数据。备份保存在现有受保护恢复目录，不复制密钥到日志或文档。
3. 给本次恢复使用新的 generation，过期本地上传回调不能完成旧提交；正常重试和重启从持久选定副本继续导入。存储故障仍返回错误，不忽略保存失败。
4. 导入读回成功后再结束数据阻断。若修复改变了云端配置，生成高于已知本地/远端版本的待上传版本；保留源 GET 的业务内容，用于批准首次修复上传。
5. 首次 POST 前仅当 GET 仍是已选定的原始业务内容时允许该替换。GET 已改变则重新按最新服务器副本修复/导入。未发送与已接受待回读两种阶段的云端 Nodes 变化都以服务器为准，不复活本地旧设备。
6. POST 后读取**未作修复转换**的 GET 验证真实结果。旧字段、丢字段或内容不匹配不能被自动规范化成“上传成功”。只有完整回读通过才清除待提交与默认恢复源记录。

App SQLite 与 Mesh SQLite 是不同连接，已有 App savepoint 不等于跨库原子事务；仍依靠现有双库检查点、pending import 和最终读回处理失败与恢复。

## 6. 范围与外部边界

生产改动集中在已有 HDB 策略、Space 身份/导入/安全恢复代码、两个 UI 入口及 en/zh-Hans 文案。未改正式 project/依赖声明，未添加生产文件或 SDK API。

五品牌共用这些源码和同一个 Localizable.strings 资源组，已核对资源归属；没有新增品牌条件路径，采用 SunSmart 代表构建。

本机 SDK 仍映射到 `nordic-sig-mesh-sdk-worktrees/one-dev`，revision `8c5af55`。该 SDK 已有其他任务的 Configuration Readback 未提交改动，本任务未编辑或回退它们。

本轮没有修改服务器、固件或其运行配置。服务器 Nodes 为空按用户确认视作权威空列表；不以调查其历史来源为 App 修复前置条件。服务器仍须完整保存并回传修复上传后的 v2 字段，真实收敛需要在线联调确认。

## 7. 验证结果

已通过：

- `check_hdb_import_recovery.py`：生产保存保护、选定快照、严格普通导入；新增混合格式、仅坏值默认化、合法空/可选字段、幂等、云端清空/同地址替换设备等回归。直接读取用户提供的服务器文件后，输出 63 Zone、0 HDB Device，Nodes 原样保持为空；未写回原文件。
- `check_space_membership_lifecycle.py`：坏本地 HDB/Trigger Zone 可以到达导入；新成员身份保存失败、非权威请求、准备失败、旧响应和退出状态仍受保护。
- `check_space_recovery_receipts.py`：生产恢复文件/状态、收尾失败重试、原始坏 GET 不确认 POST、精确回读结束、云端设备在未上传/已接受阶段变化，以及现有权限、Timed、成员、删除和 Profile 回归。
- `check_hdb_persistence.py`：真实 SQLite 精简 spaces 表的 HDB BLOB 重开、状态保存、回滚、旧格式拒绝；新增混合 v2 修复失败回滚保留原文、成功后关闭重开仍为云端空设备的覆盖。边界不包含整个手机数据库与 SDK 导入。
- `check_proximity_scoped_import.py`：共享拓扑导入/设备删除/范围隔离回归。
- 两种语言 strings 语法及五品牌资源归属核对。

`SunSmartLocal.xcworkspace` / `SunSmart` / Debug / iphoneos / generic iOS / `CODE_SIGNING_ALLOWED=NO` 构建通过，最终增量编译退出 0 且输出 `BUILD SUCCEEDED`。使用独立且可复用的 `DerivedData/SunSmart-feat-HDB-261020-default-recovery`，未清理其他缓存或操作真机。首次依赖编译有既有 CryptoSwift、SDK 与第三方告警；没有为其调整业务代码。`git diff --check` 通过。

隔离回归中的完整 Mesh 导入、HTTP、数据库入口仍有明确替身，不能作为真机或真实云端验收。实际手机 UI、双库恢复、BLE 与在线服务器往返尚未运行。

人工验收：安装构建 → 进入原 Space → 点击修复并确认 → 按本次服务器样本显示 63 Zone、0 设备 → 退出重进、重启仍一致 → 在线上传回读后同步完成。无须删除或重新创建 Space。本任务不自动安装/运行真机。


## 8. Space 2 默认修复失败的续修

新输入：

- App：`/Users/maginawin/Desktop/doing/wwd/Space_Space 2_20261022_180631_389+0800.json`
- Server：`/Users/maginawin/Desktop/doing/wwd/server data.txt`

两端 HDB 相同：schemaVersion=1、63 Zone（C040～C07E）、1 Device（000B）、Sensor Group=C07F。设备 MAC 为 null，nodeAddress/sensorGroupId 为整数，没有当前要求的三组 Model 数组和命令描述；云端 Node 含有效 MAC 和三个 Elements。诊断为 `invalidStoredHDB`，joined/active/writable，pending import/upload/deletion 均为 false。

首轮 `repairingDefaults` 的 `schemaVersion == 2` 条件即可稳定复现失败；只把版本改成 2 仍会在地址、MAC、Model 字段处继续失败。新增修复不修改普通解码器：

1. v1/v2 共用 `repairedDevice`、地址转换、成员转换、灯光属性默认化和最终引用校验。已从旧源码确认 v1 成员为 `{zoneId}` 对象数组，转换时保留有效成员，去重并遵守最多 8 个 Zone；不会把旧对象数组误作空配置。
2. 设备 UUID 必须对应最新云端 Node。使用云端地址和有效 MAC；云端缺 MAC 时只允许使用有效的同一 HDB 记录 MAC，两处都无法确定则拒绝。设备已从云端移除时，移除 HDB 引用。
3. 使用正常云端 Node 解码器和已有设备配置工厂重建 Zone/Sensor/Broadcast Models，再统一生成命令描述。此样本为 5 个 Zone Models、3 个 Sensor Models、3 个 Broadcast Models；LC 位于 000D，独立 CTL Element 000C 不被错误加入广播恢复。
4. v1 根 `broadcast` 和 Zone 内旧灯光参数不再写入 v2；设备级合法灯光值作为当前配置保留，不将 Zone 参数套给其他设备。缺少整份旧设备灯光配置时使用 App defaults。重建的订阅和需要下发的灯光字段标记 pending，不能将格式修复当成设备执行完成。
5. 已被云端删除的 Sensor Group 引用清空，后续仍由现有传感器组创建/同步流程处理。v2 缺失/损坏 MAC 或 Model 数组也复用同一修复路径。
6. 默认恢复失败复用 `recordSyncFailure`，DEBUG 导出包含 `defaultRecovery.authorityAndIdentity/hdb/timedAndReferences/decode/checkpoint/staging` 阶段，避免所有失败只剩通用提示；不记录配置原文或密钥。

本轮自动验证：

- `check_hdb_import_recovery.py` 对新服务器原文件直接运行通过：63 Zone、1 Device，Nodes 与源文件一致；覆盖 v1、v2 混合、损坏派生字段、旧对象成员、地址/MAC 变化、空 Nodes 和幂等。上次服务器原文件目前已不存在，云端清空场景通过保留的合成回归验证。
- `check_space_recovery_receipts.py` 使用无凭据复现夹具和新服务器的 Nodes/Groups/spaceData，覆盖生产暂存、导入准备、恢复收尾与严格上传回读；HTTP、完整 Mesh 导入和账户/密钥存储仍为明确测试边界。
- `check_hdb_persistence.py` 在真实 SQLite 简化表中验证 v1 修复失败回滚保留原 BLOB，成功关闭重开保留 63 Zone/1 Device 及派生字段。
- `check_cloud_node_import.py --snapshot` 对新服务器的 Node 可选字段解码及导入暂存入口通过；补齐旧测试替身缺失的 `timedReferencesChanged=false`，未因此更改生产 Timed 行为。
- `check_hdb_configuration.py` 通过，普通 v1 拒绝和当前 v2 编码/命令描述契约保持不变。
- 本轮 SunSmartLocal / SunSmart / Debug / generic iOS 编译退出 0，`BUILD SUCCEEDED`。SDK 来源与第 6 节相同，本轮未改 SDK、品牌资源或依赖。

测试共享 `hdb_recovery_test_source.py`：三个回归入口复用同一 App 工厂和本机 SDK `relatedModels/extendsDirectly` 实现。测试仅提供 Node/Element/Model 对象边界，避免各套测试重复实现广播目标规则。私人样本只读入内存，不复制凭据到仓库。

真机 UI、真实双库完整导入、BLE 下发和在线服务器往返尚未执行。最短验收：安装本次构建 → 进入 Space 2 → Fix with default configuration → 显示 63 Zone、1 Device → 重进/重启保持一致 → 完成云端回读；设备同步 pending 需按正常同步流程下发。

## 9. 修复成功后退出重进再次报错

用户进一步明确：修复的数据直接覆盖数据库，后续不应再次因同一份坏配置提示恢复。

源码及行为回归确认的两个遗漏：

1. 默认恢复从数据库读取新的 `latest` 实例，成功回调只刷新列表单元格；`site.spaces`、All、Favourites 中仍可能持有 `hdbLoadFailed=true` 的旧实例。Site 返回时刻意保留未发生成员变更的对象，下一次点击使用旧副本，在导入前普通保存处再次产生 `configurationPersistenceFailed`。
2. 修复导入已执行 `save(importingConfiguration: true)`、普通保存及数据库读回。修复源和待上传版本也已持久化，但 `update` 会先协调旧云端 Profile/成员，再检查待上传本地数据。云端仍为修复前的 v1 时，普通 HDB 校验会先失败。新增真实生产逻辑前缀回归在修正前稳定失败，修正后通过。

必要修改：

- `reloadSpaceData` 复用 `applyConfigurationState`，同步同一 Site/Space 的全部列表实例，包括 HDB、持久化基线、失败标志及版本，避免三个列表各自维护复制逻辑；其他 Site 不受影响。
- `preserveDefaultConfiguration` 集中处理已落库恢复的重进判断，在远端权限元数据生效后、普通冲突协调前调用。要求恢复源与当前 GET 的业务字段完全相同、数据库中存在不低于修复版本的有效记录、当前权限可写且没有进行中的导入/删除/引用清理。
- 条件满足时保持数据库中的修复配置及待上传记录，只清除与该旧副本比较产生的冲突。不会把旧 GET 当作上传确认；真正保存失败、数据库解码失败及无关阻断仍报告错误。
- GET 变化时继续走已有最新云端恢复路径；未上传及已接受待回读阶段的 Nodes 变化仍以服务器为准。没有增加另一套数据库写入流程，继续复用现有导入覆盖、读回和故障恢复机制。

本轮验证：

- `check_hdb_import_recovery.py` 对新服务器样本通过；新增执行生产列表刷新逻辑，验证 Site/All/Favourites 的旧错误标记全部更新，重进普通保存成功，其他 Site 不受影响。
- `check_space_recovery_receipts.py` 对合成 v1 和新服务器样本通过；覆盖修复后立即重进、从持久化恢复记录重建实例、清除旧冲突、上传已接受但尚未确认时重进，以及保存失败、坏数据库状态和访客权限。
- `check_hdb_persistence.py` 通过；真实 SQLite 覆盖后关闭重开保留 v2 HDB、设备、Model 与默认值，失败回滚保留原始数据。
- 本轮 `SunSmartLocal` / `SunSmart` / Debug / iphoneos / generic iOS 编译退出 0，输出 `BUILD SUCCEEDED`；使用第 7 节同一 DerivedData，本轮未改 SDK、依赖或品牌资源。`git diff --check` 通过。

边界：列表与恢复状态回归执行生产函数，但账户、完整 App 数据库和 HTTP 使用测试替身；真实 SQLite 测试使用精简表。尚未运行手机 UI、完整双库导入或在线服务器往返。人工最短验收：修复一次 → 返回 Site → 从 All/Favourites 再进入 → 杀掉 App 后重启再进入；同一旧云端配置不应重复要求修复，Space 2 应保持 63 Zone/1 Device。新的云端 Nodes 变化仍应反映到 Space。
