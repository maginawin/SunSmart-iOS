# 添加 L1 到 Group 后 Schedule、Switch 失败及重复任务列表

2026-11-07。**本次日志指向 App / 所用 SDK 的处理问题：补发的 TimeZoneSet 没有正常结束，持续占用 L1 的主地址，后续 Schedule、Switch 在本地发送入口被 busy 拒绝；重复 L1 列表则来自组任务构建器重复纳入同一个成员。** 设备已返回可正确解码的 TimeZoneStatus，没有证据表明这些失败由设备拒绝配置引起。

用户确认后已完成 App / SDK 修复，9 项相关回归和 SunSmart Debug generic iOS 构建通过。未提交、未发布 SDK、未操作真机。第 1–6 节保留修复前分析依据，第 7–8 节记录实施结果与剩余验收。

## 1. 输入、版本与边界

- 日志：`/Users/maginawin/Desktop/add L1 to group failed logs.txt`，1032 行。
- App：`feat/device-scene-261028`，HEAD `e767305e79aafd08e5f8c69722d8a26353b32865`，保留上一轮 Remove schedule 结果判定修复的未提交差异。
- 本地 SDK：`.local-sdk/nordic-sig-mesh-sdk` → `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`，保留上一轮 Scheduler 传输修复的未提交差异。
- 日志不含可独立核对的构建 revision。源码结论对应当前工作区，不能据此精确证明安装包 SHA。
- 相关既有记录：[日程 1 同步失败](261107_1137_timed1_sync_failure_analysis.md)、[移除成员时 Remove schedule 失败](261107_1206_group_member_remove_schedule_failure_analysis.md)。

## 2. Schedule 与 Switch 的共同失败链

L1 主地址 `49F9`，辅助 Element 为 `49FA`、LC Element 为 `49FB`；加入目标组为 `C015`。

| 日志行 | 事实 | 含义 |
| --- | --- | --- |
| 28–40 | 向主地址发送 C015 订阅添加，收到 Success | 组订阅已开始成功落地 |
| 560–579 | TimeSet 后收到正确的 TimeStatus，当前时区偏移 -300 分钟 | 前置校时成功 |
| 580–582 | 自动补发 TimeZoneSet，下一偏移 -240 分钟，TAI 切换时间 858322837 | 紧接校时的附加时区计划 |
| 588–589 | SchedulerActionSet 首次失败：`opcode=0060 pendingOpcode=823C pendingSeconds=0.139 error=busy` | Scheduler 没有取得主地址发送权；占用者是 TimeZoneSet |
| 594–595 | 收到 `0x823D / 2C3095F7283300`，随后显示 UnknownMessage | 时区回执到了，但没有按 TimeZoneStatus 交给上层 |
| 596–601 | Scheduler 后续 3 次仍 busy，pendingOpcode 一直是 823C | 回执到达后，TimeZoneSet 占用仍未释放 |
| 602–667、691–733 | C018、C019 的 Switch 相关订阅添加反复 busy | 同一主地址被占用，配置消息在本地拒发 |
| 780–835、986–1007 | 主地址 Vendor、CTL、OnOff 消息也 busy | 影响不局限于某条定时或某个开关 |
| 971–985 | 发往 LC Element 49FB 的属性配置仍收到成功回执 | 与按目的地址发生的占用一致，不像整条 BLE 链路掉线 |

`ScheduleSend set ...` 是任务准备日志，不能当成已经发到设备。此处 4 次 Scheduler 尝试都被 SDK 的 busy 拒绝。ConfigModelSubscriptionAdd 参数中的 Element 可以是 49FB / 49FA，但配置消息的实际目的地址仍是节点主地址 49F9，因此同样被阻断。

回执参数可由当前 SDK 的真实 `TimeZoneStatus.init(parameters:)` 解码为：当前 -300 分钟、下一偏移 -240 分钟、TAI 858322837，与发送计划一致。7 字节参数布局为 1 字节当前偏移 + 1 字节新偏移 + 5 字节切换时间，符合 [Bluetooth SIG Mesh Model 1.1 的 Time Zone Status 定义](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/MMDL_v1.1/out/en/index-en.html)。不能因 UnknownMessage 就判断设备回了异常格式。

### 2.1 SDK 缺少回执注册，且底层与上层收尾不一致

SDK `MeshLib/MessageDelegate/TimeClientDelegate.swift` 的 `messageTypes` 只有 TimeStatus、TimeRoleStatus、AttentionStatus，缺少 **TimeZoneStatus**。`MeshLib/Manager/MeshLibManager.swift` 的本地 Time Client 使用这个 delegate；当前其他本地 delegate 也没有补齐该 opcode。

实际接收链：

1. `nRFMeshProvision/Layers/Access Layer/AccessLayer.swift` 先按地址、响应 opcode 等条件查找等待请求。TimeZone 请求未进入 Scheduler 参数校验分支，当前会匹配成功。
2. 原始包匹配后，Access 层移除等待 context 并关闭重试 / 超时 timer。
3. 随后交给本地 Model delegate 解码。没有 TimeZoneStatus 注册，故生成 UnknownMessage。
4. `Layers/NetworkManager.swift` 只有收到匹配的 MeshResponse 时才清理 `responseCallbacks`、`acknowledgedRequests`、`acknowledgedSends`、`outgoingMessages`。UnknownMessage 不进入此分支。
5. 形成“上层仍等待，底层已无超时”的悬挂占用，之后同地址的 Scheduler、Config、Vendor 等发送持续 busy。

这与先前 Scheduler 异常回执问题属于同一类收尾一致性缺陷。此前过滤修复只覆盖 Scheduler 回执，没有覆盖 TimeZone 的解码注册与收尾，不能把上一轮通过的测试当成整个响应链已经完整验证。

### 2.2 App 的附加时区发送会与下一条任务竞争

[SiteTimeSetMessageFactory.swift](../SunSmart/Common/Data/SiteTimeSetMessageFactory.swift) 的 `makePlan` 在 TimeStatus 被接受后异步调用 `enqueueTransition`。`sendTransition` 在没有 completion 参数时直接 `MeshAPI.sendMessage(handle:)`，走普通需要等待 ACK 的单播发送。

这条补发不属于原有 Proxy 任务串行队列；TimeSet 主任务完成后，Scheduler 可以立即开始。因此即使补齐 TimeZoneStatus 解码，ACK 到达前仍可能 busy。日志第一次 busy 在时区回执之前，已经直接展示这个竞争；ACK 较慢或缺失时，短间隔 4 次重试仍可能耗尽。

现有代码已经提供可复用方案：同文件带 completion 的路径使用 SDK `submitTimeZoneSet`，通过现有 GATT 写入回执队列提交一次，不占用普通 ACK 发送等待表，不等待 TimeZoneStatus。它用于附加计划，GATT 写入完成仅代表本机提交，不证明设备接受，且不改变已成功 TimeSet 的结果。建议统一普通同步与该路径的行为，避免再新增一套队列或持久状态。

## 3. 为什么同一台 L1 出现两份任务列表

[SyncTaskPlanBuilder.swift](../SunSmart/Main/Space/Model/SyncTaskPlanBuilder.swift) 的 `.group` 分支分两次构建配置任务：

- 遍历 `inNodes`，添加本次加入成员的任务。
- 再遍历 `group.nodes` 中未退出的成员；**此处没有排除已经在 inNodes 中处理过的节点**。

虽然 `effectiveMemberCount` 计算排除了重叠，任务循环没有采用同样的互斥成员集合。一旦 L1 同时位于两个数组，就生成两个不同的 SyncDevicesModel，名称和地址相同，持有分别构建的任务。这会影响实际任务计划与进度统计，不能只在 UITableView 隐藏重复 Cell。

这种重叠是合法中间状态：SDK 的 `Node.group` 根据现有 Model subscriptions 推导，`Group.nodes` 根据 `node.group` 获取成员；首条普通组订阅成功后即可进入当前成员集合，不要求全部配置完成。日志第 40 行已收到 C015 订阅成功。与此同时，[SyncDevicesViewController.swift](../SunSmart/Main/Space/Controller/SyncDevicesViewController.swift) 在重建时保留 `inNodes`；首次构建前已经部分加入、失败重试或重建时都可能出现交集。`installTaskPlan` 是替换 sections，并非向旧列表追加。

日志没有记录每次 Group 计划的 in/current/out 地址集合及安装后列表，所以不能仅凭重复的 `restoreReady` 日志断言具体哪一次重建制造了重复。该日志也用于其他恢复检查。**确定事实是：当前生产构建分支遇到这个交集就会重复创建任务，离线已复现；现场准确重建时点仍缺专用日志。**

重复计划可能增加重复处理，但不是解释本次 busy 的必要条件；日志已经明确指出占用者为 823C，不能把它改称为“两条 Scheduler 相互抢占”。同一设备存在不同合法移除 / 配置阶段时也不应一概按名称删除列表项。

## 4. 本轮离线证据与覆盖限制

执行：`python3 /tmp/probe_l1_add_sync.py`，退出码 0。

探针一使用当前 SDK 的 TimeZone 编解码、TimeClientDelegate 注册表、实际 `ModelDelegate.decode` 方法、Access context 匹配 / timer 生命周期与 Network 异步发送 / 回执清理方法。物理传输、节点模型及无关消息类型由替身提供：

- 日志 7 字节参数可正确解码，但真实 delegate 返回 nil。
- 先处理原始回执再交付 UnknownMessage，Access timer 消失，Network 占用保留，下一条 Scheduler 返回 busy。
- 对照组交付正确 TimeZoneStatus，上层占用正常清除；回执到达前的竞争仍能复现。

探针二提取完整生产 `.group` case，替身只提供输入模型与下层设备任务构建边界：

- 当前成员为空、inNodes 含 L1：1 份配置任务容器。
- 当前成员与 inNodes 均含 L1：2 份独立容器，成员数量计算仍为 1。
- 当前成员含 L1、没有成员变更：1 份容器。

探针没有运行完整 App / UIKit、真实 BLE、实际数据库恢复或真实订阅 ACK 更新。生产 subscription → membership 的路径由源码和日志交叉核对，不能将其称为完整集成运行验收。

现有测试缺口：`check_sync_task_builders.py` 主要覆盖下层设备构建器，没有执行顶层 `.group` 合并；`check_site_clock_transmission.py` 将 `MeshAPI.sendMessage` 简化成加入数组，没有建立真实 Network 的同地址 ACK 占用；此前 Scheduler 生命周期测试不含 TimeZone delegate 注册。后续回归须补这几个实际边界。

## 5. 建议实施范围与顺序

### A. 修复 SDK 的 TimeZone 回执及收尾

1. 在实际本地 Time Client 注册 TimeZoneStatus，确认 0x823D 能成为 MeshResponse 并正常完成原始请求。
2. 核对 TimeZoneSet / TimeZoneGet 的 Access 接受条件：不能让上层无法接收的无效回执提前关闭底层超时。以本次 TimeZone 路径为边界补齐有效格式检查与收尾一致性，保留现有源地址、取消、Scheduler slot / payload 防护。
3. 覆盖合法回执、错误地址、截断参数、丢回执、取消、迟到回执、同地址后续发送；不能用“遇到 busy 就清空别人的请求”解决。

### B. 统一 App 的附加 TimeZoneSet 提交路径

1. 普通 `sendTransition` 也复用现有 `submitTimeZoneSet` / GATT 写回执机制，避免开启脱离同步队列的普通 ACK 等待。保留单播到实际 Time Setup Element、一次提交、附加计划不作为 TimeSet 成功前提的语义。
2. 保持 Site、网络、AppKey、节点与时区快照的发送前校验；核对本轮操作 STOP / 离页 / 替换后，尚未写出的附加计划不会继续发送。复用现有操作身份与取消机制，不增加数据库字段。
3. 沿共享工厂覆盖 Sync device(s)、ScheduleServer、Group / 设备配置、InformationClockRecovery，并核对 Gateway `sendPrepared`、Fast Add 独立 bearer 与 Space 广播不被误改。
4. 维持当前 ACK / 重试含义的清晰边界：普通附加单播将从“等待 ACK 的可靠发送”统一为“GATT 提交一次”；TimeSet、Scheduler、Switch 本身仍按原来的有效回执判定。未来时区计划的设备接收与生效需真机单独验收。

### C. 组任务在构建时按节点身份去重

1. 在同一网络中按稳定节点身份 / primary address 规范化 in / out / current 输入，形成互斥的退出、新增、保留集合；冲突输入按退出优先处理，配置集合排除退出成员。
2. 本次加入与已部分加入的同一 L1 只构建一次同阶段任务。保持 effectiveMemberCount、成员新增 Profile 语义、Remove → Configuration 依赖及辅助任务覆盖范围正确。
3. 重建仍根据最新已确认状态生成差异任务，不把未完成任务标成成功，不重发未变化且已成功的配置。不能用全局 UI 名称去重吞掉合法的移除 / 配置阶段。
4. 必要时增加 DEBUG 汇总：计划标识、成员输入数量 / 交集、输出设备身份，以及 TimeZone 提交 / 解码 / 完成状态；不打印凭据或完整数据。

这是 App 及其所用 SDK 范围，**不需要数据库或 export JSON 的结构、默认值或字段语义变更，不需要服务器 / 固件修改**。SDK 使用现有提交 API，无需新增公开接口；注册和收尾修复仍需以后发布到正式 SDK release，不能以本地覆盖编译代表远端依赖已经具备修复。

## 6. 实施后的必要验证与结束条件

| 范围 | 必须验证的行为 |
| --- | --- |
| SDK 接收链 | 实际本地 delegate + 0x823D 编解码 + Access / Network 收尾；有效 / 无效 / 缺失 / 取消 / 迟到回执后同地址可继续发送 |
| App 时间链 | TimeSet → 附加 TimeZoneSet → Scheduler / Switch；时区 ACK 延迟或缺失不能再占住后续任务；断线、STOP、身份 / 时区改变不得提交旧计划 |
| 顶层组计划 | 首次加入、部分订阅后重建、同页重试、退出重进、重复输入、同时增删、普通组同步；同身份同阶段只构建一次，已确认配置不重复生成 |
| 既有修复 | 复用并运行 Scheduler 生命周期、Timed 结果应用 / 持久化与 Sync Session 相关回归，确保 Remove schedule 的结果修复未回退 |
| 构建 | 一轮生产代码修改完成后，用映射正确的 SunSmartLocal.xcworkspace 构建 SunSmart Debug generic iOS，按工作树隔离 DerivedData；不自动真机安装 |
| 品牌 | 共享逻辑影响 SunSmart、Archipelago、SLG Sync Plus、SylSmart、Lumineux；如未改资源、target / API 且无品牌条件分支，先用代表 target 验证，不机械重复五套构建 |

最短人工验收：保留当前 Space 数据，给目标 Group 配置启用定时及 Switch → 首次添加 L1 → 同一配置阶段只显示一份 L1；TimeSet 成功后 Schedule 和 Switch 首轮完成，不再出现 `pendingOpcode=823C` 持续占用。接着验证部分失败后重试 / 退出重进只补未完成项、另一条仍有效的定时未被误清理，并检查附加时区计划实际写入及后续切换行为。真机结果与离线回归、generic iOS 构建分别记录。

## 7. 已实施变更

本轮继续使用既有隔离 App 工作树及其映射的 one-dev SDK；由单一执行者写入并自审，没有启用子代理。保留前两轮未提交改动，没有 commit / push、修改依赖声明、增加 SDK 公共 API 或调整数据库 / export JSON。

| 已完成项 | 实际改动 |
| --- | --- |
| SDK 回执 | `TimeClientDelegate` 注册 TimeZoneStatus；Access 层对 TimeZoneSet / Get 检查真实 7 字节解码结果，拒绝无法解码的回执消耗超时 |
| App 附加时区 | `SiteTimeSetMessageFactory.sendTransition` 的普通调用也使用现有 `submitTimeZoneSet`，一次 GATT 提交不占用 ACK 等待；保留实际 Time Setup Element、身份 / 时区校验和可选完成回调 |
| 取消与替换 | 工厂将原 TimeSet 的有效性条件延续到附加 GATT 写入；SyncExecutionSession 绑定当前轮次与配置有效性，正常完成允许已接受的附加提交，STOP / close / 新轮次拒绝旧提交；ScheduleServer 绑定实际 Timed operation，取消 / 替换后拒绝旧 TimeSet 及其附加提交 |
| 任务去重 | `.group` 分支按 primary address 规范化当前 / 新增 / 退出成员，同地址退出优先，新增与保留集合互斥；成员数量、Profile 语义、合法移除阶段及 Emergency 辅助任务沿用一致输入 |

共享工厂的 Group / 设备配置和 InformationClockRecovery 调用因此使用同一提交路径。Gateway 已有 completion 分支保留有界写入完成后回调的行为；Space 广播未改变；Fast Add 独立 bearer 的现有有效性保护保留并通过回归。

实施裁定：附加计划继续采用项目已有的“提交一次、不以 TimeZoneStatus 为成功前提”的语义，不新增队列 / 持久状态，也不改变 Scheduler / Switch 自身的 ACK 成功要求。现有 DEBUG `MeshSubmission` 日志可观察写入提交，本轮未增加高频日志。

测试夹具同步修正两处实际差异：时间链夹具补齐此前 SDK 新增读任务所有权所引用的类型；Gateway 缺失时区用例使用与 Site 实际保存值一致的 nil，未将空字符串擅自当作已经规范化的 nil。生产的精确身份校验与空值存储语义未修改。

## 8. 验证记录与交付边界

### 8.1 先失败再通过

- 真实 Time Client 对现场 0x823D 不能解码：新用例失败；注册后继续暴露“异常长度回执提前消费超时”；补齐 Access 检查后通过。
- 普通 TimeSet 的附加计划进入普通 ACK 发送队列：新用例失败；统一提交路径后通过真实 TimeZone 编码与 GATT receipt queue 的写入 / 取消边界。
- TimeSet 未随 Sync STOP / close 或 ScheduleServer operation 替换失效：新用例失败；关联既有轮次 / operation 后通过。
- L1 同时出现在新增和当前成员集合：顶层生产分支生成重复配置，新用例失败；规范化输入后通过。

### 8.2 自动化结果

以下命令均在本轮执行并返回 0；SDK 命令在 one-dev 执行，其余在当前 App 工作树执行。

| 命令 | 结果 / 覆盖 |
| --- | --- |
| `python3 scripts/check_group_sync_task_plan.py` | 通过：顶层 Group 分支首次加入、部分成员状态 / 重试输入、地址别名、增删冲突、Profile / 成员数、Emergency 及合法空任务 |
| `python3 scripts/check_site_clock_transmission.py` | 通过：实际工厂、时间编解码、GATT receipt queue；普通附加提交不进入 ACK 队列、重复回执、STOP / 移除 / AppKey / 断线保护；Gateway、Fast Add、冷缓存 |
| `python3 scripts/check_sync_execution_session.py` | 通过：真实 Session 的 TimeSet 轮次保护、正常完成、STOP / close、配置失效，以及既有 Scene / Timed 结果和重试生命周期 |
| `python3 scripts/check_timed_task_replacement.py` | 通过：真实 ScheduleServer TimeSet 的取消 / 替换保护，以及此前结果应用 / 清除绑定修复 |
| `python3 scripts/check_timed_delete_result.py` | 通过：删除预留失败、未确认清理、有效清理 |
| `python3 scripts/check_sync_task_builders.py` | 通过：真实下层设备构建器、Profile / TimeSet 依赖、组退出及 Switch 等既有策略 |
| `CLANG_MODULE_CACHE_PATH=/tmp/sunsmart-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/sunsmart-swift-module-cache python3 scripts/check_timed_slot_persistence.py` | 通过：实际 Schedule codec / SQLite 重载、保存失败、部分清理、身份 / 取消、历史数据与组退出 |
| SDK `python3 scripts/check_scheduler_transaction_lifecycle.py` | 通过：真实 TimeZone delegate / codec、Access / Network 收尾、错误地址 / 异常长度、超时 / 取消、迟到 TimeZoneStatus 不抢占后续 Scheduler；原 Scheduler 校验仍通过 |
| SDK `python3 scripts/check_scheduler_task_replacement.py` | 通过：可靠定时器、发送登记 / 取消、busy 隔离、Proxy 所有权、动态读取和回调收尾 |

测试边界：Group 顶层用例替换模型输入和下层设备差异构建，没有执行真实订阅回执更新、数据库加载或 UIKit；下层构建与 SQLite 由独立既有套件覆盖。时间链用例替换无线 / 连接及报文加密，使用真实 App 工厂、SDK codec 和 GATT 写回执队列；SDK 生命周期用例使用真实注册、匹配与收尾方法，物理传输仍由受控输入代替。以上均不等于实际 BLE 时序或设备接收验收。

### 8.3 构建与审查

已核对 `SunSmartLocal.xcworkspace`、SunSmart scheme 及本地 SDK realpath。构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-cli CODE_SIGNING_ALLOWED=NO build -quiet
```

退出码 0。构建保留 `ScheduleAddViewController.swift` 原有捕获所有权 warning；两个独立测试夹具存在原有 `default will never be executed` warning。未为消除无关 warning 扩大改动。

App / SDK 的 `git diff --check` 通过。按项目规则由实施者对最终差异做单独自审，重点核对上下层收尾一致性、共享工厂行为、取消 / 身份保护、去重后合法阶段及旧修复保留；未发现需要继续修改的问题，但没有独立审查者或真实设备运行证据。

### 8.4 剩余事项

1. 用户按第 6 节步骤验收首次添加 L1、Schedule / Switch、单份列表、部分失败重试，以及另一个有效定时不受影响；附加时区计划的接收与实际切换单独验收。
2. 本地 SDK 修复仍是 one-dev 未提交差异；未来发布需将注册和收尾改动纳入正式 SDK release。本轮不执行提交或发布。
3. 共享逻辑影响全部品牌，本轮完成代表 target SunSmart 构建；没有变更资源、target 条件或 SDK 公共 API，未机械重复其他品牌 / Release 构建。

