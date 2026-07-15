# WiFi Gateway 固件升级 App 需求分析

## 结论

`43 10` 已更新为只携带 URL 和 firmware ID，App 页面也已有当前版本、云端最新版本和升级按钮的基础能力。新的 App 区域 HTTP host + OTA download endpoint + filename 拼接规则已通过实际请求验证，返回可下载的固件镜像，服务端数据来源阻塞已解除。本地 SDK 仍按旧协议编码 SHA256 和 size，需要先同步新协议。

## 已核实的现状

- `WiFiFirmwareUpdateViewController` 已通过 `43 14` 查询 Current version，仅当 New version 高于有效 Current version 时启用 UPGRADE。
- 云端 latest 请求已有 `version`、`url`、`filename`。`version=v0.4.0` 可按“去掉最多一个前导 v/V”得到 `firmware_id=0.4.0`。
- 新 `43 10` 只要求 `http://` URL 和 `firmware_id`，payload 长度为 `5 + url_len + firmware_id_len`；若 256 字节上限仍保留，则示例无签名 URL 长 129、firmware ID 长 5，总 payload 长 139，长度合法。
- 正确 URL 规则为 `{app_region_http_host}/sitespace/ota/download?key={filename}`。示例 URL 长 148、firmware ID 长 5，新 payload 总长为 158，低于 256 字节上限。
- 示例 URL 已通过实际 GET 验证并返回 `200 OK`、`Content-Type: application/octet-stream`、`Content-Disposition: app_update.bin` 和 `Content-Length: 1006672`，服务端负责根据 ZIP key 返回实际固件镜像。
- 本地 SDK 当前 `WiFiGatewayDFUMetadata` 仍要求 `url/sha256/size/firmwareID`，`SunricherVendorSet` 仍会编码 SHA256 和 size，尚未同步本次协议更新。
- SDK 已提供 `WiFiGatewayDFUStartResult`、`WiFiGatewayDFUStatusResult` 和完整 stage/code 枚举。
- SDK 已提供 `MeshLibManager.addGlobalMessageObserver`，可以在不替换页面上层 `messageDelegate` 的情况下接收网关主动上报的 `43 11`。
- App 已有 `XWHUDManager.showCustomHUD`，视觉和行为接近 Figma 的 Loading 弹窗，应优先复用。
- `alert_failed`、`sync_success_small` 两个资源已经存在，无需新增图片资源。

## Figma 核对结果

- Loading alert：白色圆角提示层，Loading 动画加 `Loading...`。
- 状态 View：进度线宽 2，右侧显示百分比；Downloading 使用主题色进度，失败使用 `alert_failed`，成功使用 `sync_success_small`。
- 状态文案包括 `Connection failed`、`Communication timeout`、`Unable to connect to the server`、`Downloading...`、`Updating...`、`Download failed`、`Upgrade failed`、`Upgrade complete!`。
- 页面实现应复用现有主题色和字体，不照搬 Figma 生成代码；指定区域不使用 `SCRX/SCRY` 缩放宏。

## 更新后的 URL 构造规则

App 不使用 latest response 中的 S3 预签名 `url` 作为 `43 10` 参数，只使用 response 的 `filename`：

1. 读取 `UserData.currentServerRegion.baseURL`，保留当前区域 host 和 `/srv2` 基础路径，仅把 scheme 从 HTTPS 改为 HTTP。
2. 追加固定下载路径 `/sitespace/ota/download`。
3. 使用 URL query item 添加 `key=filename`，由 URL API 完成必要的 percent encoding，不做裸字符串拼接。
4. 生成后校验 scheme 为 `http`、URL 可转换为 ASCII、firmware ID 长度为 `1...32`，并校验完整业务 payload `5 + url_len + firmware_id_len <= 256`。

当前四个区域分别沿用 China Mainland、Asia Pacific、North America、Europe 的现有 baseURL，不在 WiFi DFU 页面硬编码 `www.mericher.com`。下载 endpoint 已验证会返回 `app_update.bin`，因此 App 无需下载或解压 ZIP。

## 推荐状态查询策略

1. 进入页面时发送一次 `43 11`，用于恢复 App 已知且尚未结束的本轮 OTA；不在 IDLE/default 页面永久轮询。
2. 页面可见期间注册全局消息 observer，接收目标 node 主动上报的 `43 11`。
3. 用户点击 UPGRADE，校验云端 metadata 后发送 `43 10`，Loading HUD 只覆盖等待该命令 ACK 的阶段。
4. 仅当 `43 10` 返回 accepted，记录本轮目标 `firmware_id` 并启动串行轮询；每次上一请求完成后再调度下一次，避免 ACK 冲突和请求重叠。
5. 仅接受来源 node 正确且 `firmware_id` 与本轮目标匹配的状态。IDLE、空 firmware ID、旧轮次或其它目标只作诊断，不展示为本轮升级。
6. 收到终态、页面不可见、会话被明确结束时停止轮询；主动上报与轮询共用同一个状态归并入口。
7. 为支持返回页面和 App 重启后的恢复，持久化 node/site 维度的目标 firmware ID、是否已收到 `43 10 00`、是否已由 DONE 消费。协议没有 transaction ID，因此同一 firmware ID 多轮升级无法仅靠设备状态完全区分；新一轮 `43 10 00` 必须覆盖本地旧会话。

## 推荐协议到 UI 的映射

| 协议/传输结果 | UI 状态 | 底部按钮 |
|---|---|---|
| `43 10` 发送超时、未收到合法 ACK | `connFailedTimeout` | `UPGRADE AGAIN` |
| `43 10 ret=0x04 internetUnavailable` | `connFailedServerUnable`，副文案保持 Figma 的 `Unable to connect to the server` | `UPGRADE AGAIN` |
| `43 10` 其它明确失败或本地 metadata 校验失败 | `upgradeFailed` | `UPGRADE AGAIN` |
| `stage=DOWNLOADING` | `downloading(percent)` | `CANCEL` disabled |
| `VERIFYING/VERIFY_OK/REBOOTING/RECOVERING/VERSION_CHECK` | `updating(percent)` | `CANCEL` disabled |
| `VERIFY_FAIL`，或 FAILED 且 code 为 HTTP/SIZE/NO_NET 等下载类错误 | `downloadFailed(percent)` | `UPGRADE AGAIN` |
| 其它 `FAILED`、`TIMEOUT`、保留 stage/code、状态格式错误 | `upgradeFailed(percent)` | `UPGRADE AGAIN` |
| `SUCCESS` 且 firmware ID 匹配 | `upgradeComplete(100)` | `DONE` |
| `IDLE` | 默认页面 | 按版本比较决定 UPGRADE |

`percent=100` 不表示成功，只有 `stage=SUCCESS` 才进入 upgradeComplete。

## CANCEL 边界

当前没有取消协议。已确认本期 downloading 和 updating 都展示 disabled CANCEL，待新增 cancel 协议后再开放；App 不提供仅隐藏进度的伪取消行为。

## 页面与组件设计建议

- 保留 `WiFiFirmwareUpdateViewController` 作为 WiFi 专用编排层，不把 DFU 状态机塞进共享 BLE/Mesh 父类。
- 新增独立 `WiFiFirmwareUpdatingView`，输入为 App 层 UI state，只负责进度线、百分比、状态图标和文案渲染。
- 新增 WiFi DFU session/coordinator，负责 metadata 校验、`43 10`、`43 11`、主动上报、轮询、归属过滤和会话持久化；ViewController 只绑定状态与按钮事件。
- 共享父页面需要增加少量受控布局/按钮 hook，让 WiFi 子类把 NavigationBar 与 bottom button 之间改成 UIScrollView，并在 Current version 下方插入状态 View；BLE/Mesh 默认行为不变。
- `WiFiFirmwareUpdatingView` 左右 36、距 Current version 底部 32，内容高度按约束自适应且最小约 94，不使用缩放宏。
- 所有新增用户文案同步 English 和 zh-CN；四个 target 共用该页面，需要全部编译验证。

## 测试与验收重点

- 纯状态映射单元测试：全部 stage/code、percent 边界、保留值、错误 ACK、firmware ID 不匹配。
- coordinator 测试：accepted 后才轮询、请求不重叠、终态停止、页面恢复、DONE 消费、旧状态过滤、主动上报与轮询去重。
- 静态 UI contract：滚动容器、间距、资源、按钮状态、父类默认行为未变、多 target source membership。
- SDK typed API 编译联动和现有 WiFi Gateway regression scripts。
- `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 generic iPhoneOS build。

## 已确认的交互边界

1. 本期没有 cancel 协议，downloading 和 updating 都显示 disabled CANCEL。
2. `ret=0x04` 使用 `connFailedServerUnable`，副文案继续使用 Figma 的 `Unable to connect to the server`。
