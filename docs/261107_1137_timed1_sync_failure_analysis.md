# 空间 2「日程 1」待同步与历史失败分析

2026-11-07，UTC+08:00。已按用户“按建议修复”的授权完成 App 所用 SDK 修复、针对性回归和 SunSmart generic iOS 构建；未改数据库/export JSON 结构、固件或服务器，未提交或发布。真机验收与现场首次触发报文仍待确认。

第 1–8 节保留修复前的分析证据与边界；第 9 节记录最终实施及验证结果。

## 1. 结论与证据边界

1. **当前“需要同步”有数据依据。** 日程 1 要对组 1 的设备 `49F9` 执行每周三 18:00 关灯，设备槽位为 0。App 的逐 Model 缓存只有 `49FB` 已知为空，负责关灯的 `49F9` Scheduler 缓存缺失，具体差异是 `owner-model-unknown`。业务状态因此保留 `pendingApply`，不能显示已同步。
2. **现场日志只证明 `49FB` 的清理已收到正确回执，没有证明目标日程写入 `49F9`。** 两者是同一设备上的不同 Element。`ScheduleSend set node:49F9 ...` 是构造消息时的日志，不是实际发送成功日志。
3. **排查优先级应放在 App/SDK 发送状态，而不是先归因设备。** 日志后段向 `49F9` 查询色温连续 4 次失败，错误为 SDK 本地的 `AccessError.busy`；其含义是该地址存在未结束发送/回调，并不是设备返回“忙”。日程专用发送路径没有记录错误详情，因此“目标日程也被同一 busy 阻止”是强相关推断，尚非日志直接证明。
4. **当前 SDK 存在已离线复现的相关缺陷。** Access 层与 Network 层对 Scheduler 回执的匹配条件不一致：错误槽位/旧参数回执可以先停掉底层超时，再被上层拒收，留下地址占用。复现中，`49F9` 后续 4 次发送均在进入 Access 层之前失败，而 `49FB` 清理可以正常完成。
5. **不能把该复现直接等同于现场最早的故障。** 用户日志从点击“同步失败”提示开始，缺少之前占用 `49F9` 的请求和回执，也没有日程专用发送的具体 error。已证实代码缺陷，尚未证实现场的第一次触发报文。设备 Primary Element 是否还有独立异常，也不能由目前片段排除。

## 2. 输入与代码基线

| 输入 | SHA-256 前 16 位 | 用途 |
| --- | --- | --- |
| `/Users/maginawin/Downloads/Space_空间 2_20261107_112929_210+0800.json` | `bdee24363ab12753` | 共享配置、本地数据库原始快照、恢复状态 |
| `/Users/maginawin/Desktop/sync timed logs.txt` | `ba60c54b1adcc7fc` | 228 行现场日志；以下行号均指原文件 |
| `/Users/maginawin/Desktop/server response data.txt` | `91d45b9bdf34b9f8` | get spaceprops 返回值 |

- App：`feat/device-scene-261028`，HEAD `e767305e79aafd08e5f8c69722d8a26353b32865`；开始分析时工作树干净。
- SDK：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2809c540be3b965a6a847ee4586ac46faf2ca2b5`；只读检查，工作树干净。
- `SunSmartLocal.xcworkspace` 的 `.local-sdk/nordic-sig-mesh-sdk` 实际链接至上述 SDK。
- 日志/导出未提供运行包的 App/SDK commit 指纹。源码结论针对上述当前 checkout；不能保证现场二进制与其逐字相同。
- 本文只列业务字段和协议参数，不复制凭据、完整密钥或原始完整快照。

## 3. 当前为什么需要同步

App `spaces[0].schedules` 与服务器 `data.schedules` 深度比较完全一致；两端 `timedSchemaVersion` 均为 3，`updateTimestamp` 均为 `1794022143`，即 11:29:03。

| 字段 | 值 | 解释 |
| --- | --- | --- |
| `schedules[0].name / id` | `日程 1 / 0` | Space 内业务日程 ID |
| `enabled` | `true` | 启用 |
| `selectTarget / groupAddresses` | `0 / ["C015"]` | 目标为组 1 |
| `hour / minute / dayOfWeek` | `18 / 0 / 4` | 每周三 18:00；4 是星期位图 |
| `action / fadeTime` | `0 / 0` | 关灯，渐变 0 秒 |
| `nodeSlots[0].identity.unicastAddress` | `49F9` | Dongle- L1，PID `2502` |
| `nodeSlots[0].slot` | `0` | 此设备上的物理 Scheduler 槽位 |
| `nodeSlots[0].state` | `pendingApply` | 尚未确认完整应用 |
| `actionAddress.off / recall` | `49F9 / 49F9` | 普通 Scheduler 地址 |
| `actionAddress.auto_on` | `49FB` | 同设备 Light LC Scheduler 地址；本次关灯不用该地址作为 Owner |

本地真实观察应查看 `_debugInspection.spaces[0].rawLocal.mesh.nodePropertys`，筛选 `unicastAddress=18937`（十六进制 `49F9`）：

| 观察字段 | 当前内容 | 可得结论 |
| --- | --- | --- |
| `allSchedulerModelActions.json` | 只有 `{ "elementAddress": "49FB", "entrysData": "" }` | 49FB 已知为空 |
| 上述数组中的 `49F9` 容器 | 缺失 | 49F9 为未知，不能当成已知空，更不能当成已写入 |
| `schedulesData` | 空字节串 | 没有可用的合并日程缓存，不能替代逐 Model 证据 |

当前路径为日程详情的失败提示 → `SyncDevicesViewController(.schedule)` → `SyncSceneScheduleTaskBuilder.appendSchedule` → `Schedule.getNeedSyncDatas()`。列表/详情的待同步读取也使用 `Schedule.needsSync`。

`Schedule.schedulerSyncDifference` 会检查目标、物理 slot、Owner Model 内容和其他 Scheduler 残留；本例 Owner 缓存缺失，返回 `.ownerModelUnknown`。`reconcileBinding` 只有观察与目标完整一致时才保存 `.synced`。因此，**待同步提示与 pendingApply 相符，但不是仅凭 pendingApply 字符串判断 UI。**

源码位置：

- [Owner 路由规则](../SunSmart/Main/Timed/Model/Scheduler.swift)：12–48 行。
- [实际同步差异判断](../SunSmart/Common/Data/MeshNetwork+SunSmart.swift)：1652–1699 行。
- [绑定状态收敛](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift)：74–89 行。
- [列表/详情读取](../SunSmart/Common/Data/SpacePageSyncRead.swift)：27–35、51–77 行。

### 不应误读的 JSON 字段

v3 共享配置有意移除 `nodes[].schedules` 和 `nodes[].custProps.schedulerModelStates`，本地仍保留逐 Model 缓存。服务器返回 `nodes[].schedules=[]`，App 正式导出省略该字段，**不能据此认定服务器丢失了本次日程或设备已清空**。参见 [v3 载荷转换](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `withoutSharedSchedulerObservation`（约 398 行）及[当前 v3 契约](261105_1429_space_timed_json_demo/261105_1429_space_timed_json_contract.md)中后续追加的 v3 更新。

## 4. 现场日志实际发生了什么

| 原始行号 | 事实 | 解释 |
| --- | --- | --- |
| 1–15 | 点击 `syncFailedTipBtnAction`，进入同步页面 | 日志开始时已存在失败/待同步状态；不是首次故障全过程 |
| 16–46 | 查询 `49FB` 的 `SchedulerGet`，有一次重发，最终回复 `schedules: 0` | 49FB 已确认空，且该设备能通过 Mesh 回应 |
| 47–82 | 查询 `49FC`、`49FD`，均返回空 | 这两个 Element 属于另一设备 Dongle-L2，不是日程 1 的目标 |
| 83 | `batch success=1 failed=1` | 是按设备统计的缓存读取结果；结合拓扑，符合 L2 完整成功、L1 的 Primary 读取未完成，但日志没有直接打印失败设备地址 |
| 29–30、111–112 | 打印目标业务 payload `40FE7F20018000400000` | 构造消息日志，`weekDays:1` 是选了 1 个星期，不是周一；真实位图为 4 |
| 113–114 | 向 `49FB` 发送 `SchedulerActionSet(index:0, noAction)`，参数 `40060080791EF03F0000` | 清理非 Owner Scheduler，尚不是写入周三 18:00 关灯 |
| 123–129 | `49FB` 回复 `SchedulerActionStatus(index:0)`，参数同为 `40060080791EF03F0000` | 来源、index、完整参数均匹配；未见拒绝或参数不一致 |
| 130–172 | 导出并上传，HTTP=200、业务 code=200、success | 云端保存成功，不表示日程已写入设备 |
| 203–213 | 向十进制 18937（49F9）发 `LightCTLGet`，连续 4 次 `busy` | 这是本地 SDK 发送阶段失败；该段未进入对应的 Access PDU 发送 |
| 214–228 | 查询 `49FC` 正常响应 | 故障具有目标地址相关性，不是整个连接都不能发送 |

在提供的完整 228 行内，**没有**向 `49F9` 发送上述业务 payload 的 `Sending SchedulerActionSet` / `Sending Access PDU`，也没有从 `49F9` 返回该日程参数的成功回执。

App 构造顺序是“清理非 Owner Model，再写 Owner Model”，见 [Node+MessageHandles.swift](../SunSmart/Common/Data/Node+MessageHandles.swift) 488–545 行。此次 `49FB` 的清理符合该设计。

缓存读取失败还有一个影响：SDK `MeshScheduleServer.getSchedule` 在整设备读取不完整时清除该设备所有 Model 的权威缓存，保留未知以便重试。所以前面刚读到 49FB 为空，后面仍可能重新发送清理；不能单凭重复清理判断为固件不保存。之后正确的清理回执又保存了 49FB 空状态，与导出快照一致。

## 5. 已复现的 SDK 缺陷

### 两层回执规则不一致

| 层 | 当前条件 | 错误/迟到回执的后果 |
| --- | --- | --- |
| `AccessLayer.handle` | 地址、response opcode；附加参数检查目前只支持 Sunricher Vendor | 对 Scheduler，错误 index 或旧参数也可能匹配，移除可靠上下文并关闭重试/超时 |
| `NetworkManager.notifyAbout(newMessage:)` | SchedulerActionGet 检查 index；SchedulerActionSet 检查完整 parameters | 拒绝错误回执，保留等待中的 continuation、callback 和地址占用 |
| 后续 `NetworkManager.send` | 地址已被占用/仍有回调则返回 busy | 在调用 Access 层、真正发送新请求之前结束 |

关键代码（SDK 根目录为第 2 节的 one-dev）：

- `Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/Access Layer/AccessLayer.swift`：176–184、721–745 行。
- `Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`：257–276、285–290、678–690 行。

这里不应通过“放宽上层回执校验”修复；上层拒绝旧 slot/旧参数是必要保护。问题是下层提前认为请求结束，导致上下层生命周期分裂。

### 最小行为复现

临时诊断脚本：`/tmp/analyze_timed_261107_boundary.py`。未写入业务目录或 SDK。

使用当前生产代码的真实 Scheduler 编解码、异步发送注册/取消、Network 回执处理和 Access 匹配/上下文移除代码；定时器与无线提交端为可控替身。步骤：

1. `49F9` 发起 `SchedulerActionGet(index:0)`，注册地址占用及等待回执。
2. 注入同地址的 `SchedulerActionStatus(index:1)`，模拟迟到/错误槽位回执。
3. Access 层移除计时器；Network 层拒收，回调与地址占用仍在。
4. 使用现场业务参数，尝试向 `49F9` 写入 slot 0，共 4 次；全部返回 busy，未调用 Access 发送。
5. 向 `49FB` 发送现场清理参数并回送匹配回执；成功，49F9 占用仍保留。
6. 显式取消原发送任务后，49F9 占用与回调释放。

复现结果全部符合上述链条；同时用真实编解码确认业务参数为 `slot=0 / hour=18 / minute=0 / weekdayMask=4 / action=0`，清理 Set 与 Status 完整匹配。

**覆盖边界：** 该测试不是无线重放、真实 BLE 或完整 App UI 复现；步骤 2 是构造输入，原日志没有记录该输入。它证实当前代码可以形成相同症状，不足以证明现场一定发生过该回执。

### 相关取消与诊断缺口

- `MeshScheduleServer.getSchedule` 构造的读取 handle 没有 `schedulerTask`。普通发送分支调用 callback 包装接口时未保存返回的 `MessageHandle`；Proxy 外层超时仅尝试取消 `schedulerTransmission` / `handle`。因此，读取路径发生上述上下层分裂后，外层超时不一定能回收对应实际请求。这一点由源码检查确认，临时复现未执行完整 Proxy 读取/UI 调用链。
- `MeshMessageManager.sendSchedulerMessage` 对 busy 总共尝试 4 次，重试间隔 200 ms；失败分支没有记录 error。`MeshProxyMessageCommand.schedulerSendCompleted` 又把具体错误转成通用失败。日志里只有 `49F9` 的普通 `LightCTLGet` 打印 busy，不能假称看到了日程 Set 的 busy 日志。

## 6. 云端历史诊断与本次设备同步分开看

导出还保留一条历史记录：

- `lastSyncDiagnostic.recordedAt=1794021748`：11:22:28。
- `stage=cleanupPreparation`，`error=-2004`，对应 App 的 `configurationUnavailable`。
- 该记录的 `localTimestamp=1793961042`：前一天 18:30:42 的配置版本。

这是 App 配置清理/同步准备阶段的历史失败，不是设备的 Scheduler 错误码，也不能仅凭它定位到某个具体 guard。当前快照已有 `configurationInitialized=true`、`hasCompleteExportSnapshot=true`、`pendingUpload=false`、`recoveryPhase=active`、`issues=[]`，且本段后续上传成功，服务器与 App 的日程数据一致。不能把这条历史 -2004 当作 11:29 仍需设备同步的直接原因。

参见 [NetworkRequest.swift](../SunSmart/Common/Network/NetworkRequest.swift) 391–419 行和 [SpaceSyncCleanupCoordinator.swift](../SunSmart/Common/Data/SpaceSyncCleanupCoordinator.swift) 151–173 行。

## 7. 最小修复方向与补证据

本轮未实施。无需新增/删除数据库列或调整 export JSON 结构；无需服务器、网关或固件配套才能修复已确认的 SDK 状态问题。

1. **统一 Scheduler 回执匹配边界。** Access 层只有在上层也会接纳的回执到达时，才能停止对应可靠事务；保留来源、slot 和完整写入参数校验。错误/迟到回执不能终结当前请求的超时恢复。
2. **补齐读取任务的实际取消归属。** SchedulerGet/ActionGet 在超时、停止或被替换时，应取消自己的真实请求并释放占用；不能以“清除该地址全部请求”破坏新的任务。
3. **补最小 DEBUG 日志。** 记录目标地址、opcode、slot、尝试次数、具体 error，以及被拒收原因。遇到 busy，记录占用请求的 opcode/slot 和等待时长；不输出 Key 或原始完整报文。
4. **不应把 pendingApply 强制改成 synced，或把未知 Model 当空。** 这会隐藏未下发的关灯日程。

最短现场确认路径：

- 保留现有数据，在点击失败提示前开始记录，覆盖首次进入 Space、后台 Scheduler 读回、点击同步及最终失败。重点补齐占用 `49F9` 的第一条请求、对应回执/超时，以及日程 Set 的具体错误。
- 使用两个 Element 的逐 Model 读回确认最终状态：`49F9` 的 slot 0 是周三 18:00 关灯；`49FB` 的 slot 0 无有效残留。重进日程页后应不再提示同步。
- 若补日志后仍是 busy，定位 App/SDK 占用生命周期；只有确认请求实际发到 `49F9` 后仍超时或返回错误值，才能继续区分无线/设备 Primary Scheduler 实现问题。

补充边界：本段没有 TimeSet。当前日程失败提示进入的独立 `.schedule` 同步任务只构造 Scheduler 命令，而设备整批同步和 `ScheduleServer` 的启停路径另有校时安排；这值得同入口验收时核对，但不解释本次 Owner 日程未确认、地址 busy 的现象，不能据此断定设备时钟错误。

## 8. 已验证与未验证

- 三个输入文件均解析/核对完成；日程配置、schema、时间戳与本地逐 Model 缓存已交叉比对。
- 临时跨层行为复现已运行，得到第 5 节结果；包含真实业务参数解码和清理回执匹配。
- 现有 SDK `check_scheduler_readback.py`：38 passed，0 failed。该套件覆盖编解码、Network/Proxy 匹配和缓存，不覆盖本次补充的 Access 停表与 Network 拒收组合，不能用其通过排除本缺陷。
- 未修改 App/SDK 生产代码，未运行 App 构建、未操作真机、未修改服务器，未 commit/push。
- 未验证现场二进制版本、首次卡住的请求、真实设备 Primary 的最终槽位内容或周三实际执行效果。

## 9. 2026-11-07 修复结果

### 最终行为

| 改动 | 结果 |
| --- | --- |
| Access、Network、Proxy 共用 Scheduler 回执判断 | Get 只接受匹配类型/slot；Set 保留完整参数匹配；错误槽位、旧参数、损坏回执不会提前停掉可靠事务计时器 |
| Proxy 接纳 SchedulerGet/ActionGet 时赋予独立的现有 `MeshSchedulerTask` | 初始位图查询和动态追加详情查询都使用可取消的 async 发送；不再依赖普通 callback 分支丢失的取消句柄 |
| Scheduler 发送前校验当前 Proxy 批次/handle | 已在外层超时但尚未从发送队列取出的旧请求不能继续发出 |
| Register 观察保存本次读取的内存 owner | 已取消读回的迟到位图不能把缓存标为已知空；新的完整读回仍可恢复可信状态 |
| DEBUG 失败/拒收/busy 诊断 | 输出目标地址、opcode、slot、尝试次数、具体错误；busy 附带占用请求及等待时长，不输出 Key/完整报文 |

沿用现有任务所有权和定时器机制，没有新增持久状态或独立恢复机制。正常 Scheduler 命令的目标地址、slot、payload、ACK 类型保持原值；本地 busy 最多 4 次尝试、200 ms 重试间隔不变。未把未知 Model 当空，也未强制修改 `pendingApply`。

本次没有把第 7 节补充的独立入口校时问题并入修复；该项不影响此次已复现的回执/占用问题，仍应在完整日程执行验收时核对。

### 修改范围与依赖

- App：分支和 HEAD 沿用第 2 节，仅更新本分析文档，无生产 Swift 改动。
- SDK：`one-dev`，基线 `2809c540be3b965a6a847ee4586ac46faf2ca2b5` 加本次未提交修改。
- SDK 生产文件：`AccessLayer.swift`、`NetworkManager.swift`、`MeshMessageManager.swift`、`MeshProxyMessageCommand.swift`、`MeshSchedulerTask.swift`、`MeshSchedulerObservation.swift`。
- 回归：新增 `SchedulerTransactionLifecycleTests.swift` 与 `check_scheduler_transaction_lifecycle.py`；扩展已有 Scheduler/队列边界夹具。
- 共享 SDK 内部逻辑影响使用它的各品牌；没有新增公共 API、品牌条件、资源或依赖声明。本轮构建代表 scheme SunSmart，未机械重复各品牌构建。
- 本地 workspace 映射未变，正式 project 的远端 SDK `release` 声明未变。**发布 App 前，需要把这些 SDK 差异纳入正式依赖版本；当前本地构建通过不表示远端 release 已包含修复。**

### 验证结果

新增跨层用例在修复前实际失败于 `malformed status must not stop reliable timeout`；修复后通过。测试将真实 Scheduler 编解码、Access 回执匹配和上下文移除、实际可靠超时回调、Network 异步注册/释放连接在一起，覆盖原先单层用例遗漏的边界。

| 执行目录 | 检查 | 结果与范围 |
| --- | --- | --- |
| SDK | `python3 scripts/check_scheduler_transaction_lifecycle.py` | 通过；错误 slot、旧值、损坏报文、Set 收到短回执、来源地址、正确回执、busy 隔离、取消、真实超时回调及同地址重试成功；DEBUG 日志分支参与编译 |
| SDK | `python3 scripts/check_scheduler_readback.py` | 40 passed / 0 failed；包括取消后的迟到位图拒收与重新读回恢复 |
| SDK | `python3 scripts/check_scheduler_task_replacement.py` | 通过；接纳/替换、真实 Task 取消、STOP、外层超时、动态读回回调归属、过期排队消息、迟到完成与目的地址复用 |
| SDK | `python3 scripts/check_group_control_session.py` | 26 checks；既有 Group 队列、Scheduler Set/Get/ActionGet 的 bounded busy 重试及取消期间停止重试；DEBUG 日志分支参与编译 |
| App | `python3 scripts/check_timed_task_replacement.py` | 通过；多 Model 回执、绑定释放、失败重试、同槽替换和启停部分成功/回滚 |
| App | `python3 scripts/check_sync_execution_session.py` | 通过；当前/旧回执、停止/重试、动态读回与持久化应用的 Session 边界 |
| App / SDK | `git diff --check` | 通过 |
| App | SunSmart Debug generic iOS 构建 | `xcodebuild` 退出 0，使用本地 SDK；仍有既有弃用 API、未使用变量等警告 |

构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-cli \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

首次沙箱构建无法识别已存在的 workspace；核对目录、workspace 内容、SDK realpath 和 project 格式后，使用获准的沙箱外同一命令成功。未切换 SDK 来源、未 clean、未删除共享缓存、未使用 Simulator 或操作真机。

夹具执行生产编解码、异步 continuation、超时和取消逻辑；无线传输、时钟触发、UIKit 页面和部分 Node 环境由可控替身提供。其通过不等同于真实 BLE/设备运行，数据库/服务器结构没有变动，本轮未重跑无关迁移或服务器联调。

### 最短人工验收

1. 使用上述分支和本地 SDK 的新构建，保留空间 2 原数据，进入“日程 1”并重新同步。
2. 确认实际写入 `49F9` slot 0 的周三 18:00 关灯参数并收到匹配回执；`49FB` 同槽位无有效残留。退出并重进后不再提示需要同步。
3. 补一次同步中断/停止后重试，确认后续向 `49F9` 的命令不会持续 busy。若仍失败，采集 `[ScheduleTransport]` 的 `sendFailed`、`busy`、`rejectResponse`，并保留首次进入 Space 到失败的完整日志。

没有 commit/push；现场原始首次触发原因及设备到点执行效果仍未确认。
