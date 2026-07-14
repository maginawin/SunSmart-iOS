# WiFi Gateway Current Target Version 设计

## 背景与目标

WiFi Gateway 的设备身份固定为 CID `0x0A78`、PID `0x2721`。用户从 WiFi Gateway 页面右上角点击 `WiFi DFU` 后进入 `WiFi Firmware Update` 页面。

当前 `WiFiFirmwareUpdateViewController` 在初始化数据和 `displayedCurrentTargetVersion` 中均硬编码 `0.0.1`，因此页面无法反映正式固件或 dev 固件查询的真实结果。与此同时，共享 `FirmwareVersionViewController` 使用同一个 `displayedCurrentTargetVersion` 同时完成标签展示和新旧版本比较；如果仅把该属性改成服务器版本，会发生服务器版本与自身比较，页面错误显示为最新版本并禁用 `UPGRADE`。

本次目标是让 WiFi Firmware Update 页面的 `Current target version` 展示本次查询实际获得的新固件版本，并将展示语义与共享页面的版本比较语义解耦。

## 确认后的产品行为

`Current target version` 按以下规则展示：

| 查询结果 | 展示值 |
| --- | --- |
| 正式环境返回有效新固件 | 返回的新固件版本 |
| dev 环境返回有效新固件 | 返回的新固件版本 |
| 服务器没有固件 | `None` |
| 网络或请求失败 | `None` |
| 响应缺少必要字段 | `None` |
| 响应中的 PID 无效或不是 `0x2721` | `None` |

每次正式查询、Refresh 或切换到 dev 查询时，都以本次请求结果为准。请求开始前清除 WiFi 页面的上一次服务器固件结果，因此后续查询失败时不得继续展示旧版本。

## 方案选择

采用方案 A：在共享固件页面增加最小语义钩子，由 WiFi 固件页面覆盖差异行为。

未采用的方案：

- 不在 `WiFiFirmwareUpdateViewController` 中复制整套请求和 UI 更新逻辑，避免与共享固件页面产生重复实现。
- 不在本次引入完整固件查询状态模型，避免扩大改动范围。

## 架构设计

### 共享页面

在 `FirmwareVersionViewController` 增加两个可覆盖能力：

1. 请求开始前是否清除已有 `type.serverData`。默认关闭，以保持现有 BLE/Mesh 固件页面行为。
2. 已获得有效 `FirmwareServerData` 时，是否将其视为可用的新固件。默认继续使用现有数值版本比较逻辑。

`updateUI()` 不再直接内联使用 `displayedCurrentTargetVersion` 判断服务器版本是否更新，而是调用新的可覆盖判断能力。共享页面的默认实现仍比较服务器版本和当前展示/缓存版本，因此既有固件页面行为不变。

### WiFi 固件页面

`WiFiFirmwareUpdateViewController` 执行以下覆盖：

- 初始化 `FirmwareUpdateTypeData` 时不再传入固定 `0.0.1`，`targetVersion` 使用 `nil`。
- `displayedCurrentTargetVersion` 返回当前有效的 `type.serverData?.version`。
- 开启“请求前清除服务器固件结果”。
- 只要本次请求解析出有效 `FirmwareServerData`，就视为获得新固件。

这样，正式环境和 dev 环境复用同一数据源。dev 查询仍由现有 Beta Testing Environment 入口将 `isTesting` 设置为 `true`，网络请求继续添加 `profile=dev`，无需新建 dev 专用字段或缓存。

## 数据流

1. 用户进入 `WiFi Firmware Update` 页面。
2. 页面发起 `manufacturerId=0A78`、`deviceType=2721`、`customerId=wifi` 的最新固件请求。
3. 请求前清除上一次 `type.serverData`。
4. 正式查询不携带 `profile`；dev 查询携带 `profile=dev`。
5. 响应通过现有必要字段和 PID 校验后，转换为 `FirmwareServerData`。
6. 有有效数据时，`Current target version` 展示 `FirmwareServerData.version`，页面显示新固件信息并启用 `UPGRADE`。
7. 没有有效数据时，`Current target version` 展示现有本地化值 `None`。

## 状态与错误处理

- `resourceNotFound`：沿用现有“服务器没有固件”状态，`Current target version` 为 `None`，`UPGRADE` 禁用。
- 其他请求失败：沿用现有 `Network error` 和 Refresh 按钮，`Current target version` 为 `None`，`UPGRADE` 禁用。
- 成功响应但字段缺失或 PID 不匹配：按无有效查询结果处理，`Current target version` 为 `None`，保持现有错误/刷新展示路径。
- 正式查询成功后切换 dev：先清除正式版本；dev 成功后展示 dev 版本，dev 失败则展示 `None`，不得回退展示正式版本。
- Refresh 失败：不得保留刷新前版本，展示 `None`。

`UPGRADE` 点击后继续使用现有 `under_development` 提示。本次不实现下载、传输、升级进度或失败恢复。

## 影响范围

计划修改：

- `SunSmart/Main/Firmware/Controller/FirmwareVersionViewController.swift`
- `SunSmart/Main/Firmware/Controller/WiFiFirmwareUpdateViewController.swift`
- `scripts/check_wifi_gateway_firmware_update.sh`

明确不修改：

- WiFi Gateway 入口和右上角菜单结构。
- Firmware version history。
- `customerId=wifi` 和 `profile=dev` 请求规则。
- Beta Testing Environment 密码与入口。
- BLE、Mesh Firmware Update 的默认版本比较和缓存行为。
- 真实 WiFi 固件升级逻辑。
- 本地化资源；`None` 继续复用现有 `none` key。

## 测试与验收

### 聚焦静态契约

扩展 `scripts/check_wifi_gateway_firmware_update.sh`，至少守住：

- WiFi 固件页面不再包含 `0.0.1` 固定版本。
- WiFi 初始化的 `targetVersion` 为 `nil`。
- WiFi 展示值来自当前 `type.serverData?.version`。
- WiFi 请求前清除旧服务器固件结果。
- WiFi 获得有效服务器固件后独立判定为可升级。
- 共享固件页面默认仍保留既有版本比较逻辑。
- `customerId=wifi`、dev 查询、历史版本和 `UPGRADE` placeholder 契约保持不变。

### 回归与构建

- 运行现有 WiFi Gateway 专项检查脚本。
- 运行 `git diff --check`。
- 串行执行以下 Debug iPhoneOS 构建，使用 `CODE_SIGNING_ALLOWED=NO`：
  - `SunSmart`
  - `Archipelago`
  - `SLG Sync Plus`
  - `SylSmart`

## 验收标准

- 初次正式查询成功时，`Current target version` 展示正式固件版本。
- dev 查询成功时，展示 dev 固件版本。
- 服务器无固件、请求失败或格式无效时，展示 `None`。
- 查询失败后不会残留之前成功查询的版本。
- 有有效固件结果时 `UPGRADE` 可用；无有效结果时不可用。
- 其他固件页面和四个品牌 target 均无行为或构建回归。
