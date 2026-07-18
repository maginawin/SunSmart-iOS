# WiFi Gateway RSSI 轮询间隔分析与方案

## 结论

当前 WiFi Gateway 页面中的 RSSI 轮询不是固定重复 Timer，而是按请求完成结果串行调度：

- 页面可见、Gateway 已完成 key bind、节点在线且 Wi-Fi 状态为 connected 时启动轮询。
- 首次启动时立即发送一次 `wifiGatewayRSSIStatus`（协议参数 `43 0F`）请求。
- 单次请求的 hard timeout 为 2 秒。
- 收到响应或请求超时后，再等待 5 秒发送下一次请求。
- 因此正常响应时，相邻两次请求的实际发送间隔约为“响应耗时 + 5 秒”；超时时约为 7 秒。
- 页面离开、Gateway 离线、Wi-Fi 断开、进入连接/断开/修复流程时会停止轮询。

用户提供的日志没有时间戳，无法仅凭日志文本直接测量两次 `43 0F` 的时间差；但当前代码中的调度常量和一次性 Timer 已明确上述 5 秒 completion-driven 语义。

日志中夹在两次 `43 0F` 之间的 `ConfigDefaultTtlGet` 属于 Mesh 节点 heartbeat/在线探测链路，不属于 WiFi RSSI 轮询，也不应在本次需求中调整。

## 代码证据

- `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift`
  - `wifiRSSIStatusPollDelay = 5`
  - `wifiRSSIStatusRequestTimeout = 2`
  - `startWiFiRSSIStatusRefresh()` 首次立即调用 RSSI 请求。
  - `scheduleNextWiFiRSSIStatusRefresh()` 使用一次性 Timer，在请求 completion 后等待 poll delay。
  - `refreshWiFiRSSIStatus()` 在响应、超时或当前请求未能启动后调度下一次请求。
- `scripts/check_wifi_gateway_wifi_status_header.sh`
  - 当前明确断言 completion 后等待 5 秒。
  - 当前明确断言请求 timeout 保持 2 秒。
- 本地 `NordicSigMeshSDK` 的 `MeshNodeHeartbeatManager.swift`
  - `ConfigDefaultTtlGet` 来自独立的 heartbeat polling。

## 备选方案

### 方案 A：将 completion 后等待时间从 5 秒改为 10 秒（推荐）

- 保持首次进入页面立即请求。
- 保持单次请求 2 秒 hard timeout。
- 每次请求完成或超时后，再等待 10 秒发送下一次。
- 正常快速响应时，相邻请求约为 10 秒加响应耗时；超时时约为 12 秒。
- 优点：改动最小，继续保证串行请求和无重叠，符合当前架构对“轮询间隔”的定义。
- 代价：严格意义上不是固定的 start-to-start 10 秒。

### 方案 B：固定为相邻请求开始时间间隔 10 秒

- 需要记录上一次请求开始时间，并在 completion 后计算剩余等待时间。
- 请求若 2 秒超时，下一次仍在上一请求发出约 10 秒后开始。
- 优点：发送节奏更接近严格的“每 10 秒一次”。
- 代价：引入额外时间计算和状态，偏离现有 completion-driven 的直接语义，对本需求没有明显收益。

### 方案 C：恢复 repeating Timer，每 10 秒触发

- 优点：表面实现简单。
- 缺点：请求耗时、请求占用或页面状态变化时更容易出现无效触发或重叠风险，会退回此前已被替换的设计，不推荐。

## 推荐设计

采用方案 A，只调整 App 层 WiFi RSSI 下一次请求等待常量及对应 contract 断言：

1. `wifiRSSIStatusPollDelay` 从 5 秒改为 10 秒。
2. 保留 `wifiRSSIStatusRequestTimeout = 2`。
3. 保留首次立即请求、一次性 Timer、completion-driven scheduling 和全部启动/停止门槛。
4. 不修改 `connectionPollInterval`、通用 Gateway signal timer、heartbeat、SDK、协议解析、UI 或国际化。

## 实施与验证计划（待确认）

1. 先更新 `scripts/check_wifi_gateway_wifi_status_header.sh`，将 contract 从“completion 后等待 5 秒”收紧为“completion 后等待 10 秒”，运行并确认在旧实现上失败。
2. 将 `WiFiGatewayViewController.wifiRSSIStatusPollDelay` 改为 10 秒，不改其他时序或业务逻辑。
3. 运行 focused contract，确认 RSSI polling、header 状态映射和生命周期契约全部通过。
4. 运行 `git diff --check`。
5. 按项目规则使用 generic iPhoneOS Debug 构建验证 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个引用共享代码的 target。
6. 复核最终 diff，确保只包含轮询 delay、对应 contract 和本分析/后续计划文档，不混入无关改动。

## 验收标准

- 进入可见的 WiFi Gateway 页面且 Gateway Wi-Fi 已连接时，首次 RSSI 请求仍立即发送。
- 每次 RSSI 请求响应完成或 2 秒超时后，下一次请求等待 10 秒。
- 任一时刻最多有一个 Wi-Fi Gateway 请求占用现有串行 request slot。
- 离开页面、设备离线或 Wi-Fi 非 connected 后不再继续 RSSI 轮询。
- 其他 Gateway、Wi-Fi connection polling、Mesh heartbeat、SDK 协议解析及 UI 展示保持现状。
