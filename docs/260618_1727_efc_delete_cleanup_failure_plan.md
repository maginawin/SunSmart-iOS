# EFC Delete Cleanup Failure 修复计划

## 背景

删除真实 EFC 设备时，Delete 流程会先进入 Sync device(s) 清除关联灯组设备对 EFC 内部 publish group 的订阅。当前用户实测将组内设备断电后，清除订阅仍显示成功，说明 Delete cleanup 没有按真实 Mesh 回复判断失败。

## 问题确认

当前实现存在两个风险点：

- `SyncDevicesViewController` 中 EFC Delete cleanup 被特殊放行，导致即使底层 message handle 没有成功，也可能直接将任务置为 successful。
- `EmergencyFireControllerSyncPlanner` 当前按 node 聚合多个 `ConfigModelSubscriptionDelete` handle，一个任务内可能包含多个取消订阅动作，粒度不足，无法按单个取消订阅明确呈现失败。

这会导致 Delete 流程错误地认为 associated groups 已清理完成，后续可能进入 reset/delete，或者在用户取消删除后留下功能不完整但未标记需要同步的 EFC 状态。

## 目标行为

- Delete 进入的 Sync device(s) 只清除 associated groups 的 EFC Group 订阅。
- 每个取消订阅动作都是一个独立任务，任务成功失败由对应 Mesh handle 的真实结果决定。
- 任意取消订阅失败时，该任务失败，所属 group 不能被标记为清理完成。
- 失败 group 必须立即保留为需要同步状态，用户退出或关闭 App 后仍可看到 EFC 需要同步。
- 之后从 Edit - SAVE 进入 Sync device(s) 时，按正常 EFC 配置重新订阅失败 group，使功能恢复。
- associated groups 一开始为空，或某 group 本地已没有需要清理的订阅时，仍允许进入本地完成分支。

## 修复方案

1. 在 `SyncDevicesViewController` 中移除 EFC Delete cleanup 的无条件成功放行。
2. 增加明确的成功判定：Delete cleanup 任务只有在 message handle 全部成功，或本地空任务且不是 unsupported 时，才可成功。
3. 在 `EmergencyFireControllerSyncPlanner` 中将每个 `ConfigModelSubscriptionDelete` handle 展开为一个独立 `.deleteCleanup` task。
4. 保持 group 完成条件为 group 下所有 EFC delete cleanup task 成功后才调用 `markDeleteCleanupSucceeded`。
5. 为 `scripts/check_efc_controller_flows.sh` 增加契约检查，防止 EFC Delete cleanup 再次被无条件成功放行，且要求 planner 保持逐 handle 任务展开。

## 验证计划

- 先运行 EFC guard，确认当前代码因新契约失败。
- 修复后运行 `bash scripts/check_efc_controller_flows.sh`。
- 运行 `git diff --check`。
- 运行 iPhoneOS build：
  `xcodebuild -workspace SunSmart.xcworkspace -scheme SunSmart -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

## 手工验收建议

- 关联 group 内至少一个灯设备断电。
- 删除 EFC 进入 Delete Sync device(s)。
- 对断电灯的取消订阅任务应失败，group 不应从 EFC associate groups 中移除。
- 退出 Delete 流程或直接关闭 App 后，EFC 应仍显示需要同步。
- 重新 Edit - SAVE 进入 Sync device(s)，应为失败 group 重新订阅 EFC Group。
