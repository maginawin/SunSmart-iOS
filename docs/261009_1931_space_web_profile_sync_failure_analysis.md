# Space「空间 3」同步失败分析与 taskLevel 兼容修复

日期：2026-10-09（UTC+08:00）。范围：分析 App 代码与用户提供的两份 JSON，并在用户确认后实施 App 的 taskLevel 类型相关兼容；未修改 SDK、Web、服务器或固件，未请求线上接口。

## 结论

本次直接原因已确认：云端 C002「组 1」的 Profile 缺少 `taskLevel`，被修复前 App 的统一必填校验拦截。而且不是只缺顶层，Photocell 的 General、Night、Day 三个场景也各缺一处，共四处。App 的本地诊断记录、服务端样本与生产校验代码的离线复现完全对应。

`Reload cloud data` 会重新导入云端完整配置，也会执行相同校验，因此无法用同一份不完整配置解除保护。「This Space has not finished restoring…」是该操作失败后的通用提示，不代表本次存在一直执行不完的恢复任务。

进一步核对实际灯控消费者后，已按用户确认实施类型相关兼容：type 1/2/3/4/7/8 不使用 taskLevel 生成阶段灯控参数，缺失时规范化为 100；type 5/6 使用该字段，保留原有效配置要求，不统一静默补 100。修复前对 type 8 的统一必填校验过严，不能仅凭字段缺失就认定 Web 的实际 Photocell 灯控参数错误。此前“仅由 Web 补字段、App 无需调整”的建议已据此修正。

Web 补齐字段仍是兼容现有已发布 App 的直接办法。仅凭两份快照，尚不能最终区分字段在 Web 请求体生成、服务器落库还是 GET 组装时丢失；下文给出最短定位方式。

另有独立高风险差异：云端少了本地设备 EM1（00EE），但 `deviceCount` 仍为 5。需确认是否存在主动删除，不能将它直接认定为本次拦截原因，也不能在未确认时把云端快照当作完整设备清单。

## 证据与范围

输入：

- [App 导出 JSON](</Users/maginawin/Desktop/doing/huang sync issues/Space_空间 3_20261009_192652_386+0800.json>)。
- [get spaceprops 响应](</Users/maginawin/Desktop/doing/huang sync issues/Space_空间 3_20261009_server data.json>)，实际 Space 对象为 `data`。分析时文件名为 `server data.json`；实施验证时已改名，重新确认 Space UUID、更新时间、type 8 及四处缺字段一致。
- 当前分支 `feat/timed-limited-261008`，HEAD `1455b3b82c6c2adbd5dc82ad86202a03a4399e13`；分析开始时工作树无未提交改动。

App 文件是诊断导出，`_debugInspection.uploadable=false`，其中 `spaces[0]` 可用于对比，`rawLocal` 包含本地数据库证据。它不是可直接回传服务器的修复请求体。本文不复制网络密钥、设备密钥、账号或密码。

| 项目 | App 本地 | 服务端返回 |
| --- | --- | --- |
| Space UUID | `845E3550-5CC2-4C62-9B27-F33466B7AEC6` | 相同 |
| 配置更新时间 | `1791544360`，19:12:40 | `1791544462`，19:14:22 |
| C002 Profile ID | `52A411BA-4D8B-47A8-B47F-6B832F3A563A` | 相同 |
| Profile 类型 | 1，Occupancy + Daylight | 8，Proximity Lighting with Photocell |
| 顶层 `taskLevel` | 100 | 缺失 |
| Profile 场景 | FF00，含 `taskLevel=100` | FF00/FF01/FF02，均缺 `taskLevel` |
| `nodes` 数量 | 5 | 4 |
| `deviceCount` | 5 | 5 |
| `netKey` / `appKey` | 与服务端逐字段相同 | 与本地逐字段相同 |
| `spaceData` | schema 1，空 `triggerZones` | 相同 |

App `_debugInspection.spaces[0].status`：

- `blockedReason = invalidRemoteProfile:C002:invalidProfileField:taskLevel`。
- `configurationInitialized = true`，`membershipPhase = joined`。
- `pendingImport = false`，`pendingDeletionCleanup = false`，`recoveryPhase = active`。
- 本地 Space 行的 `syncCloudError = -2005`；当前代码对应 `configurationReviewRequired`，不是服务器 HTTP 错误码。
- `comparisonPayloadAvailable=true`、诊断 `issues=[]` 表示本地检查副本可用，不代表云端 Profile 校验通过。

## 修复前两个提示为什么连续出现

1. [SpaceMembershipCoordinator.swift](../SunSmart/Common/Data/SpaceMembershipCoordinator.swift) 的 `restoreConfiguration` 校对 Space/网络身份后调用 `SpaceData.update`。
2. [ImportData.swift](../SunSmart/Common/Data/ImportData.swift) 在替换 Group/Profile/Node 之前调用 `profilesIssue(in:)`。本例返回 `C002:invalidProfileField:taskLevel`，记录 `invalidRemoteProfile:` 阻断原因；有可用本地配置时跳过远端替换，保留本地数据。
3. [SpaceConfigurationSafety.swift](../SunSmart/Common/Data/SpaceConfigurationSafety.swift) 保存阻断状态，并保留首个原因。
4. [SpaceViewController.swift](../SunSmart/Main/Space/Controller/SpaceViewController.swift) 的 `updateSyncState` 检测 `isBlocked`，显示 `Synchronization failure`，打开包含 `Reload cloud data` 的恢复对话框。
5. `reloadConfigurationFromCloud` 再 GET 同一个 Space，调用 `restoreConfiguration(... authoritativeGET: true)`。该参数用于权威 GET 的恢复处理，并不跳过 Profile 完整性检查。
6. 同一份数据仍缺字段，阻断保留。页面只有在导入结果未被拒绝且 `!isBlocked` 时才显示成功；否则显示 `space_recovery_unavailable`，即用户看到的「This Space has not finished restoring…」。即使返回的是保留本地数据的 skipped，也不能算恢复成功。

因此，现有证据支持的是“云端配置预检失败 → 本地保护 → 再次获取仍失败”。不能据此把问题归因于 BLE 通信、网关离线、恢复队列卡死或设备固件。

## Web/服务端兼容未修复 App 的调整

### 1. 修正 Photocell Profile 的完整对象生成

以下路径均位于响应 `data.groups[address=C002].profile` 下：

| 兼容未修复 App 需补齐的路径 | 本例建议值与依据 |
| --- | --- |
| `taskLevel` | 100；原本地值及当前 App 模型默认值均为 100 |
| `scenes[number=FF00].taskLevel` | 100；原 General Scene 值为 100 |
| `scenes[number=FF01].taskLevel` | 若无另行配置，采用当前模型默认值 100 |
| `scenes[number=FF02].taskLevel` | 若无另行配置，采用当前模型默认值 100 |

这里的 100 是本样本与现有模型对应的修复建议，不是对所有 Profile/历史数据无条件覆盖。已有合法值应保留；type 8 的显式字段须为 JSON 整数且在 0…100，不能用字符串、null 或布尔值代替；本次 App 修复仅新增缺字段兼容。

[SpaceConfigurationIntegrityPolicy.swift](../SunSmart/Common/Data/SpaceConfigurationIntegrityPolicy.swift) 修复前的校验契约为（修复后的 taskLevel 例外见下文）：

- Profile 顶层要求有效 `id`、`type`，以及 `highEndTrim`、`lowEndTrim`、`occupancyLevel`、`vacantLevel`、`taskLevel`、`timeT1`…`timeT5`、`manualOverrideTimeout`、`powerUpState`。
- type 8 还要求合法 `proximityLightingNumber`、非空且场景编号不重复的 `scenes`；每个场景须有 `number`、`name`、`occupancyLevel`、`vacantLevel`、`standbyLevel`、`taskLevel`、`timeT1`…`timeT5`。
- `day` / `night` 的 `sceneNumber` 必须引用这些场景。当前样本 FF02/FF01 引用存在；缺失的是被引用场景中的字段。
- 本例三个场景均缺失，因此只修复顶层或只修复 General Scene 都不够。

[ExportData.swift](../SunSmart/Common/Data/ExportData.swift) 始终导出 Profile 顶层和每个场景的 `taskLevel`。[Profile.swift](../SunSmart/Main/Profile/Model/Profile.swift) 对 type 8 的界面没有展示 taskLevel 编辑项，但模型仍保存该字段，默认值为 100。Web 不能用“当前表单未显示某项”作为删除持久化字段的依据。

导入构造函数确实还存在 `taskLevel ?? 100` 的默认值逻辑，但执行顺序是先完整性校验，再构造模型，当前不会执行到缺字段补值。结合实际用途，建议按下文规则把可安全兼容的补值前移，并统一配置比较规则，而不是继续要求业务上不使用该字段的类型提供它。

### 2. 优先排查类型切换和场景模板的序列化

服务端保留了相同 Profile ID，类型从 1 变为 8，还存在 `typeSwitchedFrom=1`。四处同时缺少同名字段，且新增场景 FF01/FF02 也不含它，优先怀疑：

- Web 类型切换时用可见表单重建 Profile，丢弃隐藏字段；
- 新建 Photocell 场景的默认模板漏了 `taskLevel`；
- 保存时的字段白名单，或服务器 Profile/scene DTO 过滤了该字段。

这是定位优先级，不是已读 Web 源码后的定论。应比对同一次保存的四个位置：**编辑前 GET → Web 提交 body → 持久化记录 → 保存后 GET**。请求体已缺失由 Web 修复；请求体完整而存储缺失由服务端写入修复；存储完整而 GET 缺失由返回映射修复。

服务器应在写入前按双方约定校验结构，并考虑现有 App 的兼容要求。若采用 Web 补字段方案，还需修复已经落库的缺字段 Profile，并更新配置版本/更新时间，否则现有 Space 反复 Reload 仍只会得到当前 App 无法导入的数据。

另外，样本还缺少本地存在的 `adjustSpeed`、`autoMinLevel`、`calibrationMode`、`powerOnCct`、`targetNightBrightness`。这些不属于本次直接失败字段，当前代码有默认/兼容处理；仍建议类型切换时按明确规则保留或转换，不要统一从表单值重建并删除所有未展示字段。

### 3. 核实设备清单完整性，避免修完字段后丢设备

本地 EM1：地址 `00EE`，PID `24C1`，`groupState=0`，未加入 C002；服务端仅包含四台在 C002 的 L1…L4。生产节点身份比较确认，云端四台是本地五台的同一配网实例子集，缺失项为 00EE。

目前缺少 Web 操作和删除记录，无法确定这是主动删除还是错误过滤。应检查保存/查询是否只取了“当前 Group 设备”或“支持当前 Profile 的设备”，从而漏掉未分组/其他设备类型；也要核查是否有其他客户端的合法删除。

`SpaceData.update` 成功应用完整快照时会移除当前网络节点并按远端 `nodes` 重建。故若 EM1 并未被用户删除，在云端补齐 Profile 后直接 Reload 可能使本地 EM1 消失。应先恢复正确成员清单，并保持 `deviceCount` 与同一版本的节点集合一致。不能仅把 `deviceCount` 改成 4 来代替确认删除意图。

### 4. 保留节点扩展数据；这是关联风险，不是当前阻断原因

本地 `nodes[].custProps.schedulerModelStates` 均存在；L2/L3/L4 各记录两个 Scheduler Model 的“已确认空”状态。服务端四台的 `custProps` 都是空对象。

当前解析器允许旧格式缺少该扩展，离线检查没有因此报错，所以它不是本次 `invalidRemoteProfile` 的原因。但丢弃扩展会失去每个 Model 的已知状态；`schedules=[]` 不能表达同样的信息，也可能影响后续读回一致性和设备同步判断。

两份快照不能证明这些扩展曾被上传并由本次 Web 操作删除。Web/服务端应检查自己的往返链路是否完整保留已有 `custProps`，对不理解的扩展字段保持透传，不能在一次 Profile 编辑时无条件重置为 `{}`。

## App 按用途兼容缺失 taskLevel（已实施）

实际消费者为 [Profile.swift](../SunSmart/Main/Profile/Model/Profile.swift) 的 `LightData` 类型分支，以及 [Node+SyncData.swift](../SunSmart/Common/Data/Node+SyncData.swift) 的 `getNodeLightDataSyncProfiles`。type 5/6 才生成 `.taskLevel`；type 1/2/3/4/7/8 使用 occupancy/vacant/standby 阶段参数。Photocell 的 Day/Night 场景沿同一类型规则生成设备配置。

| 类型 | taskLevel 用途 | 已采用的缺失策略 |
| --- | --- | --- |
| 1/2，Occupancy/Vacancy + Daylight | 阶段照度使用 occupancy/vacant/standby，未使用 taskLevel | Profile 顶层及场景缺失时补 100 |
| 3/4，Occupancy/Vacancy | 未使用 | 同上 |
| 7/8，Proximity / Photocell | 未使用 | 同上；本例四处均可补齐 |
| 5，Daylight | 持续维持照度 | 保留有效配置要求，不因为此次兼容统一静默补 100 |
| 6，Manual Control | 目标亮度 | 保留有效配置要求，不因为此次兼容统一静默补 100 |

实施边界：

1. 仅处理字段不存在。已有合法值（包括 0）原样保留；null、字符串、布尔值、负值和越界值继续按既有校验拒绝，不把所有异常都转成 100。
2. 在现有共享完整性策略中复用一个明确的类型规则；导入、导出校验、Space 引用清理、配置摘要、上传读回和持久化基线比较必须一致。不能只在 Reload 按钮或模型构造阶段补值。
3. 对允许兼容的类型，比较时将缺失与显式 100 视为等价；显式非 100 值仍保留并参与比较。已保存的授权基线、待确认上传配置也需使用同一规范化规则，避免恢复后继续因表示差异被阻断。
4. 补值不代表用户修改灯控需求，不应只因补默认值而自动生成 Mesh 配置任务或强制回写云端。正常模型保存/导出可保留补齐后的值；更改 Profile 类型时继续沿既有类型转换流程。
5. type 5/6 的旧非 Photocell 场景目前存在缺字段默认兼容。本次不顺带收紧或扩大它；具体实现与回归需保持既有允许场景，并确认最终有效 taskLevel 的来源，避免覆盖用户明确的目标值。
6. 已补行为回归：本例四处缺字段可兼容、已有 0/其他合法值不被覆盖、显式非法值仍拒绝、type 5/6 顶层缺失仍受保护、缺失与 100 的往返及旧基线比较一致，并验证真实 Profile 导入/SQLite 重载/导出链路与上传读回重试。

实现集中在 `SpaceConfigurationIntegrityPolicy.swift`：同一私有补值函数供 Profile 预检和配置序列化使用，配置序列化同时用于新数据与持久化基线。现有导入器已经在模型创建时将缺失值补为 100，因此没有重复修改导入器、页面或恢复状态机；通过真实模型/数据库回归验证其结果。只补默认值不产生引用清理 repair，也没有新加云端写入或 Mesh 下发入口。

这能解决 taskLevel 兼容性，但不会解决 EM1 缺失或服务器裁剪其他字段，不能预先承诺整个 Space 一定恢复成功。

## 修复前复现与最短验收

已将两份真实输入送入当前生产文件 `SpaceConfigurationIntegrityPolicy.swift`，通过临时 Swift 探针执行，原文件未改动，补字段仅发生在探针内存副本中：

| 输入 | Profile 校验结果 |
| --- | --- |
| App 本地 `spaces[0]` | 通过 |
| 原服务端 `data` | `C002:invalidProfileField:taskLevel` |
| 只补 Profile 顶层 | `invalidPhotocellSceneField:taskLevel` |
| 再补 FF00 | 仍为 `invalidPhotocellSceneField:taskLevel` |
| 再补 FF01 | 仍为 `invalidPhotocellSceneField:taskLevel` |
| 再补 FF02，即四处全部补齐 | 通过；配置比较数据可生成 |

另外确认原服务端空日程的目标校验通过，Scheduler 扩展缺失按兼容路径可解析，网络密钥对象与本地相同。空 `triggerZones` 在两份数据中一致，不能作为本次坏数据证据。

以上是修复前的离线复现结果，不等于补字段后的整个 App 导入、服务器往返和 Mesh 配置已验收。当时未构建；本轮实施后的编译与自动化结果单列在下方。未运行真机或线上写入，也未读取 Web/服务端实现。

交给 Web/服务端团队的最短验收路径：

1. 在测试 Space 上复现 type 1 → type 8，逐级对比提交、存储和 GET 的四处 `taskLevel`；再测试已为 type 8 的普通编辑/再次保存，避免只修类型切换入口。
2. 确认 EM1 是否有合法删除记录；没有则保证完整 GET 保留它及未编辑的其他设备、扩展数据。
3. 修复当前 Space 的云端数据和更新版本后，用户在 App 点击 Reload，预期解除阻断，正确显示 type 8 与 FF00/FF01/FF02，设备清单与用户删除意图一致。
4. 再执行一次正常 App 保存/云端读回及重新进入；确认 Web 没有再次裁剪字段。设备实际灯光行为由用户另行验收。

责任与发布依赖：App 类型相关兼容已实施；Web 团队负责类型切换、场景模板和请求体；服务端团队负责约定的数据校验、持久化、GET 完整性及历史数据处理。未修复的 App 版本仍受原校验限制，Web 补字段可用于兼容这些版本。无本次必须修改的 SDK/固件项。

## 实施验证记录

- 生产代码只修改 `SpaceConfigurationIntegrityPolicy.swift`；新增回归放入现有三个测试文件，没有新建测试工程、修改资源或依赖。
- 完整性策略回归通过：覆盖六类安全补值、type 5/6 顶层保护、显式 0/37/100 保留、非法字段拒绝、Photocell 其他必要字段保护，以及旧配置基线双向等价比较。
- `check_profile_persistence.py` 通过：执行实际 Profile 模型、云端字段映射、SQLite 保存/重载/导出；六类缺字段输入恢复为完整 Profile，有效灯控参数不变。
- `check_space_recovery_receipts.py` 通过：显式非法值保留待确认上传，兼容缺字段后直接读回及重试可确认；原 `invalidRemoteProfile` 阻断在导入最终完成后解除，不产生新的修复上传。该恢复测试执行生产保护/回执方法，完整 Mesh 导入仍是隔离边界。
- `check_space_sync_cleanup.py` 通过：共享策略的完整 Space 引用清理、旧数据与既有边界回归通过。
- 改名后的真实服务端样本通过生产 Profile 校验，规范化结果包含四处 `taskLevel=100`；拓扑有效，引用修复数量为 0，节点仍为 4。没有改写样本文件或补入 EM1。
- SunSmart Debug generic iOS 无签名编译通过。入口 `SunSmartLocal.xcworkspace`，固定 DerivedData 为 `SunSmart-feat-timed-limited-261008`。本改动为五品牌共享纯逻辑，无资源/配置/编译条件差异，未机械重复五品牌构建。
- SDK realpath 为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk-worktrees/one-dev`，HEAD `2598bd169417b894dcb11ba7cf6c63185d7c5a66`，工作树干净，没有新增 SDK API 或发布依赖。
- `git diff --check` 通过。未安装或运行真机，实际 Reload、云端读回和设备列表仍由用户验收；先确认 EM1 缺失是否符合真实删除意图。
