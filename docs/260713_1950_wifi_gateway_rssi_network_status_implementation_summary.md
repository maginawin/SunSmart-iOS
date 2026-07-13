# WiFi Gateway RSSI 网络状态更新实现总结

## 实现范围

- 为 CID `0x0A78`、PID `0x2721` 的 WiFi Gateway 更新 `43 0F` RSSI 应答解析。
- SDK 支持新版五字节应答 `43 0F <rssi_status> <rssi> <network_status>`，并保留对旧版四字节成功应答 `43 0F 00 <rssi>` 的兼容。
- App 在 `rssi_status = 0x00` 时根据 `network_status` 更新 WiFi Gateway 页面顶部状态：
  - `NORMAL`：继续显示原有 RSSI 分级 `Excellent / Good / Poor / Bad`。
  - `UNAVAILABLE`：显示 `No Internet`，保留 RSSI 对应图标。
  - `UNKNOWN` 或保留值：显示 `Unknown`，保留 RSSI 对应图标。
  - 旧固件未携带 `network_status`：继续显示原有 RSSI 分级，语义上按 Internet 状态未上报处理。
- `rssi_status != 0x00` 时保持原有 `No Signal` 行为，不使用可选的 `network_status`。
- 轮询改为应答驱动：首次立即查询；收到响应或超时后等待 5 秒再发起下一轮；单轮超时为 2 秒；页面不可见、设备离线、未绑定 AppKey 或未连接 WiFi 时停止轮询。
- 新增英文、简体中文本地化：`No Internet / 无互联网连接`、`Unknown / 未知`。

## 协议兼容与边界

- 仅接受四字节或五字节 RSSI 应答，少于四字节或多于五字节均视为格式非法。
- `rssi_status = 0x00` 时校验 RSSI 为 `-127...0 dBm`。
- 五字节应答中的网络状态按类型解析为 `normal`、`unavailable`、`unknown` 或保留值。
- 四字节成功应答解析为网络状态未上报，避免把旧固件误判为 `NORMAL` 或 `UNAVAILABLE`。
- 非成功 RSSI 状态接受四字节和五字节格式，但忽略网络状态，保持现有 UI 行为。

## 验证结果

以下契约脚本均通过：

- `scripts/check_wifi_gateway_wifi_status_header.sh`
- `scripts/check_wifi_gateway_network_connectivity.sh`
- `scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
- `scripts/check_wifi_gateway_sig_mesh_status_header.sh`
- `scripts/check_wifi_gateway_repair_recovery.sh`
- `scripts/check_wifi_gateway_server_information_recovery.sh`

以下 iPhoneOS Debug 构建均通过：

- NordicSigMeshSDK Demo
- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

App 仓库与 NordicSigMeshSDK 仓库的 `git diff --check` 均通过，最终工作区状态均为干净。

## 已知验证限制

`swift test --filter WiFiGatewayVendorMessageTests.testRSSIStatusResponseParsing` 在 macOS SwiftPM 测试环境中仍会于编译测试目标前被 SDK 既有的 UIKit 依赖阻断，错误为 `no such module 'UIKit'`，位置为 `MeshDeviceProvisioningManager.swift:8`。本次改动已通过 SDK Demo 与四个 App target 的真实 iPhoneOS 编译验证。

## 提交记录

- NordicSigMeshSDK：`fb36121 feat: add wifi gateway network status`
- App：`0387e752 feat: show wifi gateway network status`
- App：`4f1e8106 fix: align wifi rssi polling timing`
