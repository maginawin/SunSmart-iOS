# WiFi Gateway Network Connectivity 真实协议设计

## 背景

WiFi Gateway 页面当前已经存在 `Network Connectivity` section，但实现仍是早期本地模拟版本：页面固定插入 section，进入页面后读取手机当前 Wi-Fi SSID，点击 `Connect to Wi-Fi` 后用 2 秒 timer 模拟连接成功。SDK 已根据 `docs/superpowers/plans/260703_1454_wifi_gateway_vendor_protocol_implementation_plan.md` 实现 WiFi Gateway vendor 协议，App 需要把该 section 切换为真实网关配置读取、配置下发和连接状态轮询。

当前进入 Gateway 页面时，`SiteViewController` 会将 `node.isWiFiGateway` 的网关路由到 `WiFiGatewayViewController`。`WiFiGatewayViewController` 继承 `GatewayViewController`，父类在 `viewDidLoad` 中调用 `setNetworkConnected()`，并通过 `MeshLibManager.manager.connectProxy(node:)` 尝试连接当前网关。因此“进入 Gateway 页面后会尝试连接网关”这个判断成立。

## 目标

- 仅影响 WiFi Gateway 页面，不改变 legacy 4G Gateway。
- Gateway Offline 或 Unknown 时隐藏 `Network Connectivity`。
- Gateway Online 时先读取网关 SSID/password 配置，再决定是否展示 `Network Connectivity`。
- 已配置 SSID/password 时展示网关配置，并根据网关 Wi-Fi connection status 显示 `Connect to Wi-Fi` 或 `Disconnect`。
- 未配置 SSID/password 时展示手机当前连接的 SSID，并按 SSID 从 UserDefaults 自动填充已保存密码。
- 点击 `Connect to Wi-Fi` 后真实下发 SSID/password，并每 2 秒读取 Wi-Fi connection status，直到成功、失败或超时。
- 点击 `Disconnect` 只清空 App 本地 UI 内容，不向网关下发清除配置命令。

## 非目标

- 不实现网关端清除 SSID/password，因为当前网关协议没有该功能。
- 不把 Wi-Fi 密码同步到云端，不区分 Site、Space 或用户权限范围。
- 不新增 Auth 信息。
- 不重构 Gateway 父类整体结构，不改 4G Gateway APN、SIM、MQTT 逻辑。
- 不把 Network Connectivity 加到其他 Gateway 或其他设备页面。

## 协议能力

App 层使用 SDK 已提供的 typed vendor API：

- 读取网关 SSID/password：`wifiGatewayCredentials`，对应 `43 12`。
- 下发网关 SSID/password：`wifiGatewayCredentialsSet`，对应 `43 0D`。
- 读取 Wi-Fi connection status：`wifiGatewayConnectionStatus`，对应 `43 0E`。

连接状态判断必须读取 typed enum：

- `.connected` 视为连接成功。
- `.passwordError`、`.failed`、`.reserved` 视为连接失败。
- `.notStartedOrConnecting` 视为仍在连接中。

注意：SDK 当前 `SunricherVendorStatus.status.isSuccessful` 按状态字节是否为 `0x00` 判断，而 `.connected` 的状态字节是 `0x01`。App 不能用 `isSuccessful` 判断 Wi-Fi 是否连接成功，必须匹配 typed `WiFiGatewayConnectionStatus`。

## Section 展示状态

`WiFiGatewayViewController` 增加独立的 network connectivity 状态机，控制 section 是否插入 `sections`。

隐藏 section 的状态：

- Gateway 尚未完成 BLE/proxy 连接。
- Gateway Offline 或 Unknown。
- 正在初始读取网关 SSID/password。
- 初始读取网关 SSID/password 失败。
- 已配置 SSID/password，但正在读取 connection status。
- 已配置 SSID/password，但读取 connection status 失败。
- Connecting 过程中检测到网关蓝牙连接断开。

展示 section 的状态：

- 网关未配置 SSID/password，App 展示手机当前 SSID。
- 网关已配置 SSID/password，且 connection status 读取成功。
- 用户已点击 `Connect to Wi-Fi`，正在轮询 connection status。
- 用户本次页面内点击了 `Disconnect`，App 进入本地清空后的未配置展示态。
- 用户本次页面内点击了 SSID clear 按钮，App 进入本地清空后的未配置展示态。

## 初始进入流程

1. 页面进入后沿用父类现有 `connectProxy(node:)` 逻辑连接网关。
2. 连接完成后，如果 `node.state` 不是 online，隐藏 `Network Connectivity`。
3. 如果 `node.state` 是 online，发送 `wifiGatewayCredentials`。
4. 读取 credentials 成功且为已配置：
   - 保存网关返回的 SSID/password 到页面状态。
   - 继续发送 `wifiGatewayConnectionStatus`。
   - status 读取成功后展示 section。
   - `.connected` 显示 `Disconnect`。
   - `.notStartedOrConnecting`、`.passwordError`、`.failed`、`.reserved` 显示 `Connect to Wi-Fi`。
5. 读取 credentials 成功且为未配置：
   - 展示 section。
   - 读取手机当前 Wi-Fi SSID。
   - 如果按该 SSID 在 UserDefaults 找到密码，自动填入 Password。
   - 如果没有缓存密码，Password 为空。
6. 读取 credentials 失败：
   - 隐藏 section。
   - 当前页面可见时提示获取失败。

如果手机当前 SSID 读取不到，则 section 仍可展示，但 SSID 为空，`Connect to Wi-Fi` 禁用。用户通过 `Change Wi-Fi` 跳转系统设置并返回后，再重新读取手机 SSID 和对应缓存密码。

## Connect 流程

点击 `Connect to Wi-Fi` 时：

1. 校验 SSID 和 Password。
2. SSID 必须非空，并满足 SDK 的 SSID 长度和字符要求。
3. Password 为空时视为无密码 Wi-Fi。
4. Password 非空时必须满足 SDK 的密码长度和字符要求；其中长度至少 8 字符，最多 63 字符。
5. 校验通过后发送 `wifiGatewayCredentialsSet`。
6. `wifiGatewayCredentialsSet` 返回 `.accepted` 后进入 Connecting 状态。
7. Connecting 状态下禁用 `Change Wi-Fi`、`Refresh`、Password 输入、密码显隐切换和按钮重复点击。
8. 每 2 秒发送 `wifiGatewayConnectionStatus`。
9. `.connected`：
   - 停止轮询。
   - 显示连接成功提示。
   - 按 SSID 将当前 Password 保存到 UserDefaults。
   - 按钮切换为 `Disconnect`。
10. `.passwordError`、`.failed`、`.reserved`：
   - 停止轮询。
   - 显示连接失败提示。
   - 按钮切换回 `Connect to Wi-Fi`。
11. 超时仍为 `.notStartedOrConnecting`：
   - 停止轮询。
   - 按连接失败处理。

推荐超时时间为 60 秒。这样可以避免网关长期返回 connecting 导致 App 无限轮询。

如果 `wifiGatewayCredentialsSet` 返回 `.invalidParameters`、`.internalError`、`.reserved` 或超时无回复，直接提示连接失败，不进入轮询。

## Disconnect 流程

点击 `Disconnect` 时：

1. 停止当前轮询。
2. 清空页面内 SSID 和 Password。
3. 清空密码显隐状态。
4. 将按钮切换为 `Connect to Wi-Fi` 的禁用态。
5. 不发送空 SSID/password 给网关。
6. 不删除 UserDefaults 中已保存的 SSID 密码。

这只是本地 UI 清空，不代表网关端配置已清除。重新进入页面时，如果网关仍返回已配置 SSID/password，App 会按网关真实配置再次展示。

## SSID clear 流程

在 SSID 展示框右侧增加 clear 按钮，用于解决“网关已配置 SSID/password 但当前未连接，用户想切换 SSID”的入口问题。

显示规则：

- Connecting 状态下隐藏或禁用 clear。
- 已配置且 `.connected` 状态下不显示 clear，避免与 `Disconnect` 形成两个含义接近的本地清空入口。
- 已配置但非 `.connected` 状态下显示 clear，例如 `.notStartedOrConnecting`、`.passwordError`、`.failed`、`.reserved`。
- 未配置状态下如果 SSID 不为空，也可以显示 clear，用于清空当前手机 SSID。

点击 clear 时：

1. 只清空 App 本地 SSID/password 和密码显隐状态。
2. 不向网关下发清除配置命令。
3. 不删除 UserDefaults 中保存的 SSID 密码。
4. 页面进入本地清空后的未配置展示态。
5. 此后点击 `Refresh` 可读取手机当前 Wi-Fi SSID 和对应缓存密码。
6. 如果手机未连接 Wi-Fi，`Refresh` 后 SSID/password 保持为空。

## 生命周期与页面可见性

- WiFi Gateway 页面关闭或释放时，停止所有 Network Connectivity 轮询。
- 用户 push 到 `Information` 等子页面时，WiFi Gateway controller 仍在导航栈中；Connecting 状态下继续每 2 秒读取 connection status，用于保持状态更新。
- 子页面期间不展示连接成功或失败弹窗。
- 用户返回 WiFi Gateway 页面后，如果连接流程已经得出最终结果，再展示一次对应成功或失败提示。
- 如果 Gateway 页面被 pop、dismiss 或 deinit，则不再轮询，也不缓存后续结果提示。
- 如果 Mesh 设备状态更新显示网关蓝牙连接断开，立即隐藏 section、停止轮询，并清空 Connecting 状态。

## Refresh 与 Change Wi-Fi

Refresh：

- 只用于刷新手机当前连接的 Wi-Fi SSID。
- 仅在未连接和非 Connecting 状态下可用。
- 刷新成功后，根据新 SSID 从 UserDefaults 读取缓存密码并自动填入。
- 刷新失败时保留当前显示值，并提示失败。

Change Wi-Fi：

- 继续复用现有跳转系统设置的 alert。
- App 回到前台后是否读取并展示手机当前 SSID，取决于当前是否仍处于“网关配置优先展示”状态。
- 仅在 Connecting 状态下禁用。
- 只要网关读取到已配置 SSID/password，页面就优先展示网关配置，不自动用手机当前 Wi-Fi SSID 覆盖。
- Connected 状态下仍允许使用 `Change Wi-Fi`，但返回 App 后继续展示网关配置中的 SSID/password，并保持 `Disconnect` 状态。
- 已配置但非 Connected 状态下也不自动展示手机 SSID。用户想切换 SSID 时，需要先点击 SSID clear 清空本地展示，再通过 `Refresh` 读取手机当前 SSID；也可以先点击 `Change Wi-Fi` 切换手机 Wi-Fi，返回后再点击 `Refresh`。
- 未配置、已点击 `Disconnect` 清空、或已点击 SSID clear 清空后的状态下，`Refresh` 才读取并展示手机当前 Wi-Fi SSID 和对应缓存密码。

## UserDefaults 密码缓存

- 使用 UserDefaults 保存 SSID 到 Password 的映射。
- 映射全 App 共享，不区分 Site、Space。
- 仅在连接结果为 `.connected` 后保存。
- SSID 使用精确字符串匹配，区分大小写。
- open Wi-Fi 使用空字符串保存，表示该 SSID 不需要密码。
- 不写入云端，不写入 `GatewayModel`、`Node` 或数据库。
- 不新增明文 Wi-Fi 密码日志。

## UI 与本地化

复用现有 UI 结构和文案：

- `Network Connectivity`
- `SSID`
- `Password`
- `Only supports 2.4GHz networks.`
- `Connect to Wi-Fi`
- `Disconnect`
- `Refresh`
- `Select Wi-Fi`

SSID clear 使用展示框右侧的图标按钮，不新增可见按钮文字。若复用现有 clear/close 图标即可满足视觉一致性，不新增 asset。

需要新增或复用提示文案：

- 获取 Wi-Fi 配置失败。
- 连接成功。
- 连接失败。
- SSID 不能为空。
- Password 长度不合法时提示：`Leave the password empty for an open Wi-Fi network, or enter 8-63 characters.`；zh-CN：`无密码 Wi-Fi 可留空；如填写密码，请输入 8-63 个字符。`
- Password 字符不合法时提示：`Password can only contain letters, numbers, symbols, and spaces. Double quotes and backslashes are not supported.`；zh-CN：`密码只能包含英文字母、数字、符号和空格，不支持双引号或反斜杠。`

所有新增用户可见文案必须同步 English 和 zh-CN。已有通用成功、失败文案可复用，只有语义不足时才新增 key。

## 错误处理

- vendor model 不存在：隐藏 section，当前页面可见时提示获取失败。
- 读取 credentials 超时或解析失败：隐藏 section，当前页面可见时提示获取失败。
- 已配置 credentials 后读取 status 超时或解析失败：隐藏 section，当前页面可见时提示获取失败。
- 下发 credentials set 失败：停留在可编辑状态，提示连接失败。
- 轮询 status 失败一次：建议继续下一轮，直到得到明确失败状态或达到 60 秒超时。
- 网关蓝牙断开：立即隐藏 section，停止轮询，不展示连接成功或失败弹窗。

## 验收计划

静态检查：

- 确认 WiFi Gateway 才插入 `Network Connectivity`。
- 确认 4G Gateway 不受影响。
- 确认 App 判断 `.connected` 使用 typed enum，不依赖 `status.isSuccessful`。
- 确认没有新增明文 Wi-Fi 密码日志。
- 确认新增本地化 key 同步 English 和 zh-CN。

手工场景：

- Gateway offline/unknown：不展示 section。
- Gateway online，网关未配置：展示手机当前 SSID，缓存密码按 SSID 自动填充。
- Gateway online，网关已配置且 status 为 `.connected`：展示网关 SSID/password，按钮为 `Disconnect`。
- Gateway online，网关已配置但 status 非 `.connected`：展示网关 SSID/password，按钮为 `Connect to Wi-Fi`。
- 空密码 SSID 可以点击 Connect。
- 非空密码少于 8 字符不能点击 Connect。
- 非空密码超过 63 字符不能点击 Connect。
- 密码包含非可打印 ASCII 字符、双引号或反斜杠时，显示具体字符不支持提示。
- 连接成功后再次选择同 SSID 自动填充缓存密码。
- Connected 状态下可以点击 Change Wi-Fi；如果网关已配置 SSID/password 且 status 为 `.connected`，返回后仍展示网关配置，不展示手机新 SSID。
- 已配置但非 connected 状态下，用户可以点击 SSID clear 清空本地内容，再点击 Refresh 展示手机当前 SSID。
- 已配置 connected 状态下若要展示手机当前 SSID，需先点击 Disconnect 清空本地内容，再点击 Refresh。
- Connecting 时 push 到 Information 页面继续轮询，但不弹结果；返回 Gateway 后展示最终结果。
- Connecting 时网关蓝牙断开：隐藏 section 并停止轮询。
- 点击 Disconnect 只清空本地 UI，重新进入页面后仍以网关真实配置为准。

构建验证：

- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

如修改共享资源、本地化或 target 配置，再同步检查相关 target 是否受影响。
