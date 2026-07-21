# WiFi Gateway OTA Cancel `0x43/0x15` V1.9 设计

## 1. 目标

为 WiFi Gateway firmware update 页面增加真实的 OTA Cancel 能力，完整支持 V1.9 `0x43/0x15` SET/RET，并与现有 `0x43/0x10` Start、`0x43/0x11` Status RET/EVENT、页面重进权威恢复和两阶段首屏请求顺序协同工作。

实现必须满足：

- 仅在本轮 OTA 的 `PREPARING` 或 `DOWNLOADING` 阶段允许取消。
- 点击 `CANCEL` 后立即发送一次 `0x43/0x15`，不弹确认框。
- 同一 OTA 轮次只允许发送一次，不自动重发，也不提供 `CANCEL AGAIN`。
- RET 与 EVENT 乱序时按完整 `ota_id` 归并，首个有效决策生效。
- 7 秒无结论后最多执行 3 次恢复查询；仍未知时页面可见期间每 30 秒查询。
- 取消结果未知时暂停新的 `0x43/0x10`，直到完整 `IDLE` 或匹配本轮的终态解除。
- 离开页面后停止取消计时和查询；重新进入页面时通过权威 `0x43/0x11` 恢复，不重发 `0x43/0x15`。

## 2. 已确认的产品边界

- 采用“SDK 强类型协议 + App 独立取消事务状态机”。
- `CANCEL` 点击后立即发送，不显示二次确认。
- 发送后按钮标题仍为 `CANCEL`，立即变为不可点击，且同一 OTA 轮次不能重复点击。
- 取消 pending 期间不显示 `CANCELLING...`；继续展示最后合法 OTA 阶段和进度。
- 不实现 `Failed to cancel + CANCEL AGAIN`。
- 明确未取消时继续跟踪原 OTA，并给出一次轻提示。
- 取消结果未知时显示独立的等待确认状态，并禁止新 OTA。
- 离开 firmware update 页面后不运行全局 30 秒查询服务；重新进入页面再恢复。
- 不修改 BLE OTA、Mesh OTA、其它 Gateway 流程或共享 firmware 业务语义。
- 保留工作区现有“相同 WiFi firmware 版本允许升级”实验改动，本功能不回退、不扩展该规则。

## 3. 当前实现基线

### 3.1 App 已有能力

App 已具备：

- `WiFiFirmwareDFUCoordinator`：统一管理 Start、Status、Current Version、EVENT、连接变化和查询调度。
- `WiFiFirmwareDFUSession`：按 network UUID 和 node address 持久化 `ota_id`、目标 firmware ID、最后状态和权威恢复门。
- `WiFiFirmwareDFUStatusReducer`：执行身份匹配、阶段单向推进、下载进度单调和首终态锁定。
- `CANCELLED` 终态及 `Upgrade cancelled + UPGRADE AGAIN` UI。
- 页面重进时对未消费 session 执行权威 Status 查询。
- 首屏两阶段加载：`0x43/0x14` 与 cloud latest 均结束后，才启动 `0x43/0x11`。

取消实现必须扩展这些边界，不能建立第二套 OTA session 或绕过最新的 initial-load gate。

### 3.2 SDK 已有能力

本地 `NordicSigMeshSDK` 已支持强类型的 `0x43/0x10`、`0x43/0x11` 和 `0x43/0x14`，包括 Start RET 的 `ota_id` response matching，以及 Status RET/EVENT 的完整 V1.9 parser。

当前尚无 `0x43/0x15` request、response、subcode、parser 或 matcher。

### 3.3 工作区边界

- App 通过 `XCLocalSwiftPackageReference` 引用 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- App 与 SDK 是两个 Git 仓库；实现和验证需要分别检查 diff。
- App 当前存在其它未提交修改，后续实施必须逐文件保留，禁止覆盖或混入无关提交。

## 4. 总体架构

### 4.1 SDK 职责

SDK 只负责：

- `0x43/0x15` 请求模型和非零 `ota_id` 校验。
- 固定 payload 编码。
- RET 严格长度解析和 result 强类型映射。
- response code 路由。
- request/response `ota_id` 匹配。

SDK 不负责：

- 判断当前阶段是否允许取消。
- 判断 RET 与 OTA EVENT 的先后语义。
- 7 秒、3 次恢复查询或 30 秒查询调度。
- session 持久化、按钮状态或 UI 文案。

### 4.2 App 职责

App 使用三个明确边界：

1. `WiFiFirmwareDFUStatusReducer`：继续管理原 OTA 状态。
2. 新增 `WiFiFirmwareDFUCancelReducer`：只管理取消事务、竞态和恢复阶段。
3. `WiFiFirmwareDFUCoordinator`：唯一协调点，负责 Mesh 请求、计时、持久化和 UI event。

页面不直接解释 RET 或 EVENT，只展示 Coordinator 产出的 OTA 状态、取消可用性和一次性提示。

## 5. SDK 协议模型

### 5.1 SET 请求

请求格式：

```text
43 15 <ota_id:U64_LE>
```

规则：

- `ota_id` 必须非零。
- 编码总长度固定为 10 字节。
- 请求模型使用 `UInt64`，统一按 little-endian 编码。
- SDK 不提供 retry API；App 每轮只创建并发送一次请求。

### 5.2 RET 响应

响应格式：

```text
43 15 <ret> <ota_id:U64_LE>
```

解析规则：

- 总长度必须严格为 11 字节。
- 截断、尾随字节、错误 opcode 或错误 subcode 均拒绝解析。
- `ota_id` 按 little-endian 解码。
- SDK 允许解析错误应答中的 `ota_id == 0`，但它不能匹配 App 发出的非零 request。

Result 映射：

| `ret` | SDK result | App 基础含义 |
| --- | --- | --- |
| `0x00` | success | 相同 `ota_id` 已为 `CANCELLED` |
| `0x01` | invalidParameters | 参数错误，结束本次取消 |
| `0x02` | notCancelled | 取消未成功，交给 App 结合竞态决定 |
| `0x03` | unconfirmed | 取消结果未确认，进入 Status 恢复查询 |
| `0x04` | busy | 新取消事务结束，不改变原 pending 事务 |
| 其它 | reserved(rawValue:) | 按未确认处理 |

### 5.3 Response matching

`MeshMessageHandle` 必须同时验证：

- response opcode 正确。
- source node 正确。
- response code 为 `wifiGatewayDFUCancel`。
- response parameters 可解析为 Cancel RET。
- response `ota_id` 与 request `ota_id` 完全相同。

不匹配 RET 不结束当前 request。RET 仍可经过全局 message observer 到达 Coordinator，由已持久化事务做二次判断；任何不匹配身份的数据都不能改变本轮取消状态。

### 5.4 SDK 接线点

- 新建 `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUCancel.swift`。
- 修改 `SunricherVendorSet.swift`，增加 request case、payload 和 response command。
- 修改 `SunricherVendorStatus.swift`，增加 `VendorGatewayCode.wifiDFUCancel = 0x15`、response code、parser route 和 function parameters。
- 修改 `MeshProxyMessageCommand.swift`，增加 Cancel `ota_id` matcher。
- 修改 `VendorServerDelegate.swift`，在现有 WiFi Gateway 无节点属性副作用的 SET 分支中加入 Cancel case，保持 exhaustive switch 完整。

现有 `0x10`、`0x11`、`0x14` 和 OTA EVENT 类型保持不变。

## 6. App session 与取消状态模型

### 6.1 持久化字段

在现有 `WiFiFirmwareDFUSession` 中持久化取消子状态，至少表达：

- 本轮是否已经发送过 Cancel。
- 当前取消阶段：未请求、pending、恢复查询、结果未知、已结束。
- pending 期间是否见过匹配 `VERIFYING`。
- 已执行的恢复查询次数。
- 是否阻止新的 Start。
- 最后一次可展示的取消结果状态。

新增字段必须向后兼容已有 V1.9 session。旧数据缺少字段时按“从未请求取消、不额外阻止 Start”解码，不能删除仍合法的旧 OTA session。

计时器 deadline 不跨页面持久化。离页或 App 被挂起后，再进入时通过权威 Status 查询恢复，不尝试补发过期的 RET 等待。

### 6.2 取消可用性

Coordinator 仅在以下条件全部满足时允许点击：

- 页面 active 且 OTA observer 已在 initial-load gate 后启用。
- 存在未消费的本轮 session。
- `ota_id` 已绑定且非零。
- 最后合法状态同时匹配 `ota_id + firmware_id`。
- 最后合法阶段为 `PREPARING` 或 `DOWNLOADING`。
- `requiresAuthoritativeQuery == false`。
- 本轮从未发送过 Cancel。
- 尚未接受任何终态。
- 不处于取消未知暂停状态。

UI enabled 仅是展示层。Coordinator 的 `cancel()` 必须重新执行相同 guard，避免点击与状态推进之间的竞态。

### 6.3 点击原子性

点击 `CANCEL` 后的顺序固定为：

1. 在内存中把本轮标记为“已尝试取消”。
2. 持久化 session。
3. 发出按钮禁用 event。
4. 创建并发送唯一一次 `0x43/0x15`。
5. 启动 7 秒结果等待。

必须先持久化再发送，避免设备已收到命令而 App 退出后重复发送。

## 7. RET、EVENT 与终态归并

所有 RET callback、Status EVENT、Status GET 和 timer callback 都输入同一个取消 reducer。Reducer 产出决策，Coordinator 执行副作用；各 callback 不得直接各自修改 UI 或 session。

### 7.1 成功

- 匹配 `0x15/0x00`：立即锁定取消成功。
- 匹配 `CANCELLED` EVENT 或 GET：立即锁定取消成功。
- `0x00` 与 `CANCELLED` 无论谁先到，UI 和持久化只接受一次成功。
- 成功后停止取消 timer、恢复查询和普通 OTA 查询。
- 迟到 RET/EVENT 不得覆盖已锁定终态。

`0x15/0x00` 本身已经证明同一 `ota_id` 的设备状态为 `CANCELLED`。App 可立即进入现有 `Upgrade cancelled` UI，不必等待额外 `0x11`。

### 7.2 明确未取消

- `0x01`：结束取消事务，继续跟踪原 OTA。
- `0x04`：只结束本次新 Cancel，不改变 OTA；继续跟踪原 OTA。
- pending 期间已经见过匹配 `VERIFYING`，之后收到 `0x02`：取消未生效，继续跟踪原 OTA。
- 恢复查询取得匹配非终态：取消未生效，继续跟踪原 OTA。

这些分支均不允许再次 Cancel，并恢复原 OTA 的正常跟踪节奏。页面给出一次 `Unable to cancel. The update will continue.`，不进入独立失败页。

### 7.3 需要恢复查询

- 未见 `VERIFYING` 的普通 `0x02`。
- `0x03`。
- 未定义非成功 ret。
- 7 秒内既没有有效匹配 RET，也没有匹配终态。

以上分支进入第 8 节的 `0x11` 恢复查询。

### 7.4 `VERIFYING` 竞态

取消 pending 期间收到匹配 `VERIFYING`：

- 原 OTA status reducer 正常接受并更新为 `Updating...`。
- cancel reducer 记录 `sawVerifyingWhilePending = true`。
- 不结束 7 秒等待，不推断取消成功或失败。
- 后续匹配 `0x00` 或 `CANCELLED` 仍为取消成功。
- 后续匹配 `0x02` 表示取消未生效，原 OTA 继续。
- 后续其它匹配终态按原 OTA 结果结束。

### 7.5 实时 `CANCELLED` 授权

现有 status reducer 对无取消事务的 `VERIFYING -> CANCELLED` EVENT 保持保护。只有 Coordinator 能证明本轮确实已发送 Cancel 时，才以明确的 cancellation context 允许匹配 `CANCELLED` EVENT 成为终态。

不能全局移除该保护，也不能让任意 `CANCELLED` EVENT 绕过 `ota_id + firmware_id` 身份校验。

## 8. 查询与计时

### 8.1 7 秒结果等待

- 从唯一一次 `0x15` 实际发送后开始计时。
- 匹配 RET 或匹配终态先到时取消 7 秒 timer。
- 7 秒到期时必须重新检查 reducer phase；已锁定结果时不启动恢复查询。
- Cancel request 自身不由 App 重发。

### 8.2 最多 3 次恢复查询

连续执行最多 3 次 `0x43/0x11`，每次等待上限 3 秒。同一时刻最多一个 Status GET。

每次结果：

| 查询结果 | 决策 |
| --- | --- |
| 匹配 `CANCELLED` | 取消成功 |
| 匹配其它终态 | 原 OTA 已结束，按终态展示 |
| 匹配非终态 | 取消未生效，继续原 OTA |
| 完整 `IDLE` | 本次仍无可关联结果，继续下一次 |
| `ota_id` 或 firmware ID 不匹配 | 继续下一次 |
| busy、非法 RET、无响应 | 继续下一次 |

匹配非终态属于有效结论，立即结束三次恢复序列，不继续浪费查询次数。

### 8.3 结果未知

三次查询后仍没有有效结论：

- 持久化 `cancelResultUnknown`。
- 持久化阻止新的 `0x43/0x10`。
- 页面可见且 Mesh 已连接期间，每 30 秒查询一次 `0x43/0x11`。
- 不继续使用普通 10 秒 OTA 查询节奏。

30 秒查询结果：

- 完整 `IDLE`：清除旧 session 和暂停，返回正常 firmware 页面。
- 匹配本轮 `CANCELLED`：取消成功，解除暂停。
- 匹配本轮其它终态：按原 OTA 终态结束，解除暂停。
- 匹配本轮中间态：更新进度，继续显示结果未知并保持暂停。
- 身份不匹配、非法 RET 或无响应：保持暂停并继续 30 秒查询。

身份不匹配绝不能清除 cancel unknown session。最新的 authoritative recovery policy 必须增加 cancel-specific 分支，避免把旧终态恢复规则错误套用到尚未解决的取消暂停。

## 9. 页面生命周期与首屏请求顺序

### 9.1 离开页面

页面消失时：

- 停止 7 秒 timer、恢复查询和 30 秒 timer。
- 取消当前页面 generation 的 callback 消费资格。
- 持久化当前取消 phase、已尝试标记和 Start block。
- 不启动全局后台查询服务。

### 9.2 重新进入页面

重新进入仍遵守当前两阶段 initial-load gate：

1. 并行执行 `0x43/0x14` Current Version 与 cloud latest。
2. 两者均结束后启用 OTA observer。
3. 对持久化 session 发送权威 `0x43/0x11`。
4. 不重发 `0x43/0x15`。

若恢复的是 cancel pending、恢复查询或 unknown phase，页面先展示持久化状态；权威 GET 到达后按第 8 节决策。旧 generation 或离页后的迟到 callback 不得发送查询或更新取消状态。

### 9.3 Mesh 断线与重连

- 断线时停止当前等待与普通查询，标记必须权威恢复。
- 页面仍可见且 Mesh 重连后立即发权威 `0x43/0x11`。
- 重连前 EVENT、缓存状态或旧 callback 不能重新开放 `CANCEL`。
- 重连后不得重发 `0x43/0x15`。

## 10. Start 防线

`WiFiFirmwareDFUCoordinator.start()` 必须在清理旧 session 之前检查：

- 是否存在未消费 OTA session。
- 是否存在已发送但未解决的取消事务。
- 是否存在 cancel unknown Start block。
- 是否有 Start request 或 pending Start 在途。

任一条件成立时不得发送新的 `0x43/0x10`，也不得通过 `clearSession()` 绕过暂停。UI disabled 不是唯一防线。

只有以下情况可以解除取消暂停：

- 完整合法 `IDLE` RET。
- 匹配原轮次的任一合法终态。
- 用户在已知终态 UI 执行既有消费/重新升级流程。

身份不匹配、无响应、非法状态或页面重进本身都不能解除。

## 11. UI 设计

### 11.1 按钮映射

| 状态 | 标题 | Enabled | Action |
| --- | --- | --- | --- |
| 权威确认的 `PREPARING/DOWNLOADING`，本轮未取消 | `CANCEL` | 是 | 发送一次 Cancel |
| Cancel pending / recovery | `CANCEL` | 否 | 无 |
| `VERIFYING` 及以后，未取消 | `CANCEL` | 否 | 无 |
| 明确未取消后原 OTA 继续 | `CANCEL` | 否 | 无 |
| Cancel result unknown | `CANCEL` | 否 | 无 |
| Cancel success | `UPGRADE AGAIN` | 是 | 既有重新升级流程 |
| 原 OTA 其它终态 | 既有按钮 | 既有规则 | 既有规则 |

按钮点击后不弹确认框、不改为 `CANCELLING...`、不隐藏。

### 11.2 Pending 与明确未取消

- Pending/recovery 期间继续展示最后合法的 `Downloading...` 或 `Updating...` 和进度。
- `VERIFYING` 到达时可更新原 OTA UI，但 Cancel 仍禁用。
- 明确未取消时显示一次轻提示：
  - English：`Unable to cancel. The update will continue.`
  - 简体中文：`无法取消，固件升级将继续。`
- 不显示 `Failed to cancel` 页面。

### 11.3 Cancel success

沿用现有：

- `Upgrade cancelled`。
- 最后合法进度。
- `alert_failed` 图标和提示色。
- `UPGRADE AGAIN`。

不新增图片资源。

### 11.4 Cancel result unknown

新增状态：

- Title：`Cancellation result unknown`。
- Detail：`Waiting for status confirmation`。
- Button：disabled `CANCEL`。
- 后续匹配中间态可更新进度，但保持 unknown 标题和 Start block。

建议简体中文：

- `取消结果未知`
- `正在等待状态确认`

所有文案进入 English 和简体中文本地化文件，禁止硬编码。

## 12. 错误处理与幂等性

- 所有 timer、request 和 callback 使用 generation/phase 校验，过期回调无副作用。
- 所有 session 决策在主线程串行执行；纯 reducer 不持有 timer 或 Mesh 对象。
- 首个合法 OTA 终态锁定后，Cancel RET 和 EVENT 均不能覆盖。
- 首个取消成功决策锁定后，不重复显示成功、toast 或重新调度。
- `0x04` 不进入取消成功幂等判断；它只结束本次新 Cancel。
- Parser 接受的 `ota_id == 0` 错误 RET 因无法匹配本轮非零 ID，不改变 session。
- 页面层不得自行根据 timeout、按钮状态或 HTTP 结果推断取消成功或失败。

## 13. App 文件影响面

- 新建 `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift`。
- 修改 `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`。
- 修改 `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift`。
- 修改 `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`。
- 修改 `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`。
- 修改 `SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift`。
- 修改 `SunSmart/en.lproj/Localizable.strings`。
- 修改 `SunSmart/zh-Hans.lproj/Localizable.strings`。
- 修改 `SunSmart.xcodeproj/project.pbxproj`。
- 新建 `Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift`，独立覆盖取消事务状态机。
- 修改 `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`，仅补取消与 status reducer 的边界回归。
- 修改 `scripts/check_wifi_gateway_firmware_update.sh`。

新增 App 源文件必须加入 Common 共享 target，使 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 同步编译。不得覆盖当前 initial-load gate、re-entry recovery 和 Auto Layout 修复。

## 14. 测试设计

### 14.1 SDK focused tests

- 非零 request validation。
- U64 little-endian 编码和固定 10 字节请求。
- 固定 11 字节 RET；截断和尾随拒绝。
- `0x00...0x04` 与 unknown ret。
- 参数错误回显非零 ID、`ota_id == 0`。
- 正确与错误 `ota_id` response matching。
- Cancel、Start、Status、Firmware Version response 互不误匹配。

### 14.2 Cancel reducer tests

- 所有取消可用性前置条件。
- 点击后持久化优先、单次发送和按钮立即禁用。
- RET 先于 EVENT、EVENT 先于 RET。
- `0x00` 与 `CANCELLED` 幂等。
- `VERIFYING -> 0x02` 竞态。
- 普通 `0x02`、`0x03`、unknown ret、`0x04`。
- 其它终态先于迟到 RET。
- 7 秒 timer 过期与已决策保护。
- 3 次恢复查询的全部结果分支。
- unknown 后 30 秒查询、匹配中间态继续暂停。
- 完整 `IDLE` 或匹配终态解除暂停。
- 身份不匹配不得解除暂停。
- 离页停止、重进权威恢复且不重发 Cancel。
- cancel unknown 阻止 Start。
- 旧 session 向后兼容解码。

### 14.3 现有回归

- `0x10` Start response correlation。
- `0x11` RET/EVENT parser 和状态 reducer。
- 页面重进 terminal/nonterminal authoritative recovery。
- `0x14 + cloud latest -> 0x11` initial-load gate 顺序。
- 重复 completion、旧 generation 和离页 callback 防护。
- 现有 `Upgrade cancelled + UPGRADE AGAIN` UI。
- 其它 firmware 页面没有 Cancel case 或文案污染。

## 15. 构建与验收

按以下顺序收口：

1. SDK Cancel focused tests。
2. App Cancel/Status reducer focused tests。
3. `scripts/check_wifi_gateway_firmware_update.sh`。
4. `plutil -lint` 检查 project 和两个 localization 文件。
5. App 与 SDK 分别执行 `git diff --check`。
6. `NordicSigMeshDemo` Debug generic iPhoneOS build。
7. App Debug generic iPhoneOS builds：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。

所有 iOS 构建直接使用 `xcodebuild`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'` 和 `CODE_SIGNING_ALLOWED=NO`。不使用 Simulator、shell 包装或日志重定向。

真机日志验收至少证明：

- 正常阶段只发出一次 `43 15 <ota_id>`。
- 按钮点击后立即禁用。
- RET/EVENT 两种顺序均能收敛。
- 7 秒与恢复查询节奏符合设计。
- 离页重进后没有第二条 `43 15`。
- cancel unknown 期间没有新的 `43 10`。

## 16. 明确不做

- 不自动重发 `0x43/0x15`。
- 不提供 `CANCEL AGAIN`。
- 不弹取消确认框。
- 不把按钮改成 `CANCELLING...`。
- 不建立离页后的全局 30 秒查询服务。
- 不修改 BLE OTA、Mesh OTA 或其它 Gateway 流程。
- 不新增图片资源、依赖或 Auth 信息。
- 不顺手重构 shared firmware page、Mesh manager 或 vendor protocol 基础层。
- 不回退或扩展工作区已有的相同版本升级实验。

## 17. 验收标准

- SDK 严格编解码 `0x43/0x15` 并按完整 `ota_id` 匹配 RET。
- App 只在合法阶段和权威身份成立时开放 Cancel。
- 同一 OTA 轮次最多发送一次 Cancel，发送后永久禁用本轮 Cancel。
- RET、EVENT、GET 和 timer 统一经过纯取消 reducer 收敛。
- `VERIFYING` 竞态、`0x02`、`0x03`、`0x04` 和 unknown ret 均符合 V1.9。
- 7 秒、3 次 × 3 秒和 unknown 后 30 秒节奏准确。
- cancel unknown 只由完整 `IDLE` 或匹配终态解除，并阻止新的 Start。
- 页面离开停止查询，重进权威恢复且绝不重发 Cancel。
- 新增文案完成 English 与简体中文国际化。
- initial-load gate、re-entry recovery、现有 OTA 状态与四品牌 target 无回归。
- focused tests、contracts、lint、SDK Demo 和四个 App iPhoneOS builds 完成并记录结果。
