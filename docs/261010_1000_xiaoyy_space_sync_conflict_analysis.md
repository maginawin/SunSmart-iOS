# 空间 1vjj 云同步失败分析与 Profile 版本冲突修复

日期：2026-10-10，时间均为 UTC+08:00。状态：完成现场分析，并按用户确认的 Space 时间规则实施 App 修复；相关回归、现场样本隔离复测和 SunSmart Debug generic iOS 编译通过。未修改原始样本、SDK、服务器或固件，未请求线上接口或操作真机。既有邻近照明测试夹具问题及人工验收边界见文末。

## 修复前结论

1. **空间需要同步的直接原因已确认**：本地最后修改为 09:46:39，最后确认上传为 09:32:07，满足 `needUploadCloud`。本地持久化错误为 `-2002`，即 `configurationUploadUnconfirmed`，表示无法确认云同步结果，不是 HTTP 错误。
2. **证据指向双端修改后的配置冲突**：云端版本为 09:34:17，C003「组 3」与本地有实际灯控配置差异。用户已确认这一时段两边都修改过。App 的同步入口先核对云端与历史基线／待确认提交，核对失败即返回，不会因再次点击 SYNC 自动选择本地覆盖云端。
3. **已确认一个会额外制造不一致的比较兼容问题**：云端 C003 的 General Scene 带有 9 个当前 App 场景导入、导出不读写的附加字段；配置比较却保留全部场景字典。即使实际参数已经对齐，这 9 个字段仍足以使比较失败。
4. **反复 SYNC 的交互缺口可复现**：部分同步前置核对失败只返回 `-2002`，没有设置配置核对状态，因而仍显示普通重试入口，没有转入已有的云端／本机配置选择流程。

现有文件不包含实际历史基线及待确认提交。不能仅凭当前本地与云端的差异，唯一断定现场是在“无待确认提交的基线核对”还是“已有提交的读回核对”中失败，也不能认定服务器曾成功接收这份 09:46:39 的配置。下文将现场事实和条件性复现分开记录。

## 输入与代码版本

- [App 诊断导出](</Users/maginawin/Desktop/doing/xiaoyy sync issues/Space_空间 1vjj_20261010_095224_096+0800.json>)，采集于 09:52:24。SHA-256：`7d96f29d35c6015d8c6e645e6aa1e173222a8d1e79f89d917edd650a3e8e6dee`。
- [服务器 get spaceprops 数据](</Users/maginawin/Desktop/doing/xiaoyy sync issues/space 1vjj server data.json>)，业务对象位于 `data`，响应 `code=200`、`message=success`。SHA-256：`d1e7b588cc82f23e5ac3201a99b2e498dbddec9ba34c3091ce6431cb5b814fa2`。
- Site：`2FFF79D5-F3B0-488B-B1F3-4DE2819FF86F`；Space：`AF39FF10-02FB-4AAD-A606-C6824758A23D`。
- 工作树：`feat-timed-limited-261008`；分支：`feat/timed-limited-261008`；HEAD：`07aade0b30f5afbc9877e075cc3c24cbf99434e8`。分析开始时无未提交改动。
- 用户补充：09:32～09:47 期间两端均修改过该组。没有读取 Web 或后端实现。

App 文件的 `_debugInspection.uploadable=false`，它是诊断文件，不能整体作为修复上传请求体。本文不保存凭据、网络密钥或设备密钥。

## 数据证据

### 时间与保护状态

| 项目 | 值 | 含义 |
| --- | --- | --- |
| 本地 `lastUploadCloudTimestamp` | `1791595927`，09:32:07 | 最后确认上传／同步时间 |
| 云端 `updateTimestamp` | `1791596057`，09:34:17 | 比最后确认时间新 2 分 10 秒 |
| 本地 `lastUpdateTimestamp` / 导出 `updateTimestamp` | `1791596799`，09:46:39 | 比最后确认时间新 14 分 32 秒，比当前云端新 12 分 22 秒 |
| 本地 `syncCloudError` | `-2002` | 云同步结果无法确认 |
| 成员与配置 | `joined`、`configurationInitialized=true`、`recoveryPhase=active` | 有已初始化的本地配置 |
| 挂起导入／删除清理 | 均为 false | 当前导出没有这些未完成状态 |
| `blockedReason` | 未提供该字段 | 该诊断入口中表示没有保存阻断原因 |
| 导出检查 | `comparisonPayloadAvailable=true`、`issues=[]` | 当前本地检查副本可生成；不代表云端已确认 |

[SpaceData.swift](../SunSmart/Common/Data/SpaceData.swift) 的 `needUploadCloud` 使用本地修改时间与最后确认时间，且排除 visitor。当前角色为 owner，因此本例确定需要上传。`showSyncCloudError` 在需要上传／存在待确认提交时返回已保存的同步错误。

`pendingImport=false` **不表示**没有待确认上传。当前 `debugSnapshotStatus` 只导出部分状态，没有导出 `submission`、`authorizationBaseline`、`nodeIdentitiesBaseline`、`schedulerModelStatesBaseline` 等，所以不能据此判定是否存在待确认提交。

### 真正参与配置比较的差异

差异集中在 C003「组 3」，Profile ID 两端相同，类型均为 1（Occupancy + Daylight）。C000、C001 的 Profile 相同。

| C003 Profile 字段 | App 本地 | 云端 |
| --- | --- | --- |
| `occupancyLevel` | 734 | 414 |
| `vacantLevel` | 100 | 106 |
| `timeT4` | 0 | 30 |
| `adjustSpeed` | 50 | 82 |
| `calibrationMode` | `none` | `sensorCal` |
| General Scene / FF00 的 `occupancyLevel` | 734 | 414 |
| FF00 的 `vacantLevel` | 100 | 106 |
| FF00 的 `timeT4` | 0 | 30 |

类型 1 的 occupancy/vacant 等字段使用照度范围，当前校验允许至 UInt16.max；734、414、106 并非因为超过 100 而非法。两份数据均通过当前 Profile 校验，也不是此前 type 8 缺失 `taskLevel` 的问题。

云端 FF00 另外包含 9 个字段，本地场景没有：`adjustSpeed`、`highEndTrim`、`id`、`lowEndTrim`、`manualOverrideTimeout`、`powerUpState`、`relativeSensitivity`、`type`、`typeSwitchedFrom`。它们大多重复 Profile 顶层信息。

[ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 创建场景时只读取场景编号、名称及灯控阶段参数；例如场景 high/low trim 从顶层 Profile 获取，并不读取这些重复字段。[ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 也只输出场景的 13 个约定字段。但 [SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 仅在 Profile 顶层筛选比较字段，对 `scenes` 只排序，没有筛掉这些附加字段，持久化基线的规范化同样保留它们。

生产比较共报告 17 处差异：8 处实际参数差异，加上述 9 处场景附加字段。顶层 `typeSwitchedFrom` 已被过滤，不是这 17 处之一。

### 其他差异与排除项

- 两端均为 36 台设备、3 个组、6 个场景，日程、开关和紧急消防控制器集合为空。
- NetKey、AppKey 对象相同；36 台设备的 UUID、单播地址、Device Key、元素及模型、组归属一致，生产节点身份策略计算缺失节点为 0。没有证据把本例归因于丢设备或网络身份变化。
- `spaceData`、场景清单相同；两端均无待清理的拓扑引用，生产清理策略返回 `didChange=false`。
- 相同设备字段中，34 台 timestamp、22 台 lightLCPropertys、22 台 lightControlSceneExecuteDatas、21 台 pirEnabled、1 台 daylightCalibrationData 不同。它们属于设备状态／观测缓存，未进入本次逻辑配置比较，不能把全部 JSON 差异都当作同步拦截原因。
- 云端 C003 有本地没有的 `daylightSensorAddress`。它不进入上述配置摘要，但与校准使用有关，最终选择配置时应一起核对，不能只对齐表中数值就宣称完整业务已验收。

## 为什么 HTTP 成功，SYNC 仍然失败

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的同步异常弹窗使用 `SRAlertView`，标题为 `Synchronization failure`，SYNC 重新排入 `.syncSpace`；Space 页面也有同类入口。日志中的 `SRAlertView.secondBtnClick` 与这些入口一致，但没有页面路径，不能唯一确定是哪一个。
2. [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 真正生成上传请求之前，先执行 `SpaceConfigurationSafety.resumeUpload`。只要它返回失败，本轮直接调用 `finishConfigurationFailure`，保存 `-2002` 并结束，后面的 `spaceUpload` 不会执行。
3. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 有两条相关路径：
   - **没有待确认提交，但本地有修改和历史基线**：先 GET，再用 `reconcileCloudMembership` 核对云端是否仍与已确认基线相容。这并非只检查设备数量；即使设备未减少，也会核对 Profile 等逻辑配置。云端发生其他配置修改时，直接返回 false，避免自动覆盖其他端修改。
   - **已有 accepted 提交**：先 GET 确认该提交。成员协调要求云端时间不早于提交时间；若待确认的就是 09:46:39，而云端仍为 09:34:17，会在这里直接返回失败。若通过时间等检查，后面仍需比较逻辑配置与提交快照。
4. 两类早退都可能只发一次 GET、返回 `-2002`，而没有打印后面的 `[SpaceConfigurationReadback] result=mismatch`，也没有设置 `uploadReadbackConflict`。这解释了为何日志可能只有请求／响应／解码，没有更具体的冲突日志。
5. `isBlocked=false` 时，Space 页面不会走已有配置恢复对话框，而是继续普通 SYNC。重新点击会执行相同前置检查，既不刷新已确认基线，也不替用户决定保留哪一端，所以会重复失败。

用户提供日志中的 POST 实际请求的是 `/get/spaceprops`，不是 `/sync/spaceprops`。HTTP 200、gzip 传输后成功解码 274398 字节、约 0.072 秒解析耗时，只能证明这次取数据／解码完成。日志未包含上传请求、上传接受结果或一致性确认成功。响应 body 被省略，无法证明日志中的响应与附件逐字节相同。

## 离线复现

第一组探针直接编译当前生产完整性、拓扑和清理策略，读取原始文件；没有改写文件。

| 检查 | 结果 |
| --- | --- |
| 两端 Profile／日程目标校验 | 均通过 |
| 两端配置摘要、36 台节点身份、Scheduler 模型摘要 | 均可生成 |
| 节点缺失、清理变更 | 0、false |
| 日程目标／Scheduler 模型摘要比较 | 相同 |
| 原始逻辑配置比较 | 不相同，17 处差异 |
| 仅在内存中把云端 8 处有效参数对齐本地 | 仍不相同，场景附加字段仍在 |
| 在内存中把云端 C003 整个 Profile 换成本地 | 逻辑配置比较相同 |

第二组探针复用现有 `check_space_recovery_receipts.py` 的生产方法抽取和隔离替身，替换测试入口，执行生产 `resumeUpload` / `reconcileCloudMembership`。设备及 Profile 来自样本；网络身份替换为测试替身约定，网络响应、App 数据库和历史恢复状态由夹具控制，没有连接真实服务。以下历史状态是为了区分条件而构造，**不是从现场导出提取的历史基线**。

| 构造状态 | 结果 |
| --- | --- |
| 无待确认提交，基线内容取当前本地配置，云端使用附件 | 1 次 GET 后 `-2002`，未设置 blocked |
| 无待确认提交，基线内容与云端完全相同 | 1 次 GET 后前置核对成功，可继续后续流程 |
| 无待确认提交，基线与云端只有上述 9 个场景附加字段差异 | 1 次 GET 后 `-2002`，未设置 blocked |
| 待确认 accepted 提交取当前本地 09:46:39，云端使用附件 | 1 次 GET 后 `-2002`，未设置 blocked，提交继续保留 |

这证实“云端比本地旧”本身并非无条件失败理由：若云端仍与历史基线相同，较新的本地修改可以继续上传。反之，云端已改变基线或尚不能确认已提交版本时，当前代码会保留本地并停止。现有附件不足以在第一与第四类现场状态之间唯一选择。

上述为修复前分析阶段的证据；当时未构建或修改业务代码。实施后的验证另列在文末。隔离探针不等同于现场完整同步验收。

## 建议与后续边界

### 必须保留的业务保护

用户在实施时明确调整规则：Profile 差异按修改时间较新的一方处理，并确认使用 Space 的 `updateTimestamp` 选择同一组的整份 Profile。该授权替代分析阶段对 Profile 差异要求人工择版的建议；同时间但 Profile 不同仍进入配置核对。设备身份、成员关系、拓扑、日程等不按时间直接覆盖。最新 Profile 对应设备当前配置是本次产品规则，App 不据此伪造设备 ACK 或修改设备观测缓存。

### 分析阶段的 App 修复建议（最终实施规则见下文）

1. **把可确认的业务冲突接入已有恢复流程。** 区分云端数据不合法、暂时读到旧版本、网络失败、持久化失败与真正的配置冲突；在证据足够时保存明确冲突原因，让空间页面能进入已有 `Reload cloud data` / 本机配置恢复入口。不要给所有 `reconcileCloudMembership=false` 一律添加同一种阻断。Site 列表、Space 页面和普通导入复用的检测入口需要一致处理。
2. **统一场景业务比较的字段契约。** 对本例这类导入器明确忽略、导出器不产生的重复字段进行有限兼容，覆盖当前响应、新提交以及已有持久化基线／回执；仍保留真实灯控字段差异、错误类型、缺失必要字段、网络身份与权限检查。只修 9 个字段的比较，不会解决本例 8 处真实配置冲突。
3. **补充足够而不泄密的诊断。** 当前 DEBUG 导出缺少提交是否存在、phase、timestamp、基线摘要及最近核对失败阶段。可以记录这些非敏感信息及现有脱敏差异摘要，避免只能看到 HTTP 200 和通用 `-2002`。不导出密钥或完整恢复文件内容。
4. **验证与当前风险匹配。** 覆盖云端未变允许本地上传、两端真实修改进入核对、只有附加字段可兼容、accepted 提交读到旧云版本不丢回执、失败后退出重进保留冲突与本地数据；同时确认正常空配置及合法设备删除恢复没有被新状态阻断。实施后按项目规则执行相关回归及一次代表 scheme 编译。

### Web／服务器协作与证据缺口

- Web／服务端团队核对 C003 场景内重复字段是由编辑请求、保存映射还是 GET 组装产生，统一场景字段契约。仅凭这两份样本不能唯一分配产生责任。
- 要唯一定位现场早退分支，需要手机的恢复状态诊断：是否有 submission、phase、timestamp，以及 authorizationBaseline 与当前云端的脱敏差异。当前导出不包含这些信息，重复提供相同 HTTP 请求日志无法补足。
- 如需判断“App 已上传但服务器没有保存”，还必须获得对应 `/sync/spaceprops` 的请求版本、响应和紧随其后的 GET；现有 GET 200 不能提供该结论。
- 最终人工验收：明确保留哪端配置并完成恢复后，同步成功、退出重进不再提示；云端读回 C003 参数、传感器选择和 36 台设备清单符合所选结果；再做一次单端编辑确认正常收敛。真实灯光与校准效果由用户验收。

本轮不需要固件或 SDK 变更。外部字段契约核对由 Web／服务端团队负责；App 的最终实施与验证如下。


## 用户确认的规则与最终实现

用户确认：两端均可下发 Profile，使用 Space 的更新时间选取同一组的整份 Profile；不新增每个 Profile／属性的时间戳，也不要求服务器配套后才能处理本例。

- **本地较新**：保留当前本地 Profile。只有远端相对历史基线／待确认提交的差异限于 Profile，且网络身份、节点身份、拓扑、日程与 Scheduler 模型检查均满足条件，才更新云端比较基线并继续完整上传。
- **云端较新**：复用原有云端 Profile 解码器，将现存本地组的整份 Profile 及配套的校准传感器选择写入 App 数据库。保留本地组名称、图像、拓扑和其他修改，不恢复本地已删除的组。Profile、GroupInfo 与 Space 版本在同一 SQLite 事务中保存，失败整体回滚。合并版本记为云端时间加一，表示待上传的合并快照，防止随后完整云端导入覆盖其他本地修改。
- **时间相同**：共享组的 Profile 相同可以继续；不同则记录 `profileTimestampConflict`，进入已有配置核对流程。
- **原有待确认提交**：满足上述严格条件后可由新的完整快照取代，旧提交不被伪报为确认成功；`lastUploadCloudTimestamp` 仅在新上传接受并读回一致后推进。数据库合并成功而恢复状态文件写入失败时，本地合并数据保留且仍为待上传，重试可继续收敛。
- **适用边界**：自动选择需要可读取的历史比较数据、相同配网实例及明确的版本顺序。实际设备增删、跨实例变化或其他业务差异继续由原有生命周期／配置核对处理；无法证明安全时不猜测合并。暂时读到旧云版本、网络／保存失败不一律制造人工核对状态。

共享入口位于 `SpaceConfigurationSafety.reconcileCloudProfiles`，由普通 Space 更新及 `resumeUpload` 的有／无待确认提交路径调用。调用期间的本地版本变化、生命周期变化、取消、权限变化继续拒绝过期结果。新逻辑不发送 Mesh 配置命令，不改写设备观测缓存。

`ImportData.swift` 原有约 100 行 Profile 映射提取为 `Profile.fromCloud`，完整导入和局部合并复用同一实现；经对照，除缩进及赋值改为返回外，映射逻辑没有变化。云端较新时更新活动网络的 GroupInfo 并清除设备同步状态缓存，界面继续使用已有刷新机制。

## 比较兼容、交互与诊断

- 配置规范化仅忽略本例 9 个场景内重复的 Profile 字段；当前数据和已有持久化比较基线／回执使用相同规范化。实际灯控参数、未知场景字段及非法必要字段继续区分，不宽泛丢弃扩展字段。
- 可证明的非 Profile 配置或成员冲突记录明确原因；Space 页面复用现有云端／本机恢复对话框。Site 列表点击这类错误会进入 Space 并打开同一对话框，继续检查成员状态、权限及密码验证条件，不再只提供无法解除冲突的普通 SYNC。
- DEBUG 检查副本新增待确认上传是否存在、提交 phase／timestamp、本地及最后确认时间、规范化基线／提交摘要，以及最近失败阶段／错误码／时间。诊断写入和日志均处于 DEBUG 条件内，不包含原始密钥、密码或完整恢复文件。
- 本次未新增 UI 文案、资源、依赖、数据库 schema 或 SDK API；五品牌共享逻辑，无不同编译路径。代表构建使用 SunSmart。

## 实施验证结果

1. **完整性策略测试通过**：9 个重复字段的兼容、历史回执双向比较、真实参数变化保留、非法值拒绝、组地址／拓扑差异保护、未知场景字段保留。
2. **`check_space_recovery_receipts.py` 通过**：执行生产同步／恢复方法，覆盖本地／云端较新、同时间冲突、prepared／accepted 回执替换、持久化失败重试、合并成功后回执保存失败、本地修改插入等待点、取消、网络失败、权限降级和旧云版本。已有空日程、设备删除、Timed、旧回执、导入恢复用例仍通过。
3. **`check_profile_persistence.py` 通过**：真实 Profile 解码、SQLite 保存／关闭重开／读回。新用例执行生产局部合并方法，验证 Space 保存失败能回滚 Profile／GroupInfo、较新云端值和校准传感器持久化、其他组信息保留，以及过期版本拒绝。
4. **`check_space_sync_cleanup.py` 通过**：完整 Space 清理、Profile 类型 1…8、合法空配置、设备／组缺失、旧格式及拓扑边界。
5. **现场样本隔离复测通过**：以附件的 36 台节点、3 组和 Profile 为输入，构造两类历史状态（无待确认提交／已有 accepted 提交）；两者都选择本地 C003 `occupancyLevel=734`，旧确认时间不变，后续模拟正确上传读回后才确认。将云端时间在内存中设为更新的 09:46:40 后，选择云端 `414`，同样经过后续读回确认。网络、密钥解码与 App 存储为测试替身，局部持久化由上一条真实 SQLite 测试独立覆盖，不把模拟响应称为线上验收。
6. **SunSmart Debug generic iOS 构建通过**：`SunSmartLocal.xcworkspace`、`-sdk iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`；固定 DerivedData 为 `SunSmart-feat-timed-limited-261008`。首次沙盒调用因 Xcode 服务访问限制未启动构建，核对 workspace 后放开构建执行权限，实际编译输出 `BUILD SUCCEEDED`，退出码 0。未切换 workspace、执行 clean 或清理共享缓存。
7. **既有测试限制**：`check_proximity_scoped_import.py` 无法编译，原因是其 `Schedule` 替身缺少 `nodeSlots`。用脚本的 `--baseline` 在原始 HEAD 复核得到同样错误，未为此修改无关测试或业务代码。该脚本本轮不记为通过；相关成员／删除恢复由第 2、4 项覆盖。
8. **工作区检查**：`git diff --check` 通过，原始两份 JSON 的 SHA-256 与分析阶段一致。没有提交、推送或操作其他工作树。SDK realpath 为 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，工作树干净；没有 SDK 发布依赖。

## 最短人工验收

1. 安装本次构建后，在“空间 1vjj”点击一次 SYNC；以提供的时间顺序，预期保留本地 C003：734／100／T4=0／adjustSpeed=50／calibrationMode=none。
2. 检查云端读回这些值，36 台设备与组归属保持；退出重进，不再残留此次同步失败。
3. 再用 Web 对 C003 做一次更新并生成更大的 Space 时间，在 App 刷新／同步后确认整份 Profile 采用云端新值，其他本地配置不被覆盖。
4. 如仍失败，查看新的 DEBUG 状态中的 `lastSyncDiagnostic`、提交版本和基线摘要；同时核对日志是否已出现 `/sync/spaceprops` 及随后的成功读回。

上述是真机／服务器联调待验收项；未自动安装运行设备，也未把用户的“最新值已下发设备”规则当成当前灯光效果的自动化验证结果。
