# WiFi Gateway No Internet 图标修复实施总结

## 1. 实施结果

已按确认的方案 A 完成修复。

WiFi Gateway 页面收到 `networkStatus == .unavailable` 时，顶部 Wi-Fi 状态现在固定使用：

- 图标：`wifi_no_internet`
- English 文案：`No Internet`
- 简体中文文案：`无互联网连接`

图标不再受同一响应中的 RSSI 强弱或 RSSI 读取结果影响。

## 2. 改动内容

### App UI 映射

修改 `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`：

- 在 `WiFiHeaderStatus` 中新增语义化的 `noInternet` 状态；
- `noInternet` 使用现有 `wifi_no_internet` asset 和 `wifi_status_no_internet` 本地化 key；
- `networkStatus == .unavailable` 时直接展示 `noInternet`。

保持以下行为不变：

- `.normal` 继续使用 Excellent、Good、Poor、Bad 或 No Signal；
- `.unknown/.reserved` 继续显示 `Unknown` 并保留当前图标；
- Not Connected 和 Not Configured 保持现状。

### Focused contract

修改 `scripts/check_wifi_gateway_wifi_status_header.sh`：

- 检查 No Internet 图标与文案必须作为同一个语义状态存在；
- 检查 `.unavailable` 必须使用该状态；
- 检查 `wifi_no_internet` 的 1x、2x、3x 资源完整。

未修改 SDK、header view、图片资源、本地化文件、target 配置或依赖。

## 3. TDD 证据

### RED

只补充 focused contract 后执行：

`bash scripts/check_wifi_gateway_wifi_status_header.sh`

结果按预期失败：

`FAIL: No Internet must use the wifi_no_internet asset and localized No Internet status.`

失败原因是当前 controller 缺少 No Internet 图标映射，不是脚本错误或资源缺失。

### GREEN

完成最小 UI 映射修改后：

- `scripts/check_wifi_gateway_wifi_status_header.sh`：通过；
- `scripts/check_wifi_gateway_network_connectivity.sh`：通过；
- `WiFiGatewayV19TimingTests`：通过；
- `WiFiGatewayConnectionPollingReducerTests`：通过。

## 4. 构建验证

均使用 Debug、generic iPhoneOS、`CODE_SIGNING_ALLOWED=NO`：

| Scheme | 结果 |
|---|---|
| SunSmart | BUILD SUCCEEDED |
| Archipelago | BUILD SUCCEEDED |
| SLG Sync Plus | BUILD SUCCEEDED |
| SylSmart | BUILD SUCCEEDED |

构建解析并使用本地：

`/Users/maginawin/Developer/iOS/YKH/nordic-sig-mesh-sdk`

构建中出现的既有警告：

- Archipelago 与 SylSmart 的 Info.plist 位于 Copy Bundle Resources；
- SLG Sync Plus / SylSmart 存在 FSCalendar duplicate build file；
- AppIntents metadata 因无 AppIntents dependency 跳过。

这些警告与本次 No Internet 图标映射无关，未影响构建结果。

## 5. 验收边界

已验证：

- 源码契约明确约束 `.unavailable` 使用 `wifi_no_internet`；
- 公共 asset catalog 能被四个品牌 target 编译；
- App 与本地 SDK 在四个品牌 scheme 下均能完成 generic iPhoneOS 构建。

尚未验证：

- 真实 Gateway 返回 `0x43/0x0F` 且 `network_status = 0x01` 时的页面视觉；
- 真机上 `wifi_no_internet` 图片的最终显示效果。

因此，自动检查和构建已经覆盖代码与资源集成，但不能替代真实 Gateway 和真机 UI 验收。
