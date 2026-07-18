# WiFi Gateway RSSI 10 秒轮询设计

## 目标

将 WiFi Gateway 详情页中 `43 0F` RSSI 状态查询的下一次请求等待时间从 5 秒延长到 10 秒，同时保留当前 completion-driven 串行调度、首次立即请求、2 秒请求超时和全部生命周期门槛。

## 已确认方案

采用方案 A：每次 RSSI 请求收到响应或达到 2 秒 hard timeout 后，再等待 10 秒发起下一次请求。

这里的“10 秒 1 次”明确解释为 completion-to-next-start delay，而不是固定 start-to-start 10 秒：

- 正常快速响应时，相邻两次请求的发送间隔约为 10 秒加本次响应耗时。
- 请求达到 2 秒超时时，相邻两次请求的发送间隔约为 12 秒。
- 首次满足轮询条件时仍立即请求，不先等待 10 秒。

## 当前架构

RSSI 轮询由 `WiFiGatewayViewController` 独立负责：

1. `startWiFiRSSIStatusRefresh()` 校验页面与设备状态，然后立即发起一次请求。
2. `refreshWiFiRSSIStatus()` 通过现有串行 Wi-Fi request slot 发送 `.wifiGatewayRSSIStatus`。
3. 请求 completion 在响应或 timeout 后调用 `scheduleNextWiFiRSSIStatusRefresh()`。
4. `scheduleNextWiFiRSSIStatusRefresh()` 使用不重复的一次性 Timer 延迟下一次请求。
5. `stopWiFiRSSIStatusRefresh()` 负责在生命周期或状态不再满足时取消待执行 Timer。

本次设计不改变上述职责和调用关系。

## 修改范围

### App

在 `SunSmart/Main/Device/Gateway/Controller/WiFiGatewayViewController.swift` 中，仅将 `wifiRSSIStatusPollDelay` 从 5 秒调整为 10 秒。

保持以下行为不变：

- `wifiRSSIStatusRequestTimeout` 仍为 2 秒。
- 页面可见、node 已完成 key bind、node 在线且 `networkConnectState == .connected` 才允许轮询。
- 首次启动立即发送 RSSI 请求。
- 使用 completion-driven one-shot scheduling，不恢复 repeating Timer。
- 请求无法启动时仍延迟后重试，不形成紧循环。
- 页面离开、node 离线、Wi-Fi 非 connected、Disconnect 或 recovery 开始后停止轮询。

### Contract

在 `scripts/check_wifi_gateway_wifi_status_header.sh` 中，将当前“completion 后等待 5 秒”的源码契约更新为 10 秒，并保留以下断言：

- 单次请求 timeout 为 2 秒。
- 调度使用 `scheduleNextWiFiRSSIStatusRefresh()`。
- Timer 为 one-shot。
- 旧的 fixed repeating polling interval 不得恢复。
- RSSI 请求的启动、停止、解析和 header 映射契约保持存在。

### 文档

保留本设计文档和前置分析文档，记录“10 秒”的准确时间语义，避免后续将其误解成固定 start-to-start cadence。

## 明确不在范围内

- 不修改 NordicSigMeshSDK 或 `43 0F` wire format、response parsing、response matching。
- 不修改 RSSI 分级、Internet status、`No Signal`、`No Internet` 或 `Unknown` 的 UI 映射。
- 不修改国际化或资源。
- 不修改 `connectionPollInterval` 及连接 Wi-Fi 过程中的 `43 0E` polling。
- 不修改 `GatewayViewController` 的通用 signal refresh timer。
- 不修改 `MeshNodeHeartbeatManager`；日志中的 `ConfigDefaultTtlGet` 属于独立 heartbeat 链路。
- 不新增配置项、远程开关或用户设置入口。

## 数据流与生命周期

### 启动

当 WiFi Gateway 页面可见且 Wi-Fi 连接状态确认是 connected 时，现有入口调用 `startWiFiRSSIStatusRefresh()`，立即发送第一条 `43 0F`。

### 成功响应

收到 `wifiGatewayRSSIStatus` typed response 后，继续沿现有逻辑更新 header，然后创建一个 10 秒 one-shot Timer。

### 失败或超时

response 无效或 2 秒超时时，继续沿现有逻辑显示 `No Signal`，然后创建一个 10 秒 one-shot Timer。调整 polling delay 不改变错误呈现。

### request slot 被占用

如果现有串行 Wi-Fi request slot 正在处理其他请求，RSSI 请求不会并发插入；当前尝试未启动后，仍等待 10 秒再尝试。

### 停止

页面不可见、node 未完成 key bind、node 离线或 Wi-Fi 不再 connected 时，取消待执行 Timer，不再发送后续 RSSI 请求。

## 风险与控制

- 风险：只改业务常量而遗漏 contract，会让回归脚本继续要求旧的 5 秒。
  - 控制：先更新 contract 并确认其在旧实现上失败，再修改业务常量使其通过。
- 风险：误改 2 秒 request timeout，导致失败反馈变慢。
  - 控制：保留独立 timeout 断言。
- 风险：把需求实现成 repeating Timer，重新引入重叠或无效触发。
  - 控制：保留 one-shot 与 completion-driven 结构断言。
- 风险：共享代码影响多个品牌 target。
  - 控制：完成四个 generic iPhoneOS Debug target 构建。

## 验收标准

1. 页面首次满足 RSSI 轮询条件时立即发送一次 `43 0F`。
2. 每次响应 completion 或 2 秒 timeout 后，下一次请求等待 10 秒。
3. 不产生并发 RSSI 请求或 repeating Timer。
4. 页面离开、Gateway 离线或 Wi-Fi 非 connected 后停止轮询。
5. RSSI 与 Internet status 的解析、分级和 header 展示保持不变。
6. `ConfigDefaultTtlGet` heartbeat 和其他 Gateway polling 保持不变。
7. focused contract、`git diff --check` 以及 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 generic iPhoneOS Debug 构建通过。
