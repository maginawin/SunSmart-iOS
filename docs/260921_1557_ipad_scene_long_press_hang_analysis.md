# iPad 长按 Scene 卡顿：数据、引入历史与待确认修复方案

日期：2026-09-21，UTC+8。

> 实施进展：用户已确认第 7 节范围，App 侧修复与 SunSmart generic iOS 构建已完成；新增回归与最终验证记录见第 8 节。iPad 实际体验仍待人工验收。

## 结论与证据边界

已确认当前代码存在一条与症状直接对应的性能缺陷：**Scene 详情页在主线程配置每张组卡片时，重新计算整个 Scene 的待同步组；计算反复扫描全空间成员，并逐节点读取、解码配置保护文件。布局回调又无条件 reloadData，增加重复执行机会。**

本次数据恰好是重负载条件：494 台设备、两个 Scene，每个 Scene 关联 17 个组、490 台成员；这些成员的 Scene 缓存与组定义一致，不能通过“发现一个待同步节点”提前结束。iPad 每页容纳 24 个组，17 个组可以同时展示。

两份文件的 Scene、Group、成员关系和场景执行数据一致；没有发现能解释该症状的场景重复、成员重复或场景记录异常。26 MB 的导出文件包含调试用原始数据库记录和缩进，并不是长按时会重新读取的业务 JSON。

**当前证据能确定缺陷及其引入提交，尚不能把本次 CPU 86%、Disk Read 45 MB/s、数分钟延迟的全部权重归给某一个函数。** 用户未提供本次 hang 的堆栈、trace、实际恢复文件或安装包 revision。以下运行时间严格区分本机隔离测量、历史文档和本次 iPad 现象；没有进行本次旧包真机二分、构建或设备操作。

## 1. 分析基线

- App：`fix`，HEAD `4011c9c49aeaa1310b2e3d68c99bf6742ff3499f`。分析开始时工作树干净。
- 用户确认使用 SunSmart，长按“场景 1”和“场景 2”均卡顿；实际安装包版本、Build、来源 revision 尚未确认。
- 本地入口 `SunSmartLocal.xcworkspace` 的 `.local-sdk/nordic-sig-mesh-sdk` 正确指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，SDK HEAD `a971027e08f9775d7a3f071a06f89be1c38ecc96`。
- SDK 已有其他任务的 `MeshFastAddDeviceManager.swift`、`MeshProxyMessageCommand.swift` 及 Restore 队列测试改动，本次未触碰。
- 分析阶段仅新增本文；只读比较业务代码与 Git 历史，在 `/tmp` 运行 Foundation 隔离分析程序。用户确认后的代码修改与验证另记于第 8 节；未修改依赖、Scheme 或设备状态。

## 2. 两份数据的结果

输入：

- `/Users/maginawin/Desktop/tmp/Space_兴东2_20260921_154713_014+0800.json`
- `/Users/maginawin/Desktop/tmp/space server data.json`

| 项目 | 本地导出 | 服务端 data |
| --- | ---: | ---: |
| 原始文件字节数 | 26,114,781 | 3,781,312 |
| Nodes / deviceCount | 494 / 494 | 494 / 494 |
| Groups | 22 | 22 |
| Scenes | 2 | 2 |
| Switches | 2 | 2 |
| Schedules / EFC | 0 / 0 | 0 / 0 |
| Space Trigger Zones | 0 | 0 |
| PID 分布 | 2502：364；2503：130 | 相同 |

场景：

| 场景 | Number | 关联组 | 成员数 | 执行数据 |
| --- | --- | ---: | ---: | --- |
| 场景 1 | 000D / 13 | 17 | 490 | ON，lightness 65535，CCT 4500 |
| 场景 2 | 000E / 14 | 17 | 490 | OFF，lightness 0，CCT 4500 |

关联组为 `CD60…CD70`。其中 PA 有 126 台，其他组有 9～24 台；`C004` 的 4 台不属于上述两个 Scene。其余 4 个组是开关相关虚拟组。

已核对：

- Node UUID、Group address、Scene number 均无重复。
- 全部 494 台 `groupState=1`；从 Model subscriptions 推导出的普通组归属与导出的 `groupAddress` 一致。
- 490 台成员在两个 Scene 中的记录，逐项与所属组对应 Scene 数据一致；全部 34 条组场景记录为正常状态。
- 两份文件的 groups、scenes、switches、schedules、spaceData 相同；按 UUID 对齐 nodes 后，共有字段值相同。服务端另有 `props` 等观测/扩展字段和部分默认字段，本地导出省略这些字段，不能将文件大小差异解释为丢失 Scene 配置。
- 用当前生产 `SpaceConfigurationIntegrityPolicy.configurationData` 处理两份真实输入，输出均为 **77,383 bytes**，字节级相等。该比较只覆盖其定义的逻辑配置；场景等字段另行按上面的逐项比较核对。
- 本地 `_debugInspection`：`issues=[]`，`comparisonPayloadAvailable=true`，`configurationInitialized=true`，`membershipPhase=joined`，`recoveryPhase=active`，无 pending import/deletion cleanup。

本地文件是调试检查封装：`spaces[0]` 为业务比较视图，`_debugInspection.rawLocal` 额外包含 Mesh、App 数据库记录。紧凑编码后的业务 Space 约 3.108 MB，检查部分约 7.466 MB；最终 26.115 MB 还包含较多缩进。恢复状态文件全文及 authorizationBaseline 未导出，所以不能从此文件直接量出 iPad 当前保护文件大小。

## 3. 长按到弹窗的实际链路

相关源码：

- [ScenesViewController.swift](../SunSmart/Main/Scene/Controller/ScenesViewController.swift)：`collectionLongPressAction`。
- [SceneViewController.swift](../SunSmart/Main/Scene/Controller/SceneViewController.swift)：`viewDidLayoutSubviews`、`updateUI`、`cellForItemAt`。
- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：`Scene.needSyncGroups`、`SceneInfo.groups`、`SceneExecuteData.isSynced`。
- [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift)：`getSyncData`、`.scenes` 分支。
- [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift)：`configurationAvailable`、`isBlocked`、`deletionCleanupPending`。

调用顺序：长按开始 → 创建 SceneViewController → 包装 NavigationViewController 并 present → collectionView 配置组卡片 → 每张卡片执行 `scene.needSyncGroups.contains(group)`。

### 3.1 每张卡片都检查整个 Scene

`needSyncGroups` 是计算属性，没有结果缓存。它先找出所有关联组，再对每组执行 `group.nodes.contains { node.getSyncData(.scenes(scene)) 非空 }`。

SDK 的 `Group.nodes` 每次筛选全空间 realNodes；`Node.group` 遍历 Element/Model；`Model.subscriptions` 又按网络全部组重新构造订阅数组。它不是 O(1) 的成员集合读取。

当 Scene 全部同步时，`contains` 会遍历全部成员。按本样本、17 张卡片各配置一次计算：

- Scene 节点检查：`17 × 490 = 8,330` 次。
- 展开组成员：`17 × 17 = 289` 次。
- 单这部分候选节点访问：`17 × 17 × 494 = 142,766` 次，内部还会访问 Model/subscriptions。

这些是基于源码和样本的单轮工作量推导，前提是完整配置 17 张卡片、状态不变且未被保护条件提前阻断；不是本次 iPad 的实测调用计数。卡片背景的 `group.isOn`、颜色的 `effectiveCctRange` 还会增加成员查询。

### 3.2 主线程逐节点进入文件读取

`getSyncData` 首先执行 `SpaceConfigurationSafety.configurationAvailable`。有 NodeSyncReadContext 时可以读批次快照；详情页未在该上下文内执行，因此进入旧分支。

旧分支会检查组配置完整性，再执行 `isBlocked`：

- 根据账户/区域/Mesh/子网生成保护状态文件路径。
- 读取 `Library/Application Support/SpaceConfigurationRecovery/<scope-hash>.json` 并完整 JSONDecoder 解码 SpaceRecoveryState。
- 检查 pending import/reference cleanup 文件。
- 如果 device-deletions.json 存在，读、解码并判断是否仍需清理。

SpaceRecoveryState 中的 authorizationBaseline 是 Data，JSON 持久化时以 Base64 保存；即使只需 phase 等少量状态，也会完整解码。上述读取不是 HTTP 下载，也不是从灯具获取 Scene 数据。

### 3.3 布局期间无条件重新加载

`viewDidLayoutSubviews` 每次都设置 itemSize、更新 collectionView 高度、调用 layoutIfNeeded，最后 `updateUI → reloadData`。弹窗布局、尺寸变化等可以再次进入此路径，重复昂贵卡片配置。

当前代码没有尺寸不变时的跳过逻辑，也没有将数据刷新与布局计算分离。它是明确的放大点；没有本次布局计数或堆栈，不能宣称已证明无限循环、死锁，或给出固定循环次数。

### 3.4 为什么列表正常，而长按仍卡

[ScenesViewCell.swift](../SunSmart/Main/Scene/View/ScenesViewCell.swift) 已使用 `NodeSyncStatusRefresh.request(scene:)`。但 Scene 详情仍调用旧 `needSyncGroups`；已有上下文只在刷新器的同步分片内安装，不会自动覆盖 UIKit 随后的任意回调。

[SceneSettingsViewController.swift](../SunSmart/Main/Scene/Controller/SceneSettingsViewController.swift) 也在 `viewWillAppear` 和每个 Cell 配置时读取同一属性，存在相同遗漏。只改长按入口会把卡顿留到下一层 Settings。

## 4. 隔离测量与不能据此声称的结论

用当前生产的 DeviceScheduleAddressCleanup.swift（包含 SpaceRecoveryState）及 SpaceConfigurationIntegrityPolicy.swift 编译 Foundation 程序，使用两份真实 JSON。只在临时目录生成自己的测试恢复文件；不读取或改写 iPad 容器。

测量内容为旧路径中的 `Data(contentsOf:) + JSONDecoder.decode(SpaceRecoveryState)`，排除 UIKit、成员扫描、路径哈希、文件探测、删除日志和运行时诊断。编译未启用优化，环境是本机 macOS。

| 模拟状态 | 文件大小 | 读取次数 | 累计逻辑读取量 | 本机耗时 |
| --- | ---: | ---: | ---: | ---: |
| 无 baseline | 267 B | 490 | 0.131 MB | 0.007 s |
| 无 baseline | 267 B | 8,330 | 2.224 MB | 0.115 s |
| 含样本生成的 baseline | 103,474 B | 490 | 50.702 MB | 0.032 s |
| 含样本生成的 baseline | 103,474 B | 8,330 | 861.938 MB | 0.560 s |

身份使用合成值，baseline 来自样本逻辑配置；这里不是实际 iPad 恢复文件的测量。临时程序：`/tmp/scene_recovery_read_analysis_20260921.swift`。

**此结果证明重复文件访问的数量级，不能证明 iPad 数分钟卡顿全部是文件解码，也不能把累计逻辑读取量当作物理闪存流量。** 本机文件缓存、设备存储、布局重复和调试诊断的开销不同。

仓库已有 [9 月 15 日 Scene/Timed trace 分析](260915_2040_llh_debug_space_tab_hang_analysis.md) 记录过同一 `Scene.needSyncGroups` 下的成员扫描、保护检查热点，并记录了 libRPAC 回溯开销。但那是旧版 Scene 列表记录，本轮未重新分析其 trace，不能将其时间或诊断配置当成本次长按的已测事实。

若要确定本次“几分钟”和 45 MB/s 的实际构成，最小补充证据是在卡顿刚发生时采样主线程和文件访问：确认卡在上述 Scene 链，实际被读文件为何，布局/Cell 重建了几轮，是否伴随诊断符号读取。无需等卡顿结束或采集数分钟日志。

## 5. Bug 何时引入

已经比较相关提交与父提交，不仅依赖当前 blame。

| 层次 | 提交 | 时间（UTC+8） | 变化 |
| --- | --- | --- | --- |
| 每张组卡片重新计算整个 Scene | `0475c3fc9` | 2024-01-19 17:58:04 | 引入 `scene.needSyncGroups.contains(group)` 及过滤组逻辑 |
| 布局时无条件刷新数据 | `3abb43c93` | 2025-02-19 09:38:44 | iPad UI 适配加入 viewDidLayoutSubviews → updateUI |
| 详情判定接到通用节点同步生成 | `588da2b6f` | 2025-04-03 18:01:37 | needSyncGroups 改为逐节点调用 getSyncData(.scenes) |
| 每次节点检查接入保护校验 | `d4e4e4364` | 2026-09-07 15:01:04 | getSyncData 新增 configurationAvailable guard，当时 isBlocked 主要为标记/文件存在判断 |
| 每次保护检查完整读取/解码恢复文件 | **`abfbe5a710107897eea56b8267422e860a0cf162`** | **AuthorDate 2026-09-07 17:46:06；CommitDate 2026-09-08 11:02:44** | 新增 SpaceRecoveryState 文件及 isBlocked 的 Data/JSONDecoder 读取、删除日志读取，形成近期 I/O 退化链 |
| 部分性能修复，遗漏详情和设置 | `e32ef78fa` | AuthorDate 2026-09-15 15:42:59；CommitDate 2026-09-16 09:40:36 | Scene 列表接入共享状态读取；未修改 SceneViewController / SceneSettingsViewController |

因此应将“旧有重复计算结构”和“最近加入同步磁盘读取的退化”分别归因。**本次持续读盘机制的关键引入点是 abfbe5a7，实际提交日期为 2026-09-08；不能仅用 AuthorDate 写成 9 月 7 日发布。**

这些提交均已在当前 HEAD 中。未取得实际安装包 revision，也未做历史包同设备二分，所以不能给出“某个商店版本首次出现数分钟卡顿”的实测结论。

## 6. 如何在 App 上快速复现

### 最快路径：直接使用现有“兴东2”

1. 使用同一 iPad 的 SunSmart，进入原 Site → 兴东2，等待 Space 导入/初始化完成。
2. 切到 Scene，等列表本身显示稳定；长按“场景 1”约 0.5 秒，观察详情弹窗出现前主界面是否停止响应。
3. 详情出现后关闭，再长按“场景 2”。两者关联成员相同，均应触发这条检查链。
4. 需要快速定位时，卡住后即可在 Xcode Pause 查看主线程，无需等几分钟。重点查找 SceneViewController.cellForItemAt → Scene.needSyncGroups → Node.getSyncData → SpaceConfigurationSafety，以及 Group.nodes / Model.subscriptions。

可在 Space 已加载后做断开 Mesh/网络的对照，不要重启或触发重新导入：这条显示判断只使用本地状态，设备全在线或附近有 490 台真灯不是触发前提。该离线对照尚未在本次真机执行，预期应仍保留重复计算。

### 换一台测试设备时

通过 App 已有的 Site/Space 分享、扫码或 ID 导入，使用获授权账户取得同一服务器 Space，再走上述路径。需要保留的是 17 个关联组、约 490 台节点、已一致的 Scene 缓存，以及正常完成的 Space 保护/初始化状态。

**不要将这两个附件直接当作普通“Import JSON”文件。** 本地 export json 是 `_debugInspection` 检查封装、标记 uploadable=false；接口文件外层是 message/code/data；当前 Site 列表的可见 Import 入口为扫码或 ID，源码中的 Import Space 文件菜单被注释。附件本身也不包含完整恢复 side store。

若另建小规模测试数据，重点是“多组 + 多成员 + 全部已同步”。大量待同步设备会让每组 contains 很早返回，可能反而减轻卡顿。不能通过删除节点缓存来等价复现当前最重路径。数据注入/新建测试入口不在本次只读分析范围。

## 7. 修复范围（已获用户确认）

建议只在 App 侧补齐 Scene 的显示读取和布局刷新，复用当前保护、缓存、取消机制，不修改 SDK 或服务器数据协议。

1. **Scene×Group 的显示状态批量读取。** 扩展现有 SpacePageSyncRead / NodeSyncStatusRefresh 的 Scene 查询，使详情、Settings 获得当前 Scene 下各组的结果；同一有效配置批次共用保护快照与成员索引。一个 Scene 的成员最多按需要扫描一次，不再每张卡片扫描整个 Scene。
2. **Cell 只展示结果。** 详情与 Settings 的同步图标、Settings 同步按钮统一消费上述结果。结果必须以 Scene 和 Group 的组合标识；不能拿已有全 Scene 的 Bool 给每个组使用，也不能用 Group 所有功能的 needSync 代替该 Scene 的状态。
3. **数据刷新与布局分开。** viewDidLayoutSubviews 只在尺寸实际变化时更新尺寸/约束；首次数据准备由初始化路径明确触发，Scene/Group 更新和返回页面按已有 revision/事件刷新。避免每次弹窗布局都 reloadData。
4. **保留状态与生命周期语义。** 计算中/不可用不能表现为已同步；使用现有保守展示方式。按 Space 会话、网络对象、配置/保护版本失效；关闭页面、切换 Scene/Space、Cell 复用后拒绝迟到结果。实际同步、删除和授权继续走实时完整检查。
5. **同链路兼顾实时显示。** 详情卡片的开关背景和 CCT 范围优先复用该批次成员，保持收到设备上报/用户操作后的实时刷新。先处理本次 Scene 路径，不扩大为通用 SDK accessor 重构。

不建议仅将一次 `needSyncGroups` 提前到 viewDidLoad：虽少了重复调用，首次仍可能是主线程长任务。不建议将整个活 Mesh 对象计算直接丢入 global queue，也不通过删除保护 guard、清空恢复文件或将所有状态默认已同步来绕过卡顿。

### 确认实施后的验证

- 在已有隔离测试中覆盖：17 组/490 成员全已同步；单个组的单个节点待同步；两条 Scene 独立判定；OFF 场景；空组；保护阻断/读取失败；版本变更、关闭页面、Cell 复用的迟到回调。
- 检查同一有效批次保护读取次数不随“卡片数×节点数”增长；单个 Scene 的节点判定不在每张卡片重跑；重复布局不重新提交整页状态计算。
- 复用 `scripts/check_node_sync_status_refresh.py`、`scripts/check_space_protection_snapshot.py` 等相关回归，再构建一次 SunSmart / Debug / generic iOS，使用当前正确映射的 SunSmartLocal workspace。
- 此范围为各品牌共享逻辑，无品牌条件差异；若实施引入资源归属或工程配置变化，再扩大必要构建范围。
- 人工在同一 iPad、同一数据验证首次长按、关闭后重开、场景 1/2、Settings、旋转/分屏与状态变更。分别记录首次可交互和状态计算结束，确认主线程不再停留在重复保护读取/全 Scene 扫描路径；构建与隔离测试不替代这个运行验收。

上述范围已获用户确认，按下节实施。

## 8. 实施与验证记录

### 最终改动

- `SpacePageSyncRead.swift` 增加 Scene 分组读取器，使用既有 NodeSyncReadContext 的批次缓存保存正在进行的读取和完整结果。Scene 列表、详情、Settings 复用同一 Scene 的结果；仍调用原 `getSyncData(.scenes)` 比较与删除判定，不混入 Group 其他功能的同步状态。
- 返回各组的 ObjectIdentifier 集合，绑定 Scene 对象和现有配置/保护 revision。不可用保护、损坏文件和未完成计算不给出“已同步”快照；同步执行和权限检查没有放宽。
- 页面显示状态独立管理取消票据。隐藏页面取消自己的请求，保留 Space 内有效的共享结果；页面销毁、切换 Scene 或取消后不接收旧回调。
- Scene 详情第一次出现明确建立数据源；布局回调仅在有效尺寸改变时更新尺寸与高度，移除 layoutIfNeeded 与无条件 reloadData。详情和 Settings 在配置变化时刷新数据，未变化重入只刷新实时显示及按需读取状态。
- SceneGroupsViewCell 从页面提供的状态显示同步警告；配置 Cell 不再访问 Scene.needSyncGroups。警告同时处理图标/文字的显隐，避免文字图标组隐藏同步提示。
- `NodeSyncStatusRefresh.sceneGroupAppearances` 复用成员索引，必要时一次建立全空间成员投影；批量读取开关与 CCT 范围。页面返回、设备/组更新与用户开关操作后刷新显示，不冻结实时值。
- Settings 的选中状态和草稿执行参数保持现有业务流程；没有修改 Scene 保存、预览、同步、删除任务或 Mesh 消息。
- 没有新增生产源码文件、资源、文案或工程配置；生产改动为七个共享 Swift 文件。SDK 未修改，也未引用新的 SDK API。

### 自动验证

| 验证 | 结果与边界 |
| --- | --- |
| `scripts/check_node_sync_status_refresh.py` | 最终回归通过，包含新增 Scene 读取及布局/生命周期函数检查。490 节点/17 组、17 个并发消费者共检查 490 个节点，保护文件读取 2 次；列表继续请求不增加节点检查与文件读取 |
| Scene 精确语义 | 两个 Scene 相互独立、单个组的单个节点差异、空组；提取生产 `deviceTarget/isSynced` 执行 OFF 正常/开关不一致对照 |
| Scene 生命周期与保护 | 通过：共享读取中的版本失效、损坏保护文件、取消后切换 Scene、页面销毁、已缓存结果失效；最终回归包含强制分片的重叠消费者与明确 blocked 标记 |
| 布局/出现回归 | 执行生产生命周期与布局函数体，验证首次建立数据、20 次相同布局只更新一次高度、不重载数据，变窄更新高度，隐藏/重入及版本失效触发正确刷新。UIKit/SnapKit 由数值接收器隔离，不能替代真实旋转/分屏验收 |
| `scripts/check_space_protection_snapshot.py` | 通过：真实临时保护文件、损坏/权限/身份/pending/mutation；5000 次检查为 2 次文件读取＋2 次探测，主线程文件读取为 0。此脚本未改动 |
| SunSmart Debug generic iOS | 2026-09-21 16:29 输出 `BUILD SUCCEEDED`，退出码 0。使用 SunSmartLocal workspace、iphoneos、generic/platform=iOS、CODE_SIGNING_ALLOWED=NO，固定 DerivedData 为 `SunSmart-fix-cli` |
| `git diff --check` | 通过；构建后仅补充测试用例与本文，生产代码未变化 |

隔离测试使用合成的 490 节点规模夹具和可控 SDK/数据库边界，生产读取器、调度器、保护读取及被提取的比较函数真实执行；这不是将用户附件导入 iPad 后的运行结果。布局验证也没有启动 Simulator 或创建临时 Xcode 工程。

构建实际解析到现有 `.local-sdk/nordic-sig-mesh-sdk`。SDK revision 及其他任务的未提交差异与本轮开始一致，均未触碰。此改动没有品牌编译分支或资源归属变化，使用 SunSmart 代表构建；没有运行其他品牌、Release 或真机安装。

### 最短人工验收

1. 同一 iPad、同一“兴东2”，依次长按场景 1、场景 2；关闭后重新进入，再打开 Settings。预期弹窗可先正常展示，状态计算不阻塞整页数分钟；计算完成后同步图标和按钮符合实际状态。
2. 在详情与 Settings 旋转或改变分屏宽度，检查布局、分页及关闭/返回操作；改变组开关后确认背景更新，Settings 草稿选择不被状态回调清空。
3. 如观察 CPU/磁盘，比较相同构建配置和操作窗口；待同步判断不应再从 Cell 或布局回调逐节点读保护文件。本轮没有本次 iPad 修复后 CPU、Disk Read 或弹窗耗时测量，不给出数值改善承诺。

代码保持未提交，未执行 commit/push。本文持续记录本任务，未另建重复计划或总结文件。
