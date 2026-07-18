# WiFi Gateway OTA 状态 `0x43/0x11` V1.9 设计

## 1. 目标

将 WiFi Gateway OTA 状态协议从现有短状态升级到 V1.9：支持带 `ota_id` 的完整 RET、独立 EVENT、严格字段组合、阶段和进度单向归并、首终态锁定、按协议节奏补充查询，以及断连后的权威 GET 恢复。

本轮仅实现 `0x43/0x11`。不编码、不发送、不模拟 `0x43/0x15`，下载和更新阶段现有 `CANCEL` 按钮继续保持禁用。

## 2. 已确认的产品边界

- 采用方案 A：合法匹配的 `CANCELLED` 显示独立的 `Upgrade cancelled` 状态，底部使用 `UPGRADE AGAIN`。
- 不实现 `Failed to cancel` 或 `CANCEL AGAIN`。两者没有 `0x43/0x11` 协议真值和可执行命令，待完整 `0x43/0x15` 协议提供后单独规划。
- Figma `Upgrade cancelled` 节点为 `332:6041`，沿用现有 WiFi OTA 进度组件、失败/提示图标和颜色。
- Figma `Failed to cancel` 节点 `332:6053` 仅作为未来取消协议设计输入，不进入本轮代码。
- 共享 BLE/Mesh OTA 页面、其它 Gateway 流程和 WiFi DFU `0x43/0x10` metadata 规则保持不变。

## 3. 当前实现与 V1.9 差距

- SDK 当前成功 RET 不含 `ota_id`，最短长度为 8 字节；V1.9 最短完整状态为 16 字节。
- 当前主动状态仍被当作普通 RET 解析，没有独立 EVENT 语义。
- 当前阶段缺少 `CANCELLED`、`PREPARING`，错误码缺少 `METADATA`，并错误保留了 V1.9 已删除的 `0x0F triggerBusyTimeout` 语义。
- 当前 App 固定每 2 秒轮询，GET timeout 为 5 秒。
- 当前 observer 在任一请求在途时丢弃主动状态，可能丢失 `0x43/0x10` ACK 前后到达的 EVENT。
- 当前 App 只按 `firmware_id` 关联会话，没有 `ota_id` 绑定、阶段倒退保护、下载进度下降保护或首终态归并器。
- 当前断连恢复可以直接重放缓存 UI，且 SDK 没有可并存的连接观察接口，无法满足重连后立即权威查询。

## 4. 架构

### 4.1 SDK 职责

SDK 负责协议编解码和完整合法性校验，不负责 OTA 会话、状态顺序、查询调度或 UI：

- RET 继续由 `SunricherVendorStatus` 解析。
- V1.9 EVENT 使用 Vendor Opcode `0xF50A78`。按当前 SDK 的三字节 Opcode 数值约定，对应现有 `SunricherReportMessage.opCode = 0xF5780A`。
- 不注册第二个相同 Opcode 的消息类型；扩展现有 `SunricherReportMessage`，使其同时支持旧 online/offline report 和 `43 11 00...` OTA EVENT。
- RET 和 EVENT 共用同一完整状态解析器，保证字段语义一致。
- SDK 只产出强类型结果，不推断 UI 成功或失败。

### 4.2 App 职责

App 使用 WiFi 专属 coordinator 和纯状态归并器管理：

- 本地 OTA 会话和持久化。
- 首状态身份绑定及后续 `ota_id + firmware_id` 双字段匹配。
- RET/EVENT 统一归并、阶段单向推进、下载进度单调、首终态锁定。
- GET 的 3 秒等待上限、10 秒补查、30 秒通信未知和未知后的 30 秒补查。
- 断连后冻结缓存判断，重连后以本次 GET 的合法 RET 为唯一恢复基准。
- 协议状态到现有 WiFi OTA UI 的映射。

## 5. SDK 协议模型

### 5.1 GET 与查询结果

GET 编码保持：

```text
43 11
```

RET 结果类型包括：

- `success(WiFiGatewayDFUStatus)`：`ret=0x00` 且完整状态合法。
- `invalidParameters`：`43 11 01`。
- `busy`：`43 11 02`。
- `reserved(rawValue:)`：未知 ret，且 payload 必须严格为 3 字节。

失败 RET 多出任何字段均视为非法消息。App 将 `busy`、GET 超时、非法 RET 或身份不匹配统一视为“本次查询无有效结果”，不直接判定 OTA 失败。

### 5.2 完整状态结构

成功 RET 和 EVENT payload 共用：

```text
43 11 00 <ota_id:U64_LE> <stage> <percent> <code>
         <firmware_id_len> <firmware_id>
         <module_version_len> <module_version>
```

固定字段偏移：

| 字段 | 偏移 |
| --- | ---: |
| `0x43` | 0 |
| `0x11` | 1 |
| `ret=0x00` | 2 |
| `ota_id` | 3...10 |
| `stage` | 11 |
| `percent` | 12 |
| `code` | 13 |
| `firmware_id_len` | 14 |
| `firmware_id` | 15 起 |
| `module_version_len` | firmware ID 后一字节 |
| `module_version` | version length 后 |

总长度必须精确等于 `16 + firmware_id_len + module_version_len`，不得接受尾随字节或截断字段。

### 5.3 字符串校验

- `firmware_id_len` 与 `module_version_len` 分别为 `0...32`；是否允许 0 由阶段字段组合决定。
- 字符采用当前 `0x43/0x10` 已使用的固件标识规则：可打印 ASCII，拒绝双引号、CR、LF 和不可打印/非 ASCII 字节。
- 长度为 0 在强类型模型中表示 `nil`，不创建空字符串。
- `SUCCESS` 比较实际版本与目标固件标识时，只允许两侧分别移除至多一个前导 `v` 或 `V`；比较仍不一致时，完整状态非法，不能伪装为成功。

### 5.4 阶段与进度

SDK 支持已知阶段 `IDLE`、`DOWNLOADING`、`VERIFYING`、`VERIFY_OK`、`VERIFY_FAIL`、`REBOOTING`、`RECOVERING`、`VERSION_CHECK`、`SUCCESS`、`TIMEOUT`、`FAILED`、`CANCELLED`、`PREPARING`。

未知阶段没有合法字段组合，整条状态拒绝解析。各阶段 percent 约束：

- `IDLE`、`PREPARING`：必须为 0。
- `DOWNLOADING`：必须为 `0...99`。
- `VERIFYING`、`VERIFY_OK`、`VERIFY_FAIL`、`REBOOTING`、`RECOVERING`、`VERSION_CHECK`、`SUCCESS`：必须为 100。
- `TIMEOUT`、`FAILED`、`CANCELLED`：保留最后已知进度，必须位于 `0...100`。

### 5.5 错误码

- 增加 `METADATA = 0x18`。
- `0x0F` 改为 reserved，不再暴露旧的 `triggerBusyTimeout` 语义。
- 已知错误码使用 V1.9 名称；未知错误码保留 raw value。
- 未知错误码仅能在符合 `FAILED` 非超时字段组合时作为失败终态进入 App；不能用于非终态、`SUCCESS`、`CANCELLED` 或 `TIMEOUT`。
- `TIMEOUT` 接受明确超时错误：`TRIGGER_TIMEOUT`、`OTA_TIMEOUT`、`VERSION_QUERY_TIMEOUT`、`RECOVERY_TIMEOUT`。

### 5.6 字段组合

SDK 严格执行：

| 阶段 | `ota_id` | `code` | firmware ID | module version |
| --- | --- | --- | --- | --- |
| `IDLE` | 0 | `NONE` | 空 | 空 |
| `PREPARING...VERSION_CHECK` 非终态 | 非零 | `NONE` | 1...32 | 空 |
| `SUCCESS` | 非零 | `NONE` | 1...32 | 1...32，且版本一致 |
| `VERIFY_FAIL` | 非零 | `VERIFY` | 1...32 | 空 |
| `TIMEOUT` | 非零 | 对应超时码 | 1...32 | 空 |
| `FAILED` | 非零 | 非超时失败码 | 1...32 | 仅 `VERSION_MISMATCH` 为 1...32，否则为空 |
| `CANCELLED` | 非零 | `NONE` | 1...32 | 空 |

`VERIFY_FAIL + VERIFY` 与 `FAILED + VERIFY` 均为合法失败终态。

## 6. EVENT 设计

`SunricherReportMessage` 先按 payload 前缀分流：

- `43 11 00...`：调用 OTA 完整状态解析器，产出 WiFi OTA status report data。
- 原有 `01 <online>`：继续产出 online/offline report data。
- 其它前缀或非法 OTA payload：解析失败。

EVENT 和 RET 得到同一个 `WiFiGatewayDFUStatus` 数据模型，但保留消息类型差异。EVENT 不属于 `SunricherVendorGet.responseType`，因此不能满足或结束当前 GET/SET Mesh 事务。

## 7. App 会话与状态归并

### 7.1 会话身份

本地 session 持久化：

- network UUID。
- node address。
- target firmware ID。
- 已绑定的 `ota_id`，首状态前为空。
- 最后合法进度状态。
- 首个终态及是否已由页面消费。
- 是否必须经过重连权威查询恢复。

`0x43/0x10 00` 建立本地 session 时 App 尚不知道 `ota_id`。首个完整、合法、source/network 正确且 firmware ID 匹配的非 IDLE 状态绑定非零 `ota_id`；绑定后所有状态必须同时匹配 `ota_id + firmware_id`。

`IDLE`、其它 firmware ID、其它 `ota_id` 或错误来源不能清除一个已接受且尚未结束的会话，只作为无效/不匹配状态忽略。只有明确开始新一轮升级、用户消费已知终态或业务确认当前会话不再有效时才替换/清理 session。

### 7.2 状态顺序

归并器使用正常阶段顺序：

```text
PREPARING -> DOWNLOADING -> VERIFYING -> VERIFY_OK
          -> REBOOTING -> RECOVERING -> VERSION_CHECK -> SUCCESS
```

- 中间阶段允许省略。
- 非终态倒退忽略。
- `DOWNLOADING` 进度下降忽略。
- 同阶段相同进度和字段的重复状态不重复更新 UI，也不算状态推进。
- 同阶段更高下载进度是合法推进。
- 终态不要求经过完整正常阶段链，但必须通过 SDK 字段组合校验并匹配当前会话。
- 首个合法终态立即持久化并锁定；同一轮后续任何 EVENT、RET 和缓存状态均忽略。

### 7.3 `CANCELLED` 边界

- SDK 始终可以解析字段合法的 `CANCELLED`。
- 页面进入、周期补查或通信重建后的权威 GET 返回完整、合法、匹配的 `CANCELLED` 时，可恢复为取消成功 UI。
- 当前 App 不创建 `0x43/0x15` 取消事务，因此实时 EVENT 中 `VERIFYING -> CANCELLED` 不依据本地猜测放行。
- 未来实现 `0x43/0x15` 时，再增加“匹配取消事务仍在途”的实时流转例外，不修改本轮 GET 恢复规则。

## 8. GET、EVENT 与时间调度

### 8.1 Start ACK 后查询

- coordinator 在页面可见期间持续接收目标 node EVENT，即使 SET/GET 正在等待响应。
- 收到 `0x43/0x10 00` 后，若本轮尚未收到匹配的首个合法 EVENT，立即发送一次 `0x43/0x11`。
- 若 ACK 前后已经收到匹配 EVENT，不追加 GET。
- EVENT 与请求在途状态分开管理，不再用一个全局 `requestInFlight` 阻断 EVENT。

### 8.2 GET 约束

- 单次 GET 等待上限严格为 3 秒。
- 同一时刻最多一个 `0x43/0x11` GET。
- `busy`、超时、非法 RET 或身份不匹配均不更新 OTA 状态，也不结束 OTA 会话。
- 合法但内容相同的 GET 证明通信有效，但不重复更新 UI。

### 8.3 非终态查询节奏

coordinator 分别维护状态推进时间与合法通信时间：

1. EVENT 带来新阶段或更高下载进度后，从该状态重新等待 10 秒。
2. 连续 10 秒没有新合法状态时查询一次。
3. GET 返回相同但合法的完整状态时，通信仍有效；下一次 GET 最早在本次完成 10 秒后。
4. 连续 30 秒没有任何完整、合法、匹配状态时进入通信未知。
5. 通信未知后每 30 秒查询一次。
6. 合法状态恢复时退出通信未知并重新进入正常 10 秒节奏；首终态形成时停止全部查询。

## 9. 断连恢复

SDK 增加与 `addGlobalMessageObserver` 同类的 Mesh 连接多观察者接口，避免 coordinator 替换 App 当前 `MeshLibManagerDelegate`：

- observer 接收有效 Mesh bearer open、close 和 proxy replacement 后的连接真值变化。
- 使用锁保护注册、移除和快照读取；回调沿用 manager delegate queue。
- coordinator deactivate/deinit 时移除 observer。

断连与重连规则：

1. 非终态会话断连后，标记必须经过权威 GET 恢复并取消普通 10 秒调度。
2. 缓存只保留身份和最后进度展示，不能据此判定成功、失败或取消，也不能触发取消命令。
3. Mesh 重连后立即发送一次 `0x43/0x11`。
4. 本次 GET 返回完整、合法、匹配状态前，不用 EVENT 或旧缓存继续推进状态。
5. GET 成功后以该 RET 作为恢复基准，并重新开放 EVENT 归并。
6. GET 无有效结果时保持通信未知，之后每 30 秒继续查询。

已经锁定并持久化的首终态不因后续 bearer 断连而回退。

## 10. UI 设计

### 10.1 协议到 UI 映射

| 协议状态 | UI | 进度 | 主按钮 |
| --- | --- | ---: | --- |
| `PREPARING` | `Downloading...` | 0 | `CANCEL` disabled |
| `DOWNLOADING` | `Downloading...` | 0...99 | `CANCEL` disabled |
| `VERIFYING...VERSION_CHECK` | `Updating...` | 100 | `CANCEL` disabled |
| `VERIFY_FAIL` 或下载类 `FAILED` | `Download failed` | 最后进度 | `UPGRADE AGAIN` |
| 其它 `FAILED`、`TIMEOUT`、未知错误 | `Upgrade failed` | 最后进度 | `UPGRADE AGAIN` |
| `SUCCESS` | `Upgrade complete!` | 100 | `DONE` |
| `CANCELLED` | `Upgrade cancelled` | 最后进度 | `UPGRADE AGAIN` |
| 非终态通信未知 | `Connection failed` + `Communication timeout` | 最后进度 | `CANCEL` disabled |

`0x43/0x10` 未被接受或发送失败仍属于“升级未开始”，继续按现有逻辑显示可用的 `UPGRADE AGAIN`，不与升级进行中的通信未知混用。

### 10.2 Figma 复用

`Upgrade cancelled` 沿用现有 `WiFiFirmwareUpdatingView`：

- 进度条和百分比使用最后合法进度。
- 状态图标复用现有 `alert_failed`。
- 文案颜色复用现有失败/提示色。
- 新增 English 与简体中文本地化 key，禁止硬编码。
- 不新增图片资源，不修改品牌 target 配置。

## 11. 文件影响面

### 11.1 本地 NordicSigMeshSDK

当前 App 工程已经通过 `XCLocalSwiftPackageReference` 指向 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`，本轮无需再次切换 package reference。

- 新建：`Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/WiFiGatewayDFUStatus.swift`
- 修改：`Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- 修改：`Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherReportMessage.swift`
- 修改：`Sources/NordicSigMeshSDK/MeshLib/Manager/MeshLibManager.swift`
- 修改：`Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

`SunricherVendorGet`、AccessLayer 和 VendorServerDelegate 现有注册结构足够，本轮不增加重复 Opcode 类型。

### 11.2 App worktree

- 新建：`SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift`
- 修改：`SunSmart/Main/Firmware/Model/WiFiFirmwareDFUState.swift`
- 修改：`SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- 修改：`SunSmart/Main/Firmware/View/WiFiFirmwareUpdatingView.swift`
- 修改：`SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- 修改：`SunSmart/en.lproj/Localizable.strings`
- 修改：`SunSmart/zh-Hans.lproj/Localizable.strings`
- 修改：`SunSmart.xcodeproj/project.pbxproj`
- 新建：`Tests/Firmware/WiFiFirmwareDFUStatusReducerTests.swift`
- 修改：`scripts/check_wifi_gateway_firmware_update.sh`

新增 App 源文件需加入 Common 共享 target，使 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 同步编译；本地化和 target membership 必须共同检查。

## 12. 测试设计

### 12.1 SDK parser

- U64 little-endian `ota_id`。
- RET/EVENT 产生相同状态对象。
- EVENT 不匹配、不结束 GET。
- `ret=0x01`、`0x02`、未知 ret 的严格长度。
- 全部阶段、percent 边界和字段组合。
- `PREPARING`、`CANCELLED`、`METADATA`、reserved `0x0F`。
- 未知错误码只在合法 `FAILED` 组合中保留并按失败处理。
- `SUCCESS` 的前导 `v/V` 归一化比较。
- 错误长度、尾随字节、非法字符、非法 percent、非法阶段/错误组合全部拒绝。
- 旧 online/offline EVENT 保持可解析。

### 12.2 App reducer/coordinator

- 首状态绑定身份，后续双字段匹配。
- 中间阶段省略、非终态倒退、下载进度下降和重复状态。
- `VERIFY_FAIL + VERIFY`、`FAILED + VERIFY`、未知错误与首终态锁定。
- 权威 GET 恢复 `CANCELLED`；无取消事务时不放行实时 `VERIFYING -> CANCELLED`。
- start ACK 前已收到匹配 EVENT 时不追加 GET。
- EVENT 不被在途请求过滤。
- 3 秒 GET timeout、busy 和非法 RET。
- 10 秒查询、30 秒通信未知、未知后每 30 秒查询和恢复。
- 断连缓存不能判定结果，重连 GET 成功前 EVENT 不推进。
- `Upgrade cancelled + UPGRADE AGAIN` 与通信未知禁用 `CANCEL`。
- 静态检查确保没有 `0x43/0x15` 编码、消息 case 或发送调用。

## 13. 构建与验收

按以下顺序收口：

1. SDK focused tests。若 macOS `swift test` 仍被既有 UIKit 导入限制阻塞，记录原始阻塞并继续进行 source contract 与 iPhoneOS 编译验证。
2. App 状态归并 focused test。
3. `scripts/check_wifi_gateway_firmware_update.sh`。
4. `git diff --check`。
5. `NordicSigMeshDemo` Debug generic iPhoneOS build，验证本地 SDK。
6. App Debug generic iPhoneOS builds：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。

所有 iOS 构建直接使用 `xcodebuild`、`-sdk iphoneos`、`-destination 'generic/platform=iOS'` 和 `CODE_SIGNING_ALLOWED=NO`，不使用 shell 包装、日志重定向或 Simulator。

## 14. 明确不做

- 不实现 `0x43/0x15`。
- 不开放当前禁用的 CANCEL。
- 不实现 `Failed to cancel` 或 `CANCEL AGAIN`。
- 不根据通信超时、查询失败或其它 OTA 阶段推断取消失败。
- 不修改 WiFi Gateway 以外的 OTA 产品逻辑。
- 不顺手重构共享 firmware 页面、Mesh manager 或 vendor protocol 基础层。

## 15. 验收标准

- SDK 只接受完整、合法的 V1.9 RET/EVENT，并保留明确的查询失败类型。
- EVENT 永远不会结束当前 GET/SET。
- App 只归并同一 network、node、`ota_id`、`firmware_id` 的状态。
- App 忽略倒退、下降进度、重复 UI 更新和首终态之后的状态。
- App 严格执行 3 秒、10 秒、30 秒查询节奏。
- 重连后只能以本次 GET 的完整合法 RET 恢复 OTA。
- 合法 `CANCELLED` 显示 `Upgrade cancelled + UPGRADE AGAIN`。
- 代码中不存在任何 `0x43/0x15` 实现。
- focused tests、contracts、SDK Demo 和四个 App iPhoneOS builds 完成并记录结果。
