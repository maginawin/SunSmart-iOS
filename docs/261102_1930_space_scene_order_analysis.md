# Space 场景排序分析、修复方案与实施结果

更新：2026-11-02 20:08。用户已确认方案及兼容取舍，App 实现、相关自动化回归和 SunSmart generic iOS 编译已完成；真实 UI 与云端透传待人工验收。第 1～5 节保留修改前分析，第 6～9 节为已确认方案，第 10 节记录交付结果。

修改前实现存在足以解释测试反馈的排序不一致：创建时按内存追加顺序展示，重新进入 Space 后按数据库返回顺序展示，云端导出/导入又按内部场景编号重建，没有贯穿这些路径的展示顺序字段或统一排序规则。此次已补齐独立持久化顺序与相关入口。

删除后复用编号、改名后复用默认名称，会让“名称里的数字”“内部场景编号”“创建先后”不再一致。本机等价 SQLite 夹具已复现创建时显示 `Scene 1、Scene 2`，重新加载后显示 `Scene 2、Scene 1`。尚无现场数据与日志，不能确定本次反馈实际经过本地重载还是云端恢复；没有进行真机验收。

## 1. 修改前的规则

| 环节 | 当前行为 | 对位置的影响 |
| --- | --- | --- |
| Space 场景列表 | `ScenesViewController.visibleScenes` 直接取 `MeshNetworkManager.instance.scenes`，仅过滤消防保留场景；没有 `sorted`，排序按钮隐藏 | 完全依赖底层数组顺序 |
| 列表文字 | `ScenesViewCell` 显示 `scene.name` | `Scene 1` 中的 1 是名称的一部分，并非列表位置序号 |
| 默认名称 | `getNextSceneName` 从 1 起选择首个未被当前场景名称占用的 `Scene n`（中文为“场景 n”） | 删除或改名后会复用空出的名称数字；不与内部编号绑定 |
| 内部场景编号 | `nextAvailableNumber` 综合 SDK 已存编号、App 场景记录及内存编号，在已分配范围内选择最小可用普通编号 | 完整删除后可复用较小编号；待清理/未完成删除的 App 记录仍占用编号 |
| 创建 | `SceneConfigurationStore.project` 对新场景调用 SDK `network.add(scene:)`，SDK 执行 `scenes.append(scene)` | 新场景放在当前内存列表末尾，即使复用的编号更小 |
| 改名 | `commitMetadata` 保持原 `number`，更新名称并保存现有 Scene | 不直接调整当前内存位置；名称数字可以与内部编号脱离 |
| 完整删除 | `finishDeletion` 完成必要清理后移除 Scene 及 App 记录 | 保留其余场景相对位置，允许后续复用已释放的编号 |
| 本地重新加载 | SDK `Scene.load` 查询 `scenes` 表，没有指定 `ORDER BY` | 没有稳定顺序保证；本机夹具使用唯一索引，返回内部编号升序 |
| 云端导出/导入 | `exportRecords`、`SceneConfigurationPayload.metadata` 明确按 `number` 升序；导入按收到的 `sceneDicts` 顺序逐个添加 | 当前 App 导出的数据再导入时，按内部编号重建，原追加顺序不保留 |

内部编号是场景身份，用于设备命令、日程和按键引用；不是展示位置。当前代码没有因改名或重载而重编号的步骤。本问题能导致位置变化，不能据此认定场景配置或引用发生串位。

## 2. 为什么重新进入后才出现

创建、改名、删除期间，页面刷新仍取同一个内存数组，所以看起来保持操作后的顺序。

重新创建 Space 页面时，`SpaceViewController.setNetworkConnected` 调用 SDK `setMeshNetworkConnected`，进而创建新的 `MeshNetworkManager`，从数据库重新读取 `network.scenes`。并非只要回到 Scene 标签就一定重载；退出 Space 再进入、重新启动后进入、部分配置重新加载路径才会触发这一数据重建。

SDK 的 `scenes` 表存在 `(meshUUID, number)` 唯一索引，但加载查询不指定排序。本机 SQLite 3.53.3 的等价查询计划为 `SEARCH scenes USING INDEX sqlite_autoindex_scenes_1 (meshUUID=?)`，实际返回内部编号升序。不能把这次返回结果当成 SDK 明确承诺的排序规则。

随后 `loadExtensionData` / `restoreSceneProjections` 恢复扩展配置，对已经存在的 Scene 更新名称与配置，不恢复创建先后。若有缺失的 SDK 投影，恢复会按 App 记录处理并追加，仍没有统一展示顺序。

此外，SDK `Scene.save` 使用 `INSERT OR REPLACE`，未保存原表行 `id`。因此数据库自增行号也不能直接当作可靠的创建顺序字段；普通保存就可能换行号。改名单独是否导致重载换位取决于数据库返回顺序，不能断言每次改名都会换位。本次控制夹具中，仅改名没有换位。

云端导出本身不直接改动当前内存数组；后续真正执行导入/恢复重建时，才会把导出的编号顺序带回列表。本地重载已足以触发问题，不要求先发生云端同步。

## 3. 与反馈吻合的最小复现

前提：测试 Space 无其他普通场景，编号 1、2 可分配；使用空场景，或确保删除已经真正完成且没有日程/按键引用。

| 步骤 | 当前列表（名称 / 内部编号） |
| --- | --- |
| 创建两个默认场景 | `Scene 1 / 1`，`Scene 2 / 2` |
| 删除第一个场景 | `Scene 2 / 2` |
| 将剩余场景改名为 `Scene 1` | `Scene 1 / 2` |
| 再创建一个默认场景 | `Scene 1 / 2`，`Scene 2 / 1` |
| 从数据库重载，或把当前 App 导出数据重新导入 | 夹具结果为 `Scene 2 / 1`，`Scene 1 / 2` |

最后创建时名称数字确实为 1、2；新场景复用的是内部编号 1，重载后却排到前面。两个场景的名称和内部编号都没有被重载修改，变化的是数组顺序。

实际人工验证最短路径：按上述步骤操作，记录最后创建后的列表，退回 Space 列表再进入该 Space，检查是否反转。现场编号不一定从 1 开始，关键条件是“新建场景复用了比现存场景小的编号”。

## 4. 影响与后续处理建议

设备场景和传统组场景共用同一场景数组，均受影响。日程选择、组开关场景选择、设备开关场景选择也直接消费该数组，修复时应同步统一展示规则；其关联仍通过 `number` 查找，不应为修复位置而修改编号。

这些逻辑位于共享 App 代码和当前本地 SDK 中，相关品牌均应纳入影响范围，不局限于 SunSmart 页面。本次不需要固件修改，也没有证据表明服务器必须修改。

修复前需要确定期望的排序语义，不能把“补一个排序”视作三种目标都能满足：

| 期望 | 必要方向与限制 |
| --- | --- |
| 始终按内部编号排序 | 在相关展示入口统一显式排序；改动较小，创建时复用旧编号会立即插到前面，名称数字不保证升序 |
| 始终按名称排序 | 明确定义名称数字的自然排序及重名/语言规则；改名立即影响位置，不保留创建先后 |
| 新建追加末尾，改名不动，重进和恢复后仍保持 | 推荐按这一稳定位置目标评估：独立持久化展示顺序，覆盖创建、删除、恢复和分享/云端数据往返；旧数据需要确定的回退顺序，不能凭现有编号恢复真实历史创建顺序 |

如采用最后一种目标，必须核对扩展数据经云端往返是否保留新字段；若需外部配套，另行明确接口契约和责任方。本轮仅给出方向，未实施方案。

后续必要验证应覆盖：删除/改名后继续创建、单纯改名、编号复用、待删除编号不提前复用、退出重进/重启、云端数据往返、旧数据缺少排序字段，以及日程/开关选择页一致性。按最终规则选择相关回归，不以当前配置序列化的编号规范化测试代替 UI 顺序验证。

## 5. 证据范围与源码入口

- 核对版本：App 分支 `feat/device-scene-261028`，分析开始 HEAD `32c76837`，结束时 HEAD `47140eb6`；两者差异仅为 Site 页间距修改、对应测试与文档，本次场景链路未变化。`SunSmartLocal.xcworkspace` 实际映射 SDK `one-dev`，HEAD `dbcf6f1`，SDK 工作区无未提交改动。
- 已完成：App/SDK 源码链路检查；以 SDK 表结构、保存语义及加载谓词建立内存 SQLite 夹具，普通创建及仅改名控制组顺序不变，删除＋改名＋重建组重载顺序反转。
- 夹具验证的是数据库与内存顺序差异，没有运行完整 App，也没有访问真实业务数据库；云端实际往返与设备 UI 尚未验收。
- 分析阶段仅新增本文档，未修改 App/SDK 业务代码、构建或操作真机；确认后的实施结果见第 10 节。

主要源码入口：

- [ScenesViewController.swift](../SunSmart/Main/Scene/Controller/ScenesViewController.swift)：`visibleScenes`、`updateUI`。
- [ScenesViewCell.swift](../SunSmart/Main/Scene/View/ScenesViewCell.swift)：名称展示。
- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：`getNextSceneName`、`loadExtensionData`、`SceneInfo`。
- [SceneConfigurationStore.swift](../SunSmart/Main/Scene/Model/SceneConfigurationStore.swift)：`nextAvailableNumber`、`project`、`commitMetadata`、`finishDeletion`、`exportRecords`、`restoreSceneProjections`。
- [SceneConfiguration.swift](../SunSmart/Main/Scene/Model/SceneConfiguration.swift)：`SceneConfigurationPayload.metadata` / `encode`。
- [ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 与 [ImportData.swift](../SunSmart/Common/Data/ImportData.swift)：场景数据导出与重新建模。
- [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)：`setNetworkConnected`。
- SDK `Sources/NordicSigMeshSDK/MeshLib/MeshDatabase.swift`：`Scene.initDatabase`、`Scene.load`、`Scene.save` 与 `MeshNetwork.load`。
- SDK `Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`：`setMeshNetworkConnected`、`loadMeshNetwork`、`scenes`。
- SDK `Sources/NordicSigMeshSDK/nRFMeshProvision/Mesh Model/MeshNetwork.swift`：`add(scene:)`。
- SDK `Sources/NordicSigMeshSDK/MeshLib/Scene/SceneRegisterPolicy.swift`：`nextOrdinaryNumber`。

## 6. 拟实施的行为规则

采用“稳定创建顺序”，不增加手动排序入口：

1. 新建成功的场景始终放在现存场景末尾，即使复用了较小的 Mesh 编号。
2. 改名、换图标、修改成员/参数、同步回执与重试都不改变位置。
3. 删除过程中保持原位置；完整删除后移除，其余场景相对顺序不变。
4. 退出 Space 再进入、重启 App、SDK 投影恢复后保持相同顺序。
5. Space 场景页、日程场景选择、组开关/电源开关/设备开关及八键开关预配置的场景选择采用同一规则。各入口原有候选过滤和权限规则继续生效。
6. 名称生成及 Mesh 编号分配沿用现有规则。名称中的数字不是位置序号，不要求列表始终显示为 `Scene 1、Scene 2、Scene 3`；例如删除 `Scene 2` 后再新建同名场景，它应出现在末尾。

## 7. 最小完整实现

### 7.1 扩展现有 App 元数据

- 在 `SceneInfo` 和 App `sceneInfos` 表增加可空 `displayOrder: Int64?`，复用现有迁移及 SQLite 保存事务，不增加独立存储表。
- 顺序属于展示元数据，不放入 `SceneConfiguration`、`SceneDraft` 或设备同步参数。这样传统 `configuration == nil` 的组场景也可以保存顺序，并且不会仅因排序变化生成设备写入任务或改变同步 revision。
- 比较规则为“有效 displayOrder 优先作为数值键；缺失时以内部 number 作为数值键；键相同再按 number 升序”。无效展示值回退，不把合法场景标记为配置损坏。分配前进行范围和溢出检查。
- 纯排序和载荷归一化规则放在现有共享场景模型文件；App 的 Scene 数组使用同一个展示排序入口。不修改 SDK 的全局 `scenes` 数组或数据库查询，避免影响任务遍历和协议层使用方。

### 7.2 创建、编辑、删除与失败恢复

| 入口 | 拟修改行为 |
| --- | --- |
| `SceneConfigurationStore.commit` 新建 | 在已有 `configurationTransaction` 内取当前 Space 有效顺序最大值 + 1，并与场景配置一起保存；空 Space 从 1 开始 |
| 创建时取最大值的集合 | 合并当前 Space 普通 SDK 场景与 App 已提交场景记录，包含没有 SDK 投影的记录和待删除记录；不把数据库读取失败当成空集合 |
| `commit` 编辑、`commitMetadata` | 从当前持久记录保留顺序，不由旧草稿重分配；当前实现会重新构造 SceneInfo，需要显式带上该字段 |
| `SceneInfo.saveConfiguration` | `INSERT OR REPLACE` 带上顺序；旧场景缺字段可保持 nil 回退，不在普通读取中自动回填 |
| SDK 投影失败后的重试 | 复用现有按 draft revision 查找已提交记录的幂等恢复路径，复用原编号和顺序，不再分配 |
| ACK、删除意图、设备身份恢复 | 已加载 SceneInfo 的顺序随配置一起保留；同步参数与原恢复保护规则不变 |
| 完整删除 | 随原 SceneInfo 一起删除顺序；后续复用编号视为新场景，重新分配末尾顺序 |
| `importRecords` 与导入后 SDK Scene 的 `info` 赋值 | 必须保留导入后的完整 SceneInfo；不能重新构造一个只含图标/配置而遗漏顺序的对象 |

创建保存失败时，顺序与场景记录一起回滚；已提交但未投影成功时，顺序随原记录保留。不要为展示排序增加另一套提交、取消或重试状态机。

### 7.3 展示入口

在实际消费场景数组的三个共享位置接入排序：

- `ScenesViewController.visibleScenes`：保留既有消防场景过滤后排序。
- `ScheduleScenesView` 初始化数据源：保留调用方候选集合，统一顺序。
- `SwitchSelectScenePageController` 初始化数据源：覆盖组开关、电源开关、设备开关和 `PJPreAddEightKeySwitchesVC`，其子页面沿用这个数组。

这些位置只改变显示顺序；选择和回调仍传 Scene 对象/number，不能把列表下标变成持久引用。场景列表沿用现有刷新通知与页面生命周期机制。

### 7.4 分享和云端数据往返

- 使用独立可选字段 `spaceData.sceneDisplayOrder`，内容为普通场景编号的有序数组，例如 `["0002", "0001"]`，不依赖服务端保存 `scenes` 数组本身的顺序。
- 导出复用 `SceneConfigurationStore.exportRecords` 已覆盖的全部普通场景记录，包括未完成删除记录、已提交但 SDK 未投影的记录。先按有效展示顺序排列，再输出编号数组；无场景时输出空数组。
- `SceneConfigurationPayload.Record` 可增加仅供 App 传递的可空顺序值。现有 `scenes` 元数据与 `sceneConfigurations` 的编号规范化、字段校验保持原意，不将展示字段混入设备配置。
- 导入时根据完整场景记录归一化有序编号数组，再映射为紧凑本地顺序值并在现有完整 Space 导入事务内保存。回读验证补充展示顺序验证，导入失败整体回滚。
- 导出只在载荷中表示有效顺序，不为了回填字段写本地数据库，不因为访客读取页面或导出触发编辑权限要求、云端上传或 Mesh 同步。

### 7.5 必须同步处理的比较与恢复边界

已确认 `SpaceCloudNodeRemovalPolicy.Snapshot.make` 会把整个 `spaceData` 纳入摘要，`recoveryPayloadsMatch` 和 `defaultRecoverySourceData` 也比较包含 `spaceData` 的完整片段。仅增加传输字段而不处理这些使用方，会把展示差异误判成配置变化。

拟定处理：

- 在这些配置/恢复比较的副本中仅排除新增 `sceneDisplayOrder`；新旧两侧（包括历史已持久化的比较 Data）采用相同归一化，避免升级后误判已有恢复源改变。原始导出、备份和导入载体仍保留它。已有名称、编号、成员、参数、网络身份、权限和其他扩展字段校验不放宽。
- `configurationData` 本就不选取独立展示字段，保留这一边界，不改变 `sceneComparisonVersion` 或设备同步的期望配置格式。
- 节点删除 Snapshot 的 `comparisonVersion` 从 3 升至 4，并同步更新生成、比较与 `reconcileSameVersionNodeRemoval` 的版本检查。原因是旧客户端收到未知扩展字段后，可能已将它收入 v3 摘要，不能让两种摘要语义混用同一版本。
- 旧 Snapshot 复用现有可信完整导出/已确认代次的重建流程；缺少可信基线时保持原有保护，不利用排序迁移绕过原来的身份或删除确认要求。
- 不增加独立云端重试队列、Submission 状态字段、持久警告或新的用户提示流程。设备配置上传成功与云端保留展示顺序分别验收。

## 8. 旧数据和外部兼容范围

### 8.1 旧数据基线

- 没有 displayOrder 的本地旧场景按内部编号升序展示；这是稳定基线，不能还原已经丢失的历史创建顺序，升级首次可能与原内存列表有一次差异。
- 仅迁移可空列，不在打开页面时全量重写历史记录。新建分配最大值时必须把旧场景的编号回退值纳入，保证新场景仍在全部旧场景之后。
- 完整导入缺少 `sceneDisplayOrder` 时按内部编号建立基线，不能只凭编号相同保留原本地顺序，因为编号可能已经被另一场景复用。
- 合法部分数组保持其中现存编号的相对顺序，未列出的场景按编号补在末尾；重复编号去重，已不存在/保留编号忽略。字段类型无效或没有可用项时回退编号顺序。只对展示字段降级，真正的场景编号重复、身份损坏、模式冲突等仍由原校验拒绝。
- 空配置允许进入和往返；无效排序信息不能单独触发配置恢复拦截或把场景标成 Mesh Unsync。

### 8.2 新旧客户端与服务器

- 新版 App 本地重载、新版生成文件的导入导出，可以由本次 App 实现和离线测试完整覆盖。
- 当前旧客户端的 `ExportData` 会重建 `spaceData`，不会保留未知字段。因此经旧客户端重新保存/上传后，顺序字段可能丢失；新版再次完整导入时回退编号基线。此次不承诺跨旧客户端仍保留新顺序。
- 云端场景顺序保持依赖服务器在上传、保存、GET、分享等路径保留 `spaceData.sceneDisplayOrder` 数组内容和数组内顺序。现有 App 代码不足以证明服务器已满足该契约。
- 上线前做一次真实“上传 → GET 检查字段 → 另一台新版 App 导入”的联调。不能用 HTTP 成功、普通配置回读成功或 App 编译成功代替这个验收。
- 若服务端丢弃该字段，App 工作继续完成，本地排序可交付；跨手机云端顺序保持列为未完成配套，由服务器团队按上述透传契约处理。本任务不修改服务器、固件或其运行配置。

## 9. 修改范围、验证与交付

预计改动限于现有 App 共享链路：

| 范围 | 文件/职责 |
| --- | --- |
| 展示字段与通用规则 | `MeshNetwork+SunSmart.swift`、`SceneConfiguration.swift` |
| 数据库、创建/保存/恢复 | `Database.swift`、`SceneConfigurationStore.swift` |
| 导入导出 | `ExportData.swift`、`ImportData.swift` |
| 配置比较/恢复兼容 | `SpaceConfigurationIntegrityPolicy.swift`、`SpaceConfigurationSafety.swift` |
| 三个展示入口 | `ScenesViewController.swift`、`ScheduleScenesView.swift`、`SwitchSelectScenePageController.swift` |
| 验证 | 扩展现有 Scene 与 Space 比较/恢复测试和现有脚本，不创建新测试工程 |

共享代码影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。方案不需要 SDK API、依赖、资源、本地化或 target 配置变更，优先放入已有共享文件。

规划结束时工作树另有场景设备色温显示/参数编辑相关未提交改动，涉及 `SceneSettingsViewController`、测试及 `check_scene_configuration.py`。本任务没有修改这些文件；正式实施前只复核相关差异，并在现有测试脚本上增量接入，保留另一任务的工作。

确认后按以下顺序实施：

1. 扩展顺序字段、确定性排序/归一化和 SQLite 持久化，覆盖创建、编辑、失败重试、完整删除及编号复用。
2. 接入三个共享显示入口与导入导出，补齐导入重建 SceneInfo 的字段保留。
3. 处理新增展示字段的比较隔离与 Snapshot 版本兼容，补齐回归后执行一次代表 App 构建。

必要自动化验证：

- 扩展 `SceneConfigurationPersistenceTests`：旧表重复迁移、数据库关闭重开、nullable/异常展示值、跨 Mesh/Space 隔离、REPLACE 保存保留。
- 扩展 `SceneSaveFlowTests` / 创建流程测试：原复现序列、编辑/图标不动、新建末尾、事务失败、SDK 投影失败重试不重分配。
- 扩展 `ScenePayloadPersistenceTests` / roundtrip：顺序字段、旧字段缺失、部分/重复/过期/非法数组、空数组、传统组场景、tombstone、导入回滚及只读导出。
- 删除与 ACK/恢复回归：待删除保留位置和编号，完整删除后新建追加；排序不改变 pendingOperations、revision、目标集合或场景引用。
- 比较/恢复回归：仅排序不同不误判设备配置冲突；真实名称/成员/参数/身份变化仍被检测；v3 Snapshot 按可信代次重建为 v4，无可信基线继续保护。
- 展示入口行为测试：三类入口收到不同底层数组顺序时显示一致，选中回调仍对应原 Scene number。复用现有 picker/integration 夹具，不只断言源码包含某个函数名。

执行入口优先使用 `check_scene_configuration.py` 的 `storage`、`save`、`roundtrip`、`integration` 相关套件，结合 `check_scene_creation_flow.py`、`check_scene_deletion_flow.py`，以及现有 Space 完整性/恢复回归入口；只扩展与本次修改直接相关的用例。

代码稳定后使用已核对的 `SunSmartLocal.xcworkspace`，执行 SunSmart Debug、generic iOS、关闭签名的一次编译；若实际实现新增品牌特异配置或资源归属变化，再补相应品牌检查。当前规划阶段不构建。

人工验收：按第 3 节复现序列检查新建、退回 Space 列表再进入和重启后的顺序；核对日程/开关选择页；完成新版之间真实云端往返。由用户执行，不自动安装或运行真机。

用户已确认本方案整体，以及两个明确取舍：**旧数据以内部编号顺序建立首次基线；旧客户端重传丢失排序字段时允许回退基线，新版云端顺序以真实透传联调为发布验收项。**

## 10. 实施与验证结果

### 已完成

- App `SceneInfo` 增加可空 `displayOrder`，旧表自动增加列。读取 NULL、非整数、非正数和无效极值时只回退展示顺序，不把有效场景配置标为损坏。
- 新建在现有事务中分配当前 Space 最大有效顺序 + 1；数据库读取失败不当空集合，分配有溢出保护。已有场景编辑保留持久记录顺序，投影失败重试沿用原记录。
- Space 场景页、日程选择、开关选择使用生产共享排序方法；名称和内部编号不重写，点击后的 Scene 对象及 Recall 编号保持正确。
- `spaceData.sceneDisplayOrder` 随导出记录携带，导入归一化后在既有事务中保存，并增加事务内顺序回读验证；包括 SDK 投影缺失与删除未完成的记录。
- 新展示字段从相关配置比较副本中排除，其他字段仍保留检查。节点删除 Snapshot 升至 v4，默认恢复源比较兼容旧持久化 Data。
- 仅修改 App 现有共享源文件及相关测试，未修改 SDK、依赖、工程资源、本地化、固件或服务器。

### 已通过的验证

| 验证 | 结果与覆盖 |
| --- | --- |
| Scene storage | 59 assertions 通过；实际 SQLite 迁移、重开、非法类型、REPLACE、跨 Space 与回滚 |
| Scene save / coordinator | 通过；原删除＋改名＋复用编号序列、legacy/孤立记录/待删除记录分配、投影失败重试、事务回滚及原同步生命周期 |
| Scene roundtrip / roundtrip-storage / roundtrip-group | 通过；新旧/空/部分/重复/过期顺序、只读导入、持久化往返、删除记录及身份恢复；原组参数编码语义保持 |
| Scene integration | 通过；执行生产列表 getter 和两个选择页 initializer，验证不同底层排列、名称变化、旧数据回退、顺序值重复的决胜规则及实际选择/Recall 身份 |
| `check_scene_creation_flow.py` / `check_scene_deletion_flow.py` | 通过；创建取消/失败/重试与删除 ACK、退出重进、恢复和清理路径 |
| `check_space_recovery_receipts.py` | 全部通过；新增 11 个排序字段恢复兼容案例，覆盖可信 v3→v4 重建与无可信证明时原保护边界 |
| `SpaceConfigurationIntegrityPolicyTests` | 生产模型与完整性策略直接编译运行通过；真实配置缺失、类型和字段差异仍被识别 |
| `git diff --check` | 通过 |
| SunSmart Debug generic iOS | 2026-11-02 20:07 输出 `BUILD SUCCEEDED`；`SunSmartLocal.xcworkspace`，`CODE_SIGNING_ALLOWED=NO`，稳定 DerivedData `SunSmart-feat-device-scene-261028-cli` |

实施基线为分支 `feat/device-scene-261028`、HEAD `5a73c3d3`；以上结果包含本任务未提交差异。SDK 实际解析到本地 `one-dev`，revision `dbcf6f1`，无 SDK 差异。保留了原有测试脚本中设备参数编辑测试的未提交段落及另一任务文档；未执行 Git 提交。

自动化使用生产方法/SQLite 与受控 UI、BLE、HTTP 边界，不能替代完整 App 真实运行。首次测试遇到默认模块缓存不可写后，改用工作树专用、可写的 DerivedData 模块缓存完成验证，未调整业务代码绕过环境问题。

### 待人工验收及限制

1. 用两个空场景执行第 3 节操作：删第一个、把第二个改名为 `Scene 1`、新建 `Scene 2`；退回 Space 列表再进入，并重启 App，名称顺序应始终保持 `Scene 1、Scene 2`。
2. 改名/换图标/编辑参数后检查位置不变；日程与开关选择页的相对顺序一致，选中后仍绑定对应场景。
3. 在新版之间执行“上传 → GET → 另一手机导入”，确认 `spaceData.sceneDisplayOrder` 内容和数组顺序被保留，导入后的可见场景顺序一致。这是尚未执行的服务端透传验收。
4. 旧数据或旧客户端重新上传丢失字段时按编号基线展示，符合已接受取舍。没有手动排序入口；仅补回排序字段而不增加云端配置时间戳时，不扩大原有同版本导入逻辑，下一次正常配置变更或显式恢复时接收。

未自动运行真机、未验证真实云端往返；不将离线回归或构建通过表述为上述运行验收完成。
