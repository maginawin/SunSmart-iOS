# Timed 日程编辑卡死：trace 根因与关联功能分析

日期：2026-09-24，UTC+8。第 1～8 节记录只读分析；用户随后确认“按建议修复”，实施与最终验证见第 9 节。

> 实施状态：App 修复及相关回归已完成，SunSmart generic iOS Debug 构建通过。SDK 未修改；真实 iPad 交互、CPU 与 Mesh 验收仍待人工完成。

## 结论

**本次 trace 已证实：日程编辑页在主线程同步生成完整同步计划，目标判定反复重建全网组成员，形成高成本嵌套扫描。** 38,182 个采样全部位于 `ScheduleAddViewController.setupData → Schedule.getNeedSyncDatas`，主线程累计采样权重 38.182 秒；录制结束仍未离开该调用链。约 99.83% 的采样包含 `Group.nodes`，约 90.03% 包含 `Model.subscriptions`。

这属于持续 CPU 运算造成的界面无响应。该记录未证明无限循环、锁死或 crash；trace 是用户按 Stop 结束，也不是 Mesh ACK、HTTP 或读盘等待主导的采样。既有遍历是有限的，但本次录制未覆盖它的结束，不能估计还需多久恢复。

**影响不止打开编辑页。** 日程启用/禁用、编辑保存、日程同步计划、Devices/Groups/Scenes 目标弹窗，以及包含日程检查的组/设备同步，都有未使用分片读上下文的共享入口。不能只把编辑页换成异步图标查询就认为整个问题解决。

**另外确认两个独立功能缺陷：** Devices 弹窗忽略原选择而传入全部候选设备；Groups 弹窗在“仍是当前目标且又有待删除记录”的重叠状态下可能隐藏真实待同步提示。两者均运行了抽取生产函数的隔离复现，未做 UIKit/设备验收。

重要边界：trace 命中的是场景日程分支，不能证明五个日程都具有相同耗时。导出中的日程 1 只选中一台设备，目标判定不走此次昂贵的组扫描；若它也单独出现同等长时间卡住，需要该入口的独立采样。日程 4/5 虽只关联两台设备，仍被全网孤儿日程清理扫描放大。

## 1. 分析基线与证据

- 工作树：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix`，分支 `fix`，HEAD `0b76fa61f5f72cb00be56689e3b63513eed73452`；分析前工作树干净。
- 本地 workspace：`SunSmartLocal.xcworkspace`；`.local-sdk/nordic-sig-mesh-sdk` 正确指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`；SDK HEAD `ebbe1c969381363487bfe6e371bae08e954f6f00`，无未提交差异。
- trace：[scene crash.trace](</Users/maginawin/Desktop/tmp/scene crash/scene crash.trace>)。
- 数据：[Space 导出 JSON](</Users/maginawin/Desktop/tmp/scene crash/Space_兴东2_20260924_110852_723+0800.json>)。
- trace 设备：iPad (A16)，SunSmart，包含 `SunSmart.debug.dylib` 符号；录制时间 11:04:22.249～11:05:00.759，总计 38.510484 秒。
- JSON 是约 4 分钟后的导出，不能视为采样瞬间的逐字段快照。实际安装包的 Git revision 尚未由构建元数据确认；trace 中函数与当前源码能对应，但不据此宣称包与 HEAD 完全相同。
- 导出是 `_debugInspection` 检查封装，标记 `uploadable=false`；约 25.95 MB 同时包含正常导出与原始数据库，不代表点击日程会读取/解码这整个文件。

`xctrace` 在沙箱内导出采样表异常退出；沙箱外导出成功。分析使用了完整 `time-profile` 表并解析 XML 的 id/ref 引用，按每条调用栈去重汇总 inclusive 权重。辅助文件位于 `/tmp/sunsmart-scene-profile-full.xml`、`/tmp/sunsmart-scene-profile-summary.json`，不含原 JSON 中的凭据。

## 2. trace 直接证明的调用链

```text
TimedViewController.didSelectItemAt
  → present 日程编辑弹窗
  → ScheduleAddViewController.viewDidLoad
  → setupData
  → getNeedSyncDatas().isEmpty()
  → scene.info.groups.forEach
  → group.nodes.filter(targets)
     / groupTargetNodes.filter(needsSync)
  → Schedule.targets(node:contextGroup:)
  → scene.info.groups.contains { group.nodes.contains(node) }
  → Group.nodes = realNodes.filter { node.group?.address == group.address }
  → Node.group：依次检查 Element / Model 的 subscriptions
  → Model.subscriptions：扫描 Mesh 的 groups、特殊地址及订阅字符串
```

`didSelectItemAt` 是源码确认的入口；trace 实际从 UIKit 弹窗加载阶段开始采到 `viewDidLoad/setupData` 以下链路。

| 函数 | inclusive 采样权重 | 占主线程采样 |
| --- | ---: | ---: |
| `ScheduleAddViewController.setupData` / `getNeedSyncDatas` | 38.182 秒 | 100% |
| `Schedule.targets` | 38.093 秒 | 99.77% |
| `Group.nodes` | 38.117 秒 | 99.83% |
| `Node.group` | 36.846 秒 | 96.50% |
| `Model.subscriptions` | 34.375 秒 | 90.03% |

这些是包含子调用的时间，不能相加。首个采样在 0.318 秒，末个在 38.510 秒；完整中间秒几乎每秒都有 1,000 个 1ms 的主线程运行样本，足以解释主线程接近占满一个核心以及触摸、布局、动画无法继续。

全部样本仍位于 `getNeedSyncDatas` 的场景 forEach；约 19.314 秒的样本同时包含 `needsSync`，其余主要位于前置目标过滤。没有采到后面的 `needsDelete`。因此，后文的孤儿清理开销是根据当前源码和附件计数确定的后续风险，不能混称为这 38 秒已经执行过的工作。

源码入口：[TimedViewController.swift](../SunSmart/Main/Timed/Controller/TimedViewController.swift)、[ScheduleAddViewController.swift](../SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift)、[MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)。

## 3. 为什么这份 Space 特别慢

附件包含 487 个节点、22 个组记录（18 个有灯成员的组，4 个开关关联组）、5 个场景、5 个日程、21,915 个模型记录。全体节点有正常唯一的归属组；按 SDK 当前的订阅顺序解析，487 个归属都与导出字段一致，没有发现重复节点地址或多普通组订阅归属歧义。

| UI 日程 | ID | 当前目标 | 目标成员 |
| --- | ---: | --- | ---: |
| 日程 1 | 0 | Devices：单节点 `32E0` | 1 |
| 日程 2 | 1 | 场景 `000D`，18 组 | 487 |
| 日程 3 | 2 | 场景 `000D`，18 组 | 487 |
| 日程 4 | 3 | 场景 `0002`，1 组 | 2 |
| 日程 5 | 4 | 场景 `0003`，1 组 | 2 |

主要放大点：

1. **只显示一个 Bool，却先生成完整计划。** `setupData` 只需要“是否有未同步”，但调用会收集所有同步/删除设备，无法发现一条差异就结束。
2. **正向枚举成员之后，又反向遍历整网证明成员关系。** `group.nodes` 已经给出该组成员，`targets` 却对每个节点再次逐个目标组调用 `group.nodes`；`needsSync` 又重做一次 `targets`。
3. **有 `contextGroup` 仍先执行昂贵扫描。** 当前分支先查真实成员，后查传入组，已有的上下文未用于提前结束等价的目标判断。
4. **每次成员读取都是重新计算。** SDK `Group.nodes` 不是常数成本字段；`Node.group` 也不是已缓存的归属值。附件里每个节点平均检查 5 个模型才找到归属，随后还会生成和销毁订阅数组。
5. **末尾无条件做全网清理扫描。** `orphanDeleteNodes` 对全部 487 个节点先调用 `needsDelete`，之后才排除已经覆盖的目标。这让两节点场景也付出明显的全网平方级成员检查成本。

原始数据库还有正常导出未展示的待删除组列表：日程 2/3 均保留 `C004` 和 `CD6F`，但这两个组同时仍属于场景 `000D`。这会增加无效检查；当前完整规划的 `targets` 和 `allSyncNodes` 过滤会避免把现有目标直接删掉，不能把残留列表本身解释为本次错误删除。

### 隔离计数结果与边界

在 `/tmp/sunsmart_timed_analysis.py` 中从当前源码抽取生产 `targets`、`schedulerSyncDifference`、`needsDelete`、`getNeedSyncDatas`，按附件节点、组顺序、场景关系和待删除列表运行；SDK/UI 边界用小型替身，给 `Group.nodes` 及其中的归属查询加计数。此处没有运行完整 App，也没有回放真实 BLE。

| UI 日程 | 单次完整规划的 `Group.nodes` 读取 | 由这些读取触发的节点归属查询 |
| --- | ---: | ---: |
| 日程 1 | 0 | 0 |
| 日程 2 / 3（各一次） | 12,046 | 5,866,402 |
| 日程 4 / 5（各一次） | 492 | 239,604 |

计数使用导出的组排列；真实 Mesh 的排列改变时，短路扫描次数会不同。替身简化了 Scheduler Entry、模型 Owner 与状态缓存，所以此表只用于量化**成员查询结构**，不是完整设备同步结果，也不是全部 getter 的调用总数或真机耗时。仅日程 2/3 的这些归属查询，结合附件每次约 5 个订阅 getter，已经是约 2,933 万次模型订阅读取的量级。

日程 1 仍会扫描全部节点的 Scheduler 缓存，也会有少量 Owner 归属读取，但没有这里的嵌套 `Group.nodes` 放大。不能用日程 2/3 的计数和 trace 给它定同样的因。

附件里有 1 个节点缺少已知 Scheduler Model 缓存，其余 486 个均有两个模型缓存。未知缓存可能触发后续设备读取/待同步提示，不能当成主线程本地 CPU 持续占满的主因，也不应通过将其当作空或已同步来消除提示。

## 4. 其他功能的影响范围

下表除首行外为源码调用链证据，未采集各入口的独立真机耗时。

| 入口 | 共享路径与影响 |
| --- | --- |
| Timed → 打开场景日程 | **trace 已证实**；`setupData → getNeedSyncDatas` 在弹窗初始化时占住主线程 |
| 日程修改后 Done / 同步成功返回 | `doneBtnAction` 再做完整规划；同步完成回调再调用 `setupData`。可能刚恢复又卡住 |
| 日程启用/禁用 | `ScheduleServer.setEnabledState` 逐节点 `needsSync`，不带组上下文；大场景重复扫描。出现处理 HUD 不代表计算已经让出主线程 |
| Devices 目标弹窗 | 初始化再次 `getNeedSyncDatas`；当前日程原本是 Scene 时，切到 Devices 也要先承担原场景完整规划 |
| Groups 目标弹窗 | 每张组卡片 `getNeedSyncScheduleDataNodes` 再逐节点 `needsSync/needsDelete`；Cell 创建/刷新会重复 |
| Scenes 目标弹窗 | 初始化逐组逐节点检查当前日程；有短路，但已同步节点较多时仍可能重 |
| 日程 Sync / Re-sync 页面 | `SyncDevicesViewController.rebuildTaskPlan` 的 `Task @MainActor → builder.build → appendSchedule → getNeedSyncDatas`，仍在主线程；`Task` 本身不消除长任务 |
| 组同步、增删组成员、设备批量同步 | `SyncDeviceTaskBuilder → Node.getSyncData → getNodeSyncSchedules/getNodeNeedDeleteSchedules → targets`；调用发生在状态读取上下文之外时同样退回慢路径，批量节点会放大 |
| 组配置生成日程指令 | `GroupServer` 遍历绑定日程并 `needsSync`；共享目标判定仍有成本 |
| 删除整个日程 | 会读取 `existNodes`，且 `saveSchedule` 使用完整规划；但清空当前目标后不再等同于大场景目标反查，不能直接套用 38 秒或同一倍数 |

已有优化的边界：

- Timed 列表的 `SchedulesViewCell` 调用 `NodeSyncStatusRefresh.request(schedule:)`，读上下文提供成员索引和分片。
- Scene 详情/Settings、Group 详情/Members 的同步显示已有类似保护；当前分析未发现此次 trace 从它们进入，也不能据此宣称所有操作都已覆盖。
- `NodeSyncReadContext` 是线程局部、只在同步执行的读取切片中安装；进入列表并不会让未来所有按钮/弹窗回调永久自动使用它。
- 9 月 15 日的状态显示优化以及 9 月 21 日的 Scene/Group 显示补齐，没有覆盖本次日程编辑、选择器及执行规划入口。这是范围缺口；不是这份 trace 中出现了新的 Scene 长按调用。

主线程被长期占用还会拖延排队在主线程的 UI、计时器及回调。当前证据不能进一步断言已发生消息重发、蓝牙掉线、固件日程错误或云端数据损坏；设备上已经保存的日程是否执行正确，也不能由 App CPU 采样判断。

## 5. 额外确认的功能缺陷

### 5.1 Devices 选择器把全部候选设备当成原选择

位置：[ScheduleAddViewController.swift](../SunSmart/Main/Timed/Controller/ScheduleAddViewController.swift) 的 `didClickTargetAction`，以及 [ScheduleDevicesView.swift](../SunSmart/Main/Timed/View/ScheduleDevicesView.swift)。

`.devices` 分支忽略传入目标中的节点，取全 Space 支持 Scheduler 的节点，并同时作为候选列表、已选列表传给弹窗。隔离执行**原生产选择处理函数**，输入已选 1 个节点，弹窗实际收到 487 个已选节点，已稳定复现。

后果及触发条件：

- 编辑日程 1 → 打开 Devices，原本只选一台，可能显示全选；即使不主动增加设备，Confirm 会返回全部选中设备，随后 Done 会将新集合写入日程并规划下发。
- 编辑模式 `checkOffline` 把这些“已选的离线设备”全部放入 `disableUnselectNodes`，单选与取消全选都保留它们，可能表现为无关离线设备无法取消。
- 新建模式也错误地预选全部候选，再按离线检查剔除部分；重新进入选择器同样可能丢失用户前一次选择。
- 仅打开弹窗或 Cancel 尚不会保存扩大的设备集合；需要 Confirm，再完成保存才改变业务目标。

这是独立的选择语义错误，可进一步放大配置/同步数量，但不是本次“尚未打开 Devices 就卡住”的起因。Git 历史显示候选与选择变量混用已在 `fe73700de` 的 2026-01-20 改动中存在；2026-09-08 的 `.devices(let nodes) → .devices` 只是移除未使用绑定，并非该缺陷首次产生。

### 5.2 Groups 选择器可能隐藏真实的待同步提示

位置：[MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift) 的 `Group.getNeedSyncScheduleDataNodes`，调用方为 [ScheduleGroupsView.swift](../SunSmart/Main/Timed/View/ScheduleGroupsView.swift)。

函数只要发现该组出现在 `needDeleteGroups`，就只检查删除，不检查同步。但组仍可能由当前场景或当前直接目标覆盖；此时 `needsDelete=false` 是正确的，`needsSync` 却可能为 true。于是完整日程计划需要同步，而该组卡片没有提示。

附件已具备重叠前提：日程 2/3 的 `C004`、`CD6F` 同时属于当前场景和待删除列表；这两组在导出时的旧式日程缓存对应项匹配，**不能声称这份附件已经展示了错误图标**。在该结构下只把一个节点的 Owner Entry 设为不一致，抽取生产完整规划函数和组显示函数运行，复现结果为“完整计划包含该节点，组显示的同步/删除列表均为空”。

实际可见触发：后续修改日程时间、设备端状态改变，或部分同步失败，而上述重叠记录还存在时。影响是错误展示同步状态；当前证据没有显示完整 `getNeedSyncDatas` 也漏掉该节点，因此不要扩写成“所有同步入口都会丢任务”。

## 6. 引入与既有检查为何未挡住

- 已比较 `4b7bed6d1353dba8e4f042568cd37db8a3e2b9da` 与父提交。2026-06-03 的“add/remove group members and sync schedulers”新增共享 `targets`，把 `group.nodes` 放进逐节点判断，并增加全网孤儿清理；这是当前嵌套反查结构的可定位引入点。
- 这些逻辑有真实目的：兼容新增成员上下文，避免退出组/残留日程漏清理。修复应保留这些语义，不能直接撤掉目标检查或全网清理。
- `e32ef78f` 给状态读取增加上下文快路；`e25970e1` 等后续补齐 Scene/Group 显示。当前 `ScheduleAddViewController.setupData` 仍直接生成完整计划。
- 既有回归覆盖成员语义、读上下文、分片与状态失效，但没有用真实 SDK getter 成本执行 UIKit 的日程编辑初始化及所有选择器链路。隔离回归/源码契约通过，不等于这个长任务入口已有运行验收。
- 未拿历史安装包做相同 iPad 二分；这里只确定代码结构历史，不声称某个商店版本首次出现此症状。

## 7. 建议的最小完整修复范围（后续已确认实施）

1. **共享目标判定消除全网反查。** 基于当前节点的有效归属及明确 `contextGroup` 与目标组集合比较，复用现有读上下文的成员索引；一次规划内复用成员和目标集合。保留直连设备目标、退出组失败、新增成员、Restore、场景和待删除重叠的当前规则。
2. **日程编辑/选择器的显示读取补齐。** 编辑页 Bool 使用现有 `NodeSyncStatusRefresh`；选择器提供所需的节点/组/场景状态读取结果。包含取消、版本失效与页面身份检查；计算中不能先显示已同步。
3. **执行规划仍生成完整清单，但消除重复并保证可响应。** 对同步规划建立一次性成员索引，已覆盖节点用 Set 排除后再做必要清理判断；若仍存在大批量主线程工作，沿现有分片机制推进并允许取消。状态显示缓存不能替代执行前的实时授权/配置检查，不直接把共享活 Mesh 对象放到 global queue 并发读写。
4. **分别修复两个功能错误。** Devices 保留输入选择集合；Group 卡片依据当前同步/删除语义显示，不能仅凭待删除列表跳过当前目标同步检查。业务差异宜与性能改动清晰区分。

优先在 App 侧完成；目前没有证据要求修改固件、云端协议或全局 SDK getter。仅换 Release、改成 `DispatchQueue.main.async`、显示 HUD、删保护检查或把未知缓存视作空，都不能作为完整修复。

## 8. 实施后的必要验证

- 用本附件规模覆盖：487 节点/18 目标组；日程 1 的单设备、日程 2/3 的大场景、日程 4/5 的小目标大 Space；目标和待删除记录重叠、非目标残留、未知模型状态。
- 验证一次规划不再随“目标节点 × 目标组”重建全网成员；校验同步/删除结果与原语义一致，尤其是退出组、重新加入、部分失败与旧缓存。
- 验证 Devices 原选择 0/1/多台、隐藏筛选项、离线保护、Confirm/Cancel；Group 显示与完整计划在重叠且有差异时一致。
- 页面关闭、切 Space、修改日程、状态回读更新时，旧结果不得覆盖新页面；未完成/不可用不得展示已同步。
- 复用相关状态读取、Timed Owner/持久化、任务生成回归；Swift 生产改动完成后按项目规则构建一次 SunSmart generic iOS Debug。只有出现跨品牌配置/API 差异才扩大构建。
- 最终同一 iPad、同一 Space、相同构建配置复测：打开五个日程、关闭重开、三个目标弹窗、启停、Done、Sync/Re-sync 及大组/设备同步。分别看页面可交互时间、规划完成时间和主线程 trace；上述隔离计数不能替代此验收。

分析阶段已完成 trace 统计、导出数据结构/拓扑核对、源码与历史调用链审查，以及三个隔离诊断（成员查询计数、Devices 误选、Group 提示误判）。该阶段仅新增本文；未运行 App 构建和真机测试，未修改或提交业务代码。

## 9. 实施与最终验证（2026-09-24 11:41）

### 最终改动

- `Schedule.targets` 不再通过每个目标组的 `Group.nodes` 反查全网；显式新增/恢复组上下文先做等价短路，否则只检查节点自身归属。保留真实节点范围、直接设备目标、退出失败和上下文 OR 语义。
- 完整 `getNeedSyncDatas` 在本次调用内建立一次成员索引，复用同一 `Schedule.SyncDataRead` 生成同步/删除清单。目标、直接删除和组删除的覆盖使用集合；已覆盖目标不再重新检查删除。非目标残留仍遍历检测，未知模型和 Owner/清理模型策略未改变。
- 同一规划读取器可按时间预算推进；三个目标选择器通过既有 `NodeSyncStatusRefresh` 使用分片读取与同版本共享结果。编辑页只请求是否待同步的 Bool，不在 `setupData` 生成完整清单。
- 实际保存/执行仍按调用时状态完整生成计划，没有把 UI 的缓存作为执行授权。当前附件下的嵌套扫描已消除；没有扩展为对所有 Sync Devices 功能重新设计异步任务构建器。
- Devices 选择器候选与原选择分开传递，保留用户选择、筛选隐藏项和已有离线保护。三个选择器完成读取时只更新可见同步图标，不重设选择或重新绑定整张设备卡片。
- Group 待删除记录和当前目标重叠时同时依据实际同步/删除策略判断，显示结果包含仍需同步的组。Group 控制显示复用成员读取，同时保持在线、开关值为当前值，不冻结设备上报后的状态。
- 编辑页和选择器响应 Scheduler 回读更新；页面隐藏/销毁、弹窗开始关闭、请求替换后拒绝迟到结果。关闭动画期间即便仍挂在窗口，也不允许状态通知重新提交任务。保护不可用或读取未完成时不发布已同步状态。
- 生产变化涉及已有七个共享 Swift 文件；没有新增生产文件、资源、文案、依赖或 SDK API，不涉及品牌差异编译路径。

### 自动验证

| 验证 | 结果与证据边界 |
| --- | --- |
| `python3 scripts/check_node_sync_status_refresh.py` | 通过；原 Scene/Group 状态读取、保护、取消和失效回归继续通过。新增 Timed 大空间、分片共享、状态失效、替换/关闭及保护不可用用例 |
| 487 节点 / 18 组生产规划逻辑隔离夹具 | 单次完整规划 487 次模型订阅读取、487 次同步检查，已覆盖目标的删除检查为 0；不是完整 SDK 或真机性能测量 |
| 320 组小规模规划对照 | 同时执行保留的修复前规划流程及当前完整规划，同步/删除设备及分组清单一致；覆盖目标类型、退出状态、直接目标与待删除组/场景组合。SDK 差异输入用替身提供 |
| `python3 scripts/check_timed_schedule_selection.py` | 通过；执行生产选择处理、离线处理、全选/取消全选、Confirm/Cancel、编辑页异步结果接收和关闭期间刷新函数，覆盖 0/1/多选、筛选隐藏项及迟到回调 |
| `zsh scripts/check_timed_scheduler_single_owner.sh` | 通过；Owner、模型缓存未知/残留、TimeSet 分离及相关入口契约 |
| `python3 scripts/check_sync_task_builders.py` | 通过；任务构建、父子归属、TimeSet/Profile 依赖、组退出、结果/重试范围；不等于实设备下发成功 |
| SunSmart / Debug / generic iOS | 最终代码 `BUILD SUCCEEDED`；workspace 正确使用本地 `one-dev`，`CODE_SIGNING_ALLOWED=NO`，DerivedData 使用 `SunSmart-fix-cli`，无 Simulator/真机运行 |
| 差异检查 | `git diff --check` 通过；SDK 仍无未提交改动；未提交或推送 App 变更 |

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-fix-cli CODE_SIGNING_ALLOWED=NO build
```

初版完成后构建通过；关闭期间状态通知拦截补齐后，做了一次增量构建确认最终代码，亦通过。构建与隔离回归仍有已有警告（例如 AppIntents 未依赖、测试替身中的不可达 default/weak 变量提示），没有构建错误。

### 原附件的修复后隔离复核

另用分析阶段同一份脱敏拓扑夹具、同样的生产函数抽取边界再次计数：

| 日程 | 修复前成员反查触发的 `Node.group` 次数 | 修复后规划夹具中的 `Node.group` 次数 |
| --- | ---: | ---: |
| 日程 2 / 3（每次） | 5,866,402 | 487 |
| 日程 4 / 5（每次） | 239,604 | 972 |

修复后均没有调用 `Group.nodes` 重建成员表。小目标日程的 972 次包含一次全网成员索引和 485 个非目标节点的残留判断，后者保留清理语义。单设备日程在该夹具中没有成员反查。计数仍不包含替身省略的完整 Scheduler Owner / SDK 内部工作，不将其转换为真机加速倍数。

同夹具还确认：重叠组有差异时完整计划和组提示一致；原选 1 台时 Devices 弹窗仍只接收 1 台已选设备。辅助脚本为 `/tmp/sunsmart_timed_fixed_analysis.py`，正式回归在上述仓库测试中。

### 待人工验收

在同一 iPad 的“兴东2”打开日程 1～5，关闭重开并检查三个目标弹窗；Devices 应保留原选择，不误选整网设备。再验证日程启停、修改保存、Sync/Re-sync 以及大组/设备同步；应能继续响应，提示与任务清单一致。最后在相同构建条件下采样 CPU/主线程，确认不再持续停在全网成员反查链。未自动安装、运行或改变设备配置。
