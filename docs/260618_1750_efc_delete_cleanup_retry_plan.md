# EFC Delete Cleanup Retry Failure 修复计划

## 背景

在 Delete EFC 的 Sync device(s) 页面，用户点击 ProgressView 内单个取消订阅任务重试后，日志显示设备回复 `ConfigModelSubscriptionStatus(status: Success)`，但 UI 仍提示 Failure。该现象需要区分两类状态：

- 当前重试的单个 task 是否成功；
- 整个 Sync device(s) 页面是否因为其他 task 仍失败而继续显示 Failure。

当前代码缺少针对 EFC Delete cleanup 的独立成功判定与诊断日志，ProgressView 单 task 重试也只重置 `state`，未完整清理本轮 task 状态。

## 存疑点

- 同步结果成功判定仍通过 `isBatteryPowerSwitchOperationSuccessful(...)` 这个 Battery Power Switch 命名的 helper 统一处理，EFC Delete cleanup 没有独立语义。
- `.emergencyFireController` 的 `operationSuccessful` 只表达 task 是否 supported，不能说明 Delete cleanup 的真实取消订阅结果。
- ProgressView 单 task 重试仅设置 `task.state = .none`，没有统一重置 `isFineshed`、`failedCount` 和父级 finished 状态。
- 缺少 finished 后的 task 级日志，无法判断 UI 中 Failure 来自当前 task 还是其他 task。

## 修复方案

1. 新增通用同步成功判定 helper，统一入口命名为 `isSyncOperationSuccessful(...)`。
2. 为 EFC Delete cleanup 增加独立成功判定：
   - 有 message handle 时，以 `resultSuccessful` 为准；
   - 空 message handle 仍由现有 empty-task 分支处理；
   - unsupported task 仍失败。
3. ProgressView 单 task retry 改为调用 `prepareTaskForResync(_:)`：
   - 重置 task state、`isFineshed`、`failedCount`；
   - 重置 parent step/device 的 `isFineshed` 和选择态；
   - 保持其他已 successful task 不变。
4. 增加 EFC Delete cleanup finished 诊断日志，输出 task、group、node、handle 成功状态和同 group 剩余失败数量。
5. 更新 `scripts/check_efc_controller_flows.sh` 保护上述约束。

## 验证计划

- 先运行 EFC guard，确认新增契约在旧代码下失败。
- 修复后运行 `bash scripts/check_efc_controller_flows.sh`。
- 运行 `git diff --check`。
- 运行 iPhoneOS build：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 手工验收建议

- Delete EFC 进入 Sync device(s)，让某个取消订阅 task 失败。
- 恢复设备在线后，在 ProgressView 中点击该 task 的 retry。
- 若日志收到 `ConfigModelSubscriptionStatus(status: Success)`，该 task 应显示成功。
- 若页面仍显示 Failure，日志应能列出同 group 或全局仍失败的其他 task。

## 2026-06-18 自动重试补充

### 需求

Delete EFC 的 Sync device(s) 任务列表中，group 设备取消订阅失败时，不应第一次失败就立刻标记 task failed。每个 EFC Delete cleanup task 需要自动重试 2 次，再最终进入失败状态。

### 实现

- 重试策略只作用于 EFC Delete cleanup task，不扩展到普通 Sync task 或底层 `MeshProxyMessageCommand`。
- 单个取消订阅 task 最多发送 3 次：首发 1 次，加 2 次自动重试。
- 每次失败尝试后，若还可重试，先清空 `MeshMessageHandle.respondAddresss` 和 `notRespondAddresss`，再延迟 200ms 重新发送。
- 延迟重试的目的，是给 `MeshProxyMessageCommand` 本轮 finished 后的内部 reset 留出时间，避免新尝试进入上一轮发送队列。
- 日志增加 `attempt`、`maxAttempts` 和 `willRetry`，用于判断现场失败是中间尝试还是最终失败。

### 验证

- `bash scripts/check_efc_controller_flows.sh`
- `git diff --check`
- `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
