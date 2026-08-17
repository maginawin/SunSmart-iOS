# Gateway 页面 iOS 26 滚动卡帧分析与修复规划

## 结论

当前日志没有显示 Mesh 请求失败。`ConfigDefaultTtlGet/Status`、`Wi-Fi Gateway RSSI Status Get/Status` 都已正常完成，卡帧更符合主线程在滚动期间反复执行 `UITableView` 结构刷新和时间字符串格式化的表现。

当前 Wi-Fi Gateway 详情页存在两条会与滚动竞争的周期刷新链：

1. Gateway Clock 每 0.5 秒运行一次，Timer 被加入主线程 `.common` RunLoop；每次 Tick 都对 Clock Section 的 3 行执行 `reloadRows`。
2. Wi-Fi RSSI 每 5 秒自动查询一次，同样运行于 `.common` RunLoop。自动请求复用通用 Wi-Fi 请求状态，请求开始和结束会各执行一次 `reloadSection(.networkConnectivity)`。

Clock Tick 还会重复创建 `DateFormatter` 并格式化 Gateway、Local 两个时间。RSSI 回包即使仍落在同一语义档位，例如日志中的 `-47 dBm` 和 `-53 dBm` 都是 Excellent，Header 仍会重新设置图片、文案并重建约束。

因此，问题不是 `0x800C`、`0x800E`、`0xF1780A` 或 `0xF3780A` 协议错误，而是协议轮询和实时 Clock UI 共用主线程，并在 `UITableView` 正在跟踪或减速时触发了不必要的结构刷新。iOS 26 真机表现更明显，但仅凭现有证据不应把根因归类为 iOS 26 系统缺陷。

## 源码证据

### Clock 刷新链

- `GatewayViewController.syncGatewayClockTimer()` 创建 0.5 秒重复 Timer，并加入 `RunLoop.main` 的 `.common` 模式。
- `.common` 包含 UI Tracking 场景，因此手指持续拖动时 Timer 仍可执行。
- `refreshGatewayClockRows()` 每次都生成 3 个 IndexPath 并调用 `tableView.reloadRows`；其中第三行 Off by/Sync 状态并不会随每个 Tick 改变。
- Clock 两个动态时间值通过 `GatewayDetailClockCore.format` 格式化；该函数每次调用都新建 `DateFormatter`。
- 这条刷新链由 2026-08-17 的 Gateway timezone 功能引入，与本次回归时间点高度吻合。

### RSSI 刷新链

- `WiFiGatewayV19Timing.rssiPollDelay` 为 5 秒。
- `scheduleNextWiFiRSSIStatusRefresh()` 把 Timer 加入 `.common` 模式，因此滚动期间仍会发送 `0x43/0x0F`。
- `refreshWiFiRSSIStatus()` 使用 `.automatic` 请求来源发送 RSSI Get。
- `beginWiFiRequest` 和 `finishWiFiRequest` 不区分请求来源，分别刷新一次整个 Network Connectivity Section。
- RSSI 回包随后更新 Header；`GatewayHeaderStatusItemView.update` 每次都会 `remakeConstraints`。
- 日志中 `-47 dBm` 与 `-53 dBm` 均映射为 Excellent，第二次结果不需要产生任何视觉更新。

### Default TTL 心跳

- `ConfigDefaultTtlGet` 来自 SDK 的 Mesh Node Heartbeat 轮询。
- 本次日志中 `ConfigDefaultTtlStatus(ttl: 7)` 正常返回，没有超时、解密或重试异常。
- 心跳消息会增加同一时段的工作量，但没有直接触发表格刷新，不建议为了修 UI 卡帧而修改或暂停 Mesh 心跳协议。

## 推荐方案 A：消除周期任务造成的结构刷新

方案目标是保留 Clock 实时显示、Wi-Fi RSSI 5 秒轮询、Proxy Ready 和用户操作语义，只改变 UI 刷新方式。

### 1. Clock 改为可见内容原位更新

- 保留当前 0.5 秒 Tick，避免改变既有实时显示规格。
- Timer 使用 `.default` 模式，不在手指 Tracking 期间执行。
- Tick 期间若 Table 正在 Tracking、Dragging 或 Decelerating，只更新最新 Tick 时间，不刷新视图；滚动结束后补一次最新显示。
- 不再调用 `reloadRows`。只取得当前可见的 Clock Row 0、Row 1，并直接更新其时间 Label。
- Clock Row 2 的 Off by/Sync 状态只在 TimeGet、TimeSet、同步开始、同步结束、断开或时区环境变化时更新。
- 提取可复用的 Clock Cell 配置入口，确保首次显示、Cell 复用和原位 Tick 使用同一套格式化逻辑。
- 复用主线程持有的 DateFormatter，目标 Offset 变化时更新 TimeZone，避免每 0.5 秒重复创建 Formatter。

### 2. RSSI 自动轮询不再刷新 Section

- 保持 5 秒轮询间隔、响应超时、单请求串行和 Proxy Session 校验不变。
- `beginWiFiRequest`、`finishWiFiRequest` 按 `WiFiRequestOrigin` 区分 UI 策略。
- `.automatic` RSSI 请求不得调用 `reloadSection(.networkConnectivity)`。
- 如仍需在自动请求期间锁定输入，只为当前可见 Cell 增加轻量的交互状态更新方法；只修改按钮和输入控件的 Enabled 状态，不重设文本、不重建约束、不刷新 Section。
- `.userInitiated` 请求以及确实改变 SSID、Password、Connect State 或 Section 可见性的流程继续走现有业务刷新路径。

### 3. Header 更新增加语义去重

- 保存当前已显示的 Wi-Fi Header 语义状态。
- Icon、Localized Status 均未变化时直接返回。
- `GatewayHeaderStatusItemView` 的布局只在 Title 展示模式或 Icon Size 发生变化时重建；普通 RSSI 档位更新只替换必要的 Image/Text。
- `-47 dBm -> -53 dBm` 这类仍属于 Excellent 的变化不产生布局工作。

### 4. 保持协议和状态边界

- 不修改 SDK Heartbeat、Default TTL、Vendor opcode、RSSI 解析、5 秒轮询间隔和网络状态语义。
- 不把本地 Proxy Ready、Wi-Fi RSSI、Internet Status 或 Mesh Node Heartbeat 互相替代。
- 页面离开、Proxy 断开、Session 替换时继续停止或失效当前 Timer/请求，避免旧回包更新新页面。

## 不推荐方案

- 只把 RSSI 从 5 秒改成更长：只能降低复现概率，Clock 仍每 0.5 秒刷新 3 行。
- 只关闭日志：可能减少 DEBUG 构建开销，但不能消除 `reloadRows/reloadSection` 和 Formatter 创建。
- 全局关闭 Mesh Heartbeat：会破坏设备在线状态判断，且日志证明心跳响应正常。
- 针对 iOS 26 隐藏 Clock 或禁用 RSSI：属于系统版本特例，不能解决共享实现问题。
- 仅在 `scrollViewDidScroll` 中反复 Stop/Start Timer：容易产生 Timer 抖动和重复调度；应由 RunLoop 模式、滚动态门控和原位更新共同解决。

## 实施顺序

1. 先补充 Clock Tick 和 RSSI 自动请求的 UI 刷新契约测试，证明周期链不再调用 Table 的结构刷新。
2. 实现 Clock 可见 Cell 原位更新、滚动态门控和 Formatter 复用。
3. 实现自动 RSSI 请求的非结构性 Cell 交互更新。
4. 实现 Wi-Fi Header 语义去重和约束更新去重。
5. 运行聚焦测试、现有 Gateway Clock/Wi-Fi Gateway contracts、`git diff --check`。
6. 按共享 Gateway 代码影响范围，串行验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` generic iPhoneOS unsigned build。
7. 在 iOS 26 真机完成滚动和 Mesh/Wi-Fi 回归；构建成功不能替代真机帧率和 BLE/Mesh 验收。

## 测试与验收矩阵

### 自动化

- Clock Tick 不包含 `reloadRows` 或 `reloadSections`。
- Clock Tick 只更新动态时间行，不重复更新 Off by/Sync 行。
- Tracking、Dragging、Decelerating 时不执行 Clock 视图更新，结束后补最新值。
- 自动 RSSI 请求开始/完成不触发 Network Connectivity Section 刷新。
- 用户发起的 Wi-Fi 操作仍保持原有 Busy/Disabled 状态和请求串行。
- 相同 Wi-Fi Header 语义状态不会重复布局。
- Proxy 断开、页面离开、Session 替换后旧 Tick/回包不能更新 UI。

### iOS 26 真机

- Wi-Fi Gateway 已连接并持续产生 `0x43/0x0F` 时，从顶部快速滑到底部、慢速拖到底部、底部回弹和连续上下滑动均无可见停顿或跳位。
- 测试覆盖 RSSI 回包恰好发生在拖动中和减速中的场景。
- Gateway/Local 秒钟在停止滚动后最多一个 Tick 内恢复为最新显示。
- Network Connectivity 输入内容、焦点、密码显示状态不因后台 RSSI 回包被重置。
- Clock Sync、手动 Refresh、Connect/Disconnect、离页重进和 Proxy 重连行为保持正确。
- 使用 Core Animation Hitches/Time Profiler 对比修复前后，确认滚动期间不再出现由 `reloadRows`、`reloadSections`、`DateFormatter` 或 SnapKit 约束重建造成的周期性主线程峰值。

### 兼容回归

- Wi-Fi Gateway：Clock + RSSI 双周期链。
- 4G Gateway：共享 Clock 链和 10 秒 Signal 链。
- 至少一台非 iOS 26 设备验证列表内容、Clock 和按钮交互没有回归。

## 风险与边界

- 当前结论来自源码、Git 历史和用户日志，尚未取得 Instruments Trace，因此根因置信度高但不等同于真机性能采样结论。
- 自动 RSSI 请求期间的输入锁定必须使用轻量状态更新，不能通过重新配置整个输入 Cell 导致正在编辑的 SSID/Password 被覆盖。
- `GatewayViewController` 是 4G/Wi-Fi 共享基类，Clock 修复需要覆盖两类 Gateway；Wi-Fi RSSI 优化只应落在 `WiFiGatewayViewController`。
- 相关源码由四个品牌 Target 共享，实施后必须完成四 Target 构建检查。

## 建议确认项

建议采用方案 A。该方案不降低轮询能力、不改变协议、不隐藏功能，直接移除滚动期间的 Table 结构刷新，并同时处理 Clock、RSSI 和 Header 三个主线程热点。
