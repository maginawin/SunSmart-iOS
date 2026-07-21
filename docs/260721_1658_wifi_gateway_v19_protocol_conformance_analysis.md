# WiFi Gateway V1.9 协议与当前 App 实现符合性分析

## 1. 结论摘要

结论：**当前 App/SDK 已覆盖 V1.9 定义的全部 9 个 Subcode，但整体只能判定为“部分符合”，不能判定为完整符合 V1.9。**

- 协议覆盖度：`0x0D`～`0x15` 中已定义的 9 个命令均存在 SDK 编解码入口，App 也均存在对应业务入口；`0x11` RET 与 V1.9 EVENT 都已接入。
- 符合度较高的部分：OTA Start 的 V1.9 payload、非零 `ota_id`、RET `ota_id` 匹配、OTA 完整状态字段校验、阶段/进度防倒退、首个终态锁定、10 秒兜底查询、30 秒通信未知查询，以及 Cancel 的单次发送、7 秒等待、最多 3 次恢复查询、30 秒未知态查询。
- 明确不符合的重点：
  1. Wi-Fi 凭据仍按旧规则限制为 `1~31` 字节、可打印 ASCII，并排除 `"`、`\`；V1.9 要求 SSID `1~32` UTF-8 字节、密码 UTF-8，并允许协议示例中的中文、逗号和双引号。
  2. `0x0D` 和 `0x13` 返回不确定结果或超时时，App 没有按 V1.9 只查询一次 `0x12` 恢复结果。
  3. `0x0F` 在 RSSI 不可用/失败时丢弃 `network_status`，没有按 V1.9 独立处理 RSSI 与 Internet 状态。
  4. 多个请求的 App 超时超过 V1.9 上限；`0x10` 当前等待 10 秒，而协议上限是 3 秒。
  5. Wi-Fi 连接结果当前约每 2 秒查询、最多 60 秒，与 V1.9 的每 5 秒、最多 65 秒不一致。
  6. OTA 页面首次加载/恢复时先查询 `0x14` 并等待云端固件请求完成，再启动 `0x11`，不符合通信重新建立后应优先重新查询 `0x11` 的要求。
  7. Cancel 等待期间若终态 EVENT 先于 `0x15` RET 到达，UI 可能在原 SIG Mesh 事务结束前允许下一轮 `0x10`，违反 V1.9 的事务隔离要求。
- 协议自身也有需要产品、固件和安全共同确认的设计问题：强制 HTTP、缺少固件签名/防回滚要求、允许读取明文 Wi-Fi 密码、宣称不兼容旧格式但没有版本协商、普通命令缺少业务事务 ID，以及多个状态码混合“忙/失败/结果未知”语义。

因此，建议把当前状态定义为：

> **命令入口已完整覆盖；OTA 核心状态机大体符合；Wi-Fi 配置/清除/RSSI 仍明显沿用旧协议语义；V1.9 尚未完成端到端符合性收口。**

## 2. 分析范围与当前快照

### 2.1 协议快照

- 文件：`/Users/maginawin/Desktop/Obsidian/Apps/SunSmart/_protocols/WiFi Gateway V1.9.md`
- 文件行数：576
- 修改时间：2026-07-20 20:12:13 +0800
- SHA-256：`3a193c83824c0ceed59f95824ded8fe1b9ebbdd51f0f3908832f9b35d32d2378`

### 2.2 App 与 SDK 快照

- App worktree：`wifi-gateway`
- App HEAD：`2855682ae514af0481ba7fc0dcb7d3fafc64b5f6`
- App 当前存在用户未提交改动，主要涉及 Wi-Fi OTA Cancel、页面初始请求顺序和相关 UI/测试。本报告按**当前 working tree**分析，不按 HEAD 基线分析。
- `SunSmart.xcodeproj` 当前通过本地 Swift Package 引用：`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`。
- SDK HEAD：`2e8400a feat: support wifi gateway ota cancel protocol`，SDK 工作区干净。

### 2.3 判定口径

- “已实现”：SDK 存在请求编码/响应解析，且 App 存在实际调用或业务入口。
- “符合”：不仅 payload 能编解码，还要求超时、串行、响应匹配、不确定结果恢复、状态推进、页面生命周期和用户操作限制均符合 V1.9。
- 本报告是源码与静态契约审计；没有连接真实 WiFi Gateway，也没有验证固件侧行为、Mesh 丢包/乱序、断电恢复和云端 OTA 下载。

## 3. 协议本身是否存在不合理之处

### 3.1 高风险问题

| 编号 | 问题 | 判断与影响 | 建议 |
| --- | --- | --- | --- |
| P-01 | OTA 强制使用 `http://`，但未定义固件真实性校验 | V1.9 明确拒绝 HTTPS，同时只提到从 URL 获取/校验 `size/sha256`。HTTP 下攻击者可以同时替换固件和元数据；普通哈希不能证明发布者身份。协议也没有定义签名、公钥、证书校验、anti-rollback 或允许升级版本范围。 | 至少支持 HTTPS 并明确证书校验；更稳妥的是使用签名 manifest/签名固件，在设备端使用固化公钥验证，同时定义防回滚策略。`sha256` 只能做完整性校验，不能替代签名。 |
| P-02 | `0x12` 可读取完整明文 Wi-Fi 密码 | SIG Mesh 加密只能保护链路，不能形成业务最小权限；持有相同网络/AppKey 且能访问该模型的客户端可能读取密码。协议未定义权限、用户确认、返回脱敏、日志红线或敏感数据生命周期。当前 App 还会把密码保存到普通 `UserDefaults`。 | 优先调整为只返回“已配置 + SSID”，不返回密码；如果业务必须回读密码，应定义独立授权、用户确认、审计和安全存储要求，并明确禁止协议日志记录明文。 |
| P-03 | 声明“不兼容旧格式”，但没有版本或 capability 协商 | V1.9 复用原 Subcode，却修改了 `0x0F` 长度、Wi-Fi 字符规则和 OTA 状态语义。App 无法在发送前可靠判断网关使用旧版还是 V1.9，只能对个别响应做猜测性兼容。 | 增加协议版本查询或 capability bitmap；至少在 Composition/Product/firmware version 与协议能力之间建立权威映射，并定义旧固件降级策略。 |

### 3.2 中风险问题

| 编号 | 问题 | 判断与影响 | 建议 |
| --- | --- | --- | --- |
| P-04 | 普通命令没有业务事务 ID，却要求识别迟到 RET | `0x0D/0x0E/0x0F/0x12/0x13/0x14` 的 RET 只能按 source、Vendor Opcode 和 Subcode 匹配。旧事务超时后如果很快发起同 Subcode 新事务，迟到 RET 在 payload 层无法和新事务区分。协议中的“迟到 RET 必须忽略”仅靠文字无法完全实现。 | 为这些命令增加 request ID/TID，并在 RET 回显；如果格式暂时不能改，必须定义同 Subcode 的最短静默窗口和底层 transaction/sequence 绑定规则。 |
| P-05 | 一个返回码混合多个性质不同的结果 | `0x0D 02`、`0x12 02`、`0x13 02` 同时承载 busy、内部失败、超时、读取失败和结果未确认。调用方无法直接区分“肯定未执行”和“可能已经生效”，容易产生错误 UI 和重试策略。 | 至少拆分 `BUSY`、`INTERNAL_ERROR`、`TIMEOUT`、`UNCONFIRMED`；如果必须保持 wire 兼容，增加 detail/status 字段。 |
| P-06 | OTA URL 校验规则过宽但协议能力过窄 | 规则只要求以 `http://` 开头并由可打印 ASCII 组成，因此仅有 `http://`、包含空格或其它非标准 URL 字符的字符串也可能通过参数校验；同时又完全禁止 HTTPS。 | 明确 URL 语法、host/path/query 和 percent-encoding 规则；要求合法 host，并改为 HTTPS。 |
| P-07 | OTA 终态保留生命周期没有定义完整 | 协议多次引用“保留终态”，但没有明确终态跨普通重启/掉电是否保留、保留多久、何时回到 `IDLE`、由哪条命令覆盖或清除。App 的重进页面恢复和取消未知态解除都依赖这些细节。 | 增加状态生命周期表，明确 RAM/持久化范围、重启行为、覆盖条件和 `IDLE` 恢复条件。 |

### 3.3 低风险歧义

| 编号 | 问题 | 判断与影响 | 建议 |
| --- | --- | --- | --- |
| P-08 | Vendor Opcode 书写没有同时给出 on-air 字节序 | 协议写作 `0xF00A78/0xF10A78/0xF30A78/0xF50A78`，当前 SDK 常量写作 `0xF0780A/0xF1780A/0xF3780A/0xF5780A`。二者在项目约定中表示同一个 opcode，不是当前实现 bug，但新实现者容易误判。 | 在公共定义中同时给出“文档逻辑写法”“SDK UInt32 写法”和“实际 Access PDU 字节”。 |
| P-09 | SSID 被限制为合法 UTF-8 | 802.11 SSID 本质上可以是字节序列；协议的 UTF-8 限制会排除部分合法网络。对面向普通用户的 App 这可能是可接受的产品约束，但应明确是产品能力限制。 | 明确是否只支持 UTF-8 SSID；如果要兼容所有网络，应按原始字节传输并另行定义 UI 展示策略。 |

## 4. 当前 App 已实现哪些协议

当前 9 个命令在 wire 层均已覆盖：

| Subcode | 协议功能 | SDK 实现 | App 业务入口 | 覆盖结论 |
| --- | --- | --- | --- | --- |
| `0x0D` | 下发 Wi-Fi 配置 | `WiFiGatewayCredentials` + `SunricherVendorSet.wifiGatewayCredentialsSet`；解析 `WiFiGatewayCredentialsSetResult` | Network Connectivity 的 Connect | 已实现 |
| `0x0E` | 查询 Wi-Fi 连接结果 | `SunricherVendorGet.wifiGatewayConnectionStatus`；解析 `WiFiGatewayConnectionStatus` | 配置后轮询、页面加载和手动刷新 | 已实现 |
| `0x0F` | 查询 RSSI 与 Internet 状态 | `SunricherVendorGet.wifiGatewayRSSIStatus`；解析 `WiFiGatewayRSSIStatus` | Wi-Fi 已连接时轮询并更新顶部图标/文案 | 已实现，但数据模型不足以表达 V1.9 的独立双状态 |
| `0x10` | 发起互联网接入模组 OTA | `WiFiGatewayDFUStartRequest/Response` | `WiFiFirmwareDFUCoordinator.start` | 已实现 |
| `0x11` | 查询/上报 OTA 状态 | `WiFiGatewayDFUStatus`、RET parser、`SunricherReportMessage` EVENT parser | OTA reducer、轮询、断连恢复、页面恢复 | 已实现 RET + EVENT |
| `0x12` | 读取 Wi-Fi 凭据 | `SunricherVendorGet.wifiGatewayCredentials`；解析 `WiFiGatewayCredentialsReadResult` | 页面自动加载、刷新 | 已实现 |
| `0x13` | 清除 Wi-Fi 凭据 | `SunricherVendorSet.wifiGatewayCredentialsClear`；解析 `WiFiGatewayCredentialsClearResult` | Disconnect | 已实现 |
| `0x14` | 查询互联网接入模组版本 | `SunricherVendorGet.wifiGatewayFirmwareVersion`；解析 `WiFiGatewayFirmwareVersionResult` | WiFi Firmware Update 的 Current version | 已实现 |
| `0x15` | 取消互联网接入模组 OTA | `WiFiGatewayDFUCancelRequest/Response` + response matcher | OTA 页面 Cancel、恢复查询和未知态 | 当前 working tree 已实现 |

主要证据入口：

- App 网络功能：`SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- App OTA 编排：`SunSmart/Main/Firmware/Controller/WiFiFirmwareDFUCoordinator.swift`
- App OTA 状态机：`SunSmart/Main/Firmware/Model/WiFiFirmwareDFUStatusReducer.swift`
- App Cancel 状态机：`SunSmart/Main/Firmware/Model/WiFiFirmwareDFUCancelReducer.swift`
- SDK Wi-Fi 公共解析：`Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- SDK OTA Start/Status/Cancel：`WiFiGatewayDFUStart.swift`、`WiFiGatewayDFUStatus.swift`、`WiFiGatewayDFUCancel.swift`
- SDK EVENT：`SunricherReportMessage.swift`

## 5. 当前功能逻辑与 V1.9 的逐项符合性

### 5.1 汇总矩阵

| Subcode | wire 编解码 | App 流程 | 总体判定 |
| --- | --- | --- | --- |
| `0x0D` | 部分符合 | 不符合不确定结果恢复与超时 | **部分符合** |
| `0x0E` | 基本符合 | 轮询节奏、总时长、`0x06` 处理不符合 | **部分符合** |
| `0x0F` | 部分符合 | 未独立处理 Internet 状态，超时偏短 | **部分符合** |
| `0x10` | payload 符合 | 10 秒等待超过 3 秒；恢复查询主体已实现 | **部分符合** |
| `0x11` | 主体符合 | 状态机主体符合，但首次/重连查询顺序不符合 | **大部分符合** |
| `0x12` | 部分符合 | 已用于加载，但未用于 `0x0D/0x13` 不确定结果恢复 | **部分符合** |
| `0x13` | wire 基本符合 | 不确定结果恢复缺失，且失败时过早清空本地字段 | **部分符合** |
| `0x14` | 部分符合 | 页面可查询，但初始排序与字符/等待规则有偏差 | **部分符合** |
| `0x15` | wire 符合 | 主体接近 V1.9，仍有事务结束竞态与 busy 语义问题 | **大部分符合** |

### 5.2 明确不符合项

#### C-01：Wi-Fi 凭据长度和字符规则仍是旧协议

严重度：**高**

协议要求：

- SSID 为 `1~32` UTF-8 字节；
- 密码为 `0` 或 `8~63` UTF-8 字节；
- 仅禁止 Unicode 控制字符；
- 示例明确包含中文密码、逗号和双引号。

当前实现：

- SDK 只接受 SSID `1~31` 字节；
- SDK 要求 SSID/密码全为 `0x20~0x7E`，且额外禁止 `"` 和 `\`；
- App 输入层再次禁止非 ASCII 密码；
- SDK 测试明确断言 32 字节 SSID必须失败、双引号/反斜杠必须失败。

影响：协议第 12.1 节的多语言示例无法由当前 App 构造；合法的 32 字节 SSID 也无法配置或读取。Unicode SSID 构造失败时，App 还会落入通用错误并提示 SSID 为空，错误原因失真。

证据：

- 协议：第 2.1、7.2、12.1 节。
- SDK：`SunricherVendorStatus.swift:984-1044`、`SunricherVendorStatus.swift:146-169`。
- App：`WiFiGatewayViewController.swift:787-820`、`GatewayNetworkConnectivityCell.swift:351-359`。
- 测试：`WiFiGatewayVendorMessageTests.swift:27-52`。

建议：先以 V1.9 示例补 RED tests，再把 SDK 改为 UTF-8 字节长度和 Unicode scalar 控制字符校验；App 的按钮 enablement 也必须按 UTF-8 字节数而不是 Swift 字符数计算。

#### C-02：`0x0D` 不确定结果没有执行一次 `0x12` 恢复查询

严重度：**高**

协议要求：`43 0D 02` 或没有有效 RET 时，只查询一次 `0x12`，不得自动重发 `0x0D`。

当前实现：`connectNetworkWithGateway` 只在结果为 `.accepted` 时进入 `0x0E` 轮询；`.internalError`、reserved、解析失败或 timeout 都直接展示失败，不查询 `0x12`。

影响：设备可能已经保存目标凭据，但 App 显示失败并保留为可再次连接状态；用户再次点击可能创建新的状态修改事务。

证据：`WiFiGatewayViewController.swift:848-868`。

建议：把 `0x0D` 结果分为“确认成功”“确认参数错误”“需恢复确认”；后者在原事务结束后只发送一次 `0x12`，逐字节比较 SSID/password，只用于确认目标是否已生效，不把原 `0x0D` 补记为成功。

#### C-03：`0x13` 不确定结果没有执行一次 `0x12`，且本地 UI 先行清空

严重度：**高**

协议要求：`43 13 02` 或没有有效 RET 时，在事务结束后只查询一次 `0x12`；`0x12 01` 表示清除目标已达到，`0x12 00` 表示未达到，其它表示未知。

当前实现：无论 clear 返回 `.cleared`、失败还是 nil，`completeNetworkDisconnectClear` 都立即清空本地 SSID/password；只有 `.cleared` 才把 header 设为 Not Configured，其余直接提示失败，不查询 `0x12`。

影响：设备仍可能保留并使用原凭据，而 App 已清空页面字段；也可能设备已清除成功但 RET 丢失，App 却只显示失败。

证据：`WiFiGatewayViewController.swift:929-955`。

建议：收到确认成功前不要不可逆地清空当前显示；对不确定结果执行一次 `0x12`，再按 reached/not reached/unknown 三态更新 UI。

#### C-04：`0x0F` 没有独立保留 `network_status`

严重度：**高**

协议要求：`rssi_status` 与 `network_status` 独立；即使 `rssi_status=0x01/0x02`，App 仍要按 `network_status` 处理 Internet 状态。

当前实现：

- SDK 只在 `rssi_status=0x00` 时把 `network_status` 放进 typed model；`.unavailable/.readFailed` 不携带 Internet 状态。
- App 对 `.unavailable/.readFailed` 固定显示 No Signal，无法同时表达 Internet normal/unavailable/unknown。
- SDK 接受 V1.9 明确禁止的 `rssi=0` 作为有效 RSSI。
- SDK 在失败状态时没有验证 `rssi` 必须固定为 0。
- SDK 仍接受旧 4-byte response。兼容旧固件本身可以保留，但必须由版本/capability 策略明确，而不是和 V1.9 混为同一格式。

证据：

- 协议：第 4.2 节。
- SDK：`SunricherVendorStatus.swift:58-77`。
- App：`WiFiGatewayViewController.swift:1057-1097`。
- SDK 测试：`WiFiGatewayVendorMessageTests.swift:115-180`，当前测试明确把 `rssi=0` 视为有效。

建议：把 typed model 改成同时包含 `rssiResult` 与 `networkStatus` 的组合结构；V1.9 始终解析精确 5 字节并独立映射两者，旧 4 字节兼容放到明确的 legacy 分支。

#### C-05：请求等待上限没有统一按 V1.9 执行

严重度：**高**

协议规定：`0x0D=7s`、`0x0E=3s`、`0x0F=4s`、`0x10=3s`、`0x11=3s`、`0x12=7s`、`0x13=7s`、`0x14=7s`、`0x15=7s`；达到上限后的 RET 必须忽略。

当前实现：

- 网络页通用 GET、`0x0D`、`0x13` 默认使用 10 秒；因此会接受 V1.9 已定义为迟到的 7～10 秒 RET，`0x0E` 更可能接受 3～10 秒迟到 RET。
- OTA `0x10` 使用 10 秒，而协议上限是 3 秒；V1.9 要求 3 秒后进入一次 `0x11` 恢复确认，当前恢复最晚要等 10 秒才开始。
- OTA `0x11=3s`、`0x15=7s` 已对齐。
- `0x14` 当前使用 5 秒，虽然没有超过 7 秒上限，但会比协议窗口更早判失败。
- `0x0F` 当前使用 2 秒，虽然没有超过 4 秒上限，但会牺牲合法慢响应的成功率。

证据：

- `WiFiGatewayViewController.swift:458-529`、`WiFiGatewayViewController.swift:1031-1035`。
- `WiFiFirmwareDFUCoordinator.swift:219-223`、`WiFiFirmwareDFUCoordinator.swift:984-988`。
- `WiFiFirmwareDFUStatusReducer.swift:80-85`、`WiFiFirmwareDFUCancelReducer.swift:72-77`。

建议：建立单一 V1.9 deadline 表，由所有 sender 复用；业务恢复必须在对应 transaction callback/timeout 后开始，并让 generation/handle 保证迟到 RET 不更新状态。

#### C-06：`0x0E` 配置后轮询节奏不符合协议

严重度：**中高**

协议要求：`0x0D 00` 后立即查询一次 `0x0E`，得到 `00` 后等待 5 秒再查询，总等待不超过 65 秒。

当前实现：立即查询符合；后续使用 2 秒 repeating timer，并在 60 秒结束。

影响：请求明显更密集，增加 Mesh 拥塞/忙响应概率，同时比协议提前 5 秒宣告失败。

证据：`WiFiGatewayViewController.swift:66-69`、`WiFiGatewayViewController.swift:871-926`。

建议：改为 completion-driven one-shot：首次立即；`00` 后等 5 秒；以初次 `0x0E` 提交时间或 `0x0D 00` 后的明确定义起点计算 65 秒总窗口。

#### C-07：`0x0E 06` 与通用 success 标记语义不正确

严重度：**中**

- 协议要求 `0x06` 只表示本次查询格式错误，不改变当前连接状态。SDK 当前把它归为 reserved，App 会按连接失败处理并改变 UI。
- `SunricherVendorStatus` 通用逻辑把 payload 第 3 字节非零都标记为 `isSuccessful=false`。因此合法的 `43 0E 01`（已连接）也被 wrapper 标为失败，尽管 typed parameter 正确解析为 `.connected`。当前 App 没有读取 `isSuccessful`，所以主页面未直接受影响，但日志、调试工具或其它调用方可能误判。

证据：`SunricherVendorStatus.swift:182-225`、`SunricherVendorStatus.swift:1087-1110`、`WiFiGatewayVendorMessageTests.swift:102-113`。

建议：为 `0x0E 06` 增加独立 typed case，并在 App 层保持原状态；不要把状态型字段统一当作 ret success/failure。可把“消息是否合法”和“业务状态”拆成两个属性。

#### C-08：`0x11/0x14` 文本字符校验少排除了逗号和反斜杠

严重度：**中**

协议要求 OTA `firmware_id`、状态里的 firmware ID/module version、以及 `0x14` version 都禁止 `"`、`,`、`\`。

当前实现：

- `0x10` request builder正确排除了三者；
- `0x11` status parser只排除 `"`；
- `0x14` version parser只要求可打印 ASCII，没有排除三者。

影响：App 可能接受 V1.9 定义为非法的 RET/EVENT，并更新 OTA 或当前版本状态。

证据：`WiFiGatewayDFUStart.swift:89-100`、`WiFiGatewayDFUStatus.swift:182-184`、`SunricherVendorStatus.swift:116-143`。

建议：复用同一套公开/内部 ASCII identifier validator，避免 request 和 response 规则漂移。

#### C-09：OTA 页面首次/重连状态查询顺序不符合 V1.9

严重度：**高**

协议要求：通信重新建立后必须重新发送 `0x11`，只依据本次完整合法状态继续；活动 OTA 阶段查询 `0x14` 还可能返回 busy。

当前实现：

1. 页面初始加载同时启动云端固件请求与 `0x14` 当前版本查询；
2. 等二者都结束后才调用 `refreshOTAStatus()`；
3. `refreshOTAStatus()` 才注册 OTA EVENT observer 并查询 `0x11`。

影响：

- 恢复中的 `0x11` 被云请求和 `0x14` 延迟；
- observer 注册前到达的 EVENT 会丢失；
- 活动 OTA 中先发 `0x14` 可能得到预期 busy，却让 Current version UI 先显示 Failed；
- 如果云请求迟迟不 completion，状态恢复也被阻塞。

证据：`WiFiFirmwareUpdateViewController.swift:139-157`、`WiFiFirmwareUpdateViewController.swift:277-286`、`WiFiFirmwareDFUCoordinator.swift:86-106`、`WiFiFirmwareDFUCoordinator.swift:129-170`。

建议：页面激活后先注册 observer；有恢复 session 或刚发生重新连接时立即执行权威 `0x11`。云端固件请求可以并行，但不能阻塞状态恢复；`0x14` 应在确认没有使其 busy 的 OTA 阶段后发送。

#### C-10：Cancel 终态 EVENT 可能在 `0x15` SIG Mesh 事务结束前开放下一轮 OTA

严重度：**高**

协议明确：终态 RET/EVENT 可以结束取消的业务结果等待，但不结束原 `0x15` SIG Mesh 事务；原事务收到匹配 RET 或由事务层结束前，不得创建新 OTA 事务。

当前实现：

- `cancelRequestInFlight` 会持续到 `0x15` callback；
- 但 `start()` 没有检查 `cancelRequestInFlight`；
- 若 `CANCELLED` 或其它终态 EVENT 先到，页面会进入 terminal UI，Retry/Upgrade 可能启用，用户可以在旧 `0x15` handle 仍 pending 时触发新 `0x10`。

证据：`WiFiFirmwareDFUCoordinator.swift:172-180`、`WiFiFirmwareDFUCoordinator.swift:238-275`、`WiFiFirmwareDFUCoordinator.swift:597-617`、`WiFiFirmwareUpdateViewController.swift:288-306`。

建议：把“业务终态已确定”和“Mesh cancel transaction 已结束”拆成两个 gate；`start()` 及按钮 enablement 都必须等待后者完成。

#### C-11：`0x15 04` 的业务解释过早收敛

严重度：**中**

协议定义 `0x04` 只结束触发 busy 的新取消事务，不改变原 pending 取消事务。当前 Cancel reducer 把 `.busy` 与参数错误一样直接标记 resolved，并显示取消未生效、继续原 OTA。

影响：当另一个控制端或恢复中的取消事务仍在处理时，当前 App 过早断言原 OTA 继续；后续虽然仍可能通过普通状态查询纠正，但这不是 V1.9 规定的 pending/unknown 语义。

证据：`WiFiFirmwareDFUCancelReducer.swift:134-141`。

建议：`0x04` 应进入“外部/既有 cancel transaction 待确认”恢复分支，至少查询 `0x11`，不要直接判定取消未生效。

#### C-12：当前 RSSI 轮询代码与项目既有静态契约不一致

严重度：**中；属于项目内部回归，不是 V1.9 明文要求**

- 当前代码 `wifiRSSIStatusPollDelay = 5`。
- 项目脚本要求 completion 后等待 10 秒。
- 实际运行 `scripts/check_wifi_gateway_wifi_status_header.sh` 失败：`The next Wi-Fi RSSI query must wait 10 seconds after completion.`

证据：`WiFiGatewayViewController.swift:67`、`scripts/check_wifi_gateway_wifi_status_header.sh:48-58`。

建议：先确认 5 秒还是 10 秒为产品最终要求；当前源码、历史设计和静态 guard 至少必须统一。该间隔不要与 V1.9 的“单次 `0x0F` 最长等待 4 秒”混为同一个参数。

#### C-13：App 将 Wi-Fi 密码明文缓存在 UserDefaults

严重度：**高（安全）**

当前 `saveCachedPassword` 以 SSID 为 key，把密码写入普通 `UserDefaults`；项目静态脚本甚至把该行为作为必需契约。

证据：`WiFiGatewayViewController.swift:764-776`、`scripts/check_wifi_gateway_network_connectivity.sh:26`。

建议：这是产品/安全策略变更，不能作为顺手代码修复。建议停止持久化明文密码，或迁移到 Keychain 并定义访问控制、清理时机和日志红线；同步更新静态契约。

## 6. 已符合或基本符合的关键逻辑

为避免只列问题，以下 V1.9 核心点当前已经正确实现：

1. **请求与响应命令隔离**：SDK response matcher 会按 source、response opcode 和具体 Subcode 匹配；`0x10/0x15` 还会额外匹配 `ota_id`。
2. **`0x10` payload**：使用 U64 little-endian `ota_id`、U16 little-endian URL 长度、URL、1-byte firmware ID 长度和 firmware ID；不再发送 `size/sha256`；总长度边界有测试。
3. **新轮次标识**：每次用户启动 OTA 时生成非零随机 `UInt64`，并把 session 持久化到 network UUID + node address 维度。
4. **Start 丢 RET 恢复**：没有有效 `0x10` RET 时，先检查已收到的匹配 EVENT，再只查询一次 `0x11`；不会自动重发 `0x10`。
5. **`0x11` 完整状态解析**：长度、stage、percent、code、firmware ID、module version 和组合约束都做了强校验；`SUCCESS` 还会比较去掉一个前导 `v/V` 后的版本。
6. **状态关联**：App 只接受匹配 target firmware ID 和 bound OTA ID 的状态；`IDLE` 不作为当前轮次结果。
7. **状态单调性**：App 拒绝阶段倒退、下载进度下降、重复状态和终态之后的新状态，并以首个合法终态锁定结果。
8. **成功判定**：只有 `SUCCESS` 映射为升级完成；`percent=100` 本身不会被当作成功。
9. **EVENT 与事务分离**：V1.9 EVENT 使用独立 `SunricherReportMessage`，不能满足 `SunricherVendorGet` 的 response handle；RET 与 EVENT 共用 OTA 状态 parser。
10. **OTA 查询节奏**：`0x11` 单次 3 秒，非终态 10 秒无新状态后兜底查询，30 秒无有效状态进入 communication unknown，此后每 30 秒查询。
11. **重连权威状态门槛**：session 会设置 `requiresAuthoritativeQuery`，断连前缓存不会直接用于允许 Cancel；问题在于页面初始请求顺序延迟了该查询，而不是缺少该机制。
12. **Cancel 主体**：仅 PREPARING/DOWNLOADING 可触发；只发送一次；7 秒等待；无 RET 时最多 3 次 `0x11`；未知后每 30 秒查询；未知期间持久化并阻止新的 start；`VERIFYING` 竞态和 `CANCELLED` 终态均有专门处理。

## 7. 推荐整改优先级

### P0：先修会产生错误状态或安全风险的问题

1. 对齐 V1.9 Wi-Fi 凭据 UTF-8/32-byte 规则，并用协议 12.1 示例做 SDK/App 端到端测试。
2. 为 `0x0D`、`0x13` 增加一次性 `0x12` 不确定结果恢复，不自动重发 SET。
3. 重构 `0x0F` typed model，始终独立保留 RSSI result 和 Internet status。
4. 对齐所有 V1.9 timeout，尤其把 `0x10` 从 10 秒改为 3 秒，把通用 Wi-Fi GET/SET 拆成按 Subcode 的 deadline。
5. OTA 页面恢复时优先注册 observer 并查询 `0x11`；云请求不能阻塞恢复。
6. 用独立 transaction gate 阻止 `0x15` handle 结束前创建新 `0x10`。
7. 对 HTTP OTA 与明文 Wi-Fi 密码回读/缓存做产品级安全决策。

### P1：收紧语义和边界

1. 对齐 `0x0E` 的 5 秒轮询、65 秒总窗口，并为 `0x06` 保持原连接状态。
2. 修正 `0x11/0x14` 的字符校验，复用同一 identifier validator。
3. 把 `0x0D 02`、`0x12 02`、`0x13 02` 的 typed enum 命名改成“unconfirmed/busy-or-failed”类语义，避免 App 把不确定误写成确定失败。
4. 修正 `0x15 04` 的恢复语义。
5. 统一 RSSI 轮询源码和 10 秒静态契约。

### P2：协议下一版改进

1. 增加协议版本/capability 协商。
2. 为普通命令增加业务 transaction ID。
3. 拆分 overloaded result code。
4. 明确 OTA 终态持久化/清除生命周期。
5. 明确 on-air opcode 字节序和 URL grammar。

## 8. 建议新增的验证用例

### 8.1 SDK

- 32-byte SSID 成功；33-byte 失败。
- 协议 12.1 的中文 SSID/密码按 UTF-8 原始字节精确编码并可回读。
- 凭据中的 `"`、`,`、`\` 按 V1.9 接受，Unicode 控制字符拒绝。
- `0x0F` 在 RSSI unavailable/read failed 时仍保留 `network_status`。
- `rssi_status=0x00` 且 `rssi=0` 必须拒绝；失败状态且 `rssi!=0` 必须拒绝。
- `0x0E 06` 解析为独立格式错误，而不是普通连接失败。
- `0x11/0x14` 拒绝含 `"`、`,`、`\` 的 identifier/version。
- 每个命令的 trailing bytes、短包、未知状态和 response matching。

### 8.2 App 状态机

- `0x0D 02`、timeout、malformed RET 都只触发一次 `0x12`，不会重发 `0x0D`。
- `0x13 02`、timeout 都只触发一次 `0x12`，并覆盖 reached/not reached/unknown 三种 UI 结果。
- `0x0E` 首次立即、之后 5 秒、总窗口 65 秒。
- 各 Subcode timeout 与 V1.9 表一致，迟到 callback 不更新业务状态。
- 恢复 session/重连时 `0x11` 不被 `0x14` 或云请求阻塞。
- Cancel terminal EVENT 先于 RET 时，业务状态可结束，但新 `0x10` 按钮仍保持不可用，直到旧 `0x15` transaction callback/timeout。
- `0x15 04` 不直接断言取消未生效，而是进入状态恢复。
- Cancel unknown 持久化、离页重进和 App 重启后继续每 30 秒查询。

### 8.3 真机/固件联合验证

- SIG Mesh 丢 RET、迟到 RET、EVENT 先于 RET、重复 EVENT、乱序 EVENT。
- Wi-Fi 设置在写入前/写入后收到 clear 的竞态。
- 32-byte SSID、中文 SSID、中文密码、开放网络。
- RSSI 查询失败但 Internet 正常，以及 RSSI 有效但 Internet 不可用。
- OTA 过程中断开 Proxy、App 退后台、杀进程、网关/模组重启。
- Cancel 在 PREPARING、DOWNLOADING、临界 VERIFYING、其它终态的全部分支。
- HTTP 下载被劫持、固件/metadata 被替换和降级包场景；在协议安全方案确定前不能视为生产级 OTA 验收通过。

## 9. 本次静态验证结果

本次没有修改业务代码，也没有运行 iPhoneOS build；针对现有源码执行了以下只读/静态检查：

| 检查 | 结果 | 说明 |
| --- | --- | --- |
| `bash scripts/check_wifi_gateway_firmware_update.sh` | PASS | OTA reducer、Cancel reducer、V1.9 Start/Status/Cancel contract 均通过；这是静态/standalone contract，不代表真机通过。 |
| `bash scripts/check_wifi_gateway_network_connectivity.sh` | PASS | 现有 Network Connectivity 产品契约通过；该脚本仍要求 UserDefaults 密码缓存，也没有覆盖本报告发现的最新 V1.9 UTF-8/恢复语义差异。 |
| `bash scripts/check_wifi_gateway_wifi_status_header.sh` | FAIL | 当前源码为 5 秒，脚本要求 completion 后 10 秒再查询。 |
| `git diff --check` | PASS | 在生成本文档之前，现有 working tree 没有 whitespace error。 |

## 10. 最终判断

### 协议是否有不合理之处

**有。** 最需要优先处理的是 HTTP-only OTA 且缺少签名/防回滚、明文 Wi-Fi 密码回读、无版本协商、普通命令缺少事务 ID，以及结果码过度复用。其余如 opcode 写法、终态生命周期和 URL grammar 也应补充明确。

### 当前 App 已实现哪些协议

**V1.9 列出的 9 个 Subcode 均已有实现，`0x11` EVENT 也已实现。** 其中 `0x15` App 逻辑位于当前未提交 working tree；不能把“全部有入口”理解成“全部符合”。

### 当前 App 功能逻辑是否符合协议

**部分符合。** OTA 状态解析、状态单调性、身份匹配和大部分取消恢复逻辑较完整；Wi-Fi 凭据、配置/清除不确定结果、RSSI/Internet 独立语义、请求 deadline、连接轮询节奏、OTA 恢复顺序和 Cancel transaction gate 仍需要整改。完成 P0/P1 并做真机故障注入前，不建议宣称 App 已完整支持 WiFi Gateway V1.9。
