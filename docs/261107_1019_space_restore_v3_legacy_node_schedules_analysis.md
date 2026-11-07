# Space 恢复失败：Timed v3 响应混入旧节点 schedules 字段

日期：2026-11-07，UTC+08:00。工作树 `feat-timed-simple-261106`，分支 `feat/timed-simple-261106`。

> 后续调整（用户已明确要求实施）：第 1～6 节记录修复前的分析。现在采用“同步只读取与校验 App 使用的属性，忽略多余历史数据”的输入规则，替代原先要求服务器先删除旧键的建议。实施范围与验证见第 7 节。

## 1. 结论与未完成项

**本次提示的直接原因是服务器详情声明 `spaceData.timedSchemaVersion=3`，但两台设备均携带 v3 已删除的 `nodes[].schedules: []`。当前 App 要求这个旧字段完全不存在，空数组和 null 都不符合 v3 契约。** Timed 校验在检查业务定时列表之前先检查节点结构，因此 Space 的 `schedules=[]` 也会触发 `invalidTimedPayload`，最终显示 “The schedule data could not be restored.”。

已使用当前生产 `TimedSchedulerPayloadPolicy` 和两份原始文件完成定向复现。仅在内存中移除服务器两个 Node 的 `schedules` 键，保持节点、密钥、版本和其他字段不变，Timed 校验及用于导入的日程解析便通过。此结果证明本样本的 Timed 拒绝点，不等于完整 Space 导入或设备恢复已经成功。

尚未确认：旧字段由服务器 DTO 自动补出、旧存储残留，还是其他写入端提供；当前手机的准确构建 revision；真实 GET／SQLite 导入／Mesh 运行结果。本轮只分析与留档，未修改输入文件、App／SDK 业务代码、服务器或运行配置，未执行网络写入和真机操作。

## 2. 输入与数据对照

- App 导出：`/Users/maginawin/Downloads/Space_Space 1_20261107_100329_309+0800.json`
- 服务器详情：`/Users/maginawin/Desktop/server data 2.txt`
- Space：`3486A356-ED8F-406C-8C83-EB8422387978`，名称 `Space 1`。

App 文件的 `_debugInspection.purpose=localConfigurationInspection`、`uploadable=false`，捕获时间为 2026-11-07 10:03:29 +08:00。它是本地诊断导出，不应作为原样上传文件。

| 项目 | App `spaces[0]` | 服务器 `data` |
| --- | --- | --- |
| Space UUID／NetKey／AppKey 对象 | 与服务器相同 | 与 App 相同 |
| `updateTimestamp` | 1794015449 | 1794015449 |
| `spaceData.timedSchemaVersion` | 3 | 3 |
| Space 级 `schedules` | `[]` | `[]` |
| `deviceCount` | 0 | 2 |
| `nodes` | `[]` | L1／0010、L2／0013，PID 均为 2502 |
| `nodes[0].schedules` | 无节点 | `[]`，键存在 |
| `nodes[1].schedules` | 无节点 | `[]`，键存在 |
| `nodes[].custProps` | 无节点 | 两台均为 `{}`，没有 `schedulerModelStates` |
| Groups／Scenes／Space 扩展等共同字段 | 与服务器相同 | 与 App 相同 |

对两个业务对象的所有共同顶层字段比较，差异只有 `deviceCount` 与 `nodes`。服务器额外包含权限、网关状态等 GET 字段；App 额外包含 `appKeyIndex`。本轮不输出凭据或完整密钥。

App 原始存储侧也确实没有两台节点：`rawLocal.mesh.nodes`、`rawLocal.mesh.nodePropertys` 均为空。诊断状态为 `active / writable / joined`、`configurationInitialized=true`、`pendingImport=false`、`pendingUpload=false`、`baselineNodeCount=0`；本地版本与最近确认版本相同，最近回读诊断为 `noPendingReceipt`。

因此当前存在两个不同事实：本地已经是零设备快照；服务器这份新样本有两台设备，却因 Timed 格式校验被挡在配置导入前。错误文案里的“已保存配置得到保留”不表示服务器两台设备已经恢复到手机。

## 3. 为什么空日程也会报 schedule 恢复失败

完整入口链为：

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `loadSpaceReqeust` 请求 Space 详情，取响应 `data` 调用 `restoreConfiguration(... authoritativeGET: true)`。
2. [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 执行恢复入口检查后调用 `candidate.update(...)`。
3. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 `SpaceData.update` 在业务配置替换前进行 Timed 预检：修复旧绑定、识别 schema、canonical 校验、日程解析及 Schedule 解码。当前第 1976–1985 行中，canonical 返回 nil 就返回 `.rejected("invalidTimedPayload")`。
4. [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `canonicalValidated` 在 v3 分支先遍历所有 Node。当前第 559–560 行要求 `node["schedules"] == nil` 且 `custProps.schedulerModelStates` 不存在。这里检查的是键不存在，不是数组长度为零。两台设备的旧键分别都足以使整份数据失败。
5. Site 页面收到 rejected 后显示恢复页。[SpaceRecoveryViewController.swift](../SunSmart/Main/Space/Controller/SpaceRecoveryViewController.swift) 将 `invalidTimedPayload` 映射为 `space_recovery_timed_invalid`，英文文案即用户看到的提示。

`CloudConfigurationDefaults.space` 和 `repairingStaleBindings` 不会删除原生 v3 的这些键。旧格式默认值兼容只作用于对应旧版本，不能把 v3 混合格式自动变成合法数据。当前文案覆盖整个 Timed 配置校验，包含 Node 结构，因此不只代表 `schedules[]` 中某条业务记录损坏。

恢复页 Retry 会重新 GET 并走相同导入路径；响应形态不变就会再次被拒绝，不是等待后台恢复一段时间就能消除。

现有 DEBUG 日志还有一个定位局限：本样本 Space 级列表为空，`logTimedImportFailure` 在 canonical 失败后会落到 `field=schedules.crossRecordConstraints`，不会直接指出 `nodes[].schedules`。这是日志分类过宽，不代表本样本存在两条业务定时冲突。本轮没有修改诊断日志。

## 4. 生产校验器定向实验

使用临时 Swift 入口直接编译当前完整生产 `TimedSchedulerSlotPolicy.swift`，从原文件读取数据。测试变体只在内存中生成，临时目录结束后自动移除；没有重新实现一个 Python 校验器来代替生产逻辑。

| 输入 | binding repair | canonical | `decodingSchedules` |
| --- | --- | --- | --- |
| App 原始导出 | 通过 | 通过 | 0 条 |
| 服务器原始响应 | 通过 | 拒绝 | 拒绝 |
| 服务器仅保留 L1，仍带旧键 | 通过 | 拒绝 | 拒绝 |
| 服务器仅保留 L2，仍带旧键 | 通过 | 拒绝 | 拒绝 |
| 保留两台，仅移除两台的 `schedules` 键 | 通过 | 通过 | 0 条 |
| 只移除其中任一台的旧键 | 通过 | 拒绝 | 拒绝 |
| 两台旧键均改为 null | 通过 | 拒绝 | 拒绝 |
| 移除旧键，但额外加入空 `custProps.schedulerModelStates` | 通过 | 拒绝 | 拒绝 |

全部断言通过，程序退出码为 0。另断言移除旧键后的 Timed canonical 与本地空业务日程的 canonical 相同；将原节点数组放回实验对象后，完整对象与原服务器对象相等。前者只比较 Timed 规范内容，**不代表零节点和两节点的完整 Space 配置相等**。

验证边界：直接执行真实 JSON 解析和生产 Timed policy，未运行完整 `restoreConfiguration`、手机 SQLite 事务、SDK Node 加载或真实网络／Mesh。没有修改 Swift 生产代码，按项目规则不构建 App。

## 5. 契约、引入时间与处理方向

这项拒绝规则来自 `e560574b`，2026-11-06 16:24:39 +08:00，`feat: improve timed json format`。

[Timed JSON 契约第 12.7 节](261105_1429_space_timed_json_demo/261105_1429_space_timed_json_contract.md)已经明确 v3 移除 `nodes[].schedules` 与 `nodes[].custProps.schedulerModelStates`，并规定“新读端遇到 v3 携带已删除旧键，拒绝冲突格式并要求写端规范化”。因此当前现象是 v3 数据契约与实际 GET 响应不一致；当前 App 的严格拒绝行为符合仓库已确认规则。不能仅因值为空就断定 App 本来应该忽略它。

该文档同时记录服务器 v3 存取、回写和旧写端约束为外部发布依赖，尚待对应团队验收。仅凭两份数据不能判断旧键在哪个环节生成，也不能推断它造成此前的服务器 HTTP 500。

建议先由服务器／对应写入方按既有 v3 契约核对：

1. 对这个完整 Space，追踪原始写请求、已存记录、GET DTO 三个边界，确认旧键是写入时存在还是读取时被默认补出。只需结构信息，不需要公开密钥。
2. 当 schema=3 时，GET 不再输出 `nodes[].schedules` 和 `nodes[].custProps.schedulerModelStates`。本样本具体是移除地址 0010、0013 两台的空 `schedules` 键；保留两台 Node、身份、网络、Composition 和其他业务内容。空 `custProps={}` 本身可保留，不是这次拒绝原因。Space 级 `schedules=[]` 必须保留。
3. 同时核对 Space 详情和 Site 内嵌 Space 的返回、正常写入及回写，避免另一个入口又补回旧字段；v1/v2 仍按对应旧契约读写，不全局删除旧格式的设备观察数据。
4. 对含非空旧观察字段的混合数据，先核对版本／迁移来源及业务绑定完整性，再执行已有 v3 规范化；不能用本次空数组样本证明所有混合内容都可盲目丢弃。
5. 最短验收：重新 GET 确认两台 Node 保留且旧键缺失 → App Retry／退出重进 → 确认进入 Space 且 L1、L2 恢复 → 再退出重进确认持久化结果。后续 Mesh 操作与真实定时执行独立验收。

责任边界：服务器 DTO、存取、部署由服务器团队实施；其他写入端由相应负责人修正。本任务不修改外部系统。当前 App 所需的既有对外契约没有新增结构；若另选“App 容忍 v3 的空旧键”，则会改变已确认的字段存在性规则，需要单独展示兼容范围及示例并确认，不能在本次分析中擅自放宽。

## 6. 与上一轮设备消失及工作区状态的关系

[上一轮设备消失分析](261107_0951_space_devices_lost_after_sync_analysis.md)处理的是上传失败后接受同版本空节点响应，导致本地设备丢失。本次文件显示服务器现有两台、手机零台，但**仅凭这两份新快照不能重建之前设备丢失的过程**。本次可明确定位的是“两台设备的响应为什么无法导入”。保护未确认本地新增设备的修复，不会消除这次 v3 旧字段拒绝。

开始时 HEAD 为 `f53d4dca`，已有 ImportData／SpaceConfigurationSafety、相关测试及上一轮分析文档的暂存改动。分析期间外部操作将这些改动提交为 `04526e6d3e9f3b6cd7f57545eb3f7c9b87d5d4a1`（10:17:16，`fix: don't remove devices if server missed`）；本任务没有执行提交。写本文前已复核新 HEAD 及干净状态，相关 Timed policy、默认值入口和恢复文案在两个 HEAD 间没有变化，本次校验结果仍适用。SDK 未修改，本次纯策略实验不依赖 SDK。

## 7. 按用户新方向实施兼容

### 输入规则调整与不变部分

用户本轮明确授权忽略业务不使用的属性，并要求一并修复同类限制。以下为实施前核对出的具体范围；不新增／修改数据库结构，不改变 App 正常 export JSON 的键、类型、层级、默认值或业务语义，也不改写服务器。改变的是接收端对多余字段的容忍规则。

| 路径／入口 | 原行为 | 新行为 |
| --- | --- | --- |
| Timed v3 `nodes[].schedules`、`nodes[].custProps.schedulerModelStates` | 只要存在即拒绝 | 在共享输入适配中移除，不解码内容、不恢复为设备观察、不用于回执比较 |
| Timed v3 `schedules[].needDeleteNodeAddresses`、`needDeleteGroupAddresses`、`needDeleteSceneNumbers` | 只要存在即拒绝 | 忽略；真实待清理任务仍由当前 `nodeSlots[].state=pendingRemoval` 表达 |
| Timed v3 `schedules[].nodeSlots[]`、`.identity`、`.actionAddress` 内多余键 | 要求键集合完全一致 | 只解码当前使用的字段，忽略多余键，包括历史完整身份；实际本地身份仍从完整 Nodes 校验后展开 |
| HDB v2 `spaceData.hdb.lightingZones[].groupAddress` | 即使有效 `groupId` 存在也拒绝 | 仅读取当前 `groupId`，忽略旧 `groupAddress`；缺少／非法 `groupId` 仍拒绝 |
| HDB `spaceData.hdb.devices[].lightingConfiguration.lightingControl` 的多余键 | 要求恰好五个键 | 保留 status、value 及三个当前命令地址校验，忽略其余键 |
| HDB 照明属性中的旧 `mapValues`、`models`、其他不适用命令描述；failsafeDelay／installDate 的多余命令描述 | 按字段存在性拒绝 | 只读取该属性使用的值和命令目标，其余忽略 |

例如本次 v3 Node 带 `schedules:[]` 或 `schedules:"legacy"`、`custProps.schedulerModelStates:null`，均按该字段缺失处理；同一 Node 的 UUID、Device Key、地址和 Composition 仍须有效。HDB Zone 同时带 `groupId:"C001"` 与任意旧 `groupAddress` 时使用 C001；仅有旧 `groupAddress` 不会自动补出当前必需的 groupId。

这些属性在正常 v3／HDB v2 导出中仍不输出，不增加上传保留服务器未知数据的机制。旧 Timed v1/v2 的节点观察和清理数组仍属于其迁移所需业务数据，按旧规则解析与验证；本地完整 binding 的身份校验及导出时防止未迁移清理任务丢失的检查保留。HDBPreparationTarget 属于本地初始化内容，不是当前 HDB 云 JSON 的历史附加字段，本轮不改其内部不变量。

### 共享入口及验证安排

通过 Timed 共享输入规范化处理，覆盖 CloudConfigurationDefaults、Space／Site 导入、reviewed／pending import、Schedule 解码、恢复回执及分享文件读取；不能只删除 canonical 中两行，让 SDK／后续 snapshot restore 继续解析历史字段。v3 原生必需数组、绑定字段及错误类型保持严格，忽略字段不伪造物理设备空表或同步成功。

验证覆盖：实际样本、空／非空／null／错误类型的历史字段、多余嵌套键、有效字段损坏继续失败、v1/v2 不变、生产 Schedule Codable→真实 SQLite 重开→精简导出、恢复回执失败／重试、HDB 编解码与持久化；最后构建一次 SunSmart generic iOS Debug。共享逻辑影响五品牌，无品牌条件或资源归属变化，使用代表 SunSmart target。真实服务器往返和真机体验由用户验收。

### 实施结果与验证证据

已完成。生产修改仅涉及 `TimedSchedulerSlotPolicy.swift` 与 `HDBConfiguration.swift`，复用现有规范化、Codable 和导出机制，没有新增持久状态、恢复机制或依赖。Timed 与 HDB 对接文档已同步接收端的新规则。

| 验证 | 结果与范围 |
| --- | --- |
| `check_timed_device_slots.py` | 通过；v3 历史字段任意 JSON 类型、多余嵌套键、幂等／分享往返，缺失／非法当前字段继续拒绝，旧格式与槽位规则保留 |
| `check_timed_slot_persistence.py` | 通过；历史清理字段不进入生产 Schedule，真实 SQLite 保存／重开保留完整本地身份，导出不带旧键；失败回滚、晚到回执、未知观察、删除与重试通过 |
| `check_space_recovery_receipts.py` | 通过；v3 状态变化仍保留未确认回执，相同有效内容附带历史字段可确认；磁盘重开、失败／重试及同版本新增设备保护均通过 |
| `check_scheduler_cloud_roundtrip.py` | 通过；执行生产 snapshot restore 与 SDK 编解码／属性持久化片段；v3 旧数据不会恢复成观察，已有本地观察不被覆盖；旧版 70 节点／140 Model 容器往返和坏数据拒绝保留 |
| `check_cloud_node_import.py --snapshot '/Users/maginawin/Desktop/server data 2.txt'` | 通过；原始样本经生产完整配置预检、SDK 可选标识字段解码和导入 staging gate，保留两台 Node |
| `check_hdb_configuration.py` | 通过；附加字段忽略、正常导出不变；当前必需字段、实际命令目标、格式／范围／引用错误继续拒绝 |
| `check_hdb_persistence.py` | 通过；附加字段不影响 HDB 回执比较、实际 SQLite BLOB 重开、回滚及精简再编码 |
| `git diff --check`、文档链接 | 通过 |
| SunSmart generic iOS Debug | `xcodebuild` 最终退出码 0；确认两个修改文件的 arm64 对象及 App 可执行文件已生成 |

构建入口：`SunSmartLocal.xcworkspace`，scheme `SunSmart`，`-configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。使用独立 DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-timed-simple-261106-unused-fields`。本地 SDK realpath 为约定的 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，核对时干净，未修改 SDK／依赖声明。构建输出含第三方告警及一次 CryptoSwift 编译任务空输出诊断，最终命令成功；未以该中间诊断修改业务代码或清理缓存。

验证中修正过新增 HDB 测试里的 Swift throwing autoclosure 写法；Timed SQLite 初次运行被默认 Clang 缓存目录权限阻断，随后通过 `CLANG_MODULE_CACHE_PATH`／`SWIFT_MODULECACHE_PATH` 指向允许写入的 `ModuleCache.noindex/TimedSimpleChecks` 后通过，未改变测试业务逻辑。

边界：Cloud Node 夹具仅执行真实 SDK 可选标识字段，其余 Node 对象、数据库 staging 和网络为显式替身；SQLite 日程和 HDB 测试覆盖各自真实存储边界，但不替代完整手机 Space 导入事务。没有操作真机、真实 GET／POST 或 Mesh。此次构建验证代表共享逻辑编译，不宣称五品牌各自运行验收完成。

最短人工验收：运行当前分支 App，服务器保持原始两台设备和历史 schedules 字段 → Space 1 点击 Retry／退出后重进 → 确认不再出现 schedule restore 提示，L1、L2 显示，Timed 列表为空 → 再退出重进确认持久化。后续按正常操作同步，核对上传仍为 v3 精简字段且设备未丢失；真实同步结果单独验收。

交付时基线仍为 `04526e6d`，所有本次业务、测试、文档改动均未提交。未修改服务器、固件、输入样本或其他工作树。
