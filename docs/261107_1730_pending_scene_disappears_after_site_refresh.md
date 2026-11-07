# Site 刷新后待删除场景消失：原因与修复方案

日期：2026-11-07。分析完成后，用户确认实施，并明确调整：统一列表与数量，不新增导入读回检查，不增加针对服务器数据问题的 App 兜底。实施范围限 App；不操作真机或服务器。

## 结论与未完成项

问题发生在 App 的场景导入和恢复策略：云端及 App `sceneInfos` 已保存待删除状态和未完成任务，但完整导入会移除全部 SDK Scene，再跳过 `isDeleting == true` 的场景。场景列表和数量却依赖 SDK Scene，因此待删除场景被隐藏、数量减少。普通 Space 重载也刻意跳过缺失的待删除 Scene，不能自行恢复展示。

进入同步页时，`prepareDeletionRetries()` 会重新创建用于删除重试的 Scene 对象。这解释了新建场景、进入同步流程后，旧的待删除场景又出现。恢复不应依赖这个无关操作。

建议保留“待删除场景不可执行、不可建立新引用”的限制，同时让其在导入、退出重进、重启后持续可见，并能沿现有入口继续删除。复用 `sceneInfos` 和既有删除任务，不新增持久状态，不修改数据库或 export JSON 结构；当前没有发现需要 SDK 新 API、服务器或固件配套修改的依据。

已按用户调整完成 App 修改、相关离线回归及 SunSmart Debug generic iPhoneOS 构建。真实 Scene Delete 回执、L2 寄存器最终清理和 UIKit 完整操作路径仍待人工验收，详见文末。

## 工作区与证据范围

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028`。
- 分支：`feat/device-scene-261028`；HEAD：`b5d11011b2e84a60741346b08dc85def7b62f127`。
- 开始分析时已有暂存改动：`SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved`；本轮保留，未写入。
- `SunSmartLocal.xcworkspace` 的 `.local-sdk/nordic-sig-mesh-sdk` 实际指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`。
- SDK HEAD：`8f62e8aafeda0c5d9ac678f085c589da99e17e26`；检查时无未提交改动；本轮只读。
- 上述 revision 是本次检查的工作区状态。现场 App 的实际构建 revision 未提供，不能据此认定两者完全一致。
- 证据为用户给出的六份 App export JSON、三份 `get spaceprops` 响应及当前源码；未提供对应 Mesh 收发日志。文档不复制凭据、设备密钥或完整身份指纹。

## 现场快照对比

App 文件均位于 `/Users/maginawin/Downloads/`，前缀为 `Space_Space 1_20261107_`；服务器文件位于 `/Users/maginawin/Desktop/`。

| 文件时间/后缀 | export `scenes` / `sceneConfigurations` | 原始 App `sceneInfos` | 原始 SDK `scenes` | Space 保存的场景数 | 关键记录 |
| --- | ---: | ---: | ---: | ---: | --- |
| `171642_687+0800.json` | 12 / 12 | 12 | 12 | 12 | `000B`“场景 1”已待删除；`000C` 同名且正常 |
| `171817_086+0800.json` | 11 / 11 | 11 | 11 | 11 | `000B` 待删除；`000C` 已不存在 |
| `172106_641+0800.json` | 11 / 11 | 11 | 10 | 10 | `000B` 的 App 记录仍在，SDK Scene 消失 |
| `172229_658+0800.json` | 12 / 12 | 12 | 12 | 12 | `000B` SDK Scene 恢复；新 `000C` 名称为 `Scene 11` |
| `172346_420+0800.json` | 12 / 12 | 12 | 12 | 12 | `000B`、`000C` 均待删除 |
| `172525_765+0800.json` | 12 / 12 | 12 | 10 | 10 | 两条 App 待删除记录仍在，两条 SDK Scene 均消失 |

上述原始记录分别来自 `_debugInspection.spaces[0].rawLocal.app.sceneInfos`、`.mesh.scenes` 及 `.app.spaces[].sceneNumber`；export 配置来自 `spaces[0]`。

三份服务器响应：

| 文件 | 场景数 | 待删除场景 | updateTimestamp |
| --- | ---: | --- | ---: |
| `server data 1720.txt` | 11 | `000B` | 1794043080 |
| `server data 1724.txt` | 12 | `000B`、`000C` | 1794043381 |
| `server data 1725.txt` | 12 | `000B`、`000C` | 1794043381 |

已用程序断言核对：

1. `171817 → 172106` 的 export 场景元数据、配置、显示顺序完全保持；与 `1720` 服务器响应的相应记录一致。原始 `sceneInfos` 中 `000B` 的配置未改变，SDK 仅少了 `000B`。
2. `172346 → 172525` 同样保持 export 配置和任务；与 `1725` 相应记录一致。SDK 仅少了 `000B`、`000C`。
3. `1724` 与 `1725` 两份服务器响应按 JSON 对象比较完全相等。

待删除记录仍保存 `isDeleting=true`、针对 L2（地址 `0013`）的 `pendingOperations.action=remove`，以及一条 Scheduler 引用检查任务。`revision`、operation `generation`、设备身份及任务内容在两次刷新前后保持。Scheduler 任务的 `slots=[]` 不能直接解释为已经清理完成；`deletionReferences.pending` 仍非空。

L2 的 App/云端 `scenesDatas` 缓存仍含对应场景号。这与存在未完成清理相符，但缓存不是当时设备寄存器的实时读取结果；无法仅据此确认实际 Scene Delete 是否到达设备。

### 第一份文件与口述步骤的差异

第一份文件已经有两个同名“场景 1”：`000B` 待删除，`000C` 正常；不是一条刚建立的“场景 1”。第二份文件中 `000C` 连同相关缓存已经消失，只剩原来的 `000B` 待删除。后续 `Scene 11` 又使用 `000C`。

因此不能把第一至第二份之间的变化直接描述成“唯一的新场景删除失败”。缺少对应设备回执和操作日志，无法判断 `000C` 当时为何完成了本地移除，亦不能确认“离线后肯定没有任何成功回执”。此差异单独保留，不扩大为另一个未经证明的修复目标。两次 Site 刷新导致待删除 Scene 被隐藏的证据完整，不依赖这处不确定性。

## 修复前源码触发链（分析时 HEAD）

### 1. 刷新执行完整配置导入，相同时间戳也可进入

`SiteViewController.performSiteLoad` 请求 Site 数据，调用 `site.update(..., source: .completeDetail)`；`ImportData.swift` 的 Site 更新对 Space 调用 `SpaceData.import`，进入配置恢复/导入。

`ImportData.swift:2258` 附近的 `shouldApplyServerData` 接受 `lastUpdate >= self.lastUpdate`。因此服务器数据未变化、时间戳相同，也能再次触发此问题。不应通过禁止相同版本导入掩盖问题，因为首次导入、其他客户端导入和本地恢复仍需要正确处理待删除场景。

### 2. 导入保留 App 删除记录，却排除对应 SDK Scene

`ImportData.swift:2731–2757`：

- `network.forceRemove` 移除现有 SDK Scenes。
- `SceneConfigurationStore.importRecords` 将所有传入配置写入 App `sceneInfos`，包括待删除记录。
- 重建 Scene 时在 `record.configuration?.isDeleting != true` 处跳过待删除场景。
- `ImportData.swift:2920` 用过滤后的 `scenes.count` 保存 `self.sceneCount`。

SDK 的 `forceRemove(scene:)` 会删除本地 Scene 行；`add(scene:)` 会保存本地 Scene。它们在此处属于本地模型/持久化操作，不等于向 L2 发送 Scene Delete 或 Store。

### 3. UI 与数量读取 SDK 列表，因而看不到 App 中保留的任务

- `ScenesViewController.visibleScenes`（约 159 行）只读取 `MeshNetworkManager.instance.scenes`，没有补入仅存于 `sceneInfos` 的待删除记录。
- 同控制器的刷新通知和 UI 更新会将列表数量再次写回 Space。
- `SpaceViewController.refreshSummaryCountsFromSpaceMesh`（约 129 行）及其他摘要更新也以 SDK scenes 数量为准。
- `SpacesViewCell`（72 行）直接展示 `space.sceneCount`。
- `ScenesViewCell`（28 行）已实现“待删除”文案，`SceneViewController` 与列表删除入口也已支持继续删除；缺少的是承载这些入口的 Scene 对象。

### 4. 普通重载无法恢复，进入同步页才恢复

`MeshNetwork+SunSmart.loadExtensionData` 调用 `restoreSceneProjections()`。该函数在 `SceneConfigurationStore.swift:753–756` 遇到“待删除且 SDK Scene 不存在”时直接跳过；内部 `project` 在约 802 行也只允许 `deletionRetry=true` 创建这类缺失对象。

`SyncDevicesViewController.buildPreparedTaskPlan` 在约 278 行调用 `prepareDeletionRetries()`；后者从 App 行读取所有待删除场景，用 `project(..., deletionRetry: true)` 恢复对象，保留原配置和任务。

`SceneSettingsViewController.openSyncPage` 在新场景保存后进入这个同步准备入口。因此现有代码能解释“新增场景流程后旧待删除场景出现”，更准确的触发点是进入同步准备，而非创建本身或 L2 上线必然恢复了它。由于该准备会检查所有待删除记录，即使本次同步目标是新场景，也可能重新显示旧记录。

### 5. 现有导入读回检查和测试没有覆盖显示要求

`SceneConfigurationStore.exportRecords` 合并 SDK Scene 与 App 行，App 配置优先。因此 SDK 少一条待删除 Scene 时，export JSON 仍可以完整，`ImportData.swift:2958` 的配置读回比较也可通过；这证明配置保留，不证明列表完整或删除入口可达。

`Tests/Scene/SceneDeletionFlowTests.swift:202–218` 明确断言：缺失 SDK Scene 的待删除记录经过普通恢复后，SDK 列表仍为空；再显式调用 `prepareDeletionRetries` 才恢复。这一测试预期和用户要求的持续展示不一致。已有 round-trip/SQLite 测试主要验证任务持久性及显式重试，没有覆盖“完整导入 → Site 数量 → 普通进入 Space → 待删除卡片 → 原入口重试”。

## 不符合预期的行为和影响

1. 物理清理未完成，Site 数量从 11/12 变成 10，和保留的配置记录不一致。
2. 待删除场景从管理列表消失，用户无法从原场景入口继续处理。
3. 数据模型恢复依赖进入其他同步流程，表现为旧场景偶然再次出现。
4. 导出/云端配置正确与 App 列表正确脱节，自动化检查误将“任务仍在”视为足够。

目前不是待删除配置被服务器抹掉。`nextAvailableNumber()` 同时检查 App 行和 SDK 场景号，因此仍保留的 `000B` 不会仅因列表消失而被正常分配器重用。风险在于未完成的设备清理任务失去直观入口，导致残留长期留在设备上；不能将隐藏当成删除完成。

## 已确认修复方案

### A. 统一待删除 Scene 的创建与重载规则

以“App 中仍有合法待删除记录，就有可展示、可继续清理的场景对象”为规则。调整 `ImportData.swift` 的重建逻辑和 `SceneConfigurationStore` 的普通重载，不再因 `isDeleting` 本身跳过对象。

复用现有 `project` 与删除重试逻辑中安全创建对象的部分：保留 scene number、name、image、displayOrder、revision、设备身份、operation generation 和引用清理进度；在对象加入网络并暴露给使用方前先附上待删除配置。不要简单删掉导入条件后继续沿用“先 add，后赋 configuration”的顺序。

从现有实现中区分“恢复本地对象”和“有权限的删除准备/收尾”。导入和只读展示无需获得删除执行权限，也不能调用整个 `prepareDeletionRetries()` 来替代恢复，否则会混入访问权限校验、引用补偿和终结删除。复用已有机制，不引入第二套删除日志或新恢复状态机。

对于已受影响的存量数据，普通 Space 加载时根据仍存在的 `sceneInfos` 补回待删除对象，无须用户新建场景。没有 App 记录、仅设备上疑似有同号场景的情况不据此自动创建或删除，避免误操作。

### B. 统一展示数量（按用户调整）

导入后的 Site 数量应包含正常场景和未完成删除场景；列表、Space 退出保存、Site 摘要刷新使用同一范围，排除现有保留/特殊场景，按当前 Mesh/Space 和 scene number 去重。

在共享导入/恢复入口补齐 SDK 场景对象后，让列表和摘要共用场景筛选规则，避免在多个页面各自拼接待删除数组或反复读取数据库。重点核对 `ImportData`、`ScenesViewController`、`SpaceViewController` 的全部 `sceneCount` 写入点，防止一个入口修好后又被其他入口覆盖成 10。

不新增导入读回检查，不新增服务器数据补偿或规范化逻辑。现有检查保持原样；若发现服务器返回数据有误，记录接口证据并交由服务器团队修复。本问题由 App 的导入/恢复过滤行为造成，修复该行为即可。离线测试中的持久化重载断言属于回归验证，不新增生产导入保护逻辑。

### C. 保留现有执行限制及删除生命周期

- 复用既有待删除卡片、详情状态及继续删除入口；普通加载只恢复本地表示，不自动发送 Mesh 命令。
- `SceneCommandBuilder.isSelectable` 继续拒绝待删除或投影未完成的 Scene；核对列表 Recall、详情控制、Timed 和 Switch 选择、持久化引用准入，不能因恢复展示而允许使用待删除场景。
- Owner/Editor 仍按现有权限继续删除；Visitor 能看到状态，但不能下发删除或提前收尾。
- 继续用原 `SyncSceneScheduleTaskBuilder`、引用清理与 Scene Delete 流程，先处理依赖，再完成场景删除；不另建命令通道、不改变命令目标和 ACK 策略。
- 保存成功的设备/阶段不重发，只保留未完成任务；失败、取消、超时和迟到回调不能推进新 generation 或删除其他身份的设备状态。
- 只有各目标及 Scheduler/Switch 等引用清理满足现有完成条件，才最终移除 App 行和 SDK 行、更新数量及上传。`pendingOperations=[]` 单独不足以证明引用清理完成。
- 保留已完成物理清理但本地最终保存失败的恢复路径：不能重新生成 Store、重新分配场景号或把记录变回正常场景。

### D. 数据结构、兼容性与品牌范围

无数据库/export JSON 结构变更：不增加或修改表、字段、JSON Key、类型、层级、必填/可空规则、默认值、索引或字段语义。继续使用 `sceneInfos.configuration` 及 `spaceData.sceneConfigurations` 内现有字段；本次仅修正本地 Scene 投影创建和已有场景数的计算。

不需要 schema migration 或版本升级。对于已保存的删除记录，通过加载时重建本地对象恢复；旧格式无配置的普通场景沿用现有兼容导入，合法空场景/空列表保持合法，损坏配置仍拒绝，不能将缺字段当成删除成功。

与旧 App 交换的数据格式不变，但旧 App 仍可能出现隐藏行为，需要通过 App 更新修复。服务器现有样本已保留完整任务，因此暂无服务器发布依赖；不修改服务器、网关或固件。

改动属于共享 App 逻辑，影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。预计复用现有国际化文案及资源；若实施中需要新增文案，再补齐 en/zh-Hans 并检查品牌资源归属。

## 实施后的最小有效验证

1. 从现场资料制作脱敏最小夹具，保留 10 条普通场景 + 1/2 条待删除场景、L2 身份、remove generation 与 Scheduler 待检查项。经过真正 JSON 序列化/反序列化、生产导入 Scene 构建逻辑、App SQLite 保存/重开、SDK Scene 保存/重载后，再断言列表和数量。仅测试 codec 或 App 行 round-trip 不足以覆盖本缺陷；若 SDK/完整导入仍为边界夹具，单独标明未覆盖的集成路径。
2. 覆盖同时间戳重复导入、新版本导入、首次/只读导入、退出重进与重启：条目保持 11/12，待删除标记不丢失，所有原任务/身份保持，不发送命令、不生成新任务、不重复创建对象。
3. 更新旧测试中“普通加载必须隐藏”的预期；保留禁止 Recall/Store、Timed/Switch 新引用、Visitor 执行及场景号复用的保护测试。
4. 覆盖 L2 离线失败、重新上线后从原场景重试、两个待删除场景分别清理、多设备部分成功、引用未清完、保存失败后重试、取消/迟到回执、相同地址换设备身份。成功阶段不得重新加入任务。
5. 运行相关既有 Scene configuration、deletion flow/cascade、reference admission、deletion UI 回归，以及新增完整导入/重载边界用例。按最终改动范围选择，避免机械重跑无关套件。
6. 一轮 Swift 修改完成后，用已核对的 `SunSmartLocal.xcworkspace`、SunSmart Debug、generic iPhoneOS、禁签名构建一次，使用本工作树独立 DerivedData。无 SDK API、资源、依赖或品牌条件变化时不机械执行全部品牌构建；有跨品牌编译风险再扩大。

最短人工验收：L2 在线创建仅包含 L2 的场景 → L2 离线删除失败 → 回 Site 连续刷新两次 → 进入 Space、退出重进并重启 App → 始终显示待删除且计数不减 → L2 上线后直接从原待删除场景继续删除 → 全部设备/引用清理完成后条目才消失、计数才减一 → 再次刷新不回生。追加两个待删除场景时验证逐个完成、计数逐个减少。

真机验收记录 App/SDK revision，并检查 Scene Register 及关联 Scheduler 的最终状态。需要诊断时只增加 DEBUG 汇总日志：import 的输入/投影/待删除数量、scene number、操作轮次、地址、失败阶段、ACK 接受、持久化与最终任务完成；不输出密钥，不在高频循环逐条打印。

## 分析阶段验证与边界

- 六份 export 与三份响应完成结构化对比；上述两组刷新前后配置不变、仅 SDK Scene 丢失的断言通过。
- 运行 `scripts/check_scene_deletion_flow.py`，现有删除、持久化、恢复、身份保护和多 Element 回归通过。首次运行因默认 Clang 模块缓存不可写而停止；将 `CLANG_MODULE_CACHE_PATH` 和 `SWIFT_MODULECACHE_PATH` 指向 `/tmp/sunsmart-scene-analysis-module-cache` 后成功，未清理共享缓存、未修改业务代码绕过环境问题。
- 该套件使用真实 App SQLite/部分生产逻辑，SDK transport、session、UI 与部分 cascade 是边界夹具；没有运行完整 UIKit、HTTP 导入及真实 Mesh 链路。通过结果不能视为本问题已修复；套件中恰有需要纠正的隐藏预期。
- 未运行 App 构建（本轮仅分析和文档），未自动操作真机，未修改/部署服务器或固件。
- 用户已确认 App 共享导入/恢复与数量修复，明确排除新增导入读回检查和服务器问题的 App 兜底。若实施发现必须改变数据结构，先另行展示完整变更和示例并取得确认。

## 实施结果与交接

已完成以下修改：

- `ImportData.swift` 使用 `SceneConfigurationStore.projectImportedRecords` 创建全部已验证的普通场景，包括待删除记录。在 `network.add` 前设置完整 `SceneInfo`，保留场景编号、名称、图标、排序和任务信息。该方法只是复用原场景构建步骤，未新增导入验证、读回检查或服务器数据补偿。
- `restoreSceneProjections()` 为存量 `sceneInfos` 恢复缺失的待删除对象，重复加载不重复创建对象；普通加载不再补充 Scheduler 任务或执行删除收尾。引用覆盖补全及删除终结仍由已有授权清理入口执行。
- Scene 列表、导入后的摘要、Space 摘要刷新和页面数量保存共同使用 `Scene.listedScenes`，保留待删除场景并排除 EFC 保留事件号。没有新增 App 表查询、持久状态或另一份待删除列表。
- 保留已有 `isSelectable`、权限、身份与 generation 保护，以及原删除任务、ACK、引用清理和最终持久化流程。已完成物理清理但尚有 App 行的场景可显示待删除，之后由有权限的既有清理流程完成本地收尾。
- 原隐藏预期已更新；新增现场规模的 10+1 / 10+2 场景回归。测试使用合成身份，不包含现场密钥或完整身份指纹。

验证结果：

| 检查 | 结果与主要覆盖 |
| --- | --- |
| `python3 scripts/check_scene_configuration.py --suite roundtrip` | 通过；3 个子套件，包含真实 JSON 编解码、生产导入场景构建、App SQLite 保存与重开；11/12 条场景重复导入、Owner/Editor/Visitor、普通重载、原任务/引用不变、EFC 数量一致及授权收尾 |
| `python3 scripts/check_scene_deletion_flow.py` | 通过；离线/部分成功、失败重试、投影保存失败、身份变化、迟到回执、停止门控、多 Element、SDK/App 分阶段收尾及存量恢复 |
| `python3 scripts/check_scene_configuration.py --suite save` | 通过；保存和 coordinator 子套件，包含任务持久性、元数据、原 generation、授权变化、投影恢复和真实 Register 读取边界 |
| `python3 scripts/check_scene_deletion_cascade.py` | 213 passed，0 failed；引用清理和回执生命周期 |
| `python3 scripts/check_scene_reference_admission.py` | 29 passed，0 failed；场景引用准入 |
| `python3 scripts/check_scene_deletion_ui.py` | 通过；列表/详情删除入口的取消、离线、失败、完成及待删除重试 |
| `git diff --check` | 通过 |
| SunSmart Debug generic iPhoneOS | 2026-11-07 17:41:59，`BUILD SUCCEEDED`，退出码 0 |

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-pending-deletion-cli CODE_SIGNING_ALLOWED=NO build
```

构建确认 SDK 解析到约定的 `.local-sdk/nordic-sig-mesh-sdk`。使用独立 DerivedData，未 clean 或清理共享缓存。输出包含本次未修改文件的 Swift capture 警告及 AppIntents 元数据提示，无构建错误。共享逻辑没有新增品牌差异、资源、依赖或 SDK 公共 API，因此本轮仅构建代表 scheme SunSmart，未重复构建其他品牌和 Release。

测试边界：新增回归直接执行生产场景 codec、`importRecords`、`projectImportedRecords`、普通恢复及展示筛选逻辑，并重开真实 App SQLite；SDK Scene 保存/加载与 transport 仍由原有夹具替代。重复相同 JSON 验证了场景导入步骤，不代表已跑完整 Site HTTP/配置恢复状态机；UI 回归执行生产入口方法，但 UIKit 为夹具。App 构建补足真实类型和链接检查，不替代 SDK 运行持久化、真实云往返或 L2 设备验收。

工作区交接：HEAD 和 SDK revision 与分析阶段相同；业务修改未提交，未 push。原有暂存 `SunSmart.xcworkspace/xcshareddata/swiftpm/Package.resolved` 保留，未纳入本次修改。无需数据库/export JSON 迁移，无服务器或固件发布依赖。下一步由用户按上述最短人工步骤验证 L2 完整删除和再次刷新不回生。
