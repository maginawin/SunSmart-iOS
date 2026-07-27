# Timed Auto/On 按 Group Profile 路由 Scheduler 实施总结

## 1. 实施结果

已按确认的方案 A 完成 Scheduler Owner 调整：

| Action | 设备 Group/Profile 状态 | Owner |
| --- | --- | --- |
| Auto/On | 已加入非 `Manual control` Profile Group | Light LC Scheduler |
| Auto/On | 未加入任何 Group | 普通 Scheduler |
| Auto/On | 已加入 `Manual control` Profile Group | 普通 Scheduler |
| Off | 任意 | 普通 Scheduler |
| Scene Recall | 任意 | 普通 Scheduler |

原有约束保持不变：

1. 双 Model 设备只保留一个 Owner；
2. 单 Model 设备回退到唯一 Scheduler；
3. 设置前清理全部非 Owner Scheduler 的同 index；
4. 删除时清理全部 Scheduler Models 的同 index；
5. TimeSet 发送逻辑保持不变。

## 2. 主要调整

### App

- 新增独立、可测试的 Timed Scheduler Owner 纯策略；
- `Schedule` 将 Action、当前 Group、恢复目标 Group和 Group Profile 转换成 Owner；
- 写入、`needsSync` 和 App 兼容缓存投影共用同一 Owner 规则；
- Group 直接同步、Group Target 保存、Fast Add 和延迟加组同步显式传入目标 Group；
- 恢复设备使用 `restoreData.addGroup` 作为目标 Group；
- `groupState == .exitFailure` 时不再把退出中的 Group 视为有效自动 Profile；
- 新策略文件已加入 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 四个 target。

### NordicSigMeshSDK

- 新增中性的普通/Light LC Scheduler Owner 类型；
- Model 选择和非 Owner 清理不再直接解释 App 的 Action/Profile 业务；
- SDK 无 App Profile 上下文的通用 Schedule Set 使用普通 Scheduler；
- SDK 扁平 `schedulerActions` 缓存保留各 Scheduler Model 的有效 entry，不再仅根据 Action 猜测 App Owner；
- per-Model 真值继续由 `allSchedulerModelEntrys` 保存。

## 3. 既有定时影响

本次更新不会在启动时主动改写全部设备。

发生以下操作时，旧定时会按新 Owner 规则迁移：

- 编辑或重新保存定时；
- 同步相关设备；
- 同步 Group/Profile；
- 设备加入、恢复或移出 Group。

迁移时先清理旧 Owner 同 index，再写入新 Owner。因此 Profile 在 `Manual control` 与其他类型之间切换后，Group 同步任务包含 Auto/On 定时属于预期行为；成功同步后不应持续重复出现。

Off 与 Scene Recall 始终留在普通 Scheduler，不受 Profile 切换影响。

## 4. TDD 记录

### RED 1

新增 Owner 行为测试后，因生产策略文件不存在而失败。

### GREEN 1

实现最小 Owner 策略后，覆盖以下行为：

- Auto/On + 无 Group → 普通；
- Auto/On + Manual control Group → 普通；
- Auto/On + 非 Manual control Group → Light LC；
- Off、Scene Recall、No Action → 普通。

### RED 2

更新 App/SDK 路由契约后，旧 action-only SDK Owner API 和旧 App 写入路径未满足新规则。

### GREEN 2

完成 SDK 中性能力、App Group/Profile 策略、同步判断、缓存投影和目标 Group 上下文传递后，契约通过。

### Target Membership RED/GREEN

新增策略文件尚未加入 Xcode target 时，SunSmart iPhoneOS 构建按预期因找不到策略类型失败；将文件同步加入四个品牌 target 后构建通过。

## 5. 自动化与构建验证

- `scripts/check_timed_scheduler_single_owner.sh`：通过；
- App `git diff --check`：通过；
- NordicSigMeshSDK `git diff --check`：通过；
- `SunSmart.xcodeproj/project.pbxproj`：`plutil -lint` 通过；
- SunSmart generic iPhoneOS Debug：通过；
- Archipelago generic iPhoneOS Debug：通过；
- SLG Sync Plus generic iPhoneOS Debug：通过；
- SylSmart generic iPhoneOS Debug：通过。

构建仍输出工程原有 warning，包括资源符号重名、废弃 API、未使用变量和既有并发隔离提示；本次未扩大范围处理。

## 6. 尚需真机 Mesh 验收

自动化和编译不能替代设备实际 Register 验证，建议覆盖：

1. 双 Scheduler、无 Group、Auto/On；
2. 双 Scheduler、Manual control Group、Auto/On；
3. 双 Scheduler、非 Manual control Group、Auto/On；
4. Manual control 与其他 Profile 双向切换；
5. 加入 Group、恢复设备、移出 Group；
6. Off、Scene Recall 回归；
7. 编辑既有异常定时后检查旧 Owner 已清理；
8. 删除定时后检查两个 Scheduler 同 index 均无有效 entry；
9. 16 个 index 边界，确认不存在双 Model 残留导致的额外执行。
