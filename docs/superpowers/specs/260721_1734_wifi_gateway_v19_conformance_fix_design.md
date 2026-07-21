# WiFi Gateway V1.9 一致性修复设计

## 1. 背景

最新协议为 `/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/WiFi Gateway V1.9.md`。现有 App 与本地 `NordicSigMeshSDK` 已覆盖 `0x0D` 至 `0x15` 以及 `0x11` EVENT，但在 Wi-Fi 凭据编码、不确定结果恢复、RSSI/Internet typed model、请求 deadline、OTA 页面恢复顺序和 Cancel transaction 生命周期方面仍未完整符合 V1.9。

本设计只处理用户确认的 P0、P1 问题。实施采用“协议核心先行，再分链路集成”的方案 A：先让 SDK 成为严格、无歧义的 V1.9 wire truth，再接入 App Wi-Fi 状态机，最后调整 OTA 恢复与 transaction gate。

## 2. 目标

1. 严格实现 V1.9 Wi-Fi 凭据 UTF-8 与字节长度规则，并让协议第 12.1 节示例在 SDK 和 App 链路中按原始字节通过。
2. 为 `0x0D`、`0x13` 的不确定结果增加一次且仅一次的 `0x12` 恢复查询，不自动重发任何 SET。
3. 让 `0x0F` 的 RSSI 结果与 Internet 状态始终作为两个独立 typed 字段存在。
4. 让所有 V1.9 请求使用对应 Subcode 的最大等待时间，迟到结果不得改变已结束事务。
5. 让 Wi-Fi 连接轮询满足立即查询、5 秒间隔和 65 秒总窗口，并保证 `0x0E 06` 不改变当前连接状态。
6. 让 OTA 页面在激活或恢复时优先监听并查询 `0x11`，不再受云请求和 `0x14` 阻塞。
7. 用独立 transaction gate 保证原 `0x15` Mesh transaction 结束前不能创建新的 `0x10`。
8. 修正 `0x11/0x14` identifier 校验、`0x0D/0x12/0x13` typed enum 命名及 `0x15 04` 恢复语义。
9. 保持 RSSI completion-to-next-start 轮询间隔为 5 秒，并把静态检查同步到当前产品契约。

## 3. 非目标

本轮不处理以下事项：

- HTTP OTA 的签名、证书、HTTPS 或防回滚方案。
- `0x12` 明文密码回读的协议安全设计。
- App 使用 `UserDefaults` 缓存 Wi-Fi 密码的存储策略。
- V1.9 capability/version 协商。
- 普通命令 transaction ID。
- 协议 result code 的下一版拆分。
- 其它 Gateway、普通 Mesh OTA 或 BLE OTA 行为。
- 与本任务无关的 controller 重构、命名整理或格式化。

## 4. 已确认的关键决策

### 4.1 严格采用 V1.9

`0x0F` RET 只接受精确 5 字节格式：

`43 0F <rssi_status> <rssi> <network_status>`

当前 SDK 对旧 4 字节 RET 的兼容将删除，`WiFiGatewayNetworkStatus.notReported` 也不再属于 V1.9 typed model。该选择遵循协议首页“不兼容旧格式”的声明。

### 4.2 协议层与业务层分工

- SDK 负责 payload 构造、精确长度、字符合法性、typed parsing 和 raw-value 语义。
- App 负责请求时序、一次性恢复、轮询、UI 状态和 transaction 生命周期。
- SDK 不包含 UI、Timer、HUD 或云请求逻辑。
- ViewController 不自行复制协议字段限制，输入可用性通过 SDK credential validator 的结果决定。

### 4.3 不确定不等于失败

`0x0D 02`、`0x12 02`、`0x13 02` 统一使用 `.unconfirmed` 语义。该命名只表示当前 RET 不能证明目标结果，不得让 App 推导出“确定写入失败”“确定读取失败”或“确定清除失败”。

### 4.4 修改状态的 SET 不重发

`0x0D`、`0x10`、`0x13`、`0x15` 都不因 RET 丢失、malformed RET、busy-or-failed 或恢复失败而自动重发。恢复只能使用协议明确允许的 GET。

## 5. SDK 协议真值层

SDK 仓库路径为 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。

### 5.1 Wi-Fi 凭据

`WiFiGatewayCredentials` 按 UTF-8 原始字节工作：

- SSID 长度为 `1...32` bytes。
- Password 长度为 `0` 或 `8...63` bytes。
- 空字符串 password 与 `nil` 都编码为开放网络的零长度字段。
- 输入必须是合法 Swift `String`，编码后不做 trim、大小写转换或 Unicode normalization。
- 禁止 Unicode scalar `U+0000...U+001F` 和 `U+007F...U+009F`。
- 双引号、逗号、反斜杠和其它非控制 Unicode 字符允许出现。
- 控制字符必须按 Unicode scalar 判断，不能把合法多字节 UTF-8 continuation byte 错判为 `U+0080...U+009F`。

`WiFiGatewayCredentials` 的 `Equatable` 契约应明确包含保存下来的原始 SSID/password bytes，使恢复查询可以按协议要求做逐字节比较，而不是依赖 Swift `String` 的规范等价比较。

协议第 12.1 节示例必须编码为协议给出的精确 payload，并能够由 `0x12` 成功解码为相同原始字节。

### 5.2 typed enum

命名统一如下：

- `WiFiGatewayCredentialsSetResult`
  - `.accepted`
  - `.invalidParameters`
  - `.unconfirmed`
  - `.reserved(rawValue:)`
- `WiFiGatewayCredentialsReadResult`
  - `.success(credentials)`
  - `.notConfigured`
  - `.unconfirmed`
  - `.reserved(rawValue:)`
- `WiFiGatewayCredentialsClearResult`
  - `.cleared`
  - `.invalidParameters`
  - `.unconfirmed`
  - `.reserved(rawValue:)`
- `WiFiGatewayConnectionStatus`
  - 保留现有 `0x00...0x04` case。
  - 新增 `.requestFormatError` 表示 `0x06`。
  - `0x05` 及其它值仍进入 reserved/failure 语义。

本轮不扩大修改通用 `SunricherVendorStatus.isSuccessful` 的历史定义。App 必须继续以 typed parameter 为业务真值，不能用 wrapper success flag 判断 `0x0E` 是否已连接。

### 5.3 `0x0F` typed model

`WiFiGatewayRSSIStatus` 从带关联值的枚举改为组合值类型，同时包含：

- `rssiResult: WiFiGatewayRSSIResult`
- `networkStatus: WiFiGatewayNetworkStatus`

`WiFiGatewayRSSIResult` 包含：

- `.valid(dbm:)`
- `.unavailable`
- `.readFailed`
- `.reserved(rawValue:)`

解析约束：

- payload 长度必须精确为 5。
- `rssi_status=0x00` 时，RSSI 必须为 `-127...-1 dBm`。
- `rssi_status!=0x00` 时，RSSI raw byte 必须为 `0`。
- `network_status` 无论 RSSI 是否有效都必须解析和保留。
- 未知 RSSI 状态在 UI 层按不可用处理；未知 Internet 状态按 unknown 处理。
- 删除 legacy `.notReported` 网络状态及 4-byte parser/test。

### 5.4 共用 identifier validator

新增 `WiFiGatewayV19TextValidator.swift`，集中实现协议中的文本规则：

- URL 仍使用当前 `0x10` 规则，不扩大本轮 URL grammar。
- firmware ID、module version、`0x14` version 均为 `1...32` bytes 的 printable ASCII。
- 上述 identifier 禁止 `"`、`,`、`\`。

以下位置复用同一 validator：

- `WiFiGatewayDFUStartRequest` 的 firmware ID。
- `WiFiGatewayDFUStatusParser` 的 firmware ID 与 module version。
- `SunricherVendorStatus` 的 `0x14` version parser。

validator 返回的失败必须让整个 RET/EVENT 失效，不能生成部分 typed value。

## 6. App Wi-Fi 请求基础设施

### 6.1 V1.9 deadline 表

新增 `SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift`，作为 App 侧唯一等待时间真值：

| Subcode | 最长等待 |
| --- | ---: |
| `0x0D` | 7 秒 |
| `0x0E` | 3 秒 |
| `0x0F` | 4 秒 |
| `0x10` | 3 秒 |
| `0x11` | 3 秒 |
| `0x12` | 7 秒 |
| `0x13` | 7 秒 |
| `0x14` | 7 秒 |
| `0x15` | 7 秒 |

同一模型还定义：

- `0x0E` 轮询间隔 5 秒。
- `0x0E` 总窗口 65 秒。
- `0x0F` completion-to-next-start 间隔 5 秒。

`sendWiFiGatewayGet`、credentials SET/CLEAR helper 不再有 10 秒默认参数。调用方必须按具体 Subcode 取值，避免新增命令时静默继承错误 deadline。

现有 OTA reducer 中 10 秒无状态、30 秒通信未知、30 秒未知恢复查询等业务定时不是单次 Mesh request deadline，继续留在各自状态机，不与本表混淆。

### 6.2 事务结束与迟到结果

App 继续使用当前 request ID/generation 与 SDK response matcher：

- 只有 source、opcode、Subcode 以及 OTA identity 匹配的 RET 能结束当前请求。
- callback/timeout 结束后，业务 generation 必须阻止旧 completion 更新后续 operation。
- EVENT 不结束 GET/SET transaction。
- 恢复 GET 只能在原 SET callback 或 timeout 已结束后发出。

## 7. `0x0D/0x13` 一次性恢复

新增 `WiFiGatewayCredentialMutationReducer.swift`，只表达协议决策，不直接发送 Mesh 请求或更新 UI。

### 7.1 `0x0D` 流程

1. 用户操作只发送一次 `0x0D`。
2. 收到 `.accepted`：记录目标凭据已由 SET 确认，立即开始 `0x0E` 连接轮询。
3. 收到 `.invalidParameters`：结束并显示确定失败，不查询 `0x12`。
4. 收到 `.unconfirmed`、reserved、nil、malformed RET 或 timeout：原 transaction 结束后只发送一次 `0x12`。
5. `0x12 .success` 且凭据与目标 raw bytes 完全相同：目标已达到，进入 `0x0E`；不得把原 `0x0D` 改写成 `.accepted`。
6. `0x12 .success` 但不相同，或 `.notConfigured`：目标未达到，恢复可编辑状态并显示失败。
7. `0x12 .unconfirmed`、reserved、nil、malformed RET 或 timeout：结果未知，恢复可编辑状态并显示无法确认。

reducer 必须保证每个 mutation 最多产生一个 recovery GET action，任何输入序列都不能产生第二个 `0x12` 或第二个 `0x0D`。

### 7.2 `0x13` 流程

1. 用户操作只发送一次 `0x13`，本地 SSID/password 不先行清空。
2. 收到 `.cleared`：清空本地字段、停止连接/RSSI 轮询、显示 Not Configured。
3. 收到 `.invalidParameters`：保留当前字段与已知状态，显示确定失败。
4. 收到 `.unconfirmed`、reserved、nil、malformed RET 或 timeout：原 transaction 结束后只发送一次 `0x12`。
5. `0x12 .notConfigured`：清除目标已达到，此时才清空本地字段并显示 Not Configured；不得把原 `0x13` 改写成 `.cleared`。
6. `0x12 .success(credentials)`：清除未达到，使用同一次回读的完整凭据刷新字段，并重新查询一次 `0x0E` 获取当前连接状态。
7. `0x12` 仍无确定结果：保留清除前字段和连接状态，显示无法确认。

### 7.3 UI 文案

新增英文与简体中文本地化 key，至少覆盖：

- English: `Unable to confirm Wi-Fi configuration.`
- 简体中文：`无法确认 Wi-Fi 配置结果。`
- English: `Unable to confirm Wi-Fi credential removal.`
- 简体中文：`无法确认 Wi-Fi 凭据清除结果。`

其它确定成功/失败继续复用现有文案。所有新文案都不得硬编码。

## 8. `0x0E` 连接轮询

新增 `WiFiGatewayConnectionPollingReducer.swift`，使用注入的时间点做纯状态判断，避免测试依赖真实 Timer。

流程定义：

1. `0x0D` 确认目标已生效时记录 65 秒窗口起点，并立即发送首个 `0x0E`。
2. `.connected`、`.passwordError`、`.failed`、`.notConfigured` 或 reserved 结束轮询。
3. `.notStartedOrConnecting` 在当前 GET completion 后等待 5 秒，再发送 one-shot GET。
4. `.requestFormatError` 不改变当前连接状态；若 65 秒窗口仍有效，则等待 5 秒继续。
5. nil、malformed RET 或单次 timeout 不覆盖当前连接状态；若窗口仍有效，则等待 5 秒继续。
6. 到达 65 秒时停止创建新 GET，结果进入 unknown/failure UI，但不重发 `0x0D`。
7. 每个 `0x0E` 使用独立 3 秒 deadline，repeating timer 改为 completion-driven one-shot。

自动加载或手动 refresh 中收到 `.requestFormatError` 时同样保持页面原状态，不把 connected 改成 failed，也不清除已知凭据。

## 9. RSSI 与 Internet UI

`WiFiGatewayViewController` 对新的组合 typed model 做两步映射：

1. RSSI result 决定强度图标：
   - valid 保留 Excellent/Good/Poor/Bad 阈值。
   - unavailable、readFailed、reserved 使用 No Signal 图标。
2. Internet status 决定状态文案：
   - normal：RSSI valid 时显示强度文案，RSSI invalid 时显示 No Signal。
   - unavailable：始终显示 No Internet，但保留第 1 步得到的图标。
   - unknown/reserved：始终显示 Unknown，但保留第 1 步得到的图标。

单次 `0x0F` 使用 4 秒 deadline。下一轮仍在本次 completion 后等待 5 秒；不改为历史静态脚本要求的 10 秒。

## 10. OTA 页面恢复

### 10.1 初始加载顺序

`WiFiFirmwareDFUCoordinator.beginInitialLoad()` 调整为：

1. 标记 coordinator active 并恢复 session。
2. 立即注册全局 message observer 和 connection observer。
3. 立即发出权威 `0x11`。
4. 根据权威结果决定当前 session、Cancel 能力和后续 `0x14`。

`WiFiFirmwareUpdateViewController.loadFirmwareData()` 可同时发起云端固件请求，但云请求完成与否不参与 `0x11` 的触发条件。现有“云请求与 current version 都完成后才 refresh OTA status”的 gate 必须删除或改为只控制页面非 OTA 数据的 loading，不得再控制状态恢复。

### 10.2 `0x14` 调度

- 权威 `0x11` 返回 `IDLE`、普通 `PREPARING` 或保留终态时，可以查询 `0x14`。
- 权威状态为 `DOWNLOADING/VERIFYING/VERIFY_OK/REBOOTING/RECOVERING/VERSION_CHECK` 时暂缓 `0x14`。
- 无完整合法权威状态时保持 communication unknown，不发送可能掩盖真实 OTA 恢复问题的 `0x14`。
- 中间态结束后再根据首个合法终态触发 `0x14`，成功终态可继续使用状态中的 module version 更新当前版本。
- `0x14` 单次 deadline 改为 7 秒。

### 10.3 `0x10` deadline

`0x10` 单次等待由 10 秒改为 3 秒。3 秒内没有完整合法匹配 RET 时，继续复用现有“检查已收到匹配 EVENT，否则只查询一次 `0x11`”恢复，不增加重发。

## 11. `0x15` transaction gate

新增 `WiFiFirmwareDFUTransactionGate.swift`，独立于 Cancel reducer 保存 transport 生命周期。

### 11.1 两类状态必须分离

- Cancel business state：是否已经由 RET/EVENT/恢复查询知道取消或原 OTA 的业务结果。
- Cancel transport state：原 `0x15` Mesh handle 是否已 callback 或达到 7 秒 deadline。

匹配终态可以结束第一类状态，但绝不能结束第二类状态。

### 11.2 gate 生命周期

1. 提交 `0x15` 前创建 gate，记录提交时刻与 7 秒 deadline。
2. gate active 时：
   - `start()` 必须拒绝创建 `0x10`。
   - Upgrade/Retry 按钮必须 disabled。
   - terminal RET/EVENT 只能更新业务结果，不能 release gate。
3. 原 `0x15` callback 到达时 release gate；callback 内容仍交给 Cancel reducer 处理。
4. callback 没有到达时，transaction deadline 到达后 release transport gate，再按业务状态判断是否继续 block start。
5. gate deadline 持久化在 `WiFiFirmwareDFUSession`，采用 optional 字段向后兼容旧 session JSON。
6. 离页重进或新 coordinator 恢复时，未来 deadline 继续保守阻止；过期 deadline 视为旧 transaction 已结束。
7. 当前 coordinator 收到早期 callback 时立即清除持久化 gate；旧 coordinator 已销毁时，新页面最多保守等待到原 deadline。

最终 `canStart` 必须同时满足：

- 没有 start request/pending start。
- cancel transport gate 已结束。
- Cancel reducer 没有 pending/recovering/unknown block。
- 当前 session 允许开始新一轮 OTA。

Coordinator 通过单一事件把 `canStart` 提供给 `WiFiFirmwareUpdateViewController`，按钮 enablement 和 `start()` 内部 guard 使用同一真值。

### 11.3 `0x15 04`

`.busy` 不再与 `.invalidParameters` 一起进入 resolved/continueOriginalOTA。

- 本 App 发出的新 `0x15` transaction callback 已结束，因此对应 transport gate 可以按 callback 规则释放。
- `.busy` 只说明另一个或既有 Cancel transaction 仍 pending，不能断言原 OTA 继续。
- Cancel reducer 进入 recovering，并发出一次 `0x11` 权威恢复 action。
- 后续 matched terminal、matched intermediate、IDLE、identity mismatch 和无有效结果继续使用现有最多 3 次恢复/unknown 规则。

## 12. 文件改动边界

### 12.1 NordicSigMeshSDK

新增：

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayV19TextValidator.swift`

修改：

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStart.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift`
- `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`
- 相关 V1.9 standalone contract，仅在现有 contract 无法覆盖共享 validator 时扩展。

### 12.2 SunSmart App

新增：

- `SunSmart/Main/Device/Gateway/Model/WiFiGatewayV19Timing.swift`
- `SunSmart/Main/Device/Gateway/Model/WiFiGatewayCredentialMutationReducer.swift`
- `SunSmart/Main/Device/Gateway/Model/WiFiGatewayConnectionPollingReducer.swift`
- `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUTransactionGate.swift`
- `Tests/Device/WiFiGatewayCredentialMutationReducerTests.swift`
- `Tests/Device/WiFiGatewayConnectionPollingReducerTests.swift`
- `Tests/Firmware/WiFiFirmwareDFUTransactionGateTests.swift`

修改：

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/Main/Device/Gateway/View/GatewayNetworkConnectivityCell.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- `SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift`
- `Tests/Firmware/WiFiFirmwareDFUCancelReducerTests.swift`
- `Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`，仅补恢复顺序相关 policy 覆盖，不改变既有状态单调性契约。
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `scripts/check_wifi_gateway_network_connectivity.sh`
- `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
- `scripts/check_wifi_gateway_wifi_status_header.sh`
- `scripts/check_wifi_gateway_firmware_update.sh`
- `SunSmart.xcodeproj/project.pbxproj`

新 App Swift 文件必须加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target 的 Sources phase。

## 13. 测试设计

### 13.1 SDK focused tests

必须覆盖：

- 协议 12.1 的中文 SSID/password 精确编码与回读。
- 32-byte SSID 成功，33-byte 失败。
- 8/63-byte password 成功，1...7 与 64 bytes 失败，零长度开放网络成功。
- `"`、`,`、`\` 在凭据中成功；C0/C1 Unicode controls 失败。
- canonical-equivalent 但 raw UTF-8 bytes 不同的凭据不视为逐字节相同。
- `0x0D/0x12/0x13` 的 `0x02` 映射为 `.unconfirmed`。
- `0x0E 06` 映射为 `.requestFormatError`。
- `0x0F` 所有 RSSI/Internet 组合、边界值和 unknown raw values。
- `0x0F` 拒绝 4-byte、RSSI valid+0、RSSI invalid+非零、short 和 trailing payload。
- `0x11/0x14` 对 `"`、`,`、`\` 使用同一拒绝规则。
- 现有 `0x10` request 对合法/非法 firmware ID 的行为不回归。

### 13.2 App Wi-Fi reducer tests

必须覆盖：

- `0x0D` accepted、invalid、unconfirmed、timeout、malformed、reserved。
- 恢复查询 target reached、not reached、not configured、unknown。
- 任意输入序列中 `0x0D` 发送次数为 1、`0x12` 最多为 1。
- `0x13` 成功前不清空字段。
- clear recovery 的 reached/not reached/unknown 三态。
- 每个 Subcode deadline 的精确值。
- `0x0E` 首次立即、5 秒 one-shot、65 秒边界。
- `0x0E 06`、nil、timeout 保持连接状态。
- terminal connection result 停止后续 timer。
- 新 `0x0F` typed model 到 header 图标/文案的组合映射。

### 13.3 OTA tests

必须覆盖：

- 初始激活时 observer 注册先于首个状态处理，权威 `0x11` 不依赖云 completion。
- 活动 OTA 阶段不抢先发送 `0x14`。
- `IDLE`、允许状态或终态后才恢复 `0x14`。
- `0x10` 使用 3 秒 deadline，并保持既有一次性 `0x11` 恢复。
- `0x15` terminal EVENT 先于 RET 时，业务完成但 transport gate 仍 active。
- `0x15` RET、nil callback、7 秒 deadline、离页重进和 App 重启恢复。
- transport gate 与 Cancel business block 必须全部解除后才能发送新 `0x10`。
- `0x15 04` 进入 recovery query，不显示“取消未生效”确定结论。

### 13.4 静态 contract

- `check_wifi_gateway_wifi_status_header.sh` 改为要求 5 秒 completion-to-next-start 和 4 秒单次 `0x0F` deadline。
- network/clear scripts 编译并运行新增的纯 Swift reducer tests。
- firmware script 编译 transaction gate tests，并检查 `start()` 与按钮都读取相同 gate 真值。
- 静态脚本不能只按符号存在判定恢复正确；核心多分支必须由 standalone reducer tests 验证。

## 14. 实施顺序

### 阶段 1：SDK wire truth

先写失败测试，再实现 credential validator、typed enum、严格 `0x0F` 和共享 identifier validator。阶段结束时 SDK focused tests 与 standalone protocol contracts必须通过。

### 阶段 2：App timing 与 RSSI

先建立统一 deadline 和 reducer test scaffolding，再接入 request helper 与新的 `0x0F` typed model。同步把 RSSI 静态契约改为 5 秒 poll delay、4 秒 request deadline。

### 阶段 3：凭据恢复与连接轮询

先完成 mutation/polling reducer RED/GREEN，再替换 controller callback 和 repeating timer。确保不确定结果只触发一个 `0x12`，本地字段只在结果明确后改变。

### 阶段 4：OTA 恢复与 transaction gate

先完成 gate 与 Cancel reducer tests，再调整 coordinator 初始顺序、`0x10/0x14` deadline、`0x15 04` 和 UI start availability。

### 阶段 5：集成收尾

运行所有 focused contracts、SDK 验证、四 target iPhoneOS build、`git diff --check`，并记录真机故障注入清单。

每一阶段形成独立、可审查的提交。实现时默认在当前会话采用 Inline Execution，不使用 subagent-driven execution。

## 15. 验证标准

### 15.1 自动验证

1. SDK `WiFiGatewayVendorMessageTests` 及相关 V1.9 tests。
2. App Device/Firmware standalone reducer tests。
3. `scripts/check_wifi_gateway_network_connectivity.sh`。
4. `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`。
5. `scripts/check_wifi_gateway_wifi_status_header.sh`。
6. `scripts/check_wifi_gateway_firmware_update.sh`。
7. `git diff --check`。
8. NordicSigMeshDemo Debug generic iPhoneOS build。
9. 以下四个 App Debug generic iPhoneOS build：
   - `SunSmart`
   - `Archipelago`
   - `SLG Sync Plus`
   - `SylSmart`

所有 iOS 构建直接使用 `xcodebuild`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'` 和 `CODE_SIGNING_ALLOWED=NO`。不使用 Simulator、shell 包装或日志重定向。

若 SDK 的 macOS `swift test` 仍被仓库既有 UIKit 依赖阻塞，应保留原始错误，并继续执行 SDK standalone contracts、NordicSigMeshDemo iPhoneOS build 和四个 App target build；不能把环境阻塞表述为测试通过。

### 15.2 真机联合验证

自动验证后仍需真机/固件覆盖：

- 协议 12.1 中文凭据、32-byte SSID 和开放网络。
- `0x0D/0x13` 丢 RET、迟到 RET、malformed RET 与 `0x12` 恢复。
- RSSI 查询失败但 Internet normal/unavailable/unknown 的组合。
- `0x0E` 长时间 connecting、`0x06` 和 65 秒窗口。
- OTA 页面打开、Proxy 重连、后台恢复和云请求延迟/失败。
- Cancel EVENT 先于 RET、RET 先于 EVENT、无 RET、离页重进和 App 重启。
- 原 `0x15` handle 结束前快速点击 Retry/Upgrade，确认不会发送新 `0x10`。

## 16. 完成条件

满足以下全部条件才可认为本轮开发完成：

- 用户列出的 6 个 P0 与 5 个 P1 条目均有对应实现和自动化证据。
- `0x0F` 不再接受 4-byte legacy RET。
- 所有 V1.9 Subcode 使用精确 deadline。
- `0x0D/0x13` 不确定结果只执行一次 `0x12`，且不存在 SET 自动重发路径。
- `0x0E 06` 不覆盖当前连接状态。
- 云请求不再阻塞权威 `0x11`。
- Cancel 业务终态不能提前释放 `0x15` transport gate。
- 四个 App target 与 NordicSigMeshDemo 的 generic iPhoneOS build通过。
- 没有新增 Auth 信息、无无关重构、无大范围格式化。
- 最终实现总结明确区分自动验证通过项与仍待真机验证项。
