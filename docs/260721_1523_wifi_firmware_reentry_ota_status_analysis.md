# WiFi Firmware Update 重新进入后 OTA 状态异常分析与修复计划（待确认）

## 1. 结论

问题真实存在，根因位于 App 的 WiFi DFU 会话恢复策略，不在 `0x43/0x11` SDK 协议解析层。

页面重新创建 coordinator 时会从 `UserDefaults` 恢复 OTA session。当前代码只把“未消费的非终态 session”标记为需要权威查询；如果缓存已经是 `VERIFY_FAIL`、`FAILED`、`TIMEOUT`、`CANCELLED` 或 `SUCCESS`，`refresh()` 会直接回放持久化 UI 状态并返回，不发送 `0x43/0x11`。

因此，只要离开页面前后本地 session 已持久化为 `upgradeFailed` 对应终态，后续每次重新进入页面都会继续展示旧的 `Upgrade failed`。由于该终态只有开始新一轮升级或成功页点击 `DONE` 才会被清理，旧失败状态可以长期保留。

这与现象“重新进入后一直提示 `upgrade failed`，Log 中没有正常获取当前 WiFi Gateway OTA 状态”完全一致。

## 2. 触发链路

1. 用户在 WiFi Firmware Update 页面发起升级。
2. coordinator 建立并持久化本轮 session，包括 `ota_id`、`firmware_id`、最后合法协议状态和 UI 状态。
3. 用户离开页面，页面执行 `deactivate()`，停止查询并移除消息/连接 observer；session 保留用于恢复。
4. 设备状态在离开前后进入失败终态，或失败终态已经被 App 持久化。
5. 用户重新进入页面，新 coordinator 从本地恢复该终态 session。
6. 初始化逻辑不会给终态 session 设置 `requiresAuthoritativeQuery`。
7. `refresh()` 命中本地终态分支，直接发送缓存的 `updateState(upgradeFailed)` 后返回。
8. `queryDFUStatus()` 未执行，所以 Log 中没有 `43 11` GET；页面也没有机会用设备当前 OTA 状态覆盖旧缓存。

## 3. 源码证据

### 3.1 恢复时只要求非终态权威查询

`SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift` 初始化恢复 session 时，只有 `lastStatus.stage.isTerminal != true` 才把 `requiresAuthoritativeQuery` 置为 `true`。

这意味着本地 `FAILED/TIMEOUT/VERIFY_FAIL/CANCELLED/SUCCESS` 都被当作无需再次确认的永久真值。

### 3.2 `refresh()` 对终态直接返回

同一文件的 `refresh()` 先检查恢复 session。若 `lastStatus` 是终态，它只回放 `lastState`，成功时再回放 confirmed version，然后直接返回。

`queryDFUStatus(authoritative:)` 位于这个提前返回之后，因此终态恢复路径不会发送 `SunricherVendorGet(function: .wifiGatewayDFUStatus)`，即不会产生 `43 11` 请求。

### 3.3 查询调度也排除了终态 session

`isActiveNonterminalSession` 只允许非终态 session。`handleNoValidStatus()`、延迟查询和连接变化恢复均依赖这个条件。

即使只把恢复终态标记为 `requiresAuthoritativeQuery`，如果不同时调整“查询资格”判断，首次查询失败或进入页面时 Mesh 尚未就绪，后续也无法按预期重试；代理连接恢复时同样不会立即补发 `43 11`。

### 3.4 现有测试缺少该场景

`Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift` 已覆盖：

- OTA 身份和阶段顺序；
- 首终态锁定；
- pending start 恢复；
- session 的 V1.9 key 保存/读取；
- 状态到 UI 的映射。

但没有覆盖：

- 从磁盘恢复未消费终态时的恢复策略；
- 终态缓存是否必须先做权威 `43 11`；
- 恢复查询返回 IDLE/身份不匹配时如何结束旧终态；
- 恢复查询失败后，终态 session 是否仍具备重试资格。

现有 focused tests 通过不能证明重新进入页面的恢复行为正确。

## 4. 与原设计的偏差

早期 WiFi DFU 页面设计明确要求：页面可见后先发送一次 `43 11` 恢复查询，再决定恢复 OTA UI或查询 `43 14` Current version。

V1.9 状态归并设计为了防止已确认终态被断连后的噪声覆盖，引入了“首终态锁定并持久化”。该规则适合单次活跃 coordinator 内的 EVENT/RET 归并，但当前实现把它扩大到了新的页面可见周期：磁盘缓存终态未经设备确认就直接成为 UI 真值。

正确边界应为：

- 同一个活跃页面周期内，首个合法终态继续锁定，不接受后续乱序 EVENT/RET。
- 页面退出后重新进入，或 App 重启恢复时，本地终态只作为待确认缓存，必须由新的权威 `43 11` 决定当前 UI。

## 5. 非根因与范围边界

- SDK 已有 `wifiGatewayDFUStatus` GET 和 V1.9 完整 RET parser；本问题不需要修改本地 `NordicSigMeshSDK`。
- 当前工作区对“相同版本也允许升级”的未提交测试修改只影响升级按钮版本比较，不参与 session 恢复和 `43 11` 查询，不是本问题根因；实施时必须保留该用户改动。
- 本问题不是云端 latest/history 请求导致，也不需要修改 `customerId=wifi`、本地化、资源或 target 配置。
- 本次不扩展取消协议，不修改 `0x43/0x15`，不重构 BLE/Mesh OTA 流程。

## 6. 方案比较

### 方案 A：所有重新恢复的未消费 session 都先做权威查询（推荐）

把页面重新可见或 App 重启视为新的恢复周期。无论本地最后状态是非终态还是终态，只要 session 尚未消费，就先发送一次 `43 11`；收到合法匹配状态后用 fresh reducer 重建本轮基线。

优点：

- 直接满足“重新进入获取当前 Gateway OTA 状态”。
- 非终态、失败、取消和成功使用一致恢复规则。
- 保留同页首终态锁定，不削弱乱序保护。
- 可自然覆盖页面退出、App 重启和代理重连。

代价：

- 需要调整 coordinator 中多个以“非终态”为前提的查询资格判断。
- 必须明确 IDLE 和身份不匹配对旧终态缓存的处理规则。

### 方案 B：只对失败类终态重新查询

仅 `VERIFY_FAIL/FAILED/TIMEOUT` 在重新进入时查询；`SUCCESS/CANCELLED` 继续直接回放缓存。

优点是改动更小，但规则不一致。`SUCCESS/CANCELLED` 同样可能已不是设备当前状态，后续仍可能出现相同的 stale UI 问题。测试矩阵也会分裂，不推荐。

### 方案 C：退出页面时删除终态或不持久化失败终态

重新进入不会再回放 `Upgrade failed`，但会丢失设备真实失败结果；页面离开期间也无法恢复完成状态。该方案绕过症状而不是恢复当前设备真值，不推荐。

## 7. 推荐设计

采用方案 A，并保持修改集中在 WiFi DFU App 层。

### 7.1 恢复优先级

coordinator 恢复到任何未消费 session 后，都设置“需要权威查询”。`refresh()` 必须先处理这个标记，再考虑回放本地终态。

本地最后状态只用于：

- 保留 session 身份（`ota_id + firmware_id`）；
- 查询暂时不可用时保留最后进度；
- 生成 `Communication timeout` 的进度展示。

它不能在新的页面周期中直接确认成功、失败或取消。

### 7.2 查询资格

把当前“仅非终态可查询”拆成更准确的条件：

- 未消费的非终态 session 可查询；
- 任何 `requiresAuthoritativeQuery == true` 的未消费 session 可查询，即使缓存是终态；
- 已消费 session 不可查询。

首次请求失败、Mesh 尚未连接、RET busy/非法或超时时，保持 communication unknown，并保留后续调度资格。代理重新连接后立即补发权威 `43 11`。

### 7.3 权威响应处理

| 权威 `43 11` 结果 | 处理 |
| --- | --- |
| `ota_id + firmware_id` 匹配的非终态 | 用 fresh reducer 接受并恢复 downloading/updating UI，继续正常查询 |
| 匹配的失败/取消终态 | 用设备返回覆盖缓存并显示对应终态 |
| 匹配的 SUCCESS | 显示完成状态并确认 Current version |
| 查询超时、busy、非法 payload | 不把缓存失败当作当前真值；显示 communication unknown，保留 session 并重试 |
| IDLE，且本地缓存已是终态 | 认为旧终态不再是 Gateway 当前 OTA 状态；清理旧 session，回到默认页并查询 `43 14` |
| 身份不匹配，且本地缓存已是终态 | 认为旧终态不再代表当前事务；清理旧 session，但不接管非本 App 建立的其它 OTA session |
| IDLE/身份不匹配，且本地缓存是非终态 | 保留原 session 和身份保护，进入 communication unknown 并重试，避免一次异常响应误删活动会话 |

### 7.4 同页终态规则不变

设备在当前可见页面内产生首个合法终态后，仍立即持久化、停止轮询并锁定 UI。只有页面经历退出/重新进入，或 App 重启恢复，才重新建立权威查询门。

这样修复恢复问题，同时不改变正常升级过程中的首终态防抖和乱序保护。

## 8. 修复计划

### Task 1：补恢复策略的失败测试

修改：

- `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`
- `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift` 或 `WiFiFirmwareDFUStatusReducer.swift`

计划：

1. 抽出可独立测试的 session 恢复/查询资格策略，避免测试依赖 UIKit 或真实 Mesh。
2. 先增加失败用例，证明当前终态恢复不会要求权威查询。
3. 覆盖未消费非终态、未消费失败终态、未消费成功终态、已消费 session 的恢复决策。
4. 覆盖“需要权威查询的终态仍可在失败后调度重试”。

完成标准：focused test 在实现前按预期失败，且失败点明确指向终态恢复策略。

### Task 2：修正 coordinator 恢复顺序与查询资格

修改：

- `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`

计划：

1. 恢复未消费 session 时统一打开权威查询门。
2. 调整 `refresh()` 顺序，优先发权威 `43 11`，不再先回放磁盘终态并返回。
3. 将查询资格从“非终态”调整为“非终态或正在等待权威恢复”。
4. 同步应用到首次查询失败、延迟重试和连接恢复分支。
5. 权威查询成功后继续使用 fresh reducer 重建基线，保持同页首终态锁定。

完成标准：重新进入持久化失败/成功/非终态 session 时都能看到一次实际 `43 11` 发送；查询失败后仍能重试。

### Task 3：处理权威 IDLE 与身份不匹配

修改：

- `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- 对应 focused tests

计划：

1. 为权威恢复结果增加明确分支，不再把所有 IDLE/mismatch 都当作相同的无效状态。
2. 仅当本地缓存已经是终态时，IDLE 或身份不匹配结束 stale session，回到默认页并查询 Current version。
3. 本地缓存为非终态时继续保留原 session，进入 communication unknown 并重试，避免误删在途升级。
4. 不自动接管其它 `ota_id` 或 `firmware_id` 的事务。

完成标准：旧 `Upgrade failed` 不会永久滞留；活动会话身份保护仍然成立。

### Task 4：补静态 contract 与回归验证

修改：

- `scripts/check_wifi_gateway_firmware_update.sh`
- 必要时补充 focused test 文件，不新增业务 target 文件

计划：

1. contract 检查恢复终态必须进入权威查询门。
2. contract 检查查询调度资格不能只绑定非终态。
3. 运行 reducer/session focused tests。
4. 运行 WiFi Gateway firmware update 静态 contract。
5. 运行 `git diff --check`。
6. 使用 generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO` 构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

完成标准：focused tests、contract、diff check 和四 target iPhoneOS build 全部通过。

## 9. 实机验收矩阵

1. 升级处于 DOWNLOADING 时退出并重新进入：进入后立即发送 `43 11`，恢复当前进度，不先发送 `43 14`。
2. 离开期间设备进入 VERIFYING/REBOOTING：重新进入后通过 `43 11` 展示当前 Updating 状态。
3. 离开期间设备失败：重新进入后通过 `43 11` 展示设备真实失败状态，而不是仅回放本地缓存。
4. 本地缓存是 `Upgrade failed`，设备当前为 IDLE：先收到 `43 11 IDLE`，清理 stale session，再查询 `43 14` 并回到默认页面。
5. 本地缓存是终态，进入时 Mesh 未连接：页面显示 communication unknown；代理恢复后立即发送 `43 11`。
6. `43 11` timeout/busy/非法：不伪造新的失败，不开放错误的新一轮事务；按恢复节奏继续查询。
7. 当前页面内正常收到失败终态：仍锁定该终态并停止轮询；只有离开再进入才重新确认。
8. SUCCESS 后重新进入：发送 `43 11`；匹配 SUCCESS 时保持完成页，IDLE 时清理旧 session 并以 `43 14` 确认当前版本。
9. BLE OTA、Mesh OTA 页面行为不变。

## 10. 风险与控制

- 风险：把终态加入查询资格后，如果只改初始化而不改调度 predicate，会出现“第一次查询失败后永不重试”。计划要求同步修改首次查询、timer 和连接恢复三个入口。
- 风险：无条件用 IDLE 清理非终态可能丢失活动 session。推荐方案仅对已缓存终态执行 stale 清理，非终态继续保留身份门。
- 风险：身份不匹配时自动接管其它 OTA 会混淆事务归属。推荐方案只结束 stale 终态，不接管陌生事务。
- 风险：现有用户未提交的相同版本升级测试改动被覆盖。实施前后均检查该 diff，并只修改恢复相关文件。

## 11. 本轮验证状态

- 已执行现有 `WiFiFirmwareDFUStatusReducerTests`：通过。
- 该通过结果同时证明当前测试缺少重新进入终态恢复用例，不能阻止本问题。
- 本轮仅新增本分析与待确认计划文档，没有修改业务代码、SDK、本地化、资源、依赖或 target 配置。

## 12. 待确认项

建议确认方案 A 及以下产品语义：新的页面可见周期中，未消费终态不再直接作为当前真值；必须先查询 Gateway。若权威结果为 IDLE 或其它事务，仅 stale 终态缓存被清理，活动非终态 session 继续保留并重试。
