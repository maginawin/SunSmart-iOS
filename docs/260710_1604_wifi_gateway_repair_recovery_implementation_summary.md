# WiFi Gateway Repair 完整恢复实施总结

## 结论

已按方案 A 完成 WiFi Gateway（CID `0x0A78`、PID `0x2721`）Repair 完整恢复实现：Repair 页面隐藏底部 SAVE，点击 Repair 后进入一次自动启动的 Sync 页面；恢复流程先补齐 Composition 与 Key Bind，再执行 Gateway 业务配置，并以 Key Bind 完成且 Gateway diff 为空作为最终成功条件。

本轮静态契约检查、凭据排除审计、本地化检查和四个品牌 target 的 generic iPhoneOS 构建均通过。由于本轮没有连接目标网关，断电阶段、蓝牙在线恢复、失败重试和 Repair 后页面状态仍需按文末矩阵进行真机验收，不能仅依据构建结果判定现场问题已经验证通过。

## 实施内容

### Repair 页面状态与导航

- WiFi Gateway 处于 `The device needs to be repaired.` 状态时隐藏底部 SAVE。
- 已配置状态恢复显示 SAVE；页面从 Sync 返回时重新读取 Node 状态、刷新页面与按钮状态。
- WiFi Gateway 的 Repair 不再调用父类 `repairDevices` 与 Window 级 Repairing HUD，而是进入 Gateway Recovery Sync 页面。
- `Repair` 触发的恢复自动开始；`Devices not synced` 入口保留原有手动开始行为。
- 增加恢复页重复 push 门禁，避免连续点击或异步回调重复进入 Sync 页面。
- 父类仍保留旧 `repairDevices` 实现，其他 Gateway 的 Repair 行为不变。

### Composition 后动态强制初始化

- 新增 Repair Composition 阶段：本地缺少完整 Composition 时先发送 `ConfigCompositionDataGet`。
- 收到 `ConfigCompositionDataStatus` 后，动态追加完整 Repair 初始化消息。
- Repair 初始化强制重下发 NetKey、AppKey 与 Model App Bind，并继续执行普通配置中剩余的 Publish、Subscription、Sensor、Firmware 与 Hash 等配置。
- 为避免重复，普通配置追加阶段排除已经强制发送的 NetKey、AppKey 与 Model App Bind 消息。

### Gateway 业务恢复与最终成功语义

- Recovery 任务图继续覆盖 Association Project、Associated Spaces、Sync Spaces 与 Server Information。
- 新增 `Verify Configuration` 最终步骤。
- 最终成功必须同时满足 `node.isKeybindComplete == true` 和 `node.getNodeSyncGatewayData(gateway: gateway).isEmpty`。
- 任一前置依赖失败或最终差异未收敛时，不调用成功回调，避免返回详情页后再次展示 `Devices not synced` 却已经提示 Repair 成功。

### WiFi 自动请求串行与生命周期

- 页面出现、Proxy Online、Credentials 加载和 RSSI 定时刷新均增加 Key Bind 完成门禁。
- Repair 状态不会自动发送 WiFi Credentials、Connection Status 或 RSSI GET。
- 如果用户从 `Devices not synced` 入口进入时已有自动 WiFi 请求，继续沿用现有等待机制，在前置请求结束后再进入恢复页。
- Recovery 不写入、不清空 WiFi SSID 或 Password；WiFi Credentials Set/Clear 仍只属于用户主动连接或断开流程。

### 本地化与多 target 影响

- 新增英文 `Verify Configuration` 与简体中文 `验证配置`。
- 公共 Swift 源码被四个品牌 target 共享，因此对 SunSmart、Archipelago、SLG Sync Plus、SylSmart 均执行了 generic iPhoneOS 构建。
- 构建解析到本地 `NordicSigMeshSDK` 路径；本轮未修改该 SDK 文件，也未新增认证信息。

## 静态验证

### 聚焦脚本

| 命令 | 结论 |
| --- | --- |
| `bash scripts/check_wifi_gateway_repair_recovery.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_network_connectivity.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_sig_mesh_status_header.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_wifi_status_header.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_apn_removed.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_info_rows_hidden.sh` | PASS（exit 0） |
| `bash scripts/check_wifi_gateway_menu_icons.sh` | PASS（exit 0） |
| `bash scripts/check_gateway_associated_spaces_deferred_save.sh` | PASS（exit 0） |

### Builder、凭据与旧 Repair 路径审计

| 命令 | 结论 |
| --- | --- |
| `rg -n "func getForcedGateway\|func getGatewayRepair" SunSmart/Common/Data/Node+MessageHandles.swift` | 命中 forced Gateway、Repair Composition、Repair Initialization builders（exit 0） |
| `rg -n "wifiGatewayCredentials\|wifiGatewayCredentialsSet\|wifiGatewayCredentialsClear\|ssid\|password"`，范围限定为 Recovery builder、CellModel 与 Sync controller | 无命中，确认恢复链未包含 WiFi 凭据写入（预期 exit 1） |
| `rg -n "repairDevices\|showCustomHUD.*repairing\|Repairing" WiFiGatewayViewController.swift` | 无命中，WiFi Repair 不再走旧 HUD 流程（预期 exit 1） |
| `rg -n "repairDevices\(nodes: \[node\]" GatewayViewController.swift` | 父类旧 Repair 保留一个命中（exit 0） |

### 本地化与差异检查

| 命令 | 结论 |
| --- | --- |
| `plutil -lint SunSmart/en.lproj/Localizable.strings` | OK（exit 0） |
| `plutil -lint SunSmart/zh-Hans.lproj/Localizable.strings` | OK（exit 0） |
| `git diff --check 893df9a3..HEAD` | 无空白错误（exit 0） |
| `git status --short`，创建本总结前 | 工作区干净（exit 0） |

## iPhoneOS 构建

所有命令均使用 Debug、generic iPhoneOS 和 `CODE_SIGNING_ALLOWED=NO`，没有使用 Simulator 或 shell wrapper。

| Scheme | 结果 |
| --- | --- |
| SunSmart | 通过（exit 0） |
| Archipelago | 通过（exit 0） |
| SLG Sync Plus | 通过（exit 0） |
| SylSmart | 通过（exit 0） |

构建输出包含工程既有 warning，没有 compile error；四个 Scheme 均输出 `BUILD SUCCEEDED`。

## 尚需真机验收

本轮未连接 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway，以下项目均为未执行：

| 序号 | 场景 | 状态 | 验收重点 |
| --- | --- | --- | --- |
| 1 | Provisioning 完成但 Composition 未完成时断电 | 未执行 | 重新上电后展示 Repair；Repair 先获取 Composition，再继续初始化 |
| 2 | Composition 完成但 AppKey/Model Bind 未完成时断电 | 未执行 | Repair 强制补齐 Key/Bind，Initialize 不应被本地残留状态错误跳过 |
| 3 | Key Bind 完成但 Gateway append 未完成时断电 | 未执行 | Gateway 业务任务继续执行，最终 Verification 收敛 |
| 4 | Repair 页面 SAVE 隐藏 | 未执行 | `The device needs to be repaired.` 状态只显示 Repair，不显示底部 SAVE |
| 5 | Repair 只进入一次 Sync 页且可以退出 | 未执行 | 连续点击不重复 push；不会出现成功后仍停留在无限 Repairing HUD |
| 6 | Repair 成功后 `isKeybindComplete == true` | 未执行 | Key Bind 状态与设备真实 ACK 一致 |
| 7 | Repair 成功后 Gateway diff 为空 | 未执行 | 返回详情页不再展示 `Devices not synced` |
| 8 | Repair 失败、Offline、Retry 和返回页面状态 | 未执行 | 当前任务失败、后续依赖跳过、页面可退出、恢复供电后可重试 |
| 9 | WiFi Credentials 未被 Recovery 覆盖 | 未执行 | Repair 前后 SSID/Password 保持一致，不发送 Credentials Set/Clear |

真机验收还应覆盖 Associated Spaces 单项失败但其他独立任务继续执行的情况，并确认最终 Verification 因依赖失败而不产生总体成功提示。
