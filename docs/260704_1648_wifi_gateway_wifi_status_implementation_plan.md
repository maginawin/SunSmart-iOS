# WiFi Gateway Wi-Fi Status View 实施计划

## 目标

将 WiFi Gateway 顶部右侧 4G signal view 替换为 Figma 对齐的 Wi-Fi status view，并在 Wi-Fi connection status 为 connected 时每 2 秒刷新 Wi-Fi RSSI。

## 文件

- 修改 `SunSmart/Main/Device/Gateway/View/GatewayInformationHeaderView.swift`
  - 复用 `GatewayHeaderStatusItemView`。
  - 保留 4G Gateway 默认 signal UI。
  - 为 WiFi Gateway 增加右侧 Wi-Fi status UI 配置与更新入口。
- 修改 `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - 管理 Wi-Fi RSSI timer。
  - 读取 `.wifiGatewayRSSIStatus`。
  - 将 RSSI 映射为图片与文案。
  - 在 connection status 状态转移时启动或停止 RSSI 刷新。
- 修改 `SunSmart/en.lproj/Localizable.strings`
  - 增加 Wi-Fi status 文案。
- 修改 `SunSmart/zh-Hans.lproj/Localizable.strings`
  - 增加 Wi-Fi status 文案，`Not Connected` 翻译为 `未连接`。
- 新增 `scripts/check_wifi_gateway_wifi_status_header.sh`
  - 覆盖右侧 Wi-Fi status、RSSI 轮询、阈值、停止条件、本地化和资源名。
- 更新 `docs/260704_1642_wifi_gateway_wifi_status_plan.md`
  - 记录确认结果：使用 `wifi_not_connected`，zh-CN `未连接`。

## 步骤

1. 新增静态检查脚本并运行，预期当前代码失败。
2. 更新 header：
   - 增加右侧 status style。
   - WiFi Gateway 设置右侧为 Wi-Fi status。
   - 默认 4G Gateway 保持旧 signal view。
3. 更新 controller：
   - 增加 `wifiRSSIStatusTimer`。
   - 增加 `refreshWiFiRSSIStatus()`。
   - 增加 `applyWiFiRSSIStatus(_:)` 和 RSSI 映射。
   - `.connected` 时先 refresh 一次，再启动 2 秒 timer。
   - 非 `.connected`、Gateway 离线、disconnect/clear、离开页面和 deinit 时停止 timer。
4. 补本地化。
5. 运行验证：
   - `bash scripts/check_wifi_gateway_wifi_status_header.sh`
   - `bash scripts/check_wifi_gateway_sig_mesh_status_header.sh`
   - `bash scripts/check_wifi_gateway_network_connectivity.sh`
   - `bash scripts/check_wifi_gateway_menu_icons.sh`
   - `bash scripts/check_wifi_gateway_info_rows_hidden.sh`
   - `git diff --check`
   - `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
