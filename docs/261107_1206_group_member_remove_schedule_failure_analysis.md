# Group Member 移除卡在 Remove schedule 的原因

**最新状态（2026-11-07）：已按第 14 节完成计划进度、初始 Scene 任务及加载框修复，相关回归和 SunSmart Debug generic iOS 构建通过。14:43 复盘时核对：App 修复已整合到 `4d29b4e9`，SDK 前几轮修复在 `165d916`；两个工作区当时干净，本次仅更新本文。最后一轮未修改 SDK、未操作真机；真实页面是否消除闪烁仍待同场景验收。第 14 节保留日志分析，第 15 节记录实施，第 16 节汇总整个 session 的问题、出现时机及预防措施。**

首次分析（2026-11-07）：**当时 App 与 SDK 的结果判定存在确定的生命周期缺陷：成功清除定时并释放绑定后，重新使用“旧任务还能否发送”的条件判断已经收到的回执，把本次成功改判为失败，阻断后续退组。** 当时 L1、L2 首次清除均收到内容一致的设备回执；L1 重试没有重发清除，而是直接退订组，吻合此缺陷。

已按用户确认完成 App 修复，相关回归及 SunSmart Debug generic iOS 构建通过；未提交、未操作真机，修复后实际 Mesh 验收仍未完成。下文第 1–7 节保留分析依据，第 8–9 节记录实施结果。

## 1. 输入及版本

- L1：`/Users/maginawin/Desktop/Xcode remove group logs .txt`，678 行，包含首次尝试与点击重试。
- L2：`/Users/maginawin/Desktop/remove L2 failed log.txt`，343 行，只包含首次尝试；重试成功是用户现场反馈。
- App：`feat/device-scene-261028`，HEAD `e767305e79aafd08e5f8c69722d8a26353b32865`。
- 本地 SDK：`.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，叠加上一轮 Scheduler 传输修复的未提交差异。本轮未改动这些差异。
- 日志没有独立的 App/SDK revision 标识，源码结论基于上述当前工作区；不能凭日志精确证明安装包 revision。

上一轮分析及实施记录：[日程 1 同步失败分析](261107_1137_timed1_sync_failure_analysis.md)。本次是清除回执已经收到后的结果处理问题，区别于上一轮传输等待和占用问题。

## 2. 两份日志的共同证据

| 证据 | Dongle- L1 | Dongle-L2 |
| --- | --- | --- |
| 设备 Primary Element | `49F9` | `49FC` |
| 本次定时清理 | 87–89 行：Schedule id `0`，slot `0`，发往 `49F9` | 63–65 行：Schedule id `0`，slot `0`，发往 `49FC` |
| 实际 Access 请求 | opcode `0x60`，参数 `40060080791EF03F0000` | 相同 |
| 实际 Access 回执 | 98–104 行：opcode `0x5F`，相同参数，source `49F9` | 74–80 行：opcode `0x5F`，相同参数，source `49FC` |
| 设备报告的内容 | index `0`、`noAction`，完整 entry | 相同 |
| 首轮之后 | 继续处理 Scene/Profile 清理，未开始 `C015` 组退订 | 同样继续清理，整个文件无 `C015` 退订命令 |
| 重试 | 358 行点击；359–609 行开始 `C015` 的 21 条 Model Subscription Delete，均有 Success 回执 | 文件未包含重试 |
| 重试时是否再次清定时 | 没有第二条 SchedulerActionSet，也没有 SchedulerGet/ActionGet | 无法从提供文件判定 |

这里有真正的 `Sending Access PDU` 及匹配响应，不能只看构造任务时的 `ScheduleSend delete`。两份文件均没有本次 Scheduler 的 `busy`、拒收或超时错误。`manualOverrideTimeout` 是其他配置参数名称，不是超时失败。

`Local Scheduler Server ... on Primary Element (0x0001) not bound to key` 指向 App 本地模型；不是远端 L1/L2 拒绝操作。本次回执已经解码并分发，不能把该提示当作这次 Remove schedule 失败的原因。两轮 CloudSync 的成功只表示云上传完成，也不能代替退组任务成功。

两份日志只展示清除了 id/slot `0`，没有提供此次完整 Schedule 配置快照，不能从中推导另一个定时的名称、全部目标或全部 slot 状态。

## 3. 完整触发链

1. **退出组要求先处理定时。** `Node.getNodeNeedDeleteSchedules` 按当前目标关系和缓存生成清理任务；`SyncDeviceTaskBuilder` 将其显示为 `Remove schedule`，并把该步骤列为退出组的前置条件。退出组相关的定时清理失败，因此可以阻止 `C015` 的正式退订，但不阻止所有其他独立清理任务。
2. **保留待清理绑定。** `Schedule.getMessageHandles(delete: true)` 调用 `reserveForDeletion`，将本设备对应绑定保留为 `pendingRemoval`。它只给未知或该 slot 仍有效的 Scheduler Model 生成清除消息，已确认清空的 Model 不重复发。
3. **捕获旧绑定作为发送条件。** `TimedSchedulerTaskCoordinator.attach` 生成运行期 task，捕获包含 binding、目标关系、entry 的 intent；`transmissionIsValid` 要求当前 intent 仍等于捕获值。
4. **设备正确回应。** 两份现场日志均显示完整、同 source、同 slot、同参数的 `SchedulerActionStatus(noAction)`，SDK 更新对应 Model 观察状态。
5. **SDK 先结束发送，再交给 App 完成回调。** `MeshProxyMessageCommand.finishMessages` 先 `reset()` 再调用 `finished`，此时 Proxy 已空闲，因此允许释放已清空的槽位。
6. **App 应用结果并删除绑定。** `SyncExecutionSession.applyResult` 先以当时的 `handle.isSuccessful` 调用 `node.applyMessageHandle`。`Node.updateData` 的 SchedulerActionSet 分支在所有普通 Scheduler Model 已知且该 slot 清空后调用 `releaseClearedBinding`；它保存设备观察并移除当前设备的 `nodeSlots` binding。
7. **完成动作使发送条件失效。** binding 删除后，协调器 `intent(currentSchedule, node:)` 返回 nil，原 `transmissionIsValid` 变成 false。这本来是合理的：已完成的旧消息不应再发送。
8. **再次判断回执时用错条件。** SDK 的 `MeshMessageHandle.isSuccessful` 每次访问都会计算 `task 未取消 && transmissionIsValid && 已响应地址齐全`。App 在写回之后再次读取它，得到 false；尽管 `schedule.deletionIsSynchronized(on:)` 已经是 true，普通任务仍因 `resultSuccessful && operationSuccessful` 为 false 而标记失败。
9. **退组被前置失败挡住。** `Remove schedule` 失败后，依赖它的退出组任务等待；设备实际已清除的状态与同步页面状态分离。

关键点：`configurationSaved` 已有“清理完成释放绑定不取消自己的 task”的例外，本次探针中的 `task.isCancelled=false`。缺口在于该例外没有改变 `isSuccessful` 对动态发送条件的依赖；仅确认 task 未取消并不足以保留成功回执。

相关源码：

- [TimedSchedulerTaskCoordinator.swift](../SunSmart/Main/Timed/Model/TimedSchedulerTaskCoordinator.swift)：`attach`、`intent`、`configurationSaved`。
- [TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift)：`reserveForDeletion`、`releaseClearedBinding`、`deletionIsSynchronized`。
- [MeshNetwork+SunSmart.swift](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：`Node.updateData` 的 SchedulerActionSet 结果处理。
- [SyncExecutionSession+Result.swift](../SunSmart/Main/Space/Model/SyncExecutionSession+Result.swift)：先应用结果，再读取 `isSuccessful`。
- [SyncDeviceTaskBuilder.swift](../SunSmart/Main/Space/Model/SyncDeviceTaskBuilder.swift)：Remove schedule 和退出组依赖。
- SDK `MeshProxyMessageCommand.swift`：`finishMessages`、`MeshMessageHandle.isSuccessful`。

## 4. 为什么重试成功、为什么有关联定时时出现

第一次已经收到了清除回执，且该设备 binding 已成功释放。重试重建任务时，`reserveForDeletion` 允许没有本设备绑定的已清除状态；`getMessageHandles` 因没有 slot 返回空数组，`deletionIsSynchronized` 返回 true。空结果列表不含失败消息，普通任务转为成功，随后放行组退订。这与 L1 重试后直接出现 `C015` 的 Subscription Delete 一致，不需要用“第二次蓝牙变好”解释。

组目标定时会在相关设备退出组时产生设备侧清理，因而进入这条有缺陷的结果路径。问题不要求“同时存在两个定时”或“两个定时竞争一个设备”才会发生；单个待清理绑定也可复现。直接设备目标或其他仍有效的目标应按其原有归属继续保留，不能为了退组删除整条全局定时。此次日志不足以审计用户提到的另一条定时的完整目标配置。

## 5. 隔离复现与已有测试缺口

已执行临时探针：`python3 /tmp/timed-remove-schedule-probe.py`。

探针直接提取并编译当前生产 `TimedSchedulerTaskCoordinator`、`releaseClearedBinding`、`deletionIsSynchronized`、SDK `MeshSchedulerTask` 和 **实际 `MeshMessageHandle.isSuccessful` getter**，使用生产 `SyncOperationResultPolicy` 汇总。模型、编码 entry、设备观察、保存返回值与传输完成由受控替身提供；没有运行完整 Session、真实 SQLite、BLE 或 UI。

| 探针情形 | 观察结果 |
| --- | --- |
| 单 Model 完整 ACK | 释放前 `isSuccessful=true`；释放 binding 后 `cancelled=false`、`transmissionValid=false`、`isSuccessful=false`；业务删除判断为 true，最终结果却为 false |
| 两个 Model 均 ACK | 同样出现成功回执被改判失败，证明不是某个设备地址特例 |
| 已释放后空任务重试 | 不再发送 Scheduler 写入，最终结果为 true |
| 未收到 ACK | binding 保留，结果失败 |
| Model 未知或其他 Model 尚有残留 | 不释放 binding，业务结果仍失败 |
| 真实配置替换 | 旧 task 取消，旧结果仍失败 |

保存失败注入仅验证 `releaseClearedBinding` 恢复内存 binding；探针未覆盖真实存储，且删除同步条件本身仍可能为 true，不能据此声称持久化失败路径已经完整验证。后续修复需明确覆盖保存失败和重启重试。

当前仓库 `python3 scripts/check_timed_task_replacement.py` 在本轮仍通过，但 `Tests/Timed/TimedTaskReplacementTests.swift` 的替身把 `isSuccessful` 简化为 `successful && task未取消`，遗漏了真实 SDK 的 `transmissionIsValid`。现有用例甚至同时断言“绑定释放后发送无效”和“回执成功”；由于替身不同于生产代码，未能发现两者冲突。此前该套件通过不能证明当前 App/SDK 集成正确。

## 6. 与上一轮修复的关系、同类入口

- SDK 的成功 getter 中动态校验 `transmissionIsValid` 可追溯到 `4b4c0f56`（2026-11-04）；Task Coordinator 和清除完成不取消 task 的例外来自 App `b6f56743`（2026-11-05）。当前这组冲突条件早于今天上一轮传输修复。
- 上一轮未修改这个 getter、App 绑定释放或结果汇总。此次两个清除回执参数完全一致，日志没有上一轮传输 busy/异常响应拒收的特征，因此不支持把本次失败归因于新加的响应过滤。
- [ScheduleServer.swift](../SunSmart/Main/Timed/Model/ScheduleServer.swift) 的 `runScheduleDeviceBatches` 也在 `reconcileBinding` 后再次检查消息 `isSuccessful`，存在同类边界；修复不能只改 Group 页面显示。
- 本次 field 日志未打印 binding 释放与结果布尔值，因此“现场进入该内部分支”的判断来自日志顺序、当前源码和确定的隔离复现三者结合；尚未添加诊断重跑完整 App。

## 7. 建议的最小完整修复范围

1. 分开“是否允许继续发送旧任务”与“此前已匹配并接受的回执是否成功”。批次开始应用结果时先校验并保留回执结果，应用全部相关 Model 的结果及完成持久化后再统一释放绑定，避免完成本身反过来否定回执。
2. 同步覆盖 `SyncExecutionSession` 与 `ScheduleServer` 的结果处理。最终成功仍要求当前业务状态已同步；真实取消、新任务接管、设备身份/网络变化、错误 slot/参数回执继续失败，不能全局删除有效性检查。
3. 修正测试替身与 SDK 的差异，覆盖“实际成功 getter → 多 Model ACK → 结果应用 → 持久化 → binding 释放 → 任务状态 → 退组放行”的连续边界。补保存失败、未知/部分清理、退出重进、迟到 ACK/slot 复用；重试只处理未完成目标。
4. 需要补日志时，仅在 DEBUG 中记录 schedule id、设备/slot、回执是否接受、binding 是否释放、任务是否取消及最后失败原因，不记录密钥或完整 JSON。

这是 App/所用 SDK 结果处理范围，不需要固件或服务器配套，不需要数据库、export JSON 结构或语义变更。实现时优先在 App 的结果处理边界解决，若需 SDK 内部回执机制调整，仍须保持通用消息、取消及旧任务保护语义。

最短修复后人工验收：给组成员配置有效组目标定时 → 首次移除 L1/L2 → 确认清除成功后 Remove schedule 直接成功并开始组退订；不点击重试也能完成。再验证一个 Model 离线/拒答时仍失败，恢复后只补未完成清理，以及另一个仍有效的独立定时继续保留。构建、离线回归与上述真实 Mesh 验收分别记录。

## 8. 已授权实施计划

用户已确认实施第 7 节方案；沿用当前工作树，由本任务直接实现，不启动子代理、不提交。使用 Superpowers 的计划、执行与测试先行流程，按项目规则在本文记录，不另建计划文件。

目标：首次成功清除后直接放行退组；取消、接管、错误回执、未知/部分清理及保存失败继续可重试。Swift / 当前本地 SDK / 既有独立回归脚本；数据库和 JSON 不变。

- [x] 先补失败回归：采用 SDK 实际成功 getter，执行结果应用与绑定释放，覆盖单/双 Model 及重试。
- [x] 在 `TimedSchedulerBindings.swift` 增加 `Schedule.applySchedulerResults(_:expected:on:) -> Bool`，保存本批次回执判断；每条结果暂缓 binding 收尾，全部应用后统一保存、协调并检查任务取消。沿用现有绑定，不增加持久状态。
- [x] `Node.applyMessageHandle` / `updateData` 增加默认保持旧行为的收尾参数，`reconcileBinding` / `releaseClearedBinding` 返回持久化结果。接入 `SyncExecutionSession+Result` 和 `ScheduleServer`，空任务重试同样经过最终状态检查。
- [x] 回归覆盖真实 SDK getter、App 生产处理及 SQLite 保存/重载；保留部分失败、未知模型、存储失败、旧回执、其他 slot/设备和仍有效直接目标的保护。
- [x] 检查最终 diff，运行相关回归及 SunSmart Debug generic iOS 构建，更新实施与人工验收边界。

## 9. 实施与验证结果

生产改动集中于 4 个 App 文件：`TimedSchedulerBindings.swift`、`MeshNetwork+SunSmart.swift`、`SyncExecutionSession+Result.swift`、`ScheduleServer.swift`。

- 新共用批次入口先确认返回消息与预期消息一一对应、任务未取消，再固定各条 `isSuccessful`。成功消息逐条应用但暂不释放 binding；随后保存设备观察、统一协调 binding，并再次检查任务取消。
- 部分失败保存已确认的进度，保留待清理绑定。重试根据现有 Model 缓存只发未完成部分；设备已清空但上次绑定保存失败时，可通过空消息批次完成保存，不重复下发清除。
- 删除/配置 Schedule 的 Session 结果和 `ScheduleServer` 的空/非空批次都使用同一入口。`ScheduleServer` 不再在逐条成功回调中提前做 App 收尾，统一在批次完成时应用。
- `reconcileBinding`、`releaseClearedBinding` 现在返回保存结果，恢复原绑定后返回 false；节点属性保存失败也不报告批次成功。未取消条件和最终业务同步状态仍是成功前提。
- SDK 的动态 `isSuccessful`、发送有效性、回执过滤、取消机制均未改动。本次没有新增 SDK API/发布依赖；本地构建仍包含上一轮尚未发布的 SDK 差异，发布前应按上一轮记录处理。
- 无数据库、JSON、模型持久字段或协议参数变更；没有新增命令或调整 ACK、超时、重试次数，没有改变定时目标/Model 路由。共享 App 逻辑无品牌差异、资源或工程归属变化，代表 scheme 选 SunSmart。

回归先将既有替身替换为生产 SDK getter，观察到 `normal cleanup must preserve successful receipts: success` 断言失败，再完成修复及新的结果入口断言。新增 `Tests/Timed/TimedSchedulerResultTests.swift` 使用生产 Coordinator、App 结果处理、Node 的 Scheduler ACK 分支、绑定上下文、Schedule 编解码和 SQLite 写入/独立连接重载，不再只测简化的成功标记。

| 本轮执行检查 | 结果 |
| --- | --- |
| `check_timed_task_replacement.py` | 通过。实际 SDK getter、批次结果、多 Model、自身完成后的旧消息不可发送、保存失败重试、未知/部分状态、忙碌、真实替换，以及原有启停回滚/批次隔离。 |
| `check_timed_slot_persistence.py` | 通过。新增 11 类结果场景：单/双 Model、部分 ACK、未知 Model、Node/SQLite 保存失败、取消、配置替换、设备身份变化、缺失/重复结果；独立 SQLite 连接重载，已完成后 0 条清除重试、部分失败仅 1 条重试，同设备直接目标及其他设备保留。原有持久化/目标/迁移套件继续通过。 |
| `check_sync_execution_session.py` | 通过。生产 Session 的 Schedule 删除/配置接入、先应用所有结果再收尾、存储失败传播；原有取消/STOP/迟到回调与其他业务回归通过。 |
| `check_timed_delete_result.py` | 通过。生产 ScheduleServer 批次使用共用结果入口；预约失败、旧回复不满足业务清除仍失败，确认清空后完成。 |
| `check_sync_task_builders.py` | 通过。Group 退出依赖、成功矩阵、重试关联和结果作用域；已有不可达 default 警告。 |
| `check_scene_deletion_flow.py` | 通过。共用 Node 回写入口的多 Element、Group 成员移除、删除、持久化恢复及旧回执保护。 |
| `check_scene_configuration.py --suite save` | 通过。Scene 保存/删除/协调器与共用 Node 包装入口。 |
| 静态检查 | `git diff --check`、`plutil -lint SunSmart.xcodeproj/project.pbxproj` 通过。 |
| SunSmart Debug generic iOS | Xcode 27.1（27A9275），`SunSmartLocal.xcworkspace`，关闭签名，构建退出码 0；仍有项目原有 weak capture、actor 隔离等警告。未使用 Simulator。 |

SQLite 脚本初次被默认 Clang module cache 的沙盒写权限阻断；指定可写的 `/tmp/sunsmart-clang-module-cache` 和 `/tmp/sunsmart-swift-module-cache` 后通过，没有清理共享缓存。Scene 测试另发现既有夹具未声明 `withLocalChange`；补了明确拒绝调用的测试边界，因为 Scene 存储走 `markCloudChange=false`，真实 Timed revision 事务继续由 SQLite 套件执行，并未用替身伪造它通过。

最终审查由本任务自查，遵循不启用子代理的项目规则。没有新增未处理的本范围审查项；保留如下验证边界：传输/硬件与部分 SDK Node 属性存储由夹具提供，协议 entry 为合成输入；没有运行完整 UIKit、真实 BLE、服务器往返或其他品牌构建。SQLite 与离线行为通过不能替代实际设备验收。

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-cli CODE_SIGNING_ALLOWED=NO build -quiet
```

最短人工验收：

1. 重新准备 L1/L2 在组 1 中、关联组目标定时的状态，各首次移除一次。清除 ACK 后 `Remove schedule` 应直接成功并继续退组，无需手动重试。
2. 保留另一个仍有效的直接设备目标定时，确认它及其他组成员未被清除。
3. 制造中途离线/部分失败后返回重进再重试；未完成部分应继续清理，已确认完成的 Model 不重复下发。最后核对设备读回及 App 重进后的成员状态。

## 10. 再次同时移除 L1/L2：新日志证据

输入：`/Users/maginawin/Desktop/remove members from group logs .txt`，602 个逻辑行（末行无换行，因此 `wc -l` 为 601）。App 分支/HEAD、SDK realpath/HEAD 与第 1 节一致，叠加之前的移除修复及随后添加成员修复的未提交差异。新日志仍无安装包代码版本标识，无法仅凭日志核实真机运行的差异与工作区逐项一致。

| 日志位置 | 事实 | 解释及边界 |
| --- | --- | --- |
| 1–213 行 | L1 `49F9` 的 Scene 18–21 及 Profile/LC 配置清理均收到响应 | 文件从清理中途开始，没有 L1 的 SchedulerActionSet/Status；不能据此认定 L1 未发送或已清空 |
| 214–261 行 | L2 删除虚拟组 `C018` 的订阅，返回 Success | 这是 Switch 相关清理，不是正式退出组 `C015` |
| 262–264 行 | L2 `49FC`、Schedule id 0、slot 0，发送 SchedulerActionSet；Access opcode `0x60`，参数 `40060080791EF03F0000` | 确认已真正下发，不只是构造命令 |
| 273–279 行 | source `49FC`，Access opcode `0x5F`，参数完全相同；解码为完整 entry、index 0、action `noAction`，分发到 MeshLibManager | L2 对该 Element/slot 报告清除完成；不能单独证明其他 Model 状态、App binding 保存或任务最终成功 |
| 280–499 行 | 继续 L2 Scene 18–21 和 Profile/LC 清理，均有响应 | 执行器能够继续独立任务；不是整个 Mesh 队列一直挂住 |
| 512–542 行 | CloudSync HTTP/business 200 | 只表示云上传成功，不表示退组成功 |
| 全文件 | 没有真实组 `C015` 的 Subscription Delete；没有 ScheduleTransport 错误、busy、TimeZone 流程或明确的超时错误 | 与用户反馈的定时前置任务阻挡退组一致；不支持继续套用之前的 TimeZone/busy 根因 |

`manualOverrideTimeout` 是配置字段，不是超时。275–278 行的 `not bound to key` 指向 App `0001` 的本地模型；279 行已出现全局解码消息，该提示本身不能证明远端设备拒绝清除或 ACK 丢失。

**目前结论的强度：** L2 的单条清除命令及其匹配回执是已证实事实；结合用户反馈，排查重点已落在回执之后的 App/SDK 状态收尾。不能由此排除所有设备状态问题，也不能确定 L1 与 L2 触发同一条失败分支。新日志没有重试片段，本轮不沿用此前“重试无需重发”的现场结论。

## 11. 当前源码核对及未闭合边界

之前的修复仍存在：`SyncExecutionSession.applyResult` 的 Schedule 路径调用 `Schedule.applySchedulerResults`，在释放 binding 前固定各条回执的接受结果，逐条应用时传入 `finalizeSchedulerBinding: false`。因此不能把第 3 节旧触发链当作这次已经证明的根因。

当前路径仍有以下不同的失败出口；现场日志没有区分它们：

| 判定阶段 | 当前必要条件 | 本次缺失证据 |
| --- | --- | --- |
| 接受批次 | expected/results 是同一组 handle、task 未取消、回执地址齐全、捕获的发送 intent 仍有效 | handle 所属任务、接收地址、取消/intent 失效原因 |
| 应用观察 | `TimedSchedulerMessageContext` 的设备身份、网络、slot、pendingRemoval 仍匹配 | context 是否匹配；SDK 是否接受该响应写入 Model 缓存 |
| 保存设备状态 | Node 属性保存成功 | 返回值和失败阶段 |
| 完成清理 | 所有 Scheduler Setup Model 的观察状态已知，目标 slot 均无有效 entry；Proxy 空闲；binding 仍为 pendingRemoval | 每个 Model 是未知、空还是仍占用；Proxy/binding 状态 |
| 释放 binding | Schedule 保存成功；完成后 task 没有被取消 | 保存返回值；`configurationSaved` 是否撤销了本次任务 |
| 展示结果 | 共用批次结果和 `operation.isSuccessful` 同时成功 | 最终 result、失败原因和依赖阻断任务 |

SDK 在 `MeshLibManager` 分发时先执行 `Node.updateNodeStatus`。其中 `MeshSchedulerObservation.accepts` 可以因过期 owner、响应不匹配或需要完整读回而拒绝更新，并把对应 Model 缓存降为未知。App 随后的 `Node.updateData` 对未知 Model 的 clear 不会直接把整张寄存器认作已知空；`releaseClearedBinding` 因而可能拒绝释放。这是必须覆盖的具体代码路径，但**本次没有 observation 拒绝日志，尚不能认定它就是现场原因**。合法未知状态应保留安全保护，而不是无条件放宽为成功。

现有 `traceSceneSync` 仅对 Scene 场景启用，Group 操作缺少上述收尾记录。SDK 传输报错只解释发送失败，无法解释正常 ACK 后 App 返回 false。这是本轮确认的诊断缺口。

本轮重新运行 `check_timed_slot_persistence.py`，退出码 0，含既有的单/双 Model、部分成功、未知状态、保存失败、取消、替换、设备身份及回执集合测试。其局限也已核实：`TimedSchedulerResultTests` 手动标记响应地址并移除 Model 缓存中的 slot，再调用 App 生产结果代码；没有执行实际 SDK observation、消息分发、Proxy 回调与 App 结果处理的连续路径。因此通过只说明旧缺陷的已建模路径仍通过，不说明当前现场问题已复现或消失。

## 12. 本次修复计划（已授权，实施状态见第 13 节）

### 12.1 先补可判断的结果证据

在现有机制内增加 DEBUG 诊断，不新增持久化状态或独立重试系统：

1. Group 同步开始记录可区分安装包的版本/诊断标记、run、设备地址、任务类别；批次完成记录预期/返回数量、最终成功与原因。避免再次用应用结果后已失效的动态 `isSuccessful` 统计“原始 ACK 数量”，以接受结果时的快照记录。
2. `applySchedulerResults`、`reconcileBinding`、`releaseClearedBinding` 的失败出口分别记录阶段及原因，区分不匹配、取消、未知 Model、slot 仍有效、Proxy 忙、Node 保存失败、Schedule 保存失败；正常结果用一条汇总。
3. SDK observation 仅在拒绝观察时记录地址、slot、原因；task 仅在失效时记录取消来源。不要打印 Device Key、AppKey、Network Key、完整配置或高频逐项日志。

### 12.2 覆盖完整边界后确定业务改动

在既有 `Tests/Timed` 与 SDK standalone 夹具中补“同一会话添加成员成功 → 同时移除两台设备”的连续行为复现，连接真实 Scheduler 编解码、observation 判断、Proxy 成功/finished 顺序及 App 收尾，保留 SQLite 保存/重载；传输使用受控替身，不建新 Xcode 工程。

优先覆盖：当前匹配 ACK 正常完成；旧 task 取消/迟到 ACK 后的新清除；两个 Model 其中一个未知或失败；两设备顺序处理；中途 STOP、取消、重新添加替换；保存失败和退出重进后的重试。确认另一个仍有效的直接设备目标定时及其他组成员不被清除。

拿到实际失败分支后，只修对应边界：

- 若当前匹配 ACK 被旧 observation 状态挡住，核对 owner 与读回边界；未知状态按已有权威读回机制解决，不能凭单条 ACK 把所有 slot/Model 标记为空。
- 若本次成功收尾使自己的 task 失效，修正收尾与取消的区分；保留替换、STOP、真实配置变更和迟到响应的保护。
- 若是持久化失败，保留 pendingRemoval 和已确认的设备进度，修复对应保存条件，重试仅补未完成的保存/Model。
- 如果离线完整路径不能复现，先交付诊断构建，由用户从点击 Save 前开始捕获一次完整 L1/L2 日志；不能凭猜测继续调整业务判断。

### 12.3 范围与验收

- 只涉及 App 及本地 SDK；不改固件、服务器、协议参数、超时或重试次数。SDK 若有新增差异，记录正式依赖发布待办。
- 当前计划不改变数据库、export JSON 的字段、类型、默认值或语义，不需要结构迁移；若后续发现必须变更结构，应另行展示前后说明并确认。
- 实施后先运行新增复现和相关既有回归，再构建一次 SunSmart Debug generic iOS；共享逻辑无品牌差异时按代表 target 验证。
- 最短人工验收：保留组目标定时及另一条直接设备目标定时，添加 L1/L2 成功后首次同时移除；每台设备应显示一次任务列表，Remove schedule 成功后继续真实组退订，直接目标定时保留；返回重进核对成员状态。另测部分失败后重试，只补未完成任务。
- 本轮分析没有修改生产/测试代码，没有构建、安装或操作真机。当前仍未闭合的事项是**这份现场日志对应的具体 App 失败出口**，而不是等待确认固件缺陷。

## 13. 本次授权实施记录

沿用当前 App worktree 和映射正确的 SDK `one-dev`，未新建分支，未提交，也未修改其他任务的既有差异。遵循项目要求，由本任务单独写入 SDK 并自查，不启动子代理。第 12 节作为实施依据；当前已完成诊断与离线边界验证，现场根因判定仍待带新诊断标记的复测日志。

### 13.1 已落地的变化

| 位置 | 变化 |
| --- | --- |
| App `SyncExecutionSession.swift` | Group 同步记录 run、group、node、操作类别、build、`diagnostics=remove-schedule-v2`；批次统计在应用结果前固定 `acceptedBeforeApply`，避免绑定释放后再读动态 getter 导致 ACK 统计变成 0 |
| App `TimedSchedulerBindings.swift` | 结果接受、保存、协调与释放绑定的失败出口带原因；同时输出每个 Scheduler Model 的地址和有效 slot/未知状态、当前 slot/绑定状态、Proxy 是否忙。正常批次记录接受与完成两个阶段 |
| App `TimedSchedulerTaskCoordinator.swift` | 记录 admission 失效、替换、配置保存、网络生命周期及节点失效导致的 task 取消；只关联运行期 task 标识、地址和 slot |
| SDK `MeshSchedulerObservation.swift`、`Node+Messages.swift` | 拒绝观察时记录 source、slot、owner 和 `cancelledOwner` / `responseMismatch` / `requiresFullRead` / `registerOwner`，原有接受条件不变 |
| SDK `MeshProxyMessageCommand.swift` | 记录 STOP 和未完成批次触发的 Scheduler task 取消 |

所有新增输出均受 `#if DEBUG` 保护，不输出密钥、完整身份指纹或配置 JSON；没有添加数据库字段、export JSON 字段、新的持久状态、自动重试机制或协议命令。本轮没有放宽取消、未知缓存或保存失败的成功条件，也没有调整超时/重试次数。

新增 SDK 方法参数为模块内部 observation 的可选 source，不新增 App 依赖的 SDK 公共 API。正式工程仍使用远端 release 声明；诊断构建使用前述本地 SDK。此前传输修复及本轮 SDK 差异均未发布，正式交付前仍需按既定流程发布 SDK revision。

### 13.2 回归实现与发现

在原 `check_timed_slot_persistence.py` 中增加 `--scheduler-lifecycle` 模式，复用原有 SQLite 夹具，不新增 Xcode 测试工程。新的 `TimedSchedulerLifecycleTests.swift` 与 source helper 接入：

- 生产 Schedule entry 构造、Scheduler 字节编解码及响应匹配；清除请求断言为现场 `40060080791EF03F0000`。
- 生产 SDK `MeshSchedulerObservation` 和 Node 的 SchedulerStatus/ActionStatus 缓存处理。
- 生产 Proxy `reportSuccess`、`finishMessages`、`reset`，断言先 reset 再交给 App 释放绑定。
- 生产 App 结果应用、任务协调器、绑定保存，以及真实 SQLite 断开重连/重载。

夹具使用独立的模拟设备寄存器，区分“设备执行了但 ACK 丢失”和“发送前取消”；读回数据来自该寄存器，不从 App 缓存反推。模拟 BLE 接收通过主队列异步交付，等待交付条件后再完成批次。**BLE/Network 实际发送、完整 Proxy admission/receive 分支、UIKit 和 SDK Node 属性数据库存储仍由受控边界提供；这不是完整 App 或真机验收。** SDK 既有 transport/Proxy 回归另行提供这些组件的局部证据。

覆盖正常两设备添加后移除、旧 ACK 造成未知观察、两个 Model 部分回执、Node 属性保存失败、Schedule SQLite 保存失败、取消、配置替换，以及移除途中重新添加。失败场景重开 SQLite 后保留待处理绑定，再按模拟设备权威读回重试；已清空不重发，未执行清除的 Model 才补发。另保留一条直接设备目标 Off 定时，确认 slot/配置/设备寄存器未被删除。Auto/On 的 Model Owner 会随自动组归属变化，属于已有迁移规则，不能把“所有状态位完全不变”当成这类定时的验收条件。

发现：普通路径可以成功；注入已取消的旧 owner 响应后，SDK 将 Model 置为未知，随后当前匹配清除 ACK 仍因 `requiresFullRead` 不成为完整观察，App 明确返回 `unknownModels`。完整读回后可以完成清理且不重发已执行的 clear。这证明了一个可区分的失败路径，**没有证明原现场日志包含该旧响应，也没有把这条保护机制当成已确认的业务缺陷直接修改。**

### 13.3 验证与现场交接

| 检查 | 结果与边界 |
| --- | --- |
| App `check_timed_slot_persistence.py --scheduler-lifecycle` | 8 个连续行为场景全部通过；另验证运行期日志能区分观察拒绝、未知 Model、持久化失败和取消 |
| App `check_timed_slot_persistence.py` | 通过；原有编解码、SQLite、失败/恢复及绑定套件保留 |
| App `check_timed_task_replacement.py` | 通过；任务替换、结果快照、多 Model、取消及保存失败 |
| App `check_sync_execution_session.py` | 通过；Session 接入、取消和迟到回调；仍有夹具既有不可达 default 警告 |
| App `check_timed_delete_result.py` | 通过；独立 ScheduleServer 清理入口 |
| SDK `check_scheduler_readback.py` | 40 passed，0 failed；原有观察与读回接受规则保留 |
| SDK `check_scheduler_task_replacement.py` | 通过；取消所有权、传输注册、Proxy admission/回调和 STOP 边界 |
| 静态与工程检查 | App/SDK `git diff --check`、`plutil -lint SunSmart.xcodeproj/project.pbxproj` 通过 |
| SunSmart Debug generic iOS | 构建退出码 0；本地 SDK 映射及代表 scheme 已核对 |

构建使用第 9 节相同命令、workspace、scheme 及独立 DerivedData；只有此前已存在的 `ScheduleAddViewController.swift:347` weak capture 警告。未使用 Simulator、未安装或操作真机。生产逻辑没有品牌分支或资源归属变化，因此未机械重复构建其他品牌。

实施自查确认：业务 guard 的先后顺序、取消条件、缓存接受条件及失败返回语义维持原有行为；新 helper 仅记录既有结果。测试建设过程中纠正了夹具对直接目标 Auto/On 的初始 Model 路由假设，并改用生产 entry 构造和 Off 的实际路由断言；没有为使测试通过修改业务规则。当前无需额外架构或数据结构变更。

下一次现场复测请使用当前 `SunSmartLocal.xcworkspace` 的 Debug 构建，从添加 L1/L2 前开始保留完整 Xcode 日志，覆盖添加成功、点击移除 Save、首次失败/成功，以及需要时的一次重试。确认包含 `[GroupSync] diagnostics=remove-schedule-v2`，保留 `[ScheduleResult]`、`[ScheduleObservation]`、`[ScheduleTask]` 和原 Mesh 日志，不只截失败附近。优先检查第一条 `stage=failed reason=...`，再向前关联同地址/slot/task 的观察拒绝或取消原因。

当前交付边界：诊断代码及可复用离线回归已提供；**原现场问题尚不能宣称修复完成**。若新日志证实 unknownModels，后续在既有权威读回机制内处理；若指向保存或任务归属，则修正对应边界，不扩大到固件或服务器。

## 14. 最新添加后移除日志：成功，但添加计划重建 4 次

### 14.1 本轮输入与结果

- 日志：`/Users/maginawin/Desktop/add and then delete members.txt`，3051 个逻辑行，最后一行没有换行符。
- 当前 App：`feat/device-scene-261028`，HEAD `b8334969fb1a1e01d4de5154a4e349c2f870e3ca`；SDK `one-dev`，HEAD `165d916d958864c1998426dc821f17e028e899aa`。开始分析时两者工作区均干净，前轮差异已进入提交。本轮没有修改生产代码、测试或 SDK。
- 本地 SDK 映射仍指向上述 `one-dev`。日志含 `diagnostics=remove-schedule-v2`，但没有完整 revision，不能只凭日志证明安装包与当前 HEAD 完全一致。

| 检查 | 日志证据 | 结论 |
| --- | --- | --- |
| 添加 L1/L2 的定时 | 771–772、1538–1539 行：`accepted` 后 `completed`，`binding=synced` | 两台均完成设置 |
| 添加整体结果 | 1595 行：`state=syncSuccess failedModels=0` | 本次添加最终成功 |
| 移除 L1 的定时 | 1849–1850 行：接受清除结果，随后 `slot=none binding=none`，49F9/49FB 均空 | 清除与绑定释放成功 |
| 移除 L2 的定时 | 2480–2481 行：接受清除结果，随后 `slot=none binding=none`，49FC/49FD 均空 | 清除与绑定释放成功 |
| 真实组退订 | L1 2152–2392 行共 21 条；L2 2772–2991 行共 17 条 `C015` Model Subscription Delete | 已继续执行实际退组 |
| 移除整体结果 | 3005 行：`state=syncSuccess failedModels=0` | 本次移除成功，没有计划失效重建 |
| 云端提交 | 1628–1635、3039 行含 HTTP/业务成功 | 本次上传成功，仍不等于已逐项读回服务端配置 |

没有本轮 `ScheduleResult stage=failed`、Scheduler observation 拒收或 transport 失败；82 个 `batchResult` 均为 `applied=true`。4 个被中止重建的批次没有进入最终 batchResult，不能据此把整个添加过程说成无异常。Mesh 有少量最终成功的重发，既不是定时失败证据，也不对应下面四次计划失效。

### 14.2 四次闪烁对应的计划失效

同一次添加出现 5 个实际执行 run；移除只有 1 个。四次重建都紧随成功回执，且日志均为 `sceneContextsCurrent=true`：

| 设备 | 成功回执 | `planInvalidated` 行 | 重建后继续位置 |
| --- | --- | --- | --- |
| L1 / 49F9 | 40 行：Primary Element、Generic OnOff Server 首次加入 `C015` 成功 | 41 | 57 行继续其他 Model 订阅 |
| L1 / 49F9 | 172–175 行：亮度范围写入成功，min=655、max=65535 | 176 | 191 行继续 SceneRecall |
| L2 / 49FC | 866 行：Primary Element、Generic OnOff Server 首次加入 `C015` 成功 | 867 | 883 行继续其他 Model 订阅 |
| L2 / 49FC | 980 行：相同亮度范围写入成功 | 981 | 996 行继续 SceneRecall |

后续任务利用已成功更新的设备缓存继续，因此最终仍成功；这四次中止与重建没有必要。它们会重复进行准备和列表安装，并扰动执行生命周期，不应仅通过隐藏动画掩盖。

### 14.3 根因：把当前同步进度纳入了全局配置不变条件

源码链：

1. `SpaceSyncTaskScope.capture()` 捕获整个 Space 的身份、权限相关上下文及配置，其中调用 `SceneCommandBuilder.captureConfigurations()`。
2. Scene 捕获使用 `SceneTargetResolver.resolve()`；比较项除期望 Scene/Group 配置外，还包含**根据当前设备订阅推导的目标设备**、解析后的目标参数，以及**设备当前亮度/CCT 范围**。
3. SDK 收到成功订阅状态后，更新 Model 的订阅缓存；`Node.group` 随之解析为 `C015`，该设备开始进入组目标 Scene 的 targets。收到 `LightLightnessRangeStatus` 后，SDK 正常更新 `node.lightnessRange`，Scene capabilities 随之改变。这两类改变正是本次同步要求的结果。
4. 全局 Scene 比较因此返回 false；`SyncExecutionSession.validatePlan()` 停止当前批次并触发 `onPlanInvalidated`。日志中的 `sceneContextsCurrent=true` 仅代表当前消息携带的 Scene 上下文，没有表示全局 `configurationIsCurrent()` 为 true；这四处普通配置任务也没有 Scene 删除任务校验失败的证据。
5. 普通 Group 路径由 `handlePlanInvalidation()` 自动执行 `rebuildTaskPlan(resume: true)`，随后安装新列表并再次启动。

因此，本次已确认的问题在 **App 的计划有效性边界**；SDK 按成功回执更新缓存是正确行为，这份日志没有指向设备拒绝执行或新的固件问题。

移除没有同类重建也可解释：在计划捕获之前，两台设备已进入 `.exitFailure`；Scene 解析先将它们从 write targets 排除，随后真实退订不再改变该比较中的写入目标。不能把“移除不闪”推广为所有移除情形都不会触发该机制。

关联源码：

- `SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift`：`SpaceSyncTaskScope.capture()`。
- `SunSmart/Main/Scene/Model/SceneCommandBuilder.swift`：全局 `captureConfigurations()`、单条消息 `SceneMessageContext.matches()`。
- `SunSmart/Main/Scene/Model/SceneTargetResolver.swift`：`taskComparison`、组成员展开、退出成员过滤、capabilities。
- `SunSmart/Main/Space/Model/SyncExecutionSession.swift`：`validatePlan()`。
- SDK `ConfigurationClientHandler.swift`、`Node+Propertys.swift`、`Node+Messages.swift`：成功回执对订阅、组归属和亮度范围的更新。

### 14.4 快速弹出关闭的最可能是加载 HUD

`SyncDevicesViewController.rebuildTaskPlan()` 的现有顺序为：

1. 先 `showCustomHUD(nil)`。
2. Scene 恢复确认检查前 `hideInView`。
3. 无需用户确认时立即收到 `.ready`；异步准备开始又 `showCustomHUD(nil)`。
4. `installTaskPlan()` 再隐藏 HUD，替换 sections 并 `tableView.reloadData()`。

`XWHUDManager` 对 nil 文案创建约 88×88 的加载视图，显示和隐藏带动画；show 内还会先 hide 旧 HUD。四次额外重建放大了这些开关及列表替换，和“闪一下、快速出现关闭一个弹窗”的反馈吻合。

所有 6 次准备均记录 `SceneSync stage=restoreReady`，对应无恢复确认候选的分支；日志没有实际 Scene 恢复确认框被展示的证据。因此 HUD 是有源码依据的首要解释，**尚不能凭文本日志确认用户看到的每一次闪烁都是它，也没有录屏/UI 运行验证**。正常切换设备时的展开、收起也会刷新列表，但不能用它解释四次明确的自动重建。

### 14.5 最小修复建议（待实施）

1. **修正同步计划的配置比较。** 在 Space/Group 同步范围内区分用户期望配置与当前执行进度：仍校验 Scene revision、配置内容、Group/Profile、设备身份、网络/账号/权限；本轮已确定的加入/退出意图及范围设置的预期成功结果不应让整个计划失效。通过同步上下文表达这些有限的预期变化，不能每收到 ACK 就无条件重设基线，也不能全局删除 targets/capabilities 校验，让真实外部变更穿透。未预期的成员/能力变化、替换身份、配置编辑仍须停止并重新准备。
2. **复用现有 Scene 发送与回执保护。** `Scene.getSyncMessageHandles()` 在实际执行时重新创建 `SceneMessageContext` 并使用其最新 target 构造参数；虽任务行携带 `executeData`，下发参数实际来自新 context。因此可保留“前序订阅/范围成功后再按当前状态生成 Scene 命令”的机制。实施时同时核对任务生成是否包含本轮待加入节点的必要 Scene，不能依赖反复重建补出遗漏任务。发送与 ACK 继续用严格的 context.matches 校验；STOP、页面退出及迟到回调不能恢复旧任务。
3. **整理本页面准备阶段的 HUD 生命周期。** 同一次有效 preparation 只管理一次加载显示；快速完成可延迟显示，避免无确认需求时的 show→hide→show。慢准备、失败、取消、返回及旧 preparation 的迟到完成都要正确结束本次 HUD；真正需要用户恢复确认时仍显示确认框。复用现有 `preparationID`/取消机制，不引入持久状态或全局 HUD 改造。先消除无效重建，不扩大到普通列表刷新重构。

预计修改限于 App 共享同步/Scene 校验和同步页准备逻辑；没有数据库或 export JSON 的结构、字段语义变更，不需要迁移。无需调整协议命令、ACK、超时或重试次数，也不需要固件/服务器配套。共享路径影响各品牌，当前证据没有品牌特有分支；实施后以 SunSmart 代表构建并分别交付自动化与实际 UI 验收。

### 14.6 已有证据、回归要求与验收边界

本轮使用 `/tmp/probe_group_sync_scope.py` 复用现有 `check_scene_configuration.py` 的 sync 夹具，编译生产 `SceneCommandBuilder.captureConfigurations()` 和 `SceneTargetResolver`，替换临时入口进行行为复现，退出码 0：

- 逐台模拟 L1/L2 的订阅缓存变化和范围缓存变化，四次均使刚捕获且原本有效的全局 Scene 校验返回 false。
- 普通 Scene 已完成缓存更新不使该校验失效。
- 两台先设置退出意图，再清除组归属，校验保持有效，与日志移除阶段一致。
- 修改真正的组 Scene 期望亮度，校验仍失效，确认保护需求确实存在。

夹具的节点缓存变化直接赋值，**没有经过真实 SDK ACK 解码、BLE、UIKit 或完整 SyncExecutionSession**；SDK 如何写入这些属性另由生产源码及日志对应。本轮证明的是比较器的触发原因，没有宣称已自动复现屏幕动画。没有修改仓库测试、构建 App、安装或操作真机。

实施回归应覆盖：

- 两节点连续加入，真实成功回执更新订阅/范围后保持同一个有效 run，必要 Scene/Schedule/Switch 任务完整执行，没有无意义 `planInvalidated`；重试只补未完成项。
- 同步中真正修改 Scene/Group/Profile、切换网络或替换设备身份，仍中止旧计划；意外能力变化不能被当成预期 ACK 接受。
- 保留添加后移除、部分失败重试、STOP/退出重进、迟到回调及已有 Scheduler 生命周期用例。
- 快/慢准备、恢复确认、失败与取消的 HUD 生命周期；旧准备完成不能关闭新准备的 HUD 或自动续跑。

最短人工验收：同样配置下添加 L1/L2，观察整个 Sync device(s) 页面不再在订阅、范围成功后反复闪烁；随后首次同时移除，两台 Remove schedule 成功后完成真实退组。正常设备展开可继续刷新，真正耗时准备仍能显示加载反馈。保留完整日志，预期添加只有一次正常启动、没有上述四次计划失效；若仍看到弹窗，再用对应时间点的短录屏区分 HUD 与其他提示。

## 15. 计划进度与加载框修复实施记录

### 15.1 范围与实现

沿用 App `feat/device-scene-261028`、HEAD `b8334969`，仅叠加本次未提交差异；本地 SDK 保持 `165d916` 且工作区干净。原分析文档是开始实施时唯一未提交文件。本轮由同一任务写入并自查，按用户规则未启动子代理、未 commit/push、未安装或操作真机。

| 位置 | 最终行为 |
| --- | --- |
| `SceneCommandBuilder.swift` | 新增仅限运行期的 `SceneSyncProgress`，捕获当前节点身份、网络、实际/待加入组、退出意图及 Scene 相关能力；仅登记已提交的普通组订阅/退订与 `LightLightnessRangeSet` 的准确目标值。观察可从初始值走到目标值，成功观察后不再接受旧值回退 |
| `SpaceSyncCleanupCoordinator.swift` | 全局 Scene 比较接收上述进度上下文；已登记节点的派生 targets/capabilities 由准确观察校验保护，Scene revision、期望配置、成员、Group 参数及原 Space/Profile/权限边界保持严格比较。复用 `NodeSyncTopologyCapture.isMembershipGroup`，不把虚拟/特殊组订阅当成普通成员迁移 |
| `SyncExecutionEnvironment.swift`、`SyncDevicesViewController.swift` | 在当前有效计划实际提交命令、SDK 有机会处理回执之前登记预期进度；没有收到某类提交命令的变化仍使计划失效。其他 Scene 保存/预览调用继续使用默认严格快照，单条 Scene 消息的发送与 ACK 校验不放宽 |
| `Node+SyncData.swift` | 初始组计划使用已有 `restoreData.addGroupAddress` 识别待加入成员，并从组的期望 Scene 数据生成任务；实际发送仍等待订阅依赖成功，并重新生成当前 target。没有待加入意图、属于其他组、正在退出、缺 OnOff 能力或 Scene 正在删除时不生成这类写入 |
| `SyncDevicesViewController.swift` | 无恢复确认需要时不再 show→hide→show；准备超过 150 ms 才显示一次加载 HUD，完成/失败/STOP/离开时只收尾自己显示的 HUD。旧 preparation 的延迟显示和完成回调均受 `preparationID` 与页面状态约束，不能干扰新准备 |

原有单一全量快照不能区分“外部编辑”与“本轮命令的正常结果”，因此增加上述短生命周期观察上下文；没有新增数据库或 export JSON 结构、字段语义、迁移或恢复机制。加入意图继续复用既有持久字段。维护边界是显式的命令白名单：本轮只覆盖普通组订阅/退订和亮度范围；未登记的能力、身份或意图变化继续失效，不自动信任所有回执或重置全局配置基线。

修复没有改变协议参数、ACK/UNACK、超时或重试次数，没有增加补发命令，也没有整体重构列表刷新。正常设备展开收起仍保留。共用 App 逻辑影响各品牌，没有品牌专有条件、资源、本地化、SDK API 或依赖变更，因此选 SunSmart 代表编译。

### 15.2 行为回归与自查

先添加并运行用例，在原代码上分别得到“本轮成功订阅使计划失效”和“快速准备闪现加载 HUD”的失败，再实施修复。实施中另用行为用例检查初始 Scene 任务的能力/删除边界，以及尚未执行节点的待加入意图变化；发现问题后修正并重新验证。

新的 Scene 连续行为用例执行生产的 Environment 提交方法、命令到节点的登记桥接、全局 Scene 捕获/比较、Resolver、差异生成与 Scene 命令工厂。通过主队列异步交付两台设备的四次结果，断言同一个计划校验持续有效；初始待加入节点已有 Scene 任务，订阅之前不能下发，之后可以 Store，成功后不再生成重复 Scene 写入。还覆盖没有命令的成员变化、不同范围值、旧范围回退、CCT 能力变化、设备替换、真正 Scene 参数修改，以及退出意图完成。

加载框用例执行生产准备控制器方法，控制延迟队列和异步 cleanup 的完成时点，覆盖快速不显示、慢准备显示一次、恢复确认期间无加载遮挡、失败/STOP/离开收尾，以及旧准备完成不能隐藏新 HUD 或安装旧计划。既有安装与 Session 用例继续执行生产方法；更新测试夹具对抽出 HUD 方法和共享 Node 属性的声明，没有用夹具替代本次比较/准备逻辑。

自查重点为：初始任务完整性、组订阅前置依赖、期望进度与外部编辑的区分、权限和身份、回执后保存/重试、页面退出及迟到回调。没有遗留本范围内需要另行修复的已知阻断项。

### 15.3 最终验证

| 检查 | 结果 |
| --- | --- |
| `check_scene_configuration.py --suite all` | 10 个 Scene 套件全部通过，含新增连续进度用例、SQLite、保存/回执、导入导出及集成边界 |
| `check_sync_preparation.py` | 通过；权限/Gateway 原路径及新增 HUD 快慢、替换、取消生命周期 |
| `check_sync_run_lifecycle.py` | 通过；生产计划安装、关闭页面、STOP 与重复完成 |
| `check_sync_execution_session.py` | 通过；生产 Session/Coordinator 的身份、失败重试、STOP、迟到回调、Scene/Scheduler 结果处理 |
| `check_sync_task_builders.py` | 通过；组订阅前置依赖、退组、Scene、Switch、Profile/TimeSet、重试及结果作用域 |
| `check_group_sync_task_plan.py` | 通过；首次加入、部分订阅后重试、去重、退出优先及成员数量 |
| `check_scene_deletion_flow.py` | 通过；组成员退出、持久化/重进、身份替换、多 Element、迟到/失败回执 |
| `check_scene_sync_read_performance.py` | 53/500 节点读取夹具通过；只证明该读取边界，不代表整个 App 的性能验收 |
| `check_timed_slot_persistence.py --scheduler-lifecycle` | 8 个连续场景全部通过：正常添加后移除、旧 ACK、部分回执、两类保存失败、取消、替换及重新加入 |
| 静态/工程 | `git diff --check`、`plutil -lint SunSmart.xcodeproj/project.pbxproj` 通过；正式依赖声明和本地 SDK 映射未改动 |
| SunSmart Debug generic iOS | 使用第 9 节命令、`SunSmartLocal.xcworkspace` 和稳定独立 DerivedData，最终退出码 0；未使用 Simulator |

构建入口初次在沙盒内被错误报告为非 workspace，核对文件与映射后在沙盒外完成编译。首轮实际编译发现共享 helper 所属类型引用写错，修正为 `NodeSyncTopologyCapture` 后构建通过。最终仍有其他未修改文件的 weak capture、actor 隔离等编译警告；离线 Session/任务夹具保留既有不可达 default 警告。

验证边界：新增 Scene 用例的 SDK 消息对象与节点缓存更新由受控边界提供，没有执行真实 BLE 或完整 SDK 订阅缓存处理；真实异步提交桥接和 App 比较/命令逻辑已执行，完整 Session 另由既有套件覆盖，二者不能合称一次完整真机 Group 会话。Scheduler 生命周期用例另覆盖实际协议编解码、SDK observation、Proxy reset、App 结果和 SQLite。HUD 用例记录显示/隐藏调用，没有实际渲染 UIKit 动画。服务端往返与实际 UI/设备验收未执行。

人工验收沿用第 14.6 节：在同样定时配置下首次添加 L1/L2，再首次同时移除；检查 Scene/Schedule/Switch 任务完整、Remove schedule 成功后退组、页面没有反复加载闪现。日志重点确认添加没有原来的四次 `planInvalidated`，也没有漏同步后只显示成功。另执行一次 STOP/退出后重进重试，确认仅继续未完成工作。

## 16. Session 复盘：问题出现时机与预防

### 16.1 总结与证据边界

本 session 从「日程 1」待同步，连续追踪到成员移除失败、成员添加时 Schedule/Switch 失败、重复任务列表，以及最终成功情况下的页面闪烁。已确认并处理的主要是五类 App/SDK 边界问题，没有证据支持把这些失败统一归因于设备固件。

「日程 1」的待同步提示本身是正确的：负责关灯的 Owner Model 缓存未知，不能把另一个 Model 已清空当作整台设备已同步。首次日志缺少最早占用请求和异常回执，因此 SDK 悬挂缺陷已复现并修复，但它是否就是该次现场首次故障的全部原因，仍不能仅凭原日志断言。

还有一轮“再次同时移除 L1/L2 失败”的日志没有足够证据确定新的失败出口；那轮完成的是分阶段诊断与 8 个跨 App/SDK/SQLite 生命周期回归。注入旧 owner 回执可复现未知观察，但未证明现场确实发生过该输入，因而没有放宽未知状态保护。后续新日志中的两台添加与移除均成功，是该次现场结果，不是对所有历史不确定路径的追溯证明。

### 16.2 五类问题与触发条件

| 问题 | 何时触发 | 本次修复 |
| --- | --- | --- |
| Scheduler 请求未收尾，后续同地址 busy | 错 slot/旧值等回执被 Access 层当作完成并停掉超时，上层严格校验却拒收；外层取消又可能没有持有真实请求句柄 | 统一 Access/Network/Proxy 的回执规则，读取也绑定可取消任务，补齐迟到回执和发送前所有权检查及诊断 |
| Remove schedule 成功被重新判失败 | 正确清除 ACK 后 App 释放 binding，随后再次用动态发送条件读取 isSuccessful；“已经完成、无需再发”被误读成“先前回执失败” | 应用结果前固定接受结论，统一应用结果，再做协调/释放；保留部分失败、保存失败、取消和重试条件 |
| 添加时 Schedule/Switch 连续失败 | TimeSet 后额外发送 TimeZoneSet，占住主地址；合法 TimeZoneStatus 因 delegate 未注册成为 UnknownMessage，且附加 ACK 等待与下一任务竞争 | 注册/校验 TimeZoneStatus，普通附加时区也复用已有单次 GATT 提交，不占普通 ACK 等待；补 STOP/替换所有权 |
| 同一 L1 出现两个任务列表 | 部分订阅成功后，L1 同时位于 inNodes 和 group.nodes；重建/重试分别遍历两者，各建一份任务 | 顶层组计划按稳定地址规范化输入，新加入与保留成员互斥，退出优先；保留合法的不同操作阶段 |
| 成功同步时页面闪烁、加载框快速开关 | 组归属和亮度范围成功更新改变全局 Scene 快照，被误判外部编辑；两台添加共 4 次自动重建，每次又反复开关 HUD | 按实际提交命令识别预期进度；首次计划包含已有待加入意图的 Scene；HUD 延迟 150 ms，绑定 preparation 生命周期 |

重试容易成功有共同解释：设备/缓存已经完成了部分操作，而 App 首轮结果或计划状态没有正确跟进；第二轮从新的缓存生成更少任务，绕过首次的错误边界。重试成功不证明首次设备没执行，也不能作为无限增加重试次数的理由。

### 16.3 代码层面的时间线

以下由保留的旧提交对象及 git log/blame 核对，日期均为 UTC+08:00。它们是代码引入或已存在时间，**不代表安装包发布时间、用户首次遇到故障的时间，也没有做所有历史版本的真机二分**。本 session 集中发现/验证问题的日期是 2026-11-07；部分日志开始时已经失败，无法给出现场第一次出错的精确时刻。

| 时间 | 可确认的历史事实 | 与本次问题的关系 |
| --- | --- | --- |
| 至少 2024-01-08，App `a5800f36` | 组流程已先遍历 inNodes、再遍历 group.nodes，未排除交集 | 重复计划是历史潜在缺陷；此次部分订阅、重建与重试使交集实际出现。后续 2026-09-08 `c604dfa4` 抽出构建器后仍保留此逻辑 |
| 2026-10-30，App `c1a7bd2a` | 加入 Scene captureConfigurations，并接入 SpaceSyncTaskScope；比较包含运行时解析 targets/capabilities | 成功订阅/范围更新使全局计划失效的相关逻辑在此引入 |
| 2026-11-03，App `eb189247` | 增加带 preparation 生命周期的 rebuildTaskPlan、HUD 和普通计划失效后的自动重建 | 将上述误失效表现为自动重新准备、列表安装及反复加载显示 |
| 2026-11-04，SDK `4b4c0f5` | isSuccessful 增加 transmissionIsValid；Proxy 加入严格 Scheduler 地址/slot/参数检查 | 成功结果和当前发送有效性开始共用判断，形成后续 binding 释放与结果重读的组合风险 |
| 2026-11-05，App `b6f56743`、SDK `c8ef744` | App 增加捕获 binding/intent 的 Scheduler task；SDK Network 层增加严格 Scheduler 请求匹配、可取消发送所有权 | 与已有清理释放流程组合后，需区分发送条件和已接受结果；Network/Access 两层完成规则不一致也成为具体可复现的悬挂链。11-06 `e560574b` 又修改 binding 处理，不能只按最后修改日期归因 |
| 2026-11-05，App `4796d2d0` | TimeSet 成功后自动附加 TimeZoneSet，普通路径使用需要 ACK 的发送 | 触发此前已有的 Time Client 注册遗漏，并与下一个任务争用地址；本次日志直接指向占用 opcode 823C |

Time Client 未注册 TimeZoneStatus 是更早存在的覆盖缺口；本次核对旧版注册表可确认其缺失，不将注册表最后一次修改时间误称为该缺陷首次发生时间。

复盘时 App HEAD 已经 rebase/fixup 为 `4d29b4e9`：AuthorDate 为 09:40，CommitDate 为 14:41，提交说明已包含本 session 的 Group/Timed/任务列表修复。因此不能把合并后显示的 09:40 当作这些修复全部完成或缺陷全部引入的时间。SDK `165d916` 的提交时间为 13:57，包含前三轮传输/TimeZone/诊断修复。本轮仅文档复盘，不再次运行没有变化的构建或测试。

### 16.4 为什么分多轮才发现

这些问题分布在同一操作链的不同边界：前面的发送占用解除后，后面的 ACK 应用、绑定释放、成员任务合并和计划校验才有机会完整执行。存在逐层暴露的客观原因，但前几轮验证也有明确缺口：

- 单独测试 Scheduler，没有把实际 Time Client delegate 注册和 TimeZone 附加发送接进同一地址占用链。
- 只测下层设备任务生成，没有执行顶层 in/current/out 成员集合合并。
- 把发送/ACK、应用状态、持久化和完成判断分开验证，遗漏“成功保存会使旧发送条件失效”的次序。
- 验证了“外部编辑要失效”，没有反向验证“自己的成功进度必须持续有效”。
- UI 测试没有覆盖连续准备、快速完成、旧回调与新 HUD 的所有权。

这也是本次助手排查与验证需要改进的地方：不能把局部测试通过外推为整条增删成员路径闭合；证据不足时应先补可区分的诊断，而不是沿用上一轮根因。

### 16.5 后续预防规则与可执行回归

1. **明确三个状态边界。** 期望配置、设备观察、任务执行进度分别比较；“还能不能发”“这次回执是否有效”“结果是否保存成功”分别判定。成功事件不能因其合法后果被追溯改成失败。
2. **发送事务有唯一收尾责任。** 只有上层也能解码并接受的响应，才能结束底层等待；超时、取消、拒收和迟到回执都要有完整路径。任何附加发送必须沿用所属 operation 的排队/提交与取消规则。
3. **计划始终支持合法中间状态。** 在订阅前、首个订阅后、部分成功、失败重试、退出重进五个时点检查成员集合；同一身份同阶段只生成一份任务，已成功目标不重发，待加入的必要 Scene 不遗漏。
4. **维护跨边界回归，而不只增加断言数量。** App 侧保留 check_sync_preparation、check_sync_execution_session、check_sync_task_builders、check_group_sync_task_plan、Scene sync 套件及 Scheduler lifecycle；SDK 侧保留 scheduler_transaction_lifecycle 和 TimeZone 实际 delegate/Access/Network 收尾测试。修改其中一个边界时同时运行它的上下游用例，夹具必须明确哪些 SDK/持久化/异步行为被替代。
5. **固定一条真机发布验收链。** 保留组目标定时、直接设备目标定时与 Switch，首次添加两设备→同时移除→一次中断重试→退出重进；核对任务、实际退订、定时读回与页面反馈。成功路径应没有无故 planInvalidated；失败路径只补未完成项。离线回归及 generic 构建分别报告，不代替该验收。
6. **日志记录边界与版本。** 继续使用 run/node/slot/owner/阶段/失败原因，并在复测包记录 App/SDK revision；不能只保留最后一句 failed。busy 要能看到占用请求，结果日志要区分 ACK 接受、缓存观察、持久化和任务完成。禁止输出密钥与完整敏感配置。

以上为复盘与后续规则建议，没有擅自修改 CI、AGENTS、用户记忆或发布流程。最后一轮页面修复仍待真机复测；正式 App 发布前仍需核对远端 SDK release 是否包含 `165d916` 的修复，本次仅确认本地 SDK 提交，未查询远端发布状态。
