# Timed Auto/On 按 Group Profile 路由 Scheduler 开发方案

> 状态：已确认并按方案 A 实施  
> 日期：2026-07-27  
> 范围：仅调整 `Auto/On` 的 Scheduler Owner 判定；保留既有 `Off`、`Scene Recall`、非 Owner 清理和全 Model 删除规则。

## 1. 目标规则

| 日程 Action | 设备最终 Group 状态 | Group Profile | Owner Scheduler |
| --- | --- | --- | --- |
| Auto/On | 已加入 Group | 非 `Manual control` | Light LC Scheduler |
| Auto/On | 未加入任何 Group | 不适用 | 普通 Scheduler |
| Auto/On | 已加入 Group | `Manual control` | 普通 Scheduler |
| Off | 任意 | 任意 | 普通 Scheduler |
| Scene Recall | 任意 | 任意 | 普通 Scheduler |

补充约束：

1. 双 Scheduler 设备按上表选择唯一 Owner。
2. 只有一个 Scheduler 的设备继续回退到唯一可用 Model。
3. 写入前清理所有非 Owner Scheduler 的同 index。
4. 删除日程时清理设备全部 Scheduler 的同 index。
5. `devices`、`groups`、`scenes` 只是日程 Target 类型，不直接决定 Owner；Owner 最终按每台设备的 Group/Profile 状态判断。

## 2. 当前问题与设计边界

当前实现仅根据 `SchedulerAction` 选择 Model：`Auto/On` 固定选 Light LC，缺少 App 层的 Group/Profile 业务信息。因此以下两类设备会被错误写入 Light LC Scheduler：

- 尚未加入任何 Group 的设备；
- 已加入 `Manual control` Profile Group 的设备。

`Profile.ProfileType` 和 `Group.info.profile` 位于 App 工程，SDK 的 `Node` 只能看到 Mesh Model 和订阅地址，不能可靠判断某个 Group 是否为 `Manual control`。因此不能把新的完整业务规则继续固化在 SDK 的 action-only 选择函数中。

此外，Owner 判定不仅影响写入，还影响：

- `Schedule.needsSync` 的同步判断；
- `schedulerActions` 兼容缓存的投影；
- 设备加入/移出 Group；
- Group Profile 在 `Manual control` 与其他 Profile 之间切换；
- Group Profile 同步页面是否出现定时任务。

这些路径必须共用同一项 Owner 结论，不能分别复制条件。

## 3. 方案比较

### 方案 A：App 统一业务策略，SDK 仅提供中性的 Model 能力（推荐）

在 App 的 Timed 模块集中定义 Owner 策略。策略读取：

- 日程逻辑 Action；
- 设备当前 Group；
- Group Profile；
- 必要时由“加入 Group”流程显式提供的目标 Group。

SDK 只负责：

- 枚举设备全部 Scheduler Setup Models；
- 返回普通 Scheduler 或 Light LC Scheduler；
- 根据 App 已确定的 Owner 返回非 Owner Models。

优点：

- Profile 业务留在拥有真实数据的 App 层；
- 写入、同步判断和缓存投影能复用同一策略；
- 不让 SDK 依赖 App 的 `Profile` 类型；
- 后续 Profile 切换可以自然触发 Owner 迁移。

代价：

- 需要把 Group 上下文传入少数“设备尚在加入 Group、但消息已经开始组装”的路径。

### 方案 B：只在 `Schedule.getMessageHandles` 内增加条件

优点是改动最少。

不采用的原因：

- `needsSync` 仍可能按旧 Owner 判断；
- 缓存投影仍会选择错误 Model；
- Group Profile 切换后可能不出现待同步任务；
- 加组、恢复、延迟同步等路径容易再次分叉。

### 方案 C：由每个调用点传入 `isManualControlGroup` 布尔值

显式但分散，调用点较多，容易漏传或传错；布尔值也无法表达“当前 Group”“目标 Group”“正在退出 Group”等状态。不推荐。

## 4. 推荐设计

### 4.1 App 层统一 Owner 策略

在现有 Timed Model 范围内新增集中策略，输出：

- Owner 类型：普通 Scheduler 或 Light LC Scheduler；
- 实际 Owner Model；
- 需要清理的非 Owner Models。

判定顺序：

1. `Off`、`Scene Recall`、`No Action` 始终请求普通 Scheduler；
2. `Auto/On` 获取设备的有效 Group；
3. 有效 Group 存在且 Profile 不是 `Manual control` 时请求 Light LC Scheduler；
4. 无有效 Group 或 Profile 为 `Manual control` 时请求普通 Scheduler；
5. 请求的 Model 不存在时，回退到设备唯一可用 Scheduler；
6. 设备没有 Scheduler 时不生成写入消息。

### 4.2 有效 Group 语义

默认使用设备当前真实 Group：

- 正常已入组设备：使用 `node.group`；
- 未入组设备：视为无 Group；
- 正在退出 Group、`groupState == .exitFailure`：视为无有效 Group。

加入 Group 或恢复设备时有一个特殊时序：消息在本地订阅状态更新前就已组装，但 Schedule 消息实际排在订阅消息之后发送。为保证首次加组完成后立即得到正确 Owner，这些流程应显式传入“目标 Group”作为最终状态上下文：

- 目标 Group 为非 `Manual control`：`Auto/On` 写 Light LC；
- 目标 Group 为 `Manual control`：`Auto/On` 写普通 Scheduler。

该上下文只服务于本次目标状态，不修改 `node.group`，也不扩展多 Group 业务模型。

### 4.3 SDK 边界

调整 SDK 新增的 action-only Owner helper，使其不再承担 Profile 业务决策：

- 保留“普通 Scheduler”“Light LC Scheduler”“全部 Scheduler Models”的能力；
- Model 选择接受 App 已解析出的 Owner 类型；
- 清理函数根据实际 Owner Model 返回其他 Models；
- SDK 自身无法获得 Profile 的公共 `setSchedule` 路径，采用无 Group 的保守语义：`Auto/On` 默认普通 Scheduler；
- SDK 的扁平 `schedulerActions` 缓存改为中性地保留任一 Model 上的有效 entry，不再用 action 猜测 Profile Owner。

App 的 Timed 逻辑继续以 `allSchedulerModelEntrys` 作为同步真值，并按 App 策略生成业务投影。

### 4.4 写入与删除

设置日程保持固定顺序：

1. 如有需要先设置 Time；
2. 向全部非 Owner Scheduler 写入同 index 的无效 entry；
3. 向 Owner Scheduler 写入目标 entry。

删除日程保持现状：

- 不依赖 Action、Group 或 Profile；
- 向设备全部 Scheduler Models 清理同 index。

## 5. 已有定时与 Group Profile 同步影响

本次调整不会主动扫描并立即改写所有既有设备，但在后续相关同步中会迁移到新 Owner：

- 非 `Manual control` Group 中，原本位于普通 Scheduler 的 `Auto/On` 会迁移到 Light LC；
- `Manual control` Group 或无 Group 设备中，原本位于 Light LC 的 `Auto/On` 会迁移到普通 Scheduler；
- Profile 从 `Manual control` 切换为其他类型，或反向切换时，Owner 变化会使相关 `Auto/On` 显示为待同步；
- 同步时先清理旧 Owner 同 index，再写新 Owner；
- `Off`、`Scene Recall` 不迁移，仍属于普通 Scheduler。

因此 Group Profile 修改后，“Group 需要同步，任务中包含定时任务”可能是预期结果：它代表 Auto/On Owner 需要随 Profile 迁移。同步完成后不应继续重复出现。

## 6. 实施步骤

### Task 1：先扩展回归契约，建立失败基线

修改：

- `Tests/Timed/TimedSchedulerSingleOwnerContractTests.swift`
- 必要时新增一个纯策略测试文件，并接入 `scripts/check_timed_scheduler_single_owner.sh`

覆盖矩阵：

1. Auto/On + 无 Group → 普通 Scheduler；
2. Auto/On + Manual control Group → 普通 Scheduler；
3. Auto/On + 非 Manual control Group → Light LC Scheduler；
4. Auto/On + 正在退出 Group → 普通 Scheduler；
5. Auto/On + 正在加入非 Manual control 目标 Group → Light LC Scheduler；
6. Auto/On + 正在加入 Manual control 目标 Group → 普通 Scheduler；
7. Off、Scene Recall 在所有 Group 状态下 → 普通 Scheduler；
8. 单 Model 设备 → 唯一 Model；
9. 设置前清理全部非 Owner 同 index；
10. 删除时清理全部 Scheduler 同 index；
11. Owner 缺失、非 Owner 仍有效或 Model 缓存未知时 → `needsSync == true`；
12. Group Profile 改变后 → Owner 变化并产生一次迁移同步。

先运行测试并确认新断言失败，再进入实现。

### Task 2：将 SDK Model 选择改为中性能力

修改：

- `../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+SupportModels.swift`
- `../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Node/Node+Messages.swift`
- `../../nordic-sig-mesh-sdk/Sources/NordicSigMeshSDK/MeshLib/Manager/MeshScheduleServer.swift`

工作项：

1. 用显式 Owner 类型替代 action-only Model 选择；
2. 清理 Models 以实际 Owner 为准；
3. SDK 兼容缓存不再自行推断 Group/Profile Owner；
4. SDK 无 Profile 上下文的公共写入路径采用普通 Scheduler 作为 Auto/On 默认值；
5. 保留单 Model fallback。

### Task 3：在 App Timed 层实现统一策略

修改：

- `SunSmart/Main/Timed/Model/Scheduler.swift`
- `SunSmart/Common/Data/Node+MessageHandles.swift`

工作项：

1. 定义 Owner 解析和有效 Group 上下文；
2. `Schedule.getMessageHandles` 通过统一策略选择 Owner；
3. 继续按“清理非 Owner → 写 Owner”的顺序生成消息；
4. 删除路径继续遍历全部 Scheduler Models；
5. 保持 TimeSet 行为不变。

优先放入现有 Timed Model 文件，避免为一个小型策略修改多个品牌 target 的文件归属；若实现时确有必要拆成新文件，再同步检查 `SunSmart`、`Archipelago`、`SLG Sync Plus`、`SylSmart` 的 Target Membership。

### Task 4：让同步判断和缓存投影复用同一策略

修改：

- `SunSmart/Common/Data/MeshNetwork+SunSmart.swift`
- `SunSmart/Common/Data/Node+SyncData.swift`

工作项：

1. `Schedule.needsSync` 使用与写入完全相同的 Owner；
2. 对非 Owner 同 index 的有效残留继续判定为待同步；
3. Model 缓存未知时保持保守待同步；
4. App 的 `rebuildTimedSchedulerActions` 使用同一 Group/Profile Owner；
5. Profile 或 Group 归属改变后清理同步状态缓存，并重建必要的 Timed 兼容投影。

### Task 5：补齐 Group 目标上下文

重点检查并修改：

- `SunSmart/Main/Device/Model/DeviceGroupDeferredSyncPlanner.swift`
- `SunSmart/Main/Group/Model/GroupServer.swift`
- `SunSmart/Main/Timed/Model/ScheduleServer.swift`
- `SunSmart/Main/Space/Model/SyncDevicesCellModel.swift`
- `SunSmart/Main/Device/Controller/DeviceRestoreViewController.swift`
- `SunSmart/Main/Site/Controller/SiteDeviceAddViewController.swift`
- `SunSmart/Main/Device/Device1.5/FireAlarm/Model/EmerFireAlarmSyncCellModel.swift`

工作项：

1. 正常设备/日程同步默认读取当前真实 Group；
2. 加组、Fast Add、恢复等“先组装、后订阅”的流程显式传入目标 Group；
3. 移出 Group 时不把退出中的 Group 当作有效 Auto Profile；
4. Group/Scene Target 分解到具体设备后，仍逐设备判定 Owner；
5. 删除路径不依赖上下文，继续全 Model 清理；
6. 避免把 Group 上下文扩散为大量布尔参数，集中在 Schedule 策略入口。

### Task 6：验证

按顺序执行：

1. `scripts/check_timed_scheduler_single_owner.sh`
2. `git diff --check`
3. 使用 generic iPhoneOS 构建 `SunSmart`
4. 使用 generic iPhoneOS 构建 `Archipelago`
5. 根据共享代码 Target Membership，再检查 `SLG Sync Plus`、`SylSmart` 是否需要构建

真机 Mesh 验收矩阵：

1. 双 Model、无 Group、Auto/On；
2. 双 Model、Manual control Group、Auto/On；
3. 双 Model、非 Manual control Group、Auto/On；
4. Manual control ↔ 非 Manual control Profile 双向切换；
5. 未入组设备加入两类 Profile Group；
6. 已入组设备移出 Group；
7. Off、Scene Recall 回归；
8. 编辑既有异常日程，确认旧 Owner 已清理；
9. 删除日程，确认两个 Scheduler 同 index 都无有效 entry；
10. 16 个 index 边界，确认不会因双 Model 残留表现为第 17 个日程。

## 7. 完成标准

1. Owner 矩阵与第 1 节完全一致；
2. 写入、同步判断和 App 缓存投影共用一个策略；
3. Profile 切换只产生必要的一次定时迁移，同步完成后不重复提示；
4. 非 Owner 不存在有效同 index；
5. 删除后全部 Scheduler Models 均无该 index；
6. 自动化契约、diff check 和相关 iPhoneOS 构建通过；
7. 自动化/构建结果与真机 Mesh 验收结果分开报告。

## 8. 待确认项

推荐按方案 A 实施，并采用以下语义：

- 设备加入 Group 的过程中，Schedule 写入按“加入完成后的目标 Group/Profile”选 Owner，而不是按消息组装瞬间尚未更新的 `node.group`；
- SDK 没有 App Profile 上下文的通用 `setSchedule`，Auto/On 采用普通 Scheduler 的保守默认；
- Profile 切换后出现定时同步任务属于预期迁移，不屏蔽该任务。

确认后按 Superpowers 的 Inline Execution 执行，先完成测试失败基线，再做最小实现与阶段性验证。
