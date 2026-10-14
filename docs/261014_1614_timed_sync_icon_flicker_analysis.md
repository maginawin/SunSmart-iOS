# Timed 开关操作同步图标闪烁分析与优化方案

日期：2026-10-14。工作树：`feat-timed-limited-261008`；分支：`feat/timed-limited-261008`；HEAD：`733d6718`。开始分析时工作树无未提交改动。用户随后确认采用推荐方案，已完成 App 修改和自动化验证，真实设备体验待人工验收；实施记录见文末。未修改 SDK 或依赖，未提交 Git。

## 结论

已确认列表 Cell 存在“先显示需要同步图标，再异步判断并隐藏”的逻辑。任何 Cell 重新绑定都会产生误显示窗口；当前行完成回调及云同步结束后的整表刷新均能触发它。

此外，开关操作先修改本地目标值，再逐设备下发。此时目标与设备缓存的差异是正常过程状态，不能作为本次操作的最终结果展示。推荐同时修复默认显示和操作期间结果发布时机：列表保留上一次已完成结果，操作结束后重新计算并更新。

静态代码能确认上述机制；没有现场录屏、事件日志或本轮真机复现，不能断言用户观察到的每次闪烁分别来自哪次通知。

## 已核对的链路和证据

### 1. Cell 把等待计算当成需要同步

`SunSmart/Main/Timed/View/SchedulesViewCell.swift` 的 `schedule.didSet`：

- 更新开关、时间、名称及布局。
- 生成新的 `syncRequestID`。
- 无条件将 `failedImageView.isHidden` 设为 `false`。
- 调用 `NodeSyncStatusRefresh.request(schedule:owner:completion:)`，收到结果后才设为 `!needsSync`。

图标使用 `schedule_tips`，约束就在 UISwitch 左侧，与反馈位置一致。`prepareForReuse` 虽然取消旧请求，但没有按定时身份保存上一次展示结果。

`NodeSyncStatusRefresh` 至少经过一次主队列异步调度；必要时还要后台准备保护数据、准备拓扑并分片计算。即使命中结果缓存，Cell 的默认显示与回调也不是同一次同步赋值。可见闪烁时长取决于刷新和渲染时序，不能靠关闭 UICollectionView 动画消除；`reloadCollectionItem` 已设置 `CATransaction.setDisableActions(true)`。

### 2. 当前行为什么刷新

`SunSmart/Main/Timed/Controller/TimedViewController.swift` 的 `setScheduleEnabled`：

- 正常成功：隐藏 Processing，显示 Done，刷新当前行，再发送 Space 数据变更通知。
- 失败：显示 Failed，刷新当前行，然后打开 `SyncDevicesViewController`。
- 补同步成功：更新并保存 enabled，再刷新当前行并关闭同步页。
- 补同步返回：关闭同步页并刷新当前行。
- 无现存目标节点：本地保存后直接刷新当前行。

当前行刷新会重新绑定 Cell，从而触发第 1 点。源码没有在普通联网开关流程刚开始时直接刷新当前行；如果实际闪烁明确发生在设备下发完成之前，需要用时间戳区分在途读回调、缓存修复通知、云通知等来源，不能把 `enabled` 赋值本身说成 UI 刷新通知。

### 3. Done 附近为什么其他定时也刷新

确定存在以下调用链：

1. 开关成功后发送 `spaceDataChangedNotificaitonName`，类型为 `.device`。
2. `SpaceViewController` 调用 `space.commitLocalChangeForCloudSync`，标记本地变化并按 promptly 等级入云同步队列。
3. 云同步完成进入 `cloudSyncManager(_:didSyncFinished:)`，该方法无条件发送 `spacePermissionChangedNotificaitonName`。
4. Timed 收到通知调用 `refreshVisibleUI → updateUI → reloadData`。
5. 所有重新绑定的可见定时 Cell 都先显示图标，再等待异步结果。

这是与 Done 后其他行一起闪烁相符的明确代码路径，但云同步是否紧邻 Done 取决于运行时条件，尚未用现场日志确认。

其他整表刷新来源包括 `schedulesRefreshNotificationName` 和 `SpaceSchedulerReadCoordinator.didUpdate`。后者在每批未知 Scheduler 缓存读取结束时失效同步状态缓存并通知页面。只修改成功回调中的单行刷新不能覆盖这些入口。

### 4. 下发中的差异并不代表最终失败

`SunSmart/Main/Timed/Model/ScheduleServer.swift` 的 `setEnabledState` 在发命令前立即修改 `schedule.enabled`。`Scheduler.swift` 的 `schedulerEntry` 根据 enabled 生成不同 year 编码。

随后按设备批次下发，成功回执经 `applyMessageHandle → Node.updateData` 更新设备 Scheduler 缓存；最终还会检查槽位和 `needsSync`。因此，本地目标已更新、设备缓存尚未更新时，比较结果完全可能是 true，且多个设备可以处于不同阶段。

失败时现有业务规则是：部分设备成功则保留新 enabled；全部失败则恢复旧 enabled，并保存。UI 应在这些收尾完成后计算，不能简单以“成功必隐藏、失败必显示”替代判断。全部失败并回滚后也可能已与设备一致。

`SpacePageSyncRead` 不只比较当前目标，还检查待删除及孤立条目。最终判断需要沿用该完整范围，不能缩减为仅当前下发设备。

## 方案比较

| 方案 | 做法 | 效果与限制 |
| --- | --- | --- |
| A：只修 Cell 默认显示 | 未得到结果时不主动显示图标 | 可消除确定存在的误显示窗口；无法阻止操作中的真实临时差异通过回调展示；已有警告若每次都先隐藏，也可能反向闪烁 |
| B：稳定展示 + 操作结束后发布（推荐） | 保存上次已完成显示结果；开关流程期间冻结图标发布；收尾后重算；校验回调身份与版本 | 同时覆盖默认误显示、操作中间态、Cell 复用和结束后重复刷新，符合本次目标 |
| C：减少重复刷新 | 区分权限刷新与内容刷新，合并重复刷新，仅刷新有变化的行或图标 | 可减少开销；单独采用不能保证没有闪烁，可作为 B 后的可选优化 |

不建议固定延时隐藏、0.3 秒防抖或同步阻塞主线程计算。它们无法定义业务完成边界，且大规模设备、断连和重试会改变耗时。

## 推荐方案的具体边界

### 展示规则

- 第一次绑定且没有已完成结果：暂不显示同步图标；这只是尚未展示结论，不写入“已同步”业务状态。
- 已有已完成结果：异步重算及刷新期间保留该结果；既有真实警告不因重新绑定先消失再出现。
- 开关操作开始：在修改 enabled 前进入页面级操作状态，废弃或取消本页在途图标读请求；操作期间不发布新图标结果。
- 操作期间出现刷新通知：可以更新必要的权限等 UI；记录图标待刷新状态，避免用全局屏蔽通知阻断其他业务。
- 操作完成：待模型保存、保留或回滚完成后，重新读取最终状态；收到本轮有效结果再更新图标，值未变化不重复赋值。
- Done 继续表示下发流程结果，不把 Done 当作所有定时均已同步的证据，也不必等待云上传结束才结束本地开关操作。之后云通知仍可重算，但等待期间保持已显示结果。

页面应持有按当前 Space/网络与定时身份区分的展示结果，使 `reloadItems`、`reloadData` 换 Cell 后也能延续稳定显示；不要仅靠 Cell 自身保留 UIImageView 状态。计算结果有效性继续由对象身份、`SpacePageRevision` 和请求票据控制。旧展示值可暂留，但不能作为新版本下的计算缓存或命令执行依据。

开始/结束操作需要独立的操作票据，防止开始前或上一轮回调覆盖本轮结果。结束时确保最终读取使用新一轮状态，必要时沿用现有 `NodeSyncStatusGeneration.invalidate()`，避免共享 reader 复用过程结果；不要全局暂停共享 reader，影响 Group/Scene/设备页面。

### 操作结束的定义

| 路径 | 更新最终图标的边界 |
| --- | --- |
| 正常成功 | 所有批次完成、模型收尾后 |
| 部分或全部失败并转入补同步页 | 原失败回调暂不发布新图标，保持到补同步成功或用户退出；同步页自己的进度/失败提示保持现有行为 |
| 补同步成功 | 最终 enabled 保存并完成该流程后 |
| 补同步停止/失败后返回 | 收尾/关闭执行会话后按现存模型重新判断；晚到状态更新仍须走新版本刷新 |
| 无目标节点 | 本地保存完成后；最终读仍覆盖待清理条目，不预设隐藏 |
| 无连接、无权限 | 操作未启动，不留下忙状态或延迟刷新锁 |
| 页面退出、Space 切换、再次进入 | 取消失效 UI 请求；在原作用域保留必要操作生命周期，禁止旧回调更新新 Space；重进使用当前模型重新校验，不能持久化“操作中”状态 |

### 对“真正结果”的限制

现有 Bool 查询将两类情况都归为 true：已确认配置差异，以及 Scheduler 模型未知/保护数据不可读。`NodeSyncStatusRefresh.finishUnavailable()` 也会回调 true。这是既有保守安全策略，不等于回执明确证明设备配置错误。

本次建议首先区分“读请求尚未结束”和“操作尚未结束”，两者都不制造新警告；操作结束后维持现有完整判定与未知状态保护语义。如果产品进一步要求图标只能代表“已确认存在差异”，则需单独引入展示层的 unknown / synchronized / needsSync 结果及未知提示，不能将共享 Bool 的 true 直接改为 false。这会扩展交互和兼容范围，不作为消除本次闪烁的默认修改。

## 复用、范围与关联影响

- 复用 `NodeSyncStatusRefresh` 的分片、缓存、版本失效和取消机制，以及 `SpacePageRevision` 的作用域判断。
- 已检查 `GroupSyncDisplayState` 及其 Device/Group 使用方：可参考其票据与版本管理，但其接口只支持 Node/Group，且没有操作冻结及跨 Cell 的定时展示结果所有权；不宜仅为本次需求泛化所有页面。
- `ScheduleTargetDisplayState` 服务定时目标选择器，缓存目标明细；直接用于列表会引入不必要的完整目标计算。列表继续使用现有 Bool 查询。
- 必需修改集中在 Timed 列表控制器、Cell 及最小的定时展示状态管理。实际实现应以职责清晰为准，不强行限定文件数量。
- `ScheduleAddViewController.refreshSyncStatus` 也有先设未完成再异步更新的相似模式，属于设置页的相关显示问题；本次列表需求不自动扩大到设置页交互。
- 权限通知触发整表刷新可单独优化；不能简单移除通知，因为它的其他使用方仍需处理真实权限变化。
- 共享 Timed 页面影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux。无协议、固件、后端、数据库格式或历史数据迁移需求；无需新增 SDK API。

## 实施后的最小有效验证

1. 增加针对生产展示状态及列表回调时序的行为夹具：初始 pending 不显示；已有 true/false 刷新不跳变；操作中间 true 不发布；最终 true/false 正确发布；旧回调、复用、重复通知、作用域切换被隔离。
2. 覆盖正常成功、全部失败回滚、部分成功、补同步成功/返回、无节点与未连接，以及已有其他未同步定时的情况。失败不等于必显示，成功也不强制其他行隐藏。
3. 复用 `scripts/check_node_sync_status_refresh.py`，确认共享读取、取消、失效和 Timed 目标语义未回归。现有脚本包含 `TimedSyncReadTests`，但未直接验证 `SchedulesViewCell` 和 `TimedViewController` 的本次显示时序，不能只以原脚本通过作为验收。
4. Swift 生产代码修改稳定后按项目要求运行一次 SunSmart generic iOS Debug 构建，先核对本地 workspace/SDK 映射。若无品牌专用编译差异，不机械重复五品牌构建。
5. 人工最短验收：准备至少 3 条已同步定时，连续切换其中一条，观察 Processing、Done 及后续云同步结束时全部图标；再让一个目标离线制造部分失败，补同步或退出，确认仅最终仍需同步的项目显示图标。已有未同步定时应保持显示，滚动复用与退出重进不得将图标状态带到其他行或保留失效状态。

分析阶段仅完成静态链路核对，未运行测试、App 构建或真机验收。若需要精准确认两次闪烁的现场触发源，可增加仅 DEBUG 的操作开始/结束、刷新原因、查询票据及发布结果日志，不输出凭据或密钥。

## 实施与验证记录（2026-10-14 16:25）

用户确认采用推荐方案后完成以下改动：

- `SpacePageSyncRead.swift` 增加仅用于 Timed 列表的 `TimedListSyncDisplayState`。页面保存每个定时的已完成结果，计算版本过期时仍保持旧展示值；用对象、网络、账号、区域和操作/请求票据隔离迟到回调。沿用共享 reader，不改变其未知状态保护规则。
- `SchedulesViewCell.swift` 去除默认显示警告及 Cell 内独立查询，由页面传入展示结果；复用时清除旧绑定的图标和点击回调。
- `TimedViewController.swift` 在 enabled 变更之前冻结查询发布，正常成功、本地空目标保存、补同步成功或返回时结束冻结，失效共享计算缓存并刷新可见图标。失败转入补同步页时继续冻结。离开页面取消读请求，重进重新校验；预加载 Cell 进入可见区域时应用已经完成的结果。
- 保留必要的权限/内容刷新，不删除云同步通知；页面释放后原成功操作仍能发出既有 Space 变化通知。后台完成失败时不从不可见页面弹出补同步页，而是结束本次展示冻结，重进后重新判断。
- 未修改下发协议、`ScheduleServer` 的成功/部分成功/回滚规则、数据库、国际化、资源归属或 target 配置。没有新增依赖或 SDK API。

验证结果：

| 检查 | 结果与边界 |
| --- | --- |
| `python3 scripts/check_timed_list_sync_display.py` | 通过。提取并执行生产展示状态、图标更新、开关/补同步完整回调和 willDisplay；以可控传输、存储和 UI 边界覆盖 pending、重复刷新、操作冻结、成功、部分失败、全部失败回滚、补同步成功/返回、空目标、未连接、不可见页面、预加载、复用、取消、旧操作及旧作用域、页面释放后云通知。不是源码文本断言，也不是真实 UIKit/Mesh 验收 |
| `python3 scripts/check_node_sync_status_refresh.py` | 通过。覆盖共享分片读、版本失效、保护失败、取消、Timed 目标及选择器、Group/Scene 显示等原有行为；运行时有既有编译警告，无测试失败 |
| SunSmart generic iOS Debug | 最终修改后增量构建通过：`SunSmartLocal.xcworkspace`、SunSmart scheme、`iphoneos`、`generic/platform=iOS`、`CODE_SIGNING_ALLOWED=NO`；首轮编译后补充预加载和页面释放边界，因此完成补充后的编译复验 |
| 差异检查 | `git diff --check` 通过 |
| 真机/UI/BLE/云端运行验收 | 未执行，不能由隔离测试或构建替代；按上一节第 5 项操作验收 |

本地 SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `2598bd1`，核对时工作树干净。DerivedData 复用 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-timed-limited-261008`。改动为五品牌共享代码且无不同编译路径，本轮只编译代表 target SunSmart，未执行其余品牌构建。
