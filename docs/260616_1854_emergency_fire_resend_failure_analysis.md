# Emergency Fire Controller Resend 配置失败分析与修复方案

## 背景

- 设备：Emergency Fire Controller，目标地址 `0x007E`
- 发送方：Primary Element `0x0023`
- 失败命令：`SunricherVendorSet(function: .emergencyResendParameters(...))`
- 具体参数：`stateIndex = restore`，`intervalSeconds = 5`，`count = 2`
- 日志 Access PDU：
  - opcode：`0xF0780A`
  - parameters：`0x4D030205000200`
- 设备返回：
  - opcode：`0xF3780A`
  - parameters：`0x4D0302`
  - SDK 解析：`isSuccessful = false`，`errorCode = 2`，`code = emergencyResendParameters`

## 日志解码

发送参数 `0x4D030205000200` 可按当前 SDK v2 语义拆分为：

| 字节 | 含义 |
|---|---|
| `4D` | Emergency Fire vendor 子命令族 |
| `03` | resend parameters |
| `02` | state_idx = RESTORE |
| `0500` | N = 5s，小端 |
| `0200` | M = 2，小端 |

这正是协议文档 v2 `0x4D/0x03 SET` 的格式：`state_idx + N + M`，总参数为 `0x4D + subcode + 5B`。

返回参数 `0x4D0302` 可按 v2 错误码解释为：

| 字节 | 含义 |
|---|---|
| `4D` | Emergency Fire vendor 子命令族 |
| `03` | resend parameters |
| `02` | ret = length error |

协议文档定义 `0x4D/0x03 SET` 的返回码：

- `0`：OK
- `2`：payload 长度错误
- `3`：state_idx 越界
- `4`：N = 0

因此本次失败不是 `restore` state 越界，也不是 `N=0`，而是设备端认为收到的 `0x03 SET` payload 长度不符合它当前实现。

## 根因判断

高概率根因：当前 App/SDK 已按 Emergency Fire v2 协议发送 `0x4D/0x03`，但目标设备固件仍按旧 v1.3.x `0x4D/0x03` 长度校验，或固件没有真正切到 v1.4/v1.5 的 v2 协议实现。

证据：

1. 当前 SDK 编码与 v2 文档一致。
   - `SunricherVendorSet.emergencyResendParameters` 生成 `4D 03 state_idx N M`。
   - SDK 测试也固定了 `restore, N=5, M=10` 应编码为 `4D 03 02 05 00 0A 00`。
2. v2 文档明确 `0x4D/0x03` 从旧格式 breaking 改为 per-state `idx + N + M`。
   - v2：`0x4D 0x03 + state_idx + N + M`。
   - v1.3.x：`0x4D 0x03 + trigger N/M + stop N/M`，没有 `state_idx`，长度更长。
3. 设备返回的是 `ret=2` 长度错，正好符合“设备仍按旧长度规则检查，但 App 发了 v2 短格式”的表现。
4. 日志中已经收到并成功解析设备的 vendor status，说明 Mesh 加密、AppKey、网络传输和目标地址基本可用。

`Local Vendor Model model on Primary Element (0x0023) not bound to key: Space 1` 不是本次失败的直接原因。它出现在设备返回失败 ACK 之后；如果本地模型绑定才是根因，通常不会先得到并解析出 `0x4D0302` 的业务层失败状态。

## 影响面

如果目标设备确实仍是旧固件，当前 v2 App 同步链路中的多条命令都会继续失败或错位：

- `0x4D/0x03` per-state resend：旧固件按旧 8B 配置理解，会返回长度错。
- `0x4D/0x05` enable：旧固件按 mode 0/1/2 理解，语义不同。
- `0x4D/0x04` comprehensive status：旧固件返回 mode + active，v2 App 期望 enable + fire + em + ever。
- `0x4D/0x07` action config：旧固件没有该 subcode。

所以不能只针对 Restore resend 做单点修复；必须先确认设备协议代际。

## 修复方案

### 方案 A：保持当前策略，只支持 v2 固件

这是当前代码和此前计划的方向：设备仍处于研发阶段，SDK/App 直接废弃旧 API，只保留 v2。

处理步骤：

1. 确认目标设备固件是否为 v1.4.0 或 v1.5.0，且产品宏为 `PRODUCT_2421_DRYCON924_54L15`。
2. 确认设备完成 v1.3.6 到 v1.4.0 的 breaking 升级流程：
   - composition hash 已更新。
   - NVS 已全擦或 DATA_VERSION 升级路径已生效。
   - Element 3 的 8 个 Client 模型已存在并绑定 AppKey。
3. 重新 provision 或至少完整重配 EFC：
   - 绑定 Element 3 上的 8 个 Client 模型 AppKey。
   - 下发三个 state 的 `0x4D/0x07` action config。
   - 下发 `0x4D/0x03` 三个 state 的 resend 参数。
   - 下发 `0x4D/0x06` restore delay。
   - 读取 `0x4D/0x04` 验证返回 v2 comprehensive status。
4. App 侧补充诊断体验：
   - 当 `emergencyResendParameters` 返回 `errorCode=2` 时，在同步失败详情里提示“设备固件协议可能不是 Emergency Fire v2 或未完成升级重配”。
   - 记录失败命令、state、payload 和 ret，方便嵌入式确认。

优点：保持当前研发策略和代码模型一致，避免重新引入旧 API 分流。

风险：现场如果存在旧固件设备，旧设备无法被新版 App 成功配置，只能通过固件升级或重新入网解决。

### 方案 B：App/SDK 恢复旧固件兼容分流

只有在需要同时支持 v1.3.x 和 v2 设备时才建议采用。此方案会扩大实现和测试范围。

处理步骤：

1. 在 SDK 重新引入独立命名的旧协议类型，不要复用 v2 `EmergencyFireResendParameters`。
2. 建立协议代际判断：
   - 优先使用 firmware version、composition hash 或设备能力字段。
   - 不能只靠一次 `0x4D/0x03` 失败做永久判断，避免把偶发传输错误误判成旧固件。
3. App 同步 planner 分流：
   - v2 设备继续走 `enabled + three-state resend + action config + restore delay`。
   - v1.3.x 设备走旧 `mode + trigger/stop resend + publication + scene` 流程。
4. 数据模型增加清晰的 protocol generation 字段，避免 `workMode` 重新污染 v2 配置事实来源。
5. 增加 SDK 和 App 层测试，覆盖同一个 `0x4D/0x03` 在 v1/v2 下的不同编码和返回解析。

优点：可兼容研发旧固件和新固件。

风险：会重新引入旧 v1.3.x 语义，增加 UI、同步、导入导出、删除清理和测试复杂度；也与此前“设备未正式发布，直接废弃旧 API”的决策冲突。

## 推荐结论

推荐采用方案 A。

本次日志显示 App/SDK 发出的 payload 是 v2 正确格式，设备却按长度错误拒绝。应先由嵌入式确认设备固件协议版本和升级状态，而不是在 App 侧把 v2 resend 改回旧格式。

如果确认设备已经是 v1.4/v1.5 固件，则应把这条日志交给嵌入式排查 `0x4D/0x03 SET` 的长度校验实现：按文档，`0x4D 0x03 0x02 0x05 0x00 0x02 0x00` 应该被接受，除非固件实际实现与文档不一致。

## 验证清单

1. 使用同一台设备读取固件版本或 composition hash，确认不是 v1.3.x。
2. 发送 v2 探测命令：
   - `GET 0x4D/0x04` 应返回 `ret + enable + fire + em + ever_triggered`。
   - `GET 0x4D/0x03 state_idx=2` 应返回 `ret + state_idx + N + M`。
   - `GET 0x4D/0x07 state_idx=2` 应返回 action config 或 INVALID。
3. 重新发送本次失败命令：
   - `SET 0x4D/0x03 state_idx=2 N=5 M=2`
   - 预期返回 `0x4D030002` 或等价的成功 ACK 结构。
4. 如果仍返回 `0x4D0302`，固件侧按 v2 文档修复长度校验。
5. 如果固件确认为旧 v1.3.x，决定是否升级固件或重新打开方案 B 的兼容实现。
