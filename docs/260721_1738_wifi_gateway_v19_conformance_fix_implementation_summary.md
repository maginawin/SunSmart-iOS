# WiFi Gateway V1.9 一致性修复实施总结

## 1. 结论

本轮已按确认的方案 A 严格以《WiFi Gateway V1.9》为唯一协议基线，完成已批准的 6 项 P0 与 5 项 P1 修复。改动覆盖本地 `NordicSigMeshSDK` 的协议编解码与 typed model，以及 App 的超时、凭据恢复、连接轮询、OTA 恢复和 transaction gate。

当前自动化契约检查、SDK iPhoneOS Demo 构建，以及 App 四个品牌 scheme 的通用 iPhoneOS 构建均通过。SDK 的 focused XCTest 无法在 macOS SwiftPM 环境开始执行，阻塞原因是 SDK 既有源码依赖 `UIKit`，不应将该项记录为测试通过；对应 wire-level 契约已经由源码测试用例、App 检查脚本和 iPhoneOS 构建覆盖，真机时序仍需按第 5 节验证。

## 2. P0 实施结果

| 项目 | 实施结果 | 主要验证 |
| --- | --- | --- |
| Wi-Fi 凭据 UTF-8/32-byte 规则与 12.1 示例 | SDK 统一使用 UTF-8 byte count 校验：SSID/密码字段上限为 32 bytes，密码为空或至少 8 bytes；拒绝控制字符，保留协议允许的标点；App 在发送前复用同一语义。SDK 增加协议 12.1 完整 payload 契约用例。 | SDK vendor message tests 源码契约；App credential reducer 检查；SDK Demo 与 App 四 scheme iPhoneOS 构建。 |
| `0x0D`、`0x13` 的一次性 `0x12` 恢复 | 将 `02` 视为未确认结果；只允许查询一次 `0x12` 恢复最终状态，不自动重发 SET，避免错误状态和重复副作用。 | `WiFiGatewayCredentialMutationReducerTests`；disconnect/clear credentials 检查脚本。 |
| `0x0F` typed model | 严格要求 5-byte payload，RSSI result 与 Internet status 始终作为独立字段保留，并收紧成功/失败组合的 RSSI 合法性。 | SDK vendor message tests 源码契约；Wi-Fi status header 检查脚本。 |
| V1.9 timeout 对齐 | 建立按 opcode/subcode 的 timing contract；`0x10` 改为 3 秒，Wi-Fi GET/SET 按具体命令使用 3/4/7 秒 deadline，不再共享模糊的通用超时。 | `WiFiGatewayV19TimingTests`；network connectivity 与 firmware update 检查脚本。 |
| OTA 页面恢复顺序 | 页面恢复时先注册 observer、恢复本地 gate 并查询权威 `0x11`；云端固件元数据请求在此后独立进行，不能阻塞设备状态恢复。 | firmware update 静态契约检查；App 四 scheme iPhoneOS 构建。 |
| `0x15` transaction gate | 使用可持久化的独立 transaction gate，阻止 `0x15` handle 生命周期结束前创建新 `0x10`；业务终态本身不提前释放 gate，回调结束或 deadline 才释放。 | `WiFiFirmwareDFUTransactionGateTests`；firmware update 检查脚本。 |

## 3. P1 实施结果

| 项目 | 实施结果 | 主要验证 |
| --- | --- | --- |
| `0x0E` 轮询与总窗口 | 改为每 5 秒轮询、65 秒总窗口；收到 `0x06` 时保持进入流程前的原连接状态。 | `WiFiGatewayConnectionPollingReducerTests`；network connectivity 检查脚本。 |
| `0x11/0x14` identifier 校验 | SDK 复用统一 identifier validator，按 V1.9 收紧长度、字符和空值语义。 | SDK vendor message tests 源码契约；SDK Demo iPhoneOS 构建。 |
| 不确定结果 enum 命名 | `0x0D 02`、`0x12 02`、`0x13 02` 使用 `unconfirmed` 类语义；`0x0E` 错误语义同步按协议命名，避免 App 将未知结果持久化为确定失败。 | SDK typed model 编译；App credential reducer 检查。 |
| `0x15 04` 恢复语义 | 将取消结果作为“不确定/忙或失败”处理，保留 transaction gate 并查询权威状态，不把未知结果直接收敛为已取消。 | `WiFiFirmwareDFUCancelReducerTests`、transaction gate tests；firmware update 检查脚本。 |
| RSSI 轮询源码与静态契约 | 保留 App 实际 5 秒轮询语义；调整检查脚本，使其分别校验运行时轮询和 10 秒静态展示契约，不再错误要求二者使用同一源码常量。 | Wi-Fi status header 检查脚本。 |

## 4. 自动验证记录

| 验证项 | 结果 | 说明 |
| --- | --- | --- |
| `scripts/check_wifi_gateway_network_connectivity.sh` | PASS | Timing 与 connection polling reducer 测试通过。 |
| `scripts/check_wifi_gateway_disconnect_clear_credentials.sh` | PASS | Credential mutation reducer 测试通过。 |
| `scripts/check_wifi_gateway_wifi_status_header.sh` | PASS | RSSI/Internet 展示与轮询契约检查通过。 |
| `scripts/check_wifi_gateway_firmware_update.sh` | PASS | OTA status、cancel、transaction gate、metadata、start/recovery 契约检查通过。 |
| SDK focused XCTest | BLOCKED | `swift test --filter WiFiGatewayVendorMessageTests` 在编译阶段被既有 macOS 兼容问题阻塞：`MeshDeviceProvisioningManager.swift:8:8: error: no such module 'UIKit'`，测试未开始执行。 |
| NordicSigMeshDemo，generic iPhoneOS | PASS | 本地 SDK 以 iPhoneOS 工程完成编译验证。 |
| SunSmart，generic iPhoneOS | PASS | `CODE_SIGNING_ALLOWED=NO`。 |
| Archipelago，generic iPhoneOS | PASS | `CODE_SIGNING_ALLOWED=NO`。 |
| SLG Sync Plus，generic iPhoneOS | PASS | `CODE_SIGNING_ALLOWED=NO`。 |
| SylSmart，generic iPhoneOS | PASS | `CODE_SIGNING_ALLOWED=NO`。 |
| `git diff --check` | PASS | App 与 SDK 均无 whitespace error；SDK 工作区干净。 |
| 共享源码 target membership | PASS | 新增四个共享 model 均加入 SunSmart、Archipelago、SLG Sync Plus、SylSmart。 |

## 5. 真机与集成环境待验证

以下项目依赖真实 Gateway、BLE Mesh 时序、App 生命周期或云端服务，不能由编译与静态契约替代：

1. 使用协议 12.1 示例、32-byte ASCII 凭据及多字节中文凭据，分别验证 SDK → App → Gateway 端到端发送和设备连接结果。
2. 模拟 `0x0D/0x13` 丢失 RET、返回 `02`、延迟 RET，以及 EVENT/RET 乱序，确认只查询一次 `0x12`，且不会重发 SET。
3. 覆盖 `0x0F` 的 RSSI 成功/失败与 Internet connected/disconnected 全部合法组合，确认 UI 不互相覆盖两个维度。
4. 验证 `0x0E` 在 5 秒轮询、65 秒窗口边界和 `0x06` 返回下的连接状态保持。
5. 覆盖 OTA 页面首次进入、离开再进入、Proxy 断开重连、App 终止重启，以及云请求慢/失败场景，确认优先恢复 `0x11` 权威状态。
6. 在 `0x15` 回调延迟、返回 `04`、超时和 App 重启场景下，确认 gate 未结束前 Start 始终禁用，且权威状态恢复后才允许新 `0x10`。

## 6. 提交与范围

SDK 提交：

- `3f54bb1 fix: align wifi gateway credential semantics with v1.9`
- `2b3f5ee fix: enforce wifi gateway v1.9 status parsing`

App 提交：

- `242c02f3 test: compile shared wifi gateway v1.9 validator`
- `7d9feb3e test: define wifi gateway v1.9 timing contract`
- `5b82676e test: model wifi credential mutation recovery`
- `ff990ece test: model wifi gateway connection polling`
- `2849397d fix: align wifi gateway network flow with v1.9`
- `d8761c9d fix: preserve wifi ota cancel transaction gate`
- `eff0f8ae fix: prioritize wifi ota recovery and gate new starts`

本轮未处理 P2、凭据存储策略、无关 UI/业务重构、依赖升级或 Auth 信息。用户原有未跟踪文档 `docs/260721_1658_wifi_gateway_v19_protocol_conformance_analysis.md` 保持不变且不纳入提交。
