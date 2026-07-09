# WiFi Gateway Refresh Loading 优化分析与计划

## 背景

设备范围仍限定为 WiFi Gateway：`CID 0x0A78 / PID 0x2721`。

当前 `Network Connectivity` 的 Refresh 行为已经按状态分流：

- 已连接：`43 12` 读取网关 SSID/password，再 `43 0E` 获取 Wi-Fi 连接状态，不读取手机 SSID。
- 未连接/未配置：读取手机当前 Wi-Fi SSID，并用 SSID 查本地缓存 password。

当前不足：

- Refresh 按钮没有 loading 状态。
- Refresh 过程中没有单独的防重复点击状态。
- 未连接/未配置时仍使用 generic success/failed HUD，无法表达 “SSID 没变” 或 “已更新到新网络”。

## 需求合理性

需求合理。Refresh 的语义在不同状态下不同：

1. 已连接态 Refresh 是“刷新网关当前配置与连接状态”，用户不需要看到成功 toast，只需要知道命令正在进行。
2. 未连接/未配置态 Refresh 是“用手机当前 Wi-Fi 更新表单 SSID”，用户需要知道表单是否真的改变。
3. Refresh loading 应独立于 Connect/Disconnect loading，否则会误把主按钮也变成 loading。

因此推荐新增一个独立的 `isNetworkRefreshInProgress` 状态，而不是复用 `networkConnectState == .connecting/.disconnecting`。

## 推荐产品行为

| 当前状态 | Refresh 动作 | Loading | 成功提示 | 失败提示 |
| --- | --- | --- | --- | --- |
| 已配置 + 已连接 | `43 12 -> 43 0E` | 显示在 Refresh 按钮位置 | 不提示 | `Failed to retrieve data.` |
| 已配置 + 未连接 | 读取手机当前 Wi-Fi SSID | 显示在 Refresh 按钮位置 | SSID 相同：`Network unchanged.`；SSID 不同：`Updated to the new network.` | 手机 SSID 为空时提示 `Phone is not connected to Wi-Fi.` |
| 未配置 | 读取手机当前 Wi-Fi SSID | 显示在 Refresh 按钮位置 | SSID 相同：`Network unchanged.`；SSID 不同：`Updated to the new network.` | 手机 SSID 为空时提示 `Phone is not connected to Wi-Fi.` |
| Connect/Disconnect 操作中 | 不响应 Refresh | 不单独展示 Refresh loading | 不提示 | 不提示 |
| Refresh 进行中 | 不响应重复点击 | 保持 loading | 不重复提示 | 不重复提示 |

说明：

- “当前 ssid” 使用点击 Refresh 前表单里的 `networkSSID`。
- “即将更新的 ssid” 使用 `WiFiSSIDProvider` 返回的手机当前 Wi-Fi SSID。
- 如果手机当前 Wi-Fi SSID 为空，不能可靠判断 unchanged/updated，按用户确认提示 `Phone is not connected to Wi-Fi.`，并保留当前表单。

## UI 方案

推荐方案：在 `GatewayNetworkConnectivityCell` 内给 Refresh 按钮增加一个固定尺寸的 loading image view。

- 使用现有 `loading_16` 图片。
- 固定 `16 x 16`，不使用 `SCRXFrom/SCRYFrom` 做缩放适配。
- loading 时隐藏 Refresh 文案，展示居中的旋转图片。
- loading 结束后隐藏图片，恢复 `Refresh` 文案。
- loading 时 `refreshButton.isEnabled = false`，避免重复点击。
- 不增加背景和边框，不改变按钮布局。

## 备选方案

### 方案 A：直接让 UIButton 切换 image/title

优点：代码最少。

缺点：UIButton image 的尺寸和 title/image inset 容易受系统布局影响，不符合“不使用放大缩小适配”的要求。

### 方案 B：推荐方案，Refresh 按钮内加独立 loading image view

优点：尺寸可控、动画逻辑清楚、和 Connect loading 互不影响。

缺点：cell 多一个 subview 和一个 `isRefreshing` 入参。

### 方案 C：整行或 cell 级 loading

优点：状态显眼。

缺点：超出需求，会干扰 SSID/password 表单编辑，也不像一个轻量 Refresh 动作。

## 推荐开发方案

采用方案 B。

### 代码改动

1. 更新 `GatewayNetworkConnectivityCell`
   - 增加 `refreshLoadingImageView`。
   - `update(...)` 增加 `isRefreshing` 参数。
   - `apply(...)` 同步处理 Refresh 文案、loading image、button enabled。
   - loading image 固定 `16 x 16`。
   - `prepareForReuse()` 移除 refresh loading 动画。

2. 更新 `WiFiGatewayViewController`
   - 增加 `isNetworkRefreshInProgress`。
   - `configureNetworkConnectivityCell` 传入 `isRefreshing`，并在刷新中关闭 Refresh 点击。
   - `refreshNetworkConnectivity()` 开始时 guard `!isNetworkRefreshInProgress`，然后进入 loading。
   - 已连接态：执行 `43 12 -> 43 0E`，完成后只结束 loading，不弹 success toast。
   - 未连接/未配置态：记录旧 `networkSSID`，读取手机 SSID，比较旧值和新值后提示：
     - 相同：`Network unchanged.`
     - 不同：`Updated to the new network.`
   - 命令失败/超时：结束 loading，保留当前 UI，提示 `Failed to retrieve data.`。
   - 手机当前 Wi-Fi SSID 为空：结束 loading，保留当前 UI，提示 `Phone is not connected to Wi-Fi.`。

3. 本地化
   - 新增英文：
     - `network_unchanged` = `Network unchanged.`
     - `updated_to_the_new_network` = `Updated to the new network.`
     - `phone_not_connected_to_wifi` = `Phone is not connected to Wi-Fi.`
   - 新增简体中文建议：
     - `network_unchanged` = `网络未变化。`
     - `updated_to_the_new_network` = `已更新为新网络。`
     - `phone_not_connected_to_wifi` = `手机未连接 Wi-Fi。`

4. 脚本契约
   - 更新 `scripts/check_wifi_gateway_network_connectivity.sh`，覆盖：
     - cell 有独立 refresh loading image。
     - refresh loading 固定 16，不使用 `SCRYFrom/SCRXFrom`。
     - controller 有 `isNetworkRefreshInProgress`。
     - 已连接态 refresh 不展示 success toast。
     - 未连接/未配置态按 SSID 变化显示两个新 toast。
     - Refresh loading 中不响应重复点击。

5. 验证
   - 先跑更新后的脚本，确认 RED 失败。
   - 实现后跑：
     - `bash scripts/check_wifi_gateway_network_connectivity.sh`
     - `bash scripts/check_wifi_gateway_disconnect_clear_credentials.sh`
     - `bash scripts/check_wifi_gateway_wifi_status_header.sh`
     - `bash scripts/check_wifi_gateway_sig_mesh_status_header.sh`
     - `git diff --check`
   - 直接运行四个 iPhoneOS build：
     - `SunSmart`
     - `Archipelago`
     - `SLG Sync Plus`
     - `SylSmart`

## 已确认事项

1. Refresh loading 图片固定使用 `16 x 16`。
2. 手机当前 Wi-Fi SSID 为空时，按用户确认提示 `Phone is not connected to Wi-Fi.` / `手机未连接 Wi-Fi。`。
3. 两个新增中文文案使用：
   - `Network unchanged.` -> `网络未变化。`
   - `Updated to the new network.` -> `已更新为新网络。`
