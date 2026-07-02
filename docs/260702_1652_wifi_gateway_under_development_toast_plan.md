# WiFi Gateway Under Development Toast Plan

## 背景

WiFi Gateway `CID 0x0A78 / PID 0x2721` 的右上角菜单在 `WiFiGatewayViewController.moreClick()` 中组装。当前 `WiFi DFU` 和 `Diagnosis` 菜单项为占位空闭包，点击后没有用户反馈。

## 目标

- 点击 `WiFi DFU` 后提示现有文案 `under_development`。
- 点击 `Diagnosis` 后提示现有文案 `under_development`。
- 英文环境提示为 `Oops! Under development.`。
- 不新增本地化 key，不改 4G Gateway，不改 `Delete` / `Information` / `Identify` 行为。

## 实施步骤

1. 扩展 `scripts/check_wifi_gateway_menu_icons.sh`，断言 WiFi Gateway controller 中存在两处 `under_development` toast。
2. 先运行脚本确认当前实现失败。
3. 修改 `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`，在 `WiFi DFU` 和 `Diagnosis` 点击闭包中调用 `XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)`。
4. 运行脚本、`bash -n`、`git diff --check` 验证。
5. 如脚本和静态检查通过，再运行 `SunSmart` iPhoneOS build 作为编译验证。
