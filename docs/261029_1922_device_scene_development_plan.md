# 设备场景开发方案与执行计划

> 当前执行方式（2026-10-30）：用户已授权主代理以 Astra High 子代理串行完成 T06～T09；每阶段实现、独立审查和必要验证后由主代理 Git commit，再开始下一阶段。不 push/merge，不自动运行真机。原有阶段记录保留为历史证据。

日期：2026-10-29；最终交付更新：2026-10-30。T01～T09 的 App 实现、阶段验证与最终代码审查已完成；真实界面、设备/Mesh、具体开关及云端仍待人工验收。T06～T09 按用户授权使用 Astra High 子代理串行实施，由主代理逐阶段提交；最终版本与证据见第 7 节末尾。

**目标**：让用户选择具体设备、分别设置场景参数，并与组场景共用保存、同步、失败恢复和清理机制；首期接入现有定时及实体开关入口。

**方案**：保留组场景现有参数来源，为设备场景保存明确的成员和期望参数；两种模式统一解析成具体设备目标，复用现有任务执行、容量检查、定时绑定和恢复机制。界面编辑使用独立草稿，最终确认前不提交正式场景。

**技术环境**：现有 Swift/UIKit、NordicSigMeshSDK、SQLite、CocoaPods/SPM；不引入新依赖，不迁移 SwiftUI。

**验收依据**：[设备场景需求、UI 核对与 63 条测试用例](261029_1625_device_scene_requirements.md)。Q01～Q10、R1～R5 是已确认规则；本文中的技术拆分是本次建议，不能覆盖产品规则。

## 1. 本期范围和交接基线

- Groups / Devices 互斥。设备模式中的组只用于分类与选择，换组、退组、后续组成员变化不改变场景成员。
- 两类场景有实际设备目标时统一为 DONE → 发送设置 → 确认结果及待同步设备 → 保存。合法空组预配置直接保存；已有设备全部离线也允许保存期望配置。
- 弹层拖动、加减、OFF、遮罩提交和 Relay APPLY 只改变草稿；预览和 DONE 发送只应用参数，正式确认后才写入设备场景。
- 部分失败保留目标与任务。未提交草稿不跨重启；已提交任务重启后可由设备同步继续。
- 移除成员只移除场景关系；离线允许移除，清理失败不释放占用。无有效成员且无待清理任务才可切换类型。
- 首期接入定时及实体开关，显示待同步，不仅因为待同步禁止选择或调用。具体开关跨组能力以真实发送目标及实机结果确定。
- 本期只声明旧 App 不支持，不增加版本拦截；旧版可能丢失新字段的风险已接受。新版间分享、导入和恢复仍须完整。
- 只负责 App。固件、服务器、运行配置和部署不在实施范围；如外部保留字段或设备行为不满足要求，记录契约和联调结果，由对应团队处理。
- 新增 UI 文案复用国际化 Key；新 Key 同时补 English 和简体中文。复用现有控件、主题与资源，不复制它们附带的错误业务行为。

| 项目 | 本轮核对结果／执行时要求 |
| --- | --- |
| 工作树 | `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028` |
| 分支与 App HEAD | `feat/device-scene-261028`；`eba3d3d8ab57f9bbf941c81d89d175d15f25668e` |
| 已有差异 | `SunSmart.xcodeproj/project.pbxproj` 有外部未提交改动，21 行增、21 行删；不得覆盖。两份本任务文档尚未提交 |
| 本地入口 | 已有 `SunSmartLocal.xcworkspace`，引用 App、Pods 和 `.local-sdk/nordic-sig-mesh-sdk` |
| SDK | 链接实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；HEAD `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，本轮检查无未提交差异 |
| SDK 改动判断 | 当前方案可使用既有 Model 发送及 App 侧消息上下文，暂不需要修改 SDK；执行时发现真实缺口再记录，不预设 SDK 升级 |
| 版本保护 | 本文的数据格式版本用于新版解析与校验，不等于新增旧版访问限制 |
| 规划基线的验证现状 | 规划时仅静态调查和文档检查；本轮实施的自动化/构建结果见第 7 节，实机和云端未执行 |

执行前重新核对以上可能变化的项目；不同工作树不会自动带上当前未提交文档、本地 workspace、Pods 和 SDK 映射。

## 2. 选择的方案与理由

| 方案 | 实际影响 | 结论 |
| --- | --- | --- |
| 扩展现有场景，共用设备目标和同步链 | 保存直接成员与独立参数；组模式继续从真实组展开；改造相关消费者 | 推荐，符合用户不维护两套逻辑的要求 |
| 单独建一套设备场景同步 | 新页较容易独立开发，但失败、清理、定时、分享和恢复都需长期维护两套 | 不采用 |
| 把每台设备包装成隐藏组 | 会改变组关系、占用组资源，影响换组和其他组功能 | 不采用 |

这项工作按一条完整业务链分阶段实现，不能把新页面完成当作功能完成。第一阶段先完成数据、任务及失败恢复的行为测试，之后再接 UI。

### 2.1 三份数据各自负责什么

| 数据 | 保存什么 | 生命周期 |
| --- | --- | --- |
| 编辑草稿 | 本次所选模式、成员、参数、名称和图标 | 只在当前编辑期间；放弃或重启丢弃，不改 Node 实时状态 |
| 已提交期望配置 | 用户确认要保留的场景；待写入和待清理目标 | 保存在 App 数据库，参与分享和恢复 |
| 设备执行观察 | 已确认的 Store/Delete 结果、实际占用 | 继续使用 Node 场景缓存和 Register；不能反过来充当成员定义 |

`SceneExecuteData` 是引用对象，草稿必须复制参数，不能共用对象后直接改值。`scene.addresses` 反映 SDK 的设备记录，也不能替代直接成员清单。

### 2.2 最小新增模型及约定

新增类型集中在 `SunSmart/Main/Scene/Model/SceneConfiguration.swift`，优先使用值类型；以下名称作为任务间接口约定：

| 类型 | 字段或职责 |
| --- | --- |
| `SceneKind: String, Codable` | `groups`、`devices` |
| `SceneParameters: Codable, Equatable` | `isOn: Bool`、`lightness: UInt16`、`cct: UInt16`；沿用现有 Mesh 数值与 trim 换算，不另存第二份百分比 |
| `SceneDeviceMember: Codable, Equatable` | `identity: TimedSchedulerNodeIdentity`、`parameters: SceneParameters` |
| `ScenePendingOperation: Codable, Equatable` | `identity`、`action`（`write` / `remove`）、`generation: UUID`；同一场景同一身份只有一个当前意图 |
| `SceneConfiguration: Codable, Equatable` | `schemaVersion: Int = 1`、`kind`、`name: String`、`revision: UUID`、`deviceMembers`、`pendingOperations`、`isDeleting: Bool` |
| `SceneDraft` | 现有编号可空、名称/图标、模式、`groupParameters: [Address: SceneParameters]` 或直接成员、`revision: UUID`、进入编辑时的原配置比较值；每次改动换 revision，切换模式不得同时留下两类有效配置 |

身份复用 `TimedSchedulerNodeIdentity` 及 `Node.timedSchedulerIdentity`：Node UUID、主地址、Device Key 指纹。它虽以 Timed 命名，实际字段可识别配网实例，本期直接复用，不为改名扩大重构。外层另校验当前 Mesh UUID、Space/network ID；不输出完整密钥。

组参数继续以 `GroupInfo.sceneExecuteDatas` 为准；`SceneConfiguration.deviceMembers` 在组模式必须为空。组关系和设备关系冲突、身份重复、显式损坏或未知格式，均不能静默按空场景处理。旧记录没有配置块时按组模式读取，不从 Node 执行缓存猜测设备模式。

`SceneConfiguration.name` 是已提交元数据的恢复来源；图标沿用 SceneInfo.imageId。新增或修改后的 SDK Scene 基本记录是它们的投影，名称编辑必须同步走同一保存入口。此约定用于处理 App 数据库与 Mesh 数据库分开的中断窗口，不新增第三套场景存储。

### 2.3 共用目标解析，分类只影响显示

在 `SceneTargetResolver.swift` 中提供：

- `SceneTargetResolver.resolve(scene: Scene) throws -> SceneTargetSnapshot`
- `SceneTargetResolver.resolve(draft: SceneDraft) throws -> SceneTargetSnapshot`
- `SceneTargetSnapshot` 含当前作用域、提交/草稿 revision、实际写入目标、清理目标以及无法解析的目标；每个实际目标含原身份、Node、参数和可选显示分类。
- `SceneTargetSnapshot` 的比较值排除进度、ACK 和已完成任务数量；同步使用 `taskComparison` 进一步排除名称，元数据保存保持设备配置 revision，编辑器仍使用完整比较值和源名称/图标冲突检测。自己完成一台或仅修改名称/图标不能让后续任务失效，真实配置变化仍拒绝旧回执。

组模式展开有效组关系及当前成员；设备模式仅解析直接成员。两者统一按身份去重、按设备能力修正参数；待清理目标独立于当前显示分类和当前组。

所有依赖场景目标的容量、定时、同步、回执、状态读取和调用入口均消费这个结果。保留已有组接口作必要兼容适配，禁止在新调用处再复制一套 `scene.info.groups.flatMap`。

### 2.4 保存与恢复的执行次序

1. 创建只建立草稿；Templates 只生成组草稿，不提前往正式列表插入 Scene。
2. 预览或 DONE 固定当前草稿快照，按实际设备发送参数；不执行 SceneStore、SceneDelete 或正式任务持久化。DONE 即使已有预览仍重发。
3. 发送结果区分成功、失败和离线；确认页展示期望设置及待同步设备。全部离线不假报成功，也不阻断已有成员保存。返回调整后使上一轮确认失效。
4. 最终确认重新核对作用域、编辑权、设备身份、当前快照及新增容量。草稿自身 revision 相同还不够：若编辑期间原配置被其他入口改动，或组成员/能力变化使本轮实际目标改变，应保留输入并提示重新加载或发送，不能静默覆盖或确认另一批目标。新建编号此时按既有合法区间和特殊编号排除规则分配，但占用集合必须是 SDK 已有编号与同一 Mesh 全部已提交 SceneInfo 编号的并集，包含待投影、待清理和 isDeleting 记录；最终 App 事务内再检查一次，不能只调用当前 SDK 分配函数。发送参数阶段无需占用编号；合法区间不足的申请仍沿用现有服务接口，取得新区间后也不能忽略上述保留集合。
5. 在同一 App 数据库事务中保存 SceneInfo 配置、组关系变化、定时槽位保留和待处理意图；事务失败恢复内存，保留草稿，不启动正式写入。
6. 再保存 SDK Scene 基本记录，成功后才能向设备执行正式任务。两份数据库不是一个事务：App 已提交但 SDK 投影失败时保留已提交记录并显示本地记录待恢复；不显示全部保存完成，不发 Store，不丢掉重试依据。
7. 加载 Space 时，在组/设备配置都读入后，先按 App 已提交记录补齐或修复 SDK Scene 投影，再生成任务。导出同样以 App 的已提交记录为准，不能因 SDK 行尚未补齐而漏导出场景；普通旧组场景仍沿用旧加载方式。
8. 正式写入和重试均重新应用持久化期望参数，再 Store；不能把确认期间实体开关或其他控制造成的临时灯光当成期望参数。设备成功一台，确认并保存一台；结果保存失败仍显示待同步。
9. 任务中断后复用现有设备同步继续，无需重走创建确认；同步到云端另记结果。新功能未完整接入加载/导出前不作为可发布中间版本。

实现沿用 `TimedSchedulerBindings.commit`、现有 App 事务和空间恢复机制；不能把一层 `db.savepoint` 误称为跨两个数据库的原子提交。无需为此制作通用事务框架。

### 2.5 命令、回执和清理共用规则

- 从 `Scene.getSyncMessageHandles(node:data:)` 提取 `SceneCommandBuilder.parameterHandles(node: Node, parameters: SceneParameters) -> [MeshMessageHandle]`。预览/DONE 只取参数命令；正式同步在参数全部成功后 Store，参数失败不把设备当前旧状态误存成成功场景。
- 继续复用 `deviceTarget(for:)`、范围修正和现有消息类型；Relay 的 ON/OFF 以 `isOn` 为准，不能依赖不存在的亮度控件。旧组参数的其他既有字段不得被新三字段视图静默清空。
- 通过 App 侧 `SceneMessageContext` 把 Mesh/Space、场景编号、配网身份、配置 revision、操作 generation 和期望参数快照关联到 `MeshMessageHandle`，复用 `timedSchedulerContext` 的实现方式，不修改 SDK 消息协议。
- 草稿变更、提交和结果应用沿用当前同步会话的主线程串行归属；所有 App 应用 Store/Delete 结果的入口统一检查该上下文，包括 `Node.applyMessageHandle`、`SyncExecutionSession+Result` 以及其他直接回调路径。不能仍由 `Node.updateData` 从当前组或实时灯态推导设备场景缓存。
- `SpaceSyncTaskScope.capture` 纳入场景的配置内容及目标身份；排除任务进度变化，避免完成一台后把自己的剩余任务全部作废。切 Space、换配网身份、编辑新版本时旧结果不得确认新任务。
- 移除有定时引用的目标时，先清对应 Scheduler，再 SceneDelete；写入时先 SceneStore 成功，再配置依赖定时。复用现有步骤依赖。
- 移除后重新加入：替换旧 remove 意图为新 generation 的 write。旧命令可能已发出，不能假设已撤回；旧结果不得删除新成员、清掉新 write 或释放编号。先等待既有停止机制完成，再生成新写入轮次；最终以新期望重新应用和 Store 收敛。
- 整体删除沿用引用保护。保存 `isDeleting` 及清理意图，待所有目标清理完成再删 SDK 记录及 SceneInfo、释放编号；中断按相同意图重试。`isDeleting` 记录不会被加载逻辑重新当作普通可执行场景补建。
- 真正删除设备时，仅清掉匹配原配网身份的引用；普通换组/退组不得清设备场景或其定时。设备从页面消失不等于物理清理成功。

### 2.6 分享、导入及恢复契约

本地在 `sceneInfos` 增加可空 `configuration` JSON 列，迁移可重复执行。`nil` 是合法旧数据；显式解码失败保留失败状态，不返回默认空配置覆盖原文。

外部载体使用已有 `spaceData.sceneConfigurations` 数组；每项由 `number`（沿用四位十六进制格式）和 `SceneConfiguration` 字段组成。仅输出已有显式配置块的普通场景；旧组数据未编辑时不强制逐条改写。顶层 `scenes` 保留既有 number/name/imageId，数据来自同一已提交记录，不维护两份不同期望值。

- 新版导入先完整校验，再替换现有数据。校验编号、身份、模式互斥、重复成员、版本、清理意图及与顶层场景元数据的一致性。缺块兼容旧组；显式坏块拒绝覆盖。
- 同一编码/解码与规范化函数服务数据库、导出、导入和完整性校验。排序固定，正常字段顺序不同不产生冲突。
- `SpaceConfigurationIntegrityPolicy.configurationData` 纳入新块；组场景普通参数也需作为场景配置比较，不能只比较 Group Profile。上传读回、恢复快照、节点删除投影均走相同规则。
- 旧恢复收据的比较格式升级使用既有基线升级路径：区分旧收据本来不含场景字段与本次上传后远端意外缺字段。不能全局把缺失视为空或忽略新字段，误把丢失当成功；也不能让未改动旧 Space 无故无法进入。
- editor 分享恢复的是期望配置和任务意图；不序列化运行中队列、闭包和定时器。只读角色不能继续配置。
- 云端是否原样保留此字段没有实测结论。验收必须完成分享、另一手机进入、重启、继续同步及上传读回；接口无需预设新增，但若已有接口丢字段应列为发布联调阻塞。

### 2.7 调用及实体开关的实际边界

App 设备场景调用使用已保存直接成员的 Scene Model 定向发送 Recall，避免把分类组地址或 SDK `startScene` 的全网目的地址用于设备模式；组模式保留原有调用范围。两处本地回显均按模式与各设备参数处理，待同步目标不能冒充已经达到期望值。紧急控制按实际目标检查，包含未分组设备。

| 入口 | 当前代码事实 | 本期处理 |
| --- | --- | --- |
| App 列表 | SDK `startScene` 向 allNodes 发送，App 之后按组更新缓存 | 设备模式逐目标发送；复用既有传输，不预设 SDK 新 API |
| 普通 EnOcean 开关 | Scene Recall 默认 allNodes | 接入选择、待同步显示；实测代理及残留编号响应。待清理设备仍可能响应，不能承诺 App 禁按钮能阻止 |
| 八键有电/电池开关 | Scene Recall 使用 `linkGroupAddress`；目标订阅来自 `bindGroups` | 保留现有发布和订阅范围，说明跨组/未分组目标可能不可达，不自动扩大全部按键的控制对象 |
| 八键虚拟面板 | 同样使用 `linkGroupAddress` | 与该开关按相同目的地址验收，不能用 App 场景列表成功替代 |

不新增“待同步禁选”。对于具体开关已有能力限制沿用现有提示；发布前按型号记录已验证可达范围。若用户要求突破现有开关范围，需要单独评估 App/设备能力及其他按键影响，不能在执行时偷偷改成全网广播。

## 3. 文件分工与任务依赖

新增文件仅承担以下职责，不再建立平行场景框架。现有大文件只改相关分支，不顺手拆分全文件。

| 计划新增文件 | 职责 |
| --- | --- |
| `SunSmart/Main/Scene/Model/SceneConfiguration.swift` | 配置值类型、草稿、编码和字段校验 |
| `SunSmart/Main/Scene/Model/SceneTargetResolver.swift` | 将两种模式解析成设备目标及清理目标 |
| `SunSmart/Main/Scene/Model/SceneCommandBuilder.swift` | 仅参数、正式 Store、设备模式 Recall 的消息组合与 SceneMessageContext |
| `SunSmart/Main/Scene/Model/SceneConfigurationStore.swift` | App 提交、SDK 基本记录投影和加载恢复；复用既有事务/定时绑定 |
| `SunSmart/Main/Scene/Model/SceneSaveCoordinator.swift` | 草稿发送、结果确认、提交阶段；复用 SyncExecutionSession 的传输、取消和结果能力 |
| `SunSmart/Main/Scene/View/SceneDevicesSelectionView.swift` | 搜索、分类、选择及计数，不控制灯 |
| `SunSmart/Main/Scene/View/SceneDeviceSettingsCell.swift` | 展示草稿/保存参数与定位、移除入口，不绑定 Node 实时值作为编辑值 |

执行依赖：T01 → T02 → T03 → T04；T05 依赖 T01/T04；T06 依赖 T02/T04；T07 依赖 T02/T03/T06；T08 依赖 T03/T04/T05；T09 收拢全部任务。默认一个执行 session 顺序推进；不把这些依赖任务并行写入同一工作树。

每个任务先写对应行为测试，运行确认因预期缺失而失败，再实施并运行相关检查；纯视觉调整不为形式另建测试工程。新增测试应执行生产逻辑，在传输、存储等边界注入失败，不能复制一套实现后只测副本。

## 4. 可交接任务清单

### T01：配置模型、本地持久化和旧数据兼容

**文件**：新增 `SceneConfiguration.swift`；修改 `SunSmart/Common/Data/MeshNetwork+SunSmart.swift` 的 `SceneInfo`、`SunSmart/Common/Data/Database.swift` 的 SceneInfo 读写/迁移；新增 `Tests/Scene/SceneConfigurationTests.swift`、`Tests/Scene/SceneConfigurationPersistenceTests.swift`、`scripts/check_scene_configuration.py`。

**接口**：产出第 2.2 节类型；`SceneConfiguration.decode(_ data: Data) throws -> SceneConfiguration`、`encoded() throws -> Data`；`SceneInfo.configuration: SceneConfiguration?` 与 `configurationLoadFailed: Bool`，以及 `SceneInfo.loadAll(meshUUID: String, subnetworkId: String? = nil) throws -> [SceneInfo]`。恢复必须扫描当前 Space 的 App 行，不能只遍历 SDK 已有 Scene，否则找不到双库中断时缺失的 Scene；编号分配传 nil 扫描同一 Mesh 全部已提交记录，避免跨子网重复占号。后者不得被 `?? 默认值` 吞掉。新增脚本接受 `--suite model|storage|all`，失败退出非零，成功打印对应 suite 的实际通过结果。

- [x] 编写 `legacyMissingBlockLoadsGroups`、`duplicateIdentityIsRejected`、`groupModeRejectsDeviceMembers`、`corruptBlockDoesNotBecomeEmpty`、`draftCopyDoesNotMutateStoredValues`；使用 A/B 不同参数、同地址不同 UUID/指纹、OFF 的样本。
- [x] 编写并运行真实 SQLite 小夹具：重复迁移、旧行加载、新配置重开库不丢字段、数据库不可用/写入失败不报成功。沿用项目 SQLite 测试方式，不新建 Xcode 工程。
- [x] 实现值类型和最小新增列，保留旧组参数来源及失败状态。只纳入正式普通场景，特殊保留场景不误迁移。
- [x] 运行 `python3 scripts/check_scene_configuration.py --suite model`、`python3 scripts/check_scene_configuration.py --suite storage`；核对 DS-03、06、32、40、43、45、51、54。记录其仅覆盖本地数据，不是云端或灯端通过。

**完成条件**：成员、参数、任务与失败状态可保存/重载；缺字段兼容和损坏拒绝明确分开。

### T02：共用目标、容量和定时投影

**文件**：新增 `SceneTargetResolver.swift`；修改 `SunSmart/Common/Data/SceneCapacity.swift`、`MeshNetwork+SunSmart.swift` 的 `Schedule.targets`、`SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift`、`Scheduler.swift`、`ScheduleServer.swift`。扩展 `Tests/Scene/SceneTopologyTests.swift`、相关 `Tests/Timed`；新增 `Tests/Scene/SceneTargetResolverTests.swift`，接入 T01 脚本 `--suite targets`。

**接口**：消费 T01 模型，产出第 2.3 节 `resolve` 与 `SceneTargetSnapshot`；为 `TimedSchedulerBindings.prepareTopology` 和 `SceneCapacity` 增加可接收草稿目标快照的入口，现有组调用保留适配。

- [x] 先测 `deviceTargetsIgnoreGroupChanges`：Group 1 的 A/B 已选、X 未选；换组/退组/加入 X 后目标仍为 A/B。另测 U 未分组、合法空组、待清理目标不在当前分类。
- [x] 补容量与定时行为测试：同编号离线修改无需新增占位；新增未知容量不能当空；待清理不释放；Device Scene 退组时定时仍指向本人；无 Scheduler 能力的目标沿用既有能力规则，不假装已配置定时。
- [x] 实现唯一解析入口及相关投影。已有关系离线修改/减少不得被无差别 Scheduler 预读拦截；新增实际占用保留读取、容量及权限限制。
- [x] 运行 `python3 scripts/check_scene_configuration.py --suite targets`、`zsh scripts/check_scene_capacity.sh`、`python3 scripts/check_scene_topology.py`、`python3 scripts/check_timed_device_slots.py`、`python3 scripts/check_timed_slot_persistence.py`、`python3 scripts/check_schedule_scene_target_export.py`。

**完成条件**：DS-05～07、20～21、40、42～44、47、50、61～62 对应目标/容量规则有行为证据；真正空场景与绑定空组不会混淆。

### T03：共用命令、回执和设备同步入口

**文件**：新增 `SceneCommandBuilder.swift`；修改 `SunSmart/Common/Data/Node+MessageHandles.swift`、`Node+SyncData.swift`、`MeshNetwork+SunSmart.swift`、`SpaceSyncCleanupCoordinator.swift` 的 `SpaceSyncTaskScope`、`SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift` 的 `Node.applyMessageHandle`；修改 `SunSmart/Main/Space/Model/SyncSceneScheduleTaskBuilder.swift`、`SyncDevicesCellModel.swift`、`SyncExecutionSession+Result.swift`、必要的 `SyncExecutionSession+Acknowledgement.swift`。新增 `Tests/Scene/SceneCommandTests.swift`、`Tests/Scene/SceneSyncLifecycleTests.swift`，扩展 `Tests/Sync`。

**接口**：`SceneCommandBuilder.parameterHandles(node:parameters:)` 供预览；保留 `Scene.getSyncMessageHandles(node:data:)` 对外兼容并转交共用构造；`SceneMessageContext.matches(node: Node) -> Bool` 校验当前任务所有权；任务构造消费 T02 快照。

- [x] 先测 OFF、Relay ON、调光、CCT 范围修正及“预览无 Store”；正式任务按参数→Store，参数失败不完成 Store，Store 回执失败不清 write；合格目标在发送时能力消失/无法构造命令应失败，不把空命令列表当完成。
- [x] 补 `staleStoreCannotAcknowledgeNewRevision`、`lateDeleteCannotRemoveReaddedMember`、`spaceSwitchRejectsOldReply`、`addressReuseRejectsOldReply`、`firstSuccessDoesNotInvalidateRemainingTasks`。后者使用 A 成功后 B 仍需继续的场景。
- [x] 改造共享任务和结果应用。同步页、单设备/批量设备同步、组加入/退出、恢复入口统一解析；特别补 `getStandardNeedSync` 的未分组写入，以及 `getNodeNeedDeleteSceneDatas` 的退组误删设备场景分支。
- [x] 运行新增 `python3 scripts/check_scene_configuration.py --suite sync`、`python3 scripts/check_sync_execution_session.py`、`python3 scripts/check_sync_task_builders.py`、`python3 scripts/check_sync_run_lifecycle.py`。必要时扩展脚本把 Scene builder 纳入生产逻辑夹具；原脚本通过不等于新增路径已覆盖。

**完成条件**：DS-25～29、33～36、39～43、61、63 对应消息和失败恢复成立；组/设备只有一套正式同步执行规则。

### T04：提交、加载恢复和统一保存阶段

**文件**：新增 `SceneConfigurationStore.swift`、`SceneSaveCoordinator.swift`；修改 `Database.swift`、`MeshNetwork+SunSmart.swift` 的加载与名称编辑关联、`SyncExecutionSession.swift`/`SyncDevicesCellModel.swift` 的参数发送阶段适配；新增 `Tests/Scene/SceneSaveFlowTests.swift`，扩展 T01 持久化测试。

**接口**：`SceneConfigurationStore.commit(draft: SceneDraft, expectedRevision: UUID) throws -> SceneCommitResult`；`SceneCommitResult` 在此文件定义为 `.ready(Scene)` 或 `.projectionPending(number: SceneNumber)`。只有 App 尚未提交的错误才 throw；App 已提交后的 SDK 失败返回 projectionPending，coordinator 记住已提交编号，不允许再次确认造成第二次新建。`restoreSceneProjections() throws`、`nextAvailableNumber() throws -> SceneNumber`（合并 SDK 与 App 占用，遵守现有合法分配区间）；`SceneSaveCoordinator.send(draft: SceneDraft, purpose: SendPurpose)`（`preview`/`beforeSave`）、`confirm(revision: UUID)`、`cancel()`。发送结果按身份记录，回调只返回当前快照。只参数阶段复用既有执行会话，不另建全局命令队列。

- [x] 先测 `confirmRequiresLatestSnapshot`、`sourceConfigurationChangeRejectsStaleDraft`、`groupMembershipChangeRequiresResend`、`previewDoesNotPersist`、`offlineExistingTargetsCanCommit`、`emptyGroupSkipsSend`、`discardDoesNotRestoreLights`、`committedTaskSurvivesRestart`。
- [x] 注入两个数据库之间的失败/中断：App 事务失败、App 已提交而 SDK Scene 尚未写入、SDK 投影保存失败、Store 成功但结果落库失败。验证不丢配置、不假报成功、不重复创建场景，重载后可继续。增加 `projectionFailureReservesNumberForNextCreation` 与 `restartWithProjectionFailureKeepsReservation`：A 的 SDK 投影失败后新建 B，立即和重启后均不得复用/覆盖 A 的编号；原 A 重试仍使用自己的编号。
- [x] 实现第 2.4 节顺序。复用现有编号申请、事务、任务执行和停止机制。内存草稿与已提交记录分离；当前确认前无正式清理；停止旧轮次后才能用新快照发送。
- [x] 运行 `python3 scripts/check_scene_configuration.py --suite save`、`python3 scripts/check_scene_configuration.py --suite storage`、`bash scripts/check_configuration_database_safety.sh "$PWD/.local-sdk/nordic-sig-mesh-sdk"` 和受影响同步生命周期测试。

**完成条件**：DS-27～36、41、61～63 的保存阶段可在不依赖 UIKit 的测试中复现；现有组预配置仍可离线保存。

### T05：分享、导入、上传读回及完整性恢复

**文件**：修改 `SunSmart/Common/Data/ExportData.swift`、`ImportData.swift`、`SpaceConfigurationIntegrityPolicy.swift`（内含 `SpaceCloudNodeRemovalPolicy`）、`SpaceConfigurationSafety.swift`；按实际属性入口修改 `SpaceData.swift`。复用 T01 codec；新增 `Tests/Scene/SceneConfigurationRoundTripTests.swift`，扩展 `Tests/Group/SpaceRecoveryReceiptTests.swift` 及旧基线测试。

**接口**：`SceneConfigurationStore.exportRecords(scope:scenes:)` → `SceneConfigurationPayload.encode(records:) throws -> [[String: Any]]`（以 App 已提交行合并旧 SDK 元数据；原 `encode(scenes:)` 调整原因见第 7 节）、`decode(_ value: Any?) throws -> [SceneNumber: SceneConfiguration]`、`canonical(_ value: Any?) throws -> Data`，放入 T01 模型文件或其职责内小扩展，不建立第二套字段定义。外部字段固定 `spaceData.sceneConfigurations`。

- [x] 先测完成/待写入/待清理/整体删除四类往返；待 SDK 投影补齐的场景仍可导出；旧数据缺块按组，坏块拒绝替换；仅字段/成员排序改变不误报配置冲突。
- [x] 补读回与恢复测试：新字段被删除或改值不能判上传确认成功；旧比较收据升级不误拦正常旧 Space；旧 App 缺字段风险按已接受规则记录，不新增版本门禁。
- [x] 将场景配置和普通组场景参数接入 canonical、快照、恢复与节点移除投影；导入先校验后替换，任一步失败保留原可恢复状态，保持身份和权限校验。
- [x] 运行 `python3 scripts/check_scene_configuration.py --suite roundtrip`、`python3 scripts/check_space_recovery_receipts.py`、`python3 scripts/check_schedule_scene_target_export.py` 及实际受影响旧基线测试。记录离线往返与真实云端验收的区别。

**完成条件**：DS-35、43、45、52～55、63 的离线数据链有证据；真实分享/云端读回仍单列待验收。

### T06：设备选择、参数 UI 与组场景统一保存

**文件**：新增 `SceneDevicesSelectionView.swift`、`SceneDeviceSettingsCell.swift`；修改 `SunSmart/Main/Scene/Controller/SceneAddViewController.swift`、`SceneSettingsViewController.swift`，必要扩展 `SunSmart/Main/Scene/View/SceneExecuteDataPickerView.swift`；新增 `Tests/Scene/SceneDraftSelectionTests.swift`。现有基础控件的位置以实际符号为准，不复制到 Scene 目录。

**接口**：选择及参数回调只更新 `SceneDraft`，DONE/预览/取消只调用 T04 coordinator。新参数沿用 ON/100%/4500K 并按有效范围修正；OFF 后 ON 恢复允许最大亮度，已有保存值优先。复用 `DeviceNameFilterSession`、`CustomSegmentedControl`、`DeviceSliderFunctionView`、`CustomDeviceSlider`、`SRAlertView` 和现有 Identify 分支。

- [x] 先测 `selectAllUsesFilteredEligibleSet`、`hiddenSelectionsAreRetained`、`switchModeCancelRetainsDraft`、`bulkEditOnlyChangesSelectedMembers`、`relayApplyCommitsDraftOnly`、`oldSliderCallbackCannotOverwriteNewValue`。
- [x] 实现搜索、分类和参数编辑。全选范围是当前过滤的合格集合，不是屏幕可视行；全选提示明确。最低能力 OnOff Server + Scene Setup Server，离线已有成员可操作但不能新加入离线设备。
- [x] 把 Custom、Templates、已有组编辑和设备编辑接到同一保存阶段；去掉错误的全局连接拦截，保留有效权限/新增容量检查。弹层遮罩提交草稿，Relay APPLY 提交、Cancel 丢弃；不沿用定时列表“点卡片立即控灯”。
- [x] 运行 `python3 scripts/check_scene_configuration.py --suite selection`（selection suite 同时编译运行 `Tests/Device/DeviceNameFilterSessionTests.swift` 及生产 `DeviceNameFilterSession.swift`）、`python3 Tests/UI/CustomDeviceSliderInteractionTests.py`；按 DS-01～24、30～32、51、58～59、61～63 准备人工界面验收。结构检查不能当布局和真实交互通过。

**完成条件**：UI 各入口都使用共用草稿/保存逻辑，未选设备不受批量设置和预览影响；无新的设备模板定义。

### T07：列表、详情、场景调用和定时/开关入口

**文件**：修改 `SunSmart/Main/Scene/Controller/ScenesViewController.swift`、`SceneViewController.swift`、`SunSmart/Main/Scene/View/ScenesViewCell.swift`、`SunSmart/Common/Data/SpacePageSyncRead.swift`、`NodeSyncStatusRefresh.swift`、`MeshNetwork+SunSmart.swift`、`SunSmart/Main/Timed/View/ScheduleScenesView.swift`、`SunSmart/Main/Group/Switch/Controller/SwitchSelectSceneViewController.swift`、`SwitchSelectScenePageController.swift`。沿调用核对 `PJEightKeySwitchData.swift` 和虚拟面板 sender，默认不改开关发布/订阅配置。

**接口**：`SceneCommandBuilder.recallHandles(scene: Scene) throws -> [MeshMessageHandle]` 为设备模式输出实际成员 Model 定向 Recall；组模式复用既有发送范围。列表/选择器使用现有 `NodeSyncStatusRefresh` 与扩展后的场景快照获取状态，不新增每行 BLE 查询。

- [x] 先测设备调用只向 A/B/U 发，不向同组 X 发；回显按各设备值且不能将 pending 期望假报为实际已达；未分组紧急限制有效；名称/图标编辑不改变成员。
- [x] 接入详情 Devices 数量和分类、待同步/待清理、名称图标与 Settings。新建定时的 `schedule == nil` 情况仍显示 Scene 自身待同步；开关选择器补同样状态，不因 pending 禁选。
- [x] 核对第 2.7 节各开关实际目的地址，输出型号/绑定范围/预期覆盖表到执行记录；不扩大其他按键的控制范围。App、虚拟面板、实体开关分别验收。
- [x] 运行 `python3 scripts/check_scene_configuration.py --suite integration`、`python3 scripts/check_timed_schedule_selection.py`、`python3 scripts/check_timed_list_sync_display.py`、`python3 scripts/check_node_sync_status_refresh.py` 及相关行为测试；DS-45～48、55～57 的实机结果另列。

**完成条件**：组与设备列表/选择入口状态一致，定时/开关首期入口接通，App 设备调用不会退化为分类整组控制。

### T08：删除、换组、设备恢复和编号释放

**文件**：修改 `SunSmart/Main/Scene/Model/SceneServer.swift`、`SunSmart/Common/Data/DevicePermanentDeletionCleanup.swift`、`SpaceConfigurationIntegrityPolicy.swift` 中节点移除投影；核对并按实际消费路径调整 `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`、`SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`、`Node+SyncData.swift`、`MeshNetwork+SunSmart.swift`。扩展 `Tests/Scene/SceneDeletionFlowTests.swift`、`SceneTopologyTests.swift` 及恢复夹具。

**接口**：`SceneServer.deleteScene` 保留既有引用保护和回调接口，内部使用 T02 目标、T04 提交及 T03 清理上下文；成员移除由草稿提交差异生成任务，不直接复用整体删除。

- [x] 先测分类只删已选 A/B、不删 X/Group；最后一台离线移除后不能转换；清理成功后允许转换；待清理编号不能复用；整体删除中断重进保持可重试。
- [x] 补真正删设备与普通退组的区别：退组不删设备场景/定时；相同地址新 UUID/指纹不继承；永久删除仅清原身份。重加与迟到 Delete 继续复用 T03 用例，不能另设不一致逻辑。
- [x] 按 Scheduler 清理→SceneDelete→释放关系/编号的顺序实现；保留无法解析的清理目标及错误提示，不能因 Node 查不到就自动宣称已清理。只在既有永久设备删除流程确认后移除对应身份记录。
- [x] 运行 `python3 scripts/check_scene_deletion_flow.py`、`python3 scripts/check_scene_topology.py`、`zsh scripts/check_scene_delete_capability.sh`、`python3 scripts/check_scene_configuration.py --suite sync` 及相关恢复测试。

**完成条件**：DS-37～44、46、49、52、62～63 的删除/恢复路径有行为证据；本次产生的清理状态不会堵死自己的重试。

### T09：资源、品牌构建、整体验收与交接

**文件**：`SunSmart/en.lproj/Localizable.strings`、`SunSmart/zh-Hans.lproj/Localizable.strings`、`SunSmart.xcodeproj/project.pbxproj` 的必要 membership；本文执行记录。先保存并核对外部工程差异，不覆盖它。

- [x] 补齐所有新增双语文案及现有资源复用；检查长名称、键盘、弹层、计数、iPad 和不同屏幕。原 UI 的离线禁止删除文案、过期 8/16 和示例计数不带入实现。资源与静态检查已完成，真实布局/交互仍按第 7 节逐项待人工验收。
- [x] 先运行完整 `python3 scripts/check_scene_configuration.py --suite all`，再按第 5 节执行必要关联回归和代表构建；新增源文件/资源需覆盖五个正式品牌 membership，稳定后完成五品牌 Debug generic iOS 构建，不机械扩 Release。
- [x] 按第 6 节记录真实设备、云端和开关型号验收；未完成清楚标记，不用构建通过代替。
- [x] 更新第 7 节，给出实际代码版本、SDK 来源、已验证/未验证、偏差及下一步。未经用户授权不 commit/push/merge，也不生成重复的完成清单文件。

**完成条件**：DS-01～63 每条都有实施归属和验证状态；发布所需的外部验收缺口明确可见。

## 5. 自动化、构建与重点审查

### 5.1 最容易漏掉的五类失败

| 风险 | 必须证明的行为 | 负责任务 |
| --- | --- | --- |
| 同地址重新配网、切 Space、重加后的迟到回执 | 旧回执不能确认或删除新身份/新版本的配置 | T03、T08 |
| App 事务和 SDK 数据库之间中断 | 已提交意图不丢，不出现无法恢复的空记录或第二编号 | T01、T04、T05 |
| 合法空组与列表空但仍待清理 | 前者能直接预配置；后者必须清理后才能转换和释放 | T02、T04、T08 |
| 组/节点恢复、云端删除仍按组推导设备场景 | 固定直接成员和参数不被其他入口覆盖或扩大 | T02、T05、T08 |
| 参数发送/Store 部分失败及其他控制插入 | 不假报完成、不存错参数；重试以当前已提交期望收敛 | T03、T04、T07 |

### 5.2 测试执行约定

新增 `check_scene_configuration.py` 是本功能行为测试入口，不是替代现有测试的大框架；`--suite all` 必须包含已实现的 model/storage/targets/sync/save/roundtrip/selection/integration。未实现 suite 应明确失败，不能空跑通过。用例运行生产逻辑，输出失败断言与通过数量，临时文件按现有方式清理。

现有 `check_scene_topology.py`、`check_scene_deletion_flow.py`、同步 session 等脚本使用真实生产片段和边界替身；覆盖的是受控行为。若接口变化，更新夹具和装配，并保留原有行为断言。仅匹配源码文本的脚本可保留作补充，不能作为保存/恢复成功的主证据。

每项实施先观察预期失败，再跑通过；把具体失败原因和运行结果写入记录。一个实现轮次必要检查通过后停止重复运行，只有新改动或未覆盖风险才扩大验证。

### 5.3 需求用例与任务对照

这里记录覆盖归属，不表示测试通过。执行时按需求文档的具体前提、操作和结果逐条核对。

| 需求用例 | 主要负责任务 | 验证层次 |
| --- | --- | --- |
| DS-01～14 | T01、T02、T06 | 选择/权限/过滤行为＋界面；无误发命令检查 |
| DS-15～24 | T02、T03、T06 | 参数与消息行为＋界面＋真实灯控 |
| DS-25～36 | T03、T04、T06 | 保存阶段、失败/取消/重启＋实灯 |
| DS-37～44 | T02、T03、T04、T08 | 容量、身份、删除/重加行为＋实灯 |
| DS-45～46 | T01、T03、T07、T08 | 重载/调用/编号行为＋实灯 |
| DS-47～49 | T02、T07、T08 | 定时/引用行为＋具体开关实测 |
| DS-50 | T02、T07 | 场景编号/容量行为＋列表 |
| DS-51 | T01、T04、T06 | 旧组/模板回归＋实灯 |
| DS-52～54 | T01、T04、T05、T08 | 离线往返/旧数据＋真实云端及设备；旧版风险单列 |
| DS-55～56 | T04、T05、T07 | 权限/保护/紧急状态行为＋实灯 |
| DS-57～60 | T06、T07、T09 | 详情/组件回归＋布局/语言/品牌构建 |
| DS-61～63 | T02～T06、T08、T09 | 两种场景共同保存/恢复＋空组＋实灯/云端 |

### 5.4 构建

文档阶段不构建。后续执行 session 在一轮 Swift 代码改动及相关回归完成后，使用实际核对通过的 workspace：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028 CODE_SIGNING_ALLOWED=NO build
```

不得使用 Simulator、clean 或删除共享缓存来绕过问题。上述构建不连接真机，也不表示运行验收通过。

本次新增共享源码/资源存在 target membership 风险，稳定后应核对并构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的实际 scheme；不同 scheme 在同一 DerivedData 下串行执行。工程还有 HSmart 的既有 Scene/资源 membership，保留原归属，并核实其 scheme/依赖是否属于本次可构建范围；未验证明确记载，不擅自删掉或宣称它与正式五品牌相同。

## 6. 人工和外部验收的最短路径

用户默认负责真实设备和最终体验。执行 session 不因设备已连接就自动安装运行；需要自动真机验证时另按既有授权执行。

| 组合 | 操作与预期 | 对应用例 |
| --- | --- | --- |
| A/B 同组不同参数，X 同组未选，U 未分组，C Relay | 选择、搜索全选、批量与单台修改；参数层不控灯；预览/DONE/App Recall 只作用选中设备，Relay 正确 ON/OFF | 05～29、45 |
| 部分离线及全部已有成员离线 | DONE 显示已完成/失败/待同步；保存后退出、重启、恢复连接并设备同步；目标和参数不丢，不重复编号 | 33～36、61、63 |
| 清理失败、重加及退组 | 删除 A/B 关系不删组/设备；离线最后成员先待清理；重加最终恢复新值；换组后成员不变 | 37～44、62 |
| 定时及不同实体开关 | 新建定时/开关选择可见待同步；分别记录 App、代理/按键、虚拟面板对跨组及未分组设备的实际范围 | 47～49 |
| 新版分享给另一手机 editor | 完成/待写入/待清理各分享一次，进入 Space、重启、继续同步并上传读回；只读角色不能写；全部字段和任务保留 | 52、54、55、63 |
| 旧 App | 记录读取/修改/再上传造成的实际影响；按已接受风险说明，不报兼容通过 | 53 |
| 五品牌代表页面与语言 | 检查入口、主题、资源、英文/中文、长文案、列表计数及 iPad；构建与体验分开记录 | 57～60 |

实机失败时先记录型号/固件、App 分支与版本、在线状态、真实命令目标和关键回执，不用更改固件或服务器消除问题。现有命令不足、云端丢字段或特定开关范围不满足时，分别形成外部配合事项与发布限制，继续完成可独立实施的 App 工作。

## 7. 执行记录与会话交接

执行 session 持续更新本节及任务勾选，不重写已确认需求来迁就实现。状态统一使用：未开始、进行中、代码完成待验证、已验证、受阻；已验证必须写明验证层次。

| 任务 | 状态 | 实际改动／偏差 | 自动化及构建证据 | 实机／云端状态 | 下一步 |
| --- | --- | --- | --- | --- | --- |
| T01 | 已验证 | 配置值类型、独立草稿、SQLite 可空列与失败保护；增加 throwing 保存入口供 T04 事务复用 | RED：旧 metadata save 丢配置；模型骨架 11 条失败；SQLite 非 BLOB 损坏被误当缺字段。GREEN：model 14/14；storage 22 条实际断言通过 | 仅本地数据；云端/设备未验收 | 按授权停在 T02，T03 尚未开始 |
| T02 | 已验证 | 共用快照、直接成员/清理目标、容量及定时投影；保留旧组参数换算 | RED：8 条解析/定时、3 条容量/槽位、1 条定时设备收集、5 条组模式边界断言；GREEN：targets 28/28，五个关联回归入口退出 0 | 未执行 | 按授权停在 T02，T03 尚未开始 |
| T03 | 已验证 | 共用参数命令、归属回执、未分组/场景任务、分阶段 Store、组退组持久意图 | sync 与 Session/TaskBuilder/Lifecycle 回归通过；本轮五品牌 generic iOS 编译通过，范围见本节末 | 未执行 | 停止；后续 UI/完整恢复按 T06～T08 授权 |
| T04 | 已验证 | App 事务、编号保留、SDK 投影恢复、统一保存协调器及原 Edit 元数据入口 | save/storage 与数据库安全回归通过；最终共享逻辑 SunSmart 编译通过 | 未执行 | 停止；T05 待授权 |
| T05 | 已验证 | App 行导出、严格导入、场景比较、旧收据升级、云端身份清理及坏场景撤权保护 | 必要离线回归及 SunSmart generic iOS 通过；扩展回归的三项基线失败见下方 | 真机、云端、另一手机未执行 | 本轮停止；T06～T09 待授权 |
| T06 | 未开始 | — | 未执行 | 未执行 | 草稿选择及 UI |
| T07 | 未开始 | — | 未执行 | 未执行 | 调用与选择入口 |
| T08 | 未开始 | — | 未执行 | 未执行 | 清理及恢复 |
| T09 | 未开始 | — | 未执行 | 未执行 | 资源、构建及交接 |

每次更新附用例编号、实际结果、必要命令/证据和代码版本；DS-01～63 可按范围记录，但同一范围内存在失败或未执行时必须拆开。可另附日志/验收附件，不能另维护一份状态不同的完成清单。

执行结束在此补充：实际工作树/分支/HEAD、相关未提交差异、SDK revision/差异、已完成任务、未完成及受阻项、下一步。没有提交时如实记录未提交状态，不为了填写版本而自动提交。

可复制给执行 session 的任务说明：

> 在已确认实施范围内，先读取本工作树 AGENTS.md、`docs/261029_1625_device_scene_requirements.md` 和 `docs/261029_1922_device_scene_development_plan.md`。核对分支、未提交改动及 SDK 映射；保留已有工程文件差异。按 T01～T09 顺序，先编写并运行行为测试，再实施最小完整改动，优先复用已有组件和同步机制。每完成任务更新计划中的执行记录。只修改 App；不自动真机、提交、推送或部署。若发现会改变需求、兼容性或实施方向的问题，先记录证据及影响并等待确认；普通实现细节自行处理。未执行的实机/云端验收不得写通过。

### 2026-10-29 T01～T02 执行基线与接口核对

- 用户已确认本轮仅 T01～T02；单一写入负责人，不提交、不推送、不运行真机。按 executing-plans 执行，任务状态与裁定统一记录本节，替代技能默认额外 ledger/任务拆分文件；本轮不执行全分支收尾、合并或 T03～T09。
- App 分支 `feat/device-scene-261028`，HEAD `eba3d3d8ab57f9bbf941c81d89d175d15f25668e`。已有工程外部差异 21 行增/21 行删已在临时目录留存基线，两份需求/计划未提交。
- 实际 SDK 链接为指定 `one-dev`，HEAD `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，干净；本轮不修改 SDK。
- 接口预检：T01→T02 使用值类型、身份及损坏状态；T01→T04 保留 `loadAll` 的 App 行扫描/跨子网编号占用及 throwing 保存入口；T01→T05 共用严格 codec；T02→T03/T04 比较值排除 ACK/任务进度，目标保留原身份；T02→T06/T07/T08 分类不定义成员、待清理独立保留。未发现需要改变已确认需求的接口冲突。
- 复用裁定：直接沿用 `TimedSchedulerNodeIdentity`、`SceneCapacityPolicy` 和 `TimedSchedulerSlotPolicy`；不重建身份/容量/槽位框架。构建所需新增源文件 membership 随本轮加入，不等待 T09；保留原工程差异。
- 基线：`check_scene_topology.py`、`check_timed_device_slots.py`、`check_timed_slot_persistence.py`、`check_schedule_scene_target_export.py`、`check_scene_capacity.sh` 均退出 0。

### T01～T02 审查修正与当前验证

- 一次只读审查发现 3 个 Important：已有组离线草稿被误拦、旧组 `waitDelete` 丢容量/草稿清理上下文、整体删除组的重复清理目标因参数不同而冲突。均补生产逻辑失败用例后修复，未派第二轮审查。另补旧组亮度语义回归及 SQLite 类型损坏用例，均先失败再通过。无遗留 Minor。
- 草稿入口增补 `SceneDraft(scene:)`，捕获旧组关系地址和原配网身份的清理目标；后续编辑既有场景须使用该入口，不能仅传活动 `groupParameters` 重新拼草稿。`sourceGroupAddresses` / `sourceCleanupIdentities` 属于草稿原配置保护，不新增持久化副本。
- 组参数继续走 `SceneExecuteData.deviceTarget(for:)`；设备模式才采用逐设备亮度/色温修正。旧组原始 `SceneExecuteData`（包括其其他字段）未改写；T03 构造组消息时仍须保留其其他既有字段。此裁定避免旧组 trim 语义漂移，错误泛化会改变旧场景实际亮度。
- 删除目标统一无灯光参数语义，按身份去重；ACK/已完成任务不进入 `SceneTargetSnapshot.comparison`。旧组 `waitDelete` 与设备 pending remove 均保留容量。
- 本轮已验证：`check_scene_configuration.py --suite model` 14 个用例；`--suite storage` 22 条实际 SQLite 断言；`--suite targets` 28 个用例。storage 先前的 12 是场景分组数，现输出真实断言计数。
- 关联回归：`check_scene_capacity.sh`、`check_scene_topology.py`、`check_timed_device_slots.py`、`check_timed_slot_persistence.py`、`check_schedule_scene_target_export.py` 均退出 0。夹具更新只补新依赖/属性及装配，原断言保留；未用源码字符串判断业务通过。
- `--suite all` 会先运行已实现 model/storage/targets，再明确非零报告 sync/save/roundtrip/selection/integration 尚未实现；不能把本轮三个 suite 当完整功能测试。
- SunSmart 最终修正后 Debug generic iOS 构建退出 0（`-sdk iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`）；正式五品牌均已串行完成并退出 0。编译保留既有 weak capture/AppIntents 等警告，本轮不改无关代码。
- 工程核对：去除本轮两个新文件相关条目后，与修改前工程文件逐字一致；每个新增文件各有 6 个 source membership。正式五品牌均在 Podfile；HSmart 有 scheme 和源码 membership，但 Podfile 无对应依赖 target，未将其等同正式五品牌验收。
- 审查未判定的 T03～T08 命令/提交/云端/UI/真实删除链路均按已授权范围留待对应任务；性能及实机没有运行证据。以上不是推迟本轮缺陷，也不是产品发布通过。

### 进入 T03 前的接口约束

- 既有场景编辑使用 `SceneDraft(scene:)`，保留旧组待清理身份、组关系及原配置比较值；新建才用普通值初始化。草稿不序列化，不改 Node 实时值。
- `SceneTargetSnapshot` 提供实际目标、清理目标、无法解析目标与 `comparison`；发送前仍需按当前作用域/身份/能力重新解析。未解析的清理目标不能当成功释放；任务进度不能用于配置快照相等判断。
- `SceneCapacity.validateTopology(..., sceneSnapshot:)` 和 `nodesRequiringRead(..., sceneSnapshot:)` 供草稿使用；未分配编号时仅在内存预检用 0 代表额外一个占位，不能下发或持久化 0。正式编号仍由 T04 按 SDK＋App 行并集分配。
- `TimedSchedulerBindings.prepareTopology(..., sceneSnapshot:)` 保留既有槽位、将移除目标标记 pendingRemoval；`ScheduleServer.nodesRequiringSceneSchedulerRead(_:)` 只要求新增占用读取。旧页面仍待 T06 接入草稿与此入口，本轮不声称已有页面的离线保存交互完成。
- `SceneInfo.loadAll(meshUUID:subnetworkId:)` 的 nil 子网参数用于扫描同 Mesh 全部 App 行；`saveConfiguration` 是可加入 App savepoint 的 throwing 写入。SDK 投影/加载修复仍为 T04，外部载体/完整性比较仍为 T05，不能依赖 SDK Scene 列表发现未投影的 App 行。
- T03 必须保留组模式 SceneExecuteData 的其他字段、补 Relay ON 的命令行为、接入任务 revision/generation、迟到 Store/Delete 回执及未分组同步；本轮没有提前修改这些命令/回执路径。
- 生产 UI 尚无入口创建本功能配置，完整发布仍依赖 T03～T09；`all` suite 当前故意非零提示未完成部分。

### 当前工作树差异与构建记录

- 本轮新增生产文件：`SceneConfiguration.swift`、`SceneTargetResolver.swift`。修改 `SceneInfo`、SceneInfo 数据库读写、`SceneCapacity`、`Schedule.targets` / `existNodes`、`TimedSchedulerBindings` 和 `ScheduleServer` 的相应入口；没有 UI、命令发送、固件、服务器或依赖源改动。
- 新增 4 个 Scene 测试文件及 `check_scene_configuration.py`；复用并调整原 Scene topology / Timed SQLite 两个夹具和脚本。需求文档未修改；开发状态及交接仅更新本文。
- 工程原有 21 增/21 删外部重排完整保留，本轮额外增加 28 行（2 个文件引用、2 个组条目、12 个 build 引用、12 个 Sources 条目）。没有提交或推送。
- 2026-10-29：SunSmart 最终修正后构建退出 0；Archipelago 首次退出 0 但 quiet 输出包含矛盾的 SwiftCompile “exit code 0”诊断，改用完整输出做一次增量核实，退出 0 且明确 `BUILD SUCCEEDED`；SLG Sync Plus 退出 0 且明确 `BUILD SUCCEEDED`。没有 clean、缓存删除或代码绕过。SylSmart 退出 0 且明确 `BUILD SUCCEEDED`；Lumineux 退出 0 且明确 `BUILD SUCCEEDED`。正式五品牌本轮构建全部通过。

### 本轮最终交接（T01～T02 停止点）

- 工作目录 `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`；分支 `feat/device-scene-261028`；HEAD 保持 `eba3d3d8ab57f9bbf941c81d89d175d15f25668e`，本轮业务、测试、工程 membership 与本文均未提交；未推送。上文已列明相关差异，原外部工程重排完整保留。
- 构建入口 `SunSmartLocal.xcworkspace`；`.local-sdk/nordic-sig-mesh-sdk` 的 realpath 仍为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，无未提交差异。没有引用新 SDK API，也没有修改正式远端 release 依赖。
- 最终验证：model 14/14、targets 28/28、SQLite 22 条断言通过；五个关联回归脚本通过；`git diff --check`、工程 plist 格式、外部差异完整性检查通过。SunSmart / Archipelago / SLG Sync Plus / SylSmart / Lumineux 的 Debug generic iOS 构建均退出 0。
- 本轮无未解决的实施/构建阻塞。HSmart 未构建；没有 Simulator、安装或运行真机，没有云端往返、Mesh/固件/实体开关或真实 UI 验收。上述通过结果只代表本轮数据/投影基础，不代表完整场景功能可发布。
- T03～T09 均未开始；下一轮先按上文接口约束实现 T03 的共用命令、回执与同步入口，T04 再落实提交/投影中断恢复及编号保留，T05 再落实外部数据链。没有另建完成清单或修改需求/验收预期。

### 2026-10-30 T03～T04 执行基线

- 本轮授权仅 T03～T04；基线 HEAD `b867b9841870e53dc30bc21006b02f3dc5bdb4e0`，分支 `feat/device-scene-261028`，开始时工作树干净。T01～T02 已在当前代码中，不重复实施。
- `SunSmartLocal.xcworkspace` 映射到指定 `one-dev`，SDK revision `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，干净；不修改 SDK。
- 接口核对：消费 `SceneDraft(scene:)` / `SceneTargetSnapshot` / throwing `saveConfiguration`；组参数保留完整 `SceneExecuteData`；比较排除回执进度。T04 必须扫描 App 行并在事务内复核编号占用。
- Ruling: 沿用本文第 7 节作为唯一执行记录，不增加技能默认的重复 ledger；本轮只评审授权差异，不执行提交/分支收尾。需求及验收预期不变。

### T03～T04 实施与一次审查修正

- T03：新增 `SceneCommandBuilder` / `SceneMessageContext`。普通场景兼容工厂统一生成参数和 Store；参数以 `continuous = false` 防止旧批量入口跳过失败，生产 `SyncExecutionSession` 明确等待参数成功后才提交 Store。preview / beforeSave 只取参数，不发送编号 0、Store 或 Delete。
- 回执捕获 Mesh/Space、节点 UUID/主地址/配网指纹、配置 revision、操作 generation、期望参数及 comparison。`Node.applyMessageHandle` / Session 结果应用统一验证；显式配置的无上下文 Store/Delete 不再从实时灯态推导正式缓存。设备属性保存失败或 SceneInfo 保存失败保留待处理意图；成功清同步缓存。
- 设备/场景同步任务复用 Node 解析入口、现有步骤依赖及停止/重试通道；未分组 `getStandardNeedSync` 纳入 write。普通组退组仍清组场景，设备场景不随退组清除。显式组任务发送前持久保留 write/remove generation，重加后的旧 Delete 不可确认新 write。场景缓存已一致但 Scheduler 未恢复时仍生成关联任务。
- T04：新增 `SceneConfigurationStore`，在现有 `configurationTransaction` / `TimedSchedulerBindings.commit` 内提交 SceneInfo、组关系和槽位；throwing `saveConfiguration` 保留错误。App 未提交才 throw；App 已提交 SDK 保存失败返回 `.projectionPending(number:)`，同 revision 重试原行。分配在 App 事务内合并 SDK 数据库、内存 Mesh 和同 Mesh 全子网 App 行，待清理/isDeleting/待投影均占号。
- 加载在组、设备、SceneInfo 读入后、主线程交付结果前扫描 App 行修复 SDK 投影；切 Space 拒绝旧加载结果。缺失 SDK 的 isDeleting 行不重建为可执行 Scene。暂时投影失败返回加载失败，保留 App 行供下次进入重试，不创建会阻断自身恢复的永久配置保护标记。
- `SceneSaveCoordinator` 消费草稿快照，复用 `SyncExecutionSession.parameterOnlyOperations`，无独立队列。DONE 总是重新发送；只 beforeSave 当前报告允许 confirm。改 revision/原配置/组成员/能力后旧确认失效；取消不恢复灯态。确认后正式会话重新应用已提交参数再 Store。离线已有成员、合法空组及已有场景移除最后成员允许提交，新增未知容量仍受保护。
- 旧组参数继续由完整 `SceneExecuteData.deviceTarget(for:)` 取得，不把设备 trim 语义套入组。额外的 HSL/LC 字段保留，并以草稿及快照中的 auxiliary 比较值防止编辑期间被另一入口改动后静默覆盖；不新增持久字段或云字段。现有 Edit 名称/图标操作接入同一提交入口，没有新增页面。
- 一次独立只读审查发现四项：未分组标准 needSync 漏入口、explicit groups 退组清理、成功回执未清缓存、已有场景最后成员清空被拦。全部增加失败用例后修复；另外补齐 Scheduler-only 恢复、HSL/LC 原值变化及 Delete 能力消失空命令的失败用例。没有第二轮代理审查或扩大到 T05～T09。
- Ruling: 参数-only 适配放在 Session 的局部操作表，而不扩展通用 ActionType 枚举；沿用同一传输 lane、stop gate、结果及取消生命周期。代价是 T06 必须通过 coordinator 调用，不得绕过它自行拼确认状态。
- Ruling: 编号不足以 `Failure.noNumber` 返回、未知新增容量沿用已有容量异常；本轮不新增网络申请或 UI。T06 在既有地址申请/容量预读完成后重试同一 draft，仍必须由 Store 最终重新分配并检查；错误接入可能造成无法继续确认，但不会保存编号 0 或绕过新增容量保护。

### T03～T04 自动化证据与边界

- RED 已实际观察：Relay ON 误发 OFF；旧 Store 通过新 revision；未分组 write 列表及标准 needSync 漏项；Session 把参数和 Store 同批提交；合法空组提交缺实现；coordinator 无预览结果；explicit groups 退组缺清理/未持久替换 write；成功 Store 不清同步缓存；已有场景清空被拒；原 HSL 变化草稿仍覆盖；Delete 能力丢失被空命令判成功。各项已在生产逻辑用例中转 GREEN。
- model 14/14、targets 28/28、storage 22 条实际 SQLite 断言通过。sync suite 执行生产命令构造、上下文、Node 标准状态入口、场景任务构造和旧组转换；save suite 执行生产 Store/coordinator、实际 SQLite、生产 App transaction 与 Timed commit，覆盖失败/重开库/编号保留、离线修改、最后成员 pending remove 与槽位回滚。
- `check_sync_execution_session.py` 通过，新增生产 Session 参数-only 任务选择/结果不落库、参数失败不 Store、Store 失败、空 write/Delete 失败；保留原取消、重试、迟到回调等断言。`check_sync_task_builders.py`、`check_sync_run_lifecycle.py`、`check_scene_topology.py`、`check_timed_slot_persistence.py`、`check_timed_device_slots.py`、`check_scene_capacity.sh`、`check_schedule_scene_target_export.py`、`check_configuration_database_safety.sh` 已退出 0。
- 全量入口继续执行 model/storage/targets/sync/save，然后明确非零报告 `roundtrip, selection, integration (T05-T07)` 未实现。没有删除或降低既有断言。Timed 旧 Scene recovery 夹具保留其受控 reader 边界，新 sync suite 另执行真实 Node reader 与场景任务构造。
- 测试中的 BLE、SDK 对象及 GroupInfo/槽位表保存边界按既有夹具替代；GroupInfo 保存失败注入、实际 App savepoint 回滚和槽位内存/数据库回滚有证据，但不能等同真实 App 双数据库故障现场验收。Coordinator 流程测试使用受控 session；独立 Session suite 验证真实传输调度适配。
- 源码归属：新增三个 Swift 文件各 6 个 membership（五正式品牌及既有 HSmart）；移除新增三文件条目后工程与本轮 HEAD 原文逐字一致，未改旧 membership、依赖、资源或本地化。`plutil -lint` 和 `git diff --check` 通过。

### T03～T04 最终验证与用例边界（2026-10-30）

- 最后补充生产 Store 行为测试：移除已经无法解析的旧成员时，原实现丢失其清理身份，先观察失败再修复。清理集合现在合并旧快照 unresolved、原配置 deviceMembers 和 pendingOperations，随后扣除新目标；同地址新身份不能继承旧成员，旧身份保留 pending remove，不能因查不到 Node 就释放。
- 最终 `python3 scripts/check_scene_configuration.py --suite all`：model 14、storage 22、targets 28 全部通过，sync、save、coordinator 均 PASS；进程退出 1，唯一未完成项为 `roundtrip, selection, integration (T05-T07)`。这不是完整功能全绿。
- 本轮重新完成 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux 的 Debug generic iOS 构建，完整输出均有 `BUILD SUCCEEDED`、退出 0。Archipelago quiet 输出曾有矛盾的 exit code 0 诊断，改用完整输出核实通过。最后保留无法解析成员清理身份属于无品牌条件的共享逻辑修正，修正后再次完成 SunSmart 构建；其余四品牌复用本轮源码归属/依赖构建结果，未声称在最后一行共享逻辑修正后全部重编。
- 构建入口及参数沿用第 5.4 节；各品牌串行、共用本工作树稳定 DerivedData。HSmart 保留源码归属但未构建，Podfile 无相应 target。既有编译警告未作为本轮扩展范围；未运行 Release、Simulator 或真机。

| 用例 | 本轮自动化证据 | 尚未验收 |
| --- | --- | --- |
| DS-25～29、33～36 | 参数-only 预览/DONE、发送串行、重新发送与快照失效、参数/Store 失败、切 Space、恢复及原编号重试 | 按钮/弹窗/后台与真实灯控体验 |
| DS-30～32 | coordinator 取消不提交、不恢复灯态；草稿及旧确认隔离 | KEEP EDITING / DISCARD / ADJUST AGAIN 页面，T06 接入 |
| DS-39、41～43 | 离线/无法解析成员保留清理，重加迟到 Delete 拒绝，同地址新身份拒绝；实际任务不扩到未选 X | 真正删除设备与全部恢复入口 T08；实灯 |
| DS-40 | 已有最后成员移除可提交，仍有 pending remove；T01～T02 类型转换模型断言保留 | 类型切换 UI、永久删除后完整释放流程 |
| DS-51、61～63 | 完整旧组参数及 trim、合法空组、已有离线成员、共同事务与投影恢复；新增容量保护回归通过 | 各创建/编辑 UI 接入、分享/云端往返及实灯 |
| DS-55～56 | 新入口复用作用域、权限/配置保护和实际目标紧急限制；受控边界不能代替完整 Space 生命周期验收 | 新页面全部入口、退出/升级状态及实灯，后续按所属任务验证 |

### 本轮最终交接（T03～T04 停止点，替代上方历史交接）

- 工作目录 `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`；分支 `feat/device-scene-261028`；本轮基线和当前 HEAD 均为 `b867b9841870e53dc30bc21006b02f3dc5bdb4e0`。本轮三个新生产文件、共享同步/存储入口、测试脚本/夹具、工程 membership 和本文均为未提交差异；没有 commit/push，没有修改需求与确认过的验收预期。
- Workspace 为 `SunSmartLocal.xcworkspace`；SDK realpath `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，结束时仍干净。本轮没有新增 SDK API 或修改正式远端依赖，也没有修改固件/服务器。
- T03～T04 已完成本轮行为测试、关联回归与编译验证，无剩余实施阻塞；T05～T09 未开始且未授权。未自动安装运行设备；BLE/Mesh 真机、真实双数据库中断、云端和 UI 体验仍未验收。没有新 UI 或云端数据链提前接入。
- 进入 T05 前：以 **App SceneInfo 行** 为已提交意图源，导出/恢复不能仅枚举 SDK Scene；`.projectionPending(number:)` 代表 App 已提交，必须保留编号及恢复依据，不能转成“重新创建”。编号占用仍合并同 Mesh 全子网 App 行，包括 pending remove / isDeleting；内存容量预检的 0 不得进入持久化或下发。
- 后续编辑必须使用 `SceneDraft(scene:)`，保留 sourceName、完整组辅助参数比较值、原关系与清理身份；comparison 不含 ACK/任务进度。T05 导入/恢复不得清掉 pending revision/generation 或将无法解析的清理身份规范化为空；必须同时保护旧格式与损坏数据边界，按 T05 完整往返测试落实。
- 后续 T06 保存入口必须使用 `SceneSaveCoordinator`：preview / beforeSave 不提交或 Store，confirm 才进入 Store 的事务及正式重发参数→Store。保留 `.noNumber` / 容量错误供既有申请或读取流程处理；重试同一 draft，不能重造 revision 规避投影恢复。共享 session 的停止、回执身份校验及 throwing 保存失败语义不得旁路。
- 计划差异仅为复用实现选择和必要接入：Session 局部参数操作表代替新 ActionType；原 Edit 元数据入口提前统一提交，未新增界面；源码 membership 与本轮五品牌编译随新增文件完成，不代表 T09 完成。后续完整删除/编号释放仍由 T08 承接，不因本轮回执保护通过而宣称已完成。


### 2026-10-30 T05 执行基线与接口调整

- 本轮授权仅 T05；实际起点 `0073c267f6d84c0ad8d891dc836c771a6a6dd0aa`，分支 `feat/device-scene-261028`，开始时工作树干净。上方旧 HEAD、未提交描述及构建结果均为历史证据，未改写。T06～T09、UI、整体删除流程、commit/push、真机与真实 Space 操作均未执行。
- SDK 仍为 `.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，检查时无未提交差异。本轮不增加 SDK API。
- Ruling: 原 `encode(scenes: [Scene])` 改为 `SceneConfigurationStore.exportRecords(scope:scenes:)` 从当前 Space 的 App SceneInfo 行合并旧 SDK 元数据，再交给 `SceneConfigurationPayload.encode(records:)`；配置仍仅使用原严格 `SceneConfiguration` codec。SDK 投影缺失不能导致已提交编号、配置或 tombstone 遗失；错误使用 SDK 名称会覆盖已提交元数据。
- Ruling: 新完整性比较记录 `sceneComparisonVersion = 1`；新上传保留显式 `sceneConfigurations`（包括空数组），远端删字段不按空值通过。旧非空收据只能用同 Space、同网络身份、同时间戳且原比较字段一致的已保存完整快照补齐；旧比较结构与真正空的旧场景部分保留兼容，不放宽身份及权限。
- Ruling: 普通组参数保留完整 `scenesDatas`；比较只规范化 SDK 已有 HSL/LC 缺省规则，测试直接执行 SDK `SceneExecuteData` / `LightLCProperty` codec。损坏本地组场景参数新增加载失败标记并阻止覆盖保存/导出；这是防止恢复链把显式损坏变成空配置的必要一致性保护。
- Ruling: 云端确认移除沿既有删除 journal/savepoint 清除匹配完整原配网身份的 App 成员与任务，并在成功后刷新投影；只接入已证明的 cloudRemoval identity，不提前实施 T08 的普通设备删除或整体场景删除。云端完整属性快照比较升级至版本 3，成员/场景排序采用同一 codec 规范化。
- 测试先行证据：原生产比较将远端丢配置字段判为相等；原旧收据无法与新增比较字段相等；真实 SDK LC 空值→0 造成往返假冲突；本地损坏组参数原本可被保存为空；云端快照成员排序原本改变 hash。以上均实际运行观察到失败，再实施对应修复。新增 Store 接口测试先因接口尚缺失而编译失败，随后在真实 SQLite 上验证四类往返、重复导入及中途失败回滚。
- 本轮最终验证、审查修正及 T06 接口交接见下文；离线通过不等同真实云端、另一手机或设备验收。


### T05 审查修正与最终验证（2026-10-30 09:26 +08）

- 一次完成的独立只读审查确认两项 Important，均先补失败用例后修正：① 损坏 Scene/组参数与服务器撤权同时出现时，新增严格校验原本提前返回，阻断 visitor / `EditorPasswdChanged`；现在拒绝配置替换时仅应用和持久化权限收紧，普通 restore 的 live Space 与读回入口也保留撤权。② 旧 v2 节点移除快照缺精确备份时，新本地导出的空数组与旧 GET 缺字段发生假冲突；仅在确认为旧比较收据的干净本地 fallback 中规范化空扩展。新 POST 收据及非空配置不适用该兼容。两项原失败分别为 `invalid scene must not suppress authoritative revocation`、`legacySceneSchema … notOnlyNodeRemoval`。
- 保留原 Timed 校验顺序与全部既有断言；审查恢复选择的 `canDecodeConfigurationImport` 也使用同一场景预检。新旧基线识别先检查收据标记，现代收据不为升级检查反复读取完整快照/加载 Mesh。组场景损坏导出补齐现有诊断渠道，没有新增 UI。
- `python3 scripts/check_scene_configuration.py --suite roundtrip` 通过；最终 `--suite all` 的 model 14、storage 22、targets 28、sync、save、coordinator 和 roundtrip 全部通过，退出 1 仅报告 `selection, integration (T06-T07)` 未实现，未删除检查。
- `python3 scripts/check_space_recovery_receipts.py` 最终退出 0：真实生产读回与持久化收据拒绝删字段、改 revision/任务、旧快照升级、重复/失败恢复、editor/visitor、损坏组 LC 与密码失效同时出现；保留原权限、身份、Timed、Profile、节点移除、取消/重试断言。
- 必要关联回归退出 0：`check_schedule_scene_target_export.py`、`check_profile_persistence.py <SDK>`、`check_space_sync_cleanup.py`、`check_scheduler_cloud_roundtrip.py`、`check_proximity_scoped_import.py`、`check_hdb_persistence.py`、`check_lights_batch_deletion_context.py`、`check_space_protection_snapshot.py`、`check_space_membership_lifecycle.py`、`check_cloud_node_import.py`、`check_site_gateway_metadata_reload.py`、`check_configuration_database_safety.sh <SDK>`。保护快照仍为 5000 checks / 2 reads / 3 probes / main reads=0；数据库 suite 验证实际 SQLite WAL、保存点回滚及失败保护。
- `SpaceConfigurationIntegrityPolicyTests.swift` 与生产策略独立编译执行通过。其旧收据夹具显式去掉新增 marker/Scene 字段，使其确实代表历史格式；原双向匹配、Profile 差异及严格读回断言保留。CloudNode 预检夹具补合法空顶层 `scenes`；其它脚本仅补生产依赖/SDK codec 装配，没有用源码字符串判断本次行为通过。
- 扩展回归中保留三项 **起点 HEAD 已有失败**，不宣称全回归绿色：
  - `check_hdb_group_lifecycle.py`：既有样本解码缺 `index`；用 HEAD 生产策略与原测试重复失败。
  - `check_node_sync_status_refresh.py`：旧夹具未接 T03 的 Scene 配置、Node 身份及 resolver 依赖，原 HEAD 脚本也编译失败。
  - `check_path_topology_persistence.sh`：旧源码 contract 固定要求五品牌 10 次 membership，HEAD 工程含既有 HSmart 后为 12 次；使用 HEAD 文件复现同一断言。此前三个拓扑/生命周期/Trigger Zone 检查已通过，脚本在该断言停止；其后完整性业务测试单独执行通过，生产 scoped import 也单独通过。未修改这些失败断言或工程 membership。
- 本轮最终生产代码完成后，`SunSmartLocal.xcworkspace` / `SunSmart` / Debug / `-sdk iphoneos` / `-destination 'generic/platform=iOS'` / `CODE_SIGNING_ALLOWED=NO` 构建退出 0；DerivedData 固定为 `SunSmart-feat-device-scene-261028-cli`。仍有既有 weak capture/default 分支警告。此次没有新增生产文件 membership、资源、依赖或品牌编译条件，按共享逻辑规则只构建代表 SunSmart；没有复用上阶段构建冒充本轮结果，没有 Simulator、Release 或真机运行。

| 验收范围 | 本轮证据 | 仍待验收 |
| --- | --- | --- |
| DS-35、45、54 | 已提交四类意图、无 SDK 行、原编号恢复、重复导入、revision/generation 不重建，真实 SQLite 中途写失败回滚；生产收据重试 | 真实 App 双数据库中断与重启、灯端状态 |
| DS-43 | 离线/未分组/无法解析清理身份往返；同地址新配网身份不继承，确认云端移除只清原身份 | 真机重新配网及云端移除联调 |
| DS-52、55、63 的数据链 | 完整普通组 HSL/LC 原值及单位、设备期望参数、待写入/清理/isDeleting；损坏拒绝替换、只读限制及 editor 收据路径 | 另一手机分享/导入/editor 续传、只读页面、实灯；UI/整体删除仍属后续任务 |
| DS-53 | 本期未新增旧 App 版本门禁 | 旧 App 可能丢未知字段的已接受风险仍保留；不得报告兼容通过 |

### T05 最终交接与 T06 约束

- 工作树 `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`，分支 `feat/device-scene-261028`；起点及结束 HEAD 均为 `0073c267f6d84c0ad8d891dc836c771a6a6dd0aa`。本轮 App 导入/导出、Scene Store/codec、完整性/收据/权限、云端清理、GroupInfo 持久化保护及测试/脚本/本文全部未提交；未 commit/push，未修改历史验证证据。
- SDK realpath `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，结束核对仍干净；无新 SDK API、正式依赖变更或 SDK 发布依赖。未修改固件/后端/配置或部署。
- T05 到此停止。云端实际保存 `spaceData.sceneConfigurations`、真实 GET 不裁剪普通组参数、另一手机分享恢复均未执行；需外部团队/人工在测试 Space 逐类上传并读回，再由第二手机导入并继续同步。App 离线测试、构建与灯端成功分别验收。旧非空收据缺精确快照时继续保守进入既有人工恢复选择，不以当前导出伪造历史证据。
- T06 必须继续复用 `SceneDraft(scene:)` 和 `SceneSaveCoordinator`；预览/DONE 不提交，confirm 才提交正式参数→Store；`.projectionPending(number:)` 已提交且占号，保留原 number/revision/generation，不能重新创建。容量预检 0 不得导出、落库或下发。
- 后续任何外部数据入口通过 `exportRecords` / 严格 records/codec，不能改回只枚举 SDK Scene。普通组保留原 `SceneExecuteData`，不从 Node 当前灯态回填期望参数；不能因离线或解析失败丢清理身份。新上传的显式字段丢失仍是失败，旧收据兼容不得推广到新提交。
- T06 仅在后续授权后开始。设备普通删除、整体场景删除/编号最终释放仍由 T08 承接；本轮 cloudRemoval 的身份清理不代表上述流程完成。selection/integration 尚未实现，界面/权限/后台等最终体验仍须后续人工验收。


### 2026-10-30 串行子代理接管

- 接管基线 `3ced76c3`（T05 已提交）；分支 `feat/device-scene-261028`，接管时工作树干净。SDK 映射仍为指定 one-dev，revision `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，干净。已有 linked worktree 继续使用。
- 用户授权 T06→T07→T08→T09 串行实施，实施与独立审查均指定 Astra High；同一时刻一个写入者。每阶段审查及必要验证后主代理提交，不推送、不合并。主会话模型由客户端设置，子代理模型由派发参数明确指定。
- 本文是阶段状态与交接的唯一正式记录；临时 brief/report/diff 放入被忽略的 `.superpowers/sdd/261029_1922_device_scene_development_plan/`，不另建正式完成清单。
- T05 验证证据与既有三项失败沿用上节，不重复宣称全绿；T07 修改 Node sync 状态时必须补齐该夹具生产依赖并保留断言。T09 对既有 HDB/Path 检查判断本功能影响，不通过删断言掩盖失败。

| 接口/任务检查 | 结果及执行决定 |
| --- | --- |
| T06 自检 | 草稿选择行为测试与 UIKit 复用要求一致；selection 只证明行为，真实布局待人工。 |
| T07 自检 | Recall、列表与定时/开关状态同属调用链，integration 需运行实际生产逻辑。 |
| T08 自检 | 成员移除与整体删除分开，编号仅在全部清理成功后释放；未知身份保留。 |
| T09 自检 | 资源文案不能延迟到最后才可用；各阶段增量补齐，T09 总核对与五品牌构建。 |
| T06→T07 | Settings 使用草稿/coordinator，详情入口传既有场景；不以 Node 实时灯态填参数。 |
| T06→T08 | 分类移除仅改草稿，确认由 Store 生成清理；T08 接整体删除及最终释放。 |
| T06→T09 | 新文件归属/双语随 T06 实施；T09 验证全品牌，不另造 UI 组件。 |
| T07→T08 | Recall/状态需排除 isDeleting 可调用语义，删除持久意图沿同一 resolver。 |
| T07→T09 | 真实开关覆盖与 UI/云端验收分列，编译不替代实机。 |
| T08→T09 | 删除/恢复及编号释放行为回归并入最终验证，外部中断验收保留未验证。 |
| T04/T05→T06 | `.projectionPending` 已提交、保留编号/revision/generation；容量/编号申请后重试同一草稿，保留完整旧组参数与未知清理身份。 |

Ruling: 用户本轮串行实施及逐阶段 commit 授权覆盖本文旧阶段的暂停/禁提交描述；仍不授权 push、merge、真机或外部系统写入。task-brief 脚本不识别中文 T06 标题，因此按原文标题边界提取 brief，不更改任务要求。


### T06 实现与验证（2026-10-30）

- 基线 `3ced76c3`；实施者 `/root/t06_implement`，模型 Astra High。实现者已停止写入，主代理已派发独立同模型审查；未进入 T07，尚未提交。
- Custom 不再提前创建正式 Scene；Templates 保留原组参数生成，Preview/DONE 与现有组、设备编辑统一进入草稿编辑器和 `SceneSaveCoordinator`。组网格复用 `SceneMembersViewCell`；设备分类、搜索、计数/折叠复用名称过滤、主题、图标和现有参数控件。
- 新增 `SceneDraftSelection` 是无传输、无持久化的编辑所有权逻辑，供真实 UI 和行为测试共同使用；新增选择视图与设备参数行。仅当前 Space、有效身份、完成配网、在线且有 OnOff + Scene Setup 的新设备可选；已存离线成员保留、可移除/恢复，未知清理身份不丢。
- 当前筛选集合全选不改变隐藏选择；空分类显示 0/0。分类移除先确认本次数量及离线数量，仅改变已选成员草稿。Relay Cancel/Apply、调光/CCT 遮罩均只改草稿。OFF/加减/弹层关闭取消旧滑块所有权；保留旧组参数及未改动亮度的原始 Mesh 数值。
- 保存前读取真正新增占用的未知容量；最终缺号沿既有申请接口重试同一 draft/confirm。发送结果逐台列参数、成功/失败/离线；已存全离线和合法空组均按确认规则处理。后台/退出使旧确认与回调失效；`.projectionPending` 保持已提交编号和原 revision/generation，恢复原任务，不重新创建。
- Figma 结构化核对节点 `721:5068/6792/6893/5240/6760/5040`；产品确认覆盖旧离线删除文案。选择与设置共用视图、底部安全区操作栏、滚动结果弹窗为既有 UIKit 适配，真实布局仍待人工验收。三个新增生产文件加入全部 6 个既有 target Sources，新增文案双语同步。
- RED：selection 先因缺生产类型失败，随后空全选实现触发真实 `selectAllUsesFilteredEligibleSet` 断言失败；实现后 GREEN。最终 selection **17** 项、生产 DeviceNameFilterSession 通过；共享 slider/picker **99 checks**；编号申请生产回调 **7** 项；save/coordinator（含后台投影恢复、迟到正式完成、全离线与空组）、topology 通过。
- `--suite all` 已实现的 model 14/storage 22/targets 28/sync/save/roundtrip/selection 通过，仍 exit 1 明确报告 `integration (T07)` 未实施，不能写全绿。之后受收尾修改影响的 selection/save 等定向重跑通过；没有删除旧断言。picker theme 检查、项目/双语 plutil、差异检查通过。
- 最终生产代码于 **2026-10-30 09:58:28 +08** 完成 SunSmart Debug generic iOS 编译，`BUILD SUCCEEDED`，exit 0；入口 `SunSmartLocal.xcworkspace`，稳定 DerivedData `SunSmart-feat-device-scene-261028-cli`。首轮沙箱内 Xcode 路径不可访问，同命令经允许的沙箱外执行通过，未改业务代码绕过环境；后续仅对新增修改增量编译。
- SDK 仍是指定 one-dev `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673` 且干净；未改 SDK/依赖/固件/后端，未真实申请号段或操作 Space。没有 Simulator、真机安装/运行、真实云端/跨手机验收；其余品牌编译留 T09。
- 人工重点：DS-01～24/30～32/51/58～59/61～63，以及本阶段分类移除：长文案/iPad/键盘和结果滚动、多指滑块、离线编辑与重启续传、模板引导、真实 Identify/Store。T07 承接列表/详情/定时/开关；T08 承接整体删除与编号释放。

#### T06 独立审查与修复轮次 1

独立 Astra High 审查结论：规范有缺漏，质量需修复；无 Critical，三项 Important：① 号段请求被后台/关闭流程废弃后占用标记未复位，当前草稿无法再次申请；② 选择页把新建不得空保存的限制套到已有场景，取消最后成员后两处 DONE 均无法完成选择；③ 投影失败离开后重新打开 Settings 生成新 revision/generation，而非恢复原提交。已交回原实现者先补失败用例再修复，T06 未提交，T07 未开始。真实布局和设备/云端验收仍是待验收，不推断为代码缺陷，也不视为通过。

- 修复轮次 1：三项均先复现 RED，再修复。号段申请改为请求 UUID 所有权，废弃时释放，旧响应不能释放新请求；合法响应仍无号只提示，后续显式重试。新建/已有空选择分流。Store 新增 `editingDraft(for:)`，进入 Settings 和 Retry 先恢复已提交投影，成功后才创建编辑草稿，恢复不改变持久编号/revision/generation。
- 最终定向 GREEN：地址申请 **16** 条（提取生产 request/commit/lifecycle）；selection **21** 项＋既有 filter（含真实 selectDevices 入口策略）；save/coordinator 真实 SQLite（最后成员清理占用和销毁旧 coordinator 后恢复）；Swift parse/差异检查通过。最终 SunSmart generic iOS 于 **2026-10-30 10:14:53 +08** 编译退出 0。未重复不受本轮修改影响的其他 suite。原审查者复查中。

- 修复轮次 1 定向复查：三项 Important 均 ADDRESSED，规范符合、质量通过，无新阻塞项。T06 自动化/代表构建及代码审查完成；未执行的 UI/实灯/云端验收保持待验收。主代理将本阶段代码、测试、资源、工程与本文统一提交，提交后再派发 T07。

### T07 接管基线（2026-10-30）

T06 已提交 `3f252b5d`（`feat: unify scene draft editing and save flow (T06)`），提交后工作树干净。T07 以该提交为基线，使用新 Astra High 实现者，仍单一写入者；T08/T09 未启动。沿用 T06 `SceneConfigurationStore.editingDraft(for:)` 的投影恢复前置约束；列表/详情/元数据/调用相关入口按本任务实际影响核对。T05 记录的 Node sync 状态夹具缺少生产依赖是本阶段相关项，补齐装配并保留原断言。


### T07 实现与验证（2026-10-30）

- 实施者 `/root/t07_implement`（Astra High），基线 `3f252b5d`；已停止写入。设备场景列表改为按实际成员 Scene Model 单播 Recall，排除同组未选 X；组模式保留原默认无 ACK、无显式 transition/delay、allNodes 发送范围。调用仍使用原 `.control` 权限，不借保存权限阻断已有合法控制。
- 列表与 Node 回执两处回显共用逻辑：各设备只显示已确认存储值，pending 期望不写成实时灯态；单设备回执不更新其他成员。已删除/待投影/失效场景不可选，普通 pending 不禁调用或选择；未分组设备纳入紧急控制检查。
- 详情复用 T06 分类与设备行的只读模式，显示设备数、已保存参数、pending/待清理数量；不把分类当 Group 控制入口。Edit 先恢复投影，新增 `commitMetadata(draft:expectedRevision:)` 仅保存名称图标，不重建成员/参数/Scheduler slots/任务 generation。Settings 内容仍用 coordinator。
- 状态复用共享读取和取消/失效机制：`SceneGroupSyncSnapshot.needsAnySync` 合并组、直接设备、待清理；旧 `needsSync` 保留组含义。新定时 `schedule == nil` 也显示场景本身 pending；开关选择同样显示而不因 pending 禁选。T06 页面补在线/设备/分类/权限通知刷新。
- 自查发现完整 `Schedule.SyncDataRead` 的 `.scene` 分支仍只看组：新增真实 planner 用例先复现 B 被漏掉，再改为设备场景直接成员进入 `syncNodes`。修复位于本阶段定时完整调用链，不扩展删除流程。
- Figma 结构化读取 `721:8046/8125/8339`，复用既有圆形列表卡片、菜单、分类行及资源，不带入过期 8/16 上限。新增 5 个双语 Key；无新增生产文件、资源、SDK API、依赖或编译条件。
- RED/GREEN：integration 先因生产 Recall/反馈接口缺失失败后通过；元数据测试先复现重造 pending generation 后修正；完整 Scheduler planner 先漏直接成员后修正。`check_scene_configuration.py --suite integration` 与 **`--suite all` 均通过**，不是移除未实现检查。定时选择/列表、NodeSyncStatusRefresh、双语 plutil、差异检查通过。
- NodeSyncStatusRefresh 夹具补齐 Scene/resolver/身份依赖，接到实际 Settings 生命周期；保留历史首显/重进/隐藏/取消/失效断言，新增 A/B/U/X、待清理与完整 Scheduler planner。Scene picker 的新建时读取场景状态是本期需求变化，原 Devices/Groups 新建行为继续保留。T05 记录的该脚本基线失败现已解决；HDB index/Path membership 旧失败尚未扩大处理。
- SunSmart Debug generic iOS 首轮与最终增量构建均退出 0，`BUILD SUCCEEDED`；第二次因完整 planner 后续修复而运行，使用同一 SunSmartLocal 与固定 DerivedData。未运行其他品牌、Release、Simulator 或真机。SDK 仍为指定 one-dev `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，干净。

| 开关/调用入口 | 当前代码发送与订阅范围 | 尚待实测的边界 |
| --- | --- | --- |
| App 设备场景 | 直接成员 Scene Model 所在 Element 单播 | 跨组 A/B、未分组 U 的响应，X 不变；pending 可仍执行旧设备配置。 |
| App 组场景 | 原 allNodes `0xFFFF` | 保留原行为；实际响应取决于灯内场景编号。 |
| 普通 EnOcean default_4key/scenes_4key/scenes_2key | Scene Recall 默认 allNodes；default_2key 无 Scene 键，其余控制键保留 main/sub link | 代理、Mesh 可达和残留编号；待清理设备仍可能响应。 |
| CID 0x0A78、PID 0x2A01 电池 / 0x2A11 有电八键场景面板 | 前四 Scene 键用 linkGroupAddress；仅 bindGroups 节点的 Scene Model 订阅该 link 组 | 跨组需相应组在 bindGroups 中，U 不自动获得订阅；两型号分别验收。 |
| PID 0x2A02/0x2A12 八键亮度面板 | 前四键是 brightnessConfigurations，非 Scene Recall | 本期不转换为 Scene 键，不扩大其他键范围。 |
| 八键虚拟面板 | 对同一 linkGroupAddress 发送无 ACK Recall | 与对应开关相同订阅边界，App 列表成功不能替代。 |

上述为当前 App/SDK 代码事实及预期，未取得实体实测。本阶段未修改开关发布、订阅、绑定组或其它键配置。

- 后续接口：元数据用 editingDraft + commitMetadata；内容用 coordinator。T08 继续复用 pending cleanup/isDeleting 与 resolver，处理整体删除、真实设备删除和编号释放。T09 收拢全品牌与 DS 状态。
- DS-45～48、55～57 人工步骤：A/B/U/X 保存不同参数→调用核对 X 不变→制造 B pending/U 紧急→检查详情、重启、Edit 和权限→新旧定时及各类实体/虚拟开关分别触发；记录已绑定组外目标和待清理设备实际响应。小屏/iPad/长名称/中文及真正 Store/Recall、云端、换手机仍待验收。

#### T07 独立审查与修复轮次 1

独立 Astra High 审查结论为规范/质量需修复，无 Critical，2 项 Important：I-01 元数据保存改 revision/name，SceneMessageContext 与批次比较因此拒绝在途 Store/Delete，即使 operation generation 保持仍未保留任务身份；I-02 组回显只检查显式 pending，合法旧组/缓存不一致但无 pending 时仍可能将新期望写入 Group 汇总缓存。已交回原实现者补失败回归并修复，核对同一比较值的任务与编辑器使用方，保留真实配置变化的旧回执拒绝及编辑冲突检测。T07 未提交，T08/T09 未开始。

- 修复轮次 1：metadata 保存保留设备配置 revision，新增 `SceneTargetSnapshot.taskComparison` 仅在同步所有权比较中排除名称；编辑器仍使用完整 comparison 和源名称/图标冲突校验。`SpaceSyncTaskScope` 委托同一 captureConfigurations。真实内容变更仍生成新 UUID 并拒绝旧回执；补齐 projectionPending 的在途回执/批次屏障。
- 兼容决定：合法旧组 configuration=nil 的初始 revision 取已验证 Mesh UUID，首次 metadata 升格沿用；它不是单独任务身份，任务仍校验场景编号/Space/设备身份，批次还校验 Scene 实例。metadata 按场景编号保存，不走内容 commit 的 revision 查找；两旧组及后续新内容 UUID/重试的实际用例证明不混行。不新增版本字段，不允许显式配置退回兼容值。
- 组回显改为同时检查显式 pending 与生产 `isSynced(with:for:)`，保留 OFF、CCT trim、无 CCT 和空组规则；缓存缺失或不同则不覆盖 Group 汇总。
- 两项均先 RED。最终 `--suite all` 与 `check_sync_execution_session.py` 退出 0：包含真实 metadata/Store/Delete、名称图标交错、源冲突、真实参数与身份变更、双旧组隔离、SQLite 投影失败/恢复及组回显兼容；原断言保留。最后生产修改后 SunSmart generic iOS 于 **2026-10-30 11:05:37 +08** 构建退出 0。原审查者定向复查中，T07 未提交。

- 修复轮次 1 定向复查：I-01/I-02 均 ADDRESSED；新增 I-03：旧组 revision 归一化后，生产 `Node.applyMessageHandle` 仍以 revision=nil 判断旧 Delete 收尾，导致最后 ACK 后 Group.waitDelete/间接日程引用残留。metadata 升格后原 updateData 又会因显式配置提前返回，需一起解决。这是本轮兼容改动引起的既有关系收尾回归，不归为 T08 整体删除缺项。已交原实现者进入修复轮次 2，要求从真实 Delete handle→Node wrapper→关系收尾执行两成员/升格/投影恢复/错误回执用例；T07 未提交。

- 修复轮次 2 故障注入进一步证明共享事务入口缺口：SQLite 最终 RELEASE/提交失败后，Connection.savepoint 回滚到保存点但仍保留它；App `configurationTransaction` 外层 catch 未释放，`sqlite3_get_autocommit` 从 1 留为 0，后续所谓成功仅释放嵌套保存点，不能视作落盘。主代理确认将 App 侧最小修复纳入本轮必要一致性范围：只清理自己命名且已回滚的保存点，保留调用方外层事务，不修改 SDK；补连续失败/成功、重开库和嵌套事务证据，并运行已有数据库安全及相关消费者回归。不是新增事务框架或扩大固件/后端范围。

- 修复轮次 2 实现：按 groups/remove 上下文调用共用 `Node.completeGroupSceneRemoval(sceneId:)`，不再以 revision 是否存在判定 legacy。首 ACK 不提前清其他成员；组关系/间接日程仅在全组有确认依据且无剩余 pending 后保存。显式设备场景和正常组关系不误清；旧 context-free 分支复用同一方法。
- 组/Scene pending 使用 App 事务，节点缓存先内存暂存，GroupInfo 写失败则恢复并返回失败。SDK 缓存已持久清除而 App 最后提交失败时，持久 waitDelete 仍驱动原 Delete 通道重新确认和重试；组待同步读取同样保留，不以空缓存/未知寄存器假报完成。指定 SDK 代码支持 Delete status 0/2 且寄存器无该编号的幂等确认，未改协议或 SDK。
- 共享事务最终方案：优先 SDK `transaction`，使 BEGIN/body/COMMIT/失败 ROLLBACK 都在既有串行队列内。只有 body 未执行且 SQLite 明确报嵌套 BEGIN 错误才回退 savepoint；无队列外 autocommit 分支、不重放 body、不回滚调用方外层。共享 App 连接未发现手动 BEGIN 跨 run 维持外层的调用，独立只读候选连接不属于该约束。
- 新 App→SDK 嵌套保存锁序定向核对：SDK savePropertys 是单次 Mesh 写，delegate 在写前异步投递；已核对相关 App 双库/导入/读取路径，未见持有 Mesh 事务闭包再同步进入 App 的反向嵌套。该源码检查不代替真实并发压力验收。
- RED：真实 getDeleteMessageHandles→Node.applyMessageHandle 复现末 ACK 残留、GroupInfo 保存失败假成功、空节点缓存使 waitDelete 消失；真实 commitHook 复现最终提交后保存点残留。最终 GREEN：scene all、数据库安全（连续失败/成功/重开/嵌套/双线程）、timed_slot_persistence、profile_persistence、site_hdb_persistence、sync_execution_session、node_sync_status_refresh 均退出 0；保留历史断言。旧组/metadata 升格/显式组均验证 GroupInfo 写失败及 SDK 已清后 App 最终提交失败的重建任务/重试收敛。
- 最后生产修改后 SunSmart Debug generic iOS 于 **2026-10-30 11:42:15 +08** 构建退出 0；本轮仅一次最终代表构建。SDK 干净、未变更。未做真机/真实I/O故障/实际并发压力；T08整体删除与编号释放未开始。原审查者复查轮次 2 中。

- 修复轮次 2 独立复查：I-03 ADDRESSED，无新增 Critical/Important，规范符合、质量通过；已定向审计完整回执/失败重试、transaction fallback 和 App→Mesh 锁序。T07 完成，主代理按授权提交本阶段；真实 UI/设备/跨库 I/O 与并发压力仍待人工。

### T08 接管基线（2026-10-30）

T07 已提交 `17a40ff6`（`feat: integrate device scene recall and entry points (T07)`），提交后工作树干净。T08 使用新 Astra High 实现者，单一写入者；T09 未开始。必须保留已验证的 taskComparison/metadata 身份连续、旧组初始 revision、Group.waitDelete 原 Delete 通道重试与 App 事务失败收尾；SDK 仍为指定 one-dev ccdf101b95c6b475b0511f1d601ccbfd8ffe4673。

- T08 首个 RED：生产 SceneServer 在离线整体删除时先读寄存器，尚未持久删除意图即失败；本轮改为先保存 isDeleting/cleanup，再执行原同步机制。
- 恢复路径决策：明确 Restore 会改变设备 key，不能要求旧完整 identity 直接匹配新节点，也不能按地址/名称继承。允许在现有持久恢复记录机制增加隔离的 restore receipt，先核对 SDK 回调与落盘顺序；必须有明确 Restore 关联、同 UUID、作用域及 old/new 完整身份。普通删除 journal 和恢复凭据不得混用为永久删除依据。原 remove 不因新 key 自动算清理，优先迁移到已验证新身份并通过原 Delete/寄存器确认；未有足够恢复证据的旧记录继续保留，不猜测、不静默丢任务。具体结构与崩溃恢复证据尚由实现者核对，未改变 SDK/固件范围。

- 恢复凭据具体方案：沿用 `SpaceRecoveryState` 持久化独立 `sceneRestoreReceipts`，包含恢复 generation、完整旧身份及 prepared/verified/applied 状态；恢复回调核对已落盘的新身份后才 verified。重新进入仅自动重放 verified，迁移当前仍匹配旧身份的已提交意图，原 remove 仍为 remove。SDK 先落盘、App 回调前中断而只有 prepared 时，不猜新 key；Restore/Sync 入口提供人工确认，确认瞬间重验作用域、权限、旧任务及展示时的新身份，取消保留原任务。此补偿仅适用于明确 Restore 创建的凭据；普通重新添加不得自动继承。该方案不修改 SDK，真实恢复与故障窗口仍需人工验收。

- SDK 孤立删除记录的重试：普通加载仍不补建 `isDeleting` 的 SDK Scene；显式进入设备同步时，按 App 行为待清理记录建立仅供删除的投影，沿用原编号/revision/generation，禁用 Recall、Store 与编辑。pending 清空后统一收尾；局部投影失败保留任务供再次进入。
- 多 Element 边界：SDK Scene 的地址可以指向 secondary Element，需逐条解析所属 Node 后保留完整原身份；批次 Delete 回执须等同一设备全部目标完成，不能第一条 ACK 就消耗整台设备的任务 generation。自查用例复现并修正了 primary-only 残留遗漏。最终本地收尾同时复核定时/实体开关引用，避免导入或恢复路径绕过原引用保护。验证与独立审查尚未结束，本节不是完成声明。

### T08 实现与验证（2026-10-30）

- 整体删除冻结原身份及 `isDeleting/remove`，沿既有 SyncExecutionSession、Scheduler→SceneDelete 步骤和停止补偿执行。失败/离线不丢任务，重试不重生删除 generation。清完后先删 SDK 行，再 App 事务删关系/SceneInfo；App 提交失败保留 tombstone 与编号，下次继续收尾。
- `finishDeletion` 与页面共用按编号引用检查。加载/同步准备只延迟有已知引用的收尾，不阻止该页先解除引用；存储/身份异常仍报错。行为测试覆盖载入→清引用→释放连续路径。
- 永久删除 journal 新增可空原 key fingerprint，只有完整身份匹配才清场景意图；缺证明的旧 journal 保留。普通退组/换组不删设备场景或定时。T05 完整性删除投影已满足同一规则，未重复修改。
- 恢复使用前述 prepared/verified/applied 本地凭据及人工出口，双语补齐；六 target 既有共享本地化资源归属保留。SDK、正式依赖和工程配置未改。
- RED→GREEN：离线整体删除未先保存意图；旧场景仅 secondary Element 地址漏原目标；empty-pending tombstone 绕过引用保护。最终测试执行生产 Store/Server/Resolver/Builder、Node wrapper 与 SyncExecutionSession 结果分支，App 存储为隔离真实 SQLite；传输/UIKit仍是测试边界。
- 验证：`check_scene_configuration.py --suite all` 完整退出0；最后“有引用延迟收尾”差异重跑 deletion/save/roundtrip 均退出0。另 sync、topology、delete capability、permanent deletion、space recovery receipts、Restore EFC/transition time、双语plutil、diff检查通过。旧永久删除脚本补 T05 所需生产模型依赖；共享测试stub补Schedule.name，未删除原断言。
- 最终生产源码对应 SunSmart Debug generic iOS 于 **2026-10-30 12:23:54 +08** 构建退出0，后续未改生产代码。入口 SunSmartLocal、指定 one-dev `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673` 干净；DerivedData 使用本工作树稳定 `...-cli` 目录。沙箱内首次受限误报workspace无效，经映射核对后同命令沙箱外通过，未改环境配置。
- 未验收：真实多 Element ACK、Restore 实体/提示体验、离线回网与跨数据库中断、另一手机 editor 分享续传和服务器字段保留。未知旧删除身份仍需现场证据，不能假报完成。T09 未开始，独立 T08 审查中；不 commit/push 直到本阶段审查完成。

#### T08 独立审查与修复轮次 1

独立审查发现 1 项 Important（I-01），无 Critical/Minor：verified 恢复凭据后 App 迁移事务失败，或 App 已迁移但 applied 收据写失败时，重开 Restore/Sync 只查 prepared，未重放 verified；后一种还会保留旧内存 SceneInfo。根代理交原实现者修复两页面共用重入链，要求真实注入两种失败，验证重进恢复、内存/DB一致及 revision/generation 幂等。其他删除/编号/身份差异符合；本阶段尚未提交，T09未开始。

- I-01 修复：两页面共享 `SceneRestoreConfirmation.presentIfNeeded` 先重放 verified，再查 prepared；仍有无法安全处理的 verified 或持续失败时不能返回成功。App事务提交后先重挂SceneInfo/清缓存，再写applied文件，避免文件失败留下旧内存。
- 修复验证：生产共享入口上真实 App COMMIT失败、仅applied收据写失败 × write/remove 四组RED→GREEN；故障持续不放行，解除后收据/内存/DB一致，旧ACK拒绝，任务可建且重复重进不重生revision/generation。deletion/save/roundtrip退出0，最终SunSmart Debug generic iOS于 **2026-10-30 12:34:56 +08** 构建通过；SDK仍干净。原审查者定向复查中。

- 修复轮次1独立复查：I-01 **ADDRESSED**，无新增Critical/Important；T08规范与质量门禁通过。本阶段由主代理按授权提交，真机/UI/云端仍待验收。

### T09 接管基线（2026-10-30）

T08 已提交 `565a4c02`（`feat: preserve scene deletion and restore recovery (T08)`），提交后 App 工作树与指定 SDK 均干净。T09由新的Astra High实现者串行完成，主代理维护本文；重点五品牌与资源/双语归属、DS-01～63逐项证据及待人工验收边界。T08恢复重入、最终引用检查与仅供清理的SDK投影规则必须保留。

- Ruling: T09查明正式project的SDK声明在功能前基线`eba3d3d8`已为`git@github.com:maginawin/nordic-sig-mesh-sdk.git` + `release`（两项），与AGENTS描述的gitee不同；本任务保留既有声明，不擅自改绑。实际构建仍使用指定one-dev。若正式发布期望使用gitee或不同release，需另核对该远端包含本次所需revision；本地构建不能证明远端分支可复现。

### T09 实现与验证（2026-10-30）

- 仅生产差异是两语言`scene_no_search_results`值改为“没有匹配的结果 / No matching results”，同时适用于Groups/Devices。未改Swift、工程、SDK或依赖。低风险文案未形式化新增测试。
- 本轮完整scene all退出0；model14、storage22、targets28、selection21及sync/save/metadata/coordinator/roundtrip/integration通过。T08完整删除/恢复故障等验证按相同源码与SDK状态复用，all不包含的删除脚本没有冒称本轮执行。T06 slider/picker99检查与地址请求16检查按未变化源码复用。
- 工程/双语plutil、8新增Swift六target membership、43功能Key双语/占位符、47新增直接localized Key和20 Scene常量图片静态核对通过；Lumineux沿既有公共/品牌资源merge。实际五品牌产物的43 Key×两语言与源一致，20常量图名均在Assets.car。
- 五正式品牌均使用SunSmartLocal、Debug、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO及同一稳定DerivedData串行构建，全部exit0/BUILD SUCCEEDED：SunSmart资源增量（strings产物12:41:55）、Archipelago12:42:47、SLG Sync Plus12:43:23、SylSmart12:43:56、Lumineux12:48:19，均2026-10-30 +08。不做Release、Simulator或真机。
- HSmart源码/资源归属保留，现有Podfile Common仅配置正式五品牌，HSmart未构建。既有Lumineux Ruby全配置检查缺`xcodeproj` gem未运行到断言；本轮以结构、实际Debug构建及产物核对资源，未安装依赖，不报该脚本通过。
- HDB旧样本缺index、Path固定五品牌membership两个已证基线失败未重跑/未修，不删除断言；NodeSyncStatusRefresh历史依赖缺失已在T07修复，不能仍列为未修失败。
- 以下63项分别标明行为自动化、静态证据和未验UI/实灯/云端，不等同完整需求验收。最终真实UI、设备/Mesh/具体开关、云端及跨库I/O故障仍由人工验收；旧App字段丢失风险保留。SDK指定one-dev revision未变且干净。

### T09：DS-01～63 实施归属及验证状态

“自动通过”仅表示所列生产逻辑/边界夹具或实际 SQLite 行为通过；“静态核对”表示代码路径或资源结构，不能替代 UI。所有 UI、实灯、实体开关、服务器与另一手机均未运行。每条分别列出仍需验收部分，不将整条需求标为全部通过。

源码归属说明：以下 `Scene*` 模型在 `SunSmart/Main/Scene/Model/`；Controller/View 在相同 Scene 模块；`SpacePageSyncRead`、`SceneCapacity`、导入导出和身份清理在 `SunSmart/Common/Data/`。测试 suite 均指前述 `check_scene_configuration.py`，额外复用项明确写“复用”。

| 用例 | 具体实施归属 | 自动证据 / 静态核对 | 未验收或风险 |
| --- | --- | --- | --- |
| DS-01 | T01/T06：SceneAdd.makeDraft → SceneSettings + SceneDraftSelection；CREATE 不预建 SDK 场景 | model 的独立草稿/模式、selection、save 自动通过；创建入口静态核对 | 名称图标→选 5 台的完整 UI 未验 |
| DS-02 | T01/T04/T06：canFinishDeviceSelection、SceneSettings.doneAction、Store.commit | selection 新空设备选择两 DONE 拒绝、model/save 无非法空记录自动通过 | 提示及返回列表 UI 未验 |
| DS-03 | T01/T06/T08：SceneDraft.switchKind、Settings 切换确认、待清理锁 | model 模式互斥、selection 取消保留、targets 旧 cleanup 锁、复用 deletion 最后成员转换通过 | 提示取消/确认 UI 未验；保存非空不转换 |
| DS-04 | T06：SceneAdd.makeDraft、SceneAddCustomView、ImagesPicker | 静态核对 trim 空值、32 字符、isSceneTautonym、原图标入口；不声称边界 UI 已测 | 重名/超长/中文输入 UI 未验 |
| DS-05 | T01/T02/T06：SceneScope + 完整 identity、Selection、DevicesSelectionView.reload | model 身份去重、targets scopeMismatch、selection 选择/取消与隐藏保留通过；分类计数静态 | 实际多 Space 页面与数量 UI 未验 |
| DS-06 | T02/T06：SceneTargetResolver 与候选 canAdd 的 OnOff + SceneSetup + keybind | targets/sync 能力与目标处理通过；候选生产判定静态核对 | 具体型号、未知 composition/未配网显示与实灯未验 |
| DS-07 | T02/T04/T06：候选在线门槛、resolver 既有离线成员、coordinator 离线结果 | targets 禁新离线/保留旧成员、save/coordinator 同编号离线/全离线保存通过 | 实际断网掉线、UI、回网同步实灯未验 |
| DS-08 | T06/T09：groupFilter / SceneSettings.reload，复用无结果 Key 修正 | 生产 DeviceNameFilterSession 自动通过；Groups 过滤不改草稿及空结果静态核对 | 部分名/清空/无结果 UI 未验 |
| DS-09 | T06：SceneDraftSelection.filtered、DevicesSelectionView | selection 隐藏选择保留、重选原参数自动通过；总数由 draft.count 静态 | Panel 搜索实际分类与计数 UI 未验 |
| DS-10 | T06：DeviceNameFilterSession + Candidate.name/category | categorySearchUsesProductionFilter 和 filter 测试通过；大小写/trim 沿旧机制 | 分类名/设备名切换 UI 未验 |
| DS-11 | T02/T06：selectFiltered/setSelected 与 sourceConfiguration | selection 合格筛选全选、离线已有移除/恢复通过；save remove 意图通过 | 分类勾选状态和离线操作 UI 未验 |
| DS-12 | T06：selectFiltered、当前 rows、scene_select_filtered_hint | selectAllUsesFilteredEligibleSet / hiddenSelectionsAreRetained 自动通过；提示双语静态 | 折叠/出屏后搜索全选交互未验 |
| DS-13 | T06：DevicesSelectionView.collapsed、toggleAll；草稿独立于视图 | 折叠只改 Set/表刷新静态；selection 原选择和参数自动通过 | 重用、滚动、展开全部、离线色 UI 未验 |
| DS-14 | T06：Selection 无 transport；Cell 分离 Select/Settings/Identify；picker 回调仅草稿 | model/selection 草稿隔离通过；搜索/折叠/参数入口静态无 send/Store | 实灯无误发及 UI 触摸未验 |
| DS-15 | T02/T06：Candidate.defaults、SceneParameters.resolved、editingDraft | targets 能力/范围不改草稿、selection 重选保留及 storage 往返通过；默认 ON/100%/4500K 静态 | 弹层首次/重开/已存回显 UI 未验 |
| DS-16 | T02/T03/T06：Settings.editDevices Relay 分支、showCct；CommandBuilder | targets Relay/调光/CCT 字段限制、sync CTL/OnOff 命令通过；控件条件静态 | 三种实际控件与型号实灯未验 |
| DS-17 | T06：SceneExecuteDataPickerView 遮罩回调；Relay cancel/apply；Selection token | relayCancelDiscards / relayApplyCommitsDraftOnly / abandonedPopupCannotCommit 通过；关闭链静态 | 遮罩、页面放弃的真实触摸 UI 未验 |
| DS-18 | T02/T03/T06：picker.setLightnessValue/offBtnAction、resolved、parameterHandles | targets Relay ON 独立于亮度、sync OFF 命令通过；复用 picker 99 checks 的 OFF 接管；最大亮度静态 | OFF→ON 端点、Store/Recall 实灯未验 |
| DS-19 | T02/T06：Node 既有 lightnessRange/trim 换算/effectiveCctRange + resolved | targets parametersUseDeviceCapabilitiesWithoutChangingDraft、旧组 trim 行为通过；原始单位不变保存通过 | 真实范围变更/端点和实灯未验 |
| DS-20 | T02/T03/T06：已选 identity 批量 apply + resolver 单台 target | selection bulkEditOnlyChangesSelectedMembers、sync/integration 单播 A/B/U 排除 X 通过 | 同组 X 全程不变的实灯未验 |
| DS-21 | T02/T06：editDevices 混合能力窗口、逐 identity resolved | selection 批量只改已选及单台覆盖机制、targets 逐设备范围/Relay 通过 | 混合类型弹层、不同范围实灯未验 |
| DS-22 | T06：picker.cancelSliderGesture/cancel/dismiss、Selection parameterEdit token | 复用未变化 picker/slider 99 checks；selection 旧 slider callback/abandonedPopup 通过 | 多指/加减/OFF/关闭延迟的真实 UI 未验 |
| DS-23 | T06：Settings.identify → 既有 LightGroupControlCommandSender | 静态核对 node.state、Mesh、scope/identity/紧急和 vendor Identify/fallback；不修改草稿 | 没有本轮 Identify 专用运行测试；具体型号反馈/离线实灯未验 |
| DS-24 | T01/T06：独立 SceneDraft/Selection、参数弹层回调 | model draftCopyDoesNotMutateStoredValues、selection 只草稿、sync 参数-only 不 Store 通过 | 页面来回/设备主控实时态、实际灯光未验 |
| DS-25 | T03/T04/T06：coordinator.preview + Session.parameterOnlyOperations | coordinator preview 不落 App、无 Store、结果/失败仅草稿通过；结果窗静态 | Applying/结果 UI 与逐台实灯未验 |
| DS-26 | T04/T06：Settings.setBusy/startSend 与 coordinator.stop/generation | coordinator stop barrier/取消/旧轮隔离通过；busy 禁编辑/定位/DONE 静态 | 快速连续点击/进度归属 UI 未验 |
| DS-27 | T04/T06：draftChanged 取消旧确认，beforeSave 重新 snapshot | coordinator stale confirmation、revision/成员变化拒绝通过 | 修改后 DONE 重新发送实灯未验 |
| DS-28 | T04/T06：doneAction → SEND → received → confirm → Store.commit | coordinator 无 preview 也可 beforeSave/confirm，持久和正式任务自动通过；按钮链静态 | 完整点击路径/现场灯态确认与 Recall 未验 |
| DS-29 | T04/T06：preview 不创建 confirmation，DONE 总是 beforeSave | coordinator DONE resends after preview、仅一 App 行/同编号通过 | 实际再次发送与实灯恢复未验 |
| DS-30 | T06：showAlert cancel 无 handler；startSend 仅 confirm | CANCEL 不调用发送的静态核对；coordinator 取消不提交通过 | 弹窗 CANCEL 保持草稿 UI 未验 |
| DS-31 | T04/T06：ADJUST AGAIN → coordinator.cancel；下一轮 startSend | coordinator 取消/新 revision 重新确认通过；调整按钮不写库静态 | 调整再发 UI 和实灯未验 |
| DS-32 | T01/T04/T06：closeAction/leave/suspend 与 discard 双语 | coordinator discard 不回灯、不持久未提交配置、迟到正式完成隔离通过；KEEP EDITING 静态 | KEEP/DISCARD 对话框、后台/重启 UI 与已变化实灯未验 |
| DS-33 | T03/T04/T06：Session 结果、coordinator.Report、逐台结果窗与 pendingOperations | sync/save/coordinator 失败不 Store/保留任务与草稿、离线结果通过；失败列表静态 | 真实超时/回网续传、清单 UI、实灯未验 |
| DS-34 | T03/T04/T07：Store 事务/投影恢复 + isSelectable/pending snapshot | save 真实 SQLite 失败不假成功/同号重试；integration pending 可 Recall/定时/开关选择通过 | 真实 I/O/Store 失败及 pending 实灯不同版本未验 |
| DS-35 | T03/T04/T06/T08：lifecycle/generation、已提交 App 行、投影/recovery receipt | save/coordinator restart、cancel/stop、迟到完成、投影重入；复用 deletion 收据持续失败/恢复通过 | 真后台/杀进程/断网/跨库中断实灯未验 |
| DS-36 | T03/T04/T06：SceneMessageContext、snapshot comparison、validateAccess、正式先重发参数 | sync scope/身份/旧回执拒绝；coordinator stale/取消；生产 Session 参数依赖证据复用通过 | 真实其他控制插入、切 Space/权限时序与实灯未验 |
| DS-37 | T04/T06/T08：removeCategory 草稿确认 → commit remove；Delete 收尾 | selection categoryRemovalCancel/OnlySelected、save 最后成员 cleanup；复用 deletion 单台/整场景通过 | U 分类取消/移除 UI、设备确认后不响应实灯未验 |
| DS-38 | T04/T06：分类移除允许离线，数量/离线数双语；pending remove | selection 离线移除/分类限制、save 保留 cleanup 通过；无离线拒绝静态 | A/B/X 分类弹窗与离线实灯清理未验 |
| DS-39 | T01/T04/T08：sourceConfiguration 对照、完整旧身份 remove、清理保留容量 | selection 草稿取消；save pendingRemoval 原身份/编号及 SceneCapacity 预留通过 | 上线后实际 Delete/物理占用释放未验 |
| DS-40 | T01/T02/T08：draft mode lock、pending cleanup、永久删除身份清理 | model/targets 空组与真正空场景区别、cleanup 阻止转换；复用 deletion 最后离线成员/转换通过 | 两类空状态切换 UI 未验 |
| DS-41 | T03/T04/T08：未提交草稿隔离、重加生成 write、context 拒旧 Delete | selection 放弃/恢复、sync late Delete cannot remove readded member、save 原配置不变通过 | 真实先后 Delete/Store 与实灯未验 |
| DS-42 | T02/T05/T07：resolver 直接成员、topology/永久删除分离、Scheduler targets | targets deviceTargetsIgnoreGroupChanges/Timed group exit、integration 只 A/B/U；复用 topology/permanent 通过 | 换/退组后分类 UI、执行/同步/定时实灯未验 |
| DS-43 | T01/T02/T05/T08：完整 provisioning identity、永久删除 fingerprint、Restore 独立凭据 | model/targets reusedAddress 拒继承；roundtrip identity 保护；复用 deletion 普通重配网/显式 Restore 分离通过 | 真实重新配网/设备 key 变化及恢复流程未验 |
| DS-44 | T02/T04：SceneCapacity + TimedSchedulerBindings 新占用预读/同号编辑 | targets unknown 不当空、pending 第16槽不释放、同号离线无需预读；save 原子失败通过 | 真实寄存器读取/容量满/超时重试实灯未验 |
| DS-45 | T01/T03/T07：App persistence、CommandBuilder.recallHandles/applyRecallFeedback | storage/save 重载；integration 独立单播值、X 不变、pending 不伪装实时状态通过 | 真重启/灯端 Recall 与 UI 回显未验 |
| DS-46 | T01/T03/T07/T08：独立 number、App tombstone 预留、pending 可调用 | save 编号预留/投影；integration pending 可选；复用 deletion 未清理/引用不释放通过 | 不同场景相互独立与旧灯残留响应实灯未验 |
| DS-47 | T02/T07/T08：TimedSchedulerBindings、Scheduler.existNodes/SyncDataRead、Scene picker | targets 直接+cleanup 定时投影/容量；integration pending 场景可选；复用 NodeSyncStatusRefresh 完整 planner 通过 | 真定时执行及 pending 新旧状态实灯未验 |
| DS-48 | T07：SwitchSelectScenePage/ViewController 与已有绑定/发送机制 | integration pending 可选且只读不写；不同开关发布/订阅范围为 T07 静态证据 | **实灯未验**；0x2A01/0x2A11 与虚拟面板按 linkGroupAddress，未分组 U 不自动获订阅，不承诺任意跨组 |
| DS-49 | T08：SceneServer 引用保护、beginDeletion/finishDeletion、Scheduler→Delete | 复用 deletion 定时/开关引用、末端复核、离线/超时/重启编号保留、SDK→App 失败收尾通过 | 解除真实引用/实灯清理和重试未验 |
| DS-50 | T02/T04/T07：SceneCapacity 逐目标、nextAvailableNumber、Scenes 列表计数 | targets 容量、save 编号预留通过；静态无 Space 固定16与 8/16 显示 | 第17场景完整创建和计数 UI 未验；未称存在专门第17端到端测试 |
| DS-51 | T01/T02/T04/T06/T07：nil配置旧组兼容、template.makeDraft、共同 coordinator | targets 旧组 trim；roundtrip-group 原始字段；save 旧组完整参数/metadata/末ACK收尾；integration 旧组回显通过 | 自定义/模板整体 UI、旧灯预览/Store/Recall 未验 |
| DS-52 | T01/T04/T05/T08：ExportData/ImportData、App config payload、editor 恢复/pending | roundtrip/storage 丢字段拒绝、待写入/清理/tombstone 往返与幂等通过；权限入口静态 | **云端/另一手机/实灯未验**；离线 roundtrip 不能证明服务器保留字段 |
| DS-53 | 已确认兼容边界：本期不增加旧客户端技术拦截 | **已接受风险**，无“旧版兼容通过”结论；未改版本保护 | 旧版访问/上传可能丢新增字段；真实读取/编辑/上传影响未验 |
| DS-54 | T01/T04/T05：旧 nil 字段→groups、严格配置 decode、既有云同步机制 | model/storage 旧数据兼容/损坏不当空；roundtrip 严格 identity/metadata 与任务重载通过 | 真实云上传失败/重试/服务端读回未验；灯成功不等于云成功 |
| DS-55 | T04/T05/T07：validateAccess、Space protection、control vs configure、退出检查 | save/coordinator 权限/当前 scope；integration 仅control可 Recall、撤销control拒绝、只读开关选择不改通过；保护各入口静态 | 访客/升级/保护/退出各页面真实 UI 未验 |
| DS-56 | T03/T04/T07：coordinator 与 CommandBuilder 按 target.node 的 emergency 判断 | integration 未分组紧急 Recall 拒绝通过；最终修复新增生产Session首次发送、参数ACK→Store、Store结果及真实Restore适配器的紧急变化行为测试通过 | 真实紧急状态/解除后发送与灯控未验 |
| DS-57 | T06/T07：SceneView 只读复用 DevicesSelectionView；commitMetadata；Settings.editingDraft | save metadata 不重建成员/任务、在途回执连续性；integration 持久参数通过；详情菜单静态 | 长名称中文/详情计数/Edit/Delete/Settings UI 未验 |
| DS-58 | T06/T09：多行名称/摘要、自动行高、keyboardLayoutGuide、结果 UIScrollView、既有 SRAlert/picker | **仅静态核对**：列表跟键盘布局、结果可滚动、按钮独立命中；iPad grid 依容器宽度 | **UI 全未验**：小屏/iPad/长英文中文/键盘/横屏/相邻图标；分类 header 固定60与旧 picker 屏幕尺寸适配需人工观察 |
| DS-59 | T06/T07：复用 DeviceNameFilterSession/SceneExecuteDataPickerView；定时/开关选择入口 | 复用 slider/picker 99 checks/theme；本轮 filter/selection/integration 通过；T07 状态/定时 planner 证据复用 | 共享设备主控/组/定时页面真实触摸与灯控未验 |
| DS-60 | T06/T09：8新增源码、既有资源/43双语Key、五品牌同入口 | 六target membership/Key/图片静态通过；五品牌构建见上方T09最终构建记录 | 各品牌主题/入口/代表设备 UI 与实灯未验；HSmart 未构建 |
| DS-61 | T02/T04/T06/T08：组 resolver、共同 coordinator、旧组关系收尾 | targets existingOfflineGroupDraft；save/coordinator 全离线同号期望/待清理；生产末ACK旧组收尾通过 | 真实组全离线/无Mesh后续同步 UI/实灯未验 |
| DS-62 | T01/T02/T04/T06：hasConfiguredMembers vs targets、空组直接 commit、switchKind 锁 | targets emptyGroupIsConfiguredButTrulyEmptySceneIsNot；coordinator empty report 无虚构发送；model/cleanup 锁通过 | 自定义/模板空组、空场景/待清理提示 UI 未验 |
| DS-63 | T01～T08：共同 Store/coordinator、独立成员解析、往返/恢复与清理 | all 的两模式保存/取消/部分失败/重启/roundtrip；复用 T08 删除与 verified 重入故障通过 | 两模式完整 UI、真实 I/O/实灯/云端分享editor续传未验；不报告整链验收完成 |


### T09 阶段审查与最终功能审查

T09独立审查规范符合、质量Approved，无Critical/Important。新增中性搜索文案同时适用两个入口；六target双语资源、63项矩阵与五个iPhoneOS产物已定向核对。既有构建warning被列为Minor观察，非本阶段新增，保留在最终审查视野。测试/构建结果沿用实现者本轮执行证据，审查者未重复运行。最终整个功能审查覆盖pre-feature `eba3d3d8`至当前T01～T09差异；通过后T09统一提交。

#### 最终功能审查：统一修复清单

整个T01～T09审查确认0 Critical、3 Important、1 Minor，尚不能作为代码完成交付：I1正式同步计划失效未向编辑页通知终态，页面持续busy；I2共同写权限未完整消费密码待验证/恢复authority及运行中角色失效；I3正式保存和普通Sync的参数→Store链缺少实际目标紧急状态复核；M1同步预处理已完成删除后，旧详情页再次删除误报失败。根代理将四项交同一Astra High实现者统一修复，要求先复现、共用执行边界、保留已提交编号/任务和停止补偿，再做一次定向复查。不扩SDK/固件/后端，不改变已接受旧版风险。

最终审查未判断的真实UI/设备/Mesh/具体开关/云端/整体性能、HSmart及Ruby脚本/既有夹具/远端SDK发布问题均沿用前述边界，不作通过结论。I3是已确认App门禁缺失，不能借未实测而放行。

#### 最终统一修复与验证（2026-10-30）

- I1：正式保存接入计划失效终态，与正常结束共用本轮generation的一次交付；在原stop/补偿完成后通知“已保存，待同步”，现有页面解除busy并退出。已提交草稿再发送或换revision确认均拒绝，原编号、唯一App行及pending不变；离开后旧回调无效。
- I2：共同写权限同时核对持久Space及当前Space的canEditing/sceneOperates、密码待验证、临时编辑禁用/OTA和recovery authority。首次发送、后续批次和结果应用均复核。合法owner/editor、只有pending和既有允许Recall保留；权限恢复后同号续传。
- I3：实际Scene写目标的EFC检查进入命令生成、共享context和Session发送/结果边界；参数ACK后不再错误入队Store，未完成意图保留。纯remove仅受写授权限制，不误套灯控限制。
- 关联真实Restore旁路：仅deferred的Scene configuration/delete任务改用单任务既有Session，其余恢复原样。stop/补偿完成、lane释放后才推进旧队列，Stop取消后续、Dismiss使旧回调失效。校验非main安全拒绝，不用底层main.sync掩盖线程归属；Scene真实消费者在main处理，避免后台currentSpace回退DB丢临时标志。没有生产调用的旧执行入口未扩改。
- M1：App删除提交成功后保存仅本进程的作用域/编号/删除revision完成证明；旧详情再次请求须同一操作且SDK内存/SDK持久/App均无同号记录才成功。任意不存在、不同作用域或复用编号不算完成，最终删除前重新核对持久配置。
- 四项均有实际RED→GREEN。新增生产Coordinator+Session组合验证失效→stop/补偿→单次终态；真实SpaceData.update/坏配置/EditorPasswdChanged/authority落盘→Scene共同校验；生产Session初次发送、参数ACK→Store、Store结果处的权限/EFC变化；真实Restore适配器取消/退出/迟到回调；真实SQLite失败→预处理→旧详情结束与编号复用反例。无VC暂不能迁移时保留verified及可读投影，重新进入恢复write/remove通过。
- 本轮scene all退出0；最终线程/Restore变化后重跑save、sync execution session、deletion flow、space recovery receipts、Restore transition/EFC检查通过；topology与sync task builders通过。Session旧夹具缺T07 SceneDelete/context.number仅补类型装配，原断言保留。
- 最终SunSmart Debug generic iOS构建于 **2026-10-30 13:23:39 +08** 退出0，BUILD SUCCEEDED；之后未改生产代码。六个既有Swift文件变化，无新增源/资源/membership/品牌编译分叉/SDK API，五品牌不变资源配置证据复用；**另外四品牌未在本轮共享Swift修正后重编**。SDK指定one-dev仍干净；未执行真机/Simulator/云端操作。
- 原最终审查者正在对本轮差异定向复查。真实UI终态提示、BLE/EFC物理行为、Restore实际取消/恢复、各开关及云端/另一手机仍待人工；自动测试和generic构建不替代这些结论。

### 最终交付与下一步（2026-10-30）

**代码可交付进入人工验收。** 原最终审查者定向复查 I1/I2/I3/M1 全部ADDRESSED，无新增Critical/Important；本轮没有搁置的已确认代码阻断项。此结论不等于真实UI、设备或服务器验收已完成。原始阶段记录保留为历史证据，本节与上方63项矩阵为最终口径。

| 阶段 | 提交/状态 |
| --- | --- |
| T01～T02 | `b867b984`（此前用户已提交） |
| T03～T04 | `0073c267`（此前用户已提交） |
| T05 | `3ced76c3`（此前用户已提交） |
| T06 | `3f252b5d` |
| T07 | `17a40ff6` |
| T08 | `565a4c02` |
| T09 | 本节与最终统一修复随T09提交保存；准确HEAD以当前分支`git log -1`及交付消息为准 |

- 保留分支 `feat/device-scene-261028` 及当前工作树；仅本地commit，不push/merge。SDK仍为指定one-dev `ccdf101b95c6b475b0511f1d601ccbfd8ffe4673`，没有SDK未提交差异、新增API或固件/后端变更。正式依赖既有github/release与规则gitee预期差异已记录，发布前仍需核对远端可复现性。
- 自动化/构建结论见T09及最终统一修复记录：五品牌资源阶段构建成功；最后六个共享Swift修正后SunSmart复编成功，其他四品牌本轮未重编。完整scene all与必要补充故障回归通过；既有warning、HDB/Path夹具、Ruby缺gem与HSmart边界没有被改写为通过。
- 人工最短路径继续按第6节。优先同组A/B不同参数、未选X、未分组U及Relay；再测两类场景已有成员全离线保存/重启/续传、最后成员清理与换组、定时/各开关、三种状态分享给另一手机editor。
- 最终修复增加四项必验：正式保存中配置失效后解除busy并显示待同步，重进无第二编号；密码/权限撤销后停止写入，重新授权同号续传；EFC变化后不继续普通参数/Store，解除后恢复；Restore的Stop/Dismiss不继续后续Scene任务，迟到回执不更新已退出页面。SDK删除后App保存失败的恢复完成应正常退出，不再误报删除失败。
- 未执行真实UIKit、BLE/Mesh、多Element、云端/另一手机、实体开关及整体性能验收；旧客户端可能丢新字段仍是已接受风险。不存在“本轮已验证可发布”的结论。无需新增实施计划或独立完成清单：后续人工结果继续补在本文相应用例处。
