# Light Information TimeGet 返回 unknown time 分析

## 结论

本次 Light Information 页的报错不是 Mesh 发送、传输、解密或响应超时失败，而是设备成功响应了一个合法的 `TimeStatus`，其 5 字节参数为 `0x0000000000`。

该参数在 Bluetooth Mesh Time Model 中表示设备当前时间未知。SDK 将其解析为 `TaiTime.seconds == 0`；当前 App 明确拒绝展示零时间，因此进入读取失败状态，并显示 `Failed to retrieve data`。

直接根因是：地址 `0x0008` 的设备当前没有有效时间。仅凭本次读取日志，无法继续区分设备是从未成功接收过 `TimeSet`，还是曾有时间但在掉电、重启、OTA 或固件状态恢复后丢失。

## 日志证据链

| 阶段 | 日志证据 | 判定 |
| --- | --- | --- |
| 页面触发 | 点击 Light Information 时间行 | 已进入当前 Light 时间读取逻辑 |
| 请求 | `TimeGet()`，opcode `0x8237`，`src=000B`，`dst=0008` | 请求已发往目标 Light 的 Time Server Element |
| 加密与网络 | 使用 `Space 1 (index: 2)`，Network PDU 正常发出 | AppKey/NetKey 发送链路正常 |
| 响应 | 收到 `src=0008`、`dst=000B` 的 Network PDU | 目标设备确实返回了响应 |
| 解密 | Access Message 使用同一 AppKey 成功解密 | 不是密钥或解密失败 |
| 消息类型 | opcode `0x5D`，解析为 `TimeStatus` | `TimeGet` 获得了期望响应类型 |
| 响应内容 | parameters=`0x0000000000`，`seconds=0` | 设备报告 unknown time |
| App 结果 | Formatter 要求 `seconds > 0` | 快照创建失败，页面显示通用读取失败 Toast |

## 当前 App 的报错路径

1. `LightTimeInformationCoordinator` 使用设备的 `node.timeModel` 发送 `TimeGet`。
2. SDK 回调返回类型正确的 `TimeStatus`。
3. Coordinator 将 `status.time.seconds` 和 offset 交给 `GatewayTimeInformationFormatter.makeSnapshot`。
4. Formatter 对 `seconds == 0` 返回空结果，因为零值是 unknown time，不能转换成真实日期。
5. Coordinator 恢复读取前的本地 Node 时间快照，并发送 `.failed` 状态。
6. `DeviceInformationViewController` 收到 `.failed` 后显示 `failed_to_retrieve_data` 对应的 Toast。

因此，当前 UI 把“设备返回 unknown time”与超时、错误响应、本地保存失败等情况统一显示为 `Failed to retrieve data`。从用户视角看像协议报错，但实际是有效响应的业务状态未被单独表达。

## `Asia/Shanghai` 不是设备返回的时区

日志中的：

`TaiTime(seconds: 0, ..., tzOffset: Asia/Shanghai)`

容易被误解为设备返回了上海时区。实际上 5 字节 unknown-time 响应只包含全零 TAI Seconds，不包含 Subsecond、Uncertainty、TAI-UTC Delta 或 Time Zone Offset。

SDK 在解析这个特殊值时创建默认 `TaiTime()`，而默认构造器把 `tzOffset` 填为 `TimeZone.current`。因此 `Asia/Shanghai` 来自当前手机/App 运行环境，不是地址 `0x0008` 的设备数据，不能用于判断设备时区是否正确。

## Local Server Model Binding 告警不是本次失败原因

以下日志是本地 Provisioner Node 上多个 Server Model 未绑定当前 AppKey 的告警：

- Local Time Server
- Local Time Setup Server
- Local Scheduler Server
- Local Scheduler Setup Server

SDK Access Layer 会遍历本地 Element 中所有能够解码该 opcode 的 Model；命中但未绑定的本地 Server Model会分别输出告警。本次响应仍然已经：

- 成功解密；
- 成功解析为 `TimeStatus`；
- 成功送达 `MeshAPI.sendMessage` 回调；
- 被 Light Coordinator 处理。

同时日志没有出现 Local Time Client 未绑定告警。当前 Light 读取逻辑也会在发送前幂等确保本地 Time Client 绑定。因此这些 Server Model 告警是噪声，不是 `seconds == 0` 或页面 Toast 的原因。

## HTTP heartbeat 与本次报错无关

`/sitespace/user/hb` 返回 HTTP 200 和空 JSON 对象，是 Site 在线心跳。它没有参与本次 Mesh `TimeGet`、`TimeStatus` 解码或 Light Information 的失败判定，也没有业务错误证据。

## 设备为什么会处于 unknown time

当前源码能确认以下事实：

1. Light Information 页面是只读流程，只发送 `TimeGet`，不会发送 `TimeSet`。
2. Site Gateway Fast Add 只对 Gateway 追加时间初始化；非 Gateway 分支没有无条件追加 `TimeSet`。
3. 进入 Devices 页时的 All Nodes `TimeSet` 只有在至少一个 Node 存在 Schedule 且本地存在 Enabled Schedule 时才发送。
4. Schedule、Collection Schedule、Sync Devices 等部分业务会按条件发送 `TimeSet`，但这不是所有 Light 入网后必然执行的初始化步骤。

因此，如果该 Light 没有经过有效的 TimeSet 路径，或者固件在掉电、重启、OTA 后没有持久化/恢复时间，Time Server 就会继续合法返回 unknown time。

本次日志不能在以下两种情况中唯一选定一种：

- App 历史上没有向该 Light 成功发送过 `TimeSet`；
- App 曾成功设置时间，但设备后来丢失了时间状态。

需要追加该设备从入网、TimeSet 到本次 TimeGet 的连续日志，或进行一次受控的 `TimeSet -> TimeStatus -> 重启/掉电 -> TimeGet` 实验才能区分。

## 优化方向

### 方案 A：仅改善 Information 状态表达

识别 `TimeStatus.time.isKnown == false`，让两行显示明确的 `Time not set` 或等价本地化状态，不再使用通用 `Failed to retrieve data`。

优点是保持 Information 页面只读，不改变设备；缺点是只改善提示，不会恢复设备时间。

### 方案 B：补齐 Light 时间初始化与显式重试

对具有 Time Setup Server 的 Light，在确认的入网、Restore 或 Sync 流程发送当前 Site offset 的 `TimeSet`，并以匹配 Node、非零 seconds、匹配 offset 的 `TimeStatus` 作为成功条件。失败时保留已入网设备并进入可重试状态。

该方案能解决时间未初始化，但范围大于 Information 页面，需要统一普通添加、Fast Add、Restore 和 Sync 的状态与重试策略。

### 方案 C：增加受控诊断验证

在不改变正式业务的前提下，对地址 `0x0008` 执行一次单播 `TimeSet`，确认返回有效 `TimeStatus` 后再次 `TimeGet`；随后覆盖软重启、断电和 OTA，判断时间丢失发生在 App 初始化缺口还是固件持久化/恢复。

## 建议

短期建议先实施方案 A，让“读取成功但时间未知”和真正的通讯失败可区分；同时用方案 C 明确设备时间为何为零。确认设备侧行为后，再决定是否实施方案 B，避免 Information 页面在用户仅查看信息时静默修改设备时间。

## 本轮验证与边界

- 已运行 `scripts/check_light_information_time.sh`，Light/Gateway 时间相关聚焦策略与运行时合同全部通过。
- 已运行 `git diff --check`，通过。
- 本轮未修改 App 或 SDK 业务代码，只新增本分析文档。
- 未执行真实设备的 `TimeSet`、掉电、重启、OTA 或连续 Mesh 抓包，因此设备时间丢失的上游触发点仍待真机验证。
