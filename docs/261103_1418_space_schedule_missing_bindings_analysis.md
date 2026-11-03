# Space 定时恢复失败：版本 2 混入缺少 nodeSlots 的记录

日期：2026-11-03。分支 `feat/device-scene-261028`，HEAD `ba8e608c`。初始分析时工作树干净；用户随后授权实施“普通定时缺失绑定按未分配处理”的小修复。业务修改未提交，原始 JSON、服务器及固件均未修改。

## 实施结果（2026-11-03 14:54 UTC+08）

已在 `TimedSchedulerPayloadPolicy.fillingMissingBindings` 增加版本 2 的默认值兼容：仅缺失或 null 的 nodeSlots 补成 []，已有绑定和其他业务字段不变；错误类型、非法身份/槽位、重复业务 id、非法时间/类型和未知 schema 继续校验。版本 1 的既有规则与 Profile 保护不变。

生产代码仅修改 [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift)，没有新增 UI、数据库列或 SDK API。共享代码适用于五个品牌，未新增品牌条件或资源变动，本轮以 SunSmart 作为代表构建。

| 验证 | 结果与范围 |
|---|---|
| `scripts/check_timed_device_slots.py` | 通过：混合缺失/null/空/已分配绑定、幂等、备份、legacy、非法输入与占用槽位保护 |
| `scripts/check_timed_slot_persistence.py` | 通过：生产 Codable/SQLite 保存、重新连接后重载、6 条混合记录、启用状态及绑定保留、按 Space 批量清理、现有失败/重试/晚到回执与 Profile 保护 |
| `scripts/check_space_recovery_receipts.py` | 通过：生产导入预处理、owner/editor、pending import 重试、基线、原始 GET 默认值回读；非空绑定丢失时拒绝确认，正确回读后可重试成功 |
| 用户两份原始 JSON 的定向诊断 | 修复后服务器原始 6 条与 null 变体均通过 Timed 校验、生产 Schedule 编解码往返；原有 42 个绑定保持 |
| SunSmart generic iOS Debug | BUILD SUCCEEDED，禁用签名，未安装或运行真机 |
| `git diff --check` | 通过 |

导入/回执测试中的 Mesh 对象与网络为夹具边界，SQLite 测试执行真实生产表操作；不将这些结果表述为真实云端、完整 App 运行或设备执行已通过。现有诊断仍确认 Schedule 不保留任意 Web 扩展字段，本次没有扩大为未知 Web 类型的无损兼容。

构建入口为 `SunSmartLocal.xcworkspace`、scheme `SunSmart`，使用 `-sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。DerivedData 为 `/Users/maginawin/Library/Developer/Xcode/DerivedData/SunSmart-feat-device-scene-261028-checks`。SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，revision `dbcf6f1`，工作树干净且本次未修改。没有正式依赖发布待办。

实施开始时已有的 project.pbxproj 签名团队与 Bundle ID 改动按原样保留，其他任务新增文档也未触碰。未执行 commit、push 或实际删除。

待人工验收：用新构建进入原 Space（或 Retry），确认不再因缺 nodeSlots 显示恢复失败，6 条定时可见；对普通定时完成编辑/启停、设备槽位读回及云端保存后重进。已有 Profile 记录仍按原保护只读；零设备 Space 的真实删除另在测试空间验收。若 Web 已下发未映射的物理定时，需核实旧槽是否仍执行，详见后文风险边界。

以下根因与方案评估记录描述修复前行为；当前实现与验证状态以上述实施结果为准。

## 修复前结论

服务器返回 `spaceData.timedSchemaVersion = 2`，但其中 id **3、4、5** 的定时没有 `nodeSlots`。修复前 App 要求版本 2 的每条定时都显式携带该数组；未分配槽位用 `[]` 表达，缺字段不等同于空数组。因此导入预检返回 `invalidTimedPayload`，进入 Space 的流程转到恢复页面，显示 “The schedule data could not be restored.”。

已用这两份现场数据执行当前生产 `TimedSchedulerPayloadPolicy` 和从生产源码提取的 Schedule Codable，复现上述失败。仅在内存给这 3 条记录补 `nodeSlots: []`，即可通过本次 Timed 校验和编解码往返，保留 6 条定时及原有 42 个绑定。此实验只证明字段缺失是本次校验失败的充分原因，不代表设备槽位分配或完整云端恢复已经验收。

## 数据证据

- App 诊断导出：`/Users/maginawin/Downloads/Space_日出日落_20261103_141204_872+0800.json`，比较 `spaces[0]`。
- 服务器 GET 响应：`/Users/maginawin/Desktop/server data.txt`，比较 `data`。
- 两者为同一 Space，均有 14 个 Nodes、1 个 Group、1 个 Scene，定时版本均为 2。

| 项目 | App 导出 | 服务器 GET |
|---|---|---|
| updateTimestamp（UTC+08） | 2026-11-03 13:58:18 | 2026-11-03 14:09:19 |
| 定时数量 | 3 | 6 |
| id 0、1、2 的 nodeSlots | 每条 14 个，共 42 个 | 与 App 完全相同 |
| id 0、1 的业务数据 | 本地记录 | 与 App 完全相同 |
| id 2 enabled | true | false |
| id 3、4、5 | 不存在 | 存在，但均缺 nodeSlots |

服务器中缺字段的记录：

| id | 名称 | 时间 | selectTarget | action | sceneAddress |
|---|---|---|---|---|---|
| 3 | 节点日程-日出日落开 | 20:05 | 2（Scene） | 2 | 0661 |
| 4 | 节点日程-日出日落 | 14:07 | 2（Scene） | 2 | 0661 |
| 5 | 节点日程-日出日落 | 14:08 | 2（Scene） | 2 | 0661 |

这 3 条均为 enabled=true、dayOfWeek=127、fadeTime=2、second=0，带 `sceneGroups=["C000"]` 和空 profiles。它们的目标 Scene `0661` 存在，`spaceData.sceneConfigurations` 为 groups 类型，Group `C000` 中也有对应 `sceneNumber=1633`（十六进制 0661）的关联；两份数据的 Groups、Scenes、spaceData 相同。

`sceneGroups` 不属于当前 Schedule Codable 字段；App 依据 `sceneAddress` 与 Group 的场景关联解析目标。本次它并非拒绝原因。`second=0`、缺省的 deviceAddresses/groupAddresses/删除数组也不是本次失败原因：不改变这些字段，仅补 nodeSlots 就能通过。

App 诊断状态显示上次上传回读已确认，时间戳为 1793685498；pendingImport=false、pendingUpload=false、configurationInitialized=true、recoveryPhase=active。本地仍保留 3 条定时，与“远端新配置尚未被接受”一致。

## 触发链路与兼容边界

1. [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 的 `loadSpaceReqeust` 获取 spaceprops，调用 `restoreConfiguration(authoritativeGET: true)`。
2. [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 的 `restoreConfiguration` 在身份、成员等检查后调用候选 Space 的 `update`。
3. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 的 `update(spaceJsonData:initialize:)` 在替换本地业务配置前执行 Timed 预检。第一步 `repairingStaleBindings` 已返回 nil，随后直接返回 `.rejected("invalidTimedPayload")`。
4. [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `repairingStaleBindings` 对 schema 2 遍历全部定时，要求 `schedule["nodeSlots"]` 可转换为字典数组。服务器数组第一项就是 id 5，立刻触发失败；id 4、3 分别也会失败。
5. 进入 Space 的调用方收到 rejected 后显示 [SpaceRecoveryViewController.swift](../SunSmart/Main/Space/Controller/SpaceRecoveryViewController.swift)，`message` 将该原因映射到 `space_recovery_timed_invalid`。

对应 DEBUG 分支预计输出 `[SpaceImport][Timed] stage=preflight field=schedules.nodeSlots`。这是根据代码得到的预期日志，本轮没有收到或采集实际 App 运行日志。

当前 `fillingMissingBindings` 只兼容以下组合：声明/缺省版本为 1、全部记录缺 nodeSlots、至少一个业务 id ≥ 16。它据此识别旧写入方整体丢失新字段，并补版本 2 与空绑定数组。本次已经是版本 2，且仅新增的 3 条缺字段，其他 3 条保留完整绑定，因而不会触发该兼容分支。

单独的 Schedule decoder 允许 id < 16 的旧记录没有绑定，所以服务器 6 条记录能够解码；真正拒绝的是 Space 层的版本一致性校验。不能只检查 JSON 能否解析或 Schedule 能否解码，就认定 Space 可以恢复。

Retry 重新 GET 后走同一链路，响应不变就会再次失败。直接把版本改成 1 也不成立：旧的 3 条仍带 nodeSlots，违反版本 1 的规则。

## 定向复现结果

使用临时 Swift 诊断程序，直接编译当前生产 Timed policy，并提取生产 ScheduleProfile、Schedule Codable 与星期转换方法；地址和枚举类型复用现有隔离测试的边界。只读取原始文件，变体均在内存构造，结束后删除临时程序。

| 输入 | binding repair / canonical | Schedule 解码 | Codable 再编码后的 canonical |
|---|---|---|---|
| App 原始数据 | 成功 / 成功 | 3 条 | 相等 |
| 服务器原始数据 | 失败 / 失败 | 6 条 | 无有效基准 |
| 分别仅保留服务器 id 3、4 或 5 | 各自失败 / 失败 | 各 1 条 | 无有效基准 |
| 服务器仅补缺失的 nodeSlots=[] | 成功 / 成功 | 6 条 | 相等 |
| 服务器仅保留 id 0、1、2 | 成功 / 成功 | 3 条 | 相等 |
| 服务器仅改 schema=1 | 成功 / 失败 | 6 条 | 无有效基准 |

补空数组的实验额外断言：全部 6 条记录保留，原有 42 个绑定不变，所有记录的其余字段不变，包括服务器将 id 2 停用的变更。

没有进行完整 App 构建、SQLite 导入事务、真实云端往返、BLE/网关操作或真机运行；本次是根因分析，不将隔离校验成功表述为完整恢复成功。

## 写入来源与后续处理边界

已证实服务器响应存在新旧格式混用，但无法凭两份快照判断由 Web、其他 App、网关写入还是服务端处理造成。当前 App 的 [ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 会输出 timedSchemaVersion，并在返回正常导出内容前执行相同的 repair/canonical 校验，不能据此将该混合内容认定为当前 App 正常出口产生。

若需定位产生方，由持有日志的团队只读核对本 Space 新增 id 3、4、5 的写请求与后续 GET：记录写入方/版本、schema、每条 id 是否携带 nodeSlots，以及该字段是写入时缺失还是存储/返回时丢失。无需提供凭据或完整密钥。

对接契约应明确：当 `timedSchemaVersion=2` 时，所有定时都带 nodeSlots；尚未分配设备槽位才使用空数组，已分配则保留正确的节点身份、slot、state、generation。不能用业务 id 猜测物理 slot，不能清空原有 42 个绑定，也不能为通过检查降级版本或删除 3 条新增定时。

如后续决定在 App 兼容此形态，应在共享 Timed 规范化边界做定向处理，并保持 GET 导入、pending import、持久化回读、导出和上传确认的一致语义；同时验证这些定时是否已被外部写入方下发到设备，避免将“云端丢失绑定”直接当成“物理槽位未分配”。本次已按下述最小方案实施 App 兼容，未修改后端或固件。

## 最新方案评估：缺失/null 自动补 nodeSlots=[]

### 可行性结论

**技术上可行，且明显小于“外部定时只读、原始 JSON 持久化”的方案。** 当前结构本来就支持空 nodeSlots，UI 新建普通定时也先使用空数组。针对现场这 3 条 Scene 定时，补齐可以通过当前 Timed 校验及 Codable 往返，无需新增外部定时模型、数据库列或专用提示。

但需明确产品语义：**[] 表示由 App 管理、尚未分配设备槽位的定时，不表示外部只读定时，也不证明设备上不存在对应任务。** 若采用此方案，现场 id 3、4、5 会进入普通 Scene 定时的编辑、启停和同步流程；此前提出的“只能去 Web 编辑”不再由 nodeSlots 缺失来判断。已有 Profile 类型保护不变。

因此建议将该方案定义为“版本 2 中可按 App 普通定时解释的记录，缺失/null 绑定视为未分配”，而不是“任意 Web 日程都能通过补 [] 获得完整兼容”。未知 Web 类型的无损保留和只读管理仍是另一种需求，不应在本次小修复中顺带扩展。

### 最小修改方案

1. **扩展现有共享入口。** 在 [TimedSchedulerSlotPolicy.swift](../SunSmart/Main/Timed/Model/TimedSchedulerSlotPolicy.swift) 的 `fillingMissingBindings` 增加 schema 2 分支：逐条将不存在的 nodeSlots 或 JSON null 补为 []。保留所有现有数组及记录的其他字段，不排序业务记录、不生成物理绑定、不改变启用状态或时间。
2. **保留现有校验。** 错误类型、非法身份、重复槽、重复业务 id、未知版本、App 不支持的 selectTarget/action/时间表达仍按原规则拒绝。禁止使用“转换失败就默认 []”的写法，否则会吞掉真正损坏的绑定。
3. **保持 legacy 语义。** 不将所有版本 1 的 nil 全部转成 []，因为已知旧格式的 id 代表物理槽位。现有“旧写入方丢失全部绑定且存在 id≥16”的兼容分支继续原样工作。若以后要支持版本 1 的显式 null，应单独确认其旧格式含义，不在本次默认跨版本升级。
4. **复用完整链路。** `repairingStaleBindings`、`schema`、`canonical`、备份读写已经调用该入口；`ImportData.update` 在预检及 staged import 前同样调用它。保证首次 GET、pending import、恢复重试、SQLite 回读、导出、云端回执均使用同一规范表示，不仅在 UI 或单次 GET 上修改。
5. **利用现有存储。** Schedule Codable 与 SQLite 的 nodeSlots 列已经支持 []，不需要新表或新字段；Schedule 的复制也已经保留该数组。导入后本地保存 []，以后正常导出发送 []；不为补默认值专门触发一次覆盖云端的上传。
6. **保持云端确认严格性。** 仅 missing/null/[] 之间视为相同的“未分配”表示。上传了非空绑定、GET 却返回缺失/null 时，归一化后的 [] 仍必须与提交内容不相等，不能误报同步成功。

生产改动预计主要集中在这一共享 policy；是否需要其他生产调整取决于导入/持久化/回执回归结果，不能把只改一个文件作为先验限制。UI 提示与 Space 删除无需因该方案新增规则。

### 已验证的行为与必须说明的边界

**1. 导入与持久化表示。** 使用当前生产 Timed policy 与提取的生产 Schedule Codable，对现场数据及内存变体执行诊断：

| 输入/场景 | 结果 |
|---|---|
| 服务器原始缺字段 | repair/canonical 失败 |
| 将同样 3 条改成 null | repair/canonical 失败 |
| 以上两种输入仅补成 [] | 均通过 canonical 与 Schedule 编解码往返，规范结果一致 |
| 原有 id 0、1、2 | 42 个绑定保持不变 |
| nodeSlots 为字符串 | 仍拒绝 |
| selectTarget=99 或 hour=25 | 仍拒绝，补 [] 不会让未知类型/非法时间自动变为合法 |
| 真正有绑定与空绑定比较 | 仍不相等，提交回执可区分 |

本节为方案评估阶段的隔离实验，当时未修改 policy，只构造输入变体。实施后的 SQLite 与回执回归结果见文首；网络接口与真机同步仍未执行。

**2. 空数组会进入槽位分配。** [TimedSchedulerBindings.swift](../SunSmart/Main/Timed/Model/TimedSchedulerBindings.swift) 的 `reserveForSending → prepare → commit` 对 [] 使用非 legacy 规划。目标设备缺少绑定时，列表可以显示待同步，后续下发会先预留槽位。规划可能由单条定时发送或相关拓扑操作调用，不只由编辑这条记录触发。

用现场第一个节点的身份和原有三个 Profile 绑定，执行生产槽位 planner，并将三个 Scene 定时作为该节点目标，得到：

| 模拟读到的设备占用槽位 | id 3 / 4 / 5 的新分配 |
|---|---|
| 0、1、2 | 3、4、5 |
| 0、1、2、3、4、5 | 6、7、8 |
| 槽位状态未知 | unknownCapacity，不继续分配 |
| 0…15 全部占用 | capacityExceeded，不继续分配 |

这证明现有分配器会避开已观测占用，但**不会把“看起来属于这条业务定时”的已有物理任务自动认领回来**。如果 Web/网关早已把同一任务下发到槽 3…5，补 [] 后再同步可能形成重复任务；之后 App 的启停/删除只操作自己新绑定的槽，旧槽可能继续执行。本轮没有设备读回或 Web 下发证据，不能断言现场已经发生，也不能因 JSON 中 nodes.schedules 为空而断言实际设备无任务。

**3. 自动补齐不等于 Web 特有字段的完整兼容。** 对现场新增记录执行当前生产 Codable 再编码，确认每条丢弃 `sceneGroups` 与 `second`。现场 second=0，App 也按秒 0 构建命令；sceneGroups=[C000] 与当前 Scene 的 Group 关联一致，因此当前 App 可用自己的关联模型解释该样本。但服务器是否依赖重新上传这两个字段，尚无契约证据。

额外构造 second=30 的内存变体后，当前 canonical 与 second=0 的结果仍相等；Schedule 不保存该值，命令仍按秒 0 生成。这说明 canonical 通过只保证 App 已知字段的语义，不保证未来 Web 专用字段被理解。日程名称包含“日出日落”也不能证明 App 支持天文时间规则；本样本只给出固定 hour/minute，未取得 Web 调度实现。

如果确认这些记录属于普通固定时刻定时，接受由 App 管理，且没有未映射的外部已下发槽位，那么自动补齐方案合理。若仍要求未知 Web 日程保持独立执行、原样上传或只读，则不能仅靠 [] 达成，需要额外的类型/来源语义及数据保留能力。

### Space 删除与失败恢复

- 已核对 [SiteViewController.swift](../SunSmart/Main/Site/Controller/SiteViewController.swift) 和 [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift)：删除要求 deviceCount=0，不要求定时列表为空；本样本仍有 14 台设备，原有设备限制保留。
- 云端 Space 删除直接使用 `.spaceDelete(siteId:spaceId:)`，成功后本地 `SpaceData.delete()` 调用 `Schedule.deleteAll` 按 Space 范围批量清理，不先逐条下发 Scheduler 删除。
- 当前 Schedule.save/load/encode 均支持 []，补齐本身不会增加删除限制，也不会要求先到 Web 删定时。设备移除依赖的 checkpoint/export 仍需在完整回归中验证，不能仅凭 UI 删除入口下结论。
- 容量未知或已满时使用既有失败提示与重试，不能为补齐绕过实际设备读回；保留现有回滚、绑定代次与晚到回执校验。
- 权限、网络、数据库和服务器错误仍按原规则处理，本轮没有执行实际 Space 删除。

### 已落实的验证范围与人工待验收

1. 在既有 TimedPayloadTests 增加 schema 2 缺失/null/空/非空混合、幂等、旧版不变和错误类型继续拒绝的行为用例；更新原先将 schema 2 缺字段视为非法的对应预期，保留真正损坏的负例。
2. 复用 TimedSlotPersistence 与 Space import/receipt 夹具，覆盖本次 6 条数据的导入、重载、导出、pending import 重试、原始 GET 与本地 [] 回读等价；验证非空绑定在 GET 中丢失仍不能确认上传。
3. 覆盖已知空闲、已有占用、状态未知和满容量；普通定时编辑/启停、取消/失败、晚到回执不改变既有绑定语义。保留 Profile 原有保护。
4. 已验证 SQLite 按 Space 批量清理且不影响另一 Space；完整设备移除后的 checkpoint/export 与真实零设备 Space 删除仍待 App 运行验收，本次未改写删除流程。
5. 已完成相关回归与一次 SunSmart generic iOS Debug 构建。进入 Space、正常定时编辑/启停、实际槽位读回和云端保存仍待真机验收。

用户已确认并完成上述普通定时默认值兼容，采用 App 管理语义；“未知 Web 日程只读保留”不在本次实施范围。
