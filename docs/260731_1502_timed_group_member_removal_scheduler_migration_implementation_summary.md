# Group Members 退组时 Timed Scheduler Owner 迁移实施总结

## 1. 结论

已按确认方案完成代码修复：

- 自动 Profile Group 退组时，退出节点的 Device Target `Turn On` 定时 Owner 迁移会进入 Remove Section 并实际参与同步；
- 迁移任务仍是 Schedule configuration，不会删除仍然有效的 Device Target 定时；
- 迁移失败不会阻止最终 `unsubscribeGroup`；
- 迁移失败仍会使 Sync Devices 聚合为失败；
- Timed 不会伪造 synchronized，仍根据设备实际 Scheduler Model 缓存展示待同步。

静态测试和四品牌 generic iPhoneOS 构建均通过。真机 Mesh 成功路径、失败路径、Manual Control 对照和重载生命周期仍待验收。

## 2. 根因

退出自动 Profile Group 时：

- `Node.getSyncData(.group)` 会为直接 Device Target 的 `Turn On` 定时生成 `.syncSchedules`，用于将 Owner 从 Light LC Scheduler 迁回 ordinary Scheduler；
- 同时会为不再适用于退出节点的 Group Target 定时生成 `.deleteSchedules`；
- `setupDataSource()` 对 `outNodes` 只接收 `removeDevice`；
- 旧实现却把 `.syncSchedules` 无条件加入 `configturationSteps`，导致这类迁移任务没有进入退出节点的 `removeDevice`，最终未执行；
- `.deleteSchedules` 正常进入 `deleteSteps` 并执行，因此设备形成“旧 Light LC entry 仍存在、ordinary Owner entry 缺失”的已知 Model 错误 Owner 状态；
- Timed 的严格判定据实返回 `owner-entry-missing` 等差异并显示待同步。

这与最近修复的“Scheduler Model 缓存未知或未持久化”不是同一个问题。本次属于退组步骤编排遗漏。

## 3. 实际改动

### 3.1 纯策略

在 `TimedSchedulerOwnerPolicy.swift` 中增加 Group Member Exit Step 策略：

- 退组上下文将 Schedule Owner 迁移路由到 Remove Section；
- 非退组上下文继续路由到 Configuration Section；
- 退组 Schedule Owner 迁移被声明为不阻止最终 Group removal。

### 3.2 Sync Devices 接线

在 `SyncDevicesViewController.getSyncDeviceModel(...)` 中：

- `.syncSchedules` 继续创建 `.configuration(...schedule...)` task；
- 退组时把该 Step 加入 `deleteSteps`；
- 同时将该 Step 记录为 non-blocking Group-exit Step；
- 组装 `removeGroupStep.relevanceStepModels` 时只排除该迁移 Step；
- 其他既有删除步骤的阻断依赖保持不变。

因此执行语义为：

1. Schedule Owner 迁移仍按现有 level 排序在 `unsubscribeGroup` 前尝试；
2. 迁移成功时，ordinary Owner 收到目标 entry，Light LC 残留被清理；
3. 迁移失败时，Schedule Step 保持 failed，但 `unsubscribeGroup` 仍可执行；
4. Sync Devices 保留失败聚合，Timed 保留真实待同步。

## 4. TDD 证据

### 4.1 第一次 RED：路由策略缺失

先新增真实行为测试，再运行：

`scripts/check_timed_scheduler_single_owner.sh`

按预期编译失败：

`cannot find 'TimedSchedulerGroupMemberExitStepPolicy' in scope`

新增最小路由策略后转为 GREEN。

### 4.2 第二次 RED：退组优先语义缺失

自审发现 `deleteSteps` 会整体成为 `removeGroupStep` 的前置依赖；若不额外处理，迁移失败会阻止退组。

先新增“迁移失败不阻止退组”行为测试，再运行同一脚本，按预期编译失败：

`type 'TimedSchedulerGroupMemberExitStepPolicy' has no member 'shouldBlockGroupExit'`

新增 non-blocking 策略并从退组阻断依赖中排除迁移 Step 后转为 GREEN。

## 5. 自动化验证

最终代码上执行：

### 5.1 Single-owner 与路由

`scripts/check_timed_scheduler_single_owner.sh`

结果：

- `TimedSchedulerOwnerPolicyTests passed`
- `TimedSchedulerSingleOwnerContractTests passed`

新增行为覆盖：

- 退组 Schedule Owner 迁移进入 Remove Section；
- 退组 Schedule Owner 迁移不阻止 Group removal；
- 普通 Schedule 同步仍进入 Configuration Section。

### 5.2 Scheduler Model 持久化

`scripts/check_timed_scheduler_persistence.sh`

结果：

- `SchedulerModelCachePersistenceTests passed`
- `SchedulerModelReadCompletionTests passed`

### 5.3 静态检查

- `git diff --check`：通过，无输出；
- 计划内生产与测试差异仅 3 个文件；
- 未修改脚本、SDK、本地化、资源、Xcode target 或依赖配置。

## 6. 四品牌 generic iPhoneOS 构建

在最终代码上分别直接运行 `xcodebuild`，全部退出码为 0：

| Scheme | 结果 |
| --- | --- |
| SunSmart | `BUILD SUCCEEDED` |
| Archipelago | `BUILD SUCCEEDED` |
| SLG Sync Plus | `BUILD SUCCEEDED` |
| SylSmart | `BUILD SUCCEEDED` |

共同出现工程既有 warning：

`Metadata extraction skipped. No AppIntents.framework dependency found.`

未发现可归因于本次改动的新 warning。

## 7. 文件范围

本次计划内 tracked code/test 改动：

- `SunSmart/Main/Space/Controller/SyncDevicesViewController.swift`
- `SunSmart/Main/Timed/Model/TimedSchedulerOwnerPolicy.swift`
- `Tests/Timed/TimedSchedulerOwnerPolicyTests.swift`

本次文档：

- `docs/260731_1409_timed_group_member_removal_resync_root_cause_analysis.md`
- `docs/260731_1438_timed_group_member_removal_scheduler_migration_design.md`
- `docs/260731_1445_timed_group_member_removal_scheduler_migration_implementation_plan.md`
- `docs/260731_1502_timed_group_member_removal_scheduler_migration_implementation_summary.md`

工作区同时存在不属于本次任务的 staged Device asset 和
`docs/260731_1449_pid_2057_group_members_icon_missing_analysis.md`，均已保留且未编辑。

本地 NordicSigMeshSDK 工作区存在此前的 Scheduler 缓存修复改动；本次实施未编辑 SDK。

## 8. 待真机验收

### 8.1 成功路径

需要验证：

- L2、L6 退组时 id 1、3 从 Light LC 清理并写入 ordinary；
- id 0、5 按既有逻辑删除；
- id 2、4 不产生无关 Scheduler 消息；
- 退组成功后 Timed 不新增待同步；
- 退出 Timed、退出 Space、杀进程重启后状态保持。

### 8.2 失败路径

需要通过真实不可达节点或可控 Mesh 故障验证：

- Schedule Owner 迁移 Step 显示失败；
- 后续 `unsubscribeGroup` 仍执行并完成退组；
- Sync Devices 最终显示失败；
- Timed 保留 `owner-entry-missing`、`owner-entry-mismatch` 或 `cleanup-entry-residual` 等真实待同步；
- 节点恢复后可通过既有同步入口修复。

### 8.3 Manual Control 对照

需要确认 Manual Control Group 的 Device Target `Turn On` 始终使用 ordinary Scheduler，不产生不必要的 ordinary 与 Light LC Owner 迁移。

## 9. Git 操作

未执行 Git commit、push 或 merge。
