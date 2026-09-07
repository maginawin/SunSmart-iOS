# Gateway 页面 4G DFU 支持范围分析

- 分析日期：2026-09-07
- 工作区：`/Users/maginawin/Developer/iOS/YKH/sun-smart-worktrees/fix`
- 分支及提交：`fix` / `fd520c93`
- 范围：当前源码中 Gateway 页面右上角菜单的 DFU 入口；不据此判断设备固件或其他工作区的升级能力。

## 结论

当前页面中的 4G 网关，包括题述 PID `0x2703`，点击 `4G DFU` 均只显示开发中提示，不进入升级页面，不查询升级固件，也不发送 DFU 命令。当前工作区没有任何 4G 网关通过此菜单接入实际 4G DFU 流程。

实际提示文案：

- 简体中文：`哎呀！开发中。`
- 英文：`Oops! Under development.`

## 调用链与证据

1. `SunSmart/Main/Site/Controller/SiteViewController.swift:3195`：仅 `node.isWiFiGateway` 进入 `WiFiGatewayViewController`，其他网关进入 `GatewayViewController`。
2. `SunSmart/Common/Data/MeshNetwork+SunSmart.swift:1905`、`:1923`：WiFi 网关要求 CID `0x0A78`，且 PID 属于仅含 `0x2721` 的集合；PID `0x2703` 不符合。
3. `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:137`：默认固件类型固定返回 `.fourG`。
4. `SunSmart/Main/Device/Gateway/Model/GatewayMenuPolicy.swift:24`：按 WiFi/4G 类型生成 DFU 菜单项，没有 4G PID、固件版本或能力白名单判断；删除权限等参数不改变 DFU 类型。
5. `SunSmart/Main/Device/Gateway/Controller/GatewayViewController.swift:307`：点击 `4G DFU` 调用 `performGatewayDFUAction()`。
6. 同文件 `:366`：该方法仅调用 HUD 展示 `under_development`，没有条件分支或升级跳转。
7. `SunSmart/zh-Hans.lproj/Localizable.strings:833`、`SunSmart/en.lproj/Localizable.strings:814`：确认实际本地化文案。
8. `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift:284`：唯一覆写该动作的实现创建 `WiFiFirmwareUpdateViewController(node:)` 并跳转，属于 WiFi DFU。

## 当前设备范围

以下内置网关配置的 CID 均为 `0x0A78`：

| PID | 内置型号或身份 | 当前右上角菜单行为 |
| --- | --- | --- |
| `0x1701` | `SR-BL9036T-GW-WP4G` | `4G DFU` → 开发中 |
| `0x1702` | `SR-BL9036T-GW-WP4G` | `4G DFU` → 开发中 |
| `0x2701` | `SR-BL9036T-GW-WP4G` | `4G DFU` → 开发中 |
| `0x2702` | `SR-BL9036T-GW-WP4G` | `4G DFU` → 开发中 |
| `0x2711` | `SR-BL9036T-GW-WP4G` | `4G DFU` → 开发中 |
| `0x2703` | 内置配置未列出；按题述已作为 4G 网关进入页面 | `4G DFU` → 开发中 |
| `0x2721` | WiFi 网关，内置型号 `SR-BL-AB-XX` | `WiFi DFU` → 实际升级页面 |

内置配置依据：`SunSmart/devices_config.json:653`、`:1063`、`:1072`、`:1161`、`:1242`、`:1260`。

`SunSmart/Main/Site/Controller/SitesViewController.swift:475` 从服务器 `devicesConfig` 读取并替换运行时支持设备列表，因此内置 JSON 不是线上全部型号清单。此次没有读取线上响应，不能独立确认线上对 `0x2703` 的识别配置。但在题述已经进入 4G Gateway 页面的前提下，点击行为明确，不受这个不确定性影响。其他运行时识别出的非 WiFi 网关进入相同页面后，也使用同一个开发中占位动作。

## 验证与边界

- 全量搜索当前 `SunSmart` Swift 源码中的 `performGatewayDFUAction`、`gatewayFirmwareKind`、Gateway 子类及 4G DFU 入口，确认实际跳转仅由 WiFi 子类提供。
- 当前源码未找到其他工作区曾使用的 `GatewayFirmwareDFUProfile`；历史实现不能视为已集成到本工作区。
- 已运行 `bash scripts/check_wifi_gateway_menu_icons.sh`，结果 PASS；现有检查明确要求 4G 保留开发中提示、WiFi 使用升级页面。
- 本次仅新增分析文档，未修改业务代码；未运行构建或真机升级。结论针对当前源码菜单行为，不代表硬件不支持其他升级途径，也不宣称 WiFi 真机升级已验收。
