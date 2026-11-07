# Scene 离线灯同步超时崩溃：原因与修复方案

## 结论与当前状态

修复前，SDK 的 `NetworkManager.notifyAbout(error:duringSendingMessage:...)` 对 ACK 请求做失败归属判断时，比较了发送前原始消息和发送时已分配 TID 的消息的 `parameters`。原始 `LightCTLSet.tid` 为 nil，读取 `parameters` 会在 `LightCTLSet.swift:39` 强制解包并崩溃。离线灯触发正常 ACK 超时，继而暴露此 SDK 缺陷。

已通过真实消息类型、生产 Network 请求注册/失败处理、生产 TID 分配逻辑和生产超时闭包的离线边界复现，分别确认 `LightCTLSet`、`LightLightnessSet`、`GenericOnOffSet` 均会崩溃。用户确认后，已修复 SDK 的共享失败归属入口，保留 App 现有参数成功后才 Store、单灯失败后继续下一灯的流程。

当前已完成 SDK nil TID 修复，以及用户随后授权的 App 离线 Scene 保存/逐设备同步调整；相关回归和 SunSmart generic iOS Debug 构建通过。普通 Scene 可保存未知 Register 的设备目标，离线项保留待同步，在线项继续；物理写入前仍需容量校验。本轮未修改依赖声明或锁文件，未执行提交/push，未操作真机。收尾核对时 SDK 已出现包含此前修复的提交 `8f62e8a`，工作区干净；App 改动仍未提交，正式 workspace 锁文件仍指向旧 SDK revision。真实 BLE/Proxy/UI 与 SDK 缓存数据库的整链运行、云端往返尚未验收。

## 核对的版本与入口

| 项目 | 当前核对结果 |
| --- | --- |
| App 工作树 | `/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/feat-device-scene-261028` |
| App 分支 / HEAD | `feat/device-scene-261028` / `602eab0555bbac9381bd79855449db794e1a2885` |
| App 初始状态 | 工作树干净 |
| 本地入口 | `SunSmartLocal.xcworkspace`，引用 `.local-sdk/nordic-sig-mesh-sdk` |
| SDK realpath | `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev` |
| SDK 分支 / HEAD | `one-dev` / `165d916d958864c1998426dc821f17e028e899aa`，工作树干净 |
| 正式依赖 | project 保留远端 `git@github.com:maginawin/nordic-sig-mesh-sdk.git` 的 `release`；正式 workspace 的 `Package.resolved` 当前同样为 `165d916d958864c1998426dc821f17e028e899aa` |
| 缺失现场证据 | 用户日志没有完整线程栈和现场 App/SDK 构建 revision，不能仅凭日志证明现场二进制与上述 HEAD 完全一致；当前源码复现与日志的报错位置、消息类型及超时顺序一致 |

## 触发链与直接证据

### 1. Group 目标正常展开为两盏灯

日志显示 Scene 5 规划了地址 16（`0x0010`）和 19（`0x0013`），`pending=2`。按用户描述及执行顺序，当前离线目标对应 `0x0010`。在线目标 `0x0013` 在前置 Scene Register 查询中已有成功回执。

`SyncSceneScheduleTaskBuilder.appendScene` 将 Scene 目标展开为设备任务。没有关联 Schedule 时，任务可直接挂在 `SyncDevicesModel.operationType`，因此日志里的 `taskRows=0`、`steps=0` 不代表没有同步任务；后续 `commandsBuilt count=2` 也证明任务已生成。

`Node+MessageHandles.swift` 的 `Scene.getSyncMessageHandles` 生成参数设置和 `SceneStore` 两条命令。`SceneCommandBuilder.parameterHandles` 对该灯生成带 ACK 的 `LightCTLSet`，亮度 65535、色温 6500 K、Delta UV 0、Immediate、delay 0，目的地址为灯的 CTL Model 所属 Element 的单播地址。

`SyncExecutionSession.swift` 的 `send` 将参数命令与 Store 分批发送。现场停在 `submitParameters count=1`；没有进入该灯的 Store 阶段。

### 2. 原始消息为空 TID，实际发送副本已有 TID

关键源码位置以本轮 HEAD 为准：

| 位置 | 行为 |
| --- | --- |
| SDK `LightCTLSet.swift:37–39`、初始化方法 | `tid` 为 `UInt8!`，创建请求时允许为空；`parameters` 拼装需要非空 TID |
| SDK `NetworkManager.swift:270–285` | 先把原始 `message` 存入 `acknowledgedRequests[destination]`，注册 `MeshCancellableSend` 与 completion，再调用 Access Layer |
| SDK `AccessLayer.swift:228–248` | 对局部 `TransactionMessage` 值副本补 TID；不会回写上层缓存的 Swift struct |
| SDK `AccessLayer.swift:252–270` | 使用补完 TID 的副本创建 PDU 及 reliable context |

日志明确印出了前后差异：队列中 `LightCTLSet(tid: nil, ...)`，实际发送时 `tid: Optional(69)`。参数字节中的 `45` 也对应十进制 TID 69。TID 已正常用于发送和重发，并非蓝牙传输把 TID 丢失。

### 3. ACK 超时后的共用失败比较触发崩溃

`AccessLayer.swift:832–846` 的超时闭包依次执行：记录 timeout；以 `notify: false` 取消该 reliable context；清理失效计时器；将超时错误、带 TID 的 request 和 requestContext 交给 `NetworkManager.notifyAbout(error:...)`。

因此日志中 `Cancelling messages with op code: 33374` 是正常超时清理的一步，33374 即 `0x825E`。真正的危险读取发生在其后：

`NetworkManager.swift:782–784` 比较 `current.opCode` 和 `request.opCode`，相同时继续比较 `current.parameters` 与 `request.parameters`。`current` 是最初缓存的原始消息，TID 仍为空；读取左侧参数时即触发 `LightCTLSet.swift:39` 的强制解包。

这段比较是在已核对 `requestContext` 身份之后继续执行的。即使回调明确属于当前请求，也会因多余的原始消息序列化而崩溃。`git blame` 将该段比较定位到 SDK 提交 `c8ef744d`（2026-11-05，`improve timed`），且当前 SDK HEAD 包含它。这是共用发送层对带 TID 命令的回归，影响不局限于 Group Scene。

### 4. App 原有失败与持久化流程

- `SyncExecutionSession.swift:365–368`：参数批次失败时标记本灯失败并 `advance`，不会提交 Store。
- `SyncExecutionSession+Result.swift:93–102`：失败仅更新本任务状态和失败次数，随后由任务选择逻辑继续未执行目标。
- `TimedSchedulerBindings.swift:35–45` 与 `SceneMessageContext.apply`：SceneStore 成功后才提交 Scene 同步结果；pending operation 在持久化成功路径清除，保存失败会恢复内存状态。
- 当前崩溃发生在 SDK 向 App 交付正常失败之前，因此 App 无机会执行“L1 失败、继续 L2”。现有源码支持该行为，但修复后的双灯、保存、重载与真实 Mesh 链路仍需验证。

## 其他日志的解释

- `SceneDevicesSelectionView.swift:361` 存在独立的空态布局警告：背景 UIScrollView 初始宽度为 0，Stack 宽度约束却要求等于它减 40。UIKit 打破约束后继续执行，并已进入后续同步。此警告不能解释 SDK 中的 TID 强制解包，留作独立 UI 问题，本次崩溃修复不扩展到该布局。
- `cannot add handler to 0 from 0 - dropping` 缺少足以定位来源的栈信息，不能作为本次根因。
- HTTP 200 / CloudSync Success 表示相关上传成功，不能代表灯具已保存 Scene。崩溃复现不依赖网络请求、云端或布局。

## 分析阶段验证与覆盖边界

| 验证 | 结果 | 覆盖边界 |
| --- | --- | --- |
| 临时生产边界复现：CTL / Lightness / OnOff | 三种命令均触发同类 nil 强制解包，独立子进程退出码均为 `-5` | 引入真实消息协议及 codec、Network async send / failure 方法、Access TID 分配逻辑、AcknowledgmentContext 和生产 timeout 闭包；计时器触发、无线传输和 Access cancel 使用可控边界；不包含完整 BLE/加密/Proxy/UI |
| SDK `python3 scripts/check_scheduler_transaction_lifecycle.py` | 通过 | Scheduler / TimeZone codec、Access 接受、Network ownership、timeout/cancel 与同地址重试；既有用例未覆盖 TID 消息 |
| App `python3 scripts/check_sync_execution_session.py` | 通过 | 生产 Session / Coordinator、参数与 Store 顺序、失败、STOP、迟到回调等；传输、消息和部分持久化为夹具，不能证明 SDK 的实际序列化安全或整条真机链路 |

临时复现保留在 `/tmp/scene-timeout-diagnosis-261107/reproduce.py`，生成的 `Diagnosis.swift` 与三份错误输出位于同目录。复现命令：`python3 /tmp/scene-timeout-diagnosis-261107/reproduce.py`。临时目录仅用于本轮诊断，确认实施后应把有效行为复现纳入 SDK 既有回归机制。

现有 Scene 命令测试中的 `LightCTLSet` 是只保存亮度/色温的替身，没有真实 `tid` 和 `parameters`；Session 测试直接注入传输结果。历史回归通过不能覆盖此次真实发送/超时边界。

## 建议实施方案

### A. SDK 共享失败入口修复

主要修改 `Sources/NordicSigMeshSDK/nRFMeshProvision/Layers/NetworkManager.swift`，复用已有 `MeshCancellableSend` 请求身份，不新增持久状态或独立任务系统。

1. 对携带 `requestContext` 的失败，以当前请求身份严格相同作为归属依据，保留必要的 opcode 一致性检查；停止为已确定归属的错误读取发送前事务消息的 `parameters`。
2. 对没有 `requestContext` 的低层失败保留明确的隔离规则。带 TID 的 ACK 请求无法依靠“地址 + opcode”证明失败属于当前发送；应避免访问空 TID 消息参数，忽略不能确定归属的失败，让该请求已有且带身份的 reliable timeout 收尾。非事务消息保留可安全执行的匹配，Scheduler 现有无归属失败保护保持有效。普通 UNACK 事务命令没有 reliable timeout，必须保留其原有 delivery failure 收尾。
3. 在现有互斥区中完成归属核对、移除请求/回调和释放目的地址；锁外交付 completion 与 delegate，确保每次请求只结束一次。保留停止、重试和替换后的旧上下文拒绝规则。

第二项的代价是：无法归属的底层错误可能等到既有 ACK 超时才对上层报告；不增加超时时长或重发次数。相比凭 opcode 结束请求，这能保留新请求免受旧失败影响的保护。明确取消仍沿用已有取消流程。

不建议将 TID 默认改为 0、使用 `tid ?? 0` 拼装参数，或在 App 固定填 TID。这会掩盖错误比较，并可能影响事务编号行为。也不建议通过过滤离线灯来代替失败收尾；离线灯应保留可重试任务。

### B. 补足有意义的回归

在 SDK 现有 Standalone / `scripts/check_*` 测试机制内扩展，必须经过实际消息序列化与 TID 分配边界，不能只读取源码文本或构造无 TID 属性的替身。

| 用例 | 验收结果 |
| --- | --- |
| CTL / Lightness / OnOff 默认 nil TID，补 TID 后 ACK 超时 | 正常回传 timeout；可靠计时器、response callback、请求占用全部释放；不崩溃 |
| 显式 TID、正常 ACK | 原有成功流程成立，未因失败规则调整破坏成功处理 |
| 同地址超时后重试 | 新请求可以发送，无残留 busy；旧上下文 timeout/error 不得结束新请求 |
| 同地址、同 opcode、相同 payload 的旧失败 | 必须依赖请求身份拒绝，不能仅凭字节相同接收 |
| 无归属事务失败、错误 opcode | 不序列化空 TID，不消耗新请求；当前请求仍能以正确 ACK 或其自身 timeout 完成 |
| STOP / cancel 后迟到 timeout、重复失败、下一批开始 | continuation 和上层完成最多一次，不污染下一灯或新一轮状态 |
| Scheduler / TimeZone 现有保护 | 错槽、旧值、短包、错误来源、取消/重试继续通过 |

App 层保留现有业务策略，补双设备行为用例：L1 参数失败 → 不提交 L1 Store → L2 参数及 Store 成功 → L1 pending 保留、L2 成功被持久化 → 重载后仅 L1 待同步。必须区分传输夹具与真实 codec/持久化覆盖；必要时连接现有 Scene 持久化回归，不能以单层 Session 通过宣称全链路通过。

### C. 集成、发布与运行验收

- 实施前重新核对 App/SDK 状态及 SDK 写入负责人，避免与共用 `one-dev` 的其他任务同时修改。
- 本地验证仍使用现有正确映射的 `SunSmartLocal.xcworkspace`。SDK 修复需记录新 revision 或未提交 diff；正式发布需把修复带入 SDK `release` 并更新锁定 revision。本地编译不能证明正式远端已包含修复，提交/push 仍需单独授权。
- 生产代码实施完成并跑完针对性回归后，以 SunSmart 代表 scheme 构建一次 Debug generic iOS，关闭代码签名，不使用 Simulator。本次为内部共享逻辑，预计不涉及公共 API、资源或品牌条件，五品牌均受益；若实施实际引入这类跨品牌风险，合入前增加对应品牌构建。
- 最短人工验收：保持 L1 离线、L2 在线，按原路径创建 Group Scene 并 Done；等待 L1 超时后应显示失败，L2 应继续并成功保存；退出重进，Scene 仍显示 L1 待同步；恢复 L1 后重试，应仅同步 L1；再测等待期间 STOP/退出、重新进入重试，旧回调不改变新任务。
- 记录 App/SDK revision，关注已有 `SceneSync` 的 `parameterResult`、下一设备 `taskSelected`、Store `batchResult` 和最终 `finished`。必要新增诊断只记录 opcode/目的地址/请求身份/失败原因，并放在 DEBUG 条件内，不打印参数密钥。

## 范围与兼容性

无数据库或 export JSON 结构变更，无迁移/回填，无协议消息格式或 TID 分配规则变更，无固件、服务器、后端配套需求。受影响的是共用 SDK 的带 ACK 事务消息失败路径，三种 Scene 参数命令已复现，其他事务命令的具体入口尚未逐一运行验证。

## 2026-11-07 实施结果

用户已授权“按建议实施修复”。App 和 SDK 分支/HEAD 与上表一致，本任务修改均尚未提交；SDK 仍通过原有 `.local-sdk` 映射使用。本轮未改生产数据库/export JSON，测试中的 SQLite 与注入失败触发器仅存在于临时测试数据库。

### 后续复测说明：保存前 Register 查询失败

用户随后报告 Done 后停留在 Syncing，提供的日志为向 `0x0013` 发送 `SceneRegisterGet`、重发、超时以及发送失败。用户进一步更正：Syncing 随后会提示失败，并非持续卡住。

当前源码中，`SceneSettingsViewController.startSend(saving:)` 在提交新 Scene 前通过 `SceneCapacity.nodesRequiringRead` 查找缺少 Register 观察的相关节点；查询未成功时关闭 HUD、解除 busy 并提示 `sync_failed`，不执行 commit，也不进入 Sync Device(s)。这一行为与更正后的现场描述一致。该日志既不能证明 `0x0013` 离线，也不能确定它未回复的具体原因；之前日志曾收到它的 `SceneRegisterStatus`，不能据此保证本轮仍可响应。

此次未进入 L1 的参数发送/超时阶段，不能作为原 nil TID 崩溃修复的真实设备验收。下一次复测需先确认本轮前置 Register 查询收到有效状态，然后继续检查 L1 参数超时失败、L2 后续同步及退出重进的结果。没有证据支持绕过容量检查或改变重试策略。

针对“持续卡住”临时增加的 App/SDK DEBUG 诊断已撤回，仅保留原 TID 修复及其回归。没有新增业务行为或数据库/export JSON 变更；本次更正不需重复构建，原实施阶段的验证边界保持不变。

### 实际改动

- SDK `NetworkManager.swift`：有请求身份的失败先核对当前 owner，再核对 opcode；不比较发送前的事务参数。无归属的 Scheduler / ACK 事务失败保持当前请求存活，由已存在的可靠超时收尾；普通 UNACK 的 delivery failure 路径保留。未调整 TID 分配、ACK/UNACK 选择、超时时间、重发次数或公共 API。
- SDK `TransactionMessageLifecycleTests.swift` 与既有生命周期脚本：使用真实 CTL/Lightness/OnOff codec、生产 TID 分配、生产 Access cancel/timeout 和 Network 请求方法，新增 18 组 nil/显式 TID × 成功/超时/取消用例及 3 组 UNACK delivery 用例；同时检查重复失败、错误 opcode、旧 owner、同地址同字节重试和占用释放。原 Scheduler/TimeZone 用例继续执行。
- App `SyncExecutionSessionTests.swift`：新增真实 Session/任务选择/重试逻辑下的 Group 双灯用例，确认 L1 参数失败不 Store、L2 继续成功、旧失败不影响当前任务、重试仅发送 L1。
- App `SceneSaveCoordinatorTests.swift`：连接生产 SceneStore 结果应用、真实 App SQLite 保存/重新连接和生产 `getNodeSyncSceneDatas`。确认部分成功后保留 L1 原 pending generation、重进仅 L1 待同步，以及 App 保存失败仍可恢复重试。
- App 测试支持：补齐该用例所需 Schedule 夹具接口和生产同步读取方法；Scene 测试编译器使用各自临时目录的 module cache，避免系统默认 clang 缓存写入权限造成测试中断。

### 最终验证

| 检查 | 最终结果 |
| --- | --- |
| 修复前新生命周期回归 | 捕获 nil 强制解包，子进程 SIGTRAP；证明用例可发现原错误 |
| SDK `python3 scripts/check_scheduler_transaction_lifecycle.py` | 通过；含三类 ACK 事务、UNACK delivery、Scheduler、TimeZone |
| App `python3 scripts/check_sync_execution_session.py` | 通过；含新双灯失败继续/仅失败项重试和原 STOP/迟到回调用例 |
| App `python3 scripts/check_scene_configuration.py --suite save` | 通过；含新双灯 SQLite 重新连接/持久化失败恢复，以及原保存/协调器回归 |
| SunSmart / Debug / generic iOS / 禁止签名 | 最终 SDK 条件收紧为 ACK 后再次增量构建，`BUILD SUCCEEDED`；解析的 SDK 为本地 `one-dev` |
| App 与 SDK `git diff --check` | 通过 |

最终构建命令：

```sh
xcodebuild -workspace SunSmartLocal.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath /Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-scene-timeout CODE_SIGNING_ALLOWED=NO build
```

本次没有品牌资源、编译条件或 SDK 公共 API 差异，选择 SunSmart 代表共用逻辑验证；未重复构建其他品牌或 Release。

### 验证边界与交接

SDK 回归的计时器触发、无线/Upper Transport 为可控边界；App Session 的传输为夹具；App 持久化用例真正重新连接 SQLite，但 Node 的 SDK 缓存保存/重载仍是夹具。三组验证分别覆盖关联边界，不等于已经跑通真实 BLE → SDK → Proxy → App → 两层数据库的整条链，也不证明真实灯具已存储 Scene。

最短人工复测仍是：L1 离线、L2 在线创建 Group Scene → 等待 L1 失败且 L2 成功 → 退出重进确认仅 L1 待同步 → 恢复 L1 后重试 → 再测中断/退出后重进。记录本分支及实际包含本次 SDK 未提交修复的构建；正式远端 `release` 当前没有本次未提交改动，后续发布需单独集成。

## 后续流程方案：离线设备不阻断普通 Scene 保存（已授权实施）

用户已补充：本次 Register 查询失败的设备确实离线，不会回复。因此最新事实为“已知离线导致前置查询失败”，不是持续加载或回调丢失。此前关于离线原因尚不明确的记录仅描述补充信息前的证据状态。

### 推荐行为

普通 Scene 的 Done 保存期望配置及待同步任务，随后进入 Sync Device(s)。缺少设备 Register 观察时，把设备物理容量确认留到该设备实际同步之前。离线设备保留成员关系和待同步任务，在线设备继续执行。App 保存成功不代表设备已保存，也不能据此清除 pending。

| 阶段/条件 | 推荐行为 |
| --- | --- |
| Done 本地校验 | 保留权限、Site/Space/设备身份、数据完整性、目标有效性、项目容量上限及已知明确超限检查；持久化失败仍停止并保留可重试编辑状态 |
| Done 时 Register 未知 | 不要求所有设备先回复；未知保持未知，不伪造空 Register 或已确认容量；允许普通 Scene 保存待同步配置 |
| 同步初轮已明确离线 | 该设备显示未完成/离线，本轮不下发参数和 Store，保留其 pending，继续下一台；不因跳过而标记整轮成功 |
| 可尝试通信、Register 未知 | 在同步页对当前设备查询；查询超时只使本设备任务失败，继续下一台；未知时不发送参数/Store |
| Register 已确认且容量允许 | 沿用参数 ACK 成功后才提交 SceneStore；接受有效 Store 结果并成功持久化后才完成任务 |
| 确认容量不足 | 保留本设备失败/待同步及明确原因，不 Store、不自动删除设备上已有 Scene，继续其他设备 |
| 所有设备离线 | 普通 Scene 配置仍保存，页面显示全部未完成，用户可以退出，列表保留未同步状态 |
| 恢复在线后 Retry | 仅处理未完成且目标未变的任务；允许对缓存仍显示离线的设备做一次正常的有界查询尝试，避免永久依赖旧在线标志；成功设备不重复下发 |
| 退出重进/重启/取消 | 从原 pending 重建同一设备同一阶段任务；保留已成功结果，旧轮次迟到回调不能完成新任务 |

初轮跳过离线只是避免无意义等待的优化，不能删除目标或改变 pending 的含义。手动 Retry 的查询继续使用既有超时及重发机制，不增加无限重试或后台自动同步。

### 现有基础与最小修改边界

- `SceneSettingsViewController.startSend(saving:)` 当前在 Done 前调用 `SceneCapacity.readUnknownState`，要求整批成功。建议仅对保存路径移除这一整批 Register 前置依赖，保留必要本地校验及现有 Preview 行为。
- `SceneConfigurationStore.commit` 和控制器都会调用 `TimedSchedulerBindings.prepareTopology`，其中又执行 `SceneCapacity.validateTopology`。不能只修改 UI；需为 Scene 保存明确区分“校验期望配置”和“必须有设备物理观察”，默认严格规则继续用于其他调用方。仅允许普通 Scene 保存延后未知 Register 判断，已知超限和其他错误继续阻断。
- `SyncExecutionSession.processNext` 已在 Scene 任务下发前查询未知 Register、调用 `validateStore`，查询或容量检查失败后 `finishOperation(false)` 并推进下一任务。复用这一执行入口补齐离线初轮/手动重试行为及失败原因展示，不新增第二套同步队列。
- `SceneConfigurationStore.commit` 已按设备身份生成 `ScenePendingOperation(action: .write)`，保留已有同目标 pending，且不为未变化的已同步目标重建任务；复用现有存储和重试机制。

### Timed 关联边界

上述方案针对普通 Scene 的 Register 查询。Scene 编辑若导致已有 Timed 新增设备目标，需要为该设备分配 Scheduler 槽位；`TimedSchedulerSlotPolicy` 在物理槽位未知时明确禁止新分配。此次建议保留这一保护，并明确提示需要哪些设备在线完成 Timed 容量确认，不能把 Scene 的延后容量检查泛化为 Scheduler 槽位也可猜测分配。已有有效槽位的参数编辑、保留目标和移除继续沿用原规则。

若产品进一步要求“新增 Timed 槽位也能完全离线保存”，需单独设计未分配目标的持久化和恢复过程；不包含在本次建议中。用户当前报告未提供相关 Timed 关联信息，不能承诺所有带 Timed 的编辑场景都能直接保存。

### 数据与验证

本建议不新增或修改数据库表、字段、export JSON Key、类型、默认值或字段语义，无迁移；`pendingOperations` 继续表示同一设备尚未完成的期望写入。UI 离线/失败原因复用现有状态及国际化机制，不新增持久状态。实现时若发现必须扩展持久结构，应先更新具体结构说明并另行确认。

需要新增/调整的行为回归包括：未知 Register 且一离线一在线，Done 能保存并进入同步页；离线/查询超时不 Store 且下一灯继续；已知超限与未知状态不混同；全部离线；参数成功但 Store/本地保存失败；恢复后 Retry 仅失败项；退出重进及 SQLite 重载后 pending 保留；缓存离线但实际可响应时可恢复；STOP/迟到回调；新增 Timed 槽位未知时仍受保护。实施完成后运行相关 Scene/Session/Timed 回归并构建 SunSmart generic iOS；真实双灯和重启恢复由用户验收。

用户已授权“按建议实施：离线设备保留待同步任务，在线设备继续同步”。具体实施与验证如下；原 TID 修复及其验证结果保持独立。

## 2026-11-07 离线 Scene 流程实施结果

### 实际行为与范围

- Done 不再等待整批 Scene Register 查询，保存层显式允许将未知 Register 的检查留到执行阶段。权限、身份、数据完整性、已知超限和本地目标数量限制继续生效。默认拓扑校验和 `validateStore` 仍要求设备观察；其他 Group/恢复等调用方不会因新参数默认值而放宽校验。
- 进入 Sync Device(s) 后，Scene 写任务遇到已知离线设备，初轮以现有失败/未完成状态收尾，不查询、不发送参数或 Store，保留其成员和 pending，继续其他设备。若设备缓存显示在线但 Register 查询超时，同样只失败当前任务。全部离线的普通 Scene 能保存并重建待同步任务，整轮不会误报成功。
- Retry 在任务显示模型中设置临时 `allowsOfflineSceneProbe` 标记。直接任务和分步骤任务均会强制进行一次 Register 查询，即使仍有旧 Register 缓存且在线标志未更新；查询成功后本轮可继续容量校验和参数/Store，查询失败则保持未完成。该标记不入库、不导出，与分步骤重试时会清零的失败计数独立。
- Session 记录本轮成功查询的任务，防止在线标志未刷新时重复查询；查询完成闭包最多推进一次，取消或旧轮次的回调继续受原生命周期保护。已成功且目标未变化的其他设备不会重发。
- 新增 Timed 槽位仍要求读取 Scheduler 状态，失败时复用现有国际化提示，列出需连接读取的设备。Preview 保持原有前置查询行为。
- 新增 DEBUG `SceneSync stage=taskDeferred reason=offline`，其余查询与 Store 阶段继续使用现有日志。没有数据库/export JSON 结构或语义变更，没有新增本地化资源、SDK 公共 API 或依赖声明。

本阶段生产改动均在 App，未写入 SDK。开始时 SDK 为 `one-dev` / `165d916d958864c1998426dc821f17e028e899aa` 加上一阶段的未提交 TID 修复；收尾时核对到 HEAD 已变为 `8f62e8aafeda0c5d9ac678f085c589da99e17e26`（`fix crash issues`），SDK 工作区干净。其相对旧 HEAD 的四文件变更对应此前 NetworkManager 修复和相关回归，没有本阶段新增 SDK 业务改动；本轮未执行该提交。App HEAD 仍为 `602eab0555bbac9381bd79855449db794e1a2885`，实现与测试尚未提交。正式 workspace 的 Package.resolved 仍锁定旧的 `165d916d...`，本轮构建使用本地 SDK 覆盖；远端发布状态未核对。

### 最终验证

| 检查 | 结果与覆盖 |
| --- | --- |
| `python3 Tests/Scene/SceneDoneSyncFlowTests.py` | 通过；生产 Done/导航方法不等待整批 Register，进入同步页；Preview 保持原行为；Timed 读取失败阻断保存并结束 busy |
| `zsh scripts/check_scene_capacity.sh` | 通过；仅未知观察可延后，已知超限和目标数量超限继续拒绝，默认严格校验保持 |
| `python3 scripts/check_scene_configuration.py --suite save` | 通过；真实 Scene 保存/SQLite 重新连接，未知 Register 的单灯离线/全部离线 pending，保存失败回滚、成功成员持久化、失败成员独立重试；未知 Timed 槽位仍拒绝；实际 App Register 读取函数覆盖强制刷新、超时、缺少观察、身份/Space 切换及断连 |
| `python3 scripts/check_sync_execution_session.py` | 通过；直接/分步骤任务、未知/已知 Register、一离线一在线/全部离线组合；离线初轮不发、在线继续、旧在线标志下查询超时继续下一灯、强制重试探测、重复/迟到回调、仅失败项重试，以及原 STOP/参数→Store/保存失败回归 |
| `python3 scripts/check_scene_topology.py` | 通过；默认共享拓扑校验保持严格，Group/退出恢复路径保持 |
| `python3 scripts/check_scene_configuration.py --suite targets` | 通过，28 个目标解析用例 |
| `python3 scripts/check_sync_task_builders.py` | 通过；任务构建、父子关系、依赖及共享 Retry/结果策略 |
| SunSmart / Debug / generic iOS / 禁止签名 | `BUILD SUCCEEDED`；使用上文同一构建命令及独立 DerivedData，解析到本地 `one-dev` SDK |
| `git diff --check` | 通过 |

新增验证连接了真实 App 保存、Register 读取完成函数和 Session 分支；无线发送、SDK Register 观察更新、部分消息对象及 SDK 缓存落盘仍由夹具控制。未运行真实 BLE、UIKit 操作、SDK 数据库重启或云端往返。共享逻辑无品牌差异路径、无资源/公共 API 改动，本轮以 SunSmart 代表构建，未重复其他品牌或 Release。

### 最短真机验收

1. 使用包含本任务 App 未提交改动及本地 SDK `8f62e8a` 修复源码的 `SunSmartLocal.xcworkspace` 构建，L1 离线、L2 在线；创建 Scene → 选择 Group 1 → Done。应进入 Sync Device(s)，L1 显示失败/未完成，L2 继续成功，不再因 L1 的前置 Register 查询失败而停在 Settings。
2. 退出重进或重启 App，确认 L1 仍待同步、L2 不重复生成未变化的任务。恢复 L1 后 Retry，应读取其 Register，再校验容量、下发参数并 Store；L2 不重发。
3. 两灯都离线时重复创建普通 Scene，应保存为未同步；等待查询或同步期间 STOP/退出，再重进重试，旧回调不改变新任务。涉及新增 Timed 槽位的编辑仍应提示连接相应设备，不能猜测占用。
