# Simulate Fault HTTP API 实现总结

## 实现范围

- 新增 `POST /temporary/device/alert/add`，沿用 `UserData.currentServerRegion.baseURL`，最终 URL 保留 `/srv2` 前缀。
- 请求体使用独立的强类型 payload，固定包含 `siteId`、`spaceId`、`nodeId`、`alert`、`nodeAddress`、`source`、`desc`、`location`、`datetime` 九个字段。
- `nodeId` 使用 Node UUID，`nodeAddress` 使用四位大写十六进制 Mesh 地址。
- `source` 固定为 `ios`，`desc` 与 `location` 固定为空字符串。
- `datetime` 在按钮点击时生成，使用 UTC 0、Gregorian、`en_US_POSIX` 和 `yyyy-MM-dd HH:mm:ss` 格式。
- Simulate Fault 弹窗内九个按钮直接发送对应 HTTP 请求，不发送 Mesh 命令，也不向设备页面回传事件。
- 请求期间复用窗口级 XWHUD，展示本地化的 `Sending...`，并通过 `isSending` 阻止重复请求；完成后复用现有成功或失败 HUD，原 Simulate Fault 弹窗保持打开。
- 新增请求文件已加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

## Alert 映射

| UI 区域 | 按钮 | type | status | level |
| --- | --- | --- | --- | --- |
| Motion Sensor | Normal | `motion_sensor` | `normal` | `3` |
| Motion Sensor | Fault | `motion_sensor` | `fault` | `3` |
| Photocell Sensor | Normal | `photocell_sensor` | `normal` | `2` |
| Photocell Sensor | Fault | `photocell_sensor` | `fault` | `2` |
| Light Status | Normal | `light_status` | `normal` | `1` |
| Light Status | Dim | `light_status` | `dim` | `1` |
| Light Status | Flicker | `light_status` | `flicker` | `1` |
| Light Status | Dim Flicker | `light_status` | `dim_flicker` | `1` |
| Light Status | Off | `light_status` | `off` | `1` |

## 自动验证结果

- `SimulateFaultModelTests`：通过。覆盖九种 alert 映射、九字段 body 和 UTC 时间格式。
- `scripts/check_simulate_fault.sh`：通过。覆盖 API path、payload、HUD、重复点击保护、入口参数、四 target 引用及无 Mesh 命令约束。
- `scripts/check_device_menu_icons.sh`：通过。
- `plutil -lint SunSmart.xcodeproj/project.pbxproj`：通过。
- `git diff --check`：通过。
- iPhoneOS Debug 构建：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 均成功。

## 建议手工验收

1. 使用 owner/editor 权限进入 light 设备页面，打开 Simulate Fault。
2. 逐类点击代表性按钮，确认立即出现 `Sending...`，等待期间连续点击不会产生第二个请求。
3. 抓取请求确认 URL 含 `/srv2/temporary/device/alert/add`，body 字段及 alert 映射符合上表，时间为 UTC 0。
4. 分别模拟成功与失败响应，确认提示正确且 Simulate Fault 弹窗保持展示。
5. 在请求过程中撤销编辑权限，确认页面权限保护仍生效。
