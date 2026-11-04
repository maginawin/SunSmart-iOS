# G1 添加成员后 Space 同步失败：Scene 4 云端旧配置与基线冲突

日期：2026-11-04，时间均为 UTC+08:00。分析分支：`feat/device-scene-261028`，HEAD：`5511abc662335d55d9065910b7cae034168de20b`。开始时 App 工作树干净。初次完成只读分析；用户随后确认“云端 timestamp 更小时直接以本地覆盖”，已据此实施 App 修改。未操作线上 Space。

## 结论与未完成项

已按用户确认的规则修改：`remote.updateTimestamp < space.lastUpdate` 时，以完整本地 Space 配置准备覆盖上传，自动解除对应的历史冲突阻断；相等/更新云端沿用既有规则。原始样本的离线覆盖上传验证、恢复全套与相关回归及 SunSmart Debug generic iOS 构建通过。真实服务器保存、G1 图标刷新及设备下发仍待人工验收。

本例直接原因已定位：**上传前 GET 返回的 Scene 4 与 App 保存的已确认配置基线不同，触发 `baselineConfigurationMismatch`；重复遇到相同冲突后转为 `cloudBaselineNeedsReview / -2005`，新上传尚未发出就被停止。**

G1 Add Members 是触发核对的本地修改。生产比较器和状态机对照证明，保持云端节点“未入组”、保持云端旧时间不变，仅将云端 Scene 4 换成与已确认基线一致的版本，前置核对即可通过，本地两台设备的 G1 成员关系仍保留。因此不能把这次失败归因于 Add Members 没有写入 Group，或简单归因于本地/云端成员不一致。

云端 Scene 4 仍引用 L2 的旧实例：地址 `0032`、旧 Device Key 指纹；当前节点 L2 地址为 `003E`。本地 Scene 4 包含 L1、L2 的当前实例及新参数。这里存在真实配置差异，不属于空字段、默认值或排列顺序兼容问题。

**仍未查明的是旧云端内容的来源。** 两份快照没有 17:09:05 前后的 POST、回读 GET、完整基线原文及其建立来源，也没有现场 App 构建号。不能确定是旧客户端覆盖、服务端返回旧副本/未保存、不同写入口保留旧扩展，还是 App 历史确认/导入路径建立了不正确的基线。下述提交时间说明何时引入检测逻辑，不等于已经找到制造旧数据的提交。

## 输入与现场证据

- [服务器响应](</Users/maginawin/Desktop/server data 1714.json>)。
- [App 诊断导出](</Users/maginawin/Downloads/Space_Space 1_20261104_171243_831+0800.json>)，捕获时间 17:12:43。
- 导出中的 `_debugInspection.uploadable=false` 是诊断导出的格式声明；实际阻断依据是 `status.blockedReason`、持久化错误及对应生产控制流。

| 项目 | App 本地 | 服务器 |
| --- | --- | --- |
| 当前配置时间 | 17:11:19，`1793783479` | 16:04:04，`1793779444` |
| App 最后确认时间 | 17:09:05，`1793783345` | 当前 GET 早于该时间 65 分 01 秒 |
| 节点集合 | L1 `003B`、L2 `003E` | 相同 UUID、地址和 Device Key |
| 节点 Group | 两台均为 `C000`，`groupState=1` | 两台均为空，`groupState=0` |
| Group/Profile | 9 个 Group，包含 G1 | 原始对象完全一致 |
| 普通 Scene | 20 个 | 20 个；Scene 元数据相同 |
| Scene 扩展 | Scene 4 包含两个当前实例 | Scene 4 仅含 L2 的旧实例 |
| Schedule | 4 个；Schedule 1/2 已分配两台设备的 slot 0/1 | 相同计划；对应 nodeSlots 为空 |
| Switch | 2 个 | 原始对象完全一致 |
| 网络/App Key | 与服务器一致 | 不在本文记录密钥 |
| deviceCount | 2 | 1，但 nodes 实际有 2 台；计数字段过时，不是本次阻断判据 |

两台本地设备均已记录多处 `C000` Model 订阅，`restoreData.addGroupAddress=null`；本地也已有 Group 场景和 Scheduler 观测记录。这证明 App 已保存部分设备执行结果，不能据此认定所有 BLE 命令或设备实际状态均已验收。两边 `configComplete=false` 也不能单独解释本次云端失败。

Scene 4 的具体差异：

| 字段 | App 已保存的版本 | 服务器旧版本 |
| --- | --- | --- |
| revision | `EEBD5385-6924-4FCE-970E-37FDE9DFB5CC` | `9133A1BA-173F-4C1E-9F69-BD86957D58EE` |
| L1 | `003B`，6500 K，lightness=41287 | 不包含 |
| L2 | `003E`，2700 K，lightness=65535 | `0032`，4500 K，lightness=65535 |
| 实例身份 | 两个成员的 UUID/地址/Device Key 指纹均匹配当前 nodes | UUID 指向 L2，但地址和 Device Key 指纹均不匹配当前 L2 |
| 待执行操作 | 空 | 空 |

`spaceData` 的其他字段与其他 19 条 Scene 配置完全一致。Scene 4 的差异是有效成员、参数、revision 的变化，不可通过忽略 Scene 比较来消除。

导出诊断同时记录：

- `membershipPhase=joined`、`configurationInitialized=true`、`membershipNetworkMatches=true`。
- `recoveryPhase=active`、`recoveryAuthority=writable`、无密码待验证。
- `pendingUpload=false`、`pendingImport=false`、`pendingDeletionCleanup=false`，删除摘要为空。
- `baselineFields` 四项齐全，`removalSnapshotVersion=6` 与当前比较版本一致；`hasCompleteExportSnapshot=false`。
- 17:11:46：`lastBaselineDiagnostic.reason=baselineConfigurationMismatch`、`configurationMatches=false`。
- 同时：`lastReadbackDiagnostic.stage=baselineReconciliation`、`error=-2005`；数据库 `syncCloudError=-2005`，当前阻断原因为 `cloudBaselineNeedsReview`。

这些时间、错误和当前阻断相互吻合；不是单独拿一条历史诊断推断此次失败。也没有证据表明本轮是上一个删除操作的 HTTP 500/9999 或未确认上传回执问题。

## 生产比较器定位：冲突是 Scene 4，不是本次入组差异

使用本轮分析时的生产 `SpaceConfigurationIntegrityPolicy.configurationData`、`configurationsMatch` 和 `SpaceCloudNodeRemovalPolicy.Snapshot.make` 直接读取两份样本。摘要均为 SHA-256 前 8 字节，与导出字段的计算口径一致。

| 比较副本 | 逻辑配置摘要 | 完整快照 Space 属性摘要 |
| --- | --- | --- |
| App 导出记录的历史基线 | `e2c01d45616b84d3` | `27ada011477b6530` |
| 原服务器响应 | `9334b2266b1bce89` | `d1a14e133dc6b2a0` |
| 原本地导出 | `4fa14e79f79f28b9` | `d698abbda1fce1e4` |
| 服务器响应仅替换为本地 Scene 4 | **`e2c01d45616b84d3`** | **`27ada011477b6530`** |
| 本地导出仅换为服务器节点 | **`e2c01d45616b84d3`** | `d698abbda1fce1e4` |

第四行同时命中两种基线摘要，是已确认基线包含新版 Scene 4、入组前节点/日程状态的强定位证据。完整历史基线原文和 Scheduler/Timed 基线仍未包含在导出中，不能把重建副本称作从手机读取的完整历史记录。

## 修复前的调用链与两个同步提示

1. [GroupMembersViewController.swift](../SunSmart/Main/Group/Controller/GroupMembersViewController.swift) 的保存通过 `GroupMemberPersistence.commit` 持久化成员意图，配合 `TimedSchedulerBindings` 分配相关 Timed 绑定。
2. [ProximityLightingLifecycleCoordinator.swift](../SunSmart/Main/Group/Model/ProximityLightingLifecycleCoordinator.swift) 接收 `hasAdditionalLogicalChange=true`，执行 `markLocalChangePendingCloudSync()`；随后成员页面进入 `.group(...)` 设备同步。
3. [CloudSynchronizationManager.swift](../SunSmart/Common/Cloud/CloudSynchronizationManager.swift) 在构造新上传 API 前执行 `SpaceConfigurationSafety.resumeUpload`。没有 pending submission，但存在本地修改和已确认基线时，先 GET 当前 Space。
4. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 的 `reconcileOlderCloudBaseline` 发现 `remoteTimestamp < lastUploadCloudTimestamp`，使用历史 `authorizationBaseline` 比较 GET，不是拿当前入组后的本地配置直接要求相等。
5. 网络身份与基本载荷检查通过后，Scene 4 导致 `configurationsMatch(reference, actual)=false`。第一次返回未确认错误；相同本地版本、远端内容及基线再次失败后，记录 `cloudBaselineNeedsReview` 和 `configurationReviewRequired(-2005)`。
6. 此时还没有进入 Scheduler/Timed 基线比较，没有准备新的 submission，也没有发送本轮 POST。日程绑定、节点参数/订阅变化属于正常本地待上传内容，不是这次最先失败的比较项。
7. [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的 `updateSyncState → showConfigurationRecovery` 因 Space 已阻断，在标题栏展示失败，并使用 `Synchronization failure` 标题。这是配置审核恢复入口，不是某条 Mesh 命令失败的定位信息。
8. [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift) 的 `computeNeedSyncGroup` 在 `configurationAvailable=false` 时直接返回 true；批量读取路径 [NodeSyncStatusRefresh.swift](../SunSmart/Common/Data/NodeSyncStatusRefresh.swift) 也对不可用输入返回待同步。因此 Space 冲突足以让 G1 持续显示待同步。解除冲突后必须重新计算，才能判断是否还有真实设备任务。

继续点击普通同步会再次遇到同一旧快照。隐藏 G1 图标、清空错误、重置 Group 状态，均无法解决基线冲突。

## 在什么时候引入

以下为 Git 可核实的代码引入时间，列 Commit 时间；与 Author 时间不同处另注。

| 提交 | 时间 | 作用与边界 |
| --- | --- | --- |
| `d4e4e436`，`fix: space trigger zone sync issues` | 2026-09-07 15:01:04 | 引入配置不可用时将 Group 判为待同步的保护行为。不是本次云端旧 Scene 数据的来源证明。 |
| `504eefb1`，`fix: wil sync issues` | 2026-10-13 09:15:03；Author 09:07:25 | 引入 `reconcileOlderCloudBaseline`、`baselineConfigurationMismatch` 和重复冲突后 `cloudBaselineNeedsReview`。其目的包括允许“云端时间旧、但内容与已确认基线一致”的合法本地修改继续上传。 |
| `c1a7bd2a`，`feat: device scene` | **2026-10-31 13:53:45**；Author 10-30 08:12:10 | 将普通 Scene 元数据、Group Scene 参数和 `sceneConfigurations` 纳入逻辑基线及回读比较。本例的 Scene 4 差异从此成为该比较路径的阻断条件。 |

因此，若问“当前 Scene 冲突为何开始被检测”，对应 Device Scene 提交 `c1a7bd2a`；若问“重复后为何锁定并提示同步失败”，对应 `504eefb1`。**尚不能回答旧 Scene 内容究竟由哪个提交或外部写入产生，也不能把检测出真实差异本身认定为比较器 bug。**

本次没有证据把问题归到 11 月 4 日的 Group 成员持久化修复。现场最晚在 17:11:46 已进入审核状态；17:09:05 的基线建立方式和安装构建需要额外证据。

## 离线因果复现与边界

临时探针：`/tmp/g1_sample_probe.py`、`/tmp/g1_sample_probe.swift`。复用 `scripts/check_space_recovery_receipts.py`，编译生产比较策略与恢复方法，执行真实临时恢复文件读写；原始样本只读，未写入仓库。命令：

```sh
python3 /tmp/g1_sample_probe.py --g1-probe
```

| 对照 | 结果 |
| --- | --- |
| 原服务器响应，按命中摘要的副本重建基线，首次 `resumeUpload` | `configurationUploadUnconfirmed`，未锁定，POST=0 |
| 相同输入再次 `resumeUpload` | `configurationReviewRequired`，`cloudBaselineNeedsReview=true`，POST=0 |
| 仅纠正内存响应中的 Scene 4，保留旧时间、未入组节点及空 nodeSlots | `resumeUpload` 成功，冲突标记清除；本地两节点仍属于 `C000`，POST=0 |
| 原冲突状态打开现有审核预览 | 可生成预览，但摘要只显示本地 2 / 云端 2 和通用替换说明，未指出 Scene 4 差异 |
| 原冲突通过现有 `authorizeLocalRecovery` 明确选择本机版本 | 解除阻断，保留本地 Group/Scene/Timed，后续前置核对通过 |
| 之后模拟一次 POST 成功及同配置 GET 回读 | 1 次 POST，确认成功，dirty=false、pending=false |

以上断言全部通过。状态机夹具中的完整历史基线以摘要匹配副本重建，Timed/Model 基线取入组前服务器内容；不是手机完整基线实测。网络、App SQLite、Mesh 加载和网络密钥加载沿用明确测试替身；密钥对象相等和 Scene 实例指纹已另行按生产算法核对。最后一行使用服务器回传提交内容的模拟响应，不能证明真实服务器会保存。

初次分析阶段未构建或运行完整回归；后续实施验证见下文。全程未运行真机、未发起线上请求。

## 用户确认的简化规则与实施

用户明确要求：云端 `updateTimestamp < App.lastUpdate` 时，使用 App 本地完整 Space 配置覆盖云端。该决定取代初次逐项审核建议，不增加 Scene 差异 UI 或新恢复机制。

- `SpaceConfigurationSafety.swift`：较旧云端不能通过历史冲突标记反向取得配置优先权；旧云端内容无需再等于历史基线。复用现有备份、恢复回执和本地待上传标记，保留完整本地节点、Group、Scene、Timed 等配置，清除可替代的云端冲突标记。
- `ImportData.swift`：普通 GET 导入入口先判断本地是否较新，保留本地数据并准备下一次上传；较旧远端的业务字段缺失或差异不再阻止较新本地替换。
- `CloudSynchronizationManager.swift` 与离开前上传入口：上传准备阶段允许用新提交替换历史 pending 回执；POST 后仍按现有回读验证。较旧且内容不符的回读保留失败和重试状态，不把“选择本地”当成“服务器已保存”。
- 继续检查当前账号/角色、Space 与网络密钥身份、本地可完整导出、尚未完成的导入/设备删除/成员事务、取消及迟到响应。导出后的再次检查覆盖期间发生的删除或状态变化。权限恢复所要求的完整导入仍由既有流程处理。
- 不新增业务持久字段或文件类型，复用 `before-local-recovery-*.json`、`localReplacementVersion`、`prefersLocalMembership` 和 `spaceConfigurationLocalRecoveryPending`。确认版本只有实际上传回读或既有权威导入完成后推进。

这一策略以 Space 时间为完整配置的取舍依据：云端时间较小时，其中不同的 Group、Scene、Timed 或设备实例都会被本地版本覆盖；不再逐字段合并。这正是本轮用户确认的行为变更。相同时间的云端选择规则未改。

### 验证记录

| 验证 | 结果与边界 |
| --- | --- |
| 新增 `NewerLocalConfigurationTests.swift`，`--newer-local` | 通过。旧 Scene、入组差异、历史阻断、合法空 Space、本地已确认但云端回退、远端时间介于确认与当前版本之间、prepared/accepted 回执、旧 GET 失败后重试；权限、网络身份、非法本地数据、保存失败、取消和导出期间状态变化。 |
| 用户两份原始 JSON：`python3 /tmp/g1_newer_local_probe.py --g1-current` | 通过。保留 L1/L2 的 `C000` 和完整本地配置，解除 `cloudBaselineNeedsReview`，一次 POST 后模拟匹配 GET 完成。样本未复制进仓库；Mesh/数据库/HTTP 采用既有夹具替身，网络身份装载使用替身；生产 JSON 比较、回执文件和状态流程真实执行。 |
| `scripts/check_space_recovery_receipts.py` 全套 | 通过。旧测试中“时间较旧仍采用云端”的预期按新规则更新；同版本/较新云端、低层删除证明比较、显式恢复、权限、失败/重启和回读校验继续验证。 |
| `scripts/check_space_membership_lifecycle.py` | 通过；真实成员记录与流程，SDK/HTTP/App DB 为测试边界。 |
| `scripts/check_space_protection_snapshot.py` | 通过；真实保护文件、损坏/权限、失效和 pending 边界。 |
| `scripts/check_sync_preparation.py` | 通过；共享访问策略、Gateway 上下文、页面准备/取消/重试。 |
| `scripts/check_space_sync_cleanup.py` | 通过；完整快照清理、Profile、合法空值、兼容与幂等性。 |
| SunSmart Debug generic iOS | `BUILD SUCCEEDED`。`SunSmartLocal.xcworkspace`，`-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`；未安装或运行设备。首次沙箱内 Xcode 服务访问失败并误报 workspace 无效，沙箱外同命令成功。 |

`git diff --check` 通过。全套测试通过后未再修改生产代码，构建结果仍适用于当前实现。

本次为共享 App 同步逻辑，影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；无品牌条件、资源、项目配置或 SDK API 变更，使用 SunSmart 代表构建。离线测试使用真实恢复文件/UserDefaults 与生产序列化/比较，App SQLite/完整 Mesh 装载/服务器持久化为明确未覆盖边界。

### 最短人工验收

1. 使用本次构建打开原 Space，确认 G1 保留 L1 `003B` / L2 `003E`，Scene 4 保留本地两个当前实例与参数，点击标题栏同步。
2. 确认成功上传后 get spaceprops 返回本地 G1、Scene 4 和 Timed 绑定；若仍返回旧配置，App 应继续保留失败/待上传，不能只因 POST 成功就清除。
3. 退出重进并重启 App，确认配置不回退；检查 G1 待同步状态。若仍有设备任务，执行设备同步并核对回执；云端成功不能单独证明 Mesh 下发完成。

### 当前工作树与交接

分支/HEAD 与开头一致，未提交或推送。业务代码仅改上述 3 个 App 文件，新增一组定向测试并更新现有冲突/Timed/默认恢复测试预期，沿用已有脚本。未修改输入文件、SDK、服务器或固件。

构建 SDK realpath：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `dbcf6f1a7014320331f3cccdc0a46edc1a0baa88`。构建使用其他任务已有的 MeshFastAddDeviceManager、MeshMessageManager、MeshProxyMessageCommand、MeshAPI、SchedulerActionStatus 未提交修改；构建前后逐文件 SHA-256 相同。本任务没有写入或清理共享 SDK。DerivedData：`/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-cli`。

旧云端数据的写入来源仍需历史 POST/GET 和现场构建号才能进一步归属；本次修复完成用户确认的 App 版本取舍策略，不声称已修改服务端的数据产生原因。
