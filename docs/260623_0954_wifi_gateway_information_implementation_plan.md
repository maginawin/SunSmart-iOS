# WiFi Gateway Information 实现计划

## 目标

让 WiFi Gateway 右上角菜单中的 Information 点击后跳转到设备 Information 页面，复用普通 light 设备的信息内容，但隐藏 group 和 scene。

## 改动文件

- `SunSmart/Main/Device/Controller/DeviceInformationViewController.swift`
  - 增加 group section 显示开关，默认保持显示。
  - 由 group/scene 两个开关生成 `sections`。
- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - Information 菜单闭包 push `DeviceInformationViewController`。
  - WiFi Gateway 调用时关闭 group 和 scene。
- `scripts/check_wifi_gateway_menu_icons.sh`
  - 扩展静态校验，覆盖 Information 菜单跳转及隐藏 group/scene 参数。

## 执行步骤

1. 先扩展 `scripts/check_wifi_gateway_menu_icons.sh`，检查 WiFi Gateway Information 菜单是否 push `DeviceInformationViewController` 并关闭 group/scene。
2. 运行 `bash scripts/check_wifi_gateway_menu_icons.sh`，确认当前代码失败，失败点应是 Information 跳转缺失。
3. 修改 `DeviceInformationViewController`，新增默认开启的 group section 参数，并保持现有调用默认行为不变。
4. 修改 `WiFiGatewayViewController`，Information 菜单点击后 push `DeviceInformationViewController(node: self.node, showsGroupSection: false, showsSceneSection: false)`。
5. 重新运行静态校验，确认通过。
6. 运行 `git diff --check` 和 iPhoneOS `xcodebuild` 验证。
7. 因共享页面被修改，补跑 `Archipelago`、`SLG Sync Plus`、`SylSmart` 的 iPhoneOS 构建。

## 边界

- 不修改 Delete、Identify、Diagnosis、WiFi DFU 的行为。
- 不新增 WiFi Gateway 专属字段。
- 不修改 legacy 4G Gateway 页面。
