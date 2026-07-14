# WiFi Gateway 固件升级 App 需求分析

## 结论

当前 SDK 已具备 `43 10`、`43 11`、`43 14` 的编解码与强类型结果，App 页面也已有当前版本、云端最新版本和升级按钮的基础能力。但需求尚不能直接进入实现，真实升级链存在一个后端数据阻塞项，并且需要补齐 OTA 会话归属、页面恢复、状态映射、轮询退出和无取消协议时的交互边界。

## 已核实的现状

- `WiFiFirmwareUpdateViewController` 已通过 `43 14` 查询 Current version，仅当 New version 高于有效 Current version 时启用 UPGRADE。
- 云端 latest 请求当前只保存 `version`、`url`、`filename`、`size` 等通用固件字段，没有结构化保存 WiFi DFU 所需的 `sha256` 和固件镜像 size。
- 实际日志中的 `url` 是预签名 `https://...zip`，`size=653363` 是 ZIP 包大小；描述文本中的 `Image Size: 1006672` 和 `SHA256` 不是可靠的结构化业务字段。
- `43 10` 要求 `http://`、64 字节十六进制 SHA256、实际固件字节数和 `firmware_id`，完整 payload 不超过 256 字节。当前云端响应不能安全组出合法 metadata。
- SDK 已提供 `WiFiGatewayDFUMetadata` 参数校验、`WiFiGatewayDFUStartResult`、`WiFiGatewayDFUStatusResult`、完整 stage/code 枚举。
- SDK 已提供 `MeshLibManager.addGlobalMessageObserver`，可以在不替换页面上层 `messageDelegate` 的情况下接收网关主动上报的 `43 11`。
- App 已有 `XWHUDManager.showCustomHUD`，视觉和行为接近 Figma 的 Loading 弹窗，应优先复用。
- `alert_failed`、`sync_success_small` 两个资源已经存在，无需新增图片资源。

## Figma 核对结果

- Loading alert：白色圆角提示层，Loading 动画加 `Loading...`。
- 状态 View：进度线宽 2，右侧显示百分比；Downloading 使用主题色进度，失败使用 `alert_failed`，成功使用 `sync_success_small`。
- 状态文案包括 `Connection failed`、`Communication timeout`、`Unable to connect to the server`、`Downloading...`、`Updating...`、`Download failed`、`Upgrade failed`、`Upgrade complete!`。
- 页面实现应复用现有主题色和字体，不照搬 Figma 生成代码；指定区域不使用 `SCRX/SCRY` 缩放宏。

## 必须补齐的服务端数据契约

建议由 latest API 为 WiFi 固件增加结构化字段，或提供专用 WiFi DFU metadata 接口：

- 可由网关直接下载的短 `http://` 固件镜像 URL，不是 ZIP URL；URL 与 firmware ID 组合后必须满足业务 payload 不超过 256 字节。
- 固件镜像的 64 字节十六进制 SHA256。
- 固件镜像的实际字节数，范围为 `1...UInt32.max`。
- 目标 `firmware_id`，建议不带前导 `v`，长度 `1...32`。
- URL 有效期必须覆盖网关开始下载的时间窗口。

不建议从 `describe` 文本解析 Image Size/SHA256，也不建议把现有 ZIP 的 URL/size 直接发给网关。

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
| `43 10 ret=0x04 internetUnavailable` | `connFailedServerUnable`，但建议把副文案改为 Internet unavailable | `UPGRADE AGAIN` |
| `43 10` 其它明确失败或本地 metadata 校验失败 | `upgradeFailed` | `UPGRADE AGAIN` |
| `stage=DOWNLOADING` | `downloading(percent)` | 无取消协议时不可提供真正可用的 CANCEL |
| `VERIFYING/VERIFY_OK/REBOOTING/RECOVERING/VERSION_CHECK` | `updating(percent)` | `CANCEL` disabled |
| `VERIFY_FAIL`，或 FAILED 且 code 为 HTTP/SIZE/NO_NET 等下载类错误 | `downloadFailed(percent)` | `UPGRADE AGAIN` |
| 其它 `FAILED`、`TIMEOUT`、保留 stage/code、状态格式错误 | `upgradeFailed(percent)` | `UPGRADE AGAIN` |
| `SUCCESS` 且 firmware ID 匹配 | `upgradeComplete(100)` | `DONE` |
| `IDLE` | 默认页面 | 按版本比较决定 UPGRADE |

`percent=100` 不表示成功，只有 `stage=SUCCESS` 才进入 upgradeComplete。

## CANCEL 边界

当前没有取消协议。把 downloading 状态的 CANCEL 做成可点击并立即恢复默认页，只会停止 App 展示，网关仍继续 OTA；这会造成状态欺骗，也可能允许用户重复发送 `43 10`。推荐本期展示 disabled CANCEL，待新增 cancel 协议后再开放。若产品必须允许“隐藏进度”，按钮文案应明确为 HIDE，并且再次进入页面仍需恢复真实 OTA 状态，不能称为 CANCEL。

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

## 当前待确认

1. 后端采用扩展 latest API 还是新增 WiFi DFU metadata API，并提供合法的短 HTTP 镜像 URL、结构化 SHA256、镜像 size、firmware ID。
2. 本期没有 cancel 协议时，是否接受 downloading 和 updating 都显示 disabled CANCEL。
3. `ret=0x04` 的 UI 副文案是否从 Figma 的 `Unable to connect to the server` 调整为更准确的 `Internet unavailable`。
