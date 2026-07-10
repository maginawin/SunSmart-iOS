# WiFi Gateway Server Information 恢复实施总结

## 结论

已按方案 A 完成 CID `0x0A78`、PID `0x2721` WiFi Gateway 的 Server Information 恢复实现：Gateway Register、MQTT 信息解析与持久化已收敛到共享服务；Repair Recovery 新增 `Server Authorization` 和动态 `Server Information` 任务；本地 MQTT 目标缺失或设备侧服务器信息未收敛时，Repair 不再提前成功；WiFi Gateway 的手动 Authorize 改走相同服务器恢复子链。

手机无互联网但 Gateway BLE/Mesh Online 时，现有 Initialize、Associated Spaces、Association Project、Sync Spaces 仍可执行；Server Authorization 失败后，Server Information 与 Verification 标记为 Skipped，整体 Recovery 失败。网络恢复后 Retry 保留已成功 Mesh 任务，只重置服务器失败链和验证。

本轮新增及相关既有源码契约、本地化检查、凭据审计和 SunSmart、Archipelago、SLG Sync Plus、SylSmart 四个品牌的 generic iPhoneOS 构建均通过。由于本轮没有连接真实 WiFi Gateway，也没有服务端 Gateway Register 观测条件，重复注册凭据合同和真机在线/离线恢复矩阵均未执行，不能仅依据静态检查和构建结果宣称现场问题已经完全闭环。

## 实施内容

### 共享 Server Authorization 服务

- 新增 `GatewayServerAuthorizationService` actor。
- Add、Cloud Sync、Repair 和 WiFi Authorize 使用同一 Gateway Register、响应校验和持久化规则。
- 同一 Site/MAC 的同时注册请求复用同一个 in-flight Task。
- 明确区分无网络、Node export 失败、请求失败、响应字段缺失和数据库保存失败。
- 要求 `mqttUsername`、`mqttPassword`、`mqttClientId`、`host`、`port` 完整有效。
- 保存失败时恢复之前的内存值，不保留只存在于内存的虚假目标。
- 错误诊断只记录错误类型、code 或缺失字段名，不输出 MQTT 字段值和完整响应。

### Fast Add 与 Cloud Sync

- Fast Add 删除重复的 MQTT 响应解析，改用共享 Authorization 服务。
- Fast Add 的总体成功、回滚和删除语义保持不变；授权失败仍交由后续 Recovery 恢复。
- Cloud `.syncGateway` 直接调用共享服务并使用 `.always` policy，避免通用请求分支丢弃凭据。
- Cloud cancel 会取消当前 waiter；底层共享请求仍可服务同 Gateway 的其他调用者。
- Cloud 本地已有有效 MQTT 目标时，允许服务端更新响应不重复返回凭据；本地目标为空时，字段缺失仍明确失败。

### Recovery 任务图与成功条件

- WiFi Gateway Recovery 始终创建 `Server Authorization` 和 `Server Information`，不再因初始 `mqttServerInfo == nil` 省略服务器任务。
- `Server Information` 在真正执行时读取 GatewayModel 的最新目标，能够使用 Authorization 刚持久化的数据。
- 服务器任务依赖关系为 `Initialize -> Server Authorization -> Server Information`。
- Associated Spaces、Association Project 和 Sync Spaces 只依赖 Initialize，不依赖手机互联网。
- WiFi Gateway Final Verification 显式要求：
  - `mqttServerInfo` 完整有效；
  - `node.isKeybindComplete == true`；
  - 设备侧 MQTT Information 与本地目标一致；
  - Gateway diff 为空。
- 其他 Gateway 的静态 Server Information、Repair 和最终验证语义保持现状。
- Authorization 失败原因可在 Sync 任务详情中展示；不再只显示没有上下文的 `Failure`。

### WiFi Gateway Authorize 与页面刷新

- Gateway Server Information Header 改为调用可覆盖的 Authorization hook。
- 其他 Gateway 默认继续使用旧 Authorize 路径。
- WiFi Gateway 覆盖 hook，通过现有 `prepareForGatewayRecovery` 等待自动 WiFi acknowledged 请求，并阻止用户主动网络操作期间并发。
- WiFi Authorize 进入 focused Server Recovery Sync，不再从 WiFi 页面直接发送未验证的 MQTT Mesh Set。
- 页面重新出现或服务器恢复成功时，只从数据库刷新不可编辑的 `mqttServerInfo`，不覆盖未保存的 Name、Associated Spaces、APN 或 Activate 工作副本。

### 开发期编译问题

首次 Task 2 SunSmart 构建发现 `CloudSynchronizationManager.swift` 引入的 Moya `Task` 遮蔽 Swift Concurrency `Task`，导致 `Task.isCancelled` 无法解析。已使用 `_Concurrency.Task<Never, Never>.isCancelled` 明确限定类型；随后 SunSmart 构建和最终四品牌构建均通过。

## 静态验证

### 聚焦与回归脚本

| 命令 | 结果 |
| --- | --- |
| `bash scripts/check_wifi_gateway_server_information_recovery.sh` | PASS |
| `bash scripts/check_wifi_gateway_repair_recovery.sh` | PASS |
| `bash scripts/check_wifi_gateway_network_connectivity.sh` | PASS |
| `bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh` | PASS |
| `bash scripts/check_wifi_gateway_sig_mesh_status_header.sh` | PASS |
| `bash scripts/check_wifi_gateway_wifi_status_header.sh` | PASS |
| `bash scripts/check_wifi_gateway_apn_removed.sh` | PASS |
| `bash scripts/check_wifi_gateway_info_rows_hidden.sh` | PASS |
| `bash scripts/check_wifi_gateway_menu_icons.sh` | PASS |
| `bash scripts/check_gateway_associated_spaces_deferred_save.sh` | PASS |

### 凭据与直发审计

| 检查 | 结果 |
| --- | --- |
| Authorization、Cloud、Add 中搜索输出 MQTT 字段或完整响应的 `print(...)` | 无命中，预期 exit 1 |
| Sync model/controller 中搜索 WiFi Credentials、SSID、Password 写入 | 无命中，预期 exit 1 |
| WiFiGatewayViewController 中搜索直接发送 `gatewayMQTTConnectInfoSet` | 无命中，预期 exit 1 |

GatewayViewController 中仍保留其他 Gateway 使用的 legacy `gatewayMQTTConnectInfoSet` 直发路径；WiFi Gateway 已通过 override 进入新的 Server Recovery，不会执行该 legacy 分支。

### 本地化与差异检查

| 命令 | 结果 |
| --- | --- |
| `plutil -lint SunSmart/en.lproj/Localizable.strings` | OK |
| `plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings` | OK |
| `git diff --check 47f12288..9fdb6701` | 无空白错误 |

新增文案：

| English | 简体中文 |
| --- | --- |
| `Server Authorization` | `服务器授权` |

## iPhoneOS 构建

所有命令均直接使用 `xcodebuild`、Debug、generic iPhoneOS 和 `CODE_SIGNING_ALLOWED=NO`，没有使用 Simulator、shell wrapper 或日志重定向。

| Scheme | 结果 |
| --- | --- |
| SunSmart | `BUILD SUCCEEDED`，exit 0 |
| Archipelago | `BUILD SUCCEEDED`，exit 0 |
| SLG Sync Plus | `BUILD SUCCEEDED`，exit 0 |
| SylSmart | `BUILD SUCCEEDED`，exit 0 |

构建解析到本地 `/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`；本轮没有修改 NordicSigMeshSDK，也没有新增 Auth 信息。

## API 合同确认

状态：未执行。

需要服务端或真实环境确认：对已经注册、但 App 本地 MQTT credentials 丢失的 Gateway，再次调用 Gateway Register 时，是否返回完整 credentials，或是否能够重新签发 credentials。

当前 App 行为：

- 重复注册返回完整 credentials：保存并继续 Server Information 下发；
- 本地已有有效 credentials，但更新响应未重复返回：保留现有目标；
- 本地没有 credentials，响应也没有完整字段：Server Authorization 失败，Repair 不成功；
- App 不生成或猜测 MQTT password。

如果服务端不支持重复返回或重新签发，受影响的历史 Gateway 仍需要服务端能力配合，iOS 无法独立恢复已经丢失的 password。

## 真机验收矩阵

本轮没有连接目标 WiFi Gateway，以下场景均未执行：

| 场景 | 状态 | 验收重点 |
| --- | --- | --- |
| Adding 刚开始即断电，重新上电后在线 Repair | 未执行 | Authorization、Server Information、Final Verification 全部成功后才提示成功 |
| 手机离线、BLE/Mesh Online 时 Repair | 未执行 | Mesh 任务继续；Authorization Failed；服务器后继 Skipped；整体失败 |
| 离线 Repair 后恢复网络并 Retry | 未执行 | 已成功 Mesh 任务不重跑，只执行服务器失败链和验证 |
| 正常详情手动 Authorize | 未执行 | 进入服务器 Sync 子链；成功后页面警告消失 |
| Authorize 前存在自动 WiFi acknowledged 请求 | 未执行 | 等待前置请求结束，不并发发送 Mesh 请求 |
| Server Information 下发期间 Gateway 断电 | 未执行 | 当前任务失败，可 Retry，不提前成功 |
| 后台 syncGateway 返回有效 credentials | 未执行 | MQTT 信息持久化，不被丢弃 |
| 已注册 Gateway 重复 Gateway Register | 未执行 | 返回或重新签发完整 credentials |

## 未完成项与风险

1. Gateway Register 重复注册合同尚未确认，是历史 credentials 已丢失设备能否恢复的关键外部依赖。
2. 真机断电、离线 Retry、Authorize 与 WiFi acknowledged 请求等待尚未执行。
3. 当前工程没有可用的 App XCTest target；响应解析和任务依赖使用源码契约、iPhoneOS build 与待执行真机矩阵验证。
4. 四品牌构建存在工程既有 warning，本轮未新增 compile error。

## 提交记录

- `c0b7d7c7 feat: add gateway server authorization service`
- `0faebc02 fix: persist gateway server authorization data`
- `0a309ed9 fix: require server information in gateway recovery`
- `9fdb6701 fix: recover WiFi gateway server authorization`
