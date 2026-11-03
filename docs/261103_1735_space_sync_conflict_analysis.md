# 空间 1 同步冲突、添加设备受限的原因与修复方案

日期：2026-11-03（UTC+08:00）。本轮仅分析、离线复现和规划，未修改业务代码。

## 结论

1. Space `DB59BDEA-9338-43FF-A7B5-B8383FF8DE0A` 卡在“上传已接受，回读未确认”。当前阻断原因是 `cloudConfigurationConflict`，失败位置是 `sameVersionRemoval.notOnlyNodeRemoval`，错误码 `-2005`。
2. 本地 7 个节点，云端 6 个节点，唯一缺少的是 L1（`49C9`）。用户已确认该设备曾主动删除，应以删除结果为准。云端节点集合与本地剩余节点的 UUID、地址和 Device Key 身份相符。
3. 当前比较规则存在两类兼容缺口：空 `sceneConfigurations` 与字段缺失不等价；节点完整快照仍把若干可选字段/服务端默认值差异计入冲突。样本还有非零参数、色温范围缺失等差异，不能全部当成无害默认值忽略。
4. 添加设备被禁用是同一保护状态的结果，不是独立的设备数量上限或 Owner 权限故障。修复不能直接放开添加按钮。
5. 必须同时修复已有冲突的恢复入口：当前同版本“重新加载云端数据”没有记录明确的云端选择，仍可能被原来的成员协调分支挡回。

## 输入、状态与证据

分析输入：

- `/Users/maginawin/Desktop/enter space logs.txt`
- `/Users/maginawin/Downloads/Space_空间 1_20261103_172641_437+0800.json`
- `/Users/maginawin/Desktop/server data.txt`

文档只记录状态、字段名称和设备地址，不复制凭据或密钥。

| 项目 | 本地/日志证据 | 含义 |
| --- | --- | --- |
| 最近确认时间 | `1793686657`，11 月 3 日 14:17:37 | 仍未确认后续版本 |
| 本地与云端版本 | 均为 `1793697109`，17:11:49 | 不能仅凭时间戳相同宣告同步成功 |
| 提交状态 | `submissionPhase=accepted`、`pendingUpload=true` | 上传请求已接受，内容回读尚未通过 |
| 最近诊断 | 17:26:22，`membershipReconciliation / notOnlyNodeRemoval` | 持续重试同一失败路径 |
| 权限/生命周期 | Owner；`joined`、`configurationInitialized=true`、`active`、`writable` | 不是访客、未初始化或退出中的限制 |
| 网络身份 | 本地、云端 NetKey/AppKey 内容相同；提交密钥匹配状态为 true | 样本没有网络身份变更证据 |
| 本地偏好 | `prefersLocalMembership=true` | 保留了本地优先状态；不能把它当成恢复已删除 L1 的理由 |
| 删除日志 | 只有 `49C6` 的 `localDeletion / cleaned`，14:20:13；`pendingDeletionCleanup=false` | 该记录不是缺少的 `49C9`，L1 尚未完成云端删除清理 |
| 云端计数 | `deviceCount=7`，但 `nodes.count=6` | 计数字段滞后，应按实际节点实例集合判断删除 |

进入日志第 119～128 行和第 604～613 行均显示 HTTP 200 后立即报上述配置冲突。后面的 BLE 连接超时不解释这次云端回读失败，也不是禁止添加设备的直接依据。

## 完整触发链

`进入 Space / 自动同步 / 重试` → `SpaceConfigurationSafety.resumeUpload` → GET `spaceprops` → 已接受的提交遇到较小的云端节点集合 → `reconcileSameVersionNodeRemoval` → `Snapshot.removals` 或旧回执配置投影校验不通过 → 持久化 `cloudConfigurationConflict` → 回读提前返回，提交仍为 `accepted`。

随后产生两种 UI 结果：

- `SpaceData.needUploadCloud` 仍为 true，且 `hasPendingUpload` 为 true；`showSyncCloudError`、Space 列表和导航栏继续显示同步失败/待核对。
- `SpaceData.deviceOperates` 在 `isBlocked` 时最多返回 `.control`，不包含 `.add`。灯具、传感器、开关、其他设备、网关、消防控制器和 Group 内添加入口都依赖这个共享判断。Group、Scene 编辑及部分日程操作也会受同一保护影响。

源文件：`SunSmart/Common/Data/SpaceConfigurationSafety.swift`、`SpaceConfigurationIntegrityPolicy.swift`、`SpaceData.swift`，以及 `SunSmart/Main/Space/Controller/SpaceViewController.swift`、`SunSmart/Main/Space/View/SpacesViewCell.swift`。

## 哪些差异造成比较失败

### Scene 空扩展不兼容

本地 `spaceData` 含 `sceneConfigurations: []`，服务端未返回此字段。两边的 4 条 Scene 元数据一致。

`SceneConfigurationPayload.decode` 对缺失和空数组都解码为空配置；但 `Snapshot.make` 和普通 `configurationData` 仅在原始字段存在时写入比较对象，因此同一个空配置得到不同比较结果。现有空值归一化只照顾部分旧基线升级分支，未覆盖普通新提交及其回读。

本地还有 `sceneDisplayOrder`，云端未返回，但当前 `SceneDisplayOrder.excludingFromComparison` 已排除它；排序字段不是本次快照属性差异的原因。

### 节点比较还存在多种差异

以当前 `comparisonNode` 规则归一化后，6 个共同节点的哈希全部不同。差异包括：

| 类型 | 样本例子 | 修复边界 |
| --- | --- | --- |
| 无组的表示差异 | SW1 本地缺 `groupAddress`，云端为 `""` | 与现有逻辑配置归一化保持一致 |
| 空值/默认值差异 | `enOceanMacAddress=""`、`enOceanKeyScenes=[]`、`custProps={}`、`pirEnabled=null`；部分字段由缺失变为 0/false | 按导入导出和 SDK 语义逐项确认，不通用删除所有 0/false/null |
| 非零差异 | 多个节点云端 `calibrationRatedPower=62258`，本地未导出 | 不能直接判为默认值；保留诊断和核对 |
| 有效参数缺失 | L5（`49AB`）本地色温范围 2700～5000 K，云端缺少范围字段 | 不得为识别删除而无条件忽略配置丢失 |

完整导入会重新解码云端节点，因此“重新加载云端”可能替换其他节点的本地缓存参数；用户确认 L1 已删除，不等于确认所有参数差异都可覆盖。恢复预览应说明这一点。

### 离线复现与证据限制

复用了 `scripts/check_space_recovery_receipts.py` 的编译依赖和生产比较函数，在 `/private/tmp/space_261103_comparison_probe.py` 中建立临时探针，没有修改仓库测试或生产代码。

| 输入变体 | Space 属性比较 | 共同节点哈希 | 删除判定 | 删除投影后逻辑配置 |
| --- | --- | --- | --- | --- |
| 原样本 | 不同 | 0/6 相同 | 拒绝 | 不同 |
| 仅给云端补空 Scene 扩展 | 相同 | 0/6 相同 | 拒绝 | 相同 |
| 仅用本地对应节点内容替换云端共同节点内容 | 不同 | 6/6 相同 | 拒绝 | 不同 |
| 上述两个变化同时存在 | 相同 | 6/6 相同 | 接受 | 相同 |

后两项只是隔离变量的诊断，不是建议改写服务端响应或忽略节点差异。按当前样本重建 accepted 回执，实际 `resumeUpload` 返回 `configurationReviewRequired`，保护状态与待提交状态都保留，本地仍为 7 节点。

导出只带原提交的摘要，不含完整不可变回执/删除快照；当前导出的逻辑配置摘要与记录的提交摘要也不相同。因此上述复现能证明当前数据的独立阻断因素，不能声称逐字段还原了 17:11:49 的原始 POST，或精确确定该回执最先不匹配的字段。若实施时需要迁移原回执，必须使用设备内保存的同一代 `last-complete-export.json`，不能用当前导出替代历史证明。

## 什么时候引入

下表是当前分支 Git 历史中的代码引入时间，不是已发布 App 的上线时间。

| 提交 | 时间（UTC+08:00） | 与本问题的关系 |
| --- | --- | --- |
| `153bc667e` — `fix: llh sync issues` | Commit：2026-10-28 13:52:34；Author：12:23:24 | 新增完整属性/节点哈希 `Snapshot`，并在上传回读和普通导入之前调用 `reconcileSameVersionNodeRemoval`。原先依赖成员身份、逻辑配置和 Scheduler 的路径开始被完整字段差异提前否决，是本次 `sameVersionRemoval.notOnlyNodeRemoval` 问题的起点。 |
| `1e1c7b9a8` — `fix: llh sync issues` | 2026-10-28 15:02:11 | 补充遥测排除和一部分默认字段归一化，但未覆盖本样本的多种节点表示差异。 |
| `c1a7bd2ac` — `feat: device scene` | Commit：2026-10-31 13:53:45；Author：2026-10-30 08:12:10 | 开始导出 `sceneConfigurations`，并纳入比较。由此新增“空数组与旧服务端缺字段”这一独立阻断条件。 |
| `5aece5255` — `feat: add scene order` | 2026-11-02 20:21:09 | 将比较格式升到 v4 并排除 Scene 排序字段；不是本次空 Scene 扩展问题的起点。 |

因此不能把所有问题都归到今天的 Scene 删除提交。主体来自 10 月 28 日的同步保护变更，Device Scene 提交又叠加了空扩展兼容问题。现场具体从哪个已安装构建开始出现，现有文件没有构建号和原始提交请求，不能确定。

## 恢复入口的关联缺口

`showConfigurationRecovery` 仅在 `cloudBaselineNeedsReview` 时准备 `CloudBaselineReview`；本样本原因是 `cloudConfigurationConflict`，所以 review 为 nil。

`reloadConfigurationFromCloud` 只有 review 非 nil 才调用 `prepareReviewedCloudImport`；否则直接 `restoreConfiguration(authoritativeGET: true)`。这个参数并不自动把同版本导入变成用户审核过的覆盖。

本样本云端时间等于本地时间，不符合“更高版本云端导入”。`activateImport` 对 active 状态也不会清除旧回执。于是 `update` 再次调用 `reconcileSameVersionNodeRemoval`，返回 `.preserved("sameVersionNodeRemovalNeedsReview")`。临时夹具执行生产 `update` 的导入准备段已复现此返回，且 blocked/pending 均仍为 true；未运行完整 UIKit 恢复交互或真实数据库导入。需要修复这条入口，不能仅建议用户不停点“同步”或“重新加载”。

## 建议实施方案

### 1. 修复共享比较语义

- 在现有 Scene codec/配置比较机制内统一“缺失”和“合法空 Scene 扩展”，同时覆盖删除快照、正常回读和持久回执比较。不新增另一套并行配置模型。
- 仅当对应配置确实为空才允许等价；非空配置、成员、pending operation、revision 或 tombstone 丢失仍须拒绝。显式清空与未知格式不能被通用空值规则吞掉。
- 按现有导入、导出和 SDK 默认语义补齐节点可选字段规则，优先复用已存在的 `groupAddress` 等归一化。不能直接把完整节点比较替换成只比较 UUID/地址，也不能无差别忽略非零参数或参数缺失。
- 比较格式升级，并按 Space、时间戳、节点身份、网络身份匹配的保存快照重建旧哈希。没有准确原始证明时保留状态并进入可完成的审核恢复，不拿当前导出“补造”已接受回执。

### 2. 修复同版本冲突的“采用云端”恢复

- 扩展现有 `CloudBaselineReview`、`prepareReviewedCloudImport` 和 `reviewed-cloud-import.json` 流程，支持同版本 `cloudConfigurationConflict` 及 accepted 回执；不要另建恢复存储或绕开普通权限检查。
- 在现有恢复 UI 中展示本地 7 / 云端 6，以及拟删除的 L1（49C9）。保留其他参数差异的提示；只有用户在 App 明确选择采用云端完整配置，才执行完整导入。不能把普通后台 GET 当成该授权。
- 先复核网络身份、角色、当前本地版本和刚获取的云端版本，保存检查点与选定快照，再使旧上传回调失效；导入失败保留可重试的选择和备份，成功后才清理旧 submission、`prefersLocalMembership`、冲突标记及相关旧删除回执。
- 针对本 Space，以已确认的删除结果为验收目标：L1 不复活，保留云端其他 6 个节点。不能通过“使用本机数据”把 7 节点版本重新上传来解锁。
- 导入完成后的新编辑、添加设备和后续回读应持续正常，避免只短暂清除红色提示；本地缓存字段如需重新读取设备，单独列为运行验收。

选择此方案的原因：仅补空 Scene 字段仍会被 6 个节点哈希差异阻断；仅补默认值仍不能证明非零参数和有效范围缺失无害；直接移除保护或全量采用本地有复活 L1/覆盖他人修改的风险。复用明确云端选择，可以在保留严格自动冲突规则的同时恢复存量 Space。

### 3. 状态刷新与诊断

- 保持 `deviceOperates`/`canEditing` 的共享权限入口。恢复成功后通过现有刷新机制更新所有设备类别、Group 和 Scene 页面；不对单页添加按钮特判。
- 把笼统的 `notOnlyNodeRemoval` 细分为身份、Space 属性、节点字段、逻辑配置、Timed、Scheduler 等诊断阶段。仅 DEBUG 输出字段路径/计数/原因，不输出密钥或完整原始 payload。
- 诊断导出增加删除快照比较版本、可用性和安全摘要，便于区分“旧哈希未升级”与“当前数据确有差异”。

## 验证与实施边界

本次必须新增或扩展行为夹具：

- 用脱敏样本复现 7→6、accepted 回执、相同时间戳、旧本地优先状态、无关的已清理删除记录，以及空 Scene 扩展/节点默认字段差异。
- 纯合法编码差异能自动收敛；真实非空 Scene 丢失、非默认参数变化、不同 Device Key、地址复用、未知 POST 结果、撤权和陈旧响应仍受保护。
- 显式云端选择可以完成同版本恢复；取消保持原状，落盘失败和重启可重试，晚到上传回调不能恢复旧 7 节点提交。
- 老比较格式有准确保存快照时可迁移；快照缺失或不是同一代时不得自动删除。
- 恢复后重复进入、再次同步、新增一个设备及其首次上传回读都正常；L1 始终不被重新创建。

优先复用 `check_space_recovery_receipts.py`、`check_space_membership_lifecycle.py`、`check_space_protection_snapshot.py`、`check_space_sync_cleanup.py`，根据最终修改补选 Scene round-trip/删除清理回归。生产 Swift 修改后构建一次本地 workspace 的 SunSmart Debug generic iOS，禁止把隔离测试或编译当成真实云端/设备验收。

共享逻辑影响五个品牌；当前方案不修改品牌资源、依赖或 SDK API。若增加恢复文案，补 English/简体中文并核对各品牌资源归属。只实施 App；不修改服务端、固件或其配置。

服务端联调需要核对：`spaceData.sceneConfigurations` 非空时必须完整保存并回读；节点完整删除结果与字段默认/缺失语义应稳定。现有证据仅显示本次空扩展未返回，不能据此断言服务端会丢弃非空 Scene。非空场景的真实往返必须作为发布验证，不能用放宽 App 比较掩盖服务端数据丢失。

## 当前工作状态

- 分支：`feat/device-scene-261028`；分析基准 HEAD：`fa78db909112ac1f2051b79b55e0655a201abc14`。
- 本地 SDK 映射到 `nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `dbcf6f1`。分析期间 SDK 与 Scene 删除/同步文件存在其他任务未提交修改，均未改动；本任务调查的核心比较和恢复文件无未提交差异。
- 已完成：三份证据对照、共享 UI 权限链追踪、提交差异定位、当前生产比较函数、accepted 回读及同版本导入准备被拦截的离线复现。文档已检查空白格式及敏感值，无完整密钥记录。
- 未执行：业务修复、完整 App 构建、设备运行、真实云端写入/回读。临时夹具的 SDK、数据库和网络均有边界替身；不能当作完整导入成功的证据。
- 后续：确认上述方案后实施。优先补复现与同版本恢复，再修改比较逻辑及历史状态迁移，最后做对应回归和人工验收。
