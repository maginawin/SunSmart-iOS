# WiFi Gateway Network Connectivity 设计方案

## 目标

在 WiFi Gateway 设备页面为 `CID 0x0A78 / PID 0x2721` 增加 `Network Connectivity` Section。该 Section 位于 `Activate` Section 下方、`Associated Spaces` Section 上方，用于展示手机当前 Wi-Fi SSID、输入 Wi-Fi 密码并模拟连接状态。

本期只做 UI 与本地状态模拟，不向 WiFi Gateway 下发 SSID 或 Password，不新增 Mesh、SDK、云端或协议同步行为。

## 范围

- 仅影响 `WiFiGatewayViewController` 对应的 WiFi Gateway 页面。
- 其他 Gateway 继续走 legacy `GatewayViewController` 行为，不展示该 Section。
- Password 每次打开 Gateway 页面默认为空，不持久化，不写入 `GatewayModel`、`Node` 或云端数据。
- Connect 行为仅在页面内存中切换按钮状态：可用、连接中、已连接、断开。
- `Disconnect` 仅清空本地 UI 中的 SSID 和 Password，不代表真实断开手机 Wi-Fi 或网关 Wi-Fi。

## 页面结构

当前 Gateway 页面由 table view sections 组成。设计上由父类开放 section 组成与 cell 配置 hook，默认 section 不变；`WiFiGatewayViewController` 在 `Activate` 后插入 `.networkConnectivity`。

目标顺序：

1. Name
2. Activate
3. Network Connectivity
4. Basic Information
5. Associated Spaces
6. Server Information

WiFi Gateway 仍不展示 APN Section。

## UI 规格

`Network Connectivity` Section 使用独立 cell/view 实现，避免把多行输入、刷新、按钮状态塞进现有单行 `CustomTableViewCell`。

Section header：

- title: `Network Connectivity`
- header 与 cell 间距按 Figma 保持 8pt 视觉间距。

Cell：

- 白色背景，圆角 10。
- 内边距 16。
- SSID 行：左侧 `SSID`，右侧只读输入框，高 32，宽度跟随现有 343pt 内容宽度适配；右侧显示 `select_wifi` 图标按钮。
- SSID 说明行：左侧展示 `Only supports 2.4GHz networks.`，右侧展示 `Refresh` 文本按钮。
- Password 行：左侧 `Password`，右侧密码输入框，高 32；右侧使用 `show_password` / `hide_password` 图标切换明文展示。
- 底部按钮：高 32，圆角 15，文字按状态显示 `Connect to Wi-Fi` 或 `Disconnect`；连接中状态显示居中 loading 图标。

Section 间距：

- Activate 下方到 Network Connectivity header 的外部间距保持 16。
- 有 header 的 Section 通过 header 自身高度适配额外标题间距，不额外写死全局 table 间距，避免影响其他 Gateway Section。

## 交互状态

页面初始状态：

- 尝试读取手机当前连接 Wi-Fi SSID。
- 成功读取则展示 SSID；读取不到则 SSID 为空。
- Password 为空。
- Connect 按钮禁用。

Password 输入：

- 只允许 ASCII 字符。
- 非 ASCII 输入不进入文本框，可给出轻提示。
- Password 长度大于等于 8 且当前不在 connecting / connected 状态时，Connect 按钮变为可用。
- Password 长度小于 8 时，Connect 按钮禁用。

Connect：

- 点击可用的 `Connect to Wi-Fi` 后进入 connecting 状态。
- connecting 状态下禁用 SSID 选择、Refresh、Password 输入、show/hide 切换和按钮重复点击。
- 2 秒后自动进入 connected 状态，按钮显示 `Disconnect`。
- 该 2 秒流程只模拟 UI，不发送任何网络、Mesh、云端或设备命令。

Disconnect：

- 点击 `Disconnect` 后清空 SSID 和 Password。
- 状态回到初始未连接 UI，Connect 按钮禁用。
- 不自动重新读取 SSID，避免刚清空后又被系统 SSID 刷回；用户可点击 `Refresh` 手动读取。

App 回前台：

- 如果用户通过 alert 跳转系统设置后回到 App，页面自动刷新一次 SSID。
- 若当前处于 connected 或 connecting 状态，不覆盖当前模拟状态。
- 若系统无法返回 SSID，则保持空值。

页面退出：

- 取消未完成的 2 秒模拟 timer。
- 页面再次打开时重新从初始状态开始，Password 为空。

## Change Wi-Fi Alert

点击 `select_wifi` 图标弹出 Figma 样式 alert。

内容：

- 标题：`Connect to 2.4 GHz Wi-Fi Network`
- 图片：`connect_wifi_intro`，固定尺寸展示 2.4GHz 支持提示。
- 按钮：`Go to System Settings`

按钮行为：

- 打开 iOS 系统设置页。
- 用户返回 App 后触发 SSID 自动刷新。

如果系统设置跳转失败，展示轻提示，不改变当前 UI 状态。

## SSID 获取与权限

iOS 获取当前 Wi-Fi SSID 受系统限制。本功能实现时需要检查并补齐：

- Wi-Fi Info entitlement。
- 必要的定位权限描述与本地化文案。
- 所有受影响 brand target 的配置一致性。

若用户未授权、系统不返回 SSID、设备未连接 Wi-Fi 或能力不可用：

- SSID 展示为空。
- 不阻断 Password 输入。
- 不阻断模拟 Connect 流程。

## 国际化

新增用户可见文案必须加入 English 与简体中文本地化。

新增 key 覆盖：

- `network_connectivity`
- `ssid`
- `select_wifi`
- `only_supports_24ghz_networks`
- `refresh`
- `connect_to_wifi`
- `disconnect`
- `connect_to_24ghz_wifi_network`
- `go_to_system_settings`
- `wifi_password_ascii_only`

如项目已有同义 key，优先复用已有 key。

## 非目标

- 不实现真实网关配网。
- 不下发 SSID 或 Password。
- 不新增或修改 WiFi Gateway 协议。
- 不保存 Password。
- 不改变 Activate、Associated Spaces、Server Information、Delete、Identify、WiFi DFU、Diagnosis 行为。
- 不改变 4G Gateway 页面。

## 验证

静态验证：

- 确认 `Network Connectivity` 仅出现在 WiFi Gateway 页面。
- 确认 section 顺序为 Activate 下方、Associated Spaces 上方。
- 确认 Password 为空打开页面，不持久化。
- 确认非 ASCII Password 被拒绝或提示。
- 确认 Disconnect 后 SSID 与 Password 清空，且不会立即自动刷新 SSID。
- 确认 target 配置、本地化和资源引用覆盖相关 brand target。

构建验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- 如修改 target 配置、资源或本地化，再串行补充 `Archipelago`、`SLG Sync Plus`、`SylSmart` iPhoneOS build。

## 已确认决策

- 使用方案 A：新增 WiFi Gateway 专用 Network Connectivity cell/view，状态只保存在页面内存中。
- 本期仅模拟连接，不下发 SSID/password 给 WiFi Gateway。
- `Disconnect` 的清空行为作用于本地 UI，不代表真实断开设备网络。
- SSID 获取失败时展示为空，不阻断模拟连接。
