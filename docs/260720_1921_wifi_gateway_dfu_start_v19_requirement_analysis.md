# WiFi Gateway DFU Start V1.9 需求分析与待确认方案

> 确认状态：用户已于 2026-07-20 确认方案 A，并确认第 1 节的 4 个推荐决策；本文作为后续实施计划的需求基线。

## 1. 结论

需求的协议主干已经足够明确，但还不是完全闭合的 App 实施规格。当前需要锁定 4 个 App 侧决策：`firmware_id` 来源、`ota_id` 生成规则、无有效 RET 且无法确认时的 UI 结果、旧版 `0x43/0x10` 是否彻底停止兼容。

按当前代码和既有产品行为，推荐采用以下默认决策：

1. `firmware_id` 继续取 latest HTTPS response 的 `version`，最多移除一个前导 `v` 或 `V`。
2. 每次用户明确点击 `UPGRADE` 或 `UPGRADE AGAIN` 都生成一个新的、非零随机 `UInt64 ota_id`；自动恢复和状态查询不得生成新 ID，也不得自动重发 `0x43/0x10`。
3. 未收到有效 RET，且匹配 EVENT 与一次性 `0x43/0x11` 查询都不能确认本轮已建立时，结束本次请求并沿用 `Connection failed / Communication timeout` 与 `UPGRADE AGAIN`；不继续轮询，不自动重发。
4. App 和 SDK 直接切换到 V1.9，不继续发送旧版无 `ota_id` 的 `0x43/0x10`。当前协议没有能力协商字段，双格式自动兼容会产生不可判定的请求。

以上 4 点已经确认，需求可以进入详细实施计划和开发。

## 2. 当前实现核查

### 2.1 URL 拼接已经符合本次规则

当前 `WiFiFirmwareDFUMetadataBuilder` 已经：

- 从 `UserData.currentServerRegion.baseURL` 读取当前 App 区域 HTTPS base URL；
- 只把 scheme 改为 `http`；
- 保留区域 host 和 `/srv2` 基础路径；
- 追加固定 `/sitespace/ota/download`；
- 使用 response body 的 `filename` 作为 `key` query value；
- 不使用 response body 的预签名 `url`。

用需求给出的 China Mainland base URL 和 filename 实际执行当前 builder 逻辑，输出为：

```text
http://www.mericher.com/srv2/sitespace/ota/download?key=dev/20260514100245/OTA_Gateway_SS_0A78_0x2721_wifi_9036T-GW-54TA-PA-WIFI_v0.4.0_20260514.zip
```

与需求示例逐字一致，ASCII 长度为 148。因此 URL 生产代码不需要为了示例重写；实施时应补充精确行为测试，防止以后退回预签名 URL 或遗漏区域 `/srv2` 路径。

当前实现使用 `URLQueryItem` 对 filename 中必须转义的字符做 percent encoding。对于本次示例中的 `/`、`_`、`-` 和 `.`，输出不会变化。这比裸字符串拼接更安全，推荐保留。

### 2.2 `0x43/0x10` 仍是旧请求格式

本地 `NordicSigMeshSDK` 当前发送：

```text
43 10 <url_len:U16_LE> <url> <firmware_id_len> <firmware_id>
```

缺少 V1.9 新增的 8 字节 `ota_id`。按需求示例 URL 长 148、`firmware_id=0.4.0` 长 5 计算：

- 当前旧 payload：`5 + 148 + 5 = 158` 字节；
- V1.9 payload：`13 + 148 + 5 = 166` 字节。

当前 SDK 已经不再发送 `size` 和 `sha256`，这一点符合新协议。

### 2.3 SDK 长度与字符校验仍按旧格式

当前 `WiFiGatewayDFUMetadata` 只校验 `5 + url_len + firmware_id_len <= 256`，V1.9 应改为：

- `ota_id` 必须为 `1...UInt64.max`；
- `url_len` 必须为 `7...242`；
- `url_len <= 243 - firmware_id_len`；
- 总长度必须为 `13 + url_len + firmware_id_len <= 256`；
- `firmware_id` 除 `"` 外，还必须拒绝 `,` 和 `\`。

当前 URL 的 `http://` 大小写校验和 URL ASCII 字符范围已经符合要求；firmware ID 的逗号和反斜杠限制缺失。

### 2.4 SDK 仍只接受旧 3 字节 RET

当前 SDK 只接受：

```text
43 10 <ret>
```

并把 typed result 暴露为不含 `ota_id` 的 `WiFiGatewayDFUStartResult`。V1.9 的合法 RET 固定为 11 字节：

```text
43 10 <ret> <ota_id:U64_LE>
```

因此新固件返回合法 11 字节 RET 时，当前 typed parameters 会解析失败，App 最终进入 timeout/connection failed 分支。这是当前最直接的协议不兼容点。

### 2.5 当前 App 会话在首个 `0x43/0x11` 才绑定 `ota_id`

当前 coordinator 在发送 start 时只保存 `firmware_id`，收到 accepted 后创建 `otaID=nil` 的 session，再由首个匹配 firmware ID 的非 IDLE `0x43/0x11` 状态绑定任意非零 `ota_id`。

V1.9 后 App 在发送请求前就知道本轮 `ota_id`，应立即把 session、EVENT、RET 和查询全部收紧到同一个 `ota_id + firmware_id`。继续使用“首状态绑定任意 ota_id”会误接收同一 firmware ID 的旧轮次状态。

### 2.6 当前未实现“无有效 RET”的 V1.9 恢复顺序

当前 start 请求等待期间虽然会暂存匹配 firmware ID 的 EVENT，但如果 SET callback 没拿到合法 RET，代码会直接清理 pending 状态并显示 timeout：

- 不会先用已经收到的匹配 EVENT 确认请求已建立；
- 不会在原 SET 事务结束后只查询一次 `0x43/0x11`；
- EVENT 只匹配 firmware ID，没有匹配本次请求的 ota ID。

这与本次 V1.9 规则不一致，必须修改 App coordinator。

### 2.7 已经符合、不需要重做的行为

- `ret=0x04` 已映射为 Internet/server unavailable，并且不会进入 `0x43/0x11` 轮询。
- `ret=0x03` 当前不会自动重发 `0x43/0x10`。
- `0x43/0x11` V1.9 完整状态已经包含 `ota_id`，并支持 `FAILED + METADATA`。
- 当前常规状态归并已按 `ota_id + firmware_id` 过滤、拒绝阶段倒退和进度倒退，并持久化非终态会话。
- 当前 App 没有实现 `0x43/0x15` cancel；协议中“cancel pending 时返回 busy”属于设备侧优先级，本次 App 只需要正确处理 `ret=0x02`。
- `UPGRADE AGAIN` 是明确用户操作，不属于自动重发。

## 3. 需求完整性与待确认项

| 项目 | 当前需求状态 | 推荐锁定值 |
| --- | --- | --- |
| URL host/path/filename | 完整 | 沿用当前区域 base URL，仅改 HTTP，固定 path，key 取 body.filename |
| URL 特殊字符 | 未明确裸拼接还是编码 | 保留 `URLQueryItem` 的必要 percent encoding；示例输出不变 |
| `firmware_id` 来源 | 本次文本未说明 | body.version，最多移除一个前导 v/V |
| `ota_id` 生成 | 只给范围，未给 App 算法 | 每次明确用户发起生成新的非零随机 UInt64 |
| RET 关联 | 协议给出回显规则 | 只有完整 11 字节且 ota ID 等于请求 ID 才是本轮有效 RET |
| 无有效 RET 后的未知结果 UI | 协议只定义“结果未知” | timeout/connection failed + UPGRADE AGAIN，不自动重发 |
| 旧版 start 兼容 | 未说明 | 不兼容旧格式，只发送 V1.9 |
| `0x43/0x15` cancel | 未要求 App 发起 | 保持现状，不纳入本次开发 |

## 4. 方案比较

### 方案 A：SDK typed request/response + App coordinator 同步升级（推荐）

在 SDK 中用明确的 start request/response 模型承载 `ota_id`，由 SDK负责字段校验、LE 编码、RET 解析和同 opcode 响应关联；App coordinator 负责生成 ID、持久化 pending/session、EVENT/RET/一次查询恢复和 UI 映射。

优点：协议真值集中在 SDK，App 不拼 raw payload；能利用 `ota_id` 在 transport 层拒绝旧 RET；最容易通过单元测试覆盖。改动涉及 SDK 与 App 两个仓库，但边界清晰。

### 方案 B：只给现有 metadata/result 类型追加字段

直接给 `WiFiGatewayDFUMetadata` 增加 `otaID`，并把当前 result 改成携带回显 ID 的复合类型。

优点：文件数量少。缺点：metadata 名称开始同时承担事务身份，request/response 语义不清晰，后续维护容易再次遗漏 correlation。可做，但不如方案 A 清楚。

### 方案 C：App 手工拼装和解析 `0x43/0x10`

绕过 SDK typed API，在 App 内构造 payload，并在 callback 中手工读 RET。

优点：表面改动快。缺点：与现有 vendor routing、response matching 和 SDK tests 重复，最容易发生错误 RET 提前结束事务或 App/SDK 协议漂移，不建议。

## 5. 推荐设计

### 5.1 SDK 请求与应答模型

- 新的 start request 明确包含 `otaID`、`url`、`firmwareID`。
- 初始化时一次性校验非零 ID、URL scheme/字符/长度、firmware ID 字符/长度和 256 字节总长。
- `SunricherVendorSet` 严格按 `43 10 + ota_id U64_LE + url_len U16_LE + url + firmware_id_len + firmware_id` 编码。
- start response 暴露 `result + echoedOTAID`，只接受精确 11 字节；旧 3 字节 RET 和 trailing bytes 都不是合法 typed response。
- `MeshMessageHandle` 对 `wifiGatewayDFUStart` 增加 ota ID 关联：相同 node/opcode 但回显 ID 不同的 RET 不得结束当前 SET 事务。
- 保留 `ret=0x00...0x04` 和 reserved 的强类型表达，便于诊断；App 只把 `0x00...0x04` 视为协议定义的有效 ret，`isSuccessful` 只对 accepted 为 true。

### 5.2 App `ota_id` 生命周期

- `UPGRADE` / `UPGRADE AGAIN` 点击后先生成非零随机 UInt64，并与本次 filename、firmware ID 一起形成 pending start context。
- 自动状态恢复、页面重进、Mesh 重连和 `0x43/0x11` 查询复用原 ID，绝不生成新 ID。
- 每次新的用户 start 操作生成新 ID，即使目标 firmware ID 与上次相同。
- accepted RET 到达后，session 立即保存该请求 ID，不再等待首个 EVENT 绑定。
- 为兼容当前 App 已持久化的旧 session，`otaID` 可暂时保持 optional；新创建的 V1.9 session 必须非空。

### 5.3 Start 事务状态流

```text
用户点击
  -> 生成新 ota_id、构造 request、开始 SET
  -> SET 等待期间缓存 ota_id + firmware_id 均匹配的合法非 IDLE EVENT
  -> 收到匹配 ota_id 的有效 RET
       -> ret=00：建立/恢复本轮 session，进入 PREPARING 展示与常规状态跟踪
       -> ret=01/02/03/04：结束本次 start，按现有失败映射展示，不查询、不自动重发
       -> reserved ret：按无有效 RET 继续下方确认流程
  -> 未收到有效 RET
       -> 已缓存匹配 EVENT：视为请求已建立并进入常规状态跟踪
       -> 否则：原 SET 事务结束后只查询一次 43 11
            -> 匹配非 IDLE：视为请求已建立并进入常规状态跟踪
            -> IDLE/不匹配/busy/非法/超时：结果未知，结束本次请求，不轮询、不自动重发
```

有效 RET 的定义是：source/network 正确、payload 精确 11 字节、ret 位于 `0x00...0x04`、typed result 可解析、回显 ota ID 与请求 ID 相同。`ret=0x03` 是有效失败 RET，必须结束本次请求，不进入“无有效 RET”的一次查询分支。

### 5.4 URL 处理

- 保留当前 builder 的 region base URL、HTTP scheme、固定 path 和 `URLQueryItem`。
- 不读取 server response 的 `url` 作为设备 URL。
- 增加需求示例的精确回归检查，并覆盖 AP/US/EU host，确保所有 target/region 仍使用自己的 host。

## 6. 开发任务规划

### Task 1：先更新 SDK start wire contract

修改本地 `nordic-sig-mesh-sdk` 的 start request 校验、payload 编码、11 字节 RET 解析和 typed parameters；先补失败测试，再实现。覆盖非零 ota ID、U64 LE、长度边界、逗号/反斜杠、旧 RET 拒绝和所有 ret。

### Task 2：收紧 SDK response matching

让 `MeshMessageHandle` 只用相同 ota ID 的 `0x43/0x10` RET 完成当前 start SET；增加相同 node/opcode 但 ota ID 不同、ID 为 0、ID 相同三类测试，避免旧 RET 或并发事务串包。

### Task 3：更新 App start request 与 session 身份

在 `WiFiFirmwareDFUCoordinator` 中生成并保存本轮 ota ID，使用 SDK 新 typed request，pending reducer 从创建时就绑定该 ID；accepted 后 session 直接持久化该 ID。保留旧持久化 session 的读取兼容。

### Task 4：实现无有效 RET 的一次性恢复

把 pending start 明确区分为等待 RET、等待一次恢复查询、已建立、已结束。实现“先检查匹配 EVENT，否则只查询一次 `0x43/0x11`”，并确保任何失败路径都不自动重发 `0x43/0x10`。有效 `ret=01...04` 不进入恢复查询；reserved ret 视为无有效 RET。

### Task 5：锁定 URL 和 App 行为 contracts

保留当前 URL builder，增加需求示例精确结果及多区域 host 检查；更新 `scripts/check_wifi_gateway_firmware_update.sh`，移除旧 3 字节 RET/无 ota ID 假设，守住 filename 来源、V1.9 request、匹配 EVENT、一次查询和 no-auto-resend。

### Task 6：完整验证

- SDK focused tests：start encoding/validation/RET/response matching 与既有 WiFi Gateway vendor tests。
- App focused tests：ota ID 生命周期、pending start 决策、EVENT/RET/query 归属、结果未知、旧 session 恢复。
- 运行现有 WiFi Gateway regression scripts。
- `git diff --check`。
- 直接使用 generic iPhoneOS 构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 scheme，`CODE_SIGNING_ALLOWED=NO`。
- 检查本地 SDK repo 与 App worktree 的改动分别聚焦，提交时不混入其它文件。

## 7. 明确不在本次范围

- 不新增或实现 `0x43/0x15` cancel。
- 不修改 `0x43/0x11` 已完成的 V1.9 stage/code 字段布局。
- 不改 WiFi firmware 页面视觉布局和既有中英文文案，除非实施中发现“结果未知”需要新增独立文案并另行确认。
- 不修改 generic BLE/Mesh firmware update 流程。
- 不使用 HTTPS response 的预签名 `url`，不在 App 下载、校验或解压 WiFi OTA 文件。

## 8. 确认结果

已确认按方案 A 和第 1 节的 4 个推荐决策进入详细实施计划；后续变更以用户新的明确说明为准。
