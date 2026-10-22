# Space 无法保存提示：样本分析与默认配置修复方案

日期：2026-10-22。分析分支：`feat/HDB-261020`，HEAD：`f93859f7`，包含当前未提交的 HDB v2 格式修改。

结论：本次直接原因是 HDB v2 数据中残留旧 Zone 字段，并非已证实的手机存储故障。两份样本的 63 个 Zone 均使用数字 `groupAddress`；当前代码要求十六进制字符串 `groupId`。本地解码失败后，进入 Space 的恢复流程在导入前普通保存处被拦截，产生用户看到的提示。

另有独立问题：服务器 `nodes=[]`，但 `deviceCount=2` 且 HDB 引用了两个设备；本地 Mesh 保存了这两个设备。即使修正 Zone 字段，该服务器副本仍不能通过完整引用校验。

建议增加 `Fix with default configuration`，采用显式、可预览、有备份的局部修复。优先保留能校验的设备、Zone 和现有设置；仅对异常且有明确默认值的属性使用 App 默认值。尚未实施业务代码，也未修改样本或服务器。本稿按“只修复异常项”规划；是否需要全部重置 HDB 灯光参数待确认，实际差异另列于第 4 节。

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

## 4. 修复行为与默认值

### 4.1 推荐策略：只修复异常项

保留当前正常导入/加载的严格 v2 校验；显式点击修复才允许建立修复候选，不恢复全局旧格式自动兼容，也不将未知 schema 自动转换。

本样本执行：

1. 从本机同一持久快照读取原 HDB、两个 Node、65 个 Group 与其他 Space 配置。
2. 对明确可识别的 `schemaVersion=2 + groupAddress` 形态，验证每个整数地址与本地同一 Space 的实际非虚拟 Group 一致、Zone ID/地址唯一，然后重建为当前模型并输出 `groupId`。不是固定重新分配 C001～C03F。
3. 保留 Zone 名称、设备身份、两个 Sensor Group、合法空 Zone 成员、所有已校验的灯光值及其状态。该样本无需替换灯光默认值。
4. 对类似样本中确实损坏的灯光属性，逐字段使用已定义默认值；命令地址、Model 描述从该设备实际 Composition 按现有策略重建。不能给缺少 Node、MAC 或 Composition 的设备编造配置。
5. 原文缺失与显式 null 依现有 schema 语义判断；合法的可选配置为空不自动视为损坏。错误类型/越界/错误枚举等才进入对应修复规则；未知字段/版本不靠忽略实现“成功”。

若整个 HDB 无法解析且没有可校验的完整副本，不能从 Group 名称或默认 63 Zone 猜测旧成员关系。界面说明不可自动修复，保留 Retry Recovery/Saved Copies。

### 4.2 全量灯光默认值选项的影响

若用户选择“保留设备和 Zone，全部 HDB 灯光参数恢复默认”，复用 `HDBLightingValues.defaults` / `HDBLightingConfiguration.defaults`：

| 属性 | App 当前默认值 |
| --- | --- |
| Lighting Control | Auto |
| Failsafe Delay | 5 min（App 元数据，不下发设备） |
| Dim Intensity | 20% |
| Bright Intensity | 80% |
| Ramp Up Time | 1 s |
| Ramp Down Time | 2 s |
| Hold Time | 30 s |
| Install Date | 无默认日期，不生成虚构日期 |

本样本中 000E 的 dimIntensity 会从 5% 变为 20%、holdTime 从 10 s 变为 30 s；0011 的 dimIntensity 会从 0% 变为 20%。这些现值本身合法，必须在确认页明确列出。

使用默认值替换的设备字段按现有规则标记 pending；`failsafeDelay` 是 App 属性，复用其默认 synced 规则。合法未改变字段保留原状态。纯格式修复不得把所有已完成设备任务改成 pending。默认值保存成功不等于设备已执行；现有设备同步流程可能生成后续任务，确认页应说明修复值将在设备同步时应用。

## 5. 页面与完整执行路径

入口为 `SpaceRecoveryViewController`，保留 Retry Recovery、Saved Copies，增加指定英文选项 `Fix with default configuration`，简体中文建议“使用默认配置修复”。全部新增用户文案同步 en/zh-Hans。

按钮根据具体故障和可构造候选决定是否可用，不能仅凭通用 `configurationPersistenceFailed` 就允许重置。只允许当前有效的 owner/editor；重新核对密码、disableEditorPermission、账号/区域、membership、网络身份。visitor、退出/删除中、身份不匹配、未知待完成导入/提交等状态不得经此按钮绕过原保护。

推荐流程：

1. **准备预览**：读取同一版本的原始 HDB 与完整本地数据，GET 刷新权限和远端状态；只在内存生成候选，严格验证 HDB、Node/Group/Model 引用及完整 Space 导出。记录本地数据库 revision、原 BLOB 摘要、网络身份、membership generation、服务端版本与原响应内容摘要。
2. **确认具体变化**：显示本例“63 Zone 字段修复，保留 2 个设备”，列出实际被默认值替换的字段，并明确会把本机修复副本作为云端同步来源。若远端缺节点，本例明确显示服务器 0、本地保留 2；取消不修改业务数据。
3. **保存备份和恢复意图**：复用 `checkpoint(refresh:true)` 备份 App/Mesh SQLite，保存原始 HDB/远端响应和已审查候选；使用受保护恢复目录，不把密钥写入日志或文档。意图包含版本和阶段，写入成功后才能改数据库。既有 Saved Copies 用于导出备份时须核对读取目录，不能只保存内部 checkpoint 却声称用户能在列表中看到它。
4. **再次核对并提交**：确认版本/权限/身份未变化，使用现有 App 数据库 `configurationTransaction`。仅在专用、经过完整校验的修复流程中清除候选的失败标记并采用恢复写入权限，替换 HDB；本例无需改 Mesh 库、删除 Node/Group、回收地址或重新配网。普通 `save()` 保护保持。
5. **读回及收尾**：重载 Space，确认 HDB 能解码、完整导出可用、两个设备与 Group/Model 引用保持一致。建立本地修复版本及待上传状态后才清除本次数据阻断；不误清其他未完成操作。刷新持久对象和 Site 列表，再进入正常 Space。
6. **云端同步与再次进入**：复用当前 `localReplacementVersion`、local recovery pending、submission/readback 机制，让旧 GET 在修复上传确认前保留本机候选。修复版本必须大于本地、远端与最后上传版本；不能把修复动作当作服务器确认。完整上传后 GET 比较 HDB、Nodes、Groups、Timed 和身份，通过才结束待同步。

不能只给页面新增按钮后调用 `retry()`。现有 `HDBConfigurationStore.update` 要求未阻断且 HDB 已可读；`authorizeLocalRecovery` 要求完整本地导出和普通保存；`referenceRepairReview` 也依赖导出成功且只处理 Proximity 引用。三者均不能直接恢复当前坏 BLOB。

最小扩展是在已有安全恢复层接入“验证后的局部配置替换”：候选生成可使用小型 HDB 修复策略，但不另建一整套上传或恢复状态机。远端配置本身不能 canonicalize 时，用本次原始响应内容及版本绑定审查结果，不能以 `nil == nil` 作为远端未变化的证明。

同时修正已存在成员的合法云端恢复顺序：损坏本地配置不得在完整导入前被要求做普通保存。对已确认 canonical 身份的既有 Space，由导入事务提交合法配置；新成员/尚未初始化 Space 继续保留原身份建立、崩溃恢复与禁止提前上传要求。不能简单删除所有 `candidate.save()`。

## 6. 失败、重启和关联范围

- 备份或修复意图保存失败：零业务写入，继续显示可重试错误。
- 候选校验失败：显示实际不可修复字段；不改成空 HDB 或空 Space。
- 版本变化、账号切换、权限撤销、退出 Space：使旧预览失效，不提交旧候选；await 后再次检查。
- App 数据库事务失败：回滚本次写入，旧 HDB 原文保留；丢弃失败候选对象后重新加载。
- 事务成功、恢复状态文件收尾失败或进程退出：保留持久意图与阻断，重启后根据实际数据库读回继续同一次修复，不重新默认化、不重放旧云端导入。
- 同步失败/服务器继续返回旧 Zone 字段或空 Nodes：保留本机修复副本和待同步状态，Space 可基于已验证本地数据展示；不得把失败 GET 当作设备删除或重新覆盖本地。真实上传成功与 HTTP 成功分开确认。
- 本例仅修改 App HDB 与恢复记录，Mesh 数据保持；若后续支持真正改变 Group/Trigger Zone 的修复，需沿现有拓扑事务与设备任务机制另行确定范围。App 与 Mesh 为不同 SQLite 连接，现有 App savepoint 不能被当作跨库原子事务。
- Site 进入页与 Space 内已有配置恢复弹窗应共享故障判定和候选执行入口，避免一个入口能修、另一个只会失败；不改变合法普通 Site/Space、空配置、已成功 v2 的行为。
- 五品牌共享代码均受影响；新增文案需检查资源归属。SDK API、正式依赖和固件不需要因本方案改变。

## 7. 外部契约与本轮必要范围

本轮必须：当前混合格式候选修复、只读预览与备份、受限持久替换、有效云端恢复不再被旧行普通保存拦住、本地修复跨重启保留、旧 GET 不覆盖修复结果、上传回读结束条件、恢复页及已有恢复入口一致性。

不自动纳入：所有历史 HDB schema 的迁移、任意 Trigger Zone/Timed 拓扑重置、修复损坏的数据库文件、重建网络密钥或 Node、设备恢复出厂，以及改变服务器或固件实现。

服务端配合事项：核对 `/sitespace/get/spaceprops` 为什么在 deviceCount=2、HDB devices=2 时返回 `nodes=[]`，并确认 HDB v2 字段按上传内容完整保存/回传。仅凭本次 GET 无法判断是历史上传遗漏还是服务器存储/查询问题。责任方为服务端团队；用 App 完整上传与随后 GET 对比验证。无需等待外部问题定位就能开发并验证本机修复，但云端收敛要以联调结果为准。

## 8. 验证计划及已完成证据

实施后最小必要验证：

1. 脱敏复现本次混合格式：63 Zone、2 Node、Sensor Group、合法空成员、自定义灯光值保持；第二次修复幂等。
2. 默认值修复：单字段损坏只修该字段；合法 null/缺失可选配置不误修；新值 pending 与 App-only 值状态正确；错误网络身份、未知版本、缺 Node/Composition、重复或不确定地址继续拒绝。
3. 真实 SQLite：坏 BLOB → 修复 → 关闭重开后正常；备份失败、事务失败、收尾失败、崩溃阶段恢复；普通保存仍拒绝损坏行与旧版本冲突。
4. 合法云端完整副本可替换坏本地；原始服务器空 Nodes 副本不被误认为可完整导入；修复后旧 GET 不覆盖本地两个设备。
5. 云端 pending/上传回读：超时、错误、旧响应、权限变化、取消；只有完整匹配的回读可以确认。不得复用旧快照字段来伪造成功基线。
6. 两个恢复入口、owner/editor/visitor、合法空 Space、无 HDB 普通 Space、已完成 v2 配置；跨品牌本地化和资源归属。

优先扩展现有 `check_hdb_configuration.py`、`check_hdb_import_recovery.py`、`check_hdb_persistence.py`、`check_space_recovery_receipts.py` 和相关 Tests；按实际改动选择共享导入回归。实施稳定后构建一次映射核对正确的 `SunSmartLocal.xcworkspace` / SunSmart / Debug / generic iOS / 禁用签名；品牌资源或 target 配置存在差异时追加对应品牌。

本轮已完成：

- 原始两份样本读取、结构/身份比较和上述生产 HDB 编解码、引用校验探针；所有修改只在探针内存中，临时探针随运行结束删除。
- `python3 scripts/check_hdb_import_recovery.py` 退出 0：生产保存保护、坏 HDB 受限导入、旧版本冲突保护、pending/reviewed 快照选择与引用校验均通过。该脚本采用隔离存储和日志替身，不是手机 SQLite/Mesh 集成验收。

未运行 App 构建、真机 UI、真实手机 SQLite 恢复或在线服务器写入/回读。本轮为分析规划，无业务代码修改。

最短人工验收：原 Space 恢复页 → 预览修复差异 → 确认 → 正常展示 63 Zone 和 2 个设备 → 退出重进与重启保持 → 联网后确认服务器 HDB/Nodes 完整回读；设备属性真实生效另走现有设备同步并验收。
