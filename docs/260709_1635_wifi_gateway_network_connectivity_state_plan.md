# WiFi Gateway Network Connectivity 状态优化分析与计划

## 背景

WiFi Gateway 设备范围固定为 `CID 0x0A78 / PID 0x2721`。

页面进入后，BLE/Proxy 连接成功时顶部 Gateway 状态展示为 `Online`，随后读取网关 Wi-Fi 凭据 `43 12`，再按结果决定是否读取 Wi-Fi 连接状态 `43 0E` 与 RSSI `43 0F`。

当前代码中，`WiFiGatewayViewController` 已经把 header Wi-Fi 状态拆成：

- `Not Configured`：网关未配置 SSID/password。
- `Not Connected`：网关已配置或正在配置，但未成功连接 Wi-Fi。
- 信号强度：网关已连接 Wi-Fi 且 RSSI 可用。
- `No Signal`：网关已连接 Wi-Fi，但 RSSI 查询失败、不可用或解析失败。

Network Connectivity 表单当前由 `GatewayNetworkConnectivityCell` 渲染，控制器维护 `networkSSID`、`networkPassword`、`networkCredentialSource`、`networkConnectState` 等状态。

## 需求合理性

需求方向合理。核心问题不是单个按钮逻辑，而是 Network Connectivity 同时混合了三类状态：

1. 网关是否已保存 Wi-Fi 凭据。
2. 网关是否已经连接到保存的 Wi-Fi。
3. 当前表单内容来自网关、手机当前 Wi-Fi，还是本地清空状态。

如果继续只用 `connected / available / disabled` 这类按钮态表达所有业务语义，会越来越乱。更合理的处理方式是把页面状态抽象成一个明确的 view model，再由 view model 统一决定：

- header 文案。
- SSID/password 是否可编辑。
- Change Wi-Fi 点击行为。
- Refresh 点击行为。
- Connect/Disconnect 按钮标题和动作。

## 需求缺口与建议补齐

### 1. “直接编辑 SSID”需要确认 UI 形态

当前 SSID 不是输入框，而是 `UILabel + select Wi-Fi button + clear button`。所以“允许用户直接编辑 ssid”不是解除禁用即可完成，需要改成以下其中一种：

- 推荐：将 SSID 行改为可编辑 `UITextField`，右侧保留 Change Wi-Fi 图标和 Clear 图标。
- 保守：仍不支持手动输入 SSID，只允许通过手机当前 Wi-Fi 刷新/Change Wi-Fi/清除后重新选择。

如果产品明确要求“直接编辑”，推荐第一种。

### 2. 已连接时点击输入框/Change Wi-Fi/Refresh 的反馈需要一致

用户预期是“已连接时不允许修改”。建议：

- SSID 输入框点击：toast `Please disconnect first`。
- Password 输入框点击：toast `Please disconnect first`。
- Change Wi-Fi 点击：toast `Please disconnect first`。
- Refresh 点击：不 toast，按需求重新走 `43 12 -> 43 0E`，不读取手机 SSID。

也就是说，已连接态只有“编辑/换 Wi-Fi”被拦截，Refresh 仍可用。

### 3. 已配置但未连接时是否应保留网关返回 password

需求说“允许用户直接编辑 ssid 和 password”，并且 Refresh 直接刷新手机 Wi-Fi SSID。

建议行为：

- 首次进入：如果 `43 12` 返回已配置，表单先展示网关保存的 SSID/password。
- `43 0E` 返回未连接后，表单进入可编辑态。
- 用户点击 Refresh：读取手机当前 SSID，并用该 SSID 查本地缓存 password；如果无缓存则 password 置空。

这样能兼容“曾经配置的 Wi-Fi 不能再连接，需要快速换到手机当前 Wi-Fi”的产品意图。

### 4. 未配置时 password 缓存策略已合理

未配置时展示手机当前 Wi-Fi SSID，password 从本地 `wifi_gateway_saved_passwords_by_ssid` 按 SSID 查缓存，否则为空。这个方向合理。

需要注意：Disconnect/Clear 后只清空当前表单中的 SSID/password，不移除该 SSID 对应的本地缓存 password。这样用户后续再次选择同一 SSID 时，仍可自动带出缓存 password。

## 推荐产品方案

推荐使用“状态驱动的单表单方案”，不新增复杂页面。

### 状态矩阵

| Gateway Wi-Fi 状态 | Header Wi-Fi | 表单来源 | SSID/password | Change Wi-Fi | Refresh | 主按钮 |
| --- | --- | --- | --- | --- | --- | --- |
| 已配置 + 已连接 | RSSI 信号强度，RSSI 失败时 `No Signal` | Gateway | 展示网关保存值，不允许编辑 | toast `Please disconnect first` | `43 12 -> 43 0E`，不读手机 SSID | `Disconnect` |
| 已配置 + 未连接 | `Not Connected` | Gateway 初始值，可切到 Phone | 允许编辑 | 弹窗 `Connect to 2.4 GHz Wi-Fi Network` | 读取手机当前 Wi-Fi SSID，并按 SSID 带出缓存 password | `Connect to Wi-Fi` |
| 未配置 | `Not Configured` | Phone | 允许编辑，password 按 SSID 缓存带出，否则为空 | 弹窗 `Connect to 2.4 GHz Wi-Fi Network` | 读取手机当前 Wi-Fi SSID，并按 SSID 带出缓存 password | `Connect to Wi-Fi` |
| 操作中 | 保持当前状态或 `Not Connected` | 当前值 | 不允许编辑 | 禁用或无动作 | 禁用或无动作 | loading |
| Gateway Offline | 隐藏 Network Connectivity | 无 | 清空 | 无 | 无 | 无 |

### 为什么推荐这个方案

- 与当前协议能力一致：配置态来自 `43 12`，连接态来自 `43 0E`，信号来自 `43 0F`。
- 与用户心理模型一致：已连接时先断开，未连接/未配置时可直接改。
- 不需要新增“配置向导”页面，改动集中在 `WiFiGatewayViewController` 和 `GatewayNetworkConnectivityCell`。
- 后续状态增加时可以继续扩展 view model，而不是继续叠加 `if networkCredentialSource == ...`。

## 备选方案

### 方案 A：最小代码改动

沿用现有 `networkCredentialSource + networkConnectState`，只补：

- 已连接态输入/Change Wi-Fi toast。
- 已连接态 Refresh 改为 `43 12 -> 43 0E`。
- 已配置未连接态允许 password 编辑。
- 未连接/未配置态 Refresh 直接读手机 SSID。

优点：改动小。

缺点：SSID 仍不是可编辑输入框，不能完整满足“直接编辑 ssid”；状态分支会继续散落在控制器里。

### 方案 B：推荐方案，增加状态 view model

新增内部状态模型，例如：

- `configuredConnected(credentials)`
- `configuredDisconnected(credentials)`
- `notConfigured`
- `editing(source)`
- `connecting`
- `disconnecting`
- `offline`

控制器只根据协议结果更新状态模型，cell 只接收渲染结果。

优点：需求语义清楚，Refresh/Change Wi-Fi/编辑权限都有单一真值层。

缺点：比方案 A 多一些重构，但仍局限在 WiFi Gateway 页面和 cell。

### 方案 C：产品向导化

将 Network Connectivity 改成“状态卡 + Change Wi-Fi 向导”：

- 已连接只展示当前 Wi-Fi 与 Disconnect。
- 未连接/未配置点击 Connect/Change Wi-Fi 进入编辑弹窗或单独页面。
- 主页面不直接承载 SSID/password 输入。

优点：主页面更清爽，产品语义更强。

缺点：交互变化大，开发量更高，也偏离当前页面结构。

## 推荐开发方案

推荐采用方案 B，但保持 UI 不大改，只把 SSID label 改为可编辑输入框。

### 计划

1. 补静态契约脚本
   - 覆盖已连接态编辑/Change Wi-Fi toast。
   - 覆盖已连接态 Refresh 不走手机 SSID，而是 `43 12 -> 43 0E`。
   - 覆盖未连接/未配置态 Refresh 走手机 SSID。
   - 覆盖 SSID 输入回调和 password 输入回调均受同一编辑权限控制。

2. 更新 `GatewayNetworkConnectivityCell`
   - 将 SSID 显示从 label 改为 text field。
   - 增加 `ssidChangedCallback`。
   - 增加 `lockedEditCallback` 或 `textFieldShouldBeginEditing` 拦截，用于已连接态 toast。
   - 保留右侧 Change Wi-Fi 图标、Clear 图标、Refresh、Password、Connect/Disconnect。

3. 更新 `WiFiGatewayViewController`
   - 引入内部 view model 或至少收口状态判断方法。
   - 已连接态：SSID/password 不可改，点击输入或 Change Wi-Fi 提示 `Please disconnect first`，Refresh 走 `43 12 -> 43 0E`。
   - 已配置未连接态：SSID/password 可编辑；Refresh 直接读取手机 SSID；Change Wi-Fi 弹窗。
   - 未配置态：读取手机 SSID 并带出缓存 password；SSID/password 可编辑；Refresh 直接读取手机 SSID；Change Wi-Fi 弹窗。
   - Connect 成功后保存 password 缓存；Disconnect/Clear 清空当前表单，但保留对应 SSID 的缓存 password。

4. 本地化
   - 新增并同步中英文：`please_disconnect_first`。
   - 英文值：`Please disconnect first`。
   - 简体中文建议：`请先断开连接`。

5. 验证
   - 运行相关 WiFi Gateway 静态脚本。
   - 运行 `git diff --check`。
   - 直接运行四个 iPhoneOS build：`SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`。

## 待确认点

1. 是否确认把 SSID 行改成可直接输入的 `UITextField`？
2. `Please disconnect first` 的中文是否使用 `请先断开连接`？
3. Disconnect/Clear 后按用户确认改为“清空当前表单 SSID/password，但不移除该 SSID 的缓存 password”。
4. 已连接态 Refresh 是否按更严格的 `43 12 -> 43 0E` 执行，而不是只读 `43 0E`？
