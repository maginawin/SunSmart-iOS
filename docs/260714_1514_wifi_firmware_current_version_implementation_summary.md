# WiFi Firmware Current Version 实现总结

## 实现结果

已完成 WiFi Gateway `43 14` firmware version 查询协议的 SDK 与 App 接入。

- SDK 新增精确的 `43 14` GET 编码，以及 `43 14 <ret> ...` response routing。
- SDK 对成功响应执行严格校验：`version_len` 仅允许 `1...32`，版本内容仅允许可展示 ASCII `0x20...0x7E`，长度不符或存在 trailing bytes 时拒绝解析。
- SDK 为 `0x01...0x04` 和未知 ret 保留 typed result；response matching 同时校验来源地址和 `43 14` 子码。
- App 从 WiFi Gateway 菜单进入 WiFi Firmware Update 页面时传入当前网关 `Node`。
- 页面进入后立即显示 `Current version: Loading...`，并与云端 New version 请求并行发送 Mesh 查询；Refresh 同时重新请求两者。
- 查询成功后展示网关实时返回的版本；失败、busy、deadline、非法响应或 App 超时时展示 `Failed`。
- 版本比较仅移除开头一个 `v` 或 `V`，然后使用项目现有 `.numeric` 规则；仅 New version 严格高于 Current version 时启用 `UPGRADE`。
- Current version 处于 loading 或 failed 时，`UPGRADE` 保持禁用；真实 WiFi DFU 仍沿用现有 `under_development` 行为。
- 查询结果只保存在页面内存状态，不写入 `Node`、数据库或云端缓存。

## 主要文件

### NordicSigMeshSDK

- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorGet.swift`
- `Sources/NordicSigMeshSDK/MeshLib/Message/Vendor/SunricherVendorStatus.swift`
- `Tests/NordicSigMeshSDKTests/WiFiGatewayVendorMessageTests.swift`

SDK commit：`55a1500 feat: add wifi firmware version query`

### App

- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
- `SunSmart/en.lproj/Localizable.strings`
- `SunSmart/zh-Hans.lproj/Localizable.strings`
- `scripts/check_wifi_gateway_firmware_update.sh`
- `scripts/check_wifi_gateway_menu_icons.sh`

App commit：`bcd39084 feat: show wifi firmware current version`

## 计划偏差

原计划列出修改 `VendorServerDelegate.swift`，实施时通过 iPhoneOS 编译确认该 delegate 的 switch 只处理 `VendorFunctionSet`。`43 14` 是 GET 查询，其结果不应进入 SET delegate 或持久化缓存，因此最终未修改该文件；response 由现有 `MeshMessageHandle` 与 `SunricherVendorStatus` 链路返回页面。

## 验证结果

### SDK 测试与构建

- `swift test --filter WiFiGatewayVendorMessageTests`：测试 target 在执行测试前被仓库既有的 macOS SwiftPM blocker 阻断，错误为 `MeshDeviceProvisioningManager.swift:8:8: no such module 'UIKit'`。这不是本次功能引入的编译错误。
- 新增 XCTest 覆盖 GET 编码、成功长度边界、ret 映射、非法长度、非法 ASCII、trailing bytes、响应子码与来源地址匹配。
- NordicSigMeshSDK iPhoneOS Debug build：成功。

### App 静态回归

以下 12 个脚本全部通过：

- `check_gateway_activate_header_layout.sh`
- `check_gateway_associated_spaces_deferred_save.sh`
- `check_wifi_gateway_apn_removed.sh`
- `check_wifi_gateway_disconnect_clear_credentials.sh`
- `check_wifi_gateway_firmware_update.sh`
- `check_wifi_gateway_info_rows_hidden.sh`
- `check_wifi_gateway_menu_icons.sh`
- `check_wifi_gateway_network_connectivity.sh`
- `check_wifi_gateway_repair_recovery.sh`
- `check_wifi_gateway_server_information_recovery.sh`
- `check_wifi_gateway_sig_mesh_status_header.sh`
- `check_wifi_gateway_wifi_status_header.sh`

### App iPhoneOS 构建

使用 Debug、generic iPhoneOS destination、`CODE_SIGNING_ALLOWED=NO` 验证，以下 scheme 全部成功：

- `SunSmart`
- `Archipelago`
- `SLG Sync Plus`
- `SylSmart`

构建中仅出现项目既有 warning，没有本次改动引入的 error。

## 边界说明

- 协议功能仅作用于 WiFi Gateway CID `0x0A78`、PID `0x2721` 的现有入口。
- App Mesh timeout 为 10 秒；网关协议内部 5 秒总截止仍由网关以 ret `0x04` 表达。
- 本次不实现固件下载、传输或升级执行流程。
