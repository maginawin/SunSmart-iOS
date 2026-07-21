# WiFi Firmware Update 重新进入 OTA 状态修复总结

## 1. 结果

已按确认的方案 A 修复 WiFi Firmware Update 页面重新进入后直接回放 stale `Upgrade failed`、不发送 `0x43/0x11` 获取 Gateway 当前 OTA 状态的问题。

新的页面可见周期或 App 重启恢复任何未消费 session 时，无论缓存为非终态、失败、取消还是成功终态，都会先打开权威查询门。只有本次 `43 11` 返回完整、合法且身份匹配的状态后，才能重新确认当前 OTA UI。

同一个页面周期内的首终态锁定保持不变，不会恢复终态轮询或接受后续乱序 EVENT。

## 2. 修改内容

### 2.1 Session 恢复策略

`WiFiFirmwareDFUSession` 新增集中恢复策略：

- 未消费 session 在页面恢复时统一设置 `requiresAuthoritativeQuery`。
- 查询资格定义为“未消费且为非终态，或正在等待权威恢复”。
- 同页已确认终态且未进入恢复周期时仍不可查询。

### 2.2 权威响应策略

新增 Foundation-only authoritative recovery decision：

- 匹配 `ota_id + firmware_id` 的状态：接受并重建 fresh reducer 基线。
- 缓存终态遇到 IDLE、其它 `ota_id` 或其它 `firmware_id`：判定缓存终态已经 stale，清理 session，回到默认 UI并查询 `43 14` Current version。
- 缓存非终态遇到相同不匹配响应：保留 session，进入 communication unknown 并继续恢复查询，避免一次异常响应误删活动升级。
- 不接管其它事务。

### 2.3 Coordinator 生命周期

- 磁盘恢复后不再直接信任终态缓存，而是先打开权威查询门。
- `deactivate()` 对所有未消费 session 保存恢复门，包括失败、取消和成功终态。
- `refresh()` 先处理权威查询，再处理同页内存终态回放。
- 首次查询失败、延迟调度和代理重连统一使用新的查询资格，恢复终态不会在第一次 timeout 后失去重试能力。
- stale 终态清理后发出 idle UI event，并查询 Gateway Current version。

### 2.4 测试与 contract

- focused tests 新增非终态、失败终态、成功终态、已消费 session 的页面恢复矩阵。
- 新增匹配、IDLE、其它 OTA ID、其它 firmware ID，以及活动/终态 session 的权威决策矩阵。
- static contract 检查恢复策略接线、权威查询优先级、终态查询资格和 stale 清理分支。

## 3. TDD 证据

### RED

Session focused test 首次编译失败，错误明确为缺少：

- `prepareForPageRecovery`
- `isStatusQueryEligible`
- `WiFiFirmwareDFUAuthoritativeRecoveryPolicy`

Coordinator static contract 首次失败为：

`FAIL: restored session must require authoritative status`

### GREEN

实现最小恢复策略和 coordinator 接线后：

- `WiFiFirmwareDFUStatusReducerTests passed`
- `WiFiFirmwareDFUMetadataBuilderTests passed`
- `WiFiGatewayDFUStatusV19Contract passed`
- `WiFiGatewayDFUStartV19Contract passed`
- `PASS: WiFi Gateway firmware update static checks`

## 4. iPhoneOS 构建

以下 Debug generic iPhoneOS 构建均使用 `CODE_SIGNING_ALLOWED=NO`，并以 `** BUILD SUCCEEDED **` 结束：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

## 5. Scope 检查

本任务没有修改：

- NordicSigMeshSDK
- BLE OTA 或 Mesh OTA
- 本地化或用户可见文案
- 图片、资源、依赖
- Xcode target 配置或 project file

工作区原有 `WiFiFirmwareUpdateViewController.swift` 相同版本允许升级实验改动已保留，没有被本任务覆盖或改写。

`docs/260721_1036_timed_datetime_timezone_sync_analysis.md` 为进入本任务前已存在的未跟踪文件，本任务未修改。

## 6. 未覆盖项

- 尚未在真实 WiFi Gateway 上执行退出/重进、离线重连、IDLE stale 清理和离开期间成功/失败的完整实机矩阵。
- 构建与 focused tests 证明代码、策略和 target 集成有效，但不能替代真机 Mesh 时序验证。

## 7. 建议实机重点

1. DOWNLOADING 中退出再进入，确认先发 `43 11` 并恢复当前进度。
2. 缓存 `Upgrade failed`、设备当前 IDLE，确认 `43 11 IDLE` 后清理旧失败并继续查询 `43 14`。
3. 进入页面时 Proxy 未连接，确认 connection 恢复后立即补发 `43 11`。
4. 离开期间设备进入 SUCCESS/FAILED，确认重新进入以 Gateway 返回状态为准。
