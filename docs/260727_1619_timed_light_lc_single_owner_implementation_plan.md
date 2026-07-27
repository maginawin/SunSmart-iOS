# Timed 双 Scheduler 按动作单 Owner 实施计划

## 目标

落实以下最终策略：

- Auto/On → Light LC Scheduler；
- Off、Scene Recall → 普通 Scheduler；
- 写入前清理非 Owner 同 index；
- 删除时清理全部 Scheduler。

单 Scheduler 设备自动使用唯一 Model。

## 实施约束

- 当前会话 Inline Execution。
- 执行 RED → GREEN → REFACTOR。
- 保留工作区已有 QR 扫码等无关改动。
- App 与本地 `NordicSigMeshSDK` 同步修改。
- 不执行 Git commit、merge 或 push。
- 构建仅使用 generic iPhoneOS，不使用 Simulator。

## Task 1：建立动作路由契约

修改 `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`：

1. 要求 SDK 暴露普通 Scheduler 与按 Action 选择 Owner 的接口；
2. 要求 `turnOn` 优先 Light LC；
3. 要求 `turnOff`、`sceneRecall` 使用普通 Scheduler；
4. 要求单 Model 自动回退；
5. 要求 Set 先清理非 Owner，再写 Owner；
6. 要求 Delete 遍历全部 Scheduler Models；
7. 要求缓存与读取保留 Model 维度。

先运行测试确认旧的“全部 Action 统一 Light LC”实现失败。

## Task 2：SDK Action Owner

修改本地 SDK：

- `Node+SupportModels.swift`
- `MeshScheduleServer.swift`

实现：

1. `ordinarySchedulerSetupModel`；
2. `schedulerSetupModel(for:)`；
3. `schedulerCleanupModels(for:)`；
4. SDK 公开 Set API 使用同一套 Action Owner 和清理顺序；
5. 保留原 `schedulerSetupModel`，避免影响其他 SDK 业务。

## Task 3：App 写入与删除

修改 `Node+MessageHandles.swift`：

1. 非删除写入根据 `Schedule.action` 选择 Owner；
2. 先向非 Owner 写无效 entry；
3. 再向 Owner 写目标 entry；
4. 删除直接遍历全部 Scheduler Setup Models；
5. Target Type 与 Group 当前状态不参与路由。

## Task 4：缓存投影与同步判定

修改 `MeshNetwork+SunSmart.swift` 及 Scheduler 回调入口：

1. 按 `MessageHandle.model` 更新 `allSchedulerModelEntrys`；
2. 根据 App 逻辑 Action 重建 `schedulerActions`；
3. 删除态回退 entry Action，直到全部物理 entry 清除；
4. `needsSync` 检查 Action Owner 内容与全部非 Owner 残留；
5. `needsDelete` 检查全部 Scheduler Models；
6. 只有全部 Model 同 index 均已清除才完成本地删除。

## Task 5：SDK 多 Model 读取

修改：

- `Node+Messages.swift`
- `MeshScheduleServer.swift`

实现：

1. 全部 Scheduler Models 分别读取；
2. Status 后续 Action Get 保持来源 Model；
3. Action Status 按来源 Model 缓存；
4. SDK 兼容投影按 entry Action 选择 Owner；
5. 无效 entry 从对应 Model 缓存移除。

## Task 6：历史入口收口

检查 Timed、Group、Space、Restore、Fast Add、Site Add 等入口，统一复用 Schedule 消息生成器；Dongle collection Scheduler 保持独立。

## Task 7：验证

1. 运行 `scripts/check_timed_scheduler_single_owner.sh`；
2. App 与本地 SDK 分别运行 `git diff --check`；
3. 构建 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart`；
4. 全部使用 generic iPhoneOS 与 `CODE_SIGNING_ALLOWED=NO`；
5. 记录真机尚未覆盖的 AUTO、Off、Scene Recall、Action 切换、删除与 16 条容量验收。
