# WiFi Gateway 固件升级功能设计

## 目标

在 WiFi Gateway 的 WiFi Firmware Update 页面实现真实的互联网接入模组固件升级：根据 Current version 与云端 New version 判断是否可升级，使用新版 `43 10` 下发下载 URL 和 firmware ID，通过 `43 11` 查询或接收 OTA 状态，并按 Figma 展示升级进度、失败和成功结果。

## 范围

本次包含：

- 将本地 NordicSigMeshSDK 的 `43 10` 同步为 URL + firmware ID 新协议。
- App 构造当前区域对应的 HTTP OTA 下载 URL。
- App 发送 `43 10`、查询并监听 `43 11`、恢复本地 OTA session。
- 实现 `WiFiFirmwareUpdatingView` 和对应底部按钮状态。
- 将页面主内容调整为 UIScrollView，以支持小屏设备。
- English、简体中文本地化。
- 四个 App target 和本地 SDK 联动验证。

本次不包含：

- WiFi DFU cancel 协议及真实取消能力。
- 修改服务端接口或固件打包流程。
- 修改 BLE OTA、Mesh OTA 的业务行为。
- 新增 App unit-test target。

## 已确认的产品决策

- `downloading` 和 `updating` 均显示 `CANCEL`，但按钮不可点击。
- `43 10 ret=0x04` 映射为 `connFailedServerUnable`，副文案保持 Figma 的 `Unable to connect to the server`。
- 没有 cancel 协议时不提供隐藏进度或恢复默认页面的伪取消行为。
- SDK 只负责协议模型、校验、编解码；App 负责升级会话和 UI 状态机。
- Loading 优先复用现有 `XWHUDManager`。

## 协议设计

### 新版 `43 10`

SDK 的 `WiFiGatewayDFUMetadata` 只保留：

- `url: String`
- `firmwareID: String`

业务 payload 顺序为：

1. `0x43`
2. `0x10`
3. URL ASCII 字节长度 U16 Little Endian
4. URL ASCII 字节
5. firmware ID ASCII 字节长度 U8
6. firmware ID ASCII 字节

SDK 校验规则：

- URL 必须以 `http://` 开头。
- URL 和 firmware ID 只允许可打印 ASCII，拒绝双引号、CR、LF。
- firmware ID 长度为 `1...32`。
- 完整业务 payload 长度为 `5 + url_len + firmware_id_len`，不得超过 256 字节。
- 删除 SHA256、size 字段、校验错误和编码逻辑。

`43 10` response、`43 11` request/response、stage/code 枚举保持现有 SDK API 和协议语义。

## OTA URL 构造

App 不使用 latest response 中的 S3 预签名 `url` 作为 `43 10` 参数，只使用 response 的 `filename`。

URL builder 的规则：

1. 从 `UserData.currentServerRegion.baseURL` 读取当前区域 HTTPS base URL。
2. 保留 host、port 和 `/srv2` 基础路径，将 scheme 改为 `http`。
3. 追加固定路径 `/sitespace/ota/download`。
4. 通过 URL query item 添加 `key=filename`，由 URL API进行 percent encoding。
5. 将最终 URL absolute string 交给 SDK metadata 校验。

示例：

`http://www.mericher.com/srv2/sitespace/ota/download?key=dev/20260514100245/OTA_Gateway_SS_0A78_0x2721_wifi_9036T-GW-54TA-PA-WIFI_v0.4.0_20260514.zip`

该示例已实际请求并返回 `200 OK`、`application/octet-stream`、`app_update.bin` 和 `Content-Length: 1006672`。示例 URL 长 148 字节，firmware ID 长 5 字节，新协议 payload 总长 158 字节。

URL builder 不硬编码 `www.mericher.com`，China Mainland、Asia Pacific、North America、Europe 均沿用当前 App region 的 base URL。

## Firmware ID 解析

- 来源为 latest response 的 `version`。
- 只去掉最多一个前导 `v` 或 `V`。
- `v0.4.0` 转换为 `0.4.0`。
- 不使用全局字符串替换，避免误删版本内容中的其它字符。
- 解析后为空、非 ASCII 或超过 32 字节时，不发送 `43 10`。
- WiFi 页面通过专用版本解析 hook 获取 firmware ID；共享 BLE/Mesh 服务器版本解析行为保持不变。

## App 架构

### WiFiFirmwareDFUCoordinator

新增独立 coordinator，负责：

- 构造并发送 `43 10`。
- 串行发送 `43 11`。
- 注册和移除 `MeshLibManager.addGlobalMessageObserver`。
- 合并主动上报与轮询响应。
- 校验 Mesh network UUID、source node address 和 firmware ID。
- 将 SDK stage/code 映射为 App UI state。
- 调度、暂停和停止轮询。
- 保存、恢复、消费 WiFi DFU session。
- 使用 generation ID 丢弃 stale callback。

Coordinator 不持有 UIView，不直接修改页面控件。

### WiFiFirmwareDFUSession

使用现有轻量本地偏好存储持久化 Codable session，以 Mesh network UUID + gateway unicast address 作为 key，保存：

- target firmware ID
- 是否已收到 `43 10 00`
- 最后有效 stage、percent、code
- module version
- 终态是否已由 DONE 消费

Session 规则：

- 只有 `43 10 00` 创建本轮正常 OTA session。
- 新的 `43 10 00` 覆盖旧 session。
- 页面退出不清理活动 session。
- IDLE、firmware ID 不匹配、DONE 或新一轮 accepted 清理或替换旧 session。
- 没有匹配本地 session 时，设备保留的旧终态只作诊断，不展示为本轮结果。

### WiFiFirmwareUpdatingView

自定义 UIView 只接收 App UI state，负责：

- 2 pt 进度线。
- 右侧百分比。
- 主状态文案和可选副文案。
- 失败图标 `alert_failed`。
- 成功图标 `sync_success_small`。

View 不发送协议、不持有 timer、不解释 SDK stage/code。

### WiFiFirmwareUpdateViewController

Controller 负责：

- 绑定 Current version、New version、updating view 和底部按钮。
- 展示及关闭 `XWHUDManager`。
- 将 UPGRADE、UPGRADE AGAIN、DONE 事件交给 coordinator。
- 页面可见时启动恢复流程和 observer，页面不可见时停止页面轮询并移除 observer。

共享 `FirmwareVersionViewController` 只增加必要的布局和按钮 hook。BLE/Mesh 默认实现和行为保持不变。

## 页面布局

- NavigationBar 与 bottom button 之间的主内容使用 UIScrollView。
- 现有云端版本、New version、Current version 的视觉样式保持不变。
- `WiFiFirmwareUpdatingView` 位于 Current version 底部下方 32 pt。
- updating view 左右距屏幕 36 pt。
- updating view 高度由子视图约束自动计算，最小约 94 pt。
- 上述 WiFi DFU 新布局不使用 `SCRX/SCRY` 缩放宏。
- bottom button 保持在安全区底部，不随主内容滚动。
- 小屏设备可滚动查看全部版本和 OTA 状态内容。

## 页面加载与请求顺序

云端 latest 请求可独立执行，Mesh 请求必须串行：

1. 页面可见后先发送一次 `43 11` 恢复查询。
2. 若存在本地未结束 session，且设备状态的 firmware ID 匹配，则恢复 OTA UI并继续轮询，不发送 `43 14`。
3. 若没有匹配的活动 OTA，再发送 `43 14` 获取 Current version。
4. Current version 与 New version 均有效，且 New version 更高时，UPGRADE 才可用。

这样避免 OTA 期间 `43 14` 返回 busy，也避免同一 Vendor Status 通道出现不必要的并发等待。

## 启动升级流程

1. 用户点击 UPGRADE 或 UPGRADE AGAIN。
2. Controller 显示现有 Loading HUD，底部操作暂时不可重复触发。
3. App 根据当前 region、filename、version 构造 URL 和 firmware ID。
4. SDK metadata 校验失败时不发送 Mesh 命令，关闭 HUD并显示 `upgradeFailed`。
5. 发送 `43 10` 并等待 ACK。
6. 收到 accepted：关闭 HUD，创建 session，展示 OTA state view并启动 `43 11` 轮询。
7. 收到明确失败：关闭 HUD，不创建本轮正常 session，显示对应失败状态。
8. 发送超时或未收到合法 ACK：关闭 HUD，显示 `connFailedTimeout`。

Loading HUD 只覆盖等待 `43 10` ACK 的阶段，不覆盖整个 OTA。

## 轮询与主动上报

- `43 10 00` 后每 2 秒发起一次 `43 11`。
- 单次查询 timeout 为 5 秒。
- 上一次请求完成后才能调度下一次，禁止重叠。
- 主动上报和轮询响应进入同一状态归并入口。
- 页面不可见时停止查询；重新可见时立即查询一次。
- 收到终态、IDLE、目标 firmware ID 不匹配或 DONE 后停止轮询。
- 连续查询 timeout 不直接判定设备 OTA 失败，不开放 UPGRADE AGAIN；前 3 次保持 2 秒调度，达到 3 次后保留最后状态并改为每 10 秒重试，收到任一合法匹配状态后恢复 2 秒调度。
- 活动 session 的 `43 11 ret!=0`、无法解析的短响应或传输 timeout 均按查询失败处理：保留最后状态并重试，不伪造设备终态。
- 没有活动 session 时，恢复查询失败只保留默认页面，随后继续执行 `43 14`；不显示 OTA 失败。
- App 失去 Mesh 连接时不擅自判定设备升级失败；连接恢复后查询 retained status。

## 协议到 UI 的状态映射

| 协议或传输结果 | UI 状态 | 进度 | 底部按钮 |
|---|---|---|---|
| `43 10` 发送超时或无合法 ACK | `connFailedTimeout` | 0% | `UPGRADE AGAIN` enabled |
| `43 10 ret=0x04` | `connFailedServerUnable` | 0% | `UPGRADE AGAIN` enabled |
| `43 10` 其它明确失败 | `upgradeFailed` | 0% | `UPGRADE AGAIN` enabled |
| metadata 本地校验失败 | `upgradeFailed` | 0% | `UPGRADE AGAIN` enabled |
| `DOWNLOADING` | `downloading` | 协议 percent | `CANCEL` disabled |
| `VERIFYING/VERIFY_OK/REBOOTING/RECOVERING/VERSION_CHECK` | `updating` | 协议 percent | `CANCEL` disabled |
| `VERIFY_FAIL` | `downloadFailed` | 协议 percent | `UPGRADE AGAIN` enabled |
| `FAILED + NO_NET/HTTP/SIZE` | `downloadFailed` | 协议 percent | `UPGRADE AGAIN` enabled |
| 其它 `FAILED` | `upgradeFailed` | 协议 percent | `UPGRADE AGAIN` enabled |
| `TIMEOUT` | `upgradeFailed` | 最后进度 | `UPGRADE AGAIN` enabled |
| 未知 stage/code | `upgradeFailed` | 收紧到 0...100 | `UPGRADE AGAIN` enabled |
| `SUCCESS` 且 firmware ID 匹配 | `upgradeComplete` | 100% | `DONE` enabled |
| `IDLE` | 默认页面 | 不显示 | 按版本比较决定 UPGRADE |

补充规则：

- UI percent 始终收紧到 `0...100`。
- `percent=100` 不等于成功。
- 只有匹配本轮 firmware ID 的 `SUCCESS` 才能显示 upgradeComplete。
- `connFailedServerUnable` 副文案固定为 `Unable to connect to the server`。
- 本期 CANCEL 始终 disabled，不绑定 action。

## 完成和重试

SUCCESS 时：

- 优先使用 `43 11.moduleVersion` 更新 Current version。
- module version 为空时，由于 SUCCESS 已确认当前版本与目标 firmware ID 匹配，使用 target firmware ID 更新 Current version，并在恢复正常查询条件后补一次 `43 14` 校验。

点击 DONE：

- 标记终态已消费并清理 session。
- 隐藏 updating view。
- 回到默认版本页面。
- 重新比较 Current version 与 New version。
- 两者相同或 New version 不更高时，UPGRADE disabled。

点击 UPGRADE AGAIN：

- 发起新尝试时增加 attempt generation，并暂停接受旧终态；在新的 `43 10 00` 到达前，设备保留的旧 `43 11` 仅作诊断。
- 重新构造 metadata并发送新的 `43 10`。
- 旧终态不作为新一轮结果。
- 只有新的 `43 10 00` 才建立和覆盖 session。

## 生命周期和错误处理

- 页面退出或 Controller 释放时移除 observer并取消待调度 timer。
- callback 必须验证 coordinator generation，忽略旧请求结果。
- source address、network UUID、firmware ID 任一不匹配时忽略状态。
- URL 构造失败、payload 超长、版本为空或 metadata 非法时不发送协议。
- 未知 stage/code 和格式错误永远不能映射为成功。
- App 只在主线程更新 UI。
- 不修改或替换上层页面现有 `messageDelegate`，使用 SDK global observer避免影响 Gateway 页面。

## 本地化

新增或复用以下用户可见文案，并同步 English 和简体中文：

- `Loading...`
- `CANCEL`
- `UPGRADE AGAIN`
- `DONE`
- `Connection failed`
- `Communication timeout`
- `Unable to connect to the server`
- `Downloading...`
- `Updating...`
- `Download failed`
- `Upgrade failed`
- `Upgrade complete!`

优先复用现有 key；不存在时新增 WiFi firmware 专用 key。禁止硬编码用户可见文案。

## 测试与验收

### SDK

- 新版 `43 10` 精确编码测试。
- URL 与 firmware ID 长度边界测试。
- HTTP scheme、ASCII、非法字符、payload 256 字节边界测试。
- ACK ret 全枚举解析回归。
- `43 11`、`43 14` 现有测试继续通过。
- 本地 NordicSigMeshSDK Demo generic iPhoneOS build。

### App

项目当前没有 App unit-test target，本次不为该功能新建测试 target。状态映射保持为独立纯逻辑类型，并通过 focused static contract 和实机矩阵验收。

静态 contract 覆盖：

- URL builder 使用当前 ServerRegion，而非硬编码域名。
- URL 使用固定 download path 和 query item。
- 新版 SDK metadata 字段。
- 页面 UIScrollView、updating view 间距和资源。
- 状态与按钮映射。
- observer、timer 和 stale callback 清理。
- BLE/Mesh 父页面默认行为未改变。
- 新文件包含在四个 App target 中。

运行全部现有 WiFi Gateway regression scripts，并直接构建：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

构建均使用 generic iPhoneOS、关闭 code signing，不使用 Simulator。

### 实机状态矩阵

- Current < New，UPGRADE enabled。
- Current 获取失败，New version 仍显示但 UPGRADE disabled。
- `43 10` accepted、各 ret 失败、传输 timeout。
- downloading 0/中间值/100。
- verifying、rebooting、recovering、version check。
- download failed、verify failed、upgrade failed、timeout。
- success + module version、success + empty module version。
- 页面退出再进入恢复。
- App 重启恢复本地 session。
- firmware ID 不匹配和旧终态过滤。
- DONE 后 Current version 更新且 UPGRADE disabled。

## 交付边界

本次完成后，WiFi Gateway 可以从 App 发起真实 WiFi 固件升级并展示可恢复的 OTA 状态。CANCEL 仅展示 disabled；未来新增取消协议时，应在 coordinator 增加 cancel action 和状态转换，不需要重写状态 View 或页面布局。
